#!/bin/bash
# Bisect serialized REST rates along main's first parents, one compiler pin.
set -euo pipefail
export GOOSE=/mnt/c/Users/kait/projects/goose/goose/build-linux/goose
export PATH=$HOME/.cargo/bin:$PATH MACHINE=wsl2-5800x3d
root=/mnt/c/Users/kait/projects/goose/goose-http
cd "$root"
[ "$(git -C ../goose rev-parse --short HEAD)" = 46356c2 ]
if pgrep -af '[w]rk|[z]rk|[h]2load|[r]est-goose'; then echo busy >&2; exit 1; fi
w=/root/bis; rm -rf $w
for p in p:a1c6e8d f:afb4a40 w:71ef2c0; do
    tag=${p%%:*}; rev=${p##*:}; mkdir -p $w/$tag
    git archive $rev | tar -x -C $w/$tag
    "$GOOSE" build --cc gcc --standalone -o build/rest/rest-goose-b$tag $w/$tag/bench/rest/goose/rest.goose
done
rm -rf $w
OUT=/root/bis-out SERVERS="goose-uring-cx goose-uring-bp goose-uring-bf goose-uring-bw goose-uring-cm" STEPS=1 bench/rest.sh run
