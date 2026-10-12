# 020: Files without copying on io_uring and IOCP

Status: todo (asked for 2026-10-12)

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

- [ ] `http::send_file` hands a `Content-Length` body to the ring, as it does to the
      epoll loop (`Stream.direct`), on io_uring, IOCP, and the emulated ring
- [ ] `scripts/test.sh`'s `files` passes on each, with no file left open
- [ ] The 64 KB and 1 MB file rates on the desktop before and after, with how they were
      measured, and the README's row turned green
