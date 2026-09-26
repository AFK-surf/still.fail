//! Stations' admin API, over a mesh link (or plain HTTP for `local`), and the
//! station topics: overview, sessions, threads, chat rows, session, thread, live, host, link.
//!
//! While any topic of a station is live, its `/admin/api/events` stream is held
//! open and is all that keeps the topics current: each topic is read once when
//! it starts, and again only after the stream was down. Events carry what
//! changed (a session's summary, a thread's new entries, a read position, a
//! row of the viewer's sidebar, the overview, host samples), which goes into
//! the topics as it is; what an event does not carry (a thread's unread count)
//! is read for that one thing. Host samples are asked for (`?host=1`) only
//! while a `host` topic is live. A
//! `live` topic is followed on the station's `/events` (`?live=<key>&from=<entries known>`): the
//! transcript from its first entry and then as it grows, the steps in flight
//! and the phase. Nothing here runs on a timer but reconnects.
//!
//! A thread's entries and a session's transcript never change once written, so
//! they are kept on the device ([`Kept`]): a `thread` topic shows what is kept
//! at once and asks only for the entries after it (`?after=`), filling any gap
//! an event shows (`?from=&to=`); a `live` topic starts from the kept
//! transcript. Merging a thread's entries into messages is the `chat` view's
//! (entries.rs).

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::future::Future;
use std::rc::{Rc, Weak};

use futures::future::{AbortHandle, Abortable, LocalBoxFuture, join_all};
use futures::stream::LocalBoxStream;
use futures::{FutureExt, StreamExt};
use serde_json::{Value, json};

use crate::entries::n_of;
use crate::error::{CoreError, Result};
use crate::host::{Host, HttpRequest};
use crate::kept::{Kept, Log};
use crate::mesh::{GrantSource, Mesh, RequestHead};
use crate::protocol::Topic;
use crate::store::{Source, Store};
use crate::trace::{Kind, Span, SpanContext, Tracer, route};

/// How long a failed or ended stream waits before it is opened again.
pub const RECONNECT_MS: u64 = 2_000;
/// A station's streams carry a keepalive every 25 s; one silent this long is on a link that is gone though nothing
/// said so, and is read again (from where it was).
pub const STREAM_IDLE_MS: u64 = 40_000;
/// A burst of `thread` events becomes one read of each thread's summary.
pub const EVENTS_COALESCE_MS: u64 = 400;
/// Entries per page of a thread.
pub const PAGE: u64 = 50;
/// How many of a station's chats (the latest active) are brought onto the device ahead of being opened.
const WARM_CHATS: usize = 30;
/// The pause between two of them.
const WARM_GAP_MS: u64 = 150;

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
    /// How it came, when the wire knows: `relay` or `direct` over the mesh, `local` over the page's HTTP.
    pub via: Option<&'static str>,
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
                Ok(WireReply { status: r.status, headers: r.headers, body: r.body.map(|c| c.map_err(CoreError::from)).boxed_local(), via: Some("local") })
            }
            .boxed_local()
        } else {
            let answer = self.host.fetch(request);
            async move {
                let r = answer.await?;
                Ok(WireReply { status: r.status, headers: r.headers, body: futures::stream::iter([Ok(r.body)]).boxed_local(), via: Some("local") })
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
            Ok(WireReply { status, headers, body: body.boxed_local(), via: link.path() })
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
    /// The `/events` stream, and what it was opened for.
    events: Option<(AbortHandle, EventsFor)>,
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
    /// Threads whose gap is being read, with the entries that came meanwhile.
    gaps: HashMap<u64, Vec<Value>>,
    flushing: bool,
    link: Value,
    /// Its chats were brought onto the device once (see `warm`).
    warmed: bool,
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
            gaps: HashMap::new(),
            flushing: false,
            link: json!({ "state": "connecting" }),
            warmed: false,
        }
    }

    fn wants_host(&self) -> bool {
        self.topics.iter().any(|t| matches!(t, Topic::Host { .. }))
    }
}

