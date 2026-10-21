#!/bin/sh
# Builds the servers bench/run.sh compares, in release mode, into
# build/bench/: goose and goose-uring (scripts/build.sh with each loop),
# may-minihttp, hyper, tokio, odin-http, dusty, and vanilla-epoll; task 005's
# io_uring servers, xitca-web, zix, zeemo, libreactorng, vanilla-io_uring, and tina,
# which bench/run.sh runs only when SERVERS names them, as goose-uring; the
# library that gives wrk a monotonic clock (bench/wrk-monotonic.c); and the
# latency summarizer for h2load's log (bench/latency.c). ONLY=goose builds the
# Goose servers and the two helpers alone, to measure Goose beside competitor
# cells from an earlier run.
#
# Cargo's target directories, the checkouts, V, libreactorng, and the copies
# of the Zig projects that zig builds go under CACHE
# (~/.cache/goose-http-bench), on the Linux file system: cargo is slow on
# /mnt/c, and zig 0.16 fetches packages into zig-pkg/ beside build.zig.zon,
# with no option to put them elsewhere. Cargo runs from CACHE, so it reads no
# config file above the repository, such as a Windows ~/.cargo/config under
# /mnt/c/Users.
#
# GOOSE names the Goose compiler, as for scripts/build.sh. ODIN names the Odin
# compiler (default: odin on PATH), which must be ODIN_VERSION, and ZIG the Zig
# compiler (default: zig on PATH), which must be ZIG_VERSION. V is built here,
# at the commits of HttpArena's vanilla-epoll image; it needs liburing-dev.
# libreactorng needs autoconf, automake, libtool, and libltdl-dev.
#
# On aarch64 (Docker on Apple Silicon, task 012), the Zig servers build for
# aarch64-linux-musl and this machine's CPU (apple_m1 on Apple's), and V takes tccbin's arm64
# branch, for its libgc.a; V's Makefile bootstraps with gcc on arm64.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cache=${CACHE:-$HOME/.cache/goose-http-bench}
out=$root/build/bench
odin=${ODIN:-odin}
zig=${ZIG:-zig}

ODIN_VERSION=dev-2026-10
ODIN_HTTP_REPO=https://github.com/laytan/odin-http.git
ODIN_HTTP_COMMIT=fac113fbd828aad3d71479a534b5de4358b6a07b
TINA_REPO=https://github.com/pmbanugo/tina.git
TINA_COMMIT=a2e8d4dc53394dd6772d08e79a41d6b56ba3a65e
ZIG_VERSION=0.16.0
# vanilla and the V that builds it, as HttpArena's vanilla-epoll Dockerfile
# pins them: V b99970bd bootstrapped from vc 2cbaf6bc with tccbin d6e7ac1b.
VANILLA_COMMIT=091c014a0191afd7e740b84f5599b9b1fc1fd914
V_COMMIT=b99970bd438a7bdcdfbe38f74d9364db801d5439
VC_COMMIT=2cbaf6bc2367937cd5f0b4ef923d1ef9aad613b3
TCCBIN_COMMIT=d6e7ac1b1bcc98aed734a6ecbfa8509f24606c74
# tccbin's thirdparty-linux-arm64 head (2024-07-08), for its libgc.a.
TCCBIN_ARM64_COMMIT=125ad2e1153c7cb86f19ac4aa070063d18504462
CADDY_VERSION=2.10.2
CADDY_SHA256=5c218bc34c9197369263da7e9317a83acdbd80ef45d94dca5eff76e727c67cdd
# As HttpArena's libreactorng Dockerfile pins it.
LIBREACTORNG_COMMIT=7a65f8b108f62f2531db952b0f87cf5f34a24b3c

mkdir -p "$cache" "$out"

LOOP=uring "$root/scripts/build.sh"
cp "$root/build/server" "$out/goose-uring"
LOOP=epoll "$root/scripts/build.sh"
cp "$root/build/server" "$out/goose"
${CC:-cc} -O2 -shared -fPIC "$root/bench/wrk-monotonic.c" -o "$out/wrk-monotonic.so"
${CC:-cc} -O2 "$root/bench/latency.c" -o "$out/latency"
${CC:-cc} -O2 "$root/bench/loader.c" -o "$out/loader"
if [ "${ONLY:-}" = goose ]; then
    ls -l "$out"
    exit 0
fi

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

# Tina's production build (docs/guides/odin_compilation.md): bounds checks
# stay on, which it requires, and its own assertions go off.
fetch "$TINA_REPO" "$TINA_COMMIT" "$cache/deps/tina"
"$odin" build "$root/bench/tina" -collection:deps="$cache/deps" \
    -o:speed -define:TINA_ASSERTS=false -out:"$out/tina"

