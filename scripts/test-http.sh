#!/bin/sh
# Starts the HTTP server of build/server and tests it: the endpoints with
# curl, TechEmpower's checks, pipelining, keep-alive, hostile and slow
# clients, and many connections at once with scripts/http_client.py, then
# short wrk, h2load, and oha runs that must see only 200s and no errors.
# Fails on the first error, or if the server died along the way.
#
# PORT picks the port (29080): keep it below the kernel's ephemeral range
# (32768 and up), as for test-echo.sh. WORKERS sets the server's worker
# count (4). oha is looked for on PATH and in ~/.cargo/bin.
#
# On Windows, in Git Bash, it tests the IOCP build and leaves out the load
# runs and the fd limit run (docs/development.md, "Windows").
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
port=${PORT:-29080}
export WORKERS="${WORKERS:-4}"
url=http://127.0.0.1:$port
client="python3 $root/scripts/http_client.py $port"
oha=$(command -v oha || echo "$HOME/.cargo/bin/oha")
log=$(mktemp)
out=$(mktemp)
pid=
case $(uname -s) in
MINGW* | MSYS*) windows=1 ;;
*) windows= ;;
esac

# Ends the server. Git Bash's kill doesn't always end a native program, so
# on Windows it goes by the Windows process id.
end_server() {
    if [ -n "$windows" ]; then
        taskkill //F //PID "$(cat "/proc/$pid/winpid")" >/dev/null
    else
        kill "$pid"
    fi
}

# On any failure, show what the server said and don't leave it running.
trap 'status=$?
if [ -n "$pid" ]; then
    [ $status -eq 0 ] || { echo "server output:"; cat "$log"; }
    end_server 2>/dev/null || true
fi
rm -f "$log" "$out"' EXIT

# Sets the fd limit, which Windows has none of for native programs.
limit_fds() {
    [ -n "$windows" ] || ulimit -n "$1"
}

# Whether the server listens. Windows has no nc.
probe='import socket, sys; socket.create_connection(("127.0.0.1", int(sys.argv[1])), 1)'
listening() {
    if [ -n "$windows" ]; then
        python3 -c "$probe" "$port" 2>/dev/null
    else
        nc -z 127.0.0.1 "$port" 2>/dev/null
    fi
}

# The many-client run holds 10000 connections open on each side.
limit_fds 65536

fail() {
    echo "FAIL: $*"
    exit 1
}

# Starts the server, with an fd limit of $1 if given.
start() {
    # The io_uring loop's listener outlives the process by a moment: the
    # kernel tears a ring down after its process exits.
    tries=0
    while listening; do
        tries=$((tries + 1))
        [ $tries -lt 50 ] || fail "port $port is taken; set PORT"
        sleep 0.1
    done
    (limit_fds "${1:-65536}" && exec "$root/build/server" http "$port") >"$log" 2>&1 &
    pid=$!
    tries=0
    until listening; do
        kill -0 "$pid" 2>/dev/null || fail "the server exited at start"
        tries=$((tries + 1))
        [ $tries -lt 100 ] || fail "the server isn't listening after 10 s"
        sleep 0.1
    done
}

stop() {
    end_server
    wait "$pid" 2>/dev/null || true
    pid=
}

start

body=$(curl -sS "$url/plaintext")
[ "$body" = "Hello, World!" ] || fail "curl /plaintext: $body"
body=$(curl -sS "$url/json")
[ "$body" = '{"message":"Hello, World!"}' ] || fail "curl /json: $body"
ctype=$(curl -sS -o /dev/null -w '%{content_type}' "$url/json")
[ "$ctype" = application/json ] || fail "curl /json: Content-Type $ctype"
code=$(curl -sS -o /dev/null -w '%{http_code}' "$url/nope")
[ "$code" = 404 ] || fail "curl /nope: $code"
# Two requests on one connection.
connects=$(curl -sS -o /dev/null -o /dev/null -w '%{num_connects} ' "$url/plaintext" "$url/json")
[ "$connects" = "1 0 " ] || fail "curl didn't reuse the connection: $connects"
echo "curl: ok"

$client tfb
$client pipeline
$client chunked
$client keepalive
$client hostile
$client many 10000
$client slow

if [ -n "$windows" ]; then
    kill -0 "$pid" || fail "the server died"
    stop
    echo "test-http passed, without the load runs and the fd limit run on Windows. The server's output:"
    sed 's/^/    /' "$log"
    exit 0
fi

# Load generators, briefly: every response a 200, and no errors. wrk times
# requests with the wall clock, which WSL2 steps back now and then, and
# counts each request in flight across a step as a timeout; its timeouts are
# left to h2load and oha, which use a monotonic clock.
wrk_ok() {
    ! grep -E 'Non-2xx' "$out" || fail "wrk $1"
    ! grep -E 'Socket errors' "$out" | grep -v 'connect 0, read 0, write 0,' || fail "wrk $1"
    grep -E 'requests in' "$out"
}
wrk -t 2 -c 64 -d 3 -s "$root/scripts/pipeline.lua" "$url/plaintext" -- 16 >"$out"
wrk_ok plaintext
wrk -t 2 -c 64 -d 3 "$url/json" >"$out"
wrk_ok json
h2load --h1 -c 64 -m 16 -n 200000 "$url/plaintext" >"$out"
grep -q 'succeeded, 0 failed, 0 errored, 0 timeout' "$out" || { cat "$out"; fail "h2load"; }
grep -q 'status codes: 200000 2xx, 0 3xx, 0 4xx, 0 5xx' "$out" || { cat "$out"; fail "h2load"; }
grep -E '^requests:' "$out"
# A request count, not -z: at a deadline oha aborts the requests in flight
# and lists them as errors.
"$oha" -n 500000 -c 64 --no-tui "$url/json" >"$out"
grep -q 'Success rate:.100.00%' "$out" || { cat "$out"; fail "oha"; }
! grep -q 'Error distribution' "$out" || { cat "$out"; fail "oha"; }
grep -q '\[200\] 500000 responses' "$out" || { cat "$out"; fail "oha"; }
grep -E '\[200\]' "$out"
echo "load: ok"

kill -0 "$pid" || fail "the server died"
stop
echo "The server's output:"
sed 's/^/    /' "$log"

# One worker with 40 fds: accepting pauses at the limit, and resumes as
# connections close.
WORKERS=1
start 40
$client emfile 60
kill -0 "$pid" || fail "the server died"
grep -q 'accept: Too many open files' "$log" || fail "the server never reached EMFILE"
stop
echo "test-http passed. The server's output at the fd limit:"
sed 's/^/    /' "$log"
