#!/bin/sh
# Runs each test/test_*.goose, the package's unit tests, and each
# server/test_*.goose, the benchmark server's, through TinyCC. Each one asserts
# what it tests, so the first failure stops the run.
#
# GOOSE names the compiler (default: goose on PATH).
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
for t in "$root"/test/test_*.goose "$root"/server/test_*.goose; do
    "${GOOSE:-goose}" "$t"
done
