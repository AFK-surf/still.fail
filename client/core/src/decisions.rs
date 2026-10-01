//! Cards: what an agent's post asks people to answer it with (chat_post `card`): options to pick from (`options`), or
//! a field to write in (`text`). A card is the message's, whatever the turn's state (that is the agent's: need_help
//! after posting one). It waits until a person writes in the chat after it (picking an option, or writing in a text
//! card's field, sends a message quoting it; any other message answers it too), or a newer card replaces it; the
//! station says which one waits on each chat's row (`card`; an options card is the row's `decision` too, and a station
//! from before cards has only that). Here, for the viewer: the row's card and line (奏 · …), how each card in a chat's
//! messages stands, the options in the order they are shown (the one the agent recommends last), and the 奏 page (the
//! `decisions` topic: pending cards not dismissed, those set aside last). Setting one aside (待定, `decision.defer`) is
//! kept on the device with the prefs (`decisionsDeferred`); dismissing one (`decision.dismiss`) is kept by the station
//! for the viewer, on every device of theirs. The calls and the topic keep the names they had when the only cards were
//! decisions.

use serde_json::{Map, Value, json};

/// How much of a card's first line its line shows.
const LINE_CHARS: usize = 40;

/// Where a deferral is kept in the prefs (`decisionsDeferred`): the card's station, chat (thread) and post (seq).
pub fn deferral_key(station: &str, thread: u64, seq: u64) -> String {
    format!("{station}\t{thread}\t{seq}")
}

/// When the viewer set a card aside on this device, if they did.
pub fn deferred_at(prefs: &Value, station: &str, thread: u64, seq: u64) -> Option<f64> {
    prefs.get("decisionsDeferred")?.get(deferral_key(station, thread, seq))?.as_f64()
}

/// The answers an options card offers, as the clients show them (`DecisionOption`): each with a label, in the agent's
/// order with the recommended one moved last; those without a label left out.
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

/// A card's type: options, text, or one this core does not know (shown as a plain reply).
pub fn kind(card: &Value) -> &str {
    card.get("type").and_then(Value::as_str).unwrap_or("")
}

/// Options to pick from as a card (a station's from before cards).
fn options_card(options: &Value) -> Value {
    json!({ "type": "options", "options": options })
}

/// The card a message carries, as its station gives it: its `card`, else its `options` (from before cards) as an
/// options card.
pub fn of_message(m: &Value) -> Option<Value> {
    if let Some(card) = m.get("card").filter(|c| c.get("type").and_then(Value::as_str).is_some()) {
        return Some(card.clone());
    }
    m.get("options").filter(|o| o.as_array().is_some_and(|o| !o.is_empty())).map(options_card)
}

/// A card as the clients show it (`MessageCard`): its type, an options card's options as shown, a text card's
/// placeholder.
pub fn card_shown(card: &Value) -> Value {
    let mut v = json!({ "type": kind(card) });
    match kind(card) {
        "options" => v["options"] = json!(options_shown(&card["options"])),
        "text" => {
            if let Some(p) = card.get("placeholder").and_then(Value::as_str).map(str::trim).filter(|p| !p.is_empty()) {
                v["placeholder"] = json!(p);
            }
        }
        _ => {}
    }
    v
}

/// A card's line: 奏 · its post's first line, without mentions or markup, cut to about 40 characters.
pub fn line(text: &str) -> String {
    let first = text.lines().map(str::trim).find(|l| !l.is_empty()).unwrap_or("");
    let clean = crate::format::clean_text(first).replace("**", "").replace("__", "").replace('`', "");
    let clean = clean.trim_start_matches(['#', '>', '-', '*', ' ']).trim();
    let cut: String = clean.chars().take(LINE_CHARS).collect();
    let cut = if clean.chars().count() > LINE_CHARS { format!("{}…", cut.trim_end()) } else { cut };
    if cut.is_empty() { "奏".to_string() } else { format!("奏 · {cut}") }
}

