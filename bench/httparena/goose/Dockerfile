# The Goose server as an HttpArena entry. bench/httparena.sh copies this
# directory into HttpArena's frameworks/goose/ with the package (*.goose,
# http.build, shim/), the server's server/, and scripts/build.sh and
# scripts/goose.sh beside it.
FROM ubuntu:26.04 AS build
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends ca-certificates curl git cmake ninja-build gcc g++ \
        liburing-dev && \
    rm -rf /var/lib/apt/lists/*

# The Goose pin in README.md, the release scripts/goose.sh names, or with
# GOOSE_COMMIT that commit built from source.
ARG GOOSE_COMMIT=
COPY scripts/goose.sh /server/scripts/goose.sh
RUN GOOSE_COMMIT="$GOOSE_COMMIT" /server/scripts/goose.sh >/goose-path

COPY *.goose http.build /server/
COPY shim /server/shim
COPY server /server/server
COPY scripts/build.sh /server/scripts/build.sh
# The epoll loop: Docker's default seccomp profile blocks io_uring.
RUN GOOSE=$(cat /goose-path) LOOP=epoll /server/scripts/build.sh

FROM ubuntu:26.04
# The package links liburing on Linux, whichever loop the server runs.
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends liburing2 && \
    rm -rf /var/lib/apt/lists/*
COPY --from=build /server/build/server /server
# HTTP/1.1 on 8080, and h2c with prior knowledge on 8082, the port + 2.
EXPOSE 8080 8082
# One worker per CPU of the container's cpuset, which nproc reads. Waiting
# on, for the async profile's /delay: up to 16,384 timers a worker, as many
# as its connections. It left plaintext's instructions per request unchanged.
CMD ["/bin/sh", "-c", "WORKERS=${WORKERS:-$(nproc)} MAIL_SLOTS=256 MAX_WAITING=16384 exec /server http 8080"]
