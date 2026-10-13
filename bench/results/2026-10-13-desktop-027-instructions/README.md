bench/instructions.sh on 2026-10-13, Ryzen 7 5800X3D, WSL2 kernel 6.18.40.1, gcc 15.2.0,
wrk 4.1.0, Goose a6249a4, RUNS=3: one worker on CPU 0, plaintext pipelined 16 deep at 256
connections, wrk on CPUs 4-15 with 8 threads for 20 s, perf stat on CPU 0 for 10 s from
5 s in. Task 027's builds, as in 2026-10-13-desktop-027-count.
