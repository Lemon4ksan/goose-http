# 014: HTTP/2 and TLS

Status: todo (asked for 2026-10-11; long horizon, after tasks 011 and 013; the split
below is a proposal for discussion, not a decision)

HTTP/2 and HTTPS are out of scope in `README.md`. A server behind snowtime-native, or in
HttpArena's TLS and h2 profiles, needs both. This task decides where they live, then
builds them in phases, each measured against the competitors as tasks 004 and 005 were.

## How the competitors split it

| Project | HTTP/1.1 and HTTP/2 | TLS |
|---|---|---|
| hyper (Rust) | One crate, with features; framing and HPACK in the separate `h2` crate | Outside, in `tokio-rustls` or `hyper-rustls` |
| xitca-web (Rust) | `xitca-http`: h1, h2, and h3 behind features | `xitca-tls`, over rustls or OpenSSL |
| Go `net/http` | h2 written in `x/net/http2`, bundled into `net/http` | `crypto/tls`, in the standard library |
| nginx, h2o (C) | One repository; h2 is a module | OpenSSL or BoringSSL, linked in |
| zzz (Zig) | HTTP/1.1 | `secsock`, its own package |
| odin-http | HTTP/1.1 only | OpenSSL, for its client only |
| may-minihttp, libreactor, the HttpArena epoll entries | HTTP/1.1 only | none |

The fast plaintext servers don't do TLS. The full servers keep h2 beside h1, as a module
or a feature, and put TLS in a layer of its own over a C library. Where the language
has packages, that layer is a package.

## Proposed split

- HTTP/2 goes in this repository, as modules of the `http` package (task 011). Framing,
  HPACK, flow control, and stream scheduling are HTTP, share the parser, the response
  builders, and the `Date`, and change the event loop itself. Goose has no runtime
  function pointers (spec §7.6), so a separate h2 package would be compiled into this
  loop through function values anyway. HPACK and the framing are bounded, table-driven
  byte work, 1,500 to 3,000 lines in other implementations, and are worth measuring in
  Goose.
- TLS goes in a separate package, `goose-tls`: a thin Goose API over a C library, with
  opaque handles and a byte-in, byte-out handshake, and the C built from its sidecar
  (`cmake_target` or `c_libs`). A program serving plaintext doesn't link the library,
  the library can change, and the exception to `AGENTS.md`'s "C is for what Goose can't
  reach" stays in one place. Writing TLS itself in Goose (constant-time crypto, X.509)
  is out of scope.
- `http` uses `goose-tls` only from a module of its own, `http.tls`, so only a program
  that imports `http.tls` declares `goose-tls` in its root file. At `efe3155` a library's
  `import` of another package is a requirement the root must declare
  (`docs/packages.md`); whether an unimported module's requirement is skipped is
  untested.
- snowtime-native, or any program, owns certificates and configuration and composes the
  two. A repository above this one can't hold h2 or TLS, because both change the loop.

Rejected: everything in this repository, because every program would link the TLS
library; h2 as its own package, because it couples to the loop through function values
and duplicates its types.

## The event loop

- A connection slot grows HPACK tables (4 KB by default; the encoder's can stay at 0
  through `SETTINGS_HEADER_TABLE_SIZE`), a stream table capped by
  `MAX_CONCURRENT_STREAMS`, flow-control windows, and partial-frame state. Keep them in
  a separate pool indexed from the slot, so an HTTP/1.1 connection stays at today's size.
- Responses on different streams interleave and wait on window updates, so the single
  spill buffer per connection becomes a queue per stream, with a round-robin scheduler
  (RFC 9113 deprecates priorities).
- Frames are up to 16 KB by default; the 8 KB read and write buffers grow, or the server
  advertises a smaller frame size where the protocol allows.
- With TLS, a read goes recv → decrypt → parser and a write the reverse. kTLS on Linux
  hands the record layer to the kernel after the handshake, so `send`, `recv`,
  `sendfile`, and io_uring carry plaintext again; KeyUpdate and alerts still need user
  space (`EKEYEXPIRED`, control messages through `recvmsg`).

## Phases

1. Record the decision in `docs/architecture/README.md`, with the TLS exception to the C
   rule, and update `README.md`'s scope.
2. `goose-tls` over OpenSSL 3 with memory BIOs, and HTTP/1.1 over TLS in the epoll loop on
   port 8443. Measure HttpArena's JSON-over-TLS profile against its Rust entries.
3. kTLS on Linux after the handshake, then TLS through io_uring; compare the two paths.
4. h2c with prior knowledge (the `PRI * HTTP/2.0` preface; HttpArena's port 8082): frames,
   HPACK, flow control, and the stream scheduler in Goose. Without TLS, its cost is h2's
   alone. Test with h2spec and HttpArena's h2c profiles.
5. ALPN `h2` over TLS: HttpArena's h2 baseline and static profiles.

Out of scope: HTTP/3 and QUIC (UDP, loss recovery, and QUIC-TLS: a project of its own),
the `Upgrade: h2c` handshake, gRPC, and WebSocket over h2.

## Open questions

- Which TLS library. OpenSSL 3 is everywhere and supports kTLS; BoringSSL is what h2o
  and many fast servers use; rustls-ffi needs a Rust toolchain in the build; BearSSL's
  callback-free engine fits Goose best but has no TLS 1.3. Check each claim before
  recording it.
- Whether h2 lands in one loop or both, which depends on task 005's decision.
- What snowtime-native needs first: TLS alone covers browsers over HTTP/1.1.

## Acceptance criteria

- [ ] The split above discussed, and the decision recorded in `docs/architecture/README.md`
      with its reasons, or this task rewritten to the one chosen
- [ ] A test that a program importing `http` without `http.tls` builds without declaring
      `goose-tls`, at the pin of the day
- [ ] HTTP/1.1 over TLS passes HttpArena's TLS validation and is measured in its
      JSON-over-TLS profile
- [ ] kTLS and user-space TLS compared on Linux
- [ ] h2c passes h2spec and is measured in HttpArena's h2c profiles
- [ ] h2 over TLS with ALPN measured in HttpArena's h2 profiles
- [ ] An HTTP/1.1 connection's memory unchanged by the h2 state, shown by `bench/run.sh`'s
      peak RSS
