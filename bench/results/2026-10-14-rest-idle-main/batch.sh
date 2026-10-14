#!/bin/bash
# As root in WSL: idle memory of bench/rest's Goose server on main with tasks
# 025 and 027 merged (1818526), as 2026-10-14-rest-025-idle measured it: each
# tier, JSON way, and worker count started on the epoll loop on CPUs 0-3,
# VmRSS and VmHWM read 3 s after it listened, no request sent, one run each.
set -eu
export GOOSE=/mnt/c/Users/kait/projects/goose/goose/build-linux/goose
root=/mnt/c/Users/kait/projects/goose/goose-http
out=$root/bench/results/2026-10-14-rest-idle-main
port=29385
cd "$root"
rm -rf /root/idle; mkdir -p /root/idle
git archive 1818526 -- '*.goose' '*.build' shim bench/rest | tar -x -C /root/idle
"$GOOSE" build --cc gcc --standalone -o /root/idle/rest /root/idle/bench/rest/goose/rest.goose >/dev/null 2>&1
printf 'tier\tjson\tworkers\tVmRSS KB\tVmHWM KB\n' >"$out/idle.tsv"
for t in a b c; do
    for j in serialize template; do
        for n in 1 2 4; do
            REST_DATA=build/rest TIER=$t JSON=$j WORKERS=$n LOOP=epoll \
                taskset -c 0-3 /root/idle/rest $port >/dev/null 2>&1 &
            pid=$!
            until nc -z 127.0.0.1 $port 2>/dev/null; do sleep 0.1; done
            sleep 3
            rss=$(awk '/^VmRSS/ { print $2 }' /proc/$pid/status)
            hwm=$(awk '/^VmHWM/ { print $2 }' /proc/$pid/status)
            printf '%s\t%s\t%s\t%s\t%s\n' $t $j $n $rss $hwm >>"$out/idle.tsv"
            kill $pid; wait $pid 2>/dev/null || true
            while nc -z 127.0.0.1 $port 2>/dev/null; do sleep 0.1; done
        done
    done
done
rm -rf /root/idle
cat "$out/idle.tsv"
