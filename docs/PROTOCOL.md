# HTTP contract

The listener is a reverse proxy for a single configured origin in record mode,
and an origin replacement in replay mode. Point the client at the loopback
listener URL. Do not configure it as a browser's general forward proxy.

## Accepted messages

- Request versions: HTTP/1.0 and HTTP/1.1.
- Request target: ASCII origin form beginning with `/`, at most 8192 bytes.
- Percent escapes must contain two hexadecimal digits. Fragments, spaces,
  backslashes, control bytes, and absolute-form targets are rejected.
- Methods are bounded HTTP tokens. Matching is case sensitive.
- HTTP/1.1 requests require exactly one nonempty Host field.
- Response statuses: 200 through 599. Interim 1xx and protocol upgrades are
  unsupported and become explicit upstream failures.
- Header pairs preserve order and repetition. Names are HTTP tokens, values
  permit horizontal tab and Latin-1 field bytes, and CR/LF injection is rejected.

The head is limited to 64 KiB and 128 header pairs. Names are at most 256
characters and values at most 8192 characters. The decoded body limit is 8 MiB.

## Framing precedence

| Input | Result |
| --- | --- |
| One decimal Content-Length | Read exactly that many bytes |
| Repeated Content-Length, even identical | Reject ambiguity |
| Content-Length plus Transfer-Encoding | Reject ambiguity |
| Transfer-Encoding exactly `chunked` | Decode bounded chunks |
| Any other transfer coding | Reject |
| Request with neither framing field | Empty body |
| Response with neither framing field | Read through EOF |
| Response to HEAD, or status 204/304 | No entity bytes |

Chunk sizes are hexadecimal without extensions. Chunk trailers are unsupported.
The terminal zero chunk must be followed by its empty trailer terminator. EOF
before the declared length or final chunk is an incomplete response, not a
successful short body.

Expect/continue handshakes and upgrades are rejected. Send the request body
without Expect. HTTP/2, WebSockets, CONNECT tunnels, multipart streaming, and TLS
interception are outside the implementation boundary.

## Forwarding

Sluice resolves the configured origin once at reactor construction, retains up to
16 IP addresses, and attempts nonblocking connections in resolver order. DNS
resolution is a startup operation and is not subject to the reactor's request
inactivity timeout. Use an IP literal for entirely local deterministic setups.

Upstream URLs must be `http://host[:port]` without credentials, path, query, or
fragment. A request's Host is replaced by that origin authority. The original
path and query are retained for live forwarding.

Hop-by-hop fields, including additional names listed by Connection, are removed.
Transfer framing is normalized to Content-Length and `Connection: close`.
Set-Cookie multiplicity is preserved in the message model. An explicit scenario
header replacement replaces all occurrences of that field.

There is one exchange per connection. Coalesced bytes after a complete request
are rejected; bytes sent later are never dispatched as a second exchange. Every
normal response closes the connection. The origin's keep-alive behavior therefore
does not affect replay.

## HEAD and representation metadata

No response body is sent for HEAD. A recorded HEAD response can still advertise
the size of the corresponding representation. That validated metadata survives
capture and replay. A 204 response omits Content-Length. A 304 response emits no
body and may retain representation length metadata.

## Deliberate truncation

Truncation changes the transmitted entity prefix while retaining the full
advertised Content-Length. A strict client should observe an incomplete body.
The delivery receipt can still have outcome `complete`: this means every byte
in the deliberately short plan was accepted by the socket, not that HTTP entity
framing completed successfully at the client.

## Timing

Relative plan time starts after a complete baseline response is available. Record
mode buffers the origin response before this point. Delay does not include DNS,
connect time, request upload, or origin response time.

The head becomes due at `delayMs + jitter`. The first body chunk is due at the
same time. For subsequent chunks, due time is the cumulative preceding body
bytes divided by bytesPerSecond, rounded upward to a microsecond. This is paced
application output with a burst of at most one chunk. TCP may coalesce writes or
split them differently. Sluice does not claim to control packet boundaries.

No pacing rate means all chunks are due immediately after the delay. The reactor
still uses a fairness budget and handles partial writes and EAGAIN.

## References

The message grammar and framing terminology follow
[RFC 9112](https://www.rfc-editor.org/rfc/rfc9112.html). Sluice deliberately accepts
a narrower subset, documented above, instead of silently guessing at unsupported
framing or connection semantics.
