// The REST server's shared store: byte blobs written once at startup and
// then read by every worker, one copy for the process. Goose shares only
// static data between threads (spec §11.2), and copies every other global a
// worker uses when it's spawned, so the prebuilt JSON would otherwise cost a
// copy per worker. The benchmark's, not the package's: rest.build compiles
// store.c into this server only.
//
// The contract: one thread puts the blobs and calls freeze before any other
// thread reads them, and hands their ids on through something that orders
// memory: a queue, thread_spawn, or thread_wait. A put after the freeze
// fails. A read copies a range into a Goose array, since C can't hand Goose a
// view of its own memory (spec §7.10). Blobs live for the process.
//
//   let b, err = store::put(prebuilt);      // before any reader starts
//   store::freeze();
//   store::append(b, from, to, out);        // in any thread after
namespace store;

import std;

// A blob in the store. Flat, so it crosses thread_spawn and queues.
struct Blob { id: i64 = -1 }

// store.c's calls. append_c appends to out, as a builder takes it (goose.h),
// and keeps nothing of it; put_c copies data and keeps nothing of it either.
extern "store_put" fn put_c(data: const u8[:]) -> i64;
extern "store_freeze" fn freeze();
extern "store_len" fn len_c(id: i64) -> i64;
extern "store_append" fn append_c(id: i64, from: i64, to: i64, out: u8[>..]&) -> i32;

// Copies data into a new blob. Returns it, and 0 or -code: EPERM after
// freeze, ENOMEM.
fn put(data: const u8[:]) -> Blob, i64 {
    let id = put_c(data);
    guard id >= 0 else { return Blob { .. }, id; }
    return Blob { id: id }, 0;
}

// The length of b, or -1 for a blob the store doesn't have.
fn len(b: Blob) -> i64 {
    let n = len_c(b.id);
    return if n < 0 { -1 } else { n };
}

// Appends b's bytes from..to to out. Returns false, with nothing appended,
// for a blob the store doesn't have or a range outside it.
inline fn append(b: Blob, from: i64, to: i64, out: u8[>..]&) -> bool {
    return append_c(b.id, from, to, out) == 0;
}
