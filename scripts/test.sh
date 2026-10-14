#!/bin/sh
# Runs every test this repository has, and fails on the first failure: the
# typecheck of each root file, the unit tests through TinyCC
# (scripts/test-unit.sh), then each loop's build of the server
# (scripts/build.sh) with scripts/test-http.sh against it,
# scripts/test-echo.sh, and scripts/test-examples.sh, which builds each
# example and requests each of its routes on port 8080.
#
# The loops are uring and epoll on Linux and macOS, where the uring build is
# also tested over the emulation on epoll it falls back to (LOOP=uring-epoll)
# on Linux, and iocp on Windows, in Git Bash. On Windows the typecheck is the
# Windows compiler's, which no other step runs there.
#
# GOOSE names the compiler, and CC the C compiler, as for build.sh; PORT and
# WORKERS pass through to the test scripts.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
goose=${GOOSE:-goose}
os=$(uname -s)
case $os in
MINGW* | MSYS*) loops=iocp ;;
*) loops="uring epoll" ;;
esac

step() {
    echo
    echo "== $*"
}

# macOS holds a closed client's port in TIME_WAIT for 30 s, and the next
# script's 10,000 connections fail with EADDRNOTAVAIL until most are gone
# (docs/development.md, "macOS"). Waits for that, up to 60 s.
drain() {
    [ "$os" = Darwin ] || return 0
    i=0
    while [ "$(netstat -an -p tcp | grep -c TIME_WAIT)" -gt 100 ] && [ $i -lt 60 ]; do
        sleep 1
        i=$((i + 1))
    done
}

for f in "$root"/server/server.goose "$root"/server/server_epoll.goose \
    "$root"/test/test_*.goose "$root"/server/test_*.goose \
    "$root"/examples/hello/hello.goose "$root"/examples/routes/routes.goose \
    "$root"/examples/api/api.goose "$root"/examples/upload/upload.goose \
    "$root"/examples/later/later.goose "$root"/examples/files/files.goose \
    "$root"/examples/c/app.goose; do
    step "check ${f#"$root"/}"
    "$goose" --check "$f"
done

step "test-unit.sh"
"$root/scripts/test-unit.sh"

for loop in $loops; do
    step "LOOP=$loop build.sh"
    LOOP=$loop "$root/scripts/build.sh"
    drain
    step "test-http.sh, $loop loop"
    LOOP=$loop "$root/scripts/test-http.sh"
    if [ "$loop" = uring ] && [ "$os" = Linux ]; then
        drain
        step "test-http.sh, uring loop over epoll"
        LOOP=uring-epoll "$root/scripts/test-http.sh"
    fi
done

drain
step "test-echo.sh"
"$root/scripts/test-echo.sh"

step "test-examples.sh"
"$root/scripts/test-examples.sh"

echo
echo "test.sh: all passed"
