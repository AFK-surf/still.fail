//! What the clients show of sessions and sidebar rows, decided here once:
//! where a session stands, a row's state, and who said a row's last thing
//! (with that agent's state on its picture). Clients draw these; they do not
//! work them out.

use serde_json::{Value, json};

use crate::format;
use crate::protocol::Topic;

/// Where a session stands: running (also while it waits on work it started, which brings it back), queued, final,
/// block, failed, aborted, unexpected (a turn that ended without saying final or block, or was left open by a crash),
/// or idle.
pub fn session_status(s: &Value) -> &'static str {
    if s.get("process").and_then(Value::as_str) == Some("running") {
        return "running";
    }
    if s.get("pending").and_then(Value::as_u64).unwrap_or(0) > 0 {
        return "queued";
    }
    let Some(turn) = s.get("lastTurn").filter(|t| t.is_object()) else { return "idle" };
    match turn.get("declared").and_then(Value::as_str) {
        Some("final") => return "final",
        Some("block") => return "block",
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
    let since = turn.filter(|t| t.get("declared").and_then(Value::as_str) == Some("waiting")).and_then(|t| t.get("endedAt")).and_then(Value::as_i64);
    match since {
        Some(since) if session_status(s) == "running" && s.get("process").and_then(Value::as_str) != Some("running") => {
            json!({ "since": since, "seconds": turn.and_then(|t| t.get("waitSeconds")).cloned().unwrap_or(Value::Null) })
        }
        _ => Value::Null,
    }
}

/// A status as a client's small mark: run (at work), block, failed; none for the rest.
pub fn badge(status: &str) -> Option<&'static str> {
    match status {
        "running" | "queued" => Some("run"),
        "block" => Some("block"),
        "failed" | "unexpected" => Some("failed"),
        _ => None,
    }
}

/// A row's state, from its agents': one that is blocked comes first, then one at work, then one that failed.
pub fn row_state(agents: &[Value]) -> Option<&'static str> {
    let marks: Vec<&str> = agents.iter().filter_map(|a| badge(session_status(a))).collect();
    ["block", "run", "failed"].into_iter().find(|b| marks.contains(b))
}

/// Whether a person (an email, "local", a Slack user id) is the viewer: by id, by email, or as a Slack user the
/// viewer said is them.
pub fn is_viewer(me: &Value, person: &str, slack_users: &[String]) -> bool {
    let id = me.get("id").and_then(Value::as_str);
    let email = me.get("email").and_then(Value::as_str);
    id == Some(person) || email.is_some_and(|e| e.eq_ignore_ascii_case(person)) || slack_users.iter().any(|u| u == person)
}

/// A workspace member's name, by email.
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
/// them: `shown: { name, display, picture, mine }`, `name` as the workspace knows them (本机管理页 for this machine's
/// page), `display` the same but 你 for the viewer.
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
                "state": agent.and_then(|a| badge(session_status(a))),
            })
        }
        "ember" => json!({ "kind": "ember", "name": "still.fail", "mine": false }),
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
        w["left"] = json!((100.0 - used).max(0.0).round() as i64);
        w["level"] = json!(if used >= 90.0 { "red" } else if used >= 70.0 { "amber" } else { "ok" });
        w["refills"] = json!(w.get("resetsAt").and_then(Value::as_f64).map(|at| format::refills_in(at, c.now)));
    }
    list.sort_by_key(|w| w.get("order").and_then(Value::as_u64).unwrap_or(1));
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
    let status = session_status(s);
    let (mut text, tone) = format::status_text(status);
    if !waiting(s).is_null() {
        text = "等待中";
    }
    let fields = s.clone();
    let str_of = |k: &str| fields.get(k).and_then(Value::as_str).map(str::to_string);
    let runtime = str_of("runtime").unwrap_or_else(|| "claude".into());
    let model = str_of("model");
    let title = str_of("title").filter(|t| !t.is_empty())
        .or_else(|| str_of("firstText").map(|t| format::clean_text(&t)).filter(|t| !t.is_empty()))
        .unwrap_or_else(|| "（还没有消息）".into());
    let badge = badge(status);
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
        "block" => "Block：agent 停下来等人处理",
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
    // Its models' makers, by model.
    let found = p.get("check").and_then(|c| c.get("models")).and_then(Value::as_array).cloned().unwrap_or_default();
    let makers: serde_json::Map<String, Value> = p.get("models").and_then(Value::as_array).into_iter().flatten().chain(found.iter())
        .filter_map(Value::as_str).map(|m| (m.to_string(), maker(Some(m)))).collect();
    // How many of the models it could run are enabled, in words.
    let enabled: Vec<&str> = p.get("models").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str).collect();
    let mut all: Vec<&str> = found.iter().filter_map(Value::as_str).chain(enabled.iter().copied()).collect();
    all.sort_unstable();
    all.dedup();
    let text = if all.is_empty() { "还没有列出模型".to_string() } else { format!("已启用 {} / {} 个模型", enabled.len(), all.len()) };
    let by_series = series(&all);
    let names: serde_json::Map<String, Value> = p.get("models").and_then(Value::as_array).into_iter().flatten().chain(found.iter())
        .chain(p.get("model").into_iter())
        .filter_map(Value::as_str).filter(|m| !m.is_empty()).map(|m| (m.to_string(), json!(stillfail_shapes::model::name(m)))).collect();
    p["makers"] = Value::Object(makers);
    p["names"] = Value::Object(names);
    p["series"] = by_series;
    p["modelsText"] = json!(text);
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
    // Its card: what it is, how loaded (each meter coloured by how full), and what ember itself takes.
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
    h["emberText"] = json!(format!("still.fail {} MB", (n(&["emberRssBytes"]) / 1024f64.powi(2)).round()));
}

