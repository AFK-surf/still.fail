//! Sessions this machine's own Claude Code and Codex keep (run in a terminal, in ~/.claude and ~/.codex), for a person
//! to go on with one in a chat (Hub::continue_machine_session). Only read: going on with one copies its transcript into
//! the station's shared transcripts, so the original stays as it was and can still go on in the terminal on its own.
//! Formats (pinned against real files, 2026-09):
//! - claude: ~/.claude/projects/<encoded cwd>/<id>.jsonl; its records carry `cwd`; `custom-title` (named by hand) and
//!   `ai-title` records name it, the latest counting; `isCompactSummary` users are the runtime's own summaries and
//!   `isApiErrorMessage` assistants its own errors ("Not logged in").
//! - codex: $CODEX_HOME/sessions/YYYY/MM/DD/rollout-…-<id>.jsonl, its first record session_meta {id, cwd}; context it
//!   adds comes as people's messages, each wrapped in a tag; $CODEX_HOME/session_index.jsonl names threads.

use std::io::{BufRead, BufReader, Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

use anyhow::{Result, anyhow};
use ember_shapes::RuntimeKind;
use serde::Serialize;
use serde_json::Value;

use crate::machine_logins::{Env, codex_home, home_of};
use crate::transcript::{injected, parse_iso};

/// Where the machine's runtimes keep their sessions.
#[derive(Debug, Clone)]
pub struct MachineRoots {
    /// Claude Code's projects/.
    pub claude: PathBuf,
    /// Codex's sessions/.
    pub codex: PathBuf,
}

impl MachineRoots {
    pub fn of(env: &Env) -> MachineRoots {
        MachineRoots { claude: home_of(env).join(".claude").join("projects"), codex: codex_home(env).join("sessions") }
    }

    fn root(&self, runtime: RuntimeKind) -> &Path {
        if runtime == RuntimeKind::Claude { &self.claude } else { &self.codex }
    }
}

/// A session of the machine's, as the pages list it.
#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MachineSession {
    pub runtime: RuntimeKind,
    /// The runtime's own id: what it resumes.
    pub id: String,
    /// The directory it ran in.
    pub cwd: String,
    /// Its name, when the runtime gave it one.
    pub title: Option<String>,
    /// What was asked first.
    pub first: Option<String>,
    /// The model it last ran.
    pub model: Option<String>,
    /// When its transcript was last written, in ms.
    pub updated_at: i64,
    pub size: u64,
    /// The station's session already going on with it, if any.
    pub session: Option<String>,
    #[serde(skip)]
    pub path: PathBuf,
}

/// Enough of a first message to know it by.
const FIRST: usize = 200;
/// Records read from a transcript's start for its directory and first message.
const HEAD_RECORDS: usize = 400;
/// Bytes read from a transcript's end for its latest name.
const TAIL: u64 = 256 * 1024;

/// The machine's sessions, most recently written first, at most `limit`: those that ran somewhere and asked something.
pub fn list(roots: &MachineRoots, limit: usize) -> Vec<MachineSession> {
    let mut files: Vec<(RuntimeKind, PathBuf, i64, u64)> = vec![];
    for dir in std::fs::read_dir(&roots.claude).into_iter().flatten().flatten() {
        for file in std::fs::read_dir(dir.path()).into_iter().flatten().flatten() {
            let path = file.path();
            if path.extension().is_some_and(|e| e == "jsonl") {
                files.extend(stamp(&path).map(|(at, size)| (RuntimeKind::Claude, path, at, size)));
            }
        }
    }
    let mut rollouts = vec![];
    rollouts_in(&roots.codex, &mut rollouts);
    files.extend(rollouts.into_iter().filter_map(|path| stamp(&path).map(|(at, size)| (RuntimeKind::Codex, path, at, size))));
    files.sort_by(|a, b| b.2.cmp(&a.2));
    let names = codex_names(roots);
    // Codex may keep a thread in more than one file: the latest written stands for it.
    let mut seen = std::collections::HashSet::new();
    files
        .into_iter()
        .filter_map(|(runtime, path, at, size)| read(runtime, &path, at, size))
        .filter(|s| seen.insert((s.runtime, s.id.clone())))
        .take(limit)
        .map(|s| named(s, &names))
        .collect()
}

