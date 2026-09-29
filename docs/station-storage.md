# Station storage and change notifications

Two rules shape this:

- **One place for every message.** Whatever is said in a conversation — by a
  person on Slack or on ember's page, or by an agent — is one entry in its
  thread's log, and entries are only ever appended (an edit is an entry of its
  own; nothing said is taken back — ember has no delete). Clients read "the
  entries after n", never the whole thing again, and keep what they read.
- **No polling inside ember.** A station tells its clients what changed; ember
  cloud tells devices what changed; the client core refetches nothing on a
  timer. The only timers left sample things that cannot notify (host load,
  provider quotas while someone looks, idle-process eviction deadlines).

## Words

- **Session**: one agent — one runtime conversation (a Claude Code or Codex
  session) with its profile, model, workspace directory and turns.
- **Thread**: a place people talk: a Slack thread, or a chat on ember's page.
  A thread has any number of sessions taking part (a single-session connect's
  session takes part in many threads; a chat on ember's page may have several
  agents) and any number of people.
- **Message**: something said in a thread, by a person, an agent (a session),
  or ember itself (a notice).

## Tables (ember.db, schema v12)

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
  archived_at INTEGER,                -- its entries are in its archive file (see Archiving)
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
its data by hand); no migrations are kept in the code (`mesh/app/src/store.rs`).
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
- **Joining mid-thread**: when ember starts following a Slack thread at a
  reply, what Slack has before that reply is recorded first (no deliveries),
  so the thread is complete and its log keeps Slack's order.
- **Person on ember's page**: the same, with surface `ember`; quotes and
  attachments are columns, and the text the agent reads (quotes as Zork
  writes them, file paths) is made at delivery, not stored.
- **Agent posts** (`chat_post`): the surface posts it, returns its ts, and the
  message is recorded with `author_kind = agent`, `author = session key`,
  `declared`. Slack posts are recorded too — the thread on ember's page is
  complete. A message Slack takes in several parts is recorded once, under
  the first part's ts. Agents' messages are not delivered to other sessions;
  ember's own notices are recorded as `author_kind = ember`.
- **`-stop`** is recorded like any message and stops each session it is
  delivered to instead of reaching the agent.
