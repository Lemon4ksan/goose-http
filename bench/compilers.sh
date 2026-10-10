#!/bin/sh
# Builds the Goose server with each C compiler task 008 compares, into
# build/bench/goose-<variant><SUFFIX>:
#
#   gcc          gcc -O2, as scripts/build.sh builds it
#   clang        clang -O2
#   gcc-native   gcc -O2 -march=native, as the Rust servers are built
#
# SUFFIX tells builds of other source trees apart. GOOSE names the compiler,
# as for scripts/build.sh.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${OUT:-$root/build/bench}
suffix=${SUFFIX:-}
mkdir -p "$out"

build() {
    CC=$2 CFLAGS=$3 "$root/scripts/build.sh" >/dev/null
    cp "$root/build/server" "$out/goose-$1$suffix"
    echo "goose-$1$suffix: $($2 --version | head -1), $3"
}
build gcc gcc -O2
build clang clang -O2
build gcc-native gcc "-O2 -march=native"
