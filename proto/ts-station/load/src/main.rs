//! Prototype: what a station needs to be tried on one machine, and a client to try it with.
//!
//! `station-load setup <data>`: a test workspace for a station's data directory: its key (mesh/secret.key), and
//! mesh/cloud.json with a grant key of our own (its private half in <data>/grant.key), so that credentials this tool
//! signs are a member's. The rest of cloud.json (relays, origin) is the caller's to fill in.
//! `station-load ask <data> <station id> <ip:port,…> <path>`: one request, its answer's head on stderr, its body on stdout.
//! `station-load load <data> <station id> <ip:port,…> <seconds> <concurrency> <path>…`: requests on one connection,
//! `concurrency` at a time, round-robin over the paths, for `seconds`; how they went.

use std::net::SocketAddr;
use std::path::Path;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, bail};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD as B64};
use ed25519_dalek::{Signer, SigningKey};
use iroh::endpoint::{Connection, presets::Minimal};
use iroh::{Endpoint, EndpointAddr, PublicKey, RelayMode};
use serde_json::{Value, json};

const ALPN: &[u8] = b"stillfail/admin/1";
const WORKSPACE: &str = "test-workspace";

#[tokio::main]
async fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.iter().map(String::as_str).collect::<Vec<_>>().as_slice() {
        ["setup", data] => setup(Path::new(data)),
        ["ask", data, id, addrs, path] => {
            let conn = connect(Path::new(data), id, addrs).await?;
            let (head, body) = request(&conn, path).await?;
            eprintln!("{head}");
            println!("{}", String::from_utf8_lossy(&body));
            Ok(())
        }
        ["load", data, id, addrs, seconds, concurrency, paths @ ..] if !paths.is_empty() => {
            let conn = connect(Path::new(data), id, addrs).await?;
            load(conn, Duration::from_secs(seconds.parse()?), concurrency.parse()?, paths.iter().map(|p| p.to_string()).collect()).await
        }
        _ => bail!("usage: station-load setup <data> | ask <data> <id> <addrs> <path> | load <data> <id> <addrs> <seconds> <concurrency> <path>…"),
    }
}

fn setup(data: &Path) -> Result<()> {
    std::fs::create_dir_all(data.join("mesh"))?;
    let station = iroh::SecretKey::generate();
    std::fs::write(data.join("mesh").join("secret.key"), station.to_bytes())?;
    let grant = SigningKey::generate(&mut rand::rngs::OsRng);
    std::fs::write(data.join("grant.key"), grant.to_bytes())?;
    let cloud = json!({
        "origin": "http://127.0.0.1:9", "station": hex::encode(station.public().as_bytes()), "workspace": WORKSPACE,
        "workspace_name": "测试", "name": "测试 station", "relay_url": "", "relay_urls": [],
        "grant_keys": { "keys": [{ "kty": "OKP", "crv": "Ed25519", "kid": "test", "x": B64.encode(grant.verifying_key().as_bytes()) }] },
        "peers": [], "revocations": [],
    });
    std::fs::write(data.join("mesh").join("cloud.json"), serde_json::to_string_pretty(&cloud)?)?;
    println!("{}", hex::encode(station.public().as_bytes()));
    Ok(())
}

/// A member's credential for this device, as still.fail cloud signs one.
fn credential(data: &Path, device: &str) -> Result<String> {
    let bytes: [u8; 32] = std::fs::read(data.join("grant.key"))?.try_into().map_err(|_| anyhow::anyhow!("grant.key"))?;
    let grant = SigningKey::from_bytes(&bytes);
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
    let email = std::env::var("VIEWER").unwrap_or_else(|_| "zuozijian1994@gmail.com".into());
    let head = B64.encode(json!({ "alg": "EdDSA", "typ": "stillfail-member+jwt", "kid": "test" }).to_string());
    let body = B64.encode(json!({
        "iss": "stillfail-cloud", "ws": WORKSPACE, "device": device, "sub": "test-account", "email": email, "name": "测试",
        "role": "owner", "sid": "test-session", "iat": now, "exp": now + 3600,
    }).to_string());
    let sig = B64.encode(grant.sign(format!("{head}.{body}").as_bytes()).to_bytes());
    Ok(format!("{head}.{body}.{sig}"))
}

