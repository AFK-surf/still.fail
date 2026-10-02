//! GET /events: what changed, as it changes. Changes that come in a burst go out
//! as one event per session, one overview and one round of sidebar rows; a thread's entries go out as they are
//! written. `host` adds host samples; `live`, sessions as they run; `job`, a job's output as it grows. Quotas are asked again, host info sampled and
//! keepalives sent only while someone follows.

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, Weak};
use std::time::{Duration, Instant};

use bytes::Bytes;
use http_body_util::{BodyExt, StreamBody};
use hyper::Response;
use hyper::body::Frame;
use serde_json::{Value, json};
use tokio::sync::{Notify, mpsc};
use tracing::warn;

use super::{AdminApi, Body};
use crate::access::Viewer;
use crate::lang::{Lang, answering_now};
use crate::login::LoginState;
use crate::store::StoreChange;

/// How often quotas are asked again while someone follows, host info sampled while someone asks for it, and a
/// keepalive sent (proxies close idle streams).
const QUOTA_EVERY: Duration = Duration::from_secs(5 * 60);
const HOST_EVERY: Duration = Duration::from_secs(10);
const PING_EVERY: Duration = Duration::from_secs(25);
/// How often a followed job's log is looked at (its size and time) while the stream that asked for it is open.
const LOG_EVERY: Duration = Duration::from_secs(1);

struct Client {
    id: u64,
    viewer: Viewer,
    /// The language its stream was asked in: its overview and rows are said in it.
    lang: Lang,
    /// Wants host samples.
    host: bool,
    /// The sidebar rows last sent to it, by id (as JSON).
    rows: HashMap<String, String>,
    out: mpsc::UnboundedSender<Bytes>,
    /// Its live subscriptions: (session, subscription).
    live: Vec<(String, u64)>,
}

#[derive(Default)]
struct Dirty {
    sessions: HashSet<String>,
    overview: bool,
    rows_all: bool,
    rows: HashSet<String>,
}

pub struct Events {
    api: Weak<AdminApi>,
    clients: Mutex<Vec<Client>>,
    next: AtomicU64,
    dirty: Mutex<Dirty>,
    wake: Notify,
    /// The process state last announced per session; the overview counts them.
    states: Mutex<HashMap<String, &'static str>>,
    last_host: Mutex<String>,
    /// When quotas were last asked around (None: never while followed).
    quotas_at: Mutex<Option<Instant>>,
}

fn frame(event: &str, data: &Value) -> Bytes {
    Bytes::from(format!("event: {event}\ndata: {data}\n\n"))
}

impl Events {
    pub fn new(api: Weak<AdminApi>) -> Arc<Events> {
        Arc::new(Events {
            api,
            clients: Mutex::default(),
            next: AtomicU64::new(1),
            dirty: Mutex::default(),
            wake: Notify::new(),
            states: Mutex::default(),
            last_host: Mutex::default(),
            quotas_at: Mutex::default(),
        })
    }

    pub fn overview_changed(&self) {
        self.dirty.lock().unwrap().overview = true;
        self.wake.notify_one();
    }

    /// The sidebar rows of `viewer` (everyone's when None) may have changed.
    pub fn rows_changed(&self, viewer: Option<&str>) {
        {
            let mut dirty = self.dirty.lock().unwrap();
            match viewer {
                Some(v) => {
                    dirty.rows.insert(v.to_string());
                }
                None => dirty.rows_all = true,
            }
        }
        self.wake.notify_one();
    }

    fn session_changed(&self, key: &str) {
        self.dirty.lock().unwrap().sessions.insert(key.to_string());
        self.rows_changed(None);
    }

