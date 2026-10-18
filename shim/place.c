/* Placement, for place.goose, on every platform: the cores a process may
   use, a thread's affinity and priority, and SO_INCOMING_CPU. Goose has
   none of them. A set of cores is 16 u64s, a bit a core, as Linux's
   CPU_SETSIZE of 1024.

   Linux pins with sched_setaffinity and lowers a thread with nice 10 and
   SCHED_BATCH. Windows pins within processor group 0, the first 64 cores,
   and lowers with THREAD_PRIORITY_LOWEST. macOS has no affinity: place_cpus
   says so, and a low thread takes the background QoS class.

   Every function returns 0 or more on success and -code on failure, where
   code is a Linux errno value, as the other shims' do. */
#if defined(__linux__)
#define _GNU_SOURCE
#endif
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define PLACE_WORDS 16
#define PLACE_ENOMEM 12
#define PLACE_EMFILE 24
#define PLACE_EINVAL 22
#define PLACE_EOPNOTSUPP 95

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#elif defined(__linux__)
#include <errno.h>
#include <sched.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <unistd.h>
#ifndef SO_INCOMING_CPU
#define SO_INCOMING_CPU 49
#endif
#elif defined(__APPLE__)
#include <errno.h>
#include <pthread.h>
#include <pthread/qos.h>
#include <sys/sysctl.h>
#endif

/* A u64[:] and a u8[:], packed as Goose packs them (spec C.2). */
#pragma pack(push, 1)
typedef struct { uint64_t *data; int64_t len; } place_u64s;
typedef struct { const unsigned char *data; int64_t len; } place_bytes;
#pragma pack(pop)

#if defined(_MSC_VER)
typedef volatile LONG64 place_a64;
#define PLACE_ADD(p) (InterlockedExchangeAdd64((p), 1))
#else
#include <stdatomic.h>
typedef _Atomic int64_t place_a64;
#define PLACE_ADD(p) atomic_fetch_add((p), 1)
#endif

/* The placements place_keep holds, for the process's life: each a copy of a
   Goose Place's bytes, and the next index of each of its 32 roles. An entry
   is written once, before its handle is returned, and a thread gets the
   handle only after that, so reading it needs no lock. */
#define PLACE_KEPT 8
static struct {
    unsigned char *image;
    int64_t len;
    place_a64 counts[32];
} place_kept[PLACE_KEPT];
static place_a64 place_kept_count;

static void place_clear(place_u64s out) {
    for (int64_t i = 0; i < out.len; i++) out.data[i] = 0;
}

#if defined(__linux__)
/* Writes the calling thread's cores into out: the process's when main
   calls it before any thread is pinned. */
static int32_t place_affinity(place_u64s out) {
    cpu_set_t set;
    CPU_ZERO(&set);
    if (sched_getaffinity(0, sizeof set, &set) != 0) return -errno;
    for (int i = 0; i < CPU_SETSIZE && i / 64 < out.len; i++)
        if (CPU_ISSET(i, &set)) out.data[i / 64] |= (uint64_t)1 << (i % 64);
    return 0;
}
#endif

/* Writes the process's cores into out. Returns 1 where threads can be
   pinned, 0 where they can't, or -code where the cores can't be read. */
int32_t place_cpus(place_u64s out) {
    place_clear(out);
#ifdef _WIN32
    DWORD_PTR proc = 0, sys = 0;
    if (!GetProcessAffinityMask(GetCurrentProcess(), &proc, &sys)) return -PLACE_EINVAL;
    if (out.len > 0) out.data[0] = (uint64_t)proc;
    return 1;
#elif defined(__linux__)
    int32_t e = place_affinity(out);
    return e < 0 ? e : 1;
#elif defined(__APPLE__)
    int n = 0;
    size_t size = sizeof n;
    if (sysctlbyname("hw.logicalcpu", &n, &size, NULL, 0) != 0 || n < 1) n = 1;
    for (int i = 0; i < n && i / 64 < out.len; i++) out.data[i / 64] |= (uint64_t)1 << (i % 64);
    return 0;
#else
    return 0;
#endif
}

