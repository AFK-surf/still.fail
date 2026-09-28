//! The station as one piece, as ember-station runs it in its own process: the settings, store, chat connections, hub
//! and runtimes, the admin API and page, and the agents' MCP endpoint. (src/main.ts, src/mesh.ts)
//!
//! ember-station hands it requests: its local page's (a browser here: the viewer is this machine, or Cloudflare
//! Access's through a tunnel) and ember cloud members' through the mesh (the viewer it verified).

use std::collections::HashMap;
use std::convert::Infallible;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use anyhow::Result;
use bytes::Bytes;
use ember_shapes::RuntimeKind;
use futures_util::future::BoxFuture;
use http_body_util::BodyExt;
use hyper::{Request, Response};
use hyper_util::rt::TokioIo;
use serde_json::{Value, json};
use tokio::sync::watch;
use tracing::{error, info, warn};

use crate::access::{AccessDenied, AccessGate, Viewer};
use crate::admin::{AdminApi, AdminDeps, Body, CheckRequest, Mesh, MeshStatus, full, json_response};
use crate::agent_home::{link_agent_home, link_transcripts};
use crate::chat::internal::InternalChat;
use crate::chat::names::NameBook;
use crate::chat::slack::SlackSurface;
use crate::chat::{ChatEvent, ChatSurface};
use crate::config::{Config, Profile};
use crate::connections::{Connection, Connections};
use crate::hub::{Hub, HubOptions};
use crate::login::{LoginCommands, LoginManager};
use crate::machine_logins::{MachineLogins, process_env};
use crate::mcp::McpEndpoint;
use crate::runtime::AgentDriver;
use crate::runtime::claude::ClaudeDriver;
use crate::runtime::codex::CodexDriver;
use crate::settings::Settings;
use crate::store::Store;

/// Where the station keeps what it keeps, and where its page is built.
pub struct AppOptions {
    pub data: PathBuf,
    pub config: PathBuf,
    /// The built page (dist/admin).
    pub ui: PathBuf,
}

/// This station's place in ember cloud, as <data>/mesh/cloud.json says (written by `ember station enroll`, kept up to
/// date by ember cloud); looked at every couple of seconds, so an enrollment or a rename shows at once.
pub struct MeshFile {
    path: PathBuf,
    changes: watch::Sender<u64>,
}

