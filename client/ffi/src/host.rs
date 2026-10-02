//! The `Host` of a native app. It lives on the core thread (see lib.rs):
//! HTTP through reqwest, time and tasks on that thread's tokio runtime,
//! storage as files handed to a thread of their own so the core never waits
//! on the disk.

use std::cell::RefCell;
use std::collections::HashSet;
use std::panic::AssertUnwindSafe;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::mpsc;

use stillfail_core::host::{DbOp, DbRange, Host, HostError, HttpRequest, HttpResponse, SOCKET_PING, SOCKET_PING_MS, SocketFrames, StreamResponse};
use stillfail_core::{ClientId, CoreError, CoreMessage};
use stillfail_core::i18n::t;
use futures::future::LocalBoxFuture;
use futures::stream;
use futures::{FutureExt, StreamExt};
use tokio::sync::{mpsc::UnboundedSender, oneshot};
use tokio_tungstenite::Connector;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::{Error as WsError, Message};

use crate::{Command, CoreListener};

pub struct NativeHost {
    cloud_origin: String,
    /// A beta app's core (`Host::beta`).
    beta: bool,
    tls: Arc<rustls::ClientConfig>,
    /// Its pool of connections; replaced when they are taken for gone (`reset_connections`).
    http: RefCell<reqwest::Client>,
    storage: Storage,
    data_out: mpsc::Sender<(ClientId, CoreMessage)>,
    api_out: mpsc::Sender<(ClientId, CoreMessage)>,
    calls: RefCell<HashSet<(ClientId, u64)>>,
    /// Back to the core thread's loop: a task that panicked ends this core.
    commands: UnboundedSender<Command>,
    /// Zero of the monotonic clock.
    started: std::time::Instant,
}

impl NativeHost {
    pub fn new(data_dir: PathBuf, cloud_origin: String, beta: bool, listener: Arc<dyn CoreListener>, commands: UnboundedSender<Command>) -> NativeHost {
        let tls = Arc::new(tls_config());
        let http = RefCell::new(http_client(&tls));
        let data_out = output("stillfail-data-out", listener.clone(), commands.clone());
        let api_out = output("stillfail-api-out", listener, commands.clone());
        NativeHost { cloud_origin, beta, tls, http, storage: Storage::new(data_dir), data_out, api_out,
            calls: RefCell::new(HashSet::new()), commands, started: std::time::Instant::now() }
    }

    pub fn call_started(&self, client: ClientId, id: u64) { self.calls.borrow_mut().insert((client, id)); }
    pub fn client_left(&self, client: ClientId) { self.calls.borrow_mut().retain(|(c, _)| *c != client); }
}

/// Both serialization and the foreign callback can copy megabytes. Neither runs on the core event loop.
/// An API's progress and terminal reply use the same queue; topic values/deltas keep their own FIFO order.
fn output(name: &str, listener: Arc<dyn CoreListener>, commands: UnboundedSender<Command>) -> mpsc::Sender<(ClientId, CoreMessage)> {
    let (send, messages) = mpsc::channel();
    std::thread::Builder::new().name(name.into()).spawn(move || {
        for (client, message) in messages {
            let sent = std::panic::catch_unwind(AssertUnwindSafe(|| {
                let json = serde_json::to_string(&message).unwrap_or_else(|error| {
                    let id = message_id(&message);
                    serde_json::to_string(&CoreMessage::Error { id, error: CoreError::new("host", t!("core-misc.host.unsendable_ui", error = error)) }).expect("an error serializes")
                });
                listener.on_message(client, json);
            }));
            if let Err(panic) = sent { let _ = commands.send(Command::Fatal(panic_message(&*panic))); break; }
        }
    }).expect("core output thread");
    send
}

fn message_id(message: &CoreMessage) -> u64 {
    match message {
        CoreMessage::Ok { id, .. } | CoreMessage::Error { id, .. } | CoreMessage::Value { id, .. } | CoreMessage::Delta { id, .. } => *id,
    }
}

/// A client with a pool of its own. A phone that slept, or moved to another network, leaves the connections it had
/// dead with nothing said; HTTP/2 pings (answered within 5 s, or the connection is closed and what is on it fails)
/// and TCP keepalive find them out rather than a request waiting on one for the kernel's quarter of an hour.
fn http_client(tls: &rustls::ClientConfig) -> reqwest::Client {
    use std::time::Duration;
    reqwest::Client::builder()
        .tls_backend_preconfigured(tls.clone())
        .connect_timeout(Duration::from_secs(15))
        .pool_idle_timeout(Duration::from_secs(60))
        .tcp_keepalive(Duration::from_secs(30))
        .http2_keep_alive_interval(Duration::from_secs(20))
        .http2_keep_alive_timeout(Duration::from_secs(5))
        .http2_keep_alive_while_idle(true)
        .build()
        .expect("reqwest client")
}

