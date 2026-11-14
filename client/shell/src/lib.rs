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

use std::collections::{BTreeMap, HashMap};
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

mod adb;
mod keep;

const MDNS_SERVICE: &str = "stillfail";

/// The nodes a DHT starts from: n0-mainline's defaults, with ours (cloud/dht-node, on the relays' machines) in place of relay.pkarr.org.
fn dht() -> n0_mainline::DhtBuilder {
    let mut dht = n0_mainline::DhtBuilder::default();
    dht.bootstrap(&[
        "router.bittorrent.com:6881",
        "dht.transmissionbt.com:6881",
        "dht.libtorrent.org:25401",
        "39.105.157.122:6881",
        "47.79.40.84:6881",
        "120.24.233.158:6881",
    ]);
    dht
}

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

/// A file being read a part at a time (`text.open`).
struct TextReader {
    source: Box<dyn std::io::Read + Send>,
    /// Read and not given yet.
    held: Vec<u8>,
    lines: bool,
    done: bool,
}

/// How much of a file a part holds at most, past a line's end (counter.ts CHUNK).
const TEXT_PART: usize = 8 << 20;

impl TextReader {
    fn fill(&mut self, want: usize) {
        while !self.done && self.held.len() < want {
            let mut buf = vec![0u8; (want - self.held.len()).max(64 << 10)];
            match self.source.read(&mut buf) {
                Ok(0) | Err(_) => self.done = true,
                Ok(n) => self.held.extend_from_slice(&buf[..n]),
            }
        }
    }

    fn next(&mut self) -> Option<String> {
        self.fill(TEXT_PART);
        if self.lines {
            // (a part ends at the last line end in its window, else at the first after it, as counter.ts `partsOf`)
            let window = self.held.len().min(TEXT_PART);
            let cut = match self.held[..window].iter().rposition(|&b| b == b'\n') {
                Some(i) => i,
                None => loop {
                    if let Some(i) = self.held.iter().position(|&b| b == b'\n') {
                        break i;
                    }
                    if self.done {
                        return None;
                    }
                    let more = self.held.len() + TEXT_PART;
                    self.fill(more);
                },
            };
            let part: Vec<u8> = self.held.drain(..=cut).collect();
            return Some(String::from_utf8_lossy(&part).into_owned());
        }
        if self.held.is_empty() {
            return None;
        }
        // (a piece ends where a character does, but at the end)
        let mut end = self.held.len().min(TEXT_PART);
        if end < self.held.len() || !self.done {
            let mut back = 0;
            while back < 3 && end > back && (self.held[end - 1 - back] & 0xc0) == 0x80 {
                back += 1;
            }
            if end > back && self.held[end - 1 - back] >= 0xc0 {
                let lead = self.held[end - 1 - back];
                let len = if lead >= 0xf0 { 4 } else if lead >= 0xe0 { 3 } else { 2 };
                if back + 1 < len {
                    end -= back + 1;
                }
            }
        }
        if end == 0 {
            end = self.held.len();
        }
        let piece: Vec<u8> = self.held.drain(..end).collect();
        Some(String::from_utf8_lossy(&piece).into_owned())
    }
}

/// `path` made absolute and its `.` and `..` taken out by their names alone, as Node's path.resolve does.
fn lexical(path: &std::path::Path) -> PathBuf {
    use std::path::Component;
    let mut out = PathBuf::new();
    for c in path.components() {
        match c {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            c => out.push(c),
        }
    }
    out
}

/// A link's target without Windows' `\\?\` (as libuv's readlink gives it).
fn plain(target: PathBuf) -> PathBuf {
    let s = target.to_string_lossy().into_owned();
    if let Some(rest) = s.strip_prefix(r"\\?\UNC\") {
        PathBuf::from(format!(r"\\{rest}"))
    } else if let Some(rest) = s.strip_prefix(r"\\?\") {
        PathBuf::from(rest)
    } else {
        target
    }
}

/// Node's realpathSync (lib/fs.js, its JavaScript one): the path resolved, then each part from the root looked at
/// (lstat) and a link replaced by its target resolved against the parts before it, again from the root.
fn node_realpath(path: &str) -> std::io::Result<String> {
    use std::path::Component;
    let mut path = lexical(&std::path::absolute(path)?);
    let mut links = 0;
    'again: loop {
        let parts: Vec<Component> = path.components().collect();
        let mut done = PathBuf::new();
        for (i, part) in parts.iter().enumerate() {
            if !matches!(part, Component::Normal(_)) {
                done.push(part);
                continue;
            }
            let next = done.join(part);
            if std::fs::symlink_metadata(&next)?.file_type().is_symlink() {
                links += 1;
                if links > 256 {
                    return Err(std::io::Error::other("too many links"));
                }
                let mut resolved = lexical(&done.join(plain(std::fs::read_link(&next)?)));
                for rest in &parts[i + 1..] {
                    resolved.push(rest);
                }
                path = resolved;
                continue 'again;
            }
            done = next;
        }
        return Ok(done.to_string_lossy().into_owned());
    }
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
/// config (what tells the core the picture is live). Sound that comes as Opus (a view asked it: client/core-ts mesh.ts
/// `decodesOpus`) is decoded here, each packet into the 20 ms of PCM16 the hosts play, and said to the app as PCM.
struct ScreenTap {
    /// the app's call the view is (its progress' id)
    call: u64,
    /// what came and is not a whole frame yet
    pending: Vec<u8>,
    /// frames for the core, whole
    out: Vec<u8>,
    /// a video frame's head given the core since the last config
    told_video: bool,
    /// the view's sound is Opus (its config said so): what decodes it, and the capture time the next packet follows
    /// on from (0: none decoded since it was made)
    opus: Option<Box<opus_rs::OpusDecoder>>,
    opus_next: u64,
}

const FRAME_CONFIG: u8 = 1;
const FRAME_VIDEO: u8 = 2;
const FRAME_AUDIO_CONFIG: u8 = 5;
const FRAME_AUDIO: u8 = 6;
/// A frame longer than this is no frame (screen-frames.ts MAX_FRAME): left to the core, which says so.
const FRAME_MAX: usize = 64 * 1024 * 1024;
/// A packet of sound as the hosts play it: 960 frames of interleaved stereo PCM16 (20 ms at 48 kHz); the longest Opus
/// packet (RFC 6716 3.2.1).
const PCM_PACKET: usize = 3840;
const OPUS_MAX: usize = 1275;
/// A packet's capture time this far (µs) from where the last one ended still follows on from it: half a packet (the
/// sources that encode Opus give each packet of a run its time 20 ms on from the last exactly: the Helper's
/// AudioPackets, stillfail-screen's Runs); one further is after a gap (packets left out before the round trip was
/// known, while muted, silence not sent), decoded by a decoder made anew, as its encoder was.
const OPUS_SLACK: u64 = 10_000;

