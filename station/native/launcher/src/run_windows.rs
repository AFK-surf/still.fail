//! `run` on Windows: the station's Node process under a launcher whose pid and lock stay, as run.rs is on Unix, less
//! what Windows cannot do the same way.
//!
//! - Node binds its ports itself (Node cannot listen on a socket handed down on Windows), so a new Node is not started
//!   beside the old one: there is no handover, and a restart leaves the ports for a moment.
//! - The control channel is a named pipe only this user may open, `\\.\pipe\stillfail-launcher-<pid>-<n>`, given as
//!   `--launcher-pipe`; on it the same lines go both ways as on Unix's socket.
//! - There are no signals: a ^C (or the console closing) stops the station, as SIGTERM does on Unix. Node runs in a
//!   process group of its own, so the ^C reaches the launcher only.
//!
//! Threads say what happened (Node's exit, a line from it, a ^C, the parent gone) on one channel; the main thread acts.

use std::ffi::OsStr;
use std::io;
use std::os::windows::ffi::OsStrExt;
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle, RawHandle};
use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::ptr::{null, null_mut};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use serde_json::Value;
use windows_sys::Win32::Foundation::{CloseHandle, ERROR_IO_PENDING, ERROR_PIPE_CONNECTED, GetLastError, HANDLE, INVALID_HANDLE_VALUE, LocalFree};
use windows_sys::Win32::Security::Authorization::{ConvertSidToStringSidW, ConvertStringSecurityDescriptorToSecurityDescriptorW, SDDL_REVISION_1};
use windows_sys::Win32::Security::{GetTokenInformation, SECURITY_ATTRIBUTES, TOKEN_QUERY, TOKEN_USER, TokenUser};
use windows_sys::Win32::Storage::FileSystem::{FILE_FLAG_FIRST_PIPE_INSTANCE, FILE_FLAG_OVERLAPPED, PIPE_ACCESS_DUPLEX, ReadFile, WriteFile};
use windows_sys::Win32::System::Console::SetConsoleCtrlHandler;
use windows_sys::Win32::System::IO::{CancelIoEx, GetOverlappedResult, OVERLAPPED};
use windows_sys::Win32::System::Pipes::{ConnectNamedPipe, CreateNamedPipeW, PIPE_READMODE_BYTE, PIPE_REJECT_REMOTE_CLIENTS, PIPE_TYPE_BYTE, PIPE_WAIT};
use windows_sys::Win32::System::Threading::{
    CREATE_NEW_PROCESS_GROUP, CreateEventW, GetCurrentProcess, GetExitCodeProcess, OpenProcess, OpenProcessToken, PROCESS_QUERY_LIMITED_INFORMATION,
    PROCESS_SYNCHRONIZE, WaitForSingleObject,
};

use crate::data::{self, Config, now_ms, write_whole};
use crate::log;

pub struct Options {
    pub data: PathBuf,
    pub app: PathBuf,
    pub port: u16,
    pub named: bool,
    pub with_parent: bool,
}

/// As run.rs has them: a stopped Node's time to exit; restarts after an unexpected exit, doubling; how many starts in a
/// row may end before Node says ready.
const STOP: Duration = Duration::from_secs(30);
const BACKOFF: Duration = Duration::from_secs(1);
const BACKOFF_MAX: Duration = Duration::from_secs(60);
const START_FAILURES: u32 = 5;
const PARENT: Duration = Duration::from_secs(2);

