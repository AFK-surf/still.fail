//! Phones lent to this station's agents (docs/adb-share.md): the station process (stillfail-station's adb.rs) holds
//! them and says which they are (`register`); the `adb_devices` tool tells an agent, each with the serial its adb
//! reaches it at.

use std::sync::{Arc, OnceLock};

use serde_json::{Value, json};

use crate::mcp::{Run, Tool};

/// The phones offered now: `{serial, device, android, owner: {name, email}, adb, message}` each.
pub type Lister = Arc<dyn Fn() -> Vec<Value> + Send + Sync>;

static LISTER: OnceLock<Lister> = OnceLock::new();

/// Who knows the phones: the station process, once it is in still.fail cloud. Until then there are none.
pub fn register(lister: Lister) {
    let _ = LISTER.set(lister);
}

/// Where a person opens this station's 共享调试 (the still.fail Android app takes the link), once the station is in a
/// workspace.
pub type Page = Arc<dyn Fn() -> Option<String> + Send + Sync>;

/// What the agent is told: the phones, how to use them, and how to ask for one.
fn listed(phones: Vec<Value>, page: Option<String>) -> String {
    let ask = match page {
        Some(link) => format!("To ask a person for their phone (or to pair it), send them this link in the conversation: {link} — it opens this station's 共享调试 page in their still.fail Android app, where they tap 开始共享."),
        None => "A person shares their phone from the still.fail Android app: this station's page, 共享调试.".into(),
    };
    if phones.is_empty() {
        return format!("No phone is shared with this station now. {ask}");
    }
    let mut text = format!("{}\n\n", serde_json::to_string_pretty(&Value::Array(phones)).unwrap_or_default());
    text.push_str("Use a phone with `adb -s <serial> …` (adb is this machine's). adb \"connected\" is ready; \"unpaired\" means its person still has to pair it in the app (Wireless debugging › 使用配对码配对设备); after `adb kill-server` run `adb connect <serial>` again. A phone is its owner's: use it for what they asked, and it goes when they stop sharing it. ");
    text.push_str(&ask);
    text
}

pub fn tools(page: Page) -> Vec<Tool> {
    let run: Run = Arc::new(move |_key, _args| {
        let page = page.clone();
        Box::pin(async move { Ok(listed(LISTER.get().map(|list| list()).unwrap_or_default(), page())) })
    });
    vec![Tool {
        name: "adb_devices".into(),
        description: "The Android phones people shared with this station's agents (from the still.fail app), each with the adb serial it is reached at on this machine (127.0.0.1:<port>), its model, owner and whether adb is connected; and the link that opens this station's 共享调试 page in a person's app, to ask them for theirs.".into(),
        input_schema: json!({ "type": "object", "properties": {}, "additionalProperties": false }),
        run,
    }]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn says_how_to_reach_each_phone_and_what_to_do_without_one() {
        let page = Some("https://app.still.fail/w/w1/s/st1/adb".to_string());
        let none = listed(Vec::new(), page.clone());
        assert!(none.starts_with("No phone is shared") && none.contains("https://app.still.fail/w/w1/s/st1/adb"));
        let text = listed(vec![json!({ "serial": "127.0.0.1:37123", "adb": "connected" })], page);
        assert!(text.contains("127.0.0.1:37123") && text.contains("adb -s <serial>") && text.contains("/s/st1/adb"));
        assert!(!listed(Vec::new(), None).contains("http"));
    }
}
