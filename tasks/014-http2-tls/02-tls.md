# 014.02: HTTP/1.1 over TLS

Status: in-progress (started 2026-10-19). HTTP/1.1 over TLS 1.3 serves from the epoll
and io_uring loops, on `main`, and through kTLS on the epoll loop (2026-10-20); see
"Handover" at the end for what remains.

Task 014's phase 2: HTTPS through [goose-tls](https://github.com/kaitk/goose-tls)
(OpenSSL 3 over memory BIOs) from the module `http.tls`, for HttpArena's json-tls and
8gbit profiles on port 8081: TLS 1.3 with the mounted RSA-2048 certificate, ALPN
`http/1.1` (goose-rest's task 047). Phase 3, kTLS, comes after.

## Acceptance criteria

- [x] The TLS split recorded in `docs/decisions.md`, with what it rejects (2026-10-19)
- [x] A program importing `http` without `http.tls` builds without declaring goose-tls,
      tested (`test/http/no_tls.goose`, 2026-10-19)
- [x] HTTP/1.1 over TLS in the epoll and kqueue loop, as a listener's mode: the
      handshake, keep-alive, close_notify, the handshake's timeout, and the limits
      (2026-10-19)
- [x] The benchmark server serves TLS on its port + 1 given a certificate and key, with
      `/json` and `POST /echo` (2026-10-19)
- [x] Tests with curl, `openssl s_client`, Python's TLS client, and h2load in
      `scripts/test-http.sh`, run by `scripts/test.sh` on macOS and on Linux (2026-10-19)
- [x] The API's names agreed ("Answers" below, 2026-10-19)
- [x] HttpArena's TLS validation passed, and json-tls and 8gbit measured on Linux
      (2026-10-20, "Measured" below)
- [x] TLS in the io_uring loop, tested on macOS's emulated ring and on Linux's io_uring
      (2026-10-20); Windows' IOCP still fails with `ENOSYS` on a TLS listener

## Handover

Written 2026-10-19 at the end of the first run.

### Built

On `main`, from the branch `tls` (`1012e705`, then the answers in `a5048101`), on top of
`c5d3cd67`:

- `tls.goose`, the module `http.tls`: `TlsServer` (a worker's reference to the
  context, a 16 KB read buffer, and a slot per connection), `tls_server(ctx)`,
  `release(server)`, the two `serve_epoll`s that take a `TlsServer`, and the loop's
  calls: `tls_open`, `tls_recv`, `tls_seal`, `tls_notify`, `tls_ready`, `tls_close`.
- `epoll.goose`: the loop is now `epoll_loop<S, H>(cfg, fresh, tls)`, whose untyped
  `tls` is a `NoTls` (stubs, never called) from the `serve_epoll`s without TLS, or a
  `TlsServer`. `EpollConn.tls` (an `i32`, in the padding before `deadline`), `tls_at`
  per listener, `sealed` (the write buffer's prefix already encrypted), and TLS in
  accept, `close_conn`, `drive`, `advance`, `wait`, and `sweep`.
  [Architecture](../../docs/architecture.md#tls) describes the paths.
- `http.goose`: `Listener.tls` and `Config.tls`. `uring.goose`: `ENOSYS` for
  `Config.tls` and for a TLS `Listener`, before it opens a socket; since the merge of
  `h2c-uring` (014.01) the io_uring loop serves h2c and several listeners otherwise.
- `server/https.goose` and `server/server_epoll.goose`: the epoll build serves TLS on
  `TLS_PORT` (the port + 1) when `TLS_CERT` and `TLS_KEY` are set. `server/app.goose`'s
  `run` takes the root file's TLS setup and epoll runner as function values, so
  `server/server.goose` (uring, and Windows' IOCP) doesn't declare goose-tls.
- `bench/httparena/goose/Dockerfile`: libssl in both stages, port 8081, and
  `TLS_CERT`/`TLS_KEY` from `/certs` when HttpArena mounts it. `meta.json` lists
  json-tls and 8gbit since the validation passed (2026-10-20).
- `examples/tls`: HTTP on 8080 and HTTPS on 8443, with a certificate from the command
  line; `scripts/test-examples.sh` runs it (not on Windows, nor in
  `scripts/test-aarch64.sh`'s cross builds, which leave it out).
- Tests: `test/http/no_tls.goose`, `test/tls/undeclared.goose` (`// error:` fixture),
  `test/tls/tls_config.goose`; `scripts/http_client.py`'s `tls` and `tls-slow` modes,
  and an idle TLS connection in the graceful stop, which must get close_notify;
  `test/run_tests.py` leaves out `test/tls/` on Windows.
- Docs: `docs/decisions.md` (two entries), `docs/architecture.md` ("TLS"),
  `docs/api.md` ("HTTPS"), `docs/development.md` (OpenSSL and CMake), `README.md`'s
  status.

### What passes

Goose `dcc2747`, goose-tls `v0.0.1`.

- macOS (M1 Pro, macOS 26.3.1, Homebrew OpenSSL 3 through goose-tls's CMake):
  `scripts/test-http.sh` on the epoll build, with the TLS block: `s_client` TLS 1.3
  and ALPN http/1.1; curl `/plaintext`, `/json`, a reused connection, a 3,000,000-byte
  body echoed through `/echo`, the same as a file through `/files/`, 1,000,000 bytes of
  `/bytes`; `http_client.py tls` (tfb, pipeline, large, and keepalive over TLS, each
  close with close_notify; a TLS 1.2-only client refused with `protocol_version`;
  plaintext to the port closed unanswered); h2load `--h1 -c 64 -n 50000`, every
  request 2xx, ALPN http/1.1; `tls-slow` (a ClientHello cut short, and a whole one
  with no Finished, each closed at `REQUEST_MS`, 4 s, while another client is served);
  and the stop with an idle TLS connection, which gets close_notify.
- `scripts/test.sh` with `PORT=29780` on 2026-10-19, on the working tree that became
  this branch's commit:
  - macOS, as above: every step passes, 46 tests at -O0 and -O2 (`test/tls/`'s two
    included), the TLS block and `tls-slow` on the epoll build ("tls: not served by
    this loop" on uring), h2spec 146 of 146, and `examples/tls` in
    `test-examples.sh`.
  - Linux, arm64 in Docker Desktop on the same Mac (`ubuntu:26.04`, kernel
    7.0.14-linuxkit, `--security-opt seccomp=unconfined`, OpenSSL 3.5.5 from
    `libssl-dev`): every step passes, the same TLS checks on the epoll build; h2spec
    skipped, as on any arm64 Linux.

- Both again on `a5048101`, rebased onto `main` at `c5d3cd67` before the push to
  `main`, 2026-10-19: every step passes on macOS and on Linux, the same as above.
- Both again after the merge of `h2c-uring` (`a72f2460`, 2026-10-19): every step
  passes on macOS and on Linux, the TLS block on the epoll build beside h2c, and
  [014.01](01-h2c.md#what-passes) lists the rest.

- HttpArena's validation, 2026-10-20, on `583054e8` (Goose `f114b5ac`, goose-tls
  `v0.0.1`): `bench/httparena.sh validate` in the `goose-http-arena` container on the
  same Mac (Docker Desktop, arm64, 10 CPUs, `SERVER_CPUS=0-2 LOAD_CPUS=3-9`), with
  json-tls and 8gbit added to `meta.json`: 64 passed, 0 failed. The image builds as
  is, and `/server-tls` links Ubuntu 26.04's `libssl.so.3`. json-tls and 8gbit each
  serve the mounted certificate, negotiate TLS 1.3 with `TLS_AES_128_GCM_SHA256` and
  ALPN http/1.1, and refuse TLS 1.0, 1.1, and the weak cipher families; json-tls's
  `/json/N?m=M` matches the dataset with `application/json`; 8gbit echoes 1 B to
  100 KB byte for byte, chunked 10 KB and 100 KB, and an empty body with 200.

- TLS in the io_uring loop, on the branch `tls-uring` at `4324c388` (rebased onto
  `main` at `f793dce0`; Goose `f114b5ac`, goose-tls `v0.0.1`), 2026-10-20, on the
  same Mac and Docker Desktop:
  - `scripts/test.sh` with `PORT=29880`, macOS: every step passes, 51 tests at -O0 and
    -O2; the TLS block, `tls-slow`, and the stop with an idle TLS connection on both
    the uring loop (the ring emulated on kqueue) and the epoll loop, each from a TLS
    build (`TLS=1`); h2spec 146 of 146 on each; `examples/tls`.
  - `scripts/test.sh` with `PORT=29880`, Linux (arm64 `ubuntu:26.04` image built
    fresh, kernel 7.0.14-linuxkit, `--security-opt seccomp=unconfined`, OpenSSL
    3.5.5): every step passes, the same TLS checks on the uring build on io_uring
    itself (its first line names no emulated ring), on `LOOP=uring-epoll`, and on
    epoll; h2spec skipped, as on any arm64 Linux.
  - HttpArena's validation on `4324c388`, with the entry built `LOOP=uring` and
    `meta.json`'s `engine` `io_uring`: `bench/httparena.sh validate` as above
    (driver image built fresh, `SERVER_CPUS=0-2 LOAD_CPUS=3-9`): 64 passed, 0
    failed, with the same json-tls and 8gbit checks. The image, started as the
    harness does it (`--security-opt seccomp=unconfined`, a certificate in
    `/certs`), prints `uring loop` with no emulated ring, and `TLS on port 8081`.
  - Again on `b0bf0c20`, after the review (2026-10-20), with the TLS build back to
    `server/server_tls.goose` (`TLS=1 LOOP=epoll`), run with `LOOP=uring`: every step
    of `scripts/test.sh` passes on macOS and on Linux as above, and HttpArena's
    validation passes, 64 of 64. In the image, built plain with `LOOP=uring` and TLS
    with `TLS=1 LOOP=epoll`, and started with `LOOP=uring`, each server prints
    `uring loop` with no emulated ring.

The macOS runs are smoke tests; the comparison that counts is HttpArena's json-tls and
8gbit on Linux, below.

### Measured

HttpArena's json-tls and 8gbit on the desktop, 2026-10-20: Ryzen 7 5800X3D (16
logical CPUs), WSL2 kernel `6.18.54.1-microsoft-standard-WSL2`, Docker Desktop 29.8.2;
goose-http `fe07b188` (`env.txt` leaves the commit blank and says "modified": WSL's git
couldn't read the worktree's `.git` file, which names a Windows path; the tree was
clean), Goose `f114b5a`, goose-tls `v0.0.1`, the entry built `LOOP=uring`. First
`bench/httparena.sh validate goose`: 64 passed, 0 failed. Then
`FRAMEWORKS="goose actix ntex axum sark" PROFILES="json-tls 8gbit" bench/httparena.sh
run`: HttpArena `0720ee5`, server on CPUs 0-3, the load generator in Docker on CPUs
4-15 with 4 threads, 3 runs of 5 s each, the best kept. The Rust entries are actix,
which goose-rest models; ntex; axum, over hyper; and sark, the only Rust entry on
io_uring. `env.txt` is in `bench/results/httparena-2026-10-20-tls-Tiamat/`; the logs
stay on the desktop, as git ignores them.

json-tls (4,096 connections, wrk over TLS), requests per second in each run:

| Entry | Runs | Best | Server CPU | Memory |
|---|---|---:|---:|---:|
| sark | 212,540; 211,443; 214,683 | 214,683 | 245% | 175 MiB |
| goose | 178,611; 175,250; 188,349 | 188,349 | 258% | 272 MiB |
| ntex | 112,643; 121,314; 122,677 | 122,677 | 286% | 152 MiB |
| axum | 104,246; 97,664; 96,794 | 104,246 | 290% | 170 MiB |
| actix | 99,575; 100,600; 99,019 | 100,600 | 287% | 188 MiB |

8gbit (512 connections, zrk at a fixed 50,000 requests per second, uploads echoed):
CPU per request, from the server's cgroup over the run, and latency.

| Entry | CPU per request | p99 | p99.9 | Rate held |
|---|---:|---:|---:|---:|
| actix | 40.7 µs | 6.85 ms | 56.1 ms | 97.9% |
| goose | 42.2 µs | 0.35 ms | 43.2 ms | 95.9% |
| axum | 49.7 µs | 0.55 ms | 33.9 ms | 97.2% |
| ntex | 49.8 µs | 0.43 ms | 47.6 ms | 97.5% |
| sark | not measured | | | 0% |

- json-tls: goose is second, 12% behind sark, and 54% ahead of ntex, the next. It
  uses the most memory of the five, 272 MiB against 152-188 MiB, at 4,096
  connections: about 66 KB a connection, which suggests OpenSSL's per-connection
  buffers. This loss is unexplained.
- 8gbit: goose is second on CPU per request, 3.5% above actix, with the lowest p99.
  It held 95.9% of the rate, the least of the four that ran, so HttpArena warns that
  its CPU figure doesn't compare exactly with runs that held more.
- sark's 8gbit runs failed: every connection was refused (about 150,000 connect
  errors a run), so the entry doesn't serve that profile here.
- The TLS receive path's copy from `plain` into `rbuf` doesn't show at this level.
  The best json-tls run was 5% above the worst, more than the copy could cost on
  responses this size. A profile of the TLS server under load would isolate it, so
  the check stays pending ("What remains", item 4).

### What remains, in order

1. (Done: the names, "Answers" below.)
2. HttpArena: the image builds, the validation passes ("What passes"), and json-tls
   and 8gbit are measured against four Rust entries ("Measured", 2026-10-20). Open:
   json-tls's memory, 272 MiB against the Rust entries' 152-188 MiB. HttpArena starts every entry with `--security-opt seccomp=unconfined`
   (`scripts/lib/framework.sh` and `scripts/validate.sh` at the pinned commit, checked
   2026-10-20), so io_uring works there, and 23 entries name it as their engine. The
   entry now builds `LOOP=uring`, `meta.json`'s `engine` is `io_uring`, and the
   validation passed again on it ("What passes", 2026-10-20).
3. kTLS (phase 3): on the epoll loop since 2026-10-20; the io_uring loop and
   HttpArena remain. Docker Desktop's kernel (`7.0.14-linuxkit`) has no `tls` module;
   the desktop's WSL2 kernel has it as a module, loaded with `sudo modprobe tls`
   (`docs/known-issues.md`), and goose-tls's kernel side passes there (its task 002,
   2026-10-20).

   **Built**, on the epoll loop ([decisions](../../docs/decisions.md#ktls-is-the-contexts-choice-made-by-the-program),
   [architecture](../../docs/architecture.md#tls)): the program asks with
   `tls::use_kernel(ctx)`, and the benchmark server does with `KTLS=1` ("TLS on port
   8081 (kTLS)" in its first line). `TlsSlot.kernel`, `tls_recv`'s switch before it
   reads (with `kernel_wants` read exactly), `kernel_recv` for the socket's plaintext
   and the records that aren't data, `tls_seal` leaving plaintext once the kernel
   sends, and `tls_bye` for close_notify, called before the loop's two
   `SHUT_WR`s and by `tls_close`. `shim/net.c`'s `net_recv_record`,
   `net_record_type`, and `net_send_record` (`recvmsg`/`sendmsg` with `SOL_TLS`
   control messages); `shim/kqueue.c` has `ENOSYS` stubs. `scripts/test.sh` runs
   `test-http.sh` again with `KTLS=1` on epoll where `tcp_available_ulp` lists
   `tls`: the whole TLS block, with at least 64 connections counted into the kernel
   by `/proc/net/tls_stat`, and a request after s_client's `k` and `K` KeyUpdates.

   **Passes**, 2026-10-20, on the desktop (WSL2 kernel
   `6.18.54.1-microsoft-standard-WSL2`, OpenSSL 3.5.5, Goose `f114b5a`, goose-tls
   `v0.0.1`): every step of `scripts/test.sh` with `PORT=29880`, the kTLS pass
   included ("ktls: 102 connections in the kernel, KeyUpdates ok"), h2spec 146 of
   146 on each loop. Pending: macOS, where `kqueue.c`'s stubs are untested.

   **Measured**, the same day and machine: the TLS build (`TLS=1 LOOP=epoll`), one
   worker on CPU 0, `KTLS` unset or 1 in turn, 3 rounds; h2load over TLS on CPUs
   4-15 (8 threads, 256 connections, 16 in flight), 2,000,000 requests a run; `perf
   stat -e instructions:u,instructions:k,cycles` on the server. Per request:

   | Target | Mode | User instructions | Kernel instructions | Cycles | Requests/s |
   |---|---|---:|---:|---:|---:|
   | `/json` | user space | 4,331-4,333 | 1,008-1,011 | 4,178-4,353 | 749 K-802 K |
   | `/json` | kTLS | 2,506 | 2,181-2,184 | 4,192-4,209 | 790 K-814 K |
   | `/bytes?n=16384` | user space | 66,500-66,585 | 13,901-13,979 | 56,103-57,686 | 72.3 K-74.4 K |
   | `/bytes?n=16384` | kTLS | 8,988 | 82,608-82,940 | 92,722-94,030 | 36.0 K-37.0 K |

   On small responses kTLS moves the record layer's work into the kernel at the same
   cycles: the rate ranges overlap. On 16 KB responses kTLS is a loss, half the rate at
   1.65 times the cycles. In `perf record -C 0`, the kernel's
   `aes_gcm_enc_update_aesni_avx` takes 12% of the CPU there. The kernel's
   `gcm(aes)` is `generic-gcm-aesni-avx` (`/proc/crypto`; no VAES driver for GCM in
   this kernel). User-space OpenSSL encrypts the same bytes in fewer cycles,
   presumably with a wider AES-GCM; not checked. So kTLS stays the program's choice,
   off by default, and isn't used for HttpArena until 8gbit (uploads, which the
   kernel decrypts) is measured with it.

   **Left**, in order:
   - The io_uring loop: switch where `tls_take` runs once the ring has sent
     everything sealed, then `RECV` plaintext, `-EIO` → `RECVMSG` (or a
     synchronous `recvmsg`) for `kernel_record`, `SENDMSG` for close_notify and
     KeyUpdate in order with the ring's sends (goose-tls's task 002, "What
     goose-http's loops will need").
   - HttpArena's json-tls and 8gbit with `KTLS=1` against the user-space numbers
     above ("Measured"); the entry would need the module loaded on the host.
   - Files over kTLS through `sendfile` again, rather than `pread` in pieces.
   - Why the kernel's AES-GCM costs more here than OpenSSL's: a newer kernel's
     VAES GCM, or AES-256 and ChaCha20 suites, may change the 16 KB result.
4. (Done on `tls-uring`, 2026-10-20: TLS in the io_uring loop, and the benchmark
   server's with `LOOP=uring`.) `ring_loop` takes the TLS as `epoll_loop` does, with
   `RingConn.tls` in the padding after `state`. A receive's ciphertext goes to
   `tls_take` (`tls::feed`, then `tls::read` until `WANT_INPUT`, sharing `tls_plain`
   with `tls_recv`), and `flush` seals the write buffer before `ring_send`, so every
   TLS byte goes through the ring in order. Where epoll's `close_conn` sends
   close_notify directly, the ring queues it and closes as a refusal does (CLOSING,
   shut down once sent, `linger_ms`): for a client's close_notify, a failed
   handshake's alert, an idle timeout, and a stop. `close_conn` itself sends nothing,
   since `ring_close` drops unsent sends. The TLS build, `server/server_tls.goose`,
   serves it with `LOOP=uring` at run time.

   Plaintext on the io_uring loop costs no more since this change: 1,930.2 user
   instructions per request after it against 1,936.2 before, with no spread in
   either build's runs, so the plain path through `take` and the `c.tls` check
   stays. Measured on the desktop, 2026-10-20: Ryzen 7 5800X3D, WSL2 kernel
   `6.18.54.1-microsoft-standard-WSL2`, Goose `f114b5a`; `goose-uring` from
   `ONLY=goose bench/build.sh` at `f793dce0` (before) and `8e2baf45` (after), each
   starting with `uring loop` and no emulated ring; `RUNS=5 bench/count.sh
   goose-uring-before goose-uring` as root, interleaved: one worker on CPU 0,
   h2load on CPUs 4-15 (8 threads, 256 connections, 16 in flight on each),
   10,000,000 GETs of `/plaintext`. User cycles per request were 463-479 after and
   486-523 before, and the rate 1.67-1.70 M against 1.61-1.69 M requests per
   second.

   One check is pending, on the desktop (2026-10-20):
   - The TLS receive path's copy of the decrypted bytes from `plain` into `rbuf`,
     measured on json-tls, before anyone decrypts into `rbuf` directly.
5. Windows: goose-tls hasn't been built there; `test/tls/` and `examples/tls` are
   skipped, and `server/server_epoll.goose`'s typecheck in `scripts/test.sh` now
   fetches goose-tls there too (untried).
6. Smaller points:
   - A TLS connection's file responses go through `pread` in pieces at any size;
     with kTLS they could go back to `sendfile`.
   - On epoll, `tls_close` sends close_notify or an alert with one nonblocking
     `send`, and drops it if the socket doesn't take it.
   - On the ring, a TLS connection closed by an idle timeout or a stop lingers up to
     `linger_ms` for the client to close, where epoll closes it at once; a stop can
     take that long, within `grace_ms`.
   - OpenSSL's `SSL_new` failing at accept closes the socket without a report: the
     shim's error codes have no `ENOMEM`.

### Traps

- A struct may have one resizable field, and it must be last: `TlsServer`'s read
  buffer is a fixed `u8[16384]`, and its free slots a list threaded through the slots.
- A program's own subdirectory named like a package (`lib/` beside a root that
  declares `lib`) makes `import lib.tls` an error ("both a file of this package and the
  declared package's module"); keep test libraries outside the program's directory.
- `tls::shutdown` before `tls::write` fails the write: seal the response first, then
  queue close_notify (`tls_seal`'s `last`).
- `tls::read` returns one record at most; `tls_recv` reads until `WANT_INPUT` before
  calling the socket empty, or edge-triggered epoll never reports the records
  OpenSSL already holds.
- Python's `ssl` sockets can't send and receive on one connection from two threads,
  so `http_client.py`'s `stream` doesn't run over TLS; curl echoes the large body.
- `openssl s_client -brief` doesn't print the ALPN protocol; `test-http.sh` reads the
  full output.
- The scratchpad of a session may be shared by several agents: keep logs and exported
  trees in a directory of one's own.

### Commands

```sh
python3 test/run_tests.py no_tls tls
LOOP=epoll scripts/build.sh
openssl req -x509 -newkey rsa:2048 -nodes -keyout k.pem -out c.pem -days 2 -subj /CN=localhost
TLS_CERT=c.pem TLS_KEY=k.pem build/server http 8080      # TLS on 8081
curl -k https://127.0.0.1:8081/json
openssl s_client -connect 127.0.0.1:8081 -alpn http/1.1 </dev/null
python3 scripts/http_client.py 8081 tls
PORT=29780 scripts/test.sh
```

### Answers

Agreed 2026-10-19, and recorded in
[decisions](../../docs/decisions.md#tls-is-a-listeners-mode):

1. The names stay as built: `Config.tls` and `Listener.tls`; `http::TlsServer`,
   `http::tls_server(ctx)`, and `http::release(server)`; and
   `http::serve_epoll(cfg, server)` and `http::serve_epoll(cfg, fresh, server)`, the
   `TlsServer` last, rather than a `serve_tls` of its own, which would need another
   name again for io_uring.
2. The benchmark server's `TLS_PORT` defaults to the port + 1 (8081), as `H2C_PORT`
   does to the port + 2, but only when `TLS_CERT` and `TLS_KEY` are set.

### Questions for the user

None open.
