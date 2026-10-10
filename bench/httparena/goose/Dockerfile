# The Goose server as an HttpArena entry. bench/httparena.sh copies this
# directory into HttpArena's frameworks/goose/ with the server's src/, shim/,
# and scripts/build.sh beside it.
FROM ubuntu:26.04 AS build
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends ca-certificates git cmake ninja-build gcc g++ && \
    rm -rf /var/lib/apt/lists/*

# The Goose pin in README.md.
ARG GOOSE_COMMIT=2ec9b38bde93cda87ee374157b0353722b2d5f8e
RUN git init -q /goose && cd /goose && \
    git fetch -q --depth 1 https://github.com/aardappel/goose.git "$GOOSE_COMMIT" && \
    git checkout -q FETCH_HEAD && \
    git submodule update -q --init --depth 1 third_party/tinycc && \
    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DGOOSE_GFX=OFF -DGOOSE_AUDIO=OFF -DGOOSE_PHYSICS=OFF -DGOOSE_UI=OFF && \
    cmake --build build

COPY src /server/src
COPY shim /server/shim
COPY scripts/build.sh /server/scripts/build.sh
RUN GOOSE=/goose/build/goose /server/scripts/build.sh

FROM ubuntu:26.04
COPY --from=build /server/build/server /server
EXPOSE 8080
# One worker per CPU of the container's cpuset, which nproc reads.
CMD ["/bin/sh", "-c", "WORKERS=${WORKERS:-$(nproc)} exec /server http 8080"]
