//! The native shell of the core in TypeScript on Android (client/core-ts `hosts/bridge.ts`; apps/android/core runs it
//! in Hermes from C++): everything the core asks of its host that a JS engine has not, done on tokio's threads and on
//! a thread for the disk, and answered through a C callback. What it does is what the Rust core's native host (client/ffi) did (reqwest,
//! tokio-tungstenite, a file per storage key in the data directory, TCP to adbd) and what the station's addon does for
//! Node (iroh), so a phone moving from the Rust core keeps its sign-in. Each signed-in account's database is SQLite,
//! `databases/<name>.db` (beside the storage keys' files: `accounts` is one), used synchronously by the core's thread
//! (`sql.*`); the former `core.db` is only read, once.
//!
//! Operations are named and take JSON and maybe bytes; bridge.ts lists them. `sf_shell_call` answers later through
//! `complete(ctx, id, json, error, bytes)` from any thread; `sf_shell_call_sync` answers at once.

use std::collections::HashMap;
use std::ffi::{CStr, c_char, c_void};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, mpsc};

use futures::{SinkExt, StreamExt};
use iroh::endpoint::{Connection, QuicTransportConfig, RecvStream, SendStream, presets::Minimal};
use iroh::{Endpoint, EndpointAddr, EndpointId, RelayMode, RelayUrl, SecretKey, Watcher};
use serde_json::{Value, json};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_tungstenite::Connector;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::{Error as WsError, Message};

const MDNS_SERVICE: &str = "stillfail";
const FORMER_MDNS_SERVICE: &str = "ember";

/// `complete(ctx, id, json, json_len, error, error_len, bytes, bytes_len, has_bytes)`: an operation's answer, its JSON
/// (when it succeeded) or its error, and its bytes if it has any. Called on any thread.
pub type Complete = extern "C" fn(*mut c_void, u64, *const u8, usize, *const u8, usize, *const u8, usize, u8);

struct Ctx(*mut c_void);
// SAFETY: the engine's context is made to be told from any thread (the C++ side queues what it is given).
unsafe impl Send for Ctx {}
unsafe impl Sync for Ctx {}

/// An answer: JSON, and bytes where the operation has them.
struct Answer {
    json: Value,
    bytes: Option<Vec<u8>>,
}

impl Answer {
    fn json(json: Value) -> Answer {
        Answer { json, bytes: None }
    }
    fn bytes(json: Value, bytes: Vec<u8>) -> Answer {
        Answer { json, bytes: Some(bytes) }
    }
}

type Done = Result<Answer, String>;

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

/// The two halves of an iroh stream, and the reads waiting on it: a reset wakes them first (as the addon's).
struct Halves {
    send: tokio::sync::Mutex<Option<SendStream>>,
    recv: tokio::sync::Mutex<Option<RecvStream>>,
    reset: tokio::sync::watch::Sender<bool>,
    /// Read to its end; finished (or no sending half). Both: the handle goes.
    ended: std::sync::atomic::AtomicBool,
    finished: std::sync::atomic::AtomicBool,
}

#[derive(Clone)]
enum Handle {
    Response(Arc<tokio::sync::Mutex<reqwest::Response>>),
    Ws { incoming: Arc<tokio::sync::Mutex<tokio::sync::mpsc::UnboundedReceiver<Result<String, String>>>>, outgoing: tokio::sync::mpsc::UnboundedSender<String> },
    Tcp { read: Arc<tokio::sync::Mutex<tokio::net::tcp::OwnedReadHalf>>, write: Arc<tokio::sync::Mutex<tokio::net::tcp::OwnedWriteHalf>> },
    Endpoint(Endpoint),
    Conn(Connection),
    IStream(Arc<Halves>),
}

type Job = Box<dyn FnOnce() + Send>;

struct Inner {
    complete: Complete,
    ctx: Ctx,
    dir: PathBuf,
    /// One thread does every file and database job, in the order they were asked for (as the Rust core's did).
    disk: Mutex<mpsc::Sender<Job>>,
    db: Arc<Mutex<DbHandle>>,
    tls: Arc<rustls::ClientConfig>,
    http: Mutex<reqwest::Client>,
    handles: Mutex<HashMap<u64, Handle>>,
    next: AtomicU64,
    /// The accounts' databases open, by id, with their files.
    sqls: Mutex<HashMap<u64, (Option<PathBuf>, rusqlite::Connection)>>,
}

pub struct Shell {
    runtime: tokio::runtime::Runtime,
    inner: Arc<Inner>,
}

/// The connection to `core.db`, opened on first use.
struct DbHandle {
    path: PathBuf,
    conn: Option<rusqlite::Connection>,
}

fn open_db(handle: &mut DbHandle) -> Result<&mut rusqlite::Connection, String> {
    if handle.conn.is_none() {
        let conn = rusqlite::Connection::open(&handle.path).map_err(err)?;
        conn.execute_batch(
            "PRAGMA journal_mode = WAL;
             PRAGMA synchronous = NORMAL;
             CREATE TABLE IF NOT EXISTS records (tbl TEXT NOT NULL, key TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY (tbl, key)) WITHOUT ROWID;",
        )
        .map_err(err)?;
        handle.conn = Some(conn);
    }
    Ok(handle.conn.as_mut().expect("opened above"))
}

