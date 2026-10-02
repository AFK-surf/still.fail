//! `run`: the station's Node process under a launcher whose pid, lock and ports stay.
//!
//! Node is started as `node <app>/station/main.js run --app <app> --data <data> --launcher-fds 3,4,5`: fd 3 is the MCP
//! endpoint's listening socket, fd 4 the loopback port's, fd 5 the control socket (both ways, one JSON object a line).
//! Node says `{"ready":true,"version":…}` once it serves, and `{"drained":"idle"|"timeout"}` after a drain; the launcher
//! says `{"op":"handover"|"stop"|"drain"|"hup"}`. Node runs in a process group of its own (a ^C at a terminal reaches
//! the launcher only, which stops it); it ends when the control socket closes (the launcher gone).
//!
//! One thread: signals come in through a pipe (written by their handlers), and everything waits in one poll().

use std::ffi::c_int;
use std::fs::File;
use std::io::{Error, Result};
use std::os::fd::{AsRawFd, FromRawFd, IntoRawFd, OwnedFd, RawFd};
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicI32, Ordering};
use std::time::{Duration, Instant};

use serde_json::Value;

use crate::data::{self, Config, now_ms, write_whole};
use crate::log;

pub struct Options {
    pub data: PathBuf,
    pub app: PathBuf,
    pub port: u16,
    pub named: bool,
    pub with_parent: bool,
}

/// How long things may take. Tests shorten them (STILLFAIL_LAUNCHER_TIMES: `ready=ms,exit=ms,…`).
#[derive(Clone, Copy, Debug)]
struct Times {
    /// A new Node's wait to say ready on SIGUSR2, before the handover is given up.
    ready: Duration,
    /// The old Node's to exit once told to hand over; a stopped one's (SIGTERM). Then SIGKILL.
    exit: Duration,
    stop: Duration,
    /// Restarts after an unexpected exit: `backoff` doubled each time, up to `backoff_max`; back to `backoff` after a
    /// Node that ran `stable` since it was ready.
    backoff: Duration,
    backoff_max: Duration,
    stable: Duration,
    /// --with-parent: how often the parent is looked for.
    parent: Duration,
    /// How long run/drained stays when nobody stops the station (the Rust station's DRAINED_LIMIT).
    drained: Duration,
}

/// Starts in a row that end before Node says ready, after which the launcher gives up (launchd starts it again).
const START_FAILURES: u32 = 5;

impl Times {
    fn of_env() -> Times {
        let s = Duration::from_secs;
        let mut times = Times { ready: s(60), exit: s(30), stop: s(30), backoff: s(1), backoff_max: s(60), stable: s(60), parent: s(2), drained: s(300) };
        for pair in std::env::var("STILLFAIL_LAUNCHER_TIMES").unwrap_or_default().split(',') {
            let Some((key, ms)) = pair.split_once('=') else { continue };
            let Ok(ms) = ms.trim().parse::<u64>() else { continue };
            let slot = match key.trim() {
                "ready" => &mut times.ready,
                "exit" => &mut times.exit,
                "stop" => &mut times.stop,
                "backoff" => &mut times.backoff,
                "backoff_max" => &mut times.backoff_max,
                "stable" => &mut times.stable,
                "parent" => &mut times.parent,
                "drained" => &mut times.drained,
                _ => continue,
            };
            *slot = Duration::from_millis(ms);
        }
        times
    }
}

/// One Node process and its end of the control socket.
struct Node {
    pid: i32,
    control: OwnedFd,
    /// What came in on the control socket after the last whole line; `open` until it closes.
    pending: Vec<u8>,
    open: bool,
    ready: Option<Instant>,
    version: String,
}

