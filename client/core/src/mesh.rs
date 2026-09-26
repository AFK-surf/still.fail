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
//!
//! Error codes: `grant_refused` when the station turned the grant down,
//! `mesh` for everything on the way (unreachable, stream broken).

use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::Arc;

use futures::future::{Either, LocalBoxFuture, Shared};
use futures::lock::Mutex;
use futures::{FutureExt, pin_mut};

use iroh::endpoint::{ConnectionError, QuicTransportConfig, RecvStream, SendStream, presets::Minimal};
use iroh::{Endpoint, EndpointAddr, PublicKey, RelayMode, RelayUrl, SecretKey};
use serde_json::{Value, json};

use crate::cloud::Grant;
use crate::error::{CoreError, Result};
use crate::host::Host;
use crate::trace::{Kind, Tracer};

pub const DEVICE_KEY: &str = "device";
pub const ALPN: &[u8] = b"ember/admin/1";
pub const RENEW_MS: u64 = 5 * 60_000;

/// A reply head is a line of JSON; anything longer is not a station talking.
const MAX_HEAD: usize = 64 * 1024;

/// Gets a fresh grant for a station, for this device's id (hex).
pub type GrantSource = Rc<dyn Fn(String) -> LocalBoxFuture<'static, Result<Grant>>>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequestHead {
    pub method: String,
    /// Path under the station's admin API, e.g. `/admin/api/overview`.
    pub path: String,
    pub headers: Vec<(String, String)>,
}

fn mesh_error(message: String) -> CoreError {
    CoreError::new("mesh", message)
}

/// An opening shared by everyone who asks for the same station meanwhile.
type Opening = Shared<LocalBoxFuture<'static, Result<Rc<Link>>>>;

pub struct Mesh {
    host: Rc<dyn Host>,
    tracer: Rc<Tracer>,
    relay_url: String,
    /// Replaced when `migrate` brings another device key.
    endpoint: RefCell<Endpoint>,
    links: RefCell<HashMap<String, Opening>>,
}

impl Mesh {
    /// Binds the endpoint with the stored device key (making and storing one the first time).
    /// An empty `relay_url` binds without a relay (direct addresses only: tests, a LAN).
    pub async fn new(host: Rc<dyn Host>, tracer: Rc<Tracer>, relay_url: &str) -> Result<Rc<Mesh>> {
        let stored = host.storage_get(DEVICE_KEY).await?;
        let secret: [u8; 32] = match stored.and_then(|bytes| bytes.try_into().ok()) {
            Some(secret) => secret,
            // None yet (or not a key at all): a new device.
            None => {
                let mut secret = [0u8; 32];
                host.random_bytes(&mut secret);
                host.storage_set(DEVICE_KEY, secret.to_vec()).await?;
                secret
            }
        };
        let endpoint = bind(&secret, relay_url).await?;
        Ok(Rc::new(Mesh { host, tracer, relay_url: relay_url.to_string(), endpoint: RefCell::new(endpoint), links: RefCell::default() }))
    }

    /// The device key's public half, hex: what grants name.
    pub fn device_id(&self) -> String {
        hex::encode(self.endpoint.borrow().id().as_bytes())
    }

    /// The iroh endpoint itself, e.g. to tell it where a station is when there is no relay.
    pub fn endpoint(&self) -> Endpoint {
        self.endpoint.borrow().clone()
    }

