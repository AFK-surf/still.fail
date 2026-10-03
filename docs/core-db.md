# The core's database

Status: built (the TS core, docs/core-ts.md: `client/core-ts/src/data.ts`, the
sync in `client/core-ts/src/sync/` and `src/station/sync.ts`). Everything below
is a record, entries, transcripts, read positions and the outbox included; what
the Rust core kept in `kept.rs` chunks is read into records once
(`client/core-ts/src/kept.ts`).

## Why

The core used to hold what it read in memory, per topic, and kept only thread
entries and transcripts on the device (the Rust core's `kept.rs`). A cold start, or a chat not
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
| entry | station, thread, n | `/threads/:id/entries`, `thread` events (append-only) | yes (table `entry`) |
| transcript item | station, session, n | `/sessions/:key/live` (append-only) | yes (table `transcript`) |
| read position | station, thread | `read` events, `chat.read` | yes (in the thread and row records) |
| outbox message | station, thread, local id | `chat.send` (until its entry comes) | yes (table `outbox`; also `pending`, `first`, `changing`) |

A list (rows, session summaries, threads) is one record per item plus a
`list` record with the ids in order, so an empty list read is told apart from
one never read. Each record carries when it was last confirmed by its source
(table `confirmed`). Nothing is derived and stored: views (chats, chat, stations,
…) are computed from records.

## How data moves

- **In**: every reply and event is written as records, never straight into a
  topic. A topic held here has no value of its own in the store: its value is
  read from the records when asked for.
- **Out**: a write marks the records it changed; the topics and views that
  read them are recomputed and their deltas pushed (the store's existing
  coalescing window). What the core is waiting on (slow requests, links down)
  is said once, by the `status` topic (`status.ts`), not per view.
- **Sync** (`sync/scheduler.ts`, `sync/cloud.ts`, `station/sync.ts`): for as long as
  the core runs, whatever the UI shows, it keeps the accounts' workspaces, each
  workspace's stations, and of each reachable station everything it holds: link,
  overview, chat rows, sessions and their details, threads and every thread's
  entries (latest page first, then back to the first), transcripts, jobs, usage,
  footprint, the live state of every agent at work — except the logs let go to
  keep within the size cap, until their chat is opened. A UI only makes some of it
  more urgent (`client.focus`, a topic shown). Events keep it current. No polling.
- **Startup**: the core loads the records before any network, so views are
  answered at once; offline, they stay as last seen.

## Storage

The records live in memory, by table and key, and are written through to a
database the host provides (`Host::db_read` / `db_write`: ranges of keys in a
table, and batches of puts and deletes written at once or not at all):

- on the desktop: SQLite (`node:sqlite`), `core.db` in the app's data directory
  (`client/core-ts/src/hosts/node.ts`);
- on Android: the same SQLite file, kept by the native shell
  (`client/shell`, asked through `client/core-ts/src/hosts/bridge.ts`);
- on the web: IndexedDB (`client/core-ts/src/hosts/web.ts`).

## Order of work

1. Done: records and the write path for workspaces, stations, rows,
   sessions, threads, overview; topics read them; startup from the database.
2. Done: entries and transcripts are records (one per entry); the Rust core's
   chunks are read in once. A size cap (`KEPT_LIMIT`, 50 MB, as `kept.rs` had)
   with least-recently-opened eviction: past it, the entries or transcript of
   the logs not shown now go, the least recently opened first (the `log` table
   keeps each log's size, when its chat was last opened, and whether it was let
   go); metadata (rows, sessions, threads, read positions, outbox, pending) is
   small and always kept. A log let go is not brought back by the background
   sync, nor by its events: only once its chat is opened (the sync reads it then,
   as urgently as it is shown), so nothing is fetched and evicted in a loop. A
   station's records go once no signed-in account reaches it (`Data.retain`).
3. Done: background sync (`sync/`, `station/sync.ts`).
4. Done: tests (client/core-ts/test/data.test.ts, station-flows.test.ts).
