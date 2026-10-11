#!/bin/sh
# Compiles the server to build/server through generated C.
#
# GOOSE names the compiler (default: goose on PATH). The compiler reads
# GOOSE_STDLIB itself. CC and CFLAGS pick the C compiler and its flags. LOOP
# picks the event loop: epoll (src/main.goose, the default), or uring
# (src/main_uring.goose), which needs liburing (apt liburing-dev) and Linux 6.1.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
goose=${GOOSE:-goose}
cc=${CC:-cc}
cflags=${CFLAGS:--O2}

case ${LOOP:-epoll} in
epoll) main=main; uring=; libs= ;;
uring) main=main_uring; uring="--include $root/shim/uring.h"; libs=-luring ;;
*) echo "scripts/build.sh: LOOP is epoll or uring"; exit 2 ;;
esac

mkdir -p "$root/build"
# shellcheck disable=SC2086 # uring is empty or an option and its argument
"$goose" -O2 -o "$root/build/server.c" --standalone -D_GNU_SOURCE \
    --include "$root/shim/net.h" $uring "$root/src/$main.goose"
# shellcheck disable=SC2086 # CFLAGS is a list of flags
$cc $cflags "$root/build/server.c" -o "$root/build/server" $libs -lm -pthread
