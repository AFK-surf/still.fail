# Working on the station (for agents)

## Its shape

- Processes: the launcher (`native/launcher`, Rust) keeps the pid, the data directory's lock and the ports, and on an
  update starts the next Node before letting the old one go; each agent process runs under a runner
  (`native/runner`), so a turn goes on while the station restarts or crashes and the next one takes it up
  (`src/agents/runner.ts`; `adopt` in `src/agents/process.ts`). iroh is a Node addon (`native/mesh`). The native
  parts are prebuilt by their sources (`scripts/native.ts`): even a comment changed in one makes every machine and
  CI build it again, so touch them only for what they do.
- What still.fail draws outside the app (the Helper's windows, `native/helper`) is in still.fail's design (the
  colours of `web/ui/src/palette.ts`, its corners, capsule buttons, the s. mark), never the system's default controls
  (the user, 2026-10-28).
- `src/main.ts` is the composition root: every part is a Layer made there and given what it needs
  (`src/services.ts`); nothing registers itself, there is no global state. Async work is Effect 4: fibers in their
  part's scope, `Schedule` for backoff, streams for what is pushed. Pure computation stays plain functions.
- The main thread waits on nothing: every device's request and every agent's tool call waits behind it, and a call of
  microseconds took seconds on a station short of memory. No new synchronous call of node:fs, child_process or zlib
  there (fs/promises, execFile): `scripts/check.sh` refuses one a change adds unless its line says why with `sync:`
  (read before the station serves; one step that must not be split), outside a worker's file, the readers' (`src/read/`
  but for what the main thread runs of it) and `src/cli.ts`. Those from before this rule stand until they are moved; the
  line that says the main thread was held (`src/main.ts`) names, by caller, those that still take time.
  `test/main-thread-waits.test.ts` counts what a day's scenarios make it wait on; a change may lower the counts, never
  raise them.
- Time is the Clock's (a `TestClock` in tests): `Date.now`, `new Date()`, `setTimeout`, `setInterval` only in
  `src/ops/fibers.ts` (`wall`, for what is shared with other programs: mtimes, expiries, deadlines to processes).
  `scripts/check.sh` refuses them elsewhere.

## Its data

- Everything lasting is one SQLite file, `stillfail.db` (`src/store/store.ts`, schema in `src/store/schema.ts`): one
  write connection on the main thread; reads in reader threads (`src/read/pool.ts`: what is told as it changes and
  what devices ask each on a line of its own) or the MoonBit program (`mb/`) for the reads moved to it, the worker
  kept for a checkout without it. A move to the program is compared with the worker on the same data.
- A read answers by an index and a limit, never by going through all a station has (a station keeps months of chats):
  the `*-bounded.test.ts` tests count the rows a read fetches; a new read gets one. Old data a new index needs is
  built in the background (`src/read/*-builder.ts`), its batches taking one shared permit and yielding to writes
  (`src/store/backfill.ts`); until it is built, the read is bounded some other way, never a scan.
- A thread is a log: entries are appended, an edit is an entry of its own, nothing is deleted (a Slack delete is
  ignored); readers merge. The schema migrates forward only.
- What changes is told: the store's change, then `GET /events` (`src/api/events.ts`) to devices. A device never polls.
- Nothing in a workspace is hidden from its members: there is no permission system (the user, 2026-10-25). Every
  chat, a private one too, is open to every member and every agent of the workspace. The station is its server and
  the agents run as one system user, reading its database and every session's directory, so what is hidden from one
  person or one chat would not stay hidden without encryption. Do not propose or build visibility by person or by
  chat; a report of seeing another's private chat is answered that it is meant, and changing it is the owner's to
  decide. Only workspaces are kept apart from each other.

## Agents

- One actor per session (`src/sessions/actor.ts`): every change to its state, runtime events, deliveries and what its
  tools say, goes through its serial queue. Input is a prompt when idle, a steer during a turn, else queued.
- Runtimes are drivers behind one seam (`src/agents/runtime.ts`): Claude Code a `claude -p` process per session;
  Codex one app-server per account, a thread per session, whose per-session settings go in `thread/start`'s config,
  never the process's environment; the others in `src/agents/`. A driver owns its child's stdin.
- Their tools are the station's MCP endpoint (`src/tools/`, HTTP on 127.0.0.1, a bearer token per session). What they
  read of how to work is `src/agents/instructions.ts` and the skills in `src/skills/`. A change to the instructions, a
  tool's parameters or its rules adds a note at the end of `src/agents/migrations.ts` (the next number, a sentence),
  told once to sessions that began before it.
- An agent's own answer is never forwarded: it posts with `chat_post` and ends each turn with a state (`all_done`,
  `need_human`, `waiting`); a turn ended without one is asked again.

