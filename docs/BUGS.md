# Regression ledger

Every entry names a reproducer retained in the suite. Build-time diagnostics
are corrected before the affected checkpoint is committed. Runtime failures get
a failing test before the fix.

## SL-001: caller mutation changed a compiled scenario

- Reproducer: `validated scenario cannot be mutated through caller containers`.
- Before: constructing a rule with a mutable action and then changing its status
  changed the response selected by the supposedly validated scenario.
- Cause: shallow dictionary copies retained nested mutable input containers.
- Fix: immutable recursive JSON containers and deep snapshots at public compiler
  boundaries before any rules are constructed.
- Regression: the action remains status 503 after the caller changes its input
  to 500; the exposed scenario document is immutable.

## SL-002: HEAD lost the represented entity length

- Reproducer: `HEAD preserves representation length through capture and replay`.
- Before: a HEAD response advertising 123 entity bytes was stored and replayed
  with Content-Length 0 even though no entity bytes should be transmitted.
- Cause: privacy correctly removed stale body lengths, but failed to retain
  representation metadata when the received body was empty.
- Fix: preserve validated length metadata on empty responses and use it for
  HEAD and 304 delivery plans. The socket still emits no entity bytes.

## SL-003: fixture index tampering escaped integrity checking

- Reproducer: `store integrity checks detect tampered lookup indexes`.
- Before: changing the SQLite identity index without changing a fixture payload
  passed the payload hash check and could make a valid fixture unreachable.
- Cause: verification compared payload bytes with their digest but did not bind
  denormalized lookup columns to the reconstructed fixture.
- Fix: compare id, request identity, and content digest on every returned fixture.

## SL-004: a NUL byte was accepted as JSON whitespace

- Reproducer: `JSON rejects NUL bytes instead of treating them as whitespace`.
- Before: a valid JSON object followed by a raw zero byte was accepted.
- Cause: `strchr` also matches a C string's terminating zero byte.
- Fix: exclude zero explicitly from whitespace classification. Invalid zero
  bytes now fail as syntax errors instead of bypassing trailing-input checks.

## SL-005: Stop could arrive before the app published its reactor

- Trigger: start a listener and click Stop before background initialization
  returned to the main queue.
- Cause: messaging a not-yet-published reactor discarded the stop request.
- Fix: latch the request on the main thread and apply it when the reactor is
  published. The application lifecycle smoke check retains this ordering.

## SL-006: a same-second rebuild could leave a stale executable

- Reproducer: the JSON NUL regression changed its object file within the same
  timestamp tick as the test executable. macOS system make rebuilt the object
  but skipped the link, so the old failure remained despite corrected source.
- Cause: relying on coarse filesystem timestamps for incremental build validity.
- Fix: object compilation checks source, headers, command, and compiler content
  signatures; executable link steps always run. The build helper has a retained
  same-timestamp source mutation test.

## SL-007: a client write half-close discarded a valid response

- Reproducer: `test_client_write_half_close_still_receives_response`.
- Before: a client that sent a complete request then shut down its write side
  received no response.
- Cause: the reactor interpreted POLLHUP as a full connection failure even when
  the client still had a readable side waiting for the response.
- Fix: EOF is terminal during incomplete request parsing. After parsing, response
  writes determine delivery viability. Waiting connections are not polled with
  an empty interest set, avoiding repeated half-close wakeups.

## SL-008: long planned delays tripped the write-backpressure timeout

- Reproducer: `test_delay_longer_than_backpressure_timeout_remains_valid`.
- Before: a 16 second intentional delay closed without emitting a response.
- Cause: the idle-write timer started at plan creation and expired as the first
  byte became due, before any write was attempted.
- Fix: the backpressure clock starts no earlier than the current segment's due
  time. Intentional waiting and failure to make progress are separate states.

## SL-009: fixture message projections could be mutated after validation

- Reproducer: `fixture message access cannot mutate validated content`.
- Before: a caller could change the target or status on a fixture's message
  projection while its immutable document and content digest stayed unchanged.
- Cause: read-only properties exposed a mutable cached message instance.
- Fix: return message copies. Immutable body bytes and header values remain
  shared; mutable metadata stays private to the projection's caller.

## SL-010: chunk overhead made validity depend on feed size

- Reproducer: `chunk overhead does not make validity depend on feed fragment size`.
- Before: a valid 1.5 MiB entity encoded as one-byte chunks was accepted from
  normal socket reads but rejected when passed to the parser as one NSData.
- Cause: the initial pending-buffer check counted all encoded chunk overhead
  against the entity budget before the head and chunks could be consumed.
- Fix: normalize public feed calls to the same bounded read units as the reactor.
  The decoded entity budget remains unchanged and input framing is invariant.

## SL-011: recovered input exceptions leaked strong local objects

- Reproducer: `recovered rejection releases strong locals during stack unwinding`.
- Before: a precise-lifetime probe was never deallocated after its scope threw.
  The extended fuzz run also showed continuing resident-memory growth under
  repeated rejected inputs. That campaign was stopped and retained separately.
- Cause: Objective-C ARC does not release strong locals during exception unwinding
  by default. Sluice deliberately recovers from validation exceptions at request
  and command boundaries, so that default was inappropriate.
- Fix: enable `-fobjc-arc-exceptions` in every production, test, sanitizer, fuzz,
  coverage, and static-analysis compilation. The native deallocation regression
  fails immediately if the flag is removed.
- Reference: [Clang ARC exception semantics](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#exceptions).
