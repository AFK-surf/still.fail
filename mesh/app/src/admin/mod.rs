//! The admin API behind /admin/api. Who asks is decided before it gets here: the station verifies people coming
//! through ember cloud, and the local server lets this machine in and checks Cloudflare Access for the tunnel
//! (access.rs).
//!
//! Clients follow GET /events instead of asking again on a timer: every change to what the API shows is announced
//! there (see docs/station-storage.md).

mod edits;
mod events;
mod files;
mod slack;
mod views;

use std::collections::{HashMap, HashSet};
use std::convert::Infallible;
use std::sync::{Arc, Mutex, Weak};

use anyhow::Result;
use bytes::Bytes;
use futures_util::future::BoxFuture;
use http_body_util::combinators::UnsyncBoxBody;
use http_body_util::{BodyExt, Full};
use hyper::{Request, Response};
use serde_json::{Map, Value, json};
use tokio::sync::watch;
use tracing::{error, info, warn};

use crate::access::Viewer;
use crate::chat::slack_apps::SlackApps;
use crate::config::{Config, Profile};
use crate::connections::Connections;
use crate::hub::{Hub, NewChat, SessionChange};
use crate::login::LoginManager;
use crate::machine_logins::MachineLogins;
use crate::machine_sessions::MachineRoots;
use crate::profiles::{ProfileCheck, ProfileQuota};
use crate::settings::Settings;
use crate::store::Store;

pub use events::Events;

/// What a response carries: a whole body, or one that streams (events, files, previews).
pub type Body = UnsyncBoxBody<Bytes, std::io::Error>;

/// This station's link to ember cloud, as the pages show it.
#[derive(serde::Serialize, Debug, Clone, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct MeshStatus {
    /// off: not in a workspace; running: in one, reachable through ember cloud while this station runs.
    pub state: String,
    pub origin: Option<String>,
    pub station: Option<String>,
    /// The workspace's name, as it was when the station joined.
    pub workspace: Option<String>,
    pub workspace_id: Option<String>,
    pub name: Option<String>,
}

/// The station's side of ember cloud, for the pages: its state, and when it changes.
pub trait Mesh: Send + Sync {
    fn status(&self) -> MeshStatus;
    fn changes(&self) -> watch::Receiver<u64>;
}

/// What a profile check is asked with (profiles::CheckOptions, owned).
#[derive(Debug, Clone)]
pub struct CheckRequest {
    pub profile: Profile,
    /// Where it signs in: its home, or a trial one for a key being tried.
    pub home: std::path::PathBuf,
}

/// What the pages need of Slack beyond a connect's own connection: its app API with the viewer's configuration token,
/// an install's code exchanged, and tokens checked. The real one is `SlackOnline`; tests give their own.
#[async_trait::async_trait]
pub trait SlackService: Send + Sync {
    fn configured(&self, by: &str) -> bool;
    async fn export_manifest(&self, by: &str, app_id: &str) -> Result<Value>;
    /// Whether Slack wants permissions approved again.
    async fn update_manifest(&self, by: &str, app_id: &str, manifest: &Value) -> Result<bool>;
    async fn create_app(&self, by: &str, team: &str, manifest: &Value) -> Result<crate::chat::slack_apps::CreatedApp>;
    async fn set_icon(&self, by: &str, app_id: &str, picture: Vec<u8>, mime: &str) -> Result<()>;
    /// An install's code, for its bot token and its workspace's name.
    async fn exchange_install_code(&self, client_id: &str, client_secret: &str, code: &str, redirect_uri: &str) -> Result<(String, Option<String>)>;
    async fn verify_tokens(&self, app_token: &str, bot_token: &str) -> (Option<crate::chat::slack::SlackIdentity>, Vec<String>);
}

/// Slack itself: the app API with the configured tokens, and its Web API.
pub struct SlackOnline(pub SlackApps);

#[async_trait::async_trait]
impl SlackService for SlackOnline {
    fn configured(&self, by: &str) -> bool {
        self.0.configured(by)
    }
    async fn export_manifest(&self, by: &str, app_id: &str) -> Result<Value> {
        self.0.export_manifest(by, app_id).await
    }
    async fn update_manifest(&self, by: &str, app_id: &str, manifest: &Value) -> Result<bool> {
        self.0.update_manifest(by, app_id, manifest).await
    }
    async fn create_app(&self, by: &str, team: &str, manifest: &Value) -> Result<crate::chat::slack_apps::CreatedApp> {
        self.0.create_app(by, team, manifest).await
    }
    async fn set_icon(&self, by: &str, app_id: &str, picture: Vec<u8>, mime: &str) -> Result<()> {
        self.0.set_icon(by, app_id, picture, mime).await
    }
    async fn exchange_install_code(&self, client_id: &str, client_secret: &str, code: &str, redirect_uri: &str) -> Result<(String, Option<String>)> {
        crate::chat::slack_apps::exchange_install_code(client_id, client_secret, code, redirect_uri).await
    }
    async fn verify_tokens(&self, app_token: &str, bot_token: &str) -> (Option<crate::chat::slack::SlackIdentity>, Vec<String>) {
        crate::chat::slack::verify_slack_tokens(app_token, bot_token).await
    }
}

