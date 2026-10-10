#!/bin/sh
# Counts the instructions each server in build/bench/ spends per request, as
# task 004's profile did: one worker on CPU 0, plaintext pipelined 16 deep at
# 256 connections with TechEmpower's headers, wrk on CPUs 4-15 for 20 s, and
# perf stat on CPU 0 from 5 s in for 10 s, which counts the kernel's network
# work there as well as the server's. Requests are wrk's rate times those
# 10 s. Run as root, for perf.
#
#   bench/instructions.sh SERVER...   (RUNS 3, PORT 29280)
#
# Prints one line per run: instructions per request in all, in user code, and
# cycles per request, and the server's peak RSS (VmHWM) over the whole run.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
bin=$root/build/bench
runs=${RUNS:-3}
port=${PORT:-29280}
accept='Accept: text/plain,text/html;q=0.9,application/xhtml+xml;q=0.9,application/xml;q=0.8,*/*;q=0.7'
tmp=$(mktemp -d)
pid=
trap '[ -z "$pid" ] || kill "$pid" 2>/dev/null; rm -rf "$tmp"' EXIT

printf 'server\trun\treq/s\tinstructions/req\tuser instructions/req\tcycles/req\tpeak_rss_kb\n'
for run in $(seq "$runs"); do
for server in "$@"; do
    case $server in
    goose*) WORKERS=1 taskset -c 0 "$bin/$server" http "$port" >/dev/null 2>&1 & ;;
    *) WORKERS=1 taskset -c 0 "$bin/$server" "$port" >/dev/null 2>&1 & ;;
    esac
    pid=$!
    until nc -z 127.0.0.1 "$port" 2>/dev/null; do sleep 0.1; done
    LD_PRELOAD=$bin/wrk-monotonic.so taskset -c 4-15 wrk -t 8 -c 256 --timeout 8 \
        -H "Host: tfb-server" -H "Connection: keep-alive" -H "$accept" -d 20 \
        -s "$root/scripts/pipeline.lua" "http://127.0.0.1:$port/plaintext" -- 16 >"$tmp/wrk" &
    w=$!
    sleep 5
    perf stat -x, -e instructions,instructions:u,cycles -C 0 -o "$tmp/perf" -- sleep 10
    wait $w
    rss=$(awk '/^VmHWM/ {print $2}' "/proc/$pid/status")
    kill "$pid"
    wait "$pid" 2>/dev/null || true
    pid=
    rps=$(awk '/^Requests\/sec/ {print $2}' "$tmp/wrk")
    awk -F, -v rps="$rps" -v s="$server" -v r="$run" -v rss="$rss" '
        $3 == "instructions" { i = $1 } $3 == "instructions:u" { u = $1 } $3 == "cycles" { c = $1 }
        END { n = rps * 10; printf "%s\t%s\t%.0f\t%.0f\t%.0f\t%.0f\t%s\n", s, r, rps, i / n, u / n, c / n, rss }
    ' "$tmp/perf"
done
done
