#!/bin/sh
# Runs each src/test_*.goose through TinyCC. Each one asserts what it tests,
# so the first failure stops the run.
#
# GOOSE names the compiler (default: goose on PATH).
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
for t in "$root"/src/test_*.goose; do
    "${GOOSE:-goose}" "$t"
done
