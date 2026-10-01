//! An agent's execution history as the clients show it (after Zork's): a readable account of what actually ran, put
//! together here so every client draws the same thing. Messages in and out, state marks and the agent's own words are
//! boundaries; the tool calls and thinking between two boundaries fold into one group, named by its latest call.
//!
//! The view is `HistoryView` in client/shapes: its items (each `{ key, entries, body }`, `entries` the transcript
//! entries it draws, first and last, for an activity row to open the history there; `body` what kind of item it is and
//! what that kind says), what streams now, where the turn stands, the model's use, and what shows at its top. A place
//! is `format::place`'s. Only the transcript's latest entries are there at first (`more`: `history.older` loads the
//! ones before); items count entries from the transcript's start all the same.

use serde_json::{Value, json};

use crate::activity::{epoch_ms, kind_of, tool_name};
use crate::format;

/// What a history is read with besides its transcript.
pub struct Context<'a> {
    /// The session's threads: where its messages came from and went.
    pub threads: &'a [Value],
    /// The workspace's people (`{ email, name }`): someone on ember's page by their name.
    pub members: &'a [Value],
    /// The Slack users the viewer said are them.
    pub slack_users: &'a [String],
    /// Its connect's bot, as a mention of it reads.
    pub bot_user_id: Option<&'a str>,
    pub bot_name: &'a str,
    pub runtime: &'a str,
    /// The runtime has begun the session (it has a transcript somewhere).
    pub started: bool,
    pub offset_min: i32,
    /// The Slack workspaces the station's connects are in, by team id: where a Slack thread is, and the way to it.
    pub workspaces: &'a std::collections::HashMap<String, format::SlackWorkspace>,
}

fn verb_unit(kind: &str) -> (&'static str, &'static str) {
    match kind {
        "read" => ("读取", "个文件"),
        "search" => ("搜索", "次"),
        "edit" => ("编辑", "个文件"),
        "command" => ("运行", "条命令"),
        "web" => ("访问", "个网页"),
        "agent" => ("派出", "个子 agent"),
        "thread" => ("读取 thread", "次"),
        _ => ("其他", "项"),
    }
}

fn args(text: &str) -> Option<serde_json::Map<String, Value>> {
    let parsed = serde_json::from_str(text).ok().or_else(|| {
        // A long call is kept to its first characters, then `… (n more characters)`: read what is there.
        let (head, tail) = text.rsplit_once("\n… (")?;
        tail.ends_with(" more characters)").then(|| serde_json::from_str(&close(head)).ok()).flatten()
    });
    match parsed {
        Some(Value::Object(map)) => Some(map),
        _ => None,
    }
}

/// JSON cut short, closed where it stops: the string it was in ends with an ellipsis, and what was open is closed.
fn close(json: &str) -> String {
    let (mut open, mut quoted, mut escaped) = (Vec::new(), false, false);
    for c in json.chars() {
        if escaped {
            escaped = false;
        } else if quoted {
            match c {
                '\\' => escaped = true,
                '"' => quoted = false,
                _ => {}
            }
        } else {
            match c {
                '"' => quoted = true,
                '{' => open.push('}'),
                '[' => open.push(']'),
                '}' | ']' => {
                    open.pop();
                }
                _ => {}
            }
        }
    }
    let mut out = json.to_string();
    if quoted {
        if escaped {
            out.pop();
        }
        out.push_str("…\"");
    }
    let mut out = out.trim_end().to_string();
    if out.ends_with(':') {
        out.push_str("null");
    } else if out.ends_with(',') {
        out.pop();
    }
    out.extend(open.iter().rev());
    out
}

fn line(text: &str, max: usize) -> String {
    text.split('\n').next().unwrap_or("").chars().take(max).collect()
}

/// One line that says what a call did: the command, the file, the pattern.
fn hint(text: &str) -> String {
    let Some(a) = args(text) else { return line(text, 160) };
    let value = ["command", "cmd", "file_path", "path", "pattern", "url", "query", "description", "prompt"]
        .iter()
        .find_map(|k| a.get(*k).filter(|v| !v.is_null()));
    let text = match value {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Array(parts)) => parts.iter().map(|p| p.as_str().unwrap_or("")).collect::<Vec<_>>().join(" "),
        _ => String::new(),
    };
    line(&text, 160)
}

