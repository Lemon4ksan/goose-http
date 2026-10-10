#!/bin/sh
# Runs the benchmark matrix of task 004 against the servers bench/build.sh
# built, and writes the raw results to bench/results/<date>/.
#
# Each cell (server, worker count, test, run) gets a fresh server, pinned to
# SERVER_CPUS, with the load generators pinned to CLIENT_CPUS:
#
#   1. wrk for WARMUP seconds, discarded.
#   2. wrk for DURATION seconds: requests per second, errors, and the CPU time
#      of the server and of wrk. wrk runs with bench/wrk-monotonic.so, and
#      bench/clockstep.py logs any step of the wall clock during the run.
#   3. h2load for DURATION seconds after a 2 s warm-up: latency, from its
#      per-request log, summarized by bench/latency.c as it streams.
#   4. The server's peak RSS (VmHWM), over the whole cell.
#
# Plaintext is pipelined 16 deep, JSON isn't, as TechEmpower runs them, with
# TechEmpower's request headers. The runs go round by round, so each server's
# runs spread over the whole session. Each round's order is the same. The
# summary compares each server with the first in SERVERS.
#
# Settings, from the environment:
#   SERVERS       goose may-minihttp hyper tokio dusty vanilla-epoll. Any name
#                 starting with goose is a build of the Goose server, run with
#                 its mode. bench/build.sh also builds odin-http, which task
#                 009 left out: hyper's rate in JSON, 5-8% of Goose's in
#                 plaintext.
#   WORKER_COUNTS 1 and the number of SERVER_CPUS ("1 4")
#   SERVER_CPUS   0-3: cores 0 and 1 with both SMT threads. One worker gets
#                 CPU 0 alone.
#   CLIENT_CPUS   4-15, and CLIENT_THREADS (8) threads for wrk and h2load.
#                 wrk spends about 1.4 times the server's CPU time per
#                 request, so the client gets three times the CPUs: with 8
#                 CPUs each, wrk was the bottleneck. 8 threads divide every
#                 connection count; wrk gives each thread conns / threads.
#   TESTS         plaintext:256 plaintext:1024 plaintext:4096 json:256 json:1024
#   LATENCY       1; 0 skips step 3, leaving the latency columns empty
#   RUNS 3, DURATION 15, WARMUP 5, PORT 29280, OUT bench/results/<date>
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
bin=$root/build/bench
servers=${SERVERS:-goose may-minihttp hyper tokio dusty vanilla-epoll}
server_cpus=${SERVER_CPUS:-0-3}
client_cpus=${CLIENT_CPUS:-4-15}
threads=${CLIENT_THREADS:-8}
ncpus=$(taskset -c "$server_cpus" nproc)
worker_counts=${WORKER_COUNTS:-1 $ncpus}
tests=${TESTS:-plaintext:256 plaintext:1024 plaintext:4096 json:256 json:1024}
runs=${RUNS:-3}
duration=${DURATION:-15}
warmup=${WARMUP:-5}
latency=${LATENCY:-1}
port=${PORT:-29280}
out=${OUT:-$root/bench/results/$(date -u +%Y-%m-%dT%H%M)}
url=http://127.0.0.1:$port
hz=$(getconf CLK_TCK)

accept_plain='Accept: text/plain,text/html;q=0.9,application/xhtml+xml;q=0.9,application/xml;q=0.8,*/*;q=0.7'
accept_json='Accept: application/json,text/html;q=0.9,application/xhtml+xml;q=0.9,application/xml;q=0.8,*/*;q=0.7'
# wrk drops a header without a space after its colon.
host='Host: tfb-server'
conn='Connection: keep-alive'

for b in $servers wrk-monotonic.so latency; do
    [ -e "$bin/$b" ] || { echo "bench/run.sh: no $bin/$b; run bench/build.sh"; exit 1; }
done
ulimit -n 65536
mkdir -p "$out"
pid=
mon=
# The FIFO h2load logs into lives on the Linux file system: mkfifo fails on
# /mnt/c.
tmp=$(mktemp -d)
trap '[ -z "$pid" ] || kill "$pid" 2>/dev/null; [ -z "$mon" ] || kill "$mon" 2>/dev/null; rm -rf "$tmp"' EXIT

# What the numbers were measured on.
{
    echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "kernel: $(uname -r)"
    echo "os: $(. /etc/os-release && echo "$PRETTY_NAME")"
    echo "cpu: $(lscpu | sed -n 's/^Model name: *//p'), $(nproc) logical CPUs"
    echo "memory: $(free -g | awk '/^Mem:/ {print $2}') GB"
    echo "server cpus: $server_cpus, client cpus: $client_cpus, client threads: $threads"
    echo "duration: $duration s, warm-up: $warmup s, runs: $runs"
    echo "goose-http: $(git -C "$root" rev-parse --short HEAD)$(git -C "$root" diff --quiet || echo ' (modified)')"
    echo "goose: $(git -C "$root/../goose" rev-parse --short HEAD)"
    echo "cc: $(${CC:-cc} --version | head -1)"
    echo "rustc: $(PATH=$HOME/.cargo/bin:$PATH rustc --version)"
    echo "odin: $(${ODIN:-odin} version)"
    echo "zig: $(${ZIG:-zig} version)"
    echo "v: $("${CACHE:-$HOME/.cache/goose-http-bench}/deps/v/v" version)"
    echo "wrk: $(wrk -v 2>&1 | head -1)"
    echo "h2load: $(h2load --version)"
} >"$out/env.txt"
printf 'server\tworkers\ttest\tconns\trun\trps\terrors\tnon2xx\tserver_cpu_s\twrk_cpu_s\tpeak_rss_kb\tsteps\th2load_rps\th2load_failed\th2load_non2xx\tp50_us\tp99_us\tp999_us\tmax_us\n' \
    >"$out/runs.tsv"

