/* The kernel calls the server makes on macOS, for src/sys.goose: the
   functions of shim/net.c, with the same arguments and results, over kqueue
   instead of epoll. goose build compiles this beside the program (the root
   file's sidecar), so it sees none of the generated C: it spells out the
   layouts it shares with Goose, per spec C.2.

   Every function returns what its syscall returns on success and -code on
   failure, where code is errno translated to its Linux number (net_err), the
   values src/sys.goose names. None of them keeps a pointer into Goose memory
   after it returns. */
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <sys/event.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

/* Unix V7's numbers, which macOS and Linux share up to 34. */
_Static_assert(EINTR == 4 && ENFILE == 23 && EMFILE == 24 && EPIPE == 32 && ERANGE == 34,
               "errno values below 35 differ from Linux's");

/* Linux's numbers for macOS's errno values from 35 up. 0 is an errno with no
   Linux counterpart. */
static const int16_t net_linux_errno[] = {
    [EAGAIN] = 11, [EINPROGRESS] = 115, [EALREADY] = 114, [ENOTSOCK] = 88,
    [EDESTADDRREQ] = 89, [EMSGSIZE] = 90, [EPROTOTYPE] = 91, [ENOPROTOOPT] = 92,
    [EPROTONOSUPPORT] = 93, [ESOCKTNOSUPPORT] = 94, [ENOTSUP] = 95, [EPFNOSUPPORT] = 96,
    [EAFNOSUPPORT] = 97, [EADDRINUSE] = 98, [EADDRNOTAVAIL] = 99, [ENETDOWN] = 100,
    [ENETUNREACH] = 101, [ENETRESET] = 102, [ECONNABORTED] = 103, [ECONNRESET] = 104,
    [ENOBUFS] = 105, [EISCONN] = 106, [ENOTCONN] = 107, [ESHUTDOWN] = 108,
    [ETOOMANYREFS] = 109, [ETIMEDOUT] = 110, [ECONNREFUSED] = 111, [ELOOP] = 40,
    [ENAMETOOLONG] = 36, [EHOSTDOWN] = 112, [EHOSTUNREACH] = 113, [ENOTEMPTY] = 39,
    [EUSERS] = 87, [EDQUOT] = 122, [ESTALE] = 116, [EREMOTE] = 66, [ENOLCK] = 37,
    [ENOSYS] = 38, [EOVERFLOW] = 75, [ECANCELED] = 125, [EIDRM] = 43, [ENOMSG] = 42,
    [EILSEQ] = 84, [ENOATTR] = 61, [EBADMSG] = 74, [EMULTIHOP] = 72, [ENODATA] = 61,
    [ENOLINK] = 67, [ENOSR] = 63, [ENOSTR] = 60, [EPROTO] = 71, [ETIME] = 62,
    [EOPNOTSUPP] = 95, [ENOTRECOVERABLE] = 131, [EOWNERDEAD] = 130,
};
#define NET_ERRNO_COUNT (int)(sizeof net_linux_errno / sizeof net_linux_errno[0])
/* An errno with no Linux number becomes this plus its own, clear of Linux's. */
#define NET_UNMAPPED 1000

static int net_err(int e) {
    if (e < 35) return e;
    if (e < NET_ERRNO_COUNT && net_linux_errno[e]) return net_linux_errno[e];
    return NET_UNMAPPED + e;
}

/* net_err's inverse, for strerror. ENOATTR and ENODATA share 61, and ENOTSUP
   and EOPNOTSUPP 95; either one's text will do. */
static int net_native(int code) {
    if (code < 35) return code;
    if (code >= NET_UNMAPPED) return code - NET_UNMAPPED;
    for (int e = 35; e < NET_ERRNO_COUNT; e++)
        if (net_linux_errno[e] == code) return e;
    return code;
}

/* src/sys.goose spells these out as numbers, as Linux has them; this shim
   translates them, so only the shutdown how has to match. */
_Static_assert(SHUT_WR == 1, "shutdown's how differs from src/sys.goose");

/* A u8[:]: a pointer and a length, passed by value. */
typedef struct { uint8_t *data; int64_t len; } net_bytes;

/* sys::Event, packed as Goose packs a struct, and a slice of it. */
typedef struct __attribute__((packed)) { uint32_t events; uint64_t tag; } net_event;
_Static_assert(sizeof(net_event) == 12, "net_event is not packed");
typedef struct { net_event *data; int64_t len; } net_events;

/* Flags of net_listen and net_accept; sys::NONBLOCK and sys::REUSEPORT. */
#define NET_NONBLOCK 1
#define NET_REUSEPORT 2

/* sys::IN, OUT, ERR, HUP, RDHUP, and ET: epoll's bits, as src/sys.goose
   names them. */
