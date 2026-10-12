bench/instructions.sh on 2026-10-12, Ryzen 7 5800X3D, WSL2 kernel 6.18.40.1, Goose at
47876ad with Goose 5c83a5a: one worker on CPU 0, plaintext pipelined 16 deep at 256
connections, wrk on CPUs 4-15 with 8 threads for 20 s, perf stat on CPU 0 for 10 s from
5 s in. Runs 2 and 3 of the first eight servers, and all runs of the last four, came from
separate invocations after the script began waiting for the port to free.
