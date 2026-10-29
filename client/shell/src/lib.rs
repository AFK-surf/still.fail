//! The native shell of the core in TypeScript in the apps (client/core-ts `hosts/bridge.ts`; apps/mbui/engine runs it
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

/// `say(ctx, json, json_len, bytes, bytes_len)`: a message for the app, as the core says one (its JSON, and the bytes
/// beside it, or none: `bytes` null), straight from the shell (a remote screen's frames: `istream.tap`). Any thread.
pub type Say = extern "C" fn(*mut c_void, *const u8, usize, *const u8, usize);

/// `media(ctx, call, kind, key, seq, ts, bytes, bytes_len)`: a tapped remote screen's record offered to the app's host as
/// it is, before it is said (`Say`): a video frame (kind 2: `key`, `ts`, its access unit), a sound packet (6: `ts`, its
/// PCM), or a config (1) or the sound's (5), offered only to be seen (the host stops taking that view's records until
/// the app has taken it). `seq` numbers every record said of any tapped view, from 1. 1: the host took it (decoded,
/// played and acknowledged there), nothing said; 0: said to the app as before. Any of the shell's threads, a view's
/// records in order.
pub type Media = extern "C" fn(*mut c_void, u64, u8, u8, u64, u64, *const u8, usize) -> u8;

/// Where a tapped view's records go (ScreenTap::said): offered to the host (`media`), said to the app.
trait Tell {
    /// Record `kind` of view `call` offered to the host: whether it took it.
    fn media(&self, call: u64, kind: u8, key: bool, seq: u64, ts: u64, bytes: &[u8]) -> bool;
    /// A message for the app (its JSON, the bytes beside it).
    fn say(&self, json: &[u8], bytes: Option<&[u8]>);
}

/// The number of the next record said of a tapped view (`Media`'s `seq`): one count for all, so a view tapped again on
/// another stream (`screen.bounds`) goes on from where it was.
static MEDIA_SEQ: AtomicU64 = AtomicU64::new(1);

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

/// The two halves of an iroh stream, and the reads waiting on it: a reset wakes them first (as the addon's).
struct Halves {
    /// The connection it is on: it goes when that one closes.
    conn: u64,
    send: tokio::sync::Mutex<Option<SendStream>>,
    recv: tokio::sync::Mutex<Option<RecvStream>>,
    reset: tokio::sync::watch::Sender<bool>,
    /// Read to its end; finished (or no sending half). Both: the handle goes.
    ended: std::sync::atomic::AtomicBool,
    finished: std::sync::atomic::AtomicBool,
    /// A remote screen's view, tapped (`istream.tap`): its frames read here, the picture's and the sound's said to the
    /// app as they come, the rest left for the core to read.
    tap: Mutex<Option<ScreenTap>>,
}

/// A remote screen's stream read in the shell (docs/remote-screens.md, Wire; client/core-ts screen-frames.ts): its
/// frames taken apart as its pieces come; a config, a video frame, the sound's config and its packets said to the app at
/// once as the core's progress of the view's call (`{id, value}`, the bytes beside it: what screens.ts says of them),
/// so they go through neither the core's JS nor its thread; the rest (its state, a clipboard, what is not one of them)
/// kept, as they came, for the core's next read, with a video frame's head alone the first time one comes after a
/// config (what tells the core the picture is live).
struct ScreenTap {
    /// the app's call the view is (its progress' id)
    call: u64,
    /// what came and is not a whole frame yet
    pending: Vec<u8>,
    /// frames for the core, whole
    out: Vec<u8>,
    /// a video frame's head given the core since the last config
    told_video: bool,
}

const FRAME_CONFIG: u8 = 1;
const FRAME_VIDEO: u8 = 2;
const FRAME_AUDIO_CONFIG: u8 = 5;
const FRAME_AUDIO: u8 = 6;
/// A frame longer than this is no frame (screen-frames.ts MAX_FRAME): left to the core, which says so.
const FRAME_MAX: usize = 64 * 1024 * 1024;

impl ScreenTap {
    /// What came next: its whole frames said or kept.
    fn take(&mut self, chunk: &[u8], tell: &dyn Tell) {
        // (whole frames read where they came, not copied first; what is left of one kept)
        if self.pending.is_empty() {
            let used = self.frames_in(chunk, tell);
            self.pending.extend_from_slice(&chunk[used..]);
            return;
        }
        let mut pending = std::mem::take(&mut self.pending);
        pending.extend_from_slice(chunk);
        let used = self.frames_in(&pending, tell);
        pending.drain(..used);
        self.pending = pending;
    }

    /// The whole frames at the start of `data` said or kept: how many bytes they were.
    fn frames_in(&mut self, data: &[u8], tell: &dyn Tell) -> usize {
        let mut at = 0;
        loop {
            let rest = &data[at..];
            if rest.len() < 5 {
                break;
            }
            let len = u32::from_be_bytes([rest[1], rest[2], rest[3], rest[4]]) as usize;
            if len > FRAME_MAX {
                // out of step: all of it the core's, which fails the view
                self.out.extend_from_slice(rest);
                at = data.len();
                break;
            }
            if rest.len() < 5 + len {
                break;
            }
            let (kind, body) = (rest[0], &rest[5..5 + len]);
            if !self.said(kind, body, tell) {
                self.out.extend_from_slice(&rest[..5 + len]);
            }
            at += 5 + len;
        }
        at
    }

