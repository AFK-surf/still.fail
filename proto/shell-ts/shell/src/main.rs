//! Prototype: a Rust shell that holds what must outlive the logic (the iroh endpoint and its connections, SQLite)
//! and offers it as primitives to logic written in TypeScript (../logic/main.ts, on Node), one JSON object a line
//! over the logic's stdin/stdout. SIGHUP restarts the logic: the next one starts at once and takes new streams,
//! the old one finishes what it has and exits. No connection notices.
//!
//! shell → logic: {t:"stream",s,conn,peer} {t:"data",s,b} {t:"end",s} {t:"sql",r,rows|changes|error} {t:"drain"}
//! logic → shell: {t:"ready"} {t:"write",s,b} {t:"finish",s} {t:"sql",r,sql,params}
//!
//! `proto-shell serve <data> -- <logic command…>` runs it; `proto-shell client <data>/addr <count> <interval ms>`
//! sends requests on one connection and reports how they went.

use std::collections::{BTreeMap, HashMap};
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};
use base64::Engine;
use base64::engine::general_purpose::STANDARD as B64;
use iroh::endpoint::{Connection, RecvStream, SendStream, presets::Minimal};
use iroh::{Endpoint, EndpointAddr, EndpointId, RelayMode, SecretKey};
use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{ChildStdin, Command};
use tokio::signal::unix::{SignalKind, signal};
use tokio::sync::mpsc::{UnboundedSender, unbounded_channel};

const ALPN: &[u8] = b"stillfail/proto-shell/1";

#[tokio::main]
async fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.iter().map(String::as_str).collect::<Vec<_>>().as_slice() {
        ["serve", data, "--", logic @ ..] if !logic.is_empty() => serve(PathBuf::from(data), logic.iter().map(|s| s.to_string()).collect()).await,
        ["client", addr, count, interval] => client(Path::new(addr), count.parse()?, Duration::from_millis(interval.parse()?)).await,
        _ => bail!("usage: proto-shell serve <data> -- <logic command…> | proto-shell client <addr file> <count> <interval ms>"),
    }
}

// ---- serve ----

enum Event {
    Stream { s: u64, conn: usize, peer: EndpointId, send: SendStream },
    Data { s: u64, bytes: Vec<u8> },
    End { s: u64 },
    Logic { generation: u64, line: String },
    LogicExited { generation: u64, status: String },
    Restart,
}

enum Out {
    Bytes(Vec<u8>),
    Finish,
    Reset,
}

async fn serve(data: PathBuf, command: Vec<String>) -> Result<()> {
    std::fs::create_dir_all(&data)?;
    let endpoint = Endpoint::builder(Minimal)
        .secret_key(load_key(&data)?)
        .alpns(vec![ALPN.to_vec()])
        .relay_mode(RelayMode::Disabled)
        .bind_addr("127.0.0.1:0".parse::<SocketAddr>()?)?
        .bind()
        .await?;
    let ip = *endpoint.bound_sockets().iter().find(|a| a.ip().is_loopback()).context("no loopback socket")?;
    let db = rusqlite::Connection::open(data.join("shell.db"))?;
    let (tx, mut rx) = unbounded_channel();
    tokio::spawn(accept(endpoint.clone(), tx.clone()));
    let restarts = tx.clone();
    let mut hup = signal(SignalKind::hangup())?;
    tokio::spawn(async move {
        while hup.recv().await.is_some() {
            let _ = restarts.send(Event::Restart);
        }
    });
    let mut hub = Hub { db, command, tx, streams: BTreeMap::new(), logics: HashMap::new(), current: 0 };
    hub.start().await?;
    std::fs::write(data.join("addr"), format!("{} {ip}", endpoint.id()))?;
    eprintln!("shell: listening as {} on {ip}", endpoint.id());
    while let Some(event) = rx.recv().await {
        hub.handle(event).await;
    }
    Ok(())
}

fn load_key(data: &Path) -> Result<SecretKey> {
    let path = data.join("key");
    if let Ok(bytes) = std::fs::read(&path)
        && let Ok(bytes) = <[u8; 32]>::try_from(bytes.as_slice())
    {
        return Ok(SecretKey::from_bytes(&bytes));
    }
    let key = SecretKey::generate();
    std::fs::write(&path, key.to_bytes())?;
    Ok(key)
}

