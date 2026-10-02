//! Codex driver: one shared `codex app-server` per profile, one thread per session.
//!
//! Pinned by spikes (spike/README.md):
//! - a thread adds <1MB to its app-server, so sessions share one process;
//! - per-session settings (the MCP endpoint and token) travel in the thread/start|resume `config`, not the process
//!   environment;
//! - threads need sandbox "danger-full-access" with approvalPolicy "never", or MCP tool calls are refused.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use async_trait::async_trait;
use stillfail_shapes::RuntimeKind;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tokio::sync::{Mutex as AsyncMutex, oneshot};
use tracing::{debug, info, warn};

use super::process::{GroupProcess, HandedProcess, Spawn, adopt_group, spawn_group};
use super::{AgentDriver, AgentSession, Events, FailureReason, LiveEvent, LiveField, LivePhase, LiveStepKind, OpenOptions, RuntimeEvent, TurnOutcome, clean_env};
use crate::config::{Profile, expand_route};
use crate::machine_logins::{link_codex_auth, process_env};
use crate::profiles::codex_overrides;
use crate::store::Store;

const SCRUBBED: [&str; 2] = ["OPENAI_API_KEY", "CODEX_HOME"];

/// Codex otherwise reads the system's root certificates for each new connection. On macOS, from a process outside the
/// desktop session, that can take seconds or hang past its 15 s request timeout, and fail with UnknownIssuer.
/// SSL_CERT_FILE makes it use a CA file instead, for its model websocket as well as its HTTP clients. One the user set
/// wins.
const CA_BUNDLE: &str = "/etc/ssl/cert.pem";

pub fn with_ca_bundle(env: &mut BTreeMap<String, String>, bundle: &Path) {
    if ["SSL_CERT_FILE", "SSL_CERT_DIR", "CODEX_CA_CERTIFICATE"].iter().any(|k| env.contains_key(*k)) || !bundle.exists() {
        return;
    }
    env.insert("SSL_CERT_FILE".into(), bundle.display().to_string());
}

/// Codex also loads the skills in the user's own ~/.agents/skills. The station's agents share skills through the agent
/// home instead, and the personal ones pull them off course, so each is turned off by path: codex's skills.config takes
/// files, not directories.
pub fn host_skills_off(root: &Path) -> Vec<Value> {
    fn walk(dir: &Path, depth: usize, visited: &mut HashSet<PathBuf>, found: &mut Vec<PathBuf>) {
        if depth > 6 {
            return;
        }
        let Ok(real) = std::fs::canonicalize(dir) else { return };
        if !visited.insert(real) {
            return;
        }
        let Ok(entries) = std::fs::read_dir(dir) else { return };
        for entry in entries.flatten() {
            let path = dir.join(entry.file_name());
            // Follows links: skill folders are often linked in.
            let Ok(meta) = std::fs::metadata(&path) else { continue };
            if meta.is_dir() {
                walk(&path, depth + 1, visited, found);
            } else if entry.file_name() == "SKILL.md" {
                found.push(path);
            }
        }
    }
    let mut found = Vec::new();
    walk(root, 0, &mut HashSet::new(), &mut found);
    found.sort();
    found.into_iter().map(|p| json!({ "path": p.display().to_string(), "enabled": false })).collect()
}

pub fn classify_codex_error(info: &Value) -> FailureReason {
    let code = match info {
        Value::String(s) => Some(s.as_str()),
        Value::Object(map) => map.keys().next().map(String::as_str),
        _ => None,
    };
    match code {
        Some("unauthorized") => FailureReason::Auth,
        Some("usageLimitExceeded" | "rateLimitExceeded" | "serverOverloaded") => FailureReason::RateLimit,
        _ => FailureReason::Model,
    }
}

/// A thread's share of its app-server's notifications.
type ThreadSink = Arc<dyn Fn(Notice) + Send + Sync>;

enum Notice {
    Method(String, Value),
    HostExited(String),
}

/// One app-server process and its JSON-RPC connection.
struct Host {
    profile: String,
    proc: Arc<GroupProcess>,
    pending: Arc<Mutex<HashMap<i64, oneshot::Sender<Result<Value>>>>>,
    threads: Arc<Mutex<HashMap<String, ThreadSink>>>,
    next_id: AtomicI64,
    /// What the process was started with; a profile edit that changes it needs a new process.
    signature: String,
    ready: AsyncMutex<bool>,
}

/// An app-server as the next binary takes it up.
#[derive(Serialize, Deserialize)]
struct HandedHost {
    profile: String,
    signature: String,
    next_id: i64,
    ready: bool,
    process: HandedProcess,
}

