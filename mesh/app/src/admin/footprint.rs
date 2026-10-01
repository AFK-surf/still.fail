//! Compatibility response for clients released before footprint statistics were retired.
use serde_json::{Value, json};

pub(super) fn retired() -> Value {
    json!({
        "checkedAt": null, "tookMs": null, "scanning": false, "manage": false,
        "disk": { "totalBytes": 0, "freeBytes": 0 },
        "parts": [], "elsewhere": [], "chats": [],
        "unseen": { "count": 0, "bytes": 0 },
        "memory": { "totalBytes": 0, "usedBytes": 0, "stationBytes": 0 },
        "processes": [],
    })
}
