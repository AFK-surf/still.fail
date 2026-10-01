//! The station as one piece, as stillfail-station runs it in its own process: the settings, store, chat connections, hub
//! and runtimes, the admin API, and the agents' MCP endpoint.
//!
//! stillfail-station hands it the requests of still.fail cloud's members through the mesh (the viewer it verified);
//! there is no page of its own on this machine any more. It works only while in a workspace (<data>/mesh/cloud.json
//! says so, `MeshFile`): outside one, no connect connects, no turn starts, no job runs (`App::unbind`).

use std::collections::HashMap;
use std::convert::Infallible;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use anyhow::Result;
use bytes::Bytes;
use stillfail_shapes::RuntimeKind;
use futures_util::future::BoxFuture;
use http_body_util::BodyExt;
use hyper::{Request, Response};
use serde_json::{Value, json};
use tokio::sync::watch;
use tracing::{info, warn};

use crate::access::Viewer;
use crate::admin::{AdminApi, AdminDeps, Body, CheckRequest, Mesh, MeshStatus, full, json_response};
use crate::agent_home::{link_agent_home, link_transcripts};
use crate::chat::internal::InternalChat;
use crate::chat::names::NameBook;
use crate::chat::slack::SlackSurface;
use crate::chat::{ChatEvent, ChatSurface};
use crate::config::{Config, Profile};
use crate::connections::{Connection, Connections};
use crate::handoff::{Door, HandedApp};
use crate::hub::{Hold, Hub, HubOptions};
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
    /// The release's dist/admin, where the station page was built: now only what goes with a release (posthog.json).
    pub ui: PathBuf,
    /// What the previous binary handed over (handoff.rs), when it exec'd this one.
    pub handoff: Option<HandedApp>,
}

/// The station's store in the data directory: named as before the rename, so a release from before it still opens
/// it (through the link ~/.ember).
pub const DB_FILE: &str = "ember.db";

/// This station's place in still.fail cloud, as <data>/mesh/cloud.json says (written by `stillfail station enroll`, kept
/// up to date by the cloud, marked `removed_at` by stillfail-station when the cloud says it was removed); looked at every
/// couple of seconds, so an enrollment, a removal or a rename shows at once.
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
        let removed_at = state["removed_at"].as_u64();
        MeshStatus {
            state: if removed_at.is_some() { "removed" } else { "running" }.into(),
            origin: text("origin"),
            station: text("station"),
            workspace: text("workspace_name"),
            workspace_id: text("workspace"),
            name: text("name"),
            removed_at,
        }
    }
    fn changes(&self) -> watch::Receiver<u64> {
        self.changes.subscribe()
    }
}

/// Why the station does no work, for the logs of the jobs it stops.
fn out_why(status: &MeshStatus) -> String {
    match (status.state.as_str(), &status.workspace) {
        ("removed", Some(workspace)) => format!("the station was removed from its workspace ({workspace})"),
        ("removed", None) => "the station was removed from its workspace".to_string(),
        _ => "the station is in no workspace".to_string(),
    }
}

/// The profiles as the agent home links them: id, runtimes, home.
fn homes(config: &Config) -> Vec<(String, Vec<RuntimeKind>, PathBuf)> {
    config.profiles.iter().map(|p| (p.id.clone(), p.runtimes.clone(), p.home.clone())).collect()
}

