# Implementation plan

Sluice is a native macOS workbench for rehearsing failures of HTTP dependencies.
Record a dependency through a local reverse proxy, disconnect it, and run the
same client against an offline double. Change the failure, inspect the exact
response delivery plan, and compare what happened. Foundation and AppKit are the
application runtime. Objective-C owns protocol parsing, scenario compilation,
privacy, persistence, scheduling, networking, analysis, CLI, and desktop UI.

## Product boundary

- macOS 13 or later, Apple Command Line Tools, Python 3 for development checks.
- HTTP/1.0 and HTTP/1.1 at the local listener and cleartext HTTP upstream.
- Loopback listener only. One exchange per connection, explicit close semantics.
- Bounded headers, bodies, connections, deadlines, stored rows, and scenario size.
- No TLS interception, system proxy changes, daemon installation, or root access.
- Capture is privacy filtered before the persistence API sees it. Request and
  response bodies are omitted unless the user opts into JSON sanitization.
- Offline matching is exact over method, sanitized target, and sanitized request
  body digest. Ambiguous recordings must be selected explicitly.
- Failures are deterministic by request identity and per-identity occurrence,
  independent of unrelated requests. Wall-clock arrival order is not replayed.
- Receipts distinguish planned bytes, bytes accepted by send(), and completion.
  A socket write does not prove that the remote application consumed the bytes.

## Why this direction

Dependency failures are difficult to reproduce because response state, retry
order, and wire delivery change together. Sluice separates those inputs. A
filtered recording fixes the baseline, an explicit tape fixes changing state,
and a scenario changes response behavior and relative byte timing.

HTTP interception and network impairment already have mature implementations.
Sluice's specific design is a small, inspectable failure rehearsal workflow:
privacy-filtered fixtures, deterministic per-request fault choice, offline
matching, an explicit byte delivery plan, and a ledger of observed delivery.
It makes no claim to invent proxies or fault injection.

## Sequence and checkpoints

1. Establish build, support boundary, error contracts, and test runner.
2. Implement protocol value types, target parsing, incremental request/response
   framing, chunk decoding, and safe wire serialization.
3. Implement strict scenario validation, deterministic matching/selection,
   response transformations, and virtual delivery plans.
4. Implement privacy filtering and an atomic SQLite fixture/receipt store.
5. Wire the bounded poll reactor to live upstream and offline engine modes.
6. Expose recording, replay, scenario inspection, import/export, comparison,
   validation, and diagnostics through one CLI.
7. Build the AppKit application over the same engine and store.
8. Exercise actual sockets with an independent origin/client harness. Add parser
   differential tests, fragmentation campaigns, crash/reopen tests, sanitizer
   builds, concurrency/load checks, and evidence auditing.
9. Complete the developer guide, protocol and persistence specifications,
   diagrams, failure catalog, examples, and reproducible acceptance report.
10. Verify a fresh clone, publish all history, and check hosted CI.

Each independently reviewable subsystem, regression, and integration checkpoint
gets a real commit. At least 54 checkpoints are required. Source size is measured
at the end with production, tests, comments, and glue reported separately. There
is no generated source or line-count padding.

## Acceptance

- All documented commands run from a clean checkout with no package downloads.
- Unit, adversarial protocol, real socket, offline replay, privacy, persistence,
  import/export, scenario, and app smoke checks pass.
- Parser outcomes are invariant under input fragmentation.
- Truncation produces a genuinely incomplete HTTP body on the socket.
- Delays and pacing are measured with tolerant monotonic bounds.
- Unknown and misspelled scenario fields fail closed with useful diagnostics.
- Corrupted exports and mismatched receipt hashes are rejected.
- Capture persists no configured secrets, including in database WAL pages.
- ASan/UBSan and static analysis complete without unresolved findings.
- Failed gates and limitations remain visible in the final verification record.
