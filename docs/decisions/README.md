# Design decisions

## Native Objective-C across the application

The same Objective-C types own parsing, filtered fixtures, fault rules, delivery
plans, persistence, CLI, and AppKit presentation. The UI is not a wrapper around a
second server implementation. Python supplies independent clients, generated
oracles, build bookkeeping, and an entirely local demonstration.

## One dependency and one exchange per connection

A reverse proxy is explicit about which dependency it replaces. Closing after
one exchange makes framing and failure termination inspectable and avoids a
hidden keep-alive pool changing experiment order. The cost is extra connections
and no multiplexing. This is appropriate for controlled dependency rehearsal.

## Cleartext HTTP rather than certificate interception

TLS interception adds a certificate authority, trust installation, negotiation,
and encrypted-transport policy to the problem. Sluice instead provides an HTTP
origin replacement with no system trust changes. Existing HTTPS traffic can be
imported from a HAR archive; live capture stays within the documented HTTP subset.

## Complete bounded entities before transformation

Capturing a full entity permits JSON filtering, exact body identity, reproducible
replacement, and honest advertised-versus-delivered length accounting. The cost
is buffering and delayed first output until the origin has completed. An 8 MiB
entity bound and explicit lifetime/connection limits make that tradeoff visible.

## Exact matches and explicit ambiguity

Convenient fuzzy matching can serve the wrong fixture after redaction collapses
requests or a server changes state. Exact identities fail closed. A fixture pin
resolves one variant; a response tape expresses changing state. Neither falls
back to a live origin without the user changing mode.

## Per-identity counters instead of one global schedule

A global counter lets an unrelated health check move a checkout failure from its
first attempt to its second. Per-identity ordinals isolate those streams. Equal
identities arriving concurrently still have a real order decided by the reactor.
The system states that boundary instead of pretending to reproduce thread
launch order or TCP packet timing.

## Arithmetic schedules instead of allocated chunk arrays

A body may be split into very small application writes. Keeping one object per
chunk would amplify memory use. A plan stores its wire bytes and computes each
segment range and due time by index. Its summary records the effective counts
without persisting a huge synthetic event list.

## SQLite as a durable catalog

The hard problem here is the boundary between a raw exchange, a privacy-filtered
fixture, and an observed delivery. Reimplementing a storage engine would distract
from that boundary. SQLite supplies atomic commits and WAL recovery; application
hashes bind the semantic lookup metadata to immutable documents.

## Receipts describe evidence, not application success

A successful send reports kernel acceptance. A deliberately truncated plan can
complete all its sends while a strict HTTP client correctly raises an incomplete
body error. The ledger keeps those facts separate. Client retry behavior is
observed by real test clients, not inferred from a green server status.

## Checksums without authenticity claims

Bundle checksums catch damage and stale edits. A sender able to alter a document
can also recompute its checksum. There is no signing authority or trust chain in
the portable format. Adding one would require key lifecycle and policy decisions
that are not hidden behind the word "verified".
