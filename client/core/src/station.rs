//! Stations' admin API, over a mesh link (or plain HTTP for `local`), and the
//! station topics: overview, sessions, session, live, host, link.
//!
//! While any topic of a station is live, its `/admin/api/events` stream is held
//! open: `session` events refetch that session's live topics and `sessions`,
//! `config` events refetch `overview`. A `live` topic holds
//! `/sessions/:key/live?from=<timeline length>` open and merges its `timeline`
//! messages into the `session` topic's `transcript.timeline` (and `usage`), so
//! the session never has to be refetched whole while it runs. `overview` and
//! `host` also refresh on a timer (10 s / 15 s).

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::future::Future;
use std::rc::{Rc, Weak};

use futures::future::{AbortHandle, Abortable, LocalBoxFuture, join_all};
use futures::stream::LocalBoxStream;
use futures::{FutureExt, StreamExt};
use serde_json::{Value, json};

use crate::error::{CoreError, Result};
use crate::host::{Host, HttpRequest};
use crate::mesh::{GrantSource, Mesh, RequestHead};
use crate::protocol::Topic;
use crate::store::{Source, Store};

/// How long a failed or ended stream waits before it is opened again.
pub const RECONNECT_MS: u64 = 2_000;
/// Bursts of `session` events become one refetch per topic.
pub const EVENTS_COALESCE_MS: u64 = 400;
/// Connection states and process memory change without events.
pub const OVERVIEW_REFRESH_MS: u64 = 10_000;
pub const HOST_REFRESH_MS: u64 = 15_000;

const EVENT_STREAM: &str = "text/event-stream";

/// `"<workspace>/<station>"` or `"local"`.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum StationAddr {
    Local,
    Remote { workspace: String, station: String },
}

impl StationAddr {
    pub fn parse(text: &str) -> Result<StationAddr> {
        if text == "local" {
            return Ok(StationAddr::Local);
        }
        match text.split_once('/') {
            Some((workspace, station)) if !workspace.is_empty() && !station.is_empty() && !station.contains('/') => {
                Ok(StationAddr::Remote { workspace: workspace.into(), station: station.into() })
            }
            _ => Err(CoreError::invalid(format!("不认识的站点地址：{text}"))),
        }
    }
}

impl std::fmt::Display for StationAddr {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StationAddr::Local => f.write_str("local"),
            StationAddr::Remote { workspace, station } => write!(f, "{workspace}/{station}"),
        }
    }
}

// ── the wire ────────────────────────────────────────────────────────────────

/// A station's answer: status, headers, and the body as it arrives.
pub struct WireReply {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: LocalBoxStream<'static, Result<Vec<u8>>>,
}

impl WireReply {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers.iter().find(|(k, _)| k.eq_ignore_ascii_case(name)).map(|(_, v)| v.as_str())
    }

    /// The whole body.
    pub async fn bytes(mut self) -> Result<Vec<u8>> {
        let mut out = Vec::new();
        while let Some(chunk) = self.body.next().await {
            out.extend(chunk?);
        }
        Ok(out)
    }
}

/// How requests reach a station. `head.path` includes `/admin/api`; a request
/// for an event stream carries `accept: text/event-stream`.
pub trait StationWire {
    fn request(&self, station: &StationAddr, head: RequestHead, body: Vec<u8>) -> LocalBoxFuture<'static, Result<WireReply>>;
}

fn wants_stream(head: &RequestHead) -> bool {
    head.headers.iter().any(|(k, v)| k.eq_ignore_ascii_case("accept") && v.contains(EVENT_STREAM))
}

/// The page's own station, over the host's HTTP (the origin is the station's).
pub struct HttpWire {
    host: Rc<dyn Host>,
}

impl HttpWire {
    pub fn new(host: Rc<dyn Host>) -> Rc<HttpWire> {
        Rc::new(HttpWire { host })
    }
}

impl StationWire for HttpWire {
    fn request(&self, _station: &StationAddr, head: RequestHead, body: Vec<u8>) -> LocalBoxFuture<'static, Result<WireReply>> {
        let stream = wants_stream(&head);
        let request = HttpRequest {
            url: format!("{}{}", self.host.cloud_origin(), head.path),
            body: if body.is_empty() && head.method.eq_ignore_ascii_case("GET") { None } else { Some(body) },
            method: head.method,
            headers: head.headers,
        };
        if stream {
            let answer = self.host.fetch_stream(request);
            async move {
                let r = answer.await?;
                Ok(WireReply { status: r.status, headers: r.headers, body: r.body.map(|c| c.map_err(CoreError::from)).boxed_local() })
            }
            .boxed_local()
        } else {
            let answer = self.host.fetch(request);
            async move {
                let r = answer.await?;
                Ok(WireReply { status: r.status, headers: r.headers, body: futures::stream::iter([Ok(r.body)]).boxed_local() })
            }
            .boxed_local()
        }
    }
}

/// This device's endpoint, bound when first needed.
pub type MeshSource = Rc<dyn Fn() -> LocalBoxFuture<'static, Result<Rc<Mesh>>>>;
/// Grants for one station, given (workspace, station): the caller decides which account asks.
pub type StationGrants = Rc<dyn Fn(&str, &str) -> GrantSource>;

/// Remote stations, over mesh links.
pub struct MeshWire {
    mesh: MeshSource,
    grants: StationGrants,
}

impl MeshWire {
    pub fn new(mesh: MeshSource, grants: StationGrants) -> Rc<MeshWire> {
        Rc::new(MeshWire { mesh, grants })
    }
}

impl StationWire for MeshWire {
    fn request(&self, station: &StationAddr, head: RequestHead, body: Vec<u8>) -> LocalBoxFuture<'static, Result<WireReply>> {
        let StationAddr::Remote { workspace, station } = station.clone() else {
            return async { Err(CoreError::invalid("本地站点不走 mesh")) }.boxed_local();
        };
        let mesh = (self.mesh)();
        let grants = (self.grants)(&workspace, &station);
        async move {
            let mesh = mesh.await?;
            let link = mesh.link(&station, grants).await?;
            let reply = link.request(head, body).await?;
            let (status, headers) = (reply.status, reply.headers.clone());
            let body = futures::stream::unfold(reply, |mut reply| async move { reply.next().await.map(|chunk| (chunk, reply)) });
            Ok(WireReply { status, headers, body: body.boxed_local() })
        }
        .boxed_local()
    }
}

/// `local` over one wire, every other station over another.
pub struct RoutedWire {
    local: Rc<dyn StationWire>,
    remote: Rc<dyn StationWire>,
}

impl RoutedWire {
    pub fn new(local: Rc<dyn StationWire>, remote: Rc<dyn StationWire>) -> Rc<RoutedWire> {
        Rc::new(RoutedWire { local, remote })
    }
}