/// A statement's parameters as SQLite takes them: numbers (whole ones as integers), text, null; bytes as an array.
fn sql_params(a: &Value) -> Vec<rusqlite::types::Value> {
    use rusqlite::types::Value as V;
    a.get("params")
        .and_then(Value::as_array)
        .map(|list| {
            list.iter()
                .map(|v| match v {
                    Value::Null => V::Null,
                    Value::Bool(b) => V::Integer(i64::from(*b)),
                    Value::Number(n) => n.as_i64().map(V::Integer).unwrap_or_else(|| V::Real(n.as_f64().unwrap_or(0.0))),
                    Value::String(s) => V::Text(s.clone()),
                    Value::Array(bytes) => V::Blob(bytes.iter().map(|b| b.as_u64().unwrap_or(0) as u8).collect()),
                    Value::Object(_) => V::Text(v.to_string()),
                })
                .collect()
        })
        .unwrap_or_default()
}

fn tls_config() -> rustls::ClientConfig {
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let roots = rustls::RootCertStore { roots: webpki_roots::TLS_SERVER_ROOTS.to_vec() };
    rustls::ClientConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .expect("ring supports the default protocol versions")
        .with_root_certificates(roots)
        .with_no_client_auth()
}

/// As the Rust core's native host had it: HTTP/2 pings and TCP keepalive find connections a sleep or a new network left dead.
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
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .expect("reqwest client")
}

fn http_error(error: reqwest::Error) -> String {
    let mut message = error.to_string();
    let mut source = std::error::Error::source(&error);
    while let Some(cause) = source {
        message.push_str(": ");
        message.push_str(&cause.to_string());
        source = cause.source();
    }
    message
}

fn ws_error(error: WsError) -> String {
    match error {
        WsError::Http(response) => format!("websocket refused ({})", response.status().as_u16()),
        error => format!("websocket: {error}"),
    }
}

/// File names hold only letters, digits, `-` and `_`; the rest is %XX (as the Rust core had them).
fn storage_path(dir: &std::path::Path, key: &str) -> PathBuf {
    let mut name = String::new();
    for byte in key.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' => name.push(byte as char),
            _ => name.push_str(&format!("%{byte:02X}")),
        }
    }
    dir.join(name)
}

fn headers_of(response: &reqwest::Response) -> Value {
    Value::Array(response.headers().iter().map(|(k, v)| json!([k.as_str(), String::from_utf8_lossy(v.as_bytes())])).collect())
}

fn str_of<'a>(v: &'a Value, k: &str) -> Result<&'a str, String> {
    v.get(k).and_then(Value::as_str).ok_or_else(|| format!("missing {k}"))
}

fn id_of(v: &Value) -> Result<u64, String> {
    v.get("id").and_then(Value::as_u64).ok_or_else(|| "missing id".to_string())
}

fn relay_url(url: &str) -> Result<RelayUrl, String> {
    url.parse().map_err(err)
}

fn endpoint_addr(addr: &Value) -> Result<EndpointAddr, String> {
    let id = str_of(addr, "id")?;
    let bytes: [u8; 32] = hex::decode(id).map_err(err)?.try_into().map_err(|_| "the id is not 32 bytes".to_string())?;
    let mut out = EndpointAddr::new(EndpointId::from_bytes(&bytes).map_err(err)?);
    for url in addr.get("relays").and_then(Value::as_array).into_iter().flatten() {
        out = out.with_relay_url(relay_url(url.as_str().unwrap_or_default())?);
    }
    for ip in addr.get("ips").and_then(Value::as_array).into_iter().flatten() {
        out = out.with_ip_addr(ip.as_str().unwrap_or_default().parse::<std::net::SocketAddr>().map_err(err)?);
    }
    Ok(out)
}

fn close_info(error: &iroh::endpoint::ConnectionError) -> Value {
    use iroh::endpoint::ConnectionError;
    match error {
        ConnectionError::ApplicationClosed(close) => json!({ "kind": "application", "reason": String::from_utf8_lossy(&close.reason) }),
        ConnectionError::LocallyClosed => json!({ "kind": "local", "reason": "" }),
        ConnectionError::TimedOut => json!({ "kind": "timeout", "reason": "" }),
        other => json!({ "kind": "other", "reason": other.to_string() }),
    }
}

impl Inner {
    fn keep(&self, handle: Handle) -> u64 {
        let id = self.next.fetch_add(1, Ordering::Relaxed);
        self.handles.lock().unwrap().insert(id, handle);
        id
    }

    fn handle(&self, id: u64) -> Result<Handle, String> {
        self.handles.lock().unwrap().get(&id).cloned().ok_or_else(|| format!("no handle {id}"))
    }

    fn drop_handle(&self, id: u64) -> Option<Handle> {
        self.handles.lock().unwrap().remove(&id)
    }

