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

mod archive;

/// The runtimes a chat can run on, in the order they are offered.
const RUNTIMES: [&str; 2] = ["claude", "codex"];
const DAY_MS: f64 = 86_400_000.0;

/// The email of the signed-in account that reaches a workspace.
pub type EmailOf = Rc<dyn Fn(&str) -> Option<String>>;
/// What still.fail calls a relay, by its host, as `/v1/me` said (`relay_names`).
pub type RelayName = Rc<dyn Fn(&str) -> Option<String>>;
/// Whether the signed-in account that reaches a workspace is in the beta (its `/v1/me` says `user.beta`).
pub type BetaOf = Rc<dyn Fn(&str) -> bool>;

pub struct Views {
    host: Rc<dyn Host>,
    store: Rc<Store>,
    email_of: EmailOf,
    relay_name: RelayName,
    beta_of: BetaOf,
    /// Per live view, the topics it watches.
    views: RefCell<HashMap<Topic, HashMap<Topic, Watch>>>,
    /// Messages sent from here that the chat does not show yet, per (station, thread), oldest first.
    outbox: RefCell<HashMap<(String, u64), Vec<Value>>>,
    sent: Cell<u64>,
    /// Chats asked for here (`chat.create`) by the key the core gave them, until the station has made them and ever
    /// after (a page that opened one keeps its key).
    pending: RefCell<HashMap<String, Pending>>,
    archiving: archive::Archiving,
    /// Views whose words count seconds (a chat's jobs): each computed again when they next change, by the newest timer.
    again: Rc<RefCell<(u64, HashMap<Topic, u64>)>>,
}

/// A chat asked for here. Until its station has made it, it is shown at once from what is known here: its page,
/// its row, the messages sent to it waiting in its queue; then it is the station's chat under the core's key too.
struct Pending {
    station: String,
    /// What `POST /sessions` is sent.
    ask: Value,
    created_at: f64,
    /// What was sent to it before it was made, oldest first: as the outbox has them.
    queue: Vec<Value>,
    /// Why it could not be made, the last time it was tried.
    failed: Option<String>,
    /// Its session and thread, once made.
    made: Option<(String, u64)>,
    /// Its station has listed it: from then on its row is the station's alone, so one archived or removed there is
    /// not shown again from here.
    listed: Cell<bool>,
}

/// The prefix of the keys the core gives chats not made yet: no station's session key starts so.
pub const PENDING_PREFIX: &str = "new:";

/// A station of a scope, as the workspace lists it.
/// Whether a station is taken for down: its link found it so, or — not found out yet this time — it was, last.
fn down(link: &Value) -> bool {
    match link.get("state").and_then(Value::as_str) {
        Some("offline") => true,
        Some("connecting") => link.get("last").and_then(Value::as_str) == Some("offline"),
        _ => false,
    }
}

