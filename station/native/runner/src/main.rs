//! stillfail-runner: keeps one agent process (claude, codex app-server) for the station, so the agent outlives the
//! station restarting or crashing (docs/station-ts-native.md, section 1).
//!
//! The runner holds the agent's stdin and appends its stdout and stderr to `<id>.out` and `<id>.err` as they come. A
//! station attaches on `<id>.sock` and is sent what it has not acknowledged yet, then whatever follows; the agent's
//! exit comes after all of its output.

use std::fs::{self, File, OpenOptions};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::Shutdown;
use std::os::unix::fs::{DirBuilderExt, FileExt, OpenOptionsExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use base64::Engine;
use base64::engine::general_purpose::STANDARD as B64;
use serde_json::{Value, json};

const USAGE: &str = "usage: stillfail-runner --dir <run/runners> --id <id> [--cwd <dir>] -- <program> <args…>";
/// How long a runner whose agent has exited waits for a `done` before it cleans up by itself.
const LINGER: Duration = Duration::from_secs(24 * 3600);
/// After the agent exits, how long its output may take to end (something it started can hold the pipes open).
const SETTLE: Duration = Duration::from_secs(1);
/// Most bytes in one `out` message.
const CHUNK: usize = 64 * 1024;
const STREAMS: [&str; 2] = ["out", "err"];

/// Where the parent of a forked runner waits to hear it is ready (see `leave_session`); -1 when there is none.
static READY_FD: AtomicI32 = AtomicI32::new(-1);

struct Args {
    dir: PathBuf,
    id: String,
    cwd: Option<PathBuf>,
    linger: Duration,
    settle: Duration,
    program: String,
    args: Vec<String>,
}

#[derive(Clone)]
struct Paths {
    sock: PathBuf,
    json: PathBuf,
    out: PathBuf,
    err: PathBuf,
}

impl Paths {
    fn remove(&self) {
        for path in [&self.sock, &self.json, &self.out, &self.err] {
            let _ = fs::remove_file(path);
        }
    }
}

struct Shared {
    state: Mutex<State>,
    changed: Condvar,
    /// The agent's pid, which is also its process group.
    pid: i32,
    paths: Paths,
    /// Read handles on `<id>.out` and `<id>.err`, which is where what is sent comes from.
    files: [File; 2],
    stdin: Sender<Option<Vec<u8>>>,
    linger: Duration,
    settle: Duration,
}

#[derive(Default)]
struct State {
    /// Bytes of each stream written to its file so far.
    len: [u64; 2],
    eof: [bool; 2],
    /// The agent has ended (not reaped yet, maybe): its pid is no longer to be signalled alone.
    exiting: bool,
    exit: Option<Value>,
    /// The agent has exited and its output has ended (or had its time to): the exit may be sent.
    settled: bool,
    acked: [u64; 2],
    /// The current connection, by number; a new one closes the one before.
    conn: u64,
    current: Option<UnixStream>,
    /// What the current connection is being sent, once it has attached.
    push: Option<Push>,
    /// Counts attaches, so that a send in flight while the client re-attaches does not move the new cursor.
    epoch: u64,
    /// `done` came while the agent was running: clean up once it exits.
    done: bool,
}

struct Push {
    epoch: u64,
    at: [u64; 2],
    exit_sent: bool,
}

fn main() {
    let args = match parse_args(std::env::args().skip(1).collect()) {
        Ok(args) => args,
        Err(e) => {
            eprintln!("stillfail-runner: {e}\n{USAGE}");
            std::process::exit(2);
        }
    };
    leave_session();
    let (shared, listener) = match start(&args) {
        Ok(started) => started,
        Err(e) => {
            eprintln!("stillfail-runner: {e}");
            std::process::exit(1);
        }
    };
    serve(shared, listener);
}

fn parse_args(raw: Vec<String>) -> Result<Args, String> {
    let (mut dir, mut id, mut cwd, mut linger, mut settle) = (None, None, None, LINGER, SETTLE);
    let mut it = raw.into_iter();
    let mut command = Vec::new();
    while let Some(arg) = it.next() {
        let mut value = || it.next().ok_or_else(|| format!("{arg} needs a value"));
        match arg.as_str() {
            "--dir" => dir = Some(PathBuf::from(value()?)),
            "--id" => id = Some(value()?),
            "--cwd" => cwd = Some(PathBuf::from(value()?)),
            // Not for the station: lets tests see the cleanup without waiting a day.
            "--linger-ms" => linger = Duration::from_millis(value()?.parse().map_err(|_| "--linger-ms needs a number of ms")?),
            // Not for the station either: lets tests wait for the output's end however late it comes.
            "--settle-ms" => settle = Duration::from_millis(value()?.parse().map_err(|_| "--settle-ms needs a number of ms")?),
            "--" => {
                command = it.collect();
                break;
            }
            other => return Err(format!("unknown argument {other}")),
        }
    }
    let dir = dir.ok_or("--dir is required")?;
    let id = id.ok_or("--id is required")?;
    if id.is_empty() || id.starts_with('.') || id.contains('/') {
        return Err(format!("bad id {id:?}"));
    }
    if command.is_empty() {
        return Err("no program given after --".into());
    }
    let program = command.remove(0);
    let dir = std::path::absolute(&dir).map_err(|e| format!("bad --dir: {e}"))?;
    Ok(Args { dir, id, cwd, linger, settle, program, args: command })
}

/// Leaves the starter's session and process group, so that ending those (launchd ending the station, a terminal
/// closing) leaves the runner and its agent be. A group leader cannot setsid: it forks first, and the parent stays
/// only until the child is ready, then exits with what the child would have.
fn leave_session() {
    // SAFETY: plain syscalls; this runs before any thread is started, so fork is safe.
    unsafe {
        if libc::getsid(0) == libc::getpid() || libc::setsid() >= 0 {
            return;
        }
        let mut fds = [0; 2];
        if libc::pipe(fds.as_mut_ptr()) != 0 {
            eprintln!("stillfail-runner: pipe: {}", io::Error::last_os_error());
            std::process::exit(1);
        }
        // The agent must not hold either end, or the parent would wait on it.
        libc::fcntl(fds[0], libc::F_SETFD, libc::FD_CLOEXEC);
        libc::fcntl(fds[1], libc::F_SETFD, libc::FD_CLOEXEC);
        match libc::fork() {
            -1 => {
                eprintln!("stillfail-runner: fork: {}", io::Error::last_os_error());
                std::process::exit(1);
            }
            0 => {
                libc::close(fds[0]);
                libc::setsid();
                READY_FD.store(fds[1], Ordering::SeqCst);
            }
            child => {
                libc::close(fds[1]);
                let mut byte = 0u8;
                loop {
                    let n = libc::read(fds[0], (&raw mut byte).cast(), 1);
                    if n == 1 {
                        libc::_exit(0);
                    }
                    if n == 0 || io::Error::last_os_error().kind() != io::ErrorKind::Interrupted {
                        break;
                    }
                }
                // It failed before being ready: its status is ours.
                let mut status = 0;
                while libc::waitpid(child, &mut status, 0) < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {}
                libc::_exit(if libc::WIFEXITED(status) { libc::WEXITSTATUS(status) } else { 1 });
            }
        }
    }
}

/// Starts the agent and everything around it, says it is ready, and lets go of whoever started the runner.
fn start(args: &Args) -> Result<(Arc<Shared>, UnixListener), String> {
    fs::DirBuilder::new().recursive(true).mode(0o700).create(&args.dir).map_err(|e| format!("cannot create {}: {e}", args.dir.display()))?;
    let base = |ext: &str| args.dir.join(format!("{}.{ext}", args.id));
    let paths = Paths { sock: base("sock"), json: base("json"), out: base("out"), err: base("err") };
    if let Some(pid) = live_runner(&paths.json) {
        return Err(format!("{} is already kept by runner {pid}", args.id));
    }
    paths.remove();
    let started = (|| {
        let listener = bind(&paths.sock)?;
        let create = |path: &Path| {
            OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(path).map_err(|e| format!("cannot create {}: {e}", path.display()))
        };
        let (out, err) = (create(&paths.out)?, create(&paths.err)?);
        let open = |path: &Path| File::open(path).map_err(|e| format!("cannot open {}: {e}", path.display()));
        let files = [open(&paths.out)?, open(&paths.err)?];

        let mut command = Command::new(&args.program);
        command.args(&args.args).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).process_group(0);
        if let Some(cwd) = &args.cwd {
            command.current_dir(cwd);
        }
        let started_at = now_ms();
        let mut child = command.spawn().map_err(|e| format!("cannot start {}: {e}", args.program))?;
        let pid = child.id() as i32;
        let text = |path: &Path| path.to_string_lossy().into_owned();
        let info = json!({
            "id": args.id,
            "runner": std::process::id(),
            "pid": pid,
            "pgid": pid,
            "startedAt": started_at,
            "program": args.program,
            "args": args.args,
            "socket": text(&paths.sock),
            "out": text(&paths.out),
            "err": text(&paths.err),
        });
        if let Err(e) = write_atomic(&paths.json, &format!("{info}\n")) {
            // SAFETY: the group was just started and is ours.
            unsafe { libc::kill(-pid, libc::SIGKILL) };
            return Err(e);
        }

        let (stdin_tx, stdin_rx) = mpsc::channel();
        let shared = Arc::new(Shared {
            state: Mutex::new(State::default()),
            changed: Condvar::new(),
            pid,
            paths: paths.clone(),
            files,
            stdin: stdin_tx,
            linger: args.linger,
            settle: args.settle,
        });
        let stdin = child.stdin.take();
        std::thread::spawn(move || feed(stdin, stdin_rx));
        for (i, (pipe, file)) in [(Box::new(child.stdout.take().unwrap()) as Box<dyn Read + Send>, out), (Box::new(child.stderr.take().unwrap()), err)].into_iter().enumerate() {
            let shared = shared.clone();
            std::thread::spawn(move || pump(&shared, i, pipe, file));
        }
        let waiting = shared.clone();
        std::thread::spawn(move || wait_agent(&waiting));

        let mut ready = info;
        ready["ready"] = json!(true);
        Ok((shared, listener, ready))
    })();
    let (shared, listener, ready) = started.inspect_err(|_| paths.remove())?;

    let mut stdout = io::stdout().lock();
    let _ = writeln!(stdout, "{ready}").and_then(|_| stdout.flush());
    drop(stdout);
    detach_stdio();
    let fd = READY_FD.swap(-1, Ordering::SeqCst);
    if fd >= 0 {
        // SAFETY: the pipe's write end, ours alone.
        unsafe {
            libc::write(fd, [1u8].as_ptr().cast(), 1);
            libc::close(fd);
        }
    }
    Ok((shared, listener))
}