impl MeshFile {
    pub fn new(data: &Path) -> Arc<MeshFile> {
        let file = Arc::new(MeshFile { path: data.join("mesh").join("cloud.json"), changes: watch::channel(0).0 });
        let me = Arc::downgrade(&file);
        tokio::spawn(async move {
            let mut last: Option<Option<Vec<u8>>> = None;
            loop {
                let Some(file) = me.upgrade() else { return };
                let now = std::fs::read(&file.path).ok();
                if last.as_ref().is_some_and(|was| *was != now) {
                    file.changes.send_modify(|n| *n += 1);
                }
                last = Some(now);
                drop(file);
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
        });
        file
    }
}

impl Mesh for MeshFile {
    fn status(&self) -> MeshStatus {
        let Some(state) = std::fs::read(&self.path).ok().and_then(|b| serde_json::from_slice::<Value>(&b).ok()) else {
            return MeshStatus { state: "off".into(), ..MeshStatus::default() };
        };
        let text = |k: &str| state[k].as_str().map(String::from);
        MeshStatus { state: "running".into(), origin: text("origin"), station: text("station"), workspace: text("workspace_name"), workspace_id: text("workspace"), name: text("name") }
    }
    fn changes(&self) -> watch::Receiver<u64> {
        self.changes.subscribe()
    }
}

/// The profiles as the agent home links them: id, runtimes, home.
fn homes(config: &Config) -> Vec<(String, Vec<RuntimeKind>, PathBuf)> {
    config.profiles.iter().map(|p| (p.id.clone(), p.runtimes.clone(), p.home.clone())).collect()
}

fn link_homes(config: &Config) {
    let homes = homes(config);
    let refs: Vec<(&str, &[RuntimeKind], &Path)> = homes.iter().map(|(id, rs, home)| (id.as_str(), rs.as_slice(), home.as_path())).collect();
    if let Err(e) = link_agent_home(&config.agent_home, &refs) {
        warn!(error = %e, "agent home not linked");
    }
    if let Err(e) = crate::agent_home::write_builtin_skills(&config.agent_home) {
        warn!(error = %e, "the station's skills not written");
    }
    if let Err(e) = link_transcripts(&config.data_dir, &refs) {
        warn!(error = %e, "transcripts not linked");
    }
}

pub struct App {
    settings: Arc<Settings>,
    connections: Arc<Connections>,
    hub: Arc<Hub>,
    jobs: Arc<crate::jobs::Jobs>,
    logins: Arc<LoginManager>,
    admin: Arc<AdminApi>,
    gate: AccessGate,
    ui: PathBuf,
    up: AtomicBool,
    pub mesh: Arc<MeshFile>,
}

impl App {
    /// Starts everything: the MCP endpoint listens first (agents are told its address), then the connects connect and
    /// cut-off turns resume.
    pub async fn start(options: AppOptions) -> Result<Arc<App>> {
        let settings = Settings::open(&options.config, &options.data)?;
        let config = settings.config();
        let store = Arc::new(Store::open(&options.data.join("ember.db").to_string_lossy(), None)?);
        link_homes(&config);
        let reaped = crate::runtime::process::reap_stale_groups(&store).await?;
        if reaped > 0 {
            warn!(count = reaped, "reaped runtime processes left by a previous run");
        }
        let listener = crate::ports::listen(&config.http.host, config.http.port, config.http.named, "agent 的 MCP 端点").await?;
        let port = listener.local_addr()?.port();
        if port != config.http.port {
            warn!(port, "the MCP endpoint's usual port is taken; listening on a free one");
        }
        let mcp_url = format!("http://{}:{port}/mcp", config.http.host);

        // Display names of people who reached this station through ember cloud, by email.
        let names: Arc<Mutex<HashMap<String, String>>> = Arc::default();
        // Slack's names for people and channels, kept on disk; learning new ones refreshes what shows them.
        let book = NameBook::open(config.data_dir.join("slack-names.json"));
        let learned = store.clone();
        book.on_learn(move || {
            for session in learned.list_sessions().unwrap_or_default() {
                learned.notify(&session.key);
            }
        });
        let hub_cell: Arc<OnceLock<Arc<Hub>>> = Arc::default();
        let receiver = hub_cell.clone();
        let connections = Connections::new(
            Box::new(move |connect| Ok(SlackSurface::new(&connect.slack.app_token, &connect.slack.bot_token, Some(book.clone()))? as Arc<dyn Connection>)),
            Arc::new(move |id: String, event: ChatEvent| {
                let hub = receiver.get().cloned();
                Box::pin(async move {
                    match hub {
                        Some(hub) => hub.receive(&id, event).await,
                        None => Ok(()),
                    }
                }) as BoxFuture<'static, Result<()>>
            }),
        );
        let codex = Arc::new(CodexDriver::new(store.clone(), "codex"));
        let claude = Arc::new(ClaudeDriver::new(store.clone(), "claude"));
        let mesh = MeshFile::new(&options.data);
        let (read, chats, link, people) = (settings.clone(), connections.clone(), mesh.clone(), names.clone());
        let hub = Hub::new(HubOptions {
            config: Arc::new(move || read.config()),
            store: store.clone(),
            chats: Arc::new(move |id| chats.chat(id).map(|c| c as Arc<dyn ChatSurface>)),
            drivers: vec![claude as Arc<dyn AgentDriver>, codex.clone()],
            mcp_url,
            internal: Some(Arc::new(InternalChat::new(move |user| {
                people.lock().unwrap().get(user).cloned().unwrap_or_else(|| if user == "local" { "管理员".into() } else { user.to_string() })
            }))),
            // A session's /o/ link on ember cloud (it opens the app where there is one, else the web), once this
            // station is in a workspace.
            link: Some(Box::new(move |session: &str| {
                let status = link.status();
                match (status.origin, status.station, status.workspace_id) {
                    (Some(origin), Some(station), Some(workspace)) => Some(format!("{origin}/o/{workspace}/{station}/{}", encode(session))),
                    _ => None,
                }
            })),
        });
        let _ = hub_cell.set(hub.clone());
        // Background jobs and web services (jobs.rs): their agents told through the hub; a service's link is ember
        // cloud's /o/ link of its session, with its port.
        let (told, linked) = (Arc::downgrade(&hub), mesh.clone());
        let jobs = crate::jobs::Jobs::new(
            store.clone(),
            &options.data,
            Arc::new(move |session: &str, text: String| {
                if let Some(hub) = told.upgrade() {
                    if let Err(e) = hub.notify(session, text) {
                        warn!(session, error = %e, "job notice not given");
                    }
                }
            }),
            Arc::new(move |session: &str, job: &str| {
                let status = linked.status();
                match (status.origin, status.station, status.workspace_id) {
                    (Some(origin), Some(station), Some(workspace)) => Some(format!("{origin}/o/{workspace}/{station}/{}?service={}", encode(session), encode(job))),
                    _ => None,
                }
            }),
        )?;
        jobs.set_notify_url(format!("http://{}:{port}/jobs/notify", config.http.host));
        let (tokens, homes_of) = (store.clone(), store.clone());
        let mut tools = hub.tools();
        tools.extend(jobs.tools(Arc::new(move |key| homes_of.get_session(key).ok().flatten().map(|row| PathBuf::from(row.workspace)))));
        let mcp = Arc::new(McpEndpoint::new(move |token| tokens.session_by_token(token).ok().flatten().map(|row| row.key), tools));
        let logins = LoginManager::new(&config.data_dir, LoginCommands::default());
        // The machine's own Claude Code and Codex logins, read at start and again as pages ask.
        let machine_logins = MachineLogins::new(
            process_env(),
            Some(Arc::new(|runtime, env| Box::pin(async move { crate::quota::machine_usage(runtime, env).await.and_then(|q| serde_json::to_value(q).ok()) }))),
        );
        let refresh = machine_logins.clone();
        tokio::spawn(async move { refresh.refresh().await });
        let (quota_codex, models_codex) = (codex.clone(), codex.clone());
        let admin = AdminApi::new(AdminDeps {
            settings: settings.clone(),
            store: store.clone(),
            hub: hub.clone(),
            connections: connections.clone(),
            logins: logins.clone(),
            names,
            mesh: Some(mesh.clone() as Arc<dyn Mesh>),
            quota: Some(Arc::new(move |profile: Profile| {
                let codex = quota_codex.clone();
                Box::pin(async move {
                    let limits = move |p: &Profile| {
                        let (codex, p) = (codex.clone(), p.clone());
                        Box::pin(async move { codex.rate_limits(&p).await }) as BoxFuture<'static, Result<Value>>
                    };
                    crate::quota::check_quota(&profile, &process_env(), &limits).await
                })
            })),
            check_profile: Arc::new(|request: CheckRequest| {
                Box::pin(async move {
                    let env = process_env();
                    let p = &request.profile;
                    crate::profiles::check_profile(crate::profiles::CheckOptions { runtime: p.runtime, kind: p.access_kind, key: &p.key, home: &request.home, env: &env, machine: p.machine }).await
                })
            }),
            codex_models: Some(Arc::new(move |profile: Profile| {
                let codex = models_codex.clone();
                Box::pin(async move { codex.models(&profile).await })
            })),
            slack_apps: None,
            check_on_start: true,
            machine_logins: Some(machine_logins),
            dev: std::env::var("EMBER_DEV").as_deref() == Ok("1"),
            jobs: Some(jobs.clone()),
        });
        let access = settings.clone();
        let gate = AccessGate::new(move || access.config().admin_access.clone(), None, || None);
        let app = Arc::new(App { settings: settings.clone(), connections: connections.clone(), hub: hub.clone(), jobs: jobs.clone(), logins, admin, gate, ui: options.ui, up: AtomicBool::new(false), mesh });

        // Edits apply as they are saved: homes linked, connects (re)connected.
        let mut edits = settings.subscribe();
        let reconnect = connections.clone();
        tokio::spawn(async move {
            while edits.changed().await.is_ok() {
                let config = edits.borrow_and_update().clone();
                link_homes(&config);
                reconnect.reconcile(&config).await;
            }
        });
        tokio::spawn(serve_mcp(listener, mcp, jobs.clone()));
        info!(port, "ember listening");
        connections.reconcile(&config).await;
        if connections.ids().is_empty() {
            warn!("no connect is connected; add or enable one on the admin page");
        }
        hub.recover()?;
        jobs.relaunch();
        app.up.store(true, Ordering::SeqCst);
        Ok(app)
    }

