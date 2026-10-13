perf stat of bench/rest's Goose server on tier D's uploads alone, 2026-10-14, Ryzen 7
5800X3D, WSL2 kernel 6.18.54.1, gcc 15.2.0, Goose 0bdbd18. The server
(REST_DATA=build/rest TIER=d JSON=serialize WORKERS=4 LOOP=uring) on CPUs 0-3; wrk
4.1.0 with bench/rest/tier-d.lua's uploads role (1 thread, 32 connections, wrk-monotonic.so)
on CPUs 4-15, 5 s of warm-up and then 12 s, with
`perf stat -e instructions:u,cycles:u,L1-icache-load-misses,iTLB-load-misses,branch-misses -p PID -- sleep 10`
from its second second. Two rounds, each 27b, 27m, 27q in turn: 27b is 2afc12f, 27m
48f8e37, 27q 0e1f564 (bench/results/2026-10-14-desktop-027-count/README.md).
perf.txt has perf's CSV and wrk's rate for each.
