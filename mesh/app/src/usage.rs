//! What the agents spent. Every model call their runtimes write to a transcript (Claude Code's message usage, Codex's
//! token counts) is recorded once in the store (store/usage.rs), with the turn it was in and whom that turn worked for.
//! The transcripts are read as they grow, from where the last read stopped: all of them the first time (what was spent
//! before the station counted), then those of the sessions that ran since, about once a minute. Pages read it added up
//! by day (`summary`), with what it would cost at the providers' API prices.

use std::collections::{HashMap, HashSet};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::Result;
use serde::Serialize;
use serde_json::Value;
use stillfail_shapes::RuntimeKind;
use tracing::{info, warn};

use crate::config::runtime_named;
use crate::former::claude_project;
use crate::settings::Settings;
use crate::store::{SessionRow, Store, UsageCall, UsageFile, UsageFor, UsageGroup, UsageTurn, now_ms};
use crate::transcript::parse_iso;

/// How often the sessions that ran are read again.
const EVERY: Duration = Duration::from_secs(60);
/// Calls a little before a session was made (the runtime's clock against the station's) are still its own.
const SKEW_MS: i64 = 5_000;

// ── prices ─────────────────────────────────────────────────────────────────

/// A model's API prices, in dollars per million tokens. Writing to the cache costs 1.25× input for five minutes, 2× for
/// an hour; fast mode doubles all of it.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Price {
    pub input: f64,
    pub output: f64,
    pub cache_read: f64,
}

/// Standard short-context API list prices (2026-10-02). Longer names first.
/// OpenAI: https://developers.openai.com/api/docs/pricing
/// These are token-cost estimates, not invoices (no long-context or service-tier surcharges).
const PRICES: &[(&str, Price)] = &[
    ("gpt-6-astra", Price { input: 10.0, output: 50.0, cache_read: 1.0 }),
    ("gpt-6.1-sol", Price { input: 2.0, output: 10.0, cache_read: 0.1 }),
    ("gpt-6-sol", Price { input: 2.0, output: 10.0, cache_read: 0.2 }),
    ("gpt-6-luna", Price { input: 0.1, output: 0.5, cache_read: 0.01 }),
    ("gpt-5.6-sol", Price { input: 4.0, output: 20.0, cache_read: 0.4 }),
    ("claude-fable-5-1", Price { input: 10.0, output: 50.0, cache_read: 0.25 }),
    ("claude-mythos-5-1", Price { input: 10.0, output: 50.0, cache_read: 0.25 }),
    ("claude-fable-5", Price { input: 10.0, output: 50.0, cache_read: 1.0 }),
    ("claude-mythos-5", Price { input: 10.0, output: 50.0, cache_read: 1.0 }),
    ("claude-opus-5-5", Price { input: 4.0, output: 20.0, cache_read: 0.2 }),
    ("claude-opus-5", Price { input: 5.0, output: 25.0, cache_read: 0.5 }),
    ("claude-opus-4-8", Price { input: 5.0, output: 25.0, cache_read: 0.5 }),
    ("claude-opus-4-7", Price { input: 5.0, output: 25.0, cache_read: 0.5 }),
    ("claude-opus-4-6", Price { input: 5.0, output: 25.0, cache_read: 0.5 }),
    ("claude-opus-4-5", Price { input: 5.0, output: 25.0, cache_read: 0.5 }),
    ("claude-sonnet-5-5", Price { input: 2.0, output: 10.0, cache_read: 0.2 }),
    ("claude-sonnet-5", Price { input: 2.0, output: 10.0, cache_read: 0.2 }),
    ("claude-sonnet-4-6", Price { input: 3.0, output: 15.0, cache_read: 0.3 }),
    ("claude-sonnet-4-5", Price { input: 3.0, output: 15.0, cache_read: 0.3 }),
    ("claude-haiku-4-5", Price { input: 1.0, output: 5.0, cache_read: 0.1 }),
];

/// The very same table used by `cost`, for inspecting a station's calculation from the usage page.
pub fn price_table() -> Value {
    serde_json::json!({
        "note": "美元 / 100 万 token · 各类 token × 单价后相加；Claude fast ×2。GPT 按标准短上下文估算，仅记录输入、缓存读取和输出。GPT 价目核对于 2026-10-02，Claude 沿用 2026-09 价目",
        "rows": PRICES.iter().map(|(model, p)| serde_json::json!({
            "model": model, "input": p.input, "cacheRead": p.cache_read,
            "cacheWrite": model.starts_with("claude-").then_some(p.input * 1.25),
            "cacheWriteLong": model.starts_with("claude-").then_some(p.input * 2.0), "output": p.output,
        })).collect::<Vec<_>>()
    })
}