## A station's mode: whole, or only tasks (a rig)

- A station is whole, or it only runs tasks (只执行任务; `rig` in the code: `src/rig/`; the user, 2026-11-04 and
  2026-11-10): no agents, no chats kept in sight, no device served, only what the workspace's stations send it. One
  release and one list: it is added as either (`enroll --rig <the hash of its person's own lock>`) and changed in the
  app, never reinstalled. The app is not linked to one that only runs tasks: the stations say how it is (`src/rigs/`).
- A station is its owner's, the member who added it, whatever its mode, and only they change its mode, either way
  (the user, 2026-11-10): being a workspace's owner or admin is neither needed nor enough. Whole again only where
  they manage the workspace, as a member adds no whole station. One whose adder is no member (they left, or the
  operator enrolled it) the workspace's owner may make one that only runs tasks, and it is theirs then. The control
  plane holds this (`cloud/src/directory.ts` `setStationMode`): the machine does not know who added it.
- One that only runs tasks is its person's (its owner). A chat uses it only by a statement that person's own lock
  signed (`client/core-ts/src/rig-form.ts`: a grant with its timeout, idle or fixed, as a vault's secret; a grant
  taken back; 免批准, which opens it to every chat of the workspace), and the machine checks the signature itself against
  the lock it pinned: the cloud or a station that says otherwise lets no chat in. In security mode a station takes it
  only once that person signed for it (`src/rigs/adds.ts`), or the lock already lists it as a station.
- What a machine is changes only when two agree, neither alone: what was asked of the machine over a way the control
  plane has no part in (whole to tasks: a member's device that reached it, `POST /mode`, with their lock to pin, kept
  as theirs; tasks to whole: its person's signature, `rig.full`), kept there for an hour, and the control plane
  listing it so, as that same person's (`src/cloud/presence.ts`). A whole station ends its agents, connects and jobs
  before it is one that only runs tasks (`src/sessions/agents.ts`); its chats stay in its database, out of sight until
  it is whole again. Whole again is its person's to say where they manage the workspace: an admin cannot open
  someone's machine to every chat.
- It asks nothing of a station: it only tells (`RIG_TELLS` and `task.changed`, `src/mesh/peer.ts`). What it serves is
  behind a grant unless `UNGATED` (`src/rig/module.ts`) lists it, which is for reading back and stopping what a chat
  already ran there; a new method is not added to it to make something work.

## Tests

- `pnpm exec tsgo --noEmit` types; one test file is `node ../scripts/native.ts run mesh runner archive-rs reader --
  node --import ./test/setup-env.mjs --test test/<file>.test.ts` (`pnpm test` is every file). Agents in tests are
  fakes on the test's clock; real processes, signals and sockets are the side run's (`side/`).
- CI runs `test/` on Linux, in slices (`scripts/check.sh`, station-tests): a test passes there as on a Mac, or
  skips itself saying what it lacks. A test with the vault on a database in a file gives it through
  `test/vault-no-reader.ts`, unless the use index's reader is what it tests: the reader is a process of its own, and
  writes when it will.
