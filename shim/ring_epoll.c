/* ring.goose's calls emulated over the shim's own readiness calls (net_epoll_*,
   net_accept, net_recv, net_send, net_close), for where there's no io_uring.
   On Linux, shim/uring.c falls back to it when io_uring_setup fails, as in a
   container whose seccomp profile blocks io_uring, and its functions are named
   urp_*. On macOS, built with RING_EPOLL_ONLY, it is the ring, named ur_*,
   over shim/kqueue.c's epoll calls.

   A multishot accept accepts until the listener's backlog is empty, and a
   multishot receive reads into the provided buffers until the socket is
   empty, both again at each edge-triggered event. A send's bytes are copied
   and sent in the next ur_wait, and what the socket doesn't take waits for
   its writable edge. Completions that don't fit in ur_wait's out wait in a
   queue for the next call. Every call returns the same Linux errno values
   as the rest of the shim. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef RING_EPOLL_ONLY
#define RP(name) ur_##name
#else
#define RP(name) urp_##name
#endif

/* Linux's errno values, which the net_* calls return on every platform, and
   src's ring.goose and sys.goose name. */
#define RP_EINTR 4
#define RP_EAGAIN 11
#define RP_ENOMEM 12
#define RP_ENOSYS 38
#define RP_ECONNABORTED 103
#define RP_ENOBUFS 105
#define RP_ECANCELED 125

/* sys.goose's flags, epoll bits, and epoll_ctl op. */
#define RP_NONBLOCK 1
#define RP_IN 0x001u
#define RP_OUT 0x004u
#define RP_ERR 0x008u
#define RP_HUP 0x010u
#define RP_RDHUP 0x2000u
#define RP_ET 0x80000000u
#define RP_CTL_ADD 1

/* The listener's epoll tag. A connection's is its fd. */
#define RP_LISTENER UINT64_MAX

/* The layouts shared with Goose, per spec C.2: a u8[:], http::Event,
   http::Completion, and slices of the last two. */
typedef struct { uint8_t *data; int64_t len; } rp_bytes;
#pragma pack(push, 1)
typedef struct { uint32_t events; uint64_t tag; } rp_event;
typedef struct { uint64_t tag; int32_t res, buf; uint8_t more, send; } rp_completion;
#pragma pack(pop)
_Static_assert(sizeof(rp_event) == 12 && sizeof(rp_completion) == 18, "not packed");
typedef struct { rp_event *data; int64_t len; } rp_events;
typedef struct { rp_completion *data; int64_t len; } rp_completions;

/* From shim/net.c or shim/kqueue.c. */
int32_t net_accept(int32_t fd, int32_t flags);
int64_t net_recv(int32_t fd, rp_bytes buf);
int64_t net_send(int32_t fd, rp_bytes data);
int32_t net_close(int32_t fd);
int32_t net_epoll_create(void);
int32_t net_epoll_ctl(int32_t ep, int32_t op, int32_t fd, uint32_t events, uint64_t tag);
int32_t net_epoll_wait(int32_t ep, rp_events out, int32_t timeout_ms);

/* A send's bytes, owned by the ring until they're sent. */
struct rp_send {
    struct rp_send *next;
    uint64_t tag;
    uint32_t len, off;
    unsigned char data[];
};

/* What the ring knows of a socket, indexed by its fd. */
struct rp_fd {
    uint64_t tag;                   /* its receive's */
    struct rp_send *sends, *last;   /* queued in order, the first maybe partly sent */
    uint8_t added;                  /* registered with the epoll instance */
    uint8_t reading;                /* its multishot receive goes on */
    uint8_t readable;               /* may hold bytes: read until EAGAIN */
    uint8_t writable;               /* may take bytes: send until EAGAIN */
    uint8_t queued;                 /* on the ready list */
};

struct rp {
    int32_t ep;
    unsigned char *bufs;
    uint32_t nbufs, buflen;
    int32_t *free;                  /* the ids of free buffers, a stack */
    uint32_t nfree;
    struct rp_fd *fds;
    uint32_t nfds;
    int32_t *ready;                 /* fds with work for the next ur_wait */
    uint32_t nready, capready;
    rp_completion *done;            /* completions that didn't fit in out */
    uint32_t headdone, ndone, capdone;
    int32_t lfd;
    uint64_t ltag;
    uint8_t ladded, accepting, acceptable;
    int32_t err;                    /* -ENOMEM once the bookkeeping ran out, for ur_wait */
};