impl Node {
    fn tell(&self, op: &str) {
        let line = format!("{{\"op\":\"{op}\"}}\n");
        let mut rest = line.as_bytes();
        while !rest.is_empty() {
            // SAFETY: a write from a live buffer to a descriptor this Node owns.
            let n = unsafe { libc::write(self.control.as_raw_fd(), rest.as_ptr().cast(), rest.len()) };
            if n < 0 {
                let error = Error::last_os_error();
                if error.kind() == std::io::ErrorKind::Interrupted {
                    continue;
                }
                log::warn(&format!("could not tell Node {} {op}: {error}", self.pid));
                return;
            }
            rest = &rest[n as usize..];
        }
    }

    fn kill(&self) {
        // SAFETY: a signal to a child of this process not yet reaped (its pid is still its).
        unsafe { libc::kill(self.pid, libc::SIGKILL) };
    }

    /// Whole lines come in on the control socket since the last read.
    fn read(&mut self) -> Vec<Value> {
        let mut buf = [0u8; 4096];
        loop {
            // SAFETY: a read into a live buffer from a descriptor this Node owns.
            let n = unsafe { libc::read(self.control.as_raw_fd(), buf.as_mut_ptr().cast(), buf.len()) };
            match n {
                0 => {
                    self.open = false;
                    break;
                }
                n if n > 0 => self.pending.extend_from_slice(&buf[..n as usize]),
                _ => {
                    let error = Error::last_os_error();
                    match error.kind() {
                        std::io::ErrorKind::Interrupted => continue,
                        std::io::ErrorKind::WouldBlock => break,
                        _ => {
                            self.open = false;
                            break;
                        }
                    }
                }
            }
        }
        let mut said = vec![];
        while let Some(at) = self.pending.iter().position(|b| *b == b'\n') {
            let line: Vec<u8> = self.pending.drain(..=at).collect();
            match serde_json::from_slice::<Value>(&line) {
                Ok(value) => said.push(value),
                Err(error) => log::warn(&format!("Node {} said a line that does not read ({error}): {}", self.pid, String::from_utf8_lossy(&line).trim_end())),
            }
        }
        said
    }
}

/// Which of the launcher's Nodes: the one serving, the one starting beside it (SIGUSR2), the one handing over.
#[derive(Clone, Copy, PartialEq, Debug)]
enum Slot {
    Current,
    Next,
    Retiring,
}

struct Station {
    options: Options,
    times: Times,
    run: PathBuf,
    /// The listening sockets Node gets as fds 3 and 4.
    mcp: OwnedFd,
    admin: OwnedFd,
    current: Option<Node>,
    /// Starting on SIGUSR2: until when it may take to be ready, and whether it was given up (handoff-failed written).
    next: Option<(Node, Instant, bool)>,
    /// Told to hand over: until when it may take to exit.
    retiring: Option<(Node, Instant)>,
    /// Stopping (SIGTERM, SIGINT, the parent gone): until when the Nodes may take to exit.
    stopping: Option<Instant>,
    restart_at: Option<Instant>,
    failures: u32,
    backoff_step: u32,
    drained_at: Option<Instant>,
    parent: Option<(i32, Instant)>,
    /// The launcher's exit once nothing runs.
    exit: i32,
}

/// The pipe signal handlers write to.
static SIGNALS: AtomicI32 = AtomicI32::new(-1);

extern "C" fn on_signal(signal: c_int) {
    // SAFETY: errno saved and restored around a write(2), both async-signal-safe.
    unsafe {
        let errno = errno();
        let byte = signal as u8;
        libc::write(SIGNALS.load(Ordering::Relaxed), (&byte as *const u8).cast(), 1);
        *errno_ptr() = errno;
    }
}

#[cfg(target_os = "macos")]
unsafe fn errno_ptr() -> *mut c_int {
    unsafe { libc::__error() }
}

#[cfg(not(target_os = "macos"))]
unsafe fn errno_ptr() -> *mut c_int {
    unsafe { libc::__errno_location() }
}

unsafe fn errno() -> c_int {
    unsafe { *errno_ptr() }
}

const HANDLED: [c_int; 6] = [libc::SIGTERM, libc::SIGINT, libc::SIGUSR1, libc::SIGUSR2, libc::SIGHUP, libc::SIGCHLD];