/// A thread as the next binary takes it up (its app-server is handed over apart, before it).
#[derive(Serialize, Deserialize)]
struct HandedThread {
    thread_id: String,
    profile: String,
    busy: bool,
    turn_id: Option<String>,
}

fn host_signature(profile: &Profile) -> String {
    json!([profile.home, profile.env(RuntimeKind::Codex), codex_overrides(profile.access_kind, profile.model.as_deref())]).to_string()
}

impl Host {
    fn start(profile: &Profile, command: &str, store: Arc<Store>) -> Result<Arc<Host>> {
        std::fs::create_dir_all(&profile.home)?;
        if profile.machine {
            link_codex_auth(&profile.home, &process_env())?;
        }
        let mut env = clean_env(&SCRUBBED);
        env.extend(expand_route(&profile.env(RuntimeKind::Codex), &profile.id));
        env.insert("CODEX_HOME".into(), profile.home.display().to_string());
        with_ca_bundle(&mut env, Path::new(CA_BUNDLE));
        let mut args = vec!["app-server".to_string()];
        for (k, v) in codex_overrides(profile.access_kind, profile.model.as_deref()) {
            args.extend(["-c".into(), format!("{k}={v}")]);
        }
        args.extend(["--listen".into(), "stdio://".into()]);
        let label = format!("codex app-server {}", profile.id);
        Host::wire(&profile.id, host_signature(profile), 1, false, move |on_line| spawn_group(Spawn { command, args, cwd: &profile.home, env, runtime: "codex", label }, store, on_line))
    }

    /// Takes up an app-server the previous binary handed over.
    fn adopt(handed: HandedHost, store: Arc<Store>) -> Result<Arc<Host>> {
        info!(profile = handed.profile, pgid = handed.process.pgid, "taking up a codex app-server handed over");
        let (process, label) = (handed.process, format!("codex app-server {}", handed.profile));
        Host::wire(&handed.profile, handed.signature, handed.next_id, handed.ready, move |on_line| adopt_group(&process, store, "codex", &label, on_line))
    }

    /// A host on the process `start` gives, fed its lines.
    fn wire(profile: &str, signature: String, next_id: i64, ready: bool, start: impl FnOnce(Box<dyn Fn(String) + Send>) -> Result<Arc<GroupProcess>>) -> Result<Arc<Host>> {
        let pending: Arc<Mutex<HashMap<i64, oneshot::Sender<Result<Value>>>>> = Arc::default();
        let threads: Arc<Mutex<HashMap<String, ThreadSink>>> = Arc::default();
        let (line_pending, line_threads) = (pending.clone(), threads.clone());
        let replies: Arc<Mutex<Option<Arc<GroupProcess>>>> = Arc::default();
        let line_replies = replies.clone();
        let proc = start(Box::new(move |line| on_line(&line, &line_pending, &line_threads, &line_replies)))?;
        *replies.lock().unwrap() = Some(proc.clone());
        let host = Arc::new(Host { profile: profile.to_string(), proc: proc.clone(), pending, threads, next_id: AtomicI64::new(next_id), signature, ready: AsyncMutex::new(ready) });
        let exit = host.clone();
        tokio::spawn(async move {
            let code = proc.exited().await;
            if proc.handed() {
                return;
            }
            let reason = format!("codex app-server exited ({code})");
            for (_, pending) in exit.pending.lock().unwrap().drain() {
                let _ = pending.send(Err(anyhow!(reason.clone())));
            }
            let threads: Vec<ThreadSink> = exit.threads.lock().unwrap().drain().map(|(_, t)| t).collect();
            for thread in threads {
                thread(Notice::HostExited(reason.clone()));
            }
        });
        Ok(host)
    }

    fn alive(&self) -> bool {
        !self.proc.has_exited()
    }

    async fn ensure_ready(&self) -> Result<()> {
        let mut ready = self.ready.lock().await;
        if !*ready {
            self.request("initialize", json!({ "clientInfo": { "name": "stillfail", "version": "0" }, "capabilities": { "experimentalApi": true } })).await?;
            self.proc.write(&json!({ "method": "initialized", "params": {} }).to_string()).await;
            *ready = true;
        }
        Ok(())
    }

