//! Where the viewer's attention is, and what follows from it (the `notify` topic, `client.focus`).
//!
//! Each UI says whether its page is in view (`visible`), looked at (`focused`), and which chat it shows with its end
//! in view or not (`client.focus`). From that the core decides:
//! - a chat's unread line (`unreadLine`): over the first message the viewer had not read when the chat was opened
//!   (not theirs, said before it opened), held for the visit, which lasts while some UI shows the chat. The chat opens
//!   at it (station.rs `open_thread`), so it is in its first value, before a UI says it shows it; nothing is loaded to
//!   find it (`unreadAbove` stays false);
//! - what is read: a chat is read up to its newest message while a UI shows its end on a page in view;
//! - what comes in while a chat shows (`said` on a message, `started` on an agent): a message the station told as it
//!   was said (an event, past what the chat caught up on by reading: what was kept, a page, what was missed while the
//!   link was down) after the visit began, and an agent seen starting its turn during it. Only those come in with a
//!   motion; the rest is there at once. Each is decided once, when first seen: catching up later does not take back
//!   one already coming in;
//! - which notices a page shows now (`notify`): none while notifications are off, none for a chat a UI is looking
//!   at, none while this device has pushes and no page is in view (the push tells then); each once (`notice.claim`);
//! - the workspace the viewer is in: where each UI is (the workspace it says, else its chat's). Notices are only of
//!   the workspace the viewer is in (workspace.rs): those of the UIs in view, or, with none in view, of every UI's
//!   (a phone's app in the background is still in its workspace). With no UI saying where it is (none, or ones from
//!   before they said it), nothing tells which is current, and every workspace's are.
//!
//! Whether notifications are on, and whether the system was asked to allow them, are kept on the device here.

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::error::{CoreError, Result};
use crate::host::Host;
use crate::protocol::ClientId;
use crate::workspace::of_address;

/// Where the settings are kept (host storage).
const KEY: &str = "notify";
/// A notice no page took this long is not shown any more.
const SHOW_FOR_MS: f64 = 30_000.0;

#[derive(Serialize, Deserialize, Clone, Copy)]
struct Settings {
    on: bool,
    #[serde(default)]
    asked: bool,
}

/// A chat as a UI names it: its thread, or its key before it has one (or both).
#[derive(Deserialize, Clone, Debug, PartialEq, Default)]
pub struct ChatOf {
    pub station: String,
    #[serde(default)]
    pub thread: Option<u64>,
    #[serde(default)]
    pub session: Option<String>,
    /// Its end is in view (what is read).
    #[serde(default)]
    pub end: bool,
}

impl ChatOf {
    fn is(&self, station: &str, thread: Option<u64>, session: Option<&str>) -> bool {
        self.station == station
            && (thread.is_some_and(|t| self.thread == Some(t)) || session.is_some_and(|s| self.session.as_deref() == Some(s)))
    }
}

/// What one UI shows.
#[derive(Clone, Debug, Default)]
struct Focus {
    visible: bool,
    focused: bool,
    chat: Option<ChatOf>,
    /// The workspace it is in (a workspace id), as it said.
    workspace: Option<String>,
}

impl Focus {
    /// The workspace it is in: as it said, else its chat's.
    fn workspace(&self) -> Option<String> {
        self.workspace.clone().or_else(|| self.chat.as_ref().map(|c| of_address(&c.station).to_string()))
    }
}

/// A chat shown: from when, and up to where it had been read then.
struct Visit {
    at: f64,
    read: u64,
    session: Option<String>,
    /// The newest message decided on (`said` or not), and those said while it shows.
    top: u64,
    said: HashSet<u64>,
    /// Each agent's status as last seen, and those seen starting while it shows.
    statuses: HashMap<String, String>,
    started: HashSet<String>,
}

/// What a UI said (`client.focus`): each field given changes, the rest stays. `chat: null` shows none; `left`: the
/// chat it names is not shown any more, if it is the one shown (a page going as the next one comes).
#[derive(Deserialize, Debug, Default, PartialEq)]
pub struct FocusCall {
    #[serde(default)]
    visible: Option<bool>,
    #[serde(default)]
    focused: Option<bool>,
    #[serde(default, deserialize_with = "some")]
    chat: Option<Option<ChatOf>>,
    #[serde(default)]
    left: Option<ChatOf>,
    /// The workspace it is in now (a workspace id).
    #[serde(default)]
    workspace: Option<String>,
}