/// One of the machine's sessions, by its runtime and id.
pub fn find(roots: &MachineRoots, runtime: RuntimeKind, id: &str) -> Option<MachineSession> {
    if id.is_empty() || !id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
        return None;
    }
    let path = if runtime == RuntimeKind::Claude {
        std::fs::read_dir(&roots.claude).ok()?.flatten().map(|d| d.path().join(format!("{id}.jsonl"))).find(|p| p.is_file())?
    } else {
        let mut rollouts = vec![];
        rollouts_in(&roots.codex, &mut rollouts);
        let mut mine: Vec<(i64, PathBuf)> = rollouts.into_iter().filter(|p| rollout_of(p, id)).filter_map(|p| stamp(&p).map(|(at, _)| (at, p))).collect();
        mine.sort_by(|a, b| b.0.cmp(&a.0));
        mine.into_iter().map(|(_, p)| p).find(|p| stamp(p).and_then(|(at, size)| read(runtime, p, at, size)).is_some_and(|s| s.id == id))?
    };
    let (at, size) = stamp(&path)?;
    read(runtime, &path, at, size).filter(|s| s.id == id).map(|s| named(s, &codex_names(roots)))
}

/// Copies a session's transcript to where the station's runtimes keep theirs (`shared`: data/transcripts/<runtime>),
/// at the same place under it, so a profile resumes it there: for Codex every file it keeps the thread in. The
/// originals are not touched. Where the transcript read is.
pub fn copy_transcript(roots: &MachineRoots, session: &MachineSession, shared: &Path) -> Result<PathBuf> {
    let root = roots.root(session.runtime);
    let mut files = vec![session.path.clone()];
    if session.runtime == RuntimeKind::Codex {
        let mut rollouts = vec![];
        rollouts_in(root, &mut rollouts);
        files.extend(rollouts.into_iter().filter(|p| *p != session.path && rollout_of(p, &session.id)));
    }
    for from in &files {
        let to = shared.join(from.strip_prefix(root).map_err(|_| anyhow!("{} is not the machine's", from.display()))?);
        std::fs::create_dir_all(to.parent().unwrap_or(shared))?;
        let partial = to.with_extension("jsonl.part");
        std::fs::copy(from, &partial)?;
        std::fs::rename(&partial, &to)?;
    }
    Ok(shared.join(session.path.strip_prefix(root)?))
}

/// A rollout file of a thread: rollout-<time>-<id>.jsonl, or rollout-<time>-<id>_<more>.jsonl.
fn rollout_of(path: &Path, id: &str) -> bool {
    let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    name.ends_with(&format!("-{id}.jsonl")) || name.contains(&format!("-{id}_"))
}

/// Something said in a session: by the person (else by its agent), its words, when.
#[derive(Debug, Clone, PartialEq)]
pub struct Said {
    pub person: bool,
    pub text: String,
    pub at: Option<i64>,
}

/// What was said in a session's transcript, oldest first: people's messages, and each turn's words of the agent in one
/// message (its thinking and tool calls left out, and the runtime's own summaries and command output).
pub fn conversation(runtime: RuntimeKind, path: &Path) -> Vec<Said> {
    let Ok(file) = std::fs::File::open(path) else { return vec![] };
    let records: Vec<Value> = BufReader::new(file).lines().map_while(Result::ok).filter_map(|l| serde_json::from_str(&l).ok()).collect();
    let events = runtime == RuntimeKind::Codex && has_codex_events(&records);
    let mut out: Vec<Said> = vec![];
    for r in &records {
        let at = r.get("timestamp").and_then(Value::as_str).and_then(parse_iso);
        for (person, text) in said(runtime, events, r) {
            match out.last_mut() {
                Some(last) if !person && !last.person => {
                    last.text.push_str("\n\n");
                    last.text.push_str(&text);
                }
                _ => out.push(Said { person, text, at }),
            }
        }
    }
    out
}

/// What a record says: Claude's messages; Codex's events of what was said when it writes them (only what the person
/// typed, none of the context it adds), else its model messages.
fn said(runtime: RuntimeKind, events: bool, r: &Value) -> Vec<(bool, String)> {
    match (runtime, events) {
        (RuntimeKind::Claude, _) => claude_said(r),
        (_, true) => codex_event_said(r),
        _ => codex_said(r),
    }
}

fn has_codex_events(records: &[Value]) -> bool {
    records.iter().any(|r| codex_event_said(r).iter().any(|(person, _)| *person))
}