    async fn request(&self, method: &str, params: Value) -> Result<Value> {
        if !self.alive() {
            bail!("codex app-server is not running");
        }
        let id = self.next_id.fetch_add(1, Ordering::SeqCst);
        let (tx, rx) = oneshot::channel();
        self.pending.lock().unwrap().insert(id, tx);
        self.proc.write(&json!({ "id": id, "method": method, "params": params }).to_string()).await;
        rx.await.map_err(|_| anyhow!("codex app-server went away"))?
    }
}

fn on_line(line: &str, pending: &Mutex<HashMap<i64, oneshot::Sender<Result<Value>>>>, threads: &Mutex<HashMap<String, ThreadSink>>, proc: &Mutex<Option<Arc<GroupProcess>>>) {
    let Ok(msg) = serde_json::from_str::<Value>(line) else {
        debug!(line = &line[..line.len().min(500)], "codex non-json line");
        return;
    };
    let method = msg.get("method").and_then(Value::as_str);
    if let (Some(id), None) = (msg.get("id").and_then(Value::as_i64), method) {
        if let Some(reply) = pending.lock().unwrap().remove(&id) {
            let _ = reply.send(match msg.get("error") {
                Some(error) if !error.is_null() => Err(anyhow!("codex {error}")),
                _ => Ok(msg.get("result").cloned().unwrap_or(Value::Null)),
            });
        }
    } else if let (Some(id), Some(method)) = (msg.get("id").cloned(), method) {
        // Server->client requests (approvals) should not arrive with approvalPolicy "never"; refuse rather than hang.
        warn!(method, "codex asked the client something; refusing");
        if let Some(proc) = proc.lock().unwrap().clone() {
            let refusal = json!({ "id": id, "error": { "code": -32601, "message": "the station does not answer client requests" } }).to_string();
            tokio::spawn(async move { proc.write(&refusal).await });
        }
    } else if let Some(method) = method {
        let params = msg.get("params").cloned().unwrap_or(Value::Null);
        let sink = params.get("threadId").and_then(Value::as_str).and_then(|t| threads.lock().unwrap().get(t).cloned());
        if let Some(sink) = sink {
            sink(Notice::Method(method.to_string(), params));
        }
    }
}

pub struct CodexDriver {
    settings: Option<Arc<crate::settings::Settings>>,
    store: Arc<Store>,
    command: String,
    hosts: AsyncMutex<HashMap<String, Arc<Host>>>,
    /// Where the user's own skills are (~/.agents/skills), turned off for the station's agents.
    host_skills: PathBuf,
}

impl CodexDriver {
    pub fn new(store: Arc<Store>, command: &str) -> CodexDriver {
        let home = std::env::var("HOME").map(PathBuf::from).unwrap_or_default();
        CodexDriver { settings: None, store, command: command.into(), hosts: AsyncMutex::new(HashMap::new()), host_skills: home.join(".agents").join("skills") }
    }

    pub fn with_settings(mut self, settings: Arc<crate::settings::Settings>) -> Self {
        self.settings = Some(settings);
        self
    }

    async fn host(&self, profile: &Profile) -> Result<Arc<Host>> {
        let mut hosts = self.hosts.lock().await;
        if let Some(host) = hosts.get(&profile.id).cloned() {
            if host.alive() && host.signature != host_signature(profile) {
                // The profile changed. Replace the process once no session uses it; until then keep serving.
                if host.threads.lock().unwrap().is_empty() {
                    info!(profile = profile.id, "profile changed; restarting its codex app-server");
                    hosts.remove(&profile.id);
                    host.proc.kill(Duration::from_secs(5)).await;
                } else {
                    info!(profile = profile.id, "profile changed; its codex app-server restarts once idle");
                }
            }
        }
        let host = match hosts.get(&profile.id).filter(|h| h.alive()).cloned() {
            Some(host) => host,
            None => {
                let host = Host::start(profile, &self.command, self.store.clone())?;
                hosts.insert(profile.id.clone(), host.clone());
                host
            }
        };
        drop(hosts);
        host.ensure_ready().await?;
        Ok(host)
    }

    /// The account's rate-limit windows, as the profile's app-server reports them (ChatGPT subscriptions).
    pub async fn rate_limits(&self, profile: &Profile) -> Result<Value> {
        self.host(profile).await?.request("account/rateLimits/read", json!({})).await
    }

    pub async fn reset_quota(&self, profile: &Profile, key: &str) -> Result<Value> {
        self.host(profile).await?.request("account/rateLimitResetCredit/consume", json!({ "idempotencyKey": key })).await
    }

