//! The MoonBit front (station/mb's program, `--builder mesh`): the station's iroh endpoint kept for its Node across
//! handovers, so an update binds no new endpoint and its relays stay linked (station/src/mesh/front.ts). The launcher
//! starts it before the first Node (or, taking up one from before it, before the Node of that handover) and keeps it as long as it runs: across Node's handovers and restarts, and across its
//! own `renew` (its pid and the pipe to its stdin handed on). Its stdin is that pipe: the launcher gone, it ends. Each Node
//! is told where it listens (STILLFAIL_MESH_FRONT); where none could be started, a Node binds the endpoint itself as
//! before (the mesh addon). Unix only: the front listens on a Unix socket.

use std::io::Read;
use std::os::fd::{AsRawFd, FromRawFd, IntoRawFd, OwnedFd, RawFd};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use serde_json::{Value, json};

use crate::log;

/// Where the release has the program (beside the station's main.js, as station/src/read/mb-reader.ts finds it).
const PROGRAM_IN_APP: &str = "station/stillfail-reader";
/// The program to run instead of the release's (development, tests: as mb-reader.ts reads it).
const PROGRAM_VAR: &str = "STILLFAIL_MB_READER";
/// How long it may take to listen.
const LISTENS_WITHIN: Duration = Duration::from_secs(10);
/// How it hands Node the streams a connection's other end opens (its first line's `streams`; none said: 1). 2: each
/// with its index, so Node takes them in the order they were opened (a device's credential stream first, 2026-11-13).
/// 3: a route Node gave it (`route`) goes to the program that answers it, Node told the index went (station/mesh/served.ts).
/// A front kept from before a raise here is replaced once by the launcher that takes it up (`current`): the one thing
/// that does not come with an update, as it is kept across them.
pub const STREAMS: u64 = 3;

pub struct Front {
    pub pid: i32,
    /// The write end of its stdin (never written: closed, it ends).
    input: OwnedFd,
    /// Where it listens.
    pub socket: PathBuf,
    /// When it started; none for one a launcher before this one started.
    started: Option<Instant>,
    /// How it hands Node streams (`STREAMS`).
    streams: u64,
}

impl Front {
    fn program(app: &Path) -> Option<PathBuf> {
        if let Some(given) = std::env::var_os(PROGRAM_VAR).filter(|v| !v.is_empty()) {
            return Some(PathBuf::from(given));
        }
        let program = app.join(PROGRAM_IN_APP);
        program.is_file().then_some(program)
    }

    /// The front for the station of `data`, listening; none where the release has none or it did not start (said).
    pub fn start(app: &Path, data: &Path) -> Option<Front> {
        let program = Front::program(app)?;
        let run = data.join("run");
        let socket = run.join("front.sock");
        let mut command = Command::new(&program);
        command
            .args(["--builder", "mesh", "--socket"])
            .arg(&socket)
            .arg("--shell-dir")
            .arg(run.join("front"))
            // Its shell's threads carry every byte of the station's iroh: as many as the machine has cores, as the addon's
            // (tokio's own count) had (two, an app's, held bulk transfers 15% under the addon's).
            .env("STILLFAIL_SHELL_THREADS", std::thread::available_parallelism().map_or(2, |n| n.get()).to_string())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .process_group(0);
        let mut child = match command.spawn() {
            Ok(child) => child,
            Err(error) => {
                log::warn(&format!("the front ({}) did not start: {error}; each Node binds the station's endpoint itself", program.display()));
                return None;
            }
        };
        let pid = child.id() as i32;
        // SAFETY: the pipe's write end, taken from the child's handle, owned here from now on.
        let input = unsafe { OwnedFd::from_raw_fd(child.stdin.take().unwrap().into_raw_fd()) };
        let mut out = child.stdout.take().unwrap();
        // Reaped by waitpid in run.rs's serve(), not by std.
        drop(child);
        match listening(&mut out) {
            Some((said, streams)) if said == socket.to_string_lossy() => {
                log::info(&format!("the front listens (pid {pid}): {}", socket.display()));
                Some(Front { pid, input, socket, started: Some(Instant::now()), streams })
            }
            other => {
                log::warn(&format!("the front (pid {pid}) did not listen ({other:?}); each Node binds the station's endpoint itself"));
                // SAFETY: a signal to a child of this process.
                unsafe { libc::kill(pid, libc::SIGKILL) };
                None
            }
        }
    }

