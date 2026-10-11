/* The kernel calls the server makes on Linux, for src/sys.goose. goose build
   compiles this beside the program (the root file's sidecar), so it sees none
   of the generated C: it spells out the layouts it shares with Goose, per
   spec C.2.

   Every function returns what its syscall returns on success and -errno on
   failure. None of them keeps a pointer into Goose memory after it returns. */
#define _GNU_SOURCE
#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdint.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

/* src/sys.goose spells these out as numbers; this keeps them honest on any
   target the C compiles for. */
_Static_assert(EINTR == 4 && EAGAIN == 11 && EPIPE == 32 && ECONNABORTED == 103 &&
               ECONNRESET == 104 && EADDRINUSE == 98 && EMFILE == 24 && ENFILE == 23 &&
               EINVAL == 22,
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
