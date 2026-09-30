//! What a person hears about while a client runs (the `notices` topic; docs/notifications.md): a chat of theirs
//! whose agent is blocked on them, went wrong (the station's ⚠️ in it), or finished with something new to read, or where someone else said
//! something. Noticed from the chat rows the core keeps in sync anyway (sync.rs), by how each row changed; a
//! station's first rows are where it starts from. Each workspace hears of its own (workspace.rs): a workspace's
//! `notices` are its chats', the plain topic every workspace's.

use std::cell::Cell;
use std::collections::{HashMap, VecDeque};
use std::rc::Rc;

use serde_json::{Value, json};

use crate::host::Host;
use crate::protocol::Topic;
use crate::store::Store;
use crate::views::EmailOf;
use crate::workspace::{Workspace, Workspaces};

/// How many notices a workspace holds, and the plain topic.
const KEEP: usize = 20;
/// How long a notice's body may be, in characters.
const BODY: usize = 140;

/// How a row stood when last looked at.
#[derive(Clone, Debug, PartialEq)]
struct Seen {
    state: Option<&'static str>,
    /// The last message it has noticed (or found there at first).
    seq: i64,
}

/// What a workspace has heard of its chats: how each of its stations' rows stood when last looked at, by id, and
/// its notices, oldest first.
#[derive(Default)]
pub struct Heard {
    seen: HashMap<String, HashMap<String, Seen>>,
    items: VecDeque<Value>,
}

pub struct Notices {
    store: Rc<Store>,
    host: Rc<dyn Host>,
    email_of: EmailOf,
    /// Where each workspace's are kept.
    workspaces: Rc<Workspaces>,
    /// Numbers every workspace's notices: one's id is the device's own (`notice.claim`).
    next: Cell<u64>,
}

impl Notices {
    pub fn new(store: Rc<Store>, host: Rc<dyn Host>, workspaces: Rc<Workspaces>, email_of: EmailOf) -> Rc<Notices> {
        Rc::new(Notices { store, host, email_of, workspaces, next: Cell::new(1) })
    }

    /// Shown anew: their values are computed again.
    pub fn changed(&self) {
        self.store.invalidate_all(|t| matches!(t, Topic::Notices { .. }));
    }

    /// A workspace's notices; with none given, every workspace's, the latest [`KEEP`].
    pub fn value(&self, workspace: Option<&str>) -> Value {
        let items: Vec<Value> = match workspace {
            Some(id) => self.workspaces.get(id).map(|w| w.heard.borrow().items.iter().cloned().collect()).unwrap_or_default(),
            None => {
                let mut all: Vec<Value> = self.workspaces.all().iter().flat_map(|w| w.heard.borrow().items.iter().cloned().collect::<Vec<_>>()).collect();
                let n = |v: &Value| v.get("id").and_then(Value::as_str).and_then(|id| id.trim_start_matches('n').parse::<u64>().ok()).unwrap_or(0);
                all.sort_by_key(n);
                let from = all.len().saturating_sub(KEEP);
                all.split_off(from)
            }
        };
        json!({ "items": items })
    }

    /// Looks at the stations' rows as they are now (`stations`: the addresses kept in sync); what changed since the
    /// last look is noticed, each in its workspace, and answered.
    pub fn look(&self, stations: &[String]) -> Vec<Value> {
        let mut added = Vec::new();
        for workspace in self.workspaces.all() {
            workspace.heard.borrow_mut().seen.retain(|station, _| stations.contains(station));
        }
        for station in stations {
            let its = self.workspaces.of_station(station);
            let Some(Ok(rows)) = self.store.value(&Topic::ChatRows { station: station.clone() }) else { continue };
            let rows = rows.as_array().cloned().unwrap_or_default();
            let workspace = station.split_once('/').map(|(w, _)| w).unwrap_or("");
            let email = (self.email_of)(workspace);
            let me = json!({ "id": email, "email": email });
            let members: Vec<Value> = self.store.get(&Topic::Workspace { workspace: workspace.to_string() })
                .and_then(|w| w.get("members").and_then(Value::as_array).cloned()).unwrap_or_default();
            let slack_users: Vec<String> = self.store.get(&Topic::Overview { station: station.clone() })
                .and_then(|o| o.get("slackUsers").and_then(Value::as_array).cloned()).unwrap_or_default()
                .iter().filter_map(|u| u.as_str().map(str::to_string)).collect();
            let now: HashMap<String, Seen> = rows.iter().filter_map(|row| Some((row.get("id")?.as_str()?.to_string(), seen(row)))).collect();
            let before = its.heard.borrow_mut().seen.insert(station.clone(), now);
            // Its first rows are where it starts from.
            let Some(before) = before else { continue };
            for row in &rows {
                let Some(id) = row.get("id").and_then(Value::as_str) else { continue };
                let then = before.get(id);
                if let Some((kind, body)) = noticed(row, then, &me, &slack_users, &members) {
                    added.push(self.add(&its, station, row, kind, body));
                }
            }
        }
        if !added.is_empty() {
            self.changed();
        }
        added
    }

