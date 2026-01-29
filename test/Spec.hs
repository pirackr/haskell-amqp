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

-- -----------------------------------------------------------------------------
-- Test Helpers and Utilities
-- -----------------------------------------------------------------------------

-- | Test that a value roundtrips successfully through encoding and decoding
roundtripValue :: AMQPValue -> AMQPValue
roundtripValue v = runGet getAMQPValue (runPut (putAMQPValue v))

-- | Test that a frame roundtrips successfully through encoding and decoding
roundtripFrame :: Frame -> Frame
roundtripFrame f = runGet getFrame (runPut (putFrame f))

-- | QuickCheck property: verify value roundtrip equality
prop_valueRoundtrip :: AMQPValue -> Property
prop_valueRoundtrip val = roundtripValue val === val

-- | QuickCheck property: verify frame roundtrip equality
prop_frameRoundtrip :: Frame -> Property
prop_frameRoundtrip frame = roundtripFrame frame === frame

-- -----------------------------------------------------------------------------
-- QuickCheck Generators
-- -----------------------------------------------------------------------------

-- | Generate a valid POSIX timestamp
-- Constrained to avoid overflow when converting to Int64 milliseconds.
-- Max safe value is 2^63 - 1 milliseconds.
genTimestamp :: Gen POSIXTime
genTimestamp = do
  millis <- choose (0, 9223372036854775 :: Int64)
  return $ fromIntegral millis / 1000.0

-- | Generate a random UUID from four Word32 values
genUUID :: Gen UUID
genUUID = fromWords <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary

-- | Generate a random ByteString
genByteString :: Gen BS.ByteString
genByteString = BS.pack <$> arbitrary

-- | Generate random ASCII text (lowercase letters)
genText :: Gen Text
genText = T.pack <$> listOf (elements ['a'..'z'])

-- | Generate primitive AMQP values only (no composite types)
-- This is useful for testing without recursion complexity
genPrimitive :: Gen AMQPValue
genPrimitive = oneof
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
  , AMQPTimestamp <$> genTimestamp
  , AMQPUuid <$> genUUID
  , AMQPBinary <$> genByteString
  , AMQPString <$> genText
  , AMQPSymbol <$> genText
  ]

-- | Default Arbitrary instance for AMQPValue (primitives only)
instance Arbitrary AMQPValue where
  arbitrary = genPrimitive

-- | Arbitrary instance for Frame with reasonable payload sizes
instance Arbitrary Frame where
  arbitrary = do
    ftype <- elements [AMQPFrameType, SASLFrameType]
    channel <- arbitrary
    payloadLen <- choose (0, 1000)
    payload <- BS.pack <$> vectorOf payloadLen arbitrary
    return $ Frame ftype channel payload

-- -----------------------------------------------------------------------------
-- Main Test Entry Point
-- -----------------------------------------------------------------------------

main :: IO ()
main = defaultMain tests

-- -----------------------------------------------------------------------------
-- Test Suite
-- -----------------------------------------------------------------------------

tests :: TestTree
tests = testGroup "AMQP Tests"
  [ frameTests
  , primitiveTypeRoundtripTests
  , compositeTypeRoundtripTests
  , nestedStructureTests
  , describedTypeTests
  , encodingFormatTests
  , decodingFormatTests
  ]

-- -----------------------------------------------------------------------------
-- Frame Layer Tests
-- -----------------------------------------------------------------------------

