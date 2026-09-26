//! A thread's entries merged into its messages: the one place edits are
//! applied (docs/station-storage.md, Append-only threads). A message shows its
//! latest edit's text, attachments and quotes, marked edited. Nothing is taken
//! back: ember has no delete.

use std::collections::BTreeMap;

use serde_json::{Value, json};

/// An entry's number in its thread.
pub fn n_of(entry: &Value) -> Option<u64> {
    entry.get("n").and_then(Value::as_u64)
}

/// The messages of a run of entries, in thread order, as `MessageView`s (`seq` is the message's n). Edits of
/// messages before the run are left out: those messages are not in it.
pub fn merge(entries: &[Value]) -> Vec<Value> {
    let mut messages: BTreeMap<u64, Value> = BTreeMap::new();
    for entry in entries {
        let Some(n) = n_of(entry) else { continue };
        let field = |name: &str| entry.get(name).cloned().unwrap_or(Value::Null);
        match entry.get("kind").and_then(Value::as_str) {
            Some("message") => {
                messages.insert(n, json!({
                    "seq": n, "thread": field("thread"), "ts": field("ts"), "authorKind": field("authorKind"), "author": field("author"),
                    "authorName": field("authorName"), "text": entry.get("text").cloned().unwrap_or(json!("")),
                    "attachments": entry.get("attachments").cloned().unwrap_or(json!([])), "quotes": entry.get("quotes").cloned().unwrap_or(json!([])),
                    "declared": field("declared"), "createdAt": field("at"), "editedAt": null,
                }));
            }
            Some("edit") => {
                let Some(message) = entry.get("target").and_then(Value::as_u64).and_then(|t| messages.get_mut(&t)) else { continue };
                message["text"] = entry.get("text").cloned().unwrap_or(json!(""));
                message["attachments"] = entry.get("attachments").cloned().unwrap_or(json!([]));
                message["quotes"] = entry.get("quotes").cloned().unwrap_or(json!([]));
                message["editedAt"] = field("at");
            }
            _ => {}
        }
    }
    messages.into_values().collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn message(n: u64, text: &str) -> Value {
        json!({"thread": 7, "n": n, "kind": "message", "target": null, "ts": format!("{n}.0"), "authorKind": "person", "author": "a@x.com",
            "authorName": "阿", "text": text, "attachments": [], "quotes": [], "declared": null, "at": n * 10})
    }

    fn change(n: u64, kind: &str, target: u64, text: Option<&str>) -> Value {
        json!({"thread": 7, "n": n, "kind": kind, "target": target, "ts": null, "authorKind": "person", "author": "a@x.com",
            "authorName": "阿", "text": text, "attachments": [{"name": "b.png"}], "quotes": [], "declared": null, "at": n * 10})
    }

    #[test]
    fn edits_merge_into_their_messages() {
        let entries = [message(1, "一"), message(2, "二"), change(3, "edit", 1, Some("一（改）")), message(4, "三"), change(5, "edit", 1, Some("一（再改）")), message(6, "四")];
        let merged = merge(&entries);
        assert_eq!(merged.iter().map(|m| (m["seq"].as_u64().unwrap(), m["text"].as_str().unwrap())).collect::<Vec<_>>(), vec![(1, "一（再改）"), (2, "二"), (4, "三"), (6, "四")]);
        assert_eq!(merged[0]["editedAt"], 50);
        assert_eq!(merged[0]["createdAt"], 10);
        assert_eq!(merged[0]["attachments"], json!([{"name": "b.png"}]), "an edit gives the message's whole new version");
        assert_eq!(merged[1]["editedAt"], Value::Null);
        assert_eq!(merged[1]["authorName"], "阿");
        // Changes to messages before the run have nothing to change.
        assert_eq!(merge(&entries[2..]).iter().map(|m| m["seq"].clone()).collect::<Vec<_>>(), vec![json!(4), json!(6)]);
    }
}
