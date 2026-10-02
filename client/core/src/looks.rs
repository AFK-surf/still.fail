//! What the clients show of the stations and their links, in words and counts, decided here once (as present.rs does
//! for sessions and rows): the stations' glyph and its line, what a list with no rows says instead, how a chat's link is
//! when it is not as it should be, a station's face. Clients draw these; they do not work them out.

use serde_json::{Value, json};
use stillfail_i18n::t;

/// The stations' glyph (web/src/StationGlyph.tsx, Android ui/StationGlyph.kt) from a list's stations and days: each
/// station by its link, and one at work if a chat of it is running; the line beside it while all is well (the one
/// station by name, else how many; and who works), and the whole in words, for what reads it out.
pub fn glyph(stations: &[Value], days: &[Value]) -> Value {
    let state = |s: &Value| s.get("state").and_then(Value::as_str).unwrap_or("").to_string();
    let running: Vec<&str> = days.iter()
        .flat_map(|d| d.get("items").and_then(Value::as_array).into_iter().flatten())
        .filter(|i| i.get("state").and_then(Value::as_str) == Some("run"))
        .filter_map(|i| i.get("station").and_then(Value::as_str))
        .collect();
    let online: Vec<&Value> = stations.iter().filter(|s| state(s) == "online").collect();
    let dim = stations.iter().filter(|s| matches!(state(s).as_str(), "offline" | "connecting")).count();
    // Of the dim, those whose link is on its way (drawn after the online, pulsing); `dim` keeps them for clients before.
    let connecting = stations.iter().filter(|s| state(s) == "connecting").count();
    let failing = stations.iter().filter(|s| state(s) == "error").count();
    let working = online.iter().filter(|s| s.get("station").and_then(Value::as_str).is_some_and(|a| running.contains(&a))).count();
    let n = online.len() + dim + failing;
    let summary = if n == 1 {
        let one = stations[0].get("name").and_then(Value::as_str).filter(|n| !n.is_empty()).map_or_else(|| t!("core-logic.looks.stations", n = 1), str::to_string);
        if working > 0 { t!("core-logic.looks.one_working", name = one) } else { one }
    } else if working > 0 {
        t!("core-logic.looks.stations_working", n = n, working = working)
    } else {
        t!("core-logic.looks.stations", n = n)
    };
    let mut label = vec![t!("core-logic.looks.stations", n = n), t!("core-logic.looks.online", n = online.len())];
    if working > 0 {
        label.push(t!("core-logic.looks.working", n = working));
    }
    if connecting > 0 {
        label.push(t!("core-logic.looks.connecting", n = connecting));
    }
    if dim > connecting {
        label.push(t!("core-logic.looks.offline", n = dim - connecting));
    }
    if failing > 0 {
        label.push(t!("core-logic.looks.failing", n = failing));
    }
    json!({ "online": online.len(), "dim": dim, "connecting": connecting, "failing": failing, "working": working, "summary": summary, "label": label.join(&t!("core-logic.looks.sep")) })
}

/// What a list says with no rows to show, in their place: that it is still reading (a station loading or its link
/// coming back), the stations it cannot reach (each tried again), or that there is nothing. `unread`: the stations
/// whose chats this device has never read; one of them offline is not "no chats", only none known yet.
pub fn list_note(stations: &[Value], days: &[Value], loading: bool, unread: &[String]) -> Value {
    let is = |s: &Value, w: &str| s.get("state").and_then(Value::as_str) == Some(w);
    if !days.is_empty() {
        return json!({ "reading": false, "failing": [], "empty": false });
    }
    let connecting = stations.iter().any(|s| is(s, "connecting"));
    let failing: Vec<Value> = if loading { Vec::new() } else {
        stations.iter().filter(|s| is(s, "error") || (is(s, "offline") && s.get("station").and_then(Value::as_str).is_some_and(|a| unread.iter().any(|u| u == a)))).map(|s| {
            let name = s.get("name").and_then(Value::as_str).unwrap_or("");
            let text = if is(s, "error") { t!("core-logic.looks.failing.retrying", name = name) } else { t!("core-logic.looks.failing.offline", name = name) };
            json!({ "station": s["station"], "text": text, "message": s["message"] })
        }).collect()
    };
    let empty = !loading && !connecting && failing.is_empty();
    // What it waits on, in the pill over the placeholder rows: the stations whose link is on its way (by name for one).
    let on_way: Vec<&str> = stations.iter().filter(|s| is(s, "connecting")).map(|s| s.get("name").and_then(Value::as_str).unwrap_or("")).collect();
    let text = match on_way.as_slice() {
        [] => t!("core-logic.looks.reading"),
        [one] => t!("core-logic.looks.reading.connecting_one", name = one),
        all => t!("core-logic.looks.reading.connecting", n = all.len()),
    };
    json!({ "reading": loading || connecting, "text": text, "failing": failing, "empty": empty })
}

