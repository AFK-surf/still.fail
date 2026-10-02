//! test/admin.test.ts, ported. The Access gate's own cases live in access.rs; the station records request spans itself
//! (mesh/station), so the span case is not here. Requests go straight to `AdminApi::handle` with the viewer the gate or
//! the mesh would have given.

use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use anyhow::{Result, bail};
use async_trait::async_trait;
use bytes::Bytes;
use stillfail_shapes::RuntimeKind;
use futures_util::future::BoxFuture;
use http_body_util::{BodyExt, Full};
use hyper::{Request, Response};
use serde_json::{Map, Value, json};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::watch;

use super::*;
use crate::chat::internal::InternalChat;
use crate::chat::slack::{SlackIdentity, SocketStatus};
use crate::chat::slack_apps::{CreatedApp, SlackApiError, slack_manifest};
use crate::chat::{ChatEvent, ChatSurface, Handler, InboundMessage, ThreadRef};
use crate::config::{ConfigToken, ConfigTokenOwner, Connect, SlackAppMade};
use crate::connections::{Connection, Connections};
use crate::hub::{Hub, HubOptions, NewChat};
use crate::login::{LoginCommands, LoginManager};
use crate::machine_logins::MachineLogins;
use crate::profiles::{ProfileCheck, ProfileQuota, QuotaWindow};
use crate::runtime::{AgentDriver, AgentSession, Events as RuntimeEvents, OpenOptions, RuntimeEvent, TurnOutcome};
use crate::settings::Settings;
use crate::store::{Attachment, AuthorKind, NewMessage, Store, now_ms};

static COUNTER: AtomicU64 = AtomicU64::new(1);

// ── fakes ──────────────────────────────────────────────────────────────────

/// A connect's link to Slack, in memory: it says it is connected, and answers Web API calls from `answers`.
struct FakeConnection {
    posts: Mutex<Vec<(ThreadRef, String)>>,
    answers: Mutex<HashMap<String, Value>>,
    stopped: AtomicUsize,
    status: watch::Sender<SocketStatus>,
}

impl FakeConnection {
    fn new() -> Arc<FakeConnection> {
        Arc::new(FakeConnection {
            posts: Mutex::default(),
            answers: Mutex::default(),
            stopped: AtomicUsize::new(0),
            status: watch::channel(SocketStatus { connected: true, last_error: None }).0,
        })
    }
}

#[async_trait]
impl ChatSurface for FakeConnection {
    fn bot_user_id(&self) -> String {
        "UBOT".into()
    }
    fn bot_name(&self) -> String {
        "ember".into()
    }
    fn workspace(&self) -> Option<String> {
        Some("T1".into())
    }
    async fn start(self: Arc<Self>, _handler: Handler) -> Result<()> {
        Ok(())
    }
    async fn post(&self, thread: &ThreadRef, message: &str, _files: &[Attachment]) -> Result<String> {
        self.posts.lock().unwrap().push((thread.clone(), message.into()));
        Ok(format!("{}.000200", 9_000_000 + COUNTER.fetch_add(1, Ordering::SeqCst)))
    }
    async fn api(&self, method: &str, _params: Map<String, Value>) -> Result<Value> {
        let answer = self.answers.lock().unwrap().get(method).cloned();
        Ok(answer.unwrap_or_else(|| json!({ "ok": true })))
    }
    async fn stop(&self) {
        self.stopped.fetch_add(1, Ordering::SeqCst);
    }
}

#[async_trait]
impl Connection for FakeConnection {
    fn socket(&self) -> SocketStatus {
        self.status.borrow().clone()
    }
    fn identity(&self) -> Option<SlackIdentity> {
        Some(SlackIdentity {
            team: "Acme".into(),
            team_id: "T1".into(),
            url: "https://acme.slack.com/".into(),
            bot_user_id: "UBOT".into(),
            bot_name: "ember".into(),
            bot_image: Some("https://avatars.slack-edge.com/ember_72.png".into()),
            bot_id: "BBOT".into(),
        })
    }
    fn changes(&self) -> watch::Receiver<SocketStatus> {
        self.status.subscribe()
    }
    async fn refresh_identity(&self) -> Result<()> {
        Ok(())
    }
}

/// Records what the station asks of Slack's app API; tokens are always taken, an install's code gives a bot token.
struct FakeSlack {
    manifest: Mutex<Value>,
    updates: Mutex<Vec<Value>>,
    made: Mutex<Vec<(String, String, Value)>>,
    /// Install codes exchanged: (code, client secret).
    exchanged: Mutex<Vec<(String, String)>>,
}

impl FakeSlack {
    fn new() -> Arc<FakeSlack> {
        Arc::new(FakeSlack { manifest: Mutex::new(slack_manifest("ember", None, None)), updates: Mutex::default(), made: Mutex::default(), exchanged: Mutex::default() })
    }
}

fn bot_scopes_of(manifest: &Value) -> String {
    let mut scopes: Vec<&str> = manifest["oauth_config"]["scopes"]["bot"].as_array().into_iter().flatten().filter_map(Value::as_str).collect();
    scopes.sort();
    scopes.join(",")
}

#[async_trait]
impl SlackService for FakeSlack {
    fn configured(&self, _by: &str) -> bool {
        true
    }
    async fn export_manifest(&self, _by: &str, _app_id: &str) -> Result<Value> {
        Ok(self.manifest.lock().unwrap().clone())
    }
    async fn update_manifest(&self, _by: &str, _app_id: &str, manifest: &Value) -> Result<bool> {
        let mut current = self.manifest.lock().unwrap();
        let changed = bot_scopes_of(&current) != bot_scopes_of(manifest);
        self.updates.lock().unwrap().push(manifest.clone());
        *current = manifest.clone();
        Ok(changed)
    }
    async fn create_app(&self, by: &str, team: &str, manifest: &Value) -> Result<CreatedApp> {
        self.made.lock().unwrap().push((by.into(), team.into(), manifest.clone()));
        Ok(CreatedApp { app_id: "A0NEW".into(), client_id: "C1".into(), client_secret: "S1".into() })
    }
    async fn set_icon(&self, _by: &str, _app_id: &str, _picture: Vec<u8>, _mime: &str) -> Result<()> {
        Err(SlackApiError { method: "apps.icon.set".into(), code: "app_not_owned_by_manager_app".into(), details: None }.into())
    }
    async fn exchange_install_code(&self, _client_id: &str, client_secret: &str, code: &str, _redirect_uri: &str) -> Result<(String, Option<String>)> {
        self.exchanged.lock().unwrap().push((code.into(), client_secret.into()));
        Ok(("xoxb-installed".into(), Some("Acme".into())))
    }
    async fn verify_tokens(&self, _app_token: &str, _bot_token: &str) -> (Option<SlackIdentity>, Vec<String>) {
        let identity = SlackIdentity {
            team: "Acme".into(),
            team_id: "T2".into(),
            url: "https://acme.slack.com/".into(),
            bot_user_id: "UBOT".into(),
            bot_name: "helper".into(),
            bot_image: None,
            bot_id: String::new(),
        };
        (Some(identity), vec![])
    }
}

struct FakeMesh(MeshStatus, watch::Sender<u64>);

impl Mesh for FakeMesh {
    fn status(&self) -> MeshStatus {
        self.0.clone()
    }
    fn changes(&self) -> watch::Receiver<u64> {
        self.1.subscribe()
    }
}

struct FakeSession {
    id: String,
    options: OpenOptions,
    events: RuntimeEvents,
    prompts: Mutex<Vec<String>>,
    steers: Mutex<Vec<String>>,
    aborts: AtomicUsize,
    disposed: AtomicBool,
    busy: AtomicBool,
}

impl FakeSession {
    fn end(&self, outcome: TurnOutcome) {
        self.busy.store(false, Ordering::SeqCst);
        let _ = self.events.send(RuntimeEvent::TurnEnded(outcome));
    }
    /// What it was told, prompts and steers.
    fn told(&self) -> String {
        let mut all = self.steers.lock().unwrap().clone();
        all.extend(self.prompts.lock().unwrap().iter().cloned());
        all.join("\n---\n")
    }
}

#[async_trait]
impl AgentSession for FakeSession {
    fn id(&self) -> String {
        self.id.clone()
    }
    fn busy(&self) -> bool {
        self.busy.load(Ordering::SeqCst)
    }
    async fn prompt(&self, text: &str) -> Result<()> {
        if self.disposed.load(Ordering::SeqCst) {
            bail!("disposed");
        }
        if self.busy() {
            bail!("busy");
        }
        self.busy.store(true, Ordering::SeqCst);
        self.prompts.lock().unwrap().push(text.into());
        Ok(())
    }
    async fn steer(&self, text: &str) -> bool {
        if !self.busy() {
            return false;
        }
        self.steers.lock().unwrap().push(text.into());
        true
    }
    async fn abort(&self) {
        self.aborts.fetch_add(1, Ordering::SeqCst);
    }
    async fn dispose(&self) {
        self.disposed.store(true, Ordering::SeqCst);
    }
}

struct FakeDriver {
    runtime: RuntimeKind,
    sessions: Mutex<Vec<Arc<FakeSession>>>,
}

impl FakeDriver {
    fn new(runtime: RuntimeKind) -> Arc<FakeDriver> {
        Arc::new(FakeDriver { runtime, sessions: Mutex::default() })
    }
    fn last(&self) -> Arc<FakeSession> {
        self.sessions.lock().unwrap().last().cloned().expect("a session opened")
    }
}

#[async_trait]
impl AgentDriver for FakeDriver {
    fn runtime(&self) -> RuntimeKind {
        self.runtime
    }
    async fn open(&self, options: OpenOptions, events: RuntimeEvents) -> Result<Arc<dyn AgentSession>> {
        let id = options.resume.clone().unwrap_or_else(|| format!("{}-{}", crate::config::runtime_name(self.runtime), COUNTER.fetch_add(1, Ordering::SeqCst)));
        let session = Arc::new(FakeSession {
            id,
            options,
            events,
            prompts: Mutex::default(),
            steers: Mutex::default(),
            aborts: AtomicUsize::new(0),
            disposed: AtomicBool::new(false),
            busy: AtomicBool::new(false),
        });
        self.sessions.lock().unwrap().push(session.clone());
        Ok(session)
    }
    async fn shutdown(&self) {}
}

