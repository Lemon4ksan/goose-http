/* The ring of src/ring.goose on Windows, over an I/O completion port and
   Winsock, so the io_uring loop of src/uring.goose runs unchanged. goose
   build compiles this beside the program (src/main_uring.build), so it
   spells out the layouts it shares with Goose, per spec C.2. Errors are
   Linux's errno values, from net_win_err in shim/net_win.c.

   IOCP completes one operation per request, so this emulates what io_uring
   has and IOCP lacks:

   - A multishot accept is an AcceptEx kept posted on the listener, and
     posted again after each completion.
   - A multishot receive into provided buffers is a zero-byte WSARecv kept
     posted on the socket. Its completion says that data has arrived, and
     ur_wait then reads it with a non-blocking recv into a free buffer of the
     ring's, reported with the buffer's id. So an idle connection holds no
     buffer, as with io_uring, where the kernel picks a buffer only once
     data arrives.
   - A short send is posted again for the rest, and reported once.
   - A cancel is CancelIoEx, and a close is closesocket, which ends every
     request on the socket.

   The workers share one listener (shim/net_win.c), and a socket's requests
   complete on the port it's associated with, of which it can have one. So the
   listener isn't associated with any: each ring's AcceptEx signals an event,
   and a wait registered on the event posts the completion to the ring's
   port, as libuv does for a socket it can't associate.

   The ring owns every buffer the kernel touches after a call returns, as in
   shim/uring.c, since spec §7.10 forbids C to keep a Goose argument past a
   call: received bytes are in its buffers, which ur_take copies out of, and
   ur_send copies the bytes it's given. A ring is a number to Goose, the
   address of its struct ur, and belongs to the thread that created it. */
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <mswsock.h>
#include <windows.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* From shim/net_win.c. */
int32_t net_win_err(int err);
int32_t net_win_init(void);

/* Linux's errno values, as src/ring.goose and src/sys.goose name them. */
#define UR_ENOMEM 12
#define UR_ENOBUFS 105
#define UR_ECANCELED 125

/* A u8[:]: a pointer and a length, passed by value. */
typedef struct { uint8_t *data; int64_t len; } ur_bytes;

/* ring::Completion, packed as Goose packs a struct, and a slice of it. */
#pragma pack(push, 1)
typedef struct {
    uint64_t tag;
    int32_t res, buf;
    uint8_t more, send;
} ur_completion;
#pragma pack(pop)
_Static_assert(sizeof(ur_completion) == 18, "ur_completion is not packed");
typedef struct { ur_completion *data; int64_t len; } ur_completions;

/* ur_wait takes at most this many completions from the port per call. */
#define UR_MAX_EVENTS 256

enum { UR_ACCEPT, UR_RECV, UR_SEND };

/* A request: its OVERLAPPED comes first, so the OVERLAPPED a completion
   names is the request. A request that failed when it was posted, with no
   completion to come, waits on the ring's ready list with its error. */
struct ur_req {
    OVERLAPPED ov;
    int kind;
    int32_t err;               /* -code, while on the ready list */
    struct ur_req *next;       /* on the ready list */
};

/* A socket the ring has posted a receive or a send on. It lives until it's
   closed and the kernel has given back every request on it: refs counts
   those requests, and one more until ur_close. */
struct ur_sock {
    struct ur_req rd;          /* its zero-byte receive */
    SOCKET s;
    uint64_t tag;              /* the receive's */
    int refs;
    uint8_t reading, cancel, closed;
};

/* A send's bytes, owned by the ring until the send completes. Records of
   UR_SMALL bytes or fewer go back to a free list; bigger ones are allocated
   for one send. */
#define UR_SMALL 8192
struct ur_send {
    struct ur_req rq;
    struct ur_sock *sock;
    struct ur_send *next;      /* on the free list */
    uint64_t tag;
    uint32_t len, off;
    unsigned char data[];
};

