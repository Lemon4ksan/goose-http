# 022: Compression

Status: in-progress (implemented; approval record and validation remain open)

Responses use precompressed files or the optional `http.compression` module for
dynamic gzip, deflate, and zstd. HttpArena's json-comp entry is validated and measured
(task 022.03, 2026-10-14). The [architecture](../../docs/architecture.md#files-and-compression)
describes the implemented boundary. Its approval has not been recorded as a settled
decision; implementation alone does not complete that criterion.

## Encoding choices

| Encoding | On the fly | Precompressed file | Reason |
|---|---|---|---|
| gzip | yes | `.gz` | Broad client support; fallback when a client does not take zstd. |
| deflate | yes | none | DEFLATE in a zlib wrapper; offered, not preferred over gzip at equal weights. |
| zstd | yes | `.zst` | Faster and smaller at low levels; offered alongside gzip. RFC 9659 caps its HTTP window at 8 MB. |
| br | no | `.br` | High-quality compression suits prebuilt files; a dynamic encoder remains out of scope. |

Brotli's high-quality output is too costly per request, while its fast qualities add a
large encoder for little benefit over gzip. Clients without zstd get gzip for dynamic
responses and may get brotli for files. Revisit dynamic brotli if a deployment serves
large dynamic text to many clients that cannot use zstd (2026-10-12).

## Implemented boundary

The codecs live in `goose-compress`, which imports nothing of HTTP. The encoders are
Goose: compression is the byte work this project measures. Negotiation, `Vary`, and
choosing what to compress remain in `http`. Only programs importing
`http.compression` declare the codec dependency. Precompressed files need no codec.

Streaming encoders flush on byte boundaries so each response chunk or SSE event can
be decoded on arrival. Decoding compressed request bodies remains out of scope:
accepting them would require decompression limits.

## Subtasks

1. [Precompressed files](01-precompressed-files.md): implemented; Linux and Windows
   validation is still unrecorded in this subtask.
2. [gzip in goose-compress](02-gzip.md): done in the codec package.
3. [Dynamic compression](03-http-compress.md): implemented and measured; macOS has not
   been run for this change. zstd joins gzip and deflate.

## Open question

Whether to retain a C-backed encoder for comparison, or only benchmark libdeflate and
zlib-ng against the Goose implementation.

## Acceptance criteria

- [ ] Approval of the package split recorded; the implemented boundary is described in
      architecture, but its earlier proposal has no recorded approval
- [ ] Subtasks 01 to 03 complete their required validation
- [x] json-comp in the HttpArena entry, passing `bench/httparena.sh validate`
      (task 022.03, 2026-10-14)
- [x] The README's Compression row updated
