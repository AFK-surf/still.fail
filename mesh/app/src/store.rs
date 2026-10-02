//! All durable station state, in one SQLite file (the same file and schema as the Node station's, so a data directory it
//! kept opens here as it is). Runtime transcripts stay in the runtimes' own homes; this records what the station needs to route and resume,
//! and everything said in the threads its sessions take part in.
//!
//! A thread is a log of entries that are appended and never changed (docs/station-storage.md): an edit is an entry of
//! its own, which readers merge into the message it changes. A thread whose sessions are all archived is written out to
//! a zstd file and read from there.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use anyhow::{Result, anyhow, bail};
use rusqlite::{Connection, OptionalExtension, Row, params};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::broadcast;

/// Bump on schema changes. A database of another version is refused: there is one station, and its data is moved by
/// hand when the schema changes (no migrations are kept in the code).
pub const SCHEMA_VERSION: i64 = 12;

/// The page's own threads live on this surface, in this channel (stored under the name of before the rename).
pub const STILLFAIL_SURFACE: &str = "ember";

/// Archived threads whose entries are kept decompressed, the most recently read last.
const ARCHIVE_CACHE: usize = 32;

pub fn now_ms() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

/// Where a Slack connect's threads live: its team, or the connect itself while the team is unknown.
pub fn slack_surface(connect: &str, team_id: Option<&str>) -> String {
    match team_id.filter(|t| !t.is_empty()) {
        Some(team) => format!("slack:{team}"),
        None => format!("slack:{connect}"),
    }
}

// ── rows ───────────────────────────────────────────────────────────────────

/// thread: started by one thread (multi-session connects); all: takes every thread of the connects bound to it.
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum SessionScope {
    Thread,
    All,
}

impl SessionScope {
    fn as_str(self) -> &'static str {
        match self {
            SessionScope::Thread => "thread",
            SessionScope::All => "all",
        }
    }
}

#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SessionRow {
    pub key: String,
    /// The connect that started it ("ember" for the page). Replies go through the connect each thread came from.
    pub connect: String,
    pub scope: SessionScope,
    /// A name people gave it, for choosing among single-session sessions.
    pub title: Option<String>,
    /// Who started it: "slack:<connect>:<user>" for a chat message, an email for someone on still.fail cloud, "local" for the
    /// station's own page; None if unknown.
    pub created_by: Option<String>,
    pub runtime: String,
    /// The profile it last ran on.
    pub profile: String,
    /// Kept to `profile` by hand; otherwise the station picks one each time it starts.
    pub profile_pinned: bool,
    pub model: Option<String>,
    /// Reasoning effort, as the connect set it when the session started; None for the runtime's default.
    pub effort: Option<String>,
    /// None follows the subscription default; false explicitly uses standard speed.
    pub fast: Option<bool>,
    pub runtime_session_id: Option<String>,
    pub workspace: String,
    /// Where its runtime runs when that is not the workspace: the project directory of a session begun outside still.fail
    /// and continued here (Hub::continue_machine_session). The workspace stays the station's, for uploads and jobs.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    #[serde(skip)]
    pub token: String,
    /// A turn was running when this was last written; true after a crash means the turn was cut off.
    pub running: bool,
    pub created_at: i64,
    pub last_active_at: i64,
    /// Hidden from lists since then; None while shown.
    pub archived_at: Option<i64>,
    /// Who archived it: a person ("manual"), or the station once it had idled long enough ("auto").
    pub archived_by: Option<String>,
    /// When it was last shown again by hand: the station's idle clock starts over from then (Hub::auto_archive).
    pub shown_at: Option<i64>,
}

/// Archived by a person.
pub const MANUAL: &str = "manual";
/// Archived by the station, for idling (or brought back by something said).
pub const AUTO: &str = "auto";

/// A session as it is first recorded.
#[derive(Debug, Clone, Default)]
pub struct NewSession {
    pub key: String,
    pub connect: String,
    pub scope: Option<SessionScope>,
    pub title: Option<String>,
    pub created_by: Option<String>,
    pub runtime: String,
    pub profile: String,
    pub profile_pinned: bool,
    pub model: Option<String>,
    pub effort: Option<String>,
    /// None follows the subscription default; false explicitly uses standard speed.
    pub fast: Option<bool>,
    pub workspace: String,
    pub cwd: Option<String>,
    pub runtime_session_id: Option<String>,
    pub token: String,
    pub created_at: i64,
    pub last_active_at: i64,
}

/// A place people talk: a Slack thread, or a chat on the station's page.
#[derive(Serialize, Debug, Clone, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadRow {
    pub id: i64,
    /// "slack:<team id>" (or "slack:<connect id>" while the team is unknown), or "ember".
    pub surface: String,
    /// Slack channel id; "EMBER" on the page.
    pub channel: String,
    pub thread_ts: String,
    pub title: Option<String>,
    /// The name its agent gave it (chat_post's title), shown while people have given it none.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub auto_title: Option<String>,
    pub created_by: Option<String>,
    pub created_at: i64,
    /// A chat on the page made for a session (the first one it has there): that session's own, archived and shown with
    /// it. None for a chat of its own (another one opened with a session, whichever sessions join it) and Slack threads.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub home: Option<String>,
    /// A chat archived from lists since then: with its session (its home's), or alone.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hidden_at: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hidden_by: Option<String>,
    /// When a chat of its own was last shown again by hand, as a session's shown_at.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub shown_at: Option<i64>,
}

/// The name a chat's agent gave it (Store::auto_title).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct AutoTitle {
    pub title: Option<String>,
    /// The thread's last entry when it was given.
    pub n: i64,
    /// How often it was changed after the first.
    pub changes: i64,
}

/// A thread of a session, with the connect the session posts there through.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionThread {
    pub thread: ThreadRow,
    pub connect: String,
}

/// A session in a thread, and the connect it posts there through.
#[derive(Serialize, Debug, Clone, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Membership {
    pub thread: i64,
    pub session: String,
    pub connect: String,
    pub joined_at: i64,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum AuthorKind {
    Person,
    Agent,
    /// The station itself (named, stored and sent as before the rename).
    #[serde(rename = "ember")]
    StillFail,
}

impl AuthorKind {
    pub fn as_str(self) -> &'static str {
        match self {
            AuthorKind::Person => "person",
            AuthorKind::Agent => "agent",
            AuthorKind::StillFail => "ember",
        }
    }
    fn parse(s: &str) -> AuthorKind {
        match s {
            "agent" => AuthorKind::Agent,
            "ember" => AuthorKind::StillFail,
            _ => AuthorKind::Person,
        }
    }
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum EntryKind {
    Message,
    Edit,
}

/// A passage quoted from an earlier message, and what the sender says about it.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct Quote {
    pub author: String,
    pub text: String,
    pub comment: String,
    /// The quoted message's id (its ts) and whose it is, so the agent knows exactly what is quoted.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub ts: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub role: Option<String>,
    /// The name of the file, among the message's attachments, that goes with it (a preview mark's screenshot).
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub file: Option<String>,
}

/// A file someone sent to a session; `path` is where the agent finds it on the station.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct Attachment {
    pub name: String,
    pub path: String,
    pub size: u64,
    /// An image's pixel size, measured by the sender, so the page can hold its place before it loads.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub width: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub height: Option<u32>,
    /// An image's ThumbHash (base64), made by the station as it keeps it: shown blurred until the image loads.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub thumbhash: Option<String>,
}

/// One entry of a thread's log (as the archive files hold them, one per line). Entries are only ever appended; they go
/// only with their whole thread.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct EntryRow {
    pub thread: i64,
    /// 1, 2, 3 … within the thread, no gaps.
    pub n: i64,
    pub kind: EntryKind,
    /// edit: the n of the message it changes.
    pub target: Option<i64>,
    /// message: the platform's id (Slack ts; the station makes Slack-like ones), unique in the thread.
    pub ts: Option<String>,
    /// message: who said it; edit: whose message it changes.
    pub author_kind: AuthorKind,
    /// person: Slack user id, email or "local"; agent: session key; ember: "ember".
    pub author: String,
    pub text: Option<String>,
    /// The files and quotes it has (an edit gives the message's whole new version).
    pub attachments: Vec<Attachment>,
    pub quotes: Vec<Quote>,
    /// message: an agent's final or block, posted with it.
    pub declared: Option<String>,
    /// message: the still.fail app a person sent it from ("android 0.1.1123"); None elsewhere and from older apps.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub client: Option<String>,
    /// message: for still.fail's notice about one of the station's profiles (its sign-in failed), that profile's id.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub profile: Option<String>,
    /// message: an agent's post with an options card, the answers to pick from: `[{label, detail?, recommended?}]`, as
    /// `card.options` (what clients from before cards read). None for every other message.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub options: Option<Value>,
    /// message: the card an agent's post carries (chat_post `card`): `{type: "options", options}` or `{type: "text",
    /// placeholder?}`. None for every other message (and from stations before cards: their `options` are an options
    /// card, see [`EntryRow::card`]).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub card: Option<Value>,
    pub at: i64,
}

impl EntryRow {
    /// The card it carries: its own, else its options as an options card (a post from before cards).
    pub fn card(&self) -> Option<Value> {
        self.card.clone().or_else(|| self.options.as_ref().map(|o| options_card(o.clone())))
    }
}

/// Options to pick from as a card.
pub fn options_card(options: Value) -> Value {
    serde_json::json!({ "type": "options", "options": options })
}

/// A message's card as kept: its `card` column, else its `options` (from before cards) as an options card.
fn card_of(card: Option<String>, options: Option<String>) -> Option<Value> {
    card.and_then(|c| serde_json::from_str(&c).ok()).or_else(|| options.and_then(|o| serde_json::from_str(&o).ok()).map(options_card))
}

/// A message as it reads now: its latest edit's words, files and quotes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MessageRow {
    pub thread: i64,
    /// Its entry's n.
    pub n: i64,
    pub ts: String,
    pub author_kind: AuthorKind,
    pub author: String,
    pub text: String,
    pub attachments: Vec<Attachment>,
    pub quotes: Vec<Quote>,
    pub declared: Option<String>,
    /// The still.fail app a person sent it from, if one said.
    pub client: Option<String>,
    pub created_at: i64,
    /// When its latest edit came; None if never edited.
    pub edited_at: Option<i64>,
}

/// A card someone answered (`answers_since`): the post that asked and its card, who answered and when, and with what:
/// their message, or none when a choice closed it (an option with action close).
#[derive(Debug, Clone)]
pub struct CardAnswer {
    pub question: MessageRow,
    pub card: Value,
    pub by: String,
    pub at: i64,
    pub answer: Option<MessageRow>,
}

/// A message a session has yet to read, with where it was said and how the session hears that thread.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PendingMessage {
    pub message: MessageRow,
    pub surface: String,
    pub channel: String,
    pub thread_ts: String,
    /// The connect the session hears this thread through.
    pub connect: String,
}

/// A thread for listings: who takes part, the last thing said, and how much the viewer has not read.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ThreadSummary {
    pub thread: ThreadRow,
    pub sessions: Vec<Membership>,
    /// The thread's last entry number, 0 before anything is said.
    pub last: i64,
    /// The latest message as merged, for lists.
    pub last_message: Option<MessageRow>,
    /// The viewer's read position (an entry number), 0 if never read.
    pub read: i64,
    /// Messages after the read position that are not the viewer's own (nor of a Slack user they are).
    pub unread: i64,
    /// Everyone who wrote in it, as creator references, earliest first.
    pub people: Vec<String>,
    /// The first thing a person said in it (the start of it), for a title.
    pub first_text: Option<String>,
}

#[derive(Serialize, Debug, Clone, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TurnSummary {
    pub kind: String,
    pub outcome: Option<String>,
    /// How the agent ended it, in the words from before (final, block, waiting): what clients from before read.
    pub declared: Option<String>,
    /// How the agent ended it: all_done, need_decision, need_help or waiting (a turn from before them as its words
    /// mean: final all_done, block need_help).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ending: Option<String>,
    /// For need_help: what a person has to give or do, in the agent's words; for all_done, what the chat ends with.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub need: Option<String>,
    /// The message its state is about (chat_post / chat_state `about`; for need_help, the pending card by default).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub about: Option<TurnAbout>,
    /// For waiting: at most how long, in seconds, until the agent is asked again.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub wait_seconds: Option<i64>,
    /// For waiting: what it waits for, in the agent's words.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub wait_for: Option<String>,
    pub detail: Option<String>,
    pub started_at: i64,
    pub ended_at: Option<i64>,
}

/// The message a turn's state is about: its thread, entry (`seq`, as the clients number messages) and ts.
#[derive(Serialize, Debug, Clone, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TurnAbout {
    pub thread: i64,
    pub seq: i64,
    pub ts: String,
}

fn to_about(r: &Row) -> rusqlite::Result<Option<TurnAbout>> {
    let (thread, n, ts): (Option<i64>, Option<i64>, Option<String>) = (r.get("about_thread")?, r.get("about_n")?, r.get("about_ts")?);
    Ok(match (thread, n, ts) {
        (Some(thread), Some(seq), Some(ts)) => Some(TurnAbout { thread, seq, ts }),
        _ => None,
    })
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TurnRow {
    pub id: String,
    pub summary: TurnSummary,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionStats {
    pub turns: i64,
    pub pending: i64,
    pub first_text: Option<String>,
    pub last_turn: Option<TurnSummary>,
}

/// A profile's last check and quota, kept across restarts (their shapes are the checks' and quotas' own).
#[derive(Debug, Clone, PartialEq, Default)]
pub struct ProfileStatus {
    pub check: Option<Value>,
    pub quota: Option<Value>,
}

#[derive(Serialize, Debug, Clone, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProcessRow {
    pub pgid: i64,
    pub started_at: i64,
    pub runtime: String,
    pub label: String,
}

/// A message an agent posted, for its session's execution history.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Post {
    pub thread: i64,
    pub n: i64,
    pub channel: String,
    pub thread_ts: String,
    pub text: String,
    pub attachments: Vec<Attachment>,
    pub declared: Option<String>,
    pub at: i64,
}

/// How a turn ended or a post was declared (turns.declared, entries.declared) in the words from before all_done,
/// need_decision and need_help: final, block, waiting. What clients from before read, and the station's checks of it.
pub fn said_before(declared: &str) -> &str {
    match declared {
        "all_done" => "final",
        "need_decision" | "need_help" => "block",
        other => other,
    }
}

/// The same in today's words: final is all_done, block need_help; need_decision (before cards: a post with options that
/// ended the turn) need_help too.
pub fn ending(declared: &str) -> &str {
    match declared {
        "final" => "all_done",
        "block" | "need_decision" => "need_help",
        other => other,
    }
}

