//! A chat's pieces of work as its viewer sees them (the `items` of a station's rows: agents declare them with
//! chat_post): which wait on the viewer and which only on others, the order its page shows those waiting one at a
//! time (`asks`), the row's second line and mark, and the answers each card offers. An answer is a message from the
//! viewer in the chat, 「<title>」<answer> (`item.answer`); setting one aside (待定, `item.defer`) is the viewer's own,
//! kept on the device with the prefs (prefs.rs `defer`) by station, chat and key, for the request it was set aside at
//! (its `evidence`): asked again, it is not set aside.

use std::collections::HashMap;

use serde_json::{Value, json};

use crate::present::Clock;

/// Who is looking, as the rows name people: their account (`me`), the Slack users they said are them, the
/// workspace's people (for names).
pub struct Viewer<'a> {
    pub me: &'a Value,
    pub slack_users: &'a [String],
    pub members: &'a [Value],
}

/// The pieces of work of a chat the viewer set aside: by key, the request it was set aside at (its evidence) and when.
pub type Deferred = HashMap<String, (Option<i64>, f64)>;

/// Where a deferral is kept in the prefs (`deferred`): its station, chat (the row's session) and key.
pub fn deferral_key(station: &str, session: &str, key: &str) -> String {
    format!("{station}\t{session}\t{key}")
}

/// A chat's deferrals, as the prefs keep them.
pub fn deferred_of(prefs: &Value, station: &str, session: &str) -> Deferred {
    kept_of(prefs, "deferred", station, session)
}

/// A chat's pieces of work the viewer answered here (`item.answer`), by key, at the request they answered (as
/// deferrals are kept): theirs is said, so to them it is the agent's again until it is declared anew.
pub fn answered_of(prefs: &Value, station: &str, session: &str) -> Deferred {
    kept_of(prefs, "answered", station, session)
}

fn kept_of(prefs: &Value, field: &str, station: &str, session: &str) -> Deferred {
    let prefix = deferral_key(station, session, "");
    prefs.get(field).and_then(Value::as_object).into_iter().flatten()
        .filter_map(|(k, v)| Some((k.strip_prefix(&prefix)?.to_string(), (v.get("evidence").and_then(Value::as_i64), v.get("at").and_then(Value::as_f64).unwrap_or(0.0)))))
        .collect()
}

/// Whether a person (`{id, email, via}`, as a row's people are) is the viewer: by id or email, or as a Slack user they
/// said is them (`slack:<connect>:<user>`).
pub fn is_me(person: &Value, me: &Value, slack_users: &[String]) -> bool {
    let id = person.get("id").and_then(Value::as_str).unwrap_or("");
    let email = person.get("email").and_then(Value::as_str).filter(|e| !e.is_empty());
    let slack_user = id.strip_prefix("slack:").and_then(|rest| rest.rsplit_once(':')).map(|(_, user)| user);
    (!id.is_empty() && crate::present::is_viewer(me, id, slack_users))
        || email.is_some_and(|e| crate::present::is_viewer(me, e, &[]))
        || slack_user.is_some_and(|u| slack_users.iter().any(|s| s == u))
}

fn items(row: &Value) -> Vec<Value> {
    row.get("items").and_then(Value::as_array).cloned().unwrap_or_default()
}

fn waits(item: &Value) -> bool {
    item.get("state").and_then(Value::as_str) == Some("waiting")
}

fn waiting_on(item: &Value) -> Vec<Value> {
    item.get("waitingOn").and_then(Value::as_array).cloned().unwrap_or_default().into_iter().filter(Value::is_object).collect()
}

fn waits_on_me(item: &Value, me: &Value, slack_users: &[String]) -> bool {
    waits(item) && waiting_on(item).iter().any(|p| is_me(p, me, slack_users))
}

/// A row's pieces of work waiting on the viewer, as the station has them: each its key, title and evidence.
pub fn waiting_on_me(row: &Value, me: &Value, slack_users: &[String]) -> Vec<(String, String, Option<i64>)> {
    items(row).iter().filter(|it| waits_on_me(it, me, slack_users)).map(|it| {
        let text = |k: &str| it.get(k).and_then(Value::as_str).unwrap_or("").to_string();
        (text("key"), text("title"), it.get("evidence").and_then(Value::as_i64))
    }).collect()
}

