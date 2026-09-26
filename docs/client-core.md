# ember client core

The logic of an ember client — accounts, ember cloud, the mesh links to
stations, requests and live streams, the cache of what has been read — lives in
one Rust crate, `ember-core`, shared by every client:

| Client | Where the core runs | Binding |
| --- | --- | --- |
| Web (ember.3720.org) | a SharedWorker (a dedicated Worker where SharedWorker is missing, e.g. Chrome on Android) | `client/wasm` (wasm-bindgen) |
| Desktop (Electron) | a `utilityProcess` | `client/node` (napi-rs) over `client/ffi` |
| Android (iOS later) | a core thread in the app | `client/ffi` (uniffi) |

The UI never talks to ember cloud or a station itself. It sends **calls** and
holds **subscriptions** to the core over one message channel, and renders the
snapshots the core pushes. Several UIs (tabs, windows) share one core: one
device key, one link per station, one token refresh, one cache.

## Execution model

The core is single-threaded and async. Its futures are `!Send`; shared state
is `Rc<RefCell<…>>`. On the web it runs on the worker's event loop
(`wasm-bindgen-futures`); natively on a dedicated thread running a tokio
current-thread runtime with a `LocalSet`. Nothing in the core blocks.

## Host

What differs per platform comes in through one trait, `Host`
(`client/core/src/host.rs`):