/* The ring's AcceptEx. as is the socket it accepts into. */
struct ur_accept {
    struct ur_req rq;
    SOCKET ls, as;
    uint64_t tag;
    HANDLE port, event, wait;
    uint8_t active, cancel;
    char addrs[2 * (sizeof(struct sockaddr_in) + 16)];
};

/* An open-addressing hash map from a nonzero key to a pointer. */
struct ur_map {
    uint64_t *keys;
    void **vals;
    uint32_t cap, len;
};

struct ur {
    HANDLE port;
    unsigned char *bufs;
    uint32_t nbufs, buflen;
    int32_t *free;             /* the ids of free buffers, a stack */
    uint32_t nfree;
    struct ur_send *spare;
    struct ur_req *ready, *ready_last;
    struct ur_accept acc;
    struct ur_map socks;       /* socket -> ur_sock, until it's closed */
    struct ur_map reads;       /* tag -> ur_sock, while its receive goes on */
    int32_t err;               /* -ENOMEM once the bookkeeping ran out, for ur_wait */
};

static uint32_t ur_hash(uint64_t k) {
    k ^= k >> 33;
    k *= 0xff51afd7ed558ccdull;
    k ^= k >> 33;
    return (uint32_t)k;
}

static void *ur_map_get(struct ur_map *m, uint64_t k) {
    if (!m->cap) return NULL;
    for (uint32_t i = ur_hash(k) & (m->cap - 1);; i = (i + 1) & (m->cap - 1)) {
        if (!m->vals[i]) return NULL;
        if (m->keys[i] == k) return m->vals[i];
    }
}

/* Returns 0, or -ENOMEM with m unchanged. */
static int32_t ur_map_put(struct ur_map *m, uint64_t k, void *v) {
    if ((m->len + 1) * 2 > m->cap) {
        struct ur_map old = *m;
        m->cap = old.cap ? old.cap * 2 : 1024;
        m->len = 0;
        m->keys = calloc(m->cap, sizeof *m->keys);
        m->vals = calloc(m->cap, sizeof *m->vals);
        if (!m->keys || !m->vals) {
            free(m->keys);
            free(m->vals);
            *m = old;
            return -UR_ENOMEM;
        }
        for (uint32_t i = 0; i < old.cap; i++)
            if (old.vals[i]) ur_map_put(m, old.keys[i], old.vals[i]);
        free(old.keys);
        free(old.vals);
    }
    uint32_t i = ur_hash(k) & (m->cap - 1);
    while (m->vals[i] && m->keys[i] != k) i = (i + 1) & (m->cap - 1);
    if (!m->vals[i]) m->len++;
    m->keys[i] = k;
    m->vals[i] = v;
    return 0;
}

/* Removes k, moving back the entries after it that its slot kept from their
   own, so no lookup needs a tombstone. */
static void ur_map_del(struct ur_map *m, uint64_t k) {
    if (!m->cap) return;
    uint32_t mask = m->cap - 1, i = ur_hash(k) & mask;
    while (m->vals[i] && m->keys[i] != k) i = (i + 1) & mask;
    if (!m->vals[i]) return;
    m->len--;
    for (uint32_t j = i;;) {
        m->vals[i] = NULL;
        for (;;) {
            j = (j + 1) & mask;
            if (!m->vals[j]) return;
            uint32_t h = ur_hash(m->keys[j]) & mask;
            /* An entry whose home slot is in (i, j] stays where it is. */
            if (i <= j ? (i < h && h <= j) : (i < h || h <= j)) continue;
            break;
        }
        m->keys[i] = m->keys[j];
        m->vals[i] = m->vals[j];
        i = j;
    }
}

static void ur_ready(struct ur *u, struct ur_req *q, int err) {
    q->err = -net_win_err(err);
    q->next = NULL;
    if (u->ready) u->ready_last->next = q;
    else u->ready = q;
    u->ready_last = q;
}

static void ur_unref(struct ur_sock *k) {
    if (--k->refs == 0) free(k);
}

/* Runs on a thread of the system's wait pool when the AcceptEx completes,
   and hands the completion to the ring's port. */