    /// The link to a station, opening it (or reopening a closed one) with a grant from `grants`.
    pub async fn link(&self, station_id: &str, grants: GrantSource) -> Result<Rc<Link>> {
        let existing = self.links.borrow().get(station_id).cloned();
        if let Some(opening) = existing {
            match opening.peek() {
                None => return opening.await,
                Some(Ok(link)) if link.usable() => return Ok(link.clone()),
                // Failed, closed, or its grant could not be renewed: open anew.
                Some(_) => {}
            }
        }
        // A span of the request that needed the link; the grant it asks ember cloud for is part of it.
        let mut span = self.tracer.span("mesh.connect", Kind::Internal);
        span.set("ember.station", station_id.to_string());
        let opening = self.tracer.instrument(Some(span.context()), open(self.host.clone(), self.endpoint(), station_id.to_string(), grants));
        let opening = async move {
            let link = opening.await;
            match &link {
                Ok(link) => {
                    if let Some(path) = link.path() {
                        span.set("ember.path", path);
                    }
                }
                Err(error) => {
                    span.fail();
                    span.set("error.type", error.code.clone());
                }
            }
            span.end();
            link
        }
        .boxed_local()
        .shared();
        self.links.borrow_mut().insert(station_id.to_string(), opening.clone());
        opening.await
    }

    /// Takes over the device key a page kept before the core existed (32 bytes).
    ///
    /// The page's key wins: it is stored whenever it differs from the stored
    /// one (which may be a key this core made before the page handed its own
    /// over), the endpoint is rebound with it and open links are closed (they
    /// reopen under the new id). The same key again changes nothing.
    pub async fn migrate(&self, secret: Vec<u8>) -> Result<()> {
        let secret: [u8; 32] = secret.try_into().map_err(|_| CoreError::invalid("设备密钥应为 32 字节"))?;
        if self.host.storage_get(DEVICE_KEY).await?.as_deref() == Some(&secret[..]) {
            return Ok(());
        }
        let endpoint = bind(&secret, &self.relay_url).await?;
        self.host.storage_set(DEVICE_KEY, secret.to_vec()).await?;
        let old = self.endpoint.replace(endpoint);
        let links: Vec<Opening> = self.links.borrow_mut().drain().map(|(_, opening)| opening).collect();
        for opening in links {
            if let Some(Ok(link)) = opening.peek() {
                link.conn.close(0u32.into(), b"device key replaced");
            }
        }
        self.host.spawn(async move { old.close().await }.boxed_local());
        Ok(())
    }
}

/// The endpoint for a device key. On wasm iroh has no IP transports, so this
/// is relay-only like mesh/web; natively it also binds UDP and goes direct
/// once the relay has helped both sides find each other.
async fn bind(secret: &[u8; 32], relay_url: &str) -> Result<Endpoint> {
    let relay_mode = if relay_url.is_empty() {
        RelayMode::Disabled
    } else {
        let relay: RelayUrl = relay_url.parse().map_err(|e| mesh_error(format!("中继地址不对：{e}")))?;
        RelayMode::Custom(relay.into())
    };
    Endpoint::builder(Minimal)
        .secret_key(SecretKey::from_bytes(secret))
        .relay_mode(relay_mode)
        .transport_config(transport())
        .bind()
        .await.map_err(|e| mesh_error(format!("无法启动本机的 mesh 端点：{e}")))
}

/// Through a relay a round trip is hundreds of milliseconds, and QUIC's default first window
/// (~14 KB) would spread a chat's first page over several of them. Starting at 256 KB sends
/// what a screen needs in one round trip; larger transfers still grow the window as usual.
/// The station does the same (mesh/station/src/main.rs).
pub const INITIAL_WINDOW: u64 = 256 * 1024;

pub fn transport() -> QuicTransportConfig {
    let mut cubic = noq_proto::congestion::CubicConfig::default();
    cubic.initial_window(INITIAL_WINDOW);
    QuicTransportConfig::builder().congestion_controller_factory(Arc::new(cubic)).build()
}

/// How long a connection waits for this device's relay link before trying anyway.
const ONLINE_WAIT_MS: u64 = 3_000;

