//! The views: what one screen shows, put together from the account and station
//! topics so the UI does no joining, filtering or grouping (docs/client-core.md,
//! Views).
//!
//! A view watches the topics it is built from. Any change of them only
//! invalidates it; the store has it computed when its coalesced emission goes
//! out, so a burst of changes costs one computation. Each computation first
//! brings the watches in line with the workspace's station list: a station
//! that comes online is watched, one that goes offline is let go.

use std::cell::{Cell, RefCell};
use std::collections::{BTreeSet, HashMap, HashSet};
use std::rc::{Rc, Weak};

use serde_json::{Value, json};

use crate::error::Result;
use crate::host::Host;
use crate::protocol::Topic;
use crate::store::{Store, Watch};

/// The cloud counts a station online while it was seen this recently (as `online` in web/src/cloud/gate.tsx).
pub const ONLINE_WITHIN_S: f64 = 150.0;
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
    /// Messages sent from here that the session does not show yet, per (station, session key), oldest first.
    outbox: RefCell<HashMap<(String, String), Vec<Value>>>,
    sent: Cell<u64>,
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
        Rc::new(Views { host, store, email_of, views: RefCell::default(), outbox: RefCell::default(), sent: Cell::new(0) })
    }

    /// A message on its way to a session: shown in its chat at once, as `sending`. Answers its id.
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

    /// The session shows the message now (or it was given up).
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
            Topic::Chats { scope, .. } => (scope.as_str(), |station| vec![Topic::Sessions { station: station.clone() }, Topic::Overview { station: station.clone() }, Topic::Link { station }]),
            Topic::Stations { scope } => (scope.as_str(), |station| vec![Topic::Link { station: station.clone() }, Topic::Overview { station: station.clone() }, Topic::Host { station }]),
            Topic::Connects { scope, .. } => (scope.as_str(), |station| vec![Topic::Overview { station }]),
            Topic::Chat { station, key } => {
                topics.insert(Topic::Session { station: station.clone(), key: key.clone() });
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
        let now_s = self.host.now_ms() / 1000.0;
        let stations = workspace.get("stations").and_then(Value::as_array).into_iter().flatten().filter_map(|s| {
            let id = s.get("id")?.as_str()?.to_string();
            let last_seen = s.get("last_seen").cloned().unwrap_or(Value::Null);
            let online = last_seen.as_f64().is_some_and(|t| now_s - t < ONLINE_WITHIN_S);
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
                        for session in sessions.as_array().into_iter().flatten() {
                            if mine && !is_mine(&me, session.get("creator")) {
                                continue;
                            }
                            let connect = find(connects.as_ref(), session.get("connect"));
                            rows.push(json!({ "station": s.address, "stationName": s.name, "session": session, "connect": connect }));
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
        let detail = match self.store.value(&Topic::Session { station: station.to_string(), key: key.to_string() })? {
            Ok(detail) => detail,
            Err(error) => return Some(Err(error)),
        };
        let overview = self.ok(Topic::Overview { station: station.to_string() });
        let of = |list: &str, id: &str| find(overview.as_ref().and_then(|o| o.get(list)), detail["session"].get(id));
        // The scope the station belongs to: "local", or its workspace.
        let scope = station.split_once('/').map_or(station, |(workspace, _)| workspace);
        let outbox = self.outbox.borrow().get(&(station.to_string(), key.to_string())).cloned().unwrap_or_default();
        Some(Ok(json!({
            "outbox": outbox,
            "me": self.me(scope),
            "connect": of("connects", "connect"),
            "profile": of("profiles", "profile"),
            "link": self.link(station, true),
            "detail": detail,
        })))
    }
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
    fn host_of(st: &str) -> Topic {
        Topic::Host { station: st.into() }
    }
    fn sorted(mut topics: Vec<Topic>) -> Vec<Topic> {
        topics.sort_by_key(|t| format!("{t:?}"));
        topics
    }

    /// `a` online, `b` seen too long ago, `c` never.
    fn stations(now_s: f64, a_online: bool, b_online: bool) -> Value {
        let seen = |online: bool| if online { json!(now_s - 10.0) } else { json!(now_s - 1000.0) };
        json!({"id": "ws", "stations": [
            {"id": "a", "name": "alpha", "last_seen": seen(a_online), "version": "0.4.0"},
            {"id": "b", "name": "beta", "last_seen": seen(b_online), "version": null},
            {"id": "c", "name": "gamma", "last_seen": null, "version": null},
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
            assert_eq!(sorted(t.started()), sorted(vec![sessions("ws/a"), overview("ws/a"), link("ws/a")]));
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
            assert_eq!(sorted(t.started()), sorted(vec![sessions("ws/b"), overview("ws/b"), link("ws/b")]));
            let states: Vec<&str> = ui.value.as_ref().unwrap()["stations"].as_array().unwrap().iter().map(|s| s["state"].as_str().unwrap()).collect();
            assert_eq!(states, vec!["offline", "connecting", "offline"]);
            // `a`'s topics are let go: stopped after the grace, like a UI unsubscribing.
            assert!(t.stopped().is_empty());
            tokio::time::sleep(std::time::Duration::from_millis(EVICT_AFTER_MS * 5 / 4 / SPEEDUP)).await;
            assert_eq!(t.stopped(), sorted(vec![sessions("ws/a"), overview("ws/a"), link("ws/a")]));
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

    #[test]
    fn chat_is_the_session_with_its_connect_profile_and_link() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            let session_topic = Topic::Session { station: "ws/a".into(), key: "k".into() };
            t.subscribe(1, Topic::Chat { station: "ws/a".into(), key: "k".into() });
            t.read(&mut ui, 1).await;
            assert_eq!(sorted(t.started()), sorted(vec![session_topic.clone(), overview("ws/a"), link("ws/a")]));
            assert!(ui.value.is_none(), "nothing before the session is read");

            let timeline: Vec<Value> = (0..40).map(|i| json!({"kind": "message", "text": format!("第 {i} 条")})).collect();
            t.set(session_topic.clone(), json!({"session": {"key": "k", "connect": "c1", "profile": "p2"}, "transcript": {"timeline": timeline}}));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!((v["connect"].clone(), v["profile"].clone()), (Value::Null, Value::Null));
            assert_eq!(v["link"], json!({"state": "connecting", "message": null}));
            assert_eq!(v["me"], json!({"id": "Me@x.com", "email": "Me@x.com"}));
            assert_eq!(v["detail"]["transcript"]["timeline"].as_array().unwrap().len(), 40);

            t.set(overview("ws/a"), json!({"connects": [{"id": "c1", "name": "Slack"}], "profiles": [{"id": "p1"}, {"id": "p2", "name": "主力"}]}));
            t.set(link("ws/a"), json!({"state": "online"}));
            t.read(&mut ui, 1).await;
            let v = ui.value.clone().unwrap();
            assert_eq!(v["connect"], json!({"id": "c1", "name": "Slack"}));
            assert_eq!(v["profile"], json!({"id": "p2", "name": "主力"}));
            assert_eq!(v["link"], json!({"state": "online", "message": null}));

            // A new message goes out as an append, not the whole transcript.
            t.store.update(&session_topic, &mut |d| d["transcript"]["timeline"].as_array_mut().unwrap().push(json!({"kind": "message", "text": "新的"})));
            t.host.settle().await;
            let sent = t.host.take_emitted();
            assert_eq!(sent.len(), 1);
            let CoreMessage::Delta { delta, .. } = &sent[0].1 else { panic!("{:?}", sent[0]) };
            assert_eq!(serde_json::to_value(delta).unwrap(), json!([{"path": ["detail", "transcript", "timeline"], "append": [{"kind": "message", "text": "新的"}]}]));

            t.store.set(&session_topic, Err(CoreError::new("http_404", "没有这个会话")));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.error.as_ref().unwrap().message, "没有这个会话");
        });
    }

    #[test]
    fn a_sent_message_shows_until_the_session_has_it() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            let session_topic = Topic::Session { station: "ws/a".into(), key: "k".into() };
            t.subscribe(1, Topic::Chat { station: "ws/a".into(), key: "k".into() });
            t.set(session_topic.clone(), json!({"session": {"key": "k"}, "chats": []}));
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

            // The session's own copy and the outbox entry leaving go out together.
            t.store.set(&session_topic, Ok(json!({"session": {"key": "k"}, "chats": [{"messages": [{"text": "你好"}]}]})));
            views.outbox_remove("ws/a", "k", &id);
            t.host.settle().await;
            assert_eq!(t.host.take_emitted().len(), 1);
        });
    }
}
