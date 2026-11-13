# Working on the station (for agents)

## Its shape

- Processes: the launcher (`native/launcher`, Rust) keeps the pid, the data directory's lock and the ports, and on an
  update starts the next Node before letting the old one go; each agent process runs under a runner
  (`native/runner`), so a turn goes on while the station restarts or crashes and the next one takes it up
  (`src/agents/runner.ts`; `adopt` in `src/agents/process.ts`). The station's iroh endpoint is kept by the MoonBit
  front (`mb/src/front/mesh.mbt`), which the launcher starts and keeps across Node's handovers
  (`native/launcher/src/front.rs`), for each Node in turn (`src/mesh/front.ts`, its streams carried by the shell and
  none of their bytes by the program); where none runs (Windows, a checkout without the program) Node binds it itself
  with its addon (`native/mesh`), which keeps the image codecs and the rest as before. The native
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
  but for what the main thread runs of it), `src/cli.ts`, and the update's own process (`src/updates/command.ts` and
  the delta applier it runs, `src/updates/delta.ts`). Those from before this rule stand until they are moved; the
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
- What must survive of the chats is copied off the machine by an export off the main thread, as opaque batches, to two
  other stations of the workspace; a new station takes a lost one's back before its store
  opens (`src/replica/`, its AGENTS.md). It adds nothing to the main thread's writes: no trigger, no statement.

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
- What the still.fail team replies on a bug report never reaches an agent by itself (the user, 2026-11-10: it would be
  outside words in someone's session): still.fail cloud gives the replies only to the chat's workspace's members' apps
  (`client/core-ts/src/feedback-replies.ts`), no station reads or holds them, and an agent sees one only as a person
  quotes it into what they send. An agent may answer with `feedback_reply` when the person asks it to.
- An agent's own answer is never forwarded: it posts with `chat_post` and ends each turn with a state (`all_done`,
  `need_human`, `waiting`); a turn ended without one is asked again.

## How a workspace's devices reach its stations (its ways)

- A workspace's own relays and the ways its devices do not take are its stations' (`src/mesh/ways.ts`; the root
  AGENTS.md, The cloud is the account system): one record a workspace, the newest kept, brought level between its
  stations, read by devices (`GET /ways`) and told changed (`ways`). An agent adds a relay with the `relays` tool and
  nobody approves it (the user, 2026-11-11: 「要手动加太不 ai native 了」): a relay carries only end-to-end encrypted
  packets and one that is slow is not taken, so an approval would guard nothing; the tool adds one only once this
  station reached it as a relay, and who added it is kept and shown.

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

## A lock kept here

- A lock this station pinned, its home's or a joined workspace's, is let go or replaced only by the lock's own entry
  (its owner's `disable`) or on this machine (`stillfail lock reset [--workspace ID]`, `enroll --join --lock` naming
  another): never by what the control plane says (a workspace left out of a frame and named again unlocked, or made
  the home one: `src/cloud/state.ts` `leftJoined`, `src/cloud/presence.ts` `took`), nor by an ask over the mesh, where
  who manages the station may be the plane's word (`src/cli.ts` `nameJoinedLock`). Each of these let a device the lock
  never named in until 2026-11-12.
