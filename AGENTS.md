# Working on still.fail (for agents)

These apply to the whole repository; each part has its own AGENTS.md beside its code, told to you as your tools first
touch its directory (a station session's hook) and read by Claude Code as it opens a file there.

## The parts

still.fail is a coding-agent service in team chats: people talk to agents in Slack, Feishu, Comma or still.fail's own
chats, each conversation an agent session on a **station** (a machine of theirs), driven by Claude Code, Codex and others.

- `station/`: the station (TypeScript on its own Node, Effect), with prebuilt native parts (`station/native`) and a
  MoonBit reader (`station/mb`). Holds the chats, sessions, agents, jobs, accounts; serves devices over the mesh.
- `cloud/`: still.fail cloud on Cloudflare Workers: accounts, workspaces, members' credentials, the relays. Only people.
- `client/core-ts/`: the client core every app runs (TypeScript, Effect): accounts, links to stations, everything kept
  on the device, the views. The UIs only render it. `client/shell` (Rust) is its IO in the native apps,
  `client/iroh-wasm` iroh for the browser, `client/i18n/catalog` the words of every part (zh and en, the same keys).
- `apps/mbui/`: the app on every platform (Android, iOS, macOS, Windows, Linux, and the web), in MoonBit on mbui, the
  UI framework at `libs/mbui`. `libs/comma-ui`: Comma's design system as a component library on mbui, of its own.
- `web/`: the web's host of that app, a few pages of its own (Preact) and the design system `web/ui`.
- `website/`: the official site. `rules/`: rules shared by the station, cloud and core, in MoonBit, built to JS.
- `scripts/`: checks, releases, the CI plan. `vendor/`: patched upstream code (its README says each patch).
- `docs/`: only how to build, run and operate (development.md, operations.md, two notes on a station's setup) and
  the release notes. Design is in the code's comments and in these files; nothing else explains it. A comment naming
  another `docs/` file means a design document deleted in #4614 (`git show ec9da461f6^:docs/<name>.md`): where the
  comment leaves a format or a protocol to it, that is its spec.

## These files are kept true

- When a change makes what an AGENTS.md says untrue (a path, a command, a rule, how a part works), the same change
  corrects it. `scripts/check.sh` refuses a path written in one that is not there.
- A rule the owner gives that is not checked, and anything an agent would get wrong from the code alone, goes in the
  AGENTS.md of the narrowest directory it is about, said once, in a few lines. What the code or its comments already
  say is not written again; a decision says why and, where it was the owner's, when (`the user, 2026-11-09`).
- A new directory with rules of its own gets an AGENTS.md and a CLAUDE.md of one line, `@AGENTS.md`.

## Changes, checks and CI

- One pull request per piece of work, from `origin/main`. Merging to main deploys the beta (`.github/workflows/pipeline.yml`,
  `scripts/plan.sh`: what each path deploys), so main is always releasable.
- A bug's fix merges once its newest commit's checks passed; a change to the product or to what people see, when
  the owner has said so (the user, 2026-10-31).
- What people will notice of a change is said in its commit message's trailers: `Changelog:` a line for them, in
  Chinese (`修复：…`, `新增：…`, `改进：…`); `Changelog-parts:` where they see it (`station`, `web`, `android`,
  `desktop`, `cloud`); `Fixes: FB-<n>` a bug report it fixes. The apps' changelog and each stable release's notes
  are written from these alone (`scripts/changelog.ts`); a change with nothing for people writes none.
- `sh scripts/check.sh full origin/main..HEAD` checks what the range changed (the git hooks run its quick part);
  `STILLFAIL_CHECK_PART` narrows it. Run the part you changed before a PR; the whole of it is CI's.
- A fix that cannot wait a day for the next stable release (a crash, data lost, people locked out, a release that does
  not update) says `Stable: yes` in its commit message: the stable release is the day before's main, and only such
  fixes are cherry-picked onto it (`.github/stable-plan.py`; the user, 2026-11-09).
- Older stations and newer cores coexist: what is kept for older versions goes 7 days after its replacement ships, and
  that change raises the floor (`OLDEST_CORE` in `station/src/api/oldest.ts`, `OLDEST_STATION` in
  `client/core-ts/src/station/oldest.ts`). Databases migrate forward only. Existing commands and shared links keep
  working.
- New data, a new third party or a changed retention period: both privacy policies (`web/public/privacy.html`,
  `web/public/en/privacy.html`) change in the same pull request.
- Tests are deterministic: time is a test's clock, networks are simulated; never a sleep, a retry or a longer deadline
  to make one pass (`docs/development.md`, Tests). What cannot be made so is the side run's (`scripts/side.sh`). A
  check that fails and then passes on the same commit let something uncontrolled in: find it and take it out, never
  rerun it green or call it flaky.

## To people there is one safe mode

- A person's own lock (which devices are theirs) is the root of trust; a workspace's lock is going away as a thing
  of its own (the user, 2026-11-05): it keeps the roster (members, stations) and follows each person's own lock for
  their devices.
- People are never asked to tell the two apart (the user, 2026-11-10): 安全模式, 受信任设备 and 批准 look and work as
  they did before there was a lock of one's own. No page, prompt or refusal sends someone to 个人锁 to be let in to
  a workspace, or names it where the workspace's lock was named before.
- A person's devices are theirs alone to change: owners and admins take a member out, never one device of someone
  else's (the user, 2026-11-10).
- Everyone in safe mode comes to have a lock of their own with nobody asked (`client/core-ts/src/views/lock.ts`
  `ownLockFor`): their devices trusted in a workspace's lock are put on it by the one of them that approved them
  there, and take it from that one, a member's as an owner's, so that nobody approves a device again (the user,
  2026-11-10). What that costs, known and taken: until a member's devices have a lock pinned, an owner or admin of a
  workspace of theirs who rewrites its lock with a changed app can get a device of their own taken as that member's
  (`vouchersIn` says how); the entries that did it stay in the lock. Do not widen it (never by a device id, never the
  device that approved one already on the lock), and do not narrow it without the owner.
- Every error, refusal and wait tells the person what to do next to get done what they set out to do; none is a dead
  end (the user, 2026-11-12).

## No polling between still.fail's own parts

The client core (`client/core-ts`), the station (`station/`) and the cloud (`cloud/`) never read something of another
of them again on a timer to see whether it changed. The part that owns it tells the others when it changes: an event on
a socket it already keeps (the cloud's `/v1/events` and a station's presence socket, `cloud/src/types.ts`), or a stream
it serves (a station's event stream). A reader reads when it is told, when it is first shown, and when its connection
opens again; a long poll is no exception: serve a stream.

A timer is only for what tells nothing by itself:

- a heartbeat or a ping that keeps a connection, or measures it;
- a sample of this machine (CPU, memory, the network's counters);
- a retry after a failure, with a backoff, and a timeout or deadline;
- a debounce of a burst;
- an outside system that offers no push (a registry, a provider's quota, a third party's feed).

`scripts/check.sh` refuses a timer a change adds to those three parts unless its line says which of these it is with
`timer:`. Removing an old part's support (a station from before an event) is better than polling it.

## No way into a station from outside

still.fail has no public entrance. A station is reached only on the mesh (`station/src/mesh/`): the iroh endpoint,
which admits the other stations of its workspaces by their keys and members by the credentials still.fail cloud signs.
Everything else a station listens on is this machine's own (127.0.0.1, a Unix socket, a socket the launcher holds for
it), and nothing makes it otherwise: no setting of the address, no tunnel (Tailcat, ngrok, cloudflared, a Tailscale
funnel), no port forward, no webhook for a platform to call. A station connects out to what it works with (still.fail
cloud's presence socket and relays, Slack's Socket Mode, Feishu, Comma) and is told over those connections.

The cloud (`cloud/`) keeps accounts, workspaces, member credentials and the relays; it takes no request for a station to
pass on to it, and the conversations do not go through its database. What spans a workspace (what an outside program
reads of it or does in it, its chats and usage brought together, a task sent to one of its stations) is the stations'
own: a station serves it, reaching the others over the mesh.

`scripts/check.sh` refuses a socket a station listens on that does not say 127.0.0.1 (or the fd, the path) on its line,
and any tunnel's name in the station or the cloud.

## The cloud is the account system and nothing else

Only the account system depends on still.fail cloud (the user, 2026-11-09): accounts and sign-in, workspaces, their
members, roles and invitations, the list of a workspace's stations, and the member credentials it signs. Nothing else
does. What devices and stations keep, decide or tell each other goes between them over the mesh, and keeps working
with the cloud down, slow, rate-limited or holding something back. The relays are not the cloud (they only carry the
mesh's packets, end to end encrypted), and push notifications are the one exception (the user, 2026-11-09): a station
gives the cloud its notices to push through APNs, FCM and Web Push (`cloud/src/push.ts`).

Signatures the cloud cannot forge are not enough: what the cloud only carries, it can still hold back, delay or lose.
A new feature puts nothing else in the cloud. The locks are the stations' now: a device reads the workspace lock, its
person's own lock and the devices that came of the stations (`GET /lock`, `/lock/person`, `/lock/devices`; once a
workspace's chain moved to its people's logs, the logs its state is made of and its statements' bodies, `/lock/logs`,
`/lock/bodies`, which only its stations keep and give), is told
they changed on their event streams (`station/src/mesh/lock-events.ts`) and brings what it signs to them, which keep
each other level (`station/src/mesh/lock-sync.ts`, `station/src/mesh/person-sync.ts`). The cloud is asked only where
no station answers (one from before, all offline), and is sent what a station took for the stations and devices from
before, never waited on; that goes 7 days after these stations ship. Its taking an entry counts for nothing: what no
station took is pending on the device that signed it (`client/core-ts/src/lock-pending.ts`) until one does, or until
the lock names none (its last station taken out), which the cloud keeps as before there were stations.

That sync is being replaced (2026-11-12): stations that took different entries at one place never came back to one
chain (`station/test/lock-world-sim.ts` lists what that broke and what still does). What replaces it is modelled in
`station/test/lock-fork-choice-model.ts` (each log's fork choice) and `station/test/lock-roster-model.ts` (a workspace
said in its people's own logs). The stations go by the fork choice now (`station/src/cloud/log-keep.ts`), keeping a
branch only for what another keeper took: a station never makes a fork itself (what a device brings goes on from its
head, or is refused as before), so it never moves off an entry for one that came to it alone; stations of a lock still
give each other all they keep and come to one chain. The core keeps what the stations showed it and goes by the same
fork choice (`client/core-ts/src/lock-keep.ts`), so a device follows them off an entry that lost, and the device that
signed it signs it again after the head where that still says what was meant (`againOf`), carrying to each station
what it lacks of what the stations showed (`client/core-ts/src/views/lock.ts` `carry`). The cloud's copy, for the
stations and devices from before, is kept the same way: what a station gives it as another keeper's goes by the fork
choice (`cloud/src/lock.ts` `keepLockAt`), each station giving it its chain where the cloud's parts from it
(`station/src/cloud/presence.ts` `planeParted`), so it names the stations' head again. What it is built to (the user,
2026-11-12):

- The lock's adversary is the cloud and every station but the one asked (`rules/protocol/lock.spthy`): only signatures
  of devices on a lock decide. No cloud and no station orders entries, arbitrates between them, or is the one to follow.
- What can be settled by rule is: a fork by the fork choice, an entry that lost its place signed again by its device.
  What cannot (two devices removing each other, a device fully taken over, every signer lost) gets no more machinery:
  it is recognised and handed to the person with a way out.
