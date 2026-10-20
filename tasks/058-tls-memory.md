# 058: TLS connections' memory

Status: in-progress (measured, and goose-tls's fix is on its `main`, 2026-10-20; the
goose-tls release, the pin move, and json-tls's rerun are open)

On HttpArena's json-tls, at 4,096 connections, the Goose entry used 272 MiB, the most
of the five measured: ntex 152, axum 170, sark 175, and actix 188 MiB (task 014.02,
"Measured", 2026-10-20). That's about 66 KB a connection. Memory is goose-http's lead
(task 057), so TLS shouldn't give it away.

The guess was OpenSSL's record buffers, which `SSL_MODE_RELEASE_BUFFERS` frees between
records. goose-tls has set that mode on every context since its first shim (`185db3b`),
and without it a connection would hold twice as much. The measurement below found the
memory instead in OpenSSL's own state, in goose-tls's memory BIOs, and in the
handshakes in flight when 4,096 clients connect at once. goose-http's share is under
1%. goose-tls now frees a memory BIO's buffer once it's empty (its task 004).

## Acceptance criteria

- [x] Memory per TLS connection measured on Linux, idle after the handshake and at
      json-tls's load, split between OpenSSL, goose-tls's buffers, and goose-http's
      ("Measured", 2026-10-20)
- [x] `SSL_MODE_RELEASE_BUFFERS`, or what the measurement points to instead, tried:
      the memory and json-tls's rate with and without it ("Freeing the BIOs'
      buffers")
- [x] Taken where it saves memory at no cost in rate beyond the runs' spread, or
      recorded here with its numbers: on goose-tls's `main`, `6fc4279`
- [ ] json-tls rerun against the Rust entries, its memory recorded in 014.02. It waits
      for a goose-tls release with the change and this repository's pin moved to it
      (the tag in `tls.goose`, `server/server_tls.goose`, `test/tls/tls_config.goose`,
      and `examples/tls/tls.goose`): HttpArena builds goose-tls at that tag.

## Measured

On the desktop, 2026-10-20: Ryzen 7 5800X3D (16 logical CPUs), Ubuntu 26.04 in WSL2,
kernel `6.18.54.1-microsoft-standard-WSL2`, OpenSSL 3.5.5, gcc 15.2; goose-http
`7e5b7c18`, Goose `f114b5a`, goose-tls `v0.0.1`. The server is `TLS=1 LOOP=epoll
scripts/build.sh`'s, run with `LOOP=epoll` or `LOOP=uring`, with an RSA-2048
self-signed certificate, as HttpArena's is. Plain connections go to the same server's
plain port. Its clients, Python's `ssl` and h2load, use OpenSSL 3.5.5, which offers
X25519MLKEM768 first, so every handshake measured used it.

### Idle

A Python client opens N connections one after another, completes each handshake, and
sends one `GET /json/10?m=3`, then holds them; the server's `VmRSS` from
`/proc/PID/status` before and while they're held, over N, gives a connection's cost.
One run each; the two configurations repeated three times gave the same figure to
within 0.1%. A request changed nothing over the handshake alone, and `VmHWM` equalled
the held RSS, so what's held is the connections' state, not a peak.

| Loop | Workers | Plain, 1,024 | Plain, 4,096 | TLS, 1,024 | TLS, 4,096 |
|---|---:|---:|---:|---:|---:|
| epoll | 1 | 256 B | 257 B | 34,500 B | 34,513 B |
| epoll | 4 | 268 B | 262 B | 34,772 B | 34,583 B |
| uring | 1 | 1,268 B | 570 B | 35,516 B | 34,802 B |
| uring | 4 | 4,376 B | 1,576 B | 39,072 B | 35,821 B |

(io_uring's plain figures include its provided buffers, touched as the first requests
arrive, which spread over fewer connections at 1,024.)

### Where it goes

A C program makes connections as goose-tls's shim does: the same context settings,
`SSL_MODE_RELEASE_BUFFERS`, and two memory BIOs. It completes 4,096
handshakes in memory against OpenSSL clients, frees the clients, and counts the bytes
OpenSSL holds through `CRYPTO_set_mem_functions`, by the source line that allocated
them. The total, 32,798 B a server connection after one request, and glibc's in-use
bytes (34,514 B), match the server's 34.5 KB, so idle memory is OpenSSL's and
goose-tls's:

| Holder | Bytes | What |
|---|---:|---|
| OpenSSL: record layers | 8,848 | two `OSSL_RECORD_LAYER`s, read and write (`tls_common.c:1262`) |
| OpenSSL: connection | 5,576 | `SSL_CONNECTION` (`ssl_lib.c:737`) |
| OpenSSL: ML-KEM key | 6,384 | the client's X25519MLKEM768 key share, expanded, kept as `s3.peer_tmp` until `SSL_free` (`ml_kem.c:2114`) |
| OpenSSL: the rest | 6,826 | AES-GCM contexts, certificate and session references, digests, locks |
| goose-tls: memory BIOs | 5,164 | the buffers' capacity: received 1,948, to send 3,216, after the handshake and a 1.2 KB response |
| goose-http | about 300 | the loop's connection, as a plain one's 256 B, and a `TlsSlot`'s few dozen bytes |

The memory BIOs' buffers keep the size of the most each has held, for as long as the
connection lives: after json-tls's seven responses, the largest of them 8,545 B, they
held 11,120 B, and OpenSSL's total was 38,754 B. Without `SSL_MODE_RELEASE_BUFFERS`
the total is 66,083 B: the mode already saves 33 KB a connection. goose-http's 16 KB
`wire` buffer, `rbuf`, and `wbuf` are per worker.

### Under load

The server on CPUs 0-3, h2load on CPUs 4-15 (`h2load --h1 -c 4096 -t 4 -D 10 -i
uris`, json-tls's seven URIs), as HttpArena places them. The server's peak RSS,
sampled every 0.2 s, over its RSS before, per connection, one run each:

| Loop | Workers | TLS | Plain |
|---|---:|---:|---:|
| uring | 4 | 55,394 B (229 MiB peak) | 2,683 B |
| uring | 1 | 55,633 B | 901 B |
| epoll | 4 | 53,315 B | 330 B |
| epoll | 1 | 54,936 B | 305 B |

The peak comes from the handshakes, not the requests. RSS reaches it within the first
second, while the 4,096 clients connect (h2load's connect times run to 0.8 s), stays
flat through the run, and stays after every connection has closed (222-223 MiB). A
handshake in flight, its ClientHello read and its flight sent, holds 62,854 B on the
server (the C program, stopped there): with it, OpenSSL's 16 KB handshake message
buffer grown to 21,848 B and an 8,192 B buffering BIO on the write side, neither of
which OpenSSL lets a program size. With about 1,000
handshakes in flight on each worker at once, glibc's heap grows to hold them, and the
pages they free stay between the connections' long-lived state.

HttpArena's figure is `docker stats`' peak, the container's memory less its inactive
files, which counts the kernel's socket memory too: `/proc/net/sockstat` put TCP's at
33-49 MiB at this load, for plain and TLS alike. The server's peak of 218-229 MiB and
that come to about HttpArena's 272 MiB.

## Freeing the BIOs' buffers

`SSL_MODE_RELEASE_BUFFERS` was already on, so the measurement pointed at goose-tls's
memory BIOs instead. The change, in goose-tls's shim: once a BIO is empty, after
`tls_drain` for the bytes to send, and after `tls_read` and `tls_handshake` for the
bytes received, its buffer is freed. goose-http was built against the change from a
copy whose `tls.goose`, `server/server_tls.goose`, `test/tls/tls_config.goose`, and
`examples/tls/tls.goose` import goose-tls from a clone by a relative path in place of
`"github.com/kaitk/goose-tls@v0.0.1"`, as the server imports the package as `"../"`.

Idle, as above, 3 runs each, interleaved:

| Loop, workers, connections | Before | After |
|---|---:|---:|
| uring, 4, 4,096 | 35,815-35,830 B | 30,444-30,453 B |
| epoll, 1, 1,024 | 34,500 B | 29,124 B |

Under load: `h2load --h1 -c 4096 -t 4 -n 3000000 -i uris`, placed as above, with
`perf stat -e instructions,cycles,task-clock -p` on the server for the run, and its
`VmHWM` after; 4 runs each, interleaved, 4 workers:

| Loop | Build | Requests/s | Instructions/request | Cycles/request | Peak RSS |
|---|---|---|---:|---|---|
| uring | before | 221,108-227,010 | 81,038-81,081 | 65,960-67,654 | 223-232 MiB |
| uring | after | 222,800-225,225 | 83,164-83,178 | 67,544-68,848 | 214-221 MiB |
| epoll | before | 209,470-220,272 | 81,089-81,117 | 75,696-76,881 | 212-215 MiB |
| epoll | after | 215,348-223,952 | 83,544-83,580 | 74,722-76,409 | 202-210 MiB |

- An idle connection is 5.4 KB smaller (15%); the peak under load is about 10 MiB
  lower (4%), since the handshakes in flight set it.
- Rate stays within the runs' spread on both loops. The change costs 2.6% more
  instructions a request, a `malloc` and a `free` of each buffer; cycles a request
  rose 1.9% on io_uring, the ranges touching, and fell 1.3% on epoll. goose-tls took
  it (its decision, 2026-10-20).
- Freeing the buffer through `BUF_MEM_free`, which `BIO_set_mem_buf` calls, cost 6.7%
  more instructions a request (81,059 to 86,500 on io_uring, 4 runs each): it cleanses
  the whole buffer, 11 KB a response. A new `BUF_MEM` each time instead of the cleanse
  still cost 3.0%. The shim frees the data itself and keeps the `BUF_MEM`.
- Tests, 2026-10-20, on the desktop with the `tls` module loaded: goose-tls's
  `scripts/test.sh` on the change, at its own Goose pin (`v2026.2`), passed, the kTLS
  steps included; this repository's `PORT=29880 scripts/test.sh` at `7e5b7c18`, built
  against the change as above with Goose `f114b5a`, passed, its kTLS pass included.

What remains is OpenSSL's, with no setting to reduce it. Not offering ML-KEM would save
6 KB a connection, but that is a choice of key exchange, not of memory. The handshakes'
peak would fall only with fewer handshakes in flight on a worker at once, a policy for
goose-http's loops that this task doesn't take up.

## Notes

- Measure as the benchmarks do (`agents/benchmarks.md`): the TLS build (`TLS=1`),
  `LOOP=uring` as the entry runs, 4,096 connections. Idle memory can come from
  connections opened and left idle, read from `/proc/PID/status` as task 025 does.
- A fix in goose-tls goes there, under its own task, and moves this repository's pin.