/// What a station's `/events` stream is opened for, besides what every stream carries: host samples, and the
/// sessions followed as they run (their transcript, steps and phase come on the same stream, in the one order with
/// the messages).
#[derive(Clone, Debug, Default, PartialEq)]
struct EventsFor {
    host: bool,
    live: Vec<String>,
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

/// A `thread` topic's value: the entries loaded, `first ..= last` (none of an empty thread: `last` is `first - 1`),
/// and the thread's summary and sidebar title as kept, for the `chat` view to show before the station's `threads`
/// and rows are read.
fn thread_value(first: u64, entries: Vec<Value>, summary: Value, title: Value) -> Value {
    let last = first + entries.len() as u64 - 1;
    json!({ "first": first, "last": last, "entries": entries, "thread": summary, "title": title })
}

/// A station stream that ends (with an error) when nothing, not even its keepalive, came for [`STREAM_IDLE_MS`].
fn idle_guarded(host: Rc<dyn Host>, body: LocalBoxStream<'static, Result<Vec<u8>>>) -> LocalBoxStream<'static, Result<Vec<u8>>> {
    futures::stream::unfold(Some(body), move |body| {
        let host = host.clone();
        async move {
            let mut body = body?;
            match futures::future::select(body.next(), host.sleep(STREAM_IDLE_MS)).await {
                futures::future::Either::Left((Some(item), _)) => Some((item, Some(body))),
                futures::future::Either::Left((None, _)) => None,
                futures::future::Either::Right(_) => Some((Err(CoreError::new("stream_idle", "和 station 的连接没有回应")), None)),
            }
        }
    })
    .boxed_local()
}

/// Threads as the station lists them: the latest message first, then the newest thread.
fn sort_threads(threads: &mut [Value]) {
    let key = |t: &Value| {
        let said = t.get("lastMessage").and_then(|m| m.get("createdAt")?.as_f64()).unwrap_or(0.0);
        let created = t.get("createdAt").and_then(Value::as_f64).unwrap_or(0.0);
        (said, created, t.get("id").and_then(Value::as_u64).unwrap_or(0))
    };
    threads.sort_by(|a, b| {
        let (a, b) = (key(a), key(b));
        b.0.total_cmp(&a.0).then(b.1.total_cmp(&a.1)).then(b.2.cmp(&a.2))
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
    tracer: Rc<Tracer>,
    kept: Rc<Kept>,
    me: Weak<Stations>,
    stations: RefCell<HashMap<String, StationState>>,
    /// Stations their workspace says are offline: their topics are served from what was kept (the data center, the
    /// device's logs), and nothing is asked of them until they are back.
    offline: RefCell<HashSet<String>>,
}

/// A failed request's span.
fn failed(span: &mut Span, error: &CoreError) {
    span.fail();
    span.set("error.type", error.code.clone());
}

/// What a request's span records of the reply's head.
fn answered(span: &mut Span, reply: &WireReply) {
    span.set("http.response.status_code", reply.status);
    if let Some(via) = reply.via {
        span.set("ember.path", via);
    }
    if reply.status >= 500 {
        span.fail();
    }
}

impl Stations {
    pub fn new(host: Rc<dyn Host>, sink: Rc<dyn TopicSink>, wire: Rc<dyn StationWire>, tracer: Rc<Tracer>, kept: Rc<Kept>) -> Rc<Stations> {
        Rc::new_cyclic(|me| Stations { host, sink, wire, tracer, kept, me: me.clone(), stations: RefCell::default(), offline: RefCell::default() })
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

    /// POST /uploads?name= with the raw bytes: the file waits on the station, in no chat, until a message sends it.
    /// Answers the attachment.
    pub async fn upload(&self, station: &StationAddr, name: &str, bytes: Vec<u8>) -> Result<Value> {
        let path = format!("/uploads?name={}", encode(name));
        self.call(station, "POST", &path, vec![("content-type".into(), "application/octet-stream".into())], bytes).await
    }

    /// GET /sessions/:key/files?name=: (content type, bytes).
    pub async fn file(&self, station: &StationAddr, key: &str, name: &str) -> Result<(String, Vec<u8>)> {
        let path = format!("/sessions/{}/files?name={}", encode(key), encode(name));
        let (status, kind, bytes) = self.exchange(station, "GET", &path, Vec::new(), Vec::new(), |reply| reply.header("content-type").unwrap_or("").to_string()).await?;
        if status != 200 {
            return Err(CoreError::new(format!("http_{status}"), "读不到文件").with_status(status));
        }
        Ok((kind, bytes))
    }

    /// A request to a web service on the station's machine (`localhost:port`), passed through as it is: for a page
    /// of that service shown here. Answers its status, headers and body whatever the status.
    pub async fn preview(&self, station: &StationAddr, port: u16, method: &str, path: &str, headers: Vec<(String, String)>, body: Vec<u8>) -> Result<(u16, Vec<(String, String)>, Vec<u8>)> {
        let path = format!("/preview/{port}{}", if path.starts_with('/') { path.to_string() } else { format!("/{path}") });
        self.exchange(station, method, &path, headers, body, |reply| reply.headers.clone()).await
    }

    /// Starts a request: its span (under the current trace, or a trace of its own), whose `traceparent` the
    /// request carries, and the reply's head.
    fn send(&self, station: &StationAddr, method: &str, path: &str, mut headers: Vec<(String, String)>, body: Vec<u8>) -> (Span, LocalBoxFuture<'static, Result<WireReply>>) {
        let path = format!("/admin/api{path}");
        let mut span = self.tracer.span(format!("{method} {}", route(&path)), Kind::Client);
        span.set("http.request.method", method.to_string());
        span.set("url.path", route(&path));
        span.set("ember.station", match station {
            StationAddr::Local => "local".to_string(),
            StationAddr::Remote { station, .. } => station.clone(),
        });
        if !body.is_empty() {
            span.set("http.request.body.size", body.len());
        }
        headers.push(("traceparent".into(), span.context().traceparent()));
        let head = RequestHead { method: method.to_string(), path, headers };
        // Under the request's span: opening the link it needs (a grant, a connection) shows as part of it.
        let reply = self.tracer.instrument(Some(span.context()), self.wire.request(station, head, body));
        (span, reply)
    }

    /// One whole request: its status, what `head` takes from the reply's head, and the body.
    async fn exchange<T>(&self, station: &StationAddr, method: &str, path: &str, headers: Vec<(String, String)>, body: Vec<u8>, head: impl FnOnce(&WireReply) -> T) -> Result<(u16, T, Vec<u8>)> {
        let (mut span, reply) = self.send(station, method, path, headers, body);
        let result = async {
            let reply = reply.await?;
            answered(&mut span, &reply);
            let (status, taken) = (reply.status, head(&reply));
            let bytes = reply.bytes().await?;
            span.set("http.response.body.size", bytes.len());
            Ok((status, taken, bytes))
        }
        .await;
        if let Err(error) = &result {
            failed(&mut span, error);
        }
        span.end();
        result
    }

    async fn call(&self, station: &StationAddr, method: &str, path: &str, headers: Vec<(String, String)>, body: Vec<u8>) -> Result<Value> {
        let (status, (), bytes) = self.exchange(station, method, path, headers, body, |_| ()).await?;
        // Like the web's `response.json().catch(() => ({}))`.
        let data: Value = serde_json::from_slice(&bytes).unwrap_or_else(|_| json!({}));
        if !(200..300).contains(&status) {
            return Err(http_error(status, &data));
        }
        Ok(data)
    }

    /// Opens an event stream; a non-2xx answer is an error. Its span ends when the stream is open.
    async fn open_stream(&self, station: &StationAddr, path: &str) -> Result<LocalBoxStream<'static, Result<Vec<u8>>>> {
        let (mut span, reply) = self.send(station, "GET", path, vec![("accept".into(), EVENT_STREAM.into())], Vec::new());
        span.set("ember.stream", true);
        let reply = match reply.await {
            Ok(reply) => reply,
            Err(error) => {
                failed(&mut span, &error);
                return Err(error);
            }
        };
        answered(&mut span, &reply);
        span.end();
        if !(200..300).contains(&reply.status) {
            let status = reply.status;
            let bytes = reply.bytes().await.unwrap_or_default();
            let data: Value = serde_json::from_slice(&bytes).unwrap_or_else(|_| json!({}));
            return Err(http_error(status, &data));
        }
        Ok(idle_guarded(self.host.clone(), reply.body))
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
                touched.push(Topic::ChatRows { station: name.clone() });
                // A new chat answers its thread.
                if let Some(thread) = answer.get("thread").filter(|t| t.is_object()) {
                    self.put_thread(&name, thread);
                }
            }
            Some("threads") => {
                if answer.get("surface").is_some() {
                    self.put_thread(&name, answer);
                    // A new chat, or an agent more in one: the sidebar's rows change.
                    touched.push(Topic::ChatRows { station: name.clone() });
                } else if let (Some(thread), Some(n)) = (answer.get("thread").and_then(Value::as_u64), answer.get("n").and_then(Value::as_u64)) {
                    self.put_read(&name, thread, n);
                }
                if let (Some(id), Some("messages")) = (parts.get(1).and_then(|id| id.parse().ok()), parts.get(2).map(String::as_str)) {
                    touched.push(Topic::Thread { station: name.clone(), thread: id });
                }
            }
            Some("connects") => {
                touched.push(Topic::Overview { station: name.clone() });
                touched.push(Topic::Sessions { station: name.clone() });
                if let Some(connect) = parts.get(1) {
                    touched.push(Topic::SlackApp { station: name.clone(), connect: connect.clone() });
                }
            }
            Some("profiles") => touched.push(Topic::Overview { station: name.clone() }),
            // The workspace's Slack settings (its app configuration token): every connect's app reads through them.
            Some("slack") => {
                touched.push(Topic::Overview { station: name.clone() });
                touched.extend(self.live_topics(&name, |t| matches!(t, Topic::SlackApp { .. })));
            }
            // Who the viewer is on Slack: it answers the overview, and changes which rows are theirs.
            Some("me") => {
                touched.push(Topic::Overview { station: name.clone() });
                touched.push(Topic::ChatRows { station: name.clone() });
            }
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

    /// Runs a task in the trace it was started in (a chat opening reads its topics as part of it).
    fn spawn(&self, task: impl Future<Output = ()> + 'static) -> AbortHandle {
        self.spawn_in(self.tracer.current(), task)
    }

    /// For the streams held open: each of their requests is a trace of its own, not part of whatever started them.
    fn spawn_in(&self, context: Option<SpanContext>, task: impl Future<Output = ()> + 'static) -> AbortHandle {
        let (handle, registration) = AbortHandle::new_pair();
        self.host.spawn(self.tracer.instrument(context, Abortable::new(task, registration).map(|_| ())));
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
        if !self.is_live(topic) || topic.station().is_some_and(|s| !self.reachable(s)) {
            return;
        }
        let Some(addr) = topic.station().and_then(|s| self.addr(s)) else { return };
        let path = match topic {
            Topic::Overview { .. } => "/overview".to_string(),
            Topic::Sessions { .. } => "/sessions".to_string(),
            Topic::Threads { .. } => "/threads".to_string(),
            Topic::ChatRows { .. } => "/chats".to_string(),
            Topic::SlackApp { connect, .. } => format!("/connects/{}/slack-app", encode(connect)),
            Topic::Session { key, .. } => format!("/sessions/{}", encode(key)),
            // A thread already read only asks for what came after it.
            Topic::Thread { thread, .. } => match self.sink.get(topic).and_then(|v| v.get("last")?.as_u64()) {
                Some(last) => format!("/threads/{thread}/entries?after={last}"),
                None => format!("/threads/{thread}/entries?limit={PAGE}"),
            },
            _ => return,
        };
        let result = self.call(&addr, "GET", &path, Vec::new(), Vec::new()).await;
        if !self.is_live(topic) {
            return;
        }
        match (topic, result) {
            (Topic::Thread { station, thread }, Ok(answer)) => {
                let entries = answer.get("entries").and_then(Value::as_array).cloned().unwrap_or_default();
                if path.contains("after=") {
                    self.put_entries(station, *thread, entries);
                } else {
                    self.first_page(station, *thread, entries, answer.get("last").and_then(Value::as_u64).unwrap_or(0));
                }
            }
            (_, Ok(value)) => self.sink.set(topic, Ok(value)),
            (_, Err(error)) => {
                if self.sink.get(topic).is_none() {
                    self.sink.set(topic, Err(error));
                }
            }
        }
        if matches!(topic, Topic::Threads { .. } | Topic::Session { .. } | Topic::ChatRows { .. }) && let Some(station) = topic.station() {
            self.keep_summaries(station);
        }
        if let Topic::ChatRows { station } = topic {
            let first = self.stations.borrow_mut().get_mut(station).is_some_and(|s| !std::mem::replace(&mut s.warmed, true));
            if first && self.sink.get(topic).is_some() {
                let (this, station) = (self.rc(), station.clone());
                self.spawn_in(None, async move { this.warm(&station).await });
            }
        }
    }

    /// Once a station's sidebar rows are read, the chats they list come onto the device in the background, one after
    /// another, the latest active first: each one's latest page (or, for one kept, what came after it) with its
    /// summary and title, so a chat opens from what is kept rather than waiting for the station. Chats open meanwhile
    /// read themselves; it stops when the station is no longer in use.
    async fn warm(&self, station: &str) {
        if !self.reachable(station) {
            return;
        }
        let Some(addr) = self.addr(station) else { return };
        let rows = self.sink.get(&Topic::ChatRows { station: station.into() }).unwrap_or(Value::Null);
        let mut chats: Vec<(f64, u64, Value)> = rows.as_array().into_iter().flatten()
            .filter_map(|r| Some((r.get("lastActiveAt").and_then(Value::as_f64).unwrap_or(0.0), r.get("thread")?.as_u64()?, r.get("title").cloned().unwrap_or(Value::Null))))
            .collect();
        chats.sort_by(|a, b| b.0.total_cmp(&a.0));
        chats.truncate(WARM_CHATS);
        if chats.is_empty() {
            return;
        }
        // The summaries a chat opens with (as the station lists its threads).
        let threads = self.call(&addr, "GET", "/threads", Vec::new(), Vec::new()).await.ok();
        for (_, id, title) in chats {
            if self.addr(station).is_none() {
                return;
            }
            let topic = Topic::Thread { station: station.into(), thread: id };
            if self.is_live(&topic) {
                continue;
            }
            let log = Log::thread(station, id);
            let kept_last = self.kept.open(&log, 0).await.map(|(held, _)| held.last);
            let path = match kept_last {
                Some(last) => format!("/threads/{id}/entries?after={last}"),
                None => format!("/threads/{id}/entries?limit={PAGE}"),
            };
            let Ok(answer) = self.call(&addr, "GET", &path, Vec::new(), Vec::new()).await else { continue };
            let summary = threads.as_ref().and_then(|t| t.as_array()?.iter().find(|t| t.get("id").and_then(Value::as_u64) == Some(id)).cloned());
            let entries = answer.get("entries").and_then(Value::as_array).cloned().unwrap_or_default();
            if let Some(first) = entries.first().and_then(n_of) {
                self.kept.write(&log, first, entries, false, summary.clone()).await;
            }
            self.kept.summary(&log, summary, title.is_string().then_some(title)).await;
            // Gently: one chat at a time, with room between for what the viewer asks.
            self.host.sleep(WARM_GAP_MS).await;
        }
    }

    /// After the events stream was down: everything it may have missed is read once, as part of `span` (the
    /// reconnect), which ends when they are all read.
    fn refetch_all(&self, station: &str, span: Span) {
        let topics = self.live_topics(station, |t| {
            matches!(t, Topic::Overview { .. } | Topic::Sessions { .. } | Topic::Threads { .. } | Topic::ChatRows { .. } | Topic::Session { .. } | Topic::Thread { .. })
        });
        let this = self.rc();
        self.spawn_in(Some(span.context()), async move {
            join_all(topics.iter().map(|topic| this.reload(topic))).await;
            span.end();
        });
    }

    /// A station went offline or came back, as its workspace says. Offline: its streams and requests end and its link
    /// says so; its topics keep what they have. Back: what its topics want is read again and its stream opens.
    pub fn set_presence(&self, station: &str, online: bool) {
        let changed = if online { self.offline.borrow_mut().remove(station) } else { self.offline.borrow_mut().insert(station.to_string()) };
        if !changed {
            return;
        }
        if !online {
            if let Some(s) = self.stations.borrow_mut().get_mut(station) {
                for task in s.events.take().map(|(t, _)| t).into_iter().chain(s.replaced.take()) {
                    task.abort();
                }
                for (_, task) in s.tasks.drain() {
                    task.abort();
                }
                s.stale = true;
            }
            self.set_link(station, json!({ "state": "offline", "message": null }));
            return;
        }
        let topics: Vec<Topic> = self.stations.borrow().get(station).map(|s| s.topics.iter().cloned().collect()).unwrap_or_default();
        for topic in &topics {
            match topic {
                Topic::Overview { .. } | Topic::Sessions { .. } | Topic::Threads { .. } | Topic::ChatRows { .. } | Topic::Session { .. } | Topic::SlackApp { .. } | Topic::Thread { .. } => self.refetch(topic),
                _ => {}
            }
        }
        self.open_events(station, true);
    }

    /// Whether the station can be asked for anything now (not offline).
    fn reachable(&self, station: &str) -> bool {
        !self.offline.borrow().contains(station)
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
        self.open_events(station, false)
    }

    /// Opens the station's `/events` for what its topics want now (unless its stream already is, or `anew`): the
    /// new stream opens first, and the old one goes once it has, so nothing falls between.
    fn open_events(&self, station: &str, anew: bool) {
        if !self.reachable(station) {
            return;
        }
        // A session is followed once its live topic has what was kept of it: the stream asks from there.
        let mut live: Vec<String> = self
            .live_topics(station, |t| matches!(t, Topic::Live { .. }))
            .into_iter()
            .filter(|t| self.sink.get(t).is_some())
            .filter_map(|t| match t {
                Topic::Live { key, .. } => Some(key),
                _ => None,
            })
            .collect();
        live.sort();
        let (addr, wants, generation) = {
            let mut stations = self.stations.borrow_mut();
            let Some(s) = stations.get_mut(station) else { return };
            let wants = EventsFor { host: s.wants_host(), live };
            if !anew && s.events.as_ref().is_some_and(|(_, asks)| *asks == wants) {
                return;
            }
            if let Some((old, _)) = s.events.take()
                && let Some(older) = s.replaced.replace(old)
            {
                older.abort();
            }
            s.generation += 1;
            (s.addr.clone(), wants, s.generation)
        };
        // The first try belongs to whoever asked for the stream (a chat opening); later ones are traces of their own.
        let task = self.spawn_in(None, self.rc().follow_events(station.to_string(), addr, wants.clone(), generation, self.tracer.current()));
        if let Some(s) = self.stations.borrow_mut().get_mut(station) {
            s.events = Some((task, wants));
        }
    }

    /// The path of an `/events` stream for `wants`, each session asked for from the entries its topic has.
    fn events_path(&self, station: &str, wants: &EventsFor) -> String {
        let mut query: Vec<String> = Vec::new();
        if wants.host {
            query.push("host=1".into());
        }
        for key in &wants.live {
            let topic = Topic::Live { station: station.into(), key: key.clone() };
            let from = self.sink.get(&topic).and_then(|v| v.get("timeline")?.as_array().map(Vec::len)).unwrap_or(0);
            query.push(format!("live={}&from={from}", encode(key)));
        }
        if query.is_empty() { "/events".into() } else { format!("/events?{}", query.join("&")) }
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
    async fn follow_events(self: Rc<Self>, station: String, addr: StationAddr, wants: EventsFor, generation: u64, mut parent: Option<SpanContext>) {
        let mut first = true;
        loop {
            // Replaced before it opened: its successor asks instead.
            if !self.is_current(&station, generation) {
                return;
            }
            let name = if std::mem::replace(&mut first, false) { "station.connect" } else { "station.reconnect" };
            let mut span = self.tracer.enter(parent.take(), || self.tracer.span(name, Kind::Internal));
            span.set("ember.station", station.clone());
            // Asked anew each time: a session is followed from what its topic has by then.
            let path = self.events_path(&station, &wants);
            let opened = self.tracer.instrument(Some(span.context()), self.open_stream(&addr, &path)).await;
            if !self.took_over(&station, generation) {
                return;
            }
            match opened {
                Ok(mut body) => {
                    self.set_link(&station, json!({ "state": "online" }));
                    // Down for a while: what changed meanwhile was not told.
                    if self.set_stale(&station, false) {
                        self.refetch_all(&station, span);
                    } else {
                        span.end();
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
                    failed(&mut span, &error);
                    span.end();
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
                self.put_entries(station, id, data.get("entries").and_then(Value::as_array).cloned().unwrap_or_default());
                // The summaries (last message, unread) are not in the event.
                self.mark_dirty(station, id);
            }
            "thread-removed" => {
                let Some(id) = data.get("id").and_then(Value::as_u64) else { return };
                self.remove_thread(station, id);
                self.host.spawn(self.kept.forget(&Log::thread(station, id)));
                let topic = Topic::Thread { station: station.into(), thread: id };
                if self.is_live(&topic) {
                    self.sink.set(&topic, Err(CoreError::new("http_404", "没有这个对话").with_status(404)));
                }
            }
            "read" => {
                let (Some(thread), Some(n)) = (data.get("thread").and_then(Value::as_u64), data.get("n").and_then(Value::as_u64)) else { return };
                self.put_read(station, thread, n);
            }
            "chat" => self.put_row(station, &data),
            "live" => {
                let Some(key) = data.get("key").and_then(Value::as_str) else { return };
                if !self.is_live(&Topic::Live { station: station.into(), key: key.into() }) {
                    return;
                }
                if !self.on_live(station, key, &data) {
                    // Entries that cannot be placed: that session from its first entry, on a stream opened anew.
                    let topic = Topic::Live { station: station.into(), key: key.into() };
                    if let Some(s) = self.stations.borrow_mut().get_mut(station).and_then(|s| s.lives.get_mut(key)) {
                        *s = LiveView::default();
                    }
                    self.host.spawn(self.kept.forget(&Log::transcript(station, key)));
                    self.sink.set(&topic, Ok(live_start()));
                    self.open_events(station, true);
                }
            }
            "chat-removed" => {
                let Some(id) = data.get("id").and_then(Value::as_str) else { return };
                self.sink.update(&Topic::ChatRows { station: station.into() }, &mut |rows| {
                    if let Some(rows) = rows.as_array_mut() {
                        rows.retain(|r| r.get("id").and_then(Value::as_str) != Some(id));
                    }
                });
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
        self.host.spawn(self.kept.forget(&Log::transcript(station, key)));
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

    /// Opens a `thread` topic: what is kept of it at once (its latest page), then the entries after it.
    async fn open_thread(&self, station: &str, id: u64) {
        let topic = Topic::Thread { station: station.into(), thread: id };
        if let Some((held, entries)) = self.kept.open(&Log::thread(station, id), PAGE).await
            && self.is_live(&topic)
            && self.sink.get(&topic).is_none()
        {
            self.sink.set(&topic, Ok(thread_value(held.first, entries, held.thread, held.title)));
        }
        self.reload(&topic).await;
        // What it shows is on the device; so is the page before it, for when the viewer goes back.
        if let Some(first) = self.sink.get(&topic).and_then(|v| v.get("first")?.as_u64()) {
            self.prefetch_before(station, id, first);
        }
    }

    /// A thread's latest page, read with nothing kept: its topic's first value, and kept.
    fn first_page(&self, station: &str, id: u64, entries: Vec<Value>, last: u64) {
        let topic = Topic::Thread { station: station.into(), thread: id };
        let first = entries.first().and_then(n_of).unwrap_or(last + 1);
        if !entries.is_empty() {
            self.host.spawn(self.kept.write(&Log::thread(station, id), first, entries.clone(), false, self.summary(station, id)));
        }
        self.sink.set(&topic, Ok(thread_value(first, entries, Value::Null, Value::Null)));
    }

    /// New entries (an event, or `?after=`) onto a live thread topic, and kept. Those it has are skipped; entries
    /// past a gap wait while the gap is read.
    fn put_entries(&self, station: &str, id: u64, entries: Vec<Value>) {
        let topic = Topic::Thread { station: station.into(), thread: id };
        // Until it has a value, what it reads next covers these.
        let Some(last) = self.sink.get(&topic).and_then(|v| v.get("last")?.as_u64()) else { return };
        let fresh: Vec<Value> = entries.into_iter().filter(|e| n_of(e).is_some_and(|n| n > last)).collect();
        let Some(first) = fresh.first().and_then(n_of) else { return };
        {
            let mut stations = self.stations.borrow_mut();
            let Some(state) = stations.get_mut(station) else { return };
            if let Some(waiting) = state.gaps.get_mut(&id) {
                waiting.extend(fresh);
                return;
            }
            if first > last + 1 {
                state.gaps.insert(id, fresh);
                drop(stations);
                let (this, station) = (self.rc(), station.to_string());
                self.spawn(async move { this.fill_gap(&station, id, last + 1, first - 1).await });
                return;
            }
        }
        // The run that follows `last`; what lies past a hole in it comes after, as entries past a gap.
        let mut run: Vec<Value> = Vec::new();
        let mut past = Vec::new();
        for entry in fresh {
            match n_of(&entry) {
                Some(n) if n == last + 1 + run.len() as u64 => run.push(entry),
                Some(n) if n > last + run.len() as u64 => past.push(entry),
                _ => {}
            }
        }
        self.sink.update(&topic, &mut |value| {
            if value.get("last").and_then(Value::as_u64) != Some(last) {
                return;
            }
            if let Some(list) = value.get_mut("entries").and_then(Value::as_array_mut) {
                list.extend(run.iter().cloned());
            }
            value["last"] = json!(last + run.len() as u64);
        });
        self.host.spawn(self.kept.write(&Log::thread(station, id), last + 1, run, false, self.summary(station, id)));
        if !past.is_empty() {
            self.put_entries(station, id, past);
        }
    }

    /// Reads the entries `from ..= to` an event showed missing, then places them with those that came meanwhile.
    async fn fill_gap(&self, station: &str, id: u64, from: u64, to: u64) {
        let addr = self.addr(station);
        let answer = match addr {
            Some(addr) => self.call(&addr, "GET", &format!("/threads/{id}/entries?from={from}&to={to}"), Vec::new(), Vec::new()).await.ok(),
            None => None,
        };
        let waiting = self.stations.borrow_mut().get_mut(station).and_then(|s| s.gaps.remove(&id)).unwrap_or_default();
        let mut entries = answer.and_then(|a| a.get("entries").and_then(Value::as_array).cloned()).unwrap_or_default();
        entries.extend(waiting);
        entries.sort_by_key(|e| n_of(e).unwrap_or(0));
        entries.dedup_by_key(|e| n_of(e));
        self.put_entries(station, id, entries);
    }

    /// The thread's summary as a live topic lists it.
    fn summary(&self, station: &str, id: u64) -> Option<Value> {
        let find = |list: Option<&Value>| list?.as_array()?.iter().find(|t| t.get("id").and_then(Value::as_u64) == Some(id)).cloned();
        let lists = self.live_topics(station, |t| matches!(t, Topic::Threads { .. } | Topic::Session { .. }));
        lists.iter().find_map(|topic| {
            let value = self.sink.get(topic)?;
            match topic {
                Topic::Session { .. } => find(value.get("threads")),
                _ => find(Some(&value)),
            }
        })
    }

    /// Keeps the summaries and sidebar titles of the station's open threads as the lists and rows have them now (a
    /// chat opens with them).
    fn keep_summaries(&self, station: &str) {
        let rows = self.sink.get(&Topic::ChatRows { station: station.into() });
        for topic in self.live_topics(station, |t| matches!(t, Topic::Thread { .. })) {
            let Topic::Thread { thread, .. } = topic else { continue };
            let title = rows.as_ref().and_then(|rows| rows.as_array()?.iter().find(|r| r.get("thread").and_then(Value::as_u64) == Some(thread))?.get("title").cloned());
            let summary = self.summary(station, thread);
            if summary.is_some() || title.is_some() {
                self.host.spawn(self.kept.summary(&Log::thread(station, thread), summary, title));
            }
        }
    }

    /// A row of the viewer's sidebar, new or changed, into the station's rows.
    fn put_row(&self, station: &str, row: &Value) {
        let Some(id) = row.get("id").and_then(Value::as_str) else { return };
        self.sink.update(&Topic::ChatRows { station: station.into() }, &mut |rows| {
            let Some(rows) = rows.as_array_mut() else { return };
            match rows.iter().position(|r| r.get("id").and_then(Value::as_str) == Some(id)) {
                Some(i) => rows[i] = row.clone(),
                None => rows.push(row.clone()),
            }
        });
        self.keep_summaries(station);
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
        self.keep_summaries(station);
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

    /// The viewer read a thread up to entry `n`: its read position moves there, and nothing is unread once it
    /// covers the last entry (otherwise the count is read again).
    fn put_read(&self, station: &str, thread: u64, n: u64) {
        let stale = std::cell::Cell::new(false);
        let apply = |list: &mut Value| {
            for t in list.as_array_mut().into_iter().flatten() {
                if t.get("id").and_then(Value::as_u64) != Some(thread) || t.get("read").and_then(Value::as_u64).is_some_and(|read| read >= n) {
                    continue;
                }
                t["read"] = json!(n);
                if t.get("last").and_then(Value::as_u64).is_none_or(|last| n >= last) {
                    t["unread"] = json!(0);
                } else {
                    stale.set(true);
                }
            }
        };
        self.sink.update(&Topic::Threads { station: station.into() }, &mut |list| apply(list));
        // Its row is read once the read covers its last message; the station's `chat` event says the same.
        self.sink.update(&Topic::ChatRows { station: station.into() }, &mut |rows| {
            for row in rows.as_array_mut().into_iter().flatten() {
                if row.get("thread").and_then(Value::as_u64) == Some(thread) && row.get("last").and_then(|l| l.get("seq")?.as_u64()).is_none_or(|last| n >= last) {
                    row["unread"] = json!(false);
                }
            }
        });
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
        self.keep_summaries(station);
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

    /// A person's message into a thread. Answers its entry number once the thread's topic, where live, holds it.
    pub async fn post(&self, station: &StationAddr, thread: u64, message: Value) -> Result<u64> {
        let answer = self.json(station, "POST", &format!("/threads/{thread}/messages"), Some(message)).await?;
        let n = answer.get("n").and_then(Value::as_u64).ok_or_else(|| CoreError::new("bad_response", "station 的回复里没有消息序号"))?;
        let topic = Topic::Thread { station: station.to_string(), thread };
        if self.sink.get(&topic).and_then(|v| v.get("last")?.as_u64()).is_some_and(|last| last < n) {
            self.reload(&topic).await;
        }
        Ok(n)
    }

    /// The page of entries before those loaded, into the thread's topic: from what is kept, else from the station
    /// (and kept). Answers whether still older ones exist.
    pub async fn older(&self, station: &StationAddr, thread: u64) -> Result<bool> {
        let name = station.to_string();
        let topic = Topic::Thread { station: name.clone(), thread };
        let log = Log::thread(&name, thread);
        let Some(before) = self.sink.get(&topic).and_then(|v| v.get("first")?.as_u64()) else { return Ok(false) };
        if before <= 1 {
            return Ok(false);
        }
        let older = match self.kept.before(&log, before, PAGE).await {
            Some(older) => older,
            None => {
                let page = self.json(station, "GET", &format!("/threads/{thread}/entries?before={before}&limit={PAGE}"), None).await?;
                let older: Vec<Value> = page.get("entries").and_then(Value::as_array).into_iter().flatten().filter(|e| n_of(e).is_some_and(|n| n < before)).cloned().collect();
                if let Some(first) = older.first().and_then(n_of) {
                    self.host.spawn(self.kept.write(&log, first, older.clone(), false, None));
                }
                older
            }
        };
        let Some(first) = older.first().and_then(n_of) else { return Ok(false) };
        let mut still = false;
        self.sink.update(&topic, &mut |value| {
            let loaded = value.get("first").and_then(Value::as_u64);
            // Another page came first: this one is not next to what is loaded any more.
            if loaded != Some(before) || older.len() as u64 != before - first {
                still = loaded.is_some_and(|f| f > 1);
                return;
            }
            let Some(list) = value.get_mut("entries").and_then(Value::as_array_mut) else { return };
            list.splice(0..0, older.iter().cloned());
            value["first"] = json!(first);
            still = first > 1;
        });
        // A page ahead again, for the next time.
        if still {
            self.prefetch_before(&name, thread, first);
        }
        Ok(still)
    }

    /// Keeps a page ahead of what a thread shows: the page before entry `before`, brought onto the device if it is not
    /// there, so the next `older` has it at once. Nothing when the thread starts there, or its station is offline.
    fn prefetch_before(&self, station: &str, thread: u64, before: u64) {
        if before <= 1 || !self.reachable(station) {
            return;
        }
        let Ok(addr) = StationAddr::parse(station) else { return };
        let (this, name) = (self.rc(), station.to_string());
        self.spawn(async move {
            let log = Log::thread(&name, thread);
            if this.kept.before(&log, before, PAGE).await.is_some() {
                return;
            }
            let Ok(page) = this.json(&addr, "GET", &format!("/threads/{thread}/entries?before={before}&limit={PAGE}"), None).await else { return };
            let older: Vec<Value> = page.get("entries").and_then(Value::as_array).into_iter().flatten().filter(|e| n_of(e).is_some_and(|n| n < before)).cloned().collect();
            if let Some(first) = older.first().and_then(n_of) {
                this.kept.write(&log, first, older, false, None).await;
            }
        });
    }

    /// Records how far the viewer has read a thread (an entry number); nothing is sent when it is read that far
    /// already.
    pub async fn read(&self, station: &StationAddr, thread: u64, n: u64) -> Result<()> {
        let name = station.to_string();
        if self.read_position(&name, thread).is_some_and(|read| read >= n) {
            return Ok(());
        }
        let answer = self.json(station, "PUT", &format!("/threads/{thread}/read"), Some(json!({ "n": n }))).await?;
        self.put_read(&name, thread, answer.get("n").and_then(Value::as_u64).unwrap_or(n));
        Ok(())
    }

    // ── live ──

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
            self.host.spawn(self.kept.write(&Log::transcript(station, key), start as u64, entries.to_vec(), true, None));
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
                // How fast the model writes now; the rest of the view is as it was.
                "rate" => {}
                "step" => {
                    let Some(event) = message.get("event") else { return true };
                    apply_step(view, event, now);
                }
                _ => return true,
            }
            view.clone()
        };
        let rate = message.get("tokensPerSecond").and_then(Value::as_u64);
        self.sink.update(&topic, &mut |live| {
            live["steps"] = json!(view.steps);
            live["phase"] = json!(view.phase);
            match kind {
                "rate" => live["rate"] = json!(rate.unwrap_or(0)),
                // Writing stops with the step or the turn; the rate comes again with more output.
                "clear" => live["rate"] = json!(0),
                _ => {}
            }
            // What the chat shows of it (activity.rs), from all of the above.
            live["activity"] = crate::activity::present(live);
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
            // What it is; what it writes comes with its transcript entry (the station tells no deltas).
            let mut step = json!({
                "id": id,
                "step": event.get("step").cloned().unwrap_or(Value::Null),
                "input": event.get("input").and_then(Value::as_str).unwrap_or(""),
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
            Topic::Link { .. } if !self.reachable(&station) => {
                let (this, station) = (self.rc(), station.clone());
                self.spawn(async move { this.set_link(&station, json!({ "state": "offline", "message": null })) });
            }
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
            Topic::Overview { .. } | Topic::Sessions { .. } | Topic::Threads { .. } | Topic::ChatRows { .. } | Topic::Session { .. } | Topic::SlackApp { .. } => self.refetch(topic),
            Topic::Thread { thread, .. } => {
                let (this, station, thread) = (self.rc(), station.clone(), *thread);
                self.spawn(async move { this.open_thread(&station, thread).await });
            }
            // Samples come on the events stream, which asks for them now.
            Topic::Host { .. } => {}
            // What was kept of its transcript first; then the station's stream asks for it from there (see open_events).
            Topic::Live { key, .. } => {
                if let Some(s) = self.stations.borrow_mut().get_mut(&station) {
                    s.lives.insert(key.clone(), LiveView::default());
                }
                let (this, station, key, topic) = (self.rc(), station.clone(), key.clone(), topic.clone());
                self.spawn(async move {
                    let mut start = live_start();
                    if let Some((_, entries)) = this.kept.open(&Log::transcript(&station, &key), u64::MAX).await {
                        start["timeline"] = json!(entries);
                    }
                    // Offline, what was kept is all there is to read: it is loaded, and says why it ends there.
                    if !this.reachable(&station) {
                        start["loaded"] = json!(true);
                        start["offline"] = json!(true);
                    }
                    if this.is_live(&topic) && this.sink.get(&topic).is_none() {
                        this.sink.set(&topic, Ok(start));
                    }
                    this.sync_events(&station);
                });
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
        /// The `traceparent` of every request, in order.
        traceparents: RefCell<Vec<String>>,
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
            let traceparent = head.headers.iter().find(|(k, _)| k == "traceparent").map(|(_, v)| v.clone()).unwrap_or_default();
            self.traceparents.borrow_mut().push(traceparent);
            let reply = if wants_stream(&head) {
                match *self.stream_status.borrow() {
                    Some(200) => {
                        let (tx, rx) = mpsc::unbounded();
                        self.streams.borrow_mut().push((head.path.clone(), tx));
                        Ok(WireReply { status: 200, headers: vec![], body: rx.boxed_local(), via: None })
                    }
                    Some(status) => Ok(WireReply { status, headers: vec![], body: futures::stream::iter([Ok(r#"{"error":"没有权限"}"#.as_bytes().to_vec())]).boxed_local(), via: None }),
                    None => Err(CoreError::new("offline", "连不上")),
                }
            } else {
                let (status, value) = self.answers.borrow().get(&format!("{} {}", head.method, head.path)).cloned().unwrap_or((200, json!({})));
                Ok(WireReply { status, headers: vec![("content-type".into(), "application/json".into())], body: futures::stream::iter([Ok(serde_json::to_vec(&value).unwrap())]).boxed_local(), via: None })
            };
            async move { reply }.boxed_local()
        }
    }

    fn setup() -> (Rc<FakeHost>, Rc<FakeSink>, Rc<FakeWire>, Rc<Stations>) {
        let host = FakeHost::new();
        let sink = Rc::new(FakeSink::default());
        let wire = FakeWire::new();
        let stations = Stations::new(host.clone(), sink.clone(), wire.clone(), Tracer::new(host.clone(), 1.0), Kept::new(host.clone()));
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
    /// A live message for session `key`, as the events stream carries it.
    fn with_key(key: &str, mut value: Value) -> Value {
        value["key"] = json!(key);
        value
    }

    fn summary(key: &str, turns: u64) -> Value {
        json!({"key": key, "title": null, "archivedAt": null, "turns": turns, "lastTurn": null})
    }
    fn entry(n: u64, text: &str) -> Value {
        json!({"thread": 7, "n": n, "kind": "message", "target": null, "ts": format!("{n}.0"), "authorKind": "person", "author": "a@x.com", "text": text, "at": n})
    }
    fn edit(n: u64, target: u64, text: &str) -> Value {
        json!({"thread": 7, "n": n, "kind": "edit", "target": target, "ts": null, "authorKind": "person", "author": "a@x.com", "text": text, "at": n})
    }
    fn entries(from: u64, to: u64) -> Value {
        json!((from..=to).map(|n| entry(n, &format!("m{n}"))).collect::<Vec<_>>())
    }
    fn thread_view(id: u64, members: &[&str], last: u64, read: u64, unread: u64) -> Value {
        json!({"id": id, "surface": "ember", "createdAt": id, "sessions": members.iter().map(|s| json!({"thread": id, "session": s})).collect::<Vec<_>>(),
            "last": last, "lastMessage": if last > 0 { json!({"seq": last, "text": "…", "createdAt": last}) } else { Value::Null }, "read": read, "unread": unread})
    }
    /// The thread topic's messages, merged.
    fn texts(sink: &FakeSink, id: u64) -> Vec<String> {
        let page = sink.get(&thread(id)).unwrap();
        crate::entries::merge(page["entries"].as_array().unwrap()).iter().map(|m| m["text"].as_str().unwrap().to_string()).collect()
    }
    fn numbers(sink: &FakeSink, id: u64) -> Vec<u64> {
        sink.get(&thread(id)).unwrap()["entries"].as_array().unwrap().iter().filter_map(n_of).collect()
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
            wire.answer("POST /admin/api/uploads?name=a%20b.png", 200, json!({"name": "a b.png"}));
            let saved = stations.upload(&remote(), "a b.png", vec![1, 2, 3]).await.unwrap();
            assert_eq!(saved["name"], "a b.png");
            assert_eq!(wire.calls.borrow()[0].3, vec![1, 2, 3]);
            wire.answer("GET /admin/api/sessions/k/files?name=x", 404, json!({"error": "没有这个文件"}));
            let e = stations.file(&remote(), "k", "x").await.unwrap_err();
            assert_eq!((e.message.as_str(), e.status), ("读不到文件", Some(404)));
        });
    }

    #[test]
    fn an_offline_station_is_asked_for_nothing_until_it_is_back() {
        run(async {
            let (host, sink, wire, stations) = setup();
            wire.answer("GET /admin/api/overview", 200, json!({"connects": [], "profiles": []}));
            stations.set_presence(ST, false);
            for t in [overview(), link()] {
                stations.start(&t);
            }
            host.settle().await;
            assert_eq!(wire.count("GET", "/admin/api/overview"), 0, "offline: nothing asked");
            assert_eq!(sink.get(&link()).unwrap()["state"], "offline");
            stations.set_presence(ST, true);
            host.settle().await;
            assert_eq!(wire.count("GET", "/admin/api/overview"), 1, "back: what it wants is read");
            assert!(sink.get(&overview()).is_some());
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
            // The workspace's app configuration token: every connect's app shown is read again, as it now reads.
            let app = Topic::SlackApp { station: ST.into(), connect: "ds".into() };
            wire.answer("GET /admin/api/connects/ds/slack-app", 200, json!({"state": "no_config_token"}));
            stations.start(&app);
            host.settle().await;
            wire.answer("GET /admin/api/connects/ds/slack-app", 200, json!({"state": "ok"}));
            stations.request(&remote(), "PUT", "/slack/config-token", Some(json!({"refreshToken": "x"}))).await.unwrap();
            assert_eq!(sink.get(&app).unwrap()["state"], "ok");
        });
    }

    #[test]
    fn requests_carry_the_trace_they_are_made_in() {
        run(async {
            let (host, _sink, wire, stations) = setup();
            let tracer = stations.tracer.clone();
            let root = tracer.root("chat.open", Kind::Internal);
            tracer.enter(Some(root.context()), || {
                stations.start(&threads());
                stations.start(&thread(7));
            });
            host.settle().await;
            // Outside every trace: a trace of its own.
            stations.request(&remote(), "GET", "/overview", None).await.unwrap();
            let trace = hex::encode(root.context().trace);
            let (paths, parents) = (wire.paths(), wire.traceparents.borrow().clone());
            assert_eq!(paths.len(), 4, "{paths:?}");
            for (path, parent) in paths.iter().zip(&parents) {
                assert!(parent.starts_with("00-") && parent.ends_with("-01") && parent.len() == 55, "{path}: {parent}");
                // Each request is a span of its own under the trace.
                assert_ne!(&parent[36..52], hex::encode(root.context().span), "{path}");
                assert_eq!(parent[3..35] == trace, !path.ends_with("/overview"), "{path}: {parent}");
            }
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
            assert_eq!(wire.open(), vec!["/admin/api/events?host=1&live=a&from=0"]);
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
    fn thread_events_append_entries_and_refresh_summaries() {
        run(async {
            let (host, sink, wire, stations) = setup();
            wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 12, "entries": [entry(11, "a"), entry(12, "b")]}));
            wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 12, 12, 0)]));
            wire.answer("GET /admin/api/threads/7", 200, thread_view(7, &["k"], 15, 12, 2));
            wire.answer("GET /admin/api/threads/8", 200, thread_view(8, &["k"], 20, 0, 1));
            stations.start(&thread(7));
            stations.start(&threads());
            host.settle().await;
            assert_eq!(texts(&sink, 7), vec!["a", "b"]);
            // New entries (an edit among them), in one burst: appended at once, one known already skipped; the
            // summary is read once after it.
            wire.event("thread", json!({"id": 7, "entries": [entry(13, "c")]}));
            wire.event("thread", json!({"id": 7, "entries": [entry(13, "c"), entry(14, "d"), edit(15, 12, "b 改了")]}));
            host.settle().await;
            assert_eq!(numbers(&sink, 7), vec![11, 12, 13, 14, 15]);
            assert_eq!(texts(&sink, 7), vec!["a", "b 改了", "c", "d"]);
            assert_eq!(sink.get(&thread(7)).unwrap()["last"], 15);
            assert_eq!(wire.count("GET", "/admin/api/threads/7"), 0, "waits for the burst to end");
            wait(EVENTS_COALESCE_MS).await;
            assert_eq!(wire.count("GET", "/admin/api/threads/7"), 1);
            assert_eq!(sink.get(&threads()).unwrap()[0]["unread"], 2);
            // A thread not listed yet comes in, first (its last message is the newest).
            wire.event("thread", json!({"id": 8, "entries": [entry(20, "x")]}));
            host.settle().await;
            wait(EVENTS_COALESCE_MS).await;
            let ids: Vec<u64> = sink.get(&threads()).unwrap().as_array().unwrap().iter().map(|t| t["id"].as_u64().unwrap()).collect();
            assert_eq!(ids, vec![8, 7]);
            // Reading up to the last entry: nothing unread, without a request. Short of it: counted again.
            wire.event("read", json!({"viewer": "a@x.com", "thread": 7, "n": 15}));
            host.settle().await;
            assert_eq!(sink.get(&threads()).unwrap()[1]["unread"], 0);
            assert_eq!(sink.get(&threads()).unwrap()[1]["read"], 15);
            wire.event("read", json!({"viewer": "a@x.com", "thread": 8, "n": 15}));
            host.settle().await;
            wait(EVENTS_COALESCE_MS).await;
            assert_eq!(wire.count("GET", "/admin/api/threads/8"), 2);
            // A thread gone: out of the list.
            wire.answer("GET /admin/api/threads/8", 404, json!({"error": "unknown thread 8"}));
            wire.event("thread", json!({"id": 8, "entries": []}));
            host.settle().await;
            wait(EVENTS_COALESCE_MS).await;
            assert_eq!(sink.get(&threads()).unwrap().as_array().unwrap().len(), 1);
        });
    }

    #[test]
    fn a_gap_is_read_once_and_what_came_meanwhile_waits_for_it() {
        run(async {
            let (host, sink, wire, stations) = setup();
            wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 3, "entries": entries(1, 3)}));
            wire.answer("GET /admin/api/threads/7/entries?from=4&to=5", 200, json!({"last": 7, "entries": entries(4, 5)}));
            stations.start(&thread(7));
            host.settle().await;
            // Entries 4 and 5 never came: 6 shows the gap, and 7 comes while it is read.
            wire.event("thread", json!({"id": 7, "entries": [entry(6, "m6")]}));
            wire.event("thread", json!({"id": 7, "entries": [entry(7, "m7")]}));
            host.settle().await;
            assert_eq!(numbers(&sink, 7), vec![1, 2, 3, 4, 5, 6, 7]);
            assert_eq!(wire.count("GET", "/admin/api/threads/7/entries?from=4&to=5"), 1);
            assert_eq!(wire.paths().iter().filter(|p| p.contains("/entries")).count(), 2, "{:?}", wire.paths());
        });
    }

    /// A second core on the same device (the page reloaded): the same storage, a new `Stations`.
    fn reopened(host: &Rc<FakeHost>) -> (Rc<FakeSink>, Rc<FakeWire>, Rc<Stations>) {
        let sink = Rc::new(FakeSink::default());
        let wire = FakeWire::new();
        let stations = Stations::new(host.clone(), sink.clone(), wire.clone(), Tracer::new(host.clone(), 1.0), Kept::new(host.clone()));
        (sink, wire, stations)
    }

    #[test]
    fn a_thread_keeps_a_page_ahead_so_going_back_does_not_wait() {
        run(async {
            let (host, _sink, wire, stations) = setup();
            wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 300, "entries": entries(251, 300)}));
            wire.answer("GET /admin/api/threads/7/entries?before=251&limit=50", 200, json!({"last": 300, "entries": entries(201, 250)}));
            stations.start(&thread(7));
            host.settle().await;
            assert_eq!(wire.count("GET", "/admin/api/threads/7/entries?before=251&limit=50"), 1, "the page before, brought in ahead");
            // Going back shows it from the device at once, and brings the next one in.
            wire.answer("GET /admin/api/threads/7/entries?before=201&limit=50", 200, json!({"last": 300, "entries": entries(151, 200)}));
            assert!(stations.older(&remote(), 7).await.unwrap());
            assert_eq!(wire.count("GET", "/admin/api/threads/7/entries?before=251&limit=50"), 1, "not asked again");
            host.settle().await;
            assert_eq!(wire.count("GET", "/admin/api/threads/7/entries?before=201&limit=50"), 1);
        });
    }

    #[test]
    fn a_thread_opens_from_what_is_kept_and_asks_only_for_what_came_after() {
        run(async {
            let (host, sink, wire, stations) = setup();
            wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 300, "entries": entries(251, 300)}));
            wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 300, 300, 0)]));
            stations.start(&thread(7));
            stations.start(&threads());
            host.settle().await;
            wire.event("thread", json!({"id": 7, "entries": [entry(301, "m301")]}));
            host.settle().await;
            assert_eq!(numbers(&sink, 7).len(), 51);
            // Reloaded: the kept page at once, with the summary kept beside it, before anything is answered.
            let (sink, wire, stations) = reopened(&host);
            *wire.stream_status.borrow_mut() = None;
            wire.answer("GET /admin/api/threads/7/entries?after=301", 200, json!({"last": 302, "entries": [entry(302, "m302")]}));
            stations.start(&thread(7));
            host.settle().await;
            // Its latest page came from what is kept (the station was asked only for what came after it).
            let shown = sink.get(&thread(7)).expect("shown from what is kept");
            assert_eq!((shown["first"].clone(), shown["last"].clone(), shown["thread"]["id"].clone()), (json!(252), json!(302), json!(7)));
            assert_eq!(wire.paths().iter().filter(|p| p.contains("/entries")).cloned().collect::<Vec<_>>(), vec!["GET /admin/api/threads/7/entries?after=301"]);
            // Scrolling up reads what is kept first; past it, the station (and what it answers is kept too).
            assert!(stations.older(&remote(), 7).await.unwrap());
            assert_eq!(sink.get(&thread(7)).unwrap()["first"], 251);
            assert_eq!(wire.calls.borrow().len(), 2, "{:?}", wire.paths());
            wire.answer("GET /admin/api/threads/7/entries?before=251&limit=50", 200, json!({"last": 302, "entries": entries(201, 250)}));
            assert!(stations.older(&remote(), 7).await.unwrap());
            assert_eq!(numbers(&sink, 7).first(), Some(&201));
            host.settle().await;
            let (sink, wire, stations) = reopened(&host);
            *wire.stream_status.borrow_mut() = None;
            stations.start(&thread(7));
            host.settle().await;
            assert!(stations.older(&remote(), 7).await.unwrap());
            assert_eq!(numbers(&sink, 7), (203..=302).collect::<Vec<_>>(), "two pages, both from what is kept");
            assert_eq!(wire.paths().iter().filter(|p| p.contains("before=")).count(), 0);
            assert_eq!(texts(&sink, 7).last().unwrap(), "m302");
        });
    }