    /// Sends an event to the clients `to` picks; those gone are dropped.
    fn emit(&self, event: &str, data: &Value, to: impl Fn(&Client) -> bool) {
        let bytes = frame(event, data);
        let gone: Vec<Client> = {
            let mut clients = self.clients.lock().unwrap();
            let mut gone = vec![];
            clients.retain(|c| {
                let alive = !to(c) || c.out.send(bytes.clone()).is_ok();
                if !alive {
                    gone.push(Client { id: c.id, viewer: c.viewer.clone(), lang: c.lang, host: c.host, rows: HashMap::new(), out: c.out.clone(), live: c.live.clone() });
                }
                alive
            });
            gone
        };
        self.forget(gone);
    }

    /// Clients gone: their live subscriptions end.
    fn forget(&self, gone: Vec<Client>) {
        let Some(api) = self.api.upgrade() else { return };
        for client in gone {
            for (key, id) in client.live {
                api.deps.hub.live.unsubscribe(&key, id);
            }
        }
    }

    /// Opens a stream for `viewer`: the sidebar as it is now is remembered, so later changes are told against it.
    pub fn open(self: &Arc<Self>, viewer: Viewer, host: bool, live: Vec<(String, usize, Option<usize>)>, logs: Vec<(String, usize, PathBuf)>) -> Response<Body> {
        let (out, rx) = mpsc::unbounded_channel::<Bytes>();
        let _ = out.send(Bytes::from_static(b"retry: 3000\n\n"));
        let id = self.next.fetch_add(1, Ordering::SeqCst);
        let lang = crate::lang::spoken();
        let mut client = Client { id, viewer: viewer.clone(), lang, host, rows: HashMap::new(), out: out.clone(), live: vec![] };
        if let Some(api) = self.api.upgrade() {
            client.rows = api.chats(&viewer, false).unwrap_or_default().into_iter().map(|row| (row["id"].as_str().unwrap_or("").to_string(), row.to_string())).collect();
            // Those sessions as they run, on this same stream: each message a `live` event with its key.
            for (key, from, last) in live {
                let (tx, mut messages) = mpsc::unbounded_channel();
                let sub = api.deps.hub.live.subscribe(&key, from, last, tx);
                client.live.push((key.clone(), sub));
                let out = out.clone();
                tokio::spawn(async move {
                    while let Some(message) = messages.recv().await {
                        let mut data = serde_json::to_value(&message).unwrap_or(Value::Null);
                        data["key"] = json!(key);
                        if out.send(frame("live", &data)).is_err() {
                            return;
                        }
                    }
                });
            }
            // Those jobs' last lines: a `job-log` event now, and again each time the log grows, until the stream goes.
            for (id, lines, path) in logs {
                tokio::spawn(follow_log(out.clone(), id, lines, path));
            }
            if host {
                let (me, out) = (self.clone(), out.clone());
                tokio::spawn(async move {
                    if let Some(api) = me.api.upgrade() {
                        let info = crate::host::host_info(&api.config().data_dir).await;
                        let _ = out.send(frame("host", &serde_json::to_value(info).unwrap_or(Value::Null)));
                    }
                });
            }
        }
        let first = self.clients.lock().unwrap().is_empty();
        self.clients.lock().unwrap().push(client);
        // The first to follow: allowances older than a round are asked again now.
        if first {
            self.refresh_quotas(false);
        }
        // The stream lasts as long as the response: when the reader goes, its end of the channel does too.
        let stream = futures_util::stream::unfold(rx, |mut rx| async move { rx.recv().await.map(|b| (Ok::<_, std::io::Error>(Frame::data(b)), rx)) });
        Response::builder()
            .status(200)
            .header("content-type", "text/event-stream")
            .header("cache-control", "no-store")
            .header("connection", "keep-alive")
            .header("x-accel-buffering", "no")
            .body(StreamBody::new(stream).boxed_unsync())
            .expect("a response")
    }

