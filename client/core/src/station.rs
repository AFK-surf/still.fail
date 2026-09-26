//! Stations' admin API, over a mesh link (or plain HTTP for `local`), and the
//! station topics: overview, sessions, threads, session, thread, live, host, link.
//!
//! While any topic of a station is live, its `/admin/api/events` stream is held
//! open and is all that keeps the topics current: each topic is read once when
//! it starts, and again only after the stream was down. Events carry what
//! changed (a session's summary, a thread's changed messages, a read position,
//! the overview, host samples), which goes into the topics as it is; what an
//! event does not carry (a thread's unread count) is read for that one thing.
//! Host samples are asked for (`?host=1`) only while a `host` topic is live. A
//! `live` topic holds `/sessions/:key/live?from=<entries known>` open: the
//! transcript from its first entry and then as it grows, the steps in flight
//! and the phase. Nothing here runs on a timer but reconnects.

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
/// A burst of `thread` events becomes one read of each thread's summary.
pub const EVENTS_COALESCE_MS: u64 = 400;
/// Messages per page of a thread.
pub const PAGE: usize = 50;

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
    /// The `/events` stream, and whether it asks for host samples.
    events: Option<(AbortHandle, bool)>,
    /// The stream a new one replaces (to start or stop host samples). It stays open until its successor is, so no
    /// event falls between the two.
    replaced: Option<AbortHandle>,
    /// Numbers the streams opened; only the newest reports.
    generation: u64,
    /// The stream dropped since the topics were read: the next one to open reads them again.
    stale: bool,
    /// Per topic: its live stream.
    tasks: HashMap<Topic, AbortHandle>,
    /// Per session key: the steps in flight and the phase.
    lives: HashMap<String, LiveView>,
    /// Threads whose summaries (last message, unread) are read again once a burst of events is over.
    dirty: HashSet<u64>,
    flushing: bool,
    link: Value,
}

impl StationState {
    fn new(addr: StationAddr) -> Self {
        Self {
            addr,
            topics: HashSet::new(),
            events: None,
            replaced: None,
            generation: 0,
            stale: false,
            tasks: HashMap::new(),
            lives: HashMap::new(),
            dirty: HashSet::new(),
            flushing: false,
            link: json!({ "state": "connecting" }),
        }
    }

    fn wants_host(&self) -> bool {
        self.topics.iter().any(|t| matches!(t, Topic::Host { .. }))
    }
}

/// The steps in flight and the phase of a `live` topic (`LiveMessage` semantics as useLiveSession applied them).
#[derive(Default, Clone)]
struct LiveView {
    steps: Vec<Value>,
    phase: Option<Value>,
}

/// A `live` topic before its stream has said anything: `loaded` turns true with the stream's first steps, which
/// follow the transcript entries it already has.
fn live_start() -> Value {
    json!({ "loaded": false, "timeline": [], "usage": null, "steps": [], "phase": null })
}

fn seq_of(message: &Value) -> Option<u64> {
    message.get("seq").and_then(Value::as_u64)
}

/// Threads as the station lists them: the latest message first, then the newest thread.
fn sort_threads(threads: &mut [Value]) {
    let key = |t: &Value| {
        let last = t.get("last").and_then(seq_of).unwrap_or(0);
        let created = t.get("createdAt").and_then(Value::as_f64).unwrap_or(0.0);
        (last, created, t.get("id").and_then(Value::as_u64).unwrap_or(0))
    };
    threads.sort_by(|a, b| {
        let (a, b) = (key(a), key(b));
        b.0.cmp(&a.0).then(b.1.total_cmp(&a.1)).then(b.2.cmp(&a.2))
    });
}

/// Puts a thread's summary into a list, replacing the one with its id.
fn upsert_thread(list: &mut Vec<Value>, view: &Value) {
    let id = view.get("id");
    match list.iter().position(|t| t.get("id") == id) {
        Some(i) => list[i] = view.clone(),
        None => list.push(view.clone()),
    }
    sort_threads(list);
}

