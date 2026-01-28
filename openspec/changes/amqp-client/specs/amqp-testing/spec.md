## ADDED Requirements

### Requirement: TCP mock server
The system SHALL provide a TCP server that accepts connections and speaks AMQP 1.0.

#### Scenario: Accept connection
- **WHEN** client connects to mock server
- **THEN** server accepts TCP connection

#### Scenario: Complete AMQP handshake
- **WHEN** client sends protocol header and OPEN
- **THEN** mock responds with protocol header and OPEN

#### Scenario: Handle multiple connections
- **WHEN** two clients connect simultaneously
- **THEN** mock handles both independently

### Requirement: Mock protocol state
The system SHALL track connection, session, and link state in the mock server.

#### Scenario: Track connection state
- **WHEN** OPEN is received
- **THEN** mock transitions connection to OPENED state

#### Scenario: Track session state
- **WHEN** BEGIN is received
- **THEN** mock creates session and responds with BEGIN

#### Scenario: Track link state
- **WHEN** ATTACH is received
- **THEN** mock creates link and responds with ATTACH

#### Scenario: Reject invalid sequence
- **WHEN** client sends BEGIN before OPEN completes
- **THEN** mock closes connection with error

### Requirement: Mock message handling
The system SHALL echo or store messages sent to the mock.

#### Scenario: Receive transfer
- **WHEN** client sends TRANSFER
- **THEN** mock stores message and sends DISPOSITION(accepted)

#### Scenario: Deliver stored message
- **WHEN** client attaches receiver with credit
- **THEN** mock delivers stored messages via TRANSFER

### Requirement: Error injection - network layer
The system SHALL support injecting network-level errors.

#### Scenario: Connection refused
- **WHEN** error mode is "refuse-connection"
- **THEN** mock closes socket immediately on accept

#### Scenario: Connection reset
- **WHEN** error mode is "reset-connection" with trigger
- **THEN** mock sends TCP RST at specified point

#### Scenario: Slow response
- **WHEN** error mode is "slow-response" with delay
- **THEN** mock delays response by specified duration

#### Scenario: Partial frame
- **WHEN** error mode is "partial-frame"
- **THEN** mock sends incomplete frame and pauses

### Requirement: Error injection - protocol layer
The system SHALL support injecting protocol-level errors.

#### Scenario: Malformed frame
- **WHEN** error mode is "malformed-frame"
- **THEN** mock sends frame with invalid structure

#### Scenario: Invalid type encoding
- **WHEN** error mode is "invalid-encoding"
- **THEN** mock sends frame with bad type code

#### Scenario: Out of sequence
- **WHEN** error mode is "out-of-sequence"
- **THEN** mock sends performative invalid for current state

#### Scenario: Unexpected close
- **WHEN** error mode is "unexpected-close" with error condition
- **THEN** mock sends CLOSE with specified error

### Requirement: Error injection - flow control
The system SHALL support injecting flow control errors.

#### Scenario: Zero credit
- **WHEN** error mode is "zero-credit"
- **THEN** mock never grants link credit

#### Scenario: Credit exhaustion
- **WHEN** error mode is "exhaust-credit" with count
- **THEN** mock grants N credit, then stops

#### Scenario: Delayed flow
- **WHEN** error mode is "delayed-flow" with delay
- **THEN** mock delays FLOW response

### Requirement: Error injection - delivery
The system SHALL support injecting delivery outcome errors.

#### Scenario: Reject delivery
- **WHEN** error mode is "reject-delivery"
- **THEN** mock responds with DISPOSITION(rejected)

#### Scenario: Release delivery
- **WHEN** error mode is "release-delivery"
- **THEN** mock responds with DISPOSITION(released)

#### Scenario: No settlement
- **WHEN** error mode is "no-settlement"
- **THEN** mock never sends DISPOSITION

### Requirement: Docker Qpid integration
The system SHALL support running tests against Qpid broker in Docker.

#### Scenario: Start Qpid container
- **WHEN** test suite starts with real-broker flag
- **THEN** Qpid Docker container is started

#### Scenario: Run tests against Qpid
- **WHEN** running integration tests
- **THEN** tests connect to Qpid on configured port

#### Scenario: Stop Qpid container
- **WHEN** test suite completes
- **THEN** Qpid Docker container is stopped

### Requirement: Test helpers
The system SHALL provide helpers for writing AMQP tests.

#### Scenario: Assert frame received
- **WHEN** test expects specific performative
- **THEN** helper asserts frame type and contents

#### Scenario: Capture wire traffic
- **WHEN** test enables capture mode
- **THEN** all frames sent/received are logged

#### Scenario: Wait for state
- **WHEN** test waits for connection state
- **THEN** helper polls until state reached or timeout
