#!/bin/bash
# As root in WSL: which of findings-46356c2-hot's changes costs tier D's forms
# role. Each variant is git archive of findings-46356c2-hot (e047040's code,
# with main merged at 40ce2a6) with one group of files taken back from main:
#   f       the branch as it is
#   cookie  cookie.goose: each_cookie's loop instead of each_field and each_split
#   find    form.goose: find_bytes instead of std's find in multipart
#   msg     message.goose: pos = pos + k in parse, and respond as before
#   http    http.goose, epoll.goose, uring.goose, bench/rest/goose/rest.goose:
#           whole_only instead of whole, interim() and the string functions
#           instead of global string constants
# and n, main's server of 2026-10-14-rest-027-025. Each REST server is built
# with goose build --cc gcc --standalone, and measured as
# 2026-10-14-rest-027-uploads-perf/forms.sh measured n and f: the forms role
# alone, perf stat for 10 s, two rounds.
set -eu
export GOOSE=/mnt/c/Users/kait/projects/goose/goose/build-linux/goose
root=/mnt/c/Users/kait/projects/goose/goose-http
src=/mnt/c/Users/kait/.claude/jobs/9baaf113/tmp/v
out=$root/bench/results/2026-10-14-rest-027-forms-bisect
port=29384
url=http://127.0.0.1:$port
variants="f find"
cd "$root"
mkdir -p /root/bisect
for v in $variants; do
    "$GOOSE" build --cc gcc --standalone -o /root/bisect/rest-$v $src/$v/bench/rest/goose/rest.goose >/dev/null
done
cp build/rest/rest-goose-27n /root/bisect/rest-n
(cd /root/bisect && sha256sum rest-*) >"$out/confirm-binaries.txt"
wrk_() {
    taskset -c 4-15 env LD_PRELOAD=$root/build/bench/wrk-monotonic.so \
        wrk --timeout 10s --latency -t 7 -c 224 "$@" -s bench/rest/tier-d.lua "$url" -- build/rest forms
}
: >"$out/confirm.txt"
for r in 3 4; do
    for v in n $variants; do
        REST_DATA=build/rest TIER=d JSON=serialize WORKERS=4 LOOP=uring \
            taskset -c 0-3 /root/bisect/rest-$v $port >/dev/null 2>&1 &
        pid=$!
        until nc -z 127.0.0.1 $port 2>/dev/null; do sleep 0.1; done
        wrk_ -d 5 >/dev/null
        wrk_ -d 12 >/root/bisect/wrk.txt &
        w=$!
        sleep 1
        echo "-- $v round $r" >>"$out/confirm.txt"
        perf stat -x, -e instructions:u,cycles:u -p $pid -- sleep 10 2>>"$out/confirm.txt"
        wait $w
        grep -E 'Requests/sec' /root/bisect/wrk.txt >>"$out/confirm.txt"
        kill $pid; wait $pid 2>/dev/null || true
        while nc -z 127.0.0.1 $port 2>/dev/null; do sleep 0.1; done
    done
done
rm -rf /root/bisect
cat "$out/confirm.txt"
