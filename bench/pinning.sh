#!/bin/sh
# Task 045's spike: /fast's latency beside a busy CPU lane, in each layout of
# workers and lane, each given to bench/pinning/pinning.goose as a placement
# file. Two oha runs at fixed rates at once, so that a slower server can't
# hide its latency behind a slower client: /fast at FAST_RATE, and
# /primes/PRIMES_N at PRIMES_RATE. Each run of a layout takes WARMUP seconds,
# discarded, then SECONDS measured; the layouts alternate, RUNS times.
#
#   bench/pinning.sh                     (all of this platform's layouts)
#   LAYOUTS="over pinned" RUNS=1 SECONDS=5 WARMUP=1 bench/pinning.sh
#
# Layouts, on the N cores the server may use:
#
#   over      N workers, the lane floating (the default today)
#   fewer     N-1 workers, the lane floating
#   workers   N-1 workers, each pinned; the lane floating
#   pinned    N-1 workers, each pinned, in an exclusive set; the lane on the core left
#   nice      N workers; the lane at low priority (Linux: nice 10 and SCHED_BATCH;
#             macOS: the background QoS class)
#   sibling   a worker pinned to the first hardware thread of each core; the lane
#             on the SMT sibling of worker 0's (Linux with SMT only)
#   within    N-2 workers, each pinned, exclusive; the lane within the two cores left
#   incoming  pinned, with each worker's listener on SO_INCOMING_CPU (Linux)
#
# macOS can't pin, so it runs over, fewer, and nice only. Without FAST_RATE,
# the script measures /fast alone in over for 10 s and takes 70% of its
# rate; without PRIMES_RATE, it times 20 jobs one at a time and takes the
# rate that keeps the lane 80% busy. On Linux, SERVER_CPUS and CLIENT_CPUS
# (taskset lists) keep the server and the clients apart.
#
# Results go to build/bench/pinning/<date>-<host>/: env.txt, each run's oha
# JSON, runs.tsv, and summary.tsv, each layout's median and range.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/scripts/goose.sh"
os=$(uname -s)
port=${PORT:-18080}
runs=${RUNS:-5}
secs=${SECONDS_EACH:-${SECONDS:-30}}
warmup=${WARMUP:-5}
primes_n=${PRIMES_N:-200000}
fast_conns=${FAST_CONNS:-64}
primes_conns=${PRIMES_CONNS:-16}
case $os in
Darwin) default_layouts="over fewer nice" ;;
*) default_layouts="over fewer workers pinned nice sibling within incoming" ;;
esac
layouts=${LAYOUTS:-$default_layouts}

out=$root/build/bench/pinning/$(date +%Y%m%d-%H%M%S)-$(hostname -s)
bin=$root/build/bench/pinning/pinning
mkdir -p "$out"
"$GOOSE" build -O2 -o "$bin" "$root/bench/pinning/pinning.goose" >"$out/build.log" 2>&1 ||
    { cat "$out/build.log"; exit 1; }

# The server's cores, one per line.
server_cpus() {
    if [ "$os" = Darwin ]; then
        seq 0 $(($(sysctl -n hw.logicalcpu) - 1))
    elif [ -n "${SERVER_CPUS:-}" ]; then
        echo "$SERVER_CPUS" | tr ',' '\n' | while IFS=- read -r lo hi; do seq "$lo" "${hi:-$lo}"; done
    else
        taskset -cp $$ | sed 's/.*: //' | tr ',' '\n' | while IFS=- read -r lo hi; do seq "$lo" "${hi:-$lo}"; done
    fi
}
cpus=$(server_cpus)
n=$(echo "$cpus" | wc -l | tr -d ' ')
nth() { echo "$cpus" | sed -n "$(($1 + 1))p"; }
first() { echo "$cpus" | head -n "$1" | paste -sd, -; }

