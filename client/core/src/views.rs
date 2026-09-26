//! The views: what one screen shows, put together from the account and station
//! topics so the UI does no joining, filtering or grouping (docs/client-core.md,
//! Views).
//!
//! A view watches the topics it is built from. Any change of them only
//! invalidates it; the store has it computed when its coalesced emission goes
//! out, so a burst of changes costs one computation. Each computation first
//! brings the watches in line with the workspace's station list: a station
//! that comes online is watched, one that goes offline is let go.
//!
//! The one timer here is a clock: while a `chats` view is live, its days are
//! recomputed at the viewer's next local midnight (`daysAgo` changes then).

use std::cell::{Cell, RefCell};
use std::collections::{BTreeSet, HashMap, HashSet};
use std::rc::{Rc, Weak};

use futures::FutureExt;
use serde_json::{Value, json};

use crate::error::{CoreError, Result};
use crate::host::Host;
use crate::protocol::Topic;
use crate::store::{Store, Watch};

/// The runtimes a chat can run on, in the order they are offered.
const RUNTIMES: [&str; 2] = ["claude", "codex"];
const DAY_MS: f64 = 86_400_000.0;
/// How much of a chat's last message the sidebar gets.
const LAST_CHARS: usize = 200;

/// The email of the signed-in account that reaches a workspace.
pub type EmailOf = Rc<dyn Fn(&str) -> Option<String>>;

pub struct Views {
    host: Rc<dyn Host>,
    store: Rc<Store>,
    email_of: EmailOf,
    me: Weak<Views>,
    /// Per live view, the topics it watches.
    views: RefCell<HashMap<Topic, HashMap<Topic, Watch>>>,
    /// Messages sent from here that the chat does not show yet, per (station, thread), oldest first.
    outbox: RefCell<HashMap<(String, u64), Vec<Value>>>,
    sent: Cell<u64>,
    /// The midnight clock is running.
    clock: Cell<bool>,
}

/// A station of a scope, as the workspace lists it.
struct StationInfo {
    address: String,
    id: String,
    name: String,
    online: bool,
    last_seen: Value,
    version: Value,
}

impl Views {
    pub fn new(host: Rc<dyn Host>, store: Rc<Store>, email_of: EmailOf) -> Rc<Views> {
        Rc::new_cyclic(|me| Views {
            host,
            store,
            email_of,
            me: me.clone(),
            views: RefCell::default(),
            outbox: RefCell::default(),
            sent: Cell::new(0),
            clock: Cell::new(false),
        })
    }

    /// A message on its way to a chat: shown in it at once, as `sending`. Answers its id.
    pub fn outbox_add(&self, station: &str, thread: u64, message: Value) -> String {
        self.sent.set(self.sent.get() + 1);
        let id = format!("out-{}", self.sent.get());
        let mut entry = message;
        entry["id"] = json!(id);
        entry["createdAt"] = json!(self.host.now_ms());
        entry["state"] = json!("sending");
        self.outbox.borrow_mut().entry((station.to_string(), thread)).or_default().push(entry);
        self.outbox_changed(station, thread);
        id
    }

    pub fn outbox_get(&self, station: &str, thread: u64, id: &str) -> Option<Value> {
        self.outbox.borrow().get(&(station.to_string(), thread))?.iter().find(|m| m["id"] == id).cloned()
    }

    /// Marks an outgoing message `sending` again, or `failed` with the error's message.
    pub fn outbox_state(&self, station: &str, thread: u64, id: &str, failed: Option<&str>) {
        if let Some(entry) = self.outbox.borrow_mut().get_mut(&(station.to_string(), thread)).and_then(|list| list.iter_mut().find(|m| m["id"] == id)) {
            entry["state"] = json!(if failed.is_some() { "failed" } else { "sending" });
            entry["error"] = json!(failed);
        }
        self.outbox_changed(station, thread);
    }

    /// The station has the message as `seq`: the entry stays until the chat's messages reach it (and leaves in
    /// that emission). Nobody looking at the chat: it goes now.
    pub fn outbox_sent(&self, station: &str, thread: u64, id: &str, seq: u64) {
        if !self.views.borrow().contains_key(&Topic::Chat { station: station.to_string(), thread }) {
            return self.outbox_remove(station, thread, id);
        }
        if let Some(entry) = self.outbox.borrow_mut().get_mut(&(station.to_string(), thread)).and_then(|list| list.iter_mut().find(|m| m["id"] == id)) {
            entry["seq"] = json!(seq);
        }
        self.outbox_changed(station, thread);
    }

    /// Given up.
    pub fn outbox_remove(&self, station: &str, thread: u64, id: &str) {
        let mut outbox = self.outbox.borrow_mut();
        let at = (station.to_string(), thread);
        if let Some(list) = outbox.get_mut(&at) {
            list.retain(|m| m["id"] != id);
            if list.is_empty() {
                outbox.remove(&at);
            }
        }
        drop(outbox);
        self.outbox_changed(station, thread);
    }

    fn outbox_changed(&self, station: &str, thread: u64) {
        self.store.invalidate(&Topic::Chat { station: station.to_string(), thread });
    }

    pub fn start(&self, view: &Topic) {
        self.views.borrow_mut().insert(view.clone(), HashMap::new());
        self.sync(view);
        self.store.invalidate(view);
        if matches!(view, Topic::Chats { .. }) && !self.clock.replace(true) {
            self.tick();
        }
    }

    /// Waits for the viewer's next local midnight, then recomputes the `chats` views; stops when none is live.
    fn tick(&self) {
        let now = self.host.now_ms();
        let offset = self.host.utc_offset_min(now) as f64 * 60_000.0;
        let midnight = (((now + offset) / DAY_MS).floor() + 1.0) * DAY_MS - offset;
        // A second past it, so the day has surely turned.
        let sleep = self.host.sleep((midnight - now).max(0.0) as u64 + 1000);
        let me = self.me.clone();
        self.host.spawn(
            async move {
                sleep.await;
                let Some(views) = me.upgrade() else { return };
                let chats: Vec<Topic> = views.views.borrow().keys().filter(|v| matches!(v, Topic::Chats { .. })).cloned().collect();
                if chats.is_empty() {
                    views.clock.set(false);
                    return;
                }
                for view in &chats {
                    views.store.invalidate(view);
                }
                views.tick();
            }
            .boxed_local(),
        );
    }

    pub fn stop(&self, view: &Topic) {
        let watches = self.views.borrow_mut().remove(view);
        // Released with nothing borrowed here.
        drop(watches);
    }

    /// The view's value now; `None` while what it rests on (the workspace, the session) has not been read.
    pub fn compute(&self, view: &Topic) -> Option<Result<Value>> {
        if !self.views.borrow().contains_key(view) {
            return None;
        }
        self.sync(view);
        match view {
            Topic::Chats { scope, mine } => self.chats(scope, *mine),
            Topic::Stations { scope } => self.stations_view(scope),
            Topic::Connects { scope, mine } => self.connects(scope, *mine),
            Topic::Chat { station, thread } => self.chat(station, *thread),
            _ => None,
        }
    }

    /// Watches what the view needs now and lets go of the rest.
    fn sync(&self, view: &Topic) {
        let wanted = self.sources(view);
        let (released, missing) = {
            let mut views = self.views.borrow_mut();
            let Some(watches) = views.get_mut(view) else { return };
            let gone: Vec<Topic> = watches.keys().filter(|t| !wanted.contains(*t)).cloned().collect();
            let released: Vec<Watch> = gone.iter().filter_map(|t| watches.remove(t)).collect();
            let missing: Vec<Topic> = wanted.into_iter().filter(|t| !watches.contains_key(t)).collect();
            (released, missing)
        };
        drop(released);
        for topic in missing {
            let store = Rc::downgrade(&self.store);
            let target = view.clone();
            let watch = self.store.watch(&topic, Rc::new(move || invalidate(&store, &target)));
            if let Some(watches) = self.views.borrow_mut().get_mut(view) {
                watches.insert(topic, watch);
            }
        }
    }

