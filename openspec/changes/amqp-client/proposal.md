## Why

Learning project to deeply understand the AMQP 1.0 protocol and network programming in Haskell. Implementing a client from scratch teaches binary encoding, state machines, async I/O, and protocol design—knowledge that's hard to gain from just using existing libraries.

## What Changes

- Implement AMQP 1.0 type system (24 primitives + composite types)
- Implement transport layer (connection/session/link hierarchy, 9 performatives)
- Implement messaging layer (message structure, delivery states, settlement)
- Build TCP mock server for testing with error injection
- Docker-based integration tests against Qpid broker

## Capabilities

### New Capabilities
- `amqp-types`: Primitive and composite type encoding/decoding per AMQP 1.0 spec
- `amqp-transport`: Connection, session, and link state machines; frame parsing; performatives
- `amqp-messaging`: Message structure, delivery states, flow control
- `amqp-client`: High-level client API for connecting, sending, receiving
- `amqp-testing`: TCP mock server with error injection, Docker Qpid integration

### Modified Capabilities
<!-- None - greenfield project -->

## Impact

- **New library**: `haskell-amqp` package with Stack + Nix build
- **Dependencies**: `network`, `binary`/`cereal`, `async`, `stm`
- **Test infrastructure**: Haskell mock server, Docker Qpid container
- **No external systems affected**: This is a standalone learning project
