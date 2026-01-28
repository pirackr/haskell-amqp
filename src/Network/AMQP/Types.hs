{-# LANGUAGE OverloadedStrings #-}

-- | AMQP 1.0 type system encoding and decoding.
module Network.AMQP.Types
  ( -- * AMQP Values
    AMQPValue(..)
    -- * Encoding
  , putAMQPValue
  ) where

import Data.Binary.Put (Put, putWord8)
import Data.ByteString (ByteString)
import Data.Int (Int8, Int16, Int32, Int64)
import Data.Text (Text)
import Data.Time.Clock.POSIX (POSIXTime)
import Data.UUID (UUID)
import Data.Word (Word8, Word16, Word32, Word64)

-- | Represents all AMQP 1.0 primitive and composite types.
data AMQPValue
  -- Primitives
  = AMQPNull
  | AMQPBool !Bool
  | AMQPUByte !Word8
  | AMQPUShort !Word16
  | AMQPUInt !Word32
  | AMQPULong !Word64
  | AMQPByte !Int8
  | AMQPShort !Int16
  | AMQPInt !Int32
  | AMQPLong !Int64
  | AMQPFloat !Float
  | AMQPDouble !Double
  | AMQPChar !Char
  | AMQPTimestamp !POSIXTime
  | AMQPUuid !UUID
  | AMQPBinary !ByteString
  | AMQPString !Text
  | AMQPSymbol !Text
  -- Composites
  | AMQPList ![AMQPValue]
  | AMQPMap ![(AMQPValue, AMQPValue)]
  | AMQPArray ![AMQPValue]
  deriving (Eq, Show)

-- | Encode an AMQP value to its binary representation.
putAMQPValue :: AMQPValue -> Put
putAMQPValue AMQPNull = putWord8 0x40
putAMQPValue (AMQPBool True) = putWord8 0x41
putAMQPValue (AMQPBool False) = putWord8 0x42
putAMQPValue _ = error "putAMQPValue: not yet implemented"
