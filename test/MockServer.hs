{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Mock AMQP 1.0 server for testing
module MockServer
  ( -- * Server
    MockServer(..)
  , startMockServer
  , stopMockServer
    -- * State
  , MockState(..)
  , MockConnectionState(..)
  , MockSessionState(..)
  , MockLinkState(..)
    -- * Protocol
  , amqpProtocolHeader
  ) where

import Control.Concurrent (ThreadId, forkIO, killThread, myThreadId)
import Control.Concurrent.STM
import Control.Exception (bracket, finally, catch, SomeException)
import Control.Monad (forever, when, forM_)
import Data.Binary.Get (runGet, runGetOrFail, getWord32be)
import Data.Binary.Put (runPut)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Word (Word16, Word32)
import Network.Socket
  ( Socket
  , SocketType(Stream)
  , defaultProtocol
  , accept
  , bind
  , close
  , listen
  , socket
  , withSocketsDo
  , AddrInfo(..)
  , AddrInfoFlag(..)
  , getAddrInfo
  , defaultHints
  , SocketOption(..)
  , setSocketOption
  , socketToHandle
  )
import qualified Network.Socket as Socket
import qualified Network.Socket.ByteString as SBS
import System.IO (Handle, hClose, hSetBuffering, BufferMode(..), IOMode(..))

import Network.AMQP.Transport
import Network.AMQP.Performatives
import Network.AMQP.Messaging (DeliveryState(..), encodeDeliveryState)

-- | AMQP 1.0 protocol header (8 bytes)
-- Format: "AMQP" (0x41 0x4D 0x51 0x50) + protocol-id (0x00) + major (0x01) + minor (0x00) + revision (0x00)
amqpProtocolHeader :: ByteString
amqpProtocolHeader = BS.pack [0x41, 0x4D, 0x51, 0x50, 0x00, 0x01, 0x00, 0x00]

-- | Mock server handle
data MockServer = MockServer
  { mockServerSocket :: Socket
  , mockServerThread :: ThreadId
  , mockServerPort :: Int
  , mockServerState :: TVar MockState
  }

-- | Stored message in a queue
data StoredMessage = StoredMessage
  { storedPayload :: ByteString
  , storedDeliveryTag :: Maybe ByteString
  } deriving (Eq, Show)

-- | Overall mock server state
data MockState = MockState
  { mockConnections :: Map ThreadId MockConnectionState
  }

-- | Per-connection state
data MockConnectionState = MockConnectionState
  { mockConnState :: ConnectionState
  , mockConnSessions :: Map Word16 MockSessionState
  , mockQueues :: Map Text [StoredMessage]
  }

-- | Per-session state
data MockSessionState = MockSessionState
  { mockSessState :: SessionState
  , mockSessLinks :: Map Word32 MockLinkState
  , mockSessNextOutgoingId :: Word32
  , mockSessNextIncomingId :: Word32
  }

-- | Per-link state
data MockLinkState = MockLinkState
  { mockLinkState :: LinkState
  , mockLinkName :: String
  , mockLinkRole :: Role
  , mockLinkTransfers :: [(Word32, ByteString)]  -- (delivery-id, payload)
  , mockLinkTargetAddress :: Maybe Text  -- Target address for sender links
  , mockLinkSourceAddress :: Maybe Text  -- Source address for receiver links
  , mockLinkCredit :: Word32  -- Available link credit
  , mockLinkDeliveryCount :: Word32  -- Delivery count for the link
  }

-- | Start a mock AMQP server on the specified port
-- Returns the mock server handle
startMockServer :: Int -> IO MockServer
startMockServer port = withSocketsDo $ do
  -- Create initial state
  stateVar <- newTVarIO $ MockState { mockConnections = Map.empty }

  -- Get address info for localhost
  let hints = defaultHints { addrFlags = [AI_PASSIVE], addrSocketType = Stream }
  addr:_ <- getAddrInfo (Just hints) (Just "127.0.0.1") (Just (show port))

  -- Create and configure socket
  sock <- socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr)
  setSocketOption sock ReuseAddr 1
  bind sock (addrAddress addr)
  listen sock 5

  -- Start accept loop in background thread
  tid <- forkIO $ acceptLoop sock stateVar

  return $ MockServer
    { mockServerSocket = sock
    , mockServerThread = tid
    , mockServerPort = port
    , mockServerState = stateVar
    }

