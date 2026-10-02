//! What a person set going on this device and the core has not finished (the `doing` topic): every call that changes
//! something (a chat pinned, a job stopped, a mstill.fail's role) from the moment it is asked until its answer, whichever
//! page or menu asked it. The pages show it where it is, on the row or button it is about, at once: a person sees
//! that what they did is under way, and does not do it again. One that failed stays a few seconds more, with why
//! (`stage` failed, `error`), so the place that turned says so too, whoever asked it. A write whose station went
//! quiet before it answered is asked again once the station is back (station.rs `RECHECK_MS`): meanwhile its stage is
//! `rechecking`, with what it waits on (`note`).

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
    /// Why it failed, while that is still shown.
    failed: Option<String>,
}

/// How long a failure stays where it was asked.
pub const FAILED_SHOWN_MS: u64 = 6_000;

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
        self.list.borrow_mut().push(Entry { id, call: call.to_string(), params, since: now, failed: None });
        id
    }

    pub fn end(&self, id: u64) {
        self.list.borrow_mut().retain(|e| e.id != id);
    }

    /// It failed: shown so, with why, until it is `end`ed (`FAILED_SHOWN_MS` later).
    pub fn fail(&self, id: u64, why: &str) {
        if let Some(e) = self.list.borrow_mut().iter_mut().find(|e| e.id == id) {
            e.failed = Some(why.to_string());
        }
    }

    /// The topic's value: what is under way, oldest first; `rechecking` says of a call's params whether its station is
    /// being waited on to say whether it was done.
    pub fn value(&self, rechecking: &dyn Fn(&HashMap<String, String>) -> bool) -> Value {
        let doing: Vec<Value> = self.list.borrow().iter().map(|e| {
            let stage = if e.failed.is_some() { "failed" } else if rechecking(&e.params) { "rechecking" } else { "running" };
            let mut item = json!({ "call": e.call, "params": e.params, "since": e.since as i64, "stage": stage });
            if stage == "rechecking" {
                item["note"] = json!(stillfail_i18n::t!("core-misc.doing.rechecking"));
            }
            if let Some(why) = &e.failed {
                item["error"] = json!(why);
            }
            item
        }).collect();
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
        Call::ConnectFlow { action, .. } => matches!(action.as_str(), "config" | "make" | "verify" | "create"),
        Call::SlackTokens { action, .. } => action == "verify",
        Call::ProfileModels { .. } => true,
        Call::Op(op) => op.method != "GET" && !matches!(name, "session.warm" | "widget.setState" | "login.drop"),
        Call::ChatArchive { .. } | Call::ChatRetry { .. } | Call::ChatRetryIn { .. } | Call::ChatDiscard { .. } | Call::ChatDiscardIn { .. } => true,
        Call::ChatLatest { .. } | Call::SignOut { .. } | Call::AuthBegin { .. } | Call::StationMeasure { .. } => true,
        // A card answered: its button or field turns while the message goes.
        Call::DecisionAnswer { .. } | Call::DecisionReply { .. } => true,
        Call::Wake { retry, .. } => *retry,
        Call::Choose { name, .. } => name == "pick.save",
        Call::Attend(_) => name == "notify.set",
        Call::Ask(_) => name == "dev.signIn",
        // A pairing, a grant: the station's adb takes a few seconds.
        Call::Adb(crate::adb::Call::Pair { .. } | crate::adb::Call::Grant) => true,
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
        assert_eq!(doing.value(&|_| false), json!({ "doing": [
            { "call": "job.stop", "params": { "station": "w/s", "id": "j1" }, "since": 1000, "stage": "running" },
            { "call": "chat.pin", "params": { "station": "w/s", "session": "k", "pinned": "true", "thread": "7" }, "since": 2000, "stage": "running" },
        ] }));
        doing.fail(a, "连不上这台 station：没有回应");
        assert_eq!(doing.value(&|_| false)["doing"][0], json!({ "call": "job.stop", "params": { "station": "w/s", "id": "j1" }, "since": 1000, "stage": "failed", "error": "连不上这台 station：没有回应" }));
        doing.end(a);
        doing.end(b);
        assert_eq!(doing.value(&|_| false), json!({ "doing": [] }));
    }
}
