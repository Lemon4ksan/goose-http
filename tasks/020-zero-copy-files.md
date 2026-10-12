# 020: Files without copying on io_uring and IOCP

Status: done (asked for 2026-10-12; measured on the desktop 2026-10-12)

`http::serve` reads a file with `pread`, 64 KB at a time, into the write buffer at each
`MORE`, and the ring copies that into a send record: two copies through the program,
where the epoll loop's `sendfile` makes none. On the laptop of task 013, a 1 MB file
went out at 1.14-1.16 GB/s on io_uring against 6.5-7.0 GB/s on epoll. Each platform
has a way without the copies:

- io_uring: `IORING_OP_SPLICE` from the file into a pipe, and from the pipe into the
  socket, both queued on the ring, as h2o sends files on io_uring (recalled, not
  checked in code). `IORING_OP_SEND_ZC` from registered buffers saves only the send's
  copy.
- IOCP: `TransmitFile`, Windows' sendfile, completes on the port as any request does.
- The emulated ring runs over epoll or kqueue, so it can call `sendfile` as the epoll
  loop does.

## Acceptance criteria

- [x] `http::send_file` hands a `Content-Length` body to the ring, as it does to the
      epoll loop (`Stream.direct`), on io_uring, IOCP, and the emulated ring
- [x] `scripts/test.sh`'s `files` passes on each, with no file left open
- [x] The README's static files row says so, one row for every loop (2026-10-12)
- [x] The 64 KB and 1 MB file rates on the desktop before and after, with how they were
      measured, `TransmitFile` with many downloads at once among them (2026-10-12)

## On the desktop (2026-10-12)

`bench/files.sh`, Ryzen 7 5800X3D, WSL2 Ubuntu 26.04.1, kernel
6.18.40.1-microsoft-standard-WSL2, Goose `5c83a5a`, files on tmpfs: each server on CPU
0 (1 worker) or CPUs 0-3 (4), wrk 4.1.0 on CPUs 4-15 with 12 threads and 96 connections,
3 runs of 10 s after 3 s of warm-up, medians. Before is `4a65d96`. Results in
`bench/results/2026-10-12-files`.

A first round showed zero-copy losing small files: at 4 KB, `sendfile` and the splices
served 25-45% fewer requests than the copying path of `4a65d96`. A sweep of both ways
on each loop (`bench/results/2026-10-12-files-cutoff`, 1 worker, 2 runs of 5 s) put the
crossover between 32 and 64 KB on epoll and io_uring, and between 16 and 32 KB on the
emulation, so `send_file` now copies a body under `DIRECT_MIN`, 64 KB (`fcfd80d`):

| Size | epoll copy / zero-copy | io_uring | emulation |
|---:|---|---|---|
| 4 KB | 0.23 / 0.18 GB/s | 0.34 / 0.19 | 0.31 / 0.22 |
| 16 KB | 0.81 / 0.71 | 1.12 / 0.72 | 0.90 / 0.86 |
| 32 KB | 1.40 / 1.37 | 1.89 / 1.34 | 1.40 / 1.65 |
| 64 KB | 2.01 / 2.28 | 2.03 / 2.13 | 1.43 / 3.02 |
| 128 KB | 2.54 / 3.63 | 1.80 / 3.32 | 1.56 / 4.72 |

With the cutoff, against nginx 1.28.3 (apt, `sendfile`, `tcp_nopush`,
`open_file_cache`, no access log) and Caddy 2.10.2 (release binary, `file_server`), 4 KB
in requests per second, the rest in GB/s:

| Server | 4 KB, 1 w | 4 KB, 4 w | 64 KB, 1 w | 64 KB, 4 w | 1 MB, 1 w | 1 MB, 4 w |
|---|---:|---:|---:|---:|---:|---:|
| Goose epoll | 56.0 K | 179 K | 2.23 | 7.41 | 11.59 | 31.28 |
| Goose io_uring | 81.6 K | 219 K | 2.08 | 6.42 | 10.98 | 30.39 |
| Goose io_uring over epoll | 76.8 K | 206 K | 2.90 | 7.85 | 12.38 | 31.11 |
| Goose `4a65d96` epoll | 56.9 K | 183 K | 2.00 | 6.79 | 3.43 | 11.72 |
| Goose `4a65d96` io_uring | 83.4 K | 223 K | 1.27 | 4.28 | 1.02 | 3.77 |
| nginx | 50.2 K | 173 K | 2.31 | 8.15 | 9.93 | 28.52 |
| Caddy | 13.0 K | 47 K | 0.83 | 2.99 | 6.80 | 20.08 |