/// Codex's events of what was said: item_completed with a UserMessage or AgentMessage item (newer), user_message and
/// agent_message (older).
fn codex_event_said(r: &Value) -> Vec<(bool, String)> {
    let Some(p) = r.get("payload").filter(|_| r.get("type").and_then(Value::as_str) == Some("event_msg")) else { return vec![] };
    let str_of = |v: Option<&Value>| v.and_then(Value::as_str).map(String::from);
    let (person, text) = match p.get("type").and_then(Value::as_str) {
        Some("user_message") => (true, str_of(p.get("message")).and_then(|t| typed(&t).map(String::from))),
        Some("agent_message") => (false, str_of(p.get("message"))),
        Some("item_completed") => {
            let item = p.get("item");
            let person = match item.and_then(|i| i.get("type")).and_then(Value::as_str) {
                Some("UserMessage") => true,
                Some("AgentMessage") => false,
                _ => return vec![],
            };
            let parts: Vec<&str> = item.and_then(|i| i.get("content")).and_then(Value::as_array).into_iter().flatten().filter_map(|b| b.get("text").and_then(Value::as_str)).collect();
            (person, Some(parts.into_iter().filter_map(|t| if person { typed(t) } else { Some(t) }).collect::<Vec<_>>().join("\n")))
        }
        _ => return vec![],
    };
    text.map(|t| t.trim().to_string()).filter(|t| !t.is_empty() && !(person && (wrapped(t) || not_said(t)))).map(|t| vec![(person, t)]).unwrap_or_default()
}

fn named(mut session: MachineSession, names: &std::collections::HashMap<String, String>) -> MachineSession {
    if session.title.is_none() {
        session.title = names.get(&session.id).cloned();
    }
    session
}

fn stamp(path: &Path) -> Option<(i64, u64)> {
    let meta = std::fs::metadata(path).ok()?;
    let at = meta.modified().ok()?.duration_since(std::time::UNIX_EPOCH).ok()?.as_millis() as i64;
    Some((at, meta.len()))
}

fn rollouts_in(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in std::fs::read_dir(dir).into_iter().flatten().flatten() {
        let path = entry.path();
        if path.is_dir() {
            rollouts_in(&path, out);
        } else if entry.file_name().to_string_lossy().starts_with("rollout-") && path.extension().is_some_and(|e| e == "jsonl") {
            out.push(path);
        }
    }
}

fn read(runtime: RuntimeKind, path: &Path, updated_at: i64, size: u64) -> Option<MachineSession> {
    let file = std::fs::File::open(path).ok()?;
    let head: Vec<Value> = BufReader::new(file).lines().map_while(Result::ok).take(HEAD_RECORDS).filter_map(|l| serde_json::from_str(&l).ok()).collect();
    let text = |v: Option<&Value>| v.and_then(Value::as_str).map(String::from);
    let events = runtime == RuntimeKind::Codex && has_codex_events(&head);
    let first_said = |records: &[Value]| records.iter().find_map(|r| said(runtime, events, r).into_iter().find(|(person, _)| *person).map(|(_, t)| t));
    let first = first_said(&head).map(|t| clip(&t, FIRST));
    let (id, cwd) = if runtime == RuntimeKind::Claude {
        (path.file_stem()?.to_string_lossy().into_owned(), head.iter().find_map(|r| text(r.get("cwd")))?)
    } else {
        let meta = head.iter().find(|r| r.get("type").and_then(Value::as_str) == Some("session_meta"))?.get("payload")?;
        (text(meta.get("id"))?, text(meta.get("cwd"))?)
    };
    first.as_ref()?;
    let mut records = head;
    records.extend(tail(path, size));
    let title = if runtime == RuntimeKind::Claude { claude_title(&records) } else { None };
    let model = records.iter().rev().find_map(|r| {
        let model = if runtime == RuntimeKind::Claude {
            r.get("message").filter(|_| r.get("type").and_then(Value::as_str) == Some("assistant")).and_then(|m| m.get("model"))
        } else {
            r.get("payload").filter(|_| r.get("type").and_then(Value::as_str) == Some("turn_context")).and_then(|p| p.get("model"))
        };
        model.and_then(Value::as_str).filter(|m| !m.starts_with('<')).map(String::from)
    });
    Some(MachineSession { runtime, id, cwd, title, first, model, updated_at, size, session: None, path: path.to_path_buf() })
}

/// The records in the last part of a file (whole lines only).
fn tail(path: &Path, size: u64) -> Vec<Value> {
    let Ok(mut file) = std::fs::File::open(path) else { return vec![] };
    let from = size.saturating_sub(TAIL);
    let mut bytes = vec![];
    if file.seek(SeekFrom::Start(from)).is_err() || file.read_to_end(&mut bytes).is_err() {
        return vec![];
    }
    let text = String::from_utf8_lossy(&bytes);
    let whole = if from > 0 { text.split_once('\n').map(|(_, rest)| rest).unwrap_or("") } else { &text };
    whole.lines().filter_map(|l| serde_json::from_str(l).ok()).collect()
}

/// The name given by hand, else the runtime's latest.
fn claude_title(records: &[Value]) -> Option<String> {
    let latest = |kind: &str, field: &str| {
        records.iter().rev().find(|r| r.get("type").and_then(Value::as_str) == Some(kind)).and_then(|r| r.get(field)).and_then(Value::as_str).map(str::trim).filter(|t| !t.is_empty()).map(String::from)
    };
    latest("custom-title", "customTitle").or_else(|| latest("ai-title", "aiTitle")).or_else(|| latest("summary", "summary"))
}