async fn accept(endpoint: Endpoint, tx: UnboundedSender<Event>) {
    let ids = Arc::new(AtomicU64::new(0));
    while let Some(incoming) = endpoint.accept().await {
        let (tx, ids) = (tx.clone(), ids.clone());
        tokio::spawn(async move {
            let Ok(conn) = incoming.await else { return };
            eprintln!("shell: connection {} from {}", conn.stable_id(), conn.remote_id());
            while let Ok((send, recv)) = conn.accept_bi().await {
                let s = ids.fetch_add(1, Ordering::Relaxed);
                let _ = tx.send(Event::Stream { s, conn: conn.stable_id(), peer: conn.remote_id(), send });
                tokio::spawn(pump(s, recv, tx.clone()));
            }
            eprintln!("shell: connection {} ended: {:?}", conn.stable_id(), conn.close_reason());
        });
    }
}

async fn pump(s: u64, mut recv: RecvStream, tx: UnboundedSender<Event>) {
    let mut buf = vec![0u8; 16 * 1024];
    while let Ok(Some(n)) = recv.read(&mut buf).await {
        let _ = tx.send(Event::Data { s, bytes: buf[..n].to_vec() });
    }
    let _ = tx.send(Event::End { s });
}

async fn write(mut send: SendStream, mut outs: tokio::sync::mpsc::UnboundedReceiver<Out>) {
    while let Some(out) = outs.recv().await {
        match out {
            Out::Bytes(bytes) => {
                if send.write_all(&bytes).await.is_err() {
                    return;
                }
            }
            Out::Finish => {
                let _ = send.finish();
                return;
            }
            Out::Reset => {
                let _ = send.reset(1u32.into());
                return;
            }
        }
    }
}

struct Stream {
    out: UnboundedSender<Out>,
    /// What the logic has been told of it, to tell again a next logic if this one goes before answering.
    told: Vec<Value>,
    /// The logic that has it.
    logic: Option<u64>,
    wrote: bool,
}

struct Logic {
    stdin: ChildStdin,
    ready: bool,
    draining: bool,
    started: Instant,
}

struct Hub {
    db: rusqlite::Connection,
    command: Vec<String>,
    tx: UnboundedSender<Event>,
    streams: BTreeMap<u64, Stream>,
    logics: HashMap<u64, Logic>,
    /// The logic that takes new streams.
    current: u64,
}

impl Hub {
    async fn start(&mut self) -> Result<()> {
        let generation = self.current + 1;
        let mut child = Command::new(&self.command[0])
            .args(&self.command[1..])
            .env("SHELL_GENERATION", generation.to_string())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .with_context(|| format!("starting {:?}", self.command))?;
        eprintln!("shell: logic #{generation} started, pid {}", child.id().unwrap_or(0));
        let (stdin, stdout) = (child.stdin.take().unwrap(), child.stdout.take().unwrap());
        let tx = self.tx.clone();
        tokio::spawn(async move {
            let mut lines = BufReader::new(stdout).lines();
            while let Ok(Some(line)) = lines.next_line().await {
                let _ = tx.send(Event::Logic { generation, line });
            }
            let status = child.wait().await.map(|s| s.to_string()).unwrap_or_else(|e| e.to_string());
            let _ = tx.send(Event::LogicExited { generation, status });
        });
        self.logics.insert(generation, Logic { stdin, ready: false, draining: false, started: Instant::now() });
        self.current = generation;
        Ok(())
    }

    async fn tell(&mut self, generation: u64, message: &Value) {
        if let Some(logic) = self.logics.get_mut(&generation) {
            let _ = logic.stdin.write_all(format!("{message}\n").as_bytes()).await;
        }
    }

    /// Hands the current logic, once ready, every stream nobody (alive) has and nobody answered yet.
    async fn assign(&mut self) {
        let current = self.current;
        if !self.logics.get(&current).is_some_and(|l| l.ready && !l.draining) {
            return;
        }
        let mut handed = Vec::new();
        for (s, stream) in &mut self.streams {
            let held = stream.logic.is_some_and(|g| self.logics.contains_key(&g));
            if !held && !stream.wrote {
                stream.logic = Some(current);
                handed.push((*s, stream.told.clone()));
            }
        }
        for (s, told) in handed {
            if told.len() > 1 {
                eprintln!("shell: stream {s} handed to logic #{current}");
            }
            for message in told {
                self.tell(current, &message).await;
            }
        }
    }

