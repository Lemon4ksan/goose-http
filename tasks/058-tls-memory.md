# 058: TLS connections' memory

Status: todo (asked for 2026-10-20)

On HttpArena's json-tls, at 4,096 connections, the Goose entry used 272 MiB, the most
of the five measured: ntex 152, axum 170, sark 175, and actix 188 MiB (task 014.02,
"Measured", 2026-10-20). That's about 66 KB a connection. Memory is goose-http's lead
(task 057), so TLS shouldn't give it away.

The likely cause, not yet measured: OpenSSL keeps a read and a write buffer of about
16 KB each on every connection, idle ones included, plus its memory BIOs in goose-tls.
OpenSSL's `SSL_MODE_RELEASE_BUFFERS` frees them between records. If that's the cause,
the fix is in goose-tls's context setup, and goose-http doesn't change. goose-http's
own share is a `TlsSlot` a connection and one 16 KB `wire` buffer per worker.

## Acceptance criteria

- [ ] Memory per TLS connection measured on Linux, idle after the handshake and at
      json-tls's load, split between OpenSSL, goose-tls's buffers, and goose-http's
- [ ] `SSL_MODE_RELEASE_BUFFERS`, or what the measurement points to instead, tried:
      the memory and json-tls's rate with and without it
- [ ] Taken where it saves memory at no cost in rate beyond the runs' spread, or
      recorded here with its numbers
- [ ] json-tls rerun against the Rust entries, its memory recorded in 014.02

## Notes

- Measure as the benchmarks do (`agents/benchmarks.md`): the TLS build (`TLS=1`),
  `LOOP=uring` as the entry runs, 4,096 connections. Idle memory can come from
  connections opened and left idle, read from `/proc/PID/status` as task 025 does.
- A fix in goose-tls goes there, under its own task, and moves this repository's pin.