#define NET_IN 0x001u
#define NET_OUT 0x004u
#define NET_ERR 0x008u
#define NET_HUP 0x010u
#define NET_RDHUP 0x2000u
#define NET_ET 0x80000000u
/* sys::CTL_ADD, CTL_DEL, and CTL_MOD. */
#define NET_CTL_ADD 1
#define NET_CTL_DEL 2
#define NET_CTL_MOD 3

/* net_epoll_wait reads this many kernel events per call at most. */
#define NET_MAX_EVENTS 1024

static int32_t net_open_listener(int64_t ip, int32_t port, int32_t backlog, int32_t flags) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -net_err(errno);
    int one = 1;
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    addr.sin_addr.s_addr = htonl(ip < 0 ? INADDR_ANY : (uint32_t)ip);
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) < 0 ||
        (flags & NET_NONBLOCK && fcntl(fd, F_SETFL, O_NONBLOCK) < 0) ||
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one) < 0 ||
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one) < 0 ||
        bind(fd, (struct sockaddr *)&addr, sizeof addr) < 0 ||
        listen(fd, backlog) < 0) {
        int err = errno;
        close(fd);
        return -net_err(err);
    }
    return fd;
}

/* macOS's SO_REUSEPORT doesn't spread connections across listeners: the
   last one bound gets them all. So the workers share one listener per port,
   which every worker's kqueue watches, and each gets its own fd for it. This
   table is the only state the shim keeps between calls. */
#define NET_MAX_SHARED 16
static pthread_mutex_t net_shared_lock = PTHREAD_MUTEX_INITIALIZER;
static struct { int64_t ip; int32_t port, fd; } net_shared[NET_MAX_SHARED];
static int net_shared_count;

/* A TCP listener on IPv4 address ip, in host byte order, or on every address
   for -1. macOS copies TCP_NODELAY and O_NONBLOCK from the listener to each
   accepted socket. With NET_REUSEPORT, every call on an address and port
   returns an fd for the same listener, so its connections are accepted by
   whichever worker takes them first. */
int32_t net_listen(int64_t ip, int32_t port, int32_t backlog, int32_t flags) {
    if (!(flags & NET_REUSEPORT)) return net_open_listener(ip, port, backlog, flags);
    pthread_mutex_lock(&net_shared_lock);
    int32_t r = 0;
    int i = 0;
    while (i < net_shared_count && (net_shared[i].port != port || net_shared[i].ip != ip)) i++;
    if (i < net_shared_count) {
        int fd = fcntl(net_shared[i].fd, F_DUPFD_CLOEXEC, 0);
        r = fd < 0 ? -net_err(errno) : fd;
    } else if (net_shared_count == NET_MAX_SHARED) {
        r = -net_err(ENOBUFS);
    } else {
        r = net_open_listener(ip, port, backlog, flags);
        if (r >= 0) {
            net_shared[net_shared_count].ip = ip;
            net_shared[net_shared_count].port = port;
            net_shared[net_shared_count].fd = r;
            net_shared_count++;
        }
    }
    pthread_mutex_unlock(&net_shared_lock);
    return r;
}

/* macOS drops a connection whose accept fails with EMFILE, where Linux leaves
   it in the backlog. So this first checks that an fd is free, and fails
   without accepting when none is: the client keeps its place in the backlog.
   Another thread can take the fd between the check and the accept. */
int32_t net_accept(int32_t fd, int32_t flags) {
    int spare = fcntl(fd, F_DUPFD_CLOEXEC, 0);
    if (spare < 0) return -net_err(errno);
    close(spare);
    int r = accept(fd, NULL, NULL);
    if (r < 0) return -net_err(errno);
    int nb = (flags & NET_NONBLOCK) != 0;
    if (fcntl(r, F_SETFD, FD_CLOEXEC) < 0 || ioctl(r, FIONBIO, &nb) < 0) {
        int err = errno;
        close(r);
        return -net_err(err);
    }
    return r;
}

int64_t net_recv(int32_t fd, net_bytes buf) {
    ssize_t r = recv(fd, buf.data, (size_t)buf.len, 0);
    return r < 0 ? -net_err(errno) : r;
}

/* MSG_NOSIGNAL turns a write to a closed connection into -EPIPE instead of a
   SIGPIPE that would end the process. */
int64_t net_send(int32_t fd, net_bytes data) {
    ssize_t r = send(fd, data.data, (size_t)data.len, MSG_NOSIGNAL);
    return r < 0 ? -net_err(errno) : r;
}

int32_t net_shutdown(int32_t fd, int32_t how) {
    return shutdown(fd, how) < 0 ? -net_err(errno) : 0;
}

int32_t net_close(int32_t fd) {
    return close(fd) < 0 ? -net_err(errno) : 0;
}

