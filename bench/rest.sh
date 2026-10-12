#!/bin/sh
# Runs the REST benchmark of task 021 on this machine, and writes the raw
# results to bench/results/<date>-rest-<machine>/.
#
#   bench/rest.sh build    the datasets (bench/rest/gen.goose) into DATA, the
#                          Goose server (bench/rest/goose) into build/rest/rest,
#                          hyper's (bench/rest/hyper) into build/rest/rest-hyper,
#                          and zrk into CACHE
#   bench/rest.sh run      checks each server with bench/rest/check.py, then
#                          measures, round by round
#
# What a run measures, each server with WORKERS workers on SERVER_CPUS and the
# load on CLIENT_CPUS, a fresh server per cell:
#
#   1. Tiers A to C at saturation, both JSON ways: wrk with the tier's script,
#      CLIENT_THREADS threads and 256 connections, WARMUP s discarded and then
#      DURATION s, with the server's CPU time and peak RSS (VmHWM).
#   2. Tier D: tier-d.lua's uploads role alone (1 thread, 32 connections), and
#      beside the forms role (CLIENT_THREADS - 1 threads, 224 connections).
#   3. Tiers A to C at a fixed rate, both JSON ways: bench/rest/rate.py, a zrk
#      per route, at RATE_A, RATE_B, and RATE_C requests per second, which
#      default to half the lowest median rate a server reached in step 1, to
#      two significant figures. zrk corrects for coordinated omission.
#   4. The mixed run: a TIER=d server, warmed up with tier C at saturation,
#      then tier C's reads at RATE_C, alone and beside the uploads role.
#
# Each step warms each server up first: cold, Goose's first seconds
# put tier C's p99 at 20-70 ms in a 3 s run, where warm it stays under 2 ms.
#
# Settings, from the environment:
#   SERVERS        goose-uring goose-epoll hyper
#   SERVER_CPUS    0-3, WORKERS the number of them
#   CLIENT_CPUS    4-15, CLIENT_THREADS 8
#   RUNS 3, DURATION 15, WARMUP 5, PORT 29380
#   STEPS          1 2 3 4. Without step 1, step 3 needs RATE_A, RATE_B, and
#                  RATE_C, and step 4 RATE_C.
#   MACHINE        a short name for the machine (the host name), for OUT
#   DATA           build/rest; OUT bench/results/<date>-rest-<machine>
#   ZRK            zrk 2.3.0's x86-64 release, as HttpArena pins it
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cache=${CACHE:-$HOME/.cache/goose-http-bench}
bin=$root/build/rest
data=${DATA:-$root/build/rest}
PATH=$HOME/.cargo/bin:$PATH

ZRK_VERSION=2.3.0
ZRK_SHA256=ab6f1c1ce34ce73f52afd106419d15e5c494bd1cedd475afa56babb85b09a816
zrk=${ZRK:-$cache/zrk-$ZRK_VERSION/zrk}

case ${1:-} in
build)
    mkdir -p "$bin" "$data"
    goose=${GOOSE:-goose}
    "$goose" build --cc gcc --standalone -o "$bin/gen" "$root/bench/rest/gen.goose"
    "$bin/gen" "$data"
    "$goose" build --cc gcc --standalone -o "$bin/rest" "$root/bench/rest/goose/rest.goose"
    # As bench/build.sh builds bench/hyper: for this machine, from CACHE.
    (cd "$cache" && RUSTFLAGS="-C target-cpu=native" cargo build --release --locked \
        --manifest-path "$root/bench/rest/hyper/Cargo.toml" --target-dir "$cache/target-rest-hyper")
    cp "$cache/target-rest-hyper/release/rest-hyper" "$bin/rest-hyper"
    if [ ! -x "$zrk" ]; then
        curl -sSLf -o "$cache/zrk.tar.gz" \
            "https://github.com/zoxy-io/zrk/releases/download/v$ZRK_VERSION/zrk-$ZRK_VERSION-x86_64-linux.tar.gz"
        [ "$(sha256sum <"$cache/zrk.tar.gz" | cut -d' ' -f1)" = "$ZRK_SHA256" ] ||
            { echo "bench/rest.sh: zrk.tar.gz doesn't match ZRK_SHA256"; exit 1; }
        mkdir -p "$(dirname "$zrk")"
        tar -xzf "$cache/zrk.tar.gz" -C "$(dirname "$zrk")" zrk
    fi
    ls -l "$bin"
    exit 0
    ;;
