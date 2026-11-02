# Station storage and change notifications

Two rules shape this:

- **One place for every message.** Whatever is said in a conversation — by a
  person on Slack or on still.fail's page, or by an agent — is one entry in its
  thread's log, and entries are only ever appended (an edit is an entry of its
  own; nothing said is taken back — still.fail has no delete). Clients read "the
  entries after n", never the whole thing again, and keep what they read.
- **No polling inside still.fail.** A station tells its clients what changed; still.fail
  cloud tells devices what changed; the client core refetches nothing on a
  timer. The only timers left sample things that cannot notify (host load,
  provider quotas while someone looks, idle-process eviction deadlines).

## Words

- **Session**: one agent — one runtime conversation (a Claude Code or Codex
  session) with its profile, model, workspace directory and turns.
- **Thread**: a place people talk: a Slack thread, or a chat on still.fail's page.
  A thread has any number of sessions taking part (a single-session connect's
  session takes part in many threads; a chat on still.fail's page may have several
  agents) and any number of people.
- **Message**: something said in a thread, by a person, an agent (a session),
  or still.fail itself (a notice).

## Tables (stillfail.db, schema v12)

```sql
-- One agent. What it runs on and where; people and messages live in threads.
CREATE TABLE sessions (
  key TEXT PRIMARY KEY,
  connect TEXT NOT NULL,              -- the connect that started it ("ember" for the page)
  scope TEXT NOT NULL,                -- thread | all
  title TEXT,
  created_by TEXT,                    -- "slack:<connect>:<user>", an email, "local"
  runtime TEXT NOT NULL, profile TEXT NOT NULL,
  profile_pinned INTEGER NOT NULL DEFAULT 0,  -- kept to profile by hand; else the station picks one at each start
  model TEXT, effort TEXT,
  runtime_session_id TEXT,
  workspace TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  running INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  last_active_at INTEGER NOT NULL,
  archived_at INTEGER,                -- hidden from lists; deleted sessions are gone entirely
  archived_by TEXT,                   -- manual | auto (the station, after it idled)
  shown_at INTEGER,                   -- last shown again by hand: the idle clock starts over
  cwd TEXT                            -- where its runtime runs when not the workspace (a session continued from outside ember)
);

-- A place people talk. Ids are never used again (AUTOINCREMENT), so what a client keeps of a thread stays true.
CREATE TABLE threads (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  surface TEXT NOT NULL,              -- "slack:<team id>" ("slack:<connect id>" while unknown) | "ember"
  channel TEXT NOT NULL,              -- Slack channel id; "EMBER" on the page
  thread_ts TEXT NOT NULL,
  title TEXT,
  created_by TEXT,
  created_at INTEGER NOT NULL,
  archived_at INTEGER,                -- a station before wrote its entries out to its archive file (see Archiving)
  home TEXT,                          -- a page chat made for a session (its first there): archived and shown with it
  hidden_at INTEGER, hidden_by TEXT,  -- a chat archived from lists: with its home session, or alone
  shown_at INTEGER,                   -- as a session's shown_at
  UNIQUE (surface, channel, thread_ts)
);

-- Which sessions take part in a thread, and through which connect each posts there.
CREATE TABLE thread_sessions (
  thread INTEGER NOT NULL,
  session TEXT NOT NULL,
  connect TEXT NOT NULL,
  joined_at INTEGER NOT NULL,
  PRIMARY KEY (thread, session)
);

-- Everything said: each thread a log, appended to and never changed.
CREATE TABLE entries (
  thread INTEGER NOT NULL,
  n INTEGER NOT NULL,                 -- 1, 2, 3 … within the thread, no gaps
  kind TEXT NOT NULL,                 -- message | edit
  target INTEGER,                     -- edit: the n of the message it changes
  ts TEXT,                            -- message: the platform's id (Slack ts), unique per thread
  author_kind TEXT NOT NULL,          -- person | agent | ember (edit: the message's)
  author TEXT NOT NULL,
  text TEXT,                          -- message and edit: Markdown
  attachments TEXT, quotes TEXT,      -- message and edit: JSON (an edit gives the message's whole new version)
  declared TEXT,                      -- message: an agent's final | block
  at INTEGER NOT NULL,
  client TEXT,                        -- message: the still.fail app a person sent it from (added in place)
  profile TEXT,                       -- message: for still.fail's notice about a profile (its sign-in failed), its id (added in place)
  PRIMARY KEY (thread, n)
);
CREATE UNIQUE INDEX entries_ts ON entries (thread, ts) WHERE ts IS NOT NULL;
CREATE INDEX entries_target ON entries (thread, target) WHERE target IS NOT NULL;
-- Each message as it reads now (its latest edit's words, files and quotes), for the station's
-- own reading: delivery, chat_history, lists.
CREATE VIEW merged AS …;

-- Which messages a session still has to read. Person messages go to every session in the thread.
CREATE TABLE deliveries (
  thread INTEGER NOT NULL,
  n INTEGER NOT NULL,                 -- the message's entry
  session TEXT NOT NULL,
  delivered_at INTEGER,               -- null while pending
  PRIMARY KEY (thread, n, session)
);
CREATE INDEX deliveries_pending ON deliveries (session) WHERE delivered_at IS NULL;

-- How far each person has read each thread.
CREATE TABLE reads (
  viewer TEXT NOT NULL,               -- email, or "local"
  thread INTEGER NOT NULL,
  n INTEGER NOT NULL,                 -- an entry number
  at INTEGER NOT NULL,
  PRIMARY KEY (viewer, thread)
);

-- The Slack users each viewer said are them ("这是我" on a Slack user's name). Not verified: the viewer's word.
CREATE TABLE identities (
  viewer TEXT NOT NULL,               -- email, or "local"
  slack_user TEXT NOT NULL,           -- a Slack user id
  at INTEGER NOT NULL,
  PRIMARY KEY (viewer, slack_user)
);

-- The last check and quota of each profile, so a restart shows them at once.
CREATE TABLE profile_status (
  profile TEXT PRIMARY KEY,
  check_json TEXT, checked_at INTEGER,
  quota_json TEXT, quota_at INTEGER
);

-- also: turns, bindings, processes, jobs, job_notices
```