    /// A job for the disk thread, answered when done.
    async fn disk<T: Send + 'static>(&self, job: impl FnOnce() -> Result<T, String> + Send + 'static) -> Result<T, String> {
        let (done, answer) = tokio::sync::oneshot::channel();
        self.disk.lock().unwrap().send(Box::new(move || {
            let _ = done.send(job());
        })).map_err(|_| "the disk thread is gone".to_string())?;
        answer.await.map_err(|_| "the disk thread is gone".to_string())?
    }

    fn istream_done(&self, id: u64, halves: &Halves) {
        if halves.ended.load(Ordering::Relaxed) && halves.finished.load(Ordering::Relaxed) {
            self.drop_handle(id);
        }
    }

    fn request(&self, a: &Value, body: Option<Vec<u8>>) -> Result<reqwest::RequestBuilder, String> {
        let method = reqwest::Method::from_bytes(str_of(a, "method")?.as_bytes()).map_err(err)?;
        let mut builder = self.http.lock().unwrap().request(method, str_of(a, "url")?);
        for pair in a.get("headers").and_then(Value::as_array).into_iter().flatten() {
            if let (Some(k), Some(v)) = (pair.get(0).and_then(Value::as_str), pair.get(1).and_then(Value::as_str)) {
                builder = builder.header(k, v);
            }
        }
        if let Some(body) = body {
            builder = builder.body(body);
        }
        Ok(builder)
    }

    async fn run(self: &Arc<Self>, op: &str, a: Value, bytes: Option<Vec<u8>>) -> Done {
        match op {
            "fetch" => {
                let response = self.request(&a, bytes)?.send().await.map_err(http_error)?;
                let (status, headers) = (response.status().as_u16(), headers_of(&response));
                let body = response.bytes().await.map_err(http_error)?.to_vec();
                Ok(Answer::bytes(json!({ "status": status, "headers": headers }), body))
            }
            "stream.open" => {
                let response = self.request(&a, bytes)?.send().await.map_err(http_error)?;
                let (status, headers) = (response.status().as_u16(), headers_of(&response));
                let id = self.keep(Handle::Response(Arc::new(tokio::sync::Mutex::new(response))));
                Ok(Answer::json(json!({ "status": status, "headers": headers, "id": id })))
            }
            "stream.read" => {
                let Handle::Response(response) = self.handle(id_of(&a)?)? else { return Err("not a response".into()) };
                let chunk = response.lock().await.chunk().await.map_err(http_error)?;
                Ok(match chunk {
                    Some(c) => Answer::bytes(json!({}), c.to_vec()),
                    None => Answer::json(json!({ "end": true })),
                })
            }
            "stream.close" | "ws.close" | "tcp.close" => {
                // Dropping the response, the socket's sender (its task ends) or the halves closes it.
                self.drop_handle(id_of(&a)?);
                Ok(Answer::json(json!({})))
            }
            "ws.open" => self.ws_open(&a).await,
            "ws.next" => {
                let Handle::Ws { incoming, .. } = self.handle(id_of(&a)?)? else { return Err("not a socket".into()) };
                let frame = incoming.lock().await.recv().await;
                match frame {
                    Some(Ok(text)) => Ok(Answer::json(json!({ "text": text }))),
                    Some(Err(e)) => Err(e),
                    None => Ok(Answer::json(json!({ "end": true }))),
                }
            }
            "ws.send" => {
                let Handle::Ws { outgoing, .. } = self.handle(id_of(&a)?)? else { return Err("not a socket".into()) };
                outgoing.send(str_of(&a, "text")?.to_string()).map_err(|_| "the socket is closed".to_string())?;
                Ok(Answer::json(json!({})))
            }
            "storage.get" => {
                let path = storage_path(&self.dir, str_of(&a, "key")?);
                self.disk(move || match std::fs::read(&path) {
                    Ok(bytes) => Ok(Answer::bytes(json!({}), bytes)),
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Answer::json(json!({ "none": true }))),
                    Err(e) => Err(err(e)),
                })
                .await
            }
            "storage.set" => {
                let path = storage_path(&self.dir, str_of(&a, "key")?);
                let value = bytes.unwrap_or_default();
                self.disk(move || {
                    // Written aside and renamed over: a crash leaves the old value or the new one, never half.
                    let partial = path.with_extension("partial");
                    std::fs::write(&partial, &value).map_err(err)?;
                    std::fs::File::open(&partial).and_then(|f| f.sync_all()).map_err(err)?;
                    std::fs::rename(&partial, &path).map_err(err)?;
                    Ok(Answer::json(json!({})))
                })
                .await
            }
            "storage.delete" => {
                let path = storage_path(&self.dir, str_of(&a, "key")?);
                self.disk(move || match std::fs::remove_file(&path) {
                    Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(err(e)),
                    _ => Ok(Answer::json(json!({}))),
                })
                .await
            }
            "db.read" => {
                let (table, from, to) = (str_of(&a, "table")?.to_string(), str_of(&a, "from")?.to_string(), str_of(&a, "to")?.to_string());
                let db = self.db.clone();
                self.disk(move || {
                    let mut guard = db.lock().map_err(|_| "the database is gone".to_string())?;
                    let conn = open_db(&mut guard)?;
                    let mut query = conn.prepare_cached("SELECT key, value FROM records WHERE tbl = ?1 AND key >= ?2 AND key < ?3 ORDER BY key").map_err(err)?;
                    let rows = query
                        .query_map(rusqlite::params![table, from, to], |row| Ok((row.get::<_, String>(0)?, row.get::<_, Vec<u8>>(1)?)))
                        .map_err(err)?
                        .collect::<Result<Vec<_>, _>>()
                        .map_err(err)?;
                    let keys: Vec<&String> = rows.iter().map(|(k, _)| k).collect();
                    let sizes: Vec<usize> = rows.iter().map(|(_, v)| v.len()).collect();
                    let json = json!({ "keys": keys, "sizes": sizes });
                    Ok(Answer::bytes(json, rows.iter().flat_map(|(_, v)| v.iter().copied()).collect()))
                })
                .await
            }
            "tcp.open" => {
                let port = a.get("port").and_then(Value::as_u64).ok_or("missing port")? as u16;
                let stream = tokio::net::TcpStream::connect(("127.0.0.1", port)).await.map_err(err)?;
                let (read, write) = stream.into_split();
                let id = self.keep(Handle::Tcp { read: Arc::new(tokio::sync::Mutex::new(read)), write: Arc::new(tokio::sync::Mutex::new(write)) });
                Ok(Answer::json(json!({ "id": id })))
            }
            "tcp.read" => {
                let Handle::Tcp { read, .. } = self.handle(id_of(&a)?)? else { return Err("not a tcp connection".into()) };
                let mut buf = vec![0u8; 64 * 1024];
                let n = read.lock().await.read(&mut buf).await.map_err(err)?;
                if n == 0 {
                    return Ok(Answer::json(json!({ "end": true })));
                }
                buf.truncate(n);
                Ok(Answer::bytes(json!({}), buf))
            }
            "tcp.write" => {
                let Handle::Tcp { write, .. } = self.handle(id_of(&a)?)? else { return Err("not a tcp connection".into()) };
                write.lock().await.write_all(&bytes.unwrap_or_default()).await.map_err(err)?;
                Ok(Answer::json(json!({})))
            }
            "tcp.end" => {
                let Handle::Tcp { write, .. } = self.handle(id_of(&a)?)? else { return Err("not a tcp connection".into()) };
                let _ = write.lock().await.shutdown().await;
                Ok(Answer::json(json!({})))
            }
            "reset" => {
                // Requests already on the old pool keep it until they end.
                *self.http.lock().unwrap() = http_client(&self.tls);
                Ok(Answer::json(json!({})))
            }
            "iroh.bind" => self.bind(&a, bytes.unwrap_or_default()).await,
            "iroh.connect" => {
                let Handle::Endpoint(endpoint) = self.handle(id_of(&a)?)? else { return Err("not an endpoint".into()) };
                let additional: Vec<Vec<u8>> = a.get("additional").and_then(Value::as_array).into_iter().flatten().filter_map(|x| hex::decode(x.as_str()?).ok()).collect();
                let options = iroh::endpoint::ConnectOptions::new().with_additional_alpns(additional);
                let addr = endpoint_addr(a.get("addr").ok_or("missing addr")?)?;
                let connecting = endpoint.connect_with_opts(addr, &bytes.unwrap_or_default(), options).await.map_err(err)?;
                let conn = connecting.await.map_err(err)?;
                Ok(Answer::json(json!({ "id": self.keep(Handle::Conn(conn)) })))
            }
            "iroh.networkChange" => {
                let Handle::Endpoint(endpoint) = self.handle(id_of(&a)?)? else { return Err("not an endpoint".into()) };
                endpoint.network_change().await;
                Ok(Answer::json(json!({})))
            }
            "iroh.close" => {
                if let Some(Handle::Endpoint(endpoint)) = self.drop_handle(id_of(&a)?) {
                    endpoint.close().await;
                }
                Ok(Answer::json(json!({})))
            }
            "conn.openBi" | "conn.openUni" | "conn.acceptBi" => {
                let Handle::Conn(conn) = self.handle(id_of(&a)?)? else { return Err("not a connection".into()) };
                let (send, recv) = match op {
                    "conn.openBi" => {
                        let (s, r) = conn.open_bi().await.map_err(err)?;
                        (Some(s), Some(r))
                    }
                    "conn.openUni" => (Some(conn.open_uni().await.map_err(err)?), None),
                    _ => match conn.accept_bi().await {
                        Ok((s, r)) => (Some(s), Some(r)),
                        Err(_) => return Ok(Answer::json(json!({ "end": true }))),
                    },
                };
                let halves = Halves {
                    ended: (recv.is_none()).into(),
                    finished: false.into(),
                    send: tokio::sync::Mutex::new(send),
                    recv: tokio::sync::Mutex::new(recv),
                    reset: tokio::sync::watch::channel(false).0,
                };
                Ok(Answer::json(json!({ "id": self.keep(Handle::IStream(Arc::new(halves))) })))
            }
            "conn.closed" => {
                let Handle::Conn(conn) = self.handle(id_of(&a)?)? else { return Err("not a connection".into()) };
                Ok(Answer::json(close_info(&conn.closed().await)))
            }
            "conn.close" => {
                let Handle::Conn(conn) = self.handle(id_of(&a)?)? else { return Err("not a connection".into()) };
                let code = a.get("code").and_then(Value::as_u64).unwrap_or(0) as u32;
                conn.close(code.into(), a.get("reason").and_then(Value::as_str).unwrap_or("").as_bytes());
                Ok(Answer::json(json!({})))
            }
            "istream.read" => {
                let id = id_of(&a)?;
                let Handle::IStream(halves) = self.handle(id)? else { return Err("not a stream".into()) };
                let mut reset = halves.reset.subscribe();
                if *reset.borrow() {
                    return Ok(Answer::json(json!({ "end": true })));
                }
                let mut buf = vec![0u8; 64 * 1024];
                let read = {
                    let mut recv = halves.recv.lock().await;
                    let Some(recv) = recv.as_mut() else { return Ok(Answer::json(json!({ "end": true }))) };
                    tokio::select! {
                        read = recv.read(&mut buf) => read.map_err(err)?,
                        _ = reset.changed() => None,
                    }
                };
                match read {
                    Some(n) => {
                        buf.truncate(n);
                        Ok(Answer::bytes(json!({}), buf))
                    }
                    None => {
                        halves.ended.store(true, Ordering::Relaxed);
                        self.istream_done(id, &halves);
                        Ok(Answer::json(json!({ "end": true })))
                    }
                }
            }
            "istream.write" => {
                let Handle::IStream(halves) = self.handle(id_of(&a)?)? else { return Err("not a stream".into()) };
                let mut send = halves.send.lock().await;
                send.as_mut().ok_or("no sending half")?.write_all(&bytes.unwrap_or_default()).await.map_err(err)?;
                Ok(Answer::json(json!({})))
            }
            "istream.finish" => {
                let id = id_of(&a)?;
                let Handle::IStream(halves) = self.handle(id)? else { return Err("not a stream".into()) };
                if let Some(send) = halves.send.lock().await.as_mut() {
                    send.finish().map_err(err)?;
                }
                halves.finished.store(true, Ordering::Relaxed);
                // A stream one way (a measurement) is let go once `stopped` answers; one both ways once read to its end.
                // (Let go here, a measurement's `stopped` found no stream and every relay measured on Android came to
                // nothing, 2026-10-05.)
                if halves.recv.lock().await.is_some() {
                    self.istream_done(id, &halves);
                }
                Ok(Answer::json(json!({})))
            }
            "istream.stopped" => {
                let id = id_of(&a)?;
                let Handle::IStream(halves) = self.handle(id)? else { return Err("not a stream".into()) };
                // Taken under the lock and awaited without it, so writes go on meanwhile.
                let stopped = match halves.send.lock().await.as_mut() {
                    Some(send) => send.stopped(),
                    None => return Ok(Answer::json(json!({ "code": null }))),
                };
                let code = stopped.await;
                if halves.recv.lock().await.is_none() && halves.finished.load(Ordering::Relaxed) {
                    self.drop_handle(id);
                }
                let code = code.map_err(err)?;
                Ok(Answer::json(json!({ "code": code.map(|c| c.into_inner()) })))
            }
            "istream.reset" => {
                let id = id_of(&a)?;
                let code = a.get("code").and_then(Value::as_u64).unwrap_or(0) as u32;
                if let Some(Handle::IStream(halves)) = self.drop_handle(id) {
                    let _ = halves.reset.send(true);
                    if let Some(send) = halves.send.lock().await.as_mut() {
                        let _ = send.reset(code.into());
                    }
                    if let Some(recv) = halves.recv.lock().await.as_mut() {
                        let _ = recv.stop(code.into());
                    }
                }
                Ok(Answer::json(json!({})))
            }
            other => Err(format!("no operation {other}")),
        }
    }

    async fn ws_open(self: &Arc<Self>, a: &Value) -> Done {
        let mut request = str_of(a, "url")?.into_client_request().map_err(ws_error)?;
        let protocols: Vec<&str> = a.get("protocols").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str).collect();
        if !protocols.is_empty() {
            request.headers_mut().insert("sec-websocket-protocol", protocols.join(", ").parse().map_err(err)?);
        }
        let (socket, _) = tokio_tungstenite::connect_async_tls_with_config(request, None, false, Some(Connector::Rustls(self.tls.clone()))).await.map_err(ws_error)?;
        let (incoming_tx, incoming) = tokio::sync::mpsc::unbounded_channel();
        let (outgoing, mut outgoing_rx) = tokio::sync::mpsc::unbounded_channel::<String>();
        // One task owns the socket: reading is also what answers the server's pings; what is to be sent goes between.
        tokio::spawn(async move {
            let mut socket = socket;
            loop {
                tokio::select! {
                    message = socket.next() => match message {
                        Some(Ok(Message::Text(text))) => { let _ = incoming_tx.send(Ok(text.as_str().to_owned())); }
                        Some(Ok(Message::Close(_))) | Some(Err(WsError::ConnectionClosed | WsError::AlreadyClosed)) | None => return,
                        Some(Ok(_)) => {}
                        Some(Err(e)) => { let _ = incoming_tx.send(Err(ws_error(e))); return; }
                    },
                    text = outgoing_rx.recv() => match text {
                        Some(text) => { if let Err(e) = socket.send(Message::text(text)).await { let _ = incoming_tx.send(Err(ws_error(e))); return; } }
                        // The handle went (ws.close): the socket is closed.
                        None => { let _ = socket.close(None).await; return; }
                    },
                }
            }
        });
        let id = self.keep(Handle::Ws { incoming: Arc::new(tokio::sync::Mutex::new(incoming)), outgoing });
        Ok(Answer::json(json!({ "id": id })))
    }

    async fn bind(self: &Arc<Self>, a: &Value, key: Vec<u8>) -> Done {
        let bytes: [u8; 32] = key.as_slice().try_into().map_err(|_| "the key is not 32 bytes".to_string())?;
        let key = SecretKey::from_bytes(&bytes);
        let relays: Vec<RelayUrl> = a.get("relayUrls").and_then(Value::as_array).into_iter().flatten().map(|u| relay_url(u.as_str().unwrap_or_default())).collect::<Result<_, _>>()?;
        let mut cubic = noq_proto::congestion::CubicConfig::default();
        cubic.initial_window(256 * 1024);
        let mut builder = Endpoint::builder(Minimal)
            .secret_key(key)
            .relay_mode(if relays.is_empty() { RelayMode::Disabled } else { RelayMode::Custom(iroh::RelayMap::from_iter(relays.clone())) })
            .transport_config(QuicTransportConfig::builder().congestion_controller_factory(Arc::new(cubic)).build());
        if a.get("relayOnly").and_then(Value::as_bool).unwrap_or(false) {
            builder = builder.clear_ip_transports();
        }
        // Stations on the LAN (mDNS, never announced itself) and which relay they are on (the DHT), as client/core-ts's.
        if a.get("lookup").and_then(Value::as_bool).unwrap_or(false) && !relays.is_empty() {
            builder = builder
                .address_lookup(iroh_mdns_address_lookup::MdnsAddressLookup::builder().service_name(MDNS_SERVICE).advertise(false))
                .address_lookup(iroh_mdns_address_lookup::MdnsAddressLookup::builder().service_name(FORMER_MDNS_SERVICE).advertise(false))
                .address_lookup(iroh_mainline_address_lookup::DhtAddressLookup::builder().no_publish());
        }
        let endpoint = builder.bind().await.map_err(err)?;
        Ok(Answer::json(json!({ "id": self.keep(Handle::Endpoint(endpoint)) })))
    }

    /// An account's database: opened, a statement run, its rows, closed, its file removed.
    fn sql(&self, op: &str, a: &Value) -> Result<Value, String> {
        let mut sqls = self.sqls.lock().map_err(|_| "the databases are gone".to_string())?;
        match op {
            "sql.open" => {
                let name = str_of(a, "name")?;
                let (path, conn) = if name == ":memory:" {
                    (None, rusqlite::Connection::open_in_memory().map_err(err)?)
                } else {
                    if name.contains('/') || name.contains('\\') || name.starts_with('.') {
                        return Err(format!("not a database name: {name}"));
                    }
                    let dir = self.dir.join("databases");
                    std::fs::create_dir_all(&dir).map_err(err)?;
                    let path = dir.join(format!("{name}.db"));
                    (Some(path.clone()), rusqlite::Connection::open(&path).map_err(err)?)
                };
                conn.busy_timeout(std::time::Duration::from_secs(5)).map_err(err)?;
                conn.set_prepared_statement_cache_capacity(256);
                // One process at a time: another one finds it busy.
                conn.execute_batch("PRAGMA locking_mode = EXCLUSIVE; PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;").map_err(err)?;
                let id = self.next.fetch_add(1, Ordering::Relaxed);
                sqls.insert(id, (path, conn));
                Ok(json!({ "id": id }))
            }
            "sql.delete" => {
                let name = str_of(a, "name")?;
                let path = self.dir.join("databases").join(format!("{name}.db"));
                sqls.retain(|_, (p, _)| p.as_ref() != Some(&path));
                for end in ["", "-wal", "-shm", "-journal"] {
                    let file = PathBuf::from(format!("{}{end}", path.display()));
                    match std::fs::remove_file(&file) {
                        Err(e) if e.kind() != std::io::ErrorKind::NotFound => return Err(err(e)),
                        _ => {}
                    }
                }
                Ok(Value::Null)
            }
            _ => {
                let id = id_of(a)?;
                if op == "sql.close" {
                    sqls.remove(&id);
                    return Ok(Value::Null);
                }
                let (_, conn) = sqls.get(&id).ok_or_else(|| format!("no database {id}"))?;
                let sql = str_of(a, "sql")?;
                match op {
                    "sql.exec" => {
                        conn.execute_batch(sql).map_err(err)?;
                        Ok(Value::Null)
                    }
                    "sql.run" => {
                        let mut statement = conn.prepare_cached(sql).map_err(err)?;
                        let n = statement.execute(rusqlite::params_from_iter(sql_params(a))).map_err(err)?;
                        Ok(json!(n))
                    }
                    "sql.all" => {
                        let mut statement = conn.prepare_cached(sql).map_err(err)?;
                        let columns = statement.column_count();
                        let mut rows = statement.query(rusqlite::params_from_iter(sql_params(a))).map_err(err)?;
                        let mut out = Vec::new();
                        while let Some(row) = rows.next().map_err(err)? {
                            let mut values = Vec::with_capacity(columns);
                            for i in 0..columns {
                                values.push(match row.get_ref(i).map_err(err)? {
                                    rusqlite::types::ValueRef::Null => Value::Null,
                                    rusqlite::types::ValueRef::Integer(v) => json!(v),
                                    rusqlite::types::ValueRef::Real(v) => json!(v),
                                    rusqlite::types::ValueRef::Text(v) => Value::String(String::from_utf8_lossy(v).into_owned()),
                                    rusqlite::types::ValueRef::Blob(v) => Value::Array(v.iter().map(|b| json!(b)).collect()),
                                });
                            }
                            out.push(Value::Array(values));
                        }
                        Ok(Value::Array(out))
                    }
                    _ => Err(format!("no operation {op}")),
                }
            }
        }
    }

    fn run_sync(&self, op: &str, a: &Value) -> Result<Value, String> {
        let handle = self.handle(id_of(a)?)?;
        match (op, handle) {
            ("iroh.endpointId", Handle::Endpoint(e)) => Ok(json!(hex::encode(e.id().as_bytes()))),
            ("iroh.addAddr", Handle::Endpoint(e)) => {
                let addr = endpoint_addr(a.get("addr").ok_or("missing addr")?)?;
                e.address_lookup().map_err(err)?.add(iroh::address_lookup::MemoryLookup::from_endpoint_info([addr]));
                Ok(Value::Null)
            }
            ("iroh.relayStatus", Handle::Endpoint(e)) => Ok(Value::Array(e.home_relay_status().get().iter().map(|s| json!({ "url": s.url().to_string(), "connected": s.is_connected() })).collect())),
            ("conn.remoteId", Handle::Conn(c)) => Ok(json!(hex::encode(c.remote_id().as_bytes()))),
            ("conn.closeReason", Handle::Conn(c)) => Ok(c.close_reason().map(|e| close_info(&e)).unwrap_or(Value::Null)),
            ("conn.paths", Handle::Conn(c)) => Ok(Value::Array(
                c.paths()
                    .iter()
                    .map(|p| {
                        let relay = match p.remote_addr() {
                            iroh::TransportAddr::Relay(url) => Some(url.to_string()),
                            _ => None,
                        };
                        json!({ "selected": p.is_selected(), "relay": relay, "rttMs": p.rtt().as_secs_f64() * 1000.0 })
                    })
                    .collect(),
            )),
            ("conn.stats", Handle::Conn(c)) => {
                let s = c.stats();
                Ok(json!({ "rxBytes": s.udp_rx.bytes, "txBytes": s.udp_tx.bytes, "txPackets": s.udp_tx.datagrams, "lostPackets": s.lost_packets }))
            }
            (op, _) => Err(format!("no operation {op} on that handle")),
        }
    }
}

