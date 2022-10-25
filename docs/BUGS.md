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