/// `feedback`: the station brings the stillfail-feedback skill (feedback.rs; not on the test channel).
fn link_homes(config: &Config, feedback: bool) {
    let homes = homes(config);
    let refs: Vec<(&str, &[RuntimeKind], &Path)> = homes.iter().map(|(id, rs, home)| (id.as_str(), rs.as_slice(), home.as_path())).collect();
    if let Err(e) = link_agent_home(&config.agent_home, &refs) {
        warn!(error = %e, "agent home not linked");
    }
    if let Err(e) = crate::agent_home::write_builtin_skills(&config.agent_home, feedback) {
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
    pub remote: Arc<crate::remote::Remote>,
    logins: Arc<LoginManager>,
    admin: Arc<AdminApi>,
    up: AtomicBool,
    pub mesh: Arc<MeshFile>,
    /// In a workspace: doing its work (`bind`, `unbind`).
    bound: Arc<AtomicBool>,
    /// Started outside a workspace: cut-off turns not resumed and jobs not taken up yet, owed once it joins one.
    owed: AtomicBool,
    /// The agents' MCP endpoint.
    mcp: Arc<Door>,
    updates: Arc<crate::updates::Updates>,
}

impl App {
    /// Starts everything: the MCP endpoint listens first (agents are told its address), then the connects connect and
    /// cut-off turns resume.
    pub async fn start(options: AppOptions) -> Result<Arc<App>> {
        let settings = Settings::open(&options.config, &options.data)?;
        let config = settings.config();
        let store = Arc::new(Store::open(&options.data.join(DB_FILE).to_string_lossy(), None)?);
        // Bug reports to the still.fail team (feedback.rs): not from the test channel's stations, the team's own. As the
        // station started: a switch of channel comes with a new release, so a restart.
        let feedback = crate::updates::channel_of(&settings.raw(), &crate::updates::app_of(&options.ui)) == crate::updates::Channel::Stable;
        link_homes(&config, feedback);
        let mut handoff = options.handoff;
        let kept = handoff.as_ref().map(|h| h.pgids().into_iter().collect()).unwrap_or_default();
        let reaped = crate::runtime::process::reap_stale_groups(&store, &kept).await?;
        if reaped > 0 {
            warn!(count = reaped, "reaped runtime processes left by a previous run");
        }
        let handed_listener = match handoff.as_mut().and_then(|h| h.mcp.take()) {
            Some(fd) => match crate::handoff::claim_listener(fd) {
                Ok(listener) => Some(listener),
                Err(e) => {
                    warn!(error = %e, "the MCP endpoint's socket handed over could not be taken up; listening anew");
                    None
                }
            },
            None => None,
        };
        let handed = handed_listener.is_some();
        let listener = match handed_listener {
            Some(listener) => listener,
            None => crate::ports::listen(&config.http.host, config.http.port, config.http.named, "agent 的 MCP 端点").await?,
        };
        let port = listener.local_addr()?.port();
        if port != config.http.port && !handed {
            warn!(port, "the MCP endpoint's usual port is taken; listening on a free one");
        }
        let mcp_url = format!("http://{}:{port}/mcp", config.http.host);

        // Display names of people who reached this station through still.fail cloud, by email.
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
            // A session's /o/ link on still.fail cloud (it opens the app where there is one, else the web), once this
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
        // What the previous binary handed over runs on from where it was.
        if let Some(handoff) = handoff.take() {
            hub.adopt(handoff.hub).await;
        }
        // Background jobs and web services (jobs.rs): their agents told through the hub; a service's link is still.fail
        // cloud's /o/ link of its session, with its port.
        let (told, linked) = (Arc::downgrade(&hub), mesh.clone());
        let jobs = crate::jobs::Jobs::new(
            store.clone(),
            &options.data,
            Arc::new(move |session: &str, text: String| {
                // Remote task notices are kept by Jobs and returned to the source station by Remote.
                if session.starts_with("remote:") { return; }
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
        let told=Arc::downgrade(&hub);
        let remote = crate::remote::Remote::new(settings.clone(), store.clone(), jobs.clone(), Arc::new(move |session, text| {
            told.upgrade().ok_or_else(|| anyhow::anyhow!("station is shutting down"))?.notify(session,text)
        }))?;
        hub.set_jobs(&jobs);
        jobs.set_notify_url(format!("http://{}:{port}/jobs/notify", config.http.host));
        let (tokens, homes_of) = (store.clone(), store.clone());
        let mut tools = hub.tools();
        tools.extend(remote.tools());
        tools.extend(jobs.tools(Arc::new(move |key| homes_of.get_session(key).ok().flatten().map(|row| PathBuf::from(row.workspace)))));
        if feedback {
            let pages = mesh.clone();
            tools.extend(crate::feedback::tools(
                store.clone(),
                Arc::new(move |session: &str| {
                    let status = pages.status();
                    match (status.origin, status.station, status.workspace_id) {
                        (Some(origin), Some(station), Some(workspace)) => Some(format!("{origin}/o/{workspace}/{station}/{}", encode(session))),
                        _ => None,
                    }
                }),
            ));
        }
        // A station does no work outside a workspace: never in one, or removed from it.
        let status = mesh.status();
        let bound = Arc::new(AtomicBool::new(status.bound()));
        // Nor do its agents reach out of it meanwhile (mcp.rs OUTWARD): their runtimes end as it leaves (`unbind`), and
        // a call that still comes is refused. cloud.json read as well, so the refusal starts as soon as it is marked.
        let (gate_bound, gate_mesh) = (bound.clone(), mesh.clone());
        let mcp = Arc::new(McpEndpoint::new(move |token| tokens.session_by_token(token).ok().flatten().map(|row| row.key), tools).gated(move || {
            (!gate_bound.load(Ordering::SeqCst) || !gate_mesh.status().bound()).then(|| crate::mcp::UNBOUND_REFUSAL.to_string())
        }));
        let logins = LoginManager::new(&config.data_dir, LoginCommands::default());
        // The machine's own Claude Code and Codex logins, read at start and again as pages ask.
        let machine_logins = MachineLogins::new(
            process_env(),
            Some(Arc::new(|runtime, env| Box::pin(async move { crate::quota::machine_usage(runtime, env).await.and_then(|q| serde_json::to_value(q).ok()) }))),
        );
        let refresh = machine_logins.clone();
        tokio::spawn(async move { refresh.refresh().await });
        // The station's and the runtimes' versions, read at start and every few hours; updated from the pages.
        let origin_of = mesh.clone();
        let updates = crate::updates::Updates::new(
            crate::updates::app_of(&options.ui),
            options.data.clone(),
            process_env(),
            settings.clone(),
            Box::new(move || origin_of.status().origin),
        );
        let counted = Arc::downgrade(&hub);
        updates.count_running(move || counted.upgrade().map_or(0, |hub| hub.running()));
        // A runtime installed or updated from the pages: its login line (没有装 Codex…) read again.
        let reread = machine_logins.clone();
        updates.on_runtime_changed(move || {
            let reread = reread.clone();
            tokio::spawn(async move { reread.refresh().await });
        });
        updates.start();
        // What the agents spent, read from their transcripts as they grow.
        let usage = crate::usage::Usage::new(store.clone(), settings.clone());
        usage.start();
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
            updates: Some(updates.clone()),
            dev: crate::former::var("DEV").as_deref() == Some("1"),
            jobs: Some(jobs.clone()),
            usage: Some(usage),
        });
        // What the chats' people hear about while no client of theirs runs (the station process posts it on).
        crate::admin::notify::Notifier::start(&admin);
        let mcp_door = serve_mcp(listener, mcp, jobs.clone());
        let app = Arc::new(App {
            settings: settings.clone(),
            connections: connections.clone(),
            hub: hub.clone(),
            jobs: jobs.clone(),
            remote,
            logins,
            admin,
            up: AtomicBool::new(false),
            mesh,
            bound: bound.clone(),
            owed: AtomicBool::new(false),
            mcp: mcp_door,
            updates,
        });

        // Edits apply as they are saved: homes linked, connects (re)connected while in a workspace.
        let mut edits = settings.subscribe();
        let (reconnect, reconnecting) = (connections.clone(), bound.clone());
        tokio::spawn(async move {
            while edits.changed().await.is_ok() {
                let config = edits.borrow_and_update().clone();
                link_homes(&config, feedback);
                if reconnecting.load(Ordering::SeqCst) {
                    reconnect.reconcile(&config).await;
                }
            }
        });
        info!(port, "station listening");
        if status.bound() {
            connections.reconcile(&config).await;
            if connections.ids().is_empty() {
                warn!("no connect is connected; add or enable one in the workspace's settings");
            }
            hub.recover()?;
        } else {
            unbound_warning(&status, &config);
            hub.hold(Hold::Unbound);
            app.owed.store(true, Ordering::SeqCst);
            // Removed, and the station stopped before it stopped its jobs (or crashed): what still runs is ended now.
            if status.state == "removed" {
                jobs.stop_all(&out_why(&status)).await;
            }
        }
        // Chats idle long enough go to the archive (Hub::auto_archive): looked at now and every hour.
        let archiving = hub.clone();
        tokio::spawn(async move {
            let mut hourly = tokio::time::interval(std::time::Duration::from_secs(3600));
            loop {
                hourly.tick().await;
                if let Err(error) = archiving.auto_archive(crate::store::now_ms()) {
                    warn!(error = %error, "auto-archiving failed");
                }
            }
        });
        // The bug reports its agents sent that are fixed and out (feedback.rs): each session told, a few minutes after the
        // start and every hour.
        if feedback {
            let told = Arc::downgrade(&hub);
            tokio::spawn(async move {
                tokio::time::sleep(std::time::Duration::from_secs(300)).await;
                let mut hourly = tokio::time::interval(crate::feedback::FIXED_EVERY);
                loop {
                    hourly.tick().await;
                    let Some(hub) = told.upgrade() else { return };
                    if let Err(error) = crate::feedback::tell_fixed(&move |session: &str, text: String| hub.notify(session, text)).await {
                        warn!(error = %error, "fixed bug reports not read");
                    }
                }
            });
        }
        if status.bound() {
            jobs.relaunch();
        }
        tokio::spawn(follow_binding(Arc::downgrade(&app)));
        app.up.store(true, Ordering::SeqCst);
        Ok(app)
    }

    /// Whether the station is in a workspace, and so does its work.
    pub fn bound(&self) -> bool {
        self.bound.load(Ordering::SeqCst)
    }

    /// In a workspace (again): connects connect, turns cut off resume (by a start outside one, or by leaving it), what
    /// a start outside one left owed is done (jobs taken up), and turns start, what waited meanwhile first.
    async fn bind(&self) {
        if self.bound.swap(true, Ordering::SeqCst) {
            return;
        }
        info!("in a workspace: connects, turns and jobs go on");
        self.connections.reconcile(&self.settings.config()).await;
        // Resumed while still held: a message that waited joins the resumed turn rather than racing it.
        if let Err(e) = self.hub.recover() {
            warn!(error = %e, "cut-off turns not resumed");
        }
        if self.owed.swap(false, Ordering::SeqCst) {
            self.jobs.relaunch();
        }
        self.hub.release(Hold::Unbound);
    }

    /// Out of its workspace (removed, or its cloud.json taken away): no turn starts, the agents' runtime processes end
    /// (turns under way are resumed once it is back, Hub::suspend_all), their outward tools are refused, connects
    /// disconnect, jobs and services stop (their logs say why). Messages that come meanwhile wait.
    async fn unbind(&self, status: &MeshStatus) {
        if !self.bound.swap(false, Ordering::SeqCst) {
            return;
        }
        let why = out_why(status);
        warn!(why, "out of its workspace: ending the agents' runtimes, stopping connects, jobs and services");
        self.hub.hold(Hold::Unbound);
        self.hub.suspend_all().await;
        self.connections.stop_all().await;
        self.jobs.stop_all(&why).await;
    }

    pub fn up(&self) -> bool {
        self.up.load(Ordering::SeqCst)
    }

    /// One request of the admin API, from `viewer`: who stillfail-station verified (the mesh). Nothing else is served:
    /// the page is still.fail cloud's.
    pub async fn handle<B>(&self, req: Request<B>, viewer: Viewer) -> Response<Body>
    where
        B: hyper::body::Body<Data = Bytes> + Send + Unpin + 'static,
        B::Error: std::error::Error + Send + Sync + 'static,
    {
        let path = req.uri().path().to_string();
        if !self.up() {
            return plain(503, "still.fail station is starting");
        }
        if path.starts_with("/admin/api/") {
            return self.admin.handle(req, viewer).await;
        }
        json_response(404, &json!({ "error": "only the admin API is reachable over the mesh" }))
    }

    /// Holds turns: none starts, messages stay pending (Hub::hold). For a restart: once none runs, nothing is cut off.
    /// Puts the station on an update channel as this machine asked (`stillfail update --beta`/`--stable`, through
    /// stillfail-station): kept in its config by this process, which holds it, and what is out read again.
    pub fn set_update_channel(&self, channel: crate::updates::Channel) -> Result<()> {
        self.updates.keep_channel(channel)?;
        let updates = self.updates.clone();
        tokio::spawn(async move { updates.check().await });
        Ok(())
    }

    pub fn hold(&self) {
        self.hub.hold(Hold::Drain);
    }

    /// Lets turns start again (unless the station is in no workspace).
    pub fn release(&self) {
        self.hub.release(Hold::Drain);
    }

    /// Whether any turn is running.
    pub fn any_running(&self) -> bool {
        self.hub.any_running()
    }

    /// Gives up what runs to the station's next binary (handoff.rs), and stops. Until the runtimes' readers stop it
    /// can still fail and go on as it was; after, it cannot: the caller must exec the next binary (or exit, and the
    /// next start resumes what was cut off the usual way).
    pub async fn hand_off(&self) -> Result<HandedApp> {
        // Tool calls under way finish (they may still change a session's state); new ones wait for the next binary.
        self.mcp.pause(Duration::from_secs(30)).await?;
        let hub = match self.hub.hand_off().await {
            Ok(hub) => hub,
            Err(e) => {
                self.mcp.resume();
                return Err(e);
            }
        };
        self.up.store(false, Ordering::SeqCst);
        let mcp = self.mcp.keep().map_err(|e| warn!(error = %e, "the MCP endpoint's socket is not handed over")).ok();
        self.logins.stop_all();
        self.connections.stop_all().await;
        self.jobs.shutdown().await;
        Ok(HandedApp { mcp, hub })
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

/// Binds and unbinds the station as its cloud.json changes (enrolled, removed, taken back), for as long as it runs.
async fn follow_binding(app: std::sync::Weak<App>) {
    let Some(mut changes) = app.upgrade().map(|app| app.mesh.changes()) else { return };
    while changes.changed().await.is_ok() {
        let Some(app) = app.upgrade() else { return };
        let status = app.mesh.status();
        if status.bound() {
            app.bind().await;
        } else {
            app.unbind(&status).await;
        }
    }
}

/// Said at a start outside a workspace, loudly when it has connects that would have connected: they stay off until the
/// station joins one (docs/ops-log.md: stations never enrolled stop taking Slack's messages with this release).
fn unbound_warning(status: &MeshStatus, config: &Config) {
    let connects = config.connects.iter().filter(|c| c.enabled).count();
    let state = if status.state == "removed" { "removed from its workspace" } else { "in no workspace" };
    if connects > 0 {
        warn!(
            connects,
            "this station is {state}: its connects stay disconnected, and no turn or job runs, until it joins one (`stillfail station enroll <cloud> <token>`; `stillfail status` says more)"
        );
    } else {
        warn!("this station is {state}: no turn or job runs until it joins one (`stillfail station enroll <cloud> <token>`)");
    }
}

fn plain(status: u16, text: &str) -> Response<Body> {
    Response::builder().status(status).header("content-type", "text/plain; charset=utf-8").body(full(text.to_string())).expect("a response")
}

/// encodeURIComponent.
pub(crate) fn encode(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'!' | b'~' | b'*' | b'\'' | b'(' | b')' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

/// The agents' MCP endpoint, and what their jobs say (`stillfail-job notify`): loopback only, /mcp, /jobs/notify and
/// /health.
fn serve_mcp(listener: tokio::net::TcpListener, mcp: Arc<McpEndpoint>, jobs: Arc<crate::jobs::Jobs>) -> Arc<Door> {
    let cell: Arc<OnceLock<std::sync::Weak<Door>>> = Arc::default();
    let door_of = cell.clone();
    let door = Door::open(listener, move |stream, closing| {
        let (mcp, jobs, door) = (mcp.clone(), jobs.clone(), door_of.clone());
        tokio::spawn(async move {
            let service = hyper::service::service_fn(move |req: Request<hyper::body::Incoming>| {
                let (mcp, jobs) = (mcp.clone(), jobs.clone());
                let busy = door.get().and_then(std::sync::Weak::upgrade).map(|d| d.busy());
                async move {
                    let answer = answer_mcp(&mcp, &jobs, req).await;
                    drop(busy);
                    Ok::<_, Infallible>(answer)
                }
            });
            crate::handoff::serve_http1(stream, service, closing).await;
        });
    });
    let _ = cell.set(Arc::downgrade(&door));
    door
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

#[cfg(test)]
mod tests {
    use super::*;

    /// A station of its own in a temporary data directory, gone with the test.
    struct Rig {
        dir: PathBuf,
        app: Arc<App>,
    }

    impl Rig {
        async fn start(name: &str, config: Value) -> Rig {
            let dir = std::env::temp_dir().join(format!("stillfail-server-{name}-{}", std::process::id()));
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(dir.join("mesh")).unwrap();
            let mut config = config;
            // Any free port for the MCP endpoint: not a real station's 4750.
            config["http"] = json!({ "host": "127.0.0.1", "port": 0 });
            std::fs::write(dir.join("config.json"), config.to_string()).unwrap();
            let options = AppOptions { data: dir.clone(), config: dir.join("config.json"), ui: dir.join("app").join("dist").join("admin"), handoff: None };
            let app = App::start(options).await.unwrap();
            Rig { dir, app }
        }

        fn enroll(&self, removed_at: Option<u64>) {
            let mut state = json!({ "origin": "https://app.still.fail", "station": "s1", "workspace": "w1", "workspace_name": "Dev", "name": "mac", "relay_url": "https://app.still.fail", "grant_keys": {} });
            if let Some(at) = removed_at {
                (state["removed_at"], state["removed_code"]) = (json!(at), json!(4004));
            }
            std::fs::write(self.dir.join("mesh").join("cloud.json"), state.to_string()).unwrap();
        }

        /// Waits for the station to see its cloud.json (looked at every couple of seconds).
        async fn until_bound(&self, bound: bool) {
            for _ in 0..300 {
                if self.app.bound() == bound && self.app.hub.holds(Hold::Unbound) != bound {
                    return;
                }
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
            panic!("never bound = {bound}");
        }
    }

    impl Drop for Rig {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.dir);
        }
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn a_station_in_no_workspace_connects_nothing_and_holds_its_turns() {
        let connect = json!({ "id": "ds", "bind": { "runtime": "claude" }, "slack": { "appToken": "xapp-test", "botToken": "xoxb-test" } });
        let r = Rig::start("unbound", json!({ "connects": [connect] })).await;
        assert!(!r.app.bound());
        assert!(r.app.hub.holds(Hold::Unbound), "no turn starts");
        assert!(r.app.connections.ids().is_empty(), "its connect stays disconnected");
        assert_eq!(r.app.mesh.status().state, "off");
        r.app.shutdown().await;
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn joining_a_workspace_binds_it_removal_unbinds_it_and_being_taken_back_binds_it_again() {
        let r = Rig::start("binding", json!({})).await;
        assert!(!r.app.bound());
        r.enroll(None);
        r.until_bound(true).await;
        assert_eq!(r.app.mesh.status().state, "running");
        // A drain meanwhile does not undo the removal's hold, nor the other way round.
        r.enroll(Some(1_790_000_000));
        r.until_bound(false).await;
        let status = r.app.mesh.status();
        assert_eq!((status.state.as_str(), status.removed_at, status.bound(), status.serves("w1")), ("removed", Some(1_790_000_000), false, false));
        r.app.hold();
        r.app.release();
        assert!(r.app.hub.holds(Hold::Unbound));
        r.enroll(None);
        r.until_bound(true).await;
        assert!(r.app.mesh.status().serves("w1"));
        r.app.shutdown().await;
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn a_station_removed_before_it_started_stays_unbound_through_the_restart() {
        let r = Rig::start("removed-before", json!({})).await;
        r.enroll(Some(1_790_000_000));
        r.app.shutdown().await;
        let options = AppOptions { data: r.dir.clone(), config: r.dir.join("config.json"), ui: r.dir.join("app").join("dist").join("admin"), handoff: None };
        let again = App::start(options).await.unwrap();
        assert!(!again.bound());
        assert!(again.hub.holds(Hold::Unbound));
        assert_eq!(again.mesh.status().state, "removed");
        again.shutdown().await;
    }

    /// One tool call to the station's MCP endpoint as session s1: the tool's text, and whether it is an error.
    async fn call(app: &App, name: &str, args: Value) -> (String, bool) {
        let url = crate::session::SessionDeps::mcp_url(&*app.hub);
        let body = json!({ "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": { "name": name, "arguments": args } });
        let client = reqwest::Client::builder().no_proxy().build().unwrap();
        let reply: Value = client.post(url).bearer_auth("tok-s1").json(&body).send().await.unwrap().json().await.unwrap();
        let result = &reply["result"];
        (result["content"][0]["text"].as_str().unwrap_or_default().to_string(), result["isError"] == json!(true))
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn out_of_its_workspace_the_agents_tools_that_reach_out_are_refused() {
        let r = Rig::start("mcp-gate", json!({})).await;
        let db = Store::open(&r.dir.join(DB_FILE).to_string_lossy(), None).unwrap();
        let work = r.dir.join("work");
        std::fs::create_dir_all(&work).unwrap();
        db.insert_session(&crate::store::NewSession { key: "s1".into(), connect: "c".into(), runtime: "claude".into(), profile: "p".into(), workspace: work.to_string_lossy().into(), token: "tok-s1".into(), ..Default::default() }).unwrap();
        let refused = |(text, error): (String, bool)| error && text == crate::mcp::UNBOUND_REFUSAL;
        // Never joined one.
        assert!(refused(call(&r.app, "chat_post", json!({ "to": "EMBER/1.0", "text": "hi" })).await));
        assert!(refused(call(&r.app, "job_start", json!({ "name": "x", "command": "true" })).await));
        assert!(refused(call(&r.app, "slack_api", json!({ "method": "auth.test" })).await));
        let (listed, error) = call(&r.app, "chat_list", json!({})).await;
        assert!(!error, "reads stay open: {listed}");
        r.enroll(None);
        r.until_bound(true).await;
        let (text, _) = call(&r.app, "chat_post", json!({ "to": "EMBER/1.0", "text": "hi" })).await;
        assert!(text.contains("not a conversation of this session"), "in a workspace it runs: {text}");
        // Removed: refused at once, before the station has even seen its cloud.json change.
        r.enroll(Some(1_790_000_000));
        assert!(refused(call(&r.app, "chat_post", json!({ "to": "EMBER/1.0", "text": "hi" })).await));
        r.until_bound(false).await;
        assert!(refused(call(&r.app, "chat_post", json!({ "to": "EMBER/1.0", "text": "hi" })).await));
        assert!(refused(call(&r.app, "job_start", json!({ "name": "x", "command": "true" })).await));
        assert!(db.list_jobs(None).map(|jobs| jobs.is_empty()).unwrap_or(true), "no job started");
        let (state, error) = call(&r.app, "chat_state", json!({ "kind": "final" })).await;
        assert!(!error, "{state}");
        r.app.shutdown().await;
    }

    /// Removed while it was down (or it crashed between the removal and stopping its jobs): the next start finds the
    /// mark and ends the jobs and services the last one left running, rather than leaving them on unwatched.
    #[tokio::test(flavor = "multi_thread")]
    async fn a_station_starting_removed_stops_the_jobs_left_running_from_before() {
        let r = Rig::start("removed-jobs", json!({})).await;
        r.enroll(None);
        r.until_bound(true).await;
        let work = r.dir.join("work");
        std::fs::create_dir_all(&work).unwrap();
        let job = r.app.jobs.start("s1", "long", "sleep 60", &work, None, crate::jobs::Watch::default()).unwrap();
        let service = r.app.jobs.start("s1", "web", "sleep 60", &work, Some(47993), crate::jobs::Watch::default()).unwrap();
        r.app.shutdown().await;
        let db = Store::open(&r.dir.join(DB_FILE).to_string_lossy(), None).unwrap();
        let pgids: Vec<i32> = [&job.id, &service.id].iter().map(|id| db.get_job(id).unwrap().unwrap().pgid.unwrap() as i32).collect();
        assert!(pgids.iter().all(|p| crate::runtime::process::group_alive(*p)), "a stop of the station leaves them running");
        r.enroll(Some(1_790_000_000));
        let options = AppOptions { data: r.dir.clone(), config: r.dir.join("config.json"), ui: r.dir.join("app").join("dist").join("admin"), handoff: None };
        let again = App::start(options).await.unwrap();
        assert!(!again.bound());
        for (id, pgid) in [&job.id, &service.id].into_iter().zip(&pgids) {
            let row = db.get_job(id).unwrap().unwrap();
            assert_eq!(row.state, "stopped", "{id}");
            assert!(!crate::runtime::process::group_alive(*pgid), "{id}'s group is ended");
            let log = std::fs::read_to_string(&row.log).unwrap();
            assert!(log.ends_with("[still.fail] stopped: the station was removed from its workspace (Dev)\n"), "{log}");
        }
        assert!(db.list_processes().unwrap().iter().all(|p| p.runtime != "job"), "their groups are off the record");
        again.shutdown().await;
    }
}