# The placement file for layout $1, into $out/$1.place; false for a layout
# this machine can't run.
place_file() {
    f=$out/$1.place
    case $1 in
    over) echo "workers = $n" >"$f" ;;
    fewer) echo "workers = $((n - 1))" >"$f" ;;
    workers) printf 'set w = %s\nworkers = %d each w\n' "$(first $((n - 1)))" $((n - 1)) >"$f" ;;
    pinned | incoming)
        extra=""
        [ "$1" = incoming ] && extra=" incoming"
        printf 'set w = %s exclusive\nworkers = %d each w%s\nlane = core %s\n' \
            "$(first $((n - 1)))" $((n - 1)) "$extra" "$(nth $((n - 1)))" >"$f" ;;
    nice) printf 'workers = %d\nlane = 1 low\n' "$n" >"$f" ;;
    within)
        printf 'set w = %s exclusive\nworkers = %d each w\nset l = %s, %s\nlane = within l\n' \
            "$(first $((n - 2)))" $((n - 2)) "$(nth $((n - 2)))" "$(nth $((n - 1)))" >"$f" ;;
    sibling)
        # The first hardware thread of each core among the server's, and the
        # sibling of the first.
        firsts=""
        sib=""
        for c in $cpus; do
            list=$(cat "/sys/devices/system/cpu/cpu$c/topology/thread_siblings_list" 2>/dev/null) || return 1
            lead=$(echo "$list" | tr ',-' '\n\n' | head -1)
            if [ "$lead" = "$c" ]; then
                firsts="$firsts${firsts:+,}$c"
                [ -z "$sib" ] && sib=$(echo "$list" | tr ',-' '\n\n' | sed -n 2p)
            fi
        done
        [ -n "$sib" ] || return 1
        k=$(echo "$firsts" | tr ',' '\n' | wc -l | tr -d ' ')
        printf 'set w = %s\nworkers = %d each w\nlane = core %s\n' "$firsts" "$k" "$sib" >"$f" ;;
    *) echo "pinning.sh: no layout $1" >&2; exit 2 ;;
    esac
}

# Runs in the background, so exec: $! is then the server's PID, not a
# subshell's that kill would leave the server behind.
on_server() {
    if [ "$os" != Darwin ] && [ -n "${SERVER_CPUS:-}" ]; then exec taskset -c "$SERVER_CPUS" "$@"; else exec "$@"; fi
}
on_client() {
    if [ "$os" != Darwin ] && [ -n "${CLIENT_CPUS:-}" ]; then taskset -c "$CLIENT_CPUS" "$@"; else "$@"; fi
}

pid=""
start() {
    on_server "$bin" --port "$port" --place "$out/$1.place" >"$out/server-$1.log" 2>&1 &
    pid=$!
    i=0
    until curl -sf "http://127.0.0.1:$port/fast" >/dev/null; do
        i=$((i + 1))
        [ $i -lt 100 ] || { cat "$out/server-$1.log"; exit 1; }
        sleep 0.1
    done
}
stop() {
    kill "$pid"
    wait "$pid" 2>/dev/null || true
}
trap '[ -n "$pid" ] && kill "$pid" 2>/dev/null || true' EXIT

for l in $layouts; do
    place_file "$l" || { echo "pinning.sh: skipping $l, which this machine can't run" >&2; layouts=$(echo "$layouts" | sed "s/\b$l\b//"); }
done

# The JSON fields runs.tsv takes from oha's.
fields() {
    python3 -c '
import json, sys
f = json.load(open(sys.argv[1])); p = json.load(open(sys.argv[2]))
pct = f["latencyPercentiles"]; codes = p["statusCodeDistribution"]
ms = lambda s: "%.3f" % (1000 * (s or 0))
print("\t".join([ms(pct["p50"]), ms(pct["p99"]), ms(pct["p99.9"]), "%.1f" % f["summary"]["requestsPerSec"],
                 "%.1f" % (codes.get("200", 0) / float(sys.argv[3])), str(codes.get("503", 0)), str(codes.get("504", 0))]))
' "$@"
}

