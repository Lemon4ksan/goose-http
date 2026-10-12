/* The io_uring calls of the server's io_uring loop, for src/ring.goose, over
   liburing 2.14. liburing's helpers are static inline functions, which an
   extern fn can't bind, so these wrap the ones the loop uses. goose build
   compiles this beside the program (src/main_uring.build), so it spells out
   the layouts it shares with Goose, per spec C.2.

   Needs Linux 6.1: multishot accept (5.19), multishot receive into a provided
   buffer ring (6.0), and IORING_SETUP_DEFER_TASKRUN (6.1).

   The kernel writes a receive's bytes and reads a send's after the call that
   queued them returns, and spec §7.10 forbids C to keep a Goose argument past
   a call. So the ring owns every buffer the kernel touches: receives land in
   its provided buffers, which ur_take copies out of, and ur_send copies the
   bytes it's given. A ring is a number to Goose, the address of its struct
   ur, and belongs to the thread that created it (IORING_SETUP_SINGLE_ISSUER).

   Where io_uring_setup fails, as under Docker's default seccomp profile, or
   when asked, a ring is shim/ring_epoll.c's emulation over epoll instead:
   its address with the low bit set, which a struct ur's never has, and each
   call here passes it on. */
#include <errno.h>
#include <liburing.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

_Static_assert(ENOBUFS == 105 && ECANCELED == 125, "errno values differ from src/ring.goose");

/* A u8[:]: a pointer and a length, passed by value. */
typedef struct { uint8_t *data; int64_t len; } ur_bytes;

/* ring::Completion, packed as Goose packs a struct, and a slice of it. */
typedef struct __attribute__((packed)) {
    uint64_t tag;
    int32_t res, buf;
    uint8_t more, send;
} ur_completion;
_Static_assert(sizeof(ur_completion) == 18, "ur_completion is not packed");
typedef struct { ur_completion *data; int64_t len; } ur_completions;

/* A request's user_data: a Goose tag shifted left 2 (UR_TAGGED), a send
   record's address (UR_SEND), or UR_QUIET for cancels and closes, whose
   completions nobody needs. Tags fit in 62 bits. */
#define UR_TAGGED 0
#define UR_SEND 1
#define UR_QUIET 2

/* A send's bytes, owned by the ring until the send's last completion.
   Records of up to UR_SMALL bytes come in UR_CLASSES powers of two from
   UR_MIN, each with its own free list, so that a ring's records of small
   responses, one for each send in flight, pack into few pages. Bigger ones,
   sized in UR_BIG steps, go back to another while it holds under UR_KEEP
   bytes: freed to malloc, a record that size goes back to the kernel, and
   the next one faults its pages in again. */
#define UR_MIN 256
#define UR_CLASSES 6
#define UR_SMALL (UR_MIN << (UR_CLASSES - 1))
#define UR_BIG 65536
#define UR_KEEP (4u << 20)
struct ur_send {
    struct ur_send *next;
    uint64_t tag;
    int32_t fd;
    uint32_t gen;           /* fd's generation when the send was queued */
    uint32_t len, off;
    uint32_t cap;           /* data's size */
    unsigned char data[];
};

struct ur {
    struct io_uring ring;
    struct io_uring_buf_ring *br;
    unsigned char *bufs;
    uint32_t nbufs, buflen;
    int given;              /* buffers given back since the last ur_wait */
    struct ur_send *free[UR_CLASSES];
    struct ur_send *big;
    uint32_t kept;          /* the bytes of big's records */
    /* Per fd, the number of times this ring closed it. A short send's rest
       goes out only while its fd's generation is the send's: once the ring
       closes fd, the next accept, on any ring, may reuse the number. */
    uint32_t *gens;
    uint32_t ngens;
};

/* shim/ring_epoll.c, built with its functions named urp_*. */
int64_t urp_create(int32_t entries, int32_t nbufs, int32_t buflen, int32_t flags);
void urp_accept(int64_t h, int32_t fd, uint64_t tag);
void urp_recv(int64_t h, int32_t fd, uint64_t tag);
int32_t urp_send(int64_t h, int32_t fd, uint64_t tag, ur_bytes data);
void urp_cancel(int64_t h, uint64_t tag);
void urp_close(int64_t h, int32_t fd);
void urp_take(int64_t h, int32_t buf, int64_t off, ur_bytes dst);
void urp_give(int64_t h, int32_t buf);
int32_t urp_wait(int64_t h, ur_completions out, int32_t timeout_ms);
void urp_destroy(int64_t h);

/* ur_create's flag, ring.goose's RING_EMULATE. */
#define UR_EMULATE 1

