//! Runtime processes run in their own process group, recorded in the store, so the station can end everything a runtime
//! started (tool subprocesses, dev servers) and reap groups a previous run left behind.
//!
//! A group can also be handed over to the station's next binary (handoff.rs): its reader stops at a line boundary, and
//! its pipes, with what was read past the last line, go on in the new binary, which takes the group up as it was.

use std::collections::{BTreeMap, HashSet};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::path::Path;
use std::process::Stdio;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use base64::Engine;
use base64::engine::general_purpose::STANDARD as B64;
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::unix::pipe;
use tokio::process::Command;
use tokio::sync::{Mutex as AsyncMutex, oneshot, watch};
use tracing::{debug, warn};

use crate::store::{ProcessRow, Store, now_ms};

/// Asks a pipe's reader to stop between lines; it answers with the pipe and what it read past the last whole line.
type StopReader = oneshot::Sender<oneshot::Sender<(pipe::Receiver, Vec<u8>)>>;

pub struct GroupProcess {
    pub pgid: i32,
    stdin: AsyncMutex<Option<pipe::Sender>>,
    exited: watch::Receiver<Option<String>>,
    killing: Mutex<bool>,
    store: Arc<Store>,
    stdout: Mutex<Option<StopReader>>,
    stderr: Mutex<Option<StopReader>>,
    /// Given to the next binary: it is no longer this one's to kill or forget.
    handed: Mutex<bool>,
}

pub struct Spawn<'a> {
    pub command: &'a str,
    pub args: Vec<String>,
    pub cwd: &'a Path,
    pub env: BTreeMap<String, String>,
    pub runtime: &'a str,
    pub label: String,
}

/// A group as the next binary takes it up: its pipes (descriptors left open across exec) and what its stdout had
/// said past its last whole line.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct HandedProcess {
    pub pgid: i32,
    pub stdin: Option<i32>,
    pub stdout: i32,
    pub stderr: Option<i32>,
    /// Base64.
    #[serde(default)]
    pub carry: String,
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

    let stdout = pipe::Receiver::from_owned_fd(child.stdout.take().expect("piped stdout").into_owned_fd()?)?;
    let stderr = pipe::Receiver::from_owned_fd(child.stderr.take().expect("piped stderr").into_owned_fd()?)?;
    let stdin = match child.stdin.take() {
        Some(stdin) => Some(pipe::Sender::from_owned_fd(stdin.into_owned_fd()?)?),
        None => None,
    };
    let (tx, exited) = watch::channel(None);
    tokio::spawn(async move {
        let said = match child.wait().await {
            Ok(status) => describe(status),
            Err(e) => format!("wait error: {e}"),
        };
        let _ = tx.send(Some(said));
    });
    Ok(assemble(pgid, stdin, stdout, stderr, vec![], exited, store, spec.runtime, &spec.label, on_line))
}

/// Takes up a group the previous binary handed over (it is this process's child still: exec keeps the pid).
pub fn adopt_group(handed: &HandedProcess, store: Arc<Store>, runtime: &str, label: &str, on_line: impl Fn(String) + Send + 'static) -> Result<Arc<GroupProcess>> {
    let stdout = pipe::Receiver::from_owned_fd(claim_fd(handed.stdout)?)?;
    let stderr = match handed.stderr {
        Some(fd) => Some(pipe::Receiver::from_owned_fd(claim_fd(fd)?)?),
        None => None,
    };
    let stdin = match handed.stdin {
        Some(fd) => Some(pipe::Sender::from_owned_fd(claim_fd(fd)?)?),
        None => None,
    };
    let carry = B64.decode(&handed.carry).unwrap_or_default();
    let (tx, exited) = watch::channel(None);
    let pgid = handed.pgid;
    tokio::spawn(async move {
        let said = watch_exit(pgid).await.map(describe).unwrap_or_else(|| "unknown".into());
        let _ = tx.send(Some(said));
    });
    let stderr = match stderr {
        Some(stderr) => stderr,
        // Nothing to read: a pipe that never says anything stands in.
        None => {
            let (_, receiver) = pipe::pipe()?;
            receiver
        }
    };
    Ok(assemble(pgid, stdin, stdout, stderr, carry, exited, store, runtime, label, on_line))
}

#[allow(clippy::too_many_arguments)]
fn assemble(
    pgid: i32,
    stdin: Option<pipe::Sender>,
    stdout: pipe::Receiver,
    stderr: pipe::Receiver,
    carry: Vec<u8>,
    exited: watch::Receiver<Option<String>>,
    store: Arc<Store>,
    runtime: &str,
    label: &str,
    on_line: impl Fn(String) + Send + 'static,
) -> Arc<GroupProcess> {
    let stdout = read_lines(stdout, carry, on_line);
    let (runtime, label) = (runtime.to_string(), label.to_string());
    let stderr = read_lines(stderr, vec![], move |line| {
        debug!(runtime, label, line = &line[..line.floor_char_boundary(2000)], "runtime stderr");
    });
    Arc::new(GroupProcess {
        pgid,
        stdin: AsyncMutex::new(stdin),
        exited,
        killing: Mutex::new(false),
        store,
        stdout: Mutex::new(Some(stdout)),
        stderr: Mutex::new(Some(stderr)),
        handed: Mutex::new(false),
    })
}

