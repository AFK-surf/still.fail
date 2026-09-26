//! What an agent at work is doing, as a chat shows it (after Zork's activity,
//! and Cue's session activity): a status line and its latest rows, put
//! together here so every client draws the same thing. From a `live` topic's
//! value — its transcript, the steps in flight, the phase, the output rate —
//! into `activity`:
//!
//! `{ "status": "运行 cargo test" | "≈ 42 token/s" | "请求中" | …,
//!    "rows": [{ "key", "kind", "text", "live", "entry" }] }`
//!
//! The rows are this period's: since the agent last ended a turn (a post that
//! says final or block, or chat_state), so a message sent while it works does
//! not start them over. What it received (`in`), what it said (`say`) and
//! posted (`out`) stand alone; thinking and ordinary tool calls next to each
//! other share one row that sums them up (思考 12s · 读取 3 个文件 · 1 个失败),
//! so three lines say more than the last three calls. Then what runs now.
//! `entry` is the row's place in the transcript, for its history to open at.

use serde_json::{Value, json};

/// A tool's name without its MCP prefix.
pub fn tool_name(tool: &str) -> &str {
    ["mcp__ember__", "ember__", "ember."].iter().find_map(|p| tool.strip_prefix(p)).unwrap_or(tool)
}

/// What kind of thing a tool does, for its icon and its verb.
pub fn kind_of(tool: &str) -> &'static str {
    match tool_name(tool) {
        "Read" | "NotebookRead" | "view_image" => "read",
        "Glob" | "Grep" | "LS" | "ToolSearch" => "search",
        "Edit" | "MultiEdit" | "Write" | "NotebookEdit" | "apply_patch" => "edit",
        "Bash" | "BashOutput" | "KillShell" | "exec_command" | "shell" | "local_shell" | "write_stdin" | "unified_exec" => "command",
        "WebFetch" | "WebSearch" | "web_search" => "web",
        "Task" | "Agent" | "spawn_agent" => "agent",
        "chat_history" => "thread",
        _ => "other",
    }
}

fn verb(kind: &str) -> &'static str {
    match kind {
        "read" => "读取",
        "search" => "搜索",
        "edit" => "编辑",
        "command" => "运行",
        "web" => "访问",
        "agent" => "派出子 agent",
        "thread" => "查看对话",
        _ => "执行操作",
    }
}

/// A string field of a tool's input, read even when the input is cut short (a live step carries its first 300
/// characters).
fn field(input: &str, name: &str) -> Option<String> {
    if let Ok(Value::Object(args)) = serde_json::from_str::<Value>(input) {
        return match args.get(name)? {
            Value::String(s) => Some(s.clone()),
            Value::Array(parts) => Some(parts.iter().filter_map(Value::as_str).collect::<Vec<_>>().join(" ")),
            _ => None,
        };
    }
    let at = input.find(&format!("\"{name}\""))?;
    let rest = input[at + name.len() + 2..].trim_start().strip_prefix(':')?.trim_start().strip_prefix('"')?;
    let mut out = String::new();
    let mut chars = rest.chars();
    while let Some(c) = chars.next() {
        match c {
            '"' => break,
            '\\' => match chars.next() {
                Some('n') => out.push('\n'),
                Some('t') => out.push('\t'),
                Some(other) => out.push(other),
                None => break,
            },
            c => out.push(c),
        }
    }
    Some(out)
}

/// What a call does, in a few words: its own description, else its verb and what it acts on (the command, the file,
/// the pattern), on one line.
pub fn call_text(tool: &str, input: &str) -> String {
    if let Some(said) = field(input, "description").map(|d| d.trim().to_string()).filter(|d| !d.is_empty()) {
        return said;
    }
    let kind = kind_of(tool);
    let target = ["command", "cmd", "file_path", "path", "pattern", "url", "query", "prompt"]
        .iter()
        .find_map(|name| field(input, name))
        .map(|t| {
            let line = t.lines().next().unwrap_or("").trim().to_string();
            // A file by its name: the path's end is what says which.
            if kind == "read" || kind == "edit" { line.rsplit('/').next().unwrap_or(&line).to_string() } else { line }
        })
        .filter(|t| !t.is_empty());
    let what = match target {
        Some(t) => format!("{} {}", verb(kind), t.chars().take(80).collect::<String>()),
        None => verb(kind).to_string(),
    };
    if kind == "other" && tool_name(tool) != "" { format!("{} {}", verb(kind), tool_name(tool)) } else { what }
}