/// A chat's link to its station while it is not as it should be (web/src/Connection.tsx, Android screens/Connection.kt):
/// down (`trouble`, with why, less its own "连不上…：" / "Can't reach …: " the line says already) or coming back (`busy`);
/// null while up.
pub fn link_shown(link: &Value, name: &str) -> Value {
    let said = |key: &str, named: &str| if name.is_empty() { t!(key) } else { t!(named, name = name) };
    match link.get("state").and_then(Value::as_str) {
        Some("offline" | "error") => {
            let why = link.get("message").and_then(Value::as_str).filter(|m| !m.is_empty()).map(|m| match m.split_once('：').or_else(|| m.split_once(": ")) {
                Some((head, rest)) if head.contains("连不上") || head.starts_with("Can't reach") => rest.to_string(),
                _ => m.to_string(),
            });
            json!({ "tone": "trouble", "text": said("core-logic.looks.link.down", "core-logic.looks.link.down.named"), "detail": why })
        }
        Some("reconnecting") => json!({ "tone": "busy", "text": said("core-logic.looks.link.reconnecting", "core-logic.looks.link.reconnecting.named") }),
        _ => Value::Null,
    }
}

/// A station's buddy face: asleep offline, at work while an agent of it runs, else idle.
pub fn face(online: bool, overview: Option<&Value>) -> &'static str {
    let running = overview.and_then(|o| o.get("counts")).and_then(|c| c.get("running")).and_then(Value::as_u64).unwrap_or(0);
    if !online { "offline" } else if running > 0 { "working" } else { "idle" }
}

/// What a station is, under its name on its page: its processor, else whether it is up.
pub fn station_line(online: bool, host: Option<&Value>) -> String {
    host.and_then(|h| h.get("cpuModel")).and_then(Value::as_str).filter(|m| !m.is_empty()).map(str::to_string)
        .unwrap_or_else(|| t!(if online { "core-logic.looks.station.online" } else { "core-logic.looks.station.offline" }))
}