/// What the agent said a call is for, when the tool takes a description (Bash, Task, …).
fn describe(text: &str) -> Option<String> {
    let d = args(text)?.get("description")?.as_str()?.trim().to_string();
    (!d.is_empty()).then(|| line(&d, 160))
}

fn file_of(text: &str) -> Option<String> {
    let a = args(text)?;
    ["file_path", "path", "notebook_path"].iter().find_map(|k| a.get(*k)).and_then(Value::as_str).map(str::to_string)
}

/// A message a prompt carried.
#[derive(Debug, PartialEq)]
pub struct Sourced {
    pub user: String,
    pub name: Option<String>,
    pub ts: String,
    pub text: String,
    pub thread: Option<String>,
    pub slack: bool,
}

fn attr(attrs: &str, name: &str) -> Option<String> {
    let key = format!("{name}=\"");
    let mut from = 0;
    // Whole attributes only ("ts" is not the end of "thread_ts").
    while let Some(at) = attrs[from..].find(&key).map(|a| a + from) {
        if at == 0 || attrs.as_bytes()[at - 1] == b' ' {
            let rest = &attrs[at + key.len()..];
            return Some(rest[..rest.find('"')?].to_string());
        }
        from = at + key.len();
    }
    None
}

/// Where an opening tag that starts at `open` ends: its `>`, not one inside a quoted attribute (`you="ember (<@U1>)"`).
fn tag_end(text: &str, open: usize) -> Option<usize> {
    let mut quoted = false;
    for (i, c) in text[open..].char_indices() {
        match c {
            '"' => quoted = !quoted,
            '>' if !quoted => return Some(open + i),
            _ => {}
        }
    }
    None
}

fn unescape(v: &str) -> String {
    v.replace("&quot;", "\"").replace("&amp;", "&")
}

/// A tag's body: after its opening (and a line break), up to its close (and the line break before it).
fn body<'a>(text: &'a str, open_end: usize, close: &str) -> Option<(&'a str, usize)> {
    let start = if text[open_end..].starts_with('\n') { open_end + 1 } else { open_end };
    let end = start + text[start..].find(close)?;
    let inner = &text[start..end];
    Some((inner.strip_suffix('\n').unwrap_or(inner), end + close.len()))
}

/// Splits a prompt ember built into the chat messages it carried and ember's own words around them (the current
/// `<message …>` form and the older `<slack …>` one).
pub fn parse_prompt(text: &str) -> (Vec<Sourced>, String) {
    let mut messages = Vec::new();
    let mut rest = String::new();
    let mut at = 0;
    while let Some(open) = text[at..].find("<message ").map(|o| o + at) {
        let Some(head_end) = tag_end(text, open) else { break };
        let Some((inner, next)) = body(text, head_end + 1, "</message>") else { break };
        let attrs = &text[open + 9..head_end];
        let from = unescape(&attr(attrs, "from").unwrap_or_default());
        // "Name (id)": a name, and who.
        let named = from.strip_suffix(')').and_then(|f| f.rsplit_once(" (")).filter(|(_, id)| !id.is_empty() && !id.contains(['(', ')', ' ']));
        messages.push(Sourced {
            user: named.map_or_else(|| from.clone(), |(_, id)| id.to_string()),
            name: named.map(|(name, _)| name.to_string()),
            ts: attr(attrs, "ts").unwrap_or_default(),
            text: inner.to_string(),
            thread: attr(attrs, "thread"),
            slack: attr(attrs, "via").as_deref() == Some("slack"),
        });
        rest.push_str(&text[at..open]);
        at = next;
    }
    rest.push_str(&text[at..]);
    let text = rest;
    let mut rest = String::new();
    let mut at = 0;
    while let Some(open) = text[at..].find("<slack user=\"").map(|o| o + at) {
        let Some(head_end) = tag_end(&text, open) else { break };
        let Some((inner, next)) = body(&text, head_end + 1, "</slack>") else { break };
        let attrs = &text[open + 7..head_end];
        messages.push(Sourced { user: attr(attrs, "user").unwrap_or_default(), name: None, ts: attr(attrs, "ts").unwrap_or_default(), text: inner.to_string(), thread: None, slack: true });
        rest.push_str(&text[at..open]);
        at = next;
    }
    rest.push_str(&text[at..]);
    let note = rest
        .split('\n')
        .filter(|l| !(l.starts_with("(Thread ") && l.ends_with(')') && l.contains(" had messages before you were brought in;")))
        .collect::<Vec<_>>()
        .join("\n");
    (messages, note.trim().to_string())
}

