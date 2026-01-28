## ADDED Requirements

### Requirement: Primitive type encoding
The system SHALL encode all AMQP 1.0 primitive types to their binary representation per the spec: null, boolean, ubyte, ushort, uint, ulong, byte, short, int, long, float, double, decimal32, decimal64, decimal128, char, timestamp, uuid, binary, string, symbol.

#### Scenario: Encode null
- **WHEN** encoding a null value
- **THEN** the output is a single byte 0x40

#### Scenario: Encode boolean true
- **WHEN** encoding boolean true
- **THEN** the output is a single byte 0x41

#### Scenario: Encode boolean false
- **WHEN** encoding boolean false
- **THEN** the output is a single byte 0x42

#### Scenario: Encode small uint
- **WHEN** encoding uint value 0
- **THEN** the output is a single byte 0x43 (uint0 encoding)

#### Scenario: Encode string
- **WHEN** encoding a UTF-8 string "hello"
- **THEN** the output uses str8 (0xa1) or str32 (0xb1) encoding with length prefix

### Requirement: Primitive type decoding
The system SHALL decode all AMQP 1.0 primitive type binary representations back to Haskell values.

#### Scenario: Decode null
- **WHEN** decoding byte 0x40
- **THEN** the result is a null value

#### Scenario: Decode variable-width types
- **WHEN** decoding a str8-encoded string
- **THEN** the system reads the length byte and extracts that many UTF-8 bytes

#### Scenario: Handle invalid type code
- **WHEN** decoding an unknown type code
- **THEN** the system returns a decode error with the invalid code

### Requirement: Encoding roundtrip
The system SHALL satisfy encode(decode(bytes)) = bytes and decode(encode(value)) = value for all valid inputs.

#### Scenario: Roundtrip primitive types
- **WHEN** encoding a primitive value and then decoding the result
- **THEN** the decoded value equals the original value

#### Scenario: Roundtrip edge cases
- **WHEN** encoding boundary values (0, max uint64, empty string, max-length binary)
- **THEN** roundtrip preserves the exact value

### Requirement: Composite type encoding
The system SHALL encode AMQP 1.0 composite types: list, map, and array.

#### Scenario: Encode empty list
- **WHEN** encoding an empty list
- **THEN** the output uses list0 encoding (0x45)

#### Scenario: Encode list with mixed types
- **WHEN** encoding a list containing [null, true, 42, "hello"]
- **THEN** the output uses list8 or list32 encoding with count and size fields

#### Scenario: Encode map
- **WHEN** encoding a map {"key": "value"}
- **THEN** the output uses map8 or map32 encoding with key-value pairs

#### Scenario: Encode array
- **WHEN** encoding an array of integers [1, 2, 3]
- **THEN** the output uses array8 or array32 encoding with homogeneous element type

### Requirement: Composite type decoding
The system SHALL decode AMQP 1.0 composite type binary representations.

#### Scenario: Decode list
- **WHEN** decoding a list8-encoded list
- **THEN** the system reads count, then decodes that many elements

#### Scenario: Decode nested structures
- **WHEN** decoding a list containing another list
- **THEN** the system recursively decodes nested composites

### Requirement: Described types
The system SHALL support AMQP 1.0 described types (descriptor + value pairs).

#### Scenario: Encode described type
- **WHEN** encoding a described type with numeric descriptor 0x00 and value "test"
- **THEN** the output starts with 0x00 followed by descriptor encoding and value encoding

#### Scenario: Decode described type
- **WHEN** decoding a described type
- **THEN** the system extracts both descriptor and underlying value