/// Whether a station's versions offer the 测试版 switch: it can be put on a channel (its station's version says the one
/// it is on), and it is on the beta already (to be switched back) or the account that reaches it is in the beta.
fn beta_offered(overview: Option<&Value>, account_in_beta: impl FnOnce() -> bool) -> bool {
    let station = overview.and_then(|o| o.get("updates")).and_then(Value::as_array).into_iter().flatten().find(|v| v.get("id").and_then(Value::as_str) == Some("station"));
    match station.and_then(|v| v.get("channel")).and_then(Value::as_str) {
        Some("beta") => true,
        Some(_) => account_in_beta(),
        None => false,
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
    pub fn new(host: Rc<dyn Host>, store: Rc<Store>, email_of: EmailOf, relay_name: RelayName, beta_of: BetaOf) -> Rc<Views> {
        Rc::new(Views {
            host,
            store,
            email_of,
            relay_name,
            beta_of,
            views: RefCell::default(),
            outbox: RefCell::default(),
            sent: Cell::new(0),
            pending: RefCell::default(),
            archiving: Default::default(),
            again: Rc::default(),
        })
    }

    /// A chat to be made on a station with what `POST /sessions` is sent: answers the key it goes by here at once.
    pub fn pending_new(&self, station: &str, ask: Value) -> String {
        self.sent.set(self.sent.get() + 1);
        let now = self.host.now_ms();
        let key = format!("{PENDING_PREFIX}{}-{}", now.round() as i64, self.sent.get());
        let chat = Pending { station: station.to_string(), ask, created_at: now, queue: Vec::new(), failed: None, made: None, listed: Cell::new(false) };
        self.pending.borrow_mut().insert(key.clone(), chat);
        self.pending_changed(&key);
        key
    }

    /// A chat asked for here, on this station: `Some(None)` while it is not made, `Some(Some(thread))` once it is.
    pub fn pending_thread(&self, station: &str, key: &str) -> Option<Option<u64>> {
        let pending = self.pending.borrow();
        let chat = pending.get(key).filter(|c| c.station == station)?;
        Some(chat.made.as_ref().map(|(_, thread)| *thread))
    }

    /// What to ask its station for, the chat set to be tried (again): its queue is `sending` once more.
    /// The ask carries its key here (`clientKey`): the station's rows say it of the chat made from it, so its row is
    /// known for this chat's even before the station's answer comes (its events can come first).
    pub fn pending_try(&self, key: &str) -> Option<(String, Value)> {
        let mut pending = self.pending.borrow_mut();
        let chat = pending.get_mut(key).filter(|c| c.made.is_none())?;
        chat.failed = None;
        for m in &mut chat.queue {
            m["state"] = json!("sending");
            m["error"] = Value::Null;
        }
        let mut ask = chat.ask.clone();
        if let Some(ask) = ask.as_object_mut() {
            ask.insert("clientKey".into(), json!(key));
        }
        let asked = (chat.station.clone(), ask);
        drop(pending);
        self.pending_changed(key);
        Some(asked)
    }

    /// A message sent to a chat not made yet: it waits in its queue, shown as `sending` (or `failed`, as the chat).
    pub fn pending_queue(&self, key: &str, message: Value) -> Option<String> {
        self.sent.set(self.sent.get() + 1);
        let id = format!("out-{}", self.sent.get());
        let mut pending = self.pending.borrow_mut();
        let chat = pending.get_mut(key).filter(|c| c.made.is_none())?;
        let mut entry = message;
        entry["id"] = json!(id);
        entry["after"] = json!(0);
        entry["createdAt"] = json!(self.host.now_ms().round() as i64);
        entry["state"] = json!(if chat.failed.is_some() { "failed" } else { "sending" });
        entry["error"] = json!(chat.failed);
        chat.queue.push(entry);
        drop(pending);
        self.pending_changed(key);
        Some(id)
    }

    /// Drops a message waiting for its chat to be made. A chat whose every message is dropped before it was made is
    /// given up (it answers true then).
    pub fn pending_discard(&self, key: &str, id: &str) -> bool {
        let mut pending = self.pending.borrow_mut();
        let Some(chat) = pending.get_mut(key).filter(|c| c.made.is_none()) else { return false };
        chat.queue.retain(|m| m["id"] != id);
        let gone = chat.queue.is_empty() && chat.failed.is_some();
        if gone {
            pending.remove(key);
        }
        drop(pending);
        self.pending_changed(key);
        gone
    }

    /// Whether it could not be made, the last time it was tried.
    pub fn pending_failed_now(&self, key: &str) -> bool {
        self.pending.borrow().get(key).is_some_and(|c| c.made.is_none() && c.failed.is_some())
    }

    /// It could not be made: its messages say why, and wait to be tried again.
    pub fn pending_failed(&self, key: &str, error: &str) {
        if let Some(chat) = self.pending.borrow_mut().get_mut(key).filter(|c| c.made.is_none()) {
            chat.failed = Some(error.to_string());
            for m in &mut chat.queue {
                m["state"] = json!("failed");
                m["error"] = json!(error);
            }
        }
        self.pending_changed(key);
    }

    /// Its station made it as `session`, `thread`: what waited in its queue goes to the chat's outbox, in order, and is
    /// answered (id, message) to be delivered.
    pub fn pending_made(&self, key: &str, session: &str, thread: u64) -> Vec<(String, Value)> {
        let (station, queue) = {
            let mut pending = self.pending.borrow_mut();
            let Some(chat) = pending.get_mut(key).filter(|c| c.made.is_none()) else { return Vec::new() };
            chat.made = Some((session.to_string(), thread));
            (chat.station.clone(), std::mem::take(&mut chat.queue))
        };
        let sends = queue.iter().map(|m| (m["id"].as_str().unwrap_or("").to_string(), sent_as(m))).collect();
        if !queue.is_empty() {
            self.outbox.borrow_mut().entry((station.clone(), thread)).or_default().extend(queue);
        }
        self.pending_changed(key);
        self.outbox_changed(&station, thread);
        sends
    }

    /// Its page and the sidebars show it anew.
    fn pending_changed(&self, key: &str) {
        let views: Vec<Topic> = self.views.borrow().keys().cloned().collect();
        for view in views {
            let shows = match &view {
                Topic::Chat { thread: None, session: Some(k), .. } => k == key,
                Topic::Chats { .. } | Topic::ChatSearch { .. } => true,
                _ => false,
            };
            if shows {
                self.store.invalidate(&view);
            }
        }
    }

    /// A pending chat's page: its station's chat once made and read, else what is known here.
    fn pending_chat(&self, station: &str, key: &str) -> Option<Result<Value>> {
        let (made, queue, failed) = {
            let pending = self.pending.borrow();
            let chat = pending.get(key)?;
            (chat.made.clone(), chat.queue.clone(), chat.failed.clone())
        };
        if let Some((session, thread)) = &made
            && let Some(Ok(mut view)) = self.chat(station, *thread)
        {
            view["key"] = json!(session);
            return Some(Ok(view));
        }
        let outbox = match &made {
            Some((_, thread)) => self.outbox.borrow().get(&(station.to_string(), *thread)).cloned().unwrap_or_default(),
            None => queue,
        };
        let scope = station.split_once('/').map_or(station, |(workspace, _)| workspace);
        let title = outbox.first().and_then(|m| m.get("text")).and_then(Value::as_str).map(str::trim).filter(|t| !t.is_empty())
            .and_then(|t| t.lines().map(str::trim).find(|l| !l.is_empty())).unwrap_or("新对话").to_string();
        Some(Ok(json!({
            "me": self.me(scope),
            "thread": null,
            "title": title,
            "people": [],
            "agents": [],
            "messages": [],
            "more": false,
            "outbox": outbox,
            "link": self.link(station),
            "offline": self.offline(station),
            // Not made yet (its messages wait for it); once it is, the key its station gave it.
            "pending": made.is_none(),
            "key": made.map(|(session, _)| session),
            "failed": failed,
        })))
    }

    /// The rows of the chats asked for here on a station that its rows do not have yet: each as the station would
    /// list it, under the key its station gave it once made. The station's row, once there, is the chat's: it covers
    /// the one from here (made, or not answered yet: its `clientKey` says so), with the title from here while it has
    /// no messages of its own.
    fn pending_rows(&self, station: &str, rows: &mut [Value]) -> Vec<Value> {
        let pending = self.pending.borrow();
        let mut out = Vec::new();
        for (key, chat) in pending.iter().filter(|(_, c)| c.station == station) {
            // Made, it has no queue: its first message is in the outbox until the station's rows come.
            let first = chat.queue.first().cloned().or_else(|| {
                let (_, thread) = chat.made.as_ref()?;
                self.outbox.borrow().get(&(station.to_string(), *thread))?.first().cloned()
            });
            let text = first.as_ref().and_then(|m| m.get("text")).and_then(Value::as_str).unwrap_or("").trim().to_string();
            let title = text.lines().map(str::trim).find(|l| !l.is_empty()).map(str::to_string);
            let id = |r: &Value| r.get("id").and_then(Value::as_str).map(str::to_string);
            // Its row at its station: by the key the station gave it, or, not answered yet, by the key given here.
            let theirs = rows.iter().position(|r| match &chat.made {
                Some((session, _)) => id(r).as_deref() == Some(session.as_str()),
                None => r.get("clientKey").and_then(Value::as_str) == Some(key.as_str()),
            });
            if let Some(i) = theirs {
                if chat.made.is_some() {
                    chat.listed.set(true);
                }
                if let Some(title) = &title
                    && rows[i].get("last").is_none_or(Value::is_null)
                {
                    rows[i]["title"] = json!(title);
                }
                continue;
            }
            // Listed once and gone from its station's rows (archived or removed there): not shown again from here.
            if chat.listed.get() {
                continue;
            }
            // Nothing sent to it yet, and not made: not a chat to list.
            if first.is_none() && chat.made.is_none() {
                continue;
            }
            let (id, thread) = match &chat.made {
                Some((session, thread)) => (session.clone(), json!(thread)),
                None => (key.clone(), Value::Null),
            };
            let mut row = json!({
                "id": id, "session": id, "thread": thread, "title": title.unwrap_or_else(|| "新对话".to_string()), "agents": [], "last": null,
                "unread": false, "mine": true, "lastActiveAt": chat.created_at.round() as i64, "connect": null, "origin": null,
                // As its station's row will say it: the list keeps it the same row from asked to made to listed.
                "clientKey": key,
            });
            if chat.made.is_none() {
                row["pending"] = json!(true);
            }
            out.push(row);
        }
        out
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
    /// emission). Nobody looking at the chat: it goes now, but for a chat asked for here, whose page is on its way to
    /// it (else that page opens with neither the message nor its entry, and says the chat is empty).
    pub fn outbox_sent(&self, station: &str, thread: u64, id: &str, seq: u64) {
        let made_here = self.pending.borrow().values().any(|c| c.station == station && c.made.as_ref().is_some_and(|(_, t)| *t == thread));
        if !made_here && self.chat_views(station, thread).is_empty() {
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
                Topic::Chat { station: s, thread: None, session: Some(key) } if key.starts_with(PENDING_PREFIX) => s == station && self.pending_thread(s, key) == Some(Some(thread)),
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
        self.again.borrow_mut().1.remove(view);
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
        // A chat's link, when not as it should be, in words (looks.rs).
        if let Topic::Chat { station, .. } = view {
            return self.chat_view(view).map(|value| value.map(|mut v| {
                if v.get("link").is_some_and(Value::is_object) {
                    v["connection"] = crate::looks::link_shown(&v["link"], &self.station_name(station));
                }
                v
            }));
        }
        self.chat_view(view)
    }

    /// A station's name as its workspace has it, else its id.
    pub(crate) fn station_name(&self, station: &str) -> String {
        let Some((scope, id)) = station.split_once('/') else { return String::new() };
        match self.stations(scope) {
            Some(Ok(stations)) => stations.into_iter().find(|s| s.address == station).map(|s| s.name).unwrap_or_else(|| id.to_string()),
            _ => id.to_string(),
        }
    }

    fn chat_view(&self, view: &Topic) -> Option<Result<Value>> {
        match view {
            Topic::Chats { scope, mine } => self.chats(scope, *mine),
            Topic::ChatSearch { scope, query, station, exclude, limit } => {
                self.chats(scope, false).map(|chats| chats.map(|c| crate::refs::search(&c, query, station.as_deref(), exclude.as_deref(), *limit)))
            }
            Topic::Stations { scope } => self.stations_view(scope),
            Topic::Connects { scope, mine } => self.connects(scope, *mine),
            Topic::Chat { station, thread: Some(thread), .. } => self.chat(station, *thread),
            Topic::Chat { station, thread: None, session: Some(key) } if key.starts_with(PENDING_PREFIX) => {
                self.pending_chat(station, key).or_else(|| Some(Err(CoreError::new("http_404", "没有这个对话").with_status(404))))
            }
            // An item's page by its agent: its chat once it has one (made here or elsewhere), else the agent alone.
            Topic::Chat { station, thread: None, session: Some(key) } => match self.bound_thread(station, key) {
                Some(thread) => self.chat(station, thread),
                None => self.unchatted(station, key),
            },
            Topic::Chat { .. } => Some(Err(CoreError::invalid("chat 要有 thread 或 session"))),
            Topic::History { station, key } => self.history(station, key),
            Topic::Archive { scope } => self.archive(scope),
            Topic::ChatJobs { station, thread, session } => {
                let chat = Topic::Chat { station: station.clone(), thread: *thread, session: session.clone() };
                Some(self.store.value(&chat)?.map(|chat| {
                    let (jobs, next) = crate::jobs::chat_jobs(&chat, self.clock());
                    self.again_in(view, next);
                    jobs
                }))
            }
            Topic::LongJobs { scope } => {
                let stations = match self.stations(scope)? {
                    Ok(stations) => stations,
                    Err(error) => return Some(Err(error)),
                };
                // A station down, or too old to know the list, has none to show.
                let several = stations.len() > 1;
                let open: Vec<(String, Option<String>, Vec<Value>)> = stations.iter().filter(|s| s.online).map(|s| {
                    let jobs = self.ok(Topic::Jobs { station: s.address.clone() }).and_then(|j| j.as_array().cloned()).unwrap_or_default();
                    (s.address.clone(), several.then(|| s.name.clone()), jobs)
                }).collect();
                Some(Ok(crate::jobs::long_jobs(&open, self.clock())))
            }
            _ => None,
        }
    }

    /// Has a view computed again in `ms` (the timer set last is the one that counts).
    fn again_in(&self, view: &Topic, ms: f64) {
        let mut again = self.again.borrow_mut();
        if !ms.is_finite() {
            again.1.remove(view);
            return;
        }
        again.0 += 1;
        let run = again.0;
        again.1.insert(view.clone(), run);
        let (sleep, store, again, view) = (self.host.sleep(ms.ceil() as u64), Rc::downgrade(&self.store), Rc::downgrade(&self.again), view.clone());
        self.host.spawn(Box::pin(async move {
            sleep.await;
            let Some(again) = again.upgrade() else { return };
            if again.borrow().1.get(&view) == Some(&run) {
                again.borrow_mut().1.remove(&view);
                invalidate(&store, &view);
            }
        }));
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
            Topic::Chats { scope, .. } | Topic::ChatSearch { scope, .. } => (scope.as_str(), |station| vec![Topic::ChatRows { station: station.clone() }, Topic::Overview { station: station.clone() }, Topic::Link { station }]),
            Topic::Stations { scope } => (scope.as_str(), |station| vec![Topic::Link { station: station.clone() }, Topic::Overview { station: station.clone() }, Topic::Host { station: station.clone() }, Topic::Net { station }]),
            Topic::Archive { scope } => (scope.as_str(), |station| vec![Topic::ArchivedRows { station }]),
            Topic::LongJobs { scope } => (scope.as_str(), |station| vec![Topic::Jobs { station }]),
            // A chat's jobs are its agents', as its view has them.
            Topic::ChatJobs { station, thread, session } => {
                topics.insert(Topic::Chat { station: station.clone(), thread: *thread, session: session.clone() });
                return topics;
            }
            // Its sessions (the recent ones, the one it delivers into) and the chats they were last talked to in.
            Topic::Connects { scope, .. } => (scope.as_str(), |station| vec![Topic::Overview { station: station.clone() }, Topic::Sessions { station: station.clone() }, Topic::Threads { station }]),
            Topic::Chat { station, thread: None, session: Some(key) } if key.starts_with(PENDING_PREFIX) => {
                // Asked for here: the chat its station made, once it has; else whether the station is up.
                if let Some(Some(thread)) = self.pending_thread(station, key) {
                    return self.sources(&Topic::Chat { station: station.clone(), thread: Some(thread), session: None });
                }
                topics.insert(Topic::Link { station: station.clone() });
                if let Some((scope, _)) = station.split_once('/') {
                    topics.insert(Topic::Workspace { workspace: scope.to_string() });
                }
                return topics;
            }
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
        if let Topic::Chats { .. } = view {
            topics.insert(Topic::Prefs);
        }
        topics.insert(Topic::Workspace { workspace: scope.to_string() });
        // Whether the account is in the beta (`betaOffered`): its `/v1/me`, which the accounts' list follows.
        if let Topic::Stations { .. } = view {
            topics.insert(Topic::Workspaces);
        }
        if let Some(Ok(stations)) = self.stations(scope) {
            for s in stations {
                // Whether it is up is watched for every one (a station found down comes back); what else it has, for
                // the ones up.
                topics.insert(Topic::Link { station: s.address.clone() });
                if s.online {
                    topics.extend(per_station(s.address));
                }
            }
        }
        topics
    }

    /// The scope's stations; `None` until the workspace has been read.
    fn stations(&self, scope: &str) -> Option<Result<Vec<StationInfo>>> {
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

    /// Who is looking: the account that reaches the workspace.
    fn me(&self, scope: &str) -> Value {
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
        let members: Vec<Value> = self.ok(Topic::Workspace { workspace: scope.to_string() }).and_then(|w| w.get("members").and_then(Value::as_array).cloned()).unwrap_or_default();
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
                let mut listed = list.as_array().cloned().unwrap_or_default();
                let asked = self.pending_rows(&s.address, &mut listed);
                for row in asked.iter().chain(listed.iter()) {
                    if mine && row.get("mine").and_then(Value::as_bool) != Some(true) {
                        continue;
                    }
                    // On its way into the archive from here (archive.rs).
                    if self.being_archived(&s.address, row) {
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
                    // Who is in it, for its pictures: who started it first, then everyone who wrote in it, each once.
                    crate::present::row_people(&mut row, &me, &slack_users, &members);
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
        // One says itself; several are counted, marked by the worst. No retry beside it (`retry` false for clients that
        // read it): a station may stay down for long, and trying one again is done from the stations' page.
        let trouble = match troubles.as_slice() {
            [] => Value::Null,
            [(state, text)] => json!({ "text": text, "state": state, "retry": false }),
            all => {
                let worst = ["error", "offline", "reconnecting"].into_iter().find(|w| all.iter().any(|(s, _)| s == w)).unwrap_or("offline");
                json!({ "text": format!("{} 台 station 异常", all.len()), "state": worst, "retry": false })
            }
        };
        // The glyph, and what the list says with no rows (looks.rs).
        let glyph = crate::looks::glyph(&states, &days);
        let note = crate::looks::list_note(&states, &days, loading);
        // How many people the scope has: its members, once known.
        let members = self.ok(Topic::Workspace { workspace: scope.to_string() }).and_then(|w| w.get("members").and_then(Value::as_array).map(Vec::len));
        // Whose pictures lead: always the agents, the people after them (the 侧栏头像 setting is gone; clients from before
        // it read this).
        let leading = "agents";
        Some(Ok(json!({ "me": me, "stations": states, "loading": loading, "days": days, "trouble": trouble, "members": members, "leading": leading, "glyph": glyph, "note": note })))
    }

    /// Rows newest first, grouped by the viewer's local calendar day; those the viewer pinned above them all, in a group
    /// of their own (`pinned`, `daysAgo` -1), the latest pinned first. Each row says whether it is pinned (`pinned`),
    /// when its station knows pins.
    fn days(&self, rows: Vec<Value>) -> Vec<Value> {
        let at = |row: &Value| row["lastActiveAt"].as_f64().unwrap_or(0.0);
        let (mut pinned, mut rows): (Vec<Value>, Vec<Value>) = rows.into_iter().partition(|row| row.get("pinned").is_some_and(Value::is_number));
        let pinned_at = |row: &Value| row["pinned"].as_f64().unwrap_or(0.0);
        pinned.sort_by(|a, b| pinned_at(b).total_cmp(&pinned_at(a)).then(at(b).total_cmp(&at(a))));
        for row in &mut pinned {
            row["pinned"] = json!(true);
        }
        for row in rows.iter_mut().filter(|row| row.get("pinned").is_some()) {
            row["pinned"] = json!(false);
        }
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
        let top = (!pinned.is_empty()).then(|| {
            json!({ "daysAgo": -1, "at": pinned.first().map(at).unwrap_or(0.0), "label": "已固定", "pinned": true, "items": pinned })
        });
        top.into_iter()
            .chain(days.into_iter().map(|(d, t, items)| json!({ "daysAgo": today - d, "at": t, "label": crate::format::day_label(t, now, offset), "items": items })))
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
                "face": crate::looks::face(s.online, overview.as_ref()), "line": crate::looks::station_line(s.online, host.as_ref()),
                "online": s.online, "lastSeen": s.last_seen, "version": s.version,
                "link": self.link(&s.address),
                "runtimes": runtimes(overview.as_ref()),
                "models": models(overview.as_ref(), self.host.now_ms()),
                "overview": shown, "host": host,
                "net": read(Topic::Net { station: s.address.clone() }).as_ref().and_then(|raw| crate::present::net(raw, &*self.relay_name)),
                "betaOffered": beta_offered(overview.as_ref(), || (self.beta_of)(scope)),
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
        let members: Vec<Value> = self.ok(Topic::Workspace { workspace: scope.to_string() }).and_then(|w| w.get("members").and_then(Value::as_array).cloned()).unwrap_or_default();
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
                        // Who added it is an email, or "local" (one added on a station's own page, before it went).
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

    /// Whether a station is offline, as its workspace says: its chats are read
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
        let members: Vec<Value> = self.ok(Topic::Workspace { workspace: scope.to_string() }).and_then(|w| w.get("members").and_then(Value::as_array).cloned()).unwrap_or_default();
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
                "ember" => json!({ "name": "still.fail" }),
                _ => {
                    let member = members.iter().find(|x| x.get("email").and_then(Value::as_str).is_some_and(|e| e.eq_ignore_ascii_case(&author)));
                    let name = crate::present::member_name(&members, &author).map(str::to_string).or(said_name)
                        // "local": written on a station's own page, in chats from before it went.
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
        // Its item in the sidebar, as the station has it for the viewer (as kept, until read).
        let row = self.store.value(&Topic::ChatRows { station: station.to_string() }).and_then(Result::ok)
            .and_then(|rows| rows.as_array()?.iter().find(|r| r.get("thread").and_then(Value::as_u64) == Some(id)).cloned());
        Some(Ok(json!({
            "me": self.me(scope),
            "place": place,
            "slackUrl": slack_url,
            // The same title the sidebar shows: the station's for its item, while it has one.
            "title": row.as_ref().and_then(|r| r.get("title").cloned())
                .or_else(|| page.get("title").filter(|t| t.is_string()).cloned())
                .unwrap_or_else(|| json!(chat_title(&thread))),
            "people": people,
            "agents": agents,
            "messages": messages,
            // Entries before those loaded (the thread counts from 1).
            "more": page.get("first").and_then(Value::as_u64).is_some_and(|first| first > 1),
            // Up to where its messages were caught up on rather than said while it was open (station.rs thread_value).
            "caught": page.get("caught").cloned().unwrap_or(Value::Null),
            "outbox": outbox,
            "link": self.link(station),
            "offline": self.offline(station),
            "thread": thread,
            "archived": thread.get("hiddenAt").is_some_and(|at| !at.is_null()),
        })).map(|mut view| {
            // Pinned to the top of the viewer's list; absent when its station does not know pins.
            if let Some(pinned) = row.as_ref().and_then(|r| r.get("pinned")) {
                view["pinned"] = json!(pinned.is_number());
            }
            view
        }))
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
        // Every Slack workspace a connect of the station is in: its name as last seen, its address while signed in.
        let mut workspaces = std::collections::HashMap::new();
        for c in overview.as_ref().and_then(|o| o.get("connects")).and_then(Value::as_array).into_iter().flatten() {
            let seen = c.get("connection").filter(|conn| matches!(conn.get("state").and_then(Value::as_str), Some("connected" | "reconnecting"))).and_then(|conn| conn.get("workspace"));
            let Some(team) = seen.and_then(|w| w.get("teamId")).and_then(Value::as_str) else { continue };
            let name = seen.and_then(|w| w.get("team")).and_then(Value::as_str).or_else(|| c.get("team").and_then(Value::as_str)).unwrap_or("");
            let url = seen.and_then(|w| w.get("url")).and_then(Value::as_str).filter(|u| !u.is_empty()).map(str::to_string);
            workspaces.entry(team.to_string()).or_insert(crate::format::SlackWorkspace { name: name.to_string(), url });
        }
        let now = self.host.now_ms();
        let cx = crate::history::Context {
            workspaces: &workspaces,
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
    pub fn agent(&self, station: &str, key: &str) -> Option<Value> {
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
            // While it waits on work it started: since when, and for how long at most.
            "wait": crate::present::waiting(&session),
            "turns": detail.get("turns").cloned().unwrap_or_else(|| json!([])),
            "threads": detail.get("threads").cloned().unwrap_or_else(|| json!([])),
            // Its background jobs and web services (a station yet to update says none).
            "jobs": detail.get("jobs").cloned().unwrap_or_else(|| json!([])),
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
            "archived": agent["session"].get("archivedAt").is_some_and(|at| !at.is_null()),
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
/// What an outbox entry sends to its station: its words, files and quotes, and the app it was sent from if said.
pub fn sent_as(entry: &Value) -> Value {
    let mut message = json!({ "text": entry["text"], "attachments": entry["attachments"], "quotes": entry["quotes"] });
    if let Some(client) = entry.get("client").filter(|c| c.is_string()) {
        message["client"] = client.clone();
    }
    message
}

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
    let mut by_key: BTreeMap<String, BTreeSet<&str>> = BTreeMap::new();
    for p in overview.and_then(|o| o.get("profiles")).and_then(Value::as_array).into_iter().flatten()
        .filter(|p| p.get("runtimes").and_then(Value::as_array).is_some_and(|r| r.iter().any(|r| r.as_str() == Some(runtime))))
    {
        for model in p.get("models").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str) {
            by_key.entry(stillfail_shapes::model::key(model)).or_default().insert(model);
        }
    }
    let mut by_key: Vec<(String, BTreeSet<&str>)> = by_key.into_iter().collect();
    by_key.sort_by_cached_key(|(key, _)| stillfail_shapes::model::order(key));
    Value::Array(by_key.into_iter()
        .map(|(key, ids)| {
            let (model, ids) = spellings(&key, ids);
            json!({
                "model": model, "name": stillfail_shapes::model::name(model), "family": stillfail_shapes::model::family(model), "ids": ids,
                "maker": crate::present::maker(Some(model)), "runtimes": [runtime],
                "efforts": { runtime: crate::format::efforts(runtime) },
                "accounts": { runtime: profiles_running(overview, runtime, Some(model), current, now) },
            })
        })
        .collect())
}

/// A model's spellings, the one it sends first: the one that is its key when a profile has it, else the first.
fn spellings<'a>(key: &str, ids: BTreeSet<&'a str>) -> (&'a str, Vec<&'a str>) {
    let mut ids: Vec<&str> = ids.into_iter().collect();
    ids.sort_by_key(|id| *id != key);
    (ids[0], ids)
}

fn profiles_running(overview: Option<&Value>, runtime: &str, model: Option<&str>, current: Option<&str>, now: f64) -> Value {
    Value::Array(overview.and_then(|o| o.get("profiles")).and_then(Value::as_array).into_iter().flatten()
        .filter(|p| p.get("runtimes").and_then(Value::as_array).is_some_and(|r| r.iter().any(|r| r.as_str() == Some(runtime))))
        // With a model chosen, only those that have it enabled can run it.
        .filter(|p| model.is_none_or(|m| p.get("models").and_then(Value::as_array).is_some_and(|ms| ms.iter().filter_map(Value::as_str).any(|x| stillfail_shapes::model::same(x, m)))))
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
                "quotaLine": crate::choose::quota_line(p.get("quota")),
            })
        })
        .collect())
}

/// The models the station can run, each with the runtimes it runs on (those of the profiles that have it enabled):
/// a model is chosen first, and a runtime only when it has more than one.
pub fn models(overview: Option<&Value>, now: f64) -> Value {
    // One model however its profiles spell it (openai/gpt-6-astra, gpt-6-astra).
    let mut on: BTreeMap<String, (BTreeSet<&str>, Vec<Option<f64>>, BTreeSet<&str>)> = BTreeMap::new();
    for p in overview.and_then(|o| o.get("profiles")).and_then(Value::as_array).into_iter().flatten() {
        let runtimes: Vec<&str> = p.get("runtimes").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str).collect();
        let back = spent_until(p);
        let mut keys = BTreeSet::new();
        for model in p.get("models").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str) {
            let key = stillfail_shapes::model::key(model);
            let entry = on.entry(key.clone()).or_default();
            entry.0.extend(runtimes.iter().copied());
            entry.2.insert(model);
            // A profile counts once for a model it has in two spellings.
            if keys.insert(key) {
                entry.1.push(back);
            }
        }
    }
    // Claude Code first where both run it: it is the one most chats use.
    let order = |r: &&str| RUNTIMES.iter().position(|x| x == r).unwrap_or(usize::MAX);
    // By series, newest first (stillfail_shapes::model::order).
    let mut on: Vec<_> = on.into_iter().collect();
    on.sort_by_cached_key(|(key, _)| stillfail_shapes::model::order(key));
    Value::Array(on.into_iter().map(|(key, (runtimes, backs, ids))| {
        let (model, ids) = spellings(&key, ids);
        let mut runtimes: Vec<&str> = runtimes.into_iter().collect();
        runtimes.sort_by_key(order);
        // Spent when every account that runs it has a window used up; back when the first of them refills.
        let spent = backs.iter().all(Option::is_some).then(|| backs.iter().flatten().copied().fold(f64::INFINITY, f64::min));
        // For each runtime: how hard it can think, and who can run it there.
        let efforts: serde_json::Map<String, Value> = runtimes.iter().map(|r| (r.to_string(), json!(crate::format::efforts(r)))).collect();
        let accounts: serde_json::Map<String, Value> = runtimes.iter().map(|r| (r.to_string(), profiles_running(overview, r, Some(model), None, now))).collect();
        json!({
            "model": model, "name": stillfail_shapes::model::name(model), "family": stillfail_shapes::model::family(model), "ids": ids,
            "runtimes": runtimes, "maker": crate::present::maker(Some(model)),
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
        /// Whether the account that reaches "ws" is in the beta.
        beta: Rc<Cell<bool>>,
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
        let beta = Rc::new(Cell::new(false));
        let email_of: EmailOf = Rc::new(|ws: &str| (ws == "ws").then(|| "Me@x.com".to_string()));
        *router.views.borrow_mut() = Some(Views::new(host.clone(), store.clone(), email_of, Rc::new(|_: &str| None), {
            let beta = beta.clone();
            Rc::new(move |ws: &str| ws == "ws" && beta.get())
        }));
        store.set_source(router.clone());
        Setup { beta, host, store, router }
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
            self.read_all(&mut [(ui, id)]).await;
        }

        /// The same for several subscriptions at once.
        async fn read_all(&self, uis: &mut [(&mut Ui, RequestId)]) {
            self.host.settle().await;
            for (_, message) in self.host.take_emitted() {
                let at = match &message {
                    CoreMessage::Value { id, .. } | CoreMessage::Delta { id, .. } | CoreMessage::Error { id, .. } | CoreMessage::Ok { id, .. } => *id,
                };
                if let CoreMessage::Error { error, .. } = &message && error.code == "shape" {
                    panic!("{}", error.message);
                }
                let Some((ui, id)) = uis.iter_mut().find(|(_, id)| *id == at) else { continue };
                let (ui, id) = (&mut **ui, *id);
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

    /// The workspace's three stations: `a` and `b` seen by still.fail cloud a while ago, `c` never. Whether each is up is
    /// the device's own finding: their `link` topics.
    fn stations(now_s: f64) -> Value {
        json!({"id": "ws", "stations": [
            {"id": "a", "name": "alpha", "last_seen": now_s as i64 - 10, "version": "0.4.0"},
            {"id": "b", "name": "beta", "last_seen": now_s as i64 - 1000, "version": null},
            {"id": "c", "name": "gamma", "last_seen": null, "version": null},
        ]})
    }

    /// A workspace with one station, `st`.
    fn one_station() -> Value {
        json!({"id": "ws", "stations": [{"id": "st", "name": "studio", "last_seen": null, "version": null}]})
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
            "slackApps": [], "disk": null, "logins": [],
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
            {"id": "a", "name": "A", "current": true, "spent": null, "kind": null, "runtime": null, "quota": null, "quotaLine": null},
            {"id": "b", "name": "B", "current": false, "spent": {"until": 9000.0, "text": "额度用完 · 1 分钟内恢复", "back": "1 分钟内恢复"}, "kind": null, "runtime": null, "quota": {"state": "ok", "windows": [{"usedPercent": 100, "resetsAt": 9000}]}, "quotaLine": {"text": "只剩 0%", "level": "red"}},
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
            assert_eq!(sorted(t.started()), sorted(vec![workspace(), Topic::Prefs]), "the workspace, and the device's prefs (whose pictures lead)");
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
            // No rows yet: the list says it is reading; the glyph has the three dim (looks.rs).
            assert_eq!(v["note"], json!({"reading": true, "failing": [], "empty": false}));
            assert_eq!((v["glyph"]["dim"].as_u64(), v["glyph"]["online"].as_u64(), v["glyph"]["summary"].as_str()), (Some(3), Some(0), Some("3 台 station")));
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
            assert_eq!(v["glyph"]["label"], "3 台 station，1 台在线，2 台离线");
            assert_eq!(v["note"]["reading"], false);
            // Under the list, what is wrong: beta and gamma offline, counted.
            assert_eq!(v["trouble"], json!({"text": "2 台 station 异常", "state": "offline", "retry": false}));
            // Each of its rows says so itself; the online station's say nothing.
            let items = &v["days"][0]["items"];
            assert_eq!((items[0]["offline"].clone(), items[1]["offline"].clone()), (Value::Null, json!("beta 离线")));
            t.set(link("ws/b"), json!({"state": "online"}));
            t.read(&mut ui, 1).await;
            // One wrong station says itself.
            assert_eq!(ui.value.as_ref().unwrap()["trouble"], json!({"text": "gamma 离线", "state": "offline", "retry": false}));

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
            assert_eq!(v["trouble"], json!({"text": "2 台 station 异常", "state": "offline", "retry": false}));
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
            t.subscribe(1, Topic::Chats { scope: "ws".into(), mine: false });
            t.set(workspace(), one_station());
            t.host.settle().await;
            t.set(rows("ws/st"), json!([
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
            assert_eq!(v["me"], json!({"id": "Me@x.com", "email": "Me@x.com"}));
            assert_eq!(v["stations"], json!([{"station": "ws/st", "id": "st", "name": "studio", "state": "online"}]));
        });
    }

    #[test]
    fn pinned_rows_go_above_the_days_the_latest_pinned_first() {
        run(async {
            let t = setup();
            let now = t.host.now_ms();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Chats { scope: "ws".into(), mine: false });
            t.set(workspace(), one_station());
            t.host.settle().await;
            let pinned = |id: &str, at: f64, pinned: Value| {
                let mut r = row(id, at);
                r["pinned"] = pinned;
                r
            };
            t.set(rows("ws/st"), json!([
                pinned("1", now, Value::Null),
                pinned("2", now - 3.0 * DAY_MS, json!(5)),
                pinned("3", now - 1000.0, json!(9)),
                row("4", now - 2000.0),
            ]));
            t.read(&mut ui, 1).await;
            let v = ui.value.unwrap();
            assert_eq!((&v["days"][0]["label"], &v["days"][0]["daysAgo"], &v["days"][0]["pinned"]), (&json!("已固定"), &json!(-1), &json!(true)));
            assert_eq!(ids(&v), ["3", "2", "1", "4"], "pinned ones on top, the latest pinned first; the rest by when");
            let flags: Vec<Value> = v["days"].as_array().unwrap().iter().flat_map(|d| d["items"].as_array().unwrap().iter().map(|i| i.get("pinned").cloned().unwrap_or(json!("absent")))).collect();
            assert_eq!(flags, [json!(true), json!(true), json!(false), json!("absent")], "a row from a station without pins says nothing");
            assert_eq!(v["days"][1].get("pinned"), None);
        });
    }

    #[test]
    fn the_rows_are_led_by_the_agents_whatever_was_set() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Chats { scope: "ws".into(), mine: false });
            t.set(workspace(), one_station());
            t.host.settle().await;
            t.set(rows("ws/st"), json!([]));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.as_ref().unwrap()["leading"], "agents");
            // What a device set before the setting went changes nothing.
            t.set(Topic::Prefs, json!({ "rowPicture": "people" }));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.as_ref().unwrap()["leading"], "agents");
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
            t.subscribe(1, Topic::Chats { scope: "ws".into(), mine: false });
            t.set(workspace(), one_station());
            t.host.settle().await;
            let now = t.host.now_ms();
            // The station says what a row is called and whether it is unread; the view shows it as it is.
            let mut named = row("1", now - 1.0);
            named["title"] = json!("排查");
            named["unread"] = json!(true);
            named["last"] = json!({"seq": 7, "authorKind": "agent", "author": "a", "authorName": null, "text": "好的", "createdAt": now as i64 - 1});
            let mut said = row("2", now - 2.0);
            said["title"] = json!("看看 这个");
            t.set(rows("ws/st"), json!([named, said]));
            t.read(&mut ui, 1).await;
            let rows_of = |ui: &Ui| -> Vec<(String, String, bool)> {
                ui.value.as_ref().unwrap()["days"][0]["items"].as_array().unwrap().iter()
                    .map(|i| (i["id"].as_str().unwrap().to_string(), i["title"].as_str().unwrap().to_string(), i["unread"].as_bool().unwrap()))
                    .collect()
            };
            assert_eq!(rows_of(&ui), vec![("1".into(), "排查".into(), true), ("2".into(), "看看 这个".into(), false)]);
            // Read: the mark follows the station's rows.
            t.store.update(&rows("ws/st"), &mut |list| list[0]["unread"] = json!(false));
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
            let each = |st: &str| vec![link(st), overview(st), host_of(st), Topic::Net { station: st.into() }];
            let watched = sorted([vec![workspace(), Topic::Workspaces], each("ws/a"), each("ws/b"), each("ws/c")].concat());
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
                // gpt-5 through a router: the same model, its week used up too.
                profile("p6", json!({"runtimes": ["codex"], "models": ["openai/gpt-5"], "quota": {"state": "ok", "detail": null, "checkedAt": 1, "windows": [{"label": "每周", "usedPercent": 100, "resetsAt": 6000}]}})),
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
            assert_eq!(ids, ["p1", "p2", "p3", "p4", "p5", "p6"]);
            assert_eq!(v[0]["host"]["hostname"], "studio");
            assert_eq!(v[0]["runtimes"], json!([{"runtime": "claude", "models": ["deepseek-flash", "opus", "sonnet"]}, {"runtime": "codex", "models": ["deepseek-flash", "gpt-5", "o3", "openai/gpt-5"]}]));
            // An account run on both offers its model on both: a runtime is chosen for it.
            let models: Vec<Value> = v[0]["models"].as_array().unwrap().iter().map(|m| json!({"model": m["model"], "runtimes": m["runtimes"], "spent": m["spent"]["until"]})).collect();
            // By series (Claude's biggest first, the rest by name), newest first.
            assert_eq!(models, vec![
                json!({"model": "opus", "runtimes": ["claude"], "spent": null}), json!({"model": "sonnet", "runtimes": ["claude"], "spent": null}),
                json!({"model": "deepseek-flash", "runtimes": ["claude", "codex"], "spent": null}), json!({"model": "gpt-5", "runtimes": ["codex"], "spent": 5000.0}),
                json!({"model": "o3", "runtimes": ["codex"], "spent": 5000.0}),
            ]);
            // Each with its maker, how hard each runtime can think, who runs it there, and a used-up quota in words.
            let gpt = &v[0]["models"][3];
            assert_eq!(gpt["family"], "GPT");
            assert_eq!((gpt["maker"]["id"].as_str(), gpt["efforts"]["codex"][0].as_str(), gpt["accounts"]["codex"][0]["id"].as_str()), (Some("openai"), Some("minimal"), Some("p1")));
            assert!(gpt["spent"]["text"].as_str().unwrap().starts_with("额度用完 · "));
            // One model however it is spelled: named, with its spellings, run by the accounts of each.
            assert_eq!((gpt["name"].as_str(), gpt["ids"].clone()), (Some("GPT-5"), json!(["gpt-5", "openai/gpt-5"])));
            let runs: Vec<&str> = gpt["accounts"]["codex"].as_array().unwrap().iter().filter_map(|a| a["id"].as_str()).collect();
            assert_eq!(runs, ["p1", "p6"]);
            // Offline: what it was, and since when.
            assert_eq!(
                plain(&v[1]),
                json!({"station": "ws/b", "id": "b", "name": "beta", "online": false, "lastSeen": v[1]["lastSeen"],
                    "link": {"state": "offline"}, "runtimes": [], "models": [], "betaOffered": false})
            );
            assert!(v[1]["summary"].as_str().unwrap().starts_with("离线 · "));
            assert!(v[2].get("lastSeen").is_none());
        });
    }

    #[test]
    fn the_beta_switch_is_offered_to_an_account_in_the_beta_or_a_station_on_it() {
        let with = |channel: Option<&str>| json!({ "updates": [{ "id": "claude" }, { "id": "station", "channel": channel }] });
        // A station older than channels, or one that cannot be updated from here: never.
        assert!(!beta_offered(None, || true));
        assert!(!beta_offered(Some(&json!({})), || true));
        assert!(!beta_offered(Some(&with(None)), || true));
        // On the stable channel: only to an account in the beta.
        assert!(!beta_offered(Some(&with(Some("stable"))), || false));
        assert!(beta_offered(Some(&with(Some("stable"))), || true));
        // On the beta: to anyone, to be switched back.
        assert!(beta_offered(Some(&with(Some("beta"))), || false));
    }

    #[test]
    fn the_beta_switch_follows_the_accounts_beta_at_once() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, Topic::Stations { scope: "ws".into() });
            t.set(workspace(), stations(t.now_s()));
            t.read(&mut ui, 1).await;
            let mut o = overview_of(vec![], vec![]);
            o["updates"] = json!([{ "id": "station", "name": "still.fail station", "installed": true, "version": "0.1.1", "newer": false, "updatable": true, "state": "idle", "channel": "stable" }]);
            t.set(overview("ws/a"), o);
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.as_ref().unwrap()[0]["betaOffered"], false);
            // Let into the beta: the accounts' list read again, and the switch is offered.
            t.beta.set(true);
            t.set(Topic::Workspaces, json!([]));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.as_ref().unwrap()[0]["betaOffered"], true);
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
            let each = |st: &str| vec![link(st), overview(st), sessions(st), threads(st)];
            assert_eq!(sorted(t.started()), sorted([vec![workspace()], each("ws/a"), each("ws/b"), each("ws/c")].concat()));
            // gamma is not reached: nothing is waited for from it.
            t.set(link("ws/c"), json!({"state": "offline"}));
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
            t.subscribe(1, Topic::Chats { scope: "ws".into(), mine: false });
            t.set(workspace(), one_station());
            t.host.settle().await;
            t.read(&mut ui, 1).await;
            // One clock, set for a second past the next minute (and again each minute), shared by everything shown.
            let clock = |ms: &u64| *ms > 1000 && *ms <= 61_000 && *ms != EVICT_AFTER_MS;
            let count = || t.host.sleeps.borrow().iter().filter(|ms| clock(ms)).count();
            let before = count();
            assert!(before >= 1, "{:?}", t.host.sleeps.borrow());
            t.subscribe(2, Topic::Chats { scope: "ws".into(), mine: true });
            assert_eq!(count(), before, "a second view shares it");
        });
    }

    /// A value without what the clients show of it (present.rs): what a view puts together, alone.
    fn plain(v: &Value) -> Value {
        const SHOWN: [&str; 39] = ["face", "line", "available", "offered", "connection", "glyph", "note", "time", "statusText", "tone", "badgeText", "titleText", "agentText", "maker", "runtimeText", "processText", "efforts", "modeText", "modeShort", "runText", "presence", "checkText", "checkTone", "preview", "makers", "mark", "order", "left", "level", "refills", "shown", "processesText", "by", "waiting", "since", "originText", "mark", "summary", "modelsText"];
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
    fn an_open_chat_tracks_archive_and_restore_without_losing_messages() {
        run(async {
            let t = setup();
            let mut ui = Ui::default();
            t.subscribe(1, chat_topic("ws/a", 7));
            t.read(&mut ui, 1).await;
            let mut chat = thread(7, &["k"], t.host.now_ms());
            t.set(page_of("ws/a", 7), page(1, &["kept message"], chat.clone()));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.as_ref().unwrap()["archived"], false);
            for hidden in [json!(42), Value::Null] {
                chat["hiddenAt"] = hidden.clone();
                t.set(threads("ws/a"), json!([chat.clone()]));
                t.read(&mut ui, 1).await;
                let v = ui.value.as_ref().unwrap();
                assert_eq!(v["archived"], !hidden.is_null());
                assert_eq!(v["messages"][0]["text"], "kept message");
            }
            // Compression alone does not mean a shared chat was hidden from its users.
            chat["archivedAt"] = json!(42);
            t.set(threads("ws/a"), json!([chat]));
            t.read(&mut ui, 1).await;
            assert_eq!(ui.value.as_ref().unwrap()["archived"], false);
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
            t.subscribe(1, chat_topic("ws/st", 3));
            t.set(workspace(), one_station());
            t.host.settle().await;
            let mut slack = thread(3, &["k"], t.host.now_ms());
            slack["surface"] = json!("slack:T1");
            slack["channel"] = json!("C1");
            slack["channelName"] = json!("ops");
            slack["firstText"] = json!("<@U0BOT> 部署挂了");
            slack["sessions"] = json!([member(3, "k", "c1")]);
            t.set(threads("ws/st"), json!([slack]));
            t.set(page_of("ws/st", 3), page(1, &["<@U0BOT> 部署挂了", "在看"], Value::Null));
            t.read(&mut ui, 1).await;
            t.set(session_of("ws/st", "k"), json!({"session": full_session("k", json!({})), "threads": [], "turns": []}));
            t.read(&mut ui, 1).await;
            let v = ui.value.unwrap();
            assert_eq!(v["title"], "部署挂了");
            assert_eq!(v["thread"]["surface"], "slack:T1");
            assert_eq!(v["messages"].as_array().unwrap().len(), 2);
            assert_eq!(v["me"], json!({"id": "Me@x.com", "email": "Me@x.com"}));
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
            for archived in [json!(42), Value::Null] {
                t.set(session_of("ws/a", "k"), json!({"session": full_session("k", json!({"archivedAt": archived.clone()})), "threads": [], "turns": []}));
                t.read(&mut ui, 1).await;
                assert_eq!(ui.value.as_ref().unwrap()["archived"], !archived.is_null());
            }
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
    fn a_chat_asked_for_here_shows_at_once_and_becomes_its_stations_under_the_same_key() {
        run(async {
            let t = setup();
            let views = t.router.views();
            let key = views.pending_new("ws/st", json!({"runtime": "claude"}));
            let (mut screen, mut list) = (Ui::default(), Ui::default());
            t.subscribe(1, agent_page("ws/st", &key));
            t.set(workspace(), one_station());
            t.host.settle().await;
            t.subscribe(2, Topic::Chats { scope: "ws".into(), mine: true });
            t.set(rows("ws/st"), json!([row("7", t.host.now_ms() - 1000.0)]));
            t.read_all(&mut [(&mut screen, 1), (&mut list, 2)]).await;
            let v = screen.value.clone().unwrap();
            assert_eq!((v["pending"].clone(), v["key"].clone(), v["outbox"].clone(), v["title"].clone()), (json!(true), Value::Null, json!([]), json!("新对话")));
            // Nothing sent to it yet: not a row.
            assert_eq!(list.value.clone().unwrap()["days"].as_array().map(Vec::len), Some(0));

            let first = views.pending_queue(&key, json!({"text": "修一下登录\n细节…", "attachments": [], "quotes": []})).unwrap();
            t.read_all(&mut [(&mut screen, 1), (&mut list, 2)]).await;
            let v = screen.value.clone().unwrap();
            assert_eq!((v["title"].as_str(), v["outbox"][0]["id"].as_str(), v["outbox"][0]["state"].as_str()), (Some("修一下登录"), Some(first.as_str()), Some("sending")));
            let items = list.value.clone().unwrap()["days"][0]["items"].clone();
            assert_eq!((items[0]["id"].as_str(), items[0]["pending"].as_bool(), items[0]["title"].as_str()), (Some(key.as_str()), Some(true), Some("修一下登录")));

            // It could not be made: its message says why; tried again, it is on its way again.
            views.pending_failed(&key, "no claude profile configured");
            t.read_all(&mut [(&mut screen, 1), (&mut list, 2)]).await;
            let out = screen.value.clone().unwrap()["outbox"].clone();
            assert_eq!((out[0]["state"].as_str(), out[0]["error"].as_str()), (Some("failed"), Some("no claude profile configured")));
            assert_eq!(views.pending_try(&key).map(|(station, _)| station), Some("ws/st".to_string()));
            t.read_all(&mut [(&mut screen, 1), (&mut list, 2)]).await;
            assert_eq!(screen.value.clone().unwrap()["outbox"][0]["state"], "sending");

            // Made: what waited is the chat's outbox, to be delivered; the page is the station's chat once it is read,
            // with the key the station gave it.
            let sends = views.pending_made(&key, "ember:c-1", 9);
            assert_eq!(sends.iter().map(|(id, m)| (id.clone(), m["text"].clone())).collect::<Vec<_>>(), vec![(first.clone(), json!("修一下登录\n细节…"))]);
            assert_eq!(views.pending_thread("ws/st", &key), Some(Some(9)));
            t.read_all(&mut [(&mut screen, 1), (&mut list, 2)]).await;
            let v = screen.value.clone().unwrap();
            assert_eq!((v["pending"].clone(), v["key"].clone(), v["outbox"][0]["id"].as_str()), (json!(false), json!("ember:c-1"), Some(first.as_str())));
            t.read_all(&mut [(&mut screen, 1), (&mut list, 2)]).await;
            assert_eq!(list.value.clone().unwrap()["days"][0]["items"][0]["id"], "ember:c-1");
            t.set(threads("ws/st"), json!([thread(9, &["ember:c-1"], t.host.now_ms())]));
            t.set(page_of("ws/st", 9), page(1, &["修一下登录\n细节…"], Value::Null));
            t.read_all(&mut [(&mut screen, 1), (&mut list, 2)]).await;
            let v = screen.value.clone().unwrap();
            assert_eq!((v["key"].as_str(), v["thread"]["id"].as_u64(), v["messages"].as_array().map(Vec::len)), (Some("ember:c-1"), Some(9), Some(1)));
            // Its row is the station's once the station lists it.
            let mut made = row("ember:c-1", t.host.now_ms());
            made["thread"] = json!(9);
            made["mine"] = json!(true);
            t.set(rows("ws/st"), json!([made]));
            t.read_all(&mut [(&mut screen, 1), (&mut list, 2)]).await;
            let items = list.value.clone().unwrap()["days"][0]["items"].clone();
            assert_eq!((items.as_array().map(Vec::len), items[0]["pending"].clone()), (Some(1), Value::Null));
            // Archived elsewhere, it leaves the station's rows: it is not listed again from what was asked here.
            t.set(rows("ws/st"), json!([]));
            t.read_all(&mut [(&mut screen, 1), (&mut list, 2)]).await;
            assert_eq!(list.value.clone().unwrap()["days"].as_array().map(Vec::len), Some(0));
        });
    }

    #[test]
    fn the_stations_row_covers_a_chat_made_here_before_its_answer_comes() {
        run(async {
            let t = setup();
            let views = t.router.views();
            let mut list = Ui::default();
            t.subscribe(2, Topic::Chats { scope: "ws".into(), mine: true });
            t.set(workspace(), one_station());
            t.host.settle().await;
            let mut old = row("ember:c-0", t.host.now_ms() - 5000.0);
            old["mine"] = json!(true);
            old["thread"] = json!(3);
            t.set(rows("ws/st"), json!([old.clone()]));
            t.read(&mut list, 2).await;
            let key = views.pending_new("ws/st", json!({"runtime": "claude"}));
            views.pending_queue(&key, json!({"text": "修一下登录", "attachments": [], "quotes": []})).unwrap();
            views.pending_try(&key);
            let ids = |list: &Ui| -> Vec<(String, String)> {
                let days = list.value.clone().unwrap()["days"].clone();
                days.as_array().into_iter().flatten().flat_map(|d| d["items"].as_array().cloned().unwrap_or_default())
                    .map(|i| (i["id"].as_str().unwrap_or("").to_string(), i["title"].as_str().unwrap_or("").to_string())).collect()
            };
            t.read(&mut list, 2).await;
            assert!(ids(&list).contains(&(key.clone(), "修一下登录".into())));
            // The viewer makes another chat elsewhere (another client) meanwhile: it is not this one.
            let mut theirs = row("ember:c-2", t.host.now_ms());
            theirs["mine"] = json!(true);
            theirs["thread"] = json!(8);
            theirs["title"] = json!("（还没有消息）");
            t.set(rows("ws/st"), json!([old.clone(), theirs.clone()]));
            t.read(&mut list, 2).await;
            let mut got = ids(&list);
            got.sort();
            assert_eq!(got, vec![("ember:c-0".into(), "ember:c-0 的标题".into()), ("ember:c-2".into(), "（还没有消息）".into()), (key.clone(), "修一下登录".into())]);
            // The station's event brings its row, with the key given here, before its answer: that row is the chat,
            // with the title from here while it has no messages.
            assert_eq!(views.pending_try(&key).map(|(_, ask)| ask["clientKey"].clone()), Some(json!(key)));
            let mut made = row("ember:c-1", t.host.now_ms());
            made["mine"] = json!(true);
            made["thread"] = json!(9);
            made["title"] = json!("（还没有消息）");
            made["clientKey"] = json!(key);
            t.set(rows("ws/st"), json!([old.clone(), theirs.clone(), made.clone()]));
            t.read(&mut list, 2).await;
            let mut got = ids(&list);
            got.sort();
            assert_eq!(got, vec![("ember:c-0".into(), "ember:c-0 的标题".into()), ("ember:c-1".into(), "修一下登录".into()), ("ember:c-2".into(), "（还没有消息）".into())]);
            // Answered: the same rows.
            views.pending_made(&key, "ember:c-1", 9);
            t.read(&mut list, 2).await;
            let mut got = ids(&list);
            got.sort();
            assert_eq!(got, vec![("ember:c-0".into(), "ember:c-0 的标题".into()), ("ember:c-1".into(), "修一下登录".into()), ("ember:c-2".into(), "（还没有消息）".into())]);
            // Its message in, the row is the station's as it is.
            made["last"] = json!({"seq": 1, "text": "修一下登录", "authorKind": "person", "author": "Me@x.com", "createdAt": t.host.now_ms() as i64});
            made["title"] = json!("修一下登录（站上的）");
            t.set(rows("ws/st"), json!([old, theirs, made]));
            t.read(&mut list, 2).await;
            assert!(ids(&list).contains(&("ember:c-1".into(), "修一下登录（站上的）".into())));
        });
    }

    #[test]
    fn a_chat_made_here_keeps_its_first_message_until_its_page_has_the_entry() {
        run(async {
            let t = setup();
            let views = t.router.views();
            let key = views.pending_new("ws/st", json!({"runtime": "claude"}));
            let first = views.pending_queue(&key, json!({"text": "修一下登录", "attachments": [], "quotes": []})).unwrap();
            // Made and delivered before its page looks: the message stays, as sent.
            views.pending_made(&key, "ember:c-1", 9);
            views.outbox_sent("ws/st", 9, &first, 1);
            let mut screen = Ui::default();
            t.subscribe(1, agent_page("ws/st", &key));
            t.set(workspace(), one_station());
            t.host.settle().await;
            t.read(&mut screen, 1).await;
            let v = screen.value.clone().unwrap();
            assert_eq!((v["messages"].as_array().map(Vec::len), v["outbox"][0]["id"].as_str()), (Some(0), Some(first.as_str())));
            // Its entry in: it is a message of the chat, and the outbox lets it go.
            t.set(threads("ws/st"), json!([thread(9, &["ember:c-1"], t.host.now_ms())]));
            t.set(page_of("ws/st", 9), page(1, &["修一下登录"], Value::Null));
            t.read(&mut screen, 1).await;
            let v = screen.value.clone().unwrap();
            assert_eq!((v["messages"].as_array().map(Vec::len), v["outbox"].as_array().map(Vec::len)), (Some(1), Some(0)));
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
