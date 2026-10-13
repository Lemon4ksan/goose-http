# 022.03: Compressing responses in `http`

Status: done (2026-10-14), tested on Linux and Windows; macOS not run yet

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

## Measured (2026-10-14)

On the desktop: Ryzen 7 5800X3D, WSL2 kernel 6.18.54.1, gcc 15.2.0, Goose `0bdbd18`,
the benchmark server at `6f584e2` built with `scripts/build.sh` (`goose-22c`, and
`goose-22c-uring`), 4 workers on CPUs 0-3, `DATASET` HttpArena's `data/dataset.json`
(`0720ee5`). wrk 4.1.0 with `bench/json-comp.lua`, which sends json-comp's seven
requests in turn, on CPUs 4-15 with 8 threads and 512 connections, 5 s of warm-up and
then 15 s, 3 runs; `identity` sends no `Accept-Encoding`:

```sh
WORKERS=4 LOOP=uring taskset -c 0-3 build/bench/goose-22c-uring http 29391
taskset -c 4-15 wrk -t 8 -c 512 -d 15 -s bench/json-comp.lua http://127.0.0.1:29391 -- gzip
```

| Loop | Coding | Requests/s, median (range) | Bytes read per response | Peak RSS |
|---|---|---:|---:|---:|
| uring | gzip, level 1 | 113.5K (100.5-113.9K) | 1,105 | 21.8-21.9 MB |
| uring | identity | 319.0K (316.5-342.0K) | 3,666 | 12.3-12.4 MB |
| epoll | gzip, level 1 | 90.9K (90.5-94.4K) | 1,107 | 15.1 MB |
| epoll | identity | 285.1K (278.4-287.0K) | 3,666 | 4.2 MB |

Bytes read per response are wrk's total, in its binary units, over its requests, heads
included. `/json/1` and `/json/5`, about 200 and 870 bytes, are under the 1 KB
threshold and go uncompressed. Every run
kept the 4 server CPUs busy, so compressing costs about 24 µs of CPU per response:
35 µs against 12.5 on uring. The peak RSS grows by the encoders, each worker's one-shot
gzip encoder of 460,406 bytes and its stack.

`bench/count.sh`, `RUNS=3`, the branch against `main` at `48f8e37` (plaintext, which
no compression touches): 1,831.9 user instructions per request against 1,846.9 on
epoll, and 1,880.0 against 1,895.0 on uring, in every run. The branch adds a route
and a field to the benchmark server's per-request state; why that leaves 15 fewer
instructions isn't known.

### HttpArena's json-comp

`bench/httparena.sh validate` passed every check of the entry's profiles, json-comp's
three among them (`Content-Encoding` with `Accept-Encoding`, the bodies at random
counts and multipliers, none without it). Then `bench/httparena.sh run` with
`PROFILES=json-comp FRAMEWORKS="goose dusty vanilla-epoll actix"`: HttpArena `0720ee5`,
gcannon `11c802b`, each server in its HttpArena entry's Docker image on CPUs 0-3,
gcannon on 4-15 with 4 threads, 3 runs of 5 s at each connection count, Docker 29.8.2,
the same machine
([logs](../../bench/results/2026-10-14-httparena-json-comp/)). The harness keeps each
cell's best run; requests per second, bytes per response (bandwidth over rate), and
memory as the harness reads the container's:

| Server | 4,096 connections | Bytes per response | Memory | 16,384 connections | Memory |
|---|---:|---:|---:|---:|---:|
| goose, gzip level 1 | 66.1K (54.8-66.1K) | 1,477 | 51-52 MiB | 64.2K (61.2-64.2K) | 147 MiB |
| actix | 62.6K (61.2-62.6K) | 1,733 | 129-141 MiB | 61.0K (55.0-61.0K) | 368-441 MiB |
| dusty | 43.0K (42.6-43.0K) | 1,303 | 28-200 MiB | 42.0K (40.3-42.0K) | 235 MiB-1.1 GiB |
| vanilla-epoll | 404.8K (367.7-404.8K) | 1,635 | 111-115 MiB | 204.4K (80.3-204.4K) | 250-293 MiB |

Goose is the fastest of those that compress each response: 6% over actix and 54% over
dusty at 4,096 connections. vanilla-epoll compresses each count and multiplier once and
keeps the gzipped bytes (`map[u64][]u8` in its `main.v`), so its cell measures a
cache, not compression. HttpArena scores json-comp by rate times the square of the
smallest bytes per response over a server's own: dusty's gzip writes 12% fewer bytes
than goose's level 1, which scores goose at 0.78 of its rate, 51.5K, still above actix's
35.4K and dusty's 43.0K.

A higher level trades rate for that square, and loses. The benchmark server at
`a481b99`, uring, with `COMPRESS_LEVEL` at 1, 3, 6, and 9, the same wrk run as under
"Measured" above, 3 runs each in turn; the bodies of json-comp's seven requests summed
from one `curl` of each:

| gzip level | Requests/s, median (range) | Body bytes, 7 requests | Bytes read per response | Score against level 1 |
|---:|---:|---:|---:|---:|
| 1 | 112.7K (108.1-113.6K) | 6,574 | 1,105 | 1.00 |
| 3 | 101.1K (88.7-101.7K) | 6,410 | 1,083 | 0.94 |
| 6 | 83.0K (81.0-83.1K) | 6,076 | 1,036 | 0.84 |
| 9 | 66.8K (64.1-67.5K) | 6,026 | 1,022 | 0.69 |

The score is HttpArena's: the rate times the square of level 1's bytes per response
over the level's own. Level 1 stays the default.

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
- [x] Tests in `scripts/test.sh` on every loop: negotiation, the cases left alone,
      chunked streaming with flushes, and SSE events arriving whole. Passing in WSL
      (uring, epoll, uring-epoll) and Git Bash (iocp), 2026-10-14:
      `test/test_compression.goose`, and `scripts/http_client.py compress` (`/json/{count}`
      in each coding, what's left alone, pipelined, and `/zstream`'s pieces each
      decompressing as they come) and `later` (compressed `/events`, each event's chunk
      decompressing to the event alone)
- [x] json-comp's route in `server/` (`server/dataset.goose`: `GET /json/{count}?m=`,
      from the file `DATASET` names, `/data/dataset.json` by default, where HttpArena
      mounts it) and the profile in the HttpArena entry
- [x] Throughput and peak RSS with and without compression on json-comp's endpoint,
      against the competitors in their fastest documented compression setup, with how
      they were measured ("Measured", above). Not run on macOS yet.