/// Connects, presents the first grant, and starts renewing it.
async fn open(host: Rc<dyn Host>, endpoint: Endpoint, station_id: String, grants: GrantSource) -> Result<Rc<Link>> {
    let id: [u8; 32] = hex::decode(&station_id).ok().and_then(|b| b.try_into().ok()).ok_or_else(|| CoreError::invalid(format!("station id 不对：{station_id}")))?;
    let id = PublicKey::from_bytes(&id).map_err(|_| CoreError::invalid(format!("station id 不对：{station_id}")))?;
    let device = hex::encode(endpoint.id().as_bytes());
    let grant = grants(device.clone()).await?;
    // Our own relay link first (a fresh endpoint may not have it yet): packets sent before it is up are dropped,
    // and QUIC only resends after ~1 s and then ~2 s more. At most ONLINE_WAIT_MS, then try regardless.
    if !grant.relay_url.is_empty() {
        let online = endpoint.online().fuse();
        let waited = host.sleep(ONLINE_WAIT_MS).fuse();
        pin_mut!(online, waited);
        futures::select! { _ = online => {}, _ = waited => {} }
    }
    let mut addr = EndpointAddr::new(id);
    if !grant.relay_url.is_empty() {
        let relay: RelayUrl = grant.relay_url.parse().map_err(|e| mesh_error(format!("中继地址不对：{e}")))?;
        addr = addr.with_relay_url(relay);
    }
    let conn = endpoint.connect(addr, ALPN).await.map_err(|e| mesh_error(format!("连不上这台 station：{e}")))?;
    let (send, recv) = conn.open_bi().await.map_err(|e| mesh_error(format!("连不上这台 station：{e}")))?;
    let mut control = Control { send, recv, carry: Vec::new() };
    if let Err(error) = control.exchange(&grant.grant).await {
        conn.close(0u32.into(), b"grant refused");
        return Err(error);
    }
    let link = Rc::new(Link { conn, control: Mutex::new(control), renewal_failed: Cell::new(false) });
    host.spawn(renew(host.clone(), link.clone(), grants, device).boxed_local());
    Ok(link)
}

/// Presents a fresh grant every RENEW_MS until the link closes. If one cannot
/// be had or is refused, the link is left to run out its current grant and
/// the next `Mesh::link` opens another.
async fn renew(host: Rc<dyn Host>, link: Rc<Link>, grants: GrantSource, device: String) {
    loop {
        let wait = host.sleep(RENEW_MS);
        let closed = link.conn.closed();
        pin_mut!(closed);
        if let Either::Right(_) = futures::future::select(wait, closed).await {
            return;
        }
        let renewed = match grants(device.clone()).await {
            Ok(grant) => link.control.lock().await.exchange(&grant.grant).await.map(|_| ()),
            Err(error) => Err(error),
        };
        if renewed.is_err() {
            link.renewal_failed.set(true);
            return;
        }
    }
}

/// The control stream: grant lines out, answers back.
struct Control {
    send: SendStream,
    recv: RecvStream,
    carry: Vec<u8>,
}

impl Control {
    /// Sends a grant line and returns the station's answer; fails if it refused.
    async fn exchange(&mut self, grant: &str) -> Result<Value> {
        let line = format!("{}\n", json!({ "grant": grant }));
        self.send.write_all(line.as_bytes()).await.map_err(|e| mesh_error(format!("授权没送到 station：{e}")))?;
        let answer = read_line(&mut self.recv, &mut self.carry).await?.ok_or_else(|| mesh_error("station 关闭了授权通道".into()))?;
        let answer: Value = serde_json::from_str(&answer).map_err(|e| mesh_error(format!("station 的授权答复看不懂：{e}")))?;
        if let Some(error) = answer.get("error") {
            let reason = error.as_str().map(str::to_string).unwrap_or_else(|| error.to_string());
            return Err(CoreError::new("grant_refused", format!("station 拒绝了授权：{reason}")));
        }
        Ok(answer)
    }
}