    /// Frame `kind` said to the app (and what the core needs of it kept: a config, a video frame's head); false: one
    /// for the core alone.
    fn said(&mut self, kind: u8, body: &[u8], tell: &dyn Tell) -> bool {
        let id = self.call;
        match kind {
            FRAME_VIDEO if body.len() >= 9 => {
                let (key, ts) = (body[0] & 1 == 1, u64::from_be_bytes(body[1..9].try_into().unwrap()));
                let n = MEDIA_SEQ.fetch_add(1, Ordering::Relaxed);
                // the host's decoder's at once where it takes it; else said (written as it is: no JSON value made)
                if tell.media(id, FRAME_VIDEO, key, n, ts, &body[9..]) {
                    tally("tap.direct.video");
                } else {
                    let text = format!(r#"{{"id":{id},"value":{{"frame":{{"key":{key},"ts":{ts},"n":{n}}}}}}}"#);
                    tell.say(text.as_bytes(), Some(&body[9..]));
                }
                tally("tap.video");
                if !self.told_video {
                    self.told_video = true;
                    self.out.extend_from_slice(&[FRAME_VIDEO, 0, 0, 0, 9]);
                    self.out.extend_from_slice(&body[..9]);
                }
                true
            }
            FRAME_AUDIO if body.len() == 3848 => {
                let ts = u64::from_be_bytes(body[..8].try_into().unwrap());
                let n = MEDIA_SEQ.fetch_add(1, Ordering::Relaxed);
                if tell.media(id, FRAME_AUDIO, false, n, ts, &body[8..]) {
                    tally("tap.direct.audio");
                } else {
                    let text = format!(r#"{{"id":{id},"value":{{"audio":{{"ts":{ts},"n":{n}}}}}}}"#);
                    tell.say(text.as_bytes(), Some(&body[8..]));
                }
                tally("tap.audio");
                true
            }
            FRAME_AUDIO_CONFIG => {
                let Ok(c) = serde_json::from_slice::<Value>(body) else { return false };
                if c.get("codec").and_then(Value::as_str) != Some("pcm_s16le") || c.get("sampleRate").and_then(Value::as_f64) != Some(48000.0) || c.get("channels").and_then(Value::as_f64) != Some(2.0) {
                    return false;
                }
                // (seen by the host first: no packet taken there until the app has taken this)
                tell.media(id, FRAME_AUDIO_CONFIG, false, MEDIA_SEQ.fetch_add(1, Ordering::Relaxed), 0, &[]);
                let text = format!(r#"{{"id":{id},"value":{{"audioConfig":{{"codec":"pcm_s16le","sampleRate":48000,"channels":2}}}}}}"#);
                tell.say(text.as_bytes(), None);
                true
            }
            FRAME_CONFIG => {
                // said as screen-frames.ts reads it and screens.ts says it; the core keeps it too (its state's size)
                let Ok(c) = serde_json::from_slice::<Value>(body) else { return false };
                let Some(codec) = c.get("codec").and_then(Value::as_str) else { return false };
                let whole = |k: &str| c.get(k).and_then(Value::as_f64).filter(|v| v.is_finite() && *v > 0.0).map(|v| v.round()).unwrap_or(0.0);
                let description = match c.get("description").and_then(Value::as_str) {
                    Some(d) if !d.is_empty() => match base64_decode(d) {
                        Some(b) => Some(b),
                        None => return false,
                    },
                    _ => None,
                };
                let mut config = json!({ "codec": codec, "width": whole("width"), "height": whole("height") });
                if let Some(r) = region_of(c.get("region")) {
                    config["region"] = r;
                }
                // (seen by the host first: no frame taken there until the app has taken this)
                tell.media(id, FRAME_CONFIG, false, MEDIA_SEQ.fetch_add(1, Ordering::Relaxed), 0, &[]);
                tell.say(&serde_json::to_vec(&json!({ "id": id, "value": { "config": config } })).unwrap_or_default(), description.as_deref());
                self.told_video = false;
                false
            }
            _ => false,
        }
    }
}

/// A part of the screen as a station says it (screen-frames.ts regionOf): within the screen, more than nothing each way.
fn region_of(v: Option<&Value>) -> Option<Value> {
    let v = v?.as_object()?;
    let n = |k: &str| v.get(k).and_then(Value::as_f64).filter(|x| x.is_finite());
    let (x, y, w, h) = (n("x")?, n("y")?, n("w")?, n("h")?);
    (x >= 0.0 && y >= 0.0 && w > 0.0 && h > 0.0 && x + w <= 1.0001 && y + h <= 1.0001).then(|| json!({ "x": x, "y": y, "w": w, "h": h }))
}

/// Standard base64 (padded or not); None when it is not.
fn base64_decode(s: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(s.len() * 3 / 4);
    let (mut acc, mut bits) = (0u32, 0u32);
    for c in s.bytes() {
        let v = match c {
            b'A'..=b'Z' => c - b'A',
            b'a'..=b'z' => c - b'a' + 26,
            b'0'..=b'9' => c - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            b'=' => break,
            _ => return None,
        } as u32;
        acc = (acc << 6) | v;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((acc >> bits) as u8);
            acc &= (1 << bits) - 1;
        }
    }
    Some(out)
}

/// The connections coming to an endpoint whose handshakes are done, as each finishes (`iroh.accept`), once one was
/// first asked for.
type Accepted = Arc<tokio::sync::Mutex<Option<tokio::sync::mpsc::UnboundedReceiver<Connection>>>>;

#[derive(Clone)]
enum Handle {
    Response(Arc<tokio::sync::Mutex<reqwest::Response>>),
    Ws { incoming: Arc<tokio::sync::Mutex<tokio::sync::mpsc::UnboundedReceiver<Result<String, String>>>>, outgoing: tokio::sync::mpsc::UnboundedSender<String> },
    Tcp { read: Arc<tokio::sync::Mutex<tokio::net::tcp::OwnedReadHalf>>, write: Arc<tokio::sync::Mutex<tokio::net::tcp::OwnedWriteHalf>> },
    Endpoint(Endpoint, Accepted),
    Conn(Connection),
    /// A connection that closed, let go (its state, its streams), with what the core may still ask of it.
    Gone { remote: String, reason: Value, stats: Value },
    /// An endpoint closed (`iroh.close`), let go, with what the core may still ask of it: one bound anew in its place
    /// leaves a dial still under way on it asking its relays as it fails (mesh.ts `link`), as the station's addon answers.
    Unbound { id: String },
    IStream(Arc<Halves>),
    /// A zstd stream being taken apart (`zstd.open`).
    Unzstd(Arc<Mutex<Unzstd>>),
}

/// A zstd stream being taken apart, a piece at a time as the core is given them: libzstd's streaming decoder (frames
/// one after another, a piece cut anywhere), and whether what it took so far ended a frame.
struct Unzstd {
    decoder: zstd::stream::raw::Decoder<'static>,
    whole: bool,
}

impl Unzstd {
    fn new() -> Result<Unzstd, String> {
        Ok(Unzstd { decoder: zstd::stream::raw::Decoder::new().map_err(err)?, whole: true })
    }

    /// `input` taken apart: all it makes, nothing held back.
    fn take(&mut self, input: &[u8]) -> Result<Vec<u8>, String> {
        use zstd::stream::raw::{InBuffer, Operation, OutBuffer};
        let mut out = Vec::new();
        let mut src = InBuffer::around(input);
        let mut buf = vec![0u8; 128 * 1024];
        loop {
            let mut dst = OutBuffer::around(&mut buf[..]);
            let hint = self.decoder.run(&mut src, &mut dst).map_err(err)?;
            let made = dst.pos();
            out.extend_from_slice(&buf[..made]);
            // (0: a frame ended and all of it is out; said only of what took something, an empty piece says nothing)
            if made > 0 || src.pos() > 0 {
                self.whole = hint == 0;
            }
            if src.pos() >= input.len() && made < buf.len() {
                return Ok(out);
            }
        }
    }
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
    /// How long an account's database is waited for as it is opened, while another process holds it (`open_wait`).
    open_wait: std::time::Duration,
    /// Where a message for the app goes straight from here (`sf_shell_set_say`): none, nothing is tapped.
    say: Mutex<Option<(Say, Ctx)>>,
    /// Where a tapped view's records are offered first (`sf_shell_set_media`): none, all are said.
    media: Mutex<Option<(Media, Ctx)>>,
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

impl Handle {
    fn kind(&self) -> &'static str {
        match self {
            Handle::Response(_) => "response",
            Handle::Ws { .. } => "ws",
            Handle::Tcp { .. } => "tcp",
            Handle::Endpoint(..) => "endpoint",
            Handle::Conn(_) => "conn",
            Handle::Gone { .. } => "gone",
            Handle::Unbound { .. } => "unbound",
            Handle::IStream(_) => "stream",
            Handle::Unzstd(_) => "unzstd",
        }
    }
}

/// What the shells have been asked, for when the app's memory runs away (the app's MemoryWatch.kt): the calls by
/// operation since the process started and those not answered yet, and the shells' handles by kind. A loop between the
/// core and the shell shows as one operation far ahead of the rest.
#[derive(Default)]
struct Stats {
    calls: HashMap<String, (u64, i64)>,
    shells: Vec<std::sync::Weak<Inner>>,
}

static STATS: std::sync::LazyLock<Mutex<Stats>> = std::sync::LazyLock::new(Mutex::default);

/// One more of `what` (the shell's own doings, beside the operations asked: `tap.video`, a remote screen's frame said to
/// the app), as counted operations are.
fn tally(what: &str) {
    let mut stats = STATS.lock().unwrap();
    // (no name made again for each: a screen's frames are counted a hundred times a second)
    match stats.calls.get_mut(what) {
        Some(c) => c.0 += 1,
        None => {
            stats.calls.insert(what.to_string(), (1, 0));
        }
    }
}

fn counted(op: &str, started: bool) {
    let mut stats = STATS.lock().unwrap();
    let c = stats.calls.entry(op.to_string()).or_default();
    if started {
        c.0 += 1;
        c.1 += 1;
    } else {
        c.1 -= 1;
    }
}

fn stats_json() -> Value {
    let mut stats = STATS.lock().unwrap();
    stats.shells.retain(|w| w.strong_count() > 0);
    let calls: serde_json::Map<String, Value> = stats.calls.iter().map(|(op, (n, open))| (op.clone(), json!([n, open]))).collect();
    let mut handles: HashMap<&'static str, u64> = HashMap::new();
    let mut sqls = 0;
    for inner in stats.shells.iter().filter_map(std::sync::Weak::upgrade) {
        for h in inner.handles.lock().unwrap().values() {
            *handles.entry(h.kind()).or_default() += 1;
        }
        sqls += inner.sqls.lock().unwrap().len();
    }
    json!({ "calls": calls, "handles": handles, "sqls": sqls })
}

impl Tell for Inner {
    fn media(&self, call: u64, kind: u8, key: bool, seq: u64, ts: u64, bytes: &[u8]) -> bool {
        let Some((media, ctx)) = &*self.media.lock().unwrap() else { return false };
        media(ctx.0, call, kind, key as u8, seq, ts, bytes.as_ptr(), bytes.len()) != 0
    }

    /// A message for the app said from here (`say`), as the core says one.
    fn say(&self, text: &[u8], bytes: Option<&[u8]>) {
        let Some((say, ctx)) = &*self.say.lock().unwrap() else { return };
        let (b, blen) = match bytes {
            Some(b) => (if b.is_empty() { [0u8; 1].as_ptr() } else { b.as_ptr() }, b.len()),
            None => (std::ptr::null(), 0),
        };
        say(ctx.0, text.as_ptr(), text.len(), b, blen);
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

    /// A connection kept for the core, and let go once it closes, however it does (closed here, by the other end, timed
    /// out): kept, a closed connection and the streams opened on it stayed in memory, iroh's tasks still going over
    /// them, and a phone whose links were replaced often held hundreds and grew gigabytes a minute (2026-10-19).
    fn keep_conn(self: &Arc<Self>, conn: Connection) -> u64 {
        let id = self.keep(Handle::Conn(conn.clone()));
        let inner = self.clone();
        tokio::spawn(async move {
            let reason = conn.closed().await;
            inner.release_conn(id, &reason);
        });
        id
    }

    /// A closed connection let go: what the core may still ask (`remoteId`, `closeReason`, `stats`) is kept, and its
    /// streams go, a read still waiting on one woken.
    fn release_conn(&self, id: u64, reason: &iroh::endpoint::ConnectionError) {
        let mut handles = self.handles.lock().unwrap();
        let gone = match handles.get(&id) {
            Some(Handle::Conn(conn)) => {
                let s = conn.stats();
                Handle::Gone { remote: hex::encode(conn.remote_id().as_bytes()), reason: close_info(reason), stats: json!({ "rxBytes": s.udp_rx.bytes, "txBytes": s.udp_tx.bytes }) }
            }
            _ => return,
        };
        handles.insert(id, gone);
        let streams: Vec<u64> = handles.iter().filter_map(|(k, h)| matches!(h, Handle::IStream(halves) if halves.conn == id).then_some(*k)).collect();
        for k in streams {
            if let Some(Handle::IStream(halves)) = handles.remove(&k) {
                let _ = halves.reset.send(true);
            }
        }
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
            "zstd.open" => Ok(Answer::json(json!({ "id": self.keep(Handle::Unzstd(Arc::new(Mutex::new(Unzstd::new()?)))) }))),
            "zstd.push" => {
                let Handle::Unzstd(z) = self.handle(id_of(&a)?)? else { return Err("not a zstd stream".into()) };
                let input = bytes.unwrap_or_default();
                let mut z = z.lock().unwrap();
                let out = z.take(&input)?;
                Ok(Answer::bytes(json!({ "whole": z.whole }), out))
            }
            "stream.close" | "ws.close" | "tcp.close" | "zstd.close" => {
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
                    // Synced through the handle it was written with: Windows syncs only a handle that may write (one
                    // opened again to read, as this did, failed every storage.set there).
                    let partial = path.with_extension("partial");
                    let mut file = std::fs::File::create(&partial).map_err(err)?;
                    std::io::Write::write_all(&mut file, &value).and_then(|()| file.sync_all()).map_err(err)?;
                    drop(file);
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
                let endpoint = match self.handle(id_of(&a)?)? {
                    Handle::Endpoint(endpoint, _) => endpoint,
                    Handle::Unbound { .. } => return Err("the endpoint is closed".into()),
                    _ => return Err("not an endpoint".into()),
                };
                let additional: Vec<Vec<u8>> = a.get("additional").and_then(Value::as_array).into_iter().flatten().filter_map(|x| hex::decode(x.as_str()?).ok()).collect();
                let options = iroh::endpoint::ConnectOptions::new().with_additional_alpns(additional);
                let addr = endpoint_addr(a.get("addr").ok_or("missing addr")?)?;
                let connecting = endpoint.connect_with_opts(addr, &bytes.unwrap_or_default(), options).await.map_err(err)?;
                let conn = connecting.await.map_err(err)?;
                Ok(Answer::json(json!({ "id": self.keep_conn(conn) })))
            }
            // As the station's addon takes them: handshakes side by side, each on its own, so one never finished (a
            // device gone half way) holds up no other; one that fails is skipped.
            "iroh.accept" => {
                let (endpoint, accepted) = match self.handle(id_of(&a)?)? {
                    Handle::Endpoint(endpoint, accepted) => (endpoint, accepted),
                    Handle::Unbound { .. } => return Ok(Answer::json(json!({ "end": true }))),
                    _ => return Err("not an endpoint".into()),
                };
                let mut accepted = accepted.lock().await;
                let done = accepted.get_or_insert_with(|| {
                    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
                    tokio::spawn(async move {
                        while let Some(incoming) = endpoint.accept().await {
                            let tx = tx.clone();
                            tokio::spawn(async move {
                                if let Ok(conn) = incoming.await {
                                    let _ = tx.send(conn);
                                }
                            });
                        }
                    });
                    rx
                });
                match done.recv().await {
                    Some(conn) => {
                        let alpn = hex::encode(conn.alpn());
                        Ok(Answer::json(json!({ "id": self.keep_conn(conn), "alpn": alpn })))
                    }
                    None => Ok(Answer::json(json!({ "end": true }))),
                }
            }
            "iroh.networkChange" => {
                let endpoint = match self.handle(id_of(&a)?)? {
                    Handle::Endpoint(endpoint, _) => endpoint,
                    Handle::Unbound { .. } => return Ok(Answer::json(json!({}))),
                    _ => return Err("not an endpoint".into()),
                };
                endpoint.network_change().await;
                Ok(Answer::json(json!({})))
            }
            "iroh.close" => {
                let id = id_of(&a)?;
                let endpoint = {
                    let mut handles = self.handles.lock().unwrap();
                    match handles.get(&id) {
                        Some(Handle::Endpoint(endpoint, _)) => {
                            let endpoint = endpoint.clone();
                            handles.insert(id, Handle::Unbound { id: hex::encode(endpoint.id().as_bytes()) });
                            Some(endpoint)
                        }
                        _ => None,
                    }
                };
                if let Some(endpoint) = endpoint {
                    endpoint.close().await;
                }
                Ok(Answer::json(json!({})))
            }
            "conn.openBi" | "conn.openUni" | "conn.acceptBi" => {
                let on = id_of(&a)?;
                let conn = match self.handle(on)? {
                    Handle::Conn(conn) => conn,
                    Handle::Gone { .. } if op == "conn.acceptBi" => return Ok(Answer::json(json!({ "end": true }))),
                    Handle::Gone { reason, .. } => return Err(format!("connection closed: {}", reason["reason"].as_str().unwrap_or(""))),
                    _ => return Err("not a connection".into()),
                };
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
                    conn: on,
                    ended: (recv.is_none()).into(),
                    finished: false.into(),
                    send: tokio::sync::Mutex::new(send),
                    recv: tokio::sync::Mutex::new(recv),
                    reset: tokio::sync::watch::channel(false).0,
                    tap: Mutex::default(),
                };
                Ok(Answer::json(json!({ "id": self.keep(Handle::IStream(Arc::new(halves))) })))
            }
            "conn.closed" => match self.handle(id_of(&a)?)? {
                Handle::Conn(conn) => Ok(Answer::json(close_info(&conn.closed().await))),
                Handle::Gone { reason, .. } => Ok(Answer::json(reason)),
                _ => Err("not a connection".into()),
            },
            "conn.close" => {
                let conn = match self.handle(id_of(&a)?)? {
                    Handle::Conn(conn) => conn,
                    Handle::Gone { .. } => return Ok(Answer::json(json!({}))),
                    _ => return Err("not a connection".into()),
                };
                let code = a.get("code").and_then(Value::as_u64).unwrap_or(0) as u32;
                conn.close(code.into(), a.get("reason").and_then(Value::as_str).unwrap_or("").as_bytes());
                Ok(Answer::json(json!({})))
            }
            "istream.tap" => {
                // A remote screen's view (`call` the app's): its frames read here from now on, beginning with `bytes`
                // (what the core read past the stream's reply); false where nothing says to the app from here.
                let Handle::IStream(halves) = self.handle(id_of(&a)?)? else { return Err("not a stream".into()) };
                let call = a.get("call").and_then(Value::as_u64).ok_or("no call")?;
                if self.say.lock().unwrap().is_none() {
                    return Ok(Answer::json(json!({ "tapped": false })));
                }
                let mut tap = ScreenTap { call, pending: Vec::new(), out: Vec::new(), told_video: false };
                tap.take(&bytes.unwrap_or_default(), &**self);
                *halves.tap.lock().unwrap() = Some(tap);
                tally("tap.views");
                Ok(Answer::json(json!({ "tapped": true })))
            }
            "istream.read" => {
                let id = id_of(&a)?;
                let Handle::IStream(halves) = self.handle(id)? else { return Err("not a stream".into()) };
                let mut reset = halves.reset.subscribe();
                if *reset.borrow() {
                    return Ok(Answer::json(json!({ "end": true })));
                }
                // tapped: read on here, saying what is the app's, until something is the core's (or the end)
                if halves.tap.lock().unwrap().is_some() {
                    let mut buf = vec![0u8; 64 * 1024];
                    loop {
                        {
                            let mut tap = halves.tap.lock().unwrap();
                            let tap = tap.as_mut().unwrap();
                            if !tap.out.is_empty() {
                                return Ok(Answer::bytes(json!({}), std::mem::take(&mut tap.out)));
                            }
                        }
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
                                let mut tap = halves.tap.lock().unwrap();
                                tap.as_mut().unwrap().take(&buf[..n], &**self);
                            }
                            None => {
                                // what is left (a frame cut short) the core's, which says so
                                let left = {
                                    let mut tap = halves.tap.lock().unwrap();
                                    let tap = tap.as_mut().unwrap();
                                    let mut left = std::mem::take(&mut tap.out);
                                    left.append(&mut tap.pending);
                                    left
                                };
                                if !left.is_empty() {
                                    return Ok(Answer::bytes(json!({}), left));
                                }
                                halves.ended.store(true, Ordering::Relaxed);
                                self.istream_done(id, &halves);
                                return Ok(Answer::json(json!({ "end": true })));
                            }
                        }
                    }
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
        let alpns: Vec<Vec<u8>> = a.get("alpns").and_then(Value::as_array).into_iter().flatten().map(|x| hex::decode(x.as_str().unwrap_or_default()).map_err(err)).collect::<Result<_, _>>()?;
        let mut builder = Endpoint::builder(Minimal)
            .secret_key(key)
            .alpns(alpns)
            .relay_mode(if relays.is_empty() { RelayMode::Disabled } else { RelayMode::Custom(iroh::RelayMap::from_iter(relays.clone())) })
            // Home on every relay at once, each path kept alive each second and given up after 3 s of silence: one
            // connection to a station goes through every relay it is on, and on through another as one goes (the
            // station's mesh addon: PATH_KEEP_ALIVE, PATH_IDLE).
            .home_on_every_relay()
            .transport_config(
                QuicTransportConfig::builder()
                    .congestion_controller_factory(Arc::new(cubic))
                    .default_path_keep_alive_interval(std::time::Duration::from_secs(1))
                    .default_path_max_idle_timeout(std::time::Duration::from_secs(3))
                    .build(),
            );
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
        Ok(Answer::json(json!({ "id": self.keep(Handle::Endpoint(endpoint, Accepted::default())) })))
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
                conn.busy_timeout(self.open_wait).map_err(err)?;
                conn.set_prepared_statement_cache_capacity(256);
                // One process at a time: another one finds it busy.
                conn.execute_batch("PRAGMA locking_mode = EXCLUSIVE; PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;").map_err(err)?;
                conn.busy_timeout(DB_WAIT).map_err(err)?;
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
        // The file a key's value is kept in, for what reads it there itself (a face's file: client/core-ts
        // font-files.ts); null while none is kept.
        if op == "storage.path" {
            let path = storage_path(&self.dir, str_of(a, "key")?);
            return Ok(if path.is_file() { json!(path.to_string_lossy()) } else { Value::Null });
        }
        // An Ed25519 key's public half and its signature of `message` (hex both ways): a lock claim's (client/core-ts
        // lock.ts), signed for each workspace and endpoint as the core connects. In Hermes (no JIT) the JS one took ~8 ms
        // each and longer the first time, on the core's thread before anything the UI had asked for.
        if op == "ed25519.sign" {
            let seed: [u8; 32] = hex::decode(str_of(a, "seed")?).map_err(err)?.try_into().map_err(|_| "the seed is not 32 bytes".to_string())?;
            let key = SecretKey::from_bytes(&seed);
            let message = hex::decode(str_of(a, "message")?).map_err(err)?;
            return Ok(json!({ "publicKey": hex::encode(key.public().as_bytes()), "signature": hex::encode(key.sign(&message).to_bytes()) }));
        }
        let handle = self.handle(id_of(a)?)?;
        match (op, handle) {
            ("iroh.endpointId", Handle::Endpoint(e, _)) => Ok(json!(hex::encode(e.id().as_bytes()))),
            ("iroh.addAddr", Handle::Endpoint(e, _)) => {
                let addr = endpoint_addr(a.get("addr").ok_or("missing addr")?)?;
                e.address_lookup().map_err(err)?.add(iroh::address_lookup::MemoryLookup::from_endpoint_info([addr]));
                Ok(Value::Null)
            }
            ("iroh.relayStatus", Handle::Endpoint(e, _)) => Ok(Value::Array(e.home_relay_status().get().iter().map(|s| json!({ "url": s.url().to_string(), "connected": s.is_connected() })).collect())),
            ("conn.remoteId", Handle::Conn(c)) => Ok(json!(hex::encode(c.remote_id().as_bytes()))),
            ("conn.closeReason", Handle::Conn(c)) => Ok(c.close_reason().map(|e| close_info(&e)).unwrap_or(Value::Null)),
            ("conn.paths", Handle::Conn(c)) => Ok(Value::Array(
                c.paths()
                    .iter()
                    .map(|p| {
                        let (relay, ip) = match p.remote_addr() {
                            iroh::TransportAddr::Relay(url) => (Some(url.to_string()), None),
                            iroh::TransportAddr::Ip(addr) => (None, Some(addr.to_string())),
                            _ => (None, None),
                        };
                        // Packets sent and lost on this way alone: the connection's counts take in every way it tried.
                        let stats = p.stats();
                        json!({ "id": p.id().to_string(), "selected": p.is_selected(), "relay": relay, "ip": ip, "rttMs": stats.rtt.as_secs_f64() * 1000.0, "txPackets": stats.udp_tx.datagrams, "lostPackets": stats.lost_packets })
                    })
                    .collect(),
            )),
            ("conn.stats", Handle::Conn(c)) => {
                let s = c.stats();
                Ok(json!({ "rxBytes": s.udp_rx.bytes, "txBytes": s.udp_tx.bytes }))
            }
            ("conn.remoteId", Handle::Gone { remote, .. }) => Ok(json!(remote)),
            ("conn.closeReason", Handle::Gone { reason, .. }) => Ok(reason),
            ("conn.paths", Handle::Gone { .. }) => Ok(json!([])),
            ("conn.stats", Handle::Gone { stats, .. }) => Ok(stats),
            ("iroh.endpointId", Handle::Unbound { id }) => Ok(json!(id)),
            ("iroh.addAddr", Handle::Unbound { .. }) => Ok(Value::Null),
            ("iroh.relayStatus", Handle::Unbound { .. }) => Ok(json!([])),
            (op, _) => Err(format!("no operation {op} on that handle")),
        }
    }
}

/// How long a statement on an account's database waits while another connection holds it.
const DB_WAIT: std::time::Duration = std::time::Duration::from_secs(5);

/// How long an account's database is waited for as it is opened: as long as a statement, but none in a window of the
/// app's own (MBUI_WINDOW: a run started beside the app's, which holds them all as long as it runs). That run keeps
/// them in memory at once (the core's data.ts), where it waited 5 s for each and every one before: its window showed
/// nothing for 15 s (2026-10-29 用户: 独立窗口要等很久才显示内容).
fn open_wait() -> std::time::Duration {
    if std::env::var_os("MBUI_WINDOW").is_some_and(|w| !w.is_empty()) {
        std::time::Duration::ZERO
    } else {
        DB_WAIT
    }
}

impl Shell {
    pub fn start(dir: PathBuf, complete: Complete, ctx: *mut c_void) -> std::io::Result<Shell> {
        Shell::start_waiting(dir, complete, ctx, open_wait())
    }

    fn start_waiting(dir: PathBuf, complete: Complete, ctx: *mut c_void, open_wait: std::time::Duration) -> std::io::Result<Shell> {
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
        let inner = Arc::new(Inner { complete, ctx: Ctx(ctx), dir, disk: Mutex::new(jobs), db, tls, http, handles: Mutex::default(), next: AtomicU64::new(1), sqls: Mutex::default(), open_wait, say: Mutex::default(), media: Mutex::default() });
        STATS.lock().unwrap().shells.push(Arc::downgrade(&inner));
        Ok(Shell { runtime, inner })
    }

    pub fn call(&self, id: u64, op: String, json: &[u8], bytes: Option<Vec<u8>>) {
        let inner = self.inner.clone();
        let args: Value = serde_json::from_slice(json).unwrap_or(Value::Null);
        counted(&op, true);
        self.runtime.spawn(async move {
            let done = inner.run(&op, args, bytes).await;
            counted(&op, false);
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
        counted(op, true);
        counted(op, false);
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

/// What the shells have been asked so far (`{calls: {op: [started, unanswered]}, handles: {kind: n}, sqls}`), as JSON
/// to be let go with `sf_free`.
///
/// # Safety
/// `out_len` is written.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sf_shell_stats(out_len: *mut usize) -> *mut u8 {
    let mut out = serde_json::to_vec(&stats_json()).unwrap_or_default().into_boxed_slice();
    unsafe { *out_len = out.len() };
    let ptr = out.as_mut_ptr();
    std::mem::forget(out);
    ptr
}

/// # Safety
/// `ptr`/`len` from `sf_shell_call_sync` or `sf_shell_stats`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sf_free(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        // SAFETY: made by `sf_shell_call_sync` from a boxed slice of this length.
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)) });
    }
}

