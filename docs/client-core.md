# still.fail client core

The logic of a still.fail client — accounts, still.fail cloud, the mesh links to
stations, requests and live streams, everything read kept on the device — lives
in one TypeScript core, `client/core-ts` (on Effect; docs/core-ts.md for how it
came to replace the Rust core and the rules it is built to), shared by every
client. Only iroh and, on Android, the IO are native:

| Client | Where the core runs | Host (network, storage, time) | iroh |
| --- | --- | --- | --- |
| Web (app.still.fail) | one tab's dedicated Worker (the one holding the Web Lock `stillfail-core`; the other tabs' workers relay to it) | `src/hosts/web.ts`: fetch, WebSocket, IndexedDB (small values), SQLite's WASM build on OPFS | `client/iroh-wasm` (wasm-bindgen, relay only), loaded on the first link |
| Desktop (Electron) | a `utilityProcess` (Node) | `src/hosts/node.ts`: fetch, ws, `node:sqlite`, files | the station's napi addon (`station/native/mesh`, `mesh.node`) |
| Android (iOS later) | Hermes on a thread of its own (`apps/android/core/src/main/cpp/engine.cpp`), the core as Hermes bytecode | `src/hosts/bridge.ts` over the Rust shell `client/shell` (HTTP, the cloud's WebSocket, files, SQLite, TCP) | in `client/shell` |

The UI never talks to still.fail cloud or a station itself. It sends **calls** and
holds **subscriptions** to the core over one message channel, and renders the
snapshots the core pushes. Several UIs (tabs, windows) share one core: one
device key, one link per station, one token refresh, one cache.

## Execution model

The core is single-threaded: every piece of work is an Effect fiber in a scope
(`src/runtime.ts`, `Runner`); a call that can be cancelled is a fiber that is
interrupted, a subscription's work ends with its scope. Every timer is on
Effect's Clock (a TestClock in the tests): nothing in the core calls
`setTimeout`. Network waits yield to other work.

It is cache-first: everything still.fail cloud and the stations say is kept in
the signed-in account's SQLite database (`src/data.ts`, `src/db/`,
docs/core-db.md), and a topic is read from it only, by query — subscribing never
asks the network. One sync scheduler
(`src/sync/scheduler.ts`; `src/sync/cloud.ts`, `src/station/sync.ts`) owns all
traffic to still.fail cloud and the stations, keeps everything current by itself
whatever the UI shows, and takes the UI's attention (`client.focus`, a topic
shown) only as priority. A station's requests run two at a time, and two more
of what a UI has open or a person waits on (`URGENT_ROOM`): on a slow link a
read can take a minute, and the chat opened does not wait behind it. Stations
and still.fail cloud push what changes (events, sockets); nothing is read again
on a timer. Every request to a station but a preview's asks its answer
compressed (`accept-encoding: zstd`; an event stream flushed event by event and
compressed against its last megabyte, station/src/mesh/compress.ts), and it is
decompressed as it comes (fzstd, the same on every host: the browser and
Hermes have no zstd of their own); a station from before sends it as it is.
The one exception to
keeping everything current: what a station's agents spent (`stationUsage`) is
read only while a page shows it.

Topics are keyed collections (`src/collections.ts`): a change to a record
recomputes only the items that read it, and a subscription that says `keyed`
gets per-key insert/update/remove/move ops (docs/core-ts.md, 按 key 的增量).

## Host

What differs per platform comes in through one interface, `Host`
(`client/core-ts/src/host.ts`), every operation an Effect:

