# 022: Compression

Status: in progress (asked for 2026-10-12; the split below is a proposal, not a
decision, but for the package's name)

Compress responses by `Accept-Encoding`. It is the one HTTP/1.1 feature HttpArena's
plaintext profiles still need (task 018): json-comp sends `Accept-Encoding: gzip, br`
and passes on `Content-Encoding` gzip or br, and fails on any `Content-Encoding` when
the request had no `Accept-Encoding`. The static profiles send
`br;q=1, gzip;q=0.8` and check only that each body decompresses to the file's size
(HttpArena `0720ee5`, `scripts/validate.sh`).

## Encodings

| Encoding | On the fly | Precompressed file | Plan |
|---|---|---|---|
| gzip | yes | `.gz` | First. Every client takes it, and it stays the fallback for any other. |
| deflate | yes | none | The same DEFLATE stream in the zlib wrapper: a 2-byte header and Adler-32 in place of gzip's header and CRC-32. Offered, never preferred over gzip. |
| zstd | later | `.zst` | Faster and smaller than gzip at low levels, but not every client takes it, so it adds to gzip instead of replacing it. RFC 9659 caps its window at 8 MB for HTTP. |
| br | no | `.br` | Brotli pays off at quality 11, too slow per request; its fast qualities are a large encoder for little over gzip. Precompressed `.br` needs no brotli code. |

## Proposed split

- The codecs go in a package of their own, `goose-compress` (named 2026-10-12, over
  `goose-deflate`, so that zstd joins it without a rename), that imports nothing of
  HTTP: CRC-32, Adler-32, a DEFLATE encoder, the gzip and zlib wrappers, and later
  zstd. Its API takes bytes in and gives bytes out, with a flush that ends a chunk on a
  byte boundary, so a streamed response or SSE event goes out whole.
- The package is Goose, not bindings to zlib-ng or libdeflate. Compression is hashing,
  bit-packing, and Huffman tables, the byte work that measuring Goose is about
  (`AGENTS.md`); TLS goes to a C library because writing its crypto is out of scope
  (task 014), and no such reason holds here.
- `http` uses it only from a module of its own, `http.compress`, so only a program that
  imports that module declares the package, as task 014 proposes for `http.tls`.
- Negotiation, `Vary`, and choosing what to compress stay in `http`. Precompressed
  files need no codec and come first.
- Decoding request bodies sent with `Content-Encoding: gzip` is out of scope for now:
  few clients send them, and accepting them needs limits against decompression bombs.

## Subtasks

1. [Precompressed files](01-precompressed-files.md)
2. [gzip in `goose-compress`](02-gzip.md), in steps that each give valid output
3. [Compressing responses in `http`](03-http-compress.md), then json-comp

zstd follows as a subtask of its own once gzip is measured.

## Open questions

- Whether a C-backed encoder is kept beside the Goose one for comparison, or
  libdeflate and zlib-ng are only measured against it.

## Acceptance criteria

- [ ] The split agreed, and recorded in `docs/architecture/README.md`
- [ ] Subtasks 01 to 03 done
- [ ] json-comp in the HttpArena entry, passing `bench/httparena.sh validate`
- [ ] The README's Compression row updated
