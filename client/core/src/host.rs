//! What differs per platform. The web host (client/wasm) implements this over
//! fetch and IndexedDB on a worker; native hosts over reqwest-like HTTP and
//! files. Tests use `tests/fake_host.rs`.

use futures::future::LocalBoxFuture;
use futures::stream::LocalBoxStream;

use crate::protocol::{ClientId, CoreMessage};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostError(pub String);

impl std::fmt::Display for HostError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, Default)]
pub struct HttpRequest {
    pub method: String,
    /// Absolute URL.
    pub url: String,
    pub headers: Vec<(String, String)>,
    pub body: Option<Vec<u8>>,
}

#[derive(Debug, Clone, Default)]
pub struct HttpResponse {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

impl HttpResponse {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers.iter().find(|(k, _)| k.eq_ignore_ascii_case(name)).map(|(_, v)| v.as_str())
    }
}

/// A response whose body arrives in chunks (event streams).
pub struct StreamResponse {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: LocalBoxStream<'static, Result<Vec<u8>, HostError>>,
}

/// A receive-only WebSocket's text frames. The stream ends when the socket closes; dropping it closes the socket.
pub type SocketFrames = LocalBoxStream<'static, Result<String, HostError>>;

/// Keys `[from, to)` of one table of the core's database (docs/core-db.md), in key order.
#[derive(Clone, Debug, PartialEq)]
pub struct DbRange {
    pub table: String,
    pub from: String,
    pub to: String,
}

/// One change to the core's database; a batch of them is written at once or not at all.
#[derive(Clone, Debug, PartialEq)]
pub enum DbOp {
    Put { table: String, key: String, value: Vec<u8> },
    Delete { table: String, key: String },
}

pub trait Host {
    /// Where ember cloud is: the page's origin on the web, https://ember.3720.org natively.
    fn cloud_origin(&self) -> String;

    fn fetch(&self, request: HttpRequest) -> LocalBoxFuture<'static, Result<HttpResponse, HostError>>;
    fn fetch_stream(&self, request: HttpRequest) -> LocalBoxFuture<'static, Result<StreamResponse, HostError>>;
    /// Opens a WebSocket that only listens (ember cloud's `/v1/events`); resolves once it is open.
    fn websocket(&self, url: String, protocols: Vec<String>) -> LocalBoxFuture<'static, Result<SocketFrames, HostError>>;

    /// Small persistent values by key: accounts, the device key, preferences.
    fn storage_get(&self, key: &str) -> LocalBoxFuture<'static, Result<Option<Vec<u8>>, HostError>>;
    fn storage_set(&self, key: &str, value: Vec<u8>) -> LocalBoxFuture<'static, Result<(), HostError>>;
    fn storage_delete(&self, key: &str) -> LocalBoxFuture<'static, Result<(), HostError>>;

    /// The core's database (docs/core-db.md): records by table and key — SQLite natively, IndexedDB on the web.
    /// A host without one keeps nothing: reads find nothing, writes are dropped.
    fn db_read(&self, _range: DbRange) -> LocalBoxFuture<'static, Result<Vec<(String, Vec<u8>)>, HostError>> {
        Box::pin(async { Ok(Vec::new()) })
    }
    fn db_write(&self, _ops: Vec<DbOp>) -> LocalBoxFuture<'static, Result<(), HostError>> {
        Box::pin(async { Ok(()) })
    }

    /// Milliseconds since the Unix epoch.
    fn now_ms(&self) -> f64;
    /// Milliseconds on a clock that only moves forward, for timing spans (web: `performance.now()`); its zero is
    /// the host's own.
    fn monotonic_ms(&self) -> f64 {
        self.now_ms()
    }
    /// The viewer's time zone at that moment: minutes to add to UTC to get local time.
    fn utc_offset_min(&self, at_ms: f64) -> i32;
    fn sleep(&self, ms: u64) -> LocalBoxFuture<'static, ()>;
    /// The next time a UI says it is back after being away (wake.rs); never, on a host the core has not wrapped.
    fn woken(&self) -> LocalBoxFuture<'static, crate::wake::Wake> {
        Box::pin(futures::future::pending())
    }
    /// Runs a task to completion on the core's thread.
    fn spawn(&self, task: LocalBoxFuture<'static, ()>);
    fn random_bytes(&self, buf: &mut [u8]);

    /// Delivers a message to one connected UI.
    fn emit(&self, client: ClientId, message: CoreMessage);
}
