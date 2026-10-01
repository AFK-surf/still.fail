//! Stations' admin API, over mesh links, and the
//! station topics: overview, sessions, threads, chat rows, session, thread, live, host, link, job log.
//!
//! While any topic of a station is live, its `/admin/api/events` stream is held
//! open and is all that keeps the topics current: each topic is read once when
//! it starts, and again only after the stream was down. Events carry what
//! changed (a session's summary, a thread's new entries, a read position, a
//! row of the viewer's sidebar, the overview, host samples), which goes into
//! the topics as it is; what an event does not carry (a thread's unread count)
//! is read for that one thing. Host samples are asked for (`?host=1`) only
//! while a `host` topic is live. A
//! `live` topic is followed on the station's `/events`
//! (`?live=<key>&from=<entries known>&last=<TRANSCRIPT_PAGE>`): the transcript's
//! latest page (`first` says where it starts; `history.older` loads the pages
//! before it) and then as it grows, the steps in flight and the phase. A
//! `jobLog` topic is followed there too (`?job=<id>&lines=<n>`): the station
//! sends the lines again as the log grows. Nothing here runs on a timer but
//! reconnects, and reading a job's log again for a station that does not follow
//! it (one that does says so, `follows`, in the log it answers).
//!
//! A thread's entries and a session's transcript never change once written, so
//! they are kept on the device ([`Kept`]): a `thread` topic shows what is kept
//! at once and asks only for the entries after it (`?after=`), filling any gap
//! an event shows (`?from=&to=`); a `live` topic starts from the kept
//! transcript. Merging a thread's entries into messages is the `chat` view's
//! (entries.rs).

use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};
use std::future::Future;
use std::rc::{Rc, Weak};

use futures::future::{AbortHandle, Abortable, Either, LocalBoxFuture, join_all};
use futures::stream::LocalBoxStream;
use futures::{FutureExt, StreamExt, pin_mut};
use serde_json::{Value, json};

use crate::entries::n_of;
use crate::error::{CoreError, Result};
use crate::host::Host;
use crate::kept::{Kept, Log};
use crate::mesh::{CredentialSource, Link, LinkNet, Mesh, RequestHead};
use crate::protocol::Topic;
use crate::status::{Place, StatusOf, Waiting, station_what};
use crate::store::{Source, Store};
use crate::trace::{Kind, Span, SpanContext, Tracer, route};
use crate::wake;
use crate::workspace::{Workspace, Workspaces};

/// How long a failed or ended stream waits before it is opened again.
pub const RECONNECT_MS: u64 = 2_000;
/// A station not reached is tried again at RECONNECT_MS, doubling up to this.
pub const RECONNECT_MAX_MS: u64 = 60_000;
/// How many tries in a row a station that was up may miss (`reconnecting`) before it is taken for down (`offline`).
pub const MISSES: u32 = 3;
/// Where a station's last settled link state (online, offline) is kept, by station.
const LINK_KEY: &str = "link";
/// A topic whose first read failed in passing is read again after this, besides when the link comes back.
pub const RETRY_MS: u64 = 3_000;
/// A station's streams carry a keepalive every 25 s; one silent this long is on a link that is gone though nothing
/// said so, and is read again (from where it was).
pub const STREAM_IDLE_MS: u64 = 40_000;
/// A job's log on a station that does not follow it is read again after this, doubling while it stays the same, up
/// to LOG_READ_MAX_MS.
pub const LOG_READ_MS: u64 = 2_000;
pub const LOG_READ_MAX_MS: u64 = 60_000;
/// How long a preview's WebSocket may take to open: longer than the station gives the service (20 s), so this only
/// ends one nothing answers (an older station takes the socket for a request and waits for its body).
pub const SOCKET_OPEN_MS: u64 = 30_000;
/// A burst of `thread` events becomes one read of each thread's summary.
pub const EVENTS_COALESCE_MS: u64 = 400;
/// How often a station's connection is read while its card shows it (`Topic::Net`), and how many readings are kept
/// (a minute's).
pub const NET_EVERY_MS: u64 = 2_000;
const NET_KEPT: usize = 30;
/// Entries per page of a thread.
pub const PAGE: u64 = 50;
/// A chat shows a window of its thread's entries (docs: a chat opens where it is to be read, pages come in either way):
/// at most this many; a page coming in at one end lets as many go at the other.
pub const WINDOW: u64 = 3 * PAGE;
/// Entries per page of a session's transcript (a step is a call and its result, so more of them).
pub const TRANSCRIPT_PAGE: u64 = 200;
/// How many of a station's chats (the latest active) are kept current on the device ahead of being opened.
const WARM_CHATS: usize = 200;
/// The pause between two of them.
const WARM_GAP_MS: u64 = 150;
/// How long a chat opening waits for its station's list of threads being read (where reading stopped), at most.
const LIST_WAIT_MS: u64 = 3_000;

const EVENT_STREAM: &str = "text/event-stream";
/// How a stream ends whose link was replaced by another (it is opened again on it at once).
const REPLACED: &str = "换了一条连接";
/// A write's key (mesh/app/src/admin/once.rs).
pub const IDEMPOTENCY_KEY: &str = "idempotency-key";
/// On a station's every answer when it keeps a write asked with a key to once.
pub const IDEMPOTENT: &str = "stillfail-idempotent";

/// A request the wire may send twice: a read, or a write with its key to a station known to keep it to once.
/// A write asked again with its key once its station is back, while it was not answered: this long at most (a station
/// keeps a write's answer 10 minutes, mesh/app/src/admin/once.rs). Past it, nobody can say whether it was done.
pub const RECHECK_MS: f64 = 5.0 * 60.0 * 1000.0;
/// What a write asked again is waited on as (status.rs): the `doing` topic says so of the calls on that station.
pub const RECHECKING: &str = "等它回来确认";

/// A write that went and was not answered (its link gone, its station quiet): it may have been done, or not.
pub fn unconfirmed(why: &CoreError) -> CoreError {
    CoreError::new("unconfirmed", format!("不确定做没做成：{}", why.message))
}

fn may_repeat(head: &RequestHead, idempotent: bool) -> bool {
    head.method.eq_ignore_ascii_case("GET") || (idempotent && head.headers.iter().any(|(k, _)| k.eq_ignore_ascii_case(IDEMPOTENCY_KEY)))
}

/// `"<workspace>/<station>"`: every station is in a workspace.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct StationAddr {
    pub workspace: String,
    pub station: String,
}

impl StationAddr {
    pub fn parse(text: &str) -> Result<StationAddr> {
        // What a station's own page (gone) was: still in UIs' kept links and prefs.
        if text == "local" {
            return Err(CoreError::new("gone", "本机页面已经不再提供"));
        }
        match text.split_once('/') {
            Some((workspace, station)) if !workspace.is_empty() && !station.is_empty() && !station.contains('/') => {
                Ok(StationAddr { workspace: workspace.into(), station: station.into() })
            }
            _ => Err(CoreError::invalid(format!("不认识的站点地址：{text}"))),
        }
    }
}

impl std::fmt::Display for StationAddr {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}/{}", self.workspace, self.station)
    }
}

// ── the wire ────────────────────────────────────────────────────────────────

/// A station's answer: status, headers, and the body as it arrives.
pub struct WireReply {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: LocalBoxStream<'static, Result<Vec<u8>>>,
    /// How it came, when the wire knows: `relay` or `direct`.
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
    /// The way to the station is taken for gone (wake.rs): what is open to it closes, and the next request opens it anew.
    fn reset(&self, _station: &StationAddr) {}
    /// Whether the wire itself finds another way to a station when the UI comes back or the network changes (the
    /// mesh races a new link against each open one, mesh.rs `race`), rather than leaving it to the wake rules.
    fn races(&self) -> bool {
        false
    }
    /// Resolves once the way to the station that a request would take now is replaced by another: a stream on it is
    /// then opened again on the new one. Never, for a wire that does not race.
    fn replaced(&self, _station: &StationAddr) -> LocalBoxFuture<'static, ()> {
        futures::future::pending().boxed_local()
    }
    /// How the connection to the station runs now (its path, round trip, bytes both ways), for its card; None where
    /// there is none of its own to read (the page's own station, over HTTP) or none open.
    fn net(&self, _station: &StationAddr) -> Option<LinkNet> {
        None
    }
    /// Measures the ways to the station now (mesh.rs `Mesh::remeasure`). Only the mesh has more than one.
    fn measure(&self, _station: &StationAddr) -> LocalBoxFuture<'static, Result<()>> {
        async { Err(CoreError::new("unsupported", "这里只有一条路，不用测")) }.boxed_local()
    }
    /// A preview page's WebSocket (`head.path` a preview's): the station's reply, then its frames both ways
    /// ([`SocketFrame`]). Only the mesh carries one.
    fn socket(&self, _station: &StationAddr, _head: RequestHead) -> LocalBoxFuture<'static, Result<WireSocket>> {
        async { Err(CoreError::new("unsupported", "这里的预览还不支持 WebSocket")) }.boxed_local()
    }
}

/// A socket stream as it opened: the station's reply (101 once the service took the socket, else why not in its
/// body), the frames that come in the body, and where the client's frames go.
pub struct WireSocket {
    pub reply: WireReply,
    pub send: Box<dyn SocketOut>,
}

/// The client's half of a socket stream. Dropping it resets the stream.
pub trait SocketOut {
    fn write<'a>(&'a mut self, bytes: Vec<u8>) -> LocalBoxFuture<'a, Result<()>>;
    fn finish(&mut self);
}

impl SocketOut for crate::mesh::SocketSend {
    fn write<'a>(&'a mut self, bytes: Vec<u8>) -> LocalBoxFuture<'a, Result<()>> {
        async move { crate::mesh::SocketSend::write(self, &bytes).await }.boxed_local()
    }
    fn finish(&mut self) {
        crate::mesh::SocketSend::finish(self);
    }
}

/// A WebSocket message on a socket stream, framed as mesh/app/src/preview.rs frames it: a kind byte (1 text, 2 binary,
/// 8 close), the payload's length (4 bytes, big-endian), the payload; a close's is its code (2 bytes) and reason.
#[derive(Debug, Clone, PartialEq)]
pub enum SocketFrame {
    Text(String),
    Binary(Vec<u8>),
    Close(u16, String),
}

impl SocketFrame {
    pub fn encode(&self) -> Vec<u8> {
        let (kind, payload) = match self {
            SocketFrame::Text(text) => (1u8, text.as_bytes().to_vec()),
            SocketFrame::Binary(bytes) => (2, bytes.clone()),
            SocketFrame::Close(code, reason) => (8, [&code.to_be_bytes()[..], reason.as_bytes()].concat()),
        };
        let mut out = Vec::with_capacity(5 + payload.len());
        out.push(kind);
        out.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        out.extend(payload);
        out
    }

    /// The frames whole in `buf`, taken from it; what is left is the start of the next.
    pub fn take(buf: &mut Vec<u8>) -> Vec<SocketFrame> {
        let mut frames = Vec::new();
        let mut at = 0;
        while buf.len() - at >= 5 {
            let len = u32::from_be_bytes([buf[at + 1], buf[at + 2], buf[at + 3], buf[at + 4]]) as usize;
            if buf.len() - at - 5 < len {
                break;
            }
            let payload = &buf[at + 5..at + 5 + len];
            match buf[at] {
                1 => frames.push(SocketFrame::Text(String::from_utf8_lossy(payload).into_owned())),
                2 => frames.push(SocketFrame::Binary(payload.to_vec())),
                8 => {
                    let code = if payload.len() >= 2 { u16::from_be_bytes([payload[0], payload[1]]) } else { 1005 };
                    frames.push(SocketFrame::Close(code, String::from_utf8_lossy(payload.get(2..).unwrap_or_default()).into_owned()));
                }
                _ => {}
            }
            at += 5 + len;
        }
        buf.drain(..at);
        frames
    }
}

/// This device's endpoint, bound when first needed.
pub type MeshSource = Rc<dyn Fn() -> LocalBoxFuture<'static, Result<Rc<Mesh>>>>;
/// Grants for one station, given (workspace, station): the caller decides which account asks.
/// This device's credential for a workspace's stations (every one of them takes the same).
pub type StationCredentials = Rc<dyn Fn(&str) -> CredentialSource>;

/// Remote stations, over mesh links.
pub struct MeshWire {
    mesh: MeshSource,
    credentials: StationCredentials,
    /// Each workspace's waits: a link's are its workspace's, the relay brought up for it too.
    status: StatusOf,
    /// Stations that said they keep writes with a key to once ([`IDEMPOTENT`]), by id.
    idempotent: Rc<RefCell<HashSet<String>>>,
}

impl MeshWire {
    pub fn new(mesh: MeshSource, credentials: StationCredentials, status: StatusOf) -> Rc<MeshWire> {
        Rc::new(MeshWire { mesh, credentials, status, idempotent: Rc::default() })
    }
}

/// Whichever of two attempts answers; one that fails leaves it to the other.
async fn first_answer<T>(a: LocalBoxFuture<'static, Result<T>>, b: LocalBoxFuture<'static, Result<T>>) -> Result<T> {
    match futures::future::select(a, b).await {
        Either::Left((Ok(answer), _)) | Either::Right((Ok(answer), _)) => Ok(answer),
        Either::Left((Err(_), other)) | Either::Right((Err(_), other)) => other.await,
    }
}