use crate::present::member_name;

fn mentions(text: &str, cx: &Context) -> String {
    let bots: Vec<(String, String)> = cx.bot_user_id.map(|id| (id.to_string(), cx.bot_name.to_string())).into_iter().collect();
    crate::present::mentions(text, &bots, cx.members)
}

struct Step {
    call: usize,
    result: Option<usize>,
}

enum Item {
    Received(usize),
    Text(usize),
    Post(usize),
    /// A state marked, and for waiting at most how many seconds.
    Mark(String, Option<u64>),
    Group(Vec<usize>, Vec<usize>),
}

pub fn present(live: &Value, cx: &Context) -> Value {
    let empty = Vec::new();
    let timeline = live.get("timeline").and_then(Value::as_array).unwrap_or(&empty);
    // Where the timeline starts in the transcript: what is before it is not loaded (yet).
    let base = live.get("first").and_then(Value::as_u64).unwrap_or(0) as usize;
    let s = |e: &Value, k: &str| e.get(k).and_then(Value::as_str).unwrap_or("").to_string();
    let flag = |e: &Value, k: &str| e.get(k).and_then(Value::as_bool).unwrap_or(false);

    // Items, and the entries each draws.
    let mut items: Vec<(Item, usize, usize)> = Vec::new();
    let mut steps: Vec<Step> = Vec::new();
    let mut by_call: std::collections::HashMap<String, usize> = Default::default();
    let mut last_step: Option<usize> = None;
    let mut grouping = false;
    let cover = |items: &mut Vec<(Item, usize, usize)>, i: usize| {
        if let Some(last) = items.last_mut() {
            last.2 = i;
        }
    };
    for (i, e) in timeline.iter().enumerate() {
        match s(e, "kind").as_str() {
            "tool_result" => {
                let step = e.get("callId").and_then(Value::as_str).and_then(|c| by_call.get(c).copied())
                    .or(last_step.filter(|l| steps[*l].result.is_none()));
                if let Some(step) = step {
                    steps[step].result = Some(i);
                }
                cover(&mut items, i);
            }
            "tool_call" => {
                let step = steps.len();
                steps.push(Step { call: i, result: None });
                if let Some(call) = e.get("callId").and_then(Value::as_str) {
                    by_call.insert(call.to_string(), step);
                }
                last_step = Some(step);
                let tool = s(e, "tool");
                let a = args(&s(e, "text"));
                let arg = |k: &str| a.as_ref().and_then(|a| a.get(k)).and_then(Value::as_str).map(str::to_string);
                let sub = flag(e, "subagent");
                match tool_name(&tool) {
                    "chat_post" if arg("text").is_some() && !sub => {
                        items.push((Item::Post(step), i, i));
                        grouping = false;
                    }
                    "chat_state" if arg("kind").is_some() && !sub => {
                        let seconds = a.as_ref().and_then(|a| a.get("seconds")).and_then(Value::as_f64).map(|s| s.max(0.0) as u64);
                        items.push((Item::Mark(arg("kind").unwrap_or_default(), seconds), i, i));
                        grouping = false;
                    }
                    _ => {
                        if !grouping {
                            items.push((Item::Group(Vec::new(), Vec::new()), i, i));
                            grouping = true;
                        }
                        if let Some((Item::Group(g, _), _, last)) = items.last_mut() {
                            g.push(step);
                            *last = i;
                        }
                    }
                }
            }
            "thinking" => {
                if !grouping {
                    items.push((Item::Group(Vec::new(), Vec::new()), i, i));
                    grouping = true;
                }
                if let Some((Item::Group(_, t), _, last)) = items.last_mut() {
                    t.push(i);
                    *last = i;
                }
            }
            kind => {
                grouping = false;
                items.push((if kind == "user" { Item::Received(i) } else { Item::Text(i) }, i, i));
            }
        }
    }

    let failed_of = |step: &Step| step.result.is_some_and(|r| timeline[r].get("ok") == Some(&Value::Bool(false)));
    let place = |address: Option<&str>| address.map_or(Value::Null, |a| format::place(cx.threads, a, cx.offset_min, cx.workspaces));
    let shown: Vec<Value> = items.iter().map(|(item, first, last)| {
        let mut v: Value = match item {
            Item::Received(i) => {
                let (messages, note) = parse_prompt(&s(&timeline[*i], "text"));
                let messages: Vec<Value> = messages.iter().map(|m| {
                    let from = if m.slack {
                        let bound = cx.slack_users.iter().any(|u| *u == m.user);
                        let name = if bound { "你".to_string() } else { m.name.clone().filter(|n| !n.is_empty()).unwrap_or_else(|| m.user.clone()) };
                        json!({ "name": name, "slackUser": m.user, "bound": bound })
                    } else {
                        let name = member_name(cx.members, &m.user).map(str::to_string)
                            .or_else(|| m.name.clone().filter(|n| !n.is_empty())).unwrap_or_else(|| m.user.clone());
                        json!({ "name": name, "slackUser": null, "bound": false })
                    };
                    json!({ "key": m.ts, "from": from, "text": mentions(&m.text, cx), "place": place(m.thread.as_deref()) })
                }).collect();
                json!({ "kind": "received", "note": (!note.is_empty()).then_some(note), "messages": messages })
            }
            Item::Text(i) => json!({ "kind": "text", "text": s(&timeline[*i], "text"), "subagent": flag(&timeline[*i], "subagent") }),
            Item::Post(step) => {
                let a = args(&s(&timeline[steps[*step].call], "text")).unwrap_or_default();
                let text = |k: &str| a.get(k).and_then(Value::as_str);
                json!({
                    "kind": "post",
                    "text": text("text").unwrap_or(""),
                    "place": place(text("to")),
                    "block": matches!(text("kind"), Some("block" | "need_help" | "need_decision")),
                    "failed": failed_of(&steps[*step]),
                })
            }
            // Waiting is drawn as a line with an hourglass, not as a rule across, saying how long it waited: from its
            // mark until the next word came in (what brought it back), at most its limit; still waiting, the clients
            // count on from `since`.
            Item::Mark(kind, seconds) if kind == "waiting" => {
                let at = |i: usize| timeline[i].get("at").and_then(Value::as_str).and_then(epoch_ms).map(|ms| ms as i64);
                let since = at(*first);
                let until = since.and_then(|_| (*first + 1..timeline.len()).find(|&j| s(&timeline[j], "kind") == "user" && !flag(&timeline[j], "subagent")).and_then(at));
                let waited = since.zip(until).map(|(a, b)| {
                    let w = ((b - a).max(0) / 1000) as u64;
                    seconds.map_or(w, |s| w.min(s))
                });
                let most = seconds.map(|s| format!(" / {}", span(s))).unwrap_or_default();
                let text = match waited {
                    Some(w) => format!("等待了 {}{most}", span(w)),
                    None => format!("等待中{}", seconds.map(|s| format!("，最长 {}", span(s))).unwrap_or_default()),
                };
                let wait = since.map(|since| json!({ "since": since, "until": until, "seconds": seconds }));
                json!({ "kind": "mark", "text": text, "wait": wait })
            }
            Item::Mark(kind, _) => json!({ "kind": "mark", "text": match kind.as_str() {
                "final" | "all_done" => "标记为做完了".to_string(),
                "block" | "need_help" => "停下来等人帮忙".to_string(),
                "need_decision" => "停下来等人决定".to_string(),
                other => format!("标记为 {other}"),
            } }),
            Item::Group(members, thinking) => group(timeline, &steps, members, thinking),
        };
        // Its kind, and what that kind says (shapes: HistoryBody).
        let kind = v.as_object_mut().and_then(|o| o.remove("kind")).unwrap_or(Value::Null);
        json!({ "key": format!("e{}", base + first), "entries": [base + first, base + last], "body": { "kind": kind, "content": v } })
    }).collect();

    // Only thinking and the reply stream here; a tool call shows once it is done, from the transcript.
    let live_steps: Vec<Value> = live.get("steps").and_then(Value::as_array).unwrap_or(&empty).iter()
        .filter(|st| !flag(st, "subagent") && s(st, "step") != "tool")
        .map(|st| json!({ "id": s(st, "id"), "text": if s(st, "step") == "text" { "正在输出…" } else { "正在思考…" } }))
        .collect();
    let phase = live.get("phase").filter(|p| p.is_object()).map(|p| {
        let text = match p.get("phase").and_then(Value::as_str).unwrap_or("") {
            "starting" => format!("正在启动 {}", format::runtime_label(cx.runtime)),
            "requesting" => "已发送请求，等待模型响应".into(),
            "working" => "执行工具中".into(),
            _ => "Thinking".into(),
        };
        json!({ "phase": p.get("phase"), "text": text, "since": p.get("since") })
    });
    let usage = live.get("usage").filter(|u| u.is_object()).map(|u| {
        let n = |k: &str| u.get(k).and_then(Value::as_f64).unwrap_or(0.0);
        let (input, cached) = (n("inputTokens"), n("cachedTokens"));
        let rate = if input > 0.0 { format!("{}%", (cached / input * 100.0).round()) } else { "未报告".into() };
        json!([
            { "label": "模型调用", "value": format!("{} 次", n("modelCalls")) },
            { "label": "输入", "value": format::compact_number(input) },
            { "label": "其中缓存", "value": format::compact_number(cached) },
            { "label": "输出", "value": format::compact_number(n("outputTokens")) },
            { "label": "缓存命中率", "value": rate },
        ])
    });
    // The same, in a line: 调用 3 次 · 输入 2K（缓存 50%）· 输出 50.
    let usage_line = live.get("usage").filter(|u| u.is_object()).map(|u| {
        let n = |k: &str| u.get(k).and_then(Value::as_f64).unwrap_or(0.0);
        let (input, cached) = (n("inputTokens"), n("cachedTokens"));
        let rate = if input > 0.0 { format!("（缓存 {}%）", (cached / input * 100.0).round()) } else { String::new() };
        format!("调用 {} 次 · 输入 {}{rate} · 输出 {}", n("modelCalls"), format::compact_number(input), format::compact_number(n("outputTokens")))
    });
    let loaded = flag(live, "loaded");
    let (edge, is_empty) = if !loaded && shown.is_empty() {
        ("正在读取执行历史…", true)
    } else if shown.is_empty() && live_steps.is_empty() && phase.is_none() && base == 0 {
        let why = if flag(live, "offline") { "station 离线，这台设备上还没有这个会话的执行历史。" } else if cx.started { "找不到运行时记录，可能已归档。" } else { "运行时还没开始这个会话。" };
        (why, true)
    } else if base > 0 {
        ("正在读取更早的执行历史…", false)
    } else {
        ("已到 Session 开始处", false)
    };
    json!({ "items": shown, "live": live_steps, "phase": phase, "usage": usage, "usageLine": usage_line, "edge": edge, "empty": is_empty, "loaded": loaded, "more": base > 0 })
}

