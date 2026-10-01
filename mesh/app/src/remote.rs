//! Workspace peers call named operations over an authenticated station transport. Shell tasks are one service on
//! that transport, never an admin API proxy. An administrator explicitly trusts source station keys in config.json:
//! remoteTasks.allow = ["<station public key>"]. This grants shell execution as the station's OS user, not a sandbox.
use std::{collections::HashSet, io::{Read, Seek, SeekFrom, Write}, path::{Component, Path, PathBuf}, sync::{Arc, Mutex, Weak}};
use anyhow::{Result, anyhow, bail};
use base64::{Engine, engine::general_purpose::STANDARD as B64};
use futures_util::future::BoxFuture;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use crate::{hub::Hub, jobs::{Jobs, Watch}, mcp::Tool, settings::Settings, store::Store};

pub type Call = Arc<dyn Fn(String, Value) -> BoxFuture<'static, Result<Value>> + Send + Sync>;
pub const CHUNK: usize = 256 * 1024;
const MAX_FILE: u64 = 1024 * 1024 * 1024;

pub struct Remote {
    settings: Arc<Settings>,
    store: Arc<Store>,
    jobs: Arc<Jobs>,
    hub: Weak<Hub>,
    root: PathBuf,
    call: Mutex<Option<Call>>,
    serial: tokio::sync::Mutex<()>,
    watching: Mutex<HashSet<PathBuf>>,
}

fn text<'a>(v: &'a Value, key: &str) -> &'a str { v[key].as_str().unwrap_or("") }
fn hash(v: &Value) -> String { hex::encode(Sha256::digest(v.to_string().as_bytes())) }
fn read(path: &Path) -> Result<Value> { Ok(serde_json::from_slice(&std::fs::read(path)?)?) }
fn write(path: &Path, value: &Value) -> Result<()> {
    let mut nonce=[0u8;8];
    getrandom::fill(&mut nonce).map_err(|e|anyhow!("random: {e}"))?;
    let temp = path.with_extension(format!("{}.tmp",hex::encode(nonce)));
    let mut file = std::fs::File::create(&temp)?;
    file.write_all(&serde_json::to_vec(value)?)?;
    file.sync_all()?;
    std::fs::rename(temp, path)?;
    Ok(())
}

/// Relative paths only; transfers must not follow links planted by a task. Task commands themselves are trusted
/// shell execution, so separate working directories are organizational isolation, not an OS security boundary.
fn file_path(root: &Path, relative: &str, create: bool) -> Result<PathBuf> {
    let path = Path::new(relative);
    if relative.is_empty() || path.components().any(|c| !matches!(c, Component::Normal(_))) { bail!("file path must be relative, without . or .."); }
    let mut out = root.to_path_buf();
    for c in path.components() {
        out.push(c);
        if std::fs::symlink_metadata(&out).is_ok_and(|m| m.file_type().is_symlink()) { bail!("file path contains a symbolic link"); }
    }
    if create { std::fs::create_dir_all(out.parent().ok_or_else(|| anyhow!("no parent"))?)?; }
    Ok(out)
}

impl Remote {
    pub fn new(settings: Arc<Settings>, store: Arc<Store>, jobs: Arc<Jobs>, hub: Weak<Hub>) -> Result<Arc<Self>> {
        let root = settings.data_dir.join("remote");
        for name in ["incoming", "outgoing"] { std::fs::create_dir_all(root.join(name))?; }
        Ok(Arc::new(Self { settings, store, jobs, hub, root, call: Mutex::new(None), serial: tokio::sync::Mutex::new(()), watching: Mutex::new(HashSet::new()) }))
    }

    pub fn attach(self: &Arc<Self>, call: Call) {
        *self.call.lock().unwrap() = Some(call);
        if let Ok(entries) = std::fs::read_dir(self.root.join("outgoing")) {
            for e in entries.flatten().filter(|e| e.path().extension().is_some_and(|x| x == "json")) { self.watch(e.path()); }
        }
    }

    async fn call(&self, station: &str, request: Value) -> Result<Value> {
        let call = self.call.lock().unwrap().clone().ok_or_else(|| anyhow!("station mesh is not ready"))?;
        call(station.to_string(), request).await
    }

    pub fn allowed(&self, peer: &str) -> bool {
        self.settings.raw().rest.get("remoteTasks").and_then(|v| v["allow"].as_array()).is_some_and(|a| a.iter().any(|v| v.as_str() == Some(peer)))
    }