/* fd's record, made on its first request, or NULL when out of memory. */
static struct rp_fd *rp_fd_of(struct rp *u, int32_t fd) {
    if ((uint32_t)fd >= u->nfds) {
        uint32_t n = u->nfds ? u->nfds : 1024;
        while (n <= (uint32_t)fd) n *= 2;
        struct rp_fd *f = realloc(u->fds, n * sizeof *f);
        if (!f) {
            u->err = -RP_ENOMEM;
            return NULL;
        }
        memset(f + u->nfds, 0, (n - u->nfds) * sizeof *f);
        u->fds = f;
        u->nfds = n;
    }
    return &u->fds[fd];
}

static void rp_queue(struct rp *u, int32_t fd) {
    struct rp_fd *f = &u->fds[fd];
    if (f->queued) return;
    if (u->nready == u->capready) {
        uint32_t n = u->capready ? u->capready * 2 : 1024;
        int32_t *r = realloc(u->ready, n * sizeof *r);
        if (!r) {
            u->err = -RP_ENOMEM;
            return;
        }
        u->ready = r;
        u->capready = n;
    }
    u->ready[u->nready++] = fd;
    f->queued = 1;
}

/* Adds a completion to out, or to the queue behind the ones already
   waiting, which keeps a connection's completions in order. */
static void rp_emit(struct rp *u, rp_completions out, int32_t *n, uint64_t tag, int32_t res,
                    int32_t buf, int more, int send) {
    rp_completion c = { tag, res, buf, (uint8_t)more, (uint8_t)send };
    if (u->headdone == u->ndone && *n < out.len) {
        out.data[(*n)++] = c;
        return;
    }
    if (u->ndone == u->capdone) {
        if (u->headdone > 0) {
            memmove(u->done, u->done + u->headdone, (u->ndone - u->headdone) * sizeof c);
            u->ndone -= u->headdone;
            u->headdone = 0;
        } else {
            uint32_t m = u->capdone ? u->capdone * 2 : 256;
            rp_completion *d = realloc(u->done, m * sizeof c);
            if (!d) {
                u->err = -RP_ENOMEM;
                return;
            }
            u->done = d;
            u->capdone = m;
        }
    }
    u->done[u->ndone++] = c;
}

/* The completions of calls that return nothing, for the next ur_wait. */
static void rp_later(struct rp *u, uint64_t tag, int32_t res) {
    int32_t n = 0;
    rp_completions none = { NULL, 0 };
    rp_emit(u, none, &n, tag, res, -1, 0, 0);
}

static int32_t rp_add(struct rp *u, int32_t fd, struct rp_fd *f) {
    if (f->added) return 0;
    int32_t r = net_epoll_ctl(u->ep, RP_CTL_ADD, fd, RP_IN | RP_OUT | RP_RDHUP | RP_ET, (uint64_t)fd);
    if (r < 0) return r;
    f->added = 1;
    f->writable = 1;
    return 0;
}

int64_t RP(create)(int32_t entries, int32_t nbufs, int32_t buflen, int32_t flags) {
    (void)entries, (void)flags;
    struct rp *u = calloc(1, sizeof *u);
    if (!u) return -RP_ENOMEM;
    u->ep = net_epoll_create();
    if (u->ep < 0) {
        int32_t r = u->ep;
        free(u);
        return r;
    }
    u->nbufs = (uint32_t)nbufs;
    u->buflen = (uint32_t)buflen;
    u->bufs = malloc((size_t)nbufs * (size_t)buflen);
    u->free = malloc((size_t)nbufs * sizeof *u->free);
    if (!u->bufs || !u->free) {
        net_close(u->ep);
        free(u->bufs);
        free(u->free);
        free(u);
        return -RP_ENOMEM;
    }
    for (int32_t i = 0; i < nbufs; i++) u->free[i] = nbufs - 1 - i;
    u->nfree = (uint32_t)nbufs;
    u->lfd = -1;
    return (int64_t)(intptr_t)u;
}

