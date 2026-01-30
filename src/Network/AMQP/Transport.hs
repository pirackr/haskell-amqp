{-# LANGUAGE OverloadedStrings #-}

-- | AMQP 1.0 transport layer: frames, performatives, state machines.
module Network.AMQP.Transport
  ( -- * Frames
    Frame(..)
  , FrameType(..)
  , putFrame
  , getFrame
    -- * Performatives
  , module Network.AMQP.Performatives
    -- * State Machines
  , ConnectionState(..)
  , SessionState(..)
  , LinkState(..)
  , transitionConnection
  , transitionSession
  , transitionLink
  , StateTransitionError(..)
  ) where

import Network.AMQP.Performatives

import Data.Binary.Get (Get, getWord8, getWord16be, getWord32be, getByteString)
import Data.Binary.Put (Put, putWord8, putWord16be, putWord32be, putByteString)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Word (Word8, Word16, Word32)

-- | AMQP 1.0 frame types as defined in spec section 2.3
data FrameType
  = AMQPFrameType    -- ^ 0x00 - AMQP frame
  | SASLFrameType    -- ^ 0x01 - SASL frame
  deriving (Eq, Show)

-- | Convert FrameType to byte
frameTypeToByte :: FrameType -> Word8
frameTypeToByte AMQPFrameType = 0x00
frameTypeToByte SASLFrameType = 0x01

-- | Convert byte to FrameType
byteToFrameType :: Word8 -> Maybe FrameType
byteToFrameType 0x00 = Just AMQPFrameType
byteToFrameType 0x01 = Just SASLFrameType
byteToFrameType _    = Nothing

-- | AMQP 1.0 frame structure
-- Frame header is 8 bytes:
--   SIZE (4 bytes) - includes header size
--   DOFF (1 byte) - data offset in 4-byte units, minimum is 2 (8 bytes)
--   TYPE (1 byte) - frame type
--   CHANNEL (2 bytes) - channel number
--   Extended header (optional, not yet implemented)
--   Payload (variable)
data Frame = Frame
  { frameType    :: !FrameType
  , frameChannel :: !Word16
  , framePayload :: !ByteString
  } deriving (Eq, Show)

-- | Encode a frame to binary format
-- Frame format:
--   SIZE (4 bytes, big-endian) - total frame size including header
--   DOFF (1 byte) - data offset in 4-byte units (minimum 2 = 8 bytes header)
--   TYPE (1 byte) - frame type
--   CHANNEL (2 bytes, big-endian) - channel number
--   PAYLOAD (variable)
putFrame :: Frame -> Put
putFrame (Frame ftype channel payload) = do
  let doff = 2  -- 2 * 4 = 8 bytes header (no extended header)
      payloadSize = BS.length payload
      totalSize = 8 + payloadSize  -- header (8 bytes) + payload
  putWord32be (fromIntegral totalSize)
  putWord8 doff
  putWord8 (frameTypeToByte ftype)
  putWord16be channel
  putByteString payload

-- | Decode a frame from binary format
-- Returns Nothing if the frame is incomplete or malformed
getFrame :: Get Frame
getFrame = do
  size <- getWord32be
  doff <- getWord8

  -- Validate DOFF (minimum is 2, which gives 8-byte header)
  if doff < 2
    then fail "getFrame: invalid DOFF (must be >= 2)"
    else return ()

  -- Read frame type
  typeCode <- getWord8
  ftype <- case byteToFrameType typeCode of
    Just t  -> return t
    Nothing -> fail $ "getFrame: unknown frame type " ++ show typeCode

  -- Read channel
  channel <- getWord16be

  -- Calculate payload size
  let headerSize = fromIntegral doff * 4  -- DOFF is in 4-byte units
      payloadSize = fromIntegral size - headerSize

  -- Validate size
  if payloadSize < 0
    then fail "getFrame: invalid frame size"
    else return ()

  -- Skip extended header if present (DOFF > 2)
  if doff > 2
    then do
      let extendedHeaderSize = headerSize - 8
      _ <- getByteString extendedHeaderSize
      return ()
    else return ()

  -- Read payload
  payload <- getByteString payloadSize

  return $ Frame ftype channel payload

-- -----------------------------------------------------------------------------
-- State Machines
-- -----------------------------------------------------------------------------

-- | Connection state machine (spec section 2.4.1)
-- Represents the lifecycle of an AMQP connection
data ConnectionState
  = ConnStart      -- ^ Initial state before any headers exchanged
  | ConnHDRSent    -- ^ Protocol header sent, awaiting peer's header
  | ConnHDRExch    -- ^ Headers exchanged, awaiting OPEN
  | ConnOpenSent   -- ^ OPEN sent, awaiting peer's OPEN
  | ConnOpenRecv   -- ^ OPEN received, need to send OPEN
  | ConnOpened     -- ^ Connection established (both OPENs exchanged)
  | ConnCloseSent  -- ^ CLOSE sent, awaiting peer's CLOSE
  | ConnCloseRecv  -- ^ CLOSE received, need to send CLOSE
  | ConnEnd        -- ^ Connection closed (terminal state)
  deriving (Eq, Show)

-- | Session state machine (spec section 2.5.1)
-- Represents the lifecycle of an AMQP session
data SessionState
  = SessUnmapped   -- ^ Session not yet attached to a channel
  | SessBeginSent  -- ^ BEGIN sent, awaiting peer's BEGIN
  | SessBeginRecv  -- ^ BEGIN received, need to send BEGIN
  | SessMapped     -- ^ Session established (both BEGINs exchanged)
  | SessEndSent    -- ^ END sent, awaiting peer's END
  | SessEndRecv    -- ^ END received, need to send END
  deriving (Eq, Show)

-- | Link state machine (spec section 2.6.1)
-- Represents the lifecycle of an AMQP link
data LinkState
  = LinkDetached     -- ^ Link not yet attached
  | LinkAttachSent   -- ^ ATTACH sent, awaiting peer's ATTACH
  | LinkAttachRecv   -- ^ ATTACH received, need to send ATTACH
  | LinkAttached     -- ^ Link established (both ATTACHs exchanged)
  | LinkDetachSent   -- ^ DETACH sent, awaiting peer's DETACH
  | LinkDetachRecv   -- ^ DETACH received, need to send DETACH
  deriving (Eq, Show)

-- | Events that can trigger state transitions
data ConnectionEvent
  = ConnEvtSendHeader      -- ^ Send protocol header
  | ConnEvtRecvHeader      -- ^ Receive protocol header
  | ConnEvtSendOpen        -- ^ Send OPEN performative
  | ConnEvtRecvOpen        -- ^ Receive OPEN performative
  | ConnEvtSendClose       -- ^ Send CLOSE performative
  | ConnEvtRecvClose       -- ^ Receive CLOSE performative
  deriving (Eq, Show)

data SessionEvent
  = SessEvtSendBegin       -- ^ Send BEGIN performative
  | SessEvtRecvBegin       -- ^ Receive BEGIN performative
  | SessEvtSendEnd         -- ^ Send END performative
  | SessEvtRecvEnd         -- ^ Receive END performative
  deriving (Eq, Show)

data LinkEvent
  = LinkEvtSendAttach      -- ^ Send ATTACH performative
  | LinkEvtRecvAttach      -- ^ Receive ATTACH performative
  | LinkEvtSendDetach      -- ^ Send DETACH performative
  | LinkEvtRecvDetach      -- ^ Receive DETACH performative
  deriving (Eq, Show)

-- | Error type for invalid state transitions
data StateTransitionError
  = InvalidConnectionTransition ConnectionState ConnectionEvent
  | InvalidSessionTransition SessionState SessionEvent
  | InvalidLinkTransition LinkState LinkEvent
  deriving (Eq, Show)

-- -----------------------------------------------------------------------------
-- State Transition Functions
-- -----------------------------------------------------------------------------

-- | Transition connection state based on an event
-- Returns Left error if transition is invalid, Right newState if valid
transitionConnection :: ConnectionState -> ConnectionEvent -> Either StateTransitionError ConnectionState
transitionConnection ConnStart ConnEvtSendHeader = Right ConnHDRSent
transitionConnection ConnStart ConnEvtRecvHeader = Right ConnHDRExch

transitionConnection ConnHDRSent ConnEvtRecvHeader = Right ConnHDRExch

transitionConnection ConnHDRExch ConnEvtSendOpen = Right ConnOpenSent
transitionConnection ConnHDRExch ConnEvtRecvOpen = Right ConnOpenRecv

transitionConnection ConnOpenSent ConnEvtRecvOpen = Right ConnOpened

transitionConnection ConnOpenRecv ConnEvtSendOpen = Right ConnOpened

transitionConnection ConnOpened ConnEvtSendClose = Right ConnCloseSent
transitionConnection ConnOpened ConnEvtRecvClose = Right ConnCloseRecv

transitionConnection ConnCloseSent ConnEvtRecvClose = Right ConnEnd

transitionConnection ConnCloseRecv ConnEvtSendClose = Right ConnEnd

-- Invalid transitions
transitionConnection state event = Left (InvalidConnectionTransition state event)

-- | Transition session state based on an event
-- Returns Left error if transition is invalid, Right newState if valid
transitionSession :: SessionState -> SessionEvent -> Either StateTransitionError SessionState
transitionSession SessUnmapped SessEvtSendBegin = Right SessBeginSent
transitionSession SessUnmapped SessEvtRecvBegin = Right SessBeginRecv

transitionSession SessBeginSent SessEvtRecvBegin = Right SessMapped

transitionSession SessBeginRecv SessEvtSendBegin = Right SessMapped

transitionSession SessMapped SessEvtSendEnd = Right SessEndSent
transitionSession SessMapped SessEvtRecvEnd = Right SessEndRecv

transitionSession SessEndSent SessEvtRecvEnd = Right SessUnmapped

transitionSession SessEndRecv SessEvtSendEnd = Right SessUnmapped

-- Invalid transitions
transitionSession state event = Left (InvalidSessionTransition state event)

-- | Transition link state based on an event
-- Returns Left error if transition is invalid, Right newState if valid
transitionLink :: LinkState -> LinkEvent -> Either StateTransitionError LinkState
transitionLink LinkDetached LinkEvtSendAttach = Right LinkAttachSent
transitionLink LinkDetached LinkEvtRecvAttach = Right LinkAttachRecv

transitionLink LinkAttachSent LinkEvtRecvAttach = Right LinkAttached

transitionLink LinkAttachRecv LinkEvtSendAttach = Right LinkAttached

transitionLink LinkAttached LinkEvtSendDetach = Right LinkDetachSent
transitionLink LinkAttached LinkEvtRecvDetach = Right LinkDetachRecv

transitionLink LinkDetachSent LinkEvtRecvDetach = Right LinkDetached

transitionLink LinkDetachRecv LinkEvtSendDetach = Right LinkDetached

-- Invalid transitions
transitionLink state event = Left (InvalidLinkTransition state event)
