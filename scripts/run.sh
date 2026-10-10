#!/bin/sh
# Compiles and runs src/main.goose in process through TinyCC, passing the
# arguments on to the program. TinyCC can't place thread-local storage, so a
# program that spawns workers needs scripts/build.sh instead.
#
# GOOSE names the compiler (default: goose on PATH). The compiler reads
# GOOSE_STDLIB itself.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
exec "${GOOSE:-goose}" -D_GNU_SOURCE --include "$root/shim/net.h" "$root/src/main.goose" -- "$@"