/// A message being recorded.
#[derive(Debug, Clone)]
pub struct NewMessage {
    pub thread: i64,
    pub ts: String,
    pub author_kind: AuthorKind,
    pub author: String,
    pub text: String,
    pub attachments: Vec<Attachment>,
    pub quotes: Vec<Quote>,
    pub declared: Option<String>,
    pub client: Option<String>,
    /// still.fail's notice about a profile: its id (EntryRow::profile).
    pub profile: Option<String>,
    /// The card an agent's post carries (EntryRow::card); an options card is kept as `options` too.
    pub card: Option<Value>,
    /// Answers to pick from, as said before cards: an options card (EntryRow::options).
    pub options: Option<Value>,
    pub at: Option<i64>,
}

impl NewMessage {
    pub fn new(thread: i64, ts: &str, author_kind: AuthorKind, author: &str, text: &str) -> NewMessage {
        NewMessage { thread, ts: ts.into(), author_kind, author: author.into(), text: text.into(), attachments: vec![], quotes: vec![], declared: None, client: None, profile: None, card: None, options: None, at: None }
    }
}

/// A background job a session started (jobs.rs): a command the station runs and keeps, a web service when it has a
/// port.
#[derive(Serialize, Debug, Clone, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct JobRow {
    pub id: String,
    #[serde(rename = "session")]
    pub session_key: String,
    pub name: String,
    pub command: String,
    pub cwd: String,
    pub port: Option<i64>,
    /// What `stillfail-job notify` presents; not for the pages.
    #[serde(skip)]
    pub token: String,
    /// running | exited (ended by itself) | stopped (by request) | failed (could not start)
    pub state: String,
    pub pgid: Option<i64>,
    pub exit_code: Option<i64>,
    pub started_at: i64,
    pub ended_at: Option<i64>,
    /// How often a service was started again after it ended.
    pub restarts: i64,
    /// Its output, as a file.
    pub log: String,
    /// Started to keep watch (`job_start` with watch): while it runs, its chat is a watching one (not archived when
    /// idle, its agent not asked again when its wait is over, apart in the lists).
    pub watch: bool,
}

/// How many of a job's notices are kept.
const JOB_NOTICES: i64 = 50;

/// Something a job said, and when.
#[derive(Serialize, Debug, Clone, PartialEq, Eq)]
pub struct JobNotice {
    pub at: i64,
    pub text: String,
}

/// What a person chose in a widget an agent posted (an HTML file placed in its message), for the agent to hear of
/// with its next messages.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WidgetModel {
    /// The file's path, as attached.
    pub path: String,
    /// Its name as attached, else the path's last part.
    pub name: String,
    /// The thread it was posted in (channel, thread ts), when its message is still in the database.
    pub thread: Option<(String, String)>,
    /// What the widget said is for the agent (its state's modelContent).
    pub model: String,
}

fn job_row(r: &rusqlite::Row) -> rusqlite::Result<JobRow> {
    Ok(JobRow {
        id: r.get("id")?,
        session_key: r.get("session_key")?,
        name: r.get("name")?,
        command: r.get("command")?,
        cwd: r.get("cwd")?,
        port: r.get("port")?,
        token: r.get("token")?,
        state: r.get("state")?,
        pgid: r.get("pgid")?,
        exit_code: r.get("exit_code")?,
        started_at: r.get("started_at")?,
        ended_at: r.get("ended_at")?,
        restarts: r.get("restarts")?,
        log: r.get("log")?,
        watch: r.get::<_, i64>("watch")? != 0,
    })
}

/// Whom a turn works for (Store::start_turn_for).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TurnFor {
    pub profile: Option<String>,
    /// A creator reference: an email, or "slack:<connect>:<user>".
    pub person: Option<String>,
    pub thread: Option<i64>,
}

/// What the store says changed, for whoever follows it (the admin API's /events, the hub).
#[derive(Debug, Clone, PartialEq)]
pub enum StoreChange {
    /// Anything about that session changed.
    Session(String),
    /// It was deleted.
    SessionRemoved(String),
    /// Entries were appended there (contiguous, in order), or its sessions changed (none).
    Thread { id: i64, entries: Vec<EntryRow> },
    /// It went, with every entry it had.
    ThreadRemoved(i64),
    /// A viewer's read position moved.
    Read { viewer: String, thread: i64, n: i64 },
    /// The Slack users a viewer said are them changed.
    Identities(String),
    /// The chats a viewer pinned changed.
    Pins(String),
    /// The decisions a viewer dismissed changed.
    Dismissed(String),
    /// The recorded runtime processes changed.
    Processes,
    /// A background job started, started again, ended or said something (its session changes as well).
    Job(String),
    /// A job that was over was taken off its session's record (cleared from the pages).
    JobRemoved { id: String, session: String },
    /// Model calls were recorded (store/usage.rs).
    Usage,
}

// ── schema ─────────────────────────────────────────────────────────────────

const SCHEMA: &str = r#"
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
  watch INTEGER NOT NULL DEFAULT 0
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
-- How far each transcript has been read for it.
CREATE TABLE IF NOT EXISTS usage_files (
  path TEXT PRIMARY KEY,
  session TEXT,
  offset INTEGER NOT NULL,
  model TEXT
);
"#;

fn json_list<T: Serialize>(value: &[T]) -> Option<String> {
    if value.is_empty() { None } else { serde_json::to_string(value).ok() }
}

fn from_json_list<T: for<'de> Deserialize<'de>>(text: Option<String>) -> Vec<T> {
    text.and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
}

fn to_session(r: &Row) -> rusqlite::Result<SessionRow> {
    Ok(SessionRow {
        key: r.get("key")?,
        connect: r.get("connect")?,
        scope: if r.get::<_, String>("scope")? == "all" { SessionScope::All } else { SessionScope::Thread },
        title: r.get("title")?,
        created_by: r.get("created_by")?,
        runtime: r.get("runtime")?,
        profile: r.get("profile")?,
        profile_pinned: r.get::<_, i64>("profile_pinned")? == 1,
        model: r.get("model")?,
        effort: r.get("effort")?,
        fast: r.get("fast")?,
        runtime_session_id: r.get("runtime_session_id")?,
        workspace: r.get("workspace")?,
        cwd: r.get("cwd")?,
        token: r.get("token")?,
        running: r.get::<_, i64>("running")? == 1,
        created_at: r.get("created_at")?,
        last_active_at: r.get("last_active_at")?,
        archived_at: r.get("archived_at")?,
        archived_by: r.get("archived_by")?,
        shown_at: r.get("shown_at")?,
    })
}

fn to_thread(r: &Row) -> rusqlite::Result<ThreadRow> {
    Ok(ThreadRow {
        id: r.get("id")?,
        surface: r.get("surface")?,
        channel: r.get("channel")?,
        thread_ts: r.get("thread_ts")?,
        title: r.get("title")?,
        auto_title: r.get("auto_title")?,
        created_by: r.get("created_by")?,
        created_at: r.get("created_at")?,
        home: r.get("home")?,
        hidden_at: r.get("hidden_at")?,
        hidden_by: r.get("hidden_by")?,
        shown_at: r.get("shown_at")?,
    })
}

/// Columns archiving came with, added to a database made before them (same schema version: a station without them
/// opens it as it is). When they come, each session's first chat on the page is taken as its own, and chats of
/// sessions archived then as archived with them.
fn add_archive_columns(db: &Connection) -> Result<()> {
    let has = |table: &str, column: &str| -> Result<bool> {
        let mut stmt = db.prepare(&format!("SELECT 1 FROM pragma_table_info('{table}') WHERE name = ?"))?;
        Ok(stmt.exists([column])?)
    };
    for (column, kind) in [("archived_by", "TEXT"), ("shown_at", "INTEGER"), ("cwd", "TEXT"), ("fast", "INTEGER")] {
        if !has("sessions", column)? {
            db.execute_batch(&format!("ALTER TABLE sessions ADD COLUMN {column} {kind}"))?;
        }
    }
    // Came with waiting's limit, after the turns table.
    if !has("turns", "wait_seconds")? {
        db.execute_batch("ALTER TABLE turns ADD COLUMN wait_seconds INTEGER")?;
    }
    // Came with saying what a wait is for (chat_state waiting `for`).
    if !has("turns", "wait_for")? {
        db.execute_batch("ALTER TABLE turns ADD COLUMN wait_for TEXT")?;
    }
    // Came with migration notes (migrations.rs): the last one each session was told. A session from before them was told
    // none.
    if !has("sessions", "told_notes")? {
        db.execute_batch("ALTER TABLE sessions ADD COLUMN told_notes INTEGER")?;
    }
    // Came with need_help's `need`: what a person has to give or do.
    if !has("turns", "need")? {
        db.execute_batch("ALTER TABLE turns ADD COLUMN need TEXT")?;
    }
    // Came with `about`: the message a turn's state is about.
    for (column, kind) in [("about_thread", "INTEGER"), ("about_n", "INTEGER"), ("about_ts", "TEXT")] {
        if !has("turns", column)? {
            db.execute_batch(&format!("ALTER TABLE turns ADD COLUMN {column} {kind}"))?;
        }
    }
    // Came with usage (store/usage.rs): whom a turn worked for, where, and on which profile.
    for (column, kind) in [("profile", "TEXT"), ("person", "TEXT"), ("thread", "INTEGER")] {
        if !has("turns", column)? {
            db.execute_batch(&format!("ALTER TABLE turns ADD COLUMN {column} {kind}"))?;
        }
    }
    if has("threads", "home")? {
        return Ok(());
    }
    db.execute_batch(
        "BEGIN;
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
         COMMIT;",
    )?;
    Ok(())
}

/// Each message as it reads now: its latest edit's words, files and quotes.
const MERGED: &str = "CREATE VIEW merged AS
  SELECT m.thread, m.n, m.ts, m.author_kind, m.author,
    CASE WHEN e.n IS NULL THEN m.text ELSE e.text END AS text,
    CASE WHEN e.n IS NULL THEN m.attachments ELSE e.attachments END AS attachments,
    CASE WHEN e.n IS NULL THEN m.quotes ELSE e.quotes END AS quotes,
    m.declared, m.client, m.at AS created_at, e.at AS edited_at
  FROM entries m
  LEFT JOIN entries e ON e.thread = m.thread
    AND e.n = (SELECT MAX(x.n) FROM entries x WHERE x.thread = m.thread AND x.target = m.n)
  WHERE m.kind = 'message';";

/// The column a message's app came with (entries.client), added to a database made before it the same way as
/// add_archive_columns' (a station without it reads the database as it is), and the `merged` view made anew with it.
fn add_client_column(db: &Connection) -> Result<()> {
    let has = |table: &str, column: &str| -> Result<bool> {
        let mut stmt = db.prepare(&format!("SELECT 1 FROM pragma_table_info('{table}') WHERE name = ?"))?;
        Ok(stmt.exists([column])?)
    };
    if !has("entries", "client")? {
        db.execute_batch("ALTER TABLE entries ADD COLUMN client TEXT")?;
    }
    // The profile a notice is about (entries.profile) came later, the same way; the `merged` view has no need of it.
    if !has("entries", "profile")? {
        db.execute_batch("ALTER TABLE entries ADD COLUMN profile TEXT")?;
    }
    // A block post's answers to pick from (entries.options) came later, the same way; the `merged` view has no need of
    // them (a decision is read from its entry).
    if !has("entries", "options")? {
        db.execute_batch("ALTER TABLE entries ADD COLUMN options TEXT")?;
    }
    // A message's card (entries.card) came later, the same way; an options card is kept in `options` too, which
    // stations from before cards read.
    if !has("entries", "card")? {
        db.execute_batch("ALTER TABLE entries ADD COLUMN card TEXT")?;
    }
    // A chat's latest card is looked for on every list of chats: only its posts with one are read.
    db.execute_batch("CREATE INDEX IF NOT EXISTS entries_options ON entries (thread, n) WHERE options IS NOT NULL")?;
    db.execute_batch("CREATE INDEX IF NOT EXISTS entries_cards ON entries (thread, n) WHERE card IS NOT NULL")?;
    // What people said lately is looked for on every list of chats (the cards they answered: `answers_since`).
    db.execute_batch("CREATE INDEX IF NOT EXISTS entries_people_at ON entries (at) WHERE author_kind = 'person' AND kind = 'message'")?;
    if !has("merged", "client")? {
        db.execute_batch(&format!("BEGIN; DROP VIEW IF EXISTS merged; {MERGED} COMMIT;"))?;
    }
    Ok(())
}

/// The columns a chat's own name from its agent came with (threads.auto_title…), added to a database made before them
/// the same way as add_archive_columns' (a station without them reads the database as it is).
fn add_auto_title_columns(db: &Connection) -> Result<()> {
    let has = |column: &str| -> Result<bool> {
        let mut stmt = db.prepare("SELECT 1 FROM pragma_table_info('threads') WHERE name = ?")?;
        Ok(stmt.exists([column])?)
    };
    for (column, kind) in [("auto_title", "TEXT"), ("auto_title_n", "INTEGER"), ("auto_title_changes", "INTEGER NOT NULL DEFAULT 0")] {
        if !has(column)? {
            db.execute_batch(&format!("ALTER TABLE threads ADD COLUMN {column} {kind}"))?;
        }
    }
    Ok(())
}

/// The column watching jobs came with (jobs.watch), added to a database made before them the same way as
/// add_archive_columns' (a station without them reads the database as it is, and its jobs are not watches).
fn add_watch_column(db: &Connection) -> Result<()> {
    let mut stmt = db.prepare("SELECT 1 FROM pragma_table_info('jobs') WHERE name = 'watch'")?;
    if !stmt.exists([])? {
        db.execute_batch("ALTER TABLE jobs ADD COLUMN watch INTEGER NOT NULL DEFAULT 0")?;
    }
    Ok(())
}

fn to_session_thread(r: &Row) -> rusqlite::Result<SessionThread> {
    Ok(SessionThread { thread: to_thread(r)?, connect: r.get("connect")? })
}

fn to_membership(r: &Row) -> rusqlite::Result<Membership> {
    Ok(Membership { thread: r.get("thread")?, session: r.get("session")?, connect: r.get("connect")?, joined_at: r.get("joined_at")? })
}

