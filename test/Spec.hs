{-# LANGUAGE OverloadedStrings #-}

import Test.Tasty
import Test.Tasty.HUnit
import Data.Binary.Put (runPut)
import Data.ByteString.Lazy (ByteString)
import qualified Data.ByteString.Lazy as LBS
import Data.Time.Clock.POSIX (POSIXTime)
import Data.UUID (fromWords)

import Network.AMQP.Types

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "AMQP Tests"
  [ testGroup "Encoding"
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
      ]
  ]