/* Writes the calling thread's cores into out. */
int32_t place_current(place_u64s out) {
    place_clear(out);
#if defined(__linux__)
    return place_affinity(out);
#else
    return place_cpus(out) < 0 ? -PLACE_EINVAL : 0;
#endif
}

/* Pins the calling thread to cores. */
int32_t place_self(place_u64s cores) {
#ifdef _WIN32
    for (int64_t i = 1; i < cores.len; i++)
        if (cores.data[i]) return -PLACE_EINVAL;
    if (cores.len < 1 || !cores.data[0]) return -PLACE_EINVAL;
    return SetThreadAffinityMask(GetCurrentThread(), (DWORD_PTR)cores.data[0]) ? 0 : -PLACE_EINVAL;
#elif defined(__linux__)
    cpu_set_t set;
    CPU_ZERO(&set);
    for (int i = 0; i < CPU_SETSIZE && i / 64 < cores.len; i++)
        if (cores.data[i / 64] >> (i % 64) & 1) CPU_SET(i, &set);
    return sched_setaffinity(0, sizeof set, &set) == 0 ? 0 : -errno;
#else
    (void)cores;
    return -PLACE_EOPNOTSUPP;
#endif
}

/* Lowers the calling thread's priority, for work that may wait behind the
   rest. */
int32_t place_low(void) {
#ifdef _WIN32
    return SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_LOWEST) ? 0 : -PLACE_EINVAL;
#elif defined(__linux__)
    struct sched_param param;
    memset(&param, 0, sizeof param);
    if (sched_setscheduler(0, SCHED_BATCH, &param) != 0) return -errno;
    /* A thread's nice value is its own on Linux, set through its thread id. */
    if (setpriority(PRIO_PROCESS, (id_t)syscall(SYS_gettid), 10) != 0) return -errno;
    return 0;
#elif defined(__APPLE__)
    int e = pthread_set_qos_class_self_np(QOS_CLASS_BACKGROUND, 0);
    return e == 0 ? 0 : -e;
#else
    return -PLACE_EOPNOTSUPP;
#endif
}

/* Keeps a copy of image, a Place's bytes, and returns its handle, from 1. */
int32_t place_keep(place_bytes image) {
    if (image.len <= 0) return -PLACE_EINVAL;
    int64_t n = PLACE_ADD(&place_kept_count);
    if (n >= PLACE_KEPT) return -PLACE_EMFILE;
    unsigned char *copy = malloc((size_t)image.len);
    if (!copy) return -PLACE_ENOMEM;
    memcpy(copy, image.data, (size_t)image.len);
    place_kept[n].image = copy;
    place_kept[n].len = image.len;
    return (int32_t)n + 1;
}

/* Copies the Place that handle id holds into out, a Place of the program
   that kept it, so of the same size. */
int32_t place_get(int32_t id, void *out) {
    if (id < 1 || id > PLACE_KEPT || !place_kept[id - 1].image) return -PLACE_EINVAL;
    memcpy(out, place_kept[id - 1].image, (size_t)place_kept[id - 1].len);
    return 0;
}

/* The next index of role in the placement of handle id, from 0: threads that
   take their seats as they start, such as workers, each get their own. */
int64_t place_next(int32_t id, int32_t role) {
    if (id < 1 || id > PLACE_KEPT || role < 0 || role >= 32) return 0;
    return PLACE_ADD(&place_kept[id - 1].counts[role]);
}

/* Has the kernel give listener fd the connections whose packets cpu
   processed, among the listeners sharing its port. */
int32_t place_incoming(int32_t fd, int32_t cpu) {
#if defined(__linux__)
    return setsockopt(fd, SOL_SOCKET, SO_INCOMING_CPU, &cpu, sizeof cpu) == 0 ? 0 : -errno;
#else
    (void)fd;
    (void)cpu;
    return -PLACE_EOPNOTSUPP;
#endif
}