/* Accepts on the listener fd at each of its events, until a cancel or an
   error, starting in the next ur_wait: the backlog may hold clients already. */
void RP(accept)(int64_t h, int32_t fd, uint64_t tag) {
    struct rp *u = (struct rp *)(intptr_t)h;
    if (!u->ladded || u->lfd != fd) {
        int32_t r = net_epoll_ctl(u->ep, RP_CTL_ADD, fd, RP_IN | RP_ET, RP_LISTENER);
        if (r < 0) {
            rp_later(u, tag, r);
            return;
        }
        u->ladded = 1;
    }
    u->lfd = fd;
    u->ltag = tag;
    u->accepting = 1;
    u->acceptable = 1;
}

/* Reads fd into the provided buffers at each of its events, until a cancel,
   the end of the stream, or no buffer left, starting in the next ur_wait:
   bytes may be waiting already. */
void RP(recv)(int64_t h, int32_t fd, uint64_t tag) {
    struct rp *u = (struct rp *)(intptr_t)h;
    struct rp_fd *f = rp_fd_of(u, fd);
    if (!f) return;
    int32_t r = rp_add(u, fd, f);
    if (r < 0) {
        rp_later(u, tag, r);
        return;
    }
    f->tag = tag;
    f->reading = 1;
    f->readable = 1;
    rp_queue(u, fd);
}

/* Copies data, to send it in the next ur_wait after any sends queued before
   it on fd. */
int32_t RP(send)(int64_t h, int32_t fd, uint64_t tag, rp_bytes data) {
    struct rp *u = (struct rp *)(intptr_t)h;
    struct rp_fd *f = rp_fd_of(u, fd);
    if (!f) return -RP_ENOMEM;
    int32_t r = rp_add(u, fd, f);
    if (r < 0) return r;
    struct rp_send *s = malloc(sizeof *s + (size_t)data.len);
    if (!s) return -RP_ENOMEM;
    s->next = NULL;
    s->tag = tag;
    s->len = (uint32_t)data.len;
    s->off = 0;
    memcpy(s->data, data.data, (size_t)data.len);
    if (f->last) f->last->next = s;
    else f->sends = s;
    f->last = s;
    rp_queue(u, fd);
    return 0;
}

/* Ends the accept or the receive started with tag, with an ECANCELED
   completion. */
void RP(cancel)(int64_t h, uint64_t tag) {
    struct rp *u = (struct rp *)(intptr_t)h;
    if (u->accepting && u->ltag == tag) {
        u->accepting = 0;
        rp_later(u, tag, -RP_ECANCELED);
        return;
    }
    for (uint32_t fd = 0; fd < u->nfds; fd++) {
        struct rp_fd *f = &u->fds[fd];
        if (f->reading && f->tag == tag) {
            f->reading = 0;
            rp_later(u, tag, -RP_ECANCELED);
            return;
        }
    }
}

/* Closes fd. Its sends not yet made are dropped, with no completion. */
void RP(close)(int64_t h, int32_t fd) {
    struct rp *u = (struct rp *)(intptr_t)h;
    if ((uint32_t)fd < u->nfds) {
        struct rp_fd *f = &u->fds[fd];
        for (struct rp_send *s = f->sends, *next; s; s = next) {
            next = s->next;
            free(s);
        }
        uint8_t queued = f->queued;
        memset(f, 0, sizeof *f);
        f->queued = queued;
    }
    net_close(fd);
}

#ifdef RING_EPOLL_ONLY
/* There's no io_uring to probe for: the ring is always this emulation. */
int32_t ur_probe(void) { return -RP_ENOSYS; }
#endif

void RP(take)(int64_t h, int32_t buf, int64_t off, rp_bytes dst) {
    struct rp *u = (struct rp *)(intptr_t)h;
    memcpy(dst.data, u->bufs + (size_t)buf * u->buflen + off, (size_t)dst.len);
}

void RP(give)(int64_t h, int32_t buf) {
    struct rp *u = (struct rp *)(intptr_t)h;
    u->free[u->nfree++] = buf;
}

/* Accepts, sends, and reads what the listener and the queued sockets allow,
   and makes their completions. */
