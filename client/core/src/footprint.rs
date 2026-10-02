//! A station's footprint page (shapes `FootprintView`), from what `GET /footprint` answers: how much of the disk the station takes
//! and for what, its chats' directories, its agents' memory, and the clean-ups the viewer may do. Each clean-up is a
//! choice the pages run as they are told: the questions to ask in turn (deleting is asked twice), then the call.

use serde_json::{Value, json};
use stillfail_i18n::t;

use crate::brand;
use crate::format;
use crate::present::Clock;

const DAY: f64 = 86_400_000.0;

/// What each part of the data directory is, and its colour.
fn part(id: &str) -> (String, String, &'static str) {
    let (id, tone) = match id {
        "chats" => ("chats", "chart-1"),
        "transcripts" => ("transcripts", "chart-2"),
        "homes" => ("homes", "chart-3"),
        "archive" => ("archive", "chart-4"),
        "repos" => ("repos", "chart-5"),
        _ => ("other", "chart-6"),
    };
    (t!(&format!("core-logic.footprint.part.{id}")), t!(&format!("core-logic.footprint.part.{id}.note")), tone)
}

/// Places beside the data directory.
fn elsewhere(id: &str) -> String {
    match id {
        "claude" | "codex" | "playwright" | "pnpm" | "npm" | "cargo" => t!(&format!("core-logic.footprint.elsewhere.{id}")),
        _ => t!("core-logic.footprint.part.other"),
    }
}

fn n(v: &Value, key: &str) -> f64 {
    v.get(key).and_then(Value::as_f64).unwrap_or(0.0)
}

fn size(bytes: f64) -> String {
    format::bytes(bytes)
}

fn keys(rows: &[&Value]) -> Vec<Value> {
    rows.iter().filter_map(|r| r.get("key").cloned()).collect()
}

fn confirm(title: String, text: String, action: &str, danger: bool) -> Value {
    json!({ "title": title, "text": text, "action": action, "danger": danger })
}

fn choice(label: String, call: &str, keys: Vec<Value>, confirms: Vec<Value>, done: &str) -> Value {
    json!({ "label": label, "call": call, "keys": keys, "confirms": confirms, "done": done })
}

/// Deleting chats, asked twice: what goes, then once more that it cannot be undone.
fn delete_confirms(what: &str, count: usize, bytes: f64) -> Vec<Value> {
    vec![
        confirm(
            t!("core-logic.footprint.delete.title", what = what),
            t!("core-logic.footprint.delete.text", n = count, size = size(bytes)),
            &t!("core-logic.footprint.continue"),
            true,
        ),
        confirm(t!("core-logic.footprint.confirm_again"), t!("core-logic.footprint.delete.again", n = count), &t!("core-logic.footprint.delete.action", n = count), true),
    ]
}

/// The line that opens the page: how much it takes, or that it is being measured.
pub fn brief(u: &mut Value) {
    let text = match u.get("bytes").and_then(Value::as_f64) {
        Some(bytes) => size(bytes),
        None => t!("core-logic.footprint.measuring"),
    };
    u["text"] = json!(text);
}

