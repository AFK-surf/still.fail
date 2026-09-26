//! What an agent at work is doing, as a chat shows it (after Zork's activity):
//! a status line and its latest rows, put together here so every client draws
//! the same thing. From a `live` topic's value — its transcript, the steps in
//! flight, the phase, the output rate — into `activity`:
//!
//! `{ "status": "运行 cargo test" | "≈ 42 token/s" | "请求中" | …,
//!    "rows": [{ "key", "kind", "text", "live", "entry" }] }`
//!
//! The rows are this turn's (since the last message the agent was given): its
//! tool calls and thinking as the transcript records them, then what runs now.
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

/// The calls that are how the agent talks, not work to show.
fn talking(tool: &str) -> bool {
    matches!(tool_name(tool), "chat_post" | "chat_state")
}

pub fn present(live: &Value) -> Value {
    let empty = Vec::new();
    let timeline = live.get("timeline").and_then(Value::as_array).unwrap_or(&empty);
    let steps = live.get("steps").and_then(Value::as_array).unwrap_or(&empty);
    let str_of = |v: &Value, k: &str| v.get(k).and_then(Value::as_str).unwrap_or("").to_string();
    let flag = |v: &Value, k: &str| v.get(k).and_then(Value::as_bool).unwrap_or(false);
    // This turn: after the last message the agent was given.
    let start = timeline.iter().rposition(|e| str_of(e, "kind") == "user" && !flag(e, "subagent")).map_or(0, |i| i + 1);
    let mut rows = Vec::new();
    for (i, e) in timeline.iter().enumerate().skip(start) {
        if flag(e, "subagent") {
            continue;
        }
        match str_of(e, "kind").as_str() {
            "tool_call" if !talking(&str_of(e, "tool")) => {
                let tool = str_of(e, "tool");
                rows.push(json!({ "key": format!("t{i}"), "kind": kind_of(&tool), "text": call_text(&tool, &str_of(e, "text")), "live": false, "entry": i }));
            }
            "thinking" => rows.push(json!({ "key": format!("t{i}"), "kind": "think", "text": "思考", "live": false, "entry": i })),
            _ => {}
        }
    }
    let mut action = None;
    for s in steps {
        if flag(s, "ended") || flag(s, "subagent") || str_of(s, "step") == "text" {
            continue;
        }
        let tool = str_of(s, "tool");
        if str_of(s, "step") == "tool" && talking(&tool) {
            continue;
        }
        let (kind, text) = if str_of(s, "step") == "thinking" { ("think", "思考中".to_string()) } else { (kind_of(&tool), call_text(&tool, &str_of(s, "input"))) };
        if kind != "think" {
            action = Some(text.clone());
        }
        rows.push(json!({ "key": str_of(s, "id"), "kind": kind, "text": text, "live": true, "entry": Value::Null }));
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
    fn a_turn_is_its_calls_and_what_runs_now() {
        let live = json!({
            "timeline": [
                {"kind": "user", "text": "earlier"},
                {"kind": "tool_call", "tool": "Bash", "text": "{\"command\":\"ls\"}"},
                {"kind": "user", "text": "fix the build"},
                {"kind": "thinking", "text": "hmm"},
                {"kind": "tool_call", "tool": "Read", "text": "{\"file_path\":\"/w/src/main.ts\"}"},
                {"kind": "tool_call", "tool": "mcp__ember__chat_post", "text": "{}"},
                {"kind": "tool_call", "tool": "Grep", "text": "{\"pattern\":\"TODO\"}", "subagent": true},
            ],
            "steps": [{"id": "s1", "step": "tool", "tool": "Bash", "input": "{\"command\":\"cargo test --workspace\",\"descr"}],
            "phase": {"phase": "working", "since": 1},
        });
        let a = present(&live);
        let rows: Vec<(String, String, bool)> = a["rows"].as_array().unwrap().iter().map(|r| (r["kind"].as_str().unwrap().into(), r["text"].as_str().unwrap().into(), r["live"].as_bool().unwrap())).collect();
        assert_eq!(rows, vec![
            ("think".into(), "思考".into(), false),
            ("read".into(), "读取 main.ts".into(), false),
            ("command".into(), "运行 cargo test --workspace".into(), true),
        ]);
        assert_eq!(a["rows"][1]["entry"], 4, "a row opens its history at its entry");
        assert_eq!(a["status"], "运行 cargo test --workspace", "the action it runs");
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