pub type CheckFn = Arc<dyn Fn(CheckRequest) -> BoxFuture<'static, ProfileCheck> + Send + Sync>;
pub type QuotaFn = Arc<dyn Fn(Profile) -> BoxFuture<'static, ProfileQuota> + Send + Sync>;
pub type ModelsFn = Arc<dyn Fn(Profile) -> BoxFuture<'static, Result<Vec<String>>> + Send + Sync>;

pub struct AdminDeps {
    pub settings: Arc<Settings>,
    pub store: Arc<Store>,
    pub hub: Arc<Hub>,
    pub connections: Arc<Connections>,
    pub logins: Arc<LoginManager>,
    /// Display names of people seen through ember cloud, by email; shared with the station's own chat.
    pub names: Arc<Mutex<HashMap<String, String>>>,
    pub mesh: Option<Arc<dyn Mesh>>,
    /// A profile's allowance; None where nobody can ask (tests).
    pub quota: Option<QuotaFn>,
    /// How a profile is checked; tests replace it so no real CLI runs.
    pub check_profile: CheckFn,
    /// The models a ChatGPT subscription runs in Codex (its app-server's list); its sign-in check does not say.
    pub codex_models: Option<ModelsFn>,
    /// Slack's app API and Web API as the pages need them; defaults to Slack itself with the configuration tokens in
    /// the config.
    pub slack_apps: Option<Arc<dyn SlackService>>,
    /// Check every profile shortly after start (the real station; tests leave it off).
    pub check_on_start: bool,
    /// Who this machine's own Claude Code and Codex are signed in as, for the pages to say.
    pub machine_logins: Option<Arc<MachineLogins>>,
    /// Development only (EMBER_DEV=1): POST /dev/inject.
    pub dev: bool,
    /// Background jobs, for the pages to stop one; None where there are none (tests).
    pub jobs: Option<Arc<crate::jobs::Jobs>>,
}

/// An error that is the asker's: its status and what to tell them.
#[derive(Debug, thiserror::Error)]
#[error("{message}")]
pub struct HttpError {
    pub status: u16,
    pub message: String,
}

pub fn http_error(status: u16, message: impl Into<String>) -> anyhow::Error {
    HttpError { status, message: message.into() }.into()
}

/// A sign-in with no profile yet: its runtime, its home while signing in, who started it, what it made.
struct Pending {
    runtime: ember_shapes::RuntimeKind,
    home: std::path::PathBuf,
    by: Viewer,
    created: Option<String>,
}

pub struct AdminApi {
    deps: AdminDeps,
    apps: Arc<dyn SlackService>,
    checks: Arc<Mutex<HashMap<String, ProfileCheck>>>,
    quotas: Arc<Mutex<HashMap<String, ProfileQuota>>>,
    quota_pending: Mutex<HashSet<String>>,
    app_ids: Mutex<HashMap<String, String>>,
    pending: Mutex<HashMap<String, Pending>>,
    events: Arc<Events>,
    me: Weak<AdminApi>,
}

/// A request's body, read whole: JSON objects only, up to a megabyte.
pub struct Input(pub Map<String, Value>);

impl Input {
    pub fn get(&self, key: &str) -> Option<&Value> {
        self.0.get(key)
    }
    /// A string field, as given (None when absent or not a string).
    pub fn str(&self, key: &str) -> Option<&str> {
        self.0.get(key).and_then(Value::as_str)
    }
    /// JavaScript's String(x ?? "").
    pub fn text(&self, key: &str) -> String {
        match self.0.get(key) {
            None | Some(Value::Null) => String::new(),
            Some(Value::String(s)) => s.clone(),
            Some(other) => other.to_string(),
        }
    }
    pub fn has(&self, key: &str) -> bool {
        self.0.contains_key(key)
    }
}

/// What routes are asked with.
pub struct Asked {
    pub method: String,
    /// After /admin/api.
    pub path: String,
    pub query: Vec<(String, String)>,
    /// The query as asked: "?…", or empty.
    pub search: String,
    pub headers: Vec<(String, String)>,
}

impl Asked {
    pub fn param(&self, name: &str) -> Option<&str> {
        self.query.iter().find(|(k, _)| k == name).map(|(_, v)| v.as_str())
    }
    pub fn params(&self, name: &str) -> Vec<&str> {
        self.query.iter().filter(|(k, _)| k == name).map(|(_, v)| v.as_str()).collect()
    }
}

pub fn json_response(status: u16, value: &Value) -> Response<Body> {
    let text = value.to_string();
    Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .header("cache-control", "no-store")
        .header("content-length", text.len())
        .body(full(text))
        .expect("a response")
}

pub fn full(bytes: impl Into<Bytes>) -> Body {
    Full::new(bytes.into()).map_err(|never: Infallible| match never {}).boxed_unsync()
}

