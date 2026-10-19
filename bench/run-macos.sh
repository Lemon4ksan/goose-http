#!/bin/sh
# Runs a short matrix natively on macOS, where bench/run.sh can't (no taskset,
# no /proc): the Goose server against the Rust servers that build on macOS,
# with wrk on the same machine and nothing pinned. Builds them first, into
# build/bench-macos/, with bench/build.sh's flags.
#
# Each cell gets a fresh server, wrk for WARMUP seconds, then wrk for DURATION
# seconds, measured. Peak RSS is the largest of ps's once-a-second samples.
# The rounds are interleaved, as in bench/run.sh. No h2load latency run.
#
# Settings, from the environment:
#   SERVERS   goose may-minihttp hyper tokio
#   WORKERS   4, for every server; THREADS 4, for wrk. Together at most the 8
#             performance cores, so neither lands on an efficiency core.
#   TESTS     plaintext:256 plaintext:1024 json:256
#   RUNS 3, DURATION 10, WARMUP 3, PORT 29380, MACHINE (the host name),
#   OUT bench/results/<date>-<machine>
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
bin=$root/build/bench-macos
cache=${CACHE:-$HOME/.cache/goose-http-bench-macos}
servers=${SERVERS:-goose may-minihttp hyper tokio}
workers=${WORKERS:-4}
threads=${THREADS:-4}
tests=${TESTS:-plaintext:256 plaintext:1024 json:256}
runs=${RUNS:-3}
duration=${DURATION:-10}
warmup=${WARMUP:-3}
port=${PORT:-29380}
machine=${MACHINE:-$(hostname -s)}
out=${OUT:-$root/bench/results/$(date -u +%Y-%m-%d)-$machine}
PATH=$HOME/.cargo/bin:$PATH

mkdir -p "$bin" "$cache" "$out"
"$root/scripts/build.sh" >/dev/null
cp "$root/build/server" "$bin/goose"
for name in $servers; do
    case $name in goose) continue ;; esac
    (cd "$cache" && RUSTFLAGS="-C target-cpu=native" cargo build -q --release --locked \
        --manifest-path "$root/bench/$name/Cargo.toml" --target-dir "$cache/target-$name")
    cp "$cache/target-$name/release/bench-$name" "$bin/$name"
done

ulimit -n 65536
host='Host: tfb-server'
conn='Connection: keep-alive'
accept_plain='Accept: text/plain,text/html;q=0.9,application/xhtml+xml;q=0.9,application/xml;q=0.8,*/*;q=0.7'
accept_json='Accept: application/json,text/html;q=0.9,application/xhtml+xml;q=0.9,application/xml;q=0.8,*/*;q=0.7'

{
    echo "date: $(date -u +%FT%TZ)"
    echo "commit: $(git -C "$root" rev-parse --short HEAD)"
    echo "machine: $(sysctl -n machdep.cpu.brand_string)," \
        "$(sysctl -n hw.perflevel0.physicalcpu)P+$(sysctl -n hw.perflevel1.physicalcpu)E," \
        "macOS $(sw_vers -productVersion), Darwin $(uname -r)"
    echo "wrk: $(wrk -v 2>&1 | head -1)"
    echo "somaxconn: $(sysctl -n kern.ipc.somaxconn)"
    echo "power: $(pmset -g batt | head -1)"
    echo "load before: $(sysctl -n vm.loadavg)"
    echo "settings: workers=$workers threads=$threads runs=$runs duration=$duration warmup=$warmup"
    for s in $servers; do echo "$s: $(shasum -a 256 "$bin/$s" | cut -c1-16)"; done
} >"$out/env.txt"

printf 'server\tworkers\ttest\tconns\trun\trps\terrors\tnon2xx\tpeak_rss_kb\tload1\n' >"$out/runs.tsv"
for run in $(seq 1 "$runs"); do
    for t in $tests; do
        test=${t%%:*}
        conns=${t#*:}
        case $test in
        plaintext)
            accept=$accept_plain
            set -- -s "$root/scripts/pipeline.lua" "http://127.0.0.1:$port/plaintext" -- 16
            ;;
        json)
            accept=$accept_json
            set -- "http://127.0.0.1:$port/json"
            ;;
        esac
        for server in $servers; do
            name=$server-w$workers-$test-c$conns-r$run
            case $server in
            goose*) WORKERS=$workers "$bin/$server" http "$port" >"$out/$name.log" 2>&1 & ;;
            *) WORKERS=$workers "$bin/$server" "$port" >"$out/$name.log" 2>&1 & ;;
            esac
            pid=$!
            tries=0
            until nc -z 127.0.0.1 "$port" 2>/dev/null; do
                tries=$((tries + 1))
                [ $tries -lt 100 ] || { echo "bench/run-macos.sh: $server isn't listening"; exit 1; }
                sleep 0.1
            done
            wrk="wrk -t $threads -c $conns --timeout 8"
            $wrk -H "$host" -H "$conn" -H "$accept" -d "$warmup" "$@" >/dev/null
            load1=$(sysctl -n vm.loadavg | awk '{print $2}')
            (while kill -0 $pid 2>/dev/null; do ps -o rss= -p $pid; sleep 1; done) >"$out/$name.rss" &
            mon=$!
            $wrk -H "$host" -H "$conn" -H "$accept" -d "$duration" --latency "$@" >"$out/$name.wrk"
            kill $mon 2>/dev/null
            wait $mon 2>/dev/null || true
            rss=$(sort -n "$out/$name.rss" | tail -1 | tr -d ' ')
            kill $pid
            wait $pid 2>/dev/null || true

            w=$out/$name.wrk
            rps=$(awk '/^Requests\/sec/ {print $2}' "$w")
            errors=$(awk '/Socket errors/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+,?$/) n += $i; print n }' "$w")
            non2xx=$(awk '/Non-2xx/ {print $NF}' "$w")
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$server" "$workers" "$test" \
                "$conns" "$run" "$rps" "${errors:-0}" "${non2xx:-0}" "$rss" "$load1" >>"$out/runs.tsv"
            tail -1 "$out/runs.tsv"
            sleep 2
        done
    done
done
echo "load after: $(sysctl -n vm.loadavg)" >>"$out/env.txt"
echo "$out"
