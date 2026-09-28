//! Reads a runtime's own session transcript into one readable timeline for the pages. Formats (pinned against real
//! files, 2026-09):
//! - claude: $CLAUDE_CONFIG_DIR/projects/<cwd>/<id>.jsonl, lines of {type: user|assistant, message: {content: string |
//!   blocks}, isSidechain}
//! - codex: $CODEX_HOME/sessions/**/rollout-*<id>.jsonl, lines of {type: response_item, payload: message | reasoning |
//!   function_call | …}

use std::collections::{HashMap, HashSet};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

use ember_shapes::RuntimeKind;
use serde::Serialize;
use serde_json::{Map, Value};

#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TimelineEntry {
    pub at: Option<String>,
    /// user | assistant | thinking | tool_call | tool_result
    pub kind: String,
    pub text: String,
    /// Tool name for tool_call entries.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool: Option<String>,
    /// For tool_result: false when the tool reported an error.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ok: Option<bool>,
    /// Links a tool_call to its tool_result.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub call_id: Option<String>,
    /// Produced by a subagent rather than the main conversation.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subagent: Option<bool>,
}

impl TimelineEntry {
    fn new(at: Option<String>, kind: &str, text: String) -> TimelineEntry {
        TimelineEntry { at, kind: kind.into(), text, tool: None, ok: None, call_id: None, subagent: None }
    }
}

const MAX_TEXT: usize = 4000;

pub fn transcript_path(runtime: RuntimeKind, home: &Path, runtime_session_id: &str) -> Option<PathBuf> {
    if runtime == RuntimeKind::Claude {
        for dir in std::fs::read_dir(home.join("projects")).ok()?.flatten() {
            let path = dir.path().join(format!("{runtime_session_id}.jsonl"));
            if path.exists() {
                return Some(path);
            }
        }
        return None;
    }
    fn find(dir: &Path, id: &str) -> Option<PathBuf> {
        for entry in std::fs::read_dir(dir).ok()?.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().to_string();
            if path.is_dir() {
                if let Some(found) = find(&path, id) {
                    return Some(found);
                }
            } else if name.starts_with("rollout-") && name.ends_with(&format!("{id}.jsonl")) {
                return Some(path);
            }
        }
        None
    }
    find(&home.join("sessions"), runtime_session_id)
}

#[derive(Serialize, Debug, Clone, Default, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptUsage {
    /// Model requests with reported usage.
    pub model_calls: u64,
    /// Input tokens, cached ones included.
    pub input_tokens: u64,
    pub cached_tokens: u64,
    pub output_tokens: u64,
    /// The model the runtime last reported, if any.
    pub model: Option<String>,
}

fn clip(text: &str) -> String {
    let count = text.chars().count();
    if count > MAX_TEXT {
        format!("{}\n… ({} more characters)", text.chars().take(MAX_TEXT).collect::<String>(), count - MAX_TEXT)
    } else {
        text.to_string()
    }
}

fn pretty(value: &Value) -> String {
    serde_json::to_string_pretty(value).unwrap_or_default()
}

fn to_text(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Array(items) => items
            .iter()
            .map(|v| match v.get("text") {
                Some(text) if v.is_object() => text.as_str().map(String::from).unwrap_or_else(|| text.to_string()),
                _ => to_text(v),
            })
            .collect::<Vec<_>>()
            .join("\n"),
        other => pretty(other),
    }
}

/// Posting a message: the station keeps what an agent posted (its messages), so a transcript's copies of the calls are
/// left out.
pub fn is_posting(tool: &str) -> bool {
    tool == "mcp__ember__chat_post"
}

/// What reading a transcript keeps between reads: the calls left out (their results follow later), and calls taken out
/// of a script.
#[derive(Default)]
struct ReadState {
    skip: HashSet<String>,
    inner: HashMap<String, usize>,
}

fn string_of(v: Option<&Value>) -> Option<String> {
    v.and_then(Value::as_str).map(String::from)
}

