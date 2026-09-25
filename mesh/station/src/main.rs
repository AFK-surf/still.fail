//! ember-mesh: an ember station's way into ember cloud.
//!
//! `enroll` redeems a one-time token from a workspace admin, proving this
//! station holds its iroh key. `run` keeps the station reachable: it reports
//! in to ember cloud, accepts iroh connections from clients that present a
//! grant signed by ember cloud, and relays each stream's request to the
//! station's local admin API with the verified identity attached.
//!
//! Wire format on ALPN `ember/admin/1`: the first bidirectional stream carries
//! grants (one JSON line each, answered with one JSON line; a later line
//! renews). Every other stream is one request: a JSON head line
//! `{"method","path","headers"}`, then the body until the stream finishes;
//! answered by a JSON head line `{"status","headers"}` and the response body.

use std::{
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use anyhow::{Context, Result, anyhow, bail};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD as B64};
use futures_util::StreamExt;
use iroh::{
    Endpoint, RelayMode, RelayUrl, SecretKey,
    endpoint::{Connection, RecvStream, SendStream, presets::Minimal},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tracing::{info, warn};

const ALPN: &[u8] = b"ember/admin/1";
const MAX_HEAD: usize = 16 * 1024;
const MAX_BODY: usize = 4 * 1024 * 1024;
const VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Serialize, Deserialize, Clone)]
struct CloudState {
    origin: String,
    station: String,
    workspace: String,
    workspace_name: String,
    name: String,
    relay_url: String,
    grant_keys: Value,
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
    };
    save_state(data, &state)?;
    println!("已加入 workspace「{}」，这台 station 叫「{}」（{}）。", state.workspace_name, state.name, &station[..12]);
    Ok(())
}

/// Who a verified grant speaks for.
#[derive(Clone, Serialize)]
struct Viewer {
    sub: String,
    email: String,
    name: String,
    role: String,
    workspace: String,
    device: String,
}

/// Verifies an ember cloud grant for this station and the connecting device.
fn verify_grant(grant: &str, keys: &Value, station: &str, workspace: &str, device: &str) -> Result<(Viewer, u64)> {
    let mut parts = grant.split('.');
    let (Some(head), Some(body), Some(sig), None) = (parts.next(), parts.next(), parts.next(), parts.next()) else { bail!("malformed grant") };
    let header: Value = serde_json::from_slice(&B64.decode(head)?)?;
    if header["alg"] != "EdDSA" {
        bail!("unexpected grant algorithm");
    }
    let kid = header["kid"].as_str();
    let jwk = keys["keys"]
        .as_array()
        .and_then(|keys| keys.iter().find(|k| kid.is_none() || k["kid"].as_str() == kid))
        .ok_or_else(|| anyhow!("unknown grant key"))?;
    let x: [u8; 32] = B64.decode(jwk["x"].as_str().unwrap_or_default())?.try_into().map_err(|_| anyhow!("bad grant key"))?;
    let key = ed25519_dalek::VerifyingKey::from_bytes(&x)?;
    let signature = ed25519_dalek::Signature::from_slice(&B64.decode(sig)?)?;
    key.verify_strict(format!("{head}.{body}").as_bytes(), &signature).map_err(|_| anyhow!("grant signature invalid"))?;
    let claims: Value = serde_json::from_slice(&B64.decode(body)?)?;
    let text = |k: &str| claims[k].as_str().unwrap_or_default().to_string();
    let exp = claims["exp"].as_u64().unwrap_or(0);
    if text("iss") != "ember-cloud" {
        bail!("grant not issued by ember cloud");
    }
    if text("aud") != station {
        bail!("grant is for another station");
    }
    if text("ws") != workspace {
        bail!("grant is for another workspace");
    }
    if text("device") != device {
        bail!("grant is for another device");
    }
    if exp <= now() {
        bail!("grant expired");
    }
    Ok((Viewer { sub: text("sub"), email: text("email"), name: text("name"), role: text("role"), workspace: text("ws"), device: device.to_string() }, exp))
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
    admin: String,
    secret: String,
    removed: Mutex<bool>,
}