impl StationWire for MeshWire {
    fn request(&self, station: &StationAddr, head: RequestHead, body: Vec<u8>) -> LocalBoxFuture<'static, Result<WireReply>> {
        let StationAddr { workspace, station } = station.clone();
        let mesh = (self.mesh)();
        let credentials = (self.credentials)(&workspace);
        let (status, address) = ((self.status)(&workspace), Place::Station(format!("{workspace}/{station}")));
        let (idempotent, reply_station) = (self.idempotent.clone(), station.clone());
        async move {
            // Bringing up the endpoint (the relay) and opening the link are waits of their own: a request slow for
            // them says so (status.rs).
            let mesh = {
                let _waiting = status.begin(Place::Relay, "连接", true);
                mesh.await?
            };
            let link = {
                let _waiting = status.begin(address.clone(), "连接", true);
                mesh.link(&station, credentials.clone()).await?
            };
            let repeats = may_repeat(&head, idempotent.borrow().contains(&station));
            let write = !head.method.eq_ignore_ascii_case("GET") && !head.method.eq_ignore_ascii_case("HEAD");
            let ask = |link: Rc<Link>, head: RequestHead, body: Vec<u8>| async move { link.request(head, body).await.map(|reply| (link, reply)) }.boxed_local();
            let first = ask(link.clone(), head.clone(), body.clone());
            let (link, reply) = if repeats {
                // The link is replaced while this is under way (it lost to a new one as the UI came back, mesh.rs
                // `race`): asked again on the new one at once, and whichever answers first is the answer. A read may be
                // asked twice; a write only with its key, to a station that keeps it to once.
                match futures::future::select(first, mesh.replaced(&station, &link)).await {
                    // A write gone and not answered: asked again with its key whenever its station is back, a while, so
                    // what is said is what happened (the station answers the first time's answer, or does it now).
                    Either::Left((Err(error), _)) if error.code == "mesh" && write => {
                        let _waiting = status.begin(address, RECHECKING, true);
                        let started = mesh.now_ms();
                        let mut pause = 1_000;
                        loop {
                            let again = async {
                                let link = mesh.link(&station, credentials.clone()).await?;
                                ask(link, head.clone(), body.clone()).await
                            };
                            match again.await {
                                Ok(answered) => break answered,
                                Err(e) if e.code != "mesh" => return Err(e),
                                Err(e) if mesh.now_ms() - started >= RECHECK_MS => return Err(unconfirmed(&e)),
                                Err(_) => {
                                    mesh.sleep(pause).await;
                                    pause = (pause * 2).min(15_000);
                                }
                            }
                        }
                    }
                    Either::Left((Err(error), _)) if error.code == "mesh" => {
                        // Its link went before it was answered (the station restarting, a network change): once more,
                        // on the link opened in its place.
                        let _waiting = status.begin(address, "连接", true);
                        let link = mesh.link(&station, credentials).await?;
                        drop(_waiting);
                        ask(link, head, body).await?
                    }
                    Either::Left((answered, _)) => answered?,
                    Either::Right((_, first)) => {
                        let again = async move {
                            let link = mesh.link(&station, credentials).await?;
                            ask(link, head, body).await
                        }
                        .boxed_local();
                        first_answer(first, again).await?
                    }
                }
            } else {
                // A station that may do a write twice is not asked again: one gone and not answered may have been done.
                first.await.map_err(|e| if write && e.code == "mesh" { unconfirmed(&e) } else { e })?
            };
            if reply.headers.iter().any(|(k, _)| k.eq_ignore_ascii_case(IDEMPOTENT)) {
                idempotent.borrow_mut().insert(reply_station);
            }
            let (status, headers) = (reply.status, reply.headers.clone());
            let body = futures::stream::unfold(reply, |mut reply| async move { reply.next().await.map(|chunk| (chunk, reply)) });
            Ok(WireReply { status, headers, body: body.boxed_local(), via: link.path() })
        }
        .boxed_local()
    }

    fn reset(&self, station: &StationAddr) {
        let station = &station.station;
        // Only a link already made: nothing to close before the endpoint is up.
        if let Some(Ok(mesh)) = (self.mesh)().now_or_never() {
            mesh.drop_link(station);
        }
    }

    fn races(&self) -> bool {
        true
    }

    fn replaced(&self, station: &StationAddr) -> LocalBoxFuture<'static, ()> {
        let (Some(Ok(mesh)), station) = ((self.mesh)().now_or_never(), station.station.clone()) else { return futures::future::pending().boxed_local() };
        let Some(link) = mesh.current(&station) else { return futures::future::pending().boxed_local() };
        mesh.replaced(&station, &link)
    }

    fn net(&self, station: &StationAddr) -> Option<LinkNet> {
        let Some(Ok(mesh)) = (self.mesh)().now_or_never() else { return None };
        mesh.current(&station.station).map(|link| LinkNet { measured: mesh.measured(&station.station), today: Some(mesh.today(&station.station)), ..link.net() })
    }

    fn measure(&self, station: &StationAddr) -> LocalBoxFuture<'static, Result<()>> {
        let (mesh, id) = ((self.mesh)(), station.station.clone());
        async move { mesh.await?.remeasure(&id).await }.boxed_local()
    }

    fn socket(&self, station: &StationAddr, head: RequestHead) -> LocalBoxFuture<'static, Result<WireSocket>> {
        let StationAddr { workspace, station } = station.clone();
        let mesh = (self.mesh)();
        let credentials = (self.credentials)(&workspace);
        let (status, address) = ((self.status)(&workspace), Place::Station(format!("{workspace}/{station}")));
        async move {
            let mesh = {
                let _waiting = status.begin(Place::Relay, "连接", true);
                mesh.await?
            };
            let link = {
                let _waiting = status.begin(address, "连接", true);
                mesh.link(&station, credentials).await?
            };
            let (reply, send) = link.socket(head).await?;
            let (status, headers) = (reply.status, reply.headers.clone());
            let body = futures::stream::unfold(reply, |mut reply| async move { reply.next().await.map(|chunk| (chunk, reply)) });
            Ok(WireSocket { reply: WireReply { status, headers, body: body.boxed_local(), via: link.path() }, send: Box::new(send) })
        }
        .boxed_local()
    }
}

/// The real wire: mesh links.
pub fn wire(mesh: MeshSource, credentials: StationCredentials, status: StatusOf) -> Rc<dyn StationWire> {
    MeshWire::new(mesh, credentials, status)
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

/// What is kept per station while any of its topics is live: its workspace's (workspace.rs).
pub(crate) struct StationState {
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
    /// Whether it follows jobs' logs on `/events` (as its answer to reading one says); None until one is read.
    follows_logs: Option<bool>,
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
            follows_logs: None,
        }
    }

    fn wants_host(&self) -> bool {
        self.topics.iter().any(|t| matches!(t, Topic::Host { .. }))
    }
}

/// What a station's `/events` stream is opened for, besides what every stream carries: host samples, the
/// sessions followed as they run (their transcript, steps and phase come on the same stream, in the one order with
/// the messages), and the jobs' logs followed (id, lines).
#[derive(Clone, Debug, Default, PartialEq)]
struct EventsFor {
    host: bool,
    live: Vec<String>,
    logs: Vec<(String, u64)>,
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
    json!({ "loaded": false, "first": 0, "timeline": [], "usage": null, "steps": [], "phase": null })
}

/// A job's log as its topic has it: what the station answers or sends of it, without the rest.
fn job_log(answer: &Value) -> Value {
    json!({ "text": answer.get("text").cloned().unwrap_or(json!("")), "outputAt": answer.get("outputAt").cloned().unwrap_or(Value::Null) })
}

/// Where a `live` topic's timeline starts in the transcript.
fn first_of(live: &Value) -> u64 {
    live.get("first").and_then(Value::as_u64).unwrap_or(0)
}

/// A `thread` topic's value: the entries loaded, `first ..= last` (none of an empty thread: `last` is `first - 1`),
/// and the thread's summary and sidebar title as kept, for the `chat` view to show before the station's `threads`
/// and rows are read.
/// `caught`: the last entry that came by reading (what is kept, a page, `?after=`) rather than as it was said (an event):
/// clients show what is caught up at once, and bring in only what comes after it.
/// `end`: the window reaches the thread's latest entry, so what is said next joins it; short of it, what is said waits
/// on the device until the window comes down to it.
/// Where a chat was left short of its end (`chat.place`): the entry at the top of what showed, and where its top was
/// (`offset`, below the top of the list; the client's own measure, absent from one that does not say).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct LeftAt {
    pub at: u64,
    pub offset: Option<f64>,
}

/// Where a chat's place is kept on the device.
fn place_key(station: &str, thread: u64) -> String {
    format!("place/{station}/{thread}")
}

fn thread_value(first: u64, entries: Vec<Value>, summary: Value, title: Value, end: bool) -> Value {
    let last = first + entries.len() as u64 - 1;
    json!({ "first": first, "last": last, "caught": last, "entries": entries, "thread": summary, "title": title, "end": end })
}

/// Whether a thread topic's window reaches its latest entry (a value from before windows always did).
fn at_end(value: &Value) -> bool {
    value.get("end").and_then(Value::as_bool) != Some(false)
}

/// The entries of an answer numbered `from ..= to`.
fn entries_in(answer: &Value, from: u64, to: u64) -> Vec<Value> {
    answer.get("entries").and_then(Value::as_array).into_iter().flatten().filter(|e| n_of(e).is_some_and(|n| (from..=to).contains(&n))).cloned().collect()
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
    /// Where each station's state is kept, and what is waited on for it (the `status` topic): its workspace.
    workspaces: Rc<Workspaces>,
    /// Where each chat was left, not at its end (`chat.place`): where it opens next, while nothing is unread. Kept on
    /// the device too (a core started anew, the page reloaded or the app opened again, finds it there): None, a chat
    /// read from there with none, or left at its end.
    places: RefCell<HashMap<(String, u64), Option<LeftAt>>>,
    /// Entries of a thread read apart from what is kept of it (a window far from its end, and the pages ahead of it,
    /// which the one run a log keeps does not take): held while its topic is, for the window to move through at once.
    loose: RefCell<HashMap<(String, u64), BTreeMap<u64, Value>>>,
    /// Stations whose chats are being brought up to date on the device now (`warm`), and threads caught up on after a
    /// gap an event showed.
    warming: RefCell<HashSet<String>>,
    /// (Whether another event came while it was caught up on: it looks again.)
    catching: RefCell<HashMap<(String, u64), bool>>,
    me: Weak<Stations>,
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
        span.set("stillfail.path", via);
    }
    if reply.status >= 500 {
        span.fail();
    }
}

impl Stations {
    pub fn new(host: Rc<dyn Host>, sink: Rc<dyn TopicSink>, wire: Rc<dyn StationWire>, tracer: Rc<Tracer>, kept: Rc<Kept>, workspaces: Rc<Workspaces>) -> Rc<Stations> {
        Rc::new_cyclic(|me| Stations { host, sink, wire, tracer, kept, workspaces, places: RefCell::default(), loose: RefCell::default(), warming: RefCell::default(), catching: RefCell::default(), me: me.clone() })
    }