/// The crypto provider is iroh's (ring); the roots Mozilla's, as iroh's own TLS
/// uses, so nothing needs the Android platform verifier's JNI setup.
fn tls_config() -> rustls::ClientConfig {
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let roots = rustls::RootCertStore { roots: webpki_roots::TLS_SERVER_ROOTS.to_vec() };
    rustls::ClientConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .expect("ring supports the default protocol versions")
        .with_root_certificates(roots)
        .with_no_client_auth()
}

/// Opens a WebSocket that only listens; resolves once it is open. `protocols`
/// are its subprotocols (still.fail cloud reads the token from one of them).
fn websocket(tls: Arc<rustls::ClientConfig>, url: String, protocols: Vec<String>) -> LocalBoxFuture<'static, Result<SocketFrames, HostError>> {
    Box::pin(async move {
        let mut request = url.as_str().into_client_request().map_err(ws_error)?;
        if !protocols.is_empty() {
            let value = protocols.join(", ").parse().map_err(|_| HostError(t!("core-misc.host.bad_subprotocol")))?;
            request.headers_mut().insert("sec-websocket-protocol", value);
        }
        let (socket, _) = tokio_tungstenite::connect_async_tls_with_config(request, None, false, Some(Connector::Rustls(tls))).await.map_err(ws_error)?;
        // Read as one stream (not split): reading is also what answers the server's pings. `ping` goes out every
        // SOCKET_PING_MS (host.rs), sent between reads.
        let every = std::time::Duration::from_millis(SOCKET_PING_MS);
        let frames = stream::unfold(Some((socket, tokio::time::Instant::now() + every)), move |state| async move {
            let (mut socket, mut ping_at) = state?;
            loop {
                let message = tokio::select! {
                    message = socket.next() => message,
                    _ = tokio::time::sleep_until(ping_at) => {
                        ping_at = tokio::time::Instant::now() + every;
                        if let Err(error) = futures::SinkExt::send(&mut socket, Message::text(SOCKET_PING)).await {
                            return Some((Err(ws_error(error)), None));
                        }
                        continue;
                    }
                };
                match message {
                    Some(Ok(Message::Text(text))) => return Some((Ok(text.as_str().to_owned()), Some((socket, ping_at)))),
                    Some(Ok(Message::Close(_))) | Some(Err(WsError::ConnectionClosed | WsError::AlreadyClosed)) | None => return None,
                    Some(Ok(_)) => {}
                    Some(Err(error)) => return Some((Err(ws_error(error)), None)),
                }
            }
        });
        Ok(frames.boxed_local())
    })
}

/// Looked at this often while a sleep runs (`sleep`).
const SLEEP_STEP: std::time::Duration = std::time::Duration::from_secs(2);

/// A sleep that counts the device's own sleep too. tokio's clock (Android's CLOCK_MONOTONIC, macOS's uptime) stands
/// still while the phone or the laptop is asleep, so a 10 s timeout begun before went on for as long as it slept after
/// (a link tried for 18 minutes: 2026-09-30); the wall clock does not. It ends at whichever comes first, so the wall
/// clock set back does not make it longer; set forward it ends early, as a sleep does now and then anyway.
async fn sleep(duration: std::time::Duration) {
    if duration <= SLEEP_STEP {
        return tokio::time::sleep(duration).await;
    }
    let (begun, end) = (std::time::SystemTime::now(), tokio::time::Instant::now() + duration);
    loop {
        let left = end.saturating_duration_since(tokio::time::Instant::now());
        if left.is_zero() || begun.elapsed().is_ok_and(|slept| slept >= duration) {
            return;
        }
        tokio::time::sleep(left.min(SLEEP_STEP)).await;
    }
}

fn ws_error(error: WsError) -> HostError {
    match error {
        WsError::Http(response) => HostError(format!("websocket refused ({})", response.status().as_u16())),
        error => HostError(format!("websocket: {error}")),
    }
}

