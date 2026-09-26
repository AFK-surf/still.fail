# The core's database (proposal)

Status: proposal, not built. Replaces `kept.rs` and the in-memory topic values
as the core's source of truth.

## Why

Today the core holds what it read in memory, per topic, and keeps only thread
entries and transcripts on the device (`kept.rs`). A cold start, or a chat not
opened before, waits for the station; views fill in piecemeal (a chat's
messages before its agents), and the UIs were starting to paper over that with
data from other views. The rule stays: the UI subscribes to views and draws
them. What changes is where views come from.

## The model

The core keeps ember's business data as records, per account:

| Record | Key | From |
|---|---|---|
| workspace | id | cloud `/v1/me`, `/v1/workspaces/:id`, cloud events |
| station | workspace, id | cloud (list, presence) |
| row (sidebar item) | station, id | station `/chats`, `chat`/`chat-removed` events |
| session | station, key | `/sessions`, `/sessions/:key`, `session` events |
| thread | station, id | `/threads`, `thread` events |
| entry | station, thread, n | `/threads/:id/entries`, `thread` events (append-only) |
| transcript item | station, session, n | `/sessions/:key/live` (append-only) |
| overview | station | `/overview`, `overview` events (connects, profiles, Slack bindings) |
| read position | station, thread | `read` events, `chat.read` |
| outbox message | station, thread, local id | `chat.send` (until its entry comes) |

Each record carries when it was last confirmed by its source. Nothing is
derived and stored: views (chats, chat, stations, …) are computed from records.

## How data moves

- **In**: every reply and event is written as records, never straight into a
  topic. One write path per source (cloud, station events, station reads).
- **Out**: a write marks the records it changed; the views that read them are
  recomputed and their deltas pushed (the store's existing coalescing window).
  The UI is never told "loading" for data the database has; a view carries
  `syncing` while its sources are being read, so a UI may show that, not wait.
- **Sync**: while a workspace is open the core brings it up to date in the
  background, newest first: rows, sessions and threads of each station, then
  each chat's latest page (and what came after what it has), then older pages
  on demand. Events keep it current. No polling.
- **Startup**: views are answered from the database at once, before any
  network; offline, they stay as last seen.

## Storage

The records live in the host's storage through one engine in the core, so all
three clients behave the same:

- **Option A — SQLite** (rusqlite natively; on the web sqlite-wasm). The web
  core runs in a SharedWorker, where OPFS's synchronous handles are not
  available; sqlite-wasm would sit on IndexedDB there (slower) or the core
  moves to a dedicated worker.
- **Option B — records over the host's key–value storage** (what `kept.rs`
  does now: IndexedDB on the web, files natively), with the indexes the views
  need held in memory and rebuilt at start. No new dependency; queries are the
  few the views make.

Recommended: B, extending what `kept.rs` already does, with a size cap and
least-recently-opened eviction for entries and transcripts (metadata is small
and always kept).

## Order of work

1. Records and the write path for rows, sessions, threads, overview (small,
   always kept); views read them. Startup from the database.
2. Entries and transcripts move from `kept.rs` into records (same chunking).
3. Background sync per open workspace (the current `warm` becomes part of it).
4. Tests: views from a database with no network; events updating records;
   eviction.