    /// Asks every profile's allowance again that is older than a round (all of them, `all`).
    fn refresh_quotas(&self, all: bool) {
        let Some(api) = self.api.upgrade() else { return };
        if api.deps.quota.is_none() {
            return;
        }
        *self.quotas_at.lock().unwrap() = Some(Instant::now());
        let now = crate::store::now_ms();
        for p in api.config().profiles.iter() {
            let fresh = api.quotas.lock().unwrap().get(&p.id).is_some_and(|q| now - q.checked_at < QUOTA_EVERY.as_millis() as i64 - 1000);
            if fresh && !all {
                continue;
            }
            let (api, id) = (api.clone(), p.id.clone());
            tokio::spawn(async move {
                if let Err(e) = api.refresh_quota(&id).await {
                    warn!(profile = id, error = %e, "quota refresh failed");
                }
            });
        }
    }

    /// Follows what the pages show: the store, the config, connections, sign-ins, the mesh and the machine's logins;
    /// and runs what runs only while someone follows.
    pub fn follow(self: &Arc<Self>) {
        let Some(api) = self.api.upgrade() else { return };
        let me = Arc::downgrade(self);
        let mut changes = api.deps.store.subscribe();
        let events = me.clone();
        tokio::spawn(async move {
            loop {
                let change = changes.recv().await;
                let Some(events) = events.upgrade() else { return };
                match change {
                    Ok(change) => events.store_changed(change),
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {
                        events.overview_changed();
                        events.rows_changed(None);
                    }
                    Err(_) => return,
                }
            }
        });
        // The sidebar names connects and their Slack workspaces.
        let mut settings = api.deps.settings.subscribe();
        let events = me.clone();
        tokio::spawn(async move {
            while settings.changed().await.is_ok() {
                let Some(events) = events.upgrade() else { return };
                events.overview_changed();
                events.rows_changed(None);
            }
        });
        let mut connections = api.deps.connections.changes();
        let events = me.clone();
        tokio::spawn(async move {
            while connections.changed().await.is_ok() {
                let Some(events) = events.upgrade() else { return };
                if let Some(api) = events.api.upgrade() {
                    api.remember_identities();
                }
                events.overview_changed();
                events.rows_changed(None);
            }
        });
        // A finished sign-in changes what the profile can do; it is checked again right away.
        let mut logins = api.deps.logins.changes();
        let events = me.clone();
        tokio::spawn(async move {
            while let Ok(id) = logins.recv().await {
                let Some(events) = events.upgrade() else { return };
                let Some(api) = events.api.upgrade() else { return };
                let pending = api.pending.lock().unwrap().contains_key(&id);
                if pending {
                    api.pending_changed(&id);
                }
                events.overview_changed();
                if !pending && api.deps.logins.get(&id).is_some_and(|j| j.state == LoginState::Done) {
                    api.after_sign_in(&id);
                }
            }
        });
        let watched: Vec<tokio::sync::watch::Receiver<u64>> =
            api.deps.mesh.iter().map(|m| m.changes()).chain(api.deps.machine_logins.iter().map(|m| m.changes())).chain(api.deps.updates.iter().map(|u| u.changes())).collect();
        for mut watch in watched {
            let events = me.clone();
            tokio::spawn(async move {
                while watch.changed().await.is_ok() {
                    match events.upgrade() {
                        Some(events) => events.overview_changed(),
                        None => return,
                    }
                }
            });
        }
        // Changes gathered into one round each time.
        let events = me.clone();
        tokio::spawn(async move {
            loop {
                let Some(notified) = events.upgrade().map(|e| async move { e.wake.notified().await }) else { return };
                notified.await;
                tokio::task::yield_now().await;
                match events.upgrade() {
                    Some(events) => events.flush(),
                    None => return,
                }
            }
        });
        // What runs only while someone follows.
        let events = me;
        tokio::spawn(async move {
            let mut tick = tokio::time::interval(Duration::from_secs(1));
            let (mut pinged, mut sampled) = (Instant::now(), Instant::now());
            loop {
                tick.tick().await;
                let Some(events) = events.upgrade() else { return };
                let (following, hosts) = {
                    let clients = events.clients.lock().unwrap();
                    (!clients.is_empty(), clients.iter().any(|c| c.host))
                };
                if !following {
                    *events.quotas_at.lock().unwrap() = None;
                    continue;
                }
                if pinged.elapsed() >= PING_EVERY {
                    pinged = Instant::now();
                    events.emit_raw(Bytes::from_static(b": ping\n\n"));
                }
                if hosts && sampled.elapsed() >= HOST_EVERY {
                    sampled = Instant::now();
                    events.sample_host().await;
                }
                if !hosts {
                    events.last_host.lock().unwrap().clear();
                }
                let due = events.quotas_at.lock().unwrap().is_none_or(|at| at.elapsed() >= QUOTA_EVERY);
                if due {
                    events.refresh_quotas(false);
                }
            }
        });
    }