/// The pipe's read end, once each handled signal writes to it.
fn take_signals() -> Result<OwnedFd> {
    let (read, write) = pipe()?;
    for fd in [&read, &write] {
        nonblocking(fd.as_raw_fd())?;
    }
    SIGNALS.store(write.into_raw_fd(), Ordering::Relaxed);
    for signal in HANDLED {
        // SAFETY: a handler that only writes to the pipe; sigaction with a zeroed, then filled, struct.
        unsafe {
            let mut action: libc::sigaction = std::mem::zeroed();
            action.sa_sigaction = on_signal as extern "C" fn(c_int) as libc::sighandler_t;
            action.sa_flags = libc::SA_RESTART | if signal == libc::SIGCHLD { libc::SA_NOCLDSTOP } else { 0 };
            libc::sigemptyset(&mut action.sa_mask);
            if libc::sigaction(signal, &action, std::ptr::null_mut()) != 0 {
                return Err(Error::last_os_error());
            }
        }
    }
    Ok(read)
}

fn pipe() -> Result<(OwnedFd, OwnedFd)> {
    let mut fds = [0; 2];
    // SAFETY: pipe(2) fills two descriptors, then owned here.
    if unsafe { libc::pipe(fds.as_mut_ptr()) } != 0 {
        return Err(Error::last_os_error());
    }
    let (read, write) = unsafe { (OwnedFd::from_raw_fd(fds[0]), OwnedFd::from_raw_fd(fds[1])) };
    cloexec(read.as_raw_fd())?;
    cloexec(write.as_raw_fd())?;
    Ok((read, write))
}

fn socketpair() -> Result<(OwnedFd, OwnedFd)> {
    let mut fds = [0; 2];
    // SAFETY: socketpair(2) fills two descriptors, then owned here.
    if unsafe { libc::socketpair(libc::AF_UNIX, libc::SOCK_STREAM, 0, fds.as_mut_ptr()) } != 0 {
        return Err(Error::last_os_error());
    }
    let (ours, theirs) = unsafe { (OwnedFd::from_raw_fd(fds[0]), OwnedFd::from_raw_fd(fds[1])) };
    cloexec(ours.as_raw_fd())?;
    cloexec(theirs.as_raw_fd())?;
    Ok((ours, theirs))
}

fn cloexec(fd: RawFd) -> Result<()> {
    // SAFETY: fcntl on a descriptor the caller owns.
    if unsafe { libc::fcntl(fd, libc::F_SETFD, libc::FD_CLOEXEC) } != 0 {
        return Err(Error::last_os_error());
    }
    Ok(())
}

fn nonblocking(fd: RawFd) -> Result<()> {
    // SAFETY: fcntl on a descriptor the caller owns.
    unsafe {
        let flags = libc::fcntl(fd, libc::F_GETFL);
        if flags < 0 || libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) != 0 {
            return Err(Error::last_os_error());
        }
    }
    Ok(())
}

/// Fills descriptors 0 to 9 (with /dev/null) where nothing is open, so nothing the launcher opens later is at 3, 4 or
/// 5, where a Node gets its own: dup2 there in the child can then overwrite nothing it still needs (std's pipe for
/// spawn errors among them). 0 to 2 are left inheritable; the rest are close-on-exec.
fn keep_low_fds() {
    loop {
        let Ok(file) = File::open("/dev/null") else { return };
        let fd = file.into_raw_fd();
        if fd >= 10 {
            // SAFETY: the descriptor just opened, owned here.
            unsafe { libc::close(fd) };
            return;
        }
        if fd <= 2 {
            // SAFETY: as above; std opens files close-on-exec, which stdin/stdout/stderr must not be.
            unsafe { libc::fcntl(fd, libc::F_SETFD, 0) };
        }
    }
}

