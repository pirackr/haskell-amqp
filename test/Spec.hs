{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import Test.QuickCheck
import Data.Binary.Get (runGet, runGetOrFail)
import Data.Binary.Put (runPut)
import Data.ByteString.Lazy (ByteString)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString as BS
import Control.Exception (try, evaluate, ErrorCall)
import Data.Time.Clock.POSIX (POSIXTime)
import Data.UUID (UUID, fromWords)
import qualified Data.UUID as UUID
import Data.Text (Text)
import qualified Data.Text as T
import Data.Int (Int8, Int16, Int32, Int64)
import Data.Word (Word8, Word16, Word32, Word64)

import Network.AMQP.Types
import Network.AMQP.Transport

-- | Generate valid timestamp (positive POSIXTime from Word64)
-- Constrained to avoid overflow when converting to Int64 milliseconds
arbitraryTimestamp :: Gen POSIXTime
arbitraryTimestamp = do
  -- Max safe value: (2^63 - 1) milliseconds = 9223372036854775807 milliseconds
  -- In seconds: 9223372036854775.807 seconds
  -- To be safe, use a smaller max value to avoid edge cases
  millis <- choose (0, 9223372036854775 :: Int64)
  return $ fromIntegral millis / 1000.0  -- Convert to seconds

-- | Generate random UUID
arbitraryUUID :: Gen UUID
arbitraryUUID = do
  w1 <- arbitrary
  w2 <- arbitrary
  w3 <- arbitrary
  w4 <- arbitrary
  return $ fromWords w1 w2 w3 w4

-- | Generate ByteString
arbitraryByteString :: Gen BS.ByteString
arbitraryByteString = BS.pack <$> arbitrary

-- | Generate Text (ASCII subset for simplicity)
arbitraryText :: Gen Text
arbitraryText = T.pack <$> listOf (elements ['a'..'z'])

-- | Generate primitive AMQP values (no composites)
arbitraryPrimitive :: Gen AMQPValue
arbitraryPrimitive = oneof
  [ pure AMQPNull
  , AMQPBool <$> arbitrary
  , AMQPUByte <$> arbitrary
  , AMQPUShort <$> arbitrary
  , AMQPUInt <$> arbitrary
  , AMQPULong <$> arbitrary
  , AMQPByte <$> arbitrary
  , AMQPShort <$> arbitrary
  , AMQPInt <$> arbitrary
  , AMQPLong <$> arbitrary
  , AMQPFloat <$> arbitrary
  , AMQPDouble <$> arbitrary
  , AMQPTimestamp <$> arbitraryTimestamp
  , AMQPUuid <$> arbitraryUUID
  , AMQPBinary <$> arbitraryByteString
  , AMQPString <$> arbitraryText
  , AMQPSymbol <$> arbitraryText
  ]

-- | Arbitrary instances for primitive AMQP types
instance Arbitrary AMQPValue where
  arbitrary = arbitraryPrimitive

main :: IO ()
main = defaultMain tests

-- | QuickCheck property: roundtrip encoding/decoding
prop_roundtrip :: AMQPValue -> Property
prop_roundtrip val = roundtrip val === val
  where
    roundtrip v = runGet getAMQPValue (runPut (putAMQPValue v))

-- | Arbitrary Frame instance for QuickCheck
instance Arbitrary Frame where
  arbitrary = do
    ftype <- elements [AMQPFrameType, SASLFrameType]
    channel <- arbitrary
    -- Generate payload of reasonable size (0-1000 bytes)
    payloadLen <- choose (0, 1000)
    payload <- BS.pack <$> vectorOf payloadLen arbitrary
    return $ Frame ftype channel payload

-- | QuickCheck property: roundtrip encoding/decoding for frames
prop_frameRoundtrip :: Frame -> Property
prop_frameRoundtrip frame = roundtrip frame === frame
  where
    roundtrip f = runGet getFrame (runPut (putFrame f))

tests :: TestTree
tests = testGroup "AMQP Tests"
  [ testGroup "Frame Tests"
      [ testProperty "frame roundtrip" prop_frameRoundtrip
      , testCase "minimal AMQP frame" $
          let frame = Frame AMQPFrameType 0 BS.empty
              encoded = runPut (putFrame frame)
              decoded = runGet getFrame encoded
          in decoded @?= frame
      , testCase "SASL frame with payload" $
          let payload = BS.pack [0x01, 0x02, 0x03]
              frame = Frame SASLFrameType 42 payload
              encoded = runPut (putFrame frame)
              decoded = runGet getFrame encoded
          in decoded @?= frame
      , testCase "frame encoding format" $
          -- Frame: type=AMQP(0x00), channel=1, payload=[0xAA, 0xBB]
          -- SIZE: 10 bytes (8 header + 2 payload) = 0x0000000A
          -- DOFF: 2 (8 bytes header)
          -- TYPE: 0x00 (AMQP)
          -- CHANNEL: 0x0001
          -- PAYLOAD: 0xAA, 0xBB
          let frame = Frame AMQPFrameType 1 (BS.pack [0xAA, 0xBB])
          in runPut (putFrame frame) @?=
             LBS.pack [0x00, 0x00, 0x00, 0x0A,  -- SIZE
                       0x02,                      -- DOFF
                       0x00,                      -- TYPE
                       0x00, 0x01,                -- CHANNEL
                       0xAA, 0xBB]                -- PAYLOAD
      , testCase "incomplete frame - too small size" $
          -- Frame claims to be smaller than header size (8 bytes)
          let malformed = LBS.pack [0x00, 0x00, 0x00, 0x04,  -- SIZE = 4 (invalid)
                                    0x02, 0x00, 0x00, 0x00]
          in case runGetOrFail getFrame malformed of
               Left _ -> return ()  -- Expected to fail
               Right (_, _, _) -> assertFailure "Should have failed on invalid size"
      , testCase "incomplete frame - invalid DOFF" $
          -- DOFF < 2 is invalid
          let malformed = LBS.pack [0x00, 0x00, 0x00, 0x08,  -- SIZE
                                    0x01,                      -- DOFF = 1 (invalid)
                                    0x00, 0x00, 0x00]
          in case runGetOrFail getFrame malformed of
               Left _ -> return ()  -- Expected to fail
               Right (_, _, _) -> assertFailure "Should have failed on invalid DOFF"
      , testCase "incomplete frame - unknown type" $
          -- TYPE = 0xFF is not defined
          let malformed = LBS.pack [0x00, 0x00, 0x00, 0x08,  -- SIZE
                                    0x02,                      -- DOFF
                                    0xFF,                      -- TYPE = 0xFF (invalid)
                                    0x00, 0x00]
          in case runGetOrFail getFrame malformed of
               Left _ -> return ()  -- Expected to fail
               Right (_, _, _) -> assertFailure "Should have failed on unknown frame type"
      ]
  , testGroup "QuickCheck Roundtrip Tests"
      [ testProperty "null roundtrip" $ \() ->
          prop_roundtrip AMQPNull
      , testProperty "bool roundtrip" $ \b ->
          prop_roundtrip (AMQPBool b)
      , testProperty "ubyte roundtrip" $ \(w :: Word8) ->
          prop_roundtrip (AMQPUByte w)
      , testProperty "ushort roundtrip" $ \(w :: Word16) ->
          prop_roundtrip (AMQPUShort w)
      , testProperty "uint roundtrip" $ \(w :: Word32) ->
          prop_roundtrip (AMQPUInt w)
      , testProperty "ulong roundtrip" $ \(w :: Word64) ->
          prop_roundtrip (AMQPULong w)
      , testProperty "byte roundtrip" $ \(i :: Int8) ->
          prop_roundtrip (AMQPByte i)
      , testProperty "short roundtrip" $ \(i :: Int16) ->
          prop_roundtrip (AMQPShort i)
      , testProperty "int roundtrip" $ \(i :: Int32) ->
          prop_roundtrip (AMQPInt i)
      , testProperty "long roundtrip" $ \(i :: Int64) ->
          prop_roundtrip (AMQPLong i)
      , testProperty "float roundtrip" $ \f ->
          -- Skip NaN values as they don't equal themselves
          not (isNaN f) ==> prop_roundtrip (AMQPFloat f)
      , testProperty "double roundtrip" $ \d ->
          -- Skip NaN values as they don't equal themselves
          not (isNaN d) ==> prop_roundtrip (AMQPDouble d)
      , testProperty "timestamp roundtrip" $ \(w :: Word64) ->
          -- Generate timestamp from Word64, but constrain to avoid overflow
          -- when converting to Int64 milliseconds (max safe value is 2^63 - 1 milliseconds)
          let maxSafeMillis = 9223372036854775807 :: Word64  -- 2^63 - 1
              safew = w `mod` maxSafeMillis
              t = fromIntegral safew / 1000.0 :: POSIXTime
          in prop_roundtrip (AMQPTimestamp t)
      , testProperty "uuid roundtrip" $ \w1 w2 w3 w4 ->
          let uuid = fromWords w1 w2 w3 w4
          in prop_roundtrip (AMQPUuid uuid)
      , testProperty "binary roundtrip" $ \bs ->
          prop_roundtrip (AMQPBinary (BS.pack bs))
      , testProperty "string roundtrip" $ \s ->
          -- Use ASCII subset for safety
          let text = T.pack (filter (\c -> c >= ' ' && c <= '~') s)
          in prop_roundtrip (AMQPString text)
      , testProperty "symbol roundtrip" $ \s ->
          -- Use ASCII subset for safety
          let text = T.pack (filter (\c -> c >= ' ' && c <= '~') s)
          in prop_roundtrip (AMQPSymbol text)
      , testProperty "empty list roundtrip" $ \() ->
          prop_roundtrip (AMQPList [])
      , testProperty "list with primitives roundtrip" $
          -- Use small lists with primitive types only (avoid recursion for now)
          forAll (listOf1 arbitraryPrimitive) $ \items ->
            prop_roundtrip (AMQPList items)
      , testProperty "empty map roundtrip" $ \() ->
          prop_roundtrip (AMQPMap [])
      , testProperty "map with primitives roundtrip" $
          -- Use small maps with primitive types only
          forAll (listOf1 ((,) <$> arbitraryPrimitive <*> arbitraryPrimitive)) $ \pairs ->
            prop_roundtrip (AMQPMap pairs)
      , testProperty "empty array roundtrip" $ \() ->
          prop_roundtrip (AMQPArray [])
      , testProperty "array with primitives roundtrip" $
          -- Use small arrays with primitive types only
          forAll (listOf1 arbitraryPrimitive) $ \items ->
            prop_roundtrip (AMQPArray items)
      ]
  , testGroup "Nested Structures Tests"
      [ testCase "nested list (list containing list)" $
          let nested = AMQPList [AMQPNull, AMQPList [AMQPBool True, AMQPBool False], AMQPUInt 42]
              roundtripped = runGet getAMQPValue (runPut (putAMQPValue nested))
          in roundtripped @?= nested
      , testCase "nested map (map with list value)" $
          let nested = AMQPMap [(AMQPString "key", AMQPList [AMQPInt 1, AMQPInt 2])]
              roundtripped = runGet getAMQPValue (runPut (putAMQPValue nested))
          in roundtripped @?= nested
      , testCase "list containing map" $
          let nested = AMQPList [AMQPMap [(AMQPString "a", AMQPInt 1)], AMQPNull]
              roundtripped = runGet getAMQPValue (runPut (putAMQPValue nested))
          in roundtripped @?= nested
      , testCase "deeply nested list" $
          let nested = AMQPList [AMQPList [AMQPList [AMQPNull]]]
              roundtripped = runGet getAMQPValue (runPut (putAMQPValue nested))
          in roundtripped @?= nested
      , testCase "array containing primitives of same type" $
          let arr = AMQPArray [AMQPInt 1, AMQPInt 2, AMQPInt 3]
              roundtripped = runGet getAMQPValue (runPut (putAMQPValue arr))
          in roundtripped @?= arr
      ]
  , testGroup "Described Types Tests"
      [ testCase "described type with ulong descriptor" $
          let described = AMQPDescribed (AMQPULong 0x00) (AMQPString "test")
              roundtripped = runGet getAMQPValue (runPut (putAMQPValue described))
          in roundtripped @?= described
      , testCase "described type with symbol descriptor" $
          let described = AMQPDescribed (AMQPSymbol "amqp:message") (AMQPList [AMQPNull])
              roundtripped = runGet getAMQPValue (runPut (putAMQPValue described))
          in roundtripped @?= described
      , testCase "described type encoding format" $
          -- descriptor: ulong 0 (0x44), value: null (0x40)
          let described = AMQPDescribed (AMQPULong 0) AMQPNull
          in runPut (putAMQPValue described) @?= LBS.pack [0x00, 0x44, 0x40]
      , testProperty "described type roundtrip" $
          forAll arbitraryPrimitive $ \desc ->
          forAll arbitraryPrimitive $ \val ->
            let described = AMQPDescribed desc val
            in prop_roundtrip described
      ]
  , testGroup "Decoding"
      [ testCase "0x40 decodes to null" $
          runGet getAMQPValue (LBS.pack [0x40]) @?= AMQPNull
      ]
  , testGroup "Encoding"
      [ testCase "null encodes to 0x40" $
          runPut (putAMQPValue AMQPNull) @?= LBS.pack [0x40]
      , testCase "true encodes to 0x41" $
          runPut (putAMQPValue (AMQPBool True)) @?= LBS.pack [0x41]
      , testCase "false encodes to 0x42" $
          runPut (putAMQPValue (AMQPBool False)) @?= LBS.pack [0x42]
      -- ubyte: 0x50 + 1 byte
      , testCase "ubyte encodes to 0x50 + byte" $
          runPut (putAMQPValue (AMQPUByte 42)) @?= LBS.pack [0x50, 42]
      -- ushort: 0x60 + 2 bytes BE
      , testCase "ushort encodes to 0x60 + 2 bytes" $
          runPut (putAMQPValue (AMQPUShort 0x0102)) @?= LBS.pack [0x60, 0x01, 0x02]
      -- uint: 0x43 (zero), 0x52 + 1 byte (small), 0x70 + 4 bytes (large)
      , testCase "uint 0 encodes to uint0 (0x43)" $
          runPut (putAMQPValue (AMQPUInt 0)) @?= LBS.pack [0x43]
      , testCase "uint small value encodes to smalluint (0x52)" $
          runPut (putAMQPValue (AMQPUInt 255)) @?= LBS.pack [0x52, 0xFF]
      , testCase "uint large value encodes to full (0x70)" $
          runPut (putAMQPValue (AMQPUInt 256)) @?= LBS.pack [0x70, 0x00, 0x00, 0x01, 0x00]
      -- ulong: 0x44 (zero), 0x53 + 1 byte (small), 0x80 + 8 bytes (large)
      , testCase "ulong 0 encodes to ulong0 (0x44)" $
          runPut (putAMQPValue (AMQPULong 0)) @?= LBS.pack [0x44]
      , testCase "ulong small value encodes to smallulong (0x53)" $
          runPut (putAMQPValue (AMQPULong 255)) @?= LBS.pack [0x53, 0xFF]
      , testCase "ulong large value encodes to full (0x80)" $
          runPut (putAMQPValue (AMQPULong 256)) @?= LBS.pack [0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00]
      -- byte: 0x51 + 1 signed byte
      , testCase "byte encodes to 0x51 + byte" $
          runPut (putAMQPValue (AMQPByte (-1))) @?= LBS.pack [0x51, 0xFF]
      -- short: 0x61 + 2 bytes BE signed
      , testCase "short encodes to 0x61 + 2 bytes" $
          runPut (putAMQPValue (AMQPShort (-1))) @?= LBS.pack [0x61, 0xFF, 0xFF]
      -- int: 0x54 + 1 byte (small), 0x71 + 4 bytes (large)
      , testCase "int small positive encodes to smallint (0x54)" $
          runPut (putAMQPValue (AMQPInt 127)) @?= LBS.pack [0x54, 0x7F]
      , testCase "int small negative encodes to smallint (0x54)" $
          runPut (putAMQPValue (AMQPInt (-128))) @?= LBS.pack [0x54, 0x80]
      , testCase "int large value encodes to full (0x71)" $
          runPut (putAMQPValue (AMQPInt 128)) @?= LBS.pack [0x71, 0x00, 0x00, 0x00, 0x80]
      -- long: 0x55 + 1 byte (small), 0x81 + 8 bytes (large)
      , testCase "long small positive encodes to smalllong (0x55)" $
          runPut (putAMQPValue (AMQPLong 127)) @?= LBS.pack [0x55, 0x7F]
      , testCase "long small negative encodes to smalllong (0x55)" $
          runPut (putAMQPValue (AMQPLong (-128))) @?= LBS.pack [0x55, 0x80]
      , testCase "long large value encodes to full (0x81)" $
          runPut (putAMQPValue (AMQPLong 128)) @?= LBS.pack [0x81, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80]
      -- string: 0xa1 + 1 byte length (str8), 0xb1 + 4 byte length (str32)
      , testCase "string empty encodes to str8 (0xa1)" $
          runPut (putAMQPValue (AMQPString "")) @?= LBS.pack [0xa1, 0x00]
      , testCase "string short encodes to str8 (0xa1)" $
          runPut (putAMQPValue (AMQPString "hello")) @?= LBS.pack ([0xa1, 0x05] ++ [0x68, 0x65, 0x6c, 0x6c, 0x6f])
      , testCase "string UTF-8 encodes correctly" $
          -- Unicode codepoint U+4E2D (Chinese character for "middle") encodes to 3 UTF-8 bytes: E4 B8 AD
          runPut (putAMQPValue (AMQPString "\x4E2D")) @?= LBS.pack [0xa1, 0x03, 0xe4, 0xb8, 0xad]
      -- symbol: 0xa3 + 1 byte length (sym8), 0xb3 + 4 byte length (sym32)
      , testCase "symbol empty encodes to sym8 (0xa3)" $
          runPut (putAMQPValue (AMQPSymbol "")) @?= LBS.pack [0xa3, 0x00]
      , testCase "symbol short encodes to sym8 (0xa3)" $
          runPut (putAMQPValue (AMQPSymbol "amqp")) @?= LBS.pack ([0xa3, 0x04] ++ [0x61, 0x6d, 0x71, 0x70])
      -- binary: 0xa0 + 1 byte length (vbin8), 0xb0 + 4 byte length (vbin32)
      , testCase "binary empty encodes to vbin8 (0xa0)" $
          runPut (putAMQPValue (AMQPBinary "")) @?= LBS.pack [0xa0, 0x00]
      , testCase "binary short encodes to vbin8 (0xa0)" $
          runPut (putAMQPValue (AMQPBinary "\x01\x02\x03")) @?= LBS.pack [0xa0, 0x03, 0x01, 0x02, 0x03]
      -- uuid: 0x98 + 16 bytes
      , testCase "uuid encodes to 0x98 + 16 bytes" $
          -- UUID: 00112233-4455-6677-8899-aabbccddeeff
          let uuid = fromWords 0x00112233 0x44556677 0x8899aabb 0xccddeeff
          in runPut (putAMQPValue (AMQPUuid uuid)) @?=
             LBS.pack [0x98, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
                       0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]
      -- timestamp: 0x83 + 8 bytes (milliseconds since epoch)
      , testCase "timestamp encodes to 0x83 + 8 bytes" $
          -- 1000 seconds = 1000000 milliseconds = 0x00000000000F4240
          runPut (putAMQPValue (AMQPTimestamp 1000)) @?=
            LBS.pack [0x83, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0F, 0x42, 0x40]
      -- float: 0x72 + 4 bytes IEEE 754
      , testCase "float encodes to 0x72 + 4 bytes" $
          -- 1.0 in IEEE 754 single precision is 0x3F800000
          runPut (putAMQPValue (AMQPFloat 1.0)) @?= LBS.pack [0x72, 0x3F, 0x80, 0x00, 0x00]
      -- double: 0x82 + 8 bytes IEEE 754
      , testCase "double encodes to 0x82 + 8 bytes" $
          -- 1.0 in IEEE 754 double precision is 0x3FF0000000000000
          runPut (putAMQPValue (AMQPDouble 1.0)) @?= LBS.pack [0x82, 0x3F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
      -- list: 0x45 (empty), 0xc0 (list8), 0xd0 (list32)
      , testCase "empty list encodes to list0 (0x45)" $
          runPut (putAMQPValue (AMQPList [])) @?= LBS.pack [0x45]
      , testCase "list with null encodes to list8 (0xc0)" $
          -- list8: 0xc0 + size(1 byte) + count(1 byte) + items
          -- items: [null=0x40]
          -- size = 1 (count byte) + 1 (null byte) = 2, but size includes count so size = 1 + items_size = 1 + 1 = 2
          runPut (putAMQPValue (AMQPList [AMQPNull])) @?= LBS.pack [0xc0, 0x02, 0x01, 0x40]
      , testCase "list with mixed types encodes to list8 (0xc0)" $
          -- list8: 0xc0 + size + count + [null, true, uint0]
          -- items: [0x40, 0x41, 0x43] = 3 bytes
          -- size = 1 (count byte) + 3 (items) = 4
          runPut (putAMQPValue (AMQPList [AMQPNull, AMQPBool True, AMQPUInt 0])) @?=
            LBS.pack [0xc0, 0x04, 0x03, 0x40, 0x41, 0x43]
      -- map: 0xc1 (map8), 0xd1 (map32)
      , testCase "empty map encodes to map8 (0xc1)" $
          -- map8: 0xc1 + size(1 byte) + count(1 byte)
          -- size = 1 (count byte), count = 0
          runPut (putAMQPValue (AMQPMap [])) @?= LBS.pack [0xc1, 0x01, 0x00]
      , testCase "map with one pair encodes to map8 (0xc1)" $
          -- map8: 0xc1 + size + count + pairs
          -- pairs: [(true, false)] = [0x41, 0x42] = 2 bytes
          -- count = 2 (number of elements, not pairs)
          -- size = 1 (count byte) + 2 (pairs) = 3
          runPut (putAMQPValue (AMQPMap [(AMQPBool True, AMQPBool False)])) @?=
            LBS.pack [0xc1, 0x03, 0x02, 0x41, 0x42]
      -- array: 0xe0 (array8), 0xf0 (array32)
      , testCase "empty array encodes to array8 (0xe0)" $
          -- array8: 0xe0 + size(1 byte) + count(1 byte)
          -- size = 1 (count byte), count = 0
          runPut (putAMQPValue (AMQPArray [])) @?= LBS.pack [0xe0, 0x01, 0x00]
      , testCase "array with nulls encodes to array8 (0xe0)" $
          -- array8: 0xe0 + size + count + items
          -- items: [null, null] = [0x40, 0x40] = 2 bytes
          -- size = 1 (count byte) + 2 (items) = 3
          runPut (putAMQPValue (AMQPArray [AMQPNull, AMQPNull])) @?=
            LBS.pack [0xe0, 0x03, 0x02, 0x40, 0x40]
      ]
  ]