fn to_entry(r: &Row) -> rusqlite::Result<EntryRow> {
    Ok(EntryRow {
        thread: r.get("thread")?,
        n: r.get("n")?,
        kind: if r.get::<_, String>("kind")? == "edit" { EntryKind::Edit } else { EntryKind::Message },
        target: r.get("target")?,
        ts: r.get("ts")?,
        author_kind: AuthorKind::parse(&r.get::<_, String>("author_kind")?),
        author: r.get("author")?,
        text: r.get("text")?,
        attachments: from_json_list(r.get("attachments")?),
        quotes: from_json_list(r.get("quotes")?),
        declared: r.get("declared")?,
        client: r.get("client")?,
        profile: r.get("profile")?,
        options: r.get::<_, Option<String>>("options")?.and_then(|o| serde_json::from_str(&o).ok()),
        card: r.get::<_, Option<String>>("card")?.and_then(|c| serde_json::from_str(&c).ok()),
        at: r.get("at")?,
    })
}

fn to_message(r: &Row) -> rusqlite::Result<MessageRow> {
    Ok(MessageRow {
        thread: r.get("thread")?,
        n: r.get("n")?,
        ts: r.get::<_, Option<String>>("ts")?.unwrap_or_default(),
        author_kind: AuthorKind::parse(&r.get::<_, String>("author_kind")?),
        author: r.get("author")?,
        text: r.get::<_, Option<String>>("text")?.unwrap_or_default(),
        attachments: from_json_list(r.get("attachments")?),
        quotes: from_json_list(r.get("quotes")?),
        declared: r.get("declared")?,
        client: r.get("client")?,
        created_at: r.get("created_at")?,
        edited_at: r.get("edited_at")?,
    })
}

/// Entries merged into their messages, as the `merged` view does: for a thread read from its archive file.
fn merge_entries(entries: &[EntryRow]) -> Vec<MessageRow> {
    let mut messages: BTreeMap<i64, MessageRow> = BTreeMap::new();
    for e in entries {
        match e.kind {
            EntryKind::Message => {
                messages.insert(
                    e.n,
                    MessageRow {
                        thread: e.thread,
                        n: e.n,
                        ts: e.ts.clone().unwrap_or_default(),
                        author_kind: e.author_kind,
                        author: e.author.clone(),
                        text: e.text.clone().unwrap_or_default(),
                        attachments: e.attachments.clone(),
                        quotes: e.quotes.clone(),
                        declared: e.declared.clone(),
                        client: e.client.clone(),
                        created_at: e.at,
                        edited_at: None,
                    },
                );
            }
            EntryKind::Edit => {
                if let Some(m) = e.target.and_then(|t| messages.get_mut(&t)) {
                    m.text = e.text.clone().unwrap_or_default();
                    m.attachments = e.attachments.clone();
                    m.quotes = e.quotes.clone();
                    m.edited_at = Some(e.at);
                }
            }
        }
    }
    messages.into_values().collect()
}

/// Writes a file compressed with zstd: aside first, then renamed into place.
pub fn write_compressed(path: &Path, text: &str) -> Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = PathBuf::from(format!("{}.tmp", path.display()));
    std::fs::write(&tmp, zstd::encode_all(text.as_bytes(), 3)?)?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

// ── the store ──────────────────────────────────────────────────────────────

struct Inner {
    db: Connection,
    /// Where archived threads (and sessions' transcript copies) are written.
    archive_dir: PathBuf,
    /// Entries of archived threads read lately (they never change), the most recent last.
    archived: Vec<(i64, Vec<EntryRow>)>,
}

pub struct Store {
    inner: Mutex<Inner>,
    changes: broadcast::Sender<StoreChange>,
    /// Kept alive when the archive dir is a temporary one (an in-memory store).
    _temp: Option<tempdir::TempDir>,
}

mod tempdir {
    /// A directory removed when dropped: an in-memory store's archive.
    pub struct TempDir(pub std::path::PathBuf);
    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
}

type Changes = Vec<StoreChange>;

impl Store {
    /// Opens the store at `path` (":memory:" for one of its own); archived threads go to `archive`, else `archive/`
    /// beside the database.
    pub fn open(path: &str, archive: Option<&Path>) -> Result<Store> {
        let memory = path == ":memory:";
        if !memory {
            if let Some(dir) = Path::new(path).parent() {
                std::fs::create_dir_all(dir)?;
            }
        }
        let db = if memory { Connection::open_in_memory()? } else { Connection::open(path)? };
        db.execute_batch("PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;")?;
        let has_tables = db.query_row("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sessions'", [], |_| Ok(())).optional()?.is_some();
        if has_tables {
            let version: i64 = db.query_row("PRAGMA user_version", [], |r| r.get(0))?;
            if version != SCHEMA_VERSION {
                bail!("{path} has schema version {version}; this station uses {SCHEMA_VERSION}. Move its data by hand, or move it aside.");
            }
        }
        db.execute_batch(SCHEMA)?;
        add_archive_columns(&db)?;
        add_client_column(&db)?;
        add_auto_title_columns(&db)?;
        add_watch_column(&db)?;
        db.execute_batch(&format!("PRAGMA user_version = {SCHEMA_VERSION}"))?;
        let (archive_dir, temp) = match archive {
            Some(dir) => (dir.to_path_buf(), None),
            None if memory => {
                let mut bytes = [0u8; 8];
                getrandom::fill(&mut bytes).map_err(|e| anyhow!("{e}"))?;
                let dir = std::env::temp_dir().join(format!("stillfail-archive-{}", hex::encode(bytes)));
                std::fs::create_dir_all(&dir)?;
                (dir.clone(), Some(tempdir::TempDir(dir)))
            }
            None => (Path::new(path).parent().unwrap_or(Path::new(".")).join("archive"), None),
        };
        Ok(Store { inner: Mutex::new(Inner { db, archive_dir, archived: Vec::new() }), changes: broadcast::channel(4096).0, _temp: temp })
    }

    /// Hears what changes from now on.
    pub fn subscribe(&self) -> broadcast::Receiver<StoreChange> {
        self.changes.subscribe()
    }

    /// Where archived threads and transcript copies go (`threads/`, `transcripts/`).
    pub fn archive_dir(&self) -> PathBuf {
        self.inner.lock().unwrap().archive_dir.clone()
    }

    fn with<T>(&self, run: impl FnOnce(&mut Inner, &mut Changes) -> Result<T>) -> Result<T> {
        let mut changes = Vec::new();
        let result = {
            let mut inner = self.inner.lock().unwrap();
            run(&mut inner, &mut changes)
        };
        for change in changes {
            let _ = self.changes.send(change);
        }
        result
    }

    /// Announces a change the station keeps outside the database (e.g. a runtime process ending).
    pub fn notify(&self, session: &str) {
        let _ = self.changes.send(StoreChange::Session(session.to_string()));
    }

    // ── sessions ───────────────────────────────────────────────────────────

    pub fn get_session(&self, key: &str) -> Result<Option<SessionRow>> {
        self.with(|i, _| Ok(i.db.query_row("SELECT * FROM sessions WHERE key = ?", [key], to_session).optional()?))
    }

    pub fn session_by_token(&self, token: &str) -> Result<Option<SessionRow>> {
        self.with(|i, _| Ok(i.db.query_row("SELECT * FROM sessions WHERE token = ?", [token], to_session).optional()?))
    }

