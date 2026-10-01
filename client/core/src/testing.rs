//! A host for tests: in-memory storage, HTTP answered by a closure you set,
//! emissions collected, time and tasks on tokio. Run tests on a current-thread
//! runtime inside a `LocalSet` (see `run`), since the core's futures are !Send.
//!
//! ```ignore
//! stillfail_core::testing::run(async {
//!     let host = FakeHost::new();
//!     host.on_fetch(|req| json_response(200, serde_json::json!({"ok": true})));
//!     let core = Core::new(host.clone()).await;
//!     …
//!     host.settle().await;              // let spawned tasks and coalesced emissions run
//!     let sent = host.take_emitted();   // Vec<(ClientId, CoreMessage)>
//! });
//! ```

use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::Rc;

use futures::future::LocalBoxFuture;
use futures::{FutureExt, StreamExt};

use crate::error::CoreError;
use crate::host::{Host, HostError, HttpRequest, HttpResponse, StreamResponse};
use crate::mesh::RequestHead;
use crate::protocol::{ClientId, CoreMessage};
use crate::station::{StationAddr, StationWire, WireReply};

type Responder = Box<dyn Fn(&HttpRequest) -> Result<HttpResponse, HostError>>;
type StreamResponder = Box<dyn Fn(&HttpRequest) -> Result<StreamResponse, HostError>>;

pub struct FakeHost {
    pub origin: String,
    /// A beta app's host (`Host::beta`).
    pub beta: Cell<bool>,
    /// On the test channel without being a beta app, as the web is on the test channel's host (`Host::test_channel`).
    pub test_channel: Cell<bool>,
    storage: RefCell<HashMap<String, Vec<u8>>>,
    /// The core's database: (table, key) → bytes.
    pub db: RefCell<std::collections::BTreeMap<(String, String), Vec<u8>>>,
    responder: RefCell<Option<Responder>>,
    stream_responder: RefCell<Option<StreamResponder>>,
    /// The WebSockets opened: url, protocols, and the sender that feeds their frames (dropping it closes the socket).
    pub sockets: RefCell<Vec<(String, Vec<String>, futures::channel::mpsc::UnboundedSender<Result<String, HostError>>)>>,
    /// Refuse to open WebSockets (as a browser does when the server says no).
    pub refuse_sockets: Cell<bool>,
    /// How many times the core let the host's connections go (`reset_connections`).
    pub resets: Cell<u32>,
    /// Every request fetched, in order.
    pub requests: RefCell<Vec<HttpRequest>>,
    /// Every sleep asked for (ms, before speeding up), in order: timers show here.
    pub sleeps: RefCell<Vec<u64>>,
    /// Requests held back (`hold`): by what their url ends with, until let go.
    holds: RefCell<Vec<(String, futures::channel::oneshot::Receiver<()>)>>,
    pub emitted: RefCell<Vec<(ClientId, CoreMessage)>>,
    seed: RefCell<u64>,
    utc_offset_min: Cell<i32>,
    speedup: Cell<u64>,
}

impl FakeHost {
    pub fn new() -> Rc<FakeHost> {
        Rc::new(FakeHost {
            origin: "https://stillfail.test".into(),
            beta: Cell::new(false),
            test_channel: Cell::new(false),
            storage: RefCell::default(),
            db: RefCell::default(),
            responder: RefCell::default(),
            stream_responder: RefCell::default(),
            sockets: RefCell::default(),
            refuse_sockets: Cell::new(false),
            resets: Cell::new(0),
            requests: RefCell::default(),
            sleeps: RefCell::default(),
            holds: RefCell::default(),
            emitted: RefCell::default(),
            seed: RefCell::new(0x5eed),
            utc_offset_min: Cell::new(0),
            speedup: Cell::new(1),
        })
    }

    pub fn on_fetch(&self, responder: impl Fn(&HttpRequest) -> Result<HttpResponse, HostError> + 'static) {
        *self.responder.borrow_mut() = Some(Box::new(responder));
    }

    pub fn on_fetch_stream(&self, responder: impl Fn(&HttpRequest) -> Result<StreamResponse, HostError> + 'static) {
        *self.stream_responder.borrow_mut() = Some(Box::new(responder));
    }

    /// Holds back the answer of the next request whose url ends with `path` until the sender is used or dropped.
    pub fn hold(&self, path: &str) -> futures::channel::oneshot::Sender<()> {
        let (tx, rx) = futures::channel::oneshot::channel();
        self.holds.borrow_mut().push((path.to_string(), rx));
        tx
    }

