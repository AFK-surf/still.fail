//! Workspace peers call named operations over an authenticated station transport. Shell tasks are one service on
//! that transport, never an admin API proxy. An administrator explicitly trusts source station keys in config.json:
//! remoteTasks.allow = ["<station public key>"]. This grants shell execution as the station's OS user, not a sandbox.
//! A source session's tasks share one working directory on the target (remote/sessions/<id>/work). The source asks
//! for it to be removed when the session is archived or deleted; the target removes it itself after IDLE_MS unused.
use crate::{
    jobs::{Jobs, Watch},
    mcp::Tool,
    settings::Settings,
    store::Store,
};
use anyhow::{Result, anyhow, bail};
use base64::{Engine, engine::general_purpose::STANDARD as B64};
use futures_util::future::BoxFuture;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::HashSet,
    io::{Read, Seek, SeekFrom, Write},
    path::{Component, Path, PathBuf},
    sync::{Arc, Mutex},
};

pub type Notify = Arc<dyn Fn(&str, String) -> Result<()> + Send + Sync>;
pub type Call = Arc<dyn Fn(String, Value) -> BoxFuture<'static, Result<Value>> + Send + Sync>;
#[derive(Debug, thiserror::Error)]
#[error("{0}")]
pub struct Refused(pub String);

pub const CHUNK: usize = 256 * 1024;
const MAX_FILE: u64 = 1024 * 1024 * 1024;
/// A source session's directory unused this long is removed by the target, in case its source never says so.
const IDLE_MS: i64 = 14 * 24 * 3600 * 1000;
/// A source keeps asking an unreachable target to remove a closed session's directory this long.
const CLOSE_FOR_MS: i64 = 30 * 24 * 3600 * 1000;

pub struct Remote {
    settings: Arc<Settings>,
    store: Arc<Store>,
    jobs: Arc<Jobs>,
    notify: Notify,
    root: PathBuf,
    call: Mutex<Option<Call>>,
    serial: tokio::sync::Mutex<()>,
    watching: Mutex<HashSet<PathBuf>>,
    /// Read-modify-write of the source's record of stations a session used (remote/used).
    used: Mutex<()>,
}

fn text<'a>(v: &'a Value, key: &str) -> &'a str {
    v[key].as_str().unwrap_or("")
}
fn hash(v: &Value) -> String {
    hex::encode(Sha256::digest(v.to_string().as_bytes()))
}
fn read(path: &Path) -> Result<Value> {
    Ok(serde_json::from_slice(&std::fs::read(path)?)?)
}
fn write(path: &Path, value: &Value) -> Result<()> {
    let mut nonce = [0u8; 8];
    getrandom::fill(&mut nonce).map_err(|e| anyhow!("random: {e}"))?;
    let temp = path.with_extension(format!("{}.tmp", hex::encode(nonce)));
    use std::os::unix::fs::OpenOptionsExt;
    let mut file = std::fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temp)?;
    file.write_all(&serde_json::to_vec(value)?)?;
    file.sync_all()?;
    std::fs::rename(temp, path)?;
    Ok(())
}

/// Relative paths only; transfers must not follow links planted by a task. Task commands themselves are trusted
/// shell execution, so separate working directories are organizational isolation, not an OS security boundary.
fn file_path(root: &Path, relative: &str, create: bool) -> Result<PathBuf> {
    if std::fs::symlink_metadata(root)?.file_type().is_symlink() {
        bail!("transfer root is a symbolic link");
    }
    let path = Path::new(relative);
    if relative.is_empty() || path.components().any(|c| !matches!(c, Component::Normal(_))) {
        bail!("file path must be relative, without . or ..");
    }
    let mut out = root.to_path_buf();
    for c in path.components() {
        out.push(c);
        if std::fs::symlink_metadata(&out).is_ok_and(|m| m.file_type().is_symlink()) {
            bail!("file path contains a symbolic link");
        }
    }
    if create {
        std::fs::create_dir_all(out.parent().ok_or_else(|| anyhow!("no parent"))?)?;
    }
    Ok(out)
}

impl Remote {
    pub fn new(settings: Arc<Settings>, store: Arc<Store>, jobs: Arc<Jobs>, notify: Notify) -> Result<Arc<Self>> {
        let root = settings.data_dir.join("remote");
        for name in ["incoming", "outgoing", "sessions", "used"] {
            std::fs::create_dir_all(root.join(name))?;
        }
        Ok(Arc::new(Self {
            settings,
            store,
            jobs,
            notify,
            root,
            call: Mutex::new(None),
            serial: tokio::sync::Mutex::new(()),
            watching: Mutex::new(HashSet::new()),
            used: Mutex::new(()),
        }))
    }

    pub fn attach(self: &Arc<Self>, call: Call) {
        *self.call.lock().unwrap() = Some(call);
        if let Ok(entries) = std::fs::read_dir(self.root.join("outgoing")) {
            for e in entries.flatten().filter(|e| e.path().extension().is_some_and(|x| x == "json")) {
                self.watch(e.path());
            }
        }
        if let Ok(entries) = std::fs::read_dir(self.root.join("used")) {
            for e in entries.flatten().filter(|e| e.path().extension().is_some_and(|x| x == "json")) {
                if read(&e.path()).is_ok_and(|v| v["closing"] == true) {
                    self.closer(e.path());
                }
            }
        }
        let me = Arc::downgrade(self);
        tokio::spawn(async move {
            loop {
                let Some(remote) = me.upgrade() else { return };
                remote.sweep(crate::store::now_ms()).await;
                drop(remote);
                tokio::time::sleep(std::time::Duration::from_secs(3600)).await;
            }
        });
    }