- Small files are back at the copying path's rate, within 1-2%; 1 MB is 3.4 times
  `4a65d96` on epoll and 8-11 times on io_uring.
- nginx wins 64 KB against both real loops, by 4-27%: io_uring's two splices through a
  pipe cost more than `sendfile` there, and the emulation, which calls `sendfile`, is
  ahead of io_uring at every size from 32 KB.
- 1 MB with 4 workers measures wrk: it used all of its 120 CPU-seconds in Goose's
  cells. Server CPU per request there: Goose epoll 106 µs, nginx 148, Caddy 197.
- One socket error in the emulation's 64 KB cells, of about 1.3 M requests.

**IOCP**, `bench/oha.sh` in Git Bash, Windows 11 Pro 10.0.26200 on the same machine,
oha 1.16.0's Windows release, 256 connections, 3 runs, nothing pinned; HEAD sends 64 KB
and up with `TransmitFile`, `00a0ab1` copies everything. Requests per second, medians:

| File | Workers | HEAD | `00a0ab1` |
|---|---:|---:|---:|
| 4 KB (both copy) | 1 / 4 | 6.8 K / 16.3 K | 8.5 K / 17.2 K |
| 64 KB | 1 / 4 | 5.5 K / 15.7 K | 6.9 K / 16.4 K |
| 1 MB | 1 / 4 | 3.4-4.0 K / 4.1-4.2 K | 1.0-1.3 K / 4.1-4.8 K |

- Every file request costs 100-200 µs of kernel time on Windows, whatever its size, a
  dozen times plaintext's: opening the file, through the file system filters and
  Defender's real-time scan, dominates. The 4 KB rows take the same path in both builds
  and still differ by up to 20%, so the spread is wide.
- `TransmitFile` gains 3-4 times at 1 MB with 1 worker, at a quarter of the kernel CPU,
  and nothing with 4: client Windows runs two at a time system-wide, as noted below.
  At 64 KB it loses 5-20%.
- Left: a per-worker cache of open handles, as nginx's `open_file_cache`, if files on
  Windows matter; whether `TransmitFile` should start higher than 64 KB on IOCP.

## Notes (2026-10-12)

`ring_send_file` (`ring.goose`) queues a file behind a connection's sends, and the ring
owns the file from then on. The io_uring loop hands it over in `pump` as soon as
`answer` stops for it, and goes on answering, since the ring keeps the order.

- io_uring (`shim/uring.c`): `IORING_OP_SPLICE` from the file into a pipe, then from
  the pipe into the socket, one step at a time, not linked: a short first splice
  would leave a linked second one waiting for bytes that don't come. Pipes are asked
  for 1 MB (`F_SETPIPE_SZ`) and up to 64 empty ones are kept per ring. A send
  completes once per piece, so the loop's deadline moves as a long file goes out.
- Emulation (`shim/ring_epoll.c`): `net_sendfile`, as the epoll loop does.
- IOCP (`shim/iocp.c`): `TransmitFile`, 1 MB per call. Client Windows runs two
  TransmitFiles at a time system-wide and queues the rest, so many concurrent
  downloads on a desktop may be slower than the copying path; measure it.

Tested 2026-10-12: `scripts/test.sh` passed in WSL2 (Ubuntu 26.04, uring, uring over
epoll, epoll) and on Windows (IOCP), with `examples/c` moved out of the tree for the
run: it breaks every JIT test ([findings](../docs/goose-findings.md#a-packages-jit-library-links-the-externs-of-every-file-under-its-root)).
On macOS (the emulation over kqueue, with `sendfile`), `scripts/test.sh` passed twice
on the MacBook Pro in `docs/development.md`, macOS 26.3.1, Goose `5c83a5a`, at
`67ed334` with `examples/c` moved out, `files` reporting none left open on both loops
(2026-10-12). `examples/c` is now off `main`, on the `examples-c` branch, until Goose
leaves it out of the package.

Left: the benchmark.
