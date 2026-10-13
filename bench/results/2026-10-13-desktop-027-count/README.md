bench/count.sh on 2026-10-13, Ryzen 7 5800X3D, WSL2 kernel 6.18.40.1, gcc 15.2.0, h2load
1.68.0, Goose a6249a4, RUNS=3: one worker on CPU 0, exactly 10 million plaintext
requests from h2load on CPUs 4-15 (8 threads, 256 connections, 16 in flight on each),
perf stat on the server's process. Task 027's builds, each of both loops: goose-27base
at 2afc12f, goose-27p1 at a9783c8, goose-27p2 at 070e830, goose-27p3 at dfc4a00
(0962213 builds the same code). goose-27TAG is the epoll loop, goose-27TAG-uring the
io_uring one.
