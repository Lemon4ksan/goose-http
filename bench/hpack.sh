#!/bin/sh
# Times HPACK alone (hpack.goose): bench/hpack/hpack.goose decodes and encodes
# request and response field blocks and Huffman-codes 1 KB, built by goose -O2
# and CC (default cc) with CFLAGS (default -O2), and prints the best of 5 runs
# of each in ns. Runs on Linux and macOS; on Linux it pins to CPU (default 2).
# With PERF=1, on Linux, it then runs each case alone under perf stat, and
# prints its user-mode instructions and cycles per block or byte, over all 5
# runs and the case's setup.
#
#   bench/hpack.sh            (GOOSE as for scripts/build.sh)
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/scripts/goose.sh"
goose=$GOOSE
cc=${CC:-cc}
cflags=${CFLAGS:--O2}
cpu=${CPU:-2}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Imports resolve from the root file's directory. hpack.goose is namespace
# http, and needs none of the package's other files.
cp "$root/hpack.goose" "$tmp/http.goose"
cp "$root/bench/hpack/hpack.goose" "$tmp/main.goose"
"$goose" -O2 -o "$tmp/main.c" --standalone "$tmp/main.goose" >/dev/null
# shellcheck disable=SC2086 # CFLAGS is a list of flags
$cc $cflags "$tmp/main.c" -o "$tmp/hpack" -lm -pthread
if command -v taskset >/dev/null; then
    taskset -c "$cpu" "$tmp/hpack"
else
    "$tmp/hpack"
fi
[ "${PERF:-}" = 1 ] || exit 0
printf 'case\tinstructions:u\tcycles:u\tper\n'
for c in "decode request, first" "decode request, later" "encode response, first" \
    "encode response, later" "Huffman decode, 1 KB" "Huffman encode, 1 KB"; do
    CASE=$c perf stat -x, -e instructions:u,cycles:u -o "$tmp/perf" \
        taskset -c "$cpu" "$tmp/hpack" >"$tmp/out"
    units=$(awk -F'\t' 'NF >= 5 {print $5}' "$tmp/out")
    unit=$(awk -F'\t' 'NF >= 5 {print $3}' "$tmp/out")
    awk -F, -v c="$c" -v n="$units" -v u="$unit" '
        /instructions:u/ {i = $1} /cycles:u/ {y = $1}
        END {printf "%s\t%.1f\t%.1f\t%s\n", c, i / n, y / n, u}' "$tmp/perf"
done