    /// The models the account can run in Codex, as its app-server lists them (the ones it does not hide).
    pub async fn models(&self, profile: &Profile) -> Result<ModelCatalog> {
        let host = self.host(profile).await?;
        let mut catalog = ModelCatalog::default();
        let mut cursor = None;
        let mut seen = HashSet::new();
        loop {
            let answer = host.request("model/list", json!({"cursor": cursor})).await?;
            catalog.extend(&answer)?;
            cursor = answer.get("nextCursor").and_then(Value::as_str).filter(|c| !c.is_empty()).map(String::from);
            match &cursor {
                None => break,
                Some(c) if !seen.insert(c.clone()) => bail!("model/list repeated its cursor"),
                _ => {}
            }
        }
        catalog.models.sort();
        catalog.models.dedup();
        Ok(catalog)
    }
}

/// Keep capabilities alongside model ids; an old runtime may omit them.
#[derive(Default)]
pub struct ModelCatalog {
    pub models: Vec<String>,
    pub efforts: HashMap<String, Vec<String>>,
}

impl ModelCatalog {
    fn extend(&mut self, answer: &Value) -> Result<()> {
        let rows = answer.get("data").and_then(Value::as_array).ok_or_else(|| anyhow!("model/list omitted data"))?;
        for m in rows.iter().filter(|m| m.get("hidden") != Some(&Value::Bool(true))) {
            let Some(id) = m.get("id").or_else(|| m.get("model")).and_then(Value::as_str).filter(|s| !s.is_empty()) else { continue };
            self.models.push(id.to_string());
            if let Some(levels) = m.get("supportedReasoningEfforts").and_then(Value::as_array) {
                let mut efforts = Vec::new();
                for level in levels {
                    if let Some(effort) = level.get("reasoningEffort").and_then(Value::as_str).filter(|s| !s.is_empty()) {
                        if !efforts.iter().any(|e| e == effort) {
                            efforts.push(effort.to_string());
                        }
                    }
                }
                self.efforts.insert(id.to_string(), efforts);
            }
        }
        Ok(())
    }
}

struct ThreadState {
    busy: bool,
    turn_id: Option<String>,
    closed: bool,
}

pub struct CodexSession {
    settings: Option<Arc<crate::settings::Settings>>,
    thread_id: String,
    host: Arc<Host>,
    state: Arc<Mutex<ThreadState>>,
}

fn end_turn(state: &Mutex<ThreadState>, events: &Events, outcome: TurnOutcome) {
    {
        let mut s = state.lock().unwrap();
        s.busy = false;
        s.turn_id = None;
    }
    let _ = events.send(RuntimeEvent::TurnEnded(outcome));
}

/// A thread's share of its app-server's notifications: its turns and live steps, as events.
fn thread_sink(state: &Arc<Mutex<ThreadState>>, events: &Events, thread_id: &str) -> ThreadSink {
    let live = Mutex::new(LiveFromCodex::default());
    let (sink_state, sink_events, sink_thread) = (state.clone(), events.clone(), thread_id.to_string());
    Arc::new(move |notice| match notice {
        Notice::Method(method, params) => {
            for event in live.lock().unwrap().feed(&method, &params) {
                let _ = sink_events.send(RuntimeEvent::Live(event));
            }
            match method.as_str() {
                "turn/started" => {
                    let started = {
                        let mut s = sink_state.lock().unwrap();
                        if let Some(id) = params.get("turn").and_then(|t| t.get("id")).and_then(Value::as_str) {
                            s.turn_id = Some(id.to_string());
                        }
                        let was = s.busy;
                        s.busy = true;
                        !was
                    };
                    if started {
                        let _ = sink_events.send(RuntimeEvent::TurnStarted);
                    }
                }
                "turn/completed" => {
                    let turn = params.get("turn").cloned().unwrap_or(Value::Null);
                    let outcome = match turn.get("status").and_then(Value::as_str) {
                        Some("interrupted") => TurnOutcome::Aborted,
                        Some("failed") => {
                            let error = turn.get("error").cloned().unwrap_or(Value::Null);
                            TurnOutcome::Failed {
                                reason: classify_codex_error(error.get("codexErrorInfo").unwrap_or(&Value::Null)),
                                message: error.get("message").and_then(Value::as_str).unwrap_or("turn failed").chars().take(1000).collect(),
                            }
                        }
                        _ => TurnOutcome::Completed,
                    };
                    end_turn(&sink_state, &sink_events, outcome);
                }
                "error" if params.get("willRetry") != Some(&Value::Bool(true)) => {
                    let error = params.get("error").cloned().unwrap_or(Value::Null).to_string();
                    warn!(thread = sink_thread, error, "codex turn error");
                }
                _ => {}
            }
        }
        Notice::HostExited(reason) => {
            let busy = {
                let mut s = sink_state.lock().unwrap();
                s.closed = true;
                s.busy
            };
            if busy {
                end_turn(&sink_state, &sink_events, TurnOutcome::Failed { reason: FailureReason::Exited, message: reason.clone() });
            }
            let _ = sink_events.send(RuntimeEvent::Closed(reason));
        }
    })
}