    /// It ended: another in its place, unless it ended sooner than `lives` after it started (said).
    pub fn ended(self, app: &Path, data: &Path, how: &str, lives: Duration) -> Option<Front> {
        if let Some(started) = self.started.filter(|s| s.elapsed() < lives) {
            log::error(&format!("the front (pid {}) {how} {} ms after it started; not started again, Nodes from now on bind the station's endpoint themselves", self.pid, started.elapsed().as_millis()));
            return None;
        }
        log::warn(&format!("the front (pid {}) {how}; starting another", self.pid));
        drop(self);
        Front::start(app, data)
    }

    /// What the launcher it becomes (`renew`) takes it up by.
    pub fn state(&self) -> Value {
        json!({ "pid": self.pid, "input": self.input.as_raw_fd(), "socket": self.socket, "streams": self.streams })
    }

    pub fn fds(&self) -> Vec<RawFd> {
        vec![self.input.as_raw_fd()]
    }

    /// One a launcher before this one handed on.
    pub fn resumed(state: &Value) -> Option<Front> {
        let pid = state["pid"].as_i64().and_then(|n| i32::try_from(n).ok())?;
        let input = state["input"].as_i64().and_then(|n| RawFd::try_from(n).ok()).filter(|n| *n > 2)?;
        let socket = PathBuf::from(state["socket"].as_str()?);
        crate::run::cloexec_on(input);
        // SAFETY: the descriptor the launcher before handed on, owned by this one from here.
        Some(Front { pid, input: unsafe { OwnedFd::from_raw_fd(input) }, socket, started: None, streams: state["streams"].as_u64().unwrap_or(1) })
    }

    /// Itself where it hands streams as this launcher's release does; else ended (its connections go with it, the
    /// devices dial again), so that one of the release starts in its place.
    pub fn current(self) -> Option<Front> {
        if self.streams >= STREAMS {
            return Some(self);
        }
        log::warn(&format!("the front (pid {}) hands streams as {} and this release as {STREAMS}: ending it for the release's", self.pid, self.streams));
        // SAFETY: a signal to this process's child (a launcher before this one started it in this same process), then
        // its exit waited for, so the next binds its socket and the station's endpoint with it gone.
        unsafe {
            libc::kill(self.pid, libc::SIGKILL);
            libc::waitpid(self.pid, std::ptr::null_mut(), 0);
        }
        None
    }
}

/// Where it said it listens and how it hands streams (`{"listening": path, "streams": n}`, its first line), within
/// LISTENS_WITHIN.
fn listening(out: &mut std::process::ChildStdout) -> Option<(String, u64)> {
    let deadline = Instant::now() + LISTENS_WITHIN;
    let mut line = vec![];
    let mut byte = [0u8; 1];
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return None;
        }
        let mut fd = libc::pollfd { fd: out.as_raw_fd(), events: libc::POLLIN, revents: 0 };
        // SAFETY: poll on one live pollfd.
        let polled = unsafe { libc::poll(&mut fd, 1, left.as_millis().min(i32::MAX as u128) as libc::c_int) };
        if polled < 0 && std::io::Error::last_os_error().kind() == std::io::ErrorKind::Interrupted {
            continue;
        }
        if polled <= 0 {
            return None;
        }
        match out.read(&mut byte) {
            Ok(1) if byte[0] == b'\n' => break,
            Ok(1) => line.push(byte[0]),
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            _ => return None,
        }
    }
    let said: Value = serde_json::from_slice(&line).ok()?;
    said["listening"].as_str().map(|path| (path.to_string(), said["streams"].as_u64().unwrap_or(1)))
}