/// What a person typed that the runtime keeps as their message though it is not what they said: a slash command and
/// its output, the caveat around it, a reminder it added.
fn not_said(text: &str) -> bool {
    let t = text.trim_start();
    t.is_empty() || ["<command-", "<local-command", "<system-reminder>", "<bash-", "<user-memory-input>", "Caveat: ", "This session is being continued from a previous conversation"].iter().any(|p| t.starts_with(p))
}

fn claude_said(r: &Value) -> Vec<(bool, String)> {
    let kind = r.get("type").and_then(Value::as_str).unwrap_or("");
    let flag = |k: &str| r.get(k) == Some(&Value::Bool(true));
    if (kind != "user" && kind != "assistant") || ["isMeta", "isSidechain", "isCompactSummary", "isApiErrorMessage"].iter().any(|k| flag(k)) {
        return vec![];
    }
    let person = kind == "user";
    let texts: Vec<String> = match r.get("message").and_then(|m| m.get("content")) {
        Some(Value::String(text)) => vec![text.clone()],
        Some(Value::Array(blocks)) => blocks
            .iter()
            .filter(|b| b.get("type").and_then(Value::as_str) == Some("text"))
            .filter_map(|b| b.get("text").and_then(Value::as_str).map(String::from))
            .collect(),
        _ => vec![],
    };
    texts.into_iter().filter(|t| !t.trim().is_empty() && !(person && not_said(t))).map(|t| (person, t.trim().to_string())).collect()
}

fn codex_said(r: &Value) -> Vec<(bool, String)> {
    let p = r.get("payload");
    if r.get("type").and_then(Value::as_str) != Some("response_item") || p.and_then(|p| p.get("type")).and_then(Value::as_str) != Some("message") {
        return vec![];
    }
    let person = match p.and_then(|p| p.get("role")).and_then(Value::as_str) {
        Some("user") => true,
        Some("assistant") => false,
        _ => return vec![],
    };
    // Each part on its own: Codex puts its context in parts of their own, beside what the person said.
    let text: Vec<&str> = p
        .and_then(|p| p.get("content"))
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|b| b.get("text").and_then(Value::as_str))
        .filter_map(|t| if person { typed(t) } else { Some(t) })
        .filter(|t| !t.trim().is_empty() && !(person && (injected(t) || wrapped(t) || not_said(t))))
        .collect();
    let text = text.join("\n");
    if text.trim().is_empty() {
        return vec![];
    }
    vec![(person, text.trim().to_string())]
}

/// What the person typed in a part of a Codex user message: none of the instructions it adds, and of the context an
/// editor adds before a request ("# Context from my IDE setup:", "# Files mentioned by the user:", "## Referenced
/// chats…"), only the request.
fn typed(text: &str) -> Option<&str> {
    let t = text.trim_start();
    if t.starts_with("# AGENTS.md instructions") {
        return None;
    }
    if !t.starts_with('#') {
        return Some(text);
    }
    ["## My request for Codex:", "## My request:"].iter().find_map(|mark| t.rfind(mark).map(|at| t[at + mark.len()..].trim())).or(Some(text))
}

/// Context Codex adds as a person's message, one tag around all of it (<recommended_plugins>…</recommended_plugins>).
fn wrapped(text: &str) -> bool {
    let t = text.trim();
    let Some(name) = t.strip_prefix('<').and_then(|rest| rest.split_once('>')).map(|(name, _)| name) else { return false };
    !name.is_empty() && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-') && t.ends_with(&format!("</{name}>"))
}

/// The names Codex gave its threads (session_index.jsonl beside sessions/: the latest line for an id counts).
fn codex_names(roots: &MachineRoots) -> std::collections::HashMap<String, String> {
    let Some(index) = roots.codex.parent().map(|home| home.join("session_index.jsonl")) else { return Default::default() };
    let Ok(file) = std::fs::File::open(index) else { return Default::default() };
    BufReader::new(file)
        .lines()
        .map_while(Result::ok)
        .filter_map(|l| serde_json::from_str::<Value>(&l).ok())
        .filter_map(|r| Some((r.get("id")?.as_str()?.to_string(), r.get("thread_name")?.as_str()?.trim().to_string())))
        .filter(|(_, name)| !name.is_empty())
        .collect()
}

fn clip(text: &str, max: usize) -> String {
    let line = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if line.chars().count() > max { format!("{}…", line.chars().take(max).collect::<String>()) } else { line }
}

#[cfg(test)]
pub(crate) mod tests;