static VOID CALLBACK ur_accepted(PVOID ctx, BOOLEAN timed_out) {
    (void)timed_out;
    struct ur_accept *a = ctx;
    PostQueuedCompletionStatus(a->port, 0, 0, &a->rq.ov);
}

static void ur_post_accept(struct ur *u) {
    struct ur_accept *a = &u->acc;
    a->as = WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, NULL, 0,
                       WSA_FLAG_OVERLAPPED | WSA_FLAG_NO_HANDLE_INHERIT);
    a->active = 1;
    if (a->as == INVALID_SOCKET) {
        ur_ready(u, &a->rq, WSAGetLastError());
        return;
    }
    memset(&a->rq.ov, 0, sizeof a->rq.ov);
    a->rq.ov.hEvent = a->event;
    DWORD got;
    if (!AcceptEx(a->ls, a->as, a->addrs, 0, sizeof a->addrs / 2, sizeof a->addrs / 2,
                  &got, &a->rq.ov)) {
        int err = WSAGetLastError();
        if (err != ERROR_IO_PENDING) {
            closesocket(a->as);
            a->as = INVALID_SOCKET;
            ur_ready(u, &a->rq, err);
        }
    }
}

/* Posts sock's zero-byte receive. */
static void ur_post_recv(struct ur *u, struct ur_sock *k) {
    WSABUF b = { 0, NULL };
    DWORD flags = 0;
    memset(&k->rd.ov, 0, sizeof k->rd.ov);
    k->refs++;
    if (WSARecv(k->s, &b, 1, NULL, &flags, &k->rd.ov, NULL)) {
        int err = WSAGetLastError();
        if (err != WSA_IO_PENDING) ur_ready(u, &k->rd, err);
    }
}

static void ur_post_send(struct ur *u, struct ur_send *s) {
    WSABUF b = { s->len - s->off, (char *)s->data + s->off };
    memset(&s->rq.ov, 0, sizeof s->rq.ov);
    s->sock->refs++;
    if (WSASend(s->sock->s, &b, 1, NULL, 0, &s->rq.ov, NULL)) {
        int err = WSAGetLastError();
        if (err != WSA_IO_PENDING) ur_ready(u, &s->rq, err);
    }
}

static void ur_send_free(struct ur *u, struct ur_send *s) {
    if (s->len <= UR_SMALL) {
        s->next = u->spare;
        u->spare = s;
    } else {
        free(s);
    }
}

/* The ring's record of socket fd, made on its first request, or NULL when
   out of memory. */
static struct ur_sock *ur_sock_of(struct ur *u, int32_t fd) {
    struct ur_sock *k = ur_map_get(&u->socks, (uint32_t)fd);
    if (k) return k;
    k = calloc(1, sizeof *k);
    if (!k) return NULL;
    k->rd.kind = UR_RECV;
    k->s = (SOCKET)(intptr_t)fd;
    k->refs = 1;
    if (ur_map_put(&u->socks, (uint32_t)fd, k) < 0) {
        free(k);
        return NULL;
    }
    return k;
}

/* A ring with nbufs buffers of buflen bytes. entries sizes io_uring's
   submission queue; a completion port has none to size, and Windows has no
   emulation for flags to ask for. */
int64_t ur_create(int32_t entries, int32_t nbufs, int32_t buflen, int32_t flags) {
    (void)entries, (void)flags;
    int32_t r = net_win_init();
    if (r < 0) return r;
    struct ur *u = calloc(1, sizeof *u);
    if (!u) return -UR_ENOMEM;
    u->nbufs = (uint32_t)nbufs;
    u->buflen = (uint32_t)buflen;
    u->bufs = malloc((size_t)nbufs * (size_t)buflen);
    u->free = malloc((size_t)nbufs * sizeof *u->free);
    u->port = CreateIoCompletionPort(INVALID_HANDLE_VALUE, NULL, 0, 1);
    u->acc.event = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (!u->bufs || !u->free || !u->port || !u->acc.event) {
        r = u->bufs && u->free ? -net_win_err((int)GetLastError()) : -UR_ENOMEM;
        if (u->port) CloseHandle(u->port);
        if (u->acc.event) CloseHandle(u->acc.event);
        free(u->bufs);
        free(u->free);
        free(u);
        return r;
    }
    for (int32_t i = 0; i < nbufs; i++) u->free[i] = nbufs - 1 - i;
    u->nfree = (uint32_t)nbufs;
    u->acc.rq.kind = UR_ACCEPT;
    u->acc.port = u->port;
    return (int64_t)(intptr_t)u;
}

