#!/bin/sh
# Runs each test/test_*.goose, the package's unit tests, and each
# server/test_*.goose, the benchmark server's, through TinyCC. Each one asserts
# what it tests, so the first failure stops the run. TinyCC can't run threads,
# so a test with a thread_fn is built with goose build into build/ and run
# from there.
#
# GOOSE names the compiler (default: the pinned release, scripts/goose.sh), and CC the C compiler for
# the tests with threads, as for build.sh.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/scripts/goose.sh"
goose=$GOOSE
case $(uname -s) in
MINGW* | MSYS*) cc=${CC:-msvc} exe=.exe ;;
*) cc=${CC:-gcc} exe= ;;
esac
mkdir -p "$root/build"
for t in "$root"/test/test_*.goose "$root"/server/test_*.goose; do
    if grep -q '^thread_fn' "$t"; then
        out=$root/build/$(basename "$t" .goose)
        "$goose" build --cc "$cc" -o "$out" "$t"
        "$out$exe"
    else
        "$goose" "$t"
    fi
done