fn group(timeline: &[Value], steps: &[Step], members: &[usize], thinking: &[usize]) -> Value {
    let text = |i: usize| timeline[i].get("text").and_then(Value::as_str).unwrap_or("").to_string();
    let tool = |i: usize| timeline[i].get("tool").and_then(Value::as_str).unwrap_or("").to_string();
    let failed_of = |st: &Step| st.result.is_some_and(|r| timeline[r].get("ok") == Some(&Value::Bool(false)));
    // What it did, by kind: files read or edited count once each.
    let mut counts: Vec<(&str, Vec<String>, usize)> = Vec::new();
    for &m in members {
        let call = steps[m].call;
        let kind = kind_of(&tool(call));
        let file = if matches!(kind, "read" | "edit") { file_of(&text(call)) } else { None };
        let at = match counts.iter().position(|(k, _, _)| *k == kind) {
            Some(at) => at,
            None => {
                counts.push((kind, Vec::new(), 0));
                counts.len() - 1
            }
        };
        match file {
            Some(f) if !counts[at].1.contains(&f) => counts[at].1.push(f),
            Some(_) => {}
            None => counts[at].2 += 1,
        }
    }
    let title = counts.iter().map(|(k, files, n)| {
        let (verb, unit) = verb_unit(k);
        format!("{verb} {} {unit}", if files.is_empty() { *n } else { files.len() })
    }).collect::<Vec<_>>().join("、");
    let failed = members.iter().filter(|m| failed_of(&steps[**m])).count();
    let pending = members.iter().filter(|m| steps[**m].result.is_none()).count();
    let first_line = |t: &str| t.split('\n').find(|l| !l.trim().is_empty()).unwrap_or("").to_string();
    // Named by its latest call: its description, else what it did and to what.
    let summary = match members.last() {
        None => format!("思考：{}", thinking.first().map(|t| first_line(&text(*t)).chars().take(80).collect::<String>()).unwrap_or_default()),
        Some(&last) => {
            let call = steps[last].call;
            let name = tool(call);
            let kind = kind_of(&name);
            let doing = describe(&text(call)).unwrap_or_else(|| {
                let verb = if kind == "other" { tool_name(&name).to_string() } else { verb_unit(kind).0.to_string() };
                format!("{verb} {}", hint(&text(call))).trim().to_string()
            });
            if members.len() == 1 { doing } else { format!("{doing} · 共 {} 项", members.len()) }
        }
    };
    let steps: Vec<Value> = members.iter().map(|&m| {
        let st = &steps[m];
        let call = &timeline[st.call];
        let result = st.result.map(|r| &timeline[r]);
        let failed = failed_of(st);
        let took = result
            .and_then(|r| epoch_ms(r.get("at")?.as_str()?))
            .zip(call.get("at").and_then(Value::as_str).and_then(epoch_ms))
            .map(|(b, a)| b - a)
            .filter(|ms| *ms >= 0.0);
        let meta = if result.is_none() { "进行中".to_string() } else if failed { "失败".to_string() } else { took.map(format::duration).unwrap_or_default() };
        json!({
            "said": describe(&text(st.call)),
            "name": tool_name(&tool(st.call)),
            "hint": hint(&text(st.call)),
            "meta": meta,
            "failed": failed,
            "call": text(st.call),
            "result": result.map(|r| r.get("text").cloned().unwrap_or(json!(""))),
        })
    }).collect();
    let thinking: Vec<Value> = thinking.iter().map(|&t| json!({ "text": text(t), "first": first_line(&text(t)) })).collect();
    json!({ "kind": "group", "summary": summary, "title": title, "failures": failed, "pending": pending, "thinking": thinking, "steps": steps })
}