async fn run(data: &Path, admin: String, secret: String) -> Result<()> {
    let key = load_key(data)?;
    let state = load_state(data)?;
    let relay: RelayUrl = state.relay_url.parse().context("relay url")?;
    let endpoint = Endpoint::builder(Minimal)
        .secret_key(key)
        .alpns(vec![ALPN.to_vec()])
        .relay_mode(RelayMode::Custom(relay.into()))
        .bind()
        .await?;
    info!(station = %endpoint.id(), workspace = %state.workspace_name, "ember-mesh listening");
    let station = Arc::new(Station { data: data.to_path_buf(), state: Mutex::new(state), admin, secret, removed: Mutex::new(false) });
    tokio::spawn(heartbeat(station.clone(), endpoint.secret_key().clone()));
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

/// Reports in every minute, picking up key rotations; stops serving once the station was removed.
async fn heartbeat(station: Arc<Station>, key: SecretKey) {
    let client = http();
    loop {
        let (origin, id) = {
            let s = station.state.lock().unwrap();
            (s.origin.clone(), s.station.clone())
        };
        let ts = now();
        let signature = hex::encode(key.sign(format!("ember-station-heartbeat-v1:{origin}:{id}:{ts}").as_bytes()).to_bytes());
        let result = client
            .post(format!("{origin}/v1/stations/heartbeat"))
            .json(&json!({ "station": id, "ts": ts, "signature": signature, "version": VERSION }))
            .send()
            .await;
        match result {
            Ok(r) if r.status().is_success() => {
                if let Ok(body) = r.json::<Value>().await {
                    let mut s = station.state.lock().unwrap();
                    s.workspace = body["workspace"].as_str().unwrap_or(&s.workspace).to_string();
                    s.name = body["name"].as_str().unwrap_or(&s.name).to_string();
                    if body["grant_keys"].is_object() {
                        s.grant_keys = body["grant_keys"].clone();
                    }
                    let _ = save_state(&station.data, &s);
                }
                *station.removed.lock().unwrap() = false;
            }
            Ok(r) if r.status() == reqwest::StatusCode::NOT_FOUND => {
                warn!("this station was removed from its workspace; refusing connections");
                *station.removed.lock().unwrap() = true;
            }
            Ok(r) => warn!(status = %r.status(), "heartbeat refused"),
            Err(error) => warn!(%error, "heartbeat failed; ember cloud unreachable"),
        }
        tokio::time::sleep(Duration::from_secs(60)).await;
    }
}

async fn serve(station: Arc<Station>, conn: Connection) -> Result<()> {
    if *station.removed.lock().unwrap() {
        conn.close(2u32.into(), b"station_removed");
        bail!("station removed");
    }
    let device = hex::encode(conn.remote_id().as_bytes());
    // The first stream carries the grant; nothing else is served before it checks out.
    let (mut send, mut recv) = conn.accept_bi().await?;
    let mut carry = Vec::new();
    let check = |line: &Value| -> Result<(Viewer, u64)> {
        let s = station.state.lock().unwrap();
        verify_grant(line["grant"].as_str().unwrap_or_default(), &s.grant_keys, &s.station, &s.workspace, &device)
    };
    let first = read_line(&mut recv, &mut carry).await?.ok_or_else(|| anyhow!("no grant"))?;
    let (viewer, exp) = match check(&first) {
        Ok(v) => v,
        Err(error) => {
            write_line(&mut send, &json!({ "error": error.to_string() })).await.ok();
            send.finish().ok();
            tokio::time::sleep(Duration::from_millis(200)).await;
            conn.close(1u32.into(), b"grant_refused");
            return Err(error);
        }
    };
    let station_name = station.state.lock().unwrap().name.clone();
    write_line(&mut send, &json!({ "ok": true, "station": station_name, "expires_at": exp })).await?;
    info!(email = %viewer.email, device = %&device[..12], "client connected");
    let current = Arc::new(Mutex::new((viewer, exp)));

    // Renewals on the grant stream; the connection closes when the grant runs out.
    let renew = {
        let (current, station, conn, device) = (current.clone(), station.clone(), conn.clone(), device.clone());
        async move {
            loop {
                tokio::select! {
                    line = read_line(&mut recv, &mut carry) => {
                        let Ok(Some(line)) = line else { break };
                        let verified = {
                            let s = station.state.lock().unwrap();
                            verify_grant(line["grant"].as_str().unwrap_or_default(), &s.grant_keys, &s.station, &s.workspace, &device)
                        };
                        let reply = match verified {
                            Ok((viewer, exp)) => { *current.lock().unwrap() = (viewer, exp); json!({ "ok": true, "expires_at": exp }) }
                            Err(error) => json!({ "error": error.to_string() }),
                        };
                        if write_line(&mut send, &reply).await.is_err() { break }
                    }
                    _ = tokio::time::sleep(Duration::from_secs(5)) => {}
                }
                if current.lock().unwrap().1 <= now() {
                    conn.close(3u32.into(), b"grant_expired");
                    break;
                }
            }
        }
    };
    tokio::spawn(renew);

    let client = reqwest::Client::builder().build()?;
    loop {
        let (send, recv) = match conn.accept_bi().await {
            Ok(streams) => streams,
            Err(_) => return Ok(()),
        };
        let (viewer, exp) = current.lock().unwrap().clone();
        if exp <= now() {
            conn.close(3u32.into(), b"grant_expired");
            return Ok(());
        }
        let (station, client) = (station.clone(), client.clone());
        tokio::spawn(async move {
            if let Err(error) = relay_request(&station, &client, &viewer, send, recv).await {
                info!(%error, "request failed");
            }
        });
    }
}

/// One request stream: to the local admin API, with the verified viewer attached, and back.
async fn relay_request(station: &Station, client: &reqwest::Client, viewer: &Viewer, mut send: SendStream, mut recv: RecvStream) -> Result<()> {
    let mut carry = Vec::new();
    let head = read_line(&mut recv, &mut carry).await?.ok_or_else(|| anyhow!("empty request"))?;
    let method = head["method"].as_str().unwrap_or("GET").to_uppercase();
    let path = head["path"].as_str().unwrap_or_default().to_string();
    if !path.starts_with("/admin/api/") || path.contains("..") {
        write_line(&mut send, &json!({ "status": 404, "headers": { "content-type": "application/json" } })).await?;
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
    let mut request = client
        .request(method.parse()?, format!("{}{}", station.admin, path))
        .header("x-ember-mesh", &station.secret)
        .header("x-ember-viewer", B64.encode(serde_json::to_vec(viewer)?));
    if let Some(ct) = head["headers"]["content-type"].as_str() {
        request = request.header("content-type", ct);
    }
    if !body.is_empty() {
        request = request.body(body);
    }
    let response = match request.send().await {
        Ok(r) => r,
        Err(error) => {
            write_line(&mut send, &json!({ "status": 502, "headers": { "content-type": "application/json" } })).await?;
            send.write_all(json!({ "error": format!("station unreachable: {error}") }).to_string().as_bytes()).await?;
            send.finish()?;
            return Ok(());
        }
    };
    let content_type = response.headers().get("content-type").and_then(|v| v.to_str().ok()).unwrap_or("application/octet-stream").to_string();
    write_line(&mut send, &json!({ "status": response.status().as_u16(), "headers": { "content-type": content_type } })).await?;
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        send.write_all(&chunk?).await?;
    }
    send.finish()?;
    Ok(())
}

fn usage() -> ! {
    eprintln!("usage:\n  ember-mesh enroll <ember-cloud-origin> <token> [--data DIR]\n  ember-mesh run [--data DIR] [--admin URL]\n  ember-mesh id [--data DIR]\n\nrun reads the admin secret from EMBER_MESH_SECRET.");
    std::process::exit(2);
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info,iroh=warn".into())).init();
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let mut take = |flag: &str| -> Option<String> {
        let i = args.iter().position(|a| a == flag)?;
        let value = args.get(i + 1).cloned();
        args.drain(i..(i + 2).min(args.len()));
        value
    };
    let data = PathBuf::from(take("--data").unwrap_or_else(|| format!("{}/.ember", std::env::var("HOME").unwrap_or_default())));
    let admin = take("--admin").unwrap_or_else(|| "http://127.0.0.1:4760".into());
    match args.first().map(String::as_str) {
        Some("enroll") if args.len() == 3 => enroll(&data, args[1].trim_end_matches('/'), &args[2]).await,
        Some("run") => {
            let secret = std::env::var("EMBER_MESH_SECRET").context("EMBER_MESH_SECRET is not set")?;
            run(&data, admin, secret).await
        }
        Some("id") => {
            println!("{}", hex::encode(load_key(&data)?.public().as_bytes()));
            Ok(())
        }
        _ => usage(),
    }
}