frameTests :: TestTree
frameTests = testGroup "Frame Layer"
  [ testGroup "Roundtrip Tests"
      [ testProperty "arbitrary frame roundtrip" prop_frameRoundtrip
      , testCase "minimal AMQP frame" $
          let frame = Frame AMQPFrameType 0 BS.empty
          in roundtripFrame frame @?= frame
      , testCase "SASL frame with payload" $
          let frame = Frame SASLFrameType 42 (BS.pack [0x01, 0x02, 0x03])
          in roundtripFrame frame @?= frame
      ]
  , testGroup "Encoding Format"
      [ testCase "AMQP frame with payload" $
          -- Frame structure: SIZE (4) | DOFF (1) | TYPE (1) | CHANNEL (2) | PAYLOAD
          let frame = Frame AMQPFrameType 1 (BS.pack [0xAA, 0xBB])
          in runPut (putFrame frame) @?=
             LBS.pack [ 0x00, 0x00, 0x00, 0x0A  -- SIZE: 10 bytes total
                      , 0x02                      -- DOFF: 2 (8 byte header / 4)
                      , 0x00                      -- TYPE: AMQP
                      , 0x00, 0x01                -- CHANNEL: 1
                      , 0xAA, 0xBB                -- PAYLOAD
                      ]
      ]
  , testGroup "Error Handling"
      [ testCase "reject frame with size smaller than header" $
          let malformed = LBS.pack [0x00, 0x00, 0x00, 0x04, 0x02, 0x00, 0x00, 0x00]
          in case runGetOrFail getFrame malformed of
               Left _ -> return ()
               Right _ -> assertFailure "Should reject size < 8"
      , testCase "reject frame with DOFF < 2" $
          let malformed = LBS.pack [0x00, 0x00, 0x00, 0x08, 0x01, 0x00, 0x00, 0x00]
          in case runGetOrFail getFrame malformed of
               Left _ -> return ()
               Right _ -> assertFailure "Should reject DOFF < 2"
      , testCase "reject frame with unknown type" $
          let malformed = LBS.pack [0x00, 0x00, 0x00, 0x08, 0x02, 0xFF, 0x00, 0x00]
          in case runGetOrFail getFrame malformed of
               Left _ -> return ()
               Right _ -> assertFailure "Should reject unknown frame type"
      ]
  ]
-- -----------------------------------------------------------------------------
-- Primitive Type Roundtrip Tests
-- -----------------------------------------------------------------------------

primitiveTypeRoundtripTests :: TestTree
primitiveTypeRoundtripTests = testGroup "Primitive Type Roundtrips"
  [ testGroup "Fixed-Width Types"
      [ testProperty "null" $ \() -> prop_valueRoundtrip AMQPNull
      , testProperty "bool" $ \b -> prop_valueRoundtrip (AMQPBool b)
      , testProperty "ubyte" $ \(w :: Word8) -> prop_valueRoundtrip (AMQPUByte w)
      , testProperty "ushort" $ \(w :: Word16) -> prop_valueRoundtrip (AMQPUShort w)
      , testProperty "uint" $ \(w :: Word32) -> prop_valueRoundtrip (AMQPUInt w)
      , testProperty "ulong" $ \(w :: Word64) -> prop_valueRoundtrip (AMQPULong w)
      , testProperty "byte" $ \(i :: Int8) -> prop_valueRoundtrip (AMQPByte i)
      , testProperty "short" $ \(i :: Int16) -> prop_valueRoundtrip (AMQPShort i)
      , testProperty "int" $ \(i :: Int32) -> prop_valueRoundtrip (AMQPInt i)
      , testProperty "long" $ \(i :: Int64) -> prop_valueRoundtrip (AMQPLong i)
      , testProperty "float" $ \f ->
          not (isNaN f) ==> prop_valueRoundtrip (AMQPFloat f)
      , testProperty "double" $ \d ->
          not (isNaN d) ==> prop_valueRoundtrip (AMQPDouble d)
      ]
  , testGroup "Variable-Width Types"
      [ testProperty "binary" $ \bs ->
          prop_valueRoundtrip (AMQPBinary (BS.pack bs))
      , testProperty "string" $ \s ->
          let text = T.pack (filter (\c -> c >= ' ' && c <= '~') s)
          in prop_valueRoundtrip (AMQPString text)
      , testProperty "symbol" $ \s ->
          let text = T.pack (filter (\c -> c >= ' ' && c <= '~') s)
          in prop_valueRoundtrip (AMQPSymbol text)
      ]
  , testGroup "Temporal Types"
      [ testProperty "timestamp" $ \(w :: Word64) ->
          let maxSafeMillis = 9223372036854775807 :: Word64
              safew = w `mod` maxSafeMillis
              t = fromIntegral safew / 1000.0 :: POSIXTime
          in prop_valueRoundtrip (AMQPTimestamp t)
      ]
  , testGroup "Identifier Types"
      [ testProperty "uuid" $ \w1 w2 w3 w4 ->
          let uuid = fromWords w1 w2 w3 w4
          in prop_valueRoundtrip (AMQPUuid uuid)
      ]
  ]

-- -----------------------------------------------------------------------------
-- Composite Type Roundtrip Tests
-- -----------------------------------------------------------------------------

