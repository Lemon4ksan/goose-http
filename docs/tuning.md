# Production tuning

Start without tuning: the defaults run one worker per hardware thread and let the OS
place every thread. Change the worker count when the program runs under a CPU quota.
Add a placement file only after a measurement on that kind of machine shows a gain: so
far, no layout has beaten the default on the one machine measured
([what has been measured](#what-has-been-measured)). The calls are in the API's
[placement](api.md#placement) section; this page says when to use them.

## Worker count

`Config.workers` sets how many workers `http::worker_count(cfg)` returns, and
`http::run` spawns that many ([config and shutdown](api.md#config-and-shutdown)). The
default, 0, depends on the platform:

| Platform | Default workers |
|---|---|
| Linux | One per hardware thread the process may use, SMT siblings included: Goose's `hardware_threads()` counts the affinity mask, so `taskset` or a cpuset lowers it |
| macOS | One per performance core's logical CPU (`hw.perflevel0.logicalcpu`, 8 on an M1 Pro), or one per hardware thread on an Intel Mac; each worker takes the user-interactive QoS class |
| Windows | One per hardware thread |

A CPU quota without a mask, such as Docker's `--cpus` or a Kubernetes CPU limit, leaves
every core in the mask, so the default counts the host's hardware threads. Set
`Config.workers`, or the workers' count in the placement file, to the quota instead.

Lanes, the threads that take slow work from the workers
([slow work](patterns.md#slow-work)), run beside the workers. An idle lane thread takes
no CPU, and a busy one at most one core, taken from the workers on the cores it lands
on.

## When placement helps

Placement decides which cores each thread runs on, and at what priority. It's opt-in:
without a placement file, every thread floats, and the OS decides where it runs.

Placement is experimental: it's opt-in and free when unused, but not yet measured to
help on real cores (only macOS has been measured, with no gain), so its grammar and
calls may be trimmed or removed once measured.

Placement may help a dedicated machine with cores to spare, where a lane does CPU work
beside workers whose short requests need a low tail latency: the lane gets cores of its
own, or a low priority, so short requests don't wait behind it. Whether it does is
unmeasured on real cores so far.

It can't help in these cases:

- **1 or 2 cores.** No core is left to give a lane. Only `low` applies: it lets the
  workers go first.
- **A CPU quota without a mask.** The quota limits CPU time, not which cores the
  container gets, so the cores a file names are shared with whatever else the host
  runs.
- **A VM, including WSL2 and Docker on macOS.** A pin there pins a virtual CPU, which
  the host moves between its cores, so nothing real is pinned.
- **macOS.** It has no CPU affinity; only `low` applies
  ([what each platform does](#what-each-platform-does)).

## Placement files

The code names roles: the workers (`Config.role`, `"workers"` by default) and each
lane. A placement file, one per kind of machine, maps roles to cores. A repository
holds as many as it has kinds of machine, such as `place/api-eu-1.place` and
`place/dev.place`, and each deployment names its own, so a new machine needs a new
file, not a new build.

`http::place_load()` reads the file the command line names with `--place FILE` or
`--place=FILE`, or else the one the `GOOSE_PLACE` environment variable names. A
program that parses its own flags passes the path: `http::place_load(path)`. With no
file named, every thread floats.

The workers take their seats themselves, from `Config.place` and the index `http::run`
gives each in `Config.worker`. A lane's thread is the
program's, so the program hands it its seat, and the thread takes it first, before it
touches memory of its own: Linux puts a page on the NUMA node of the thread that first
writes it.

```rust
thread_fn hasher(box: http::Box, at: http::Seat) {
    http::take_seat(at);
    while !http::mail_stopped(box) {
        http::mail_wait(box, -1);
        http::mail_take(box) { key, tag, bytes => /* ... */ };
    }
    http::mail_close(box);
}

fn main() {
    http::exit_on_error(http::stop_on_signals());
    let place = http::place_load();
    let cfg = http::Config { port: 8080, place: http::place_ref(place), mail_slots: 256, max_waiting: 1024, .. };
    let b, err = http::mail_open(256, 64);
    http::exit_on_error(err);
    let lane = thread_spawn(hasher, b, http::place_seat(place, "hasher", 0));
    http::run(cfg, http::address(b, 0), worker);
    http::mail_stop(b);
    thread_wait(lane);
}
```

For a lane of several threads, each with a box of its own,
`http::place_threads(place, "hasher", 1, 2)` gives the count: the file's, up to the
code's most of 2, or the code's 1 where the file gives none. Thread `i` takes
`http::place_seat(place, "hasher", i)`. goose-rest's lanes do this for the program.

`bench/pinning/pinning.goose` is a whole program that loads a placement file.

## The file's grammar

A file has a line for each set or role. A `#` starts a comment at the start of a line
or after a space or tab. Blank lines, tabs, and CRLF line ends are allowed.

```ini
set NAME = CORES [exclusive]
ROLE = [COUNT] [each SET | within SET | core N] [low] [incoming]
```

| Word | Meaning |
|---|---|
| `set NAME = CORES` | A named set of cores, which roles refer to |
| `exclusive` | No role but those that name the set runs on its cores ([exclusive sets](#exclusive-sets)) |
| `COUNT` | The role's threads, 1 or more; without it, the code's count |
| `each SET` | Each thread on a core of its own of the set, in order, wrapping around when there are more threads than cores |
| `within SET` | Every thread anywhere within the set |
| `core N` | Every thread on core `N` |
| `low` | At low priority ([low](#low)) |
| `incoming` | Each thread's listener gets the connections its core's interrupts received ([incoming](#incoming)) |

`CORES` is a list of cores and ranges, such as `0-3, 8`, from 0 to 1023. `each` and
`within` take a set's name, or cores, which become a set of the role's own. A name has
1 to 31 letters, digits, `_`, or `-`. A file holds at most 16 sets, the roles' own
included, and 32 roles. A role with no `each`, `within`, or `core` floats; a role the
file doesn't name keeps the code's count and floats too. A floating thread runs on the
cores no exclusive set holds.

The workers' count from the file wins over `Config.workers`, with no bound, since every
worker is the same. A lane's count is bounded by the code: a count above the most the
code allows is cut to it, with a warning.

### Two machines

A desktop with 8 cores and 16 hardware threads (a Ryzen 7 5800X3D, where CPU n and n+8
share a core):

```ini
# place/desktop.place
set front = 0-3        exclusive   # no role but the workers runs here
set flows = 4-5                    # shared by two lanes
set db    = 6-7, 12-15

workers  = 4 each front incoming   # one per core
hasher   = 1 within flows
checkout = 1 within flows          # shares cores with hasher
writer   = core 7                  # the code's count
reports  = 4 within db             # SQLite readers
# A lane not named here keeps the code's count and floats on 4-15.
```

A laptop with 2 cores, where nothing is pinned:

```ini
# place/dev.place
workers = 2
hasher  = 1 low
```

Which cores share an L3 cache or a NUMA node is for the file's author to know and write
down: the package reads no topology.

### Exclusive sets

An exclusive set keeps its cores for the roles that name it. A role whose `each`,
`within`, or `core` names cores of an exclusive set it doesn't name loses those cores,
with a warning; when none are left, it floats. A floating thread runs on the cores no
exclusive set holds.

An exclusive set holds hardware threads, not cores. In the desktop file, cores 0-3's
SMT siblings, 8-11, aren't in `front`, so a floating lane can run on them. Put the
siblings in the set to keep them free.

When the exclusive sets hold every core the process may use, nothing is left to float
on: a floating thread then runs on any core, the exclusive ones included, with one
warning.

### Low

`low` lowers a thread's priority, so that the OS runs it after the other threads. It
works on any number of cores, 1 included, and on every platform. On macOS the work
also runs slower: it takes the background QoS class, which on Apple silicon runs only
on the efficiency cores, and also throttles the thread's I/O. On an M1 Pro, a CPU lane
at `low` completed about 40% fewer jobs
([what has been measured](#what-has-been-measured)). Use it for work that can wait, not to make the workers faster.

### Incoming

`incoming` on a role whose threads each have one core, such as `each` or `core`, sets
`SO_INCOMING_CPU` on each worker's listener (Linux): among the listeners on the port,
the kernel gives a connection to the one whose core processed its packets, so it stays
on the core where its interrupts arrive. On a role whose threads have several cores, or
float, it can't apply, and prints a warning. Only workers have listeners: on a lane's
role it does nothing.

## What each platform does

| | Linux | macOS | Windows |
|---|---|---|---|
| The process's cores | Its affinity mask (`sched_getaffinity`) | Every logical CPU (`hw.logicalcpu`) | Its affinity mask in processor group 0 (`GetProcessAffinityMask`), cores 0-63 |
| `each`, `within`, `core` | `sched_setaffinity` | Nothing: one warning, and every thread floats | `SetThreadAffinityMask`, within group 0 |
| `low` | nice 10 and `SCHED_BATCH` | The background QoS class | `THREAD_PRIORITY_LOWEST` |
| `incoming` | `SO_INCOMING_CPU` | Nothing: one warning | Nothing: one warning per role |
| Tested | In Docker on macOS (arm64), and in WSL2 | Natively | Natively, built with MSVC and with clang-cl |

On macOS, each worker sets the user-interactive QoS class first and then takes its seat,
so `low` on the workers' role replaces it with the background class.

## Warnings and errors

Nothing about the hardware stops the start. `place_load` checks the file against the
machine and prints a warning, prefixed `place:`, to stderr for each thing the machine
can't do, then runs with what it could apply:

- Cores the process can't use, such as a core the machine lacks or one outside a
  container's cpuset: they're skipped.
- A role on cores an exclusive set holds: it runs on the rest, or floats.
- Exclusive sets that hold every core the process may use.
- `incoming` on a role whose threads have several cores or float, or on a platform that
  can't pin or has no `SO_INCOMING_CPU` (Windows).
- A platform that can't pin threads (macOS): every thread floats.
- More threads than a role's `each` set has cores: they share them.
- A lane's count above the code's most: it's cut to it.

A thread that fails to take its seat, to lower its priority, or to set
`SO_INCOMING_CPU` prints a warning from that thread and goes on where it is.

A placement file that can't be read or doesn't parse stops the program with exit code
2, after a message that names the file and line, such as
`place: desktop.place:4: no set front above`.

## What has been measured

On macOS, no layout beat the default (task 045, 2026-10-17). The machine was an M1 Pro
(8 performance and 2 efficiency cores) on macOS 26.3.1 (Darwin 25.3.0), with Goose
`v2026.2`, at `e73ccb82`. `bench/pinning.sh` ran with `RUNS=5 SECONDS_EACH=30 WARMUP=5`,
the layouts alternating. A short route, `/fast`, ran at a fixed rate over 64
connections, beside a CPU lane counting primes at a rate that kept it about 80% busy,
over 16 connections; both clients were oha 1.16.0 with `--latency-correction`, on the
same cores as the server, since macOS can't keep them apart. `over` and `nice` ran 10
workers and `fewer` 9, and the lane was one thread.

| `/fast` rate | Layout | `/fast` p99, median of 5 (range) | Primes done/s |
|---|---|---|---|
| 24,331/s, 70% of `over` alone | `over`: 10 workers, all floating | 4.49 ms (4.14–4.65) | 1,771 |
| | `fewer`: 9 workers | 5.17 ms (4.91–6.95) | 1,771 |
| | `nice`: the lane at `low` | 6.39 ms (6.35–6.47) | 1,060 |
| 12,165/s, 35% | `over` | 4.01 ms (3.99–4.02) | 1,771 |
| | `fewer` | 4.00 ms (3.95–4.04) | 1,771 |
| | `nice` | 3.96 ms (3.91–3.99) | 998 |

Neither `fewer` nor `nice` beats `over` on `/fast`'s p99 by more than the runs' spread:
at 70% both are worse, and at 35% `nice` is 1% lower, with ranges that touch. `nice`
cost the lane about 40% of its rate. Task 045 has the full table, p50 and p99.9
included.

The layouts that pin threads, each worker on its own core, a lane on a core of its own,
on a worker's SMT sibling, or within a set, and `incoming`, haven't been measured on
real cores yet. They need bare-metal Linux, and that run is pending (task 045). Until
it's done, no measurement shows that pinning helps.
To measure a machine of your own, run `bench/pinning.sh`
([benchmark scripts](../bench/README.md)).
