//! Distributed tracing: one trace per user action, spans for what it asks of
//! stations and still.fail cloud, exported as OTLP JSON to still.fail cloud's
//! `/v1/telemetry/traces` (which forwards to Axiom). See docs/telemetry.md.
//!
//! The core is single-threaded, so the trace an operation belongs to travels
//! as the tracer's *current* context: [`Tracer::enter`] sets it around a
//! synchronous call (starting a view starts its topics and their requests
//! inside it), [`Tracer::instrument`] around every poll of a future. Tasks
//! spawned by the station module take the context they were spawned in.
//!
//! Every station request carries a W3C `traceparent`; stillfail-mesh and the
//! admin API record their spans under it. Spans are batched and sent at most
//! every [`EXPORT_MS`]; a batch that cannot be sent is dropped.

use std::cell::{Cell, RefCell};
use std::future::Future;
use std::pin::Pin;
use std::rc::{Rc, Weak};
use std::task::{Context, Poll};

use futures::FutureExt;
use futures::future::LocalBoxFuture;
use serde_json::{Value, json};

use crate::host::Host;

/// The share of traces recorded. Every trace for now (a small team); lower it as use grows.
pub const SAMPLE: f64 = 1.0;
/// Spans wait this long to go out together.
pub const EXPORT_MS: u64 = 3_000;
/// Spans kept while waiting; beyond this they are dropped (nobody signed in to send them, say).
const MAX_BUFFER: usize = 1_000;

/// Which clock a trace's times come from: the wall clock once, when its root started, then the monotonic one.
#[derive(Debug, Clone, Copy, PartialEq)]
struct Anchor {
    wall_ms: f64,
    mono_ms: f64,
}

/// Where a span sits: its trace, itself, and whether the trace is recorded.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SpanContext {
    pub trace: [u8; 16],
    pub span: [u8; 8],
    pub sampled: bool,
    anchor: Anchor,
}

impl SpanContext {
    /// The W3C `traceparent` header for requests made under this span.
    pub fn traceparent(&self) -> String {
        format!("00-{}-{}-{}", hex::encode(self.trace), hex::encode(self.span), if self.sampled { "01" } else { "00" })
    }
}

/// OTLP's span kinds.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Internal = 1,
    Client = 3,
}

/// Sends one OTLP JSON body; failures are the sender's to swallow.
pub type Export = Rc<dyn Fn(Vec<u8>) -> LocalBoxFuture<'static, ()>>;

pub struct Tracer {
    host: Rc<dyn Host>,
    sample: f64,
    me: Weak<Tracer>,
    current: Cell<Option<SpanContext>>,
    buffer: RefCell<Vec<Value>>,
    scheduled: Cell<bool>,
    export: RefCell<Option<Export>>,
}

impl Tracer {
    /// `sample`: the share of new traces recorded ([`SAMPLE`]; 0 records none).
    pub fn new(host: Rc<dyn Host>, sample: f64) -> Rc<Tracer> {
        Rc::new_cyclic(|me| Tracer {
            host,
            sample,
            me: me.clone(),
            current: Cell::new(None),
            buffer: RefCell::default(),
            scheduled: Cell::new(false),
            export: RefCell::default(),
        })
    }

    /// Where batches go; until this is set they wait (up to [`MAX_BUFFER`] spans).
    pub fn set_export(&self, export: Export) {
        *self.export.borrow_mut() = Some(export);
    }

    pub fn current(&self) -> Option<SpanContext> {
        self.current.get()
    }

    /// Runs `f` with `context` current: what it starts synchronously belongs to that trace.
    pub fn enter<T>(&self, context: Option<SpanContext>, f: impl FnOnce() -> T) -> T {
        let before = self.current.replace(context);
        let out = f();
        self.current.set(before);
        out
    }