pub fn run(options: Options) -> i32 {
    keep_low_fds();
    let run = options.data.join("run");
    if let Err(error) = std::fs::create_dir_all(&run) {
        log::error(&format!("{}: {error}", run.display()));
        return 1;
    }
    let config = match Config::read(&options.data) {
        Ok(config) => config,
        Err(error) => {
            log::error(&format!("the config does not read: {error}"));
            return 1;
        }
    };
    // One station per data directory: a second would take the first one's ports and runtimes away.
    let _lock = match data::lock(&run.join("station.lock")) {
        Ok(Some(lock)) => lock,
        Ok(None) => {
            let dir = options.data.display();
            if config.english {
                eprintln!("Another still.fail station is running on this data directory ({dir}); only one station can run on a data directory on one machine");
            } else {
                eprintln!("另一个 still.fail station 正在运行这个数据目录（{dir}）；同一台机器上的一个数据目录只能运行一个 station");
            }
            return crate::HELD;
        }
        Err(error) => {
            log::error(&format!("{}: {error}", run.join("station.lock").display()));
            return 1;
        }
    };
    let _ = std::fs::remove_file(run.join("drained"));
    // Both at descriptors of 10 and up (keep_low_fds).
    let bound = crate::ports::mcp(&config).and_then(|mcp| Ok((mcp, crate::ports::admin(&options.data, options.port, options.named, config.english)?)));
    let (mcp, admin): (OwnedFd, OwnedFd) = match bound {
        Ok((mcp, admin)) => (mcp.into(), admin.into()),
        Err(error) => {
            log::error(&error);
            eprintln!("{error}");
            return 1;
        }
    };
    let signals = match take_signals() {
        Ok(fd) => fd,
        Err(error) => {
            log::error(&format!("signals not taken: {error}"));
            return 1;
        }
    };
    let times = Times::of_env();
    // SAFETY: getppid has no preconditions.
    let parent = options.with_parent.then(|| (unsafe { libc::getppid() }, Instant::now() + times.parent));
    let mut station = Station {
        options,
        times,
        run,
        mcp,
        admin,
        current: None,
        next: None,
        retiring: None,
        stopping: None,
        restart_at: None,
        failures: 0,
        backoff_step: 0,
        drained_at: None,
        parent,
        exit: 0,
    };
    station.start_current();
    station.serve(signals)
}

impl Station {
    fn spawn(&self) -> Result<Node> {
        let app = &self.options.app;
        let (ours, theirs) = socketpair()?;
        let mut command = Command::new(crate::node(app));
        command
            .arg(crate::main_js(app))
            .arg("run")
            .arg("--app")
            .arg(app)
            .arg("--data")
            .arg(&self.options.data)
            .args(["--launcher-fds", "3,4,5"])
            .stdin(Stdio::null())
            .process_group(0);
        let given = [self.mcp.as_raw_fd(), self.admin.as_raw_fd(), theirs.as_raw_fd()];
        // SAFETY: only dup2 (async-signal-safe) between fork and exec. The sources are all at 10 and up, so none is
        // overwritten before it is copied; the copies are not close-on-exec.
        unsafe {
            command.pre_exec(move || {
                for (to, from) in given.iter().enumerate() {
                    if libc::dup2(*from, 3 + to as c_int) < 0 {
                        return Err(Error::last_os_error());
                    }
                }
                Ok(())
            });
        }
        let child = command.spawn()?;
        drop(theirs);
        nonblocking(ours.as_raw_fd())?;
        let pid = child.id() as i32;
        // Reaped by waitpid in reap(), not by std.
        drop(child);
        Ok(Node { pid, control: ours, pending: vec![], open: true, ready: None, version: String::new() })
    }

    /// Starts the Node that serves (at first, after a crash).
    fn start_current(&mut self) {
        self.restart_at = None;
        match self.spawn() {
            Ok(node) => {
                log::info(&format!("Node started (pid {})", node.pid));
                self.current = Some(node);
            }
            Err(error) => {
                log::error(&format!("{} did not start: {error}", crate::node(&self.options.app).display()));
                self.failed_start();
            }
        }
    }

