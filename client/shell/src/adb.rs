//! This phone's own adb session (docs/adb-share.md, 2026-10-31, user: 「按理说不是应该 app 自己连接然后给 station 用吗」):
//! the app pairs with its own adbd once, with a key of its own (`adb/adbkey` in the data directory), and holds one
//! session to it (TLS, as Wireless debugging speaks) for as long as its process lives. A station's adb reaches the phone
//! through a session of its own here (`adb.open`): it says CNXN and is answered at once with the phone's banner (no
//! AUTH, no STLS: the station is let in by the chat's grant before its bytes come here), and its streams are carried on
//! the one held session, their ids made unique among the stations'. A station going (restarted, its link moved) ends
//! its streams only: the phone's session, and Android's 「已连接到无线调试」 with it, stays.
//!
//! Before, each station's adb held a session of its own to adbd, under its own key: every station had to be paired
//! once, and a station restarted ended its session and started one anew, Android saying so each time.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use embedded_io_async::Write as _;
use libadb::keys::rsa::rand_core::OsRng;
use libadb::keys::store;
use libadb::transport::tls::MaybeTls;
use libadb::{AdbKey, Connection, ConnectionConfig, Splittable, TlsClientConfig, TlsIdentity, TokioTcp};
use tokio::io::{AsyncReadExt, AsyncWriteExt, DuplexStream};
use tokio::sync::mpsc;

const CNXN: u32 = 0x4e58_4e43;
const AUTH: u32 = 0x4854_5541;
const OPEN: u32 = 0x4e45_504f;
const OKAY: u32 = 0x5941_4b4f;
const CLSE: u32 = 0x4553_4c43;
const WRTE: u32 = 0x4554_5257;
const STLS: u32 = 0x534c_5453;
/// What this side says it takes in one packet (adb's own `MAX_PAYLOAD`).
const MAX_PAYLOAD: u32 = 1024 * 1024;
/// The key's name, as adbd lists it among its trusted hosts.
const KEY_NAME: &str = "still.fail";

/// The features this side asks adbd for, which the stations are then told the phone has (those adbd has too): adb's
/// own host's, but `delayed_ack`, whose windows are a session's and not a stream's (one session here carries many
/// stations').
const FEATURES: &[&str] = &[
    "shell_v2", "cmd", "stat_v2", "ls_v2", "fixed_push_mkdir", "apex", "abb", "fixed_push_symlink_timestamp", "abb_exec", "remount_shell", "track_app",
    "sendrecv_v2", "sendrecv_v2_brotli", "sendrecv_v2_lz4", "sendrecv_v2_zstd", "sendrecv_v2_dry_run_send", "openscreen_mdns", "devicetracker_proto_format",
    "devraw", "app_info", "server_status",
];

/// One adb packet: its command, its two arguments, its payload.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Packet {
    pub cmd: u32,
    pub arg0: u32,
    pub arg1: u32,
    pub data: Vec<u8>,
}

impl Packet {
    fn new(cmd: u32, arg0: u32, arg1: u32, data: Vec<u8>) -> Packet {
        Packet { cmd, arg0, arg1, data }
    }

    fn header(&self) -> [u8; 24] {
        let check = self.data.iter().fold(0u32, |s, b| s.wrapping_add(*b as u32));
        let mut h = [0u8; 24];
        for (i, v) in [self.cmd, self.arg0, self.arg1, self.data.len() as u32, check, self.cmd ^ 0xffff_ffff].iter().enumerate() {
            h[i * 4..i * 4 + 4].copy_from_slice(&v.to_le_bytes());
        }
        h
    }

    fn bytes(&self) -> Vec<u8> {
        let mut out = self.header().to_vec();
        out.extend_from_slice(&self.data);
        out
    }

    /// A packet's header read: its command, arguments and payload's length (a payload past `MAX_PAYLOAD` is not one).
    fn parse_header(h: &[u8; 24]) -> Result<(u32, u32, u32, usize), String> {
        let word = |i: usize| u32::from_le_bytes(h[i * 4..i * 4 + 4].try_into().unwrap());
        let (cmd, len, magic) = (word(0), word(3), word(5));
        if magic != cmd ^ 0xffff_ffff {
            return Err("not an adb packet".into());
        }
        if len > MAX_PAYLOAD {
            return Err(format!("an adb packet of {len} bytes"));
        }
        Ok((cmd, word(1), word(2), len as usize))
    }
}