-- | Stop the mock server
stopMockServer :: MockServer -> IO ()
stopMockServer server = do
  killThread (mockServerThread server)
  close (mockServerSocket server)

-- | Accept loop - accepts connections and spawns handler threads
acceptLoop :: Socket -> TVar MockState -> IO ()
acceptLoop sock stateVar = forever $ do
  (clientSock, _clientAddr) <- accept sock
  -- Spawn a new thread to handle this connection
  tid <- forkIO $ handleConnection clientSock stateVar `finally` close clientSock
  -- Register connection in state
  atomically $ modifyTVar' stateVar $ \s ->
    s { mockConnections = Map.insert tid initialConnectionState (mockConnections s) }
  where
    initialConnectionState = MockConnectionState
      { mockConnState = ConnStart
      , mockConnSessions = Map.empty
      , mockQueues = Map.empty
      }

-- | Handle a single client connection
handleConnection :: Socket -> TVar MockState -> IO ()
handleConnection sock stateVar = do
  -- Convert socket to handle for easier I/O
  handle <- socketToHandle sock ReadWriteMode
  hSetBuffering handle NoBuffering

  -- Protocol header exchange
  protocolHeaderExchange handle stateVar

  -- OPEN/CLOSE handling
  openCloseHandling handle stateVar

  hClose handle

