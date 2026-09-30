//! What the clients show of the stations and their links, in words and counts, decided here once (as present.rs does
//! for sessions and rows): the stations' glyph and its line, what a list with no rows says instead, how a chat's link is
//! when it is not as it should be, a station's face. Clients draw these; they do not work them out.

use serde_json::{Value, json};

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
    let failing = stations.iter().filter(|s| state(s) == "error").count();
    let working = online.iter().filter(|s| s.get("station").and_then(Value::as_str).is_some_and(|a| running.contains(&a))).count();
    let n = online.len() + dim + failing;
    // The one station of a station's own page goes unnamed: it is this machine.
    let summary = if n == 1 {
        let one = stations[0].get("name").and_then(Value::as_str).filter(|n| !n.is_empty()).unwrap_or("这台机器");
        if working > 0 { format!("{one} · 在干活") } else { one.to_string() }
    } else if working > 0 {
        format!("{n} 台 station · {working} 台在干活")
    } else {
        format!("{n} 台 station")
    };
    let mut label = vec![format!("{n} 台 station"), format!("{} 台在线", online.len())];
    if working > 0 {
        label.push(format!("{working} 台在干活"));
    }
    if dim > 0 {
        label.push(format!("{dim} 台离线"));
    }
    if failing > 0 {
        label.push(format!("{failing} 台出错"));
    }
    json!({ "online": online.len(), "dim": dim, "failing": failing, "working": working, "summary": summary, "label": label.join("，") })
}

/// What a list says with no rows to show, in their place: that it is still reading (a station loading or its link
/// coming back), the stations it cannot reach (each tried again), or that there is nothing. A station's own page
/// (`local`) is only ever reading or empty: its one station's state is the page's.
pub fn list_note(local: bool, stations: &[Value], days: &[Value], loading: bool) -> Value {
    let is = |s: &Value, w: &str| s.get("state").and_then(Value::as_str) == Some(w);
    if !days.is_empty() {
        return json!({ "reading": false, "failing": [], "empty": false });
    }
    let connecting = !local && stations.iter().any(|s| is(s, "connecting"));
    let failing: Vec<Value> = if local || loading { Vec::new() } else {
        stations.iter().filter(|s| is(s, "error")).map(|s| {
            let name = s.get("name").and_then(Value::as_str).unwrap_or("");
            json!({ "station": s["station"], "text": format!("连不上「{name}」，正在重试…"), "message": s["message"] })
        }).collect()
    };
    let empty = !loading && !connecting && failing.is_empty();
    json!({ "reading": loading || connecting, "failing": failing, "empty": empty })
}

/// A chat's link to its station while it is not as it should be (web/src/Connection.tsx, Android screens/Connection.kt):
/// down (`trouble`, with why, less its own "连不上…：" the line says already) or coming back (`busy`); null while up.
pub fn link_shown(link: &Value, name: &str) -> Value {
    let station = if name.is_empty() { " station".to_string() } else { format!("「{name}」") };
    match link.get("state").and_then(Value::as_str) {
        Some("offline" | "error") => {
            let why = link.get("message").and_then(Value::as_str).filter(|m| !m.is_empty()).map(|m| match m.split_once('：') {
                Some((head, rest)) if head.contains("连不上") => rest.to_string(),
                _ => m.to_string(),
            });
            json!({ "tone": "trouble", "text": format!("连不上{station}"), "detail": why })
        }
        Some("reconnecting") => json!({ "tone": "busy", "text": format!("正在重连{station}") }),
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
        .unwrap_or_else(|| if online { "在线" } else { "离线" }.to_string())
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
        // One station goes by its name; a station's own page's (no name) is this machine.
        assert_eq!(glyph(&[station("w/a", "Studio", "online")], &days)["summary"], "Studio · 在干活");
        assert_eq!(glyph(&[station("local", "", "online")], &[])["summary"], "这台机器");
        assert_eq!(glyph(&[], &[])["label"], "0 台 station，0 台在线");
    }

    #[test]
    fn a_list_with_no_rows_says_it_reads_fails_or_has_none() {
        let days = [json!({ "items": [{}] })];
        assert_eq!(list_note(false, &[station("w/a", "A", "error")], &days, false), json!({ "reading": false, "failing": [], "empty": false }));
        assert_eq!(list_note(false, &[station("w/a", "A", "online")], &[], true)["reading"], true);
        assert_eq!(list_note(false, &[station("w/a", "A", "connecting")], &[], false)["reading"], true);
        let failing = list_note(false, &[station("w/a", "A", "error"), station("w/b", "B", "online")], &[], false);
        assert_eq!(failing["failing"][0]["text"], "连不上「A」，正在重试…");
        assert_eq!(failing["empty"], false);
        assert_eq!(list_note(false, &[station("w/b", "B", "online")], &[], false)["empty"], true);
        assert_eq!(list_note(false, &[], &[], false)["empty"], true);
        // A station's own page says only that it reads, or that there is nothing.
        let local = list_note(true, &[station("local", "", "error")], &[], false);
        assert_eq!((local["reading"].as_bool(), local["failing"].as_array().map(Vec::len), local["empty"].as_bool()), (Some(false), Some(0), Some(true)));
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