    /// The topics a view is built from, given what is known now.
    fn sources(&self, view: &Topic) -> HashSet<Topic> {
        let mut topics = HashSet::new();
        let (scope, per_station): (&str, fn(String) -> Vec<Topic>) = match view {
            Topic::Chats { scope, .. } => (scope.as_str(), |station| {
                vec![Topic::Sessions { station: station.clone() }, Topic::Overview { station: station.clone() }, Topic::Threads { station: station.clone() }, Topic::Link { station }]
            }),
            Topic::Stations { scope } => (scope.as_str(), |station| vec![Topic::Link { station: station.clone() }, Topic::Overview { station: station.clone() }, Topic::Host { station }]),
            Topic::Connects { scope, .. } => (scope.as_str(), |station| vec![Topic::Overview { station }]),
            Topic::Chat { station, thread } => {
                // Its agents, once the station's threads say who they are.
                for key in self.thread_of(station, *thread).as_ref().map(members).unwrap_or_default() {
                    topics.insert(Topic::Session { station: station.clone(), key });
                }
                topics.insert(Topic::Threads { station: station.clone() });
                topics.insert(Topic::Sessions { station: station.clone() });
                topics.insert(Topic::Thread { station: station.clone(), thread: *thread });
                if let Some(companion) = self.companion(station, *thread) {
                    topics.insert(Topic::Thread { station: station.clone(), thread: companion });
                }
                topics.insert(Topic::Overview { station: station.clone() });
                topics.insert(Topic::Link { station: station.clone() });
                return topics;
            }
            _ => return topics,
        };
        if scope != "local" {
            topics.insert(Topic::Workspace { workspace: scope.to_string() });
        }
        if let Some(Ok(stations)) = self.stations(scope) {
            topics.extend(stations.into_iter().filter(|s| s.online).flat_map(|s| per_station(s.address)));
        }
        topics
    }

    /// The scope's stations; `None` until the workspace has been read.
    fn stations(&self, scope: &str) -> Option<Result<Vec<StationInfo>>> {
        if scope == "local" {
            // A station's own page: the web shows no name for it.
            let local = StationInfo { address: "local".into(), id: "local".into(), name: String::new(), online: true, last_seen: Value::Null, version: Value::Null };
            return Some(Ok(vec![local]));
        }
        let workspace = match self.store.value(&Topic::Workspace { workspace: scope.to_string() })? {
            Ok(workspace) => workspace,
            Err(error) => return Some(Err(error)),
        };
        let stations = workspace.get("stations").and_then(Value::as_array).into_iter().flatten().filter_map(|s| {
            let id = s.get("id")?.as_str()?.to_string();
            let last_seen = s.get("last_seen").cloned().unwrap_or(Value::Null);
            // Connected to ember cloud right now (its presence socket), as the cloud says.
            let online = s.get("online").and_then(Value::as_bool).unwrap_or(false);
            Some(StationInfo {
                address: format!("{scope}/{id}"),
                name: s.get("name").and_then(Value::as_str).unwrap_or(&id).to_string(),
                id,
                online,
                last_seen,
                version: s.get("version").cloned().unwrap_or(Value::Null),
            })
        });
        Some(Ok(stations.collect()))
    }

    /// Who is looking: the account that reaches the workspace, or "local" on a station's own page.
    fn me(&self, scope: &str) -> Value {
        if scope == "local" {
            return json!({ "id": "local", "email": null });
        }
        let email = (self.email_of)(scope);
        json!({ "id": email, "email": email })
    }

    /// A thread as the station's `threads` topic has it.
    /**
     * A Slack chat's internal chat on ember: the ember thread of one of its
     * agents (the oldest). What is written on ember's page in the Slack chat
     * goes there — it reaches the agent like a Slack message, and the agent
     * answers there, not in Slack — and the page shows both together.
     */
    fn companion(&self, station: &str, id: u64) -> Option<u64> {
        let threads = self.ok(Topic::Threads { station: station.to_string() })?;
        let list = threads.as_array()?;
        let thread = list.iter().find(|t| t.get("id").and_then(Value::as_u64) == Some(id))?;
        if thread.get("surface").and_then(Value::as_str) == Some("ember") {
            return None;
        }
        let keys = members(thread);
        list.iter()
            .filter(|t| t.get("surface").and_then(Value::as_str) == Some("ember"))
            .filter(|t| members(t).iter().any(|k| keys.contains(k)))
            .filter_map(|t| t.get("id").and_then(Value::as_u64))
            .min()
    }

    /// Where a message written in this chat goes: the chat itself, a Slack chat's internal chat, or — a Slack chat
    /// whose agent has none yet — a new one to make for that agent's session first.
    pub fn send_target(&self, station: &str, id: u64) -> SendTarget {
        let Some(thread) = self.thread_of(station, id) else { return SendTarget::Thread(id) };
        if thread.get("surface").and_then(Value::as_str) == Some("ember") {
            return SendTarget::Thread(id);
        }
        match self.companion(station, id) {
            Some(companion) => SendTarget::Thread(companion),
            None => members(&thread).into_iter().next().map_or(SendTarget::Thread(id), SendTarget::NewChatFor),
        }
    }

    fn thread_of(&self, station: &str, id: u64) -> Option<Value> {
        self.ok(Topic::Threads { station: station.to_string() })?.as_array()?.iter().find(|t| t.get("id").and_then(Value::as_u64) == Some(id)).cloned()
    }

    fn ok(&self, topic: Topic) -> Option<Value> {
        self.store.value(&topic)?.ok()
    }

    /// The station's link as `{ state, message }`.
    fn link(&self, station: &str, online: bool) -> Value {
        if !online {
            return json!({ "state": "offline", "message": null });
        }
        match self.store.value(&Topic::Link { station: station.to_string() }) {
            Some(Ok(link)) => json!({ "state": link.get("state").cloned().unwrap_or(json!("connecting")), "message": link.get("message").cloned().unwrap_or(Value::Null) }),
            Some(Err(error)) => json!({ "state": "error", "message": error.message }),
            None => json!({ "state": "connecting", "message": null }),
        }
    }

    fn chats(&self, scope: &str, mine: bool) -> Option<Result<Value>> {
        let stations = match self.stations(scope)? {
            Ok(stations) => stations,
            Err(error) => return Some(Err(error)),
        };
        let me = self.me(scope);
        let mut states = Vec::new();
        let mut rows = Vec::new();
        let mut loading = false;
        for s in &stations {
            let (state, message) = if !s.online {
                ("offline", Value::Null)
            } else {
                let link = self.link(&s.address, true);
                let link_state = link["state"].as_str().unwrap_or("connecting");
                let link_message = link["message"].clone();
                let sessions = self.store.value(&Topic::Sessions { station: s.address.clone() });
                let threads = self.store.value(&Topic::Threads { station: s.address.clone() });
                match (sessions, threads) {
                    (Some(Err(error)), _) | (_, Some(Err(error))) => ("error", json!(error.message)),
                    (Some(Ok(sessions)), Some(Ok(threads))) => {
                        let connects = self.ok(Topic::Overview { station: s.address.clone() }).and_then(|o| o.get("connects").cloned());
                        let shown: HashMap<&str, &Value> = sessions.as_array().into_iter().flatten().filter_map(|summary| Some((summary.get("key")?.as_str()?, summary))).collect();
                        for thread in threads.as_array().into_iter().flatten() {
                            if let Some(row) = chat_row(&me, mine, s, thread, &shown, connects.as_ref()) {
                                rows.push(row);
                            }
                        }
                        // Chats already read stay in view while the link comes back.
                        match link_state {
                            "error" => ("error", link_message),
                            "offline" => ("connecting", link_message),
                            _ => ("online", Value::Null),
                        }
                    }
                    _ => {
                        loading = true;
                        if link_state == "error" { ("error", link_message) } else { ("connecting", Value::Null) }
                    }
                }
            };
            states.push(json!({ "station": s.address, "id": s.id, "name": s.name, "state": state, "message": message }));
        }
        let days = self.days(rows);
        Some(Ok(json!({ "me": me, "stations": states, "loading": loading, "days": days })))
    }