/// The pid of a runner still alive for this id, from the json it left.
fn live_runner(json: &Path) -> Option<i32> {
    let info: Value = serde_json::from_slice(&fs::read(json).ok()?).ok()?;
    let pid = info["runner"].as_i64()? as i32;
    // SAFETY: signal 0 only checks the process exists.
    let alive = pid > 0 && pid as u32 != std::process::id() && (unsafe { libc::kill(pid, 0) } == 0 || io::Error::last_os_error().raw_os_error() == Some(libc::EPERM));
    alive.then_some(pid)
}

fn bind(sock: &Path) -> Result<UnixListener, String> {
    // The socket is made 0600 from the start; the umask is the process's, so it is put back right after.
    // SAFETY: umask has no failure; no other thread runs yet.
    let old = unsafe { libc::umask(0o177) };
    let bound = UnixListener::bind(sock);
    unsafe { libc::umask(old) };
    let listener = bound.map_err(|e| format!("cannot listen on {}: {e}", sock.display()))?;
    let _ = fs::set_permissions(sock, fs::Permissions::from_mode(0o600));
    Ok(listener)
}

fn write_atomic(path: &Path, text: &str) -> Result<(), String> {
    let tmp = path.with_extension("json.tmp");
    let written = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&tmp)
        .and_then(|mut file| file.write_all(text.as_bytes()).and_then(|_| file.sync_all()))
        .and_then(|_| fs::rename(&tmp, path));
    written.map_err(|e| {
        let _ = fs::remove_file(&tmp);
        format!("cannot write {}: {e}", path.display())
    })
}

