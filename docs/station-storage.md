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
  surface TEXT NOT NULL,              -- "slack:<team id>" ("slack:<connect id>" while unknown) | "ember"
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

-- unchanged: turns, bindings, processes
```

`chats`, `chat_messages` and `inbound` are gone: an ember chat is a thread
with surface `ember`; what a person typed there and what came from Slack are
both messages; what `inbound.status` recorded is `deliveries`. The v9 → v10
migration moves existing rows over (data only; no code keeps the old shape):

- threads come from `chats` (surface `ember`), from the threads `inbound`
  rows came from, and from a session's own first thread when it has no
  messages; `thread_sessions` from the same, each with the connect its first
  message came through;
- a message typed on the page is in both old tables and becomes one message:
  the `chat_messages` row gives its words, files and quotes (the `inbound`
  copy held the text formatted for the agent); `inbound.status` becomes the
  delivery's `delivered_at`; seq (and rev) follow the time things were said;
- earlier ember notices were stored as the agent's posts and stay agent
  messages (nothing tells them apart);
- a Slack thread's surface needs the connect's team: before the store opens,
  ember asks Slack (`auth.test` with the connect's bot token) once; a connect
  it cannot ask gets `slack:<connect id>`. New rows follow the same rule — the
  team of the connection the message came through, `slack:<connect id>`
  while that is unknown — so migrated and new rows name a thread alike.
- Schemas before v9 are refused.

### Writing

- **Slack message in**: upsert its thread, insert the message (a duplicate
  `(thread, ts)` is the same message seen twice — ignored), add a delivery
  for each session in the thread (creating the session and its
  `thread_sessions` row first when the message starts one), then ack Slack.
  Several connects in one channel share the thread row and its messages;
  whichever sees a message first delivers it to every session in the thread,
  and a later connect only brings in its own session.
- **Joining mid-thread**: when ember starts following a Slack thread at a
  reply, what Slack has before that reply is recorded first (no deliveries),
  so the thread is complete and seq keeps Slack's order.
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
- **Slack edits and deletes** (`message_changed`, `message_deleted`) update
  the row and bump `rev` (an "edit" with the same words — Slack sends those
  for thread roots as replies come — changes nothing). A message still
  pending reaches the agent as it reads at delivery; a deleted one not at all.
- Every insert or change takes the next `rev` in the same transaction.

### Reading

- `GET /threads?session=…` / the thread list of a session (all threads
  without `session`), `GET /threads/:id`: threads with their sessions, their
  people (everyone who wrote in it, earliest first), the first thing a person
  said (`firstText`, for a chat's title), last message, rev, and the viewer's
  read position and unread count (messages after it, not deleted, not the
  viewer's own — in a Slack thread, not of a Slack user the viewer is).
- `GET /threads/:id/messages?after=<rev>` — every message changed after that
  cursor; `?before=<seq>&limit=` pages back through history (no cursor: the
  latest page). The answer is `{ rev, messages, more }`: follow `after=rev`;
  `more` says older messages exist before a page. A page opens a thread with
  the last page and follows `after`. Messages carry `authorName`.
- `PUT /threads/:id/read {seq}` — the viewer's read position; it only moves
  forward, and the answer says where it is.
- `POST /threads/:id/messages {text, attachments, quotes}` — a person's
  message in an ember chat (Slack threads are written in Slack);
  attachments must be uploads of a session in the thread
  (`POST /sessions/:key/files`). `POST /threads {session, title?}` opens
  another chat on a session; `POST /threads/:id/sessions {session}` brings
  another session into an ember chat. `POST /sessions` (a new chat) makes the
  session and its chat and answers `{ key, thread }`.
- A session's transcript comes only from `/sessions/:key/live?from=N` (entries
  from index N, then as they are written); the station keeps each watched
  transcript parsed incrementally instead of re-reading the file per request.
- `GET /chats` — the viewer's sidebar items (The sidebar, below).
- `PUT /me/slack/:user` / `DELETE /me/slack/:user` — the viewer says a Slack
  user is them ("这是我"), or no longer ("不是我"); nothing checks it. The
  answer is the overview, whose `slackUsers` lists the viewer's Slack users.
- `GET /sessions/:key` is the session row, its threads, and its turns — no
  messages, no transcript. `GET /sessions` lists shown sessions;
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
  "last": { "seq", "authorKind", "author", "authorName", "text", "createdAt", "deletedAt" } | null,
  //   the chat's latest message, its text cut to 200 characters; null without a chat
  "unread": true,                 // messages after the viewer's read position that are not their own
  "mine": true,
  "lastActiveAt": 1790000000000,  // the latest message's time, else the chat's; without a chat: the session's
  "connect": "ds" | null,         // the connect its agent came from; null for one made on ember
  "origin": { "teamName": "Cue", "channel": "C1", "channelName": "ops", "threadTs": "…" } | null
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
made of changes (sessions, messages, memberships, read positions, the
viewer's Slack users, connects), the station reads the items again, once per
viewer for a burst, and tells each stream what differs from the items it last
told it: `chat` with the whole item when one is new or changed,
`chat-removed {id}` when one is gone (an agent's item moves from its session's
key to its chat's id when the chat is made). The items a stream starts from
are those at the moment it opened.

### Housekeeping

- `POST /sessions/:key/archive` / `DELETE /sessions/:key/archive`: hide and
  show; the answer is the session summary.
- `DELETE /sessions/:key`: ends its process, deletes its rows (turns,
  deliveries, thread_sessions; threads left with no session and their
  messages) and its workspace directory. The runtime's own transcript file is
  left alone (it is in the profile's home, which may be a person's own).

## Append-only threads (schema v11 — next)

A thread is a log: entries are appended and never changed, so whatever a
client has fetched stays true forever and can be kept on the device. Changes
are new entries the client merges.

```sql
CREATE TABLE entries (
  thread INTEGER NOT NULL,
  n INTEGER NOT NULL,                 -- 1, 2, 3 … within the thread, no gaps
  kind TEXT NOT NULL,                 -- message | edit | delete
  target INTEGER,                     -- edit/delete: the n of the message it changes
  ts TEXT,                            -- message: the platform's id (Slack ts), unique per thread
  author_kind TEXT NOT NULL,          -- person | agent | ember
  author TEXT NOT NULL,
  text TEXT,                          -- message and edit: Markdown
  attachments TEXT, quotes TEXT,      -- message and edit: JSON
  declared TEXT,                      -- message: an agent's final | block
  at INTEGER NOT NULL,
  PRIMARY KEY (thread, n)
);
```

- `messages` goes (v10 → v11 moves each message to an entry in thread order;
  an edited one becomes its message with the edited text — there is no older
  text to keep; a deleted one becomes a message followed by a delete).
  `deliveries` and `reads` point at `(thread, n)`.
- Slack `message_changed` appends an `edit`, `message_deleted` a `delete`.
- The only way entries disappear is with their whole thread (deleting a
  session removes threads left without one): `thread-removed {id}` tells
  clients to drop what they keep of it.

Archiving writes a thread out of the database: when every session of a
thread is archived, its entries go to `<data>/archive/threads/<id>.jsonl.zst`
(one entry per line, zstd) in one step with deleting its rows, and the
thread row is marked archived. Since entries never change, the file is the
thread as it was, and clients' kept copies stay valid. Reading an archived
thread reads the file (the same API, answers from the decompressed entries);
a new entry — someone writing in it, or unarchiving — loads it back into the
database first and removes the file. The session's transcript copy
(`<data>/archive/transcripts/<session>.jsonl.zst`) is written the same way;
the runtime's own file in the profile's home is left as it is.

Reading: `GET /threads/:id/entries?after=n` (what came since),
`?before=n&limit=` (older pages), `?from=a&to=b` (a gap). Thread summaries
carry `last` (the last n) and the latest message as merged, for lists.
The `thread` event carries the new entries, always contiguous: a client whose
last n is below the first one it receives asks for the gap.

Merging (in the client core, one place): a message shows its latest edit's
text, attachments and quotes, marked edited; a deleted message is gone from
the view. Unread and read positions are entry numbers.

The client core keeps entries on the device, through `Host` storage in
chunks — `thread/<station>/<thread>/<chunk>` holding entries
`chunk*256+1 … chunk*256+256`, plus `thread/<station>/<thread>/meta`
(`{ first, last }` it holds). Opening a chat shows what is kept at once, then
asks for `after=last`; scrolling up reads kept chunks before asking the
station. A session's transcript is append-only too (its entries are indexed
from 0 in `/sessions/:key/live?from=N`) and is kept the same way under
`transcript/<station>/<session>/<chunk>`. Kept data is bounded (least
recently opened threads go first past a size limit) and is dropped for a
station the account can no longer reach and on sign-out.

## Notifications

### Station → clients: `GET /events`

One event stream per client. Each event names what changed and carries it
when it is small:

| event | data |
| --- | --- |
| `session` | the session summary (row, state warm/cold/running, last turn, creator, participants) |
| `session-removed` | `{ key }` (threads that went with it get no event of their own) |
| `thread` | `{ id, rev, messages: [changed rows] }`; `messages: []` when its sessions changed |
| `read` | `{ viewer, thread, seq }` (only to that viewer) |
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
rate-limit backoff, ember-mesh's restart backoff, a keepalive comment on open
event streams every 25 s (proxies close silent ones), a 40 ms coalescing of
transcript writes for live watchers, a sign-in's 15-minute deadline, and the
profile checks a few seconds after start. ember-mesh is started when
`mesh/cloud.json` appears and when its binary is built (both watched with
`fs.watch`), not on a timer.

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
| `{"type":"station","workspace","id","online"}` | a station connected or disconnected | the workspace's members |

A device refetches `/v1/me` on `workspaces` and `/v1/workspaces/:id` on
`workspace`; `station` is complete in itself. Nothing is replayed: after a
reconnect the device refetches what it shows.

### Station presence: `GET /v1/stations/connect` (WebSocket)

The station keeps a WebSocket open to ember cloud instead of posting a
heartbeat: open is online, closed is offline, and both are pushed to devices
at once (`station` above). `StationView.online` says whether it is connected
now; `last_seen` is when it last connected or disconnected ("last online at").

- **Auth**: signed with the station's key at connect, in headers:
  `x-ember-station` (its key, hex), `x-ember-ts` (unix seconds, within 5
  minutes), `x-ember-signature` (hex Ed25519 over
  `ember-station-connect-v1:<origin>:<station>:<ts>`), and `x-ember-version`.
  A station that is not enrolled gets 404 and refuses clients until it is.
- **From the cloud**: `{"type":"state","workspace","workspace_name","name","grant_keys"}`
  on connect and whenever these change (renamed, moved by re-enrolling).
  Close codes: 4000 replaced by a newer socket of the same station, 4004
  removed from its workspace, 4008 silent.
- **Liveness**: the station sends `ping` every 30 s and the runtime answers
  `pong` without waking the directory; a station that gets no `pong` before
  its next ping reconnects. While any station is connected, an alarm every
  90 s drops station sockets unanswered for 90 s (a station that vanished
  without closing), so a dead station shows offline within three minutes.
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
