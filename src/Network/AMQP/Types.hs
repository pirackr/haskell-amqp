{-# LANGUAGE OverloadedStrings #-}

-- | AMQP 1.0 type system encoding and decoding.
module Network.AMQP.Types
  ( -- * AMQP Values
    AMQPValue(..)
    -- * Encoding
  , putAMQPValue
    -- * Decoding
  , getAMQPValue
  ) where

import Data.Binary.Get (Get, getWord8, getWord16be, getWord32be, getWord64be, getInt8, getInt16be, getInt32be, getInt64be, getByteString, getFloatbe, getDoublebe)
import Data.Binary.Put (Put, putWord8, putWord16be, putWord32be, putWord64be, putInt8, putInt16be, putInt32be, putInt64be, putByteString, putFloatbe, putDoublebe)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Int (Int8, Int16, Int32, Int64)
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import Data.Time.Clock.POSIX (POSIXTime)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
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
-- Binary
putAMQPValue (AMQPBinary bs) =
  let len = BS.length bs
  in if len <= 255
     then putWord8 0xa0 >> putWord8 (fromIntegral len) >> putByteString bs  -- vbin8
     else putWord8 0xb0 >> putWord32be (fromIntegral len) >> putByteString bs  -- vbin32
-- UUID: 0x98 + 16 bytes
putAMQPValue (AMQPUuid uuid) =
  putWord8 0x98 >> putByteString (LBS.toStrict (UUID.toByteString uuid))
-- Timestamp: 0x83 + 8 bytes (milliseconds since Unix epoch)
putAMQPValue (AMQPTimestamp t) =
  let millis = floor (t * 1000) :: Int64
  in putWord8 0x83 >> putInt64be millis
-- Float: 0x72 + 4 bytes IEEE 754
putAMQPValue (AMQPFloat f) = putWord8 0x72 >> putFloatbe f
-- Double: 0x82 + 8 bytes IEEE 754
putAMQPValue (AMQPDouble d) = putWord8 0x82 >> putDoublebe d
putAMQPValue _ = error "putAMQPValue: not yet implemented"

-- | Decode an AMQP value from its binary representation.
getAMQPValue :: Get AMQPValue
getAMQPValue = do
  typeCode <- getWord8
  case typeCode of
    0x40 -> return AMQPNull
    0x41 -> return (AMQPBool True)
    0x42 -> return (AMQPBool False)
    -- Unsigned integers
    0x50 -> AMQPUByte <$> getWord8
    0x60 -> AMQPUShort <$> getWord16be
    0x43 -> return (AMQPUInt 0)  -- uint0
    0x52 -> AMQPUInt . fromIntegral <$> getWord8  -- smalluint
    0x70 -> AMQPUInt <$> getWord32be
    0x44 -> return (AMQPULong 0)  -- ulong0
    0x53 -> AMQPULong . fromIntegral <$> getWord8  -- smallulong
    0x80 -> AMQPULong <$> getWord64be
    -- Signed integers
    0x51 -> AMQPByte <$> getInt8
    0x61 -> AMQPShort <$> getInt16be
    0x54 -> AMQPInt . fromIntegral <$> getInt8  -- smallint
    0x71 -> AMQPInt <$> getInt32be
    0x55 -> AMQPLong . fromIntegral <$> getInt8  -- smalllong
    0x81 -> AMQPLong <$> getInt64be
    -- Binary
    0xa0 -> do  -- vbin8
      len <- fromIntegral <$> getWord8
      AMQPBinary <$> getByteString len
    0xb0 -> do  -- vbin32
      len <- fromIntegral <$> getWord32be
      AMQPBinary <$> getByteString len
    -- String (UTF-8)
    0xa1 -> do  -- str8
      len <- fromIntegral <$> getWord8
      bs <- getByteString len
      return $ AMQPString (TE.decodeUtf8 bs)
    0xb1 -> do  -- str32
      len <- fromIntegral <$> getWord32be
      bs <- getByteString len
      return $ AMQPString (TE.decodeUtf8 bs)
    -- Symbol (ASCII)
    0xa3 -> do  -- sym8
      len <- fromIntegral <$> getWord8
      bs <- getByteString len
      return $ AMQPSymbol (TE.decodeUtf8 bs)
    0xb3 -> do  -- sym32
      len <- fromIntegral <$> getWord32be
      bs <- getByteString len
      return $ AMQPSymbol (TE.decodeUtf8 bs)
    -- UUID: 16 bytes
    0x98 -> do
      bs <- getByteString 16
      case UUID.fromByteString (LBS.fromStrict bs) of
        Just uuid -> return (AMQPUuid uuid)
        Nothing   -> fail "getAMQPValue: invalid UUID bytes"
    -- Float: IEEE 754 4 bytes
    0x72 -> AMQPFloat <$> getFloatbe
    -- Double: IEEE 754 8 bytes
    0x82 -> AMQPDouble <$> getDoublebe
    -- Timestamp: 8 bytes (milliseconds since Unix epoch)
    0x83 -> do
      millis <- getInt64be
      let posixTime = fromIntegral millis / 1000 :: POSIXTime
      return (AMQPTimestamp posixTime)
    _    -> fail $ "getAMQPValue: unknown type code " ++ show typeCode