/// Ends a turn: a post that says final or block, or chat_state.
fn ends_turn(tool: &str, input: &str) -> bool {
    match tool_name(tool) {
        "chat_state" => true,
        "chat_post" => matches!(field(input, "kind").as_deref(), Some("final" | "block")),
        _ => false,
    }
}

/// Milliseconds since the epoch of an RFC 3339 time (2026-09-27T00:00:02.500Z); None for anything else.
fn epoch_ms(at: &str) -> Option<f64> {
    let b = at.as_bytes();
    if b.len() < 19 || b[4] != b'-' || b[10] != b'T' {
        return None;
    }
    let num = |r: std::ops::Range<usize>| at.get(r)?.parse::<i64>().ok();
    let (y, m, d) = (num(0..4)?, num(5..7)?, num(8..10)?);
    let (hh, mm, ss) = (num(11..13)?, num(14..16)?, num(17..19)?);
    let frac = at[19..].strip_prefix('.').map(|f| f.chars().take_while(char::is_ascii_digit).collect::<String>()).unwrap_or_default();
    let ms = if frac.is_empty() { 0.0 } else { format!("0.{frac}").parse::<f64>().unwrap_or(0.0) * 1000.0 };
    // Days from the civil date (Howard Hinnant's algorithm); times are UTC as the runtimes write them.
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    Some((((days * 24 + hh) * 60 + mm) * 60 + ss) as f64 * 1000.0 + ms)
}

fn seconds(ms: f64) -> String {
    let s = (ms / 1000.0).round().max(1.0) as u64;
    if s < 60 { format!("{s}s") } else { format!("{}m {}s", s / 60, s % 60) }
}

/// The first line of some text, cut to a line's worth.
fn first_line(text: &str) -> String {
    let line = text.lines().map(str::trim).find(|l| !l.is_empty()).unwrap_or("");
    let cut: String = line.chars().take(120).collect();
    if cut.chars().count() < line.chars().count() { format!("{cut}…") } else { cut }
}

/// A message the agent was given (`<message … from="Name (id)" …>text</message>`): who from, and what it says.
fn received(text: &str) -> Option<(String, String)> {
    let open = text.find("<message ")?;
    let head_end = open + text[open..].find('>')?;
    let head = &text[open..head_end];
    let from = head.find("from=\"").map(|at| {
        let rest = &head[at + 6..];
        let raw = &rest[..rest.find('"').unwrap_or(rest.len())];
        raw.split(" (").next().unwrap_or(raw).to_string()
    });
    let body_end = text[head_end..].find("</message>").map_or(text.len(), |e| head_end + e);
    Some((from.unwrap_or_else(|| "有人".into()), first_line(&text[head_end + 1..body_end])))
}

/// Thinking and ordinary calls next to each other: summed up in one row.
struct Member {
    kind: &'static str,
    text: String,
    entry: usize,
    call: Option<String>,
    failed: bool,
    thought_ms: Option<f64>,
}

fn group_row(members: &[Member]) -> Value {
    let first = &members[0];
    let key = format!("t{}", first.entry);
    if members.len() == 1 {
        let text = match (first.kind, first.thought_ms) {
            ("think", Some(ms)) => format!("思考 {}", seconds(ms)),
            ("think", None) => "思考".to_string(),
            _ if first.failed => format!("{} · 失败", first.text),
            _ => first.text.clone(),
        };
        return json!({ "key": key, "kind": first.kind, "text": text, "live": false, "entry": first.entry });
    }
    let mut parts = Vec::new();
    let thought: f64 = members.iter().filter_map(|m| m.thought_ms).sum();
    if members.iter().any(|m| m.kind == "think") {
        parts.push(if thought > 0.0 { format!("思考 {}", seconds(thought)) } else { "思考".to_string() });
    }
    let mut kinds: Vec<&str> = Vec::new();
    for m in members.iter().filter(|m| m.kind != "think") {
        if !kinds.contains(&m.kind) {
            kinds.push(m.kind);
        }
    }
    for kind in &kinds {
        let n = members.iter().filter(|m| m.kind == *kind).count();
        parts.push(match *kind {
            "read" => format!("读取 {n} 个文件"),
            "search" => format!("搜索 {n} 次"),
            "edit" => format!("编辑 {n} 个文件"),
            "command" => format!("运行 {n} 条命令"),
            "web" => format!("访问 {n} 个网页"),
            "agent" => format!("派出 {n} 个子 agent"),
            "thread" => format!("查看对话 {n} 次"),
            _ => format!("执行 {n} 个操作"),
        });
    }
    let failed = members.iter().filter(|m| m.failed).count();
    if failed > 0 {
        parts.push(format!("{failed} 个失败"));
    }
    // Its icon: what most of it does.
    let kind = kinds.iter().max_by_key(|k| members.iter().filter(|m| m.kind == **k).count()).copied().unwrap_or("think");
    json!({ "key": key, "kind": kind, "text": parts.join(" · "), "live": false, "entry": first.entry })
}

