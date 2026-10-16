# 040: Typed reads from the shared store

Status: in-progress (asked for 2026-10-15; done on macOS 2026-10-16, the Linux and
Windows test runs are still to do)

`http::store`'s one read is `store_append(b, from, to, out)`, which copies a range of a
blob into a growable buffer. A program that keeps numbers in the store, such as a column
of prices or an index of offsets, then needs a buffer and decodes each value by hand,
and one that keeps fixed-size records rebuilds each from its bytes. Spec §7.10 lets C
return a scalar or a flat fixed-size value by value, so the store can read them with no
buffer at all:

```rust
let price = http::store_i64(prices, i * 8);          // a column of i64s
let end = http::store_u32(index, i * 4);             // an index of u32 offsets
http::store_append(names, at, at + len, out);        // text, as now, into the answer
let item = http::store_record<app::Item>(items, i);  // a fixed-size struct, by value
```

That makes the layouts goose-rest's task 027 considered (columns, an index, record
images) cheap to read, with no helper over the store.

An `extern fn` can't be generic (§7.10), so `store_record<T>` is Goose: it copies the
record's image and rebuilds the struct with `from_bytes`, which verifies it, or the
program declares a C function per record type. Which is cheaper is measured here.

## Acceptance criteria

- [x] Scalar reads by value: `store_i64`, `store_u32`, `store_u8`, and the floats if
      they're wanted, each one C call returning the value, out of range answered as a
      store read out of range is now
- [x] A record read by value for a flat fixed-size `T`, the Goose way or per type,
      whichever measures cheaper, with how it was measured
- [x] Tests for each, in the store's tests, and `docs/api.md` documents them beside
      `store_append`
- [x] The cost per read, against `store_append` into a buffer, measured with how
- [ ] `test/run_tests.py store` on Linux and on Windows (MSVC), where the test's own C
      and the struct returns haven't run yet

## What changed

- `http::store_i64`, `store_u32`, `store_u8`, and `store_f64` (`store.goose`) each
  make one C call (`shim/store.c`) and return the value at a byte offset and true,
  or 0 and false for a value that doesn't fit inside the blob or a blob the store
  doesn't have, as `store_append` returns false. `store_u8` and `store_u32` come
  back from C widened to an `i64`, -1 for out of range; `store_i64` and `store_f64`
  as a 9-byte packed struct of the value and a flag, returned in registers. `f32` is
  left out until a program wants it.
- `http::store_record<T>(b, i, read)` returns record `i` by value. `read` is the
  program's C function for `T`, which copies the record with the shim's
  `store_record_at(id, i, size)`. An `extern fn` can't be generic, and two `extern
  fn`s can't bind one C symbol with different types: each emits a prototype, and the
  C compiler rejects the second as conflicting. So the shim can't offer one C read for
  every `T&`, and the program writes about ten lines of C per record type
  (`docs/api.md`, "The store").
- The Goose way, `store_append` of the record's image after a ULEB size and then
  `from_bytes<T[>..]>`, needs no C but costs four times as much, below. It stays in
  `bench/store/reads.goose` as `goose_record`, for the comparison. A third way, one
  C function for every type taking the size from Goose (`memcpy` of a variable
  length, called through a per-type alias), cost 5.1 ns, twice the per-type read,
  and was dropped.
- Tests: `test/store/shared_store.goose` reads each scalar, at the last offset that
  fits and past it, of a blob the store doesn't have, and records 0 to 2 of three by
  value, then 3, -1, `i64` max, and no blob, which are refused. Its C read is
  `test/store/shared_store.c`, named by `shared_store.build`.

## Measurements

`bench/store.sh` builds `bench/store/reads.goose` with `goose build -O2` and runs it.
Each way reads 10 M values in turn from a blob of 8192 `i64`s or of 1024 25-byte
records (`i64, i64, i32, f32, u8`), adds them up, and checks the sum; 7 rounds per way
in one process, and the program run 3 times. ns per read: the best and worst round of
the 21, and the median of the 3 runs' medians:

| Way | Best | Median | Worst |
|---|---|---|---|
| `store_append` of 8 bytes into a cleared buffer, decoded by hand | 3.80 | 3.82 | 4.50 |
| `store_i64` | 1.86 | 1.92 | 1.95 |
| `store_append` of a record into a cleared buffer, one field decoded | 5.04 | 5.16 | 6.02 |
| The Goose way: `store_append` of the image, then `from_bytes` | 10.08 | 10.31 | 11.22 |
| `store_record` with a per-type C read | 2.54 | 2.59 | 2.67 |

A scalar read costs half of a `store_append` of the same bytes, and a record read half
of a `store_append` of the record, with the record whole. The machine: Apple M1 Pro,
macOS 26.3.1 (Darwin 25.3.0), Apple clang 21.0.0, Goose v2026.2, no pinning, on
2026-10-16. A run on the Linux desktop isn't needed for the choice, which a factor of
four settles, and can join the next overnight batch.