/// Lets go of the starter's stdio: stdout closes (it reads the ready line to its end), and nothing it holds is
/// written to or read from again.
fn detach_stdio() {
    // SAFETY: open and dup2 onto the standard descriptors, which nothing else holds on to.
    unsafe {
        let null = libc::open(c"/dev/null".as_ptr(), libc::O_RDWR);
        if null >= 0 {
            for fd in 0..3 {
                libc::dup2(null, fd);
            }
            if null > 2 {
                libc::close(null);
            }
        }
    }
}

fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0)
}

impl Shared {
    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// The station is done with it: the files go and the runner ends.
    fn finish(&self) -> ! {
        self.paths.remove();
        std::process::exit(0);
    }
}

/// Writes what the station sends to the agent's stdin, in order, off the connection's thread (an agent that is not
/// reading must not hold up a `signal`). `None` closes it.
fn feed(mut stdin: Option<ChildStdin>, rx: Receiver<Option<Vec<u8>>>) {
    for message in rx {
        match message {
            Some(bytes) => {
                if let Some(pipe) = stdin.as_mut()
                    && pipe.write_all(&bytes).is_err()
                {
                    stdin = None; // it went away; its exit says so
                }
            }
            None => stdin = None,
        }
    }
}

/// Copies one of the agent's output pipes into its file, telling the connection each time there is more.
fn pump(shared: &Shared, i: usize, mut pipe: Box<dyn Read + Send>, file: File) {
    let mut buf = vec![0u8; CHUNK];
    loop {
        let n = match pipe.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => n,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        };
        // Written at the stream's length, so a failed write (disk full) leaves no gap: what is lost is lost whole,
        // and offsets stay those of the file.
        let at = shared.lock().len[i];
        if file.write_all_at(&buf[..n], at).is_ok() {
            shared.lock().len[i] += n as u64;
            shared.changed.notify_all();
        }
    }
    shared.lock().eof[i] = true;
    shared.changed.notify_all();
}

