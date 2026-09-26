//! This device's iroh endpoint and its links to stations.
//!
//! One endpoint per core (its secret key is the device key, kept in storage
//! under [`DEVICE_KEY`]). A link to a station is opened with a grant from ember
//! cloud and renewed every [`RENEW_MS`] on the control stream; a closed link is
//! reopened on the next request. Wire format: mesh/station/src/main.rs — ALPN
//! `ember/admin/1`; the first bi-stream carries `{"grant": …}` lines, each
//! further bi-stream one request: a JSON head line `{method, path, headers}`
//! then the body; the reply is a JSON head line `{status, headers}` then the
//! body, streamed. The web build is relay-only (browsers have no UDP).

use std::rc::Rc;

use futures::future::LocalBoxFuture;

use crate::cloud::Grant;
use crate::error::Result;
use crate::host::Host;

pub const DEVICE_KEY: &str = "device";
pub const ALPN: &[u8] = b"ember/admin/1";
pub const RENEW_MS: u64 = 5 * 60_000;

/// Gets a fresh grant for a station, for this device's id (hex).
pub type GrantSource = Rc<dyn Fn(String) -> LocalBoxFuture<'static, Result<Grant>>>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequestHead {
    pub method: String,
    /// Path under the station's admin API, e.g. `/admin/api/overview`.
    pub path: String,
    pub headers: Vec<(String, String)>,
}

pub struct Mesh {
    _host: Rc<dyn Host>,
}

impl Mesh {
    /// Binds the endpoint with the stored device key (making and storing one the first time).
    pub async fn new(host: Rc<dyn Host>, relay_url: &str) -> Result<Rc<Mesh>> {
        let _ = (host, relay_url);
        todo!("mesh")
    }

    /// The device key's public half, hex: what grants name.
    pub fn device_id(&self) -> String {
        todo!()
    }

    /// The link to a station, opening it (or reopening a closed one) with a grant from `grants`.
    pub async fn link(&self, station_id: &str, grants: GrantSource) -> Result<Rc<Link>> {
        let _ = (station_id, grants);
        todo!()
    }

    /// Takes over the device key a page kept before the core existed (32 bytes).
    pub async fn migrate(&self, secret: Vec<u8>) -> Result<()> {
        let _ = secret;
        todo!()
    }
}

pub struct Link {}

impl Link {
    /// One request on its own stream.
    pub async fn request(&self, head: RequestHead, body: Vec<u8>) -> Result<Reply> {
        let _ = (head, body);
        todo!()
    }

    /// Why the link closed, if it did.
    pub fn closed(&self) -> Option<String> {
        todo!()
    }
}

pub struct Reply {
    pub status: u16,
    pub headers: Vec<(String, String)>,
}

impl Reply {
    /// The next chunk of the body; None at its end.
    pub async fn next(&mut self) -> Option<Result<Vec<u8>>> {
        todo!()
    }

    /// The rest of the body.
    pub async fn body(self) -> Result<Vec<u8>> {
        todo!()
    }
}