/// Reads one newline-terminated line; whatever followed stays in `carry`.
async fn read_line(recv: &mut RecvStream, carry: &mut Vec<u8>) -> Result<Option<String>> {
    loop {
        if let Some(i) = carry.iter().position(|&b| b == b'\n') {
            let line: Vec<u8> = carry.drain(..=i).collect();
            return Ok(Some(String::from_utf8_lossy(&line[..line.len() - 1]).into_owned()));
        }
        if carry.len() > MAX_HEAD {
            return Err(mesh_error("station 发来的头部太长".into()));
        }
        let mut buf = [0u8; 8192];
        match recv.read(&mut buf).await.map_err(|e| mesh_error(format!("读取 station 的回复失败：{e}")))? {
            Some(n) => carry.extend_from_slice(&buf[..n]),
            None if carry.is_empty() => return Ok(None),
            None => return Err(mesh_error("station 的回复在一行中间断了".into())),
        }
    }
}

pub struct Link {
    conn: iroh::endpoint::Connection,
    control: Mutex<Control>,
    renewal_failed: Cell<bool>,
}

impl Link {
    /// One request on its own stream.
    pub async fn request(&self, head: RequestHead, body: Vec<u8>) -> Result<Reply> {
        let sent = |e: &dyn std::fmt::Display| mesh_error(format!("请求没送到 station：{e}"));
        let (mut send, mut recv) = self.conn.open_bi().await.map_err(|e| sent(&e))?;
        let headers: serde_json::Map<String, Value> = head.headers.into_iter().map(|(k, v)| (k, Value::String(v))).collect();
        let line = format!("{}\n", json!({ "method": head.method, "path": head.path, "headers": headers }));
        send.write_all(line.as_bytes()).await.map_err(|e| sent(&e))?;
        if !body.is_empty() {
            send.write_all(&body).await.map_err(|e| sent(&e))?;
        }
        send.finish().map_err(|e| sent(&e))?;
        let mut carry = Vec::new();
        let line = read_line(&mut recv, &mut carry).await?.ok_or_else(|| mesh_error("station 没有回应".into()))?;
        let reply: Value = serde_json::from_str(&line).map_err(|e| mesh_error(format!("station 的回复看不懂：{e}")))?;
        let status = reply["status"].as_u64().and_then(|s| u16::try_from(s).ok()).ok_or_else(|| mesh_error("station 的回复没有状态码".into()))?;
        let headers = match &reply["headers"] {
            Value::Object(map) => map.iter().map(|(k, v)| (k.clone(), v.as_str().map(str::to_string).unwrap_or_else(|| v.to_string()))).collect(),
            _ => Vec::new(),
        };
        Ok(Reply { status, headers, recv, carry, done: false })
    }

    /// Why the link closed, if it did.
    pub fn closed(&self) -> Option<String> {
        self.conn.close_reason().map(|reason| close_message(&reason))
    }

    /// Closes the connection now (its streams end with it).
    pub fn close(&self) {
        self.conn.close(0u32.into(), b"closed");
    }

    /// How the connection runs now: `relay`, or `direct` once hole punching found a way.
    pub fn path(&self) -> Option<&'static str> {
        self.conn.paths().iter().find(|p| p.is_selected()).map(|p| if p.is_relay() { "relay" } else { "direct" })
    }

    /// Open, and its grant still being renewed.
    fn usable(&self) -> bool {
        self.conn.close_reason().is_none() && !self.renewal_failed.get()
    }
}

/// In words, with the station's own reasons (mesh/station) spelled out.
fn close_message(reason: &ConnectionError) -> String {
    match reason {
        ConnectionError::ApplicationClosed(close) => match &close.reason[..] {
            b"grant_refused" => "station 拒绝了授权".into(),
            b"grant_expired" => "授权已过期".into(),
            b"station_removed" => "这台 station 已被移出 workspace".into(),
            other => format!("station 断开了连接：{}", String::from_utf8_lossy(other)),
        },
        ConnectionError::LocallyClosed => "连接已关闭".into(),
        ConnectionError::TimedOut => "连接超时".into(),
        other => format!("连接断开：{other}"),
    }
}