/// What a piece of work asks, as the shapes have it: a word for yes and answers to pick, each said; none for a plain yes.
fn ask_of(item: &Value) -> Value {
    let ask = item.get("ask").filter(|a| a.is_object());
    let label = ask.and_then(|a| a.get("label")).and_then(Value::as_str).map(str::trim).filter(|l| !l.is_empty());
    let options: Vec<&str> = ask.and_then(|a| a.get("options")).and_then(Value::as_array).into_iter().flatten()
        .filter_map(Value::as_str).map(str::trim).filter(|o| !o.is_empty()).collect();
    let question = ask.and_then(|a| a.get("question")).and_then(Value::as_str).map(str::trim).filter(|q| !q.is_empty());
    if question.is_none() && label.is_none() && options.is_empty() {
        return Value::Null;
    }
    json!({ "question": question, "label": label, "options": (!options.is_empty()).then_some(options) })
}

/// The answers a card offers while it waits, the same whoever it waits on (anyone may answer): yes (准, or the
/// agent's word), the agent's options, 随便, 待定. Anything else is said in the composer.
fn answers(title: &str, ask: &Value) -> Vec<Value> {
    let said = |answer: &str| json!(format!("「{title}」{answer}"));
    let yes = ask.get("label").and_then(Value::as_str).unwrap_or("准");
    let mut out = vec![json!({ "label": yes, "kind": "yes", "text": said(yes) })];
    for option in ask.get("options").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str) {
        out.push(json!({ "label": option, "kind": "option", "text": said(option) }));
    }
    out.push(json!({ "label": "随便", "kind": "delegate", "text": said("随便") }));
    out.push(json!({ "label": "待定", "kind": "defer" }));
    out
}

/// Names in a line: 王磊; 王磊、小李; 王磊 等 3 人.
fn names_said(names: &[String]) -> String {
    match names {
        [] => "别人".to_string(),
        [one] => one.clone(),
        [a, b] => format!("{a}、{b}"),
        [a, ..] => format!("{a} 等 {} 人", names.len()),
    }
}

/// A piece of work as the clients show it (`WorkItem`): what the station keeps of it, each person named, and for the
/// viewer whether it waits on them, whether they set it aside, its card's lines and answers.
fn shown(item: &Value, viewer: &Viewer, deferred: &Deferred, answered: &Deferred, c: Clock) -> Value {
    let text = |k: &str| item.get(k).and_then(Value::as_str).unwrap_or("").to_string();
    let title = text("title");
    let people: Vec<Value> = waiting_on(item).into_iter().map(|p| {
        let mut p = json!({ "id": p.get("id").and_then(Value::as_str).unwrap_or(""), "name": p.get("name").and_then(Value::as_str).unwrap_or(""),
            "email": p.get("email").and_then(Value::as_str), "via": p.get("via").and_then(Value::as_str).unwrap_or("cloud") });
        crate::present::person(&mut p, viewer.me, viewer.members);
        if is_me(&p, viewer.me, viewer.slack_users) {
            p["shown"]["mine"] = json!(true);
            p["shown"]["display"] = json!("你");
        }
        p
    }).collect();
    let evidence = item.get("evidence").and_then(Value::as_i64);
    // Answered here at the request it waits with: the agent's to take up, not the viewer's to answer again.
    // Or by anyone, as its station says (`answered`): the same on every device.
    let taken = waits(item)
        && (item.get("answered").and_then(Value::as_bool) == Some(true) || answered.get(&text("key")).is_some_and(|(at, _)| *at == evidence));
    let waiting = waits(item) && !taken;
    let mine = waiting && people.iter().any(|p| p["shown"]["mine"] == true);
    let others: Vec<String> = people.iter().filter(|p| p["shown"]["mine"] != true).map(|p| p["shown"]["display"].as_str().unwrap_or("").to_string()).collect();
    let key = text("key");
    let set_aside = waiting && deferred.get(&key).is_some_and(|(at, _)| *at == evidence);
    let ask = ask_of(item);
    let lead = match (waiting, mine) {
        (false, _) => String::new(),
        (true, true) => "奏".to_string(),
        (true, false) if others.is_empty() => "等人决定".to_string(),
        (true, false) => format!("等{}决定", others.join("、")),
    };
    let updated = item.get("updatedAt").and_then(Value::as_i64).unwrap_or(0);
    let detail = item.get("detail").and_then(Value::as_str).map(str::trim).filter(|d| !d.is_empty());
    let when = (updated > 0).then(|| crate::format::relative_time(updated as f64, c.now, c.offset_min));
    let line = detail.map(str::to_string).into_iter().chain(when).collect::<Vec<_>>().join(" · ");
    // Its card: the question in front, and over it one quiet line, whose, what it is and since when (奏 · 设置页间距 ·
    // 3 分钟前); not its detail (a branch, a commit: the agent's, the question says what matters of it).
    let question = ask.get("question").and_then(Value::as_str).map(str::to_string).unwrap_or_else(|| title.clone());
    let since = (updated > 0).then(|| crate::format::relative_time(updated as f64, c.now, c.offset_min)).unwrap_or_default();
    let head = [lead.as_str(), title.as_str(), since.as_str()].into_iter().filter(|s| !s.is_empty()).collect::<Vec<_>>().join(" · ");
    json!({
        "key": key,
        "session": text("session"),
        "title": title,
        "state": if taken { "working".to_string() } else { text("state") },
        "waitingOn": if waiting { people } else { Vec::new() },
        "ask": ask,
        "detail": detail,
        "evidence": evidence,
        "createdAt": item.get("createdAt").and_then(Value::as_i64).unwrap_or(0),
        "updatedAt": updated,
        "mine": mine,
        "deferred": set_aside.then_some(true),
        "lead": lead,
        "line": line,
        "question": question,
        "head": head,
        "answers": if waiting { answers(&title, &ask) } else { Vec::new() },
    })
}

