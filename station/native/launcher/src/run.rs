//! `run` on Unix: the station's Node process under a launcher whose pid, lock and ports stay. What happens to the Node
//! (ready, crashed and started again, handed over, stopped) is lifecycle.rs's, as on Windows; this is how Unix gives
//! it its processes and events.
//!
//! Node is started as `node <app>/station/main.js run --app <app> --data <data> --launcher-fds 3,4,5`: fd 3 is the MCP
//! endpoint's listening socket, fd 4 the loopback port's, fd 5 the control socket (both ways, one JSON object a line).
//! Node says `{"ready":true,"version":…}` once it serves, `{"drained":"idle"|"timeout"}` after a drain and, handing over,
//! `{"carry":…}` (what it holds only in memory, `--launcher-carries`); the launcher says
//! `{"op":"handover"|"stop"|"drain"|"hup"}`, and `{"op":"carried","carried":…}` to the Node taking over. Node runs in a
//! process group of its own (a ^C at a terminal reaches the launcher only, which stops it); it ends when the control
//! socket closes (the launcher gone). The listening sockets passing from Node to Node is what makes a handover
//! (SIGUSR2) possible here.
//!
//! An update brings a launcher too, at `<app>/mesh/target/release/stillfail-station`: at a handover, a launcher unlike
//! it becomes it first (`renew`: exec, its pid, lock, listening sockets and the Node serving with their descriptors
//! kept, told to the new one by `--resume`), which hands over. Else a launcher would run until the machine's next
//! start, and what is changed in it would come to no running station.
//!
//! One thread: signals come in through a pipe (written by their handlers), and everything waits in one poll().

use std::ffi::{CString, OsString, c_int};
use std::fs::File;
use std::hash::{DefaultHasher, Hasher};
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::io::{Error, Result};
use std::os::fd::{AsRawFd, FromRawFd, IntoRawFd, OwnedFd, RawFd};
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicI32, Ordering};
use std::time::Instant;

use serde_json::{Value, json};

use crate::data::{self, Config};
use crate::lifecycle::{Lifecycle, Os, Process, Times};
pub use crate::lifecycle::Options;
use crate::log;

/// One Node process and its end of the control socket.
struct Node {
    pid: i32,
    control: OwnedFd,
    /// What came in on the control socket after the last whole line; `open` until it closes.
    pending: Vec<u8>,
    open: bool,
}

impl Process for Node {
    fn pid(&self) -> u32 {
        self.pid as u32
    }

    fn send(&self, line: &Value) {
        let line = format!("{line}\n");
        let mut rest = line.as_bytes();
        while !rest.is_empty() {
            // SAFETY: a write from a live buffer to a descriptor this Node owns.
            let n = unsafe { libc::write(self.control.as_raw_fd(), rest.as_ptr().cast(), rest.len()) };
            if n < 0 {
                let error = Error::last_os_error();
                match error.kind() {
                    std::io::ErrorKind::Interrupted => continue,
                    // Non-blocking: a long line (what is carried over) waits for Node to read.
                    std::io::ErrorKind::WouldBlock => {
                        let mut fd = libc::pollfd { fd: self.control.as_raw_fd(), events: libc::POLLOUT, revents: 0 };
                        // SAFETY: poll over one live pollfd.
                        if unsafe { libc::poll(&mut fd, 1, 5_000) } <= 0 {
                            log::warn(&format!("Node {} did not read what it was told", self.pid));
                            return;
                        }
                        continue;
                    }
                    _ => {}
                }
                log::warn(&format!("could not tell Node {}: {error}", self.pid));
                return;
            }
            rest = &rest[n as usize..];
        }
    }
}

