//! Decisions: an agent's block post with options (chat_post `options`) asks the people in its chat to decide. It waits
//! until a person writes in the chat after it (picking an option sends a message quoting it with the option's label;
//! any other message answers it too), or a newer one replaces it; the station says which one waits on each chat's row
//! (`decision`). Here, for the viewer: the row's second line (奏 · …) and mark, the options in the order they are shown
//! (the one the agent recommends last), where each decision in a chat's messages stands, and the decisions page (those
//! not dismissed, the ones set aside last). Setting one aside (待定, `decision.defer`) is kept on the device with the
//! prefs (`decisionsDeferred`); dismissing one (`decision.dismiss`) is kept by the station for the viewer, on every
//! device of theirs.

use serde_json::{Map, Value, json};

/// How much of a decision's first line its line shows.
const LINE_CHARS: usize = 40;

/// Where a deferral is kept in the prefs (`decisionsDeferred`): the decision's station, chat (thread) and post (seq).
pub fn deferral_key(station: &str, thread: u64, seq: u64) -> String {
    format!("{station}\t{thread}\t{seq}")
}

/// When the viewer set a decision aside on this device, if they did.
pub fn deferred_at(prefs: &Value, station: &str, thread: u64, seq: u64) -> Option<f64> {
    prefs.get("decisionsDeferred")?.get(deferral_key(station, thread, seq))?.as_f64()
}

/// The answers a decision offers, as the clients show them (`DecisionOption`): each with a label, in the agent's order
/// with the recommended one moved last; those without a label left out.
pub fn options_shown(options: &Value) -> Vec<Value> {
    let all: Vec<Value> = options.as_array().into_iter().flatten().filter_map(|o| {
        let label = o.get("label").and_then(Value::as_str).map(str::trim).filter(|l| !l.is_empty())?;
        let mut shown = json!({ "label": label });
        if let Some(detail) = o.get("detail").and_then(Value::as_str).map(str::trim).filter(|d| !d.is_empty()) {
            shown["detail"] = json!(detail);
        }
        if o.get("recommended").and_then(Value::as_bool) == Some(true) {
            shown["recommended"] = json!(true);
        }
        Some(shown)
    }).collect();
    let (recommended, rest): (Vec<Value>, Vec<Value>) = all.into_iter().partition(|o| o.get("recommended").is_some());
    rest.into_iter().chain(recommended).collect()
}

/// A decision's line: 奏 · its post's first line, without mentions or markup, cut to about 40 characters.
pub fn line(text: &str) -> String {
    let first = text.lines().map(str::trim).find(|l| !l.is_empty()).unwrap_or("");
    let clean = crate::format::clean_text(first).replace("**", "").replace("__", "").replace('`', "");
    let clean = clean.trim_start_matches(['#', '>', '-', '*', ' ']).trim();
    let cut: String = clean.chars().take(LINE_CHARS).collect();
    let cut = if clean.chars().count() > LINE_CHARS { format!("{}…", cut.trim_end()) } else { cut };
    if cut.is_empty() { "奏".to_string() } else { format!("奏 · {cut}") }
}

/// The decision a row waits on, as its station gives it (`{seq, options, dismissed?, message, before}`).
pub fn of_row(row: &Value) -> Option<&Value> {
    row.get("decision").filter(|d| d.get("seq").and_then(Value::as_u64).is_some())
}

/// Whether the viewer dismissed it.
pub fn dismissed(decision: &Value) -> bool {
    decision.get("dismissed").and_then(Value::as_bool) == Some(true)
}

/// Whether a row has a decision waiting for the viewer: pending, and not dismissed by them.
pub fn waits(row: &Value) -> bool {
    of_row(row).is_some_and(|d| !dismissed(d))
}

/// A row's mark, the most urgent first: alert (blocked or failed), wait (a decision waits for the viewer), busy (at
/// work), done (something unread); none otherwise. Its `state` is the row's (present.rs `row_state`). An agent blocked
/// on a decision is not an alert but a decision (wait); once the viewer dismissed it, it marks nothing.
pub fn tone(row: &Value) -> Option<&'static str> {
    let state = row.get("state").and_then(Value::as_str);
    let decided = of_row(row).is_some();
    if state == Some("failed") || (state == Some("block") && !decided) {
        return Some("alert");
    }
    if waits(row) {
        return Some("wait");
    }
    if state == Some("run") {
        return Some("busy");
    }
    (row.get("unread").and_then(Value::as_bool) == Some(true)).then_some("done")
}

