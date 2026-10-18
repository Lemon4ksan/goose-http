# 047: The lane stop and placement on Windows, under MSVC

Status: in progress

Tasks 044 and 046 added C that every Windows build compiles and every worker runs, on
the `tina-alignment` branch: `shim/place.c`, which `http.build` lists under
`c_sources_windows`, and in `shim/mail.c` the stop flag, `mail_stop`, `mail_stopped`,
and `mail_queued`. Each loop calls `place_worker` as it starts, which returns at once
when no placement is loaded. So a compile error in either file breaks every Windows
program, whether it places threads or not. None of it has been built with MSVC or run on
Windows yet (2026-10-17).

The goal (2026-10-18): MSVC builds every feature, and each one works on Windows. Where a
Windows API can't do what a feature asks, the feature prints one warning and the program
runs without it, as placement already does on macOS. Only a placement file that doesn't
parse stops the start (task 046).

## What was checked without Windows (2026-10-17)

- `shim/place.c` and `shim/mail.c` compile with MinGW-w64's gcc, `-std=c11 -Wall
  -Wextra`, with no warnings ([Check the Windows shims without
  Windows](../docs/development.md#check-the-windows-shims-without-windows)).
- `shim/place.c` with `-D_MSC_VER=1930` under the same gcc: its MSVC branch, the
  `Interlocked*` counters, compiles. That is gcc with MinGW's headers, not `cl.exe`.
- `mail.c`'s new code uses only the atomics macros its MSVC branch already defines
  (`LOAD32_SEQ`, `STORE32_SEQ`, `LOAD64_SEQ`, `LOAD64_ACQUIRE`, `ADD64`), and the
  platform's `net_waker_wake`, an IOCP completion packet on Windows.

## What was checked on Windows (2026-10-18)

On the desktop (Ryzen 7 5800X3D, Windows 11 Pro 10.0.26300), in Git Bash, with MSVC
19.51 and clang-cl:

- Both shims compile under MSVC and clang-cl, and `test/run_tests.py` passes with each,
  the mail and placement tests included.
- `place_seat` failed as predicted, `0 of 3` rather than `1 of 3`. `place_current`'s
  Windows branch now reads the thread's own mask with `GetThreadGroupAffinity`, which
  Windows 7 and later have, and the test prints `3 of 3`.
- `bench/pinning/pinning.goose` with this placement starts, warns, and answers `/fast`
  and `/primes/N`:

  ```text
  set far = 1, 70
  workers = 4 each far incoming
  lane = 1 within 2 low
  ```

  ```text
  place: set far: cores 70 aren't the process's (0-15); skipped
  place: role workers: incoming needs Linux's SO_INCOMING_CPU; it does nothing here
  place: role workers: 4 threads on 1 cores; they share them
  ```

  `incoming` used to warn only when a listener failed (`can't set SO_INCOMING_CPU`),
  from each worker. `place_check` now warns once per role where the shim says the
  platform has no `SO_INCOMING_CPU` (`place_has_incoming`), and `place_listener` skips
  the call there.
- `scripts/test-http.sh` doesn't build `build/server.exe`: run it after
  `scripts/build.sh`, as `scripts/test.sh` does, or it tests an old server. One run
  against a server from 2026-10-14 failed `later`, which the current build passes.

## What each feature does on Windows

| Feature | Windows call | Where it can fall short |
|---|---|---|
| `mail_stop`, `mail_stopped`, `mail_queued` | none of its own; the wake is `net_waker_wake` | none found; `test/mail/mail_stop.goose` passes |
| Pin a thread (`take_seat`) | `SetThreadAffinityMask` on processor group 0 | a core above 63 never reaches it: `place_check` warns once at load that it isn't the process's and drops it from its set, so no worker warns |
| Read a thread's cores (`place_current`) | `GetThreadGroupAffinity` | a thread outside group 0 reads as no cores |
| The process's cores (`place_cpus`) | `GetProcessAffinityMask`, group 0 | a machine with more than 64 logical CPUs, or several groups, shows only group 0's, so a file naming the others warns that they "aren't the process's" |
| `low` | `SetThreadPriority(THREAD_PRIORITY_LOWEST)` | none found |
| `incoming` | none: `SO_INCOMING_CPU` is Linux's | one warning per role at load; `place_listener` skips the call, so no worker warns |
| Workers' index | `InterlockedExchangeAdd64` | none found |

clangd's "Unterminated `#pragma pack`" on `shim/place.c` is a false report: the file
pops it after its two structs, as `mail.c` does.

## A cost on every send under MSVC

`mail_send` reads the box's stop flag (`LOAD32_SEQ(&b->stopped)`) on every send, beside
the table's generation (`LOAD32_SEQ(&mail_table[i].gen)`), which it already read before
task 044. Every reply to a worker's box is a send. With GCC and Clang, `LOAD32_SEQ` is a
plain load on x86-64 and `ldar` on arm64. Under MSVC it is `InterlockedOr(p, 0)`, a
locked read-modify-write, which takes the cache line for itself, so senders to the same
box contend for it. Task 044 added the second of these per send.