- `fetch` — one HTTP request to still.fail cloud, whole body; `fetchStream` — a
  streamed response in a scope (tests' stations, the side-by-side run);
  `websocket` — a receive-only WebSocket (still.fail cloud's `/v1/events`) with the
  subprotocols given, open once it resolves, closed with its scope.
- `storageGet` / `storageSet` / `storageDelete` — small persistent values by
  key (accounts and tokens, the device key, UI preferences). Web: IndexedDB
  (`stillfail-core` `values`, as the Rust core kept it); desktop and Android:
  a file per key in the app's data directory, as the Rust core kept them, so an
  update keeps the sign-in.
- `openDb` / `deleteDb` / `memoryDb` — an account's SQLite database (`Sql`:
  `exec`, `run`, `all`, synchronous): desktop node:sqlite, Android the shell's
  (`sql.*`), web SQLite's WASM build on OPFS; `legacyRead` — the former records
  store, read once (docs/core-db.md).
- `nowMs`, `monotonicMs`, `utcOffsetMin` (the viewer's time zone), `randomBytes`,
  `resetConnections`, `tcp` (adbd, native hosts).
- `emit` — delivers a message to one connected UI (by its client id).

iroh comes from the host too (`src/iroh.ts`): the browser's is relay-only (no
UDP), the native ones are the full endpoint. The credential, renewal, request
lines and the choice of relay are the core's (`src/mesh.ts`).

## Protocol (UI ↔ core)

Messages are JSON-shaped data (structured clone on the web, JSON strings
natively). Binary values (file bytes) are base64 strings everywhere, so the
protocol is the same on every host.

UI → core:

```jsonc
{ "id": 7, "call": "job.stop", "params": { … } }          // one answer
{ "id": 8, "subscribe": { "topic": "station.session", "station": "ws1/st1", "key": "…" } }
{ "id": 8, "unsubscribe": true }
{ "id": 7, "cancel": true }                                 // stops a streamed preview or a preview socket: it answers { code: "cancelled" }
```

A call may tell its UI how far it has got before it answers: values under its
id (`{ "id": 7, "value": … }`), then its answer. A UI that goes away cancels its
streamed previews and preview sockets; any other call runs to its end.

core → UI:

```jsonc
{ "id": 7, "ok": { … } }            // or { "id": 7, "error": { "code": "…", "message": "…", "status": 403 } }
{ "id": 8, "value": { … } }         // a subscription's whole current value: its first message, and the first after an error
{ "id": 8, "delta": [ … ] }         // what changed since the previous value
{ "id": 8, "error": { … } }         // the topic could not be read (the subscription stays; a later value clears it)
```

A subscription gets its topic's whole value first, then only what changed:

```jsonc
{ "path": ["detail", "transcript", "timeline"], "append": [ … ] }  // items added at the end of an array
{ "path": ["items", 3, "title"], "set": "…" }                       // a value replaced (path [] = the whole value)
{ "path": ["link", "message"], "remove": true }                     // a key gone from an object
```

Path segments are object keys (strings) and array indexes (numbers). The core
diffs the value it last sent against the current one: objects key by key, an
array that only grew as one `append`, an array of the same length item by
item, anything else as `set`. An equal value sends nothing; ops that would be
larger than the value send the whole `value` instead. `web/src/core/client.ts`
applies the ops, copying only along their paths, and hands the page whole
values. The core sends at most one message per topic per animation frame's
worth of changes (coalesced, ~50 ms); the window is one for all topics, so
what one event changes (a live step ending as the timeline grows) goes out
together, in the order it changed. Live steps are the exception that needs
speed, and they are small.

### Stations and accounts

A station is addressed as `"<workspace>/<station>"`: every station is in a
workspace and reached over a mesh link. `"local"` (a station's own page, gone)
is refused with the error `gone`. The core knows which signed-in account reaches
which workspace (from each account's `/v1/me`) and uses that account's token
for its member credential (30 days, kept on the device: docs/cloud.md).

Workspaces are kept apart (`workspace.ts`): each holds the account that
reaches it, its stations' state, what is waited on for them, the notices of its
chats, what is kept in sync of it and what its new chats were last started on
(`choice` records `ws:<workspace>:station:<id>`, `ws:<workspace>:last`; the
keys from before are read where there is none yet). Nothing of one is read or
dropped through another. What is the device's stays shared (the mesh endpoint,
relays, what is kept on the device, notification settings), and what is an
account's is kept by account. A UI says which workspace it is in (`client.focus {workspace}`);
notices are only of the workspace the viewer is in (attend.ts).

### Topics

| Topic | Params | Value |
| --- | --- | --- |
| `accounts` | — | signed-in accounts (no tokens) |
| `workspaces` | — | every workspace of every account, with its account and pending invitations |
| `workspace` | `workspace` | the workspace view (members, stations) |
| `link` | `station` | the device's own link to the station: `connecting` (with `last`, how it was last time) / `online` / `reconnecting` / `offline` (not reached: retried with backoff, 2 s doubling to 60 s) / `error` + message |
| `overview` | `station` | the admin API's `/overview` |
| `sessions` | `station` | `/sessions` (the shown sessions' `SessionSummary`s) |
| `archivedRows` | `station` | `/chats?archived=1`: the station's archived chats (read again after `chat.archive`, `session.delete`) |
| `threads` | `station` | `/threads`: every thread (`ThreadView`: its sessions, people, first person message, `last` entry, `lastMessage`, the viewer's `read` and `unread`), latest message first |
| `chatRows` | `station` | `/chats`: the viewer's sidebar rows as the station puts them together (`ChatRow`; docs/station-storage.md, The sidebar) |
| `session` | `station`, `key` | `/sessions/:key`: `{ session, threads, turns, jobs }` (no messages, no transcript) |
| `jobs` | `station` | `/jobs`: its background jobs still up (running, or a service being started again), newest first, each with the `chat` it is in as the viewer's sidebar has it |
| `stationUsage` | `station` | `/usage?from=&tz=`: what its agents spent from this device's midnight 29 days ago, days as its clock has them (`rows` added up by day, thread, person, profile and model, each with `cost` at the model's API prices; the `threads`, `people` and `profiles` they name; `since`, the earliest call recorded; `reading` while the transcripts are read for the first time). Read only while a page shows it (some 200 KB, changing with every model call): on its `usage` event (it recorded more, about every 15 s while agents work) while shown, else marked to be read as it is next shown; a station from before it answers 404 |
| `job` | `station`, `id` | `/jobs/:id` as it is now, with what the clients show of it (jobs.ts): kept current by its events, read again each half minute (every 4 s from a station too old to say whose it is) |
| `jobLog` | `station`, `job` (id), `lines` | `{ text, outputAt, last, said }`: the job's last `lines` lines of output and when it last grew (below); `last` its last line, `said` (最后输出 · 3 分钟前) goes out fresh as it changes (jobs.ts) |
| `thread` | `station`, `thread` (id) | `{ first, last, caught, end, entries, thread }`: a window of the thread's entries `first ..= last` (`EntryView`s, never changed once read), at most 150 (`WINDOW`). It opens where the chat is to be read — the page before the first entry not read and the page from it while something is unread, else where it was left (`chat.place`), else the latest page — and its first value is whole: from what is kept when all of it is and it is current (the station's `threads` say how far each goes), else read first. `chat.older` / `chat.newer` bring in the page before / after (a page is kept ahead either way), as many going at the other end; `end`: it reaches the thread's latest entry, so what is said joins it; short of it, what is said waits on the device. `caught`: its last entry read rather than told as it was said. `thread` is its summary |
| `live` | `station`, `key` | the session as it runs (below) |
| `host` | `station` | host samples (`HostInfo`) |
| `status` | `workspace?` | what the core is waiting on, when it is worth saying (`StatusView`, status.ts): of a workspace its stations' waits (the relay and links opened for them too), its account's still.fail cloud socket down and the relay opened for no station; with none, all of it |
| `connection` | `station` | what a chat on the station says of its connection (`ConnectionView`, pill.ts): its link down or coming back, else its workspace's `status`; trouble at once, coming back only after 1.5 s, `back` (已连上) 1.5 s only after one was shown. No page shows it any more (the phones dropped the pill over a chat); kept for apps from before |
| `notices` | `workspace?` | what a person hears about while the client runs: chats of theirs that want them (docs/notifications.md); a workspace's, or every one's |
| `notify` | `workspace?` | notifications on this device: on or off, asked, whether to hold pushes, the notices to show now (docs/notifications.md), only the workspace's for a page in one |
| `adbShare` | — | this phone's adb as lent to a station's agents (`AdbShareView`, adb.ts; docs/adb-share.md): whether it is and to which, how the offer goes (`phase`), how the station's adb holds the phone (`adb`, `serial`, `message`), until when, the tunnels open now. Kept in memory only |

```jsonc
// live
{
  "loaded": true,             // the stream has sent the transcript it had; until then `timeline` may be partial
  "first": 800,               // where `timeline` starts in the transcript: its latest page first, `history.older` loads those before
  "timeline": [ … ],          // TimelineEntry: the transcript from entry `first`, appended as it grows
  "usage": { "modelCalls": 3, "inputTokens": 1200, "cachedTokens": 900, "outputTokens": 80, "model": "claude-…", "contextTokens": 420, "contextWindow": null, "cost": 0.0123, "unpricedCalls": 0 } | null,
  "steps": [ … ],             // steps in flight (LiveStep; an ended one keeps "ended": true until the entry that records it arrives)
  "phase": { "phase": "requesting", "since": 1790000000000 } | null
}
```

Nothing is read on a timer. Each topic is read once when it starts; after
that only notifications change it:

- `accounts`, `workspaces` and `workspace`: while `workspaces` or any
  `workspace` is live (a view resting on one counts), each signed-in account
  holds still.fail cloud's `/v1/events` socket (subprotocols `ember-events` and
  `ember-token.<access token>`, a token good now asked of the accounts module
  at every (re)connect; auth, events and shapes in `docs/station-storage.md`).
  `{"type":"workspaces"}` reads that account's `/v1/me` again (the
  `workspaces` value), `{"type":"workspace","id"}` that workspace, and
  `{"type":"station","workspace","id","online"}` sets the station's `online`
  (and `last_seen` to now) in the `workspace` value without a request. Every
  time a socket opens, the live account topics are read once (nothing is
  replayed); a socket that cannot open on its first try reads them anyway.
  Sockets reopen with backoff (1 s doubling to a minute, back to 1 s after one
  held a minute) and close when no account topic is live. A change of the
  accounts (sign-in, sign-out) reads the topics again; a token refresh alone
  does not.