/// The next packet off a station's session; none at its end.
async fn read_packet(r: &mut (impl tokio::io::AsyncRead + Unpin)) -> Result<Option<Packet>, String> {
    let mut h = [0u8; 24];
    match r.read_exact(&mut h).await {
        Ok(_) => {}
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(e.to_string()),
    }
    let (cmd, arg0, arg1, len) = Packet::parse_header(&h)?;
    let mut data = vec![0u8; len];
    r.read_exact(&mut data).await.map_err(|e| e.to_string())?;
    Ok(Some(Packet { cmd, arg0, arg1, data }))
}

/// Bytes off adbd's session, what was read ahead of it first.
struct DeviceReader<R> {
    ahead: Vec<u8>,
    read: R,
}

impl<R: embedded_io_async::Read> DeviceReader<R>
where
    R::Error: std::fmt::Display,
{
    async fn fill(&mut self, buf: &mut [u8]) -> Result<bool, String> {
        let mut at = 0;
        while at < buf.len() {
            if !self.ahead.is_empty() {
                let n = self.ahead.len().min(buf.len() - at);
                buf[at..at + n].copy_from_slice(&self.ahead[..n]);
                self.ahead.drain(..n);
                at += n;
                continue;
            }
            let n = self.read.read(&mut buf[at..]).await.map_err(|e| e.to_string())?;
            if n == 0 {
                return if at == 0 { Ok(false) } else { Err("adbd's session ended inside a packet".into()) };
            }
            at += n;
        }
        Ok(true)
    }

    async fn packet(&mut self) -> Result<Option<Packet>, String> {
        let mut h = [0u8; 24];
        if !self.fill(&mut h).await? {
            return Ok(None);
        }
        let (cmd, arg0, arg1, len) = Packet::parse_header(&h)?;
        let mut data = vec![0u8; len];
        if !self.fill(&mut data).await? && len > 0 {
            return Err("adbd's session ended inside a packet".into());
        }
        Ok(Some(Packet { cmd, arg0, arg1, data }))
    }
}

/// The phone's banner as the stations are told it: adbd's own, its features those of its that this side asked for
/// (the ones the held session has).
fn station_banner(device: &[u8]) -> Vec<u8> {
    let text = String::from_utf8_lossy(device);
    let text = text.trim_end_matches('\0');
    let (head, props) = match text.split_once("::") {
        Some((head, props)) => (head, props),
        None => return device.to_vec(),
    };
    let props: Vec<String> = props
        .split(';')
        .filter(|p| !p.is_empty())
        .map(|p| match p.strip_prefix("features=") {
            Some(list) => format!("features={}", list.split(',').filter(|f| FEATURES.contains(f)).collect::<Vec<_>>().join(",")),
            None => p.to_string(),
        })
        .collect();
    format!("{head}::{}", props.join(";")).into_bytes()
}

/// Which stream of which station an id on the held session is, and the other ends' ids.
#[derive(Default)]
pub(crate) struct Routes {
    next: u32,
    /// By the id this side gave a stream on the held session: its station's session and the id that station gave it.
    ours: HashMap<u32, (u64, u32)>,
    /// By station session and its id: ours.
    theirs: HashMap<(u64, u32), u32>,
    /// By ours: adbd's id of the stream, once it said it.
    device: HashMap<u32, u32>,
    /// The stations' sessions, where what adbd says of their streams goes.
    sessions: HashMap<u64, mpsc::UnboundedSender<Packet>>,
    /// The station session that last asked adbd to open streams back to it (`reverse:`): where a stream adbd opens
    /// goes.
    reverse: Option<u64>,
}

impl Routes {
    fn ours_for(&mut self, session: u64, theirs: u32) -> u32 {
        if let Some(ours) = self.theirs.get(&(session, theirs)) {
            return *ours;
        }
        loop {
            self.next = self.next.wrapping_add(1);
            if self.next != 0 && !self.ours.contains_key(&self.next) {
                break;
            }
        }
        let ours = self.next;
        self.ours.insert(ours, (session, theirs));
        self.theirs.insert((session, theirs), ours);
        ours
    }