/// Waits for the agent to exit, lets its output end, then for a `done`; cleans up by itself after the linger.
fn wait_agent(shared: &Shared) {
    let pid = shared.pid;
    // It is seen ended before it is reaped, so a `signal` never reaches a pid that was reaped and reused.
    // SAFETY: waitid/waitpid on our own child, with somewhere to write.
    unsafe {
        let mut info: libc::siginfo_t = std::mem::zeroed();
        while libc::waitid(libc::P_PID, pid as libc::id_t, &mut info, libc::WEXITED | libc::WNOWAIT) < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {}
    }
    shared.lock().exiting = true;
    let mut status = 0;
    unsafe { while libc::waitpid(pid, &mut status, 0) < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {} }
    let exit = if libc::WIFSIGNALED(status) {
        json!({"op": "exit", "code": null, "signal": signal_name(libc::WTERMSIG(status))})
    } else {
        json!({"op": "exit", "code": libc::WEXITSTATUS(status), "signal": null})
    };

    let mut st = shared.lock();
    st.exit = Some(exit);
    let settle_by = Instant::now() + shared.settle;
    while !(st.eof[0] && st.eof[1]) {
        let left = settle_by.saturating_duration_since(Instant::now());
        if left.is_zero() {
            break;
        }
        st = shared.changed.wait_timeout(st, left).unwrap_or_else(|e| e.into_inner()).0;
    }
    st.settled = true;
    shared.changed.notify_all();
    if st.done {
        shared.finish();
    }
    let linger_until = Instant::now() + shared.linger;
    loop {
        let left = linger_until.saturating_duration_since(Instant::now());
        if left.is_zero() {
            shared.finish();
        }
        st = shared.changed.wait_timeout(st, left).unwrap_or_else(|e| e.into_inner()).0;
    }
}

