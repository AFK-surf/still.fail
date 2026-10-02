//! What the clients show of sessions and sidebar rows, decided here once:
//! where a session stands, a row's state, and who said a row's last thing
//! (with that agent's state on its picture). Clients draw these; they do not
//! work them out.

use serde_json::{Value, json};

use crate::format;
use crate::protocol::Topic;

/// How a session's last turn ended, in today's words (all_done, need_help, waiting): the station's `ending`, else its
/// `declared` as a station from before them says it (final all_done, block need_help). need_decision (a station from
/// before cards: a post with options that ended the turn) is need_help: the card is the message's.
pub fn ending(s: &Value) -> Option<&str> {
    let turn = s.get("lastTurn").filter(|t| t.is_object())?;
    let said = match turn.get("ending").and_then(Value::as_str) {
        Some(ending) => ending,
        None => turn.get("declared").and_then(Value::as_str)?,
    };
    Some(match said {
        "final" => "all_done",
        "block" | "need_decision" => "need_help",
        other => other,
    })
}

/// Where a session stands: running (also while it waits on work it started, which brings it back), queued, final
/// (all done), block (it needs a person: need_help), failed, aborted, unexpected (a turn that ended without a state, or
/// was left open by a crash), or idle.
pub fn session_status(s: &Value) -> &'static str {
    if s.get("process").and_then(Value::as_str) == Some("running") {
        return "running";
    }
    if s.get("pending").and_then(Value::as_u64).unwrap_or(0) > 0 {
        return "queued";
    }
    let Some(turn) = s.get("lastTurn").filter(|t| t.is_object()) else { return "idle" };
    match ending(s) {
        Some("all_done") => return "final",
        Some("need_help") => return "block",
        Some("waiting") => return "running",
        _ => {}
    }
    match turn.get("outcome").and_then(Value::as_str) {
        Some("failed") => "failed",
        Some("aborted") => "aborted",
        // Still open with no process: a crash left it so.
        _ => "unexpected",
    }
}

/// While a session waits on work it started (its last turn ended as waiting, nothing runs or is queued): since that
/// turn ended, and at most how many seconds until it is asked again; null otherwise.
pub fn waiting(s: &Value) -> Value {
    let turn = s.get("lastTurn").filter(|t| t.is_object());
    let since = turn.filter(|_| ending(s) == Some("waiting")).and_then(|t| t.get("endedAt")).and_then(Value::as_i64);
    match since {
        Some(since) if session_status(s) == "running" && s.get("process").and_then(Value::as_str) != Some("running") => {
            let what = turn.and_then(|t| t.get("waitFor")).and_then(Value::as_str).map(str::trim).filter(|w| !w.is_empty());
            json!({
                "since": since, "seconds": turn.and_then(|t| t.get("waitSeconds")).cloned().unwrap_or(Value::Null),
                "text": what.map(|w| format!("在等：{w}")).unwrap_or_else(|| "等待中".to_string()),
            })
        }
        _ => Value::Null,
    }
}

/// A chat's watch (`RowWatch`), when one of its agents keeps watch (their sessions' `watch`): what it watches, and what
/// archiving it by hand says first (it runs on in the archive, and anything new brings the chat back).
pub fn row_watch(agents: &[Value]) -> Option<Value> {
    let names: Vec<&str> = agents.iter()
        .filter_map(|a| a.get("watch").filter(|w| w.is_object()))
        .flat_map(|w| w.get("names").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str))
        .collect();
    if names.is_empty() {
        return None;
    }
    let named = names.iter().map(|n| format!("「{n}」")).collect::<Vec<_>>().join("、");
    Some(json!({
        "text": format!("监控中：{}", names.join("、")),
        "ask": format!("{named}还在监控。归档后它照常运行，有新消息时对话会回到列表。"),
    }))
}

/// Whether it waits on a watch of its own: then it is not at work for as long as it watches (no ring, no activity;
/// its row has the watch's own mark), and no wait runs out.
pub fn watching(s: &Value) -> bool {
    s.get("watch").is_some_and(Value::is_object) && !waiting(s).is_null()
}

/// Where a session stands as the clients show it: as `session_status`, but idle while it watches.
pub fn shown_status(s: &Value) -> &'static str {
    if watching(s) { "idle" } else { session_status(s) }
}

/// A session's small mark (`badge` of its shown status): none while it watches.
pub fn mark_of(s: &Value) -> Option<&'static str> {
    badge(shown_status(s))
}

/// A status as a client's small mark: run (at work), block (it needs a person: help or a decision), failed; none for
/// the rest.
pub fn badge(status: &str) -> Option<&'static str> {
    match status {
        "running" | "queued" => Some("run"),
        "block" | "decision" => Some("block"),
        "failed" | "unexpected" => Some("failed"),
        _ => None,
    }
}

/// A row's state, from its agents': one that is blocked comes first, then one at work, then one that failed.
pub fn row_state(agents: &[Value]) -> Option<&'static str> {
    let marks: Vec<&str> = agents.iter().filter_map(mark_of).collect();
    ["block", "run", "failed"].into_iter().find(|b| marks.contains(b))
}

/// A chat with nothing left in it (`settled`, `archivable`): each of its agents ended its last turn all_done (or final,
/// from a station before), none at work, no decision waiting for the viewer, nothing unread. Drawn faded and below the
/// rest of its day; one tap archives it.
pub fn settled(row: &Value) -> bool {
    let agents = row.get("agents").and_then(Value::as_array).cloned().unwrap_or_default();
    !agents.is_empty()
        && agents.iter().all(|a| shown_status(a) == "final")
        && !crate::decisions::waits(row)
        && row.get("unread").and_then(Value::as_bool) != Some(true)
}

/// A chat the viewer pinned: one they keep for the long run, never drawn as finished (faded, one tap from the archive)
/// however its agents ended (`pinned`: when, from the station; true once the core has said so).
pub fn pinned(row: &Value) -> bool {
    row.get("pinned").is_some_and(|p| p.is_number() || p == true)
}

/// The message an agent's state is about (its last turn's `about`), when it is in this chat: its seq.
pub fn state_about(agent: &Value, thread: Option<u64>) -> Option<u64> {
    let about = agent.get("lastTurn")?.get("about").filter(|a| a.is_object())?;
    (about.get("thread").and_then(Value::as_u64) == thread || thread.is_none()).then(|| about.get("seq").and_then(Value::as_u64)).flatten()
}

/// Where a chat stands, in words, for its second line (`stateText`), and the message that is about (`stateAbout`, a
/// seq), from its agents' states first: what one needs (要你帮忙：…), what went wrong (出问题：…); then a card waiting
/// for the viewer (奏 · …: whatever its agents do, at work included, but for a need, which says more); then what one
/// waits for (在等：…), 做完了 when all are done. None while one is at work with no card waiting, or with nothing to say.
pub fn row_state_line(row: &Value) -> Option<(String, Option<u64>)> {
    let thread = row.get("thread").and_then(Value::as_u64);
    // Its line: as the row shows it already (decisions::present), else from its post.
    let card = crate::decisions::pending(row).map(|c| {
        let line = c.get("text").and_then(Value::as_str).map(str::to_string)
            .unwrap_or_else(|| crate::decisions::line(c.get("message").and_then(|m| m.get("text")).and_then(Value::as_str).unwrap_or("")));
        (line, c.get("seq").and_then(Value::as_u64))
    });
    let agents = row.get("agents").and_then(Value::as_array).cloned().unwrap_or_default();
    let text_of = |a: &Value| a.get("statusText").and_then(Value::as_str).map(str::to_string);
    let status = |a: &Value| shown_status(a);
    let at_work = agents.iter().any(|a| matches!(status(a), "queued") || (status(a) == "running" && waiting(a).is_null()));
    if !at_work {
        // A need: in its words, about its message (the card it asks with, by default). Said without words (from
        // before them), a card waiting says more.
        if let Some(a) = agents.iter().find(|a| status(a) == "block") {
            let need = a.get("lastTurn").and_then(|t| t.get("need")).and_then(Value::as_str).is_some_and(|n| !n.trim().is_empty());
            match (&card, need) {
                (Some(card), false) => return Some(card.clone()),
                _ => return text_of(a).map(|t| (t, state_about(a, thread).or(card.as_ref().and_then(|c| c.1)))),
            }
        }
        if let Some(a) = agents.iter().find(|a| matches!(status(a), "failed" | "unexpected" | "aborted")) {
            return text_of(a).map(|t| (t, state_about(a, thread)));
        }
    }
    if let Some(card) = card {
        return Some(card);
    }
    if at_work {
        return None;
    }
    if let Some(a) = agents.iter().find(|a| !waiting(a).is_null()) {
        return text_of(a).map(|t| (t, state_about(a, thread)));
    }
    // What one of them says the chat ends with (做完了：已合并所有代码), else 做完了.
    settled(row).then(|| {
        let done = agents.iter().find(|a| a.get("statusText").and_then(Value::as_str).is_some_and(|t| t.starts_with("做完了：")));
        let text = done.and_then(text_of).unwrap_or_else(|| "做完了".to_string());
        let about = done.and_then(|a| state_about(a, thread)).or_else(|| agents.iter().find_map(|a| state_about(a, thread)));
        (text, about)
    })
}

/// What a chat's agents are doing, for the 奏 page's 正在办 (while no card waits there): 在做 · what was said last,
/// while one is at work; what one waits for (在等：…), while one does. None otherwise.
pub fn working_line(row: &Value) -> Option<String> {
    let agents = row.get("agents").and_then(Value::as_array).cloned().unwrap_or_default();
    let at_work = agents.iter().any(|a| matches!(shown_status(a), "queued") || (shown_status(a) == "running" && waiting(a).is_null()));
    if at_work {
        let text = row.get("last").and_then(|l| l.get("text")).and_then(Value::as_str).unwrap_or("");
        let last = crate::format::clean_text(text.lines().map(str::trim).find(|l| !l.is_empty()).unwrap_or(""));
        return Some(if last.is_empty() { "在做".to_string() } else { format!("在做 · {last}") });
    }
    agents.iter().map(waiting).find(|w| !w.is_null()).and_then(|w| w.get("text").and_then(Value::as_str).map(str::to_string))
}

