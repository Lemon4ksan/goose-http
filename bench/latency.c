/* Latency percentiles from h2load's per-request log, read from stdin as it
   streams: h2load --log-file=FIFO, with this program reading the FIFO.

   Each line is "start_us<TAB>status<TAB>duration_us". h2load measures the
   duration on the monotonic clock, from the request's submission to the end
   of its response. Prints one line, durations in microseconds:

       count N non2xx N p50 N p90 N p99 N p999 N max N

   cc -O2 bench/latency.c -o build/bench/latency */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/* 1 us buckets to 100 ms, then 100 us buckets to 60 s. */
#define FINE 100000
#define COARSE 600000
#define BUCKETS (FINE + COARSE)

static uint64_t hist[BUCKETS];

static size_t bucket(uint64_t us) {
    if (us < FINE) return (size_t)us;
    uint64_t b = FINE + (us - FINE) / 100;
    return b < BUCKETS ? (size_t)b : BUCKETS - 1;
}

static uint64_t value(size_t b) {
    return b < FINE ? b : FINE + (uint64_t)(b - FINE) * 100;
}

static uint64_t percentile(uint64_t count, double p) {
    uint64_t rank = (uint64_t)(p * (double)count);
    if (rank >= count) rank = count - 1;
    uint64_t seen = 0;
    for (size_t b = 0; b < BUCKETS; b++) {
        seen += hist[b];
        if (seen > rank) return value(b);
    }
    return 0;
}

int main(void) {
    static char line[256];
    uint64_t count = 0, non2xx = 0, max = 0;
    while (fgets(line, sizeof line, stdin)) {
        char *p = line, *end;
        strtoull(p, &end, 10);
        if (end == p || *end != '\t') continue;
        p = end + 1;
        long status = strtol(p, &end, 10);
        if (end == p || *end != '\t') continue;
        p = end + 1;
        uint64_t us = strtoull(p, &end, 10);
        if (end == p) continue;
        count++;
        if (status < 200 || status > 299) non2xx++;
        if (us > max) max = us;
        hist[bucket(us)]++;
    }
    if (count == 0) {
        printf("count 0 non2xx 0 p50 0 p90 0 p99 0 p999 0 max 0\n");
        return 1;
    }
    printf("count %llu non2xx %llu p50 %llu p90 %llu p99 %llu p999 %llu max %llu\n",
           (unsigned long long)count, (unsigned long long)non2xx,
           (unsigned long long)percentile(count, 0.50),
           (unsigned long long)percentile(count, 0.90),
           (unsigned long long)percentile(count, 0.99),
           (unsigned long long)percentile(count, 0.999), (unsigned long long)max);
    return 0;
}