    pub fn up(&self) -> bool {
        self.up.load(Ordering::SeqCst)
    }

    /// One request of the station's page or admin API. `viewer`: who ember-station verified (the mesh); None for this
    /// machine's own page, whose viewer the Access gate says.
    pub async fn handle<B>(&self, req: Request<B>, viewer: Option<Viewer>) -> Response<Body>
    where
        B: hyper::body::Body<Data = Bytes> + Send + Unpin + 'static,
        B::Error: std::error::Error + Send + Sync + 'static,
    {
        let path = req.uri().path().to_string();
        if path == "/healthz" {
            return plain(if self.up() { 200 } else { 503 }, "");
        }
        if !self.up() {
            return plain(503, "ember station is starting");
        }
        if path.starts_with("/admin/api/") {
            let viewer = match viewer {
                Some(viewer) => viewer,
                None => {
                    let headers = req.headers().clone();
                    match self.gate.check(|name| headers.get(name).and_then(|v| v.to_str().ok()).map(String::from), true).await {
                        Ok(viewer) => viewer,
                        Err(e) if e.downcast_ref::<AccessDenied>().is_some() => return json_response(403, &json!({ "error": e.to_string() })),
                        Err(e) => {
                            error!(error = %e, "access check failed");
                            return json_response(500, &json!({ "error": e.to_string() }));
                        }
                    }
                }
            };
            return self.admin.handle(req, viewer).await;
        }
        if viewer.is_some() {
            return json_response(404, &json!({ "error": "only the admin API is reachable over the mesh" }));
        }
        if path == "/admin" || path.starts_with("/admin/") {
            return self.serve_ui(&path).await;
        }
        if path == "/" {
            return Response::builder().status(302).header("location", "/admin").body(full(Bytes::new())).expect("a response");
        }
        plain(404, "")
    }

