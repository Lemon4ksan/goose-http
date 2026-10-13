# 022.02: gzip in `goose-compress`

Status: done (2026-10-12), as [goose-compress](https://github.com/kaitk/goose-compress)'s
task 001

A DEFLATE encoder in Goose with the gzip and zlib wrappers, in a package of its own
([task 022](README.md)). Its steps, acceptance criteria, and measurements are tracked in
goose-compress's `tasks/001-gzip.md`: levels 0 to 9, dynamic Huffman blocks, a one-shot
`compress`, and a streaming encoder with `flush` and `finish`. Speed work goes on there
in its task 003, with the same API.

## Acceptance criteria

- [x] goose-compress's task 001 done
