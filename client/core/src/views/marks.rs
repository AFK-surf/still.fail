//! What each workspace has waiting for its person, for where workspaces are switched (`Topic::WorkspaceMarks`): of
//! the chats they take part in, those that want them (blocked or failed) and those with something unread; of all its
//! chats, those with a piece of work waiting on them (work.rs); from the chat rows the core keeps
//! in sync of every workspace anyway (sync.rs); and the chat last open in it, to go back to. Only how many and how
//! urgent goes past a workspace: nothing of what its chats say.

use std::collections::BTreeMap;

use serde_json::{Map, Value, json};
use stillfail_i18n::{Lang, t};

use super::Views;
use crate::error::Result;
use crate::protocol::Topic;

/// The workspaces' ids, as the accounts' `/v1/me` list them.
pub(super) fn workspace_ids(workspaces: Option<Value>) -> Vec<String> {
    let entries = workspaces.as_ref().and_then(Value::as_array).cloned().unwrap_or_default();
    entries.iter()
        .flat_map(|a| a.get("workspaces").and_then(Value::as_array).cloned().unwrap_or_default())
        .filter_map(|w| w.get("id").and_then(Value::as_str).map(str::to_string))
        .collect()
}

/// What a chat's row asks of its person: `alert` (its agent failed), `wait` (its agent needs them: need_help), `done`
/// (something in it unread), or nothing; as its mark in the list says (web ChatMark.tsx). Only a chat they take part in
/// (`mine`) asks anything: the others are theirs who are in them. A card waiting counts as `wait` too, for everyone who
/// has not dismissed it (`marks`).
pub fn row_tone(row: &Value) -> Option<&'static str> {
    if row.get("mine").and_then(Value::as_bool) != Some(true) {
        return None;
    }
    let agents = row.get("agents").and_then(Value::as_array).cloned().unwrap_or_default();
    let state = crate::present::row_state(&agents);
    match state {
        Some("failed") => Some("alert"),
        Some("block") => Some("wait"),
        _ => (row.get("unread").and_then(Value::as_bool) == Some(true) && state != Some("run")).then_some("done"),
    }
}

/// The chat last open in a workspace, from the prefs: as the core keeps it (`openChat`), else as a page from before
/// kept its path (`lastChat`: `/w/<workspace>/s/<station>/chats/<key>`).
pub fn last_chat(prefs: &Value, workspace: &str) -> Option<Value> {
    if let Some(chat) = prefs.get("openChat").and_then(|m| m.get(workspace)).filter(|c| c.is_object()) {
        return Some(chat.clone());
    }
    let path = prefs.get("lastChat")?.get(workspace)?.as_str()?;
    let rest = path.strip_prefix(&format!("/w/{workspace}/s/"))?;
    let (station, key) = rest.split_once("/chats/")?;
    let key = crate::accounts::decode_component(key.split(['?', '#', '/']).next()?);
    (!station.is_empty() && !key.is_empty() && !key.starts_with(super::PENDING_PREFIX))
        .then(|| json!({ "station": format!("{workspace}/{station}"), "key": key }))
}

impl Views {
    /// The topics the marks are put together from: the workspaces, the prefs (the chat last open), and of each
    /// workspace its stations' rows.
    pub(super) fn marks_sources(&self) -> Vec<Topic> {
        let mut topics = vec![Topic::Workspaces, Topic::Prefs];
        for id in workspace_ids(self.ok(Topic::Workspaces)) {
            topics.push(Topic::Workspace { workspace: id.clone() });
            if let Some(Ok(stations)) = self.stations(&id) {
                for s in stations {
                    topics.push(Topic::Link { station: s.address.clone() });
                    if s.online {
                        topics.push(Topic::ChatRows { station: s.address });
                    }
                }
            }
        }
        topics
    }

    /// Each workspace's marks, and of those other than `current` (the one in view) the most urgent, for where the
    /// others are reached from.
    pub(super) fn marks(&self, current: Option<&str>) -> Option<Result<Value>> {
        let prefs = self.ok(Topic::Prefs).unwrap_or(Value::Null);
        let mut all = BTreeMap::new();
        let mut others = Counts::default();
        for id in workspace_ids(self.ok(Topic::Workspaces)) {
            let mut counts = Counts::default();
            let mut decisions = 0u64;
            if let Some(Ok(stations)) = self.stations(&id) {
                for s in stations {
                    let rows = self.ok(Topic::ChatRows { station: s.address.clone() }).and_then(|r| r.as_array().cloned()).unwrap_or_default();
                    for row in rows.iter().filter(|r| !self.being_archived(&s.address, r)) {
                        let waits = crate::decisions::for_viewer(row, &self.me(&id)).is_some();
                        decisions += u64::from(waits);
                        match (row_tone(row), waits) {
                            (Some("alert"), _) => counts.alert += 1,
                            (Some("wait"), _) | (_, true) => counts.wait += 1,
                            (Some(_), false) => counts.unread += 1,
                            (None, false) => {}
                        }
                    }
                }
            }
            if current != Some(id.as_str()) {
                others = Counts { alert: others.alert + counts.alert, wait: others.wait + counts.wait, unread: others.unread + counts.unread };
            }
            let mut mark = Map::new();
            mark.insert("alert".into(), json!(counts.alert));
            mark.insert("unread".into(), json!(counts.unread));
            if counts.wait > 0 {
                mark.insert("wait".into(), json!(counts.wait));
            }
            if decisions > 0 {
                mark.insert("decisions".into(), json!(decisions));
            }
            if let Some(tone) = counts.tone() {
                mark.insert("tone".into(), json!(tone));
                mark.insert("label".into(), json!(counts.label()));
            }
            if let Some(chat) = last_chat(&prefs, &id) {
                mark.insert("chat".into(), chat);
            }
            all.insert(id, Value::Object(mark));
        }
        let mut value = json!({ "workspaces": all });
        if let Some(tone) = others.tone() {
            value["others"] = json!(tone);
            value["othersLabel"] = json!(t!("core-views.marks.others", label = others.label()));
        }
        Some(Ok(value))
    }
}

