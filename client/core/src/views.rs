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
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::rc::{Rc, Weak};

use futures::FutureExt;
use serde_json::{Value, json};

use crate::entries::merge;
use crate::error::{CoreError, Result};
use crate::host::Host;
use crate::protocol::Topic;
use crate::store::{Store, Watch};

/// The runtimes a chat can run on, in the order they are offered.
const RUNTIMES: [&str; 2] = ["claude", "codex"];
const DAY_MS: f64 = 86_400_000.0;

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

    /// The station has the message as entry `seq`: it stays until the chat's entries reach it (and leaves in that
    /// emission). Nobody looking at the chat: it goes now.
    pub fn outbox_sent(&self, station: &str, thread: u64, id: &str, seq: u64) {
        if self.chat_views(station, thread).is_empty() {
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
        for view in self.chat_views(station, thread) {
            self.store.invalidate(&view);
        }
    }

    /// The live pages showing a chat: by its thread, or by its agent once the chat is the agent's.
    fn chat_views(&self, station: &str, thread: u64) -> Vec<Topic> {
        let views: Vec<Topic> = self.views.borrow().keys().cloned().collect();
        views
            .into_iter()
            .filter(|view| match view {
                Topic::Chat { station: s, thread: Some(t), .. } => s == station && *t == thread,
                Topic::Chat { station: s, thread: None, session: Some(key) } => s == station && self.bound_thread(s, key) == Some(thread),
                _ => false,
            })
            .collect()
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
            Topic::Chat { station, thread: Some(thread), .. } => self.chat(station, *thread),
            // An item's page by its agent: its chat once it has one (made here or elsewhere), else the agent alone.
            Topic::Chat { station, thread: None, session: Some(key) } => match self.bound_thread(station, key) {
                Some(thread) => self.chat(station, thread),
                None => self.unchatted(station, key),
            },
            Topic::Chat { .. } => Some(Err(CoreError::invalid("chat 要有 thread 或 session"))),
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
            // Its overview says which Slack users are the viewer (a row's last thing said by one is "你").
            Topic::Chats { scope, .. } => (scope.as_str(), |station| vec![Topic::ChatRows { station: station.clone() }, Topic::Overview { station: station.clone() }, Topic::Link { station }]),
            Topic::Stations { scope } => (scope.as_str(), |station| vec![Topic::Link { station: station.clone() }, Topic::Overview { station: station.clone() }, Topic::Host { station }]),
            Topic::Connects { scope, .. } => (scope.as_str(), |station| vec![Topic::Overview { station }]),
            Topic::Chat { station, thread: None, session: Some(key) } if self.bound_thread(station, key).is_some() => {
                let thread = self.bound_thread(station, key);
                return self.sources(&Topic::Chat { station: station.clone(), thread, session: None });
            }
            Topic::Chat { station, thread: None, session } => {
                // An agent with no chat yet: itself, and its title as the station's items have it.
                if let Some(key) = session {
                    topics.insert(Topic::Session { station: station.clone(), key: key.clone() });
                }
                topics.insert(Topic::ChatRows { station: station.clone() });
                topics.insert(Topic::Sessions { station: station.clone() });
                topics.insert(Topic::Overview { station: station.clone() });
                topics.insert(Topic::Link { station: station.clone() });
                return topics;
            }
            Topic::Chat { station, thread: Some(thread), .. } => {
                // Its agents, once the station's threads (or the thread as kept) say who they are.
                let kept = || self.ok(Topic::Thread { station: station.clone(), thread: *thread })?.get("thread").filter(|t| t.is_object()).cloned();
                for key in self.thread_of(station, *thread).or_else(kept).as_ref().map(members).unwrap_or_default() {
                    topics.insert(Topic::Session { station: station.clone(), key });
                }
                topics.insert(Topic::Threads { station: station.clone() });
                topics.insert(Topic::Sessions { station: station.clone() });
                topics.insert(Topic::Thread { station: station.clone(), thread: *thread });
                topics.insert(Topic::ChatRows { station: station.clone() });
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
    /// The chat an agent's item has: the ember chat bound to it (its first session), as the station's items say, or
    /// its threads do.
    fn bound_thread(&self, station: &str, key: &str) -> Option<u64> {
        let from_rows = self.ok(Topic::ChatRows { station: station.to_string() }).and_then(|rows| {
            rows.as_array()?.iter().find(|r| r.get("session").and_then(Value::as_str) == Some(key))?.get("thread")?.as_u64()
        });
        from_rows.or_else(|| {
            self.ok(Topic::Threads { station: station.to_string() })?.as_array()?.iter().find(|t| {
                t.get("surface").and_then(Value::as_str) == Some("ember") && members(t).first().map(String::as_str) == Some(key)
            })?.get("id")?.as_u64()
        })
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

    /// The stations' sidebar rows side by side: each station puts its own together for the viewer (`/chats`);
    /// here they only get their station, the `mine` filter, and days.
    fn chats(&self, scope: &str, mine: bool) -> Option<Result<Value>> {
        let stations = match self.stations(scope)? {
            Ok(stations) => stations,
            Err(error) => return Some(Err(error)),
        };
        let me = self.me(scope);
        // The workspace's people, by email: a row's last speaker is named and pictured as they are here.
        let members: Vec<Value> = if scope == "local" { Vec::new() } else {
            self.ok(Topic::Workspace { workspace: scope.to_string() }).and_then(|w| w.get("members").and_then(Value::as_array).cloned()).unwrap_or_default()
        };
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
                match self.store.value(&Topic::ChatRows { station: s.address.clone() }) {
                    Some(Err(error)) => ("error", json!(error.message)),
                    Some(Ok(list)) => {
                        let slack_users: Vec<String> = self.ok(Topic::Overview { station: s.address.clone() })
                            .and_then(|o| o.get("slackUsers").and_then(Value::as_array).cloned())
                            .unwrap_or_default().iter().filter_map(|u| u.as_str().map(str::to_string)).collect();
                        for row in list.as_array().into_iter().flatten() {
                            if mine && row.get("mine").and_then(Value::as_bool) != Some(true) {
                                continue;
                            }
                            let mut row = row.clone();
                            row["station"] = json!(s.address);
                            row["stationName"] = json!(s.name);
                            // What the clients draw of it, decided here (present.rs).
                            let agents = row.get("agents").and_then(Value::as_array).cloned().unwrap_or_default();
                            row["state"] = json!(crate::present::row_state(&agents));
                            if let Some(by) = crate::present::last_by(&row, &me, &slack_users, &members) {
                                row["last"]["by"] = by;
                            }
                            rows.push(row);
                        }
                        // Rows already read stay in view while the link comes back.
                        match link_state {
                            "error" => ("error", link_message),
                            "offline" => ("connecting", link_message),
                            _ => ("online", Value::Null),
                        }
                    }
                    None => {
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
                "models": models(overview.as_ref()),
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
        // It shows as soon as its latest entries are there (kept on the device, or read); its agents fill in as they are.
        let page = match self.store.value(&Topic::Thread { station: station.to_string(), thread: id })? {
            Ok(page) => page,
            Err(error) => return Some(Err(error)),
        };
        let thread = match self.store.value(&Topic::Threads { station: station.to_string() }) {
            Some(Ok(threads)) => match threads.as_array().into_iter().flatten().find(|t| t.get("id").and_then(Value::as_u64) == Some(id)) {
                Some(thread) => thread.clone(),
                None => return Some(Err(CoreError::new("http_404", "没有这个对话").with_status(404))),
            },
            Some(Err(error)) => return Some(Err(error)),
            // Not read yet: the thread as it was kept with its entries.
            None => page.get("thread").filter(|t| t.is_object())?.clone(),
        };
        let agents: Vec<Value> = members(&thread).iter().filter_map(|key| self.agent(station, key)).collect();
        let mut messages = merge(page.get("entries").and_then(Value::as_array).map(Vec::as_slice).unwrap_or_default());
        // Which are the viewer's (their bubbles), decided here: by account, or as a Slack user they said is them.
        let viewer = self.me(station.split_once('/').map_or(station, |(workspace, _)| workspace));
        let slack_users: Vec<String> = self.ok(Topic::Overview { station: station.to_string() })
            .and_then(|o| o.get("slackUsers").and_then(Value::as_array).cloned())
            .unwrap_or_default().iter().filter_map(|u| u.as_str().map(str::to_string)).collect();
        for m in messages.iter_mut() {
            let person = m.get("authorKind").and_then(Value::as_str) == Some("person");
            let author = m.get("author").and_then(Value::as_str).unwrap_or("").to_string();
            m["mine"] = json!(person && crate::present::is_viewer(&viewer, &author, &slack_users));
        }
        // A sent message leaves the outbox as its own entry (or anything later) arrives.
        let newest = page.get("last").and_then(Value::as_u64);
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
            // The same title the sidebar shows: the station's for its item, while it has one (as kept, until read).
            "title": self.store.value(&Topic::ChatRows { station: station.to_string() }).and_then(Result::ok)
                .and_then(|rows| rows.as_array()?.iter().find(|r| r.get("thread").and_then(Value::as_u64) == Some(id))?.get("title").cloned())
                .or_else(|| page.get("title").filter(|t| t.is_string()).cloned())
                .unwrap_or_else(|| json!(chat_title(&thread))),
            "people": thread.get("people").cloned().unwrap_or_else(|| json!([])),
            "agents": agents,
            "messages": messages,
            // Entries before those loaded (the thread counts from 1).
            "more": page.get("first").and_then(Value::as_u64).is_some_and(|first| first > 1),
            "outbox": outbox,
            "link": self.link(station, true),
            "thread": thread,
        })))
    }
}

impl Views {
    /// An agent of a chat: its session, the connect that started it, its profile, turns and threads. Until its detail
    /// is read it is its summary from the station's list (no turns, no threads yet); one that cannot be read at all
    /// (removed meanwhile) is `None`.
    fn agent(&self, station: &str, key: &str) -> Option<Value> {
        let detail = match self.store.value(&Topic::Session { station: station.to_string(), key: key.to_string() }) {
            Some(Ok(detail)) => detail,
            Some(Err(_)) => return None,
            None => match self.ok(Topic::Sessions { station: station.to_string() }) {
                Some(summaries) => json!({ "session": summaries.as_array()?.iter().find(|s| s.get("key").and_then(Value::as_str) == Some(key))? }),
                // The station's list not read yet: the agent as the sidebar's rows have it (kept on the device), so a
                // chat opened from them shows who its agents are at once.
                None => json!({ "session": self.row_agent(station, key)? }),
            },
        };
        let overview = self.ok(Topic::Overview { station: station.to_string() });
        let of = |list: &str, id: Option<&Value>| find(overview.as_ref().and_then(|o| o.get(list)), id);
        let session = detail.get("session").cloned().unwrap_or(Value::Null);
        Some(json!({
            // Where it stands, and its mark: decided here for every client (present.rs).
            "status": crate::present::session_status(&session),
            "badge": crate::present::badge(crate::present::session_status(&session)),
            "session": session,
            "connect": of("connects", session.get("connect")),
            "profile": of("profiles", session.get("profile")),
            "turns": detail.get("turns").cloned().unwrap_or_else(|| json!([])),
            "threads": detail.get("threads").cloned().unwrap_or_else(|| json!([])),
        }))
    }

    /// An agent as a sidebar row lists it (key, runtime, model, effort, process, pending, lastTurn), with the connect
    /// its row came from: a session's summary in short.
    fn row_agent(&self, station: &str, key: &str) -> Option<Value> {
        let rows = self.ok(Topic::ChatRows { station: station.to_string() })?;
        rows.as_array()?.iter().find_map(|row| {
            let mut agent = row.get("agents")?.as_array()?.iter().find(|a| a.get("key").and_then(Value::as_str) == Some(key))?.clone();
            if row.get("session").and_then(Value::as_str) == Some(key)
                && let (Some(connect), Some(obj)) = (row.get("connect").filter(|c| c.is_string()), agent.as_object_mut())
            {
                obj.insert("connect".into(), connect.clone());
            }
            Some(agent)
        })
    }

    /// The page of an item whose agent has no chat yet: the agent alone, no messages, titled as the station's item
    /// is. Its chat is made with the first message (`POST /threads {session}`).
    fn unchatted(&self, station: &str, key: &str) -> Option<Result<Value>> {
        let agent = match self.agent(station, key) {
            Some(agent) => agent,
            // Not read yet, or gone.
            None => {
                let detail = self.store.value(&Topic::Session { station: station.to_string(), key: key.to_string() })?;
                return Some(Err(detail.err().unwrap_or_else(|| CoreError::new("http_404", "没有这个 agent").with_status(404))));
            }
        };
        // Its title is the station's: the page waits for its items.
        let rows = self.store.value(&Topic::ChatRows { station: station.to_string() })?.ok();
        let row = rows.as_ref().and_then(Value::as_array).and_then(|rows| rows.iter().find(|r| r.get("id").and_then(Value::as_str) == Some(key)));
        let title = row.and_then(|r| r.get("title").cloned()).unwrap_or_else(|| json!("（还没有消息）"));
        let scope = station.split_once('/').map_or(station, |(workspace, _)| workspace);
        Some(Ok(json!({
            "me": self.me(scope),
            "thread": null,
            "title": title,
            "people": [],
            "agents": [agent],
            "messages": [],
            "more": false,
            "outbox": [],
            "link": self.link(station, true),
        })))
    }
}


/// The session keys taking part in a thread.
fn members(thread: &Value) -> Vec<String> {
    thread.get("sessions").and_then(Value::as_array).into_iter().flatten().filter_map(|m| Some(m.get("session")?.as_str()?.to_string())).collect()
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

/// Whether the viewer added something: its creator's id, or email in any case, is theirs (useIsMine in web/src/api.ts).
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
            // An account run on several runtimes offers its models on each.
            .filter(|p| p.get("runtimes").and_then(Value::as_array).is_some_and(|r| r.iter().any(|r| r.as_str() == Some(runtime))))
            .flat_map(|p| p.get("models").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str))
            .collect();
        (!models.is_empty()).then(|| json!({ "runtime": runtime, "models": models }))
    });
    Value::Array(list.collect())
}