/// Where a chat stands, in words (`row_state_line`'s words).
pub fn row_state_text(row: &Value) -> Option<String> {
    row_state_line(row).map(|(text, _)| text)
}

/// Whether a person (an email, "local", a Slack user id) is the viewer: by id, by email, or as a Slack user the
/// viewer said is them.
pub fn is_viewer(me: &Value, person: &str, slack_users: &[String]) -> bool {
    let id = me.get("id").and_then(Value::as_str);
    let email = me.get("email").and_then(Value::as_str);
    id == Some(person) || email.is_some_and(|e| e.eq_ignore_ascii_case(person)) || slack_users.iter().any(|u| u == person)
}

/// A workspace mstill.fail's name, by email.
pub fn member_name<'a>(members: &'a [Value], email: &str) -> Option<&'a str> {
    members.iter()
        .find(|m| m.get("email").and_then(Value::as_str).is_some_and(|e| e.eq_ignore_ascii_case(email)))
        .and_then(|m| m.get("name")).and_then(Value::as_str).filter(|n| !n.is_empty())
}

/// Slack's `<@U…>` mentions by name: a bot by its connect's (`bots`: bot user id, name), a person as the workspace
/// knows them, else the id.
pub fn mentions(text: &str, bots: &[(String, String)], members: &[Value]) -> String {
    let mut out = String::new();
    let mut rest = text;
    while let Some(at) = rest.find("<@") {
        out.push_str(&rest[..at]);
        let tail = &rest[at + 2..];
        let len = tail.find(|c: char| !(c.is_ascii_uppercase() || c.is_ascii_digit())).unwrap_or(tail.len());
        if len > 0 && tail[len..].starts_with('>') {
            let id = &tail[..len];
            let name = bots.iter().find(|(b, _)| b == id).map(|(_, n)| n.as_str()).or_else(|| member_name(members, id)).unwrap_or(id);
            out.push('@');
            out.push_str(name);
            rest = &tail[len + 1..];
        } else {
            out.push_str("<@");
            rest = tail;
        }
    }
    out.push_str(rest);
    out
}

/// A connect's bot, while it is signed in to Slack: its user id and the connect's name (what a mention of it reads).
pub fn bot_of(connect: &Value) -> Option<(String, String)> {
    let c = connect.get("connection")?;
    let on = matches!(c.get("state").and_then(Value::as_str), Some("connected" | "reconnecting"));
    let id = c.get("botUserId").and_then(Value::as_str).filter(|_| on)?;
    Some((id.to_string(), connect.get("name").and_then(Value::as_str).unwrap_or("").to_string()))
}

/// A person (`{ id, email, name }`: someone who made or takes part in a chat, or owns a connect) as the clients show
/// them: `shown: { name, display, picture, mine }`, `name` as the workspace knows them (本机管理页 for one on a
/// station's own page, in chats from before it went), `display` the same but 你 for the viewer.
pub fn person(p: &mut Value, me: &Value, members: &[Value]) {
    if !p.is_object() {
        return;
    }
    let str_of = |k: &str| p.get(k).and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string);
    let (id, email) = (str_of("id").unwrap_or_default(), str_of("email"));
    let key = email.clone().unwrap_or_else(|| id.clone());
    let member = members.iter().find(|m| m.get("email").and_then(Value::as_str).is_some_and(|e| e.eq_ignore_ascii_case(&key)));
    let member_name = member.and_then(|m| m.get("name")).and_then(Value::as_str).filter(|n| !n.is_empty()).map(str::to_string);
    let name = if id == "local" { "本机管理页".to_string() } else { member_name.or_else(|| str_of("name")).or(email.clone()).unwrap_or(id.clone()) };
    let mine = is_viewer(me, &id, &[]) || email.as_deref().is_some_and(|e| is_viewer(me, e, &[]));
    let picture = member.and_then(|m| m.get("picture")).and_then(Value::as_str).filter(|p| !p.is_empty());
    p["shown"] = json!({ "name": name, "display": if mine { "你".to_string() } else { name.clone() }, "picture": picture, "mine": mine });
}

/// A row's people as the clients show them (`person`): who started it first, then everyone who wrote in it, each once;
/// `creator` shown the same. A Slack user the viewer said is them is the viewer too.
pub fn row_people(row: &mut Value, me: &Value, slack_users: &[String], members: &[Value]) {
    // A station that does not say who: the row as it was.
    if row.get("people").is_none() && row.get("creator").is_none() {
        return;
    }
    let shown = |p: &Value| {
        let mut p = p.clone();
        person(&mut p, me, members);
        if p.get("id").and_then(Value::as_str).is_some_and(|id| is_viewer(me, id, slack_users)) {
            p["shown"]["mine"] = json!(true);
            p["shown"]["display"] = json!("你");
        }
        p
    };
    let creator = row.get("creator").filter(|c| c.is_object()).map(shown);
    let same = |a: &Value, b: &Value| {
        let key = |p: &Value| p.get("email").and_then(Value::as_str).or_else(|| p.get("id").and_then(Value::as_str)).unwrap_or("").to_ascii_lowercase();
        key(a) == key(b)
    };
    let mut people: Vec<Value> = creator.iter().cloned().collect();
    for p in row.get("people").and_then(Value::as_array).into_iter().flatten() {
        if !people.iter().any(|q| same(q, p)) {
            people.push(shown(p));
        }
    }
    let display = |p: &Value| p["shown"]["display"].as_str().unwrap_or("").to_string();
    let starter = creator.as_ref().and_then(|c| people.iter().position(|p| p.get("id").is_some() && p.get("id") == c.get("id")));
    let rest: Vec<String> = people.iter().enumerate().filter(|(i, _)| Some(*i) != starter).map(|(_, p)| display(p)).collect();
    let text: Vec<String> = starter.map(|i| format!("{} 发起", display(&people[i]))).into_iter().chain((!rest.is_empty()).then(|| rest.join("、"))).collect();
    row["peopleText"] = json!(text.join(" · "));
    if let Some(creator) = creator {
        row["creator"] = creator;
    }
    row["people"] = json!(people);
}

/// Who said a row's last thing, as its line shows them: `{ kind, name, model?, runtime?, picture?, mine, state? }`,
/// the agent's state riding on its picture when it is an agent of the row.
pub fn last_by(row: &Value, me: &Value, slack_users: &[String], members: &[Value]) -> Option<Value> {
    let last = row.get("last").filter(|l| l.is_object())?;
    let kind = last.get("authorKind").and_then(Value::as_str).unwrap_or("person");
    let author = last.get("author").and_then(Value::as_str).unwrap_or("");
    let said_name = last.get("authorName").and_then(Value::as_str).filter(|n| !n.is_empty());
    Some(match kind {
        "agent" => {
            let agent = row.get("agents").and_then(Value::as_array).and_then(|a| a.iter().find(|a| a.get("key").and_then(Value::as_str) == Some(author)));
            let model = agent.and_then(|a| a.get("model")).and_then(Value::as_str);
            json!({
                "kind": "agent",
                "name": model.map(stillfail_shapes::model::name).or(said_name.map(str::to_string)).unwrap_or_else(|| "agent".into()),
                "model": model,
                "runtime": agent.and_then(|a| a.get("runtime")).cloned().unwrap_or(json!("claude")),
                "mine": false,
                "state": agent.and_then(mark_of),
            })
        }
        "ember" => json!({ "kind": "ember", "name": crate::brand::name(), "mine": false }),
        _ => {
            let mine = is_viewer(me, author, slack_users);
            let member = members.iter().find(|m| m.get("email").and_then(Value::as_str).is_some_and(|e| e.eq_ignore_ascii_case(author)));
            let name = if mine { "你".to_string() } else {
                member.and_then(|m| m.get("name")).and_then(Value::as_str).filter(|n| !n.is_empty()).or(said_name).unwrap_or(author).to_string()
            };
            json!({
                "kind": "person",
                "id": author,
                "name": name,
                "picture": member.and_then(|m| m.get("picture")).filter(|p| p.as_str().is_some_and(|p| !p.is_empty())),
                "mine": mine,
            })
        }
    })
}

/// The viewer's clock: now, and their UTC offset (minutes) then.
#[derive(Clone, Copy)]
pub struct Clock {
    pub now: f64,
    pub offset_min: i32,
}

/// A moment as the clients show it: `{ at, ago, full, until, past }` (3 分钟前; 9/20 14:05:09; 3 小时后; whether it has
/// come).
pub fn stamp(ms: f64, c: Clock) -> Value {
    json!({
        "past": ms <= c.now,
        "at": ms,
        "ago": format::relative_time(ms, c.now, c.offset_min),
        "full": format::absolute_time(ms, c.offset_min),
        "until": format::time_until(ms, c.now),
    })
}

/// Times kept in seconds (still.fail cloud's) and in milliseconds (the station's).
const SECONDS: [&str; 6] = ["created_at", "expires_at", "used_at", "revoked_at", "last_seen", "lastSeen"];
const MILLIS: [&str; 4] = ["createdAt", "lastActiveAt", "checkedAt", "resetsAt"];