/* The ring is always a completion port. */
int32_t ur_probe(void) { return 0; }

/* Posts an AcceptEx on the listener fd, and again after each completion,
   until a cancel or an error. Accepted sockets have TCP_NODELAY and are
   non-blocking. */
void ur_accept(int64_t h, int32_t fd, uint64_t tag) {
    struct ur *u = (struct ur *)(intptr_t)h;
    struct ur_accept *a = &u->acc;
    if (!a->wait && !RegisterWaitForSingleObject(&a->wait, a->event, ur_accepted, a,
                                                 INFINITE, WT_EXECUTEINWAITTHREAD)) {
        a->active = 1;
        a->tag = tag;
        a->as = INVALID_SOCKET;
        ur_ready(u, &a->rq, (int)GetLastError());
        return;
    }
    a->ls = (SOCKET)(intptr_t)fd;
    a->tag = tag;
    a->cancel = 0;
    ur_post_accept(u);
}

/* Posts the zero-byte receive that stands for a multishot receive. Out of
   memory, it posts nothing, and the next ur_wait fails with ENOMEM. */
void ur_recv(int64_t h, int32_t fd, uint64_t tag) {
    struct ur *u = (struct ur *)(intptr_t)h;
    struct ur_sock *k = ur_sock_of(u, fd);
    if (!k || ur_map_put(&u->reads, tag, k) < 0) {
        u->err = -UR_ENOMEM;
        return;
    }
    k->tag = tag;
    k->reading = 1;
    k->cancel = 0;
    ur_post_recv(u, k);
}

/* Copies data and posts a send of it. A short send is posted again for the
   rest inside ur_wait, which reports the send once. */
int32_t ur_send(int64_t h, int32_t fd, uint64_t tag, ur_bytes data) {
    struct ur *u = (struct ur *)(intptr_t)h;
    struct ur_send *s;
    if (data.len <= UR_SMALL && u->spare) {
        s = u->spare;
        u->spare = s->next;
    } else {
        s = malloc(sizeof *s + (data.len <= UR_SMALL ? UR_SMALL : (size_t)data.len));
        if (!s) return -UR_ENOMEM;
    }
    s->rq.kind = UR_SEND;
    s->sock = ur_sock_of(u, fd);
    s->tag = tag;
    s->len = (uint32_t)data.len;
    if (!s->sock) {
        ur_send_free(u, s);
        return -UR_ENOMEM;
    }
    s->off = 0;
    memcpy(s->data, data.data, (size_t)data.len);
    ur_post_send(u, s);
    return 0;
}

/* Cancels the accept or the receive posted with tag. Its completion reports
   ECANCELED, or what it got before the cancel landed, and ends it. */
void ur_cancel(int64_t h, uint64_t tag) {
    struct ur *u = (struct ur *)(intptr_t)h;
    if (u->acc.active && u->acc.tag == tag) {
        u->acc.cancel = 1;
        CancelIoEx((HANDLE)u->acc.ls, &u->acc.rq.ov);
        return;
    }
    struct ur_sock *k = ur_map_get(&u->reads, tag);
    if (k) {
        k->cancel = 1;
        CancelIoEx((HANDLE)k->s, &k->rd.ov);
    }
}

/* Closes fd, which ends every request on it with an error. Their
   completions still come, and are reported with their tags. */