/// The card a row waits on, as its station gives it: `{seq, card, dismissed?, message, before}`. From its `card`; else
/// its `decision` (a station from before cards; or a row the core has put together already), whose options are an
/// options card.
pub fn of_row(row: &Value) -> Option<Value> {
    let has_seq = |v: &&Value| v.get("seq").and_then(Value::as_u64).is_some();
    if let Some(card) = row.get("card").filter(has_seq).filter(|c| c.get("card").is_some_and(Value::is_object)) {
        return Some(card.clone());
    }
    let decision = row.get("decision").filter(has_seq)?;
    let mut v = decision.clone();
    if !v.get("card").is_some_and(Value::is_object) {
        v["card"] = options_card(&decision["options"]);
    }
    Some(v)
}

/// Whether the viewer dismissed it.
pub fn dismissed(card: &Value) -> bool {
    card.get("dismissed").and_then(Value::as_bool) == Some(true)
}

/// The card a row has waiting for the viewer: pending, and not dismissed by them.
pub fn pending(row: &Value) -> Option<Value> {
    of_row(row).filter(|c| !dismissed(c))
}

/// Whether a row has a card waiting for the viewer.
pub fn waits(row: &Value) -> bool {
    pending(row).is_some()
}

/// A row's mark, the most urgent first: alert (an agent failed), wait (a card waits for the viewer, or an agent needs
/// a person: need_help), busy (at work), done (something unread); none otherwise. Its `state` is the row's (present.rs
/// `row_state`).
pub fn tone(row: &Value) -> Option<&'static str> {
    let state = row.get("state").and_then(Value::as_str);
    if state == Some("failed") {
        return Some("alert");
    }
    if waits(row) || state == Some("block") {
        return Some("wait");
    }
    if state == Some("run") {
        return Some("busy");
    }
    (row.get("unread").and_then(Value::as_bool) == Some(true)).then_some("done")
}

/// A row's card as the clients show it (`RowDecision`): its seq, the card as shown (and an options card's options, as
/// before cards), whether dismissed, and its line while it waits for the viewer.
pub fn shown(card: &Value) -> Value {
    let shown = card_shown(&card["card"]);
    let options = shown.get("options").cloned().unwrap_or(json!([]));
    let mut v = json!({ "seq": card["seq"], "options": options, "card": shown });
    if dismissed(card) {
        v["dismissed"] = json!(true);
    } else {
        v["text"] = json!(line(card.get("message").and_then(|m| m.get("text")).and_then(Value::as_str).unwrap_or("")));
    }
    v
}

/// Puts in a row what the clients show of its card (`decision`, as [`shown`]; the station's own `card` goes) and its
/// mark (`tone`).
pub fn present(row: &mut Value) {
    let card = of_row(row);
    if let Some(map) = row.as_object_mut() {
        map.remove("card");
        map.remove("decision");
    }
    if let Some(card) = card {
        row["decision"] = shown(&card);
    }
    if let Some(tone) = tone(row) {
        row["tone"] = json!(tone);
    }
}

/// Where each card in a chat's messages stands (`ChatMessage::card`, `options`, `decision`), messages decorated as the
/// chat shows them (with `by` and `mine`). `pending`: the seq of the one its row says waits, and whether the viewer
/// dismissed it; `None` when the row is not known (then the messages loaded say: none of a person after it, nor a
/// newer card).
pub fn in_messages(messages: &mut [Value], pending: Option<Option<(u64, bool)>>) {
    let cards: Vec<(usize, Value)> = (0..messages.len()).filter_map(|i| of_message(&messages[i]).map(|c| (i, c))).collect();
    for (at, (i, card)) in cards.iter().enumerate() {
        let i = *i;
        let seq = messages[i].get("seq").and_then(Value::as_u64).unwrap_or(0);
        let ts = messages[i].get("ts").and_then(Value::as_str).unwrap_or("").to_string();
        let shown = card_shown(card);
        let options = shown.get("options").and_then(Value::as_array).cloned().unwrap_or_default();
        let answer = messages[i + 1..].iter().find(|m| m.get("authorKind").and_then(Value::as_str) == Some("person"));
        let replaced = at + 1 < cards.len();
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
        // An options card's options, as before cards: what UIs draw under the message.
        if kind(card) == "options" {
            m.insert("options".into(), json!(options));
        } else {
            m.remove("options");
        }
        m.insert("card".into(), shown);
        m.insert("decision".into(), decision);
    }
}