    /// Every session, most recently active first.
    pub fn list_sessions(&self) -> Result<Vec<SessionRow>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT * FROM sessions ORDER BY last_active_at DESC")?;
            Ok(stmt.query_map([], to_session)?.collect::<rusqlite::Result<_>>()?)
        })
    }

    pub fn insert_session(&self, s: &NewSession) -> Result<()> {
        self.with(|i, changes| {
            i.db.execute(
                "INSERT INTO sessions (key, connect, scope, title, created_by, runtime, profile, profile_pinned, model, effort, workspace, cwd, runtime_session_id, token, created_at, last_active_at, told_notes, fast)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                params![
                    s.key, s.connect, s.scope.unwrap_or(SessionScope::Thread).as_str(), s.title, s.created_by, s.runtime, s.profile,
                    s.profile_pinned as i64, s.model, s.effort, s.workspace, s.cwd, s.runtime_session_id, s.token, s.created_at, s.last_active_at,
                    // A new session begins with today's instructions: no note is news to it.
                    crate::migrations::latest(), s.fast
                ],
            )?;
            changes.push(StoreChange::Session(s.key.clone()));
            Ok(())
        })
    }

    /// The messages a session's agent posted, in every thread, oldest first: its execution history's record of them.
    pub fn posts_by(&self, key: &str) -> Result<Vec<Post>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare(
                "SELECT e.thread, e.n, t.channel, t.thread_ts, e.text, e.attachments, e.declared, e.at FROM entries e JOIN threads t ON t.id = e.thread
                 WHERE e.kind = 'message' AND e.author_kind = 'agent' AND e.author = ? ORDER BY e.at, e.thread, e.n",
            )?;
            let rows = stmt.query_map([key], |r| {
                Ok(Post {
                    thread: r.get(0)?,
                    n: r.get(1)?,
                    channel: r.get(2)?,
                    thread_ts: r.get(3)?,
                    text: r.get::<_, Option<String>>(4)?.unwrap_or_default(),
                    attachments: from_json_list(r.get(5)?),
                    declared: r.get(6)?,
                    at: r.get(7)?,
                })
            })?;
            Ok(rows.collect::<rusqlite::Result<_>>()?)
        })
    }

    /// Moves a session to another profile (its transcripts are shared by its runtime's profiles); `pinned` keeps it there.
    pub fn set_session_profile(&self, key: &str, profile: &str, pinned: bool) -> Result<()> {
        self.update_session(key, "UPDATE sessions SET profile = ?1, profile_pinned = ?2 WHERE key = ?3", params![profile, pinned as i64, key])
    }

    /// A session's model and effort from its next start on (None: the runtime's default).
    pub fn set_session_model(&self, key: &str, model: Option<&str>, effort: Option<&str>) -> Result<()> {
        self.update_session(key, "UPDATE sessions SET model = ?1, effort = ?2 WHERE key = ?3", params![model, effort, key])
    }

    pub fn set_session_fast(&self, key: &str, fast: Option<bool>) -> Result<()> {
        self.update_session(key, "UPDATE sessions SET fast = ?1 WHERE key = ?2", params![fast, key])
    }

    pub fn codex_session_fast(&self, thread: &str) -> Result<Option<bool>> {
        self.with(|i, _| {
            Ok(i.db.query_row("SELECT fast FROM sessions WHERE runtime = 'codex' AND runtime_session_id = ?", [thread], |r| r.get::<_, Option<bool>>(0)).optional()?.flatten())
        })
    }

    pub fn set_title(&self, key: &str, title: Option<&str>) -> Result<()> {
        self.update_session(key, "UPDATE sessions SET title = ?1 WHERE key = ?2", params![title, key])
    }

    pub fn set_runtime_session_id(&self, key: &str, id: &str) -> Result<()> {
        self.update_session(key, "UPDATE sessions SET runtime_session_id = ?1 WHERE key = ?2", params![id, key])
    }

    pub fn set_running(&self, key: &str, running: bool) -> Result<()> {
        self.update_session(key, "UPDATE sessions SET running = ?1, last_active_at = ?2 WHERE key = ?3", params![running as i64, now_ms(), key])
    }

    fn update_session(&self, key: &str, sql: &str, args: impl rusqlite::Params) -> Result<()> {
        self.with(|i, changes| {
            i.db.execute(sql, args)?;
            changes.push(StoreChange::Session(key.to_string()));
            Ok(())
        })
    }

    pub fn touch(&self, key: &str) -> Result<()> {
        self.with(|i, _| {
            i.db.execute("UPDATE sessions SET last_active_at = ? WHERE key = ?", params![now_ms(), key])?;
            Ok(())
        })
    }

    /// Hides a session from lists, or shows it again, with its own chat (ThreadRow::home); `by` is MANUAL or AUTO. A
    /// thread out of lists (archived itself, or every session of it archived) goes out to its archive file; showing it
    /// again brings it back.
    pub fn set_archived(&self, key: &str, archived: bool, by: &str) -> Result<()> {
        self.with(|i, changes| i.set_archived(key, archived, by, changes))
    }

    /// Hides a chat of its own from lists, or shows it again; its sessions stay as they are. (A session's own chat goes
    /// with the session: set_archived.)
    pub fn set_thread_hidden(&self, thread: i64, hidden: bool, by: &str) -> Result<()> {
        self.with(|i, changes| i.set_thread_hidden(thread, hidden, by, changes))
    }

    /// Names a chat, or (None) leaves it to be named by the first thing a person said in it.
    pub fn set_thread_title(&self, thread: i64, title: Option<&str>) -> Result<()> {
        self.with(|i, changes| {
            i.db.execute("UPDATE threads SET title = ?1 WHERE id = ?2", params![title, thread])?;
            changes.push(StoreChange::Thread { id: thread, entries: vec![] });
            Ok(())
        })
    }

    /// The name a chat's agent gave it, as it stands: the name, the entry it came at, and how often it was changed since.
    pub fn auto_title(&self, thread: i64) -> Result<AutoTitle> {
        self.with(|i, _| {
            Ok(i.db
                .query_row("SELECT auto_title, auto_title_n, auto_title_changes FROM threads WHERE id = ?", [thread], |r| {
                    Ok(AutoTitle { title: r.get(0)?, n: r.get::<_, Option<i64>>(1)?.unwrap_or(0), changes: r.get(2)? })
                })
                .optional()?
                .unwrap_or_default())
        })
    }

    /// Names a chat as its agent did (AutoTitle): the first name, or (`changed`) another one, counted.
    pub fn set_auto_title(&self, thread: i64, title: &str, changed: bool) -> Result<()> {
        self.with(|i, changes| {
            let n = i.last_entry(thread)?;
            i.db.execute(
                "UPDATE threads SET auto_title = ?1, auto_title_n = ?2, auto_title_changes = auto_title_changes + ?3 WHERE id = ?4",
                params![title, n, changed as i64, thread],
            )?;
            changes.push(StoreChange::Thread { id: thread, entries: vec![] });
            Ok(())
        })
    }

    /// How many messages people have written in a thread after entry `n`.
    pub fn people_said_after(&self, thread: i64, n: i64) -> Result<i64> {
        self.with(|i, _| {
            Ok(i.db.query_row(
                "SELECT COUNT(*) FROM entries WHERE thread = ? AND n > ? AND kind = 'message' AND author_kind = 'person'",
                params![thread, n],
                |r| r.get(0),
            )?)
        })
    }

    /// When anyone last read a thread (moved their read position), in ms; None if nobody has.
    pub fn last_read_at(&self, thread: i64) -> Result<Option<i64>> {
        self.with(|i, _| Ok(i.db.query_row("SELECT MAX(at) FROM reads WHERE thread = ?", [thread], |r| r.get(0))?))
    }

    /// A session's own chat on the page (ThreadRow::home), if it has one.
    pub fn home_chat(&self, session: &str) -> Result<Option<ThreadRow>> {
        self.with(|i, _| Ok(i.db.query_row("SELECT * FROM threads WHERE home = ? ORDER BY id LIMIT 1", [session], to_thread).optional()?))
    }

    /// Chats of their own on the page (no session's home) still in lists.
    pub fn chats_of_their_own(&self) -> Result<Vec<ThreadRow>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT * FROM threads WHERE surface = ? AND home IS NULL AND hidden_at IS NULL")?;
            Ok(stmt.query_map([STILLFAIL_SURFACE], to_thread)?.collect::<rusqlite::Result<_>>()?)
        })
    }

    /// Forgets a session: its row, turns, deliveries, memberships and bindings, and the threads only it took part in,
    /// with their entries (or archive files) and reads.
    pub fn delete_session(&self, key: &str) -> Result<()> {
        self.with(|i, changes| {
            let tx = i.db.transaction()?;
            let threads: Vec<i64> = {
                let mut stmt = tx.prepare("SELECT thread FROM thread_sessions WHERE session = ?")?;
                stmt.query_map([key], |r| r.get(0))?.collect::<rusqlite::Result<_>>()?
            };
            tx.execute("DELETE FROM thread_sessions WHERE session = ?", [key])?;
            tx.execute("DELETE FROM deliveries WHERE session = ?", [key])?;
            tx.execute("DELETE FROM turns WHERE session_key = ?", [key])?;
            tx.execute("DELETE FROM bindings WHERE session_key = ?", [key])?;
            tx.execute("DELETE FROM job_notices WHERE job_id IN (SELECT id FROM jobs WHERE session_key = ?)", [key])?;
            tx.execute("DELETE FROM jobs WHERE session_key = ?", [key])?;
            tx.execute("DELETE FROM widget_states WHERE session = ?", [key])?;
            tx.execute("DELETE FROM pins WHERE session = ?", [key])?;
            tx.execute("DELETE FROM sessions WHERE key = ?", [key])?;
            let mut kept = Vec::new();
            let mut removed = Vec::new();
            for thread in threads {
                if tx.query_row("SELECT 1 FROM thread_sessions WHERE thread = ? LIMIT 1", [thread], |_| Ok(())).optional()?.is_some() {
                    kept.push(thread);
                    continue;
                }
                removed.push(thread);
                tx.execute("DELETE FROM deliveries WHERE thread = ?", [thread])?;
                tx.execute("DELETE FROM entries WHERE thread = ?", [thread])?;
                tx.execute("DELETE FROM reads WHERE thread = ?", [thread])?;
                tx.execute("DELETE FROM items WHERE thread = ?", [thread])?;
                tx.execute("DELETE FROM dismissed WHERE thread = ?", [thread])?;
                tx.execute("DELETE FROM closed_cards WHERE thread = ?", [thread])?;
                tx.execute("DELETE FROM kept_chats WHERE thread = ?", [thread])?;
                tx.execute("DELETE FROM threads WHERE id = ?", [thread])?;
            }
            tx.commit()?;
            for thread in &removed {
                i.archived.retain(|(id, _)| id != thread);
                let _ = std::fs::remove_file(i.thread_file(*thread));
            }
            changes.push(StoreChange::SessionRemoved(key.to_string()));
            // Clients drop what they keep of the threads that went with it.
            changes.extend(removed.into_iter().map(StoreChange::ThreadRemoved));
            changes.extend(kept.into_iter().map(|id| StoreChange::Thread { id, entries: vec![] }));
            Ok(())
        })
    }

    // ── single-session bindings ───────────────────────────────────────────

    /// The session a single-session connect delivers into, if one is bound.
    pub fn binding(&self, connect: &str) -> Result<Option<String>> {
        self.with(|i, _| Ok(i.binding(connect)?))
    }

    /// Binds a connect to a session, or unbinds it (None) so its next message starts a new one.
    pub fn set_binding(&self, connect: &str, session: Option<&str>) -> Result<()> {
        self.with(|i, changes| {
            let before = i.binding(connect)?;
            match session {
                Some(key) => i.db.execute("INSERT OR REPLACE INTO bindings (connect, session_key) VALUES (?, ?)", params![connect, key])?,
                None => i.db.execute("DELETE FROM bindings WHERE connect = ?", [connect])?,
            };
            let keys: BTreeSet<String> = before.into_iter().chain(session.map(String::from)).collect();
            changes.extend(keys.into_iter().map(StoreChange::Session));
            Ok(())
        })
    }

    /// Connects bound to each session.
    pub fn list_bindings(&self) -> Result<BTreeMap<String, Vec<String>>> {
        self.with(|i, _| {
            let mut out: BTreeMap<String, Vec<String>> = BTreeMap::new();
            let mut stmt = i.db.prepare("SELECT connect, session_key FROM bindings")?;
            for row in stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))? {
                let (connect, key) = row?;
                out.entry(key).or_default().push(connect);
            }
            Ok(out)
        })
    }

    // ── threads ────────────────────────────────────────────────────────────

    pub fn get_thread(&self, id: i64) -> Result<Option<ThreadRow>> {
        self.with(|i, _| i.get_thread(id))
    }

    pub fn thread_at(&self, surface: &str, channel: &str, thread_ts: &str) -> Result<Option<ThreadRow>> {
        self.with(|i, _| i.thread_at(surface, channel, thread_ts))
    }

    /// The threads at CHANNEL/THREAD_TS on any surface (an agent names a conversation without its surface).
    pub fn threads_at(&self, channel: &str, thread_ts: &str) -> Result<Vec<ThreadRow>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT * FROM threads WHERE channel = ? AND thread_ts = ? ORDER BY id")?;
            Ok(stmt.query_map(params![channel, thread_ts], to_thread)?.collect::<rusqlite::Result<_>>()?)
        })
    }

    /// The thread at this address, made if new.
    pub fn open_thread(&self, surface: &str, channel: &str, thread_ts: &str, title: Option<&str>, created_by: Option<&str>) -> Result<ThreadRow> {
        self.open_thread_of(surface, channel, thread_ts, title, created_by, None)
    }

    /// The thread at this address, made if new as `home`'s own chat (ThreadRow::home).
    pub fn open_thread_of(&self, surface: &str, channel: &str, thread_ts: &str, title: Option<&str>, created_by: Option<&str>, home: Option<&str>) -> Result<ThreadRow> {
        self.with(|i, _| {
            i.db.execute(
                "INSERT OR IGNORE INTO threads (surface, channel, thread_ts, title, created_by, created_at, home) VALUES (?, ?, ?, ?, ?, ?, ?)",
                params![surface, channel, thread_ts, title, created_by, now_ms(), home],
            )?;
            i.thread_at(surface, channel, thread_ts)?.ok_or_else(|| anyhow!("thread {surface} {channel}/{thread_ts} not made"))
        })
    }

    /// The thread a platform message is in: the one it was said in, else the one it starts.
    pub fn thread_of_message(&self, surface: &str, channel: &str, ts: &str) -> Result<Option<ThreadRow>> {
        self.with(|i, _| {
            let said = i
                .db
                .query_row(
                    "SELECT t.* FROM entries e JOIN threads t ON t.id = e.thread WHERE t.surface = ? AND t.channel = ? AND e.ts = ? LIMIT 1",
                    params![surface, channel, ts],
                    to_thread,
                )
                .optional()?;
            match said {
                Some(t) => Ok(Some(t)),
                None => i.thread_at(surface, channel, ts),
            }
        })
    }

    /// Makes a session take part in a thread, posting through `connect`. False if it already did.
    pub fn join_thread(&self, thread: i64, session: &str, connect: &str) -> Result<bool> {
        self.with(|i, changes| {
            let joined = i.db.execute(
                "INSERT OR IGNORE INTO thread_sessions (thread, session, connect, joined_at) VALUES (?, ?, ?, ?)",
                params![thread, session, connect, now_ms()],
            )? > 0;
            if joined {
                changes.push(StoreChange::Session(session.to_string()));
                changes.push(StoreChange::Thread { id: thread, entries: vec![] });
            }
            Ok(joined)
        })
    }

    pub fn thread_sessions(&self, thread: i64) -> Result<Vec<Membership>> {
        self.with(|i, _| i.thread_sessions(thread))
    }

    /// A thread of this session by the address the agent names it with, and how the session posts there.
    pub fn session_thread(&self, session: &str, channel: &str, thread_ts: &str) -> Result<Option<SessionThread>> {
        self.with(|i, _| {
            Ok(i.db
                .query_row(
                    "SELECT t.*, ts.connect FROM thread_sessions ts JOIN threads t ON t.id = ts.thread WHERE ts.session = ? AND t.channel = ? AND t.thread_ts = ?",
                    params![session, channel, thread_ts],
                    to_session_thread,
                )
                .optional()?)
        })
    }

    /// The threads a session takes part in, most recently joined first, with the connect it posts through in each.
    pub fn session_threads(&self, session: &str) -> Result<Vec<SessionThread>> {
        self.with(|i, _| i.session_threads(session))
    }

    /// The thread a session last heard from: where the station's own notices go and whose connect's name the agent goes
    /// by. Falls back to the thread it joined last when it has heard nothing yet.
    pub fn latest_thread(&self, session: &str) -> Result<Option<SessionThread>> {
        self.with(|i, _| {
            let heard = i
                .db
                .query_row(
                    "SELECT t.*, ts.connect FROM deliveries d JOIN threads t ON t.id = d.thread
                     JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = d.session
                     WHERE d.session = ? ORDER BY d.rowid DESC LIMIT 1",
                    [session],
                    to_session_thread,
                )
                .optional()?;
            match heard {
                Some(t) => Ok(Some(t)),
                None => Ok(i.session_threads(session)?.into_iter().next()),
            }
        })
    }

    /// Threads with their sessions, last entry, latest message and the viewer's unread count, most recently said in
    /// first: those of one session, one thread, or all.
    pub fn list_threads(&self, viewer: &str, session: Option<&str>, thread: Option<i64>) -> Result<Vec<ThreadSummary>> {
        self.with(|i, _| {
            let base = "SELECT t.*, COALESCE(r.n, 0) AS read_n FROM threads t LEFT JOIN reads r ON r.thread = t.id AND r.viewer = ?1";
            let rows: Vec<(ThreadRow, i64)> = {
                let (sql, arg): (String, Option<rusqlite::types::Value>) = match (thread, session) {
                    (Some(id), _) => (format!("{base} WHERE t.id = ?2"), Some(id.into())),
                    (None, Some(key)) => (format!("{base} WHERE t.id IN (SELECT thread FROM thread_sessions WHERE session = ?2)"), Some(key.to_string().into())),
                    (None, None) => (base.to_string(), None),
                };
                let mut stmt = i.db.prepare(&sql)?;
                let map = |r: &Row| Ok((to_thread(r)?, r.get::<_, i64>("read_n")?));
                match arg {
                    Some(arg) => stmt.query_map(params![viewer, arg], map)?.collect::<rusqlite::Result<_>>()?,
                    None => stmt.query_map(params![viewer], map)?.collect::<rusqlite::Result<_>>()?,
                }
            };
            let mut summaries = Vec::new();
            for (t, read) in rows {
                let id = t.id;
                summaries.push(ThreadSummary {
                    sessions: i.thread_sessions(id)?,
                    last: i.last_entry(id)?,
                    last_message: i.last_message(id)?,
                    read,
                    unread: i.unread_count(viewer, id, read)?,
                    people: i.thread_people(id, &t.surface)?,
                    first_text: i.first_text(id)?,
                    thread: t,
                });
            }
            let said = |t: &ThreadSummary| t.last_message.as_ref().map(|m| m.created_at).unwrap_or(0);
            summaries.sort_by(|a, b| said(b).cmp(&said(a)).then(b.thread.created_at.cmp(&a.thread.created_at)).then(b.thread.id.cmp(&a.thread.id)));
            Ok(summaries)
        })
    }

    /// The thread's latest message as merged, for lists.
    pub fn last_message(&self, thread: i64) -> Result<Option<MessageRow>> {
        self.with(|i, _| i.last_message(thread))
    }

    /// Messages after the viewer's read position that are not the viewer's own (nor of a Slack user they are).
    pub fn unread_count(&self, viewer: &str, thread: i64) -> Result<i64> {
        self.with(|i, _| {
            let read = i.read_position(viewer, thread)?;
            i.unread_count(viewer, thread, read)
        })
    }

    // ── entries ────────────────────────────────────────────────────────────

    /// Records something said. A message already recorded in that thread (Slack delivers to every connect in the
    /// channel, and redelivers) is the same message: its n comes back with `fresh` false and nothing changes.
    pub fn insert_message(&self, m: NewMessage) -> Result<(i64, bool)> {
        self.with(|i, changes| {
            if let Some(existing) = i.message_at(m.thread, &m.ts)? {
                return Ok((existing.n, false));
            }
            let entry = i.append(
                EntryRow {
                    thread: m.thread,
                    n: 0,
                    kind: EntryKind::Message,
                    target: None,
                    ts: Some(m.ts),
                    author_kind: m.author_kind,
                    author: m.author,
                    text: Some(m.text),
                    attachments: m.attachments,
                    quotes: m.quotes,
                    declared: m.declared,
                    client: m.client,
                    profile: m.profile,
                    // An options card is kept as options too (what stations and clients from before cards read).
                    options: m.options.clone().or_else(|| {
                        m.card.as_ref().filter(|c| c.get("type").and_then(Value::as_str) == Some("options")).and_then(|c| c.get("options").cloned())
                    }),
                    card: m.card.or_else(|| m.options.map(options_card)),
                    at: m.at.unwrap_or_else(now_ms),
                },
                changes,
            )?;
            Ok((entry.n, true))
        })
    }

    /// A platform edit: an edit entry with the message's new words. The thread, or None for a message the station never
    /// recorded or one whose words did not change.
    pub fn edit_message(&self, surface: &str, channel: &str, thread_ts: &str, ts: &str, text: &str) -> Result<Option<i64>> {
        self.with(|i, changes| {
            let Some(thread) = i.thread_at(surface, channel, thread_ts)? else { return Ok(None) };
            let Some(message) = i.message_at(thread.id, ts)? else { return Ok(None) };
            if message.text == text {
                return Ok(None);
            }
            i.append(
                EntryRow {
                    thread: message.thread,
                    n: 0,
                    kind: EntryKind::Edit,
                    target: Some(message.n),
                    ts: None,
                    author_kind: message.author_kind,
                    author: message.author,
                    text: Some(text.to_string()),
                    attachments: message.attachments,
                    quotes: message.quotes,
                    declared: None,
                    client: None,
                    profile: None,
                    options: None,
                    card: None,
                    at: now_ms(),
                },
                changes,
            )?;
            Ok(Some(message.thread))
        })
    }

    /// The thread's last entry number, 0 before anything is said.
    pub fn last_entry(&self, thread: i64) -> Result<i64> {
        self.with(|i, _| i.last_entry(thread))
    }

    /// Entries after n: what came since.
    pub fn entries_after(&self, thread: i64, n: i64) -> Result<Vec<EntryRow>> {
        self.entries_between(thread, n + 1, i64::MAX)
    }

    /// The latest `limit` entries before n (the latest of all without it), oldest first.
    pub fn entries_before(&self, thread: i64, n: Option<i64>, limit: usize) -> Result<Vec<EntryRow>> {
        self.with(|i, _| {
            let before = n.unwrap_or(i64::MAX);
            if i.is_archived(thread)? {
                let entries: Vec<EntryRow> = i.archived_entries(thread)?.into_iter().filter(|e| e.n < before).collect();
                return Ok(entries[entries.len().saturating_sub(limit)..].to_vec());
            }
            let mut stmt = i.db.prepare("SELECT * FROM entries WHERE thread = ? AND n < ? ORDER BY n DESC LIMIT ?")?;
            let mut rows: Vec<EntryRow> = stmt.query_map(params![thread, before, limit as i64], to_entry)?.collect::<rusqlite::Result<_>>()?;
            rows.reverse();
            Ok(rows)
        })
    }

    /// Entries from n = `from` to n = `to`, both included: a gap.
    pub fn entries_between(&self, thread: i64, from: i64, to: i64) -> Result<Vec<EntryRow>> {
        self.with(|i, _| {
            if i.is_archived(thread)? {
                return Ok(i.archived_entries(thread)?.into_iter().filter(|e| e.n >= from && e.n <= to).collect());
            }
            let mut stmt = i.db.prepare("SELECT * FROM entries WHERE thread = ? AND n >= ? AND n <= ? ORDER BY n")?;
            Ok(stmt.query_map(params![thread, from, to], to_entry)?.collect::<rusqlite::Result<_>>()?)
        })
    }

    /// A message of the thread by its platform id, as merged.
    pub fn message_at(&self, thread: i64, ts: &str) -> Result<Option<MessageRow>> {
        self.with(|i, _| i.message_at(thread, ts))
    }

    /// The latest `limit` messages before n (the latest of all without it), as merged, oldest first.
    pub fn messages_before(&self, thread: i64, n: Option<i64>, limit: usize) -> Result<Vec<MessageRow>> {
        self.with(|i, _| {
            let before = n.unwrap_or(i64::MAX);
            if i.is_archived(thread)? {
                let messages: Vec<MessageRow> = merge_entries(&i.archived_entries(thread)?).into_iter().filter(|m| m.n < before).collect();
                return Ok(messages[messages.len().saturating_sub(limit)..].to_vec());
            }
            let mut stmt = i.db.prepare("SELECT * FROM merged WHERE thread = ? AND n < ? ORDER BY n DESC LIMIT ?")?;
            let mut rows: Vec<MessageRow> = stmt.query_map(params![thread, before, limit as i64], to_message)?.collect::<rusqlite::Result<_>>()?;
            rows.reverse();
            Ok(rows)
        })
    }

    // ── deliveries ────────────────────────────────────────────────────────

    /// Hands a message to sessions. Those that did not have it yet.
    pub fn deliver(&self, thread: i64, n: i64, sessions: &[String]) -> Result<Vec<String>> {
        self.with(|i, changes| {
            let mut added = Vec::new();
            for s in sessions {
                if i.db.execute("INSERT OR IGNORE INTO deliveries (thread, n, session) VALUES (?, ?, ?)", params![thread, n, s])? > 0 {
                    added.push(s.clone());
                    changes.push(StoreChange::Session(s.clone()));
                }
            }
            Ok(added)
        })
    }

    /// What the session has yet to read, as merged now, in the order it was handed over.
    pub fn pending_messages(&self, session: &str) -> Result<Vec<PendingMessage>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare(
                "SELECT m.*, t.surface, t.channel, t.thread_ts, ts.connect FROM deliveries d
                 JOIN merged m ON m.thread = d.thread AND m.n = d.n JOIN threads t ON t.id = d.thread
                 JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = d.session
                 WHERE d.session = ? AND d.delivered_at IS NULL ORDER BY d.rowid",
            )?;
            let rows = stmt.query_map([session], |r| {
                Ok(PendingMessage {
                    message: to_message(r)?,
                    surface: r.get("surface")?,
                    channel: r.get("channel")?,
                    thread_ts: r.get("thread_ts")?,
                    connect: r.get("connect")?,
                })
            })?;
            Ok(rows.collect::<rusqlite::Result<_>>()?)
        })
    }

    pub fn mark_delivered(&self, session: &str, messages: &[(i64, i64)]) -> Result<()> {
        self.with(|i, changes| {
            let now = now_ms();
            for (thread, n) in messages {
                i.db.execute(
                    "UPDATE deliveries SET delivered_at = ? WHERE thread = ? AND n = ? AND session = ? AND delivered_at IS NULL",
                    params![now, thread, n, session],
                )?;
            }
            if !messages.is_empty() {
                changes.push(StoreChange::Session(session.to_string()));
            }
            Ok(())
        })
    }

    /// Makes messages delivered to the session pending again: the runtime they were handed to ended before it could be
    /// sure to have read them (SessionActor::suspend).
    pub fn mark_undelivered(&self, session: &str, messages: &[(i64, i64)]) -> Result<()> {
        self.with(|i, changes| {
            for (thread, n) in messages {
                i.db.execute("UPDATE deliveries SET delivered_at = NULL WHERE thread = ? AND n = ? AND session = ?", params![thread, n, session])?;
            }
            if !messages.is_empty() {
                changes.push(StoreChange::Session(session.to_string()));
            }
            Ok(())
        })
    }

    /// Threads the session has already read something from.
    pub fn heard_threads(&self, session: &str) -> Result<HashSet<i64>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT DISTINCT thread FROM deliveries WHERE session = ? AND delivered_at IS NOT NULL")?;
            Ok(stmt.query_map([session], |r| r.get(0))?.collect::<rusqlite::Result<_>>()?)
        })
    }

    pub fn sessions_with_pending(&self) -> Result<Vec<String>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT DISTINCT session FROM deliveries WHERE delivered_at IS NULL")?;
            Ok(stmt.query_map([], |r| r.get(0))?.collect::<rusqlite::Result<_>>()?)
        })
    }

    /// Everyone who wrote in each session's threads (or one session's), as creator references, earliest first.
    pub fn participants(&self, session: Option<&str>) -> Result<BTreeMap<String, Vec<String>>> {
        self.with(|i, _| {
            let rows: Vec<(String, String, i64, String, Option<i64>)> = {
                let sql = format!(
                    "SELECT ts.session, ts.connect, t.id, t.surface, t.archived_at FROM thread_sessions ts JOIN threads t ON t.id = ts.thread {}",
                    if session.is_some() { "WHERE ts.session = ?" } else { "" }
                );
                let mut stmt = i.db.prepare(&sql)?;
                let map = |r: &Row| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?));
                match session {
                    Some(key) => stmt.query_map([key], map)?.collect::<rusqlite::Result<_>>()?,
                    None => stmt.query_map([], map)?.collect::<rusqlite::Result<_>>()?,
                }
            };
            // Each person once per session, at the first time they wrote in any of its threads.
            let mut firsts: BTreeMap<String, BTreeMap<String, i64>> = BTreeMap::new();
            for (key, connect, thread, surface, archived_at) in rows {
                let authors: Vec<(String, i64)> = if archived_at.is_some() {
                    i.archived_entries(thread)?
                        .into_iter()
                        .filter(|e| e.kind == EntryKind::Message && e.author_kind == AuthorKind::Person)
                        .map(|e| (e.author, e.at))
                        .collect()
                } else {
                    let mut stmt = i.db.prepare(
                        "SELECT author, MIN(at) AS at FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' GROUP BY author",
                    )?;
                    stmt.query_map([thread], |r| Ok((r.get(0)?, r.get(1)?)))?.collect::<rusqlite::Result<_>>()?
                };
                let refs = firsts.entry(key).or_default();
                for (author, at) in authors {
                    let reference = if surface == STILLFAIL_SURFACE { author } else { format!("slack:{connect}:{author}") };
                    let first = refs.entry(reference).or_insert(at);
                    if at < *first {
                        *first = at;
                    }
                }
            }
            Ok(firsts
                .into_iter()
                .filter(|(_, refs)| !refs.is_empty())
                .map(|(key, refs)| {
                    let mut refs: Vec<(String, i64)> = refs.into_iter().collect();
                    refs.sort_by_key(|(_, at)| *at);
                    (key, refs.into_iter().map(|(r, _)| r).collect())
                })
                .collect())
        })
    }

    // ── reads ──────────────────────────────────────────────────────────────

    /// How far a viewer has read a thread (an entry number), 0 if never.
    pub fn read_position(&self, viewer: &str, thread: i64) -> Result<i64> {
        self.with(|i, _| i.read_position(viewer, thread))
    }

    /// Moves a viewer's read position forward (never back). Where it is now.
    pub fn set_read(&self, viewer: &str, thread: i64, n: i64) -> Result<i64> {
        self.with(|i, changes| {
            i.db.execute(
                "INSERT INTO reads (viewer, thread, n, at) VALUES (?, ?, ?, ?)
                 ON CONFLICT (viewer, thread) DO UPDATE SET n = MAX(n, excluded.n), at = excluded.at",
                params![viewer, thread, n, now_ms()],
            )?;
            let now = i.read_position(viewer, thread)?;
            changes.push(StoreChange::Read { viewer: viewer.to_string(), thread, n: now });
            Ok(now)
        })
    }

    // ── pins ──────────────────────────────────────────────────────────────

    /// The chats a viewer pinned (by their session's key), with when.
    pub fn pins(&self, viewer: &str) -> Result<HashMap<String, i64>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT session, at FROM pins WHERE viewer = ?")?;
            let pins = stmt.query_map(params![viewer], |r| Ok((r.get(0)?, r.get(1)?)))?.collect::<rusqlite::Result<_>>()?;
            Ok(pins)
        })
    }

    /// The chats someone pinned (by their session's key): the station does not archive them for idling.
    pub fn pinned_sessions(&self) -> Result<HashSet<String>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT DISTINCT session FROM pins")?;
            let keys = stmt.query_map([], |r| r.get(0))?.collect::<rusqlite::Result<_>>()?;
            Ok(keys)
        })
    }

    /// Pins a chat to the top of a viewer's list, or lets it go. Pinned again, it keeps when it was first pinned.
    pub fn set_pin(&self, viewer: &str, session: &str, pinned: bool) -> Result<()> {
        self.with(|i, changes| {
            if pinned {
                i.db.execute("INSERT OR IGNORE INTO pins (viewer, session, at) VALUES (?, ?, ?)", params![viewer, session, now_ms()])?;
            } else {
                i.db.execute("DELETE FROM pins WHERE viewer = ? AND session = ?", params![viewer, session])?;
            }
            changes.push(StoreChange::Pins(viewer.to_string()));
            Ok(())
        })
    }

    /// Chats kept instead of offered for archiving. None selects every viewer, for automatic archiving.
    pub fn kept_chats(&self, viewer: Option<&str>) -> Result<HashSet<i64>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT DISTINCT thread FROM kept_chats WHERE ?1 IS NULL OR viewer = ?1")?;
            Ok(stmt.query_map([viewer], |r| r.get(0))?.collect::<rusqlite::Result<_>>()?)
        })
    }

    pub fn keep_chat(&self, viewer: &str, thread: i64) -> Result<()> {
        self.with(|i, changes| {
            i.db.execute("INSERT OR IGNORE INTO kept_chats (viewer, thread) VALUES (?, ?)", params![viewer, thread])?;
            changes.push(StoreChange::Dismissed(viewer.to_string()));
            Ok(())
        })
    }

    // ── cards ─────────────────────────────────────────────────────────────

    /// The thread's card still pending, if any: its latest post with a card (a newer one replaces an older one), as long
    /// as no person has written in the thread since. The post as merged, and its card (EntryRow::card).
    pub fn pending_card(&self, thread: i64) -> Result<Option<(MessageRow, Value)>> {
        self.with(|i, _| {
            if i.is_archived(thread)? {
                return Ok(None);
            }
            // The latest of each kind (cards, and options from before cards), each read by its own index.
            let latest = |column: &str| -> Result<Option<(i64, Option<String>, Option<String>)>> {
                Ok(i.db
                    .query_row(
                        &format!("SELECT n, card, options FROM entries WHERE thread = ? AND kind = 'message' AND {column} IS NOT NULL ORDER BY n DESC LIMIT 1"),
                        [thread],
                        |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
                    )
                    .optional()?)
            };
            let asked = match (latest("card")?, latest("options")?) {
                (Some(a), Some(b)) => Some(if a.0 >= b.0 { a } else { b }),
                (a, b) => a.or(b),
            };
            let Some((n, card, options)) = asked else { return Ok(None) };
            let answered = i
                .db
                .query_row("SELECT 1 FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? LIMIT 1", params![thread, n], |_| Ok(()))
                .optional()?
                .is_some();
            let closed = i.db.query_row("SELECT 1 FROM closed_cards WHERE thread = ? AND n = ?", params![thread, n], |_| Ok(())).optional()?.is_some();
            if answered || closed {
                return Ok(None);
            }
            let Some(card) = card_of(card, options) else { return Ok(None) };
            let message = i.db.query_row("SELECT * FROM merged WHERE thread = ? AND n = ?", params![thread, n], to_message).optional()?;
            Ok(message.map(|m| (m, card)))
        })
    }

    /// The cards answered since `since` (ms), whoever answered them: each a person's first message after a card (the
    /// thread's latest card then), or a choice that closed it (closed_cards, by a person: not its agent withdrawing it).
    pub fn answers_since(&self, since: i64) -> Result<Vec<CardAnswer>> {
        self.with(|i, _| {
            let mut out = Vec::new();
            let said: Vec<(i64, i64)> = {
                let mut stmt = i.db.prepare("SELECT thread, n FROM entries WHERE author_kind = 'person' AND kind = 'message' AND at >= ?")?;
                stmt.query_map([since], |r| Ok((r.get(0)?, r.get(1)?)))?.collect::<rusqlite::Result<_>>()?
            };
            let asked_before = |thread: i64, n: i64| -> Result<Option<i64>> {
                let card: Option<i64> = i.db.query_row("SELECT max(n) FROM entries WHERE thread = ? AND n < ? AND kind = 'message' AND card IS NOT NULL", params![thread, n], |r| r.get(0))?;
                let options: Option<i64> = i.db.query_row("SELECT max(n) FROM entries WHERE thread = ? AND n < ? AND kind = 'message' AND options IS NOT NULL", params![thread, n], |r| r.get(0))?;
                Ok(card.max(options))
            };
            let card_at = |thread: i64, n: i64| -> Result<Option<(MessageRow, Value)>> {
                let row: Option<(Option<String>, Option<String>)> = i.db.query_row("SELECT card, options FROM entries WHERE thread = ? AND n = ?", params![thread, n], |r| Ok((r.get(0)?, r.get(1)?))).optional()?;
                let Some(card) = row.and_then(|(card, options)| card_of(card, options)) else { return Ok(None) };
                let message = i.db.query_row("SELECT * FROM merged WHERE thread = ? AND n = ?", params![thread, n], to_message).optional()?;
                Ok(message.map(|m| (m, card)))
            };
            for (thread, n) in said {
                let Some(asked) = asked_before(thread, n)? else { continue };
                // Only the first word after it answers it; one closed (by a choice or withdrawn) was answered then.
                let earlier = i.db.query_row("SELECT 1 FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ? AND n < ? LIMIT 1", params![thread, asked, n], |_| Ok(())).optional()?.is_some();
                let closed = i.db.query_row("SELECT 1 FROM closed_cards WHERE thread = ? AND n = ?", params![thread, asked], |_| Ok(())).optional()?.is_some();
                if earlier || closed {
                    continue;
                }
                let Some((question, card)) = card_at(thread, asked)? else { continue };
                let Some(answer) = i.db.query_row("SELECT * FROM merged WHERE thread = ? AND n = ?", params![thread, n], to_message).optional()? else { continue };
                out.push(CardAnswer { question, card, by: answer.author.clone(), at: answer.created_at, answer: Some(answer) });
            }
            let closed: Vec<(i64, i64, String, i64)> = {
                let mut stmt = i.db.prepare("SELECT thread, n, viewer, at FROM closed_cards WHERE at >= ?")?;
                stmt.query_map([since], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))?.collect::<rusqlite::Result<_>>()?
            };
            for (thread, n, by, at) in closed {
                let Some((question, card)) = card_at(thread, n)? else { continue };
                // Withdrawn by its own agent: no one answered it.
                if question.author == by {
                    continue;
                }
                out.push(CardAnswer { question, card, by, at, answer: None });
            }
            Ok(out)
        })
    }

    /// The cards a viewer dismissed, as (thread, n).
    pub fn dismissed(&self, viewer: &str) -> Result<HashSet<(i64, i64)>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT thread, n FROM dismissed WHERE viewer = ?")?;
            let rows = stmt.query_map([viewer], |r| Ok((r.get(0)?, r.get(1)?)))?.collect::<rusqlite::Result<_>>()?;
            Ok(rows)
        })
    }

    /// A viewer will not take up a card (the post at `n`): it leaves their list, on every device of theirs.
    pub fn dismiss(&self, viewer: &str, thread: i64, n: i64) -> Result<()> {
        self.with(|i, changes| {
            i.db.execute("INSERT OR IGNORE INTO dismissed (viewer, thread, n, at) VALUES (?, ?, ?, ?)", params![viewer, thread, n, now_ms()])?;
            changes.push(StoreChange::Dismissed(viewer.to_string()));
            Ok(())
        })
    }

    /// The author withdraws one exact card, without deleting its post or declaring the chat complete.
    pub fn withdraw_card(&self, agent: &str, thread: i64, ts: &str) -> Result<bool> {
        self.with(|i, changes| {
            let n: Option<i64> = i.db.query_row(
                "SELECT n FROM entries WHERE thread = ? AND ts = ? AND kind = 'message' AND author_kind = 'agent' AND author = ? AND (card IS NOT NULL OR options IS NOT NULL)",
                params![thread, ts, agent], |r| r.get(0),
            ).optional()?;
            let Some(n) = n else { return Ok(false) };
            i.db.execute("INSERT OR IGNORE INTO closed_cards (thread, n, viewer, at) VALUES (?, ?, ?, ?)", params![thread, n, agent, now_ms()])?;
            changes.push(StoreChange::Thread { id: thread, entries: vec![] });
            Ok(true)
        })
    }

    /// Close this exact pending card for everyone. This writes no message or delivery: the agent stays asleep.
    /// A stale click cannot close a newer question or overwrite a newer turn's state.
    pub fn close_card(&self, viewer: &str, thread: i64, n: i64, option: &str) -> Result<bool> {
        self.with(|i, changes| {
            let tx = i.db.transaction()?;
            let offered: Option<(Option<String>, Option<String>)> = tx.query_row(
                "SELECT card, options FROM entries WHERE thread = ? AND n = ? AND kind = 'message'",
                params![thread, n], |r| Ok((r.get(0)?, r.get(1)?)),
            ).optional()?;
            let Some(card) = offered.and_then(|(card, options)| card_of(card, options)) else { return Ok(false) };
            if card["type"] != "options" || !card["options"].as_array().into_iter().flatten().any(|o| o["label"].as_str().is_some_and(|l| l.trim() == option) && o["action"] == "close") {
                return Ok(false);
            }
            if tx.query_row("SELECT 1 FROM closed_cards WHERE thread = ? AND n = ?", params![thread, n], |_| Ok(())).optional()?.is_some() {
                return Ok(true);
            }
            let asked: Option<(i64, String, i64)> = tx.query_row(
                "SELECT n, author, at FROM entries WHERE thread = ? AND kind = 'message' AND (card IS NOT NULL OR options IS NOT NULL) ORDER BY n DESC LIMIT 1",
                [thread], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            ).optional()?;
            let Some((latest, agent, at)) = asked else { return Ok(false) };
            if latest != n || tx.query_row("SELECT EXISTS(SELECT 1 FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' AND n > ?)", params![thread, n], |r| r.get::<_, bool>(0))? {
                return Ok(false);
            }
            // Do not race the agent still composing its question / recording its ending.
            let composing = tx.query_row("SELECT ended_at IS NULL FROM turns WHERE session_key = ? ORDER BY started_at DESC LIMIT 1", [&agent], |r| r.get::<_, bool>(0)).optional()?.unwrap_or(false);
            if composing { return Ok(false); }
            tx.execute("INSERT INTO closed_cards (thread, n, viewer, at) VALUES (?, ?, ?, ?)", params![thread, n, viewer, now_ms()])?;
            let changed = tx.execute(
                "UPDATE turns SET declared = 'final', need = ?5, wait_seconds = NULL
                 WHERE id = (SELECT id FROM turns WHERE session_key = ?1 ORDER BY started_at DESC LIMIT 1)
                   AND declared IN ('block', 'need_help', 'need_human', 'need_decision') AND ended_at IS NOT NULL
                   AND ((about_thread = ?2 AND about_n = ?3) OR (about_n IS NULL AND thread = ?2 AND started_at <= ?4))",
                params![agent, thread, n, at, format!("用户选择「{option}」")],
            )?;
            tx.commit()?;
            if changed > 0 { changes.push(StoreChange::Session(agent)); }
            changes.push(StoreChange::Thread { id: thread, entries: vec![] });
            Ok(true)
        })
    }

    // ── identities ────────────────────────────────────────────────────────

    /// The Slack users a viewer said are them: their messages are the viewer's own.
    pub fn slack_identities(&self, viewer: &str) -> Result<Vec<String>> {
        self.with(|i, _| i.slack_identities(viewer))
    }

    /// Binds a Slack user to a viewer ("这是我"), or unbinds it. Nobody checks: it is the viewer's word.
    pub fn set_slack_identity(&self, viewer: &str, user: &str, bound: bool) -> Result<()> {
        self.with(|i, changes| {
            if bound {
                i.db.execute("INSERT OR IGNORE INTO identities (viewer, slack_user, at) VALUES (?, ?, ?)", params![viewer, user, now_ms()])?;
            } else {
                i.db.execute("DELETE FROM identities WHERE viewer = ? AND slack_user = ?", params![viewer, user])?;
            }
            changes.push(StoreChange::Identities(viewer.to_string()));
            Ok(())
        })
    }

    // ── turns ─────────────────────────────────────────────────────────────

    /// Whether the session has had a turn.
    pub fn has_turns(&self, session: &str) -> Result<bool> {
        self.with(|i, _| Ok(i.db.query_row("SELECT EXISTS (SELECT 1 FROM turns WHERE session_key = ?)", [session], |r| r.get::<_, bool>(0))?))
    }

    pub fn start_turn(&self, id: &str, session: &str, kind: &str) -> Result<()> {
        self.start_turn_for(id, session, kind, &TurnFor::default())
    }

    /// Starts a turn for someone: the person whose message it answers, in that thread, on that profile. A turn nobody's
    /// message started (a job's notice, a nudge, going on after an account ran out) goes on with the work of the one
    /// before it, so it is theirs.
    pub fn start_turn_for(&self, id: &str, session: &str, kind: &str, by: &TurnFor) -> Result<()> {
        self.with(|i, changes| {
            let before = |column: &str| format!("(SELECT {column} FROM turns WHERE session_key = ?2 AND {column} IS NOT NULL ORDER BY started_at DESC LIMIT 1)");
            i.db.execute(
                &format!(
                    "INSERT INTO turns (id, session_key, kind, started_at, profile, person, thread) VALUES (?1, ?2, ?3, ?4, ?5, COALESCE(?6, {}), COALESCE(?7, {}))",
                    before("person"),
                    before("thread")
                ),
                params![id, session, kind, now_ms(), by.profile, by.person, by.thread],
            )?;
            changes.push(StoreChange::Session(session.to_string()));
            Ok(())
        })
    }

    /// What a turn waits for once it ends as waiting (chat_state waiting `for`), in the agent's words.
    pub fn set_wait_for(&self, id: &str, what: &str) -> Result<()> {
        self.with(|i, _| {
            i.db.execute("UPDATE turns SET wait_for = ? WHERE id = ?", params![what, id])?;
            Ok(())
        })
    }

    /// The message a turn's state is about (`about`: thread, entry and ts), or none.
    pub fn set_about(&self, id: &str, about: Option<(i64, i64, &str)>) -> Result<()> {
        self.with(|i, _| {
            let (thread, n, ts) = match about {
                Some((thread, n, ts)) => (Some(thread), Some(n), Some(ts)),
                None => (None, None, None),
            };
            i.db.execute("UPDATE turns SET about_thread = ?, about_n = ?, about_ts = ? WHERE id = ?", params![thread, n, ts, id])?;
            Ok(())
        })
    }

    /// What a turn needs of a person once it ends as need_help (`need`), in the agent's words.
    /// The last migration note a session was told (migrations.rs); 0 for one never told any.
    pub fn told_notes(&self, key: &str) -> Result<i64> {
        self.with(|i, _| Ok(i.db.query_row("SELECT told_notes FROM sessions WHERE key = ?", [key], |r| r.get::<_, Option<i64>>(0)).optional()?.flatten().unwrap_or(0)))
    }

    pub fn set_told_notes(&self, key: &str, n: i64) -> Result<()> {
        self.with(|i, _| {
            i.db.execute("UPDATE sessions SET told_notes = ? WHERE key = ?", params![n, key])?;
            Ok(())
        })
    }

    pub fn set_need(&self, id: &str, what: &str) -> Result<()> {
        self.with(|i, _| {
            i.db.execute("UPDATE turns SET need = ? WHERE id = ?", params![what, id])?;
            Ok(())
        })
    }

    /// Ends a turn; `wait_seconds` is how long a turn ending as waiting waits at most.
    pub fn end_turn(&self, id: &str, outcome: &str, detail: Option<&str>, declared: Option<&str>, wait_seconds: Option<u64>) -> Result<()> {
        self.with(|i, changes| {
            i.db.execute(
                "UPDATE turns SET ended_at = ?, outcome = ?, detail = ?, declared = ?, wait_seconds = ? WHERE id = ?",
                params![now_ms(), outcome, detail, declared, wait_seconds.map(|s| s as i64), id],
            )?;
            if let Some(key) = i.db.query_row("SELECT session_key FROM turns WHERE id = ?", [id], |r| r.get::<_, String>(0)).optional()? {
                changes.push(StoreChange::Session(key));
            }
            Ok(())
        })
    }

    /// The session was stopped while it waited: its latest turn, if it ended waiting, is recorded as stopped instead
    /// (aborted, no longer waiting). Whether it was.
    pub fn stop_wait(&self, session: &str) -> Result<bool> {
        self.with(|i, changes| {
            let n = i.db.execute(
                "UPDATE turns SET outcome = 'aborted', declared = NULL, wait_seconds = NULL, detail = 'other: stopped while waiting'
                 WHERE id = (SELECT id FROM turns WHERE session_key = ?1 ORDER BY started_at DESC LIMIT 1) AND declared = 'waiting' AND ended_at IS NOT NULL",
                [session],
            )?;
            if n > 0 {
                changes.push(StoreChange::Session(session.to_string()));
            }
            Ok(n > 0)
        })
    }

    /// The session's latest turn.
    pub fn last_turn(&self, session: &str) -> Result<Option<TurnSummary>> {
        self.with(|i, _| {
            let turn = i.db.query_row("SELECT * FROM turns WHERE session_key = ? ORDER BY started_at DESC LIMIT 1", [session], |r| {
                Ok(TurnSummary {
                    kind: r.get("kind")?,
                    outcome: r.get("outcome")?,
                    declared: r.get::<_, Option<String>>("declared")?.map(|d| said_before(&d).to_string()),
                    ending: r.get::<_, Option<String>>("declared")?.map(|d| ending(&d).to_string()),
                    need: r.get("need")?,
                    about: to_about(r)?,
                    wait_seconds: r.get("wait_seconds")?,
                    wait_for: r.get("wait_for")?,
                    detail: r.get("detail")?,
                    started_at: r.get("started_at")?,
                    ended_at: r.get("ended_at")?,
                })
            });
            Ok(turn.optional()?)
        })
    }

    pub fn list_turns(&self, session: &str) -> Result<Vec<TurnRow>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT * FROM turns WHERE session_key = ? ORDER BY started_at")?;
            let rows = stmt.query_map([session], |r| {
                Ok(TurnRow {
                    id: r.get("id")?,
                    summary: TurnSummary {
                        kind: r.get("kind")?,
                        outcome: r.get("outcome")?,
                        declared: r.get::<_, Option<String>>("declared")?.map(|d| said_before(&d).to_string()),
                        ending: r.get::<_, Option<String>>("declared")?.map(|d| ending(&d).to_string()),
                        need: r.get("need")?,
                        about: to_about(r)?,
                        wait_seconds: r.get("wait_seconds")?,
                    wait_for: r.get("wait_for")?,
                        detail: r.get("detail")?,
                        started_at: r.get("started_at")?,
                        ended_at: r.get("ended_at")?,
                    },
                })
            })?;
            Ok(rows.collect::<rusqlite::Result<_>>()?)
        })
    }

    /// Per session (or for one): turn count, the latest turn, undelivered messages and the first one it heard.
    pub fn session_stats(&self, key: Option<&str>) -> Result<BTreeMap<String, SessionStats>> {
        self.with(|i, _| {
            let sql = format!(
                "SELECT s.key,
                   (SELECT COUNT(*) FROM turns t WHERE t.session_key = s.key) AS turns,
                   (SELECT COUNT(*) FROM deliveries d WHERE d.session = s.key AND d.delivered_at IS NULL) AS pending,
                   (SELECT substr(m.text, 1, 300) FROM deliveries d JOIN merged m ON m.thread = d.thread AND m.n = d.n
                     WHERE d.session = s.key ORDER BY d.rowid LIMIT 1) AS first_text,
                   l.kind, l.outcome, l.declared, l.wait_seconds, l.wait_for, l.need, l.about_thread, l.about_n, l.about_ts, l.detail, l.started_at, l.ended_at
                 FROM sessions s
                 LEFT JOIN turns l ON l.id = (SELECT id FROM turns t2 WHERE t2.session_key = s.key ORDER BY t2.started_at DESC LIMIT 1)
                 {}",
                if key.is_some() { "WHERE s.key = ?" } else { "" }
            );
            let mut stmt = i.db.prepare(&sql)?;
            let map = |r: &Row| {
                let started: Option<i64> = r.get("started_at")?;
                Ok((
                    r.get::<_, String>("key")?,
                    SessionStats {
                        turns: r.get("turns")?,
                        pending: r.get("pending")?,
                        first_text: r.get("first_text")?,
                        last_turn: match started {
                            None => None,
                            Some(started_at) => Some(TurnSummary {
                                kind: r.get("kind")?,
                                outcome: r.get("outcome")?,
                                declared: r.get::<_, Option<String>>("declared")?.map(|d| said_before(&d).to_string()),
                                ending: r.get::<_, Option<String>>("declared")?.map(|d| ending(&d).to_string()),
                                need: r.get("need")?,
                                about: to_about(r)?,
                                wait_seconds: r.get("wait_seconds")?,
                    wait_for: r.get("wait_for")?,
                                detail: r.get("detail")?,
                                started_at,
                                ended_at: r.get("ended_at")?,
                            }),
                        },
                    },
                ))
            };
            Ok(match key {
                Some(k) => stmt.query_map([k], map)?.collect::<rusqlite::Result<_>>()?,
                None => stmt.query_map([], map)?.collect::<rusqlite::Result<_>>()?,
            })
        })
    }

    // ── profile checks and quotas ─────────────────────────────────────────

    pub fn profile_status(&self) -> Result<BTreeMap<String, ProfileStatus>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT profile, check_json, quota_json FROM profile_status")?;
            let rows = stmt.query_map([], |r| {
                let check: Option<String> = r.get(1)?;
                let quota: Option<String> = r.get(2)?;
                Ok((
                    r.get::<_, String>(0)?,
                    ProfileStatus {
                        check: check.and_then(|c| serde_json::from_str(&c).ok()),
                        quota: quota.and_then(|q| serde_json::from_str(&q).ok()),
                    },
                ))
            })?;
            Ok(rows.collect::<rusqlite::Result<_>>()?)
        })
    }

    /// Keeps a profile's check (its `checkedAt` says when).
    pub fn set_profile_check(&self, profile: &str, check: &Value) -> Result<()> {
        self.with(|i, _| {
            i.db.execute(
                "INSERT INTO profile_status (profile, check_json, checked_at) VALUES (?, ?, ?)
                 ON CONFLICT (profile) DO UPDATE SET check_json = excluded.check_json, checked_at = excluded.checked_at",
                params![profile, check.to_string(), check.get("checkedAt").and_then(Value::as_i64)],
            )?;
            Ok(())
        })
    }

    /// Keeps a profile's quota (its `checkedAt` says when).
    pub fn set_profile_quota(&self, profile: &str, quota: &Value) -> Result<()> {
        self.with(|i, _| {
            i.db.execute(
                "INSERT INTO profile_status (profile, quota_json, quota_at) VALUES (?, ?, ?)
                 ON CONFLICT (profile) DO UPDATE SET quota_json = excluded.quota_json, quota_at = excluded.quota_at",
                params![profile, quota.to_string(), quota.get("checkedAt").and_then(Value::as_i64)],
            )?;
            Ok(())
        })
    }

    // ── runtime process groups ────────────────────────────────────────────

    pub fn record_process(&self, pgid: i64, started_at: i64, runtime: &str, label: &str) -> Result<()> {
        self.with(|i, changes| {
            i.db.execute("INSERT OR REPLACE INTO processes (pgid, started_at, runtime, label) VALUES (?, ?, ?, ?)", params![pgid, started_at, runtime, label])?;
            changes.push(StoreChange::Processes);
            Ok(())
        })
    }

    pub fn forget_process(&self, pgid: i64) -> Result<()> {
        self.with(|i, changes| {
            if i.db.execute("DELETE FROM processes WHERE pgid = ?", [pgid])? > 0 {
                changes.push(StoreChange::Processes);
            }
            Ok(())
        })
    }

    // ── background jobs ───────────────────────────────────────────────────

    pub fn insert_job(&self, job: &JobRow) -> Result<()> {
        self.with(|i, changes| {
            i.db.execute(
                "INSERT INTO jobs (id, session_key, name, command, cwd, port, token, state, pgid, exit_code, started_at, ended_at, restarts, log, watch) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                params![job.id, job.session_key, job.name, job.command, job.cwd, job.port, job.token, job.state, job.pgid, job.exit_code, job.started_at, job.ended_at, job.restarts, job.log, job.watch as i64],
            )?;
            changes.push(StoreChange::Session(job.session_key.clone()));
            changes.push(StoreChange::Job(job.id.clone()));
            Ok(())
        })
    }

    /// A job started (again): running, in this process group.
    pub fn job_started(&self, id: &str, pgid: i64, restarted: bool) -> Result<()> {
        self.job_update(id, "UPDATE jobs SET state = 'running', pgid = ?1, exit_code = NULL, ended_at = NULL, restarts = restarts + ?2 WHERE id = ?3", params![pgid, restarted as i64, id])
    }

    /// A job ended: `state` exited, stopped or failed.
    pub fn job_ended(&self, id: &str, state: &str, exit_code: Option<i64>) -> Result<()> {
        self.job_update(id, "UPDATE jobs SET state = ?1, exit_code = ?2, ended_at = ?3, pgid = NULL WHERE id = ?4", params![state, exit_code, now_ms(), id])
    }

    fn job_update(&self, id: &str, sql: &str, args: impl rusqlite::Params) -> Result<()> {
        self.with(|i, changes| {
            i.db.execute(sql, args)?;
            if let Some(session) = i.db.query_row("SELECT session_key FROM jobs WHERE id = ?", [id], |r| r.get::<_, String>(0)).optional()? {
                changes.push(StoreChange::Session(session));
                changes.push(StoreChange::Job(id.to_string()));
            }
            Ok(())
        })
    }

    pub fn get_job(&self, id: &str) -> Result<Option<JobRow>> {
        self.with(|i, _| Ok(i.db.query_row("SELECT * FROM jobs WHERE id = ?", [id], job_row).optional()?))
    }

    pub fn job_by_token(&self, token: &str) -> Result<Option<JobRow>> {
        self.with(|i, _| Ok(i.db.query_row("SELECT * FROM jobs WHERE token = ?", [token], job_row).optional()?))
    }

    /// A session's jobs (all sessions' with None), newest first.
    pub fn list_jobs(&self, session: Option<&str>) -> Result<Vec<JobRow>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT * FROM jobs WHERE ?1 IS NULL OR session_key = ?1 ORDER BY started_at DESC")?;
            let rows = stmt.query_map([session], job_row)?;
            Ok(rows.collect::<rusqlite::Result<_>>()?)
        })
    }

    /// What a job said (`stillfail-job notify`), kept for the pages: a job's latest words are how people see what it is up to.
    pub fn add_job_notice(&self, id: &str, text: &str) -> Result<()> {
        self.with(|i, changes| {
            i.db.execute("INSERT INTO job_notices (job_id, at, text) VALUES (?, ?, ?)", params![id, now_ms(), text])?;
            // A job keeps its latest words only.
            i.db.execute(
                "DELETE FROM job_notices WHERE job_id = ?1 AND rowid NOT IN (SELECT rowid FROM job_notices WHERE job_id = ?1 ORDER BY at DESC, rowid DESC LIMIT ?2)",
                params![id, JOB_NOTICES],
            )?;
            if let Some(session) = i.db.query_row("SELECT session_key FROM jobs WHERE id = ?", [id], |r| r.get::<_, String>(0)).optional()? {
                changes.push(StoreChange::Session(session));
                changes.push(StoreChange::Job(id.to_string()));
            }
            Ok(())
        })
    }

    /// A session's jobs that are over (stopped, failed, or ended by themselves; a service waiting to start again is not)
    /// taken off its record, with what they said: their ids and logs.
    pub fn clear_ended_jobs(&self, session: &str) -> Result<Vec<(String, String)>> {
        self.with(|i, changes| {
            let tx = i.db.transaction()?;
            let gone: Vec<(String, String)> = {
                let mut stmt = tx.prepare(
                    "SELECT id, log FROM jobs WHERE session_key = ? AND (state IN ('stopped', 'failed') OR (state = 'exited' AND port IS NULL))",
                )?;
                stmt.query_map([session], |r| Ok((r.get(0)?, r.get(1)?)))?.collect::<rusqlite::Result<_>>()?
            };
            for (id, _) in &gone {
                tx.execute("DELETE FROM job_notices WHERE job_id = ?", [id])?;
                tx.execute("DELETE FROM jobs WHERE id = ?", [id])?;
            }
            tx.commit()?;
            if !gone.is_empty() {
                changes.push(StoreChange::Session(session.to_string()));
                changes.extend(gone.iter().map(|(id, _)| StoreChange::JobRemoved { id: id.clone(), session: session.to_string() }));
            }
            Ok(gone)
        })
    }

    /// A job's notices, newest first (at most `limit`).
    pub fn job_notices(&self, id: &str, limit: usize) -> Result<Vec<JobNotice>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT at, text FROM job_notices WHERE job_id = ? ORDER BY at DESC, rowid DESC LIMIT ?")?;
            let rows = stmt.query_map(params![id, limit as i64], |r| Ok(JobNotice { at: r.get(0)?, text: r.get(1)? }))?;
            Ok(rows.collect::<rusqlite::Result<_>>()?)
        })
    }

    pub fn list_processes(&self) -> Result<Vec<ProcessRow>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT * FROM processes")?;
            let rows = stmt.query_map([], |r| Ok(ProcessRow { pgid: r.get("pgid")?, started_at: r.get("started_at")?, runtime: r.get("runtime")?, label: r.get("label")? }))?;
            Ok(rows.collect::<rusqlite::Result<_>>()?)
        })
    }
    // ── widget states ─────────────────────────────────────────────────────

    /// Keeps what a widget in one of the session's messages holds (`state`, JSON) and what of it is for the agent
    /// (`model`). A model other than the one last told is told again.
    pub fn put_widget_state(&self, session: &str, path: &str, state: &str, model: Option<&str>) -> Result<()> {
        self.with(|i, _| {
            i.db.execute(
                "INSERT INTO widget_states (session, path, state, model, updated_at) VALUES (?, ?, ?, ?, ?)
                 ON CONFLICT (session, path) DO UPDATE SET state = excluded.state, model = excluded.model, updated_at = excluded.updated_at,
                   told_at = CASE WHEN widget_states.model IS excluded.model THEN widget_states.told_at END",
                params![session, path, state, model, now_ms()],
            )?;
            Ok(())
        })
    }

    pub fn widget_state(&self, session: &str, path: &str) -> Result<Option<String>> {
        self.with(|i, _| Ok(i.db.query_row("SELECT state FROM widget_states WHERE session = ? AND path = ?", [session, path], |r| r.get(0)).optional()?))
    }

    /// The session's widget models it has not been told, with where each widget was posted (the latest of its
    /// threads' messages that carry the file).
    pub fn untold_widget_models(&self, session: &str) -> Result<Vec<WidgetModel>> {
        self.with(|i, _| {
            let mut stmt = i.db.prepare("SELECT path, model FROM widget_states WHERE session = ? AND model IS NOT NULL AND told_at IS NULL ORDER BY updated_at, rowid")?;
            let untold: Vec<(String, String)> = stmt.query_map([session], |r| Ok((r.get(0)?, r.get(1)?)))?.collect::<rusqlite::Result<_>>()?;
            let mut place = i.db.prepare(
                "SELECT t.channel, t.thread_ts, json_extract(a.value, '$.name') FROM merged m
                 JOIN threads t ON t.id = m.thread JOIN thread_sessions ts ON ts.thread = t.id AND ts.session = ?1, json_each(m.attachments) a
                 WHERE m.attachments IS NOT NULL AND json_extract(a.value, '$.path') = ?2 ORDER BY m.created_at DESC LIMIT 1",
            )?;
            let mut out = Vec::new();
            for (path, model) in untold {
                let found: Option<(String, String, Option<String>)> = place.query_row([session, path.as_str()], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).optional()?;
                let base = path.rsplit(['/', '\\']).next().unwrap_or(&path).to_string();
                let (thread, name) = match found {
                    Some((channel, ts, name)) => (Some((channel, ts)), name.filter(|n| !n.is_empty()).unwrap_or(base)),
                    None => (None, base),
                };
                out.push(WidgetModel { path, name, thread, model });
            }
            Ok(out)
        })
    }

    /// The agent was told these (path, model): each is marked told unless its model changed since.
    pub fn mark_widget_models_told(&self, session: &str, told: &[(String, String)]) -> Result<()> {
        self.with(|i, _| {
            let now = now_ms();
            for (path, model) in told {
                i.db.execute("UPDATE widget_states SET told_at = ? WHERE session = ? AND path = ? AND model = ?", params![now, session, path, model])?;
            }
            Ok(())
        })
    }
}