    /// The workspace a station is in: where its state is kept and its waits go.
    fn of(&self, station: &str) -> Rc<Workspace> {
        self.workspaces.of_station(station)
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

    /// GET /sessions/:key/files?name=(&thumb=1): (content type, bytes). `progress` hears the bytes so far and the
    /// whole size (when the station gives it) as they come: now and then, not for every chunk.
    pub async fn file(&self, station: &StationAddr, key: &str, name: &str, thumb: bool, progress: impl Fn(u64, Option<u64>)) -> Result<(String, Vec<u8>)> {
        // A station from before thumbnails answers the image itself.
        let path = format!("/sessions/{}/files?name={}{}", encode(key), encode(name), if thumb { "&thumb=1" } else { "" });
        let (mut span, waiting, reply) = self.send(station, "GET", &path, Vec::new(), Vec::new(), false);
        let result = async {
            let mut reply = reply.await?;
            answered(&mut span, &reply);
            if reply.status != 200 {
                let status = reply.status;
                return Err(CoreError::new(format!("http_{status}"), "读不到文件").with_status(status));
            }
            let kind = reply.header("content-type").unwrap_or("").to_string();
            let total = reply.header("content-length").and_then(|n| n.trim().parse::<u64>().ok());
            // Every hundredth of it, or every 256 KB when its size is not known.
            let step = total.map_or(256 * 1024, |t| (t / 100).max(64 * 1024));
            progress(0, total);
            let (mut bytes, mut told) = (Vec::with_capacity(total.unwrap_or(0).min(64 << 20) as usize), 0u64);
            while let Some(chunk) = reply.body.next().await {
                let chunk = chunk?;
                match &waiting {
                    Some(waiting) => waiting.received(chunk.len()),
                    None => self.of(&station.to_string()).status.received(None, chunk.len()),
                }
                bytes.extend(chunk);
                let loaded = bytes.len() as u64;
                if loaded - told >= step {
                    progress(loaded, total);
                    told = loaded;
                }
            }
            span.set("http.response.body.size", bytes.len());
            Ok((kind, bytes))
        }
        .await;
        if let Err(error) = &result {
            failed(&mut span, error);
        }
        span.end();
        result
    }

    /// A request to a web service on the station's machine (`localhost:port`), passed through as it is: for a page
    /// of that service shown here. Answers its status, headers and body whatever the status.
    pub async fn preview(&self, station: &StationAddr, port: u16, method: &str, path: &str, headers: Vec<(String, String)>, body: Vec<u8>) -> Result<(u16, Vec<(String, String)>, Vec<u8>)> {
        let path = format!("/preview/{port}{}", if path.starts_with('/') { path.to_string() } else { format!("/{path}") });
        self.exchange(station, method, &path, headers, body, false, |reply| reply.headers.clone()).await
    }

    /// A preview request whose answer is handed on as it comes (an event stream, a long poll, a page still loading):
    /// its status and headers once they are there, then its body. It is waited on (status.rs) only until then; its
    /// body is dropped to stop it, and the station then stops asking the service.
    pub async fn preview_stream(&self, station: &StationAddr, port: u16, method: &str, path: &str, headers: Vec<(String, String)>, body: Vec<u8>) -> Result<(u16, Vec<(String, String)>, LocalBoxStream<'static, Result<Vec<u8>>>)> {
        let path = format!("/preview/{port}{}", if path.starts_with('/') { path.to_string() } else { format!("/{path}") });
        let (mut span, waiting, reply) = self.send(station, method, &path, headers, body, false);
        span.set("stillfail.stream", true);
        let reply = match reply.await {
            Ok(reply) => reply,
            Err(error) => {
                failed(&mut span, &error);
                span.end();
                return Err(error);
            }
        };
        drop(waiting);
        answered(&mut span, &reply);
        span.end();
        let status = Rc::downgrade(&self.of(&station.to_string()).status);
        let body = reply.body.inspect(move |chunk| {
            if let (Ok(chunk), Some(status)) = (chunk, status.upgrade()) {
                status.received(None, chunk.len());
            }
        });
        Ok((reply.status, reply.headers, body.boxed_local()))
    }

    /// A preview page's WebSocket to `path` of the service at `port`: open once the station answers 101 (else the
    /// station's reason, as an error with its status).
    pub async fn preview_socket(&self, station: &StationAddr, port: u16, path: &str, headers: Vec<(String, String)>) -> Result<WireSocket> {
        let path = format!("/admin/api/preview/{port}{}", if path.starts_with('/') { path.to_string() } else { format!("/{path}") });
        let _waiting = self.of(&station.to_string()).status.begin(Place::Station(station.to_string()), "打开网页服务的 WebSocket", false);
        let mut span = self.tracer.span(format!("SOCKET {}", route(&path)), Kind::Client);
        span.set("url.path", route(&path));
        span.set("stillfail.stream", true);
        let mut headers = headers;
        headers.push(("traceparent".into(), span.context().traceparent()));
        let opening = self.tracer.instrument(Some(span.context()), self.wire.socket(station, RequestHead { method: "GET".into(), path, headers }));
        let opened = match futures::future::select(opening, self.host.sleep(SOCKET_OPEN_MS)).await {
            Either::Left((opened, _)) => opened,
            // Let go, its stream is reset.
            Either::Right(_) => Err(CoreError::new("timeout", "网页服务的 WebSocket 没有打开：station 没有回应")),
        };
        let socket = match opened {
            Ok(socket) => socket,
            Err(error) => {
                failed(&mut span, &error);
                span.end();
                return Err(error);
            }
        };
        answered(&mut span, &socket.reply);
        span.end();
        if socket.reply.status != 101 {
            let status = socket.reply.status;
            let bytes = socket.reply.bytes().await.unwrap_or_default();
            let data: Value = serde_json::from_slice(&bytes).unwrap_or_else(|_| json!({}));
            return Err(http_error(status, &data));
        }
        Ok(socket)
    }

    /// Starts a request: its span (under the current trace, or a trace of its own), whose `traceparent` the
    /// request carries, what it is waited on as (none for one in the background, `quiet`), and the reply's head.
    fn send(&self, station: &StationAddr, method: &str, path: &str, mut headers: Vec<(String, String)>, body: Vec<u8>, quiet: bool) -> (Span, Option<Waiting>, LocalBoxFuture<'static, Result<WireReply>>) {
        let waiting = (!quiet).then(|| self.of(&station.to_string()).status.begin(Place::Station(station.to_string()), station_what(method, path), false));
        let path = format!("/admin/api{path}");
        let mut span = self.tracer.span(format!("{method} {}", route(&path)), Kind::Client);
        span.set("http.request.method", method.to_string());
        span.set("url.path", route(&path));
        span.set("stillfail.station", station.station.clone());
        if !body.is_empty() {
            span.set("http.request.body.size", body.len());
        }
        headers.push(("traceparent".into(), span.context().traceparent()));
        // A write carries a key of its own: a station that keeps writes to once (mesh/app/src/admin/once.rs) does it
        // once however often it arrives, so the wire may send it again on another way there (a link that went quiet).
        if !method.eq_ignore_ascii_case("GET") && !method.eq_ignore_ascii_case("HEAD") && !headers.iter().any(|(k, _)| k.eq_ignore_ascii_case(IDEMPOTENCY_KEY)) {
            let mut key = [0u8; 16];
            self.host.random_bytes(&mut key);
            headers.push((IDEMPOTENCY_KEY.into(), hex::encode(key)));
        }
        let head = RequestHead { method: method.to_string(), path, headers };
        // Under the request's span: opening the link it needs (a credential, a connection) shows as part of it.
        let reply = self.tracer.instrument(Some(span.context()), self.wire.request(station, head, body));
        (span, waiting, reply)
    }

    /// A reply's whole body, its bytes counted as they come (status.rs).
    async fn read_body(&self, station: &StationAddr, reply: WireReply, waiting: Option<&Waiting>) -> Result<Vec<u8>> {
        let mut body = reply.body;
        let mut out = Vec::new();
        while let Some(chunk) = body.next().await {
            let chunk = chunk?;
            match waiting {
                Some(waiting) => waiting.received(chunk.len()),
                None => self.of(&station.to_string()).status.received(None, chunk.len()),
            }
            out.extend(chunk);
        }
        Ok(out)
    }

    /// One whole request: its status, what `head` takes from the reply's head, and the body.
    async fn exchange<T>(&self, station: &StationAddr, method: &str, path: &str, headers: Vec<(String, String)>, body: Vec<u8>, quiet: bool, head: impl FnOnce(&WireReply) -> T) -> Result<(u16, T, Vec<u8>)> {
        let (mut span, waiting, reply) = self.send(station, method, path, headers, body, quiet);
        let result = async {
            let reply = reply.await?;
            answered(&mut span, &reply);
            let (status, taken) = (reply.status, head(&reply));
            let bytes = self.read_body(station, reply, waiting.as_ref()).await?;
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
        self.call_as(station, method, path, headers, body, false).await
    }

    /// A call, in the background (`quiet`): nobody waits on it, so it is not said to be waited on.
    async fn call_as(&self, station: &StationAddr, method: &str, path: &str, headers: Vec<(String, String)>, body: Vec<u8>, quiet: bool) -> Result<Value> {
        let (status, (), bytes) = self.exchange(station, method, path, headers, body, quiet, |_| ()).await?;
        // Like the web's `response.json().catch(() => ({}))`.
        let data: Value = serde_json::from_slice(&bytes).unwrap_or_else(|_| json!({}));
        if !(200..300).contains(&status) {
            return Err(http_error(status, &data));
        }
        Ok(data)
    }

    /// Opens an event stream; a non-2xx answer is an error. Its span ends when the stream is open.
    async fn open_stream(&self, station: &StationAddr, path: &str) -> Result<LocalBoxStream<'static, Result<Vec<u8>>>> {
        let (mut span, waiting, reply) = self.send(station, "GET", path, vec![("accept".into(), EVENT_STREAM.into())], Vec::new(), false);
        span.set("stillfail.stream", true);
        let reply = match reply.await {
            Ok(reply) => reply,
            Err(error) => {
                failed(&mut span, &error);
                return Err(error);
            }
        };
        // Open: what comes on it is no longer waited on, only counted.
        drop(waiting);
        answered(&mut span, &reply);
        span.end();
        if !(200..300).contains(&reply.status) {
            let status = reply.status;
            let bytes = reply.bytes().await.unwrap_or_default();
            let data: Value = serde_json::from_slice(&bytes).unwrap_or_else(|_| json!({}));
            return Err(http_error(status, &data));
        }
        let status = Rc::downgrade(&self.of(&station.to_string()).status);
        let body = reply.body.inspect(move |chunk| {
            if let (Ok(chunk), Some(status)) = (chunk, status.upgrade()) {
                status.received(None, chunk.len());
            }
        });
        Ok(idle_guarded(self.host.clone(), body.boxed_local()))
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
                // One archived, restored or deleted.
                touched.push(Topic::ArchivedRows { station: name.clone() });
                // Deleted, or its process ended: the footprint page counts it.
                touched.push(Topic::Footprint { station: name.clone() });
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
                // Into the archive or back: out of one list and into the other.
                if parts.get(2).map(String::as_str) == Some("archive") {
                    touched.retain(|t| !matches!(t, Topic::ChatRows { .. }));
                    touched.push(Topic::ChatRows { station: name.clone() });
                    touched.push(Topic::ArchivedRows { station: name.clone() });
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
            // Cleaned up or measured again: the footprint page, and the overview's line of it.
            Some("footprint") => {
                touched.push(Topic::Footprint { station: name.clone() });
                touched.push(Topic::Overview { station: name.clone() });
            }
            // The station's software: updated, checked, or put on another channel (its versions are the overview's).
            Some("updates") => touched.push(Topic::Overview { station: name.clone() }),
            // The workspace's Slack settings (its app configuration token): every connect's app reads through them.
            Some("slack") => {
                touched.push(Topic::Overview { station: name.clone() });
                touched.extend(self.live_topics(&name, |t| matches!(t, Topic::SlackApp { .. })));
            }
            // A job stopped: it answers the job as it is now.
            Some("jobs") if answer.get("id").is_some() && answer.get("state").is_some() => self.on_job(&name, answer),
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
        self.of(station).stations.borrow().get(station).is_some_and(|s| s.topics.contains(topic))
    }

    fn addr(&self, station: &str) -> Option<StationAddr> {
        self.of(station).stations.borrow().get(station).map(|s| s.addr.clone())
    }

    /// The station's live topics that `pick` chooses.
    fn live_topics(&self, station: &str, pick: impl Fn(&Topic) -> bool) -> Vec<Topic> {
        self.of(station).stations.borrow().get(station).map(|s| s.topics.iter().filter(|t| pick(t)).cloned().collect()).unwrap_or_default()
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
            Topic::ArchivedRows { .. } => "/chats?archived=1".to_string(),
            Topic::SlackApp { connect, .. } => format!("/connects/{}/slack-app", encode(connect)),
            Topic::Jobs { .. } => "/jobs".to_string(),
            // From this device's midnight 29 days ago, days as its clock has them.
            Topic::StationUsage { .. } => {
                let now = self.host.now_ms();
                let offset = self.host.utc_offset_min(now) as i64;
                let (day, local) = (86_400_000_i64, now as i64 + offset * 60_000);
                let from = local - local.rem_euclid(day) - 29 * day - offset * 60_000;
                format!("/usage?from={from}&tz={offset}")
            }
            Topic::Footprint { .. } => "/footprint".to_string(),
            Topic::Session { key, .. } => format!("/sessions/{}", encode(key)),
            Topic::JobLog { job, lines, .. } => format!("/jobs/{}/log?lines={lines}", encode(job)),
            // A thread shown at its end only asks for what came after it; one short of its end has nothing to catch up
            // on (what comes waits on the device); one not shown yet opens.
            Topic::Thread { thread, .. } => match self.sink.get(topic) {
                Some(value) if !at_end(&value) => return,
                Some(value) => format!("/threads/{thread}/entries?after={}", value.get("last").and_then(Value::as_u64).unwrap_or(0)),
                None => {
                    let (this, station, thread) = (self.rc(), topic.station().unwrap_or_default().to_string(), *thread);
                    // Boxed: this is inside reload.
                    let open: LocalBoxFuture<'static, ()> = async move { this.open_thread(&station, thread).await }.boxed_local();
                    return open.await;
                }
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
                self.put_entries(station, *thread, entries, false);
            }
            (Topic::JobLog { station, .. }, Ok(answer)) => {
                let follows = answer.get("follows").and_then(Value::as_bool) == Some(true);
                if let Some(s) = self.of(station).stations.borrow_mut().get_mut(station) {
                    s.follows_logs = Some(follows);
                }
                self.sink.set(topic, Ok(job_log(&answer)));
            }
            (_, Ok(value)) => self.sink.set(topic, Ok(value)),
            (_, Err(error)) => {
                // What it had stays. With nothing yet: a station that answered no (4xx) says so; a failure that passes
                // (the link down, a timeout, a 5xx) leaves it loading, read again once the link is back, and once shortly.
                if self.sink.get(topic).is_none() {
                    if error.status.is_some_and(|s| (400..500).contains(&s)) {
                        self.sink.set(topic, Err(error));
                    } else {
                        if let Some(station) = topic.station() {
                            self.set_stale(station, true);
                        }
                        let (this, topic) = (self.rc(), topic.clone());
                        // Boxed: this is inside reload.
                        let again: LocalBoxFuture<'static, ()> = async move {
                            this.host.sleep(RETRY_MS).await;
                            if this.sink.get(&topic).is_none() {
                                this.reload(&topic).await;
                            }
                        }
                        .boxed_local();
                        self.spawn_in(None, again);
                    }
                }
            }
        }
        if matches!(topic, Topic::Threads { .. } | Topic::Session { .. } | Topic::ChatRows { .. }) && let Some(station) = topic.station() {
            self.keep_summaries(station);
        }
        if let Topic::ChatRows { station } = topic {
            let first = self.of(station).stations.borrow_mut().get_mut(station).is_some_and(|s| !std::mem::replace(&mut s.warmed, true));
            if first && self.sink.get(topic).is_some() {
                let (this, station) = (self.rc(), station.clone());
                self.spawn_in(None, async move { this.warm(&station).await });
            }
        }
    }

    /// Once a station's sidebar rows are read, and each time its link is back, the chats they list are brought up to
    /// date on the device in the background, one after another, the latest active first: those behind the station's
    /// list only (the rest ask nothing), each by what came after what is kept (its latest page when that is more than a
    /// page, or nothing is kept), with its summary and title. So a chat opens whole from the device rather than waiting
    /// for the station. Chats open meanwhile read themselves; it stops when the station is no longer in use.
    async fn warm(&self, station: &str) {
        if !self.reachable(station) || !self.warming.borrow_mut().insert(station.to_string()) {
            return;
        }
        self.warm_all(station).await;
        self.warming.borrow_mut().remove(station);
    }

    async fn warm_all(&self, station: &str) {
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
        // The summaries a chat opens with, and how far each thread goes (as the station lists its threads).
        let threads = self.call_as(&addr, "GET", "/threads", Vec::new(), Vec::new(), true).await.ok();
        for (_, id, title) in chats {
            if self.addr(station).is_none() || !self.reachable(station) {
                return;
            }
            let topic = Topic::Thread { station: station.into(), thread: id };
            if self.is_live(&topic) {
                continue;
            }
            let log = Log::thread(station, id);
            let summary = threads.as_ref().and_then(|t| t.as_array()?.iter().find(|t| t.get("id").and_then(Value::as_u64) == Some(id)).cloned());
            let listed = summary.as_ref().and_then(|t| t.get("last")?.as_u64());
            let kept_last = self.kept.held_of(&log).await.map(|held| held.last);
            let title = title.is_string().then_some(title);
            if kept_last.is_some_and(|k| listed.is_some_and(|l| k >= l)) {
                self.kept.summary(&log, summary, title).await;
                continue;
            }
            let path = match kept_last {
                Some(last) if listed.is_some_and(|l| l - last <= PAGE) => format!("/threads/{id}/entries?after={last}"),
                _ => format!("/threads/{id}/entries?limit={PAGE}"),
            };
            let Ok(answer) = self.call_as(&addr, "GET", &path, Vec::new(), Vec::new(), true).await else { continue };
            let entries = answer.get("entries").and_then(Value::as_array).cloned().unwrap_or_default();
            if let Some(first) = entries.first().and_then(n_of) {
                self.kept.write(&log, first, entries, false, summary.clone()).await;
            }
            self.kept.summary(&log, summary, title).await;
            // Gently: one chat at a time, with room between for what the viewer asks.
            self.host.sleep(WARM_GAP_MS).await;
        }
    }

    /// Said in a chat not shown (or shown short of its end), past a gap in what is kept of it: what came after what
    /// is kept is read, once at a time, so it stays whole on the device.
    fn catch_up_kept(&self, station: &str, id: u64, from: u64) {
        let key = (station.to_string(), id);
        if !self.reachable(station) {
            return;
        }
        if let Some(again) = self.catching.borrow_mut().get_mut(&key) {
            *again = true;
            return;
        }
        let Some(addr) = self.addr(station) else { return };
        let this = self.rc();
        self.catching.borrow_mut().insert(key.clone(), false);
        self.spawn(async move {
            let log = Log::thread(&key.0, id);
            // What was said last, as far as told: past what is kept, a gap.
            let mut told = from;
            loop {
                if let Some(held) = this.kept.held_of(&log).await
                    && told > held.last + 1
                    && let Ok(answer) = this.call_as(&addr, "GET", &format!("/threads/{id}/entries?after={}", held.last), Vec::new(), Vec::new(), true).await
                {
                    let entries: Vec<Value> = answer.get("entries").and_then(Value::as_array).into_iter().flatten().filter(|e| n_of(e).is_some_and(|n| n > held.last)).cloned().collect();
                    this.kept.extend(&log, held.last + 1, entries).await;
                }
                let again = this.catching.borrow_mut().get_mut(&key).is_some_and(|a| std::mem::replace(a, false));
                if !again {
                    break;
                }
                told = this.latest_known(&key.0, id).await.map_or(told, |l| l.max(told));
            }
            this.catching.borrow_mut().remove(&key);
        });
    }

    /// After the events stream was down: everything it may have missed is read once, as part of `span` (the
    /// reconnect), which ends when they are all read.
    fn refetch_all(&self, station: &str, span: Span) {
        let topics = self.live_topics(station, |t| {
            matches!(t, Topic::Overview { .. } | Topic::Sessions { .. } | Topic::Threads { .. } | Topic::ChatRows { .. } | Topic::ArchivedRows { .. } | Topic::Session { .. } | Topic::Thread { .. })
        });
        let this = self.rc();
        let name = station.to_string();
        self.spawn_in(Some(span.context()), async move {
            join_all(topics.iter().map(|topic| this.reload(topic))).await;
            span.end();
            // What each chat missed meanwhile, onto the device.
            this.warm(&name).await;
        });
    }