    fn room(&self, workspace: &str, peer: &str, session: &str) -> PathBuf {
        self.root.join("sessions").join(hash(&json!([workspace, peer, session])))
    }

    /// Makes a source session's shared directory and notes when it was last used (at most once a minute).
    fn seen(&self, workspace: &str, peer: &str, session: &str) -> Result<PathBuf> {
        let room = self.room(workspace, peer, session);
        std::fs::create_dir_all(room.join("work"))?;
        let record = room.join("session.json");
        let now = crate::store::now_ms();
        if !read(&record).is_ok_and(|v| now - v["seen"].as_i64().unwrap_or(0) < 60_000) {
            write(&record, &json!({"workspace":workspace,"station":peer,"session":session,"seen":now}))?;
        }
        Ok(room.join("work"))
    }

    /// Task directories (incoming/<id>) of a source session.
    fn tasks_of(&self, workspace: &str, peer: &str, session: &str) -> Vec<PathBuf> {
        let Ok(entries) = std::fs::read_dir(self.root.join("incoming")) else { return vec![] };
        entries
            .flatten()
            .filter(|e| {
                read(&e.path().join("task.json")).is_ok_and(|m| {
                    text(&m, "workspace") == workspace && text(&m, "station") == peer && text(&m, "session") == session
                })
            })
            .map(|e| e.path())
            .collect()
    }

    fn running(&self, task: &Path) -> bool {
        let id = format!("remote_{}", task.file_name().unwrap_or_default().to_string_lossy());
        self.store.get_job(&id).ok().flatten().is_some_and(|j| j.state == "running")
    }

    /// Stops a source session's tasks and removes their records and its shared directory. Callers hold `serial`.
    async fn close_here(&self, workspace: &str, peer: &str, session: &str) -> Result<()> {
        for task in self.tasks_of(workspace, peer, session) {
            if self.running(&task) {
                let id = format!("remote_{}", task.file_name().unwrap_or_default().to_string_lossy());
                self.jobs.stop(&id).await?;
            }
            std::fs::remove_dir_all(&task)?;
        }
        let room = self.room(workspace, peer, session);
        if room.exists() {
            std::fs::remove_dir_all(&room)?;
            tracing::info!(workspace, station = peer, session, "remote session directory removed");
        }
        Ok(())
    }

