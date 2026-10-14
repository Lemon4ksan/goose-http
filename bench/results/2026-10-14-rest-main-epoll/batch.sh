#!/bin/bash
# Follow the io_uring batch with the same archived REST binaries on epoll.
set -euo pipefail
export GOOSE=/mnt/c/Users/kait/projects/goose/goose/build-linux/goose
export PATH=$HOME/.cargo/bin:$PATH
export MACHINE=wsl2-5800x3d
root=/mnt/c/Users/kait/projects/goose/goose-http
cd "$root"
revs="x:e4f7b55 m:bc75f2a"
revinfo() {
    echo "date: $(date -u +%FT%TZ)"
    echo "machine: $MACHINE, $(lscpu | awk -F: '/Model name/ { gsub(/^ +/, "", $2); print $2 }')"
    echo "kernel: $(uname -r)"
    echo "gcc: $(gcc --version | head -1)"
    echo "goose: $(git -C ../goose rev-parse --short HEAD)"
    for p in $revs; do echo "${p%%:*}: $(git rev-parse "${p##*:}")"; done
    echo "quiet: machine kept quiet; only concurrent README edits, no other benchmarks or taxing work"
    echo "builds: archived REST binaries from ../2026-10-14-rest-main/batch.sh"
}
[ "$(git -C ../goose rev-parse --short HEAD)" = 46356c2 ]
if pgrep -af '[w]rk|[z]rk|[h]2load|[r]est-goose'; then
    echo 'Another benchmark process is running; stop before measuring.' >&2
    exit 1
fi
OUT=bench/results/2026-10-14-rest-main-epoll \
    SERVERS="goose-epoll-cx goose-epoll-cm" \
    STEPS="1 2 4" RATE_C=16000 bench/rest.sh run
revinfo >bench/results/2026-10-14-rest-main-epoll/revs.txt
echo "== done $(date +%T)"