    pub fn stored(&self, key: &str) -> Option<Vec<u8>> {
        self.storage.borrow().get(key).cloned()
    }

    pub fn store(&self, key: &str, value: Vec<u8>) {
        self.storage.borrow_mut().insert(key.into(), value);
    }

    /// The viewer's time zone (default UTC).
    pub fn set_utc_offset_min(&self, minutes: i32) {
        self.utc_offset_min.set(minutes);
    }

    /// Makes the core's timers run `factor` times faster (eviction after 0.6 s at 100).
    pub fn speed_up(&self, factor: u64) {
        self.speedup.set(factor);
    }

    /// Sends a text frame on the newest open WebSocket whose url ends with `path`.
    pub fn socket_send(&self, path: &str, text: &str) {
        let sockets = self.sockets.borrow();
        let (_, _, tx) = sockets.iter().rev().find(|(url, _, tx)| url.ends_with(path) && !tx.is_closed()).expect("socket open");
        tx.unbounded_send(Ok(text.to_string())).unwrap();
    }

    /// Closes every WebSocket whose url ends with `path` (the server went away).
    pub fn socket_close(&self, path: &str) {
        for (url, _, tx) in self.sockets.borrow().iter() {
            if url.ends_with(path) {
                tx.close_channel();
            }
        }
    }

    /// WebSockets whose url ends with `path` that are still open.
    pub fn open_sockets(&self, path: &str) -> usize {
        self.sockets.borrow().iter().filter(|(url, _, tx)| url.ends_with(path) && !tx.is_closed()).count()
    }

    pub fn take_emitted(&self) -> Vec<(ClientId, CoreMessage)> {
        std::mem::take(&mut self.emitted.borrow_mut())
    }

    /// Lets spawned tasks and timers up to `COALESCE_MS` run.
    pub async fn settle(&self) {
        for _ in 0..5 {
            tokio::task::yield_now().await;
        }
        tokio::time::sleep(std::time::Duration::from_millis(crate::store::COALESCE_MS + 20)).await;
        for _ in 0..5 {
            tokio::task::yield_now().await;
        }
    }
}

/// A JSON response.
pub fn json_response(status: u16, value: serde_json::Value) -> Result<HttpResponse, HostError> {
    Ok(HttpResponse { status, headers: vec![("content-type".into(), "application/json".into())], body: serde_json::to_vec(&value).unwrap() })
}

/// Runs a test body on a current-thread runtime with a LocalSet (for !Send futures and `spawn_local`).
pub fn run<F: std::future::Future<Output = ()>>(body: F) {
    let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
    let local = tokio::task::LocalSet::new();
    local.block_on(&runtime, body);
}

impl Host for FakeHost {
    fn cloud_origin(&self) -> String {
        self.origin.clone()
    }

    fn beta(&self) -> bool {
        self.beta.get()
    }

    fn test_channel(&self) -> bool {
        self.beta.get() || self.test_channel.get()
    }