/// Whether the turns a session detail lists still end as its summary says.
fn same_turns(turns: Option<&Value>, summary: &Value) -> bool {
    let turns = turns.and_then(Value::as_array).map(Vec::as_slice).unwrap_or_default();
    if summary.get("turns").and_then(Value::as_u64) != Some(turns.len() as u64) {
        return false;
    }
    let last = summary.get("lastTurn").filter(|t| !t.is_null());
    match (turns.last(), last) {
        (None, None) => true,
        (Some(record), Some(last)) => ["kind", "outcome", "declared", "detail", "startedAt", "endedAt"].iter().all(|k| record.get(k) == last.get(k)),
        _ => false,
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

    /// One JSON call to the admin API (path without the `/admin/api` prefix); a write answers once the live topics
    /// it changes are current.
    pub async fn request(&self, station: &StationAddr, method: &str, path: &str, body: Option<Value>) -> Result<Value> {
        let value = self.json(station, method, path, body).await?;
        if !method.eq_ignore_ascii_case("GET") {
            self.after_write(station, path, &value).await;
        }
        Ok(value)
    }

    async fn json(&self, station: &StationAddr, method: &str, path: &str, body: Option<Value>) -> Result<Value> {
        let (headers, bytes) = match body {
            Some(body) => (vec![("content-type".into(), "application/json".into())], serde_json::to_vec(&body).unwrap_or_default()),
            None => (Vec::new(), Vec::new()),
        };
        self.call(station, method, path, headers, bytes).await
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

    /// Brings the topics a successful write changed up to date before the write answers, so a page that moves on
    /// right away finds what it wrote: from the answer where it says (an overview, a thread, a read position),
    /// else by reading them again. The station's events would bring the same a moment later.
    async fn after_write(&self, station: &StationAddr, path: &str, answer: &Value) {
        let name = station.to_string();
        let path = path.split('?').next().unwrap_or("");
        let parts: Vec<String> = path.split('/').filter(|p| !p.is_empty()).map(decode).collect();
        let mut touched = Vec::new();
        match parts.first().map(String::as_str) {
            Some("sessions") => {
                if let Some(key) = parts.get(1) {
                    touched.push(Topic::Session { station: name.clone(), key: key.clone() });
                }
                touched.push(Topic::Sessions { station: name.clone() });
                // A new chat answers its thread.
                if let Some(thread) = answer.get("thread").filter(|t| t.is_object()) {
                    self.put_thread(&name, thread);
                }
            }
            Some("threads") => {
                if answer.get("surface").is_some() {
                    self.put_thread(&name, answer);
                } else if let (Some(thread), Some(seq)) = (answer.get("thread").and_then(Value::as_u64), answer.get("seq").and_then(Value::as_u64)) {
                    self.put_read(&name, thread, seq);
                }
                if let (Some(id), Some("messages")) = (parts.get(1).and_then(|id| id.parse().ok()), parts.get(2).map(String::as_str)) {
                    touched.push(Topic::Thread { station: name.clone(), thread: id });
                }
            }
            Some("connects") => {
                touched.push(Topic::Overview { station: name.clone() });
                touched.push(Topic::Sessions { station: name.clone() });
            }
            Some("profiles") | Some("slack") => touched.push(Topic::Overview { station: name.clone() }),
            _ => {}
        }
        // Profile and connect edits answer the overview as it is now.
        if answer.get("connects").is_some() && answer.get("profiles").is_some() {
            let overview = Topic::Overview { station: name };
            if self.is_live(&overview) {
                self.sink.set(&overview, Ok(answer.clone()));
            }
            touched.retain(|t| *t != overview);
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

    /// The station's live topics that `pick` chooses.
    fn live_topics(&self, station: &str, pick: impl Fn(&Topic) -> bool) -> Vec<Topic> {
        self.stations.borrow().get(station).map(|s| s.topics.iter().filter(|t| pick(t)).cloned().collect()).unwrap_or_default()
    }

    /// Sets a topic from an event, if it is live.
    fn set_live(&self, topic: Topic, value: Value) {
        if self.is_live(&topic) {
            self.sink.set(&topic, Ok(value));
        }
    }

    /// Reads a live topic again; a failure only shows when there is nothing better to show.
    fn refetch(&self, topic: &Topic) {
        let this = self.rc();
        let topic = topic.clone();
        self.spawn(async move { this.reload(&topic).await });
    }

    async fn reload(&self, topic: &Topic) {
        if !self.is_live(topic) {
            return;
        }
        let Some(addr) = topic.station().and_then(|s| self.addr(s)) else { return };
        let path = match topic {
            Topic::Overview { .. } => "/overview".to_string(),
            Topic::Sessions { .. } => "/sessions".to_string(),
            Topic::Threads { .. } => "/threads".to_string(),
            Topic::Session { key, .. } => format!("/sessions/{}", encode(key)),
            // A thread already read only asks for what changed since.
            Topic::Thread { thread, .. } => match self.sink.get(topic).and_then(|v| v.get("rev")?.as_u64()) {
                Some(rev) => format!("/threads/{thread}/messages?after={rev}"),
                None => format!("/threads/{thread}/messages?limit={PAGE}"),
            },
            _ => return,
        };
        let result = self.call(&addr, "GET", &path, Vec::new(), Vec::new()).await;
        if !self.is_live(topic) {
            return;
        }
        match result {
            Ok(changed) if path.contains("after=") => self.merge_messages(topic, &changed),
            Ok(value) => self.sink.set(topic, Ok(value)),
            Err(error) => {
                if self.sink.get(topic).is_none() {
                    self.sink.set(topic, Err(error));
                }
            }
        }
    }

    /// After the events stream was down: everything it may have missed is read once.
    fn refetch_all(&self, station: &str) {
        let topics = self.live_topics(station, |t| {
            matches!(t, Topic::Overview { .. } | Topic::Sessions { .. } | Topic::Threads { .. } | Topic::Session { .. } | Topic::Thread { .. })
        });
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

    // ── the events stream ──

    /// Opens the station's `/events` if it is not open, or opens it anew when a `host` topic starts or stops
    /// (host samples are asked for with `?host=1` when the stream opens).
    fn sync_events(&self, station: &str) {
        let (addr, host, generation) = {
            let mut stations = self.stations.borrow_mut();
            let Some(s) = stations.get_mut(station) else { return };
            let host = s.wants_host();
            if s.events.as_ref().is_some_and(|(_, asks)| *asks == host) {
                return;
            }
            if let Some((old, _)) = s.events.take()
                && let Some(older) = s.replaced.replace(old)
            {
                older.abort();
            }
            s.generation += 1;
            (s.addr.clone(), host, s.generation)
        };
        let task = self.spawn(self.rc().follow_events(station.to_string(), addr, host, generation));
        if let Some(s) = self.stations.borrow_mut().get_mut(station) {
            s.events = Some((task, host));
        }
    }

    /// Whether this stream is the station's newest; if so, the one it replaces goes now.
    fn took_over(&self, station: &str, generation: u64) -> bool {
        let mut stations = self.stations.borrow_mut();
        let Some(s) = stations.get_mut(station) else { return false };
        if s.generation != generation {
            return false;
        }
        if let Some(old) = s.replaced.take() {
            old.abort();
        }
        true
    }

    fn is_current(&self, station: &str, generation: u64) -> bool {
        self.stations.borrow().get(station).is_some_and(|s| s.generation == generation)
    }

    fn set_stale(&self, station: &str, stale: bool) -> bool {
        self.stations.borrow_mut().get_mut(station).map(|s| std::mem::replace(&mut s.stale, stale)).unwrap_or(false)
    }

    /// Holds the station's `/events` open while any of its topics is live; its events keep the topics current.
    async fn follow_events(self: Rc<Self>, station: String, addr: StationAddr, host: bool, generation: u64) {
        let path = if host { "/events?host=1" } else { "/events" };
        loop {
            // Replaced before it opened: its successor asks instead.
            if !self.is_current(&station, generation) {
                return;
            }
            let opened = self.open_stream(&addr, path).await;
            if !self.took_over(&station, generation) {
                return;
            }
            match opened {
                Ok(mut body) => {
                    self.set_link(&station, json!({ "state": "online" }));
                    // Down for a while: what changed meanwhile was not told.
                    if self.set_stale(&station, false) {
                        self.refetch_all(&station);
                    }
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
                    if !self.is_current(&station, generation) {
                        return;
                    }
                    self.set_stale(&station, true);
                    self.set_link(&station, json!({ "state": "offline", "message": why }));
                }
                Err(error) => {
                    self.set_stale(&station, true);
                    let state = if error.status.is_some() { "error" } else { "offline" };
                    self.set_link(&station, json!({ "state": state, "message": error.message }));
                }
            }
            self.host.sleep(RECONNECT_MS).await;
        }
    }

    fn on_event(&self, station: &str, name: &str, data: &str) {
        let Ok(data) = serde_json::from_str::<Value>(data) else { return };
        match name {
            "session" => self.on_session(station, &data),
            "session-removed" => {
                let Some(key) = data.get("key").and_then(Value::as_str) else { return };
                self.on_session_removed(station, key);
            }
            "thread" => {
                let Some(id) = data.get("id").and_then(Value::as_u64) else { return };
                self.merge_messages(&Topic::Thread { station: station.into(), thread: id }, &data);
                // The summaries (last message, unread) are not in the event.
                self.mark_dirty(station, id);
            }
            "read" => {
                let (Some(thread), Some(seq)) = (data.get("thread").and_then(Value::as_u64), data.get("seq").and_then(Value::as_u64)) else { return };
                self.put_read(station, thread, seq);
            }
            "overview" => self.set_live(Topic::Overview { station: station.into() }, data),
            "host" => self.set_live(Topic::Host { station: station.into() }, data),
            _ => {}
        }
    }

    /// A session's summary changed: it replaces the one in `sessions` and in its `session` topic. The detail's
    /// turns are read again only when the summary says they changed.
    fn on_session(&self, station: &str, summary: &Value) {
        let Some(key) = summary.get("key").and_then(Value::as_str) else { return };
        // `/sessions` lists the shown ones.
        let shown = summary.get("archivedAt").is_none_or(Value::is_null);
        self.sink.update(&Topic::Sessions { station: station.into() }, &mut |list| {
            let Some(list) = list.as_array_mut() else { return };
            match (list.iter().position(|s| s.get("key").and_then(Value::as_str) == Some(key)), shown) {
                (Some(i), true) => list[i] = summary.clone(),
                (Some(i), false) => {
                    list.remove(i);
                }
                (None, true) => list.insert(0, summary.clone()),
                (None, false) => {}
            }
        });
        let topic = Topic::Session { station: station.into(), key: key.into() };
        let mut turns_changed = false;
        self.sink.update(&topic, &mut |detail| {
            turns_changed = !same_turns(detail.get("turns"), summary);
            detail["session"] = summary.clone();
        });
        if turns_changed {
            self.refetch(&topic);
        }
    }

    fn on_session_removed(&self, station: &str, key: &str) {
        self.sink.update(&Topic::Sessions { station: station.into() }, &mut |list| {
            if let Some(list) = list.as_array_mut() {
                list.retain(|s| s.get("key").and_then(Value::as_str) != Some(key));
            }
        });
        let topic = Topic::Session { station: station.into(), key: key.into() };
        if self.is_live(&topic) {
            self.sink.set(&topic, Err(CoreError::new("http_404", "这个会话已经删除了").with_status(404)));
        }
        // Its threads lose it; those left with nobody went with it.
        self.sink.update(&Topic::Threads { station: station.into() }, &mut |list| {
            let Some(list) = list.as_array_mut() else { return };
            for thread in list.iter_mut() {
                if let Some(members) = thread.get_mut("sessions").and_then(Value::as_array_mut) {
                    members.retain(|m| m.get("session").and_then(Value::as_str) != Some(key));
                }
            }
            list.retain(|t| t.get("sessions").and_then(Value::as_array).is_some_and(|m| !m.is_empty()));
        });
    }

    // ── threads ──

    /// Changed messages (an event, or `?after=`) into a thread's topic: replaced by seq, new ones in order. A
    /// change to a message older than the pages loaded waits until that page is.
    fn merge_messages(&self, topic: &Topic, changed: &Value) {
        let messages = changed.get("messages").and_then(Value::as_array).map(Vec::as_slice).unwrap_or_default();
        let rev = changed.get("rev").and_then(Value::as_u64).unwrap_or(0);
        self.sink.update(topic, &mut |value| {
            let more = value.get("more").and_then(Value::as_bool).unwrap_or(false);
            if let Some(list) = value.get_mut("messages").and_then(Value::as_array_mut) {
                let oldest = list.first().and_then(seq_of);
                for message in messages {
                    let Some(seq) = seq_of(message) else { continue };
                    match list.binary_search_by_key(&seq, |m| seq_of(m).unwrap_or(0)) {
                        Ok(i) => list[i] = message.clone(),
                        Err(i) => {
                            if !(more && oldest.is_some_and(|oldest| seq < oldest)) {
                                list.insert(i, message.clone());
                            }
                        }
                    }
                }
            }
            if value.get("rev").and_then(Value::as_u64).is_none_or(|known| rev > known) {
                value["rev"] = json!(rev);
            }
        });
    }

    /// A thread's summary into every live topic that lists it: `threads`, and the `session` topics of the
    /// sessions taking part (a session that left it loses it).
    fn put_thread(&self, station: &str, view: &Value) {
        let Some(id) = view.get("id").and_then(Value::as_u64) else { return };
        let members: Vec<&str> = view.get("sessions").and_then(Value::as_array).into_iter().flatten().filter_map(|m| m.get("session")?.as_str()).collect();
        self.sink.update(&Topic::Threads { station: station.into() }, &mut |list| {
            if let Some(list) = list.as_array_mut() {
                upsert_thread(list, view);
            }
        });
        for topic in self.live_topics(station, |t| matches!(t, Topic::Session { .. })) {
            let Topic::Session { key, .. } = &topic else { continue };
            let member = members.contains(&key.as_str());
            self.sink.update(&topic, &mut |detail| {
                let Some(threads) = detail.get_mut("threads").and_then(Value::as_array_mut) else { return };
                if member {
                    upsert_thread(threads, view);
                } else {
                    threads.retain(|t| t.get("id").and_then(Value::as_u64) != Some(id));
                }
            });
        }
    }

    fn remove_thread(&self, station: &str, id: u64) {
        let drop_it = |list: &mut Value| {
            if let Some(list) = list.as_array_mut() {
                list.retain(|t| t.get("id").and_then(Value::as_u64) != Some(id));
            }
        };
        self.sink.update(&Topic::Threads { station: station.into() }, &mut |list| drop_it(list));
        for topic in self.live_topics(station, |t| matches!(t, Topic::Session { .. })) {
            self.sink.update(&topic, &mut |detail| {
                if let Some(threads) = detail.get_mut("threads") {
                    drop_it(threads);
                }
            });
        }
    }

    /// The viewer read a thread up to `seq`: its read position moves there, and nothing is unread once it
    /// covers the last message (otherwise the count is read again).
    fn put_read(&self, station: &str, thread: u64, seq: u64) {
        let stale = std::cell::Cell::new(false);
        let apply = |list: &mut Value| {
            for t in list.as_array_mut().into_iter().flatten() {
                if t.get("id").and_then(Value::as_u64) != Some(thread) || t.get("read").and_then(Value::as_u64).is_some_and(|read| read >= seq) {
                    continue;
                }
                t["read"] = json!(seq);
                if t.get("last").and_then(seq_of).is_none_or(|last| seq >= last) {
                    t["unread"] = json!(0);
                } else {
                    stale.set(true);
                }
            }
        };
        self.sink.update(&Topic::Threads { station: station.into() }, &mut |list| apply(list));
        for topic in self.live_topics(station, |t| matches!(t, Topic::Session { .. })) {
            self.sink.update(&topic, &mut |detail| {
                if let Some(threads) = detail.get_mut("threads") {
                    apply(threads);
                }
            });
        }
        if stale.get() {
            self.mark_dirty(station, thread);
        }
    }

    /// How far the viewer has read a thread, as a live topic lists it.
    fn read_position(&self, station: &str, thread: u64) -> Option<u64> {
        let find = |list: Option<&Value>| {
            list?.as_array()?.iter().find(|t| t.get("id").and_then(Value::as_u64) == Some(thread))?.get("read")?.as_u64()
        };
        let lists = self.live_topics(station, |t| matches!(t, Topic::Threads { .. } | Topic::Session { .. }));
        lists.iter().filter_map(|topic| {
            let value = self.sink.get(topic)?;
            match topic {
                Topic::Session { .. } => find(value.get("threads")),
                _ => find(Some(&value)),
            }
        }).max()
    }

    /// Reads a thread's summary again once the burst of events is over, if a live topic lists threads.
    fn mark_dirty(&self, station: &str, thread: u64) {
        let schedule = {
            let mut stations = self.stations.borrow_mut();
            let Some(s) = stations.get_mut(station) else { return };
            if !s.topics.iter().any(|t| matches!(t, Topic::Threads { .. } | Topic::Session { .. })) {
                return;
            }
            s.dirty.insert(thread);
            !std::mem::replace(&mut s.flushing, true)
        };
        if schedule {
            let this = self.rc();
            let station = station.to_string();
            let sleep = self.host.sleep(EVENTS_COALESCE_MS);
            self.spawn(async move {
                sleep.await;
                this.flush_threads(&station).await;
            });
        }
    }

    async fn flush_threads(&self, station: &str) {
        let (dirty, addr) = {
            let mut stations = self.stations.borrow_mut();
            let Some(s) = stations.get_mut(station) else { return };
            s.flushing = false;
            (std::mem::take(&mut s.dirty), s.addr.clone())
        };
        join_all(dirty.into_iter().map(|id| {
            let addr = addr.clone();
            async move {
                match self.call(&addr, "GET", &format!("/threads/{id}"), Vec::new(), Vec::new()).await {
                    Ok(view) => self.put_thread(station, &view),
                    Err(error) if error.status == Some(404) => self.remove_thread(station, id),
                    Err(_) => {}
                }
            }
        }))
        .await;
    }

    // ── chats ──

    /// A person's message into a thread. Answers its seq once the thread's topic, where live, holds it.
    pub async fn post(&self, station: &StationAddr, thread: u64, message: Value) -> Result<u64> {
        let answer = self.json(station, "POST", &format!("/threads/{thread}/messages"), Some(message)).await?;
        let seq = answer.get("seq").and_then(Value::as_u64).ok_or_else(|| CoreError::new("bad_response", "station 的回复里没有消息序号"))?;
        let topic = Topic::Thread { station: station.to_string(), thread };
        let has = |v: &Value| v.get("messages").and_then(Value::as_array).is_some_and(|m| m.iter().any(|m| seq_of(m) == Some(seq)));
        if self.sink.get(&topic).is_some_and(|v| !has(&v)) {
            self.reload(&topic).await;
        }
        Ok(seq)
    }

    /// The page of messages before those loaded, into the thread's topic. Answers whether still older ones exist.
    pub async fn older(&self, station: &StationAddr, thread: u64) -> Result<bool> {
        let topic = Topic::Thread { station: station.to_string(), thread };
        let Some(value) = self.sink.get(&topic) else { return Ok(false) };
        let first = value.get("messages").and_then(Value::as_array).and_then(|m| m.first()).and_then(seq_of);
        let (Some(before), true) = (first, value.get("more").and_then(Value::as_bool).unwrap_or(false)) else { return Ok(false) };
        let page = self.json(station, "GET", &format!("/threads/{thread}/messages?before={before}&limit={PAGE}"), None).await?;
        let older: Vec<Value> = page.get("messages").and_then(Value::as_array).into_iter().flatten().filter(|m| seq_of(m).is_some_and(|s| s < before)).cloned().collect();
        let more = page.get("more").and_then(Value::as_bool).unwrap_or(false);
        let mut still = false;
        self.sink.update(&topic, &mut |value| {
            let Some(list) = value.get_mut("messages").and_then(Value::as_array_mut) else { return };
            // Another page came first: this one is not next to what is loaded any more.
            if list.first().and_then(seq_of) != Some(before) {
                still = value.get("more").and_then(Value::as_bool).unwrap_or(false);
                return;
            }
            list.splice(0..0, older.iter().cloned());
            value["more"] = json!(more);
            still = more;
        });
        Ok(still)
    }

    /// Records how far the viewer has read a thread; nothing is sent when it is read that far already.
    pub async fn read(&self, station: &StationAddr, thread: u64, seq: u64) -> Result<()> {
        let name = station.to_string();
        if self.read_position(&name, thread).is_some_and(|read| read >= seq) {
            return Ok(());
        }
        let answer = self.json(station, "PUT", &format!("/threads/{thread}/read"), Some(json!({ "seq": seq }))).await?;
        self.put_read(&name, thread, answer.get("seq").and_then(Value::as_u64).unwrap_or(seq));
        Ok(())
    }

    // ── live ──

    /// Holds `/sessions/:key/live` open: the transcript from its first entry, then as it grows, and the steps in
    /// flight. A reconnect asks from the entries already here.
    async fn follow_live(self: Rc<Self>, station: String, addr: StationAddr, key: String) {
        let topic = Topic::Live { station: station.clone(), key: key.clone() };
        self.sink.set(&topic, Ok(live_start()));
        loop {
            let from = self.sink.get(&topic).and_then(|v| v.get("timeline")?.as_array().map(Vec::len)).unwrap_or(0);
            let path = format!("/sessions/{}/live?from={from}", encode(&key));
            let mut gap = false;
            if let Ok(mut body) = self.open_stream(&addr, &path).await {
                let mut parser = SseParser::default();
                'read: while let Some(Ok(bytes)) = body.next().await {
                    for (_, data) in parser.feed(&bytes) {
                        if let Ok(message) = serde_json::from_str::<Value>(&data)
                            && !self.on_live(&station, &key, &message)
                        {
                            gap = true;
                            break 'read;
                        }
                    }
                }
            }
            if gap {
                // Entries that cannot be placed: start over from the first.
                if let Some(s) = self.stations.borrow_mut().get_mut(&station).and_then(|s| s.lives.get_mut(&key)) {
                    *s = LiveView::default();
                }
                self.sink.set(&topic, Ok(live_start()));
            } else {
                self.host.sleep(RECONNECT_MS).await;
            }
        }
    }

    /// One message of the live stream into the topic; false when its entries leave a gap.
    fn on_live(&self, station: &str, key: &str, message: &Value) -> bool {
        let topic = Topic::Live { station: station.into(), key: key.into() };
        let now = self.host.now_ms();
        let kind = message.get("type").and_then(Value::as_str).unwrap_or("");
        let mut entries_came = false;
        if kind == "timeline" {
            let start = message.get("start").and_then(Value::as_u64).unwrap_or(0) as usize;
            let entries = message.get("entries").and_then(Value::as_array).map(Vec::as_slice).unwrap_or_default();
            let mut placed = false;
            self.sink.update(&topic, &mut |live| {
                let Some(timeline) = live.get_mut("timeline").and_then(Value::as_array_mut) else { return };
                if start > timeline.len() {
                    return;
                }
                timeline.truncate(start);
                timeline.extend(entries.iter().cloned());
                live["usage"] = message.get("usage").cloned().unwrap_or(Value::Null);
                placed = true;
            });
            if !placed {
                return false;
            }
            entries_came = !entries.is_empty();
        }
        let view = {
            let mut stations = self.stations.borrow_mut();
            let Some(view) = stations.get_mut(station).and_then(|s| s.lives.get_mut(key)) else { return true };
            match kind {
                // Ended steps stay until the entries that record them arrive.
                "timeline" if entries_came => view.steps.retain(|s| s.get("ended") != Some(&Value::Bool(true))),
                "steps" => {
                    view.steps = message.get("steps").and_then(Value::as_array).cloned().unwrap_or_default();
                    view.phase = message.get("phase").filter(|p| !p.is_null()).map(|p| {
                        let elapsed = p.get("elapsedMs").and_then(Value::as_f64).unwrap_or(0.0);
                        json!({ "phase": p.get("phase").cloned().unwrap_or(Value::Null), "since": now - elapsed })
                    });
                }
                "clear" => *view = LiveView::default(),
                "step" => {
                    let Some(event) = message.get("event") else { return true };
                    apply_step(view, event, now);
                }
                _ => return true,
            }
            view.clone()
        };
        self.sink.update(&topic, &mut |live| {
            live["steps"] = json!(view.steps);
            live["phase"] = json!(view.phase);
            // The stream sends the steps right after the entries it has: the transcript is all here.
            if kind == "steps" {
                live["loaded"] = json!(true);
            }
        });
        true
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
        let fresh = {
            let mut stations = self.stations.borrow_mut();
            let state = stations.entry(station.clone()).or_insert_with(|| StationState::new(addr.clone()));
            state.topics.insert(topic.clone())
        };
        if !fresh {
            return;
        }
        match topic {
            Topic::Link { .. } => {
                // The state as it is when this runs: the events stream may have moved on.
                let (this, station) = (self.rc(), station.clone());
                self.spawn(async move {
                    let link = this.stations.borrow().get(&station).map(|s| s.link.clone());
                    if let Some(link) = link {
                        this.set_link(&station, link);
                    }
                });
            }
            Topic::Overview { .. } | Topic::Sessions { .. } | Topic::Threads { .. } | Topic::Session { .. } | Topic::Thread { .. } => self.refetch(topic),
            // Samples come on the events stream, which asks for them now.
            Topic::Host { .. } => {}
            Topic::Live { key, .. } => {
                if let Some(s) = self.stations.borrow_mut().get_mut(&station) {
                    s.lives.insert(key.clone(), LiveView::default());
                }
                let task = self.spawn(self.rc().follow_live(station.clone(), addr, key.clone()));
                if let Some(s) = self.stations.borrow_mut().get_mut(&station) {
                    s.tasks.insert(topic.clone(), task);
                }
            }
            _ => {}
        }
        self.sync_events(&station);
    }

    fn stop(&self, topic: &Topic) {
        let Some(station) = topic.station() else { return };
        {
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
                for task in state.events.take().map(|(t, _)| t).into_iter().chain(state.replaced.take()) {
                    task.abort();
                }
                for (_, task) in state.tasks.drain() {
                    task.abort();
                }
                stations.remove(station);
                return;
            }
        }
        self.sync_events(station);
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
            let (_, tx) = streams.iter().rev().find(|(p, tx)| p.starts_with(prefix) && !tx.is_closed()).expect("stream open");
            tx.unbounded_send(Ok(text.as_bytes().to_vec())).unwrap();
        }
        fn event(&self, name: &str, data: Value) {
            self.push("/admin/api/events", &format!("event: {name}\ndata: {data}\n\n"));
        }
        fn end(&self, prefix: &str) {
            let mut streams = self.streams.borrow_mut();
            streams.retain(|(p, _)| !p.starts_with(prefix));
        }
        /// Paths of the streams still open (the core has not let go of them).
        fn open(&self) -> Vec<String> {
            self.streams.borrow().iter().filter(|(_, tx)| !tx.is_closed()).map(|(p, _)| p.clone()).collect()
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
    fn threads() -> Topic {
        Topic::Threads { station: ST.into() }
    }
    fn thread(id: u64) -> Topic {
        Topic::Thread { station: ST.into(), thread: id }
    }
    fn overview() -> Topic {
        Topic::Overview { station: ST.into() }
    }
    fn host_topic() -> Topic {
        Topic::Host { station: ST.into() }
    }
    fn link() -> Topic {
        Topic::Link { station: ST.into() }
    }
    fn remote() -> StationAddr {
        StationAddr::parse(ST).unwrap()
    }
    fn live_of(sink: &FakeSink, key: &str) -> Value {
        sink.get(&live(key)).unwrap()
    }
    fn msg(value: Value) -> String {
        format!("event: {}\ndata: {}\n\n", value["type"].as_str().unwrap(), value)
    }
    fn summary(key: &str, turns: u64) -> Value {
        json!({"key": key, "title": null, "archivedAt": null, "turns": turns, "lastTurn": null})
    }
    fn message(seq: u64, text: &str) -> Value {
        json!({"seq": seq, "rev": seq, "thread": 7, "ts": format!("{seq}.0"), "authorKind": "person", "author": "a@x.com", "text": text})
    }
    fn thread_view(id: u64, members: &[&str], last: u64, read: u64, unread: u64) -> Value {
        json!({"id": id, "surface": "ember", "createdAt": id, "sessions": members.iter().map(|s| json!({"thread": id, "session": s})).collect::<Vec<_>>(),
            "last": if last > 0 { message(last, "…") } else { Value::Null }, "rev": last, "read": read, "unread": unread})
    }
    fn texts(sink: &FakeSink, id: u64) -> Vec<String> {
        sink.get(&thread(id)).unwrap()["messages"].as_array().unwrap().iter().map(|m| m["text"].as_str().unwrap().to_string()).collect()
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
    fn writes_bring_what_they_touch_up_to_date() {
        run(async {
            let (host, sink, wire, stations) = setup();
            wire.answer("GET /admin/api/sessions/k%201", 200, json!({"session": summary("k 1", 0), "threads": [], "turns": []}));
            wire.answer("GET /admin/api/threads", 200, json!([]));
            for t in [session("k 1"), session("other"), sessions(), overview(), threads()] {
                stations.start(&t);
            }
            host.settle().await;
            assert!(sink.get(&session("k 1")).is_some());
            let before = |p: &str| wire.count("GET", p);
            let (s, k, o, other) = (before("/admin/api/sessions"), before("/admin/api/sessions/k%201"), before("/admin/api/overview"), before("/admin/api/sessions/other"));
            stations.request(&remote(), "POST", "/sessions/k%201/stop", None).await.unwrap();
            assert_eq!(wire.count("GET", "/admin/api/sessions"), s + 1);
            assert_eq!(wire.count("GET", "/admin/api/sessions/k%201"), k + 1);
            assert_eq!(wire.count("GET", "/admin/api/sessions/other"), other);
            assert_eq!(wire.count("GET", "/admin/api/overview"), o);
            // A profile edit answers the overview: that is the topic's value, nothing is read again.
            let edited = json!({"viewer": {}, "connects": [], "profiles": [{"id": "p"}]});
            wire.answer("PUT /admin/api/profiles/p", 200, edited.clone());
            stations.request(&remote(), "PUT", "/profiles/p", Some(json!({}))).await.unwrap();
            assert_eq!(sink.get(&overview()), Some(edited));
            assert_eq!(wire.count("GET", "/admin/api/overview"), o);
            stations.request(&remote(), "POST", "/profiles/p/check", None).await.unwrap();
            assert_eq!(wire.count("GET", "/admin/api/overview"), o + 1);
            // Another chat on a session answers its thread, which goes into the lists without a request.
            let reads = wire.calls.borrow().len();
            wire.answer("POST /admin/api/threads", 200, thread_view(9, &["k 1"], 0, 0, 0));
            stations.request(&remote(), "POST", "/threads", Some(json!({"session": "k 1"}))).await.unwrap();
            assert_eq!(sink.get(&session("k 1")).unwrap()["threads"][0]["id"], 9);
            assert_eq!(sink.get(&threads()).unwrap()[0]["id"], 9);
            assert_eq!(wire.calls.borrow().len(), reads + 1);
            // A read changes nothing.
            stations.request(&remote(), "GET", "/slack/config-token", None).await.unwrap();
            assert_eq!(wire.count("GET", "/admin/api/overview"), o + 1);
        });
    }

    #[test]
    fn topics_are_read_once_and_nothing_runs_on_a_timer() {
        run(async {
            let (host, _sink, wire, stations) = setup();
            for t in [session("a"), sessions(), overview(), threads(), thread(7), host_topic(), link(), live("a")] {
                stations.start(&t);
            }
            host.settle().await;
            assert_eq!(wire.open(), vec!["/admin/api/events?host=1", "/admin/api/sessions/a/live?from=0"]);
            let requests = wire.calls.borrow().len();
            assert_eq!(requests, 7, "{:?}", wire.paths());
            host.sleeps.borrow_mut().clear();
            wait(RECONNECT_MS * 2).await;
            assert_eq!(wire.calls.borrow().len(), requests, "idle: no request");
            assert!(host.sleeps.borrow().is_empty(), "idle: no timer {:?}", host.sleeps.borrow());
        });
    }

    #[test]
    fn session_events_update_in_place() {
        run(async {
            let (host, sink, wire, stations) = setup();
            wire.answer("GET /admin/api/sessions", 200, json!([summary("a", 1), summary("b", 0)]));
            wire.answer("GET /admin/api/sessions/a", 200, json!({"session": summary("a", 1), "threads": [], "turns": [{"id": "t1", "kind": "chat", "outcome": null, "declared": null, "detail": null, "startedAt": 1, "endedAt": null}]}));
            stations.start(&sessions());
            stations.start(&session("a"));
            host.settle().await;
            let reads = wire.calls.borrow().len();
            // The same turns: only the summary changes, without a request.
            let mut renamed = summary("a", 1);
            renamed["title"] = json!("新名字");
            renamed["lastTurn"] = json!({"kind": "chat", "outcome": null, "declared": null, "detail": null, "startedAt": 1, "endedAt": null});
            wire.event("session", renamed.clone());
            wire.event("session", summary("c", 0));
            host.settle().await;
            assert_eq!(wire.calls.borrow().len(), reads);
            let list = sink.get(&sessions()).unwrap();
            let keys: Vec<&str> = list.as_array().unwrap().iter().map(|s| s["key"].as_str().unwrap()).collect();
            assert_eq!(keys, vec!["c", "a", "b"]);
            assert_eq!(list[1]["title"], "新名字");
            assert_eq!(sink.get(&session("a")).unwrap()["session"]["title"], "新名字");
            // The turn ended: the detail's turns are read again.
            let mut ended = renamed.clone();
            ended["lastTurn"]["endedAt"] = json!(2);
            wire.event("session", ended);
            host.settle().await;
            assert_eq!(wire.count("GET", "/admin/api/sessions/a"), 2);
            // Archived: gone from the list. Removed: gone, and its topic says so.
            let mut archived = summary("b", 0);
            archived["archivedAt"] = json!(5);
            wire.event("session", archived);
            wire.event("session-removed", json!({"key": "a"}));
            host.settle().await;
            let keys: Vec<String> = sink.get(&sessions()).unwrap().as_array().unwrap().iter().map(|s| s["key"].as_str().unwrap().to_string()).collect();
            assert_eq!(keys, vec!["c"]);
            assert_eq!(sink.values.borrow()[&session("a")].as_ref().unwrap_err().status, Some(404));
        });
    }

    #[test]
    fn overview_and_host_come_from_events() {
        run(async {
            let (host, sink, wire, stations) = setup();
            stations.start(&overview());
            host.settle().await;
            assert_eq!(wire.open(), vec!["/admin/api/events"]);
            wire.event("overview", json!({"connects": [1]}));
            wire.event("host", json!({"hostname": "not asked"}));
            host.settle().await;
            assert_eq!(sink.get(&overview()), Some(json!({"connects": [1]})));
            assert_eq!(sink.get(&host_topic()), None);
            // Host samples are asked for while a host topic is live: the stream opens anew with ?host=1, and the old one goes once it has.
            stations.start(&host_topic());
            host.settle().await;
            assert_eq!(wire.open(), vec!["/admin/api/events?host=1"]);
            wire.event("host", json!({"hostname": "studio"}));
            host.settle().await;
            assert_eq!(sink.get(&host_topic()), Some(json!({"hostname": "studio"})));
            assert_eq!(wire.count("GET", "/admin/api/overview"), 1, "a handover is no reconnect: nothing is read again");
            stations.stop(&host_topic());
            host.settle().await;
            assert_eq!(wire.open(), vec!["/admin/api/events"]);
            assert_eq!(wire.count("GET", "/admin/api/host"), 0);
        });
    }

    #[test]
    fn thread_events_merge_messages_and_refresh_summaries() {
        run(async {
            let (host, sink, wire, stations) = setup();
            wire.answer("GET /admin/api/threads/7/messages?limit=50", 200, json!({"rev": 12, "messages": [message(11, "a"), message(12, "b")], "more": true}));
            wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 12, 12, 0)]));
            wire.answer("GET /admin/api/threads/7", 200, thread_view(7, &["k"], 14, 12, 2));
            wire.answer("GET /admin/api/threads/8", 200, thread_view(8, &["k"], 20, 0, 1));
            stations.start(&thread(7));
            stations.start(&threads());
            host.settle().await;
            assert_eq!(texts(&sink, 7), vec!["a", "b"]);
            // New messages and an edit, in one burst: merged at once; the summary is read once after it.
            wire.event("thread", json!({"id": 7, "rev": 13, "messages": [message(13, "c")]}));
            wire.event("thread", json!({"id": 7, "rev": 15, "messages": [message(14, "d"), {"seq": 12, "rev": 15, "text": "b 改了"}]}));
            // Older than the page, while older pages exist: not placed.
            wire.event("thread", json!({"id": 7, "rev": 16, "messages": [message(3, "old")]}));
            host.settle().await;
            assert_eq!(texts(&sink, 7), vec!["a", "b 改了", "c", "d"]);
            assert_eq!(sink.get(&thread(7)).unwrap()["rev"], 16);
            assert_eq!(wire.count("GET", "/admin/api/threads/7"), 0, "waits for the burst to end");
            wait(EVENTS_COALESCE_MS).await;
            assert_eq!(wire.count("GET", "/admin/api/threads/7"), 1);
            assert_eq!(sink.get(&threads()).unwrap()[0]["unread"], 2);
            // A thread not listed yet comes in, first (its last message is the newest).
            wire.event("thread", json!({"id": 8, "rev": 20, "messages": [message(20, "x")]}));
            host.settle().await;
            wait(EVENTS_COALESCE_MS).await;
            let ids: Vec<u64> = sink.get(&threads()).unwrap().as_array().unwrap().iter().map(|t| t["id"].as_u64().unwrap()).collect();
            assert_eq!(ids, vec![8, 7]);
            // Reading up to the last message: nothing unread, without a request. Short of it: counted again.
            wire.event("read", json!({"viewer": "a@x.com", "thread": 7, "seq": 14}));
            host.settle().await;
            assert_eq!(sink.get(&threads()).unwrap()[1]["unread"], 0);
            assert_eq!(sink.get(&threads()).unwrap()[1]["read"], 14);
            wire.event("read", json!({"viewer": "a@x.com", "thread": 8, "seq": 15}));
            host.settle().await;
            wait(EVENTS_COALESCE_MS).await;
            assert_eq!(wire.count("GET", "/admin/api/threads/8"), 2);
            // A thread gone: out of the list.
            wire.answer("GET /admin/api/threads/8", 404, json!({"error": "unknown thread 8"}));
            wire.event("thread", json!({"id": 8, "rev": 21, "messages": []}));
            host.settle().await;
            wait(EVENTS_COALESCE_MS).await;
            assert_eq!(sink.get(&threads()).unwrap().as_array().unwrap().len(), 1);
        });
    }

    #[test]
    fn a_session_topic_follows_its_threads() {
        run(async {
            let (host, sink, wire, stations) = setup();
            wire.answer("GET /admin/api/sessions/k", 200, json!({"session": summary("k", 0), "threads": [thread_view(7, &["k"], 12, 0, 1)], "turns": []}));
            wire.answer("GET /admin/api/threads/9", 200, thread_view(9, &["k", "j"], 30, 0, 1));
            stations.start(&session("k"));
            host.settle().await;
            wire.event("thread", json!({"id": 9, "rev": 30, "messages": []}));
            wire.event("read", json!({"viewer": "a@x.com", "thread": 7, "seq": 12}));
            host.settle().await;
            wait(EVENTS_COALESCE_MS).await;
            let detail = sink.get(&session("k")).unwrap();
            let ids: Vec<u64> = detail["threads"].as_array().unwrap().iter().map(|t| t["id"].as_u64().unwrap()).collect();
            assert_eq!(ids, vec![9, 7]);
            assert_eq!(detail["threads"][1]["unread"], 0);
            // The session left thread 9.
            wire.answer("GET /admin/api/threads/9", 200, thread_view(9, &["j"], 30, 0, 1));
            wire.event("thread", json!({"id": 9, "rev": 31, "messages": []}));
            host.settle().await;
            wait(EVENTS_COALESCE_MS).await;
            assert_eq!(sink.get(&session("k")).unwrap()["threads"].as_array().unwrap().len(), 1);
        });
    }

    #[test]
    fn a_thread_pages_back_and_catches_up() {
        run(async {
            let (host, sink, wire, stations) = setup();
            wire.answer("GET /admin/api/threads/7/messages?limit=50", 200, json!({"rev": 12, "messages": [message(11, "c"), message(12, "d")], "more": true}));
            wire.answer("GET /admin/api/threads/7/messages?before=11&limit=50", 200, json!({"rev": 12, "messages": [message(9, "a"), message(10, "b")], "more": false}));
            stations.start(&thread(7));
            stations.start(&link());
            host.settle().await;
            assert!(stations.older(&remote(), 7).await.unwrap() == false);
            assert_eq!(texts(&sink, 7), vec!["a", "b", "c", "d"]);
            assert_eq!(sink.get(&thread(7)).unwrap()["more"], false);
            // Nothing older: no request.
            assert!(!stations.older(&remote(), 7).await.unwrap());
            assert_eq!(wire.count("GET", "/admin/api/threads/7/messages?before=9&limit=50"), 0);
            // The stream was down: what changed since the thread's rev is read, and the pages stay.
            wire.answer("GET /admin/api/threads/7/messages?after=12", 200, json!({"rev": 13, "messages": [message(13, "e")], "more": false}));
            wire.end("/admin/api/events");
            host.settle().await;
            assert_eq!(sink.get(&link()).unwrap()["state"], "offline");
            wait(RECONNECT_MS + 50).await;
            assert_eq!(sink.get(&link()).unwrap()["state"], "online");
            assert_eq!(texts(&sink, 7), vec!["a", "b", "c", "d", "e"]);
            assert_eq!(wire.count("GET", "/admin/api/threads/7/messages?limit=50"), 1);
        });
    }

    #[test]
    fn posts_into_a_thread_and_answers_once_it_shows() {
        run(async {
            let (host, sink, wire, stations) = setup();
            wire.answer("GET /admin/api/threads/7/messages?limit=50", 200, json!({"rev": 12, "messages": [message(12, "d")], "more": false}));
            wire.answer("POST /admin/api/threads/7/messages", 200, json!({"seq": 13}));
            wire.answer("GET /admin/api/threads/7/messages?after=12", 200, json!({"rev": 13, "messages": [message(13, "你好")], "more": false}));
            stations.start(&thread(7));
            host.settle().await;
            assert_eq!(stations.post(&remote(), 7, json!({"text": "你好"})).await.unwrap(), 13);
            assert_eq!(texts(&sink, 7), vec!["d", "你好"]);
            // Reading: sent once, not again for less.
            stations.start(&threads());
            wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 13, 0, 1)]));
            host.settle().await;
            wire.answer("PUT /admin/api/threads/7/read", 200, json!({"viewer": "a@x.com", "thread": 7, "seq": 13}));
            stations.read(&remote(), 7, 13).await.unwrap();
            stations.read(&remote(), 7, 12).await.unwrap();
            assert_eq!(wire.count("PUT", "/admin/api/threads/7/read"), 1);
            assert_eq!(sink.get(&threads()).unwrap()[0]["unread"], 0);
        });
    }

    #[test]
    fn events_reconnect_report_the_link_and_read_everything_once() {
        run(async {
            let (host, sink, wire, stations) = setup();
            stations.start(&link());
            stations.start(&sessions());
            host.settle().await;
            assert_eq!(sink.get(&link()).unwrap()["state"], "online");
            *wire.stream_status.borrow_mut() = None;
            wire.end("/admin/api/events");
            host.settle().await;
            assert_eq!(sink.get(&link()).unwrap()["state"], "offline");
            wait(RECONNECT_MS + 50).await;
            assert_eq!(sink.get(&link()).unwrap(), json!({"state": "offline", "message": "连不上"}));
            *wire.stream_status.borrow_mut() = Some(403);
            wait(RECONNECT_MS + 50).await;
            assert_eq!(sink.get(&link()).unwrap(), json!({"state": "error", "message": "没有权限"}));
            let s = wire.count("GET", "/admin/api/sessions");
            *wire.stream_status.borrow_mut() = Some(200);
            wait(RECONNECT_MS + 50).await;
            assert_eq!(sink.get(&link()).unwrap()["state"], "online");
            assert_eq!(wire.count("GET", "/admin/api/sessions"), s + 1, "a reconnect reads the station's topics once");
            // Nothing live: the stream closes and stays closed.
            stations.stop(&link());
            stations.stop(&sessions());
            let e = wire.count("GET", "/admin/api/events");
            wait(RECONNECT_MS + 100).await;
            assert_eq!(wire.count("GET", "/admin/api/events"), e);
            assert!(wire.open().is_empty());
        });
    }

    #[test]
    fn live_holds_the_transcript_and_its_usage() {
        run(async {
            let (host, sink, wire, stations) = setup();
            stations.start(&live("k"));
            host.settle().await;
            assert_eq!(live_of(&sink, "k"), live_start());
            assert!(wire.paths().contains(&"GET /admin/api/sessions/k/live?from=0".to_string()));
            let push = |v: Value| wire.push("/admin/api/sessions/k/live", &msg(v));
            push(json!({"type": "timeline", "start": 0, "entries": ["a", "b"], "usage": {"modelCalls": 1, "model": "claude-opus"}}));
            push(json!({"type": "steps", "steps": [], "phase": null}));
            host.settle().await;
            let v = live_of(&sink, "k");
            assert_eq!((v["loaded"].clone(), v["timeline"].clone(), v["usage"]["model"].clone()), (json!(true), json!(["a", "b"]), json!("claude-opus")));
            push(json!({"type": "timeline", "start": 2, "entries": ["c"], "usage": {"modelCalls": 2}}));
            host.settle().await;
            assert_eq!(live_of(&sink, "k")["timeline"], json!(["a", "b", "c"]));
            assert_eq!(live_of(&sink, "k")["usage"]["modelCalls"], 2);
            // Overlap: replaced from `start`.
            push(json!({"type": "timeline", "start": 1, "entries": ["B", "c", "d"], "usage": {}}));
            host.settle().await;
            assert_eq!(live_of(&sink, "k")["timeline"], json!(["a", "B", "c", "d"]));
            // Reconnects ask from what is known.
            wire.end("/admin/api/sessions/k/live");
            wait(RECONNECT_MS + 50).await;
            assert!(wire.paths().contains(&"GET /admin/api/sessions/k/live?from=4".to_string()), "{:?}", wire.paths());
            // A gap: from the start again, at once.
            wire.push("/admin/api/sessions/k/live", &msg(json!({"type": "timeline", "start": 9, "entries": ["z"], "usage": {}})));
            host.settle().await;
            assert_eq!(wire.count("GET", "/admin/api/sessions/k/live?from=0"), 2);
            assert_eq!(live_of(&sink, "k")["loaded"], false);
        });
    }

    #[test]
    fn live_steps_and_phase() {
        run(async {
            let (host, sink, wire, stations) = setup();
            stations.start(&live("k"));
            host.settle().await;
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
            let v = live_of(&sink, "k");
            assert_eq!((v["steps"].clone(), v["phase"].clone(), v["timeline"].clone()), (json!([]), Value::Null, json!(["x"])));
        });
    }

    #[test]
    fn bad_station_and_failed_fetches_are_errors() {
        run(async {
            let (host, sink, wire, stations) = setup();
            let bad = Topic::Overview { station: "nope".into() };
            stations.start(&bad);
            wire.answer("GET /admin/api/sessions", 502, json!({"error": "坏了"}));
            stations.start(&sessions());
            host.settle().await;
            assert_eq!(sink.values.borrow()[&bad].as_ref().unwrap_err().code, "invalid_params");
            assert_eq!(sink.values.borrow()[&sessions()].as_ref().unwrap_err().message, "坏了");
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