place_file over
if [ -z "${FAST_RATE:-}" ] || [ -z "${PRIMES_RATE:-}" ]; then
    start over
    if [ -z "${FAST_RATE:-}" ]; then
        on_client oha --no-tui --output-format json -z 10s -c "$fast_conns" "http://127.0.0.1:$port/fast" >"$out/calibrate-fast.json"
        FAST_RATE=$(python3 -c 'import json,sys; print(int(0.7 * json.load(open(sys.argv[1]))["summary"]["requestsPerSec"]))' "$out/calibrate-fast.json")
    fi
    if [ -z "${PRIMES_RATE:-}" ]; then
        on_client oha --no-tui --output-format json -n 20 -c 1 "http://127.0.0.1:$port/primes/$primes_n" >"$out/calibrate-primes.json"
        PRIMES_RATE=$(python3 -c 'import json,sys; print(round(0.8 / json.load(open(sys.argv[1]))["summary"]["average"], 1))' "$out/calibrate-primes.json")
    fi
    stop
fi

{
    echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "machine: $(hostname -s), $(uname -srm)"
    if [ "$os" = Darwin ]; then
        echo "cpu: $(sysctl -n machdep.cpu.brand_string), $(sysctl -n hw.perflevel0.logicalcpu) performance + $(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null || echo 0) efficiency cores"
    else
        echo "cpu: $(lscpu | sed -n 's/^Model name: *//p' | head -1), $(nproc --all) hardware threads"
        echo "smt: $(cat /sys/devices/system/cpu/smt/active 2>/dev/null || echo unknown)"
    fi
    echo "server cores: $(echo "$cpus" | paste -sd, -), clients: ${CLIENT_CPUS:-shared}"
    echo "compiler: $(goose_version)"
    echo "commit: $(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "oha: $(oha --version)"
    echo "/fast: $FAST_RATE requests/s over $fast_conns connections"
    echo "/primes/$primes_n: $PRIMES_RATE requests/s over $primes_conns connections"
    echo "runs: $runs of $warmup s warm-up and $secs s each, layouts alternating: $layouts"
} >"$out/env.txt"
cat "$out/env.txt"

printf 'layout\trun\tfast_p50_ms\tfast_p99_ms\tfast_p999_ms\tfast_rps\tprimes_ok_per_s\tprimes_503\tprimes_504\n' >"$out/runs.tsv"
for r in $(seq 1 "$runs"); do
    for l in $layouts; do
        start "$l"
        load() {
            on_client oha --no-tui --output-format json --latency-correction -z "$1s" -q "$FAST_RATE" -c "$fast_conns" \
                "http://127.0.0.1:$port/fast" >"$2-fast.json" &
            f=$!
            on_client oha --no-tui --output-format json --latency-correction -z "$1s" -q "$PRIMES_RATE" -c "$primes_conns" \
                "http://127.0.0.1:$port/primes/$primes_n" >"$2-primes.json"
            wait $f
        }
        load "$warmup" "$out/warmup"
        load "$secs" "$out/$l-$r"
        stop
        printf '%s\t%s\t%s\n' "$l" "$r" "$(fields "$out/$l-$r-fast.json" "$out/$l-$r-primes.json" "$secs")" >>"$out/runs.tsv"
        tail -1 "$out/runs.tsv"
    done
done

python3 -c '
import csv, statistics, sys
rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\t"))
cols = [c for c in rows[0] if c not in ("layout", "run")]
print("layout\t" + "\t".join(cols))
for l in dict.fromkeys(r["layout"] for r in rows):
    mine = [r for r in rows if r["layout"] == l]
    cells = []
    for c in cols:
        v = [float(r[c]) for r in mine]
        cells.append("%g (%g-%g)" % (statistics.median(v), min(v), max(v)))
    print(l + "\t" + "\t".join(cells))
' "$out/runs.tsv" | tee "$out/summary.tsv"
echo "results in $out"