    #[test]
    fn a_removed_thread_and_a_removed_sessions_transcript_are_forgotten() {
        run(async {
            let (host, _sink, wire, stations) = setup();
            wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 2, "entries": entries(1, 2)}));
            stations.start(&thread(7));
            stations.start(&live("k"));
            host.settle().await;
            wire.event("live", with_key("k", json!({"type": "timeline", "start": 0, "entries": ["a"], "usage": {}})));
            host.settle().await;
            assert!(host.stored("thread/ws/st/7/0").is_some() && host.stored("transcript/ws/st/k/0").is_some());
            wire.event("thread-removed", json!({"id": 7}));
            wire.event("session-removed", json!({"key": "k"}));
            host.settle().await;
            assert_eq!((host.stored("thread/ws/st/7/0"), host.stored("thread/ws/st/7/meta")), (None, None));
            assert_eq!(host.stored("transcript/ws/st/k/0"), None);
        });
    }

    #[test]
    fn chat_rows_come_from_the_station_and_follow_its_events() {
        run(async {
            let (host, sink, wire, stations) = setup();
            let rows = Topic::ChatRows { station: ST.into() };
            let row = |id: &str, thread: Option<u64>, last: u64, unread: bool| json!({"id": id, "thread": thread, "title": id, "last": if last > 0 { json!({"seq": last, "text": "…"}) } else { Value::Null }, "unread": unread});
            wire.answer("GET /admin/api/chats", 200, json!([row("7", Some(7), 12, true), row("k", None, 0, false)]));
            stations.start(&rows);
            host.settle().await;
            assert_eq!(wire.open(), vec!["/admin/api/events"]);
            let ids = |sink: &FakeSink| sink.get(&rows).unwrap().as_array().unwrap().iter().map(|r| r["id"].as_str().unwrap().to_string()).collect::<Vec<_>>();
            assert_eq!(ids(&sink), vec!["7", "k"]);
            let reads = wire.calls.borrow().len();
            // Rows change, come and go as the station says, without a request.
            let mut renamed = row("7", Some(7), 13, true);
            renamed["title"] = json!("排查");
            wire.event("chat", renamed);
            wire.event("chat", row("8", Some(8), 1, false));
            wire.event("chat-removed", json!({"id": "k"}));
            host.settle().await;
            assert_eq!(ids(&sink), vec!["7", "8"]);
            assert_eq!(sink.get(&rows).unwrap()[0]["title"], "排查");
            assert_eq!(wire.calls.borrow().len(), reads);
            // Read short of the last message: still unread; up to it: read, at once.
            wire.event("read", json!({"viewer": "a@x.com", "thread": 7, "n": 12}));
            host.settle().await;
            assert_eq!(sink.get(&rows).unwrap()[0]["unread"], true);
            stations.read(&remote(), 7, 13).await.unwrap();
            assert_eq!(sink.get(&rows).unwrap()[0]["unread"], false);
            // A new chat is written: the rows are current when the write answers.
            wire.answer("GET /admin/api/chats", 200, json!([row("9", Some(9), 0, false)]));
            wire.answer("POST /admin/api/threads", 200, thread_view(9, &["k"], 0, 0, 0));
            stations.request(&remote(), "POST", "/threads", Some(json!({"session": "k"}))).await.unwrap();
            assert_eq!(ids(&sink), vec!["9"]);
            // So is saying who one is on Slack.
            wire.answer("PUT /admin/api/me/slack/U7", 200, json!({"viewer": {}, "connects": [], "profiles": [], "slackUsers": ["U7"]}));
            let before = wire.count("GET", "/admin/api/chats");
            stations.request(&remote(), "PUT", "/me/slack/U7", None).await.unwrap();
            assert_eq!(wire.count("GET", "/admin/api/chats"), before + 1);
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
            wire.event("thread", json!({"id": 9, "entries": []}));
            wire.event("read", json!({"viewer": "a@x.com", "thread": 7, "n": 12}));
            host.settle().await;
            wait(EVENTS_COALESCE_MS).await;
            let detail = sink.get(&session("k")).unwrap();
            let ids: Vec<u64> = detail["threads"].as_array().unwrap().iter().map(|t| t["id"].as_u64().unwrap()).collect();
            assert_eq!(ids, vec![9, 7]);
            assert_eq!(detail["threads"][1]["unread"], 0);
            // The session left thread 9.
            wire.answer("GET /admin/api/threads/9", 200, thread_view(9, &["j"], 30, 0, 1));
            wire.event("thread", json!({"id": 9, "entries": []}));
            host.settle().await;
            wait(EVENTS_COALESCE_MS).await;
            assert_eq!(sink.get(&session("k")).unwrap()["threads"].as_array().unwrap().len(), 1);
        });
    }

    #[test]
    fn a_thread_pages_back_and_catches_up() {
        run(async {
            let (host, sink, wire, stations) = setup();
            wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 4, "entries": [entry(3, "c"), entry(4, "d")]}));
            wire.answer("GET /admin/api/threads/7/entries?before=3&limit=50", 200, json!({"last": 4, "entries": [entry(1, "a"), entry(2, "b")]}));
            stations.start(&thread(7));
            stations.start(&link());
            host.settle().await;
            assert!(!stations.older(&remote(), 7).await.unwrap());
            assert_eq!(texts(&sink, 7), vec!["a", "b", "c", "d"]);
            // Nothing older: no request.
            assert!(!stations.older(&remote(), 7).await.unwrap());
            assert_eq!(wire.paths().iter().filter(|p| p.contains("before=")).count(), 1);
            // The stream was down: what came after the last entry is read, and the pages stay.
            wire.answer("GET /admin/api/threads/7/entries?after=4", 200, json!({"last": 5, "entries": [entry(5, "e")]}));
            wire.end("/admin/api/events");
            host.settle().await;
            assert_eq!(sink.get(&link()).unwrap()["state"], "offline");
            wait(RECONNECT_MS + 50).await;
            assert_eq!(sink.get(&link()).unwrap()["state"], "online");
            assert_eq!(texts(&sink, 7), vec!["a", "b", "c", "d", "e"]);
            assert_eq!(wire.count("GET", "/admin/api/threads/7/entries?limit=50"), 1);
        });
    }

    #[test]
    fn posts_into_a_thread_and_answers_once_it_shows() {
        run(async {
            let (host, sink, wire, stations) = setup();
            wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 12, "entries": [entry(12, "d")]}));
            wire.answer("POST /admin/api/threads/7/messages", 200, json!({"n": 13}));
            wire.answer("GET /admin/api/threads/7/entries?after=12", 200, json!({"last": 13, "entries": [entry(13, "你好")]}));
            stations.start(&thread(7));
            host.settle().await;
            assert_eq!(stations.post(&remote(), 7, json!({"text": "你好"})).await.unwrap(), 13);
            assert_eq!(texts(&sink, 7), vec!["d", "你好"]);
            // Reading: sent once, not again for less.
            stations.start(&threads());
            wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 13, 0, 1)]));
            host.settle().await;
            wire.answer("PUT /admin/api/threads/7/read", 200, json!({"viewer": "a@x.com", "thread": 7, "n": 13}));
            stations.read(&remote(), 7, 13).await.unwrap();
            stations.read(&remote(), 7, 12).await.unwrap();
            assert_eq!(wire.count("PUT", "/admin/api/threads/7/read"), 1);
            assert_eq!(wire.calls.borrow().iter().find(|(_, m, _, _)| m == "PUT").unwrap().3, br#"{"n":13}"#.to_vec());
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
            assert!(wire.paths().contains(&"GET /admin/api/events?live=k&from=0".to_string()));
            let push = |v: Value| wire.event("live", with_key("k", v));
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
            wire.end("/admin/api/events");
            wait(RECONNECT_MS + 50).await;
            assert!(wire.paths().contains(&"GET /admin/api/events?live=k&from=4".to_string()), "{:?}", wire.paths());
            // Reloaded: the kept transcript at once, and only what came after it is asked for.
            host.settle().await;
            let (reloaded, again, other) = reopened(&host);
            other.start(&live("k"));
            host.settle().await;
            assert_eq!(live_of(&reloaded, "k")["timeline"], json!(["a", "B", "c", "d"]));
            assert!(again.paths().contains(&"GET /admin/api/events?live=k&from=4".to_string()), "{:?}", again.paths());
            // Written anew and shorter: what is kept is cut there too.
            again.event("live", with_key("k", json!({"type": "timeline", "start": 1, "entries": [], "usage": {}})));
            host.settle().await;
            assert_eq!(live_of(&reloaded, "k")["timeline"], json!(["a"]));
            let (reloaded, _, other) = reopened(&host);
            other.start(&live("k"));
            host.settle().await;
            assert_eq!(live_of(&reloaded, "k")["timeline"], json!(["a"]));
            // A gap: from the start again, at once, and nothing kept.
            wire.event("live", with_key("k", json!({"type": "timeline", "start": 9, "entries": ["z"], "usage": {}})));
            host.settle().await;
            assert_eq!(wire.count("GET", "/admin/api/events?live=k&from=0"), 2);
            assert_eq!(live_of(&sink, "k")["loaded"], false);
            assert_eq!(host.stored("transcript/ws/st/k/meta"), None);
        });
    }

    #[test]
    fn a_stream_silent_past_its_keepalive_is_read_again() {
        run(async {
            let (host, _sink, wire, stations) = setup();
            // Timers 100 times faster: 40 s of silence is 0.4 s here.
            host.speed_up(100);
            let wait = |ms: u64| wait(ms / 100);
            stations.start(&live("k"));
            host.settle().await;
            assert_eq!(wire.count("GET", "/admin/api/events?live=k&from=0"), 1);
            // The keepalive keeps it open.
            wait(STREAM_IDLE_MS / 2).await;
            wire.push("/admin/api/events", ": ping\n\n");
            wait(STREAM_IDLE_MS / 2 + 5_000).await;
            assert_eq!(wire.count("GET", "/admin/api/events?live=k&from=0"), 1);
            // Nothing at all for longer: the link is taken for gone, and it is asked for again.
            wait(STREAM_IDLE_MS + RECONNECT_MS + 5_000).await;
            assert_eq!(wire.count("GET", "/admin/api/events?live=k&from=0"), 2);
        });
    }

    #[test]
    fn live_steps_and_phase() {
        run(async {
            let (host, sink, wire, stations) = setup();
            stations.start(&live("k"));
            host.settle().await;
            let push = |v: Value| wire.event("live", with_key("k", v));
            let now = host.now_ms();
            push(json!({"type": "steps", "steps": [{"id": "s0", "step": "text", "input": "", "startedAt": 1}], "phase": {"phase": "thinking", "elapsedMs": 5000}}));
            host.settle().await;
            let v = live_of(&sink, "k");
            assert_eq!(v["steps"][0]["id"], "s0");
            assert_eq!(v["phase"]["phase"], "thinking");
            let since = v["phase"]["since"].as_f64().unwrap();
            assert!((since - (now - 5000.0)).abs() < 1000.0, "{since} vs {now}");
            push(json!({"type": "step", "event": {"kind": "start", "id": "t1", "step": "tool", "tool": "Bash", "input": "ls"}}));
            push(json!({"type": "step", "event": {"kind": "end", "id": "t1"}}));
            push(json!({"type": "step", "event": {"kind": "phase", "phase": "responding"}}));
            host.settle().await;
            let v = live_of(&sink, "k");
            let t1 = &v["steps"][1];
            // What it is, not what it wrote: the station tells turning points only.
            assert_eq!((t1["tool"].as_str(), t1["input"].as_str(), t1["ended"].as_bool()), (Some("Bash"), Some("ls"), Some(true)));
            assert!(t1.get("output").is_none() && t1.get("text").is_none());
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
            assert_eq!((v["steps"][0]["step"].as_str(), v["steps"][0]["subagent"].as_bool(), v["steps"][0]["parent"].as_str()), (Some("text"), Some(true), Some("t0")));
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
            let stations = Stations::new(host.clone(), sink, RoutedWire::new(local.clone(), far.clone()), Tracer::new(host.clone(), 1.0), Kept::new(host.clone()));
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
