// The store's schema (the Rust station's store.rs `// ── schema`): the tables as CREATE … IF NOT EXISTS, and the columns that
// came after schema version 12 without changing it, added in place on open (add_*_columns), the same way and in the
// same order as the Rust station does, so either station opens what the other kept.
import type { DatabaseSync } from "node:sqlite";
import { COMPACTED_FROM, QUARTER_MS } from "./rows.ts";

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
-- A session's latest check (review.ts undecided, for every done chat) and those of the last days (the archive policy's
-- view, in every overview): without them each scanned every check.
CREATE INDEX IF NOT EXISTS decision_checks_session ON decision_checks (session, id);
CREATE INDEX IF NOT EXISTS decision_checks_at ON decision_checks (created_at);
-- Each session's latest check of the last days (store.ts LATEST_DECISIONS): from the index alone, and then only the
-- rows of those latest (ccvm: 1,025 checks of 210 sessions in a week).
CREATE INDEX IF NOT EXISTS decision_checks_lately ON decision_checks (created_at, session);
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
-- The sessions shown (store.ts LIVE_SESSIONS): what the station's own periodic work goes over; the archived ones only grow.
CREATE INDEX IF NOT EXISTS sessions_live ON sessions (last_active_at) WHERE archived_at IS NULL;
-- The sessions running (store.ts ANY_RUNNING, RUNNING_SESSIONS).
CREATE INDEX IF NOT EXISTS sessions_running ON sessions (key) WHERE running = 1;
-- The sessions someone started lately (store.ts modelsUsedBy: the models they chose, as a chat is opened for them).
CREATE INDEX IF NOT EXISTS sessions_by_creator ON sessions (created_by, created_at);
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
-- The threads at an address on any surface (store.ts threadsAt: session_send to a thread by its channel and ts).
CREATE INDEX IF NOT EXISTS threads_at ON threads (channel, thread_ts);
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
-- A message's latest edit (the merged view, at each message any list or page reads): by the thread, the message and
-- the edit's own number, found at once. With (thread, target) alone, node's SQLite (3.53) took the latest from the
-- primary key instead, going back over the whole thread for a message never edited: every message read had a long
-- chat's every page read with it, 5 to 8 s on ccvm with its pages put out (2026-10-25).
CREATE INDEX IF NOT EXISTS entries_edits ON entries (thread, target, n) WHERE target IS NOT NULL;
-- A thread's people's messages since a time (rows.ts SAID_SINCE: the cards they answered, of the sidebar items a change
-- touched): without it each went over the thread's every entry.
CREATE INDEX IF NOT EXISTS entries_people_since ON entries (thread, at) WHERE author_kind = 'person' AND kind = 'message';
-- The login cards (store.ts closeLoginCards, as a login ends): without it each read every entry of the station's.
CREATE INDEX IF NOT EXISTS entries_login_cards ON entries (thread, n) WHERE card LIKE '%"login"%';
CREATE TABLE IF NOT EXISTS deliveries (
  thread INTEGER NOT NULL,
  n INTEGER NOT NULL,
  session TEXT NOT NULL,
  delivered_at INTEGER,
  PRIMARY KEY (thread, n, session)
);
CREATE INDEX IF NOT EXISTS deliveries_pending ON deliveries (session) WHERE delivered_at IS NULL;
CREATE INDEX IF NOT EXISTS deliveries_session ON deliveries (session, thread);
-- What a session took lately, as it was delivered (usage.ts TAKEN_SINCE: whom a turn from before turns said so worked
-- for, as the usage counter reads its calls).
CREATE INDEX IF NOT EXISTS deliveries_taken ON deliveries (session, delivered_at) WHERE delivered_at IS NOT NULL;
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
  about_ts TEXT,
  wait_watch INTEGER
);
-- A session's turns, by when they started: every list of chats and sessions counts each session's turns and takes its
-- latest (sessionStats); without it each scanned every turn of every session (some 160 ms a list on a busy station).
CREATE INDEX IF NOT EXISTS turns_by_session ON turns (session_key, started_at);
-- The turns running or ended lately (usage.ts usageActiveSessions, at each read of the usage counter: every few seconds
-- while agents work): without it each read scanned every turn of the station's.
CREATE INDEX IF NOT EXISTS turns_ended ON turns (ended_at);
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
-- The jobs running (store.ts runningJobs, JOBS_RUNNING: every station_list that asks how busy this one is, the
-- memory's watch every ten seconds, who keeps watch), and the services stopped on their own that hold their port
-- (JOBS_UP: what keeps a session from being archived): without them each looked at every job the station ever ran.
CREATE INDEX IF NOT EXISTS jobs_state ON jobs (state);
CREATE INDEX IF NOT EXISTS jobs_up ON jobs (state, port);
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
-- The cards closed lately (store.ts answersSince, at each list of chats).
CREATE INDEX IF NOT EXISTS closed_cards_at ON closed_cards (at);
-- What the agents spent (store/usage.rs): one row per model call their runtimes recorded, read from the transcripts,
-- with whom and what it was for as it was then. Kept when its session goes: it was spent all the same. The one record
-- of it: a chat's usage and the usage page are both added up from here (usage/module.ts, read/usage.ts). calls: how
-- many calls the row is (a runtime that tells a turn's counts at once, Devin or Grok Build, says how many it made).
-- context: of a main-thread row, what its session's context held after it (the prompt a call sent; what the runtime
-- says of a turn's last call); context_window: the model's window where the runtime tells it. NULL: not told.
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
  output INTEGER NOT NULL,
  calls INTEGER NOT NULL DEFAULT 1,
  context INTEGER,
  context_window INTEGER
);
CREATE INDEX IF NOT EXISTS usage_at ON usage (at);
-- A session's calls (session_usage, accounts.ts lastContexts) read without the rest.
CREATE INDEX IF NOT EXISTS usage_session ON usage (session, at);
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
-- The session that went on with a runtime's session, by its id (rows.ts SESSION_OF_RUNTIME: a machine's session gone
-- on with, Codex's fast mode).
CREATE INDEX IF NOT EXISTS runtime_sessions_by_id ON runtime_sessions (id);
CREATE INDEX IF NOT EXISTS sessions_by_runtime_id ON sessions (runtime_session_id) WHERE runtime_session_id IS NOT NULL;
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
-- Each task another station's chat ran here, as it began running (jobs/jobs.ts spawn: a remote: session's job, not
-- a service started again): its job, when, and whose (its session's key, remote:<workspace>:<station>:<session>),
-- kept 90 days whatever comes of the task and its session (store.ts noteRemoteRun), for what a workspace's card says of
-- the tasks its chats ran on other stations (read/usage.ts remoteRuns).
CREATE TABLE IF NOT EXISTS remote_runs (
  job TEXT PRIMARY KEY,
  at INTEGER NOT NULL,
  session TEXT NOT NULL
);
-- How many entries each session's transcript has, as the station last read it while the session was at work
-- (sessions/live.ts): its summary says so, and a device that missed some of them knows to read them.
CREATE TABLE IF NOT EXISTS transcript_lengths (
  session TEXT PRIMARY KEY,
  n INTEGER NOT NULL
);
-- What each session's calls used (read/usage.ts SessionUsage, as JSON), as the usage counter recorded them
-- (usage/module.ts keepUsage): its summary says it, so a device knows what an agent at rest used without following it.
CREATE TABLE IF NOT EXISTS session_usage (
  session TEXT PRIMARY KEY,
  usage TEXT NOT NULL
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

/// The indexes on the threads' columns that came with homes (addArchiveColumns), made once those are there: a session's
/// own chat (store.ts homeChat, usage.ts usageTurns: each part of a transcript the usage counter reads), and the chats
/// of their own the auto-archiving goes over, without reading every thread.
export function addThreadIndexes(db: DatabaseSync): void {
  db.exec(`CREATE INDEX IF NOT EXISTS threads_home ON threads (home) WHERE home IS NOT NULL;
    CREATE INDEX IF NOT EXISTS threads_own ON threads (surface) WHERE home IS NULL AND hidden_at IS NULL;`);
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

/// The column saying a wait is its session's watch came with (turns.wait_watch, chat_state waiting `watch`): 1 it is, 0
/// something else; NULL said before it (taken as its watch while one runs).
export function addWaitWatchColumn(db: DatabaseSync): void {
  if (!has(db, "turns", "wait_watch")) db.exec("ALTER TABLE turns ADD COLUMN wait_watch INTEGER");
}

/// The column a job's sandbox size came with (jobs.size, agents/sandbox.ts).
export function addSizeColumn(db: DatabaseSync): void {
  if (!has(db, "jobs", "size")) db.exec("ALTER TABLE jobs ADD COLUMN size TEXT");
}

/// What each session's calls add up to, by runtime, model ('' for none) and speed (store/usage.ts `usageOfSession`): kept
/// by the database itself as calls are recorded (or their output grows), whatever station process records them. A
/// session's usage is a few rows, where adding up its calls read every one of them, scattered over the table: some
/// 20,000 for a long chat, seconds of reading on a machine short of memory, on the main thread, each time the live view
/// of a session at work told its usage (ccvm, 2026-10-24: the station stopped answering for up to a minute).
/// The triggers that add a call to its session's totals and take one away, each by the calls it is (usage.calls).
const USAGE_TOTALS_KEPT = `
CREATE TRIGGER usage_totals_add AFTER INSERT ON usage BEGIN
  INSERT INTO usage_totals VALUES (NEW.session, NEW.runtime, COALESCE(NEW.model, ''), NEW.fast, NEW.calls, NEW.input, NEW.cache_read, NEW.cache_write, NEW.cache_write_long, NEW.output)
  ON CONFLICT (session, runtime, model, fast) DO UPDATE SET calls = calls + excluded.calls, input = input + excluded.input, cache_read = cache_read + excluded.cache_read,
    cache_write = cache_write + excluded.cache_write, cache_write_long = cache_write_long + excluded.cache_write_long, output = output + excluded.output;
END;
CREATE TRIGGER usage_totals_drop AFTER DELETE ON usage BEGIN
  UPDATE usage_totals SET calls = calls - OLD.calls, input = input - OLD.input, cache_read = cache_read - OLD.cache_read, cache_write = cache_write - OLD.cache_write,
    cache_write_long = cache_write_long - OLD.cache_write_long, output = output - OLD.output
  WHERE session = OLD.session AND runtime = OLD.runtime AND model = COALESCE(OLD.model, '') AND fast = OLD.fast;
END;
`;
const USAGE_TOTALS = `
CREATE TABLE usage_totals (
  session TEXT NOT NULL,
  runtime TEXT NOT NULL,
  model TEXT NOT NULL,
  fast INTEGER NOT NULL,
  calls INTEGER NOT NULL,
  input INTEGER NOT NULL,
  cache_read INTEGER NOT NULL,
  cache_write INTEGER NOT NULL,
  cache_write_long INTEGER NOT NULL,
  output INTEGER NOT NULL,
  PRIMARY KEY (session, runtime, model, fast)
) WITHOUT ROWID;
INSERT INTO usage_totals
  SELECT session, runtime, COALESCE(model, ''), fast, SUM(calls), SUM(input), SUM(cache_read), SUM(cache_write), SUM(cache_write_long), SUM(output)
  FROM usage NOT INDEXED GROUP BY session, runtime, COALESCE(model, ''), fast;
${USAGE_TOTALS_KEPT}
CREATE TRIGGER usage_totals_grow AFTER UPDATE OF output ON usage WHEN NEW.output <> OLD.output BEGIN
  UPDATE usage_totals SET output = output + NEW.output - OLD.output
  WHERE session = NEW.session AND runtime = NEW.runtime AND model = COALESCE(NEW.model, '') AND fast = NEW.fast;
END;
`;

/// The columns usage came with as the one record of what was spent (usage.calls, context, context_window), added to a
/// table made before them, in one transaction: a row from before is one call, and a main-thread one left the context it
/// sent (as the context of a call was worked out before), and the triggers made before them (the totals', the
/// compactions') are made anew to read them. Before the totals and compactions are made, which read them too.
export function addUsageColumns(db: DatabaseSync): void {
  if (has(db, "usage", "calls")) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!has(db, "usage", "calls")) {
      db.exec(`ALTER TABLE usage ADD COLUMN calls INTEGER NOT NULL DEFAULT 1;
        ALTER TABLE usage ADD COLUMN context INTEGER;
        ALTER TABLE usage ADD COLUMN context_window INTEGER;
        UPDATE usage SET context = input + cache_read + cache_write + cache_write_long WHERE subagent = 0;`);
      const made = (name: string) => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = ?").get(name) !== undefined;
      if (made("usage_totals_add")) db.exec(`DROP TRIGGER usage_totals_add; DROP TRIGGER usage_totals_drop; ${USAGE_TOTALS_KEPT}`);
      if (made("usage_compactions_add")) db.exec(`DROP TRIGGER usage_compactions_add; ${USAGE_COMPACTIONS_KEPT}`);
    }
    db.exec("COMMIT");
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

/// The usage totals (USAGE_TOTALS), made once from the calls recorded before them, in the same transaction as the
/// triggers that keep them from then on: no call is counted twice or missed. The making reads the table through once, in
/// order (a second or two for 300,000 calls).
export function addUsageTotals(db: DatabaseSync): void {
  const made = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_totals'").get() !== undefined;
  if (made()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!made()) db.exec(USAGE_TOTALS);
    db.exec("COMMIT");
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

/// The calls added up by quarter of an hour (`quarter`: their time, ms, over QUARTER_MS) and by session, thread, person,
/// profile, runtime, model and speed (none of them said: 0 or ''), kept by the database itself as calls are recorded (or
/// their output grows), as the totals are: what the usage page reads (store/usage.ts USAGE_GROUPS), days in any time
/// zone being whole quarters. Adding up its 30 days read every call of them, 440,000 on ccvm, each time a page showing
/// it was told usage changed (every minute while agents work): 30 to 100 seconds a read on a machine short of memory,
/// both of the station's readers held by it and every other read waiting.
const USAGE_QUARTERS_KEPT = `
CREATE TRIGGER usage_quarters_add AFTER INSERT ON usage BEGIN
  INSERT INTO usage_quarters VALUES (NEW.at / ${QUARTER_MS}, NEW.session, COALESCE(NEW.thread, 0), COALESCE(NEW.person, ''), COALESCE(NEW.profile, ''), NEW.runtime,
    COALESCE(NEW.model, ''), NEW.fast, NEW.calls, NEW.input, NEW.cache_read, NEW.cache_write, NEW.cache_write_long, NEW.output)
  ON CONFLICT (quarter, session, thread, person, profile, runtime, model, fast) DO UPDATE SET calls = calls + excluded.calls, input = input + excluded.input,
    cache_read = cache_read + excluded.cache_read, cache_write = cache_write + excluded.cache_write, cache_write_long = cache_write_long + excluded.cache_write_long,
    output = output + excluded.output;
END;
CREATE TRIGGER usage_quarters_drop AFTER DELETE ON usage BEGIN
  UPDATE usage_quarters SET calls = calls - OLD.calls, input = input - OLD.input, cache_read = cache_read - OLD.cache_read, cache_write = cache_write - OLD.cache_write,
    cache_write_long = cache_write_long - OLD.cache_write_long, output = output - OLD.output
  WHERE quarter = OLD.at / ${QUARTER_MS} AND session = OLD.session AND thread = COALESCE(OLD.thread, 0) AND person = COALESCE(OLD.person, '')
    AND profile = COALESCE(OLD.profile, '') AND runtime = OLD.runtime AND model = COALESCE(OLD.model, '') AND fast = OLD.fast;
  DELETE FROM usage_quarters WHERE quarter = OLD.at / ${QUARTER_MS} AND calls <= 0;
END;
CREATE TRIGGER usage_quarters_grow AFTER UPDATE OF output ON usage WHEN NEW.output <> OLD.output BEGIN
  UPDATE usage_quarters SET output = output + NEW.output - OLD.output
  WHERE quarter = NEW.at / ${QUARTER_MS} AND session = NEW.session AND thread = COALESCE(NEW.thread, 0) AND person = COALESCE(NEW.person, '')
    AND profile = COALESCE(NEW.profile, '') AND runtime = NEW.runtime AND model = COALESCE(NEW.model, '') AND fast = NEW.fast;
END;
`;
const USAGE_QUARTERS = `
CREATE TABLE usage_quarters (
  quarter INTEGER NOT NULL,
  session TEXT NOT NULL,
  thread INTEGER NOT NULL,
  person TEXT NOT NULL,
  profile TEXT NOT NULL,
  runtime TEXT NOT NULL,
  model TEXT NOT NULL,
  fast INTEGER NOT NULL,
  calls INTEGER NOT NULL,
  input INTEGER NOT NULL,
  cache_read INTEGER NOT NULL,
  cache_write INTEGER NOT NULL,
  cache_write_long INTEGER NOT NULL,
  output INTEGER NOT NULL,
  PRIMARY KEY (quarter, session, thread, person, profile, runtime, model, fast)
) WITHOUT ROWID;
INSERT INTO usage_quarters
  SELECT at / ${QUARTER_MS}, session, COALESCE(thread, 0), COALESCE(person, ''), COALESCE(profile, ''), runtime, COALESCE(model, ''), fast,
    SUM(calls), SUM(input), SUM(cache_read), SUM(cache_write), SUM(cache_write_long), SUM(output)
  FROM usage NOT INDEXED GROUP BY 1, 2, 3, 4, 5, 6, 7, 8;
${USAGE_QUARTERS_KEPT}`;

/// The usage by quarter (USAGE_QUARTERS), made once from the calls recorded before, in the same transaction as the
/// triggers that keep it from then on (as addUsageTotals).
export function addUsageQuarters(db: DatabaseSync): void {
  const made = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_quarters'").get() !== undefined;
  if (made()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!made()) db.exec(USAGE_QUARTERS);
    db.exec("COMMIT");
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

/// The trigger that keeps the compactions (USAGE_COMPACTIONS) as each main-thread call is recorded: the session's call
/// before it, looked up by its index.
const USAGE_COMPACTIONS_KEPT = `
CREATE TRIGGER usage_compactions_add AFTER INSERT ON usage WHEN NEW.subagent = 0 AND NEW.model IS NOT NULL BEGIN
  INSERT INTO usage_compactions
    SELECT NEW.at, NEW.model, p.context FROM (
      SELECT b.context, b.profile, b.model FROM usage b
      WHERE b.session = NEW.session AND b.subagent = 0 AND b.at < NEW.at ORDER BY b.at DESC LIMIT 1) p
    WHERE p.context >= ${COMPACTED_FROM} AND NEW.context * 2 < p.context AND p.profile IS NEW.profile AND p.model IS NEW.model;
END;
`;

/// Where a model's context was compacted, at each call it was (pool.ts `cheapToLeave` asks the last days' most): the
/// call's time and model, and the context the call before it left (usage.context). Made once from the calls recorded
/// before (what compactionPoints worked out from every call of the last days, by a window over them, each time it was
/// asked: 4 s on ccvm, 2026-10-25), and kept by a trigger from then on (USAGE_COMPACTIONS_KEPT).
const USAGE_COMPACTIONS = `
CREATE TABLE usage_compactions (
  at INTEGER NOT NULL,
  model TEXT NOT NULL,
  point INTEGER NOT NULL
);
CREATE INDEX usage_compactions_at ON usage_compactions (at);
INSERT INTO usage_compactions
  SELECT at, model, before FROM (
    SELECT at, model, profile, context, LAG(context) OVER w AS before, LAG(profile) OVER w AS was, LAG(model) OVER w AS of
    FROM usage u WHERE subagent = 0 WINDOW w AS (PARTITION BY session ORDER BY at))
  WHERE before >= ${COMPACTED_FROM} AND context * 2 < before AND profile IS was AND model IS of AND model IS NOT NULL;
${USAGE_COMPACTIONS_KEPT}`;

/// The compactions (USAGE_COMPACTIONS), made once from the calls recorded before, in the same transaction as the
/// trigger that keeps them from then on (as addUsageTotals).
export function addUsageCompactions(db: DatabaseSync): void {
  const made = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'usage_compactions'").get() !== undefined;
  if (made()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!made()) db.exec(USAGE_COMPACTIONS);
    db.exec("COMMIT");
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

/// What lists say of each thread and session, kept as what they are made of is written, not read out of every message
/// each time a list is made (every sidebar, every GET /threads and /sessions, every event a viewer is told):
/// - thread_state: a thread's last entry, its latest message that is not a letter (`said_n`), the first a person
///   said (`person_n`), and how many letters it has. Entries only grow, and a thread's go together.
/// - thread_people: who wrote in a thread, each with the first message they wrote there.
/// - session_first: the first message a session was given (its delivery the earliest made).
/// Made once from what is there, in the same transaction as the triggers that keep them from then on (as
/// usage_totals), after the letters were marked (addLetterColumn).
const LIST_STATE = `
CREATE TABLE thread_state (
  thread INTEGER PRIMARY KEY,
  last_n INTEGER NOT NULL,
  said_n INTEGER,
  person_n INTEGER,
  letters INTEGER NOT NULL
);
CREATE TABLE thread_people (
  thread INTEGER NOT NULL,
  author TEXT NOT NULL,
  first_n INTEGER NOT NULL,
  PRIMARY KEY (thread, author)
) WITHOUT ROWID;
CREATE TABLE session_first (
  session TEXT PRIMARY KEY,
  thread INTEGER NOT NULL,
  n INTEGER NOT NULL
) WITHOUT ROWID;
INSERT INTO thread_state
  SELECT thread, MAX(n), MAX(CASE WHEN kind = 'message' AND letter IS NULL THEN n END),
    MIN(CASE WHEN kind = 'message' AND author_kind = 'person' THEN n END), COUNT(CASE WHEN kind = 'message' AND letter IS NOT NULL THEN 1 END)
  FROM entries GROUP BY thread;
INSERT INTO thread_people
  SELECT thread, author, MIN(n) FROM entries WHERE kind = 'message' AND author_kind = 'person' GROUP BY thread, author;
INSERT INTO session_first
  SELECT session, thread, n FROM (SELECT session, thread, n, MIN(rowid) FROM deliveries GROUP BY session);
CREATE TRIGGER thread_state_add AFTER INSERT ON entries BEGIN
  INSERT INTO thread_state VALUES (NEW.thread, NEW.n,
      CASE WHEN NEW.kind = 'message' AND NEW.letter IS NULL THEN NEW.n END,
      CASE WHEN NEW.kind = 'message' AND NEW.author_kind = 'person' THEN NEW.n END,
      CASE WHEN NEW.kind = 'message' AND NEW.letter IS NOT NULL THEN 1 ELSE 0 END)
  ON CONFLICT (thread) DO UPDATE SET
    last_n = MAX(last_n, excluded.last_n),
    said_n = CASE WHEN excluded.said_n IS NULL THEN said_n WHEN said_n IS NULL THEN excluded.said_n ELSE MAX(said_n, excluded.said_n) END,
    person_n = CASE WHEN excluded.person_n IS NULL THEN person_n WHEN person_n IS NULL THEN excluded.person_n ELSE MIN(person_n, excluded.person_n) END,
    letters = letters + excluded.letters;
  INSERT INTO thread_people SELECT NEW.thread, NEW.author, NEW.n WHERE NEW.kind = 'message' AND NEW.author_kind = 'person'
  ON CONFLICT (thread, author) DO UPDATE SET first_n = MIN(first_n, excluded.first_n);
END;
CREATE TRIGGER thread_state_drop AFTER DELETE ON entries BEGIN
  DELETE FROM thread_state WHERE thread = OLD.thread;
  DELETE FROM thread_people WHERE thread = OLD.thread;
END;
CREATE TRIGGER session_first_add AFTER INSERT ON deliveries BEGIN
  INSERT OR IGNORE INTO session_first VALUES (NEW.session, NEW.thread, NEW.n);
END;
CREATE TRIGGER session_first_drop AFTER DELETE ON deliveries
  WHEN EXISTS (SELECT 1 FROM session_first WHERE session = OLD.session AND thread = OLD.thread AND n = OLD.n) BEGIN
  DELETE FROM session_first WHERE session = OLD.session;
  INSERT OR IGNORE INTO session_first SELECT session, thread, n FROM deliveries WHERE session = OLD.session ORDER BY rowid LIMIT 1;
END;
`;

/// Letters (rows.ts Letter): what two chats' agents write each other, kept in a log of their own beside each chat's,
/// numbered from 1 in it, not among what is said in the chat (its entries): a chat's pages, its unread and its latest
/// page are of what it shows alone. Those from before it stay entries marked as letters (addLetterColumn).
/// - letters: a chat's letters both ways, in the order written.
/// - letter_deliveries: a letter coming in handed to the chat's sessions, as deliveries are a message.
const LETTERS = `
CREATE TABLE letters (
  thread INTEGER NOT NULL,
  n INTEGER NOT NULL,
  ts TEXT NOT NULL,
  author_kind TEXT NOT NULL,
  author TEXT NOT NULL,
  text TEXT NOT NULL,
  attachments TEXT,
  at INTEGER NOT NULL,
  letter TEXT NOT NULL,
  PRIMARY KEY (thread, n)
);
CREATE TABLE letter_deliveries (
  thread INTEGER NOT NULL,
  n INTEGER NOT NULL,
  session TEXT NOT NULL,
  delivered_at INTEGER,
  PRIMARY KEY (thread, n, session)
);
CREATE INDEX letter_deliveries_pending ON letter_deliveries (session) WHERE delivered_at IS NULL;
`;

/// The letters' own log (LETTERS), made once (as addListState).
export function addLetters(db: DatabaseSync): void {
  const made = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'letters'").get() !== undefined;
  if (made()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!made()) db.exec(LETTERS);
    db.exec("COMMIT");
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

/// The lists' kept state (LIST_STATE), made once, with its triggers (as addUsageTotals).
export function addListState(db: DatabaseSync): void {
  const made = () => db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'thread_state'").get() !== undefined;
  if (made()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    if (!made()) db.exec(LIST_STATE);
    db.exec("COMMIT");
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

/// The columns a station in several workspaces came with (docs/multi-workspace.md): which workspace a session's chat
/// is in (sessions.ws) and whose archive policy a row is (archive_policy.ws); NULL is the station's home workspace.
export function addWorkspaceColumns(db: DatabaseSync): void {
  if (!has(db, "sessions", "ws")) db.exec("ALTER TABLE sessions ADD COLUMN ws TEXT");
  if (!has(db, "archive_policy", "ws")) db.exec("ALTER TABLE archive_policy ADD COLUMN ws TEXT");
  // The sessions counted by connect and workspace (store.ts SESSION_COUNTS, in every overview): from the index alone.
  db.exec("CREATE INDEX IF NOT EXISTS sessions_by_connect ON sessions (connect, ws)");
}