impl Node {
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

/// Unix's processes: each Node given the listening sockets as fds 3 and 4, in a process group of its own.
struct System {
    options: Options,
    /// The data directory's lock (data::lock).
    lock: File,
    mcp: OwnedFd,
    admin: OwnedFd,
    /// The parent at the start (--with-parent): another one later (init, a subreaper) is its end.
    parent: i32,
    /// What this launcher is (its executable's bytes, hashed), told apart from the release's (`renew`).
    own: Option<u64>,
}

/// Where the release has its launcher (scripts/station-bundle.sh: the Rust station's path).
const LAUNCHER_IN_APP: &str = "mesh/target/release/stillfail-station";
/// What a launcher's `handoff-version` says from when it takes a running one's place (`--resume`).
const TAKES_OVER: u32 = 3;

fn hash_of(path: &Path) -> Option<u64> {
    let bytes = std::fs::read(path).ok()?;
    let mut hasher = DefaultHasher::new();
    hasher.write(&bytes);
    Some(hasher.finish())
}

/// The descriptors a launcher hands on to the one it becomes (exec): inherited, then made close-on-exec again there.
fn inheritable(fds: &[RawFd], on: bool) {
    for fd in fds {
        // SAFETY: fcntl on descriptors this process owns.
        unsafe { libc::fcntl(*fd, libc::F_SETFD, if on { 0 } else { libc::FD_CLOEXEC }) };
    }
}

/// The handled signals, held (pending) or let through: held across an exec, they reach the new launcher's handlers.
fn hold_signals(hold: bool) {
    // SAFETY: a signal set filled here, given to sigprocmask.
    unsafe {
        let mut set: libc::sigset_t = std::mem::zeroed();
        libc::sigemptyset(&mut set);
        for signal in HANDLED {
            libc::sigaddset(&mut set, signal);
        }
        libc::sigprocmask(if hold { libc::SIG_BLOCK } else { libc::SIG_UNBLOCK }, &set, std::ptr::null_mut());
    }
}

impl Os for System {
    type Node = Node;

    fn now(&self) -> Instant {
        Instant::now()
    }

    fn spawn(&mut self) -> Result<Node> {
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
            .args(["--launcher-fds", "3,4,5", "--launcher-carries"])
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
        // Reaped by waitpid in serve(), not by std.
        drop(child);
        Ok(Node { pid, control: ours, pending: vec![], open: true })
    }

    fn kill(&mut self, node: &mut Node) {
        // SAFETY: a signal to a child of this process not yet reaped.
        unsafe { libc::kill(node.pid, libc::SIGKILL) };
    }

    fn parent_gone(&mut self) -> bool {
        // SAFETY: getppid has no preconditions.
        unsafe { libc::getppid() != self.parent }
    }

    fn program(&self) -> String {
        crate::node(&self.options.app).display().to_string()
    }