impl Shell {
    pub fn start(dir: PathBuf, complete: Complete, ctx: *mut c_void) -> std::io::Result<Shell> {
        std::fs::create_dir_all(&dir)?;
        let runtime = tokio::runtime::Builder::new_multi_thread().worker_threads(2).thread_name("stillfail-shell").enable_all().build()?;
        let (jobs, queue) = mpsc::channel::<Job>();
        std::thread::Builder::new().name("stillfail-disk".into()).spawn(move || {
            for job in queue {
                job();
            }
        })?;
        let tls = Arc::new(tls_config());
        let http = Mutex::new(http_client(&tls));
        let db = Arc::new(Mutex::new(DbHandle { path: dir.join("core.db"), conn: None }));
        let inner = Arc::new(Inner { complete, ctx: Ctx(ctx), dir, disk: Mutex::new(jobs), db, tls, http, handles: Mutex::default(), next: AtomicU64::new(1), sqls: Mutex::default() });
        Ok(Shell { runtime, inner })
    }

    pub fn call(&self, id: u64, op: String, json: &[u8], bytes: Option<Vec<u8>>) {
        let inner = self.inner.clone();
        let args: Value = serde_json::from_slice(json).unwrap_or(Value::Null);
        self.runtime.spawn(async move {
            let done = inner.run(&op, args, bytes).await;
            let (json, error, bytes) = match done {
                Ok(answer) => (serde_json::to_vec(&answer.json).unwrap_or_default(), Vec::new(), answer.bytes),
                Err(e) => (Vec::new(), if e.is_empty() { b"failed".to_vec() } else { e.into_bytes() }, None),
            };
            let (b, blen, has) = match &bytes {
                Some(b) => (b.as_ptr(), b.len(), 1),
                None => (std::ptr::null(), 0, 0),
            };
            (inner.complete)(inner.ctx.0, id, json.as_ptr(), json.len(), error.as_ptr(), error.len(), b, blen, has);
        });
    }