/// A row's decision as the clients show it (`RowDecision`): its seq, options as shown, whether dismissed, and its line
/// while it waits for the viewer.
pub fn shown(decision: &Value) -> Value {
    let mut v = json!({ "seq": decision["seq"], "options": options_shown(&decision["options"]) });
    if dismissed(decision) {
        v["dismissed"] = json!(true);
    } else {
        v["text"] = json!(line(decision.get("message").and_then(|m| m.get("text")).and_then(Value::as_str).unwrap_or("")));
    }
    v
}

/// Puts in a row what the clients show of its decision (`decision`, as [`shown`]) and its mark (`tone`).
pub fn present(row: &mut Value) {
    match of_row(row).map(shown) {
        Some(decision) => row["decision"] = decision,
        None => {
            if let Some(map) = row.as_object_mut() {
                map.remove("decision");
            }
        }
    }
    if let Some(tone) = tone(row) {
        row["tone"] = json!(tone);
    }
}

/// Where each decision in a chat's messages stands (`ChatMessage::options`, `decision`), messages decorated as the
/// chat shows them (with `by` and `mine`). `pending`: the seq of the one its row says waits, and whether the viewer
/// dismissed it; `None` when the row is not known (then the messages loaded say: none of a person after it, nor a
/// newer decision).
pub fn in_messages(messages: &mut [Value], pending: Option<Option<(u64, bool)>>) {
    let asked: Vec<usize> = (0..messages.len())
        .filter(|&i| messages[i].get("options").and_then(Value::as_array).is_some_and(|o| !o.is_empty()))
        .collect();
    for &i in &asked {
        let seq = messages[i].get("seq").and_then(Value::as_u64).unwrap_or(0);
        let ts = messages[i].get("ts").and_then(Value::as_str).unwrap_or("").to_string();
        let options = options_shown(&messages[i]["options"]);
        let later = &messages[i + 1..];
        let answer = later.iter().find(|m| m.get("authorKind").and_then(Value::as_str) == Some("person"));
        let replaced = later.iter().any(|m| m.get("options").and_then(Value::as_array).is_some_and(|o| !o.is_empty()));
        let (waiting, dismissed) = match pending {
            Some(Some((p, dismissed))) => (p == seq, p == seq && dismissed),
            Some(None) => (false, false),
            None => (answer.is_none() && !replaced, false),
        };
        let mut decision = json!({ "resolved": !waiting });
        if dismissed {
            decision["dismissed"] = json!(true);
        }
        if !waiting {
            match answer {
                Some(a) => {
                    let name = if a.get("mine").and_then(Value::as_bool) == Some(true) {
                        "你".to_string()
                    } else {
                        a.get("by").and_then(|b| b.get("name")).and_then(Value::as_str).unwrap_or("").to_string()
                    };
                    let quoted = a.get("quotes").and_then(Value::as_array).into_iter().flatten()
                        .any(|q| q.get("ts").and_then(Value::as_str).is_some_and(|t| !ts.is_empty() && t == ts));
                    let said = a.get("text").and_then(Value::as_str).unwrap_or("").trim().to_string();
                    let chosen = options.iter().filter_map(|o| o.get("label").and_then(Value::as_str)).find(|l| quoted && *l == said);
                    decision["answeredBy"] = json!(name);
                    match chosen {
                        Some(label) => {
                            decision["chosen"] = json!(label);
                            decision["text"] = json!(format!("{name} 选了「{label}」"));
                        }
                        None => decision["text"] = json!(format!("{name} 回复了")),
                    }
                }
                None if replaced => decision["text"] = json!("已换成新的问题"),
                None => {}
            }
        }
        let m: &mut Map<String, Value> = match messages[i].as_object_mut() {
            Some(m) => m,
            None => continue,
        };
        m.insert("options".into(), json!(options));
        m.insert("decision".into(), decision);
    }
}

