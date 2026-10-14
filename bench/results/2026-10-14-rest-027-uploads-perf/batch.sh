#!/bin/bash
# As root in WSL: perf stat of the REST server on tier D's uploads alone, n
# (main, cb57a0b) against f (findings-46356c2-hot, e047040), the builds of
# 2026-10-14-rest-027-025, as 2026-10-14-desktop-027-uploads-perf measured
# p2: 4 workers on CPUs 0-3, wrk's uploads role on 4-15, 5 s of warm-up and
# then 12 s, perf stat from its second second for 10 s. Two rounds.
set -eu
root=/mnt/c/Users/kait/projects/goose/goose-http
out=$root/bench/results/2026-10-14-rest-027-uploads-perf
port=29383
url=http://127.0.0.1:$port
cd "$root"
wrk_() {
    taskset -c 4-15 env LD_PRELOAD=$root/build/bench/wrk-monotonic.so \
        wrk --timeout 10s --latency -t 1 -c 32 "$@" -s bench/rest/tier-d.lua "$url" -- build/rest uploads
}
: >"$out/perf.txt"
for r in 1 2; do
    for b in n f; do
        REST_DATA=build/rest TIER=d JSON=serialize WORKERS=4 LOOP=uring \
            taskset -c 0-3 build/rest/rest-goose-27$b $port >/dev/null 2>&1 &
        pid=$!
        until nc -z 127.0.0.1 $port 2>/dev/null; do sleep 0.1; done
        wrk_ -d 5 >/dev/null
        wrk_ -d 12 >"$out/wrk-$b-r$r.txt" &
        w=$!
        sleep 1
        echo "-- 27$b round $r" >>"$out/perf.txt"
        perf stat -x, -e instructions:u,cycles:u,L1-icache-load-misses,iTLB-load-misses,branch-misses \
            -p $pid -- sleep 10 2>>"$out/perf.txt"
        wait $w
        grep -E 'requests in|Requests/sec' "$out/wrk-$b-r$r.txt" >>"$out/perf.txt"
        kill $pid; wait $pid 2>/dev/null || true
        while nc -z 127.0.0.1 $port 2>/dev/null; do sleep 0.1; done
    done
done
cat "$out/perf.txt"
