## 1. Project Setup

- [x] 1.1 Create stack.yaml with nix: true and appropriate GHC version
- [x] 1.2 Create package.yaml with library and test targets
- [x] 1.3 Create shell.nix with system dependencies (zlib, etc.)
- [x] 1.4 Create module structure: Network.AMQP.Types, Transport, Connection, Client
- [x] 1.5 Add dependencies: binary, network, async, stm, tasty, QuickCheck

## 2. Types - Primitives

- [x] 2.1 Define AMQPValue ADT for all primitive types (null, bool, integers, floats, string, symbol, binary, uuid, timestamp)
- [x] 2.2 Implement Put instance for null encoding (0x40)
- [x] 2.3 Implement Put instance for boolean encoding (0x41, 0x42)
- [x] 2.4 Implement Put instance for integer types with compact encodings (uint0, smalluint, uint, etc.)
- [x] 2.5 Implement Put instance for string/symbol with str8/str32 encodings
- [x] 2.6 Implement Put instance for binary with vbin8/vbin32 encodings
- [x] 2.7 Implement Put instance for uuid, timestamp, float, double
- [x] 2.8 Implement Get instance for null decoding
- [x] 2.9 Implement Get instance for boolean decoding
- [x] 2.10 Implement Get instance for integer types
- [x] 2.11 Implement Get instance for string/symbol/binary
- [x] 2.12 Implement Get instance for uuid, timestamp, float, double
- [x] 2.13 Write QuickCheck roundtrip tests for all primitive types

## 3. Types - Composites

- [x] 3.1 Implement Put instance for list (list0, list8, list32)
- [ ] 3.2 Implement Put instance for map (map8, map32)
- [ ] 3.3 Implement Put instance for array (array8, array32)
- [x] 3.4 Implement Get instance for list
- [ ] 3.5 Implement Get instance for map
- [ ] 3.6 Implement Get instance for array
- [ ] 3.7 Write QuickCheck roundtrip tests for composite types
- [ ] 3.8 Write tests for nested structures (list containing list)

## 4. Types - Described Types

- [ ] 4.1 Define DescribedType wrapper (descriptor + value)
- [ ] 4.2 Implement Put instance for described types (0x00 prefix)
- [ ] 4.3 Implement Get instance for described types
- [ ] 4.4 Write roundtrip tests for described types

## 5. Transport - Frames

- [ ] 5.1 Define Frame data type (size, doff, type, channel, payload)
- [ ] 5.2 Implement frame parser (Get monad)
- [ ] 5.3 Implement frame builder (Put monad)
- [ ] 5.4 Write tests for frame parsing/building roundtrip
- [ ] 5.5 Write tests for incomplete frame handling

## 6. Transport - Performatives

- [ ] 6.1 Define Performative ADT (Open, Begin, Attach, Flow, Transfer, Disposition, Detach, End, Close)
- [ ] 6.2 Define Open fields (container-id, hostname, max-frame-size, channel-max, idle-time-out)
- [ ] 6.3 Define Begin fields (remote-channel, next-outgoing-id, incoming-window, outgoing-window)
- [ ] 6.4 Define Attach fields (name, handle, role, snd-settle-mode, rcv-settle-mode, source, target)
- [ ] 6.5 Define Flow fields (next-incoming-id, incoming-window, next-outgoing-id, outgoing-window, handle, delivery-count, link-credit, drain)
- [ ] 6.6 Define Transfer fields (handle, delivery-id, delivery-tag, message-format, settled)
- [ ] 6.7 Define Disposition fields (role, first, last, settled, state)
- [ ] 6.8 Define Detach, End, Close fields
- [ ] 6.9 Implement encoding for all performatives as described lists
- [ ] 6.10 Implement decoding for all performatives
- [ ] 6.11 Write roundtrip tests for each performative

## 7. Transport - State Machines

- [ ] 7.1 Define ConnectionState ADT (Start, HDRSent, HDRExch, OpenSent, OpenRecv, Opened, CloseSent, CloseRecv, End)
- [ ] 7.2 Define SessionState ADT (Unmapped, BeginSent, BeginRecv, Mapped, EndSent, EndRecv)
- [ ] 7.3 Define LinkState ADT (Detached, AttachSent, AttachRecv, Attached, DetachSent, DetachRecv)
- [ ] 7.4 Implement connection state transition function
- [ ] 7.5 Implement session state transition function
- [ ] 7.6 Implement link state transition function
- [ ] 7.7 Write tests for valid state transitions
- [ ] 7.8 Write tests for invalid state transition rejection

## 8. Messaging - Message Structure

