#!/bin/sh
# Builds the benchmark server, server/, into build/server with goose build.
#
# GOOSE names the compiler (default: the pinned release, scripts/goose.sh). CC picks the C compiler
# (default gcc, which builds a faster server than clang: task 008). The
# server has both of the package's loops, and LOOP picks the one it serves
# with when its own LOOP isn't set at run time: uring (server/server.goose,
# http::serve, the default on Linux), which needs liburing (apt liburing-dev)
# on Linux and runs over an emulation on kqueue on macOS, or epoll
# (server/server_epoll.goose, http::serve_epoll, the default on macOS, over
# kqueue). TLS=1 builds the epoll server with its TLS listener instead
# (server/server_tls.goose), which links OpenSSL (apt libssl-dev); the others
# serve no TLS and don't map it. The package's sidecar, http.build, names
# the C in shim/ it links on each platform.
#
# On Windows, in Git Bash, the loop is iocp, http::serve over I/O completion
# ports (shim/iocp.c), and CC defaults to msvc.
#
# --standalone puts the runtime in the program's C file, as one translation
# unit, so the C compiler can inline the runtime's functions into the server.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/scripts/goose.sh"
goose=$GOOSE

os=$(uname -s)
case $os in
MINGW* | MSYS*) os=Windows loop=${LOOP:-iocp} cc=${CC:-msvc} ;;
Linux) loop=${LOOP:-uring} cc=${CC:-gcc} ;;
*) loop=${LOOP:-epoll} cc=${CC:-gcc} ;;
esac
case $loop in
epoll) main=server_epoll; [ "${TLS:-}" != 1 ] || main=server_tls ;;
uring | iocp) main=server ;;
*) echo "scripts/build.sh: LOOP is epoll, uring, or iocp"; exit 2 ;;
esac
if [ "$loop" = uring ] && [ "$os" = Windows ]; then
    echo "scripts/build.sh: LOOP=uring is LOOP=iocp on Windows"
    exit 2
fi
if [ "$loop" = iocp ] && [ "$os" != Windows ]; then
    echo "scripts/build.sh: LOOP=iocp needs Windows"
    exit 2
fi
if [ "$loop" = epoll ] && [ "$os" = Windows ]; then
    echo "scripts/build.sh: LOOP=epoll needs Linux or macOS"
    exit 2
fi

mkdir -p "$root/build"
"$goose" build --cc "$cc" --standalone -o "$root/build/server" "$root/server/$main.goose"