/// A quota's windows as the clients draw them, shortest first: each with its mark (5H, W), what is left, how full it
/// is (ok, amber, red), and when it refills in words.
fn windows(list: &mut Vec<Value>, c: Clock) {
    for w in list.iter_mut() {
        let label = w.get("label").and_then(Value::as_str).unwrap_or("").to_string();
        let used = w.get("usedPercent").and_then(Value::as_f64).unwrap_or(0.0);
        let (mark, order) = format::window_mark(&label);
        w["mark"] = json!(mark);
        w["order"] = json!(order);
        let (left, level) = left_level(used);
        w["left"] = json!(left);
        w["level"] = json!(level);
        w["refills"] = json!(w.get("resetsAt").and_then(Value::as_f64).map(|at| format::refills_in(at, c.now)));
    }
    list.sort_by_key(|w| w.get("order").and_then(Value::as_u64).unwrap_or(1));
}

/// What a window with `used` percent of it used has left, and how full it is (ok, amber, red).
pub fn left_level(used: f64) -> (i64, &'static str) {
    ((100.0 - used).max(0.0).round() as i64, if used >= 90.0 { "red" } else if used >= 70.0 { "amber" } else { "ok" })
}

/// Every time in a value, in words beside it: an object with some gets `time: { <field>: stamp }`; a quota's windows
/// are put as they are drawn (`windows`). Refreshed each
/// minute while shown (`Store::refresh`).
pub fn times(value: &mut Value, c: Clock) {
    match value {
        Value::Array(items) => items.iter_mut().for_each(|v| times(v, c)),
        Value::Object(map) => {
            let mut stamps = serde_json::Map::new();
            for (key, v) in map.iter_mut() {
                if let Some(n) = v.as_f64().filter(|n| *n > 0.0) {
                    if SECONDS.contains(&key.as_str()) {
                        stamps.insert(key.clone(), stamp(n * 1000.0, c));
                    } else if MILLIS.contains(&key.as_str()) {
                        stamps.insert(key.clone(), stamp(n, c));
                    }
                } else if key == "windows" && v.as_array().is_some_and(|l| l.iter().any(|w| w.get("usedPercent").is_some())) {
                    if let Some(list) = v.as_array_mut() {
                        windows(list, c);
                    }
                } else if key != "time" {
                    times(v, c);
                }
            }
            if map.contains_key("windows") && map.contains_key("state") {
                if let Some(credits) = map.get("credits").filter(|v| v.is_object()) {
                    let text = if credits["unlimited"] == true { "不限额".to_string() }
                        else if let Some(balance) = credits["balance"].as_str() { format!("{balance} 积分") }
                        else if credits["hasCredits"] == false { "0 积分".to_string() }
                        else { "有可用积分 · 未提供余额".to_string() };
                    map.insert("creditsText".into(), json!(text));
                }
                if let Some(count) = map.get("resetCount").and_then(Value::as_u64) {
                    map.insert("resetText".into(), json!(format!("剩余 {count} 次")));
                }
            }
            if !stamps.is_empty() {
                map.insert("time".into(), Value::Object(stamps));
            }
        }
        _ => {}
    }
}

/// A session's summary with what the clients show of it: where it stands in words and a tone, and its mark (`mark`: run, block, failed; and in words); its
/// title, its agent's label (`agentText`), its model's maker; its runtime and process in words; the efforts its runtime has.
pub fn session(s: &mut Value) {
    if !s.is_object() {
        return;
    }
    let status = shown_status(s);
    let (text, tone) = format::status_text(status);
    let mut text = text.to_string();
    let turn = s.get("lastTurn").cloned().unwrap_or(Value::Null);
    let said = |k: &str| turn.get(k).and_then(Value::as_str).map(str::trim).filter(|w| !w.is_empty()).map(str::to_string);
    match status {
        // What it needs, in its words (要你帮忙：要 Stripe 的测试 key).
        "block" => if let Some(need) = said("need") {
            text = format!("要你帮忙：{need}");
        },
        // What it leaves the chat with (做完了：已合并所有代码).
        "final" => if let Some(done) = said("need") {
            text = format!("做完了：{done}");
        },
        // Why, in words (出问题：额度用完).
        "failed" => text = format!("出问题：{}", format::failure_text(&said("detail").unwrap_or_default())),
        _ => {}
    }
    if !waiting(s).is_null() {
        // Waiting on a watch of its own: the watch brings it back, however long (the station does not ask it again).
        // Otherwise on what it said it waits for (an older station says nothing of it).
        let what = s.get("lastTurn").and_then(|t| t.get("waitFor")).and_then(Value::as_str).map(str::trim).filter(|w| !w.is_empty());
        text = match (s.get("watch").is_some_and(Value::is_object), what) {
            (true, _) => "监控中".to_string(),
            (false, Some(what)) => format!("在等：{what}"),
            (false, None) => "等待中".to_string(),
        };
    }
    let fields = s.clone();
    let str_of = |k: &str| fields.get(k).and_then(Value::as_str).map(str::to_string);
    let runtime = str_of("runtime").unwrap_or_else(|| "claude".into());
    let model = str_of("model");
    let title = str_of("title").filter(|t| !t.is_empty())
        .or_else(|| str_of("firstText").map(|t| format::clean_text(&t)).filter(|t| !t.is_empty()))
        .unwrap_or_else(|| "（还没有消息）".into());
    let badge = mark_of(s);
    s["statusText"] = json!(text);
    s["tone"] = json!(tone);
    s["mark"] = json!(badge);
    s["badgeText"] = json!(badge.map(badge_text));
    s["titleText"] = json!(title);
    let effort = str_of("effort");
    let process = str_of("process");
    s["agentText"] = json!(format::agent_label(model.as_deref(), effort.as_deref()));
    s["modelName"] = json!(model.as_deref().filter(|m| !m.is_empty()).map(stillfail_shapes::model::name));
    s["maker"] = maker(model.as_deref());
    s["runtimeText"] = json!(format::runtime_label(&runtime));
    s["processText"] = json!(process.map(|p| format::process_text(&p)));
    s["efforts"] = json!(format::efforts(&runtime));
}

/// A mark in words: what it says when pointed at.
pub fn badge_text(badge: &str) -> &'static str {
    match badge {
        "block" => "agent 停下来等人处理",
        "run" => "工作中",
        _ => "失败了，需要处理",
    }
}

/// A model's maker as the clients mark it: `{ id, name }`, or null when the marks do not know it (the runtime's mark
/// stands in).
pub fn maker(model: Option<&str>) -> Value {
    match model.and_then(format::maker_of) {
        Some((id, name)) => json!({ "id": id, "name": name }),
        None => Value::Null,
    }
}

/// A connect with its state and how it runs in words.
pub fn connect(c: &mut Value) {
    if !c.is_object() {
        return;
    }
    let (text, presence) = format::connection(c.get("connection").unwrap_or(&Value::Null));
    let mode = c.get("mode").and_then(Value::as_str).unwrap_or("multi-session").to_string();
    let (mode_text, mode_short) = format::mode_text(&mode, c.get("requireMention").and_then(Value::as_bool).unwrap_or(true));
    let bind = c.get("bind").cloned().unwrap_or(Value::Null);
    let runtime = bind.get("runtime").and_then(Value::as_str).unwrap_or("claude");
    let label = format::agent_label(bind.get("model").and_then(Value::as_str), bind.get("effort").and_then(Value::as_str));
    c["statusText"] = json!(text);
    c["presence"] = json!(presence);
    c["modeText"] = json!(mode_text);
    c["modeShort"] = json!(mode_short);
    c["runtimeText"] = json!(format::runtime_label(runtime));
    c["runText"] = json!(format!("{} · {label}", format::runtime_label(runtime)));
    c["modelName"] = json!(bind.get("model").and_then(Value::as_str).filter(|m| !m.is_empty()).map(stillfail_shapes::model::name));
}

/// A profile with its last check in words, and the makers of its models and of those its check found (`makers`, by model).
pub fn profile(p: &mut Value) {
    if !p.is_object() {
        return;
    }
    // An account its provider refuses (suspended, on hold) says so first, whatever its last check found.
    let blocked = p.get("quota").and_then(|q| q.get("state")).and_then(Value::as_str) == Some("blocked");
    let (text, tone) = if blocked { ("被停用", "red") } else { format::check_text(p.get("check").unwrap_or(&Value::Null)) };
    p["checkText"] = json!(text);
    p["checkTone"] = json!(tone);
    p["trouble"] = profile_trouble(p);
    // Its models' makers, by model.
    let mut found = p.get("check").and_then(|c| c.get("models")).and_then(Value::as_array).cloned().unwrap_or_default();
    // Keep a removed model in place while its save is still pending.
    found.extend(p.get("modelsSaving").and_then(Value::as_array).into_iter().flatten().cloned());
    let makers: serde_json::Map<String, Value> = p.get("models").and_then(Value::as_array).into_iter().flatten().chain(found.iter())
        .filter_map(Value::as_str).map(|m| (m.to_string(), maker(Some(m)))).collect();
    // How many of the models it could run are enabled, in words.
    let enabled: Vec<&str> = p.get("models").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str).collect();
    let mut all: Vec<&str> = found.iter().filter_map(Value::as_str).chain(enabled.iter().copied()).collect();
    all.sort_unstable();
    all.dedup();
    let text = if all.is_empty() { "还没有列出模型".to_string() } else { format!("已启用 {} / {} 个模型", enabled.len(), all.len()) };
    let by_series = series(&all);
    // What can be enabled on it: what its provider lists, then whatever is enabled already, each once.
    let mut available: Vec<String> = Vec::new();
    for m in found.iter().filter_map(Value::as_str).chain(enabled.iter().copied()) {
        if !available.iter().any(|a| a == m) {
            available.push(m.to_string());
        }
    }
    let names: serde_json::Map<String, Value> = p.get("models").and_then(Value::as_array).into_iter().flatten().chain(found.iter())
        .chain(p.get("model").into_iter())
        .filter_map(Value::as_str).filter(|m| !m.is_empty()).map(|m| (m.to_string(), json!(stillfail_shapes::model::name(m)))).collect();
    p["makers"] = Value::Object(makers);
    p["names"] = Value::Object(names);
    p["series"] = by_series;
    p["modelsText"] = json!(text);
    p["available"] = json!(available);
}

