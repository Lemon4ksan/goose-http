# 022.01: Precompressed files

Status: in progress

`http::open_precompressed` opens `x.br`, `x.zst`, or `x.gz` in place of `x` when it
exists and the request's `Accept-Encoding` takes that coding, as Caddy's
`precompressed` and nginx's `gzip_static` do, and `http::serve_file` sends it. No codec
is involved ([task 022](README.md)).

A copy older than `x` is passed over: it may hold what `x` held before an edit, and
neither Caddy nor nginx checks. `Last-Modified`, `If-Modified-Since`, and the ETag
come from the copy, whose ETag ends in its coding (`"…-gzip"`), so it differs from the
original's even at the same size. A request that refuses `identity` and takes no copy
on disk still gets `x` uncompressed, as nginx and Caddy answer, rather than 415.

## Acceptance criteria

- [x] `Accept-Encoding` parsed with q-values, `*`, `x-gzip` as gzip, and every field of
      the name: `http::coding_q` in `media.goose`, which shares `element_end` with
      `Accept`'s weighing
- [x] Among the copies on disk the request takes, the highest q wins; ties go to br,
      then zstd, then gzip
- [x] `Content-Encoding`, and `Vary: Accept-Encoding` on every response
      `open_precompressed` opened, 304 included; `Content-Type` from the original's
      name
- [x] A range request gets the copy's bytes, as RFC 9110 §14 defines ranges on the
      representation sent
- [x] Unit tests (`test_codings` in `test/test_http.goose`), and `scripts/http_client.py
      files` checking a real gzip copy, a range of it, its 304, a `.br` copy, and a copy
      older than its file
- [ ] `scripts/test.sh` passing on every loop: passed on macOS on both loops
      (2026-10-12); Linux and Windows not run yet