/* Whether h is an emulated ring, and the emulation's own handle for it. */
#define UR_EMULATED(h) (((h) & 1) != 0)
#define UR_POLL(h) ((h) & ~(int64_t)1)

static int64_t ur_emulate(int32_t entries, int32_t nbufs, int32_t buflen) {
    int64_t h = urp_create(entries, nbufs, buflen, 0);
    return h < 0 ? h : h | 1;
}

/* Whether ur_create gets an io_uring ring here: 0, or the error that makes it
   fall back to the emulation. Sets up and tears down a small ring as
   ur_create sets up its own. */
int32_t ur_probe(void) {
    struct io_uring ring;
    struct io_uring_params p;
    memset(&p, 0, sizeof p);
    p.flags = IORING_SETUP_SINGLE_ISSUER | IORING_SETUP_DEFER_TASKRUN | IORING_SETUP_SUBMIT_ALL;
    int r = io_uring_queue_init_params(2, &ring, &p);
    if (r < 0) return r;
    struct io_uring_buf_ring *br = io_uring_setup_buf_ring(&ring, 1, 0, 0, &r);
    if (br) io_uring_free_buf_ring(&ring, br, 1, 0);
    io_uring_queue_exit(&ring);
    return br ? 0 : r;
}

/* An SQE, submitting what's queued first if the submission queue is full. */
static struct io_uring_sqe *ur_sqe(struct ur *u) {
    struct io_uring_sqe *sqe = io_uring_get_sqe(&u->ring);
    if (!sqe) {
        io_uring_submit(&u->ring);
        sqe = io_uring_get_sqe(&u->ring);
    }
    return sqe;
}

/* A ring of entries submission entries and four times as many completions,
   with nbufs provided buffers of buflen bytes in buffer group 0. nbufs must
   be a power of two. */
int64_t ur_create(int32_t entries, int32_t nbufs, int32_t buflen, int32_t flags) {
    if (flags & UR_EMULATE) return ur_emulate(entries, nbufs, buflen);
    struct ur *u = calloc(1, sizeof *u);
    if (!u) return -ENOMEM;
    struct io_uring_params p;
    memset(&p, 0, sizeof p);
    p.flags = IORING_SETUP_SINGLE_ISSUER | IORING_SETUP_DEFER_TASKRUN |
              IORING_SETUP_SUBMIT_ALL | IORING_SETUP_CQSIZE;
    p.cq_entries = (unsigned)entries * 4;
    int r = io_uring_queue_init_params((unsigned)entries, &u->ring, &p);
    if (r < 0) {
        free(u);
        return ur_emulate(entries, nbufs, buflen);
    }
    u->nbufs = (uint32_t)nbufs;
    u->buflen = (uint32_t)buflen;
    u->bufs = aligned_alloc(4096, (size_t)nbufs * (size_t)buflen);
    if (!u->bufs) r = -ENOMEM;
    else u->br = io_uring_setup_buf_ring(&u->ring, (unsigned)nbufs, 0, 0, &r);
    if (!u->br) {
        io_uring_queue_exit(&u->ring);
        free(u->bufs);
        free(u);
        return r == -ENOMEM ? r : ur_emulate(entries, nbufs, buflen);
    }
    int mask = io_uring_buf_ring_mask((unsigned)nbufs);
    for (int i = 0; i < nbufs; i++)
        io_uring_buf_ring_add(u->br, u->bufs + (size_t)i * u->buflen, u->buflen,
                              (unsigned short)i, mask, i);
    io_uring_buf_ring_advance(u->br, nbufs);
    return (int64_t)(intptr_t)u;
}

/* Queues a multishot accept on the listener fd. Accepted sockets are
   blocking, which io_uring doesn't need otherwise. */
void ur_accept(int64_t h, int32_t fd, uint64_t tag) {
    if (UR_EMULATED(h)) {
        urp_accept(UR_POLL(h), fd, tag);
        return;
    }
    struct ur *u = (struct ur *)(intptr_t)h;
    struct io_uring_sqe *sqe = ur_sqe(u);
    io_uring_prep_multishot_accept(sqe, fd, NULL, NULL, SOCK_CLOEXEC);
    io_uring_sqe_set_data64(sqe, tag << 2 | UR_TAGGED);
}

/* Queues a multishot receive into the provided buffers. */
void ur_recv(int64_t h, int32_t fd, uint64_t tag) {
    if (UR_EMULATED(h)) {
        urp_recv(UR_POLL(h), fd, tag);
        return;
    }
    struct ur *u = (struct ur *)(intptr_t)h;
    struct io_uring_sqe *sqe = ur_sqe(u);
    io_uring_prep_recv_multishot(sqe, fd, NULL, 0, 0);
    sqe->flags |= IOSQE_BUFFER_SELECT;
    sqe->buf_group = 0;
    io_uring_sqe_set_data64(sqe, tag << 2 | UR_TAGGED);
}