/// Use provider/check states, never guesses from an error string, to offer a safe next step.
fn profile_trouble(p: &Value) -> Value {
    let check = &p["check"];
    let quota = &p["quota"];
    let detail = |v: &Value, fallback: &str| v["detail"].as_str().filter(|s| !s.trim().is_empty()).unwrap_or(fallback).to_string();
    let issue = |title: &str, detail: String, next: &str, action: &str, label: &str|
        json!({ "title": title, "detail": detail, "next": next, "action": action, "label": label });
    if quota["state"] == "blocked" {
        return issue("账号被停用", detail(quota, "服务商拒绝了这个账号"),
            "到服务商的账号页面查看停用原因，按提示恢复账号；处理后重新查询额度", "quota", "重新查询额度");
    }
    if check["state"] == "login" || check["state"] == "failed" {
        let title = if check["state"] == "login" { "需要登录" } else { "账号检查失败" };
        let why = detail(check, title);
        if p["machine"] == true && check["state"] == "login" {
            return issue(title, why, "在这台 Profile 所属的 station 上运行下面的登录命令，完成后重新检查", "command", "登录后重新检查");
        }
        match p["access"]["kind"].as_str() {
            Some("subscription") if p["machine"] != true && check["state"] == "login" =>
                return issue(title, why, "重新登录这个账号，按下方步骤完成浏览器授权", "login", "重新登录"),
            Some("anthropic-api" | "opencode-go") =>
                return issue(title, why, "核对服务商的 key 是否有效、余额和权限是否足够；可以更换 key，保存后会自动检查", "key", "更换 key"),
            Some("env") =>
                return issue(title, why, "检查模型服务地址、凭据和网络，修改环境变量后重新检查", "env", "编辑环境变量"),
            _ => return issue(title, why, "先重新检查；如果仍然失败，按上面的原因检查账号或 station 的网络", "check", "重新检查"),
        }
    }
    if quota["state"] == "unavailable" {
        return issue("额度查询失败", detail(quota, "暂时查不到额度"),
            "查不到额度不代表账号不能用。先重新查询；仍失败时按返回原因检查登录或网络", "quota", "重新查询额度");
    }
    Value::Null
}

/// Models by series, newest first (stillfail_shapes::model::order), those of no known series last as 其他:
/// `[{ name, models }]`.
pub fn series(models: &[&str]) -> Value {
    let mut sorted: Vec<&str> = models.to_vec();
    sorted.sort_by_cached_key(|m| stillfail_shapes::model::order(m));
    let mut out: Vec<(String, Vec<&str>)> = Vec::new();
    for m in sorted {
        let family = stillfail_shapes::model::family(m).unwrap_or_else(|| "其他".into());
        match out.iter_mut().find(|(f, _)| *f == family) {
            Some((_, list)) => list.push(m),
            None => out.push((family, vec![m])),
        }
    }
    Value::Array(out.into_iter().map(|(name, models)| json!({ "name": name, "models": models })).collect())
}

/// A machine as the clients show it: `summary` (8 核 · 32 GB), `line` (macOS · 8 核 · 32 GB · 已运行 3 天), `facts`
/// (what it is), `meters` (CPU, memory, disk: `{ label, percent, level, value, note }`), `emberText`.
pub fn host(h: &mut Value) {
    if !h.is_object() {
        return;
    }
    let src = h.clone();
    let n = |path: &[&str]| path.iter().try_fold(&src, |v, k| v.get(*k)).and_then(Value::as_f64).unwrap_or(0.0);
    let (cpus, load, uptime) = (n(&["cpus"]), n(&["load"]), n(&["uptimeSec"]));
    let (mem_used, mem_total) = (n(&["memory", "usedBytes"]), n(&["memory", "totalBytes"]));
    let (disk_free, disk_total) = (n(&["disk", "freeBytes"]), n(&["disk", "totalBytes"]));
    let os = src.get("os").and_then(Value::as_str).unwrap_or("").to_string();
    let summary = format!("{cpus} 核 · {}", format::gb(mem_total));
    h["summary"] = json!(summary);
    h["line"] = json!(format!("{os} · {summary} · 已运行 {} 天", (uptime / 86_400.0).floor()));
    // Its card: what it is, how loaded (each meter coloured by how full), and what still.fail itself takes.
    let days = (uptime / 86_400.0).floor();
    let hours = ((uptime % 86_400.0) / 3600.0).floor();
    let arch = src.get("arch").and_then(Value::as_str).unwrap_or("").to_string();
    let meter = |label: &str, short: &str, percent: f64, value: String, note: Option<String>| {
        let p = percent.clamp(0.0, 100.0).round() as i64;
        json!({ "label": label, "short": short, "percent": p, "level": if p >= 90 { "red" } else if p >= 75 { "amber" } else { "ok" }, "value": value, "note": note })
    };
    let swap = n(&["memory", "swapUsedBytes"]);
    // How busy the CPUs are, all of them together (up to 100%), the load average beside it; stations before cpuBusy: the
    // load average over the cores alone.
    let model = src.get("cpuModel").and_then(Value::as_str).filter(|m| !m.is_empty());
    let cpu = match src.get("cpuBusy").and_then(Value::as_f64) {
        Some(busy) => {
            let note = [Some(format!("负载 {:.1}", load * cpus)), model.map(str::to_string)].into_iter().flatten().collect::<Vec<_>>().join(" · ");
            meter("CPU", "CPU", busy * 100.0, format!("{}%", (busy * 100.0).round()), Some(note))
        }
        None => meter("CPU 负载", "CPU", load * 100.0, format!("{}%", (load * 100.0).round()), model.map(str::to_string)),
    };
    h["facts"] = json!([
        src.get("hostname").and_then(Value::as_str).unwrap_or(""), os, format!("{arch} · {cpus} 核"),
        format!("已运行 {}", if days > 0.0 { format!("{days} 天 {hours} 小时") } else { format!("{hours} 小时") }),
    ]);
    h["meters"] = json!([
        cpu,
        meter("内存", "内存", if mem_total > 0.0 { mem_used / mem_total * 100.0 } else { 0.0 }, format!("{} / {}", format::gb1(mem_used), format::gb1(mem_total)),
            (swap > 0.0).then(|| format!("swap {}", format::gb1(swap)))),
        meter("磁盘", "磁盘", if disk_total > 0.0 { (disk_total - disk_free) / disk_total * 100.0 } else { 0.0 }, format!("剩 {} / {}", format::gb1(disk_free), format::gb1(disk_total)), None),
    ]);
    let remaining = |bytes: f64| format!("剩余 {:.1} G", bytes.max(0.0) / 1024f64.powi(3));
    h["meters"][1]["remaining"] = json!(remaining(mem_total - mem_used));
    h["meters"][2]["remaining"] = json!(remaining(disk_free));
    h["emberText"] = json!(format!("{} {} MB", crate::brand::name(), (n(&["emberRssBytes"]) / 1024f64.powi(2)).round()));
}

/// A station's connection as its card shows it (shapes `StationNet`), from what `Topic::Net` read of it; None
/// while there is none. Only what is off is coloured: a slow round trip, packets lost. A relay is said by the name
/// still.fail gives it (`relay_name`, by host: 北京中继), or its host.
pub fn net(raw: &Value, relay_name: &dyn Fn(&str) -> Option<String>) -> Option<Value> {
    if !raw.is_object() {
        return None;
    }
    let path = match raw.get("path").and_then(Value::as_str) {
        Some("direct") => "直连".to_string(),
        Some("relay") => match raw.get("relay").and_then(Value::as_str).filter(|h| !h.is_empty()) {
            Some(host) => match relay_name(host) {
                Some(name) => format!("{name}中继"),
                None => format!("中继 {host}"),
            },
            None => "中继".to_string(),
        },
        _ => "正在选路".to_string(),
    };
    let samples: Vec<&Value> = raw.get("samples").and_then(Value::as_array).map(|a| a.iter().collect()).unwrap_or_default();
    let figure = |ms: f64| {
        let text = if ms >= 1000.0 { format!("{:.1} s", ms / 1000.0) } else { format!("{} ms", ms.round().max(1.0) as i64) };
        json!({ "text": text, "level": if ms >= 1000.0 { "red" } else if ms >= 300.0 { "amber" } else { "ok" } })
    };
    let rtt = raw.get("rttMs").and_then(Value::as_f64).map(figure);
    let named = |host: &str| relay_name(host).unwrap_or_else(|| host.to_string());
    // The way through each relay as last measured (mesh.rs `Mesh::quickest`): the one the link goes through marked.
    let via = (raw.get("path").and_then(Value::as_str) == Some("relay")).then(|| raw.get("relay").and_then(Value::as_str)).flatten();
    let measured = raw.get("measured").filter(|m| m.is_object()).map(|m| {
        let relays: Vec<Value> = m.get("relays").and_then(Value::as_array).into_iter().flatten().filter_map(|r| {
            let host = r.get("relay").and_then(Value::as_str)?;
            Some(json!({ "name": named(host), "rtt": r.get("rttMs").and_then(Value::as_f64).map(figure), "current": via == Some(host) }))
        }).collect();
        json!({
            "measuring": m.get("measuring").and_then(Value::as_bool).unwrap_or(false),
            "relays": relays,
            "moved": m.get("moved").and_then(Value::as_str).map(named),
        })
    });
    let history: Vec<f64> = samples.iter().filter_map(|s| s.get("rttMs").and_then(Value::as_f64)).map(|ms| (ms * 10.0).round() / 10.0).collect();
    let rate = |key: &str| samples.last().and_then(|s| s.get(key)).and_then(Value::as_f64).map(|b| format!("{}/s", format::bytes(b))).unwrap_or_else(|| "—".into());
    let n = |key: &str| raw.get(key).and_then(Value::as_f64).unwrap_or(0.0);
    let (sent, lost) = samples.iter().fold((0.0, 0.0), |(sent, lost), s| {
        (sent + s.get("sent").and_then(Value::as_f64).unwrap_or(0.0), lost + s.get("lost").and_then(Value::as_f64).unwrap_or(0.0))
    });
    // Today's over all its links where the wire counts them (the mesh), else this connection's since it opened.
    let daily = raw.get("todayRxBytes").is_some_and(Value::is_number);
    let (rx, tx) = if daily { (n("todayRxBytes"), n("todayTxBytes")) } else { (n("rxBytes"), n("txBytes")) };
    // Over enough packets to say, and enough of them lost to matter.
    let loss = (sent >= 20.0 && lost / sent >= 0.01).then(|| {
        let pct = lost / sent * 100.0;
        json!({ "text": format!("丢包 {pct:.1}%"), "level": if pct >= 10.0 { "red" } else { "amber" } })
    });
    Some(json!({
        "path": path, "rtt": rtt, "rttHistory": history,
        "down": rate("rxBps"), "up": rate("txBps"),
        "total": format!("{} ↓ {} · ↑ {}", if daily { "今天共" } else { "本次共" }, format::bytes(rx), format::bytes(tx)),
        "downTotal": format::bytes(rx),
        "upTotal": format::bytes(tx),
        "loss": loss,
        "measured": measured,
    }))
}