"$zig" version | grep -qx "$ZIG_VERSION" || {
    echo "bench/build.sh: dusty, zix, and zeemo need Zig $ZIG_VERSION, not: $("$zig" version)"
    exit 1
}
# Builds the Zig project bench/$1 with zig build flags $2..., from a copy in
# CACHE, into build/bench/$1.
zig_build() {
    name=$1
    shift
    rm -rf "$cache/app-$name"
    mkdir -p "$cache/app-$name"
    cp -r "$root/bench/$name/." "$cache/app-$name/"
    (cd "$cache/app-$name" && "$zig" build --cache-dir "$cache/zig-cache" \
        --global-cache-dir "$cache/zig-global" --prefix "$cache/$name-out" "$@")
    cp "$cache/$name-out/bin/bench-$name" "$out/$name"
}
# The targets and CPUs of HttpArena's images. zeemo's names no CPU, so it
# builds for the baseline CPU.
# On Apple Silicon under Docker Desktop, the VM hides the CPU's part number,
# and Zig's native resolves to generic arm64, without the M1's features.
case $(uname -m) in
aarch64)
    target=aarch64-linux-musl cpu=native
    grep -q '^CPU implementer.*0x61' /proc/cpuinfo && cpu=apple_m1
    ;;
*) target=x86_64-linux-musl cpu=x86_64_v3+aes+pclmul+adx ;;
esac
zig_build dusty -Dtarget=$target -Dcpu=$cpu --release=fast
zig_build zix -Dtarget=$target -Dcpu=$cpu --release=fast
zig_build zeemo -Dtarget=$target --release=fast

v=$cache/deps/v
if [ "$(git -C "$v" rev-parse HEAD 2>/dev/null)" != "$V_COMMIT" ] || [ ! -x "$v/v" ]; then
    fetch https://github.com/vlang/v "$V_COMMIT" "$v"
    fetch https://github.com/vlang/vc "$VC_COMMIT" "$v/vc"
    case $(uname -m) in
    aarch64) fetch https://github.com/vlang/tccbin "$TCCBIN_ARM64_COMMIT" "$v/thirdparty/tcc" ;;
    *) fetch https://github.com/vlang/tccbin "$TCCBIN_COMMIT" "$v/thirdparty/tcc" ;;
    esac
    # local=1 builds with the vc and tcc above instead of pulling their heads.
    make -C "$v" local=1
fi
fetch https://github.com/enghitalo/vanilla "$VANILLA_COMMIT" "$cache/vmodules/vanilla"
# HttpArena's vanilla-epoll flags, without -d vanilla_tls, which only its
# TLS listener needs.
VMODULES=$cache/vmodules "$v/v" -prod -gc none "$root/bench/vanilla-epoll" \
    -o "$out/vanilla-epoll"
# HttpArena's vanilla-io_uring flags: V's default GC, and again without
# -d vanilla_tls.
VMODULES=$cache/vmodules "$v/v" -prod -d vanilla_io_uring "$root/bench/vanilla-io_uring" \
    -o "$out/vanilla-io_uring"

# libreactorng as HttpArena's image builds it: patched, configured with
# -O3 -march=native, and installed, here under CACHE. The install is a static
# library of LTO objects, so gcc links the server.
fetch https://github.com/fredrikwidlund/libreactorng "$LIBREACTORNG_COMMIT" \
    "$cache/deps/libreactorng"
rm -rf "$cache/libreactorng-src" "$cache/libreactorng"
cp -r "$cache/deps/libreactorng" "$cache/libreactorng-src"
git -C "$cache/libreactorng-src" apply "$root/bench/libreactorng/connection-close.patch"
(cd "$cache/libreactorng-src" && ./autogen.sh &&
    ./configure --prefix="$cache/libreactorng" CFLAGS="-O3 -march=native" &&
    make && make install)
gcc -O3 -march=native -Wall -Wextra -pthread "$root/bench/libreactorng/server.c" \
    -o "$out/libreactorng" \
    $(PKG_CONFIG_PATH=$cache/libreactorng/lib/pkgconfig pkg-config --libs --cflags libreactor)

# Caddy for bench/files.sh: its x86-64 release, checked against the hash it
# had when pinned. nginx is the system's (apt nginx).
if [ "$(uname -m)" = x86_64 ]; then
    if [ "$(sha256sum <"$cache/caddy.tgz" 2>/dev/null | cut -d' ' -f1)" != "$CADDY_SHA256" ]; then
        curl -sSLf -o "$cache/caddy.tgz" \
            "https://github.com/caddyserver/caddy/releases/download/v$CADDY_VERSION/caddy_${CADDY_VERSION}_linux_amd64.tar.gz"
        [ "$(sha256sum <"$cache/caddy.tgz" | cut -d' ' -f1)" = "$CADDY_SHA256" ] ||
            { echo "bench/build.sh: caddy.tgz doesn't match CADDY_SHA256"; exit 1; }
    fi
    tar -xzf "$cache/caddy.tgz" -C "$out" caddy
fi

ls -l "$out"