    /// The future with `context` current whenever it runs.
    pub fn instrument<'a, T: 'a>(&self, context: Option<SpanContext>, future: impl Future<Output = T> + 'a) -> LocalBoxFuture<'a, T> {
        Instrumented { tracer: self.rc(), context, inner: future.boxed_local() }.boxed_local()
    }

    /// A span under the current context, or the root of a new trace if there is none.
    pub fn span(&self, name: impl Into<String>, kind: Kind) -> Span {
        match self.current.get() {
            Some(parent) => self.start(name.into(), kind, Some(parent)),
            None => self.root(name, kind),
        }
    }

    /// A span under the current context; none outside a trace.
    pub fn child(&self, name: impl Into<String>, kind: Kind) -> Option<Span> {
        let parent = self.current.get()?;
        Some(self.start(name.into(), kind, Some(parent)))
    }

    /// The root of a new trace, recorded or not as sampling decides.
    pub fn root(&self, name: impl Into<String>, kind: Kind) -> Span {
        self.start(name.into(), kind, None)
    }

    /// The root of a new trace that is always recorded, whatever the sampling: for what went wrong, which is rare and
    /// worth every one.
    pub fn always(&self, name: impl Into<String>, kind: Kind) -> Span {
        let mut span = self.start(name.into(), kind, None);
        span.context.sampled = true;
        span
    }

    fn start(&self, name: String, kind: Kind, parent: Option<SpanContext>) -> Span {
        let mut span = [0u8; 8];
        self.host.random_bytes(&mut span);
        let context = match parent {
            Some(parent) => SpanContext { span, ..parent },
            None => {
                let mut trace = [0u8; 16];
                self.host.random_bytes(&mut trace);
                let mut roll = [0u8; 4];
                self.host.random_bytes(&mut roll);
                let sampled = (u32::from_le_bytes(roll) as f64) < self.sample * (u32::MAX as f64 + 1.0);
                SpanContext { trace, span, sampled, anchor: Anchor { wall_ms: self.host.now_ms(), mono_ms: self.host.monotonic_ms() } }
            }
        };
        Span {
            tracer: self.me.clone(),
            context,
            parent: parent.map(|p| p.span),
            name,
            kind,
            start_ms: self.host.monotonic_ms(),
            attributes: Vec::new(),
            error: false,
            ended: false,
        }
    }

    fn rc(&self) -> Rc<Tracer> {
        self.me.upgrade().expect("the tracer is alive while it runs")
    }

    fn record(&self, span: Value) {
        {
            let mut buffer = self.buffer.borrow_mut();
            if buffer.len() >= MAX_BUFFER {
                return;
            }
            buffer.push(span);
        }
        if self.scheduled.replace(true) {
            return;
        }
        // The one timer here, and only while something waits to go out.
        let (wait, me) = (self.host.sleep(EXPORT_MS), self.me.clone());
        self.host.spawn(
            async move {
                wait.await;
                if let Some(tracer) = me.upgrade() {
                    tracer.flush();
                }
            }
            .boxed_local(),
        );
    }

    /// Sends what waits now, if there is somewhere to send it.
    pub fn flush(&self) {
        self.scheduled.set(false);
        let Some(export) = self.export.borrow().clone() else {
            // Kept for when there is: the next span schedules another try.
            return;
        };
        let spans = std::mem::take(&mut *self.buffer.borrow_mut());
        if spans.is_empty() {
            return;
        }
        let body = json!({
            "resourceSpans": [{
                "resource": { "attributes": [attribute("service.name", SERVICE.into())] },
                "scopeSpans": [{ "scope": { "name": "stillfail-core" }, "spans": spans }],
            }],
        });
        // Outside every trace: sending spans makes none.
        self.host.spawn(self.instrument(None, export(serde_json::to_vec(&body).unwrap_or_default())));
    }
}

/// Which client this core is, for Axiom's `service.name`.
const SERVICE: &str = if cfg!(target_arch = "wasm32") { "stillfail-web" } else { "stillfail-native" };

/// A future with a context current while it is polled.
struct Instrumented<'a, T> {
    tracer: Rc<Tracer>,
    context: Option<SpanContext>,
    inner: LocalBoxFuture<'a, T>,
}

impl<T> Future for Instrumented<'_, T> {
    type Output = T;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<T> {
        let this = self.get_mut();
        let before = this.tracer.current.replace(this.context);
        let out = this.inner.as_mut().poll(cx);
        this.tracer.current.set(before);
        out
    }
}

/// A span being timed. `end` records it; one dropped before that (its task aborted) is recorded as cancelled.
pub struct Span {
    tracer: Weak<Tracer>,
    context: SpanContext,
    parent: Option<[u8; 8]>,
    name: String,
    kind: Kind,
    start_ms: f64,
    attributes: Vec<Value>,
    error: bool,
    ended: bool,
}

