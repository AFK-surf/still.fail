# Station storage and change notifications

Two rules shape this:

- **One place for every message.** Whatever is said in a conversation — by a
  person on Slack or on ember's page, or by an agent — is one row in one
  table, with one cursor that only grows. Clients read "what changed after
  cursor N", never the whole thing again.
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

## Tables (ember.db, schema v10)

```sql
-- One agent. What it runs on and where; people and messages live in threads.
CREATE TABLE sessions (
  key TEXT PRIMARY KEY,
  connect TEXT NOT NULL,              -- the connect that started it ("ember" for the page)
  scope TEXT NOT NULL,                -- thread | all
  title TEXT,
  created_by TEXT,                    -- "slack:<connect>:<user>", an email, "local"
  runtime TEXT NOT NULL, profile TEXT NOT NULL, model TEXT, effort TEXT,
  runtime_session_id TEXT,
  workspace TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  running INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  last_active_at INTEGER NOT NULL,
  archived_at INTEGER                 -- hidden from lists; deleted sessions are gone entirely
);

-- A place people talk.
CREATE TABLE threads (
  id INTEGER PRIMARY KEY,
  surface TEXT NOT NULL,              -- "slack:<team id>" | "ember"
  channel TEXT NOT NULL,              -- Slack channel id; "EMBER" on the page
  thread_ts TEXT NOT NULL,
  title TEXT,
  created_by TEXT,
  created_at INTEGER NOT NULL,
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

-- Everything said. seq orders a thread; rev is the change cursor (global, grows on insert, edit and delete).
CREATE TABLE messages (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  rev INTEGER NOT NULL UNIQUE,
  thread INTEGER NOT NULL,
  ts TEXT NOT NULL,                   -- the platform's id (Slack ts; ember makes Slack-like ones)
  author_kind TEXT NOT NULL,          -- person | agent | ember
  author TEXT NOT NULL,               -- person: Slack user id / email / "local"; agent: session key
  text TEXT NOT NULL,                 -- as shown (Markdown)
  attachments TEXT,                   -- JSON [{name, path, size, width?, height?}]
  quotes TEXT,                        -- JSON [{author, text, comment, ts?, role?}]
  declared TEXT,                      -- an agent's final | block with this message
  created_at INTEGER NOT NULL,
  edited_at INTEGER,
  deleted_at INTEGER,                 -- text and files cleared, the row stays so cursors hold
  UNIQUE (thread, ts)
);
CREATE INDEX messages_thread_rev ON messages (thread, rev);

-- Which messages a session still has to read. Person messages go to every session in the thread.
CREATE TABLE deliveries (
  message INTEGER NOT NULL,           -- messages.seq
  session TEXT NOT NULL,
  delivered_at INTEGER,               -- null while pending
  PRIMARY KEY (message, session)
);
CREATE INDEX deliveries_pending ON deliveries (session) WHERE delivered_at IS NULL;

-- How far each person has read each thread.
CREATE TABLE reads (
  viewer TEXT NOT NULL,               -- email, or "local"
  thread INTEGER NOT NULL,
  seq INTEGER NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (viewer, thread)
);

-- The last check and quota of each profile, so a restart shows them at once.
CREATE TABLE profile_status (
  profile TEXT PRIMARY KEY,
  check_json TEXT, checked_at INTEGER,
  quota_json TEXT, quota_at INTEGER
);

-- unchanged: turns, bindings, processes
```

`chats`, `chat_messages` and `inbound` are gone: an ember chat is a thread
with surface `ember`; what a person typed there and what came from Slack are
both messages; what `inbound.status` recorded is `deliveries`. The v9 → v10
migration moves existing rows over (data only; no code keeps the old shape).

### Writing

- **Slack message in**: upsert its thread, insert the message (a duplicate
  `(thread, ts)` is the same message seen twice — ignored), add a delivery
  for each session in the thread (creating the session and its
  `thread_sessions` row first when the message starts one), then ack Slack.
- **Person on ember's page**: the same, with surface `ember`; quotes and
  attachments are columns, and the text the agent reads (quotes as Zork
  writes them, file paths) is made at delivery, not stored.
- **Agent posts** (`chat_post`): the surface posts it, returns its ts, and the
  message is recorded with `author_kind = agent`, `author = session key`,
  `declared`. Slack posts are recorded too — the thread on ember's page is
  complete.
- **Slack edits and deletes** (`message_changed`, `message_deleted`) update
  the row and bump `rev`.
- Every insert or change takes the next `rev` in the same transaction.

### Reading

- `GET /threads?session=…` / the thread list of a session: threads with their
  sessions, last message, and the viewer's unread count.
- `GET /threads/:id/messages?after=<rev>` — every message changed after that
  cursor; `?before=<seq>&limit=` pages back through history. A page opens a
  thread with the last page and follows `after`.
- `PUT /threads/:id/read {seq}` — the viewer's read position.
- A session's transcript comes only from `/sessions/:key/live?from=N` (entries
  from index N, then as they are written); the station keeps each watched
  transcript parsed incrementally instead of re-reading the file per request.
- `GET /sessions/:key` is the session row, its threads, and its turns — no
  messages, no transcript.

### Housekeeping

- `POST /sessions/:key/archive` / `DELETE /sessions/:key/archive`: hide and show.
- `DELETE /sessions/:key`: ends its process, deletes its rows (turns,
  deliveries, thread_sessions; threads left with no session and their
  messages) and its workspace directory. The runtime's own transcript file is
  left alone (it is in the profile's home, which may be a person's own).

## Notifications

### Station → clients: `GET /events`

One event stream per client. Each event names what changed and carries it
when it is small:

| event | data |
| --- | --- |
| `session` | the session summary (row, state warm/cold/running, last turn) |
| `session-removed` | `{ key }` |
| `thread` | `{ id, rev, messages: [changed rows] }` |
| `read` | `{ viewer, thread, seq }` (only to that viewer) |
| `overview` | the whole overview — sent when config, connect status, logins, profile checks or quotas change |
| `host` | host info; sampled every 10 s **only while some client asks for it** (`/events?host=1`) and sent when it changed |

Per-session live steps stay on `/sessions/:key/live`.

Timers that remain on the station and why: host sampling (above), quota
refresh while an overview subscriber exists (the provider cannot notify), an
idle process's eviction deadline (a timer per process, set when it goes idle,
instead of a sweep every minute), Slack reconnect backoff.

### ember cloud → devices: `GET /v1/events` (WebSocket)

A device keeps one WebSocket per account to the directory (hibernatable, so
idle sockets cost nothing). Events: `workspaces` (the account's list or
invitations changed), `workspace {id}` (members, roles, stations, names),
`station {workspace, id, online}`.

### Station presence

The station keeps a WebSocket open to ember cloud instead of posting a
heartbeat: open is online, closed is offline, and both are pushed to devices
at once. The socket carries the station's version on open.

### The client core

Holds one `/events` stream per station in use and one `/v1/events` socket per
account; topics change only when these say so. `REFRESH_MS`,
`OVERVIEW_REFRESH_MS` and `HOST_REFRESH_MS` go. A write's answer updates the
topic it returns (e.g. a profile edit returns the overview), and a call
returns only after the topics it touches are current, so a page that
navigates right after a write finds what it wrote.
