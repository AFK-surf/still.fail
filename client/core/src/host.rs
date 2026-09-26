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

pub trait Host {
    /// Where ember cloud is: the page's origin on the web, https://ember.3720.org natively.
    fn cloud_origin(&self) -> String;

    fn fetch(&self, request: HttpRequest) -> LocalBoxFuture<'static, Result<HttpResponse, HostError>>;
    fn fetch_stream(&self, request: HttpRequest) -> LocalBoxFuture<'static, Result<StreamResponse, HostError>>;

    /// Small persistent values by key: accounts, the device key, preferences.
    fn storage_get(&self, key: &str) -> LocalBoxFuture<'static, Result<Option<Vec<u8>>, HostError>>;
    fn storage_set(&self, key: &str, value: Vec<u8>) -> LocalBoxFuture<'static, Result<(), HostError>>;
    fn storage_delete(&self, key: &str) -> LocalBoxFuture<'static, Result<(), HostError>>;

    /// Milliseconds since the Unix epoch.
    fn now_ms(&self) -> f64;
    /// The viewer's time zone at that moment: minutes to add to UTC to get local time.
    fn utc_offset_min(&self, at_ms: f64) -> i32;
    fn sleep(&self, ms: u64) -> LocalBoxFuture<'static, ()>;
    /// Runs a task to completion on the core's thread.
    fn spawn(&self, task: LocalBoxFuture<'static, ()>);
    fn random_bytes(&self, buf: &mut [u8]);

    /// Delivers a message to one connected UI.
    fn emit(&self, client: ClientId, message: CoreMessage);
}