- `fetch` — one HTTP request to ember cloud, whole body; `fetch_stream` — a
  streamed response (the local station's `/admin/api` event streams, web only);
  `websocket` — a receive-only WebSocket (ember cloud's `/v1/events`) with the
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
{ "id": 7, "call": "station.request", "params": { … } }   // one answer
{ "id": 8, "subscribe": { "topic": "station.session", "station": "ws1/st1", "key": "…" } }
{ "id": 8, "unsubscribe": true }
```

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

A station is addressed as `"<workspace>/<station>"`, or `"local"` for the page
served by a station itself. The core knows which signed-in account reaches
which workspace (from each account's `/v1/me`) and uses that account's token
for grants.

### Topics

| Topic | Params | Value |
| --- | --- | --- |
| `accounts` | — | signed-in accounts (no tokens) |
| `workspaces` | — | every workspace of every account, with its account and pending invitations |
| `workspace` | `workspace` | the workspace view (members, stations with `online`) |
| `link` | `station` | the station's events stream: `connecting` / `online` / `offline` / `error` + message |
| `overview` | `station` | the admin API's `/overview` |
| `sessions` | `station` | `/sessions` (the shown sessions' `SessionSummary`s) |
| `threads` | `station` | `/threads`: every thread (`ThreadView`: its sessions, people, first person message, last message, the viewer's `read` and `unread`), latest message first |
| `chatRows` | `station` | `/chats`: the viewer's sidebar rows as the station puts them together (`ChatRow`; docs/station-storage.md, The sidebar) |
| `session` | `station`, `key` | `/sessions/:key`: `{ session, threads, turns }` (no messages, no transcript) |
| `thread` | `station`, `thread` (id) | `{ rev, messages, more }`: the thread's latest page of `MessageView`s by `seq`, older pages in front as `chat.older` loads them; `more`: older ones exist |
| `live` | `station`, `key` | the session as it runs (below) |
| `host` | `station` | host samples (`HostInfo`) |

```jsonc
// live
{
  "loaded": true,             // the stream has sent the transcript it had; until then `timeline` may be partial
  "timeline": [ … ],          // TimelineEntry: the whole transcript from entry 0, appended as it grows
  "usage": { "modelCalls": 3, "inputTokens": 1200, "cachedTokens": 900, "outputTokens": 80, "model": "claude-…" } | null,
  "steps": [ … ],             // steps in flight (LiveStep; an ended one keeps "ended": true until the entry that records it arrives)
  "phase": { "phase": "requesting", "since": 1790000000000 } | null
}
```

Nothing is read on a timer. Each topic is read once when it starts; after
that only notifications change it:

- `accounts`, `workspaces` and `workspace`: while `workspaces` or any
  `workspace` is live (a view resting on one counts), each signed-in account
  holds ember cloud's `/v1/events` socket (subprotocols `ember-events` and
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
  `thread` merges the changed messages into that `thread` topic (by `seq`; a
  message older than the pages loaded is left until its page is) and, since
  it does not carry unread counts, reads `/threads/:id` for the `threads` and
  `session` topics that list it (bursts coalesced over 400 ms; a 404 removes
  it); `read` sets the thread's `read` there, and `unread` to 0 when it covers
  the last message (else the thread is read again), and turns off `unread` of
  that thread's `chatRows` row when it covers the row's last message; `chat`
  puts a row into `chatRows` (replacing the one with its `id`), `chat-removed`
  takes one out; `overview` and `host` are the whole values. After the stream was down, every live topic of the station
  is read once when it reopens (`thread` topics only what changed:
  `?after=<rev>`); `link` says how the stream is.
- `live` holds `/sessions/:key/live?from=<entries it has>` open; a timeline
  message that cannot be placed starts it over from 0.

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
are online — connected to ember cloud right now, as the `workspace` topic says —
and follows the workspace's station list as it changes. It has no value until
the `workspace` topic has one; a failed `workspace` is the view's error, while
a failing station only shows in that station's state. `chat` watches the
station's `threads` and `sessions`, its thread's `thread` (messages),
`overview` and `link` — all asked for at once when it starts, so a chat opens
in one round of requests — and, once `threads` names them, the `session` of
each of its agents. It has a value as soon as its thread is in `threads` and
its latest page of messages is read; its agents fill in after (an agent whose
`session` is not read yet is its summary from `sessions`, without turns or
threads; one that fails is left out). A failed `threads` or `thread` is its
error, and so is its thread missing from `threads` (404). With `session`
instead of `thread`, `chat` watches that `session`, `sessions`, `chatRows`,
`overview` and `link`.

While a `chats` view is live, a clock waits for the viewer's next local
midnight and recomputes it then (`daysAgo` changes); that is the only timer of
the views.

`scope` is a workspace id, or `"local"` for the page served by a station
itself (one station, addressed `"local"`).

| View | Params | Value |
| --- | --- | --- |
| `chats` | `scope`, `mine` | the sidebar: `{ me, stations, loading, days }`; every station's rows side by side |
| `stations` | `scope` | every station of the scope, each with its link, overview, host and usable models |
| `connects` | `scope`, `mine` | every connect of every online station: `{ me, items: [{ station, stationName, connect }], loading }`; with `mine`, those whose `createdBy.id` is me |
| `chat` | `station`, and `thread` (id) or `session` (key) | an item's page: `{ me, thread, title, people, agents, messages, more, outbox, link }` |

`live` (above) stays its own topic: its steps change many times a second,
while `chat` changes with messages.

```jsonc
// chats
{
  "me": { "id": "a@b.c", "email": "a@b.c" },     // { "id": "local", "email": null } on a station's own page
  "stations": [{ "station": "ws/st", "id": "st", "name": "studio", "state": "online", "message": null }],
  //   state: "online" | "connecting" | "offline" (not connected to ember cloud) | "error" (message says why)
  //   error: its rows could not be read, or its link failed; connecting: rows not read yet, or the link
  //   is reconnecting (rows already read stay listed). The local station is named "".
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
  "online": true, "lastSeen": 1790000000, "version": "0.4.0",   // from the workspace (local: always online)
  "link": { "state": "online", "message": null },
  "overview": { … } | null,                                      // null while offline or not yet read
  "host": { … } | null,
  "runtimes": [{ "runtime": "claude", "models": ["…"] }]         // claude, codex if a profile has models enabled; those models, distinct and sorted
}]

// chat
{
  "me": { … },                   // as in chats
  "thread": { … } | null,        // the ThreadView (with the viewer's `read` position and `unread`, `people`, `last`); null before the agent has a chat
  "title": "…",                  // see below
  "people": [ … ],               // the thread's people
  "agents": [{                   // its sessions, in the order they joined
    "session": { … },            // SessionSummary
    "connect": { … } | null,     // the connect that started the session, from the overview
    "profile": { … } | null,     // the profile it runs on, from the overview
    "turns": [ … ],              // TurnRecord, oldest first ([] until its session is read)
    "threads": [ … ]             // ThreadView: every thread it takes part in ([] until read), to name the places in its history
  }],
  "messages": [ … ],             // the thread's MessageViews loaded so far, by seq (deleted ones included, with deletedAt)
  "more": true,                  // older messages exist: `chat.older` loads the page before them
  "outbox": [{ "id": "out-1", "text": "…", "attachments": [], "quotes": [], "createdAt": 1790000000000, "state": "sending", "error": null, "seq": 42 }],
  //   messages sent from this device that `messages` does not show yet; `seq` once the station has it. An entry leaves
  //   in the same emission that brings a message with that seq (or a later one) into `messages`.
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
`thread.read` at that moment; a client keeps it for the visit (the web draws
its "以下是新消息" line from it) while reading moves the position on.

Grouping by day needs the viewer's time zone: `Host::utc_offset_min(at_ms)`
gives it (web: `-new Date(at).getTimezoneOffset()`).

### Calls

| Call | Params | Result |
| --- | --- | --- |
| `auth.begin` | `redirect_uri`, `return_to`, `device_name` | `{ url }` to open (web: navigate; native: system browser) |
| `auth.complete` | `query` (the callback's query string) | `{ account, return_to }` |
| `auth.signOut` | `account` | — |
| `cloud.request` | `account`, `method`, `path`, `body?` | the JSON answer (the core adds the token and refreshes it) |
| `station.request` | `station`, `method`, `path`, `body?` | the JSON answer; the core then refreshes the topics this write can change |
| `chat.send` | `station`, `thread`, `text`, `attachments?`, `quotes?` | `{ seq }`, once the station has it and the chat's `thread` topic (when read) holds it. Only chats on ember's page take messages (the station refuses the rest). Meanwhile the message is in the view's `outbox` as `sending` (a failure leaves it there as `failed`, with `error`) |
| `chat.retry` / `chat.discard` | `station`, `thread`, `id` | sends a failed outbox message again / drops it |
| `chat.older` | `station`, `thread` | `{ more }`: loads the page (50) before the chat's oldest loaded message into its `thread` topic, so `messages` grows in front |
| `chat.read` | `station`, `thread`, `seq` | — ; records that the viewer has read the chat up to `seq` (`PUT /threads/:id/read`); nothing is sent when it is read that far already. `unread` in `chats` follows |
| `station.upload` | `station`, `key`, `name`, `bytes` | the attachment (into that session's workspace; a message may carry uploads of any session in its chat) |
| `station.file` | `station`, `key`, `name` | `{ type, bytes }` |
| `migrate` | `accounts`, `device` | — (web only: what localStorage held before the core existed) |

Writes go through `station.request`, which answers only after the live topics
the write touches are current, so the UI never invalidates caches itself and a
page that navigates right after a write finds what it wrote: an answer that is
an overview (profile and connect edits) becomes the `overview`; a thread
(`POST /threads`, `POST /threads/:id/sessions`) goes into `threads` and the
`session` topics; a read position into the threads; otherwise the touched
topics are read again (`/sessions…` → `session`, `sessions` and `chatRows`;
a thread answered by `/threads…` → `chatRows` as well; `/connects…` →
`overview` and `sessions`; `/profiles…`, `/slack…` → `overview`;
`/me/slack/:user` → `overview` (its answer) and `chatRows`;
`/threads/:id/messages` → that `thread`). The station's events
bring the same a moment later.

## Crates

```
client/
  core/    ember-core      the core: host trait, protocol, store, accounts, cloud, mesh, station, views
  wasm/    ember-core-wasm web host (IndexedDB, fetch) + SharedWorker entry
  ffi/     ember-core-ffi  native host (reqwest, files) on a core thread, exported with uniffi
  node/    ember-core-node client/ffi's core thread for Node, exported with napi-rs (the desktop app)
```

`ember-core` modules:

- `host.rs` — the `Host` trait and its request/response types.
- `protocol.rs` — the messages above (serde).
- `core.rs` — `Core`: accepts client messages, routes calls, manages subscriptions.
- `store.rs` — topics: values, subscribers and watches, coalesced emission as deltas, eviction.
- `delta.rs` — the ops between two values of a topic.
- `accounts.rs` — sign-in (PKCE), token refresh (single flight per account), persistence.
- `cloud.rs` — ember cloud API: errors, `/v1/me`, workspaces, grants. (Its events socket is held in `core.rs`, with the account topics.)
- `mesh.rs` — the device endpoint and station links: grants, renewal (every 5 min), reconnection, requests and streamed replies (wire format: `mesh/station/src/main.rs`).
- `station.rs` — the admin API over a link (or over HTTP for `local`): the station topics kept current from its events and live streams, threads (paging, posting, read positions), uploads.
- `views.rs` — the view topics, put together from the others.
- `trace.rs` — traces of user actions: spans, the `traceparent` every station request carries, batched export to ember cloud (docs/telemetry.md).

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
Gradle). Its `:core` module is `dev.ember.core.EmberCore`: `call(name, params)`
and `topic(topic)` as a `Flow<TopicState>` — shared by everyone who collects
the same topic, deltas applied as on the web, unsubscribed 2 s after the last
collector leaves.

## Desktop

`apps/desktop` is the web app running natively: the window loads the cloud
build (`pnpm run build:cloud`'s `dist/cloud-app`, bundled into the app) from
`app://ember`, served as ember cloud serves it (a file, else `index.html`).
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
- Sign-in: `auth.begin` with `redirect_uri` `ember://auth/callback` (a scheme
  the app registers). Leaving `app://ember` opens the system browser instead
  (so does `window.open`); ember cloud sends the browser back to
  `ember://auth/callback?…`, which the OS hands to the app (`open-url` on
  macOS, `second-instance` elsewhere), and the app loads the page's own
  `/auth/callback` with that query, which calls `auth.complete` as on the web.

ember cloud defaults to https://ember.3720.org; `EMBER_CLOUD_ORIGIN`
overrides it. `apps/desktop/build.sh` builds the core for macOS arm64 and
packages an unsigned `.app` with electron-builder.

## Web

`web/src/core/` is the UI side: it starts the worker (SharedWorker, else
Worker), speaks the protocol over its port, and gives React
`useTopic(topic)` (built on `useSyncExternalStore`) and `call(name, params)`.
The pages move from `@tanstack/react-query` and `Transport` to these.
In development the core can also run on the page itself, for debugging.

## Order of work

1. `ember-core` with a fake host in tests: protocol, store, accounts, cloud, mesh, station.
2. `ember-core-wasm` and `web/src/core`; the web app moves onto the core.
3. Electron shell (`client/node`).
4. Native apps (`client/ffi`; Android first), with push notifications through ember cloud.