pub(crate) fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        let hex = bytes.get(i + 1..i + 3).and_then(|h| std::str::from_utf8(h).ok()).and_then(|h| u8::from_str_radix(h, 16).ok());
        match (bytes[i], hex) {
            (b'%', Some(b)) => {
                out.push(b);
                i += 3;
            }
            (b'+', _) => {
                out.push(b' ');
                i += 1;
            }
            (b, _) => {
                out.push(b);
                i += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// A path segment: `+` stays itself there (decodeURIComponent).
fn segment_decode(s: &str) -> String {
    percent_decode(&s.replace('+', "%2B"))
}

pub fn query_pairs(query: &str) -> Vec<(String, String)> {
    query
        .split('&')
        .filter(|p| !p.is_empty())
        .map(|p| {
            let (k, v) = p.split_once('=').unwrap_or((p, ""));
            (percent_decode(k), percent_decode(v))
        })
        .collect()
}

/// Masks a secret for the pages: its first five and last four characters.
pub fn mask(value: &str) -> String {
    if value.is_empty() {
        return String::new();
    }
    let chars: Vec<char> = value.chars().collect();
    if chars.len() <= 8 {
        return "••••".into();
    }
    format!("{}…{}", chars[..5].iter().collect::<String>(), chars[chars.len() - 4..].iter().collect::<String>())
}

impl AdminApi {
    pub fn new(deps: AdminDeps) -> Arc<AdminApi> {
        let apps = deps.slack_apps.clone().unwrap_or_else(|| {
            let (load, save) = (deps.settings.clone(), deps.settings.clone());
            Arc::new(SlackOnline(SlackApps::new(
                Arc::new(move || load.config().slack_config_tokens.clone()),
                Arc::new(move |token| {
                    if let Err(e) = save.update(|raw| {
                        raw.slack_config_tokens = Some(slack::upsert_token(raw.slack_config_tokens.take().unwrap_or_default(), token));
                        Ok(())
                    }) {
                        warn!(error = %e, "slack configuration token not saved");
                    }
                }),
            )))
        });
        let api = Arc::new_cyclic(|me: &Weak<AdminApi>| AdminApi {
            apps,
            checks: Arc::default(),
            quotas: Arc::default(),
            quota_pending: Mutex::default(),
            app_ids: Mutex::default(),
            pending: Mutex::default(),
            events: Events::new(me.clone()),
            me: me.clone(),
            deps,
        });
        // What the last run learned about profiles shows until they are checked again.
        if let Ok(status) = api.deps.store.profile_status() {
            for (id, s) in status {
                if let Some(check) = s.check.and_then(|c| serde_json::from_value(c).ok()) {
                    api.checks.lock().unwrap().insert(id.clone(), check);
                }
                if let Some(quota) = s.quota.and_then(|q| serde_json::from_value(q).ok()) {
                    api.quotas.lock().unwrap().insert(id, quota);
                }
            }
        }
        // The account pool picks profiles by what their checks and allowances say.
        let (checks, quotas) = (api.checks.clone(), api.quotas.clone());
        api.deps.hub.set_profile_health(Arc::new(move |id| crate::pool::ProfileHealth {
            check: checks.lock().unwrap().get(id).cloned(),
            quota: quotas.lock().unwrap().get(id).cloned(),
        }));
        if api.deps.check_on_start {
            let me = api.me.clone();
            tokio::spawn(async move {
                tokio::time::sleep(std::time::Duration::from_secs(3)).await;
                let Some(api) = me.upgrade() else { return };
                for p in api.config().profiles.iter() {
                    let (api, id) = (api.clone(), p.id.clone());
                    tokio::spawn(async move {
                        if let Err(e) = api.check(&id).await {
                            warn!(profile = id, error = %e, "profile check failed");
                        }
                    });
                }
            });
        }
        api.events.follow();
        api
    }

    fn config(&self) -> Arc<Config> {
        self.deps.settings.config()
    }

    /// Answers one request under /admin/api for `viewer`. `path` is what follows /admin/api.
    pub async fn handle<B>(&self, req: Request<B>, viewer: Viewer) -> Response<Body>
    where
        B: hyper::body::Body<Data = Bytes> + Send + Unpin + 'static,
        B::Error: std::error::Error + Send + Sync + 'static,
    {
        let started = std::time::Instant::now();
        let (parts, body) = req.into_parts();
        let path = parts.uri.path().strip_prefix("/admin/api").unwrap_or(parts.uri.path()).to_string();
        let asked = Asked {
            method: parts.method.as_str().to_string(),
            query: query_pairs(parts.uri.query().unwrap_or("")),
            search: parts.uri.query().map(|q| format!("?{q}")).unwrap_or_default(),
            headers: parts.headers.iter().map(|(k, v)| (k.as_str().to_string(), v.to_str().unwrap_or("").to_string())).collect(),
            path,
        };
        if let Viewer::Mesh { email, name, .. } = &viewer {
            if !name.is_empty() {
                self.deps.names.lock().unwrap().insert(email.clone(), name.clone());
            }
        }
        let who = match &viewer {
            Viewer::Local => "local",
            Viewer::Access { .. } => "access",
            Viewer::Mesh { .. } => "mesh",
        };
        let response = match self.route(&asked, body, &viewer).await {
            Ok(response) => response,
            Err(e) => {
                let status = e.downcast_ref::<HttpError>().map(|h| h.status).unwrap_or(500);
                if status == 500 {
                    error!(path = asked.path, error = %format!("{e:#}"), "admin request failed");
                }
                json_response(status, &json!({ "error": e.to_string() }))
            }
        };
        let query = if parts.uri.query().is_some() { format!("?{}", parts.uri.query().unwrap_or("")) } else { String::new() };
        info!(method = asked.method, path = format!("{}{query}", asked.path), status = response.status().as_u16(), ms = started.elapsed().as_millis() as u64, via = who, "admin request");
        response
    }

    async fn route<B>(&self, asked: &Asked, body: B, viewer: &Viewer) -> Result<Response<Body>>
    where
        B: hyper::body::Body<Data = Bytes> + Send + Unpin + 'static,
        B::Error: std::error::Error + Send + Sync + 'static,
    {
        let method = asked.method.as_str();
        let path = asked.path.as_str();
        let parts: Vec<String> = path.split('/').filter(|p| !p.is_empty()).map(segment_decode).collect();
        let part = |i: usize| parts.get(i).map(String::as_str);
        let (resource, id, action) = (part(0), part(1), part(2));
        let ok = |value: Value| Ok(json_response(200, &value));
        let me = self.me.upgrade().ok_or_else(|| anyhow::anyhow!("the station is stopping"))?;

        if let Some((port, target)) = crate::preview::preview_target(path) {
            return files::preview(asked, body, port, &target).await;
        }
        match (method, path) {
            ("GET", "/host") => return ok(serde_json::to_value(crate::host::host_info(&self.config().data_dir).await)?),
            ("GET", "/overview") => return ok(self.overview(viewer)),
            ("GET", "/events") => {
                // `live=<key>&from=<n>&last=<m>`, repeated: those sessions as they run, on this same stream (from
                // entry `n`, but no more than the last `m` of the transcript; `last=0`: all of it).
                let froms = asked.params("from");
                let lasts = asked.params("last");
                let live = asked
                    .params("live")
                    .into_iter()
                    .enumerate()
                    .filter(|(_, key)| matches!(self.deps.store.get_session(key), Ok(Some(_))))
                    .map(|(i, key)| {
                        let from = froms.get(i).and_then(|f| f.parse::<f64>().ok()).map(|f| f.max(0.0) as usize).unwrap_or(0);
                        let last = lasts.get(i).and_then(|l| l.parse::<usize>().ok()).filter(|l| *l > 0);
                        (key.to_string(), from, last)
                    })
                    .collect();
                return Ok(self.events.open(viewer.clone(), asked.param("host") == Some("1"), live));
            }
            ("GET", "/sessions") => return ok(Value::Array(self.sessions(asked.param("connect"), asked.param("archived") == Some("1"))?)),
            ("POST", "/sessions") => {
                // A new chat: its session and its thread are made first, so files can be uploaded into it before the
                // first message.
                let input = read_json(body).await?;
                let runtime = match input.text("runtime").as_str() {
                    "claude" => ember_shapes::RuntimeKind::Claude,
                    "codex" => ember_shapes::RuntimeKind::Codex,
                    _ => return Err(http_error(400, "runtime 必须是 claude 或 codex")),
                };
                let given = |k: &str| input.str(k).filter(|s| !s.is_empty()).map(String::from);
                let chat = NewChat {
                    runtime,
                    profile: given("profile"),
                    model: given("model"),
                    effort: given("effort"),
                    title: input.str("title").map(|t| t.chars().take(120).collect()),
                    created_by: viewer.id(),
                };
                let (key, thread) = self.deps.hub.new_session(chat).map_err(|e| http_error(400, e.to_string()))?;
                return ok(json!({ "key": key, "thread": self.thread(thread.id, viewer)? }));
            }
            // Sessions this machine's own Claude Code and Codex kept (in a terminal), to go on with one in a chat.
            ("GET", "/machine-sessions") => {
                let roots = MachineRoots::of(&crate::machine_logins::process_env());
                let mut found = tokio::task::spawn_blocking(move || crate::machine_sessions::list(&roots, 100)).await?;
                let going: HashMap<(String, String), String> = self
                    .deps
                    .store
                    .list_sessions()?
                    .into_iter()
                    .filter_map(|r| Some(((r.runtime.clone(), r.runtime_session_id.clone()?), r.key)))
                    .collect();
                for s in &mut found {
                    s.session = going.get(&(crate::config::runtime_name(s.runtime).to_string(), s.id.clone())).cloned();
                }
                return ok(json!({ "sessions": found }));
            }
            ("POST", "/machine-sessions") => {
                let input = read_json(body).await?;
                let runtime = match input.text("runtime").as_str() {
                    "claude" => ember_shapes::RuntimeKind::Claude,
                    "codex" => ember_shapes::RuntimeKind::Codex,
                    _ => return Err(http_error(400, "runtime 必须是 claude 或 codex")),
                };
                let id = input.text("id");
                let roots = MachineRoots::of(&crate::machine_logins::process_env());
                let found = {
                    let (roots, id) = (roots.clone(), id.clone());
                    tokio::task::spawn_blocking(move || crate::machine_sessions::find(&roots, runtime, &id)).await?
                };
                let found = found.ok_or_else(|| http_error(404, format!("本机没有这个会话：{id}")))?;
                // A long transcript takes a moment to copy and read.
                let (hub, by) = (self.deps.hub.clone(), viewer.id());
                let (key, thread) = tokio::task::spawn_blocking(move || hub.continue_machine_session(&roots, &found, &by)).await?.map_err(|e| http_error(400, e.to_string()))?;
                info!(session = key, from = id, by = viewer.id(), "machine session continued from the admin page");
                return ok(json!({ "key": key, "thread": self.thread(thread.id, viewer)? }));
            }
            ("GET", "/chats") => return ok(Value::Array(self.chats(viewer, asked.param("archived") == Some("1"))?)),
            ("GET", "/threads") => return ok(Value::Array(self.threads(viewer, asked.param("session"))?)),
            // The services and jobs still up on this station, across its chats (the sidebar keeps those left open a long while in view).
            ("GET", "/jobs") => return ok(Value::Array(self.open_jobs(viewer)?)),
            ("POST", "/threads") => {
                // Another chat on the pages with a session in it.
                let input = read_json(body).await?;
                let session = input.text("session");
                self.session_row(&session)?;
                let title = input.str("title").map(str::trim).filter(|t| !t.is_empty()).map(|t| t.chars().take(80).collect::<String>());
                let thread = self.deps.hub.open_chat(&session, &viewer.id(), title.as_deref())?;
                return ok(self.thread(thread.id, viewer)?);
            }
            ("POST", "/connects") => return ok(me.new_slack_connect(&read_json(body).await?, viewer).await?),
            ("POST", "/slack/apps") => return ok(self.make_slack_app(&read_json(body).await?, viewer).await?),
            ("POST", "/slack/installs") => return ok(self.installed(&read_json(body).await?).await?),
            ("POST", "/uploads") => {
                // Files wait here, in no chat, until a message takes them into its chat (attachments): choosing a file
                // for a new chat makes nothing.
                let dir = self.staged();
                files::sweep_staged(&dir).await;
                return ok(serde_json::to_value(files::save_upload(body, &dir, asked.param("name").unwrap_or("file")).await?)?);
            }
            ("POST", "/profiles/machine") => return ok(me.new_machine_profile(&read_json(body).await?, viewer).await?),
            ("POST", "/profiles") => return ok(me.new_keyed_profile(&read_json(body).await?, viewer).await?),
            ("POST", "/logins") => return ok(self.new_login(&read_json(body).await?, viewer)?),
            ("POST", "/slack/verify") => return ok(self.verify_slack(&read_json(body).await?).await),
            ("POST", "/dev/inject") if self.deps.dev && matches!(viewer, Viewer::Local) => {
                // Hand the station a chat message as if the connect had received it.
                let input = read_json(body).await?;
                let ts = input.text("ts");
                let message = crate::chat::InboundMessage {
                    channel: input.text("channel"),
                    thread_ts: input.str("threadTs").map(String::from).unwrap_or_else(|| ts.clone()),
                    ts,
                    user: input.text("user"),
                    text: input.text("text"),
                    addressed: input.get("addressed") != Some(&Value::Bool(false)),
                };
                self.deps.hub.accept(&input.text("connect"), message).await?;
                return ok(json!({ "ok": true }));
            }
            ("POST", "/slack/config-tokens") => return ok(self.add_config_token(&read_json(body).await?, viewer).await?),
            ("GET", "/slack/people") => return ok(self.slack_people().await),
            // The agents' memory, for the pages to show (the agents write it): the global one, and the shared skills (projects'
            // memories among them).
            ("GET", "/memory") => {
                let home = self.config().agent_home.clone();
                let path = crate::agent_home::agent_home_paths(&home).0;
                let text = std::fs::read_to_string(&path).unwrap_or_default();
                return ok(json!({ "global": { "path": path.to_string_lossy(), "text": text }, "skills": crate::agent_home::list_skills(&home) }));
            }
            ("GET", "/slack/create-app-url") => {
                let name = asked.param("name").map(str::trim).filter(|n| !n.is_empty()).ok_or_else(|| http_error(400, "name is required"))?;
                return ok(json!({ "url": crate::chat::slack_apps::create_app_url(name) }));
            }
            _ => {}
        }

        match (resource, id, action, method) {
            // One of the machine's sessions, to look at before going on with it: what was said, the latest `limit`.
            (Some("machine-sessions"), Some(runtime), Some(session), "GET") => {
                let runtime = crate::config::runtime_named(runtime).ok_or_else(|| http_error(404, format!("no runtime {runtime}")))?;
                let limit = asked.param("limit").and_then(|l| l.parse::<usize>().ok()).unwrap_or(200).clamp(1, 1000);
                let roots = MachineRoots::of(&crate::machine_logins::process_env());
                let id = session.to_string();
                let (found, said) = tokio::task::spawn_blocking(move || {
                    let found = crate::machine_sessions::find(&roots, runtime, &id)?;
                    let said = crate::machine_sessions::conversation(runtime, &found.path);
                    Some((found, said))
                })
                .await?
                .ok_or_else(|| http_error(404, format!("本机没有这个会话：{session}")))?;
                let mut found = found;
                let name = crate::config::runtime_name(runtime);
                found.session = self.deps.store.list_sessions()?.into_iter().find(|r| r.runtime == name && r.runtime_session_id.as_deref() == Some(found.id.as_str())).map(|r| r.key);
                let total = said.len();
                return ok(json!({ "session": found, "total": total, "said": &said[total.saturating_sub(limit)..] }));
            }
            (Some("sessions"), Some(key), None, "GET") => return ok(self.session(key, viewer)?),
            // Transcript entries before those a page was sent (`/events`' `last`): up to `limit` before entry `before`.
            (Some("sessions"), Some(key), Some("timeline"), "GET") => {
                self.session_row(key)?;
                let before = asked.param("before").and_then(|b| b.parse::<usize>().ok()).unwrap_or(0);
                let limit = asked.param("limit").and_then(|l| l.parse::<usize>().ok()).unwrap_or(200).clamp(1, 1000);
                let (live, key) = (self.deps.hub.live.clone(), key.to_string());
                let (start, entries) = tokio::task::spawn_blocking(move || live.before(&key, before, limit)).await?.unwrap_or((0, vec![]));
                return ok(json!({ "start": start, "entries": entries }));
            }
            // A background job's last output, for the pages (`lines`, default 200).
            (Some("jobs"), Some(id), Some("log"), "GET") => {
                let job = self.deps.store.get_job(id)?.ok_or_else(|| http_error(404, format!("no job {id}")))?;
                let lines = asked.param("lines").and_then(|l| l.parse::<usize>().ok()).unwrap_or(200).clamp(1, 1000);
                let log = std::path::Path::new(&job.log);
                return ok(json!({ "text": crate::jobs::tail(log, lines), "outputAt": crate::jobs::output_at(log) }));
            }
            // A background job (a web service's own page finds its port by it).
            (Some("jobs"), Some(id), None, "GET") => return ok(crate::jobs::shown(&self.deps.store, &self.deps.store.get_job(id)?.ok_or_else(|| http_error(404, format!("no job {id}")))?)),
            // A background job stopped from the pages, as its agent's job_stop does.
            (Some("jobs"), Some(id), Some("stop"), "POST") => {
                let jobs = self.deps.jobs.clone().ok_or_else(|| http_error(404, "no jobs here".to_string()))?;
                let job = jobs.stop_for(id, &viewer.id()).await?;
                info!(job = id, by = viewer.id(), "job stopped from the admin page");
                return ok(crate::jobs::shown(&self.deps.store, &job));
            }
            (Some("sessions"), Some(key), None, "DELETE") => {
                self.session_row(key)?;
                self.deps.hub.delete_session(key).await?;
                info!(session = key, by = viewer.id(), "session deleted from the admin page");
                return ok(json!({ "ok": true }));
            }
            (Some("sessions"), Some(key), Some("archive"), "POST" | "DELETE") => {
                self.session_row(key)?;
                self.deps.hub.archive(key, method == "POST")?;
                return ok(self.summary(key)?);
            }
            (Some("sessions"), Some(key), Some("stop"), "POST") => {
                self.deps.hub.stop(key).await?;
                return ok(json!({ "ok": true }));
            }
            (Some("sessions"), Some(key), Some("evict"), "POST") => {
                self.deps.hub.evict(key).await;
                return ok(json!({ "ok": true }));
            }
            (Some("sessions"), Some(key), Some("warm"), "POST") => {
                if self.deps.store.get_session(key)?.is_none() {
                    return Err(http_error(404, format!("unknown session {key}")));
                }
                let (hub, key) = (self.deps.hub.clone(), key.to_string());
                tokio::spawn(async move {
                    if let Err(e) = hub.warm(&key).await {
                        warn!(session = key, error = %e, "warming failed");
                    }
                });
                return Ok(json_response(202, &json!({ "ok": true })));
            }
            (Some("sessions"), Some(key), Some("files"), "GET") => return self.session_file(key, asked.param("name").unwrap_or(""), asked.param("thumb") == Some("1")).await,
            (Some("sessions"), Some(key), Some("settings"), "POST") => {
                // How the session runs from its next turn on: its profile, model, effort (Hub::configure).
                let input = read_json(body).await?;
                let pick = |name: &str| match input.get(name) {
                    None => None,
                    Some(Value::Null) => Some(None),
                    Some(Value::String(s)) => Some(Some(s.clone())),
                    Some(other) => Some(Some(other.to_string())),
                };
                // A profile's id keeps the session to it; null gives the choice back to the station.
                let profile = match input.get("profile") {
                    Some(Value::String(s)) => Some(Some(s.clone())),
                    Some(Value::Null) => Some(None),
                    _ => None,
                };
                let change = SessionChange { profile, model: pick("model"), effort: pick("effort") };
                self.deps.hub.configure(key, change).await.map_err(|e| http_error(400, e.to_string()))?;
                return ok(json!({ "ok": true }));
            }
            (Some("sessions"), Some(key), Some("title"), "POST") => {
                let input = read_json(body).await?;
                if self.deps.store.get_session(key)?.is_none() {
                    return Err(http_error(404, format!("unknown session {key}")));
                }
                let title = input.str("title").map(str::trim).filter(|t| !t.is_empty()).map(|t| t.chars().take(80).collect::<String>());
                self.deps.store.set_title(key, title.as_deref())?;
                return ok(json!({ "ok": true }));
            }
            // What a widget in one of the session's messages holds (web/src/Viz.tsx), by its file's path; its
            // modelContent reaches the agent with its next messages (Session::format).
            (Some("sessions"), Some(key), Some("widget-state"), "GET") => {
                self.session_row(key)?;
                let state = self.deps.store.widget_state(key, asked.param("path").unwrap_or(""))?;
                return ok(json!({ "state": state.and_then(|s| serde_json::from_str::<Value>(&s).ok()) }));
            }
            (Some("sessions"), Some(key), Some("widget-state"), "PUT") => {
                let input = read_json(body).await?;
                self.session_row(key)?;
                let path = input.text("path");
                if path.is_empty() {
                    return Err(http_error(400, "path is required"));
                }
                let state = input.get("state").cloned().unwrap_or(Value::Null);
                let json = state.to_string();
                if json.len() > WIDGET_STATE_MAX {
                    return Err(http_error(400, format!("widget state is over {WIDGET_STATE_MAX} bytes")));
                }
                self.deps.store.put_widget_state(key, &path, &json, widget_model(&state).as_deref())?;
                return ok(json!({ "ok": true }));
            }
            // "这是我" / "不是我" on a Slack user's name: taken at the viewer's word.
            (Some("me"), Some("slack"), Some(user), "PUT" | "DELETE") if parts.len() == 3 => {
                self.deps.store.set_slack_identity(&viewer.id(), user, method == "PUT")?;
                return ok(self.overview(viewer));
            }
            (Some("threads"), Some(id), _, _) => {
                let thread_id: i64 = id.parse().map_err(|_| http_error(404, format!("unknown thread {id}")))?;
                let thread = self.deps.store.get_thread(thread_id)?.ok_or_else(|| http_error(404, format!("unknown thread {id}")))?;
                match (action, method) {
                    (None, "GET") => return ok(self.thread(thread_id, viewer)?),
                    (Some("entries"), "GET") => return ok(self.entries(thread_id, asked)?),
                    (Some("messages"), "POST") => {
                        if thread.surface != crate::store::EMBER_SURFACE {
                            return Err(http_error(400, "只能在 ember 自己的对话里发消息"));
                        }
                        let input = read_json(body).await?;
                        let text = input.text("text").trim().to_string();
                        let attachments = self.attachments(thread_id, input.get("attachments"))?;
                        let quotes = files::quotes_of(input.get("quotes"));
                        if text.is_empty() && attachments.is_empty() && quotes.is_empty() {
                            return Err(http_error(400, "消息是空的"));
                        }
                        crate::thumbs::make_later(attachments.iter().map(|a| a.path.clone().into()).collect(), crate::thumbs::dir(&self.config().data_dir));
                        let n = self.deps.hub.say(thread_id, &viewer.id(), &text, attachments, quotes)?;
                        return ok(json!({ "n": n }));
                    }
                    (Some("read"), "PUT") => {
                        let input = read_json(body).await?;
                        let n = input.get("n").and_then(Value::as_f64).filter(|n| n.fract() == 0.0 && *n >= 0.0).ok_or_else(|| http_error(400, "n 必须是整数"))?;
                        let n = self.deps.store.set_read(&viewer.id(), thread_id, n as i64)?;
                        return ok(json!({ "viewer": viewer.id(), "thread": thread_id, "n": n }));
                    }
                    (Some("sessions"), "POST") => {
                        let input = read_json(body).await?;
                        let session = input.text("session");
                        self.session_row(&session)?;
                        self.deps.hub.add_to_thread(thread_id, &session).map_err(|e| http_error(400, e.to_string()))?;
                        return ok(self.thread(thread_id, viewer)?);
                    }
                    // A chat archived or shown again: with its session when it is that session's own (Hub::archive_chat).
                    (Some("archive"), "POST" | "DELETE") => {
                        self.deps.hub.archive_chat(thread_id, method == "POST").map_err(|e| http_error(400, e.to_string()))?;
                        return ok(self.thread(thread_id, viewer)?);
                    }
                    _ => {}
                }
            }
            (Some("slack"), Some("apps"), Some(app), "DELETE") => return ok(self.drop_made_app(app, viewer)?),
            (Some("slack"), Some("config-tokens"), Some(team), "DELETE") => {
                let by = viewer.id();
                return ok(self.save(viewer, "slack configuration token removed", |raw| {
                    raw.slack_config_tokens = Some(raw.slack_config_tokens.take().unwrap_or_default().into_iter().filter(|t| t.by != by || t.team_id != team).collect());
                    Ok(())
                })?);
            }
            (Some("connects"), Some(id), None, "PUT") => return ok(self.put_connect(id, &read_json(body).await?, viewer)?),
            (Some("connects"), Some(id), None, "DELETE") => return ok(self.delete_connect(id, viewer)?),
            (Some("connects"), Some(id), Some("session"), "POST") => {
                let input = read_json(body).await?;
                let target = input.str("session").filter(|s| !s.is_empty());
                let key = self.deps.hub.bind_single(id, target, input.str("title"), Some(&viewer.id()))?;
                info!(connect = id, session = key, by = viewer.id(), "single-session binding changed from the admin page");
                return ok(json!({ "session": key }));
            }
            (Some("connects"), Some(id), Some("reconnect"), "POST") => {
                self.deps.connections.reconcile(&self.config()).await;
                // Who the bot is, read again: a name changed in Slack shows now.
                if let Err(e) = self.deps.connections.refresh_identity(id).await {
                    warn!(connect = id, error = %e, "slack identity refresh failed");
                }
                return ok(json!({ "ok": true }));
            }
            (Some("connects"), Some(id), Some("slack-app"), "GET") => return ok(self.slack_app(id, viewer).await?),
            (Some("connects"), Some(id), Some("slack-app"), "PUT") => return ok(me.put_slack_app(id, &read_json(body).await?, viewer).await?),
            (Some("connects"), Some(id), Some("slack-app"), "POST") => return ok(self.create_slack_app(id, &read_json(body).await?, viewer).await?),
            (Some("profiles"), Some(id), None, "PUT") => {
                let overview = self.put_profile(id, &read_json(body).await?, viewer)?;
                // Its new state is reported once known.
                let (api, id) = (me.clone(), id.to_string());
                tokio::spawn(async move {
                    if let Err(e) = api.check(&id).await {
                        warn!(profile = id, error = %e, "profile check failed");
                    }
                });
                return ok(overview);
            }
            (Some("profiles"), Some(id), None, "DELETE") => return ok(self.delete_profile(id, viewer)?),
            (Some("profiles"), Some(id), Some("check"), "POST") => return ok(serde_json::to_value(me.check(id).await?)?),
            (Some("profiles"), Some(id), Some("quota"), "POST") => return ok(serde_json::to_value(self.refresh_quota(id).await?)?),
            (Some("profiles"), Some(id), Some("login"), _) => {
                let config = self.config();
                let profile = config.profiles.iter().find(|p| p.id == id).ok_or_else(|| http_error(404, format!("unknown profile {id}")))?;
                match method {
                    "GET" => return ok(json!({ "job": self.deps.logins.get(id) })),
                    "DELETE" => {
                        self.deps.logins.cancel(id);
                        return ok(json!({ "job": self.deps.logins.get(id) }));
                    }
                    "POST" => {
                        if profile.access_kind != ember_shapes::AccessKind::Subscription {
                            return Err(http_error(400, "只有订阅账号需要登录"));
                        }
                        if profile.machine {
                            return Err(http_error(400, "这个 Profile 用的是这台机器自己的登录，要在机器上登录"));
                        }
                        info!(profile = id, by = viewer.id(), "login started from the admin page");
                        return ok(json!({ "job": self.deps.logins.start(profile)? }));
                    }
                    _ => {}
                }
            }
            (Some("profiles"), Some(id), Some("login-code"), "POST") => {
                let input = read_json(body).await?;
                let job = self.deps.logins.submit_code(id, &input.text("code")).await.map_err(|e| http_error(400, e.to_string()))?;
                return ok(json!({ "job": job }));
            }
            (Some("logins"), Some(id), _, _) if self.pending.lock().unwrap().contains_key(id) => match (action, method) {
                (None, "DELETE") => {
                    self.drop_login(id);
                    return ok(json!({ "ok": true }));
                }
                (Some("code"), "POST") => {
                    let input = read_json(body).await?;
                    let job = self.deps.logins.submit_code(id, &input.text("code")).await.map_err(|e| http_error(400, e.to_string()))?;
                    return ok(json!({ "job": job }));
                }
                _ => {}
            },
            _ => {}
        }
        Err(http_error(404, format!("no route {method} {path}")))
    }

    fn session_row(&self, key: &str) -> Result<crate::store::SessionRow> {
        self.deps.store.get_session(key)?.ok_or_else(|| http_error(404, format!("unknown session {key}")))
    }
}

/// The most a widget's state takes, as JSON (web/src/Viz.tsx keeps no more).
const WIDGET_STATE_MAX: usize = 16384;
/// The most of a widget's modelContent the agent is told, in characters.
const WIDGET_MODEL_MAX: usize = 4000;

/// What of a widget's state is for the agent (Codex's shape: `{modelContent, privateContent}`): its modelContent, a
/// string as it is and anything else as JSON, cut to WIDGET_MODEL_MAX.
fn widget_model(state: &Value) -> Option<String> {
    let model = match state.get("modelContent")? {
        Value::Null => return None,
        Value::String(s) => s.clone(),
        other => other.to_string(),
    };
    Some(model.chars().take(WIDGET_MODEL_MAX).collect())
}

/// A request's JSON object, up to a megabyte; an empty body is `{}`.
pub async fn read_json<B>(body: B) -> Result<Input>
where
    B: hyper::body::Body<Data = Bytes> + Send + Unpin + 'static,
    B::Error: std::error::Error + Send + Sync + 'static,
{
    let limited = http_body_util::Limited::new(body, 1_000_000);
    let bytes = match limited.collect().await {
        Ok(collected) => collected.to_bytes(),
        Err(e) if e.to_string().contains("length limit exceeded") => return Err(http_error(413, "request too large")),
        Err(e) => return Err(anyhow::anyhow!("reading the request: {e}")),
    };
    if bytes.is_empty() {
        return Ok(Input(Map::new()));
    }
    match serde_json::from_slice::<Value>(&bytes) {
        Ok(Value::Object(map)) => Ok(Input(map)),
        Ok(_) => Ok(Input(Map::new())),
        Err(_) => Err(http_error(400, "invalid JSON")),
    }
}

#[cfg(test)]
mod tests;