    /// Rows newest first, grouped by the viewer's local calendar day.
    fn days(&self, mut rows: Vec<Value>) -> Vec<Value> {
        let at = |row: &Value| row["lastActiveAt"].as_f64().unwrap_or(0.0);
        rows.sort_by(|a, b| at(b).total_cmp(&at(a)));
        let day = |ms: f64| ((ms + self.host.utc_offset_min(ms) as f64 * 60_000.0) / DAY_MS).floor() as i64;
        let today = day(self.host.now_ms());
        let mut days: Vec<(i64, f64, Vec<Value>)> = Vec::new();
        for row in rows {
            let (t, d) = (at(&row), day(at(&row)));
            match days.last_mut() {
                Some((last, _, items)) if *last == d => items.push(row),
                _ => days.push((d, t, vec![row])),
            }
        }
        days.into_iter().map(|(d, t, items)| json!({ "daysAgo": today - d, "at": t, "items": items })).collect()
    }

    fn stations_view(&self, scope: &str) -> Option<Result<Value>> {
        let stations = match self.stations(scope)? {
            Ok(stations) => stations,
            Err(error) => return Some(Err(error)),
        };
        let items = stations.iter().map(|s| {
            let read = |topic: Topic| if s.online { self.ok(topic) } else { None };
            let overview = read(Topic::Overview { station: s.address.clone() });
            let host = read(Topic::Host { station: s.address.clone() });
            json!({
                "station": s.address, "id": s.id, "name": s.name,
                "online": s.online, "lastSeen": s.last_seen, "version": s.version,
                "link": self.link(&s.address, s.online),
                "runtimes": runtimes(overview.as_ref()),
                "overview": overview, "host": host,
            })
        });
        Some(Ok(Value::Array(items.collect())))
    }

    fn connects(&self, scope: &str, mine: bool) -> Option<Result<Value>> {
        let stations = match self.stations(scope)? {
            Ok(stations) => stations,
            Err(error) => return Some(Err(error)),
        };
        let me = self.me(scope);
        let mut items = Vec::new();
        let mut loading = false;
        for s in stations.iter().filter(|s| s.online) {
            match self.store.value(&Topic::Overview { station: s.address.clone() }) {
                None => loading = true,
                Some(Err(_)) => {}
                Some(Ok(overview)) => {
                    for connect in overview.get("connects").and_then(Value::as_array).into_iter().flatten() {
                        // Who added it is an email, or "local" (as the web's Connects page read it).
                        let creator = connect.get("createdBy").and_then(|c| c.get("id")).map(|id| json!({ "id": id, "email": id }));
                        if mine && !is_mine(&me, creator.as_ref()) {
                            continue;
                        }
                        items.push(json!({ "station": s.address, "stationName": s.name, "connect": connect }));
                    }
                }
            }
        }
        Some(Ok(json!({ "me": me, "items": items, "loading": loading })))
    }

    fn chat(&self, station: &str, id: u64) -> Option<Result<Value>> {
        let threads = match self.store.value(&Topic::Threads { station: station.to_string() })? {
            Ok(threads) => threads,
            Err(error) => return Some(Err(error)),
        };
        let Some(thread) = threads.as_array().into_iter().flatten().find(|t| t.get("id").and_then(Value::as_u64) == Some(id)).cloned() else {
            return Some(Err(CoreError::new("http_404", "没有这个对话").with_status(404)));
        };
        // It shows as soon as its latest messages are read; its agents fill in as they are.
        let page = match self.store.value(&Topic::Thread { station: station.to_string(), thread: id })? {
            Ok(page) => page,
            Err(error) => return Some(Err(error)),
        };
        let overview = self.ok(Topic::Overview { station: station.to_string() });
        let of = |list: &str, id: Option<&Value>| find(overview.as_ref().and_then(|o| o.get(list)), id);
        let summaries = self.ok(Topic::Sessions { station: station.to_string() });
        let mut agents = Vec::new();
        for key in members(&thread) {
            // Until its detail is read, an agent is its summary from the station's list (no turns, no threads yet);
            // one that cannot be read at all (removed meanwhile) is left out.
            let detail = match self.store.value(&Topic::Session { station: station.to_string(), key: key.clone() }) {
                Some(Ok(detail)) => detail,
                Some(Err(_)) => continue,
                None => match summaries.as_ref().and_then(Value::as_array).and_then(|list| list.iter().find(|s| s.get("key").and_then(Value::as_str) == Some(&key))) {
                    Some(summary) => json!({ "session": summary }),
                    None => continue,
                },
            };
            let session = detail.get("session").cloned().unwrap_or(Value::Null);
            agents.push(json!({
                "session": session,
                "connect": of("connects", session.get("connect")),
                "profile": of("profiles", session.get("profile")),
                "turns": detail.get("turns").cloned().unwrap_or_else(|| json!([])),
                "threads": detail.get("threads").cloned().unwrap_or_else(|| json!([])),
            }));
        }
        let mut messages = page.get("messages").cloned().unwrap_or_else(|| json!([]));
        // A Slack chat also shows its internal chat: what was said to its agent on ember, and the answers.
        let companion = self.companion(station, id);
        if let Some(Ok(extra)) = companion.and_then(|c| self.store.value(&Topic::Thread { station: station.to_string(), thread: c })) {
            if let (Some(list), Some(more)) = (messages.as_array_mut(), extra.get("messages").and_then(Value::as_array)) {
                list.extend(more.iter().cloned());
                let key = |m: &Value| (m.get("createdAt").and_then(Value::as_f64).unwrap_or(0.0), m.get("seq").and_then(Value::as_u64).unwrap_or(0));
                list.sort_by(|a, b| key(a).partial_cmp(&key(b)).unwrap_or(std::cmp::Ordering::Equal));
            }
        }
        // A sent message leaves the outbox as its own copy (or anything later) arrives; seqs grow across threads.
        let newest = messages.as_array().and_then(|m| m.iter().filter_map(|m| m.get("seq")?.as_u64()).max());
        let at = (station.to_string(), id);
        let outbox = {
            let mut all = self.outbox.borrow_mut();
            let list = all.entry(at.clone()).or_default();
            list.retain(|m| !m.get("seq").and_then(Value::as_u64).is_some_and(|seq| newest.is_some_and(|n| n >= seq)));
            let shown = list.clone();
            if list.is_empty() {
                all.remove(&at);
            }
            shown
        };
        // The scope the station belongs to: "local", or its workspace.
        let scope = station.split_once('/').map_or(station, |(workspace, _)| workspace);
        Some(Ok(json!({
            "me": self.me(scope),
            "title": chat_title(&thread),
            "people": thread.get("people").cloned().unwrap_or_else(|| json!([])),
            "agents": agents,
            "messages": messages,
            "more": page.get("more").cloned().unwrap_or(json!(false)),
            "outbox": outbox,
            "sendTo": companion,
            "link": self.link(station, true),
            "thread": thread,
        })))
    }
}

/// See [`Views::send_target`].
pub enum SendTarget {
    Thread(u64),
    NewChatFor(String),
}