    /// Whether the station is worth asking now: not while its link has found it down (`offline`) — its topics are
    /// served from what was kept (the data center, the device's logs) and read again when the link is back. Whether it
    /// is up is this device's own finding, by reaching it (the events stream), not anyone else's say.
    fn reachable(&self, station: &str) -> bool {
        self.of(station).stations.borrow().get(station).is_none_or(|s| s.link.get("state").and_then(Value::as_str) != Some("offline"))
    }

    fn set_link(&self, station: &str, value: Value) {
        // What it settled on (up, or down) is kept, so the next start shows it until the link finds out anew.
        if let Some(state @ ("online" | "offline")) = value.get("state").and_then(Value::as_str) {
            let was = self.of(station).stations.borrow().get(station).and_then(|s| s.link.get("state").and_then(Value::as_str).map(str::to_string));
            if was.as_deref() != Some(state) {
                let (host, key, state) = (self.host.clone(), format!("{LINK_KEY}/{station}"), state.to_string());
                self.spawn(async move {
                    let _ = host.storage_set(&key, state.into_bytes()).await;
                });
            }
        }
        let live = {
            let workspace = self.of(station);
            let mut stations = workspace.stations.borrow_mut();
            let Some(s) = stations.get_mut(station) else { return };
            s.link = value.clone();
            s.topics.contains(&Topic::Link { station: station.into() })
        };
        if live {
            self.sink.set(&Topic::Link { station: station.into() }, Ok(value));
        }
    }

