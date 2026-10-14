#!/bin/bash
# Cache, TLB, and branch misses per request, REST serialized C, x vs p, uring.
set -euo pipefail
root=/mnt/c/Users/kait/projects/goose/goose-http
cd "$root"; ulimit -n 65536
port=29380; data=build/rest; t=${T:-c}
ev=instructions:u,cycles:u,branch-misses:u,L1-icache-load-misses:u,L1-dcache-load-misses:u,iTLB-load-misses:u,dTLB-load-misses:u
for run in 1 2; do for tag in ${TAGS:-cx bp}; do
    REST_DATA=$data TIER=$t JSON=serialize WORKERS=4 LOOP=uring taskset -c 0-3 build/rest/rest-goose-$tag $port >/dev/null 2>&1 &
    pid=$!
    until nc -z 127.0.0.1 $port 2>/dev/null; do sleep 0.1; done
    w() { taskset -c 4-15 env LD_PRELOAD=$root/build/bench/wrk-monotonic.so wrk --timeout 10s -t 8 -c 256 -s bench/rest/tier-$t.lua "$@" http://127.0.0.1:$port -- $data; }
    w -d 5 >/dev/null
    w -d 14 > /root/cnt.wrk &
    wp=$!
    sleep 2
    perf stat -x, -e $ev -p $pid -- sleep 10 2> /root/cnt.perf
    wait $wp
    rate=$(awk '/Requests\/sec/ {print $2}' /root/cnt.wrk)
    echo "== run $run tier $t $tag $rate req/s"
    awk -F, -v q="$rate" '$1 ~ /^[0-9]/ { printf "  %-26s %10.1f\n", $3, $1 / (q * 10) } $1 !~ /^[0-9]/ { print "  " $0 }' /root/cnt.perf
    kill $pid; wait $pid 2>/dev/null || true; sleep 1
done; done