impl Inner {
    fn get_thread(&self, id: i64) -> Result<Option<ThreadRow>> {
        Ok(self.db.query_row("SELECT * FROM threads WHERE id = ?", [id], to_thread).optional()?)
    }

    fn thread_at(&self, surface: &str, channel: &str, thread_ts: &str) -> Result<Option<ThreadRow>> {
        Ok(self
            .db
            .query_row("SELECT * FROM threads WHERE surface = ? AND channel = ? AND thread_ts = ?", params![surface, channel, thread_ts], to_thread)
            .optional()?)
    }

    fn thread_sessions(&self, thread: i64) -> Result<Vec<Membership>> {
        let mut stmt = self.db.prepare("SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid")?;
        Ok(stmt.query_map([thread], to_membership)?.collect::<rusqlite::Result<_>>()?)
    }

    fn session_threads(&self, session: &str) -> Result<Vec<SessionThread>> {
        let mut stmt = self.db.prepare(
            "SELECT t.*, ts.connect FROM thread_sessions ts JOIN threads t ON t.id = ts.thread WHERE ts.session = ? ORDER BY ts.joined_at DESC, ts.rowid DESC",
        )?;
        Ok(stmt.query_map([session], to_session_thread)?.collect::<rusqlite::Result<_>>()?)
    }