    /// A Node that ended before it was ready (or never started): again after the backoff, or, after START_FAILURES in
    /// a row, the launcher gives up.
    fn failed_start(&mut self) {
        self.failures += 1;
        if self.failures >= START_FAILURES {
            log::error(&format!("Node did not start {START_FAILURES} times in a row; giving up"));
            self.exit = 1;
            self.stop();
            return;
        }
        self.schedule_restart();
    }

    fn schedule_restart(&mut self) {
        let delay = self.times.backoff.saturating_mul(1 << self.backoff_step.min(16)).min(self.times.backoff_max);
        self.backoff_step += 1;
        log::info(&format!("starting Node again in {} ms", delay.as_millis()));
        self.restart_at = Some(Instant::now() + delay);
    }

    /// station.json says this Node's start: the installer takes a new startedAt with the same pid for "handed over".
    fn say_started(&mut self) {
        let Some(node) = &self.current else { return };
        let text = data::station_json(std::process::id(), now_ms(), &node.version);
        if let Err(error) = write_whole(&self.run.join("station.json"), &text) {
            log::warn(&format!("station.json not written: {error}"));
        }
        let _ = std::fs::remove_file(self.run.join("drained"));
        self.drained_at = None;
    }

    fn handoff_failed(&self, why: &str) {
        log::warn(&format!("not handed over; going on as before: {why}"));
        let _ = write_whole(&self.run.join("handoff-failed"), &format!("{why}\n"));
    }

    fn node_mut(&mut self, slot: Slot) -> Option<&mut Node> {
        match slot {
            Slot::Current => self.current.as_mut(),
            Slot::Next => self.next.as_mut().map(|n| &mut n.0),
            Slot::Retiring => self.retiring.as_mut().map(|n| &mut n.0),
        }
    }

    fn said(&mut self, slot: Slot, message: Value) {
        if message["ready"] == true {
            if slot == Slot::Next && self.next.as_ref().is_some_and(|n| n.2) {
                return;
            }
            let Some(node) = self.node_mut(slot) else { return };
            if node.ready.is_some() {
                return;
            }
            node.ready = Some(Instant::now());
            node.version = message["version"].as_str().unwrap_or_default().to_string();
            log::info(&format!("Node {} ready (version {})", node.pid, node.version));
            match slot {
                Slot::Current => {
                    self.failures = 0;
                    self.say_started();
                }
                Slot::Next => self.hand_over(),
                Slot::Retiring => {}
            }
        } else if let Some(said) = message["drained"].as_str().filter(|_| slot == Slot::Current) {
            log::info(&format!("drained ({said})"));
            let _ = write_whole(&self.run.join("drained"), &format!("{said}\n"));
            self.drained_at = Some(Instant::now());
        } else {
            log::warn(&format!("Node said what the launcher does not know: {message}"));
        }
    }

    /// The new Node is ready: it serves, and the old one is told to hand over and go.
    fn hand_over(&mut self) {
        let Some((next, _, _)) = self.next.take() else { return };
        self.restart_at = None;
        match self.current.replace(next) {
            Some(old) => {
                log::info(&format!("handing over from Node {} to Node {}", old.pid, self.current.as_ref().map_or(0, |n| n.pid)));
                old.tell("handover");
                self.retiring = Some((old, Instant::now() + self.times.exit));
            }
            // The old one had crashed meanwhile: nothing to wait for.
            None => {
                self.failures = 0;
                self.say_started();
            }
        }
    }

    fn signal(&mut self, signal: c_int) {
        match signal {
            libc::SIGCHLD => self.reap(),
            libc::SIGTERM | libc::SIGINT => {
                log::info("stopping");
                self.stop();
            }
            libc::SIGUSR1 | libc::SIGHUP => {
                let op = if signal == libc::SIGUSR1 { "drain" } else { "hup" };
                match &self.current {
                    Some(node) if self.stopping.is_none() => node.tell(op),
                    _ => log::warn(&format!("asked to {op} with no Node serving; not now")),
                }
            }
            libc::SIGUSR2 => self.start_next(),
            _ => {}
        }
    }