    fn add(&self, into: &Workspace, station: &str, row: &Value, kind: &str, body: String) -> Value {
        let (workspace, id) = station.split_once('/').unwrap_or(("", station));
        let session = row.get("id").and_then(Value::as_str).unwrap_or("");
        let n = self.next.replace(self.next.get() + 1);
        let notice = json!({
            "id": format!("n{n}"),
            "kind": kind,
            "station": station, "workspace": workspace, "stationId": id,
            "session": session, "thread": row.get("thread").cloned().unwrap_or(Value::Null),
            "title": title(row),
            "body": body,
            "tag": format!("{workspace}/{id}/{session}"),
            "url": format!("/o/{workspace}/{id}/{}", encode(session)),
            "at": self.host.now_ms() as i64,
        });
        let mut heard = into.heard.borrow_mut();
        let items = &mut heard.items;
        items.push_back(notice.clone());
        while items.len() > KEEP {
            items.pop_front();
        }
        notice
    }
}

fn seen(row: &Value) -> Seen {
    let agents = row.get("agents").and_then(Value::as_array).cloned().unwrap_or_default();
    Seen { state: crate::present::row_state(&agents), seq: last_seq(row) }
}

fn last_seq(row: &Value) -> i64 {
    row.get("last").and_then(|l| l.get("seq")).and_then(Value::as_i64).unwrap_or(0)
}

/// What a row's change is worth telling its person, and in what words: its kind (block, failed, done, message) and
/// body. Only rows of still.fail's own chats (a Slack thread has Slack's notifications) that are the viewer's.
fn noticed(row: &Value, then: Option<&Seen>, me: &Value, slack_users: &[String], members: &[Value]) -> Option<(&'static str, String)> {
    if row.get("mine").and_then(Value::as_bool) != Some(true) || row.get("connect").is_some_and(|c| !c.is_null()) {
        return None;
    }
    let now = seen(row);
    let then = then.cloned().unwrap_or(Seen { state: None, seq: 0 });
    let last = row.get("last").filter(|l| l.is_object());
    let text = last.map(|l| crate::format::clean_text(l.get("text").and_then(Value::as_str).unwrap_or(""))).unwrap_or_default();
    let text = if text.is_empty() && last.is_some() { "（文件）".to_string() } else { text };
    let by = crate::present::last_by(row, me, slack_users, members);
    let by_name = by.as_ref().and_then(|b| b.get("name")).and_then(Value::as_str).unwrap_or("").to_string();
    if now.state == Some("block") && then.state != Some("block") {
        return Some(("block", body("block", &by_name, &text)));
    }
    let fresh = now.seq > then.seq;
    let kind = by.as_ref().and_then(|b| b.get("kind")).and_then(Value::as_str);
    // Something went wrong: the station says so in the chat (⚠️ first), for a turn that failed and for an agent that
    // could not start alike.
    if fresh && kind == Some("ember") && let Some(said) = text.strip_prefix("⚠️") {
        return Some(("failed", body("failed", "", said.trim())));
    }
    // Something new to read, said by someone else, with nobody at work.
    let unread = row.get("unread").and_then(Value::as_bool) == Some(true);
    let mine = by.as_ref().and_then(|b| b.get("mine")).and_then(Value::as_bool) == Some(true);
    if !unread || !fresh || mine || now.state == Some("run") || last.is_none() {
        return None;
    }
    let kind = match kind {
        Some("agent") => "done",
        Some("person") => "message",
        _ => return None,
    };
    Some((kind, body(kind, &by_name, &text)))
}

