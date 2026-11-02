# A station's machine shared by many agents

Many chats' agents send builds and tests to the same big machine (`station_task`), and the agents of the chats on that
machine run commands of their own. Each agent looking at the load and starting when it sees room is how they trod on
each other: several saw an idle machine at once and all started, and nobody knew how much a task would take (a Zig
build once took 42 GiB and the machine went down). The station itself decides now, by what it measures; nothing is
estimated beforehand, since the same command takes more or less by its caches.

## The queue (jobs/admit.ts, in jobs/jobs.ts)

Other stations' tasks (`remote_…` jobs) go through it; an agent's own jobs and services do not.

- With none of the queue's tasks running, the first waiting starts, however busy the machine is: one always goes on.
- Another starts only once the CPUs, looked at for at least 10 s since the last one started (while it still runs),
  were busy less than 80% (over the last 20 s when it has ended). Tasks come in one by one while there is room.
- None starts while the system says its memory is under pressure (macOS's `kern.memorystatus_vm_pressure_level` warn
  or critical; elsewhere under a tenth of the memory available).
- A task prepared with `screen: true` starts only while no other task has the screen (below), and no command that
  asked for it before the task came still waits for it.
- Of the sessions with tasks waiting, the one whose task last started longest ago goes first, its oldest task.
- A task started beside others gets `STILLFAIL_CPUS`, and `MAKEFLAGS`, `CARGO_BUILD_JOBS`, `CMAKE_BUILD_PARALLEL_LEVEL`
  where its environment has none, with how many CPUs were free (at least 1). One started alone gets none of them.
- One explicitly `small: true` task may start beside busy work without waiting for a CPU sample, provided memory is
  not under pressure. Its separate slot holds one task at a time; it is told to use one CPU. This is for brief offscreen
  work such as rendering a picture with prebuilt tools, not a build, test suite, video or task using the screen. An
  older station is checked at prepare and rejected rather than silently placing it in the ordinary queue.

A waiting task is a job with `state: running` and `queued: true` (the jobs table's `queued`, `screen` and `small` columns):
running as far as its agent and an older source station are concerned, with no process yet. `station_task start` and
`get` answer `queue` while it waits: its place, its own blocker and note; `cause` distinguishes a CPU sample still being
taken from a sample that actually found the CPUs busy. `decision` contains the queue's CPU sample (share, seconds and
time, or null until it has enough ticks) and the last memory pressure reading. `load` is the station's host reading,
including CPU use and its sample span, available and total memory, disk space and `checkedAt`, as in `station_list`.
If that read fails or takes over a second, `load.unavailable` says so; no numbers are invented. A batch of queued
tasks shares one host reading. Stopped while waiting, a task never runs. A station that restarts
takes up what still waits, as it never ran (unlike a lost running task, which is failed rather than run again). The
queue looks at the machine every 5 s while a task waits, and when a task of its own ends.

## The screen (jobs/admit.ts `served`, in jobs/jobs.ts)

Windows, a simulator, screenshots of what is on the screen: one task's at a time, for as long as it uses it. A task
has the screen while a command of its runs as `stillfail-job screen <command>…` (any job of the station, the queue's
or an agent's own), or, prepared with `screen: true`, for as long as it runs. A task that takes pictures between
builds and tests has it only for the pictures; the rest runs beside the others'. (With the whole task having it, one
that had drawn its pictures in 40 s held the screen minutes more for its tests while the others with pictures to take
waited 20 minutes and more in line, the CPUs a third busy, 2026-10-25.)

- `stillfail-job screen` asks the door (`POST /jobs/screen`, the job's token, `take <pid>`: its shell's process) and
  again each second while it waits; with the screen, it runs the command and says `give <pid>` when it ends.
- The screen goes to the first command that asked while no task has it, and at once to a command of a task that has
  it already (one inside another, or inside a `screen: true` task: it does not wait for itself).
- A claim whose process is gone (the command killed before it gave the screen back) or whose job is over is dropped
  whenever the queue looks. Those that hold the screen are written to `jobs/screen.json`, so a station that starts
  while their commands go on knows who has it.
- A job in a sandbox has no `STILLFAIL_JOB_SCREEN` (it has none of this machine's screen); nor has one a station from
  before it started. Without it, `stillfail-job screen` runs the command as it is. A station that has not answered
  for a minute is not waited for: the command runs, and the log says so.
- Scripts that open windows ask for it themselves: apps/mbui's (`on_screen`, scripts/env.sh), around each app they
  run in a window; what they draw offscreen (scripts/film.sh, corners.sh, squeeze.sh) and the Tester's tests do not.
- The screen is for a machine's work, done in minutes. A window put up for a person and left there (a virtual machine
  to try, a simulator or an app to look at) is no claim on it: `stillfail-job show <command>…` waits as `screen` does,
  so the window does not come up under another task's work, then gives the screen back at once and runs the command,
  holding nothing. (A Mac VM for trying a new user's way in ran as a `screen` claim and held Studio's screen 23 hours,
  every task with pictures to take in line behind it, 2026-10-27.)
- While a person uses the screen (macOS: the machine's input, `ioreg`'s HIDIdleTime, idle less than a minute; someone
  at it, or working it through still.fail's view of it), nothing more is given it: no window comes up under their
  hand. What holds it goes on, and a command of a task that has it still gets it. Elsewhere no person is seen.
- Waiting, a command and a task are told who has the screen: the task's name and id, its chat, for how long (the
  answer's `who`, which `stillfail-job` prints, and `station_task`'s `queue.holder`), or that a person uses it.
- A command that has held the screen 10 minutes while another waits has its agent told once (the screen is for work
  done in minutes; a window kept up is `show`'s). Nothing is taken from it: what it is for is its agent's to say.

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