/// A model's prices, however a profile spells it (anthropic/claude-opus-5-5, claude-opus-5-5[1m]); None for a model
/// without a list price here.
pub fn price(model: &str) -> Option<Price> {
    let name = stillfail_shapes::model::key(model);
    PRICES.iter().find(|(prefix, _)| name == *prefix || name.strip_prefix(prefix).is_some_and(|suffix| suffix.starts_with('['))).map(|(_, p)| *p)
}

/// What a day's calls of one model would cost at its API prices, in dollars.
pub fn cost(g: &UsageGroup) -> Option<f64> {
    let p = price(g.model.as_deref()?)?;
    let tokens = g.input as f64 * p.input
        + g.cache_write as f64 * p.input * 1.25
        + g.cache_write_long as f64 * p.input * 2.0
        + g.cache_read as f64 * p.cache_read
        + g.output as f64 * p.output;
    Some(tokens / 1e6 * if g.fast { 2.0 } else { 1.0 })
}

// ── reading transcripts ────────────────────────────────────────────────────

/// A transcript's lines read into calls. `model` is the model the transcript last named, carried from read to read.
fn calls_of(runtime: RuntimeKind, text: &str, subagent: bool, model: &mut Option<String>, codex_id: &mut Option<String>) -> Vec<UsageCall> {
    let n = |v: Option<&Value>| v.and_then(Value::as_i64).unwrap_or(0);
    let mut out: Vec<UsageCall> = vec![];
    let mut at_index: HashMap<String, usize> = HashMap::new();
    for line in text.lines() {
        // Most lines are something else: only those that may hold usage are parsed.
        let wanted = if runtime == RuntimeKind::Claude { line.contains("\"usage\"") } else { line.contains("token_count") || line.contains("turn_context") || line.contains("session_meta") };
        if !wanted {
            continue;
        }
        let Ok(r) = serde_json::from_str::<Value>(line) else { continue };
        let at = r.get("timestamp").and_then(Value::as_str).and_then(parse_iso).unwrap_or(0);
        if runtime == RuntimeKind::Claude {
            if r.get("type").and_then(Value::as_str) != Some("assistant") {
                continue;
            }
            let Some(m) = r.get("message") else { continue };
            let (Some(usage), Some(id)) = (m.get("usage"), m.get("id").and_then(Value::as_str)) else { continue };
            let name = m.get("model").and_then(Value::as_str).filter(|m| *m != "<synthetic>");
            if name.is_none() {
                continue;
            }
            let written = n(usage.get("cache_creation_input_tokens"));
            let split = usage.get("cache_creation");
            let long = split.map(|c| n(c.get("ephemeral_1h_input_tokens"))).unwrap_or(0);
            let short = split.map(|c| n(c.get("ephemeral_5m_input_tokens"))).filter(|s| s + long == written).unwrap_or(written - long);
            let call = UsageCall {
                id: id.to_string(),
                at,
                model: name.map(String::from),
                subagent: subagent || r.get("isSidechain").and_then(Value::as_bool).unwrap_or(false),
                fast: usage.get("speed").and_then(Value::as_str) == Some("fast"),
                input: n(usage.get("input_tokens")),
                cache_read: n(usage.get("cache_read_input_tokens")),
                cache_write: short,
                cache_write_long: long,
                output: n(usage.get("output_tokens")),
            };
            // One response is written as several lines (a block each), each with its usage: counted once, at its fullest.
            match at_index.get(id) {
                Some(&i) => out[i].output = out[i].output.max(call.output),
                None => {
                    at_index.insert(id.to_string(), out.len());
                    out.push(call);
                }
            }
        } else {
            let p = r.get("payload").cloned().unwrap_or(Value::Null);
            match r.get("type").and_then(Value::as_str) {
                Some("session_meta") => *codex_id = p.get("id").and_then(Value::as_str).map(String::from).or(codex_id.take()),
                Some("turn_context") => *model = p.get("model").and_then(Value::as_str).map(String::from).or(model.take()),
                Some("event_msg") if p.get("type").and_then(Value::as_str) == Some("token_count") => {
                    let info = p.get("info").filter(|i| !i.is_null());
                    let Some(last) = info.and_then(|i| i.get("last_token_usage")).filter(|l| !l.is_null()) else { continue };
                    // Token counts are told again with rate limits; the running total tells a call from its repeat.
                    let total = info.and_then(|i| i.get("total_token_usage")).map(|t| n(t.get("total_tokens"))).unwrap_or(at);
                    let cached = n(last.get("cached_input_tokens"));
                    out.push(UsageCall {
                        id: format!("codex:{}:{total}", codex_id.as_deref().unwrap_or("")),
                        at,
                        model: model.clone(),
                        subagent,
                        fast: false,
                        input: (n(last.get("input_tokens")) - cached).max(0),
                        cache_read: cached,
                        cache_write: 0,
                        cache_write_long: 0,
                        output: n(last.get("output_tokens")),
                    });
                }
                _ => {}
            }
        }
    }
    out
}