/// The models the station can run, each with the runtimes it runs on (those of the profiles that have it enabled):
/// a model is chosen first, and a runtime only when it has more than one.
fn models(overview: Option<&Value>) -> Value {
    let mut on: BTreeMap<&str, BTreeSet<&str>> = BTreeMap::new();
    for p in overview.and_then(|o| o.get("profiles")).and_then(Value::as_array).into_iter().flatten() {
        let runtimes: Vec<&str> = p.get("runtimes").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str).collect();
        for model in p.get("models").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str) {
            on.entry(model).or_default().extend(runtimes.iter().copied());
        }
    }
    // Claude Code first where both run it: it is the one most chats use.
    let order = |r: &&str| RUNTIMES.iter().position(|x| x == r).unwrap_or(usize::MAX);
    Value::Array(on.into_iter().map(|(model, runtimes)| {
        let mut runtimes: Vec<&str> = runtimes.into_iter().collect();
        runtimes.sort_by_key(order);
        json!({ "model": model, "runtimes": runtimes })
    }).collect())
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
    fn rows(st: &str) -> Topic {
        Topic::ChatRows { station: st.into() }
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
            "last": id * 10,
            "lastMessage": {"seq": id * 10, "authorKind": "agent", "author": keys.first().copied().unwrap_or(""), "authorName": null, "text": "好的", "createdAt": at},
            "read": 0, "unread": 0, "people": [], "firstText": null,
        })
    }

    /// A station's sidebar item, as `/chats` has it, last active at `at`: with a chat when `id` is its thread's.
    fn row(id: &str, at: f64) -> Value {
        let thread = id.parse::<u64>().ok();
        json!({
            "id": id, "session": if thread.is_some() { "s" } else { id }, "thread": thread,
            "title": format!("{id} 的标题"), "agents": [session(id)], "last": null, "unread": false, "mine": false,
            "lastActiveAt": at, "connect": null, "origin": null,
        })
    }

    fn ids(v: &Value) -> Vec<String> {
        v["days"].as_array().unwrap().iter().flat_map(|d| d["items"].as_array().unwrap().iter().map(|i| i["id"].as_str().unwrap().to_string())).collect()
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

            t.set(workspace(), stations(t.now_s(), true, true));
            t.read(&mut ui, 1).await;
            assert_eq!(sorted(t.started()), sorted(vec![rows("ws/a"), link("ws/a"), overview("ws/a"), rows("ws/b"), link("ws/b"), overview("ws/b")]), "each station's rows (and its overview, for who the viewer is there), nothing to join them with");
            let v = ui.value.clone().unwrap();
            assert_eq!(v["me"], json!({"id": "Me@x.com", "email": "Me@x.com"}));
            assert_eq!(v["loading"], true);
            assert_eq!(v["stations"], json!([
                {"station": "ws/a", "id": "a", "name": "alpha", "state": "connecting", "message": null},
                {"station": "ws/b", "id": "b", "name": "beta", "state": "connecting", "message": null},
                {"station": "ws/c", "id": "c", "name": "gamma", "state": "offline", "message": null},
            ]));
            assert_eq!(v["days"], json!([]));

            // Both stations' rows, merged newest first; each as the station has it, with its station.
            let now = t.host.now_ms();
            let mut slack = row("s1", now - 2000.0);
            slack["connect"] = json!("c1");
            slack["origin"] = json!({"teamName": "Acme", "channel": "C1", "channelName": "ops", "threadTs": "1.0"});
            t.set(link("ws/a"), json!({"state": "online"}));
            t.set(rows("ws/a"), json!([row("1", now - 1000.0), slack.clone()]));
            t.set(link("ws/b"), json!({"state": "online"}));
            t.set(rows("ws/b"), json!([row("1", now - 1500.0)]));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!(v["loading"], false);
            assert_eq!((v["stations"][0]["state"].as_str(), v["stations"][1]["state"].as_str()), (Some("online"), Some("online")));
            let items = &v["days"][0]["items"];
            assert_eq!(ids(&v), vec!["1", "1", "s1"]);
            assert_eq!((items[0]["station"].as_str(), items[1]["station"].as_str(), items[1]["stationName"].as_str()), (Some("ws/a"), Some("ws/b"), Some("beta")));
            let mut shown = slack;
            shown["station"] = json!("ws/a");
            shown["stationName"] = json!("alpha");
            // What clients draw of it is the core's: its state (none: its agent is idle).
            shown["state"] = Value::Null;
            assert_eq!(items[2], shown);

            // One station failing shows as that station's state; the other's rows stay.
            t.store.set(&rows("ws/a"), Err(CoreError::new("http_500", "坏了")));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!(v["stations"][0], json!({"station": "ws/a", "id": "a", "name": "alpha", "state": "error", "message": "坏了"}));
            assert_eq!(ids(&v), vec!["1"]);
            // The link dropping, with rows read: reconnecting, rows kept.
            t.set(rows("ws/a"), json!([row("1", now - 1000.0)]));
            t.set(link("ws/a"), json!({"state": "offline", "message": "连接断开了"}));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!((v["stations"][0]["state"].as_str(), v["stations"][0]["message"].as_str()), (Some("connecting"), Some("连接断开了")));
            assert_eq!(ids(&v).len(), 2);

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
            assert_eq!(sorted(t.started()), sorted(vec![rows("ws/b"), link("ws/b"), overview("ws/b")]));
            let states: Vec<&str> = ui.value.as_ref().unwrap()["stations"].as_array().unwrap().iter().map(|s| s["state"].as_str().unwrap()).collect();
            assert_eq!(states, vec!["offline", "connecting", "offline"]);
            // `a`'s topics are let go: stopped after the grace, like a UI unsubscribing.
            assert!(t.stopped().is_empty());
            tokio::time::sleep(std::time::Duration::from_millis(EVICT_AFTER_MS * 5 / 4 / SPEEDUP)).await;
            assert_eq!(t.stopped(), sorted(vec![rows("ws/a"), link("ws/a"), overview("ws/a")]));
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
            t.set(rows("local"), json!([
                row("1", midnight - 1000.0),
                row("2", midnight - 2.0 * DAY_MS - 1000.0),
                row("3", today),
                row("4", midnight - DAY_MS + 1000.0),
                row("a", midnight - 3.0 * DAY_MS - 1000.0),
            ]));
            t.read(&mut ui, 1).await;
            let v = ui.value.unwrap();
            let days: Vec<(i64, Vec<String>)> = v["days"]
                .as_array()
                .unwrap()
                .iter()
                .map(|d| (d["daysAgo"].as_i64().unwrap(), d["items"].as_array().unwrap().iter().map(|i| i["id"].as_str().unwrap().to_string()).collect()))
                .collect();
            let day = |ago: i64, ids: &[&str]| (ago, ids.iter().map(|s| s.to_string()).collect::<Vec<_>>());
            assert_eq!(days, vec![day(0, &["3"]), day(1, &["1", "4"]), day(3, &["2"]), day(4, &["a"])]);
            assert_eq!(v["days"][1]["at"], json!(midnight - 1000.0));
            assert_eq!(v["me"], json!({"id": "local", "email": null}));
            assert_eq!(v["stations"], json!([{"station": "local", "id": "local", "name": "", "state": "online", "message": null}]));
        });
    }

    #[test]
    fn mine_keeps_the_rows_the_station_says_are_the_viewers() {
        run(async {
            let t = setup();
            let mut all = Ui::default();
            let mut mine = Ui::default();
            t.subscribe(1, Topic::Chats { scope: "ws".into(), mine: false });
            t.set(workspace(), stations(t.now_s(), true, true));
            t.read(&mut all, 1).await;
            let now = t.host.now_ms();
            let with = |id: &str, at: f64, is_mine: bool| {
                let mut r = row(id, at);
                r["mine"] = json!(is_mine);
                r
            };
            t.set(rows("ws/a"), json!([with("1", now - 1.0, true), with("k", now - 2.0, false)]));
            t.set(rows("ws/b"), json!([with("1", now - 3.0, false), with("j", now - 4.0, true)]));
            t.read(&mut all, 1).await;
            t.subscribe(2, Topic::Chats { scope: "ws".into(), mine: true });
            t.read(&mut mine, 2).await;
            assert_eq!(ids(all.value.as_ref().unwrap()), vec!["1", "k", "1", "j"]);
            let mine = mine.value.unwrap();
            assert_eq!(ids(&mine), vec!["1", "j"]);
            assert_eq!(mine["days"][0]["items"][1]["station"], "ws/b");
        });
    }

    #[test]
    fn a_chats_unread_is_a_mark_and_its_title_comes_from_what_was_said() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Chats { scope: "local".into(), mine: false });
            let now = t.host.now_ms();
            // The station says what a row is called and whether it is unread; the view shows it as it is.
            let mut named = row("1", now - 1.0);
            named["title"] = json!("排查");
            named["unread"] = json!(true);
            named["last"] = json!({"seq": 7, "authorKind": "agent", "author": "a", "authorName": null, "text": "好的", "createdAt": now - 1.0});
            let mut said = row("2", now - 2.0);
            said["title"] = json!("看看 这个");
            t.set(rows("local"), json!([named, said]));
            t.read(&mut ui, 1).await;
            let rows_of = |ui: &Ui| -> Vec<(String, String, bool)> {
                ui.value.as_ref().unwrap()["days"][0]["items"].as_array().unwrap().iter()
                    .map(|i| (i["id"].as_str().unwrap().to_string(), i["title"].as_str().unwrap().to_string(), i["unread"].as_bool().unwrap()))
                    .collect()
            };
            assert_eq!(rows_of(&ui), vec![("1".into(), "排查".into(), true), ("2".into(), "看看 这个".into(), false)]);
            // Read: the mark follows the station's rows.
            t.store.update(&rows("local"), &mut |list| list[0]["unread"] = json!(false));
            t.read(&mut ui, 1).await;
            assert_eq!(rows_of(&ui)[0].2, false);
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
                t.set(rows(st), json!([row("1", t.host.now_ms())]));
            }
            t.store.update(&rows("ws/a"), &mut |v| v[0]["title"] = json!("改了"));
            t.read(&mut ui, 1).await;
            assert_eq!(t.router.computed.get(), computed + 1);
            assert_eq!(ui.messages, messages + 1);
            assert_eq!(ui.value.as_ref().unwrap()["days"][0]["items"].as_array().unwrap().len(), 2);
            // Recomputed to the same value: nothing goes out.
            t.set(link("ws/a"), json!({"state": "online"}));
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
                {"id": "p1", "runtimes": ["codex"], "models": ["o3", "gpt-5"]},
                {"id": "p2", "runtimes": ["claude"], "models": []},
                {"id": "p3", "runtimes": ["claude"], "models": ["sonnet"]},
                {"id": "p4", "runtimes": ["claude"], "models": ["opus", "sonnet"]},
                {"id": "p5", "runtimes": ["claude", "codex"], "models": ["deepseek-flash"]},
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
            assert_eq!(v[0]["runtimes"], json!([{"runtime": "claude", "models": ["deepseek-flash", "opus", "sonnet"]}, {"runtime": "codex", "models": ["deepseek-flash", "gpt-5", "o3"]}]));
            // An account run on both offers its model on both: a runtime is chosen for it.
            assert_eq!(v[0]["models"], json!([{"model": "deepseek-flash", "runtimes": ["claude", "codex"]}, {"model": "gpt-5", "runtimes": ["codex"]}, {"model": "o3", "runtimes": ["codex"]}, {"model": "opus", "runtimes": ["claude"]}, {"model": "sonnet", "runtimes": ["claude"]}]));
            assert_eq!(
                v[1],
                json!({"station": "ws/b", "id": "b", "name": "beta", "online": false, "lastSeen": v[1]["lastSeen"], "version": null,
                    "link": {"state": "offline", "message": null}, "overview": null, "host": null, "runtimes": [], "models": []})
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

    fn session_of(st: &str, key: &str) -> Topic {
        Topic::Session { station: st.into(), key: key.into() }
    }
    fn page_of(st: &str, id: u64) -> Topic {
        Topic::Thread { station: st.into(), thread: id }
    }
    fn entry(n: u64, text: &str) -> Value {
        json!({"thread": 7, "n": n, "kind": "message", "ts": format!("{n}.0"), "authorKind": "person", "author": "a@x.com", "authorName": null, "text": text, "at": n})
    }
    /// A thread topic's value: entries `first ..= last` (their texts), and the summary kept with them.
    fn page(first: u64, texts: &[&str], kept: Value) -> Value {
        let entries: Vec<Value> = texts.iter().enumerate().map(|(i, t)| entry(first + i as u64, t)).collect();
        json!({"first": first, "last": first + texts.len() as u64 - 1, "entries": entries, "thread": kept})
    }

    fn chat_topic(station: &str, thread: u64) -> Topic {
        Topic::Chat { station: station.to_string(), thread: Some(thread), session: None }
    }

    fn agent_page(station: &str, key: &str) -> Topic {
        Topic::Chat { station: station.into(), thread: None, session: Some(key.into()) }
    }

    #[test]
    fn an_items_page_is_its_agents_and_becomes_its_chat() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, agent_page("ws/a", "k"));
            t.read(&mut ui, 1).await;
            let now = t.host.now_ms();
            t.set(sessions("ws/a"), json!([{"key": "k", "connect": "ember", "profile": "p1"}]));
            t.set(rows("ws/a"), json!([{"id": "k", "session": "k", "thread": null, "title": "修构建", "agents": []}]));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().expect("the agent alone");
            assert_eq!((v["thread"].clone(), v["messages"].clone(), v["title"].clone()), (Value::Null, json!([]), json!("修构建")));
            // A chat is made for it (here or elsewhere): the same page is the chat now, at the same address.
            t.set(rows("ws/a"), json!([{"id": "k", "session": "k", "thread": 7, "title": "修构建", "agents": []}]));
            t.read(&mut ui, 1).await;
            // Now it reads that chat, as any chat's page does.
            assert!(t.started().contains(&page_of("ws/a", 7)), "{:?}", t.started());
            t.set(threads("ws/a"), json!([thread(7, &["k"], now)]));
            t.set(page_of("ws/a", 7), page(1, &["开始吧"], Value::Null));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!(v["thread"]["id"], 7);
            assert_eq!(v["messages"].as_array().unwrap().len(), 1);
        });
    }

    #[test]
    fn chat_is_a_thread_its_messages_and_its_agents() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, chat_topic("ws/a", 7));
            t.read(&mut ui, 1).await;
            // Its thread and its messages are asked for at once.
            assert_eq!(sorted(t.started()), sorted(vec![threads("ws/a"), sessions("ws/a"), page_of("ws/a", 7), rows("ws/a"), overview("ws/a"), link("ws/a")]));
            assert!(ui.value.is_none(), "nothing before the thread is read");

            let now = t.host.now_ms();
            let mut chat = thread(7, &["k", "j"], now);
            chat["title"] = json!("排查");
            chat["people"] = json!([{"id": "local", "name": "本机管理页", "email": null, "via": "local"}]);
            // What is kept on the device shows before the station's threads are read.
            let mut kept = chat.clone();
            kept["title"] = json!("排查（上次）");
            t.set(page_of("ws/a", 7), page(39, &["第 39 条", "第 40 条"], kept));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().expect("shown from what is kept");
            assert_eq!((v["title"].clone(), v["messages"].as_array().unwrap().len(), v["more"].clone()), (json!("排查（上次）"), 2, json!(true)));
            assert_eq!(sorted(t.started()), sorted(vec![session_of("ws/a", "k"), session_of("ws/a", "j")]), "its agents are read as the kept thread names them");
            t.set(threads("ws/a"), json!([thread(3, &["k"], now), chat.clone()]));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.clone().unwrap()["title"], "排查", "the station's threads, once read");
            let texts: Vec<String> = (11..=40).map(|i| format!("第 {i} 条")).collect();
            t.set(page_of("ws/a", 7), page(11, &texts.iter().map(String::as_str).collect::<Vec<_>>(), Value::Null));
            t.read(&mut ui, 1).await;
            // The messages do not wait for the agents: those not read yet are their summaries where the list has them.
            let v = ui.value.clone().unwrap();
            assert_eq!(v["agents"], json!([]));
            t.set(sessions("ws/a"), json!([{"key": "j", "connect": "ember", "profile": "p1"}]));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.clone().unwrap()["agents"], json!([{"status": "idle", "badge": null, "session": {"key": "j", "connect": "ember", "profile": "p1"}, "connect": null, "profile": null, "turns": [], "threads": []}]));

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
            t.store.update(&page_of("ws/a", 7), &mut |p| {
                p["entries"].as_array_mut().unwrap().push(entry(41, "新的"));
                p["last"] = json!(41);
            });
            t.host.settle().await;
            let sent = t.host.take_emitted();
            assert_eq!(sent.len(), 1);
            let CoreMessage::Delta { delta, .. } = &sent[0].1 else { panic!("{:?}", sent[0]) };
            // Appended as merged, with whose it is (the core decides: not the viewer's here).
            let mut appended = merge(&[entry(41, "新的")]);
            appended[0]["mine"] = json!(false);
            assert_eq!(serde_json::to_value(delta).unwrap(), json!([{"path": ["messages"], "append": appended}]));
            delta::apply(ui.value.as_mut().unwrap(), delta);
            // An edit shows in its message: merged here, not by the page.
            t.store.update(&page_of("ws/a", 7), &mut |p| {
                p["entries"].as_array_mut().unwrap().push(json!({"n": 42, "kind": "edit", "target": 41, "text": "新的（改）", "attachments": [], "quotes": [], "at": 42}));
                p["last"] = json!(42);
            });
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            let last: Vec<(Value, Value)> = v["messages"].as_array().unwrap().iter().rev().take(2).map(|m| (m["text"].clone(), m["editedAt"].clone())).collect();
            assert_eq!(last, vec![(json!("新的（改）"), json!(42)), (json!("第 40 条"), Value::Null)]);
            // An older page, in front.
            t.store.update(&page_of("ws/a", 7), &mut |p| {
                p["entries"].as_array_mut().unwrap().splice(0..0, (1..=10).map(|n| entry(n, "旧的")));
                p["first"] = json!(1);
            });
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!((v["messages"][0]["seq"].clone(), v["messages"].as_array().unwrap().len(), v["more"].clone()), (json!(1), 41, json!(false)));

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
            t.set(page_of("local", 3), page(1, &["<@U0BOT> 部署挂了", "在看"], Value::Null));
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
    fn an_agent_without_a_chat_is_its_page_with_no_messages() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Chat { station: "ws/a".into(), thread: None, session: Some("k".into()) });
            t.read(&mut ui, 1).await;
            assert_eq!(sorted(t.started()), sorted(vec![session_of("ws/a", "k"), rows("ws/a"), sessions("ws/a"), overview("ws/a"), link("ws/a")]));
            t.set(session_of("ws/a", "k"), json!({"session": {"key": "k", "connect": "c1", "profile": "p1"}, "threads": [{"id": 3, "surface": "slack:T1"}], "turns": [{"id": "t1"}]}));
            t.read(&mut ui, 1).await;
            assert!(ui.value.is_none(), "its title is the station's: it waits for the items");
            let mut item = row("k", t.host.now_ms());
            item["title"] = json!("部署挂了");
            t.set(rows("ws/a"), json!([row("7", t.host.now_ms()), item]));
            t.set(overview("ws/a"), json!({"connects": [{"id": "c1", "name": "Slack"}], "profiles": []}));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!((v["thread"].clone(), v["title"].clone(), v["messages"].clone(), v["outbox"].clone(), v["more"].clone()), (Value::Null, json!("部署挂了"), json!([]), json!([]), json!(false)));
            assert_eq!(v["agents"], json!([{"status": "idle", "badge": null, "session": {"key": "k", "connect": "c1", "profile": "p1"}, "connect": {"id": "c1", "name": "Slack"}, "profile": null,
                "turns": [{"id": "t1"}], "threads": [{"id": 3, "surface": "slack:T1"}]}]));
            assert_eq!(v["me"], json!({"id": "Me@x.com", "email": "Me@x.com"}));
            // Deleted: the page says so.
            t.store.set(&session_of("ws/a", "k"), Err(CoreError::new("http_404", "这个会话已经删除了").with_status(404)));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.error.as_ref().unwrap().status, Some(404));
        });
    }

    #[test]
    fn a_sent_message_shows_until_the_chat_has_it() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, chat_topic("ws/a", 7));
            t.set(threads("ws/a"), json!([thread(7, &[], t.host.now_ms())]));
            t.set(page_of("ws/a", 7), page(5, &["早"], Value::Null));
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

            // Sent as entry 6: it stays until the entries reach 6, and leaves in that same emission.
            views.outbox_state("ws/a", 7, &id, None);
            views.outbox_sent("ws/a", 7, &id, 6);
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.clone().unwrap()["outbox"][0]["seq"], 6);
            t.store.update(&page_of("ws/a", 7), &mut |p| {
                p["entries"].as_array_mut().unwrap().push(entry(6, "你好"));
                p["last"] = json!(6);
            });
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