    fn fetch(&self, request: HttpRequest) -> LocalBoxFuture<'static, Result<HttpResponse, HostError>> {
        self.requests.borrow_mut().push(request.clone());
        let answer = match self.responder.borrow().as_ref() {
            Some(r) => r(&request),
            None => Err(HostError(format!("no responder for {} {}", request.method, request.url))),
        };
        let held = {
            let mut holds = self.holds.borrow_mut();
            holds.iter().position(|(path, _)| request.url.ends_with(path.as_str())).map(|i| holds.remove(i).1)
        };
        async move {
            if let Some(held) = held {
                let _ = held.await;
            }
            answer
        }
        .boxed_local()
    }

    fn fetch_stream(&self, request: HttpRequest) -> LocalBoxFuture<'static, Result<StreamResponse, HostError>> {
        self.requests.borrow_mut().push(request.clone());
        let answer = match self.stream_responder.borrow().as_ref() {
            Some(r) => r(&request),
            None => Err(HostError(format!("no stream responder for {} {}", request.method, request.url))),
        };
        async move { answer }.boxed_local()
    }

    fn websocket(&self, url: String, protocols: Vec<String>) -> LocalBoxFuture<'static, Result<crate::host::SocketFrames, HostError>> {
        if self.refuse_sockets.get() {
            return async { Err(HostError("refused".into())) }.boxed_local();
        }
        let (tx, rx) = futures::channel::mpsc::unbounded();
        self.sockets.borrow_mut().push((url, protocols, tx));
        async move { Ok(rx.boxed_local()) }.boxed_local()
    }

    fn reset_connections(&self) {
        self.resets.set(self.resets.get() + 1);
    }

    fn storage_get(&self, key: &str) -> LocalBoxFuture<'static, Result<Option<Vec<u8>>, HostError>> {
        let value = self.storage.borrow().get(key).cloned();
        async move { Ok(value) }.boxed_local()
    }

    fn storage_set(&self, key: &str, value: Vec<u8>) -> LocalBoxFuture<'static, Result<(), HostError>> {
        self.storage.borrow_mut().insert(key.into(), value);
        async { Ok(()) }.boxed_local()
    }

    fn storage_delete(&self, key: &str) -> LocalBoxFuture<'static, Result<(), HostError>> {
        self.storage.borrow_mut().remove(key);
        async { Ok(()) }.boxed_local()
    }

    fn db_read(&self, range: crate::host::DbRange) -> LocalBoxFuture<'static, Result<Vec<(String, Vec<u8>)>, HostError>> {
        let db = self.db.borrow();
        let found = db
            .range((range.table.clone(), range.from.clone())..(range.table.clone(), range.to.clone()))
            .map(|((_, key), value)| (key.clone(), value.clone()))
            .collect();
        async move { Ok(found) }.boxed_local()
    }

    fn db_write(&self, ops: Vec<crate::host::DbOp>) -> LocalBoxFuture<'static, Result<(), HostError>> {
        let mut db = self.db.borrow_mut();
        for op in ops {
            match op {
                crate::host::DbOp::Put { table, key, value } => {
                    db.insert((table, key), value);
                }
                crate::host::DbOp::Delete { table, key } => {
                    db.remove(&(table, key));
                }
            }
        }
        async { Ok(()) }.boxed_local()
    }

    fn now_ms(&self) -> f64 {
        std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() as f64
    }

    fn utc_offset_min(&self, _at_ms: f64) -> i32 {
        self.utc_offset_min.get()
    }

    fn sleep(&self, ms: u64) -> LocalBoxFuture<'static, ()> {
        self.sleeps.borrow_mut().push(ms);
        tokio::time::sleep(std::time::Duration::from_micros(ms * 1000 / self.speedup.get())).boxed_local()
    }

    fn spawn(&self, task: LocalBoxFuture<'static, ()>) {
        tokio::task::spawn_local(task);
    }

    fn random_bytes(&self, buf: &mut [u8]) {
        // Deterministic xorshift: tests see the same "random" values every run.
        let mut s = self.seed.borrow_mut();
        for b in buf.iter_mut() {
            *s ^= *s << 13;
            *s ^= *s >> 7;
            *s ^= *s << 17;
            *b = (*s & 0xff) as u8;
        }
    }

    fn emit(&self, client: ClientId, message: CoreMessage) {
        self.emitted.borrow_mut().push((client, message));
    }
}

/// A streamed body from fixed chunks, for `on_fetch_stream`.
pub fn chunks(parts: Vec<Vec<u8>>) -> futures::stream::LocalBoxStream<'static, Result<Vec<u8>, HostError>> {
    futures::stream::iter(parts.into_iter().map(Ok)).boxed_local()
}

/// Stations for tests, in place of the mesh: every one answers over the host's fetch, at `<cloud origin><path>`. An
/// event stream (`accept: text/event-stream`) and a preview's answer come as they are sent, the rest whole.
pub struct HostWire {
    host: Rc<dyn Host>,
}

impl HostWire {
    pub fn new(host: Rc<dyn Host>) -> Rc<HostWire> {
        Rc::new(HostWire { host })
    }
}

impl StationWire for HostWire {
    fn request(&self, _station: &StationAddr, head: RequestHead, body: Vec<u8>) -> LocalBoxFuture<'static, Result<WireReply, CoreError>> {
        let stream = head.path.starts_with("/admin/api/preview/") || head.headers.iter().any(|(k, v)| k.eq_ignore_ascii_case("accept") && v.contains("text/event-stream"));
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
                Ok(WireReply { status: r.status, headers: r.headers, body: r.body.map(|c| c.map_err(CoreError::from)).boxed_local(), via: None })
            }
            .boxed_local()
        } else {
            let answer = self.host.fetch(request);
            async move {
                let r = answer.await?;
                Ok(WireReply { status: r.status, headers: r.headers, body: futures::stream::iter([Ok(r.body)]).boxed_local(), via: None })
            }
            .boxed_local()
        }
    }
}