/// A row's mark, the most urgent first: alert (blocked or failed), wait (something waits on the viewer), busy (at
/// work), done (something unread), other (something waits only on others); none otherwise. Its `state` is the row's
/// (present.rs `row_state`).
pub fn tone(row: &Value, mine: usize, others: usize) -> Option<&'static str> {
    let state = row.get("state").and_then(Value::as_str);
    if matches!(state, Some("block" | "failed")) {
        return Some("alert");
    }
    if mine > 0 {
        return Some("wait");
    }
    if state == Some("run") {
        return Some("busy");
    }
    if row.get("unread").and_then(Value::as_bool) == Some(true) {
        return Some("done");
    }
    (others > 0).then_some("other")
}

/// Puts in a row what the clients show of its pieces of work (`ChatItem`): `items` each as shown, `asks` (those
/// waiting, in the order its page shows them: on the viewer, then only on others, each with those set aside last, the
/// one set aside latest last), `waiting` (its second line), `tone`, and `settled` when all are done or dropped and
/// nothing else marks it. A row with none has only its tone.
pub fn present(row: &mut Value, viewer: &Viewer, deferred: &Deferred, answered: &Deferred, c: Clock) {
    let raw = items(row);
    if raw.is_empty() {
        if let Some(map) = row.as_object_mut() {
            map.remove("items");
        }
        if let Some(tone) = tone(row, 0, 0) {
            row["tone"] = json!(tone);
        }
        return;
    }
    let shown: Vec<Value> = raw.iter().map(|it| shown(it, viewer, deferred, answered, c)).collect();
    let set_aside_at = |it: &Value| deferred.get(it["key"].as_str().unwrap_or("")).filter(|_| it["deferred"] == true).map(|(_, at)| *at).unwrap_or(0.0);
    let mut asks: Vec<&Value> = shown.iter().filter(|it| it["state"] == "waiting").collect();
    // Stable: those not set aside keep the station's order (oldest first).
    asks.sort_by(|a, b| {
        let rank = |it: &Value| (it["mine"] != true, it["deferred"] == true);
        rank(a).cmp(&rank(b)).then(set_aside_at(a).total_cmp(&set_aside_at(b)))
    });
    let mine = asks.iter().filter(|it| it["mine"] == true).count();
    let others = asks.len() - mine;
    let tone = tone(row, mine, others);
    if let Some(first) = asks.first() {
        let title = first["title"].as_str().unwrap_or("");
        // Who an item waits on besides the viewer, by name.
        let names_of = |items: &[&Value]| {
            let mut names: Vec<String> = Vec::new();
            for it in items {
                for p in it["waitingOn"].as_array().into_iter().flatten().filter(|p| p["shown"]["mine"] != true) {
                    let name = p["shown"]["display"].as_str().unwrap_or("").to_string();
                    if !names.contains(&name) {
                        names.push(name);
                    }
                }
            }
            names
        };
        let mut parts = Vec::new();
        if mine > 0 {
            parts.push("奏".to_string());
            parts.push(title.to_string());
            if mine > 1 {
                parts.push(format!("另 {} 件", mine - 1));
            }
            if others > 0 {
                let theirs: Vec<&Value> = asks[mine..].to_vec();
                let more = if mine > 1 { "" } else { "另 " };
                parts.push(format!("{more}{others} 件等{}", names_said(&names_of(&theirs))));
            }
        } else {
            parts.push(format!("等{}", names_said(&names_of(&asks[..1]))));
            parts.push(title.to_string());
            if others > 1 {
                parts.push(format!("另 {} 件等{}", others - 1, names_said(&names_of(&asks[1..]))));
            }
        }
        row["waiting"] = json!({ "mine": mine, "others": others, "text": parts.join(" · ") });
        row["asks"] = json!(asks);
    }
    let closed = shown.iter().all(|it| matches!(it["state"].as_str(), Some("done" | "dropped")));
    if closed && tone.is_none() {
        row["settled"] = json!(true);
    }
    if let Some(tone) = tone {
        row["tone"] = json!(tone);
    }
    row["items"] = json!(shown);
}