    fn binding(&self, connect: &str) -> Result<Option<String>> {
        Ok(self.db.query_row("SELECT session_key FROM bindings WHERE connect = ?", [connect], |r| r.get(0)).optional()?)
    }

    fn read_position(&self, viewer: &str, thread: i64) -> Result<i64> {
        Ok(self.db.query_row("SELECT n FROM reads WHERE viewer = ? AND thread = ?", params![viewer, thread], |r| r.get(0)).optional()?.unwrap_or(0))
    }

    fn slack_identities(&self, viewer: &str) -> Result<Vec<String>> {
        let mut stmt = self.db.prepare("SELECT slack_user FROM identities WHERE viewer = ? ORDER BY at")?;
        Ok(stmt.query_map([viewer], |r| r.get(0))?.collect::<rusqlite::Result<_>>()?)
    }

    fn last_message(&mut self, thread: i64) -> Result<Option<MessageRow>> {
        if self.is_archived(thread)? {
            return Ok(merge_entries(&self.archived_entries(thread)?).pop());
        }
        Ok(self.db.query_row("SELECT * FROM merged WHERE thread = ? ORDER BY n DESC LIMIT 1", [thread], to_message).optional()?)
    }

    fn unread_count(&mut self, viewer: &str, thread: i64, read: i64) -> Result<i64> {
        let slack = self.get_thread(thread)?.map(|t| t.surface != STILLFAIL_SURFACE).unwrap_or(true);
        let mut selves = vec![viewer.to_string()];
        if slack {
            selves.extend(self.slack_identities(viewer)?);
        }
        if self.is_archived(thread)? {
            let count = merge_entries(&self.archived_entries(thread)?)
                .into_iter()
                .filter(|m| m.n > read && !(m.author_kind == AuthorKind::Person && selves.contains(&m.author)))
                .count();
            return Ok(count as i64);
        }
        Ok(self.db.query_row(
            "SELECT COUNT(*) FROM entries WHERE thread = ? AND n > ? AND kind = 'message'
             AND NOT (author_kind = 'person' AND author IN (SELECT value FROM json_each(?)))",
            params![thread, read, serde_json::to_string(&selves)?],
            |r| r.get(0),
        )?)
    }

