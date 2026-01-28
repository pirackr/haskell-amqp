## ADDED Requirements

### Requirement: Connect to broker
The system SHALL establish TCP connection and complete AMQP handshake with a broker.

#### Scenario: Connect to localhost
- **WHEN** calling connect with host="localhost", port=5672
- **THEN** TCP connection is established and AMQP OPEN handshake completes

#### Scenario: Connection refused
- **WHEN** broker is not running
- **THEN** connect returns connection error

#### Scenario: Connection timeout
- **WHEN** broker does not respond within timeout
- **THEN** connect returns timeout error

### Requirement: Create session
The system SHALL create sessions on an established connection.

#### Scenario: Create default session
- **WHEN** calling createSession on connection
- **THEN** BEGIN handshake completes and session is usable

#### Scenario: Create multiple sessions
- **WHEN** creating two sessions on same connection
- **THEN** each session has unique channel and independent state

### Requirement: Create sender link
The system SHALL create sender links for publishing messages.

#### Scenario: Create sender to address
- **WHEN** calling createSender with target address "queue/test"
- **THEN** ATTACH handshake completes with role=sender

#### Scenario: Sender link credit
- **WHEN** sender link is attached
- **THEN** sender receives credit from broker via FLOW

### Requirement: Create receiver link
The system SHALL create receiver links for consuming messages.

#### Scenario: Create receiver from address
- **WHEN** calling createReceiver with source address "queue/test"
- **THEN** ATTACH handshake completes with role=receiver

#### Scenario: Receiver grants credit
- **WHEN** receiver link is attached
- **THEN** receiver sends FLOW granting initial credit to broker

### Requirement: Send message
The system SHALL send messages through sender links.

#### Scenario: Send simple message
- **WHEN** calling send with binary payload
- **THEN** TRANSFER frame is sent with message body

#### Scenario: Send with properties
- **WHEN** calling send with message containing properties
- **THEN** TRANSFER includes properties section

#### Scenario: Send blocks without credit
- **WHEN** sender has no credit
- **THEN** send blocks until credit is received

### Requirement: Receive message
The system SHALL receive messages through receiver links.

#### Scenario: Receive message
- **WHEN** message arrives on receiver link
- **THEN** receive returns the message with delivery info

#### Scenario: Receive blocks when empty
- **WHEN** no messages available
- **THEN** receive blocks until message arrives or timeout

#### Scenario: Auto-grant credit
- **WHEN** message is received and processed
- **THEN** receiver automatically grants more credit

### Requirement: Acknowledge message
The system SHALL acknowledge received messages with delivery outcomes.

#### Scenario: Accept message
- **WHEN** calling accept on delivery
- **THEN** DISPOSITION with accepted outcome is sent

#### Scenario: Reject message
- **WHEN** calling reject on delivery with error
- **THEN** DISPOSITION with rejected outcome is sent

#### Scenario: Release message
- **WHEN** calling release on delivery
- **THEN** DISPOSITION with released outcome is sent

### Requirement: Close resources
The system SHALL cleanly close links, sessions, and connections.

#### Scenario: Close sender
- **WHEN** calling close on sender
- **THEN** DETACH is sent and link transitions to detached

#### Scenario: Close session
- **WHEN** calling close on session
- **THEN** END is sent after closing all links

#### Scenario: Close connection
- **WHEN** calling close on connection
- **THEN** CLOSE is sent after closing all sessions

### Requirement: Error handling
The system SHALL surface AMQP errors to the caller.

#### Scenario: Link error
- **WHEN** broker sends DETACH with error
- **THEN** client surfaces error condition to caller

#### Scenario: Session error
- **WHEN** broker sends END with error
- **THEN** session and its links are marked failed

#### Scenario: Connection error
- **WHEN** broker sends CLOSE with error
- **THEN** connection and all sessions are marked failed