- Station topics: while any topic of a station is live, the station's
  `/events` stream is held open, with `?host=1` while a `host` topic is live
  (the stream is opened anew when that changes, and when the sessions it
  follows do; the old one closes once the new one is open). Every stream
  after the first asks `since=<the last event id heard>` (an id is the
  station's run and the event's number in it, `<run>.<n>`): one taking over
  from a stream still open, and one coming back after its link went (on a
  weak link that is every minute or so: the link moves to a better way, or
  loses its way). The station keeps what it told for ten minutes (while
  nobody follows too, for one coming back) and tells what came after first,
  with the same ids, then the viewer's sidebar rows and overview as they
  changed meanwhile, and answers `stillfail-resumed: 1`: nothing is read
  again. When it cannot (more than that ago, or another run's), it says
  `missed` and the station is read again, once; a station from before
  resuming does not answer so, and a stream coming back reads it again as
  before (one taking over only on `missed`). Events go into the topics
  as they come: `session` replaces the summary in `sessions` (an archived one
  leaves the list) and in its `session` topic (whose `turns` are read again
  only when the summary's `turns` or `lastTurn` differ from them);
  `session-removed` takes it out of `sessions`, out of the threads' sessions
  (a thread left with none goes), and makes its `session` topic a 404 error;
  `thread` appends the new entries to that `thread` topic (those it has are
  skipped; entries past a gap wait while the gap is read, once, with
  `?from=&to=`) and, since it does not carry unread counts, reads
  `/threads/:id` for the `threads` and `session` topics that list it (bursts
  coalesced over 400 ms; a 404 removes it); `thread-removed` takes the thread
  out of them, makes its `thread` topic a 404 error and forgets what is kept of
  it; `read` sets the thread's `read` there, and `unread` to 0 when it covers
  the last entry (else the thread is read again), and turns off `unread` of
  that thread's `chatRows` row when it covers the row's last message; `chat`
  puts a row into `chatRows` (replacing the one with its `id`), `chat-removed`
  takes one out; `job` (a job as `GET /jobs/:id` answers it, whenever it
  starts, starts again, ends or says something) replaces it in its session's
  `jobs` (or goes in front), and in `jobs` while it is up (one not listed there
  yet reads `jobs` again, for its chat; one no longer up leaves); `overview`
  and `host` are the whole values. After the stream
  was down and could not be resumed, every live topic of the station is read
  once when it reopens (`thread` topics only what came after them:
  `?after=<last>`); `link` says how the stream is.
- `thread` shows what is kept on the device of the thread (its latest page)
  at once, then reads `?after=<last>`; with nothing kept it reads the latest
  page. What it reads is kept (docs/station-storage.md, In the client core),
  with the thread's summary and its sidebar title as `threads` and `chatRows`
  have them.
- `live` starts from the latest page (200 entries) of the transcript kept on
  the device and follows it on `/events?live=<key>&from=<entries it has>&last=200`,
  keeping what comes: the station sends no more than the last 200 entries, so
  a timeline message past what it has (or before it: the transcript written
  anew) starts the timeline there. `history.older` brings the pages before, from
  what is kept, else `GET /sessions/:key/timeline?before=&limit=`. Both ask
  `brief=1`: what is pushed and paged is what a history shows before a step is
  opened (docs/station-storage.md, Reading); a step or thought in brief says
  so (`brief`, with its `entries`), and `history.detail` reads those entries
  whole as it is opened (`?from=&to=`), never pushed, behind what is shown
  (`Priority.detail`, above `background`, below `shown`). A station from
  before it passes over `brief=1` and sends everything whole.
- `jobLog` reads `GET /jobs/:id/log?lines=<n>` once and follows it on
  `/events?job=<id>&lines=<n>`: the station sends `job-log` (`id`, `lines`,
  `text`, `outputAt`) at once and whenever the log's size or time changes
  (looked at each second while the stream is open). A station that does so
  says `follows: true` in the log it answers; one that does not (older) passes
  over `job=`, and the log is read again instead: after 2 s, doubling while it
  stays the same up to a minute, back to 2 s when it changed.

A topic nobody subscribes to is dropped after a minute.

### Views

The UI does no joining, filtering or grouping of data: every screen subscribes
to one **view** topic that the core has already put together from the
topics above (and keeps current as they change). A view keeps the topics it is
built from subscribed inside the core (`Store::watch`: it counts as a
subscriber and hears each change); a change only marks the view stale, and it
is computed once, when its coalesced emission goes out, however many of them
changed. A workspace view watches the `chatRows` / `link` (for `stations`:
`link` / `overview` / `host`; for `connects`: `overview`) of the stations that
are online — connected to still.fail cloud right now, as the `workspace` topic says —
and follows the workspace's station list as it changes. It has no value until
the `workspace` topic has one; a failed `workspace` is the view's error, while
a failing station only shows in that station's state. `chat` watches the
station's `threads` and `sessions`, its thread's `thread` (entries),
`overview` and `link` — all asked for at once when it starts, so a chat opens
in one round of requests — and, once `threads` (or the thread as kept) names
them, the `session` of each of its agents. It has a value as soon as its
latest entries are there and its thread is in `threads` — or, before
`threads` is read, as soon as its entries are there from what is kept, with
the thread as kept beside them; its agents fill in after (an agent whose
`session` is not read yet is its summary from `sessions`, without turns or
threads; one that fails is left out). A failed `threads` or `thread` is its
error, and so is its thread missing from `threads` once read (404). Its
`messages` are its entries merged (entries.ts): each message with its latest
edit's text, attachments and quotes (`editedAt`). With `session` instead of
`thread`, `chat` watches that `session`, `sessions`, `chatRows`, `overview`
and `link`.

While a `chats` view is live, a clock waits for the viewer's next local
midnight and recomputes it then (`daysAgo` changes); that is the only timer of
the views.

`scope` is a workspace id.

| View | Params | Value |
| --- | --- | --- |
| `chats` | `scope`, `mine` | the sidebar: `{ me, stations, loading, days }`; every station's rows side by side |
| `stations` | `scope` | every station of the scope, each with its link, overview, host and usable models |
| `connects` | `scope`, `mine` | every connect of every online station: `{ me, items: [{ station, stationName, connect }], loading }`; with `mine`, those whose `createdBy.id` is me |
| `chat` | `station`, and `thread` (id) or `session` (key) | an item's page: `{ me, thread, title, people, agents, messages, more, outbox, link }` |
| `archive` | `scope` | the archive: `{ days, errors, loading, note }`, every online station's archived chats newest first by the day they were archived |
| `chatJobs` | as `chat` | the chat's services and jobs as its pages show them (`ChatJobsView`, jobs.ts): every one, what matters first, each with its dot (`tone`), word, line (`meta`) and times in words (computed again when they next change, to the second); the button's `alarm`, the groups' notes, how many are current and ended, whose ended ones clearing takes |
| `usage` | `scope`, `days?` (7, the default, or 30) | what the agents of the scope's online stations spent (`UsageView`, views/usage.ts): `tiles` (cost, calls, input and output tokens), `daily` (each day's cost split by `series`, the four people who spent most and 其他), `lists` (按人 / 按对话 / 按账号 / 按模型, the most spent first, each with its share; a person merged across Slack and the page by email), `notes` (stations offline or too old, the first read under way, models without a price, since when anything is recorded) |
| `decisions` | `workspace` | the 奏 page: the cards waiting for the viewer in the workspace's chats (`DecisionsView`, decisions.ts; the name is from when the only cards were decisions), whatever their agents' states: `{ items, count, loading }`, each item `{ station, stationName, session, thread, title, seq, message, before, card, options, deferred?, text }` (the post with the card and the one or two messages before it as `chat` shows messages; `card` is `{type: "options", options}` or `{type: "text", placeholder?}`; `options` an options card's, the recommended one last, empty for a text card); pending and not dismissed by the viewer, oldest asked first, those set aside on this device (`decision.defer`) last; `count` for 奏 N |
| `longJobs` | `scope` | the services and jobs up longer than an hour on the scope's stations that are up (their `jobs`), oldest first, in groups: `{ groups: [{ key, head, jobs }] }`, each job with `whereText` and `age` |

`live` (above) stays its own topic: its steps change many times a second,
while `chat` changes with messages.

```jsonc
// chats
{
  "me": { "id": "a@b.c", "email": "a@b.c" },
  "stations": [{ "station": "ws/st", "id": "st", "name": "studio", "state": "online", "message": null }],
  //   state: "online" | "connecting" | "offline" (not connected to still.fail cloud) | "error" (message says why)
  //   error: its rows could not be read, or its link failed; connecting: rows not read yet, or the link
  //   is reconnecting (rows already read stay listed).
  "loading": false,                                // an online station has not answered its rows yet
  "days": [{ "daysAgo": 0, "at": 1790000000000, "items": [{
    "station": "ws/st", "stationName": "studio",   // added here; the rest is the station's row as it is
    "id": "7", "session": "ds:C1:1790000000.000100", "thread": 7, "title": "部署挂了", "agents": [ … ], "last": { … } | null,
    "unread": true, "mine": true, "lastActiveAt": 1790000000000, "connect": "ds" | null, "origin": { … } | null
  }] }]
  // days: most recent first, grouped by the viewer's local calendar day; items by lastActiveAt, newest first.
  // with mine = true only the rows whose `mine` is true.
}
```

The rows are the station's (`GET /chats`, kept current by its `chat` and
`chat-removed` events): which chats and agents are listed, what they are
called, whether they are unread, where their agents came from, and whether the
viewer takes part all come from the station, which knows who is asking. The
core joins nothing here: it puts every station's rows side by side, adds their
station, applies `mine`, and groups them by day.

The `chat` view's `title` is the thread's title; else the first line of the
first thing a person said in it (`firstText`, Slack mentions left out, spaces
collapsed); else its Slack channel (`#name`), `私信` for a direct message, or
`（还没有消息）`.

```jsonc
// stations
[{
  "station": "ws/st", "id": "st", "name": "studio",
  "online": true, "lastSeen": 1790000000, "version": "0.4.0",   // from the workspace
  "link": { "state": "online", "message": null },
  "overview": { … } | null,                                      // null while offline or not yet read
  "host": { … } | null,
  "runtimes": [{ "runtime": "claude", "models": ["…"] }]         // claude, codex if a profile has models enabled; those models, distinct and sorted
}]

// chat
{
  "me": { … },                   // as in chats
  "thread": { … } | null,        // the ThreadView (with the viewer's `read` position and `unread`, `people`, `last`, `lastMessage`); null before the agent has a chat
  "title": "…",                  // see below (as kept with the entries until `chatRows` is read)
  "people": [ … ],               // the thread's people
  "agents": [{                   // its sessions, in the order they joined
    "session": { … },            // SessionSummary
    "connect": { … } | null,     // the connect that started the session, from the overview
    "profile": { … } | null,     // the profile it runs on, from the overview
    "turns": [ … ],              // TurnRecord, oldest first ([] until its session is read)
    "threads": [ … ]             // ThreadView: every thread it takes part in ([] until read), to name the places in its history
  }],
  "messages": [ … ],             // the thread's messages merged from the entries loaded so far, by seq (a message's entry n)
  "more": true,                  // older entries exist: `chat.older` loads the page before them
  "newer": false,                // newer entries exist (the window is short of the end): `chat.newer` loads the page after, `chat.latest` goes to the end
  "outbox": [{ "id": "out-1", "text": "…", "attachments": [], "quotes": [], "createdAt": 1790000000000, "state": "sending", "error": null, "seq": 42 }],
  //   messages sent from this device that `messages` does not show yet; `seq` (its entry n) once the station has it. An
  //   entry leaves in the same emission that brings the entry with that n (or a later one) into the chat.
  "link": { "state": "online", "message": null }
}
```

Every item of the sidebar opens the same page, the `chat` view: with
`thread`, an internal chat (`surface: "ember"`); with `session`, an agent that
has no chat yet — `thread` null, no people or messages, the agent alone (as
in a chat), titled as the station's item is (the view waits for the station's
`chatRows`); a session that cannot be read is its error. Its chat is made
(`POST /threads {session}`) when the first message is sent, and the page
moves to it. Where the viewer had read up to when a chat opened is
`thread.read` at that moment (from the thread as kept, when the chat opens
from what the device kept); a client keeps it for the visit while reading
moves the position on. The web draws its "以下是新消息" line over the first
message after it that is not the viewer's own and was said before the chat
opened, whether it came from what was kept or from the station after opening.