/// The rows kept at most: a preview shows three; the rest let it scroll.
const ROWS: usize = 50;

pub fn present(live: &Value) -> Value {
    let empty = Vec::new();
    let timeline = live.get("timeline").and_then(Value::as_array).unwrap_or(&empty);
    let steps = live.get("steps").and_then(Value::as_array).unwrap_or(&empty);
    let str_of = |v: &Value, k: &str| v.get(k).and_then(Value::as_str).unwrap_or("").to_string();
    let flag = |v: &Value, k: &str| v.get(k).and_then(Value::as_bool).unwrap_or(false);
    // This period: after the agent last ended a turn.
    let start = timeline
        .iter()
        .rposition(|e| str_of(e, "kind") == "tool_call" && !flag(e, "subagent") && ends_turn(&str_of(e, "tool"), &str_of(e, "text")))
        .map_or(0, |i| i + 1);
    let mut rows: Vec<Value> = Vec::new();
    let mut group: Vec<Member> = Vec::new();
    let flush = |group: &mut Vec<Member>, rows: &mut Vec<Value>| {
        if !group.is_empty() {
            rows.push(group_row(group));
            group.clear();
        }
    };
    for (i, e) in timeline.iter().enumerate().skip(start) {
        if flag(e, "subagent") {
            continue;
        }
        let text = str_of(e, "text");
        match str_of(e, "kind").as_str() {
            "user" => {
                if let Some((from, said)) = received(&text) {
                    flush(&mut group, &mut rows);
                    rows.push(json!({ "key": format!("t{i}"), "kind": "in", "text": format!("收到 {from}：{said}"), "live": false, "entry": i }));
                }
            }
            "assistant" => {
                let said = first_line(&text);
                if !said.is_empty() {
                    flush(&mut group, &mut rows);
                    rows.push(json!({ "key": format!("t{i}"), "kind": "say", "text": said, "live": false, "entry": i }));
                }
            }
            "tool_call" => {
                let tool = str_of(e, "tool");
                match tool_name(&tool) {
                    "chat_post" => {
                        flush(&mut group, &mut rows);
                        let said = field(&text, "text").map(|t| first_line(&t)).unwrap_or_default();
                        rows.push(json!({ "key": format!("t{i}"), "kind": "out", "text": format!("回复：{said}"), "live": false, "entry": i }));
                    }
                    "chat_state" => {}
                    _ => group.push(Member { kind: kind_of(&tool), text: call_text(&tool, &text), entry: i, call: e.get("callId").and_then(Value::as_str).map(str::to_string), failed: false, thought_ms: None }),
                }
            }
            "tool_result" => {
                if e.get("ok") == Some(&Value::Bool(false)) {
                    let call = e.get("callId").and_then(Value::as_str);
                    if let Some(m) = group.iter_mut().rev().find(|m| m.call.is_some() && m.call.as_deref() == call) {
                        m.failed = true;
                    }
                }
            }
            "thinking" => {
                // How long it thought: until the next entry.
                let from = epoch_ms(&str_of(e, "at"));
                let to = timeline.get(i + 1).and_then(|n| epoch_ms(&str_of(n, "at")));
                let thought_ms = from.zip(to).map(|(a, b)| b - a).filter(|ms| *ms > 0.0);
                group.push(Member { kind: "think", text: "思考".into(), entry: i, call: None, failed: false, thought_ms });
            }
            _ => {}
        }
    }
    flush(&mut group, &mut rows);
    let mut action = None;
    for s in steps {
        if flag(s, "ended") || flag(s, "subagent") || str_of(s, "step") == "text" {
            continue;
        }
        let tool = str_of(s, "tool");
        if str_of(s, "step") == "tool" && matches!(tool_name(&tool), "chat_post" | "chat_state") {
            continue;
        }
        let (kind, text) = if str_of(s, "step") == "thinking" { ("think", "思考中".to_string()) } else { (kind_of(&tool), call_text(&tool, &str_of(s, "input"))) };
        if kind != "think" {
            action = Some(text.clone());
        }
        rows.push(json!({ "key": str_of(s, "id"), "kind": kind, "text": text, "live": true, "entry": Value::Null }));
    }
    if rows.len() > ROWS {
        rows.drain(..rows.len() - ROWS);
    }
    let rate = live.get("rate").and_then(Value::as_u64).unwrap_or(0);
    let phase = live.get("phase").and_then(|p| p.get("phase")).and_then(Value::as_str).unwrap_or("");
    let status = if let Some(action) = action {
        action
    } else if rate > 0 {
        format!("≈ {rate} token/s")
    } else {
        match phase {
            "starting" => "正在启动",
            "requesting" => "请求中",
            "thinking" | "responding" => "思考中",
            _ => "处理中",
        }
        .to_string()
    };
    json!({ "status": status, "rows": rows })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_period_is_what_came_in_and_went_out_and_the_work_between_summed_up() {
        let live = json!({
            "timeline": [
                {"kind": "user", "text": "<message via=\"slack\" from=\"Ada (U1)\" ts=\"1\">\nearlier\n</message>"},
                {"kind": "tool_call", "tool": "Bash", "text": "{\"command\":\"ls\"}"},
                {"kind": "tool_call", "tool": "mcp__ember__chat_post", "text": "{\"to\":\"C1/1\",\"text\":\"done\",\"kind\":\"final\"}"},
                {"kind": "user", "text": "<message via=\"slack\" from=\"Ada (U1)\" ts=\"2\">\nfix the build\nplease\n</message>"},
                {"kind": "thinking", "text": "hmm", "at": "2026-09-27T00:00:00.000Z"},
                {"kind": "tool_call", "tool": "Read", "text": "{\"file_path\":\"/w/src/main.ts\"}", "callId": "a", "at": "2026-09-27T00:00:12.000Z"},
                {"kind": "tool_call", "tool": "Read", "text": "{\"file_path\":\"/w/src/a.ts\"}", "callId": "b"},
                {"kind": "tool_result", "callId": "b", "ok": false},
                {"kind": "tool_call", "tool": "Bash", "text": "{\"command\":\"cargo build\"}", "callId": "c"},
                {"kind": "user", "text": "<message via=\"slack\" from=\"Bo (U2)\" ts=\"3\">\nalso tests\n</message>"},
                {"kind": "tool_call", "tool": "mcp__ember__chat_post", "text": "{\"to\":\"C1/2\",\"text\":\"on it\"}"},
                {"kind": "tool_call", "tool": "Grep", "text": "{\"pattern\":\"TODO\"}", "subagent": true},
            ],
            "steps": [{"id": "s1", "step": "tool", "tool": "Bash", "input": "{\"command\":\"cargo test --workspace\",\"descr"}],
            "phase": {"phase": "working", "since": 1},
        });
        let a = present(&live);
        let rows: Vec<(String, String, bool)> = a["rows"].as_array().unwrap().iter().map(|r| (r["kind"].as_str().unwrap().into(), r["text"].as_str().unwrap().into(), r["live"].as_bool().unwrap())).collect();
        assert_eq!(rows, vec![
            // After the turn that ended final: a message sent meanwhile does not start it over.
            ("in".into(), "收到 Ada：fix the build".into(), false),
            ("read".into(), "思考 12s · 读取 2 个文件 · 运行 1 条命令 · 1 个失败".into(), false),
            ("in".into(), "收到 Bo：also tests".into(), false),
            ("out".into(), "回复：on it".into(), false),
            ("command".into(), "运行 cargo test --workspace".into(), true),
        ]);
        assert_eq!(a["rows"][1]["entry"], 4, "a row opens its history at its first entry");
        assert_eq!(a["status"], "运行 cargo test --workspace", "the action it runs");
        assert_eq!(epoch_ms("1970-01-02T00:00:01.500Z"), Some(86_401_500.0));
    }

    #[test]
    fn the_status_says_where_the_turn_stands() {
        let status = |live: Value| present(&live)["status"].as_str().unwrap().to_string();
        assert_eq!(status(json!({"phase": {"phase": "requesting"}})), "请求中");
        assert_eq!(status(json!({"phase": {"phase": "responding"}, "rate": 42})), "≈ 42 token/s");
        assert_eq!(status(json!({"phase": {"phase": "responding"}})), "思考中");
        assert_eq!(status(json!({"phase": {"phase": "starting"}})), "正在启动");
        assert_eq!(status(json!({})), "处理中");
        // A call's own description says it best.
        assert_eq!(call_text("Bash", "{\"command\":\"npm i\",\"description\":\"安装依赖\"}"), "安装依赖");
    }
}
