//! The station's traces: the mesh's own spans (a request stream from
//! accepted to fully answered). Batched, and sent at most every
//! EXPORT to still.fail cloud's `/v1/telemetry/traces`, signed with the station's
//! key like the presence socket; the cloud forwards them to Axiom. A batch
//! that cannot be sent is dropped. Off unless the station's config turns
//! traces on (telemetry.traces).

use std::{
    sync::{Arc, Mutex},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use iroh::SecretKey;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use tokio::sync::Notify;
use tracing::{info, warn};

use crate::{Station, http, now};

/// Spans wait this long to go out together.
const EXPORT: Duration = Duration::from_secs(3);
/// Spans kept while waiting; beyond this they are dropped.
const MAX_BUFFER: usize = 2_000;
/// At most this many spans in one batch (the cloud caps a batch's size).
const MAX_BATCH: usize = 500;

/// A W3C trace context: the trace, the caller's span, whether it is recorded.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Parent {
    pub trace: [u8; 16],
    pub span: [u8; 8],
    pub sampled: bool,
}

impl Parent {
    /// `00-<trace>-<span>-<flags>`; anything else is no context.
    pub fn parse(header: &str) -> Option<Parent> {
        let parts: Vec<&str> = header.trim().split('-').collect();
        let [version, trace, span, flags] = parts[..] else { return None };
        if version.len() != 2 || version == "ff" || flags.len() != 2 {
            return None;
        }
        let trace: [u8; 16] = hex::decode(trace).ok()?.try_into().ok()?;
        let span: [u8; 8] = hex::decode(span).ok()?.try_into().ok()?;
        let flags = u8::from_str_radix(flags, 16).ok()?;
        if trace == [0; 16] || span == [0; 8] {
            return None;
        }
        Some(Parent { trace, span, sampled: flags & 1 == 1 })
    }
}

pub struct Telemetry {
    enabled: bool,
    spans: Mutex<Vec<(&'static str, Value)>>,
    waiting: Notify,
}

/// One span being timed: the wall clock when it started, then the monotonic one.
pub struct Span {
    pub parent: Parent,
    pub id: [u8; 8],
    wall: SystemTime,
    started: Instant,
}

impl Span {
    /// The `traceparent` for what this span asks of others.
    pub fn traceparent(&self) -> String {
        format!("00-{}-{}-01", hex::encode(self.parent.trace), hex::encode(self.id))
    }
}

impl Telemetry {
    pub fn new(enabled: bool) -> Arc<Telemetry> {
        Arc::new(Telemetry { enabled, spans: Mutex::default(), waiting: Notify::new() })
    }

    /// A span under `parent`, started at `since` (the wall clock and the monotonic one), when traces are on and the
    /// caller records this trace.
    pub fn start(&self, parent: Option<Parent>, since: (SystemTime, Instant)) -> Option<Span> {
        let parent = parent.filter(|p| self.enabled && p.sampled)?;
        let mut id = [0u8; 8];
        getrandom::fill(&mut id).ok()?;
        Some(Span { parent, id, wall: since.0, started: since.1 })
    }

    /// Ends `span` as an OTLP server span with these attributes (keys and string, number or bool values).
    pub fn end(&self, span: Span, name: String, attributes: &[(&str, Value)], failed: bool) {
        let start = span.wall.duration_since(UNIX_EPOCH).unwrap_or_default();
        let end = start + span.started.elapsed();
        let value = json!({
            "traceId": hex::encode(span.parent.trace),
            "spanId": hex::encode(span.id),
            "parentSpanId": hex::encode(span.parent.span),
            "name": name,
            "kind": 2,
            "startTimeUnixNano": start.as_nanos().to_string(),
            "endTimeUnixNano": end.as_nanos().to_string(),
            "attributes": attributes.iter().map(|(k, v)| attribute(k, v)).collect::<Vec<_>>(),
            "status": { "code": if failed { 2 } else { 1 } },
        });
        self.record("stillfail-mesh", value);
    }

    fn record(&self, service: &'static str, span: Value) {
        if !self.enabled {
            return;
        }
        let mut spans = self.spans.lock().unwrap();
        if spans.len() < MAX_BUFFER {
            spans.push((service, span));
        }
        drop(spans);
        self.waiting.notify_one();
    }

    pub fn enabled(&self) -> bool {
        self.enabled
    }