#[async_trait]
impl AgentDriver for CodexDriver {
    fn runtime(&self) -> RuntimeKind {
        RuntimeKind::Codex
    }

    async fn open(&self, options: OpenOptions, events: Events) -> Result<Arc<dyn AgentSession>> {
        let host = self.host(&options.profile).await?;
        let model = options.model.clone().or_else(|| options.profile.model.clone());
        let skills_off = host_skills_off(&self.host_skills);
        let mut config = json!({
            "mcp_servers.ember.url": options.mcp_url,
            "mcp_servers.ember.http_headers": { "Authorization": format!("Bearer {}", options.mcp_token) },
        });
        if let Some(effort) = &options.effort {
            config["model_reasoning_effort"] = json!(effort);
        }
        if !skills_off.is_empty() {
            config["skills.config"] = Value::Array(skills_off);
        }
        let mut common = json!({
            "cwd": options.cwd,
            "approvalPolicy": "never",
            "sandbox": "danger-full-access",
            "developerInstructions": options.instructions,
            "config": config,
        });
        if let Some(model) = &model {
            common["model"] = json!(model);
        }
        // None for a thread continued from a terminal: it keeps its own, so its cache holds.
        if options.instructions.is_empty() {
            common.as_object_mut().map(|c| c.remove("developerInstructions"));
        }
        let opened = match &options.resume {
            Some(thread) => {
                common["threadId"] = json!(thread);
                host.request("thread/resume", common).await?
            }
            None => host.request("thread/start", common).await?,
        };
        let thread_id = opened.get("thread").and_then(|t| t.get("id")).and_then(Value::as_str).ok_or_else(|| anyhow!("codex gave no thread id"))?.to_string();
        let state = Arc::new(Mutex::new(ThreadState { busy: false, turn_id: None, closed: false }));
        host.threads.lock().unwrap().insert(thread_id.clone(), thread_sink(&state, &events, &thread_id));
        Ok(Arc::new(CodexSession { settings: self.settings.clone(), thread_id, host, state }))
    }

