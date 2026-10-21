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
#                 plaintext. It builds task 005's io_uring servers too,
#                 xitca-web, zix, zeemo, libreactorng, and vanilla-io_uring,
#                 which run only when named here.
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
#   MACHINE       a short name for the machine (the host name), for OUT
#   RUNS 3, DURATION 15, WARMUP 5, PORT 29280,
#   OUT bench/results/<date>-<machine>
#   REUSE         earlier result directories whose cells this run copies
#                 instead of measuring again. A cell is copied when the
#                 earlier run had the same key.txt (METHOD, the settings
#                 above, the machine, and the load generators), the same
#                 server binary (binaries.txt), and all RUNS of the cell. Its
#                 rows name their directory in the from column. Goose builds
#                 always run: sessions drift by up to 5%, and a Goose build
#                 rerun beside an earlier one shows by how much.
set -eu

# Bump METHOD when a change here changes what a cell measures, so REUSE stops
# copying cells measured the old way.
METHOD=1

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/scripts/goose.sh"
bin=$root/build/bench
servers=${SERVERS:-goose dusty vanilla-epoll}
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
machine=${MACHINE:-$(hostname -s)}
out=${OUT:-$root/bench/results/$(date -u +%Y-%m-%dT%H%M)-$machine}
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
    echo "machine: $machine"
    echo "kernel: $(uname -r)"
    echo "os: $(. /etc/os-release && echo "$PRETTY_NAME")"
    echo "cpu: $(lscpu | sed -n 's/^Model name: *//p'), $(nproc) logical CPUs"
    echo "memory: $(free -g | awk '/^Mem:/ {print $2}') GB"
    echo "server cpus: $server_cpus, client cpus: $client_cpus, client threads: $threads"
    echo "duration: $duration s, warm-up: $warmup s, runs: $runs"
    echo "goose-http: $(git -C "$root" rev-parse --short HEAD)$(git -C "$root" diff --quiet || echo ' (modified)')"
    echo "goose: $(goose_version)"
    echo "cc: $(${CC:-cc} --version | head -1)"
    echo "odin: $(${ODIN:-odin} version)"
    echo "zig: $(${ZIG:-zig} version)"
    echo "v: $("${CACHE:-$HOME/.cache/goose-http-bench}/deps/v/v" version)"
    echo "wrk: $(wrk -v 2>&1 | head -1)"
    echo "h2load: $(h2load --version)"
} >"$out/env.txt"
# What a cell's numbers depend on besides the server, for REUSE.
{
    echo "method: $METHOD"
    echo "kernel: $(uname -r)"
    echo "cpu: $(lscpu | sed -n 's/^Model name: *//p'), $(nproc) logical CPUs"
    echo "server cpus: $server_cpus, client cpus: $client_cpus, client threads: $threads"
    echo "duration: $duration s, warm-up: $warmup s, latency: $latency"
    echo "wrk: $(wrk -v 2>&1 | head -1)"
    echo "h2load: $(h2load --version)"
    (cd "$root" && sha256sum scripts/pipeline.lua bench/wrk-monotonic.c bench/latency.c \
        bench/clockstep.py)
} >"$out/key.txt"
# shellcheck disable=SC2086 # servers is a list of names
(cd "$bin" && sha256sum $servers) >"$out/binaries.txt"
printf 'server\tworkers\ttest\tconns\trun\trps\terrors\tnon2xx\tserver_cpu_s\twrk_cpu_s\tpeak_rss_kb\tsteps\th2load_rps\th2load_failed\th2load_non2xx\tp50_us\tp99_us\tp999_us\tmax_us\tfrom\n' \
    >"$out/runs.tsv"

# Prints the RUNS rows of the cell of server $1, $2 workers, test $3, and $4
# connections from the first REUSE directory that has them for the same key
# and binary. The from column names that directory, or the one the rows were
# first copied from.
reused_rows() {
    case $1 in goose*) return 1 ;; esac
    sum=$(awk -v s="$1" '$2 == s {print $1}' "$out/binaries.txt")
    for dir in ${REUSE:-}; do
        [ -f "$dir/key.txt" ] && cmp -s "$dir/key.txt" "$out/key.txt" || continue
        [ "$(awk -v s="$1" '$2 == s {print $1}' "$dir/binaries.txt")" = "$sum" ] || continue
        awk -F '\t' -v OFS='\t' -v s="$1" -v w="$2" -v t="$3" -v c="$4" -v n="$runs" \
            -v d="$(basename "$dir")" '
            NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
            $1 == s && $2 == w && $3 == t && $4 == c && $5 <= n && !($5 in row) {
                f = ("from" in col && $col["from"] != "") ? $col["from"] : d
                line = $1
                for (i = 2; i <= 19; i++) line = line OFS $i
                row[$5] = line OFS f
                k++
            }
            END {
                if (k != n) exit 1
                for (i = 1; i <= n; i++) print row[i]
            }' "$dir/runs.tsv" && return 0
    done
    return 1
}

skip=
for workers in $worker_counts; do
    for server in $servers; do
    for t in $tests; do
        if reused_rows "$server" "$workers" "${t%%:*}" "${t#*:}" >"$tmp/rows"; then
            cat "$tmp/rows" >>"$out/runs.tsv"
            skip="$skip $server-w$workers-$t"
            echo "$server-w$workers-$t: reused"
        fi
    done
    done
done

# utime + stime of a process and its threads, in clock ticks.
cpu_ticks() { awk '{print $14 + $15}' "/proc/$1/stat"; }

for run in $(seq "$runs"); do
for workers in $worker_counts; do
    if [ "$workers" = 1 ]; then cpus=${server_cpus%%[-,]*}; else cpus=$server_cpus; fi
    for server in $servers; do
    for t in $tests; do
        case "$skip " in *" $server-w$workers-$t "*) continue ;; esac
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
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t\n' \
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