void ur_close(int64_t h, int32_t fd) {
    struct ur *u = (struct ur *)(intptr_t)h;
    struct ur_sock *k = ur_map_get(&u->socks, (uint32_t)fd);
    closesocket((SOCKET)(intptr_t)fd);
    if (!k) return;
    ur_map_del(&u->socks, (uint32_t)fd);
    if (k->reading && ur_map_get(&u->reads, k->tag) == k) ur_map_del(&u->reads, k->tag);
    k->closed = 1;
    ur_unref(k);
}

/* Copies dst.len bytes of buffer buf from off into dst. */
void ur_take(int64_t h, int32_t buf, int64_t off, ur_bytes dst) {
    struct ur *u = (struct ur *)(intptr_t)h;
    memcpy(dst.data, u->bufs + (size_t)buf * u->buflen + off, (size_t)dst.len);
}

void ur_give(int64_t h, int32_t buf) {
    struct ur *u = (struct ur *)(intptr_t)h;
    u->free[u->nfree++] = buf;
}

/* A request's result: its byte count, or -code. */
static int32_t ur_result(struct ur_req *q, SOCKET s) {
    DWORD bytes, flags;
    if (q->ov.Internal == 0) return (int32_t)q->ov.InternalHigh;
    if (WSAGetOverlappedResult(s, &q->ov, &bytes, FALSE, &flags)) return (int32_t)bytes;
    return -net_win_err(WSAGetLastError());
}

static int ur_fill(ur_completion *c, uint64_t tag, int32_t res, int32_t buf, int more, int send) {
    c->tag = tag;
    c->res = res;
    c->buf = buf;
    c->more = (uint8_t)more;
    c->send = (uint8_t)send;
    return 1;
}

static void ur_end_read(struct ur *u, struct ur_sock *k) {
    k->reading = 0;
    if (ur_map_get(&u->reads, k->tag) == k) ur_map_del(&u->reads, k->tag);
}

/* The accept completed with res, the accepted socket or -code. Writes its
   completion into c, if it has one, and returns whether it did. */
static int ur_finish_accept(struct ur *u, int32_t res, ur_completion *c) {
    struct ur_accept *a = &u->acc;
    SOCKET s = a->as;
    a->active = 0;
    a->as = INVALID_SOCKET;
    if (res >= 0) {
        BOOL one = TRUE;
        u_long nb = 1;
        if (setsockopt(s, SOL_SOCKET, SO_UPDATE_ACCEPT_CONTEXT, (const char *)&a->ls,
                       sizeof a->ls) ||
            setsockopt(s, IPPROTO_TCP, TCP_NODELAY, (const char *)&one, sizeof one) ||
            ioctlsocket(s, FIONBIO, &nb))
            res = -net_win_err(WSAGetLastError());
        else if (!CreateIoCompletionPort((HANDLE)s, u->port, 0, 0))
            res = -net_win_err((int)GetLastError());
        if (res < 0) closesocket(s);
    } else if (s != INVALID_SOCKET) {
        closesocket(s);
    }
    if (res >= 0) {
        ur_fill(c, a->tag, (int32_t)s, -1, !a->cancel, 0);
        if (!a->cancel) ur_post_accept(u);
        return 1;
    }
    /* A client that left before its accept took it is no error. */
    if (!a->cancel && (res == -net_win_err(WSAECONNRESET) || res == -net_win_err(WSAECONNABORTED))) {
        ur_post_accept(u);
        return 0;
    }
    return ur_fill(c, a->tag, a->cancel ? -UR_ECANCELED : res, -1, 0, 0);
}

/* sock's zero-byte receive completed with res: data has arrived, or the
   receive failed. Reads the data into a free buffer and posts the receive
   again, or ends it. */
