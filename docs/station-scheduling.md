# A station's machine shared by many agents

Many chats' agents send builds and tests to the same big machine (`station_task`), and the agents of the chats on that
machine run commands of their own. Each agent looking at the load and starting when it sees room is how they trod on
each other: several saw an idle machine at once and all started, and nobody knew how much a task would take (a Zig
build once took 42 GiB and the machine went down). The station itself decides now, by what it measures; nothing is
estimated beforehand, since the same command takes more or less by its caches.

## The queue (jobs/admit.ts, in jobs/jobs.ts)

Other stations' tasks (`remote_…` jobs) go through it; an agent's own jobs and services do not.

- With none of the queue's tasks running, the first waiting starts, however busy the machine is: one always goes on.
- Another starts only once the last one started has had 30 s to get going and the CPUs were busy less than 80% over the
  last 20 s. Tasks come in one by one while there is room.
- None starts while the system says its memory is under pressure (macOS's `kern.memorystatus_vm_pressure_level` warn
  or critical; elsewhere under a tenth of the memory available).
- A task prepared with `screen: true` (windows, a simulator, screenshots) starts only while no other such task runs.
- Of the sessions with tasks waiting, the one whose task last started longest ago goes first, its oldest task.
- A task started beside others gets `STILLFAIL_CPUS`, and `MAKEFLAGS`, `CARGO_BUILD_JOBS`, `CMAKE_BUILD_PARALLEL_LEVEL`
  where its environment has none, with how many CPUs were free (at least 1). One started alone gets none of them.

A waiting task is a job with `state: running` and `queued: true` (the jobs table's `queued` and `screen` columns):
running as far as its agent and an older source station are concerned, with no process yet. `station_task start` and
`get` answer `queue: {place, why, note}` while it waits. Stopped while waiting, it never runs. A station that restarts
takes up what still waits, as it never ran (unlike a lost running task, which is failed rather than run again). The
queue looks at the machine every 5 s while a task waits, and when a task of its own ends.

## Memory (jobs/memory.ts)

Watched every 10 s (5 s under pressure, then with macOS's footprints from `top`, which count what is compressed or
swapped out; resident memory otherwise). What is watched: the station's jobs (a job's process group and all its members
started) and each command an agent's runtime started (a child of the runtime's process, and all under it). The
runtimes, the runners and the station are never stopped. A command of a runtime shared by sessions (codex's host) is
its session's whose directory it runs in.

- Something over an eighth of the machine's memory (2 GiB at least): its agent is told, again each time it doubles.
  Nothing is stopped for it.
- The memory under pressure: the agents of the three largest (of 512 MiB or more) are told, once while it lasts.
- The system about to run out (critical): the largest is stopped (SIGTERM, SIGKILL 5 s later) and its agent told why;
  another only 15 s later, if it is still critical. Pausing would not free its memory, and only the largest helps.

Other stations' tasks are told through their notices, which go back to the session that asked; the station's own
sessions through the hub. Windows reads no process table: there only the queue's memory check applies.
