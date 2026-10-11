#!/bin/sh
# Times http::parse alone: each bench/parse/*.goose parses one request 10 M
# times, built with message.goose by goose -O2 and CC (default cc) with
# CFLAGS (default -O2). Prints instructions per parse (perf stat, user code)
# and the best of 5 runs in ns per parse, on CPU 2.
#
#   bench/parse.sh            (GOOSE as for scripts/build.sh; CPU 2)
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
goose=${GOOSE:-goose}
cc=${CC:-cc}
cflags=${CFLAGS:--O2}
cpu=${CPU:-2}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Imports resolve from the root file's directory. message.goose is namespace
# http, and needs none of the package's other files.
cp "$root/message.goose" "$tmp/http.goose"
cp "$root"/bench/parse/*.goose "$tmp"
printf 'request\tinstructions/parse\tns/parse\n'
for f in "$root"/bench/parse/*.goose; do
    p=$(basename "$f" .goose)
    "$goose" -O2 -o "$tmp/$p.c" --standalone "$tmp/$p.goose" >/dev/null
    # shellcheck disable=SC2086 # CFLAGS is a list of flags
    $cc $cflags "$tmp/$p.c" -o "$tmp/$p" -lm -pthread
    n=$(taskset -c "$cpu" perf stat -x, -e instructions:u "$tmp/$p" 2>&1 >/dev/null |
        awk -F, '/instructions/ {print $1}')
    best=
    for r in 1 2 3 4 5; do
        t0=$(date +%s%N)
        taskset -c "$cpu" "$tmp/$p" >/dev/null
        t1=$(date +%s%N)
        t=$(((t1 - t0) / 100000))
        if [ -z "$best" ] || [ "$t" -lt "$best" ]; then best=$t; fi
    done
    printf '%s\t%d\t%d.%02d\n' "$p" $((n / 10000000)) $((best / 100)) $((best % 100))
done
