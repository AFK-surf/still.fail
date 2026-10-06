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

/// What the launcher does to processes, and its clock: the system's (`System`), or a test's.
trait Os {
    fn now(&self) -> Instant;
    /// A new Node, given `fds` (the listening sockets) as fds 3 and 4.
    fn spawn(&mut self, options: &Options, fds: [RawFd; 2]) -> Result<Node>;
    /// SIGKILL to a Node not yet reaped (its pid is still its).
    fn kill(&mut self, pid: i32);
    fn parent(&self) -> i32;
}

struct System;

impl Os for System {
    fn now(&self) -> Instant {
        Instant::now()
    }

    fn spawn(&mut self, options: &Options, fds: [RawFd; 2]) -> Result<Node> {
        let app = &options.app;
        let (ours, theirs) = socketpair()?;
        let mut command = Command::new(crate::node(app));
        command
            .arg(crate::main_js(app))
            .arg("run")
            .arg("--app")
            .arg(app)
            .arg("--data")
            .arg(&options.data)
            .args(["--launcher-fds", "3,4,5"])
            .stdin(Stdio::null())
            .process_group(0);
        let given = [fds[0], fds[1], theirs.as_raw_fd()];
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

    fn kill(&mut self, pid: i32) {
        // SAFETY: a signal to a child of this process not yet reaped.
        unsafe { libc::kill(pid, libc::SIGKILL) };
    }

    fn parent(&self) -> i32 {
        // SAFETY: getppid has no preconditions.
        unsafe { libc::getppid() }
    }
}

struct Station<O: Os = System> {
    os: O,
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
    let mut station = Station::new(System, options, Times::of_env(), run, mcp, admin);
    station.start_current();
    station.serve(signals)
}

impl<O: Os> Station<O> {
    fn new(os: O, options: Options, times: Times, run: PathBuf, mcp: OwnedFd, admin: OwnedFd) -> Station<O> {
        let parent = options.with_parent.then(|| (os.parent(), os.now() + times.parent));
        Station {
            os,
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
        }
    }

    fn spawn(&mut self) -> Result<Node> {
        let fds = [self.mcp.as_raw_fd(), self.admin.as_raw_fd()];
        self.os.spawn(&self.options, fds)
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
        self.restart_at = Some(self.os.now() + delay);
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
            let now = self.os.now();
            let Some(node) = self.node_mut(slot) else { return };
            if node.ready.is_some() {
                return;
            }
            node.ready = Some(now);
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
            self.drained_at = Some(self.os.now());
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
                self.retiring = Some((old, self.os.now() + self.times.exit));
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
                self.next = Some((node, self.os.now() + self.times.ready, false));
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
        self.stopping = Some(self.os.now() + self.times.stop);
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
            self.ended(pid, status);
        }
    }