    pub fn call_sync(&self, op: &str, json: &[u8]) -> Vec<u8> {
        let args: Value = serde_json::from_slice(json).unwrap_or(Value::Null);
        let done = if op.starts_with("sql.") { self.inner.sql(op, &args) } else { self.inner.run_sync(op, &args) };
        let out = match done {
            Ok(value) => json!({ "value": value }),
            Err(error) => json!({ "error": error }),
        };
        serde_json::to_vec(&out).unwrap_or_default()
    }
}

/// Starts a shell keeping its files in `data_dir`. Null when it cannot (the directory cannot be made).
///
/// # Safety
/// `data_dir` is a NUL-terminated string; `complete` may be called with `ctx` from any thread until `sf_shell_stop`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sf_shell_start(data_dir: *const c_char, complete: Complete, ctx: *mut c_void) -> *mut Shell {
    // SAFETY: the caller gives a NUL-terminated string.
    let dir = unsafe { CStr::from_ptr(data_dir) }.to_string_lossy().into_owned();
    match Shell::start(PathBuf::from(dir), complete, ctx) {
        Ok(shell) => Box::into_raw(Box::new(shell)),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Starts operation `id`.
///
/// # Safety
/// `shell` is from `sf_shell_start`; `op` NUL-terminated; `json`/`bytes` valid for their lengths (`bytes` read only
/// when `has_bytes`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sf_shell_call(shell: *const Shell, id: u64, op: *const c_char, json: *const u8, json_len: usize, bytes: *const u8, bytes_len: usize, has_bytes: u8) {
    // SAFETY: as documented.
    let (shell, op, json) = unsafe { (&*shell, CStr::from_ptr(op).to_string_lossy().into_owned(), std::slice::from_raw_parts(json, json_len)) };
    let bytes = (has_bytes != 0).then(|| if bytes_len == 0 { Vec::new() } else { unsafe { std::slice::from_raw_parts(bytes, bytes_len) }.to_vec() });
    shell.call(id, op, json, bytes);
}

