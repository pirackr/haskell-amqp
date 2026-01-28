{-# LANGUAGE OverloadedStrings #-}

-- | AMQP 1.0 type system encoding and decoding.
module Network.AMQP.Types
  ( -- * AMQP Values
    AMQPValue(..)
    -- * Encoding
  , putAMQPValue
  ) where

import Data.Binary.Put (Put, putWord8, putWord16be, putWord32be, putWord64be, putInt8, putInt16be, putInt32be, putInt64be, putByteString)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Int (Int8, Int16, Int32, Int64)
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
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
-- Unsigned integers
putAMQPValue (AMQPUByte n) = putWord8 0x50 >> putWord8 n
putAMQPValue (AMQPUShort n) = putWord8 0x60 >> putWord16be n
putAMQPValue (AMQPUInt n)
  | n == 0    = putWord8 0x43  -- uint0
  | n <= 255  = putWord8 0x52 >> putWord8 (fromIntegral n)  -- smalluint
  | otherwise = putWord8 0x70 >> putWord32be n  -- full uint
putAMQPValue (AMQPULong n)
  | n == 0    = putWord8 0x44  -- ulong0
  | n <= 255  = putWord8 0x53 >> putWord8 (fromIntegral n)  -- smallulong
  | otherwise = putWord8 0x80 >> putWord64be n  -- full ulong
-- Signed integers
putAMQPValue (AMQPByte n) = putWord8 0x51 >> putInt8 n
putAMQPValue (AMQPShort n) = putWord8 0x61 >> putInt16be n
putAMQPValue (AMQPInt n)
  | n >= -128 && n <= 127 = putWord8 0x54 >> putInt8 (fromIntegral n)  -- smallint
  | otherwise = putWord8 0x71 >> putInt32be n  -- full int
putAMQPValue (AMQPLong n)
  | n >= -128 && n <= 127 = putWord8 0x55 >> putInt8 (fromIntegral n)  -- smalllong
  | otherwise = putWord8 0x81 >> putInt64be n  -- full long
-- String (UTF-8)
putAMQPValue (AMQPString t) =
  let bs = TE.encodeUtf8 t
      len = BS.length bs
  in if len <= 255
     then putWord8 0xa1 >> putWord8 (fromIntegral len) >> putByteString bs  -- str8
     else putWord8 0xb1 >> putWord32be (fromIntegral len) >> putByteString bs  -- str32
-- Symbol (ASCII subset)
putAMQPValue (AMQPSymbol t) =
  let bs = TE.encodeUtf8 t
      len = BS.length bs
  in if len <= 255
     then putWord8 0xa3 >> putWord8 (fromIntegral len) >> putByteString bs  -- sym8
     else putWord8 0xb3 >> putWord32be (fromIntegral len) >> putByteString bs  -- sym32
putAMQPValue _ = error "putAMQPValue: not yet implemented"
