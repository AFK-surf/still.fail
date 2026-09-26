# ember client core

The logic of an ember client — accounts, ember cloud, the mesh links to
stations, requests and live streams, the cache of what has been read — lives in
one Rust crate, `ember-core`, shared by every client:

| Client | Where the core runs | Binding |
| --- | --- | --- |
| Web (ember.3720.org) | a SharedWorker (a dedicated Worker where SharedWorker is missing, e.g. Chrome on Android) | `client/wasm` (wasm-bindgen) |
| Desktop (Electron) | a `utilityProcess` | `client/node` (napi-rs), later |
| iOS / Android (native) | a core thread in the app | `client/ffi` (uniffi), later |

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
- `now_ms`, `utc_offset_min` (the viewer's time zone), `sleep`, `spawn`, `random_bytes`.
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
| `threads` | `station` | `/threads`: every thread (`ThreadView`: its sessions, last message, the viewer's `read` and `unread`), latest message first |
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
  the last message (else the thread is read again); `overview` and `host` are
  the whole values. After the stream was down, every live topic of the station
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
changed. A workspace view watches the `sessions` / `overview` / `threads` /
`link` (for `stations`: `link` / `overview` / `host`) of the stations that are
online — connected to ember cloud right now, as the `workspace` topic says —
and follows the workspace's station list as it changes. It has no value until
the `workspace` topic has one; a failed `workspace` is the view's error, while
a failing station only shows in that station's state. `chat` watches the
session, the station's `overview` and `link`, and its chat's `thread`; it has
no value until the session is read (and, when it has a chat on ember's page,
that thread's latest page), and their errors are its error.

While a `chats` view is live, a clock waits for the viewer's next local
midnight and recomputes it then (`daysAgo` changes); that is the only timer of
the views.

`scope` is a workspace id, or `"local"` for the page served by a station
itself (one station, addressed `"local"`).

| View | Params | Value |
| --- | --- | --- |
| `chats` | `scope`, `mine` | the sidebar: `{ me, stations, loading, days }` |
| `stations` | `scope` | every station of the scope, each with its link, overview, host and usable models |
| `connects` | `scope`, `mine` | every connect of every online station: `{ me, items: [{ station, stationName, connect }], loading }`; with `mine`, those whose `createdBy.id` is me |
| `chat` | `station`, `key` | one chat: `{ me, session, threads, turns, thread, messages, more, outbox, connect, profile, link }` |

`live` (above) stays its own topic: its steps change many times a second,
while `chat` changes with messages.

```jsonc
// chats
{
  "me": { "id": "a@b.c", "email": "a@b.c" },     // { "id": "local", "email": null } on a station's own page
  "stations": [{ "station": "ws/st", "id": "st", "name": "studio", "state": "online", "message": null }],
  //   state: "online" | "connecting" | "offline" (not connected to ember cloud) | "error" (message says why)
  //   error: its sessions could not be read, or its link failed; connecting: sessions not read yet, or the link
  //   is reconnecting (sessions already read stay listed). The local station is named "".
  "loading": false,                                // an online station has not answered yet
  "days": [{ "daysAgo": 0, "at": 1790000000000, "items": [{
    "station": "ws/st", "stationName": "studio",
    "session": { … },                              // the station's SessionSummary
    "connect": { … } | null,                       // the connect it belongs to, from that station's overview
    "unread": 2                                    // the viewer's unread messages, summed over the threads the session takes part in (0 until `threads` is read)
  }] }]
  // days: most recent first, grouped by the viewer's local calendar day; items by lastActiveAt, newest first;
  // with mine = true only sessions the viewer takes part in: the creator or a participant matches me (id, or email case-insensitively).
}

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
  "session": { … },              // SessionSummary
  "threads": [ … ],              // ThreadView: every thread the session takes part in (Slack threads, chats on ember's page)
  "turns": [ … ],                // TurnRecord, oldest first
  "thread": { … } | null,        // its chat on ember's page (the first thread with surface "ember"); null until a message makes one
  "messages": [ … ],             // that thread's MessageViews loaded so far, by seq (deleted ones included, with deletedAt)
  "more": true,                  // older messages exist: `chat.older` loads the page before them
  "outbox": [{ "id": "out-1", "text": "…", "attachments": [], "quotes": [], "createdAt": 1790000000000, "state": "sending", "error": null, "seq": 42 }],
  //   messages sent from this device that `messages` does not show yet; `seq` once the station has it. An entry leaves
  //   in the same emission that brings a message with that seq (or a later one) into `messages`.
  "connect": { … } | null,
  "profile": { … } | null,       // the profile the session runs on, from the overview
  "link": { "state": "online", "message": null }
}
```

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
| `chat.send` | `station`, `key`, `text`, `attachments?`, `quotes?` | `{ seq }`, once the station has it and the chat's `thread` topic (when read) holds it. Posts into the session's chat on ember's page, opening one first (`POST /threads {session}`) when it has none. Meanwhile the message is in the view's `outbox` as `sending` (a failure leaves it there as `failed`, with `error`) |
| `chat.retry` / `chat.discard` | `station`, `key`, `id` | sends a failed outbox message again / drops it |
| `chat.older` | `station`, `key` | `{ more }`: loads the page (50) before the chat's oldest loaded message into its `thread` topic, so `messages` grows in front |
| `chat.read` | `station`, `key`, `seq` | — ; records that the viewer has read the chat up to `seq` (`PUT /threads/:id/read`); nothing is sent when it is read that far already. `unread` in `chats` follows |
| `station.upload` | `station`, `key`, `name`, `bytes` | the attachment |
| `station.file` | `station`, `key`, `name` | `{ type, bytes }` |
| `migrate` | `accounts`, `device` | — (web only: what localStorage held before the core existed) |

Writes go through `station.request`, which answers only after the live topics
the write touches are current, so the UI never invalidates caches itself and a
page that navigates right after a write finds what it wrote: an answer that is
an overview (profile and connect edits) becomes the `overview`; a thread
(`POST /threads`, `POST /threads/:id/sessions`) goes into `threads` and the
`session` topics; a read position into the threads; otherwise the touched
topics are read again (`/sessions/:key/…` → `session` and `sessions`;
`/connects…` → `overview` and `sessions`; `/profiles…`, `/slack…` →
`overview`; `/threads/:id/messages` → that `thread`). The station's events
bring the same a moment later.

## Crates

```
client/
  core/    ember-core      the core: host trait, protocol, store, accounts, cloud, mesh, station, views
  wasm/    ember-core-wasm web host (IndexedDB, fetch) + SharedWorker entry
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
4. Native apps (`client/ffi`), with push notifications through ember cloud.
