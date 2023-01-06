# Verification record

The published snapshot verifies runtime source revision
`160bc6ab4ca558e0f563eaf0c12dddef4db12b3c` on 2026-10-18. Later commits package
these logs, documentation, and the actual workbench screenshot. The exact
109-file source manifest, rather than a prose completion claim, binds the record
to the current implementation.

All nine gates passed and the source manifest remained unchanged throughout the
campaign. The [machine-readable report](../verification/2026-10-18/report.json)
preserves commands, exit status, elapsed time, and hashes of the raw outputs.

| Gate | Observed result | Evidence |
| --- | --- | --- |
| Native build and tests | CLI and app built; 38 tests passed | [Raw log](../verification/2026-10-18/native.log) |
| Real socket integration | 18 tests passed | [Raw log](../verification/2026-10-18/integration.log) |
| Differential HTTP parsing | 1200 generated responses matched Python's parser | [Raw log](../verification/2026-10-18/differential.log) |
| Build cache | Same-timestamp source changes rebuilt correctly | [Raw log](../verification/2026-10-18/build-cache.log) |
| Native app | Background rendering and early Stop lifecycle passed | [Raw log](../verification/2026-10-18/app.log) |
| Static analyzer | 36 production translation units, zero diagnostics | [Raw log](../verification/2026-10-18/analyzer.log) |
| Execution coverage | Instrumented unit, socket, and app runs completed | [Raw log](../verification/2026-10-18/coverage.log) |
| ASan and UBSan | Native and socket suites passed | [Raw log](../verification/2026-10-18/sanitizers.log) |
| Coverage-guided fuzzing | 1000000 inputs completed without a finding | [Raw log](../verification/2026-10-18/fuzz.log) |

The final fuzz run reported 460 MiB peak resident memory, including sanitizer
allocator overhead. That is an observation for this campaign, not a memory bound
for every possible client workload. The learned corpus is retained in
[fuzz-corpus.tar.gz](../verification/2026-10-18/fuzz-corpus.tar.gz).

## What was exercised

Real socket tests cover live recording, offline replay, explicit misses,
variant ambiguity and fixture pinning, response tapes and exhaustion, JSON
privacy, live database/WAL scans, body omission, bundle exchange and corruption,
SIGKILL recovery, chunked requests and origins, HEAD metadata, truncated entities,
pacing, a 16 second deliberate delay, TCP half-close, concurrent clients,
smuggling ambiguity, database tampering, and strict configuration failures.

The local demonstration closes its origin before replay and observes a
first-attempt 503 followed by a successful catalog response. A separate clean
checkout built both binaries, passed all 38 native tests, and ran that complete
demonstration. Its [raw output](../verification/2026-10-18/clean-checkout.log)
is retained.

## Coverage boundary

| Production area | Executable lines covered | Line coverage |
| --- | --- | --- |
| Core and CLI | 2582 / 2873 | 89.87% |
| AppKit application | 756 / 1276 | 59.25% |
| Combined | 3338 / 4149 | 80.45% |

The [LLVM report](../verification/2026-10-18/coverage-report.txt) and
[per-file summary](../verification/2026-10-18/coverage-summary.json) include the
underlying counts. Line coverage is not exhaustive path coverage. Native app
checks cover rendering, loading, and startup/stop ordering; they do not automate
every system file-picker interaction or every possible GUI action sequence.

The parser differential campaign covers supported positive response semantics.
It is not a claim of complete RFC conformance. The fuzzer has a 4096 byte input
limit for this campaign. Separate native tests cover larger bodies, including a
1.5 MiB entity encoded as many small chunks and canonical JSON expansion near the
8 MiB capture boundary.

The local host was macOS on arm64. Normal builds used Apple's compiler, and the
fuzz target used LLVM with libFuzzer. Hosted CI separately builds and exercises
macOS Intel and Apple Silicon. Actual compiler flags and host details remain in
the logs and report. The deployment target of macOS 13 is not a claim that every
older release or hardware configuration was executed locally.

## Regression evidence and negative controls

[BUGS.md](BUGS.md) records fourteen development findings and the retained tests
that cover them. [Development failure and recovery logs](../verification/2026-10-18/regressions)
are preserved alongside the final successful campaign.

One earlier fuzz campaign was intentionally stopped after resident-memory growth
was traced to missing ARC exception cleanup. A direct deallocation test failed
before `-fobjc-arc-exceptions` was added. Its failed run is retained as historical
evidence; it is not included as a passing final gate.

A lifecycle negative control removes the early-Stop latch. The app check then
rejects that mutant with exit status 4 rather than silently hanging. Evidence
negative controls also confirm that altered raw logs, a missing gate, and a
changed source manifest are rejected by the verifier. Their
[output is retained](../verification/2026-10-18/evidence-controls.log).

## Source accounting

Measured production Objective-C, including headers: 4625 code lines in 70 files.
Native test code adds 845 lines. Python supplies 811 code lines for independent
clients, verification, measurement, and build glue. Comments, blank lines,
generated workloads, learned fuzz inputs, and evidence logs are separate.

This implementation is substantially below a 30000-line source estimate. No
claim is made that the estimate was reached. The [accounting snapshot](../verification/2026-10-18/source-size.json)
and `python3 scripts/size.py` expose the actual size.

## Recheck the record

```sh
make verify
cd verification/2026-10-18
shasum -a 256 -c SHA256SUMS
```

`make verify` checks the exact gate set, successful status, raw-log hashes, and
current source manifest. It rejects stale or altered evidence. Checksums bind
bytes and detect damage; they do not authenticate an author or prove the absence
of bugs. A changed runtime source requires a new campaign, as described in the
[developer guide](DEVELOPING.md).