fn http_error(error: reqwest::Error) -> HostError {
    // reqwest's Display leaves out the cause ("error sending request"); the chain says what failed.
    let mut message = error.to_string();
    let mut source = std::error::Error::source(&error);
    while let Some(cause) = source {
        message.push_str(": ");
        message.push_str(&cause.to_string());
        source = cause.source();
    }
    HostError(message)
}

fn build(http: &reqwest::Client, request: HttpRequest) -> Result<reqwest::RequestBuilder, HostError> {
    let method = reqwest::Method::from_bytes(request.method.as_bytes()).map_err(|e| HostError(e.to_string()))?;
    let mut builder = http.request(method, &request.url);
    for (name, value) in request.headers {
        builder = builder.header(name, value);
    }
    if let Some(body) = request.body {
        builder = builder.body(body);
    }
    Ok(builder)
}

fn headers(response: &reqwest::Response) -> Vec<(String, String)> {
    response.headers().iter().map(|(k, v)| (k.to_string(), String::from_utf8_lossy(v.as_bytes()).into_owned())).collect()
}

impl Host for NativeHost {
    fn cloud_origin(&self) -> String {
        self.cloud_origin.clone()
    }

    fn beta(&self) -> bool {
        self.beta
    }

    fn fetch(&self, request: HttpRequest) -> LocalBoxFuture<'static, Result<HttpResponse, HostError>> {
        let request = build(&self.http.borrow(), request);
        Box::pin(async move {
            let response = request?.send().await.map_err(http_error)?;
            let (status, headers) = (response.status().as_u16(), headers(&response));
            let body = response.bytes().await.map_err(http_error)?.to_vec();
            Ok(HttpResponse { status, headers, body })
        })
    }

    fn websocket(&self, url: String, protocols: Vec<String>) -> LocalBoxFuture<'static, Result<SocketFrames, HostError>> {
        websocket(self.tls.clone(), url, protocols)
    }

    fn reset_connections(&self) {
        // Requests already on the old pool keep it until they end (the core fails those it takes for gone).
        *self.http.borrow_mut() = http_client(&self.tls);
    }

    fn fetch_stream(&self, request: HttpRequest) -> LocalBoxFuture<'static, Result<StreamResponse, HostError>> {
        let request = build(&self.http.borrow(), request);
        Box::pin(async move {
            let response = request?.send().await.map_err(http_error)?;
            let (status, headers) = (response.status().as_u16(), headers(&response));
            // Dropping the stream drops the response, which closes the connection.
            let body = response.bytes_stream().map(|chunk| chunk.map(|c| c.to_vec()).map_err(http_error)).boxed_local();
            Ok(StreamResponse { status, headers, body })
        })
    }

    fn storage_get(&self, key: &str) -> LocalBoxFuture<'static, Result<Option<Vec<u8>>, HostError>> {
        let path = self.storage.path(key);
        self.storage.run(move || match std::fs::read(&path) {
            Ok(bytes) => Ok(Some(bytes)),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(io_error("core-misc.host.storage.read", error)),
        })
    }

    fn storage_set(&self, key: &str, value: Vec<u8>) -> LocalBoxFuture<'static, Result<(), HostError>> {
        let path = self.storage.path(key);
        self.storage.run(move || {
            // Written aside and renamed over: a crash leaves the old value or the new one, never half.
            let partial = path.with_extension("partial");
            std::fs::write(&partial, &value).map_err(|e| io_error("core-misc.host.storage.write", e))?;
            std::fs::File::open(&partial).and_then(|f| f.sync_all()).map_err(|e| io_error("core-misc.host.storage.write", e))?;
            std::fs::rename(&partial, &path).map_err(|e| io_error("core-misc.host.storage.write", e))
        })
    }

    fn db_read(&self, range: DbRange) -> LocalBoxFuture<'static, Result<Vec<(String, Vec<u8>)>, HostError>> {
        let db = self.storage.db.clone();
        self.storage.run(move || read_records(&db, range))
    }

    fn db_write(&self, ops: Vec<DbOp>) -> LocalBoxFuture<'static, Result<(), HostError>> {
        let db = self.storage.db.clone();
        self.storage.run(move || write_records(&db, ops))
    }

    fn storage_delete(&self, key: &str) -> LocalBoxFuture<'static, Result<(), HostError>> {
        let path = self.storage.path(key);
        self.storage.run(move || match std::fs::remove_file(&path) {
            Err(error) if error.kind() != std::io::ErrorKind::NotFound => Err(io_error("core-misc.host.storage.delete", error)),
            _ => Ok(()),
        })
    }

    fn now_ms(&self) -> f64 {
        let since = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
        since.as_secs_f64() * 1000.0
    }

    fn monotonic_ms(&self) -> f64 {
        self.started.elapsed().as_secs_f64() * 1000.0
    }

    fn utc_offset_min(&self, at_ms: f64) -> i32 {
        utc_offset_min(at_ms)
    }

    fn sleep(&self, ms: u64) -> LocalBoxFuture<'static, ()> {
        Box::pin(sleep(std::time::Duration::from_millis(ms)))
    }

    fn spawn(&self, task: LocalBoxFuture<'static, ()>) {
        let commands = self.commands.clone();
        tokio::task::spawn_local(async move {
            if let Err(panic) = AssertUnwindSafe(task).catch_unwind().await {
                let _ = commands.send(Command::Fatal(panic_message(&*panic)));
            }
        });
    }

    fn random_bytes(&self, buf: &mut [u8]) {
        getrandom::fill(buf).expect("the system's random source");
    }

    fn background(&self, task: Box<dyn FnOnce() + Send>) {
        tokio::task::spawn_blocking(task);
    }

    fn emit(&self, client: ClientId, message: CoreMessage) {
        let key = (client, message_id(&message));
        let mut calls = self.calls.borrow_mut();
        let api = calls.contains(&key);
        if matches!(&message, CoreMessage::Ok { .. } | CoreMessage::Error { .. }) { calls.remove(&key); }
        let queue = if api { &self.api_out } else { &self.data_out };
        let _ = queue.send((client, message));
    }
}

