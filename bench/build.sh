#!/bin/sh
# Builds the servers bench/run.sh compares, in release mode, into
# build/bench/: goose (scripts/build.sh), may-minihttp, hyper, and odin-http,
# the library that gives wrk a monotonic clock (bench/wrk-monotonic.c), and
# the latency summarizer for h2load's log (bench/latency.c).
#
# Cargo's target directories and the odin-http checkout go under CACHE
# (~/.cache/goose-http-bench), on the Linux file system: cargo is slow on
# /mnt/c. Cargo runs from CACHE, so it reads no config file above the
# repository, such as a Windows ~/.cargo/config under /mnt/c/Users.
#
# GOOSE names the Goose compiler, as for scripts/build.sh. ODIN names the Odin
# compiler (default: odin on PATH), which must be ODIN_VERSION.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cache=${CACHE:-$HOME/.cache/goose-http-bench}
out=$root/build/bench
odin=${ODIN:-odin}
PATH=$HOME/.cargo/bin:$PATH

ODIN_VERSION=dev-2026-10
ODIN_HTTP_REPO=https://github.com/laytan/odin-http.git
ODIN_HTTP_COMMIT=fac113fbd828aad3d71479a534b5de4358b6a07b

mkdir -p "$cache" "$out"

"$root/scripts/build.sh"
cp "$root/build/server" "$out/goose"

# TechEmpower builds its Rust entries for the machine they run on.
for name in may-minihttp hyper; do
    (cd "$cache" && RUSTFLAGS="-C target-cpu=native" cargo build --release --locked \
        --manifest-path "$root/bench/$name/Cargo.toml" --target-dir "$cache/target-$name")
    cp "$cache/target-$name/release/bench-$name" "$out/$name"
done

"$odin" version | grep -q "$ODIN_VERSION" || {
    echo "bench/build.sh: odin-http needs Odin $ODIN_VERSION, not: $("$odin" version)"
    exit 1
}
if [ ! -d "$cache/deps/odin-http" ]; then
    git clone -q "$ODIN_HTTP_REPO" "$cache/deps/odin-http"
fi
git -C "$cache/deps/odin-http" fetch -q origin
git -C "$cache/deps/odin-http" checkout -q "$ODIN_HTTP_COMMIT"
# The flags odin-http's own comparison builds with (comparisons/empty-ok-all).
"$odin" build "$root/bench/odin-http" -collection:deps="$cache/deps" \
    -o:speed -disable-assert -no-bounds-check -out:"$out/odin-http"

${CC:-cc} -O2 -shared -fPIC "$root/bench/wrk-monotonic.c" -o "$out/wrk-monotonic.so"
${CC:-cc} -O2 "$root/bench/latency.c" -o "$out/latency"

ls -l "$out"