impl StationWire for RoutedWire {
    fn request(&self, station: &StationAddr, head: RequestHead, body: Vec<u8>) -> LocalBoxFuture<'static, Result<WireReply>> {
        match station {
            StationAddr::Local => self.local.request(station, head, body),
            StationAddr::Remote { .. } => self.remote.request(station, head, body),
        }
    }
}

/// The real wire: HTTP for `local`, mesh links for the rest.
pub fn wire(host: Rc<dyn Host>, mesh: MeshSource, grants: StationGrants) -> Rc<dyn StationWire> {
    RoutedWire::new(HttpWire::new(host), MeshWire::new(mesh, grants))
}

// ── where topic values go ───────────────────────────────────────────────────

/// What the station module needs of the store.
pub trait TopicSink {
    fn set(&self, topic: &Topic, value: Result<Value>);
    /// Changes the value in place; does nothing if the topic has no value.
    fn update(&self, topic: &Topic, change: &mut dyn FnMut(&mut Value));
    fn get(&self, topic: &Topic) -> Option<Value>;
}

impl TopicSink for Store {
    fn set(&self, topic: &Topic, value: Result<Value>) {
        Store::set(self, topic, value)
    }
    fn update(&self, topic: &Topic, change: &mut dyn FnMut(&mut Value)) {
        Store::update(self, topic, change)
    }
    fn get(&self, topic: &Topic) -> Option<Value> {
        Store::get(self, topic)
    }
}

// ── server-sent events ──────────────────────────────────────────────────────

/// Splits a text/event-stream into (event name, data) as chunks arrive.
#[derive(Default)]
pub struct SseParser {
    buffer: Vec<u8>,
}

impl SseParser {
    pub fn feed(&mut self, chunk: &[u8]) -> Vec<(String, String)> {
        // CR only ever comes as CRLF here (data is JSON, which escapes it).
        self.buffer.extend(chunk.iter().copied().filter(|&b| b != b'\r'));
        let mut events = Vec::new();
        while let Some(end) = self.buffer.windows(2).position(|w| w == b"\n\n") {
            let block: Vec<u8> = self.buffer.drain(..end + 2).collect();
            // A block ends at a newline, so it never splits a UTF-8 sequence.
            let block = String::from_utf8_lossy(&block[..end]);
            let mut name = "message".to_string();
            let mut data = Vec::new();
            for line in block.split('\n') {
                if let Some(rest) = line.strip_prefix("event:") {
                    name = rest.trim().to_string();
                } else if let Some(rest) = line.strip_prefix("data:") {
                    data.push(rest.strip_prefix(' ').unwrap_or(rest));
                }
            }
            if !data.is_empty() {
                events.push((name, data.join("\n")));
            }
        }
        events
    }
}

// ── paths ───────────────────────────────────────────────────────────────────