/// Where a message for the app goes straight from the shell (a remote screen's frames, `istream.tap`): `say` with
/// `ctx`, from any of the shell's threads, until `sf_shell_stop`.
///
/// # Safety
/// `shell` from `sf_shell_start`; `say` may be called with `ctx` from any thread.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sf_shell_set_say(shell: *const Shell, say: Say, ctx: *mut c_void) {
    // SAFETY: made by `sf_shell_start`.
    let shell = unsafe { &*shell };
    *shell.inner.say.lock().unwrap() = Some((say, Ctx(ctx)));
}

/// Where a tapped remote screen's records are offered before they are said to the app (`Media`): `media` with `ctx`,
/// from any of the shell's threads, until `sf_shell_stop`.
///
/// # Safety
/// `shell` from `sf_shell_start`; `media` may be called with `ctx` from any thread.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sf_shell_set_media(shell: *const Shell, media: Media, ctx: *mut c_void) {
    // SAFETY: made by `sf_shell_start`.
    let shell = unsafe { &*shell };
    *shell.inner.media.lock().unwrap() = Some((media, Ctx(ctx)));
}

/// A remote screen's frame `ts` acknowledged by the app straight to the station, on the stream its view `call` is
/// tapped on (`istream.tap`), not through the core (an ack frame: screen-frames.ts ackFrame); 0 when no tapped stream
/// is that view's (the app asks the core then).
///
/// # Safety
/// `shell` from `sf_shell_start`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sf_shell_screen_ack(shell: *const Shell, call: u64, ts: f64) -> u8 {
    // SAFETY: made by `sf_shell_start`.
    let shell = unsafe { &*shell };
    let halves = shell.inner.handles.lock().unwrap().values().find_map(|h| match h {
        Handle::IStream(halves) if halves.tap.lock().unwrap().as_ref().is_some_and(|t| t.call == call) => Some(halves.clone()),
        _ => None,
    });
    let Some(halves) = halves else { return 0 };
    let mut frame = vec![17u8, 0, 0, 0, 8];
    frame.extend_from_slice(&(ts.max(0.0).floor() as u64).to_be_bytes());
    tally("tap.acks");
    shell.runtime.spawn(async move {
        if let Some(send) = halves.send.lock().await.as_mut() {
            let _ = send.write_all(&frame).await;
        }
    });
    1
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
#[cfg(not(windows))]
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

