---
name: stillfail-jobs
description: Run background jobs, long-running watches, web previews or tasks on another still.fail station, or reach a service on another station (its HTTP API by URL, or any port forwarded here). Use for work that outlives a turn, a browser service people need to use, or a service (an LLM server, an API, a dev server, a database) another station runs.
---

# Jobs and services

Jobs run in separate process groups with persistent logs. They survive turns and station restarts; interrupted jobs
restart. Completion and `stillfail-job notify` messages wake you. A job with a port is a service, kept running and
available to workspace members through its returned link.

## Background work

- Use `job_start` without a port for long builds, tests, data work or loops. Run quick commands directly; if a result
  is needed before answering, wait for it in the turn.
- Supply `command` (run by `sh -c`), a short `name`, and optionally `cwd` (defaults to the session workspace).
  Keep clones and outputs in that workspace.
- Tell people what is running, carry on with whatever does not depend on it, and end `waiting` only when nothing
  else is left; use `need_human` instead if you also need their input.
- To wait on CI or another remote run, start a job (or background command) that polls it and exits on the first
  failure: its completion wakes you. Do not end `waiting` on a guessed duration with nothing watching.
- Inside long jobs, `stillfail-job notify "<words>"` reports meaningful milestones or trouble, not every line.
  Notices arrive via="station"; relay only what matters and act on failures.
- Completion includes the exit code and log tail. `job_log` reads more (up to 1000 lines); `job_list` shows your
  jobs; `job_stop` stops one. A completed step needs no separate user post unless it is useful news.

## Watches

For an explicitly requested ongoing watch (CI, deployment, metrics, review queue) that outlives your own work, set `watch: true` and loop,
notifying on changes. The chat appears under 监控中, does not auto-archive, and asks before manual archiving.
End `waiting` with `watch: true` when the watch is all you wait on: people see the chat as watching, and its timeout will not
wake you; a notice, completion or user message will. Waiting on anything else meanwhile (a build, a CI loop), leave
`watch` out: people see what you wait for, and the timeout asks you again as usual.
Give the next post a title naming the watch (e.g. 监控 · PR #482 的 CI); watch chats can be renamed immediately.
Stop the job when no longer needed; the chat then becomes ordinary again.

Watch with a loop that checks and notifies on changes. A check that fails (a command erroring or timing out, an empty
answer) is news too: count the failures and notify while they go on, never hide them (`2>/dev/null`, `|| true`) in a
loop that then waits forever. Leave its output in the job's log, not redirected to a file of its own, so people can
see each check.

## Web services

Use a port for something people should try in a browser: a UI, prototype, dashboard or tool. A one-off answer,
static image or internal-only background task does not need a service.

1. Start with `command`, `name`, and `port` (1024–65535). Listen on `$PORT`; 127.0.0.1 is enough, e.g.
   `python3 -m http.server $PORT`. One service per port.
2. Verify it answers with `curl -sf http://127.0.0.1:<port>/`; retry briefly or inspect `job_log` on failure.
3. Post the returned `link` where requested (Slack: `<link|label>`), naming the service and what to try, not its
   port. It is private to workspace members, not a public URL.
4. Stop unused services with `job_stop`. To restart, stop then start (or let a dev server reload itself).
   Repeated crashes cause restarts with increasing delays and notices: inspect logs and fix the cause.

Services open in a frame on their own origin. Use root paths (`/`). Responses are relayed whole: WebSockets,
SSE and long-poll streams do not pass through. Disable browser hot reload; live data only appears when read.
Keep the shown version running during review; compare another version via a separate checkout/service.
The preview supports phone/tablet/desktop sizes, rotation, zoom and screenshot annotations; tell reviewers they
can mark places and comment. Use stillfail-show for evidence to accompany the link.

## Another station

Use `station_list` to see the workspace's stations and how busy each is right now (cores, arch/OS, GPU, CPU busy over
the last minute, load average, free memory and disk where tasks run, what it is running); `station_list {station}`
gives one in detail with its task capabilities and file limits. All are asked at once: one not answering within 2 s
is listed offline. Any station of the workspace accepts tasks from here; one not updated yet may still refuse them,
and an older one's load shows as unknown. A station safe mode does not protect is listed last with `unprotected`: why
it cannot be called from here, and how an owner or admin protects it. That is not a bug: tell the person.

Choosing where to run: the right OS and architecture first; then enough free memory and disk for the job (a large
build needs several GiB of each); then the least busy (low CPU busy and load per core, few running tasks). Heavy
builds and test suites go to a big machine, not a small VM. Offline stations are skipped. There are no locks: do
not wait for, ask for or announce a "lock" on a machine, and do not queue behind other agents' claims. Look at the
load, and if a machine is busy pick another or start anyway when nothing better is free: the station queues it when
it must.