    /// Something about a stream: told to the logic that has it, kept for a next one.
    async fn about(&mut self, s: u64, message: Value) {
        let Some(stream) = self.streams.get_mut(&s) else { return };
        stream.told.push(message.clone());
        match stream.logic {
            Some(generation) if self.logics.contains_key(&generation) => self.tell(generation, &message).await,
            _ => self.assign().await,
        }
    }

    async fn handle(&mut self, event: Event) {
        match event {
            Event::Stream { s, conn, peer, send } => {
                let (out, outs) = unbounded_channel();
                tokio::spawn(write(send, outs));
                self.streams.insert(s, Stream { out, told: Vec::new(), logic: None, wrote: false });
                self.about(s, json!({ "t": "stream", "s": s, "conn": conn, "peer": peer.to_string() })).await;
            }
            Event::Data { s, bytes } => self.about(s, json!({ "t": "data", "s": s, "b": B64.encode(bytes) })).await,
            Event::End { s } => self.about(s, json!({ "t": "end", "s": s })).await,
            Event::Logic { generation, line } => {
                let Ok(message) = serde_json::from_str::<Value>(&line) else {
                    eprintln!("shell: logic #{generation} said something unreadable: {line}");
                    return;
                };
                self.from_logic(generation, message).await;
            }
            Event::LogicExited { generation, status } => {
                self.logics.remove(&generation);
                eprintln!("shell: logic #{generation} exited ({status})");
                // Streams it had answered part of cannot be answered again; the others go to the next logic.
                let cut: Vec<u64> = self.streams.iter().filter(|(_, st)| st.logic == Some(generation) && st.wrote).map(|(s, _)| *s).collect();
                for s in cut {
                    if let Some(stream) = self.streams.remove(&s) {
                        let _ = stream.out.send(Out::Reset);
                    }
                }
                if generation == self.current {
                    eprintln!("shell: logic #{generation} was current; starting the next");
                    if let Err(error) = self.start().await {
                        eprintln!("shell: {error:#}");
                    }
                } else {
                    self.assign().await;
                }
            }
            Event::Restart => {
                let old = self.current;
                eprintln!("shell: restart: logic #{old} drains");
                if let Some(logic) = self.logics.get_mut(&old) {
                    logic.draining = true;
                }
                self.tell(old, &json!({ "t": "drain" })).await;
                if let Err(error) = self.start().await {
                    eprintln!("shell: {error:#}");
                }
            }
        }
    }

    async fn from_logic(&mut self, generation: u64, message: Value) {
        let s = message["s"].as_u64().unwrap_or(u64::MAX);
        match message["t"].as_str() {
            Some("ready") => {
                if let Some(logic) = self.logics.get_mut(&generation) {
                    logic.ready = true;
                    eprintln!("shell: logic #{generation} ready in {} ms", logic.started.elapsed().as_millis());
                }
                self.assign().await;
            }
            Some("write") => {
                if let Some(stream) = self.streams.get_mut(&s)
                    && stream.logic == Some(generation)
                {
                    stream.wrote = true;
                    let _ = stream.out.send(Out::Bytes(B64.decode(message["b"].as_str().unwrap_or_default()).unwrap_or_default()));
                }
            }
            Some("finish") => {
                if self.streams.get(&s).is_some_and(|st| st.logic == Some(generation))
                    && let Some(stream) = self.streams.remove(&s)
                {
                    let _ = stream.out.send(Out::Finish);
                }
            }
            Some("sql") => {
                let answer = match self.sql(message["sql"].as_str().unwrap_or_default(), message["params"].as_array().map(Vec::as_slice).unwrap_or_default()) {
                    Ok(mut answer) => {
                        answer["t"] = json!("sql");
                        answer["r"] = message["r"].clone();
                        answer
                    }
                    Err(error) => json!({ "t": "sql", "r": message["r"], "error": error.to_string() }),
                };
                self.tell(generation, &answer).await;
            }
            _ => eprintln!("shell: logic #{generation} sent {message}"),
        }
    }