    /// Reads the connection to the station every [`NET_EVERY_MS`] while `topic` is watched, and keeps the last
    /// [`NET_KEPT`] readings: `{ path, relay, rttMs, rxBytes, txBytes, todayRxBytes, todayTxBytes, samples: [{ at, rttMs,
    /// rxBps, txBps, sent, lost }] }`, or null while there is no connection. Bytes are the connection's since it opened
    /// (a new one starts over); today's are all of the station's links' on this device today, where the wire counts them.
    async fn sample_net(self: Rc<Self>, topic: Topic, addr: StationAddr) {
        let mut last: Option<(f64, LinkNet)> = None;
        let mut samples: VecDeque<Value> = VecDeque::new();
        loop {
            if !self.is_live(&topic) {
                return;
            }
            let now = self.host.now_ms();
            let value = match self.wire.net(&addr) {
                None => {
                    last = None;
                    samples.clear();
                    Value::Null
                }
                Some(net) => {
                    // What went over it since the reading before; none for a connection opened since (its counts
                    // start again).
                    let since = last.as_ref().filter(|(_, was)| net.rx_bytes >= was.rx_bytes && net.tx_bytes >= was.tx_bytes);
                    if let Some((at, was)) = since {
                        let secs = ((now - at) / 1000.0).max(0.001);
                        samples.push_back(json!({
                            "at": now.round(),
                            "rttMs": net.rtt_ms,
                            "rxBps": ((net.rx_bytes - was.rx_bytes) as f64 / secs).round(),
                            "txBps": ((net.tx_bytes - was.tx_bytes) as f64 / secs).round(),
                            "sent": net.tx_packets.saturating_sub(was.tx_packets),
                            "lost": net.lost_packets.saturating_sub(was.lost_packets),
                        }));
                    } else {
                        samples.clear();
                    }
                    while samples.len() > NET_KEPT {
                        samples.pop_front();
                    }
                    let measured = net.measured.as_ref().map(|m| json!({
                        "measuring": m.measuring,
                        "relays": m.relays.iter().map(|(relay, ms)| json!({ "relay": relay, "rttMs": ms })).collect::<Vec<_>>(),
                        "moved": m.moved,
                    }));
                    let value = json!({
                        "path": net.path, "relay": net.relay, "rttMs": net.rtt_ms,
                        "rxBytes": net.rx_bytes, "txBytes": net.tx_bytes, "samples": samples, "measured": measured,
                        "todayRxBytes": net.today.map(|t| t.0), "todayTxBytes": net.today.map(|t| t.1),
                    });
                    last = Some((now, net));
                    value
                }
            };
            if self.sink.get(&topic).as_ref() != Some(&value) {
                self.sink.set(&topic, Ok(value));
            }
            self.host.sleep(NET_EVERY_MS).await;
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
        let mut logs: Vec<(String, u64)> = self
            .live_topics(station, |t| matches!(t, Topic::JobLog { .. }))
            .into_iter()
            .filter_map(|t| match t {
                Topic::JobLog { job, lines, .. } => Some((job, lines)),
                _ => None,
            })
            .collect();
        logs.sort();
        let (addr, wants, generation) = {
            let workspace = self.of(station);
            let mut stations = workspace.stations.borrow_mut();
            let Some(s) = stations.get_mut(station) else { return };
            let wants = EventsFor { host: s.wants_host(), live, logs };
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
        if let Some(s) = self.of(station).stations.borrow_mut().get_mut(station) {
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
            let from = self.sink.get(&topic).and_then(|v| Some(first_of(&v) + v.get("timeline")?.as_array()?.len() as u64)).unwrap_or(0);
            // No more than the latest page: a station older than `last` sends all from `from`.
            query.push(format!("live={}&from={from}&last={TRANSCRIPT_PAGE}", encode(key)));
        }
        // A station older than `job` leaves it out (and its log is read again instead, see `follow_log`).
        for (job, lines) in &wants.logs {
            query.push(format!("job={}&lines={lines}", encode(job)));
        }
        if query.is_empty() { "/events".into() } else { format!("/events?{}", query.join("&")) }
    }

    /// Whether this stream is the station's newest; if so, the one it replaces goes now.
    fn took_over(&self, station: &str, generation: u64) -> bool {
        let workspace = self.of(station);
        let mut stations = workspace.stations.borrow_mut();
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
        self.of(station).stations.borrow().get(station).is_some_and(|s| s.generation == generation)
    }

    fn set_stale(&self, station: &str, stale: bool) -> bool {
        self.of(station).stations.borrow_mut().get_mut(station).map(|s| std::mem::replace(&mut s.stale, stale)).unwrap_or(false)
    }

    /// Holds the station's `/events` open while any of its topics is live; its events keep the topics current.
    async fn follow_events(self: Rc<Self>, station: String, addr: StationAddr, wants: EventsFor, generation: u64, mut parent: Option<SpanContext>) {
        let mut first = true;
        // How the last stream ended and how long it lasted: on the reconnect's span, so a stream that keeps ending shows why.
        let mut previous: Option<(String, f64)> = None;
        // Tries in a row that did not reach it, and whether it was reached before: a station that was up and dropped
        // is coming back (`reconnecting`) for a few tries; one not reached for MISSES, or never, is down (`offline`).
        let mut misses: u32 = 0;
        let mut reached = false;
        loop {
            // Replaced before it opened: its successor asks instead.
            if !self.is_current(&station, generation) {
                return;
            }
            let name = if std::mem::replace(&mut first, false) { "station.connect" } else { "station.reconnect" };
            let mut span = self.tracer.enter(parent.take(), || self.tracer.span(name, Kind::Internal));
            span.set("stillfail.station", station.clone());
            if let Some((why, lasted)) = previous.take() {
                span.set("stillfail.previous.end", why);
                span.set("stillfail.previous.lasted_ms", lasted.round() as i64);
            }
            // Asked anew each time: a session is followed from what its topic has by then.
            let path = self.events_path(&station, &wants);
            let opening = self.tracer.instrument(Some(span.context()), self.open_stream(&addr, &path));
            // Still opening when the UI came back from being away since before: on a way taken for gone, tried anew now.
            // (A wire that races its links asks again on the new one itself.)
            let sent = self.host.now_ms();
            let races = self.wire.races();
            let dropped = {
                let this = self.clone();
                let station = station.clone();
                async move {
                    loop {
                        let wake = wake::woken_for(this.host.clone(), move |w| w.suspects_connections() || w.drops_request(sent)).await;
                        if !races && wake.drops_request(sent) {
                            return;
                        }
                        // Tried again beside this try (mesh.rs `hedge`), as a person tapped 重试: said at once.
                        this.retrying(&station);
                    }
                }
            };
            pin_mut!(opening, dropped);
            let opened = match futures::future::select(opening, dropped).await {
                Either::Left((opened, _)) => opened,
                Either::Right(_) => {
                    self.wire.reset(&addr);
                    span.fail();
                    span.end();
                    previous = Some((wake::GONE.to_string(), 0.0));
                    self.set_stale(&station, true);
                    continue;
                }
            };
            if !self.took_over(&station, generation) {
                return;
            }
            match opened {
                Ok(mut body) => {
                    misses = 0;
                    reached = true;
                    self.set_link(&station, json!({ "state": "online" }));
                    // Down for a while: what changed meanwhile was not told.
                    if self.set_stale(&station, false) {
                        self.refetch_all(&station, span);
                    } else {
                        span.end();
                    }
                    let mut parser = SseParser::default();
                    let opened_at = self.host.now_ms();
                    let mut why = "ended".to_string();
                    let mut heard = opened_at;
                    // The way it came is replaced by another (a link that lost to a new one, mesh.rs `race`): opened
                    // again at once on the new one, the old one not waited on.
                    let replaced = self.wire.replaced(&addr).shared();
                    loop {
                        // Nothing on it while the UI was away (not even the keepalive): taken for gone, and the link with
                        // it. A wire that races its links finds out itself, sooner: its link is replaced, or kept.
                        let gone = wake::woken_for(self.host.clone(), move |w| !races && w.drops_stream(heard)).boxed_local();
                        let ended = futures::future::select(gone, replaced.clone());
                        pin_mut!(ended);
                        let chunk = match futures::future::select(body.next(), ended).await {
                            Either::Left((Some(chunk), _)) => chunk,
                            Either::Left((None, _)) => break,
                            Either::Right((Either::Left(_), _)) => {
                                self.wire.reset(&addr);
                                why = wake::GONE.to_string();
                                break;
                            }
                            Either::Right((Either::Right(_), _)) => {
                                why = REPLACED.to_string();
                                break;
                            }
                        };
                        heard = self.host.now_ms();
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
                    let woke = why == wake::GONE || why == wake::NETWORK || why == REPLACED;
                    if !self.is_current(&station, generation) {
                        return;
                    }
                    previous = Some((why.clone(), self.host.now_ms() - opened_at));
                    self.set_stale(&station, true);
                    self.set_link(&station, json!({ "state": "reconnecting", "message": if why == "ended" { "连接断开了".to_string() } else { why } }));
                    // Taken for gone as the UI came back: opened again at once.
                    if woke {
                        continue;
                    }
                }
                Err(error) => {
                    failed(&mut span, &error);
                    span.end();
                    previous = Some((format!("open failed: {}", error.message), 0.0));
                    self.set_stale(&station, true);
                    misses += 1;
                    // It answered, but no (refused, failing): it is there. Not reached at all: coming back, or down.
                    let state = if error.status.is_some() { "error" } else if reached && misses < MISSES { "reconnecting" } else { "offline" };
                    self.set_link(&station, json!({ "state": state, "message": error.message }));
                }
            }
            // Not reached: less and less often, up to RECONNECT_MAX_MS.
            let wait = RECONNECT_MS.saturating_mul(1u64 << misses.saturating_sub(1).min(8)).min(RECONNECT_MAX_MS);
            // A UI back after being away wants it now: no more waiting.
            if let Either::Right(_) = futures::future::select(self.host.sleep(wait), self.host.woken()).await {
                self.retrying(&station);
            }
        }
    }

    /// Down, and tried again now (a person tapped 重试, the UI came back, the network changed): `reconnecting` until
    /// the try ends, so what shows the link shows it is being tried rather than still down.
    fn retrying(&self, station: &str) {
        let link = self.of(station).stations.borrow().get(station).map(|s| s.link.clone());
        let Some(link) = link else { return };
        if matches!(link.get("state").and_then(Value::as_str), Some("offline" | "error")) {
            self.set_link(station, json!({ "state": "reconnecting", "message": link.get("message").cloned().unwrap_or(Value::Null) }));
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
                let entries = data.get("entries").and_then(Value::as_array).cloned().unwrap_or_default();
                // How far the thread goes, at once (a chat opens whole by it: `latest_known`); the rest of its summary
                // is read below.
                if let Some(newest) = entries.iter().filter_map(n_of).max() {
                    self.sink.update(&Topic::Threads { station: station.into() }, &mut |list| {
                        for t in list.as_array_mut().into_iter().flatten() {
                            if t.get("id").and_then(Value::as_u64) == Some(id) && t.get("last").and_then(Value::as_u64).is_some_and(|l| l < newest) {
                                t["last"] = json!(newest);
                            }
                        }
                    });
                }
                self.put_entries(station, id, entries, true);
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
                    // Entries with no timeline to go in: that session from its latest page, on a stream opened anew.
                    let topic = Topic::Live { station: station.into(), key: key.into() };
                    if let Some(s) = self.of(station).stations.borrow_mut().get_mut(station).and_then(|s| s.lives.get_mut(key)) {
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
            "job" => self.on_job(station, &data),
            // A job that was over, cleared: out of its session's jobs.
            "job-removed" => {
                let (Some(id), Some(key)) = (data.get("id").and_then(Value::as_str), data.get("session").and_then(Value::as_str)) else { return };
                self.sink.update(&Topic::Session { station: station.into(), key: key.into() }, &mut |detail| {
                    if let Some(jobs) = detail.get_mut("jobs").and_then(Value::as_array_mut) {
                        jobs.retain(|j| j.get("id").and_then(Value::as_str) != Some(id));
                    }
                });
            }
            // A followed job's log, at first and as it grows.
            "job-log" => {
                let (Some(id), Some(lines)) = (data.get("id").and_then(Value::as_str), data.get("lines").and_then(Value::as_u64)) else { return };
                self.set_live(Topic::JobLog { station: station.into(), job: id.into(), lines }, job_log(&data));
            }
            "overview" => self.set_live(Topic::Overview { station: station.into() }, data),
            "host" => self.set_live(Topic::Host { station: station.into() }, data),
            // It recorded more of what its agents spent (about once a minute while they work).
            "usage" => self.refetch(&Topic::StationUsage { station: station.into() }),
            "footprint" => self.set_live(Topic::Footprint { station: station.into() }, data),
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

    /// A job as it is now (its event, or the answer to stopping it): in place in its session's jobs, and among the
    /// station's open ones while it is open (running, or a service being started again).
    fn on_job(&self, station: &str, job: &Value) {
        let (Some(id), Some(key)) = (job.get("id").and_then(Value::as_str), job.get("session").and_then(Value::as_str)) else { return };
        // Shown by itself (a service's page, jobs.rs): as it is now.
        self.sink.update(&Topic::Job { station: station.into(), id: id.into() }, &mut |shown| *shown = job.clone());
        self.sink.update(&Topic::Session { station: station.into(), key: key.into() }, &mut |detail| {
            // A station yet to list jobs with a session has none to put it in.
            let Some(jobs) = detail.get_mut("jobs").and_then(Value::as_array_mut) else { return };
            match jobs.iter().position(|j| j.get("id").and_then(Value::as_str) == Some(id)) {
                Some(i) => jobs[i] = job.clone(),
                None => jobs.insert(0, job.clone()),
            }
        });
        let open = job.get("state").and_then(Value::as_str) == Some("running")
            || (job.get("state").and_then(Value::as_str) == Some("exited") && job.get("port").is_some_and(|p| !p.is_null()));
        let topic = Topic::Jobs { station: station.into() };
        let mut unknown = false;
        self.sink.update(&topic, &mut |list| {
            let Some(list) = list.as_array_mut() else { return };
            match (list.iter().position(|j| j.get("id").and_then(Value::as_str) == Some(id)), open) {
                // What chat it is in stays as the station said.
                (Some(i), true) => {
                    let chat = list[i].get("chat").cloned();
                    list[i] = job.clone();
                    if let Some(chat) = chat {
                        list[i]["chat"] = chat;
                    }
                }
                (Some(i), false) => {
                    list.remove(i);
                }
                // A new one: which chat it is in is the station's to say.
                (None, true) => unknown = true,
                (None, false) => {}
            }
        });
        if unknown {
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

    /// A `jobLog` topic: read once; after that the station's events keep it current, or, for a station that does not
    /// follow jobs' logs (nor has said yet), it is read again now and then: soon while it grows, less often while not.
    async fn follow_log(self: Rc<Self>, topic: Topic) {
        let Some(station) = topic.station().map(str::to_string) else { return };
        let mut wait = LOG_READ_MS;
        loop {
            let before = self.sink.get(&topic);
            self.reload(&topic).await;
            let follows = self.of(&station).stations.borrow().get(&station).and_then(|s| s.follows_logs);
            if !self.is_live(&topic) || follows == Some(true) {
                return;
            }
            wait = if self.sink.get(&topic) == before { (wait * 2).min(LOG_READ_MAX_MS) } else { LOG_READ_MS };
            self.host.sleep(wait).await;
        }
    }

    // ── threads ──

    /// Keeps entries read of a thread: with what is kept where they join it, else held loose.
    fn keep_entries(&self, station: &str, id: u64, entries: Vec<Value>) {
        let Some(first) = entries.first().and_then(n_of) else { return };
        let (this, station) = (self.rc(), station.to_string());
        self.host.spawn(async move {
            if this.kept.join(&Log::thread(&station, id), first, entries.clone()).await {
                return;
            }
            let mut loose = this.loose.borrow_mut();
            let held = loose.entry((station, id)).or_default();
            // Far more than a window moves through: what was held goes.
            if held.len() as u64 + entries.len() as u64 > 4 * WINDOW {
                held.clear();
            }
            held.extend(entries.into_iter().filter_map(|e| Some((n_of(&e)?, e))));
        }.boxed_local());
    }

    /// Entries `from ..= to` of a thread, if all of them are on the device (kept, or held loose).
    async fn have(&self, station: &str, id: u64, from: u64, to: u64) -> Option<Vec<Value>> {
        if from > to {
            return None;
        }
        if let Some(entries) = self.kept.range(&Log::thread(station, id), from, to).await {
            return Some(entries);
        }
        let loose = self.loose.borrow();
        let held = loose.get(&(station.to_string(), id))?;
        (from..=to).map(|n| held.get(&n).cloned()).collect()
    }

    /// Up to `count` entries just before `before`, if they are on the device: kept (as far as it goes), or held loose.
    async fn have_before(&self, station: &str, id: u64, before: u64, count: u64) -> Option<Vec<Value>> {
        if let Some(entries) = self.kept.before(&Log::thread(station, id), before, count).await {
            return Some(entries);
        }
        self.have(station, id, before.saturating_sub(count).max(1), before.checked_sub(1)?).await
    }

    /// Opens a `thread` topic where the chat is to be read, whole from the first value on (nothing is filled in under
    /// the reader afterwards): at the first entry not read while something is unread, else where it was left (not at
    /// its end: `place`), else at its end. Then the page on either side is brought onto the device ahead.
    async fn open_thread(&self, station: &str, id: u64) {
        let topic = Topic::Thread { station: station.into(), thread: id };
        if self.sink.get(&topic).is_some() {
            return self.reload(&topic).await;
        }
        // Where reading stopped, as the station's list says: while it is being read (the app just opened), once it is;
        // with no list read, asked for this one.
        let threads = Topic::Threads { station: station.into() };
        let mut summary = self.summary(station, id);
        let mut waited = 0;
        while summary.is_none() && self.is_live(&threads) && self.sink.get(&threads).is_none() && self.reachable(station) && waited < LIST_WAIT_MS {
            self.host.sleep(50).await;
            waited += 50;
            summary = self.summary(station, id);
        }
        if summary.is_none()
            && self.reachable(station)
            && let Some(addr) = self.addr(station)
            && let Ok(view) = self.call(&addr, "GET", &format!("/threads/{id}"), Vec::new(), Vec::new()).await
        {
            self.put_thread(station, &view);
            summary = Some(view);
        }
        let unread = summary.as_ref().and_then(|t| t.get("unread")?.as_u64()).unwrap_or(0);
        let read = summary.as_ref().and_then(|t| t.get("read")?.as_u64());
        let place = self.place_of(station, id).await;
        let (at, offset) = match read {
            Some(read) if unread > 0 => (Some(read + 1), None),
            _ => (place.map(|p| p.at), place.and_then(|p| p.offset)),
        };
        let Some(mut value) = self.window(station, id, at).await else { return };
        // Opened where it was left: where that entry's top was, too.
        if let Some(offset) = offset
            && value.get("at").is_some()
        {
            value["atOffset"] = json!(offset);
        }
        if !self.is_live(&topic) || self.sink.get(&topic).is_some() {
            return;
        }
        self.sink.set(&topic, Ok(value));
        // Said while it was being read, kept meanwhile: onto it, as said.
        if let Some(last) = self.sink.get(&topic).filter(at_end).and_then(|v| v.get("last")?.as_u64())
            && let Some(held) = self.kept.held_of(&Log::thread(station, id)).await
            && held.last > last
            && let Some(told) = self.kept.range(&Log::thread(station, id), last + 1, held.last).await
        {
            self.put_entries(station, id, told, true);
        }
        self.ahead(station, id);
    }

    /// A thread's latest entry, as the station's list says (it follows its events, a moment behind), or as far as what
    /// is kept goes past it (events carry on what is kept at once); unknown while the list is not read.
    async fn latest_known(&self, station: &str, id: u64) -> Option<u64> {
        let listed = self.summary(station, id).and_then(|t| t.get("last")?.as_u64())?;
        let kept = self.kept.held_of(&Log::thread(station, id)).await.map_or(0, |h| h.last);
        Some(listed.max(kept))
    }

    /// The window a chat shows around entry `at` (a page before it and a page from it on), or its latest page: from
    /// what is kept when all of it is and it is known to be current, else read from the station (and kept). Offline,
    /// the latest page kept is all there is. None while nothing can be had.
    async fn window(&self, station: &str, id: u64, at: Option<u64>) -> Option<Value> {
        let log = Log::thread(station, id);
        let held = self.kept.held_of(&log).await;
        let summary = self.summary(station, id);
        let latest = self.latest_known(station, id).await;
        let (thread, title) = held.as_ref().map_or((Value::Null, Value::Null), |h| (h.thread.clone(), h.title.clone()));
        let thread = summary.clone().unwrap_or(thread);
        let reachable = self.reachable(station);
        let addr = self.addr(station).filter(|_| reachable);
        if let Some(at) = at.filter(|&at| latest.is_none_or(|l| at <= l)) {
            let from = at.saturating_sub(PAGE).max(1);
            let to = latest.map_or(at + PAGE - 1, |l| l.min(at + PAGE - 1));
            let placed = |mut value: Value| {
                value["at"] = json!(at);
                value
            };
            if let Some(latest) = latest
                && let Some(entries) = self.have(station, id, from, to).await
            {
                return Some(placed(thread_value(from, entries, thread, title, to >= latest)));
            }
            if let Some(addr) = &addr
                && let Ok(answer) = self.call(addr, "GET", &format!("/threads/{id}/entries?from={from}&to={to}"), Vec::new(), Vec::new()).await
            {
                let entries = entries_in(&answer, from, to);
                let last = answer.get("last").and_then(Value::as_u64).unwrap_or(to);
                if let Some(first) = entries.first().and_then(n_of) {
                    self.keep_entries(station, id, entries.clone());
                    let end = first + entries.len() as u64 > last;
                    return Some(placed(thread_value(first, entries, thread, title, end)));
                }
            }
        }
        // At its end.
        if let Some(h) = &held
            && latest.is_some_and(|l| l == h.last)
            && let Some((held, entries)) = self.kept.open(&log, PAGE).await
        {
            return Some(thread_value(held.first, entries, thread, title, true));
        }
        if let Some(addr) = &addr {
            // What came after what is kept, when that is less than a page; else the latest page.
            let near = held.as_ref().filter(|h| latest.is_none_or(|l| l.saturating_sub(h.last) < PAGE));
            let path = match near {
                Some(h) => format!("/threads/{id}/entries?after={}", h.last),
                None => format!("/threads/{id}/entries?limit={PAGE}"),
            };
            if let Ok(answer) = self.call(addr, "GET", &path, Vec::new(), Vec::new()).await {
                let mut entries = answer.get("entries").and_then(Value::as_array).cloned().unwrap_or_default();
                let last = answer.get("last").and_then(Value::as_u64).unwrap_or(0);
                if let Some(h) = near {
                    entries.retain(|e| n_of(e).is_some_and(|n| n > h.last));
                    if let Some(first) = entries.first().and_then(n_of) {
                        self.kept.write(&log, first, entries.clone(), false, summary.clone()).await;
                    }
                    let (held, kept) = self.kept.open(&log, PAGE).await?;
                    return Some(thread_value(held.first, kept, thread, title, true));
                }
                let first = entries.first().and_then(n_of).unwrap_or(last + 1);
                if !entries.is_empty() {
                    self.host.spawn(self.kept.write(&log, first, entries.clone(), false, summary.clone()));
                }
                return Some(thread_value(first, entries, thread, title, true));
            }
            return None;
        }
        // Offline: its latest page kept, as it was.
        let (held, entries) = self.kept.open(&log, PAGE).await?;
        Some(thread_value(held.first, entries, thread, title, true))
    }

    /// What a thread shows is on the device; so is the page on either side of it, for when the reader goes on.
    fn ahead(&self, station: &str, id: u64) {
        let topic = Topic::Thread { station: station.into(), thread: id };
        let Some(value) = self.sink.get(&topic) else { return };
        if let Some(first) = value.get("first").and_then(Value::as_u64) {
            self.prefetch_before(station, id, first);
        }
        if !at_end(&value) && let Some(last) = value.get("last").and_then(Value::as_u64) {
            self.prefetch_after(station, id, last);
        }
    }

    /// New entries (an event, or `?after=`) onto a live thread topic, and kept. Those it has are skipped; entries
    /// past a gap wait while the gap is read. `told`: as they were said (an event, and the gap it showed), not caught
    /// up on by reading (see `thread_value`).
    fn put_entries(&self, station: &str, id: u64, entries: Vec<Value>, told: bool) {
        let topic = Topic::Thread { station: station.into(), thread: id };
        // A chat not shown, or its window still being read, or short of its end: what is said carries on what is kept,
        // where the window takes it from when it comes down to it (or opens).
        let value = self.sink.get(&topic);
        let Some(last) = value.as_ref().filter(|v| at_end(v)).and_then(|v| v.get("last")?.as_u64()) else {
            if told && let Some(first) = entries.first().and_then(n_of) {
                self.host.spawn(self.kept.extend(&Log::thread(station, id), first, entries));
                self.catch_up_kept(station, id, first);
            }
            return;
        };
        let fresh: Vec<Value> = entries.into_iter().filter(|e| n_of(e).is_some_and(|n| n > last)).collect();
        let Some(first) = fresh.first().and_then(n_of) else { return };
        {
            let workspace = self.of(station);
            let mut stations = workspace.stations.borrow_mut();
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
            if !told {
                value["caught"] = value["last"].clone();
            }
        });
        self.host.spawn(self.kept.write(&Log::thread(station, id), last + 1, run, false, self.summary(station, id)));
        if !past.is_empty() {
            self.put_entries(station, id, past, told);
        }
    }

    /// Reads the entries `from ..= to` an event showed missing, then places them with those that came meanwhile.
    async fn fill_gap(&self, station: &str, id: u64, from: u64, to: u64) {
        let addr = self.addr(station);
        let answer = match addr {
            Some(addr) => self.call(&addr, "GET", &format!("/threads/{id}/entries?from={from}&to={to}"), Vec::new(), Vec::new()).await.ok(),
            None => None,
        };
        let waiting = self.of(station).stations.borrow_mut().get_mut(station).and_then(|s| s.gaps.remove(&id)).unwrap_or_default();
        let mut entries = answer.and_then(|a| a.get("entries").and_then(Value::as_array).cloned()).unwrap_or_default();
        entries.extend(waiting);
        entries.sort_by_key(|e| n_of(e).unwrap_or(0));
        entries.dedup_by_key(|e| n_of(e));
        self.put_entries(station, id, entries, true);
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
            let workspace = self.of(station);
            let mut stations = workspace.stations.borrow_mut();
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
            let workspace = self.of(station);
            let mut stations = workspace.stations.borrow_mut();
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
        // Sent from a window short of its end: the reader goes to the end, where it is.
        if self.sink.get(&topic).is_some_and(|v| !at_end(&v)) {
            let _ = self.latest(station, thread).await;
        }
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
        let Some(before) = self.sink.get(&topic).and_then(|v| v.get("first")?.as_u64()) else { return Ok(false) };
        if before <= 1 {
            return Ok(false);
        }
        let older = match self.have_before(&name, thread, before, PAGE).await {
            Some(older) => older,
            None => {
                let page = self.json(station, "GET", &format!("/threads/{thread}/entries?before={before}&limit={PAGE}"), None).await?;
                let older: Vec<Value> = page.get("entries").and_then(Value::as_array).into_iter().flatten().filter(|e| n_of(e).is_some_and(|n| n < before)).cloned().collect();
                self.keep_entries(&name, thread, older.clone());
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
            // As many go at the other end: the window is short of its end from then on.
            let over = list.len().saturating_sub(WINDOW as usize);
            if over > 0 {
                list.truncate(WINDOW as usize);
                let last = first + WINDOW - 1;
                value["last"] = json!(last);
                value["end"] = json!(false);
            }
            value["first"] = json!(first);
            still = first > 1;
        });
        // A page ahead again, for the next time.
        if still {
            self.prefetch_before(&name, thread, first);
        }
        Ok(still)
    }

    /// The page of entries after those loaded, into the thread's topic: from what is kept, else from the station (and
    /// kept); as many go at its start. Answers whether still newer ones exist (the window is short of the end).
    pub async fn newer(&self, station: &StationAddr, thread: u64) -> Result<bool> {
        let name = station.to_string();
        let topic = Topic::Thread { station: name.clone(), thread };
        let Some(value) = self.sink.get(&topic) else { return Ok(false) };
        if at_end(&value) {
            return Ok(false);
        }
        let Some(after) = value.get("last").and_then(Value::as_u64) else { return Ok(false) };
        let latest = self.latest_known(&name, thread).await;
        let (from, to) = (after + 1, after + PAGE);
        let have = match latest {
            Some(latest) => self.have(&name, thread, from, latest.min(to)).await,
            None => None,
        };
        let (newer, last) = match have {
            Some(newer) => (newer, latest.unwrap_or(to)),
            None => {
                let answer = self.json(station, "GET", &format!("/threads/{thread}/entries?from={from}&to={to}"), None).await?;
                let newer = entries_in(&answer, from, to);
                self.keep_entries(&name, thread, newer.clone());
                (newer, answer.get("last").and_then(Value::as_u64).unwrap_or(to))
            }
        };
        let mut still = false;
        self.sink.update(&topic, &mut |value| {
            // Another page came first: this one does not follow what is loaded any more.
            if value.get("last").and_then(Value::as_u64) != Some(after) || at_end(value) {
                still = !at_end(value);
                return;
            }
            let Some(list) = value.get_mut("entries").and_then(Value::as_array_mut) else { return };
            list.extend(newer.iter().cloned());
            let over = list.len().saturating_sub(WINDOW as usize);
            list.drain(..over);
            let first = value.get("first").and_then(Value::as_u64).unwrap_or(1) + over as u64;
            let now = after + newer.len() as u64;
            value["first"] = json!(first);
            value["last"] = json!(now);
            // Read, not said: it shows at once.
            value["caught"] = json!(now);
            value["end"] = json!(now >= last);
            still = now < last;
        });
        if still {
            self.prefetch_after(&name, thread, after + newer.len() as u64);
        }
        Ok(still)
    }

    /// The thread's latest page in place of its window (the reader goes to its end), read as `open_thread` reads it.
    pub async fn latest(&self, station: &StationAddr, thread: u64) -> Result<()> {
        let name = station.to_string();
        let topic = Topic::Thread { station: name.clone(), thread };
        if self.sink.get(&topic).is_some_and(|v| at_end(&v)) {
            return Ok(());
        }
        let value = self.window(&name, thread, None).await.ok_or_else(|| CoreError::new("offline", "连不上 station"))?;
        if self.is_live(&topic) {
            self.sink.set(&topic, Ok(value));
            self.ahead(&name, thread);
        }
        Ok(())
    }

    /// Where the reader leaves a chat: at entry `at`, short of its end (it opens there next, while nothing is unread),
    /// its top `offset` below the top of the list, or at its end (none). Kept on the device as well.
    pub fn place(&self, station: &str, thread: u64, at: Option<u64>, offset: Option<f64>) {
        let place = at.map(|at| LeftAt { at, offset: offset.filter(|o| o.is_finite()) });
        let was = self.places.borrow_mut().insert((station.to_string(), thread), place);
        if was == Some(place) {
            return;
        }
        // What is written is the latest: a write that finishes after a later one does not put an older place back.
        let (this, station) = (self.rc(), station.to_string());
        self.host.spawn(
            async move {
                let Some(place) = this.places.borrow().get(&(station.clone(), thread)).copied() else { return };
                let key = place_key(&station, thread);
                let _ = match place {
                    Some(p) => this.host.storage_set(&key, serde_json::to_vec(&json!({ "at": p.at, "offset": p.offset })).unwrap_or_default()).await,
                    None => this.host.storage_delete(&key).await,
                };
            }
            .boxed_local(),
        );
    }

    /// Where a chat was left (`place`): as told since this core started, else as kept on the device.
    async fn place_of(&self, station: &str, thread: u64) -> Option<LeftAt> {
        let key = (station.to_string(), thread);
        if let Some(place) = self.places.borrow().get(&key) {
            return *place;
        }
        let kept = self.host.storage_get(&place_key(station, thread)).await.ok().flatten().and_then(|bytes| {
            let v: Value = serde_json::from_slice(&bytes).ok()?;
            Some(LeftAt { at: v.get("at")?.as_u64()?, offset: v.get("offset").and_then(Value::as_f64) })
        });
        // Told meanwhile: that is newer.
        *self.places.borrow_mut().entry(key).or_insert(kept)
    }

    /// Measures the ways to the station now (its card's 重新测量); its `net` topic shows what was found.
    pub async fn measure(&self, station: &StationAddr) -> Result<()> {
        self.wire.measure(station).await
    }

    /// The page of a session's transcript before what its `live` topic has, into it: from what is kept, else from the
    /// station (and kept). Answers whether still older entries exist.
    pub async fn history_older(&self, station: &StationAddr, key: &str) -> Result<bool> {
        let name = station.to_string();
        let topic = Topic::Live { station: name.clone(), key: key.to_string() };
        let log = Log::transcript(&name, key);
        let Some(before) = self.sink.get(&topic).map(|v| first_of(&v)) else { return Ok(false) };
        if before == 0 {
            return Ok(false);
        }
        let older = match self.kept.before(&log, before, TRANSCRIPT_PAGE).await {
            Some(older) => older,
            None => {
                let page = self.json(station, "GET", &format!("/sessions/{}/timeline?before={before}&limit={TRANSCRIPT_PAGE}", encode(key)), None).await?;
                let start = page.get("start").and_then(Value::as_u64).unwrap_or(0);
                let older: Vec<Value> = page.get("entries").and_then(Value::as_array).cloned().unwrap_or_default();
                // None, or not the entries just before (the transcript was written anew meanwhile: the stream says).
                if older.is_empty() || start + older.len() as u64 != before {
                    return Ok(false);
                }
                self.host.spawn(self.kept.write(&log, start, older.clone(), false, None));
                older
            }
        };
        let first = before - older.len() as u64;
        let mut still = false;
        self.sink.update(&topic, &mut |live| {
            let loaded = first_of(live);
            // Another page came first, or the timeline started anew: this one is not next to it any more.
            if loaded != before {
                still = loaded > 0;
                return;
            }
            let Some(timeline) = live.get_mut("timeline").and_then(Value::as_array_mut) else { return };
            timeline.splice(0..0, older.iter().cloned());
            live["first"] = json!(first);
            still = first > 0;
        });
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
            if this.have_before(&name, thread, before, PAGE).await.is_some() {
                return;
            }
            let Ok(page) = this.json(&addr, "GET", &format!("/threads/{thread}/entries?before={before}&limit={PAGE}"), None).await else { return };
            let older: Vec<Value> = page.get("entries").and_then(Value::as_array).into_iter().flatten().filter(|e| n_of(e).is_some_and(|n| n < before)).cloned().collect();
            this.keep_entries(&name, thread, older);
        });
    }

    /// Keeps a page ahead after what a thread shows, as `prefetch_before` does before it.
    fn prefetch_after(&self, station: &str, thread: u64, after: u64) {
        if !self.reachable(station) {
            return;
        }
        let Ok(addr) = StationAddr::parse(station) else { return };
        let (this, name) = (self.rc(), station.to_string());
        self.spawn(async move {
            let latest = this.latest_known(&name, thread).await;
            let to = latest.map_or(after + PAGE, |l| l.min(after + PAGE));
            if to <= after || this.have(&name, thread, after + 1, to).await.is_some() {
                return;
            }
            let Ok(page) = this.json(&addr, "GET", &format!("/threads/{thread}/entries?from={}&to={}", after + 1, after + PAGE), None).await else { return };
            this.keep_entries(&name, thread, entries_in(&page, after + 1, after + PAGE));
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
            let start = message.get("start").and_then(Value::as_u64).unwrap_or(0);
            let entries = message.get("entries").and_then(Value::as_array).map(Vec::as_slice).unwrap_or_default();
            let mut placed = false;
            self.sink.update(&topic, &mut |live| {
                let first = first_of(live);
                let Some(timeline) = live.get_mut("timeline").and_then(Value::as_array_mut) else { return };
                if (first..=first + timeline.len() as u64).contains(&start) {
                    timeline.truncate((start - first) as usize);
                    timeline.extend(entries.iter().cloned());
                } else {
                    // Not next to what is here: past it (only the latest page was sent), or before it (the transcript
                    // written anew): these start the timeline.
                    *timeline = entries.to_vec();
                    live["first"] = json!(start);
                }
                live["usage"] = message.get("usage").cloned().unwrap_or(Value::Null);
                placed = true;
            });
            if !placed {
                return false;
            }
            self.host.spawn(self.kept.write(&Log::transcript(station, key), start, entries.to_vec(), true, None));
            entries_came = !entries.is_empty();
        }
        let view = {
            let workspace = self.of(station);
            let mut stations = workspace.stations.borrow_mut();
            let Some(view) = stations.get_mut(station).and_then(|s| s.lives.get_mut(key)) else { return true };
            match kind {
                // Ended steps stay until the entries that record them arrive.
                "timeline" if entries_came => view.steps.retain(|s| s.get("ended") != Some(&Value::Bool(true))),
                "steps" => {
                    view.steps = message.get("steps").and_then(Value::as_array).cloned().unwrap_or_default();
                    view.phase = message.get("phase").filter(|p| !p.is_null()).map(|p| {
                        let elapsed = p.get("elapsedMs").and_then(Value::as_f64).unwrap_or(0.0);
                        json!({ "phase": p.get("phase").cloned().unwrap_or(Value::Null), "since": (now - elapsed).round() as i64 })
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
        "phase" => view.phase = Some(json!({ "phase": event.get("phase").cloned().unwrap_or(Value::Null), "since": now.round() as i64 })),
        "start" => {
            // Started again (with its input, which Claude Code streams after the start): it keeps when it started.
            let started = view.steps.iter().find(|s| s.get("id") == Some(&id)).and_then(|s| s.get("startedAt")).and_then(Value::as_i64);
            view.steps.retain(|s| s.get("id") != Some(&id));
            // What it is; what it writes comes with its transcript entry (the station tells no deltas).
            let mut step = json!({
                "id": id,
                "step": event.get("step").cloned().unwrap_or(Value::Null),
                "input": event.get("input").and_then(Value::as_str).unwrap_or(""),
                "startedAt": started.unwrap_or(now.round() as i64),
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
            let workspace = self.of(&station);
            let mut stations = workspace.stations.borrow_mut();
            let state = stations.entry(station.clone()).or_insert_with(|| StationState::new(addr.clone()));
            state.topics.insert(topic.clone())
        };
        if !fresh {
            return;
        }
        match topic {
            Topic::Link { .. } => {
                // The state as it is when this runs: the events stream may have moved on. Not found out yet this time:
                // how it was last (kept), for the views to show meanwhile.
                let (this, station) = (self.rc(), station.clone());
                self.spawn(async move {
                    let last = this.host.storage_get(&format!("{LINK_KEY}/{station}")).await.ok().flatten().and_then(|b| String::from_utf8(b).ok());
                    let link = this.of(&station).stations.borrow().get(&station).map(|s| s.link.clone());
                    let Some(mut link) = link else { return };
                    if link.get("state").and_then(Value::as_str) == Some("connecting") && let Some(last) = last {
                        link["last"] = json!(last);
                    }
                    this.set_link(&station, link);
                });
            }
            Topic::Overview { .. } | Topic::Sessions { .. } | Topic::Threads { .. } | Topic::ChatRows { .. } | Topic::ArchivedRows { .. } | Topic::Session { .. } | Topic::SlackApp { .. } | Topic::Jobs { .. } | Topic::StationUsage { .. } | Topic::Footprint { .. } => {
                self.refetch(topic)
            }
            Topic::Thread { thread, .. } => {
                let (this, station, thread) = (self.rc(), station.clone(), *thread);
                self.spawn(async move { this.open_thread(&station, thread).await });
            }
            // Samples come on the events stream, which asks for them now.
            Topic::Host { .. } => {}
            Topic::Net { .. } => {
                let task = self.spawn(self.rc().sample_net(topic.clone(), addr.clone()));
                if let Some(s) = self.of(&station).stations.borrow_mut().get_mut(&station) {
                    s.tasks.insert(topic.clone(), task);
                }
                return;
            }
            Topic::JobLog { .. } => {
                let task = self.spawn(self.rc().follow_log(topic.clone()));
                if let Some(s) = self.of(&station).stations.borrow_mut().get_mut(&station) {
                    s.tasks.insert(topic.clone(), task);
                }
            }
            // What was kept of its transcript first; then the station's stream asks for it from there (see open_events).
            Topic::Live { key, .. } => {
                if let Some(s) = self.of(&station).stations.borrow_mut().get_mut(&station) {
                    s.lives.insert(key.clone(), LiveView::default());
                }
                let (this, station, key, topic) = (self.rc(), station.clone(), key.clone(), topic.clone());
                self.spawn(async move {
                    let mut start = live_start();
                    // Its latest page; `history.older` brings the rest.
                    if let Some((held, entries)) = this.kept.open(&Log::transcript(&station, &key), TRANSCRIPT_PAGE).await {
                        start["first"] = json!(held.first);
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
            let workspace = self.of(station);
            let mut stations = workspace.stations.borrow_mut();
            let Some(state) = stations.get_mut(station) else { return };
            state.topics.remove(topic);
            if let Topic::Thread { thread, .. } = topic {
                self.loose.borrow_mut().remove(&(station.to_string(), *thread));
            }
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
    use crate::testing::{FakeHost, run};
    use futures::channel::mpsc;
    use std::time::Duration;

    // ── fakes ──

    fn wants_stream(head: &RequestHead) -> bool {
        head.headers.iter().any(|(k, v)| k.eq_ignore_ascii_case("accept") && v.contains(EVENT_STREAM))
    }

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
        /// Stream requests are never answered.
        stream_hangs: std::cell::Cell<bool>,
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
            if wants_stream(&head) && self.stream_hangs.get() {
                return futures::future::pending().boxed_local();
            }
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
        /// A socket nothing answers (an older station waiting for a request's body).
        fn socket(&self, _station: &StationAddr, _head: RequestHead) -> LocalBoxFuture<'static, Result<WireSocket>> {
            futures::future::pending().boxed_local()
        }
    }

    fn setup() -> (Rc<FakeHost>, Rc<FakeSink>, Rc<FakeWire>, Rc<Stations>) {
        let host = FakeHost::new();
        let sink = Rc::new(FakeSink::default());
        let wire = FakeWire::new();
        let stations = Stations::new(host.clone(), sink.clone(), wire.clone(), Tracer::new(host.clone(), 1.0), Kept::new(host.clone()), Workspaces::new(host.clone()));
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
        assert_eq!(StationAddr::parse("ws/st").unwrap(), StationAddr { workspace: "ws".into(), station: "st".into() });
        assert_eq!(StationAddr::parse("ws/st").unwrap().to_string(), "ws/st");
        for bad in ["", "ws", "/st", "ws/", "a/b/c", "Local"] {
            assert_eq!(StationAddr::parse(bad).unwrap_err().code, "invalid_params", "{bad}");
        }
        // A station's own page, still in kept links and prefs: gone, said so.
        assert_eq!(StationAddr::parse("local").unwrap_err().code, "gone");
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
            let e = stations.file(&remote(), "k", "x", false, |_, _| {}).await.unwrap_err();
            assert_eq!((e.message.as_str(), e.status), ("读不到文件", Some(404)));
        });
    }

    #[test]
    fn tells_how_far_a_file_has_come() {
        run(async {
            let (_host, _sink, wire, stations) = setup();
            let big = "x".repeat(300 * 1024);
            wire.answer("GET /admin/api/sessions/k/files?name=big", 200, json!(big));
            let heard = RefCell::new(Vec::new());
            let (_, bytes) = stations.file(&remote(), "k", "big", false, |loaded, total| heard.borrow_mut().push((loaded, total))).await.unwrap();
            // At the start, then once past 256 KB (the size not given, it comes in one chunk here).
            assert_eq!(heard.into_inner(), vec![(0, None), (bytes.len() as u64, None)]);
        });
    }

    #[test]
    fn a_station_not_reached_is_down_and_asked_for_nothing_until_it_is() {
        run(async {
            let (host, sink, wire, stations) = setup();
            wire.answer("GET /admin/api/overview", 200, json!({"connects": [], "profiles": []}));
            // Never reached: down (whatever else says otherwise), and kept so for the next start.
            *wire.stream_status.borrow_mut() = None;
            stations.start(&link());
            host.settle().await;
            assert_eq!(sink.get(&link()).unwrap()["state"], "offline");
            assert_eq!(host.stored(&format!("{LINK_KEY}/{ST}")).as_deref(), Some(&b"offline"[..]));
            stations.start(&overview());
            host.settle().await;
            assert_eq!(wire.count("GET", "/admin/api/overview"), 0, "down: nothing asked");
            // Reached: what it wants is read.
            *wire.stream_status.borrow_mut() = Some(200);
            wait(RECONNECT_MS * 2 + 50).await;
            assert_eq!(sink.get(&link()).unwrap()["state"], "online");
            assert_eq!(wire.count("GET", "/admin/api/overview"), 1, "back: what it wants is read");
            assert_eq!(host.stored(&format!("{LINK_KEY}/{ST}")).as_deref(), Some(&b"online"[..]));
        });
    }

    #[test]
    fn a_station_down_shows_it_is_tried_again_as_soon_as_a_person_asks() {
        run(async {
            let fake = FakeHost::new();
            let wakes = Rc::new(crate::wake::Wakes::default());
            let host: Rc<dyn Host> = crate::wake::WakingHost::new(fake.clone(), wakes.clone());
            let sink = Rc::new(FakeSink::default());
            let wire = FakeWire::new();
            let stations = Stations::new(host.clone(), sink.clone(), wire.clone(), Tracer::new(host.clone(), 1.0), Kept::new(host.clone()), Workspaces::new(host.clone()));
            *wire.stream_status.borrow_mut() = None;
            stations.start(&link());
            fake.settle().await;
            assert_eq!(sink.get(&link()).unwrap()["state"], "offline");
            // 重试 (client.wake, network), and the try it starts takes a while: not "down" meanwhile.
            wire.stream_hangs.set(true);
            wakes.wake(crate::wake::Wake { at: host.now_ms(), away: 0.0, network: true, retry: false });
            fake.settle().await;
            assert_eq!(sink.get(&link()).unwrap()["state"], "reconnecting");
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
            // Put on another update channel: its versions (the overview's) read again.
            wire.answer("POST /admin/api/updates/channel", 200, json!([]));
            stations.request(&remote(), "POST", "/updates/channel", Some(json!({"channel": "beta"}))).await.unwrap();
            assert_eq!(wire.count("GET", "/admin/api/overview"), o + 2);
            // Another chat on a session answers its thread, which goes into the lists without a request.
            let reads = wire.calls.borrow().len();
            wire.answer("POST /admin/api/threads", 200, thread_view(9, &["k 1"], 0, 0, 0));
            stations.request(&remote(), "POST", "/threads", Some(json!({"session": "k 1"}))).await.unwrap();
            assert_eq!(sink.get(&session("k 1")).unwrap()["threads"][0]["id"], 9);
            assert_eq!(sink.get(&threads()).unwrap()[0]["id"], 9);
            assert_eq!(wire.calls.borrow().len(), reads + 1);
            // A read changes nothing.
            stations.request(&remote(), "GET", "/slack/config-token", None).await.unwrap();
            assert_eq!(wire.count("GET", "/admin/api/overview"), o + 2);
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
    fn jobs_are_put_in_place_from_their_events_and_from_stopping_them() {
        run(async {
            let (host, sink, wire, stations) = setup();
            let job = |id: &str, state: &str| json!({"id": id, "session": "a", "name": id, "state": state, "port": 4817, "startedAt": 1});
            let open = Topic::Jobs { station: ST.into() };
            wire.answer("GET /admin/api/sessions/a", 200, json!({"session": summary("a", 0), "threads": [], "turns": [], "jobs": [job("j1", "running")]}));
            wire.answer("GET /admin/api/jobs", 200, json!([{"id": "j1", "session": "a", "name": "j1", "state": "running", "port": 4817, "startedAt": 1, "chat": {"id": "7", "title": "t", "archived": false}}]));
            stations.start(&session("a"));
            stations.start(&open);
            host.settle().await;
            let reads = wire.calls.borrow().len();
            // Stopped from a page: the answer is the job as it is now, in its chat and gone from the open ones, with
            // nothing read again.
            wire.answer("POST /admin/api/jobs/j1/stop", 200, job("j1", "stopped"));
            stations.request(&remote(), "POST", "/jobs/j1/stop", None).await.unwrap();
            assert_eq!(sink.get(&session("a")).unwrap()["jobs"][0]["state"], "stopped");
            assert_eq!(sink.get(&open).unwrap(), json!([]));
            assert_eq!(wire.calls.borrow().len(), reads + 1);
            // Started again elsewhere (an agent, another device): its event puts it back; which chat it is in, the list
            // read again says.
            wire.event("job", job("j1", "running"));
            host.settle().await;
            assert_eq!(sink.get(&session("a")).unwrap()["jobs"][0]["state"], "running");
            assert_eq!(sink.get(&open).unwrap()[0]["chat"]["id"], "7");
            assert_eq!(wire.count("GET", "/admin/api/jobs"), 2);
            // A new one goes in front of its session's; one listed keeps its chat as it changes.
            wire.event("job", job("j2", "failed"));
            let mut restarting = job("j1", "exited");
            restarting["restarts"] = json!(1);
            wire.event("job", restarting);
            host.settle().await;
            let jobs = sink.get(&session("a")).unwrap()["jobs"].clone();
            assert_eq!((jobs[0]["id"].as_str(), jobs[1]["state"].as_str()), (Some("j2"), Some("exited")));
            assert_eq!(sink.get(&open).unwrap()[0]["restarts"], 1);
            assert_eq!(sink.get(&open).unwrap()[0]["chat"]["id"], "7");
            assert_eq!(wire.count("GET", "/admin/api/jobs"), 2);
            // One that was over, cleared (here or on another device): out of its chat's.
            wire.event("job-removed", json!({"id": "j2", "session": "a"}));
            host.settle().await;
            let ids: Vec<Value> = sink.get(&session("a")).unwrap()["jobs"].as_array().unwrap().iter().map(|j| j["id"].clone()).collect();
            assert_eq!(ids, [json!("j1")]);
        });
    }

    #[test]
    fn a_jobs_log_is_read_once_and_then_kept_current_by_the_stations_events() {
        run(async {
            let (host, sink, wire, stations) = setup();
            let log = |lines| Topic::JobLog { station: ST.into(), job: "j1".into(), lines };
            wire.answer("GET /admin/api/jobs/j1/log?lines=400", 200, json!({"text": "a\nb", "outputAt": 5, "follows": true}));
            wire.answer("GET /admin/api/jobs/j1/log?lines=1", 200, json!({"text": "b", "outputAt": 5, "follows": true}));
            stations.start(&log(400));
            host.settle().await;
            assert_eq!(sink.get(&log(400)).unwrap(), json!({"text": "a\nb", "outputAt": 5}));
            assert_eq!(wire.open(), vec!["/admin/api/events?job=j1&lines=400"]);
            // As it grows the station says so, each topic its own lines; nothing is read again, and nothing waits to.
            stations.start(&log(1));
            host.settle().await;
            assert_eq!(wire.open(), vec!["/admin/api/events?job=j1&lines=1&job=j1&lines=400"]);
            host.sleeps.borrow_mut().clear();
            wire.event("job-log", json!({"id": "j1", "lines": 400, "text": "a\nb\nc", "outputAt": 9}));
            wire.event("job-log", json!({"id": "j1", "lines": 1, "text": "c", "outputAt": 9}));
            host.settle().await;
            assert_eq!(sink.get(&log(400)).unwrap(), json!({"text": "a\nb\nc", "outputAt": 9}));
            assert_eq!(sink.get(&log(1)).unwrap(), json!({"text": "c", "outputAt": 9}));
            wait(LOG_READ_MS + 200).await;
            assert_eq!((wire.count("GET", "/admin/api/jobs/j1/log?lines=400"), wire.count("GET", "/admin/api/jobs/j1/log?lines=1")), (1, 1));
            assert!(!host.sleeps.borrow().contains(&LOG_READ_MS), "{:?}", host.sleeps.borrow());
            // Given up: the stream no longer asks for it.
            stations.stop(&log(400));
            host.settle().await;
            assert_eq!(wire.open(), vec!["/admin/api/events?job=j1&lines=1"]);
        });
    }

    #[test]
    fn a_jobs_log_on_a_station_that_does_not_follow_it_is_read_again_less_often_while_it_stays_the_same() {
        run(async {
            let (host, sink, wire, stations) = setup();
            host.speed_up(100);
            let topic = Topic::JobLog { station: ST.into(), job: "j1".into(), lines: 1 };
            let path = "/admin/api/jobs/j1/log?lines=1";
            // An older station: no `follows`, and `job=` on its stream passed over.
            wire.answer(&format!("GET {path}"), 200, json!({"text": "a", "outputAt": 5}));
            stations.start(&topic);
            host.settle().await;
            assert_eq!(sink.get(&topic).unwrap(), json!({"text": "a", "outputAt": 5}));
            wire.answer(&format!("GET {path}"), 200, json!({"text": "b", "outputAt": 6}));
            wait(80).await;
            assert_eq!(sink.get(&topic).unwrap(), json!({"text": "b", "outputAt": 6}));
            wait(200).await;
            let waits: Vec<u64> = host.sleeps.borrow().iter().copied().filter(|ms| [LOG_READ_MS, LOG_READ_MS * 2, LOG_READ_MS * 4].contains(ms)).collect();
            assert!(waits.contains(&(LOG_READ_MS * 2)) && waits.contains(&(LOG_READ_MS * 4)), "{waits:?}");
            // Given up: no more reading.
            stations.stop(&topic);
            host.settle().await;
            let reads = wire.count("GET", path);
            wait(200).await;
            assert_eq!(wire.count("GET", path), reads);
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
            // (With no list of threads to say where reading stopped, the chat asks for its own summary.)
            assert_eq!(paths.len(), 5, "{paths:?}");
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
            assert_eq!(wire.open(), vec!["/admin/api/events?host=1&live=a&from=0&last=200"]);
            let requests = wire.calls.borrow().len();
            // (With no list of threads to say where reading stopped, the chat asks for its own summary.)
            assert_eq!(requests, 8, "{:?}", wire.paths());
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
            assert_eq!(sink.get(&thread(7)).unwrap()["caught"], 12, "what was read, not what was said since");
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
            assert_eq!(sink.get(&thread(7)).unwrap()["caught"], 3, "a gap an event showed is part of what was said");
            assert_eq!(wire.count("GET", "/admin/api/threads/7/entries?from=4&to=5"), 1);
            assert_eq!(wire.paths().iter().filter(|p| p.contains("/entries")).count(), 2, "{:?}", wire.paths());
        });
    }

    /// A second core on the same device (the page reloaded): the same storage, a new `Stations`.
    fn reopened(host: &Rc<FakeHost>) -> (Rc<FakeSink>, Rc<FakeWire>, Rc<Stations>) {
        let sink = Rc::new(FakeSink::default());
        let wire = FakeWire::new();
        let stations = Stations::new(host.clone(), sink.clone(), wire.clone(), Tracer::new(host.clone(), 1.0), Kept::new(host.clone()), Workspaces::new(host.clone()));
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
            assert_eq!((shown["first"].clone(), shown["last"].clone(), shown["thread"]["id"].clone()), (json!(253), json!(302), json!(7)));
            // All of it caught up on (kept, then read): none of it was said while the chat was open.
            assert_eq!(shown["caught"], 302);
            assert_eq!(wire.paths().iter().filter(|p| p.contains("/entries")).cloned().collect::<Vec<_>>(), vec!["GET /admin/api/threads/7/entries?after=301"]);
            // Scrolling up reads what is kept first; past it, the station (and what it answers is kept too).
            assert!(stations.older(&remote(), 7).await.unwrap());
            assert_eq!(sink.get(&thread(7)).unwrap()["first"], 251);
            // (Its summary, with no list read to say where reading stopped; the entries after what is kept; the stream.)
            assert_eq!(wire.calls.borrow().len(), 3, "{:?}", wire.paths());
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

    fn window_of(sink: &FakeSink, id: u64) -> (u64, u64, bool) {
        let v = sink.get(&thread(id)).unwrap();
        (v["first"].as_u64().unwrap(), v["last"].as_u64().unwrap(), at_end(&v))
    }

    #[test]
    fn a_chat_with_something_unread_opens_whole_at_it_and_pages_either_way() {
        run(async {
            let (host, sink, wire, stations) = setup();
            // 300 entries, read up to 200: the window is the page before the first unread and the page from it.
            wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 300, 200, 100)]));
            stations.start(&threads());
            host.settle().await;
            wire.answer("GET /admin/api/threads/7/entries?from=151&to=250", 200, json!({"last": 300, "entries": entries(151, 250)}));
            wire.answer("GET /admin/api/threads/7/entries?before=151&limit=50", 200, json!({"last": 300, "entries": entries(101, 150)}));
            wire.answer("GET /admin/api/threads/7/entries?from=251&to=300", 200, json!({"last": 300, "entries": entries(251, 300)}));
            stations.start(&thread(7));
            host.settle().await;
            assert_eq!(window_of(&sink, 7), (151, 250, false));
            assert_eq!(wire.paths().iter().filter(|p| p.contains("/entries")).count(), 3, "the window, then a page ahead either way: {:?}", wire.paths());
            // Said meanwhile, past the window: it waits (kept for when the window comes down to it).
            wire.event("thread", json!({"id": 7, "entries": [entry(301, "m301")]}));
            host.settle().await;
            assert_eq!(window_of(&sink, 7), (151, 250, false));
            // Down: the page after, from what was brought ahead, read (not said); then what waited, and the window is
            // at its end, as many gone at its start.
            assert!(stations.newer(&remote(), 7).await.unwrap());
            assert_eq!(wire.count("GET", "/admin/api/threads/7/entries?from=251&to=300"), 1, "not asked again");
            assert_eq!(window_of(&sink, 7), (151, 300, false));
            host.settle().await;
            assert!(!stations.newer(&remote(), 7).await.unwrap());
            assert_eq!(window_of(&sink, 7), (152, 301, true));
            assert_eq!(sink.get(&thread(7)).unwrap()["caught"], 301);
            // Up: the page before comes in, and as many go at the other end.
            assert!(stations.older(&remote(), 7).await.unwrap());
            assert_eq!(window_of(&sink, 7), (102, 251, false));
            assert_eq!(numbers(&sink, 7).len() as u64, WINDOW);
            // To the end: its latest page in place of the window, from the device.
            let asked = wire.paths().len();
            stations.latest(&remote(), 7).await.unwrap();
            assert_eq!(window_of(&sink, 7), (252, 301, true));
            assert_eq!(wire.paths().len(), asked, "{:?}", wire.paths());
            // At its end, what is said joins it.
            wire.event("thread", json!({"id": 7, "entries": [entry(302, "m302")]}));
            host.settle().await;
            assert_eq!(window_of(&sink, 7).1, 302);
        });
    }

    #[test]
    fn a_chat_opens_from_the_device_when_what_is_kept_is_current_and_else_waits_to_be_whole() {
        run(async {
            let (host, _sink, wire, stations) = setup();
            wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 300, 300, 0)]));
            wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 300, "entries": entries(251, 300)}));
            stations.start(&threads());
            stations.start(&thread(7));
            host.settle().await;
            // Opened again, nothing new: from the device alone.
            let (sink, wire, stations) = reopened(&host);
            wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 300, 300, 0)]));
            stations.start(&threads());
            host.settle().await;
            stations.start(&thread(7));
            host.settle().await;
            assert_eq!(window_of(&sink, 7), (251, 300, true));
            assert!(wire.paths().iter().all(|p| !p.contains("/threads/7/entries?after") && !p.contains("entries?limit=50")), "{:?}", wire.paths());
            // Opened again with 20 new (read): what came after is read first; the first value is whole.
            let (sink, wire, stations) = reopened(&host);
            wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 320, 320, 0)]));
            wire.answer("GET /admin/api/threads/7/entries?after=300", 200, json!({"last": 320, "entries": entries(301, 320)}));
            stations.start(&threads());
            host.settle().await;
            stations.start(&thread(7));
            host.settle().await;
            assert_eq!(window_of(&sink, 7), (271, 320, true));
            assert_eq!(sink.get(&thread(7)).unwrap()["caught"], 320, "read, not said");
            // Left short of its end and opened again: there.
            stations.place(ST, 7, Some(120), None);
            stations.stop(&thread(7));
            sink.values.borrow_mut().remove(&thread(7));
            wire.answer("GET /admin/api/threads/7/entries?from=70&to=169", 200, json!({"last": 320, "entries": entries(70, 169)}));
            stations.start(&thread(7));
            host.settle().await;
            assert_eq!(window_of(&sink, 7), (70, 169, false));
        });
    }

