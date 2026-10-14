#!/bin/bash
# A/B of bc75f2a's process-wide mallopt on serialized REST tiers.
set -euo pipefail
export GOOSE=/mnt/c/Users/kait/projects/goose/goose/build-linux/goose
export PATH=$HOME/.cargo/bin:$PATH MACHINE=wsl2-5800x3d
root=/mnt/c/Users/kait/projects/goose/goose-http
cd "$root"
[ "$(git -C ../goose rev-parse --short HEAD)" = 46356c2 ]
if pgrep -af '[w]rk|[z]rk|[h]2load|[r]est-goose'; then echo busy >&2; exit 1; fi
w=/root/ab; rm -rf $w; mkdir -p $w/n $w/r
git archive bc75f2a | tar -x -C $w/n
git archive bc75f2a | tar -x -C $w/r
f=bench/rest/goose/rest.goose
grep -q '^    mallopt(M_MMAP_THRESHOLD, 131072);$' $w/n/$f
sed -i '/^    mallopt(M_MMAP_THRESHOLD, 131072);$/d' $w/n/$f
sed -i 's/^    thread_wait(giving);$/    thread_wait(giving);\n    mallopt(M_MMAP_THRESHOLD, 33554432);\n    mallopt(-1, 67108864);/' $w/r/$f
grep -c 33554432 $w/r/$f
"$GOOSE" build --cc gcc --standalone -o build/rest/rest-goose-cn $w/n/$f
"$GOOSE" build --cc gcc --standalone -o build/rest/rest-goose-cr $w/r/$f
rm -rf $w
OUT=${OUT:-/root/ab-out} SERVERS="goose-uring-cm goose-uring-cn goose-uring-cr" STEPS=1 bench/rest.sh run