/// The session keys taking part in a thread.
fn members(thread: &Value) -> Vec<String> {
    thread.get("sessions").and_then(Value::as_array).into_iter().flatten().filter_map(|m| Some(m.get("session")?.as_str()?.to_string())).collect()
}

/// A thread as a row of the sidebar; `None` when none of its agents is shown (all archived), or with `mine` when the
/// viewer takes no part in it (started it or wrote in it).
fn chat_row(me: &Value, mine: bool, station: &StationInfo, thread: &Value, shown: &HashMap<&str, &Value>, connects: Option<&Value>) -> Option<Value> {
    let memberships: Vec<&Value> = thread.get("sessions").and_then(Value::as_array).into_iter().flatten().collect();
    let agents: Vec<Value> = memberships
        .iter()
        .filter_map(|m| shown.get(m.get("session")?.as_str()?))
        .map(|s| {
            let field = |name: &str| s.get(name).cloned().unwrap_or(Value::Null);
            json!({
                "key": field("key"), "runtime": field("runtime"), "model": field("model"), "effort": field("effort"),
                "process": field("process"), "pending": field("pending"), "lastTurn": field("lastTurn"),
            })
        })
        .collect();
    if agents.is_empty() {
        return None;
    }
    let people = thread.get("people").cloned().unwrap_or_else(|| json!([]));
    let takes_part = is_mine(me, thread.get("creator")) || people.as_array().is_some_and(|people| people.iter().any(|p| is_mine(me, Some(p))));
    if mine && !takes_part {
        return None;
    }
    let last = thread.get("last").filter(|l| l.is_object());
    let created = thread.get("createdAt").and_then(Value::as_f64).unwrap_or(0.0);
    let last_active = last.and_then(|l| l.get("createdAt")?.as_f64()).map_or(created, |at| at.max(created));
    // Where it came from: the connect of a Slack thread; ember's own chats have none.
    let connect = memberships.iter().filter_map(|m| m.get("connect")).find(|c| c.as_str() != Some("ember")).map_or(Value::Null, |c| find(connects, Some(c)));
    let pick = |from: &Value, names: &[&str]| Value::Object(names.iter().map(|n| (n.to_string(), from.get(*n).cloned().unwrap_or(Value::Null))).collect());
    let last = last.map_or(Value::Null, |l| {
        let mut short = pick(l, &["seq", "authorKind", "author", "authorName", "createdAt", "deletedAt"]);
        short["text"] = json!(l.get("text").and_then(Value::as_str).unwrap_or("").chars().take(LAST_CHARS).collect::<String>());
        short
    });
    Some(json!({
        "station": station.address,
        "stationName": station.name,
        "thread": pick(thread, &["id", "surface", "channel", "channelName", "threadTs", "title", "createdAt", "creator"]),
        "title": chat_title(thread),
        "agents": agents,
        "people": people,
        "last": last,
        "unread": thread.get("unread").and_then(Value::as_u64).unwrap_or(0) > 0,
        "lastActiveAt": last_active,
        "connect": connect,
    }))
}

/// What a chat is called: its title, else the first line a person wrote in it (Slack mentions left out), else its
/// Slack channel.
pub fn chat_title(thread: &Value) -> String {
    let text = |name: &str| thread.get(name).and_then(Value::as_str).map(str::trim).filter(|t| !t.is_empty());
    if let Some(title) = text("title") {
        return title.to_string();
    }
    let first = text("firstText").map(without_mentions).and_then(|t| t.lines().map(|l| l.split_whitespace().collect::<Vec<_>>().join(" ")).find(|l| !l.is_empty()));
    if let Some(first) = first {
        return first;
    }
    if let Some(channel) = text("channelName") {
        return format!("#{channel}");
    }
    if thread.get("surface").and_then(Value::as_str) != Some("ember") && text("channel").is_some_and(|c| c.starts_with('D')) {
        return "私信".to_string();
    }
    "（还没有消息）".to_string()
}

/// Text without Slack's `<@U123>` mentions.
fn without_mentions(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(at) = rest.find("<@") {
        out.push_str(&rest[..at]);
        let after = &rest[at + 2..];
        match after.find('>') {
            Some(end) if end > 0 && after[..end].chars().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit()) => rest = &after[end + 1..],
            _ => {
                out.push_str("<@");
                rest = after;
            }
        }
    }
    out.push_str(rest);
    out
}

fn invalidate(store: &Weak<Store>, view: &Topic) {
    if let Some(store) = store.upgrade() {
        store.invalidate(view);
    }
}

/// The item of `list` whose `id` is `id`, or null.
fn find(list: Option<&Value>, id: Option<&Value>) -> Value {
    let (Some(list), Some(id)) = (list.and_then(Value::as_array), id.filter(|id| !id.is_null())) else { return Value::Null };
    list.iter().find(|item| item.get("id") == Some(id)).cloned().unwrap_or(Value::Null)
}

/// Whether the viewer started a session: its creator's id, or email in any case, is theirs (useIsMine in web/src/station.tsx).
fn is_mine(me: &Value, creator: Option<&Value>) -> bool {
    let Some(creator) = creator.filter(|c| c.is_object()) else { return false };
    if creator.get("id").is_some_and(|id| !id.is_null() && Some(id) == me.get("id")) {
        return true;
    }
    let email = |v: &Value| v.get("email").and_then(Value::as_str).filter(|e| !e.is_empty()).map(str::to_lowercase);
    email(me).is_some_and(|mine| email(creator) == Some(mine))
}