    /// A Node ended (`status` as waitpid says).
    fn ended(&mut self, pid: i32, status: c_int) {
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
                if self.os.now().saturating_duration_since(at) >= self.times.stable {
                    self.backoff_step = 0;
                }
                self.schedule_restart();
            }
            None => self.failed_start(),
        }
    }

    /// What is due by now: a handover given up, a Node killed, a restart, the parent gone.
    fn tick(&mut self) {
        let now = self.os.now();
        if let Some((node, by, given_up)) = &mut self.next
            && !*given_up
            && now >= *by
        {
            *given_up = true;
            let pid = node.pid;
            self.os.kill(pid);
            self.handoff_failed(&format!("the new station (pid {pid}) was not ready within {} s", self.times.ready.as_secs_f32()));
        }
        if let Some((node, by)) = &mut self.retiring
            && now >= *by
        {
            log::warn(&format!("Node {} did not exit within {} s of handing over; killed", node.pid, self.times.exit.as_secs_f32()));
            *by = now + Duration::from_secs(3600);
            let pid = node.pid;
            self.os.kill(pid);
        }
        if let Some(by) = self.stopping
            && now >= by
        {
            let pids: Vec<i32> = [self.current.as_ref(), self.next.as_ref().map(|n| &n.0), self.retiring.as_ref().map(|n| &n.0)].into_iter().flatten().map(|n| n.pid).collect();
            for pid in pids {
                log::warn(&format!("Node {pid} did not stop within {} s; killed", self.times.stop.as_secs_f32()));
                self.os.kill(pid);
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
            if self.os.parent() != *parent {
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
            let timeout = self.next_due().map_or(-1, |at| at.saturating_duration_since(self.os.now()).as_millis().min(i32::MAX as u128) as c_int + 1);
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;
    use std::os::unix::net::UnixStream;

    use serde_json::json;

    /// The test's processes and clock: a Node is a pid (from 101 on) and the far end of its control socket.
    struct Fake {
        dir: PathBuf,
        now: Instant,
        pid: i32,
        theirs: Vec<(i32, UnixStream)>,
        killed: Vec<i32>,
        parent: i32,
    }

    impl Os for Fake {
        fn now(&self) -> Instant {
            self.now
        }

        fn spawn(&mut self, _: &Options, _: [RawFd; 2]) -> Result<Node> {
            let (ours, theirs) = socketpair()?;
            nonblocking(ours.as_raw_fd())?;
            nonblocking(theirs.as_raw_fd())?;
            self.pid += 1;
            self.theirs.push((self.pid, UnixStream::from(theirs)));
            Ok(Node { pid: self.pid, control: ours, pending: vec![], open: true, ready: None, version: String::new() })
        }

        fn kill(&mut self, pid: i32) {
            self.killed.push(pid);
        }

        fn parent(&self) -> i32 {
            self.parent
        }
    }

    impl Drop for Fake {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.dir);
        }
    }

    const MS: Duration = Duration::from_millis(1);

    fn s(secs: u64) -> Duration {
        Duration::from_secs(secs)
    }

    /// A launcher with its first Node started.
    fn station(name: &str, with_parent: bool) -> Station<Fake> {
        let data = std::env::temp_dir().join(format!("launcher-run-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&data);
        let run = data.join("run");
        std::fs::create_dir_all(&run).unwrap();
        let null = || OwnedFd::from(File::open("/dev/null").unwrap());
        let fake = Fake { dir: data.clone(), now: Instant::now(), pid: 100, theirs: vec![], killed: vec![], parent: 4321 };
        let times = Times { ready: s(60), exit: s(30), stop: s(30), backoff: s(1), backoff_max: s(4), stable: s(60), parent: s(2), drained: s(300) };
        let options = Options { data, app: PathBuf::from("/nowhere"), port: 0, named: false, with_parent };
        let mut station = Station::new(fake, options, times, run, null(), null());
        station.start_current();
        station
    }

    fn ready(version: &str) -> Value {
        json!({"ready": true, "version": version})
    }

    /// waitpid's status for an exit with `code`, and for SIGKILL.
    fn exited(code: c_int) -> c_int {
        code << 8
    }

    const KILLED: c_int = libc::SIGKILL;

    impl Station<Fake> {
        /// The clock moved on by `by`, and what is due by then done.
        fn pass(&mut self, by: Duration) {
            self.os.now += by;
            self.tick();
        }

        /// The Node started last.
        fn last(&self) -> i32 {
            self.os.pid
        }

        fn serving(&self) -> i32 {
            self.current.as_ref().unwrap().pid
        }

        /// The ops told to Node `pid` since last asked.
        fn told(&mut self, pid: i32) -> Vec<String> {
            let (_, theirs) = self.os.theirs.iter_mut().find(|(p, _)| *p == pid).unwrap();
            let mut bytes = vec![];
            // Up to what is there (non-blocking); everything told was written before.
            let _ = theirs.read_to_end(&mut bytes);
            String::from_utf8(bytes).unwrap().lines().map(|l| serde_json::from_str::<Value>(l).unwrap()["op"].as_str().unwrap().to_string()).collect()
        }

        fn file(&self, name: &str) -> Option<String> {
            std::fs::read_to_string(self.run.join(name)).ok()
        }

        fn station_json(&self) -> Value {
            serde_json::from_str(&self.file("station.json").unwrap()).unwrap()
        }
    }

    #[test]
    fn a_handover_lets_the_old_node_go_once_the_new_one_is_ready() {
        let mut station = station("handover", false);
        let old = station.last();
        station.said(Slot::Current, ready("0.1.0"));
        assert_eq!(station.station_json()["version"], "0.1.0");
        assert_eq!(station.station_json()["pid"], std::process::id());
        station.signal(libc::SIGUSR2);
        let new = station.last();
        assert_ne!(new, old);
        // Asked again meanwhile: not a second one.
        station.signal(libc::SIGUSR2);
        assert_eq!(station.last(), new);
        assert!(station.told(old).is_empty(), "the old one serves until the new one is ready");
        station.said(Slot::Next, ready("0.2.0"));
        assert_eq!(station.told(old), ["handover"]);
        assert_eq!(station.serving(), new);
        // The old one not gone within its time: killed. station.json says the new start once it is gone.
        station.pass(s(30) - MS);
        assert!(station.os.killed.is_empty());
        assert_eq!(station.station_json()["version"], "0.1.0");
        station.pass(MS);
        assert_eq!(station.os.killed, [old]);
        station.ended(old, KILLED);
        assert_eq!(station.station_json()["version"], "0.2.0");
        assert_eq!(station.station_json()["pid"], std::process::id());
        assert!(station.file("handoff-failed").is_none());
        assert!(station.told(new).is_empty() && station.stopping.is_none());
    }

    #[test]
    fn a_new_node_never_ready_is_given_up_and_the_old_one_serves_on() {
        let mut station = station("handfail", false);
        let old = station.last();
        station.said(Slot::Current, ready("0.1.0"));
        let first = station.file("station.json");
        station.signal(libc::SIGUSR2);
        let new = station.last();
        station.pass(s(60) - MS);
        assert!(station.os.killed.is_empty() && station.file("handoff-failed").is_none());
        station.pass(MS);
        assert_eq!(station.os.killed, [new]);
        assert!(station.file("handoff-failed").unwrap().contains("not ready"));
        // Ready too late: not taken.
        station.said(Slot::Next, ready("0.2.0"));
        station.ended(new, KILLED);
        assert_eq!(station.serving(), old);
        assert!(station.told(old).is_empty());
        assert_eq!(station.file("station.json"), first);
        assert!(station.restart_at.is_none());
        // A later handover works.
        station.signal(libc::SIGUSR2);
        let again = station.last();
        station.said(Slot::Next, ready("0.2.0"));
        assert_eq!(station.told(old), ["handover"]);
        station.ended(old, exited(0));
        assert_eq!(station.serving(), again);
        assert_eq!(station.station_json()["version"], "0.2.0");
    }

    #[test]
    fn a_new_node_that_ends_before_it_is_ready_fails_the_handover() {
        let mut station = station("handend", false);
        let old = station.last();
        station.said(Slot::Current, ready("0.1.0"));
        station.signal(libc::SIGUSR2);
        station.ended(station.last(), exited(1));
        assert!(station.file("handoff-failed").unwrap().contains("exited with 1 before it was ready"));
        assert_eq!(station.serving(), old);
        assert!(station.told(old).is_empty() && station.os.killed.is_empty());
    }

    #[test]
    fn sigterm_during_a_handover_stops_both_and_kills_what_does_not_stop_in_time() {
        let mut station = station("stopboth", false);
        let old = station.last();
        station.said(Slot::Current, ready("0.1.0"));
        station.signal(libc::SIGUSR2);
        let new = station.last();
        station.signal(libc::SIGTERM);
        assert_eq!(station.told(old), ["stop"]);
        assert_eq!(station.told(new), ["stop"]);
        station.pass(s(30) - MS);
        assert!(station.os.killed.is_empty());
        station.ended(old, exited(0));
        station.pass(MS);
        assert_eq!(station.os.killed, [new]);
        station.ended(new, KILLED);
        assert!(!station.running());
        assert_eq!(station.exit, 0);
        // Nothing is started again.
        station.pass(s(3600));
        assert_eq!(station.last(), new);
    }

    #[test]
    fn a_crashed_node_is_started_again_after_a_backoff_that_doubles() {
        let mut station = station("crash", false);
        // Each one crashing once ready: again after 1, 2, 4, then 4 s (backoff_max).
        for expected in [1000, 2000, 4000, 4000] {
            let node = station.last();
            station.said(Slot::Current, ready("0.1.0"));
            station.ended(node, exited(1));
            station.pass(Duration::from_millis(expected) - MS);
            assert_eq!(station.last(), node, "not again before {expected} ms");
            station.pass(MS);
            assert_ne!(station.last(), node, "again after {expected} ms");
        }
        // One that served for `stable` before it crashed: back to the first backoff.
        let node = station.last();
        station.said(Slot::Current, ready("0.1.0"));
        station.pass(s(60));
        station.ended(node, exited(1));
        station.pass(s(1) - MS);
        assert_eq!(station.last(), node);
        station.pass(MS);
        assert_ne!(station.last(), node);
        assert!(station.stopping.is_none());
    }

    #[test]
    fn five_starts_in_a_row_that_end_before_ready_and_it_gives_up() {
        let mut station = station("giveup", false);
        for start in 1..=5 {
            station.ended(station.last(), exited(1));
            if start < 5 {
                station.pass(s(4));
            }
        }
        assert_eq!(station.os.theirs.len(), 5);
        assert!(station.stopping.is_some() && !station.running());
        assert_eq!(station.exit, 1);
        station.pass(s(3600));
        assert_eq!(station.os.theirs.len(), 5);
    }

    #[test]
    fn with_parent_it_stops_once_the_parent_is_gone() {
        let mut station = station("parent", true);
        let node = station.last();
        station.said(Slot::Current, ready("0.1.0"));
        for _ in 0..30 {
            station.pass(s(2));
        }
        assert!(station.stopping.is_none() && station.told(node).is_empty(), "still there while the parent is");
        // Taken up by another: seen at the next look.
        station.os.parent = 1;
        station.pass(s(2) - MS);
        assert!(station.stopping.is_none());
        station.pass(MS);
        assert!(station.stopping.is_some());
        assert_eq!(station.told(node), ["stop"]);
        station.ended(node, exited(0));
        assert!(!station.running());
    }

    #[test]
    fn sigusr1_and_sighup_go_to_node_and_drained_is_taken_back_when_nobody_stops_it() {
        let mut station = station("drain", false);
        let node = station.last();
        station.said(Slot::Current, ready("0.1.0"));
        station.signal(libc::SIGUSR1);
        station.signal(libc::SIGHUP);
        assert_eq!(station.told(node), ["drain", "hup"]);
        station.said(Slot::Current, json!({"drained": "idle"}));
        assert_eq!(station.file("drained").as_deref(), Some("idle\n"));
        station.pass(s(300) - MS);
        assert!(station.file("drained").is_some());
        station.pass(MS);
        assert!(station.file("drained").is_none());
        assert!(station.stopping.is_none() && station.told(node).is_empty());
    }
}