fn claude_timeline(records: &[Value], state: &mut ReadState) -> Vec<TimelineEntry> {
    let mut out = Vec::new();
    for r in records {
        let kind = r.get("type").and_then(Value::as_str).unwrap_or("");
        if (kind != "user" && kind != "assistant") || r.get("isMeta") == Some(&Value::Bool(true)) {
            continue;
        }
        let at = string_of(r.get("timestamp"));
        let subagent = (r.get("isSidechain") == Some(&Value::Bool(true))).then_some(true);
        let entry = |kind: &str, text: String| TimelineEntry { subagent, ..TimelineEntry::new(at.clone(), kind, text) };
        let content = r.get("message").and_then(|m| m.get("content"));
        if let Some(Value::String(text)) = content {
            out.push(entry(kind, clip(text)));
            continue;
        }
        for block in content.and_then(Value::as_array).into_iter().flatten() {
            let text_of = |k: &str| block.get(k).and_then(Value::as_str).filter(|t| !t.is_empty());
            match block.get("type").and_then(Value::as_str) {
                Some("text") => out.extend(text_of("text").map(|t| entry(kind, clip(t)))),
                Some("thinking") => out.extend(text_of("thinking").map(|t| entry("thinking", clip(t)))),
                Some("tool_use") => {
                    let name = block.get("name").and_then(Value::as_str).unwrap_or("").to_string();
                    let id = string_of(block.get("id"));
                    if is_posting(&name) {
                        state.skip.extend(id);
                        continue;
                    }
                    out.push(TimelineEntry { tool: Some(name), call_id: id, ..entry("tool_call", clip(&pretty(block.get("input").unwrap_or(&Value::Null)))) });
                }
                Some("tool_result") => {
                    let id = string_of(block.get("tool_use_id"));
                    if id.as_ref().is_some_and(|i| state.skip.contains(i)) {
                        continue;
                    }
                    let failed = block.get("is_error").and_then(Value::as_bool).unwrap_or(false);
                    out.push(TimelineEntry { ok: Some(!failed), call_id: id, ..entry("tool_result", clip(&to_text(block.get("content").unwrap_or(&Value::Null)))) });
                }
                _ => {}
            }
        }
    }
    out
}

/// Codex prepends context it generated itself as user messages; they are not what anyone said.
fn injected(text: &str) -> bool {
    let t = text.trim_start();
    ["environment_context", "user_instructions", "permissions", "skills_instructions", "collaboration_mode"].iter().any(|tag| {
        t.strip_prefix('<').and_then(|rest| rest.strip_prefix(tag)).is_some_and(|after| after.is_empty() || !after.chars().next().unwrap().is_alphanumeric() && after.chars().next() != Some('_'))
    })
}