Both can be `LOAD32_ACQUIRE` (`ReadAcquire`), a plain load on x64, without breaking
the ordering they exist for. Each comes right after `ADD64(&...senders, 1)`, an
`InterlockedExchangeAdd64`, which is a full barrier under MSVC on x64 and arm64, so no
later load moves before it; that is what the seq_cst loads give with C11 atomics. The
stop's argument is in `mail_stopped`'s comment, and the generation's in the file's
opening comment. Say in a comment beside the macro that the MSVC branch relies on the
barrier.

`mail_wait`'s spin reads `stopped` with `LOAD32_SEQ` too, beside `pending`, in each of
its 2,000 turns and again on each pass of the kernel wait, so under MSVC each of those
`InterlockedOr`s takes the box's cache line from the senders writing to it. `LOAD32_ACQUIRE` is enough there: no ordering hangs on that read, and a
flag the spin misses falls through to the kernel wait, which `mail_stop`'s wake ends.

Measure it before keeping it, as a change made for speed (AGENTS.md, "Benchmarks"): the
mail tests' ping-pong, and `bench/oha.sh` with a program that replies through `later`,
with and without the change, on the IOCP loop. Task 017 owns IOCP's speed and its
baseline.

### Measured: no gain, not kept (2026-10-18)

`bench/pinning/pinning.goose`'s `/primes/2`, where every worker mails one lane box and
the lane mails each reply back, under oha 1.16.0: `oha --no-tui -n 300000 -c 256`, a
fresh server per run, MSVC 19.51, `goose build --standalone`, the default 16 workers,
nothing pinned, old and new builds alternating with 15 s between runs for TIME_WAIT.
Ryzen 7 5800X3D, Windows 11 Pro 10.0.26300, Git Bash. Every response was 200.

| Change | Runs | Requests/s, min to max | Mean |
|---|---|---|---|
| none | 7 | 191,893 to 204,055 | 194,266 |
| `mail_send`'s two loads and `mail_wait`'s two reads of `stopped` with `ReadAcquire` | 7 | 190,462 to 201,776 | 194,569 |

An earlier set of 5 runs each, with only `mail_send`'s two loads changed and before
`mail_stopped` waited out in-flight calls, gave 206,572 to 216,798 (mean 212,089) and
214,491 to 220,213 (mean 216,801): overlapping too. Neither is faster beyond the runs'
spread, so `mail.c` keeps `LOAD32_SEQ`. The ping-pong wasn't measured apart: it waits on
a wake for every message, which costs far more than a locked load.

## Measuring placement on Windows

Task 045's spike measures the pinned layouts, which macOS can't run. WSL2 pins virtual
CPUs, so the desktop's real cores are pinned only natively. This contradicts
`docs/development.md` ("Windows isn't for benchmarks"): record the decision there if the
spike runs natively. `bench/pinning.sh` as written needs Linux for three things: the
server's cores (`taskset -cp`), `SERVER_CPUS` and `CLIENT_CPUS` (`taskset -c`), and
`sibling` (`/sys/.../thread_siblings_list`). The placement files themselves work on
Windows. A native run needs those three from Windows: the core count from `nproc` in Git
Bash, `start /affinity` or the placement file for the clients, and SMT siblings from
`GetLogicalProcessorInformationEx` (on the 5800X3D, CPU n and n+8 share a core, which can
be written down instead).

## Acceptance criteria

- [x] `scripts/test.sh` passes in Git Bash with MSVC (`CC=msvc`, the default) on the
      branch, the mail and placement tests included, and with `CC=clang-cl`
- [x] `place_current` reads the thread's own mask on Windows, and `place_seat` prints
      `3 of 3 threads read their seats back` there
- [x] Each Windows shortfall in the table above prints one warning and runs on without
      the feature, checked with a placement file that names a core above 63 and one
      that uses `incoming`; any other shortfall found is added to the table
- [x] goose-rest's tests pass with the branch's goose-http, as its
      `docs/development.md` runs them on Windows: its `scripts/test.sh`, natively in
      Git Bash and in WSL, at goose-http `d0e3fd4` (2026-10-18)
- [x] `mail_send`'s two loads, and `mail_wait`'s reads of `stopped`, read with
      `LOAD32_ACQUIRE` under MSVC, kept only if it measures faster beyond the runs'
      spread, and recorded here either way
- [ ] Tasks 044 and 045's Windows criteria ticked, or what failed recorded there
- [ ] If task 045's spike runs natively: `bench/pinning.sh` runs there, and the
      decision to measure on Windows is in `docs/development.md`