enum Event {
    /// Node `n` exited, with this code.
    Exited(u64, Option<i32>),
    /// Node `n` said this.
    Said(u64, Value),
    Stop(&'static str),
}

static EVENTS: OnceLock<Mutex<Sender<Event>>> = OnceLock::new();

/// ^C, ^Break, the console closing, the user logging off: the station stops.
unsafe extern "system" fn on_ctrl(_kind: u32) -> i32 {
    if let Some(events) = EVENTS.get() {
        let _ = events.lock().unwrap_or_else(|e| e.into_inner()).send(Event::Stop("a console event"));
    }
    1
}

struct Node {
    n: u64,
    child: Child,
    pipe: Pipe,
    ready: bool,
}

impl Node {
    fn tell(&self, op: &str) {
        let line = format!("{{\"op\":\"{op}\"}}\n");
        if let Err(error) = self.pipe.write_all(line.as_bytes()) {
            log::warn(&format!("Node {} not told {op}: {error}", self.child.id()));
        }
    }
}

pub fn run(options: Options) -> i32 {
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
    let security = match Security::this_user() {
        Ok(security) => Arc::new(security),
        Err(error) => {
            log::error(&error);
            return 1;
        }
    };
    let (tx, rx) = mpsc::channel();
    let _ = EVENTS.set(Mutex::new(tx.clone()));
    // SAFETY: a handler that only sends on a channel.
    unsafe { SetConsoleCtrlHandler(Some(on_ctrl), 1) };
    if options.with_parent {
        watch_parent(tx.clone());
    }
    Launcher { options, run, security, tx, rx, next: 0, failures: 0, backoff_step: 0 }.serve()
}

struct Launcher {
    options: Options,
    run: PathBuf,
    security: Arc<Security>,
    tx: Sender<Event>,
    rx: Receiver<Event>,
    next: u64,
    failures: u32,
    backoff_step: u32,
}

impl Launcher {
    fn serve(mut self) -> i32 {
        let mut node = self.start();
        let mut restart_at: Option<Instant> = None;
        loop {
            if node.is_none() && restart_at.is_none() {
                restart_at = Some(self.failed_start());
                if self.failures >= START_FAILURES {
                    log::error(&format!("Node did not start {START_FAILURES} times in a row; giving up"));
                    return 1;
                }
            }
            let event = match restart_at {
                Some(at) => match self.rx.recv_timeout(at.saturating_duration_since(Instant::now())) {
                    Ok(event) => Some(event),
                    Err(RecvTimeoutError::Timeout) => None,
                    Err(RecvTimeoutError::Disconnected) => return 1,
                },
                None => self.rx.recv().ok(),
            };
            match event {
                None => {
                    restart_at = None;
                    node = self.start();
                }
                Some(Event::Said(n, message)) => {
                    let Some(current) = node.as_mut().filter(|c| c.n == n) else { continue };
                    if message["ready"] == true && !current.ready {
                        current.ready = true;
                        self.failures = 0;
                        self.backoff_step = 0;
                        let version = message["version"].as_str().unwrap_or_default();
                        log::info(&format!("Node {} ready (version {version})", current.child.id()));
                        if let Err(error) = write_whole(&self.run.join("station.json"), &data::station_json(std::process::id(), now_ms(), version)) {
                            log::warn(&format!("station.json not written: {error}"));
                        }
                    } else if let Some(said) = message["drained"].as_str() {
                        let _ = write_whole(&self.run.join("drained"), &format!("{said}\n"));
                    }
                }
                Some(Event::Exited(n, code)) => {
                    let Some(current) = node.take_if(|c| c.n == n) else { continue };
                    log::warn(&format!("Node {} exited unexpectedly ({})", current.child.id(), code.map_or("no code".into(), |c| format!("code {c}"))));
                    if current.ready {
                        restart_at = Some(self.backoff());
                    }
                }
                Some(Event::Stop(why)) => {
                    log::info(&format!("stopping ({why})"));
                    if let Some(current) = node.take() {
                        self.stop(current);
                    }
                    return 0;
                }
            }
        }
    }

    /// A start that came to nothing: when to try again.
    fn failed_start(&mut self) -> Instant {
        self.failures += 1;
        self.backoff()
    }

    fn backoff(&mut self) -> Instant {
        let delay = BACKOFF.saturating_mul(1 << self.backoff_step.min(16)).min(BACKOFF_MAX);
        self.backoff_step += 1;
        log::info(&format!("starting Node again in {} ms", delay.as_millis()));
        Instant::now() + delay
    }