-- | Handle protocol header exchange
protocolHeaderExchange :: Handle -> TVar MockState -> IO ()
protocolHeaderExchange handle stateVar = do
  -- Read 8 bytes for protocol header
  clientHeader <- BS.hGet handle 8

  -- Validate client header
  when (clientHeader == amqpProtocolHeader) $ do
    -- Update state: received header
    updateConnectionState stateVar ConnEvtRecvHeader

    -- Send our protocol header
    BS.hPut handle amqpProtocolHeader

    -- Update state: sent header (after receiving, we're now in HDRExch state)
    -- No need to transition again as receiving header already put us in HDRExch
    return ()

-- | Update connection state based on event
updateConnectionState :: TVar MockState -> ConnectionEvent -> IO ()
updateConnectionState stateVar event = do
  tid <- myThreadId
  atomically $ modifyTVar' stateVar $ \s ->
    case Map.lookup tid (mockConnections s) of
      Nothing -> s
      Just connState ->
        let oldState = mockConnState connState
            newStateE = transitionConnection oldState event
        in case newStateE of
          Left _ -> s  -- Invalid transition, keep old state
          Right newState ->
            let updatedConnState = connState { mockConnState = newState }
            in s { mockConnections = Map.insert tid updatedConnState (mockConnections s) }

-- | Update session state based on event
updateSessionState :: TVar MockState -> Word16 -> SessionEvent -> IO ()
updateSessionState stateVar channel event = do
  tid <- myThreadId
  atomically $ modifyTVar' stateVar $ \s ->
    case Map.lookup tid (mockConnections s) of
      Nothing -> s
      Just connState ->
        case Map.lookup channel (mockConnSessions connState) of
          Nothing -> s
          Just sessState ->
            let oldState = mockSessState sessState
                newStateE = transitionSession oldState event
            in case newStateE of
              Left _ -> s
              Right newState ->
                let updatedSessState = sessState { mockSessState = newState }
                    updatedSessions = Map.insert channel updatedSessState (mockConnSessions connState)
                    updatedConnState = connState { mockConnSessions = updatedSessions }
                in s { mockConnections = Map.insert tid updatedConnState (mockConnections s) }

-- | Update link state based on event
updateLinkState :: TVar MockState -> Word16 -> Word32 -> LinkEvent -> IO ()
updateLinkState stateVar channel handle event = do
  tid <- myThreadId
  atomically $ modifyTVar' stateVar $ \s ->
    case Map.lookup tid (mockConnections s) of
      Nothing -> s
      Just connState ->
        case Map.lookup channel (mockConnSessions connState) of
          Nothing -> s
          Just sessState ->
            case Map.lookup handle (mockSessLinks sessState) of
              Nothing -> s
              Just linkState ->
                let oldState = mockLinkState linkState
                    newStateE = transitionLink oldState event
                in case newStateE of
                  Left _ -> s
                  Right newState ->
                    let updatedLinkState = linkState { mockLinkState = newState }
                        updatedLinks = Map.insert handle updatedLinkState (mockSessLinks sessState)
                        updatedSessState = sessState { mockSessLinks = updatedLinks }
                        updatedSessions = Map.insert channel updatedSessState (mockConnSessions connState)
                        updatedConnState = connState { mockConnSessions = updatedSessions }
                    in s { mockConnections = Map.insert tid updatedConnState (mockConnections s) }

-- | Handle OPEN/CLOSE performatives
openCloseHandling :: Handle -> TVar MockState -> IO ()
openCloseHandling handle stateVar = do
  -- Main frame processing loop
  frameLoop handle stateVar
    `catch` (\(e :: SomeException) -> return ())

-- | Main frame processing loop
frameLoop :: Handle -> TVar MockState -> IO ()
frameLoop handle stateVar = do
  -- Read frame size (4 bytes)
  sizeBytes <- BS.hGet handle 4
  if BS.length sizeBytes < 4
    then return ()  -- Connection closed
    else do
      let size = runGet getWord32be (LBS.fromStrict sizeBytes)
      -- Read rest of frame (size - 4 bytes already read)
      restBytes <- BS.hGet handle (fromIntegral size - 4)
      let frameBytes = sizeBytes <> restBytes

      -- Parse frame
      case runGetOrFail getFrame (LBS.fromStrict frameBytes) of
        Left _ -> return ()  -- Invalid frame
        Right (_, _, frame) -> do
          -- Handle frame
          handleFrame handle stateVar frame
          -- Continue processing
          frameLoop handle stateVar

-- | Handle a single frame
handleFrame :: Handle -> TVar MockState -> Frame -> IO ()
handleFrame handle stateVar frame = do
  -- Parse performative from frame payload
  case runGetOrFail getPerformative (LBS.fromStrict (framePayload frame)) of
    Left _ -> return ()  -- Invalid performative
    Right (remaining, _, perf) -> do
      -- Extract message payload (data after performative) for TRANSFER
      let msgPayload = LBS.toStrict remaining
      handlePerformative handle stateVar (frameChannel frame) perf msgPayload

-- | Handle a performative
handlePerformative :: Handle -> TVar MockState -> Word16 -> Performative -> ByteString -> IO ()
handlePerformative handle stateVar channel perf msgPayload = case perf of
  -- OPEN handling
  PerformativeOpen clientOpen -> do
    updateConnectionState stateVar ConnEvtRecvOpen

    -- Send OPEN response
    let serverOpen = Open
          { openContainerId = "mock-server"
          , openHostname = Nothing
          , openMaxFrameSize = Just 65536
          , openChannelMax = Just 255
          , openIdleTimeOut = Nothing
          , openOutgoingLocales = Nothing
          , openIncomingLocales = Nothing
          , openOfferedCapabilities = Nothing
          , openDesiredCapabilities = Nothing
          , openProperties = Nothing
          }
    sendPerformative handle 0 (PerformativeOpen serverOpen)
    updateConnectionState stateVar ConnEvtSendOpen

  -- CLOSE handling
  PerformativeClose clientClose -> do
    updateConnectionState stateVar ConnEvtRecvClose

    -- Send CLOSE response
    let serverClose = Close { closeError = Nothing }
    sendPerformative handle 0 (PerformativeClose serverClose)
    updateConnectionState stateVar ConnEvtSendClose

  -- BEGIN handling
  PerformativeBegin clientBegin -> do
    -- Create session state if it doesn't exist
    createSessionIfNeeded stateVar channel
    updateSessionState stateVar channel SessEvtRecvBegin

    -- Send BEGIN response
    let serverBegin = Begin
          { beginRemoteChannel = Just channel
          , beginNextOutgoingId = 0
          , beginIncomingWindow = 2048
          , beginOutgoingWindow = 2048
          , beginHandleMax = Just 255
          , beginOfferedCapabilities = Nothing
          , beginDesiredCapabilities = Nothing
          , beginProperties = Nothing
          }
    sendPerformative handle channel (PerformativeBegin serverBegin)
    updateSessionState stateVar channel SessEvtSendBegin

  -- END handling
  PerformativeEnd clientEnd -> do
    updateSessionState stateVar channel SessEvtRecvEnd

    -- Send END response
    let serverEnd = End { endError = Nothing }
    sendPerformative handle channel (PerformativeEnd serverEnd)
    updateSessionState stateVar channel SessEvtSendEnd

  -- ATTACH handling
  PerformativeAttach clientAttach -> do
    -- Extract addresses from source/target
    let targetAddr = case attachTarget clientAttach of
          Just (Target (Terminus { terminusAddress = addr })) -> addr
          _ -> Nothing
    let sourceAddr = case attachSource clientAttach of
          Just (Source (Terminus { terminusAddress = addr })) -> addr
          _ -> Nothing

    -- Create link state if it doesn't exist
    createLinkIfNeeded stateVar channel (attachHandle clientAttach) (attachName clientAttach) (attachRole clientAttach) targetAddr sourceAddr
    updateLinkState stateVar channel (attachHandle clientAttach) LinkEvtRecvAttach

    -- Send ATTACH response (mirror the client's attach but with opposite role)
    let serverRole = case attachRole clientAttach of
          RoleSender -> RoleReceiver
          RoleReceiver -> RoleSender
    let serverAttach = Attach
          { attachName = attachName clientAttach
          , attachHandle = attachHandle clientAttach
          , attachRole = serverRole
          , attachSndSettleMode = attachSndSettleMode clientAttach
          , attachRcvSettleMode = attachRcvSettleMode clientAttach
          , attachSource = attachSource clientAttach
          , attachTarget = attachTarget clientAttach
          , attachUnsettled = Nothing
          , attachIncompleteUnsettled = Nothing
          , attachInitialDeliveryCount = if serverRole == RoleReceiver then Just 0 else Nothing
          , attachMaxMessageSize = Nothing
          , attachOfferedCapabilities = Nothing
          , attachDesiredCapabilities = Nothing
          , attachProperties = Nothing
          }
    sendPerformative handle channel (PerformativeAttach serverAttach)
    updateLinkState stateVar channel (attachHandle clientAttach) LinkEvtSendAttach

    -- If client is a receiver (mock is sender), deliver queued messages
    when (attachRole clientAttach == RoleReceiver) $ do
      deliverQueuedMessages handle stateVar channel (attachHandle clientAttach)

  -- DETACH handling
  PerformativeDetach clientDetach -> do
    updateLinkState stateVar channel (detachHandle clientDetach) LinkEvtRecvDetach

    -- Send DETACH response
    let serverDetach = Detach
          { detachHandle = detachHandle clientDetach
          , detachClosed = detachClosed clientDetach
          , detachError = Nothing
          }
    sendPerformative handle channel (PerformativeDetach serverDetach)
    updateLinkState stateVar channel (detachHandle clientDetach) LinkEvtSendDetach

  -- TRANSFER handling
  PerformativeTransfer transfer -> do
    -- Store the transfer in link state with actual message payload
    storeTransfer stateVar channel (transferHandle transfer) (transferDeliveryId transfer) msgPayload

    -- Send DISPOSITION response if delivery-id is present
    case transferDeliveryId transfer of
      Just deliveryId -> do
        let disposition = Disposition
              { dispositionRole = RoleReceiver  -- Mock is receiver
              , dispositionFirst = deliveryId
              , dispositionLast = Nothing
              , dispositionSettled = Just True
              , dispositionState = Just (encodeDeliveryState StateAccepted)
              , dispositionBatchable = Nothing
              }
        sendPerformative handle channel (PerformativeDisposition disposition)
      Nothing -> return ()

  -- FLOW handling
  PerformativeFlow clientFlow -> do
    -- Update link credit if this is a link flow (handle is present)
    case flowHandle clientFlow of
      Just linkHandle -> do
        -- Update link credit
        updateLinkCredit stateVar channel linkHandle (flowLinkCredit clientFlow)
      Nothing -> return ()  -- Session-level flow, ignore for now

  _ -> return ()  -- Ignore other performatives for now

-- | Send a performative on a channel
sendPerformative :: Handle -> Word16 -> Performative -> IO ()
sendPerformative handle channel perf = do
  let payload = LBS.toStrict $ runPut (putPerformative perf)
  let frame = Frame AMQPFrameType channel payload
  let frameBytes = LBS.toStrict $ runPut (putFrame frame)
  BS.hPut handle frameBytes

-- | Create session state if it doesn't exist
createSessionIfNeeded :: TVar MockState -> Word16 -> IO ()
createSessionIfNeeded stateVar channel = do
  tid <- myThreadId
  atomically $ modifyTVar' stateVar $ \s ->
    case Map.lookup tid (mockConnections s) of
      Nothing -> s
      Just connState ->
        if Map.member channel (mockConnSessions connState)
          then s
          else
            let newSessState = MockSessionState
                  { mockSessState = SessUnmapped
                  , mockSessLinks = Map.empty
                  , mockSessNextOutgoingId = 0
                  , mockSessNextIncomingId = 0
                  }
                updatedSessions = Map.insert channel newSessState (mockConnSessions connState)
                updatedConnState = connState { mockConnSessions = updatedSessions }
            in s { mockConnections = Map.insert tid updatedConnState (mockConnections s) }

-- | Create link state if it doesn't exist
createLinkIfNeeded :: TVar MockState -> Word16 -> Word32 -> Text -> Role -> Maybe Text -> Maybe Text -> IO ()
createLinkIfNeeded stateVar channel handle name role targetAddr sourceAddr = do
  tid <- myThreadId
  atomically $ modifyTVar' stateVar $ \s ->
    case Map.lookup tid (mockConnections s) of
      Nothing -> s
      Just connState ->
        case Map.lookup channel (mockConnSessions connState) of
          Nothing -> s
          Just sessState ->
            if Map.member handle (mockSessLinks sessState)
              then s
              else
                let newLinkState = MockLinkState
                      { mockLinkState = LinkDetached
                      , mockLinkName = T.unpack name
                      , mockLinkRole = role
                      , mockLinkTransfers = []
                      , mockLinkTargetAddress = targetAddr
                      , mockLinkSourceAddress = sourceAddr
                      , mockLinkCredit = 0
                      , mockLinkDeliveryCount = 0
                      }
                    updatedLinks = Map.insert handle newLinkState (mockSessLinks sessState)
                    updatedSessState = sessState { mockSessLinks = updatedLinks }
                    updatedSessions = Map.insert channel updatedSessState (mockConnSessions connState)
                    updatedConnState = connState { mockConnSessions = updatedSessions }
                in s { mockConnections = Map.insert tid updatedConnState (mockConnections s) }

-- | Deliver queued messages to a receiver link
deliverQueuedMessages :: Handle -> TVar MockState -> Word16 -> Word32 -> IO ()
deliverQueuedMessages handle stateVar channel linkHandle = do
  tid <- myThreadId
  -- Get source address and queued messages
  (sourceAddr, messages, nextDeliveryId) <- atomically $ do
    s <- readTVar stateVar
    case Map.lookup tid (mockConnections s) of
      Nothing -> return (Nothing, [], 0)
      Just connState ->
        case Map.lookup channel (mockConnSessions connState) of
          Nothing -> return (Nothing, [], 0)
          Just sessState ->
            case Map.lookup linkHandle (mockSessLinks sessState) of
              Nothing -> return (Nothing, [], 0)
              Just linkState -> do
                let addr = mockLinkSourceAddress linkState
                let msgs = case addr of
                      Just a -> Map.findWithDefault [] a (mockQueues connState)
                      Nothing -> []
                let nextId = mockSessNextOutgoingId sessState
                return (addr, msgs, nextId)

  -- Send each message as a TRANSFER
  forM_ (zip [nextDeliveryId..] messages) $ \(deliveryId, msg) -> do
    let transfer = Transfer
          { transferHandle = linkHandle
          , transferDeliveryId = Just deliveryId
          , transferDeliveryTag = storedDeliveryTag msg
          , transferMessageFormat = Just 0
          , transferSettled = Just False
          , transferMore = Just False
          , transferRcvSettleMode = Nothing
          , transferState = Nothing
          , transferResume = Nothing
          , transferAborted = Nothing
          , transferBatchable = Nothing
          }
    -- Send TRANSFER performative + message payload in one frame
    let transferBytes = LBS.toStrict $ runPut (putPerformative (PerformativeTransfer transfer))
    let payload = transferBytes <> storedPayload msg
    let frame = Frame AMQPFrameType channel payload
    let frameBytes = LBS.toStrict $ runPut (putFrame frame)
    BS.hPut handle frameBytes

-- | Update link credit based on FLOW performative
updateLinkCredit :: TVar MockState -> Word16 -> Word32 -> Maybe Word32 -> IO ()
updateLinkCredit stateVar channel linkHandle mCredit = do
  tid <- myThreadId
  atomically $ modifyTVar' stateVar $ \s ->
    case Map.lookup tid (mockConnections s) of
      Nothing -> s
      Just connState ->
        case Map.lookup channel (mockConnSessions connState) of
          Nothing -> s
          Just sessState ->
            case Map.lookup linkHandle (mockSessLinks sessState) of
              Nothing -> s
              Just linkState ->
                let credit = maybe 0 id mCredit
                    updatedLinkState = linkState { mockLinkCredit = credit }
                    updatedLinks = Map.insert linkHandle updatedLinkState (mockSessLinks sessState)
                    updatedSessState = sessState { mockSessLinks = updatedLinks }
                    updatedSessions = Map.insert channel updatedSessState (mockConnSessions connState)
                    updatedConnState = connState { mockConnSessions = updatedSessions }
                in s { mockConnections = Map.insert tid updatedConnState (mockConnections s) }

-- | Store a received transfer in link state and message queue
storeTransfer :: TVar MockState -> Word16 -> Word32 -> Maybe Word32 -> ByteString -> IO ()
storeTransfer stateVar channel linkHandle mDeliveryId payload = do
  tid <- myThreadId
  atomically $ modifyTVar' stateVar $ \s ->
    case Map.lookup tid (mockConnections s) of
      Nothing -> s
      Just connState ->
        case Map.lookup channel (mockConnSessions connState) of
          Nothing -> s
          Just sessState ->
            case Map.lookup linkHandle (mockSessLinks sessState) of
              Nothing -> s
              Just linkState ->
                let deliveryId = maybe 0 id mDeliveryId
                    newTransfers = mockLinkTransfers linkState ++ [(deliveryId, payload)]
                    updatedLinkState = linkState { mockLinkTransfers = newTransfers }
                    updatedLinks = Map.insert linkHandle updatedLinkState (mockSessLinks sessState)
                    updatedSessState = sessState { mockSessLinks = updatedLinks }
                    updatedSessions = Map.insert channel updatedSessState (mockConnSessions connState)

                    -- Store message in queue if target address exists
                    updatedConnState = case mockLinkTargetAddress linkState of
                      Just addr ->
                        let storedMsg = StoredMessage
                              { storedPayload = payload
                              , storedDeliveryTag = Nothing
                              }
                            currentQueue = Map.findWithDefault [] addr (mockQueues connState)
                            updatedQueue = currentQueue ++ [storedMsg]
                            updatedQueues = Map.insert addr updatedQueue (mockQueues connState)
                        in connState { mockConnSessions = updatedSessions, mockQueues = updatedQueues }
                      Nothing -> connState { mockConnSessions = updatedSessions }
                in s { mockConnections = Map.insert tid updatedConnState (mockConnections s) }
