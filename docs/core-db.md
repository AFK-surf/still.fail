# The core's database

Status: built (2026-10-04, branch `core-ts`). The TS core (docs/core-ts.md) keeps everything it reads in **one SQLite
database per signed-in account**: `client/core-ts/src/db/schema.ts` (tables, migrations), `src/db/account.ts` (one
account's database: its writer, reads, caches), `src/data.ts` (which database keeps what, the device's own values),
`src/db/import.ts` (what the device kept before, brought over once).

## Why

The core used to keep a generic key → JSON-blob store under a cache: every table but entries and transcripts was
loaded whole into memory at start, lists were blobs of ids rewritten on every event, several cores could write it
(the web without SharedWorker), it was shared by every account although some of it is the viewer's own (read
positions, unread, drafts), and it had no versions. Patching that was not the way (「太打补丁了」): this is one design
instead.

## The model

- **A database per signed-in account**, on every platform; signing out removes it. What is a station's or a
  workspace's is kept in the database of the account that reaches the workspace (`Workspaces.owner`: the first
  account in sign-in order whose `/v1/me` lists it), so workspaces are apart by construction and what is the
  viewer's (read positions, unread, pins, drafts, the outbox) is the account's. Its name is `account-<sub>` (what a
  file name cannot hold as `_xx`, `dbName` in data.ts).
- **The device's own values stay in the host's small storage**: the accounts list and tokens, the device key,
  preferences (`device/prefs`), the changelog seen (`device/changelog`), a new chat's picks and chat links that are
  not a workspace's (`device/choice`, `device/chat_ref`), the links' last state (`link/<station>`), push
  registration. Read at start (data.ts `Device`), written by one fiber.
- **Real tables are the data model** (schema.ts). Each keeps the station's payload of a row as JSON (`json`), passed
  through as it came, so a field a station adds needs no migration; next to it typed key columns, the columns views
  find and sort rows by, with indexes for them, and the fields that change often on their own as columns only,
  updated in place:

| Table | Key | Columns besides the payload | From |
|---|---|---|---|
| `account_doc` | name (`me`, `login_sessions`, `admin/<list>`) | confirmed | cloud `/v1/me`, `/v1/auth/sessions`, `/v1/admin/*` |
| `workspace` | id | confirmed | `/v1/workspaces/:id`, cloud events |
| `station` | address, kind (`overview`, `footprint`, `usage`) | confirmed | `/overview`, `/footprint`, `/usage`, events |
| `slack_app` | station, connect | confirmed | `/connects/:id/slack-app` |
| `list` | station, list (`chats`, `archived`, `sessions`, `threads`, `jobs`) | confirmed, rev | a list read at all (an empty one is not one never read); how often a station's chats changed |
| `chat` | station, archived, id | ord, thread, session, client_key, last_active, pinned_at, unread, mine, running, tone, asks, desk | `/chats`, `/chats?archived=1`, `chat`/`chat-removed`/`read` events |
| `session` | station, key | listed, ord, last_active, process, connect, archived_at, turns; `summary`, `detail` | `/sessions`, `/sessions/:key`, `session` events |
| `thread` | station, id | listed, last, read, unread, sort_at, created_at, surface, first_member | `/threads`, `/threads/:id`, a session's detail, `thread`/`read` events |
| `thread_member` | station, session, thread | — | each thread's `sessions` |
| `entry` | station, thread, n | — | `/threads/:id/entries`, `thread` events |
| `transcript` | station, session, i | — | `/sessions/:key/timeline`, `live` |
| `job` | station, id | session, open, ord, chat | `/jobs`, `job` events, a session's detail |
| `outbox`, `pending`, `first`, `changing` | station and thread / key / session / id | — | what was done here and not confirmed yet (views/local.ts) |
| `draft` | station, chat | — | `draft.put` |
| `workspace_pref` | workspace, key | — | a workspace's new-chat picks (`choice:…`), chats' links (`links`) |
| `meta` | key | — | the account, when what came before was imported |
| `said` (+ `said_index`, FTS5 trigram) | id; station, thread, seq | n, at, text | each message's latest words, kept by triggers on `entry` (`ensureSaid`): what ⌘K's search finds |
| `log_use` | kind, station, id | opened, evicted | when a log's chat was last opened here, whether its items were let go for room (`ensureKept`) |