run) ;;
*)
    echo "usage: bench/rest.sh build | run"
    exit 2
    ;;
esac

servers=${SERVERS:-goose-uring goose-epoll hyper}
server_cpus=${SERVER_CPUS:-0-3}
client_cpus=${CLIENT_CPUS:-4-15}
threads=${CLIENT_THREADS:-8}
workers=${WORKERS:-$(taskset -c "$server_cpus" nproc)}
runs=${RUNS:-3}
duration=${DURATION:-15}
warmup=${WARMUP:-5}
port=${PORT:-29380}
steps=${STEPS:-1 2 3 4}
machine=${MACHINE:-$(hostname -s)}
out=${OUT:-$root/bench/results/$(date -u +%Y-%m-%dT%H%M)-rest-$machine}
url=http://127.0.0.1:$port
hz=$(getconf CLK_TCK)

for b in "$bin/rest" "$bin/rest-hyper" "$zrk"; do
    [ -x "$b" ] || { echo "bench/rest.sh: no $b; run bench/rest.sh build"; exit 1; }
done
[ -e "$root/build/bench/wrk-monotonic.so" ] || { echo "bench/rest.sh: run bench/build.sh"; exit 1; }
ulimit -n 65536
mkdir -p "$out"
pid=
trap '[ -z "$pid" ] || kill "$pid" 2>/dev/null' EXIT

{
    echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "machine: $machine"
    echo "kernel: $(uname -r)"
    echo "cpu: $(lscpu | sed -n 's/^Model name: *//p'), $(nproc) logical CPUs"
    echo "server cpus: $server_cpus, workers: $workers, client cpus: $client_cpus, client threads: $threads"
    echo "duration: $duration s, warm-up: $warmup s, runs: $runs"
    echo "goose-http: $(git -C "$root" rev-parse --short HEAD)$(git -C "$root" diff --quiet || echo ' (modified)')"
    echo "goose: $(git -C "$root/../goose" rev-parse --short HEAD)"
    echo "cc: $(${CC:-cc} --version | head -1)"
    echo "rustc: $(rustc --version)"
    echo "wrk: $(wrk -v 2>&1 | head -1)"
    echo "zrk: $ZRK_VERSION"
} >"$out/env.txt"
(cd "$bin" && sha256sum rest rest-hyper) >"$out/binaries.txt"

# Starts server $1 on tier $2 with JSON way $3, and waits until it listens.
start() {
    if nc -z 127.0.0.1 "$port" 2>/dev/null; then
        echo "bench/rest.sh: port $port is taken; set PORT"
        exit 1
    fi
    case $1 in
    goose-uring) exe=$bin/rest loop=uring ;;
    goose-epoll) exe=$bin/rest loop=epoll ;;
    hyper) exe=$bin/rest-hyper loop= ;;
    *) echo "bench/rest.sh: no server $1"; exit 1 ;;
    esac
    REST_DATA=$data TIER=$2 JSON=$3 WORKERS=$workers LOOP=$loop \
        taskset -c "$server_cpus" "$exe" "$port" >>"$out/$1.log" 2>&1 &
    pid=$!
    tries=0
    # Loading tier C's records takes a few seconds.
    until nc -z 127.0.0.1 "$port" 2>/dev/null; do
        tries=$((tries + 1))
        [ $tries -lt 600 ] || { echo "bench/rest.sh: $1 isn't listening"; exit 1; }
        sleep 0.1
    done
}

ticks() { awk '{print $14 + $15}' "/proc/$pid/stat"; }

# Stops the server, after writing its CPU ticks since mark, the clock's ticks
# per second, and its peak RSS in KB into $1.stat.
stop() {
    echo "$c0 $(ticks) $hz $(awk '/^VmHWM/ {print $2}' "/proc/$pid/status")" >"$1.stat"
    kill $pid
    wait $pid 2>/dev/null || true
    pid=
}

wrk_() {
    taskset -c "$client_cpus" env LD_PRELOAD="$root/build/bench/wrk-monotonic.so" \
        wrk --timeout 10s --latency "$@"
}

