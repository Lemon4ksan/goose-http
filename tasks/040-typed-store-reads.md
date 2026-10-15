# 040: Typed reads from the shared store

Status: todo (asked for 2026-10-15)

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

- [ ] Scalar reads by value: `store_i64`, `store_u32`, `store_u8`, and the floats if
      they're wanted, each one C call returning the value, out of range answered as a
      store read out of range is now
- [ ] A record read by value for a flat fixed-size `T`, the Goose way or per type,
      whichever measures cheaper, with how it was measured
- [ ] Tests for each, in the store's tests, and `docs/api.md` documents them beside
      `store_append`
- [ ] The cost per read, against `store_append` into a buffer, measured with how