    fn emit_raw(&self, bytes: Bytes) {
        let gone: Vec<Client> = {
            let mut clients = self.clients.lock().unwrap();
            let mut gone = vec![];
            clients.retain(|c| {
                let alive = c.out.send(bytes.clone()).is_ok();
                if !alive {
                    gone.push(Client { id: c.id, viewer: c.viewer.clone(), lang: c.lang, host: c.host, rows: HashMap::new(), out: c.out.clone(), live: c.live.clone() });
                }
                alive
            });
            gone
        };
        self.forget(gone);
    }

    /// Host info to every client asking for it, when it changed.
    async fn sample_host(&self) {
        let Some(api) = self.api.upgrade() else { return };
        let info = serde_json::to_value(crate::host::host_info(&api.config().data_dir).await).unwrap_or(Value::Null);
        let mut shown = info.clone();
        if let Some(o) = shown.as_object_mut() {
            o.remove("checkedAt");
            o.remove("uptimeSec");
        }
        let key = shown.to_string();
        {
            let mut last = self.last_host.lock().unwrap();
            if *last == key {
                return;
            }
            *last = key;
        }
        self.emit("host", &info, |c| c.host);
    }

    fn store_changed(&self, change: StoreChange) {
        let Some(api) = self.api.upgrade() else { return };
        match change {
            StoreChange::Session(key) => self.session_changed(&key),
            StoreChange::SessionRemoved(key) => {
                self.dirty.lock().unwrap().sessions.remove(&key);
                self.states.lock().unwrap().remove(&key);
                self.emit("session-removed", &json!({ "key": key }), |_| true);
                self.overview_changed();
                self.rows_changed(None);
            }
            StoreChange::Thread { id, entries } => {
                if !self.clients.lock().unwrap().is_empty() {
                    self.emit("thread", &json!({ "id": id, "entries": api.entry_views(id, &entries) }), |_| true);
                }
                self.rows_changed(None);
            }
            StoreChange::ThreadRemoved(id) => {
                self.emit("thread-removed", &json!({ "id": id }), |_| true);
                self.rows_changed(None);
            }
            StoreChange::Read { viewer, thread, n } => {
                self.emit("read", &json!({ "viewer": viewer, "thread": thread, "n": n }), |c| c.viewer.id() == viewer);
                self.rows_changed(Some(&viewer));
            }
            // Who the viewer is on Slack: their overview says it, and their rows count it.
            StoreChange::Identities(viewer) => {
                self.overview_changed();
                self.rows_changed(Some(&viewer));
            }
            // What the viewer pinned: their rows say it.
            StoreChange::Pins(viewer) => self.rows_changed(Some(&viewer)),
            // What the viewer dismissed: their rows say it.
            StoreChange::Dismissed(viewer) => self.rows_changed(Some(&viewer)),
            StoreChange::Processes => self.overview_changed(),
            // A job as `GET /jobs/:id` answers it, so a client holding it (a chat's jobs, the open ones) puts it in
            // place without reading anything again.
            StoreChange::Job(id) => {
                if let Ok(Some(job)) = api.deps.store.get_job(&id) {
                    self.emit("job", &crate::jobs::shown(&api.deps.store, &job), |_| true);
                }
            }
            StoreChange::JobRemoved { id, session } => self.emit("job-removed", &json!({ "id": id, "session": session }), |_| true),
            // Model calls were recorded: a page showing usage reads it again (it is too big to send to everyone).
            StoreChange::Usage => self.emit("usage", &json!({}), |_| true),
        }
    }

