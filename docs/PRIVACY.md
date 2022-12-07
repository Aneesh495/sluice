# Privacy boundary

The store API accepts a filtered fixture, never an original request or response.
Live forwarding and stored observations are separate representations. This is
necessary because a useful live request may contain credentials that do not
belong in a reusable offline fixture.

## Default policy

```json
{"version": 1, "bodies": "omit"}
```

The default captures metadata and omits every nonempty entity. Such a recording
is intentionally not replayable when either body was omitted. It does not
silently replay an empty response in place of missing bytes.

Opt into JSON body capture with a policy file:

```sh
build/sluice record --workspace work/session --upstream http://127.0.0.1:9000 \
  --privacy examples/privacy.json
```

The app's Privacy button loads the same document. It shows the selected body mode
and policy digest. Replay must use the recording policy, including configured
extra field names.

## Always-filtered names

| Location | Case-insensitive names |
| --- | --- |
| Headers | Authorization, Proxy-Authorization, Cookie, Set-Cookie, X-API-Key |
| Query | token, access_token, password, secret, key, api_key, authorization |
| JSON keys | password, secret, token, access_token, api_key, authorization |

Configured `headers`, `query`, and `jsonKeys` arrays add names. They cannot remove
the defaults. Values are replaced by `[redacted]`. Query replacements use the
percent-encoded marker, preserving the original parameter name and order.

Query name matching decodes valid percent escapes and treats plus as a space.
Encoded names such as `to%6Ben` still match `token`. Invalid UTF-8 in a query name
fails closed instead of falling through an unfiltered capture path. The query
separator is `&`; no alternate framework-specific query grammar is inferred.

## JSON body capture

`bodies: "json"` accepts `application/json` and media types ending in `+json`.
Parameters such as charset do not change recognition. Input must pass the strict
JSON reader. The filter descends through objects and arrays and replaces values
at configured keys. It then stores canonical sorted-key JSON bytes.

Malformed JSON, unsupported media types, and compressed bodies stay omitted.
The engine does not guess that an arbitrary text or binary body is safe. HAR
content is decoded according to the archive representation before it enters the
same filter.

Header and query filtering applies even when bodies are omitted. Filtered JSON
also drops stale content hashes and encoding metadata. Empty response bodies
retain validated representation length metadata where HEAD requires it.

## Request identity

The identity is SHA-256 over a domain-separated JSON tuple containing:

1. Identity schema label `sluice.request.v1`.
2. Exact method token.
3. Filtered encoded target, including query order.
4. Body state (`json`, `empty`, or `omitted`).
5. SHA-256 of the filtered body bytes.
6. Ordered Content-Type field values.
7. Ordered Accept field values.

Host is absent because the loopback listener replaces the origin. Canonical JSON
makes object-key order irrelevant for JSON request bodies. Query order, encoded
path spelling, and Accept values remain exact.

Redaction can collapse different original requests into the same identity. The
fixture index therefore refuses differing responses unless a fixture pin or
state tape makes the choice explicit. It also refuses unsupported Vary fields.
Supported Vary identity fields are Accept and Content-Type.

## What the filter does not infer

The policy matches names, not the meaning of arbitrary text. A secret embedded in
a path, an unconfigured header, a JSON value under an ordinary key, a status
reason, or a nested string containing another document can remain in metadata or
captured JSON. Add the appropriate names or keep bodies omitted. No regular
expression or language model claims to discover all secrets.

Lengths, timing, method, target shape, selected rule, and content digests remain
observable. Receipts contain a digest of intended wire bytes, including live
bytes that might have been omitted from a fixture. A digest is not the raw
secret, but it can confirm guesses about low-entropy content. This is a local
engineering tool, not an anonymization system.

## Storage and sharing

Workspaces are owned directories restricted to mode 0700. The database and
atomic exports use mode 0600. SQLite WAL pages only receive filtered fixture
bytes and receipt documents. The integration suite scans the database and live
WAL for sentinel credentials, query values, and JSON secrets.

File reads use O_NOFOLLOW and verify the opened regular file with fstat. Workspace
and database symlinks are rejected at the direct boundary. This is not a defense
against an attacker who controls the account or races ancestor directory
replacement. Bundle checksums detect accidental damage, not a malicious sender
who can recompute them.

There is no telemetry, account, cloud service, certificate installation, root
helper, system proxy change, or automatic remote upload. Exports are explicit
local files. Review a filtered fixture before sharing it.
