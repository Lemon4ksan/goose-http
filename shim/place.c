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
typedef struct { const char *data; int64_t len; } place_bytes;
#pragma pack(pop)

#if defined(_MSC_VER)
typedef volatile LONG64 place_a64;
#define PLACE_ADD(p) (InterlockedExchangeAdd64((p), 1))
#else
#include <stdatomic.h>
typedef _Atomic int64_t place_a64;
#define PLACE_ADD(p) atomic_fetch_add((p), 1)
#endif

static place_a64 place_counts[32];
static place_a64 place_warned[32];

static void place_clear(place_u64s out) {
    for (int64_t i = 0; i < out.len; i++) out.data[i] = 0;
}

/* Writes the process's cores into out. Returns 1 where threads can be
   pinned, 0 where they can't. */
int32_t place_cpus(place_u64s out) {
    place_clear(out);
#ifdef _WIN32
    DWORD_PTR proc = 0, sys = 0;
    if (!GetProcessAffinityMask(GetCurrentProcess(), &proc, &sys)) return -PLACE_EINVAL;
    if (out.len > 0) out.data[0] = (uint64_t)proc;
    return 1;
#elif defined(__linux__)
    cpu_set_t set;
    CPU_ZERO(&set);
    if (sched_getaffinity(0, sizeof set, &set) != 0) return -errno;
    for (int i = 0; i < CPU_SETSIZE && i / 64 < out.len; i++)
        if (CPU_ISSET(i, &set)) out.data[i / 64] |= (uint64_t)1 << (i % 64);
    return 1;
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
    cpu_set_t set;
    CPU_ZERO(&set);
    if (sched_getaffinity(0, sizeof set, &set) != 0) return -errno;
    for (int i = 0; i < CPU_SETSIZE && i / 64 < out.len; i++)
        if (CPU_ISSET(i, &set)) out.data[i / 64] |= (uint64_t)1 << (i % 64);
    return 0;
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

/* The next index of role, from 0: threads that take their seats as they
   start, such as workers, each get their own. */
int64_t place_next(int32_t role) {
    if (role < 0 || role >= 32) return 0;
    return PLACE_ADD(&place_counts[role]);
}

/* 1 the first time for what, so that a thread's failure warns once. */
int32_t place_once(int32_t what) {
    if (what < 0 || what >= 32) return 0;
    return PLACE_ADD(&place_warned[what]) == 0;
}

/* Sets the environment variable name to value, for settings.goose's .env
   loader, before any thread but main runs. */
int32_t place_setenv(place_bytes name, place_bytes value) {
    char n[256], v[4096];
    if (name.len <= 0 || name.len >= (int64_t)sizeof n || value.len < 0 || value.len >= (int64_t)sizeof v)
        return -PLACE_EINVAL;
    memcpy(n, name.data, (size_t)name.len);
    n[name.len] = 0;
    memcpy(v, value.data, (size_t)value.len);
    v[value.len] = 0;
#ifdef _WIN32
    return _putenv_s(n, v) == 0 ? 0 : -PLACE_EINVAL;
#else
    return setenv(n, v, 1) == 0 ? 0 : -PLACE_EINVAL;
#endif
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