impl Span {
    pub fn context(&self) -> SpanContext {
        self.context
    }

    /// An attribute: a string, number or bool. Never message content, titles or emails.
    pub fn set(&mut self, key: &str, value: impl Into<Value>) {
        if self.context.sampled {
            self.attributes.push(attribute(key, value.into()));
        }
    }

    /// Marks the span failed.
    pub fn fail(&mut self) {
        self.error = true;
    }

    pub fn end(mut self) {
        self.finish();
    }

    fn finish(&mut self) {
        self.ended = true;
        let Some(tracer) = self.tracer.upgrade() else { return };
        if !self.context.sampled {
            return;
        }
        let end_ms = tracer.host.monotonic_ms();
        let anchor = self.context.anchor;
        let nanos = |mono: f64| format!("{}", ((anchor.wall_ms + (mono - anchor.mono_ms)) * 1e6).max(0.0) as u64);
        let mut span = json!({
            "traceId": hex::encode(self.context.trace),
            "spanId": hex::encode(self.context.span),
            "name": self.name,
            "kind": self.kind as u8,
            "startTimeUnixNano": nanos(self.start_ms),
            "endTimeUnixNano": nanos(end_ms.max(self.start_ms)),
            "attributes": std::mem::take(&mut self.attributes),
            "status": { "code": if self.error { 2 } else { 1 } },
        });
        if let Some(parent) = self.parent {
            span["parentSpanId"] = json!(hex::encode(parent));
        }
        tracer.record(span);
    }
}

impl Drop for Span {
    fn drop(&mut self) {
        if !self.ended {
            self.set("stillfail.cancelled", true);
            self.finish();
        }
    }
}

/// An OTLP attribute.
fn attribute(key: &str, value: Value) -> Value {
    let value = match value {
        Value::Bool(b) => json!({ "boolValue": b }),
        Value::Number(n) if n.is_i64() || n.is_u64() => json!({ "intValue": n.to_string() }),
        Value::Number(n) => json!({ "doubleValue": n.as_f64() }),
        Value::String(s) => json!({ "stringValue": s }),
        other => json!({ "stringValue": other.to_string() }),
    };
    json!({ "key": key, "value": value })
}

/// Collections whose next path segment is an id, whatever it looks like.
const COLLECTIONS: [&str; 10] = ["sessions", "threads", "connects", "profiles", "logins", "workspaces", "stations", "members", "enrollments", "accounts"];

