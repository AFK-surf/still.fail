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

use std::rc::Rc;

use serde_json::Value;

use crate::error::Result;
use crate::protocol::Topic;
use crate::store::Source;

/// `"<workspace>/<station>"` or `"local"`.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum StationAddr {
    Local,
    Remote { workspace: String, station: String },
}

impl StationAddr {
    pub fn parse(text: &str) -> Result<StationAddr> {
        let _ = text;
        todo!()
    }
}

pub struct Stations {}

impl Stations {
    /// One JSON call to the admin API (path without the `/admin/api` prefix); then refetches the live topics the write can change.
    pub async fn request(&self, station: &StationAddr, method: &str, path: &str, body: Option<Value>) -> Result<Value> {
        let _ = (station, method, path, body);
        todo!("station")
    }

    /// POST /sessions/:key/files?name= with the raw bytes; answers the attachment.
    pub async fn upload(&self, station: &StationAddr, key: &str, name: &str, bytes: Vec<u8>) -> Result<Value> {
        let _ = (station, key, name, bytes);
        todo!()
    }

    /// GET /sessions/:key/files?name=: (content type, bytes).
    pub async fn file(&self, station: &StationAddr, key: &str, name: &str) -> Result<(String, Vec<u8>)> {
        let _ = (station, key, name);
        todo!()
    }
}

impl Source for Stations {
    fn start(&self, topic: &Topic) {
        let _ = topic;
        todo!()
    }

    fn stop(&self, topic: &Topic) {
        let _ = topic;
        todo!()
    }
}
