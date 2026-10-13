#!/bin/sh
# Builds each program in examples/ and requests each of its routes once, so
# that a change to the package can't leave an example broken. Each example
# listens on port 8080, which must be free. Needs curl.
#
# GOOSE names the compiler (default: goose on PATH), and CC the C compiler,
# as scripts/build.sh takes them.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
goose=${GOOSE:-goose}
url=http://127.0.0.1:8080
case $(uname -s) in
MINGW* | MSYS*) windows=1 cc=${CC:-msvc} ;;
*) windows= cc=${CC:-gcc} ;;
esac
bin=$root/build/examples
mkdir -p "$bin"
tmp=$(mktemp -d)
pid=

# Ends the running example. Git Bash's kill doesn't always end a native
# program, so on Windows it goes by the Windows process id.
end_example() {
    if [ -n "$windows" ]; then
        taskkill //F //PID "$(cat "/proc/$pid/winpid")" >/dev/null
    else
        kill "$pid"
    fi
    wait "$pid" 2>/dev/null || true
    pid=
}

trap 'status=$?
if [ -n "$pid" ]; then
    [ $status -eq 0 ] || { echo "example output:"; cat "$tmp/log"; }
    end_example 2>/dev/null || true
fi
rm -rf "$tmp"' EXIT

fail() {
    echo "FAIL: $*"
    exit 1
}

# Builds example $1 and starts it with the arguments after it, then waits
# until it listens.
start() {
    name=$1
    shift
    "$goose" build --cc "$cc" --standalone -o "$bin/$name" "$root/examples/$name/$name.goose" >"$tmp/log" 2>&1 ||
        { cat "$tmp/log"; fail "$name doesn't build"; }
    tries=0
    while curl -s -o /dev/null "$url/" 2>/dev/null; do
        tries=$((tries + 1))
        [ $tries -lt 50 ] || fail "port 8080 is taken"
        sleep 0.1
    done
    "$bin/$name${windows:+.exe}" "$@" >"$tmp/log" 2>&1 &
    pid=$!
    tries=0
    until curl -s -o /dev/null "$url/" 2>/dev/null; do
        kill -0 "$pid" 2>/dev/null || fail "$name exited at start"
        tries=$((tries + 1))
        [ $tries -lt 100 ] || fail "$name isn't listening after 10 s"
        sleep 0.1
    done
}

# Requests with curl's arguments after $1, which is the status it must
# answer; the body lands in $tmp/body.
expect() {
    want=$1
    shift
    code=$(curl -sS -o "$tmp/body" -w '%{http_code}' "$@")
    [ "$code" = "$want" ] || fail "$name: curl $*: $code, want $want: $(head -c 200 "$tmp/body")"
}

# Fails unless $tmp/body holds $1.
holds() {
    grep -qF -- "$1" "$tmp/body" || fail "$name: body $(head -c 200 "$tmp/body"), want $1"
}

start hello
expect 200 "$url/"
holds "Hello, World!"
expect 404 "$url/nope"
end_example

start routes
expect 200 "$url/"
expect 200 "$url/users/42"
holds '{"id":"42"}'
expect 200 -d hi "$url/echo"
holds hi
expect 405 -X DELETE "$url/users/42"
expect 404 "$url/nope"
end_example

start api
json='Content-Type: application/json'
expect 401 -H "$json" -d '{"text":"buy milk"}' "$url/notes"
# A worker's notes are its own, so the read goes on the same connection.
code=$(curl -sS -o "$tmp/body" -w '%{http_code} ' -H 'Authorization: Bearer let-me-in' -H "$json" \
    -d '{"text":"buy milk"}' "$url/notes" --next "$url/notes/1")
[ "$code" = "201 200 " ] || fail "api: POST then GET: $code"
holds "buy milk"
expect 422 -H 'Authorization: Bearer let-me-in' -H "$json" -d '{"note":1}' "$url/notes"
expect 200 "$url/visits"
holds 1
expect 200 -H 'Cookie: visits=4' "$url/visits"
holds 5
end_example

start upload
head -c 300000 /dev/zero >"$tmp/zeros"
expect 200 --data-binary "@$tmp/zeros" "$url/upload"
holds "300000 bytes"
printf 'hello' >"$tmp/part.txt"
expect 200 -F note=hi -F "file=@$tmp/part.txt" "$url/form"
holds "note: 2 bytes"
holds "file (part.txt): 5 bytes"
expect 415 -d plain "$url/form"
end_example

start later
expect 200 "$url/primes/100"
holds 25
expect 404 "$url/primes/x"
end_example

mkdir "$tmp/site"
printf 'Hello, files!\n' >"$tmp/site/a.txt"
site=$tmp/site
[ -z "$windows" ] || site=$(cygpath -m "$site")
start files "$site"
expect 200 "$url/files/a.txt"
holds "Hello, files!"
expect 206 -r 0-4 "$url/files/a.txt"
[ "$(cat "$tmp/body")" = Hello ] || fail "files: a range came as $(cat "$tmp/body")"
etag=$(curl -sS -D - -o /dev/null "$url/files/a.txt" | tr -d '\r' | sed -n 's/^[Ee][Tt][Aa][Gg]: //p')
expect 304 -H "If-None-Match: $etag" "$url/files/a.txt"
expect 404 "$url/files/missing.txt"
end_example

echo "test-examples.sh: all passed"