    fn forget(&mut self, ours: u32) {
        if let Some((session, theirs)) = self.ours.remove(&ours) {
            self.theirs.remove(&(session, theirs));
        }
        self.device.remove(&ours);
    }

    /// A station's packet as adbd is to have it (none: nothing goes to adbd).
    pub(crate) fn of_station(&mut self, session: u64, p: Packet) -> Option<Packet> {
        match p.cmd {
            OPEN => {
                if p.data.starts_with(b"reverse:") {
                    self.reverse = Some(session);
                }
                let ours = self.ours_for(session, p.arg0);
                Some(Packet { arg0: ours, ..p })
            }
            OKAY | WRTE | CLSE => {
                // A stream adbd opened, turned down: nothing of the station's to name.
                if p.arg0 == 0 {
                    return Some(p);
                }
                let ours = match self.theirs.get(&(session, p.arg0)) {
                    Some(ours) => *ours,
                    // The station taking up a stream adbd opened.
                    None if p.cmd == OKAY => self.ours_for(session, p.arg0),
                    None => return None,
                };
                if p.cmd == OKAY {
                    self.device.insert(ours, p.arg1);
                }
                if p.cmd == CLSE {
                    self.forget(ours);
                }
                Some(Packet { arg0: ours, ..p })
            }
            _ => None,
        }
    }

    /// Where adbd's packet goes: its station session and the packet as that station is to have it; or, for one of a
    /// stream no station has now, what adbd is told back.
    pub(crate) fn of_device(&mut self, p: Packet) -> Result<(u64, Packet), Option<Packet>> {
        match p.cmd {
            OPEN => match self.reverse.filter(|s| self.sessions.contains_key(s)) {
                Some(session) => Ok((session, p)),
                None => Err(Some(Packet::new(CLSE, 0, p.arg0, Vec::new()))),
            },
            OKAY | WRTE | CLSE => match self.ours.get(&p.arg1).copied() {
                Some((session, theirs)) => {
                    if p.cmd == OKAY {
                        self.device.insert(p.arg1, p.arg0);
                    }
                    if p.cmd == CLSE {
                        self.forget(p.arg1);
                    }
                    Ok((session, Packet { arg1: theirs, ..p }))
                }
                // Its station gone: closed on adbd too.
                None if p.cmd != CLSE && p.arg1 != 0 => Err(Some(Packet::new(CLSE, p.arg1, p.arg0, Vec::new()))),
                None => Err(None),
            },
            _ => Err(None),
        }
    }

    /// A station's session ended: what adbd is told to close of its streams.
    pub(crate) fn end(&mut self, session: u64) -> Vec<Packet> {
        self.sessions.remove(&session);
        if self.reverse == Some(session) {
            self.reverse = None;
        }
        let ours: Vec<u32> = self.ours.iter().filter(|(_, (s, _))| *s == session).map(|(o, _)| *o).collect();
        ours.into_iter()
            .map(|o| {
                let device = self.device.get(&o).copied().unwrap_or(0);
                self.forget(o);
                Packet::new(CLSE, o, device, Vec::new())
            })
            .collect()
    }
}

/// The session held to adbd.
struct Held {
    port: u16,
    /// adbd's CNXN: its protocol version, how much it takes in a packet, its banner as the stations are told it.
    version: u32,
    max: u32,
    banner: Vec<u8>,
    out: mpsc::UnboundedSender<Packet>,
    routes: Mutex<Routes>,
    alive: AtomicBool,
}

impl Held {
    fn send(&self, p: Packet) {
        let _ = self.out.send(p);
    }
}

/// The phone's adb: its key and the session held to adbd.
pub(crate) struct Adb {
    dir: PathBuf,
    held: tokio::sync::Mutex<Option<Arc<Held>>>,
    next: std::sync::atomic::AtomicU64,
}

fn key(dir: &Path) -> Result<AdbKey, String> {
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    store::load_or_generate(dir, &mut OsRng, KEY_NAME).map_err(|e| e.to_string())
}

fn tls_of(key: &AdbKey) -> Result<TlsClientConfig, String> {
    let identity = TlsIdentity::from_key(key, &mut OsRng).map_err(|e| e.to_string())?;
    TlsClientConfig::adb(&identity).map_err(|e| e.to_string())
}