/// A station's answer as the clients show it: the agents' memory (`GET /memory`) with each skill's text as people read
/// it (`body`, without its frontmatter) and when it applies (`about`, a project's without its 项目记忆：).
pub fn answer(method: &str, path: &str, value: &mut Value) {
    if method != "GET" || path != "/memory" {
        return;
    }
    for skill in value.get_mut("skills").and_then(Value::as_array_mut).into_iter().flatten() {
        let text = skill.get("text").and_then(Value::as_str).unwrap_or("");
        let body = match text.strip_prefix("---\n").and_then(|rest| rest.find("\n---").map(|at| &rest[at + 4..])) {
            Some(after) => after.strip_prefix('\n').unwrap_or(after),
            None => text,
        }.trim().to_string();
        let description = skill.get("description").and_then(Value::as_str).unwrap_or("");
        let project = skill.get("project").and_then(Value::as_bool) == Some(true);
        let about = if project { description.strip_prefix("项目记忆：").unwrap_or(description) } else { description }.to_string();
        skill["body"] = json!(body);
        skill["about"] = json!(about);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn station(address: &str, name: &str, state: &str) -> Value {
        json!({ "station": address, "id": address, "name": name, "state": state, "message": null })
    }

    #[test]
    fn the_glyph_counts_stations_by_their_links_and_says_who_works() {
        let stations = [station("w/a", "Studio", "online"), station("w/b", "MBA", "online"), station("w/c", "Pi", "offline"), station("w/d", "X", "error")];
        let days = [json!({ "items": [{ "station": "w/a", "state": "run" }, { "station": "w/c", "state": "run" }, { "station": "w/b", "state": null }] })];
        let g = glyph(&stations, &days);
        assert_eq!((g["online"].as_u64(), g["dim"].as_u64(), g["failing"].as_u64(), g["working"].as_u64()), (Some(2), Some(1), Some(1), Some(1)));
        assert_eq!(g["summary"], "4 台 station · 1 台在干活");
        assert_eq!(g["label"], "4 台 station，2 台在线，1 台在干活，1 台离线，1 台出错");
        // One station goes by its name.
        assert_eq!(glyph(&[station("w/a", "Studio", "online")], &days)["summary"], "Studio · 在干活");
        assert_eq!(glyph(&[], &[])["label"], "0 台 station，0 台在线");
        // A link on its way is still dim, and said apart from the offline.
        let g = glyph(&[station("w/a", "A", "connecting"), station("w/b", "B", "offline")], &[]);
        assert_eq!((g["dim"].as_u64(), g["connecting"].as_u64()), (Some(2), Some(1)));
        assert_eq!(g["label"], "2 台 station，0 台在线，1 台正在连接，1 台离线");
    }

    #[test]
    fn a_list_with_no_rows_says_it_reads_fails_or_has_none() {
        let days = [json!({ "items": [{}] })];
        assert_eq!(list_note(&[station("w/a", "A", "error")], &days, false, &[]), json!({ "reading": false, "failing": [], "empty": false }));
        assert_eq!(list_note(&[station("w/a", "A", "connecting")], &[], false, &[])["text"], "正在连接 A");
        assert_eq!(list_note(&[station("w/a", "A", "connecting"), station("w/b", "B", "connecting")], &[], false, &[])["text"], "正在连接 2 台 station");
        assert_eq!(list_note(&[station("w/a", "A", "online")], &[], true, &[])["text"], "正在读取会话");
        assert_eq!(list_note(&[station("w/a", "A", "online")], &[], true, &[])["reading"], true);
        assert_eq!(list_note(&[station("w/a", "A", "connecting")], &[], false, &[])["reading"], true);
        let failing = list_note(&[station("w/a", "A", "error"), station("w/b", "B", "online")], &[], false, &[]);
        assert_eq!(failing["failing"][0]["text"], "连不上「A」，正在重试…");
        assert_eq!(failing["empty"], false);
        assert_eq!(list_note(&[station("w/b", "B", "online")], &[], false, &[])["empty"], true);
        assert_eq!(list_note(&[], &[], false, &[])["empty"], true);
        // An offline station never read here: its chats are not known, not none.
        let unread = list_note(&[station("w/a", "A", "offline")], &[], false, &["w/a".to_string()]);
        assert_eq!((unread["empty"].as_bool(), unread["failing"][0]["text"].as_str()), (Some(false), Some("A 离线 · 还没读到会话")));
        assert_eq!(list_note(&[station("w/a", "A", "offline")], &[], false, &[])["empty"], true);
    }

    #[test]
    fn a_skill_reads_without_its_frontmatter() {
        let mut memory = json!({ "global": { "path": "g", "text": "x" }, "skills": [
            { "name": "a", "description": "项目记忆：做 a 时", "project": true, "text": "---\nname: a\n---\n\n# A\n" },
            { "name": "b", "description": "别的", "project": false, "text": "no front" },
        ] });
        answer("GET", "/memory", &mut memory);
        assert_eq!((memory["skills"][0]["body"].as_str(), memory["skills"][0]["about"].as_str()), (Some("# A"), Some("做 a 时")));
        assert_eq!((memory["skills"][1]["body"].as_str(), memory["skills"][1]["about"].as_str()), (Some("no front"), Some("别的")));
    }

    #[test]
    fn a_chat_link_is_said_only_while_down_or_coming_back() {
        let down = link_shown(&json!({ "state": "error", "message": "连不上这台 station：超时" }), "Studio");
        assert_eq!(down, json!({ "tone": "trouble", "text": "连不上「Studio」", "detail": "超时" }));
        assert_eq!(link_shown(&json!({ "state": "offline", "message": "别的：原因" }), "")["detail"], "别的：原因");
        assert_eq!(link_shown(&json!({ "state": "offline" }), "")["text"], "连不上 station");
        assert_eq!(link_shown(&json!({ "state": "reconnecting" }), "S"), json!({ "tone": "busy", "text": "正在重连「S」" }));
        assert_eq!(link_shown(&json!({ "state": "online" }), "S"), Value::Null);
        assert_eq!(face(true, Some(&json!({ "counts": { "running": 2 } }))), "working");
        assert_eq!(face(false, Some(&json!({ "counts": { "running": 2 } }))), "offline");
        assert_eq!(station_line(true, Some(&json!({ "cpuModel": "" }))), "在线");
    }
}

/// Kept overview progress survives a handover's disconnected interval. No update is inferred from a disconnect.
pub fn station_update(overview: Option<&Value>, chat: &Value, dismissed: Option<&str>, open: bool, manager: bool) -> Value {
    let Some(update) = overview.and_then(|v| v["updates"].as_array()).and_then(|all| all.iter().find(|v| v["id"] == "station")) else { return Value::Null };
    let offline = chat["link"]["state"].as_str().is_some_and(|s| s != "online");
    if update["state"] == "updating" {
        let sending = chat["outbox"].as_array().is_some_and(|entries| entries.iter().any(|entry| entry["state"] == "sending" && entry["seq"].is_null()));
        let progress = if offline { "正在等待 station 重新连接" } else { update["progress"].as_str().unwrap_or("正在准备新版本") };
        let detail = if sending { format!("{progress}；消息仍在发送，连接恢复后自动继续") } else { progress.to_string() };
        return json!({ "tone": "busy", "label": "更新中", "text": "station 正在更新", "detail": detail, "open": open, "canUpdate": false, "dismissible": false });
    }
    if update["state"] == "failed" {
        return json!({ "tone": "trouble", "label": "更新失败", "text": "station 更新失败", "detail": update["message"].as_str().unwrap_or("可重试更新"), "open": open, "canUpdate": manager && !offline && update["updatable"] == true, "dismissible": false });
    }
    if update["newer"] == true && update["updatable"] == true {
        let version = update["latest"].as_str().map(|v| format!("{}:{v}", update["channel"].as_str().unwrap_or("")));
        if version.as_deref().is_some_and(|v| Some(v) == dismissed) { return Value::Null; }
        let detail = if update["auto"] == true && update["idleOnly"] == true { "空闲时自动更新" } else if manager { "可立即更新" } else { "请管理员更新" };
        return json!({ "tone": "notice", "label": "可更新", "text": "station 有新版本", "detail": detail, "version": version, "open": open, "canUpdate": manager && !offline, "dismissible": version.is_some() });
    }
    Value::Null
}

#[cfg(test)]
mod update_tests {
    use super::*;
    #[test]
    fn update_progress_and_pending_messages_survive_disconnect_and_clear_on_new_overview() {
        let mut overview = json!({"updates": [{"id":"station", "state":"updating", "progress":"正在下载新版本…"}]});
        let mut chat = json!({"link":{"state":"online"}, "outbox":[]});
        assert_eq!(station_update(Some(&overview), &chat, None, false, true)["detail"], "正在下载新版本…");
        chat["link"]["state"] = json!("reconnecting");
        chat["outbox"] = json!([{"id":"one", "state":"sending"}]);
        let notice = station_update(Some(&overview), &chat, None, false, true);
        assert_eq!(notice["text"], "station 正在更新");
        assert!(notice["detail"].as_str().unwrap().contains("消息仍在发送"));
        chat["outbox"][0]["state"] = json!("failed");
        assert!(!station_update(Some(&overview), &chat, None, false, true)["detail"].as_str().unwrap().contains("消息仍在发送"));
        chat["outbox"][0]["state"] = json!("sending");
        chat["outbox"][0]["seq"] = json!(7);
        assert!(!station_update(Some(&overview), &chat, None, false, true)["detail"].as_str().unwrap().contains("消息仍在发送"));
        overview["updates"][0] = json!({"id":"station", "state":"idle", "newer":false});
        assert!(station_update(Some(&overview), &chat, None, false, true).is_null());
        assert!(station_update(None, &chat, None, false, true).is_null(), "older station or unknown reason: never guess updating");
    }
    #[test]
    fn dismissal_is_version_and_channel_scoped_and_never_hides_progress() {
        let mut overview = json!({"updates":[{"id":"station","state":"idle","newer":true,"updatable":true,"latest":"2","channel":"stable"}]});
        assert!(station_update(Some(&overview), &Value::Null, Some("stable:2"), false, true).is_null());
        let next = station_update(Some(&overview), &Value::Null, Some("stable:1"), true, false);
        assert_eq!(next["open"], true);
        assert_eq!(next["canUpdate"], false);
        assert_eq!(next["dismissible"], true);
        assert!(!station_update(Some(&overview), &Value::Null, Some("beta:2"), false, true).is_null());
        overview["updates"][0]["state"] = json!("updating");
        let progress = station_update(Some(&overview), &Value::Null, Some("stable:2"), false, true);
        assert_eq!(progress["label"], "更新中");
        assert_eq!(progress["dismissible"], false);
    }
    #[test]
    fn availability_explains_deferral_only_when_automatic_updates_are_enabled() {
        let mut overview = json!({"updates": [{"id":"station", "state":"idle", "newer":true, "updatable":true, "auto":true, "idleOnly":true}]});
        assert!(station_update(Some(&overview), &Value::Null, None, false, true)["detail"].as_str().unwrap().contains("空闲时自动更新"));
        overview["updates"][0]["auto"] = json!(false);
        assert_eq!(station_update(Some(&overview), &Value::Null, None, false, true)["detail"], "可立即更新");
    }
}