/// The viewer's time zone at `at_ms` from the C library, which on Android
/// follows the system's zone setting (and its changes) and knows its DST rules.
pub fn utc_offset_min(at_ms: f64) -> i32 {
    let at = (at_ms / 1000.0).floor() as libc::time_t;
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    // SAFETY: both pointers are valid for the call; localtime_r is the thread-safe variant.
    if unsafe { libc::localtime_r(&at, &mut tm) }.is_null() {
        return 0;
    }
    (tm.tm_gmtoff / 60) as i32
}

pub fn panic_message(panic: &(dyn std::any::Any + Send)) -> String {
    let text = panic.downcast_ref::<&str>().map(|s| s.to_string()).or_else(|| panic.downcast_ref::<String>().cloned());
    t!("core-misc.host.crashed", reason = text.unwrap_or_else(|| t!("core-misc.host.unknown_reason")))
}

fn io_error(key: &str, error: std::io::Error) -> HostError {
    HostError(t!(key, error = error))
}

type Job = Box<dyn FnOnce() + Send>;

/// Small values as files in the app's data directory, one per key. One thread
/// does every file operation in the order they were asked for, so a write is
/// never overtaken by an earlier one.
struct Storage {
    dir: PathBuf,
    jobs: mpsc::Sender<Job>,
    /// The core's database, `core.db` in the directory: opened by the first job that needs it.
    db: Arc<std::sync::Mutex<DbHandle>>,
}

/// The database connection once open, with where it is.
struct DbHandle {
    path: PathBuf,
    conn: Option<rusqlite::Connection>,
}

/// The connection, opened (and its table made) on first use.
fn open_db(handle: &mut DbHandle) -> Result<&mut rusqlite::Connection, HostError> {
    if handle.conn.is_none() {
        let conn = rusqlite::Connection::open(&handle.path).map_err(db_error)?;
        conn.execute_batch(
            "PRAGMA journal_mode = WAL;
             PRAGMA synchronous = NORMAL;
             CREATE TABLE IF NOT EXISTS records (tbl TEXT NOT NULL, key TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY (tbl, key)) WITHOUT ROWID;",
        )
        .map_err(db_error)?;
        handle.conn = Some(conn);
    }
    Ok(handle.conn.as_mut().expect("opened above"))
}

/// A table's records with keys in `[from, to)`, in key order.
fn read_records(db: &std::sync::Mutex<DbHandle>, range: DbRange) -> Result<Vec<(String, Vec<u8>)>, HostError> {
    let mut guard = db.lock().map_err(|_| HostError(t!("core-misc.host.db_unavailable")))?;
    let conn = open_db(&mut guard)?;
    let mut query = conn.prepare_cached("SELECT key, value FROM records WHERE tbl = ?1 AND key >= ?2 AND key < ?3 ORDER BY key").map_err(db_error)?;
    let rows = query
        .query_map(rusqlite::params![range.table, range.from, range.to], |row| Ok((row.get::<_, String>(0)?, row.get::<_, Vec<u8>>(1)?)))
        .map_err(db_error)?;
    rows.collect::<Result<Vec<_>, _>>().map_err(db_error)
}

