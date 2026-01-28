## Context

Greenfield Haskell library implementing AMQP 1.0 client from scratch. No existing codebase—starting fresh with Stack + Nix build system.

AMQP 1.0 is a layered protocol:
- **Types**: Binary encoding for 24 primitives + composites (list, map, array)
- **Transport**: Connection → Session → Link hierarchy with 9 performatives
- **Messaging**: Message structure, delivery states, flow control
- **Security**: TLS + SASL (deferred to later phase)
- **Transactions**: Atomic operations (deferred to later phase)

Primary learning goals: binary encoding, state machines, async network I/O.

## Goals / Non-Goals

**Goals:**
- Implement core AMQP 1.0 type encoding/decoding
- Implement transport layer (connection, session, link state machines)
- Implement basic messaging (send/receive with settlement)
- Build testable architecture with pure protocol logic separated from I/O
- Create TCP mock server for controlled testing
- Validate against real broker (Qpid via Docker)

**Non-Goals:**
- TLS/SASL security (future phase)
- Transactions (future phase)
- Performance optimization (learning first, optimize later)
- Production-ready error handling (focus on happy path + key error cases)
- Full spec compliance (implement enough to be functional and educational)

## Decisions

### 1. Layer Separation: Pure Protocol vs I/O

**Decision**: Separate pure protocol logic from network I/O.

```
┌─────────────────────────────────────────────────────┐
│  Network.AMQP.Client        (IO, high-level API)    │
├─────────────────────────────────────────────────────┤
│  Network.AMQP.Connection    (IO, TCP sockets)       │
├─────────────────────────────────────────────────────┤
│  Network.AMQP.Transport     (Pure, state machines)  │
├─────────────────────────────────────────────────────┤
│  Network.AMQP.Types         (Pure, encoding)        │
└─────────────────────────────────────────────────────┘
```

**Rationale**: Pure layers are easy to test with QuickCheck. I/O layer can be tested against mock server. Clear separation aids learning.

**Alternatives considered**:
- Monolithic design: Simpler initially but harder to test and understand
- Tagless final: More flexible but adds complexity for a learning project

### 2. Binary Encoding: `binary` package

**Decision**: Use `binary` package for encoding/decoding.

**Rationale**:
- Well-documented, widely used
- `Get` and `Put` monads match AMQP's sequential encoding
- Good error messages for debugging

**Alternatives considered**:
- `cereal`: Similar but stricter, less forgiving for learning
- `flatparse`: Faster but steeper learning curve
- Hand-rolled: Educational but time-consuming

### 3. Concurrency: `async` + `stm`

**Decision**: Use `async` for concurrent operations, `stm` for shared state.

**Rationale**:
- Connection needs concurrent read/write
- Sessions and links need shared state
- STM provides safe, composable concurrency

**Alternatives considered**:
- MVar only: Simpler but prone to deadlocks
- Streaming libraries (conduit/pipes): Overkill for this scope

### 4. State Machines: Explicit ADTs

**Decision**: Model connection/session/link states as explicit Haskell ADTs.

```haskell
data ConnectionState
  = Start
  | HDRSent
  | HDRExch
  | OpenSent
  | OpenRecv
  | Opened
  | CloseSent
  | CloseRecv
  | End
```

**Rationale**: Type safety, pattern matching catches missing cases, self-documenting.

**Alternatives considered**:
- State monad with enum: Less type-safe
- Free monad: Over-engineered for this use case

### 5. Testing: Three-tier approach

**Decision**:
1. **Pure unit tests**: Types, frame parsing, state transitions (QuickCheck + HUnit)
2. **Mock server tests**: TCP mock with error injection (controlled integration)
3. **Real broker tests**: Qpid Docker container (validation)

**Rationale**: Fast feedback loop for most tests, real validation when needed.

**Alternatives considered**:
- Docker only: Slow, no error injection control
- Pure only: Doesn't catch real network issues

### 6. Mock Server: Stateful with Error Injection

**Decision**: TCP mock server that:
- Tracks connection/session/link state
- Responds with valid AMQP frames
- Supports configurable error injection (delays, drops, malformed frames)

**Rationale**: Testing error handling is critical. Mock gives precise control.

## Risks / Trade-offs

**[Spec complexity]** → Start with minimal viable subset. Add features incrementally. Keep AMQP spec PDF bookmarked.

**[Binary encoding bugs]** → Extensive roundtrip property tests (encode . decode = id). Compare against wire captures from real brokers.

**[State machine correctness]** → Model states explicitly. Test all valid transitions. Invalid transitions should be compile errors where possible.

**[Mock server diverges from real broker]** → Regular validation against Qpid Docker. Mock is for speed and error injection, not spec conformance.

**[Scope creep]** → Strict non-goals. No TLS, no transactions, no optimizations until core works.

## Open Questions

- Which GHC version minimizes dependency rebuilds with our chosen packages?
- Should we generate type definitions from AMQP spec XML, or hand-write them?
- How much of flow control to implement initially? (Minimum viable: fixed credit window)
