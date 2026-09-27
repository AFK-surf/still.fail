//! ember-station: an ember station, as launchd (or the desktop app) runs it.
//!
//! `run` runs the station: its Node part (src/main.ts) as a child, watched and started again when it ends (node.rs);
//! the admin page on a loopback port for a browser here (local.rs); and, once the station is in a workspace, its way
//! into ember cloud. It holds a presence socket to ember cloud (connected is online) while the Node part is up — which
//! also brings what ember cloud revokes — accepts iroh connections from clients that present a member's credential
//! signed by ember cloud (checked offline: the cloud need not be reachable), and relays each stream's request to the
//! Node part's admin API, on its Unix socket, with the verified identity attached. `enroll` redeems a one-time token
//! from a workspace admin, proving this station holds its iroh key.
//!
//! Wire format on ALPN `ember/admin/1`: the first bidirectional stream carries
//! credentials (`{"credential": …}`, one JSON line each, answered with one JSON line; a later line
//! renews). Every other stream is one request: a JSON head line
//! `{"method","path","headers"}`, then the body until the stream finishes;
//! answered by a JSON head line `{"status","headers"}` and the response body.
//! A request's `traceparent` header is passed on to the admin API (see telemetry.rs).

mod local;
mod node;
mod telemetry;

use std::{
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use anyhow::{Context, Result, anyhow, bail};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD as B64};
use futures_util::{SinkExt, StreamExt};
use iroh::{
    Endpoint, RelayMode, RelayUrl, SecretKey,
    endpoint::{Connection, QuicTransportConfig, RecvStream, SendStream, presets::Minimal},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use tokio::sync::watch;
use tokio_tungstenite::tungstenite::{self, Message, client::IntoClientRequest};
use tracing::{info, warn};

use crate::telemetry::{Parent, Telemetry, route};

const ALPN: &[u8] = b"ember/admin/1";
/// Headers of one hop, not of what is relayed.
const HOP: [&str; 9] = ["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "te", "trailer", "host", "content-length"];
const MAX_HEAD: usize = 16 * 1024;
// Files sent to a session go through here; the station caps them at 50 MB.
const MAX_BODY: usize = 64 * 1024 * 1024;
const VERSION: &str = env!("CARGO_PKG_VERSION");
/// ember cloud expects a "ping" this often and drops a station silent for three of them.
const PING: Duration = Duration::from_secs(30);
/// How ember cloud closes the socket of a station removed from its workspace.
const CLOSE_REMOVED: u16 = 4004;

#[derive(Serialize, Deserialize, Clone)]
struct CloudState {
    origin: String,
    station: String,
    workspace: String,
    workspace_name: String,
    name: String,
    relay_url: String,
    grant_keys: Value,
    /// What ember cloud took back (a member removed, a role changed, a session signed out): credentials of that
    /// account (`sub`) or session (`sid`) issued up to `at` are refused. Kept, so it holds with the cloud away.
    #[serde(default)]
    revocations: Vec<Revocation>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
struct Revocation {
    kind: String,
    id: String,
    at: u64,
}

fn mesh_dir(data: &Path) -> PathBuf {
    data.join("mesh")
}

/// The station's iroh key, created on first use and kept private.
fn load_key(data: &Path) -> Result<SecretKey> {
    let path = mesh_dir(data).join("secret.key");
    if let Ok(bytes) = std::fs::read(&path) {
        let bytes: [u8; 32] = bytes.try_into().map_err(|_| anyhow!("{} is not a 32-byte key", path.display()))?;
        return Ok(SecretKey::from_bytes(&bytes));
    }
    std::fs::create_dir_all(mesh_dir(data))?;
    let key = SecretKey::generate();
    write_private(&path, &key.to_bytes())?;
    Ok(key)
}

fn write_private(path: &Path, bytes: &[u8]) -> Result<()> {
    use std::{io::Write, os::unix::fs::OpenOptionsExt};
    let tmp = path.with_extension("tmp");
    let mut file = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&tmp)?;
    file.write_all(bytes)?;
    file.sync_all()?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

fn load_state(data: &Path) -> Result<CloudState> {
    let path = mesh_dir(data).join("cloud.json");
    let text = std::fs::read_to_string(&path).with_context(|| format!("{} is missing: enroll this station first", path.display()))?;
    Ok(serde_json::from_str(&text)?)
}

fn save_state(data: &Path, state: &CloudState) -> Result<()> {
    write_private(&mesh_dir(data).join("cloud.json"), serde_json::to_string_pretty(state)?.as_bytes())
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs()
}

fn http() -> reqwest::Client {
    reqwest::Client::builder().timeout(Duration::from_secs(20)).build().expect("http client")
}

async fn cloud_error(response: reqwest::Response) -> anyhow::Error {
    let status = response.status();
    let body = response.text().await.unwrap_or_default();
    anyhow!("ember cloud answered {status}: {body}")
}

async fn enroll(data: &Path, origin: &str, token: &str) -> Result<()> {
    let key = load_key(data)?;
    let station = hex::encode(key.public().as_bytes());
    let message = format!("ember-station-enroll-v1:{origin}:{token}:{station}");
    let signature = hex::encode(key.sign(message.as_bytes()).to_bytes());
    let response = http()
        .post(format!("{origin}/v1/stations/enroll"))
        .json(&json!({ "token": token, "station": station, "signature": signature, "version": VERSION }))
        .send()
        .await?;
    if !response.status().is_success() {
        return Err(cloud_error(response).await);
    }
    let body: Value = response.json().await?;
    let text = |k: &str| body[k].as_str().unwrap_or_default().to_string();
    let state = CloudState {
        origin: origin.to_string(),
        station: station.clone(),
        workspace: text("workspace"),
        workspace_name: text("workspace_name"),
        name: text("name"),
        relay_url: text("relay_url"),
        grant_keys: body["grant_keys"].clone(),
        revocations: Vec::new(),
    };
    save_state(data, &state)?;
    println!("已加入 workspace「{}」，这台 station 叫「{}」（{}）。", state.workspace_name, state.name, &station[..12]);
    Ok(())
}

/// Who a verified credential speaks for.
#[derive(Clone, Serialize)]
struct Viewer {
    sub: String,
    email: String,
    name: String,
    role: String,
    workspace: String,
    device: String,
}

/// A credential that checked out: who, until when, and what could take it back (when issued, which session).
#[derive(Clone)]
struct Admitted {
    viewer: Viewer,
    exp: u64,
    iat: u64,
    sid: String,
}

impl Admitted {
    /// Whether ember cloud took it back since it was issued.
    fn revoked(&self, revocations: &[Revocation]) -> bool {
        revocations.iter().any(|r| self.iat <= r.at && ((r.kind == "sub" && r.id == self.viewer.sub) || (r.kind == "sid" && r.id == self.sid)))
    }
}

/// Verifies a member's credential (ember cloud's, for this station's workspace, 30 days) for the connecting device,
/// offline: with the key pinned at enrollment, and what was revoked since.
fn verify_member(credential: &str, keys: &Value, workspace: &str, device: &str, revocations: &[Revocation]) -> Result<Admitted> {
    let mut parts = credential.split('.');
    let (Some(head), Some(body), Some(sig), None) = (parts.next(), parts.next(), parts.next(), parts.next()) else { bail!("malformed credential") };
    let header: Value = serde_json::from_slice(&B64.decode(head)?)?;
    if header["alg"] != "EdDSA" || header["typ"] != "ember-member+jwt" {
        bail!("not a member's credential");
    }
    let kid = header["kid"].as_str();
    let jwk = keys["keys"]
        .as_array()
        .and_then(|keys| keys.iter().find(|k| kid.is_none() || k["kid"].as_str() == kid))
        .ok_or_else(|| anyhow!("unknown credential key"))?;
    let x: [u8; 32] = B64.decode(jwk["x"].as_str().unwrap_or_default())?.try_into().map_err(|_| anyhow!("bad credential key"))?;
    let key = ed25519_dalek::VerifyingKey::from_bytes(&x)?;
    let signature = ed25519_dalek::Signature::from_slice(&B64.decode(sig)?)?;
    key.verify_strict(format!("{head}.{body}").as_bytes(), &signature).map_err(|_| anyhow!("credential signature invalid"))?;
    let claims: Value = serde_json::from_slice(&B64.decode(body)?)?;
    let text = |k: &str| claims[k].as_str().unwrap_or_default().to_string();
    if text("iss") != "ember-cloud" {
        bail!("credential not issued by ember cloud");
    }
    if text("ws") != workspace {
        bail!("credential is for another workspace");
    }
    if text("device") != device {
        bail!("credential is for another device");
    }
    let exp = claims["exp"].as_u64().unwrap_or(0);
    if exp <= now() {
        bail!("credential expired");
    }
    let admitted = Admitted {
        viewer: Viewer { sub: text("sub"), email: text("email"), name: text("name"), role: text("role"), workspace: text("ws"), device: device.to_string() },
        exp,
        iat: claims["iat"].as_u64().unwrap_or(0),
        sid: text("sid"),
    };
    if admitted.revoked(revocations) {
        bail!("credential revoked");
    }
    Ok(admitted)
}

/// Reads one newline-terminated JSON line; returns it and whatever followed.
async fn read_line(recv: &mut RecvStream, carry: &mut Vec<u8>) -> Result<Option<Value>> {
    loop {
        if let Some(i) = carry.iter().position(|&b| b == b'\n') {
            let line: Vec<u8> = carry.drain(..=i).collect();
            return Ok(Some(serde_json::from_slice(&line[..line.len() - 1])?));
        }
        if carry.len() > MAX_HEAD {
            bail!("head too large");
        }
        let mut buf = [0u8; 4096];
        match recv.read(&mut buf).await? {
            Some(n) => carry.extend_from_slice(&buf[..n]),
            None if carry.is_empty() => return Ok(None),
            None => bail!("stream ended mid-line"),
        }
    }
}

async fn write_line(send: &mut SendStream, value: &Value) -> Result<()> {
    let mut line = serde_json::to_vec(value)?;
    line.push(b'\n');
    send.write_all(&line).await?;
    Ok(())
}

struct Station {
    data: PathBuf,
    state: Mutex<CloudState>,
    /// The Node part's admin API, and whether it answers now.
    socket: PathBuf,
    ready: watch::Receiver<bool>,
    secret: String,
    removed: Mutex<bool>,
    telemetry: Arc<Telemetry>,
}

/// What `run` is given: where the data is, the app with the Node part and its interpreter, and the admin page's port.
struct Run {
    data: PathBuf,
    app: PathBuf,
    node: PathBuf,
    port: u16,
    named: bool,
    /// Ends when the process that started it does (the desktop app).
    with_parent: bool,
}

async fn run(options: Run) -> Result<()> {
    let data = options.data;
    let socket = data.join("run").join("admin.sock");
    std::fs::create_dir_all(data.join("run"))?;
    // One station per data directory: a second would take the first one's socket and port away.
    let _lock = lock(&data.join("run").join("station.lock"))?;
    let mut bytes = [0u8; 32];
    getrandom::fill(&mut bytes).map_err(|e| anyhow!("{e}"))?;
    let secret = B64.encode(bytes);
    let telemetry = Telemetry::new(traces_on(&data));
    let (ready_tx, ready) = watch::channel(false);
    let (stop_tx, stopping) = watch::channel(false);
    let launch = node::Launch { node: options.node, app: options.app, data: data.clone(), socket: socket.clone(), secret: secret.clone() };
    let supervised = tokio::spawn(node::supervise(launch, ready_tx, telemetry.clone(), stopping));
    let listener = local::bind(&data, options.port, options.named).await?;
    tokio::spawn(local::serve(listener, socket.clone(), ready.clone()));
    tokio::spawn(mesh(data.clone(), socket, ready, secret, telemetry));
    // SIGTERM (launchd, the desktop app) or ^C: the Node part ends its runtimes first. So does, with --with-parent, the
    // parent's end (the desktop app's, killed): orphaned, this would hold the machine's station with no app to stop it.
    // Run otherwise (launchd, nohup), the parent may well end first.
    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    tokio::select! {
        _ = term.recv() => {}
        _ = tokio::signal::ctrl_c() => {}
        _ = orphaned(), if options.with_parent => info!("parent ended"),
    }
    info!("stopping");
    stop_tx.send_replace(true);
    let _ = supervised.await;
    Ok(())
}

/// Resolves once this process's parent has ended (it is then another's child).
async fn orphaned() {
    // SAFETY: getppid has no preconditions.
    let parent = unsafe { libc::getppid() };
    loop {
        tokio::time::sleep(Duration::from_secs(2)).await;
        if unsafe { libc::getppid() } != parent {
            return;
        }
    }
}

/// Another ember-station runs the data directory. `run` then exits with HELD, which the desktop app takes for "this
/// machine's station is already running" (apps/desktop/src/station.ts).
#[derive(Debug)]
struct Held(PathBuf);

impl std::fmt::Display for Held {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "另一个 ember-station 正在运行这个数据目录（{}）；同一台机器上的一个数据目录只能运行一个 station", self.0.display())
    }
}

impl std::error::Error for Held {}

const HELD: i32 = 3;

/// Holds `path` locked for as long as the file lives; fails when another process holds it.
fn lock(path: &Path) -> Result<std::fs::File> {
    let file = std::fs::OpenOptions::new().create(true).truncate(false).write(true).open(path)?;
    // SAFETY: flock on a descriptor this function owns.
    if unsafe { libc::flock(std::os::fd::AsRawFd::as_raw_fd(&file), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        return Err(Held(path.parent().and_then(Path::parent).unwrap_or(path).to_path_buf()).into());
    }
    Ok(file)
}

/// Whether the station's config turns traces on (telemetry.traces in <data>/config.json).
fn traces_on(data: &Path) -> bool {
    std::fs::read(data.join("config.json")).ok().and_then(|b| serde_json::from_slice::<Value>(&b).ok()).is_some_and(|c| c["telemetry"]["traces"] == true)
}

/// The station's way into ember cloud, once it is in a workspace (enrolled: `ember station enroll`).
async fn mesh(data: PathBuf, socket: PathBuf, ready: watch::Receiver<bool>, secret: String, telemetry: Arc<Telemetry>) {
    let state = loop {
        match load_state(&data) {
            Ok(state) if load_key(&data).is_ok() => break state,
            _ => tokio::time::sleep(Duration::from_secs(2)).await,
        }
    };
    if let Err(error) = serve_mesh(data, state, socket, ready, secret, telemetry).await {
        warn!(%error, "mesh stopped");
    }
}

async fn serve_mesh(data: PathBuf, state: CloudState, socket: PathBuf, ready: watch::Receiver<bool>, secret: String, telemetry: Arc<Telemetry>) -> Result<()> {
    let key = load_key(&data)?;
    let relay: RelayUrl = state.relay_url.parse().context("relay url")?;
    // ember's relay, and iroh's public ones should it be down; found without ember cloud: on the LAN by mDNS, and
    // which relay it is on, published to the Mainline DHT (clients look both up: client/core/src/mesh.rs).
    let relays = iroh::RelayMap::from(relay);
    relays.extend(&iroh::defaults::prod::default_relay_map());
    let endpoint = Endpoint::builder(Minimal)
        .secret_key(key.clone())
        .alpns(vec![ALPN.to_vec()])
        .relay_mode(RelayMode::Custom(relays))
        .address_lookup(iroh_mdns_address_lookup::MdnsAddressLookup::builder())
        .address_lookup(iroh_mainline_address_lookup::DhtAddressLookup::builder().secret_key(key))
        .transport_config(transport())
        .bind()
        .await?;
    info!(station = %endpoint.id(), workspace = %state.workspace_name, "mesh listening");
    let traces = telemetry.enabled();
    let station = Arc::new(Station { data, state: Mutex::new(state), socket, ready, secret, removed: Mutex::new(false), telemetry: telemetry.clone() });
    // Online at ember cloud only once the relay can reach us: a device that saw "online" and connected before
    // our relay link was up had its first packets dropped and waited out QUIC's retransmits (~3 s).
    if tokio::time::timeout(std::time::Duration::from_secs(15), endpoint.online()).await.is_err() {
        warn!("no relay link after 15 s; going online at ember cloud anyway");
    }
    tokio::spawn(presence(station.clone(), endpoint.secret_key().clone()));
    if traces {
        tokio::spawn(telemetry.export(station.clone(), endpoint.secret_key().clone()));
    }
    while let Some(incoming) = endpoint.accept().await {
        let station = station.clone();
        tokio::spawn(async move {
            match incoming.await {
                Ok(conn) => {
                    if let Err(error) = serve(station, conn).await {
                        info!(%error, "connection ended");
                    }
                }
                Err(error) => warn!(%error, "incoming connection failed"),
            }
        });
    }
    Ok(())
}

/// Keeps the presence socket open, reconnecting with backoff.
async fn presence(station: Arc<Station>, key: SecretKey) {
    let mut backoff = Duration::from_secs(1);
    let mut ready = station.ready.clone();
    loop {
        // Online only while the station answers: its Node part up.
        let up = *ready.borrow();
        if !up {
            let _ = ready.wait_for(|up| *up).await.map(|_| ());
            backoff = Duration::from_secs(1);
        }
        let started = Instant::now();
        match connect(&station, &key).await {
            Ok(()) => info!("ember cloud closed the presence socket"),
            Err(error) => warn!(%error, "no presence socket to ember cloud"),
        }
        // A socket that held a while starts over quickly; failing again and again backs off to a minute.
        if started.elapsed() > Duration::from_secs(60) {
            backoff = Duration::from_secs(1);
        }
        tokio::time::sleep(backoff).await;
        backoff = (backoff * 2).min(Duration::from_secs(60));
    }
}

/// One presence socket, signed at connect like enrollment; returns when it ends.
async fn connect(station: &Station, key: &SecretKey) -> Result<()> {
    let (origin, id) = {
        let s = station.state.lock().unwrap();
        (s.origin.clone(), s.station.clone())
    };
    let ts = now();
    let signature = hex::encode(key.sign(format!("ember-station-connect-v1:{origin}:{id}:{ts}").as_bytes()).to_bytes());
    let mut request = format!("{}/v1/stations/connect", origin.replacen("http", "ws", 1)).into_client_request()?;
    let headers = request.headers_mut();
    headers.insert("x-ember-station", id.parse()?);
    headers.insert("x-ember-ts", ts.to_string().parse()?);
    headers.insert("x-ember-signature", signature.parse()?);
    headers.insert("x-ember-version", VERSION.parse()?);
    let (mut socket, _) = match tokio::time::timeout(Duration::from_secs(20), tokio_tungstenite::connect_async(request)).await.context("connect timed out")? {
        Ok(connected) => connected,
        Err(tungstenite::Error::Http(response)) if response.status().as_u16() == 404 => {
            removed(station);
            bail!("station removed");
        }
        Err(error) => return Err(error.into()),
    };
    *station.removed.lock().unwrap() = false;
    info!("online at ember cloud");
    let mut ping = tokio::time::interval(PING);
    ping.tick().await;
    let mut answered = true;
    let mut ready = station.ready.clone();
    loop {
        tokio::select! {
            // Its Node part went down: offline until it is back.
            _ = async { let _ = ready.wait_for(|up| !*up).await; } => {
                info!("station not answering; going offline at ember cloud");
                let _ = socket.close(None).await;
                return Ok(());
            }
            frame = socket.next() => match frame {
                Some(Ok(Message::Text(text))) if text.as_str() == "pong" => answered = true,
                Some(Ok(Message::Text(text))) => apply_state(station, text.as_str()),
                Some(Ok(Message::Close(frame))) => {
                    if frame.is_some_and(|f| u16::from(f.code) == CLOSE_REMOVED) {
                        removed(station);
                    }
                    return Ok(());
                }
                Some(Ok(_)) => {}
                Some(Err(error)) => return Err(error.into()),
                None => return Ok(()),
            },
            _ = ping.tick() => {
                // No pong since the last ping: the connection is gone even if the socket has not noticed.
                if !answered {
                    bail!("ember cloud stopped answering");
                }
                answered = false;
                socket.send(Message::Text("ping".into())).await?;
            }
        }
    }
}

fn removed(station: &Station) {
    warn!("this station was removed from its workspace; refusing connections");
    *station.removed.lock().unwrap() = true;
}

/// ember cloud says where the station is and what it is called (on connect and whenever that changes, with every
/// revocation it keeps), and what it takes back as it does.
fn apply_state(station: &Station, text: &str) {
    let Ok(body) = serde_json::from_str::<Value>(text) else { return };
    let mut guard = station.state.lock().unwrap();
    let s = &mut *guard;
    match body["type"].as_str() {
        Some("state") => {
            for (field, key) in [(&mut s.workspace, "workspace"), (&mut s.workspace_name, "workspace_name"), (&mut s.name, "name")] {
                if let Some(value) = body[key].as_str() {
                    *field = value.to_string();
                }
            }
            if body["grant_keys"].is_object() {
                s.grant_keys = body["grant_keys"].clone();
            }
            if let Ok(all) = serde_json::from_value::<Vec<Revocation>>(body["revocations"].clone()) {
                s.revocations = all;
            }
        }
        Some("revoke") => {
            let Ok(revocation) = serde_json::from_value::<Revocation>(body.clone()) else { return };
            s.revocations.retain(|r| !(r.kind == revocation.kind && r.id == revocation.id));
            s.revocations.push(revocation);
        }
        _ => return,
    }
    let _ = save_state(&station.data, s);
}

async fn serve(station: Arc<Station>, conn: Connection) -> Result<()> {
    if *station.removed.lock().unwrap() {
        conn.close(2u32.into(), b"station_removed");
        bail!("station removed");
    }
    let device = hex::encode(conn.remote_id().as_bytes());
    // The first stream carries the credential; nothing else is served before it checks out.
    let (mut send, mut recv) = conn.accept_bi().await?;
    let mut carry = Vec::new();
    let check = {
        let (station, device) = (station.clone(), device.clone());
        move |line: &Value| -> Result<Admitted> {
            let s = station.state.lock().unwrap();
            verify_member(line["credential"].as_str().unwrap_or_default(), &s.grant_keys, &s.workspace, &device, &s.revocations)
        }
    };
    let first = read_line(&mut recv, &mut carry).await?.ok_or_else(|| anyhow!("no credential"))?;
    let admitted = match check(&first) {
        Ok(v) => v,
        Err(error) => {
            write_line(&mut send, &json!({ "error": error.to_string() })).await.ok();
            send.finish().ok();
            tokio::time::sleep(Duration::from_millis(200)).await;
            conn.close(1u32.into(), b"credential_refused");
            return Err(error);
        }
    };
    let station_name = station.state.lock().unwrap().name.clone();
    write_line(&mut send, &json!({ "ok": true, "station": station_name, "expires_at": admitted.exp })).await?;
    info!(email = %admitted.viewer.email, device = %&device[..12], "client connected");
    let current = Arc::new(Mutex::new(admitted));

    // Renewals on the credential stream; the connection closes when the credential runs out or is revoked.
    let renew = {
        let (current, station, conn, check) = (current.clone(), station.clone(), conn.clone(), check.clone());
        async move {
            loop {
                tokio::select! {
                    line = read_line(&mut recv, &mut carry) => {
                        let Ok(Some(line)) = line else { break };
                        let reply = match check(&line) {
                            Ok(admitted) => { let exp = admitted.exp; *current.lock().unwrap() = admitted; json!({ "ok": true, "expires_at": exp }) }
                            Err(error) => json!({ "error": error.to_string() }),
                        };
                        if write_line(&mut send, &reply).await.is_err() { break }
                    }
                    _ = tokio::time::sleep(Duration::from_secs(5)) => {}
                }
                let (expired, revoked) = {
                    let admitted = current.lock().unwrap();
                    (admitted.exp <= now(), admitted.revoked(&station.state.lock().unwrap().revocations))
                };
                if expired || revoked {
                    conn.close(3u32.into(), if revoked { b"credential_revoked".as_slice() } else { b"credential_expired".as_slice() });
                    break;
                }
            }
        }
    };
    tokio::spawn(renew);

    loop {
        let (send, recv) = match conn.accept_bi().await {
            Ok(streams) => streams,
            Err(_) => return Ok(()),
        };
        let accepted = (SystemTime::now(), Instant::now());
        let via = conn.paths().iter().find(|p| p.is_selected()).map(|p| if p.is_relay() { "relay" } else { "direct" });
        let admitted = current.lock().unwrap().clone();
        if admitted.exp <= now() || admitted.revoked(&station.state.lock().unwrap().revocations) {
            conn.close(3u32.into(), b"credential_expired");
            return Ok(());
        }
        let viewer = admitted.viewer;
        let station = station.clone();
        tokio::spawn(async move {
            if let Err(error) = relay_request(&station, &viewer, (accepted, via), send, recv).await {
                info!(%error, "request failed");
            }
        });
    }
}

/// When a request stream was accepted, and how its connection runs (relay or direct).
type Accepted = ((SystemTime, Instant), Option<&'static str>);

/// What a request came to, for its span.
#[derive(Default)]
struct Outcome {
    status: u16,
    received: usize,
    sent: usize,
}

/// A request's span while it runs: recorded once it is answered, or, for an event stream, once it is open.
struct Traced<'a> {
    station: &'a Station,
    span: Option<telemetry::Span>,
    method: &'a str,
    path: &'a str,
    via: Option<&'static str>,
}

impl Traced<'_> {
    fn end(&mut self, outcome: &Outcome, stream: bool, error: Option<&anyhow::Error>) {
        let Some(span) = self.span.take() else { return };
        let mut attributes = vec![
            ("http.request.method", json!(self.method)),
            ("url.path", json!(route(self.path))),
            ("http.response.status_code", json!(outcome.status)),
            ("http.request.body.size", json!(outcome.received)),
        ];
        if stream {
            attributes.push(("ember.stream", json!(true)));
        } else {
            attributes.push(("http.response.body.size", json!(outcome.sent)));
        }
        if let Some(via) = self.via {
            attributes.push(("ember.path", json!(via)));
        }
        if let Some(error) = error {
            attributes.push(("error.type", json!(error.to_string())));
        }
        let failed = error.is_some() || outcome.status >= 500;
        self.station.telemetry.end(span, format!("{} {}", self.method, route(self.path)), &attributes, failed);
    }
}

/// One request stream: to the local admin API, with the verified viewer attached, and back. A span of the caller's
/// trace when it records one: from the stream's acceptance to its answer's last byte (an event stream's: to its head).
async fn relay_request(station: &Station, viewer: &Viewer, accepted: Accepted, mut send: SendStream, mut recv: RecvStream) -> Result<()> {
    let mut carry = Vec::new();
    let head = read_line(&mut recv, &mut carry).await?.ok_or_else(|| anyhow!("empty request"))?;
    let method = head["method"].as_str().unwrap_or("GET").to_uppercase();
    let path = head["path"].as_str().unwrap_or_default().to_string();
    let theirs = head["headers"]["traceparent"].as_str();
    let span = station.telemetry.start(theirs.and_then(Parent::parse), accepted.0);
    // The admin API's span goes under ours, or under the caller's when we record none.
    let traceparent = span.as_ref().map(|s| s.traceparent()).or(theirs.map(str::to_string));
    let mut traced = Traced { station, span, method: &method, path: &path, via: accepted.1 };
    let mut outcome = Outcome::default();
    let result = answer(station, viewer, &head, traceparent, carry, &mut send, &mut recv, &mut outcome, &mut traced).await;
    traced.end(&outcome, false, result.as_ref().err());
    result
}

#[allow(clippy::too_many_arguments)]
async fn answer(
    station: &Station,
    viewer: &Viewer,
    head: &Value,
    traceparent: Option<String>,
    carry: Vec<u8>,
    send: &mut SendStream,
    recv: &mut RecvStream,
    outcome: &mut Outcome,
    traced: &mut Traced<'_>,
) -> Result<()> {
    let (method, path) = (traced.method, traced.path);
    if !path.starts_with("/admin/api/") || path.contains("..") {
        outcome.status = 404;
        write_line(send, &json!({ "status": 404, "headers": { "content-type": "application/json" } })).await?;
        send.write_all(br#"{"error":"only the admin API is reachable over the mesh"}"#).await?;
        send.finish()?;
        return Ok(());
    }
    let mut body = carry;
    let mut buf = [0u8; 16 * 1024];
    while let Some(n) = recv.read(&mut buf).await? {
        body.extend_from_slice(&buf[..n]);
        if body.len() > MAX_BODY {
            bail!("request body too large");
        }
    }
    outcome.received = body.len();
    let mut request = hyper::Request::builder()
        .method(method)
        .uri(path)
        .header("host", "ember")
        .header("x-ember-mesh", &station.secret)
        .header("x-ember-viewer", B64.encode(serde_json::to_vec(viewer)?));
    // The caller's headers go on (a preview's page needs its cookies and what it accepts), but not those of the hop,
    // nor any of ember's own: who is asking is only what this process says.
    for (name, value) in head["headers"].as_object().into_iter().flatten() {
        let lower = name.to_ascii_lowercase();
        if HOP.contains(&lower.as_str()) || lower.starts_with("x-ember-") || lower == "traceparent" || lower == "tracestate" {
            continue;
        }
        if let Some(value) = value.as_str() {
            request = request.header(name.as_str(), value);
        }
    }
    if let Some(traceparent) = traceparent {
        request = request.header("traceparent", traceparent);
    }
    let request = request.body(Full::new(Bytes::from(body)))?;
    let unreachable = |error: String| json!({ "error": format!("station unreachable: {error}") });
    let up = *station.ready.borrow();
    let response = if !up {
        Err(anyhow!("not started"))
    } else {
        local::request(&station.socket, request).await
    };
    let response = match response {
        Ok(r) => r,
        Err(error) => {
            outcome.status = 502;
            write_line(send, &json!({ "status": 502, "headers": { "content-type": "application/json" } })).await?;
            send.write_all(unreachable(error.to_string()).to_string().as_bytes()).await?;
            send.finish()?;
            return Ok(());
        }
    };
    outcome.status = response.status().as_u16();
    let content_type = response.headers().get("content-type").and_then(|v| v.to_str().ok()).unwrap_or("application/octet-stream").to_string();
    // Its headers go back too (a preview's redirect, cookies, caching), those of the hop aside; a name said twice is
    // one line, its values joined.
    let mut headers = serde_json::Map::new();
    for (name, value) in response.headers() {
        let (name, Ok(value)) = (name.as_str(), value.to_str()) else { continue };
        if HOP.contains(&name) || name == "content-length" {
            continue;
        }
        match headers.get_mut(name) {
            Some(Value::String(was)) => { was.push_str(", "); was.push_str(value); }
            _ => { headers.insert(name.to_string(), json!(value)); }
        }
    }
    headers.insert("content-type".into(), json!(content_type));
    write_line(send, &json!({ "status": response.status().as_u16(), "headers": headers })).await?;
    // An event stream may stay open for hours: its span is the opening.
    if content_type.starts_with("text/event-stream") {
        traced.end(outcome, true, None);
    }
    let mut body = response.into_body();
    while let Some(frame) = body.frame().await {
        if let Ok(chunk) = frame?.into_data() {
            send.write_all(&chunk).await?;
            outcome.sent += chunk.len();
        }
    }
    send.finish()?;
    Ok(())
}

fn usage() -> ! {
    eprintln!("usage:\n  ember-station run --app DIR [--node PATH] [--port N] [--data DIR] [--with-parent]\n  ember-station enroll <ember-cloud-origin> <token> [--data DIR]\n  ember-station id [--data DIR]\n\nrun: --app holds src/main.ts; --port the admin page's (default 4760, a free one when it is taken); --with-parent: end when the parent does.");
    std::process::exit(2);
}

#[tokio::main]
async fn main() -> Result<()> {
    // The DHT and mDNS say a lot that is not the station's trouble: a network where the DHT cannot be reached (its
    // bootstrap fails every second there) still finds stations through the relay and the LAN.
    let filter = "info,iroh=warn,swarm_discovery=warn,n0_mainline=off,iroh_mainline_address_lookup=error";
    tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| filter.into())).init();
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let mut take = |flag: &str| -> Option<String> {
        let i = args.iter().position(|a| a == flag)?;
        let value = args.get(i + 1).cloned();
        args.drain(i..(i + 2).min(args.len()));
        value
    };
    let data = PathBuf::from(take("--data").unwrap_or_else(|| format!("{}/.ember", std::env::var("HOME").unwrap_or_default())));
    let app = take("--app");
    let node = take("--node").unwrap_or_else(|| "node".into());
    let port = take("--port");
    let with_parent = args.iter().position(|a| a == "--with-parent").map(|i| args.remove(i)).is_some();
    match args.first().map(String::as_str) {
        Some("enroll") if args.len() == 3 => enroll(&data, args[1].trim_end_matches('/'), &args[2]).await,
        Some("run") => {
            let Some(app) = app else { usage() };
            let named = port.is_some();
            let port = port.map(|p| p.parse::<u16>()).transpose().context("--port")?.unwrap_or(4760);
            let ran = run(Run { data, app: PathBuf::from(app), node: PathBuf::from(node), port, named, with_parent }).await;
            if let Some(held) = ran.as_ref().err().and_then(|e| e.downcast_ref::<Held>()) {
                eprintln!("{held}");
                std::process::exit(HELD);
            }
            ran
        }
        Some("id") => {
            println!("{}", hex::encode(load_key(&data)?.public().as_bytes()));
            Ok(())
        }
        _ => usage(),
    }
}

