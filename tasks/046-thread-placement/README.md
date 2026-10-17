# 046: Where threads run, and what lanes become, designed against Tina

Status: todo

Tina (at `d129f67`) plans every thread's place before it starts: one shard per core,
pinned, each named by `target_core` in a boot spec that doesn't change while it runs, and
work routed to a shard by `key_to_shard` (its `docs/concepts/thread_per_core.md` and
`docs/concepts/designing_shard_topologies.md`). goose-http plans none of it. Workers float
over every hardware thread, lanes float on top of them, and an app picks a lane's thread
by hand. This task designs the opinionated version for this architecture: not a copy of
Tina, but as close to its locality as Goose and the platforms allow, and opt-in, so a
program that sets nothing runs as it does today. A Goose thread already owns all its
memory, so a pinned thread gets most of the locality Tina builds arenas for.

The design covers, in one place, the Tina-inspired changes discussed on 2026-10-16:

- **Placement:** below.
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

## Placement, as agreed on 2026-10-17

- **Code names roles; a file per machine places them.** The program names its
  workers and each lane. A placement file, chosen at startup (`--place
  place/api-eu-1.place`, or an environment variable naming it), maps each role to cores.
  A repository holds as many as it has kinds of machine, and each deployment names its
  own. A program run without one floats every thread, as today. Changing a machine
  changes the file, not the build.
- **Code bounds each lane's threads; the file chooses within the bounds.** Today the
  code alone sets every count: `Config.workers`, 0 by default, starts one worker per
  hardware thread, SMT siblings included, and each lane has exactly the threads the
  program spawns for it. An idle lane thread takes no CPU, and a busy one at most one
  core, so a lane never uses more cores than it has threads; what a busy lane takes is
  time from the workers on the cores it lands on. With placement, `lane_open` gives a
  default and a maximum (a SQLite writer's is 1, since SQLite allows one writer), and the
  file may pick any count up to it; a count above it is cut to it, with a warning. A lane
  the file doesn't name keeps the code's default and floats on the cores no exclusive set
  holds.
  Tina fixes its layout in a boot spec compiled into the program; Vx's machine files
  (`vxc --machine`, [vxlang.org](https://vxlang.org/docs/machine-files.html)) describe
  hardware to the compiler. Here the file is read at run time and holds only cores.
- **Cores and sets of cores, nothing the package discovers.** A role is pinned to one
  core, or each of its threads to its own core of a set, or kept anywhere within a set.
  Which cores share an L3 or a NUMA node is the operator's to know and write down; the
  package reads no topology. Hardware descriptions may come later, once a machine shows
  they matter.
- **Named sets of cores** (the name is open: zone, cpuset, pen). A set is named once and
  roles refer to it. A set can be exclusive: the workers' set shares cores with no lane's,
  while lanes' sets may overlap each other, so two workflows can share two cores and
  neither ever runs on a worker's.
- **The start never fails on hardware.** A core that doesn't exist, a set smaller than its
  threads (they wrap around), an overlap with an exclusive set, and a platform with no
  affinity (macOS) each print one warning, and the program runs with what it could
  apply. A file that doesn't parse stops the start, as any malformed configuration does.
- **A thread places itself first**, before it touches its own memory: Linux puts a page
  on the NUMA node of the thread that first writes it.
- **Low priority** is the option for any machine, 1 core included: `nice` and
  `SCHED_BATCH` on Linux, a background QoS class on macOS.

### What the design still has to settle

- **The file's format.** Goose has `env`, `args`, and `read_file`, and no parser for TOML
  or YAML; a line format (`name = value`) parses in a few lines of Goose. The same parser
  could load a `.env` file for development. In production, systemd's `EnvironmentFile`
  and Compose's `env_file` already load one into the environment that `env` reads.
- **The name** for a named set of cores.
- **Who opens a box.** `mail_open` in `main` touches a box's slots on `main`'s node; on a
  NUMA machine the owner thread may have to open it.
- **Connections to cores.** With `SO_REUSEPORT`, Linux spreads connections by hash, not
  by the core whose NIC queue received them, so a pinned worker still gets connections
  another core processed. `SO_INCOMING_CPU`, or a reuseport BPF program, keeps each on
  the core of its interrupt. Task 045 measures it as a layout of its own.
- **Database lanes.** With SQLite, or Turso's embedded engine, a query runs in the lane's
  own thread: parsing, the B-tree, and the page cache are CPU and memory work there, so a
  reader lane may gain from a core and a warm cache like a CPU lane does. Only a commit's
  `fsync`, or a remote Turso server, is a wait. The spike says which.
- **Containers.** `hardware_threads()` already counts the affinity mask (Goose `92afe05`,
  in `v2026.2`). A CPU quota without a mask still says nothing about which cores the
  program may use.

## Acceptance criteria

- [ ] `docs/architecture.md` or a design doc: the decisions above, each with its reason,
      what Tina does, and why this differs where it does
- [ ] `before-after.html` in this folder, opened from disk: today's code beside the
      design's for workers, a CPU lane, a database lane of N threads with a key, a writer
      with group commit, a lane that stops, and a placement file for two environments; it
      states which parts tasks 044 and 045 settle
- [ ] Task 045's layouts cover the placements the design proposes, on bare-metal Linux
      (WSL2 pins to virtual CPUs): pinned workers, connections kept on their interrupt's
      core, a CPU lane and a SQLite reader lane on a core of their own or a worker's SMT
      sibling, and a lane kept within a set; a placement that doesn't beat floating by
      more than the runs' spread is dropped, and recorded there
- [ ] A placement for a NUMA or multi-L3 machine is measured on one, or marked unmeasured:
      the benchmark desktop (Ryzen 7 5800X3D) has one L3 and one node
- [ ] The accepted parts: decisions in `docs/decisions.md`, then implementation tasks for
      goose-http (placement file, placement, low priority) and goose-rest (lanes of N,
      group commit)