/// encodeURIComponent.
pub fn encode(text: &str) -> String {
    let mut out = String::new();
    for b in text.bytes() {
        if b.is_ascii_alphanumeric() || b"-_.!~*'()".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

fn decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Some(b) = std::str::from_utf8(&bytes[i + 1..i + 3]).ok().and_then(|h| u8::from_str_radix(h, 16).ok()) {
                out.push(b);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn topic_path(topic: &Topic) -> Option<String> {
    match topic {
        Topic::Overview { .. } => Some("/overview".into()),
        Topic::Sessions { .. } => Some("/sessions".into()),
        Topic::Session { key, .. } => Some(format!("/sessions/{}", encode(key))),
        Topic::Host { .. } => Some("/host".into()),
        _ => None,
    }
}

/// A station's non-2xx answer as an error.
fn http_error(status: u16, data: &Value) -> CoreError {
    let message = data.get("error").and_then(Value::as_str).map(str::to_string).unwrap_or_else(|| format!("请求失败（{status}）"));
    CoreError::new(format!("http_{status}"), message).with_status(status)
}

// ── stations ────────────────────────────────────────────────────────────────

/// What is kept per station while any of its topics is live.
struct StationState {
    addr: StationAddr,
    topics: HashSet<Topic>,
    events: Option<AbortHandle>,
    /// Per topic: its timer or live stream.
    tasks: HashMap<Topic, AbortHandle>,
    /// Per session key: the steps in flight and the phase.
    lives: HashMap<String, LiveView>,
    dirty: HashSet<String>,
    flushing: bool,
    link: Value,
}

impl StationState {
    fn new(addr: StationAddr) -> Self {
        Self {
            addr,
            topics: HashSet::new(),
            events: None,
            tasks: HashMap::new(),
            lives: HashMap::new(),
            dirty: HashSet::new(),
            flushing: false,
            link: json!({ "state": "connecting" }),
        }
    }
}

/// A `live` topic's value: `LiveMessage` semantics as useLiveSession applied them.
#[derive(Default, Clone)]
struct LiveView {
    steps: Vec<Value>,
    phase: Option<Value>,
}

impl LiveView {
    fn value(&self) -> Value {
        json!({ "steps": self.steps, "phase": self.phase })
    }
}

pub struct Stations {
    host: Rc<dyn Host>,
    sink: Rc<dyn TopicSink>,
    wire: Rc<dyn StationWire>,
    me: Weak<Stations>,
    stations: RefCell<HashMap<String, StationState>>,
}

impl Stations {
    pub fn new(host: Rc<dyn Host>, sink: Rc<dyn TopicSink>, wire: Rc<dyn StationWire>) -> Rc<Stations> {
        Rc::new_cyclic(|me| Stations { host, sink, wire, me: me.clone(), stations: RefCell::default() })
    }

    /// One JSON call to the admin API (path without the `/admin/api` prefix); then refetches the live topics the write can change.
    pub async fn request(&self, station: &StationAddr, method: &str, path: &str, body: Option<Value>) -> Result<Value> {
        let (headers, bytes) = match body {
            Some(body) => (vec![("content-type".into(), "application/json".into())], serde_json::to_vec(&body).unwrap_or_default()),
            None => (Vec::new(), Vec::new()),
        };
        let value = self.call(station, method, path, headers, bytes).await?;
        if !method.eq_ignore_ascii_case("GET") {
            self.after_write(station, path).await;
        }
        Ok(value)
    }

    /// POST /sessions/:key/files?name= with the raw bytes; answers the attachment.
    pub async fn upload(&self, station: &StationAddr, key: &str, name: &str, bytes: Vec<u8>) -> Result<Value> {
        let path = format!("/sessions/{}/files?name={}", encode(key), encode(name));
        self.call(station, "POST", &path, vec![("content-type".into(), "application/octet-stream".into())], bytes).await
    }

    /// GET /sessions/:key/files?name=: (content type, bytes).
    pub async fn file(&self, station: &StationAddr, key: &str, name: &str) -> Result<(String, Vec<u8>)> {
        let path = format!("/sessions/{}/files?name={}", encode(key), encode(name));
        let reply = self.send(station, "GET", &path, Vec::new(), Vec::new()).await?;
        let status = reply.status;
        let kind = reply.header("content-type").unwrap_or("").to_string();
        let bytes = reply.bytes().await?;
        if status != 200 {
            return Err(CoreError::new(format!("http_{status}"), "读不到文件").with_status(status));
        }
        Ok((kind, bytes))
    }

    fn send(&self, station: &StationAddr, method: &str, path: &str, headers: Vec<(String, String)>, body: Vec<u8>) -> LocalBoxFuture<'static, Result<WireReply>> {
        let head = RequestHead { method: method.to_string(), path: format!("/admin/api{path}"), headers };
        self.wire.request(station, head, body)
    }

    async fn call(&self, station: &StationAddr, method: &str, path: &str, headers: Vec<(String, String)>, body: Vec<u8>) -> Result<Value> {
        let reply = self.send(station, method, path, headers, body).await?;
        let status = reply.status;
        let bytes = reply.bytes().await?;
        // Like the web's `response.json().catch(() => ({}))`.
        let data: Value = serde_json::from_slice(&bytes).unwrap_or_else(|_| json!({}));
        if !(200..300).contains(&status) {
            return Err(http_error(status, &data));
        }
        Ok(data)
    }

    /// Opens an event stream; a non-2xx answer is an error.
    async fn open_stream(&self, station: &StationAddr, path: &str) -> Result<LocalBoxStream<'static, Result<Vec<u8>>>> {
        let reply = self.send(station, "GET", path, vec![("accept".into(), EVENT_STREAM.into())], Vec::new()).await?;
        if !(200..300).contains(&reply.status) {
            let status = reply.status;
            let bytes = reply.bytes().await.unwrap_or_default();
            let data: Value = serde_json::from_slice(&bytes).unwrap_or_else(|_| json!({}));
            return Err(http_error(status, &data));
        }
        Ok(reply.body)
    }

    /// Reloads the topics a successful write can have changed; the write answers only after, so a page
    /// that moves on right away finds what it wrote.
    async fn after_write(&self, station: &StationAddr, path: &str) {
        let station = station.to_string();
        let path = path.split('?').next().unwrap_or("");
        let parts: Vec<String> = path.split('/').filter(|p| !p.is_empty()).map(decode).collect();
        let mut touched = Vec::new();
        match parts.first().map(String::as_str) {
            Some("sessions") => {
                if let Some(key) = parts.get(1) {
                    touched.push(Topic::Session { station: station.clone(), key: key.clone() });
                }
                touched.push(Topic::Sessions { station });
            }
            Some("connects") => {
                touched.push(Topic::Overview { station: station.clone() });
                touched.push(Topic::Sessions { station });
            }
            Some("profiles") | Some("slack") => touched.push(Topic::Overview { station }),
            _ => {}
        }
        join_all(touched.iter().map(|topic| self.reload(topic))).await;
    }

    fn rc(&self) -> Rc<Stations> {
        self.me.upgrade().expect("stations are alive while they run")
    }

    fn spawn(&self, task: impl Future<Output = ()> + 'static) -> AbortHandle {
        let (handle, registration) = AbortHandle::new_pair();
        self.host.spawn(Abortable::new(task, registration).map(|_| ()).boxed_local());
        handle
    }

    fn is_live(&self, topic: &Topic) -> bool {
        let Some(station) = topic.station() else { return false };
        self.stations.borrow().get(station).is_some_and(|s| s.topics.contains(topic))
    }

    fn addr(&self, station: &str) -> Option<StationAddr> {
        self.stations.borrow().get(station).map(|s| s.addr.clone())
    }

    /// Fetches a live topic again; a failure only shows when there is nothing better to show.
    fn refetch(&self, topic: &Topic) {
        let this = self.rc();
        let topic = topic.clone();
        self.spawn(async move { this.reload(&topic).await });
    }

    async fn reload(&self, topic: &Topic) {
        if !self.is_live(topic) {
            return;
        }
        let (Some(path), Some(addr)) = (topic_path(topic), topic.station().and_then(|s| self.addr(s))) else { return };
        let result = self.call(&addr, "GET", &path, Vec::new(), Vec::new()).await;
        if !self.is_live(topic) {
            return;
        }
        match result {
            Ok(value) => self.sink.set(topic, Ok(value)),
            Err(error) => {
                if self.sink.get(topic).is_none() {
                    self.sink.set(topic, Err(error));
                }
            }
        }
    }

    fn refetch_all(&self, station: &str) {
        let topics: Vec<Topic> = self.stations.borrow().get(station).map(|s| s.topics.iter().cloned().collect()).unwrap_or_default();
        for topic in topics {
            self.refetch(&topic);
        }
    }

    fn set_link(&self, station: &str, value: Value) {
        let live = {
            let mut stations = self.stations.borrow_mut();
            let Some(s) = stations.get_mut(station) else { return };
            s.link = value.clone();
            s.topics.contains(&Topic::Link { station: station.into() })
        };
        if live {
            self.sink.set(&Topic::Link { station: station.into() }, Ok(value));
        }
    }

    /// Holds the station's `/events` open while any of its topics is live.
    async fn follow_events(self: Rc<Self>, station: String, addr: StationAddr) {
        let mut opened_before = false;
        loop {
            match self.open_stream(&addr, "/events").await {
                Ok(mut body) => {
                    self.set_link(&station, json!({ "state": "online" }));
                    // After a reconnect, anything of this station may have changed.
                    if opened_before {
                        self.refetch_all(&station);
                    }
                    opened_before = true;
                    let mut parser = SseParser::default();
                    let mut why = "连接断开了".to_string();
                    while let Some(chunk) = body.next().await {
                        match chunk {
                            Ok(bytes) => {
                                for (name, data) in parser.feed(&bytes) {
                                    self.on_event(&station, &name, &data);
                                }
                            }
                            Err(error) => {
                                why = error.message;
                                break;
                            }
                        }
                    }
                    self.set_link(&station, json!({ "state": "offline", "message": why }));
                }
                Err(error) if error.status.is_some() => self.set_link(&station, json!({ "state": "error", "message": error.message })),
                Err(error) => self.set_link(&station, json!({ "state": "offline", "message": error.message })),
            }
            self.host.sleep(RECONNECT_MS).await;
        }
    }

    fn on_event(&self, station: &str, name: &str, data: &str) {
        match name {
            "session" => {
                let Some(key) = serde_json::from_str::<Value>(data).ok().and_then(|v| v.get("key")?.as_str().map(str::to_string)) else { return };
                let schedule = {
                    let mut stations = self.stations.borrow_mut();
                    let Some(s) = stations.get_mut(station) else { return };
                    s.dirty.insert(key);
                    !std::mem::replace(&mut s.flushing, true)
                };
                if schedule {
                    let this = self.rc();
                    let station = station.to_string();
                    let sleep = self.host.sleep(EVENTS_COALESCE_MS);
                    self.spawn(async move {
                        sleep.await;
                        this.flush(&station);
                    });
                }
            }
            "config" | "login" => self.refetch(&Topic::Overview { station: station.into() }),
            _ => {}
        }
    }

    fn flush(&self, station: &str) {
        let dirty = {
            let mut stations = self.stations.borrow_mut();
            let Some(s) = stations.get_mut(station) else { return };
            s.flushing = false;
            std::mem::take(&mut s.dirty)
        };
        self.refetch(&Topic::Sessions { station: station.into() });
        for key in dirty {
            self.refetch(&Topic::Session { station: station.into(), key });
        }
    }

    /// Refetches a topic every `ms` while it is live.
    fn every(&self, topic: &Topic, ms: u64) -> AbortHandle {
        let this = self.rc();
        let topic = topic.clone();
        self.spawn(async move {
            loop {
                this.host.sleep(ms).await;
                this.refetch(&topic);
            }
        })
    }

    /// How much of the session's timeline is known here.
    fn timeline_len(&self, station: &str, key: &str) -> usize {
        self.sink
            .get(&Topic::Session { station: station.into(), key: key.into() })
            .and_then(|v| v.get("transcript")?.get("timeline")?.as_array().map(Vec::len))
            .unwrap_or(0)
    }

    /// Holds `/sessions/:key/live` open, resuming from what is known.
    async fn follow_live(self: Rc<Self>, station: String, addr: StationAddr, key: String) {
        loop {
            let path = format!("/sessions/{}/live?from={}", encode(&key), self.timeline_len(&station, &key));
            if let Ok(mut body) = self.open_stream(&addr, &path).await {
                let mut parser = SseParser::default();
                while let Some(Ok(bytes)) = body.next().await {
                    for (_, data) in parser.feed(&bytes) {
                        if let Ok(message) = serde_json::from_str::<Value>(&data) {
                            self.on_live(&station, &key, &message);
                        }
                    }
                }
            }
            self.host.sleep(RECONNECT_MS).await;
        }
    }

    fn on_live(&self, station: &str, key: &str, message: &Value) {
        let now = self.host.now_ms();
        let kind = message.get("type").and_then(Value::as_str).unwrap_or("");
        if kind == "timeline" {
            self.merge_timeline(station, key, message);
        }
        let view = {
            let mut stations = self.stations.borrow_mut();
            let Some(view) = stations.get_mut(station).and_then(|s| s.lives.get_mut(key)) else { return };
            match kind {
                "timeline" => {
                    // Ended steps stay until the entries that record them arrive.
                    let entries = message.get("entries").and_then(Value::as_array).is_some_and(|e| !e.is_empty());
                    if !entries {
                        return;
                    }
                    view.steps.retain(|s| s.get("ended") != Some(&Value::Bool(true)));
                }
                "steps" => {
                    view.steps = message.get("steps").and_then(Value::as_array).cloned().unwrap_or_default();
                    view.phase = message.get("phase").filter(|p| !p.is_null()).map(|p| {
                        let elapsed = p.get("elapsedMs").and_then(Value::as_f64).unwrap_or(0.0);
                        json!({ "phase": p.get("phase").cloned().unwrap_or(Value::Null), "since": now - elapsed })
                    });
                }
                "clear" => *view = LiveView::default(),
                "step" => {
                    let Some(event) = message.get("event") else { return };
                    apply_step(view, event, now);
                }
                _ => return,
            }
            view.value()
        };
        self.sink.set(&Topic::Live { station: station.into(), key: key.into() }, Ok(view));
    }

    /// Puts a `timeline` message's entries into the cached session at `start`;
    /// refetches the session when they cannot be placed.
    fn merge_timeline(&self, station: &str, key: &str, message: &Value) {
        let topic = Topic::Session { station: station.into(), key: key.into() };
        let start = message.get("start").and_then(Value::as_u64).unwrap_or(0) as usize;
        let entries = message.get("entries").and_then(Value::as_array).cloned().unwrap_or_default();
        let usage = message.get("usage").cloned().unwrap_or(Value::Null);
        // Stays false when the session has no value or no transcript yet, or on a gap.
        let mut merged = false;
        self.sink.update(&topic, &mut |session| {
            let Some(transcript) = session.get_mut("transcript").filter(|t| t.is_object()) else { return };
            let Some(timeline) = transcript.get_mut("timeline").and_then(Value::as_array_mut) else { return };
            if start > timeline.len() {
                return;
            }
            timeline.truncate(start);
            timeline.extend(entries.iter().cloned());
            transcript["usage"] = usage.clone();
            merged = true;
        });
        if !merged {
            self.refetch(&topic);
        }
    }
}

/// One `step` event, as useLiveSession applies it.
fn apply_step(view: &mut LiveView, event: &Value, now: f64) {
    let kind = event.get("kind").and_then(Value::as_str).unwrap_or("");
    let id = event.get("id").cloned().unwrap_or(Value::Null);
    match kind {
        "phase" => view.phase = Some(json!({ "phase": event.get("phase").cloned().unwrap_or(Value::Null), "since": now })),
        "start" => {
            view.steps.retain(|s| s.get("id") != Some(&id));
            let mut step = json!({
                "id": id,
                "step": event.get("step").cloned().unwrap_or(Value::Null),
                "text": "",
                "input": event.get("input").and_then(Value::as_str).unwrap_or(""),
                "output": "",
                "startedAt": now,
            });
            if let Some(tool) = event.get("tool").filter(|t| t.as_str().is_some_and(|t| !t.is_empty())) {
                step["tool"] = tool.clone();
            }
            if event.get("subagent").and_then(Value::as_bool) == Some(true) {
                step["subagent"] = Value::Bool(true);
            }
            if let Some(parent) = event.get("parent").filter(|p| p.as_str().is_some_and(|p| !p.is_empty())) {
                step["parent"] = parent.clone();
            }
            view.steps.push(step);
        }
        "delta" => {
            let (Some(field), Some(text)) = (event.get("field").and_then(Value::as_str), event.get("text").and_then(Value::as_str)) else { return };
            for step in view.steps.iter_mut().filter(|s| s.get("id") == Some(&id)) {
                let joined = format!("{}{}", step.get(field).and_then(Value::as_str).unwrap_or(""), text);
                step[field] = Value::String(joined);
            }
        }
        "end" => {
            for step in view.steps.iter_mut().filter(|s| s.get("id") == Some(&id)) {
                step["ended"] = Value::Bool(true);
            }
        }
        _ => {}
    }
}

impl Source for Stations {
    fn start(&self, topic: &Topic) {
        let Some(station) = topic.station().map(str::to_string) else { return };
        let addr = match StationAddr::parse(&station) {
            Ok(addr) => addr,
            Err(error) => {
                // Never into the store while it is calling us.
                let (sink, topic) = (self.sink.clone(), topic.clone());
                self.spawn(async move { sink.set(&topic, Err(error)) });
                return;
            }
        };
        let (fresh, new_station) = {
            let mut stations = self.stations.borrow_mut();
            let state = stations.entry(station.clone()).or_insert_with(|| StationState::new(addr.clone()));
            let new_station = state.events.is_none();
            (state.topics.insert(topic.clone()), new_station)
        };
        if !fresh {
            return;
        }
        if new_station {
            let events = self.spawn(self.rc().follow_events(station.clone(), addr.clone()));
            if let Some(s) = self.stations.borrow_mut().get_mut(&station) {
                s.events = Some(events);
            }
        }
        let task = match topic {
            Topic::Link { .. } => {
                // The state as it is when this runs: the events stream may have moved on.
                let (this, station) = (self.rc(), station.clone());
                self.spawn(async move {
                    let link = this.stations.borrow().get(&station).map(|s| s.link.clone());
                    if let Some(link) = link {
                        this.set_link(&station, link);
                    }
                });
                None
            }
            Topic::Overview { .. } => {
                self.refetch(topic);
                Some(self.every(topic, OVERVIEW_REFRESH_MS))
            }
            Topic::Host { .. } => {
                self.refetch(topic);
                Some(self.every(topic, HOST_REFRESH_MS))
            }
            Topic::Sessions { .. } | Topic::Session { .. } => {
                self.refetch(topic);
                None
            }
            Topic::Live { key, .. } => {
                if let Some(s) = self.stations.borrow_mut().get_mut(&station) {
                    s.lives.insert(key.clone(), LiveView::default());
                }
                let (sink, t) = (self.sink.clone(), topic.clone());
                self.spawn(async move { sink.set(&t, Ok(LiveView::default().value())) });
                Some(self.spawn(self.rc().follow_live(station.clone(), addr, key.clone())))
            }
            _ => None,
        };
        if let Some(task) = task {
            if let Some(s) = self.stations.borrow_mut().get_mut(&station) {
                s.tasks.insert(topic.clone(), task);
            }
        }
    }

    fn stop(&self, topic: &Topic) {
        let Some(station) = topic.station() else { return };
        let mut stations = self.stations.borrow_mut();
        let Some(state) = stations.get_mut(station) else { return };
        state.topics.remove(topic);
        if let Some(task) = state.tasks.remove(topic) {
            task.abort();
        }
        if let Topic::Live { key, .. } = topic {
            state.lives.remove(key);
        }
        if state.topics.is_empty() {
            if let Some(events) = state.events.take() {
                events.abort();
            }
            for (_, task) in state.tasks.drain() {
                task.abort();
            }
            stations.remove(station);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::{FakeHost, chunks, json_response, run};
    use crate::host::{HostError, StreamResponse};
    use futures::channel::mpsc;
    use std::time::Duration;

    // ── fakes ──

    #[derive(Default)]
    struct FakeSink {
        values: RefCell<HashMap<Topic, Result<Value>>>,
    }

    impl TopicSink for FakeSink {
        fn set(&self, topic: &Topic, value: Result<Value>) {
            self.values.borrow_mut().insert(topic.clone(), value);
        }
        fn update(&self, topic: &Topic, change: &mut dyn FnMut(&mut Value)) {
            if let Some(Ok(value)) = self.values.borrow_mut().get_mut(topic) {
                change(value);
            }
        }
        fn get(&self, topic: &Topic) -> Option<Value> {
            self.values.borrow().get(topic).and_then(|v| v.as_ref().ok().cloned())
        }
    }

    type Chunk = Result<Vec<u8>>;

    #[derive(Default)]
    struct FakeWire {
        /// (station, method, path, body) of every request.
        calls: RefCell<Vec<(StationAddr, String, String, Vec<u8>)>>,
        /// "METHOD path" → (status, JSON). Missing: 200 {}.
        answers: RefCell<HashMap<String, (u16, Value)>>,
        /// Open streams by path, newest last.
        streams: RefCell<Vec<(String, mpsc::UnboundedSender<Chunk>)>>,
        /// Status for stream requests (200 opens one); None: the wire fails.
        stream_status: RefCell<Option<u16>>,
    }

    impl FakeWire {
        fn new() -> Rc<FakeWire> {
            let wire = FakeWire::default();
            *wire.stream_status.borrow_mut() = Some(200);
            Rc::new(wire)
        }
        fn answer(&self, what: &str, status: u16, value: Value) {
            self.answers.borrow_mut().insert(what.into(), (status, value));
        }
        fn count(&self, method: &str, path: &str) -> usize {
            self.calls.borrow().iter().filter(|(_, m, p, _)| m == method && p == path).count()
        }
        fn paths(&self) -> Vec<String> {
            self.calls.borrow().iter().map(|(_, m, p, _)| format!("{m} {p}")).collect()
        }
        /// Sends SSE text on the newest open stream whose path starts with `prefix`.
        fn push(&self, prefix: &str, text: &str) {
            let streams = self.streams.borrow();
            let (_, tx) = streams.iter().rev().find(|(p, _)| p.starts_with(prefix)).expect("stream open");
            tx.unbounded_send(Ok(text.as_bytes().to_vec())).unwrap();
        }
        fn end(&self, prefix: &str) {
            let mut streams = self.streams.borrow_mut();
            streams.retain(|(p, _)| !p.starts_with(prefix));
        }
    }

    impl StationWire for FakeWire {
        fn request(&self, station: &StationAddr, head: RequestHead, body: Vec<u8>) -> LocalBoxFuture<'static, Result<WireReply>> {
            self.calls.borrow_mut().push((station.clone(), head.method.clone(), head.path.clone(), body));
            let reply = if wants_stream(&head) {
                match *self.stream_status.borrow() {
                    Some(200) => {
                        let (tx, rx) = mpsc::unbounded();
                        self.streams.borrow_mut().push((head.path.clone(), tx));
                        Ok(WireReply { status: 200, headers: vec![], body: rx.boxed_local() })
                    }
                    Some(status) => Ok(WireReply { status, headers: vec![], body: futures::stream::iter([Ok(r#"{"error":"没有权限"}"#.as_bytes().to_vec())]).boxed_local() }),
                    None => Err(CoreError::new("offline", "连不上")),
                }
            } else {
                let (status, value) = self.answers.borrow().get(&format!("{} {}", head.method, head.path)).cloned().unwrap_or((200, json!({})));
                Ok(WireReply { status, headers: vec![("content-type".into(), "application/json".into())], body: futures::stream::iter([Ok(serde_json::to_vec(&value).unwrap())]).boxed_local() })
            };
            async move { reply }.boxed_local()
        }
    }

    fn setup() -> (Rc<FakeHost>, Rc<FakeSink>, Rc<FakeWire>, Rc<Stations>) {
        let host = FakeHost::new();
        let sink = Rc::new(FakeSink::default());
        let wire = FakeWire::new();
        let stations = Stations::new(host.clone(), sink.clone(), wire.clone());
        (host, sink, wire, stations)
    }

    async fn wait(ms: u64) {
        tokio::time::sleep(Duration::from_millis(ms)).await;
    }

    const ST: &str = "ws/st";
    fn session(key: &str) -> Topic {
        Topic::Session { station: ST.into(), key: key.into() }
    }
    fn live(key: &str) -> Topic {
        Topic::Live { station: ST.into(), key: key.into() }
    }
    fn sessions() -> Topic {
        Topic::Sessions { station: ST.into() }
    }
    fn overview() -> Topic {
        Topic::Overview { station: ST.into() }
    }
    fn remote() -> StationAddr {
        StationAddr::parse(ST).unwrap()
    }
    fn timeline_of(sink: &FakeSink, key: &str) -> Value {
        sink.get(&session(key)).unwrap()["transcript"]["timeline"].clone()
    }
    fn live_of(sink: &FakeSink, key: &str) -> Value {
        sink.get(&live(key)).unwrap()
    }
    fn msg(value: Value) -> String {
        format!("event: {}\ndata: {}\n\n", value["type"].as_str().unwrap(), value)
    }

    // ── tests ──

    #[test]
    fn parses_addresses() {
        assert_eq!(StationAddr::parse("local").unwrap(), StationAddr::Local);
        assert_eq!(StationAddr::parse("ws/st").unwrap(), StationAddr::Remote { workspace: "ws".into(), station: "st".into() });
        assert_eq!(StationAddr::parse("ws/st").unwrap().to_string(), "ws/st");
        for bad in ["", "ws", "/st", "ws/", "a/b/c", "Local"] {
            assert_eq!(StationAddr::parse(bad).unwrap_err().code, "invalid_params", "{bad}");
        }
    }

    #[test]
    fn parses_sse_across_chunks() {
        let mut p = SseParser::default();
        assert!(p.feed(b"retry: 2000\n\n: ping\n\nevent: sess").is_empty());
        assert_eq!(p.feed(b"ion\r\ndata: {\"key\":\"a\"}\r\n\r\ndata: x\ndata:y\n\nevent: e\n"), vec![
            ("session".to_string(), "{\"key\":\"a\"}".to_string()),
            ("message".to_string(), "x\ny".to_string()),
        ]);
        let text = "data: 你好\n\n".as_bytes();
        assert!(p.feed(&text[..7]).is_empty());
        assert_eq!(p.feed(&text[7..]), vec![("e".to_string(), "你好".to_string())]);
    }

    #[test]
    fn encodes_like_the_web() {
        assert_eq!(encode("a b/ç!"), "a%20b%2F%C3%A7!");
        assert_eq!(decode("a%20b%2F%C3%A7!"), "a b/ç!");
        assert_eq!(decode("100%"), "100%");
    }

    #[test]
    fn maps_request_errors() {
        run(async {
            let (_host, _sink, wire, stations) = setup();
            wire.answer("GET /admin/api/overview", 200, json!({"connects": []}));
            wire.answer("POST /admin/api/sessions/k/stop", 403, json!({"error": "没有权限"}));
            wire.answer("GET /admin/api/host", 500, json!("oops"));
            assert_eq!(stations.request(&remote(), "GET", "/overview", None).await.unwrap(), json!({"connects": []}));
            let e = stations.request(&remote(), "POST", "/sessions/k/stop", Some(json!({}))).await.unwrap_err();
            assert_eq!((e.code.as_str(), e.message.as_str(), e.status), ("http_403", "没有权限", Some(403)));
            let e = stations.request(&remote(), "GET", "/host", None).await.unwrap_err();
            assert_eq!((e.code.as_str(), e.message.as_str(), e.status), ("http_500", "请求失败（500）", Some(500)));
            // The body goes as JSON.
            assert_eq!(wire.calls.borrow()[1].3, b"{}".to_vec());
        });
    }

    #[test]
    fn uploads_and_reads_files() {
        run(async {
            let (_host, _sink, wire, stations) = setup();
            wire.answer("POST /admin/api/sessions/k%201/files?name=a%20b.png", 200, json!({"name": "a b.png"}));
            let saved = stations.upload(&remote(), "k 1", "a b.png", vec![1, 2, 3]).await.unwrap();
            assert_eq!(saved["name"], "a b.png");
            assert_eq!(wire.calls.borrow()[0].3, vec![1, 2, 3]);
            wire.answer("GET /admin/api/sessions/k/files?name=x", 404, json!({"error": "没有这个文件"}));
            let e = stations.file(&remote(), "k", "x").await.unwrap_err();
            assert_eq!((e.message.as_str(), e.status), ("读不到文件", Some(404)));
        });
    }

    #[test]
    fn writes_refetch_what_they_touch() {
        run(async {
            let (host, sink, wire, stations) = setup();
            for t in [session("k 1"), session("other"), sessions(), overview()] {
                stations.start(&t);
            }
            host.settle().await;
            assert!(sink.get(&session("k 1")).is_some());
            let before = |p: &str| wire.count("GET", p);
            let (s, k, o, other) = (before("/admin/api/sessions"), before("/admin/api/sessions/k%201"), before("/admin/api/overview"), before("/admin/api/sessions/other"));
            stations.request(&remote(), "POST", "/sessions/k%201/stop", None).await.unwrap();
            host.settle().await;
            assert_eq!(wire.count("GET", "/admin/api/sessions"), s + 1);
            assert_eq!(wire.count("GET", "/admin/api/sessions/k%201"), k + 1);
            assert_eq!(wire.count("GET", "/admin/api/sessions/other"), other);
            assert_eq!(wire.count("GET", "/admin/api/overview"), o);
            stations.request(&remote(), "PUT", "/connects/c", Some(json!({}))).await.unwrap();
            stations.request(&remote(), "POST", "/profiles/p/check", None).await.unwrap();
            host.settle().await;
            assert_eq!(wire.count("GET", "/admin/api/overview"), o + 2);
            assert_eq!(wire.count("GET", "/admin/api/sessions"), s + 2);
            // A read changes nothing.
            stations.request(&remote(), "GET", "/slack/config-token", None).await.unwrap();
            host.settle().await;
            assert_eq!(wire.count("GET", "/admin/api/overview"), o + 2);
        });
    }

    #[test]
    fn events_refetch_coalesced() {
        run(async {
            let (host, sink, wire, stations) = setup();
            let link = Topic::Link { station: ST.into() };
            for t in [session("a"), session("b"), sessions(), overview(), link.clone()] {
                stations.start(&t);
            }
            host.settle().await;
            assert_eq!(sink.get(&link).unwrap()["state"], "online");
            assert_eq!(wire.count("GET", "/admin/api/events"), 1, "one events stream per station");
            let n = |p: &str| wire.count("GET", p);
            let (a, b, s, o) = (n("/admin/api/sessions/a"), n("/admin/api/sessions/b"), n("/admin/api/sessions"), n("/admin/api/overview"));
            for _ in 0..3 {
                wire.push("/admin/api/events", "event: session\ndata: {\"key\":\"a\"}\n\n");
            }
            wire.push("/admin/api/events", "event: session\ndata: {\"key\":\"nobody-watches\"}\n\n");
            host.settle().await;
            assert_eq!(n("/admin/api/sessions"), s, "waits for the burst to end");
            wait(EVENTS_COALESCE_MS).await;
            assert_eq!(n("/admin/api/sessions/a"), a + 1);
            assert_eq!(n("/admin/api/sessions/b"), b);
            assert_eq!(n("/admin/api/sessions"), s + 1);
            assert_eq!(n("/admin/api/sessions/nobody-watches"), 0);
            wire.push("/admin/api/events", "event: config\ndata: {}\n\n");
            host.settle().await;
            assert_eq!(n("/admin/api/overview"), o + 1);
        });
    }

    #[test]
    fn events_reconnect_and_report_the_link() {
        run(async {
            let (host, sink, wire, stations) = setup();
            let link = Topic::Link { station: ST.into() };
            stations.start(&link);
            stations.start(&sessions());
            host.settle().await;
            assert_eq!(sink.get(&link).unwrap()["state"], "online");
            *wire.stream_status.borrow_mut() = None;
            wire.end("/admin/api/events");
            host.settle().await;
            assert_eq!(sink.get(&link).unwrap()["state"], "offline");
            wait(RECONNECT_MS + 50).await;
            assert_eq!(sink.get(&link).unwrap(), json!({"state": "offline", "message": "连不上"}));
            *wire.stream_status.borrow_mut() = Some(403);
            wait(RECONNECT_MS + 50).await;
            assert_eq!(sink.get(&link).unwrap(), json!({"state": "error", "message": "没有权限"}));
            let s = wire.count("GET", "/admin/api/sessions");
            *wire.stream_status.borrow_mut() = Some(200);
            wait(RECONNECT_MS + 50).await;
            assert_eq!(sink.get(&link).unwrap()["state"], "online");
            assert_eq!(wire.count("GET", "/admin/api/sessions"), s + 1, "a reconnect refetches the station's topics");
            // Nothing live: the stream closes and stays closed.
            stations.stop(&link);
            stations.stop(&sessions());
            let e = wire.count("GET", "/admin/api/events");
            wait(RECONNECT_MS + 100).await;
            assert_eq!(wire.count("GET", "/admin/api/events"), e);
        });
    }

    #[test]
    fn live_merges_the_timeline() {
        run(async {
            let (host, sink, wire, stations) = setup();
            wire.answer("GET /admin/api/sessions/k", 200, json!({"transcript": {"timeline": ["a", "b"], "usage": {"modelCalls": 1}}}));
            stations.start(&session("k"));
            host.settle().await;
            stations.start(&live("k"));
            host.settle().await;
            assert!(wire.paths().contains(&"GET /admin/api/sessions/k/live?from=2".to_string()));
            wire.push("/admin/api/sessions/k/live", &msg(json!({"type": "timeline", "start": 2, "entries": ["c"], "usage": {"modelCalls": 2}})));
            host.settle().await;
            assert_eq!(timeline_of(&sink, "k"), json!(["a", "b", "c"]));
            assert_eq!(sink.get(&session("k")).unwrap()["transcript"]["usage"]["modelCalls"], 2);
            // Overlap: replaced from `start`.
            wire.push("/admin/api/sessions/k/live", &msg(json!({"type": "timeline", "start": 1, "entries": ["B", "c", "d"], "usage": {}})));
            host.settle().await;
            assert_eq!(timeline_of(&sink, "k"), json!(["a", "B", "c", "d"]));
            // A gap: the session is fetched again.
            let fetched = wire.count("GET", "/admin/api/sessions/k");
            wire.push("/admin/api/sessions/k/live", &msg(json!({"type": "timeline", "start": 9, "entries": ["z"], "usage": {}})));
            host.settle().await;
            assert_eq!(wire.count("GET", "/admin/api/sessions/k"), fetched + 1);
            assert_eq!(timeline_of(&sink, "k"), json!(["a", "b"]), "the refetched session");
            // Reconnects ask from what is known now.
            wire.push("/admin/api/sessions/k/live", &msg(json!({"type": "timeline", "start": 2, "entries": ["c", "d", "e"], "usage": {}})));
            host.settle().await;
            wire.end("/admin/api/sessions/k/live");
            wait(RECONNECT_MS + 50).await;
            assert!(wire.paths().contains(&"GET /admin/api/sessions/k/live?from=5".to_string()), "{:?}", wire.paths());
        });
    }

    #[test]
    fn live_without_a_transcript_refetches() {
        run(async {
            let (host, _sink, wire, stations) = setup();
            wire.answer("GET /admin/api/sessions/k", 200, json!({"transcript": null}));
            stations.start(&session("k"));
            stations.start(&live("k"));
            host.settle().await;
            assert!(wire.paths().contains(&"GET /admin/api/sessions/k/live?from=0".to_string()));
            let fetched = wire.count("GET", "/admin/api/sessions/k");
            wire.push("/admin/api/sessions/k/live", &msg(json!({"type": "timeline", "start": 0, "entries": ["a"], "usage": {}})));
            host.settle().await;
            assert_eq!(wire.count("GET", "/admin/api/sessions/k"), fetched + 1);
        });
    }

    #[test]
    fn live_steps_and_phase() {
        run(async {
            let (host, sink, wire, stations) = setup();
            wire.answer("GET /admin/api/sessions/k", 200, json!({"transcript": {"timeline": [], "usage": {}}}));
            stations.start(&session("k"));
            stations.start(&live("k"));
            host.settle().await;
            assert_eq!(live_of(&sink, "k"), json!({"steps": [], "phase": null}));
            let push = |v: Value| wire.push("/admin/api/sessions/k/live", &msg(v));
            let now = host.now_ms();
            push(json!({"type": "steps", "steps": [{"id": "s0", "step": "text", "text": "hi", "input": "", "output": "", "startedAt": 1}], "phase": {"phase": "thinking", "elapsedMs": 5000}}));
            host.settle().await;
            let v = live_of(&sink, "k");
            assert_eq!(v["steps"][0]["id"], "s0");
            assert_eq!(v["phase"]["phase"], "thinking");
            let since = v["phase"]["since"].as_f64().unwrap();
            assert!((since - (now - 5000.0)).abs() < 1000.0, "{since} vs {now}");
            push(json!({"type": "step", "event": {"kind": "start", "id": "t1", "step": "tool", "tool": "Bash", "input": "ls"}}));
            push(json!({"type": "step", "event": {"kind": "delta", "id": "t1", "field": "output", "text": "a"}}));
            push(json!({"type": "step", "event": {"kind": "delta", "id": "t1", "field": "output", "text": "b"}}));
            push(json!({"type": "step", "event": {"kind": "end", "id": "t1"}}));
            push(json!({"type": "step", "event": {"kind": "phase", "phase": "responding"}}));
            host.settle().await;
            let v = live_of(&sink, "k");
            let t1 = &v["steps"][1];
            assert_eq!((t1["tool"].as_str(), t1["input"].as_str(), t1["output"].as_str(), t1["ended"].as_bool()), (Some("Bash"), Some("ls"), Some("ab"), Some(true)));
            assert!(t1.get("subagent").is_none());
            assert_eq!(v["phase"]["phase"], "responding");
            assert!(v["phase"]["since"].as_f64().unwrap() >= now);
            // No entries: ended steps stay.
            push(json!({"type": "timeline", "start": 0, "entries": [], "usage": {}}));
            host.settle().await;
            assert_eq!(live_of(&sink, "k")["steps"].as_array().unwrap().len(), 2);
            // Entries: they recorded the ended step.
            push(json!({"type": "timeline", "start": 0, "entries": ["x"], "usage": {}}));
            host.settle().await;
            let v = live_of(&sink, "k");
            assert_eq!(v["steps"].as_array().unwrap().len(), 1);
            assert_eq!(v["steps"][0]["id"], "s0");
            // A restarted id replaces the old step.
            push(json!({"type": "step", "event": {"kind": "start", "id": "s0", "step": "text", "subagent": true, "parent": "t0"}}));
            host.settle().await;
            let v = live_of(&sink, "k");
            assert_eq!(v["steps"].as_array().unwrap().len(), 1);
            assert_eq!((v["steps"][0]["text"].as_str(), v["steps"][0]["subagent"].as_bool(), v["steps"][0]["parent"].as_str()), (Some(""), Some(true), Some("t0")));
            push(json!({"type": "clear"}));
            host.settle().await;
            assert_eq!(live_of(&sink, "k"), json!({"steps": [], "phase": null}));
        });
    }

    #[test]
    fn timers_refresh_overview() {
        run(async {
            let (host, _sink, wire, stations) = setup();
            stations.start(&overview());
            host.settle().await;
            let o = wire.count("GET", "/admin/api/overview");
            wait(OVERVIEW_REFRESH_MS).await;
            assert_eq!(wire.count("GET", "/admin/api/overview"), o + 1);
            stations.stop(&overview());
            wait(OVERVIEW_REFRESH_MS).await;
            assert_eq!(wire.count("GET", "/admin/api/overview"), o + 1);
        });
    }

    #[test]
    fn bad_station_and_failed_fetches_are_errors() {
        run(async {
            let (host, sink, wire, stations) = setup();
            let bad = Topic::Overview { station: "nope".into() };
            stations.start(&bad);
            wire.answer("GET /admin/api/host", 502, json!({"error": "坏了"}));
            let h = Topic::Host { station: ST.into() };
            stations.start(&h);
            host.settle().await;
            assert_eq!(sink.values.borrow()[&bad].as_ref().unwrap_err().code, "invalid_params");
            assert_eq!(sink.values.borrow()[&h].as_ref().unwrap_err().message, "坏了");
        });
    }

    #[test]
    fn routes_local_and_remote() {
        run(async {
            let (host, sink) = (FakeHost::new(), Rc::new(FakeSink::default()));
            let (local, far) = (FakeWire::new(), FakeWire::new());
            let stations = Stations::new(host.clone(), sink, RoutedWire::new(local.clone(), far.clone()));
            stations.request(&StationAddr::Local, "GET", "/overview", None).await.unwrap();
            stations.request(&remote(), "GET", "/host", None).await.unwrap();
            assert_eq!(local.paths(), vec!["GET /admin/api/overview"]);
            assert_eq!(far.paths(), vec!["GET /admin/api/host"]);
            assert_eq!(far.calls.borrow()[0].0, remote());
        });
    }

    #[test]
    fn http_wire_uses_the_hosts_fetch() {
        run(async {
            let host = FakeHost::new();
            host.on_fetch(|_| json_response(200, json!({"ok": true})));
            host.on_fetch_stream(|_| Ok(StreamResponse { status: 200, headers: vec![], body: chunks(vec![b"event: config\ndata: {}\n\n".to_vec()]) }));
            let wire = HttpWire::new(host.clone());
            let head = RequestHead { method: "GET".into(), path: "/admin/api/overview".into(), headers: vec![] };
            let reply = wire.request(&StationAddr::Local, head, vec![]).await.unwrap();
            assert_eq!(reply.bytes().await.unwrap(), br#"{"ok":true}"#.to_vec());
            let head = RequestHead { method: "GET".into(), path: "/admin/api/events".into(), headers: vec![("accept".into(), EVENT_STREAM.into())] };
            let reply = wire.request(&StationAddr::Local, head, vec![]).await.unwrap();
            let mut parser = SseParser::default();
            assert_eq!(parser.feed(&reply.bytes().await.unwrap()), vec![("config".to_string(), "{}".to_string())]);
            let urls: Vec<String> = host.requests.borrow().iter().map(|r| r.url.clone()).collect();
            assert_eq!(urls, vec!["https://ember.test/admin/api/overview", "https://ember.test/admin/api/events"]);
            assert!(host.requests.borrow()[0].body.is_none());
            host.on_fetch(|_| Err(HostError("down".into())));
            let head = RequestHead { method: "GET".into(), path: "/admin/api/host".into(), headers: vec![] };
            assert_eq!(wire.request(&StationAddr::Local, head, vec![]).await.err().unwrap().code, "host");
        });
    }
}