/// Clients reach the station through a relay, where a round trip is hundreds of milliseconds;
/// QUIC's default first window (~14 KB) would spread a chat's first page over several of them.
/// Starting at 256 KB answers what a screen needs in one; the client core does the same.
fn transport() -> QuicTransportConfig {
    let mut cubic = noq_proto::congestion::CubicConfig::default();
    cubic.initial_window(256 * 1024);
    QuicTransportConfig::builder().congestion_controller_factory(Arc::new(cubic)).build()
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};

    const WS: &str = "01M3DB2N6P5SY7PJ7RG1F62TRX";
    const DEVICE: &str = "aa";

    fn key() -> SigningKey {
        SigningKey::from_bytes(&[7u8; 32])
    }

    /// The keys a station pins at enrollment, with this one's public half.
    fn keys() -> Value {
        json!({ "keys": [{ "kid": "k", "x": B64.encode(key().verifying_key().as_bytes()) }] })
    }

    /// A credential as ember cloud signs one (cloud/src/grants.ts), with `claims` over the usual ones.
    fn credential(typ: &str, claims: Value) -> String {
        let mut body = json!({ "iss": "ember-cloud", "sub": "bob", "email": "bob@x", "name": "Bob", "ws": WS, "role": "member", "device": DEVICE, "sid": "s1", "iat": now() - 10, "exp": now() + 3600 });
        for (k, v) in claims.as_object().unwrap() {
            body[k] = v.clone();
        }
        let head = B64.encode(json!({ "alg": "EdDSA", "typ": typ, "kid": "k" }).to_string());
        let body = B64.encode(body.to_string());
        let signature = key().sign(format!("{head}.{body}").as_bytes());
        format!("{head}.{body}.{}", B64.encode(signature.to_bytes()))
    }

    fn check(credential: &str, revocations: &[Revocation]) -> Result<Admitted> {
        verify_member(credential, &keys(), WS, DEVICE, revocations)
    }

    #[test]
    fn a_members_credential_lets_its_device_in_offline() {
        let admitted = check(&credential("ember-member+jwt", json!({})), &[]).unwrap();
        assert_eq!((admitted.viewer.sub.as_str(), admitted.viewer.role.as_str(), admitted.sid.as_str()), ("bob", "member", "s1"));
    }

    #[test]
    fn it_is_refused_for_another_workspace_device_or_kind_expired_or_tampered() {
        assert!(check(&credential("ember-member+jwt", json!({ "ws": "OTHER" })), &[]).is_err());
        assert!(check(&credential("ember-member+jwt", json!({ "device": "bb" })), &[]).is_err());
        assert!(check(&credential("ember-member+jwt", json!({ "exp": now() - 1 })), &[]).is_err());
        assert!(check(&credential("ember-grant+jwt", json!({})), &[]).is_err());
        let good = credential("ember-member+jwt", json!({}));
        let mut parts: Vec<&str> = good.split('.').collect();
        let forged = B64.encode(json!({ "iss": "ember-cloud", "sub": "bob", "ws": WS, "role": "owner", "device": DEVICE, "sid": "s1", "iat": now(), "exp": now() + 3600 }).to_string());
        parts[1] = &forged;
        assert!(check(&parts.join("."), &[]).is_err(), "a changed body no longer matches its signature");
    }

    #[test]
    fn what_ember_cloud_revoked_is_refused_and_what_came_after_is_not() {
        let issued = now() - 10;
        let old = credential("ember-member+jwt", json!({ "iat": issued }));
        let revoked_account = [Revocation { kind: "sub".into(), id: "bob".into(), at: issued }];
        let revoked_session = [Revocation { kind: "sid".into(), id: "s1".into(), at: issued + 5 }];
        let someone_else = [Revocation { kind: "sub".into(), id: "carol".into(), at: now() }];
        assert!(check(&old, &revoked_account).is_err());
        assert!(check(&old, &revoked_session).is_err());
        assert!(check(&old, &someone_else).is_ok());
        // A credential asked for after the revocation (a new role, a new sign-in) is taken.
        let new = credential("ember-member+jwt", json!({ "iat": issued + 1 }));
        assert!(check(&new, &revoked_account).is_ok());
    }
}
