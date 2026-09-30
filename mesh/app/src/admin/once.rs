//! Writes asked with an `idempotency-key` header happen once. A client that is not sure a write arrived (its
//! connection went quiet) asks again on another connection, or on two at once, with the same key; the station does
//! the first and answers any other with that first answer, so nothing is said twice. While the first is under way,
//! the others wait for it. Answers are kept [`KEEP`], in memory: long past any client's asking again.
//!
//! A 5xx is not kept (the write may not have happened; asked again, it is tried again). Every answer says the station
//! does this ([`HEADER`]), so a client knows which stations it may ask twice.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use bytes::Bytes;
use http_body_util::BodyExt;
use hyper::Response;
use hyper::header::{HeaderMap, HeaderValue};

use super::{Body, full, json_response};
use serde_json::json;

/// The header a write's key comes in.
pub const KEY: &str = "idempotency-key";
/// On every answer: this station keeps writes to once.
pub const HEADER: &str = "stillfail-idempotent";
/// How long an answer is kept.
pub const KEEP: Duration = Duration::from_secs(10 * 60);

struct Kept {
    at: Instant,
    status: u16,
    headers: HeaderMap,
    body: Bytes,
}

impl Kept {
    fn response(&self) -> Response<Body> {
        let mut response = Response::new(full(self.body.clone()));
        *response.status_mut() = hyper::StatusCode::from_u16(self.status).unwrap_or(hyper::StatusCode::OK);
        *response.headers_mut() = self.headers.clone();
        response
    }
}

type Slot = Arc<tokio::sync::Mutex<Option<Kept>>>;

#[derive(Default)]
pub struct Once {
    slots: Mutex<HashMap<String, Slot>>,
}

impl Once {
    /// `write`'s answer, or the answer the first write under `key` had.
    pub async fn run(&self, key: String, write: impl Future<Output = Response<Body>>) -> Response<Body> {
        let slot = {
            let mut slots = self.slots.lock().unwrap();
            // What is old goes (a slot under way is held by its writer, and kept).
            slots.retain(|_, slot| slot.try_lock().map_or(true, |kept| kept.as_ref().is_none_or(|k| k.at.elapsed() < KEEP)));
            slots.entry(key).or_default().clone()
        };
        let mut kept = slot.lock().await;
        if let Some(kept) = kept.as_ref() {
            return kept.response();
        }
        let (parts, body) = write.await.into_parts();
        let body = match body.collect().await {
            Ok(collected) => collected.to_bytes(),
            Err(e) => return json_response(500, &json!({ "error": e.to_string() })),
        };
        let answer = Kept { at: Instant::now(), status: parts.status.as_u16(), headers: parts.headers, body };
        let response = answer.response();
        if answer.status < 500 {
            *kept = Some(answer);
        }
        response
    }
}

/// Says on an answer that this station keeps writes to once.
pub fn mark(response: &mut Response<Body>) {
    response.headers_mut().insert(HEADER, HeaderValue::from_static("1"));
}
