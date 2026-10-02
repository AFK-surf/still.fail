//! Prototype: the client's Rust shell. It holds the iroh endpoint and offers it as primitives to a core written in
//! TypeScript (../core/core.ts, types stripped to JS) running in QuickJS, the way the Android app would run it inside
//! its library. Built as a plain binary so it runs on the desktop and, cross-built, on an Android device by `adb shell`.
//!
//! `proto-client-shell <core.js> "<station id> <ip:port>" <chats> [save chats to file]`
//!
//! What the core gets, as `host`: now() log(text) emit(topic, json) save(text) connect(addr) → Promise<json>
//! request(conn, body) → Promise<body>. The network runs on the runtime's worker threads; the JS on this one.

use std::cell::{Cell, RefCell};
use std::net::SocketAddr;
use std::rc::Rc;
use std::time::Instant;

use anyhow::{Context as _, Result, anyhow, bail};
use iroh::endpoint::{Connection, presets::Minimal};
use iroh::{Endpoint, EndpointAddr, EndpointId, RelayMode};
use rquickjs::prelude::Async;
use rquickjs::{AsyncContext, AsyncRuntime, CatchResultExt, Function, Object, Promise};
use serde_json::json;

const ALPN: &[u8] = b"stillfail/proto-shell/1";

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [core, addr, chats, rest @ ..] = args.as_slice() else {
        bail!("usage: proto-client-shell <core.js> \"<station id> <ip:port>\" <chats> [save chats to file]");
    };
    let source = std::fs::read_to_string(core).with_context(|| format!("reading {core}"))?;
    let save = rest.first().cloned();
    let network = tokio::runtime::Builder::new_multi_thread().worker_threads(2).enable_all().build()?;
    network.block_on(run(source, addr.clone(), chats.parse()?, save))
}

async fn run(source: String, addr: String, chats: u32, save: Option<String>) -> Result<()> {
    let endpoint = tokio::spawn(async {
        Endpoint::builder(Minimal).relay_mode(RelayMode::Disabled).bind_addr("0.0.0.0:0".parse::<SocketAddr>()?)?.bind().await.map_err(anyhow::Error::from)
    })
    .await??;

    let started = Instant::now();
    let runtime = AsyncRuntime::new()?;
    let context = AsyncContext::full(&runtime).await?;
    let conns: Rc<RefCell<Vec<Connection>>> = Rc::default();
    let emitted = Rc::new(Cell::new((0usize, 0usize)));
    let result: Rc<RefCell<Option<String>>> = Rc::default();

    let outcome: std::result::Result<(), String> = context.async_with(async |ctx| {
        let setup = || -> rquickjs::Result<()> {
            let host = Object::new(ctx.clone())?;
            host.set("now", Function::new(ctx.clone(), move || started.elapsed().as_secs_f64() * 1000.0)?)?;
            host.set("log", Function::new(ctx.clone(), |text: String| eprintln!("core: {text}"))?)?;
            let (counted, kept) = (emitted.clone(), result.clone());
            host.set("emit", Function::new(ctx.clone(), move |topic: String, value: String| {
                let (n, bytes) = counted.get();
                counted.set((n + 1, bytes + value.len()));
                if topic == "result" {
                    *kept.borrow_mut() = Some(value);
                }
            })?)?;
            host.set("save", Function::new(ctx.clone(), move |text: String| {
                if let Some(path) = &save {
                    let _ = std::fs::write(path, text);
                }
            })?)?;
            let (opened, endpoint) = (conns.clone(), endpoint.clone());
            host.set("connect", Function::new(ctx.clone(), Async(move |addr: String| {
                let (opened, endpoint) = (opened.clone(), endpoint.clone());
                async move {
                    match tokio::spawn(connect(endpoint, addr)).await.map_err(anyhow::Error::from).and_then(|r| r) {
                        Ok(conn) => {
                            opened.borrow_mut().push(conn);
                            json!({ "id": opened.borrow().len() - 1 }).to_string()
                        }
                        Err(error) => json!({ "error": format!("{error:#}") }).to_string(),
                    }
                }
            }))?)?;
            let opened = conns.clone();
            host.set("request", Function::new(ctx.clone(), Async(move |id: u32, body: String| {
                let conn = opened.borrow().get(id as usize).cloned();
                async move {
                    let Some(conn) = conn else { return "\0no such connection".to_string() };
                    match tokio::spawn(request(conn, body)).await.map_err(anyhow::Error::from).and_then(|r| r) {
                        Ok(body) => body,
                        Err(error) => format!("\0{error:#}"),
                    }
                }
            }))?)?;
            ctx.globals().set("host", host)?;
            Ok(())
        };
        setup().catch(&ctx).map_err(|e| e.to_string())?;
        ctx.eval::<(), _>(source).catch(&ctx).map_err(|e| e.to_string())?;
        let main: Function = ctx.globals().get("main").catch(&ctx).map_err(|e| e.to_string())?;
        let promise: Promise = main.call((addr, chats)).catch(&ctx).map_err(|e| e.to_string())?;
        promise.into_future::<()>().await.catch(&ctx).map_err(|e| e.to_string())
    })
    .await;
    outcome.map_err(|e| anyhow!("core: {e}"))?;
    let (n, bytes) = emitted.get();
    println!("{}", result.borrow().clone().unwrap_or_default());
    eprintln!("shell: core emitted {n} times, {bytes} bytes to the UI");
    Ok(())
}

async fn connect(endpoint: Endpoint, addr: String) -> Result<Connection> {
    let (id, ip) = addr.trim().split_once(' ').context("addr: <id> <ip:port>")?;
    let id: EndpointId = id.parse()?;
    let ip: SocketAddr = ip.parse()?;
    Ok(endpoint.connect(EndpointAddr::new(id).with_ip_addr(ip), ALPN).await?)
}

async fn request(conn: Connection, body: String) -> Result<String> {
    let (mut send, mut recv) = conn.open_bi().await?;
    send.write_all(body.as_bytes()).await?;
    send.finish()?;
    Ok(String::from_utf8(recv.read_to_end(64 << 20).await?)?)
}