    /// SIGUSR2: a new Node beside the one serving (the release at --app may be new).
    fn start_next(&mut self) {
        if self.stopping.is_some() {
            return;
        }
        if self.next.is_some() || self.retiring.is_some() {
            log::warn("asked to hand over while a handover is under way; not again");
            return;
        }
        match self.spawn() {
            Ok(node) => {
                log::info(&format!("handover: Node {} started beside the one serving", node.pid));
                self.next = Some((node, Instant::now() + self.times.ready, false));
            }
            Err(error) => self.handoff_failed(&format!("{} did not start: {error}", crate::node(&self.options.app).display())),
        }
    }

    /// Asks every Node to stop; the launcher exits once none runs.
    fn stop(&mut self) {
        if self.stopping.is_some() {
            return;
        }
        self.restart_at = None;
        self.stopping = Some(Instant::now() + self.times.stop);
        if let Some(node) = &self.current {
            node.tell("stop");
        }
        if let Some((node, ..)) = &self.next {
            node.tell("stop");
        }
        // The one retiring is ending already (within its own limit).
    }

    fn reap(&mut self) {
        loop {
            let mut status = 0;
            // SAFETY: waitpid on this process's children, without blocking.
            let pid = unsafe { libc::waitpid(-1, &mut status, libc::WNOHANG) };
            if pid <= 0 {
                return;
            }
            let how = describe(status);
            if self.current.as_ref().is_some_and(|n| n.pid == pid) {
                let node = self.current.take().unwrap();
                log::info(&format!("Node {pid} {how}"));
                if self.stopping.is_none() {
                    self.crashed(node);
                }
            } else if self.next.as_ref().is_some_and(|n| n.0.pid == pid) {
                let (node, _, given_up) = self.next.take().unwrap();
                log::info(&format!("Node {pid} (starting beside) {how}"));
                if !given_up && self.stopping.is_none() {
                    self.handoff_failed(&format!("the new station {how} before it was ready"));
                }
                drop(node);
                if self.current.is_none() && self.stopping.is_none() && self.restart_at.is_none() {
                    self.schedule_restart();
                }
            } else if self.retiring.as_ref().is_some_and(|n| n.0.pid == pid) {
                self.retiring = None;
                log::info(&format!("Node {pid} handed over and {how}"));
                if self.stopping.is_none() && self.current.as_ref().is_some_and(|n| n.ready.is_some()) {
                    self.say_started();
                }
            }
        }
    }

    /// The serving Node ended without being asked: started again after the backoff.
    fn crashed(&mut self, node: Node) {
        log::warn(&format!("Node {} ended unexpectedly", node.pid));
        // A handover under way brings the next one up.
        if self.next.is_some() {
            return;
        }
        match node.ready {
            Some(at) => {
                self.failures = 0;
                if at.elapsed() >= self.times.stable {
                    self.backoff_step = 0;
                }
                self.schedule_restart();
            }
            None => self.failed_start(),
        }
    }