int32_t net_epoll_create(void) {
    int r = kqueue();
    if (r < 0) return -net_err(errno);
    if (fcntl(r, F_SETFD, FD_CLOEXEC) < 0) {
        int err = errno;
        close(r);
        return -net_err(err);
    }
    return r;
}

/* An epoll registration as kevent changes: IN is EVFILT_READ, OUT is
   EVFILT_WRITE, and ET is EV_CLEAR on both. kqueue reports a peer's close
   unasked, so RDHUP needs no filter. A filter not asked for is deleted, and
   deleting one that isn't registered is no error. */
int32_t net_epoll_ctl(int32_t ep, int32_t op, int32_t fd, uint32_t events, uint64_t tag) {
    uint16_t add = EV_ADD | EV_RECEIPT | (events & NET_ET ? EV_CLEAR : 0);
    uint16_t del = EV_DELETE | EV_RECEIPT;
    struct kevent ch[2], res[2];
    if (op != NET_CTL_ADD && op != NET_CTL_DEL && op != NET_CTL_MOD) return -net_err(EINVAL);
    int n = 0;
    if (op == NET_CTL_DEL || events & NET_IN || op == NET_CTL_MOD)
        EV_SET(&ch[n++], fd, EVFILT_READ,
               op != NET_CTL_DEL && events & NET_IN ? add : del, 0, 0, (void *)tag);
    if (op == NET_CTL_DEL || events & NET_OUT || op == NET_CTL_MOD)
        EV_SET(&ch[n++], fd, EVFILT_WRITE,
               op != NET_CTL_DEL && events & NET_OUT ? add : del, 0, 0, (void *)tag);
    if (n == 0) return 0;
    int got = kevent(ep, ch, n, res, n, NULL);
    if (got < 0) return -net_err(errno);
    for (int i = 0; i < got; i++) {
        int err = res[i].flags & EV_ERROR ? (int)res[i].data : 0;
        int deleting = res[i].filter == ch[0].filter ? ch[0].flags & EV_DELETE
                                                     : ch[n - 1].flags & EV_DELETE;
        if (err && !(err == ENOENT && deleting)) return -net_err(err);
    }
    return 0;
}

/* struct kevent is 32 bytes on arm64, so the kernel writes into a local
   array of it and the events are copied out into sys::Event. kqueue reports
   each filter apart, and epoll one event per fd holding both, so the events
   of one fd are merged: the loop frees a connection's slot on the event that
   closes it, and a second event for it in the same batch would find the slot
   freed. EV_EOF is RDHUP on the read filter and HUP on the write filter, and
   its fflags, when set, is the socket's error. */
int32_t net_epoll_wait(int32_t ep, net_events out, int32_t timeout_ms) {
    struct kevent kev[NET_MAX_EVENTS];
    uintptr_t fds[NET_MAX_EVENTS];
    struct timespec ts, *tp = NULL;
    if (timeout_ms >= 0) {
        ts.tv_sec = timeout_ms / 1000;
        ts.tv_nsec = (long)(timeout_ms % 1000) * 1000000;
        tp = &ts;
    }
    int max = out.len < NET_MAX_EVENTS ? (int)out.len : NET_MAX_EVENTS;
    int n = kevent(ep, NULL, 0, kev, max, tp);
    if (n < 0) return -net_err(errno);
    int m = 0;
    for (int i = 0; i < n; i++) {
        uint32_t bits;
        if (kev[i].filter == EVFILT_READ) bits = NET_IN | (kev[i].flags & EV_EOF ? NET_RDHUP : 0);
        else if (kev[i].filter == EVFILT_WRITE) bits = NET_OUT | (kev[i].flags & EV_EOF ? NET_HUP : 0);
        else continue;
        if (kev[i].flags & EV_EOF && kev[i].fflags) bits |= NET_ERR;
        int j = m;
        while (j > 0 && fds[j - 1] != kev[i].ident) j--;
        if (j > 0) {
            out.data[j - 1].events |= bits;
        } else {
            fds[m] = kev[i].ident;
            out.data[m].events = bits;
            out.data[m].tag = (uint64_t)kev[i].udata;
            m++;
        }
    }
    return m;
}

/* CLOCK_MONOTONIC_RAW_APPROX is the value cached at the last context switch,
   up to about 2 ms old, read without the hardware counter, as Linux's coarse
   clocks are. macOS reads CLOCK_REALTIME without a syscall. std's clock_ns
   and time_ns are the precise ones. */
int64_t net_clock_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC_RAW_APPROX, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int64_t net_time_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (int64_t)ts.tv_sec;
}

/* Writes the C library's text for an error code into out, cut to fit, and
   returns its length. */
int64_t net_strerror(int64_t err, net_bytes out) {
    const char *s = strerror(net_native((int)err));
    size_t n = strlen(s);
    if (n > (size_t)out.len) n = (size_t)out.len;
    memcpy(out.data, s, n);
    return (int64_t)n;
}