/// A request path as a span shows it: no query, and ids as `:id`, so requests group by route and names stay out.
pub fn route(path: &str) -> String {
    let path = path.split(['?', '#']).next().unwrap_or("");
    let mut after_collection = false;
    let segments: Vec<&str> = path
        .split('/')
        .map(|segment| {
            let word = !segment.is_empty()
                && segment.len() <= 24
                && segment.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-' || b == b'_' || b == b'.')
                && segment.bytes().any(|b| b.is_ascii_lowercase());
            let id = !segment.is_empty() && (after_collection || !word);
            after_collection = !id && COLLECTIONS.contains(&segment);
            if id { ":id" } else { segment }
        })
        .collect();
    segments.join("/")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::{FakeHost, run};

    fn exported(bodies: &RefCell<Vec<Value>>) -> Vec<Value> {
        bodies.borrow().iter().flat_map(|b| b["resourceSpans"][0]["scopeSpans"][0]["spans"].as_array().cloned().unwrap_or_default()).collect()
    }

    fn capture(tracer: &Tracer) -> Rc<RefCell<Vec<Value>>> {
        let bodies: Rc<RefCell<Vec<Value>>> = Rc::default();
        let sink = bodies.clone();
        tracer.set_export(Rc::new(move |body: Vec<u8>| {
            sink.borrow_mut().push(serde_json::from_slice(&body).unwrap());
            async {}.boxed_local()
        }));
        bodies
    }

    #[test]
    fn routes_hide_ids_and_queries() {
        assert_eq!(route("/admin/api/threads/42/messages?before=9&limit=50"), "/admin/api/threads/:id/messages");
        assert_eq!(route("/admin/api/sessions/slack:T1:C1:1790000000.0001/live?from=3"), "/admin/api/sessions/:id/live");
        assert_eq!(route("/admin/api/sessions/abc/files?name=报告.pdf"), "/admin/api/sessions/:id/files");
        assert_eq!(route("/admin/api/profiles/cc/check"), "/admin/api/profiles/:id/check");
        assert_eq!(route("/v1/workspaces/01J8ZK4Q3M5N6P7R8S9T0V1W2X/stations/9f3a"), "/v1/workspaces/:id/stations/:id");
        assert_eq!(route("/v1/invitations/preview"), "/v1/invitations/preview");
        assert_eq!(route("/admin/api/events"), "/admin/api/events");
    }

    #[test]
    fn spans_nest_and_go_out_in_one_batch() {
        run(async {
            let host = FakeHost::new();
            host.speed_up(100);
            let tracer = Tracer::new(host.clone(), 1.0);
            let bodies = capture(&tracer);
            let mut root = tracer.root("chat.open", Kind::Internal);
            root.set("stillfail.station", "st");
            let context = root.context();
            // A future instrumented with the root makes its spans children of it, even after an await.
            let inner = tracer.clone();
            tracer
                .instrument(Some(context), async move {
                    tokio::task::yield_now().await;
                    let mut child = inner.span("GET /admin/api/threads", Kind::Client);
                    child.set("http.response.status_code", 200);
                    child.end();
                })
                .await;
            assert_eq!(tracer.current(), None);
            // Outside every trace a span is a root of its own.
            tracer.span("GET /admin/api/overview", Kind::Client).end();
            root.end();
            assert!(bodies.borrow().is_empty());
            tokio::time::sleep(std::time::Duration::from_millis(EXPORT_MS / 100 + 20)).await;
            tokio::task::yield_now().await;
            assert_eq!(bodies.borrow().len(), 1);
            assert_eq!(bodies.borrow()[0]["resourceSpans"][0]["resource"]["attributes"][0]["value"]["stringValue"], SERVICE);
            let spans = exported(&bodies);
            let names: Vec<&str> = spans.iter().map(|s| s["name"].as_str().unwrap()).collect();
            assert_eq!(names, ["GET /admin/api/threads", "GET /admin/api/overview", "chat.open"]);
            let (child, other, root) = (&spans[0], &spans[1], &spans[2]);
            assert_eq!(child["traceId"], root["traceId"]);
            assert_eq!(child["parentSpanId"], root["spanId"]);
            assert_ne!(other["traceId"], root["traceId"]);
            assert!(root.get("parentSpanId").is_none());
            assert_eq!(child["attributes"][0], json!({ "key": "http.response.status_code", "value": { "intValue": "200" } }));
            assert_eq!(root["attributes"][0], json!({ "key": "stillfail.station", "value": { "stringValue": "st" } }));
            let (start, end): (u64, u64) = (root["startTimeUnixNano"].as_str().unwrap().parse().unwrap(), root["endTimeUnixNano"].as_str().unwrap().parse().unwrap());
            assert!(end >= start && start > 1_700_000_000_000_000_000);
            assert_eq!(context.traceparent(), format!("00-{}-{}-01", root["traceId"].as_str().unwrap(), root["spanId"].as_str().unwrap()));
        });
    }

    #[test]
    fn nothing_is_recorded_when_off_and_a_dropped_span_is_cancelled() {
        run(async {
            let host = FakeHost::new();
            host.speed_up(100);
            let off = Tracer::new(host.clone(), 0.0);
            let bodies = capture(&off);
            let root = off.root("chat.send", Kind::Internal);
            // Not sampled: the traceparent still says so downstream.
            assert!(root.context().traceparent().ends_with("-00"));
            off.enter(Some(root.context()), || off.span("POST /admin/api/threads/1/messages", Kind::Client).end());
            root.end();
            tokio::time::sleep(std::time::Duration::from_millis(EXPORT_MS / 100 + 20)).await;
            assert!(bodies.borrow().is_empty());
            assert!(host.sleeps.borrow().is_empty());

            let on = Tracer::new(host.clone(), 1.0);
            let bodies = capture(&on);
            drop(on.root("chat.open", Kind::Internal));
            tokio::time::sleep(std::time::Duration::from_millis(EXPORT_MS / 100 + 20)).await;
            let spans = exported(&bodies);
            assert_eq!(spans[0]["attributes"][0], json!({ "key": "stillfail.cancelled", "value": { "boolValue": true } }));
        });
    }
}