/// What a file holds past `offset`, up to its last whole line, and where that ends. A file now shorter than `offset`
/// was written anew: it is read from its start (calls already recorded stay once).
fn read_from(path: &Path, offset: u64) -> Option<(String, u64)> {
    let size = std::fs::metadata(path).ok()?.len();
    let offset = if size < offset { 0 } else { offset };
    if size == offset {
        return None;
    }
    let mut file = std::fs::File::open(path).ok()?;
    file.seek(SeekFrom::Start(offset)).ok()?;
    let mut bytes = Vec::with_capacity((size - offset) as usize);
    file.take(size - offset).read_to_end(&mut bytes).ok()?;
    let cut = bytes.iter().rposition(|b| *b == b'\n').map(|i| i + 1)?;
    bytes.truncate(cut);
    Some((String::from_utf8_lossy(&bytes).into_owned(), offset + cut as u64))
}

fn jsonl_in(dir: &Path) -> Vec<PathBuf> {
    std::fs::read_dir(dir).into_iter().flatten().flatten().map(|e| e.path()).filter(|p| p.extension().is_some_and(|x| x == "jsonl") && p.is_file()).collect()
}

/// A Claude Code session's transcripts in a project directory: its own, and its sub-agents' beside it
/// (`<id>/subagents/*.jsonl`). `only`: that runtime session's alone (a session continued from a terminal shares its
/// directory with the terminal's own).
fn claude_files(dir: &Path, only: Option<&str>) -> Vec<(PathBuf, bool)> {
    let mut out: Vec<(PathBuf, bool)> = match only {
        Some(id) => vec![dir.join(format!("{id}.jsonl"))].into_iter().filter(|p| p.is_file()).map(|p| (p, false)).collect(),
        None => jsonl_in(dir).into_iter().map(|p| (p, false)).collect(),
    };
    let ids: Vec<String> = out.iter().filter_map(|(p, _)| Some(p.file_stem()?.to_string_lossy().into_owned())).collect();
    for id in ids {
        out.extend(jsonl_in(&dir.join(id).join("subagents")).into_iter().map(|p| (p, true)));
    }
    out
}

fn rollouts_in(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in std::fs::read_dir(dir).into_iter().flatten().flatten() {
        let path = entry.path();
        if path.is_dir() {
            rollouts_in(&path, out);
        } else if entry.file_name().to_string_lossy().starts_with("rollout-") && path.extension().is_some_and(|x| x == "jsonl") {
            out.push(path);
        }
    }
}

/// A Codex transcript's session id and the directory it ran in, from its first line.
fn codex_meta(path: &Path) -> Option<(String, String)> {
    let mut first = String::new();
    std::io::BufRead::read_line(&mut std::io::BufReader::new(std::fs::File::open(path).ok()?), &mut first).ok()?;
    let r: Value = serde_json::from_str(&first).ok()?;
    let p = r.get("payload")?;
    Some((p.get("id")?.as_str()?.to_string(), p.get("cwd")?.as_str()?.to_string()))
}

// ── the counter ────────────────────────────────────────────────────────────

#[derive(Default)]
struct State {
    /// When the last read started; 0 before the first.
    last: i64,
    /// The first read (everything) is under way.
    first: bool,
}