compositeTypeRoundtripTests :: TestTree
compositeTypeRoundtripTests = testGroup "Composite Type Roundtrips"
  [ testGroup "List"
      [ testProperty "empty list" $ \() ->
          prop_valueRoundtrip (AMQPList [])
      , testProperty "list with primitives" $
          forAll (listOf1 genPrimitive) $ \items ->
            prop_valueRoundtrip (AMQPList items)
      ]
  , testGroup "Map"
      [ testProperty "empty map" $ \() ->
          prop_valueRoundtrip (AMQPMap [])
      , testProperty "map with primitives" $
          forAll (listOf1 ((,) <$> genPrimitive <*> genPrimitive)) $ \pairs ->
            prop_valueRoundtrip (AMQPMap pairs)
      ]
  , testGroup "Array"
      [ testProperty "empty array" $ \() ->
          prop_valueRoundtrip (AMQPArray [])
      , testProperty "array with primitives" $
          forAll (listOf1 genPrimitive) $ \items ->
            prop_valueRoundtrip (AMQPArray items)
      ]
  ]
-- -----------------------------------------------------------------------------
-- Nested Structure Tests
-- -----------------------------------------------------------------------------

nestedStructureTests :: TestTree
nestedStructureTests = testGroup "Nested Structures"
  [ testCase "list containing list" $
      let nested = AMQPList [AMQPNull, AMQPList [AMQPBool True, AMQPBool False], AMQPUInt 42]
      in roundtripValue nested @?= nested
  , testCase "map with list value" $
      let nested = AMQPMap [(AMQPString "key", AMQPList [AMQPInt 1, AMQPInt 2])]
      in roundtripValue nested @?= nested
  , testCase "list containing map" $
      let nested = AMQPList [AMQPMap [(AMQPString "a", AMQPInt 1)], AMQPNull]
      in roundtripValue nested @?= nested
  , testCase "deeply nested list (3 levels)" $
      let nested = AMQPList [AMQPList [AMQPList [AMQPNull]]]
      in roundtripValue nested @?= nested
  , testCase "array with homogeneous elements" $
      let arr = AMQPArray [AMQPInt 1, AMQPInt 2, AMQPInt 3]
      in roundtripValue arr @?= arr
  ]

-- -----------------------------------------------------------------------------
-- Described Type Tests
-- -----------------------------------------------------------------------------

describedTypeTests :: TestTree
describedTypeTests = testGroup "Described Types"
  [ testGroup "Roundtrip Tests"
      [ testCase "ulong descriptor with string value" $
          let described = AMQPDescribed (AMQPULong 0x00) (AMQPString "test")
          in roundtripValue described @?= described
      , testCase "symbol descriptor with list value" $
          let described = AMQPDescribed (AMQPSymbol "amqp:message") (AMQPList [AMQPNull])
          in roundtripValue described @?= described
      , testProperty "arbitrary primitive descriptor and value" $
          forAll genPrimitive $ \desc ->
          forAll genPrimitive $ \val ->
            let described = AMQPDescribed desc val
            in prop_valueRoundtrip described
      ]
  , testGroup "Encoding Format"
      [ testCase "descriptor marker followed by descriptor and value" $
          -- Format: 0x00 (descriptor marker) | descriptor | value
          let described = AMQPDescribed (AMQPULong 0) AMQPNull
          in runPut (putAMQPValue described) @?= LBS.pack [0x00, 0x44, 0x40]
      ]
  ]

-- -----------------------------------------------------------------------------
-- Decoding Format Tests
-- -----------------------------------------------------------------------------

decodingFormatTests :: TestTree
decodingFormatTests = testGroup "Decoding Format"
  [ testCase "0x40 decodes to null" $
      runGet getAMQPValue (LBS.pack [0x40]) @?= AMQPNull
  ]
-- -----------------------------------------------------------------------------
-- Encoding Format Tests
-- These tests verify exact binary encoding per AMQP 1.0 specification
-- -----------------------------------------------------------------------------

encodingFormatTests :: TestTree
encodingFormatTests = testGroup "Encoding Format"
  [ fixedWidthEncodingTests
  , variableWidthEncodingTests
  , compositeEncodingTests
  ]

