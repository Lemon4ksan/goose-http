#!/bin/sh
# Splits the idle memory of bench/rest's Goose server by source (task 025):
# for each tier and JSON way, the server with 1 and then 2 workers on the
# epoll loop, no request sent, /proc/PID/smaps read 3 s after it listens and
# its Rss summed by mapping:
#
#   data stacks   the runtime's 2 GB reservations, where each thread keeps
#                 its arrays, the globals a worker copies among them
#   arenas        glibc's heap and thread arenas (64 MB reservations)
#   large malloc  other anonymous mappings: malloc's mmap'ed blocks, such
#                 as the packet thread_spawn hands a worker its globals in
#   thread stacks the 8 MB stacks of the threads
#   files         the binary and the libraries
#
# One worker's share is the 2-worker figure less the 1-worker one. Beside it,
# what the worker's globals hold, from the loader's REST_LENS lines and each
# record's size in the generated C: records (their strings and indexes
# included) and templates. Writes OUT/memory.tsv and prints it.
#
#   bench/rest-memory.sh    (DATA build/rest, OUT bench/results/<date>-rest-memory,
#                            SERVER_CPUS 0-3, PORT 29381, TIERS "a b c")
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/scripts/goose.sh"
goose=$GOOSE
data=${DATA:-$root/build/rest}
out=${OUT:-$root/bench/results/$(date +%F)-rest-memory}
cpus=${SERVER_CPUS:-0-3}
port=${PORT:-29381}
tiers=${TIERS:-a b c}
work=$(mktemp -d)
pid=
trap '[ -z "$pid" ] || kill "$pid" 2>/dev/null; rm -rf "$work"' EXIT
mkdir -p "$out"

"$goose" build --cc gcc --standalone -o "$work/rest" "$root/bench/rest/goose/rest.goose" >"$work/build.log" 2>&1 ||
    { cat "$work/build.log"; exit 1; }
c=$(ls -t "${GOOSE_HOME:-$HOME/.goose}"/build/prog/rest-*/rest.c | head -1)

# Each record type's size, from the C: an array of that many bytes per type,
# read back with nm.
types="Str Item User Org Project Person Entry Staffer Service Client Visit Note Booking Shift"
{
    echo "#define main rest_main"
    echo "#include \"$c\""
    for t in $types; do echo "char sz_$t[sizeof(${t}_g)];"; done
} >"$work/sizes.c"
gcc -w -c -o "$work/sizes.o" "$work/sizes.c"
nm -S "$work/sizes.o" | awk '$4 ~ /^sz_/ { sub(/^sz_/, "", $4); print $4, strtonum("0x" $2) }' >"$work/sizes"
printf 'u8 1\ni64 8\n' >>"$work/sizes"

# Rss in KB by source, for process $1: data, arenas, large, stacks, files.
split_rss() {
    awk '
        /^[0-9a-f]+-[0-9a-f]+ / {
            split($1, r, "-")
            size = (strtonum("0x" r[2]) - strtonum("0x" r[1])) / 1024
            path = NF >= 6 ? $6 : ""
            if (path ~ /^\// && path !~ /^\/(dev|memfd)/) kind = "files"
            else if (path == "[heap]") kind = "arenas"
            else if (path == "[stack]" || size == 8192 || size == 8196) kind = "stacks"
            else if (size >= 1048576) kind = "data"
            else if (size == 65536 || size == 131072) kind = "arenas"
            else if (path == "") kind = "large"
            else kind = "files"
            next
        }
        /^Rss:/ { rss[kind] += $2 }
        END { printf "%d\t%d\t%d\t%d\t%d\n", rss["data"], rss["arenas"], rss["large"], rss["stacks"], rss["files"] }
    ' "/proc/$1/smaps"
}

# Starts the server with $1 workers on tier $2, JSON way $3, and waits until
# it listens; its output goes to $work/log.
start() {
    REST_DATA=$data TIER=$2 JSON=$3 WORKERS=$1 LOOP=epoll REST_LENS=1 \
        taskset -c "$cpus" "$work/rest" "$port" >"$work/log" 2>&1 &
    pid=$!
    until nc -z 127.0.0.1 "$port" 2>/dev/null; do
        kill -0 "$pid" 2>/dev/null || { cat "$work/log"; exit 1; }
        sleep 0.1
    done
    sleep 3
}

stop() {
    kill "$pid"
    wait "$pid" 2>/dev/null || true
    pid=
    while nc -z 127.0.0.1 "$port" 2>/dev/null; do sleep 0.1; done
}

printf 'tier\tjson\tworkers\tdata_kb\tarenas_kb\tlarge_kb\tstacks_kb\tfiles_kb\tvmrss_kb\trecords_kb\ttemplates_kb\n' >"$out/memory.tsv"
for tier in $tiers; do
    for json in serialize template; do
        for n in 1 2; do
            start "$n" "$tier" "$json"
            parts=$(split_rss "$pid")
            vmrss=$(awk '/^VmRSS:/ { print $2 }' "/proc/$pid/status")
            globals=$(awk 'NR == FNR { size[$1] = $2; next }
                /^lens: / { kb[$2] += $5 * size[$4] / 1024 }
                END { printf "%d\t%d", kb["records"], kb["templates"] }' "$work/sizes" "$work/log")
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$tier" "$json" "$n" "$parts" "$vmrss" "$globals" >>"$out/memory.tsv"
            stop
        done
    done
done

cat >"$out/README.md" <<EOF
Idle memory of bench/rest's Goose server split by source, $(date +%F), by
bench/rest-memory.sh at $(git -C "$root" rev-parse --short HEAD)$(git -C "$root" diff --quiet || echo ' (modified)'):
$(uname -r), $(gcc --version | head -1), Goose $(git -C "$(dirname "$(command -v "$goose")")" rev-parse --short HEAD 2>/dev/null || echo unknown).
Each tier and JSON way with 1 and 2 workers, epoll loop, CPUs $cpus, Rss from
/proc/PID/smaps 3 s after the server listened, no request sent, one run each.
records_kb and templates_kb are what one worker's globals hold, from the
loader's REST_LENS lines and the record sizes in the generated C.
EOF
column -t "$out/memory.tsv"