/* Copies data and queues a send of it, with MSG_NOSIGNAL. A short send is
   queued again for the rest inside ur_wait, which reports the send once. */
int32_t ur_send(int64_t h, int32_t fd, uint64_t tag, ur_bytes data) {
    if (UR_EMULATED(h)) return urp_send(UR_POLL(h), fd, tag, data);
    struct ur *u = (struct ur *)(intptr_t)h;
    struct ur_send *s;
    if ((uint32_t)fd >= u->ngens) {
        uint32_t n = u->ngens ? u->ngens : 1024;
        while (n <= (uint32_t)fd) n *= 2;
        uint32_t *g = realloc(u->gens, n * sizeof *g);
        if (!g) return -ENOMEM;
        memset(g + u->ngens, 0, (n - u->ngens) * sizeof *g);
        u->gens = g;
        u->ngens = n;
    }
    s = NULL;
    int k = 0;
    if (data.len <= UR_SMALL) {
        while ((UR_MIN << k) < data.len) k++;
        if (u->free[k]) {
            s = u->free[k];
            u->free[k] = s->next;
        }
    } else {
        for (struct ur_send **p = &u->big; *p; p = &(*p)->next) {
            if ((*p)->cap >= data.len) {
                s = *p;
                *p = s->next;
                u->kept -= s->cap;
                break;
            }
        }
    }
    if (!s) {
        size_t cap = data.len <= UR_SMALL ? (size_t)UR_MIN << k : ((size_t)data.len + UR_BIG - 1) / UR_BIG * UR_BIG;
        s = malloc(sizeof *s + cap);
        if (!s) return -ENOMEM;
        s->cap = (uint32_t)cap;
    }
    s->tag = tag;
    s->fd = fd;
    s->gen = u->gens[fd];
    s->len = (uint32_t)data.len;
    s->off = 0;
    memcpy(s->data, data.data, (size_t)data.len);
    struct io_uring_sqe *sqe = ur_sqe(u);
    io_uring_prep_send(sqe, fd, s->data, s->len, MSG_NOSIGNAL);
    io_uring_sqe_set_data64(sqe, (uint64_t)(uintptr_t)s | UR_SEND);
    return 0;
}

static void ur_send_free(struct ur *u, struct ur_send *s) {
    if (s->cap <= UR_SMALL) {
        int k = 0;
        while ((UR_MIN << k) < s->cap) k++;
        s->next = u->free[k];
        u->free[k] = s;
    } else if (u->kept + s->cap <= UR_KEEP) {
        s->next = u->big;
        u->big = s;
        u->kept += s->cap;
    } else {
        free(s);
    }
}

/* Queues a cancel of the request queued with tag. */
void ur_cancel(int64_t h, uint64_t tag) {
    if (UR_EMULATED(h)) {
        urp_cancel(UR_POLL(h), tag);
        return;
    }
    struct ur *u = (struct ur *)(intptr_t)h;
    struct io_uring_sqe *sqe = ur_sqe(u);
    io_uring_prep_cancel64(sqe, tag << 2 | UR_TAGGED, 0);
    io_uring_sqe_set_data64(sqe, UR_QUIET);
    sqe->flags |= IOSQE_CQE_SKIP_SUCCESS;
}

/* Queues a cancel of every request on fd, then its close. A queued request
   holds a reference to the socket, so closing fd alone would leave the
   connection open until its receive ended. */
void ur_close(int64_t h, int32_t fd) {
    if (UR_EMULATED(h)) {
        urp_close(UR_POLL(h), fd);
        return;
    }
    struct ur *u = (struct ur *)(intptr_t)h;
    if ((uint32_t)fd < u->ngens) u->gens[fd]++;
    struct io_uring_sqe *sqe = ur_sqe(u);
    io_uring_prep_cancel_fd(sqe, fd, IORING_ASYNC_CANCEL_ALL);
    io_uring_sqe_set_data64(sqe, UR_QUIET);
    sqe->flags |= IOSQE_IO_HARDLINK | IOSQE_CQE_SKIP_SUCCESS;
    sqe = io_uring_get_sqe(&u->ring);
    if (!sqe) {
        /* The link can't span a submit; close fd after what's queued. */
        io_uring_submit(&u->ring);
        close(fd);
        return;
    }
    io_uring_prep_close(sqe, fd);
    io_uring_sqe_set_data64(sqe, UR_QUIET);
    sqe->flags |= IOSQE_CQE_SKIP_SUCCESS;
}

