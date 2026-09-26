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

use crate::error::Result;
use crate::host::Host;
use crate::protocol::Topic;
use crate::station::ember_thread;
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
    /// Messages sent from here that the chat does not show yet, per (station, session key), oldest first.
    outbox: RefCell<HashMap<(String, String), Vec<Value>>>,
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
    pub fn outbox_add(&self, station: &str, key: &str, message: Value) -> String {
        self.sent.set(self.sent.get() + 1);
        let id = format!("out-{}", self.sent.get());
        let mut entry = message;
        entry["id"] = json!(id);
        entry["createdAt"] = json!(self.host.now_ms());
        entry["state"] = json!("sending");
        self.outbox.borrow_mut().entry((station.to_string(), key.to_string())).or_default().push(entry);
        self.outbox_changed(station, key);
        id
    }

    pub fn outbox_get(&self, station: &str, key: &str, id: &str) -> Option<Value> {
        self.outbox.borrow().get(&(station.to_string(), key.to_string()))?.iter().find(|m| m["id"] == id).cloned()
    }

    /// Marks an outgoing message `sending` again, or `failed` with the error's message.
    pub fn outbox_state(&self, station: &str, key: &str, id: &str, failed: Option<&str>) {
        if let Some(entry) = self.outbox.borrow_mut().get_mut(&(station.to_string(), key.to_string())).and_then(|list| list.iter_mut().find(|m| m["id"] == id)) {
            entry["state"] = json!(if failed.is_some() { "failed" } else { "sending" });
            entry["error"] = json!(failed);
        }
        self.outbox_changed(station, key);
    }

    /// The station has the message as `seq`: the entry stays until the chat's messages reach it (and leaves in
    /// that emission). Nobody looking at the chat: it goes now.
    pub fn outbox_sent(&self, station: &str, key: &str, id: &str, seq: u64) {
        if !self.views.borrow().contains_key(&Topic::Chat { station: station.to_string(), key: key.to_string() }) {
            return self.outbox_remove(station, key, id);
        }
        if let Some(entry) = self.outbox.borrow_mut().get_mut(&(station.to_string(), key.to_string())).and_then(|list| list.iter_mut().find(|m| m["id"] == id)) {
            entry["seq"] = json!(seq);
        }
        self.outbox_changed(station, key);
    }

    /// Given up.
    pub fn outbox_remove(&self, station: &str, key: &str, id: &str) {
        let mut outbox = self.outbox.borrow_mut();
        let at = (station.to_string(), key.to_string());
        if let Some(list) = outbox.get_mut(&at) {
            list.retain(|m| m["id"] != id);
            if list.is_empty() {
                outbox.remove(&at);
            }
        }
        drop(outbox);
        self.outbox_changed(station, key);
    }

    fn outbox_changed(&self, station: &str, key: &str) {
        self.store.invalidate(&Topic::Chat { station: station.to_string(), key: key.to_string() });
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
            Topic::Chat { station, key } => self.chat(station, key),
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
            Topic::Chat { station, key } => {
                let session = Topic::Session { station: station.clone(), key: key.clone() };
                // Its messages, once the session says which thread is its chat.
                if let Some(id) = self.chat_thread(&session) {
                    topics.insert(Topic::Thread { station: station.clone(), thread: id });
                }
                topics.insert(session);
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

    /// The id of the session's chat on ember's page, as its topic lists its threads.
    fn chat_thread(&self, session: &Topic) -> Option<u64> {
        ember_thread(self.ok(session.clone())?.get("threads")?)?.get("id")?.as_u64()
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
                match self.store.value(&Topic::Sessions { station: s.address.clone() }) {
                    Some(Err(error)) => ("error", json!(error.message)),
                    None => {
                        loading = true;
                        if link_state == "error" { ("error", link_message) } else { ("connecting", Value::Null) }
                    }
                    Some(Ok(sessions)) => {
                        let connects = self.ok(Topic::Overview { station: s.address.clone() }).and_then(|o| o.get("connects").cloned());
                        let unread = unread_by_session(self.ok(Topic::Threads { station: s.address.clone() }).as_ref());
                        for session in sessions.as_array().into_iter().flatten() {
                            // "Mine" for chats is where the viewer takes part: started it, or is among its participants.
                            let takes_part = is_mine(&me, session.get("creator"))
                                || session.get("participants").and_then(Value::as_array).is_some_and(|people| people.iter().any(|p| is_mine(&me, Some(p))));
                            if mine && !takes_part {
                                continue;
                            }
                            let connect = find(connects.as_ref(), session.get("connect"));
                            let count = session.get("key").and_then(Value::as_str).and_then(|k| unread.get(k)).copied().unwrap_or(0);
                            rows.push(json!({ "station": s.address, "stationName": s.name, "session": session, "connect": connect, "unread": count }));
                        }
                        // Sessions already read stay in view while the link comes back.
                        match link_state {
                            "error" => ("error", link_message),
                            "offline" => ("connecting", link_message),
                            _ => ("online", Value::Null),
                        }
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
        let at = |row: &Value| row["session"]["lastActiveAt"].as_f64().unwrap_or(0.0);
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

    fn chat(&self, station: &str, key: &str) -> Option<Result<Value>> {
        let session = Topic::Session { station: station.to_string(), key: key.to_string() };
        let detail = match self.store.value(&session)? {
            Ok(detail) => detail,
            Err(error) => return Some(Err(error)),
        };
        let threads = detail.get("threads").cloned().unwrap_or_else(|| json!([]));
        let thread = ember_thread(&threads).cloned();
        // With a chat, nothing shows until its latest messages are read.
        let (messages, more) = match thread.as_ref().and_then(|t| t.get("id")?.as_u64()) {
            Some(id) => match self.store.value(&Topic::Thread { station: station.to_string(), thread: id })? {
                Ok(page) => (page.get("messages").cloned().unwrap_or_else(|| json!([])), page.get("more").cloned().unwrap_or(json!(false))),
                Err(error) => return Some(Err(error)),
            },
            None => (json!([]), json!(false)),
        };
        // A sent message leaves the outbox as its own copy (or anything later) arrives.
        let newest = messages.as_array().and_then(|m| m.last()).and_then(|m| m.get("seq")?.as_u64());
        let at = (station.to_string(), key.to_string());
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
        let overview = self.ok(Topic::Overview { station: station.to_string() });
        let of = |list: &str, id: &str| find(overview.as_ref().and_then(|o| o.get(list)), detail["session"].get(id));
        // The scope the station belongs to: "local", or its workspace.
        let scope = station.split_once('/').map_or(station, |(workspace, _)| workspace);
        Some(Ok(json!({
            "me": self.me(scope),
            "session": detail.get("session").cloned().unwrap_or(Value::Null),
            "threads": threads,
            "turns": detail.get("turns").cloned().unwrap_or_else(|| json!([])),
            "thread": thread,
            "messages": messages,
            "more": more,
            "outbox": outbox,
            "connect": of("connects", "connect"),
            "profile": of("profiles", "profile"),
            "link": self.link(station, true),
        })))
    }
}

/// Unread messages per session key: the sum over the threads it takes part in.
fn unread_by_session(threads: Option<&Value>) -> HashMap<String, u64> {
    let mut counts = HashMap::new();
    for thread in threads.and_then(Value::as_array).into_iter().flatten() {
        let unread = thread.get("unread").and_then(Value::as_u64).unwrap_or(0);
        for member in thread.get("sessions").and_then(Value::as_array).into_iter().flatten() {
            if let Some(key) = member.get("session").and_then(Value::as_str) {
                *counts.entry(key.to_string()).or_default() += unread;
            }
        }
    }
    counts
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

    fn session(key: &str, at: f64, creator: Value) -> Value {
        json!({"key": key, "connect": "c1", "profile": "p1", "lastActiveAt": at, "creator": creator})
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
            t.set(sessions("ws/a"), json!([session("old", now - 2000.0, Value::Null), {"key": "new", "connect": "gone", "lastActiveAt": now - 1000.0}]));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!(v["loading"], false);
            assert_eq!(v["stations"][0]["state"], "online");
            let items = &v["days"][0]["items"];
            assert_eq!(v["days"][0]["at"], json!(now - 1000.0));
            assert_eq!(items[0]["session"]["key"], "new");
            assert_eq!(items[0]["connect"], Value::Null);
            assert_eq!(items[1]["session"]["key"], "old");
            assert_eq!(items[1]["connect"], json!({"id": "c1", "name": "Slack"}));
            assert_eq!(items[1]["unread"], 0, "no threads read yet: nothing unread");
            assert_eq!((items[1]["station"].as_str(), items[1]["stationName"].as_str()), (Some("ws/a"), Some("alpha")));

            // One station failing shows as that station's state.
            t.store.set(&sessions("ws/a"), Err(CoreError::new("http_500", "坏了")));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.as_ref().unwrap()["stations"][0], json!({"station": "ws/a", "id": "a", "name": "alpha", "state": "error", "message": "坏了"}));
            // The link dropping, with sessions read: reconnecting.
            t.set(sessions("ws/a"), json!([]));
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
            t.set(sessions("local"), json!([
                session("yesterday-late", midnight - 1000.0, Value::Null),
                session("three-days", midnight - 2.0 * DAY_MS - 1000.0, Value::Null),
                session("today", today, Value::Null),
                session("yesterday-early", midnight - DAY_MS + 1000.0, Value::Null),
            ]));
            t.read(&mut ui, 1).await;
            let v = ui.value.unwrap();
            let days: Vec<(i64, Vec<&str>)> = v["days"]
                .as_array()
                .unwrap()
                .iter()
                .map(|d| (d["daysAgo"].as_i64().unwrap(), d["items"].as_array().unwrap().iter().map(|i| i["session"]["key"].as_str().unwrap()).collect()))
                .collect();
            assert_eq!(days, vec![(0, vec!["today"]), (1, vec!["yesterday-late", "yesterday-early"]), (3, vec!["three-days"])]);
            assert_eq!(v["days"][1]["at"], json!(midnight - 1000.0));
            assert_eq!(v["me"], json!({"id": "local", "email": null}));
            assert_eq!(v["stations"], json!([{"station": "local", "id": "local", "name": "", "state": "online", "message": null}]));
        });
    }

    #[test]
    fn mine_keeps_the_viewers_sessions() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Chats { scope: "ws".into(), mine: true });
            t.set(workspace(), stations(t.now_s(), true, false));
            t.read(&mut ui, 1).await;
            let now = t.host.now_ms();
            t.set(sessions("ws/a"), json!([
                session("by-id", now - 1.0, json!({"id": "Me@x.com", "name": "我"})),
                session("by-email", now - 2.0, json!({"id": "U123", "email": "me@X.com"})),
                session("other", now - 3.0, json!({"id": "U9", "email": "you@x.com"})),
                session("slack", now - 4.0, json!({"id": "U8", "email": null})),
                session("nobody", now - 5.0, Value::Null),
            ]));
            t.read(&mut ui, 1).await;
            let keys: Vec<&str> = ui.value.as_ref().unwrap()["days"][0]["items"].as_array().unwrap().iter().map(|i| i["session"]["key"].as_str().unwrap()).collect();
            assert_eq!(keys, vec!["by-id", "by-email"]);
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
                t.set(sessions(st), json!([session(st, t.host.now_ms(), Value::Null)]));
            }
            t.store.update(&sessions("ws/a"), &mut |v| v[0]["title"] = json!("改了"));
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

    fn member(thread: u64, key: &str) -> Value {
        json!({"thread": thread, "session": key, "connect": "ember"})
    }

    #[test]
    fn chats_counts_unread_per_session() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Chats { scope: "local".into(), mine: false });
            let now = t.host.now_ms();
            t.set(sessions("local"), json!([session("a", now - 1.0, Value::Null), session("b", now - 2.0, Value::Null)]));
            t.set(threads("local"), json!([
                {"id": 1, "sessions": [member(1, "a")], "unread": 2},
                {"id": 2, "sessions": [member(2, "a"), member(2, "b")], "unread": 3},
                {"id": 3, "sessions": [member(3, "gone")], "unread": 9},
            ]));
            t.read(&mut ui, 1).await;
            let items = ui.value.clone().unwrap()["days"][0]["items"].clone();
            assert_eq!((items[0]["unread"].clone(), items[1]["unread"].clone()), (json!(5), json!(3)));
            // Read: the counts follow the threads topic.
            t.store.update(&threads("local"), &mut |list| list[1]["unread"] = json!(0));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.clone().unwrap()["days"][0]["items"][0]["unread"], 2);
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

    #[test]
    fn chat_is_the_session_its_chat_and_its_messages() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            let session_topic = Topic::Session { station: "ws/a".into(), key: "k".into() };
            let thread_topic = Topic::Thread { station: "ws/a".into(), thread: 7 };
            t.subscribe(1, Topic::Chat { station: "ws/a".into(), key: "k".into() });
            t.read(&mut ui, 1).await;
            assert_eq!(sorted(t.started()), sorted(vec![session_topic.clone(), overview("ws/a"), link("ws/a")]));
            assert!(ui.value.is_none(), "nothing before the session is read");

            let slack = json!({"id": 3, "surface": "slack:T1", "sessions": [member(3, "k")]});
            let ember = json!({"id": 7, "surface": "ember", "sessions": [member(7, "k")]});
            t.set(session_topic.clone(), json!({"session": {"key": "k", "connect": "c1", "profile": "p2"}, "threads": [slack, ember], "turns": [{"id": "t1"}]}));
            t.read(&mut ui, 1).await;
            assert_eq!(t.started(), vec![thread_topic.clone()], "its chat's messages are read next");
            assert!(ui.value.is_none(), "nothing before its messages are read");

            let page: Vec<Value> = (11..=40).map(|i| json!({"seq": i, "text": format!("第 {i} 条")})).collect();
            t.set(thread_topic.clone(), json!({"rev": 40, "messages": page, "more": true}));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!((v["connect"].clone(), v["profile"].clone()), (Value::Null, Value::Null));
            assert_eq!(v["link"], json!({"state": "connecting", "message": null}));
            assert_eq!(v["me"], json!({"id": "Me@x.com", "email": "Me@x.com"}));
            assert_eq!(v["session"]["key"], "k");
            assert_eq!(v["threads"].as_array().unwrap().len(), 2);
            assert_eq!(v["turns"], json!([{"id": "t1"}]));
            assert_eq!(v["thread"], ember);
            assert_eq!((v["messages"].as_array().unwrap().len(), v["more"].clone()), (30, json!(true)));

            t.set(overview("ws/a"), json!({"connects": [{"id": "c1", "name": "Slack"}], "profiles": [{"id": "p1"}, {"id": "p2", "name": "主力"}]}));
            t.set(link("ws/a"), json!({"state": "online"}));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!(v["connect"], json!({"id": "c1", "name": "Slack"}));
            assert_eq!(v["profile"], json!({"id": "p2", "name": "主力"}));
            assert_eq!(v["link"], json!({"state": "online", "message": null}));

            // A new message goes out as an append.
            t.store.update(&thread_topic, &mut |p| p["messages"].as_array_mut().unwrap().push(json!({"seq": 41, "text": "新的"})));
            t.host.settle().await;
            let sent = t.host.take_emitted();
            assert_eq!(sent.len(), 1);
            let CoreMessage::Delta { delta, .. } = &sent[0].1 else { panic!("{:?}", sent[0]) };
            assert_eq!(serde_json::to_value(delta).unwrap(), json!([{"path": ["messages"], "append": [{"seq": 41, "text": "新的"}]}]));
            // An older page, in front.
            t.store.update(&thread_topic, &mut |p| {
                p["messages"].as_array_mut().unwrap().insert(0, json!({"seq": 10, "text": "旧的"}));
                p["more"] = json!(false);
            });
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!((v["messages"][0]["seq"].clone(), v["messages"].as_array().unwrap().len(), v["more"].clone()), (json!(10), 32, json!(false)));

            t.store.set(&session_topic, Err(CoreError::new("http_404", "没有这个会话")));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.error.as_ref().unwrap().message, "没有这个会话");
        });
    }

    #[test]
    fn a_chat_without_a_thread_has_no_messages() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Chat { station: "local".into(), key: "k".into() });
            t.set(Topic::Session { station: "local".into(), key: "k".into() }, json!({"session": {"key": "k"}, "threads": [], "turns": []}));
            t.read(&mut ui, 1).await;
            let v = ui.value.unwrap();
            assert_eq!((v["thread"].clone(), v["messages"].clone(), v["more"].clone()), (Value::Null, json!([]), json!(false)));
            assert_eq!(v["me"], json!({"id": "local", "email": null}));
        });
    }

    #[test]
    fn a_sent_message_shows_until_the_chat_has_it() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            let session_topic = Topic::Session { station: "ws/a".into(), key: "k".into() };
            let thread_topic = Topic::Thread { station: "ws/a".into(), thread: 7 };
            t.subscribe(1, Topic::Chat { station: "ws/a".into(), key: "k".into() });
            t.set(session_topic.clone(), json!({"session": {"key": "k"}, "threads": [{"id": 7, "surface": "ember"}], "turns": []}));
            t.read(&mut ui, 1).await;
            t.set(thread_topic.clone(), json!({"rev": 5, "messages": [{"seq": 5, "text": "早"}], "more": false}));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.clone().unwrap()["outbox"], json!([]));

            let views = t.router.views();
            let id = views.outbox_add("ws/a", "k", json!({"text": "你好", "attachments": [], "quotes": []}));
            t.read(&mut ui, 1).await;
            let out = ui.value.clone().unwrap()["outbox"].clone();
            assert_eq!((out[0]["id"].as_str(), out[0]["text"].as_str(), out[0]["state"].as_str()), (Some(id.as_str()), Some("你好"), Some("sending")));

            views.outbox_state("ws/a", "k", &id, Some("连不上 station"));
            t.read(&mut ui, 1).await;
            let out = ui.value.clone().unwrap()["outbox"].clone();
            assert_eq!((out[0]["state"].as_str(), out[0]["error"].as_str()), (Some("failed"), Some("连不上 station")));

            // Sent as seq 6: it stays until the messages reach 6, and leaves in that same emission.
            views.outbox_state("ws/a", "k", &id, None);
            views.outbox_sent("ws/a", "k", &id, 6);
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.clone().unwrap()["outbox"][0]["seq"], 6);
            t.store.update(&thread_topic, &mut |p| p["messages"].as_array_mut().unwrap().push(json!({"seq": 6, "text": "你好"})));
            t.host.settle().await;
            let sent = t.host.take_emitted();
            assert_eq!(sent.len(), 1);
            let CoreMessage::Delta { delta, .. } = &sent[0].1 else { panic!("{:?}", sent[0]) };
            let ops = serde_json::to_value(delta).unwrap();
            assert!(ops.as_array().unwrap().iter().any(|op| op["path"] == json!(["messages"])), "{ops}");
            assert!(ops.as_array().unwrap().iter().any(|op| op["path"] == json!(["outbox"]) && op["set"] == json!([])), "{ops}");
            // Sent while nobody looks: gone at once.
            let id = views.outbox_add("ws/b", "j", json!({"text": "x"}));
            views.outbox_sent("ws/b", "j", &id, 1);
            assert!(views.outbox_get("ws/b", "j", &id).is_none());
        });
    }
}
