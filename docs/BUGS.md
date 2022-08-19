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