/// The row a piece of work is in, among a station's rows: the chat whose session (or id) is `session`, else the one
/// whose item `key` was declared by `session`. Answers the row's session (what its deferrals go by), its thread, and
/// the item as the station has it.
pub fn find(rows: &Value, session: &str, key: &str) -> Option<(String, Option<u64>, Value)> {
    let rows = rows.as_array()?;
    let item_in = |row: &Value| items(row).into_iter().find(|it| it.get("key").and_then(Value::as_str) == Some(key));
    let row = rows.iter().find(|r| (r.get("session").and_then(Value::as_str) == Some(session) || r.get("id").and_then(Value::as_str) == Some(session)) && item_in(r).is_some())
        .or_else(|| rows.iter().find(|r| item_in(r).is_some_and(|it| it.get("session").and_then(Value::as_str) == Some(session))))?;
    let row_session = row.get("session").or_else(|| row.get("id")).and_then(Value::as_str).unwrap_or(session).to_string();
    Some((row_session, row.get("thread").and_then(Value::as_u64), item_in(row)?))
}

#[cfg(test)]
mod tests {
    use super::*;

    const MIN: i64 = 60_000;
    const NOW: i64 = 100 * MIN;

    fn clock() -> Clock {
        Clock { now: NOW as f64, offset_min: 0 }
    }

    fn person(email: &str, name: &str) -> Value {
        json!({ "id": email, "name": name, "email": email, "via": "cloud" })
    }

    fn me() -> Value {
        json!({ "id": "me@x.y", "email": "me@x.y" })
    }

    fn item(key: &str, state: &str, on: &[Value]) -> Value {
        json!({ "key": key, "session": "s1", "title": format!("活{key}"), "state": state, "waitingOn": on, "ask": null, "detail": null,
            "evidence": 4, "createdAt": NOW - 10 * MIN, "updatedAt": NOW - 3 * MIN })
    }

    fn row(items: Vec<Value>) -> Value {
        json!({ "id": "s1", "session": "s1", "thread": 7, "state": null, "unread": false, "items": items })
    }

    fn shown_row(mut r: Value, deferred: &Deferred) -> Value {
        let (me, members) = (me(), vec![json!({ "email": "wl@x.y", "name": "王磊" })]);
        let slack = vec!["U9".to_string()];
        present(&mut r, &Viewer { me: &me, slack_users: &slack, members: &members }, deferred, &Deferred::new(), clock());
        r
    }