fn codex_timeline(records: &[Value], state: &mut ReadState) -> Vec<TimelineEntry> {
    let mut out = Vec::new();
    for r in records {
        if r.get("type").and_then(Value::as_str) != Some("response_item") {
            continue;
        }
        let p = r.get("payload").cloned().unwrap_or(Value::Null);
        let at = string_of(r.get("timestamp"));
        let kind = p.get("type").and_then(Value::as_str).unwrap_or("");
        let name = p.get("name").and_then(Value::as_str).unwrap_or("").to_string();
        let call_id = string_of(p.get("call_id"));
        match kind {
            "message" => {
                let role = p.get("role").and_then(Value::as_str).unwrap_or("");
                if role != "user" && role != "assistant" {
                    continue;
                }
                let text = to_text(p.get("content").unwrap_or(&Value::Null));
                if role == "user" && injected(&text) {
                    continue;
                }
                if !text.trim().is_empty() {
                    out.push(TimelineEntry::new(at, role, clip(&text)));
                }
            }
            "reasoning" => {
                let content = p.get("content").filter(|c| c.as_array().is_some_and(|a| !a.is_empty()));
                let text = to_text(content.or(p.get("summary")).unwrap_or(&Value::Array(vec![])));
                if !text.trim().is_empty() {
                    out.push(TimelineEntry::new(at, "thinking", clip(&text)));
                }
            }
            "custom_tool_call" if name == "exec" => {
                // Codex's code mode: the model calls tools from a script. The calls in it are the steps (posts are the
                // station's own record); the script itself is one only when it does more than call them.
                let script = p.get("input").and_then(Value::as_str).unwrap_or("").to_string();
                let (calls, only) = script_calls(&script);
                let others: Vec<(String, Value)> = calls.into_iter().filter(|(tool, _)| !is_posting(tool)).collect();
                if only && others.is_empty() {
                    state.skip.extend(call_id);
                    continue;
                }
                if !only {
                    out.push(TimelineEntry { tool: Some("exec".into()), call_id: call_id.clone(), ..TimelineEntry::new(at.clone(), "tool_call", clip(&script)) });
                }
                for (i, (tool, args)) in others.iter().enumerate() {
                    // The script's output answers its first call when the script is nothing but calls.
                    let id = call_id.as_ref().map(|id| if only && i == 0 { id.clone() } else { format!("{id}#{i}") });
                    out.push(TimelineEntry { tool: Some(tool.clone()), call_id: id, ..TimelineEntry::new(at.clone(), "tool_call", clip(&pretty(args))) });
                }
                // Calls taken out of a script that does more: they are done when the script is.
                if let (false, Some(id), false) = (only, &call_id, others.is_empty()) {
                    state.inner.insert(id.clone(), others.len());
                }
            }
            "function_call" | "custom_tool_call" => {
                if is_posting(&name) {
                    state.skip.extend(call_id);
                    continue;
                }
                let raw = p.get("arguments").or(p.get("input")).map(|v| v.as_str().map(String::from).unwrap_or_else(|| v.to_string())).unwrap_or_default();
                // Not JSON (custom tools take free text): shown as is.
                let args = serde_json::from_str::<Value>(&raw).map(|v| pretty(&v)).unwrap_or(raw);
                out.push(TimelineEntry { tool: Some(name), call_id, ..TimelineEntry::new(at, "tool_call", clip(&args)) });
            }
            "function_call_output" | "custom_tool_call_output" => {
                if call_id.as_ref().is_some_and(|id| state.skip.contains(id)) {
                    continue;
                }
                let text = to_text(p.get("output").unwrap_or(&Value::Null));
                let failed = text.find("Process exited with code ").is_some_and(|i| text[i + 25..].starts_with(|c: char| ('1'..='9').contains(&c)));
                out.push(TimelineEntry { ok: Some(!failed), call_id: call_id.clone(), ..TimelineEntry::new(at.clone(), "tool_result", clip(&text)) });
                let count = call_id.as_ref().and_then(|id| state.inner.get(id)).copied().unwrap_or(0);
                for i in 0..count {
                    out.push(TimelineEntry {
                        ok: Some(!failed),
                        call_id: Some(format!("{}#{i}", call_id.as_deref().unwrap_or(""))),
                        ..TimelineEntry::new(at.clone(), "tool_result", "（结果在脚本的输出里）".into())
                    });
                }
            }
            _ => {}
        }
    }
    out
}

/// The tool calls in a code-mode script, `tools.<name>({…})` with a literal argument (read as data, never run), and
/// whether the script is nothing else (each call alone, or wrapped in `text(await …)`).
pub fn script_calls(script: &str) -> (Vec<(String, Value)>, bool) {
    let chars: Vec<char> = script.chars().collect();
    let mut calls = Vec::new();
    let mut rest = script.to_string();
    let mut i = 0;
    while let Some(found) = find_from(&chars, i, "tools.") {
        let mut j = found + 6;
        let name_start = j;
        while j < chars.len() && (chars[j].is_alphanumeric() || chars[j] == '_' || chars[j] == '$') {
            j += 1;
        }
        let name: String = chars[name_start..j].iter().collect();
        let first_ok = chars.get(name_start).is_some_and(|c| c.is_alphabetic() || *c == '_' || *c == '$');
        while j < chars.len() && chars[j].is_whitespace() {
            j += 1;
        }
        i = found + 6;
        if !first_ok || chars.get(j) != Some(&'(') {
            continue;
        }
        let Some((value, end)) = read_literal(&chars, j + 1) else { continue };
        let mut k = end;
        while k < chars.len() && chars[k].is_whitespace() {
            k += 1;
        }
        if chars.get(k) != Some(&')') {
            continue;
        }
        calls.push((name, value));
        let whole: String = chars[found..=k].iter().collect();
        rest = rest.replacen(&whole, "", 1);
        i = k + 1;
    }
    // What is left once the calls are out: nothing but their wrapping.
    let stripped = strip_wrapping(&rest);
    let only = !calls.is_empty() && stripped.chars().all(|c| c.is_whitespace() || c == ';');
    (calls, only)
}

fn find_from(chars: &[char], from: usize, needle: &str) -> Option<usize> {
    let n: Vec<char> = needle.chars().collect();
    (from..chars.len().saturating_sub(n.len() - 1)).find(|&i| chars[i..].starts_with(&n))
}

