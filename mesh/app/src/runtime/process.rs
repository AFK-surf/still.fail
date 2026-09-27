//! Runtime processes run in their own process group, recorded in the store, so the station can end everything a runtime
//! started (tool subprocesses, dev servers) and reap groups a previous run left behind. (src/runtime/process.ts)

use std::collections::BTreeMap;
use std::path::Path;
use std::process::Stdio;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::{Result, anyhow};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{ChildStdin, Command};
use tokio::sync::{Mutex as AsyncMutex, watch};
use tracing::{debug, warn};

use crate::store::{Store, now_ms};

pub struct GroupProcess {
    pub pgid: i32,
    stdin: AsyncMutex<Option<ChildStdin>>,
    exited: watch::Receiver<Option<String>>,
    killing: Mutex<bool>,
    store: Arc<Store>,
}

pub struct Spawn<'a> {
    pub command: &'a str,
    pub args: Vec<String>,
    pub cwd: &'a Path,
    pub env: BTreeMap<String, String>,
    pub runtime: &'a str,
    pub label: String,
}

/// Starts `command` as the leader of a group of its own, recorded in the store; each line it writes to stdout goes to
/// `on_line`, what it writes to stderr to the debug log.
pub fn spawn_group(spec: Spawn, store: Arc<Store>, on_line: impl Fn(String) + Send + 'static) -> Result<Arc<GroupProcess>> {
    let mut child = Command::new(spec.command)
        .args(&spec.args)
        .current_dir(spec.cwd)
        .env_clear()
        .envs(&spec.env)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .process_group(0)
        .kill_on_drop(false)
        .spawn()
        .map_err(|e| anyhow!("failed to spawn {}: {e}", spec.command))?;
    let pgid = child.id().ok_or_else(|| anyhow!("failed to spawn {}", spec.command))? as i32;
    store.record_process(pgid as i64, now_ms(), spec.runtime, &spec.label)?;

    let stdout = child.stdout.take().expect("piped stdout");
    tokio::spawn(async move {
        let mut lines = BufReader::new(stdout).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            on_line(line);
        }
    });
    let stderr = child.stderr.take().expect("piped stderr");
    let (runtime, label) = (spec.runtime.to_string(), spec.label.clone());
    tokio::spawn(async move {
        let mut lines = BufReader::new(stderr).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            debug!(runtime, label, line = &line[..line.len().min(2000)], "runtime stderr");
        }
    });
    let stdin = child.stdin.take();
    let (tx, exited) = watch::channel(None);
    tokio::spawn(async move {
        let status = child.wait().await;
        let said = match status {
            Ok(s) => match s.code() {
                Some(code) => code.to_string(),
                None => {
                    use std::os::unix::process::ExitStatusExt;
                    s.signal().map(signal_name).unwrap_or_else(|| "unknown".into())
                }
            },
            Err(e) => format!("wait error: {e}"),
        };
        let _ = tx.send(Some(said));
    });
    Ok(Arc::new(GroupProcess { pgid, stdin: AsyncMutex::new(stdin), exited, killing: Mutex::new(false), store }))
}

fn signal_name(signal: i32) -> String {
    match signal {
        libc::SIGTERM => "SIGTERM".into(),
        libc::SIGKILL => "SIGKILL".into(),
        libc::SIGINT => "SIGINT".into(),
        libc::SIGHUP => "SIGHUP".into(),
        other => format!("signal {other}"),
    }
}

impl GroupProcess {
    /// Writes a line to its stdin (the newline added); nothing when it is gone.
    pub async fn write(&self, line: &str) {
        let mut stdin = self.stdin.lock().await;
        if let Some(pipe) = stdin.as_mut() {
            let mut bytes = line.as_bytes().to_vec();
            if !line.ends_with('\n') {
                bytes.push(b'\n');
            }
            if pipe.write_all(&bytes).await.is_err() || pipe.flush().await.is_err() {
                *stdin = None; // the process went away; its exit reports it
            }
        }
    }

    /// Its exit code (or signal name), once the leader exits.
    pub async fn exited(&self) -> String {
        let mut rx = self.exited.clone();
        loop {
            if let Some(said) = rx.borrow().clone() {
                return said;
            }
            if rx.changed().await.is_err() {
                return "unknown".into();
            }
        }
    }