- Of each lock (its home's, a joined workspace's, each person's own) it goes by the rules' active chain of what it keeps
  (`src/cloud/log-keep.ts`; 2026-11-12): everything that reads "the lock" reads that chain, the file's `entries` are it
  (what an older station reads), `aside` the rest, at most `ASIDE_MOST`. It changes branch only for entries another
  keeper took (another station of the lock; a device saying `keep`): what a device, a hello or the control plane
  brings itself is taken only where it goes on from the head, else answered as a fork was before and not kept, its
  signer at hand to sign it after the head. A device keeps what a station showed it and goes by the same fork choice
  (`client/core-ts/src/lock-keep.ts`), so it follows a station that changes branch; refusing a fresh entry decides
  nothing for any other keeper.
- Where a lock's active chain holds `moved {root}` (2026-11-13, nothing signs one yet), the state in force there is the
  rules' `state4` of the root's log, the person logs kept and the statements' bodies kept (`src/cloud/lock-bodies.ts`,
  `mesh/locks/<ws>.bodies.json`), by this station's clock: `Cloud.locked` gives it to every reader of "the lock"
  (admission, the vault, rigs, the roster); what reads the chain itself (its seq, head, genesis: `lock-sync.ts`, the
  cloud's copy in `presence.ts`, `lockHead`, pinning) reads `Cloud.chain`. Off is a state (`locked` null, nothing let
  go); without the root's log or its `open` (`waiting`) nobody is let in and the chain's stations are answered only the
  lock's own methods. A body is taken only against an entry kept that commits to it (`bodyRefusal`), and given only in
  its workspace: to a device let in there (`GET /lock/bodies`, with `lacking`), to a station its state names
  (`lock.bodies.*`, `person-sync.ts`), and to one a removal took out, that removal and its `prev` chain alone.

## Screens

- One person's view drives a screen at a time, any number look (pengxiao, 2026-11-12: 「控制独占，查看不限」):
  `src/screens/hub.ts` `drive` decides it as a view opens. Its person asking (控制, 接管: the view's `taken`) takes
  it, and every other person's view that drives it, their own on another device too, only looks from then on, told
  who took it; a view's own reopen (its link went, a resize) never takes it. An agent's view is not one of them: its
  input waits while a person drives (`src/tools/computer.ts`). Each side is told it in a notice (「独占这块应该需要有提示」).

## Devices (设备)

- A device is what agents use that runs no station (the user, 2026-11-10): attached to a station (on its USB, in its
  network, a serial port: `src/devices/`, `connect.ts` reaches it) or a member's phone lent by its app (`src/adb/`).
  One list (`device_list`), one way to ask (`device_use`), each its person's. A chat gets a port of 127.0.0.1 on its
  own station that only its processes connect to (`src/adb/door.ts`'s gate), carried over the mesh to the device's station
  (`src/mesh/peer-http.ts`, a tunnel's `device`).
- On a whole station a device is every chat's, with no grant: the station is every chat's, so none would guard it. One
  that needs its owner's approval is attached to a station that only runs tasks, by that station's owner, as they sign
  it (`client/core-ts/src/rig-form.ts` `DeviceBody`), kept and checked by the rig itself (`src/rig/grants.ts`), granted alone or with the
  rig, or 免批准 on it.

## Tests

- `pnpm exec tsgo --noEmit` types; one test file is `node ../scripts/native.ts run mesh runner archive-rs reader --
  node --import ./test/setup-env.mjs --test test/<file>.test.ts` (`pnpm test` is every file). Agents in tests are
  fakes on the test's clock; real processes, signals and sockets are the side run's (`side/`).
- CI runs `test/` on Linux, in slices (`scripts/check.sh`, station-tests): a test passes there as on a Mac, or
  skips itself saying what it lacks. A test with the vault on a database in a file gives it through
  `test/vault-no-reader.ts`, unless the use index's reader is what it tests: the reader is a process of its own, and
  writes when it will.
- A test waits for what the station set going with `settle()` (`test/hub-fakes.ts`): turns of the loop with no file
  request out, since the station reads off its main thread and how many turns the disk takes is the machine's. A count
  of turns of a test's own before it looks is that race again.
- The lock's world tests (`test/lock-world-sim.ts`, run by `test/lock-world-1.test.ts` to `-3`) pass when exactly what
  `KNOWN_SEEDS` and `KNOWN_TOLD` say fails on the product (2026-11-12): anything else failing fails them, and a known
  failure that holds now must be taken out of the table, which only shrinks. The fork-choice models' runners
  (`test/lock-fork-choice.test.ts`, `test/lock-roster.test.ts`, `test/lock-roster4.test.ts`) print what they measure
  and assert only the models' soundness; their envs (`LOCK_FORK_*`, `LOCK_ROSTER_*`, `LOCK_ROSTER4_*`) give the full
  counts.