    async fn hand_off(&self) -> Result<Value> {
        let hosts: Vec<Arc<Host>> = self.hosts.lock().await.values().filter(|h| h.alive()).cloned().collect();
        // Replies owed are the old binary's to take: wait for them, before anything is given up.
        for _ in 0..100 {
            if hosts.iter().all(|h| h.pending.lock().unwrap().is_empty()) {
                break;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        if let Some(host) = hosts.iter().find(|h| !h.pending.lock().unwrap().is_empty()) {
            bail!("codex app-server {} still owes replies", host.profile);
        }
        let mut handed = vec![];
        for host in hosts {
            let ready = host.ready.try_lock().map(|r| *r).unwrap_or(false);
            match host.proc.hand_off().await {
                Ok(process) => handed.push(HandedHost { profile: host.profile.clone(), signature: host.signature.clone(), next_id: host.next_id.load(Ordering::SeqCst), ready, process }),
                Err(e) => warn!(profile = host.profile, error = %e, "codex app-server not handed over"),
            }
        }
        Ok(serde_json::to_value(handed)?)
    }

    async fn adopt(&self, handed: &Value) -> Result<()> {
        let handed: Vec<HandedHost> = serde_json::from_value(handed.clone())?;
        let mut hosts = self.hosts.lock().await;
        for host in handed {
            let profile = host.profile.clone();
            match Host::adopt(host, self.store.clone()) {
                Ok(host) => {
                    hosts.insert(profile, host);
                }
                Err(e) => warn!(profile, error = %e, "codex app-server handed over could not be taken up"),
            }
        }
        Ok(())
    }

    async fn adopt_session(&self, handed: &Value, events: Events) -> Result<Arc<dyn AgentSession>> {
        let handed: HandedThread = serde_json::from_value(handed.clone())?;
        let host = self.hosts.lock().await.get(&handed.profile).filter(|h| h.alive()).cloned().ok_or_else(|| anyhow!("codex app-server {} was not taken up", handed.profile))?;
        let state = Arc::new(Mutex::new(ThreadState { busy: handed.busy, turn_id: handed.turn_id, closed: false }));
        host.threads.lock().unwrap().insert(handed.thread_id.clone(), thread_sink(&state, &events, &handed.thread_id));
        Ok(Arc::new(CodexSession { settings: self.settings.clone(), thread_id: handed.thread_id, host, state }))
    }

    async fn shutdown(&self) {
        let hosts: Vec<Arc<Host>> = self.hosts.lock().await.drain().map(|(_, h)| h).collect();
        for host in hosts {
            host.proc.kill(Duration::from_secs(5)).await;
        }
    }
}

fn input(text: &str) -> Value {
    json!([{ "type": "text", "text": text }])
}

#[async_trait]
impl AgentSession for CodexSession {
    fn id(&self) -> String {
        self.thread_id.clone()
    }

    fn busy(&self) -> bool {
        self.state.lock().unwrap().busy
    }

    async fn prompt(&self, text: &str) -> Result<()> {
        {
            let mut s = self.state.lock().unwrap();
            if s.closed {
                bail!("codex session is closed");
            }
            if s.busy {
                bail!("a turn is already running");
            }
            s.busy = true;
        }
        let mut params = json!({ "threadId": self.thread_id, "input": input(text) });
        if let Some(settings) = &self.settings {
            if let Some(p) = settings.config().profiles.iter().find(|p| p.id == self.host.profile && p.access_kind == stillfail_shapes::AccessKind::Subscription) {
                // An explicit null clears a previously selected tier; omitting it would keep Fast on.
                params["serviceTier"] = if p.fast { json!("fast") } else { Value::Null };
            }
        }
        match self.host.request("turn/start", params).await {
            Ok(started) => {
                if let Some(id) = started.get("turn").and_then(|t| t.get("id")).and_then(Value::as_str) {
                    self.state.lock().unwrap().turn_id = Some(id.to_string());
                }
                Ok(())
            }
            Err(error) => {
                self.state.lock().unwrap().busy = false;
                Err(error)
            }
        }
    }

    async fn steer(&self, text: &str) -> bool {
        let turn = {
            let s = self.state.lock().unwrap();
            if s.closed || !s.busy {
                return false;
            }
            s.turn_id.clone()
        };
        let Some(turn) = turn else { return false };
        match self.host.request("turn/steer", json!({ "threadId": self.thread_id, "input": input(text), "expectedTurnId": turn })).await {
            Ok(_) => true,
            Err(error) => {
                debug!(thread = self.thread_id, error = %error, "codex steer refused");
                false
            }
        }
    }

    async fn abort(&self) {
        let turn = {
            let s = self.state.lock().unwrap();
            if s.closed || !s.busy {
                return;
            }
            s.turn_id.clone()
        };
        if let Some(turn) = turn {
            if let Err(error) = self.host.request("turn/interrupt", json!({ "threadId": self.thread_id, "turnId": turn })).await {
                warn!(thread = self.thread_id, error = %error, "codex interrupt failed");
            }
        }
    }

    async fn dispose(&self) {
        {
            let mut s = self.state.lock().unwrap();
            if s.closed {
                return;
            }
            s.closed = true;
        }
        self.host.threads.lock().unwrap().remove(&self.thread_id);
        // Handed over, the thread is the next binary's.
        if self.host.proc.handed() {
            return;
        }
        // Best effort: the thread just stays loaded.
        let _ = self.host.request("thread/unsubscribe", json!({ "threadId": self.thread_id })).await;
    }

    /// After the driver's hand_off: its app-server's reader has stopped, so the thread stands as it last said.
    async fn hand_off(&self) -> Result<Value> {
        if !self.host.proc.handed() {
            bail!("codex app-server {} was not handed over", self.host.profile);
        }
        let (busy, turn_id) = {
            let mut s = self.state.lock().unwrap();
            if s.closed {
                bail!("codex session is closed");
            }
            s.closed = true;
            (s.busy, s.turn_id.clone())
        };
        self.host.threads.lock().unwrap().remove(&self.thread_id);
        Ok(serde_json::to_value(HandedThread { thread_id: self.thread_id.clone(), profile: self.host.profile.clone(), busy, turn_id })?)
    }
}

/// The app-server's item notifications as live steps: an item starts, grows by deltas (the reply, reasoning, a
/// command's output as it runs) and completes.
#[derive(Default)]
pub struct LiveFromCodex {
    open: HashSet<String>,
    phase: Option<LivePhase>,
}

const TOOL_ITEMS: [&str; 5] = ["commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "webSearch"];

impl LiveFromCodex {
    pub fn feed(&mut self, method: &str, params: &Value) -> Vec<LiveEvent> {
        let mut out = Vec::new();
        let to = |me: &mut Self, next: LivePhase, out: &mut Vec<LiveEvent>| {
            if me.phase != Some(next) {
                me.phase = Some(next);
                out.push(LiveEvent::Phase { phase: next });
            }
        };
        let item_type = params.get("item").and_then(|i| i.get("type")).and_then(Value::as_str).unwrap_or("");
        match method {
            "turn/started" => to(self, LivePhase::Requesting, &mut out),
            "turn/completed" => self.phase = None,
            m if m == "item/agentMessage/delta" || m.starts_with("item/reasoning/") => to(self, LivePhase::Responding, &mut out),
            "item/started" if TOOL_ITEMS.contains(&item_type) => to(self, LivePhase::Working, &mut out),
            "item/completed" if TOOL_ITEMS.contains(&item_type) => to(self, LivePhase::Requesting, &mut out),
            _ => {}
        }
        let text = |v: Option<&Value>| v.and_then(Value::as_str).unwrap_or("").to_string();
        let pretty = |v: Option<&Value>| serde_json::to_string_pretty(v.unwrap_or(&json!({}))).unwrap_or_default();
        match method {
            "item/started" => {
                let item = params.get("item").cloned().unwrap_or(Value::Null);
                let id = match item.get("id") {
                    Some(Value::String(s)) => s.clone(),
                    Some(Value::Number(n)) => n.to_string(),
                    _ => String::new(),
                };
                let start: Option<(LiveStepKind, Option<String>, Option<String>)> = match item_type {
                    "agentMessage" => Some((LiveStepKind::Text, None, None)),
                    "reasoning" => Some((LiveStepKind::Thinking, None, None)),
                    "commandExecution" => Some((LiveStepKind::Tool, Some("shell".into()), Some(text(item.get("command"))))),
                    "fileChange" => Some((
                        LiveStepKind::Tool,
                        Some("apply_patch".into()),
                        Some(item.get("changes").and_then(Value::as_array).into_iter().flatten().map(|c| text(c.get("path"))).collect::<Vec<_>>().join("\n")),
                    )),
                    "mcpToolCall" => Some((LiveStepKind::Tool, Some(format!("{}.{}", text(item.get("server")), text(item.get("tool")))), Some(pretty(item.get("arguments"))))),
                    "dynamicToolCall" => Some((LiveStepKind::Tool, Some(text(item.get("tool"))), Some(pretty(item.get("arguments"))))),
                    "webSearch" => Some((LiveStepKind::Tool, Some("web_search".into()), Some(text(item.get("query"))))),
                    _ => None,
                };
                if let (false, Some((step, tool, input))) = (id.is_empty(), start) {
                    self.open.insert(id.clone());
                    out.push(LiveEvent::Start { id, step, tool, input, subagent: None, parent: None });
                }
            }
            "item/agentMessage/delta" | "item/reasoning/textDelta" | "item/reasoning/summaryTextDelta" | "item/plan/delta" | "item/commandExecution/outputDelta" => {
                let id = text(params.get("itemId"));
                let delta = text(params.get("delta"));
                if self.open.contains(&id) && !delta.is_empty() {
                    let field = if method == "item/commandExecution/outputDelta" { LiveField::Output } else { LiveField::Text };
                    out.push(LiveEvent::delta(id, field, delta));
                }
            }
            "item/completed" => {
                let id = text(params.get("item").and_then(|i| i.get("id")));
                if self.open.remove(&id) {
                    out.push(LiveEvent::End { id });
                }
            }
            _ => {}
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn model_catalog_keeps_reported_efforts_across_pages_and_old_runtimes() {
        let mut catalog = ModelCatalog::default();
        catalog.extend(&json!({"data": [
            {"id": "gpt-6-astra", "supportedReasoningEfforts": [
                {"reasoningEffort": "low"}, {"reasoningEffort": "max"}, {"reasoningEffort": "ultra"}
            ]},
            {"id": "hidden", "hidden": true, "supportedReasoningEfforts": []}
        ], "nextCursor": "page2"})).unwrap();
        catalog.extend(&json!({"data": [{"model": "legacy"}, {"id": "fixed", "supportedReasoningEfforts": []}]})).unwrap();
        assert_eq!(catalog.models, ["gpt-6-astra", "legacy", "fixed"]);
        assert_eq!(catalog.efforts["gpt-6-astra"], ["low", "max", "ultra"]);
        assert!(!catalog.efforts.contains_key("legacy"));
        assert_eq!(catalog.efforts["fixed"], Vec::<String>::new());
        assert!(catalog.extend(&json!({})).is_err());
    }


    #[test]
    fn codex_item_notifications_become_steps() {
        let mut feed = LiveFromCodex::default();
        let mut out = Vec::new();
        for (method, params) in [
            ("item/started", json!({ "item": { "type": "userMessage", "id": "u" } })),
            ("item/started", json!({ "item": { "type": "commandExecution", "id": "c1", "command": "ls" } })),
            ("item/commandExecution/outputDelta", json!({ "itemId": "c1", "delta": "a\n" })),
            ("item/completed", json!({ "item": { "id": "c1" } })),
            ("item/started", json!({ "item": { "type": "agentMessage", "id": "a1" } })),
            ("item/agentMessage/delta", json!({ "itemId": "a1", "delta": "ok" })),
            ("item/completed", json!({ "item": { "id": "a1" } })),
        ] {
            out.extend(feed.feed(method, &params));
        }
        let phases: Vec<LivePhase> = out.iter().filter_map(|e| if let LiveEvent::Phase { phase } = e { Some(*phase) } else { None }).collect();
        assert_eq!(phases, vec![LivePhase::Working, LivePhase::Responding]);
        let steps: Vec<Value> = out.iter().filter(|e| !matches!(e, LiveEvent::Phase { .. })).map(|e| serde_json::to_value(e).unwrap()).collect();
        assert_eq!(
            steps,
            vec![
                json!({ "kind": "start", "id": "c1", "step": "tool", "tool": "shell", "input": "ls" }),
                json!({ "kind": "delta", "id": "c1", "field": "output", "text": "a\n" }),
                json!({ "kind": "end", "id": "c1" }),
                json!({ "kind": "start", "id": "a1", "step": "text" }),
                json!({ "kind": "delta", "id": "a1", "field": "text", "text": "ok" }),
                json!({ "kind": "end", "id": "a1" }),
            ]
        );
    }

    #[test]
    fn codex_reads_a_ca_file_unless_the_user_chose_one() {
        let dir = tempfile::tempdir().unwrap();
        let bundle = dir.path().join("cert.pem");
        std::fs::write(&bundle, "").unwrap();
        let with = |env: &[(&str, &str)], bundle: &Path| {
            let mut env: BTreeMap<String, String> = env.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
            with_ca_bundle(&mut env, bundle);
            env.get("SSL_CERT_FILE").cloned()
        };
        assert_eq!(with(&[], &bundle), Some(bundle.display().to_string()));
        assert_eq!(with(&[("SSL_CERT_FILE", "/mine.pem")], &bundle), Some("/mine.pem".into()));
        assert_eq!(with(&[("CODEX_CA_CERTIFICATE", "/mine.pem")], &bundle), None);
        assert_eq!(with(&[], &dir.path().join("missing.pem")), None);
    }

    #[test]
    fn the_users_own_skills_are_turned_off_one_skill_md_at_a_time() {
        let root = tempfile::tempdir().unwrap();
        let elsewhere = tempfile::tempdir().unwrap();
        std::fs::create_dir(root.path().join("plain")).unwrap();
        std::fs::write(root.path().join("plain/SKILL.md"), "").unwrap();
        std::fs::create_dir(elsewhere.path().join("inner")).unwrap();
        std::fs::write(elsewhere.path().join("inner/SKILL.md"), "").unwrap();
        std::os::unix::fs::symlink(elsewhere.path(), root.path().join("pack")).unwrap();
        std::os::unix::fs::symlink(root.path(), root.path().join("pack/loop")).unwrap(); // a cycle ends
        let paths: Vec<Value> = host_skills_off(root.path());
        assert_eq!(
            paths,
            vec![
                json!({ "path": root.path().join("pack/inner/SKILL.md").display().to_string(), "enabled": false }),
                json!({ "path": root.path().join("plain/SKILL.md").display().to_string(), "enabled": false }),
            ]
        );
        assert!(host_skills_off(&root.path().join("none")).is_empty());
    }

    #[test]
    fn codex_errors_are_told_apart_by_their_code() {
        assert_eq!(classify_codex_error(&json!("unauthorized")), FailureReason::Auth);
        assert_eq!(classify_codex_error(&json!({ "usageLimitExceeded": {} })), FailureReason::RateLimit);
        assert_eq!(classify_codex_error(&json!(null)), FailureReason::Model);
    }
}