static int ur_finish_recv(struct ur *u, struct ur_sock *k, int32_t res, ur_completion *c) {
    uint64_t tag = k->tag;
    if (k->closed || k->cancel || res < 0) {
        int32_t err = res < 0 && !k->cancel && !k->closed ? res : -UR_ECANCELED;
        if (!k->closed) ur_end_read(u, k);
        ur_unref(k);
        return ur_fill(c, tag, err, -1, 0, 0);
    }
    if (u->nfree == 0) {
        ur_end_read(u, k);
        ur_unref(k);
        return ur_fill(c, tag, -UR_ENOBUFS, -1, 0, 0);
    }
    int32_t buf = u->free[--u->nfree];
    int n = recv(k->s, (char *)u->bufs + (size_t)buf * u->buflen, (int)u->buflen, 0);
    int err = n == SOCKET_ERROR ? WSAGetLastError() : 0;
    if (n > 0 || err == WSAEWOULDBLOCK) {
        if (n <= 0) u->free[u->nfree++] = buf;
        ur_post_recv(u, k);
        ur_unref(k);
        return n > 0 ? ur_fill(c, tag, n, buf, 1, 0) : 0;
    }
    u->free[u->nfree++] = buf;
    ur_end_read(u, k);
    ur_unref(k);
    return ur_fill(c, tag, n == 0 ? 0 : -net_win_err(err), -1, 0, 0);
}

static int ur_finish_send(struct ur *u, struct ur_send *s, int32_t res, ur_completion *c) {
    struct ur_sock *k = s->sock;
    if (res >= 0 && s->off + (uint32_t)res < s->len) {
        if (!k->closed) {
            s->off += (uint32_t)res;
            ur_post_send(u, s);
            ur_unref(k);
            return 0;
        }
        res = -UR_ECANCELED;
    }
    ur_fill(c, s->tag, res < 0 ? res : (int32_t)s->len, -1, 0, 1);
    ur_send_free(u, s);
    ur_unref(k);
    return 1;
}

static int ur_finish(struct ur *u, struct ur_req *q, int from_port, ur_completion *c) {
    if (q->kind == UR_ACCEPT) {
        struct ur_accept *a = (struct ur_accept *)q;
        return ur_finish_accept(u, from_port ? ur_result(q, a->ls) : q->err, c);
    }
    if (q->kind == UR_RECV) {
        struct ur_sock *k = (struct ur_sock *)q;
        return ur_finish_recv(u, k, from_port && !k->closed ? ur_result(q, k->s)
                                    : from_port ? -UR_ECANCELED : q->err, c);
    }
    struct ur_send *s = (struct ur_send *)q;
    return ur_finish_send(u, s, from_port && !s->sock->closed ? ur_result(q, s->sock->s)
                                : from_port ? -UR_ECANCELED : q->err, c);
}

/* Waits up to timeout_ms (-1: no limit) for completions, and writes up to
   out.len of them into out. Requests that failed when posted come first.
   Each completion the port gives makes at most one in out, and some make
   none: a short send posted again, or a receive that found no data. */
int32_t ur_wait(int64_t h, ur_completions out, int32_t timeout_ms) {
    struct ur *u = (struct ur *)(intptr_t)h;
    if (u->err) return u->err;
    int32_t n = 0;
    while (n < out.len && u->ready) {
        struct ur_req *q = u->ready;
        u->ready = q->next;
        n += ur_finish(u, q, 0, &out.data[n]);
    }
    if (n == out.len) return n;
    OVERLAPPED_ENTRY ents[UR_MAX_EVENTS];
    ULONG want = out.len - n < UR_MAX_EVENTS ? (ULONG)(out.len - n) : UR_MAX_EVENTS, got = 0;
    DWORD wait = n > 0 || u->ready ? 0 : timeout_ms < 0 ? INFINITE : (DWORD)timeout_ms;
    if (!GetQueuedCompletionStatusEx(u->port, ents, want, &got, wait, FALSE)) {
        DWORD err = GetLastError();
        if (err != WAIT_TIMEOUT) return n > 0 ? n : -net_win_err((int)err);
        got = 0;
    }
    for (ULONG i = 0; i < got; i++)
        n += ur_finish(u, (struct ur_req *)ents[i].lpOverlapped, 1, &out.data[n]);
    return n;
}
