//! A host for tests: in-memory storage, HTTP answered by a closure you set,
//! emissions collected, time and tasks on tokio. Run tests on a current-thread
//! runtime inside a `LocalSet` (see `run`), since the core's futures are !Send.
//!
//! ```ignore
//! ember_core::testing::run(async {
//!     let host = FakeHost::new();
//!     host.on_fetch(|req| json_response(200, serde_json::json!({"ok": true})));
//!     let core = Core::new(host.clone()).await;
//!     …
//!     host.settle().await;              // let spawned tasks and coalesced emissions run
//!     let sent = host.take_emitted();   // Vec<(ClientId, CoreMessage)>
//! });
//! ```

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use futures::future::LocalBoxFuture;
use futures::{FutureExt, StreamExt};

use crate::host::{Host, HostError, HttpRequest, HttpResponse, StreamResponse};
use crate::protocol::{ClientId, CoreMessage};

type Responder = Box<dyn Fn(&HttpRequest) -> Result<HttpResponse, HostError>>;
type StreamResponder = Box<dyn Fn(&HttpRequest) -> Result<StreamResponse, HostError>>;

pub struct FakeHost {
    pub origin: String,
    storage: RefCell<HashMap<String, Vec<u8>>>,
    responder: RefCell<Option<Responder>>,
    stream_responder: RefCell<Option<StreamResponder>>,
    /// Every request fetched, in order.
    pub requests: RefCell<Vec<HttpRequest>>,
    emitted: RefCell<Vec<(ClientId, CoreMessage)>>,
    seed: RefCell<u64>,
}

impl FakeHost {
    pub fn new() -> Rc<FakeHost> {
        Rc::new(FakeHost {
            origin: "https://ember.test".into(),
            storage: RefCell::default(),
            responder: RefCell::default(),
            stream_responder: RefCell::default(),
            requests: RefCell::default(),
            emitted: RefCell::default(),
            seed: RefCell::new(0x5eed),
        })
    }

    pub fn on_fetch(&self, responder: impl Fn(&HttpRequest) -> Result<HttpResponse, HostError> + 'static) {
        *self.responder.borrow_mut() = Some(Box::new(responder));
    }

    pub fn on_fetch_stream(&self, responder: impl Fn(&HttpRequest) -> Result<StreamResponse, HostError> + 'static) {
        *self.stream_responder.borrow_mut() = Some(Box::new(responder));
    }

    pub fn stored(&self, key: &str) -> Option<Vec<u8>> {
        self.storage.borrow().get(key).cloned()
    }

    pub fn store(&self, key: &str, value: Vec<u8>) {
        self.storage.borrow_mut().insert(key.into(), value);
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
    let runtime = tokio::runtime::Builder::new_current_thread().enable_time().build().unwrap();
    let local = tokio::task::LocalSet::new();
    local.block_on(&runtime, body);
}

impl Host for FakeHost {
    fn cloud_origin(&self) -> String {
        self.origin.clone()
    }

    fn fetch(&self, request: HttpRequest) -> LocalBoxFuture<'static, Result<HttpResponse, HostError>> {
        self.requests.borrow_mut().push(request.clone());
        let answer = match self.responder.borrow().as_ref() {
            Some(r) => r(&request),
            None => Err(HostError(format!("no responder for {} {}", request.method, request.url))),
        };
        async move { answer }.boxed_local()
    }

    fn fetch_stream(&self, request: HttpRequest) -> LocalBoxFuture<'static, Result<StreamResponse, HostError>> {
        self.requests.borrow_mut().push(request.clone());
        let answer = match self.stream_responder.borrow().as_ref() {
            Some(r) => r(&request),
            None => Err(HostError(format!("no stream responder for {} {}", request.method, request.url))),
        };
        async move { answer }.boxed_local()
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

    fn now_ms(&self) -> f64 {
        std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() as f64
    }

    fn sleep(&self, ms: u64) -> LocalBoxFuture<'static, ()> {
        tokio::time::sleep(std::time::Duration::from_millis(ms)).boxed_local()
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
