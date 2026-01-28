## ADDED Requirements

### Requirement: Frame parsing
The system SHALL parse AMQP 1.0 frames consisting of: 4-byte size, 1-byte DOFF, 1-byte type, 2-byte channel, and variable-length payload.

#### Scenario: Parse minimal frame
- **WHEN** parsing bytes representing a valid AMQP frame
- **THEN** the system extracts size, DOFF, type, channel, and payload

#### Scenario: Handle frame size limits
- **WHEN** receiving a frame exceeding negotiated max-frame-size
- **THEN** the system rejects the frame with an error

#### Scenario: Handle incomplete frame
- **WHEN** receiving fewer bytes than the frame size indicates
- **THEN** the system waits for more bytes or returns a partial read indicator

### Requirement: Frame building
The system SHALL construct valid AMQP 1.0 frames from performatives.

#### Scenario: Build OPEN frame
- **WHEN** building a frame with OPEN performative
- **THEN** the output has correct size, DOFF=2, type=0, channel=0, and encoded OPEN

#### Scenario: Build TRANSFER frame with payload
- **WHEN** building a TRANSFER frame with message payload
- **THEN** the frame contains the performative followed by message bytes

### Requirement: Connection state machine
The system SHALL implement the AMQP 1.0 connection state machine with states: START, HDR-SENT, HDR-EXCH, OPEN-SENT, OPEN-RCVD, OPENED, CLOSE-SENT, CLOSE-RCVD, END.

#### Scenario: Connection open handshake
- **WHEN** client sends protocol header and OPEN
- **THEN** state transitions START → HDR-SENT → HDR-EXCH → OPEN-SENT → OPENED

#### Scenario: Connection close
- **WHEN** client sends CLOSE in OPENED state
- **THEN** state transitions to CLOSE-SENT, then END after receiving CLOSE

#### Scenario: Reject invalid transition
- **WHEN** receiving TRANSFER before connection is OPENED
- **THEN** the system rejects the frame as invalid for current state

### Requirement: Session state machine
The system SHALL implement session lifecycle with states: UNMAPPED, BEGIN-SENT, BEGIN-RCVD, MAPPED, END-SENT, END-RCVD, DISCARDING.

#### Scenario: Session begin
- **WHEN** client sends BEGIN on channel N
- **THEN** session state transitions UNMAPPED → BEGIN-SENT → MAPPED

#### Scenario: Session end
- **WHEN** client sends END
- **THEN** session state transitions to END-SENT, then UNMAPPED after END received

#### Scenario: Multiple sessions
- **WHEN** opening sessions on channels 0 and 1
- **THEN** each session has independent state

### Requirement: Link state machine
The system SHALL implement link lifecycle with states: DETACHED, ATTACH-SENT, ATTACH-RCVD, ATTACHED, DETACH-SENT, DETACH-RCVD.

#### Scenario: Link attach as sender
- **WHEN** client sends ATTACH with role=sender
- **THEN** link state transitions DETACHED → ATTACH-SENT → ATTACHED

#### Scenario: Link attach as receiver
- **WHEN** client sends ATTACH with role=receiver
- **THEN** link state transitions to ATTACHED with receiver role

#### Scenario: Link detach
- **WHEN** client sends DETACH
- **THEN** link state transitions to DETACH-SENT, then DETACHED

### Requirement: Performative encoding
The system SHALL encode all 9 AMQP transport performatives: OPEN, BEGIN, ATTACH, FLOW, TRANSFER, DISPOSITION, DETACH, END, CLOSE.

#### Scenario: Encode OPEN
- **WHEN** encoding OPEN with container-id "test-client"
- **THEN** output is described list with descriptor 0x10 and fields

#### Scenario: Encode ATTACH
- **WHEN** encoding ATTACH with name, handle, role, source, target
- **THEN** output includes all required fields in correct order

#### Scenario: Encode TRANSFER
- **WHEN** encoding TRANSFER with handle, delivery-id, delivery-tag
- **THEN** output includes transfer fields followed by message payload

### Requirement: Performative decoding
The system SHALL decode all 9 AMQP transport performatives from binary frames.

#### Scenario: Decode OPEN
- **WHEN** decoding a frame with OPEN performative
- **THEN** extract container-id, hostname, max-frame-size, channel-max, idle-time-out

#### Scenario: Decode FLOW
- **WHEN** decoding FLOW
- **THEN** extract next-incoming-id, incoming-window, next-outgoing-id, outgoing-window, handle, delivery-count, link-credit

#### Scenario: Handle unknown performative
- **WHEN** decoding a frame with unrecognized descriptor
- **THEN** return an error indicating unknown performative
