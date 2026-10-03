# still.fail client core

The logic of a still.fail client — accounts, still.fail cloud, the mesh links to
stations, requests and live streams, the cache of what has been read — lives in
one Rust crate, `stillfail-core`, shared by every client:

| Client | Where the core runs | Binding |
| --- | --- | --- |
| Web (app.still.fail) | a SharedWorker (a dedicated Worker where SharedWorker is missing, e.g. Chrome on Android) | `client/wasm` (wasm-bindgen) |
| Desktop (Electron) | a `utilityProcess` | `client/node` (napi-rs) over `client/ffi` |
| Android (iOS later) | a core thread in the app | `client/ffi` (uniffi) |

The UI never talks to still.fail cloud or a station itself. It sends **calls** and
holds **subscriptions** to the core over one message channel, and renders the
snapshots the core pushes. Several UIs (tabs, windows) share one core: one
device key, one link per station, one token refresh, one cache.

## Execution model

The core is single-threaded and async. Its futures are `!Send`; shared state
is `Rc<RefCell<…>>`. On the web it runs on the worker's event loop
(`wasm-bindgen-futures`); natively on a dedicated thread running a tokio
current-thread runtime with a `LocalSet`. Network waits yield to other work.

Native input JSON and call parameters (including base64 uploads) are decoded on
an input thread with `Core::prepare`, then applied in order on the core thread.
Pure, payload-sized conversion uses `Host::background` (the native blocking pool).
Outgoing topic messages and API messages have separate FIFO worker queues for
JSON serialization and foreign callbacks. An API's progress and answer share
its queue, so the terminal answer cannot overtake its stream. Callbacks may run
concurrently across the two queues; consumers must hand them off safely.

Android likewise separates outgoing serialization, incoming topic parsing and
API parsing from the queue that owns client state. Topic deltas are applied in
order. Its chat decoder retains unchanged message objects by JSON identity,
bounded to the current message window. Markdown parsing and code highlighting
and shaping run off Main; the UI draws the prepared code layout. These boundaries
avoid blocking the UI on payload processing; they do not eliminate layout costs,
GC pauses, or contention for CPU and memory.

## Host

What differs per platform comes in through one trait, `Host`
(`client/core/src/host.rs`):

- `fetch` — one HTTP request to still.fail cloud, whole body; `fetch_stream` — a
  streamed response (only tests' stations use it: stations are reached over mesh links only);
  `websocket` — a receive-only WebSocket (still.fail cloud's `/v1/events`) with the
  subprotocols given, resolving once it is open; its text frames end when it
  closes, and dropping them closes it.
- `storage_get` / `storage_set` / `storage_delete` — small persistent values by
  key (accounts and tokens, the device key, UI preferences). Web: IndexedDB
  (a worker has no localStorage); native: a file in the app's data directory.
- `now_ms`, `monotonic_ms` (for timing spans: `performance.now()` on the web, a
  monotonic clock natively), `utc_offset_min` (the viewer's time zone), `sleep`, `spawn`, `random_bytes`.
  `sleep` serves reconnect backoff, coalescing windows, evictions and the
  midnight clock of `chats` — never polling: nothing is read again on a timer.
- `emit` — delivers a message to one connected UI (by its client id).

iroh is used directly by the core: the wasm build uses relay-only connections
(browsers have no UDP), native builds the full endpoint.

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

Workspaces are kept apart (`workspace.rs`): each holds the account that
reaches it, its stations' state, what is waited on for them, the notices of its
chats, what is kept in sync of it and what its new chats were last started on
(`choice` records `ws:<workspace>:station:<id>`, `ws:<workspace>:last`; the
keys from before are read where there is none yet). Nothing of one is read or
dropped through another. What is the device's stays shared (the mesh endpoint,
relays, what is kept on the device, notification settings), and what is an
account's is kept by account. A UI says which workspace it is in (`client.focus {workspace}`);
notices are only of the workspace the viewer is in (attend.rs).

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
| `stationUsage` | `station` | `/usage?from=&tz=`: what its agents spent from this device's midnight 29 days ago, days as its clock has them (`rows` added up by day, thread, person, profile and model, each with `cost` at the model's API prices; the `threads`, `people` and `profiles` they name; `since`, the earliest call recorded; `reading` while the transcripts are read for the first time). Read again on its `usage` event (it recorded more, about once a minute while agents work); a station from before it answers 404 |
| `job` | `station`, `id` | `/jobs/:id` as it is now, with what the clients show of it (client/core/src/jobs.rs): kept current by its events, read again each half minute (every 4 s from a station too old to say whose it is) |
| `jobLog` | `station`, `job` (id), `lines` | `{ text, outputAt, last, said }`: the job's last `lines` lines of output and when it last grew (below); `last` its last line, `said` (最后输出 · 3 分钟前) goes out fresh as it changes (jobs.rs) |
| `thread` | `station`, `thread` (id) | `{ first, last, caught, end, entries, thread }`: a window of the thread's entries `first ..= last` (`EntryView`s, never changed once read), at most 150 (`WINDOW`). It opens where the chat is to be read — the page before the first entry not read and the page from it while something is unread, else where it was left (`chat.place`), else the latest page — and its first value is whole: from what is kept when all of it is and it is current (the station's `threads` say how far each goes), else read first. `chat.older` / `chat.newer` bring in the page before / after (a page is kept ahead either way), as many going at the other end; `end`: it reaches the thread's latest entry, so what is said joins it; short of it, what is said waits on the device. `caught`: its last entry read rather than told as it was said. `thread` is its summary |
| `live` | `station`, `key` | the session as it runs (below) |
| `host` | `station` | host samples (`HostInfo`) |
| `status` | `workspace?` | what the core is waiting on, when it is worth saying (`StatusView`, status.rs): of a workspace its stations' waits (the relay and links opened for them too), its account's still.fail cloud socket down and the relay opened for no station; with none, all of it |
| `connection` | `station` | what a chat on the station says of its connection (`ConnectionView`, pill.rs): its link down or coming back, else its workspace's `status`; trouble at once, coming back only after 1.5 s, `back` (已连上) 1.5 s only after one was shown. No page shows it any more (the phones dropped the pill over a chat); kept for apps from before |
| `notices` | `workspace?` | what a person hears about while the client runs: chats of theirs that want them (docs/notifications.md); a workspace's, or every one's |
| `notify` | `workspace?` | notifications on this device: on or off, asked, whether to hold pushes, the notices to show now (docs/notifications.md), only the workspace's for a page in one |
| `adbShare` | — | this phone's adb as lent to a station's agents (`AdbShareView`, adb.rs; docs/adb-share.md): whether it is and to which, how the offer goes (`phase`), how the station's adb holds the phone (`adb`, `serial`, `message`), until when, the tunnels open now. Kept in memory only |

