#!/bin/sh
# Times HPACK alone (hpack.goose): bench/hpack/hpack.goose decodes and encodes
# request and response field blocks and Huffman-codes 1 KB, built by goose -O2
# and CC (default cc) with CFLAGS (default -O2), and prints the best of 5 runs
# of each in ns. Runs on Linux and macOS; on Linux it pins to CPU (default 2).
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
