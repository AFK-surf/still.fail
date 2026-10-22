// The store's schema (the Rust station's store.rs `// ── schema`): the tables as CREATE … IF NOT EXISTS, and the columns that
// came after schema version 12 without changing it, added in place on open (add_*_columns), the same way and in the
// same order as the Rust station does, so either station opens what the other kept.
import type { DatabaseSync } from "node:sqlite";

/// Bump on schema changes. A database of another version is refused: there is one station, and its data is moved by
/// hand when the schema changes (no migrations are kept in the code).
export const SCHEMA_VERSION = 12;

export const SCHEMA = `
CREATE TABLE IF NOT EXISTS archive_suggestions (
  thread INTEGER PRIMARY KEY,
  version INTEGER NOT NULL,
  at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS archive_policy (
  id INTEGER PRIMARY KEY,
  at INTEGER NOT NULL,
  policy TEXT NOT NULL,
  author TEXT NOT NULL,
  summary TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS archive_verdicts (
  thread INTEGER PRIMARY KEY,
  version INTEGER NOT NULL,
  at INTEGER NOT NULL,
  verdict TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS decision_checks (
  id INTEGER PRIMARY KEY,
  session TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  result TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
  key TEXT PRIMARY KEY,
  connect TEXT NOT NULL,
  scope TEXT NOT NULL,
  title TEXT,
  created_by TEXT,
  runtime TEXT NOT NULL,
  profile TEXT NOT NULL,
  profile_pinned INTEGER NOT NULL DEFAULT 0,
  model TEXT,
  effort TEXT,
  fast INTEGER,
  runtime_session_id TEXT,
  workspace TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  running INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  last_active_at INTEGER NOT NULL,
  archived_at INTEGER,
  archived_by TEXT,
  shown_at INTEGER,
  cwd TEXT
);
CREATE TABLE IF NOT EXISTS threads (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  surface TEXT NOT NULL,
  channel TEXT NOT NULL,
  thread_ts TEXT NOT NULL,
  title TEXT,
  created_by TEXT,
  created_at INTEGER NOT NULL,
  archived_at INTEGER,
  home TEXT,
  hidden_at INTEGER,
  hidden_by TEXT,
  shown_at INTEGER,
  auto_title TEXT,
  auto_title_n INTEGER,
  auto_title_changes INTEGER NOT NULL DEFAULT 0,
  UNIQUE (surface, channel, thread_ts)
);
CREATE TABLE IF NOT EXISTS thread_sessions (
  thread INTEGER NOT NULL,
  session TEXT NOT NULL,
  connect TEXT NOT NULL,
  joined_at INTEGER NOT NULL,
  PRIMARY KEY (thread, session)
);
CREATE INDEX IF NOT EXISTS thread_sessions_session ON thread_sessions (session);
CREATE TABLE IF NOT EXISTS entries (
  thread INTEGER NOT NULL,
  n INTEGER NOT NULL,
  kind TEXT NOT NULL,
  target INTEGER,
  ts TEXT,
  author_kind TEXT NOT NULL,
  author TEXT NOT NULL,
  text TEXT,
  attachments TEXT,
  quotes TEXT,
  declared TEXT,
  at INTEGER NOT NULL,
  client TEXT,
  profile TEXT,
  runtime TEXT,
  options TEXT,
  card TEXT,
  PRIMARY KEY (thread, n)
);
CREATE UNIQUE INDEX IF NOT EXISTS entries_ts ON entries (thread, ts) WHERE ts IS NOT NULL;
CREATE INDEX IF NOT EXISTS entries_target ON entries (thread, target) WHERE target IS NOT NULL;
CREATE TABLE IF NOT EXISTS deliveries (
  thread INTEGER NOT NULL,
  n INTEGER NOT NULL,
  session TEXT NOT NULL,
  delivered_at INTEGER,
  PRIMARY KEY (thread, n, session)
);
CREATE INDEX IF NOT EXISTS deliveries_pending ON deliveries (session) WHERE delivered_at IS NULL;
CREATE INDEX IF NOT EXISTS deliveries_session ON deliveries (session, thread);
CREATE TABLE IF NOT EXISTS reads (
  viewer TEXT NOT NULL,
  thread INTEGER NOT NULL,
  n INTEGER NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (viewer, thread)
);
CREATE TABLE IF NOT EXISTS profile_status (
  profile TEXT PRIMARY KEY,
  check_json TEXT, checked_at INTEGER,
  quota_json TEXT, quota_at INTEGER
);
CREATE TABLE IF NOT EXISTS bindings (
  connect TEXT PRIMARY KEY,
  session_key TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS turns (
  id TEXT PRIMARY KEY,
  session_key TEXT NOT NULL,
  kind TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  outcome TEXT,
  detail TEXT,
  declared TEXT,
  wait_seconds INTEGER,
  wait_for TEXT,
  need TEXT,
  about_thread INTEGER,
  about_n INTEGER,
  about_ts TEXT
);
-- A session's turns, by when they started: every list of chats and sessions counts each session's turns and takes its
-- latest (sessionStats); without it each scanned every turn of every session (some 160 ms a list on a busy station).
CREATE INDEX IF NOT EXISTS turns_by_session ON turns (session_key, started_at);
CREATE TABLE IF NOT EXISTS processes (
  pgid INTEGER PRIMARY KEY,
  started_at INTEGER NOT NULL,
  runtime TEXT NOT NULL,
  label TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS jobs (
  id TEXT PRIMARY KEY,
  session_key TEXT NOT NULL,
  name TEXT NOT NULL,
  command TEXT NOT NULL,
  cwd TEXT NOT NULL,
  port INTEGER,
  token TEXT NOT NULL UNIQUE,
  state TEXT NOT NULL,
  pgid INTEGER,
  exit_code INTEGER,
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  restarts INTEGER NOT NULL DEFAULT 0,
  log TEXT NOT NULL,
  watch INTEGER NOT NULL DEFAULT 0,
  queued INTEGER,
  screen INTEGER,
  size TEXT
);
CREATE INDEX IF NOT EXISTS jobs_by_session ON jobs (session_key);
CREATE TABLE IF NOT EXISTS job_notices (
  job_id TEXT NOT NULL,
  at INTEGER NOT NULL,
  text TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS job_notices_by_job ON job_notices (job_id, at);
CREATE TABLE IF NOT EXISTS identities (
  viewer TEXT NOT NULL,
  slack_user TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (viewer, slack_user)
);
-- Came after schema version 12 without changing it: made in place on open, like add_archive_columns' columns.
-- The chats a viewer keeps at the top of their list, by their item's id (its session's key), and since when.
CREATE TABLE IF NOT EXISTS pins (
  viewer TEXT NOT NULL,
  session TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (viewer, session)
);
CREATE TABLE IF NOT EXISTS widget_states (
  session TEXT NOT NULL,
  path TEXT NOT NULL,
  state TEXT NOT NULL,
  model TEXT,
  updated_at INTEGER NOT NULL,
  told_at INTEGER,
  PRIMARY KEY (session, path)
);
-- The pieces of work in a chat, as its agents declare them (chat_post items): each waiting on someone or not.
CREATE TABLE IF NOT EXISTS items (
  thread INTEGER NOT NULL,
  key TEXT NOT NULL,
  session TEXT NOT NULL,
  title TEXT NOT NULL,
  state TEXT NOT NULL,
  waiting_on TEXT,
  ask TEXT,
  detail TEXT,
  evidence INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (thread, key)
);
-- Pending decisions (an agent's block post with options) a viewer said they will not take up: not on their list
-- any more, still pending for everyone else. By the post's thread and entry number.
CREATE TABLE IF NOT EXISTS dismissed (
  viewer TEXT NOT NULL,
  thread INTEGER NOT NULL,
  n INTEGER NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (viewer, thread, n)
);
-- A viewer keeps a chat instead of receiving archive reminders.
CREATE TABLE IF NOT EXISTS kept_chats (
  viewer TEXT NOT NULL,
  thread INTEGER NOT NULL,
  PRIMARY KEY (viewer, thread)
);
-- A card closed by its viewer or withdrawn by its author.
CREATE TABLE IF NOT EXISTS closed_cards (
  thread INTEGER NOT NULL,
  n INTEGER NOT NULL,
  viewer TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (thread, n)
);
-- What the agents spent (store/usage.rs): one row per model call their runtimes recorded, read from the transcripts,
-- with whom and what it was for as it was then. Kept when its session goes: it was spent all the same.
CREATE TABLE IF NOT EXISTS usage (
  id TEXT PRIMARY KEY,
  at INTEGER NOT NULL,
  session TEXT NOT NULL,
  turn TEXT,
  thread INTEGER,
  person TEXT,
  profile TEXT,
  runtime TEXT NOT NULL,
  model TEXT,
  subagent INTEGER NOT NULL DEFAULT 0,
  fast INTEGER NOT NULL DEFAULT 0,
  input INTEGER NOT NULL,
  cache_read INTEGER NOT NULL,
  cache_write INTEGER NOT NULL,
  cache_write_long INTEGER NOT NULL,
  output INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS usage_at ON usage (at);
-- The runtime sessions a session has run in, the first first, each with the profile it last ran on. The latest is
-- sessions.runtime_session_id; one before it was left for a new one (its account changed), and its history goes on
-- from theirs.
CREATE TABLE IF NOT EXISTS runtime_sessions (
  session_key TEXT NOT NULL,
  id TEXT NOT NULL,
  profile TEXT,
  at INTEGER NOT NULL,
  PRIMARY KEY (session_key, id)
);
-- How far each transcript has been read for it.
CREATE TABLE IF NOT EXISTS usage_files (
  path TEXT PRIMARY KEY,
  session TEXT,
  offset INTEGER NOT NULL,
  model TEXT
);
-- Chats an agent opened for another (chat_create, sessions/opened.ts): the session opened (child) and the one that
-- opened it (parent), each by its station ('' for this one) and key, with the key the opener gave the call. The station
-- of either keeps a row: the child's to tell its parent how its turns end, the parent's to know its children by.
CREATE TABLE IF NOT EXISTS opened_chats (
  child_station TEXT NOT NULL,
  child TEXT NOT NULL,
  parent_station TEXT NOT NULL,
  parent TEXT NOT NULL,
  key TEXT NOT NULL,
  title TEXT,
  link TEXT,
  state TEXT,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (child_station, child)
);
CREATE INDEX IF NOT EXISTS opened_chats_by_key ON opened_chats (parent_station, parent, key, child_station);
-- Chats shared with other workspaces (docs/chat-share.md, xshare/), by the session key their links name: to whom
-- (to: JSON [{workspace, name}]), whether they may write in it, who changed it last and when.
CREATE TABLE IF NOT EXISTS chat_shares (
  session TEXT PRIMARY KEY,
  shared TEXT NOT NULL,
  write INTEGER NOT NULL DEFAULT 0,
  by TEXT NOT NULL,
  at INTEGER NOT NULL
);
-- Chats published as a snapshot anyone with its link reads (docs/public-share.md, publish/): the link's id and key, the
-- chat's title then, who published it (email, name) and when, its last message (upto, an n) and its size in bytes. The
-- snapshot itself is in published/<id>/ beside the database.
CREATE TABLE IF NOT EXISTS published (
  id TEXT PRIMARY KEY,
  thread INTEGER NOT NULL,
  key TEXT NOT NULL,
  title TEXT NOT NULL,
  created_by TEXT NOT NULL,
  by_name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  upto INTEGER NOT NULL,
  size INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS published_by_thread ON published (thread);
-- Where chats were relayed (docs/relay.md, sessions/relay.ts): each connect's channel or group, by when a chat was last
-- relayed there, so the picker offers the places used before first.
CREATE TABLE IF NOT EXISTS relayed_to (
  connect TEXT NOT NULL,
  channel TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (connect, channel)
);
`;

