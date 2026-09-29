//! Background jobs: commands a session's agent starts that the station runs and keeps, apart from the agent's turns.
//! Each runs in a process group of its own with its output in a log file; the agent hears when it ends, and whatever
//! the job says on the way (`ember-job notify …`). A job with a port is a web service: kept up (started again when it
//! ends, with a growing pause), and seen by the workspace's members through the station's /preview. Jobs outlive the
//! station: a restart takes up what still runs, and starts again what does not (the machine restarted).

use std::collections::HashMap;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, Weak};
use std::time::{Duration, Instant};

use anyhow::{Result, anyhow, bail};
use serde_json::{Map, Value, json};
use tokio::process::Command;
use tracing::{info, warn};

use crate::mcp::{Run, Tool};
use crate::runtime::process::{end_group, group_alive, signal_group, still_ours, watch_exit};
use crate::store::{JobRow, Store, now_ms};

/// At most this many jobs of one session run at once.
const MAX_RUNNING: usize = 20;
/// How much of a log job_log gives at most, and how many lines by default.
const LOG_BYTES: u64 = 64 * 1024;
const LOG_LINES: usize = 50;
/// How many of a job's notices the pages get with it.
const NOTICES_SHOWN: usize = 20;
/// A service that ran this long before it ended starts again at once; one that keeps ending waits longer each time.
const STEADY: Duration = Duration::from_secs(60);
const MAX_PAUSE: Duration = Duration::from_secs(60);
/// A job stopped from the pages is told to its agent only if the agent was at work this lately: one idle longer is not
/// woken for it (the job's state shows it stopped when the agent next looks).
const AWAKE: Duration = Duration::from_secs(5 * 60);

/// How a job's command runs: under a shell that writes its exit code to a file when it ends, so a station that did not
/// start it (it outlived the one that did) still learns how it ended.
const WRAPPER: &str = r#"/bin/sh -c "$1"; code=$?; printf '%s' "$code" > "$2"; exit "$code""#;

/// What `ember-job` is, in each job's PATH: `ember-job notify <words>` (or the words on stdin) tells the agent.
const EMBER_JOB: &str = r#"#!/bin/sh
# ember-job notify <words>: tells the agent that started this job (the words, or stdin's).
case "$1" in
  notify)
    shift
    if [ "$#" -gt 0 ]; then printf '%s' "$*"; else cat; fi |
      curl -fsS -X POST -H "Authorization: Bearer $EMBER_JOB_TOKEN" -H "content-type: text/plain; charset=utf-8" --data-binary @- "$EMBER_JOB_NOTIFY" >/dev/null
    ;;
  *) echo "usage: ember-job notify <words>" >&2; exit 2 ;;
esac
"#;

/// Tells a session's agent something (Hub::notify).
pub type Notify = Arc<dyn Fn(&str, String) + Send + Sync>;
/// A session's web service as members open it: its link (ember cloud's /o/ link of the session, naming the service),
/// when the station is in a workspace.
pub type Link = Arc<dyn Fn(&str, &str) -> Option<String> + Send + Sync>;

struct Running {
    pgid: i32,
    /// Stopped by request: its end is not news, nor restarted.
    stopping: Arc<AtomicBool>,
}

pub struct Jobs {
    store: Arc<Store>,
    dir: PathBuf,
    notify: Notify,
    link: Link,
    /// Where `ember-job notify` posts (the MCP endpoint's /jobs/notify).
    notify_url: Mutex<String>,
    running: Mutex<HashMap<String, Running>>,
    /// Shutting down: jobs go on without the station and stay recorded as running, to be taken up by the next one.
    closing: AtomicBool,
    me: Weak<Jobs>,
}

fn random_hex(n: usize) -> String {
    let mut b = vec![0u8; n];
    let _ = getrandom::fill(&mut b);
    hex::encode(b)
}

/// A job as the pages show it: its record, what it said lately (newest first) and when its output last grew.
pub fn shown(store: &Store, job: &JobRow) -> Value {
    let mut v = serde_json::to_value(job).unwrap_or(Value::Null);
    if let Some(o) = v.as_object_mut() {
        o.insert("notices".into(), json!(store.job_notices(&job.id, NOTICES_SHOWN).unwrap_or_default()));
        o.insert("outputAt".into(), json!(output_at(Path::new(&job.log))));
    }
    v
}

