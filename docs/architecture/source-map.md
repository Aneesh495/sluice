# Source map

Read the code in this order for a complete exchange.

1. `Sources/HTTP/SLHTTPParser.m` determines framing and completeness.
2. `Sources/Network/SLReactor.m` turns readiness events into state transitions.
3. `Sources/Engine/SLSession.m` allocates identity ordinals and chooses a baseline.
4. `Sources/Privacy/SLPrivacy.m` defines the persistence boundary and identity.
5. `Sources/Engine/SLReplayIndex.m` refuses uncertain offline matches.
6. `Sources/Engine/SLTape.m` selects explicit recorded state transitions.
7. `Sources/Scenario/SLScenario.m` selects ordered deterministic faults.
8. `Sources/Engine/SLDeliveryPlan.m` defines the exact intended output bytes.
9. `Sources/Engine/SLReceipt.m` states what delivery evidence can establish.
10. `Sources/Storage/SLStore.m` owns transactions and integrity checks.

## Directories

| Path | Responsibility |
| --- | --- |
| `Sources/Core` | Stable failures, strict schemas, bytes, atomic files, strict JSON, arguments |
| `Sources/HTTP` | Header multiplicity, targets, incremental framing, chunk decoding, wire encoding |
| `Sources/Privacy` | Query/header/body filtering and request identity |
| `Sources/Scenario` | Predicates, ordinal rules, hash sampling, response transformations |
| `Sources/Engine` | Sessions, fixture selection, state tapes, plans, receipts |
| `Sources/Network` | Owned sockets, connection states, monotonic poll reactor |
| `Sources/Storage` | Fixtures, SQLite, portable bundles, HAR import |
| `Sources/Analysis` | Bounded JSON-pointer diffs and delivery reports |
| `Sources/CLI` | Strict command adapter and signal integration |
| `Sources/App` | Native controls, table, inspector, timeline, application lifecycle |
| `Tests/Unit` | Native unit, boundary, and retained regression tests |
| `Tests/Integration` | Independent real clients, durability, build, and application checks |
| `Tests/Differential` | Comparison with Python's independent HTTP response parser |
| `Tests/Fuzz` | Coverage-guided parser/JSON fuzzing and byte-exact seed corpus |
| `scripts` | Build signatures, demonstration, verification, and evidence tools |

## Error boundaries

Domain failures are `SLError` exceptions with stable codes. CLI commands catch
them once and return structured stderr with exit status 2. Unexpected exceptions
return status 3. Connection processing catches domain failures per connection and
emits a small stable-code error response where delivery is still possible.

A failure to save a receipt is session-fatal. The reactor retains the error code,
stops accepting work, and attempts to close active connections. The CLI returns a
failure; the application presents it. Storage failure is not silently reported
as a successful observed delivery.

## Extending the project

A new fault should have four pieces: strict configuration validation, a pure
transformation or arithmetic schedule change, a plan summary that explains its
effect, and a real socket test for the observed behavior. Prefer extending the
plan rather than adding hidden sleeps or network side effects to predicates.

A new identity field changes fixture matching semantics. Version the identity
domain string and plan a workspace/bundle migration. Do not silently reinterpret
old hashes.

A new persistence schema requires an explicit migration and failure tests for
interrupted or incompatible upgrades. Opening an unknown future schema already
fails rather than modifying it.
