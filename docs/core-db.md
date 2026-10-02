# The core's database

Status: partly built (`client/core/src/data.rs`, `client/core/src/sync.rs`).
Workspaces, stations and each station's rows, sessions, threads and overview
are records in the core's database; thread entries and transcripts are still
in `kept.rs`; read positions and the outbox are not records yet.

## Why

The core used to hold what it read in memory, per topic, and kept only thread
entries and transcripts on the device (`kept.rs`). A cold start, or a chat not
opened before, waited for the station; views filled in piecemeal (a chat's
messages before its agents), and the UIs were starting to paper over that with
data from other views. The rule stays: the UI subscribes to views and draws
them. What changes is where views come from.

## The model

The core keeps still.fail's business data as records, per account:

| Record | Key | From | Built |
|---|---|---|---|
| me | account | cloud `/v1/me` | yes |
| workspace (with its stations) | id | cloud `/v1/workspaces/:id`, cloud events | yes |
| row (sidebar item) | station, id | station `/chats`, `chat`/`chat-removed` events | yes |
| session summary | station, key | `/sessions`, `session` events | yes |
| session | station, key | `/sessions/:key`, `session` events | yes |
| thread | station, id | `/threads`, `thread` events | yes |
| overview | station | `/overview`, `overview` events (connects, profiles, Slack bindings) | yes |
| entry | station, thread, n | `/threads/:id/entries`, `thread` events (append-only) | no: `kept.rs` |
| transcript item | station, session, n | `/sessions/:key/live` (append-only) | no: `kept.rs` |
| read position | station, thread | `read` events, `chat.read` | no |
| outbox message | station, thread, local id | `chat.send` (until its entry comes) | no |

A list (rows, session summaries, threads) is one record per item plus a
`list` record with the ids in order, so an empty list read is told apart from
one never read. Not built yet: each record carrying when it was last
confirmed by its source. Nothing is derived and stored: views (chats, chat, stations,
…) are computed from records.

## How data moves

- **In**: every reply and event is written as records, never straight into a
  topic. A topic held here has no value of its own in the store: its value is
  read from the records when asked for.
- **Out**: a write marks the records it changed; the topics and views that
  read them are recomputed and their deltas pushed (the store's existing
  coalescing window). What the core is waiting on (slow requests, links down)
  is said once, by the `status` topic (`status.rs`), not per view.
- **Sync** (`sync.rs`): for as long as the core runs, whatever the UI shows, it
  keeps the accounts' workspaces, each workspace's stations, and of each
  reachable station its link, overview, chat rows, sessions and threads, plus
  the live state of every agent at work. Messages are kept by the stations
  module: the latest chats' pages (`warm`) and a page ahead of what a chat
  shows. Events keep it current. No polling.
- **Startup**: the core loads the records before any network, so views are
  answered at once; offline, they stay as last seen.

## Storage

The records live in memory, by table and key, and are written through to a
database the host provides (`Host::db_read` / `db_write`: ranges of keys in a
table, and batches of puts and deletes written at once or not at all):

- natively (desktop, Android): SQLite, `core.db` in the app's data directory
  (`client/ffi/src/host.rs`);
- on the web: IndexedDB (`client/wasm/src/idb.rs`).

## Order of work

1. Done: records and the write path for workspaces, stations, rows,
   sessions, threads, overview; topics read them; startup from the database.
2. Entries and transcripts move from `kept.rs` into records (same chunking),
   with a size cap and least-recently-opened eviction (metadata is small and
   always kept).
3. Done: background sync (`sync.rs`).
4. Tests: views from a database with no network, restarts, lists, updates
   (done, `data.rs`); eviction once entries move.
