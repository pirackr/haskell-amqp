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
      ]
  ]
