#!/bin/bash
# As root in WSL Ubuntu: compare archived main with the README benchmark build.
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
}

[ "$(git -C ../goose rev-parse --short HEAD)" = 46356c2 ]
if pgrep -af '[w]rk|[z]rk|[h]2load|[r]est-goose'; then
    echo 'Another benchmark process is running; stop before building.' >&2
    exit 1
fi
[ ! -e /root/bconf ] || { echo '/root/bconf already exists' >&2; exit 1; }
trap 'rm -rf /root/bconf' EXIT
echo "== build $(date +%T)"
mkdir -p build/bench build/rest
for p in $revs; do
    tag=${p%%:*}; rev=${p##*:}
    d=/root/bconf/$tag
    mkdir -p "$d"
    git archive "$rev" | tar -x -C "$d"
    (cd "$d" && LOOP=epoll scripts/build.sh >/dev/null && cp build/server "$root/build/bench/goose-c$tag")
    (cd "$d" && LOOP=uring scripts/build.sh >/dev/null && cp build/server "$root/build/bench/goose-c$tag-uring")
    "$GOOSE" build --cc gcc --standalone -o "$root/build/rest/rest-goose-c$tag" "$d/bench/rest/goose/rest.goose"
done

echo "== count $(date +%T)"
out=bench/results/2026-10-14-desktop-main-count
mkdir -p "$out"
revinfo >"$out/env.txt"
h2load --version | head -1 >>"$out/env.txt"
RUNS=3 bench/count.sh goose-c{x,m} goose-c{x,m}-uring | tee "$out/runs.tsv"

echo "== run $(date +%T)"
OUT=bench/results/2026-10-14-desktop-main-run \
    SERVERS="goose-cx goose-cm goose-cx-uring goose-cm-uring" \
    TESTS="plaintext:256 json:256" LATENCY=0 bench/run.sh

echo "== rest $(date +%T)"
OUT=bench/results/2026-10-14-rest-main \
    SERVERS="goose-uring-cx goose-uring-cm" \
    STEPS="1 2 4" RATE_C=16000 bench/rest.sh run
revinfo >bench/results/2026-10-14-rest-main/revs.txt
echo "== done $(date +%T)"