Grouping by day needs the viewer's time zone: `Host::utc_offset_min(at_ms)`
gives it (web: `-new Date(at).getTimezoneOffset()`).

### Calls

| Call | Params | Result |
| --- | --- | --- |
| `auth.begin` | `redirect_uri`, `return_to`, `device_name` | `{ url }` to open (web: navigate; native: system browser) |
| `auth.password` | `email`, `password`, `device_name` | `{ account }`: signed in with an account still.fail cloud set up for a password (REVIEW_ACCOUNTS: App Store review's); a wrong one fails `login_wrong_password` |
| `auth.complete` | `query` (the callback's query string) | `{ account, return_to }` |
| `auth.signOut` | `account` | — |
| `slack.tokens.edit` | `station`, `form` (the generated `SlackTokenForm`), `input` (changed `appToken`, `botToken`, `connect`, `install`; `clear` invalidates verification) | the transient draft; also published as `{ topic: "slackTokens", station, form }` (`SlackTokensView`) |
| `slack.tokens.verify` | `station`, `form` | `true` only for the current verified draft; errors and identity in the topic. Late results for edited or closed forms cannot advance it |
| `slack.tokens.drop` | `station`, `form` | clears the in-memory draft; disconnecting its owning UI also clears it. Nothing is saved to device storage |
| *an operation* | `station` or `account`, and its own | what the station or still.fail cloud answers; see below |
| `chat.send` | `station`, `thread`, `text`, `attachments?`, `quotes?`, `client?` (the app it is sent from, for the chat's agent) | `{ seq }`, once the station has it and the chat's `thread` topic (when read) holds it. Only chats on still.fail's page take messages (the station refuses the rest). Meanwhile the message is in the view's `outbox` as `sending` (a failure leaves it there as `failed`, with `error`) |
| `chat.retry` / `chat.discard` | `station`, `thread`, `id` | sends a failed outbox message again / drops it |
| `decision.answer` | `station`, `thread`, `seq`, `option` (an option's `label`) | as `chat.send`: the viewer's message in the chat, the option's label quoting the post that asked (decisions.ts); refused once the chat's row no longer has that card pending, or for a card that is not an options card |
| `decision.reply` | `station`, `thread`, `seq`, `text` | as `chat.send`: what the viewer wrote in a text card's field, quoting the post that asked (decisions.ts); refused once the chat's row no longer has that card pending, or for a card that is not a text card |
| `decision.defer` | `station`, `thread`, `seq` | — ; 待定: set aside on this device (the prefs' `decisionsDeferred`), last on the `decisions` page, still pending. Nothing is sent |
| `decision.dismiss` | `station`, `thread`, `seq` | `PUT /threads/:thread/dismissed {n}`: the viewer will not take it up; off their rows' line, marks and `decisions`, on every device of theirs (the station keeps it); still pending for everyone else |
| `chat.older` | `station`, `thread` | `{ more }`: loads the page (50 entries) before the chat's oldest loaded entry into its `thread` topic — from what is kept, else from the station — so `messages` grows in front |
| `chat.newer` | `station`, `thread` | `{ more }`: loads the page after the chat's newest loaded entry (it is short of the end), from the device when it is there (kept ahead), as many going at the start; read, not said: nothing comes in with a motion |
| `chat.latest` | `station`, `thread` | — ; the chat's latest page in place of its window (the reader goes to its end); sending from a window short of its end does it too |
| `chat.place` | `station`, `thread`, `seq?` | — ; where the reader leaves the chat: the entry at the top of what shows, short of its end, or none at its end. It opens there next while nothing is unread (held while the core runs) |
| `history.older` | `station`, `key` | `{ more }`: loads the page (200 entries) of the session's transcript before its `live` topic's `first` into it — from what is kept, else from the station — so the `history` view's `items` grow in front (`more` in the view: there are older ones) |
| `history.detail` | `station`, `key`, `from`, `to` | — ; reads the session's transcript entries `from` to `to` whole in place of what is kept of them in brief, as a history's step or thought in brief (`brief`, its `entries`) is opened: the `history` view shows it whole once they are in. Behind what is shown (`Priority.detail`); tried while the station seems away too, failing as the request does |
| `chat.read` | `station`, `thread`, `seq` | — ; records that the viewer has read the chat up to entry `seq` (`PUT /threads/:id/read {n}`); nothing is sent when it is read that far already. `unread` in `chats` follows. The clients no longer call it: the core reads a chat up to its newest message while a UI shows its end on a page in view (`client.focus`, attend.ts) |
| `client.focus` | `visible?`, `focused?`, `chat?`, `left?`, `workspace?` | — ; where this UI's attention is (docs/notifications.md): what is read, a chat's `unreadLine` (held for the visit, older pages loaded first while `unreadAbove`) and which notices show follow from it; `workspace`, the one it is in (else its chat's) |
| `station.upload` | `station`, `key`, `name`, `bytes` | the attachment (into that session's workspace; a message may carry uploads of any session in its chat) |
| `station.upload.part` | `station`, `id` (the UI's, one per file), `name`, `size`, `offset`, `bytes` (at most 16 MB) | `{ have, file? }`: how much of the file the station has (the next part starts there) and, once whole, the attachment. Up to 1 GB a file; a station from before parts takes it whole once all parts are in, up to 50 MB |
| `station.file` | `station`, `key`, `name` | `{ type, bytes }` |
| `station.file.part` | `station`, `key`, `name`, `offset`, `length` (at most 8 MB) | `{ type, total, bytes }`: a part of the file and its whole size, for a big one fetched onto the disk a part at a time; `unsupported` from a station before parts |
| `station.poster` | `station`, `key`, `name` | `{ type, bytes }`, a video's first frame as a small JPEG the station makes; null when it has none |
| `cache.usage` | — | `{ chats: [{ station, thread, title, sessions, bytes }] }`: what this device keeps of each chat (its messages, its sessions' transcripts), for a page of what it keeps |
| `cache.clear` | `station`, `thread` | — ; forgets what is kept of the chat (its messages and transcripts, read again from the station when it is opened); its outbox, draft and row stay |
| `station.preview` | `station`, `port`, `method`, `path`, `headers?`, `body?`, `stream?` | a request to a web service on the station's machine (`/preview/<port>`): `{ status, headers, body }`; with `stream`, values `{ head: { status, headers } }` then `{ chunk }` for each piece of the body as it comes, and the answer (null) at its end. Only waited on (`status`) until its head; cancelled, the station stops asking the service |
| `preview.socket` | `station`, `port`, `path`, `headers?`, `socket` (a name the UI gives it) | a WebSocket of that service, over the mesh only: values `{ open: { protocol } }`, then `{ text }` or `{ binary }` for each message; the answer is its close, `{ code, reason }`. Cancelling the call drops it |
| `preview.socket.send` | `socket`, one of `text`, `binary`, `close: [code, reason]` | — ; what the page sends on the socket it named so |
| `migrate` | `accounts`, `device` | — (web only: what localStorage held before the core existed) |
| `push.key` / `push.register` / `push.unregister` | see docs/notifications.md | this device's push registration, with every signed-in account |
| `newChat.pick` | `scope`, `station?` (its id), `model?`, `runtime?`, `effort?`, `profile?` (null: the default depth, the station's pick) | — ; what a new chat in the scope starts on, kept on the device (choose.rs): the `newChat` view follows. A model keeps its runtime where it runs there; a runtime changed takes its default depth |
| `newChat.create` | `station` | `{ key, runtime, model, effort? }`: `chat.create` with what is picked on that station; the scope's next new chat starts there |
| `newChat.migrate` | `choices` (by station id), `last?`, `lastIn?` | — ; what a client kept before the core did, taken where the core keeps nothing |
| `pick.set` / `pick.save` | `station`, `of` (`new`, `session:<key>`, `connect:<id>`, `connect-new`), and for `set` any of `model`, `runtime`, `effort`, `profile`, `open`, `clear` | a model control's picks until saved (the `pick` topic); `save` makes them what it runs on (`session.settings`, `connect.put`, the new chat's choice), `{ saved }` |
| `adb.share` | `station`, `connect?`, `pair?` (adbd's ports, as the app found them), `device`, `android`, `package`, `minutes?` (60) | — ; lends this phone's adb to the station's agents (native cores only), or the offer as it is now; another station's in place of one before (docs/adb-share.md) |
| `adb.stop` | — | — ; lent no longer |
| `adb.pair` | `code` | `{ message }`: the station's adb pairs with the phone through its pairing port |
| `adb.grant` | — | `{ message }`: the station's adb grants the app `WRITE_SECURE_SETTINGS`, to turn Wireless debugging on itself |

A UI never makes a request of a station or still.fail cloud itself (no method, no
path): it names what it wants done, and the core knows the request that does it
and what that changes (`ops.ts`; `scripts/check.sh` fails on a UI that asks
for a request). Station operations take `station`: `session.stop`,
`session.warm`, `session.evict`, `session.delete`, `session.settings`,
`session.new`, `chat.archive` (by its thread, else its session; a station from
before archiving threads archives the session; one going in is left out of
`chats` until the station answers, back if it refused), `chat.rename` (by its
thread, else its session), `chats.archived`,
`chat.forSession`, `widget.state`, `widget.setState`, `machineSessions.list`,
`machineSessions.read`, `machineSessions.continue`, `connect.create`,
`connect.put`, `connect.delete`, `connect.reconnect`, `connect.bindSession`,
`connect.putSlackApp`, `slack.verify`, `slack.makeApp`, `slack.dropApp`,
`slack.installed`, `slack.addConfigToken`, `slack.removeConfigToken`,
`slack.people`, `slack.createAppUrl`, `slack.identity`, `profile.add`,
`profile.useMachineLogin`, `profile.put`, `profile.delete`, `profile.quota`,
`profile.check`, `profile.login`, `profile.cancelLogin`, `profile.loginCode`,
`login.new`, `login.code`, `login.drop`, `job.get`, `job.log`, `job.stop`,
`memory.get`, `software.update`, `software.check`, `software.channel`. still.fail cloud's take
`account`: `workspace.create`, `workspace.rename`, `workspace.setRelays`, `workspace.delete`,
`workspace.invite`, `workspace.addMembers`, `workspace.removeAdded`,
`workspace.revokeInvitation`, `workspace.setRole`, `workspace.removeMember`,
`workspace.enroll`, `workspace.renameStation`, `workspace.removeStation`,
`invitation.preview`, `invitation.accept`, `invitation.decline`,
`loginSession.revoke`, `admin.me`, `admin.createCode`, `admin.revokeCode`,
`admin.feedbackStatus`.

An operation answers only after the live topics it touches are current, so
the UI never invalidates caches itself and a page that navigates right after a
write finds what it wrote: an answer that is an overview (profile and connect
edits) becomes the `overview`; a thread (`chat.forSession`, a new chat) goes
into `threads` and the `session` topics; a read position into the threads; a
job stopped into its session's `jobs` and into `jobs` (as its `job` event
would); otherwise the touched topics are read again (sessions → `session`,
`sessions` and `chatRows`; a thread answered → `chatRows` as well; connects →
`overview` and `sessions`; profiles, Slack → `overview`; `slack.identity` →
`overview` (its answer) and `chatRows`). A write to still.fail cloud reads the
account topics again. The station's events bring the same a moment later.

## Layout

```
client/
  core-ts/    the core (TypeScript, Effect): protocol, store, data, sync, accounts, cloud, mesh, station, views
    src/hosts/  web.ts (the worker), node.ts (the desktop's utilityProcess), bridge.ts + hermes.ts (Android's shell)
    src/shapes/ schema.ts: what the core gives its clients, declared once (the clients' types are made from it)
    scripts/    shapes.ts, operations.ts (the clients' types and operation bindings), hermes-bundle.ts
    test/       the core's tests (the Rust core's, ported, and the TS core's own); harness/ the side-by-side run
  iroh-wasm/  iroh alone for the browser (wasm-bindgen), which hosts/web.ts binds
  shell/      Android's native shell (C ABI): HTTP, the cloud's WebSocket, files, SQLite, TCP, iroh
  i18n/       the words (catalog/<lang>/*.json), shared with the station, the web and Android
```

The core's modules (`client/core-ts/src`):

- `host.ts` — the `Host` interface; `runtime.ts` — `Runner`: scopes, fibers, the Clock.
- `protocol.ts` — the messages above.
- `core.ts` — `Core`: accepts client messages, routes calls, manages subscriptions. `core/calls.ts` parses the named calls and validates input; `core/execute.ts` runs them; `core/routing.ts` routes topics; `core/account_state.ts` reconciles accounts, workspaces and their sockets.
- `ops.ts` — station and cloud operations: their requests, their effects on the records, and their contracts (`PARAMS`).
- `store.ts` — topics: values, subscribers, coalesced emission as deltas (`delta.ts`; keyed by `collections.ts`, shaped by `output.ts` and `conform.ts`), eviction.
- `data.ts`, `db/` — the data (docs/core-db.md): a SQLite database per signed-in account (`db/schema.ts` its tables and migrations, `db/account.ts` its writer and reads), the device's own values, what came before imported once (`db/import.ts`).
- `sync/scheduler.ts`, `sync/cloud.ts`, `station/sync.ts` — everything kept current, by itself; `station/topics.ts` — the station topics, read from the records; `station/requests.ts`, `station/wire.ts` — requests over a link.
- `accounts.ts` — sign-in (PKCE), token refresh (one at a time per account), persistence. `cloud.ts` — still.fail cloud's API.
- `mesh.ts` — the device endpoint and station links: the credential and its renewal, reopening, hedging on a wake, relay measurement and moving.
- `entries.ts` — a thread's entries merged into messages (edits applied): the one place that does it.
- `workspace.ts` — the workspaces, each with what is its own. `notices.ts`, `attend.ts` (`client.focus`, `notify`), `status.ts`, `pill.ts`, `doing.ts`, `adb.ts`.
- `activity.ts`, `history.ts`, `present.ts`, `format.ts`, `decisions.ts`, `jobs.ts`, `looks.ts`, `changelog.ts` — what the clients show, decided once for every client.
- `views/` — the view topics (chats, chat, stations, decisions, usage, admin…), and `views/local.ts`, the local overlays (outbox, pending chats, renames and pins under way).
- `choose.ts`, `forms.ts` — the new-chat and model pickers, the forms (automatic decisions, Slack tokens, the connect wizard, adding a profile).
- `trace.ts` — traces of user actions (docs/telemetry.md). `testing.ts` — a host for tests.

## Native (Android)

`apps/android/core` runs the core in Hermes (React Native's prebuilt
`hermes-android`, without React Native): `engine.cpp` gives each core a thread
with a task queue, timers on CLOCK_BOOTTIME and the microtasks drained after
each task, and `__native` calls into the Rust shell (`client/shell`), which does
the IO the core asks of its host — HTTP (reqwest, rustls), the cloud's
WebSocket, files per storage key (the same directory and format as the Rust
core's), the accounts' SQLite databases (`databases/`, asked synchronously), TCP
to adbd, iroh — on threads of its own and answers through a C callback. The core is bundled for Hermes and compiled to its bytecode
(`client/core-ts/scripts/hermes-bundle.ts` → `core.hbc` in the app's assets).
A bug that ends a fiber ends the core: every client gets `{"fatal": "…"}` and the
app starts a new one.

`apps/android/build.py` builds the shell with the NDK and the core's bytecode,
checks the generated types (`Shapes.kt`, `Operations.kt`), then runs Gradle.
The `:core` module is `fail.still.core.StillFailCore` (behind its `Engine`
interface): `call(name, params)` and `topic(topic)` as a `Flow<TopicState>` —
shared by everyone who collects the same topic, deltas applied as on the web
(keyed ones too: `Delta.kt`), unsubscribed 2 s after the last collector leaves.

## Desktop

`apps/desktop` is the web app running natively: the window loads the cloud
build (`pnpm run build:cloud`'s `dist/cloud-web`, bundled into the app) from
`app://ember`, served as still.fail cloud serves it (a file, else `index.html`).
Nothing in the pages differs but the host underneath:

- The core runs in a `utilityProcess` (`src/core.ts`): the TypeScript core
  (`client/core-ts`, its Node host bundled as `core-ts.js`; docs/core-ts.md),
  with its data in the app's `userData/core` (the same files the Rust core
  kept, so an update keeps the sign-in; the accounts' databases in
  `databases/`, what `core.db` held imported once and left there). Its iroh endpoint is the full native one
  (the station's napi addon, `mesh.node`), so links go direct once the relay has
  introduced both sides.
- A page asks the main process for a channel (`emberDesktop.openCore`, from
  the preload): a `MessageChannelMain` whose one end goes to the core and the
  other to the page, as a window message (a port cannot cross the context
  bridge). `web/src/core/client.ts` uses that port instead of the
  worker (`desktopOpener`); the protocol is the same, posted as objects
  and answered as the core's JSON. A port that closes disconnects its client;
  a core process that exits is announced to every page, which opens a new
  channel (the main process starts a new core); a `{"fatal"}` (a fiber that
  failed with a bug) makes the core process start a new core for the channels that follow.
- Sign-in: `auth.begin` with `redirect_uri` `stillfail://auth/callback` (a scheme
  the app registers). Leaving `app://ember` opens the system browser instead
  (so does `window.open`); still.fail cloud sends the browser back to
  `stillfail://auth/callback?…`, which the OS hands to the app (`open-url` on
  macOS, `second-instance` elsewhere), and the app loads the page's own
  `/auth/callback` with that query, which calls `auth.complete` as on the web.

- The app carries a station release (scripts/station-bundle.sh: the station
  in TypeScript with its Node) and runs its launcher, `stillfail-station`,
  itself (`src/station.ts`), on
  `~/.stillfail` like an installed station; when one is running already
  (`stillfail-station` exits with HELD) it leaves it be.

still.fail cloud defaults to https://app.still.fail; `STILLFAIL_CLOUD_ORIGIN`
overrides it. `apps/desktop/build.sh` builds the core and the station for
macOS arm64 and packages an `.app` with electron-builder. Use `UNSIGNED=1`
for a local unsigned package; release builds use the maintainer signing identity.
The internal `app://ember` origin is retained so existing localStorage and
IndexedDB data remain accessible.

## Web

`web/src/core/` is the UI side: it starts the tab's worker, speaks the protocol
over its port, and gives React `useTopic(topic)` (built on
`useSyncExternalStore`) and `call(name, params)`. One tab's worker
(`web/src/core/worker.ts`, the one holding the Web Lock `stillfail-core`) runs
the TS core (`@stillfail/core-ts/web`, aliased to
`client/core-ts/src/hosts/web.ts`) on SQLite's WASM build (loaded by it alone),
and loads `client/iroh-wasm`'s module on its first link; the other tabs' workers
relay to it over a BroadcastChannel and take over when its tab goes (the page
subscribes again on `{rejoin: true}`). `web/src/core/delta.ts` applies deltas (keyed ones
too) for the pages and the desktop's main process alike.

## Operation contracts and module boundaries

The ordinary station and cloud HTTP operations declare what they take beside
their requests, in `ops.ts` (`PARAMS`); `client/core-ts/test/ops-contracts.test.ts`
checks that each reads exactly that. `node client/core-ts/scripts/operations.ts`
generates `web/src/core/operations.ts` and Android's `data/Operations.kt` from
them; `--check` (CI, `scripts/check.sh`, the Android build) rejects drift. These
bindings own named calls and parameter packing; the hand-written facades provide
convenient return types and adapters. Special core calls (chat streaming, picks,
local drafts) keep their own adapters. Optional fields distinguish absence (leave
unchanged) from explicit `null` (reset). Kotlin's optional-fields builder records
assignments, including null; it must not serialize every unassigned property.

The clients' types are made the same way, from `src/shapes/schema.ts` (the
shapes every topic's value passes through on its way out): `node
client/core-ts/scripts/shapes.ts` writes `web/src/core/shapes.ts` and Android's
`data/Shapes.kt`, and `--check` keeps them from drifting.

`connectFlow {station, form}` owns the complete Slack connection wizard: team,
configuration token, app settings, installation, token verification, model binding
and submission. Calls are `connect.flow.open/edit/go/config/make/verify/create/drop`.
The core chooses desktop inline versus mobile separate token steps. Each form has
its own `connect-new:<form>` pick and token state, belongs to its client, and is
removed on close/disconnect. Secrets are transient; no draft is written to Data.
Operation generations and token revisions prevent late replies from advancing a
closed or edited form; pending and completed forms cannot submit twice. Nested
pick quota labels use the normal presentation decorator. Web keeps a legacy
wizard only for a desktop host whose bundled core answers `unknown_call`.

Web `action.ts` replaces the station and cloud action implementations. It observes
named calls and shows their `doing` state; synchronous thin wrappers preserve this
metadata through `captureCall`. Android's `CallObserver` carries call metadata in
the coroutine context (isolated across concurrent actions), and `Action` observes
`doing`. Read-only exclusions are generated from `ops.ts` (`QUIET_WRITES` and the reads). Neither
adapter retains token/password/code parameters. A local entry lock prevents a
second click before the core's first update.

Business operations in account/workspace/profile/connection/archive/login and
confirmation controls use that shared state. Local pending flags remain for
browser/OS permissions, sign-in handoffs, image rendering/export, gesture
animations, old core compatibility and host callbacks with no single tracked
operation. Input echoes, optimistic setting queues and displayed errors remain
view concerns; they do not claim whether the station completed a write.
