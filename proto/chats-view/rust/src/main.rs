//! Prototype: the core's chat list, as client/core/src/views.rs `chats` and `days` compute it for one station (online,
//! its link up, nothing changed or asked from here), over a station's rows given as a file (../make-input.py). The
//! per-row work is the original's, line for line, calling the core's own present/decisions/format; only reading the
//! store is replaced by the file. ../ts/chats.ts is the same in TypeScript; their outputs must be equal.
//!
//! `chats-view-bench <input.json> <runs> [output.json]`: the view `runs` times, how long each took.

use std::time::Instant;

use serde_json::{Value, json};
use stillfail_core::present;
use stillfail_i18n::t;

const DAY_MS: f64 = 86_400_000.0;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let input: Value = serde_json::from_str(&std::fs::read_to_string(&args[0]).expect("input")).expect("input json");
    let runs: usize = args.get(1).and_then(|n| n.parse().ok()).unwrap_or(20);
    let mut out = Value::Null;
    let mut took = Vec::new();
    for _ in 0..runs {
        let started = Instant::now();
        out = chats(&input);
        // Handed to the UI as text, as the core's emissions are.
        let text = out.to_string();
        took.push(started.elapsed().as_secs_f64() * 1000.0);
        std::hint::black_box(text);
    }
    if let Some(path) = args.get(2) {
        std::fs::write(path, out.to_string()).expect("output");
    }
    let first = took[0];
    let mut rest = took[1..].to_vec();
    rest.sort_by(f64::total_cmp);
    let median = rest.get(rest.len() / 2).copied().unwrap_or(first);
    println!("{}", json!({ "engine": "rust", "rows": input["rows"].as_array().map(Vec::len), "first": first, "median": median }));
}

fn chats(input: &Value) -> Value {
    let me = input["me"].clone();
    let members: Vec<Value> = input["members"].as_array().cloned().unwrap_or_default();
    let slack_users: Vec<String> = input["slackUsers"].as_array().into_iter().flatten().filter_map(|u| u.as_str().map(str::to_string)).collect();
    let (address, name) = (input["station"]["address"].as_str().unwrap_or(""), input["station"]["name"].as_str().unwrap_or(""));
    let mut rows = Vec::new();
    for row in input["rows"].as_array().into_iter().flatten() {
        let mut row = row.clone();
        row["station"] = json!(address);
        row["stationName"] = json!(name);
        // What the clients draw of it, decided here (present.rs).
        let agents = row.get("agents").and_then(Value::as_array).cloned().unwrap_or_default();
        if let Some(watch) = present::row_watch(&agents) {
            row["watch"] = watch;
        }
        row["state"] = json!(present::row_state(&agents));
        for agent in row.get_mut("agents").and_then(Value::as_array_mut).into_iter().flatten() {
            present::session(agent);
        }
        // Where it came from, for its mark's tip: the Slack workspace, then the thread's channel.
        if row.get("connect").is_some_and(|c| !c.is_null()) {
            let o = row.get("origin").cloned().unwrap_or(Value::Null);
            let text = |k: &str| o.get(k).and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string);
            let place = text("channelName").map(|n| format!("#{n}"))
                .or_else(|| text("channel").filter(|c| c.starts_with('D')).map(|_| t!("core-views.direct_message")));
            row["originText"] = json!(["Slack".to_string()].into_iter().chain(text("teamName")).chain(place).collect::<Vec<_>>().join(" · "));
        }
        // Its line: what was said last, without mentions (a file alone says so).
        if let Some(last) = row.get_mut("last").filter(|l| l.is_object()) {
            let text = stillfail_core::format::clean_text(last.get("text").and_then(Value::as_str).unwrap_or(""));
            last["preview"] = json!(if text.is_empty() { t!("core-views.file") } else { text });
        }
        present::row_people(&mut row, &me, &slack_users, &members);
        if let Some(by) = present::last_by(&row, &me, &slack_users, &members) {
            row["last"]["by"] = by;
            let name = row["last"]["by"]["name"].as_str().unwrap_or("").to_string();
            row["last"]["by"]["label"] = json!(match row["last"]["by"]["state"].as_str() {
                Some(state) => t!("core-views.by_label", name = name, state = present::badge_text(state)),
                None => name,
            });
            let model = row["last"]["by"]["model"].as_str().map(str::to_string);
            row["last"]["by"]["maker"] = present::maker(model.as_deref());
        }
        stillfail_core::decisions::present(&mut row);
        if present::settled(&row) && !present::pinned(&row) && row["archiveReminderDismissed"] != true {
            row["settled"] = json!(true);
            row["archivable"] = json!(true);
        }
        if let Some((text, about)) = present::row_state_line(&row) {
            row["stateText"] = json!(text);
            if let Some(seq) = about {
                row["stateAbout"] = json!(seq);
            }
        }
        rows.push(row);
    }
    let now = input["now"].as_f64().unwrap_or(0.0);
    let offset = input["offsetMin"].as_i64().unwrap_or(0) as i32;
    json!({ "days": days(rows, now, offset) })
}

fn days(rows: Vec<Value>, now: f64, offset: i32) -> Vec<Value> {
    let at = |row: &Value| row["lastActiveAt"].as_f64().unwrap_or(0.0);
    let (mut pinned, mut rows): (Vec<Value>, Vec<Value>) = rows.into_iter().partition(|row| row.get("pinned").is_some_and(Value::is_number));
    let pinned_at = |row: &Value| row["pinned"].as_f64().unwrap_or(0.0);
    pinned.sort_by(|a, b| pinned_at(b).total_cmp(&pinned_at(a)).then(at(b).total_cmp(&at(a))));
    for row in &mut pinned {
        row["pinned"] = json!(true);
    }
    for row in rows.iter_mut().filter(|row| row.get("pinned").is_some()) {
        row["pinned"] = json!(false);
    }
    let day = |ms: f64| ((ms + offset as f64 * 60_000.0) / DAY_MS).floor() as i64;
    let settled = |row: &Value| row.get("settled").and_then(Value::as_bool) == Some(true);
    rows.sort_by(|a, b| day(at(b)).cmp(&day(at(a))).then(settled(a).cmp(&settled(b))).then(at(b).total_cmp(&at(a))));
    let today = day(now);
    let mut days: Vec<(i64, f64, Vec<Value>)> = Vec::new();
    for row in rows {
        let (t, d) = (at(&row), day(at(&row)));
        match days.last_mut() {
            Some((last, _, items)) if *last == d => items.push(row),
            _ => days.push((d, t, vec![row])),
        }
    }
    let top = (!pinned.is_empty()).then(|| {
        json!({ "daysAgo": -1, "at": pinned.first().map(at).unwrap_or(0.0), "label": t!("core-views.pinned"), "pinned": true, "items": pinned })
    });
    top.into_iter()
        .chain(days.into_iter().map(|(d, t, items)| json!({ "daysAgo": today - d, "at": t, "label": stillfail_core::format::day_label(t, now, offset), "items": items })))
        .collect()
}
