//! What an agent at work is doing, as a chat shows it: one line, the thing it does now, put together here so every
//! client draws the same thing. From a `live` topic's value (the steps in flight, the phase, the output rate) into
//! `activity`:
//!
//! `{ "now": { "key", "text" } }`: `text` "运行 cargo test" | "正在回复" | "思考中 · ≈ 42 token/s" | "请求中" | …; `key`
//! names the thing (a step's id, or where the turn stands), so a client can tell a new thing from the same one whose
//! words changed (the rate ticking).

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
pub(crate) fn field(input: &str, name: &str) -> Option<String> {
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

/// Milliseconds since the epoch of an RFC 3339 time (2026-09-27T00:00:02.500Z); None for anything else.
pub(crate) fn epoch_ms(at: &str) -> Option<f64> {
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

/// What the agent does now: the call it runs (the newest, if several), its reply as it writes it, its thinking, or
/// where the turn stands.
pub fn present(live: &Value) -> Value {
    let empty = Vec::new();
    let steps = live.get("steps").and_then(Value::as_array).unwrap_or(&empty);
    let str_of = |v: &Value, k: &str| v.get(k).and_then(Value::as_str).unwrap_or("").to_string();
    let flag = |v: &Value, k: &str| v.get(k).and_then(Value::as_bool).unwrap_or(false);
    let mut call = None;
    let mut replying = false;
    let mut thinking = false;
    for s in steps.iter().filter(|s| !flag(s, "ended") && !flag(s, "subagent")) {
        match str_of(s, "step").as_str() {
            "thinking" => thinking = true,
            "tool" => {
                let tool = str_of(s, "tool");
                match tool_name(&tool) {
                    "chat_post" => replying = true,
                    "chat_state" => {}
                    _ => call = Some((str_of(s, "id"), call_text(&tool, &str_of(s, "input")))),
                }
            }
            _ => {}
        }
    }
    let rate = live.get("rate").and_then(Value::as_u64).unwrap_or(0);
    let phase = live.get("phase").and_then(|p| p.get("phase")).and_then(Value::as_str).unwrap_or("");
    let (key, text) = if let Some((id, text)) = call {
        (id, text)
    } else if replying {
        ("reply".to_string(), "正在回复".to_string())
    } else {
        let (key, text) = match phase {
            _ if thinking => ("think", "思考中"),
            "starting" => ("starting", "正在启动"),
            "requesting" => ("requesting", "请求中"),
            "thinking" => ("think", "思考中"),
            "responding" => ("write", "输出中"),
            _ => ("busy", "处理中"),
        };
        (key.to_string(), if rate > 0 { format!("{text} · ≈ {rate} token/s") } else { text.to_string() })
    };
    json!({ "now": { "key": key, "text": text } })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn now(live: Value) -> (String, String) {
        let a = present(&live);
        (a["now"]["key"].as_str().unwrap().into(), a["now"]["text"].as_str().unwrap().into())
    }

    #[test]
    fn it_says_the_call_it_runs_or_its_reply_or_where_the_turn_stands() {
        // The newest call it runs, by its step: the same call keeps its key.
        let steps = json!([
            {"id": "s0", "step": "tool", "tool": "Read", "input": "{\"file_path\":\"/w/a.ts\"}", "ended": true},
            {"id": "s1", "step": "thinking"},
            {"id": "s2", "step": "tool", "tool": "Bash", "input": "{\"command\":\"cargo test --workspace\",\"descr"},
            {"id": "s3", "step": "tool", "tool": "Grep", "input": "{\"pattern\":\"TODO\"}", "subagent": true},
        ]);
        assert_eq!(now(json!({"steps": steps, "phase": {"phase": "working"}})), ("s2".into(), "运行 cargo test --workspace".into()));
        // Writing its reply (chat_post's input streaming in); chat_state says nothing of its own.
        assert_eq!(now(json!({"steps": [{"id": "p", "step": "tool", "tool": "mcp__ember__chat_post", "input": "{\"to"}]})), ("reply".into(), "正在回复".into()));
        assert_eq!(now(json!({"steps": [{"id": "t", "step": "thinking"}], "rate": 30})), ("think".into(), "思考中 · ≈ 30 token/s".into()));
        // Where the turn stands; the rate changes the words, not the thing.
        assert_eq!(now(json!({"phase": {"phase": "requesting"}})), ("requesting".into(), "请求中".into()));
        assert_eq!(now(json!({"phase": {"phase": "responding"}, "rate": 42})), ("write".into(), "输出中 · ≈ 42 token/s".into()));
        assert_eq!(now(json!({"phase": {"phase": "thinking"}})), ("think".into(), "思考中".into()));
        assert_eq!(now(json!({"phase": {"phase": "starting"}})), ("starting".into(), "正在启动".into()));
        assert_eq!(now(json!({})), ("busy".into(), "处理中".into()));
        // A call's own description says it best.
        assert_eq!(call_text("Bash", "{\"command\":\"npm i\",\"description\":\"安装依赖\"}"), "安装依赖");
        assert_eq!(epoch_ms("1970-01-02T00:00:01.500Z"), Some(86_401_500.0));
    }
}