- [ ] 8.1 Define Message data type with all sections (header, properties, app-properties, body, footer)
- [ ] 8.2 Define Header fields (durable, priority, ttl, first-acquirer, delivery-count)
- [ ] 8.3 Define Properties fields (message-id, to, subject, reply-to, correlation-id, content-type, etc.)
- [ ] 8.4 Define body variants (Data, AmqpSequence, AmqpValue)
- [ ] 8.5 Implement message encoding (concatenated sections)
- [ ] 8.6 Implement message decoding
- [ ] 8.7 Write roundtrip tests for messages

## 9. Messaging - Delivery States

- [ ] 9.1 Define DeliveryState ADT (Accepted, Rejected, Released, Modified)
- [ ] 9.2 Define Rejected with error condition
- [ ] 9.3 Define Modified with delivery-failed and undeliverable-here flags
- [ ] 9.4 Implement encoding for delivery states
- [ ] 9.5 Implement decoding for delivery states
- [ ] 9.6 Write roundtrip tests for delivery states

## 10. Testing - Mock Server Core

- [ ] 10.1 Create TCP listener that accepts connections
- [ ] 10.2 Implement connection handler that spawns per-connection thread
- [ ] 10.3 Implement protocol header exchange
- [ ] 10.4 Implement OPEN/CLOSE handling in mock
- [ ] 10.5 Implement BEGIN/END handling in mock
- [ ] 10.6 Implement ATTACH/DETACH handling in mock
- [ ] 10.7 Add connection state tracking in mock
- [ ] 10.8 Add session state tracking in mock
- [ ] 10.9 Add link state tracking in mock
- [ ] 10.10 Write tests verifying mock handles basic handshake

## 11. Testing - Mock Message Handling

- [ ] 11.1 Implement TRANSFER reception in mock
- [ ] 11.2 Implement DISPOSITION sending from mock
- [ ] 11.3 Implement message storage in mock
- [ ] 11.4 Implement FLOW handling (credit granting)
- [ ] 11.5 Implement message delivery to receivers
- [ ] 11.6 Write tests for send/receive through mock

## 12. Testing - Error Injection

- [ ] 12.1 Add error injection configuration type
- [ ] 12.2 Implement connection refused injection
- [ ] 12.3 Implement connection reset injection
- [ ] 12.4 Implement slow response injection
- [ ] 12.5 Implement partial frame injection
- [ ] 12.6 Implement malformed frame injection
- [ ] 12.7 Implement zero credit injection
- [ ] 12.8 Implement reject delivery injection
- [ ] 12.9 Implement no settlement injection
- [ ] 12.10 Write tests verifying client handles each error type

## 13. Client - Connection

- [ ] 13.1 Implement connect function (TCP + protocol header + OPEN)
- [ ] 13.2 Implement connection close function
- [ ] 13.3 Implement connection reader thread (async frame reading)
- [ ] 13.4 Implement connection writer (frame sending)
- [ ] 13.5 Implement frame dispatch to sessions
- [ ] 13.6 Write tests for connect/close against mock

## 14. Client - Session

- [ ] 14.1 Implement createSession function (BEGIN handshake)
- [ ] 14.2 Implement session close function (END)
- [ ] 14.3 Implement session frame handling
- [ ] 14.4 Implement link management within session
- [ ] 14.5 Write tests for session lifecycle against mock

## 15. Client - Sender Link

- [ ] 15.1 Implement createSender function (ATTACH with role=sender)
- [ ] 15.2 Implement sender close function (DETACH)
- [ ] 15.3 Implement credit tracking for sender
- [ ] 15.4 Implement send function (TRANSFER)
- [ ] 15.5 Implement delivery tracking for sent messages
- [ ] 15.6 Write tests for sender lifecycle and send against mock

## 16. Client - Receiver Link

- [ ] 16.1 Implement createReceiver function (ATTACH with role=receiver)
- [ ] 16.2 Implement receiver close function (DETACH)
- [ ] 16.3 Implement credit granting (FLOW)
- [ ] 16.4 Implement receive function (wait for TRANSFER)
- [ ] 16.5 Implement accept/reject/release functions (DISPOSITION)
- [ ] 16.6 Write tests for receiver lifecycle and receive against mock

## 17. Testing - Docker Qpid

- [ ] 17.1 Create docker-compose.yml or script for Qpid broker
- [ ] 17.2 Add test flag to enable/disable Docker tests
- [ ] 17.3 Write integration test: connect to Qpid
- [ ] 17.4 Write integration test: send message through Qpid
- [ ] 17.5 Write integration test: receive message from Qpid
- [ ] 17.6 Write integration test: full send/receive roundtrip

## 18. Error Handling Integration Tests

- [ ] 18.1 Write test: client handles connection refused
- [ ] 18.2 Write test: client handles connection reset mid-transfer
- [ ] 18.3 Write test: client handles malformed frame
- [ ] 18.4 Write test: client handles broker CLOSE with error
- [ ] 18.5 Write test: client handles zero credit (blocks/times out)
- [ ] 18.6 Write test: client handles rejected delivery