fn signal_name(signal: i32) -> String {
    let name = match signal {
        libc::SIGTERM => "TERM",
        libc::SIGKILL => "KILL",
        libc::SIGINT => "INT",
        libc::SIGHUP => "HUP",
        libc::SIGQUIT => "QUIT",
        libc::SIGABRT => "ABRT",
        libc::SIGSEGV => "SEGV",
        libc::SIGBUS => "BUS",
        libc::SIGILL => "ILL",
        libc::SIGFPE => "FPE",
        libc::SIGPIPE => "PIPE",
        libc::SIGALRM => "ALRM",
        libc::SIGUSR1 => "USR1",
        libc::SIGUSR2 => "USR2",
        other => return other.to_string(),
    };
    name.into()
}

/// One connection at a time: a new one closes the one before.
fn serve(shared: Arc<Shared>, listener: UnixListener) {
    for stream in listener.incoming() {
        let stream = match stream {
            Ok(stream) => stream,
            Err(_) => {
                std::thread::sleep(Duration::from_millis(100)); // out of descriptors, say: not a spin
                continue;
            }
        };
        let conn = {
            let mut st = shared.lock();
            if let Some(old) = st.current.take() {
                let _ = old.shutdown(Shutdown::Both);
            }
            st.conn += 1;
            st.push = None;
            st.current = stream.try_clone().ok();
            shared.changed.notify_all();
            st.conn
        };
        let shared = shared.clone();
        std::thread::spawn(move || connection(&shared, stream, conn));
    }
}

fn connection(shared: &Arc<Shared>, stream: UnixStream, conn: u64) {
    let Ok(writer) = stream.try_clone() else { return };
    let writer = Arc::new(Mutex::new(writer));
    {
        let (shared, writer) = (shared.clone(), writer.clone());
        std::thread::spawn(move || push(&shared, conn, &writer));
    }
    let mut reader = BufReader::new(stream);
    let mut line = Vec::new();
    loop {
        line.clear();
        match reader.read_until(b'\n', &mut line) {
            Ok(0) | Err(_) => break,
            Ok(_) => {}
        }
        if shared.lock().conn != conn {
            break;
        }
        if line.iter().all(u8::is_ascii_whitespace) {
            continue;
        }
        if let Err(e) = handle(shared, &line) {
            let _ = send(&writer, &json!({"op": "error", "error": e}));
        }
    }
    let mut st = shared.lock();
    if st.conn == conn {
        st.conn += 1;
        st.push = None;
        st.current = None;
        shared.changed.notify_all();
    }
}

