import Test.Tasty
import Test.Tasty.HUnit
import Data.Binary.Put (runPut)
import Data.ByteString.Lazy (ByteString)
import qualified Data.ByteString.Lazy as LBS

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
      ]
  ]
