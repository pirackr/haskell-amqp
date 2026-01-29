{-# LANGUAGE OverloadedStrings #-}

-- | AMQP 1.0 transport performatives.
-- This module implements all 9 AMQP performatives as defined in section 2.7 of the spec.
module Network.AMQP.Performatives
  ( -- * Performative ADT
    Performative(..)
    -- * Open
  , Open(..)
    -- * Begin
  , Begin(..)
    -- * Attach
  , Attach(..)
  , Role(..)
  , SenderSettleMode(..)
  , ReceiverSettleMode(..)
    -- * Flow
  , Flow(..)
    -- * Transfer
  , Transfer(..)
    -- * Disposition
  , Disposition(..)
    -- * Detach
  , Detach(..)
    -- * End
  , End(..)
    -- * Close
  , Close(..)
    -- * Error
  , Error(..)
    -- * Source/Target
  , Source(..)
  , Target(..)
  , Terminus(..)
    -- * Encoding/Decoding
  , putPerformative
  , getPerformative
  ) where

import Data.Binary.Get (Get)
import Data.Binary.Put (Put, runPut)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import Data.Word (Word8, Word16, Word32, Word64)
import Network.AMQP.Types (AMQPValue(..), putAMQPValue, getAMQPValue)

-- | AMQP 1.0 performatives (transport layer operations)
data Performative
  = PerformativeOpen !Open
  | PerformativeBegin !Begin
  | PerformativeAttach !Attach
  | PerformativeFlow !Flow
  | PerformativeTransfer !Transfer
  | PerformativeDisposition !Disposition
  | PerformativeDetach !Detach
  | PerformativeEnd !End
  | PerformativeClose !Close
  deriving (Eq, Show)

-- | OPEN performative (descriptor 0x00000010)
-- Negotiates connection parameters
data Open = Open
  { openContainerId      :: !Text               -- ^ Required: unique container identifier
  , openHostname         :: !(Maybe Text)       -- ^ Optional: hostname of target
  , openMaxFrameSize     :: !(Maybe Word32)     -- ^ Optional: max frame size in bytes (default 4294967295)
  , openChannelMax       :: !(Maybe Word16)     -- ^ Optional: max channel number (default 65535)
  , openIdleTimeOut      :: !(Maybe Word32)     -- ^ Optional: idle timeout in milliseconds
  , openOutgoingLocales  :: !(Maybe [Text])     -- ^ Optional: supported outgoing locales
  , openIncomingLocales  :: !(Maybe [Text])     -- ^ Optional: supported incoming locales
  , openOfferedCapabilities :: !(Maybe [Text]) -- ^ Optional: offered capabilities
  , openDesiredCapabilities :: !(Maybe [Text]) -- ^ Optional: desired capabilities
  , openProperties       :: !(Maybe [(AMQPValue, AMQPValue)]) -- ^ Optional: connection properties
  } deriving (Eq, Show)

-- | BEGIN performative (descriptor 0x00000011)
-- Begins a session on a channel
data Begin = Begin
  { beginRemoteChannel      :: !(Maybe Word16) -- ^ Optional for initiator, required for responder
  , beginNextOutgoingId     :: !Word32         -- ^ Required: next outgoing transfer-id
  , beginIncomingWindow     :: !Word32         -- ^ Required: incoming window size
  , beginOutgoingWindow     :: !Word32         -- ^ Required: outgoing window size
  , beginHandleMax          :: !(Maybe Word32) -- ^ Optional: max handle value (default 4294967295)
  , beginOfferedCapabilities :: !(Maybe [Text]) -- ^ Optional: offered capabilities
  , beginDesiredCapabilities :: !(Maybe [Text]) -- ^ Optional: desired capabilities
  , beginProperties         :: !(Maybe [(AMQPValue, AMQPValue)]) -- ^ Optional: session properties
  } deriving (Eq, Show)

-- | Role in link attachment
data Role
  = RoleSender   -- ^ Link is sender (0x00 = false)
  | RoleReceiver -- ^ Link is receiver (0x01 = true)
  deriving (Eq, Show)

-- | Sender settlement mode
data SenderSettleMode
  = Unsettled -- ^ 0: sender will send unsettled
  | Settled   -- ^ 1: sender will send settled
  | Mixed     -- ^ 2: sender may send settled or unsettled
  deriving (Eq, Show)

-- | Receiver settlement mode
data ReceiverSettleMode
  = First  -- ^ 0: receiver settles first
  | Second -- ^ 1: receiver settles second
  deriving (Eq, Show)

-- | Terminus (source or target)
data Terminus = Terminus
  { terminusAddress      :: !(Maybe Text)           -- ^ Address of terminus
  , terminusDurable      :: !(Maybe Word32)         -- ^ Durability (0=none, 1=configuration, 2=unsettled-state)
  , terminusExpiryPolicy :: !(Maybe Text)           -- ^ Expiry policy
  , terminusTimeout      :: !(Maybe Word32)         -- ^ Timeout in seconds
  , terminusDynamic      :: !(Maybe Bool)           -- ^ Dynamic creation
  , terminusDynamicNodeProperties :: !(Maybe [(AMQPValue, AMQPValue)]) -- ^ Properties for dynamic node
  , terminusCapabilities :: !(Maybe [Text])         -- ^ Extension capabilities
  } deriving (Eq, Show)

-- | Source terminus
newtype Source = Source Terminus
  deriving (Eq, Show)

-- | Target terminus
newtype Target = Target Terminus
  deriving (Eq, Show)

-- | ATTACH performative (descriptor 0x00000012)
-- Attaches a link to a session
data Attach = Attach
  { attachName            :: !Text                   -- ^ Required: link name
  , attachHandle          :: !Word32                 -- ^ Required: link handle
  , attachRole            :: !Role                   -- ^ Required: role (sender/receiver)
  , attachSndSettleMode   :: !(Maybe SenderSettleMode)   -- ^ Optional: sender settlement mode
  , attachRcvSettleMode   :: !(Maybe ReceiverSettleMode) -- ^ Optional: receiver settlement mode
  , attachSource          :: !(Maybe Source)         -- ^ Optional: source terminus
  , attachTarget          :: !(Maybe Target)         -- ^ Optional: target terminus
  , attachUnsettled       :: !(Maybe [(AMQPValue, AMQPValue)]) -- ^ Optional: unsettled deliveries
  , attachIncompleteUnsettled :: !(Maybe Bool)       -- ^ Optional: unsettled list incomplete
  , attachInitialDeliveryCount :: !(Maybe Word32)    -- ^ Optional: initial delivery count (required for receiver)
  , attachMaxMessageSize  :: !(Maybe Word64)         -- ^ Optional: max message size
  , attachOfferedCapabilities :: !(Maybe [Text])     -- ^ Optional: offered capabilities
  , attachDesiredCapabilities :: !(Maybe [Text])     -- ^ Optional: desired capabilities
  , attachProperties      :: !(Maybe [(AMQPValue, AMQPValue)]) -- ^ Optional: link properties
  } deriving (Eq, Show)

-- | FLOW performative (descriptor 0x00000013)
-- Updates flow control state
data Flow = Flow
  { flowNextIncomingId   :: !(Maybe Word32)  -- ^ Optional: next expected transfer-id
  , flowIncomingWindow   :: !Word32          -- ^ Required: available incoming window
  , flowNextOutgoingId   :: !Word32          -- ^ Required: next outgoing transfer-id
  , flowOutgoingWindow   :: !Word32          -- ^ Required: available outgoing window
  , flowHandle           :: !(Maybe Word32)  -- ^ Optional: link handle for link flow
  , flowDeliveryCount    :: !(Maybe Word32)  -- ^ Optional: delivery count (required for link flow)
  , flowLinkCredit       :: !(Maybe Word32)  -- ^ Optional: link credit (required for link flow)
  , flowAvailable        :: !(Maybe Word32)  -- ^ Optional: available messages
  , flowDrain            :: !(Maybe Bool)    -- ^ Optional: drain mode
  , flowEcho             :: !(Maybe Bool)    -- ^ Optional: request echo
  , flowProperties       :: !(Maybe [(AMQPValue, AMQPValue)]) -- ^ Optional: flow properties
  } deriving (Eq, Show)

-- | TRANSFER performative (descriptor 0x00000014)
-- Transfers a message
data Transfer = Transfer
  { transferHandle        :: !Word32            -- ^ Required: link handle
  , transferDeliveryId    :: !(Maybe Word32)    -- ^ Optional: delivery identifier
  , transferDeliveryTag   :: !(Maybe ByteString) -- ^ Optional: delivery tag
  , transferMessageFormat :: !(Maybe Word32)    -- ^ Optional: message format code
  , transferSettled       :: !(Maybe Bool)      -- ^ Optional: settled flag
  , transferMore          :: !(Maybe Bool)      -- ^ Optional: more message data follows
  , transferRcvSettleMode :: !(Maybe ReceiverSettleMode) -- ^ Optional: receiver settlement mode
  , transferState         :: !(Maybe AMQPValue) -- ^ Optional: delivery state
  , transferResume        :: !(Maybe Bool)      -- ^ Optional: resume previous transfer
  , transferAborted       :: !(Maybe Bool)      -- ^ Optional: aborted flag
  , transferBatchable     :: !(Maybe Bool)      -- ^ Optional: batchable hint
  } deriving (Eq, Show)

-- | DISPOSITION performative (descriptor 0x00000015)
-- Informs remote peer of delivery state changes
data Disposition = Disposition
  { dispositionRole     :: !Role           -- ^ Required: role (sender/receiver)
  , dispositionFirst    :: !Word32         -- ^ Required: first delivery-id
  , dispositionLast     :: !(Maybe Word32) -- ^ Optional: last delivery-id (defaults to first)
  , dispositionSettled  :: !(Maybe Bool)   -- ^ Optional: settled flag
  , dispositionState    :: !(Maybe AMQPValue) -- ^ Optional: delivery state
  , dispositionBatchable :: !(Maybe Bool)  -- ^ Optional: batchable hint
  } deriving (Eq, Show)

-- | Error condition
data Error = Error
  { errorCondition   :: !Text                              -- ^ Required: error condition symbol
  , errorDescription :: !(Maybe Text)                      -- ^ Optional: error description
  , errorInfo        :: !(Maybe [(AMQPValue, AMQPValue)])  -- ^ Optional: supplementary information
  } deriving (Eq, Show)

-- | DETACH performative (descriptor 0x00000016)
-- Detaches a link
data Detach = Detach
  { detachHandle :: !Word32      -- ^ Required: link handle
  , detachClosed :: !(Maybe Bool) -- ^ Optional: closed flag (true = link destroyed)
  , detachError  :: !(Maybe Error) -- ^ Optional: error causing detach
  } deriving (Eq, Show)

-- | END performative (descriptor 0x00000017)
-- Ends a session
data End = End
  { endError :: !(Maybe Error) -- ^ Optional: error causing end
  } deriving (Eq, Show)

-- | CLOSE performative (descriptor 0x00000018)
-- Closes a connection
data Close = Close
  { closeError :: !(Maybe Error) -- ^ Optional: error causing close
  } deriving (Eq, Show)

-- Helper function to create a list of optional fields
-- Fields are added to the list in order, with Nothing becoming AMQPNull
optionalField :: Maybe a -> (a -> AMQPValue) -> AMQPValue
optionalField Nothing _ = AMQPNull
optionalField (Just x) f = f x

-- Helper to convert list to AMQPValue
listToAMQP :: [Text] -> AMQPValue
listToAMQP xs = AMQPList (map AMQPSymbol xs)

-- Helper to convert map to AMQPValue
mapToAMQP :: [(AMQPValue, AMQPValue)] -> AMQPValue
mapToAMQP = AMQPMap

-- | Encode a performative as a described type with a list of fields
putPerformative :: Performative -> Put
putPerformative (PerformativeOpen open) = putAMQPValue $ encodeOpen open
putPerformative (PerformativeBegin begin) = putAMQPValue $ encodeBegin begin
putPerformative (PerformativeAttach attach) = putAMQPValue $ encodeAttach attach
putPerformative (PerformativeFlow flow) = putAMQPValue $ encodeFlow flow
putPerformative (PerformativeTransfer transfer) = putAMQPValue $ encodeTransfer transfer
putPerformative (PerformativeDisposition disposition) = putAMQPValue $ encodeDisposition disposition
putPerformative (PerformativeDetach detach) = putAMQPValue $ encodeDetach detach
putPerformative (PerformativeEnd end) = putAMQPValue $ encodeEnd end
putPerformative (PerformativeClose close) = putAMQPValue $ encodeClose close

-- Encode OPEN as described list
encodeOpen :: Open -> AMQPValue
encodeOpen open = AMQPDescribed
  (AMQPULong 0x00000010)  -- descriptor
  (AMQPList
    [ AMQPString (openContainerId open)
    , optionalField (openHostname open) AMQPString
    , optionalField (openMaxFrameSize open) AMQPUInt
    , optionalField (openChannelMax open) AMQPUShort
    , optionalField (openIdleTimeOut open) AMQPUInt
    , optionalField (openOutgoingLocales open) listToAMQP
    , optionalField (openIncomingLocales open) listToAMQP
    , optionalField (openOfferedCapabilities open) listToAMQP
    , optionalField (openDesiredCapabilities open) listToAMQP
    , optionalField (openProperties open) mapToAMQP
    ])

-- Encode BEGIN as described list
encodeBegin :: Begin -> AMQPValue
encodeBegin begin = AMQPDescribed
  (AMQPULong 0x00000011)  -- descriptor
  (AMQPList
    [ optionalField (beginRemoteChannel begin) AMQPUShort
    , AMQPUInt (beginNextOutgoingId begin)
    , AMQPUInt (beginIncomingWindow begin)
    , AMQPUInt (beginOutgoingWindow begin)
    , optionalField (beginHandleMax begin) AMQPUInt
    , optionalField (beginOfferedCapabilities begin) listToAMQP
    , optionalField (beginDesiredCapabilities begin) listToAMQP
    , optionalField (beginProperties begin) mapToAMQP
    ])

-- Encode Role
encodeRole :: Role -> AMQPValue
encodeRole RoleSender = AMQPBool False
encodeRole RoleReceiver = AMQPBool True

-- Encode SenderSettleMode
encodeSenderSettleMode :: SenderSettleMode -> AMQPValue
encodeSenderSettleMode Unsettled = AMQPUByte 0
encodeSenderSettleMode Settled = AMQPUByte 1
encodeSenderSettleMode Mixed = AMQPUByte 2

-- Encode ReceiverSettleMode
encodeReceiverSettleMode :: ReceiverSettleMode -> AMQPValue
encodeReceiverSettleMode First = AMQPUByte 0
encodeReceiverSettleMode Second = AMQPUByte 1

-- Encode Terminus
encodeTerminus :: Terminus -> AMQPValue
encodeTerminus terminus = AMQPList
  [ optionalField (terminusAddress terminus) AMQPString
  , optionalField (terminusDurable terminus) AMQPUInt
  , optionalField (terminusExpiryPolicy terminus) AMQPSymbol
  , optionalField (terminusTimeout terminus) AMQPUInt
  , optionalField (terminusDynamic terminus) AMQPBool
  , optionalField (terminusDynamicNodeProperties terminus) mapToAMQP
  , optionalField (terminusCapabilities terminus) listToAMQP
  ]

-- Encode Source (descriptor 0x00000028)
encodeSource :: Source -> AMQPValue
encodeSource (Source terminus) = AMQPDescribed
  (AMQPULong 0x00000028)
  (encodeTerminus terminus)

-- Encode Target (descriptor 0x00000029)
encodeTarget :: Target -> AMQPValue
encodeTarget (Target terminus) = AMQPDescribed
  (AMQPULong 0x00000029)
  (encodeTerminus terminus)

-- Encode ATTACH as described list
encodeAttach :: Attach -> AMQPValue
encodeAttach attach = AMQPDescribed
  (AMQPULong 0x00000012)  -- descriptor
  (AMQPList
    [ AMQPString (attachName attach)
    , AMQPUInt (attachHandle attach)
    , encodeRole (attachRole attach)
    , optionalField (attachSndSettleMode attach) encodeSenderSettleMode
    , optionalField (attachRcvSettleMode attach) encodeReceiverSettleMode
    , optionalField (attachSource attach) encodeSource
    , optionalField (attachTarget attach) encodeTarget
    , optionalField (attachUnsettled attach) mapToAMQP
    , optionalField (attachIncompleteUnsettled attach) AMQPBool
    , optionalField (attachInitialDeliveryCount attach) AMQPUInt
    , optionalField (attachMaxMessageSize attach) AMQPULong
    , optionalField (attachOfferedCapabilities attach) listToAMQP
    , optionalField (attachDesiredCapabilities attach) listToAMQP
    , optionalField (attachProperties attach) mapToAMQP
    ])

-- Encode FLOW as described list
encodeFlow :: Flow -> AMQPValue
encodeFlow flow = AMQPDescribed
  (AMQPULong 0x00000013)  -- descriptor
  (AMQPList
    [ optionalField (flowNextIncomingId flow) AMQPUInt
    , AMQPUInt (flowIncomingWindow flow)
    , AMQPUInt (flowNextOutgoingId flow)
    , AMQPUInt (flowOutgoingWindow flow)
    , optionalField (flowHandle flow) AMQPUInt
    , optionalField (flowDeliveryCount flow) AMQPUInt
    , optionalField (flowLinkCredit flow) AMQPUInt
    , optionalField (flowAvailable flow) AMQPUInt
    , optionalField (flowDrain flow) AMQPBool
    , optionalField (flowEcho flow) AMQPBool
    , optionalField (flowProperties flow) mapToAMQP
    ])

-- Encode TRANSFER as described list
encodeTransfer :: Transfer -> AMQPValue
encodeTransfer transfer = AMQPDescribed
  (AMQPULong 0x00000014)  -- descriptor
  (AMQPList
    [ AMQPUInt (transferHandle transfer)
    , optionalField (transferDeliveryId transfer) AMQPUInt
    , optionalField (transferDeliveryTag transfer) AMQPBinary
    , optionalField (transferMessageFormat transfer) AMQPUInt
    , optionalField (transferSettled transfer) AMQPBool
    , optionalField (transferMore transfer) AMQPBool
    , optionalField (transferRcvSettleMode transfer) encodeReceiverSettleMode
    , optionalField (transferState transfer) id
    , optionalField (transferResume transfer) AMQPBool
    , optionalField (transferAborted transfer) AMQPBool
    , optionalField (transferBatchable transfer) AMQPBool
    ])

-- Encode DISPOSITION as described list
encodeDisposition :: Disposition -> AMQPValue
encodeDisposition disposition = AMQPDescribed
  (AMQPULong 0x00000015)  -- descriptor
  (AMQPList
    [ encodeRole (dispositionRole disposition)
    , AMQPUInt (dispositionFirst disposition)
    , optionalField (dispositionLast disposition) AMQPUInt
    , optionalField (dispositionSettled disposition) AMQPBool
    , optionalField (dispositionState disposition) id
    , optionalField (dispositionBatchable disposition) AMQPBool
    ])

-- Encode Error (descriptor 0x0000001d)
encodeError :: Error -> AMQPValue
encodeError err = AMQPDescribed
  (AMQPULong 0x0000001d)  -- descriptor
  (AMQPList
    [ AMQPSymbol (errorCondition err)
    , optionalField (errorDescription err) AMQPString
    , optionalField (errorInfo err) mapToAMQP
    ])

-- Encode DETACH as described list
encodeDetach :: Detach -> AMQPValue
encodeDetach detach = AMQPDescribed
  (AMQPULong 0x00000016)  -- descriptor
  (AMQPList
    [ AMQPUInt (detachHandle detach)
    , optionalField (detachClosed detach) AMQPBool
    , optionalField (detachError detach) encodeError
    ])

-- Encode END as described list
encodeEnd :: End -> AMQPValue
encodeEnd end = AMQPDescribed
  (AMQPULong 0x00000017)  -- descriptor
  (AMQPList
    [ optionalField (endError end) encodeError
    ])

-- Encode CLOSE as described list
encodeClose :: Close -> AMQPValue
encodeClose close = AMQPDescribed
  (AMQPULong 0x00000018)  -- descriptor
  (AMQPList
    [ optionalField (closeError close) encodeError
    ])

-- | Decode a performative from a described type
getPerformative :: Get Performative
getPerformative = do
  value <- getAMQPValue
  case value of
    AMQPDescribed descriptor fields -> decodePerformative descriptor fields
    _ -> fail "getPerformative: expected described type"

-- Decode based on descriptor
decodePerformative :: AMQPValue -> AMQPValue -> Get Performative
decodePerformative (AMQPULong descriptor) fields =
  case descriptor of
    0x00000010 -> PerformativeOpen <$> decodeOpen fields
    0x00000011 -> PerformativeBegin <$> decodeBegin fields
    0x00000012 -> PerformativeAttach <$> decodeAttach fields
    0x00000013 -> PerformativeFlow <$> decodeFlow fields
    0x00000014 -> PerformativeTransfer <$> decodeTransfer fields
    0x00000015 -> PerformativeDisposition <$> decodeDisposition fields
    0x00000016 -> PerformativeDetach <$> decodeDetach fields
    0x00000017 -> PerformativeEnd <$> decodeEnd fields
    0x00000018 -> PerformativeClose <$> decodeClose fields
    _ -> fail $ "decodePerformative: unknown descriptor " ++ show descriptor
decodePerformative _ _ = fail "decodePerformative: descriptor must be ulong"

-- Helper to extract field from list
getField :: [AMQPValue] -> Int -> Maybe AMQPValue
getField fields idx
  | idx >= length fields = Nothing
  | otherwise = case fields !! idx of
      AMQPNull -> Nothing
      val -> Just val

-- Helper to get required field
getRequiredField :: String -> [AMQPValue] -> Int -> Get AMQPValue
getRequiredField name fields idx =
  case getField fields idx of
    Nothing -> fail $ "getRequiredField: missing " ++ name
    Just val -> return val

-- Decode OPEN
decodeOpen :: AMQPValue -> Get Open
decodeOpen (AMQPList fields) = do
  containerId <- case getField fields 0 of
    Just (AMQPString s) -> return s
    _ -> fail "decodeOpen: missing or invalid container-id"

  let hostname = case getField fields 1 of
        Just (AMQPString s) -> Just s
        _ -> Nothing

  let maxFrameSize = case getField fields 2 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  let channelMax = case getField fields 3 of
        Just (AMQPUShort n) -> Just n
        _ -> Nothing

  let idleTimeOut = case getField fields 4 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  let outgoingLocales = case getField fields 5 of
        Just (AMQPList xs) -> Just (map (\(AMQPSymbol s) -> s) xs)
        _ -> Nothing

  let incomingLocales = case getField fields 6 of
        Just (AMQPList xs) -> Just (map (\(AMQPSymbol s) -> s) xs)
        _ -> Nothing

  let offeredCapabilities = case getField fields 7 of
        Just (AMQPList xs) -> Just (map (\(AMQPSymbol s) -> s) xs)
        _ -> Nothing

  let desiredCapabilities = case getField fields 8 of
        Just (AMQPList xs) -> Just (map (\(AMQPSymbol s) -> s) xs)
        _ -> Nothing

  let properties = case getField fields 9 of
        Just (AMQPMap m) -> Just m
        _ -> Nothing

  return $ Open
    { openContainerId = containerId
    , openHostname = hostname
    , openMaxFrameSize = maxFrameSize
    , openChannelMax = channelMax
    , openIdleTimeOut = idleTimeOut
    , openOutgoingLocales = outgoingLocales
    , openIncomingLocales = incomingLocales
    , openOfferedCapabilities = offeredCapabilities
    , openDesiredCapabilities = desiredCapabilities
    , openProperties = properties
    }
decodeOpen _ = fail "decodeOpen: expected list"

-- Decode BEGIN
decodeBegin :: AMQPValue -> Get Begin
decodeBegin (AMQPList fields) = do
  let remoteChannel = case getField fields 0 of
        Just (AMQPUShort n) -> Just n
        _ -> Nothing

  nextOutgoingId <- case getField fields 1 of
    Just (AMQPUInt n) -> return n
    _ -> fail "decodeBegin: missing next-outgoing-id"

  incomingWindow <- case getField fields 2 of
    Just (AMQPUInt n) -> return n
    _ -> fail "decodeBegin: missing incoming-window"

  outgoingWindow <- case getField fields 3 of
    Just (AMQPUInt n) -> return n
    _ -> fail "decodeBegin: missing outgoing-window"

  let handleMax = case getField fields 4 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  let offeredCapabilities = case getField fields 5 of
        Just (AMQPList xs) -> Just (map (\(AMQPSymbol s) -> s) xs)
        _ -> Nothing

  let desiredCapabilities = case getField fields 6 of
        Just (AMQPList xs) -> Just (map (\(AMQPSymbol s) -> s) xs)
        _ -> Nothing

  let properties = case getField fields 7 of
        Just (AMQPMap m) -> Just m
        _ -> Nothing

  return $ Begin
    { beginRemoteChannel = remoteChannel
    , beginNextOutgoingId = nextOutgoingId
    , beginIncomingWindow = incomingWindow
    , beginOutgoingWindow = outgoingWindow
    , beginHandleMax = handleMax
    , beginOfferedCapabilities = offeredCapabilities
    , beginDesiredCapabilities = desiredCapabilities
    , beginProperties = properties
    }
decodeBegin _ = fail "decodeBegin: expected list"

-- Decode Role
decodeRole :: AMQPValue -> Get Role
decodeRole (AMQPBool False) = return RoleSender
decodeRole (AMQPBool True) = return RoleReceiver
decodeRole _ = fail "decodeRole: expected boolean"

-- Decode SenderSettleMode
decodeSenderSettleMode :: AMQPValue -> Get SenderSettleMode
decodeSenderSettleMode (AMQPUByte 0) = return Unsettled
decodeSenderSettleMode (AMQPUByte 1) = return Settled
decodeSenderSettleMode (AMQPUByte 2) = return Mixed
decodeSenderSettleMode _ = fail "decodeSenderSettleMode: invalid value"

-- Decode ReceiverSettleMode
decodeReceiverSettleMode :: AMQPValue -> Get ReceiverSettleMode
decodeReceiverSettleMode (AMQPUByte 0) = return First
decodeReceiverSettleMode (AMQPUByte 1) = return Second
decodeReceiverSettleMode _ = fail "decodeReceiverSettleMode: invalid value"

-- Decode Terminus
decodeTerminus :: AMQPValue -> Get Terminus
decodeTerminus (AMQPList fields) = do
  let address = case getField fields 0 of
        Just (AMQPString s) -> Just s
        _ -> Nothing

  let durable = case getField fields 1 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  let expiryPolicy = case getField fields 2 of
        Just (AMQPSymbol s) -> Just s
        _ -> Nothing

  let timeout = case getField fields 3 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  let dynamic = case getField fields 4 of
        Just (AMQPBool b) -> Just b
        _ -> Nothing

  let dynamicNodeProperties = case getField fields 5 of
        Just (AMQPMap m) -> Just m
        _ -> Nothing

  let capabilities = case getField fields 6 of
        Just (AMQPList xs) -> Just (map (\(AMQPSymbol s) -> s) xs)
        _ -> Nothing

  return $ Terminus
    { terminusAddress = address
    , terminusDurable = durable
    , terminusExpiryPolicy = expiryPolicy
    , terminusTimeout = timeout
    , terminusDynamic = dynamic
    , terminusDynamicNodeProperties = dynamicNodeProperties
    , terminusCapabilities = capabilities
    }
decodeTerminus _ = fail "decodeTerminus: expected list"

-- Decode Source
decodeSource :: AMQPValue -> Get Source
decodeSource (AMQPDescribed (AMQPULong 0x00000028) value) = Source <$> decodeTerminus value
decodeSource _ = fail "decodeSource: expected described type with descriptor 0x28"

-- Decode Target
decodeTarget :: AMQPValue -> Get Target
decodeTarget (AMQPDescribed (AMQPULong 0x00000029) value) = Target <$> decodeTerminus value
decodeTarget _ = fail "decodeTarget: expected described type with descriptor 0x29"

-- Decode ATTACH
decodeAttach :: AMQPValue -> Get Attach
decodeAttach (AMQPList fields) = do
  name <- case getField fields 0 of
    Just (AMQPString s) -> return s
    _ -> fail "decodeAttach: missing name"

  handle <- case getField fields 1 of
    Just (AMQPUInt n) -> return n
    _ -> fail "decodeAttach: missing handle"

  role <- case getField fields 2 of
    Just r -> decodeRole r
    _ -> fail "decodeAttach: missing role"

  sndSettleMode <- case getField fields 3 of
    Just val -> Just <$> decodeSenderSettleMode val
    Nothing -> return Nothing

  rcvSettleMode <- case getField fields 4 of
    Just val -> Just <$> decodeReceiverSettleMode val
    Nothing -> return Nothing

  source <- case getField fields 5 of
    Just val -> Just <$> decodeSource val
    Nothing -> return Nothing

  target <- case getField fields 6 of
    Just val -> Just <$> decodeTarget val
    Nothing -> return Nothing

  let unsettled = case getField fields 7 of
        Just (AMQPMap m) -> Just m
        _ -> Nothing

  let incompleteUnsettled = case getField fields 8 of
        Just (AMQPBool b) -> Just b
        _ -> Nothing

  let initialDeliveryCount = case getField fields 9 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  let maxMessageSize = case getField fields 10 of
        Just (AMQPULong n) -> Just n
        _ -> Nothing

  let offeredCapabilities = case getField fields 11 of
        Just (AMQPList xs) -> Just (map (\(AMQPSymbol s) -> s) xs)
        _ -> Nothing

  let desiredCapabilities = case getField fields 12 of
        Just (AMQPList xs) -> Just (map (\(AMQPSymbol s) -> s) xs)
        _ -> Nothing

  let properties = case getField fields 13 of
        Just (AMQPMap m) -> Just m
        _ -> Nothing

  return $ Attach
    { attachName = name
    , attachHandle = handle
    , attachRole = role
    , attachSndSettleMode = sndSettleMode
    , attachRcvSettleMode = rcvSettleMode
    , attachSource = source
    , attachTarget = target
    , attachUnsettled = unsettled
    , attachIncompleteUnsettled = incompleteUnsettled
    , attachInitialDeliveryCount = initialDeliveryCount
    , attachMaxMessageSize = maxMessageSize
    , attachOfferedCapabilities = offeredCapabilities
    , attachDesiredCapabilities = desiredCapabilities
    , attachProperties = properties
    }
decodeAttach _ = fail "decodeAttach: expected list"

-- Decode FLOW
decodeFlow :: AMQPValue -> Get Flow
decodeFlow (AMQPList fields) = do
  let nextIncomingId = case getField fields 0 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  incomingWindow <- case getField fields 1 of
    Just (AMQPUInt n) -> return n
    _ -> fail "decodeFlow: missing incoming-window"

  nextOutgoingId <- case getField fields 2 of
    Just (AMQPUInt n) -> return n
    _ -> fail "decodeFlow: missing next-outgoing-id"

  outgoingWindow <- case getField fields 3 of
    Just (AMQPUInt n) -> return n
    _ -> fail "decodeFlow: missing outgoing-window"

  let handle = case getField fields 4 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  let deliveryCount = case getField fields 5 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  let linkCredit = case getField fields 6 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  let available = case getField fields 7 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  let drain = case getField fields 8 of
        Just (AMQPBool b) -> Just b
        _ -> Nothing

  let echo = case getField fields 9 of
        Just (AMQPBool b) -> Just b
        _ -> Nothing

  let properties = case getField fields 10 of
        Just (AMQPMap m) -> Just m
        _ -> Nothing

  return $ Flow
    { flowNextIncomingId = nextIncomingId
    , flowIncomingWindow = incomingWindow
    , flowNextOutgoingId = nextOutgoingId
    , flowOutgoingWindow = outgoingWindow
    , flowHandle = handle
    , flowDeliveryCount = deliveryCount
    , flowLinkCredit = linkCredit
    , flowAvailable = available
    , flowDrain = drain
    , flowEcho = echo
    , flowProperties = properties
    }
decodeFlow _ = fail "decodeFlow: expected list"

-- Decode TRANSFER
decodeTransfer :: AMQPValue -> Get Transfer
decodeTransfer (AMQPList fields) = do
  handle <- case getField fields 0 of
    Just (AMQPUInt n) -> return n
    _ -> fail "decodeTransfer: missing handle"

  let deliveryId = case getField fields 1 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  let deliveryTag = case getField fields 2 of
        Just (AMQPBinary bs) -> Just bs
        _ -> Nothing

  let messageFormat = case getField fields 3 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  let settled = case getField fields 4 of
        Just (AMQPBool b) -> Just b
        _ -> Nothing

  let more = case getField fields 5 of
        Just (AMQPBool b) -> Just b
        _ -> Nothing

  rcvSettleMode <- case getField fields 6 of
    Just val -> Just <$> decodeReceiverSettleMode val
    Nothing -> return Nothing

  let state = getField fields 7

  let resume = case getField fields 8 of
        Just (AMQPBool b) -> Just b
        _ -> Nothing

  let aborted = case getField fields 9 of
        Just (AMQPBool b) -> Just b
        _ -> Nothing

  let batchable = case getField fields 10 of
        Just (AMQPBool b) -> Just b
        _ -> Nothing

  return $ Transfer
    { transferHandle = handle
    , transferDeliveryId = deliveryId
    , transferDeliveryTag = deliveryTag
    , transferMessageFormat = messageFormat
    , transferSettled = settled
    , transferMore = more
    , transferRcvSettleMode = rcvSettleMode
    , transferState = state
    , transferResume = resume
    , transferAborted = aborted
    , transferBatchable = batchable
    }
decodeTransfer _ = fail "decodeTransfer: expected list"

-- Decode DISPOSITION
decodeDisposition :: AMQPValue -> Get Disposition
decodeDisposition (AMQPList fields) = do
  role <- case getField fields 0 of
    Just r -> decodeRole r
    _ -> fail "decodeDisposition: missing role"

  first <- case getField fields 1 of
    Just (AMQPUInt n) -> return n
    _ -> fail "decodeDisposition: missing first"

  let last = case getField fields 2 of
        Just (AMQPUInt n) -> Just n
        _ -> Nothing

  let settled = case getField fields 3 of
        Just (AMQPBool b) -> Just b
        _ -> Nothing

  let state = getField fields 4

  let batchable = case getField fields 5 of
        Just (AMQPBool b) -> Just b
        _ -> Nothing

  return $ Disposition
    { dispositionRole = role
    , dispositionFirst = first
    , dispositionLast = last
    , dispositionSettled = settled
    , dispositionState = state
    , dispositionBatchable = batchable
    }
decodeDisposition _ = fail "decodeDisposition: expected list"

-- Decode Error
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

-- Decode DETACH
decodeDetach :: AMQPValue -> Get Detach
decodeDetach (AMQPList fields) = do
  handle <- case getField fields 0 of
    Just (AMQPUInt n) -> return n
    _ -> fail "decodeDetach: missing handle"

  let closed = case getField fields 1 of
        Just (AMQPBool b) -> Just b
        _ -> Nothing

  error <- case getField fields 2 of
    Just val -> Just <$> decodeError val
    Nothing -> return Nothing

  return $ Detach
    { detachHandle = handle
    , detachClosed = closed
    , detachError = error
    }
decodeDetach _ = fail "decodeDetach: expected list"

-- Decode END
decodeEnd :: AMQPValue -> Get End
decodeEnd (AMQPList fields) = do
  error <- case getField fields 0 of
    Just val -> Just <$> decodeError val
    Nothing -> return Nothing

  return $ End { endError = error }
decodeEnd _ = fail "decodeEnd: expected list"

-- Decode CLOSE
decodeClose :: AMQPValue -> Get Close
decodeClose (AMQPList fields) = do
  error <- case getField fields 0 of
    Just val -> Just <$> decodeError val
    Nothing -> return Nothing

  return $ Close { closeError = error }
decodeClose _ = fail "decodeClose: expected list"
