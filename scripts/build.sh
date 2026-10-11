#!/bin/sh
# Builds the benchmark server, server/, into build/server with goose build.
#
# GOOSE names the compiler (default: goose on PATH). CC picks the C compiler
# (default gcc, which builds a faster server than clang: task 008). The
# server has both of the package's loops, and LOOP picks the one it serves
# with when its own LOOP isn't set at run time: uring (server/server.goose,
# http::serve, the default on Linux), which needs liburing (apt liburing-dev)
# on Linux and runs over an emulation on kqueue on macOS, or epoll
# (server/server_epoll.goose, http::serve_epoll, the default on macOS, over
# kqueue). The package's sidecar, http.build, names
# the C in shim/ it links on each platform.
#
# On Windows, in Git Bash, the loop is iocp, http::serve over I/O completion
# ports (shim/iocp.c), and CC defaults to msvc.
#
# --standalone puts the runtime in the program's C file, as one translation
# unit, so the C compiler can inline the runtime's functions into the server.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
goose=${GOOSE:-goose}

os=$(uname -s)
case $os in
MINGW* | MSYS*) os=Windows loop=${LOOP:-iocp} cc=${CC:-msvc} ;;
Linux) loop=${LOOP:-uring} cc=${CC:-gcc} ;;
*) loop=${LOOP:-epoll} cc=${CC:-gcc} ;;
esac
case $loop in
epoll) main=server_epoll ;;
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
# goose build on Linux never sees a change to the shim's C (docs/goose-findings.md), so
# the stamp that says the shim is built goes first: the stamps of the local packages
# whose link list has the shim's objects.
for rsp in "${GOOSE_HOME:-$HOME/.goose}"/build/pkg/local/*/*/link-*.rsp; do
    if [ -f "$rsp" ] && grep -q -e '/net\.o' -e '/net_win\.obj' -e '/kqueue\.o' "$rsp"; then
        rm -f "$(dirname "$rsp")/stamp"
    fi
done
"$goose" build --cc "$cc" --standalone -o "$root/build/server" "$root/server/$main.goose"