/// Whether what goes out of a topic shows times in words (sent again each minute).
pub fn ticks(topic: &Topic) -> bool {
    !matches!(topic, Topic::Live { .. } | Topic::Thread { .. } | Topic::History { .. } | Topic::Host { .. } | Topic::Status | Topic::Notices | Topic::Notify | Topic::Draft { .. } | Topic::JobLog { .. })
}

/// A topic's value through the shape the clients are generated from (client/shapes): what it does not declare is
/// dropped, and a value it does not allow (a fractional time, a field missing) is an error naming the field. Topics
/// with no shape yet go as they are.
pub fn conform(topic: &Topic, value: Value) -> Result<Value, String> {
    use stillfail_shapes as s;
    match topic {
        Topic::Chats { .. } => s::conform::<s::ChatsView>(value),
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
        Topic::Status => s::conform::<s::StatusView>(value),
        Topic::Notices => s::conform::<s::NoticesView>(value),
        Topic::Draft { .. } => s::conform::<s::DraftView>(value),
        Topic::Notify => s::conform::<s::NotifyView>(value),
        _ => Ok(value),
    }
}

/// What goes out of a topic, with what the clients show of it put in (see above). The transcript and a thread's
/// pages go as they are: the views that show them put in their own.
pub fn decorate(topic: &Topic, value: &mut Value, c: Clock) {
    match topic {
        Topic::Host { .. } => return host(value),
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
            value.get_mut("connects").and_then(Value::as_array_mut).into_iter().flatten().for_each(connect);
            value.get_mut("profiles").and_then(Value::as_array_mut).into_iter().flatten().for_each(profile);
        }
        _ => {}
    }
    times(value, c);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_session_stands_where_its_process_and_last_turn_say() {
        assert_eq!(session_status(&json!({"process": "running"})), "running");
        assert_eq!(session_status(&json!({"process": "warm", "pending": 1})), "queued");
        assert_eq!(session_status(&json!({"lastTurn": {"declared": "block", "outcome": "completed"}})), "block");
        assert_eq!(session_status(&json!({"process": "warm", "lastTurn": {"declared": "waiting", "outcome": "completed"}})), "running");
        assert_eq!(session_status(&json!({"lastTurn": {"outcome": "completed"}})), "unexpected");
        let waits = json!({"process": "warm", "lastTurn": {"declared": "waiting", "outcome": "completed", "endedAt": 5, "waitSeconds": 600}});
        assert_eq!(waiting(&waits), json!({"since": 5, "seconds": 600}));
        assert_eq!(waiting(&json!({"process": "warm", "lastTurn": {"declared": "waiting", "outcome": "completed", "endedAt": 5}})), json!({"since": 5, "seconds": null}));
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
    fn what_the_clients_show_is_put_in_here() {
        let c = Clock { now: 1_790_467_200_000.0, offset_min: 480 };
        // A session: where it stands in words, its title, label and maker, and its runtime's efforts.
        let mut s = json!({"runtime": "codex", "model": "gpt-6-astra", "effort": "medium", "process": "warm", "lastTurn": {"declared": "block"}, "firstText": "<@U1> 看看 CI"});
        session(&mut s);
        assert_eq!((s["statusText"].as_str(), s["tone"].as_str(), s["badgeText"].as_str()), (Some("Block"), Some("blue"), Some("Block：agent 停下来等人处理")));
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

}
