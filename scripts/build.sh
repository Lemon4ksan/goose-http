#!/bin/sh
# Builds the server into build/server with goose build.
#
# GOOSE names the compiler (default: goose on PATH). CC picks the C compiler
# (default gcc, which builds a faster server than clang: task 008). LOOP
# picks the event loop: epoll (src/main.goose, the default), or uring
# (src/main_uring.goose), which needs liburing (apt liburing-dev) and Linux
# 6.1. Each root file's sidecar (src/main.build, src/main_uring.build) names
# the C in shim/ it links.
#
# --standalone puts the runtime in the program's C file, as one translation
# unit, so the C compiler can inline the runtime's functions into the server.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
goose=${GOOSE:-goose}

case ${LOOP:-epoll} in
epoll) main=main ;;
uring) main=main_uring ;;
*) echo "scripts/build.sh: LOOP is epoll or uring"; exit 2 ;;
esac
if [ "$main" = main_uring ] && [ "$(uname -s)" != Linux ]; then
    echo "scripts/build.sh: LOOP=uring needs Linux"
    exit 2
fi

mkdir -p "$root/build"
"$goose" build --cc "${CC:-gcc}" --standalone -o "$root/build/server" "$root/src/$main.goose"
