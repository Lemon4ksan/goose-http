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
