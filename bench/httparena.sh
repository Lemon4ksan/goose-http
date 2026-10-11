#!/bin/sh
# Runs HttpArena's own harness (MDA2AV/HttpArena, MIT) on this machine, with
# the Goose server as an entry (bench/httparena/goose) beside HttpArena's
# entries, built from their own Dockerfiles.
#
#   bench/httparena.sh validate [FRAMEWORK]   scripts/validate.sh (default goose)
#   bench/httparena.sh run                    scripts/benchmark.sh, each framework
#                                             and profile, logs into OUT
#
# The checkout is HTTPARENA_COMMIT under CACHE, reset on every call. What this
# changes in it, so that the runs match bench/run.sh's layout on 16 CPUs and
# work under Docker Desktop:
#
# - Every profile's server cpuset, 0-31,64-95 on HttpArena's 128-thread
#   machine, becomes SERVER_CPUS (0-3). On a machine with fewer CPUs the
#   harness would otherwise give the server all of them, shared with the load
#   generator.
# - The load generators run in Docker (LOADGEN_DOCKER) on LOAD_CPUS (4-15) with
#   THREADS (4) threads, where the harness's default is 64. With Goose, tokio,
#   and vanilla-epoll on CPUs 0-3, baseline peaked at 4 gcannon threads (463K
#   to 473K requests per second) and fell at 3 and at 6; 12 threads gave 267K
#   (2026-10-10). gcannon's image is built at GCANNON_COMMIT, where its
#   Dockerfile follows gcannon's main branch.
# - latency-1m offers LATENCY_RATE (200,000) requests per second instead of
#   1,000,000, which zrk couldn't reach here (309K against Goose): the profile
#   compares CPU per request at a rate every server holds.
#
# - Under Docker Desktop, the readiness probe and the cgroup CPU reads run in
#   helper containers (bench/httparena/docker-desktop.sh).
#
# SKIP_TUNE leaves the host as bench/run.sh measures it: the harness's
# system_tune changes sysctls and restarts Docker.
#
# Settings, from the environment:
#   FRAMEWORKS  goose tokio dusty vanilla-epoll
#   PROFILES    baseline limited-conn latency-1m pipelined
#   MACHINE     a short name for the machine (the host name), for OUT
#   RUNS 3 (the harness keeps the best), DURATION 5s,
#   OUT bench/results/httparena-<date>-<machine>
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cache=${CACHE:-$HOME/.cache/goose-http-bench}
arena=$cache/httparena
frameworks=${FRAMEWORKS:-goose tokio dusty vanilla-epoll}
profiles=${PROFILES:-baseline limited-conn latency-1m pipelined}
server_cpus=${SERVER_CPUS:-0-3}
machine=${MACHINE:-$(hostname -s)}
out=${OUT:-$root/bench/results/httparena-$(date -u +%Y-%m-%dT%H%M)-$machine}
# The runs happen in the checkout, so a relative OUT is taken from here.
case $out in /*) ;; *) out=$PWD/$out ;; esac

HTTPARENA_COMMIT=0720ee57dc20424cc3fa3fc1735946a1abaf1a59
GCANNON_COMMIT=11c802b2bdfe9af2fac4ac2571ae2de4c530cc62

if [ ! -d "$arena/.git" ]; then
    git clone -q https://github.com/MDA2AV/HttpArena.git "$arena"
fi
git -C "$arena" fetch -q origin
git -C "$arena" checkout -q -f "$HTTPARENA_COMMIT"
git -C "$arena" clean -q -fdx frameworks/goose scripts

rm -rf "$arena/frameworks/goose"
cp -r "$root/bench/httparena/goose" "$arena/frameworks/goose"
cp -r "$root/src" "$root/shim" "$arena/frameworks/goose/"
mkdir -p "$arena/frameworks/goose/scripts"
cp "$root/scripts/build.sh" "$arena/frameworks/goose/scripts/"
sed -i "s/0-31,64-95/$server_cpus/g" "$arena/scripts/lib/profiles.sh"
# Docker Desktop's host network is its VM's, which the containers share but
# WSL doesn't reach, so the readiness probe runs curl in a container too.
if docker info --format '{{.OperatingSystem}}' | grep -q 'Docker Desktop'; then
    sed -i 's|if curl -sk -o /dev/null --max-time 2 |if docker run --rm --network host curlimages/curl:8.11.1 -sk -o /dev/null --max-time 2 |' \
        "$arena/scripts/lib/framework.sh"
    cat "$root/bench/httparena/docker-desktop.sh" >>"$arena/scripts/lib/stats.sh"
fi

export LOADGEN_DOCKER=true SKIP_TUNE=true
export GCANNON_CPUS=${LOAD_CPUS:-4-15} THREADS=${THREADS:-4}
export ZRK_RATE_LATENCY_1M=${LATENCY_RATE:-200000}
export RUNS=${RUNS:-3} DURATION=${DURATION:-5s}

docker build -q --build-arg GCANNON_REF="$GCANNON_COMMIT" -t gcannon:latest \
    -f "$arena/docker/gcannon.Dockerfile" "$arena/docker" >/dev/null

cd "$arena"
case ${1:-} in
validate)
    ./scripts/validate.sh "${2:-goose}"
    ;;
run)
    mkdir -p "$out"
    {
        echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "machine: $machine"
        echo "kernel: $(uname -r)"
        echo "cpu: $(lscpu | sed -n 's/^Model name: *//p'), $(nproc) logical CPUs"
        echo "httparena: $HTTPARENA_COMMIT, gcannon: $GCANNON_COMMIT"
        echo "goose-http: $(git -C "$root" rev-parse --short HEAD)$(git -C "$root" diff --quiet || echo ' (modified)')"
        echo "server cpus: $server_cpus, load cpus: $GCANNON_CPUS, threads: $THREADS"
        echo "runs: $RUNS, duration: $DURATION, latency-1m rate: $ZRK_RATE_LATENCY_1M"
        echo "docker: $(docker version --format '{{.Server.Version}}')"
    } >"$out/env.txt"
    for fw in $frameworks; do
        for p in $profiles; do
            echo "$fw $p"
            ./scripts/benchmark.sh "$fw" "$p" >"$out/$fw-$p.log" 2>&1 || echo "$fw $p: failed"
        done
    done
    echo "results: $out"
    ;;
*)
    echo "usage: bench/httparena.sh validate [FRAMEWORK] | run"
    exit 2
    ;;
esac
