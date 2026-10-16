#!/bin/sh
# Times reads from the store, http.store: bench/store/reads.goose built by
# goose build -O2 with the platform's cc, then run, on CPU 2 under taskset
# where there is one. Prints each way's best, median, and worst ns per read
# of 7 rounds of 10 M reads; reads.goose says what each way is.
#
#   bench/store.sh            (GOOSE as for scripts/build.sh; CPU 2)
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/scripts/goose.sh"
out=$root/build/bench/store
mkdir -p "$out"
"$GOOSE" build -O2 -o "$out/reads" "$root/bench/store/reads.goose" >"$out/build.log" 2>&1 ||
    { cat "$out/build.log"; exit 1; }
if command -v taskset >/dev/null; then
    taskset -c "${CPU:-2}" "$out/reads"
else
    "$out/reads"
fi