/// Whether what goes out of a topic shows times in words (sent again each minute).
pub fn ticks(topic: &Topic) -> bool {
    !matches!(topic, Topic::Live { .. } | Topic::Thread { .. } | Topic::History { .. } | Topic::Host { .. } | Topic::Net { .. } | Topic::Status { .. } | Topic::Notices { .. } | Topic::Notify { .. } | Topic::Connection { .. } | Topic::Draft { .. } | Topic::Prefs | Topic::Doing | Topic::SlackTokens { .. })
}

/// A topic's value through the shape the clients are generated from (client/shapes): what it does not declare is
/// dropped, and a value it does not allow (a fractional time, a field missing) is an error naming the field. Topics
/// with no shape yet go as they are.
pub fn conform(topic: &Topic, value: Value) -> Result<Value, String> {
    use stillfail_shapes as s;
    match topic {
        Topic::Chats { .. } => s::conform::<s::ChatsView>(value),
        Topic::ChatSearch { .. } => s::conform::<s::ChatSearchView>(value),
        Topic::Chat { .. } => s::conform::<s::ChatView>(value),
        Topic::Stations { .. } => s::conform::<Vec<s::StationView>>(value),
        Topic::Connects { .. } => s::conform::<s::ConnectsView>(value),
        Topic::History { .. } => s::conform::<s::HistoryView>(value),
        Topic::Live { .. } => s::conform::<s::Live>(value),
        Topic::Overview { .. } => s::conform::<s::Overview>(value),
        Topic::Sessions { .. } => s::conform::<Vec<s::Session>>(value),
        Topic::Session { .. } => s::conform::<s::SessionDetail>(value),
        Topic::Threads { .. } => s::conform::<Vec<s::ChatThread>>(value),
        Topic::Host { .. } => s::conform::<s::Host>(value),
        Topic::Footprint { .. } => s::conform::<s::FootprintView>(value),
        Topic::Status { .. } => s::conform::<s::StatusView>(value),
        Topic::Connection { .. } => s::conform::<s::ConnectionView>(value),
        Topic::Notices { .. } => s::conform::<s::NoticesView>(value),
        Topic::Draft { .. } => s::conform::<s::DraftView>(value),
        Topic::Notify { .. } => s::conform::<s::NotifyView>(value),
        Topic::Archive { .. } => s::conform::<s::ArchiveView>(value),
        Topic::NewChat { .. } => s::conform::<s::NewChatView>(value),
        Topic::Pick { .. } => s::conform::<s::PickView>(value),
        Topic::ChatJobs { .. } => s::conform::<s::ChatJobsView>(value),
        Topic::LongJobs { .. } => s::conform::<s::LongJobsView>(value),
        Topic::Usage { .. } => s::conform::<s::UsageView>(value),
        Topic::Job { .. } => s::conform::<s::Job>(value),
        Topic::JobLog { .. } => s::conform::<s::JobLogView>(value),
        Topic::Prefs => s::conform::<s::PrefsView>(value),
        Topic::Changelog => s::conform::<s::ChangelogView>(value),
        Topic::ConnectFlow { .. } => s::conform::<s::ConnectFlowView>(value),
        Topic::SlackTokens { .. } => s::conform::<s::SlackTokensView>(value),
        Topic::Doing => s::conform::<s::DoingView>(value),
        Topic::WorkspaceMarks { .. } => s::conform::<s::WorkspaceMarksView>(value),
        Topic::Decisions { .. } => s::conform::<s::DecisionsView>(value),
        _ => Ok(value),
    }
}