/* Copies dst.len bytes of provided buffer buf from off into dst. */
void ur_take(int64_t h, int32_t buf, int64_t off, ur_bytes dst) {
    if (UR_EMULATED(h)) {
        urp_take(UR_POLL(h), buf, off, dst);
        return;
    }
    struct ur *u = (struct ur *)(intptr_t)h;
    memcpy(dst.data, u->bufs + (size_t)buf * u->buflen + off, (size_t)dst.len);
}

/* Gives provided buffer buf back to the kernel, at the next ur_wait. */
void ur_give(int64_t h, int32_t buf) {
    if (UR_EMULATED(h)) {
        urp_give(UR_POLL(h), buf);
        return;
    }
    struct ur *u = (struct ur *)(intptr_t)h;
    io_uring_buf_ring_add(u->br, u->bufs + (size_t)buf * u->buflen, u->buflen,
                          (unsigned short)buf, io_uring_buf_ring_mask(u->nbufs), u->given++);
}

/* Submits what's queued, waits up to timeout_ms (-1: no limit) for at least
   one completion, and writes up to out.len of them into out. Leaves any
   others for the next call. */
int32_t ur_wait(int64_t h, ur_completions out, int32_t timeout_ms) {
    if (UR_EMULATED(h)) return urp_wait(UR_POLL(h), out, timeout_ms);
    struct ur *u = (struct ur *)(intptr_t)h;
    if (u->given) {
        io_uring_buf_ring_advance(u->br, u->given);
        u->given = 0;
    }
    struct io_uring_cqe *cqe;
    int r;
    if (timeout_ms < 0) {
        r = io_uring_submit_and_wait(&u->ring, 1);
    } else {
        struct __kernel_timespec ts = { timeout_ms / 1000, (long long)(timeout_ms % 1000) * 1000000 };
        r = io_uring_submit_and_wait_timeout(&u->ring, &cqe, 1, &ts, NULL);
    }
    if (r < 0 && r != -ETIME) return r;
    int32_t n = 0;
    unsigned head, seen = 0;
    io_uring_for_each_cqe(&u->ring, head, cqe) {
        if (n == out.len) break;
        seen++;
        uint64_t ud = cqe->user_data;
        if ((ud & 3) == UR_QUIET) continue;
        ur_completion *c = &out.data[n];
        if ((ud & 3) == UR_SEND) {
            struct ur_send *s = (struct ur_send *)(uintptr_t)(ud & ~(uint64_t)3);
            int rest = cqe->res > 0 && s->off + (uint32_t)cqe->res < s->len;
            if (rest && s->gen == u->gens[s->fd]) {
                s->off += (uint32_t)cqe->res;
                struct io_uring_sqe *sqe = ur_sqe(u);
                io_uring_prep_send(sqe, s->fd, s->data + s->off, s->len - s->off, MSG_NOSIGNAL);
                io_uring_sqe_set_data64(sqe, ud);
                continue;
            }
            c->tag = s->tag;
            c->res = rest ? -ECANCELED : cqe->res < 0 ? cqe->res : (int32_t)s->len;
            c->buf = -1;
            c->more = 0;
            c->send = 1;
            ur_send_free(u, s);
        } else {
            c->tag = ud >> 2;
            c->res = cqe->res;
            c->buf = cqe->flags & IORING_CQE_F_BUFFER ? (int32_t)(cqe->flags >> IORING_CQE_BUFFER_SHIFT) : -1;
            c->more = (cqe->flags & IORING_CQE_F_MORE) != 0;
            c->send = 0;
        }
        n++;
    }
    io_uring_cq_advance(&u->ring, seen);
    return n;
}

/* Tears the ring down, with whatever is still queued on it. The records of
   sends still in flight aren't freed: only a completion says when the kernel
   is done with one. */
void ur_destroy(int64_t h) {
    if (UR_EMULATED(h)) {
        urp_destroy(UR_POLL(h));
        return;
    }
    struct ur *u = (struct ur *)(intptr_t)h;
    io_uring_free_buf_ring(&u->ring, u->br, u->nbufs, 0);
    io_uring_queue_exit(&u->ring);
    for (int k = 0; k < UR_CLASSES; k++) {
        while (u->free[k]) {
            struct ur_send *s = u->free[k];
            u->free[k] = s->next;
            free(s);
        }
    }
    while (u->big) {
        struct ur_send *s = u->big;
        u->big = s->next;
        free(s);
    }
    free(u->bufs);
    free(u->gens);
    free(u);
}