/// When a log last grew (ms), if it has anything in it.
pub fn output_at(path: &Path) -> Option<i64> {
    let meta = std::fs::metadata(path).ok().filter(|m| m.len() > 0)?;
    let at = meta.modified().ok()?.duration_since(std::time::UNIX_EPOCH).ok()?;
    Some(at.as_millis() as i64)
}

/// The last `lines` lines of a log, from at most its last LOG_BYTES.
pub fn tail(path: &Path, lines: usize) -> String {
    let Ok(mut file) = std::fs::File::open(path) else { return String::new() };
    let size = file.metadata().map(|m| m.len()).unwrap_or(0);
    let _ = file.seek(SeekFrom::Start(size.saturating_sub(LOG_BYTES)));
    let mut bytes = vec![];
    let _ = file.read_to_end(&mut bytes);
    let text = String::from_utf8_lossy(&bytes);
    let all: Vec<&str> = text.lines().collect();
    all[all.len().saturating_sub(lines)..].join("\n")
}

impl Jobs {
    pub fn new(store: Arc<Store>, data: &Path, notify: Notify, link: Link) -> Result<Arc<Jobs>> {
        let dir = data.join("jobs");
        std::fs::create_dir_all(dir.join("logs"))?;
        std::fs::create_dir_all(dir.join("bin"))?;
        std::fs::create_dir_all(dir.join("exit"))?;
        let script = dir.join("bin").join("ember-job");
        std::fs::write(&script, EMBER_JOB)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755))?;
        }
        Ok(Arc::new_cyclic(|me| Jobs {
            store,
            dir,
            notify,
            link,
            notify_url: Mutex::default(),
            running: Mutex::default(),
            closing: AtomicBool::new(false),
            me: me.clone(),
        }))
    }

    /// Where `ember-job notify` posts, once the endpoint listens.
    pub fn set_notify_url(&self, url: String) {
        *self.notify_url.lock().unwrap() = url;
    }

    fn tell(&self, job: &JobRow, text: String) {
        (self.notify)(&job.session_key, text);
    }

    fn named(job: &JobRow) -> String {
        match job.port {
            Some(port) => format!("Service \"{}\" ({}, port {port})", job.name, job.id),
            None => format!("Job \"{}\" ({})", job.name, job.id),
        }
    }

    /// Starts a job for `session`: `command` run by sh in `cwd`; a web service when it has a port.
    pub fn start(&self, session: &str, name: &str, command: &str, cwd: &Path, port: Option<u16>) -> Result<JobRow> {
        if command.trim().is_empty() {
            bail!("command is empty");
        }
        if !cwd.is_dir() {
            bail!("no such directory: {}", cwd.display());
        }
        if port.is_some_and(|p| p < 1024) {
            bail!("a service's port is 1024 or above");
        }
        let jobs = self.store.list_jobs(Some(session))?;
        if jobs.iter().filter(|j| j.state == "running").count() >= MAX_RUNNING {
            bail!("this session runs {MAX_RUNNING} jobs already; stop some first");
        }
        if let Some(port) = port {
            // A service holds its port until it is stopped (between its restarts too).
            let holds = |j: &JobRow| j.port == Some(port as i64) && (j.state == "running" || j.state == "exited");
            if let Some(taken) = self.store.list_jobs(None)?.into_iter().find(holds) {
                bail!("port {port} is {}'s already", Self::named(&taken));
            }
        }
        let id = format!("job_{}", random_hex(4));
        let name = if name.trim().is_empty() { command.split_whitespace().next().unwrap_or("job").to_string() } else { name.trim().chars().take(60).collect() };
        let job = JobRow {
            log: self.dir.join("logs").join(format!("{id}.log")).to_string_lossy().into_owned(),
            id,
            session_key: session.into(),
            name,
            command: command.into(),
            cwd: cwd.to_string_lossy().into_owned(),
            port: port.map(i64::from),
            token: random_hex(16),
            state: "running".into(),
            pgid: None,
            exit_code: None,
            started_at: now_ms(),
            ended_at: None,
            restarts: 0,
        };
        self.store.insert_job(&job)?;
        if let Err(e) = self.spawn(&job, false) {
            self.store.job_ended(&job.id, "failed", None)?;
            return Err(e);
        }
        info!(job = job.id, session, name = job.name, port = ?job.port, "job started");
        Ok(self.store.get_job(&job.id)?.unwrap_or(job))
    }

    /// Where a job's exit code is written when it ends.
    fn exit_file(&self, id: &str) -> PathBuf {
        self.dir.join("exit").join(id)
    }

    /// Runs a job's command, and follows it to its end.
    fn spawn(&self, job: &JobRow, restarted: bool) -> Result<()> {
        let log = std::fs::OpenOptions::new().create(true).append(true).open(&job.log)?;
        let path = format!("{}:{}", self.dir.join("bin").display(), std::env::var("PATH").unwrap_or_default());
        let exit = self.exit_file(&job.id);
        let _ = std::fs::remove_file(&exit);
        let mut command = Command::new("/bin/sh");
        command
            .arg("-c")
            .arg(WRAPPER)
            .arg("ember-job")
            .arg(&job.command)
            .arg(&exit)
            .current_dir(&job.cwd)
            .env("PATH", path)
            .env("EMBER_JOB_ID", &job.id)
            .env("EMBER_JOB_TOKEN", &job.token)
            .env("EMBER_JOB_NOTIFY", self.notify_url.lock().unwrap().clone())
            .stdin(std::process::Stdio::null())
            .stdout(log.try_clone()?)
            .stderr(log)
            .process_group(0)
            .kill_on_drop(false);
        if let Some(port) = job.port {
            command.env("PORT", port.to_string());
        }
        let mut child = command.spawn()?;
        let pgid = child.id().ok_or_else(|| anyhow!("the job ended before it started"))? as i32;
        self.store.record_process(pgid as i64, now_ms(), "job", &format!("job: {}", job.name))?;
        self.store.job_started(&job.id, pgid as i64, restarted)?;
        let stopping = Arc::new(AtomicBool::new(false));
        self.running.lock().unwrap().insert(job.id.clone(), Running { pgid, stopping: stopping.clone() });
        let (me, id, began) = (self.me.clone(), job.id.clone(), Instant::now());
        tokio::spawn(async move {
            let status = child.wait().await;
            let Some(jobs) = me.upgrade() else { return };
            jobs.ended(&id, Some(pgid), status.ok().and_then(|s| s.code()), stopping.load(Ordering::SeqCst), began.elapsed()).await;
        });
        Ok(())
    }

    /// Follows a job an earlier station started (it went on through the restart) to its end.
    fn follow(&self, job: &JobRow, pgid: i32) {
        let stopping = Arc::new(AtomicBool::new(false));
        self.running.lock().unwrap().insert(job.id.clone(), Running { pgid, stopping: stopping.clone() });
        let (me, id, exit) = (self.me.clone(), job.id.clone(), self.exit_file(&job.id));
        let began = Instant::now().checked_sub(Duration::from_millis((now_ms() - job.started_at).max(0) as u64)).unwrap_or_else(Instant::now);
        tokio::spawn(async move {
            let status = watch_exit(pgid).await;
            let Some(jobs) = me.upgrade() else { return };
            // Its status when it is this process's child (an exec handoff kept it so); else what its shell wrote.
            let code = match status {
                Some(status) => status.code(),
                None => read_exit(&exit),
            };
            jobs.ended(&id, Some(pgid), code, stopping.load(Ordering::SeqCst), began.elapsed()).await;
        });
    }

    /// A job's command ended: said to its agent, and a service started again. `pgid`: its group, when it ended just
    /// now (what it started itself goes with it).
    async fn ended(&self, id: &str, pgid: Option<i32>, code: Option<i32>, stopped: bool, ran: Duration) {
        // The station stopping: left as it is on record, for the next one to find it ended (its exit file says how).
        if self.closing.load(Ordering::SeqCst) {
            return;
        }
        self.running.lock().unwrap().remove(id);
        if let Some(pgid) = pgid {
            let _ = self.store.forget_process(pgid as i64);
            // What it started itself (a server forked off) goes with it.
            signal_group(pgid, libc::SIGTERM);
        }
        let Ok(Some(job)) = self.store.get_job(id) else { return };
        let code = code.map(i64::from);
        if stopped {
            let _ = self.store.job_ended(id, "stopped", code);
            return;
        }
        let said = |c: Option<i64>| c.map(|c| format!("exit code {c}")).unwrap_or_else(|| "a signal".to_string());
        let last = tail(Path::new(&job.log), 20);
        let last = if last.is_empty() { String::new() } else { format!("\nIts last lines:\n```\n{last}\n```") };
        if job.port.is_none() {
            let _ = self.store.job_ended(id, "exited", code);
            self.tell(&job, format!("{} ended with {}.{last}", Self::named(&job), said(code)));
            return;
        }
        // A service is kept up: at once after a steady run, else after a pause that grows with each quick end.
        let pause = if ran >= STEADY { Duration::ZERO } else { Duration::from_secs(1 << job.restarts.clamp(0, 6) as u32).min(MAX_PAUSE) };
        let _ = self.store.job_ended(id, "exited", code);
        self.tell(&job, format!("{} ended with {}; the station starts it again{}.{last}", Self::named(&job), said(code), if pause.is_zero() { String::new() } else { format!(" in {} s", pause.as_secs()) }));
        let me = self.me.clone();
        let id = id.to_string();
        tokio::spawn(async move {
            tokio::time::sleep(pause).await;
            let Some(jobs) = me.upgrade() else { return };
            // Stopped meanwhile (job_stop, the session deleted): not again.
            let Ok(Some(job)) = jobs.store.get_job(&id) else { return };
            if job.state != "exited" || jobs.closing.load(Ordering::SeqCst) {
                return;
            }
            if let Err(e) = jobs.spawn(&job, true) {
                warn!(job = id, error = %e, "service not started again");
                let _ = jobs.store.job_ended(&id, "failed", None);
                jobs.tell(&job, format!("{} could not be started again: {e}", Self::named(&job)));
            }
        });
    }

    /// Stops a job: its process group asked to end, then made to.
    pub async fn stop(&self, id: &str) -> Result<JobRow> {
        let job = self.store.get_job(id)?.ok_or_else(|| anyhow!("no job {id}"))?;
        let running = self.running.lock().unwrap().get(id).map(|r| (r.pgid, r.stopping.clone()));
        match running {
            Some((pgid, stopping)) => {
                stopping.store(true, Ordering::SeqCst);
                signal_group(pgid, libc::SIGTERM);
                for _ in 0..50 {
                    if !group_alive(pgid) {
                        break;
                    }
                    tokio::time::sleep(Duration::from_millis(100)).await;
                }
                if group_alive(pgid) {
                    signal_group(pgid, libc::SIGKILL);
                }
            }
            // A service waiting to start again, or one on record only: it stays stopped.
            None if job.state == "running" || job.state == "exited" => self.store.job_ended(id, "stopped", job.exit_code)?,
            None => {}
        }
        for _ in 0..30 {
            if self.running.lock().unwrap().get(id).is_none() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        Ok(self.store.get_job(id)?.unwrap_or(job))
    }

    /// Stops a job for someone on the pages: its agent is told who did (it did not ask for it), if it was at work
    /// within AWAKE; an idle one is not woken for it.
    pub async fn stop_for(&self, id: &str, who: &str) -> Result<JobRow> {
        let job = self.stop(id).await?;
        if self.awake(&job.session_key) {
            self.tell(&job, format!("{} was stopped by {who} from ember's page.", Self::named(&job)));
        }
        Ok(job)
    }

    /// Takes a session's jobs that are over off its record (the pages' 清掉已结束的), their logs with them: the ids gone.
    pub fn clear_ended(&self, session: &str) -> Result<Vec<String>> {
        let gone = self.store.clear_ended_jobs(session)?;
        for (id, log) in &gone {
            let log = Path::new(log);
            if log.starts_with(&self.dir) {
                let _ = std::fs::remove_file(log);
            }
            let _ = std::fs::remove_file(self.exit_file(id));
        }
        Ok(gone.into_iter().map(|(id, _)| id).collect())
    }

    /// Whether a session's agent is in a turn, or was within AWAKE.
    fn awake(&self, session: &str) -> bool {
        match self.store.get_session(session) {
            Ok(Some(s)) => s.running || now_ms() - s.last_active_at < AWAKE.as_millis() as i64,
            _ => false,
        }
    }

    /// After a start of the station: what still runs is followed again; what ended meanwhile is told as ended; what was
    /// running and is gone without a word (the machine restarted, or an older station ended it) runs again, and its
    /// agent is told; a service waiting to start again starts. Groups of jobs no longer running are ended.
    pub fn relaunch(&self) {
        let recorded: HashMap<i64, crate::store::ProcessRow> =
            self.store.list_processes().unwrap_or_default().into_iter().filter(|p| p.runtime == "job").map(|p| (p.pgid, p)).collect();
        let mut followed = std::collections::HashSet::new();
        let jobs = self.store.list_jobs(None).unwrap_or_default();
        for job in jobs.iter().filter(|j| j.state == "running") {
            if let Some(entry) = job.pgid.and_then(|pgid| recorded.get(&pgid)) {
                if still_ours(entry) {
                    info!(job = job.id, pgid = entry.pgid, "job went on through the restart; following it again");
                    self.follow(job, entry.pgid as i32);
                    followed.insert(entry.pgid);
                    continue;
                }
                let _ = self.store.forget_process(entry.pgid);
                if let Some(code) = read_exit(&self.exit_file(&job.id)) {
                    // It ended while no station was running: as if it had just ended.
                    let (me, id) = (self.me.clone(), job.id.clone());
                    let ran = Duration::from_millis((now_ms() - job.started_at).max(0) as u64);
                    tokio::spawn(async move {
                        if let Some(jobs) = me.upgrade() {
                            jobs.ended(&id, None, Some(code), false, ran).await;
                        }
                    });
                    continue;
                }
            }
            match self.spawn(job, true) {
                Ok(()) => self.tell(job, format!("The station restarted; {} was started again.", Self::named(job))),
                Err(e) => {
                    warn!(job = job.id, error = %e, "job not started again");
                    let _ = self.store.job_ended(&job.id, "failed", None);
                    self.tell(job, format!("The station restarted; {} could not be started again: {e}", Self::named(job)));
                }
            }
        }
        // A service that ended just before the station stopped, waiting out its pause: it starts now.
        for job in jobs.iter().filter(|j| j.state == "exited" && j.port.is_some()) {
            if let Err(e) = self.spawn(job, true) {
                warn!(job = job.id, error = %e, "service not started again");
                let _ = self.store.job_ended(&job.id, "failed", None);
            }
        }
        for (pgid, entry) in recorded {
            if followed.contains(&pgid) {
                continue;
            }
            if still_ours(&entry) {
                warn!(pgid, label = entry.label, "ending the group of a job no longer running");
                tokio::spawn(end_group(pgid as i32, Duration::from_secs(5)));
            }
            let _ = self.store.forget_process(pgid);
        }
    }

    /// The station stops: its jobs go on (the next station takes them up).
    pub async fn shutdown(&self) {
        self.closing.store(true, Ordering::SeqCst);
    }

    /// `ember-job notify`: the job with this token tells its agent something.
    pub fn notified(&self, token: &str, text: &str) -> Result<()> {
        let job = self.store.job_by_token(token)?.ok_or_else(|| anyhow!("unknown job token"))?;
        let text: String = text.trim().chars().take(4000).collect();
        if text.is_empty() {
            bail!("nothing to say");
        }
        self.store.add_job_notice(&job.id, &text)?;
        self.tell(&job, format!("{} says: {text}", Self::named(&job)));
        Ok(())
    }

    /// A job as the agent reads it.
    fn view(&self, job: &JobRow) -> Value {
        let mut v = serde_json::to_value(job).unwrap_or(Value::Null);
        if let (Some(_), Some(o)) = (job.port, v.as_object_mut()) {
            o.insert("link".into(), json!((self.link)(&job.session_key, &job.id)));
        }
        v
    }

    /// The agents' tools for jobs, run as the session whose token the MCP request carries.
    pub fn tools(&self, workspace: Arc<dyn Fn(&str) -> Option<PathBuf> + Send + Sync>) -> Vec<Tool> {
        type Body = fn(Arc<Jobs>, String, Map<String, Value>, Arc<dyn Fn(&str) -> Option<PathBuf> + Send + Sync>) -> futures_util::future::BoxFuture<'static, Result<String>>;
        let me = self.me.clone();
        let run = move |body: Body| -> Run {
            let (me, workspace) = (me.clone(), workspace.clone());
            Arc::new(move |key, args| match me.upgrade() {
                Some(jobs) => body(jobs, key, args, workspace.clone()),
                None => Box::pin(async { bail!("the station is shutting down") }),
            })
        };
        vec![
            Tool {
                name: "job_start".into(),
                description: "Start a background job: a shell command the station runs apart from your turns, with its output kept in a log. You are told when it ends, and whatever it says on the way: inside the job, `ember-job notify <words>` sends you a message (use it for milestones or problems in a long run). Give a port for a web service: it is kept up (started again if it ends), gets PORT in its environment, and the workspace's members can open it through the returned link (post the link where people should see it). Jobs keep running across your turns and across restarts of the station (one that did not survive, say the machine restarted, is started again).".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "command": { "type": "string", "description": "The shell command (run by sh -c)." },
                        "name": { "type": "string", "description": "A short name for it." },
                        "cwd": { "type": "string", "description": "Where it runs; default this session's workspace." },
                        "port": { "type": "integer", "minimum": 1024, "maximum": 65535, "description": "For a web service: the port it listens on (127.0.0.1 is enough)." },
                    },
                    "required": ["command"],
                    "additionalProperties": false,
                }),
                run: run(|jobs, key, args, workspace| {
                    Box::pin(async move {
                        let text = |k: &str| args.get(k).and_then(Value::as_str).unwrap_or("").to_string();
                        let home = workspace(&key).ok_or_else(|| anyhow!("unknown session"))?;
                        let cwd = match text("cwd").trim() {
                            "" => home,
                            given => home.join(given),
                        };
                        let port = match args.get("port") {
                            None | Some(Value::Null) => None,
                            Some(p) => Some(p.as_u64().filter(|p| *p <= 65535).ok_or_else(|| anyhow!("port must be a number from 1024 to 65535"))? as u16),
                        };
                        let job = jobs.start(&key, &text("name"), &text("command"), &cwd, port)?;
                        Ok(serde_json::to_string_pretty(&jobs.view(&job))?)
                    })
                }),
            },
            Tool {
                name: "job_list".into(),
                description: "This session's background jobs, newest first: their state (running, exited, stopped, failed), exit code, port and link.".into(),
                input_schema: json!({ "type": "object", "properties": {}, "additionalProperties": false }),
                run: run(|jobs, key, _, _| {
                    Box::pin(async move {
                        let list: Vec<Value> = jobs.store.list_jobs(Some(&key))?.iter().map(|j| jobs.view(j)).collect();
                        Ok(if list.is_empty() { "No jobs.".into() } else { serde_json::to_string_pretty(&list)? })
                    })
                }),
            },
            Tool {
                name: "job_log".into(),
                description: "The last lines of a background job's output.".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": { "id": { "type": "string" }, "lines": { "type": "integer", "minimum": 1, "maximum": 1000, "description": "Default 50." } },
                    "required": ["id"],
                    "additionalProperties": false,
                }),
                run: run(|jobs, key, args, _| {
                    Box::pin(async move {
                        let job = owned(&jobs, &key, &args)?;
                        let lines = args.get("lines").and_then(Value::as_u64).map(|n| n.clamp(1, 1000) as usize).unwrap_or(LOG_LINES);
                        let log = tail(Path::new(&job.log), lines);
                        Ok(if log.is_empty() { format!("{} has written nothing yet.", Jobs::named(&job)) } else { log })
                    })
                }),
            },
            Tool {
                name: "job_stop".into(),
                description: "Stop a background job (a service is then not started again).".into(),
                input_schema: json!({ "type": "object", "properties": { "id": { "type": "string" } }, "required": ["id"], "additionalProperties": false }),
                run: run(|jobs, key, args, _| {
                    Box::pin(async move {
                        let job = owned(&jobs, &key, &args)?;
                        let job = jobs.stop(&job.id).await?;
                        Ok(format!("{} is {}.", Jobs::named(&job), job.state))
                    })
                }),
            },
        ]
    }
}

/// The exit code a job's shell wrote when it ended, if it did.
fn read_exit(path: &Path) -> Option<i32> {
    std::fs::read_to_string(path).ok()?.trim().parse().ok()
}

/// The job a tool names (`id`), when it is this session's.
fn owned(jobs: &Jobs, key: &str, args: &Map<String, Value>) -> Result<JobRow> {
    let id = args.get("id").and_then(Value::as_str).unwrap_or("").trim();
    let job = jobs.store.get_job(id)?.ok_or_else(|| anyhow!("no job {id}: job_list names this session's"))?;
    if job.session_key != key {
        bail!("job {id} is another session's");
    }
    Ok(job)
}

#[cfg(test)]
mod tests;