/// An operation answered at once: its JSON (`{value}` or `{error}`), to be let go with `sf_free`.
///
/// # Safety
/// As `sf_shell_call`; `out_len` is written.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sf_shell_call_sync(shell: *const Shell, op: *const c_char, json: *const u8, json_len: usize, out_len: *mut usize) -> *mut u8 {
    // SAFETY: as documented.
    let (shell, op, json) = unsafe { (&*shell, CStr::from_ptr(op).to_string_lossy().into_owned(), std::slice::from_raw_parts(json, json_len)) };
    let mut out = shell.call_sync(&op, json).into_boxed_slice();
    unsafe { *out_len = out.len() };
    let ptr = out.as_mut_ptr();
    std::mem::forget(out);
    ptr
}

/// # Safety
/// `ptr`/`len` from `sf_shell_call_sync`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sf_free(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        // SAFETY: made by `sf_shell_call_sync` from a boxed slice of this length.
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)) });
    }
}

/// Stops a shell: what is under way is dropped, its answers never come.
///
/// # Safety
/// `shell` from `sf_shell_start`, not used after.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sf_shell_stop(shell: *mut Shell) {
    if !shell.is_null() {
        // SAFETY: made by `sf_shell_start`.
        let shell = unsafe { Box::from_raw(shell) };
        shell.runtime.shutdown_background();
    }
}

