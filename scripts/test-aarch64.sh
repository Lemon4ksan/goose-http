#!/bin/sh
# Cross-builds every example for aarch64 Linux, then runs
# scripts/test-examples.sh on the builds in an arm64 container, which Docker
# runs under emulation on an x86-64 host (docs/embedded.md). Prints each
# example's peak RSS, which under emulation includes the emulator's own.
#
# GOOSE names a Linux build of the compiler in its checkout, such as
# ../goose/build-linux/goose, which must run on Ubuntu 26.04. Needs Docker with
# arm64 emulation: Docker Desktop has it, and elsewhere tonistiigi/binfmt
# installs it.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
: "${GOOSE:?GOOSE must name a Linux build of the compiler}"
goose=$(cd "$(dirname "$GOOSE")" && pwd)/$(basename "$GOOSE")
# The compiler finds its stdlib in its checkout, which the container mounts.
checkout=$(dirname "$(dirname "$goose")")
out=$root/build/aarch64
mkdir -p "$out/examples" "$out/goose-home"

docker build -q --platform linux/amd64 -t goose-http-cross-aarch64 - >/dev/null <<'EOF'
FROM ubuntu:26.04
# arm64 packages come from Ubuntu's ports archive, for liburing-dev:arm64.
RUN sed -i 's/^Types: deb$/Types: deb\nArchitectures: amd64/' /etc/apt/sources.list.d/ubuntu.sources && \
    . /etc/os-release && \
    printf 'Types: deb\nURIs: http://ports.ubuntu.com/ubuntu-ports\nSuites: %s %s-updates\nComponents: main universe\nArchitectures: arm64\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n' \
        "$VERSION_CODENAME" "$VERSION_CODENAME" >/etc/apt/sources.list.d/arm64.sources && \
    dpkg --add-architecture arm64 && apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gcc-aarch64-linux-gnu liburing-dev:arm64 >/dev/null
EOF
docker build -q --platform linux/arm64 -t goose-http-run-arm64 - >/dev/null <<'EOF'
FROM ubuntu:26.04
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq liburing2 curl >/dev/null
EOF

echo "cross-building the examples into $out/examples"
docker run --rm --platform linux/amd64 --user "$(id -u):$(id -g)" \
    -v "$root:$root" -v "$checkout:$checkout" -w "$root" \
    -e GOOSE="$goose" -e GOOSE_HOME="$out/goose-home" -e BIN="$out/examples" \
    goose-http-cross-aarch64 sh -c '
set -eu
for dir in examples/*/; do
    name=$(basename "$dir")
    src=$dir$name.goose
    [ -f "$src" ] || src=${dir}app.goose
    "$GOOSE" build --cc /usr/bin/aarch64-linux-gnu-gcc --standalone -o "$BIN/$name" "$src" >"$BIN/$name.log" 2>&1 ||
        { cat "$BIN/$name.log"; echo "FAIL: $name does not build for aarch64"; exit 1; }
done'

echo "running them on arm64"
docker run --rm --platform linux/arm64 --user "$(id -u):$(id -g)" -v "$root:$root" -w "$root" \
    -e PREBUILT=1 -e RSS=1 -e BIN="$out/examples" \
    goose-http-run-arm64 sh scripts/test-examples.sh