```jsonc
// live
{
  "loaded": true,             // the stream has sent the transcript it had; until then `timeline` may be partial
  "first": 800,               // where `timeline` starts in the transcript: its latest page first, `history.older` loads those before
  "timeline": [ … ],          // TimelineEntry: the transcript from entry `first`, appended as it grows
  "usage": { "modelCalls": 3, "inputTokens": 1200, "cachedTokens": 900, "outputTokens": 80, "model": "claude-…" } | null,
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
  (the stream is opened anew when that changes; the old one closes once the
  new one is open, so nothing falls between them). Events go into the topics
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
  was down, every live topic of the station is read once when it reopens
  (`thread` topics only what came after them: `?after=<last>`); `link` says
  how the stream is.
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
  what is kept, else `GET /sessions/:key/timeline?before=&limit=`.
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
`messages` are its entries merged (entries.rs): each message with its latest
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
| `chatJobs` | as `chat` | the chat's services and jobs as its pages show them (`ChatJobsView`, jobs.rs): every one, what matters first, each with its dot (`tone`), word, line (`meta`) and times in words (computed again when they next change, to the second); the button's `alarm`, the groups' notes, how many are current and ended, whose ended ones clearing takes |
| `usage` | `scope`, `days?` (7, the default, or 30) | what the agents of the scope's online stations spent (`UsageView`, views/usage.rs): `tiles` (cost, calls, input and output tokens), `daily` (each day's cost split by `series`, the four people who spent most and 其他), `lists` (按人 / 按对话 / 按账号 / 按模型, the most spent first, each with its share; a person merged across Slack and the page by email), `notes` (stations offline or too old, the first read under way, models without a price, since when anything is recorded) |
| `decisions` | `workspace` | the 奏 page: the cards waiting for the viewer in the workspace's chats (`DecisionsView`, decisions.rs; the name is from when the only cards were decisions), whatever their agents' states: `{ items, count, loading }`, each item `{ station, stationName, session, thread, title, seq, message, before, card, options, deferred?, text }` (the post with the card and the one or two messages before it as `chat` shows messages; `card` is `{type: "options", options}` or `{type: "text", placeholder?}`; `options` an options card's, the recommended one last, empty for a text card); pending and not dismissed by the viewer, oldest asked first, those set aside on this device (`decision.defer`) last; `count` for 奏 N |
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
| `auth.begin` | `redirect_uri`, `return_to`, `device_name`, `provider?` (`"google"` by default, or `"apple"`) | `{ url }` to open (web: navigate; native: system browser) |
| `auth.complete` | `query` (the callback's query string) | `{ account, return_to }` |
| `auth.signOut` | `account` | — |
| `slack.tokens.edit` | `station`, `form` (the generated `SlackTokenForm`), `input` (changed `appToken`, `botToken`, `connect`, `install`; `clear` invalidates verification) | the transient draft; also published as `{ topic: "slackTokens", station, form }` (`SlackTokensView`) |
| `slack.tokens.verify` | `station`, `form` | `true` only for the current verified draft; errors and identity in the topic. Late results for edited or closed forms cannot advance it |
| `slack.tokens.drop` | `station`, `form` | clears the in-memory draft; disconnecting its owning UI also clears it. Nothing is saved to device storage |
| *an operation* | `station` or `account`, and its own | what the station or still.fail cloud answers; see below |
| `chat.send` | `station`, `thread`, `text`, `attachments?`, `quotes?`, `client?` (the app it is sent from, for the chat's agent) | `{ seq }`, once the station has it and the chat's `thread` topic (when read) holds it. Only chats on still.fail's page take messages (the station refuses the rest). Meanwhile the message is in the view's `outbox` as `sending` (a failure leaves it there as `failed`, with `error`) |
| `chat.retry` / `chat.discard` | `station`, `thread`, `id` | sends a failed outbox message again / drops it |
| `decision.answer` | `station`, `thread`, `seq`, `option` (an option's `label`) | as `chat.send`: the viewer's message in the chat, the option's label quoting the post that asked (decisions.rs); refused once the chat's row no longer has that card pending, or for a card that is not an options card |
| `decision.reply` | `station`, `thread`, `seq`, `text` | as `chat.send`: what the viewer wrote in a text card's field, quoting the post that asked (decisions.rs); refused once the chat's row no longer has that card pending, or for a card that is not a text card |
| `decision.defer` | `station`, `thread`, `seq` | — ; 待定: set aside on this device (the prefs' `decisionsDeferred`), last on the `decisions` page, still pending. Nothing is sent |
| `decision.dismiss` | `station`, `thread`, `seq` | `PUT /threads/:thread/dismissed {n}`: the viewer will not take it up; off their rows' line, marks and `decisions`, on every device of theirs (the station keeps it); still pending for everyone else |
| `chat.older` | `station`, `thread` | `{ more }`: loads the page (50 entries) before the chat's oldest loaded entry into its `thread` topic — from what is kept, else from the station — so `messages` grows in front |
| `chat.newer` | `station`, `thread` | `{ more }`: loads the page after the chat's newest loaded entry (it is short of the end), from the device when it is there (kept ahead), as many going at the start; read, not said: nothing comes in with a motion |
| `chat.latest` | `station`, `thread` | — ; the chat's latest page in place of its window (the reader goes to its end); sending from a window short of its end does it too |
| `chat.place` | `station`, `thread`, `seq?` | — ; where the reader leaves the chat: the entry at the top of what shows, short of its end, or none at its end. It opens there next while nothing is unread (held while the core runs) |
| `history.older` | `station`, `key` | `{ more }`: loads the page (200 entries) of the session's transcript before its `live` topic's `first` into it — from what is kept, else from the station — so the `history` view's `items` grow in front (`more` in the view: there are older ones) |
| `chat.read` | `station`, `thread`, `seq` | — ; records that the viewer has read the chat up to entry `seq` (`PUT /threads/:id/read {n}`); nothing is sent when it is read that far already. `unread` in `chats` follows. The clients no longer call it: the core reads a chat up to its newest message while a UI shows its end on a page in view (`client.focus`, attend.rs) |
| `client.focus` | `visible?`, `focused?`, `chat?`, `left?`, `workspace?` | — ; where this UI's attention is (docs/notifications.md): what is read, a chat's `unreadLine` (held for the visit, older pages loaded first while `unreadAbove`) and which notices show follow from it; `workspace`, the one it is in (else its chat's) |
| `station.upload` | `station`, `key`, `name`, `bytes` | the attachment (into that session's workspace; a message may carry uploads of any session in its chat) |
| `station.file` | `station`, `key`, `name` | `{ type, bytes }` |
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
and what that changes (`ops.rs`; `scripts/check.sh` fails on a UI that asks
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
`account`: `workspace.create`, `workspace.rename`, `workspace.delete`,
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

## Crates

```
client/
  core/    stillfail-core  the core: host trait, protocol, store, accounts, cloud, mesh, station, views
  wasm/    stillfail-core-wasm web host (IndexedDB, fetch) + SharedWorker entry
  ffi/     stillfail-core-ffi  native host (reqwest, files) on a core thread, exported with uniffi
  node/    stillfail-core-node client/ffi's core thread for Node, exported with napi-rs (the desktop app)
