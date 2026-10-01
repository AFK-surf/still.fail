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

mod transport;
mod events;
mod threads;

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
use crate::ops::{Effect, Request};
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
/// A stream silent past one keepalive (and a little) may be on a link that is gone: one opened in its place reads
/// again what it may have missed.
pub const STREAM_QUIET_MS: u64 = 30_000;
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

mod wire;
pub use wire::{WireReply, StationWire, WireSocket, SocketOut, SocketFrame, MeshSource, StationCredentials, MeshWire, wire};
#[cfg(test)]
use wire::first_answer;

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
    /// When the open stream last gave anything (its keepalive included); None while none is open.
    heard: Option<f64>,
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
            heard: None,
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

    /// Brings the topics a successful write changed up to date before the write answers, so a page that moves on
    /// right away finds what it wrote: from the answer where it says (an overview, a thread, a read position),
    /// else by reading them again. The station's events would bring the same a moment later.
    async fn after_write(&self, station: &StationAddr, effect: &Effect, answer: &Value) {
        let name = station.to_string();
        if *effect == Effect::None { return; }
        let mut touched = Vec::new();
        match effect {
            Effect::Session(key) => {
                if let Some(key) = key {
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
            Effect::Thread { archived } => {
                if answer.get("surface").is_some() {
                    self.put_thread(&name, answer);
                    // A new chat, or an agent more in one: the sidebar's rows change.
                    touched.push(Topic::ChatRows { station: name.clone() });
                } else if let (Some(thread), Some(n)) = (answer.get("thread").and_then(Value::as_u64), answer.get("n").and_then(Value::as_u64)) {
                    self.put_read(&name, thread, n);
                }
                // A decision dismissed: the viewer's rows say so.
                if answer.get("dismissed").is_some() {
                    touched.push(Topic::ChatRows { station: name.clone() });
                }
                // Into the archive or back: out of one list and into the other.
                if *archived {
                    touched.retain(|t| !matches!(t, Topic::ChatRows { .. }));
                    touched.push(Topic::ChatRows { station: name.clone() });
                    touched.push(Topic::ArchivedRows { station: name.clone() });
                }
            }
            Effect::Connect(connect) => {
                touched.push(Topic::Overview { station: name.clone() });
                touched.push(Topic::Sessions { station: name.clone() });
                if let Some(connect) = connect {
                    touched.push(Topic::SlackApp { station: name.clone(), connect: connect.clone() });
                }
            }
            Effect::Overview => touched.push(Topic::Overview { station: name.clone() }),
            // Cleaned up or measured again: the footprint page, and the overview's line of it.
            Effect::Footprint => {
                touched.push(Topic::Footprint { station: name.clone() });
                touched.push(Topic::Overview { station: name.clone() });
            }
            // The workspace's Slack settings (its app configuration token): every connect's app reads through them.
            Effect::Slack => {
                touched.push(Topic::Overview { station: name.clone() });
                touched.extend(self.live_topics(&name, |t| matches!(t, Topic::SlackApp { .. })));
            }
            // A job stopped: it answers the job as it is now.
            Effect::Job => {
                if answer.get("id").is_some() && answer.get("state").is_some() { self.on_job(&name, answer); }
            },
            // Who the viewer is on Slack: it answers the overview, and changes which rows are theirs.
            Effect::Identity => {
                touched.push(Topic::Overview { station: name.clone() });
                touched.push(Topic::ChatRows { station: name.clone() });
            }
            Effect::None => {}
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
mod tests;
