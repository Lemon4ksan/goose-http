#!/bin/sh
# Builds the server into build/server with goose build.
#
# GOOSE names the compiler (default: goose on PATH). CC picks the C compiler
# (default gcc, which builds a faster server than clang: task 008). LOOP
# picks the event loop: uring (src/main_uring.goose, the default on Linux),
# which needs liburing (apt liburing-dev) and Linux 6.1, or epoll
# (src/main.goose, the only loop on macOS, over kqueue). Each root file's
# sidecar (src/main.build, src/main_uring.build) names the C in shim/ it
# links.
#
# On Windows, in Git Bash, the loop is iocp, src/main_uring.goose's loop over
# I/O completion ports (shim/iocp.c), and CC defaults to msvc.
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
epoll) main=main ;;
uring) main=main_uring ;;
iocp) main=main_uring ;;
*) echo "scripts/build.sh: LOOP is epoll, uring, or iocp"; exit 2 ;;
esac
if [ "$loop" = uring ] && [ "$os" != Linux ]; then
    echo "scripts/build.sh: LOOP=uring needs Linux"
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
"$goose" build --cc "$cc" --standalone -o "$root/build/server" "$root/src/$main.goose"