A database of another schema version is refused (the station says to move
its data by hand); no migrations are kept in the code (`station/src/store/schema.ts`).
The archive and hide columns (`archived_by`, `shown_at`, `cwd`, `home`,
`hidden_*`) are added in place when missing.

### Writing

- **Slack message in**: upsert its thread, append the message (a duplicate
  `(thread, ts)` is the same message seen twice — ignored), add a delivery
  for each session in the thread (creating the session and its
  `thread_sessions` row first when the message starts one), then ack Slack.
  Several connects in one channel share the thread row and its messages;
  whichever sees a message first delivers it to every session in the thread,
  and a later connect only brings in its own session.
- **Joining mid-thread**: when still.fail starts following a Slack thread at a
  reply, what Slack has before that reply is recorded first (no deliveries),
  so the thread is complete and its log keeps Slack's order.
- **Person on still.fail's page**: the same, with surface `ember`; quotes and
  attachments are columns, and the text the agent reads (quotes as Zork
  writes them, file paths) is made at delivery, not stored.
- **Agent posts** (`chat_post`): the surface posts it, returns its ts, and the
  message is recorded with `author_kind = agent`, `author = session key`,
  `declared`. Slack posts are recorded too — the thread on still.fail's page is
  complete. A message Slack takes in several parts is recorded once, under
  the first part's ts. Agents' messages are not delivered to other sessions;
  still.fail's own notices are recorded as `author_kind = ember`.
- **Question cards**: a person's first message after the latest card ends its
  wait, whether it is an answer or a clarification; a newer card replaces it.
  At delivery, the station identifies the card that stopped waiting and any
  newer card still pending, using entry order (not message timestamps).
  `chat_history` reports each card and its current state. An agent cannot point
  `need_human` at an inactive question: it must ask again if a decision remains.
- **`-stop`** is recorded like any message and stops each session it is
  delivered to instead of reaching the agent; so are **`-compact`** (its
  context compacted between turns) and **`-clear`** (its context cleared: no
  `runtime_session_id` until its next turn starts a new runtime session, the
  ones before kept in `runtime_sessions` for its history).