-- Test encoding of fixed-width primitive types
fixedWidthEncodingTests :: TestTree
fixedWidthEncodingTests = testGroup "Fixed-Width Types"
  [ testGroup "Boolean and Null"
      [ testCase "null -> 0x40" $
          runPut (putAMQPValue AMQPNull) @?= LBS.pack [0x40]
      , testCase "true -> 0x41" $
          runPut (putAMQPValue (AMQPBool True)) @?= LBS.pack [0x41]
      , testCase "false -> 0x42" $
          runPut (putAMQPValue (AMQPBool False)) @?= LBS.pack [0x42]
      ]
  , testGroup "Unsigned Integers"
      [ testCase "ubyte -> 0x50 + 1 byte" $
          runPut (putAMQPValue (AMQPUByte 42)) @?= LBS.pack [0x50, 42]
      , testCase "ushort -> 0x60 + 2 bytes (BE)" $
          runPut (putAMQPValue (AMQPUShort 0x0102)) @?= LBS.pack [0x60, 0x01, 0x02]
      , testGroup "uint (compact encoding)"
          [ testCase "uint(0) -> 0x43" $
              runPut (putAMQPValue (AMQPUInt 0)) @?= LBS.pack [0x43]
          , testCase "uint(255) -> 0x52 + 1 byte" $
              runPut (putAMQPValue (AMQPUInt 255)) @?= LBS.pack [0x52, 0xFF]
          , testCase "uint(256) -> 0x70 + 4 bytes" $
              runPut (putAMQPValue (AMQPUInt 256)) @?= LBS.pack [0x70, 0x00, 0x00, 0x01, 0x00]
          ]
      , testGroup "ulong (compact encoding)"
          [ testCase "ulong(0) -> 0x44" $
              runPut (putAMQPValue (AMQPULong 0)) @?= LBS.pack [0x44]
          , testCase "ulong(255) -> 0x53 + 1 byte" $
              runPut (putAMQPValue (AMQPULong 255)) @?= LBS.pack [0x53, 0xFF]
          , testCase "ulong(256) -> 0x80 + 8 bytes" $
              runPut (putAMQPValue (AMQPULong 256)) @?=
                LBS.pack [0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00]
          ]
      ]
  , testGroup "Signed Integers"
      [ testCase "byte -> 0x51 + 1 byte" $
          runPut (putAMQPValue (AMQPByte (-1))) @?= LBS.pack [0x51, 0xFF]
      , testCase "short -> 0x61 + 2 bytes (BE)" $
          runPut (putAMQPValue (AMQPShort (-1))) @?= LBS.pack [0x61, 0xFF, 0xFF]
      , testGroup "int (compact encoding)"
          [ testCase "int(127) -> 0x54 + 1 byte" $
              runPut (putAMQPValue (AMQPInt 127)) @?= LBS.pack [0x54, 0x7F]
          , testCase "int(-128) -> 0x54 + 1 byte" $
              runPut (putAMQPValue (AMQPInt (-128))) @?= LBS.pack [0x54, 0x80]
          , testCase "int(128) -> 0x71 + 4 bytes" $
              runPut (putAMQPValue (AMQPInt 128)) @?= LBS.pack [0x71, 0x00, 0x00, 0x00, 0x80]
          ]
      , testGroup "long (compact encoding)"
          [ testCase "long(127) -> 0x55 + 1 byte" $
              runPut (putAMQPValue (AMQPLong 127)) @?= LBS.pack [0x55, 0x7F]
          , testCase "long(-128) -> 0x55 + 1 byte" $
              runPut (putAMQPValue (AMQPLong (-128))) @?= LBS.pack [0x55, 0x80]
          , testCase "long(128) -> 0x81 + 8 bytes" $
              runPut (putAMQPValue (AMQPLong 128)) @?=
                LBS.pack [0x81, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80]
          ]
      ]
  , testGroup "Floating Point"
      [ testCase "float(1.0) -> 0x72 + 4 bytes IEEE 754" $
          runPut (putAMQPValue (AMQPFloat 1.0)) @?= LBS.pack [0x72, 0x3F, 0x80, 0x00, 0x00]
      , testCase "double(1.0) -> 0x82 + 8 bytes IEEE 754" $
          runPut (putAMQPValue (AMQPDouble 1.0)) @?=
            LBS.pack [0x82, 0x3F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
      ]
  , testGroup "Temporal and Identifier"
      [ testCase "timestamp -> 0x83 + 8 bytes (milliseconds)" $
          runPut (putAMQPValue (AMQPTimestamp 1000)) @?=
            LBS.pack [0x83, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0F, 0x42, 0x40]
      , testCase "uuid -> 0x98 + 16 bytes" $
          let uuid = fromWords 0x00112233 0x44556677 0x8899aabb 0xccddeeff
          in runPut (putAMQPValue (AMQPUuid uuid)) @?=
             LBS.pack [0x98, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
                       0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]
      ]
  ]

-- Test encoding of variable-width types
variableWidthEncodingTests :: TestTree
variableWidthEncodingTests = testGroup "Variable-Width Types"
  [ testGroup "Binary"
      [ testCase "empty binary -> vbin8 (0xa0)" $
          runPut (putAMQPValue (AMQPBinary "")) @?= LBS.pack [0xa0, 0x00]
      , testCase "binary with data -> vbin8 (0xa0)" $
          runPut (putAMQPValue (AMQPBinary "\x01\x02\x03")) @?=
            LBS.pack [0xa0, 0x03, 0x01, 0x02, 0x03]
      ]
  , testGroup "String"
      [ testCase "empty string -> str8 (0xa1)" $
          runPut (putAMQPValue (AMQPString "")) @?= LBS.pack [0xa1, 0x00]
      , testCase "ASCII string -> str8 (0xa1)" $
          runPut (putAMQPValue (AMQPString "hello")) @?=
            LBS.pack ([0xa1, 0x05] ++ [0x68, 0x65, 0x6c, 0x6c, 0x6f])
      , testCase "UTF-8 string -> str8 (0xa1)" $
          -- U+4E2D (Chinese "middle") = E4 B8 AD in UTF-8
          runPut (putAMQPValue (AMQPString "\x4E2D")) @?=
            LBS.pack [0xa1, 0x03, 0xe4, 0xb8, 0xad]
      ]
  , testGroup "Symbol"
      [ testCase "empty symbol -> sym8 (0xa3)" $
          runPut (putAMQPValue (AMQPSymbol "")) @?= LBS.pack [0xa3, 0x00]
      , testCase "symbol with data -> sym8 (0xa3)" $
          runPut (putAMQPValue (AMQPSymbol "amqp")) @?=
            LBS.pack ([0xa3, 0x04] ++ [0x61, 0x6d, 0x71, 0x70])
      ]
  ]

-- Test encoding of composite types
compositeEncodingTests :: TestTree
compositeEncodingTests = testGroup "Composite Types"
  [ testGroup "List"
      [ testCase "empty list -> list0 (0x45)" $
          runPut (putAMQPValue (AMQPList [])) @?= LBS.pack [0x45]
      , testCase "single element list -> list8 (0xc0)" $
          -- Format: 0xc0 | size | count | elements
          runPut (putAMQPValue (AMQPList [AMQPNull])) @?=
            LBS.pack [0xc0, 0x02, 0x01, 0x40]
      , testCase "mixed type list -> list8 (0xc0)" $
          runPut (putAMQPValue (AMQPList [AMQPNull, AMQPBool True, AMQPUInt 0])) @?=
            LBS.pack [0xc0, 0x04, 0x03, 0x40, 0x41, 0x43]
      ]
  , testGroup "Map"
      [ testCase "empty map -> map8 (0xc1)" $
          -- Format: 0xc1 | size | count
          runPut (putAMQPValue (AMQPMap [])) @?= LBS.pack [0xc1, 0x01, 0x00]
      , testCase "single pair map -> map8 (0xc1)" $
          -- Count is number of elements (2 * pairs)
          runPut (putAMQPValue (AMQPMap [(AMQPBool True, AMQPBool False)])) @?=
            LBS.pack [0xc1, 0x03, 0x02, 0x41, 0x42]
      ]
  , testGroup "Array"
      [ testCase "empty array -> array8 (0xe0)" $
          -- Format: 0xe0 | size | count
          runPut (putAMQPValue (AMQPArray [])) @?= LBS.pack [0xe0, 0x01, 0x00]
      , testCase "array with elements -> array8 (0xe0)" $
          runPut (putAMQPValue (AMQPArray [AMQPNull, AMQPNull])) @?=
            LBS.pack [0xe0, 0x03, 0x02, 0x40, 0x40]
      ]
  ]