    fn start(&mut self) -> Option<Node> {
        self.next += 1;
        let n = self.next;
        let name = format!(r"\\.\pipe\stillfail-launcher-{}-{n}", std::process::id());
        let pipe = match Pipe::create(&name, &self.security) {
            Ok(pipe) => pipe,
            Err(error) => {
                log::error(&format!("{name}: {error}"));
                return None;
            }
        };
        let app = &self.options.app;
        let mut command = Command::new(crate::node(app));
        command.arg(crate::main_js(app)).arg("run").arg("--app").arg(app).arg("--data").arg(&self.options.data).arg("--launcher-pipe").arg(&name);
        if self.options.named {
            command.arg("--port").arg(self.options.port.to_string());
        }
        command.stdin(Stdio::null()).creation_flags(CREATE_NEW_PROCESS_GROUP);
        let mut child = match command.spawn() {
            Ok(child) => child,
            Err(error) => {
                log::error(&format!("{} did not start: {error}", crate::node(app).display()));
                return None;
            }
        };
        log::info(&format!("Node started (pid {})", child.id()));
        // Its exit, seen from a thread of its own: a handle of its process to wait on.
        // SAFETY: a handle of ours, closed by OwnedHandle.
        let process = unsafe { OpenProcess(PROCESS_SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, 0, child.id()) };
        if process.is_null() {
            log::error(&format!("Node {} cannot be waited for: {}", child.id(), io::Error::last_os_error()));
            let _ = child.kill();
            return None;
        }
        let process = unsafe { OwnedHandle::from_raw_handle(process as RawHandle) };
        let (tx, wait_pipe) = (self.tx.clone(), pipe.clone());
        std::thread::spawn(move || {
            // SAFETY: waiting on our handle.
            unsafe { WaitForSingleObject(process.as_raw_handle() as HANDLE, u32::MAX) };
            // A pipe it never connected to waits no more.
            wait_pipe.cancel();
            let code = exit_code(&process);
            let _ = tx.send(Event::Exited(n, code));
        });
        let (tx, read_pipe) = (self.tx.clone(), pipe.clone());
        std::thread::spawn(move || read_lines(n, read_pipe, tx));
        let _ = child.stdin.take();
        Some(Node { n, child, pipe, ready: false })
    }