/// Reads `pipe` a line at a time (starting with what `carry` holds), until it ends or is asked to stop.
fn read_lines(mut pipe: pipe::Receiver, mut carry: Vec<u8>, on_line: impl Fn(String) + Send + 'static) -> StopReader {
    let (stop, mut stopping) = oneshot::channel::<oneshot::Sender<(pipe::Receiver, Vec<u8>)>>();
    fn emit(carry: &mut Vec<u8>, on_line: &impl Fn(String)) {
        while let Some(i) = carry.iter().position(|&b| b == b'\n') {
            let mut line: Vec<u8> = carry.drain(..=i).collect();
            line.pop();
            if line.last() == Some(&b'\r') {
                line.pop();
            }
            on_line(String::from_utf8_lossy(&line).into_owned());
        }
    }
    tokio::spawn(async move {
        emit(&mut carry, &on_line);
        let mut chunk = vec![0u8; 64 * 1024];
        let mut can_stop = true;
        loop {
            tokio::select! {
                biased;
                asked = &mut stopping, if can_stop => match asked {
                    Ok(answer) => {
                        let _ = answer.send((pipe, carry));
                        return;
                    }
                    // Nobody can ask any more: read on to the end.
                    Err(_) => can_stop = false,
                },
                read = pipe.read(&mut chunk) => match read {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        carry.extend_from_slice(&chunk[..n]);
                        emit(&mut carry, &on_line);
                    }
                },
            }
        }
        if !carry.is_empty() {
            on_line(String::from_utf8_lossy(&carry).into_owned());
        }
    });
    stop
}