/// The text and quote a picked option sends (`decision.answer`): the option's label, quoting the post that asked
/// (whole, as the agent's own message: its ts says exactly which).
pub fn answer(decision: &Value, option: &str) -> Option<(String, Value)> {
    let options = options_shown(&decision["options"]);
    let label = options.iter().filter_map(|o| o.get("label").and_then(Value::as_str)).find(|l| *l == option.trim())?.to_string();
    let message = decision.get("message").filter(|m| m.is_object())?;
    let text = message.get("text").and_then(Value::as_str).unwrap_or("");
    let author = message.get("authorName").and_then(Value::as_str).filter(|a| !a.is_empty()).unwrap_or("agent");
    let mut quote = json!({ "author": author, "text": text, "comment": "", "role": "agent" });
    if let Some(ts) = message.get("ts").and_then(Value::as_str).filter(|t| !t.is_empty()) {
        quote["ts"] = json!(ts);
    }
    Some((label, json!([quote])))
}

/// The order of the decisions page: those not set aside, oldest asked first; then those set aside, the one set aside
/// latest last. Each `(asked at, set aside at)`.
pub fn order(items: &mut [(Value, f64, Option<f64>)]) {
    items.sort_by(|a, b| {
        let key = |x: &(Value, f64, Option<f64>)| (x.2.is_some(), x.2.unwrap_or(0.0), x.1);
        let (ka, kb) = (key(a), key(b));
        ka.0.cmp(&kb.0).then(ka.1.total_cmp(&kb.1)).then(ka.2.total_cmp(&kb.2))
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn decision(seq: u64, dismissed: bool) -> Value {
        let mut d = json!({
            "seq": seq,
            "options": [{ "label": "按今天累计", "detail": "重连不清零", "recommended": true }, { "label": " 先不改 " }, { "label": "" }, { "label": "改成本次", "detail": " " }],
            "message": { "seq": seq, "ts": "9.000002", "text": "**「共」改成按今天累计吗？**\n细节：重连、换中继不清零", "authorName": "Claude" },
            "before": [],
        });
        if dismissed {
            d["dismissed"] = json!(true);
        }
        d
    }

    #[test]
    fn options_show_the_recommended_one_last() {
        let shown = options_shown(&decision(4, false)["options"]);
        assert_eq!(shown, vec![json!({ "label": "先不改" }), json!({ "label": "改成本次" }), json!({ "label": "按今天累计", "detail": "重连不清零", "recommended": true })]);
        for o in &shown {
            stillfail_shapes::conform::<stillfail_shapes::DecisionOption>(o.clone()).unwrap();
        }
        assert!(options_shown(&Value::Null).is_empty());
    }

    #[test]
    fn a_decisions_line_is_its_first_line_cut_short() {
        assert_eq!(line("**「共」改成按今天累计吗？**\n细节"), "奏 · 「共」改成按今天累计吗？");
        assert_eq!(line("\n\n## 选哪个"), "奏 · 选哪个");
        let long = "字".repeat(50);
        assert_eq!(line(&long), format!("奏 · {}…", "字".repeat(40)));
        assert_eq!(line(""), "奏");
    }

    #[test]
    fn a_row_with_a_decision_says_so_and_is_marked_wait_until_dismissed() {
        let mut row = json!({ "state": "block", "unread": true, "decision": decision(4, false) });
        present(&mut row);
        assert_eq!(row["tone"], "wait", "blocked on a decision: not an alert");
        assert_eq!(row["decision"]["text"], "奏 · 「共」改成按今天累计吗？");
        assert_eq!(row["decision"]["options"][2]["label"], "按今天累计");
        assert_eq!(row["decision"].get("message"), None, "the rows carry only what they show");
        stillfail_shapes::conform::<stillfail_shapes::RowDecision>(row["decision"].clone()).unwrap();
        // Dismissed: no line, no mark from it.
        let mut row = json!({ "state": "block", "unread": false, "decision": decision(4, true) });
        present(&mut row);
        assert_eq!((row.get("tone"), row["decision"].get("text"), row["decision"]["dismissed"].clone()), (None, None, json!(true)));
        let mut row = json!({ "state": "block", "unread": true, "decision": decision(4, true) });
        present(&mut row);
        assert_eq!(row["tone"], "done");
        // Blocked with no decision: an alert, as before; failed always.
        assert_eq!(tone(&json!({ "state": "block" })), Some("alert"));
        assert_eq!(tone(&json!({ "state": "failed", "decision": decision(4, false) })), Some("alert"));
        assert_eq!(tone(&json!({ "state": "run", "decision": decision(4, false) })), Some("wait"));
        assert_eq!(tone(&json!({ "state": "run" })), Some("busy"));
        assert_eq!(tone(&json!({ "state": null, "unread": true })), Some("done"));
        assert_eq!(tone(&json!({ "state": null })), None);
        // None at all: nothing said.
        let mut row = json!({ "state": null, "decision": null });
        present(&mut row);
        assert_eq!((row.get("decision"), row.get("tone")), (None, None));
    }

    fn said(seq: u64, kind: &str, text: &str) -> Value {
        json!({ "seq": seq, "ts": format!("9.00000{seq}"), "authorKind": kind, "text": text, "quotes": [], "mine": false, "by": { "name": if kind == "person" { "林晓" } else { "Claude" } } })
    }

    fn asked(seq: u64) -> Value {
        let mut m = said(seq, "agent", "选哪个？");
        m["options"] = json!([{ "label": "A", "recommended": true }, { "label": "B" }]);
        m
    }

    #[test]
    fn decisions_in_a_chat_say_whether_they_wait_and_who_answered_how() {
        // As the row says: the one it names waits, dismissed or not.
        let mut messages = vec![said(1, "person", "做吧"), asked(2), said(3, "agent", "顺便说下进度")];
        in_messages(&mut messages, Some(Some((2, true))));
        assert_eq!(messages[1]["decision"], json!({ "resolved": false, "dismissed": true }));
        assert_eq!(messages[1]["options"], json!([{ "label": "B" }, { "label": "A", "recommended": true }]));
        assert_eq!(messages[0].get("decision"), None);
        // Picked: quoted, with an option's label.
        let mut pick = said(3, "person", " B ");
        pick["quotes"] = json!([{ "author": "Claude", "text": "选哪个？", "ts": "9.000002", "role": "agent" }]);
        let mut messages = vec![asked(2), pick];
        in_messages(&mut messages, Some(None));
        assert_eq!(messages[0]["decision"], json!({ "resolved": true, "answeredBy": "林晓", "chosen": "B", "text": "林晓 选了「B」" }));
        stillfail_shapes::conform::<stillfail_shapes::MessageDecision>(messages[0]["decision"].clone()).unwrap();
        // Written without picking; by the viewer.
        let mut mine = said(3, "person", "都不要");
        mine["mine"] = json!(true);
        let mut messages = vec![asked(2), mine];
        in_messages(&mut messages, Some(None));
        assert_eq!(messages[0]["decision"]["text"], "你 回复了");
        // An option's label without quoting it is a reply.
        let mut messages = vec![asked(2), said(3, "person", "A")];
        in_messages(&mut messages, Some(None));
        assert_eq!(messages[0]["decision"].get("chosen"), None);
        // Replaced by a newer one; the row not known: the messages say.
        let mut messages = vec![asked(2), said(3, "agent", "进度"), asked(4)];
        in_messages(&mut messages, None);
        assert_eq!(messages[0]["decision"], json!({ "resolved": true, "text": "已换成新的问题" }));
        assert_eq!(messages[2]["decision"], json!({ "resolved": false }));
    }

    #[test]
    fn a_picked_option_is_its_label_quoting_the_post() {
        let d = decision(4, false);
        let (text, quotes) = answer(&d, "先不改").unwrap();
        assert_eq!(text, "先不改");
        assert_eq!(quotes, json!([{ "author": "Claude", "text": "**「共」改成按今天累计吗？**\n细节：重连、换中继不清零", "comment": "", "role": "agent", "ts": "9.000002" }]));
        assert!(answer(&d, "别的").is_none());
    }

    #[test]
    fn the_page_puts_those_set_aside_last() {
        let mut items = vec![(json!("c"), 3.0, Some(20.0)), (json!("a"), 5.0, None), (json!("d"), 1.0, Some(10.0)), (json!("b"), 2.0, None)];
        order(&mut items);
        assert_eq!(items.iter().map(|i| i.0.as_str().unwrap()).collect::<Vec<_>>(), ["b", "a", "d", "c"]);
        let prefs = json!({ "decisionsDeferred": { deferral_key("w/s", 7, 4): 12.0 } });
        assert_eq!(deferred_at(&prefs, "w/s", 7, 4), Some(12.0));
        assert_eq!(deferred_at(&prefs, "w/s", 7, 5), None);
    }
}