/// Each message as it reads now: its latest edit's words, files and quotes.
export const MERGED = `CREATE VIEW merged AS
  SELECT m.thread, m.n, m.ts, m.author_kind, m.author,
    CASE WHEN e.n IS NULL THEN m.text ELSE e.text END AS text,
    CASE WHEN e.n IS NULL THEN m.attachments ELSE e.attachments END AS attachments,
    CASE WHEN e.n IS NULL THEN m.quotes ELSE e.quotes END AS quotes,
    m.declared, m.client, m.agent_identity, m.at AS created_at, e.at AS edited_at, m.letter
  FROM entries m
  LEFT JOIN entries e ON e.thread = m.thread
    AND e.n = (SELECT MAX(x.n) FROM entries x WHERE x.thread = m.thread AND x.target = m.n)
  WHERE m.kind = 'message';`;

const has = (db: DatabaseSync, table: string, column: string): boolean =>
  db.prepare(`SELECT 1 FROM pragma_table_info('${table}') WHERE name = ?`).get(column) !== undefined;

/// add_archive_columns: columns archiving came with, added to a database made before them. When they come, each
/// session's first chat on the page is taken as its own, and chats of sessions archived then as archived with them.
export function addArchiveColumns(db: DatabaseSync): void {
  for (const [column, kind] of [["archived_by", "TEXT"], ["shown_at", "INTEGER"], ["cwd", "TEXT"], ["fast", "INTEGER"]]) {
    if (!has(db, "sessions", column!)) db.exec(`ALTER TABLE sessions ADD COLUMN ${column} ${kind}`);
  }
  // Came with waiting's limit, after the turns table.
  if (!has(db, "turns", "wait_seconds")) db.exec("ALTER TABLE turns ADD COLUMN wait_seconds INTEGER");
  // Came with saying what a wait is for (chat_state waiting `for`).
  if (!has(db, "turns", "wait_for")) db.exec("ALTER TABLE turns ADD COLUMN wait_for TEXT");
  // Came with migration notes: the last one each session was told. A session from before them was told none.
  if (!has(db, "sessions", "told_notes")) db.exec("ALTER TABLE sessions ADD COLUMN told_notes INTEGER");
  // Came with need_help's `need`: what a person has to give or do.
  if (!has(db, "turns", "need")) db.exec("ALTER TABLE turns ADD COLUMN need TEXT");
  // Came with `about`: the message a turn's state is about.
  for (const [column, kind] of [["about_thread", "INTEGER"], ["about_n", "INTEGER"], ["about_ts", "TEXT"]]) {
    if (!has(db, "turns", column!)) db.exec(`ALTER TABLE turns ADD COLUMN ${column} ${kind}`);
  }
  // Came with usage (store/usage.ts): whom a turn worked for, where, and on which profile.
  for (const [column, kind] of [["profile", "TEXT"], ["person", "TEXT"], ["thread", "INTEGER"]]) {
    if (!has(db, "turns", column!)) db.exec(`ALTER TABLE turns ADD COLUMN ${column} ${kind}`);
  }
  if (has(db, "threads", "home")) return;
  db.exec(
    `BEGIN;
     ALTER TABLE threads ADD COLUMN home TEXT;
     ALTER TABLE threads ADD COLUMN hidden_at INTEGER;
     ALTER TABLE threads ADD COLUMN hidden_by TEXT;
     ALTER TABLE threads ADD COLUMN shown_at INTEGER;
     UPDATE threads SET home = (SELECT ts.session FROM thread_sessions ts WHERE ts.thread = threads.id ORDER BY ts.joined_at, ts.rowid LIMIT 1)
     WHERE surface = 'ember' AND id = (
       SELECT MIN(t2.id) FROM threads t2 JOIN thread_sessions ts2 ON ts2.thread = t2.id
       WHERE t2.surface = 'ember' AND ts2.session = (SELECT ts.session FROM thread_sessions ts WHERE ts.thread = threads.id ORDER BY ts.joined_at, ts.rowid LIMIT 1));
     UPDATE sessions SET archived_by = 'manual' WHERE archived_at IS NOT NULL AND archived_by IS NULL;
     UPDATE threads SET hidden_at = (SELECT archived_at FROM sessions WHERE key = threads.home), hidden_by = 'manual'
     WHERE home IN (SELECT key FROM sessions WHERE archived_at IS NOT NULL);
     COMMIT;`,
  );
}