    fn keys(list: &Value) -> Vec<&str> {
        list.as_array().unwrap().iter().map(|i| i["key"].as_str().unwrap()).collect()
    }

    #[test]
    fn what_waits_on_the_viewer_comes_first_and_says_so() {
        let (wl, xl, mine) = (person("wl@x.y", "wl"), person("xl@x.y", "小李"), person("ME@x.y", "我"));
        let r = shown_row(row(vec![item("a", "waiting", &[wl.clone()]), item("b", "waiting", &[mine.clone()]), item("c", "working", &[]), item("d", "waiting", &[mine.clone(), xl.clone()])]), &Deferred::new());
        assert_eq!(keys(&r["asks"]), ["b", "d", "a"]);
        assert_eq!(r["waiting"], json!({ "mine": 2, "others": 1, "text": "奏 · 活b · 另 1 件 · 1 件等王磊" }));
        assert_eq!(r["tone"], "wait");
        assert_eq!(r["asks"][0]["lead"], "奏");
        assert_eq!(r["asks"][0]["line"], "3 分钟前");
        assert_eq!(r["asks"][2]["lead"], "等王磊决定", "named as the workspace knows them");
        assert_eq!(r["asks"][2]["mine"], false);
        assert_eq!(r["items"].as_array().unwrap().len(), 4);
        assert_eq!(r["items"][2]["answers"], json!([]), "only one waiting offers answers");
        assert_eq!(r.get("settled"), None);
        // As the clients are given them.
        for it in r["items"].as_array().unwrap().iter().chain(r["asks"].as_array().unwrap()) {
            stillfail_shapes::conform::<stillfail_shapes::WorkItem>(it.clone()).unwrap();
        }
        stillfail_shapes::conform::<stillfail_shapes::RowWaiting>(r["waiting"].clone()).unwrap();
        // One on the viewer and one on someone else.
        let r = shown_row(row(vec![item("a", "waiting", &[wl.clone()]), item("b", "waiting", &[mine.clone()])]), &Deferred::new());
        assert_eq!(r["waiting"]["text"], "奏 · 活b · 另 1 件等王磊");
        // Only on others.
        let r = shown_row(row(vec![item("a", "waiting", &[wl.clone(), xl.clone()]), item("b", "waiting", &[xl.clone()]), item("c", "waiting", &[wl.clone()])]), &Deferred::new());
        assert_eq!(r["waiting"], json!({ "mine": 0, "others": 3, "text": "等王磊、小李 · 活a · 另 2 件等小李、王磊" }));
        assert_eq!(r["asks"][0]["lead"], "等王磊、小李决定");
        assert_eq!(r["tone"], "other");
        let r = shown_row(row(vec![item("a", "waiting", &[wl.clone()])]), &Deferred::new());
        assert_eq!(r["waiting"]["text"], "等王磊 · 活a");
        // A Slack user the viewer said is them is the viewer.
        let slack = json!({ "id": "slack:ds:U9", "name": "zz", "email": null, "via": "slack" });
        let r = shown_row(row(vec![item("a", "waiting", &[slack])]), &Deferred::new());
        assert_eq!((r["asks"][0]["mine"].clone(), r["asks"][0]["waitingOn"][0]["shown"]["display"].clone()), (json!(true), json!("你")));
    }

    #[test]
    fn answered_here_is_the_agents_again_until_declared_anew() {
        let mine = person("me@x.y", "我");
        let me = json!({ "id": "me@x.y", "email": "me@x.y" });
        let (slack, members): (Vec<String>, Vec<Value>) = (vec![], vec![]);
        let items = vec![item("a", "waiting", &[mine.clone()]), item("b", "waiting", &[mine.clone()])];
        let answered: Deferred = [("a".to_string(), (Some(4), 1.0))].into();
        let mut r = row(items.clone());
        present(&mut r, &Viewer { me: &me, slack_users: &slack, members: &members }, &Deferred::new(), &answered, clock());
        assert_eq!(keys(&r["asks"]), ["b"]);
        assert_eq!(r["waiting"]["mine"], 1);
        assert_eq!(r["items"][0]["state"], "working");
        // Answered by anyone, on any device: its station says so.
        let mut elsewhere = items.clone();
        elsewhere[1]["answered"] = json!(true);
        let mut r = row(elsewhere);
        present(&mut r, &Viewer { me: &me, slack_users: &slack, members: &members }, &Deferred::new(), &Deferred::new(), clock());
        assert_eq!(keys(&r["asks"]), ["a"]);
        // Asked again: waiting on the viewer once more.
        let mut again = items;
        again[0]["evidence"] = json!(9);
        let mut r = row(again);
        present(&mut r, &Viewer { me: &me, slack_users: &slack, members: &members }, &Deferred::new(), &answered, clock());
        assert_eq!(keys(&r["asks"]), ["a", "b"]);
    }