/// The quote an answer to a card carries: the post that asked (whole, as the agent's own message: its ts says exactly
/// which).
fn quote_of(card: &Value) -> Option<Value> {
    let message = card.get("message").filter(|m| m.is_object())?;
    let text = message.get("text").and_then(Value::as_str).unwrap_or("");
    let author = message.get("authorName").and_then(Value::as_str).filter(|a| !a.is_empty()).unwrap_or("agent");
    let mut quote = json!({ "author": author, "text": text, "comment": "", "role": "agent" });
    if let Some(ts) = message.get("ts").and_then(Value::as_str).filter(|t| !t.is_empty()) {
        quote["ts"] = json!(ts);
    }
    Some(json!([quote]))
}

/// The text and quote a picked option sends (`decision.answer`): the option's label, quoting the post that asked. Only
/// for an options card offering it.
pub fn answer(card: &Value, option: &str) -> Option<(String, Value)> {
    if kind(&card["card"]) != "options" {
        return None;
    }
    let options = options_shown(&card["card"]["options"]);
    let label = options.iter().filter_map(|o| o.get("label").and_then(Value::as_str)).find(|l| *l == option.trim())?.to_string();
    Some((label, quote_of(card)?))
}

/// The text and quote a text card's answer sends (`decision.reply`): what the viewer wrote, quoting the post that
/// asked. Only for a text card.
pub fn reply(card: &Value, text: &str) -> Option<(String, Value)> {
    if kind(&card["card"]) != "text" || text.trim().is_empty() {
        return None;
    }
    Some((text.trim().to_string(), quote_of(card)?))
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

    /// A row's card as a station from before cards gives it (`decision`).
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

    /// A row's text card, as a station gives it (`card`).
    fn text_card(seq: u64) -> Value {
        json!({ "seq": seq, "card": { "type": "text", "placeholder": " sk_test_… " },
            "message": { "seq": seq, "ts": "9.000003", "text": "Stripe 的测试 key 是多少？", "authorName": "Claude" }, "before": [] })
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
    fn a_cards_line_is_its_first_line_cut_short() {
        assert_eq!(line("**「共」改成按今天累计吗？**\n细节"), "奏 · 「共」改成按今天累计吗？");
        assert_eq!(line("\n\n## 选哪个"), "奏 · 选哪个");
        let long = "字".repeat(50);
        assert_eq!(line(&long), format!("奏 · {}…", "字".repeat(40)));
        assert_eq!(line(""), "奏");
    }

    #[test]
    fn a_rows_card_is_read_from_its_card_else_its_decision() {
        // From a station before cards: its options are an options card.
        let row = json!({ "decision": decision(4, false) });
        assert_eq!(kind(&of_row(&row).unwrap()["card"]), "options");
        // Its card first.
        let row = json!({ "decision": decision(4, false), "card": text_card(5) });
        assert_eq!((of_row(&row).unwrap()["seq"].clone(), kind(&of_row(&row).unwrap()["card"]).to_string()), (json!(5), "text".to_string()));
        assert!(of_row(&json!({ "card": null, "decision": null })).is_none());
        // A message's: its card, else its options.
        assert_eq!(of_message(&json!({ "options": [{ "label": "A" }] })), Some(json!({ "type": "options", "options": [{ "label": "A" }] })));
        assert_eq!(of_message(&json!({ "card": { "type": "text" } })), Some(json!({ "type": "text" })));
        assert_eq!(of_message(&json!({ "options": [] })), None);
        assert_eq!(card_shown(&json!({ "type": "text", "placeholder": " sk_… " })), json!({ "type": "text", "placeholder": "sk_…" }));
        stillfail_shapes::conform::<stillfail_shapes::MessageCard>(card_shown(&of_message(&json!({ "options": [{ "label": "A" }] })).unwrap())).unwrap();
    }

    #[test]
    fn a_row_with_a_card_says_so_and_is_marked_wait_until_dismissed() {
        let mut row = json!({ "state": "run", "unread": true, "decision": decision(4, false) });
        present(&mut row);
        assert_eq!(row["tone"], "wait", "a card waits for the viewer, whatever the agent does");
        assert_eq!(row["decision"]["text"], "奏 · 「共」改成按今天累计吗？");
        assert_eq!(row["decision"]["options"][2]["label"], "按今天累计");
        assert_eq!(row["decision"]["card"]["type"], "options");
        assert_eq!(row["decision"].get("message"), None, "the rows carry only what they show");
        stillfail_shapes::conform::<stillfail_shapes::RowDecision>(row["decision"].clone()).unwrap();
        // Read again from what it shows (the marks, the notices read presented rows too).
        assert_eq!(of_row(&row).map(|c| c["seq"].clone()), Some(json!(4)));
        // A text card: no options, its placeholder; the station's own `card` goes.
        let mut row = json!({ "state": null, "card": text_card(6) });
        present(&mut row);
        assert_eq!((row.get("card"), row["decision"]["options"].clone(), row["decision"]["card"].clone()), (None, json!([]), json!({ "type": "text", "placeholder": "sk_test_…" })));
        assert_eq!(row["tone"], "wait");
        // Dismissed: no line, no mark from it.
        let mut row = json!({ "state": null, "unread": false, "decision": decision(4, true) });
        present(&mut row);
        assert_eq!((row.get("tone"), row["decision"].get("text"), row["decision"]["dismissed"].clone()), (None, None, json!(true)));
        let mut row = json!({ "state": null, "unread": true, "decision": decision(4, true) });
        present(&mut row);
        assert_eq!(row["tone"], "done");
        // need_help is a wait (blue), with a card or not; failed an alert, always.
        assert_eq!(tone(&json!({ "state": "block" })), Some("wait"));
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

    fn typed(seq: u64) -> Value {
        let mut m = said(seq, "agent", "key？");
        m["card"] = json!({ "type": "text", "placeholder": "sk_" });
        m
    }

    #[test]
    fn cards_in_a_chat_say_whether_they_wait_and_who_answered_how() {
        // As the row says: the one it names waits, dismissed or not.
        let mut messages = vec![said(1, "person", "做吧"), asked(2), said(3, "agent", "顺便说下进度")];
        in_messages(&mut messages, Some(Some((2, true))));
        assert_eq!(messages[1]["decision"], json!({ "resolved": false, "dismissed": true }));
        assert_eq!(messages[1]["options"], json!([{ "label": "B" }, { "label": "A", "recommended": true }]));
        assert_eq!(messages[1]["card"], json!({ "type": "options", "options": [{ "label": "B" }, { "label": "A", "recommended": true }] }));
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
        // Replaced by a newer card, of another type; the row not known: the messages say.
        let mut messages = vec![asked(2), said(3, "agent", "进度"), typed(4)];
        in_messages(&mut messages, None);
        assert_eq!(messages[0]["decision"], json!({ "resolved": true, "text": "已换成新的问题" }));
        assert_eq!(messages[2]["decision"], json!({ "resolved": false }));
        assert_eq!((messages[2]["card"].clone(), messages[2].get("options")), (json!({ "type": "text", "placeholder": "sk_" }), None));
        // A text card answered: who replied.
        let mut messages = vec![typed(2), said(3, "person", "sk_test_1")];
        in_messages(&mut messages, Some(None));
        assert_eq!(messages[0]["decision"], json!({ "resolved": true, "answeredBy": "林晓", "text": "林晓 回复了" }));
    }

    #[test]
    fn a_picked_option_or_a_written_answer_quotes_the_post() {
        let d = of_row(&json!({ "decision": decision(4, false) })).unwrap();
        let (text, quotes) = answer(&d, "先不改").unwrap();
        assert_eq!(text, "先不改");
        assert_eq!(quotes, json!([{ "author": "Claude", "text": "**「共」改成按今天累计吗？**\n细节：重连、换中继不清零", "comment": "", "role": "agent", "ts": "9.000002" }]));
        assert!(answer(&d, "别的").is_none());
        assert!(reply(&d, "随便").is_none(), "an options card is answered by picking");
        let t = text_card(5);
        let (text, quotes) = reply(&t, "  sk_test_123 ").unwrap();
        assert_eq!((text.as_str(), quotes[0]["ts"].clone()), ("sk_test_123", json!("9.000003")));
        assert!(reply(&t, " ").is_none());
        assert!(answer(&t, "sk").is_none(), "a text card has no options");
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