async fn connect(data: &Path, id: &str, addrs: &str) -> Result<Connection> {
    let bytes: [u8; 32] = hex::decode(id)?.try_into().map_err(|_| anyhow::anyhow!("station id"))?;
    let mut addr = EndpointAddr::new(PublicKey::from_bytes(&bytes)?);
    for a in addrs.split(',').filter(|a| !a.is_empty()) {
        addr = addr.with_ip_addr(a.parse::<SocketAddr>()?);
    }
    let endpoint = Endpoint::builder(Minimal).relay_mode(RelayMode::Disabled).bind().await?;
    let conn = endpoint.connect(addr, ALPN).await?;
    let (mut send, mut recv) = conn.open_bi().await?;
    let device = hex::encode(endpoint.id().as_bytes());
    send.write_all(format!("{}\n", json!({ "credential": credential(data, &device)?, "protocol": 1 })).as_bytes()).await?;
    let mut line = Vec::new();
    let mut byte = [0u8; 1];
    while recv.read(&mut byte).await?.is_some() && byte[0] != b'\n' {
        line.push(byte[0]);
    }
    let answer: Value = serde_json::from_slice(&line)?;
    if std::env::var("DEBUG").is_ok() {
        eprintln!("load: {answer}");
    }
    if answer["ok"] != true {
        bail!("refused: {answer}");
    }
    // The credential stream stays open for the connection's life, and the endpoint (dropped, it closes) for the program's.
    std::mem::forget((send, recv, endpoint));
    Ok(conn)
}

async fn request(conn: &Connection, path: &str) -> Result<(Value, Vec<u8>)> {
    let debug = std::env::var("DEBUG").is_ok();
    let (mut send, mut recv) = conn.open_bi().await?;
    send.write_all(format!("{}\n", json!({ "method": "GET", "path": path, "headers": {} })).as_bytes()).await?;
    send.finish()?;
    if debug {
        eprintln!("load: asked {path}");
    }
    let all = recv.read_to_end(256 << 20).await?;
    if debug {
        eprintln!("load: {} bytes back", all.len());
    }
    let at = all.iter().position(|b| *b == b'\n').context("no head")?;
    Ok((serde_json::from_slice(&all[..at])?, all[at + 1..].to_vec()))
}

async fn load(conn: Connection, seconds: Duration, concurrency: usize, paths: Vec<String>) -> Result<()> {
    let until = Instant::now() + seconds;
    let mut workers = Vec::new();
    for w in 0..concurrency {
        let (conn, paths) = (conn.clone(), paths.clone());
        workers.push(tokio::spawn(async move {
            let mut took = Vec::new();
            let mut failed = 0usize;
            let mut i = w;
            while Instant::now() < until {
                let started = Instant::now();
                match request(&conn, &paths[i % paths.len()]).await {
                    Ok((head, _)) if head["status"] == 200 => took.push(started.elapsed().as_secs_f64() * 1000.0),
                    _ => failed += 1,
                }
                i += concurrency;
            }
            (took, failed)
        }));
    }
    let mut took = Vec::new();
    let mut failed = 0;
    for w in workers {
        let (t, f) = w.await?;
        took.extend(t);
        failed += f;
    }
    took.sort_by(f64::total_cmp);
    let at = |q: f64| took.get(((took.len() as f64 - 1.0) * q).round() as usize).copied().unwrap_or(0.0);
    println!("{}", json!({
        "requests": took.len(), "failed": failed, "perSecond": took.len() as f64 / seconds.as_secs_f64(),
        "p50": at(0.5), "p95": at(0.95), "max": at(1.0),
    }));
    Ok(())
}