impl Adb {
    pub(crate) fn new(dir: PathBuf) -> Adb {
        Adb { dir: dir.join("adb"), held: tokio::sync::Mutex::new(None), next: std::sync::atomic::AtomicU64::new(1) }
    }

    /// Paired with adbd's pairing port (open while 使用配对码配对设备 is), with the six digits it shows.
    pub(crate) async fn pair(&self, port: u16, code: &str) -> Result<(), String> {
        let key = key(&self.dir)?;
        let tls = tls_of(&key)?;
        let socket = tokio::net::TcpStream::connect(("127.0.0.1", port)).await.map_err(|e| e.to_string())?;
        let mut transport = MaybeTls::plain(TokioTcp::new(socket));
        libadb::pairing::pair(&mut transport, &tls, &key, code, &mut OsRng).await.map_err(|e| match e {
            libadb::pairing::PairingError::WrongCode => "wrong code".to_string(),
            e => e.to_string(),
        })?;
        Ok(())
    }

    /// The session to adbd at `port` held (started if none is, or the one held is to another port or has ended).
    /// `unpaired` when adbd does not take the key.
    pub(crate) async fn hold(&self, port: u16) -> Result<(), String> {
        let mut held = self.held.lock().await;
        if let Some(h) = held.as_ref() {
            if h.port == port && h.alive.load(Ordering::SeqCst) {
                return Ok(());
            }
            h.alive.store(false, Ordering::SeqCst);
            let sessions: Vec<_> = h.routes.lock().unwrap().sessions.drain().collect();
            drop(sessions);
        }
        *held = None;
        let key = key(&self.dir)?;
        let tls = tls_of(&key)?;
        let socket = tokio::net::TcpStream::connect(("127.0.0.1", port)).await.map_err(|e| e.to_string())?;
        let _ = socket.set_nodelay(true);
        let banner = format!("host::features={}", FEATURES.join(","));
        let conn: Connection<MaybeTls<TokioTcp>> =
            Connection::connect_tls_with_raw_banner_and_config(MaybeTls::plain(TokioTcp::new(socket)), key, banner.as_bytes(), &tls, ConnectionConfig::new())
                .await
                .map_err(|e| match e {
                    libadb::Error::Auth(libadb::error::AuthError::TlsKeyNotTrusted) => "unpaired".to_string(),
                    e => e.to_string(),
                })?;
        let (version, max) = (conn.protocol_version(), conn.max_payload());
        let device_banner = station_banner(conn.device_banner().unwrap_or_default());
        let (transport, ahead) = conn.into_parts();
        let (read, mut write) = transport.split().map_err(|e| e.to_string())?;
        let (out, mut outgoing) = mpsc::unbounded_channel::<Packet>();
        let h = Arc::new(Held { port, version, max, banner: device_banner, out, routes: Mutex::new(Routes::default()), alive: AtomicBool::new(true) });
        // What goes to adbd, one packet after another.
        let writer = h.clone();
        tokio::spawn(async move {
            while let Some(p) = outgoing.recv().await {
                if write.write_all(&p.bytes()).await.is_err() || write.flush().await.is_err() {
                    break;
                }
            }
            writer.alive.store(false, Ordering::SeqCst);
        });
        // What adbd says, to the station whose stream it is.
        let reader = h.clone();
        tokio::spawn(async move {
            let mut device = DeviceReader { ahead: ahead.to_vec(), read };
            while let Ok(Some(p)) = device.packet().await {
                let routed = reader.routes.lock().unwrap().of_device(p);
                match routed {
                    Ok((session, p)) => {
                        let to = reader.routes.lock().unwrap().sessions.get(&session).cloned();
                        if let Some(to) = to {
                            let _ = to.send(p);
                        }
                    }
                    Err(Some(back)) => reader.send(back),
                    Err(None) => {}
                }
            }
            reader.alive.store(false, Ordering::SeqCst);
            // The stations' sessions end with it.
            let sessions: Vec<_> = reader.routes.lock().unwrap().sessions.drain().collect();
            drop(sessions);
        });
        *held = Some(h);
        Ok(())
    }

    /// Whether a session to adbd is held now, and to which port.
    pub(crate) async fn state(&self) -> Option<u16> {
        self.held.lock().await.as_ref().filter(|h| h.alive.load(Ordering::SeqCst)).map(|h| h.port)
    }