    #[test]
    fn set_aside_goes_last_and_still_waits_until_asked_again() {
        let mine = person("me@x.y", "我");
        let wl = person("wl@x.y", "王磊");
        let items = vec![item("a", "waiting", &[mine.clone()]), item("b", "waiting", &[mine.clone()]), item("c", "waiting", &[mine.clone()]), item("d", "waiting", &[wl.clone()])];
        let deferred: Deferred = [("a".to_string(), (Some(4), 2.0)), ("b".to_string(), (Some(4), 1.0))].into();
        let r = shown_row(row(items.clone()), &deferred);
        assert_eq!(keys(&r["asks"]), ["c", "b", "a", "d"], "the latest set aside last, before what waits on others");
        assert_eq!(r["asks"][1]["deferred"], true);
        assert_eq!(r["asks"][0]["deferred"], Value::Null);
        assert_eq!(r["waiting"]["mine"], 3, "set aside, it still waits on the viewer");
        assert_eq!(r["tone"], "wait");
        // Asked again (another entry declared it): not set aside.
        let mut again = items.clone();
        again[0]["evidence"] = json!(9);
        let r = shown_row(row(again), &deferred);
        assert_eq!(keys(&r["asks"]), ["a", "c", "b", "d"]);
        // All of the viewer's set aside: the first set aside leads the line.
        let deferred: Deferred = [("a", 2.0), ("b", 1.0), ("c", 3.0)].into_iter().map(|(k, at)| (k.to_string(), (Some(4), at))).collect();
        let r = shown_row(row(items), &deferred);
        assert_eq!(r["waiting"]["text"], "奏 · 活b · 另 2 件 · 1 件等王磊");
    }

    #[test]
    fn a_chat_whose_work_is_all_done_is_settled_unless_something_else_marks_it() {
        let r = shown_row(row(vec![item("a", "done", &[]), item("b", "dropped", &[])]), &Deferred::new());
        assert_eq!((r["settled"].clone(), r.get("tone"), r.get("asks"), r.get("waiting")), (json!(true), None, None, None));
        let mut unread = row(vec![item("a", "done", &[])]);
        unread["unread"] = json!(true);
        let r = shown_row(unread, &Deferred::new());
        assert_eq!((r.get("settled"), r["tone"].clone()), (None, json!("done")));
        let mut running = row(vec![item("a", "done", &[])]);
        running["state"] = json!("run");
        assert_eq!(shown_row(running, &Deferred::new()).get("settled"), None);
        let r = shown_row(row(vec![item("a", "done", &[]), item("b", "working", &[])]), &Deferred::new());
        assert_eq!(r.get("settled"), None);
        // None at all: not settled, and no items said.
        let r = shown_row(row(vec![]), &Deferred::new());
        assert_eq!((r.get("settled"), r.get("items")), (None, None));
    }

    #[test]
    fn a_rows_mark_is_its_most_urgent() {
        let r = |state: Value, unread: bool| json!({ "state": state, "unread": unread });
        assert_eq!(tone(&r(json!("block"), true), 1, 1), Some("alert"));
        assert_eq!(tone(&r(json!("failed"), false), 0, 0), Some("alert"));
        assert_eq!(tone(&r(json!("run"), true), 1, 0), Some("wait"));
        assert_eq!(tone(&r(json!("run"), true), 0, 1), Some("busy"));
        assert_eq!(tone(&r(Value::Null, true), 0, 1), Some("done"));
        assert_eq!(tone(&r(Value::Null, false), 0, 1), Some("other"));
        assert_eq!(tone(&r(Value::Null, false), 0, 0), None);
    }