`said` and `log_use` are made where missing at every open, not by a migration (the version stays, so an older core
still writes the database; `said`'s triggers keep it current under it too). The room an account's database takes is
kept within `KEPT` (data.ts, 256 MB): past it, the items of the logs not shown, least recently used first (opened here,
or last active), transcripts before entries, go down to 80% of it, their words with them; a log let go is not synced
again until its chat is opened.

Indexes: `chat (archived, pinned_at DESC, last_active DESC)` (a list's first screen across stations), by thread, by
session, the rows at work (`running`), those that ask something or are unread (`tone`/`asks`), those the 奏 page
lists (`desk`); `session (station, listed, ord)`; `thread (station, listed, sort_at DESC, created_at DESC, id DESC)`
and by first member (the chat bound to an agent); `job (station, open, ord)`. `tone`, `asks` and `desk` are what only
the core can say of a row (marks.rowTone, decisions.asked, present.workingLine), computed as the row is written.

A session's detail keeps its turns and jobs as read; its threads are the thread rows it takes part in (and those its
detail named), so a thread changing changes one row, not every detail that lists it. A thread's `last`, `read`,
`unread` and a chat row's `unread` are columns: a read position moves by an `UPDATE` of them.

## Versions

`PRAGMA user_version` is the schema's version; `MIGRATIONS` in schema.ts take a database from each version to the next,
in order, each in its own transaction. A database a newer core wrote (its version past ours) is opened to be read only:
it shows what it holds, nothing is written, and the `status` topic says so (`core-logic.status.db.newer`). Adding a
table or a column is a new migration at the end, never a change to an old one.

## Writing: one writer per database

Every change goes through its account's database (`AccountDb`): it opens the burst's transaction (`BEGIN IMMEDIATE`)
if none is open and runs in it, so what is read next sees it; the database's write fiber (Effect) commits the burst
once the work at hand has run — a burst of events from a station's stream, a list read with its rows, is one
transaction. After each commit the writer tells what changed in it: the held topics whose values changed, each sidebar
row before and after (what `notices` hears), the logs that grew. The store recomputes only those topics and sends
keyed deltas (src/collections.ts, src/output.ts); a list that changed only by a row is one op.

A row that did not change is not written: a list read again compares each row's JSON (and hot columns) with what is
held and writes the ones that differ; rows keep their place (`ord`, REAL) where the new order keeps them, so a chat put
on top writes that chat alone. Events update rows in place (a session's summary, a thread's read position), never
rewrite a list.

There is one writer by construction:

- **Desktop**: the core runs in the app's one utility process (node:sqlite, `hosts/node-sql.ts`); files
  `databases/<name>.db` in the app's data directory, `locking_mode = EXCLUSIVE` and WAL: another process finds it
  busy.
- **Android**: the app's one core, SQLite in the Rust shell (`client/shell`, `sql.*` answered at once through
  `callSync`), `databases/<name>.db`, EXCLUSIVE likewise.
- **Web**: every tab has a dedicated worker (`web/src/core/worker.ts`); the one holding the Web Lock `stillfail-core`
  runs the core: its databases are SQLite's official WASM build (`@sqlite.org/sqlite-wasm`) on the `opfs-sahpool` VFS,
  whose access handles only one worker can hold, so the tab that holds them is the writer. The other tabs' workers
  relay their page's messages over a BroadcastChannel to it and what it says back (each holds a lock of its own, which
  tells the core when a tab is gone). When the tab running the core goes, its lock goes to a waiting worker, which
  starts the core from the same databases; every page subscribes again (`{rejoin: true}`; calls in flight fail as
  when a worker restarts). SQLite's module is loaded by that worker alone.

A database that cannot be opened (another process holds it) is one in memory for this run, said by `status`
(`core-logic.status.db.busy`).

**No room left**: when a commit (or a statement) fails for want of room — SQLITE_FULL, or on the web a write OPFS
refuses (the origin's quota) — the burst is rolled back, the caches dropped, and what this device did itself (the
outbox, chats asked for, first messages, changes, drafts, workspace picks) is written again on its own; if even that
cannot be, it is kept and written with the next burst (it is also held in memory, views/local.ts). The `status` topic
says so (`core-logic.status.db.full`) until a burst is written again. On the web the page asks for persistent storage
(`navigator.storage.persist()`, web/src/core/client.ts) so the browser does not evict it.

## Reading: queries

Topics read what they show by query, when they go out; nothing is loaded at start:

- A row asked for by key (a thread, a session's summary or detail, a chat row by thread or session, a job, a document)
  is read by its key and kept, frozen, until written (a cache by identity, so an unchanged row is the same object from
  one read to the next and a view's row made of it is not made again).
- A station's list a topic shows whole (`chatRows`, `archivedRows`, `sessions`, `threads`, `jobs`) is loaded by one
  indexed query the first time it is read, kept current by the writer row by row, and let go when its topic goes
  (`Store` → `Data.release`). A list a view only watches (a source of the chat list) is not read for it.
- The chat list (`chats`): while its stations' rows are not loaded and they are many (more than 500), the rows it shows
  on top are read by one query over the `chat_recent` index (80: pinned, then the latest active), and go out at once;
  the stations' rows are loaded after, a station at a time, and the whole list follows (as one op).
- The workspace marks read only the rows that ask something or are unread (`tone`/`asks`); the 奏 page only the rows
  it lists (`desk`); the station sync the rows at work (`running`).
- A chat's page reads its window of entries by range (`entry` between two `n`), a transcript its latest page; a gap is
  found from the numbers held.
- Notices hear the rows a write changed, before and after (a station's first rows are where they start from).

Startup answers the first view from the database before any network: the accounts' databases are opened, the
workspaces' owners found from each `me`, and a subscribed view is answered from the tables; the sync then reads every
station again in the background (it owns all network traffic; the UI only changes priorities, docs/core-ts.md rule 6).

## What came before: imported once

When an account's database is made, what the device kept before is brought into it once (`meta.imported`): the former
records store (the KV `records` table of `core.db` on desktop and Android, IndexedDB `stillfail-core` `records` on the
web) and, where no TS core read them before (`kept-read` absent), the Rust core's `kept` chunks. Each account takes
what is its own and what is of the workspaces it reaches, as the accounts' `/v1/me` said then; the device's values go
to the device's storage once (`device-imported`). Lists, documents, details, the outbox and drafts come first, before
the first view; threads' entries and transcripts after, in the background, a station at a time, without writing over
what the sync brought meanwhile. Nothing is taken away, so an older core still finds what it kept (a rollback works).
All of it comes over; past the room an account may take (`KEPT`, above), the least used logs go as the sync writes.

## Tests

`client/core-ts/test/data.test.ts`: a database per account at the current version, named by its account; signing out
removes it; a newer one only read and said; one held by another process in memory and said; a burst is one
transaction told once committed; a list read again writes only the rows that changed (a new one on top writes one
row); places; a list loaded when read and kept current (unchanged rows the same objects); a restart; read positions
updated in place, the rows and the session's detail following; a session's detail holding its threads as their rows
are; session events; chat rows before and after; the first screen, the marked rows; logs by range, written once,
cut; a full disk said and what was done here kept; retain; model edits; drafts; the device's values; the former
records and the Rust core's chunks imported once, each account taking its own; the first view from the database with
no network. `client/shell` (`cargo test -p stillfail-shell`) and `test/bridge.test.ts` test the shell's `sql.*`.

## Measurements

2026-10-04, studio (Mac Studio, M-series), against the core before this (1f4100b2: records loaded whole at start), on
the same dataset: one account, one workspace of 20 stations × 2 000 chats, sessions and threads, 100 000 entries
(`bench/first-view.ts seed` writes it as the former records store; the core before reads it, this one imports it
once, then the runs below are on what it imported). Offline: what shows is what the device holds. "First" is the
chat list's first value with rows, "whole" when it held all 40 000; three runs each.

| | | before | now |
|---|---|---|---|
| **Node** (`bench/first-view.ts run`) | first | 2.90–2.96 s, all 40 000 rows | **103–109 ms**, the first 80 |
| | whole | 2.98–3.03 s | 2.06–2.14 s |
| | memory at first (RSS / JS heap after GC) | 1 162–1 165 MB / 490 MB | **168 MB / 31 MB** |
| | settled, 5 s after (RSS / heap) | 1 160–1 171 MB / 404–407 MB | 770–1 010 MB / 288 MB |
| **Hermes** (`bench/hermes-host`) | first | 23.5–23.7 s, all rows | **124–135 ms**, the first 80 |
| | whole | 23.5–23.7 s | 11.0–11.1 s |
| | memory at first (RSS / Hermes heap after GC) | 716 MB / 266 MB | **35.5 MB / 2.9 MB** |
| | peak RSS | 0.92–1.31 GB | 518–533 MB |
| **Chrome** (`bench/web-first-view.mjs`) | first | 2.55–2.61 s, all rows | **154–156 ms**, the first 80 |
| | whole | 2.55–2.61 s | 1.85–1.86 s |
| | renderer RSS (page + the core's worker) | 1 314–1 514 MB | 662–663 MB |

- Hermes is React Native's 0.81.4 (its macOS build, the Android app's version) running the app's bundle on the Rust
  shell built for macOS, by `bench/hermes-host` (the Android engine without JNI; the Hermes CLI has no SQLite).
- Chrome: headless Google Chrome; a bare page starts the build's core worker and subscribes as the app does (the app's
  own page drawing 40 000 rows is another cost: with it, the build before crashed the tab once).
- The import, once, on the first start after the update: the first view at 4.9 s (Node) / 4.2 s (Chrome), all
  100 000 entries in within the run.
- Web bundle: SQLite's WASM build adds 215 KB of JS and 869 KB of wasm (65 KB + 402 KB gzipped), loaded by the tab
  running the core only; the worker grew 46 KB (12 KB gzipped). The build also emits 246 KB of the package's files
  that are never loaded (its Worker1 API and the `opfs` VFS's proxy).