/// A batch of changes, all or none.
fn write_records(db: &std::sync::Mutex<DbHandle>, ops: Vec<DbOp>) -> Result<(), HostError> {
    let mut guard = db.lock().map_err(|_| HostError(t!("core-misc.host.db_unavailable")))?;
    let conn = open_db(&mut guard)?;
    let tx = conn.transaction().map_err(db_error)?;
    for op in ops {
        match op {
            DbOp::Put { table, key, value } => {
                tx.execute("INSERT OR REPLACE INTO records (tbl, key, value) VALUES (?1, ?2, ?3)", rusqlite::params![table, key, value]).map_err(db_error)?;
            }
            DbOp::Delete { table, key } => {
                tx.execute("DELETE FROM records WHERE tbl = ?1 AND key = ?2", rusqlite::params![table, key]).map_err(db_error)?;
            }
        }
    }
    tx.commit().map_err(db_error)
}

fn db_error(error: rusqlite::Error) -> HostError {
    HostError(t!("core-misc.host.db_error", error = error))
}

impl Storage {
    fn new(dir: PathBuf) -> Storage {
        let (jobs, queue) = mpsc::channel::<Job>();
        std::thread::Builder::new()
            .name("stillfail-storage".into())
            .spawn(move || {
                for job in queue {
                    job();
                }
            })
            .expect("storage thread");
        let db = Arc::new(std::sync::Mutex::new(DbHandle { path: dir.join("core.db"), conn: None }));
        Storage { dir, jobs, db }
    }

    /// Keys may hold anything; file names only letters, digits, `-` and `_` (the rest is %XX).
    fn path(&self, key: &str) -> PathBuf {
        let mut name = String::new();
        for byte in key.bytes() {
            match byte {
                b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' => name.push(byte as char),
                _ => name.push_str(&format!("%{byte:02X}")),
            }
        }
        self.dir.join(name)
    }

