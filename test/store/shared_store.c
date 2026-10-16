/* shared_store.goose's per-type record read, for http::store_record. */
#include <stdint.h>
#include <string.h>

#pragma pack(push, 1)
typedef struct { int64_t id; double price; uint32_t stock; uint8_t name[4]; } item;
#pragma pack(pop)
_Static_assert(sizeof(item) == 24, "packed as Goose");

const uint8_t *store_record_at(int64_t id, int64_t i, int64_t size);

int32_t test_item_read(int64_t id, int64_t i, item *out) {
    const uint8_t *p = store_record_at(id, i, sizeof *out);
    if (!p) return -1;
    memcpy(out, p, sizeof *out);
    return 0;
}