    /// Files under dist/admin by path; anything else gets index.html, where the client router takes over.
    async fn serve_ui(&self, path: &str) -> Response<Body> {
        let relative = clean_relative(path.strip_prefix("/admin").unwrap_or(""));
        let Some(relative) = relative else { return plain(400, "") };
        let hashed = relative.starts_with("assets/");
        let has_extension = Path::new(&relative).extension().is_some();
        let candidates = if !relative.is_empty() && has_extension { vec![relative.clone(), "index.html".into()] } else { vec!["index.html".to_string()] };
        for file in candidates {
            let Ok(content) = tokio::fs::read(self.ui.join(&file)).await else { continue };
            // Vite fingerprints assets; the shell must always be revalidated.
            let cache = if hashed && file == relative { "public, max-age=31536000, immutable" } else { "no-cache" };
            return Response::builder().status(200).header("content-type", ui_type(&file)).header("cache-control", cache).body(full(content)).expect("a response");
        }
        plain(503, "admin client not built: run `pnpm build`")
    }

    /// Stops: sign-ins end, connects disconnect, runtimes end (a running turn stays marked running, for the next start
    /// to resume).
    pub async fn shutdown(&self) {
        info!("shutting down");
        self.up.store(false, Ordering::SeqCst);
        self.logins.stop_all();
        self.connections.stop_all().await;
        self.jobs.shutdown().await;
        self.hub.shutdown().await;
        drop(self.settings.clone());
    }
}

/// A path under the page's directory, `.` and `..` worked out; None when it would leave it.
fn clean_relative(path: &str) -> Option<String> {
    let mut parts: Vec<&str> = vec![];
    for part in path.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop()?;
            }
            p => parts.push(p),
        }
    }
    Some(parts.join("/"))
}