/// Stands in for `claude auth login` and `codex login --device-auth`.
fn fake_login() -> &'static str {
    static PATH: OnceLock<String> = OnceLock::new();
    PATH.get_or_init(|| {
        let dir = std::env::temp_dir().join(format!("ember-fake-login-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("fake-login");
        std::fs::write(
            &path,
            "#!/bin/sh\nif [ \"$1\" = \"auth\" ]; then\n  echo \"Opening browser to sign in…\"\n  echo \"If the browser didn't open, visit: https://claude.com/cai/oauth/authorize?code=true&client_id=x&state=y\"\n  printf \"Paste code here if prompted > \"\n  read code\n  [ \"$code\" = \"good-code\" ] && { echo \"Login successful\"; exit 0; }\n  echo \"OAuth error: invalid code\"; exit 1\nfi\nprintf \"1. Open this link\\n   \\033[94mhttps://auth.openai.com/codex/device\\033[0m\\n2. Enter this one-time code\\n   \\033[94mABCD-12345\\033[0m\\n\"\nsleep 0.3\necho \"Successfully logged in\"\n",
        )
        .unwrap();
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        path.to_string_lossy().into_owned()
    })
}

// ── the rig ────────────────────────────────────────────────────────────────

#[derive(Default)]
struct Setup {
    store: Option<Arc<Store>>,
    dir: Option<PathBuf>,
    /// Counts quota questions; with it, profiles have an allowance (12% of five hours).
    quota: Option<Arc<AtomicUsize>>,
    reset_quota: Option<super::ResetQuotaFn>,
    cloud: Option<&'static str>,
    machine: Option<Arc<MachineLogins>>,
    /// The station's updates, as a release installed from `channel` (BUILD 1300) in a cloud that answers nothing.
    updates: Option<Option<&'static str>>,
}

struct Rig {
    _dir: Option<tempfile::TempDir>,
    data: PathBuf,
    path: PathBuf,
    settings: Arc<Settings>,
    store: Arc<Store>,
    hub: Arc<Hub>,
    conns: Arc<Connections>,
    connections: Arc<Mutex<Vec<Arc<FakeConnection>>>>,
    claude: Arc<FakeDriver>,
    slack: Arc<FakeSlack>,
    api: Arc<AdminApi>,
    logins: Arc<LoginManager>,
}

impl Drop for Rig {
    fn drop(&mut self) {
        self.logins.stop_all();
    }
}

/// The workspace's owner, through still.fail cloud (the only way in).
fn owner() -> Viewer {
    viewer("owner@example.com", "Owner", "owner")
}

/// Another member.
fn dev() -> Viewer {
    viewer("dev@example.com", "", "member")
}

fn viewer(email: &str, name: &str, role: &str) -> Viewer {
    Viewer::Mesh { sub: format!("sub-{email}"), email: email.into(), name: name.into(), role: role.into(), workspace: "ws".into(), device: "d".into() }
}

async fn setup() -> Rig {
    setup_with(Setup::default()).await
}

async fn setup_with(o: Setup) -> Rig {
    let (dir, data) = match o.dir {
        Some(d) => (None, d),
        None => {
            let d = tempfile::tempdir().unwrap();
            let p = d.path().to_path_buf();
            (Some(d), p)
        }
    };
    let path = data.join("config.json");
    std::fs::write(
        &path,
        json!({
            "profiles": [
                { "id": "cc", "runtime": "claude", "home": "homes/cc", "env": { "ANTHROPIC_API_KEY": "sk-very-secret-value", "ANTHROPIC_BASE_URL": "https://example" } },
                { "id": "cx", "runtime": "codex", "home": "homes/cx" },
            ],
            "connects": [{ "id": "ds", "kind": "slack", "mode": "multi-session", "bind": { "runtime": "claude" }, "slack": { "appToken": "xapp-1-aaaaaaaaaaaa", "botToken": "xoxb-bbbbbbbbbbbb", "appId": "A0DS", "team": { "id": "T0", "name": "Acme" }, "botName": "ember" } }],
        })
        .to_string(),
    )
    .unwrap();
    let settings = Settings::open(&path, &data).unwrap();
    let store = o.store.unwrap_or_else(|| Arc::new(Store::open(":memory:", None).unwrap()));
    let connections: Arc<Mutex<Vec<Arc<FakeConnection>>>> = Arc::default();
    let hub_cell: Arc<OnceLock<Arc<Hub>>> = Arc::default();
    let made = connections.clone();
    let cell = hub_cell.clone();
    let conns = Connections::new(
        Box::new(move |_c: &Connect| {
            let c = FakeConnection::new();
            made.lock().unwrap().push(c.clone());
            Ok(c as Arc<dyn Connection>)
        }),
        Arc::new(move |id: String, event: ChatEvent| {
            let hub = cell.get().cloned();
            Box::pin(async move {
                match hub {
                    Some(hub) => hub.receive(&id, event).await,
                    None => Ok(()),
                }
            }) as BoxFuture<'static, Result<()>>
        }),
    );
    let claude = FakeDriver::new(RuntimeKind::Claude);
    let (read, chats) = (settings.clone(), conns.clone());
    let hub = Hub::new(HubOptions {
        config: Arc::new(move || read.config()),
        store: store.clone(),
        chats: Arc::new(move |id| chats.chat(id).map(|c| c as Arc<dyn ChatSurface>)),
        drivers: vec![claude.clone(), FakeDriver::new(RuntimeKind::Codex)],
        mcp_url: "x".into(),
        internal: Some(Arc::new(InternalChat::default())),
        link: None,
    });
    let _ = hub_cell.set(hub.clone());
    // The config's changes reach the connections.
    let (mut changes, follow) = (settings.subscribe(), conns.clone());
    tokio::spawn(async move {
        while changes.changed().await.is_ok() {
            let config = changes.borrow().clone();
            follow.reconcile(&config).await;
        }
    });
    conns.reconcile(&settings.config()).await;
    let logins = LoginManager::new(&data, LoginCommands { claude: fake_login().into(), codex: fake_login().into() });
    let slack = FakeSlack::new();
    let quota: Option<QuotaFn> = o.quota.map(|count| {
        Arc::new(move |_p: Profile| {
            count.fetch_add(1, Ordering::SeqCst);
            Box::pin(async {
                ProfileQuota { credits: None, reset_count: None, state: "ok".into(), windows: vec![QuotaWindow { label: "5 小时".into(), used_percent: 12.0, resets_at: None }], detail: None, checked_at: now_ms() }
            }) as BoxFuture<'static, ProfileQuota>
        }) as QuotaFn
    });
    let mesh: Option<Arc<dyn Mesh>> = o.cloud.map(|origin| {
        let status = MeshStatus {
            state: "running".into(),
            origin: Some(origin.into()),
            station: Some("st".into()),
            workspace: Some("W".into()),
            workspace_id: Some("ws".into()),
            name: Some("S".into()),
            removed_at: None,
        };
        Arc::new(FakeMesh(status, watch::channel(0).0)) as Arc<dyn Mesh>
    });
    let api = AdminApi::new(AdminDeps {
        settings: settings.clone(),
        store: store.clone(),
        hub: hub.clone(),
        connections: conns.clone(),
        logins: logins.clone(),
        names: Arc::default(),
        mesh,
        quota,
        reset_quota: o.reset_quota,
        check_profile: Arc::new(|_r| Box::pin(async { ProfileCheck { decision: None, model_efforts: None, state: "ok".into(), detail: "fake".into(), models: Some(vec![]), checked_at: now_ms() } })),
        codex_models: None,
        slack_apps: Some(slack.clone()),
        check_on_start: false,
        machine_logins: o.machine,
        updates: o.updates.map(|channel| crate::updates::tests::installed(&data, "1300", channel, Some(settings.clone()))),
        dev: false,
        jobs: None,
        usage: None,
    });
    Rig { _dir: dir, data, path, settings, store, hub, conns, connections, claude, slack, api, logins }
}

impl Rig {
    async fn raw(&self, method: &str, route: &str, body: impl Into<Bytes>, viewer: Viewer) -> Response<Body> {
        let req = Request::builder().method(method).uri(format!("/admin/api{route}")).header("content-type", "application/json").body(Full::new(body.into())).unwrap();
        self.api.handle(req, viewer).await
    }

    /// A request as a viewer; its status and JSON body.
    async fn call_as(&self, method: &str, route: &str, body: Option<Value>, viewer: Viewer) -> (u16, Value) {
        let text = body.map(|b| b.to_string()).unwrap_or_default();
        let response = self.raw(method, route, text, viewer).await;
        let status = response.status().as_u16();
        let bytes = response.into_body().collect().await.unwrap().to_bytes();
        (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
    }

    async fn call(&self, method: &str, route: &str, body: Option<Value>) -> (u16, Value) {
        self.call_as(method, route, body, owner()).await
    }

    async fn get(&self, route: &str) -> Value {
        self.call("GET", route, None).await.1
    }

    async fn text(&self, method: &str, route: &str, body: &'static str) -> (u16, String) {
        let response = self.raw(method, route, body, owner()).await;
        let status = response.status().as_u16();
        let bytes = response.into_body().collect().await.unwrap().to_bytes();
        (status, String::from_utf8_lossy(&bytes).into_owned())
    }

    /// Follows an event stream (/events), gathering what it sends.
    async fn follow(&self, route: &str, viewer: Viewer) -> Follower {
        let response = self.raw("GET", route, Bytes::new(), viewer).await;
        let events: Arc<Mutex<Vec<(String, Value)>>> = Arc::default();
        let gathered = events.clone();
        let task = tokio::spawn(async move {
            let mut body = response.into_body();
            let mut buffer = String::new();
            while let Some(Ok(frame)) = body.frame().await {
                let Ok(data) = frame.into_data() else { continue };
                buffer.push_str(&String::from_utf8_lossy(&data));
                while let Some(end) = buffer.find("\n\n") {
                    let chunk: String = buffer.drain(..end + 2).collect();
                    let field = |name: &str| chunk.lines().find_map(|l| l.strip_prefix(name)).map(String::from);
                    if let (Some(event), Some(data)) = (field("event: "), field("data: ")) {
                        gathered.lock().unwrap().push((event, serde_json::from_str(&data).unwrap_or(Value::Null)));
                    }
                }
            }
        });
        Follower { events, task }
    }

    fn config(&self) -> Arc<crate::config::Config> {
        self.settings.config()
    }

    fn saved(&self) -> Value {
        serde_json::from_str(&std::fs::read_to_string(&self.path).unwrap()).unwrap()
    }

    fn connection(&self, i: usize) -> Arc<FakeConnection> {
        self.connections.lock().unwrap()[i].clone()
    }
}

struct Follower {
    events: Arc<Mutex<Vec<(String, Value)>>>,
    task: tokio::task::JoinHandle<()>,
}

impl Follower {
    fn len(&self) -> usize {
        self.events.lock().unwrap().len()
    }

    fn all(&self) -> Vec<(String, Value)> {
        self.events.lock().unwrap().clone()
    }

    /// The first event (after `from`) that `accept` takes, once it has come.
    async fn next_from(&self, event: &str, from: usize, accept: impl Fn(&Value) -> bool) -> Value {
        for _ in 0..300 {
            let found = self.events.lock().unwrap().iter().skip(from).find(|(e, d)| e == event && accept(d)).map(|(_, d)| d.clone());
            if let Some(found) = found {
                return found;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        panic!("no {event} event; got {:?}", self.events.lock().unwrap().iter().map(|(e, _)| e.clone()).collect::<Vec<_>>());
    }

    async fn next(&self, event: &str, accept: impl Fn(&Value) -> bool) -> Value {
        self.next_from(event, 0, accept).await
    }
}

impl Drop for Follower {
    fn drop(&mut self) {
        self.task.abort();
    }
}

fn message(text: &str) -> InboundMessage {
    let ts = format!("{}.000100", 1000 + COUNTER.fetch_add(1, Ordering::SeqCst));
    InboundMessage { channel: "C1".into(), thread_ts: ts.clone(), ts, user: "U1".into(), text: text.into(), addressed: true }
}

fn at(ts: &str, thread_ts: &str, user: &str, text: &str, addressed: bool) -> InboundMessage {
    InboundMessage { channel: "C1".into(), thread_ts: thread_ts.into(), ts: ts.into(), user: user.into(), text: text.into(), addressed }
}

/// Lets queued tasks and what they started run.
async fn settle() {
    for _ in 0..20 {
        tokio::task::yield_now().await;
    }
    tokio::time::sleep(Duration::from_millis(30)).await;
}

fn enc(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

fn ids(v: &Value, key: &str) -> Vec<Value> {
    v.as_array().into_iter().flatten().map(|x| x[key].clone()).collect()
}

// ── tests ──────────────────────────────────────────────────────────────────

#[test]
fn secrets_are_masked_for_the_pages() {
    assert_eq!(mask(""), "");
    assert_eq!(mask("short"), "••••");
    assert_eq!(mask("xoxb-123456789"), "xoxb-…6789");
}

#[tokio::test]
async fn a_slack_app_made_on_a_station_in_ember_cloud_is_installed_through_slacks_oauth_its_bot_token_taken_by_the_station() {
    let s = setup_with(Setup { cloud: Some("https://cloud.test"), ..Setup::default() }).await;
    let owner = |team: &str| ConfigTokenOwner { team: team.into(), team_domain: None, team_icon: None, user: "Ada".into(), email: Some("ada@example.com".into()), image: None };
    let token = |team_id: &str, team: &str, by: &str| ConfigToken {
        access_token: format!("xoxe.xoxp-{team_id}"),
        refresh_token: "xoxe-1".into(),
        expires_at: now_ms() + 3_600_000,
        team_id: team_id.into(),
        by: by.into(),
        owner: Some(owner(team)),
    };
    // Someone else's token on this station: not the viewer's to see or use.
    s.settings
        .update(|raw| {
            raw.slack_config_tokens = Some(vec![token("T1", "Acme", "owner@example.com"), token("T2", "Other", "owner@example.com"), token("T3", "Theirs", "bob@example.com")]);
            Ok(())
        })
        .unwrap();
    // Several workspaces: the station lists them (never their tokens), and the app goes into the one chosen.
    let overview0 = s.get("/overview").await;
    assert_eq!(
        overview0["slackTeams"],
        json!([{ "teamId": "T1", "name": "Acme", "owner": owner("Acme") }, { "teamId": "T2", "name": "Other", "owner": owner("Other") }])
    );
    assert!(!overview0.to_string().contains("xoxe"));
    assert_eq!(s.call("POST", "/slack/apps", Some(json!({ "settings": { "name": "ember" } }))).await.0, 400, "which workspace, when there are several");
    let (_, made) = s.call("POST", "/slack/apps", Some(json!({ "team": "T2", "settings": { "name": "Helper", "description": "Hi", "groups": { "dm": false } } }))).await;
    let sent = s.slack.made.lock().unwrap()[0].clone();
    assert_eq!((sent.0.as_str(), sent.1.as_str()), ("owner@example.com", "T2"));
    assert_eq!(s.call("POST", "/slack/apps", Some(json!({ "team": "T3", "settings": { "name": "x" } }))).await.0, 400, "not with another's token");
    let manifest = sent.2;
    assert_eq!((manifest["display_information"]["name"].as_str(), manifest["display_information"]["description"].as_str()), (Some("Helper"), Some("Hi")));
    // Slack sends the person back to still.fail cloud's page, which hands the code to the station the state names.
    assert_eq!(manifest["oauth_config"]["redirect_urls"], json!(["https://cloud.test/slack/installed"]));
    let install = s.get("/overview").await["slackApps"][0]["install"].as_str().unwrap().to_string();
    let query: HashMap<String, String> = query_pairs(install.split_once('?').unwrap().1).into_iter().collect();
    // It asks for what the app has on, no more.
    let scopes: Vec<&str> = manifest["oauth_config"]["scopes"]["bot"].as_array().unwrap().iter().filter_map(Value::as_str).collect();
    assert_eq!(query["scope"], scopes.join(","));
    assert!(!query["scope"].split(',').any(|s| s == "im:write"));
    assert_eq!((query["client_id"].as_str(), query["redirect_uri"].as_str()), ("C1", "https://cloud.test/slack/installed"));
    let state = &query["state"];
    assert!(state.strip_prefix("ws/st~").is_some_and(|r| r.len() == 32 && r.chars().all(|c| c.is_ascii_hexdigit())), "{state}");
    // The app is kept on the station from the moment it is made: its maker sees it waiting, to install and finish any time.
    let waiting = s.get("/overview").await["slackApps"].clone();
    assert_eq!(waiting.as_array().unwrap().len(), 1);
    let w = &waiting[0];
    assert_eq!((w["appId"].clone(), w["name"].clone(), w["teamId"].clone(), w["install"].clone(), w["installed"].clone()), (json!("A0NEW"), json!("Helper"), json!("T2"), json!(install), json!(false)));
    assert!(!waiting.to_string().contains("S1"), "its secret stays on the station");
    assert!(made.get("install").is_none(), "what the pages need of it comes with the overview");
    // Kept in the config: a restart of the station loses nothing.
    assert_eq!(s.saved()["slackApps"][0]["appId"], "A0NEW");
    assert_eq!(s.call("POST", "/slack/installs", Some(json!({ "code": "c", "state": "ws/st~other" }))).await.0, 400, "only an install this station began");
    assert_eq!(s.call("POST", "/slack/installs", Some(json!({ "code": "the-code", "state": w["state"] }))).await.1, json!({ "team": "Acme" }));
    assert_eq!(s.slack.exchanged.lock().unwrap()[0], ("the-code".to_string(), "S1".to_string()));
    let overview = s.get("/overview").await;
    assert_eq!((overview["slackApps"][0]["installed"].clone(), overview["slackApps"][0]["installedTeam"].clone()), (json!(true), json!("Acme")));
    assert!(!overview.to_string().contains("xoxb-installed"), "the token stays on the station");
    // Made without Socket Mode (so its maker turns it on in Slack, where the app-level token comes with its scope
    // picked), and so without events; the connect that takes it puts both in.
    assert_eq!(manifest["settings"]["socket_mode_enabled"], false);
    assert!(manifest["settings"].get("event_subscriptions").is_none());
    *s.slack.manifest.lock().unwrap() = manifest.clone();
    let connected = s
        .call("POST", "/connects", Some(json!({ "kind": "slack", "mode": "multi-session", "bind": { "runtime": "claude" }, "slack": { "appToken": "xapp-1-new", "install": w["state"] } })))
        .await;
    assert_eq!(connected.0, 200, "{}", connected.1);
    let turned_on = s.slack.updates.lock().unwrap().last().cloned().unwrap();
    assert_eq!(turned_on["settings"]["socket_mode_enabled"], true);
    assert!(turned_on["settings"]["event_subscriptions"]["bot_events"].as_array().unwrap().iter().any(|e| e == "app_mention"));
    assert_eq!(s.get("/overview").await["slackApps"], json!([]), "connected: no longer waiting");
    // Another one, to drop.
    s.call("POST", "/slack/apps", Some(json!({ "team": "T2", "settings": { "name": "Helper" } }))).await;
    // Only its maker sees it, or drops it (it stays in Slack).
    s.settings
        .update(|raw| {
            raw.slack_apps.get_or_insert_with(Vec::new).push(SlackAppMade { app_id: "A0BOB".into(), name: "Bob's".into(), team_id: "T3".into(), by: "bob@example.com".into(), created: 1, oauth: None });
            Ok(())
        })
        .unwrap();
    assert_eq!(ids(&s.get("/overview").await["slackApps"], "appId"), vec![json!("A0NEW")]);
    assert_eq!(s.call("DELETE", "/slack/apps/A0BOB", None).await.0, 404);
    assert_eq!(s.call("DELETE", "/slack/apps/A0NEW", None).await.0, 200);
    assert_eq!(s.get("/overview").await["slackApps"], json!([]));
}

#[tokio::test]
async fn the_viewer_is_who_the_mesh_verified() {
    let t = setup().await;
    let (status, body) = t.call("GET", "/overview", None).await;
    assert_eq!(status, 200);
    assert_eq!(body["viewer"], json!({ "via": "mesh", "sub": "sub-owner@example.com", "email": "owner@example.com", "name": "Owner", "role": "owner", "workspace": "ws", "device": "d" }));
}

#[tokio::test]
async fn secrets_are_masked_in_the_overview() {
    let t = setup().await;
    let body = t.get("/overview").await;
    assert_eq!(body["connects"][0]["slack"]["botToken"], "xoxb-…bbbb");
    assert_eq!(body["connects"][0]["connection"]["state"], "connected");
    let env: HashMap<String, Value> = body["profiles"][0]["env"].as_array().unwrap().iter().map(|e| (e["key"].as_str().unwrap().to_string(), e.clone())).collect();
    assert_eq!(env["ANTHROPIC_API_KEY"]["secret"], true);
    assert_eq!(env["ANTHROPIC_API_KEY"]["value"], "sk-ve…alue");
    assert_eq!(env["ANTHROPIC_BASE_URL"]["value"], "https://example");
    let text = body.to_string();
    assert!(!text.contains("very-secret") && !text.contains("bbbbbbbbbbbb"));
}

#[tokio::test]
async fn editing_a_connect_keeps_tokens_that_were_left_blank_and_writes_config_json_privately() {
    let t = setup().await;
    let (status, _) = t.call("PUT", "/connects/ds", Some(json!({ "bind": { "model": "deepseek-flash" }, "slack": { "appToken": "", "botToken": "" } }))).await;
    assert_eq!(status, 200);
    // Known by its bot's name in its Slack workspace, kept through the edit (and as Slack says once connected: T1).
    for _ in 0..100 {
        if t.saved()["connects"][0]["slack"]["team"]["id"] == "T1" {
            break;
        }
        settle().await;
    }
    let saved = t.saved();
    assert_eq!((saved["connects"][0]["slack"]["team"].clone(), saved["connects"][0]["slack"]["botName"].clone()), (json!({ "id": "T1", "name": "Acme" }), json!("ember")));
    let view = t.get("/overview").await["connects"][0].clone();
    assert_eq!((view["name"].clone(), view["team"].clone()), (json!("ember"), json!("Acme")));
    assert_eq!(saved["connects"][0]["slack"]["botToken"], "xoxb-bbbbbbbbbbbb");
    assert_eq!(saved["connects"][0]["bind"]["model"], "deepseek-flash");
    assert!(saved.get("bots").is_none());
    use std::os::unix::fs::PermissionsExt;
    assert_eq!(std::fs::metadata(&t.path).unwrap().permissions().mode() & 0o777, 0o600);
}

#[tokio::test]
async fn adding_disabling_and_deleting_connects_follows_through_to_connections() {
    let t = setup().await;
    assert_eq!(t.connections.lock().unwrap().len(), 1);
    t.call("PUT", "/connects/gpt", Some(json!({ "bind": { "runtime": "codex" }, "slack": { "appToken": "xapp-2-cccccccccc", "botToken": "xoxb-dddddddddd" } }))).await;
    t.conns.reconcile(&t.config()).await;
    let mut ids = t.conns.ids();
    ids.sort();
    assert_eq!(ids, ["ds", "gpt"]);
    t.call("PUT", "/connects/gpt", Some(json!({ "bind": { "runtime": "claude" } }))).await;
    assert_eq!(t.config().connects.iter().find(|c| c.id == "gpt").unwrap().bind.runtime, RuntimeKind::Codex, "a connect's runtime stays as it was made");
    t.call("PUT", "/connects/gpt", Some(json!({ "enabled": false }))).await;
    t.conns.reconcile(&t.config()).await;
    assert_eq!(t.conns.ids(), ["ds"]);
    assert_eq!(t.connection(1).stopped.load(Ordering::SeqCst), 1);
    let body = t.get("/overview").await;
    let gpt = body["connects"].as_array().unwrap().iter().find(|b| b["id"] == "gpt").unwrap().clone();
    assert_eq!(gpt["connection"]["state"], "disabled");
    t.call("DELETE", "/connects/gpt", None).await;
    assert_eq!(t.config().connects.iter().map(|c| c.id.clone()).collect::<Vec<_>>(), ["ds"]);
}

#[tokio::test]
async fn invalid_edits_are_refused_and_leave_the_config_unchanged() {
    let t = setup().await;
    let before = std::fs::read_to_string(&t.path).unwrap();
    let bad = t.call("PUT", "/connects/x", Some(json!({ "bind": { "runtime": "nope" } }))).await;
    assert_eq!(bad.0, 400);
    assert!(bad.1["error"].as_str().unwrap().contains("unknown runtime"), "{}", bad.1);
    let last = t.call("DELETE", "/profiles/cc", None).await;
    assert_eq!(last.0, 400);
    assert!(last.1["error"].as_str().unwrap().contains("最后一个 claude 的 Profile，ember 还要用它运行"), "{}", last.1);
    assert_eq!(std::fs::read_to_string(&t.path).unwrap(), before);
}

#[tokio::test]
async fn profile_env_strings_set_null_removes_omitted_keys_stay() {
    let t = setup().await;
    t.call("PUT", "/profiles/cc", Some(json!({ "env": { "ANTHROPIC_BASE_URL": null, "EXTRA": "1" } }))).await;
    assert_eq!(
        t.config().profiles[0].env(RuntimeKind::Claude),
        BTreeMap::from([("ANTHROPIC_API_KEY".to_string(), "sk-very-secret-value".to_string()), ("EXTRA".to_string(), "1".to_string())])
    );
    assert_eq!(t.call("PUT", "/profiles/cc", Some(json!({ "env": { "BAD NAME": "x" } }))).await.0, 400);
    t.call("PUT", "/profiles/new-one", Some(json!({ "runtime": "codex" }))).await;
    assert_eq!(t.config().profiles.last().unwrap().home, t.data.join("homes/new-one"));
}

#[tokio::test]
async fn editing_a_profiles_access_keeps_a_blank_key_but_never_carries_it_to_another_kind() {
    let t = setup().await;
    let cx = |t: &Rig| t.config().profiles.iter().find(|p| p.id == "cx").cloned().unwrap();
    assert_eq!(t.call("PUT", "/profiles/cx", Some(json!({ "access": { "kind": "opencode-go", "key": "ocg-key-123456" } }))).await.0, 200);
    assert_eq!(cx(&t).env(RuntimeKind::Codex)["OPENCODE_GO_KEY"], "ocg-key-123456");
    t.call("PUT", "/profiles/cx", Some(json!({ "name": "Codex OCG", "access": { "kind": "opencode-go", "key": "" } }))).await;
    assert_eq!((cx(&t).key, cx(&t).name), ("ocg-key-123456".to_string(), "Codex OCG".to_string()));
    assert_eq!(t.call("PUT", "/profiles/cx", Some(json!({ "access": { "kind": "subscription", "key": "" } }))).await.0, 200);
    assert_eq!(cx(&t).key, "");
    let body = t.get("/overview").await;
    let view = body["profiles"].as_array().unwrap().iter().find(|p| p["id"] == "cx").unwrap().clone();
    assert_eq!(view["loginCommand"], format!("CODEX_HOME={} codex login", t.data.join("homes/cx").display()));
}

#[tokio::test]
async fn a_key_on_a_listed_provider_makes_a_profile_that_runs_what_its_endpoints_speak() {
    let t = setup().await;
    let added = |t: &Rig, id: &str| t.config().profiles.iter().find(|p| p.id == id).cloned().unwrap();
    // Chat completions only: no runtime, but a profile all the same (it serves the automatic decisions).
    let (status, body) = t.call("POST", "/profiles", Some(json!({ "access": { "kind": "api-provider", "provider": "groq", "key": "gsk-123456" } }))).await;
    assert_eq!(status, 200, "{body}");
    let groq = added(&t, "groq");
    assert_eq!((groq.access_kind, groq.provider.as_deref(), groq.runtimes.clone()), (stillfail_shapes::AccessKind::ApiProvider, Some("groq"), vec![]));
    assert_eq!(groq.name, "Groq");
    // Anthropic and Responses endpoints: both runtimes, set up from where the provider speaks.
    assert_eq!(t.call("POST", "/profiles", Some(json!({ "access": { "kind": "api-provider", "provider": "opencode", "key": "oc-key-1" } }))).await.0, 200);
    let zen = added(&t, "opencode");
    assert_eq!(zen.runtimes, vec![RuntimeKind::Claude, RuntimeKind::Codex]);
    assert_eq!(zen.env(RuntimeKind::Claude)["ANTHROPIC_BASE_URL"], "https://opencode.ai/zen");
    assert_eq!(zen.env(RuntimeKind::Claude)["ANTHROPIC_CUSTOM_HEADERS"], "x-opencode-session: {route}");
    assert_eq!(zen.env(RuntimeKind::Codex)["EMBER_API_KEY"], "oc-key-1");
    // A second key on the same provider is a profile of its own.
    assert_eq!(t.call("POST", "/profiles", Some(json!({ "access": { "kind": "api-provider", "provider": "groq", "key": "gsk-other" } }))).await.0, 200);
    assert_eq!(t.config().profiles.iter().filter(|p| p.provider.as_deref() == Some("groq")).count(), 2);
    // The address is the person's where the provider has none; a key is optional only for a server of one's own.
    assert_eq!(t.call("POST", "/profiles", Some(json!({ "access": { "kind": "api-provider", "provider": "azure-openai", "key": "k" } }))).await.0, 400);
    assert_eq!(t.call("POST", "/profiles", Some(json!({ "access": { "kind": "api-provider", "provider": "custom", "endpoint": "http://127.0.0.1:4000/v1", "protocol": "anthropic" } }))).await.0, 200);
    let custom = added(&t, "custom");
    // A server of one's own speaks the one protocol chosen for it: here the runtime that reads Anthropic.
    assert_eq!((custom.key.as_str(), custom.endpoint.as_deref(), custom.runtimes.clone()), ("", Some("http://127.0.0.1:4000/v1"), vec![RuntimeKind::Claude]));
    assert_eq!(t.call("POST", "/profiles", Some(json!({ "access": { "kind": "api-provider", "provider": "groq" } }))).await.0, 400, "a key is needed");
    assert_eq!(t.call("POST", "/profiles", Some(json!({ "access": { "kind": "api-provider", "provider": "nope", "key": "k" } }))).await.0, 400);
    assert_eq!(t.call("POST", "/profiles", Some(json!({ "access": { "kind": "api-provider", "provider": "anthropic", "key": "k" } }))).await.0, 400, "Anthropic is its own kind");
    // What an older core is shown: `env`, with the provider beside it; the list of providers leaves out the two kinds from before.
    let body = t.get("/overview").await;
    let view = body["profiles"].as_array().unwrap().iter().find(|p| p["id"] == "groq").unwrap().clone();
    assert_eq!((view["access"]["kind"].as_str(), view["access"]["provider"].as_str(), view["access"]["key"].as_str().map(|k| k.contains("123456"))), (Some("env"), Some("groq"), Some(false)));
    let listed: Vec<&str> = body["apiProviders"].as_array().unwrap().iter().map(|p| p["id"].as_str().unwrap()).collect();
    assert!(listed.contains(&"deepseek") && listed.contains(&"opencode") && !listed.contains(&"anthropic") && !listed.contains(&"opencode-go"));
    // Its address can be changed, its key kept; it can be deleted although it runs no runtime.
    assert_eq!(t.call("PUT", "/profiles/custom", Some(json!({ "access": { "kind": "api-provider", "endpoint": "http://127.0.0.1:5000/v1" } }))).await.0, 200);
    assert_eq!(added(&t, "custom").endpoint.as_deref(), Some("http://127.0.0.1:5000/v1"));
    assert_eq!(t.call("DELETE", "/profiles/groq", None).await.0, 200);
}

#[tokio::test]
async fn session_detail_is_the_session_its_threads_and_turns_its_transcript_comes_live_from_any_entry_on() {
    let t = setup().await;
    t.hub.accept("ds", message("<@UBOT> hi")).await.unwrap();
    settle().await;
    let row = t.store.list_sessions().unwrap()[0].clone();
    let projects = t.data.join("homes/cc/projects/-work");
    std::fs::create_dir_all(&projects).unwrap();
    std::fs::write(
        projects.join(format!("{}.jsonl", row.runtime_session_id.clone().unwrap())),
        [
            json!({ "type": "user", "timestamp": "2026-09-26T00:00:00Z", "message": { "content": "hi" } }).to_string(),
            json!({ "type": "assistant", "message": { "content": [{ "type": "tool_use", "name": "Bash", "input": { "command": "ls" } }] } }).to_string(),
        ]
        .join("\n")
            + "\n",
    )
    .unwrap();
    let list = t.get("/sessions").await;
    assert_eq!(list[0]["process"], "running");
    assert!(list[0].get("token").is_none(), "session tokens are never sent to the page");
    let detail = t.get(&format!("/sessions/{}", enc(&row.key))).await;
    let mut keys: Vec<&String> = detail.as_object().unwrap().keys().collect();
    keys.sort();
    assert_eq!(keys, ["jobs", "session", "threads", "turns"]);
    assert_eq!(detail["threads"].as_array().unwrap().len(), 1);
    assert_eq!(detail["threads"][0]["lastMessage"]["text"], "<@UBOT> hi");
    assert_eq!(detail["threads"][0]["surface"], "slack:T1");
    assert_eq!(detail["turns"].as_array().unwrap().len(), 1);
    // Its transcript comes on the events stream opened for it, from the entry asked for.
    let live = t.follow(&format!("/events?live={}&from=1&live=nobody&from=0", enc(&row.key)), owner()).await;
    let timeline = live.next("live", |m| m["type"] == "timeline").await;
    assert_eq!((timeline["key"].clone(), timeline["start"].clone()), (json!(row.key), json!(1)));
    assert_eq!(ids(&timeline["entries"], "kind"), vec![json!("tool_call")]);
    assert!(!live.all().iter().any(|(e, d)| e == "live" && d["key"] == "nobody"), "a session that is not there is left out");
    drop(live);
    assert_eq!(t.call("POST", &format!("/sessions/{}/stop", enc(&row.key)), None).await.0, 200);
    assert_eq!(t.claude.last().aborts.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn a_single_session_connect_can_be_set_to_wake_without_a_mention() {
    let t = setup().await;
    assert_eq!(t.call("PUT", "/connects/ds", Some(json!({ "mode": "single-session", "requireMention": false }))).await.0, 200);
    let body = t.get("/overview").await;
    assert_eq!((body["connects"][0]["mode"].clone(), body["connects"][0]["requireMention"].clone()), (json!("single-session"), json!(false)));
    t.call("PUT", "/connects/ds", Some(json!({ "mode": "multi-session" }))).await;
    assert!(t.config().connects[0].require_mention, "multi-session always needs a mention");
}

#[tokio::test]
async fn a_subscription_sign_in_runs_on_the_ember_host_and_relays_the_link_the_code_and_the_result() {
    let t = setup().await;
    t.call("PUT", "/profiles/sub", Some(json!({ "runtime": "claude", "access": { "kind": "subscription" } }))).await;
    async fn wait(t: &Rig, profile: &str, state: &str) -> Value {
        for _ in 0..500 {
            let body = t.get(&format!("/profiles/{profile}/login")).await;
            if body["job"]["state"] == state {
                return body["job"].clone();
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
        panic!("login of {profile} never reached {state}");
    }
    assert_eq!(t.call("POST", "/profiles/cc/login", None).await.0, 400, "keyed profiles do not sign in");
    t.call("POST", "/profiles/sub/login", None).await;
    let job = wait(&t, "sub", "needs_code").await;
    assert!(job["url"].as_str().unwrap().starts_with("https://claude.com/cai/oauth/authorize?"));
    t.call("POST", "/profiles/sub/login-code", Some(json!({ "code": "wrong" }))).await;
    assert!(wait(&t, "sub", "failed").await["error"].as_str().unwrap().contains("invalid code"));
    t.call("POST", "/profiles/sub/login", None).await;
    wait(&t, "sub", "needs_code").await;
    t.call("POST", "/profiles/sub/login-code", Some(json!({ "code": " good-code " }))).await;
    wait(&t, "sub", "done").await;

    t.call("PUT", "/profiles/cxs", Some(json!({ "runtime": "codex", "access": { "kind": "subscription" } }))).await;
    t.call("POST", "/profiles/cxs/login", None).await;
    let device = wait(&t, "cxs", "needs_approval").await;
    assert_eq!((device["url"].clone(), device["userCode"].clone()), (json!("https://auth.openai.com/codex/device"), json!("ABCD-12345")));
    wait(&t, "cxs", "done").await;
    let body = t.get("/overview").await;
    let cxs = body["profiles"].as_array().unwrap().iter().find(|p| p["id"] == "cxs").unwrap().clone();
    assert_eq!(cxs["login"]["state"], "done");
}

#[tokio::test]
async fn a_sign_in_after_its_profile_was_deleted_makes_a_profile_beside_the_home_left_behind() {
    let t = setup().await;
    async fn signed_in(t: &Rig) -> String {
        let id = t.call("POST", "/logins", Some(json!({ "runtime": "codex" }))).await.1["id"].as_str().unwrap().to_string();
        for _ in 0..500 {
            let body = t.get("/overview").await;
            let login = body["logins"].as_array().unwrap().iter().find(|l| l["id"] == id.as_str()).cloned().unwrap();
            assert_eq!(login["error"], Value::Null, "{login}");
            if let Some(created) = login["created"].as_str() {
                return created.to_string();
            }
            tokio::time::sleep(Duration::from_millis(30)).await;
        }
        panic!("the sign-in {id} made no profile");
    }
    let first = signed_in(&t).await;
    assert_eq!(t.call("DELETE", &format!("/profiles/{first}"), None).await.0, 200);
    assert!(t.data.join("homes").join(&first).is_dir(), "a deleted profile's home stays");
    let second = signed_in(&t).await;
    assert_ne!(second, first);
    assert!(t.config().profiles.iter().any(|p| p.id == second));
}

#[tokio::test]
async fn a_connects_slack_app_is_edited_through_its_manifest_new_permissions_need_approval_in_slack() {
    let t = setup().await;
    let app = t.get("/connects/ds/slack-app").await;
    assert_eq!((app["state"].clone(), app["settings"]["name"].clone()), (json!("ok"), json!("ember")));
    assert_eq!(app["links"]["install"], "https://app.slack.com/app-settings/T0/A0DS/install-on-team");
    let renamed = t.call("PUT", "/connects/ds/slack-app", Some(json!({ "name": "ember-ds", "description": "DS agent" }))).await.1;
    assert_eq!(renamed["permissionsUpdated"], false);
    assert_eq!(t.slack.manifest.lock().unwrap()["display_information"]["name"], "ember-ds");
    let fewer = t.call("PUT", "/connects/ds/slack-app", Some(json!({ "groups": { "files": false }, "icon": "data:image/png;base64,AAAA" }))).await.1;
    assert_eq!(fewer["permissionsUpdated"], true);
    assert!(fewer["iconError"].as_str().unwrap().contains("API 创建"));
    assert_eq!(t.call("PUT", "/connects/ds/slack-app", Some(json!({ "backgroundColor": "red" }))).await.0, 400);
    // Token edits keep the app id ember learned.
    t.call("PUT", "/connects/ds", Some(json!({ "slack": { "botToken": "xoxb-new-token-123" } }))).await;
    assert_eq!(t.config().connects[0].slack.app_id.as_deref(), Some("A0DS"));
}

#[tokio::test]
async fn connects_sessions_and_chats_remember_who_created_them() {
    let t = setup().await;
    let created = |t: &Rig, id: &str| t.config().connects.iter().find(|c| c.id == id).unwrap().created_by.clone().map(|o| (o.id, o.name));
    t.call("PUT", "/connects/fresh", Some(json!({ "bind": { "runtime": "claude" } }))).await;
    assert_eq!(created(&t, "fresh"), Some(("owner@example.com".to_string(), "Owner".to_string())));
    t.call("PUT", "/connects/fresh", Some(json!({ "mode": "single-session" }))).await;
    assert_eq!(created(&t, "fresh").map(|c| c.0), Some("owner@example.com".to_string()), "editing keeps the creator");
    let body = t.get("/overview").await;
    assert_eq!(body["connects"].as_array().unwrap().iter().find(|c| c["id"] == "ds").unwrap()["createdBy"], Value::Null, "older connects have none");
    t.call("PUT", "/connects/ds", Some(json!({ "owner": { "id": "Bob@Example.test", "name": "Bob" } }))).await;
    assert_eq!(created(&t, "ds"), Some(("bob@example.test".to_string(), "Bob".to_string())));
    assert_eq!(t.call("PUT", "/connects/ds", Some(json!({ "owner": { "id": "not an email" } }))).await.0, 400);

    t.hub.accept("ds", at("11.000001", "11.000001", "U42", "<@UBOT> hi", true)).await.unwrap();
    settle().await;
    let summary = t.get("/sessions").await[0].clone();
    assert_eq!(summary["creator"], json!({ "id": "slack:ds:U42", "name": "U42", "email": null, "via": "slack" }));
    assert_eq!(ids(&summary["participants"], "id"), vec![json!("slack:ds:U42")]);
    let key = summary["key"].as_str().unwrap().to_string();
    let chat = t.call("POST", "/threads", Some(json!({ "session": key, "title": "排查" }))).await.1;
    assert_eq!((chat["surface"].clone(), chat["creator"]["via"].clone()), (json!("ember"), json!("cloud")));
    let members: Vec<(Value, Value)> = chat["sessions"].as_array().unwrap().iter().map(|m| (m["session"].clone(), m["connect"].clone())).collect();
    assert_eq!(members, vec![(json!(key), json!("ember"))]);
    let chat_id = chat["id"].as_i64().unwrap();
    assert_eq!(t.call("POST", &format!("/threads/{chat_id}/messages"), Some(json!({ "text": "  " }))).await.0, 400);
    t.call("POST", &format!("/threads/{chat_id}/messages"), Some(json!({ "text": "hello from the page" }))).await;
    let after = t.get(&format!("/sessions/{}", enc(&key))).await;
    assert_eq!(ids(&after["session"]["participants"], "id"), vec![json!("slack:ds:U42"), json!("owner@example.com")]);
    assert_eq!(ids(&after["threads"], "title"), vec![json!("排查"), Value::Null]);
    let firsts: Vec<(Value, Vec<Value>)> = after["threads"].as_array().unwrap().iter().map(|x| (x["firstText"].clone(), ids(&x["people"], "id"))).collect();
    assert_eq!(firsts, vec![(json!("hello from the page"), vec![json!("owner@example.com")]), (json!("<@UBOT> hi"), vec![json!("slack:ds:U42")])]);
    let slack_thread = after["threads"][1]["id"].as_i64().unwrap();
    assert_eq!(t.call("POST", &format!("/threads/{slack_thread}/messages"), Some(json!({ "text": "hi" }))).await.0, 400, "Slack threads are written in Slack");
    // The app a message was sent from is kept with it, for its agent; older apps say none.
    t.call("POST", &format!("/threads/{chat_id}/messages"), Some(json!({ "text": "from the phone", "client": " android 0.1.1123\n" }))).await;
    let entries = t.get(&format!("/threads/{chat_id}/entries")).await["entries"].clone();
    let clients: Vec<(Value, Value)> = entries.as_array().unwrap().iter().map(|e| (e["text"].clone(), e["client"].clone())).collect();
    assert_eq!(clients, vec![(json!("hello from the page"), Value::Null), (json!("from the phone"), json!("android 0.1.1123"))]);
}

#[tokio::test]
async fn a_write_asked_again_under_its_key_is_done_once() {
    let t = setup().await;
    t.hub.accept("ds", at("11.000001", "11.000001", "U42", "<@UBOT> hi", true)).await.unwrap();
    settle().await;
    let key = t.get("/sessions").await[0]["key"].as_str().unwrap().to_string();
    let chat_id = t.call("POST", "/threads", Some(json!({ "session": key }))).await.1["id"].as_i64().unwrap();
    let post = |text: &'static str, key: Option<&'static str>| {
        let t = &t;
        async move {
            let mut req = Request::builder().method("POST").uri(format!("/admin/api/threads/{chat_id}/messages")).header("content-type", "application/json");
            if let Some(key) = key {
                req = req.header("idempotency-key", key);
            }
            let response = t.api.handle(req.body(Full::new(Bytes::from(json!({ "text": text }).to_string()))).unwrap(), owner()).await;
            assert_eq!(response.headers().get("stillfail-idempotent").map(|v| v.to_str().unwrap()), Some("1"), "every answer says so");
            let status = response.status().as_u16();
            let body: Value = serde_json::from_slice(&response.into_body().collect().await.unwrap().to_bytes()).unwrap();
            (status, body["n"].clone())
        }
    };
    // The same write on two connections at once, and once more later: said once, each told the same entry.
    let (a, b) = tokio::join!(post("once", Some("k1")), post("once", Some("k1")));
    let c = post("once", Some("k1")).await;
    assert_eq!((a.0, b.0, c.0), (200, 200, 200));
    assert!(a.1.is_u64() && a.1 == b.1 && b.1 == c.1, "{a:?} {b:?} {c:?}");
    // Another key, or none (an older client), is another write.
    post("twice", Some("k2")).await;
    post("thrice", None).await;
    let texts: Vec<Value> = t.get(&format!("/threads/{chat_id}/entries")).await["entries"].as_array().unwrap().iter().map(|e| e["text"].clone()).filter(|x| x != "<@UBOT> hi").collect();
    assert_eq!(texts, vec![json!("once"), json!("twice"), json!("thrice")]);
}

#[tokio::test]
async fn the_station_reports_the_machine_it_runs_on() {
    let t = setup().await;
    let (status, body) = t.call("GET", "/host", None).await;
    assert_eq!(status, 200);
    assert!(!body["hostname"].as_str().unwrap().is_empty() && body["cpus"].as_u64().unwrap() > 0);
    let (total, used) = (body["memory"]["totalBytes"].as_u64().unwrap(), body["memory"]["usedBytes"].as_u64().unwrap());
    assert!(total > 0 && used > 0 && used <= total);
    assert!(body["disk"]["totalBytes"].as_u64().unwrap() > 0 && body["disk"]["freeBytes"].as_u64().unwrap() <= body["disk"]["totalBytes"].as_u64().unwrap());
}

#[tokio::test]
async fn files_wait_in_the_uploads_move_into_the_chats_session_when_a_message_sends_them_and_reach_the_agent_as_paths() {
    let t = setup().await;
    t.hub.accept("ds", message("<@UBOT> hi")).await.unwrap();
    settle().await;
    let summary = t.get("/sessions").await[0].clone();
    let key = summary["key"].as_str().unwrap().to_string();
    let chat = t.call("POST", "/threads", Some(json!({ "session": key }))).await.1;
    let chat_id = chat["id"].as_i64().unwrap();
    let say = |input: Value| {
        let t = &t;
        async move { t.call("POST", &format!("/threads/{chat_id}/messages"), Some(input)).await }
    };
    let threads_before = t.get("/threads").await.as_array().unwrap().len();
    let upload = t.raw("POST", &format!("/uploads?name={}", enc("../../report.txt")), "hello file", owner()).await;
    assert_eq!(upload.status(), 200);
    let staged: Value = serde_json::from_slice(&upload.into_body().collect().await.unwrap().to_bytes()).unwrap();
    let staged_path = staged["path"].as_str().unwrap().to_string();
    assert_eq!(Path::new(&staged_path).parent().unwrap(), t.data.join("uploads"), "a name cannot climb out of the uploads");
    assert!(staged_path.ends_with("-report.txt"));
    assert_eq!(std::fs::read_to_string(&staged_path).unwrap(), "hello file");
    assert_eq!(t.get("/threads").await.as_array().unwrap().len(), threads_before, "a file waiting makes no chat");
    let mut elsewhere = staged.clone();
    elsewhere["path"] = json!("/etc/hosts");
    assert_eq!(say(json!({ "text": "看看", "attachments": [elsewhere] })).await.0, 400);
    assert_eq!(say(json!({ "text": "看看这个", "attachments": [staged] })).await.0, 200);
    settle().await;
    let file = t.get(&format!("/threads/{chat_id}/entries")).await["entries"][0]["attachments"][0].clone();
    let file_path = file["path"].as_str().unwrap().to_string();
    assert!(file_path.contains("/uploads/") && file_path.ends_with("-report.txt"), "{file_path}");
    assert_ne!(file_path, staged_path, "it moved into the session's uploads");
    assert!(!Path::new(&staged_path).exists());
    assert_eq!(std::fs::read_to_string(&file_path).unwrap(), "hello file");
    assert_eq!(say(json!({ "text": "再发一次", "attachments": [staged] })).await.0, 200, "sent again, it is found where it moved");
    settle().await;
    assert!(t.claude.last().told().contains(&format!("看看这个\n\nAttached files:\n- {file_path}")), "{}", t.claude.last().told());
    let page = t.get(&format!("/threads/{chat_id}/entries")).await;
    assert_eq!(ids(&page["entries"][0]["attachments"], "name"), vec![staged["name"].clone()]);
    assert_eq!(page["entries"][0]["text"], "看看这个", "the words are stored as typed");
    assert_eq!(page["entries"][0]["authorName"], "Owner");
    let name = Path::new(&file_path).file_name().unwrap().to_string_lossy().into_owned();
    assert_eq!(t.text("GET", &format!("/sessions/{}/files?name={}", enc(&key), enc(&name)), "").await, (200, "hello file".to_string()));
    assert_eq!(t.text("GET", &format!("/sessions/{}/files?name={}", enc(&key), enc("../../../config.json")), "").await.0, 404);
    say(json!({ "text": "改一下", "quotes": [{ "author": "deepseek-flash", "role": "agent", "ts": "1790383286.536000", "text": "第一行\n第二行", "comment": "这里不对" }] })).await;
    settle().await;
    assert!(
        t.claude.last().told().contains("[Quote] From your own earlier message 1790383286.536000 in this conversation:\n> 第一行\n> 第二行\nTheir comment on it: 这里不对\n\n改一下"),
        "{}",
        t.claude.last().told()
    );
    let after = t.get(&format!("/threads/{chat_id}/entries")).await;
    let last_entry = after["entries"].as_array().unwrap().last().unwrap().clone();
    assert_eq!(last_entry["quotes"][0]["comment"], "这里不对");
    // The agent answers with an image; it is copied into the uploads and measured.
    let mut png = vec![0x89, b'P', b'N', b'G', 13, 10, 26, 10, 0, 0, 0, 13];
    png.extend(b"IHDR");
    png.extend(320u32.to_be_bytes());
    png.extend(200u32.to_be_bytes());
    let shot = t.data.join("chart.png");
    std::fs::write(&shot, png).unwrap();
    let post = t.hub.tools().into_iter().find(|x| x.name == "chat_post").unwrap();
    let thread_ts = chat["threadTs"].as_str().unwrap().to_string();
    let args = |files: Value| json!({ "to": format!("EMBER/{thread_ts}"), "text": "图在这", "files": files }).as_object().unwrap().clone();
    (post.run)(key.clone(), args(json!([shot.to_string_lossy()]))).await.unwrap();
    let reply = t.get(&format!("/threads/{chat_id}/entries?after={}", after["last"])).await["entries"].as_array().unwrap().last().unwrap().clone();
    assert_eq!((reply["authorKind"].clone(), reply["author"].clone(), reply["authorName"].clone()), (json!("agent"), json!(key), json!("ember")));
    let image = &reply["attachments"][0];
    assert_eq!((image["name"].clone(), image["width"].clone(), image["height"].clone()), (json!("chart.png"), json!(320), json!(200)));
    assert!(image["path"].as_str().unwrap().contains("/uploads/") && image["path"].as_str().unwrap().ends_with("-chart.png"));
    let missing = (post.run)(key.clone(), args(json!(["/no/such/file.png"]))).await.unwrap_err();
    assert!(missing.to_string().contains("no such file"));
}

#[tokio::test]
async fn a_new_chat_makes_a_session_of_its_own_with_the_chosen_runtime_model_and_effort() {
    let t = setup().await;
    assert_eq!(t.call("POST", "/sessions", Some(json!({ "runtime": "gpt" }))).await.0, 400);
    assert_eq!(t.call("POST", "/sessions", Some(json!({ "runtime": "claude", "effort": "turbo" }))).await.0, 400);
    assert_eq!(t.call("POST", "/sessions", Some(json!({ "runtime": "claude", "model": "deepseek-flash" }))).await.0, 400, "no profile has the model enabled");
    t.call("PUT", "/profiles/cc", Some(json!({ "models": ["deepseek-flash", "deepseek-flash", " glm-5 "] }))).await;
    let ov = t.get("/overview").await;
    assert_eq!(ov["profiles"].as_array().unwrap().iter().find(|p| p["id"] == "cc").unwrap()["models"], json!(["deepseek-flash", "glm-5"]));
    let made = t.call("POST", "/sessions", Some(json!({ "runtime": "claude", "model": "deepseek-flash", "effort": "high", "title": "新对话", "clientKey": "new:1-1" }))).await;
    assert_eq!(made.0, 200);
    let made = made.1;
    // Its row says the key the client gave it, so the client knows it for its own before this answer comes.
    let rows = t.get("/chats").await;
    let row = rows.as_array().unwrap().iter().find(|r| r["id"] == made["key"]).unwrap();
    assert_eq!(row["clientKey"], "new:1-1");
    assert_eq!((made["thread"]["surface"].clone(), made["thread"]["title"].clone(), made["thread"]["sessions"][0]["session"].clone()), (json!("ember"), json!("新对话"), made["key"].clone()));
    let key = made["key"].as_str().unwrap().to_string();
    assert_eq!(t.call("POST", &format!("/threads/{}/messages", made["thread"]["id"]), Some(json!({ "text": "开始吧" }))).await.0, 200);
    settle().await;
    let body = t.get(&format!("/sessions/{}", enc(&key))).await;
    let s = &body["session"];
    assert_eq!((s["connect"].clone(), s["profile"].clone(), s["model"].clone(), s["effort"].clone()), (json!("ember"), json!("cc"), json!("deepseek-flash"), json!("high")));
    assert_eq!(s["creator"]["via"], "cloud");
    assert_eq!(body["threads"][0]["lastMessage"]["text"], "开始吧");
    assert_eq!(t.claude.last().options.model.as_deref(), Some("deepseek-flash"));
    assert!(t.claude.last().prompts.lock().unwrap()[0].contains("开始吧"));
}

#[tokio::test]
async fn thread_entries_the_latest_page_pages_back_what_came_after_n_and_a_gap_from_a_to_b() {
    let t = setup().await;
    let (_, thread) = t.hub.new_session(NewChat { fast: None, runtime: RuntimeKind::Claude, profile: None, model: None, effort: None, title: None, created_by: "local".into(), client_key: None }).unwrap();
    for i in 1..=5 {
        t.hub.say(thread.id, "local", &format!("m{i}"), vec![], vec![], None).unwrap();
    }
    let latest = t.get(&format!("/threads/{}/entries?limit=2", thread.id)).await;
    let rows: Vec<(Value, Value, Value)> = latest["entries"].as_array().unwrap().iter().map(|e| (e["n"].clone(), e["text"].clone(), e["authorName"].clone())).collect();
    assert_eq!(rows, vec![(json!(4), json!("m4"), json!("管理员")), (json!(5), json!("m5"), json!("管理员"))]);
    assert_eq!(latest["last"], 5);
    assert_eq!(ids(&t.get(&format!("/threads/{}/entries?before=4&limit=10", thread.id)).await["entries"], "text"), vec![json!("m1"), json!("m2"), json!("m3")]);
    assert_eq!(ids(&t.get(&format!("/threads/{}/entries?from=2&to=3", thread.id)).await["entries"], "n"), vec![json!(2), json!(3)]);
    assert_eq!(t.get(&format!("/threads/{}/entries?after=5", thread.id)).await["entries"], json!([]));
    // A Slack thread takes edits: entries after the ones read, which never change.
    t.hub.accept("ds", at("7.000001", "7.000001", "U1", "<@UBOT> one", true)).await.unwrap();
    t.hub.accept("ds", at("7.000002", "7.000001", "U1", "two", false)).await.unwrap();
    let slack = t.store.thread_at("slack:T1", "C1", "7.000001").unwrap().unwrap();
    let opened = t.get(&format!("/threads/{}/entries", slack.id)).await;
    t.hub.receive("ds", ChatEvent::Changed { channel: "C1".into(), thread_ts: "7.000001".into(), ts: "7.000001".into(), text: "<@UBOT> one, edited".into() }).await.unwrap();
    t.hub.say(thread.id, "local", "m6", vec![], vec![], None).unwrap();
    let since = t.get(&format!("/threads/{}/entries?after={}", slack.id, opened["last"])).await;
    let rows: Vec<Vec<Value>> = since["entries"].as_array().unwrap().iter().map(|e| vec![e["n"].clone(), e["kind"].clone(), e["target"].clone(), e["text"].clone()]).collect();
    assert_eq!(rows, vec![vec![json!(3), json!("edit"), json!(1), json!("<@UBOT> one, edited")]]);
    assert_eq!(since["last"], 3);
    assert_eq!(t.get(&format!("/threads/{}/entries?from=1&to=2", slack.id)).await["entries"], opened["entries"]);
    assert_eq!(ids(&t.get(&format!("/threads/{}/entries?after=5", thread.id)).await["entries"], "text"), vec![json!("m6")]);
    // Lists carry the last n and the latest message as merged.
    let session = t.store.thread_sessions(slack.id).unwrap()[0].session.clone();
    let view = t.get(&format!("/threads?session={}", enc(&session))).await[0].clone();
    assert_eq!((view["last"].clone(), view["lastMessage"]["seq"].clone(), view["lastMessage"]["text"].clone()), (json!(3), json!(2), json!("two")));
    assert_eq!(t.call("GET", &format!("/threads/{}/entries?from=2", thread.id), None).await.0, 400);
    assert_eq!(t.call("GET", "/threads/999/entries", None).await.0, 404);
}

#[tokio::test]
async fn read_positions_and_unread_counts_are_per_viewer_and_only_move_forward() {
    let t = setup().await;
    let (key, thread) = t.hub.new_session(NewChat { fast: None, runtime: RuntimeKind::Claude, profile: None, model: None, effort: None, title: None, created_by: "owner@example.com".into(), client_key: None }).unwrap();
    let first = t.hub.say(thread.id, "owner@example.com", "mine", vec![], vec![], None).unwrap();
    t.hub.say(thread.id, "dev@example.com", "theirs", vec![], vec![], None).unwrap();
    t.store.insert_message(NewMessage::new(thread.id, "9.000001", AuthorKind::Agent, &key, "answer")).unwrap();
    let route = format!("/threads?session={}", enc(&key));
    let unread = |viewer: Viewer| {
        let (t, route) = (&t, route.clone());
        async move { t.call_as("GET", &route, None, viewer).await.1[0]["unread"].clone() }
    };
    assert_eq!(unread(owner()).await, 2, "a viewer's own messages are not unread for them");
    assert_eq!(unread(dev()).await, 2);
    let local_events = t.follow("/events", owner()).await;
    let dev_events = t.follow("/events", dev()).await;
    let put = t.call("PUT", &format!("/threads/{}/read", thread.id), Some(json!({ "n": first + 1 }))).await.1;
    assert_eq!(put, json!({ "viewer": "owner@example.com", "thread": thread.id, "n": first + 1 }));
    assert_eq!(unread(owner()).await, 1);
    assert_eq!(unread(dev()).await, 2);
    assert_eq!(local_events.next("read", |_| true).await, json!({ "viewer": "owner@example.com", "thread": thread.id, "n": first + 1 }));
    t.call_as("PUT", &format!("/threads/{}/read", thread.id), Some(json!({ "n": first })), dev()).await;
    dev_events.next("read", |_| true).await;
    settle().await;
    assert_eq!(dev_events.all().iter().filter(|(e, _)| e == "read").count(), 1, "a read goes only to its viewer");
    assert_eq!(t.call("PUT", &format!("/threads/{}/read", thread.id), Some(json!({ "n": 1 }))).await.1["n"], first + 1, "never back");
    let view = t.get(&route).await[0].clone();
    assert_eq!((view["read"].clone(), view["unread"].clone(), view["last"].clone(), view["lastMessage"]["text"].clone()), (json!(first + 1), json!(1), json!(3), json!("answer")));
}

#[tokio::test]
async fn sessions_can_be_archived_shown_again_and_deleted_with_their_workspace() {
    let t = setup().await;
    t.hub.accept("ds", message("<@UBOT> hi")).await.unwrap();
    settle().await;
    let summary = t.get("/sessions").await[0].clone();
    let key = enc(summary["key"].as_str().unwrap());
    let thread = t.get("/threads").await[0].clone();
    let entries = t.get(&format!("/threads/{}/entries", thread["id"])).await;
    let archived = t.call("POST", &format!("/sessions/{key}/archive"), None).await.1;
    assert!(archived["archivedAt"].as_i64().unwrap() > 0);
    // Its thread is read from its archive file, the same way.
    assert!(t.store.archive_dir().join("threads").join(format!("{}.jsonl.zst", thread["id"])).exists());
    assert_eq!(t.get(&format!("/threads/{}/entries", thread["id"])).await, entries);
    assert_eq!(t.get("/threads").await, json!([thread]));
    assert_eq!(t.get("/sessions").await, json!([]));
    assert_eq!(ids(&t.get("/sessions?archived=1").await, "key"), vec![summary["key"].clone()]);
    t.call("DELETE", &format!("/sessions/{key}/archive"), None).await;
    assert_eq!(t.get("/sessions").await.as_array().unwrap().len(), 1);
    let workspace = summary["workspace"].as_str().unwrap().to_string();
    assert!(Path::new(&workspace).exists());
    assert_eq!(t.call("DELETE", &format!("/sessions/{key}"), None).await.0, 200);
    assert!(!Path::new(&workspace).exists());
    assert!(t.claude.last().disposed.load(Ordering::SeqCst));
    assert_eq!(t.call("GET", &format!("/sessions/{key}"), None).await.0, 404);
    assert_eq!(t.get("/threads").await, json!([]));
}

#[tokio::test]
async fn chats_are_archived_with_their_session_or_alone_and_listed_in_the_archive() {
    let t = setup().await;
    let made = t.call("POST", "/sessions", Some(json!({ "runtime": "claude" }))).await.1;
    let key = made["key"].as_str().unwrap().to_string();
    let own = made["thread"]["id"].as_i64().unwrap();
    let other = t.call("POST", "/threads", Some(json!({ "session": key }))).await.1["id"].as_i64().unwrap();
    let rows = |v: Value| {
        let mut rows: Vec<(i64, Option<String>)> =
            v.as_array().unwrap().iter().map(|r| (r["thread"].as_i64().unwrap(), r["archived"]["by"].as_str().map(String::from))).collect();
        rows.sort();
        rows
    };
    assert_eq!(rows(t.get("/chats").await), vec![(own, None), (other, None)]);
    // A chat of its own goes alone.
    assert_eq!(t.call("POST", &format!("/threads/{other}/archive"), None).await.1["id"], json!(other));
    assert_eq!(rows(t.get("/chats").await), vec![(own, None)]);
    assert_eq!(rows(t.get("/chats?archived=1").await), vec![(other, Some("manual".into()))]);
    assert_eq!(t.get("/chats?archived=1").await[0]["archived"]["alone"], json!(true));
    assert_eq!(t.store.get_session(&key).unwrap().unwrap().archived_at, None);
    // A session's own chat goes with the session.
    t.call("POST", &format!("/threads/{own}/archive"), None).await;
    assert_eq!(rows(t.get("/chats").await), vec![]);
    assert_eq!(rows(t.get("/chats?archived=1").await), vec![(own, Some("manual".into())), (other, Some("manual".into()))]);
    assert!(t.store.get_session(&key).unwrap().unwrap().archived_at.is_some());
    t.call("DELETE", &format!("/threads/{own}/archive"), None).await;
    assert_eq!(rows(t.get("/chats").await), vec![(own, None)]);
    assert_eq!(t.call("POST", "/threads/99999/archive", None).await.0, 404);
}

#[tokio::test]
async fn chats_are_pinned_by_each_viewer_for_themselves() {
    let t = setup().await;
    let made = t.call("POST", "/sessions", Some(json!({ "runtime": "claude" }))).await.1;
    let key = made["key"].as_str().unwrap().to_string();
    let pinned = |v: Value, key: &str| v.as_array().unwrap().iter().find(|r| r["id"] == key).map(|r| r["pinned"].clone()).unwrap();
    assert_eq!(pinned(t.get("/chats").await, &key), Value::Null);
    let pin = format!("/sessions/{}/pin", enc(&key));
    assert_eq!(t.call("PUT", &pin, None).await, (200, json!({ "session": key, "pinned": true })));
    let at = pinned(t.get("/chats").await, &key);
    assert!(at.is_i64(), "when it was pinned: {at}");
    t.call("PUT", &pin, None).await;
    assert_eq!(pinned(t.get("/chats").await, &key), at, "pinned again, it keeps when it was first pinned");
    assert_eq!(pinned(t.call_as("GET", "/chats", None, dev()).await.1, &key), Value::Null, "another viewer's list is their own");
    assert_eq!(t.call("DELETE", &pin, None).await.0, 200);
    assert_eq!(pinned(t.get("/chats").await, &key), Value::Null);
    assert_eq!(t.call("PUT", "/sessions/nobody/pin", None).await.0, 404);
}

#[tokio::test]
async fn a_pending_decision_is_on_its_chats_row_and_each_viewer_dismisses_it_for_themselves() {
    let t = setup().await;
    let made = t.call("POST", "/sessions", Some(json!({ "runtime": "claude" }))).await.1;
    let key = made["key"].as_str().unwrap().to_string();
    let thread = made["thread"]["id"].as_i64().unwrap();
    t.call("POST", &format!("/threads/{thread}/messages"), Some(json!({ "text": "改一下统计" }))).await;
    let decision = |rows: Value| rows.as_array().unwrap().iter().find(|r| r["id"] == key).map(|r| r.get("decision").cloned().unwrap_or(Value::Null)).unwrap();
    assert_eq!(decision(t.get("/chats").await), Value::Null);
    t.store.insert_message(NewMessage::new(thread, "9.000001", AuthorKind::Agent, &key, "先看看")).unwrap();
    let options = json!([{ "label": "按今天累计", "recommended": true }, { "label": "先不改" }]);
    let (n, _) = t.store.insert_message(NewMessage { declared: Some("block".into()), options: Some(options.clone()), ..NewMessage::new(thread, "9.000002", AuthorKind::Agent, &key, "改成按今天累计吗？") }).unwrap();
    let d = decision(t.get("/chats").await);
    assert_eq!((d["seq"].clone(), d["options"].clone(), d.get("dismissed")), (json!(n), options.clone(), None));
    assert_eq!((d["message"]["seq"].clone(), d["message"]["text"].clone(), d["message"]["options"].clone()), (json!(n), json!("改成按今天累计吗？"), options.clone()));
    let before: Vec<Value> = d["before"].as_array().unwrap().iter().map(|m| m["text"].clone()).collect();
    assert_eq!(before, vec![json!("改一下统计"), json!("先看看")], "the two messages before it");
    // Its entry carries its options for the chat page.
    let entries = t.get(&format!("/threads/{thread}/entries")).await;
    assert_eq!(entries["entries"].as_array().unwrap().last().unwrap()["options"], options);
    // Dismissed by one viewer: on their rows as dismissed, on everyone else's as it was.
    let dismiss = format!("/threads/{thread}/dismissed");
    assert_eq!(t.call("PUT", &dismiss, Some(json!({ "n": n }))).await, (200, json!({ "dismissed": { "thread": thread, "n": n } })));
    assert_eq!(decision(t.get("/chats").await)["dismissed"], json!(true));
    assert_eq!(decision(t.call_as("GET", "/chats", None, dev()).await.1).get("dismissed"), None);
    assert_eq!(t.call("PUT", &dismiss, Some(json!({ "n": n - 2 }))).await.0, 404, "a message that asks nothing: a person's");
    assert_eq!(t.call("PUT", &dismiss, Some(json!({ "n": "x" }))).await.0, 400);
    // A person answers it: gone from every row.
    t.call_as("POST", &format!("/threads/{thread}/messages"), Some(json!({ "text": "先不改", "quotes": [{ "author": "agent", "text": "改成按今天累计吗？", "ts": "9.000002", "role": "agent" }] })), dev()).await;
    assert_eq!(decision(t.get("/chats").await), Value::Null);
    assert_eq!(decision(t.call_as("GET", "/chats", None, dev()).await.1), Value::Null);
}

#[tokio::test]
async fn a_chats_row_says_which_cards_its_viewer_answered_lately() {
    let t = setup().await;
    let made = t.call("POST", "/sessions", Some(json!({ "runtime": "claude" }))).await.1;
    let key = made["key"].as_str().unwrap().to_string();
    let thread = made["thread"]["id"].as_i64().unwrap();
    t.call("POST", &format!("/threads/{thread}/messages"), Some(json!({ "text": "发版" }))).await;
    let answered = |rows: Value| rows.as_array().unwrap().iter().find(|r| r["id"] == key).map(|r| r.get("answered").cloned().unwrap_or(Value::Null)).unwrap();
    let card = json!({ "type": "options", "options": [{ "label": "先发测试版" }, { "label": "直接发" }] });
    let (n, _) = t.store.insert_message(NewMessage { card: Some(card.clone()), ..NewMessage::new(thread, "9.000001", AuthorKind::Agent, &key, "先发测试版吗？") }).unwrap();
    assert_eq!(answered(t.get("/chats").await), Value::Null, "not answered yet");
    t.call("POST", &format!("/threads/{thread}/messages"), Some(json!({ "text": "先发测试版", "quotes": [{ "author": "agent", "text": "先发测试版吗？", "ts": "9.000001", "role": "agent" }] }))).await;
    // Said again after: the first answer only.
    t.call("POST", &format!("/threads/{thread}/messages"), Some(json!({ "text": "记得看录屏" }))).await;
    let a = answered(t.get("/chats").await);
    assert_eq!(a.as_array().map(Vec::len), Some(1));
    assert_eq!((a[0]["seq"].clone(), a[0]["text"].clone(), a[0]["card"].clone(), a[0]["reply"].clone(), a[0]["quoted"].clone()), (json!(n), json!("先发测试版吗？"), card, json!("先发测试版"), json!(true)));
    assert!(a[0]["answeredAt"].as_i64().unwrap() >= a[0]["askedAt"].as_i64().unwrap());
    // Someone else's rows: they answered nothing.
    assert_eq!(answered(t.call_as("GET", "/chats", None, dev()).await.1), Value::Null);
    // A card its agent withdrew was answered by no one.
    let (_, _) = t.store.insert_message(NewMessage { card: Some(json!({ "type": "text" })), ..NewMessage::new(thread, "9.000005", AuthorKind::Agent, &key, "标语？") }).unwrap();
    assert!(t.store.withdraw_card(&key, thread, "9.000005").unwrap());
    assert_eq!(answered(t.get("/chats").await).as_array().map(Vec::len), Some(1));
}

#[tokio::test]
async fn a_pending_card_is_on_its_chats_row_an_options_card_as_its_decision_too() {
    let t = setup().await;
    let made = t.call("POST", "/sessions", Some(json!({ "runtime": "claude" }))).await.1;
    let key = made["key"].as_str().unwrap().to_string();
    let thread = made["thread"]["id"].as_i64().unwrap();
    t.call("POST", &format!("/threads/{thread}/messages"), Some(json!({ "text": "上线" }))).await;
    let row = |rows: Value| rows.as_array().unwrap().iter().find(|r| r["id"] == key).cloned().unwrap();
    // An options card: `card`, and `decision` as before cards.
    let card = json!({ "type": "options", "options": [{ "label": "合", "recommended": true }] });
    let (n, _) = t.store.insert_message(NewMessage { card: Some(card.clone()), ..NewMessage::new(thread, "9.000001", AuthorKind::Agent, &key, "合吗？") }).unwrap();
    let r = row(t.get("/chats").await);
    assert_eq!((r["card"]["seq"].clone(), r["card"]["card"].clone(), r["card"]["message"]["card"].clone()), (json!(n), card.clone(), card.clone()));
    assert_eq!((r["decision"]["seq"].clone(), r["decision"]["options"].clone(), r["decision"].get("card")), (json!(n), card["options"].clone(), None));
    assert_eq!(r["decision"]["message"]["options"], card["options"]);
    // A text card: `card` only (clients from before cards know only options), and dismissed the same way.
    let text = json!({ "type": "text", "placeholder": "sk_test_…" });
    let (n, _) = t.store.insert_message(NewMessage { card: Some(text.clone()), ..NewMessage::new(thread, "9.000002", AuthorKind::Agent, &key, "key 是多少？") }).unwrap();
    let r = row(t.get("/chats").await);
    assert_eq!((r["card"]["seq"].clone(), r["card"]["card"].clone(), r.get("decision")), (json!(n), text.clone(), None));
    assert_eq!(r["card"]["message"].get("options"), None);
    let entries = t.get(&format!("/threads/{thread}/entries")).await;
    let last = entries["entries"].as_array().unwrap().last().unwrap().clone();
    assert_eq!((last["card"].clone(), last.get("options")), (text.clone(), None));
    assert_eq!(t.call("PUT", &format!("/threads/{thread}/dismissed"), Some(json!({ "n": n }))).await.0, 200);
    assert_eq!(row(t.get("/chats").await)["card"]["dismissed"], json!(true));
}

#[tokio::test]
async fn a_need_without_a_card_is_on_its_chats_row_until_someone_writes() {
    let t = setup().await;
    let made = t.call("POST", "/sessions", Some(json!({ "runtime": "claude" }))).await.1;
    let key = made["key"].as_str().unwrap().to_string();
    let thread = made["thread"]["id"].as_i64().unwrap();
    t.call("POST", &format!("/threads/{thread}/messages"), Some(json!({ "text": "接 Stripe" }))).await;
    let need = |rows: Value| rows.as_array().unwrap().iter().find(|r| r["id"] == key).map(|r| r.get("need").cloned().unwrap_or(Value::Null)).unwrap();
    // A turn that ends need_help, asking in words: the message it is about.
    t.store.start_turn("ask", &key, "message").unwrap();
    t.store.insert_message(NewMessage::new(thread, "9.000001", AuthorKind::Agent, &key, "先看看")).unwrap();
    let (n, _) = t.store.insert_message(NewMessage::new(thread, "9.000002", AuthorKind::Agent, &key, "要 Stripe 的测试 key")).unwrap();
    assert_eq!(need(t.get("/chats").await), Value::Null, "at work: nothing asked yet");
    t.store.set_about("ask", Some((thread, n, "9.000002"))).unwrap();
    t.store.end_turn("ask", "completed", None, Some("block"), None).unwrap();
    let d = need(t.get("/chats").await);
    assert_eq!((d["seq"].clone(), d["message"]["text"].clone(), d.get("dismissed")), (json!(n), json!("要 Stripe 的测试 key"), None));
    let before: Vec<Value> = d["before"].as_array().unwrap().iter().map(|m| m["text"].clone()).collect();
    assert_eq!(before, vec![json!("接 Stripe"), json!("先看看")]);
    // Dismissed by one viewer, as a card is.
    assert_eq!(t.call("PUT", &format!("/threads/{thread}/dismissed"), Some(json!({ "n": n }))).await.0, 200);
    assert_eq!(need(t.get("/chats").await)["dismissed"], json!(true));
    assert_eq!(need(t.call_as("GET", "/chats", None, dev()).await.1).get("dismissed"), None);
    // Someone writes: answered.
    t.call_as("POST", &format!("/threads/{thread}/messages"), Some(json!({ "text": "sk_test_1" })), dev()).await;
    assert_eq!(need(t.get("/chats").await), Value::Null);
    // Asked with a card: the card's, not a need.
    t.store.start_turn("card", &key, "message").unwrap();
    let (c, _) = t.store.insert_message(NewMessage { card: Some(json!({ "type": "text" })), ..NewMessage::new(thread, "9.000004", AuthorKind::Agent, &key, "key？") }).unwrap();
    t.store.set_about("card", Some((thread, c, "9.000004"))).unwrap();
    t.store.end_turn("card", "completed", None, Some("block"), None).unwrap();
    let rows = t.get("/chats").await;
    assert_eq!(need(rows.clone()), Value::Null);
    assert!(t.store.withdraw_card(&key, thread, "9.000004").unwrap());
    assert_eq!(need(t.get("/chats").await), Value::Null, "nor once its card is gone");
}

#[tokio::test]
async fn a_chat_is_renamed_by_hand_and_named_by_its_agent_or_first_message_again_when_the_name_is_cleared() {
    let t = setup().await;
    let made = t.call("POST", "/sessions", Some(json!({ "runtime": "claude" }))).await.1;
    let key = made["key"].as_str().unwrap().to_string();
    let own = made["thread"]["id"].as_i64().unwrap();
    t.call("POST", &format!("/threads/{own}/messages"), Some(json!({ "text": "修一下登录\n细节在后面" }))).await;
    let title = |t: &Value| t.as_array().unwrap().iter().find(|r| r["thread"] == json!(own)).unwrap()["title"].clone();
    assert_eq!(title(&t.get("/chats").await), json!("修一下登录"));
    let named = t.call("PUT", &format!("/threads/{own}/title"), Some(json!({ "title": "  登录排查  " }))).await;
    assert_eq!((named.0, named.1["title"].clone()), (200, json!("登录排查")));
    assert_eq!(title(&t.get("/chats").await), json!("登录排查"));
    let long = "长".repeat(100);
    t.call("PUT", &format!("/threads/{own}/title"), Some(json!({ "title": long }))).await;
    assert_eq!(title(&t.get("/chats").await).as_str().unwrap().chars().count(), 80);
    t.call("PUT", &format!("/threads/{own}/title"), Some(json!({ "title": "  " }))).await;
    assert_eq!(title(&t.get("/chats").await), json!("修一下登录"), "no name: its first line again");
    t.call("PUT", &format!("/threads/{own}/title"), Some(json!({ "title": null }))).await;
    assert_eq!(title(&t.get("/chats").await), json!("修一下登录"));
    // Its agent named it: that name, until people give one; cleared, the agent's again.
    t.store.set_auto_title(own, "登录超时", false).unwrap();
    assert_eq!(title(&t.get("/chats").await), json!("登录超时"));
    t.call("PUT", &format!("/threads/{own}/title"), Some(json!({ "title": "我的名字" }))).await;
    assert_eq!(title(&t.get("/chats").await), json!("我的名字"));
    t.call("PUT", &format!("/threads/{own}/title"), Some(json!({ "title": "" }))).await;
    assert_eq!(title(&t.get("/chats").await), json!("登录超时"));
    // Naming the session names its own chat too.
    t.call("POST", &format!("/sessions/{}/title", enc(&key)), Some(json!({ "title": "值班" }))).await;
    assert_eq!(title(&t.get("/chats").await), json!("值班"));
    assert_eq!(t.call("PUT", "/threads/99999/title", Some(json!({ "title": "x" }))).await.0, 404);
    t.hub.accept("ds", at("12.000001", "12.000001", "U42", "<@UBOT> hi", true)).await.unwrap();
    settle().await;
    let slack = t.store.list_threads("local", None, None).unwrap().into_iter().find(|x| x.thread.surface != crate::store::STILLFAIL_SURFACE).unwrap().thread.id;
    assert_eq!(t.call("PUT", &format!("/threads/{slack}/title"), Some(json!({ "title": "x" }))).await.0, 400, "a Slack thread is named in Slack");
}

#[tokio::test]
async fn events_announce_each_kind_of_change() {
    let quotas = Arc::new(AtomicUsize::new(0));
    let t = setup_with(Setup { quota: Some(quotas.clone()), ..Setup::default() }).await;
    t.get("/overview").await;
    assert_eq!(quotas.load(Ordering::SeqCst), 0, "quotas are not asked while nobody follows");
    let events = t.follow("/events", owner()).await;
    events.next("overview", |o| o["profiles"].as_array().unwrap().iter().any(|p| p["quota"]["windows"][0]["usedPercent"] == 12.0)).await;
    assert_eq!(quotas.load(Ordering::SeqCst), 2, "following starts a quota round");
    t.hub.accept("ds", at("8.000001", "8.000001", "U1", "<@UBOT> hi", true)).await.unwrap();
    let key = "ds:C1:8.000001";
    let session = events.next("session", |s| s["key"] == key && s["process"] == "running").await;
    assert_eq!(session["creator"]["via"], "slack");
    let thread = events.next("thread", |x| x["entries"].as_array().is_some_and(|e| e.len() == 1)).await;
    let e = &thread["entries"][0];
    assert_eq!((e["text"].clone(), e["authorKind"].clone(), e["n"].clone()), (json!("<@UBOT> hi"), json!("person"), json!(1)));
    events.next("overview", |o| o["counts"]["running"] == 1).await;
    let from = events.len();
    t.call("PUT", "/profiles/cx", Some(json!({ "name": "Codex 2" }))).await;
    events.next_from("overview", from, |o| o["profiles"].as_array().unwrap().iter().any(|p| p["name"] == "Codex 2")).await;
    let from = events.len();
    t.call("POST", "/profiles/cc/check", None).await;
    events.next_from("overview", from, |o| o["profiles"].as_array().unwrap().iter().find(|p| p["id"] == "cc").unwrap()["check"]["detail"] == "fake").await;
    t.claude.last().end(TurnOutcome::Aborted);
    events.next("overview", |o| o["counts"]["running"] == 0 && o["counts"]["warm"] == 1).await;
    t.call("DELETE", &format!("/sessions/{}", enc(key)), None).await;
    assert_eq!(events.next("session-removed", |_| true).await, json!({ "key": key }));
    assert_eq!(events.next("thread-removed", |_| true).await, json!({ "id": thread["id"] }));
    assert!(!events.all().iter().any(|(e, _)| e == "host"), "host only for those asking");
    let host = t.follow("/events?host=1", owner()).await;
    assert!(host.next("host", |_| true).await["cpus"].as_u64().unwrap() > 0);
}

#[tokio::test]
async fn profile_checks_and_quotas_are_kept_so_a_restart_shows_them_at_once() {
    let dir = tempfile::tempdir().unwrap();
    let db = dir.path().join("ember.db");
    {
        let store = Arc::new(Store::open(db.to_str().unwrap(), None).unwrap());
        let first = setup_with(Setup { store: Some(store), dir: Some(dir.path().to_path_buf()), quota: Some(Arc::default()), ..Setup::default() }).await;
        first.call("POST", "/profiles/cc/check", None).await;
        first.call("POST", "/profiles/cc/quota", None).await;
    }
    let store = Arc::new(Store::open(db.to_str().unwrap(), None).unwrap());
    let again = setup_with(Setup { store: Some(store), dir: Some(dir.path().to_path_buf()), ..Setup::default() }).await;
    let body = again.get("/overview").await;
    let cc = body["profiles"].as_array().unwrap().iter().find(|p| p["id"] == "cc").unwrap().clone();
    assert_eq!(cc["check"]["detail"], "fake");
    assert_eq!(cc["quota"]["windows"][0]["usedPercent"], 12.0);
}

#[tokio::test]
async fn the_sidebar_is_one_kind_of_item_an_agent_merged_with_its_internal_chat_a_slack_thread_only_lends_it_a_title_connect_and_origin() {
    let t = setup().await;
    t.hub.accept("ds", at("5.000001", "5.000001", "U42", "<@UBOT>  部署挂了\n第二行", true)).await.unwrap();
    settle().await;
    let slack_key = "ds:C1:5.000001";
    let origin = json!({ "teamName": "Acme", "channel": "C1", "channelName": null, "threadTs": "5.000001" });
    let starter = json!({ "id": "slack:ds:U42", "name": "U42", "email": null, "via": "slack" });
    let rows = || async { t.get("/chats").await.as_array().unwrap().clone() };
    let find = |rows: &[Value], id: &str| rows.iter().find(|r| r["id"] == id).cloned().unwrap();
    let mut agent_row = find(&rows().await, slack_key);
    let agents = agent_row["agents"].clone();
    let o = agent_row.as_object_mut().unwrap();
    o.remove("agents");
    o.remove("lastActiveAt");
    assert_eq!(
        agent_row,
        json!({
            "id": slack_key, "session": slack_key, "thread": null, "title": "部署挂了", "last": null, "unread": false, "mine": false, "connect": "ds", "origin": origin,
            // No chat yet: who started it is all who is in it.
            "creator": starter, "people": [starter], "pinned": null,
        })
    );
    let mut keys: Vec<&String> = agents[0].as_object().unwrap().keys().collect();
    keys.sort();
    assert_eq!(keys, ["effort", "key", "lastTurn", "model", "pending", "process", "runtime"]);
    assert_eq!(rows().await.len(), 1, "the Slack thread is no item of its own");

    // A chat made on ember: its item, from no connect. An item's id is its agent's session, chat or no chat.
    let made = t.call("POST", "/sessions", Some(json!({ "runtime": "claude" }))).await.1;
    let made_key = made["key"].as_str().unwrap().to_string();
    let own = find(&rows().await, &made_key);
    assert_eq!(
        vec![own["thread"].clone(), own["session"].clone(), own["title"].clone(), own["connect"].clone(), own["origin"].clone(), own["last"].clone(), own["mine"].clone()],
        vec![made["thread"]["id"].clone(), json!(made_key), json!("（还没有消息）"), Value::Null, Value::Null, Value::Null, json!(true)]
    );

    // The Slack agent's internal chat: the same item, now with its chat, titled by the Slack thread until it has words
    // of its own.
    let chat = t.call("POST", "/threads", Some(json!({ "session": slack_key }))).await.1;
    let chat_id = chat["id"].as_i64().unwrap();
    let list = rows().await;
    assert_eq!(list.iter().filter(|r| r["id"] == slack_key).count(), 1, "still one item, at the same id");
    let row = find(&list, slack_key);
    assert_eq!(row["thread"], chat_id);
    assert_eq!(
        vec![row["session"].clone(), row["title"].clone(), row["connect"].clone(), row["origin"].clone(), json!(ids(&row["agents"], "key"))],
        vec![json!(slack_key), json!("部署挂了"), json!("ds"), origin.clone(), json!([slack_key])]
    );
    t.hub.say(chat_id, "owner@example.com", "看看日志", vec![], vec![], None).unwrap();
    let row = find(&rows().await, slack_key);
    assert_eq!(
        vec![row["title"].clone(), row["last"]["text"].clone(), row["last"]["authorKind"].clone(), row["unread"].clone(), row["mine"].clone()],
        vec![json!("看看日志"), json!("看看日志"), json!("person"), json!(false), json!(true)]
    );
    // What the agent says is unread until read; the Slack thread's messages never show in the chat.
    let (said, _) = t.store.insert_message(NewMessage::new(chat_id, "9.000001", AuthorKind::Agent, slack_key, &"x".repeat(300))).unwrap();
    let row = find(&rows().await, slack_key);
    assert_eq!((row["unread"].clone(), row["last"]["text"].as_str().unwrap().chars().count(), row["last"]["seq"].clone()), (json!(true), 200, json!(said)));
    t.call("PUT", &format!("/threads/{chat_id}/read"), Some(json!({ "n": said }))).await;
    assert_eq!(find(&rows().await, slack_key)["unread"], false);
    assert_eq!(ids(&t.get(&format!("/threads/{chat_id}/entries")).await["entries"], "text"), vec![json!("看看日志"), json!("x".repeat(300))]);
    // Archived: its item goes.
    t.call("POST", &format!("/sessions/{}/archive", enc(slack_key)), None).await;
    assert_eq!(ids(&json!(rows().await), "id"), vec![json!(made_key)]);
}

#[tokio::test]
async fn a_viewer_can_say_a_slack_user_is_them_the_station_then_takes_that_user_for_the_viewer() {
    let t = setup().await;
    t.hub.accept("ds", at("6.000001", "6.000001", "U42", "<@UBOT> 看一下", true)).await.unwrap();
    t.hub.accept("ds", at("6.000002", "6.000001", "U7", "我也在", false)).await.unwrap();
    settle().await;
    let key = "ds:C1:6.000001";
    let mine = |viewer: Viewer| {
        let t = &t;
        async move { t.call_as("GET", "/chats", None, viewer).await.1.as_array().unwrap().iter().find(|r| r["session"] == key).unwrap()["mine"].clone() }
    };
    let slack_unread = |viewer: Viewer| {
        let t = &t;
        async move { t.call_as("GET", &format!("/threads?session={}", enc(key)), None, viewer).await.1[0]["unread"].clone() }
    };
    assert_eq!(mine(dev()).await, false);
    assert_eq!(slack_unread(dev()).await, 2);
    let dev_events = t.follow("/events", dev()).await;
    let local_events = t.follow("/events", owner()).await;

    // "这是我" on the session's creator: the agent's row is now the local viewer's, and only their stream hears of it.
    let bound = t.call("PUT", "/me/slack/U42", None).await.1;
    assert_eq!(bound["slackUsers"], json!(["U42"]));
    assert_eq!(mine(owner()).await, true);
    assert_eq!(mine(dev()).await, false, "bindings are per viewer");
    local_events.next("chat", |r| r["session"] == key && r["mine"] == true).await;
    local_events.next("overview", |o| o["slackUsers"].as_array().unwrap().iter().any(|u| u == "U42")).await;
    settle().await;
    assert!(!dev_events.all().iter().any(|(e, d)| e == "chat" && d["mine"] == true));
    // U7 only wrote in the Slack thread: their words are dev's own now, but the agent's row is not dev's — with no chat
    // yet, only whoever started the session counts.
    assert_eq!(t.call_as("PUT", "/me/slack/U7", None, dev()).await.1["slackUsers"], json!(["U7"]));
    assert_eq!(mine(dev()).await, false);
    assert_eq!(slack_unread(dev()).await, 1);
    dev_events.next("overview", |o| o["slackUsers"].as_array().unwrap().iter().any(|u| u == "U7")).await;
    assert_eq!(t.call_as("GET", "/overview", None, dev()).await.1["slackUsers"], json!(["U7"]));

    // "不是我": as before.
    t.call_as("DELETE", "/me/slack/U7", None, dev()).await;
    assert_eq!(mine(dev()).await, false);
    assert_eq!(slack_unread(dev()).await, 2);

    // Items change on the stream: the agent's item, once it has a chat, is the same item (its id is the session) with it.
    let from = local_events.len();
    let chat = t.call("POST", "/threads", Some(json!({ "session": key }))).await.1;
    let changed = local_events.next_from("chat", from, |r| r["thread"] == chat["id"]).await;
    assert_eq!((changed["id"].clone(), changed["title"].clone()), (json!(key), json!("看一下")));
    assert!(!local_events.all().iter().skip(from).any(|(e, _)| e == "chat-removed"), "nothing leaves the sidebar");
}

/// A web service on a port: it tells what it was asked (x-seen), refuses to be framed, and moves /old to /new.
async fn service() -> (u16, tokio::task::JoinHandle<()>) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let task = tokio::spawn(async move {
        loop {
            let Ok((mut socket, _)) = listener.accept().await else { return };
            tokio::spawn(async move {
                let mut got = Vec::new();
                let mut buf = [0u8; 4096];
                let head_end = loop {
                    let Ok(n) = socket.read(&mut buf).await else { return };
                    if n == 0 {
                        return;
                    }
                    got.extend_from_slice(&buf[..n]);
                    if let Some(i) = got.windows(4).position(|w| w == b"\r\n\r\n") {
                        break i;
                    }
                };
                let head = String::from_utf8_lossy(&got[..head_end]).into_owned();
                let mut lines = head.lines();
                let first = lines.next().unwrap_or("").to_string();
                let headers: HashMap<String, String> = lines.filter_map(|l| l.split_once(':')).map(|(k, v)| (k.trim().to_lowercase(), v.trim().to_string())).collect();
                let length: usize = headers.get("content-length").and_then(|l| l.parse().ok()).unwrap_or(0);
                let mut body = got[head_end + 4..].to_vec();
                while body.len() < length {
                    let Ok(n) = socket.read(&mut buf).await else { return };
                    if n == 0 {
                        break;
                    }
                    body.extend_from_slice(&buf[..n]);
                }
                let mut parts = first.split(' ');
                let (method, url) = (parts.next().unwrap_or(""), parts.next().unwrap_or(""));
                let response = if url == "/old" {
                    format!("HTTP/1.1 302 Found\r\nlocation: http://localhost:{port}/new?x=1\r\ncontent-length: 0\r\nconnection: close\r\n\r\n")
                } else {
                    let seen = format!(
                        "{method} {url} {} {} {}",
                        headers.get("host").map(String::as_str).unwrap_or("-"),
                        headers.get("traceparent").map(String::as_str).unwrap_or("-"),
                        String::from_utf8_lossy(&body)
                    );
                    let text = "hello from the service";
                    format!(
                        "HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\nx-frame-options: DENY\r\ncontent-security-policy: frame-ancestors 'none'\r\nx-seen: {seen}\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{text}",
                        text.len()
                    )
                };
                let _ = socket.write_all(response.as_bytes()).await;
            });
        }
    });
    (port, task)
}

#[tokio::test]
async fn a_web_service_on_the_machine_is_reached_through_preview_port_as_it_answers_framing_allowed() {
    let t = setup().await;
    let (port, task) = service().await;
    let req = Request::builder()
        .method("POST")
        .uri(format!("/admin/api/preview/{port}/a/b?q=1"))
        .header("traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01")
        .header("content-length", "3")
        .body(Full::new(Bytes::from_static(b"x=1")))
        .unwrap();
    let got = t.api.handle(req, owner()).await;
    assert_eq!(got.status(), 200);
    let header = |r: &Response<Body>, k: &str| r.headers().get(k).map(|v| v.to_str().unwrap().to_string());
    assert_eq!(header(&got, "x-seen"), Some(format!("POST /a/b?q=1 localhost:{port} - x=1")), "the path and query as asked, the service's own host, none of the admin call's headers");
    assert_eq!(header(&got, "x-frame-options"), None);
    assert_eq!(header(&got, "content-security-policy"), None);
    assert_eq!(String::from_utf8_lossy(&got.into_body().collect().await.unwrap().to_bytes()), "hello from the service");
    let moved = t.raw("GET", &format!("/preview/{port}/old"), Bytes::new(), owner()).await;
    assert_eq!(header(&moved, "location"), Some("/new?x=1".to_string()), "a redirect to the service stays on it");
    task.abort();
    let _ = task.await;
    tokio::time::sleep(Duration::from_millis(50)).await;
    let (status, text) = t.text("GET", &format!("/preview/{port}/"), "").await;
    assert_eq!(status, 502);
    assert!(text.contains(&format!("localhost:{port} 没有回应")), "{text}");
    assert_eq!(t.call("GET", "/preview/99999/", None).await.0, 404, "not a port");
}

/// This machine's CLIs, faked: Claude Code signed in with its login in a file; Codex signed in, its login not in a file.
fn fake_machine() -> (tempfile::TempDir, Arc<MachineLogins>) {
    let dir = tempfile::tempdir().unwrap();
    let bin = dir.path().join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    std::fs::create_dir_all(dir.path().join(".claude")).unwrap();
    std::fs::write(dir.path().join(".claude/.credentials.json"), json!({ "claudeAiOauth": { "accessToken": "fake-access", "expiresAt": now_ms() + 3_600_000 } }).to_string()).unwrap();
    use std::os::unix::fs::PermissionsExt;
    for (name, script) in [
        ("claude", "#!/bin/sh\necho '{\"loggedIn\": true, \"email\": \"b@x.com\", \"subscriptionType\": \"pro\"}'\n"),
        ("codex", "#!/bin/sh\necho 'Logged in using ChatGPT'\n"),
    ] {
        let path = bin.join(name);
        std::fs::write(&path, script).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
    }
    let env = BTreeMap::from([("HOME".to_string(), dir.path().to_string_lossy().into_owned()), ("PATH".to_string(), format!("{}:/usr/bin:/bin", bin.display()))]);
    (dir, MachineLogins::new(env, None))
}

#[tokio::test]
async fn a_profile_on_the_machines_own_login_made_from_a_login_kept_in_a_file_its_models_chosen_never_renamed_or_signed_in_and_stopped() {
    // (The TS test makes the Codex one; here it is Claude Code's, whose login is a file in a home of the test's own:
    // linking Codex's would reach this machine's real login.)
    let (_machine, logins) = fake_machine();
    let s = setup_with(Setup { machine: Some(logins), ..Setup::default() }).await;
    // Kept elsewhere than a file: not one to use.
    let keychain = s.call("POST", "/profiles/machine", Some(json!({ "runtime": "codex" }))).await;
    assert_eq!(keychain.0, 400);
    assert!(keychain.1["error"].as_str().unwrap().contains("钥匙串"), "{}", keychain.1);
    let made = s.call("POST", "/profiles/machine", Some(json!({ "runtime": "claude" }))).await;
    assert_eq!(made.0, 200, "{}", made.1);
    assert_eq!(made.1["id"], "machine-claude");
    let profile = |s: &Rig| s.config().profiles.iter().find(|p| p.id == "machine-claude").cloned().unwrap();
    assert!(profile(&s).machine);
    assert_eq!(profile(&s).name, "b@x.com（本机）");
    assert_eq!(profile(&s).access_kind, stillfail_shapes::AccessKind::Subscription);
    assert_eq!(s.call("POST", "/profiles/machine", Some(json!({ "runtime": "claude" }))).await.0, 409);
    // Only its models are chosen here.
    assert_eq!(s.call("PUT", "/profiles/machine-claude", Some(json!({ "name": "renamed", "models": ["claude-x"], "access": { "kind": "opencode-go", "key": "k" } }))).await.0, 200);
    assert_eq!(profile(&s).name, "b@x.com（本机）");
    assert_eq!(profile(&s).models, ["claude-x"]);
    assert_eq!(profile(&s).access_kind, stillfail_shapes::AccessKind::Subscription);
    assert!(profile(&s).machine);
    let body = s.get("/overview").await;
    assert_eq!(body["profiles"].as_array().unwrap().iter().find(|p| p["id"] == "machine-claude").unwrap()["machine"], true);
    // And how it runs: on by default, turned off and on here; other edits keep it.
    assert!(profile(&s).background_on_message);
    assert_eq!(s.call("PUT", "/profiles/machine-claude", Some(json!({ "backgroundOnMessage": false }))).await.0, 200);
    assert!(!profile(&s).background_on_message);
    assert_eq!(s.call("PUT", "/profiles/machine-claude", Some(json!({ "models": ["claude-y"] }))).await.0, 200);
    let body = s.get("/overview").await;
    assert_eq!(body["profiles"].as_array().unwrap().iter().find(|p| p["id"] == "machine-claude").unwrap()["backgroundOnMessage"], false);
    assert_eq!(s.call("PUT", "/profiles/machine-claude", Some(json!({ "backgroundOnMessage": true }))).await.0, 200);
    assert!(profile(&s).background_on_message);
    assert_eq!(s.call("POST", "/profiles/machine-claude/login", None).await.0, 400);
    // Stopped: the profile goes; it can be made again from the machine's login.
    assert_eq!(s.call("DELETE", "/profiles/machine-claude", None).await.0, 200);
    assert!(!s.config().profiles.iter().any(|p| p.id == "machine-claude"));
    assert_eq!(s.call("POST", "/profiles/machine", Some(json!({ "runtime": "claude" }))).await.0, 200);
}

#[tokio::test]
async fn a_profile_just_made_has_its_allowance_read_at_once_without_waiting_for_a_round() {
    let quotas = Arc::new(AtomicUsize::new(0));
    let t = setup_with(Setup { quota: Some(quotas.clone()), ..Setup::default() }).await;
    let made = t.call("PUT", "/profiles/linked", Some(json!({ "name": "Linked", "runtime": "codex", "access": { "kind": "subscription" }, "home": "homes/linked" }))).await;
    assert_eq!(made.0, 200);
    for _ in 0..50 {
        if quotas.load(Ordering::SeqCst) > 0 {
            break;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    assert_eq!(quotas.load(Ordering::SeqCst), 1);
    let body = t.get("/overview").await;
    assert_eq!(body["profiles"].as_array().unwrap().iter().find(|p| p["id"] == "linked").unwrap()["quota"]["windows"][0]["usedPercent"], 12.0);
}

#[tokio::test]
async fn the_slack_people_of_the_stations_connects_are_listed_once_each_by_email_bots_and_the_deactivated_left_out_guests_marked() {
    let s = setup().await;
    s.connection(0).answers.lock().unwrap().insert(
        "users.list".into(),
        json!({ "ok": true, "members": [
            { "id": "U1", "profile": { "real_name": "Ada", "email": "Ada@Example.test", "image_72": "https://img/ada" } },
            { "id": "U2", "is_bot": true, "profile": { "real_name": "Bot", "email": "bot@example.test" } },
            { "id": "U3", "deleted": true, "profile": { "real_name": "Gone", "email": "gone@example.test" } },
            { "id": "U4", "is_restricted": true, "profile": { "real_name": "Guest", "email": "guest@example.test" } },
            { "id": "U5", "profile": { "real_name": "No email" } },
            { "id": "USLACKBOT", "profile": { "real_name": "Slackbot", "email": "slackbot@example.test" } },
        ] }),
    );
    let (status, body) = s.call("GET", "/slack/people", None).await;
    assert_eq!(status, 200);
    let people: Vec<Value> = body["people"].as_array().unwrap().iter().map(|p| json!([p["email"], p["name"], p["guest"], p["team"]])).collect();
    assert_eq!(people, vec![json!(["ada@example.test", "Ada", false, "Acme"]), json!(["guest@example.test", "Guest", true, "Acme"])]);
    assert_eq!(body["errors"], json!([]));
}

#[tokio::test]
async fn the_agents_memory_is_shown_on_the_pages_global_and_projects() {
    let r = setup().await;
    let home = r.settings.config().agent_home.clone();
    std::fs::create_dir_all(home.join("skills").join("发版")).unwrap();
    std::fs::write(home.join("MEMORY.md"), "# ember memory\n- 用中文回复\n").unwrap();
    std::fs::write(home.join("skills").join("发版").join("SKILL.md"), "---\nname: 发版\ndescription: 项目记忆：每周发版时使用。\n---\n\n- 周四发\n").unwrap();
    let memory = r.get("/memory").await;
    assert_eq!(memory["global"]["text"], "# ember memory\n- 用中文回复\n");
    assert!(memory["skills"].as_array().unwrap().iter().any(|s| s["name"] == "发版" && s["project"] == true));
    let (status, _) = r.call("PUT", "/memory/global", Some(json!({ "text": "x" }))).await;
    assert_ne!(status, 200, "the pages only read it");
}

#[tokio::test]
async fn a_widgets_state_is_kept_for_its_session_and_its_model_rides_along_with_the_next_messages_once() {
    let t = setup().await;
    let route = |key: &str| format!("/sessions/{}/widget-state", enc(key));
    assert_eq!(t.call("PUT", &route("nobody"), Some(json!({ "path": "/x.html", "state": {} }))).await.0, 404);
    assert_eq!(t.call("GET", &format!("{}?path=%2Fx.html", route("nobody")), None).await.0, 404);
    let made = t.call("POST", "/sessions", Some(json!({ "runtime": "claude" }))).await.1;
    let key = made["key"].as_str().unwrap().to_string();
    let chat_id = made["thread"]["id"].as_i64().unwrap();
    let thread_ts = made["thread"]["threadTs"].as_str().unwrap().to_string();
    let path = "/w/uploads/pick.html";
    let mut posted = NewMessage::new(chat_id, "9.1", AuthorKind::Agent, &key, "![](pick.html)");
    posted.attachments = vec![Attachment { name: "pick.html".into(), path: path.into(), size: 9, width: None, height: None, thumbhash: None }];
    t.store.insert_message(posted).unwrap();
    let get = format!("{}?path={}", route(&key), enc(path));
    assert_eq!(t.get(&get).await, json!({ "state": null }));
    let big = "x".repeat(16384);
    assert_eq!(t.call("PUT", &route(&key), Some(json!({ "path": path, "state": { "privateContent": big } }))).await.0, 400);
    let state = json!({ "modelContent": "chose red", "privateContent": { "tab": 2 } });
    assert_eq!(t.call("PUT", &route(&key), Some(json!({ "path": path, "state": state }))).await, (200, json!({ "ok": true })));
    assert_eq!(t.get(&get).await, json!({ "state": state }));
    settle().await;
    assert!(t.claude.sessions.lock().unwrap().is_empty(), "a widget's state starts no turn");
    let say = |text: &'static str| {
        let t = &t;
        async move { t.call("POST", &format!("/threads/{chat_id}/messages"), Some(json!({ "text": text }))).await }
    };
    say("好了").await;
    settle().await;
    let section = format!("A widget you posted has state for you (the person's choices in it; not a message to answer by itself):\n- pick.html in EMBER/{thread_ts}: chose red");
    assert!(t.claude.last().told().contains(&format!("好了\n</message>\n\n{section}")), "{}", t.claude.last().told());
    say("还有").await;
    settle().await;
    assert!(t.claude.last().told().contains("还有"));
    assert_eq!(t.claude.last().told().matches("A widget you posted").count(), 1, "told once");
}

#[tokio::test]
async fn a_jobs_log_asked_for_on_the_events_stream_comes_at_once_and_again_as_it_grows() {
    let t = setup().await;
    let log = t.data.join("j1.log");
    std::fs::write(&log, "one\ntwo\nthree\n").unwrap();
    let job = crate::store::JobRow {
        id: "j1".into(),
        session_key: "nobody".into(),
        name: "build".into(),
        command: "make".into(),
        cwd: "/".into(),
        port: None,
        token: "t".into(),
        state: "running".into(),
        pgid: None,
        exit_code: None,
        started_at: now_ms(),
        ended_at: None,
        restarts: 0,
        log: log.to_string_lossy().into_owned(),
        watch: false,
    };
    t.store.insert_job(&job).unwrap();
    // Read by itself, it says the stream follows it (a client that knows needs no reading again).
    let read = t.get("/jobs/j1/log?lines=1").await;
    assert_eq!((read["text"].clone(), read["follows"].clone()), (json!("three"), json!(true)));
    // A job nobody has is left out; the one asked for comes with the lines asked for, then as it grows.
    let events = t.follow("/events?job=gone&lines=5&job=j1&lines=2", owner()).await;
    let first = events.next("job-log", |_| true).await;
    assert_eq!((first["id"].clone(), first["lines"].clone(), first["text"].clone()), (json!("j1"), json!(2), json!("two\nthree")));
    assert!(first["outputAt"].as_i64().is_some());
    let from = events.len();
    std::io::Write::write_all(&mut std::fs::OpenOptions::new().append(true).open(&log).unwrap(), b"four\n").unwrap();
    let grown = events.next_from("job-log", from, |_| true).await;
    assert_eq!(grown["text"], "three\nfour");
    // Nothing new: nothing sent.
    tokio::time::sleep(Duration::from_millis(1500)).await;
    assert_eq!(events.all().iter().filter(|(e, _)| e == "job-log").count(), 2);
}

fn member(role: &str) -> Viewer {
    Viewer::Mesh { sub: "s".into(), email: "m@x.com".into(), name: "M".into(), role: role.into(), workspace: "ws".into(), device: "d".into() }
}

#[tokio::test]
async fn the_update_channel_is_said_with_the_versions_and_set_by_an_admin() {
    let s = setup_with(Setup { updates: Some(Some("beta")), ..Default::default() }).await;
    s.call("POST", "/updates/check", None).await;
    let station = |updates: &Value| updates.as_array().unwrap().iter().find(|v| v["id"] == "station").cloned().unwrap();
    let overview = s.get("/overview").await;
    assert_eq!(station(&overview["updates"])["channel"], "beta", "installed from the beta, on it");

    // A member may not; nor a channel that is not one.
    let (status, _) = s.call_as("POST", "/updates/channel", Some(json!({ "channel": "stable" })), member("member")).await;
    assert_eq!(status, 403);
    let (status, _) = s.call_as("POST", "/updates/channel", Some(json!({ "channel": "nightly" })), member("admin")).await;
    assert_eq!(status, 400);

    let (status, updates) = s.call_as("POST", "/updates/channel", Some(json!({ "channel": "stable" })), member("admin")).await;
    assert_eq!(status, 200, "{updates}");
    assert_eq!(station(&updates)["channel"], "stable");
    assert_eq!(s.settings.raw().update_channel.as_deref(), Some("stable"));
    let overview = s.get("/overview").await;
    assert_eq!(station(&overview["updates"])["channel"], "stable");
}

#[tokio::test]
async fn updating_by_itself_is_said_with_the_versions_and_turned_on_by_an_admin() {
    let s = setup_with(Setup { updates: Some(None), ..Default::default() }).await;
    s.call("POST", "/updates/check", None).await;
    let station = |updates: &Value| updates.as_array().unwrap().iter().find(|v| v["id"] == "station").cloned().unwrap();
    assert_eq!(station(&s.get("/overview").await["updates"])["auto"], false, "off unless turned on");

    let (status, _) = s.call_as("POST", "/updates/auto", Some(json!({ "on": true })), member("member")).await;
    assert_eq!(status, 403);
    let (status, _) = s.call_as("POST", "/updates/auto", Some(json!({ "on": "yes" })), member("admin")).await;
    assert_eq!(status, 400);

    let (status, updates) = s.call_as("POST", "/updates/auto", Some(json!({ "on": true })), member("admin")).await;
    assert_eq!(status, 200, "{updates}");
    assert_eq!(station(&updates)["auto"], true);
    assert_eq!(s.settings.raw().auto_update, Some(true));
    let (_, updates) = s.call_as("POST", "/updates/auto", Some(json!({ "on": false })), member("admin")).await;
    assert_eq!(station(&updates)["auto"], false);
    assert_eq!(station(&s.get("/overview").await["updates"])["auto"], false);
}

#[tokio::test]
async fn a_station_with_nothing_to_update_has_no_channel_to_set() {
    let s = setup().await;
    let (status, _) = s.call("POST", "/updates/channel", Some(json!({ "channel": "beta" }))).await;
    assert_eq!(status, 404);
}

#[tokio::test]
async fn retired_footprint_does_not_offer_stats_or_cleanup() {
    let t = setup().await;
    assert!(t.get("/overview").await["footprint"].is_null());
    let view = t.get("/footprint").await;
    assert_eq!(view["scanning"], json!(false));
    assert_eq!(view["manage"], json!(false));
    assert_eq!(view["chats"], json!([]));
    for action in ["scan", "rebuild", "delete", "evict"] {
        assert_eq!(t.call("POST", &format!("/footprint/{action}"), Some(json!({}))).await.0, 410);
    }
}

#[tokio::test]
async fn connect_depth_uses_model_capabilities_and_survives_config_reload() {
    let t = setup().await;
    t.settings.update(|raw| {
        raw.profiles.as_mut().unwrap().iter_mut().find(|p| p.id == "cx").unwrap().models = Some(vec!["gpt-6-astra".into()]);
        Ok(())
    }).unwrap();
    let check: ProfileCheck = serde_json::from_value(json!({
        "state": "ok", "detail": "", "models": ["gpt-6-astra"], "checkedAt": 1,
        "modelEfforts": {"codex": {"gpt-6-astra": ["low", "medium", "high", "xhigh", "max", "ultra"]}}
    })).unwrap();
    t.api.checks.lock().unwrap().insert("cx".into(), check.clone());
    t.store.set_profile_check("cx", &serde_json::to_value(&check).unwrap()).unwrap();
    let body = |effort: &str| json!({"bind": {"runtime": "codex", "model": "gpt-6-astra", "effort": effort}});
    let (status, _) = t.call("PUT", "/connects/astra", Some(body("max"))).await;
    assert_eq!(status, 200);
    assert_eq!(t.saved()["connects"][1]["bind"]["effort"], "max");
    assert_eq!(t.call("PUT", "/connects/astra", Some(body("minimal"))).await.0, 400);
    assert_eq!(t.call("PUT", "/connects/astra", Some(body("ultra"))).await.0, 200);
    let raw = serde_json::from_value(t.saved()).unwrap();
    let reloaded = crate::config::parse_config(&raw, t.path.parent().unwrap()).unwrap();
    assert_eq!(reloaded.connects[1].bind.effort.as_deref(), Some("ultra"));
    let saved = t.store.profile_status().unwrap().remove("cx").unwrap().check.unwrap();
    let restored: ProfileCheck = serde_json::from_value(saved).unwrap();
    assert_eq!(restored.model_efforts, check.model_efforts);
    let old: ProfileCheck = serde_json::from_value(json!({"state": "ok", "detail": "", "checkedAt": 0})).unwrap();
    assert!(old.model_efforts.is_none());
}

#[tokio::test]
async fn answering_a_card_reads_only_that_question_for_its_viewer() {
    for extra in [false, true] {
        let t = setup().await;
        let (key, thread) = t.hub.new_session(NewChat { fast: None, runtime: RuntimeKind::Claude, profile: None, model: None, effort: None, title: None, created_by: "owner@example.com".into(), client_key: None }).unwrap();
        let (asked, _) = t.store.insert_message(NewMessage { card: Some(json!({"type":"text"})),
            ..NewMessage::new(thread.id, "9.000001", AuthorKind::Agent, &key, "怎么处理？") }).unwrap();
        if extra {
            t.store.insert_message(NewMessage::new(thread.id, "9.000002", AuthorKind::Agent, &key, "补充消息")).unwrap();
        }
        let events = t.follow("/events", owner()).await;
        let path = format!("/threads/{}/messages", thread.id);
        assert_eq!(t.call("POST", &path, Some(json!({"text":"按计划做", "quotes":[{"ts":"9.000001", "text":"怎么处理？", "author":"agent", "role":"agent"}]}))).await.0, 200);
        assert_eq!(t.store.read_position("owner@example.com", thread.id).unwrap(), asked);
        assert_eq!(t.store.read_position("dev@example.com", thread.id).unwrap(), 0);
        assert_eq!(events.next("read", |_| true).await["n"], asked);
        let summary = t.get(&format!("/threads/{}", thread.id)).await;
        assert_eq!(summary["unread"], if extra { 1 } else { 0 });
    }
}

#[tokio::test]
async fn closing_a_question_clears_its_wait_without_a_message_or_delivery() {
    let t = setup().await;
    let made = t.call("POST", "/sessions", Some(json!({ "runtime": "claude" }))).await.1;
    let key = made["key"].as_str().unwrap().to_string();
    let thread = made["thread"]["id"].as_i64().unwrap();
    let row = |rows: Value| rows.as_array().unwrap().iter().find(|r| r["id"] == key).cloned().unwrap();
    let card = json!({ "type": "options", "options": [{ "label": "部署" }, { "label": "不需要部署", "action": "close" }] });
    t.store.start_turn("close-test", &key, "message").unwrap();
    let (n, _) = t.store.insert_message(NewMessage { card: Some(card.clone()), ..NewMessage::new(thread, "9.000001", AuthorKind::Agent, &key, "需要部署吗？") }).unwrap();
    t.store.set_about("close-test", Some((thread, n, "9.000001"))).unwrap();
    t.store.set_need("close-test", "决定是否部署").unwrap();
    let path = format!("/threads/{thread}/closed-card");
    assert_eq!(t.call("PUT", &path, Some(json!({"n": n, "option": "不需要部署"}))).await.0, 409, "cannot race an unfinished turn");
    t.store.end_turn("close-test", "completed", None, Some("block"), None).unwrap();
    assert_eq!(t.call("PUT", &path, Some(json!({"n": n, "option": "部署"}))).await.0, 409, "ordinary options cannot close");
    assert_eq!(t.call("PUT", &path, Some(json!({"n": n}))).await.0, 400, "no generic close action");
    assert_eq!(t.call("POST", &format!("/threads/{thread}/messages"), Some(json!({"text": "不需要部署", "quotes": [{"ts":"9.000001", "text":"需要部署吗？", "author":"agent", "role":"agent"}]}))).await.0, 409, "old cores must not send silent options to the agent");
    let entries = t.get(&format!("/threads/{thread}/entries")).await;
    let pending = t.store.pending_messages(&key).unwrap().len();
    assert_eq!(t.call("PUT", &path, Some(json!({"n": n, "option": "不需要部署"}))).await.0, 200);
    assert_eq!(t.store.read_position("owner@example.com", thread).unwrap(), n);
    assert_eq!(t.store.read_position("dev@example.com", thread).unwrap(), 0);
    assert_eq!(row(t.get("/chats").await)["unread"], false);
    assert!(row(t.get("/chats").await).get("card").is_none());
    assert!(row(t.call_as("GET", "/chats", None, dev()).await.1).get("card").is_none(), "closed for every viewer");
    let turn = t.store.last_turn(&key).unwrap().unwrap();
    assert_eq!(turn.ending.as_deref(), Some("all_done"));
    assert_eq!(turn.need.as_deref(), Some("用户选择「不需要部署」"));
    assert_eq!(t.get(&format!("/threads/{thread}/entries")).await, entries, "no message posted");
    assert_eq!(t.store.pending_messages(&key).unwrap().len(), pending, "no agent delivery");
    assert_eq!(t.call("PUT", &path, Some(json!({"n": n, "option": "不需要部署"}))).await.0, 200, "retry is idempotent");
    assert_eq!(t.call("PUT", &path, Some(json!({"n": "bad"}))).await.0, 400);
    // A newer turn and card still wait; retrying the old close cannot touch them.
    t.store.start_turn("close-next", &key, "message").unwrap();
    let (next, _) = t.store.insert_message(NewMessage { card: Some(card.clone()), ..NewMessage::new(thread, "9.000002", AuthorKind::Agent, &key, "另一个问题") }).unwrap();
    t.store.set_about("close-next", Some((thread, next, "9.000002"))).unwrap();
    t.store.end_turn("close-next", "completed", None, Some("block"), None).unwrap();
    assert_eq!(t.call("PUT", &path, Some(json!({"n": n, "option": "不需要部署"}))).await.0, 200);
    assert_eq!(t.store.read_position("owner@example.com", thread).unwrap(), n, "retry does not read the newer question");
    assert_eq!(row(t.get("/chats").await)["unread"], true);
    assert_eq!(row(t.get("/chats").await)["card"]["seq"], next);
    assert_eq!(t.store.last_turn(&key).unwrap().unwrap().ending.as_deref(), Some("need_help"));
    let (newest, _) = t.store.insert_message(NewMessage { card: Some(card), ..NewMessage::new(thread, "9.000003", AuthorKind::Agent, &key, "换了一个问题") }).unwrap();
    assert_eq!(t.call("PUT", &path, Some(json!({"n": next, "option": "不需要部署"}))).await.0, 409, "stale card cannot close the newer question");
    assert_eq!(row(t.get("/chats").await)["card"]["seq"], newest);
    // Closing a newer card must not rewrite a turn whose state refers to another question.
    assert_eq!(t.call("PUT", &path, Some(json!({"n": newest, "option": "不需要部署"}))).await.0, 200);
    assert_eq!(t.store.last_turn(&key).unwrap().unwrap().ending.as_deref(), Some("need_help"));
}

#[tokio::test]
async fn keeping_a_chat_suppresses_only_this_viewers_archive_reminder() {
    let t = setup().await;
    let made = t.call("POST", "/sessions", Some(json!({"runtime": "claude"}))).await.1;
    let thread = made["thread"]["id"].as_i64().unwrap();
    let row = |rows: Value| rows.as_array().unwrap().iter().find(|r| r["thread"] == thread).unwrap().clone();
    assert_eq!(row(t.get("/chats").await)["archiveReminderDismissed"], false);
    for _ in 0..2 {
        assert_eq!(t.call("PUT", &format!("/threads/{thread}/keep"), None).await.0, 200);
    }
    assert_eq!(row(t.get("/chats").await)["archiveReminderDismissed"], true);
    assert_eq!(row(t.call_as("GET", "/chats", None, dev()).await.1)["archiveReminderDismissed"], false);
    assert!(t.store.kept_chats(None).unwrap().contains(&thread));
    assert_eq!(t.store.get_thread(thread).unwrap().unwrap().hidden_at, None);
}

#[tokio::test]
async fn openai_reset_keeps_its_redemption_key_and_refreshes_even_without_a_reset() {
    let keys = Arc::new(Mutex::new(Vec::<String>::new()));
    let seen = keys.clone();
    let reads = Arc::new(AtomicUsize::new(0));
    let t = setup_with(Setup { quota: Some(reads.clone()), reset_quota: Some(Arc::new(move |p, key| {
        assert_eq!(p.id, "cx");
        seen.lock().unwrap().push(key.clone());
        Box::pin(async move { Ok(json!({"outcome": match key.as_str() { "empty" => "noCredit", "unused" => "nothingToReset", "again" => "alreadyRedeemed", _ => "reset" }})) })
    })), ..Setup::default() }).await;
    t.call("PUT", "/profiles/cx", Some(json!({"access":{"kind":"subscription"}}))).await;
    let redeem = |id: &'static str, key: &'static str| {
        let t = &t;
        async move {
            let req = Request::builder().method("POST").uri(format!("/admin/api/profiles/{id}/reset-quota"))
                .header("idempotency-key", key).body(Full::new(Bytes::new())).unwrap();
            t.api.handle(req, owner()).await.status().as_u16()
        }
    };
    assert_eq!(t.call("POST", "/profiles/cx/reset-quota", None).await.0, 400);
    assert_eq!(redeem("cc", "wrong-provider").await, 400);
    let (a, b) = tokio::join!(redeem("cx", "one"), redeem("cx", "one"));
    assert_eq!((a,b), (200,200));
    assert_eq!(keys.lock().unwrap().as_slice(), ["one"]);
    assert_eq!(redeem("cx", "again").await, 200);
    assert_eq!(redeem("cx", "empty").await, 409);
    assert_eq!(redeem("cx", "unused").await, 409);
    assert!(reads.load(Ordering::SeqCst) >= 4);
}

#[tokio::test]
async fn openai_fast_defaults_off_survives_other_edits_and_can_be_disabled() {
    let t = setup().await;
    let profile = || t.config().profiles.iter().find(|p| p.id == "cx").cloned().unwrap();
    assert!(!profile().fast);
    assert_eq!(t.call("PUT", "/profiles/cx", Some(json!({"fast": true, "access":{"kind":"subscription"}}))).await.0, 200);
    assert!(profile().fast);
    t.call("PUT", "/profiles/cx", Some(json!({"name": "OpenAI"}))).await;
    assert!(profile().fast);
    t.call("PUT", "/profiles/cx", Some(json!({"fast": false}))).await;
    assert!(!profile().fast);
    assert_eq!(t.call("PUT", "/profiles/cx", Some(json!({"fast": "yes"}))).await.0, 400);
}

#[tokio::test]
async fn archived_attachments_remain_readable_without_expanding_the_workspace() {
    let t = setup().await;
    let (key, _) = t.hub.new_session(NewChat { runtime: RuntimeKind::Claude, profile: None, model: None,
        effort: None, fast: None, title: None, created_by: "local".into(), client_key: None }).unwrap();
    let workspace = PathBuf::from(t.store.get_session(&key).unwrap().unwrap().workspace);
    std::fs::create_dir_all(workspace.join("uploads")).unwrap();
    std::fs::write(workspace.join("uploads/evidence.txt"), b"original evidence").unwrap();
    t.hub.archive(&key, true).unwrap();
    t.hub.finish_archive(&key).await.unwrap();
    assert!(!workspace.join("uploads/evidence.txt").exists());
    assert_eq!(t.text("GET", &format!("/sessions/{}/files?name=evidence.txt", enc(&key)), "").await,
        (200, "original evidence".to_string()));
    assert!(!workspace.join("uploads/evidence.txt").exists(), "viewing does not unpack the workspace");
    assert_eq!(t.call("DELETE", &format!("/sessions/{}/archive", enc(&key)), None).await.0, 200);
    assert_eq!(std::fs::read(workspace.join("uploads/evidence.txt")).unwrap(), b"original evidence");
}

#[tokio::test]
async fn automatic_decisions_configure_purpose_and_model_without_separate_credentials() {
    use crate::decision::{Provider, profiles::{Capability, fingerprint}};
    let t=setup().await;
    assert_eq!(t.get("/overview").await["automaticDecisions"]["settings"]["completion"]["enabled"],false);
    let input=json!({"completion":{"enabled":true,"model":"gpt-6-luna"}});
    assert_eq!(t.call_as("PUT","/automatic-decisions",Some(input.clone()),member("member")).await.0,403);
    assert_eq!(t.call("PUT","/automatic-decisions",Some(input.clone())).await.0,400);
    t.settings.update(|raw| {
        let profile=raw.profiles.as_mut().unwrap().iter_mut().find(|p|p.id=="cx").unwrap();
        profile.env=Some(BTreeMap::from([("OPENAI_API_KEY".into(),"private-existing-key".into())]));
        Ok(())
    }).unwrap();
    let profile=t.config().profiles.iter().find(|p|p.id=="cx").unwrap().clone();
    let capability=Capability {state:"ready".into(),detail:"verified".into(),model:Some("gpt-6-luna".into()),
        models:vec!["gpt-6-luna".into(),"gpt-6-sol".into()],provider:Some(Provider::ChatLogprobs),fingerprint:fingerprint(&profile)};
    let check=ProfileCheck {decision:Some(capability),model_efforts:None,state:"ok".into(),detail:String::new(),models:None,checked_at:0};
    t.api.checks.lock().unwrap().insert("cx".into(),check);
    let (status,view)=t.call("PUT","/automatic-decisions",Some(input.clone())).await;
    assert_eq!(status,200,"{view}");
    assert_eq!(view["automaticDecisions"]["models"].as_array().unwrap().len(),2);
    stillfail_shapes::conform::<stillfail_shapes::AutomaticDecisionView>(view["automaticDecisions"].clone()).unwrap();
    assert!(!view["automaticDecisions"].to_string().contains("private-existing-key"));
    assert_eq!(t.saved()["automaticDecisions"],input);
    assert_eq!(t.call("PUT","/automatic-decisions",Some(json!({"completion":{"enabled":true,"model":"invented"}}))).await.0,400);
    assert_eq!(t.call("PUT","/automatic-decisions",Some(json!({"completion":{"enabled":false,"model":"gpt-6-luna"},"apiKey":"not-accepted"}))).await.0,400);
    assert_eq!(t.call("PUT","/automatic-decisions",Some(json!({"completion":{"enabled":false,"model":"gpt-6-luna"}}))).await.0,200);
    assert!(!t.config().automatic_decisions.completion.enabled);
}
