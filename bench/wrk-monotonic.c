/* Preloaded into wrk by bench/run.sh: gettimeofday answers from the
   monotonic clock.

   wrk 4.1.0 times requests and runs its event loop's timers on
   gettimeofday. WSL2 steps the wall clock back by about a millisecond every
   30 s or so, and wrk then counts each request in flight across the step as
   a timeout and drops its latency. wrk uses the time only for differences,
   so a monotonic clock gives it the same numbers without the steps.

   cc -O2 -shared -fPIC bench/wrk-monotonic.c -o build/bench/wrk-monotonic.so */
#define _GNU_SOURCE
#include <sys/time.h>
#include <time.h>

int gettimeofday(struct timeval *restrict tv, void *restrict tz) {
    (void)tz;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    tv->tv_sec = ts.tv_sec;
    tv->tv_usec = ts.tv_nsec / 1000;
    return 0;
}