```

`stillfail-core` modules:

- `host.rs` — the `Host` trait and its request/response types.
- `protocol.rs` — the messages above (serde).
- `core.rs` — `Core`: accepts client messages, routes calls, manages subscriptions. `core/calls.rs` holds the named calls and input validation.
- `ops.rs` — requests and their explicit update effects together. Compatibility fallbacks have their own effects; `station.rs` applies only the successful request's effect, before answering.
- `slack_tokens.rs` — transient token drafts and verification shared by Web and Android. Input controls echo keystrokes immediately; readiness and verification belong to core. Web retains the previous form for desktop cores without these calls.
- `store.rs` — topics: values, subscribers and watches, coalesced emission as deltas, eviction.
- `delta.rs` — the ops between two values of a topic.
- `accounts.rs` — sign-in (PKCE), token refresh (single flight per account), persistence.
- `cloud.rs` — still.fail cloud API: errors, `/v1/me`, workspaces, member credentials. (Its events socket is held in `core.rs`, with the account topics.)
- `mesh.rs` — the device endpoint (mDNS and the DHT to find stations, still.fail's and iroh's relays) and station links: the credential, reconnection, requests and streamed replies (wire format: `mesh/station/src/main.rs`).
- `station.rs` — the admin API over a mesh link: the station topics kept current from its events and live streams, threads (entries by number, gaps, paging, posting, read positions), uploads.
- `kept.rs` — threads' entries and transcripts kept on the device in 256-entry chunks through `Host` storage, bounded (least recently opened go first), forgotten for stations out of reach.
- `entries.rs` — a thread's entries merged into messages (edits applied): the one place that does it.
- `data.rs` — the data center (docs/core-db.md): what still.fail cloud and the stations said, held as records.
- `sync.rs` — what the core keeps in sync by itself, whatever the UI shows.
- `workspace.rs` — the workspaces, each with what is its own: its account, its stations' state, its waits, its notices, what is kept in sync of it.
- `notices.rs` — what a person hears about while the client runs (the `notices` topic), from how the chat rows change, each workspace's apart.
- `attend.rs` — where each UI's attention is (`client.focus`): chats' unread lines and what is read, notifications' settings and which notices show (the `notify` topic).
- `status.rs` — what the core is waiting on (the `status` topic): slow requests and links, sockets that are down; each workspace's waits, and the device's.
- `adb.rs` — this phone's adb lent to a station's agents (the `adbShare` topic, `adb.*`): the offer on the station's link, tunnels the station opens to adbd (docs/adb-share.md).
- `pill.rs` — what a chat says of its connection (the `connection` topic), and when.
- `activity.rs`, `history.rs`, `present.rs`, `format.rs` — what the clients show (an agent's current activity, its execution history, sessions' and rows' state, words and times), decided once for every client.
- `error.rs` — the one error type calls and topics report.
- `views.rs` — the view topics, put together from the others.
- `testing.rs` — a host for tests.
- `trace.rs` — traces of user actions: spans, the `traceparent` every station request carries, batched export to still.fail cloud (docs/telemetry.md).

## Native (Android)

`client/ffi` runs the core on a thread of its own: a tokio current-thread
runtime with a `LocalSet`. `start(data_dir, cloud_origin, listener)` returns an
object whose `connect()` / `receive(client, json)` / `disconnect(client)` only
post to that thread, so they never block the caller; the core answers on its
thread through `listener.on_message(client, json)`. The host fetches with
reqwest (rustls, Mozilla's roots like iroh's own TLS), keeps storage as one
file per key under `data_dir` (written aside and renamed, on a storage thread
so writes keep their order), and takes the time zone from the C library,
which on Android follows the system setting. A panic ends the core: every
client gets `{"fatal": "…"}` and the app starts a new one.

`apps/android` is the app (Gradle; `build.py` builds the core with the NDK,
generates the uniffi Kotlin bindings from the built library, then runs
Gradle). Its `:core` module is `fail.still.core.StillFailCore`: `call(name, params)`
and `topic(topic)` as a `Flow<TopicState>` — shared by everyone who collects
the same topic, deltas applied as on the web, unsubscribed 2 s after the last
collector leaves.

## Desktop

`apps/desktop` is the web app running natively: the window loads the cloud
build (`pnpm run build:cloud`'s `dist/cloud-web`, bundled into the app) from
`app://ember`, served as still.fail cloud serves it (a file, else `index.html`).
Nothing in the pages differs but the host underneath:

- The core runs in a `utilityProcess` (`src/core.ts`) through `client/node`,
  a thin napi-rs layer over `client/ffi` (the same core thread and host; the
  listener is a JS function on Node's thread), with its data in the app's
  `userData/core`. Its iroh endpoint is the full native one, so links go
  direct once the relay has introduced both sides.
- A page asks the main process for a channel (`emberDesktop.openCore`, from
  the preload): a `MessageChannelMain` whose one end goes to the core and the
  other to the page, as a window message (a port cannot cross the context
  bridge). `web/src/core/client.ts` uses that port instead of the
  SharedWorker (`desktopOpener`); the protocol is the same, posted as objects
  and answered as the core's JSON. A port that closes disconnects its client;
  a core process that exits is announced to every page, which opens a new
  channel (the main process starts a new core); a panic's `{"fatal"}` makes
  the core process start a new core for the channels that follow.
- Sign-in: `auth.begin` with `redirect_uri` `stillfail://auth/callback` (a scheme
  the app registers). Leaving `app://ember` opens the system browser instead
  (so does `window.open`); still.fail cloud sends the browser back to
  `stillfail://auth/callback?…`, which the OS hands to the app (`open-url` on
  macOS, `second-instance` elsewhere), and the app loads the page's own
  `/auth/callback` with that query, which calls `auth.complete` as on the web.

- The app carries a station release (scripts/station-bundle.sh) and runs
  `stillfail-station` itself (`src/station.ts`, docs/station-rust.md), on
  `~/.stillfail` like an installed station; when one is running already
  (`stillfail-station` exits with HELD) it leaves it be.

still.fail cloud defaults to https://app.still.fail; `STILLFAIL_CLOUD_ORIGIN`
overrides it. `apps/desktop/build.sh` builds the core and the station for
macOS arm64 and packages an `.app` with electron-builder. Use `UNSIGNED=1`
for a local unsigned package; release builds use the maintainer signing identity.
The internal `app://ember` origin is retained so existing localStorage and
IndexedDB data remain accessible.

## Web

`web/src/core/` is the UI side: it starts the worker (SharedWorker, else
Worker), speaks the protocol over its port, and gives React
`useTopic(topic)` (built on `useSyncExternalStore`) and `call(name, params)`.
In development the core can also run on the page itself, for debugging.

## Order of work

1. `stillfail-core` with a fake host in tests: protocol, store, accounts, cloud, mesh, station.
2. `stillfail-core-wasm` and `web/src/core`; the web app moves onto the core.
3. Electron shell (`client/node`).
4. Native apps (`client/ffi`; Android first), with push notifications through still.fail cloud.

## Operation contracts and module boundaries

`core.rs` owns initialization and the client protocol. `core/execute.rs` executes
named calls; `core/account_state.rs` reconciles accounts/workspaces and their
sockets; `core/routing.rs` routes topics. `station.rs` owns station state, with
wire types in `station/wire.rs`, requests in `station/transport.rs`, event and
reconnect handling in `station/events.rs`, and thread subscriptions/lifetimes in
`station/threads.rs`. Tests live beside those boundaries in their `tests.rs`.

The 81 ordinary station/cloud HTTP operations declare their scalar parameters
beside the routes in `ops.rs` (`@params`). `python3 scripts/operations.py` generates
`web/src/core/operations.ts` and Android's `data/Operations.kt`; `--check` rejects
drift and missing route inputs. These bindings own named calls and parameter
packing; the hand-written facades provide convenient return types and adapters.
Special core calls (chat streaming, picks, local drafts) keep their own adapters.
Optional fields distinguish absence (leave unchanged) from explicit `null`
(reset). Kotlin's optional-fields builder records assignments, including null;
it must not serialize every unassigned property. Tests cover both languages.

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
`doing`. Read-only exclusions are generated from `ops.rs` and `doing.rs`. Neither
adapter retains token/password/code parameters. A local entry lock prevents a
second click before the core's first update.

Business operations in account/workspace/profile/connection/archive/login and
confirmation controls use that shared state. Local pending flags remain for
browser/OS permissions, sign-in handoffs, image rendering/export, gesture
animations, old core compatibility and host callbacks with no single tracked
operation. Input echoes, optimistic setting queues and displayed errors remain
view concerns; they do not claim whether the station completed a write.