pub fn shown(raw: &Value, c: Clock) -> Value {
    let name = brand::name();
    let checked = raw.get("checkedAt").and_then(Value::as_f64);
    let scanning = raw.get("scanning").and_then(Value::as_bool).unwrap_or(false);
    let manage = raw.get("manage").and_then(Value::as_bool).unwrap_or(false);
    let checked_text = match (checked, scanning) {
        (None, _) => t!("core-logic.footprint.measuring_first"),
        (Some(_), true) => t!("core-logic.footprint.measuring_again"),
        (Some(at), false) => t!("core-logic.footprint.measured", when = format::relative_time(at, c.now, c.offset_min)),
    };
    let parts: Vec<&Value> = raw.get("parts").and_then(Value::as_array).map(|a| a.iter().collect()).unwrap_or_default();
    let total: f64 = parts.iter().map(|p| n(p, "bytes")).sum();
    let disk = raw.get("disk").cloned().unwrap_or(Value::Null);
    let (disk_total, disk_free) = (n(&disk, "totalBytes"), n(&disk, "freeBytes"));
    let percent = |bytes: f64| if disk_total > 0.0 { (bytes / disk_total * 1000.0).round() / 10.0 } else { 0.0 };
    let rest = (disk_total - disk_free - total).max(0.0);
    let mut bar: Vec<Value> = parts.iter().filter(|p| n(p, "bytes") > 0.0).map(|p| {
        let id = p.get("id").and_then(Value::as_str).unwrap_or("");
        json!({ "id": id, "percent": percent(n(p, "bytes")), "tone": part(id).2 })
    }).collect();
    bar.push(json!({ "id": "rest", "percent": percent(rest), "tone": "rest" }));
    bar.push(json!({ "id": "free", "percent": percent(disk_free), "tone": "free" }));
    let free_share = if disk_total > 0.0 { disk_free / disk_total } else { 1.0 };
    let free_level = if free_share < 0.1 { "red" } else if free_share < 0.2 { "amber" } else { "ok" };
    let legend = vec![
        json!({ "text": format!("{name} {}", size(total)), "tone": "chart-1", "level": "ok" }),
        json!({ "text": t!("core-logic.footprint.legend.rest", size = size(rest)), "tone": "rest", "level": "ok" }),
        json!({ "text": t!("core-logic.footprint.legend.free", free = size(disk_free), total = size(disk_total)), "tone": "", "level": free_level }),
    ];
    let chats: Vec<&Value> = raw.get("chats").and_then(Value::as_array).map(|a| a.iter().collect()).unwrap_or_default();
    let chat_bytes: f64 = parts.iter().find(|p| p.get("id").and_then(Value::as_str) == Some("chats")).map(|p| n(p, "bytes")).unwrap_or(0.0);
    // Parts with nothing in them are left out.
    let parts_shown: Vec<Value> = parts.iter().filter(|p| n(p, "bytes") > 0.0).map(|p| {
        let id = p.get("id").and_then(Value::as_str).unwrap_or("");
        let (label, note, tone) = part(id);
        let note = if id == "chats" { t!("core-logic.footprint.part.chats.count", n = chats.len(), note = note) } else { note };
        json!({ "id": id, "label": label, "note": note, "text": size(n(p, "bytes")), "tone": tone, "opens": id == "chats" && !chats.is_empty() })
    }).collect();
    let elsewhere_shown: Vec<Value> = raw.get("elsewhere").and_then(Value::as_array).into_iter().flatten().map(|e| {
        let id = e.get("id").and_then(Value::as_str).unwrap_or("");
        json!({ "id": id, "label": elsewhere(id), "note": e.get("path").cloned().unwrap_or(json!("")), "text": size(n(e, "bytes")), "tone": "", "opens": false })
    }).collect();

    // Clean-ups.
    let idle = |r: &&Value| r.get("state").and_then(Value::as_str) != Some("running");
    let rebuildable: Vec<&Value> = chats.iter().copied().filter(|r| n(r, "rebuildBytes") > 0.0).filter(idle).collect();
    let rebuild_bytes: f64 = rebuildable.iter().map(|r| n(r, "rebuildBytes")).sum();
    let archived: Vec<&Value> = chats.iter().copied().filter(|r| r.get("archived").and_then(Value::as_bool) == Some(true)).collect();
    let processes: Vec<&Value> = raw.get("processes").and_then(Value::as_array).map(|a| a.iter().collect()).unwrap_or_default();
    let warm: Vec<&Value> = processes.iter().copied().filter(|p| p.get("state").and_then(Value::as_str) == Some("warm")).collect();
    let warm_bytes: f64 = warm.iter().map(|p| n(p, "rssBytes")).sum();
    let mut actions = vec![];
    if manage && checked.is_some() {
        if rebuild_bytes > 0.0 {
            let text = t!("core-logic.footprint.rebuild.text", n = rebuildable.len(), size = size(rebuild_bytes));
            let clean = t!("core-logic.footprint.clean");
            actions.push(json!({
                "id": "rebuild", "title": t!("core-logic.footprint.rebuild.title", size = size(rebuild_bytes)),
                "note": t!("core-logic.footprint.rebuild.note"), "action": clean, "danger": false, "pick": null,
                "choices": [choice(t!("core-logic.footprint.all"), "footprint.rebuild", keys(&rebuildable), vec![confirm(t!("core-logic.footprint.rebuild.confirm"), text, &clean, false)], &t!("core-logic.footprint.cleaned"))],
            }));
        }
        if !archived.is_empty() {
            let mut choices = vec![];
            let mut counts = vec![];
            for days in [0u32, 7, 30] {
                let old: Vec<&Value> = archived.iter().copied().filter(|r| days == 0 || c.now - n(r, "lastActiveAt") > days as f64 * DAY).collect();
                if old.is_empty() || counts.contains(&old.len()) {
                    continue;
                }
                counts.push(old.len());
                let bytes: f64 = old.iter().map(|r| n(r, "bytes")).sum();
                let (label, what) = if days == 0 {
                    (t!("core-logic.footprint.archived.all", n = old.len(), size = size(bytes)), t!("core-logic.footprint.archived.all.what"))
                } else {
                    (t!("core-logic.footprint.archived.unused", days = days, n = old.len(), size = size(bytes)), t!("core-logic.footprint.archived.unused.what", days = days))
                };
                choices.push(choice(label, "footprint.delete", keys(&old), delete_confirms(&what, old.len(), bytes), &t!("core-logic.footprint.deleted")));
            }
            let bytes: f64 = archived.iter().map(|r| n(r, "bytes")).sum();
            actions.push(json!({
                "id": "archived", "title": t!("core-logic.footprint.archived.title", n = archived.len(), size = size(bytes)),
                "note": t!("core-logic.footprint.archived.note"), "action": t!("core-logic.footprint.archived.action"), "danger": true,
                "pick": t!("core-logic.footprint.archived.pick"), "choices": choices,
            }));
        }
        if !warm.is_empty() {
            let text = t!("core-logic.footprint.idle.text", size = size(warm_bytes));
            let end = t!("core-logic.footprint.end");
            actions.push(json!({
                "id": "idle", "title": t!("core-logic.footprint.idle.title", n = warm.len(), size = size(warm_bytes)),
                "note": t!("core-logic.footprint.idle.note"), "action": end, "danger": false, "pick": null,
                "choices": [choice(t!("core-logic.footprint.all"), "footprint.evict", keys(&warm), vec![confirm(t!("core-logic.footprint.idle.confirm", n = warm.len()), text, &end, false)], &t!("core-logic.footprint.idle.ended"))],
            }));
        }
    }
    let actions_note = if checked.is_none() {
        None
    } else if !manage {
        Some(t!("core-logic.footprint.actions.not_allowed"))
    } else if actions.is_empty() {
        Some(t!("core-logic.footprint.actions.none"))
    } else {
        None
    };

    // Each chat: its size, and what can be done with it.
    let chats_shown: Vec<Value> = chats.iter().map(|r| {
        let chat = r.get("chat").cloned().unwrap_or(Value::Null);
        let title = chat.get("title").and_then(Value::as_str).filter(|t| !t.is_empty()).map_or_else(|| t!("core-logic.footprint.untitled"), str::to_string);
        let archived = r.get("archived").and_then(Value::as_bool).unwrap_or(false);
        let running = r.get("state").and_then(Value::as_str) == Some("running");
        let rebuild = n(r, "rebuildBytes");
        let last = n(r, "lastActiveAt");
        let mut note = vec![];
        if running {
            note.push(t!("core-logic.footprint.working"));
        } else if last > 0.0 {
            note.push(t!("core-logic.footprint.used", when = format::relative_time(last, c.now, c.offset_min)));
        }
        if rebuild > 0.0 {
            note.push(t!("core-logic.footprint.chat.rebuildable", size = size(rebuild)));
        }
        let key = r.get("key").cloned().unwrap_or(Value::Null);
        let mut choices = vec![];
        if manage && rebuild > 0.0 && !running {
            choices.push(choice(
                t!("core-logic.footprint.chat.rebuild", size = size(rebuild)),
                "footprint.rebuild",
                vec![key.clone()],
                vec![confirm(t!("core-logic.footprint.chat.rebuild.confirm", title = title), t!("core-logic.footprint.chat.rebuild.text", size = size(rebuild)), &t!("core-logic.footprint.clean"), false)],
                &t!("core-logic.footprint.cleaned"),
            ));
        }
        if manage && archived {
            let delete = t!("core-logic.footprint.chat.delete");
            choices.push(choice(
                delete.clone(),
                "footprint.delete",
                vec![key.clone()],
                vec![
                    confirm(t!("core-logic.footprint.chat.delete.confirm", title = title), t!("core-logic.footprint.chat.delete.text", size = size(n(r, "bytes"))), &t!("core-logic.footprint.continue"), true),
                    confirm(t!("core-logic.footprint.confirm_again"), t!("core-logic.footprint.chat.delete.again"), &delete, true),
                ],
                &t!("core-logic.footprint.deleted"),
            ));
        }
        json!({
            "key": key, "chat": chat.get("id").cloned(), "title": title, "archived": archived,
            "text": size(n(r, "bytes")), "note": note.join(" · "), "choices": choices,
        })
    }).collect();
    let unseen = raw.get("unseen").cloned().unwrap_or(Value::Null);
    let unseen_text = (n(&unseen, "count") > 0.0).then(|| t!("core-logic.footprint.unseen", n = n(&unseen, "count"), size = size(n(&unseen, "bytes"))));

    // Memory: the station, its agents, each agent's process (busiest first).
    let memory = raw.get("memory").cloned().unwrap_or(Value::Null);
    let agents: f64 = processes.iter().map(|p| n(p, "rssBytes")).sum();
    let mut rows = vec![
        json!({ "label": t!("core-logic.footprint.memory.station"), "text": size(n(&memory, "stationBytes")), "nested": false }),
        json!({ "label": t!("core-logic.footprint.memory.agents", n = processes.len()), "text": size(agents), "nested": false }),
    ];
    let mut sorted = processes.clone();
    sorted.sort_by(|a, b| n(b, "rssBytes").total_cmp(&n(a, "rssBytes")));
    for p in sorted {
        let chat = p.get("chat").filter(|c| c.is_object());
        let label = match (chat.and_then(|c| c.get("title")).and_then(Value::as_str).filter(|t| !t.is_empty()), p.get("runtime").and_then(Value::as_str)) {
            (Some(title), _) => title.to_string(),
            (None, Some("codex")) => t!("core-logic.footprint.memory.codex"),
            _ => t!("core-logic.footprint.untitled"),
        };
        let state = p.get("state").and_then(Value::as_str);
        let note = match state {
            Some("running") => Some(t!("core-logic.footprint.working")),
            Some("warm") => p.get("lastActiveAt").and_then(Value::as_f64).map(|at| t!("core-logic.footprint.memory.idle", when = format::relative_time(at, c.now, c.offset_min))),
            _ => None,
        };
        let end = (manage && state == Some("warm")).then(|| {
            choice(
                t!("core-logic.footprint.memory.end"),
                "footprint.evict",
                vec![p.get("key").cloned().unwrap_or(Value::Null)],
                vec![confirm(t!("core-logic.footprint.memory.end.confirm", label = label), t!("core-logic.footprint.memory.end.text", size = size(n(p, "rssBytes"))), &t!("core-logic.footprint.end"), false)],
                &t!("core-logic.footprint.ended"),
            )
        });
        rows.push(json!({
            "label": label, "text": p.get("rssBytes").and_then(Value::as_f64).map(size).unwrap_or_else(|| "—".into()), "note": note,
            "nested": true, "chat": chat.and_then(|c| c.get("id")).cloned(), "choice": end,
        }));
    }
    json!({
        "measured": checked.is_some(),
        "scanning": scanning,
        "manage": manage,
        "checkedText": checked_text,
        "lead": t!("core-logic.footprint.lead", name = name),
        "totalText": if checked.is_some() { size(total) } else { "—".into() },
        "bar": if checked.is_some() { bar } else { vec![] },
        "legend": if checked.is_some() { legend } else { vec![] },
        "parts": parts_shown,
        "elsewhere": elsewhere_shown,
        "elsewhereNote": t!("core-logic.footprint.elsewhere.note"),
        "actions": actions,
        "actionsNote": actions_note,
        "chats": chats_shown,
        "chatsText": t!("core-logic.footprint.chats", n = chats.len(), size = size(chat_bytes)),
        "unseenText": unseen_text,
        "memoryTitle": t!("core-logic.footprint.memory.title", total = size(n(&memory, "totalBytes")), used = size(n(&memory, "usedBytes"))),
        "memory": rows,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use stillfail_shapes as s;

    const NOW: f64 = 1_790_000_000_000.0;

    fn raw(manage: bool) -> Value {
        json!({
            "checkedAt": NOW - 120_000.0, "tookMs": 9000, "scanning": false, "manage": manage,
            "disk": { "totalBytes": 100e9, "freeBytes": 8e9 },
            "parts": [{ "id": "chats", "bytes": 8e9 }, { "id": "transcripts", "bytes": 1e9 }, { "id": "homes", "bytes": 0 }, { "id": "archive", "bytes": 3e8 }, { "id": "repos", "bytes": 3e8 }, { "id": "other", "bytes": 1e8 }],
            "elsewhere": [{ "id": "playwright", "path": "~/Library/Caches/ms-playwright", "bytes": 8e8 }],
            "chats": [
                { "key": "a", "chat": { "id": "a", "title": "预加载", "archived": false }, "bytes": 3e9, "rebuildBytes": 2.9e9, "archived": false, "lastActiveAt": NOW - 3_600_000.0, "state": "warm" },
                { "key": "b", "chat": { "id": "b", "title": "", "archived": true }, "bytes": 4e8, "rebuildBytes": 1e8, "archived": true, "lastActiveAt": NOW - 10.0 * DAY, "state": "cold" },
                { "key": "c", "chat": { "id": "c", "title": "在跑", "archived": false }, "bytes": 3e8, "rebuildBytes": 3e8, "archived": false, "lastActiveAt": NOW, "state": "running" },
                { "key": "d", "chat": { "id": "d", "title": "旧的", "archived": true }, "bytes": 1e8, "rebuildBytes": 0, "archived": true, "lastActiveAt": NOW - 2.0 * DAY, "state": "cold" },
            ],
            "unseen": { "count": 0, "bytes": 0 },
            "memory": { "totalBytes": 6e9, "usedBytes": 5.2e9, "stationBytes": 2.2e7 },
            "processes": [
                { "pgid": 1, "runtime": "claude", "rssBytes": 1.3e8, "key": "a", "chat": { "id": "a", "title": "预加载" }, "state": "warm", "lastActiveAt": NOW - 3_600_000.0 },
                { "pgid": 2, "runtime": "claude", "rssBytes": 1.8e8, "key": "c", "chat": { "id": "c", "title": "在跑" }, "state": "running", "lastActiveAt": NOW },
                { "pgid": 3, "runtime": "codex", "rssBytes": null, "key": null, "chat": null, "state": null, "lastActiveAt": null },
            ],
        })
    }

    #[test]
    fn the_page_says_what_takes_the_disk_and_what_can_be_cleaned() {
        let v = shown(&raw(true), Clock { now: NOW, offset_min: 480 });
        s::conform::<s::FootprintView>(v.clone()).unwrap();
        assert_eq!(v["checkedText"], "2 分钟前统计");
        assert_eq!(v["totalText"], "9.0 GB");
        assert_eq!(v["legend"][2]["level"], "red", "8% free");
        let actions: Vec<&str> = v["actions"].as_array().unwrap().iter().map(|a| a["id"].as_str().unwrap()).collect();
        assert_eq!(actions, ["rebuild", "archived", "idle"]);
        // Not the running chat's.
        assert_eq!(v["actions"][0]["choices"][0]["keys"], json!(["a", "b"]));
        // All archived, or those not used for a week; deleting is asked twice.
        let archived = &v["actions"][1]["choices"];
        assert_eq!(archived.as_array().unwrap().iter().map(|c| c["keys"].clone()).collect::<Vec<_>>(), [json!(["b", "d"]), json!(["b"])]);
        assert_eq!(archived[0]["confirms"].as_array().unwrap().len(), 2);
        assert_eq!(v["actions"][2]["choices"][0]["keys"], json!(["a"]));
        assert_eq!(v["chats"][1]["title"], "未命名的 chat");
        assert_eq!(v["chats"][2]["choices"], json!([]), "a chat at work is left alone, and one not archived is not deleted here");
        assert_eq!(v["chats"][1]["choices"][1]["confirms"].as_array().unwrap().len(), 2);
        assert_eq!(v["memory"][2]["label"], "在跑");
        assert!(v["memory"][4]["label"].as_str().unwrap().starts_with("Codex"));
        assert_eq!(v["memory"][3]["choice"]["call"], "footprint.evict");
    }

    #[test]
    fn members_look_and_a_first_scan_is_waited_for() {
        let v = shown(&raw(false), Clock { now: NOW, offset_min: 480 });
        assert_eq!((v["actions"].clone(), v["actionsNote"].clone()), (json!([]), json!("只有 workspace 的 owner 和管理员能清理")));
        assert!(v["chats"].as_array().unwrap().iter().all(|c| c["choices"] == json!([])));
        let first = shown(&json!({ "scanning": true, "manage": true, "disk": {}, "parts": [], "chats": [], "processes": [] }), Clock { now: NOW, offset_min: 480 });
        s::conform::<s::FootprintView>(first.clone()).unwrap();
        assert_eq!((first["measured"].clone(), first["totalText"].clone()), (json!(false), json!("—")));
        let mut b = json!({ "bytes": null, "scanning": true });
        brief(&mut b);
        assert_eq!(b["text"], "正在统计…");
    }
}
