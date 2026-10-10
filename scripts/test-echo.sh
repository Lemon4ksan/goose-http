#!/bin/sh
# Starts each echo server in src/echo.goose and tests it with nc and
# scripts/echo_client.py: a short echo, clients that hang up while the server
# writes, and many clients at once. Fails on the first error, or if a server
# died along the way.
#
# The server command defaults to build/server; `scripts/test-echo.sh
# scripts/run.sh` tests the TinyCC build instead. PORT picks the port (29080):
# keep it below the kernel's ephemeral range (32768 and up), where the
# clients' own TIME_WAIT sockets from earlier runs can block the bind.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
port=${PORT:-29080}
[ $# -gt 0 ] || set -- "$root/build/server"
client="python3 $root/scripts/echo_client.py $port"
log=$(mktemp)
pid=
# On any failure, show what the server said and don't leave it running.
trap 'status=$?
if [ -n "$pid" ]; then
    [ $status -eq 0 ] || { echo "server output:"; cat "$log"; }
    kill "$pid" 2>/dev/null || true
fi
rm -f "$log"' EXIT
# The many-client run holds 10000 connections open on each side.
ulimit -n 65536

for mode in echo-blocking echo-epoll; do
    if nc -z 127.0.0.1 "$port" 2>/dev/null; then
        echo "port $port is taken; set PORT"
        exit 1
    fi
    "$@" "$mode" "$port" >"$log" 2>&1 &
    pid=$!
    # A TinyCC run compiles the program first.
    tries=0
    until nc -z 127.0.0.1 "$port" 2>/dev/null; do
        kill -0 "$pid" 2>/dev/null || { echo "$mode exited at start"; exit 1; }
        tries=$((tries + 1))
        [ $tries -lt 600 ] || { echo "$mode isn't listening after 60 s"; exit 1; }
        sleep 0.1
    done

    reply=$(printf 'hello\n' | nc -N -w 2 127.0.0.1 "$port")
    [ "$reply" = hello ] || { echo "nc: got '$reply'"; exit 1; }
    echo "nc: ok"
    $client cut 10
    if [ "$mode" = echo-blocking ]; then
        # One client at a time: the rest wait in the listen backlog.
        $client many 20 65536
    else
        $client many 2000 65536
        $client many 10000 100
    fi
    $client ping

    kill -0 "$pid" || { echo "$mode died"; exit 1; }
    # The cut runs must have reached the error that raises SIGPIPE.
    grep -q 'send: Broken pipe' "$log" || { echo "$mode never saw EPIPE"; exit 1; }
    kill "$pid"
    wait "$pid" 2>/dev/null || true
    pid=
    echo "$mode passed. Its output:"
    sed 's/^/    /' "$log"
done
