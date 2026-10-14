#!/bin/bash
# User instructions and cycles per request, REST serialized B/C, x vs p, uring.
set -euo pipefail
root=/mnt/c/Users/kait/projects/goose/goose-http
cd "$root"; ulimit -n 65536
port=29380; data=build/rest
for run in 1 2 3; do for t in b c; do for tag in ${TAGS:-cx bp}; do
    REST_DATA=$data TIER=$t JSON=serialize WORKERS=4 LOOP=uring taskset -c 0-3 build/rest/rest-goose-$tag $port >/dev/null 2>&1 &
    pid=$!
    until nc -z 127.0.0.1 $port 2>/dev/null; do sleep 0.1; done
    w() { taskset -c 4-15 env LD_PRELOAD=$root/build/bench/wrk-monotonic.so wrk --timeout 10s -t 8 -c 256 -s bench/rest/tier-$t.lua "$@" http://127.0.0.1:$port -- $data; }
    w -d 5 >/dev/null
    w -d 14 > /root/cnt.wrk &
    wp=$!
    sleep 2
    perf stat -x, -e instructions:u,cycles:u -p $pid -- sleep 10 2> /root/cnt.perf
    wait $wp
    rate=$(awk '/Requests\/sec/ {print $2}' /root/cnt.wrk)
    ins=$(awk -F, '/instructions/ {print $1}' /root/cnt.perf)
    cyc=$(awk -F, '/cycles/ {print $1}' /root/cnt.perf)
    awk -v r=$run -v t=$t -v g=$tag -v q=$rate -v i=$ins -v c=$cyc 'BEGIN { printf "%s\t%s\t%s\t%.0f\t%.0f\t%.0f\n", r, t, g, q, i/(q*10), c/(q*10) }'
    kill $pid; wait $pid 2>/dev/null || true; sleep 1
done; done; done