    /// A station's session: its end of a pipe, the other served here on the held session. Fails while none is held.
    pub(crate) async fn open(&self) -> Result<DuplexStream, String> {
        let held = self.held.lock().await.clone().filter(|h| h.alive.load(Ordering::SeqCst)).ok_or("no adb session")?;
        let (station, here) = tokio::io::duplex(2 * MAX_PAYLOAD as usize);
        let session = self.next.fetch_add(1, Ordering::SeqCst);
        tokio::spawn(serve(held, session, here));
        Ok(station)
    }
}

/// One station's session, served on the held one until either ends.
async fn serve(held: Arc<Held>, session: u64, pipe: DuplexStream) {
    let (mut read, mut write) = tokio::io::split(pipe);
    // The station's CNXN, answered with the phone's at once: no AUTH, no STLS.
    let hello = loop {
        match read_packet(&mut read).await {
            Ok(Some(p)) if p.cmd == CNXN => break p,
            Ok(Some(_)) => continue,
            _ => return,
        }
    };
    let cnxn = Packet::new(CNXN, hello.arg0.min(held.version), hello.arg1.min(held.max), held.banner.clone());
    if write.write_all(&cnxn.bytes()).await.is_err() {
        return;
    }
    let (to, mut incoming) = mpsc::unbounded_channel::<Packet>();
    held.routes.lock().unwrap().sessions.insert(session, to);
    // What adbd says of this station's streams, to it.
    let writer = tokio::spawn(async move {
        while let Some(p) = incoming.recv().await {
            if write.write_all(&p.bytes()).await.is_err() {
                break;
            }
        }
        let _ = write.shutdown().await;
    });
    while let Ok(Some(p)) = read_packet(&mut read).await {
        if matches!(p.cmd, CNXN | AUTH | STLS) {
            continue;
        }
        let out = held.routes.lock().unwrap().of_station(session, p);
        if let Some(out) = out {
            held.send(out);
        }
    }
    let closes = held.routes.lock().unwrap().end(session);
    for p in closes {
        held.send(p);
    }
    writer.abort();
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(cmd: u32, arg0: u32, arg1: u32) -> Packet {
        Packet::new(cmd, arg0, arg1, Vec::new())
    }

    fn with_sessions(n: u64) -> (Routes, Vec<mpsc::UnboundedReceiver<Packet>>) {
        let mut routes = Routes::default();
        let mut rx = Vec::new();
        for s in 1..=n {
            let (tx, r) = mpsc::unbounded_channel();
            routes.sessions.insert(s, tx);
            rx.push(r);
        }
        (routes, rx)
    }

    #[test]
    fn two_stations_streams_of_the_same_id_are_told_apart() {
        let (mut r, _rx) = with_sessions(2);
        let a = r.of_station(1, Packet::new(OPEN, 1, 0, b"shell:\0".to_vec())).unwrap();
        let b = r.of_station(2, Packet::new(OPEN, 1, 0, b"shell:\0".to_vec())).unwrap();
        assert_ne!(a.arg0, b.arg0);
        // adbd takes both up, as its streams 7 and 8.
        assert_eq!(r.of_device(p(OKAY, 7, a.arg0)), Ok((1, p(OKAY, 7, 1))));
        assert_eq!(r.of_device(p(OKAY, 8, b.arg0)), Ok((2, p(OKAY, 8, 1))));
        // Each station's write goes on its own stream.
        assert_eq!(r.of_station(2, p(WRTE, 1, 8)), Some(p(WRTE, b.arg0, 8)));
        assert_eq!(r.of_station(1, p(WRTE, 1, 7)), Some(p(WRTE, a.arg0, 7)));
    }

    #[test]
    fn a_station_gone_closes_its_streams_on_adbd_and_no_one_elses() {
        let (mut r, _rx) = with_sessions(2);
        let a = r.of_station(1, Packet::new(OPEN, 5, 0, b"shell:\0".to_vec())).unwrap();
        let b = r.of_station(2, Packet::new(OPEN, 5, 0, b"shell:\0".to_vec())).unwrap();
        r.of_device(p(OKAY, 7, a.arg0)).unwrap();
        r.of_device(p(OKAY, 8, b.arg0)).unwrap();
        assert_eq!(r.end(1), vec![p(CLSE, a.arg0, 7)]);
        // What adbd still says of the gone station's stream is closed back; the other's goes on.
        assert_eq!(r.of_device(p(WRTE, 7, a.arg0)), Err(Some(p(CLSE, a.arg0, 7))));
        assert_eq!(r.of_device(p(WRTE, 8, b.arg0)), Ok((2, p(WRTE, 8, 5))));
    }

    #[test]
    fn a_stream_adbd_opens_goes_to_the_station_that_asked_for_reverse() {
        let (mut r, _rx) = with_sessions(2);
        r.of_station(2, Packet::new(OPEN, 3, 0, b"reverse:forward:tcp:8080;tcp:8080\0".to_vec())).unwrap();
        let open = Packet::new(OPEN, 40, 0, b"tcp:8080\0".to_vec());
        assert_eq!(r.of_device(open.clone()), Ok((2, open)));
        // The station takes it up as its stream 9.
        let okay = r.of_station(2, p(OKAY, 9, 40)).unwrap();
        assert_eq!(okay.arg1, 40);
        assert_eq!(r.of_device(p(WRTE, 40, okay.arg0)), Ok((2, p(WRTE, 40, 9))));
        // With no station asking, adbd's is turned down.
        r.end(2);
        assert_eq!(r.of_device(Packet::new(OPEN, 41, 0, b"tcp:8080\0".to_vec())), Err(Some(p(CLSE, 0, 41))));
    }

    #[test]
    fn the_stations_are_told_only_the_features_the_held_session_has() {
        let banner = station_banner(b"device::ro.product.name=x;ro.product.model=Pixel;features=shell_v2,delayed_ack,cmd,abb_exec\0");
        assert_eq!(String::from_utf8(banner).unwrap(), "device::ro.product.name=x;ro.product.model=Pixel;features=shell_v2,cmd,abb_exec");
    }

    /// On a real adbd (`ADB_TEST_DIR` keeps the key; `ADB_TEST_CONNECT`, adbd's port forwarded here; `ADB_TEST_PAIR`
    /// and `ADB_TEST_CODE` pair first): the session held, and a station's session on it for each connection to
    /// 127.0.0.1:`ADB_TEST_LISTEN`, for `ADB_TEST_SECS` (scripts drive a real adb at it meanwhile).
    #[tokio::test]
    #[ignore]
    async fn on_a_device() {
        let var = |k: &str| std::env::var(k).unwrap_or_default();
        let adb = Arc::new(Adb::new(PathBuf::from(var("ADB_TEST_DIR"))));
        if !var("ADB_TEST_PAIR").is_empty() {
            adb.pair(var("ADB_TEST_PAIR").parse().unwrap(), &var("ADB_TEST_CODE")).await.unwrap();
            eprintln!("ADB_TEST paired");
        }
        adb.hold(var("ADB_TEST_CONNECT").parse().unwrap()).await.unwrap();
        eprintln!("ADB_TEST held");
        let listener = tokio::net::TcpListener::bind(("127.0.0.1", var("ADB_TEST_LISTEN").parse::<u16>().unwrap())).await.unwrap();
        let serving = adb.clone();
        tokio::spawn(async move {
            while let Ok((mut socket, _)) = listener.accept().await {
                let mut session = serving.open().await.unwrap();
                tokio::spawn(async move {
                    let _ = tokio::io::copy_bidirectional(&mut socket, &mut session).await;
                });
            }
        });
        tokio::time::sleep(std::time::Duration::from_secs(var("ADB_TEST_SECS").parse().unwrap())).await;
        assert_eq!(adb.state().await, Some(var("ADB_TEST_CONNECT").parse().unwrap()), "the held session ended");
    }

    #[test]
    fn packets_go_out_as_adb_reads_them() {
        let packet = Packet::new(WRTE, 3, 4, b"hi".to_vec());
        let bytes = packet.bytes();
        let (cmd, arg0, arg1, len) = Packet::parse_header(bytes[..24].try_into().unwrap()).unwrap();
        assert_eq!((cmd, arg0, arg1, len), (WRTE, 3, 4, 2));
        assert_eq!(u32::from_le_bytes(bytes[16..20].try_into().unwrap()), b'h' as u32 + b'i' as u32);
    }
}
