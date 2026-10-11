/* ring.goose's calls on macOS, which has no ring yet: ur_create fails with
   ENOSYS, so http::serve returns that error at start, and http::serve_epoll is
   the loop to call there. The other calls are never reached. */
#include <stdint.h>

#define UR_ENOSYS 38

typedef struct { uint8_t *data; int64_t len; } ur_bytes;
typedef struct { void *data; int64_t len; } ur_completions;

int64_t ur_create(int32_t entries, int32_t nbufs, int32_t buflen) {
    (void)entries, (void)nbufs, (void)buflen;
    return -UR_ENOSYS;
}

void ur_accept(int64_t h, int32_t fd, uint64_t tag) { (void)h, (void)fd, (void)tag; }

void ur_recv(int64_t h, int32_t fd, uint64_t tag) { (void)h, (void)fd, (void)tag; }

int32_t ur_send(int64_t h, int32_t fd, uint64_t tag, ur_bytes data) {
    (void)h, (void)fd, (void)tag, (void)data;
    return -UR_ENOSYS;
}

void ur_cancel(int64_t h, uint64_t tag) { (void)h, (void)tag; }

void ur_close(int64_t h, int32_t fd) { (void)h, (void)fd; }

void ur_take(int64_t h, int32_t buf, int64_t off, ur_bytes dst) {
    (void)h, (void)buf, (void)off, (void)dst;
}

void ur_give(int64_t h, int32_t buf) { (void)h, (void)buf; }

int32_t ur_wait(int64_t h, ur_completions out, int32_t timeout_ms) {
    (void)h, (void)out, (void)timeout_ms;
    return -UR_ENOSYS;
}
