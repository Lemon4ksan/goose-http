/* The shared store, for store.goose, on every platform: byte blobs written
   once at startup and then read by every thread. goose build compiles this
   beside the program, so it sees none of the generated C but goose.h.

   Goose shares only static data between threads (spec §11.2): every other
   global a worker uses is copied when it's spawned. Data a program builds at
   startup and never writes again, such as prebuilt responses, then costs a
   copy per worker. A blob here is one copy for the process.

   The contract, which store.goose states: one thread puts the blobs and
   freezes the store before any other thread reads it, and hands the blobs'
   ids to the readers through something that orders memory, such as a
   queue, thread_spawn, or thread_wait. After the freeze nothing writes, so
   readers need no lock; a put after it fails. Blobs live for the process.

   Every function returns 0 or more on success and -code on failure, where
   code is a Linux errno value, as the other shims' do. None keeps a pointer
   into Goose memory after it returns. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "goose.h"

#define STORE_EINVAL 22
#define STORE_ENOMEM 12
#define STORE_EPERM 1

typedef struct { const uint8_t *data; int64_t len; } store_bytes;

static uint8_t **store_blobs;
static int64_t *store_lens;
static int64_t store_count, store_cap;
static int store_frozen;

/* Copies data into a new blob and returns its id, or -EPERM once frozen. */
int64_t store_put(store_bytes data) {
    if (store_frozen) return -STORE_EPERM;
    if (data.len < 0) return -STORE_EINVAL;
    if (store_count == store_cap) {
        int64_t cap = store_cap ? store_cap * 2 : 16;
        uint8_t **blobs = realloc(store_blobs, (size_t)cap * sizeof *blobs);
        if (!blobs) return -STORE_ENOMEM;
        store_blobs = blobs;
        int64_t *lens = realloc(store_lens, (size_t)cap * sizeof *lens);
        if (!lens) return -STORE_ENOMEM;
        store_lens = lens;
        store_cap = cap;
    }
    uint8_t *p = malloc(data.len ? (size_t)data.len : 1);
    if (!p) return -STORE_ENOMEM;
    if (data.len) memcpy(p, data.data, (size_t)data.len);
    store_blobs[store_count] = p;
    store_lens[store_count] = data.len;
    return store_count++;
}

/* Ends the writes: a put after it returns -EPERM. */
void store_freeze(void) { store_frozen = 1; }

/* The length of blob id, or -EINVAL for none. */
int64_t store_len(int64_t id) {
    return id >= 0 && id < store_count ? store_lens[id] : -STORE_EINVAL;
}

/* Appends blob id's bytes [from, to) to out. Returns 0, or -EINVAL for no
   such blob or a range outside it, with nothing appended. */
int32_t store_append(int64_t id, int64_t from, int64_t to, gs_rref out) {
    if (id < 0 || id >= store_count || from < 0 || to < from || to > store_lens[id]) return -STORE_EINVAL;
    gs_bld_append(out, store_blobs[id] + from, to - from);
    return 0;
}

/* Blob id's n bytes at at, or NULL for no such blob or a range outside it. */
static const uint8_t *store_at(int64_t id, int64_t at, int64_t n) {
    if (id < 0 || id >= store_count || at < 0 || n < 0 || at > store_lens[id] - n) return NULL;
    return store_blobs[id] + at;
}

/* Record i of blob id, of records of size bytes end to end, or NULL for no
   such blob or an i outside it. For a program's own C, which declares it:
   the per-type reads that http::store_record takes (docs/api.md). */
const uint8_t *store_record_at(int64_t id, int64_t i, int64_t size) {
    if (size <= 0 || i < 0 || i > INT64_MAX / size - 1) return NULL;
    return store_at(id, i * size, size);
}

/* The scalar reads: the value at byte at, in the host's order, which is
   little-endian wherever Goose runs, as to_bytes writes. u8 and u32 come
   back widened, and -1 for no such blob or a range outside it; i64 and f64
   come back with a flag, in the packed layouts of store.goose's StoreI64 and
   StoreF64. */
#pragma pack(push, 1)
typedef struct { int64_t v; uint8_t ok; } store_i64_read;
typedef struct { double v; uint8_t ok; } store_f64_read;
#pragma pack(pop)
_Static_assert(sizeof(store_i64_read) == 9 && sizeof(store_f64_read) == 9, "packed as Goose");

int64_t store_u8(int64_t id, int64_t at) {
    const uint8_t *p = store_at(id, at, 1);
    return p ? *p : -1;
}

int64_t store_u32(int64_t id, int64_t at) {
    const uint8_t *p = store_at(id, at, 4);
    uint32_t v;
    if (!p) return -1;
    memcpy(&v, p, 4);
    return v;
}

store_i64_read store_i64(int64_t id, int64_t at) {
    store_i64_read r = { 0, 0 };
    const uint8_t *p = store_at(id, at, 8);
    if (p) { memcpy(&r.v, p, 8); r.ok = 1; }
    return r;
}

store_f64_read store_f64(int64_t id, int64_t at) {
    store_f64_read r = { 0, 0 };
    const uint8_t *p = store_at(id, at, 8);
    if (p) { memcpy(&r.v, p, 8); r.ok = 1; }
    return r;
}