pub struct Usage {
    store: Arc<Store>,
    settings: Arc<Settings>,
    state: Mutex<State>,
}

/// The pages' summary: every day's calls from `from` until `to`, by thread, person, profile and model.
#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct UsageRow {
    pub day: String,
    pub session: String,
    pub thread: Option<i64>,
    pub person: Option<String>,
    pub profile: Option<String>,
    pub runtime: String,
    pub model: Option<String>,
    pub calls: i64,
    pub input: i64,
    pub cache_read: i64,
    pub cache_write: i64,
    pub output: i64,
    /// At the model's API prices, in dollars; None for a model without one.
    pub cost: Option<f64>,
}

impl Usage {
    pub fn new(store: Arc<Store>, settings: Arc<Settings>) -> Arc<Usage> {
        Arc::new(Usage { store, settings, state: Mutex::default() })
    }

    /// Reads the transcripts now and about once a minute from now on.
    pub fn start(self: &Arc<Self>) {
        let me = Arc::downgrade(self);
        tokio::spawn(async move {
            loop {
                let Some(usage) = me.upgrade() else { return };
                let reader = usage.clone();
                match tokio::task::spawn_blocking(move || reader.read()).await {
                    Ok(Err(e)) => warn!(error = %format!("{e:#}"), "usage not read"),
                    Err(e) => warn!(error = %e, "usage reading stopped"),
                    Ok(Ok(_)) => {}
                }
                drop(usage);
                tokio::time::sleep(EVERY).await;
            }
        });
    }

    /// Whether everything is still being read for the first time.
    pub fn reading_all(&self) -> bool {
        let state = self.state.lock().unwrap();
        state.first || state.last == 0
    }

    /// One read: the transcripts of every session the first time, then of those that ran since the last. How many calls
    /// were new.
    pub fn read(&self) -> Result<usize> {
        let started = now_ms();
        let last = {
            let mut state = self.state.lock().unwrap();
            state.first = state.last == 0;
            state.last
        };
        let sessions: Vec<SessionRow> = self.store.list_sessions()?;
        let wanted: Option<HashSet<String>> = if last == 0 { None } else { Some(self.store.usage_active_sessions(last - EVERY.as_millis() as i64)?.into_iter().collect()) };
        let known = self.store.usage_files()?;
        let config = self.settings.config();
        let mut added = 0;
        // Claude Code: each session's project directory (named after where it runs), in the shared transcripts and in
        // any profile's own.
        let mut claude_roots = vec![config.data_dir.join("transcripts").join("claude")];
        let mut codex_roots = vec![config.data_dir.join("transcripts").join("codex")];
        for p in &config.profiles {
            claude_roots.push(p.home.join("projects"));
            codex_roots.push(p.home.join("sessions"));
        }
        let distinct = |roots: Vec<PathBuf>| -> Vec<PathBuf> {
            let mut seen = HashSet::new();
            roots.into_iter().filter(|r| r.is_dir()).filter(|r| seen.insert(std::fs::canonicalize(r).unwrap_or_else(|_| r.clone()))).collect()
        };
        let (claude_roots, codex_roots) = (distinct(claude_roots), distinct(codex_roots));
        let mut seen_files: HashSet<PathBuf> = HashSet::new();
        for s in sessions.iter().filter(|s| wanted.as_ref().is_none_or(|w| w.contains(&s.key))) {
            if runtime_named(&s.runtime) != Some(RuntimeKind::Claude) {
                continue;
            }
            let project = claude_project(Path::new(s.cwd.as_deref().unwrap_or(&s.workspace)));
            let only = if s.cwd.is_some() { s.runtime_session_id.as_deref() } else { None };
            if s.cwd.is_some() && only.is_none() {
                continue;
            }
            let mut turns = None;
            for root in &claude_roots {
                for (path, subagent) in claude_files(&root.join(&project), only) {
                    let real = std::fs::canonicalize(&path).unwrap_or_else(|_| path.clone());
                    if !seen_files.insert(real) {
                        continue;
                    }
                    added += self.read_file(&path, RuntimeKind::Claude, subagent, s, &known, &mut turns)?;
                }
            }
        }
        // Codex: its transcripts are kept by date, so each new one is matched to a session by its id, or by where it ran.
        let mut rollouts = vec![];
        for root in &codex_roots {
            rollouts_in(root, &mut rollouts);
        }
        if !rollouts.is_empty() {
            let codex: Vec<&SessionRow> = sessions.iter().filter(|s| runtime_named(&s.runtime) == Some(RuntimeKind::Codex)).collect();
            let mut turns_of: HashMap<String, Option<Vec<UsageTurn>>> = HashMap::new();
            for path in rollouts {
                let key = path.to_string_lossy().into_owned();
                let session = match known.get(&key) {
                    Some(file) => file.session.clone(),
                    None => codex_meta(&path).and_then(|(id, cwd)| {
                        codex
                            .iter()
                            .find(|s| s.runtime_session_id.as_deref() == Some(id.as_str()) || (s.cwd.is_none() && s.workspace == cwd))
                            .map(|s| s.key.clone())
                    }),
                };
                let Some(session) = session else {
                    if !known.contains_key(&key) {
                        // None of the station's (a terminal's own): passed over from now on.
                        let size = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
                        self.store.record_usage(&key, &UsageFile { session: None, offset: size, model: None }, "codex", &[])?;
                    }
                    continue;
                };
                if wanted.as_ref().is_some_and(|w| !w.contains(&session)) && known.contains_key(&key) {
                    continue;
                }
                let Some(s) = codex.iter().find(|s| s.key == session) else { continue };
                let turns = turns_of.entry(session.clone()).or_default();
                added += self.read_file(&path, RuntimeKind::Codex, false, s, &known, turns)?;
            }
        }
        {
            let mut state = self.state.lock().unwrap();
            state.last = started;
            state.first = false;
        }
        if added > 0 {
            if last == 0 {
                info!(calls = added, ms = now_ms() - started, "usage read from every transcript");
            }
            self.store.usage_changed();
        }
        Ok(added)
    }