/// Removes `text(await )`, `await` and `text()` (spaces inside allowed), as the TS regex does.
fn strip_wrapping(rest: &str) -> String {
    let mut s = rest.to_string();
    loop {
        let before = s.clone();
        // text( await )
        let mut out = String::new();
        let chars: Vec<char> = s.chars().collect();
        let mut i = 0;
        while i < chars.len() {
            let tail: String = chars[i..].iter().collect();
            if let Some(after) = tail.strip_prefix("text(") {
                let trimmed = after.trim_start();
                let skipped = after.len() - trimmed.len();
                if let Some(after_await) = trimmed.strip_prefix("await") {
                    let t2 = after_await.trim_start();
                    if t2.starts_with(')') {
                        i += 5 + skipped + 5 + (after_await.len() - t2.len()) + 1;
                        continue;
                    }
                } else if trimmed.starts_with(')') {
                    i += 5 + skipped + 1;
                    continue;
                }
            }
            if tail.starts_with("await") {
                i += 5;
                continue;
            }
            out.push(chars[i]);
            i += 1;
        }
        s = out;
        if s == before {
            return s;
        }
    }
}

/// A JavaScript literal (object, array, string, number, true/false/null) at `at`, as data; None when it is anything
/// else. Its end with it.
fn read_literal(src: &[char], at: usize) -> Option<(Value, usize)> {
    struct P<'a> {
        s: &'a [char],
        i: usize,
    }
    impl P<'_> {
        fn space(&mut self) {
            while self.i < self.s.len() && self.s[self.i].is_whitespace() {
                self.i += 1;
            }
        }
        fn value(&mut self) -> Option<Value> {
            self.space();
            match *self.s.get(self.i)? {
                '{' => {
                    self.i += 1;
                    let mut obj = Map::new();
                    loop {
                        self.space();
                        if self.s.get(self.i) == Some(&'}') {
                            self.i += 1;
                            return Some(Value::Object(obj));
                        }
                        let key = match self.s.get(self.i) {
                            Some('"' | '\'') => self.string()?,
                            _ => {
                                let start = self.i;
                                let first = *self.s.get(self.i)?;
                                if !(first.is_alphabetic() || first == '_' || first == '$') {
                                    return None;
                                }
                                while self.i < self.s.len() && (self.s[self.i].is_alphanumeric() || self.s[self.i] == '_' || self.s[self.i] == '$') {
                                    self.i += 1;
                                }
                                self.s[start..self.i].iter().collect()
                            }
                        };
                        self.space();
                        if self.s.get(self.i) != Some(&':') {
                            return None;
                        }
                        self.i += 1;
                        let v = self.value()?;
                        obj.insert(key, v);
                        self.space();
                        match self.s.get(self.i) {
                            Some(',') => self.i += 1,
                            Some('}') => {
                                self.i += 1;
                                return Some(Value::Object(obj));
                            }
                            _ => return None,
                        }
                    }
                }
                '[' => {
                    self.i += 1;
                    let mut list = Vec::new();
                    loop {
                        self.space();
                        if self.s.get(self.i) == Some(&']') {
                            self.i += 1;
                            return Some(Value::Array(list));
                        }
                        list.push(self.value()?);
                        self.space();
                        match self.s.get(self.i) {
                            Some(',') => self.i += 1,
                            Some(']') => {
                                self.i += 1;
                                return Some(Value::Array(list));
                            }
                            _ => return None,
                        }
                    }
                }
                '"' | '\'' | '`' => self.string().map(Value::String),
                _ => {
                    let rest: String = self.s[self.i..].iter().take(64).collect();
                    for word in ["true", "false", "null"] {
                        if rest.starts_with(word) {
                            self.i += word.len();
                            return serde_json::from_str(word).ok();
                        }
                    }
                    let len = number_len(&rest)?;
                    self.i += len;
                    serde_json::from_str(&rest[..len]).ok()
                }
            }
        }
        fn string(&mut self) -> Option<String> {
            let quote = self.s[self.i];
            self.i += 1;
            let mut out = String::new();
            while self.i < self.s.len() && self.s[self.i] != quote {
                if quote == '`' && self.s[self.i] == '$' && self.s.get(self.i + 1) == Some(&'{') {
                    return None;
                }
                if self.s[self.i] == '\\' {
                    let next = *self.s.get(self.i + 1)?;
                    if next == 'u' {
                        let hex: String = self.s.get(self.i + 2..self.i + 6)?.iter().collect();
                        out.push(char::from_u32(u32::from_str_radix(&hex, 16).ok()?)?);
                        self.i += 6;
                        continue;
                    }
                    out.push(match next {
                        'n' => '\n',
                        't' => '\t',
                        'r' => '\r',
                        'b' => '\u{8}',
                        'f' => '\u{c}',
                        'v' => '\u{b}',
                        '0' => '\0',
                        other => other,
                    });
                    self.i += 2;
                    continue;
                }
                out.push(self.s[self.i]);
                self.i += 1;
            }
            if self.s.get(self.i) != Some(&quote) {
                return None;
            }
            self.i += 1;
            Some(out)
        }
    }
    let mut p = P { s: src, i: at };
    let v = p.value()?;
    Some((v, p.i))
}