    /// Tells it to stop, waits for its exit (STOP at most), then ends it.
    fn stop(&self, mut node: Node) {
        node.tell("stop");
        let deadline = Instant::now() + STOP;
        loop {
            match self.rx.recv_timeout(deadline.saturating_duration_since(Instant::now())) {
                Ok(Event::Exited(n, _)) if n == node.n => return,
                Ok(_) => {}
                Err(_) => break,
            }
        }
        log::warn(&format!("Node {} did not stop in {} s; ending it", node.child.id(), STOP.as_secs()));
        let _ = node.child.kill();
        let _ = node.child.wait();
    }
}

fn exit_code(process: &OwnedHandle) -> Option<i32> {
    let mut code = 0u32;
    // SAFETY: on our handle of the exited process.
    let ok = unsafe { GetExitCodeProcess(process.as_raw_handle() as HANDLE, &mut code) };
    (ok != 0).then_some(code as i32)
}

/// Lines from Node on the pipe, once it has connected; until it closes.
fn read_lines(n: u64, pipe: Pipe, tx: Sender<Event>) {
    if pipe.connect().is_err() {
        return;
    }
    let mut pending = Vec::new();
    let mut buf = [0u8; 4096];
    loop {
        let got = match pipe.read(&mut buf) {
            Ok(0) | Err(_) => return,
            Ok(got) => got,
        };
        pending.extend_from_slice(&buf[..got]);
        while let Some(at) = pending.iter().position(|&b| b == b'\n') {
            let line: Vec<u8> = pending.drain(..=at).collect();
            match serde_json::from_slice::<Value>(&line) {
                Ok(message) => {
                    let _ = tx.send(Event::Said(n, message));
                }
                Err(_) => log::warn(&format!("an unreadable line from Node: {}", String::from_utf8_lossy(&line).trim())),
            }
        }
    }
}

/// --with-parent: the parent's end stops the station (looked at every PARENT, as on Unix).
fn watch_parent(tx: Sender<Event>) {
    let Some(parent) = parent_pid() else {
        log::warn("--with-parent: the parent is not known");
        return;
    };
    // SAFETY: a handle of ours, waited on and closed.
    let process = unsafe { OpenProcess(PROCESS_SYNCHRONIZE, 0, parent) };
    if process.is_null() {
        let _ = tx.send(Event::Stop("the parent is gone"));
        return;
    }
    let process = unsafe { OwnedHandle::from_raw_handle(process as RawHandle) };
    std::thread::spawn(move || {
        // SAFETY: waiting on our handle; PARENT at a time, as Unix looks.
        while unsafe { WaitForSingleObject(process.as_raw_handle() as HANDLE, PARENT.as_millis() as u32) } != 0 {}
        let _ = tx.send(Event::Stop("the parent is gone"));
    });
}

fn parent_pid() -> Option<u32> {
    use windows_sys::Win32::System::Diagnostics::ToolHelp::{CreateToolhelp32Snapshot, PROCESSENTRY32W, Process32FirstW, Process32NextW, TH32CS_SNAPPROCESS};
    let me = std::process::id();
    // SAFETY: a snapshot of ours, closed after; the entry's size set as the API wants.
    unsafe {
        let snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if snapshot == INVALID_HANDLE_VALUE {
            return None;
        }
        let snapshot = OwnedHandle::from_raw_handle(snapshot as RawHandle);
        let mut entry: PROCESSENTRY32W = std::mem::zeroed();
        entry.dwSize = size_of::<PROCESSENTRY32W>() as u32;
        let mut more = Process32FirstW(snapshot.as_raw_handle() as HANDLE, &mut entry) != 0;
        while more {
            if entry.th32ProcessID == me {
                return Some(entry.th32ParentProcessID);
            }
            more = Process32NextW(snapshot.as_raw_handle() as HANDLE, &mut entry) != 0;
        }
        None
    }
}

fn wide(text: &str) -> Vec<u16> {
    OsStr::new(text).encode_wide().chain(Some(0)).collect()
}

/// A security descriptor letting this user alone open the pipe (as the runner's).
struct Security(*mut std::ffi::c_void);

// SAFETY: read only, by CreateNamedPipeW.
unsafe impl Send for Security {}
unsafe impl Sync for Security {}

impl Security {
    fn this_user() -> Result<Security, String> {
        let failed = |what: &str| format!("{what}: {}", io::Error::last_os_error());
        // SAFETY: the token and buffers are ours; what Windows allocates is freed with LocalFree.
        unsafe {
            let mut token = null_mut();
            if OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token) == 0 {
                return Err(failed("OpenProcessToken"));
            }
            let token = OwnedHandle::from_raw_handle(token as RawHandle);
            let mut size = 0;
            GetTokenInformation(token.as_raw_handle() as HANDLE, TokenUser, null_mut(), 0, &mut size);
            let mut buf = vec![0u64; (size as usize).div_ceil(8)];
            if GetTokenInformation(token.as_raw_handle() as HANDLE, TokenUser, buf.as_mut_ptr().cast(), size, &mut size) == 0 {
                return Err(failed("GetTokenInformation"));
            }
            let user = &*(buf.as_ptr() as *const TOKEN_USER);
            let mut sid = null_mut();
            if ConvertSidToStringSidW(user.User.Sid, &mut sid) == 0 {
                return Err(failed("ConvertSidToStringSidW"));
            }
            let len = (0..).take_while(|&i| *sid.add(i) != 0).count();
            let sid_text = String::from_utf16_lossy(std::slice::from_raw_parts(sid, len));
            LocalFree(sid.cast());
            let sddl = wide(&format!("D:P(A;;GA;;;{sid_text})"));
            let mut descriptor = null_mut();
            if ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl.as_ptr(), SDDL_REVISION_1, &mut descriptor, null_mut()) == 0 {
                return Err(failed("ConvertStringSecurityDescriptorToSecurityDescriptorW"));
            }
            Ok(Security(descriptor))
        }
    }
}