/// The same on Windows (the mbui app's core), whose C library has neither localtime_r nor tm_gmtoff: the local time the
/// CRT makes of `at_ms` (the system's zone and its DST rules, or $TZ when set), read back as if it were UTC, less
/// `at_ms`. 0 where the CRT has no local time (before 1970).
#[cfg(windows)]
#[unsafe(no_mangle)]
pub extern "C" fn sf_utc_offset_min(at_ms: f64) -> i32 {
    unsafe extern "C" {
        fn _localtime64_s(tm: *mut libc::tm, time: *const i64) -> i32;
        fn _mkgmtime64(tm: *mut libc::tm) -> i64;
    }
    let at = (at_ms / 1000.0).floor() as i64;
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    // SAFETY: both pointers are valid for the calls.
    if unsafe { _localtime64_s(&mut tm, &at) } != 0 {
        return 0;
    }
    let local_as_utc = unsafe { _mkgmtime64(&mut tm) };
    if local_as_utc == -1 {
        return 0;
    }
    ((local_as_utc - at) / 60) as i32
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Condvar, Mutex as StdMutex};

    fn frame(kind: u8, body: &[u8]) -> Vec<u8> {
        let mut f = vec![kind];
        f.extend_from_slice(&(body.len() as u32).to_be_bytes());
        f.extend_from_slice(body);
        f
    }

    /// What a tapped view offered its host and said to the app; the host takes the kinds in `takes`.
    #[derive(Default)]
    struct Told {
        takes: Vec<u8>,
        offered: StdMutex<Vec<(u64, u8, bool, u64, u64, usize)>>,
        said: StdMutex<Vec<(Value, Option<Vec<u8>>)>>,
    }

    impl Tell for Told {
        fn media(&self, call: u64, kind: u8, key: bool, seq: u64, ts: u64, bytes: &[u8]) -> bool {
            self.offered.lock().unwrap().push((call, kind, key, seq, ts, bytes.len()));
            self.takes.contains(&kind)
        }
        fn say(&self, json: &[u8], bytes: Option<&[u8]>) {
            self.said.lock().unwrap().push((serde_json::from_slice(json).unwrap(), bytes.map(<[u8]>::to_vec)));
        }
    }

    fn screen_wire() -> (Vec<u8>, Vec<u8>) {
        let config = frame(FRAME_CONFIG, br#"{"codec":"h264","width":1919.6,"height":1080,"description":"AQID","region":{"x":0.5,"y":0,"w":0.5,"h":0.5}}"#);
        let mut video = vec![1u8];
        video.extend_from_slice(&5u64.to_be_bytes());
        video.extend_from_slice(b"pic");
        let mut later = vec![0u8];
        later.extend_from_slice(&6u64.to_be_bytes());
        later.extend_from_slice(b"pic2");
        let mut audio = 9u64.to_be_bytes().to_vec();
        audio.extend_from_slice(&[0u8; 3840]);
        let state = frame(3, br#"{"cursor":null}"#);
        let mut wire = config.clone();
        for f in [frame(FRAME_VIDEO, &video), frame(FRAME_VIDEO, &later), frame(FRAME_AUDIO, &audio), state.clone()] {
            wire.extend(f);
        }
        // the core's: the config, the first video frame's head alone, the state
        let mut core = config;
        core.extend(frame(FRAME_VIDEO, &video[..9]));
        core.extend(state);
        (wire, core)
    }

    #[test]
    fn a_tapped_screen_says_its_picture_and_sound_and_keeps_the_rest_for_the_core() {
        let told = Told::default();
        let mut tap = ScreenTap { call: 7, pending: Vec::new(), out: Vec::new(), told_video: false };
        let (wire, core) = screen_wire();
        // cut anywhere
        for piece in wire.chunks(7) {
            tap.take(piece, &told);
        }
        let said = told.said.into_inner().unwrap();
        let offered = told.offered.into_inner().unwrap();
        // each offered the host first, in order, numbered one after another; none taken there
        assert_eq!(offered.iter().map(|o| (o.0, o.1, o.2, o.4, o.5)).collect::<Vec<_>>(), vec![(7, FRAME_CONFIG, false, 0, 0), (7, FRAME_VIDEO, true, 5, 3), (7, FRAME_VIDEO, false, 6, 4), (7, FRAME_AUDIO, false, 9, 3840)]);
        let n: Vec<u64> = offered.iter().map(|o| o.3).collect();
        assert!(n.windows(2).all(|w| w[1] > w[0]));
        assert_eq!(said.len(), 4);
        assert_eq!(said[0].0, json!({ "id": 7, "value": { "config": { "codec": "h264", "width": 1920.0, "height": 1080.0, "region": { "x": 0.5, "y": 0.0, "w": 0.5, "h": 0.5 } } } }));
        assert_eq!(said[0].1.as_deref(), Some(&[1u8, 2, 3][..]));
        assert_eq!(said[1].0, json!({ "id": 7, "value": { "frame": { "key": true, "ts": 5, "n": n[1] } } }));
        assert_eq!(said[1].1.as_deref(), Some(&b"pic"[..]));
        assert_eq!(said[2].0, json!({ "id": 7, "value": { "frame": { "key": false, "ts": 6, "n": n[2] } } }));
        assert_eq!(said[3].0, json!({ "id": 7, "value": { "audio": { "ts": 9, "n": n[3] } } }));
        assert_eq!(said[3].1.as_ref().map(Vec::len), Some(3840));
        assert_eq!(tap.out, core);
        assert!(tap.pending.is_empty());
        // as it came whole, or a frame cut across two pieces: the same
        for cut in [wire.len(), wire.len() - 3] {
            let told = Told::default();
            let mut again = ScreenTap { call: 7, pending: Vec::new(), out: Vec::new(), told_video: false };
            again.take(&wire[..cut], &told);
            again.take(&wire[cut..], &told);
            assert_eq!((told.said.lock().unwrap().len(), &again.out, again.pending.len()), (4, &core, 0));
        }
    }

    #[test]
    fn what_the_host_takes_of_a_tapped_screen_is_not_said() {
        // the host decodes and plays the frames and the sound itself: only the config said, the core's kept the same
        let told = Told { takes: vec![FRAME_VIDEO, FRAME_AUDIO], ..Told::default() };
        let mut tap = ScreenTap { call: 3, pending: Vec::new(), out: Vec::new(), told_video: false };
        let (wire, core) = screen_wire();
        tap.take(&wire, &told);
        let said = told.said.into_inner().unwrap();
        assert_eq!(said.len(), 1);
        assert!(said[0].0["value"]["config"].is_object());
        assert_eq!(told.offered.lock().unwrap().len(), 4);
        assert_eq!(tap.out, core);
    }

    static ANSWERS: StdMutex<Vec<(u64, String, String, Option<Vec<u8>>)>> = StdMutex::new(Vec::new());
    static ANSWERED: Condvar = Condvar::new();

    extern "C" fn complete(_: *mut c_void, id: u64, json: *const u8, jl: usize, e: *const u8, el: usize, b: *const u8, bl: usize, has: u8) {
        let s = |p: *const u8, l: usize| if l == 0 { String::new() } else { String::from_utf8_lossy(unsafe { std::slice::from_raw_parts(p, l) }).into_owned() };
        let bytes = (has != 0).then(|| if bl == 0 { Vec::new() } else { unsafe { std::slice::from_raw_parts(b, bl) }.to_vec() });
        ANSWERS.lock().unwrap().push((id, s(json, jl), s(e, el), bytes));
        ANSWERED.notify_all();
    }

    /// A directory of its own under the system's temporary one, removed when dropped (after the shell started in it,
    /// made after it). Not tempfile's: a dev-dependency gives the tests' build other features of the crates below it, so
    /// that build compiled iroh and the rest a second time (the Windows shell's prebuild, 2026-10-23).
    struct TempDir(PathBuf);
    impl TempDir {
        fn new() -> Self {
            static N: AtomicU64 = AtomicU64::new(0);
            let dir = std::env::temp_dir().join(format!("stillfail-shell-test-{}-{}", std::process::id(), N.fetch_add(1, Ordering::Relaxed)));
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(&dir).unwrap();
            TempDir(dir)
        }
        fn path(&self) -> &std::path::Path {
            &self.0
        }
    }
    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
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
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().to_path_buf(), complete, std::ptr::null_mut()).unwrap();
        shell.call(1, "storage.set".into(), br#"{"key":"device"}"#, Some(vec![1, 2, 3]));
        assert_eq!(answer(1).1, "");
        assert!(dir.path().join("device").exists());
        shell.call(2, "storage.get".into(), br#"{"key":"device"}"#, None);
        assert_eq!(answer(2).2, Some(vec![1, 2, 3]));
        shell.call(3, "storage.get".into(), br#"{"key":"a/b"}"#, None);
        assert_eq!(answer(3).0, r#"{"none":true}"#);
        // Where a value is kept, read there by the app itself: none while it is not.
        let path = |key: &str| -> Value { serde_json::from_slice::<Value>(&shell.call_sync("storage.path", format!(r#"{{"key":"{key}"}}"#).as_bytes())).unwrap()["value"].clone() };
        assert_eq!(path("device"), json!(dir.path().join("device").to_string_lossy()));
        assert_eq!(path("a/b"), Value::Null);
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
    fn takes_zstd_apart_a_piece_at_a_time() {
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().to_path_buf(), complete, std::ptr::null_mut()).unwrap();
        // A reply as a station compresses it (two frames, as a stream flushed twice sends them, and a JSON reply),
        // given in pieces cut anywhere.
        let first: Vec<u8> = (0..40_000).map(|i| format!("{{\"seq\":{i}}},")).collect::<String>().into_bytes();
        let second = b"{\"entries\":[]}".to_vec();
        let mut packed = zstd::stream::encode_all(&first[..], 3).unwrap();
        packed.extend(zstd::stream::encode_all(&second[..], 9).unwrap());
        shell.call(9001, "zstd.open".into(), b"{}", None);
        let id = serde_json::from_str::<Value>(&answer(9001).0).unwrap()["id"].as_u64().unwrap();
        let mut made = Vec::new();
        let mut call = 9002;
        let mut whole = Vec::new();
        for piece in packed.chunks(7_001) {
            shell.call(call, "zstd.push".into(), format!(r#"{{"id":{id}}}"#).as_bytes(), Some(piece.to_vec()));
            let (json, error, bytes) = answer(call);
            assert_eq!(error, "");
            made.extend(bytes.unwrap_or_default());
            whole.push(serde_json::from_str::<Value>(&json).unwrap()["whole"] == json!(true));
            call += 1;
        }
        let mut both = first.clone();
        both.extend(&second);
        assert_eq!(made, both);
        // mid frame, not whole; at the end, whole
        assert!(!whole[0]);
        assert!(whole[whole.len() - 1]);
        shell.call(call, "zstd.close".into(), format!(r#"{{"id":{id}}}"#).as_bytes(), None);
        assert_eq!(answer(call).1, "");
        // gone once closed
        shell.call(call + 1, "zstd.push".into(), format!(r#"{{"id":{id}}}"#).as_bytes(), Some(vec![0]));
        assert_eq!(answer(call + 1).1, format!("no handle {id}"));
        // cut short: what came is given, and it is not whole
        let cut = zstd::stream::encode_all(&first[..], 3).unwrap();
        shell.call(call + 2, "zstd.open".into(), b"{}", None);
        let id = serde_json::from_str::<Value>(&answer(call + 2).0).unwrap()["id"].as_u64().unwrap();
        shell.call(call + 3, "zstd.push".into(), format!(r#"{{"id":{id}}}"#).as_bytes(), Some(cut[..cut.len() - 1].to_vec()));
        let (json, error, bytes) = answer(call + 3);
        assert_eq!(error, "");
        assert!(first.starts_with(&bytes.unwrap_or_default()));
        assert_eq!(serde_json::from_str::<Value>(&json).unwrap()["whole"], json!(false));
        // and what is not zstd fails
        shell.call(call + 4, "zstd.open".into(), b"{}", None);
        let id = serde_json::from_str::<Value>(&answer(call + 4).0).unwrap()["id"].as_u64().unwrap();
        shell.call(call + 5, "zstd.push".into(), format!(r#"{{"id":{id}}}"#).as_bytes(), Some(b"not zstd at all".to_vec()));
        assert_ne!(answer(call + 5).1, "");
    }

    #[test]
    fn keeps_an_accounts_database() {
        let dir = TempDir::new();
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

    #[test]
    fn a_window_of_its_own_finds_an_accounts_database_held_busy_at_once() {
        let dir = TempDir::new();
        let app = Shell::start_waiting(dir.path().to_path_buf(), complete, std::ptr::null_mut(), DB_WAIT).unwrap();
        let window = Shell::start_waiting(dir.path().to_path_buf(), complete, std::ptr::null_mut(), std::time::Duration::ZERO).unwrap();
        let sync = |shell: &Shell, op: &str, json: &str| -> Value { serde_json::from_slice(&shell.call_sync(op, json.as_bytes())).unwrap() };
        assert!(sync(&app, "sql.open", r#"{"name":"account-a"}"#)["value"]["id"].is_u64());
        // held by the app's run: busy, said at once (not after DB_WAIT)
        let asked = std::time::Instant::now();
        let busy = sync(&window, "sql.open", r#"{"name":"account-a"}"#);
        assert!(busy["error"].as_str().unwrap().contains("locked"), "{busy}");
        assert!(asked.elapsed() < DB_WAIT / 5, "{:?}", asked.elapsed());
        // one no one holds: opened as ever
        assert!(sync(&window, "sql.open", r#"{"name":"account-b"}"#)["value"]["id"].is_u64());
    }

    #[test]
    fn signs_with_an_ed25519_seed() {
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().to_path_buf(), complete, std::ptr::null_mut()).unwrap();
        let sync = |op: &str, json: &str| -> Value { serde_json::from_slice(&shell.call_sync(op, json.as_bytes())).unwrap() };
        // RFC 8032's test 2
        let signed = sync("ed25519.sign", r#"{"seed":"4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb","message":"72"}"#);
        assert_eq!(signed["value"]["publicKey"], json!("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"));
        assert_eq!(
            signed["value"]["signature"],
            json!("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00")
        );
        assert!(sync("ed25519.sign", r#"{"seed":"4ccd","message":"72"}"#)["error"].is_string());
    }

    #[test]
    fn counts_calls_by_operation() {
        counted("test.op", true);
        counted("test.op", true);
        counted("test.op", false);
        let stats = stats_json();
        assert_eq!(stats["calls"]["test.op"], json!([2, 1]));
    }

    #[test]
    fn answers_of_a_closed_endpoint() {
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().to_path_buf(), complete, std::ptr::null_mut()).unwrap();
        let inner = shell.inner.clone();
        shell.runtime.block_on(async move {
            let endpoint = Endpoint::builder(Minimal).relay_mode(RelayMode::Disabled).bind().await.unwrap();
            let id = inner.keep(Handle::Endpoint(endpoint.clone(), Accepted::default()));
            inner.run("iroh.close", json!({ "id": id }), None).await.unwrap();
            // A dial on it failing after another was bound in its place asks it still (the app's core died of "no handle 3").
            assert_eq!(inner.run_sync("iroh.endpointId", &json!({ "id": id })).unwrap(), json!(hex::encode(endpoint.id().as_bytes())));
            assert_eq!(inner.run_sync("iroh.relayStatus", &json!({ "id": id })).unwrap(), json!([]));
            assert_eq!(inner.run("iroh.accept", json!({ "id": id }), None).await.unwrap().json, json!({ "end": true }));
            let addr = json!({ "id": hex::encode(endpoint.id().as_bytes()), "ips": ["127.0.0.1:1"] });
            assert!(inner.run("iroh.connect", json!({ "id": id, "addr": addr }), Some(b"stillfail/test".to_vec())).await.is_err());
            assert!(inner.run("iroh.close", json!({ "id": id }), None).await.is_ok());
        });
    }

    #[test]
    fn lets_a_closed_connection_and_its_streams_go() {
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().to_path_buf(), complete, std::ptr::null_mut()).unwrap();
        let inner = shell.inner.clone();
        shell.runtime.block_on(async move {
            let alpn = b"stillfail/test".to_vec();
            let bind = |alpns: Vec<Vec<u8>>| Endpoint::builder(Minimal).relay_mode(RelayMode::Disabled).alpns(alpns).bind();
            let (a, b) = (bind(vec![]).await.unwrap(), bind(vec![alpn.clone()]).await.unwrap());
            let port = b.bound_sockets().iter().find(|s| s.is_ipv4()).unwrap().port();
            let addr = endpoint_addr(&json!({ "id": hex::encode(b.id().as_bytes()), "ips": [format!("127.0.0.1:{port}")] })).unwrap();
            // The other end kept, so its close is sent rather than its endpoint gone.
            let taking = b.clone();
            let taken = tokio::spawn(async move { taking.accept().await.unwrap().await.unwrap() });
            let id = inner.keep_conn(a.connect(addr, &alpn).await.unwrap());
            let theirs = taken.await.unwrap();
            let opened = inner.run("conn.openBi", json!({ "id": id }), None).await.unwrap();
            let stream = opened.json["id"].as_u64().unwrap();
            assert!(matches!(inner.handle(stream), Ok(Handle::IStream(_))));
            let remote = inner.run_sync("conn.remoteId", &json!({ "id": id })).unwrap();
            theirs.close(7u32.into(), b"bye");
            for _ in 0..200 {
                if matches!(inner.handle(id), Ok(Handle::Gone { .. })) {
                    break;
                }
                tokio::time::sleep(std::time::Duration::from_millis(10)).await;
            }
            // Let go, its stream with it; what the core asks after still answers.
            assert!(matches!(inner.handle(id), Ok(Handle::Gone { .. })));
            assert!(inner.handle(stream).is_err());
            assert_eq!(inner.run_sync("conn.closeReason", &json!({ "id": id })).unwrap(), json!({ "kind": "application", "reason": "bye" }));
            assert_eq!(inner.run_sync("conn.remoteId", &json!({ "id": id })).unwrap(), remote);
            assert_eq!(inner.run_sync("conn.paths", &json!({ "id": id })).unwrap(), json!([]));
            assert_eq!(inner.run("conn.closed", json!({ "id": id }), None).await.unwrap().json, json!({ "kind": "application", "reason": "bye" }));
            assert!(inner.run("conn.openBi", json!({ "id": id }), None).await.is_err());
            assert_eq!(inner.run("conn.acceptBi", json!({ "id": id }), None).await.unwrap().json, json!({ "end": true }));
        });
    }
}
