## ADDED Requirements

### Requirement: Message structure
The system SHALL support AMQP 1.0 message format with sections: header, delivery-annotations, message-annotations, properties, application-properties, body (data/sequence/value), footer.

#### Scenario: Build message with body only
- **WHEN** creating a message with just a binary body
- **THEN** the message contains a single data section

#### Scenario: Build message with properties
- **WHEN** creating a message with message-id, to, subject, reply-to
- **THEN** the message includes properties section before body

#### Scenario: Build message with all sections
- **WHEN** creating a message with header, properties, application-properties, and body
- **THEN** sections appear in correct order per AMQP spec

### Requirement: Message encoding
The system SHALL encode messages as concatenated section encodings.

#### Scenario: Encode data body
- **WHEN** encoding a message with binary data body
- **THEN** output contains data section with descriptor 0x75 and binary payload

#### Scenario: Encode properties
- **WHEN** encoding properties section
- **THEN** output contains descriptor 0x73 and properties fields as list

#### Scenario: Encode multiple data sections
- **WHEN** encoding a message with multiple data sections
- **THEN** each data section is encoded sequentially

### Requirement: Message decoding
The system SHALL decode AMQP 1.0 messages from binary payloads.

#### Scenario: Decode message with data body
- **WHEN** decoding bytes containing header + properties + data
- **THEN** extract each section into structured message

#### Scenario: Handle missing optional sections
- **WHEN** decoding a message with only data section
- **THEN** optional sections (header, properties) are empty/default

### Requirement: Delivery states
The system SHALL support delivery outcome states: accepted, rejected, released, modified.

#### Scenario: Create accepted outcome
- **WHEN** settling a delivery as accepted
- **THEN** disposition contains accepted descriptor 0x24

#### Scenario: Create rejected outcome
- **WHEN** settling a delivery as rejected with error
- **THEN** disposition contains rejected descriptor 0x25 with error condition

#### Scenario: Create released outcome
- **WHEN** settling a delivery as released
- **THEN** disposition contains released descriptor 0x26

#### Scenario: Create modified outcome
- **WHEN** settling a delivery as modified with delivery-failed=true
- **THEN** disposition contains modified descriptor 0x27 with flags

### Requirement: Settlement modes
The system SHALL support sender-settle-mode (unsettled, settled, mixed) and receiver-settle-mode (first, second).

#### Scenario: Send pre-settled message
- **WHEN** sending with settled=true in TRANSFER
- **THEN** no disposition is expected from receiver

#### Scenario: Send unsettled message
- **WHEN** sending with settled=false
- **THEN** sender waits for DISPOSITION from receiver

#### Scenario: Receiver settles first
- **WHEN** receiver uses rcv-settle-mode=first
- **THEN** receiver sends DISPOSITION immediately upon processing

### Requirement: Flow control
The system SHALL implement link-level credit-based flow control.

#### Scenario: Grant credit
- **WHEN** receiver sends FLOW with link-credit=10
- **THEN** sender can send up to 10 transfers

#### Scenario: Credit exhaustion
- **WHEN** sender has sent all credited transfers
- **THEN** sender waits for more credit before sending

#### Scenario: Drain mode
- **WHEN** receiver sends FLOW with drain=true
- **THEN** sender sends remaining messages and returns unused credit

### Requirement: Delivery tracking
The system SHALL track deliveries by delivery-id and delivery-tag.

#### Scenario: Assign delivery-id
- **WHEN** sending a transfer
- **THEN** delivery-id is sequential within the session

#### Scenario: Match disposition to delivery
- **WHEN** receiving DISPOSITION with first=5, last=10
- **THEN** outcomes apply to deliveries 5 through 10

#### Scenario: Track unsettled deliveries
- **WHEN** sending unsettled messages
- **THEN** system maintains map of delivery-id to pending deliveries
