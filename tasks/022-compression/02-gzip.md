# 022.02: gzip in `goose-compress`

Status: todo

A DEFLATE encoder in Goose with the gzip and zlib wrappers, in a package of its own
([task 022](README.md)). Each step below gives output `gzip -d` accepts, so subtask 03
can start after step 1.

## Steps

1. Stored blocks: the gzip header, the input in uncompressed DEFLATE blocks, then CRC-32
   and the length. About 100 lines, and enough to build `http`'s side against.
2. LZ77 matching with one hash probe per position, coded with DEFLATE's fixed Huffman
   tables.
3. Dynamic Huffman tables per block, built from the block's symbol counts and limited
   to 15 bits.
4. Speed: slice-by-8 CRC-32, a lazy-matching level beside the greedy one, and the
   memory a stream holds (the 32 KB window and the hash table).

## Acceptance criteria

- [ ] The package builds as its own repository and imports nothing of `http`
- [ ] One-shot `compress` and a streaming encoder with `flush` (an empty stored block,
      as zlib's `Z_SYNC_FLUSH`) and `finish`
- [ ] gzip and zlib wrappers over the same DEFLATE stream
- [ ] Round trips through `gzip -d` and Python's `zlib` on empty input, one byte, text,
      JSON, random bytes, and inputs across block boundaries
- [ ] A fuzz test of random inputs and flush points against Python's `zlib`
- [ ] Rate and ratio per level against libdeflate and zlib-ng at their nearest levels,
      on the same inputs and machine, with how they were measured
- [ ] Findings from the work recorded in `docs/goose-findings.md`
