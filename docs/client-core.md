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
- `now_ms`, `sleep`, `spawn`, `random_bytes`.
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
{ "id": 8, "value": { … } }         // a subscription's current value, sent on subscribe and on every change
{ "id": 8, "error": { … } }         // the topic could not be read (the subscription stays; a later value clears it)
```

A subscription's value is always the whole current value of its topic, not a
patch; the core sends at most one value per topic per animation frame's worth
of changes (coalesced, ~50 ms). Live steps are the exception that needs speed,
and they are small.

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
built from subscribed inside the core; its value is recomputed at most once
per coalescing window, however many of them changed.

`scope` is a workspace id, or `"local"` for the page served by a station
itself (one station, addressed `"local"`).

| View | Params | Value |
| --- | --- | --- |
| `chats` | `scope`, `mine` | the sidebar: `{ me, stations, loading, days }` |
| `stations` | `scope` | every station of the scope, each with its link, overview, host and usable models |
| `connects` | `scope` | every connect of every online station: `{ items: [{ station, stationName, connect }], loading }` |
| `chat` | `station`, `key` | one chat: `{ detail, connect, profile, link }` |

`live` (above) stays its own topic: its steps change many times a second and
are small, while `chat` carries the whole transcript.

```jsonc
// chats
{
  "me": { "id": "a@b.c", "email": "a@b.c" },     // "local" on a station's own page
  "stations": [{ "station": "ws/st", "id": "st", "name": "studio", "state": "online", "message": null }],
  //   state: "online" | "connecting" | "offline" (the cloud has not seen it) | "error" (message says why)
  "loading": false,                                // an online station has not answered yet
  "days": [{ "daysAgo": 0, "at": 1790000000000, "items": [{
    "station": "ws/st", "stationName": "studio",
    "session": { … },                              // the station's SessionSummary
    "connect": { … } | null                        // the connect it belongs to, from that station's overview
  }] }]
  // days: most recent first, grouped by the viewer's local calendar day; items by lastActiveAt, newest first;
  // with mine = true only sessions the viewer created (creator id or email matches me).
}

// stations
[{
  "station": "ws/st", "id": "st", "name": "studio",
  "online": true, "lastSeen": 1790000000, "version": "0.4.0",   // from the workspace (local: always online)
  "link": { "state": "online", "message": null },
  "overview": { … } | null,                                      // null while offline or not yet read
  "host": { … } | null,
  "runtimes": [{ "runtime": "claude", "models": ["…"] }]         // runtimes with an enabled model, and those models
}]

// chat
{
  "detail": { … },               // the session topic's value (SessionDetail), timeline kept current
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
  core/    ember-core      the core: host trait, protocol, store, accounts, cloud, mesh, station
  wasm/    ember-core-wasm web host (IndexedDB, fetch) + SharedWorker entry
```

`ember-core` modules:

- `host.rs` — the `Host` trait and its request/response types.
- `protocol.rs` — the messages above (serde).
- `core.rs` — `Core`: accepts client messages, routes calls, manages subscriptions.
- `store.rs` — topics: values, subscribers, refresh, coalesced emission, eviction.
- `accounts.rs` — sign-in (PKCE), token refresh (single flight per account), persistence.
- `cloud.rs` — ember cloud API: errors, `/v1/me`, workspaces, grants.
- `mesh.rs` — the device endpoint and station links: grants, renewal (every 5 min), reconnection, requests and streamed replies (wire format: `mesh/station/src/main.rs`).
- `station.rs` — the admin API over a link (or over HTTP for `local`): typed paths, event and live streams, uploads.

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
