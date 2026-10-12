# 022.01: Precompressed files

Status: todo

`http::send_file` serves `x.br`, `x.zst`, or `x.gz` in place of `x` when it exists and
the request's `Accept-Encoding` takes that coding, as Caddy's `precompressed` and
nginx's `gzip_static` do. No codec is involved ([task 022](README.md)).

## Acceptance criteria

- [ ] `Accept-Encoding` parsed with q-values, `identity`, `identity;q=0`, and `*`,
      sharing the weighing `media.goose` does for `Accept`
- [ ] Among the variants on disk the request takes, the highest q wins; ties go to
      br, then zstd, then gzip
- [ ] `Content-Encoding` and `Vary: Accept-Encoding` set; `Content-Type`, `Last-Modified`,
      and the conditional checks from the original file; an ETag that differs from
      the original's
- [ ] A range request gets the variant's bytes, as RFC 9110 §14 defines ranges on the
      representation sent
- [ ] Tests in `scripts/test.sh` that decompress each variant and compare it to the
      original, on every loop
