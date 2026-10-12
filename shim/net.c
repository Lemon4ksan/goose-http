/* The kernel calls the server makes on Linux, for src/sys.goose. goose build
   compiles this beside the program (the root file's sidecar), so it sees none
   of the generated C: it spells out the layouts it shares with Goose, per
   spec C.2.

   Every function returns what its syscall returns on success and -errno on
   failure. None of them keeps a pointer into Goose memory after it returns. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

/* src/sys.goose spells these out as numbers; this keeps them honest on any
   target the C compiles for. */
_Static_assert(EINTR == 4 && EAGAIN == 11 && EPIPE == 32 && ECONNABORTED == 103 &&
               ECONNRESET == 104 && EADDRINUSE == 98 && EMFILE == 24 && ENFILE == 23 &&
               EINVAL == 22 && ENOENT == 2 && EACCES == 13 && ENOTDIR == 20 && EISDIR == 21 &&
               ENAMETOOLONG == 36,
               "errno values differ from src/sys.goose");
_Static_assert(EPOLLIN == 0x001 && EPOLLOUT == 0x004 && EPOLLERR == 0x008 &&
               EPOLLHUP == 0x010 && EPOLLRDHUP == 0x2000 && EPOLLET == 1u << 31,
               "epoll event bits differ from src/sys.goose");
_Static_assert(EPOLL_CTL_ADD == 1 && EPOLL_CTL_DEL == 2 && EPOLL_CTL_MOD == 3,
               "epoll_ctl ops differ from src/sys.goose");
_Static_assert(SHUT_WR == 1, "shutdown's how differs from src/sys.goose");

/* A u8[:]: a pointer and a length, passed by value. */
typedef struct { uint8_t *data; int64_t len; } net_bytes;

/* sys::PollEvent, packed as Goose packs a struct, and a slice of it. */
typedef struct __attribute__((packed)) { uint32_t events; uint64_t tag; } net_event;
_Static_assert(sizeof(net_event) == 12, "net_event is not packed");
typedef struct { net_event *data; int64_t len; } net_events;

/* Flags of net_listen and net_accept; sys::NONBLOCK and sys::REUSEPORT. */
#define NET_NONBLOCK 1
#define NET_REUSEPORT 2

/* epoll_wait converts this many kernel events per call at most. */
#define NET_MAX_EVENTS 1024

/* A TCP listener on IPv4 address ip, in host byte order, or on every address
   for -1. Linux copies TCP_NODELAY from the listener to each accepted socket,
   so accept needs no setsockopt. */
int32_t net_listen(int64_t ip, int32_t port, int32_t backlog, int32_t flags) {
    int fd = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC |
                    (flags & NET_NONBLOCK ? SOCK_NONBLOCK : 0), 0);
    if (fd < 0) return -errno;
    int one = 1;
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    addr.sin_addr.s_addr = htonl(ip < 0 ? INADDR_ANY : (uint32_t)ip);
    if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one) < 0 ||
        (flags & NET_REUSEPORT &&
         setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, sizeof one) < 0) ||
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one) < 0 ||
        bind(fd, (struct sockaddr *)&addr, sizeof addr) < 0 ||
        listen(fd, backlog) < 0) {
        int err = errno;
        close(fd);
        return -err;
    }
    return fd;
}

int32_t net_accept(int32_t fd, int32_t flags) {
    int r = accept4(fd, NULL, NULL,
                    SOCK_CLOEXEC | (flags & NET_NONBLOCK ? SOCK_NONBLOCK : 0));
    return r < 0 ? -errno : r;
}

int64_t net_recv(int32_t fd, net_bytes buf) {
    ssize_t r = recv(fd, buf.data, (size_t)buf.len, 0);
    return r < 0 ? -errno : r;
}

/* MSG_NOSIGNAL turns a write to a closed connection into -EPIPE instead of a
   SIGPIPE that would end the process. */
int64_t net_send(int32_t fd, net_bytes data) {
    ssize_t r = send(fd, data.data, (size_t)data.len, MSG_NOSIGNAL);
    return r < 0 ? -errno : r;
}

int32_t net_shutdown(int32_t fd, int32_t how) {
    return shutdown(fd, how) < 0 ? -errno : 0;
}

int32_t net_close(int32_t fd) {
    return close(fd) < 0 ? -errno : 0;
}

int32_t net_epoll_create(void) {
    int r = epoll_create1(EPOLL_CLOEXEC);
    return r < 0 ? -errno : r;
}