    /// Sends what was recorded, a batch at a time, until the process ends.
    pub async fn export(self: Arc<Self>, station: Arc<Station>, key: SecretKey) {
        let client = http();
        loop {
            self.waiting.notified().await;
            // Whatever else comes meanwhile goes in the same batch.
            tokio::time::sleep(EXPORT).await;
            loop {
                let batch: Vec<(&'static str, Value)> = {
                    let mut spans = self.spans.lock().unwrap();
                    let n = spans.len().min(MAX_BATCH);
                    spans.drain(..n).collect()
                };
                if batch.is_empty() {
                    break;
                }
                if let Err(error) = send(&client, &station, &key, batch).await {
                    warn!(%error, "traces dropped");
                }
            }
        }
    }
}

/// Posts one batch with a canonical proof and a separate legacy proof for pre-rename clouds.
async fn send(client: &reqwest::Client, station: &Station, key: &SecretKey, batch: Vec<(&'static str, Value)>) -> anyhow::Result<()> {
    let (origin, id) = {
        let s = station.state.lock().unwrap();
        (s.origin.clone(), s.station.clone())
    };
    let mut services: Vec<(&'static str, Vec<Value>)> = Vec::new();
    for (service, span) in batch {
        match services.iter_mut().find(|(s, _)| *s == service) {
            Some((_, spans)) => spans.push(span),
            None => services.push((service, vec![span])),
        }
    }
    let body = serde_json::to_vec(&json!({
        "resourceSpans": services.into_iter().map(|(service, spans)| json!({
            "resource": { "attributes": [attribute("service.name", &json!(service)), attribute("stillfail.station", &json!(id))] },
            "scopeSpans": [{ "scope": { "name": service }, "spans": spans }],
        })).collect::<Vec<_>>(),
    }))?;
    let ts = now();
    let digest = hex::encode(Sha256::digest(&body));
    let signature = hex::encode(key.sign(format!("stillfail-station-telemetry-v1:{origin}:{id}:{ts}:{digest}").as_bytes()).to_bytes());
    let former_signature = hex::encode(key.sign(format!("ember-station-telemetry-v1:{origin}:{id}:{ts}:{digest}").as_bytes()).to_bytes());
    let response = client
        .post(format!("{origin}/v1/telemetry/traces"))
        .header("content-type", "application/json")
        .header("x-stillfail-station", &id)
        .header("x-stillfail-ts", ts.to_string())
        .header("x-stillfail-signature", &signature)
        .header("x-ember-station", &id)
        .header("x-ember-ts", ts.to_string())
        .header("x-ember-signature", former_signature)
        .body(body)
        .send()
        .await?;
    if !response.status().is_success() {
        anyhow::bail!("still.fail cloud answered {}", response.status());
    }
    info!("traces sent");
    Ok(())
}

fn attribute(key: &str, value: &Value) -> Value {
    let value = match value {
        Value::Bool(b) => json!({ "boolValue": b }),
        Value::Number(n) if n.is_i64() || n.is_u64() => json!({ "intValue": n.to_string() }),
        Value::Number(n) => json!({ "doubleValue": n.as_f64() }),
        Value::String(s) => json!({ "stringValue": s }),
        other => json!({ "stringValue": other.to_string() }),
    };
    json!({ "key": key, "value": value })
}

/// Collections whose next path segment is an id, whatever it looks like (as the client core has it).
const COLLECTIONS: [&str; 10] = ["sessions", "threads", "connects", "profiles", "logins", "workspaces", "stations", "members", "enrollments", "accounts"];

/// A request path as a span shows it: no query, ids as `:id`.
pub fn route(path: &str) -> String {
    let path = path.split(['?', '#']).next().unwrap_or("");
    let mut after_collection = false;
    path.split('/')
        .map(|segment| {
            let word = !segment.is_empty()
                && segment.len() <= 24
                && segment.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-' || b == b'_' || b == b'.')
                && segment.bytes().any(|b| b.is_ascii_lowercase());
            let id = !segment.is_empty() && (after_collection || !word);
            after_collection = !id && COLLECTIONS.contains(&segment);
            if id { ":id" } else { segment }
        })
        .collect::<Vec<_>>()
        .join("/")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_traceparent() {
        let parent = Parent::parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01").unwrap();
        assert!(parent.sampled);
        assert_eq!(hex::encode(parent.span), "00f067aa0ba902b7");
        assert!(!Parent::parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00").unwrap().sampled);
        for bad in ["", "00-zz-00f067aa0ba902b7-01", "00-00000000000000000000000000000000-00f067aa0ba902b7-01", "ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"] {
            assert_eq!(Parent::parse(bad), None, "{bad}");
        }
    }

    #[test]
    fn spans_only_when_on_and_sampled() {
        let parent = Parent::parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01");
        let now = || (SystemTime::now(), Instant::now());
        let off = Telemetry::new(false);
        assert!(off.start(parent, now()).is_none());
        let on = Telemetry::new(true);
        assert!(on.start(None, now()).is_none());
        assert!(on.start(Parent::parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"), now()).is_none());
        let span = on.start(parent, now()).unwrap();
        let traceparent = span.traceparent();
        assert!(traceparent.starts_with("00-4bf92f3577b34da6a3ce929d0e0e4736-") && traceparent.ends_with("-01"));
        on.end(span, "GET /admin/api/threads".into(), &[("http.response.status_code", json!(200))], false);
        let spans = on.spans.lock().unwrap();
        let (service, span) = &spans[0];
        assert_eq!(*service, "stillfail-mesh");
        assert_eq!(span["parentSpanId"], "00f067aa0ba902b7");
        assert_eq!(span["attributes"][0]["value"]["intValue"], "200");
        assert_eq!(&traceparent[36..52], span["spanId"].as_str().unwrap());
    }

    #[test]
    fn routes_hide_ids() {
        assert_eq!(route("/admin/api/threads/42/messages?limit=50"), "/admin/api/threads/:id/messages");
        assert_eq!(route("/admin/api/sessions/slack:T1:C1/files?name=a.pdf"), "/admin/api/sessions/:id/files");
    }
}