# utime + stime of a process and its threads, in clock ticks.
cpu_ticks() { awk '{print $14 + $15}' "/proc/$1/stat"; }

for run in $(seq "$runs"); do
for workers in $worker_counts; do
    if [ "$workers" = 1 ]; then cpus=${server_cpus%%[-,]*}; else cpus=$server_cpus; fi
    for server in $servers; do
    for t in $tests; do
        test=${t%%:*}
        conns=${t#*:}
        name=$server-w$workers-$test-c$conns-r$run
        echo "$name"
        if [ "$test" = plaintext ]; then
            accept=$accept_plain
            depth=16
            set -- -s "$root/scripts/pipeline.lua" "$url/$test" -- $depth
        else
            accept=$accept_json
            depth=1
            set -- "$url/$test"
        fi

        if nc -z 127.0.0.1 "$port" 2>/dev/null; then
            echo "bench/run.sh: port $port is taken; set PORT"
            exit 1
        fi
        case $server in
        goose*) WORKERS=$workers taskset -c "$cpus" "$bin/$server" http "$port" >"$out/$name.log" 2>&1 & ;;
        *) WORKERS=$workers taskset -c "$cpus" "$bin/$server" "$port" >"$out/$name.log" 2>&1 & ;;
        esac
        pid=$!
        tries=0
        until nc -z 127.0.0.1 "$port" 2>/dev/null; do
            tries=$((tries + 1))
            [ $tries -lt 100 ] || { echo "bench/run.sh: $server isn't listening"; exit 1; }
            sleep 0.1
        done

        wrk="taskset -c $client_cpus wrk -t $threads -c $conns --timeout 8"
        LD_PRELOAD=$bin/wrk-monotonic.so $wrk -H "$host" -H "$conn" -H "$accept" -d "$warmup" "$@" \
            >/dev/null

        python3 "$root/bench/clockstep.py" >"$out/$name.steps" &
        mon=$!
        c0=$(cpu_ticks $pid)
        (
            LD_PRELOAD=$bin/wrk-monotonic.so $wrk -H "$host" -H "$conn" -H "$accept" \
                -d "$duration" --latency "$@" >"$out/$name.wrk"
            times >"$out/$name.times"
        )
        c1=$(cpu_ticks $pid)
        kill $mon
        wait $mon 2>/dev/null || true
        mon=

        : >"$out/$name.h2load"
        : >"$out/$name.lat"
        if [ "$latency" = 1 ]; then
            fifo=$tmp/$name.fifo
            mkfifo "$fifo"
            "$bin/latency" <"$fifo" >"$out/$name.lat" &
            lat=$!
            taskset -c "$client_cpus" h2load --h1 -t "$threads" -c "$conns" -m $depth \
                -H "$host" -H "$conn" -H "$accept" -D "$duration" --warm-up-time=2 \
                --log-file="$fifo" "$url/$test" >"$out/$name.h2load" 2>&1 || true
            wait $lat || true
            rm -f "$fifo"
        fi

        rss=$(awk '/^VmHWM/ {print $2}' "/proc/$pid/status")
        kill $pid
        wait $pid 2>/dev/null || true
        pid=

        w=$out/$name.wrk
        rps=$(awk '/^Requests\/sec/ {print $2}' "$w")
        errors=$(awk '/Socket errors/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+,?$/) n += $i; print n }' "$w")
        non2xx=$(awk '/Non-2xx/ {print $NF}' "$w")
        wrk_cpu=$(awk 'NR == 2 {
            split($1, u, /[ms]/); split($2, s, /[ms]/); printf "%.2f", u[1] * 60 + u[2] + s[1] * 60 + s[2]
        }' "$out/$name.times")
        steps=$(wc -l <"$out/$name.steps")
        h2rps=$(awk '/^finished in/ {print $4}' "$out/$name.h2load")
        h2failed=$(awk '/^requests:/ {print $10 + $12 + $14}' "$out/$name.h2load")
        set -- $(cat "$out/$name.lat")
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$server" "$workers" "$test" "$conns" "$run" "$rps" "${errors:-0}" "${non2xx:-0}" \
            "$(echo "$c0 $c1 $hz" | awk '{printf "%.2f", ($2 - $1) / $3}')" "$wrk_cpu" "$rss" \
            "$steps" "${h2rps:-}" "${h2failed:-}" "${4:-}" "${6:-}" "${10:-}" "${12:-}" "${14:-}" \
            >>"$out/runs.tsv"
    done
    done
done
done
echo "results: $out"
python3 "$root/bench/summarize.py" "$out/runs.tsv" "${servers%% *}" | tee "$out/summary.md"