pub fn describe(status: std::process::ExitStatus) -> String {
    match status.code() {
        Some(code) => code.to_string(),
        None => {
            use std::os::unix::process::ExitStatusExt;
            status.signal().map(signal_name).unwrap_or_else(|| "unknown".into())
        }
    }
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

/// Waits for `pid` to end when it is no tokio child of this process: a child of the previous binary (exec kept it
/// this process's child) is reaped, with its status; a process another station started is watched until it is gone
/// (None: its status is its new parent's to see).
pub async fn watch_exit(pid: i32) -> Option<std::process::ExitStatus> {
    use std::os::unix::process::ExitStatusExt;
    loop {
        let mut status = 0;
        // SAFETY: waitpid on one pid, with a status to write to.
        let reaped = unsafe { libc::waitpid(pid, &mut status, libc::WNOHANG) };
        if reaped == pid {
            return Some(std::process::ExitStatus::from_raw(status));
        }
        if reaped < 0 && std::io::Error::last_os_error().raw_os_error() == Some(libc::ECHILD) && unsafe { libc::kill(pid, 0) } != 0 {
            return None;
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
}

/// A descriptor the previous binary left open across exec, made this process's own again: closed on exec, so what it
/// starts next does not inherit it.
pub fn claim_fd(fd: i32) -> Result<OwnedFd> {
    // SAFETY: F_GETFD on a number the handoff names; it fails on one that is not open.
    if fd < 0 || unsafe { libc::fcntl(fd, libc::F_GETFD) } < 0 {
        bail!("descriptor {fd} was not handed over");
    }
    unsafe { libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC) };
    // SAFETY: open (checked above) and nobody else's: the handoff names each descriptor once.
    Ok(unsafe { OwnedFd::from_raw_fd(fd) })
}

/// A copy of `fd` that stays open across exec (dup does not copy close-on-exec), for the next binary.
pub fn keep_across_exec(fd: &impl AsRawFd) -> Result<i32> {
    // SAFETY: dup of an open descriptor.
    let kept = unsafe { libc::dup(fd.as_raw_fd()) };
    if kept < 0 {
        bail!("dup failed: {}", std::io::Error::last_os_error());
    }
    Ok(kept)
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

    pub fn handed(&self) -> bool {
        *self.handed.lock().unwrap()
    }

    /// Stops reading it and gives its pipes up for the next binary. What it writes meanwhile waits in the pipe; what
    /// was read past the last whole line goes along. Fails when it has exited (or is exiting: its output ended).
    pub async fn hand_off(&self) -> Result<HandedProcess> {
        if self.has_exited() {
            bail!("process {} has exited", self.pgid);
        }
        let stop = |slot: &Mutex<Option<StopReader>>| {
            let (answer, answered) = oneshot::channel();
            slot.lock().unwrap().take().map(|stop| stop.send(answer).ok()).flatten().map(|_| answered)
        };
        let out = stop(&self.stdout).ok_or_else(|| anyhow!("process {}'s output is no longer read", self.pgid))?;
        let err = stop(&self.stderr);
        let (stdout, carry) = tokio::time::timeout(Duration::from_secs(2), out).await.map_err(|_| anyhow!("process {}'s reader did not stop", self.pgid))?.map_err(|_| anyhow!("process {}'s output ended", self.pgid))?;
        let stderr = match err {
            Some(err) => tokio::time::timeout(Duration::from_secs(2), err).await.ok().and_then(Result::ok).map(|(pipe, _)| pipe),
            None => None,
        };
        let stdin = self.stdin.lock().await.take();
        *self.handed.lock().unwrap() = true;
        Ok(HandedProcess {
            pgid: self.pgid,
            stdin: stdin.as_ref().map(keep_across_exec).transpose()?,
            stdout: keep_across_exec(&stdout)?,
            stderr: stderr.as_ref().map(keep_across_exec).transpose()?,
            carry: B64.encode(&carry),
        })
    }

    /// SIGTERM the whole group, SIGKILL whatever is left after `grace`.
    pub async fn kill(&self, grace: Duration) {
        if self.handed() {
            return;
        }
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

/// Whether a group recorded by an earlier run is still that group. One whose leader is alive is only if the leader
/// started when it was recorded (pids get reused); one whose leader is gone but still has members is, because a pgid
/// cannot be reused while any member remains.
pub fn still_ours(entry: &ProcessRow) -> bool {
    let pgid = entry.pgid as i32;
    let ours = match start_time_of(pgid) {
        // ps gives whole seconds: a few seconds either way is the same start.
        Some(started) => (started - entry.started_at).abs() < 5000,
        None => group_alive(pgid),
    };
    ours && group_alive(pgid)
}

/// SIGTERM a group, SIGKILL it if it is still there after `grace`.
pub async fn end_group(pgid: i32, grace: Duration) {
    signal_group(pgid, libc::SIGTERM);
    for _ in 0..(grace.as_millis() / 100).max(1) {
        tokio::time::sleep(Duration::from_millis(100)).await;
        if !group_alive(pgid) {
            return;
        }
    }
    signal_group(pgid, libc::SIGKILL);
}

/// Kills process groups recorded by an earlier run, except `kept` (handed over to this binary) and background jobs
/// (jobs.rs takes those up again).
pub async fn reap_stale_groups(store: &Store, kept: &HashSet<i64>) -> Result<usize> {
    let mut reaped = 0;
    for entry in store.list_processes()? {
        if kept.contains(&entry.pgid) || entry.runtime == "job" {
            continue;
        }
        if still_ours(&entry) {
            warn!(pgid = entry.pgid, label = entry.label, "reaping process group left by a previous run");
            end_group(entry.pgid as i32, Duration::from_secs(2)).await;
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

    #[tokio::test]
    async fn a_group_handed_over_goes_on_where_it_was_what_it_said_meanwhile_included() {
        let store = Arc::new(Store::open(":memory:", None).unwrap());
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        let spec = Spawn {
            command: "/bin/sh",
            args: vec!["-c".into(), "read x; echo got $x; printf 'half'; read y; echo \" and $y\"; read z; echo last $z".into()],
            cwd: Path::new("/"),
            env: BTreeMap::from([("PATH".to_string(), "/bin:/usr/bin".to_string())]),
            runtime: "claude",
            label: "test".into(),
        };
        let group = spawn_group(spec, store.clone(), move |line| {
            let _ = tx.send(line);
        })
        .unwrap();
        group.write("a").await;
        assert_eq!(rx.recv().await.unwrap(), "got a");
        tokio::time::sleep(Duration::from_millis(200)).await; // "half" is read, a line not yet
        let handed = group.hand_off().await.unwrap();
        assert!(group.handed());
        assert_eq!(B64.decode(&handed.carry).unwrap(), b"half");
        // What the next binary reads it from: the same descriptors, by number.
        let handed: HandedProcess = serde_json::from_str(&serde_json::to_string(&handed).unwrap()).unwrap();
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        let taken = adopt_group(&handed, store.clone(), "claude", "test", move |line| {
            let _ = tx.send(line);
        })
        .unwrap();
        taken.write("b").await;
        assert_eq!(rx.recv().await.unwrap(), "half and b");
        taken.write("c").await;
        assert_eq!(rx.recv().await.unwrap(), "last c");
        // The old one's kill does nothing now; the new one's does.
        group.kill(Duration::from_millis(100)).await;
        assert_eq!(store.list_processes().unwrap().len(), 1);
        taken.kill(Duration::from_secs(2)).await;
        assert!(!group_alive(taken.pgid));
    }
}