    #[test]
    fn where_a_chat_was_left_is_kept_on_the_device_for_a_core_started_anew() {
        run(async {
            let (host, _sink, wire, stations) = setup();
            wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 300, 300, 0)]));
            wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 300, "entries": entries(251, 300)}));
            stations.start(&threads());
            stations.start(&thread(7));
            host.settle().await;
            // Left 180 down: the core goes (the page reloaded) before the chat is opened again.
            stations.place(ST, 7, Some(180), Some(-36.5));
            host.settle().await;
            let (sink, wire, stations) = reopened(&host);
            wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 300, 300, 0)]));
            wire.answer("GET /admin/api/threads/7/entries?from=130&to=229", 200, json!({"last": 300, "entries": entries(130, 229)}));
            stations.start(&threads());
            host.settle().await;
            stations.start(&thread(7));
            host.settle().await;
            assert_eq!(window_of(&sink, 7), (130, 229, false));
            let value = sink.get(&thread(7)).unwrap();
            assert_eq!((value["at"].clone(), value["atOffset"].clone()), (json!(180), json!(-36.5)));
            // Left at its end: the next core opens it there.
            stations.place(ST, 7, None, None);
            host.settle().await;
            let (sink, wire, stations) = reopened(&host);
            wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 300, 300, 0)]));
            stations.start(&threads());
            host.settle().await;
            stations.start(&thread(7));
            host.settle().await;
            assert_eq!(window_of(&sink, 7).2, true);
            assert!(sink.get(&thread(7)).unwrap().get("at").is_none());
        });
    }

    #[test]
    fn a_chat_not_open_keeps_up_on_the_device() {
        run(async {
            let (host, sink, wire, stations) = setup();
            wire.answer("GET /admin/api/threads/7/entries?limit=50", 200, json!({"last": 300, "entries": entries(251, 300)}));
            wire.answer("GET /admin/api/threads", 200, json!([thread_view(7, &["k"], 300, 300, 0)]));
            stations.start(&thread(7));
            stations.start(&threads());
            host.settle().await;
            // Closed (let go by the store, its value with it); what is said meanwhile carries on what is kept. Past a
            // gap, what came after what is kept is read then, so it stays whole.
            stations.stop(&thread(7));
            sink.values.borrow_mut().remove(&thread(7));
            wire.answer("GET /admin/api/threads/7/entries?after=301", 200, json!({"last": 303, "entries": [entry(302, "m302"), entry(303, "m303")]}));
            wire.event("thread", json!({"id": 7, "entries": [entry(301, "m301")]}));
            wire.event("thread", json!({"id": 7, "entries": [entry(303, "m303")]}));
            host.settle().await;
            assert_eq!(wire.count("GET", "/admin/api/threads/7/entries?after=301"), 1, "asked only for what came after what was kept");
            // Opened: whole from the device, nothing asked.
            let asked = wire.paths().len();
            stations.start(&thread(7));
            host.settle().await;
            assert_eq!(texts(&sink, 7).last().unwrap(), "m303");
            assert_eq!(wire.paths().iter().skip(asked).filter(|p| p.contains("entries?after") || p.contains("entries?limit")).count(), 0, "{:?}", wire.paths());
            assert_eq!(sink.get(&thread(7)).unwrap()["caught"], 303);
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
            assert_eq!(sink.get(&thread(7)).unwrap()["caught"], 4);
            // Nothing older: no request.
            assert!(!stations.older(&remote(), 7).await.unwrap());
            assert_eq!(wire.paths().iter().filter(|p| p.contains("before=")).count(), 1);
            // The stream was down: what came after the last entry is read, and the pages stay.
            wire.answer("GET /admin/api/threads/7/entries?after=4", 200, json!({"last": 5, "entries": [entry(5, "e")]}));
            wire.end("/admin/api/events");
            host.settle().await;
            assert_eq!(sink.get(&link()).unwrap()["state"], "reconnecting");
            wait(RECONNECT_MS + 50).await;
            assert_eq!(sink.get(&link()).unwrap()["state"], "online");
            assert_eq!(texts(&sink, 7), vec!["a", "b", "c", "d", "e"]);
            assert_eq!(sink.get(&thread(7)).unwrap()["caught"], 5, "what was missed while the stream was down is caught up on");
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
            // It was up and dropped: coming back, for a few tries.
            assert_eq!(sink.get(&link()).unwrap()["state"], "reconnecting");
            wait(RECONNECT_MS + 50).await;
            assert_eq!(sink.get(&link()).unwrap(), json!({"state": "reconnecting", "message": "连不上"}));
            *wire.stream_status.borrow_mut() = Some(403);
            wait(RECONNECT_MS + 50).await;
            assert_eq!(sink.get(&link()).unwrap(), json!({"state": "error", "message": "没有权限"}));
            let s = wire.count("GET", "/admin/api/sessions");
            *wire.stream_status.borrow_mut() = Some(200);
            // Tries come less often as they miss: twice the wait by now.
            wait(RECONNECT_MS * 2 + 50).await;
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
            assert!(wire.paths().contains(&"GET /admin/api/events?live=k&from=0&last=200".to_string()));
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
            assert!(wire.paths().contains(&"GET /admin/api/events?live=k&from=4&last=200".to_string()), "{:?}", wire.paths());
            // Reloaded: the kept transcript at once, and only what came after it is asked for.
            host.settle().await;
            let (reloaded, again, other) = reopened(&host);
            other.start(&live("k"));
            host.settle().await;
            assert_eq!(live_of(&reloaded, "k")["timeline"], json!(["a", "B", "c", "d"]));
            assert!(again.paths().contains(&"GET /admin/api/events?live=k&from=4&last=200".to_string()), "{:?}", again.paths());
            // Written anew and shorter: what is kept is cut there too.
            again.event("live", with_key("k", json!({"type": "timeline", "start": 1, "entries": [], "usage": {}})));
            host.settle().await;
            assert_eq!(live_of(&reloaded, "k")["timeline"], json!(["a"]));
            let (reloaded, _, other) = reopened(&host);
            other.start(&live("k"));
            host.settle().await;
            assert_eq!(live_of(&reloaded, "k")["timeline"], json!(["a"]));
            // Past what is here (the station sent only its latest page): the timeline starts there, and so does what
            // is kept.
            wire.event("live", with_key("k", json!({"type": "timeline", "start": 9, "entries": ["z"], "usage": {}})));
            host.settle().await;
            assert_eq!((live_of(&sink, "k")["first"].clone(), live_of(&sink, "k")["timeline"].clone()), (json!(9), json!(["z"])));
            let (reloaded, again, other) = reopened(&host);
            other.start(&live("k"));
            host.settle().await;
            assert_eq!((live_of(&reloaded, "k")["first"].clone(), live_of(&reloaded, "k")["timeline"].clone()), (json!(9), json!(["z"])));
            assert!(again.paths().contains(&"GET /admin/api/events?live=k&from=10&last=200".to_string()), "{:?}", again.paths());
        });
    }

    #[test]
    fn a_transcript_shows_its_latest_page_and_the_ones_before_as_asked() {
        run(async {
            let (host, sink, wire, stations) = setup();
            let entries = |from: u64, to: u64| (from..=to).map(|i| json!(format!("e{i}"))).collect::<Vec<_>>();
            stations.start(&live("k"));
            host.settle().await;
            wire.event("live", with_key("k", json!({"type": "timeline", "start": 300, "entries": entries(300, 499), "usage": {}})));
            host.settle().await;
            assert_eq!(live_of(&sink, "k")["first"], 300);
            // From the station, and kept.
            wire.answer("GET /admin/api/sessions/k/timeline?before=300&limit=200", 200, json!({"start": 100, "entries": entries(100, 299)}));
            assert!(stations.history_older(&remote(), "k").await.unwrap());
            let v = live_of(&sink, "k");
            assert_eq!((v["first"].clone(), v["timeline"].as_array().unwrap().len(), v["timeline"][0].clone()), (json!(100), 400, json!("e100")));
            wire.answer("GET /admin/api/sessions/k/timeline?before=100&limit=200", 200, json!({"start": 0, "entries": entries(0, 99)}));
            assert!(!stations.history_older(&remote(), "k").await.unwrap());
            assert_eq!(live_of(&sink, "k")["first"], 0);
            assert!(!stations.history_older(&remote(), "k").await.unwrap());
            host.settle().await;
            // Opened again: the latest page from the device, the one before it from the device too.
            let (reloaded, again, other) = reopened(&host);
            other.start(&live("k"));
            host.settle().await;
            assert_eq!((live_of(&reloaded, "k")["first"].clone(), live_of(&reloaded, "k")["timeline"][0].clone()), (json!(300), json!("e300")));
            assert!(again.paths().contains(&"GET /admin/api/events?live=k&from=500&last=200".to_string()), "{:?}", again.paths());
            assert!(other.history_older(&remote(), "k").await.unwrap());
            assert_eq!(live_of(&reloaded, "k")["first"], 100);
            assert!(!again.paths().iter().any(|p| p.contains("/timeline")), "{:?}", again.paths());
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
            assert_eq!(wire.count("GET", "/admin/api/events?live=k&from=0&last=200"), 1);
            // The keepalive keeps it open.
            wait(STREAM_IDLE_MS / 2).await;
            wire.push("/admin/api/events", ": ping\n\n");
            wait(STREAM_IDLE_MS / 2 + 5_000).await;
            assert_eq!(wire.count("GET", "/admin/api/events?live=k&from=0&last=200"), 1);
            // Nothing at all for longer: the link is taken for gone, and it is asked for again.
            wait(STREAM_IDLE_MS + RECONNECT_MS + 5_000).await;
            assert_eq!(wire.count("GET", "/admin/api/events?live=k&from=0&last=200"), 2);
        });
    }

    #[test]
    fn a_preview_socket_nothing_answers_fails_in_time() {
        run(async {
            let (host, _sink, _wire, stations) = setup();
            host.speed_up(100);
            let opened = stations.preview_socket(&remote(), 5180, "/", vec![]).await;
            assert_eq!(opened.err().map(|e| e.code).as_deref(), Some("timeout"));
            assert!(host.sleeps.borrow().contains(&SOCKET_OPEN_MS));
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
            assert!(v["phase"]["since"].is_i64(), "a whole number of ms: clients read it as one");
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
    fn a_bad_station_and_a_stations_no_are_errors_a_passing_failure_keeps_loading() {
        run(async {
            let (host, sink, wire, stations) = setup();
            let bad = Topic::Overview { station: "nope".into() };
            stations.start(&bad);
            wire.answer("GET /admin/api/sessions", 404, json!({"error": "没有"}));
            stations.start(&sessions());
            host.settle().await;
            assert_eq!(sink.values.borrow()[&bad].as_ref().unwrap_err().code, "invalid_params");
            assert_eq!(sink.values.borrow()[&sessions()].as_ref().unwrap_err().message, "没有");
            // A failure that passes (a 502 while the link is down): no error, still loading, read again shortly.
            wire.answer("GET /admin/api/threads", 502, json!({"error": "坏了"}));
            stations.start(&threads());
            host.settle().await;
            assert!(!sink.values.borrow().contains_key(&threads()), "loading, not an error");
            wire.answer("GET /admin/api/threads", 200, json!([]));
            wait(RETRY_MS + 50).await;
            host.settle().await;
            assert_eq!(sink.values.borrow()[&threads()].as_ref().unwrap(), &json!([]));
        });
    }

    #[test]
    fn socket_frames_are_taken_whole_however_they_come_apart() {
        let frames = [SocketFrame::Text("héllo".into()), SocketFrame::Binary(vec![0, 255]), SocketFrame::Close(4001, "done".into())];
        let bytes: Vec<u8> = frames.iter().flat_map(SocketFrame::encode).collect();
        assert_eq!(&bytes[..5], &[1, 0, 0, 0, 6], "kind, then the length big-endian");
        // One byte at a time: each frame once it is all there, nothing before.
        let (mut buf, mut got) = (Vec::new(), Vec::new());
        for b in &bytes {
            buf.push(*b);
            got.extend(SocketFrame::take(&mut buf));
        }
        assert_eq!(got, frames);
        assert!(buf.is_empty());
        // All at once, with the start of another after them.
        let mut buf = [&bytes[..], &[2, 0, 0]].concat();
        assert_eq!(SocketFrame::take(&mut buf), frames);
        assert_eq!(buf, vec![2, 0, 0]);
        // A close with no code says 1005, as a WebSocket does.
        assert_eq!(SocketFrame::take(&mut vec![8, 0, 0, 0, 0]), vec![SocketFrame::Close(1005, String::new())]);
    }
}