/// add_client_column: the column a message's app came with (entries.client) and those after it, and the `merged` view
/// made anew with them.
export function addClientColumn(db: DatabaseSync): void {
  if (!has(db, "entries", "agent_identity")) db.exec("ALTER TABLE entries ADD COLUMN agent_identity TEXT");
  if (!has(db, "entries", "client")) db.exec("ALTER TABLE entries ADD COLUMN client TEXT");
  // The profile a notice is about; the `merged` view has no need of it.
  if (!has(db, "entries", "profile")) db.exec("ALTER TABLE entries ADD COLUMN profile TEXT");
  // The runtime a notice says is not installed (offered to install).
  if (!has(db, "entries", "runtime")) db.exec("ALTER TABLE entries ADD COLUMN runtime TEXT");
  // A block post's answers to pick from; the `merged` view has no need of them.
  if (!has(db, "entries", "options")) db.exec("ALTER TABLE entries ADD COLUMN options TEXT");
  // A message's card; an options card is kept in `options` too, which stations from before cards read.
  if (!has(db, "entries", "card")) db.exec("ALTER TABLE entries ADD COLUMN card TEXT");
  // A chat's latest card is looked for on every list of chats: only its posts with one are read.
  db.exec("CREATE INDEX IF NOT EXISTS entries_options ON entries (thread, n) WHERE options IS NOT NULL");
  db.exec("CREATE INDEX IF NOT EXISTS entries_cards ON entries (thread, n) WHERE card IS NOT NULL");
  // What people said lately is looked for on every list of chats (the cards they answered: `answersSince`).
  db.exec("CREATE INDEX IF NOT EXISTS entries_people_at ON entries (at) WHERE author_kind = 'person' AND kind = 'message'");
  // A prior upgrade may have added the table column without rebuilding this view.
  if (!has(db, "merged", "client") || !has(db, "merged", "agent_identity") || !has(db, "merged", "letter")) db.exec(`BEGIN; DROP VIEW IF EXISTS merged; ${MERGED} COMMIT;`);
}

