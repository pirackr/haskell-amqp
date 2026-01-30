{-# LANGUAGE OverloadedStrings #-}

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
  ) where

import Control.Concurrent (ThreadId, forkIO, killThread)
import Control.Concurrent.STM
import Control.Exception (bracket, finally, catch, SomeException)
import Control.Monad (forever, when)
import Data.Binary.Get (runGet, runGetOrFail)
import Data.Binary.Put (runPut)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
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
  )
import qualified Network.Socket as Socket
import qualified Network.Socket.ByteString as SBS
import System.IO (Handle, hClose, hSetBuffering, BufferMode(..))
import Network.Socket (socketToHandle, IOMode(..))

import Network.AMQP.Transport
import Network.AMQP.Performatives

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

-- | Overall mock server state
data MockState = MockState
  { mockConnections :: Map ThreadId MockConnectionState
  }

-- | Per-connection state
data MockConnectionState = MockConnectionState
  { mockConnState :: ConnectionState
  , mockConnSessions :: Map Word16 MockSessionState
  }

-- | Per-session state
data MockSessionState = MockSessionState
  { mockSessState :: SessionState
  , mockSessLinks :: Map Word32 MockLinkState
  }

-- | Per-link state
data MockLinkState = MockLinkState
  { mockLinkState :: LinkState
  , mockLinkName :: String
  , mockLinkRole :: Role
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
    -- TODO: Update connection state

    -- Send our protocol header
    BS.hPut handle amqpProtocolHeader

    -- Update state: sent header
    -- TODO: Update connection state

    return ()

-- | Handle OPEN/CLOSE performatives
openCloseHandling :: Handle -> TVar MockState -> IO ()
openCloseHandling handle stateVar = do
  -- Read frames and handle OPEN/CLOSE
  -- TODO: Implement frame reading and performative handling
  return ()
