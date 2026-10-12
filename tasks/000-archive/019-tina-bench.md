# 019: Tina in the benchmark

Status: done (asked for 2026-10-12, done 2026-10-13)

Tina (`pmbanugo/tina`), a thread-per-core framework in Odin whose mailboxes task 015
took ideas from, has an HTTP/1.1 server. It joins `bench/` as `tina`, built in its
documented production configuration, beside odin-http, the other Odin entry.

## Acceptance criteria

- [x] `bench/tina/main.odin` serves `/plaintext` and `/json` as the other entries do,
      and `bench/build.sh` builds it at a pinned commit (2026-10-12)
- [x] A quick relative comparison in Docker on the Mac, recorded below (2026-10-12)
- [x] Each of `scripts/http_client.py`'s checks that Tina fails, in `bench/README.md`'s
      table, with why (2026-10-13)
- [x] The full `bench/run.sh` matrix on the benchmark desktop, with `SERVERS` naming
      `tina`, in `docs/results.md` (2026-10-12,
      [the full field](../../docs/results.md#the-full-field))

## The entry

Tina `a2e8d4d` (2026-10-12), built with Odin `dev-2026-10`, the version odin-http uses;
its README's badge names `dev-2026-05`, and `dev-2026-10` builds it unchanged. Tina's
production build, from its `docs/guides/odin_compilation.md`: `-o:speed`, its own
assertions off with `-define:TINA_ASSERTS=false`, and Odin's bounds checks on, which it
requires. One shard per worker, 4,096 connection slots per shard. Responses carry
`Server`, `Date`, `Content-Type`, and `Content-Length`.

Tina has two ingress modes. Its docs call `Coordinator`, one listener that hands
accepted sockets to the other shards, the primary path, and its own
`examples/http_server_for_bench.odin` uses it; `Reuse_Port`, a listener per shard, is
the documented fallback. `Reuse_Port` served 2.5 times the requests in every cell below,
and had no wrk timeouts, so the entry uses it with more than one worker, as `bench/`
runs every competitor in its fastest documented configuration; `INGRESS=coordinator`
picks the other.

## A quick comparison (2026-10-12)

Docker Desktop 29.8.2 on the MacBook Pro M1 Pro of `docs/development.md`, kernel
7.0.14-linuxkit, 10 CPUs, image `goose-http-dev3` with wrk 4.1.0, `--security-opt
seccomp=unconfined`, so both run on io_uring where they choose it. Goose at `3eff01d`,
Goose compiler `5c83a5a`. Each server with 3 workers or shards on CPUs 0-2, wrk on CPUs
3-9 with 7 threads, 5 s per run, 3 rounds alternating the servers. Plaintext pipelined
16 deep with `scripts/pipeline.lua`, JSON not pipelined, as `bench/run.sh` runs them. In
requests per second, the range of the 3 runs:

| Test | Goose io_uring | Goose epoll | Tina, `Coordinator` | Tina, `Reuse_Port` |
|---|---:|---:|---:|---:|
| plaintext, 256 connections | 5.62-5.79 M | 5.63-6.04 M | 0.29-0.31 M | 0.78-0.84 M |
| plaintext, 4,096 connections | 5.40-5.60 M | 5.51-5.70 M | 0.20-0.25 M | 0.57-0.65 M |
| JSON, 256 connections | 680-714 K | 674-699 K | 241-250 K | 571-613 K |

- Unpipelined, Tina with `Reuse_Port` is 10-20% behind both Goose loops.
- Pipelined, it serves 7-10 times fewer requests than Goose: the pipelining barely raises
  its rate over JSON's. Why isn't checked in its code yet.
- wrk counted timeouts in each of `Coordinator`'s 4,096-connection runs (200-1,171), and
  in one Goose run each on epoll plaintext at 256 connections (99) and io_uring JSON
  (455).

The Docker VM isn't the benchmark machine, and 3 short rounds show the shape, not
figures for the README.

On the desktop (2026-10-12), `bench/instructions.sh` (one shard on CPU 0, plaintext
pipelined 16 deep at 256 connections, wrk on CPUs 4-15, 3 runs): Tina served 216-221 K
requests per second at 19,983-20,260 instructions and 18,566-18,751 cycles per request,
8,230-8,334 of the instructions in user code, with 190 MB of peak RSS. Goose's epoll loop,
in the same runs: 1.65-1.68 M, 2,475-2,530, and 1,995-2,036, with 2.4 MB
([results](../../docs/results.md#instructions-per-request)).

In the desktop's full matrix (2026-10-12, Goose `73dd28c`, 4 workers), Tina served
plaintext at 0.47-0.74 M requests per second, against Goose io_uring's 6.02-6.74 M, and
JSON at 446-504 K, against 487-498 K: at 256 connections it led Goose's io_uring loop by
1%. It held 755 MB with 4 workers and 190 MB with 1, against 8.9-15 and 4.0-6.2 MB. At
4,096 connections with 1 worker, wrk counted 34,865 socket errors and h2load a p99 of
3.7 s.

`scripts/http_client.py` against it, in Docker: `tfb` fails at its absolute-form request
(`GET http://host/plaintext`), which Tina answers with 400, and `pipeline` gets a
connection reset. That request has since moved to `forms`; on the desktop (2026-10-13)
Tina passes `tfb`, and `bench/README.md` lists what it fails, with why.
