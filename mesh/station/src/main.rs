//! stillfail-station: a still.fail station, as launchd (or the desktop app) runs it (ember-station before the rename,
//! still a link to this in a release: docs/rename-still-fail.md).
//!
//! `run` runs the station: its app (stillfail-app) in this process; a loopback port that sends links to the page it once
//! had on to still.fail cloud (local.rs); and, once the station is in a workspace, its way into still.fail cloud. It
//! holds a presence socket to the cloud (connected is online) while the app is up — which also brings what the cloud
//! revokes — accepts iroh connections from clients that present a mstill.fail's credential signed by the cloud (checked
//! offline: the cloud need not be reachable), and hands each stream's request to the app's admin API with the verified
//! identity. `enroll` redeems a one-time token from a workspace admin, proving this station holds its iroh key.
//! `status` says where the station is.
//!
//! A station works only in a workspace. Removed from it (the cloud closes the presence socket with 4004, or refuses it
//! with 404), it marks <data>/mesh/cloud.json `removed_at` and keeps the file (the desktop app then does not join it
//! again by itself); the app sees the mark and stops its work (stillfail_app::server). The cloud is asked again now and
//! then; should it take the station back, the mark goes. `enroll` writes the file anew, without it.
//!
//! Wire format on ALPN `ember/admin/1` (clients from before the rename ask for it; `stillfail/admin/1` is the same): the
//! first bidirectional stream carries
//! credentials (`{"credential": …}`, one JSON line each, answered with one JSON line; a later line
//! renews). Every other stream is one request: a JSON head line
//! `{"method","path","headers"}`, then the body until the stream finishes;
//! answered by a JSON head line `{"status","headers"}` and the response body.
//! A request's `traceparent` header is passed on to the admin API (see telemetry.rs).

mod errors;
mod feedback;
mod keep;
mod peer;
mod local;
mod notify;
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

const ALPN: &[u8] = b"stillfail/admin/1";
/// The ALPN clients from before the rename ask for: the same protocol.
const FORMER_ALPN: &[u8] = b"ember/admin/1";
/// Headers of one hop, not of what is relayed.
const HOP: [&str; 9] = ["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "te", "trailer", "host", "content-length"];
const MAX_HEAD: usize = 16 * 1024;
// Files sent to a session go through here; the station caps them at 50 MB.
const MAX_BODY: usize = 64 * 1024 * 1024;
/// This station's version, as still.fail cloud and `stillfail update` are told it: its release's (`0.1.<n>`, the BUILD beside
/// the binary's mesh/target/release: stillfail_app::updates), else the crate's. Read once: an update puts the next
/// release's in its place before this one hands over.
fn version() -> &'static str {
    static VERSION: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    VERSION.get_or_init(|| {
        let app = std::env::current_exe().ok().and_then(|exe| exe.ancestors().nth(4).map(Path::to_path_buf));
        app.and_then(|app| stillfail_app::updates::station_version(&app)).unwrap_or_else(|| env!("CARGO_PKG_VERSION").to_string())
    })
}
/// still.fail cloud expects a "ping" this often and drops a station silent for three of them.
const PING: Duration = Duration::from_secs(30);
/// How still.fail cloud closes the socket of a station removed from its workspace.
const CLOSE_REMOVED: u16 = 4004;

#[derive(Serialize, Deserialize, Clone)]
struct CloudState {
    origin: String,
    station: String,
    workspace: String,
    workspace_name: String,
    name: String,
    relay_url: String,
    /// Every relay, still.fail's (`relay_url`) first: the station homes on the nearest (`relays`). Missing from a cloud
    /// or a state file from before there were several.
    #[serde(default)]
    relay_urls: Vec<String>,
    grant_keys: Value,
    /// Authenticated workspace roster; old control planes grant no peer access.
    #[serde(default)]
    peers: Vec<Value>,
    /// What the cloud took back (a member removed, a role changed, a session signed out): credentials of that
    /// account (`sub`) or session (`sid`) issued up to `at` are refused. Kept, so it holds with the cloud away.
    #[serde(default)]
    revocations: Vec<Revocation>,
    /// When the cloud said the station was removed from its workspace (unix seconds), and how (4004: the presence
    /// socket closed so; 404: refused at connect). Absent while it is in the workspace, and in files of before.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    removed_at: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    removed_code: Option<u16>,
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
    anyhow!("still.fail cloud answered {status}: {body}")
}

async fn enroll(data: &Path, origin: &str, token: &str) -> Result<()> {
    let key = load_key(data)?;
    let station = hex::encode(key.public().as_bytes());
    // The signed words keep the old name: the cloud checks them as they are (so do clouds from before the rename).
    let message = format!("ember-station-enroll-v1:{origin}:{token}:{station}");
    let signature = hex::encode(key.sign(message.as_bytes()).to_bytes());
    let response = http()
        .post(format!("{origin}/v1/stations/enroll"))
        .json(&json!({ "token": token, "station": station, "signature": signature, "version": version() }))
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
        relay_urls: strings(&body["relay_urls"]),
        grant_keys: body["grant_keys"].clone(),
        peers: Vec::new(),
        revocations: Vec::new(),
        removed_at: None,
        removed_code: None,
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
    /// Whether the cloud took it back since it was issued.
    fn revoked(&self, revocations: &[Revocation]) -> bool {
        revocations.iter().any(|r| self.iat <= r.at && ((r.kind == "sub" && r.id == self.viewer.sub) || (r.kind == "sid" && r.id == self.sid)))
    }
}

/// What a mstill.fail's credential says it is, and who issued it: the cloud's names for them, and those of before the
/// rename (credentials already out, clouds that still issue them).
const MEMBER_TYPES: [&str; 2] = ["stillfail-member+jwt", "ember-member+jwt"];
const ISSUERS: [&str; 2] = ["stillfail-cloud", "ember-cloud"];

