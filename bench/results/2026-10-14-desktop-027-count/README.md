bench/count.sh on 2026-10-14, Ryzen 7 5800X3D, WSL2 kernel 6.18.54.1, gcc 15.2.0, h2load
1.68.0, Goose 0bdbd18, RUNS=3: one worker on CPU 0, exactly 10 million plaintext
requests from h2load on CPUs 4-15 (8 threads, 256 connections, 16 in flight on each),
perf stat on the server's process. Task 027's builds, each of both loops, made from
git archive of each commit: goose-27b at 2afc12f (the baseline), goose-27m at 48f8e37
(main: p2, p4, p5, and p6), goose-27q at 0e1f564 (task-027-p3, p3 on main).
goose-27TAG is the epoll loop, goose-27TAG-uring the io_uring one.
