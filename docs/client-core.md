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
  streamed response (the local station's `/admin/api` event streams, web only).
- `storage_get` / `storage_set` / `storage_delete` — small persistent values by
  key (accounts and tokens, the device key, UI preferences). Web: IndexedDB
  (a worker has no localStorage); native: a file in the app's data directory.
- `now_ms`, `utc_offset_min` (the viewer's time zone), `sleep`, `spawn`, `random_bytes`.
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
| `workspace` | `workspace` | the workspace view (members, stations with online state) |
| `link` | `station` | the mesh link: `connecting` / `online` / `offline` / `error` + message |
| `overview` | `station` | the admin API's `/overview` |
| `sessions` | `station` | `/sessions` |
| `session` | `station`, `key` | `/sessions/:key`, its transcript timeline kept current from the live stream |
| `live` | `station`, `key` | the steps in flight and the phase (`LiveMessage` semantics of `src/live.ts`) |
| `host` | `station` | `/host` |

`accounts`, `workspaces` and `workspace` follow each account's `/v1/events`
socket (ember cloud; auth, events and shapes in `docs/station-storage.md`):
`workspaces` refetches `/v1/me`, `workspace` that workspace, and `station`
sets the station's `online` in the workspace value without a request.

The core keeps each topic current: the station's `/events` stream says which
sessions changed (it refetches those topics that are subscribed), `live`
subscriptions hold `/sessions/:key/live` open and merge its `timeline`
messages into the `session` value, and `overview` / `host` refresh on a timer
(10 s / 15 s) while subscribed. A topic nobody subscribes to is dropped after
a minute.

### Views

The UI does no joining, filtering or grouping of data: every screen subscribes
to one **view** topic that the core has already put together from the
topics above (and keeps current as they change). A view keeps the topics it is
built from subscribed inside the core (`Store::watch`: it counts as a
subscriber and hears each change); a change only marks the view stale, and it
is computed once, when its coalesced emission goes out, however many of them
changed. A workspace view watches the `sessions` / `overview` / `link` (and
for `stations`, `host`) of the stations that are online — `last_seen` less than
150 s ago, as in the web — and follows the workspace's station list as it
changes. It has no value until the `workspace` topic has one; a failed
`workspace` is the view's error, while a failing station only shows in that
station's state. `chat` has no value until the session is read, and the
session's error is its error.

`scope` is a workspace id, or `"local"` for the page served by a station
itself (one station, addressed `"local"`).

| View | Params | Value |
| --- | --- | --- |
| `chats` | `scope`, `mine` | the sidebar: `{ me, stations, loading, days }` |
| `stations` | `scope` | every station of the scope, each with its link, overview, host and usable models |
| `connects` | `scope`, `mine` | every connect of every online station: `{ me, items: [{ station, stationName, connect }], loading }`; with `mine`, those whose `createdBy.id` is me |
| `chat` | `station`, `key` | one chat: `{ me, detail, connect, profile, link }` |

`live` (above) stays its own topic: its steps change many times a second and
are small, while `chat` carries the whole transcript.

```jsonc
// chats
{
  "me": { "id": "a@b.c", "email": "a@b.c" },     // { "id": "local", "email": null } on a station's own page
  "stations": [{ "station": "ws/st", "id": "st", "name": "studio", "state": "online", "message": null }],
  //   state: "online" | "connecting" | "offline" (the cloud has not seen it) | "error" (message says why)
  //   error: its sessions could not be read, or its link failed; connecting: sessions not read yet, or the link
  //   is reconnecting (sessions already read stay listed). The local station is named "".
  "loading": false,                                // an online station has not answered yet
  "days": [{ "daysAgo": 0, "at": 1790000000000, "items": [{
    "station": "ws/st", "stationName": "studio",
    "session": { … },                              // the station's SessionSummary
    "connect": { … } | null                        // the connect it belongs to, from that station's overview
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
  "detail": { … },               // the session topic's value (SessionDetail), timeline kept current
  "connect": { … } | null,
  "profile": { … } | null,       // the profile the session runs on, from the overview
  "link": { "state": "online", "message": null },
  "outbox": [{ "id": "out-1", "text": "…", "attachments": [], "quotes": [], "createdAt": 1790000000000, "state": "sending", "error": null }]
  // messages sent from this device that the session does not show yet; each leaves in the same emission that brings the session's own copy
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
| `chat.send` | `station`, `key`, `text`, `attachments?`, `quotes?` | answers once the station has it and the `chat` view shows it; meanwhile the message is in the view's `outbox` as `sending` (a failure leaves it there as `failed`, with `error`) |
| `chat.retry` / `chat.discard` | `station`, `key`, `id` | sends a failed outbox message again / drops it |
| `station.upload` | `station`, `key`, `name`, `bytes` | the attachment |
| `station.file` | `station`, `key`, `name` | `{ type, bytes }` |
| `migrate` | `accounts`, `device` | — (web only: what localStorage held before the core existed) |

Writes go through `station.request`; after a successful write the core
refetches the subscribed topics of that station that the path touches
(`/sessions/:key/…` → `session` and `sessions`; `/connects…`, `/profiles…` →
`overview`), so the UI never invalidates caches itself.

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
- `cloud.rs` — ember cloud API: errors, `/v1/me`, workspaces, grants.
- `mesh.rs` — the device endpoint and station links: grants, renewal (every 5 min), reconnection, requests and streamed replies (wire format: `mesh/station/src/main.rs`).
- `station.rs` — the admin API over a link (or over HTTP for `local`): typed paths, event and live streams, uploads.
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