/// What goes out of a topic, with what the clients show of it put in (see above). The transcript and a thread's
/// pages go as they are: the views that show them put in their own.
pub fn decorate(topic: &Topic, value: &mut Value, c: Clock) {
    match topic {
        Topic::Host { .. } => return host(value),
        Topic::Footprint { .. } => return *value = crate::footprint::shown(value, c),
        _ if !ticks(topic) => return,
        Topic::Sessions { .. } => value.as_array_mut().into_iter().flatten().for_each(session),
        Topic::Session { .. } => {
            if let Some(s) = value.get_mut("session") {
                session(s);
            }
        }
        Topic::Overview { .. } => {
            // Its agents' processes, in a line.
            if let Some(processes) = value.get("processes").and_then(Value::as_array).cloned() {
                let mb: f64 = processes.iter().filter_map(|p| p.get("rssMb").and_then(Value::as_f64)).sum();
                value["processesText"] = json!(if processes.is_empty() {
                    "没有运行中的 agent 进程".to_string()
                } else {
                    format!("{} 个 agent 进程 {}", processes.len(), if mb >= 1024.0 { format!("{:.1} GB", mb / 1024.0) } else { format!("{mb} MB") })
                });
            }
            if let Some(usage) = value.get_mut("footprint").filter(|u| u.is_object()) {
                crate::footprint::brief(usage);
            }
            value.get_mut("connects").and_then(Value::as_array_mut).into_iter().flatten().for_each(connect);
            if let Some(profiles) = value.get_mut("profiles").and_then(Value::as_array_mut) {
                profiles.iter_mut().for_each(profile);
                // Both mobile clients open the settings count onto the same, actionable profiles first.
                profiles.sort_by_key(|p| p["trouble"].is_null());
            }
            // The machine's own logins a profile could use now: no machine profile or bound subscription on the same account.
            let subscriptions: Vec<(Value, String)> = value.get("profiles").and_then(Value::as_array).into_iter().flatten()
                .filter(|p| p["access"]["kind"] == "subscription")
                .filter_map(|p| Some((p.get("runtime")?.clone(), p.get("email")?.as_str()?.trim().to_ascii_lowercase())))
                .filter(|(_, email)| !email.is_empty()).collect();
            let taken: Vec<Value> = value.get("profiles").and_then(Value::as_array).into_iter().flatten()
                .filter(|p| p.get("machine").and_then(Value::as_bool) == Some(true)).filter_map(|p| p.get("runtime").cloned()).collect();
            for l in value.get_mut("machineLogins").and_then(Value::as_array_mut).into_iter().flatten() {
                let offered = l.get("loggedIn").and_then(Value::as_bool) == Some(true)
                    && l.get("plan").is_some_and(|p| p.as_str().is_some_and(|p| !p.is_empty()))
                    && !l.get("runtime").is_some_and(|r| taken.contains(r))
                    && !l.get("email").and_then(Value::as_str).is_some_and(|email| {
                        subscriptions.iter().any(|(runtime, bound)| l.get("runtime") == Some(runtime) && email.trim().eq_ignore_ascii_case(bound))
                    });
                l["offered"] = json!(offered);
            }
        }
        // Its agents' jobs, each with its dot and words (jobs.rs); a job, its output.
        Topic::Chat { .. } => {
            for jobs in value.get_mut("agents").and_then(Value::as_array_mut).into_iter().flatten().filter_map(|a| a.get_mut("jobs")?.as_array_mut()) {
                jobs.iter_mut().for_each(|j| *j = crate::jobs::shown(j, c));
            }
        }
        Topic::Decisions { .. } => crate::decisions::today(value, c),
        Topic::Job { .. } => *value = crate::jobs::shown(value, c),
        Topic::JobLog { .. } => crate::jobs::log(value, c),
        _ => {}
    }
    times(value, c);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_connection_is_said_in_words_and_only_what_is_off_is_coloured() {
        let unnamed = |_: &str| None;
        assert_eq!(net(&Value::Null, &unnamed), None);
        let sample = |rtt: f64, sent: u64, lost: u64| json!({ "at": 0, "rttMs": rtt, "rxBps": 1_468_006, "txBps": 83_968, "sent": sent, "lost": lost });
        let raw = json!({ "path": "direct", "rttMs": 38.4, "rxBytes": 222_298_112u64, "txBytes": 10_066_329u64, "samples": [sample(40.0, 50, 0), sample(38.4, 50, 0)] });
        let shown = net(&raw, &unnamed).unwrap();
        assert_eq!(shown["path"], "直连");
        assert_eq!(shown["rtt"], json!({ "text": "38 ms", "level": "ok" }));
        assert_eq!(shown["rttHistory"], json!([40.0, 38.4]));
        assert_eq!((shown["down"].as_str(), shown["up"].as_str()), (Some("1.4 MB/s"), Some("82 KB/s")));
        assert_eq!(shown["total"], "本次共 ↓ 212 MB · ↑ 9.6 MB");
        assert_eq!((shown["downTotal"].as_str(), shown["upTotal"].as_str()), (Some("212 MB"), Some("9.6 MB")));
        assert_eq!(shown["loss"], Value::Null);
        // Where the wire counts the day (the mesh): today's over all the station's links, not this one's.
        let mut daily = raw.clone();
        daily["todayRxBytes"] = json!(1_073_741_824u64);
        daily["todayTxBytes"] = json!(52_428_800u64);
        let shown = net(&daily, &unnamed).unwrap();
        assert_eq!(shown["total"], "今天共 ↓ 1.0 GB · ↑ 50 MB");
        assert_eq!((shown["downTotal"].as_str(), shown["upTotal"].as_str()), (Some("1.0 GB"), Some("50 MB")));

        let raw = json!({ "path": "relay", "relay": "relay.still.fail", "rttMs": 286.0, "rxBytes": 0, "txBytes": 0, "samples": [sample(1200.0, 40, 2)] });
        let shown = net(&raw, &unnamed).unwrap();
        assert_eq!(shown["path"], "中继 relay.still.fail");
        let named = |host: &str| (host == "relay.still.fail").then(|| "北京".to_string());
        assert_eq!(net(&raw, &named).unwrap()["path"], "北京中继");
        assert_eq!(shown["rtt"]["level"], "ok");
        assert_eq!(shown["loss"], json!({ "text": "丢包 5.0%", "level": "amber" }));
        // Not yet two readings: nothing to say of speed.
        let measured = json!({ "measuring": false, "relays": [{ "relay": "relay.still.fail", "rttMs": 11_000.0 }, { "relay": "hk.test", "rttMs": 82.0 }, { "relay": "cf.test", "rttMs": null }], "moved": "hk.test" });
        let raw = json!({ "path": "relay", "relay": "hk.test", "rttMs": 90.0, "rxBytes": 0, "txBytes": 0, "samples": [], "measured": measured });
        assert_eq!(net(&raw, &named).unwrap()["measured"], json!({
            "measuring": false,
            "relays": [
                { "name": "北京", "rtt": { "text": "11.0 s", "level": "red" }, "current": false },
                { "name": "hk.test", "rtt": { "text": "82 ms", "level": "ok" }, "current": true },
                { "name": "cf.test", "rtt": null, "current": false },
            ],
            "moved": "hk.test",
        }));
        let shown = net(&json!({ "path": null, "rttMs": 1500.0, "rxBytes": 0, "txBytes": 0, "samples": [] }), &unnamed).unwrap();
        assert_eq!((shown["path"].as_str(), shown["down"].as_str()), (Some("正在选路"), Some("—")));
        assert_eq!(shown["rtt"], json!({ "text": "1.5 s", "level": "red" }));
    }

    #[test]
    fn a_rows_people_are_said_in_words_who_started_it_first() {
        let me = json!({ "id": "me@x.com", "email": "me@x.com" });
        let mut row = json!({ "creator": { "id": "wang@x.com", "name": "小王" }, "people": [{ "id": "lina@x.com", "name": "Lina" }, { "id": "me@x.com", "name": "Me" }] });
        row_people(&mut row, &me, &[], &[]);
        assert_eq!(row["peopleText"], "小王 发起 · Lina、你");
        // Nobody said to have started it: only who is in it.
        let mut row = json!({ "people": [{ "id": "lina@x.com", "name": "Lina" }] });
        row_people(&mut row, &me, &[], &[]);
        assert_eq!(row["peopleText"], "Lina");
    }

    #[test]
    fn profile_recovery_follows_states_and_clears_after_success() {
        let mut p = json!({"access": {"kind": "subscription"}, "check": {"state": "login"}, "quota": {"state": "unavailable"}});
        profile(&mut p);
        assert_eq!(p["trouble"]["action"], "login", "fix the login before retrying the quota");
        p["machine"] = json!(true);
        profile(&mut p);
        assert_eq!(p["trouble"]["action"], "command", "a machine login cannot be changed in the app");
        p["check"]["state"] = json!("ok");
        profile(&mut p);
        assert_eq!(p["trouble"]["action"], "quota");
        assert_eq!(p["checkText"], "可用", "failure to read quota does not make the account unusable");
        assert_eq!(p["trouble"]["detail"], "暂时查不到额度", "old stations may omit the error detail");
        p["quota"]["state"] = json!("ok");
        profile(&mut p);
        assert!(p["trouble"].is_null(), "a recovered profile no longer contributes to the count");
        p["quota"]["state"] = json!("blocked");
        profile(&mut p);
        assert_eq!(p["trouble"]["title"], "账号被停用");
        assert_eq!(p["checkTone"], "red");
    }

    #[test]
    fn profile_recovery_offers_only_the_editor_for_its_access_kind() {
        for (kind, action) in [("anthropic-api", "key"), ("opencode-go", "key"), ("env", "env"), ("subscription", "check")] {
            let p = json!({"access": {"kind": kind}, "check": {"state": "failed", "detail": "timeout"}});
            let issue = profile_trouble(&p);
            assert_eq!(issue["action"], action);
            assert_eq!(issue["detail"], "timeout");
        }
        assert!(profile_trouble(&json!({})).is_null(), "an unchecked old profile has no invented problem");
    }

    #[test]
    fn a_session_stands_where_its_process_and_last_turn_say() {
        assert_eq!(session_status(&json!({"process": "running"})), "running");
        assert_eq!(session_status(&json!({"process": "warm", "pending": 1})), "queued");
        assert_eq!(session_status(&json!({"lastTurn": {"declared": "block", "outcome": "completed"}})), "block");
        // Today's words, as the station says them besides the words from before.
        assert_eq!(session_status(&json!({"lastTurn": {"declared": "block", "ending": "need_decision", "outcome": "completed"}})), "block", "need_decision from a station before cards: need_help");
        assert_eq!(session_status(&json!({"lastTurn": {"declared": "block", "ending": "need_help", "outcome": "completed"}})), "block");
        assert_eq!(session_status(&json!({"lastTurn": {"declared": "final", "ending": "all_done", "outcome": "completed"}})), "final");
        assert_eq!(session_status(&json!({"lastTurn": {"declared": "final", "outcome": "completed"}})), "final");
        assert_eq!(session_status(&json!({"process": "warm", "lastTurn": {"declared": "waiting", "ending": "waiting", "outcome": "completed"}})), "running");
        assert_eq!(session_status(&json!({"process": "warm", "lastTurn": {"declared": "waiting", "outcome": "completed"}})), "running");
        assert_eq!(session_status(&json!({"lastTurn": {"outcome": "completed"}})), "unexpected");
        let waits = json!({"process": "warm", "lastTurn": {"declared": "waiting", "outcome": "completed", "endedAt": 5, "waitSeconds": 600}});
        assert_eq!(waiting(&waits), json!({"since": 5, "seconds": 600, "text": "等待中"}));
        assert_eq!(waiting(&json!({"process": "warm", "lastTurn": {"declared": "waiting", "outcome": "completed", "endedAt": 5}})), json!({"since": 5, "seconds": null, "text": "等待中"}));
        assert_eq!(waiting(&json!({"process": "warm", "lastTurn": {"declared": "waiting", "outcome": "completed", "endedAt": 5, "waitFor": "CI 跑完"}}))["text"], "在等：CI 跑完");
        // Waiting on a watch of its own: said so.
        let mut watching = json!({"process": "warm", "lastTurn": {"declared": "waiting", "outcome": "completed", "endedAt": 5, "waitSeconds": 600}, "watch": {"names": ["盯 CI"], "since": 1, "at": 5}});
        session(&mut watching);
        assert_eq!((watching["statusText"].clone(), watching["mark"].clone()), (json!("监控中"), Value::Null), "not at work");
        let mut plain = waits.clone();
        session(&mut plain);
        assert_eq!(plain["statusText"], "等待中");
        let mut said = json!({"process": "warm", "lastTurn": {"declared": "waiting", "outcome": "completed", "endedAt": 5, "waitSeconds": 600, "waitFor": "CI 跑完"}});
        session(&mut said);
        assert_eq!(said["statusText"], "在等：CI 跑完");
        assert_eq!(waiting(&json!({"process": "running", "lastTurn": {"declared": "waiting", "outcome": "completed", "endedAt": 5}})), Value::Null);
        assert_eq!(waiting(&json!({"process": "warm", "pending": 1, "lastTurn": {"declared": "waiting", "endedAt": 5}})), Value::Null);
        assert_eq!(session_status(&json!({})), "idle");
    }

    #[test]
    fn an_account_its_provider_refuses_says_so_whatever_its_check_found() {
        let mut p = json!({"check": {"state": "ok"}, "quota": {"state": "blocked", "windows": []}});
        profile(&mut p);
        assert_eq!((p["checkText"].as_str(), p["checkTone"].as_str()), (Some("被停用"), Some("red")));
        let mut ok = json!({"check": {"state": "ok"}, "quota": {"state": "unavailable", "windows": []}});
        profile(&mut ok);
        assert_eq!(ok["checkText"], "可用");
    }

    #[test]
    fn a_rows_state_puts_block_first() {
        let agents = [json!({"lastTurn": {"outcome": "failed"}}), json!({"process": "running"}), json!({"lastTurn": {"declared": "block"}})];
        assert_eq!(row_state(&agents), Some("block"));
        assert_eq!(row_state(&agents[..2]), Some("run"));
        assert_eq!(row_state(&[json!({"lastTurn": {"declared": "final"}})]), None);
    }

    #[test]
    fn the_last_speaker_is_named_and_an_agents_state_rides_on_it() {
        let me = json!({"id": "a@x.com", "email": "a@x.com"});
        let members = [json!({"email": "b@x.com", "name": "阿二", "picture": "https://p/b"})];
        let row = |kind: &str, author: &str| json!({
            "agents": [{"key": "k", "model": "deepseek-flash", "runtime": "claude", "lastTurn": {"declared": "block"}}],
            "last": {"authorKind": kind, "author": author, "authorName": null, "text": "hi"},
        });
        let agent = last_by(&row("agent", "k"), &me, &[], &members).unwrap();
        assert_eq!((agent["name"].as_str(), agent["state"].as_str()), (Some("DeepSeek Flash"), Some("block")));
        let other = last_by(&row("person", "b@x.com"), &me, &[], &members).unwrap();
        assert_eq!((other["name"].as_str(), other["picture"].as_str(), other["mine"].as_bool()), (Some("阿二"), Some("https://p/b"), Some(false)));
        assert_eq!(last_by(&row("person", "A@x.com"), &me, &[], &members).unwrap()["name"], "你");
        assert_eq!(last_by(&row("person", "U7"), &me, &["U7".into()], &members).unwrap()["mine"], true, "a Slack user who is the viewer");
    }

    #[test]
    fn a_profiles_models_come_by_series() {
        let mut p = json!({"models": ["claude-opus-5-5"], "check": {"models": ["claude-sonnet-5", "claude-opus-4-8", "claude-opus-5-5", "my-model", "claude-fable-5-1"]}});
        profile(&mut p);
        assert_eq!(p["series"], json!([
            {"name": "Fable", "models": ["claude-fable-5-1"]},
            {"name": "Opus", "models": ["claude-opus-5-5", "claude-opus-4-8"]},
            {"name": "Sonnet", "models": ["claude-sonnet-5"]},
            {"name": "其他", "models": ["my-model"]},
        ]));
    }

    #[test]
    fn how_a_turn_ended_says_itself_in_words() {
        let words = |turn: Value| {
            let mut s = json!({"process": "warm", "lastTurn": turn});
            session(&mut s);
            s["statusText"].as_str().unwrap().to_string()
        };
        assert_eq!(words(json!({"declared": "final", "ending": "all_done", "outcome": "completed"})), "做完了");
        assert_eq!(words(json!({"declared": "block", "ending": "need_help", "need": "要 Stripe 的测试 key", "outcome": "completed"})), "要你帮忙：要 Stripe 的测试 key");
        assert_eq!(words(json!({"declared": "block", "outcome": "completed"})), "要你帮忙");
        assert_eq!(words(json!({"declared": "block", "ending": "need_decision", "outcome": "completed"})), "要你帮忙");
        assert_eq!(words(json!({"outcome": "failed", "detail": "rate_limit: You've hit your limit"})), "出问题：额度用完");
        assert_eq!(words(json!({"outcome": "failed", "detail": "auth: 401"})), "出问题：登录失效");
        assert_eq!(words(json!({"outcome": "aborted"})), "出问题：被停止");
        assert_eq!(words(json!({"outcome": "completed"})), "出问题：没说一声就停了");
        let mut decided = json!({"process": "warm", "lastTurn": {"declared": "block", "ending": "need_decision", "outcome": "completed"}});
        session(&mut decided);
        assert_eq!(decided["mark"], "block", "a decision marks it as help does: the row's decision says which");
    }

    #[test]
    fn a_decision_agent_passes_the_chat_shape() {
        let mut s = json!({
            "key": "ember:c-decision", "runtime": "codex", "process": "warm", "pending": 0,
            "lastTurn": {"kind": "message", "startedAt": 1, "declared": "block", "ending": "need_decision", "outcome": "completed"}
        });
        session(&mut s);
        let agent = json!({
            "status": shown_status(&s), "badge": mark_of(&s), "session": s,
            "profiles": [], "choices": [], "attention": [], "turns": [], "threads": [], "jobs": []
        });
        let checked = stillfail_shapes::conform::<stillfail_shapes::ChatAgent>(agent).unwrap();
        assert_eq!(checked["status"], "block");
        assert_eq!(checked["badge"], "block");
        assert_eq!(checked["session"]["statusText"], "要你帮忙");
        // Older cores emitted decision: the shape must accept those values too.
        let mut legacy = checked;
        legacy["status"] = json!("decision");
        assert_eq!(stillfail_shapes::conform::<stillfail_shapes::ChatAgent>(legacy).unwrap()["status"], "decision");
    }

    #[test]
    fn a_chat_with_nothing_left_is_settled_and_says_where_it_stands() {
        let agent = |turn: Value, process: &str| {
            let mut a = json!({"key": "k", "process": process, "pending": 0, "lastTurn": turn});
            session(&mut a);
            a
        };
        let done = agent(json!({"declared": "final", "ending": "all_done", "outcome": "completed"}), "warm");
        let helped = agent(json!({"declared": "block", "ending": "need_help", "need": "要 key", "outcome": "completed"}), "warm");
        let waits = agent(json!({"declared": "waiting", "ending": "waiting", "waitFor": "CI 跑完", "outcome": "completed", "endedAt": 5}), "warm");
        let works = agent(Value::Null, "running");
        let row = |agents: Vec<Value>, unread: bool| json!({"agents": agents, "unread": unread});
        assert!(settled(&row(vec![done.clone()], false)));
        let mut kept = row(vec![done.clone()], false);
        kept["pinned"] = json!(1700000000000i64);
        assert!(pinned(&kept), "pinned: kept for the long run, not drawn as finished");
        assert!(!pinned(&row(vec![done.clone()], false)));
        assert_eq!(row_state_text(&row(vec![done.clone()], false)).as_deref(), Some("做完了"));
        let merged = agent(json!({"declared": "final", "ending": "all_done", "need": "已合并所有代码", "outcome": "completed"}), "warm");
        assert_eq!(merged["statusText"], "做完了：已合并所有代码");
        assert_eq!(row_state_text(&row(vec![merged], false)).as_deref(), Some("做完了：已合并所有代码"));
        assert!(!settled(&row(vec![done.clone()], true)), "something unread in it");
        assert!(!settled(&row(vec![done.clone(), helped.clone()], false)));
        assert_eq!(row_state_text(&row(vec![done.clone(), helped.clone()], false)).as_deref(), Some("要你帮忙：要 key"));
        assert_eq!(row_state_text(&row(vec![done.clone(), waits.clone()], false)).as_deref(), Some("在等：CI 跑完"));
        assert_eq!(row_state_text(&row(vec![done.clone(), works], false)), None, "at work: its activity says");
        assert!(!settled(&row(vec![], false)));
        // A card waiting for the viewer keeps it from being settled, and says itself over all done, a wait, or work.
        let card = json!({"seq": 4, "card": {"type": "text"}, "message": {"seq": 4, "text": "**域名用哪个？**\n细节"}});
        let mut asked = row(vec![done.clone()], false);
        asked["card"] = card.clone();
        assert_eq!((settled(&asked), row_state_line(&asked)), (false, Some(("奏 · 域名用哪个？".to_string(), Some(4)))));
        asked["agents"] = json!([agent(Value::Null, "running")]);
        assert_eq!(row_state_text(&asked).as_deref(), Some("奏 · 域名用哪个？"), "at work: the card still says");
        asked["agents"] = json!([waits.clone()]);
        assert_eq!(row_state_text(&asked).as_deref(), Some("奏 · 域名用哪个？"));
        // But a need says itself first (about the card, unless it says what it is about); and so does a failure.
        asked["agents"] = json!([helped.clone()]);
        assert_eq!(row_state_line(&asked), Some(("要你帮忙：要 key".to_string(), Some(4))));
        let failed = agent(json!({"outcome": "failed", "detail": "auth: 401"}), "warm");
        asked["agents"] = json!([failed]);
        assert_eq!(row_state_text(&asked).as_deref(), Some("出问题：登录失效"));
        // A need said without words (a station from before them): the card says more.
        asked["agents"] = json!([agent(json!({"declared": "block", "ending": "need_decision", "outcome": "completed"}), "warm")]);
        assert_eq!(row_state_text(&asked).as_deref(), Some("奏 · 域名用哪个？"));
        asked["card"]["dismissed"] = json!(true);
        assert_eq!(row_state_text(&asked).as_deref(), Some("要你帮忙"));
        asked["agents"] = json!([done.clone()]);
        assert!(settled(&asked), "dismissed: nothing waits for the viewer");
        // A state about a message in this chat: its seq; one in another chat of the agent's: none.
        let about = |about: Value| agent(json!({"declared": "final", "ending": "all_done", "need": "已合进 main", "about": about, "outcome": "completed"}), "warm");
        let mut here = row(vec![about(json!({"thread": 7, "seq": 12, "ts": "1.2"}))], false);
        here["thread"] = json!(7);
        assert_eq!(row_state_line(&here), Some(("做完了：已合进 main".to_string(), Some(12))));
        here["agents"] = json!([about(json!({"thread": 8, "seq": 12, "ts": "1.2"}))]);
        assert_eq!(row_state_line(&here), Some(("做完了：已合进 main".to_string(), None)));
        let mut waiting = row(vec![agent(json!({"declared": "waiting", "ending": "waiting", "waitFor": "CI", "about": {"thread": 7, "seq": 3, "ts": "1.1"}, "outcome": "completed", "endedAt": 5}), "warm")], false);
        waiting["thread"] = json!(7);
        assert_eq!(row_state_line(&waiting), Some(("在等：CI".to_string(), Some(3))));
    }

    #[test]
    fn what_a_profile_can_enable_and_which_machine_logins_are_offered() {
        let mut p = json!({"models": ["mine", "b"], "check": {"models": ["a", "b"]}});
        profile(&mut p);
        assert_eq!(p["available"], json!(["a", "b", "mine"]));
        let c = Clock { now: 0.0, offset_min: 0 };
        let mut o = json!({
            "profiles": [{"runtime": "claude", "machine": true, "models": []}],
            "machineLogins": [
                {"runtime": "claude", "loggedIn": true, "plan": "max"},
                {"runtime": "codex", "loggedIn": true, "plan": "plus"},
                {"runtime": "codex", "loggedIn": true, "plan": null},
                {"runtime": "codex", "loggedIn": false, "plan": "plus"},
            ],
        });
        decorate(&Topic::Overview { station: "w/s".into() }, &mut o, c);
        let offered: Vec<bool> = o["machineLogins"].as_array().unwrap().iter().map(|l| l["offered"] == true).collect();
        assert_eq!(offered, [false, true, false, false]);
    }

    #[test]
    fn bound_subscriptions_hide_only_the_same_machine_account() {
        let mut o = json!({
            "profiles": [
                {"name": "Renamed", "runtime": "claude", "access": {"kind": "subscription"}, "email": " A@x.com "},
                {"runtime": "codex", "access": {"kind": "env"}, "email": "b@x.com"},
                {"runtime": "codex", "access": {"kind": "subscription"}, "email": "c@x.com"},
                {"name": "d@x.com", "runtime": "codex", "access": {"kind": "subscription"}},
            ],
            "machineLogins": [
                {"runtime": "claude", "email": "a@x.com"},
                {"runtime": "codex", "email": "a@x.com"},
                {"runtime": "codex", "email": "b@x.com"},
                {"runtime": "codex", "email": "c@x.com"},
                {"runtime": "codex", "email": "d@x.com"},
                {"runtime": "claude", "email": ""},
                {"runtime": "claude"},
            ],
        });
        for l in o["machineLogins"].as_array_mut().unwrap() {
            l["loggedIn"] = json!(true);
            l["plan"] = json!("pro");
        }
        let topic = Topic::Overview { station: "w/s".into() };
        let clock = Clock { now: 0.0, offset_min: 0 };
        decorate(&topic, &mut o, clock);
        let offered: Vec<_> = o["machineLogins"].as_array().unwrap().iter().map(|l| l["offered"] == true).collect();
        assert_eq!(offered, [false, true, true, false, true, true, true]);
        o["profiles"] = json!([]);
        decorate(&topic, &mut o, clock);
        assert!(o["machineLogins"].as_array().unwrap().iter().all(|l| l["offered"] == true));
    }

    #[test]
    fn what_the_clients_show_is_put_in_here() {
        let c = Clock { now: 1_790_467_200_000.0, offset_min: 480 };
        // A session: where it stands in words, its title, label and maker, and its runtime's efforts.
        let mut s = json!({"runtime": "codex", "model": "gpt-6-astra", "effort": "medium", "process": "warm", "lastTurn": {"declared": "block"}, "firstText": "<@U1> 看看 CI"});
        session(&mut s);
        assert_eq!((s["statusText"].as_str(), s["tone"].as_str(), s["badgeText"].as_str()), (Some("要你帮忙"), Some("blue"), Some("agent 停下来等人处理")));
        assert_eq!((s["titleText"].as_str(), s["agentText"].as_str(), s["maker"]["id"].as_str()), (Some("看看 CI"), Some("GPT-6 Astra · medium"), Some("openai")));
        assert_eq!(s["modelName"], "GPT-6 Astra");
        assert_eq!((s["processText"].as_str(), s["efforts"][0].as_str()), (Some("保温中"), Some("minimal")));
        // Times anywhere, and a quota's windows shortest first, marked.
        let mut v = json!({"createdAt": c.now - 180_000.0, "quota": {"windows": [
            {"label": "每周", "usedPercent": 95, "resetsAt": c.now + 3_900_000.0},
            {"label": "5 小时", "usedPercent": 10, "resetsAt": null},
        ]}});
        times(&mut v, c);
        assert_eq!(v["time"]["createdAt"]["ago"], "3 分钟前");
        let w = &v["quota"]["windows"];
        assert_eq!((w[0]["mark"].as_str(), w[1]["mark"].as_str(), w[1]["level"].as_str(), w[1]["refills"].as_str()), (Some("5H"), Some("W"), Some("red"), Some("1 小时 5 分钟后刷新")));
        // Mentions by name; a person as the workspace knows them, 你 for the viewer.
        let members = [json!({"email": "a@x.com", "name": "阿一", "picture": "https://p/a"})];
        assert_eq!(mentions("<@UBOT> 和 <@U9> 看下", &[("UBOT".into(), "ds-ember".into())], &members), "@ds-ember 和 @U9 看下");
        let mut me = json!({"id": "a@x.com", "email": "a@x.com", "name": "A"});
        person(&mut me, &json!({"id": "a@x.com", "email": "a@x.com"}), &members);
        assert_eq!(me["shown"], json!({"name": "阿一", "display": "你", "picture": "https://p/a", "mine": true}));
        // A machine in words.
        let mut h = json!({"hostname": "studio", "os": "macOS 26", "arch": "arm64", "cpus": 8, "load": 0.5, "uptimeSec": 90_000,
            "memory": {"usedBytes": 8.0 * 1024f64.powi(3), "totalBytes": 32.0 * 1024f64.powi(3), "swapUsedBytes": null},
            "disk": {"totalBytes": 1000.0 * 1024f64.powi(3), "freeBytes": 50.0 * 1024f64.powi(3)}, "emberRssBytes": 100.0 * 1024f64.powi(2)});
        host(&mut h);
        assert!(h["meters"][0]["percent"].is_i64() && v["quota"]["windows"][0]["left"].is_i64(), "whole numbers: clients read them as such");
        assert_eq!((h["summary"].as_str(), h["facts"][3].as_str()), (Some("8 核 · 32 GB"), Some("已运行 1 天 1 小时")));
        assert_eq!((h["meters"][0]["label"].as_str(), h["meters"][0]["value"].as_str()), (Some("CPU 负载"), Some("50%")), "a station before cpuBusy: the load");
        h["cpuBusy"] = json!(0.93);
        h["cpuModel"] = json!("Apple M2 Max");
        host(&mut h);
        let cpu = &h["meters"][0];
        assert_eq!((cpu["label"].as_str(), cpu["percent"].as_i64(), cpu["level"].as_str(), cpu["value"].as_str(), cpu["note"].as_str()),
            (Some("CPU"), Some(93), Some("red"), Some("93%"), Some("负载 4.0 · Apple M2 Max")));
                assert_eq!((h["meters"][2]["level"].as_str(), h["meters"][2]["value"].as_str(), h["emberText"].as_str()), (Some("red"), Some("剩 50.0 GB / 1000 GB"), Some("still.fail 100 MB")));
    }


    #[test]
    fn a_watching_chat_says_what_it_watches_and_what_archiving_it_means() {
        let agent = |watch: Value| json!({"key": "a", "watch": watch});
        assert_eq!(row_watch(&[json!({"key": "a"})]), None);
        let marked = row_watch(&[agent(json!({"names": ["盯 CI"], "since": 0, "at": 1})), json!({"key": "b"}), agent(json!({"names": ["relay 延迟"], "since": 0, "at": 0}))]).unwrap();
        assert_eq!(marked, json!({"text": "监控中：盯 CI、relay 延迟", "ask": "「盯 CI」、「relay 延迟」还在监控。归档后它照常运行，有新消息时对话会回到列表。"}));
    }
}