/// How many chats want their person, each counted once by its most urgent: failed (`alert`), a card waiting for them
/// or an agent needing them (`wait`), something unread.
#[derive(Default, Clone, Copy)]
struct Counts {
    alert: u64,
    wait: u64,
    unread: u64,
}

impl Counts {
    fn tone(&self) -> Option<&'static str> {
        if self.alert > 0 { Some("alert") } else if self.wait > 0 { Some("wait") } else if self.unread > 0 { Some("done") } else { None }
    }

    /// 2 个需要处理 · 1 个在等你 · 3 个有新消息
    fn label(&self) -> String {
        self.label_in(stillfail_i18n::current())
    }

    fn label_in(&self, lang: Lang) -> String {
        let mut parts = Vec::new();
        if self.alert > 0 {
            parts.push(t!(lang; "core-views.marks.alert", n = self.alert));
        }
        if self.wait > 0 {
            parts.push(t!(lang; "core-views.marks.wait", n = self.wait));
        }
        if self.unread > 0 {
            parts.push(t!(lang; "core-views.marks.unread", n = self.unread));
        }
        parts.join(" · ")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn agent(status: &str) -> Value {
        match status {
            "running" => json!({ "key": "k", "process": "running" }),
            "blocked" => json!({ "key": "k", "lastTurn": { "declared": "block" } }),
            _ => json!({ "key": "k" }),
        }
    }

    #[test]
    fn only_a_row_its_person_takes_part_in_wants_them() {
        assert_eq!(row_tone(&json!({ "mine": true, "agents": [agent("blocked")] })), Some("wait"), "need_help: it waits for them, nothing went wrong");
        assert_eq!(row_tone(&json!({ "mine": true, "agents": [{ "key": "k", "lastTurn": { "outcome": "failed" } }] })), Some("alert"));
        assert_eq!(row_tone(&json!({ "mine": false, "agents": [agent("blocked")] })), None);
        assert_eq!(row_tone(&json!({ "mine": true, "unread": true, "agents": [] })), Some("done"));
        assert_eq!(row_tone(&json!({ "mine": false, "unread": true, "agents": [] })), None);
        assert_eq!(row_tone(&json!({ "mine": true, "unread": true, "agents": [agent("running")] })), None);
        assert_eq!(row_tone(&json!({ "mine": true, "agents": [] })), None);
        assert_eq!(row_tone(&json!({ "mine": true, "agents": [agent("blocked")], "decision": { "seq": 4 } })), Some("wait"));
    }

    #[test]
    fn the_chat_last_open_is_the_cores_else_the_path_a_page_kept() {
        let kept = json!({ "openChat": { "ws": { "station": "ws/a", "key": "k1" } }, "lastChat": { "ws": "/w/ws/s/b/chats/k2" } });
        assert_eq!(last_chat(&kept, "ws"), Some(json!({ "station": "ws/a", "key": "k1" })));
        let old = json!({ "lastChat": { "ws": "/w/ws/s/b/chats/thread%3A7", "x": "/w/x/new", "y": "/w/y/s/c/chats/new%3A1" } });
        assert_eq!(last_chat(&old, "ws"), Some(json!({ "station": "ws/b", "key": "thread:7" })));
        assert_eq!(last_chat(&old, "x"), None);
        assert_eq!(last_chat(&old, "y"), None);
        assert_eq!(last_chat(&old, "z"), None);
    }

    #[test]
    fn marks_say_how_many_and_how_urgent() {
        let counts = |alert, wait, unread| Counts { alert, wait, unread };
        assert_eq!(counts(1, 1, 3).tone(), Some("alert"));
        assert_eq!(counts(0, 1, 3).tone(), Some("wait"));
        assert_eq!(counts(0, 0, 3).tone(), Some("done"));
        assert_eq!(counts(0, 0, 0).tone(), None);
        assert_eq!(counts(2, 0, 3).label(), "2 个需要处理 · 3 个有新消息");
        assert_eq!(counts(0, 1, 1).label(), "1 个在等你 · 1 个有新消息");
        assert_eq!(counts(0, 0, 1).label(), "1 个有新消息");
    }

    #[test]
    fn marks_are_said_in_english_too() {
        let counts = |alert, wait, unread| Counts { alert, wait, unread };
        assert_eq!(counts(2, 1, 1).label_in(Lang::En), "2 need attention · 1 waiting for you · 1 with new messages");
        assert_eq!(counts(1, 0, 3).label_in(Lang::En), "1 needs attention · 3 with new messages");
        assert_eq!(counts(0, 0, 1).label_in(Lang::Zh), "1 个有新消息");
    }
}