    fn run<T: Send + 'static>(&self, job: impl FnOnce() -> Result<T, HostError> + Send + 'static) -> LocalBoxFuture<'static, Result<T, HostError>> {
        let (done, result) = oneshot::channel();
        let sent = self.jobs.send(Box::new(move || {
            let _ = done.send(job());
        }));
        Box::pin(async move {
            sent.map_err(|_| HostError(t!("core-misc.host.storage_closed")))?;
            result.await.map_err(|_| HostError(t!("core-misc.host.storage_closed")))?
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio_tungstenite::tungstenite::handshake::server::{Request, Response};

    #[test]
    fn the_database_keeps_records_across_opens() {
        let dir = tempfile::tempdir().unwrap();
        let handle = |dir: &std::path::Path| std::sync::Mutex::new(DbHandle { path: dir.join("core.db"), conn: None });
        let put = |table: &str, key: &str, value: &str| DbOp::Put { table: table.into(), key: key.into(), value: value.as_bytes().to_vec() };
        {
            let db = handle(dir.path());
            write_records(&db, vec![put("row", "s\u{1}a", "1"), put("row", "s\u{1}b", "2"), put("row", "t\u{1}a", "3"), put("thread", "s\u{1}a", "4")]).unwrap();
            write_records(&db, vec![DbOp::Delete { table: "row".into(), key: "s\u{1}b".into() }, put("row", "s\u{1}a", "5")]).unwrap();
        }
        let db = handle(dir.path());
        let found = read_records(&db, DbRange { table: "row".into(), from: "s\u{1}".into(), to: "s\u{2}".into() }).unwrap();
        assert_eq!(found, vec![("s\u{1}a".to_string(), b"5".to_vec())]);
    }

    #[test]
    fn a_websocket_hands_over_its_text_frames_until_it_closes() {
        let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
        tokio::task::LocalSet::new().block_on(&runtime, async {
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let port = listener.local_addr().unwrap().port();
            let server = tokio::spawn(async move {
                let (tcp, _) = listener.accept().await.unwrap();
                let mut asked = None;
                let mut socket = tokio_tungstenite::accept_hdr_async(tcp, |request: &Request, mut response: Response| {
                    asked = request.headers().get("sec-websocket-protocol").map(|v| v.to_str().unwrap().to_string());
                    response.headers_mut().insert("sec-websocket-protocol", "stillfail-events".parse().unwrap());
                    Ok(response)
                })
                .await
                .unwrap();
                use futures::SinkExt;
                for frame in [Message::text("one"), Message::Ping(vec![1].into()), Message::binary(vec![2]), Message::text("two")] {
                    socket.send(frame).await.unwrap();
                }
                socket.close(None).await.unwrap();
                asked
            });
            let protocols = vec!["stillfail-events".to_string(), "stillfail-token.abc".to_string()];
            let frames = websocket(Arc::new(tls_config()), format!("ws://127.0.0.1:{port}/v1/events"), protocols).await.unwrap();
            let frames: Vec<_> = frames.collect().await;
            assert_eq!(frames, vec![Ok("one".to_string()), Ok("two".to_string())]);
            assert_eq!(server.await.unwrap().as_deref(), Some("stillfail-events, stillfail-token.abc"));

            let refused = websocket(Arc::new(tls_config()), "ws://127.0.0.1:9/".into(), vec![]).await;
            assert!(refused.is_err());
        });
    }

    #[test]
    fn a_blocked_api_callback_does_not_hold_data_and_keeps_progress_order() {
        use std::time::Duration;
        use serde_json::{Value, json};
        struct SlowApi {
            entered: mpsc::Sender<()>,
            release: std::sync::Mutex<mpsc::Receiver<()>>,
            seen: mpsc::Sender<Value>,
        }
        impl CoreListener for SlowApi {
            fn on_message(&self, _: u64, text: String) {
                let message: Value = serde_json::from_str(&text).unwrap();
                if message["id"] == 7 && message.get("value").is_some() {
                    self.entered.send(()).unwrap();
                    self.release.lock().unwrap().recv_timeout(Duration::from_secs(5)).unwrap();
                }
                self.seen.send(message).unwrap();
            }
        }
        let (entered, entered_rx) = mpsc::channel();
        let (release, release_rx) = mpsc::channel();
        let (seen, seen_rx) = mpsc::channel();
        let (commands, _) = tokio::sync::mpsc::unbounded_channel();
        let data = tempfile::tempdir().unwrap();
        let host = NativeHost::new(data.path().into(), String::new(), false,
            Arc::new(SlowApi { entered, release: std::sync::Mutex::new(release_rx), seen }), commands);
        host.call_started(1, 7);
        host.emit(1, CoreMessage::Value { id: 7, value: json!("chunk") });
        entered_rx.recv_timeout(Duration::from_secs(2)).unwrap();
        host.emit(1, CoreMessage::Ok { id: 7, ok: json!("finished") });
        host.emit(1, CoreMessage::Value { id: 8, value: json!("data continues") });
        let data = seen_rx.recv_timeout(Duration::from_secs(2)).expect("data blocked by API callback");
        assert_eq!(data["id"], 8);
        release.send(()).unwrap();
        let progress = seen_rx.recv_timeout(Duration::from_secs(2)).unwrap();
        let done = seen_rx.recv_timeout(Duration::from_secs(2)).unwrap();
        assert_eq!(progress["value"], "chunk");
        assert_eq!(done["ok"], "finished");
    }

    #[test]
    fn pure_cpu_work_runs_outside_the_core_event_loop() {
        struct Quiet;
        impl CoreListener for Quiet { fn on_message(&self, _: u64, _: String) {} }
        let (commands, _) = tokio::sync::mpsc::unbounded_channel();
        let data = tempfile::tempdir().unwrap();
        let host = NativeHost::new(data.path().into(), String::new(), false, Arc::new(Quiet), commands);
        let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
        runtime.block_on(async {
            let core_thread = std::thread::current().id();
            let worker = stillfail_core::host::background(&host, || std::thread::current().id()).await.unwrap();
            assert_ne!(core_thread, worker);
        });
    }

    #[test]
    fn keys_become_safe_file_names() {
        let (commands, _) = tokio::sync::mpsc::unbounded_channel();
        struct Quiet;
        impl CoreListener for Quiet {
            fn on_message(&self, _: u64, _: String) {}
        }
        let host = NativeHost::new(PathBuf::from("/data"), String::new(), false, Arc::new(Quiet), commands);
        assert_eq!(host.storage.path("device"), PathBuf::from("/data/device"));
        assert_eq!(host.storage.path("../x.y"), PathBuf::from("/data/%2E%2E%2Fx%2Ey"));
    }
}