- **Slack edits** (`message_changed`, found by the thread Slack names —
  `thread_ts`, or the message's own ts outside a thread) append an `edit`
  (the message's new words, its files and quotes as they were). An "edit"
  with the same words — Slack sends those for thread roots as replies come —
  changes nothing. A message still pending reaches the agent as it reads at
  delivery (merged).
- **Slack deletes** (`message_deleted`) are ignored: still.fail has no
  retraction, and the message stays as it was said.
- Every entry takes its thread's next n in the same transaction.

### Reading

- `GET /threads?session=…` / the thread list of a session (all threads
  without `session`), `GET /threads/:id`: threads with their sessions, their
  people (everyone who wrote in it, earliest first), the first thing a person
  said (`firstText`, for a chat's title), `last` (the last entry's n) and
  `lastMessage` (the latest message as merged, for lists), and the viewer's
  read position and unread count (messages after it that are not the
  viewer's own — in a Slack thread, not of a Slack user the viewer is); the
  latest said first. The store's `last_message(thread)`,
  `unread_count(viewer, thread)` and `read_position(viewer, thread)` give these
  for anything else that lists threads (the sidebar's items do).
- `GET /threads/:id/entries?after=n` — what came since; `?before=n&limit=`
  — older pages (no cursor: the latest page, 50 unless `limit`, at most
  500); `?from=a&to=b` — a gap, both ends included. The answer is
  `{ last, entries }`. Entries carry `authorName` (the author in words as the
  station knows them when read).
- `PUT /threads/:id/read {n}` — the viewer's read position; it only moves
  forward, and the answer says where it is.
- `POST /threads/:id/messages {text, attachments, quotes, client?}` — a person's
  message in a still.fail chat (Slack threads are written in Slack), answered
  with its `{ n }`; `client` is the app it was sent from ("android 0.1.1123"),
  kept for the chat's agent (`client="…"` on its message) and not shown; `cc: [thread id…]` copies it, after the answer, to those of the chat's Slack and Feishu threads ([relay.md](relay.md) "抄送"); attachments must be uploads of a session in the thread
  (`POST /sessions/:key/files`). `POST /threads {session, title?}` opens
  another chat on a session; `POST /threads/:id/sessions {session}` brings
  another session into a still.fail chat. `POST /sessions` (a new chat) makes the
  session and its chat and answers `{ key, thread }`. A `clientKey` given
  (the key the asking client shows the chat by until it is made) is said by
  the chat's sidebar item for ten minutes (in memory only): its `chat` event
  can reach the client before the answer does.
- A session at work is followed by the station itself, from when its
  `running` goes on until two minutes after it goes off (`sessions/live.ts`
  `running`, `HELD_AFTER_MS`): its steps and its transcript's entries as they
  are written go to every `/events?running=1` stream whose viewer sees it, and
  such a stream is told as it opens where each stands (no entry of before).
  How many entries each transcript has is kept as it is read
  (`transcript_lengths`), and its session's summary says it
  (`transcriptLength`). So is what its calls used (`session_usage`, the
  summary's `usage`), and what its stream tells of them: both as the usage
  counter recorded them (`usage`, the one record of what was spent; the usage
  page adds up the same rows), never counted from the transcript apart. What
  the transcript of a session at work gains, the counter is asked to read for
  that session alone a moment later (`usage/counter.ts` `soon`), so the count
  goes on with each call. The calls are read from `usage_totals`, which the
  database keeps added up per session, runtime, model and speed as calls are
  recorded (triggers on `usage`, each row the `calls` it is: a runtime that
  tells a turn's counts at once says how many it made): a few rows each time it
  is told, not every call the session made; the model, the context it carries
  on with and the model's window are those of its last main-thread call
  (`usage.context`, `context_window`). A change of a
  session at rest (its last turn's count comes in after it ended) is told as
  the session's; one at work is on its stream. A client from before follows a session by name, on
  `/events?live=<key>&from=N&last=200` (entries from index N, no more than the
  last 200 — and the usage so far, even when N is all of them — then as they are
  written; a watcher asking past the end is told where it ends). The rest comes
  from `GET /sessions/:key/timeline`: `?before=&limit=` (a page before),
  `?after=&limit=` (what comes after an entry), `?from=&to=` (a stretch), each
  answer saying how many entries there are (`end`). The live view reads none
  of a transcript's past on the main thread: a session it starts to watch goes
  on from where the reader that keeps its history stands (the `transcriptState`
  read: offsets, counts and what a read keeps between lines, `read/tail.ts`
  `snapshot`), counting what came before without keeping it, and a listener
  that lacks some of it is given it from there (what is said meanwhile told
  after). A transcript is read once (`read/transcripts.ts`): as a reader reads
  it, it marks where every 256th entry starts (its byte offset, with what
  reading keeps between lines there; or every 8 MB with an entry), and keeps
  where its reading stands and its marks on disk
  (`<data>/transcript-marks/<sha1 of its path>.json`, removed with its session),
  so a reader that starts again (one goes after a minute idle, all of them at
  every start of the station) reads on from there, not from the transcript's
  start, and a page or a stretch, whole or in brief, is read from the mark
  before it: no more than 256 entries or 8 MB before what was asked. An entry's
  index is what reading counted, kept across starts; what is kept says the way
  lines were read (`READING`, `read/transcript.ts`), and kept another way it is
  read anew. The pool sends a session's reads to the reader that read it last,
  which keeps it in memory. A transcript is read 4 MB at a time
  (`read/tail.ts`), never as one buffer. With `brief=1` on either, entries come
  in brief, as an execution history shows them before a
  step is opened (`read/transcript.ts` `brief`, marked `brief: true`): a call
  longer than 600 characters by the fields of its input that say what it does
  (`description`, `command`, `file_path`, … each at most 300; posts, states
  and Slack calls whole), a result without what it gave (Slack's answer kept to
  `ok` and `ts`), a thought by its first line. `?from=a&to=b` reads entries a
  to b (both included, at most 1000), whole as such a step is opened, in brief
  with `brief=1` (a stretch a stream left out).
- `GET /chats` — the viewer's sidebar items (The sidebar, below).
- `POST /batch {gets}` — several reads in one: each path (with its query) is
  answered as its GET is, and the answer is `{ answers: [{ status, body }] }`
  in their order, compressed as one and harder than other answers (zstd level
  9: nobody waits on it). Only the reads a client brings a
  station's history onto its device with: a thread's entries, a thread, a
  session, a session's timeline (any other is `400`); at most 64, four at a
  time. It only reads: a read-only member may ask it.
- `POST /changed/chats`, `/changed/threads`, `/changed/sessions` (each with
  its GET's query) `{ held }` — what changed of the list since what the
  client holds: `held` is each held row's digest by its id (a session's
  `key`), the digest the row's JSON with its keys sorted, hashed (cyrb53, 53
  bits, base 36: read/digest.ts; the core's digest.ts is the same, both
  tested on the same values). The answer is `{ order, rows }`: the list's
  ids in order, and the rows whose digest differs or that are not held. A
  client whose stream could not be resumed reads its lists so; it only
  reads, and a read-only member may ask it.
- `PUT /me/slack/:user` / `DELETE /me/slack/:user` — the viewer says a Slack
  user is them ("这是我"), or no longer ("不是我"); nothing checks it. The
  answer is the overview, whose `slackUsers` lists the viewer's Slack users.
- `GET /sessions/:key` is the session row, its threads, and its turns — no
  entries, no transcript. `GET /sessions` lists shown sessions;
  `?archived=1` lists the archived ones.

### The sidebar

A chat is still.fail's own internal chat (a thread on surface `ember`), bound to
one or more sessions, with people. A Slack thread is Slack's conversation,
not a chat: its messages show only in its agent's execution history. The
sidebar has one kind of item, merged here at the source: an agent (a shown
session) with its internal chat. An agent in an internal chat is that chat's
item (a chat with several agents is one item); an agent with none yet is an
item without a chat, whose chat is made (`POST /threads {session}`) with its
first message — none is made ahead. Every item opens the same page. An
archived session is in no item; a chat whose sessions are all archived is
not listed. The station puts the items together for whoever asks, since
unread marks and who takes part are the viewer's:

```jsonc
{
  "id": "7",                      // where its page is: its chat's thread id, or its session's key while it has no chat
  "session": "ds:C1:1790000000.000100",  // its agent (a chat's first)
  "thread": 7,                    // its internal chat; null until the first message makes it
  "title": "部署挂了",
  "agents": [{ "key", "runtime", "model", "effort", "process", "pending", "lastTurn" }],  // its shown sessions
  "last": { "seq", "authorKind", "author", "authorName", "text", "createdAt" } | null,
  //   the chat's latest message as merged (the store's lastMessage; seq is its entry n), its text cut to 200
  //   characters; null without a chat
  "unread": true,                 // messages after the viewer's read position that are not their own (the store's unreadCount)
  "mine": true,
  "lastActiveAt": 1790000000000,  // the latest message's time, else the chat's; without a chat: the session's
  "connect": "ds" | null,         // the connect its agent came from; null for one made on ember
  "origin": { "teamName": "Acme", "channel": "C1", "channelName": "ops", "threadTs": "…" } | null
}
```

A Slack thread lends its agent's item three things and nothing else: the
title (only while the chat has no words of its own), the connect, and the
origin (the web's connect icon's tip: `Slack · <workspace> · #channel`, or
`私信` for a direct message). An agent's Slack thread is the latest one it is
in; a chat's is that of the first of its sessions that has one.

- **title**: the name people gave the chat, else the one its agent gave it;
  with neither, its Slack thread's (that thread's name, else the first line of
  the first thing a person said in it, Slack mentions left out and spaces
  collapsed, then `#channel`, `私信`); else `新对话`, the same until it is named
  (not the words said in it as they come in). Without a chat: the session's
  title, else its Slack thread's, else `新对话`.
- **mine**: a chat the viewer started, wrote in, or is among the people of;
  without a chat, the viewer started the session or is among the people of
  its Slack thread. A person is the viewer by id (an email, or `local`), by
  email (a Slack user's, case aside), or as a Slack user the viewer said is
  them (`identities`) — who also count as the viewer for unread.

`GET /events` sends the viewer's items as they change: when anything they are
made of changes (sessions, entries, memberships, read positions, the
viewer's Slack users, connects), the station reads the items again, once per
viewer for a burst, and tells each stream what differs from the items it last
told it: `chat` with the whole item when one is new or changed,
`chat-removed {id}` when one is gone (an agent's item moves from its session's
key to its chat's id when the chat is made). The items a stream starts from
are those at the moment it opened.

### Housekeeping

- A working chat's own workspace is measured on this station and, where it has run tasks, on each target station.
  The soft limit is 10 GiB per chat per station. Above it the agent is told the path, size and limit, and is asked to
  clean what it may or set a new whole-GiB limit with `workspace_limit {station?, limit_gib}`. It is reminded hourly
  while still over; a completed or archived chat is not woken for this. The limit and last notice survive a station
  restart. No files or work are stopped by this watch. A scan is queued off the station thread, one at a time; it counts
  allocated blocks, not following symbolic links and counting hard links once. Once it has counted more than the limit it
  stops and reports a lower bound. Measurements are refreshed every five minutes, so changes to files or limits are
  reflected after another scan completes. APFS clones can share blocks and are not deduplicated. A custom project outside
  the station's own session directories is not traversed. Older or offline target stations are skipped until they can
  answer; the next scan tries again.
- `POST /sessions/:key/archive` / `DELETE /sessions/:key/archive`: hide and
  show (and archive its threads, below); the answer is the session summary.
  `POST|DELETE /threads/:id/archive` does the same for a chat (with its
  session when it is that session's own chat). The station also archives
  what has idled past `auto_archive_ms` and is done (`Hub::auto_archive`,
  hourly); anything new said brings it back.
- An archived, idle session's own directory goes to cold storage
  (`sessions/cold.ts`): what a build makes again is removed, the rest of its
  workspace is packed into `workspace.tar.zst` beside it, and the transcripts
  the station keeps are compressed; all of it is restored before its runtime
  starts again. Once it has been archived for `archivedWorkspaceDays` (7 by
  default; 0 keeps them), the station empties its workspace
  (`expireArchived`, looked at when the next one comes due and hourly): the
  files sent in its chat (`uploads/`) are taken out of the archive onto the
  disk, the archive and everything else in the workspace are removed, and the
  git worktrees it locked are let go. Its transcripts and its threads stay, so
  it goes on in its history, in an empty workspace. With less than 20 GiB free
  on the disk of the station's data (`ops/disk.ts`, looked at every five
  minutes), once the mirrors of other stations' tasks not in use have gone,
  archived workspaces are emptied the same way before their time, the longest
  archived first, until there is that much again (`relieveArchived`); none
  with `archivedWorkspaceDays` 0.
- `DELETE /sessions/:key`: ends its process, deletes its rows (turns,
  deliveries, thread_sessions; threads left with no session, with their
  entries or archive files, and reads), its workspace directory and the Rust
  station's copy of its transcript. The runtime's own transcript file is left alone (it is in
  the profile's home, which may be a person's own). `thread-removed` tells
  clients about each thread that went.

## Append-only threads

A thread is a log: entries are appended and never changed, so whatever a
client has fetched stays true forever and can be kept on the device. Changes
are new entries the client merges. The only way entries disappear is with
their whole thread (deleting a session removes threads left without one):
`thread-removed {id}` tells clients to drop what they keep of it.

### Archiving

A thread out of every list (archived itself, or every session of it archived)
keeps its entries in the database, as one in a list does: entries are small
(all of ccvm's 26,000 come to some 20 MB), and every list reads what it shows
of every thread by an index, some 10 ms for all of a station's (2026-10-25).

Stations before wrote such a thread's entries out to
`<data>/archive/threads/<id>.jsonl.zst` (one entry per line, zstd) in one step
with deleting their rows, and marked the thread row (`archived_at`). Then every
list of chats, sessions and threads read each archived thread's file (some 850
on ccvm), decompressed again whenever a reader had let go of what it kept of
them. Those files are read as they are (the same API and summaries, answered
from the decompressed entries; what lists show of each read from its file once
a reader and kept by the file as it is) until the station brings each back
into the database: a few at a time, two minutes after it starts
(`Store.bringInArchived`, 20 a second), and at once when one is said in (an
edit too) or a session of it is shown again. Since entries never change, they
are the same either way, and clients' kept copies stay valid. Bringing one back
writes its entries into the database first and removes the file.

An archived, idle session's transcripts are packed in place (cold storage,
under Housekeeping). The Rust station instead wrote a copy of them,
`<data>/archive/transcripts/<session>.jsonl.zst`, and left them as they were,
so both stayed on the disk (1.4 GB on ccvm); a station packs those sessions'
transcripts and lets go of the copy three minutes after it starts
(`ColdRooms.finishLegacyCopies`, their workspaces left as they are). Nothing
reads the copies; showing the session again or deleting it removes one too.

### In the client core

Merging happens in one place (`client/core-ts/src/entries.ts`, used by the
`chat` view): a message shows its latest edit's text, attachments and quotes,
marked edited (`editedAt`). Unread and read positions are entry numbers.

The client core keeps entries on the device, through `Host` storage (IndexedDB
on the web, files natively) in chunks — `thread/<station>/<thread>/<chunk>`
holding entries `chunk*256+1 … chunk*256+256`, plus
`thread/<station>/<thread>/meta` (`{ first, last }` it holds, one run, and the
thread's summary as last seen, so the chat opens before the station's thread
list is read). Opening a chat shows its latest page of what is kept at once,
then asks for `after=last`; scrolling up reads kept chunks before asking the
station (whose answer is kept too). The `thread` event carries the new entries,
always contiguous: a client whose last n is below the first one it receives
asks for the gap (`from`/`to`) once, and places what comes meanwhile after it.
A session's transcript is append-only too (its entries are indexed from 0 in
`/sessions/:key/live?from=N`) and is kept the same way under
`transcript/<station>/<session>/<chunk>` (a transcript written anew and
shorter is cut there too). Storage cannot list its keys, so `kept` indexes
every kept log with its chunks' sizes and when it was last opened; past 50 MB
the least recently opened go first. Kept data is dropped for a station the
account can no longer reach (a workspace no signed-in account lists — decided
once every account's `/v1/me` has answered — or a station its workspace no
longer lists), on sign-out (what no remaining account reaches), with
`thread-removed`, and with `session-removed` (its transcript).

## Notifications

### Station → clients: `GET /events`

One event stream per client. Each event names what changed and carries it
when it is small:

| event | data |
| --- | --- |
| `session` | the session summary (row, state warm/cold/running, last turn, creator, participants) |
| `session-removed` | `{ key }` |
| `thread` | `{ id, entries: [appended entries, contiguous] }`; `entries: []` when its sessions changed |
| `thread-view` | after a `thread` with entries, the thread as `GET /threads/:id` has it for the viewer (their read position and unread count; only to that viewer and language): a client puts it in place rather than read it |
| `thread-removed` | `{ id }`: it went with every entry (a deleted session took it along) |
| `read` | `{ viewer, thread, n }` (only to that viewer) |
| `chat` | an item of the viewer's sidebar, new or changed (only to that viewer) |
| `chat-removed` | `{ id }`: an item gone from the viewer's sidebar |
| `overview` | the whole overview, with the viewer and their Slack users (`slackUsers`) — sent when config, connect status, logins, profile checks, quotas, ember-mesh's state, recorded runtime processes, the running/warm counts or a viewer's Slack users change |
| `host` | host info; sampled every 10 s **only while some client asks for it** (`/events?host=1`) and sent when it changed |

Changes within one turn of the event loop are gathered: one `session` event
per session, one `overview`, one round of sidebar items. Per-session live steps stay on
`/sessions/:key/live`.

Each event has an `id:` of the station's run and its number in it
(`<run>.<n>`; one number for an event told to everyone, whichever streams
it went to). What is told is kept an hour (at most 20,000 events and 8 MB),
so a client's stream that takes over from another (the client opens a new one
whenever what it follows changes, and lets the old one go once the new one is
open), or comes back after its link went, asks `/events?since=<the last id it
heard>` and is told first what came after it, as it was, then its viewer's
sidebar rows and overview where they changed meanwhile, and the answer says
`stillfail-resumed: 1` (the client reads nothing again); or `missed` (`{}`)
when that is not all kept, or was another run's, and the client reads the
station again. So that one coming back misses nothing, what is told is still
made and kept for an hour after the last stream went; past that, nothing
before can be resumed. A viewer's sidebar rows and overview are told against
what their streams were told last (one telling, in each language, for all
their streams, kept like the rest); a stream that starts afresh reads their
sidebar before it answers, and is what their changes are told against from
then on.

A run is not one process: a station process that stops (a handover at an
update, or a stop before the next start) writes what it keeps — the run, its
numbers, the events kept, what each viewer's streams were told of their
sidebar and overview, who followed last — and its pid to `run/events.json`
(whole: a temporary file renamed), after the last it tells; keeping nothing
(nobody followed for an hour), it removes any file there. The next process
answers no stream before the one before it is gone; then it takes the file up
and removes it, and goes on with the same run and numbers, making and keeping
what it tells from then on as while nobody follows. What it was to tell before
(a read mark, a message, a vault's request, while the one before still
stopped) waits, and is told then, numbered on from what it took up. A stream
that comes back to it is resumed as the old process would have resumed it. A
crash leaves no file; a file older than an hour, one that does not read, or
one by another process than the one `run/hub.json` named as it started (one
that a process before it stopped waiting for after 40 s, written once that
process had begun a run of its own) is not taken up but removed: a run of its
own, and `missed`. (On ccvm, updated 32 times on 2026-10-24, every stream was told
`missed` at each update, and every device read the whole station at once
while the new process was starting.)

Over the mesh, an answer is compressed for a client that asks
(`accept-encoding: zstd`; station/src/mesh/compress.ts): JSON and text from
512 bytes, zstd at its fast level, an event stream flushed after each event
(each comes out whole as it arrives) and compressed against the last
megabyte of it, so what a stream tells again (a session's summary, a sidebar
row, the overview) is a few bytes the next time: of a real station's stream
7% of it, where deflate, looking back 32 KB only, left 24%. Nothing of a
preview (its page reads what the service sent), and no `content-length` then.
A client from before asks nothing and gets every answer as it is.

Timers that remain on the station and why: host sampling (above), quota
refresh every five minutes while some `/events` stream is open (the provider
cannot notify), an idle process's eviction deadline (a timer per process, set
when it goes idle, instead of a sweep every minute), Slack reconnect and
rate-limit backoff, a keepalive comment on open
event streams every 25 s (proxies close silent ones), a 40 ms coalescing of
transcript writes for live watchers, a sign-in's 15-minute deadline, the
profile checks a few seconds after start, the auto-archive (when the next chat
comes due, at most ten minutes apart), and a look
at `mesh/cloud.json` every 2 s (enrollment and renames; `MeshFile`).

### still.fail cloud → devices: `GET /v1/events` (WebSocket)

A device keeps one WebSocket per account to the directory (hibernatable, so
idle sockets cost nothing).

- **Auth**: browsers cannot set headers on a WebSocket, so the access token
  travels as a subprotocol: `new WebSocket(url, ["ember-events",
  "ember-token." + accessToken])`; the answer selects `ember-events`. (A
  header keeps it out of URLs and so out of request logs; query strings are
  not accepted.) The token is checked at connect only: it may expire while
  the socket stays open, since events name what changed and carry nothing a
  device may not see — it refetches with a fresh token. A refused socket gets
  401 before the upgrade; a device reconnects with a fresh token.
- **Keepalive**: the device may send the text `ping`; the runtime answers
  `pong` without waking the directory.
- **Events** (JSON text frames), each to exactly the accounts it concerns:

| event | when | to |
| --- | --- | --- |
| `{"type":"workspaces"}` | the account's workspace list or its invitations changed (a workspace created, renamed, deleted, joined or left; a role; member or station counts; an invitation to it arrived, went, or its inviter's name changed) | that account |
| `{"type":"workspace","id"}` | the workspace view changed: members, roles, stations, names, invitations (the managers' list) | its members, and a member who just left or was removed |

A device refetches `/v1/me` on `workspaces` and `/v1/workspaces/:id` on
`workspace`; `station` is complete in itself. Nothing is replayed: after a
reconnect the device refetches what it shows.

### Station control channel: `GET /v1/stations/connect` (WebSocket)

The station keeps a WebSocket open to still.fail cloud for what still.fail cloud has to
tell it: its name and workspace, the keys member credentials are signed with,
revocations, and its removal. It is not presence: whether a station is up,
each device finds out by connecting to it (the client core's `link`), and a
station works without this socket (devices keep their credentials).
`last_seen` is when it last connected or disconnected.

- **Auth**: signed with the station's key at connect, in headers:
  `x-ember-station` (its key, hex), `x-ember-ts` (unix seconds, within 5
  minutes), `x-ember-signature` (hex Ed25519 over
  `ember-station-connect-v1:<origin>:<station>:<ts>`), and `x-ember-version`.
  A station that is not enrolled gets 404 and refuses clients until it is.
- **From the cloud**: `{"type":"state","workspace","workspace_name","name","grant_keys","revocations"}`
  on connect and whenever these change (renamed, moved by re-enrolling), with
  the last 31 days' revocations (`{kind: "sub"|"sid", id, at}`: credentials of
  that account or login session issued at or before `at` are refused); and
  `{"type":"revoke", …}` as one happens.
  Close codes: 4000 replaced by a newer socket of the same station, 4004
  removed from its workspace, 4008 silent.
- **Liveness**: the station sends `ping` every 30 s and the runtime answers
  `pong` without waking the directory; a station that gets no `pong` before
  its next ping reconnects. While any station is connected, an alarm every
  90 s drops station sockets unanswered for 90 s (a station that vanished
  without closing).
- The station reconnects with backoff (1 s doubling to a minute; back to 1 s
  after a socket held a minute). A reconnect replaces the old socket without
  an offline in between.

### The client core

Holds one `/events` stream per station in use and one `/v1/events` socket per
account; topics change only when these say so. `REFRESH_MS`,
`OVERVIEW_REFRESH_MS` and `HOST_REFRESH_MS` go. A write's answer updates the
topic it returns (e.g. a profile edit returns the overview), and a call
returns only after the topics it touches are current, so a page that
navigates right after a write finds what it wrote.
