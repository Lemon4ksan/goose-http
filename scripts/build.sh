#!/bin/sh
# Compiles src/main.goose to build/server through generated C.
#
# GOOSE names the compiler (default: goose on PATH). The compiler reads
# GOOSE_STDLIB itself. CC and CFLAGS pick the C compiler and its flags.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
goose=${GOOSE:-goose}
cc=${CC:-cc}
cflags=${CFLAGS:--O2}

mkdir -p "$root/build"
"$goose" -O2 -o "$root/build/server.c" --standalone -D_GNU_SOURCE \
    --include "$root/shim/net.h" "$root/src/main.goose"
# shellcheck disable=SC2086 # CFLAGS is a list of flags
$cc $cflags "$root/build/server.c" -o "$root/build/server" -lm -pthread