    /// One round: an event per changed session, the overview to each (as its viewer sees it), and the sidebar rows that
    /// changed.
    fn flush(&self) {
        let Some(api) = self.api.upgrade() else { return };
        let dirty = std::mem::take(&mut *self.dirty.lock().unwrap());
        let mut overview = dirty.overview;
        let following = !self.clients.lock().unwrap().is_empty();
        for key in &dirty.sessions {
            if !matches!(api.deps.store.get_session(key), Ok(Some(_))) {
                continue;
            }
            let state = api.deps.hub.process_state(key);
            // The overview counts running and warm sessions.
            if self.states.lock().unwrap().insert(key.clone(), state) != Some(state) {
                overview = true;
            }
            if following {
                match api.summary(key) {
                    Ok(summary) => self.emit("session", &summary, |_| true),
                    Err(e) => warn!(session = key, error = %e, "session event not sent"),
                }
            }
        }
        // Each viewer's, in each language their streams were asked in.
        let viewers: Vec<(Viewer, Lang)> = {
            let clients = self.clients.lock().unwrap();
            let mut seen = HashSet::new();
            clients.iter().filter(|c| seen.insert((c.viewer.id(), c.lang))).map(|c| (c.viewer.clone(), c.lang)).collect()
        };
        if overview && following {
            for (viewer, lang) in &viewers {
                let value = answering_now(*lang, || api.overview(viewer));
                let id = viewer.id();
                self.emit("overview", &value, |c| c.viewer.id() == id && c.lang == *lang);
            }
        }
        if dirty.rows_all || !dirty.rows.is_empty() {
            for (viewer, lang) in viewers.iter().filter(|(v, _)| dirty.rows_all || dirty.rows.contains(&v.id())) {
                let rows = match answering_now(*lang, || api.chats(viewer, false)) {
                    Ok(rows) => rows,
                    Err(e) => {
                        warn!(error = %e, "sidebar rows not read");
                        continue;
                    }
                };
                let now: HashMap<String, String> = rows.iter().map(|r| (r["id"].as_str().unwrap_or("").to_string(), r.to_string())).collect();
                let id = viewer.id();
                let mut clients = self.clients.lock().unwrap();
                for client in clients.iter_mut().filter(|c| c.viewer.id() == id && c.lang == *lang) {
                    for row in &rows {
                        let key = row["id"].as_str().unwrap_or("");
                        if client.rows.get(key) != now.get(key) {
                            let _ = client.out.send(frame("chat", row));
                        }
                    }
                    for gone in client.rows.keys().filter(|k| !now.contains_key(*k)) {
                        let _ = client.out.send(frame("chat-removed", &json!({ "id": gone })));
                    }
                    client.rows = now.clone();
                }
            }
        }
    }
}

/// A job's last `lines` of output on a stream (`job-log`: `id`, `lines`, `text`, `outputAt`): at once, then whenever
/// its log's size or time changes, until the stream is gone.
async fn follow_log(out: mpsc::UnboundedSender<Bytes>, id: String, lines: usize, path: PathBuf) {
    let mut tick = tokio::time::interval(LOG_EVERY);
    let mut seen = None;
    loop {
        tick.tick().await;
        if out.is_closed() {
            return;
        }
        let now = tokio::fs::metadata(&path).await.ok().map(|m| (m.len(), m.modified().ok()));
        if seen.as_ref() == Some(&now) {
            continue;
        }
        seen = Some(now);
        let read = path.clone();
        let Ok((text, at)) = tokio::task::spawn_blocking(move || (crate::jobs::tail(&read, lines), crate::jobs::output_at(&read))).await else { return };
        if out.send(frame("job-log", &json!({ "id": id, "lines": lines, "text": text, "outputAt": at }))).is_err() {
            return;
        }
    }
}