    fn sql(&self, sql: &str, params: &[Value]) -> Result<Value> {
        use rusqlite::types::{Value as Sql, ValueRef};
        let params = params.iter().map(|v| match v {
            Value::Null => Sql::Null,
            Value::Bool(b) => Sql::Integer(*b as i64),
            Value::Number(n) => n.as_i64().map(Sql::Integer).unwrap_or_else(|| Sql::Real(n.as_f64().unwrap_or_default())),
            Value::String(s) => Sql::Text(s.clone()),
            other => Sql::Text(other.to_string()),
        });
        let mut statement = self.db.prepare(sql)?;
        let columns = statement.column_count();
        if columns == 0 {
            let changes = statement.execute(rusqlite::params_from_iter(params))?;
            return Ok(json!({ "changes": changes }));
        }
        let mut rows = statement.query(rusqlite::params_from_iter(params))?;
        let mut out = Vec::new();
        while let Some(row) = rows.next()? {
            let mut values = Vec::with_capacity(columns);
            for i in 0..columns {
                values.push(match row.get_ref(i)? {
                    ValueRef::Null => Value::Null,
                    ValueRef::Integer(n) => json!(n),
                    ValueRef::Real(f) => json!(f),
                    ValueRef::Text(t) => json!(String::from_utf8_lossy(t)),
                    ValueRef::Blob(b) => json!(B64.encode(b)),
                });
            }
            out.push(Value::Array(values));
        }
        Ok(json!({ "rows": out }))
    }
}

// ---- client ----

async fn client(addr: &Path, count: u64, interval: Duration) -> Result<()> {
    let text = std::fs::read_to_string(addr)?;
    let (id, ip) = text.trim().split_once(' ').context("addr file: <id> <ip:port>")?;
    let id: EndpointId = id.parse()?;
    let ip: SocketAddr = ip.parse()?;
    let endpoint = Endpoint::builder(Minimal).relay_mode(RelayMode::Disabled).bind_addr("127.0.0.1:0".parse::<SocketAddr>()?)?.bind().await?;
    let conn = endpoint.connect(EndpointAddr::new(id).with_ip_addr(ip), ALPN).await?;
    let started = Instant::now();
    println!("client: connected, connection {}", conn.stable_id());
    let (tx, mut rx) = unbounded_channel();
    for i in 0..count {
        let (conn, tx) = (conn.clone(), tx.clone());
        tokio::spawn(async move {
            let sent = Instant::now();
            let result = request(&conn, i).await;
            let _ = tx.send((i, sent.elapsed(), result));
        });
        tokio::time::sleep(interval).await;
    }
    drop(tx);
    let mut answers = BTreeMap::new();
    let mut failed = Vec::new();
    let mut slowest = Duration::ZERO;
    while let Some((i, took, result)) = rx.recv().await {
        slowest = slowest.max(took);
        match result {
            Ok(answer) if answer["ok"] == true => {
                answers.insert(i, answer);
            }
            Ok(answer) => failed.push(format!("#{i}: {answer}")),
            Err(error) => failed.push(format!("#{i}: {error:#}")),
        }
    }
    // Which logic answered, in order of the requests.
    let mut last = None;
    for (i, answer) in &answers {
        let who = (answer["generation"].as_u64(), answer["version"].as_str().map(str::to_string), answer["pid"].as_u64());
        if last.as_ref() != Some(&who) {
            println!("client: from #{i}: logic #{} {} (pid {})", who.0.unwrap_or(0), who.1.clone().unwrap_or_default(), who.2.unwrap_or(0));
            last = Some(who);
        }
    }
    for failure in &failed {
        println!("client: failed {failure}");
    }
    println!(
        "client: {} requests over {:.1} s, {} answered, {} failed, slowest {} ms, connection {} still open: {}",
        count,
        started.elapsed().as_secs_f64(),
        answers.len(),
        failed.len(),
        slowest.as_millis(),
        conn.stable_id(),
        conn.close_reason().is_none(),
    );
    conn.close(0u32.into(), b"done");
    endpoint.close().await;
    if !failed.is_empty() {
        std::process::exit(1);
    }
    Ok(())
}

async fn request(conn: &Connection, i: u64) -> Result<Value> {
    let (mut send, mut recv) = conn.open_bi().await?;
    send.write_all(format!("{}\n", json!({ "op": "hit", "i": i })).as_bytes()).await?;
    send.finish()?;
    let body = recv.read_to_end(1 << 20).await?;
    Ok(serde_json::from_slice(&body)?)
}
