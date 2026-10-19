#!/bin/sh
# Runs HttpArena's h2c profiles (scripts/lib/tools/h2load.sh there) against
# build/server (scripts/build.sh) on Linux, for each loop in LOOPS:
#
#   baseline-h2c  GET /baseline2?a=1&b=1, h2load -p h2c -m 100, at 256, 1,024,
#                 and 4,096 connections
#   json-h2c      HttpArena's seven /json/{count}?m= URIs, -m 32, at 1,024 and
#                 4,096 connections
#
# Each run gets a fresh server, one worker per CPU of SERVER_CPUS and pinned
# to them, serving h2c on PORT + 2, with h2load pinned to CLIENT_CPUS. Prints a
# line per run: h2load's requests per second, its failed and non-2xx
# requests, and the server's peak RSS (VmHWM) in KB.
#
# Settings, from the environment:
#   LOOPS           epoll uring
#   SERVER_CPUS     0-3; CLIENT_CPUS 4-15, and CLIENT_THREADS h2load threads
#                   (one per CPU of CLIENT_CPUS). HttpArena runs 64.
#   CELLS           the profiles and connection counts, as below
#   RUNS 3, DURATION 5 (HttpArena's), WARMUP 2 (seconds), PORT 29380
#   DATASET         json-h2c's data: HttpArena's data/dataset.json, by default
#                   from the checkout bench/httparena.sh keeps in
#                   ~/.cache/goose-http-bench/httparena
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
server=$root/build/server
loops=${LOOPS:-epoll uring}
server_cpus=${SERVER_CPUS:-0-3}
client_cpus=${CLIENT_CPUS:-4-15}
threads=${CLIENT_THREADS:-$(taskset -c "$client_cpus" nproc)}
workers=$(taskset -c "$server_cpus" nproc)
cells=${CELLS:-baseline-h2c:256 baseline-h2c:1024 baseline-h2c:4096 json-h2c:1024 json-h2c:4096}
runs=${RUNS:-3}
duration=${DURATION:-5}
warmup=${WARMUP:-2}
port=${PORT:-29380}
h2c=$((port + 2))
dataset=${DATASET:-$HOME/.cache/goose-http-bench/httparena/data/dataset.json}

[ -x "$server" ] || { echo "h2c.sh: no $server; run scripts/build.sh" >&2; exit 1; }
[ -r "$dataset" ] || {
    echo "h2c.sh: no $dataset; set DATASET to HttpArena's data/dataset.json" >&2
    exit 1
}
ulimit -n 65536
tmp=$(mktemp -d)
pid=
trap 'if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi; rm -rf "$tmp"' EXIT
for uri in "/json/1?m=3" "/json/5?m=7" "/json/10?m=2" "/json/15?m=5" "/json/25?m=4" \
    "/json/40?m=8" "/json/50?m=6"; do
    echo "http://127.0.0.1:$h2c$uri"
done >"$tmp/json-uris.txt"

echo "kernel $(uname -r), $(h2load --version | head -n 1), server CPUs $server_cpus ($workers workers)," \
    "client CPUs $client_cpus ($threads threads), ${duration} s after ${warmup} s, $runs runs"
printf 'loop\tprofile\tconns\trun\trps\tfailed\tnon2xx\tpeak_rss_kb\n'
for loop in $loops; do
    for cell in $cells; do
        profile=${cell%%:*}
        conns=${cell#*:}
        for run in $(seq "$runs"); do
            LOOP=$loop WORKERS=$workers H2C_PORT=$h2c DATASET=$dataset \
                taskset -c "$server_cpus" "$server" http "$port" >"$tmp/server.log" 2>&1 &
            pid=$!
            tries=0
            until nc -z 127.0.0.1 "$h2c" 2>/dev/null; do
                tries=$((tries + 1))
                [ $tries -lt 100 ] || { cat "$tmp/server.log" >&2; exit 1; }
                sleep 0.05
            done
            case $profile in
            baseline-h2c) set -- -m 100 "http://127.0.0.1:$h2c/baseline2?a=1&b=1" ;;
            json-h2c) set -- -m 32 -i "$tmp/json-uris.txt" ;;
            *) echo "h2c.sh: no profile $profile" >&2; exit 2 ;;
            esac
            taskset -c "$client_cpus" h2load -p h2c -t "$threads" -c "$conns" \
                --warm-up-time="$warmup" -D "$duration" "$@" >"$tmp/h2load.txt" 2>&1 || true
            rss=$(awk '/^VmHWM/ {print $2}' "/proc/$pid/status")
            kill "$pid"
            wait "$pid" || true
            pid=
            rps=$(sed -n 's/^finished in .*, \([0-9.]*\) req\/s.*/\1/p' "$tmp/h2load.txt")
            failed=$(sed -n 's/^requests: .* \([0-9]*\) failed.*/\1/p' "$tmp/h2load.txt")
            non2xx=$(awk '/^status codes:/ {print $5 + $7 + $9}' "$tmp/h2load.txt")
            [ -n "$rps" ] || { cat "$tmp/h2load.txt" >&2; exit 1; }
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$loop" "$profile" "$conns" "$run" "$rps" \
                "$failed" "$non2xx" "$rss"
        done
    done
done
