// The store: byte blobs written once at startup and then read by
// every thread, one copy for the process. Goose shares only static data
// between threads (spec §11.2), and copies every other global a worker uses
// when it's spawned, so data built at startup and never written again, such
// as prebuilt responses, would otherwise cost a copy per worker.
//
// The contract: one thread puts the blobs and calls store_freeze before any
// other thread reads them, and hands their ids on through something that
// orders memory: a queue, thread_spawn, or thread_wait. A put after the
// freeze fails. A read copies a range into a Goose array, or a scalar or a
// flat fixed-size record out by value, since C can't hand Goose a view of
// its own memory (spec §7.10). Blobs live for the process.
//
// The blobs are C's (shim/store.c), since Goose has no memory threads share.
// Nothing here knows HTTP, so that it can move to a package of its own
// unchanged. A program that doesn't import this module doesn't build it.
//
//   import http.store;
//   let b, err = http::store_put(prebuilt);      // in main, before any spawn
//   http::store_freeze();
//   http::store_append(b, from, to, out.buf);     // in any thread after
//   let price, ok = http::store_i64(prices, i * 8);
namespace http;

import std;

// A blob in the store. Flat, so it crosses thread_spawn and queues.
struct Blob { id: i64 = -1 }

// What store_i64's and store_f64's C return: the value, and whether there
// was one.
struct StoreI64 { v: i64, ok: bool }
struct StoreF64 { v: f64, ok: bool }

// The shim's calls. store_append's C appends to out, as a builder takes it
// (goose.h), and keeps nothing of it; store_put's copies data and keeps
// nothing of it either.
extern "store_put" fn store_put_c(data: const u8[:]) -> i64;
extern "store_freeze" fn store_freeze();
extern "store_len" fn store_len_c(id: i64) -> i64;
extern "store_append" fn store_append_c(id: i64, from: i64, to: i64, out: u8[>..]&) -> i32;
extern "store_u8" fn store_u8_c(id: i64, at: i64) -> i64;
extern "store_u32" fn store_u32_c(id: i64, at: i64) -> i64;
extern "store_i64" fn store_i64_c(id: i64, at: i64) -> StoreI64;
extern "store_f64" fn store_f64_c(id: i64, at: i64) -> StoreF64;

// Copies data into a new blob. Returns it, and 0 or -code: EPERM after
// store_freeze, ENOMEM.
fn store_put(data: const u8[:]) -> Blob, i64 {
    let id = store_put_c(data);
    guard id >= 0 else { return Blob { .. }, id; }
    return Blob { id: id }, 0;
}

// The length of b, or -1 for a blob the store doesn't have.
fn store_len(b: Blob) -> i64 {
    let n = store_len_c(b.id);
    return if n < 0 { -1 } else { n };
}

// Appends b's bytes from..to to out. Returns false, with nothing appended,
// for a blob the store doesn't have or a range outside it.
inline fn store_append(b: Blob, from: i64, to: i64, out: u8[>..]&) -> bool {
    return store_append_c(b.id, from, to, out) == 0;
}

// The scalar at byte at of b, little-endian as to_bytes and bytes_of write
// it, and true; or 0 and false for a blob the store doesn't have or a value
// that doesn't fit inside it. One C call each.
inline fn store_u8(b: Blob, at: i64) -> u8, bool {
    let v = store_u8_c(b.id, at);
    guard v >= 0 else { return 0, false; }
    return v as u8, true;
}

inline fn store_u32(b: Blob, at: i64) -> u32, bool {
    let v = store_u32_c(b.id, at);
    guard v >= 0 else { return 0, false; }
    return v as u32, true;
}

inline fn store_i64(b: Blob, at: i64) -> i64, bool {
    let r = store_i64_c(b.id, at);
    return r.v, r.ok;
}

inline fn store_f64(b: Blob, at: i64) -> f64, bool {
    let r = store_f64_c(b.id, at);
    return r.v, r.ok;
}

// Record i of b, a blob of flat fixed-size Ts end to end, such as bytes_of
// an array of them gives, and true; or default<T>() and false for a blob the
// store doesn't have or an i outside it. READ is the program's own C for T,
// an extern fn (id: i64, i: i64, out: T&) -> i32 that copies the record into
// out and returns 0, or -1 with out as it was (docs/api.md, "The store"). An
// extern fn can't be generic, and from_bytes, which could rebuild any T in
// Goose, costs four times as much. Nothing verifies the bytes, so the blob
// must hold Ts as bytes_of wrote them, and T no references.
inline fn store_record<T, READ>(b: Blob, i: i64) -> T, bool {
    var r = default<T>();
    guard READ(b.id, i, r) == 0 else { return default<T>(), false; }
    return r, true;
}