# Each server answers the checker before its runs, on each tier it serves.
for s in $servers; do
    for t in a b c d; do
        for j in serialize template; do
            [ "$t" = d ] && [ "$j" = template ] && continue
            start "$s" "$t" "$j"
            f=$out/check-$s-$t-$j.txt
            python3 "$root/bench/rest/check.py" "$port" "$data" "$t" >"$f" 2>&1 &&
                { [ "$t" != d ] || python3 "$root/bench/rest/check.py" "$port" "$data" c >>"$f" 2>&1; } ||
                { echo "bench/rest.sh: $s fails tier $t ($j):"; tail -3 "$f"; exit 1; }
            kill $pid
            wait $pid 2>/dev/null || true
            pid=
            echo "check $s $t $j: ok"
        done
    done
done

for run in $(seq "$runs"); do
    case " $steps " in *" 1 "*)
    for s in $servers; do
    for t in a b c; do
    for j in serialize template; do
        name=$out/sat-$s-$t-$j-r$run
        echo "${name##*/}"
        start "$s" "$t" "$j"
        set -- -t "$threads" -c 256 -s "$root/bench/rest/tier-$t.lua" "$url" -- "$data"
        wrk_ -d "$warmup" "$@" >/dev/null
        c0=$(ticks)
        wrk_ -d "$duration" "$@" >"$name.wrk"
        stop "$name"
    done
    done
    done
    ;; esac

    case " $steps " in *" 2 "*)
    for s in $servers; do
    for role in alone both; do
        name=$out/d-$s-$role-r$run
        echo "${name##*/}"
        start "$s" d serialize
        set -- -s "$root/bench/rest/tier-d.lua" "$url" -- "$data"
        wrk_ -t 1 -c 32 -d "$warmup" "$@" uploads >/dev/null
        set -- -d "$duration" "$@"
        c0=$(ticks)
        if [ "$role" = both ]; then
            wrk_ -t $((threads - 1)) -c 224 "$@" forms >"$name.forms.wrk" &
            forms=$!
        fi
        wrk_ -t 1 -c 32 "$@" uploads >"$name.uploads.wrk"
        [ "$role" = alone ] || wait $forms
        stop "$name"
    done
    done
    ;; esac
done

# The fixed rates, from step 1's results unless given.
rate_a=${RATE_A:-} rate_b=${RATE_B:-} rate_c=${RATE_C:-}
case " $steps " in *" 3 "*) need="a b c" ;; *" 4 "*) need=c ;; *) need= ;; esac
for t in $need; do
    eval "r=\$rate_$t"
    [ -n "$r" ] || r=$(python3 "$root/bench/rest/summary.py" --half "$out" "$t")
    eval "rate_$t=$r"
    echo "rate $t: $r" | tee -a "$out/env.txt"
done

for run in $(seq "$runs"); do
    case " $steps " in *" 3 "*)
    for s in $servers; do
    for t in a b c; do
    for j in serialize template; do
        name=$out/rate-$s-$t-$j-r$run
        echo "${name##*/}"
        start "$s" "$t" "$j"
        wrk_ -t "$threads" -c 256 -d "$warmup" -s "$root/bench/rest/tier-$t.lua" "$url" -- "$data" >/dev/null
        eval "r=\$rate_$t"
        c0=$(ticks)
        python3 "$root/bench/rest/rate.py" "$zrk" "$url" "$data" "$t" "$r" "$duration" "$client_cpus" "$name" ||
            echo "$name: zrk exited with an error"
        stop "$name"
    done
    done
    done
    ;; esac

    case " $steps " in *" 4 "*)
    for s in $servers; do
    for role in alone uploads; do
        name=$out/mixed-$s-$role-r$run
        echo "${name##*/}"
        start "$s" d serialize
        wrk_ -t "$threads" -c 256 -d "$warmup" -s "$root/bench/rest/tier-c.lua" "$url" -- "$data" >/dev/null
        c0=$(ticks)
        if [ "$role" = uploads ]; then
            wrk_ -t 1 -c 32 -d "$duration" -s "$root/bench/rest/tier-d.lua" "$url" -- "$data" uploads \
                >"$name.uploads.wrk" &
            up=$!
        fi
        python3 "$root/bench/rest/rate.py" "$zrk" "$url" "$data" c "$rate_c" "$duration" "$client_cpus" "$name" ||
            echo "$name: zrk exited with an error"
        [ "$role" = alone ] || wait $up
        stop "$name"
    done
    done
    ;; esac
done

echo "results: $out"
python3 "$root/bench/rest/summary.py" "$out" | tee "$out/summary.md"
