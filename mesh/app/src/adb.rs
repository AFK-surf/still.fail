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

/// What the agent is told: the phones, and how to use them.
fn listed(phones: Vec<Value>) -> String {
    if phones.is_empty() {
        return "No phone is shared with this station now. A person shares theirs from the still.fail Android app (the station's page, 共享调试); ask them to if you need one.".into();
    }
    let mut text = format!("{}\n\n", serde_json::to_string_pretty(&Value::Array(phones)).unwrap_or_default());
    text.push_str("Use a phone with `adb -s <serial> …` (adb is this machine's). adb \"connected\" is ready; \"unpaired\" means its person still has to pair it in the app (Wireless debugging › 使用配对码配对设备); after `adb kill-server` run `adb connect <serial>` again. A phone is its owner's: use it for what they asked, and it goes when they stop sharing it.");
    text
}

pub fn tools() -> Vec<Tool> {
    let run: Run = Arc::new(|_key, _args| Box::pin(async move { Ok(listed(LISTER.get().map(|list| list()).unwrap_or_default())) }));
    vec![Tool {
        name: "adb_devices".into(),
        description: "The Android phones people shared with this station's agents (from the still.fail app), each with the adb serial it is reached at on this machine (127.0.0.1:<port>), its model, owner and whether adb is connected.".into(),
        input_schema: json!({ "type": "object", "properties": {}, "additionalProperties": false }),
        run,
    }]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn says_how_to_reach_each_phone_and_what_to_do_without_one() {
        assert!(listed(Vec::new()).starts_with("No phone is shared"));
        let text = listed(vec![json!({ "serial": "127.0.0.1:37123", "adb": "connected" })]);
        assert!(text.contains("127.0.0.1:37123") && text.contains("adb -s <serial>"));
    }
}