static void rp_work(struct rp *u, rp_completions out, int32_t *n) {
    while (u->accepting && u->acceptable) {
        int32_t fd = net_accept(u->lfd, RP_NONBLOCK);
        if (fd == -RP_EAGAIN) {
            u->acceptable = 0;
            break;
        }
        if (fd == -RP_EINTR || fd == -RP_ECONNABORTED) continue;
        /* EMFILE or ENFILE ends the accept, as io_uring's does, and leaves
           the backlog to the accept queued after it. */
        if (fd < 0) u->accepting = 0;
        rp_emit(u, out, n, u->ltag, fd, -1, fd >= 0, 0);
    }
    for (uint32_t i = 0; i < u->nready; i++) {
        int32_t fd = u->ready[i];
        struct rp_fd *f = &u->fds[fd];
        f->queued = 0;
        while (f->sends && f->writable) {
            struct rp_send *s = f->sends;
            rp_bytes rest = { s->data + s->off, (int64_t)(s->len - s->off) };
            int64_t r = rest.len > 0 ? net_send(fd, rest) : 0;
            if (r == -RP_EAGAIN) {
                f->writable = 0;
                break;
            }
            if (r == -RP_EINTR) continue;
            if (r >= 0) s->off += (uint32_t)r;
            if (r >= 0 && s->off < s->len) continue;
            rp_emit(u, out, n, s->tag, r < 0 ? (int32_t)r : (int32_t)s->len, -1, 0, 1);
            f->sends = s->next;
            if (!f->sends) f->last = NULL;
            free(s);
        }
        while (f->reading && f->readable) {
            if (u->nfree == 0) {
                /* As io_uring ends a multishot receive that finds no buffer.
                   The socket stays readable for the receive queued next. */
                f->reading = 0;
                rp_emit(u, out, n, f->tag, -RP_ENOBUFS, -1, 0, 0);
                break;
            }
            int32_t b = u->free[--u->nfree];
            rp_bytes into = { u->bufs + (size_t)b * u->buflen, u->buflen };
            int64_t r = net_recv(fd, into);
            if (r == -RP_EAGAIN || r == -RP_EINTR) u->free[u->nfree++] = b;
            if (r == -RP_EAGAIN) {
                f->readable = 0;
                break;
            }
            if (r == -RP_EINTR) continue;
            if (r <= 0) {
                /* The end of the stream, or an error. */
                u->free[u->nfree++] = b;
                f->reading = 0;
                f->readable = 0;
                rp_emit(u, out, n, f->tag, (int32_t)r, -1, 0, 0);
                break;
            }
            rp_emit(u, out, n, f->tag, (int32_t)r, b, 1, 0);
        }
    }
    u->nready = 0;
}

/* Makes what's queued, waits up to timeout_ms (-1: no limit) for events if
   that made no completion, and writes up to out.len completions into out. */
int32_t RP(wait)(int64_t h, rp_completions out, int32_t timeout_ms) {
    struct rp *u = (struct rp *)(intptr_t)h;
    if (u->err) return u->err;
    int32_t n = 0;
    while (n < out.len && u->headdone < u->ndone) out.data[n++] = u->done[u->headdone++];
    if (u->headdone == u->ndone) u->headdone = u->ndone = 0;
    rp_work(u, out, &n);
    if (n > 0) return n;
    rp_event evs[256];
    rp_events in = { evs, 256 };
    int32_t got = net_epoll_wait(u->ep, in, timeout_ms);
    if (got < 0) return got;
    for (int32_t i = 0; i < got; i++) {
        if (evs[i].tag == RP_LISTENER) {
            u->acceptable = 1;
            continue;
        }
        int32_t fd = (int32_t)evs[i].tag;
        struct rp_fd *f = &u->fds[fd];
        if (!f->added) continue;
        if (evs[i].events & (RP_IN | RP_RDHUP | RP_HUP | RP_ERR)) f->readable = 1;
        if (evs[i].events & (RP_OUT | RP_HUP | RP_ERR)) f->writable = 1;
        rp_queue(u, fd);
    }
    rp_work(u, out, &n);
    return u->err ? u->err : n;
}
