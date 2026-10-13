# 022.03: Compressing responses in `http`

Status: todo

The module `http.compress` compresses a response on the fly with subtask 02's encoder
when the request takes gzip, deflate, or zstd ([task 022](README.md)). It uses subtask
01's `Accept-Encoding` parsing.

## Acceptance criteria

- [ ] A response built in one piece is compressed once and keeps its `Content-Length`;
      a streamed one goes chunked, with a flush at each chunk the handler sends
- [ ] Left alone: `HEAD`, 204, 304, 206, bodies under a threshold in `Config`
      (default 1 KB), and media types already compressed (images, audio, video,
      archives)
- [ ] `Vary: Accept-Encoding` on every response the route could compress, compressed
      or not
- [ ] A one-shot response uses one scratch buffer per worker; only a streamed one holds
      encoder state on its connection
- [ ] Encoders are built once and reset per response. `compress::compress` already
      resets one encoder that each worker's program instance keeps. A streamed
      response's encoder, 460,406 bytes for gzip and deflate and 879,875 for zstd,
      comes from a pool sized for the concurrent streams, not one per connection slot,
      and starts each response with `compress::reset`: building one with
      `compress::encoder` copies its arrays several times, about 145 µs on a Ryzen 7
      5800X3D under Windows, where a reset takes a few µs (goose-compress `68307f4`,
      its README)
- [ ] Tests in `scripts/test.sh` on every loop: negotiation, the cases left alone,
      chunked streaming with flushes, and SSE events arriving whole
- [ ] json-comp's route in `server/` and the profile in the HttpArena entry
- [ ] Throughput and peak RSS with and without compression on json-comp's endpoint,
      against the competitors in their fastest documented compression setup, with how
      they were measured
