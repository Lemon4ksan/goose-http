#!/bin/sh
# Cross-builds every example for aarch64 Linux, then runs
# scripts/test-examples.sh on the builds in an arm64 container, which Docker
# runs under emulation on an x86-64 host (docs/embedded.md). Prints each
# example's peak RSS, which under emulation includes the emulator's own.
#
# GOOSE names a Linux x86-64 build of the compiler that runs on Ubuntu 26.04,
# by default the pinned release's linux-x64 archive (scripts/goose.sh). A
# release finds its stdlib beside it and a checkout's build in the checkout;
# for one copied elsewhere, GOOSE_STDLIB names the stdlib.
# Needs Docker with ARM emulation: Docker Desktop has it, and elsewhere
# tonistiigi/binfmt installs it.
set -eu

arch=aarch64 deb=arm64 gcc=aarch64-linux-gnu-gcc platform=linux/arm64
root=$(cd "$(dirname "$0")/.." && pwd)
if [ -z "${GOOSE:-}" ]; then
    # GOOSE_COMMIT, or a commit goose.sh pins, builds for the host, and the
    # cross-build runs on Linux x86-64.
    pinned=$(sed -n 's/^goose_commit=//p' "$root/scripts/goose.sh")
    if [ -n "${GOOSE_COMMIT:-$pinned}" ] && [ "$(uname -s)-$(uname -m)" != Linux-x86_64 ]; then
        echo "GOOSE_COMMIT builds a compiler for this host; set GOOSE to a Linux x86-64 build" >&2
        exit 2
    fi
    GOOSE=$(GOOSE_ASSET=linux-x64 "$root/scripts/goose.sh")
fi
goose=$(cd "$(dirname "$GOOSE")" && pwd)/$(basename "$GOOSE")
if [ -n "${GOOSE_STDLIB:-}" ]; then
    stdlib=$GOOSE_STDLIB
elif [ -d "$(dirname "$goose")/stdlib" ]; then
    stdlib=$(dirname "$goose")/stdlib
else
    stdlib=$(dirname "$(dirname "$goose")")/stdlib
fi
stdlib=$(cd "$stdlib" && pwd)
out=$root/build/$arch
mkdir -p "$out/examples" "$out/goose-home"

docker build -q --platform linux/amd64 --build-arg DEB="$deb" --build-arg GCC="$gcc" \
    -t "goose-http-cross-$arch" - >/dev/null <<'EOF'
FROM ubuntu:26.04
ARG DEB
ARG GCC
# ARM packages come from Ubuntu's ports archive, for the board's liburing-dev.
# git fetches the packages examples import, such as examples/compress's. Where
# the mount shows another owner, as Docker Desktop's file sharing can, git
# refuses the fetch's directory unless safe.directory allows it.
RUN sed -i 's/^Types: deb$/Types: deb\nArchitectures: amd64/' /etc/apt/sources.list.d/ubuntu.sources && \
    . /etc/os-release && \
    printf 'Types: deb\nURIs: http://ports.ubuntu.com/ubuntu-ports\nSuites: %s %s-updates\nComponents: main universe\nArchitectures: %s\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n' \
        "$VERSION_CODENAME" "$VERSION_CODENAME" "$DEB" >/etc/apt/sources.list.d/ports.sources && \
    dpkg --add-architecture "$DEB" && apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "gcc-${GCC%-gcc}" "liburing-dev:$DEB" git ca-certificates >/dev/null
EOF
docker build -q --platform "$platform" -t "goose-http-run-$arch" - >/dev/null <<'EOF'
FROM ubuntu:26.04
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq liburing2 curl >/dev/null
EOF

echo "cross-building the examples into $out/examples"
docker run --rm --platform linux/amd64 --user "$(id -u):$(id -g)" \
    -v "$root:$root" -v "$(dirname "$goose"):$(dirname "$goose")" -v "$stdlib:$stdlib" -w "$root" \
    -e GOOSE="$goose" -e GOOSE_STDLIB="$stdlib" -e GOOSE_HOME="$out/goose-home" \
    -e BIN="$out/examples" -e CC="/usr/bin/$gcc" -e ARCH="$arch" \
    -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
    "goose-http-cross-$arch" sh -c '
set -eu
for dir in examples/*/; do
    name=$(basename "$dir")
    # goose-tls builds with OpenSSL through CMake, not set up for cross builds.
    [ "$name" != tls ] || continue
    src=$dir$name.goose
    [ -f "$src" ] || src=${dir}app.goose
    "$GOOSE" build --cc "$CC" --standalone -o "$BIN/$name" "$src" \
        >"$BIN/$name.log" 2>&1 ||
        { cat "$BIN/$name.log"; echo "FAIL: $name does not build for $ARCH"; exit 1; }
done'

echo "running them on $platform"
docker run --rm --platform "$platform" --user "$(id -u):$(id -g)" -v "$root:$root" -w "$root" \
    -e PREBUILT=1 -e RSS=1 -e BIN="$out/examples" \
    "goose-http-run-$arch" sh scripts/test-examples.sh