    /// Everyone who wrote in a thread, as creator references (a Slack user through a connect in it), earliest first.
    fn thread_people(&mut self, thread: i64, surface: &str) -> Result<Vec<String>> {
        let connect: Option<String> = self.db.query_row("SELECT MIN(connect) FROM thread_sessions WHERE thread = ?", [thread], |r| r.get(0))?;
        let authors: Vec<String> = if self.is_archived(thread)? {
            let mut seen = HashSet::new();
            self.archived_entries(thread)?
                .into_iter()
                .filter(|e| e.kind == EntryKind::Message && e.author_kind == AuthorKind::Person)
                .map(|e| e.author)
                .filter(|a| seen.insert(a.clone()))
                .collect()
        } else {
            let mut stmt = self.db.prepare(
                "SELECT author, MIN(n) AS first FROM entries WHERE thread = ? AND kind = 'message' AND author_kind = 'person' GROUP BY author ORDER BY first",
            )?;
            stmt.query_map([thread], |r| r.get(0))?.collect::<rusqlite::Result<_>>()?
        };
        if surface == STILLFAIL_SURFACE {
            return Ok(authors);
        }
        Ok(match connect {
            Some(connect) => authors.into_iter().map(|a| format!("slack:{connect}:{a}")).collect(),
            None => vec![],
        })
    }

