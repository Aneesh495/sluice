# Architecture

Sluice replaces one HTTP dependency with a controlled local endpoint. A client
keeps making real socket requests. The workbench changes the response state and
its delivery, then records what the local socket accepted.

The desktop application and command line are adapters over the same engine.
Neither has a second implementation of matching, privacy, parsing, or faults.

```mermaid
flowchart LR
    Client[Client application] -->|HTTP over loopback| Reactor[Bounded poll reactor]
    Reactor --> Parser[Incremental HTTP parser]
    Parser --> Session[Session and identity counters]
    Session --> Privacy[Privacy policy]
    Session --> Exact[Exact fixture index]
    Session --> Tape[Recorded state tape]
    Session --> Rules[Scenario compiler and ordered rules]
    Session --> Origin[Configured HTTP origin]
    Origin --> Fixture[Filtered immutable fixture]
    Fixture --> Store[(SQLite WAL workspace)]
    Exact --> Plan[Response transformation and byte plan]
    Tape --> Exact
    Rules --> Plan
    Plan --> Reactor
    Reactor -->|accepted bytes and outcome| Receipt[Delivery receipt]
    Receipt --> Store
    Store --> CLI[CLI inspection and exchange]
    Store --> App[AppKit workspace and inspector]
```

## Ownership boundaries

| Component | Owns | Does not own |
| --- | --- | --- |
| `SLHTTPParser` | Bounded partial head and decoded entity | Sockets or deadlines |
| `SLSession` | Identity ordinals, replay snapshot, scenario selection | Poll events |
| `SLPrivacy` | Filtering and canonical request representation | Original network writes |
| `SLStore` | One serialized SQLite connection and transactions | Raw traffic |
| `SLReplayIndex` | Frozen request-to-fixture candidates | New database observations |
| `SLTape` | Explicit fixture sequence for each identity | Wall-clock arrival order |
| `SLDeliveryPlan` | Immutable output bytes and arithmetic segment schedule | Actual socket progress |
| `SLConnection` | Client/upstream descriptors and one exchange state | Cross-thread access |
| `SLReactor` | Descriptor readiness, fairness, timeouts, final receipts | UI state |
| `SLAppController` | Main-thread controls and background work dispatch | Protocol semantics |

Connections and sessions are confined to the reactor thread. `stop` uses a
nonblocking self-pipe so the UI and signal dispatch handlers can wake the poll
loop. The UI uses a separate serial data queue. SQLite access through a store
instance is synchronized; separate store connections coordinate through WAL and
SQLite's busy timeout.

## Record an exchange

```mermaid
sequenceDiagram
    participant C as Client
    participant R as Reactor
    participant E as Session
    participant O as Origin
    participant P as Privacy
    participant S as SQLite
    C->>R: Complete HTTP request
    R->>E: Begin identity and occurrence
    E->>P: Sanitize identity inputs
    R->>O: Normalized request, Connection close
    O->>R: Complete bounded HTTP response
    R->>E: Complete exchange
    E->>P: Sanitize request and response
    P->>S: Insert filtered fixture atomically
    E->>R: Immutable delivery plan
    R->>C: Planned segments when due
    R->>S: Final delivery receipt
```

The original live request and response are forwarded, except for protocol
normalization and an explicitly selected fault. Capture filtering changes the
stored fixture, not the user's live credentials. Offline replay serves the
filtered representation. It can therefore differ intentionally from the live
response, for example a token becomes `[redacted]`.

A fixture commits before delivery starts. A receipt commits before the connection
is closed normally. These are separate observations: the origin might have
completed while the client disconnected before reading the result. A process
crash between those commits can leave a fixture with no delivery receipt.

## Offline exchange

```mermaid
sequenceDiagram
    participant C as Client
    participant R as Reactor
    participant E as Session
    participant I as Frozen fixture index
    participant T as Optional state tape
    C->>R: Real HTTP request
    R->>E: Filter request and allocate identity ordinal
    opt Tape selected
        E->>T: Select fixture at this ordinal
        T-->>E: Fixture UUID, or exhausted
    end
    E->>I: Exact identity and optional fixture UUID
    I-->>E: Unambiguous replayable fixture
    E->>E: Select first applicable fault rule
    E->>R: Baseline response transformed into byte plan
    R->>C: Scheduled real socket writes
```

The origin resolver and connector are never used in replay mode. A missing,
ambiguous, omitted-body, unsupported-Vary, mismatched-policy, or exhausted-tape
request produces an explicit 409 error. It does not fall back to the network.

## State machine

```mermaid
stateDiagram-v2
    [*] --> ReadingRequest
    ReadingRequest --> ConnectingOrigin: record
    ReadingRequest --> DeliveringResponse: replay
    ConnectingOrigin --> WritingOrigin: connect succeeds
    ConnectingOrigin --> ConnectingOrigin: next resolved address
    WritingOrigin --> ReadingOrigin: full request written
    ReadingOrigin --> DeliveringResponse: complete response captured
    ReadingRequest --> DeliveringResponse: bounded protocol error
    ReadingOrigin --> DeliveringResponse: upstream error response
    DeliveringResponse --> Closed: all planned bytes accepted
    DeliveringResponse --> Closed: peer failure or deadline
    ReadingRequest --> Closed: incomplete peer EOF
    ConnectingOrigin --> Closed: deadline or shutdown
    WritingOrigin --> Closed: deadline or shutdown
    ReadingOrigin --> Closed: deadline or shutdown
    Closed --> [*]: receipt finalized, descriptors released
```

A client write half-close is compatible with receiving a response. After the
request has completed, the reactor uses response writes to determine whether
delivery remains possible. It does not confuse an input EOF with a full socket
failure.

## Scheduling and fairness

The poll array has room for the listener, wake pipe, and two descriptors for each
of 64 connections. Every accepted connection receives one exchange. A loop
iteration accepts at most 32 clients and writes at most 64 KiB per delivering
connection. Slow readers cannot monopolize a write loop.

Deadlines use a monotonic clock. There is a 10 second inactivity bound before
delivery, a 15 second blocked-write bound after a segment becomes due, and a 125
second total lifetime. A plan can schedule at most 120 seconds. Intentional delay
is excluded from blocked-write time.

The engine buffers a complete entity before capture and transformation. It is a
bounded dependency workbench, not an unbounded streaming proxy. The body bound is
8 MiB and the connection bound is 64. Worst-case memory includes concurrent
request, response, transformed, encoded, and fixture representations. Do not use
those maxima as a target load on a small machine.

## Durable and reproducible state

Deterministic behavior covers identity, per-identity ordinal selection, hash
sampling, response transformations, and relative segment due times. It does not
promise identical operating-system scheduling, TCP packet boundaries, elapsed
latency, or ordering among concurrent requests with the same identity.

An exact replay index is frozen at session start. New captures from another
process do not change a running replay. A state tape makes changing baseline
responses explicit and refuses gaps when constructed from a recording session.

The database stores filtered fixture documents and receipt documents with raw
payload hashes. Reads reconstruct the fixture and also verify denormalized id,
identity, and content-digest columns. Bundle checksums detect damage; they are
not signatures or proof that a sender is trustworthy.