impl Drop for Security {
    fn drop(&mut self) {
        // SAFETY: allocated by ConvertStringSecurityDescriptorToSecurityDescriptorW.
        unsafe { LocalFree(self.0) };
    }
}

/// One instance of a named pipe for one Node, opened for overlapped I/O (a read waiting does not hold up a write).
#[derive(Clone)]
struct Pipe(Arc<OwnedHandle>);

impl Pipe {
    fn create(name: &str, security: &Security) -> io::Result<Pipe> {
        let attributes = SECURITY_ATTRIBUTES { nLength: size_of::<SECURITY_ATTRIBUTES>() as u32, lpSecurityDescriptor: security.0, bInheritHandle: 0 };
        let name = wide(name);
        // SAFETY: a name and attributes that live through the call.
        let handle = unsafe {
            CreateNamedPipeW(
                name.as_ptr(),
                PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
                PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
                1,
                4096,
                4096,
                0,
                &attributes,
            )
        };
        if handle == INVALID_HANDLE_VALUE {
            return Err(io::Error::last_os_error());
        }
        // SAFETY: just made, ours alone.
        Ok(Pipe(Arc::new(unsafe { OwnedHandle::from_raw_handle(handle as RawHandle) })))
    }

    fn raw(&self) -> HANDLE {
        self.0.as_raw_handle() as HANDLE
    }

    fn connect(&self) -> io::Result<()> {
        self.overlapped(|h, o| unsafe { ConnectNamedPipe(h, o) }, |e| e == ERROR_PIPE_CONNECTED).map(|_| ())
    }

    fn read(&self, buf: &mut [u8]) -> io::Result<usize> {
        let len = buf.len() as u32;
        // SAFETY: the buffer outlives the operation (`overlapped` waits for its end).
        self.overlapped(|h, o| unsafe { ReadFile(h, buf.as_mut_ptr(), len, null_mut(), o) }, |_| false)
    }

    fn write_all(&self, mut buf: &[u8]) -> io::Result<()> {
        while !buf.is_empty() {
            let len = buf.len() as u32;
            // SAFETY: as in read.
            let n = self.overlapped(|h, o| unsafe { WriteFile(h, buf.as_ptr(), len, null_mut(), o) }, |_| false)?;
            if n == 0 {
                return Err(io::ErrorKind::WriteZero.into());
            }
            buf = &buf[n..];
        }
        Ok(())
    }

    /// Ends what waits on it (a connect Node will never make).
    fn cancel(&self) {
        // SAFETY: on our own handle.
        unsafe { CancelIoEx(self.raw(), null()) };
    }

    fn overlapped(&self, start: impl FnOnce(HANDLE, *mut OVERLAPPED) -> i32, done: impl Fn(u32) -> bool) -> io::Result<usize> {
        // SAFETY: the event and the OVERLAPPED live until the operation has ended (GetOverlappedResult waits for it).
        unsafe {
            let event = CreateEventW(null(), 1, 0, null());
            if event.is_null() {
                return Err(io::Error::last_os_error());
            }
            let mut o: OVERLAPPED = std::mem::zeroed();
            o.hEvent = event;
            let result = (|| {
                if start(self.raw(), &mut o) == 0 {
                    let error = GetLastError();
                    if done(error) {
                        return Ok(0);
                    }
                    if error != ERROR_IO_PENDING {
                        return Err(io::Error::from_raw_os_error(error as i32));
                    }
                }
                let mut n = 0;
                if GetOverlappedResult(self.raw(), &o, &mut n, 1) == 0 {
                    return Err(io::Error::last_os_error());
                }
                Ok(n as usize)
            })();
            CloseHandle(event);
            result
        }
    }
}
