#!/bin/sh
# Builds the Goose server with each C compiler task 008 compares, into
# build/bench/goose-<variant><SUFFIX>:
#
#   gcc          gcc -O2, as scripts/build.sh builds it
#   clang        clang -O2
#   gcc-native   gcc -O2 -march=native, as the Rust servers are built
#
# goose build takes C flags only from the sidecar, so this writes the C itself
# and compiles it with shim/net.c, as goose build does. SUFFIX tells builds of
# other source trees apart. GOOSE names the compiler, as for scripts/build.sh.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${OUT:-$root/build/bench}
suffix=${SUFFIX:-}
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
"${GOOSE:-goose}" -O2 -o "$tmp/server.c" --standalone "$root/src/main.goose" >/dev/null

build() {
    # shellcheck disable=SC2086 # $3 is a list of flags
    $2 $3 "$tmp/server.c" "$root/shim/net.c" -o "$out/goose-$1$suffix" -lm -pthread
    echo "goose-$1$suffix: $($2 --version | head -1), $3"
}
build gcc gcc -O2
build clang clang -O2
build gcc-native gcc "-O2 -march=native"