pub struct Reply {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    recv: RecvStream,
    /// Body bytes that came with the head line.
    carry: Vec<u8>,
    done: bool,
}

impl Reply {
    /// The next chunk of the body; None at its end.
    pub async fn next(&mut self) -> Option<Result<Vec<u8>>> {
        if !self.carry.is_empty() {
            return Some(Ok(std::mem::take(&mut self.carry)));
        }
        if self.done {
            return None;
        }
        let mut buf = vec![0u8; 32 * 1024];
        match self.recv.read(&mut buf).await {
            Ok(Some(n)) => {
                buf.truncate(n);
                Some(Ok(buf))
            }
            Ok(None) => {
                self.done = true;
                None
            }
            Err(e) => {
                self.done = true;
                Some(Err(mesh_error(format!("读取 station 的回复失败：{e}"))))
            }
        }
    }

    /// The rest of the body.
    pub async fn body(mut self) -> Result<Vec<u8>> {
        let mut body = Vec::new();
        while let Some(chunk) = self.next().await {
            body.extend_from_slice(&chunk?);
        }
        Ok(body)
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use crate::host::{HostError, HttpRequest, HttpResponse, StreamResponse};
    use crate::protocol::{ClientId, CoreMessage};
    use crate::testing::FakeHost;
    use iroh::address_lookup::MemoryLookup;
    use iroh::endpoint::Connection;
    use std::time::Duration;

    /// FakeHost, but the renewal wait is short so tests see renewals.
    struct QuickHost(Rc<FakeHost>);

    impl Host for QuickHost {
        fn cloud_origin(&self) -> String {
            self.0.cloud_origin()
        }
        fn fetch(&self, request: HttpRequest) -> LocalBoxFuture<'static, std::result::Result<HttpResponse, HostError>> {
            self.0.fetch(request)
        }
        fn fetch_stream(&self, request: HttpRequest) -> LocalBoxFuture<'static, std::result::Result<StreamResponse, HostError>> {
            self.0.fetch_stream(request)
        }
        fn websocket(&self, url: String, protocols: Vec<String>) -> LocalBoxFuture<'static, std::result::Result<crate::host::SocketFrames, HostError>> {
            self.0.websocket(url, protocols)
        }
        fn storage_get(&self, key: &str) -> LocalBoxFuture<'static, std::result::Result<Option<Vec<u8>>, HostError>> {
            self.0.storage_get(key)
        }
        fn storage_set(&self, key: &str, value: Vec<u8>) -> LocalBoxFuture<'static, std::result::Result<(), HostError>> {
            self.0.storage_set(key, value)
        }
        fn storage_delete(&self, key: &str) -> LocalBoxFuture<'static, std::result::Result<(), HostError>> {
            self.0.storage_delete(key)
        }
        fn now_ms(&self) -> f64 {
            self.0.now_ms()
        }
        fn utc_offset_min(&self, at_ms: f64) -> i32 {
            self.0.utc_offset_min(at_ms)
        }
        fn sleep(&self, ms: u64) -> LocalBoxFuture<'static, ()> {
            self.0.sleep(if ms == RENEW_MS { 150 } else { ms })
        }
        fn spawn(&self, task: LocalBoxFuture<'static, ()>) {
            self.0.spawn(task)
        }
        fn random_bytes(&self, buf: &mut [u8]) {
            self.0.random_bytes(buf)
        }
        fn emit(&self, client: ClientId, message: CoreMessage) {
            self.0.emit(client, message)
        }
    }

    /// iroh needs tokio's IO driver, which `testing::run` leaves off.
    fn run<F: std::future::Future<Output = ()>>(body: F) {
        let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
        tokio::task::LocalSet::new().block_on(&runtime, body);
    }

    /// A station on localhost: accepts grants starting with "ok", echoes requests.
    struct Station {
        endpoint: Endpoint,
        grants: Rc<RefCell<Vec<String>>>,
        conns: Rc<RefCell<Vec<Connection>>>,
    }

    impl Station {
        async fn start() -> Station {
            let endpoint = Endpoint::builder(Minimal)
                .alpns(vec![ALPN.to_vec()])
                .relay_mode(RelayMode::Disabled)
                .bind_addr("127.0.0.1:0".parse::<std::net::SocketAddr>().unwrap())
                .unwrap()
                .bind()
                .await
                .unwrap();
            let station = Station { endpoint: endpoint.clone(), grants: Rc::default(), conns: Rc::default() };
            let (grants, conns) = (station.grants.clone(), station.conns.clone());
            tokio::task::spawn_local(async move {
                while let Some(incoming) = endpoint.accept().await {
                    let Ok(conn) = incoming.await else { continue };
                    conns.borrow_mut().push(conn.clone());
                    tokio::task::spawn_local(serve(conn, grants.clone()));
                }
            });
            station
        }

        fn id(&self) -> String {
            hex::encode(self.endpoint.id().as_bytes())
        }

        fn addr(&self) -> EndpointAddr {
            let ip = *self.endpoint.bound_sockets().iter().find(|a| a.ip().is_loopback()).unwrap();
            EndpointAddr::new(self.endpoint.id()).with_ip_addr(ip)
        }
    }

    async fn write_line(send: &mut SendStream, value: &Value) {
        send.write_all(format!("{value}\n").as_bytes()).await.unwrap();
    }

    async fn serve(conn: Connection, grants: Rc<RefCell<Vec<String>>>) {
        let Ok((mut send, mut recv)) = conn.accept_bi().await else { return };
        let mut carry = Vec::new();
        let answer = |line: &str, grants: &Rc<RefCell<Vec<String>>>| {
            let grant = serde_json::from_str::<Value>(line).unwrap()["grant"].as_str().unwrap().to_string();
            grants.borrow_mut().push(grant.clone());
            if grant.starts_with("ok") { json!({ "ok": true, "station": "测试" }) } else { json!({ "error": "grant signature invalid" }) }
        };
        let first = read_line(&mut recv, &mut carry).await.unwrap().unwrap();
        let reply = answer(&first, &grants);
        write_line(&mut send, &reply).await;
        if reply.get("error").is_some() {
            send.finish().ok();
            tokio::time::sleep(Duration::from_millis(200)).await;
            conn.close(1u32.into(), b"grant_refused");
            return;
        }
        let renewals = grants.clone();
        tokio::task::spawn_local(async move {
            while let Ok(Some(line)) = read_line(&mut recv, &mut carry).await {
                let reply = answer(&line, &renewals);
                write_line(&mut send, &reply).await;
            }
        });
        while let Ok((mut send, mut recv)) = conn.accept_bi().await {
            tokio::task::spawn_local(async move {
                let mut carry = Vec::new();
                let head = read_line(&mut recv, &mut carry).await.unwrap().unwrap();
                let mut body = carry;
                let mut buf = [0u8; 4096];
                while let Some(n) = recv.read(&mut buf).await.unwrap() {
                    body.extend_from_slice(&buf[..n]);
                }
                let head: Value = serde_json::from_str(&head).unwrap();
                write_line(&mut send, &json!({ "status": 200, "headers": { "content-type": "text/event-stream", "x-method": head["method"] } })).await;
                send.write_all(format!("{}|{}", head, String::from_utf8_lossy(&body)).as_bytes()).await.unwrap();
                // Then a stream that trickles, like /events.
                for part in ["|one", "|two", "|three"] {
                    tokio::time::sleep(Duration::from_millis(100)).await;
                    send.write_all(part.as_bytes()).await.unwrap();
                }
                send.finish().unwrap();
            });
        }
    }

    /// Grants "<prefix>-1", "<prefix>-2", … and counts them.
    fn grants(prefix: &'static str, count: Rc<Cell<u32>>) -> GrantSource {
        Rc::new(move |device: String| {
            assert_eq!(device.len(), 64);
            count.set(count.get() + 1);
            let grant = Grant { grant: format!("{prefix}-{}", count.get()), expires_at: 0.0, station: String::new(), station_name: String::new(), relay_url: String::new() };
            async move { Ok(grant) }.boxed_local()
        })
    }

    async fn setup(host: Rc<dyn Host>) -> (Rc<Mesh>, Station) {
        let station = Station::start().await;
        let mesh = Mesh::new(host.clone(), Tracer::new(host, 1.0), "").await.unwrap();
        mesh.endpoint().address_lookup().unwrap().add(MemoryLookup::from_endpoint_info([station.addr()]));
        (mesh, station)
    }

    fn head(path: &str) -> RequestHead {
        RequestHead { method: "POST".into(), path: path.into(), headers: vec![("content-type".into(), "application/json".into())] }
    }

    #[test]
    fn opens_requests_and_streams_the_reply() {
        run(async {
            let host = FakeHost::new();
            let (mesh, station) = setup(host.clone()).await;
            assert_eq!(host.stored(DEVICE_KEY).map(|k| k.len()), Some(32));
            let link = mesh.link(&station.id(), grants("ok", Rc::default())).await.unwrap();
            assert_eq!(*station.grants.borrow(), vec!["ok-1".to_string()]);

            let mut reply = link.request(head("/admin/api/sessions"), b"{\"a\":1}".to_vec()).await.unwrap();
            assert_eq!(reply.status, 200);
            assert!(reply.headers.contains(&("content-type".into(), "text/event-stream".into())));
            assert!(reply.headers.contains(&("x-method".into(), "POST".into())));
            let first = String::from_utf8(reply.next().await.unwrap().unwrap()).unwrap();
            let echoed: Value = serde_json::from_str(first.split('|').next().unwrap()).unwrap();
            assert_eq!(echoed, json!({ "method": "POST", "path": "/admin/api/sessions", "headers": { "content-type": "application/json" } }));
            // The first chunk comes before the stream ends.
            assert_eq!(first.split('|').nth(1), Some("{\"a\":1}"));
            assert!(!first.contains("three"));
            let rest = String::from_utf8(reply.body().await.unwrap()).unwrap();
            assert!(rest.ends_with("|one|two|three"), "{rest}");
            assert_eq!(link.closed(), None);
        });
    }

    #[test]
    fn refused_grant_fails_with_a_reason() {
        run(async {
            let (mesh, station) = setup(FakeHost::new()).await;
            let count = Rc::new(Cell::new(0));
            let error = mesh.link(&station.id(), grants("bad", count.clone())).await.err().unwrap();
            assert_eq!(error.code, "grant_refused");
            assert!(error.message.contains("station 拒绝了授权"), "{}", error.message);
            // A failed opening is not kept: the next call tries again.
            assert!(mesh.link(&station.id(), grants("bad", count.clone())).await.is_err());
            assert_eq!(count.get(), 2);
        });
    }

    #[test]
    fn reuses_the_open_link_and_shares_an_opening() {
        run(async {
            let (mesh, station) = setup(FakeHost::new()).await;
            let count = Rc::new(Cell::new(0));
            let id = station.id();
            let (a, b) = futures::join!(mesh.link(&id, grants("ok", count.clone())), mesh.link(&id, grants("ok", count.clone())));
            let (a, b) = (a.unwrap(), b.unwrap());
            assert!(Rc::ptr_eq(&a, &b));
            let c = mesh.link(&id, grants("ok", count.clone())).await.unwrap();
            assert!(Rc::ptr_eq(&a, &c));
            assert_eq!(count.get(), 1);
            assert_eq!(station.conns.borrow().len(), 1);
        });
    }

    #[test]
    fn reopens_a_closed_link_with_a_fresh_grant() {
        run(async {
            let (mesh, station) = setup(FakeHost::new()).await;
            let count = Rc::new(Cell::new(0));
            let first = mesh.link(&station.id(), grants("ok", count.clone())).await.unwrap();
            station.conns.borrow()[0].close(3u32.into(), b"grant_expired");
            for _ in 0..100 {
                if first.closed().is_some() {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
            assert_eq!(first.closed().as_deref(), Some("授权已过期"));
            let second = mesh.link(&station.id(), grants("ok", count.clone())).await.unwrap();
            assert!(!Rc::ptr_eq(&first, &second));
            assert_eq!(*station.grants.borrow(), vec!["ok-1".to_string(), "ok-2".to_string()]);
            let reply = second.request(head("/admin/api/overview"), Vec::new()).await.unwrap();
            assert_eq!(reply.status, 200);
            assert!(reply.body().await.is_ok());
        });
    }

    #[test]
    fn renews_the_grant_until_the_link_closes() {
        run(async {
            let (mesh, station) = setup(Rc::new(QuickHost(FakeHost::new()))).await;
            let count = Rc::new(Cell::new(0));
            let link = mesh.link(&station.id(), grants("ok", count.clone())).await.unwrap();
            tokio::time::sleep(Duration::from_millis(400)).await;
            let seen = station.grants.borrow().clone();
            assert!(seen.len() >= 3, "{seen:?}");
            assert_eq!(seen[..3], ["ok-1", "ok-2", "ok-3"]);
            // Renewing kept the same link.
            assert!(Rc::ptr_eq(&link, &mesh.link(&station.id(), grants("ok", count.clone())).await.unwrap()));

            link.close();
            let asked = count.get();
            tokio::time::sleep(Duration::from_millis(400)).await;
            assert_eq!(count.get(), asked);
            assert_eq!(link.closed().as_deref(), Some("连接已关闭"));
        });
    }

    #[test]
    fn a_refused_renewal_makes_the_next_link_reopen() {
        run(async {
            let (mesh, station) = setup(Rc::new(QuickHost(FakeHost::new()))).await;
            let refuse_later: GrantSource = {
                let count = Rc::new(Cell::new(0));
                Rc::new(move |_device: String| {
                    count.set(count.get() + 1);
                    let grant = Grant { grant: if count.get() == 1 { "ok".into() } else { "revoked".into() }, expires_at: 0.0, station: String::new(), station_name: String::new(), relay_url: String::new() };
                    async move { Ok(grant) }.boxed_local()
                })
            };
            let first = mesh.link(&station.id(), refuse_later).await.unwrap();
            tokio::time::sleep(Duration::from_millis(300)).await;
            let second = mesh.link(&station.id(), grants("ok", Rc::default())).await.unwrap();
            assert!(!Rc::ptr_eq(&first, &second));
        });
    }

    #[test]
    fn keeps_the_device_key_and_migrates_to_the_pages() {
        run(async {
            let host = FakeHost::new();
            let first = Mesh::new(host.clone(), Tracer::new(host.clone(), 1.0), "").await.unwrap();
            let again = Mesh::new(host.clone(), Tracer::new(host.clone(), 1.0), "").await.unwrap();
            assert_eq!(first.device_id(), again.device_id());

            let page = [7u8; 32];
            first.migrate(page.to_vec()).await.unwrap();
            assert_eq!(host.stored(DEVICE_KEY), Some(page.to_vec()));
            assert_eq!(first.device_id(), hex::encode(SecretKey::from_bytes(&page).public().as_bytes()));
            assert_ne!(first.device_id(), again.device_id());
            first.migrate(page.to_vec()).await.unwrap();
            assert_eq!(first.migrate(vec![1, 2, 3]).await.err().unwrap().code, "invalid_params");
        });
    }
}