int32_t net_epoll_ctl(int32_t ep, int32_t op, int32_t fd, uint32_t events, uint64_t tag) {
    struct epoll_event ev;
    ev.events = events;
    ev.data.u64 = tag;
    return epoll_ctl(ep, op, fd, &ev) < 0 ? -errno : 0;
}

/* The kernel's struct epoll_event is packed on x86-64 and padded to 16 bytes
   on arm64, so the kernel writes into a local array of it and the events are
   copied out into sys::PollEvent, whose layout is the same everywhere. */
int32_t net_epoll_wait(int32_t ep, net_events out, int32_t timeout_ms) {
    struct epoll_event kev[NET_MAX_EVENTS];
    int max = out.len < NET_MAX_EVENTS ? (int)out.len : NET_MAX_EVENTS;
    int n = epoll_wait(ep, kev, max, timeout_ms);
    if (n < 0) return -errno;
    for (int i = 0; i < n; i++) {
        out.data[i].events = kev[i].events;
        out.data[i].tag = kev[i].data.u64;
    }
    return n;
}

/* The coarse clocks return the time of the last scheduler tick, 1 to 4 ms
   old by the kernel's HZ, without reading the hardware counter. std's
   clock_ns and time_ns are the precise ones. */
int64_t net_clock_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC_COARSE, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int64_t net_time_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME_COARSE, &ts);
    return (int64_t)ts.tv_sec;
}

void net_worker_start(void) {}

int32_t net_default_workers(void) {
    return 0;
}

/* Writes the C library's text for an errno value into out, cut to fit, and
   returns its length. */
int64_t net_strerror(int64_t err, net_bytes out) {
    const char *s = strerror((int)err);
    size_t n = strlen(s);
    if (n > (size_t)out.len) n = (size_t)out.len;
    memcpy(out.data, s, n);
    return (int64_t)n;
}

/* How many times net_stop has run in the process. A loop reads it at its
   start, and stops once it has moved on. An atomic counter, and not a flag, so
   that a loop started after a stop runs. A signal handler may call net_stop:
   a lock-free atomic add is async-signal-safe. */
static _Atomic int64_t net_stop_count;

void net_stop(void) {
    atomic_fetch_add_explicit(&net_stop_count, 1, memory_order_relaxed);
}

int64_t net_stops(void) {
    return atomic_load_explicit(&net_stop_count, memory_order_relaxed);
}

static void net_on_signal(int sig) {
    (void)sig;
    net_stop();
}

/* Makes SIGTERM and SIGINT call net_stop instead of ending the process. */
int32_t net_stop_on_signals(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = net_on_signal;
    sigemptyset(&sa.sa_mask);
    if (sigaction(SIGTERM, &sa, NULL) < 0 || sigaction(SIGINT, &sa, NULL) < 0) return -errno;
    return 0;
}

#define ERR(e) (e)

/* An i64[:]. */
typedef struct { int64_t *data; int64_t len; } net_i64s;

/* Opens path, which holds no NUL, for reading: a regular file, else -EISDIR
   for a directory and -EINVAL for anything else. O_NONBLOCK keeps a FIFO from
   blocking the open; a regular file's reads ignore it. Writes its size to
   info[0] and its modification time, in seconds since the epoch, to info[1]. */
int64_t net_file_open(net_bytes path, net_i64s info) {
    char p[4096];
    if (path.len >= (int64_t)sizeof p) return -ERR(ENAMETOOLONG);
    if (memchr(path.data, 0, (size_t)path.len)) return -ERR(ENOENT);
    memcpy(p, path.data, (size_t)path.len);
    p[path.len] = 0;
    int fd = open(p, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0) return -ERR(errno);
    struct stat st;
    if (fstat(fd, &st) < 0) {
        int e = errno;
        close(fd);
        return -ERR(e);
    }
    if (!S_ISREG(st.st_mode)) {
        close(fd);
        return S_ISDIR(st.st_mode) ? -ERR(EISDIR) : -ERR(EINVAL);
    }
    if (info.len >= 2) {
        info.data[0] = (int64_t)st.st_size;
        info.data[1] = (int64_t)st.st_mtime;
    }
    return fd;
}

/* Reads buf.len bytes of fd at off into buf, fewer only at the file's end.
   Returns how many, or -code. */
int64_t net_file_read(int64_t fd, net_bytes buf, int64_t off) {
    int64_t got = 0;
    while (got < buf.len) {
        ssize_t n = pread((int)fd, buf.data + got, (size_t)(buf.len - got), (off_t)(off + got));
        if (n < 0) {
            if (errno == EINTR) continue;
            return -ERR(errno);
        }
        if (n == 0) break;
        got += n;
    }
    return got;
}

void net_file_close(int64_t fd) {
    close((int)fd);
}