A station whose `mode` in `station_list` is `tasks` only runs tasks: it runs no agents and holds no chats, and it is
its owner's. It says whose it is, whether this chat may use it (`thisChat`) and who has access. Unless it is open to
every chat, ask with `station_use {station, reason}` (and `timeout` when an hour idle is not what the work needs); a
card in your chat goes to its owner, who may not be the person you work for, and you are told when it is decided.
Once this chat may use it, it is named as `station` as any other is, in `station_task`, `station_file`,
`peer_forward` and `secret_use`. When the grant ends (its time up, idle, taken back, the chat archived) what this
chat runs there is stopped, and you are told; a task's log and files are still read afterwards. A task of yours still
running there counts as use, so an idle grant does not end under it. `station_use {station, done: true}` hands it
back. One whose owner turned 免批准 on takes every chat with no grant: do not ask for it.

A station runs other stations' tasks through its own queue. Busy CPUs never hold a task back; when one must wait,
`start` and `get` answer with `queue` (its place and why it waits: memory under pressure, the screen another task's or
a person's, the small-task slot taken) and the machine's measured load (CPU, memory, disk, `checkedAt`), or why it
could not be measured, and the task starts by itself when that passes. A task is not told how many CPUs
to take either (no `STILLFAIL_CPUS`, `MAKEFLAGS` or `CARGO_BUILD_JOBS` from the station; only a small task is told
one): the system shares the cores. You end `waiting` as for any task; its end is told as usual.

For a brief offscreen task such as a single picture made with a prebuilt renderer, `station_task` prepare takes
`small: true`: one such task may run beside the rest even while the memory is under pressure (not when it is about
to run out). It is told to use one CPU, and waits if another small task is running. Do not use it for builds,
test suites, video, or work needing the screen. An older target that cannot do this says so at prepare.

The screen (windows, GUI tests, simulators, emulators, screenshots of what is on it) is one task's at a time. Run just
the command that uses it as `stillfail-job screen <command>…`: it waits while another task has the screen, has it while
that command runs, and gives it back when it ends, so the builds and tests around it run beside the other tasks. A
script that knows it opens windows may do this itself (mbui's do). `screen: true` at prepare has the screen for the
whole task instead: only for a task that uses it from start to end. What draws offscreen needs neither. The screen is
for work done in minutes: a window you put up for a person and leave there (a virtual machine to try, a simulator,
an app to look at) is `stillfail-job show <command>…`, which waits for the screen to be free, puts the window up and
holds nothing however long it stays. While a person uses the machine (its input not idle), no task is given the
screen; waiting, you are told who has it (`queue.holder`, and the line `stillfail-job screen` prints). A command that
holds the screen long while others wait has its agent told.

Memory: nothing is stopped for using much. When something you run (a task, a job, a command in your own shell) uses
more than an eighth of the machine's memory, or the memory comes under pressure, you are told; stop or shrink it if
you can. Only when the machine is about to run out of memory does the station stop the largest of what the agents run
there, and tells its agent why.

Prepare `station_task` with a stable `key`, upload inputs with `station_file`, then start the same key. Commands
run as the target OS user, not a sandbox. A sandbox of this station's (`station_list`: kind `sandbox`, by its name;
config.json's `sandboxes`) takes `station_task` the same way: a Linux sandbox of this chat's, made for its first task
and deleted once idle, with nothing installed there; give `dir` to sync what it builds and `back` for what comes back.
It has no screen. All tasks of this session share one directory on the target (the working
directory of each task), so a later task can build in what an earlier one cloned. Keep checkouts, worktrees and build
output inside it rather than elsewhere on that machine (or over ssh): it is removed with anything still running when
this chat is archived or deleted, or after 14 days unused, which is what keeps the target's disk free. Pin inputs and
versions: clone or fetch the intended revision there, or upload a bundle.

If prepare fails or is interrupted, start refuses that key until a prepare succeeds. Retry the intended prepare; use a
new key for different work. A failed re-prepare never makes the previous command the intended one.

A station is often someone's own computer, in use. A command that needs an administrator's password or a permission
the system asks for (`sudo`, `sfltool dumpbtm`, a first `osascript` controlling another app, a protected folder) puts
the system's dialog on that machine's screen, naming only the command, so nobody there can tell who asks; the task
waits until someone answers it. Prefer a way that asks nothing (login items through System Events, launchd jobs from
their plists); when none will do, say in the chat first what will appear on which machine and why, and end
`need_human`.

To build or test a local working directory there (a checkout with uncommitted changes), prepare with `dir` (its
absolute path here) instead of uploading: each start syncs it into a mirror on the target (named in prepare's answer,
inside the session directory) and runs the command there. Only files Git tracks or would add (all but the usual build
and dependency directories outside Git) go, and only what changed; the target's build output and dependencies stay
warm, and unchanged files keep their mtime. A sync that takes longer than about 40 s answers `syncing: true` and goes
on: call start again with the same key, which waits on that sync instead of beginning another. `back: [paths]`
downloads outputs into `station-back/<key>/` here when the task ends; it is removed once nothing in
it changed for 6 hours, so move what you keep into your workspace. Synced files the command
changed come back as `station-back/<key>/changes.patch`: review it and `git apply` it in the directory if wanted. One task
at a time per mirror.

`station_task` lists, inspects, tails or stops your remote tasks. Completion and notices survive reconnects and
station restarts; no local polling job is needed. End `waiting`, naming the task. Download artifacts with
`station_file` and post them to the requesting chat. Downloads create new files, never overwrite; inputs may be
uploaded again before start.

When a task changes files in a mirror, the next sync preserves those changes if the source is unchanged, and refuses
conflicting changes on both sides. Its result must finish coming back before another task uses the mirror. If a notice
says some results could not be saved, preserve those with `station_file` first, then use `station_task` action `release`
with that task's key; this permits later tasks to change the remote files. A target without this protection must be
updated before a task can sync a directory there.

`station_task` action `mirrors` lists this chat's synced directories on that station, with whether each is in use.
Action `clean` with `mirror` set to one listed name asks the station to remove it; a running or syncing mirror cannot
be removed. It deletes everything in that mirror, task outputs and changed files not brought back included: save what
is needed and choose only an unused, rebuildable mirror. If clean answers pending, repeat it with the same station and
mirror until it answers; the removal goes on meanwhile. A later task syncs it again.

After a timeout, inspect or retry the same key: work may already have run. Lost remote processes are not restarted
automatically; `failed` without an exit code means the outcome may be uncertain. Inspect before using a new key.

## Another station's services

Services listening on another station's localhost are reachable from here with no port opened anywhere, two ways.
`<station>` is its name from `station_list` (any case) or, when a name is not unique, its id.

- **A program calling an HTTP API with a base URL** (an LLM server, a REST API, a script): use the path form,
  `$STILLFAIL_PEER_HTTP/<station>/<port>/<path>` = `http://localhost:<port>/<path>` there (streams, large bodies and
  WebSockets pass as they come), e.g. `OLLAMA_HOST=$STILLFAIL_PEER_HTTP/willow/11434`. Without the variable, it is
  your stillfail MCP URL with `/mcp` replaced by `/peer`. Programs only (Host 127.0.0.1, no browser `Origin`). 502
  "needs an update": that station is from before this; 504: it is offline.
- **Anything else: a browser, web pages, dev servers (HMR), databases, any TCP protocol**: forward the port with
  `peer_forward {station, port}`, like `ssh -L`. It listens on 127.0.0.1 here, at the same port when free (the answer
  gives the address and URL; there it tries 127.0.0.1 and [::1], as a local client would), and passes bytes as they
  are, so absolute paths, client routing, redirects, cookies and
  WebSockets work as on that machine, and `psql -h 127.0.0.1 -p <port>`, `redis-cli` and the like too. It closes
  when this chat is archived, when the `job` you tie it to ends, after 30 minutes with no connection, or when this
  station restarts (then open it again). `peer_forward {}` lists yours and whether each station is online;
  `peer_forward {close: <local port>}` closes one. A path prefix breaks web pages, so do not use the path form for them.
  A station from before forwarding is reported as needing an update.
- To drive another station's Chrome over CDP, its DevTools WebSocket works through either: forward its debugging
  port and use `ws://127.0.0.1:<port>/devtools/...` as `/json/version` gives it, or take that URL's path under
  `$STILLFAIL_PEER_HTTP/<station>/<port>` (with `ws://`).
- For people's browsers (a link to post), start a job with a port instead: forwards are this machine's only.

## Devices

What runs no station but is attached to one (a phone, a board, a camera, a router, a serial port) or lent by a
person's still.fail app (their Android phone) is in `device_list`, and asked for with `device_use {device, reason}`.
One attached to a whole station is every chat's and is put on a port of 127.0.0.1 here at once; one on a station that
only runs tasks, and a person's phone, go to their owner on a card, as a tasks-only station does: it does not wait,
you are told when it is decided (meanwhile go on with what does not need it; with nothing else left, end need_human
about the card), and only a grant counts. Once granted, call `device_use` again for where it is:

- adb: `adb -P <port> -s <serial> …` (the port is the adb server of the machine it is on; `-P` on every command);
- tcp: connect to 127.0.0.1:<port> as you would to its address (http, `ssh -p`, mqtt, rtsp…);
- serial: the port's bytes both ways over 127.0.0.1:<port> (it is set raw at its baud there).

With no device named it is the phone of the person you work for, as `phone_use {reason}` asks for it: they approve it
for this chat for an hour, until it has gone unused for an hour, for eight hours, or until the chat is archived.
Called again once granted, `phone_use` says how the phone is reached now (its adb server and serial, which other
chats cannot reach). A grant ends when its time is up, when this chat has used the device for nothing for the idle
time, when its owner takes it back, or when this chat is archived; you are told. Done with a device (what it was asked
for is finished), hand it back with `done: true`: its port here closes and, for a phone, it is no longer lent for this
chat and you are no longer told how it comes and goes.