/// The column letters came with (entries.letter, rows.ts Letter): what two chats' agents write each other, kept apart
/// from what is said in a chat. Before it, a letter was known by its heading alone (`来自 …：`, by an agent not of the
/// thread): those are marked once as the column comes, with the chat their heading names. Runs before addClientColumn,
/// whose `merged` view has the column.
export function addLetterColumn(db: DatabaseSync): void {
  if (has(db, "entries", "letter")) return;
  db.exec("ALTER TABLE entries ADD COLUMN letter TEXT");
  db.exec("CREATE INDEX IF NOT EXISTS entries_letters ON entries (thread, n) WHERE letter IS NOT NULL");
  const before = db.prepare(
    `SELECT thread, n, text FROM entries e WHERE kind = 'message' AND author_kind = 'agent' AND (text LIKE '来自 %' OR text LIKE 'From %')
     AND author NOT IN (SELECT session FROM thread_sessions WHERE thread = e.thread)`,
  ).all() as { thread: number; n: number; text: string }[];
  if (before.length === 0) return;
  const mark = db.prepare("UPDATE entries SET letter = ? WHERE thread = ? AND n = ?");
  db.exec("BEGIN");
  try {
    for (const r of before) mark.run(JSON.stringify({ way: "in", ...headedFrom(r.text) }), r.thread, r.n);
    db.exec("COMMIT");
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

/// The chat a letter's heading names (sessions/messages.ts `header`): `来自 [title](link)：`, Slack's `From <link|title>:`,
/// or a title alone.
export function headedFrom(text: string): { title: string; link: string | null } {
  const head = (text.split("\n", 1)[0] ?? "").replace(/^(来自|From) /, "").replace(/(：|:)\s*$/, "");
  const md = /^\[(.*)\]\((\S+)\)$/.exec(head);
  if (md) return { title: md[1]!, link: md[2]! };
  const slack = /^<([^|>]+)\|(.*)>$/.exec(head);
  if (slack) return { title: slack[2]!, link: slack[1]! };
  return { title: head, link: null };
}

/// add_auto_title_columns: the columns a chat's own name from its agent came with (threads.auto_title…).
export function addAutoTitleColumns(db: DatabaseSync): void {
  for (const [column, kind] of [["auto_title", "TEXT"], ["auto_title_n", "INTEGER"], ["auto_title_changes", "INTEGER NOT NULL DEFAULT 0"]]) {
    if (!has(db, "threads", column!)) db.exec(`ALTER TABLE threads ADD COLUMN ${column} ${kind}`);
  }
}

/// add_watch_column: the column watching jobs came with (jobs.watch).
export function addWatchColumn(db: DatabaseSync): void {
  if (!has(db, "jobs", "watch")) db.exec("ALTER TABLE jobs ADD COLUMN watch INTEGER NOT NULL DEFAULT 0");
}

/// The columns the station's queue came with (jobs/admit.ts): a job waiting for room (jobs.queued), one that uses the
/// screen (jobs.screen).
export function addQueueColumns(db: DatabaseSync): void {
  if (!has(db, "jobs", "queued")) db.exec("ALTER TABLE jobs ADD COLUMN queued INTEGER");
  if (!has(db, "jobs", "screen")) db.exec("ALTER TABLE jobs ADD COLUMN screen INTEGER");
}

/// The column a job's sandbox size came with (jobs.size, agents/sandbox.ts).
export function addSizeColumn(db: DatabaseSync): void {
  if (!has(db, "jobs", "size")) db.exec("ALTER TABLE jobs ADD COLUMN size TEXT");
}

/// The columns a station in several workspaces came with (docs/multi-workspace.md): which workspace a session's chat
/// is in (sessions.ws) and whose archive policy a row is (archive_policy.ws); NULL is the station's home workspace.
export function addWorkspaceColumns(db: DatabaseSync): void {
  if (!has(db, "sessions", "ws")) db.exec("ALTER TABLE sessions ADD COLUMN ws TEXT");
  if (!has(db, "archive_policy", "ws")) db.exec("ALTER TABLE archive_policy ADD COLUMN ws TEXT");
}