    pub fn has_exited(&self) -> bool {
        self.exited.borrow().is_some()
    }

    /// SIGTERM the whole group, SIGKILL whatever is left after `grace`.
    pub async fn kill(&self, grace: Duration) {
        let already = {
            let mut killing = self.killing.lock().unwrap();
            std::mem::replace(&mut *killing, true)
        };
        if already {
            self.exited().await;
            return;
        }
        signal_group(self.pgid, libc::SIGTERM);
        // The leader's exit is the signal the group is done; what outlives it, or a leader that ignores SIGTERM, is killed.
        let _ = tokio::time::timeout(grace, self.exited()).await;
        if group_alive(self.pgid) {
            signal_group(self.pgid, libc::SIGKILL);
            // Gone once the system has taken them away, a moment after.
            for _ in 0..100 {
                if !group_alive(self.pgid) {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        }
        let _ = self.store.forget_process(self.pgid as i64);
    }
}

pub fn signal_group(pgid: i32, signal: i32) {
    // ESRCH: the group is already gone.
    unsafe {
        libc::kill(-pgid, signal);
    }
}

pub fn group_alive(pgid: i32) -> bool {
    unsafe { libc::kill(-pgid, 0) == 0 }
}

/// When `pid` started (ms), or None if it is not running: from its elapsed time as ps says it ([[dd-]hh:]mm:ss).
fn start_time_of(pid: i32) -> Option<i64> {
    let out = std::process::Command::new("ps").args(["-o", "etime=", "-p", &pid.to_string()]).output().ok()?;
    let text = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if text.is_empty() {
        return None;
    }
    let (days, rest) = match text.split_once('-') {
        Some((d, r)) => (d.parse::<i64>().ok()?, r.to_string()),
        None => (0, text),
    };
    let parts: Vec<i64> = rest.split(':').map(|p| p.parse().ok()).collect::<Option<_>>()?;
    let seconds = match parts.as_slice() {
        [h, m, s] => h * 3600 + m * 60 + s,
        [m, s] => m * 60 + s,
        _ => return None,
    } + days * 86_400;
    Some(now_ms() - seconds * 1000)
}

/// Kills process groups recorded by an earlier run. A group whose leader is alive is only ours if the leader started
/// when we recorded it (pids get reused); a group whose leader is gone but still has members is ours, because a pgid
/// cannot be reused while any member remains.
pub async fn reap_stale_groups(store: &Store) -> Result<usize> {
    let mut reaped = 0;
    for entry in store.list_processes()? {
        let pgid = entry.pgid as i32;
        let ours = match start_time_of(pgid) {
            // ps gives whole seconds: a few seconds either way is the same start.
            Some(started) => (started - entry.started_at).abs() < 5000,
            None => group_alive(pgid),
        };
        if ours && group_alive(pgid) {
            warn!(pgid, label = entry.label, "reaping process group left by a previous run");
            signal_group(pgid, libc::SIGTERM);
            tokio::time::sleep(Duration::from_secs(2)).await;
            if group_alive(pgid) {
                signal_group(pgid, libc::SIGKILL);
            }
            reaped += 1;
        }
        store.forget_process(entry.pgid)?;
    }
    Ok(reaped)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn a_group_is_recorded_its_lines_heard_and_all_of_it_killed() {
        let store = Arc::new(Store::open(":memory:", None).unwrap());
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        let spec = Spawn {
            command: "/bin/sh",
            args: vec!["-c".into(), "read x; echo got $x; sleep 30 & sleep 30".into()],
            cwd: Path::new("/"),
            env: BTreeMap::from([("PATH".to_string(), "/bin:/usr/bin".to_string())]),
            runtime: "claude",
            label: "test".into(),
        };
        let group = spawn_group(spec, store.clone(), move |line| {
            let _ = tx.send(line);
        })
        .unwrap();
        assert_eq!(store.list_processes().unwrap()[0].pgid, group.pgid as i64);
        group.write("hello").await;
        assert_eq!(rx.recv().await.unwrap(), "got hello");
        group.kill(Duration::from_secs(2)).await;
        assert!(!group_alive(group.pgid), "the background sleep went with it");
        assert!(store.list_processes().unwrap().is_empty());
        assert_eq!(group.exited().await, "SIGTERM");
    }
}