impl ScreenTap {
    fn new(call: u64) -> Self {
        ScreenTap { call, pending: Vec::new(), out: Vec::new(), told_video: false, opus: None, opus_next: 0 }
    }

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
            FRAME_AUDIO if body.len() > 8 && (if self.opus.is_some() { body.len() <= 8 + OPUS_MAX } else { body.len() == 8 + PCM_PACKET }) => {
                let ts = u64::from_be_bytes(body[..8].try_into().unwrap());
                let mut decoded = [0u8; PCM_PACKET];
                let pcm = match &mut self.opus {
                    None => &body[8..],
                    Some(decoder) => {
                        if self.opus_next != 0 && ts.abs_diff(self.opus_next) > OPUS_SLACK {
                            match opus_rs::OpusDecoder::new(48_000, 2) {
                                Ok(fresh) => **decoder = fresh,
                                Err(_) => return true,
                            }
                            tally("tap.audio.resumed");
                        }
                        let mut samples = [0f32; PCM_PACKET / 2];
                        // (one that does not decode to 20 ms is none: the sound goes on with the next, its decoder made
                        // anew; a panic of the decoder on bytes the station sent is that too, not the end of the view)
                        let packet = &body[8..];
                        let decoded_n = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| decoder.decode(packet, PCM_PACKET / 4, &mut samples)));
                        match decoded_n {
                            Ok(Ok(n)) if n * 4 == PCM_PACKET => self.opus_next = ts + 20_000,
                            _ => {
                                self.opus_next = 0;
                                if let Ok(fresh) = opus_rs::OpusDecoder::new(48_000, 2) {
                                    **decoder = fresh;
                                }
                                tally("tap.audio.undecoded");
                                return true;
                            }
                        }
                        for (i, v) in samples.iter().enumerate() {
                            let v = if v.is_finite() { (v.clamp(-1.0, 1.0) * 32767.0).round() as i16 } else { 0 };
                            decoded[i * 2..i * 2 + 2].copy_from_slice(&v.to_le_bytes());
                        }
                        &decoded[..]
                    }
                };
                let n = MEDIA_SEQ.fetch_add(1, Ordering::Relaxed);
                if tell.media(id, FRAME_AUDIO, false, n, ts, pcm) {
                    tally("tap.direct.audio");
                } else {
                    let text = format!(r#"{{"id":{id},"value":{{"audio":{{"ts":{ts},"n":{n}}}}}}}"#);
                    tell.say(text.as_bytes(), Some(pcm));
                }
                tally("tap.audio");
                true
            }
            FRAME_AUDIO_CONFIG => {
                let Ok(c) = serde_json::from_slice::<Value>(body) else { return false };
                let codec = c.get("codec").and_then(Value::as_str);
                if !matches!(codec, Some("pcm_s16le" | "opus")) || c.get("sampleRate").and_then(Value::as_f64) != Some(48000.0) || c.get("channels").and_then(Value::as_f64) != Some(2.0) {
                    return false;
                }
                // (the app is told PCM either way: what it plays is what is said from here)
                self.opus = None;
                self.opus_next = 0;
                if codec == Some("opus") {
                    match opus_rs::OpusDecoder::new(48_000, 2) {
                        Ok(decoder) => self.opus = Some(Box::new(decoder)),
                        Err(_) => return false,
                    }
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

/// What an endpoint keeps beside iroh's own: the connections whose handshakes are done (`iroh.accept`); a station's
/// keepers on relays it is not home on (`iroh.keep`), and those it is home on (bound with); the next connections to come
/// held unanswered, not even their handshake (`iroh.holdIncoming`), and those held.
#[derive(Default)]
struct Kept {
    accepted: Accepted,
    keepers: Mutex<HashMap<String, tokio::task::JoinHandle<()>>>,
    homes: Vec<RelayUrl>,
    held: Mutex<(u32, Vec<iroh::endpoint::Incoming>)>,
}

/// A socket's halves as the shell keeps them (`Handle::Tcp`).
type SocketRead = Arc<tokio::sync::Mutex<Box<dyn tokio::io::AsyncRead + Send + Unpin>>>;
type SocketWrite = Arc<tokio::sync::Mutex<Box<dyn tokio::io::AsyncWrite + Send + Unpin>>>;

/// A stream carried whole into a socket (`istream.pipe`): each piece of it as a frame, its length (4 bytes, big-endian)
/// then its bytes; its end, or what failed it (the frame's tag, then the words' length and the words), as one of these.
const PIPE_END: u32 = 0xFFFF_FFFE;
const PIPE_FAILED: u32 = 0xFFFF_FFFD;
/// A frame no longer than this (the longest a read gives, and what the other side sends).
const PIPE_MOST: u32 = 1 << 20;

#[derive(Clone)]
enum Handle {
    Response(Arc<tokio::sync::Mutex<reqwest::Response>>),
    Ws { incoming: Arc<tokio::sync::Mutex<tokio::sync::mpsc::UnboundedReceiver<Result<String, String>>>>, outgoing: tokio::sync::mpsc::UnboundedSender<String> },
    /// A socket to the device's own port, or a station's session on the phone's adb (`adb.open`).
    Tcp { read: Arc<tokio::sync::Mutex<Box<dyn tokio::io::AsyncRead + Send + Unpin>>>, write: Arc<tokio::sync::Mutex<Box<dyn tokio::io::AsyncWrite + Send + Unpin>>> },
    Endpoint(Endpoint, Arc<Kept>),
    Conn(Connection),
    /// A connection that closed, let go (its state, its streams), with what the core may still ask of it.
    Gone { remote: String, reason: Value, stats: Value },
    /// An endpoint closed (`iroh.close`), let go, with what the core may still ask of it: one bound anew in its place
    /// leaves a dial still under way on it asking its relays as it fails (mesh.ts `link`), as the station's addon answers.
    Unbound { id: String },
    IStream(Arc<Halves>),
    /// A socket listening on this machine (`tcp.listen`, `unix.listen`): what a station's program serves (station/mb).
    Listener(Arc<Listener>),
    /// A zstd stream being taken apart (`zstd.open`).
    Unzstd(Arc<Mutex<Unzstd>>),
}

/// A listening socket: TCP on this machine's loopback (one bound here, or one a launcher bound and handed down by its
/// descriptor), or a Unix socket by its path.
enum Listener {
    Tcp(tokio::net::TcpListener),
    #[cfg(unix)]
    Unix(tokio::net::UnixListener),
}

impl Listener {
    /// The next connection, as a socket read and written as `tcp.open`'s are, and who it came from.
    async fn accept(&self) -> Result<(Handle, String), String> {
        fn halves<R, W>(read: R, write: W) -> Handle
        where
            R: tokio::io::AsyncRead + Send + Unpin + 'static,
            W: tokio::io::AsyncWrite + Send + Unpin + 'static,
        {
            Handle::Tcp { read: Arc::new(tokio::sync::Mutex::new(Box::new(read))), write: Arc::new(tokio::sync::Mutex::new(Box::new(write))) }
        }
        match self {
            Listener::Tcp(l) => {
                let (stream, peer) = l.accept().await.map_err(err)?;
                let _ = stream.set_nodelay(true);
                let (read, write) = stream.into_split();
                Ok((halves(read, write), peer.to_string()))
            }
            #[cfg(unix)]
            Listener::Unix(l) => {
                let (stream, _) = l.accept().await.map_err(err)?;
                let (read, write) = stream.into_split();
                Ok((halves(read, write), String::new()))
            }
        }
    }
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
    /// Fetch calls still owned by the core. Their exchange is dropped when its caller stops waiting, even between
    /// response headers and the body. Registered before spawning, so an immediate cancellation cannot miss it.
    fetches: Mutex<HashMap<u64, tokio::sync::oneshot::Sender<()>>>,
    handles: Mutex<HashMap<u64, Handle>>,
    next: AtomicU64,
    /// The accounts' databases open, by id, with their files.
    sqls: Mutex<HashMap<u64, (Option<PathBuf>, rusqlite::Connection)>>,
    /// Files being read a part at a time (`text.open`), by id.
    texts: Mutex<HashMap<u64, TextReader>>,
    /// How long an account's database is waited for as it is opened, while another process holds it (`open_wait`).
    open_wait: std::time::Duration,
    /// Where a message for the app goes straight from here (`sf_shell_set_say`): none, nothing is tapped.
    say: Mutex<Option<(Say, Ctx)>>,
    /// Where a tapped view's records are offered first (`sf_shell_set_media`): none, all are said.
    media: Mutex<Option<(Media, Ctx)>>,
    adb: adb::Adb,
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

/// A file to write a kept value in (`storage.set`: the partial one, renamed over the value once written). On Unix
/// its user's alone whatever the process's umask (0600, less what the umask takes of that): a value kept is a
/// device's key among others, and was readable by whomever the umask let (0644 under most), unless the program had
/// set the whole process's umask for it. What a crash left there is taken away first and the file made only if none
/// is there, so its mode is the one it is made with (none is set after: a filesystem may refuse that, where writing
/// did not fail before) and nothing is written through a link left in its place. One shell writes its values one
/// at a time (the disk thread). Two processes writing one key at once, which no program does, each write a file of
/// their own, and one of them fails (here, or at its rename), where their bytes went into one file before.
fn create_private(path: &std::path::Path) -> std::io::Result<std::fs::File> {
    #[cfg(unix)]
    {
        match std::fs::remove_file(path) {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => return Err(e),
            _ => {}
        }
        let mut options = std::fs::OpenOptions::new();
        std::os::unix::fs::OpenOptionsExt::mode(options.write(true).create_new(true), 0o600);
        options.open(path)
    }
    #[cfg(not(unix))]
    {
        std::fs::File::create(path)
    }
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

/// The connections' transport (the station's addon's `transport`): the congestion controller named, Cubic or BBR (opt
/// in), each with a 256 KiB initial window; each path kept alive each second and given up after 3 s of silence, so one
/// connection goes on through another relay as one goes; a link kept 10 minutes in silence (an app frozen in the
/// background past iroh's 30 s came back to every link timed out).
fn transport(congestion: &str) -> Result<QuicTransportConfig, String> {
    let controller: Arc<dyn noq_proto::congestion::ControllerFactory + Send + Sync> = match congestion {
        "cubic" => {
            let mut config = noq_proto::congestion::CubicConfig::default();
            config.initial_window(256 * 1024);
            Arc::new(config)
        }
        "bbr" => {
            let mut config = noq_proto::congestion::Bbr3Config::default();
            config.initial_window(256 * 1024);
            Arc::new(config)
        }
        _ => return Err("congestion: expected cubic or bbr".into()),
    };
    Ok(QuicTransportConfig::builder()
        .congestion_controller_factory(controller)
        .default_path_keep_alive_interval(std::time::Duration::from_secs(1))
        .default_path_max_idle_timeout(std::time::Duration::from_secs(3))
        .max_idle_timeout(Some(iroh::endpoint::VarInt::from_u32(10 * 60_000).into()))
        .build())
}

/// A way of finding stations (mDNS, the DHT) that could not be made leaves a station's endpoint without it, said, as
/// the station's addon has it: mDNS binds UDP 5353, which fails with no network up yet or the port held by another
/// program, and the endpoint failing left the station off the mesh until it was restarted.
#[derive(Debug)]
struct Optional<B>(&'static str, B);

#[derive(Debug)]
struct Unmade<L>(Option<L>);

impl<B: iroh::address_lookup::AddressLookupBuilder> iroh::address_lookup::AddressLookupBuilder for Optional<B> {
    fn into_address_lookup(self, endpoint: &Endpoint) -> Result<impl iroh::address_lookup::AddressLookup, iroh::address_lookup::AddressLookupBuilderError> {
        Ok(Unmade(match self.1.into_address_lookup(endpoint) {
            Ok(lookup) => Some(lookup),
            Err(error) => {
                eprintln!("mesh: stations not found through {}: {error:#}", self.0);
                None
            }
        }))
    }
}

impl<L: iroh::address_lookup::AddressLookup> iroh::address_lookup::AddressLookup for Unmade<L> {
    fn publish(&self, data: &iroh::address_lookup::EndpointData) {
        if let Some(lookup) = &self.0 {
            lookup.publish(data);
        }
    }

    fn resolve(&self, endpoint_id: EndpointId) -> Option<n0_future::boxed::BoxStream<Result<iroh::address_lookup::Item, iroh::address_lookup::Error>>> {
        self.0.as_ref().and_then(|lookup| lookup.resolve(endpoint_id))
    }
}

fn bytes_of(b: &'static [u8]) -> bytes::Bytes {
    bytes::Bytes::from_static(b)
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
    let mut info = match error {
        ConnectionError::ApplicationClosed(close) => json!({ "kind": "application", "reason": String::from_utf8_lossy(&close.reason) }),
        ConnectionError::LocallyClosed => json!({ "kind": "local", "reason": "" }),
        ConnectionError::TimedOut => json!({ "kind": "timeout", "reason": "" }),
        other => json!({ "kind": "other", "reason": other.to_string() }),
    };
    // (and in words, as the station's addon says it: its `closed`)
    info["text"] = json!(error.to_string());
    info
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
            Handle::Listener(_) => "listener",
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

    /// A stream given to the Unix socket at `path` (`istream.hand`): connected, `head` written, carried.
    async fn hand(self: &Arc<Self>, id: u64, halves: Arc<Halves>, path: &str, head: &[u8]) -> Result<(), String> {
        #[cfg(unix)]
        {
            let socket = match tokio::net::UnixStream::connect(path).await {
                Ok(socket) => socket,
                Err(e) => {
                    self.reset_stream(id).await;
                    return Err(err(e));
                }
            };
            {
                use std::os::fd::AsRawFd;
                // A stream's pieces written a megabyte ahead of the other side's reads (a Unix socket's own is 8 KiB
                // on macOS): fewer turns of both for what a stream carries.
                let size: libc::c_int = 1 << 20;
                // SAFETY: setsockopt on a socket this function holds, with an int it reads.
                unsafe { libc::setsockopt(socket.as_raw_fd(), libc::SOL_SOCKET, libc::SO_SNDBUF, (&size as *const libc::c_int).cast(), std::mem::size_of::<libc::c_int>() as libc::socklen_t) };
            }
            let (read, mut write) = socket.into_split();
            if let Err(e) = write.write_all(head).await {
                self.reset_stream(id).await;
                return Err(err(e));
            }
            let read: SocketRead = Arc::new(tokio::sync::Mutex::new(Box::new(read)));
            let write: SocketWrite = Arc::new(tokio::sync::Mutex::new(Box::new(write)));
            self.pipe(id, halves, read, write).await;
            Ok(())
        }
        #[cfg(not(unix))]
        {
            let _ = (id, halves, path, head);
            Err("Unix sockets are Unix's".into())
        }
    }

    /// A stream ended at once both ways, and let go (`istream.reset`'s).
    async fn reset_stream(&self, id: u64) {
        if let Some(Handle::IStream(halves)) = self.drop_handle(id) {
            let _ = halves.reset.send(true);
            if let Some(send) = halves.send.lock().await.as_mut() {
                let _ = send.reset(0u32.into());
            }
            if let Some(recv) = halves.recv.lock().await.as_mut() {
                let _ = recv.stop(0u32.into());
            }
        }
    }

    /// A stream carried whole into a socket, both ways (`istream.pipe`, which says how), till both ways are done.
    async fn pipe(&self, id: u64, halves: Arc<Halves>, read: SocketRead, write: SocketWrite) {
        let down = async {
            let mut write = write.lock().await;
            let mut reset = halves.reset.subscribe();
            let mut buf = vec![0u8; 4 + 256 * 1024];
            loop {
                if *reset.borrow() {
                    break;
                }
                let read = {
                    let mut recv = halves.recv.lock().await;
                    // (one way: nothing comes)
                    let Some(recv) = recv.as_mut() else { break };
                    tokio::select! {
                        read = recv.read(&mut buf[4..]) => read,
                        _ = reset.changed() => break,
                    }
                };
                let frame: &[u8] = match read {
                    Ok(Some(n)) => {
                        buf[..4].copy_from_slice(&(n as u32).to_be_bytes());
                        &buf[..4 + n]
                    }
                    Ok(None) => {
                        halves.ended.store(true, Ordering::Relaxed);
                        let _ = write.write_all(&PIPE_END.to_be_bytes()).await;
                        break;
                    }
                    Err(e) => {
                        let words = e.to_string();
                        let mut failed = PIPE_FAILED.to_be_bytes().to_vec();
                        failed.extend((words.len() as u32).to_be_bytes());
                        failed.extend(words.as_bytes());
                        let _ = write.write_all(&failed).await;
                        break;
                    }
                };
                if write.write_all(frame).await.is_err() {
                    break;
                }
            }
            let _ = write.shutdown().await;
        };
        let up = async {
            let mut read = read.lock().await;
            let mut reset = halves.reset.subscribe();
            let mut head = [0u8; 4];
            let mut buf = Vec::new();
            let mut written_end = false;
            let finished = loop {
                if *reset.borrow() {
                    break false;
                }
                let ok = tokio::select! {
                    r = read.read_exact(&mut head) => r.is_ok(),
                    _ = reset.changed() => break false,
                };
                if !ok {
                    break false;
                }
                let n = u32::from_be_bytes(head);
                if n == PIPE_END {
                    break true;
                }
                if n > PIPE_MOST {
                    break false;
                }
                buf.resize(n as usize, 0);
                let ok = tokio::select! {
                    r = read.read_exact(&mut buf) => r.is_ok(),
                    _ = reset.changed() => break false,
                };
                if !ok {
                    break false;
                }
                let mut send = halves.send.lock().await;
                let Some(send) = send.as_mut() else { break false };
                let sent = tokio::select! {
                    r = send.write_all(&buf) => r.is_ok(),
                    _ = reset.changed() => false,
                };
                if !sent {
                    // (reset by either end: the socket's frames go nowhere now)
                    written_end = true;
                    break false;
                }
            };
            if !written_end && !*reset.borrow() {
                let mut send = halves.send.lock().await;
                if let Some(send) = send.as_mut() {
                    if finished {
                        let _ = send.finish();
                    } else {
                        let _ = send.reset(0u32.into());
                    }
                }
            }
            halves.finished.store(true, Ordering::Relaxed);
        };
        tokio::join!(down, up);
        // Let go once both ways are done, unless its sending half is still to be asked when it is acknowledged.
        if halves.recv.lock().await.is_some() {
            self.istream_done(id, &halves);
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
            "stream.close" | "ws.close" | "tcp.close" | "zstd.close" | "listen.close" => {
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
                    let mut file = create_private(&partial).map_err(err)?;
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
                let id = self.keep(Handle::Tcp { read: Arc::new(tokio::sync::Mutex::new(Box::new(read))), write: Arc::new(tokio::sync::Mutex::new(Box::new(write))) });
                Ok(Answer::json(json!({ "id": id })))
            }
            // The phone's own adb (adb.rs): paired once, its session held, a station's session on it read and written as a
            // socket is.
            "adb.pair" => {
                let port = a.get("port").and_then(Value::as_u64).ok_or("missing port")? as u16;
                self.adb.pair(port, str_of(&a, "code")?).await?;
                Ok(Answer::json(json!({})))
            }
            "adb.hold" => {
                let port = a.get("port").and_then(Value::as_u64).ok_or("missing port")? as u16;
                self.adb.hold(port).await?;
                Ok(Answer::json(json!({})))
            }
            "adb.state" => Ok(Answer::json(json!({ "port": self.adb.state().await }))),
            "adb.open" => {
                let (read, write) = tokio::io::split(self.adb.open().await?);
                let id = self.keep(Handle::Tcp { read: Arc::new(tokio::sync::Mutex::new(Box::new(read))), write: Arc::new(tokio::sync::Mutex::new(Box::new(write))) });
                Ok(Answer::json(json!({ "id": id })))
            }
            // A socket to serve (station/mb's programs): a launcher's, handed down by its descriptor (`fd`, Unix), or one
            // bound here on 127.0.0.1 (`port`, 0 for any free one); its port said. Only this machine's: no other address.
            "tcp.listen" => {
                let listener = match a.get("fd").and_then(Value::as_i64) {
                    #[cfg(unix)]
                    Some(fd) => {
                        use std::os::fd::FromRawFd;
                        // SAFETY: the descriptor was handed to this process to serve, and is taken over once here.
                        let std = unsafe { std::net::TcpListener::from_raw_fd(fd as i32) };
                        std.set_nonblocking(true).map_err(err)?;
                        tokio::net::TcpListener::from_std(std).map_err(err)?
                    }
                    #[cfg(not(unix))]
                    Some(_) => return Err("a socket handed down by its descriptor is Unix's".into()),
                    None => {
                        let port = a.get("port").and_then(Value::as_u64).unwrap_or(0) as u16;
                        tokio::net::TcpListener::bind(("127.0.0.1", port)).await.map_err(err)?
                    }
                };
                let port = listener.local_addr().map_err(err)?.port();
                Ok(Answer::json(json!({ "id": self.keep(Handle::Listener(Arc::new(Listener::Tcp(listener)))), "port": port })))
            }
            // A Unix socket to serve at `path` (one there before is replaced).
            "unix.listen" => {
                #[cfg(unix)]
                {
                    let path = str_of(&a, "path")?;
                    let _ = std::fs::remove_file(path);
                    let listener = tokio::net::UnixListener::bind(path).map_err(err)?;
                    Ok(Answer::json(json!({ "id": self.keep(Handle::Listener(Arc::new(Listener::Unix(listener)))) })))
                }
                #[cfg(not(unix))]
                Err("Unix sockets are Unix's".into())
            }
            // Two sockets carried into each other, both ways, here (each side's end said to the other as it comes),
            // answered once both ways ended: what a station's program passes on whole, with no step of its own per piece.
            "tcp.pipe" => {
                let ids = a.get("ids").and_then(Value::as_array).ok_or("missing ids")?;
                let id = |i: usize| ids.get(i).and_then(Value::as_u64).ok_or_else(|| "missing ids".to_string());
                let (one, two) = (self.drop_handle(id(0)?), self.drop_handle(id(1)?));
                let (Some(Handle::Tcp { read: r1, write: w1 }), Some(Handle::Tcp { read: r2, write: w2 })) = (one, two) else {
                    return Err("not two tcp connections".into());
                };
                async fn carry(from: Arc<tokio::sync::Mutex<Box<dyn tokio::io::AsyncRead + Send + Unpin>>>, to: Arc<tokio::sync::Mutex<Box<dyn tokio::io::AsyncWrite + Send + Unpin>>>) -> u64 {
                    let (mut from, mut to) = (from.lock().await, to.lock().await);
                    let n = tokio::io::copy(&mut *from, &mut *to).await.unwrap_or(0);
                    let _ = to.shutdown().await;
                    n
                }
                let (there, back) = tokio::join!(carry(r1, w2), carry(r2, w1));
                Ok(Answer::json(json!({ "there": there, "back": back })))
            }
            // The next connection to a listening socket: a socket read and written as `tcp.open`'s are (`tcp.read`,
            // `tcp.write`, `tcp.end`, `tcp.close`), and who it came from.
            "tcp.accept" => {
                let Handle::Listener(listener) = self.handle(id_of(&a)?)? else { return Err("not a listening socket".into()) };
                let (conn, peer) = listener.accept().await?;
                Ok(Answer::json(json!({ "id": self.keep(conn), "peer": peer })))
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
                let (endpoint, kept) = match self.handle(id_of(&a)?)? {
                    Handle::Endpoint(endpoint, kept) => (endpoint, kept),
                    Handle::Unbound { .. } => return Ok(Answer::json(json!({ "end": true }))),
                    _ => return Err("not an endpoint".into()),
                };
                let mut accepted = kept.accepted.lock().await;
                let done = accepted.get_or_insert_with(|| {
                    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
                    let kept = kept.clone();
                    tokio::spawn(async move {
                        while let Some(incoming) = endpoint.accept().await {
                            {
                                let mut held = kept.held.lock().unwrap();
                                if held.0 > 0 {
                                    held.0 -= 1;
                                    held.1.push(incoming);
                                    continue;
                                }
                            }
                            let tx = tx.clone();
                            tokio::spawn(async move {
                                // One whose handshake fails is said, where it came from and how long it took (the
                                // station's addon's, which says why).
                                let from = incoming.remote_addr();
                                let started = std::time::Instant::now();
                                match incoming.await {
                                    Ok(conn) => {
                                        let _ = tx.send(conn);
                                    }
                                    Err(error) => eprintln!("mesh: a connection's handshake failed from {from:?} after {} ms: {error:#}", started.elapsed().as_millis()),
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
            "iroh.setRelayEntries" => {
                let endpoint = match self.handle(id_of(&a)?)? {
                    Handle::Endpoint(endpoint, _) => endpoint,
                    Handle::Unbound { .. } => return Ok(Answer::json(json!({}))),
                    _ => return Err("not an endpoint".into()),
                };
                let mut entries = BTreeMap::<RelayUrl, Vec<RelayUrl>>::new();
                for entry in a.get("entries").and_then(Value::as_array).into_iter().flatten() {
                    entries.entry(relay_url(str_of(entry, "relay")?)?).or_default().push(relay_url(str_of(entry, "entry")?)?);
                }
                endpoint.set_relay_entries(entries.into_iter().collect()).await;
                Ok(Answer::json(json!({})))
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
                        Some(Handle::Endpoint(endpoint, kept)) => {
                            for (_, task) in kept.keepers.lock().unwrap().drain() {
                                task.abort();
                            }
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
                let mut tap = ScreenTap::new(call);
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
            // A station's endpoint (station/mb's front, which keeps it for the station's Node: the addon's `Endpoint`).
            "iroh.online" | "iroh.insertRelay" | "iroh.removeRelay" | "iroh.publicRelays" | "iroh.keep" | "iroh.setCongestion" | "iroh.holdIncoming" => {
                let (endpoint, kept) = match self.handle(id_of(&a)?)? {
                    Handle::Endpoint(endpoint, kept) => (endpoint, kept),
                    Handle::Unbound { .. } => return Err("the endpoint is closed".into()),
                    _ => return Err("not an endpoint".into()),
                };
                match op {
                    // Once it is on its home relay (at once with relays off).
                    "iroh.online" => endpoint.online().await,
                    "iroh.insertRelay" => {
                        let url = relay_url(str_of(&a, "url")?)?;
                        endpoint.insert_relay(url.clone(), Arc::new(iroh::RelayConfig::from(url))).await;
                    }
                    "iroh.removeRelay" => {
                        endpoint.remove_relay(&relay_url(str_of(&a, "url")?)?).await;
                    }
                    // iroh's own public relays: added while none of still.fail's answers, removed once one does.
                    "iroh.publicRelays" => {
                        let on = a.get("on").and_then(Value::as_bool).unwrap_or(false);
                        for config in iroh::defaults::prod::default_relay_map().relays::<Vec<_>>() {
                            if on {
                                endpoint.insert_relay(config.url.clone(), config.clone()).await;
                            } else {
                                endpoint.remove_relay(&config.url).await;
                            }
                        }
                    }
                    // On exactly these relays besides those it is home on: a keeper for each new one, those of relays no
                    // longer named stopped.
                    "iroh.keep" => {
                        let mut relays: Vec<RelayUrl> = a.get("urls").and_then(Value::as_array).into_iter().flatten().map(|u| relay_url(u.as_str().unwrap_or_default())).collect::<Result<_, _>>()?;
                        relays.retain(|r| !kept.homes.contains(r));
                        let urls: Vec<String> = relays.iter().map(ToString::to_string).collect();
                        let mut keepers = kept.keepers.lock().unwrap();
                        keepers.retain(|url, task| {
                            let named = urls.contains(url);
                            if !named {
                                task.abort();
                            }
                            named
                        });
                        for relay in relays {
                            let endpoint = endpoint.clone();
                            keepers.entry(relay.to_string()).or_insert_with(|| tokio::spawn(keep::keep(endpoint, relay)));
                        }
                    }
                    // The controller of the connections made from now on.
                    "iroh.setCongestion" => endpoint.set_transport_config(transport(str_of(&a, "congestion")?)?),
                    // The next `n` connections coming never answered, not even their handshake (tests: a device whose way
                    // here is gone).
                    _ => kept.held.lock().unwrap().0 = a.get("n").and_then(Value::as_u64).unwrap_or(0) as u32,
                }
                Ok(Answer::json(json!({})))
            }
            // Whether the other end is still there: asked with a datagram (which a live end acknowledges at once) a few
            // times within `within` ms, true as soon as anything is heard from it (the addon's `answers`, which says why).
            "conn.answers" => {
                let conn = match self.handle(id_of(&a)?)? {
                    Handle::Conn(conn) => conn,
                    Handle::Gone { .. } => return Ok(Answer::json(json!(false))),
                    _ => return Err("not a connection".into()),
                };
                let within = std::time::Duration::from_millis(a.get("within").and_then(Value::as_u64).unwrap_or(0));
                let heard = conn.stats().udp_rx.datagrams;
                let deadline = std::time::Instant::now() + within;
                let mut ask = std::time::Instant::now();
                let answers = loop {
                    if conn.close_reason().is_some() {
                        break false;
                    }
                    if conn.stats().udp_rx.datagrams > heard {
                        break true;
                    }
                    let now = std::time::Instant::now();
                    if now >= deadline {
                        break false;
                    }
                    if now >= ask {
                        match conn.send_datagram(bytes_of(&[0])) {
                            Ok(()) => {}
                            Err(iroh::endpoint::SendDatagramError::ConnectionLost(_)) => break false,
                            Err(_) => break true,
                        }
                        ask = now + within / 3;
                    }
                    tokio::time::sleep(std::time::Duration::from_millis(20)).await;
                };
                Ok(Answer::json(json!(answers)))
            }
            // A Unix socket on this machine, read and written as `tcp.open`'s is.
            "unix.open" => {
                #[cfg(unix)]
                {
                    let (read, write) = tokio::net::UnixStream::connect(str_of(&a, "path")?).await.map_err(err)?.into_split();
                    let id = self.keep(Handle::Tcp { read: Arc::new(tokio::sync::Mutex::new(Box::new(read))), write: Arc::new(tokio::sync::Mutex::new(Box::new(write))) });
                    Ok(Answer::json(json!({ "id": id })))
                }
                #[cfg(not(unix))]
                Err("Unix sockets are Unix's".into())
            }
            // A stream carried whole into a socket (`to`, taken), both ways, here: what comes on it written to the socket
            // in frames (PIPE_END its end, PIPE_FAILED what failed it), and the frames the socket sends written on it, its
            // PIPE_END finishing it; the socket ending without one resets it. What the station's Node reads and writes of
            // a stream the front keeps for it (station/mb's front), none of it through the front's program. Answered once
            // both ways are done; `istream.stopped` and `istream.reset` are asked of the stream meanwhile as before.
            "istream.pipe" => {
                let id = id_of(&a)?;
                let Handle::IStream(halves) = self.handle(id)? else { return Err("not a stream".into()) };
                let to = a.get("to").and_then(Value::as_u64).ok_or("missing to")?;
                let Some(Handle::Tcp { read, write }) = self.drop_handle(to) else { return Err("not a socket".into()) };
                self.pipe(id, halves, read, write).await;
                Ok(Answer::json(json!({})))
            }
            // A stream given to the Unix socket at `path`: a connection to it, `bytes` written first (what tells the
            // other side which stream it is), then the stream carried into it as `istream.pipe` carries it.
            "istream.hand" => {
                let id = id_of(&a)?;
                let Handle::IStream(halves) = self.handle(id)? else { return Err("not a stream".into()) };
                self.hand(id, halves, str_of(&a, "path")?, &bytes.unwrap_or_default()).await?;
                Ok(Answer::json(json!({})))
            }
            // Each stream the other end of a connection opens, given as it comes to the Unix socket at `path` as
            // `istream.hand` gives one, its head the connection's id and the stream's (8 bytes each, big-endian), a 2
            // and the stream's index on the connection (QUIC's, 8 bytes): each is handed by a task of its own, so their
            // sockets come to the other side in any order, which puts them back in the order they were opened by it
            // (a device's credential stream is its first; 2026-11-13, its requests came first and were refused as
            // one). A 0 there and no index: a front from before. Kept as a stream here meanwhile
            // (`istream.stopped`, `istream.reset`). Answered once the connection is gone.
            // What station/mb's front gives its Node, with no step of the program's for each stream.
            "conn.hand" => {
                let on = id_of(&a)?;
                let path = str_of(&a, "path")?.to_string();
                let Handle::Conn(conn) = self.handle(on)? else { return Ok(Answer::json(json!({}))) };
                while let Ok((mut send, mut recv)) = conn.accept_bi().await {
                    if !matches!(self.handle(on), Ok(Handle::Conn(_))) {
                        let _ = send.reset(0u32.into());
                        let _ = recv.stop(0u32.into());
                        break;
                    }
                    let index = recv.id().index();
                    let halves = Arc::new(Halves {
                        conn: on,
                        ended: false.into(),
                        finished: false.into(),
                        send: tokio::sync::Mutex::new(Some(send)),
                        recv: tokio::sync::Mutex::new(Some(recv)),
                        reset: tokio::sync::watch::channel(false).0,
                        tap: Mutex::default(),
                    });
                    let id = self.keep(Handle::IStream(halves.clone()));
                    let mut head = on.to_be_bytes().to_vec();
                    head.extend(id.to_be_bytes());
                    head.push(2);
                    head.extend(index.to_be_bytes());
                    let (inner, path) = (self.clone(), path.clone());
                    tokio::spawn(async move {
                        if let Err(e) = inner.hand(id, halves, &path, &head).await {
                            eprintln!("mesh: a stream not given: {e}");
                        }
                    });
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
        let key_again = key.clone();
        let relays: Vec<RelayUrl> = a.get("relayUrls").and_then(Value::as_array).into_iter().flatten().map(|u| relay_url(u.as_str().unwrap_or_default())).collect::<Result<_, _>>()?;
        let entries: Vec<(RelayUrl, RelayUrl)> = a.get("relayEntries").and_then(Value::as_array).into_iter().flatten().map(|e| Ok((relay_url(str_of(e, "entry")?)?, relay_url(str_of(e, "relay")?)?))).collect::<Result<_, String>>()?;
        let relay_map = iroh::RelayMap::from_iter(relays.iter().map(|relay| {
            iroh::RelayConfig::from(relay.clone()).with_entries(entries.iter().filter(|(_, target)| target == relay).map(|(entry, _)| entry.clone()))
        }));
        let alpns: Vec<Vec<u8>> = a.get("alpns").and_then(Value::as_array).into_iter().flatten().map(|x| hex::decode(x.as_str().unwrap_or_default()).map_err(err)).collect::<Result<_, _>>()?;
        let mut builder = Endpoint::builder(Minimal)
            .secret_key(key)
            .alpns(alpns)
            .relay_mode(if relays.is_empty() { RelayMode::Disabled } else { RelayMode::Custom(relay_map) })
            // Home on every relay at once, each path kept alive each second and given up after 3 s of silence: one
            // connection to a station goes through every relay it is on, and on through another as one goes (the
            // station's mesh addon: PATH_KEEP_ALIVE, PATH_IDLE).
            .home_on_every_relay()
            .transport_config(transport(a.get("congestion").and_then(Value::as_str).unwrap_or("cubic"))?);
        // Where a station listens (its config's fixed port); any free port when not said.
        if let Some(addr) = a.get("bindAddr").and_then(Value::as_str) {
            builder = builder.bind_addr(addr.parse::<std::net::SocketAddr>().map_err(err)?).map_err(err)?;
        }
        if a.get("relayOnly").and_then(Value::as_bool).unwrap_or(false) {
            builder = builder.clear_ip_transports();
        }
        // The DHT unless `dht: false` (a company's filter marking the Mainline DHT as risky), mDNS either way: the
        // station's addon's `dht`.
        let with_dht = a.get("dht").and_then(Value::as_bool).unwrap_or(true);
        // Stations on the LAN (mDNS, never announced itself) and which relay they are on (the DHT), as client/core-ts's.
        if a.get("lookup").and_then(Value::as_bool).unwrap_or(false) && !relays.is_empty() {
            builder = builder.address_lookup(iroh_mdns_address_lookup::MdnsAddressLookup::builder().service_name(MDNS_SERVICE).advertise(false));
            if with_dht {
                builder = builder.address_lookup(iroh_mainline_address_lookup::DhtAddressLookup::builder().dht_builder(dht()).no_publish());
            }
        } else if a.get("discovery").and_then(Value::as_bool).unwrap_or(false) {
            // A station's: found on the LAN by mDNS and by its relay through the DHT, both announced (the station's
            // addon's `bind`), each left out, said, where it cannot be made (mDNS's port held, no network yet).
            builder = builder.address_lookup(Optional("mDNS", iroh_mdns_address_lookup::MdnsAddressLookup::builder().service_name(MDNS_SERVICE)));
            if with_dht {
                builder = builder.address_lookup(Optional("the DHT", iroh_mainline_address_lookup::DhtAddressLookup::builder().dht_builder(dht()).secret_key(key_again)));
            }
        }
        let endpoint = builder.bind().await.map_err(err)?;
        Ok(Answer::json(json!({ "id": self.keep(Handle::Endpoint(endpoint, Arc::new(Kept { homes: relays.clone(), ..Kept::default() }))) })))
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
            // A database another process keeps (the station's, by its path) and writes as well: never made here (but with
            // `create`), never held for this process alone, waited for `wait` ms when it is busy.
            "sql.attach" => {
                let path = PathBuf::from(str_of(a, "path")?);
                let wait = a.get("wait").and_then(Value::as_u64).unwrap_or(0);
                let mut flags = rusqlite::OpenFlags::SQLITE_OPEN_READ_WRITE | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX | rusqlite::OpenFlags::SQLITE_OPEN_URI;
                // `create`: one of the program's own, made where it is not (station/mb src/replica's export.db).
                if a.get("create").and_then(Value::as_bool).unwrap_or(false) {
                    flags |= rusqlite::OpenFlags::SQLITE_OPEN_CREATE;
                }
                let conn = rusqlite::Connection::open_with_flags(&path, flags).map_err(err)?;
                conn.busy_timeout(std::time::Duration::from_millis(wait)).map_err(err)?;
                conn.set_prepared_statement_cache_capacity(256);
                conn.execute_batch("PRAGMA synchronous = NORMAL;").map_err(err)?;
                let id = self.next.fetch_add(1, Ordering::Relaxed);
                sqls.insert(id, (None, conn));
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
                        // `named`: the columns' names beside the rows ({columns, rows}), as the station's reads give them.
                        let names: Option<Vec<String>> = a.get("named").and_then(Value::as_bool).unwrap_or(false)
                            .then(|| statement.column_names().into_iter().map(String::from).collect());
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
                        Ok(match names {
                            Some(columns) => json!({ "columns": columns, "rows": out }),
                            None => Value::Array(out),
                        })
                    }
                    _ => Err(format!("no operation {op}")),
                }
            }
        }
    }

    fn run_sync(&self, op: &str, a: &Value) -> Result<Value, String> {
        // Whether a screen view's Opus sound is decoded here (ScreenTap): only where its tap says to the app, so the
        // core asks the station for Opus only then (client/core-ts hosts/bridge.ts `opus`), else PCM.
        if op == "tap.opus" {
            return Ok(json!(self.say.lock().unwrap().is_some()));
        }
        if op == "fetch.cancel" {
            let pending = self.fetches.lock().unwrap().remove(&id_of(a)?);
            return Ok(json!(pending.is_some_and(|cancel| cancel.send(()).is_ok())));
        }
        // The file a key's value is kept in, for what reads it there itself (a face's file: client/core-ts
        // font-files.ts); null while none is kept.
        if op == "storage.path" {
            let path = storage_path(&self.dir, str_of(a, "key")?);
            return Ok(if path.is_file() { json!(path.to_string_lossy()) } else { Value::Null });
        }
        // A path's kind as stat (links followed) says it: "file", "dir" or "other"; null when it cannot be (none there,
        // no right): what the station's programs ask of the filesystem (station/mb src/locate), as Node's statSync does.
        // With `lstat`, the path itself as lstat says it (a link "link", not followed).
        if op == "fs.stat" {
            let path = str_of(a, "path")?;
            let lstat = a.get("lstat").and_then(Value::as_bool).unwrap_or(false);
            return Ok(match if lstat { std::fs::symlink_metadata(path) } else { std::fs::metadata(path) } {
                Ok(m) if m.file_type().is_symlink() => json!("link"),
                Ok(m) if m.is_file() => json!("file"),
                Ok(m) if m.is_dir() => json!("dir"),
                Ok(_) => json!("other"),
                Err(_) => Value::Null,
            });
        }
        // A directory's names, with their kinds as the directory says them (`types`: [name, "file" | "dir" | "link" |
        // "other"], links not followed), in Node's readdirSync's order (libuv sorts them by their bytes, but on Windows);
        // null when it cannot be read.
        // `disk`: in the order the file system gives them (Node's opendirSync, Rust's read_dir), an entry that does not
        // read ending the list rather than failing it (station/src/read/machine.ts `readDir`).
        if op == "fs.readdir" {
            let Ok(entries) = std::fs::read_dir(str_of(a, "path")?) else { return Ok(Value::Null) };
            let disk = a.get("disk").and_then(Value::as_bool).unwrap_or(false);
            let mut out: Vec<(String, &str)> = Vec::new();
            for entry in entries {
                let Ok(entry) = entry else {
                    if disk {
                        break;
                    }
                    return Ok(Value::Null);
                };
                let kind = match entry.file_type() {
                    Ok(t) if t.is_symlink() => "link",
                    Ok(t) if t.is_dir() => "dir",
                    Ok(t) if t.is_file() => "file",
                    _ => "other",
                };
                out.push((entry.file_name().to_string_lossy().into_owned(), kind));
            }
            if !cfg!(windows) && !disk {
                out.sort_by(|x, y| x.0.as_bytes().cmp(y.0.as_bytes()));
            }
            let types = a.get("types").and_then(Value::as_bool).unwrap_or(false);
            return Ok(Value::Array(out.into_iter().map(|(name, kind)| if types { json!([name, kind]) } else { json!(name) }).collect()));
        }
        // A path with its links resolved as Node's realpathSync resolves them (each part looked at, a link's target put in
        // its place; the parts' names as given, not as the disk spells them); null when a part is not there.
        if op == "fs.realpath" {
            return Ok(node_realpath(str_of(a, "path")?).map_or(Value::Null, |p| json!(p)));
        }
        // A file's text: `strict` as a TextDecoder with `fatal` reads it (a leading byte order mark dropped, none when it
        // is not UTF-8), else as Node's readFileSync(path, "utf8") does (what is not UTF-8 replaced); null when it does
        // not read.
        // A transcript read a part at a time (station/src/usage/counter.ts `readFrom`, search/sources.ts `mentions`): the
        // file as long as it was when opened, or its `.zst` (every frame, the seek table passed over) when the file is
        // not there. Each `text.next` is the next part, decoded as Buffer.toString("utf8") does: `lines` whole lines of
        // at most about 8 MB (a last line without its end left out, as readFrom leaves it), else every byte, in pieces
        // cut where a character ends. Null at the end; `text.close` lets it go.
        if op == "text.open" {
            let path = PathBuf::from(str_of(a, "path")?);
            let lines = a.get("lines").and_then(Value::as_bool).unwrap_or(false);
            let packed = PathBuf::from(format!("{}.zst", path.display()));
            let source: Box<dyn std::io::Read + Send> = match std::fs::File::open(&path) {
                Ok(file) => {
                    let size = file.metadata().map(|m| m.len()).unwrap_or(0);
                    Box::new(std::io::Read::take(file, size))
                }
                Err(_) => match std::fs::File::open(&packed) {
                    Ok(file) => match zstd::stream::read::Decoder::new(file) {
                        Ok(d) => Box::new(d),
                        Err(_) => return Ok(Value::Null),
                    },
                    Err(_) => return Ok(Value::Null),
                },
            };
            let id = self.next.fetch_add(1, Ordering::Relaxed);
            self.texts.lock().map_err(|_| "the readers are gone".to_string())?.insert(id, TextReader { source, held: Vec::new(), lines, done: false });
            return Ok(json!({ "id": id }));
        }
        if op == "text.next" {
            let id = id_of(a)?;
            let mut texts = self.texts.lock().map_err(|_| "the readers are gone".to_string())?;
            let reader = texts.get_mut(&id).ok_or_else(|| format!("no reader {id}"))?;
            return Ok(reader.next().map_or(Value::Null, Value::String));
        }
        if op == "text.close" {
            self.texts.lock().map_err(|_| "the readers are gone".to_string())?.remove(&id_of(a)?);
            return Ok(Value::Null);
        }
        // A path's size and when it was last written (ms, none before 1970), links followed, as Node's statSync with
        // `bigint` says them; null when it cannot be.
        if op == "fs.meta" {
            let Ok(meta) = std::fs::metadata(str_of(a, "path")?) else { return Ok(Value::Null) };
            let since = meta.modified().ok().and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok());
            let modified = since.map(|d| d.as_millis() as u64);
            // `mtime`: as Node's statSync (no `bigint`) says `mtimeMs`, its fraction of a millisecond kept.
            let mtime = since.map(|d| d.as_secs() as f64 * 1e3 + d.subsec_nanos() as f64 / 1e6);
            return Ok(json!({ "size": meta.len(), "mtimeMs": modified, "mtime": mtime, "dir": meta.is_dir() }));
        }
        // The end of a file, at most `bytes` of it (up to its size when opened), decoded as TextDecoder("utf-8") does
        // (what is not UTF-8 replaced, a leading byte order mark dropped); null when it does not open.
        if op == "fs.tail" {
            use std::io::{Read, Seek, SeekFrom};
            let Ok(mut file) = std::fs::File::open(str_of(a, "path")?) else { return Ok(Value::Null) };
            let most = a.get("bytes").and_then(Value::as_u64).unwrap_or(64 * 1024);
            let size = file.metadata().map(|m| m.len()).unwrap_or(most);
            let from = size.saturating_sub(most);
            let mut bytes = Vec::new();
            if file.seek(SeekFrom::Start(from)).is_ok() {
                let _ = file.take(size - from).read_to_end(&mut bytes);
            }
            let body = bytes.strip_prefix(b"\xef\xbb\xbf").unwrap_or(&bytes);
            return Ok(json!(String::from_utf8_lossy(body)));
        }
        // Bytes of a file as hex, from byte `from` (0), `length` of them where it says (to its end where not), or with
        // `zstd` what the zstd frames there hold (station/mb src/history's transcripts read a piece at a time, a put-away
        // one a frame at a time); with `exact`, a file that ends before `length` is a failure. Null when it does not open.
        if op == "fs.bytes" {
            use std::io::{Read, Seek, SeekFrom};
            let Ok(mut file) = std::fs::File::open(str_of(a, "path")?) else { return Ok(Value::Null) };
            let from = a.get("from").and_then(Value::as_u64).unwrap_or(0);
            let length = a.get("length").and_then(Value::as_u64);
            let mut bytes = Vec::new();
            file.seek(SeekFrom::Start(from)).map_err(err)?;
            match length {
                Some(n) => file.take(n).read_to_end(&mut bytes),
                None => file.read_to_end(&mut bytes),
            }
            .map_err(err)?;
            if a.get("exact").and_then(Value::as_bool).unwrap_or(false) && length.is_some_and(|n| (bytes.len() as u64) < n) {
                return Err("a put-away transcript ended early".into());
            }
            if a.get("zstd").and_then(Value::as_bool).unwrap_or(false) {
                bytes = zstd::decode_all(bytes.as_slice()).map_err(err)?;
            }
            return Ok(json!(hex::encode(bytes)));
        }
        // A program run to its end, as Node's execFileSync runs one (station/src/read/sessions.ts `inRepositories`: `git
        // ls-files`): `command` with `args`, nothing on its stdin and its stderr let go, its stdout decoded as
        // Buffer.toString("utf8") does; null where it did not end well: not started, ended by a signal or with a code
        // not 0, still running after `timeoutMs` (killed then), or writing more than `maxBytes`.
        if op == "proc.run" {
            use std::io::Read;
            use std::process::{Command, Stdio};
            let args: Vec<String> = a.get("args").and_then(Value::as_array).map(|v| v.iter().filter_map(|x| x.as_str().map(String::from)).collect()).unwrap_or_default();
            let timeout = std::time::Duration::from_millis(a.get("timeoutMs").and_then(Value::as_u64).unwrap_or(5000));
            let most = a.get("maxBytes").and_then(Value::as_u64).unwrap_or(1 << 20) as usize;
            let Ok(mut child) = Command::new(str_of(a, "command")?).args(&args).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn() else {
                return Ok(Value::Null);
            };
            let mut stdout = child.stdout.take().expect("piped");
            let reading = std::thread::spawn(move || {
                let mut out = Vec::new();
                let over = (&mut stdout).take(most as u64 + 1).read_to_end(&mut out).is_err() || out.len() > most;
                (out, over)
            });
            let started = std::time::Instant::now();
            let status = loop {
                match child.try_wait() {
                    Ok(Some(status)) => break Some(status),
                    Ok(None) if started.elapsed() < timeout => std::thread::sleep(std::time::Duration::from_millis(2)),
                    _ => {
                        let _ = child.kill();
                        let _ = child.wait();
                        break None;
                    }
                }
            };
            let (out, over) = reading.join().unwrap_or((Vec::new(), true));
            return Ok(match status {
                Some(s) if s.success() && !over => json!(String::from_utf8_lossy(&out)),
                _ => Value::Null,
            });
        }
        // What a link points to, as Node's readlinkSync gives it; null when the path is no link or cannot be read.
        if op == "fs.readlink" {
            return Ok(std::fs::read_link(str_of(a, "path")?).map_or(Value::Null, |p| json!(p.to_string_lossy())));
        }
        // A file from byte `from` to its end, decoded as Buffer.toString("utf8") does (what is not UTF-8 replaced, a byte
        // order mark kept); null when it does not open.
        if op == "fs.from" {
            use std::io::{Read, Seek, SeekFrom};
            let Ok(mut file) = std::fs::File::open(str_of(a, "path")?) else { return Ok(Value::Null) };
            let from = a.get("from").and_then(Value::as_u64).unwrap_or(0);
            let mut bytes = Vec::new();
            if file.seek(SeekFrom::Start(from)).is_err() || file.read_to_end(&mut bytes).is_err() {
                return Ok(Value::Null);
            }
            return Ok(json!(String::from_utf8_lossy(&bytes)));
        }
        // A file's lines as Rust's BufRead::lines with map_while(Result::ok) reads them (station/src/read/machine.ts
        // `lines`): without their "\n" or "\r\n", each decoded strictly with a leading byte order mark dropped, ending at
        // the first that is not UTF-8 or at a read that fails; at most `limit`. A line longer than `max` bytes (its "\n"
        // counted) is read as "". None when the file does not open: an empty list.
        if op == "fs.lines" {
            use std::io::Read;
            let Ok(mut file) = std::fs::File::open(str_of(a, "path")?) else { return Ok(json!([])) };
            let limit = a.get("limit").and_then(Value::as_u64).map_or(usize::MAX, |n| n as usize);
            let max = a.get("max").and_then(Value::as_u64).map_or(usize::MAX, |n| n as usize);
            let mut out: Vec<Value> = Vec::new();
            let mut pending: Vec<u8> = Vec::new();
            let mut over = false;
            // Whether more are wanted.
            let take = |line: &[u8], over: &mut bool, out: &mut Vec<Value>| -> bool {
                if *over {
                    *over = false;
                    out.push(json!(""));
                    return out.len() < limit;
                }
                let mut line = line;
                if line.last() == Some(&b'\n') {
                    line = &line[..line.len() - 1];
                }
                if line.last() == Some(&b'\r') {
                    line = &line[..line.len() - 1];
                }
                let body = line.strip_prefix(b"\xef\xbb\xbf").unwrap_or(line);
                match std::str::from_utf8(body) {
                    Ok(text) => out.push(json!(text)),
                    Err(_) => return false,
                }
                out.len() < limit
            };
            let mut chunk = vec![0u8; 1 << 16];
            loop {
                let n = match file.read(&mut chunk) {
                    Ok(n) => n,
                    Err(_) => return Ok(Value::Array(out)),
                };
                if n == 0 {
                    break;
                }
                let mut start = 0;
                let keep = |part: &[u8], pending: &mut Vec<u8>, over: &mut bool| {
                    if *over {
                        return;
                    }
                    if pending.len() + part.len() > max {
                        *over = true;
                        pending.clear();
                    } else {
                        pending.extend_from_slice(part);
                    }
                };
                while let Some(nl) = chunk[start..n].iter().position(|&b| b == b'\n').map(|i| start + i) {
                    keep(&chunk[start..=nl], &mut pending, &mut over);
                    let line = std::mem::take(&mut pending);
                    start = nl + 1;
                    if !take(&line, &mut over, &mut out) {
                        return Ok(Value::Array(out));
                    }
                }
                if start < n {
                    keep(&chunk[start..n], &mut pending, &mut over);
                }
            }
            if !pending.is_empty() || over {
                take(&pending, &mut over, &mut out);
            }
            return Ok(Value::Array(out));
        }
        // What the station's programs write (station/mb src/replica, as station/src/replica/export.ts writes): `text`
        // as a whole file at `path`, zstd's frame of it with `zstd` (level 3, as Node's zstdCompressSync), written beside
        // it, synced and renamed into place, its folders made; the SHA-256 of the bytes written and how many.
        if op == "fs.write" {
            use sha2::Digest;
            use std::io::Write;
            let path = PathBuf::from(str_of(a, "path")?);
            let text = str_of(a, "text")?.as_bytes();
            let bytes = if a.get("zstd").and_then(Value::as_bool).unwrap_or(false) { zstd::encode_all(text, 3).map_err(err)? } else { text.to_vec() };
            if let Some(dir) = path.parent() {
                std::fs::create_dir_all(dir).map_err(err)?;
            }
            let mut random = [0u8; 4];
            getrandom::fill(&mut random).map_err(err)?;
            let tmp = PathBuf::from(format!("{}.{}.{}.tmp", path.display(), std::process::id(), hex::encode(random)));
            let written = (|| {
                let mut file = std::fs::File::create(&tmp)?;
                file.write_all(&bytes)?;
                file.sync_all()
            })();
            if let Err(e) = written.and_then(|_| std::fs::rename(&tmp, &path)) {
                let _ = std::fs::remove_file(&tmp);
                return Err(err(e));
            }
            return Ok(json!({ "sha256": hex::encode(sha2::Sha256::digest(&bytes)), "size": bytes.len() }));
        }
        // A file's SHA-256 (hex), read a MiB at a time; null when it does not open.
        if op == "fs.hash" {
            use sha2::Digest;
            use std::io::Read;
            let Ok(mut file) = std::fs::File::open(str_of(a, "path")?) else { return Ok(Value::Null) };
            let mut hash = sha2::Sha256::new();
            let mut buf = vec![0u8; 1 << 20];
            loop {
                let n = file.read(&mut buf).map_err(err)?;
                if n == 0 {
                    break;
                }
                hash.update(&buf[..n]);
            }
            return Ok(json!(hex::encode(hash.finalize())));
        }
        // A folder and those it is in, made where they are not (mkdirSync's `recursive`).
        if op == "fs.mkdir" {
            std::fs::create_dir_all(str_of(a, "path")?).map_err(err)?;
            return Ok(Value::Null);
        }
        // What is at `path` let go, a folder with all it holds with `recursive`; nothing there is no failure (rmSync's
        // `force`).
        if op == "fs.remove" {
            let path = PathBuf::from(str_of(a, "path")?);
            let recursive = a.get("recursive").and_then(Value::as_bool).unwrap_or(false);
            let gone = match std::fs::symlink_metadata(&path) {
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
                Err(e) => Err(e),
                Ok(m) if m.is_dir() && recursive => std::fs::remove_dir_all(&path),
                Ok(m) if m.is_dir() => std::fs::remove_dir(&path),
                Ok(_) => std::fs::remove_file(&path),
            };
            return gone.map(|_| Value::Null).map_err(err);
        }
        if op == "fs.rename" {
            std::fs::rename(str_of(a, "from")?, str_of(a, "to")?).map_err(err)?;
            return Ok(Value::Null);
        }
        if op == "fs.copy" {
            std::fs::copy(str_of(a, "from")?, str_of(a, "to")?).map_err(err)?;
            return Ok(Value::Null);
        }
        // `bytes` random bytes (hex), from the system's source.
        if op == "crypto.random" {
            let mut bytes = vec![0u8; a.get("bytes").and_then(Value::as_u64).unwrap_or(0).min(1024) as usize];
            getrandom::fill(&mut bytes).map_err(err)?;
            return Ok(json!(hex::encode(bytes)));
        }
        if op == "fs.read" {
            let Ok(mut bytes) = std::fs::read(str_of(a, "path")?) else { return Ok(Value::Null) };
            // `zstd`: a file that is zstd's frames, read as what they hold (a copy's batch: station/mb src/replica).
            if a.get("zstd").and_then(Value::as_bool).unwrap_or(false) {
                bytes = zstd::decode_all(bytes.as_slice()).map_err(err)?;
            }
            if a.get("strict").and_then(Value::as_bool).unwrap_or(false) {
                let body = bytes.strip_prefix(b"\xef\xbb\xbf").unwrap_or(&bytes);
                return Ok(std::str::from_utf8(body).map_or(Value::Null, |s| json!(s)));
            }
            return Ok(json!(String::from_utf8_lossy(&bytes)));
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
        // Whether `signature` is `key`'s over `message` (hex all): Ed25519 (a 32-byte key, a 64-byte signature) or ECDSA
        // P-256 over SHA-256 (`ES256`: an uncompressed point and r‖s; `ES256-der`: the signature DER, as WebAuthn gives
        // it), by libcrux's formally verified implementations: what the core checks the lock's entries and the vault's
        // records by (client/core-ts vault/verified.ts) where the shell has it, not @noble's in JS.
        if op == "crypto.verify" {
            let key = hex::decode(str_of(a, "key")?).map_err(err)?;
            let signature = hex::decode(str_of(a, "signature")?).map_err(err)?;
            let message = hex::decode(str_of(a, "message")?).map_err(err)?;
            let ok = match str_of(a, "alg")? {
                "Ed25519" => match (<[u8; 32]>::try_from(key.as_slice()), <[u8; 64]>::try_from(signature.as_slice())) {
                    (Ok(k), Ok(s)) => libcrux_ed25519::verify(&message, &k, &s).is_ok(),
                    _ => false,
                },
                alg @ ("ES256" | "ES256-der") => {
                    use libcrux_ecdsa::p256::{PublicKey, Signature, verify};
                    let s = if alg == "ES256" { <[u8; 64]>::try_from(signature.as_slice()).ok().map(Signature::from_bytes) } else { Signature::from_der(&signature).ok() };
                    match (s, PublicKey::try_from(key.as_slice())) {
                        (Some(s), Ok(k)) if key.len() == 65 => verify(libcrux_ecdsa::DigestAlgorithm::Sha256, &message, &s, &k).is_ok(),
                        _ => false,
                    }
                }
                other => return Err(format!("no {other} here")),
            };
            return Ok(json!(ok));
        }
        // What the DHT lookup's socket and lookups went through since the last take, while the core records (`keep`;
        // false: none kept from now on): the record's `dht:` lines (client/core-ts mesh.ts, vendor/n0-mainline's `stillfail`).
        if op == "dht.said" {
            let (lines, dropped) = n0_mainline::stillfail::said(a.get("keep").and_then(Value::as_bool).unwrap_or(false));
            return Ok(json!({ "lines": lines.into_iter().map(|s| json!({ "at": s.at_ms, "text": s.text })).collect::<Vec<_>>(), "dropped": dropped }));
        }
        let handle = self.handle(id_of(a)?)?;
        match (op, handle) {
            ("iroh.endpointId", Handle::Endpoint(e, _)) => Ok(json!(hex::encode(e.id().as_bytes()))),
            ("iroh.addAddr", Handle::Endpoint(e, _)) => {
                let addr = endpoint_addr(a.get("addr").ok_or("missing addr")?)?;
                e.address_lookup().map_err(err)?.add(iroh::address_lookup::MemoryLookup::from_endpoint_info([addr]));
                Ok(Value::Null)
            }
            ("iroh.sockets", Handle::Endpoint(e, _)) => Ok(json!(e.bound_sockets().iter().map(ToString::to_string).collect::<Vec<_>>())),
            ("iroh.sockets", Handle::Unbound { .. }) => Ok(json!([])),
            // How it runs now: "relay", "direct", or null while none is chosen.
            ("conn.via", Handle::Conn(c)) => Ok(c.paths().iter().find(|p| p.is_selected()).map(|p| json!(if p.is_relay() { "relay" } else { "direct" })).unwrap_or(Value::Null)),
            ("conn.via", Handle::Gone { .. }) => Ok(Value::Null),
            ("iroh.relayStatus", Handle::Endpoint(e, _)) => Ok(Value::Array(e.home_relay_status().get().iter().map(|s| json!({ "url": s.url().to_string(), "connected": s.is_connected(), "access": s.access_url().to_string() })).collect())),
            ("conn.alpn", Handle::Conn(c)) => Ok(json!(hex::encode(c.alpn()))),
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
                        json!({ "id": p.id().to_string(), "selected": p.is_selected(), "relay": relay, "ip": ip, "rttMs": stats.same_path_rtt.map(|rtt| rtt.as_secs_f64() * 1000.0), "txPackets": stats.udp_tx.datagrams, "lostPackets": stats.lost_packets, "cwnd": stats.cwnd, "congestionEvents": stats.congestion_events })
                    })
                    .collect(),
            )),
            // What went over it since it opened (the addon's `stats`, which says what each is for).
            ("conn.stats", Handle::Conn(c)) => {
                let s = c.stats();
                let data = |f: &iroh::endpoint::FrameStats| f.stream + f.datagram + f.crypto;
                Ok(json!({
                    "rxBytes": s.udp_rx.bytes, "txBytes": s.udp_tx.bytes, "rxPackets": s.udp_rx.datagrams, "txPackets": s.udp_tx.datagrams,
                    "rxPings": s.frame_rx.ping, "txPings": s.frame_tx.ping, "rxAckRequests": s.frame_rx.immediate_ack, "txAckRequests": s.frame_tx.immediate_ack,
                    "rxAcks": s.frame_rx.acks + s.frame_rx.path_acks, "txAcks": s.frame_tx.acks + s.frame_tx.path_acks, "rxData": data(&s.frame_rx), "txData": data(&s.frame_tx),
                }))
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
        // Two threads in an app; a station's program says how many it is to have (STILLFAIL_SHELL_THREADS: the station's
        // front, whose threads carry every byte of the station's iroh, its addon's on as many as the machine has cores).
        let threads = std::env::var("STILLFAIL_SHELL_THREADS").ok().and_then(|n| n.parse::<usize>().ok()).filter(|n| *n > 0).unwrap_or(2);
        let runtime = tokio::runtime::Builder::new_multi_thread().worker_threads(threads).thread_name("stillfail-shell").enable_all().build()?;
        let (jobs, queue) = mpsc::channel::<Job>();
        std::thread::Builder::new().name("stillfail-disk".into()).spawn(move || {
            for job in queue {
                job();
            }
        })?;
        let tls = Arc::new(tls_config());
        let http = Mutex::new(http_client(&tls));
        let db = Arc::new(Mutex::new(DbHandle { path: dir.join("core.db"), conn: None }));
        let adb = adb::Adb::new(dir.clone());
        let inner = Arc::new(Inner { complete, ctx: Ctx(ctx), dir, disk: Mutex::new(jobs), db, tls, http, fetches: Mutex::default(), handles: Mutex::default(), next: AtomicU64::new(1), sqls: Mutex::default(), texts: Mutex::default(), open_wait, say: Mutex::default(), media: Mutex::default(), adb });
        STATS.lock().unwrap().shells.push(Arc::downgrade(&inner));
        Ok(Shell { runtime, inner })
    }

    pub fn call(&self, id: u64, op: String, json: &[u8], bytes: Option<Vec<u8>>) {
        let inner = self.inner.clone();
        let args: Value = serde_json::from_slice(json).unwrap_or(Value::Null);
        // A fetch, and a dial's handshake (iroh.connect): given up when the core cancels the call, its connection dropped,
        // which closes it (a dial left going retransmitted its Initial for the connection's whole idle timeout: the
        // station addon's `dial`, station/native/mesh/src/lib.rs).
        let cancelled = if op == "fetch" || op == "iroh.connect" {
            let (cancel, cancelled) = tokio::sync::oneshot::channel();
            inner.fetches.lock().unwrap().insert(id, cancel);
            Some(cancelled)
        } else {
            None
        };
        counted(&op, true);
        self.runtime.spawn(async move {
            let done = if let Some(cancelled) = cancelled {
                let done = tokio::select! {
                    biased;
                    _ = cancelled => Err("cancelled".into()),
                    done = inner.run(&op, args, bytes) => done,
                };
                inner.fetches.lock().unwrap().remove(&id);
                done
            } else {
                inner.run(&op, args, bytes).await
            };
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
        let mut tap = ScreenTap::new(7);
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
            let mut again = ScreenTap::new(7);
            again.take(&wire[..cut], &told);
            again.take(&wire[cut..], &told);
            assert_eq!((told.said.lock().unwrap().len(), &again.out, again.pending.len()), (4, &core, 0));
        }
    }

    #[test]
    fn what_the_host_takes_of_a_tapped_screen_is_not_said() {
        // the host decodes and plays the frames and the sound itself: only the config said, the core's kept the same
        let told = Told { takes: vec![FRAME_VIDEO, FRAME_AUDIO], ..Told::default() };
        let mut tap = ScreenTap::new(3);
        let (wire, core) = screen_wire();
        tap.take(&wire, &told);
        let said = told.said.into_inner().unwrap();
        assert_eq!(said.len(), 1);
        assert!(said[0].0["value"]["config"].is_object());
        assert_eq!(told.offered.lock().unwrap().len(), 4);
        assert_eq!(tap.out, core);
    }

    /// The first 80 ms of a tone (440 Hz and 1250 Hz on the left, 660 Hz on the right, 0.3 and 0.1 of full scale) as the
    /// Mac's helper encodes it (AudioToolbox, 64 kbit/s): one Opus packet each 20 ms.
    const TONE_OPUS: [&str; 4] = [
            "fc7efcfac83adf72422eb70639fd4e7994094ff81dca24140fcda72ab2837dafcb307757fd6f158807f14e5e02ba87d108d7bd98511d4749ba09a54029f42122017d75bb3f223221c5fca7b5cd5d7ea2a96148eb32fcc8e81946df99d205a49cd119fd285e189d81b698fe1eb8a4cea59aa6b594d60479250ecd7fcc39e8231dde329ac910ad059cc974b3dc9f2151d605aa2169f84ff7e1dbc00263e2c45f6243d8dad8ff115909f7c119fc6f003690930e4f7b70a549bf3fb41999da21cfa221cfa7445c5eea9f2dea8d6e4752a3a16abe4752a77619af9e3f8443068d0e8f4b3b67e429ea271c65f49d1280a1f826b8a6e4235d037e42f70b1b3def726cd85c5675900040f45954157bb1fed63d34848eb0c9061d95fa530354ab8f281430570d47f20f2e1ce4b8379de776c5758efa3b17e75eb7df13019e2eb8127e",
            "fcf01f552abac40cb85b1b9c453ab1c5c0efde6ee2a4abc433f8c758944a04de36245ed4673c74936b45224cd6674e8e979829b7673b8ee8d5faae9dfb85461dc85db4fcfe1ca13bf53a8e7d455427f10b9283f4e3969eaca97907055f74b4f3c68af224684fcea74a70759c10ce055a78da40cfe736edb1f06af2e1516d9c9b0596688961e12b253da1eb5255a67bb07d1b5bd61e2b25abbaab1cc4eed48e12cce89ccbf893d75f050cbf06e645c0d5cc8e",
            "fcf0533d61b4ccf9c20a05dd48d2b7a632b6b587bf7509d2330cbf4df6837f3fff1a8f72494cb696db3b4f99658c1997d9a4ad792c6ad90573eb04a8ba81ea16e73fe342e66946a731490469fd67f67cb28038aab73f603d03c51d9eba899826c31d1240e44aeb48a68649472d543c2b233cdd6908a1968506aaaa461321ac70e71855735019314fde063951e507e1f33e5883ba01f68ff0e094dde1ec8e",
            "fced3cd57d7aa6a3555bbe8628998d7798b5f24ff8b642112c57c81112f8b2b55d3d49112fd2e45042ae08e20c311cc5d634041eb70f9edee772340f4c0c4b37067ffc0378b1e7934408b5f67f1c18a2704671798a125eadce7ee7f6372126813aa7441d008cf744241e40631cbed650ac8ed66b3172863ef769665807743a9e63409d45846a5361e3926ce68773ceb4a34ff103e65fda8b9c924ae4d77c8e",
    ];

    fn unhex(s: &str) -> Vec<u8> {
        (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap()).collect()
    }

    #[test]
    fn a_tapped_screens_opus_sound_is_said_as_the_pcm_it_decodes_to() {
        let told = Told::default();
        let mut tap = ScreenTap::new(4);
        let mut wire = frame(FRAME_AUDIO_CONFIG, br#"{"codec":"opus","sampleRate":48000,"channels":2}"#);
        for (i, packet) in TONE_OPUS.iter().enumerate() {
            let mut body = ((i as u64 + 1) * 20_000).to_be_bytes().to_vec();
            body.extend(unhex(packet));
            wire.extend(frame(FRAME_AUDIO, &body));
        }
        // one that is no Opus packet: left out, the sound going on with the next
        let mut broken = 100_000u64.to_be_bytes().to_vec();
        broken.extend_from_slice(&[0xff; 3]);
        wire.extend(frame(FRAME_AUDIO, &broken));
        // after a gap (and the packet not decoded): decoded by a decoder made anew
        let mut after = 1_000_000u64.to_be_bytes().to_vec();
        after.extend(unhex(TONE_OPUS[1]));
        wire.extend(frame(FRAME_AUDIO, &after));
        for piece in wire.chunks(13) {
            tap.take(piece, &told);
        }
        let said = told.said.into_inner().unwrap();
        // the app is told PCM: what it plays is the decoded sound
        assert_eq!(said[0].0, json!({ "id": 4, "value": { "audioConfig": { "codec": "pcm_s16le", "sampleRate": 48000, "channels": 2 } } }));
        let packets: Vec<&Vec<u8>> = said[1..].iter().map(|s| s.1.as_ref().unwrap()).collect();
        assert_eq!(packets.iter().map(|p| p.len()).collect::<Vec<_>>(), vec![PCM_PACKET; 5]);
        assert_eq!(said[1..].iter().map(|s| s.0["value"]["audio"]["ts"].as_u64().unwrap()).collect::<Vec<_>>(), vec![20_000, 40_000, 60_000, 80_000, 1_000_000]);
        // past the decoder's start, the tone: the left about 0.22 of full scale (RMS), the right about 0.21
        let rms = |p: &[u8], ch: usize| {
            let v: Vec<f64> = p.chunks_exact(4).map(|f| i16::from_le_bytes([f[ch * 2], f[ch * 2 + 1]]) as f64 / 32768.0).collect();
            (v.iter().map(|x| x * x).sum::<f64>() / v.len() as f64).sqrt()
        };
        let (left, right) = (rms(packets[3], 0), rms(packets[3], 1));
        assert!((0.19..0.26).contains(&left) && (0.18..0.25).contains(&right), "{left} {right}");
        assert!(tap.out.is_empty(), "nothing of it the core's");
    }

    /// The answers of every test's shells, each told by its test (the shell's `ctx`, the test's thread's tag) and its id:
    /// ids alike in tests run at once were taken by either (94_001, a dial's test's and a listening socket's, 2026-11-12).
    static ANSWERS: StdMutex<Vec<(usize, u64, String, String, Option<Vec<u8>>)>> = StdMutex::new(Vec::new());
    static ANSWERED: Condvar = Condvar::new();
    static TAGS: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(1);
    thread_local! {
        static TAG: usize = TAGS.fetch_add(1, Ordering::Relaxed);
    }

    /// What a shell started on this test's thread is given to say whose its answers are.
    fn ctx() -> *mut c_void {
        TAG.with(|t| *t as *mut c_void)
    }

    extern "C" fn complete(ctx: *mut c_void, id: u64, json: *const u8, jl: usize, e: *const u8, el: usize, b: *const u8, bl: usize, has: u8) {
        let s = |p: *const u8, l: usize| if l == 0 { String::new() } else { String::from_utf8_lossy(unsafe { std::slice::from_raw_parts(p, l) }).into_owned() };
        let bytes = (has != 0).then(|| if bl == 0 { Vec::new() } else { unsafe { std::slice::from_raw_parts(b, bl) }.to_vec() });
        ANSWERS.lock().unwrap().push((ctx as usize, id, s(json, jl), s(e, el), bytes));
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
        let tag = TAG.with(|t| *t);
        let mut answers = ANSWERS.lock().unwrap();
        loop {
            if let Some(i) = answers.iter().position(|a| a.0 == tag && a.1 == id) {
                let (_, _, j, e, b) = answers.remove(i);
                return (j, e, b);
            }
            answers = ANSWERED.wait(answers).unwrap();
        }
    }

    #[test]
    fn serves_a_listening_socket_bound_here_handed_down_or_unix() {
        use std::io::{Read, Write};
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().join("shell"), complete, ctx()).unwrap();
        let call = |id: u64, op: &str, a: Value, bytes: Option<Vec<u8>>| {
            shell.call(id, op.into(), a.to_string().as_bytes(), bytes);
            let (json, error, bytes) = answer(id);
            assert_eq!(error, "", "{op}");
            (serde_json::from_str::<Value>(&json).unwrap(), bytes)
        };
        // Each socket: a connection taken, what it sent read, an answer written, the end said.
        let serve = |base: u64, listener: u64, connect: &dyn Fn() -> Box<dyn ReadWrite>| {
            let mut client = connect();
            client.write_all(b"ping").unwrap();
            let (accepted, _) = call(base, "tcp.accept", json!({ "id": listener }), None);
            let conn = accepted["id"].as_u64().unwrap();
            let (_, got) = call(base + 1, "tcp.read", json!({ "id": conn }), None);
            assert_eq!(got.unwrap(), b"ping");
            call(base + 2, "tcp.write", json!({ "id": conn }), Some(b"pong".to_vec()));
            call(base + 3, "tcp.end", json!({ "id": conn }), None);
            let mut back = Vec::new();
            client.read_to_end(&mut back).unwrap();
            assert_eq!(back, b"pong");
        };
        // bound here, on 127.0.0.1, its port said
        let (bound, _) = call(96_001, "tcp.listen", json!({ "port": 0 }), None);
        let port = bound["port"].as_u64().unwrap() as u16;
        serve(96_010, bound["id"].as_u64().unwrap(), &|| Box::new(std::net::TcpStream::connect(("127.0.0.1", port)).unwrap()));
        #[cfg(unix)]
        {
            use std::os::fd::IntoRawFd;
            // one a launcher bound and handed down by its descriptor
            let launcher = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
            let port = launcher.local_addr().unwrap().port();
            let (handed, _) = call(96_020, "tcp.listen", json!({ "fd": launcher.into_raw_fd() }), None);
            assert_eq!(handed["port"].as_u64().unwrap() as u16, port);
            serve(96_030, handed["id"].as_u64().unwrap(), &|| Box::new(std::net::TcpStream::connect(("127.0.0.1", port)).unwrap()));
            // a Unix socket, by its path (one left there before replaced)
            let path = dir.path().join("front.sock");
            std::fs::write(&path, "left").unwrap();
            let (unix, _) = call(96_040, "unix.listen", json!({ "path": path.display().to_string() }), None);
            let p = path.clone();
            serve(96_050, unix["id"].as_u64().unwrap(), &move || Box::new(std::os::unix::net::UnixStream::connect(&p).unwrap()));
        }
    }

    #[test]
    fn pipes_two_sockets_into_each_other() {
        use std::io::{Read, Write};
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().join("shell"), complete, ctx()).unwrap();
        let call = |id: u64, op: &str, a: Value| {
            shell.call(id, op.into(), a.to_string().as_bytes(), None);
            let (json, error, _) = answer(id);
            assert_eq!(error, "", "{op}");
            serde_json::from_str::<Value>(&json).unwrap()
        };
        let front = call(95_001, "tcp.listen", json!({ "port": 0 }));
        let target = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let mut client = std::net::TcpStream::connect(("127.0.0.1", front["port"].as_u64().unwrap() as u16)).unwrap();
        let accepted = call(95_002, "tcp.accept", json!({ "id": front["id"] }));
        let opened = call(95_003, "tcp.open", json!({ "port": target.local_addr().unwrap().port() }));
        let (mut server, _) = target.accept().unwrap();
        shell.call(95_004, "tcp.pipe".into(), json!({ "ids": [accepted["id"], opened["id"]] }).to_string().as_bytes(), None);
        client.write_all(b"hello").unwrap();
        client.shutdown(std::net::Shutdown::Write).unwrap();
        let mut got = Vec::new();
        server.read_to_end(&mut got).unwrap();
        assert_eq!(got, b"hello", "carried there, and its end");
        server.write_all(b"back").unwrap();
        drop(server);
        let mut back = Vec::new();
        client.read_to_end(&mut back).unwrap();
        assert_eq!(back, b"back", "carried back, and its end");
        let (json, error, _) = answer(95_004);
        assert_eq!(error, "");
        assert_eq!(serde_json::from_str::<Value>(&json).unwrap(), json!({ "there": 5, "back": 4 }));
        // the sockets are the pipe's now: not the shell's to read
        shell.call(95_005, "tcp.read".into(), json!({ "id": accepted["id"] }).to_string().as_bytes(), None);
        assert_ne!(answer(95_005).1, "");
    }

    trait ReadWrite: std::io::Read + std::io::Write {}
    impl<T: std::io::Read + std::io::Write> ReadWrite for T {}

    #[test]
    fn cancelling_a_fetch_closes_the_socket_while_headers_or_body_are_stalled() {
        for (id, body) in [(93_001, false), (93_002, true)] {
            let dir = TempDir::new();
            let shell = Shell::start(dir.path().to_path_buf(), complete, ctx()).unwrap();
            let (listener, addr) = shell.runtime.block_on(async {
                let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
                let addr = listener.local_addr().unwrap();
                (listener, addr)
            });
            let (ready, arrived) = tokio::sync::oneshot::channel();
            let closed = shell.runtime.spawn(async move {
                let (mut socket, _) = listener.accept().await.unwrap();
                let mut request = Vec::new();
                while !request.ends_with(b"\r\n\r\n") {
                    request.push(socket.read_u8().await.unwrap());
                }
                if body {
                    socket.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\na").await.unwrap();
                }
                ready.send(()).unwrap();
                // No more response bytes arrive. Cancelling the fetch must drop the actual HTTP exchange.
                socket.read_u8().await
            });
            shell.call(id, "fetch".into(), serde_json::to_vec(&json!({ "url": format!("http://{addr}/credential"), "method": "GET", "headers": [] })).unwrap().as_slice(), None);
            shell.runtime.block_on(arrived).unwrap();
            let cancel = || serde_json::from_slice::<Value>(&shell.call_sync("fetch.cancel", serde_json::to_vec(&json!({ "id": id })).unwrap().as_slice())).unwrap();
            assert_eq!(cancel(), json!({ "value": true }));
            assert_eq!(answer(id).1, "cancelled");
            assert!(shell.runtime.block_on(closed).unwrap().is_err());
            assert_eq!(cancel(), json!({ "value": false }));
        }
    }

    /// A dial the core gave up (its opening ended: client/core-ts mesh.ts) is cancelled here as a fetch is: its
    /// handshake dropped, which closes it (what that stops, the Initial sent again for ten minutes, the station addon's
    /// `a_dial_given_up_sends_no_more` counts), and the endpoint closes at once.
    #[test]
    fn cancelling_a_dial_drops_its_handshake() {
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().to_path_buf(), complete, ctx()).unwrap();
        // A station that never answers: a socket that takes what comes.
        let quiet = shell.runtime.block_on(tokio::net::UdpSocket::bind("127.0.0.1:0")).unwrap();
        shell.call(94_001, "iroh.bind".into(), serde_json::to_vec(&json!({ "relayUrls": [], "alpns": [] })).unwrap().as_slice(), Some(vec![3; 32]));
        let endpoint = serde_json::from_str::<Value>(&answer(94_001).0).unwrap()["id"].clone();
        let station = json!({ "id": hex::encode(SecretKey::from_bytes(&[7; 32]).public().as_bytes()), "ips": [quiet.local_addr().unwrap().to_string()] });
        shell.call(94_002, "iroh.connect".into(), serde_json::to_vec(&json!({ "id": endpoint, "addr": station })).unwrap().as_slice(), Some(b"test".to_vec()));
        // Its Initial came: the dial is under way.
        shell.runtime.block_on(quiet.recv(&mut [0u8; 2048])).unwrap();
        let cancel = || serde_json::from_slice::<Value>(&shell.call_sync("fetch.cancel", serde_json::to_vec(&json!({ "id": 94_002 })).unwrap().as_slice())).unwrap();
        assert_eq!(cancel(), json!({ "value": true }));
        assert_eq!(answer(94_002).1, "cancelled");
        assert_eq!(cancel(), json!({ "value": false }));
        shell.call(94_003, "iroh.close".into(), serde_json::to_vec(&json!({ "id": endpoint })).unwrap().as_slice(), None);
        assert_eq!(answer(94_003).1, "");
    }

    #[test]
    fn keeps_files_and_records_as_client_ffi_does() {
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().to_path_buf(), complete, ctx()).unwrap();
        shell.call(1, "storage.set".into(), br#"{"key":"device"}"#, Some(vec![1, 2, 3]));
        assert_eq!(answer(1).1, "");
        assert!(dir.path().join("device").exists());
        // A value kept is its user's alone, whatever the process's umask (0644 by the umask of most, before): made
        // so, and one written over a file from before, or over a partial one a crash left, is made so too.
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = |name: &str| std::fs::metadata(dir.path().join(name)).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode("device"), 0o600);
            std::fs::set_permissions(dir.path().join("device"), std::fs::Permissions::from_mode(0o644)).unwrap();
            std::fs::write(dir.path().join("device.partial"), b"left").unwrap();
            std::fs::set_permissions(dir.path().join("device.partial"), std::fs::Permissions::from_mode(0o644)).unwrap();
            shell.call(1, "storage.set".into(), br#"{"key":"device"}"#, Some(vec![1, 2, 3]));
            assert_eq!(answer(1).1, "");
            assert_eq!(mode("device"), 0o600);
            assert!(!dir.path().join("device.partial").exists());
            // A partial one left that is a link to somewhere is taken away, never written through: what it led to
            // is as it was, and the value is a file of its own.
            std::fs::write(dir.path().join("elsewhere"), b"another's").unwrap();
            std::os::unix::fs::symlink(dir.path().join("elsewhere"), dir.path().join("device.partial")).unwrap();
            shell.call(1, "storage.set".into(), br#"{"key":"device"}"#, Some(vec![4, 5]));
            assert_eq!(answer(1).1, "");
            assert_eq!(std::fs::read(dir.path().join("elsewhere")).unwrap(), b"another's");
            assert_eq!(std::fs::read(dir.path().join("device")).unwrap(), vec![4, 5]);
            assert!(std::fs::symlink_metadata(dir.path().join("device")).unwrap().file_type().is_file());
            assert_eq!(mode("device"), 0o600);
            shell.call(1, "storage.set".into(), br#"{"key":"device"}"#, Some(vec![1, 2, 3]));
            assert_eq!(answer(1).1, "");
        }
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
        let shell = Shell::start(dir.path().to_path_buf(), complete, ctx()).unwrap();
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
    fn attaches_a_database_another_process_keeps() {
        let dir = TempDir::new();
        let path = dir.path().join("station.db");
        // the station's own connection, in WAL, holding it while the shell's is open beside it
        let station = rusqlite::Connection::open(&path).unwrap();
        station.execute_batch("PRAGMA journal_mode = WAL; CREATE TABLE t (k TEXT, n INTEGER); INSERT INTO t VALUES ('a', 1);").unwrap();
        let shell = Shell::start(dir.path().join("shell"), complete, ctx()).unwrap();
        let sync = |op: &str, json: &str| -> Value { serde_json::from_slice(&shell.call_sync(op, json.as_bytes())).unwrap() };
        let at = serde_json::to_string(&path.display().to_string()).unwrap();
        let id = sync("sql.attach", &format!(r#"{{"path":{at},"wait":0}}"#))["value"]["id"].as_u64().unwrap();
        let rows = sync("sql.all", &format!(r#"{{"id":{id},"sql":"SELECT k, n FROM t","named":true}}"#));
        assert_eq!(rows["value"], json!({ "columns": ["k", "n"], "rows": [["a", 1]] }));
        // both write: neither holds it for itself
        station.execute("INSERT INTO t VALUES ('b', 2)", []).unwrap();
        let checkpoint = sync("sql.all", &format!(r#"{{"id":{id},"sql":"PRAGMA wal_checkpoint(PASSIVE)","named":true}}"#));
        assert_eq!(checkpoint["value"]["columns"], json!(["busy", "log", "checkpointed"]));
        // a path with no database is not made one
        let missing = serde_json::to_string(&dir.path().join("none.db").display().to_string()).unwrap();
        assert!(sync("sql.attach", &format!(r#"{{"path":{missing}}}"#))["error"].is_string());
        assert!(!dir.path().join("none.db").exists());
    }

    #[test]
    fn writes_hashes_and_moves_the_station_programs_files() {
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().join("shell"), complete, ctx()).unwrap();
        let sync = |op: &str, a: Value| -> Value { serde_json::from_slice(&shell.call_sync(op, a.to_string().as_bytes())).unwrap() };
        let at = |p: &str| dir.path().join(p).display().to_string();
        // written whole, its folders made, nothing left beside it; zstd's frame of it read back as what it holds
        let plain = sync("fs.write", json!({ "path": at("a/b/plain.txt"), "text": "中\n" }));
        use sha2::Digest;
        assert_eq!(plain["value"]["sha256"], json!(hex::encode(sha2::Sha256::digest("中\n".as_bytes()))));
        assert_eq!(plain["value"]["size"], json!(4));
        assert_eq!(std::fs::read(dir.path().join("a/b/plain.txt")).unwrap(), "中\n".as_bytes());
        let packed = sync("fs.write", json!({ "path": at("a/packed.zst"), "text": "x".repeat(1000), "zstd": true }));
        let bytes = std::fs::read(dir.path().join("a/packed.zst")).unwrap();
        assert!(bytes.len() < 100);
        assert_eq!(packed["value"], json!({ "sha256": hex::encode(sha2::Sha256::digest(&bytes)), "size": bytes.len() }));
        assert_eq!(sync("fs.read", json!({ "path": at("a/packed.zst"), "zstd": true }))["value"], json!("x".repeat(1000)));
        assert_eq!(std::fs::read_dir(dir.path().join("a")).unwrap().count(), 2);
        assert_eq!(sync("fs.hash", json!({ "path": at("a/b/plain.txt") }))["value"], plain["value"]["sha256"]);
        // a piece of a file as hex, a frame of it decompressed, and one that ends early
        assert_eq!(sync("fs.bytes", json!({ "path": at("a/packed.zst"), "zstd": true }))["value"], json!(hex::encode("x".repeat(1000))));
        let whole = sync("fs.bytes", json!({ "path": at("a/b/plain.txt") }))["value"].as_str().unwrap().to_string();
        assert_eq!(sync("fs.bytes", json!({ "path": at("a/b/plain.txt"), "from": 1, "length": 2 }))["value"], json!(whole[2..6]));
        assert!(sync("fs.bytes", json!({ "path": at("a/b/plain.txt"), "from": 1, "length": 1_000_000, "exact": true }))["error"].is_string());
        assert_eq!(sync("fs.bytes", json!({ "path": at("none") }))["value"], Value::Null);
        assert_eq!(sync("fs.hash", json!({ "path": at("none") }))["value"], Value::Null);
        // a program's output, and one that fails, runs too long or writes too much; a link as lstat says it
        #[cfg(unix)]
        {
            assert_eq!(sync("proc.run", json!({ "command": "printf", "args": ["a\\nb"] }))["value"], json!("a\nb"));
            assert_eq!(sync("proc.run", json!({ "command": "false" }))["value"], Value::Null);
            assert_eq!(sync("proc.run", json!({ "command": "sleep", "args": ["5"], "timeoutMs": 50 }))["value"], Value::Null);
            assert_eq!(sync("proc.run", json!({ "command": "printf", "args": ["abcdef"], "maxBytes": 3 }))["value"], Value::Null);
            assert_eq!(sync("proc.run", json!({ "command": "/no/such/program" }))["value"], Value::Null);
            std::os::unix::fs::symlink(at("a/b/plain.txt"), at("a/link")).unwrap();
            assert_eq!(sync("fs.stat", json!({ "path": at("a/link"), "lstat": true }))["value"], json!("link"));
            assert_eq!(sync("fs.stat", json!({ "path": at("a/link") }))["value"], json!("file"));
            std::fs::remove_file(at("a/link")).unwrap();
        }
        // copied, renamed, a folder made, then let go with what it holds; nothing there is no failure
        assert_eq!(sync("fs.copy", json!({ "from": at("a/b/plain.txt"), "to": at("a/copy.txt") }))["value"], Value::Null);
        assert_eq!(sync("fs.rename", json!({ "from": at("a/copy.txt"), "to": at("a/moved.txt") }))["value"], Value::Null);
        assert_eq!(std::fs::read(dir.path().join("a/moved.txt")).unwrap(), "中\n".as_bytes());
        assert_eq!(sync("fs.mkdir", json!({ "path": at("c/d") }))["value"], Value::Null);
        assert!(dir.path().join("c/d").is_dir());
        assert!(sync("fs.remove", json!({ "path": at("a") }))["error"].is_string());
        assert_eq!(sync("fs.remove", json!({ "path": at("a"), "recursive": true }))["value"], Value::Null);
        assert!(!dir.path().join("a").exists());
        assert_eq!(sync("fs.remove", json!({ "path": at("a") }))["value"], Value::Null);
        assert_eq!(sync("crypto.random", json!({ "bytes": 4 }))["value"].as_str().unwrap().len(), 8);
        // a database of the program's own, made with `create`
        assert!(sync("sql.attach", json!({ "path": at("own.db") }))["error"].is_string());
        assert!(sync("sql.attach", json!({ "path": at("own.db"), "create": true }))["value"]["id"].is_u64());
        assert!(dir.path().join("own.db").exists());
    }

    #[test]
    fn keeps_an_accounts_database() {
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().to_path_buf(), complete, ctx()).unwrap();
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
        let app = Shell::start_waiting(dir.path().to_path_buf(), complete, ctx(), DB_WAIT).unwrap();
        let window = Shell::start_waiting(dir.path().to_path_buf(), complete, ctx(), std::time::Duration::ZERO).unwrap();
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
        let shell = Shell::start(dir.path().to_path_buf(), complete, ctx()).unwrap();
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
    fn checks_ed25519_and_p256_signatures() {
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().to_path_buf(), complete, ctx()).unwrap();
        let sync = |op: &str, json: &str| -> Value { serde_json::from_slice(&shell.call_sync(op, json.as_bytes())).unwrap() };
        // RFC 8032's test 2; then the message changed
        let ed = |message: &str| sync("crypto.verify", &format!(r#"{{"alg":"Ed25519","key":"3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c","signature":"92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00","message":"{message}"}}"#));
        assert_eq!(ed("72")["value"], json!(true));
        assert_eq!(ed("73")["value"], json!(false));
        // RFC 6979 A.2.5, P-256 with SHA-256, message "sample": r‖s, then DER
        let key = "0460fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb67903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299";
        let r = "efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716";
        let s = "f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8";
        let p = |alg: &str, signature: &str, message: &str| sync("crypto.verify", &format!(r#"{{"alg":"{alg}","key":"{key}","signature":"{signature}","message":"{message}"}}"#));
        assert_eq!(p("ES256", &format!("{r}{s}"), "73616d706c65")["value"], json!(true));
        assert_eq!(p("ES256", &format!("{r}{s}"), "73616d706c66")["value"], json!(false));
        assert_eq!(p("ES256-der", &format!("3046022100{r}022100{s}"), "73616d706c65")["value"], json!(true));
        assert_eq!(p("ES256", "00", "73616d706c65")["value"], json!(false));
        assert!(sync("crypto.verify", r#"{"alg":"RS256","key":"00","signature":"00","message":"00"}"#)["error"].is_string());
    }

    #[test]
    fn counts_calls_by_operation() {
        counted("test.op", true);
        counted("test.op", true);
        counted("test.op", false);
        let stats = stats_json();
        assert_eq!(stats["calls"]["test.op"], json!([2, 1]));
    }

    // The DHT's lines as the core takes them: none kept until it takes with `keep`, none once it takes without.
    #[test]
    fn dht_said() {
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().to_path_buf(), complete, ctx()).unwrap();
        let said = |keep: bool| shell.inner.run_sync("dht.said", &json!({ "keep": keep })).unwrap();
        assert_eq!(said(false), json!({ "lines": [], "dropped": 0 }));
        assert_eq!(said(true), json!({ "lines": [], "dropped": 0 }));
    }

    #[test]
    fn answers_of_a_closed_endpoint() {
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().to_path_buf(), complete, ctx()).unwrap();
        let inner = shell.inner.clone();
        shell.runtime.block_on(async move {
            let endpoint = Endpoint::builder(Minimal).relay_mode(RelayMode::Disabled).bind().await.unwrap();
            let id = inner.keep(Handle::Endpoint(endpoint.clone(), Arc::default()));
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

    #[cfg(unix)]
    #[test]
    fn pipes_a_stream_into_a_socket_in_frames() {
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().to_path_buf(), complete, ctx()).unwrap();
        let inner = shell.inner.clone();
        shell.runtime.block_on(async move {
            let alpn = b"stillfail/test".to_vec();
            let bind = |alpns: Vec<Vec<u8>>| Endpoint::builder(Minimal).relay_mode(RelayMode::Disabled).alpns(alpns).bind();
            let (a, b) = (bind(vec![]).await.unwrap(), bind(vec![alpn.clone()]).await.unwrap());
            let port = b.bound_sockets().iter().find(|s| s.is_ipv4()).unwrap().port();
            let addr = endpoint_addr(&json!({ "id": hex::encode(b.id().as_bytes()), "ips": [format!("127.0.0.1:{port}")] })).unwrap();
            let taking = b.clone();
            let taken = tokio::spawn(async move { taking.accept().await.unwrap().await.unwrap() });
            let id = inner.keep_conn(a.connect(addr, &alpn).await.unwrap());
            let theirs = taken.await.unwrap();
            let stream = inner.run("conn.openBi", json!({ "id": id }), None).await.unwrap().json["id"].as_u64().unwrap();
            let (ours, node) = tokio::net::UnixStream::pair().unwrap();
            let (read, write) = ours.into_split();
            let socket = inner.keep(Handle::Tcp { read: Arc::new(tokio::sync::Mutex::new(Box::new(read))), write: Arc::new(tokio::sync::Mutex::new(Box::new(write))) });
            let piping = {
                let inner = inner.clone();
                tokio::spawn(async move { inner.run("istream.pipe", json!({ "id": stream, "to": socket }), None).await })
            };
            // what the socket's side writes, in frames, its end finishing the stream
            let (mut node_read, mut node_write) = node.into_split();
            let sent: Vec<u8> = (0..200_000u32).map(|i| (i % 251) as u8).collect();
            let mut framed = Vec::new();
            for piece in sent.chunks(70_000) {
                framed.extend((piece.len() as u32).to_be_bytes());
                framed.extend(piece);
            }
            framed.extend(PIPE_END.to_be_bytes());
            node_write.write_all(&framed).await.unwrap();
            let (mut send, mut recv) = theirs.accept_bi().await.unwrap();
            assert_eq!(recv.read_to_end(1 << 20).await.unwrap(), sent);
            // what comes on the stream, read in frames by the socket's side, then its end
            send.write_all(b"back").await.unwrap();
            send.finish().unwrap();
            let mut got = Vec::new();
            node_read.read_to_end(&mut got).await.unwrap();
            let mut want = 4u32.to_be_bytes().to_vec();
            want.extend(b"back");
            want.extend(PIPE_END.to_be_bytes());
            assert_eq!(got, want);
            piping.await.unwrap().unwrap();

            // the socket ending without its end resets the stream; the other end's reset is said as what failed it
            let stream = inner.run("conn.openBi", json!({ "id": id }), None).await.unwrap().json["id"].as_u64().unwrap();
            let (ours, node) = tokio::net::UnixStream::pair().unwrap();
            let (read, write) = ours.into_split();
            let socket = inner.keep(Handle::Tcp { read: Arc::new(tokio::sync::Mutex::new(Box::new(read))), write: Arc::new(tokio::sync::Mutex::new(Box::new(write))) });
            let piping = {
                let inner = inner.clone();
                tokio::spawn(async move { inner.run("istream.pipe", json!({ "id": stream, "to": socket }), None).await })
            };
            let (mut node_read, mut node_write) = node.into_split();
            node_write.write_all(&[0, 0, 0, 1, 7]).await.unwrap();
            let (mut send, mut recv) = theirs.accept_bi().await.unwrap();
            let mut one = [0u8; 1];
            recv.read_exact(&mut one).await.unwrap();
            drop(node_write);
            assert!(recv.read_to_end(1024).await.is_err());
            send.reset(5u32.into()).unwrap();
            let mut got = Vec::new();
            node_read.read_to_end(&mut got).await.unwrap();
            assert_eq!(&got[..4], &PIPE_FAILED.to_be_bytes());
            assert!(String::from_utf8_lossy(&got[8..]).contains('5'), "{}", String::from_utf8_lossy(&got[8..]));
            piping.await.unwrap().unwrap();
        });
    }

    #[test]
    fn lets_a_closed_connection_and_its_streams_go() {
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().to_path_buf(), complete, ctx()).unwrap();
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
            assert_eq!(inner.run_sync("conn.closeReason", &json!({ "id": id })).unwrap(), json!({ "kind": "application", "reason": "bye", "text": "closed by peer: bye (code 7)" }));
            assert_eq!(inner.run_sync("conn.remoteId", &json!({ "id": id })).unwrap(), remote);
            assert_eq!(inner.run_sync("conn.paths", &json!({ "id": id })).unwrap(), json!([]));
            assert_eq!(inner.run("conn.closed", json!({ "id": id }), None).await.unwrap().json, json!({ "kind": "application", "reason": "bye", "text": "closed by peer: bye (code 7)" }));
            assert!(inner.run("conn.openBi", json!({ "id": id }), None).await.is_err());
            assert_eq!(inner.run("conn.acceptBi", json!({ "id": id }), None).await.unwrap().json, json!({ "end": true }));
        });
    }

    #[cfg(unix)]
    #[test]
    fn closing_a_connection_stops_a_half_open_piped_socket() {
        let dir = TempDir::new();
        let shell = Shell::start(dir.path().to_path_buf(), complete, ctx()).unwrap();
        let inner = shell.inner.clone();
        shell.runtime.block_on(async move {
            let alpn = b"stillfail/test".to_vec();
            let bind = |alpns: Vec<Vec<u8>>| Endpoint::builder(Minimal).relay_mode(RelayMode::Disabled).alpns(alpns).bind();
            let (a, b) = (bind(vec![]).await.unwrap(), bind(vec![alpn.clone()]).await.unwrap());
            let port = b.bound_sockets().iter().find(|s| s.is_ipv4()).unwrap().port();
            let addr = endpoint_addr(&json!({ "id": hex::encode(b.id().as_bytes()), "ips": [format!("127.0.0.1:{port}")] })).unwrap();
            let taking = b.clone();
            let taken = tokio::spawn(async move { taking.accept().await.unwrap().await.unwrap() });
            let id = inner.keep_conn(a.connect(addr, &alpn).await.unwrap());
            let theirs = taken.await.unwrap();
            let stream = inner.run("conn.openBi", json!({ "id": id }), None).await.unwrap().json["id"].as_u64().unwrap();
            let (ours, node) = tokio::net::UnixStream::pair().unwrap();
            let (read, write) = ours.into_split();
            let socket = inner.keep(Handle::Tcp { read: Arc::new(tokio::sync::Mutex::new(Box::new(read))), write: Arc::new(tokio::sync::Mutex::new(Box::new(write))) });
            let piping = {
                let inner = inner.clone();
                tokio::spawn(async move { inner.run("istream.pipe", json!({ "id": stream, "to": socket }), None).await })
            };
            let (mut _node_read, mut node_write) = node.into_split();
            node_write.write_all(&[0, 0, 0, 1, 9]).await.unwrap();
            let _peer = theirs.accept_bi().await.unwrap();
            // Even while Node keeps its Unix socket open, closing the connection ends the pipe.
            theirs.close(0u32.into(), b"bye");
            piping.await.unwrap().unwrap();
            assert!(inner.handle(stream).is_err());
        });
    }
}
