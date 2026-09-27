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
//! Times in words (a day's heading, "3 分钟前") go out fresh each minute: the store's clock invalidates what is
//! shown (store.rs, `tick`).

use std::cell::{Cell, RefCell};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::rc::{Rc, Weak};

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
    /// Per live view, the topics it watches.
    views: RefCell<HashMap<Topic, HashMap<Topic, Watch>>>,
    /// Messages sent from here that the chat does not show yet, per (station, thread), oldest first.
    outbox: RefCell<HashMap<(String, u64), Vec<Value>>>,
    sent: Cell<u64>,
}

/// A station of a scope, as the workspace lists it.
/// Whether a station is taken for down: its link found it so, or — not found out yet this time — it was, last.
fn down(link: &Value) -> bool {
    match link.get("state").and_then(Value::as_str) {
        Some("offline") => true,
        Some("connecting") => link.get("last").and_then(Value::as_str) == Some("offline"),
        _ => false,
    }
}

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
        Rc::new(Views {
            host,
            store,
            email_of,
            views: RefCell::default(),
            outbox: RefCell::default(),
            sent: Cell::new(0),
        })
    }

    /// A message on its way to a chat: shown in it at once, as `sending`. Answers its id. `after` is the chat's newest
    /// entry then: the message itself comes later than that.
    pub fn outbox_add(&self, station: &str, thread: u64, message: Value) -> String {
        self.sent.set(self.sent.get() + 1);
        let id = format!("out-{}", self.sent.get());
        let after = self.ok(Topic::Thread { station: station.to_string(), thread }).and_then(|p| p.get("last").and_then(Value::as_u64)).unwrap_or(0);
        let mut entry = message;
        entry["id"] = json!(id);
        entry["after"] = json!(after);
        entry["createdAt"] = json!(self.host.now_ms().round() as i64);
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
    }

    fn clock(&self) -> crate::present::Clock {
        let now = self.host.now_ms();
        crate::present::Clock { now, offset_min: self.host.utc_offset_min(now) }
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
            Topic::History { station, key } => self.history(station, key),
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
            // Its sessions (the recent ones, the one it delivers into) and the chats they were last talked to in.
            Topic::Connects { scope, .. } => (scope.as_str(), |station| vec![Topic::Overview { station: station.clone() }, Topic::Sessions { station: station.clone() }, Topic::Threads { station }]),
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
                // Whether it is online (offline, nothing can be sent).
                if let Some((scope, _)) = station.split_once('/') {
                    topics.insert(Topic::Workspace { workspace: scope.to_string() });
                }
                return topics;
            }
            Topic::History { station, key } => {
                topics.insert(Topic::Live { station: station.clone(), key: key.clone() });
                topics.insert(Topic::Session { station: station.clone(), key: key.clone() });
                topics.insert(Topic::Overview { station: station.clone() });
                if let Some((scope, _)) = station.split_once('/') {
                    topics.insert(Topic::Workspace { workspace: scope.to_string() });
                }
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
                if let Some((scope, _)) = station.split_once('/') {
                    topics.insert(Topic::Workspace { workspace: scope.to_string() });
                }
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
            let address = format!("{scope}/{id}");
            // Up as this device finds it, reaching it over the mesh: not as anyone else says.
            let online = !down(&self.link(&address));
            Some(StationInfo {
                address,
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

    /// The station's link as `{ state, message, last }`: connecting (`last`: how it was last, kept), online,
    /// reconnecting (it was up and dropped), offline (not reached), error (it answers, but no).
    fn link(&self, station: &str) -> Value {
        match self.store.value(&Topic::Link { station: station.to_string() }) {
            Some(Ok(link)) => json!({
                "state": link.get("state").cloned().unwrap_or(json!("connecting")),
                "message": link.get("message").cloned().unwrap_or(Value::Null),
                "last": link.get("last").cloned().unwrap_or(Value::Null),
            }),
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
        let mut troubles: Vec<(&str, String)> = Vec::new();
        let mut rows = Vec::new();
        let mut loading = false;
        for s in &stations {
            // What was read from it shows whatever its state: an offline station's chats are still there to read (the
            // data center kept them), only not to write to.
            let read = self.store.value(&Topic::ChatRows { station: s.address.clone() });
            if let Some(Ok(list)) = &read {
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
                    // Its station offline: the row says so itself (greyed, marked), not the list above it; its link
                    // coming back (or failing and retried), the same, marked with a turning ring.
                    if !s.online {
                        row["offline"] = json!(format!("{} 离线", s.name));
                    } else {
                        match self.link(&s.address)["state"].as_str().unwrap_or("connecting") {
                            "error" => row["reconnecting"] = json!(format!("连不上 {}，正在重试", s.name)),
                            "reconnecting" => row["reconnecting"] = json!(format!("正在重连 {}…", s.name)),
                            _ => {}
                        }
                    }
                    // What the clients draw of it, decided here (present.rs).
                    let agents = row.get("agents").and_then(Value::as_array).cloned().unwrap_or_default();
                    row["state"] = json!(crate::present::row_state(&agents));
                    for agent in row.get_mut("agents").and_then(Value::as_array_mut).into_iter().flatten() {
                        crate::present::session(agent);
                    }
                    // Where it came from, for its mark's tip: the Slack workspace, then the thread's channel.
                    if row.get("connect").is_some_and(|c| !c.is_null()) {
                        let o = row.get("origin").cloned().unwrap_or(Value::Null);
                        let text = |k: &str| o.get(k).and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string);
                        let place = text("channelName").map(|n| format!("#{n}"))
                            .or_else(|| text("channel").filter(|c| c.starts_with('D')).map(|_| "私信".to_string()));
                        row["originText"] = json!(["Slack".to_string()].into_iter().chain(text("teamName")).chain(place).collect::<Vec<_>>().join(" · "));
                    }
                    // Its line: what was said last, without mentions (a file alone says so).
                    if let Some(last) = row.get_mut("last").filter(|l| l.is_object()) {
                        let text = crate::format::clean_text(last.get("text").and_then(Value::as_str).unwrap_or(""));
                        last["preview"] = json!(if text.is_empty() { "（文件）".to_string() } else { text });
                    }
                    if let Some(by) = crate::present::last_by(&row, &me, &slack_users, &members) {
                        row["last"]["by"] = by;
                        // What its picture says when pointed at: who, and an agent's state.
                        let name = row["last"]["by"]["name"].as_str().unwrap_or("").to_string();
                        row["last"]["by"]["label"] = json!(match row["last"]["by"]["state"].as_str() {
                            Some(state) => format!("{name}（{}）", crate::present::badge_text(state)),
                            None => name,
                        });
                        let model = row["last"]["by"]["model"].as_str().map(str::to_string);
                        row["last"]["by"]["maker"] = crate::present::maker(model.as_deref());
                    }
                    rows.push(row);
                }
            }
            let (state, message) = if !s.online {
                ("offline", Value::Null)
            } else {
                let link = self.link(&s.address);
                let link_state = link["state"].as_str().unwrap_or("connecting");
                let link_message = link["message"].clone();
                match &read {
                    Some(Err(error)) => ("error", json!(error.message)),
                    // Rows already read stay in view while the link comes back.
                    Some(Ok(_)) => match link_state {
                        "error" => ("error", link_message),
                        "reconnecting" => ("connecting", link_message),
                        _ => ("online", Value::Null),
                    },
                    None => {
                        loading = true;
                        if link_state == "error" { ("error", link_message) } else { ("connecting", Value::Null) }
                    }
                }
            };
            // What is wrong with it, if anything: offline, failing, or its link coming back (with what was read of it
            // there to show; a station first connecting is only loading).
            let wrong = match state {
                "offline" => Some(("offline", format!("{} 离线", s.name))),
                "error" => Some(("error", format!("连不上 {}", s.name))),
                "connecting" if matches!(read, Some(Ok(_))) => Some(("reconnecting", format!("正在重连 {}", s.name))),
                _ => None,
            };
            if let Some(w) = wrong {
                troubles.push(w);
            }
            states.push(json!({ "station": s.address, "id": s.id, "name": s.name, "state": state, "message": message }));
        }
        let days = self.days(rows);
        // One says itself; several are counted, marked by the worst.
        let trouble = match troubles.as_slice() {
            [] => Value::Null,
            [(state, text)] => json!({ "text": text, "state": state }),
            all => {
                let worst = ["error", "offline", "reconnecting"].into_iter().find(|w| all.iter().any(|(s, _)| s == w)).unwrap_or("offline");
                json!({ "text": format!("{} 台 station 异常", all.len()), "state": worst })
            }
        };
        Some(Ok(json!({ "me": me, "stations": states, "loading": loading, "days": days, "trouble": trouble })))
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
        let (now, offset) = (self.host.now_ms(), self.host.utc_offset_min(self.host.now_ms()));
        days.into_iter()
            .map(|(d, t, items)| json!({ "daysAgo": today - d, "at": t, "label": crate::format::day_label(t, now, offset), "items": items }))
            .collect()
    }

    fn stations_view(&self, scope: &str) -> Option<Result<Value>> {
        let stations = match self.stations(scope)? {
            Ok(stations) => stations,
            Err(error) => return Some(Err(error)),
        };
        let items = stations.iter().map(|s| {
            // Offline, what was kept of it still shows (the data center holds its overview).
            let read = |topic: Topic| self.ok(topic);
            let overview = read(Topic::Overview { station: s.address.clone() });
            let host = read(Topic::Host { station: s.address.clone() }).map(|mut h| {
                crate::present::host(&mut h);
                h
            });
            let mut shown = overview.clone();
            if let Some(o) = shown.as_mut() {
                crate::present::decorate(&Topic::Overview { station: s.address.clone() }, o, self.clock());
            }
            // Its line in a list: offline since when, or what it is and whether its agents are at work.
            let c = self.clock();
            let summary = if !s.online {
                match s.last_seen.as_f64() {
                    Some(seen) => format!("离线 · {}", crate::format::relative_time(seen * 1000.0, c.now, c.offset_min)),
                    None => "离线".to_string(),
                }
            } else if let Some(h) = &host {
                let running = overview.as_ref().and_then(|o| o.get("counts")).and_then(|c| c.get("running")).and_then(Value::as_u64).unwrap_or(0);
                let what = h.get("cpuModel").and_then(Value::as_str).filter(|m| !m.is_empty()).or_else(|| h.get("os").and_then(Value::as_str)).unwrap_or("");
                format!("{what} · {}", if running > 0 { format!("{running} 个 agent 在跑") } else { "空闲".to_string() })
            } else {
                "正在连接…".to_string()
            };
            json!({
                "station": s.address, "id": s.id, "name": s.name, "summary": summary,
                "online": s.online, "lastSeen": s.last_seen, "version": s.version,
                "link": self.link(&s.address),
                "runtimes": runtimes(overview.as_ref()),
                "models": models(overview.as_ref(), self.host.now_ms()),
                "overview": shown, "host": host,
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
        let members: Vec<Value> = if scope == "local" { Vec::new() } else {
            self.ok(Topic::Workspace { workspace: scope.to_string() }).and_then(|w| w.get("members").and_then(Value::as_array).cloned()).unwrap_or_default()
        };
        let mut items = Vec::new();
        let mut loading = false;
        for s in stations.iter().filter(|s| s.online) {
            match self.store.value(&Topic::Overview { station: s.address.clone() }) {
                None => loading = true,
                Some(Err(_)) => {}
                Some(Ok(overview)) => {
                    let sessions: Vec<Value> = self.ok(Topic::Sessions { station: s.address.clone() }).and_then(|v| v.as_array().cloned()).unwrap_or_default();
                    let threads: Vec<Value> = self.ok(Topic::Threads { station: s.address.clone() }).and_then(|v| v.as_array().cloned()).unwrap_or_default();
                    let connects = overview.get("connects").and_then(Value::as_array).cloned().unwrap_or_default();
                    for connect in &connects {
                        // Who added it is an email, or "local" (as the web's Connects page read it).
                        let creator = connect.get("createdBy").and_then(|c| c.get("id")).map(|id| json!({ "id": id, "email": id }));
                        if mine && !is_mine(&me, creator.as_ref()) {
                            continue;
                        }
                        let mut shown = connect.clone();
                        crate::present::connect(&mut shown);
                        if let Some(owner) = shown.get_mut("createdBy") {
                            crate::present::person(owner, &me, &members);
                        }
                        let mut item = json!({ "station": s.address, "stationName": s.name, "connect": shown });
                        connect_sessions(&mut item, connect, &connects, &sessions, &threads, self.clock());
                        items.push(item);
                    }
                }
            }
        }
        Some(Ok(json!({ "me": me, "items": items, "loading": loading })))
    }

    /// Whether a station is offline, as its workspace says (a station's own page is always online): its chats are read
    /// from what was kept, and nothing can be sent to them.
    fn offline(&self, station: &str) -> bool {
        let Some((scope, _)) = station.split_once('/') else { return false };
        match self.stations(scope) {
            Some(Ok(stations)) => stations.iter().find(|s| s.address == station).is_some_and(|s| !s.online),
            _ => false,
        }
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
        let scope = station.split_once('/').map_or(station, |(workspace, _)| workspace);
        let members: Vec<Value> = if scope == "local" { Vec::new() } else {
            self.ok(Topic::Workspace { workspace: scope.to_string() }).and_then(|w| w.get("members").and_then(Value::as_array).cloned()).unwrap_or_default()
        };
        // Mentions of its agents' bots read as their connects' names.
        let bots: Vec<(String, String)> = agents.iter().filter_map(|a| crate::present::bot_of(a.get("connect")?)).collect();
        // The messages its agents have not taken yet are the last people wrote: they wait.
        let waiting = agents.iter().filter_map(|a| a["session"].get("pending").and_then(Value::as_u64)).max().unwrap_or(0) as usize;
        let people_seqs: Vec<u64> = messages.iter().filter(|m| m.get("authorKind").and_then(Value::as_str) == Some("person"))
            .filter_map(|m| m.get("seq").and_then(Value::as_u64)).collect();
        let waits = &people_seqs[people_seqs.len().saturating_sub(waiting)..];
        // What people wrote, as written (before mentions are named): how a message on its way is known once it is in.
        let written: Vec<(u64, String)> = messages.iter().filter(|m| m.get("authorKind").and_then(Value::as_str) == Some("person"))
            .filter_map(|m| Some((m.get("seq").and_then(Value::as_u64)?, m.get("text").and_then(Value::as_str).unwrap_or("").to_string()))).collect();
        for m in messages.iter_mut() {
            let kind = m.get("authorKind").and_then(Value::as_str).unwrap_or("").to_string();
            let author = m.get("author").and_then(Value::as_str).unwrap_or("").to_string();
            let said_name = m.get("authorName").and_then(Value::as_str).filter(|n| !n.is_empty()).map(str::to_string);
            m["mine"] = json!(kind == "person" && crate::present::is_viewer(&viewer, &author, &slack_users));
            // What ember itself says in a chat (a limit hit, a failure): a notice, not someone's message.
            m["system"] = json!(kind == "ember");
            // Who said it, as its line shows them: an agent by its label and mark, a person by name and picture.
            m["by"] = match kind.as_str() {
                "agent" => {
                    let agent = agents.iter().find(|a| a["session"].get("key").and_then(Value::as_str) == Some(&author));
                    let session = agent.map(|a| &a["session"]);
                    json!({
                        "name": session.and_then(|s| s.get("agentText")).and_then(Value::as_str).map(str::to_string).or(said_name).unwrap_or_else(|| "agent".into()),
                        "agent": agent.map(|_| author.clone()),
                        "maker": session.map(|s| s["maker"].clone()),
                        "runtime": session.and_then(|s| s.get("runtime")).cloned(),
                    })
                }
                "ember" => json!({ "name": "ember" }),
                _ => {
                    let member = members.iter().find(|x| x.get("email").and_then(Value::as_str).is_some_and(|e| e.eq_ignore_ascii_case(&author)));
                    let name = crate::present::member_name(&members, &author).map(str::to_string).or(said_name)
                        .unwrap_or_else(|| if author == "local" { "本机".into() } else { author.clone() });
                    json!({ "name": name, "picture": member.and_then(|x| x.get("picture")).filter(|p| p.as_str().is_some_and(|p| !p.is_empty())) })
                }
            };
            if kind == "person" {
                let text = m.get("text").and_then(Value::as_str).unwrap_or("").to_string();
                m["text"] = json!(crate::present::mentions(&text, &bots, &members));
            }
            m["waiting"] = json!(m.get("seq").and_then(Value::as_u64).is_some_and(|s| waits.contains(&s)));
        }
        // A sent message leaves the outbox as its own entry (or anything later) arrives. Its entry often comes before the
        // station has answered the post with its seq: then it is the viewer's first message since it was sent with the
        // same words, each taken once.
        let newest = page.get("last").and_then(Value::as_u64);
        let mine: Vec<(u64, &str)> = written.iter()
            .filter(|(seq, _)| messages.iter().any(|m| m.get("seq").and_then(Value::as_u64) == Some(*seq) && m["mine"] == true))
            .map(|(seq, text)| (*seq, text.as_str())).collect();
        let at = (station.to_string(), id);
        let outbox = {
            let mut all = self.outbox.borrow_mut();
            let list = all.entry(at.clone()).or_default();
            // Sent in order, they arrive in order: one found as entry S, those sent after it come after S.
            let mut past = 0;
            list.retain_mut(|m| {
                if let Some(seq) = m.get("seq").and_then(Value::as_u64) {
                    past = past.max(seq);
                    return !newest.is_some_and(|n| n >= seq);
                }
                let after = m.get("after").and_then(Value::as_u64).unwrap_or(0).max(past);
                m["after"] = json!(after);
                let text = m.get("text").and_then(Value::as_str).unwrap_or("");
                match mine.iter().find(|(seq, said)| *seq > after && *said == text) {
                    Some((seq, _)) => { past = *seq; false }
                    None => true,
                }
            });
            let shown = list.clone();
            if list.is_empty() {
                all.remove(&at);
            }
            shown
        };
        // Its people, and who started it, named as the workspace knows them.
        let mut people = thread.get("people").cloned().unwrap_or_else(|| json!([]));
        for p in people.as_array_mut().into_iter().flatten() {
            crate::present::person(p, &viewer, &members);
        }
        let mut thread = thread;
        if let Some(creator) = thread.get_mut("creator") {
            crate::present::person(creator, &viewer, &members);
        }
        // Where a Slack chat is, in words, and the way to it in Slack (while its connect is signed in there).
        let str_of = |v: &Value, k: &str| v.get(k).and_then(Value::as_str).unwrap_or("").to_string();
        let slack = str_of(&thread, "surface") != "ember";
        let channel = str_of(&thread, "channel");
        let place = slack.then(|| if channel.starts_with('D') { "私信".to_string() } else {
            format!("#{}", thread.get("channelName").and_then(Value::as_str).filter(|n| !n.is_empty()).unwrap_or(&channel))
        });
        let workspace_url = agents.iter().filter_map(|a| a.get("connect")).filter(|c| str_of(c, "kind") == "slack")
            .find_map(|c| {
                let conn = c.get("connection")?;
                matches!(conn.get("state").and_then(Value::as_str), Some("connected" | "reconnecting")).then(|| conn.get("workspace")?.get("url")?.as_str().map(str::to_string)).flatten()
            });
        let slack_url = workspace_url.filter(|_| slack).map(|url| format!("{url}archives/{channel}/p{}", str_of(&thread, "threadTs").replace('.', "")));
        Some(Ok(json!({
            "me": self.me(scope),
            "place": place,
            "slackUrl": slack_url,
            // The same title the sidebar shows: the station's for its item, while it has one (as kept, until read).
            "title": self.store.value(&Topic::ChatRows { station: station.to_string() }).and_then(Result::ok)
                .and_then(|rows| rows.as_array()?.iter().find(|r| r.get("thread").and_then(Value::as_u64) == Some(id))?.get("title").cloned())
                .or_else(|| page.get("title").filter(|t| t.is_string()).cloned())
                .unwrap_or_else(|| json!(chat_title(&thread))),
            "people": people,
            "agents": agents,
            "messages": messages,
            // Entries before those loaded (the thread counts from 1).
            "more": page.get("first").and_then(Value::as_u64).is_some_and(|first| first > 1),
            "outbox": outbox,
            "link": self.link(station),
            "offline": self.offline(station),
            "thread": thread,
        })))
    }
}

impl Views {
    /// An agent's execution history (history.rs): its transcript read with its threads, its connect's bot, and the
    /// workspace's people. It shows as soon as its transcript does; the rest names things as it arrives.
    fn history(&self, station: &str, key: &str) -> Option<Result<Value>> {
        let live = match self.store.value(&Topic::Live { station: station.to_string(), key: key.to_string() })? {
            Ok(live) => live,
            Err(error) => return Some(Err(error)),
        };
        let detail = self.ok(Topic::Session { station: station.to_string(), key: key.to_string() });
        let session = detail.as_ref().and_then(|d| d.get("session")).cloned().unwrap_or(Value::Null);
        let threads: Vec<Value> = detail.as_ref().and_then(|d| d.get("threads")).and_then(Value::as_array).cloned().unwrap_or_default();
        let overview = self.ok(Topic::Overview { station: station.to_string() });
        let connect = find(overview.as_ref().and_then(|o| o.get("connects")), session.get("connect"));
        let connection = connect.get("connection");
        let signed_in = connection.and_then(|c| c.get("state")).and_then(Value::as_str).is_some_and(|s| s == "connected" || s == "reconnecting");
        let bot_user_id = connection.filter(|_| signed_in).and_then(|c| c.get("botUserId")).and_then(Value::as_str);
        let bot_name = connect.get("name").and_then(Value::as_str).or_else(|| session.get("connect").and_then(Value::as_str)).unwrap_or("");
        let slack_users: Vec<String> = overview.as_ref().and_then(|o| o.get("slackUsers")).and_then(Value::as_array).into_iter().flatten()
            .filter_map(|u| u.as_str().map(str::to_string)).collect();
        let members: Vec<Value> = station.split_once('/').and_then(|(scope, _)| self.ok(Topic::Workspace { workspace: scope.to_string() }))
            .and_then(|w| w.get("members").and_then(Value::as_array).cloned()).unwrap_or_default();
        let now = self.host.now_ms();
        let cx = crate::history::Context {
            threads: &threads,
            members: &members,
            slack_users: &slack_users,
            bot_user_id,
            bot_name,
            runtime: session.get("runtime").and_then(Value::as_str).unwrap_or("claude"),
            started: session.get("runtimeSessionId").is_some_and(|id| id.is_string()),
            offset_min: self.host.utc_offset_min(now),
        };
        Some(Ok(crate::history::present(&live, &cx)))
    }

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
        let mut session = detail.get("session").cloned().unwrap_or(Value::Null);
        crate::present::session(&mut session);
        let mut connect = of("connects", session.get("connect"));
        crate::present::connect(&mut connect);
        let mut profile = of("profiles", session.get("profile"));
        crate::present::profile(&mut profile);
        let runnable = runnable_on(overview.as_ref(), &session, self.host.now_ms());
        let account = runnable.as_array().and_then(|r| r.iter().find(|p| p.get("current") == Some(&Value::Bool(true))).cloned())
            .or_else(|| profile.is_object().then(|| json!({
                "id": profile["id"], "name": profile["name"], "current": true, "kind": profile["access"]["kind"],
                "runtime": profile["runtime"], "quota": profile.get("quota").cloned().unwrap_or(Value::Null),
            })))
            .unwrap_or(Value::Null);
        Some(json!({
            // Where it stands, and its mark: decided here for every client (present.rs).
            "status": crate::present::session_status(&session),
            "badge": crate::present::badge(crate::present::session_status(&session)),
            "session": session,
            "connect": connect,
            "profile": profile,
            // Whom it can be moved to: the profiles that run its runtime (its transcripts are shared by them all).
            "profiles": runnable_on(overview.as_ref(), &session, self.host.now_ms()),
            // What it can be moved to, a model at a time: another model, and then who runs it.
            "choices": choices(overview.as_ref(), &session, self.host.now_ms()),
            // The account it runs on now, as its model control shows it.
            "account": account,
            // What is worth a look about it now (a quota running out, the disk filling up): its history's summary.
            "attention": attention(overview.as_ref(), &session, self.host.now_ms()),
            // When its running turn began (null when none runs): its activity counts from there.
            "since": detail.get("turns").and_then(Value::as_array).and_then(|t| t.last())
                .filter(|t| t.get("endedAt").is_none_or(Value::is_null)).and_then(|t| t.get("startedAt")).cloned().unwrap_or(Value::Null),
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
            "link": self.link(station),
            "offline": self.offline(station),
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

/// A connect's sessions as its page shows them: `sessions`, its latest dozen (each with `chat`, the chat it was last
/// talked in); `bound`, the one a single-session connect delivers into; `candidates`, those of its runtime it could
/// deliver into instead, described; `running`, how many of its own run now.
fn connect_sessions(item: &mut Value, connect: &Value, connects: &[Value], sessions: &[Value], threads: &[Value], clock: crate::present::Clock) {
    let id = connect.get("id").and_then(Value::as_str).unwrap_or("");
    let str_of = |v: &Value, k: &str| v.get(k).and_then(Value::as_str).unwrap_or("").to_string();
    let at = |v: &Value| v.get("lastActiveAt").and_then(Value::as_f64).unwrap_or(0.0);
    let name_of = |c: &str| connects.iter().find(|x| str_of(x, "id") == c).map(|x| str_of(x, "name")).filter(|n| !n.is_empty()).unwrap_or_else(|| c.to_string());
    let shown = |s: &Value| {
        let mut s = s.clone();
        crate::present::session(&mut s);
        let key = str_of(&s, "key");
        s["chat"] = threads.iter()
            .find(|t| t.get("sessions").and_then(Value::as_array).is_some_and(|m| m.iter().any(|m| m.get("session").and_then(Value::as_str) == Some(&key))))
            .and_then(|t| t.get("id").cloned()).unwrap_or(Value::Null);
        s
    };
    let mut by_recent: Vec<&Value> = sessions.iter().collect();
    by_recent.sort_by(|a, b| at(b).total_cmp(&at(a)));
    let bound_to = |s: &Value| s.get("boundTo").and_then(Value::as_array).is_some_and(|b| b.iter().any(|c| c.as_str() == Some(id)));
    let own: Vec<Value> = by_recent.iter().filter(|s| str_of(s, "connect") == id).take(12).map(|s| shown(s)).collect();
    let running = sessions.iter().filter(|s| (str_of(s, "connect") == id || bound_to(s)) && str_of(s, "process") == "running").count();
    let current = connect.get("session").and_then(Value::as_str);
    let runtime = connect.get("bind").and_then(|b| b.get("runtime")).and_then(Value::as_str).unwrap_or("");
    let candidates: Vec<Value> = by_recent.iter().filter(|s| str_of(s, "runtime") == runtime).map(|s| {
        let mut c = shown(s);
        let others: Vec<String> = s.get("boundTo").and_then(Value::as_array).into_iter().flatten()
            .filter_map(Value::as_str).filter(|c| *c != id).map(name_of).collect();
        let mut description = format!(
            "{} · {} · {} 轮 · {}",
            if str_of(s, "scope") == "all" { "单会话" } else { "来自一个 thread" },
            name_of(&str_of(s, "connect")),
            s.get("turns").and_then(Value::as_u64).unwrap_or(0),
            crate::format::relative_time(at(s), clock.now, clock.offset_min),
        );
        if !others.is_empty() {
            description.push_str(&format!(" · 也被 {} 使用", others.join("、")));
        }
        c["description"] = json!(description);
        c["current"] = json!(Some(str_of(s, "key").as_str()) == current);
        c
    }).collect();
    item["sessions"] = json!(own);
    item["bound"] = sessions.iter().find(|s| current.is_some_and(|k| str_of(s, "key") == k)).map(shown).unwrap_or(Value::Null);
    item["candidates"] = json!(candidates);
    item["running"] = json!(running);
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

/// A quota window, or the disk, is worth a look when this little is left (percent).
const LOW_LEFT: f64 = 20.0;
const LOW_DISK: f64 = 10.0;
const LOW_DISK_BYTES: f64 = 10.0 * 1024.0 * 1024.0 * 1024.0;

/// What is worth a look about a session now, most pressing first; empty when nothing is: its account cannot run
/// (signed out, key refused), a window of its account running out (with its ring), the station's disk filling up.
/// Each says so in `text` (shapes: Attention).
fn attention(overview: Option<&Value>, session: &Value, now: f64) -> Value {
    let mut out = Vec::new();
    let profile = find(overview.and_then(|o| o.get("profiles")), session.get("profile"));
    if let Some(p) = Some(&profile).filter(|p| p.is_object()) {
        let check = p.get("check");
        if let Some(state @ ("login" | "failed")) = check.and_then(|c| c.get("state")).and_then(Value::as_str) {
            let name = p.get("name").and_then(Value::as_str).unwrap_or("");
            let text = if state == "login" { format!("「{name}」要重新登录") } else { format!("「{name}」的 key 被拒绝") };
            out.push(json!({ "kind": "account", "text": text }));
        }
        if p.get("quota").and_then(|q| q.get("state")).and_then(Value::as_str) == Some("ok") {
            for w in p.get("quota").and_then(|q| q.get("windows")).and_then(Value::as_array).into_iter().flatten() {
                let left = 100.0 - w.get("usedPercent").and_then(Value::as_f64).unwrap_or(0.0);
                if left <= LOW_LEFT {
                    let label = w.get("label").and_then(Value::as_str).unwrap_or("");
                    let left = left.max(0.0).round() as i64;
                    let until = w.get("resetsAt").and_then(Value::as_i64);
                    out.push(json!({
                        "kind": "quota", "text": format!("{label}剩余 {left}%"),
                        "more": until.map(|at| crate::format::refills_in(at as f64, now)),
                        "quota": { "left": left, "mark": crate::format::window_mark(label).0, "level": if left <= 10 { "red" } else { "amber" }, "until": until },
                    }));
                }
            }
        }
    }
    if let Some(disk) = overview.and_then(|o| o.get("disk")).filter(|d| d.is_object()) {
        let (free, total) = (disk.get("freeBytes").and_then(Value::as_f64).unwrap_or(0.0), disk.get("totalBytes").and_then(Value::as_f64).unwrap_or(0.0));
        if total > 0.0 && (free / total * 100.0 <= LOW_DISK || free <= LOW_DISK_BYTES) {
            out.push(json!({ "kind": "disk", "text": format!("磁盘剩 {}", crate::format::gb(free)) }));
        }
    }
    Value::Array(out)
}

/// The profiles a session can run on, those of its runtime with its model enabled: `{ id, name, current, spent, kind, runtime, quota }`
/// (`spent`: a window of it is used up, and when it is back).
fn runnable_on(overview: Option<&Value>, session: &Value, now: f64) -> Value {
    let runtime = session.get("runtime").and_then(Value::as_str).unwrap_or("");
    let model = session.get("model").and_then(Value::as_str);
    let current = session.get("profile").and_then(Value::as_str);
    profiles_running(overview, runtime, model, current, now)
}

/// The models a session can move to (those a profile of its runtime has enabled), as a model control offers them
/// (shapes: ModelOption): its runtime alone, how hard it can think there, and who runs it (as `runnable_on` has them).
fn choices(overview: Option<&Value>, session: &Value, now: f64) -> Value {
    let runtime = session.get("runtime").and_then(Value::as_str).unwrap_or("");
    let current = session.get("profile").and_then(Value::as_str);
    let models: BTreeSet<&str> = overview.and_then(|o| o.get("profiles")).and_then(Value::as_array).into_iter().flatten()
        .filter(|p| p.get("runtimes").and_then(Value::as_array).is_some_and(|r| r.iter().any(|r| r.as_str() == Some(runtime))))
        .flat_map(|p| p.get("models").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str))
        .collect();
    Value::Array(models.into_iter()
        .map(|model| json!({
            "model": model, "maker": crate::present::maker(Some(model)), "runtimes": [runtime],
            "efforts": { runtime: crate::format::efforts(runtime) },
            "accounts": { runtime: profiles_running(overview, runtime, Some(model), current, now) },
        }))
        .collect())
}

fn profiles_running(overview: Option<&Value>, runtime: &str, model: Option<&str>, current: Option<&str>, now: f64) -> Value {
    Value::Array(overview.and_then(|o| o.get("profiles")).and_then(Value::as_array).into_iter().flatten()
        .filter(|p| p.get("runtimes").and_then(Value::as_array).is_some_and(|r| r.iter().any(|r| r.as_str() == Some(runtime))))
        // With a model chosen, only those that have it enabled can run it.
        .filter(|p| model.is_none_or(|m| p.get("models").and_then(Value::as_array).is_some_and(|ms| ms.iter().any(|x| x.as_str() == Some(m)))))
        .map(|p| {
            let id = p.get("id").and_then(Value::as_str).unwrap_or("");
            let spent = spent_until(p);
            json!({
                "id": id, "name": p.get("name").cloned().unwrap_or(json!(id)), "current": Some(id) == current,
                "spent": spent.map(|until| spent_view(until, now)),
                // What its line shows: whose account it is, and its quota.
                "kind": p.get("access").and_then(|a| a.get("kind")).cloned().unwrap_or(Value::Null),
                "runtime": p.get("runtime").cloned().unwrap_or(Value::Null),
                "quota": p.get("quota").cloned().unwrap_or(Value::Null),
            })
        })
        .collect())
}

/// The models the station can run, each with the runtimes it runs on (those of the profiles that have it enabled):
/// a model is chosen first, and a runtime only when it has more than one.
fn models(overview: Option<&Value>, now: f64) -> Value {
    let mut on: BTreeMap<&str, (BTreeSet<&str>, Vec<Option<f64>>)> = BTreeMap::new();
    for p in overview.and_then(|o| o.get("profiles")).and_then(Value::as_array).into_iter().flatten() {
        let runtimes: Vec<&str> = p.get("runtimes").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str).collect();
        let back = spent_until(p);
        for model in p.get("models").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str) {
            let entry = on.entry(model).or_default();
            entry.0.extend(runtimes.iter().copied());
            entry.1.push(back);
        }
    }
    // Claude Code first where both run it: it is the one most chats use.
    let order = |r: &&str| RUNTIMES.iter().position(|x| x == r).unwrap_or(usize::MAX);
    Value::Array(on.into_iter().map(|(model, (runtimes, backs))| {
        let mut runtimes: Vec<&str> = runtimes.into_iter().collect();
        runtimes.sort_by_key(order);
        // Spent when every account that runs it has a window used up; back when the first of them refills.
        let spent = backs.iter().all(Option::is_some).then(|| backs.iter().flatten().copied().fold(f64::INFINITY, f64::min));
        // For each runtime: how hard it can think, and who can run it there.
        let efforts: serde_json::Map<String, Value> = runtimes.iter().map(|r| (r.to_string(), json!(crate::format::efforts(r)))).collect();
        let accounts: serde_json::Map<String, Value> = runtimes.iter().map(|r| (r.to_string(), profiles_running(overview, r, Some(model), None, now))).collect();
        json!({
            "model": model, "runtimes": runtimes, "maker": crate::present::maker(Some(model)),
            "efforts": efforts, "accounts": accounts,
            "spent": spent.map(|until| spent_view(until, now)),
        })
    }).collect())
}

/// Used up until a time (or for no one knows how long): `{ until, text, back }` (额度用完 · 3 小时后恢复; 3 小时后恢复).
fn spent_view(until: f64, now: f64) -> Value {
    let until = until.is_finite().then_some(until);
    let back = until.map(|at| format!("{}恢复", crate::format::time_until(at, now)));
    let text = match &back {
        Some(back) => format!("额度用完 · {back}"),
        None => "额度用完".to_string(),
    };
    json!({ "until": until, "text": text, "back": back })
}

/// When a profile whose quota has a window used up can run again: when the last of those windows refills (unknown:
/// infinity). None when nothing of it is used up.
fn spent_until(profile: &Value) -> Option<f64> {
    let quota = profile.get("quota").filter(|q| q.get("state").and_then(Value::as_str) == Some("ok"))?;
    let full: Vec<Option<f64>> = quota.get("windows").and_then(Value::as_array).into_iter().flatten()
        .filter(|w| w.get("usedPercent").and_then(Value::as_f64).is_some_and(|u| u >= 100.0))
        .map(|w| w.get("resetsAt").and_then(Value::as_f64))
        .collect();
    if full.is_empty() {
        return None;
    }
    Some(full.iter().map(|at| at.unwrap_or(f64::INFINITY)).fold(0.0, f64::max))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_station_is_down_as_its_link_finds_it_or_as_it_was_last_until_then() {
        let link = |v: Value| down(&v);
        assert!(link(json!({"state": "offline"})));
        assert!(!link(json!({"state": "online"})));
        // Up and dropped: coming back, not down yet; it answered, but no: there.
        assert!(!link(json!({"state": "reconnecting"})));
        assert!(!link(json!({"state": "error"})));
        // Not found out yet this time: as it was last (a station never seen is taken for up while it is tried).
        assert!(link(json!({"state": "connecting", "last": "offline"})));
        assert!(!link(json!({"state": "connecting", "last": "online"})));
        assert!(!link(json!({"state": "connecting"})));
    }
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
        store.set_shaped();
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
                    // What goes out breaking its shape is a bug here, whatever the test looks at.
                    CoreMessage::Error { error, .. } if error.code == "shape" => panic!("{}", error.message),
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

    /// The workspace's three stations: `a` and `b` seen by ember cloud a while ago, `c` never. Whether each is up is
    /// the device's own finding: their `link` topics.
    fn stations(now_s: f64) -> Value {
        json!({"id": "ws", "stations": [
            {"id": "a", "name": "alpha", "last_seen": now_s as i64 - 10, "version": "0.4.0"},
            {"id": "b", "name": "beta", "last_seen": now_s as i64 - 1000, "version": null},
            {"id": "c", "name": "gamma", "last_seen": null, "version": null},
        ]})
    }

    fn session(key: &str) -> Value {
        json!({"key": key, "connect": "c1", "profile": "p1", "runtime": "claude", "model": "opus", "effort": null, "process": "cold", "pending": 0, "lastTurn": null})
    }

    fn member(thread: u64, key: &str, connect: &str) -> Value {
        json!({"thread": thread, "session": key, "connect": connect, "joinedAt": 1})
    }

    /// Merges `patch` into `base`, key by key.
    fn with(mut base: Value, patch: Value) -> Value {
        if let (Some(b), Some(p)) = (base.as_object_mut(), patch.as_object()) {
            b.extend(p.clone());
        }
        base
    }

    /// A session as the station's list has it, with `patch` over it.
    fn full_session(key: &str, patch: Value) -> Value {
        with(json!({
            "key": key, "connect": "c1", "scope": "thread", "title": null, "createdBy": null, "boundTo": [], "creator": null,
            "participants": [], "runtime": "claude", "profile": "p1", "profilePinned": false, "model": null, "effort": null,
            "runtimeSessionId": null, "workspace": "/w", "running": false, "createdAt": 1, "lastActiveAt": 1, "archivedAt": null,
            "process": "cold", "turns": 0, "pending": 0, "firstText": null, "lastTurn": null,
        }), patch)
    }

    fn turn(id: &str) -> Value {
        json!({"id": id, "kind": "chat", "outcome": null, "declared": null, "detail": null, "startedAt": 1, "endedAt": null})
    }

    /// A profile as a station's overview has it.
    fn profile(id: &str, patch: Value) -> Value {
        with(json!({
            "id": id, "name": id, "runtime": "claude", "runtimes": ["claude"], "access": {"kind": "subscription", "key": ""},
            "home": "/h", "homeExists": true, "model": null, "models": [], "env": [], "usedBy": [], "loginCommand": "",
            "check": null, "login": null, "quota": null,
        }), patch)
    }

    /// A station's overview with these connects and profiles.
    fn overview_of(connects: Vec<Value>, profiles: Vec<Value>) -> Value {
        json!({
            "viewer": {"via": "local"}, "connects": connects, "profiles": profiles, "processes": [],
            "counts": {"sessions": 0, "running": 0, "warm": 0}, "mesh": null, "slackUsers": [], "slackTeams": [],
            "slackInstalls": [], "disk": null, "logins": [],
        })
    }

    fn host_info(hostname: &str) -> Value {
        json!({
            "hostname": hostname, "os": "macOS 26", "arch": "arm64", "cpus": 8, "cpuModel": "M4", "load": 0.2, "uptimeSec": 100,
            "memory": {"totalBytes": 1024, "usedBytes": 512, "swapUsedBytes": null}, "disk": {"path": "/", "totalBytes": 1024, "freeBytes": 512},
            "emberRssBytes": 10, "checkedAt": 1,
        })
    }

    /// A Slack thread as a session's detail lists it.
    fn slack_thread(id: u64) -> Value {
        json!({
            "id": id, "surface": "slack:T1", "channel": "C1", "channelName": "ops", "threadTs": "1.0", "title": null, "createdBy": null,
            "creator": null, "createdAt": 1, "sessions": [], "last": 0, "lastMessage": null, "read": 0, "unread": 0, "people": [], "firstText": null,
        })
    }

    /// A connect as a station's overview has it.
    fn connect(id: &str, name: &str) -> Value {
        json!({
            "id": id, "name": name, "team": null, "enabled": true, "kind": "slack", "mode": "multi-session", "requireMention": true,
            "bind": {"runtime": "claude", "model": null, "effort": null, "profile": null}, "slack": {"appToken": "", "botToken": ""},
            "connection": {"state": "no_tokens"}, "createdBy": null, "sessions": 0, "session": null,
        })
    }

    /// A chat on ember's page with these agents, last written in at `at`.
    fn thread(id: u64, keys: &[&str], at: f64) -> Value {
        json!({
            "id": id, "surface": "ember", "channel": "EMBER", "channelName": null, "threadTs": format!("{id}.0"), "title": null,
            "createdAt": at as i64 - 10, "creator": null, "sessions": keys.iter().map(|k| member(id, k, "ember")).collect::<Vec<_>>(),
            "last": id * 10,
            "lastMessage": {
                "seq": id * 10, "thread": id, "ts": format!("{}.0", id * 10), "authorKind": "agent", "author": keys.first().copied().unwrap_or(""),
                "authorName": null, "text": "好的", "attachments": [], "quotes": [], "declared": null, "createdAt": at as i64, "editedAt": null,
            },
            "read": 0, "unread": 0, "people": [], "firstText": null,
        })
    }

    /// A station's sidebar item, as `/chats` has it, last active at `at`: with a chat when `id` is its thread's.
    fn row(id: &str, at: f64) -> Value {
        let thread = id.parse::<u64>().ok();
        json!({
            "id": id, "session": if thread.is_some() { "s" } else { id }, "thread": thread,
            "title": format!("{id} 的标题"), "agents": [session(id)], "last": null, "unread": false, "mine": false,
            "lastActiveAt": at as i64, "connect": null, "origin": null,
        })
    }

    fn ids(v: &Value) -> Vec<String> {
        v["days"].as_array().unwrap().iter().flat_map(|d| d["items"].as_array().unwrap().iter().map(|i| i["id"].as_str().unwrap().to_string())).collect()
    }

    #[test]
    fn what_is_worth_a_look_about_a_session_is_its_account_its_quota_running_out_and_the_disk_filling_up() {
        let overview = |check: &str, week: f64, free: f64| json!({
            "profiles": [{"id": "a", "name": "A", "check": {"state": check, "detail": "d"}, "quota": {"state": "ok", "windows": [
                {"label": "5 小时", "usedPercent": 10, "resetsAt": 1},
                {"label": "每周", "usedPercent": week, "resetsAt": 2},
            ]}}],
            "disk": {"freeBytes": free, "totalBytes": 1000e9},
        });
        let session = json!({"profile": "a"});
        assert_eq!(attention(Some(&overview("ok", 50.0, 500e9)), &session, 0.0), json!([]), "nothing when all is well");
        assert_eq!(attention(Some(&overview("login", 92.0, 5e9)), &session, 0.0), json!([
            {"kind": "account", "text": "「A」要重新登录"},
            {"kind": "quota", "text": "每周剩余 8%", "more": "马上刷新", "quota": {"left": 8, "mark": "W", "level": "red", "until": 2}},
            {"kind": "disk", "text": "磁盘剩 5 GB"},
        ]));
    }

    #[test]
    fn an_agent_can_be_moved_to_the_profiles_of_its_runtime() {
        let overview = json!({"profiles": [
            {"id": "a", "name": "A", "runtimes": ["claude", "codex"], "models": ["m"]},
            {"id": "b", "name": "B", "runtimes": ["codex"], "models": ["m"], "quota": {"state": "ok", "windows": [{"usedPercent": 100, "resetsAt": 9000}]}},
            {"id": "c", "name": "C", "runtimes": ["claude"], "models": ["m"]},
            {"id": "d", "name": "D", "runtimes": ["codex"], "models": ["other"]},
        ]});
        // Of its runtime, and with its model enabled.
        let session = json!({"runtime": "codex", "profile": "a", "model": "m"});
        assert_eq!(runnable_on(Some(&overview), &session, 0.0), json!([
            {"id": "a", "name": "A", "current": true, "spent": null, "kind": null, "runtime": null, "quota": null},
            {"id": "b", "name": "B", "current": false, "spent": {"until": 9000.0, "text": "额度用完 · 1 分钟内恢复", "back": "1 分钟内恢复"}, "kind": null, "runtime": null, "quota": {"state": "ok", "windows": [{"usedPercent": 100, "resetsAt": 9000}]}},
        ]));
        // Every model of its runtime, each with who runs it.
        let choices = choices(Some(&overview), &session, 0.0);
        assert!(choices.as_array().unwrap().iter().any(|c| c["model"] == "m" && c["accounts"]["codex"].as_array().unwrap().len() == 2));
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

            t.set(workspace(), stations(t.now_s()));
            t.read(&mut ui, 1).await;
            let each = |st: &str| vec![rows(st), link(st), overview(st)];
            assert_eq!(sorted(t.started()), sorted([each("ws/a"), each("ws/b"), each("ws/c")].concat()), "each station's rows (and its overview, for who the viewer is there), nothing to join them with; every station is tried");
            let v = ui.value.clone().unwrap();
            assert_eq!(v["me"], json!({"id": "Me@x.com", "email": "Me@x.com"}));
            assert_eq!(v["loading"], true);
            assert_eq!(v["stations"], json!([
                {"station": "ws/a", "id": "a", "name": "alpha", "state": "connecting"},
                {"station": "ws/b", "id": "b", "name": "beta", "state": "connecting"},
                {"station": "ws/c", "id": "c", "name": "gamma", "state": "connecting"},
            ]));
            assert_eq!(v["days"], json!([]));
            // gamma is not reached: down.
            t.set(link("ws/c"), json!({"state": "offline"}));

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
            // Its agents as the rows' shape has them: what their marks need.
            shown["agents"] = json!([{"key": "s1", "runtime": "claude", "model": "opus", "process": "cold", "pending": 0}]);
            assert_eq!(plain(&items[2]), plain(&shown));

            // A station found down keeps its chats listed, as they were read (the data center keeps them); it only
            // says it is offline.
            t.set(link("ws/b"), json!({"state": "offline"}));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!(ids(&v), vec!["1", "1", "s1"]);
            assert_eq!(v["stations"][1]["state"], "offline");
            // Under the list, what is wrong: beta and gamma offline, counted.
            assert_eq!(v["trouble"], json!({"text": "2 台 station 异常", "state": "offline"}));
            // Each of its rows says so itself; the online station's say nothing.
            let items = &v["days"][0]["items"];
            assert_eq!((items[0]["offline"].clone(), items[1]["offline"].clone()), (Value::Null, json!("beta 离线")));
            t.set(link("ws/b"), json!({"state": "online"}));
            t.read(&mut ui, 1).await;
            // One wrong station says itself.
            assert_eq!(ui.value.as_ref().unwrap()["trouble"], json!({"text": "gamma 离线", "state": "offline"}));

            // One station failing shows as that station's state; the other's rows stay.
            t.store.set(&rows("ws/a"), Err(CoreError::new("http_500", "坏了")));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!(v["stations"][0], json!({"station": "ws/a", "id": "a", "name": "alpha", "state": "error", "message": "坏了"}));
            assert_eq!(ids(&v), vec!["1"]);
            // The link dropping, with rows read: reconnecting, rows kept.
            t.set(rows("ws/a"), json!([row("1", now - 1000.0)]));
            t.set(link("ws/a"), json!({"state": "reconnecting", "message": "连接断开了"}));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!((v["stations"][0]["state"].as_str(), v["stations"][0]["message"].as_str()), (Some("connecting"), Some("连接断开了")));
            assert_eq!(ids(&v).len(), 2);
            // alpha coming back and gamma offline: counted, marked by the worse.
            assert_eq!(v["trouble"], json!({"text": "2 台 station 异常", "state": "offline"}));
            // Its rows say so themselves; the other station's say nothing. Failing and retried, the same, in other words.
            let reconnecting = |v: &Value| v["days"][0]["items"].as_array().unwrap().iter().map(|i| (i["station"].as_str().unwrap().to_string(), i["reconnecting"].clone())).collect::<Vec<_>>();
            assert!(reconnecting(&v).contains(&("ws/a".into(), json!("正在重连 alpha…"))), "{v}");
            assert!(reconnecting(&v).iter().all(|(s, r)| s == "ws/a" || r.is_null()), "{v}");
            t.set(link("ws/a"), json!({"state": "error", "message": "没有权限"}));
            t.read(&mut ui, 1).await;
            assert!(reconnecting(ui.value.as_ref().unwrap()).contains(&("ws/a".into(), json!("连不上 alpha，正在重试"))));
            t.set(link("ws/a"), json!({"state": "online"}));
            t.read(&mut ui, 1).await;
            assert!(reconnecting(ui.value.as_ref().unwrap()).iter().all(|(_, r)| r.is_null()));

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
            t.set(workspace(), stations(t.now_s()));
            t.read(&mut ui, 1).await;
            t.started();
            // `a` leaves the workspace.
            let mut without_a = stations(t.now_s());
            without_a["stations"].as_array_mut().unwrap().remove(0);
            t.set(workspace(), without_a);
            t.read(&mut ui, 1).await;
            let listed: Vec<&str> = ui.value.as_ref().unwrap()["stations"].as_array().unwrap().iter().map(|s| s["id"].as_str().unwrap()).collect();
            assert_eq!(listed, vec!["b", "c"]);
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
            assert_eq!(v["me"], json!({"id": "local"}));
            assert_eq!(v["stations"], json!([{"station": "local", "id": "local", "name": "", "state": "online"}]));
        });
    }

    #[test]
    fn mine_keeps_the_rows_the_station_says_are_the_viewers() {
        run(async {
            let t = setup();
            let mut all = Ui::default();
            let mut mine = Ui::default();
            t.subscribe(1, Topic::Chats { scope: "ws".into(), mine: false });
            t.set(workspace(), stations(t.now_s()));
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
            named["last"] = json!({"seq": 7, "authorKind": "agent", "author": "a", "authorName": null, "text": "好的", "createdAt": now as i64 - 1});
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
            t.set(workspace(), stations(t.now_s()));
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
            t.set(workspace(), stations(t.now_s()));
            t.read(&mut ui, 1).await;
            let each = |st: &str| vec![link(st), overview(st), host_of(st)];
            let watched = sorted([vec![workspace()], each("ws/a"), each("ws/b"), each("ws/c")].concat());
            assert_eq!(sorted(t.started()), watched);
            t.store.unsubscribe(1, 1);
            // The view itself goes after the grace, then what it watched after another.
            tokio::time::sleep(std::time::Duration::from_millis(EVICT_AFTER_MS * 5 / 4 / SPEEDUP)).await;
            assert!(t.stopped().is_empty());
            tokio::time::sleep(std::time::Duration::from_millis(EVICT_AFTER_MS * 5 / 4 / SPEEDUP)).await;
            assert_eq!(t.stopped(), watched);
            assert!(t.store.live_topics().is_empty());
        });
    }

    #[test]
    fn stations_shows_each_station_with_its_models() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Stations { scope: "ws".into() });
            t.set(workspace(), stations(t.now_s()));
            t.read(&mut ui, 1).await;
            let overview_a = overview_of(vec![], vec![
                // Its week used up: its models are spent until it refills.
                profile("p1", json!({"runtimes": ["codex"], "models": ["o3", "gpt-5"], "quota": {"state": "ok", "detail": null, "checkedAt": 1, "windows": [{"label": "5 小时", "usedPercent": 40, "resetsAt": 100}, {"label": "每周", "usedPercent": 100, "resetsAt": 5000}]}})),
                profile("p2", json!({"runtimes": ["claude"], "models": []})),
                profile("p3", json!({"runtimes": ["claude"], "models": ["sonnet"]})),
                profile("p4", json!({"runtimes": ["claude"], "models": ["opus", "sonnet"]})),
                profile("p5", json!({"runtimes": ["claude", "codex"], "models": ["deepseek-flash"]})),
            ]);
            t.set(overview("ws/a"), overview_a.clone());
            t.set(host_of("ws/a"), host_info("studio"));
            t.set(link("ws/a"), json!({"state": "error", "message": "没有权限"}));
            // beta is not reached: down.
            t.set(link("ws/b"), json!({"state": "offline"}));
            t.read(&mut ui, 1).await;
            let v = ui.value.unwrap();
            let seen = t.now_s();
            assert!(v[0]["lastSeen"].as_f64().is_some_and(|s| (seen - s - 10.0).abs() < 5.0));
            assert_eq!(v[0]["version"], "0.4.0");
            assert_eq!(v[0]["online"], true);
            assert_eq!(v[0]["link"], json!({"state": "error", "message": "没有权限"}));
            let ids: Vec<&str> = v[0]["overview"]["profiles"].as_array().unwrap().iter().filter_map(|p| p["id"].as_str()).collect();
            assert_eq!(ids, ["p1", "p2", "p3", "p4", "p5"]);
            assert_eq!(v[0]["host"]["hostname"], "studio");
            assert_eq!(v[0]["runtimes"], json!([{"runtime": "claude", "models": ["deepseek-flash", "opus", "sonnet"]}, {"runtime": "codex", "models": ["deepseek-flash", "gpt-5", "o3"]}]));
            // An account run on both offers its model on both: a runtime is chosen for it.
            let models: Vec<Value> = v[0]["models"].as_array().unwrap().iter().map(|m| json!({"model": m["model"], "runtimes": m["runtimes"], "spent": m["spent"]["until"]})).collect();
            assert_eq!(models, vec![
                json!({"model": "deepseek-flash", "runtimes": ["claude", "codex"], "spent": null}), json!({"model": "gpt-5", "runtimes": ["codex"], "spent": 5000.0}),
                json!({"model": "o3", "runtimes": ["codex"], "spent": 5000.0}), json!({"model": "opus", "runtimes": ["claude"], "spent": null}), json!({"model": "sonnet", "runtimes": ["claude"], "spent": null}),
            ]);
            // Each with its maker, how hard each runtime can think, who runs it there, and a used-up quota in words.
            let gpt = &v[0]["models"][1];
            assert_eq!((gpt["maker"]["id"].as_str(), gpt["efforts"]["codex"][0].as_str(), gpt["accounts"]["codex"][0]["id"].as_str()), (Some("openai"), Some("minimal"), Some("p1")));
            assert!(gpt["spent"]["text"].as_str().unwrap().starts_with("额度用完 · "));
            // Offline: what it was, and since when.
            assert_eq!(
                plain(&v[1]),
                json!({"station": "ws/b", "id": "b", "name": "beta", "online": false, "lastSeen": v[1]["lastSeen"],
                    "link": {"state": "offline"}, "runtimes": [], "models": []})
            );
            assert!(v[1]["summary"].as_str().unwrap().starts_with("离线 · "));
            assert!(v[2].get("lastSeen").is_none());
        });
    }

    #[test]
    fn connects_lists_every_online_stations_connects() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Connects { scope: "ws".into(), mine: false });
            t.set(workspace(), stations(t.now_s()));
            t.read(&mut ui, 1).await;
            let each = |st: &str| vec![overview(st), sessions(st), threads(st)];
            assert_eq!(sorted(t.started()), sorted([vec![workspace()], each("ws/a"), each("ws/b"), each("ws/c")].concat()));
            let me = json!({"id": "Me@x.com", "email": "Me@x.com"});
            assert_eq!(ui.value.as_ref().unwrap(), &json!({"me": me, "items": [], "loading": true}));
            let c1 = with(connect("c1", "one"), json!({"createdBy": {"id": "me@x.com", "name": "我"}}));
            let c2 = connect("c2", "two");
            t.set(overview("ws/a"), overview_of(vec![c1.clone(), c2.clone()], vec![]));
            t.store.set(&overview("ws/b"), Err(CoreError::new("offline", "连不上")));
            t.read(&mut ui, 1).await;
            let v = ui.value.as_ref().unwrap();
            let listed: Vec<(&str, &str)> = v["items"].as_array().unwrap().iter().map(|i| (i["station"].as_str().unwrap(), i["connect"]["id"].as_str().unwrap())).collect();
            assert_eq!(listed, [("ws/a", "c1"), ("ws/a", "c2")]);
            assert_eq!((v["loading"].as_bool(), v["items"][0]["running"].as_i64(), v["items"][0]["sessions"].as_array().map(Vec::len)), (Some(false), Some(0), Some(0)));
            // Its owner, named for people: the viewer.
            assert_eq!(v["items"][0]["connect"]["createdBy"]["shown"]["display"], "你");
            // What it says of itself is the core's.
            assert_eq!(ui.value.as_ref().unwrap()["items"][0]["connect"]["statusText"], "未连接 Slack");
            // Only mine: the connects the viewer added.
            let mut mine = Ui::default();
            t.subscribe(2, Topic::Connects { scope: "ws".into(), mine: true });
            t.read(&mut mine, 2).await;
            let mine: Vec<String> = mine.value.unwrap()["items"].as_array().unwrap().iter().map(|i| i["connect"]["id"].as_str().unwrap().to_string()).collect();
            assert_eq!(mine, ["c1"]);
        });
    }

    #[test]
    fn times_in_words_go_out_fresh_each_minute() {
        run(async {
            let t = setup();
            t.host.set_utc_offset_min(480);
            t.store.set_clock();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Chats { scope: "local".into(), mine: false });
            t.read(&mut ui, 1).await;
            // One clock, set for a second past the next minute (and again each minute), shared by everything shown.
            let clock = |ms: &u64| *ms > 1000 && *ms <= 61_000 && *ms != EVICT_AFTER_MS;
            let count = || t.host.sleeps.borrow().iter().filter(|ms| clock(ms)).count();
            let before = count();
            assert!(before >= 1, "{:?}", t.host.sleeps.borrow());
            t.subscribe(2, Topic::Chats { scope: "local".into(), mine: true });
            assert_eq!(count(), before, "a second view shares it");
        });
    }

    /// A value without what the clients show of it (present.rs): what a view puts together, alone.
    fn plain(v: &Value) -> Value {
        const SHOWN: [&str; 32] = ["time", "statusText", "tone", "badgeText", "titleText", "agentText", "maker", "runtimeText", "processText", "efforts", "modeText", "modeShort", "runText", "presence", "checkText", "checkTone", "preview", "makers", "mark", "order", "left", "level", "refills", "shown", "processesText", "by", "waiting", "since", "originText", "mark", "summary", "modelsText"];
        match v {
            Value::Array(items) => Value::Array(items.iter().map(plain).collect()),
            // An absent option is left out, as the shapes send it.
            Value::Object(map) => Value::Object(map.iter().filter(|(k, v)| !SHOWN.contains(&k.as_str()) && !v.is_null()).map(|(k, v)| (k.clone(), plain(v))).collect()),
            other => other.clone(),
        }
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
            t.set(sessions("ws/a"), json!([full_session("k", json!({"connect": "ember"}))]));
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
            // And its workspace, which says whether the station is online.
            assert_eq!(sorted(t.started()), sorted(vec![threads("ws/a"), sessions("ws/a"), page_of("ws/a", 7), rows("ws/a"), overview("ws/a"), link("ws/a"), workspace()]));
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
            t.set(sessions("ws/a"), json!([full_session("j", json!({"connect": "ember"}))]));
            t.read(&mut ui, 1).await;
            let agents = ui.value.clone().unwrap()["agents"].clone();
            assert_eq!((agents.as_array().unwrap().len(), agents[0]["session"]["key"].as_str(), agents[0]["status"].as_str()), (1, Some("j"), Some("idle")));
            assert!(agents[0].get("connect").is_none() && agents[0].get("profile").is_none());

            t.set(session_of("ws/a", "k"), json!({"session": full_session("k", json!({"profile": "p2"})), "threads": [chat.clone()], "turns": [turn("t1")]}));
            t.store.set(&session_of("ws/a", "j"), Err(CoreError::new("http_404", "没有这个会话")));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!(v["me"], json!({"id": "Me@x.com", "email": "Me@x.com"}));
            assert_eq!(v["title"], "排查");
            assert_eq!(plain(&v["thread"]), plain(&chat));
            assert_eq!(plain(&v["people"]), plain(&chat["people"]));
            assert_eq!(v["people"][0]["shown"]["name"], "本机管理页");
            assert_eq!(v["link"], json!({"state": "connecting"}));
            assert_eq!((v["messages"].as_array().unwrap().len(), v["more"].clone()), (30, json!(true)));
            assert_eq!(v["agents"].as_array().unwrap().len(), 1, "an agent that cannot be read is left out");
            assert_eq!(v["agents"][0]["session"]["key"], "k");
            assert_eq!(v["agents"][0]["turns"][0]["id"], "t1");
            assert_eq!(plain(&v["agents"][0]["threads"]), plain(&json!([chat])));
            assert_eq!((v["agents"][0]["connect"].clone(), v["agents"][0]["profile"].clone()), (Value::Null, Value::Null));

            t.set(overview("ws/a"), overview_of(vec![connect("c1", "Slack")], vec![profile("p1", json!({})), profile("p2", json!({"name": "主力"}))]));
            t.set(link("ws/a"), json!({"state": "online"}));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!((v["agents"][0]["connect"]["id"].as_str(), v["agents"][0]["connect"]["name"].as_str()), (Some("c1"), Some("Slack")));
            assert_eq!((v["agents"][0]["profile"]["id"].as_str(), v["agents"][0]["profile"]["name"].as_str()), (Some("p2"), Some("主力")));
            assert_eq!(v["link"], json!({"state": "online"}));

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
            appended[0]["system"] = json!(false);
            assert_eq!(plain(&serde_json::to_value(delta).unwrap()), plain(&json!([{"path": ["messages"], "append": appended}])));
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
            t.set(session_of("ws/a", "n"), json!({"session": full_session("n", json!({"connect": "ember"})), "threads": [], "turns": []}));
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
            t.set(session_of("local", "k"), json!({"session": full_session("k", json!({})), "threads": [], "turns": []}));
            t.read(&mut ui, 1).await;
            let v = ui.value.unwrap();
            assert_eq!(v["title"], "部署挂了");
            assert_eq!(v["thread"]["surface"], "slack:T1");
            assert_eq!(v["messages"].as_array().unwrap().len(), 2);
            assert_eq!(v["me"], json!({"id": "local"}));
        });
    }

    #[test]
    fn an_agent_without_a_chat_is_its_page_with_no_messages() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Chat { station: "ws/a".into(), thread: None, session: Some("k".into()) });
            t.read(&mut ui, 1).await;
            assert_eq!(sorted(t.started()), sorted(vec![session_of("ws/a", "k"), rows("ws/a"), sessions("ws/a"), overview("ws/a"), link("ws/a"), workspace()]));
            t.set(session_of("ws/a", "k"), json!({"session": full_session("k", json!({})), "threads": [slack_thread(3)], "turns": [turn("t1")]}));
            t.read(&mut ui, 1).await;
            assert!(ui.value.is_none(), "its title is the station's: it waits for the items");
            let mut item = row("k", t.host.now_ms());
            item["title"] = json!("部署挂了");
            t.set(rows("ws/a"), json!([row("7", t.host.now_ms()), item]));
            t.set(overview("ws/a"), overview_of(vec![connect("c1", "Slack")], vec![]));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!((v["thread"].clone(), v["title"].clone(), v["messages"].clone(), v["outbox"].clone(), v["more"].clone()), (Value::Null, json!("部署挂了"), json!([]), json!([]), json!(false)));
            let a = &v["agents"][0];
            assert_eq!((v["agents"].as_array().unwrap().len(), a["session"]["key"].as_str(), a["connect"]["name"].as_str(), a["status"].as_str()), (1, Some("k"), Some("Slack"), Some("idle")));
            assert_eq!((a["turns"][0]["id"].as_str(), a["threads"][0]["id"].as_i64()), (Some("t1"), Some(3)));
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

    #[test]
    fn a_sent_message_that_arrives_before_its_seq_leaves_the_outbox_with_it() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, chat_topic("ws/a", 7));
            t.set(threads("ws/a"), json!([thread(7, &[], t.host.now_ms())]));
            t.set(page_of("ws/a", 7), page(5, &["早"], Value::Null));
            t.read(&mut ui, 1).await;
            let views = t.router.views();
            let first = views.outbox_add("ws/a", 7, json!({"text": "你好", "attachments": [], "quotes": []}));
            let second = views.outbox_add("ws/a", 7, json!({"text": "你好", "attachments": [], "quotes": []}));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.clone().unwrap()["outbox"].as_array().unwrap().len(), 2);
            // Someone else saying the same does not count; the viewer's own entry takes the first of the two, once.
            let mine = |n: u64, text: &str| { let mut e = entry(n, text); e["author"] = json!("Me@x.com"); e };
            t.store.update(&page_of("ws/a", 7), &mut |p| {
                p["entries"].as_array_mut().unwrap().push(entry(6, "你好"));
                p["entries"].as_array_mut().unwrap().push(mine(7, "你好"));
                p["last"] = json!(7);
            });
            t.read(&mut ui, 1).await;
            let out = ui.value.clone().unwrap()["outbox"].clone();
            assert_eq!(out.as_array().unwrap().iter().map(|m| m["id"].as_str().unwrap()).collect::<Vec<_>>(), vec![second.as_str()]);
            assert!(views.outbox_get("ws/a", 7, &first).is_none());
            // The station's answer for the one already gone changes nothing.
            views.outbox_sent("ws/a", 7, &first, 7);
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.clone().unwrap()["outbox"].as_array().unwrap().len(), 1);
        });
    }
}
