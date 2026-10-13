# The Goose server as an HttpArena entry. bench/httparena.sh copies this
# directory into HttpArena's frameworks/goose/ with the package (*.goose,
# http.build, shim/), the server's server/, and scripts/build.sh beside it.
FROM ubuntu:26.04 AS build
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends ca-certificates git cmake ninja-build gcc g++ \
        liburing-dev && \
    rm -rf /var/lib/apt/lists/*

# The Goose pin in README.md.
ARG GOOSE_COMMIT=a6249a4b37b02d5d3c6c546c0bf114d660e12a0e
RUN git init -q /goose && cd /goose && \
    git fetch -q --depth 1 https://github.com/aardappel/goose.git "$GOOSE_COMMIT" && \
    git checkout -q FETCH_HEAD && \
    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build

COPY *.goose http.build /server/
COPY shim /server/shim
COPY server /server/server
COPY scripts/build.sh /server/scripts/build.sh
# The epoll loop: Docker's default seccomp profile blocks io_uring.
RUN GOOSE=/goose/build/goose LOOP=epoll /server/scripts/build.sh

FROM ubuntu:26.04
# The package links liburing on Linux, whichever loop the server runs.
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends liburing2 && \
    rm -rf /var/lib/apt/lists/*
COPY --from=build /server/build/server /server
EXPOSE 8080
# One worker per CPU of the container's cpuset, which nproc reads. Waiting
# on, for the async profile's /delay: up to 16,384 timers a worker, as many
# as its connections. It left plaintext's instructions per request unchanged.
CMD ["/bin/sh", "-c", "WORKERS=${WORKERS:-$(nproc)} MAIL_SLOTS=256 MAX_WAITING=16384 exec /server http 8080"]
