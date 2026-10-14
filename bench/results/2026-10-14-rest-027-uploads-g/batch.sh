#!/bin/bash
# As root in WSL: tier D for g, findings-46356c2-hot at d1f4ffc (find_bytes
# kept in multipart), against n (main, cb57a0b, the build of
# 2026-10-14-rest-027-025), g first.
set -eu
export GOOSE=/mnt/c/Users/kait/projects/goose/goose/build-linux/goose
export PATH=$HOME/.cargo/bin:$PATH
export MACHINE=wsl2-5800x3d
root=/mnt/c/Users/kait/projects/goose/goose-http
cd "$root"
rm -rf /root/b27g; mkdir -p /root/b27g
git archive d1f4ffc -- '*.goose' '*.build' shim bench/rest | tar -x -C /root/b27g
"$GOOSE" build --cc gcc --standalone -o build/rest/rest-goose-27g /root/b27g/bench/rest/goose/rest.goose >/dev/null
rm -rf /root/b27g
OUT=bench/results/2026-10-14-rest-027-uploads-g \
    SERVERS="goose-uring-27g goose-uring-27n" STEPS=2 bench/rest.sh run 2>&1 | tail -12