fn some<'de, D: serde::Deserializer<'de>>(d: D) -> std::result::Result<Option<Option<ChatOf>>, D::Error> {
    Option::<ChatOf>::deserialize(d).map(Some)
}

#[derive(Debug, PartialEq)]
pub enum Call {
    Focus(FocusCall),
    /// Notifications on or off, and the system asked to allow them.
    Set { on: Option<bool>, asked: Option<bool> },
    /// A page takes a notice to show: only the first one does.
    Claim { id: String },
    /// A push came while no page may be open (Android's FCM service): whether to show it; `workspace`, the one it is
    /// of (none from a UI before it said).
    Pushed { workspace: Option<String> },
}

/// The calls of this module, by name; `None`: not one of them.
pub fn parse(name: &str, params: &Value) -> Option<Result<Call>> {
    let params = if params.is_null() { json!({}) } else { params.clone() };
    let bad = |e: serde_json::Error| CoreError::invalid(format!("参数不对：{e}"));
    Some(match name {
        "client.focus" => serde_json::from_value::<FocusCall>(params).map(Call::Focus).map_err(bad),
        "notify.set" => {
            #[derive(Deserialize)]
            struct P { on: Option<bool>, asked: Option<bool> }
            serde_json::from_value::<P>(params).map(|p| Call::Set { on: p.on, asked: p.asked }).map_err(bad)
        }
        "notice.claim" => {
            #[derive(Deserialize)]
            struct P { id: String }
            serde_json::from_value::<P>(params).map(|p| Call::Claim { id: p.id }).map_err(bad)
        }
        "notice.pushed" => {
            #[derive(Deserialize)]
            struct P { #[serde(default)] workspace: Option<String> }
            serde_json::from_value::<P>(params).map(|p| Call::Pushed { workspace: p.workspace }).map_err(bad)
        }
        _ => return None,
    })
}

/// What a chat's value asks of the core once computed: a read position recorded.
#[derive(Debug, PartialEq)]
pub enum Due {
    Read { thread: u64, seq: u64 },
}

pub struct Attend {
    host: Rc<dyn Host>,
    settings: Cell<Settings>,
    /// This device holds a push registration that still.fail cloud has.
    pushing: Cell<bool>,
    focus: RefCell<HashMap<ClientId, Focus>>,
    visits: RefCell<HashMap<(String, u64), Visit>>,
    /// Read positions asked for, by chat: each once.
    reads: RefCell<HashMap<(String, u64), u64>>,
    /// Notices to be shown now, and since when.
    show: RefCell<Vec<(Value, f64)>>,
}

impl Attend {
    pub async fn load(host: Rc<dyn Host>) -> Rc<Attend> {
        let kept = host.storage_get(KEY).await.ok().flatten().and_then(|b| serde_json::from_slice::<Settings>(&b).ok());
        Rc::new(Attend {
            host,
            settings: Cell::new(kept.unwrap_or(Settings { on: true, asked: false })),
            pushing: Cell::default(),
            focus: RefCell::default(),
            visits: RefCell::default(),
            reads: RefCell::default(),
            show: RefCell::default(),
        })
    }

    pub fn on(&self) -> bool {
        self.settings.get().on
    }

    /// The `notify` topic: the settings, whether this device should hold a push registration, and what to show now
    /// (a page in `workspace` shows only its own).
    pub fn value(&self, workspace: Option<&str>) -> Value {
        let now = self.host.now_ms();
        let Settings { on, asked } = self.settings.get();
        let show: Vec<Value> = self.show.borrow().iter()
            .filter(|(n, at)| now - at < SHOW_FOR_MS && workspace.is_none_or(|w| of(n) == w))
            .map(|(n, _)| n.clone()).collect();
        json!({ "on": on, "asked": asked, "push": on, "show": show })
    }

    /// Changes the settings and keeps them.
    pub async fn set(&self, on: Option<bool>, asked: Option<bool>) {
        let mut s = self.settings.get();
        s.on = on.unwrap_or(s.on);
        s.asked = asked.unwrap_or(s.asked);
        self.settings.set(s);
        if !s.on {
            self.show.borrow_mut().clear();
        }
        let _ = self.host.storage_set(KEY, serde_json::to_vec(&s).unwrap_or_default()).await;
    }

    pub fn set_pushing(&self, on: bool) {
        self.pushing.set(on);
    }

    /// Any page in view.
    fn seen(&self) -> bool {
        self.focus.borrow().values().any(|f| f.visible)
    }

    /// The workspaces the viewer is in: the UIs' in view, or with none in view every UI's; `None` while no UI says
    /// (then no workspace is the current one, and none is left out).
    pub fn current(&self) -> Option<HashSet<String>> {
        let focus = self.focus.borrow();
        let of_uis = |in_view: bool| -> HashSet<String> { focus.values().filter(|f| f.visible || !in_view).filter_map(Focus::workspace).collect() };
        let shown = of_uis(true);
        let all = if shown.is_empty() { of_uis(false) } else { shown };
        (!all.is_empty()).then_some(all)
    }

    /// Whether a notice (or a push) of `workspace` is the current workspace's.
    fn current_has(&self, workspace: &str) -> bool {
        self.current().is_none_or(|c| c.contains(workspace))
    }

    /// A UI's focus changed.
    pub fn focus(&self, client: ClientId, call: FocusCall) {
        let mut all = self.focus.borrow_mut();
        let f = all.entry(client).or_default();
        if let Some(v) = call.visible {
            f.visible = v;
        }
        if let Some(v) = call.focused {
            f.focused = v;
        }
        if let Some(left) = call.left
            && f.chat.as_ref().is_some_and(|c| c.is(&left.station, left.thread, left.session.as_deref()))
        {
            f.chat = None;
        }
        if let Some(chat) = call.chat {
            f.chat = chat;
        }
        if let Some(workspace) = call.workspace {
            f.workspace = Some(workspace);
        }
        drop(all);
        self.end_visits();
    }

    /// A UI went away.
    pub fn gone(&self, client: ClientId) {
        self.focus.borrow_mut().remove(&client);
        self.end_visits();
    }

    /// A visit lasts while some UI shows its chat.
    fn end_visits(&self) {
        let focus = self.focus.borrow();
        self.visits.borrow_mut().retain(|(station, thread), v| {
            focus.values().filter_map(|f| f.chat.as_ref()).any(|c| c.is(station, Some(*thread), v.session.as_deref()))
        });
    }

    /// The UIs showing a chat.
    fn showing(&self, station: &str, thread: Option<u64>, session: Option<&str>) -> Vec<Focus> {
        self.focus.borrow().values().filter(|f| f.chat.as_ref().is_some_and(|c| c.is(station, thread, session))).cloned().collect()
    }

    /// A chat's value as computed (`session`: the key its topic names it by): its unread line goes in
    /// (`unreadLine`), and what it asks of the core comes back.
    pub fn chat(&self, station: &str, session: Option<&str>, value: &mut Value) -> Vec<Due> {
        let mut due = Vec::new();
        let Some(thread) = value.get("thread").and_then(|t| t.get("id")).and_then(Value::as_u64) else { return due };
        let shown = self.showing(station, Some(thread), session);
        let known = value["thread"].get("read").and_then(Value::as_u64).unwrap_or(0);
        let messages = value.get("messages").and_then(Value::as_array).cloned().unwrap_or_default();
        let seq = |m: &Value| m.get("seq").and_then(Value::as_u64).unwrap_or(0);
        let now = self.host.now_ms();
        // Over the first unread message, when the window reaches back to where reading stopped (one past it, gone to
        // the end, has no line: what is above it is unread too).
        let more = value.get("more").and_then(Value::as_bool) == Some(true);
        let unread_line = |read: u64, opened: f64| {
            if more && messages.first().is_none_or(|m| seq(m) > read + 1) {
                return Value::Null;
            }
            messages.iter().find(|m| {
                seq(m) > read
                    && m.get("createdAt").and_then(Value::as_f64).is_some_and(|at| at <= opened)
                    && m.get("mine").and_then(Value::as_bool) != Some(true)
            }).map_or(Value::Null, |m| json!(seq(m)))
        };
        value["unreadAbove"] = json!(false);
        // Not shown yet (its first value, before a UI says it shows it): the line as it will be.
        if shown.is_empty() {
            value["unreadLine"] = unread_line(known, now);
            return due;
        }
        let mut visits = self.visits.borrow_mut();
        let newest = messages.last().map(seq).unwrap_or(0);
        let visit = visits.entry((station.to_string(), thread)).or_insert_with(|| Visit {
            at: now, read: known, session: session.map(str::to_string), top: newest, said: HashSet::new(), statuses: HashMap::new(), started: HashSet::new(),
        });
        let (read, opened) = (visit.read, visit.at);
        // Said while it shows: past what it had when the visit began, and past what was caught up on (station.rs
        // `caught`: an event moves it not, a read does).
        let caught = value.get("caught").and_then(Value::as_u64).unwrap_or(0);
        for m in &messages {
            let n = seq(m);
            if n > visit.top && n > caught {
                visit.said.insert(n);
            }
        }
        visit.top = visit.top.max(newest);
        for m in value.get_mut("messages").and_then(Value::as_array_mut).into_iter().flatten() {
            if visit.said.contains(&seq(m)) {
                m["said"] = json!(true);
            }
        }
        // Started while it shows: seen at something else first (one at work when first seen was at it before).
        for a in value.get_mut("agents").and_then(Value::as_array_mut).into_iter().flatten() {
            let Some(key) = a.get("session").and_then(|s| s.get("key")).and_then(Value::as_str).map(str::to_string) else { continue };
            let status = a.get("status").and_then(Value::as_str).unwrap_or("").to_string();
            let running = status == "running";
            match visit.statuses.insert(key.clone(), status) {
                _ if !running => { visit.started.remove(&key); }
                Some(was) if was != "running" => { visit.started.insert(key.clone()); }
                _ => {}
            }
            if visit.started.contains(&key) {
                a["started"] = json!(true);
            }
        }
        drop(visits);
        value["unreadLine"] = unread_line(read, opened);
        // Read: up to the newest, while its end is in view on a page in view. A window short of the chat's end is not
        // read by its end showing: a page can land after it between the UI saying so and this (station.rs `newer`).
        let short = value.get("newer").and_then(Value::as_bool) == Some(true);
        if !short && shown.iter().any(|f| f.visible && f.chat.as_ref().is_some_and(|c| c.end)) && newest > known {
            let mut reads = self.reads.borrow_mut();
            let sent = reads.entry((station.to_string(), thread)).or_default();
            if *sent < newest {
                *sent = newest;
                due.push(Due::Read { thread, seq: newest });
            }
        }
        due
    }

    /// What was due could not be done: asked again the next time.
    pub fn failed(&self, station: &str, due: &Due) {
        match *due {
            Due::Read { thread, .. } => {
                self.reads.borrow_mut().remove(&(station.to_string(), thread));
            }
        }
    }

    /// Notices new since the last look (notices.rs): answers whether any is to be shown now. `listened`: a page takes
    /// what is to be shown (someone subscribes to `notify`); with none, nothing waits to be shown later.
    pub fn noticed(&self, added: &[Value], listened: bool) -> bool {
        if !self.on() || !listened {
            return false;
        }
        // No page in view and a push on its way: that says it.
        if self.pushing.get() && !self.seen() {
            return false;
        }
        let now = self.host.now_ms();
        let mut show = self.show.borrow_mut();
        show.retain(|(_, at)| now - at < SHOW_FOR_MS);
        let before = show.len();
        for n in added {
            // Another workspace's: not the viewer's now.
            if !self.current_has(of(n)) {
                continue;
            }
            let station = n.get("station").and_then(Value::as_str).unwrap_or("");
            let looking = self.showing(station, n.get("thread").and_then(Value::as_u64), n.get("session").and_then(Value::as_str))
                .iter().any(|f| f.visible && f.focused);
            if !looking {
                show.push((n.clone(), now));
            }
        }
        show.len() > before
    }

    /// A page takes a notice to show: the first to ask.
    pub fn claim(&self, id: &str) -> bool {
        let mut show = self.show.borrow_mut();
        let before = show.len();
        show.retain(|(n, _)| n.get("id").and_then(Value::as_str) != Some(id));
        show.len() < before
    }

    /// A push came: shown unless notifications are off, a page is in view (it shows its own), or it is of another
    /// workspace than the viewer's.
    pub fn pushed(&self, workspace: Option<&str>) -> bool {
        self.on() && !self.seen() && workspace.is_none_or(|w| self.current_has(w))
    }
}

/// The workspace a notice is of (its station's, where it does not say).
fn of(notice: &Value) -> &str {
    notice.get("workspace").and_then(Value::as_str).unwrap_or_else(|| of_address(notice.get("station").and_then(Value::as_str).unwrap_or("")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::{FakeHost, run};

    fn focus(v: Value) -> FocusCall {
        serde_json::from_value(v).unwrap()
    }

    fn chat(read: u64, more: bool, messages: &[(u64, f64, bool)]) -> Value {
        json!({
            "thread": { "id": 7, "read": read },
            "more": more,
            "messages": messages.iter().map(|(seq, at, mine)| json!({ "seq": seq, "createdAt": at, "mine": mine })).collect::<Vec<_>>(),
        })
    }

    #[test]
    fn the_unread_line_holds_for_the_visit_and_is_there_from_the_first_value() {
        run(async {
            let host = FakeHost::new();
            let attend = Attend::load(host.clone()).await;
            // Not shown yet (its first value): the line as it will be, over the first unread not mine (3 is mine);
            // nothing due.
            let mut v = chat(2, false, &[(1, 0.0, false), (2, 0.0, false), (3, 0.0, true), (4, 0.0, false)]);
            assert!(attend.chat("ws/st", None, &mut v).is_empty());
            assert_eq!(v["unreadLine"], 4);
            // Opened: over the first unread not mine (3 is mine).
            attend.focus(1, focus(json!({ "visible": true, "focused": true, "chat": { "station": "ws/st", "thread": 7 } })));
            attend.chat("ws/st", None, &mut v);
            assert_eq!(v["unreadLine"], 4);
            // Read meanwhile: the line stays for the visit; a message said after it opened gets none.
            let later = host.now_ms() + 1.0;
            let mut v = chat(4, false, &[(1, 0.0, false), (2, 0.0, false), (3, 0.0, true), (4, 0.0, false), (5, later, false)]);
            attend.chat("ws/st", None, &mut v);
            assert_eq!(v["unreadLine"], 4);
            // Left and opened again: read up to 4 now, 5 said before this visit.
            attend.focus(1, focus(json!({ "left": { "station": "ws/st", "thread": 7 } })));
            attend.focus(1, focus(json!({ "chat": { "station": "ws/st", "session": "k1", "thread": 7 } })));
            tokio::time::sleep(std::time::Duration::from_millis(5)).await;
            attend.chat("ws/st", Some("k1"), &mut v);
            assert_eq!(v["unreadLine"], 5);
            // A page of the chat another leaves does not end the visit.
            attend.focus(1, focus(json!({ "left": { "station": "ws/st", "thread": 8 } })));
            assert_eq!(attend.visits.borrow().len(), 1);
            // A window past what was read (the chat went to its end): no line (what is above it is unread too), and
            // nothing is loaded to find it.
            attend.focus(1, focus(json!({ "chat": null })));
            attend.focus(2, focus(json!({ "chat": { "station": "ws/st", "thread": 7 } })));
            let mut v = chat(1, true, &[(10, 0.0, false), (11, 0.0, false)]);
            assert!(attend.chat("ws/st", None, &mut v).is_empty());
            assert_eq!((v["unreadLine"].clone(), v["unreadAbove"].clone()), (Value::Null, json!(false)));
            // One reaching back to it: over the first unread.
            let mut v = chat(1, true, &[(1, 0.0, false), (2, 0.0, false)]);
            attend.chat("ws/st", None, &mut v);
            assert_eq!(v["unreadLine"], 2);
        });
    }

    #[test]
    fn only_what_is_said_while_a_chat_shows_comes_in() {
        run(async {
            let host = FakeHost::new();
            let attend = Attend::load(host.clone()).await;
            let said = |v: &Value| -> Vec<u64> {
                v["messages"].as_array().unwrap().iter().filter(|m| m["said"] == true).map(|m| m["seq"].as_u64().unwrap()).collect()
            };
            let started = |v: &Value| -> Vec<String> {
                v["agents"].as_array().unwrap().iter().filter(|a| a["started"] == true).map(|a| a["session"]["key"].as_str().unwrap().to_string()).collect()
            };
            let at = |n: u64, caught: u64, agents: Value| {
                let mut v = chat(n, false, &(1..=n).map(|s| (s, 0.0, false)).collect::<Vec<_>>());
                v["caught"] = json!(caught);
                v["agents"] = agents;
                v
            };
            let agents = |a: &str, b: &str| json!([{ "session": { "key": "a" }, "status": a }, { "session": { "key": "b" }, "status": b }]);
            attend.focus(1, focus(json!({ "visible": true, "chat": { "station": "ws/st", "thread": 7 } })));
            // Opened from what was kept (2), its agent a at work already: nothing comes in.
            let mut v = at(2, 2, agents("running", "idle"));
            attend.chat("ws/st", None, &mut v);
            assert!(said(&v).is_empty() && started(&v).is_empty());
            // Caught up on from the station (3, 4 read after what was kept): there at once, however a works on.
            let mut v = at(4, 4, agents("running", "idle"));
            attend.chat("ws/st", None, &mut v);
            assert!(said(&v).is_empty());
            // Told as said (5, 6, an event: caught stays), and b starts: they come in.
            let mut v = at(6, 4, agents("running", "running"));
            attend.chat("ws/st", None, &mut v);
            assert_eq!((said(&v), started(&v)), (vec![5, 6], vec!["b".to_string()]));
            // Caught up on past them later (the link came back): what came in stays so; 7, read, does not.
            let mut v = at(7, 7, agents("running", "running"));
            attend.chat("ws/st", None, &mut v);
            assert_eq!(said(&v), vec![5, 6]);
            // b's turn ends: it is not starting any more.
            let mut v = at(7, 7, agents("running", "idle"));
            attend.chat("ws/st", None, &mut v);
            assert!(started(&v).is_empty());
            // Left and opened again: all of it is there at once.
            attend.focus(1, focus(json!({ "chat": null })));
            attend.focus(1, focus(json!({ "chat": { "station": "ws/st", "thread": 7 } })));
            let mut v = at(7, 7, agents("running", "idle"));
            attend.chat("ws/st", None, &mut v);
            assert!(said(&v).is_empty());
            // Not shown: nothing is decided.
            attend.focus(1, focus(json!({ "chat": null })));
            let mut v = at(9, 7, agents("running", "idle"));
            attend.chat("ws/st", None, &mut v);
            assert!(said(&v).is_empty());
        });
    }

    #[test]
    fn a_chat_is_read_while_its_end_shows_on_a_page_in_view() {
        run(async {
            let host = FakeHost::new();
            let attend = Attend::load(host.clone()).await;
            let mut v = chat(1, false, &[(1, 0.0, false), (2, 0.0, false)]);
            attend.focus(1, focus(json!({ "visible": false, "chat": { "station": "ws/st", "thread": 7, "end": true } })));
            assert!(attend.chat("ws/st", None, &mut v).is_empty());
            attend.focus(1, focus(json!({ "visible": true, "chat": { "station": "ws/st", "thread": 7, "end": false } })));
            assert!(attend.chat("ws/st", None, &mut v).is_empty());
            attend.focus(1, focus(json!({ "chat": { "station": "ws/st", "thread": 7, "end": true } })));
            assert_eq!(attend.chat("ws/st", None, &mut v), [Due::Read { thread: 7, seq: 2 }]);
            // Once; again if it failed.
            assert!(attend.chat("ws/st", None, &mut v).is_empty());
            attend.failed("ws/st", &Due::Read { thread: 7, seq: 2 });
            assert_eq!(attend.chat("ws/st", None, &mut v), [Due::Read { thread: 7, seq: 2 }]);
            // Read already: nothing.
            let mut v = chat(2, false, &[(1, 0.0, false), (2, 0.0, false)]);
            assert!(attend.chat("ws/st", None, &mut v).is_empty());
            // A window short of the chat's end: its end showing reads nothing.
            let mut v = chat(2, false, &[(1, 0.0, false), (2, 0.0, false), (3, 0.0, false)]);
            v["newer"] = json!(true);
            assert!(attend.chat("ws/st", None, &mut v).is_empty());
        });
    }

    #[test]
    fn notices_show_unless_off_looked_at_or_left_to_a_push_and_each_once() {
        run(async {
            let host = FakeHost::new();
            let attend = Attend::load(host.clone()).await;
            let n = |id: &str| json!({ "id": id, "station": "ws/st", "session": "k1", "thread": 7 });
            let shown = |a: &Attend| a.value(None)["show"].as_array().unwrap().iter().map(|n| n["id"].as_str().unwrap().to_string()).collect::<Vec<_>>();
            // Nobody listening: nothing waits.
            assert!(!attend.noticed(&[n("n1")], false));
            attend.focus(1, focus(json!({ "visible": true, "focused": false, "chat": { "station": "ws/st", "thread": 7 } })));
            // The chat shown but not looked at: shown.
            assert!(attend.noticed(&[n("n2")], true));
            // Looked at: not.
            attend.focus(1, focus(json!({ "focused": true })));
            assert!(!attend.noticed(&[n("n3")], true));
            assert_eq!(shown(&attend), ["n2"]);
            // Each page takes it once.
            assert!(attend.claim("n2"));
            assert!(!attend.claim("n2"));
            assert!(shown(&attend).is_empty());
            // With pushes and no page in view, the push says it.
            attend.set_pushing(true);
            attend.focus(1, focus(json!({ "visible": false, "focused": false })));
            assert!(!attend.noticed(&[n("n4")], true));
            assert!(attend.pushed(None));
            attend.focus(2, focus(json!({ "visible": true })));
            assert!(attend.noticed(&[n("n5")], true));
            assert!(!attend.pushed(None));
            // Off: none, and it is kept.
            attend.set(Some(false), Some(true)).await;
            assert!(!attend.noticed(&[n("n6")], true));
            assert!(shown(&attend).is_empty());
            let again = Attend::load(host.clone()).await;
            assert_eq!(again.value(None), json!({ "on": false, "asked": true, "push": false, "show": [] }));
            // A page gone is in view no more.
            attend.gone(2);
            assert!(!attend.seen());
        });
    }

    #[test]
    fn only_the_workspace_the_viewer_is_in_is_heard_of() {
        run(async {
            let host = FakeHost::new();
            let attend = Attend::load(host.clone()).await;
            let n = |id: &str, workspace: &str| json!({ "id": id, "station": format!("{workspace}/st"), "workspace": workspace, "session": "k1", "thread": 7 });
            let shown = |a: &Attend, w: Option<&str>| a.value(w)["show"].as_array().unwrap().iter().map(|n| n["id"].as_str().unwrap().to_string()).collect::<Vec<_>>();
            // Nobody says where they are: every workspace's.
            attend.focus(1, focus(json!({ "visible": true })));
            assert!(attend.noticed(&[n("n1", "w1"), n("n2", "w2")], true));
            assert_eq!(shown(&attend, None), ["n1", "n2"]);
            attend.claim("n1");
            attend.claim("n2");
            // In W1 (as said, or by the chat shown): W2's is not.
            attend.focus(1, focus(json!({ "workspace": "w1" })));
            assert!(!attend.noticed(&[n("n3", "w2")], true));
            attend.focus(1, focus(json!({ "chat": { "station": "w1/st", "thread": 9 } })));
            assert!(attend.noticed(&[n("n4", "w1"), n("n5", "w2")], true));
            assert_eq!(shown(&attend, None), ["n4"]);
            // A page in W2 beside it, in view: each page shows its workspace's.
            attend.focus(2, focus(json!({ "visible": true, "workspace": "w2" })));
            assert!(attend.noticed(&[n("n6", "w2")], true));
            assert_eq!(shown(&attend, Some("w2")), ["n6"]);
            assert_eq!(shown(&attend, Some("w1")), ["n4"]);
            // None in view: where they were. A push of W3 is none of theirs.
            attend.focus(1, focus(json!({ "visible": false })));
            attend.focus(2, focus(json!({ "visible": false })));
            assert!(attend.pushed(Some("w2")));
            assert!(!attend.pushed(Some("w3")));
            assert!(attend.pushed(None));
            attend.gone(1);
            attend.gone(2);
            assert!(attend.pushed(Some("w3")), "no UI: nothing says which workspace is current");
        });
    }
}