/// Verifies a mstill.fail's credential (still.fail cloud's, for this station's workspace, 30 days) for the connecting device,
/// offline: with the key pinned at enrollment, and what was revoked since.
fn verify_member(credential: &str, keys: &Value, workspace: &str, device: &str, revocations: &[Revocation]) -> Result<Admitted> {
    let mut parts = credential.split('.');
    let (Some(head), Some(body), Some(sig), None) = (parts.next(), parts.next(), parts.next(), parts.next()) else { bail!("malformed credential") };
    let header: Value = serde_json::from_slice(&B64.decode(head)?)?;
    if header["alg"] != "EdDSA" || !MEMBER_TYPES.contains(&header["typ"].as_str().unwrap_or_default()) {
        bail!("not a mstill.fail's credential");
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
    if !ISSUERS.contains(&text("iss").as_str()) {
        bail!("credential not issued by still.fail cloud");
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
    peers_current: std::sync::atomic::AtomicBool,
    /// Where its requests go, and whether that answers now.
    backend: local::Backend,
    ready: watch::Receiver<bool>,
    telemetry: Arc<Telemetry>,
}

impl Station {
    /// Whether the cloud removed it from its workspace (and has not taken it back).
    fn removed(&self) -> bool {
        self.state.lock().unwrap().removed_at.is_some()
    }

    /// Takes up what cloud.json says now: an enrollment made while this runs (`stillfail station enroll`) wrote it anew.
    /// What this process learns it writes there at once (`apply_state`, `removed`), so the file is never behind.
    fn reload(&self) {
        if let Ok(state) = load_state(&self.data) {
            *self.state.lock().unwrap() = state;
        }
    }
}

/// What `run` is given: where the data is, the app directory (the release: dist/admin keeps what it built for the
/// station, posthog.json), and the loopback port.
struct Run {
    data: PathBuf,
    app: PathBuf,
    port: u16,
    named: bool,
    /// Ends when the process that started it does (the desktop app).
    with_parent: bool,
    /// What the previous binary handed over (--handoff <file>), when it exec'd this one.
    handoff: Option<PathBuf>,
}

/// What a station hands over to its next binary (stillfail_app::handoff), written to <data>/run/handoff.json.
#[derive(Serialize, Deserialize)]
struct Handoff {
    version: u32,
    /// The loopback port's listening socket.
    admin: Option<i32>,
    app: stillfail_app::handoff::HandedApp,
}

/// How long a drain waits for running turns to end, and how long a drained station waits to be stopped before it
/// takes turns again (whoever asked went away).
const DRAIN_LIMIT: Duration = Duration::from_secs(600);
const DRAINED_LIMIT: Duration = Duration::from_secs(300);

/// Says who runs this data directory and what it can do, for `stillfail update` (cloud/src/install.ts): SIGUSR2 hands over
/// to the binary now at this one's path (handoff), SIGUSR1 holds turns and says when none runs (drain).
fn write_station_file(run: &Path, started_at: u64) {
    // channel: SIGHUP takes the update channel asked for in run/channel-ask (`stillfail-station channel`).
    let text = json!({ "pid": std::process::id(), "startedAt": started_at, "version": version(), "handoff": stillfail_app::handoff::VERSION, "drain": 1, "channel": 1 }).to_string();
    if let Err(error) = std::fs::write(run.join("station.json"), format!("{text}\n")) {
        warn!(%error, "station.json not written");
    }
}

async fn run(options: Run) -> Result<()> {
    let data = options.data.clone();
    std::fs::create_dir_all(data.join("run"))?;
    // One station per data directory: a second would take the first one's port and runtimes away.
    let _lock = lock(&data.join("run").join("station.lock"))?;
    // Handed over: the file is read once (it names descriptors only this process holds).
    let mut handoff: Option<Handoff> = match &options.handoff {
        Some(path) => {
            let read = std::fs::read(path).map_err(anyhow::Error::from).and_then(|b| Ok(serde_json::from_slice::<Handoff>(&b)?));
            let _ = std::fs::remove_file(path);
            match read {
                Ok(handoff) if handoff.version == stillfail_app::handoff::VERSION => {
                    info!(sessions = handoff.app.hub.sessions.len(), "taking over from the previous binary");
                    Some(handoff)
                }
                Ok(handoff) => {
                    warn!(version = handoff.version, "handoff of another version; starting afresh");
                    None
                }
                Err(error) => {
                    warn!(%error, "handoff not read; starting afresh");
                    None
                }
            }
        }
        None => None,
    };
    let _ = std::fs::remove_file(data.join("run").join("drained"));
    let telemetry = Telemetry::new(traces_on(&data));
    let (ready_tx, ready) = watch::channel(false);
    // Held for as long as this runs: a dropped sender reads as "not answering" to whoever waits on `ready`.
    let ready_tx = Arc::new(ready_tx);
    let backend = local::Backend::default();
    let ui = options.app.join("dist").join("admin");
    let config = stillfail_app::former::var("CONFIG").map(PathBuf::from).unwrap_or_else(|| data.join("config.json"));
    // Its errors to still.fail's error tracking, while the config says so.
    let (config_path, state_data) = (config.clone(), data.clone());
    let _ = errors::REPORTS.set(stillfail_app::telemetry::ErrorReports::new(stillfail_app::telemetry::ErrorReportsOptions {
        key: stillfail_app::telemetry::built_key(&ui),
        enabled: Arc::new(move || {
            std::fs::read(&config_path).ok().and_then(|b| serde_json::from_slice::<Value>(&b).ok()).is_some_and(|c| c["telemetry"]["errors"] == true)
        }),
        station: Arc::new(move || load_state(&state_data).ok().map(|s| s.station)),
        home: None,
    }));
    {
        let (cell, data, ready_tx) = (backend.0.clone(), data.clone(), ready_tx.clone());
        let handed = handoff.as_mut().map(|h| std::mem::take(&mut h.app));
        tokio::spawn(async move {
            match stillfail_app::server::App::start(stillfail_app::server::AppOptions { data, config, ui, handoff: handed }).await {
                Ok(app) => {
                    let _ = cell.set(app);
                    ready_tx.send_replace(true);
                }
                Err(error) => {
                    tracing::error!(error = %format!("{error:#}"), "the station did not start");
                    std::process::exit(1);
                }
            }
        });
    }
    let handed_admin = handoff.as_ref().and_then(|h| h.admin).and_then(|fd| {
        stillfail_app::handoff::claim_listener(fd).map_err(|error| warn!(%error, "the loopback port's socket handed over could not be taken up")).ok()
    });
    let listener = match handed_admin {
        Some(listener) => listener,
        None => local::bind(&data, options.port, options.named).await?,
    };
    let door = local::serve(listener, data.clone(), ready.clone());
    tokio::spawn(mesh(data.clone(), backend.clone(), ready, telemetry));
    // Before station.json says SIGHUP is taken: until a handler is set, it would end the process.
    let mut hup = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::hangup())?;
    write_station_file(&data.join("run"), now() * 1000 + (SystemTime::now().duration_since(UNIX_EPOCH).unwrap().subsec_millis() as u64));
    // SIGTERM (launchd, the desktop app) or ^C: the runtimes end first. So does, with --with-parent, the parent's end
    // (the desktop app's, killed): orphaned, this would hold the machine's station with no app to stop it. Run
    // otherwise (launchd, nohup), the parent may well end first. SIGUSR2 hands over to the next binary; SIGUSR1 drains.
    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    let mut usr1 = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::user_defined1())?;
    let mut usr2 = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::user_defined2())?;
    let draining = Arc::new(std::sync::atomic::AtomicBool::new(false));
    loop {
        tokio::select! {
            _ = term.recv() => break,
            _ = tokio::signal::ctrl_c() => break,
            _ = orphaned(), if options.with_parent => {
                info!("parent ended");
                break;
            }
            _ = usr1.recv() => {
                if let Some(app) = backend.0.get().cloned() {
                    if !draining.swap(true, std::sync::atomic::Ordering::SeqCst) {
                        tokio::spawn(drain(app, data.join("run"), draining.clone()));
                    }
                }
            }
            // `stillfail update --beta`/`--stable`: the channel asked for, kept by this process (it holds the config).
            _ = hup.recv() => match backend.0.get().cloned() {
                Some(app) => answer_channel_ask(&data.join("run"), |channel| app.set_update_channel(channel)),
                None => warn!("asked for an update channel before the station is up; not now"),
            },
            _ = usr2.recv() => {
                let Some(app) = backend.0.get().cloned() else {
                    warn!("asked to hand over before the station is up; not now");
                    continue;
                };
                if let Err(error) = hand_over(&options, &door, &app, &ready_tx).await {
                    warn!(error = %format!("{error:#}"), "not handed over; going on as before");
                    let _ = std::fs::write(data.join("run").join("handoff-failed"), format!("{error:#}\n"));
                }
            }
        }
    }
    info!("stopping");
    ready_tx.send_replace(false);
    if let Some(app) = backend.0.get() {
        app.shutdown().await;
    }
    if let Some(reports) = errors::REPORTS.get() {
        reports.shutdown().await;
    }
    Ok(())
}