fn handle(shared: &Shared, line: &[u8]) -> Result<(), String> {
    let message: Value = serde_json::from_slice(line).map_err(|e| format!("bad message: {e}"))?;
    match message["op"].as_str().ok_or("message has no op")? {
        "attach" => {
            let mut st = shared.lock();
            st.epoch += 1;
            st.push = Some(Push { epoch: st.epoch, at: st.acked, exit_sent: false });
            // A station that attaches wants it again.
            st.done = false;
            shared.changed.notify_all();
        }
        "ack" => {
            let mut st = shared.lock();
            let mut acked = st.acked;
            for (i, stream) in STREAMS.iter().enumerate() {
                let Some(n) = message.get(*stream) else { continue };
                let n = n.as_u64().ok_or_else(|| format!("ack: {stream} is not a byte offset"))?;
                if n > st.len[i] {
                    return Err(format!("ack: {stream} {n} is past the {} bytes there are", st.len[i]));
                }
                acked[i] = acked[i].max(n);
            }
            st.acked = acked;
        }
        "write" => {
            let data = message["data"].as_str().ok_or("write: no data")?;
            let bytes = B64.decode(data).map_err(|e| format!("write: data is not base64: {e}"))?;
            let _ = shared.stdin.send(Some(bytes));
        }
        "close_stdin" => {
            let _ = shared.stdin.send(None);
        }
        "signal" => {
            let signal = match message["signal"].as_str() {
                Some("TERM") => libc::SIGTERM,
                Some("KILL") => libc::SIGKILL,
                Some("INT") => libc::SIGINT,
                other => return Err(format!("signal: unknown signal {other:?}")),
            };
            let group = message["group"].as_bool().unwrap_or(false);
            // Held across kill: the agent is not reaped meanwhile (see wait_agent).
            let st = shared.lock();
            let target = target(shared.pid, group, st.exiting)?;
            // SAFETY: kill on the agent or its group.
            if unsafe { libc::kill(target, signal) } != 0 {
                return Err(format!("signal: {}", io::Error::last_os_error()));
            }
        }
        "done" => {
            let mut st = shared.lock();
            if st.exit.is_some() {
                shared.finish();
            }
            st.done = true;
        }
        other => return Err(format!("unknown op {other:?}")),
    }
    Ok(())
}

/// Whom a `signal` goes to: the agent's group (which outlives the agent), else the agent alone while it runs.
fn target(pid: i32, group: bool, exiting: bool) -> Result<i32, String> {
    if group {
        Ok(-pid)
    } else if exiting {
        Err("signal: the agent has exited".into())
    } else {
        Ok(pid)
    }
}

/// Sends the attached connection what it has not had: each stream from its cursor, in order, then the exit.
fn push(shared: &Shared, conn: u64, writer: &Mutex<UnixStream>) {
    enum Work {
        Out { i: usize, at: u64, n: usize },
        Exit(Value),
    }
    let mut buf = vec![0u8; CHUNK];
    // Turns between the streams, so a busy one does not hold the other back.
    let mut first = 0;
    loop {
        let (work, epoch) = {
            let mut st = shared.lock();
            loop {
                if st.conn != conn {
                    return;
                }
                if let Some(p) = &st.push {
                    let next = [first, 1 - first].into_iter().find(|&i| p.at[i] < st.len[i]);
                    if let Some(i) = next {
                        let n = (st.len[i] - p.at[i]).min(CHUNK as u64) as usize;
                        break (Work::Out { i, at: p.at[i], n }, p.epoch);
                    }
                    if st.settled && !p.exit_sent {
                        break (Work::Exit(st.exit.clone().unwrap()), p.epoch);
                    }
                }
                st = shared.changed.wait(st).unwrap_or_else(|e| e.into_inner());
            }
        };
        let sent = match &work {
            Work::Out { i, at, n } => {
                first = 1 - i;
                if shared.files[*i].read_exact_at(&mut buf[..*n], *at).is_err() {
                    return;
                }
                send(writer, &json!({"op": "out", "stream": STREAMS[*i], "at": at, "data": B64.encode(&buf[..*n])}))
            }
            Work::Exit(exit) => send(writer, exit),
        };
        if sent.is_err() {
            return;
        }
        let mut st = shared.lock();
        if let Some(p) = st.push.as_mut().filter(|p| p.epoch == epoch) {
            match work {
                Work::Out { i, at, n } => p.at[i] = at + n as u64,
                Work::Exit(_) => p.exit_sent = true,
            }
        }
    }
}

fn send(writer: &Mutex<UnixStream>, message: &Value) -> io::Result<()> {
    let mut line = message.to_string();
    line.push('\n');
    writer.lock().unwrap_or_else(|e| e.into_inner()).write_all(line.as_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_signal_goes_to_the_agent_alone_unless_to_its_group() {
        assert_eq!(target(42, false, false), Ok(42));
        assert_eq!(target(42, true, false), Ok(-42));
        // Its group still: what it started may run on.
        assert_eq!(target(42, true, true), Ok(-42));
        assert_eq!(target(42, false, true), Err("signal: the agent has exited".into()));
    }
}
