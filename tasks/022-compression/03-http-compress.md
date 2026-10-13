# 022.03: Compressing responses in `http`

Status: in progress, on the `task-022-03` branch until its benchmarks are recorded

The module `http.compression` compresses a response on the fly with goose-compress
when the request takes gzip, deflate, or zstd ([task 022](README.md)). It uses subtask
01's `Accept-Encoding` parsing.

## How it's built (2026-10-14)

- The module is `compression.goose`, imported as `http.compression`, not
  `http.compress`: a package's file may not have the name of a package the program
  declares (spec §11.1), and goose-compress's is `compress`. A program that imports the
  module declares goose-compress in its root file, at the commit the module names
  (`4bed2d2`); one that doesn't builds as before.
- Its settings are a struct of its own, `http::Compression` (`min_size` 1,024 bytes,
  `level` 1 for gzip and deflate, `zstd_level` 1, `zstd` offered), passed to its
  functions, not fields of `Config`: `Config` reaches the loops, and `Reply`, built per
  request, would need the threshold too. Level 1 is nginx's default `gzip_comp_level`.
- `http::coding_for(req, c)` picks the coding `Accept-Encoding` weighs highest, zstd
  before gzip before deflate at equal weights, as task 022 orders them.
- `http::respond_compressed(out, req, status, content_type, body, c)` writes a whole
  response, with the body compressed whole into a local resizable on the worker's
  data stack. A global scratch buffer can't be used: Goose won't let a handler clear a
  global resizable while it holds `out`, whose `buf` it can't tell apart from it
  (spec §5.1).
- `http::begin_compressed`, `send_compressed`, `end_compressed`, and
  `release_compressed` stream a response chunked, each piece flushed (zlib's
  `Z_SYNC_FLUSH`, or zstd's block end), with an `http::Compressed` in the handler's
  state that holds the encoder's slot. The worker's encoders are a pool in global
  resizables, built once with `compress::encoder` or `compress::zstd_encoder` and
  reset for each stream; a flag per slot marks it held, since a handler can't pop a
  global free list for the same reason. A handler calls `release_compressed` at
  `CLOSED`.
- HTTP/1.0 streams go uncompressed: they can't take chunks, and the body would end
  with the connection.

## Acceptance criteria

- [x] A response built in one piece is compressed once and keeps its `Content-Length`;
      a streamed one goes chunked, with a flush at each chunk the handler sends
- [x] Left alone: `HEAD`, 204, 304, 206, bodies under a threshold (default 1 KB, in
      `http::Compression` rather than `Config`, above), and media types already
      compressed (images but SVG, audio, video, WOFF fonts, archives, and
      `application/octet-stream`)
- [x] `Vary: Accept-Encoding` on every response the route could compress, compressed
      or not: every response of a compressible media type
- [x] A one-shot response uses one scratch buffer per worker, on its data stack; only
      a streamed one holds encoder state on its connection
- [x] Encoders are built once and reset per response. `compress::compress` already
      resets one encoder that each worker's program instance keeps. A streamed
      response's encoder, 460,406 bytes for gzip and deflate and 1,010,955 for zstd
      (goose-compress `4bed2d2`), comes from a pool sized for the concurrent streams,
      not one per connection slot, and starts each response with `compress::reset`:
      building one with `compress::encoder` copies its arrays several times, about
      145 µs on a Ryzen 7 5800X3D under Windows, where a reset takes a few µs
      (goose-compress `68307f4`, its README)
- [ ] Tests in `scripts/test.sh` on every loop: negotiation, the cases left alone,
      chunked streaming with flushes, and SSE events arriving whole.
      `test/test_compression.goose`, and `scripts/http_client.py compress` (`/json/{count}`
      in each coding, what's left alone, pipelined, and `/zstream`'s pieces each
      decompressing as they come) and `later` (compressed `/events`, each event's chunk
      decompressing to the event alone)
- [x] json-comp's route in `server/` (`server/dataset.goose`: `GET /json/{count}?m=`,
      from the file `DATASET` names, `/data/dataset.json` by default, where HttpArena
      mounts it) and the profile in the HttpArena entry
- [ ] Throughput and peak RSS with and without compression on json-comp's endpoint,
      against the competitors in their fastest documented compression setup, with how
      they were measured