    /// The first thing a person said in it (up to 300 characters).
    fn first_text(&mut self, thread: i64) -> Result<Option<String>> {
        if self.is_archived(thread)? {
            return Ok(merge_entries(&self.archived_entries(thread)?)
                .into_iter()
                .find(|m| m.author_kind == AuthorKind::Person)
                .map(|m| m.text.chars().take(300).collect()));
        }
        Ok(self
            .db
            .query_row("SELECT substr(text, 1, 300) FROM merged WHERE thread = ? AND author_kind = 'person' ORDER BY n LIMIT 1", [thread], |r| r.get(0))
            .optional()?)
    }

    fn last_entry(&mut self, thread: i64) -> Result<i64> {
        if self.is_archived(thread)? {
            return Ok(self.archived_entries(thread)?.last().map(|e| e.n).unwrap_or(0));
        }
        Ok(self.db.query_row("SELECT MAX(n) FROM entries WHERE thread = ?", [thread], |r| r.get::<_, Option<i64>>(0))?.unwrap_or(0))
    }

    fn message_at(&mut self, thread: i64, ts: &str) -> Result<Option<MessageRow>> {
        if self.is_archived(thread)? {
            return Ok(merge_entries(&self.archived_entries(thread)?).into_iter().find(|m| m.ts == ts));
        }
        Ok(self.db.query_row("SELECT * FROM merged WHERE thread = ? AND ts = ?", params![thread, ts], to_message).optional()?)
    }

    /// Appends an entry as the thread's next, bringing an archived thread back first.
    fn append(&mut self, mut entry: EntryRow, changes: &mut Changes) -> Result<EntryRow> {
        if self.is_archived(entry.thread)? {
            self.restore_thread(entry.thread)?;
        }
        let tx = self.db.transaction()?;
        let n: Option<i64> = tx.query_row("SELECT MAX(n) FROM entries WHERE thread = ?", [entry.thread], |r| r.get(0))?;
        entry.n = n.unwrap_or(0) + 1;
        insert_entry(&tx, &entry)?;
        tx.commit()?;
        changes.push(StoreChange::Thread { id: entry.thread, entries: vec![entry.clone()] });
        self.bring_back(&entry, changes)?;
        Ok(entry)
    }

    fn set_archived(&mut self, key: &str, archived: bool, by: &str, changes: &mut Changes) -> Result<()> {
        let now = now_ms();
        let tx = self.db.transaction()?;
        if archived {
            tx.execute("UPDATE sessions SET archived_at = ?, archived_by = ? WHERE key = ?", params![now, by, key])?;
        } else {
            let shown = (by == MANUAL).then_some(now);
            tx.execute("UPDATE sessions SET archived_at = NULL, archived_by = NULL, shown_at = COALESCE(?, shown_at) WHERE key = ?", params![shown, key])?;
        }
        let hidden = archived.then_some(now);
        let hidden_by = archived.then_some(by);
        tx.execute("UPDATE threads SET hidden_at = ?, hidden_by = ? WHERE home = ?", params![hidden, hidden_by, key])?;
        tx.commit()?;
        for t in self.session_threads(key)? {
            self.file_away(t.thread.id)?;
            changes.push(StoreChange::Thread { id: t.thread.id, entries: vec![] });
        }
        changes.push(StoreChange::Session(key.to_string()));
        Ok(())
    }

    fn set_thread_hidden(&mut self, thread: i64, hidden: bool, by: &str, changes: &mut Changes) -> Result<()> {
        let now = now_ms();
        if hidden {
            self.db.execute("UPDATE threads SET hidden_at = ?, hidden_by = ? WHERE id = ?", params![now, by, thread])?;
        } else {
            let shown = (by == MANUAL).then_some(now);
            self.db.execute("UPDATE threads SET hidden_at = NULL, hidden_by = NULL, shown_at = COALESCE(?, shown_at) WHERE id = ?", params![shown, thread])?;
        }
        self.file_away(thread)?;
        changes.push(StoreChange::Thread { id: thread, entries: vec![] });
        Ok(())
    }

    /// Out of every list: archived itself, or none of its sessions shown.
    fn out_of_lists(&self, thread: i64) -> Result<bool> {
        let Some(hidden) = self.db.query_row("SELECT hidden_at FROM threads WHERE id = ?", [thread], |r| r.get::<_, Option<i64>>(0)).optional()? else {
            return Ok(false);
        };
        if hidden.is_some() {
            return Ok(true);
        }
        let shown = self
            .db
            .query_row(
                "SELECT 1 FROM thread_sessions ts JOIN sessions s ON s.key = ts.session WHERE ts.thread = ? AND s.archived_at IS NULL LIMIT 1",
                [thread],
                |_| Ok(()),
            )
            .optional()?
            .is_some();
        Ok(!shown)
    }

    /// Writes a thread out to its archive file when it went out of lists, or brings it back when it came back.
    fn file_away(&mut self, thread: i64) -> Result<()> {
        let out = self.out_of_lists(thread)?;
        let filed = self.is_archived(thread)?;
        if out && !filed {
            self.archive_thread(thread)?;
        } else if !out && filed {
            self.restore_thread(thread)?;
        }
        Ok(())
    }

    /// Something new said in a thread brings what it is about back into lists: the chat, if it was archived alone, and
    /// the archived sessions that hear it (a person's message goes to every session of the thread) or said it.
    fn bring_back(&mut self, entry: &EntryRow, changes: &mut Changes) -> Result<()> {
        if entry.kind != EntryKind::Message || entry.author_kind == AuthorKind::StillFail {
            return Ok(());
        }
        let Some(thread) = self.get_thread(entry.thread)? else { return Ok(()) };
        let archived: Vec<String> = if entry.author_kind == AuthorKind::Agent {
            self.db
                .query_row("SELECT key FROM sessions WHERE key = ? AND archived_at IS NOT NULL", [&entry.author], |r| r.get(0))
                .optional()?
                .into_iter()
                .collect()
        } else {
            let mut stmt = self
                .db
                .prepare("SELECT s.key FROM thread_sessions ts JOIN sessions s ON s.key = ts.session WHERE ts.thread = ? AND s.archived_at IS NOT NULL")?;
            stmt.query_map([entry.thread], |r| r.get(0))?.collect::<rusqlite::Result<_>>()?
        };
        for key in archived {
            self.set_archived(&key, false, AUTO, changes)?;
        }
        if thread.hidden_at.is_some() && thread.home.is_none() {
            self.set_thread_hidden(thread.id, false, AUTO, changes)?;
        }
        Ok(())
    }

    // ── archive ────────────────────────────────────────────────────────────

    fn is_archived(&self, thread: i64) -> Result<bool> {
        Ok(self
            .db
            .query_row("SELECT archived_at FROM threads WHERE id = ?", [thread], |r| r.get::<_, Option<i64>>(0))
            .optional()?
            .flatten()
            .is_some())
    }

    fn thread_file(&self, thread: i64) -> PathBuf {
        self.archive_dir.join("threads").join(format!("{thread}.jsonl.zst"))
    }

    /// Writes a thread's entries out to its archive file (one entry per line, zstd) and deletes their rows. Entries
    /// never change, so the file is the thread as it was and what clients keep of it stays true.
    fn archive_thread(&mut self, thread: i64) -> Result<()> {
        let entries: Vec<EntryRow> = {
            let mut stmt = self.db.prepare("SELECT * FROM entries WHERE thread = ? ORDER BY n")?;
            stmt.query_map([thread], to_entry)?.collect::<rusqlite::Result<_>>()?
        };
        let path = self.thread_file(thread);
        let mut text = String::new();
        for e in &entries {
            text.push_str(&serde_json::to_string(e)?);
            text.push('\n');
        }
        write_compressed(&path, &text)?;
        let done = (|| -> Result<()> {
            let tx = self.db.transaction()?;
            tx.execute("DELETE FROM entries WHERE thread = ?", [thread])?;
            tx.execute("UPDATE threads SET archived_at = ? WHERE id = ?", params![now_ms(), thread])?;
            tx.commit()?;
            Ok(())
        })();
        if done.is_err() {
            let _ = std::fs::remove_file(&path);
        }
        done
    }

    /// Loads an archived thread's entries back into the database and removes its file.
    fn restore_thread(&mut self, thread: i64) -> Result<()> {
        let entries = self.archived_entries(thread)?;
        let tx = self.db.transaction()?;
        for e in &entries {
            insert_entry(&tx, e)?;
        }
        tx.execute("UPDATE threads SET archived_at = NULL WHERE id = ?", [thread])?;
        tx.commit()?;
        self.archived.retain(|(id, _)| *id != thread);
        let _ = std::fs::remove_file(self.thread_file(thread));
        Ok(())
    }

    /// An archived thread's entries, from its file.
    fn archived_entries(&mut self, thread: i64) -> Result<Vec<EntryRow>> {
        if let Some(at) = self.archived.iter().position(|(id, _)| *id == thread) {
            let cached = self.archived.remove(at);
            let entries = cached.1.clone();
            self.archived.push(cached);
            return Ok(entries);
        }
        let bytes = std::fs::read(self.thread_file(thread))?;
        let text = String::from_utf8(zstd::decode_all(&bytes[..])?)?;
        let entries: Vec<EntryRow> = text.lines().filter(|l| !l.is_empty()).map(serde_json::from_str).collect::<Result<_, _>>()?;
        if self.archived.len() >= ARCHIVE_CACHE {
            self.archived.remove(0);
        }
        self.archived.push((thread, entries.clone()));
        Ok(entries)
    }
}

fn insert_entry(db: &Connection, e: &EntryRow) -> Result<()> {
    db.execute(
        "INSERT INTO entries (thread, n, kind, target, ts, author_kind, author, text, attachments, quotes, declared, client, profile, options, card, at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        params![
            e.thread,
            e.n,
            if e.kind == EntryKind::Edit { "edit" } else { "message" },
            e.target,
            e.ts,
            e.author_kind.as_str(),
            e.author,
            e.text,
            json_list(&e.attachments),
            json_list(&e.quotes),
            e.declared,
            e.client,
            e.profile,
            e.options.as_ref().map(Value::to_string),
            e.card.as_ref().map(Value::to_string),
            e.at
        ],
    )?;
    Ok(())
}

mod usage;
pub use usage::{UsageCall, UsageFile, UsageFor, UsageGroup, UsageTurn};

#[cfg(test)]
mod tests;