/// Posts worth concentrating on at the end of a chat. Read receipts do not dismiss a final result.
pub fn focus_message(message: &Value) -> bool {
    if message["authorKind"] != "agent" || message["system"] == true { return false; }
    let ending = message.get("ending").and_then(Value::as_str)
        .or_else(|| message.get("declared").and_then(Value::as_str));
    if matches!(ending, Some("all_done" | "final")) { return true; }
    if message["decision"]["resolved"] == true || message["decision"]["dismissed"] == true { return false; }
    matches!(ending, Some("need_human" | "need_help" | "need_decision" | "block"))
        || message.get("decision").is_some_and(|d| d["resolved"] == false)
}

#[test]
fn focus_message_results_and_pending_requests() {
    for ending in ["all_done", "need_human", "need_help", "need_decision"] {
        assert!(focus_message(&json!({"authorKind":"agent", "ending":ending})));
    }
    assert!(focus_message(&json!({"authorKind":"agent", "declared":"final"})));
    assert!(focus_message(&json!({"authorKind":"agent", "decision":{"resolved":false}})));
    for message in [
        json!({"authorKind":"person", "ending":"all_done"}),
        json!({"authorKind":"agent"}),
        json!({"authorKind":"agent", "ending":"waiting"}),
        json!({"authorKind":"agent", "ending":"need_human", "decision":{"resolved":true}}),
        json!({"authorKind":"agent", "ending":"need_human", "decision":{"resolved":false,"dismissed":true}}),
    ] { assert!(!focus_message(&message), "{message}"); }
}

#[test]
fn alert_capacity_is_remaining_while_its_edge_is_used_percent() {
    let gib = 1024f64.powi(3);
    let mut h = json!({"memory":{"usedBytes":5.3*gib,"totalBytes":6.0*gib},"disk":{"freeBytes":6.0*gib,"totalBytes":60.0*gib}});
    host(&mut h);
    assert_eq!(h["meters"][1]["remaining"], "剩余 0.7 G");
    assert_eq!(h["meters"][1]["percent"], 88);
    assert_eq!(h["meters"][2]["remaining"], "剩余 6.0 G");
    assert_eq!(h["meters"][2]["percent"], 90);
    h["memory"]["usedBytes"] = json!(7.0*gib);
    host(&mut h);
    assert_eq!(h["meters"][1]["remaining"], "剩余 0.0 G");
}