/// Holds turns until none runs (or DRAIN_LIMIT passes), then says so in <data>/run/drained, for whoever restarts the
/// station to stop it now. Nobody does within DRAINED_LIMIT: turns go on again.
async fn drain(app: Arc<stillfail_app::server::App>, run: PathBuf, draining: Arc<std::sync::atomic::AtomicBool>) {
    info!("draining: no new turns; waiting for running ones to end");
    app.hold();
    let until = Instant::now() + DRAIN_LIMIT;
    while app.any_running() && Instant::now() < until {
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
    let said = if app.any_running() { "timeout" } else { "idle" };
    info!(said, "drained");
    let _ = std::fs::write(run.join("drained"), format!("{said}\n"));
    tokio::time::sleep(DRAINED_LIMIT).await;
    warn!("drained but not stopped; taking turns again");
    let _ = std::fs::remove_file(run.join("drained"));
    app.release();
    draining.store(false, std::sync::atomic::Ordering::SeqCst);
}

/// Hands over to the binary now at this one's path (`stillfail update` put the new release there): asks it whether it
/// reads this binary's handoff, stops taking anything new, gives up what runs (stillfail_app::handoff) and execs it in this
/// process. Fails, and goes on as before, as long as nothing was given up; once the runtimes were, it cannot fail back:
/// a failed exec exits, and the next start resumes what was cut off the usual way.
async fn hand_over(options: &Run, door: &stillfail_app::handoff::Door, app: &stillfail_app::server::App, ready_tx: &watch::Sender<bool>) -> Result<()> {
    use std::os::unix::process::CommandExt;
    let exe = std::env::current_dir()?.join(std::env::args_os().next().ok_or_else(|| anyhow!("no argv[0]"))?);
    let answer = tokio::process::Command::new(&exe).arg("handoff-version").output().await.with_context(|| format!("{} did not run", exe.display()))?;
    let theirs = String::from_utf8_lossy(&answer.stdout).trim().parse::<u32>().ok();
    if !answer.status.success() || theirs != Some(stillfail_app::handoff::VERSION) {
        bail!("{} does not take this binary's handoff (it reads {:?}, this writes {})", exe.display(), theirs, stillfail_app::handoff::VERSION);
    }
    info!(to = %exe.display(), "handing over to the next binary");
    // The loopback port's requests under way finish; new ones wait in the backlog for the next binary.
    door.pause(Duration::from_secs(10)).await?;
    let handed = match app.hand_off().await {
        Ok(handed) => handed,
        Err(error) => {
            door.resume();
            return Err(error);
        }
    };
    ready_tx.send_replace(false);
    let admin = door.keep().map_err(|error| warn!(%error, "the loopback port's socket is not handed over")).ok();
    let path = options.data.join("run").join("handoff.json");
    let written = serde_json::to_vec(&Handoff { version: stillfail_app::handoff::VERSION, admin, app: handed }).map_err(anyhow::Error::from).and_then(|bytes| write_private(&path, &bytes));
    if let Err(error) = written {
        tracing::error!(%error, "handoff not written; exiting (the next start resumes what was cut off)");
        std::process::exit(1);
    }
    // The same arguments, less an earlier --handoff.
    let mut args: Vec<std::ffi::OsString> = std::env::args_os().skip(1).collect();
    if let Some(i) = args.iter().position(|a| a == "--handoff") {
        args.drain(i..(i + 2).min(args.len()));
    }
    args.extend(["--handoff".into(), path.into_os_string()]);
    let error = std::process::Command::new(&exe).args(&args).exec();
    tracing::error!(%error, "exec of the next binary failed; exiting (the next start resumes what was cut off)");
    std::process::exit(1);
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

/// Another station runs the data directory. `run` then exits with HELD, which the desktop app takes for "this
/// machine's station is already running" (apps/desktop/src/station.ts).
#[derive(Debug)]
struct Held(PathBuf);

impl std::fmt::Display for Held {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "另一个 still.fail station 正在运行这个数据目录（{}）；同一台机器上的一个数据目录只能运行一个 station", self.0.display())
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

/// Where `stillfail-station channel` asks the running station for an update channel, and where it answers.
const CHANNEL_ASK: &str = "channel-ask";
const CHANNEL_ANSWER: &str = "channel-answer";

/// Writes `text` to `path` whole (a reader never sees half of it).
fn write_whole(path: &Path, text: &str) -> Result<()> {
    let tmp = path.with_extension(format!("tmp-{}", std::process::id()));
    std::fs::write(&tmp, text)?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

/// The running station's side: takes the channel asked for in <run>/channel-ask (if any), sets it, and answers in
/// <run>/channel-answer (`ok <channel>`, or `error <why>`).
fn answer_channel_ask(run: &Path, set: impl FnOnce(stillfail_app::updates::Channel) -> Result<()>) {
    let ask = run.join(CHANNEL_ASK);
    let Ok(asked) = std::fs::read_to_string(&ask) else { return };
    let _ = std::fs::remove_file(&ask);
    let answer = match stillfail_app::updates::Channel::of(&asked) {
        Some(channel) => match set(channel) {
            Ok(()) => format!("ok {}", channel.id()),
            Err(error) => format!("error {error:#}"),
        },
        None => format!("error 不认识的渠道 {}", asked.trim()),
    };
    if let Err(error) = write_whole(&run.join(CHANNEL_ANSWER), &format!("{answer}\n")) {
        warn!(%error, "the update channel's answer not written");
    }
}

/// Whether `pid` is a station (its command says so), as the installer checks it: a pid left in station.json may be
/// another process's by now.
fn is_station(pid: i32) -> bool {
    std::process::Command::new("ps").args(["-p", &pid.to_string(), "-o", "command="]).output()
        .is_ok_and(|o| { let c = String::from_utf8_lossy(&o.stdout); c.contains("stillfail-station") || c.contains("ember-station") })
}

/// Puts the station of `data` on `channel` (`stillfail update --beta`/`--stable`). A station running there holds the
/// config (an edit of its own would write over one made beside it): it is asked to (SIGHUP, the channel in
/// run/channel-ask) and its answer waited for, up to `wait`. With none running, the config is written here, the
/// station's lock held meanwhile; so it is too beside a running station from before it took the ask (station.json
/// says `channel`), which the update that follows replaces at once.
fn set_channel(data: &Path, config: &Path, channel: stillfail_app::updates::Channel, wait: Duration, is_station: impl Fn(i32) -> bool) -> Result<()> {
    use stillfail_app::updates::set_channel_in;
    let run = data.join("run");
    std::fs::create_dir_all(&run)?;
    match lock(&run.join("station.lock")) {
        Ok(_held) => return set_channel_in(config, data, channel),
        Err(error) if error.downcast_ref::<Held>().is_none() => return Err(error),
        Err(_) => {}
    }
    let said: Value = std::fs::read(run.join("station.json")).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or(Value::Null);
    let pid = said["pid"].as_i64().and_then(|p| i32::try_from(p).ok()).filter(|p| *p > 0);
    let Some(pid) = pid.filter(|p| said["channel"] == 1 && is_station(*p)) else {
        return set_channel_in(config, data, channel);
    };
    let answer = run.join(CHANNEL_ANSWER);
    let _ = std::fs::remove_file(&answer);
    write_whole(&run.join(CHANNEL_ASK), channel.id())?;
    // SAFETY: a signal to the process the station's own file names, checked to be a station.
    if unsafe { libc::kill(pid, libc::SIGHUP) } != 0 {
        let _ = std::fs::remove_file(run.join(CHANNEL_ASK));
        bail!("没能通知运行中的 station（pid {pid}）：{}", std::io::Error::last_os_error());
    }
    let until = Instant::now() + wait;
    while Instant::now() < until {
        if let Ok(text) = std::fs::read_to_string(&answer) {
            let _ = std::fs::remove_file(&answer);
            let text = text.trim();
            return match text.strip_prefix("ok") {
                Some(_) => Ok(()),
                None => Err(anyhow!("{}", text.strip_prefix("error ").unwrap_or(text))),
            };
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    let _ = std::fs::remove_file(run.join(CHANNEL_ASK));
    bail!("运行中的 station 没有回应（它可能还在启动），过一会儿再试")
}

/// Whether the station's config turns traces on (telemetry.traces in <data>/config.json).
fn traces_on(data: &Path) -> bool {
    std::fs::read(data.join("config.json")).ok().and_then(|b| serde_json::from_slice::<Value>(&b).ok()).is_some_and(|c| c["telemetry"]["traces"] == true)
}

/// The station's way into still.fail cloud, once it is in a workspace (enrolled: `stillfail station enroll`).
async fn mesh(data: PathBuf, backend: local::Backend, ready: watch::Receiver<bool>, telemetry: Arc<Telemetry>) {
    write_presence(&data, false, Some("not in a workspace"));
    let state = loop {
        match load_state(&data) {
            Ok(state) if load_key(&data).is_ok() => break state,
            _ => tokio::time::sleep(Duration::from_secs(2)).await,
        }
    };
    if let Err(error) = serve_mesh(data, state, backend, ready, telemetry).await {
        warn!(%error, "mesh stopped");
    }
}

/// The mDNS service this station announces itself under: ours (named before the rename, and kept: clients look for it
/// by this name), not iroh's shared `irohv1`, where any iroh
/// app's endpoints answer too and a query's answers stop after a few (client/core/src/mesh.rs asks for it).
const MDNS_SERVICE: &str = "ember";

async fn serve_mesh(data: PathBuf, state: CloudState, backend: local::Backend, ready: watch::Receiver<bool>, telemetry: Arc<Telemetry>) -> Result<()> {
    let key = load_key(&data)?;
    // still.fail's relays, homing on the nearest (iroh's public ones only while none answers: `keep_relays`); found
    // without the cloud: on the LAN by mDNS, and which relay it is on, published to the Mainline DHT (clients look both
    // up: client/core/src/mesh.rs).
    let relays = iroh::RelayMap::from_iter(relays(&state));
    if relays.is_empty() {
        bail!("no relay url");
    }
    let endpoint = Endpoint::builder(Minimal)
        .secret_key(key.clone())
        .alpns(vec![ALPN.to_vec(), FORMER_ALPN.to_vec(), peer::ALPN.to_vec()])
        .relay_mode(RelayMode::Custom(relays))
        .address_lookup(iroh_mdns_address_lookup::MdnsAddressLookup::builder().service_name(MDNS_SERVICE))
        .address_lookup(iroh_mainline_address_lookup::DhtAddressLookup::builder().secret_key(key))
        .transport_config(transport())
        .bind()
        .await?;
    info!(station = %endpoint.id(), workspace = %state.workspace_name, "mesh listening");
    let traces = telemetry.enabled();
    let station = Arc::new(Station { data, state: Mutex::new(state), peers_current: std::sync::atomic::AtomicBool::new(false), backend, ready, telemetry: telemetry.clone() });
    // Online at still.fail cloud only once the relay can reach us: a device that saw "online" and connected before
    // our relay link was up had its first packets dropped and waited out QUIC's retransmits (~3 s).
    if tokio::time::timeout(std::time::Duration::from_secs(15), endpoint.online()).await.is_err() {
        warn!("no relay link after 15 s; going online at still.fail cloud anyway");
    }
    tokio::spawn(presence(station.clone(), endpoint.secret_key().clone()));
    tokio::spawn(keep_relays(endpoint.clone(), station.clone()));
    // What the chats' people hear about, pushed through still.fail cloud.
    tokio::spawn(notify::forward(station.clone(), endpoint.secret_key().clone()));
    // Bug reports its agents send the still.fail team (stillfail_app::feedback).
    feedback::register(station.clone(), endpoint.secret_key().clone());
    if traces {
        tokio::spawn(telemetry.export(station.clone(), endpoint.secret_key().clone()));
    }
    peer::attach(endpoint.clone(), station.clone());
    while let Some(incoming) = endpoint.accept().await {
        let station = station.clone();
        tokio::spawn(async move {
            match incoming.await {
                Ok(conn) => {
                    let result = if conn.alpn() == peer::ALPN { peer::serve(station, conn).await } else { serve(station, conn).await };
                    if let Err(error) = result {
                        info!(%error, "connection ended");
                    }
                }
                Err(error) => warn!(%error, "incoming connection failed"),
            }
        });
    }
    Ok(())
}

/// How often still.fail's relays are checked (`keep_relays`).
const RELAY_CHECK: Duration = Duration::from_secs(30);

/// still.fail's relays as the cloud names them, its own first (`relay_urls`, or `relay_url` alone from a cloud or a
/// state file from before there were several); one that does not parse is left out.
fn relays(state: &CloudState) -> Vec<RelayUrl> {
    let urls = if state.relay_urls.is_empty() { std::slice::from_ref(&state.relay_url) } else { &state.relay_urls[..] };
    urls.iter().filter_map(|url| url.parse().inspect_err(|error| warn!(%url, %error, "not a relay url")).ok()).collect()
}

/// The strings in a JSON array (none for anything else).
fn strings(value: &Value) -> Vec<String> {
    value.as_array().into_iter().flatten().filter_map(|v| v.as_str().map(str::to_string)).collect()
}

/// Keeps the station's relays still.fail's, the ones browsers reach (relay-only, they know no others), iroh homing
/// on the nearest: a station in mainland China on the relay there, one abroad on Cloudflare's; it stays on the others
/// too (`keep::Keepers`), so a device that reaches only some of them still reaches it. Those the cloud adds or
/// takes away later are put in or taken out as it says so. iroh's public relays are added only while none of ours
/// answers, so the station can still be reached (the DHT says where), and taken away once one does again, so the
/// station goes back home: with them in the map beside ours iroh could pick one of them as home, and browsers would
/// lose the station.
async fn keep_relays(endpoint: Endpoint, station: Arc<Station>) {
    let client = reqwest::Client::builder().timeout(Duration::from_secs(10)).build().expect("http client");
    let public: Vec<Arc<iroh::RelayConfig>> = iroh::defaults::prod::default_relay_map().relays();
    let mut ours: Vec<RelayUrl> = relays(&station.state.lock().unwrap());
    let mut keepers = keep::Keepers::default();
    keepers.set(&endpoint, &ours);
    let mut added = false;
    loop {
        let now = relays(&station.state.lock().unwrap());
        if !now.is_empty() && now != ours {
            info!(relays = ?now, "still.fail's relays changed");
            for url in now.iter().filter(|url| !ours.contains(url)) {
                endpoint.insert_relay(url.clone(), Arc::new(iroh::RelayConfig::from(url.clone()))).await;
            }
            for url in ours.iter().filter(|url| !now.contains(url)) {
                endpoint.remove_relay(url).await;
            }
            keepers.set(&endpoint, &now);
            ours = now;
        }
        // Two tries each: one lost request is not the relay down.
        let mut up = false;
        'relays: for relay in &ours {
            let ping = format!("{}/ping", relay.as_str().trim_end_matches('/'));
            for _ in 0..2 {
                if client.get(&ping).send().await.is_ok_and(|r| r.status().is_success()) {
                    up = true;
                    break 'relays;
                }
            }
        }
        if !up && !added {
            warn!(relays = ?ours, "none of still.fail's relays answers; adding iroh's public relays until one does");
            for config in &public {
                endpoint.insert_relay(config.url.clone(), config.clone()).await;
            }
            added = true;
        } else if up && added {
            info!(relays = ?ours, "still.fail's relays answer again; back home to them");
            for config in &public {
                endpoint.remove_relay(&config.url).await;
            }
            added = false;
        }
        tokio::time::sleep(RELAY_CHECK).await;
    }
}

/// How often a station removed from its workspace asks the cloud whether it is taken back.
const REMOVED_RETRY: Duration = Duration::from_secs(600);

/// REMOVED_RETRY, or the seconds in STILLFAIL_REMOVED_RETRY_SECS (for tests against a dev cloud; not set otherwise).
fn removed_retry() -> Duration {
    std::env::var("STILLFAIL_REMOVED_RETRY_SECS").ok().and_then(|v| v.trim().parse().ok()).map(Duration::from_secs).unwrap_or(REMOVED_RETRY)
}

/// Keeps the presence socket open, reconnecting with backoff; removed from its workspace, only now and then
/// (`REMOVED_RETRY`), or at once when it is enrolled again meanwhile.
async fn presence(station: Arc<Station>, key: SecretKey) {
    let mut backoff = Duration::from_secs(1);
    let mut ready = station.ready.clone();
    loop {
        // Online only while the station answers: its app up.
        let up = *ready.borrow();
        if !up {
            let _ = ready.wait_for(|up| *up).await.map(|_| ());
            backoff = Duration::from_secs(1);
        }
        station.reload();
        if station.removed() {
            let retry = removed_retry();
            let every = if retry == REMOVED_RETRY { "every 10 minutes".to_string() } else { format!("every {} s", retry.as_secs()) };
            write_presence(&station.data, false, Some(&format!("removed from its workspace; the cloud is asked again {every}")));
            let until = Instant::now() + retry;
            while Instant::now() < until {
                tokio::time::sleep(Duration::from_secs(2)).await;
                station.reload();
                if !station.removed() {
                    break;
                }
            }
        }
        let started = Instant::now();
        station.peers_current.store(false, std::sync::atomic::Ordering::SeqCst);
        let ended = connect(&station, &key).await;
        station.peers_current.store(false, std::sync::atomic::Ordering::SeqCst);
        write_presence(&station.data, false, Some(&match &ended {
            Ok(()) => "still.fail cloud closed the presence socket".to_string(),
            Err(error) => error.to_string(),
        }));
        match ended {
            Ok(()) => info!("still.fail cloud closed the presence socket"),
            Err(error) => warn!(%error, "no presence socket to still.fail cloud"),
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
    // As at enrollment, the signed words keep the old name.
    let signature = hex::encode(key.sign(format!("ember-station-connect-v1:{origin}:{id}:{ts}").as_bytes()).to_bytes());
    let mut request = format!("{}/v1/stations/connect", origin.replacen("http", "ws", 1)).into_client_request()?;
    let headers = request.headers_mut();
    // Under both names: the cloud reads the new ones first, one from before the rename only the old.
    for (name, value) in [("station", id.clone()), ("ts", ts.to_string()), ("signature", signature), ("version", version().to_string())] {
        for prefix in ["x-stillfail-", "x-ember-"] {
            headers.insert(tungstenite::http::HeaderName::from_bytes(format!("{prefix}{name}").as_bytes())?, value.parse()?);
        }
    }
    let (mut socket, _) = match tokio::time::timeout(Duration::from_secs(20), tokio_tungstenite::connect_async(request)).await.context("connect timed out")? {
        Ok(connected) => connected,
        Err(tungstenite::Error::Http(response)) if response.status().as_u16() == 404 => {
            removed(station, 404);
            bail!("station removed");
        }
        Err(error) => return Err(error.into()),
    };
    taken_back(station);
    write_presence(&station.data, true, None);
    info!("online at still.fail cloud");
    let mut ping = tokio::time::interval(PING);
    ping.tick().await;
    let mut answered = true;
    let mut ready = station.ready.clone();
    loop {
        tokio::select! {
            // Its app is not up: offline until it is.
            _ = async { let _ = ready.wait_for(|up| !*up).await; } => {
                info!("station not answering; going offline at still.fail cloud");
                let _ = socket.close(None).await;
                return Ok(());
            }
            frame = socket.next() => match frame {
                Some(Ok(Message::Text(text))) if text.as_str() == "pong" => answered = true,
                Some(Ok(Message::Text(text))) => apply_state(station, text.as_str()),
                Some(Ok(Message::Close(frame))) => {
                    if frame.is_some_and(|f| u16::from(f.code) == CLOSE_REMOVED) {
                        removed(station, CLOSE_REMOVED);
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
                    bail!("still.fail cloud stopped answering");
                }
                answered = false;
                socket.send(Message::Text("ping".into())).await?;
            }
        }
    }
}

/// The cloud says the station is out of its workspace (`code`: how it said so): marked in cloud.json, kept there
/// through restarts. The app stops its work on seeing it; clients are refused from now on.
fn removed(station: &Station, code: u16) {
    let mut state = station.state.lock().unwrap();
    if state.removed_at.is_some() {
        return;
    }
    warn!(code, workspace = %state.workspace_name, "this station was removed from its workspace; it stops its work and refuses connections");
    mark_removed(&mut state, now(), code);
    if let Err(error) = save_state(&station.data, &state) {
        warn!(%error, "the removal not written to cloud.json");
    }
}

fn mark_removed(state: &mut CloudState, at: u64, code: u16) {
    state.removed_at = Some(at);
    state.removed_code = Some(code);
}

/// The cloud took the presence socket: a station it had removed is in its workspace again, and works.
fn taken_back(station: &Station) {
    let mut state = station.state.lock().unwrap();
    if state.removed_at.is_none() {
        return;
    }
    info!(workspace = %state.workspace_name, "still.fail cloud takes this station again; back to work");
    state.removed_at = None;
    state.removed_code = None;
    if let Err(error) = save_state(&station.data, &state) {
        warn!(%error, "cloud.json not written");
    }
}

/// Whether the station is online at still.fail cloud, and since when or why not: <data>/run/presence.json, for
/// `stillfail status`.
fn write_presence(data: &Path, online: bool, error: Option<&str>) {
    let text = json!({ "online": online, "at": now(), "error": error }).to_string();
    let _ = std::fs::create_dir_all(data.join("run"));
    if let Err(error) = std::fs::write(data.join("run").join("presence.json"), format!("{text}\n")) {
        warn!(%error, "presence.json not written");
    }
}

/// still.fail cloud says where the station is and what it is called (on connect and whenever that changes, with every
/// revocation it keeps, and its own origin and relay as it has them now: a station enrolled under the old host moves
/// to the new one, and its links with it), and what it takes back as it does.
fn apply_state(station: &Station, text: &str) {
    let Ok(body) = serde_json::from_str::<Value>(text) else { return };
    let mut guard = station.state.lock().unwrap();
    let s = &mut *guard;
    match body["type"].as_str() {
        Some("state") => {
            for (field, key) in [
                (&mut s.workspace, "workspace"),
                (&mut s.workspace_name, "workspace_name"),
                (&mut s.name, "name"),
                (&mut s.origin, "origin"),
                (&mut s.relay_url, "relay_url"),
            ] {
                if let Some(value) = body[key].as_str() {
                    *field = value.to_string();
                }
            }
            // Missing roster means an old cloud: never retain peers from another binding.
            s.peers = body["peers"].as_array().cloned().unwrap_or_default();
            station.peers_current.store(body["peers"].is_array(), std::sync::atomic::Ordering::SeqCst);
            if body["relay_urls"].is_array() {
                s.relay_urls = strings(&body["relay_urls"]);
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
    if station.removed() {
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
                // Removed from the workspace meanwhile: its members' connections end too.
                if station.removed() {
                    conn.close(2u32.into(), b"station_removed");
                    break;
                }
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
        if station.removed() {
            conn.close(2u32.into(), b"station_removed");
            return Ok(());
        }
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
            attributes.push(("stillfail.stream", json!(true)));
        } else {
            attributes.push(("http.response.body.size", json!(outcome.sent)));
        }
        if let Some(via) = self.via {
            attributes.push(("stillfail.path", json!(via)));
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
    // A preview page's WebSocket (`"socket": true`): no body to wait for, the stream carries its messages both ways.
    if head["socket"].as_bool() == Some(true) {
        return socket(station, head, carry, send, recv, outcome, traced).await;
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
    let mut request = hyper::Request::builder().method(method).uri(path).header("host", "stillfail");
    // The caller's headers go on (a preview's page needs its cookies and what it accepts), but not those of the hop,
    // nor any of the station's own (under either name): who is asking is only what this process says.
    for (name, value) in head["headers"].as_object().into_iter().flatten() {
        let lower = name.to_ascii_lowercase();
        if HOP.contains(&lower.as_str()) || lower.starts_with("x-stillfail-") || lower.starts_with("x-ember-") || lower == "traceparent" || lower == "tracestate" {
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
    let seen = stillfail_app::access::Viewer::Mesh {
        sub: viewer.sub.clone(),
        email: viewer.email.clone(),
        name: viewer.name.clone(),
        role: viewer.role.clone(),
        workspace: viewer.workspace.clone(),
        device: viewer.device.clone(),
    };
    let response = if !up { Err(anyhow!("not started")) } else { station.backend.call(request, &seen).await };
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
        if let Ok(chunk) = frame.map_err(|e| anyhow!("{e}"))?.into_data() {
            send.write_all(&chunk).await?;
            outcome.sent += chunk.len();
        }
    }
    send.finish()?;
    Ok(())
}

/// A WebSocket of a web service on this machine, for a preview's page (stillfail_app::preview::open_socket): answered
/// 101 once the service took it, then its messages framed both ways (stillfail_app::preview::FRAME_TEXT) until either
/// side closes. Only a preview's path is opened; its span is the opening, as an event stream's.
async fn socket(station: &Station, head: &Value, carry: Vec<u8>, send: &mut SendStream, recv: &mut RecvStream, outcome: &mut Outcome, traced: &mut Traced<'_>) -> Result<()> {
    let target = traced.path.strip_prefix("/admin/api").and_then(stillfail_app::preview::preview_target);
    let refuse = async |send: &mut SendStream, status: u16, error: String| -> Result<()> {
        write_line(send, &json!({ "status": status, "headers": { "content-type": "application/json" } })).await?;
        send.write_all(json!({ "error": error }).to_string().as_bytes()).await?;
        send.finish()?;
        Ok(())
    };
    let Some((port, path)) = target.filter(|_| !traced.path.contains("..")) else {
        outcome.status = 404;
        return refuse(send, 404, "only a preview's WebSocket is opened over the mesh".into()).await;
    };
    if !*station.ready.borrow() {
        outcome.status = 502;
        return refuse(send, 502, "station unreachable: not started".into()).await;
    }
    let headers: Vec<(String, String)> = head["headers"].as_object().into_iter().flatten().filter_map(|(k, v)| Some((k.to_ascii_lowercase(), v.as_str()?.to_string()))).collect();
    let (service, protocol) = match stillfail_app::preview::open_socket(&headers, port, &path).await {
        Ok(opened) => opened,
        Err((status, error)) => {
            outcome.status = status;
            return refuse(send, status, error).await;
        }
    };
    outcome.status = 101;
    let mut answer = serde_json::Map::new();
    if let Some(protocol) = protocol {
        answer.insert("sec-websocket-protocol".into(), json!(protocol));
    }
    write_line(send, &json!({ "status": 101, "headers": answer })).await?;
    traced.end(outcome, true, None);
    // What came with the head line is the first of the client's frames.
    let from_client = tokio::io::AsyncReadExt::chain(std::io::Cursor::new(carry), recv);
    stillfail_app::preview::pump_socket(service, from_client, send).await;
    Ok(())
}

fn usage() -> ! {
    eprintln!("usage:\n  stillfail-station run --app DIR [--port N] [--data DIR] [--with-parent]\n  stillfail-station enroll <cloud-origin> <token> [--data DIR]\n  stillfail-station status [--data DIR]\n  stillfail-station id [--data DIR]\n  stillfail-station channel [stable|beta] [--app DIR] [--data DIR]\n\n--data: default ~/.stillfail ($STILLFAIL_DATA, else $EMBER_DATA); ~/.ember is moved there on the first start.\nrun: --app is the release (bin/, dist/admin/); --port the loopback port's, which sends old page links to still.fail cloud (default 4760, a free one when it is taken); --with-parent: end when the parent does.");
    std::process::exit(2);
}

/// `status`: where the station is and whether it works, as its files say (mesh/cloud.json; run/station.json and
/// run/presence.json while it runs), for people.
fn status(data: &Path) -> String {
    let when = |at: u64| stillfail_app::transcript::iso(at as i64 * 1000);
    let read = |path: PathBuf| std::fs::read(path).ok().and_then(|b| serde_json::from_slice::<Value>(&b).ok());
    let running = read(data.join("run").join("station.json")).filter(|s| {
        // SAFETY: kill with signal 0 only asks whether the process is there.
        s["pid"].as_i64().is_some_and(|pid| pid > 0 && unsafe { libc::kill(pid as i32, 0) } == 0)
    });
    let mut out = vec![format!("数据目录：{}", data.display())];
    out.push(match &running {
        Some(s) => format!("station：在运行（pid {}，版本 {}）", s["pid"], s["version"].as_str().unwrap_or("?")),
        None => "station：没有在运行".into(),
    });
    let join = "stillfail station enroll <cloud> <token>（token 在 still.fail 的「添加 station」里生成）";
    let Ok(state) = load_state(data) else {
        out.push("workspace：没有加入".into());
        out.push(format!("工作：停着。不在 workspace 里的 station 不接 Slack、不跑 agent 和任务。加入：{join}"));
        return out.join("\n");
    };
    out.push(format!("workspace：{}（{}）", state.workspace_name, state.workspace));
    out.push(format!("station 名字：{}（{}）", state.name, &state.station[..state.station.len().min(12)]));
    out.push(format!("cloud：{}", state.origin));
    if let Some(at) = state.removed_at {
        let how = match state.removed_code {
            Some(CLOSE_REMOVED) => "cloud 断开连接时说的（4004）".to_string(),
            Some(404) => "连接时 cloud 说这台 station 已不在 workspace 里（404）".to_string(),
            Some(code) => format!("代码 {code}"),
            None => String::new(),
        };
        out.push(format!("已被移出：workspace「{}」，{}，{how}", state.workspace_name, when(at)));
        out.push(format!("工作：停着。被移出时停下了 Slack 连接、正在跑的 agent 和任务（任务日志末尾写了原因）；每 10 分钟问一次 cloud，重新被接纳就自动恢复。重新加入：{join}"));
    }
    let presence = read(data.join("run").join("presence.json")).filter(|_| running.is_some());
    out.push(match presence {
        Some(p) if p["online"] == true => format!("在线：是（从 {} 起）", p["at"].as_u64().map(when).unwrap_or_default()),
        Some(p) => format!("在线：否（{}）", p["error"].as_str().unwrap_or("还没连上")),
        None if running.is_none() => "在线：否（station 没有在运行）".into(),
        None => "在线：否".into(),
    });
    if state.removed_at.is_none() {
        out.push("工作：正常（连接 Slack、跑 agent 和任务）".into());
    }
    out.join("\n")
}

#[tokio::main]
async fn main() -> Result<()> {
    // The DHT and mDNS say a lot that is not the station's trouble: a network where the DHT cannot be reached (its
    // bootstrap fails every second there) still finds stations through the relay and the LAN.
    let filter = "info,iroh=warn,swarm_discovery=warn,n0_mainline=off,iroh_mainline_address_lookup=error";
    {
        use tracing_subscriber::layer::SubscriberExt;
        use tracing_subscriber::util::SubscriberInitExt;
        let filter = tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| filter.into());
        tracing_subscriber::registry().with(tracing_subscriber::fmt::layer()).with(filter).with(errors::ErrorLayer).init();
    }
    // Read before anything can replace the release around this binary.
    let _ = version();
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let mut take = |flag: &str| -> Option<String> {
        let i = args.iter().position(|a| a == flag)?;
        let value = args.get(i + 1).cloned();
        args.drain(i..(i + 2).min(args.len()));
        value
    };
    // ~/.stillfail, moved from ~/.ember the first time (given as --data by launchers from before the rename too).
    let home = stillfail_app::former::home();
    let data = stillfail_app::former::data_dir(&home, take("--data").or_else(|| stillfail_app::former::var("DATA")).map(PathBuf::from));
    stillfail_app::former::link_claude_projects(&data, &home.join(stillfail_app::former::FORMER_DATA_DIR));
    let app = take("--app");
    // What the Node part ran on, from launchers written before it went (older desktop apps): taken and let be.
    let _ = take("--node");
    let port = take("--port");
    let handoff = take("--handoff").map(PathBuf::from);
    let with_parent = args.iter().position(|a| a == "--with-parent").map(|i| args.remove(i)).is_some();
    match args.first().map(String::as_str) {
        Some("enroll") if args.len() == 3 => enroll(&data, args[1].trim_end_matches('/'), &args[2]).await,
        Some("status") => {
            println!("{}", status(&data));
            Ok(())
        }
        Some("run") => {
            let Some(app) = app else { usage() };
            let named = port.is_some();
            let port = port.map(|p| p.parse::<u16>()).transpose().context("--port")?.unwrap_or(4760);
            let ran = run(Run { data, app: PathBuf::from(app), port, named, with_parent, handoff }).await;
            if let Some(held) = ran.as_ref().err().and_then(|e| e.downcast_ref::<Held>()) {
                eprintln!("{held}");
                std::process::exit(HELD);
            }
            ran
        }
        // Which handoff this binary reads: asked by the running station before it execs this one.
        Some("handoff-version") => {
            println!("{}", stillfail_app::handoff::VERSION);
            Ok(())
        }
        Some("id") => {
            println!("{}", hex::encode(load_key(&data)?.public().as_bytes()));
            Ok(())
        }
        // The channel the station is updated on (`stillfail update`): set when one is named (kept in its config, read
        // as the station starts), then said; `--app`: the release, which says the channel it came from.
        Some("channel") if args.len() <= 2 => {
            use stillfail_app::updates::{Channel, channel_of};
            let config = stillfail_app::former::var("CONFIG").map(PathBuf::from).unwrap_or_else(|| data.join("config.json"));
            if let Some(named) = args.get(1) {
                let channel = Channel::of(named).ok_or_else(|| anyhow!("channel 必须是 stable 或 beta，不是 {named}"))?;
                set_channel(&data, &config, channel, Duration::from_secs(10), is_station)?;
            }
            let raw = stillfail_app::config::read_raw(&config)?;
            println!("{}", channel_of(&raw, &app.map(PathBuf::from).unwrap_or_default()).id());
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

    /// A credential as the cloud signs one (cloud/src/grants.ts), with `claims` over the usual ones.
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

    /// A data directory of its own, gone with the test.
    struct Dir(PathBuf);

    impl Dir {
        fn new(name: &str) -> Dir {
            let dir = std::env::temp_dir().join(format!("stillfail-station-{name}-{}", std::process::id()));
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(mesh_dir(&dir)).unwrap();
            Dir(dir)
        }
    }

    impl Drop for Dir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn enrolled(dir: &Path) -> Station {
        let state: CloudState = serde_json::from_value(json!({ "origin": "https://app.still.fail", "station": "abcdef0123456789", "workspace": "w", "workspace_name": "Dev", "name": "mac", "relay_url": "https://app.still.fail", "grant_keys": {} })).unwrap();
        save_state(dir, &state).unwrap();
        Station { data: dir.to_path_buf(), state: Mutex::new(state), peers_current: std::sync::atomic::AtomicBool::new(false), backend: local::Backend::default(), ready: watch::channel(true).1, telemetry: Telemetry::new(false) }
    }

    #[test]
    fn a_cloud_json_of_before_opens_and_one_without_a_removal_is_written_as_before() {
        let before = json!({ "origin": "o", "station": "s", "workspace": "w", "workspace_name": "W", "name": "n", "relay_url": "r", "grant_keys": {}, "revocations": [] });
        let state: CloudState = serde_json::from_value(before.clone()).unwrap();
        assert_eq!((state.removed_at, state.removed_code), (None, None));
        let written = serde_json::to_value(&state).unwrap();
        assert!(written.get("removed_at").is_none() && written.get("removed_code").is_none(), "{written}");
        let mut removed = state.clone();
        mark_removed(&mut removed, 1_790_000_000, CLOSE_REMOVED);
        let written = serde_json::to_value(&removed).unwrap();
        assert_eq!((written["removed_at"].clone(), written["removed_code"].clone()), (json!(1_790_000_000), json!(4004)));
        let back: CloudState = serde_json::from_value(written).unwrap();
        assert_eq!((back.removed_at, back.removed_code), (Some(1_790_000_000), Some(4004)));
    }

    #[test]
    fn removed_by_the_cloud_the_mark_is_written_and_stays_through_a_restart() {
        let dir = Dir::new("removed");
        let station = enrolled(&dir.0);
        assert!(!station.removed());
        removed(&station, CLOSE_REMOVED);
        assert!(station.removed());
        // A later removal (the 404 of the next try) keeps the first time and code.
        let at = station.state.lock().unwrap().removed_at;
        removed(&station, 404);
        // The next start reads it from the file.
        let again = load_state(&dir.0).unwrap();
        assert_eq!((again.removed_at, again.removed_code), (at, Some(CLOSE_REMOVED)));
        assert_eq!(again.workspace_name, "Dev", "the rest of the file stays: the desktop app does not join by itself again");
        let said = status(&dir.0);
        assert!(said.contains("已被移出：workspace「Dev」") && said.contains("4004") && said.contains("stillfail station enroll"), "{said}");
        // The app reads the same file (stillfail_app::server::MeshFile): removed, not in a workspace.
        let raw: Value = serde_json::from_slice(&std::fs::read(mesh_dir(&dir.0).join("cloud.json")).unwrap()).unwrap();
        assert!(raw["removed_at"].as_u64().is_some());
    }

    #[test]
    fn taken_back_by_the_cloud_or_enrolled_again_the_mark_goes() {
        let dir = Dir::new("back");
        let station = enrolled(&dir.0);
        removed(&station, 404);
        taken_back(&station);
        assert!(!station.removed());
        assert_eq!(load_state(&dir.0).unwrap().removed_at, None);
        // `enroll` writes the file anew while this runs: taken up as it is.
        removed(&station, CLOSE_REMOVED);
        let mut fresh = load_state(&dir.0).unwrap();
        (fresh.removed_at, fresh.removed_code, fresh.workspace_name) = (None, None, "Other".into());
        save_state(&dir.0, &fresh).unwrap();
        station.reload();
        assert!(!station.removed());
        assert_eq!(station.state.lock().unwrap().workspace_name, "Other");
    }

    #[test]
    fn status_says_where_the_station_is() {
        let dir = Dir::new("status");
        let said = status(&dir.0);
        assert!(said.contains("workspace：没有加入") && said.contains("station：没有在运行") && said.contains("stillfail station enroll"), "{said}");
        enrolled(&dir.0);
        let said = status(&dir.0);
        assert!(said.contains("workspace：Dev（w）") && said.contains("cloud：https://app.still.fail") && said.contains("工作：正常") && said.contains("在线：否"), "{said}");
    }

    #[test]
    fn with_no_station_running_the_channel_is_written_in_the_config() {
        use stillfail_app::updates::Channel;
        let dir = tempfile::tempdir().unwrap();
        let config = dir.path().join("config.json");
        set_channel(dir.path(), &config, Channel::Beta, Duration::from_secs(1), |_| panic!("no station to ask")).unwrap();
        assert_eq!(stillfail_app::config::read_raw(&config).unwrap().update_channel.as_deref(), Some("beta"));
        // Beside a station from before it took the ask: written too (the update that follows restarts it).
        let _held = lock(&dir.path().join("run").join("station.lock")).unwrap();
        std::fs::write(dir.path().join("run").join("station.json"), json!({ "pid": std::process::id(), "drain": 1 }).to_string()).unwrap();
        set_channel(dir.path(), &config, Channel::Stable, Duration::from_secs(1), |_| true).unwrap();
        assert_eq!(stillfail_app::config::read_raw(&config).unwrap().update_channel.as_deref(), Some("stable"));
    }

    #[tokio::test]
    async fn a_running_station_is_asked_for_the_channel_and_keeps_it_itself() {
        use stillfail_app::updates::Channel;
        let dir = tempfile::tempdir().unwrap();
        let (data, run) = (dir.path().to_path_buf(), dir.path().join("run"));
        std::fs::create_dir_all(&run).unwrap();
        // This process plays the station: its lock held, its file saying it takes the ask, SIGHUP taken.
        let _held = lock(&run.join("station.lock")).unwrap();
        std::fs::write(run.join("station.json"), json!({ "pid": std::process::id(), "drain": 1, "channel": 1 }).to_string()).unwrap();
        let mut hup = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::hangup()).unwrap();
        let asked = Arc::new(Mutex::new(Vec::new()));
        let (station_run, kept) = (run.clone(), asked.clone());
        tokio::spawn(async move {
            while hup.recv().await.is_some() {
                answer_channel_ask(&station_run, |channel| {
                    kept.lock().unwrap().push(channel);
                    if channel == Channel::Stable { anyhow::bail!("不行") } else { Ok(()) }
                });
            }
        });
        let config = data.join("config.json");
        let (d, c) = (data.clone(), config.clone());
        tokio::task::spawn_blocking(move || set_channel(&d, &c, Channel::Beta, Duration::from_secs(5), |_| true)).await.unwrap().unwrap();
        assert_eq!(*asked.lock().unwrap(), [Channel::Beta]);
        assert!(!config.exists(), "the running station keeps it, not this");
        assert!(!run.join(CHANNEL_ASK).exists() && !run.join(CHANNEL_ANSWER).exists());
        // What the station says when it cannot.
        let (d, c) = (data.clone(), config.clone());
        let refused = tokio::task::spawn_blocking(move || set_channel(&d, &c, Channel::Stable, Duration::from_secs(5), |_| true)).await.unwrap();
        assert_eq!(refused.unwrap_err().to_string(), "不行");
    }

    #[test]
    fn its_relays_are_the_clouds_list_or_the_one_from_before_there_were_several() {
        let before: CloudState = serde_json::from_value(json!({ "origin": "o", "station": "s", "workspace": "w", "workspace_name": "W", "name": "n", "relay_url": "https://app.still.fail", "grant_keys": {} })).unwrap();
        assert_eq!(relays(&before).iter().map(|u| u.to_string()).collect::<Vec<_>>(), ["https://app.still.fail/"]);
        let now = CloudState { relay_urls: strings(&json!(["https://app.still.fail", "not a url", "https://39.105.157.122"])), ..before };
        assert_eq!(relays(&now).iter().map(|u| u.to_string()).collect::<Vec<_>>(), ["https://app.still.fail/", "https://39.105.157.122/"]);
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
    fn credentials_under_the_new_names_and_the_old_are_both_members() {
        let issued_new = credential("stillfail-member+jwt", json!({ "iss": "stillfail-cloud" }));
        assert_eq!(check(&issued_new, &[]).unwrap().viewer.sub, "bob");
        assert!(check(&credential("ember-member+jwt", json!({})), &[]).is_ok());
        assert!(check(&credential("stillfail-member+jwt", json!({ "iss": "someone-else" })), &[]).is_err());
    }

    #[test]
    fn what_the_cloud_revoked_is_refused_and_what_came_after_is_not() {
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
