//! What a person set going on this device and the core has not finished (the `doing` topic): every call that changes
//! something (a chat pinned, a job stopped, a member's role) from the moment it is asked until its answer, whichever
//! page or menu asked it. The pages show it where it is, on the row or button it is about, at once: a person sees
//! that what they did is under way, and does not do it again.

use std::cell::{Cell, RefCell};
use std::collections::HashMap;

use serde_json::{json, Value};

use crate::core::Call;

struct Entry {
    id: u64,
    call: String,
    /// Its params that are words, numbers or yes/no, as words: what a page matches it by (`station`, `id`, `session`…).
    params: HashMap<String, String>,
    since: f64,
}

#[derive(Default)]
pub struct Doing {
    next: Cell<u64>,
    list: RefCell<Vec<Entry>>,
}

impl Doing {
    /// One begun; `end` it with what this gives.
    pub fn start(&self, call: &str, params: &Value, now: f64) -> u64 {
        let id = self.next.get() + 1;
        self.next.set(id);
        let params = params.as_object().into_iter().flatten().filter_map(|(k, v)| words(v).map(|v| (k.clone(), v))).collect();
        self.list.borrow_mut().push(Entry { id, call: call.to_string(), params, since: now });
        id
    }

    pub fn end(&self, id: u64) {
        self.list.borrow_mut().retain(|e| e.id != id);
    }

    /// The topic's value: what is under way, oldest first.
    pub fn value(&self) -> Value {
        let doing: Vec<Value> = self.list.borrow().iter().map(|e| json!({ "call": e.call, "params": e.params, "since": e.since as i64 })).collect();
        json!({ "doing": doing })
    }
}

fn words(v: &Value) -> Option<String> {
    match v {
        Value::String(s) => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        Value::Bool(b) => Some(b.to_string()),
        _ => None,
    }
}

/// Whether a call is one a person does and waits on: it changes something, or it is a step they asked for (跳到最新,
/// 重试). Reads, what pages do by themselves (drafts, places, previews) and what changes only this device at once are
/// not.
pub(crate) fn counts(call: &Call, name: &str) -> bool {
    match call {
        Call::Op(op) => op.method != "GET" && !matches!(name, "session.warm" | "widget.setState" | "login.drop"),
        Call::ChatArchive { .. } | Call::ChatRetry { .. } | Call::ChatRetryIn { .. } | Call::ChatDiscard { .. } | Call::ChatDiscardIn { .. } => true,
        Call::ChatLatest { .. } | Call::SignOut { .. } | Call::AuthBegin { .. } => true,
        Call::Wake { retry, .. } => *retry,
        Call::Choose { name, .. } => name == "pick.save",
        Call::Attend(_) => name == "notify.set",
        Call::Ask(_) => name == "dev.signIn",
        _ => false,
    }
}

/// Calls whose params are too big to keep a copy of while they run (files, pages, messages).
pub(crate) fn heavy(name: &str) -> bool {
    matches!(name, "station.upload" | "station.preview" | "preview.socket.send" | "draft.put" | "chat.send" | "migrate" | "push.register")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_what_is_under_way_with_its_plain_params() {
        let doing = Doing::default();
        let a = doing.start("job.stop", &json!({ "station": "w/s", "id": "j1", "input": { "x": 1 } }), 1000.5);
        let b = doing.start("chat.pin", &json!({ "station": "w/s", "session": "k", "pinned": true, "thread": 7 }), 2000.0);
        assert_eq!(doing.value(), json!({ "doing": [
            { "call": "job.stop", "params": { "station": "w/s", "id": "j1" }, "since": 1000 },
            { "call": "chat.pin", "params": { "station": "w/s", "session": "k", "pinned": "true", "thread": "7" }, "since": 2000 },
        ] }));
        doing.end(a);
        doing.end(b);
        assert_eq!(doing.value(), json!({ "doing": [] }));
    }
}