    #[test]
    fn a_card_offers_answers_as_messages() {
        let (mine, wl, xl) = (person("me@x.y", "我"), person("wl@x.y", "王磊"), person("xl@x.y", "小李"));
        let mut asked = item("x", "waiting", &[mine.clone()]);
        asked["title"] = json!("设置页间距");
        let r = shown_row(row(vec![asked.clone()]), &Deferred::new());
        let said = |r: &Value| r["asks"][0]["answers"].as_array().unwrap().iter().map(|a| (a["label"].as_str().unwrap().to_string(), a["kind"].as_str().unwrap().to_string(), a["text"].as_str().map(str::to_string))).collect::<Vec<_>>();
        let a = |label: &str, kind: &str, text: Option<&str>| (label.to_string(), kind.to_string(), text.map(str::to_string));
        assert_eq!(said(&r), [
            a("准", "yes", Some("「设置页间距」准")), a("随便", "delegate", Some("「设置页间距」随便")), a("待定", "defer", None),
        ]);
        // In the agent's words, with answers to pick.
        asked["ask"] = json!({ "question": " 间距这样改，合吗？ ", "label": " 合并 ", "options": ["先上线", 3, ""], "other": 1 });
        let r = shown_row(row(vec![asked.clone()]), &Deferred::new());
        assert_eq!(r["asks"][0]["ask"], json!({ "question": "间距这样改，合吗？", "label": "合并", "options": ["先上线"] }));
        assert_eq!(r["asks"][0]["question"], "间距这样改，合吗？");
        assert_eq!(said(&r)[..2], [a("合并", "yes", Some("「设置页间距」合并")), a("先上线", "option", Some("「设置页间距」先上线"))]);
        // Waiting on others: the same answers, anyone may give them.
        asked["waitingOn"] = json!([wl.clone()]);
        asked["ask"] = Value::Null;
        asked["detail"] = json!("分支 settings-gap");
        let r = shown_row(row(vec![asked.clone()]), &Deferred::new());
        assert_eq!(said(&r), [a("准", "yes", Some("「设置页间距」准")), a("随便", "delegate", Some("「设置页间距」随便")), a("待定", "defer", None)]);
        assert_eq!(r["asks"][0]["line"], "分支 settings-gap · 3 分钟前");
        assert_eq!(r["asks"][0]["question"], "设置页间距", "no question from the agent: its title");
        assert_eq!(r["asks"][0]["head"], "等王磊决定 · 设置页间距 · 3 分钟前");
    }

    #[test]
    fn deferrals_are_kept_by_station_chat_and_key() {
        let prefs = json!({ "deferred": {
            deferral_key("w/st", "s1", "a"): { "evidence": 4, "at": 5.0 },
            deferral_key("w/st", "s2", "b"): { "evidence": null, "at": 6.0 },
        } });
        assert_eq!(deferred_of(&prefs, "w/st", "s1"), [("a".to_string(), (Some(4), 5.0))].into());
        assert_eq!(deferred_of(&prefs, "w/st", "s2"), [("b".to_string(), (None, 6.0))].into());
        assert!(deferred_of(&prefs, "w/other", "s1").is_empty());
        assert!(deferred_of(&Value::Null, "w/st", "s1").is_empty());
    }

    #[test]
    fn an_item_is_found_by_its_chat_or_the_agent_that_declared_it() {
        let mut other = row(vec![item("a", "waiting", &[])]);
        other["id"] = json!("s0");
        other["session"] = json!("s0");
        other["thread"] = json!(3);
        other["items"][0]["session"] = json!("s5");
        let rows = json!([other, row(vec![item("a", "waiting", &[])])]);
        let (session, thread, it) = find(&rows, "s1", "a").unwrap();
        assert_eq!((session.as_str(), thread, it["key"].as_str()), ("s1", Some(7), Some("a")));
        assert_eq!(find(&rows, "s5", "a").map(|f| (f.0, f.1)), Some(("s0".to_string(), Some(3))));
        assert!(find(&rows, "s1", "nope").is_none());
    }
}
