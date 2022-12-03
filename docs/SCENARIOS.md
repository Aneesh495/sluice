# Scenarios and state tapes

A scenario changes a baseline response. A tape chooses which recorded baseline
state exists at each occurrence. They can be combined.

## Scenario document

```json
{
  "version": 1,
  "name": "Retry after a partial catalog response",
  "seed": 41,
  "rules": [
    {
      "id": "first-attempt-short-body",
      "match": {"method": "GET", "pathPrefix": "/catalog"},
      "limit": 1,
      "action": {"delayMs": 80, "jitterMs": 20, "truncateAfter": 12}
    }
  ]
}
```

The compiler rejects unknown keys, duplicate ids, incorrect types, fractional
integer fields, and out-of-range values. It also rejects duplicate JSON object
keys before schema validation. A misspelled delay field cannot silently turn
into a no-op.

## Match predicates

| Field | Meaning |
| --- | --- |
| `method` | Exact case-sensitive method token |
| `path` | Exact encoded path, excluding query |
| `pathPrefix` | Encoded path prefix, excluding query |
| `headers` | Object from field name to an exact field value |

All specified predicates must match. `path` and `pathPrefix` are mutually
exclusive. Header names are case insensitive; values are exact, and a repeated
field matches if one value matches. An empty matcher matches every request.

Predicates see the filtered request. A secret header predicate must therefore
match `[redacted]`, not a live credential. This keeps recording and offline
selection consistent.

A prefix is literal, not a glob or path-segment matcher. `/api` also matches
`/apiculture`. Use `/api/` when the trailing slash matters.

## Ordinal selection

Each request identity has an independent occurrence counter starting at one.
A rule is eligible when:

```
occurrence > after
relative = occurrence - after - 1
relative mod every == 0
limit == 0 OR relative / every < limit
```

Defaults are `after: 0`, `every: 1`, `limit: 0`, and `chancePermille: 1000`.
A zero limit means unlimited eligible positions. The limit counts positions,
not successful random draws. `chancePermille` ranges from 0 to 1000.

Rules are tested in document order. The first predicate and ordinal/chance match
wins. Rules are not accumulated. If none match, the baseline passes through.

Hash draws use a domain-separated JSON tuple containing the seed, rule id,
request identity, occurrence, and purpose. Chance and jitter have different
purpose labels. There is no global PRNG whose state depends on unrelated traffic.
Modulo sampling has the small finite-word bias expected from direct 64-bit
modulo reduction; this is reproducible failure selection, not statistical
inference or cryptographic random sampling.

Concurrent equal-identity requests receive ordinals in the order the reactor
finishes parsing them. Their thread launch order is not a replay guarantee.

## Response actions

| Field | Default | Range or behavior |
| --- | --- | --- |
| `status` | Baseline | 200 through 599 |
| `bodyText` | Baseline | UTF-8 replacement, at most 1 MiB characters |
| `bodyJSON` | Baseline | Canonical JSON replacement, at most 1 MiB encoded |
| `headers` | None | Ordered name/value replacement pairs |
| `removeHeaders` | None | List of case-insensitive field names |
| `delayMs` | 0 | 0 through 60000 |
| `jitterMs` | 0 | Add a deterministic draw from 0 through this value |
| `bytesPerSecond` | 0 | 0 means unpaced; maximum 1000000000 |
| `chunkBytes` | 16384 | 1 through 1048576 |
| `truncateAfter` | Unset | Keep this many entity bytes, maximum 8 MiB |
| `disconnect` | false | Close without sending response bytes after the delay |

`bodyText` and `bodyJSON` are mutually exclusive. Replacing a body removes stale
encoding, ETag, Content-MD5, and Digest fields and selects a matching content type.
An explicit headers action runs afterward. Final wire encoding owns framing and
hop-by-hop fields, so a configured Content-Length does not override the actual
plan. Statuses 204 and 304 suppress entity bytes.

A plan whose final chunk is due after 120 seconds is rejected. Inspect a scenario
against a fixture before running a very slow pace:

```sh
build/sluice plan --workspace work/session --fixture UUID \
  --scenario examples/outage.json --occurrence 1
```

The plan reports effective advertised, delivered, and wire byte counts. A
truncate value larger than the body leaves it intact and reports `truncated:
false`. `truncateAfter: 0` emits the head and no entity bytes. Disconnect emits
neither head nor entity.

## Record changing state

A dependency may answer `pending`, then `ready` for identical requests. The
ordinary index refuses that ambiguity. A tape makes the sequence explicit.

First record both responses in one session. The readiness event contains its
session UUID. Then run:

```sh
build/sluice tape --workspace work/session --session SESSION_UUID \
  --output work/job-sequence.json
build/sluice replay --workspace work/session --privacy examples/privacy.json \
  --tape work/job-sequence.json --scenario examples/outage.json
```

A generated tape groups receipt fixture references by identity and sorts by
occurrence. It rejects missing fixtures, gaps, duplicate ordinals, and incomplete
recorded exchanges. Cross-identity interleaving is intentionally absent.

```json
{
  "version": 1,
  "name": "job transitions",
  "repeatLast": false,
  "streams": [
    {"identity": "64-character request digest", "fixtures": ["FIRST_UUID", "SECOND_UUID"]}
  ]
}
```

The example above illustrates the shape; use generated UUIDs and digests for a
valid tape. A tape is validated against workspace fixtures before listening.
Exhaustion returns 409 `tape.exhausted`. Add `--repeat-last` when creating the
tape to keep returning its final state. This behavior is explicit and applies
independently to each identity.

A fixture pin and a tape are mutually exclusive. Tape selection consumes one
baseline state for each parsed matching request, even when a scenario then
changes that state's status, body, or delivery.