/// Seconds in short, as the chat's activity says them: 45s, 3m 20s, 10m, 1h 5m.
fn span(s: u64) -> String {
    match s {
        0..60 => format!("{s}s"),
        60..3600 if s % 60 == 0 => format!("{}m", s / 60),
        60..3600 => format!("{}m {}s", s / 60, s % 60),
        _ if s % 3600 / 60 == 0 => format!("{}h", s / 3600),
        _ => format!("{}h {}m", s / 3600, s % 3600 / 60),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_a_call_cut_short() {
        let cut = "{\n  \"file_path\": \"/a/b.ts\",\n  \"content\": \"line one\\nline t\n… (1200 more characters)";
        assert_eq!(hint(cut), "/a/b.ts");
        assert_eq!(args(cut).unwrap()["content"], "line one\nline t…");
        assert_eq!(args("{\"a\": [1, 2,\n… (9 more characters)").unwrap()["a"], json!([1, 2]));
    }

    fn cx<'a>(threads: &'a [Value], members: &'a [Value], slack: &'a [String]) -> Context<'a> {
        let workspaces = Box::leak(Box::new(std::collections::HashMap::from([(
            "T1".to_string(),
            format::SlackWorkspace { name: "Acme".into(), url: Some("https://acme.slack.com/".into()) },
        )])));
        Context { threads, members, slack_users: slack, bot_user_id: Some("UBOT"), bot_name: "ds-ember", runtime: "codex", started: true, offset_min: 480, workspaces }
    }

    #[test]
    fn a_slack_place_is_named_with_its_workspace_and_links_to_its_thread() {
        let threads = vec![json!({ "surface": "slack:T1", "channel": "C1", "threadTs": "1.000200", "channelName": "ops", "sessions": [{ "session": "s1" }] })];
        let (members, slack) = (vec![], vec![]);
        let cx = cx(&threads, &members, &slack);
        let place = format::place(cx.threads, "C1/1.000200", cx.offset_min, cx.workspaces);
        assert_eq!((place["name"].as_str(), place["url"].as_str()), (Some("Acme#ops"), Some("https://acme.slack.com/archives/C1/p1000200")));
        let unknown = format::place(cx.threads, "C9/2.0", cx.offset_min, cx.workspaces);
        assert_eq!((unknown["name"].as_str(), unknown["url"].as_str()), (Some("#C9"), None), "a thread it has not seen: no workspace, no link");
    }

    #[test]
    fn a_prompt_is_the_messages_it_carried_and_embers_words_around_them() {
        // What the agent is called there, a mention inside a quoted attribute, does not end the tag.
        let (said, _) = parse_prompt("<message via=\"slack\" connect=\"cl\" you=\"ember (<@UBOT>)\" thread=\"C1/1.0\" from=\"Ada (U1)\" ts=\"1.2\">\nhi\n</message>");
        assert_eq!((said.len(), said[0].user.as_str(), said[0].ts.as_str(), said[0].text.as_str()), (1, "U1", "1.2", "hi"));
        let (messages, note) = parse_prompt("Heads up.\n<message via=\"slack\" from=\"Ada &amp; Co (U1)\" ts=\"1.2\" thread=\"C1/1.0\">\nhi <@UBOT>\n</message>\n(Thread C1/1.0 had messages before you were brought in; read them.)");
        assert_eq!(note, "Heads up.");
        assert_eq!(messages, vec![Sourced { user: "U1".into(), name: Some("Ada & Co".into()), ts: "1.2".into(), text: "hi <@UBOT>".into(), thread: Some("C1/1.0".into()), slack: true }]);
        let (old, _) = parse_prompt("<slack user=\"U2\" bot ts=\"3.4\">\nyo\n</slack>");
        assert_eq!(old[0].user, "U2");
        assert_eq!(old[0].text, "yo");
    }

    #[test]
    fn boundaries_stand_alone_and_the_work_between_folds_into_a_group() {
        let threads = [json!({"channel": "C1", "threadTs": "1.0", "channelName": "ops", "sessions": [{"session": "s1"}]})];
        let members = [json!({"email": "a@x.com", "name": "阿一"})];
        let slack = ["U1".to_string()];
        let live = json!({
            "loaded": true,
            "timeline": [
                {"kind": "user", "text": "<message via=\"slack\" from=\"Ada (U1)\" ts=\"1.2\" thread=\"C1/1.0\">\nhi <@UBOT>\n</message>"},
                {"kind": "thinking", "text": "\nplan it\nmore"},
                {"kind": "tool_call", "tool": "Read", "text": "{\"file_path\":\"/a.ts\"}", "callId": "a", "at": "2026-09-27T00:00:00.000Z"},
                {"kind": "tool_result", "callId": "a", "ok": true, "text": "x", "at": "2026-09-27T00:00:02.000Z"},
                {"kind": "tool_call", "tool": "Read", "text": "{\"file_path\":\"/a.ts\"}", "callId": "b"},
                {"kind": "tool_call", "tool": "Bash", "text": "{\"command\":\"ls\",\"description\":\"看看目录\"}", "callId": "c"},
                {"kind": "tool_result", "callId": "c", "ok": false, "text": "no"},
                {"kind": "tool_call", "tool": "mcp__ember__chat_post", "text": "{\"to\":\"C1/1.0\",\"text\":\"done\",\"kind\":\"block\"}", "callId": "d"},
                {"kind": "tool_call", "tool": "mcp__ember__chat_state", "text": "{\"kind\":\"final\"}"},
                {"kind": "assistant", "text": "ok"},
            ],
            "steps": [{"id": "s", "step": "thinking"}, {"id": "t", "step": "tool", "tool": "Bash"}],
            "phase": {"phase": "starting", "since": 5},
            "usage": {"modelCalls": 3, "inputTokens": 2000, "cachedTokens": 1000, "outputTokens": 50},
        });
        let h = present(&live, &cx(&threads, &members, &slack));
        let items = h["items"].as_array().unwrap();
        let kinds: Vec<&str> = items.iter().map(|i| i["body"]["kind"].as_str().unwrap()).collect();
        assert_eq!(kinds, ["received", "group", "post", "mark", "text"]);
        let m = &items[0]["body"]["content"]["messages"][0];
        assert_eq!((m["from"]["name"].as_str(), m["text"].as_str(), m["place"]["name"].as_str(), m["place"]["session"].as_str()), (Some("你"), Some("hi @ds-ember"), Some("#ops"), Some("s1")));
        let g = &items[1]["body"]["content"];
        assert_eq!(g["summary"], "看看目录 · 共 3 项");
        assert_eq!(g["title"], "读取 1 个文件、运行 1 条命令");
        assert_eq!((g["failures"].as_u64(), g["pending"].as_u64()), (Some(1), Some(1)));
        assert_eq!(g["steps"][0]["meta"], "2 秒");
        assert_eq!(g["steps"][1]["meta"], "进行中");
        assert_eq!(g["thinking"][0]["first"], "plan it");
        assert_eq!(items[1]["entries"], json!([1, 6]));
        assert_eq!((items[2]["body"]["content"]["block"].as_bool(), items[2]["body"]["content"]["place"]["name"].as_str()), (Some(true), Some("#ops")));
        assert_eq!(items[3]["body"]["content"]["text"], "标记为做完了");
        let waits = |args: &str| {
            let live = json!({"loaded": true, "timeline": [{"kind": "tool_call", "tool": "mcp__ember__chat_state", "text": args}]});
            present(&live, &cx(&threads, &members, &slack))["items"][0]["body"]["content"].clone()
        };
        let waits = |args: &str, next: Option<&str>| {
            let mut timeline = vec![json!({"kind": "tool_call", "tool": "mcp__ember__chat_state", "text": args, "at": "2026-09-27T00:00:00.000Z"})];
            if let Some(at) = next {
                timeline.push(json!({"kind": "user", "text": "<message via=\"ember\">done</message>", "at": at}));
            }
            let live = json!({"loaded": true, "timeline": timeline});
            present(&live, &cx(&threads, &members, &slack))["items"][0]["body"]["content"].clone()
        };
        // Brought back after 80 seconds: how long it waited, and its limit.
        let back = waits("{\"kind\":\"waiting\",\"seconds\":150}", Some("2026-09-27T00:01:20.000Z"));
        assert_eq!(back["text"], "等待了 1m 20s / 2m 30s");
        assert_eq!(back["wait"], json!({"since": 1790467200000_i64, "until": 1790467280000_i64, "seconds": 150}));
        // Asked again late (a restart, say): never past its limit.
        assert_eq!(waits("{\"kind\":\"waiting\",\"seconds\":60}", Some("2026-09-27T01:00:00.000Z"))["text"], "等待了 1m / 1m");
        // Still waiting: the clients count on from since.
        let now = waits("{\"kind\":\"waiting\",\"seconds\":600}", None);
        assert_eq!((now["text"].as_str(), now["wait"]["until"].is_null()), (Some("等待中，最长 10m"), true));
        assert_eq!(h["live"], json!([{"id": "s", "text": "正在思考…"}]));
        assert_eq!(h["phase"]["text"], "正在启动 Codex");
        assert_eq!(h["usage"][4]["value"], "50%");
        assert_eq!(h["usageLine"], "调用 3 次 · 输入 2K（缓存 50%） · 输出 50");
        assert_eq!(h["edge"], "已到 Session 开始处");
    }

    #[test]
    fn an_empty_history_says_why() {
        let none: [Value; 0] = [];
        let edge = |live: Value, started: bool| {
            let mut c = cx(&none, &none, &[]);
            c.started = started;
            present(&live, &c)["edge"].as_str().unwrap().to_string()
        };
        assert_eq!(edge(json!({"loaded": false}), true), "正在读取执行历史…");
        assert_eq!(edge(json!({"loaded": true}), false), "运行时还没开始这个会话。");
        assert_eq!(edge(json!({"loaded": true, "offline": true}), true), "station 离线，这台设备上还没有这个会话的执行历史。");
    }

    #[test]
    fn a_timeline_loaded_from_further_on_counts_entries_from_the_transcripts_start() {
        let none: [Value; 0] = [];
        let live = json!({"loaded": true, "first": 400, "timeline": [
            {"kind": "user", "text": "hi"},
            {"kind": "tool_call", "tool": "Bash", "text": "{\"command\":\"ls\"}", "callId": "a"},
            {"kind": "tool_result", "callId": "a", "ok": true, "text": "x"},
        ]});
        let h = present(&live, &cx(&none, &none, &[]));
        assert_eq!((h["items"][0]["key"].clone(), h["items"][1]["entries"].clone()), (json!("e400"), json!([401, 402])));
        assert_eq!((h["more"].clone(), h["edge"].clone(), h["empty"].clone()), (json!(true), json!("正在读取更早的执行历史…"), json!(false)));
        assert_eq!(present(&json!({"loaded": true, "first": 400, "timeline": []}), &cx(&none, &none, &[]))["more"], true);
    }
}