/// The runtimes a chat can start on and their models: those with a profile that has models enabled,
/// each with its profiles' models (modelsOf in web/src/NewChat.tsx: distinct and sorted).
fn runtimes(overview: Option<&Value>) -> Value {
    let profiles: Vec<&Value> = overview.and_then(|o| o.get("profiles")).and_then(Value::as_array).into_iter().flatten().collect();
    let list = RUNTIMES.iter().filter_map(|runtime| {
        let models: BTreeSet<&str> = profiles
            .iter()
            .filter(|p| p.get("runtime").and_then(Value::as_str) == Some(runtime))
            .flat_map(|p| p.get("models").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str))
            .collect();
        (!models.is_empty()).then(|| json!({ "runtime": runtime, "models": models }))
    });
    Value::Array(list.collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::delta;
    use crate::error::CoreError;
    use crate::protocol::{CoreMessage, RequestId};
    use crate::store::{EVICT_AFTER_MS, Source};
    use crate::testing::{FakeHost, run};
    use std::cell::Cell;

    /// Timers run this many times faster, so evictions take well under a second.
    const SPEEDUP: u64 = 100;

    /// Routes views to `Views` like core.rs does; notes the other topics started and stopped.
    #[derive(Default)]
    struct Router {
        views: RefCell<Option<Rc<Views>>>,
        started: RefCell<Vec<Topic>>,
        stopped: RefCell<Vec<Topic>>,
        computed: Cell<usize>,
    }

    impl Router {
        fn views(&self) -> Rc<Views> {
            self.views.borrow().clone().unwrap()
        }
    }

    impl Source for Router {
        fn start(&self, topic: &Topic) {
            if topic.is_view() { self.views().start(topic) } else { self.started.borrow_mut().push(topic.clone()) }
        }
        fn stop(&self, topic: &Topic) {
            if topic.is_view() { self.views().stop(topic) } else { self.stopped.borrow_mut().push(topic.clone()) }
        }
        fn compute(&self, topic: &Topic) -> Option<Result<Value>> {
            self.computed.set(self.computed.get() + 1);
            self.views().compute(topic)
        }
    }

    struct Setup {
        host: Rc<FakeHost>,
        store: Rc<Store>,
        router: Rc<Router>,
    }

    fn setup() -> Setup {
        let host = FakeHost::new();
        host.speed_up(SPEEDUP);
        let store = Store::new(host.clone());
        let router = Rc::new(Router::default());
        let email_of: EmailOf = Rc::new(|ws: &str| (ws == "ws").then(|| "Me@x.com".to_string()));
        *router.views.borrow_mut() = Some(Views::new(host.clone(), store.clone(), email_of));
        store.set_source(router.clone());
        Setup { host, store, router }
    }

    /// What one UI subscription has seen: values and deltas applied, as the web client does.
    #[derive(Default)]
    struct Ui {
        value: Option<Value>,
        error: Option<CoreError>,
        messages: usize,
    }

    impl Setup {
        fn subscribe(&self, id: RequestId, topic: Topic) {
            self.store.subscribe(1, id, topic);
        }

        /// Lets the coalescing window pass and applies what client 1 got for `id`.
        async fn read(&self, ui: &mut Ui, id: RequestId) {
            self.host.settle().await;
            for (_, message) in self.host.take_emitted() {
                match message {
                    CoreMessage::Value { id: i, value } if i == id => (ui.value, ui.error) = (Some(value), None),
                    CoreMessage::Delta { id: i, delta } if i == id => delta::apply(ui.value.as_mut().expect("a delta needs a value"), &delta),
                    CoreMessage::Error { id: i, error } if i == id => ui.error = Some(error),
                    _ => continue,
                }
                ui.messages += 1;
            }
        }

        fn set(&self, topic: Topic, value: Value) {
            self.store.set(&topic, Ok(value));
        }

        fn started(&self) -> Vec<Topic> {
            std::mem::take(&mut self.router.started.borrow_mut())
        }

        fn stopped(&self) -> Vec<Topic> {
            let mut stopped = std::mem::take(&mut *self.router.stopped.borrow_mut());
            stopped.sort_by_key(|t| format!("{t:?}"));
            stopped
        }

        fn now_s(&self) -> f64 {
            self.host.now_ms() / 1000.0
        }
    }

    fn workspace() -> Topic {
        Topic::Workspace { workspace: "ws".into() }
    }
    fn sessions(st: &str) -> Topic {
        Topic::Sessions { station: st.into() }
    }
    fn overview(st: &str) -> Topic {
        Topic::Overview { station: st.into() }
    }
    fn link(st: &str) -> Topic {
        Topic::Link { station: st.into() }
    }
    fn threads(st: &str) -> Topic {
        Topic::Threads { station: st.into() }
    }
    fn host_of(st: &str) -> Topic {
        Topic::Host { station: st.into() }
    }
    fn sorted(mut topics: Vec<Topic>) -> Vec<Topic> {
        topics.sort_by_key(|t| format!("{t:?}"));
        topics
    }

    /// `a` and `b` online as asked, `c` never seen.
    fn stations(now_s: f64, a_online: bool, b_online: bool) -> Value {
        json!({"id": "ws", "stations": [
            {"id": "a", "name": "alpha", "online": a_online, "last_seen": now_s - 10.0, "version": "0.4.0"},
            {"id": "b", "name": "beta", "online": b_online, "last_seen": now_s - 1000.0, "version": null},
            {"id": "c", "name": "gamma", "online": false, "last_seen": null, "version": null},
        ]})
    }

    fn session(key: &str) -> Value {
        json!({"key": key, "connect": "c1", "profile": "p1", "runtime": "claude", "model": "opus", "effort": null, "process": "cold", "pending": 0, "lastTurn": null})
    }

    fn member(thread: u64, key: &str, connect: &str) -> Value {
        json!({"thread": thread, "session": key, "connect": connect})
    }

    /// A chat on ember's page with these agents, last written in at `at`.
    fn thread(id: u64, keys: &[&str], at: f64) -> Value {
        json!({
            "id": id, "surface": "ember", "channel": "EMBER", "channelName": null, "threadTs": format!("{id}.0"), "title": null,
            "createdAt": at - 10.0, "creator": null, "sessions": keys.iter().map(|k| member(id, k, "ember")).collect::<Vec<_>>(),
            "last": {"seq": id * 10, "rev": id * 10, "authorKind": "agent", "author": keys.first().copied().unwrap_or(""), "authorName": null, "text": "好的", "createdAt": at, "deletedAt": null},
            "rev": id * 10, "read": 0, "unread": 0, "people": [], "firstText": null,
        })
    }

    fn ids(v: &Value) -> Vec<u64> {
        v["days"].as_array().unwrap().iter().flat_map(|d| d["items"].as_array().unwrap().iter().map(|i| i["thread"]["id"].as_u64().unwrap())).collect()
    }

    #[test]
    fn chats_puts_together_the_online_stations() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Chats { scope: "ws".into(), mine: false });
            t.read(&mut ui, 1).await;
            assert_eq!(t.started(), vec![workspace()]);
            assert!(ui.value.is_none(), "nothing to show before the workspace is read");

            t.set(workspace(), stations(t.now_s(), true, false));
            t.read(&mut ui, 1).await;
            assert_eq!(sorted(t.started()), sorted(vec![sessions("ws/a"), overview("ws/a"), threads("ws/a"), link("ws/a")]));
            let v = ui.value.clone().unwrap();
            assert_eq!(v["me"], json!({"id": "Me@x.com", "email": "Me@x.com"}));
            assert_eq!(v["loading"], true);
            assert_eq!(v["stations"], json!([
                {"station": "ws/a", "id": "a", "name": "alpha", "state": "connecting", "message": null},
                {"station": "ws/b", "id": "b", "name": "beta", "state": "offline", "message": null},
                {"station": "ws/c", "id": "c", "name": "gamma", "state": "offline", "message": null},
            ]));
            assert_eq!(v["days"], json!([]));

            let now = t.host.now_ms();
            t.set(link("ws/a"), json!({"state": "online"}));
            t.set(overview("ws/a"), json!({"connects": [{"id": "c1", "name": "Slack"}]}));
            t.set(sessions("ws/a"), json!([session("s1"), session("s2")]));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.as_ref().unwrap()["loading"], true, "its threads are not read yet");
            let mut slack = thread(2, &["s1"], now - 2000.0);
            slack["surface"] = json!("slack:T1");
            slack["channel"] = json!("C1");
            slack["channelName"] = json!("ops");
            slack["sessions"] = json!([member(2, "s1", "c1")]);
            t.set(threads("ws/a"), json!([thread(1, &["s2", "gone"], now - 1000.0), slack]));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!(v["loading"], false);
            assert_eq!(v["stations"][0]["state"], "online");
            assert_eq!(v["days"][0]["at"], json!(now - 1000.0));
            let items = &v["days"][0]["items"];
            assert_eq!(ids(&v), vec![1, 2]);
            assert_eq!(items[0]["connect"], Value::Null, "ember's own chat comes from no connect");
            assert_eq!(items[0]["agents"], json!([{"key": "s2", "runtime": "claude", "model": "opus", "effort": null, "process": "cold", "pending": 0, "lastTurn": null}]), "only agents still shown");
            assert_eq!(items[0]["title"], "（还没有消息）");
            assert_eq!(items[0]["last"], json!({"seq": 10, "authorKind": "agent", "author": "s2", "authorName": null, "createdAt": now - 1000.0, "deletedAt": null, "text": "好的"}));
            assert_eq!(items[0]["lastActiveAt"], json!(now - 1000.0));
            assert_eq!(items[1]["connect"], json!({"id": "c1", "name": "Slack"}));
            assert_eq!(items[1]["title"], "#ops");
            assert_eq!(items[1]["thread"]["surface"], "slack:T1");
            assert_eq!(items[1]["unread"], false);
            assert_eq!((items[1]["station"].as_str(), items[1]["stationName"].as_str()), (Some("ws/a"), Some("alpha")));

            // One station failing shows as that station's state.
            t.store.set(&threads("ws/a"), Err(CoreError::new("http_500", "坏了")));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.as_ref().unwrap()["stations"][0], json!({"station": "ws/a", "id": "a", "name": "alpha", "state": "error", "message": "坏了"}));
            // The link dropping, with threads read: reconnecting.
            t.set(threads("ws/a"), json!([]));
            t.set(link("ws/a"), json!({"state": "offline", "message": "连接断开了"}));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.as_ref().unwrap()["stations"][0]["state"], "connecting");
            assert_eq!(ui.value.as_ref().unwrap()["stations"][0]["message"], "连接断开了");

            // The workspace failing is the view's error.
            t.store.set(&workspace(), Err(CoreError::new("not_found", "进不了这个工作区")));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.error.as_ref().unwrap().code, "not_found");
        });
    }

    #[test]
    fn follows_the_workspaces_station_list() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Chats { scope: "ws".into(), mine: false });
            t.set(workspace(), stations(t.now_s(), true, false));
            t.read(&mut ui, 1).await;
            t.started();
            // `b` comes online, `a` goes offline.
            t.set(workspace(), stations(t.now_s(), false, true));
            t.read(&mut ui, 1).await;
            assert_eq!(sorted(t.started()), sorted(vec![sessions("ws/b"), overview("ws/b"), threads("ws/b"), link("ws/b")]));
            let states: Vec<&str> = ui.value.as_ref().unwrap()["stations"].as_array().unwrap().iter().map(|s| s["state"].as_str().unwrap()).collect();
            assert_eq!(states, vec!["offline", "connecting", "offline"]);
            // `a`'s topics are let go: stopped after the grace, like a UI unsubscribing.
            assert!(t.stopped().is_empty());
            tokio::time::sleep(std::time::Duration::from_millis(EVICT_AFTER_MS * 5 / 4 / SPEEDUP)).await;
            assert_eq!(t.stopped(), sorted(vec![sessions("ws/a"), overview("ws/a"), threads("ws/a"), link("ws/a")]));
        });
    }

    #[test]
    fn groups_by_the_viewers_day_newest_first() {
        run(async {
            let t = setup();
            // UTC+8: local midnight is 16:00 UTC the day before.
            t.host.set_utc_offset_min(480);
            let now = t.host.now_ms();
            let offset = 480.0 * 60_000.0;
            let midnight = ((now + offset) / DAY_MS).floor() * DAY_MS - offset;
            let today = midnight + (now - midnight) / 2.0;
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Chats { scope: "local".into(), mine: false });
            t.set(sessions("local"), json!([session("a")]));
            // A chat nobody has written in yet is as new as the chat itself.
            let mut empty = thread(5, &["a"], 0.0);
            empty["last"] = Value::Null;
            empty["createdAt"] = json!(midnight - 3.0 * DAY_MS - 1000.0);
            t.set(threads("local"), json!([
                thread(1, &["a"], midnight - 1000.0),
                thread(2, &["a"], midnight - 2.0 * DAY_MS - 1000.0),
                thread(3, &["a"], today),
                thread(4, &["a"], midnight - DAY_MS + 1000.0),
                empty,
            ]));
            t.read(&mut ui, 1).await;
            let v = ui.value.unwrap();
            let days: Vec<(i64, Vec<u64>)> = v["days"]
                .as_array()
                .unwrap()
                .iter()
                .map(|d| (d["daysAgo"].as_i64().unwrap(), d["items"].as_array().unwrap().iter().map(|i| i["thread"]["id"].as_u64().unwrap()).collect()))
                .collect();
            assert_eq!(days, vec![(0, vec![3]), (1, vec![1, 4]), (3, vec![2]), (4, vec![5])]);
            assert_eq!(v["days"][1]["at"], json!(midnight - 1000.0));
            assert_eq!(v["me"], json!({"id": "local", "email": null}));
            assert_eq!(v["stations"], json!([{"station": "local", "id": "local", "name": "", "state": "online", "message": null}]));
        });
    }

    #[test]
    fn mine_keeps_the_chats_the_viewer_takes_part_in() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Chats { scope: "ws".into(), mine: true });
            t.set(workspace(), stations(t.now_s(), true, false));
            t.read(&mut ui, 1).await;
            let now = t.host.now_ms();
            t.set(sessions("ws/a"), json!([session("a")]));
            let with = |id: u64, creator: Value, people: Value| {
                let mut t = thread(id, &["a"], now - id as f64);
                t["creator"] = creator;
                t["people"] = people;
                t
            };
            t.set(threads("ws/a"), json!([
                with(1, json!({"id": "Me@x.com", "name": "我"}), json!([])),
                with(2, Value::Null, json!([{"id": "U9", "email": "you@x.com"}, {"id": "U123", "email": "me@X.com"}])),
                with(3, json!({"id": "U9", "email": "you@x.com"}), json!([{"id": "U9", "email": "you@x.com"}])),
                with(4, json!({"id": "U8", "email": null}), json!([{"id": "U8", "email": null}])),
                with(5, Value::Null, json!([])),
            ]));
            t.read(&mut ui, 1).await;
            assert_eq!(ids(ui.value.as_ref().unwrap()), vec![1, 2]);
        });
    }

    #[test]
    fn a_chats_unread_is_a_mark_and_its_title_comes_from_what_was_said() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Chats { scope: "local".into(), mine: false });
            let now = t.host.now_ms();
            t.set(sessions("local"), json!([session("a"), session("b")]));
            let mut named = thread(1, &["a"], now - 1.0);
            named["title"] = json!(" 排查 ");
            named["firstText"] = json!("不用这个");
            named["unread"] = json!(2);
            let mut said = thread(2, &["a", "b"], now - 2.0);
            said["firstText"] = json!("\n <@U0BOT>  看看   这个\n第二行");
            let mut dm = thread(3, &["b"], now - 3.0);
            dm["surface"] = json!("slack:T1");
            dm["channel"] = json!("D1");
            dm["unread"] = json!(7);
            let archived = thread(4, &["gone"], now - 4.0);
            t.set(threads("local"), json!([named, said, dm, archived]));
            t.read(&mut ui, 1).await;
            let items = ui.value.clone().unwrap()["days"][0]["items"].clone();
            let rows: Vec<(u64, &str, bool, usize)> = items
                .as_array()
                .unwrap()
                .iter()
                .map(|i| (i["thread"]["id"].as_u64().unwrap(), i["title"].as_str().unwrap(), i["unread"].as_bool().unwrap(), i["agents"].as_array().unwrap().len()))
                .collect();
            assert_eq!(rows, vec![(1, "排查", true, 1), (2, "看看 这个", false, 2), (3, "私信", true, 1)], "a chat whose agents are all hidden is not listed");
            // Read: the mark follows the threads topic.
            t.store.update(&threads("local"), &mut |list| list[0]["unread"] = json!(0));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.clone().unwrap()["days"][0]["items"][0]["unread"], false);
        });
    }

    #[test]
    fn many_changes_are_one_computation_and_one_emission() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Chats { scope: "ws".into(), mine: false });
            t.set(workspace(), stations(t.now_s(), true, true));
            t.read(&mut ui, 1).await;
            let (computed, messages) = (t.router.computed.get(), ui.messages);
            for st in ["ws/a", "ws/b"] {
                t.set(link(st), json!({"state": "online"}));
                t.set(overview(st), json!({"connects": []}));
                t.set(sessions(st), json!([session(st)]));
                t.set(threads(st), json!([thread(1, &[st], t.host.now_ms())]));
            }
            t.store.update(&threads("ws/a"), &mut |v| v[0]["title"] = json!("改了"));
            t.read(&mut ui, 1).await;
            assert_eq!(t.router.computed.get(), computed + 1);
            assert_eq!(ui.messages, messages + 1);
            assert_eq!(ui.value.as_ref().unwrap()["days"][0]["items"].as_array().unwrap().len(), 2);
            // Recomputed to the same value: nothing goes out.
            t.set(overview("ws/a"), json!({"connects": []}));
            t.read(&mut ui, 1).await;
            assert_eq!(t.router.computed.get(), computed + 2);
            assert_eq!(ui.messages, messages + 1);
        });
    }

    #[test]
    fn a_stopped_view_lets_its_topics_go() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Stations { scope: "ws".into() });
            t.set(workspace(), stations(t.now_s(), true, false));
            t.read(&mut ui, 1).await;
            assert_eq!(sorted(t.started()), sorted(vec![workspace(), link("ws/a"), overview("ws/a"), host_of("ws/a")]));
            t.store.unsubscribe(1, 1);
            // The view itself goes after the grace, then what it watched after another.
            tokio::time::sleep(std::time::Duration::from_millis(EVICT_AFTER_MS * 5 / 4 / SPEEDUP)).await;
            assert!(t.stopped().is_empty());
            tokio::time::sleep(std::time::Duration::from_millis(EVICT_AFTER_MS * 5 / 4 / SPEEDUP)).await;
            assert_eq!(t.stopped(), sorted(vec![workspace(), link("ws/a"), overview("ws/a"), host_of("ws/a")]));
            assert!(t.store.live_topics().is_empty());
        });
    }

    #[test]
    fn stations_shows_each_station_with_its_models() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Stations { scope: "ws".into() });
            t.set(workspace(), stations(t.now_s(), true, false));
            t.read(&mut ui, 1).await;
            let overview_a = json!({"connects": [], "profiles": [
                {"id": "p1", "runtime": "codex", "models": ["o3", "gpt-5"]},
                {"id": "p2", "runtime": "claude", "models": []},
                {"id": "p3", "runtime": "claude", "models": ["sonnet"]},
                {"id": "p4", "runtime": "claude", "models": ["opus", "sonnet"]},
            ]});
            t.set(overview("ws/a"), overview_a.clone());
            t.set(host_of("ws/a"), json!({"hostname": "studio"}));
            t.set(link("ws/a"), json!({"state": "error", "message": "没有权限"}));
            t.read(&mut ui, 1).await;
            let v = ui.value.unwrap();
            let seen = t.now_s();
            assert!(v[0]["lastSeen"].as_f64().is_some_and(|s| (seen - s - 10.0).abs() < 5.0));
            assert_eq!(v[0]["version"], "0.4.0");
            assert_eq!(v[0]["online"], true);
            assert_eq!(v[0]["link"], json!({"state": "error", "message": "没有权限"}));
            assert_eq!(v[0]["overview"], overview_a);
            assert_eq!(v[0]["host"], json!({"hostname": "studio"}));
            assert_eq!(v[0]["runtimes"], json!([{"runtime": "claude", "models": ["opus", "sonnet"]}, {"runtime": "codex", "models": ["gpt-5", "o3"]}]));
            assert_eq!(
                v[1],
                json!({"station": "ws/b", "id": "b", "name": "beta", "online": false, "lastSeen": v[1]["lastSeen"], "version": null,
                    "link": {"state": "offline", "message": null}, "overview": null, "host": null, "runtimes": []})
            );
            assert_eq!(v[2]["lastSeen"], Value::Null);
        });
    }

    #[test]
    fn connects_lists_every_online_stations_connects() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Connects { scope: "ws".into(), mine: false });
            t.set(workspace(), stations(t.now_s(), true, true));
            t.read(&mut ui, 1).await;
            assert_eq!(sorted(t.started()), sorted(vec![workspace(), overview("ws/a"), overview("ws/b")]));
            let me = json!({"id": "Me@x.com", "email": "Me@x.com"});
            assert_eq!(ui.value.as_ref().unwrap(), &json!({"me": me, "items": [], "loading": true}));
            let c1 = json!({"id": "c1", "createdBy": {"id": "me@x.com", "name": "我"}});
            let c2 = json!({"id": "c2", "createdBy": null});
            t.set(overview("ws/a"), json!({"connects": [c1, c2]}));
            t.store.set(&overview("ws/b"), Err(CoreError::new("offline", "连不上")));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.as_ref().unwrap(), &json!({"me": me, "items": [
                {"station": "ws/a", "stationName": "alpha", "connect": c1},
                {"station": "ws/a", "stationName": "alpha", "connect": c2},
            ], "loading": false}));
            // Only mine: the connects the viewer added.
            let mut mine = Ui::default();
            t.subscribe(2, Topic::Connects { scope: "ws".into(), mine: true });
            t.read(&mut mine, 2).await;
            assert_eq!(mine.value.unwrap()["items"], json!([{"station": "ws/a", "stationName": "alpha", "connect": c1}]));
        });
    }

    #[test]
    fn chats_turns_the_day_at_local_midnight() {
        run(async {
            let t = setup();
            t.host.set_utc_offset_min(480);
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Chats { scope: "local".into(), mine: false });
            t.read(&mut ui, 1).await;
            // One clock, set for the next local midnight (and a second).
            let now = t.host.now_ms();
            let offset = 480.0 * 60_000.0;
            let midnight = (((now + offset) / DAY_MS).floor() + 1.0) * DAY_MS - offset;
            let asked: Vec<u64> = t.host.sleeps.borrow().iter().copied().filter(|ms| *ms > EVICT_AFTER_MS).collect();
            assert_eq!(asked.len(), 1, "{:?}", t.host.sleeps.borrow());
            assert!((asked[0] as f64 - (midnight - now + 1000.0)).abs() < 2000.0);
            // A second chats view shares it.
            t.subscribe(2, Topic::Chats { scope: "local".into(), mine: true });
            t.host.settle().await;
            assert_eq!(t.host.sleeps.borrow().iter().filter(|ms| **ms > EVICT_AFTER_MS).count(), 1);
        });
    }

    fn chat_topic(st: &str, id: u64) -> Topic {
        Topic::Chat { station: st.into(), thread: id }
    }
    fn session_of(st: &str, key: &str) -> Topic {
        Topic::Session { station: st.into(), key: key.into() }
    }
    fn page_of(st: &str, id: u64) -> Topic {
        Topic::Thread { station: st.into(), thread: id }
    }

    #[test]
    fn chat_is_a_thread_its_messages_and_its_agents() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, chat_topic("ws/a", 7));
            t.read(&mut ui, 1).await;
            // Its thread and its messages are asked for at once.
            assert_eq!(sorted(t.started()), sorted(vec![threads("ws/a"), sessions("ws/a"), page_of("ws/a", 7), overview("ws/a"), link("ws/a")]));
            assert!(ui.value.is_none(), "nothing before the thread is read");

            let now = t.host.now_ms();
            let mut chat = thread(7, &["k", "j"], now);
            chat["title"] = json!("排查");
            chat["people"] = json!([{"id": "local", "name": "本机管理页", "email": null, "via": "local"}]);
            t.set(threads("ws/a"), json!([thread(3, &["k"], now), chat.clone()]));
            t.read(&mut ui, 1).await;
            assert_eq!(sorted(t.started()), sorted(vec![session_of("ws/a", "k"), session_of("ws/a", "j")]), "its agents are read next");
            let page: Vec<Value> = (11..=40).map(|i| json!({"seq": i, "text": format!("第 {i} 条")})).collect();
            t.set(page_of("ws/a", 7), json!({"rev": 40, "messages": page, "more": true}));
            t.read(&mut ui, 1).await;
            // The messages do not wait for the agents: those not read yet are their summaries where the list has them.
            let v = ui.value.clone().expect("shown once the thread and its messages are read");
            assert_eq!(v["agents"], json!([]));
            t.set(sessions("ws/a"), json!([{"key": "j", "connect": "ember", "profile": "p1"}]));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.clone().unwrap()["agents"], json!([{"session": {"key": "j", "connect": "ember", "profile": "p1"}, "connect": null, "profile": null, "turns": [], "threads": []}]));

            t.set(session_of("ws/a", "k"), json!({"session": {"key": "k", "connect": "c1", "profile": "p2"}, "threads": [chat.clone()], "turns": [{"id": "t1"}]}));
            t.store.set(&session_of("ws/a", "j"), Err(CoreError::new("http_404", "没有这个会话")));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!(v["me"], json!({"id": "Me@x.com", "email": "Me@x.com"}));
            assert_eq!(v["title"], "排查");
            assert_eq!(v["thread"], chat);
            assert_eq!(v["people"], chat["people"]);
            assert_eq!(v["link"], json!({"state": "connecting", "message": null}));
            assert_eq!((v["messages"].as_array().unwrap().len(), v["more"].clone()), (30, json!(true)));
            assert_eq!(v["agents"].as_array().unwrap().len(), 1, "an agent that cannot be read is left out");
            assert_eq!(v["agents"][0]["session"]["key"], "k");
            assert_eq!(v["agents"][0]["turns"], json!([{"id": "t1"}]));
            assert_eq!(v["agents"][0]["threads"], json!([chat]));
            assert_eq!((v["agents"][0]["connect"].clone(), v["agents"][0]["profile"].clone()), (Value::Null, Value::Null));

            t.set(overview("ws/a"), json!({"connects": [{"id": "c1", "name": "Slack"}], "profiles": [{"id": "p1"}, {"id": "p2", "name": "主力"}]}));
            t.set(link("ws/a"), json!({"state": "online"}));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!(v["agents"][0]["connect"], json!({"id": "c1", "name": "Slack"}));
            assert_eq!(v["agents"][0]["profile"], json!({"id": "p2", "name": "主力"}));
            assert_eq!(v["link"], json!({"state": "online", "message": null}));

            // A new message goes out as an append.
            t.store.update(&page_of("ws/a", 7), &mut |p| p["messages"].as_array_mut().unwrap().push(json!({"seq": 41, "text": "新的"})));
            t.host.settle().await;
            let sent = t.host.take_emitted();
            assert_eq!(sent.len(), 1);
            let CoreMessage::Delta { delta, .. } = &sent[0].1 else { panic!("{:?}", sent[0]) };
            assert_eq!(serde_json::to_value(delta).unwrap(), json!([{"path": ["messages"], "append": [{"seq": 41, "text": "新的"}]}]));
            // An older page, in front.
            t.store.update(&page_of("ws/a", 7), &mut |p| {
                p["messages"].as_array_mut().unwrap().insert(0, json!({"seq": 10, "text": "旧的"}));
                p["more"] = json!(false);
            });
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!((v["messages"][0]["seq"].clone(), v["messages"].as_array().unwrap().len(), v["more"].clone()), (json!(10), 32, json!(false)));

            // Another agent joins: it is read, and shows once it is.
            t.store.update(&threads("ws/a"), &mut |list| list[1]["sessions"].as_array_mut().unwrap().push(member(7, "n", "ember")));
            t.read(&mut ui, 1).await;
            assert_eq!(t.started(), vec![session_of("ws/a", "n")]);
            t.set(session_of("ws/a", "n"), json!({"session": {"key": "n", "connect": "ember", "profile": "p1"}, "threads": [], "turns": []}));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.clone().unwrap()["agents"].as_array().unwrap().iter().map(|a| a["session"]["key"].as_str().unwrap()).collect::<Vec<_>>(), vec!["k", "n"]);

            // The thread going (its last agent deleted) is the view's error.
            t.set(threads("ws/a"), json!([thread(3, &["k"], now)]));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.error.as_ref().unwrap().status, Some(404));
        });
    }

    #[test]
    fn a_slack_chat_is_its_thread_like_any_other() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, chat_topic("local", 3));
            let mut slack = thread(3, &["k"], t.host.now_ms());
            slack["surface"] = json!("slack:T1");
            slack["channel"] = json!("C1");
            slack["channelName"] = json!("ops");
            slack["firstText"] = json!("<@U0BOT> 部署挂了");
            slack["sessions"] = json!([member(3, "k", "c1")]);
            t.set(threads("local"), json!([slack]));
            t.set(page_of("local", 3), json!({"rev": 2, "messages": [{"seq": 1, "authorKind": "person", "text": "<@U0BOT> 部署挂了"}, {"seq": 2, "authorKind": "agent", "text": "在看"}], "more": false}));
            t.read(&mut ui, 1).await;
            t.set(session_of("local", "k"), json!({"session": {"key": "k", "connect": "c1"}, "threads": [], "turns": []}));
            t.read(&mut ui, 1).await;
            let v = ui.value.unwrap();
            assert_eq!(v["title"], "部署挂了");
            assert_eq!(v["thread"]["surface"], "slack:T1");
            assert_eq!(v["messages"].as_array().unwrap().len(), 2);
            assert_eq!(v["me"], json!({"id": "local", "email": null}));
        });
    }

    #[test]
    fn a_sent_message_shows_until_the_chat_has_it() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, chat_topic("ws/a", 7));
            t.set(threads("ws/a"), json!([thread(7, &[], t.host.now_ms())]));
            t.set(page_of("ws/a", 7), json!({"rev": 5, "messages": [{"seq": 5, "text": "早"}], "more": false}));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.clone().unwrap()["outbox"], json!([]));

            let views = t.router.views();
            let id = views.outbox_add("ws/a", 7, json!({"text": "你好", "attachments": [], "quotes": []}));
            t.read(&mut ui, 1).await;
            let out = ui.value.clone().unwrap()["outbox"].clone();
            assert_eq!((out[0]["id"].as_str(), out[0]["text"].as_str(), out[0]["state"].as_str()), (Some(id.as_str()), Some("你好"), Some("sending")));

            views.outbox_state("ws/a", 7, &id, Some("连不上 station"));
            t.read(&mut ui, 1).await;
            let out = ui.value.clone().unwrap()["outbox"].clone();
            assert_eq!((out[0]["state"].as_str(), out[0]["error"].as_str()), (Some("failed"), Some("连不上 station")));

            // Sent as seq 6: it stays until the messages reach 6, and leaves in that same emission.
            views.outbox_state("ws/a", 7, &id, None);
            views.outbox_sent("ws/a", 7, &id, 6);
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.clone().unwrap()["outbox"][0]["seq"], 6);
            t.store.update(&page_of("ws/a", 7), &mut |p| p["messages"].as_array_mut().unwrap().push(json!({"seq": 6, "text": "你好"})));
            t.host.settle().await;
            let sent = t.host.take_emitted();
            assert_eq!(sent.len(), 1);
            let CoreMessage::Delta { delta, .. } = &sent[0].1 else { panic!("{:?}", sent[0]) };
            let ops = serde_json::to_value(delta).unwrap();
            assert!(ops.as_array().unwrap().iter().any(|op| op["path"] == json!(["messages"])), "{ops}");
            assert!(ops.as_array().unwrap().iter().any(|op| op["path"] == json!(["outbox"]) && op["set"] == json!([])), "{ops}");
            // Sent while nobody looks: gone at once.
            let id = views.outbox_add("ws/b", 1, json!({"text": "x"}));
            views.outbox_sent("ws/b", 1, &id, 1);
            assert!(views.outbox_get("ws/b", 1, &id).is_none());
        });
    }
}
