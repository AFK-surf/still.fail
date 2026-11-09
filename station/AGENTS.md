# Working on the station (for agents)

## Its shape

- Processes: the launcher (`native/launcher`, Rust) keeps the pid, the data directory's lock and the ports, and on an
  update starts the next Node before letting the old one go; each agent process runs under a runner
  (`native/runner`), so a turn goes on while the station restarts or crashes and the next one takes it up
  (`src/agents/runner.ts`, `adopt`). iroh is a Node addon (`native/mesh`). The native parts are prebuilt by their
  sources (`scripts/native.ts`): even a comment changed in one makes every machine and CI build it again, so touch
  them only for what they do.
- `src/main.ts` is the composition root: every part is a Layer made there and given what it needs
  (`src/services.ts`); nothing registers itself, there is no global state. Async work is Effect 4: fibers in their
  part's scope, `Schedule` for backoff, streams for what is pushed. Pure computation stays plain functions.
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

## Tests

- `pnpm exec tsgo --noEmit` types; one test file is `node ../scripts/native.ts run mesh runner archive-rs reader --
  node --import ./test/setup-env.mjs --test test/<file>.test.ts` (`pnpm test` is every file). Agents in tests are
  fakes on the test's clock; real processes, signals and sockets are the side run's (`side/`).