    /// Called only after the transport authenticates the source station and checks current workspace membership.
    pub async fn handle(&self, workspace: &str, peer: &str, request: Value) -> Result<Value> {
        let method = text(&request, "method");
        if method == "describe" {
            return Ok(json!({"protocol":1,"os":std::env::consts::OS,"arch":std::env::consts::ARCH,"tasks":self.allowed(peer),"fileChunkBytes":CHUNK,"maxFileBytes":MAX_FILE}));
        }
        if !self.allowed(peer) { bail!("remote tasks are not enabled for this source station; a target administrator must add its public key to remoteTasks.allow"); }
        let _guard = self.serial.lock().await;
        let session = text(&request, "session");
        let key = text(&request, "key");
        if session.is_empty() || session.len() > 256 || key.is_empty() || key.len() > 128 { bail!("session and task key are required (at most 256 / 128 bytes)"); }
        let id = hash(&json!([workspace, peer, session, key]));
        let dir = self.root.join("incoming").join(&id);
        let record = dir.join("task.json");
        let job_id = format!("remote_{id}");
        let owner = format!("remote:{workspace}:{peer}:{session}");
        let work = dir.join("work");
        if method == "task.prepare" {
            let spec = request["spec"].clone();
            if text(&spec, "command").trim().is_empty() { bail!("command is required"); }
            if record.exists() {
                if read(&record)?["spec"] != spec { bail!("task key already used with different inputs; choose a new key for new work"); }
            } else {
                std::fs::create_dir_all(&work)?;
                write(&record, &json!({"spec":spec,"workspace":workspace,"station":peer,"session":session,"key":key}))?;
            }
            return Ok(json!({"key":key,"prepared":true}));
        }
        let mut meta = read(&record).map_err(|_| anyhow!("unknown task"))?;
        let job = self.store.get_job(&job_id)?;
        match method {
            "task.start" => {
                if meta["uploads"].as_object().is_some_and(|m|m.values().any(|v|v!=true)) {bail!("input upload is incomplete; finish it before starting");}
                let spec = &meta["spec"];
                let job = self.jobs.start_id(&owner, text(spec,"name"), text(spec,"command"), &work, None, Watch::default(), Some(&job_id))?;
                Ok(json!({"key":key,"job":job}))
            }
            "task.get" | "task.log" => Ok(json!({"key":key,"job":job,"log":job.as_ref().map(|j| crate::jobs::tail(Path::new(&j.log), request["lines"].as_u64().unwrap_or(50).clamp(1,1000) as usize)),"notices":self.store.job_notices(&job_id,20)?})),
            "task.stop" => {
                let job = job.ok_or_else(|| anyhow!("task has not started"))?;
                Ok(json!({"key":key,"job":self.jobs.stop(&job.id).await?}))
            }
            "file.put" => {
                if job.is_some() { bail!("inputs are immutable after a task starts"); }
                let offset = request["offset"].as_u64().ok_or_else(|| anyhow!("offset is required"))?;
                let bytes = B64.decode(text(&request,"data"))?;
                if bytes.len() > CHUNK || offset.saturating_add(bytes.len() as u64) > MAX_FILE { bail!("file limit exceeded"); }
                let path = file_path(&work, text(&request,"path"), true)?;
                if !meta["uploads"].is_object() {meta["uploads"]=json!({});}
                meta["uploads"][text(&request,"path")]=json!(false);
                write(&record,&meta)?;
                let mut options = std::fs::OpenOptions::new();
                options.create(true).write(true);
                use std::os::unix::fs::OpenOptionsExt;
                options.custom_flags(libc::O_NOFOLLOW);
                let mut f = options.open(&path)?;
                if offset > f.metadata()?.len() { bail!("file offset leaves a gap"); }
                f.seek(SeekFrom::Start(offset))?;
                f.write_all(&bytes)?;
                if request["final"] == true { f.set_len(offset + bytes.len() as u64)?; f.sync_all()?; }
                if request["final"] == true {
                    meta["uploads"][text(&request,"path")]=json!(true);
                    write(&record,&meta)?;
                }
                Ok(json!({"bytes":bytes.len()}))
            }
            "file.get" => {
                let path = file_path(&work, text(&request,"path"), false)?;
                let mut options = std::fs::OpenOptions::new();
                use std::os::unix::fs::OpenOptionsExt;
                options.read(true).custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK);
                let mut f = options.open(path)?;
                if !f.metadata()?.is_file() { bail!("only regular files can be transferred"); }
                let size = f.metadata()?.len();
                if size > MAX_FILE { bail!("file limit exceeded"); }
                let offset = request["offset"].as_u64().unwrap_or(0);
                if offset > size { bail!("offset past end"); }
                f.seek(SeekFrom::Start(offset))?;
                let mut bytes = vec![0; CHUNK];
                let n = f.read(&mut bytes)?;
                Ok(json!({"data":B64.encode(&bytes[..n]),"size":size,"eof":offset+n as u64>=size}))
            }
            _ => bail!("unsupported peer method: {method}"),
        }
    }

    /// Removed peers and withdrawn local permissions stop their tasks, without touching any local jobs.
    pub async fn revoke(&self, workspace: &str, peers: &[String]) {
        let _guard=self.serial.lock().await;
        if let Ok(entries)=std::fs::read_dir(self.root.join("incoming")) {
            for entry in entries.flatten() {
                let Ok(meta)=read(&entry.path().join("task.json")) else {continue};
                let peer=text(&meta,"station");
                if text(&meta,"workspace")==workspace && peers.iter().any(|p| p==peer) && self.allowed(peer) {continue;}
                let id=format!("remote_{}",entry.file_name().to_string_lossy());
                if self.store.get_job(&id).ok().flatten().is_some_and(|j|j.state=="running") { let _=self.jobs.stop(&id).await; }
            }
        }
    }

    fn workspace(&self) -> Result<String> {
        let state=read(&self.settings.data_dir.join("mesh/cloud.json"))?;
        if !state["removed_at"].is_null() { bail!("station was removed from workspace"); }
        let ws=text(&state,"workspace");
        if ws.is_empty() {bail!("station has no workspace");}
        Ok(ws.to_string())
    }

    fn outgoing(&self, session: &str, station: &str, key: &str) -> PathBuf {
        self.root.join("outgoing").join(format!("{}.json", hash(&json!([session,station,key]))))
    }

    fn watch(self: &Arc<Self>, path: PathBuf) {
        if !self.watching.lock().unwrap().insert(path.clone()) { return; }
        let me = Arc::downgrade(self);
        tokio::spawn(async move {
            loop {
                let Some(remote) = me.upgrade() else { return; };
                let Ok(mut entry) = read(&path) else { break; };
                if entry["delivered"] == true { break; }
                let request = json!({"method":"task.get","workspace":entry["workspace"],"session":entry["session"],"key":entry["key"]});
                if let Ok(result) = remote.call(text(&entry,"station"), request).await {
                    let state = text(&result["job"], "state");
                    let notices = result["notices"].clone();
                    let finished = !state.is_empty() && state != "running";
                    if finished || (notices.as_array().is_some_and(|n| !n.is_empty()) && entry["notices"] != notices) {
                        let message = format!("Remote task {} on {}: {}", text(&entry,"key"), text(&entry,"station"), result);
                        if let Some(hub) = remote.hub.upgrade() {
                            if hub.notify(text(&entry,"session"), message).is_ok() {
                                entry["notices"] = notices;
                                entry["delivered"] = json!(finished);
                                let _ = write(&path, &entry);
                            }
                        }
                    }
                    if finished && entry["delivered"] == true { break; }
                }
                drop(remote);
                tokio::time::sleep(std::time::Duration::from_secs(5)).await;
            }
            if let Some(remote) = me.upgrade() { remote.watching.lock().unwrap().remove(&path); }
        });
    }

    pub fn tools(self: &Arc<Self>) -> Vec<Tool> {
        let mut tools = Vec::new();
        for (name, description, schema) in [
            ("station_list", "List stations in this workspace. With station, ask its OS, architecture and whether it accepts tasks from here. Old stations may not support peer calls.", json!({"type":"object","properties":{"station":{"type":"string"}},"additionalProperties":false})),
            ("station_task", "Run a shell task on a trusted workspace station, in its own persistent directory. action prepare records command/name with a caller-chosen stable key; upload inputs with station_file; action start executes it once. Reuse the same key after uncertain replies; use a new key for new work. get/log/stop address the same task. Completion and job notices return here, including after reconnect/restart. Commands run as the remote station OS user, not in a sandbox. A lost process is marked failed with unknown exit, never automatically re-executed.", json!({"type":"object","properties":{"station":{"type":"string"},"key":{"type":"string"},"action":{"enum":["prepare","start","get","log","stop"]},"command":{"type":"string"},"name":{"type":"string"},"lines":{"type":"integer"}},"required":["station","key","action"],"additionalProperties":false})),
            ("station_file", "Upload an input before starting a remote task, or download a task artifact to this session. path is relative to the task directory; local is a path in this session workspace. Files are transferred in chunks, up to 1 GiB each; repeat upload after a disconnect. direction is upload/download. Downloads never overwrite an existing local file. Post downloaded artifacts using chat_post files.", json!({"type":"object","properties":{"station":{"type":"string"},"key":{"type":"string"},"direction":{"enum":["upload","download"]},"path":{"type":"string"},"local":{"type":"string"}},"required":["station","key","direction","path","local"],"additionalProperties":false})),
        ] {
            let remote = self.clone();
            tools.push(Tool { name:name.into(), description:description.into(), input_schema:schema, run:Arc::new(move |session,args| {
                let remote = remote.clone();
                Box::pin(async move { Ok(serde_json::to_string_pretty(&remote.tool(name, &session, Value::Object(args)).await?)?) })
            }) });
        }
        tools
    }

    async fn tool(self: &Arc<Self>, tool: &str, session: &str, args: Value) -> Result<Value> {
        let row = self.store.get_session(session)?.ok_or_else(|| anyhow!("unknown session"))?;
        let station = text(&args,"station");
        if tool == "station_list" { return self.call(station, json!({"method":if station.is_empty(){"peers"}else{"describe"}})).await; }
        let key = text(&args,"key");
        if station.is_empty() || key.is_empty() { bail!("station and key are required"); }
        let workspace=self.workspace()?;
        let mut request = json!({"workspace":workspace,"session":session,"key":key});
        if tool == "station_task" {
            let action = text(&args,"action");
            if !["prepare","start","get","log","stop"].contains(&action) { bail!("unknown task action"); }
            request["method"] = json!(format!("task.{action}"));
            request["lines"] = args["lines"].clone();
            request["spec"] = json!({"name":args["name"],"command":args["command"],"requestedBy":row.created_by});
            if action == "start" {
                // Persist before sending: an uncertain start is still followed after a process restart.
                let path = self.outgoing(session,station,key);
                if !path.exists() { write(&path,&json!({"workspace":workspace,"session":session,"station":station,"key":key,"delivered":false}))?; }
                self.watch(path);
            }
            return self.call(station, request).await;
        }
        let root = PathBuf::from(row.workspace);
        let local_arg = Path::new(text(&args,"local"));
        let relative = if local_arg.is_absolute() { local_arg.strip_prefix(&root).map_err(|_| anyhow!("local file must be inside this session workspace"))? } else { local_arg };
        let path = file_path(&root, &relative.to_string_lossy(), text(&args,"direction")=="download")?;
        request["path"] = args["path"].clone();
        match text(&args,"direction") {
            "upload" => {
                let mut f = std::fs::File::open(&path)?;
                let size = f.metadata()?.len();
                if !f.metadata()?.is_file() || size > MAX_FILE { bail!("input must be a regular file of at most 1 GiB"); }
                let mut offset = 0;
                loop {
                    let mut bytes = vec![0;CHUNK];
                    let n = f.read(&mut bytes)?;
                    request["method"] = json!("file.put");
                    request["offset"] = json!(offset);
                    request["data"] = json!(B64.encode(&bytes[..n]));
                    request["final"] = json!(offset+n as u64==size);
                    self.call(station,request.clone()).await?;
                    offset += n as u64;
                    if offset == size { break; }
                    if n == 0 { bail!("input changed while reading"); }
                }
                Ok(json!({"uploaded":path,"bytes":size}))
            }
            "download" => {
                let mut f = std::fs::OpenOptions::new().write(true).create_new(true).open(&path)?;
                let result: Result<u64> = async {
                    let mut offset=0;
                    loop {
                        request["method"]=json!("file.get"); request["offset"]=json!(offset);
                        let answer=self.call(station,request.clone()).await?;
                        let bytes=B64.decode(text(&answer,"data"))?;
                        if bytes.len()>CHUNK || offset+bytes.len() as u64>MAX_FILE { bail!("invalid file response"); }
                        f.write_all(&bytes)?; offset+=bytes.len() as u64;
                        if answer["eof"]==true { f.sync_all()?; return Ok(offset); }
                        if bytes.is_empty() { bail!("file transfer made no progress"); }
                    }
                }.await;
                match result { Ok(size)=>Ok(json!({"downloaded":path,"bytes":size})), Err(e)=>{ drop(f); let _=std::fs::remove_file(&path); Err(e) } }
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
        let dir=tempfile::tempdir().unwrap();
        for path in ["","/etc/passwd","../secret","a/../../secret"] { assert!(file_path(dir.path(),path,true).is_err(),"{path}"); }
        std::os::unix::fs::symlink("/tmp",dir.path().join("link")).unwrap();
        assert!(file_path(dir.path(),"link/file",true).is_err());
        assert!(file_path(dir.path(),"nested/file",true).unwrap().starts_with(dir.path()));
    }
}

#[cfg(test)]
mod task_tests {
    use super::*;
    fn rig() -> (tempfile::TempDir, Arc<Remote>) {
        let dir=tempfile::tempdir().unwrap();
        let settings=Settings::open(&dir.path().join("config.json"),dir.path()).unwrap();
        settings.update(|raw| {raw.rest.insert("remoteTasks".into(),json!({"allow":["peer-a","peer-b"]}));Ok(())}).unwrap();
        let store=Arc::new(Store::open(":memory:",None).unwrap());
        let jobs=Jobs::new(store.clone(),dir.path(),Arc::new(|_,_|{}),Arc::new(|_,_|None)).unwrap();
        let remote=Remote::new(settings,store,jobs,Weak::new()).unwrap();
        (dir,remote)
    }
    async fn call(r:&Remote, peer:&str, method:&str, more:Value)->Result<Value> {
        let mut args=json!({"session":"s","key":"build-1","method":method});
        for (key,value) in more.as_object().unwrap() {args[key]=value.clone();}
        r.handle("ws",peer,args).await
    }
    #[tokio::test]
    async fn tasks_are_owned_idempotent_and_return_files() {
        let (_dir,r)=rig();
        let spec=json!({"spec":{"command":"cat input > output; echo ran >> count","name":"copy"}});
        call(&r,"peer-a","task.prepare",spec.clone()).await.unwrap();
        call(&r,"peer-a","file.put",json!({"path":"input","offset":0,"data":B64.encode("hello"),"final":true})).await.unwrap();
        let first=call(&r,"peer-a","task.start",json!({})).await.unwrap();
        for _ in 0..200 {
            if call(&r,"peer-a","task.get",json!({})).await.unwrap()["job"]["state"]!="running" {break;}
            tokio::time::sleep(std::time::Duration::from_millis(25)).await;
        }
        let again=call(&r,"peer-a","task.start",json!({})).await.unwrap();
        assert_eq!(first["job"]["id"],again["job"]["id"]);
        assert_eq!(again["job"]["exitCode"],0);
        for (path,expected) in [("output","hello"),("count","ran\n")] {
            let file=call(&r,"peer-a","file.get",json!({"path":path})).await.unwrap();
            assert_eq!(B64.decode(text(&file,"data")).unwrap(),expected.as_bytes());
        }
        assert!(call(&r,"peer-b","task.get",json!({})).await.is_err());
        assert!(call(&r,"peer-c","task.prepare",spec).await.is_err());
        assert!(call(&r,"peer-a","task.get",json!({"session":"other"})).await.is_err());
        assert!(call(&r,"peer-a","task.prepare",json!({"spec":{"command":"echo wrong"}})).await.is_err());
        assert!(call(&r,"peer-a","file.put",json!({"path":"input","offset":0,"data":"","final":true})).await.is_err());
    }
    #[tokio::test]
    async fn withdrawal_stops_only_the_revoked_peers_task() {
        let (_dir,r)=rig();
        for peer in ["peer-a","peer-b"] {
            call(&r,peer,"task.prepare",json!({"spec":{"command":"sleep 30"}})).await.unwrap();
            call(&r,peer,"task.start",json!({})).await.unwrap();
        }
        r.revoke("ws",&["peer-b".into()]).await;
        assert_eq!(call(&r,"peer-a","task.get",json!({})).await.unwrap()["job"]["state"],"stopped");
        assert_eq!(call(&r,"peer-b","task.get",json!({})).await.unwrap()["job"]["state"],"running");
        call(&r,"peer-b","task.stop",json!({})).await.unwrap();
    }
}