- **Slack edits** (`message_changed`, found by the thread Slack names —
  `thread_ts`, or the message's own ts outside a thread) append an `edit`
  (the message's new words, its files and quotes as they were). An "edit"
  with the same words — Slack sends those for thread roots as replies come —
  changes nothing. A message still pending reaches the agent as it reads at
  delivery (merged).
- **Slack deletes** (`message_deleted`) are ignored: ember has no
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
- `POST /threads/:id/messages {text, attachments, quotes}` — a person's
  message in an ember chat (Slack threads are written in Slack), answered
  with its `{ n }`; attachments must be uploads of a session in the thread
  (`POST /sessions/:key/files`). `POST /threads {session, title?}` opens
  another chat on a session; `POST /threads/:id/sessions {session}` brings
  another session into an ember chat. `POST /sessions` (a new chat) makes the
  session and its chat and answers `{ key, thread }`. A `clientKey` given
  (the key the asking client shows the chat by until it is made) is said by
  the chat's sidebar item for ten minutes (in memory only): its `chat` event
  can reach the client before the answer does.
- A session's transcript comes only from `/sessions/:key/live?from=N` (entries
  from index N — and the usage so far, even when N is all of them — then as
  they are written; a watcher asking past the end is told where it ends); the
  station keeps each watched transcript parsed incrementally instead of
  re-reading the file per request.
- `GET /chats` — the viewer's sidebar items (The sidebar, below).
- `PUT /me/slack/:user` / `DELETE /me/slack/:user` — the viewer says a Slack
  user is them ("这是我"), or no longer ("不是我"); nothing checks it. The
  answer is the overview, whose `slackUsers` lists the viewer's Slack users.
- `GET /sessions/:key` is the session row, its threads, and its turns — no
  entries, no transcript. `GET /sessions` lists shown sessions;
  `?archived=1` lists the archived ones.

### The sidebar

A chat is ember's own internal chat (a thread on surface `ember`), bound to
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

- **title**: the chat's title, else the first line of the first thing a person
  said in it (Slack mentions left out, spaces collapsed); with neither, its
  Slack thread's (the same, then `#channel`, `私信`); else `（还没有消息）`.
  Without a chat: the session's title, else its Slack thread's, else
  `（还没有消息）`.
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

- `POST /sessions/:key/archive` / `DELETE /sessions/:key/archive`: hide and
  show (and archive its threads, below); the answer is the session summary.
  `POST|DELETE /threads/:id/archive` does the same for a chat (with its
  session when it is that session's own chat). The station also archives
  what has idled past `auto_archive_ms` and is done (`Hub::auto_archive`,
  hourly); anything new said brings it back.
- `DELETE /sessions/:key`: ends its process, deletes its rows (turns,
  deliveries, thread_sessions; threads left with no session, with their
  entries or archive files, and reads), its workspace directory and its
  transcript copy. The runtime's own transcript file is left alone (it is in
  the profile's home, which may be a person's own). `thread-removed` tells
  clients about each thread that went.

## Append-only threads

A thread is a log: entries are appended and never changed, so whatever a
client has fetched stays true forever and can be kept on the device. Changes
are new entries the client merges. The only way entries disappear is with
their whole thread (deleting a session removes threads left without one):
`thread-removed {id}` tells clients to drop what they keep of it.

### Archiving

When a thread goes out of every list (archived itself, or every session of it
archived), its entries go to
`<data>/archive/threads/<id>.jsonl.zst` (one entry per line, zstd) in one step with deleting their rows, and
the thread row is marked archived (`archived_at`). Since entries never change,
the file is the thread as it was, and clients' kept copies stay valid.
Reading an archived thread reads the file (the same API and summaries,
answered from the decompressed entries; the last 32 threads read are kept
decompressed in memory). A new entry — someone writing in it (an edit too), or a session of it shown again — loads it back into the
database first and removes the file. Archiving a session also writes its
transcript copy, `<data>/archive/transcripts/<session>.jsonl.zst` (the
runtime's file, compressed); the runtime's own file in the profile's home is
left as it is. Showing the session again or deleting it removes the copy.

### In the client core

Merging happens in one place (`client/core/src/entries.rs`, used by the
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
| `thread-removed` | `{ id }`: it went with every entry (a deleted session took it along) |
| `read` | `{ viewer, thread, n }` (only to that viewer) |
| `chat` | an item of the viewer's sidebar, new or changed (only to that viewer) |
| `chat-removed` | `{ id }`: an item gone from the viewer's sidebar |
| `overview` | the whole overview, with the viewer and their Slack users (`slackUsers`) — sent when config, connect status, logins, profile checks, quotas, ember-mesh's state, recorded runtime processes, the running/warm counts or a viewer's Slack users change |
| `host` | host info; sampled every 10 s **only while some client asks for it** (`/events?host=1`) and sent when it changed |

Changes within one turn of the event loop are gathered: one `session` event
per session, one `overview`, one round of sidebar items. Per-session live steps stay on
`/sessions/:key/live`.

Timers that remain on the station and why: host sampling (above), quota
refresh every five minutes while some `/events` stream is open (the provider
cannot notify), an idle process's eviction deadline (a timer per process, set
when it goes idle, instead of a sweep every minute), Slack reconnect and
rate-limit backoff, a keepalive comment on open
event streams every 25 s (proxies close silent ones), a 40 ms coalescing of
transcript writes for live watchers, a sign-in's 15-minute deadline, the
profile checks a few seconds after start, the hourly auto-archive, and a look
at `mesh/cloud.json` every 2 s (enrollment and renames; `MeshFile`).

### ember cloud → devices: `GET /v1/events` (WebSocket)

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

The station keeps a WebSocket open to ember cloud for what ember cloud has to
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