    /// What is due by now: a handover given up, a Node killed, a restart, the parent gone.
    fn tick(&mut self) {
        let now = Instant::now();
        if let Some((node, by, given_up)) = &mut self.next
            && !*given_up
            && now >= *by
        {
            *given_up = true;
            node.kill();
            let pid = node.pid;
            self.handoff_failed(&format!("the new station (pid {pid}) was not ready within {} s", self.times.ready.as_secs_f32()));
        }
        if let Some((node, by)) = &mut self.retiring
            && now >= *by
        {
            log::warn(&format!("Node {} did not exit within {} s of handing over; killed", node.pid, self.times.exit.as_secs_f32()));
            node.kill();
            *by = now + Duration::from_secs(3600);
        }
        if let Some(by) = self.stopping
            && now >= by
        {
            for node in [self.current.as_ref(), self.next.as_ref().map(|n| &n.0), self.retiring.as_ref().map(|n| &n.0)].into_iter().flatten() {
                log::warn(&format!("Node {} did not stop within {} s; killed", node.pid, self.times.stop.as_secs_f32()));
                node.kill();
            }
            self.stopping = Some(now + Duration::from_secs(3600));
        }
        if self.restart_at.is_some_and(|at| now >= at) && self.stopping.is_none() {
            self.start_current();
        }
        if let Some(at) = self.drained_at
            && now >= at + self.times.drained
        {
            log::warn("drained but not stopped; run/drained taken back");
            let _ = std::fs::remove_file(self.run.join("drained"));
            self.drained_at = None;
        }
        if let Some((parent, at)) = &mut self.parent
            && now >= *at
        {
            *at = now + self.times.parent;
            // SAFETY: getppid has no preconditions.
            if unsafe { libc::getppid() } != *parent {
                log::info("parent ended; stopping");
                self.parent = None;
                self.stop();
            }
        }
    }

    fn next_due(&self) -> Option<Instant> {
        [
            self.next.as_ref().filter(|n| !n.2).map(|n| n.1),
            self.retiring.as_ref().map(|n| n.1),
            self.stopping,
            self.restart_at,
            self.drained_at.map(|at| at + self.times.drained),
            self.parent.map(|p| p.1),
        ]
        .into_iter()
        .flatten()
        .min()
    }

    fn running(&self) -> bool {
        self.current.is_some() || self.next.is_some() || self.retiring.is_some()
    }

    fn serve(&mut self, signals: OwnedFd) -> i32 {
        loop {
            if self.stopping.is_some() && !self.running() {
                log::info("stopped");
                return self.exit;
            }
            let mut fds = vec![libc::pollfd { fd: signals.as_raw_fd(), events: libc::POLLIN, revents: 0 }];
            let mut slots = vec![];
            for slot in [Slot::Current, Slot::Next, Slot::Retiring] {
                if let Some(node) = self.node_mut(slot).filter(|n| n.open) {
                    fds.push(libc::pollfd { fd: node.control.as_raw_fd(), events: libc::POLLIN, revents: 0 });
                    slots.push(slot);
                }
            }
            let timeout = self.next_due().map_or(-1, |at| at.saturating_duration_since(Instant::now()).as_millis().min(i32::MAX as u128) as c_int + 1);
            // SAFETY: poll over a live array of pollfds.
            let n = unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, timeout) };
            if n < 0 && Error::last_os_error().kind() != std::io::ErrorKind::Interrupted {
                log::error(&format!("poll: {}", Error::last_os_error()));
                return 1;
            }
            if n > 0 {
                for (slot, fd) in slots.iter().zip(&fds[1..]) {
                    if fd.revents == 0 {
                        continue;
                    }
                    let said = match self.node_mut(*slot) {
                        Some(node) => node.read(),
                        None => continue,
                    };
                    for message in said {
                        self.said(*slot, message);
                    }
                }
                if fds[0].revents != 0 {
                    for signal in drain_signals(&signals) {
                        self.signal(signal);
                    }
                }
            }
            self.tick();
        }
    }
}

fn drain_signals(fd: &OwnedFd) -> Vec<c_int> {
    let mut buf = [0u8; 64];
    let mut got = vec![];
    loop {
        // SAFETY: a read into a live buffer from the signal pipe.
        let n = unsafe { libc::read(fd.as_raw_fd(), buf.as_mut_ptr().cast(), buf.len()) };
        if n <= 0 {
            return got;
        }
        got.extend(buf[..n as usize].iter().map(|b| *b as c_int));
    }
}

/// How a process ended, as waitpid said.
fn describe(status: c_int) -> String {
    if libc::WIFEXITED(status) {
        format!("exited with {}", libc::WEXITSTATUS(status))
    } else if libc::WIFSIGNALED(status) {
        format!("was ended by signal {}", libc::WTERMSIG(status))
    } else {
        format!("ended ({status})")
    }
}
