#!/bin/sh
# Builds the servers bench/run.sh compares, in release mode, into
# build/bench/: goose (scripts/build.sh), may-minihttp, hyper, tokio,
# odin-http, dusty, and vanilla-epoll, the library that gives wrk a monotonic
# clock (bench/wrk-monotonic.c), and the latency summarizer for h2load's log
# (bench/latency.c).
#
# Cargo's target directories, the checkouts, V, and the copy of bench/dusty
# that zig builds go under CACHE (~/.cache/goose-http-bench), on the Linux
# file system: cargo is slow on /mnt/c, and zig 0.16 fetches packages into
# zig-pkg/ beside build.zig.zon, with no option to put them elsewhere. Cargo
# runs from CACHE, so it reads no config file above the repository, such as a
# Windows ~/.cargo/config under /mnt/c/Users.
#
# GOOSE names the Goose compiler, as for scripts/build.sh. ODIN names the Odin
# compiler (default: odin on PATH), which must be ODIN_VERSION, and ZIG the Zig
# compiler (default: zig on PATH), which must be ZIG_VERSION. V is built here,
# at the commits of HttpArena's vanilla-epoll image; it needs liburing-dev.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cache=${CACHE:-$HOME/.cache/goose-http-bench}
out=$root/build/bench
odin=${ODIN:-odin}
zig=${ZIG:-zig}
PATH=$HOME/.cargo/bin:$PATH

ODIN_VERSION=dev-2026-10
ODIN_HTTP_REPO=https://github.com/laytan/odin-http.git
ODIN_HTTP_COMMIT=fac113fbd828aad3d71479a534b5de4358b6a07b
ZIG_VERSION=0.16.0
# vanilla and the V that builds it, as HttpArena's vanilla-epoll Dockerfile
# pins them: V b99970bd bootstrapped from vc 2cbaf6bc with tccbin d6e7ac1b.
VANILLA_COMMIT=091c014a0191afd7e740b84f5599b9b1fc1fd914
V_COMMIT=b99970bd438a7bdcdfbe38f74d9364db801d5439
VC_COMMIT=2cbaf6bc2367937cd5f0b4ef923d1ef9aad613b3
TCCBIN_COMMIT=d6e7ac1b1bcc98aed734a6ecbfa8509f24606c74

mkdir -p "$cache" "$out"

"$root/scripts/build.sh"
cp "$root/build/server" "$out/goose"

# TechEmpower builds its Rust entries for the machine they run on, and
# HttpArena's tokio image does too.
for name in may-minihttp hyper tokio; do
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

# Fetches repository $1 at commit $2 into directory $3, alone.
fetch() {
    if [ "$(git -C "$3" rev-parse HEAD 2>/dev/null)" != "$2" ]; then
        rm -rf "$3"
        git init -q "$3"
        git -C "$3" fetch -q --depth 1 "$1" "$2"
        git -C "$3" checkout -q FETCH_HEAD
    fi
}

"$zig" version | grep -qx "$ZIG_VERSION" || {
    echo "bench/build.sh: dusty needs Zig $ZIG_VERSION, not: $("$zig" version)"
    exit 1
}
rm -rf "$cache/app-dusty"
mkdir -p "$cache/app-dusty"
cp -r "$root/bench/dusty/." "$cache/app-dusty/"
# The target and CPU of HttpArena's dusty image.
(cd "$cache/app-dusty" && "$zig" build --cache-dir "$cache/zig-cache" \
    --global-cache-dir "$cache/zig-global" --prefix "$cache/dusty-out" \
    -Dtarget=x86_64-linux-musl -Dcpu=x86_64_v3+aes+pclmul+adx --release=fast)
cp "$cache/dusty-out/bin/bench-dusty" "$out/dusty"

v=$cache/deps/v
if [ "$(git -C "$v" rev-parse HEAD 2>/dev/null)" != "$V_COMMIT" ] || [ ! -x "$v/v" ]; then
    fetch https://github.com/vlang/v "$V_COMMIT" "$v"
    fetch https://github.com/vlang/vc "$VC_COMMIT" "$v/vc"
    fetch https://github.com/vlang/tccbin "$TCCBIN_COMMIT" "$v/thirdparty/tcc"
    # local=1 builds with the vc and tcc above instead of pulling their heads.
    make -C "$v" local=1
fi
fetch https://github.com/enghitalo/vanilla "$VANILLA_COMMIT" "$cache/vmodules/vanilla"
# HttpArena's vanilla-epoll flags, without -d vanilla_tls, which only its
# TLS listener needs.
VMODULES=$cache/vmodules "$v/v" -prod -gc none "$root/bench/vanilla-epoll" \
    -o "$out/vanilla-epoll"

${CC:-cc} -O2 -shared -fPIC "$root/bench/wrk-monotonic.c" -o "$out/wrk-monotonic.so"
${CC:-cc} -O2 "$root/bench/latency.c" -o "$out/latency"

ls -l "$out"