    /// Reads one transcript of `session` on from where it was left, and records its calls.
    fn read_file(&self, path: &Path, runtime: RuntimeKind, subagent: bool, session: &SessionRow, known: &HashMap<String, UsageFile>, turns: &mut Option<Vec<UsageTurn>>) -> Result<usize> {
        let key = path.to_string_lossy().into_owned();
        let before = known.get(&key).cloned().unwrap_or_default();
        let Some((text, offset)) = read_from(path, before.offset) else { return Ok(0) };
        let mut model = before.model.clone();
        // A Codex transcript's id is in its first line: read again for a file read on from the middle.
        let mut codex_id = if runtime == RuntimeKind::Codex { codex_meta(path).map(|(id, _)| id) } else { None };
        let calls = calls_of(runtime, &text, subagent, &mut model, &mut codex_id);
        // What ran before the station had the session (a terminal's, continued here) is not the station's.
        let calls: Vec<UsageCall> = calls.into_iter().filter(|c| c.at >= session.created_at - SKEW_MS).collect();
        if turns.is_none() {
            *turns = Some(self.store.usage_turns(&session.key)?);
        }
        let turns = turns.as_deref().unwrap_or_default();
        let with: Vec<(UsageCall, UsageFor)> = calls
            .into_iter()
            .map(|c| {
                // The turn it was made in: the last to start before it (the first, for one before them all).
                let i = turns.partition_point(|t| t.started_at <= c.at);
                let of = turns[i.saturating_sub(1)].of.clone();
                (c, of)
            })
            .collect();
        let file = UsageFile { session: Some(session.key.clone()), offset, model };
        self.store.record_usage(&key, &file, crate::config::runtime_name(runtime), &with)
    }

    /// Every day's calls from `from` until `to` (ms), days as the asker's clock has them (`utc_offset_min`).
    pub fn summary(&self, from: i64, to: i64, utc_offset_min: i64) -> Result<Vec<UsageRow>> {
        Ok(self
            .store
            .usage_groups(from, to, utc_offset_min)?
            .into_iter()
            .map(|g| UsageRow {
                cost: cost(&g),
                day: g.day,
                session: g.session,
                thread: g.thread,
                person: g.person,
                profile: g.profile,
                runtime: g.runtime,
                model: g.model,
                calls: g.calls,
                input: g.input,
                cache_read: g.cache_read,
                cache_write: g.cache_write + g.cache_write_long,
                output: g.output,
            })
            .collect())
    }
}

#[cfg(test)]
mod tests;
