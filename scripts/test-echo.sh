#!/bin/sh
# Starts each echo server in src/echo.goose and tests it with nc and
# scripts/echo_client.py: a short echo, clients that hang up while the server
# writes, and many clients at once. Fails on the first error, or if a server
# died along the way.
#
# The server command defaults to build/server; another can be given as the
# arguments. PORT picks the port (29080):
# keep it below the kernel's ephemeral range (32768 and up), where the
# clients' own TIME_WAIT sockets from earlier runs can block the bind.
#
# On Windows, in Git Bash, it tests only echo-blocking, without nc
# (docs/development.md, "Windows").
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
port=${PORT:-29080}
client="python3 $root/scripts/echo_client.py $port"
log=$(mktemp)
pid=
case $(uname -s) in
MINGW* | MSYS*) windows=1 ;;
*) windows= ;;
esac
# Named in full on Windows, as in test-http.sh.
[ $# -gt 0 ] || set -- "$root/build/server${windows:+.exe}"

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
rm -f "$log"' EXIT

# Whether the server listens. Windows has no nc.
probe='import socket, sys; socket.create_connection(("127.0.0.1", int(sys.argv[1])), 1)'
listening() {
    if [ -n "$windows" ]; then
        python3 -c "$probe" "$port" 2>/dev/null
    else
        nc -z 127.0.0.1 "$port" 2>/dev/null
    fi
}

# Windows has no epoll (shim/net_win.c), and no fd limit for native
# programs. A send there fails with ECONNRESET where Linux's fails with
# EPIPE, and no signal goes with either.
modes="echo-blocking echo-epoll"
send_error='send: Broken pipe'
if [ -n "$windows" ]; then
    modes=echo-blocking
    send_error='send: Connection reset by peer'
else
    # The many-client run holds 10000 connections open on each side.
    ulimit -n 65536
    # OpenBSD's nc shuts down its side after the input with -N, where macOS's
    # takes -N for a count of keepalive probes; there, -w ends the wait instead.
    nc_eof=
    nc -h 2>&1 | grep -q -- '-N.*[Ss]hutdown' && nc_eof=-N
fi

for mode in $modes; do
    if listening; then
        echo "port $port is taken; set PORT"
        exit 1
    fi
    "$@" "$mode" "$port" >"$log" 2>&1 &
    pid=$!
    # A TinyCC run compiles the program first.
    tries=0
    until listening; do
        kill -0 "$pid" 2>/dev/null || { echo "$mode exited at start"; exit 1; }
        tries=$((tries + 1))
        [ $tries -lt 600 ] || { echo "$mode isn't listening after 60 s"; exit 1; }
        sleep 0.1
    done

    if [ -z "$windows" ]; then
        reply=$(printf 'hello\n' | nc $nc_eof -w 2 127.0.0.1 "$port")
        [ "$reply" = hello ] || { echo "nc: got '$reply'"; exit 1; }
        echo "nc: ok"
    fi
    # An odd cut round ends in EPIPE only when the client's close sends a FIN,
    # before the echo reaches it; on a fast loopback the echo often wins, and
    # the close resets the connection instead (ECONNRESET). So the rounds
    # repeat until the server has seen its send error, up to 5 times.
    tries=0
    until grep -q "$send_error" "$log" || [ $tries -eq 5 ]; do
        $client cut 10
        tries=$((tries + 1))
    done
    if [ "$mode" = echo-blocking ]; then
        # One client at a time: the rest wait in the listen backlog.
        $client many 20 65536
    else
        $client many 2000 65536
        $client many 10000 100
    fi
    $client ping

    kill -0 "$pid" || { echo "$mode died"; exit 1; }
    # The cut runs must have reached the send error that raises SIGPIPE on
    # Linux.
    grep -q "$send_error" "$log" || { echo "$mode never saw '$send_error'"; exit 1; }
    end_server
    wait "$pid" 2>/dev/null || true
    pid=
    echo "$mode passed. Its output:"
    sed 's/^/    /' "$log"
done