fn ui_type(file: &str) -> &'static str {
    match Path::new(file).extension().and_then(|e| e.to_str()) {
        Some("html") => "text/html; charset=utf-8",
        Some("js") => "text/javascript; charset=utf-8",
        Some("css") => "text/css; charset=utf-8",
        Some("svg") => "image/svg+xml",
        Some("png") => "image/png",
        Some("webmanifest") => "application/manifest+json",
        Some("woff2") => "font/woff2",
        _ => "application/octet-stream",
    }
}

fn plain(status: u16, text: &str) -> Response<Body> {
    Response::builder().status(status).header("content-type", "text/plain; charset=utf-8").body(full(text.to_string())).expect("a response")
}

/// encodeURIComponent.
fn encode(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'!' | b'~' | b'*' | b'\'' | b'(' | b')' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

/// The agents' MCP endpoint, and what their jobs say (`ember-job notify`): loopback only, /mcp, /jobs/notify and
/// /health.
async fn serve_mcp(listener: tokio::net::TcpListener, mcp: Arc<McpEndpoint>, jobs: Arc<crate::jobs::Jobs>) {
    loop {
        let (stream, _) = match listener.accept().await {
            Ok(accepted) => accepted,
            Err(e) => {
                warn!(error = %e, "mcp accept failed");
                continue;
            }
        };
        let (mcp, jobs) = (mcp.clone(), jobs.clone());
        tokio::spawn(async move {
            let service = hyper::service::service_fn(move |req: Request<hyper::body::Incoming>| {
                let (mcp, jobs) = (mcp.clone(), jobs.clone());
                async move { Ok::<_, Infallible>(answer_mcp(&mcp, &jobs, req).await) }
            });
            let _ = hyper::server::conn::http1::Builder::new().serve_connection(TokioIo::new(stream), service).await;
        });
    }
}

async fn answer_mcp(mcp: &McpEndpoint, jobs: &crate::jobs::Jobs, req: Request<hyper::body::Incoming>) -> Response<Body> {
    match req.uri().path() {
        "/health" => json_response(200, &json!({ "ok": true })),
        "/jobs/notify" if req.method() == hyper::Method::POST => {
            let token = req.headers().get("authorization").and_then(|v| v.to_str().ok()).and_then(|a| a.strip_prefix("Bearer ")).unwrap_or("").to_string();
            let body = match http_body_util::Limited::new(req.into_body(), 64 * 1024).collect().await {
                Ok(body) => body.to_bytes(),
                Err(e) => return json_response(400, &json!({ "error": e.to_string() })),
            };
            match jobs.notified(&token, &String::from_utf8_lossy(&body)) {
                Ok(()) => json_response(200, &json!({ "ok": true })),
                Err(e) => json_response(400, &json!({ "error": e.to_string() })),
            }
        }
        "/mcp" => {
            let method = req.method().as_str().to_string();
            let authorization = req.headers().get("authorization").and_then(|v| v.to_str().ok()).map(String::from);
            let body = match req.into_body().collect().await {
                Ok(body) => body.to_bytes(),
                Err(e) => return json_response(400, &json!({ "error": e.to_string() })),
            };
            let reply = mcp.handle(&method, authorization.as_deref(), &body).await;
            match reply.body {
                Some(body) => json_response(reply.status, &body),
                None => Response::builder().status(reply.status).body(full(Bytes::new())).expect("a response"),
            }
        }
        _ => plain(404, ""),
    }
}
