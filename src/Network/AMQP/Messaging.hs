{-# LANGUAGE OverloadedStrings #-}

-- | AMQP 1.0 messaging layer: message structure and encoding.
-- Implements message format as defined in section 3.2 of the AMQP 1.0 spec.
module Network.AMQP.Messaging
  ( -- * Message Structure
    Message(..)
    -- * Message Sections
  , Header(..)
  , Properties(..)
  , ApplicationProperties
  , Footer
  , MessageBody(..)
    -- * Message ID and Correlation ID
  , MessageId(..)
    -- * Delivery States
  , DeliveryState(..)
  , Rejected(..)
  , Modified(..)
    -- * Encoding/Decoding
  , putMessage
  , getMessage
  , putDeliveryState
  , getDeliveryState
  , encodeDeliveryState
  ) where

import Data.Binary.Get (Get, isEmpty)
import Data.Binary.Put (Put)
import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Word (Word8, Word32, Word64)
import Data.Time.Clock.POSIX (POSIXTime)
import Data.UUID (UUID)
import Network.AMQP.Types (AMQPValue(..), putAMQPValue, getAMQPValue)
import Network.AMQP.Performatives (Error(..))

-- | AMQP 1.0 message structure (section 3.2)
-- A message consists of multiple optional sections, each encoded as a described type.
-- The sections must appear in the following order:
--   1. Header (delivery annotations for transport)
--   2. Delivery Annotations (not yet implemented)
--   3. Message Annotations (not yet implemented)
--   4. Properties (immutable message properties)
--   5. Application Properties (structured application data)
--   6. Body (message payload)
--   7. Footer (transport footers, e.g., for signing)
data Message = Message
  { messageHeader             :: !(Maybe Header)
  , messageProperties         :: !(Maybe Properties)
  , messageApplicationProperties :: !(Maybe ApplicationProperties)
  , messageBody               :: !(Maybe MessageBody)
  , messageFooter             :: !(Maybe Footer)
  } deriving (Eq, Show)

-- | Header section (descriptor 0x00000070)
-- Contains delivery-related metadata (section 3.2.1)
data Header = Header
  { headerDurable       :: !(Maybe Bool)    -- ^ Durable messages survive broker restart
  , headerPriority      :: !(Maybe Word8)   -- ^ Message priority (0-9, default 4)
  , headerTtl           :: !(Maybe Word32)  -- ^ Time to live in milliseconds
  , headerFirstAcquirer :: !(Maybe Bool)    -- ^ True if this is first acquirer
  , headerDeliveryCount :: !(Maybe Word32)  -- ^ Number of failed delivery attempts
  } deriving (Eq, Show)

-- | Message ID can be various types (section 3.2.4)
data MessageId
  = MessageIdULong !Word64
  | MessageIdUuid !UUID
  | MessageIdBinary !ByteString
  | MessageIdString !Text
  deriving (Eq, Show)

-- | Properties section (descriptor 0x00000073)
-- Contains immutable message metadata (section 3.2.4)
data Properties = Properties
  { propertiesMessageId       :: !(Maybe MessageId) -- ^ Application message identifier
  , propertiesUserId          :: !(Maybe ByteString) -- ^ Creating user id
  , propertiesTo              :: !(Maybe Text)       -- ^ Destination address
  , propertiesSubject         :: !(Maybe Text)       -- ^ Message subject
  , propertiesReplyTo         :: !(Maybe Text)       -- ^ Address for replies
  , propertiesCorrelationId   :: !(Maybe MessageId)  -- ^ Correlation identifier
  , propertiesContentType     :: !(Maybe Text)       -- ^ MIME content type
  , propertiesContentEncoding :: !(Maybe Text)       -- ^ MIME content encoding
  , propertiesAbsoluteExpiryTime :: !(Maybe POSIXTime) -- ^ Absolute expiry time
  , propertiesCreationTime    :: !(Maybe POSIXTime)  -- ^ Creation time
  , propertiesGroupId         :: !(Maybe Text)       -- ^ Group identifier
  , propertiesGroupSequence   :: !(Maybe Word32)     -- ^ Sequence number within group
  , propertiesReplyToGroupId  :: !(Maybe Text)       -- ^ Reply-to group identifier
  } deriving (Eq, Show)

-- | Application Properties is a map of application-defined properties
-- Encoded as descriptor 0x00000074 with a map value
type ApplicationProperties = [(AMQPValue, AMQPValue)]

-- | Footer is a map of delivery annotations
-- Encoded as descriptor 0x00000078 with a map value
type Footer = [(AMQPValue, AMQPValue)]

-- | Message body variants (section 3.2.6, 3.2.7, 3.2.8)
-- A message can have one of three body types
data MessageBody
  = DataBody ![ByteString]              -- ^ Opaque binary data (descriptor 0x00000075)
  | AmqpSequenceBody ![[AMQPValue]]     -- ^ Sequence of AMQP lists (descriptor 0x00000076)
  | AmqpValueBody !AMQPValue            -- ^ Single AMQP value (descriptor 0x00000077)
  deriving (Eq, Show)

-- | Delivery states (section 3.4)
-- Describes the state of a message delivery
data DeliveryState
  = StateAccepted                       -- ^ Message accepted (descriptor 0x00000024)
  | StateRejected !Rejected             -- ^ Message rejected (descriptor 0x00000025)
  | StateReleased                       -- ^ Message released (descriptor 0x00000026)
  | StateModified !Modified             -- ^ Message modified (descriptor 0x00000027)
  deriving (Eq, Show)

-- | Rejected delivery state (descriptor 0x00000025)
-- Contains error information about why the message was rejected
data Rejected = Rejected
  { rejectedError :: !(Maybe Error)     -- ^ Error condition causing rejection
  } deriving (Eq, Show)

-- | Modified delivery state (descriptor 0x00000027)
-- Indicates message was modified and may be re-delivered
data Modified = Modified
  { modifiedDeliveryFailed      :: !(Maybe Bool)   -- ^ True if delivery failed
  , modifiedUndeliverableHere   :: !(Maybe Bool)   -- ^ True if undeliverable at this node
  , modifiedMessageAnnotations  :: !(Maybe [(AMQPValue, AMQPValue)])  -- ^ Updated annotations
  } deriving (Eq, Show)

-- Helper function to create a list of optional fields
optionalField :: Maybe a -> (a -> AMQPValue) -> AMQPValue
optionalField Nothing _ = AMQPNull
optionalField (Just x) f = f x

-- | Encode a message as a sequence of described type sections
putMessage :: Message -> Put
putMessage msg = do
  -- Encode header if present
  case messageHeader msg of
    Just hdr -> putAMQPValue (encodeHeader hdr)
    Nothing -> return ()

  -- Encode properties if present
  case messageProperties msg of
    Just props -> putAMQPValue (encodeProperties props)
    Nothing -> return ()

  -- Encode application properties if present
  case messageApplicationProperties msg of
    Just appProps -> putAMQPValue (encodeApplicationProperties appProps)
    Nothing -> return ()

  -- Encode body if present
  case messageBody msg of
    Just body -> encodeMessageBody body
    Nothing -> return ()

  -- Encode footer if present
  case messageFooter msg of
    Just footer -> putAMQPValue (encodeFooter footer)
    Nothing -> return ()

-- Encode Header as described list (descriptor 0x00000070)
encodeHeader :: Header -> AMQPValue
encodeHeader hdr = AMQPDescribed
  (AMQPULong 0x00000070)
  (AMQPList
    [ optionalField (headerDurable hdr) AMQPBool
    , optionalField (headerPriority hdr) AMQPUByte
    , optionalField (headerTtl hdr) AMQPUInt
    , optionalField (headerFirstAcquirer hdr) AMQPBool
    , optionalField (headerDeliveryCount hdr) AMQPUInt
    ])

-- Encode MessageId
encodeMessageId :: MessageId -> AMQPValue
encodeMessageId (MessageIdULong n) = AMQPULong n
encodeMessageId (MessageIdUuid u) = AMQPUuid u
encodeMessageId (MessageIdBinary b) = AMQPBinary b
encodeMessageId (MessageIdString s) = AMQPString s

-- Encode Properties as described list (descriptor 0x00000073)
encodeProperties :: Properties -> AMQPValue
encodeProperties props = AMQPDescribed
  (AMQPULong 0x00000073)
  (AMQPList
    [ optionalField (propertiesMessageId props) encodeMessageId
    , optionalField (propertiesUserId props) AMQPBinary
    , optionalField (propertiesTo props) AMQPString
    , optionalField (propertiesSubject props) AMQPString
    , optionalField (propertiesReplyTo props) AMQPString
    , optionalField (propertiesCorrelationId props) encodeMessageId
    , optionalField (propertiesContentType props) AMQPSymbol
    , optionalField (propertiesContentEncoding props) AMQPSymbol
    , optionalField (propertiesAbsoluteExpiryTime props) AMQPTimestamp
    , optionalField (propertiesCreationTime props) AMQPTimestamp
    , optionalField (propertiesGroupId props) AMQPString
    , optionalField (propertiesGroupSequence props) AMQPUInt
    , optionalField (propertiesReplyToGroupId props) AMQPString
    ])

-- Encode Application Properties (descriptor 0x00000074)
encodeApplicationProperties :: ApplicationProperties -> AMQPValue
encodeApplicationProperties appProps = AMQPDescribed
  (AMQPULong 0x00000074)
  (AMQPMap appProps)

-- Encode Footer (descriptor 0x00000078)
encodeFooter :: Footer -> AMQPValue
encodeFooter footer = AMQPDescribed
  (AMQPULong 0x00000078)
  (AMQPMap footer)

-- Encode message body
encodeMessageBody :: MessageBody -> Put
encodeMessageBody (DataBody sections) = do
  -- Each section is encoded as a described type with descriptor 0x00000075
  mapM_ (\bs -> putAMQPValue (AMQPDescribed (AMQPULong 0x00000075) (AMQPBinary bs))) sections
encodeMessageBody (AmqpSequenceBody sequences) = do
  -- Each sequence is encoded as a described type with descriptor 0x00000076
  mapM_ (\seq -> putAMQPValue (AMQPDescribed (AMQPULong 0x00000076) (AMQPList seq))) sequences
encodeMessageBody (AmqpValueBody value) = do
  -- Single value encoded as a described type with descriptor 0x00000077
  putAMQPValue (AMQPDescribed (AMQPULong 0x00000077) value)

-- | Decode a message from a sequence of described type sections
getMessage :: Get Message
getMessage = readSections Nothing Nothing Nothing Nothing Nothing

-- Helper to read message sections sequentially
readSections :: Maybe Header -> Maybe Properties -> Maybe ApplicationProperties -> Maybe MessageBody -> Maybe Footer -> Get Message
readSections hdr props appProps body footer = do
  -- Check if there's more data to read
  empty <- isEmpty
  if empty
    then return $ Message hdr props appProps body footer
    else do
      section <- getAMQPValue
      case section of
        AMQPDescribed descriptor value -> do
          case descriptor of
            AMQPULong 0x00000070 -> do
              -- Header section
              header <- decodeHeader value
              readSections (Just header) props appProps body footer
            AMQPULong 0x00000073 -> do
              -- Properties section
              properties <- decodeProperties value
              readSections hdr (Just properties) appProps body footer
            AMQPULong 0x00000074 -> do
              -- Application Properties
              appProperties <- decodeApplicationProperties value
              readSections hdr props (Just appProperties) body footer
            AMQPULong 0x00000075 -> do
              -- Data body - may have multiple sections
              case body of
                Just (DataBody sections) -> do
                  bs <- case value of
                    AMQPBinary b -> return b
                    _ -> fail "decodeDataBody: expected binary"
                  readSections hdr props appProps (Just (DataBody (sections ++ [bs]))) footer
                Nothing -> do
                  bs <- case value of
                    AMQPBinary b -> return b
                    _ -> fail "decodeDataBody: expected binary"
                  readSections hdr props appProps (Just (DataBody [bs])) footer
                _ -> fail "getMessage: cannot mix body types"
            AMQPULong 0x00000076 -> do
              -- AmqpSequence body - may have multiple sections
              case body of
                Just (AmqpSequenceBody sequences) -> do
                  seq <- case value of
                    AMQPList lst -> return lst
                    _ -> fail "decodeAmqpSequenceBody: expected list"
                  readSections hdr props appProps (Just (AmqpSequenceBody (sequences ++ [seq]))) footer
                Nothing -> do
                  seq <- case value of
                    AMQPList lst -> return lst
                    _ -> fail "decodeAmqpSequenceBody: expected list"
                  readSections hdr props appProps (Just (AmqpSequenceBody [seq])) footer
                _ -> fail "getMessage: cannot mix body types"
            AMQPULong 0x00000077 -> do
              -- AmqpValue body (single value only)
              readSections hdr props appProps (Just (AmqpValueBody value)) footer
            AMQPULong 0x00000078 -> do
              -- Footer
              footerMap <- decodeFooter value
              readSections hdr props appProps body (Just footerMap)
            _ -> fail $ "getMessage: unknown descriptor " ++ show descriptor
        _ -> fail "getMessage: expected described type for message section"

-- Decode Header
decodeHeader :: AMQPValue -> Get Header
decodeHeader (AMQPList fields) = do
  let durable = case getField fields 0 of
        Just (AMQPBool b) -> Just b
        _ -> Nothing

  let priority = case getField fields 1 of
        Just (AMQPUByte n) -> Just n
        _ -> Nothing

  let ttl = case getField fields 2 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  let firstAcquirer = case getField fields 3 of
        Just (AMQPBool b) -> Just b
        _ -> Nothing

  let deliveryCount = case getField fields 4 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  return $ Header
    { headerDurable = durable
    , headerPriority = priority
    , headerTtl = ttl
    , headerFirstAcquirer = firstAcquirer
    , headerDeliveryCount = deliveryCount
    }
decodeHeader _ = fail "decodeHeader: expected list"

-- Decode MessageId
decodeMessageId :: AMQPValue -> Get MessageId
decodeMessageId (AMQPULong n) = return $ MessageIdULong n
decodeMessageId (AMQPUuid u) = return $ MessageIdUuid u
decodeMessageId (AMQPBinary b) = return $ MessageIdBinary b
decodeMessageId (AMQPString s) = return $ MessageIdString s
decodeMessageId _ = fail "decodeMessageId: invalid type"

-- Decode Properties
decodeProperties :: AMQPValue -> Get Properties
decodeProperties (AMQPList fields) = do
  messageId <- case getField fields 0 of
    Just val -> Just <$> decodeMessageId val
    Nothing -> return Nothing

  let userId = case getField fields 1 of
        Just (AMQPBinary b) -> Just b
        _ -> Nothing

  let to = case getField fields 2 of
        Just (AMQPString s) -> Just s
        _ -> Nothing

  let subject = case getField fields 3 of
        Just (AMQPString s) -> Just s
        _ -> Nothing

  let replyTo = case getField fields 4 of
        Just (AMQPString s) -> Just s
        _ -> Nothing

  correlationId <- case getField fields 5 of
    Just val -> Just <$> decodeMessageId val
    Nothing -> return Nothing

  let contentType = case getField fields 6 of
        Just (AMQPSymbol s) -> Just s
        _ -> Nothing

  let contentEncoding = case getField fields 7 of
        Just (AMQPSymbol s) -> Just s
        _ -> Nothing

  let absoluteExpiryTime = case getField fields 8 of
        Just (AMQPTimestamp t) -> Just t
        _ -> Nothing

  let creationTime = case getField fields 9 of
        Just (AMQPTimestamp t) -> Just t
        _ -> Nothing

  let groupId = case getField fields 10 of
        Just (AMQPString s) -> Just s
        _ -> Nothing

  let groupSequence = case getField fields 11 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  let replyToGroupId = case getField fields 12 of
        Just (AMQPString s) -> Just s
        _ -> Nothing

  return $ Properties
    { propertiesMessageId = messageId
    , propertiesUserId = userId
    , propertiesTo = to
    , propertiesSubject = subject
    , propertiesReplyTo = replyTo
    , propertiesCorrelationId = correlationId
    , propertiesContentType = contentType
    , propertiesContentEncoding = contentEncoding
    , propertiesAbsoluteExpiryTime = absoluteExpiryTime
    , propertiesCreationTime = creationTime
    , propertiesGroupId = groupId
    , propertiesGroupSequence = groupSequence
    , propertiesReplyToGroupId = replyToGroupId
    }
decodeProperties _ = fail "decodeProperties: expected list"

-- Decode Application Properties
decodeApplicationProperties :: AMQPValue -> Get ApplicationProperties
decodeApplicationProperties (AMQPMap m) = return m
decodeApplicationProperties _ = fail "decodeApplicationProperties: expected map"

-- Decode Footer
decodeFooter :: AMQPValue -> Get Footer
decodeFooter (AMQPMap m) = return m
decodeFooter _ = fail "decodeFooter: expected map"

-- Decode Data body
decodeDataBody :: AMQPValue -> [ByteString] -> Get MessageBody
decodeDataBody (AMQPBinary bs) acc = do
  -- For now, just return a single data section
  -- In a full implementation, we'd continue reading subsequent data sections
  return $ DataBody (reverse (bs:acc))
decodeDataBody _ _ = fail "decodeDataBody: expected binary"

-- Decode AmqpSequence body
decodeAmqpSequenceBody :: AMQPValue -> [[AMQPValue]] -> Get MessageBody
decodeAmqpSequenceBody (AMQPList lst) acc = do
  -- For now, just return a single sequence
  return $ AmqpSequenceBody (reverse (lst:acc))
decodeAmqpSequenceBody _ _ = fail "decodeAmqpSequenceBody: expected list"

-- Helper to extract field from list
getField :: [AMQPValue] -> Int -> Maybe AMQPValue
getField fields idx
  | idx >= length fields = Nothing
  | otherwise = case fields !! idx of
      AMQPNull -> Nothing
      val -> Just val

-- -----------------------------------------------------------------------------
-- Delivery States Encoding/Decoding
-- -----------------------------------------------------------------------------

-- | Encode a delivery state as a described type
putDeliveryState :: DeliveryState -> Put
putDeliveryState state = putAMQPValue (encodeDeliveryState state)

-- | Decode a delivery state from a described type
getDeliveryState :: Get DeliveryState
getDeliveryState = do
  value <- getAMQPValue
  case value of
    AMQPDescribed descriptor fields -> decodeDeliveryState descriptor fields
    _ -> fail "getDeliveryState: expected described type"

-- Encode delivery state
encodeDeliveryState :: DeliveryState -> AMQPValue
encodeDeliveryState StateAccepted = AMQPDescribed
  (AMQPULong 0x00000024)
  (AMQPList [])

encodeDeliveryState (StateRejected rejected) = AMQPDescribed
  (AMQPULong 0x00000025)
  (AMQPList
    [ optionalField (rejectedError rejected) encodeError
    ])

encodeDeliveryState StateReleased = AMQPDescribed
  (AMQPULong 0x00000026)
  (AMQPList [])

encodeDeliveryState (StateModified modified) = AMQPDescribed
  (AMQPULong 0x00000027)
  (AMQPList
    [ optionalField (modifiedDeliveryFailed modified) AMQPBool
    , optionalField (modifiedUndeliverableHere modified) AMQPBool
    , optionalField (modifiedMessageAnnotations modified) AMQPMap
    ])

-- Encode Error (descriptor 0x0000001d)
-- Internal helper function for encoding Error values
encodeError :: Error -> AMQPValue
encodeError err = AMQPDescribed
  (AMQPULong 0x0000001d)
  (AMQPList
    [ AMQPSymbol (errorCondition err)
    , optionalField (errorDescription err) AMQPString
    , optionalField (errorInfo err) AMQPMap
    ])

-- Decode delivery state based on descriptor
decodeDeliveryState :: AMQPValue -> AMQPValue -> Get DeliveryState
decodeDeliveryState (AMQPULong descriptor) fields =
  case descriptor of
    0x00000024 -> return StateAccepted
    0x00000025 -> StateRejected <$> decodeRejected fields
    0x00000026 -> return StateReleased
    0x00000027 -> StateModified <$> decodeModified fields
    _ -> fail $ "decodeDeliveryState: unknown descriptor " ++ show descriptor
decodeDeliveryState _ _ = fail "decodeDeliveryState: descriptor must be ulong"

-- Decode Rejected
decodeRejected :: AMQPValue -> Get Rejected
decodeRejected (AMQPList fields) = do
  error <- case getField fields 0 of
    Just val -> Just <$> decodeError val
    Nothing -> return Nothing

  return $ Rejected { rejectedError = error }
decodeRejected _ = fail "decodeRejected: expected list"

-- Decode Modified
decodeModified :: AMQPValue -> Get Modified
decodeModified (AMQPList fields) = do
  let deliveryFailed = case getField fields 0 of
        Just (AMQPBool b) -> Just b
        _ -> Nothing

  let undeliverableHere = case getField fields 1 of
        Just (AMQPBool b) -> Just b
        _ -> Nothing

  let messageAnnotations = case getField fields 2 of
        Just (AMQPMap m) -> Just m
        _ -> Nothing

  return $ Modified
    { modifiedDeliveryFailed = deliveryFailed
    , modifiedUndeliverableHere = undeliverableHere
    , modifiedMessageAnnotations = messageAnnotations
    }
decodeModified _ = fail "decodeModified: expected list"

-- Decode Error (descriptor 0x0000001d)
-- Internal helper function for decoding Error values
decodeError :: AMQPValue -> Get Error
decodeError (AMQPDescribed (AMQPULong 0x0000001d) (AMQPList fields)) = do
  condition <- case getField fields 0 of
    Just (AMQPSymbol s) -> return s
    _ -> fail "decodeError: missing condition"

  let description = case getField fields 1 of
        Just (AMQPString s) -> Just s
        _ -> Nothing

  let info = case getField fields 2 of
        Just (AMQPMap m) -> Just m
        _ -> Nothing

  return $ Error
    { errorCondition = condition
    , errorDescription = description
    , errorInfo = info
    }
decodeError _ = fail "decodeError: expected described type with descriptor 0x1d"
