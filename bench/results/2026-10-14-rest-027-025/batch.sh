#!/bin/bash
# As root in WSL: every pending bench of task 027 and task 025, in one batch.
#   e  e67d92d                     main before review items 7-11
#   n  main                        cb57a0b
#   h  api-hot                     review item 3, on main
#   f  findings-46356c2-hot        with main merged
#   w  task-025-worker-load        with f merged (REST only)
#   s  task-025-shared-templates   with w merged (REST only)
set -eu
export GOOSE=/mnt/c/Users/kait/projects/goose/goose/build-linux/goose
export PATH=$HOME/.cargo/bin:$PATH
export MACHINE=wsl2-5800x3d
root=/mnt/c/Users/kait/projects/goose/goose-http
cd "$root"

revs="e:e67d92d n:cb57a0b h:4292f87 f:e047040 w:b10cf60 s:effcd47"
revinfo() {
    echo "date: $(date -u +%FT%TZ)"
    echo "machine: $MACHINE, $(lscpu | awk -F: '/Model name/ { gsub(/^ +/, "", $2); print $2 }')"
    echo "kernel: $(uname -r)"
    echo "gcc: $(gcc --version | head -1)"
    echo "goose: $(git -C ../goose rev-parse --short HEAD)"
    for p in $revs; do echo "${p%%:*}: ${p##*:}"; done
}

echo "== build $(date +%T)"
mkdir -p build/bench build/rest
for p in $revs; do
    tag=${p%%:*}; rev=${p##*:}
    d=/root/b27/$tag
    rm -rf "$d"; mkdir -p "$d"
    git archive "$rev" | tar -x -C "$d"
    case $tag in e|n|f)
        (cd "$d" && LOOP=epoll scripts/build.sh >/dev/null && cp build/server "$root/build/bench/goose-27$tag")
        (cd "$d" && LOOP=uring scripts/build.sh >/dev/null && cp build/server "$root/build/bench/goose-27$tag-uring");;
    esac
    case $tag in e) ;; *)
        "$GOOSE" build --cc gcc --standalone -o "$root/build/rest/rest-goose-27$tag" "$d/bench/rest/goose/rest.goose";;
    esac
done

echo "== count $(date +%T)"
out=bench/results/2026-10-14-desktop-027-recount
mkdir -p "$out"; revinfo >"$out/env.txt"; h2load --version | head -1 >>"$out/env.txt"
RUNS=3 bench/count.sh goose-27{e,n,f} goose-27{e,n,f}-uring | tee "$out/runs.tsv"

echo "== run $(date +%T)"
OUT=bench/results/2026-10-14-desktop-027-recheck-run \
    SERVERS="goose-27e goose-27n goose-27f goose-27e-uring goose-27n-uring goose-27f-uring" \
    TESTS="plaintext:256 json:256" LATENCY=0 bench/run.sh 2>&1 | tail -40

echo "== rest $(date +%T)"
OUT=bench/results/2026-10-14-rest-027-025 \
    SERVERS="goose-uring-27n goose-uring-27h goose-uring-27f goose-uring-27w goose-uring-27s" \
    STEPS="1 2 4" RATE_C=16000 bench/rest.sh run 2>&1 | tail -60
revinfo >bench/results/2026-10-14-rest-027-025/revs.txt
echo "== done $(date +%T)"
