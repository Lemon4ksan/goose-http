# 032: One bench harness that goose-rest can reuse

Status: todo (asked for 2026-10-14)

goose-rest, the REST framework on this package, waits for its first benchmark run on
the benchmark desktop, the reference machine. It should run on this repository's REST
tiers with the harness this repository uses, not a copy of it. Today each script carries
its own: `bench/rest.sh`, `bench/run.sh`, and `bench/files.sh` each start and stop
servers, wait for a port, read a server's CPU ticks from `/proc`, run wrk, and write
`env.txt` and a summary, with small differences between them.

Order (asked for 2026-10-14): this goes after task 027's API work and the merges that
wait on the overnight benchmarks (task 027, "Pending"), and before goose-rest's first
run, which comes once the HTTP changes are on `main`.

## Acceptance criteria

- [ ] The common parts in one sourced file, for example `bench/lib.sh`: starting a server
      pinned to `SERVER_CPUS` and waiting for its port, stopping it and waiting for the
      port to free, CPU ticks and peak RSS (VmHWM) of a PID, a pinned wrk run, `env.txt`
      (machine, kernel, commits, compilers), and the medians and ranges of a cell's runs
- [ ] `bench/rest.sh`, `bench/run.sh`, and `bench/files.sh` use it, and produce the same
      result files as before: checked by running one short cell of each before and after
- [ ] Another repository can run the REST tiers against its own server binary: a
      documented way to name a binary, its start command, and its environment, with
      `bench/rest/check.py` run first, as for the servers here
- [ ] `bench/README.md` describes the harness and how goose-rest calls it