/// The length of a JSON-like number at the start of `s` (-?\d+(\.\d+)?([eE][+-]?\d+)?), if one is there.
fn number_len(s: &str) -> Option<usize> {
    let b = s.as_bytes();
    let mut i = 0;
    if b.first() == Some(&b'-') {
        i += 1;
    }
    let digits = |i: &mut usize| {
        let start = *i;
        while *i < b.len() && b[*i].is_ascii_digit() {
            *i += 1;
        }
        *i > start
    };
    if !digits(&mut i) {
        return None;
    }
    if b.get(i) == Some(&b'.') {
        let mut j = i + 1;
        if digits(&mut j) {
            i = j;
        }
    }
    if matches!(b.get(i), Some(b'e' | b'E')) {
        let mut j = i + 1;
        if matches!(b.get(j), Some(b'+' | b'-')) {
            j += 1;
        }
        if digits(&mut j) {
            i = j;
        }
    }
    Some(i)
}

/// Milliseconds of an ISO timestamp (as transcripts write them: 2026-09-27T00:00:02.500Z), if it is one.
pub fn parse_iso(at: &str) -> Option<i64> {
    let b = at.as_bytes();
    let num = |from: usize, len: usize| std::str::from_utf8(b.get(from..from + len)?).ok()?.parse::<i64>().ok();
    let (y, mo, d, h, mi, s) = (num(0, 4)?, num(5, 2)?, num(8, 2)?, num(11, 2)?, num(14, 2)?, num(17, 2)?);
    let mut ms = 0;
    if b.get(19) == Some(&b'.') {
        let frac: String = at[20..].chars().take_while(char::is_ascii_digit).collect();
        ms = format!("{:0<3}", &frac[..frac.len().min(3)]).parse().unwrap_or(0);
    }
    // Days from the civil date (Howard Hinnant's algorithm).
    let (yy, mm) = if mo <= 2 { (y - 1, mo + 9) } else { (y, mo - 3) };
    let era = yy.div_euclid(400);
    let yoe = yy - era * 400;
    let doy = (153 * mm + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    Some(((days * 86_400 + h * 3600 + mi * 60 + s) * 1000) + ms)
}

/// An ISO timestamp of milliseconds since the epoch, as JavaScript's toISOString writes it.
pub fn iso(ms: i64) -> String {
    let (days, rest) = (ms.div_euclid(86_400_000), ms.rem_euclid(86_400_000));
    // The civil date of a day count (Howard Hinnant's algorithm).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    let (h, mi, s, milli) = (rest / 3_600_000, rest / 60_000 % 60, rest / 1000 % 60, rest % 1000);
    format!("{y:04}-{m:02}-{d:02}T{h:02}:{mi:02}:{s:02}.{milli:03}Z")
}

/// Reads a transcript as it grows: each read returns the timeline entries of the lines written since the last one,
/// and the usage so far. Lines are independent, so parsing only the new ones gives what a full read would. Everything
/// read is kept, so watchers joining later are served from memory.
pub struct TranscriptTail {
    pub runtime: RuntimeKind,
    pub path: PathBuf,
    offset: u64,
    partial: Vec<u8>,
    /// Timeline entries read so far.
    pub entries: Vec<TimelineEntry>,
    pub usage: TranscriptUsage,
    seen: HashSet<String>,
    state: ReadState,
}

impl TranscriptTail {
    pub fn new(runtime: RuntimeKind, path: PathBuf) -> TranscriptTail {
        TranscriptTail { runtime, path, offset: 0, partial: vec![], entries: vec![], usage: TranscriptUsage::default(), seen: HashSet::new(), state: ReadState::default() }
    }

    /// New entries since the last read, with the index of the first.
    pub fn read(&mut self) -> (usize, Vec<TimelineEntry>) {
        let start = self.entries.len();
        let Ok(size) = std::fs::metadata(&self.path).map(|m| m.len()) else { return (start, vec![]) };
        if size < self.offset {
            // Rewritten: start over.
            self.offset = 0;
            self.partial.clear();
            self.entries.clear();
        }
        let start = self.entries.len();
        if size == self.offset {
            return (start, vec![]);
        }
        let mut buffer = vec![0u8; (size - self.offset) as usize];
        let read = std::fs::File::open(&self.path).and_then(|mut f| {
            f.seek(SeekFrom::Start(self.offset))?;
            f.read_exact(&mut buffer)
        });
        if read.is_err() {
            return (start, vec![]);
        }
        self.offset = size;
        let mut bytes = std::mem::take(&mut self.partial);
        bytes.extend(buffer);
        // A line still being written waits for the next read.
        let cut = bytes.iter().rposition(|b| *b == b'\n').map(|i| i + 1).unwrap_or(0);
        self.partial = bytes.split_off(cut);
        let text = String::from_utf8_lossy(&bytes);
        let records: Vec<Value> = text.lines().filter(|l| !l.is_empty()).filter_map(|l| serde_json::from_str(l).ok()).collect();
        self.add_usage(&records);
        let entries = if self.runtime == RuntimeKind::Claude { claude_timeline(&records, &mut self.state) } else { codex_timeline(&records, &mut self.state) };
        self.entries.extend(entries.clone());
        (start, entries)
    }

    /// Weaves entries from elsewhere (the station's record of its own tool calls) into what was read, by time. For a
    /// tail nobody has been told of yet: it reorders what is there.
    pub fn weave(&mut self, entries: Vec<TimelineEntry>) {
        if entries.is_empty() {
            return;
        }
        let time = |e: &TimelineEntry| e.at.as_deref().and_then(parse_iso);
        let mut merged = Vec::with_capacity(self.entries.len() + entries.len());
        let mut next = 0;
        for e in std::mem::take(&mut self.entries) {
            if let Some(t) = time(&e) {
                while next < entries.len() && time(&entries[next]).is_some_and(|x| x <= t) {
                    merged.push(entries[next].clone());
                    next += 1;
                }
            }
            merged.push(e);
        }
        merged.extend(entries[next..].iter().cloned());
        self.entries = merged;
    }

    /// Entries from elsewhere that happen now: after all that was read. Where they start.
    pub fn append(&mut self, entries: Vec<TimelineEntry>) -> usize {
        let start = self.entries.len();
        self.entries.extend(entries);
        start
    }

    fn add_usage(&mut self, records: &[Value]) {
        let n = |v: Option<&Value>| v.and_then(Value::as_u64).unwrap_or(0);
        for r in records {
            if self.runtime == RuntimeKind::Claude {
                let Some(m) = r.get("message").filter(|_| r.get("type").and_then(Value::as_str) == Some("assistant")) else { continue };
                let (Some(usage), Some(id)) = (m.get("usage"), m.get("id").and_then(Value::as_str)) else { continue };
                if !self.seen.insert(id.to_string()) {
                    continue;
                }
                let cached = n(usage.get("cache_read_input_tokens")) + n(usage.get("cache_creation_input_tokens"));
                self.usage.model_calls += 1;
                self.usage.input_tokens += n(usage.get("input_tokens")) + cached;
                self.usage.cached_tokens += n(usage.get("cache_read_input_tokens"));
                self.usage.output_tokens += n(usage.get("output_tokens"));
                if let Some(model) = m.get("model").and_then(Value::as_str).filter(|m| *m != "<synthetic>") {
                    self.usage.model = Some(model.to_string());
                }
            } else {
                let p = r.get("payload").cloned().unwrap_or(Value::Null);
                let kind = r.get("type").and_then(Value::as_str);
                if kind == Some("turn_context") {
                    if let Some(model) = p.get("model").and_then(Value::as_str) {
                        self.usage.model = Some(model.to_string());
                    }
                }
                let last = (kind == Some("event_msg") && p.get("type").and_then(Value::as_str) == Some("token_count"))
                    .then(|| p.get("info").and_then(|i| i.get("last_token_usage")))
                    .flatten()
                    .filter(|l| !l.is_null());
                let Some(last) = last else { continue };
                self.usage.model_calls += 1;
                self.usage.input_tokens += n(last.get("input_tokens"));
                self.usage.cached_tokens += n(last.get("cached_input_tokens"));
                self.usage.output_tokens += n(last.get("output_tokens"));
            }
        }
    }
}

#[cfg(test)]
mod tests;