    fn renew(&mut self, serving: &Node, version: &str, served: &[(String, u16)]) {
        let release = self.options.app.join(LAUNCHER_IN_APP);
        let Some(theirs) = hash_of(&release) else { return };
        if self.own == Some(theirs) {
            return;
        }
        // One from before it could take over (a release rolled back to) would not find the lock its own.
        let takes = Command::new(&release).arg("handoff-version").stdin(Stdio::null()).stderr(Stdio::null()).output();
        let version_said = takes.ok().filter(|o| o.status.success()).and_then(|o| String::from_utf8_lossy(&o.stdout).trim().parse::<u32>().ok());
        if version_said.is_none_or(|v| v < TAKES_OVER) {
            log::warn(&format!("the release's launcher ({}) cannot take this one's place; this one hands over", release.display()));
            return;
        }
        let state = json!({
            "lock": self.lock.as_raw_fd(),
            "mcp": self.mcp.as_raw_fd(),
            "admin": self.admin.as_raw_fd(),
            "parent": self.parent,
            "node": {"pid": serving.pid, "control": serving.control.as_raw_fd(), "pending": serving.pending, "version": version, "served": served},
        });
        let mut args = vec![release.as_os_str().to_owned()];
        args.extend(resumed_args(std::env::args_os().skip(1)));
        args.extend([OsString::from("--resume"), OsString::from(state.to_string())]);
        let Ok(argv) = args.iter().map(|a| CString::new(a.as_bytes())).collect::<std::result::Result<Vec<_>, _>>() else { return };
        let mut pointers: Vec<*const libc::c_char> = argv.iter().map(|a| a.as_ptr()).collect();
        pointers.push(std::ptr::null());
        log::info(&format!("the release has a new launcher; this one becomes it ({})", release.display()));
        let fds = [self.lock.as_raw_fd(), self.mcp.as_raw_fd(), self.admin.as_raw_fd(), serving.control.as_raw_fd()];
        hold_signals(true);
        inheritable(&fds, true);
        // SAFETY: execv with NUL-ended strings that live through the call; it returns only when it failed.
        unsafe { libc::execv(pointers[0], pointers.as_ptr()) };
        let error = Error::last_os_error();
        inheritable(&fds, false);
        hold_signals(false);
        log::warn(&format!("the release's launcher did not run ({error}); this one hands over"));
    }
}

/// This launcher's arguments, for the one it becomes: all but what it was resumed with.
fn resumed_args(mut args: impl Iterator<Item = OsString>) -> Vec<OsString> {
    let mut out = vec![];
    while let Some(arg) = args.next() {
        if arg == "--resume" {
            args.next();
        } else {
            out.push(arg);
        }
    }
    out
}

/// What a launcher this one was before (`renew`) hands on.
struct Resumed {
    lock: File,
    mcp: OwnedFd,
    admin: OwnedFd,
    parent: i32,
    node: Node,
    version: String,
    served: Vec<(String, u16)>,
}

impl Resumed {
    fn read(text: &str) -> Option<Resumed> {
        let state: Value = serde_json::from_str(text).ok()?;
        let fd = |v: &Value| v.as_i64().and_then(|n| RawFd::try_from(n).ok()).filter(|n| *n > 2);
        let (lock, mcp, admin) = (fd(&state["lock"])?, fd(&state["mcp"])?, fd(&state["admin"])?);
        let node = &state["node"];
        let (pid, control) = (node["pid"].as_i64().and_then(|n| i32::try_from(n).ok())?, fd(&node["control"])?);
        let pending: Vec<u8> = serde_json::from_value(node["pending"].clone()).ok()?;
        let served: Vec<(String, u16)> = serde_json::from_value(node["served"].clone()).ok()?;
        let version = node["version"].as_str()?.to_string();
        let parent = state["parent"].as_i64().and_then(|n| i32::try_from(n).ok())?;
        inheritable(&[lock, mcp, admin, control], false);
        // SAFETY: the descriptors the launcher before handed on, owned by this one from here.
        let (lock, mcp, admin, control) = unsafe { (File::from_raw_fd(lock), OwnedFd::from_raw_fd(mcp), OwnedFd::from_raw_fd(admin), OwnedFd::from_raw_fd(control)) };
        Some(Resumed { lock, mcp, admin, parent, node: Node { pid, control, pending, open: true }, version, served })
    }
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
    // Held by a launcher before this one across its exec (`renew`): what came meanwhile comes now.
    hold_signals(false);
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

pub fn run(mut options: Options) -> i32 {
    keep_low_fds();
    let run = options.data.join("run");
    if let Some(state) = options.resume.take() {
        return resume(options, run, &state);
    }
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
    let lock = match data::lock(&run.join("station.lock")) {
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
    let bound = {
        // Only the machine's own data directory has the usual ports (ports.rs).
        let own = data::is_default(&data::home(), &options.data);
        crate::ports::mcp(&options.data, &config, own).and_then(|mcp| Ok((mcp, crate::ports::admin(&options.data, options.port, options.named, own, config.english)?)))
    };
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
    let with_parent = options.with_parent;
    // SAFETY: getppid has no preconditions.
    let parent = unsafe { libc::getppid() };
    let own = std::env::current_exe().ok().and_then(|exe| hash_of(&exe));
    let mut station = Lifecycle::new(System { options, lock, mcp, admin, parent, own }, Times::of_env(), run, with_parent);
    station.start();
    serve(&mut station, signals)
}

/// A launcher before this one in this process became this one at a handover (`renew`): its lock, ports and the Node
/// serving taken up, and the handover it was asked for gone on with.
fn resume(options: Options, run: PathBuf, state: &str) -> i32 {
    let Some(resumed) = Resumed::read(state) else {
        // Nothing to go on with: the Node serving ends as its control socket closes with this, and the service starts
        // the station again.
        log::error("what the launcher before this one handed on does not read; stopping");
        return 1;
    };
    let signals = match take_signals() {
        Ok(fd) => fd,
        Err(error) => {
            log::error(&format!("signals not taken: {error}"));
            return 1;
        }
    };
    if let Err(error) = nonblocking(resumed.node.control.as_raw_fd()) {
        log::warn(&format!("the control socket not made non-blocking: {error}"));
    }
    let with_parent = options.with_parent;
    // This launcher is the release's (it was run from there).
    let own = hash_of(&options.app.join(LAUNCHER_IN_APP));
    let Resumed { lock, mcp, admin, parent, node, version, served } = resumed;
    let mut station = Lifecycle::new(System { options, lock, mcp, admin, parent, own }, Times::of_env(), run, with_parent);
    station.adopt(node, version, served);
    // A Node that ended meanwhile (its SIGCHLD held, then come) is reaped as signals come.
    station.start_next();
    serve(&mut station, signals)
}

/// Waits for what happens (a signal, a line from a Node, something due) and tells the lifecycle, until it is done.
fn serve(station: &mut Lifecycle<System>, signals: OwnedFd) -> i32 {
    loop {
        if let Some(exit) = station.finished() {
            log::info("stopped");
            return exit;
        }
        let mut fds = vec![libc::pollfd { fd: signals.as_raw_fd(), events: libc::POLLIN, revents: 0 }];
        let mut pids = vec![];
        for (_, node) in station.processes_mut() {
            if node.open {
                fds.push(libc::pollfd { fd: node.control.as_raw_fd(), events: libc::POLLIN, revents: 0 });
                pids.push(node.pid);
            }
        }
        let timeout = station.next_due().map_or(-1, |at| at.saturating_duration_since(Instant::now()).as_millis().min(i32::MAX as u128) as c_int + 1);
        // SAFETY: poll over a live array of pollfds.
        let n = unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, timeout) };
        if n < 0 && Error::last_os_error().kind() != std::io::ErrorKind::Interrupted {
            log::error(&format!("poll: {}", Error::last_os_error()));
            return 1;
        }
        if n > 0 {
            for (pid, fd) in pids.iter().zip(&fds[1..]) {
                if fd.revents == 0 {
                    continue;
                }
                let Some(said) = station.processes_mut().into_iter().find(|(_, node)| node.pid == *pid).map(|(_, node)| node.read()) else {
                    continue;
                };
                station.heard(*pid as u32, said);
            }
            if fds[0].revents != 0 {
                for signal in drain_signals(&signals) {
                    match signal {
                        libc::SIGCHLD => reap(station),
                        libc::SIGTERM | libc::SIGINT => {
                            log::info("stopping");
                            station.stop();
                        }
                        libc::SIGUSR1 => station.ask("drain"),
                        libc::SIGHUP => station.ask("hup"),
                        libc::SIGUSR2 => station.start_next(),
                        _ => {}
                    }
                }
            }
        }
        station.tick();
    }
}

/// The Nodes that ended, told to the lifecycle.
fn reap(station: &mut Lifecycle<System>) {
    loop {
        let mut status = 0;
        // SAFETY: waitpid on this process's children, without blocking.
        let pid = unsafe { libc::waitpid(-1, &mut status, libc::WNOHANG) };
        if pid <= 0 {
            return;
        }
        // What it said before it ended (what it carried over at a handover) is the lifecycle's first.
        if let Some(said) = station.processes_mut().into_iter().find(|(_, node)| node.pid == pid && node.open).map(|(_, node)| node.read()) {
            station.heard(pid as u32, said);
        }
        station.ended(pid as u32, &describe(status));
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