    /// The target's own cleanup: a source session's directory unused for IDLE_MS, with nothing running, goes; so do
    /// task directories from before shared session directories.
    pub async fn sweep(&self, now: i64) {
        let _guard = self.serial.lock().await;
        if let Ok(entries) = std::fs::read_dir(self.root.join("sessions")) {
            for entry in entries.flatten() {
                let Ok(meta) = read(&entry.path().join("session.json")) else { continue };
                if now - meta["seen"].as_i64().unwrap_or(now) < IDLE_MS {
                    continue;
                }
                let (workspace, peer, session) = (text(&meta, "workspace"), text(&meta, "station"), text(&meta, "session"));
                if self.tasks_of(workspace, peer, session).iter().any(|t| self.running(t)) {
                    continue;
                }
                if let Err(e) = self.close_here(workspace, peer, session).await {
                    tracing::warn!(error = %e, "idle remote session directory not removed");
                }
            }
        }
        if let Ok(entries) = std::fs::read_dir(self.root.join("incoming")) {
            for entry in entries.flatten() {
                let record = entry.path().join("task.json");
                let Ok(meta) = read(&record) else { continue };
                let modified = std::fs::metadata(&record)
                    .and_then(|m| m.modified())
                    .ok()
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_millis() as i64)
                    .unwrap_or(now);
                if meta["layout"] == "session" || now - modified < IDLE_MS || self.running(&entry.path()) {
                    continue;
                }
                let _ = std::fs::remove_dir_all(entry.path());
            }
        }
    }

    fn used_path(&self, session: &str) -> PathBuf {
        self.root.join("used").join(format!("{}.json", hash(&json!(session))))
    }

    /// The source remembers which stations a session ran tasks on, to ask them to clean up when it closes.
    fn record_use(&self, workspace: &str, session: &str, station: &str) -> Result<()> {
        let _lock = self.used.lock().unwrap();
        let path = self.used_path(session);
        let mut v = read(&path).unwrap_or_else(|_| json!({"session":session,"workspace":workspace,"stations":[]}));
        let known = v["stations"].as_array().is_some_and(|a| a.iter().any(|s| s == station));
        if known && v["closing"] != true {
            return Ok(());
        }
        if !known {
            v["stations"].as_array_mut().ok_or_else(|| anyhow!("bad record"))?.push(json!(station));
        }
        // Used again after closing (shown again): close later from the start.
        v["closing"] = json!(false);
        v["closed"] = json!([]);
        v["workspace"] = json!(workspace);
        write(&path, &v)
    }

    /// A session was archived or deleted: its tasks on other stations stop and their directories are removed. Asked
    /// until each station has answered (CLOSE_FOR_MS at most), across restarts.
    pub fn close_session(self: &Arc<Self>, session: &str) {
        let path = self.used_path(session);
        {
            let _lock = self.used.lock().unwrap();
            let Ok(mut v) = read(&path) else { return };
            v["closing"] = json!(true);
            v["since"] = json!(crate::store::now_ms());
            if write(&path, &v).is_err() {
                return;
            }
        }
        // Their directories are going away: stop following this session's tasks.
        if let Ok(entries) = std::fs::read_dir(self.root.join("outgoing")) {
            for e in entries.flatten() {
                if let Ok(mut entry) = read(&e.path()) {
                    if text(&entry, "session") == session && entry["delivered"] != true {
                        entry["delivered"] = json!(true);
                        let _ = write(&e.path(), &entry);
                    }
                }
            }
        }
        self.closer(path);
    }

    fn closer(self: &Arc<Self>, path: PathBuf) {
        if !self.watching.lock().unwrap().insert(path.clone()) {
            return;
        }
        let me = Arc::downgrade(self);
        tokio::spawn(async move {
            loop {
                let Some(remote) = me.upgrade() else { return };
                let v = {
                    let _lock = remote.used.lock().unwrap();
                    read(&path).ok()
                };
                let Some(v) = v.filter(|v| v["closing"] == true) else { break };
                let closed = |s: &Value| v["closed"].as_array().is_some_and(|c| c.contains(s));
                let pending: Vec<String> = v["stations"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter(|s| !closed(s))
                    .filter_map(|s| s.as_str().map(str::to_string))
                    .collect();
                if pending.is_empty() || crate::store::now_ms() - v["since"].as_i64().unwrap_or(0) > CLOSE_FOR_MS {
                    let _lock = remote.used.lock().unwrap();
                    if read(&path).is_ok_and(|now| now["closing"] == true) {
                        let _ = std::fs::remove_file(&path);
                    }
                    break;
                }
                for station in pending {
                    let request = json!({"method":"session.close","workspace":v["workspace"],"session":v["session"]});
                    // An answer, or a refusal (a station from before session directories, or one that no longer
                    // takes tasks from here), is final; no connection is asked again.
                    let done = match remote.call(&station, request).await {
                        Ok(_) => true,
                        Err(e) => e.downcast_ref::<Refused>().is_some(),
                    };
                    if done {
                        let _lock = remote.used.lock().unwrap();
                        if let Ok(mut now) = read(&path) {
                            if let (true, Some(closed)) = (now["closing"] == true, now["closed"].as_array_mut()) {
                                closed.push(json!(station));
                                let _ = write(&path, &now);
                            }
                        }
                    }
                }
                drop(remote);
                tokio::time::sleep(std::time::Duration::from_secs(60)).await;
            }
            if let Some(remote) = me.upgrade() {
                remote.watching.lock().unwrap().remove(&path);
            }
        });
    }

    async fn call(&self, station: &str, request: Value) -> Result<Value> {
        let call = self
            .call
            .lock()
            .unwrap()
            .clone()
            .ok_or_else(|| anyhow!("station mesh is not ready"))?;
        call(station.to_string(), request).await
    }

    pub fn allowed(&self, peer: &str) -> bool {
        self.settings
            .raw()
            .rest
            .get("remoteTasks")
            .and_then(|v| v["allow"].as_array())
            .is_some_and(|a| a.iter().any(|v| v.as_str() == Some(peer)))
    }

    /// Called only after the transport authenticates the source station and checks current workspace membership.
    pub async fn handle(&self, workspace: &str, peer: &str, request: Value) -> Result<Value> {
        let method = text(&request, "method");
        if method == "describe" {
            return Ok(
                json!({"protocol":1,"os":std::env::consts::OS,"arch":std::env::consts::ARCH,"tasks":self.allowed(peer),"sessions":true,"fileChunkBytes":CHUNK,"maxFileBytes":MAX_FILE}),
            );
        }
        if !self.allowed(peer) {
            bail!(
                "remote tasks are not enabled for this source station; a target administrator must add its public key to remoteTasks.allow"
            );
        }
        let _guard = self.serial.lock().await;
        let session = text(&request, "session");
        if method == "task.list" {
            if session.is_empty() || session.len() > 256 {
                bail!("session is required");
            }
            let mut tasks = Vec::new();
            for entry in std::fs::read_dir(self.root.join("incoming"))?.flatten() {
                let Ok(meta) = read(&entry.path().join("task.json")) else {
                    continue;
                };
                if text(&meta, "workspace") != workspace || text(&meta, "station") != peer || text(&meta, "session") != session {
                    continue;
                }
                let job = self.store.get_job(&format!("remote_{}", entry.file_name().to_string_lossy()))?;
                tasks.push(json!({"key":meta["key"],"spec":meta["spec"],"job":job}));
            }
            return Ok(json!({"tasks":tasks}));
        }
        if method == "session.close" {
            if session.is_empty() || session.len() > 256 {
                bail!("session is required");
            }
            self.close_here(workspace, peer, session).await?;
            return Ok(json!({"closed":true}));
        }
        let key = text(&request, "key");
        if session.is_empty() || session.len() > 256 || key.is_empty() || key.len() > 128 {
            bail!("session and task key are required (at most 256 / 128 bytes)");
        }
        let id = hash(&json!([workspace, peer, session, key]));
        let dir = self.root.join("incoming").join(&id);
        let record = dir.join("task.json");
        let job_id = format!("remote_{id}");
        let owner = format!("remote:{workspace}:{peer}:{session}");
        if method == "task.prepare" {
            let spec = request["spec"].clone();
            if text(&spec, "command").trim().is_empty() {
                bail!("command is required");
            }
            if record.exists() {
                if read(&record)?["spec"] != spec {
                    bail!("task key already used with different inputs; choose a new key for new work");
                }
            } else {
                std::fs::create_dir_all(&dir)?;
                write(
                    &record,
                    &json!({"spec":spec,"workspace":workspace,"station":peer,"session":session,"key":key,"layout":"session"}),
                )?;
            }
            self.seen(workspace, peer, session)?;
            return Ok(json!({"key":key,"prepared":true}));
        }
        let mut meta = read(&record).map_err(|_| anyhow!("unknown task"))?;
        let job = self.store.get_job(&job_id)?;
        // Tasks prepared before shared session directories keep their own.
        let work = if meta["layout"] == "session" {
            if matches!(method, "task.start" | "file.put") {
                self.seen(workspace, peer, session)?
            } else {
                self.room(workspace, peer, session).join("work")
            }
        } else {
            dir.join("work")
        };
        match method {
            "task.start" => {
                if meta["uploads"].as_object().is_some_and(|m| m.values().any(|v| v != true)) {
                    bail!("input upload is incomplete; finish it before starting");
                }
                let spec = &meta["spec"];
                let job = self.jobs.start_id(
                    &owner,
                    text(spec, "name"),
                    text(spec, "command"),
                    &work,
                    None,
                    Watch::default(),
                    Some(&job_id),
                )?;
                Ok(json!({"key":key,"job":job}))
            }
            "task.get" | "task.log" => Ok(
                json!({"key":key,"job":job,"log":job.as_ref().map(|j| crate::jobs::tail(Path::new(&j.log), request["lines"].as_u64().unwrap_or(50).clamp(1,1000) as usize)),"notices":self.store.job_notices(&job_id,20)?}),
            ),
            "task.stop" => {
                let job = job.ok_or_else(|| anyhow!("task has not started"))?;
                Ok(json!({"key":key,"job":self.jobs.stop(&job.id).await?}))
            }
            "file.put" => {
                if job.is_some() {
                    bail!("inputs are immutable after a task starts");
                }
                let offset = request["offset"].as_u64().ok_or_else(|| anyhow!("offset is required"))?;
                let bytes = B64.decode(text(&request, "data"))?;
                if bytes.len() > CHUNK || offset.saturating_add(bytes.len() as u64) > MAX_FILE {
                    bail!("file limit exceeded");
                }
                let path = file_path(&work, text(&request, "path"), true)?;
                if !meta["uploads"].is_object() {
                    meta["uploads"] = json!({});
                }
                meta["uploads"][text(&request, "path")] = json!(false);
                write(&record, &meta)?;
                let mut options = std::fs::OpenOptions::new();
                options.create(true).write(true);
                use std::os::unix::fs::OpenOptionsExt;
                options.custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK);
                let mut f = options.open(&path)?;
                if !f.metadata()?.is_file() { bail!("only regular files can be transferred"); }
                if offset > f.metadata()?.len() {
                    bail!("file offset leaves a gap");
                }
                f.seek(SeekFrom::Start(offset))?;
                f.write_all(&bytes)?;
                if request["final"] == true {
                    f.set_len(offset + bytes.len() as u64)?;
                    f.sync_all()?;
                }
                if request["final"] == true {
                    meta["uploads"][text(&request, "path")] = json!(true);
                    write(&record, &meta)?;
                }
                Ok(json!({"bytes":bytes.len()}))
            }
            "file.get" => {
                if job.as_ref().is_some_and(|j| j.state == "running") {
                    bail!("wait for the task to finish before downloading artifacts");
                }
                let path = file_path(&work, text(&request, "path"), false)?;
                let mut options = std::fs::OpenOptions::new();
                use std::os::unix::fs::OpenOptionsExt;
                options.read(true).custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK);
                let mut f = options.open(path)?;
                if !f.metadata()?.is_file() {
                    bail!("only regular files can be transferred");
                }
                let size = f.metadata()?.len();
                if size > MAX_FILE {
                    bail!("file limit exceeded");
                }
                let offset = request["offset"].as_u64().unwrap_or(0);
                if offset > size {
                    bail!("offset past end");
                }
                f.seek(SeekFrom::Start(offset))?;
                let mut bytes = vec![0; CHUNK];
                let n = f.read(&mut bytes)?;
                Ok(json!({"data":B64.encode(&bytes[..n]),"size":size,"eof":offset+n as u64>=size}))
            }
            _ => bail!("unsupported peer method: {method}"),
        }
    }

    /// Removed peers and withdrawn local permissions stop their tasks, without touching any local jobs.
    pub async fn revoke(&self, workspace: &str, peers: &[String], membership_current: bool) {
        let _guard = self.serial.lock().await;
        if let Ok(entries) = std::fs::read_dir(self.root.join("incoming")) {
            for entry in entries.flatten() {
                let Ok(meta) = read(&entry.path().join("task.json")) else {
                    continue;
                };
                let peer = text(&meta, "station");
                if self.allowed(peer) && (!membership_current || (text(&meta, "workspace") == workspace && peers.iter().any(|p| p == peer)))
                {
                    continue;
                }
                let id = format!("remote_{}", entry.file_name().to_string_lossy());
                if self.store.get_job(&id).ok().flatten().is_some_and(|j| j.state == "running") {
                    let _ = self.jobs.stop(&id).await;
                }
            }
        }
    }

    fn workspace(&self) -> Result<String> {
        let state = read(&self.settings.data_dir.join("mesh/cloud.json"))?;
        if !state["removed_at"].is_null() {
            bail!("station was removed from workspace");
        }
        let ws = text(&state, "workspace");
        if ws.is_empty() {
            bail!("station has no workspace");
        }
        Ok(ws.to_string())
    }

    fn outgoing(&self, workspace: &str, session: &str, station: &str, key: &str) -> PathBuf {
        self.root
            .join("outgoing")
            .join(format!("{}.json", hash(&json!([workspace, session, station, key]))))
    }

    fn watch(self: &Arc<Self>, path: PathBuf) {
        if !self.watching.lock().unwrap().insert(path.clone()) {
            return;
        }
        let me = Arc::downgrade(self);
        tokio::spawn(async move {
            loop {
                let Some(remote) = me.upgrade() else {
                    return;
                };
                let Ok(mut entry) = read(&path) else {
                    break;
                };
                if entry["delivered"] == true {
                    break;
                }
                let request = json!({"method":"task.get","workspace":entry["workspace"],"session":entry["session"],"key":entry["key"]});
                if let Ok(result) = remote.call(text(&entry, "station"), request).await {
                    let state = text(&result["job"], "state");
                    let notices = result["notices"].clone();
                    let finished = !state.is_empty() && state != "running";
                    if finished || (notices.as_array().is_some_and(|n| !n.is_empty()) && entry["notices"] != notices) {
                        let message = format!("Remote task {} on {}: {}", text(&entry, "key"), text(&entry, "station"), result);
                        if (remote.notify)(text(&entry, "session"), message).is_ok() {
                            entry["notices"] = notices;
                            entry["delivered"] = json!(finished);
                            let _ = write(&path, &entry);
                        }
                    }
                    if finished && entry["delivered"] == true {
                        break;
                    }
                }
                drop(remote);
                tokio::time::sleep(std::time::Duration::from_secs(5)).await;
            }
            if let Some(remote) = me.upgrade() {
                remote.watching.lock().unwrap().remove(&path);
            }
        });
    }

    pub fn tools(self: &Arc<Self>) -> Vec<Tool> {
        let mut tools = Vec::new();
        for (name, description, schema) in [
            (
                "station_list",
                "List stations in this workspace. With station, ask its OS, architecture and whether it accepts tasks from here. Old stations may not support peer calls.",
                json!({"type":"object","properties":{"station":{"type":"string"}},"additionalProperties":false}),
            ),
            (
                "station_task",
                "Run a shell task on a trusted workspace station. All tasks of this session run in one persistent directory there (shared, so a later task can build in what an earlier one cloned); keep checkouts and build output inside it, not elsewhere on that machine. It is removed, with anything still running, when this chat is archived or deleted, or after 14 days unused. action prepare records command/name with a caller-chosen stable key; upload inputs with station_file; action start executes it once. Reuse the same key after uncertain replies; use a new key for new work. get/log/stop address the same task. Completion and job notices return here, including after reconnect/restart. Commands run as the remote station OS user, not in a sandbox. A lost process is marked failed with unknown exit, never automatically re-executed.",
                json!({"type":"object","properties":{"station":{"type":"string"},"key":{"type":"string"},"action":{"enum":["prepare","start","get","log","stop","list"]},"command":{"type":"string"},"name":{"type":"string"},"lines":{"type":"integer"}},"required":["station","action"],"additionalProperties":false}),
            ),
            (
                "station_file",
                "Upload an input before starting a remote task, or download a task artifact to this session. path is relative to this session's directory on that station; local is a path in this session workspace. Files are transferred in chunks, up to 1 GiB each; repeat upload after a disconnect. direction is upload/download. Downloads never overwrite an existing local file. Post downloaded artifacts using chat_post files.",
                json!({"type":"object","properties":{"station":{"type":"string"},"key":{"type":"string"},"direction":{"enum":["upload","download"]},"path":{"type":"string"},"local":{"type":"string"}},"required":["station","key","direction","path","local"],"additionalProperties":false}),
            ),
        ] {
            let remote = self.clone();
            tools.push(Tool {
                name: name.into(),
                description: description.into(),
                input_schema: schema,
                run: Arc::new(move |session, args| {
                    let remote = remote.clone();
                    Box::pin(async move {
                        Ok(serde_json::to_string_pretty(
                            &remote.tool(name, &session, Value::Object(args)).await?,
                        )?)
                    })
                }),
            });
        }
        tools
    }

    async fn tool(self: &Arc<Self>, tool: &str, session: &str, args: Value) -> Result<Value> {
        let row = self.store.get_session(session)?.ok_or_else(|| anyhow!("unknown session"))?;
        let station = text(&args, "station");
        if tool == "station_list" {
            return self
                .call(station, json!({"method":if station.is_empty(){"peers"}else{"describe"}}))
                .await;
        }
        let key = text(&args, "key");
        if station.is_empty() || (key.is_empty() && !(tool == "station_task" && args["action"] == "list")) {
            bail!("station and key are required (list needs only station)");
        }
        let workspace = self.workspace()?;
        if !(tool == "station_task" && args["action"] == "list") {
            self.record_use(&workspace, session, station)?;
        }
        let mut request = json!({"workspace":workspace,"session":session,"key":key});
        if tool == "station_task" {
            let action = text(&args, "action");
            if !["prepare", "start", "get", "log", "stop", "list"].contains(&action) {
                bail!("unknown task action");
            }
            request["method"] = json!(format!("task.{action}"));
            request["lines"] = args["lines"].clone();
            request["spec"] = json!({"name":args["name"],"command":args["command"],"requestedBy":row.created_by});
            if action == "start" {
                // Persist before sending: an uncertain start is still followed after a process restart.
                let path = self.outgoing(&workspace, session, station, key);
                if !path.exists() || read(&path).is_ok_and(|v| v["refused"] == true) {
                    write(
                        &path,
                        &json!({"workspace":workspace,"session":session,"station":station,"key":key,"delivered":false}),
                    )?;
                }
                self.watch(path);
            }
            let result = self.call(station, request).await;
            if action == "start" && result.as_ref().is_err_and(|e| e.downcast_ref::<Refused>().is_some()) {
                let path = self.outgoing(&workspace, session, station, key);
                if let Ok(mut entry) = read(&path) {
                    entry["delivered"] = json!(true);
                    entry["refused"] = json!(true);
                    write(&path, &entry)?;
                }
            }
            return result;
        }
        let root = PathBuf::from(row.workspace);
        let local_arg = Path::new(text(&args, "local"));
        let relative = if local_arg.is_absolute() {
            local_arg
                .strip_prefix(&root)
                .map_err(|_| anyhow!("local file must be inside this session workspace"))?
        } else {
            local_arg
        };
        let path = file_path(&root, &relative.to_string_lossy(), text(&args, "direction") == "download")?;
        request["path"] = args["path"].clone();
        match text(&args, "direction") {
            "upload" => {
                use std::os::unix::fs::OpenOptionsExt;
                let mut f = std::fs::OpenOptions::new()
                    .read(true)
                    .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
                    .open(&path)?;
                let size = f.metadata()?.len();
                if !f.metadata()?.is_file() || size > MAX_FILE {
                    bail!("input must be a regular file of at most 1 GiB");
                }
                let mut offset = 0;
                loop {
                    let mut bytes = vec![0; CHUNK];
                    let n = f.read(&mut bytes)?;
                    request["method"] = json!("file.put");
                    request["offset"] = json!(offset);
                    request["data"] = json!(B64.encode(&bytes[..n]));
                    request["final"] = json!(offset + n as u64 == size);
                    self.call(station, request.clone()).await?;
                    offset += n as u64;
                    if offset == size {
                        break;
                    }
                    if n == 0 {
                        bail!("input changed while reading");
                    }
                }
                Ok(json!({"uploaded":path,"bytes":size}))
            }
            "download" => {
                if path.exists() {
                    bail!("local output already exists; choose another path");
                }
                let mut nonce = [0u8; 8];
                getrandom::fill(&mut nonce).map_err(|e| anyhow!("random: {e}"))?;
                let temp = path.with_extension(format!("{}.part", hex::encode(nonce)));
                let mut f = std::fs::OpenOptions::new().write(true).create_new(true).open(&temp)?;
                let result: Result<u64> = async {
                    let mut offset = 0;
                    loop {
                        request["method"] = json!("file.get");
                        request["offset"] = json!(offset);
                        let answer = self.call(station, request.clone()).await?;
                        let bytes = B64.decode(text(&answer, "data"))?;
                        if bytes.len() > CHUNK || offset + bytes.len() as u64 > MAX_FILE {
                            bail!("invalid file response");
                        }
                        f.write_all(&bytes)?;
                        offset += bytes.len() as u64;
                        if answer["eof"] == true {
                            f.sync_all()?;
                            return Ok(offset);
                        }
                        if bytes.is_empty() {
                            bail!("file transfer made no progress");
                        }
                    }
                }
                .await;
                drop(f);
                let result = result.and_then(|size| {
                    std::fs::hard_link(&temp, &path)?;
                    Ok(json!({"downloaded":path,"bytes":size}))
                });
                let _ = std::fs::remove_file(&temp);
                result
            }
            _ => bail!("direction must be upload or download"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn transfer_paths_do_not_escape_or_follow_links() {
        let dir = tempfile::tempdir().unwrap();
        for path in ["", "/etc/passwd", "../secret", "a/../../secret"] {
            assert!(file_path(dir.path(), path, true).is_err(), "{path}");
        }
        std::os::unix::fs::symlink("/tmp", dir.path().join("link")).unwrap();
        assert!(file_path(dir.path(), "link/file", true).is_err());
        assert!(file_path(&dir.path().join("link"), "file", true).is_err());
        assert!(file_path(dir.path(), "nested/file", true).unwrap().starts_with(dir.path()));
    }
}

#[cfg(test)]
mod task_tests {
    use super::*;
    fn rig() -> (tempfile::TempDir, Arc<Remote>) {
        let dir = tempfile::tempdir().unwrap();
        let settings = Settings::open(&dir.path().join("config.json"), dir.path()).unwrap();
        settings
            .update(|raw| {
                raw.rest.insert("remoteTasks".into(), json!({"allow":["peer-a","peer-b"]}));
                Ok(())
            })
            .unwrap();
        let store = Arc::new(Store::open(":memory:", None).unwrap());
        let jobs = Jobs::new(store.clone(), dir.path(), Arc::new(|_, _| {}), Arc::new(|_, _| None)).unwrap();
        let remote = Remote::new(settings, store, jobs, Arc::new(|_, _| Ok(()))).unwrap();
        (dir, remote)
    }
    async fn call(r: &Remote, peer: &str, method: &str, more: Value) -> Result<Value> {
        let mut args = json!({"session":"s","key":"build-1","method":method});
        for (key, value) in more.as_object().unwrap() {
            args[key] = value.clone();
        }
        r.handle("ws", peer, args).await
    }
    #[tokio::test]
    async fn tasks_are_owned_idempotent_and_return_files() {
        let (_dir, r) = rig();
        let spec = json!({"spec":{"command":"cat input > output; echo ran >> count","name":"copy"}});
        call(&r, "peer-a", "task.prepare", spec.clone()).await.unwrap();
        call(
            &r,
            "peer-a",
            "file.put",
            json!({"path":"input","offset":0,"data":B64.encode("hello"),"final":true}),
        )
        .await
        .unwrap();
        let first = call(&r, "peer-a", "task.start", json!({})).await.unwrap();
        for _ in 0..200 {
            if call(&r, "peer-a", "task.get", json!({})).await.unwrap()["job"]["state"] != "running" {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(25)).await;
        }
        let again = call(&r, "peer-a", "task.start", json!({})).await.unwrap();
        assert_eq!(first["job"]["id"], again["job"]["id"]);
        assert_eq!(again["job"]["exitCode"], 0);
        for (path, expected) in [("output", "hello"), ("count", "ran\n")] {
            let file = call(&r, "peer-a", "file.get", json!({"path":path})).await.unwrap();
            assert_eq!(B64.decode(text(&file, "data")).unwrap(), expected.as_bytes());
        }
        assert!(call(&r, "peer-b", "task.get", json!({})).await.is_err());
        assert!(call(&r, "peer-c", "task.prepare", spec).await.is_err());
        assert!(call(&r, "peer-a", "task.get", json!({"session":"other"})).await.is_err());
        assert!(
            call(&r, "peer-a", "task.prepare", json!({"spec":{"command":"echo wrong"}}))
                .await
                .is_err()
        );
        assert!(
            call(&r, "peer-a", "file.put", json!({"path":"input","offset":0,"data":"","final":true}))
                .await
                .is_err()
        );
    }
    #[tokio::test]
    async fn withdrawal_stops_only_the_revoked_peers_task() {
        let (_dir, r) = rig();
        for peer in ["peer-a", "peer-b"] {
            call(&r, peer, "task.prepare", json!({"spec":{"command":"sleep 30"}}))
                .await
                .unwrap();
            call(&r, peer, "task.start", json!({})).await.unwrap();
        }
        r.revoke("ws", &["peer-b".into()], true).await;
        assert_eq!(call(&r, "peer-a", "task.get", json!({})).await.unwrap()["job"]["state"], "stopped");
        assert_eq!(call(&r, "peer-b", "task.get", json!({})).await.unwrap()["job"]["state"], "running");
        call(&r, "peer-b", "task.stop", json!({})).await.unwrap();
    }
}

#[cfg(test)]
mod session_tests {
    use super::*;
    fn rig() -> (tempfile::TempDir, Arc<Remote>) {
        let dir = tempfile::tempdir().unwrap();
        let settings = Settings::open(&dir.path().join("config.json"), dir.path()).unwrap();
        settings
            .update(|raw| {
                raw.rest.insert("remoteTasks".into(), json!({"allow":["peer-a"]}));
                Ok(())
            })
            .unwrap();
        let store = Arc::new(Store::open(":memory:", None).unwrap());
        let jobs = Jobs::new(store.clone(), dir.path(), Arc::new(|_, _| {}), Arc::new(|_, _| None)).unwrap();
        let remote = Remote::new(settings, store, jobs, Arc::new(|_, _| Ok(()))).unwrap();
        (dir, remote)
    }
    async fn call(r: &Remote, session: &str, key: &str, method: &str, more: Value) -> Result<Value> {
        let mut args = json!({"session":session,"key":key,"method":method});
        for (k, v) in more.as_object().unwrap() {
            args[k] = v.clone();
        }
        r.handle("ws", "peer-a", args).await
    }
    async fn run(r: &Remote, session: &str, key: &str, command: &str) -> Value {
        call(r, session, key, "task.prepare", json!({"spec":{"command":command}})).await.unwrap();
        call(r, session, key, "task.start", json!({})).await.unwrap();
        for _ in 0..200 {
            let got = call(r, session, key, "task.get", json!({})).await.unwrap();
            if got["job"]["state"] != "running" {
                return got;
            }
            tokio::time::sleep(std::time::Duration::from_millis(25)).await;
        }
        panic!("task did not finish");
    }

    #[tokio::test]
    async fn a_sessions_tasks_share_one_directory_that_closing_removes() {
        let (_dir, r) = rig();
        run(&r, "s", "clone", "mkdir repo && echo built > repo/out").await;
        assert_eq!(run(&r, "s", "build", "cat repo/out > copy").await["job"]["exitCode"], 0);
        let copy = call(&r, "s", "build", "file.get", json!({"path":"copy"})).await.unwrap();
        assert_eq!(B64.decode(text(&copy, "data")).unwrap(), b"built\n");
        // Another session starts empty and is left alone when the first closes.
        assert_ne!(run(&r, "t", "look", "test -e repo").await["job"]["exitCode"], 0);
        call(&r, "s", "long", "task.prepare", json!({"spec":{"command":"sleep 30"}})).await.unwrap();
        let long = call(&r, "s", "long", "task.start", json!({})).await.unwrap();
        r.handle("ws", "peer-a", json!({"method":"session.close","session":"s"})).await.unwrap();
        assert!(!r.room("ws", "peer-a", "s").exists());
        assert_eq!(r.store.get_job(text(&long["job"], "id")).unwrap().unwrap().state, "stopped");
        assert!(call(&r, "s", "build", "task.get", json!({})).await.is_err(), "records go with the directory");
        assert!(r.room("ws", "peer-a", "t").join("work").exists());
        // Closing again (a retried request) is fine.
        r.handle("ws", "peer-a", json!({"method":"session.close","session":"s"})).await.unwrap();
    }

    #[tokio::test]
    async fn the_target_removes_idle_session_and_old_task_directories_itself() {
        let (_dir, r) = rig();
        run(&r, "idle", "a", "touch made").await;
        run(&r, "recent", "a", "touch made").await;
        let old = r.root.join("incoming").join("from-before");
        std::fs::create_dir_all(old.join("work")).unwrap();
        write(&old.join("task.json"), &json!({"spec":{"command":"true"},"workspace":"ws","station":"peer-a","session":"x","key":"k"})).unwrap();
        let later = crate::store::now_ms() + IDLE_MS + 1000;
        let record = r.room("ws", "peer-a", "recent").join("session.json");
        let mut seen = read(&record).unwrap();
        seen["seen"] = json!(later);
        write(&record, &seen).unwrap();
        r.sweep(later).await;
        assert!(!r.room("ws", "peer-a", "idle").exists());
        assert!(r.room("ws", "peer-a", "recent").exists());
        assert!(!old.exists());
    }

    #[tokio::test(start_paused = true)]
    async fn closing_a_source_session_asks_each_used_station_until_answered() {
        let (dir, r) = rig();
        std::fs::create_dir_all(dir.path().join("mesh")).unwrap();
        r.record_use("ws", "s", "up").unwrap();
        r.record_use("ws", "s", "old").unwrap();
        r.record_use("ws", "s", "down").unwrap();
        r.record_use("ws", "other", "up").unwrap();
        let asked: Arc<Mutex<Vec<String>>> = Arc::default();
        let (seen, down) = (asked.clone(), Arc::new(std::sync::atomic::AtomicUsize::new(0)));
        let fails = down.clone();
        r.attach(Arc::new(move |station, request| {
            assert_eq!(request["method"], "session.close");
            assert_eq!(request["session"], "s");
            seen.lock().unwrap().push(station.clone());
            let n = if station == "down" { fails.fetch_add(1, std::sync::atomic::Ordering::SeqCst) } else { 0 };
            Box::pin(async move {
                match station.as_str() {
                    "old" => Err(Refused("unsupported peer method: session.close".into()).into()),
                    "down" if n < 2 => bail!("offline"),
                    _ => Ok(json!({"closed":true})),
                }
            })
        }));
        r.close_session("s");
        let path = r.used_path("s");
        for _ in 0..300 {
            tokio::time::advance(std::time::Duration::from_secs(1)).await;
            tokio::task::yield_now().await;
            if !path.exists() {
                break;
            }
        }
        assert!(!path.exists(), "every station answered");
        let asked = asked.lock().unwrap().clone();
        assert_eq!(asked.iter().filter(|s| *s == "up").count(), 1);
        assert_eq!(asked.iter().filter(|s| *s == "old").count(), 1);
        assert_eq!(asked.iter().filter(|s| *s == "down").count(), 3);
        assert!(r.used_path("other").exists());
    }
}

#[cfg(test)]
mod recovery_tests {
    use super::*;
    #[tokio::test(start_paused = true)]
    async fn a_persisted_receipt_reconnects_and_delivers_to_its_original_session() {
        let dir = tempfile::tempdir().unwrap();
        let settings = Settings::open(&dir.path().join("config.json"), dir.path()).unwrap();
        let store = Arc::new(Store::open(":memory:", None).unwrap());
        let jobs = Jobs::new(store.clone(), dir.path(), Arc::new(|_, _| {}), Arc::new(|_, _| None)).unwrap();
        let remote = Remote::new(settings.clone(), store.clone(), jobs.clone(), Arc::new(|_, _| Ok(()))).unwrap();
        let path = remote.outgoing("ws", "original-session", "target", "stable-key");
        write(
            &path,
            &json!({"workspace":"ws","session":"original-session","station":"target","key":"stable-key","delivered":false}),
        )
        .unwrap();
        drop(remote);
        let messages: Arc<Mutex<Vec<(String, String)>>> = Arc::default();
        let told = messages.clone();
        let restarted = Remote::new(
            settings,
            store,
            jobs,
            Arc::new(move |session, message| {
                told.lock().unwrap().push((session.into(), message));
                Ok(())
            }),
        )
        .unwrap();
        let attempts = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let calls = attempts.clone();
        restarted.attach(Arc::new(move |station, request| {
            let n = calls.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            Box::pin(async move {
                assert_eq!(station, "target");
                assert_eq!(request["workspace"], "ws");
                assert_eq!(request["session"], "original-session");
                assert_eq!(request["key"], "stable-key");
                assert_eq!(request["method"], "task.get", "recovery queries; it does not resubmit the command");
                if n < 2 {
                    bail!("offline");
                }
                Ok(json!({"job":{"state":"exited","exitCode":0},"log":"done","notices":[]}))
            })
        }));
        for _ in 0..20 {
            tokio::time::advance(std::time::Duration::from_secs(1)).await;
            tokio::task::yield_now().await;
            if read(&path).unwrap()["delivered"] == true {
                break;
            }
        }
        assert_eq!(attempts.load(std::sync::atomic::Ordering::SeqCst), 3);
        assert_eq!(messages.lock().unwrap().len(), 1);
        assert_eq!(messages.lock().unwrap()[0].0, "original-session");
        assert!(messages.lock().unwrap()[0].1.contains("done"));
        assert_eq!(read(&path).unwrap()["delivered"], true);
    }
}