/// A notice's body, as still.fail cloud words a push the same (docs/notifications.md): one line, cut short.
pub fn body(kind: &str, by: &str, text: &str) -> String {
    let text = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let line = match kind {
        "block" => format!("需要处理 · {text}"),
        "failed" => format!("出错了 · {text}"),
        _ if !by.is_empty() => format!("{by}: {text}"),
        _ => text,
    };
    cut(line.trim_end_matches([' ', '·', ':']).to_string(), BODY)
}

fn cut(text: String, max: usize) -> String {
    if text.chars().count() <= max {
        return text;
    }
    let mut out: String = text.chars().take(max - 1).collect();
    out.push('…');
    out
}

fn title(row: &Value) -> String {
    row.get("title").and_then(Value::as_str).map(|t| t.split_whitespace().collect::<Vec<_>>().join(" ")).filter(|t| !t.is_empty())
        .unwrap_or_else(|| "（还没有消息）".to_string())
}

/// A path segment, as `encodeURIComponent` has it.
fn encode(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'!' | b'~' | b'*' | b'\'' | b'(' | b')' => out.push(b as char),
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::CoreError;
    use crate::store::Source;
    use crate::testing::{FakeHost, run};
    use std::cell::RefCell;

    struct Quiet(RefCell<Option<Rc<Notices>>>);

    impl Source for Quiet {
        fn start(&self, _topic: &Topic) {}
        fn stop(&self, _topic: &Topic) {}
        fn compute(&self, topic: &Topic) -> Option<Result<Value, CoreError>> {
            let Topic::Notices { workspace } = topic else { return None };
            Some(Ok(self.0.borrow().as_ref().unwrap().value(workspace.as_deref())))
        }
    }

    fn row(state: Option<&str>, seq: i64, unread: bool, by: (&str, &str)) -> Value {
        let (process, declared, outcome) = match state {
            Some("run") => ("running", None, "completed"),
            Some("block") => ("warm", Some("block"), "completed"),
            Some("failed") => ("warm", None, "failed"),
            _ => ("warm", Some("final"), "completed"),
        };
        json!({
            "id": "ds:C1:1.2", "session": "ds:C1:1.2", "thread": 7, "title": "部署挂了", "mine": true, "unread": unread, "connect": null,
            "agents": [{ "key": "ds:C1:1.2", "model": "claude-opus-5-5", "runtime": "claude", "process": process, "pending": 0,
                "lastTurn": { "declared": declared, "outcome": outcome } }],
            "last": { "seq": seq, "authorKind": by.0, "author": by.1, "authorName": null, "text": "修好了\n  再看看" },
        })
    }

    fn setup() -> (Rc<FakeHost>, Rc<Store>, Rc<Notices>) {
        let host = FakeHost::new();
        let store = Store::new(host.clone());
        let notices = Notices::new(store.clone(), host.clone(), Workspaces::new(host.clone()), Rc::new(|_: &str| Some("me@x.y".to_string())));
        store.set_source(Rc::new(Quiet(RefCell::new(Some(notices.clone())))));
        (host, store, notices)
    }

    fn kinds(notices: &Notices) -> Vec<String> {
        notices.value(None)["items"].as_array().unwrap().iter().map(|n| n["kind"].as_str().unwrap().to_string()).collect()
    }

    #[test]
    fn a_chat_of_mine_is_noticed_as_it_changes_and_not_for_how_it_was_at_first() {
        run(async {
            let (_host, store, notices) = setup();
            let rows = Topic::ChatRows { station: "ws/st".into() };
            let stations = ["ws/st".to_string()];
            let _watch = store.watch(&rows, Rc::new(|| {}));
            // Found blocked and unread at first: old news.
            store.set(&rows, Ok(json!([row(Some("block"), 3, true, ("agent", "ds:C1:1.2"))])));
            notices.look(&stations);
            assert!(kinds(&notices).is_empty());
            // At work, saying things: nothing yet.
            store.set(&rows, Ok(json!([row(Some("run"), 4, true, ("agent", "ds:C1:1.2"))])));
            notices.look(&stations);
            assert!(kinds(&notices).is_empty());
            // Done, with its last word unread.
            store.set(&rows, Ok(json!([row(None, 5, true, ("agent", "ds:C1:1.2"))])));
            notices.look(&stations);
            assert_eq!(kinds(&notices), ["done"]);
            let n = &notices.value(None)["items"][0];
            assert_eq!(n["body"], "Opus 5.5: 修好了 再看看");
            assert_eq!(n["tag"], "ws/st/ds:C1:1.2");
            assert_eq!(n["url"], "/o/ws/st/ds%3AC1%3A1.2");
            assert_eq!(n["title"], "部署挂了");
            // Looked at again unchanged: nothing more.
            notices.look(&stations);
            assert_eq!(kinds(&notices).len(), 1);
            // My own message: nothing; then blocked on me.
            store.set(&rows, Ok(json!([row(None, 6, false, ("person", "me@x.y"))])));
            notices.look(&stations);
            store.set(&rows, Ok(json!([row(Some("block"), 7, true, ("agent", "ds:C1:1.2"))])));
            notices.look(&stations);
            assert_eq!(kinds(&notices), ["done", "block"]);
            assert!(notices.value(None)["items"][1]["body"].as_str().unwrap().starts_with("需要处理 · 修好了"));
            // Someone else says something.
            store.set(&rows, Ok(json!([row(None, 8, true, ("person", "you@x.y"))])));
            notices.look(&stations);
            assert_eq!(kinds(&notices), ["done", "block", "message"]);
            // The station says something went wrong (a failed turn says so too; its state alone says nothing).
            let mut failed = row(Some("failed"), 9, true, ("ember", "ember"));
            failed["last"]["text"] = json!("⚠️ 无法启动 agent：没有 claude");
            store.set(&rows, Ok(json!([failed])));
            notices.look(&stations);
            assert_eq!(kinds(&notices), ["done", "block", "message", "failed"]);
            assert_eq!(notices.value(None)["items"][3]["body"], "出错了 · 无法启动 agent：没有 claude");
        });
    }

    #[test]
    fn chats_not_mine_and_slack_threads_are_not_noticed() {
        run(async {
            let (_host, store, notices) = setup();
            let rows = Topic::ChatRows { station: "ws/st".into() };
            let stations = ["ws/st".to_string()];
            let _watch = store.watch(&rows, Rc::new(|| {}));
            store.set(&rows, Ok(json!([])));
            notices.look(&stations);
            let mut theirs = row(Some("block"), 2, true, ("agent", "ds:C1:1.2"));
            theirs["mine"] = json!(false);
            let mut slack = row(Some("block"), 2, true, ("agent", "ds:C1:1.2"));
            slack["id"] = json!("other");
            slack["connect"] = json!("ds");
            store.set(&rows, Ok(json!([theirs, slack])));
            notices.look(&stations);
            assert!(kinds(&notices).is_empty());
        });
    }

    #[test]
    fn a_workspace_hears_of_its_own_chats_only() {
        run(async {
            let (_host, store, notices) = setup();
            let (one, two) = (Topic::ChatRows { station: "w1/st".into() }, Topic::ChatRows { station: "w2/st".into() });
            let stations = ["w1/st".to_string(), "w2/st".to_string()];
            let _watch = (store.watch(&one, Rc::new(|| {})), store.watch(&two, Rc::new(|| {})));
            store.set(&one, Ok(json!([row(Some("run"), 3, true, ("agent", "ds:C1:1.2"))])));
            store.set(&two, Ok(json!([row(Some("run"), 3, true, ("agent", "ds:C1:1.2"))])));
            notices.look(&stations);
            store.set(&one, Ok(json!([row(None, 4, true, ("agent", "ds:C1:1.2"))])));
            let added = notices.look(&stations);
            assert_eq!(added.len(), 1);
            assert_eq!(notices.value(Some("w1"))["items"][0]["workspace"], "w1");
            assert_eq!(notices.value(Some("w2"))["items"], json!([]));
            // W2 no longer kept in sync: what it had seen goes, W1's stays.
            store.set(&two, Ok(json!([row(Some("block"), 5, true, ("agent", "ds:C1:1.2"))])));
            notices.look(&stations[..1]);
            notices.look(&stations);
            assert_eq!(notices.value(Some("w2"))["items"], json!([]), "found blocked when it came back: where it starts from");
            assert_eq!(kinds(&notices), ["done"]);
        });
    }

    #[test]
    fn bodies_are_one_short_line() {
        assert_eq!(body("done", "Claude", "a\n\n b"), "Claude: a b");
        assert_eq!(body("failed", "Claude", ""), "出错了");
        let long = body("message", "x", &"字".repeat(300));
        assert_eq!(long.chars().count(), BODY);
        assert!(long.ends_with('…'));
    }
}
