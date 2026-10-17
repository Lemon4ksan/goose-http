# 046: Where threads run, and what lanes become, designed against Tina

Status: todo

Tina (at `d129f67`) plans every thread's place before it starts: one shard per core,
pinned, each named by `target_core` in a boot spec that doesn't change while it runs, and
work routed to a shard by `key_to_shard` (its `docs/concepts/thread_per_core.md` and
`docs/concepts/designing_shard_topologies.md`). goose-http plans none of it. Workers float
over every hardware thread, lanes float on top of them, and an app picks a lane's thread
by hand. This task designs the opinionated version for this architecture: not a copy of
Tina, but as close to its locality as Goose and the platforms allow, and opt-in, so a
program that sets nothing runs as it does today.

The design covers, in one place, the Tina-inspired changes discussed on 2026-10-16:

- **Placement.** Any thread, a worker or a lane, can stay floating (the default), be
  pinned to one core the package picks, to one core named, or be kept within a named set
  of cores. A set lets a program plan around the cache hierarchy and NUMA nodes: workers
  on one L3 or one node, a CPU lane on the SMT sibling of a worker or on a core of its
  own, a database lane on the node its disk and NIC hang off.
- **Lanes of N threads.** A lane is N threads, each with its own box and database
  connection. A job goes to the first box with room, or, given a key, to the thread the
  key always picks, Tina's `key_to_shard`. A lane's threads take their placement from
  the lane.
- **Group commit** on a writer lane: every waiting job in one transaction, each in a
  savepoint, replies after the commit.
- **Stopping a lane** is task 044, and the measurement is task 045's spike; this task
  gives both the API they settle on.

What stays out, decided 2026-10-16: lanes as processes, and a supervisor in the package
(`docs/decisions.md`, "A crash ends the process, and a service manager restarts it").
A restart per thread waits on Goose (`docs/goose-findings.md`, "An abort ends every
thread of the program").

## What the design has to settle

- **The placement API.** A per-role setting in `Config` for workers, the same for each
  lane, and a call a thread makes on itself. How a core set is written (`"0-5,8"`, as
  `taskset` and cgroups write it, or a list), and what "the package picks" means: the
  next free physical core, SMT siblings last.
- **Topology.** What the package reads, and on which platform: on Linux, `/sys/devices/
  system/cpu/cpu*/topology` (cores and SMT siblings), `cache/index3/shared_cpu_list` (L3
  groups), and `/sys/devices/system/node` (NUMA); on Windows,
  `GetLogicalProcessorInformationEx` and processor groups past 64 CPUs. Whether the
  package names groups ("the L3 of core 0", "node 1") or only takes core numbers and
  leaves the plan to the program.
- **Memory placement.** Linux places a page on the node of the thread that first
  touches it. A Goose thread can pin itself only once it runs, after the runtime copied
  its arguments and globals, and `mail_open` in `main` touches a box's slots on `main`'s
  node. The design says who opens a box, and whether pinning has to come first in a
  thread.
- **Connections to cores.** With `SO_REUSEPORT`, Linux spreads connections by hash, not
  by the core whose NIC queue received them. `SO_INCOMING_CPU`, or a reuseport BPF
  program, keeps a connection on the core of its interrupt. The design says whether
  pinned workers use either.
- **Platforms without affinity.** macOS has none; it already keeps workers on the
  performance cores with a QoS class (`sys.goose`, `net_worker_start`). A low-priority
  lane there gets a background QoS class instead of a core. WSL2 pins to virtual CPUs,
  not physical cores, so its numbers don't speak for bare metal.
- **Containers and quotas.** `hardware_threads()` already counts the affinity mask
  (Goose `92afe05`, in `v2026.2`). A CPU quota without a mask still says nothing about
  the cores the program may use; the design says what a pinned layout does then.
- **Fewer cores than threads.** On 1 or 2 cores nothing can have a core of its own: the
  design says what each setting does there, and that it never fails the start.

## Acceptance criteria

- [ ] `docs/design/placement.md`, or a section of `docs/architecture.md`: the decisions
      above, each with its reason, what Tina does, and why this differs where it does
- [ ] `before-after.html` in this folder, opened from disk: today's code beside the
      design's for workers, a CPU lane, a database lane of N threads with a key, a writer
      with group commit, and a lane that stops; it states which parts tasks 044 and 045
      settle
- [ ] Task 045's layouts cover the placements the design proposes: pinned workers, a
      lane on a core of its own, a lane on a worker's SMT sibling, and a lane kept in a
      set; a placement the spike can't separate from floating by more than the runs'
      spread is dropped, and recorded there
- [ ] A topology a NUMA or multi-L3 machine needs is measured on one, or marked unmeasured:
      the benchmark desktop (Ryzen 7 5800X3D) has one L3 and one node
- [ ] The accepted parts: decisions in `docs/decisions.md`, then implementation tasks for
      goose-http (placement, topology) and goose-rest (lanes of N, group commit)