/// The viewer's time zone at `at_ms` (minutes east of UTC), from the C library, which on Android follows the system's
/// zone setting and its DST rules (as the Rust core had them).
#[unsafe(no_mangle)]
pub extern "C" fn sf_utc_offset_min(at_ms: f64) -> i32 {
    let at = (at_ms / 1000.0).floor() as libc::time_t;
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    // SAFETY: both pointers are valid for the call; localtime_r is the thread-safe variant.
    if unsafe { libc::localtime_r(&at, &mut tm) }.is_null() {
        return 0;
    }
    (tm.tm_gmtoff / 60) as i32
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Condvar, Mutex as StdMutex};

    static ANSWERS: StdMutex<Vec<(u64, String, String, Option<Vec<u8>>)>> = StdMutex::new(Vec::new());
    static ANSWERED: Condvar = Condvar::new();

    extern "C" fn complete(_: *mut c_void, id: u64, json: *const u8, jl: usize, e: *const u8, el: usize, b: *const u8, bl: usize, has: u8) {
        let s = |p: *const u8, l: usize| if l == 0 { String::new() } else { String::from_utf8_lossy(unsafe { std::slice::from_raw_parts(p, l) }).into_owned() };
        let bytes = (has != 0).then(|| if bl == 0 { Vec::new() } else { unsafe { std::slice::from_raw_parts(b, bl) }.to_vec() });
        ANSWERS.lock().unwrap().push((id, s(json, jl), s(e, el), bytes));
        ANSWERED.notify_all();
    }

    /// The answer to `id`, once it comes (however long that takes).
    fn answer(id: u64) -> (String, String, Option<Vec<u8>>) {
        let mut answers = ANSWERS.lock().unwrap();
        loop {
            if let Some(i) = answers.iter().position(|a| a.0 == id) {
                let (_, j, e, b) = answers.remove(i);
                return (j, e, b);
            }
            answers = ANSWERED.wait(answers).unwrap();
        }
    }

    #[test]
    fn keeps_files_and_records_as_client_ffi_does() {
        let dir = tempfile::tempdir().unwrap();
        let shell = Shell::start(dir.path().to_path_buf(), complete, std::ptr::null_mut()).unwrap();
        shell.call(1, "storage.set".into(), br#"{"key":"device"}"#, Some(vec![1, 2, 3]));
        assert_eq!(answer(1).1, "");
        assert!(dir.path().join("device").exists());
        shell.call(2, "storage.get".into(), br#"{"key":"device"}"#, None);
        assert_eq!(answer(2).2, Some(vec![1, 2, 3]));
        shell.call(3, "storage.get".into(), br#"{"key":"a/b"}"#, None);
        assert_eq!(answer(3).0, r#"{"none":true}"#);
        // The former records store, as client/ffi wrote it: read only.
        {
            let conn = rusqlite::Connection::open(dir.path().join("core.db")).unwrap();
            conn.execute_batch("CREATE TABLE records (tbl TEXT NOT NULL, key TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY (tbl, key)) WITHOUT ROWID;").unwrap();
            for (k, v) in [("s\u{1}a", b"1".to_vec()), ("s\u{1}b", b"22".to_vec()), ("t\u{1}a", Vec::new())] {
                conn.execute("INSERT INTO records (tbl, key, value) VALUES ('row', ?1, ?2)", rusqlite::params![k, v]).unwrap();
            }
        }
        shell.call(5, "db.read".into(), "{\"table\":\"row\",\"from\":\"s\\u0001\",\"to\":\"s\\u0002\"}".as_bytes(), None);
        let (json, _, bytes) = answer(5);
        assert_eq!(json, "{\"keys\":[\"s\\u0001a\",\"s\\u0001b\"],\"sizes\":[1,2]}");
        assert_eq!(bytes, Some(b"122".to_vec()));
        assert!(dir.path().join("core.db").exists());
        let out = shell.call_sync("conn.remoteId", br#"{"id":999}"#);
        assert_eq!(String::from_utf8(out).unwrap(), r#"{"error":"no handle 999"}"#);
    }

    #[test]
    fn keeps_an_accounts_database() {
        let dir = tempfile::tempdir().unwrap();
        let shell = Shell::start(dir.path().to_path_buf(), complete, std::ptr::null_mut()).unwrap();
        let sync = |op: &str, json: &str| -> Value { serde_json::from_slice(&shell.call_sync(op, json.as_bytes())).unwrap() };
        let id = sync("sql.open", r#"{"name":"account-a"}"#)["value"]["id"].as_u64().unwrap();
        assert!(dir.path().join("databases/account-a.db").exists());
        assert_eq!(sync("sql.exec", &format!(r#"{{"id":{id},"sql":"CREATE TABLE t (k TEXT PRIMARY KEY, n INTEGER, x REAL, j TEXT)"}}"#))["value"], Value::Null);
        assert_eq!(sync("sql.run", &format!(r#"{{"id":{id},"sql":"INSERT INTO t VALUES (?, ?, ?, ?)","params":["a",1,1.5,"{{\"x\":\"中\"}}"]}}"#))["value"], json!(1));
        assert_eq!(sync("sql.run", &format!(r#"{{"id":{id},"sql":"INSERT INTO t VALUES (?, ?, ?, ?)","params":["b",null,null,null]}}"#))["value"], json!(1));
        let rows = sync("sql.all", &format!(r#"{{"id":{id},"sql":"SELECT k, n, x, j FROM t ORDER BY k","params":[]}}"#));
        assert_eq!(rows["value"], json!([["a", 1, 1.5, "{\"x\":\"中\"}"], ["b", null, null, null]]));
        let bad = sync("sql.run", &format!(r#"{{"id":{id},"sql":"INSERT INTO t VALUES (?, 1, 1, 1)","params":["a"]}}"#));
        assert!(bad["error"].as_str().unwrap().contains("UNIQUE"));
        assert_eq!(sync("sql.close", &format!(r#"{{"id":{id}}}"#))["value"], Value::Null);
        assert!(sync("sql.all", &format!(r#"{{"id":{id},"sql":"SELECT 1"}}"#))["error"].is_string());
        assert_eq!(sync("sql.delete", r#"{"name":"account-a"}"#)["value"], Value::Null);
        assert!(!dir.path().join("databases/account-a.db").exists());
        assert!(sync("sql.open", r#"{"name":"../x"}"#)["error"].is_string());
        let memory = sync("sql.open", r#"{"name":":memory:"}"#)["value"]["id"].as_u64().unwrap();
        assert_eq!(sync("sql.all", &format!(r#"{{"id":{memory},"sql":"SELECT 2"}}"#))["value"], json!([[2]]));
    }
}
