# 020: Files without copying on io_uring and IOCP

Status: in progress (asked for 2026-10-12)

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
- [ ] The 64 KB and 1 MB file rates on the desktop before and after, with how they were
      measured, and the README's row turned green

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
