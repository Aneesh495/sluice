# Developer guide

## Toolchain

The normal build needs macOS, Apple Command Line Tools, and Python 3.9 or newer. Install the
Command Line Tools with `xcode-select --install` if `xcrun clang` is unavailable.
There is no generated Xcode project or dependency installation step. Foundation,
AppKit, CommonCrypto, BSD sockets, and SQLite are supplied by macOS.

`make` builds the command line. `make app` creates a normal application bundle.
The deployment target is macOS 13. Building on an SDK does not establish runtime
coverage for every older release; consult the verification record for actual
hosts.

```sh
make
build/sluice doctor
make app
open build/Sluice.app
```

A command-line workspace is always explicit. The app defaults to its normal
Application Support directory when no workspace argument is given. Examples and
the demo use project-local workspaces. `make clean` removes build outputs; it does
not remove the default demo workspaces under `work/`.

## Build validity

Objects are keyed by source bytes, public headers, compiler command, and compiler
version. The helper uses atomic staging and marker publication. Link steps always
run. This avoids a same-second timestamp issue in the system make implementation.

A changed header invalidates all objects. This is deliberately conservative for a
small dependency-free project. Different instrumentation configurations use
separate build directories.

```sh
make BUILD=build/debug EXTRA_FLAGS='-O0'
make BUILD=build/sanitize EXTRA_FLAGS='-fsanitize=address,undefined -O1' all test
```

Normal compiler flags include ARC, blocks, warnings as errors, debug symbols, and
a consistent macOS deployment target. The formatting style is in `.clang-format`.
Formatting tools are optional developer tools and are not required to clone and
run the project.

## Test layers

| Command | What it establishes |
| --- | --- |
| `make test` | Native schemas, parsing, privacy, schedules, plans, persistence, tapes, analysis, regressions |
| `make integration` | Independent Python clients over real sockets, including long delay and TCP half-close |
| `make differential` | 1200 generated response semantics compared with Python's HTTP parser |
| `python3 Tests/Integration/test_build.py` | Content cache invalidation despite unchanged file timestamps |
| `make app-smoke` | Background native window rendering and stop-before-publication lifecycle |
| `make analyze` | Analyzer diagnostics checked from plist outputs for every production translation unit |
| `make sanitize` | Native tests under address and undefined-behavior sanitizers |
| `make coverage` | Instrumented unit, CLI integration, and native app execution coverage |
| `make fuzz` | libFuzzer parser fragmentation and strict JSON campaign |
| `make acceptance` | Full source-bound campaign with raw logs and gate status |
| `make verify` | Validate published evidence hashes, required gates, and current source binding |

A passing parser test does not establish network delivery. That is why truncation,
pacing, half-closes, concurrent clients, WAL recovery, and privacy scans have real
socket/database tests. Conversely, green socket tests do not establish that an
arbitrary unsupported protocol is accepted.

The fuzzer compares whole-input and fragmented parsing for accepted inputs. It
also exercises the strict JSON reader and scenario compiler. Apple's Command
Line Tools do not ship libFuzzer on all versions. Use a separate LLVM compiler
when needed:

```sh
brew install llvm
make fuzz FUZZ_CC="$(brew --prefix llvm)/bin/clang" FUZZ_RUNS=1000000
```

The full acceptance command reports a missing fuzz runtime as a failure. It does
not silently substitute a smoke test or reduce the requested campaign.

## Reproduce a failure

A domain error is a structured code and message on stderr, with status 2. The
workbench deliberately avoids echoing request bodies into diagnostics. Use
`fixtures --id UUID`, `plan`, `receipts`, and `report` to inspect filtered evidence.

```sh
build/sluice fixtures --workspace work/session --id UUID
build/sluice plan --workspace work/session --fixture UUID \
  --scenario examples/outage.json --occurrence 2
build/sluice diff --workspace work/session --before FIRST_UUID --after SECOND_UUID
```

Connect LLDB to a debug build for descriptor and state inspection:

```sh
lldb -- build/debug/sluice replay --workspace work/session \
  --privacy examples/privacy.json --port 0
```

Useful breakpoints are `-[SLReactor requestReady:]`,
`-[SLReactor originEvent:events:]`, `-[SLReactor writeClient:]`, and `SLFail`.
Do not print raw credential-bearing messages into an artifact you intend to share.

## Add a regression

1. Reproduce the failure with a test at the lowest meaningful boundary.
2. Run it against the failing implementation and retain the raw failure output.
3. Fix the ownership, framing, schema, or scheduling rule that caused it.
4. Run the new test and the related integration layer.
5. Add a short entry to `BUGS.md` with the cause and retained test name.
6. Regenerate acceptance evidence when production, tests, examples, or scripts change.

Do not replace an assertion with a weaker one to obtain a green report. A plan
should state an effective no-op truthfully, for example a truncation limit above
the body length, rather than inventing a fault event.

## App checks

The smoke renderer captures only the application's own content view. It does not
capture the user's display. It stays in the background and saves a local PNG.

```sh
build/Sluice.app/Contents/MacOS/Sluice --workspace work/session \
  --privacy examples/privacy.json --scenario examples/outage.json \
  --snapshot build/workbench.png --smoke
```

`--exercise` starts replay on an ephemeral port and immediately requests Stop
before background startup publishes its reactor. A timeout makes the lifecycle
check fail. Normal application startup does not execute this test path.

## Verification evidence

The source manifest covers production source, tests, scripts, examples, and build
configuration. A full run freezes that manifest before its first gate and checks
it again after the last gate. It preserves all gate output, including failures.

The verifier requires the exact gate set, successful exit status, matching raw-log
hashes, and an exact current source manifest. It fails on missing or stale files.
This is reproducibility bookkeeping, not a signature or an independent proof of
correctness. Read the tests and the raw observations behind the result.

## Recoverable exceptions and ARC

Sluice enables `-fobjc-arc-exceptions` explicitly. Validation failures recover at
well-defined adapter and connection boundaries; they are not process-terminal
programmer failures. Ordinary Objective-C ARC omits strong-local releases during
exception unwinding unless this option is enabled. A precise-lifetime probe in
the native suite checks deallocation after a recovered throw. Keep the flag when
adding build configurations.
