//! What the runner does through the system on macOS and Linux: a Unix socket, a session and a process group of the
//! agent's own, signals.

use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::net::Shutdown;
use std::os::unix::fs::{DirBuilderExt, FileExt, OpenOptionsExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicI32, Ordering};

use serde_json::{Value, json};

use super::Signal;

/// Where the parent of a forked runner waits to hear it is ready (see `leave_session`); -1 when there is none.
static READY_FD: AtomicI32 = AtomicI32::new(-1);

/// `<dir>/<id>.sock`.
pub fn socket_path(dir: &Path, id: &str) -> PathBuf {
    dir.join(format!("{id}.sock"))
}

/// The socket is a file: it goes with the others.
pub fn remove_socket(sock: &Path) {
    let _ = fs::remove_file(sock);
}

/// Leaves the starter's session and process group, so that ending those (launchd ending the station, a terminal
/// closing) leaves the runner and its agent be. A group leader cannot setsid: it forks first, and the parent stays
/// only until the child is ready, then exits with what the child would have.
pub fn leave_session() {
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

/// Tells a forked runner's parent it is ready, so it exits and lets go of the starter.
pub fn ready() {
    let fd = READY_FD.swap(-1, Ordering::SeqCst);
    if fd >= 0 {
        // SAFETY: the pipe's write end, ours alone.
        unsafe {
            libc::write(fd, [1u8].as_ptr().cast(), 1);
            libc::close(fd);
        }
    }
}

pub fn create_dir(dir: &Path) -> io::Result<()> {
    fs::DirBuilder::new().recursive(true).mode(0o700).create(dir)
}

/// Opened for writing, created 0600.
pub fn create_file(options: &mut OpenOptions) -> &mut OpenOptions {
    options.mode(0o600)
}

pub fn write_all_at(file: &File, buf: &[u8], at: u64) -> io::Result<()> {
    file.write_all_at(buf, at)
}

/// Gives back the disk under `len` bytes of `path` from `at`, the file keeping its length (what is there reads as
/// zeros): macOS's F_PUNCHHOLE, Linux's FALLOC_FL_PUNCH_HOLE. `at` and `len` whole blocks.
pub fn punch(path: &Path, at: u64, len: u64) -> io::Result<()> {
    use std::os::fd::AsRawFd;
    let file = std::fs::OpenOptions::new().write(true).open(path)?;
    let fd = file.as_raw_fd();
    #[cfg(target_os = "macos")]
    let r = {
        let hole = libc::fpunchhole_t { fp_flags: 0, reserved: 0, fp_offset: at as libc::off_t, fp_length: len as libc::off_t };
        // SAFETY: fd is open for writing; `hole` lives across the call.
        unsafe { libc::fcntl(fd, libc::F_PUNCHHOLE, &hole) }
    };
    #[cfg(target_os = "linux")]
    // SAFETY: fd is open for writing.
    let r = unsafe { libc::fallocate(fd, libc::FALLOC_FL_PUNCH_HOLE | libc::FALLOC_FL_KEEP_SIZE, at as libc::off_t, len as libc::off_t) };
    #[cfg(not(any(target_os = "macos", target_os = "linux")))]
    let r = { let _ = (fd, at, len); 0 };
    if r == 0 { Ok(()) } else { Err(io::Error::last_os_error()) }
}

pub fn read_exact_at(file: &File, buf: &mut [u8], at: u64) -> io::Result<()> {
    file.read_exact_at(buf, at)
}

/// Whether a process of this pid lives (one of another user's, too).
pub fn alive(pid: i32) -> bool {
    // SAFETY: signal 0 only checks the process exists. One not ours to signal (EPERM) is no runner of this user's.
    pid > 0 && unsafe { libc::kill(pid, 0) } == 0
}

/// When a process started, in ms since the epoch, if that can be told.
#[cfg(target_os = "macos")]
pub fn started_ms(pid: i32) -> Option<u64> {
    let size = std::mem::size_of::<libc::proc_bsdinfo>() as libc::c_int;
    // SAFETY: an all-zero proc_bsdinfo is valid (plain integers and bytes), and the call writes at most `size` bytes.
    let info = unsafe {
        let mut info: libc::proc_bsdinfo = std::mem::zeroed();
        (libc::proc_pidinfo(pid, libc::PROC_PIDTBSDINFO, 0, (&raw mut info).cast(), size) == size).then_some(info)?
    };
    Some(info.pbi_start_tvsec * 1000 + info.pbi_start_tvusec / 1000)
}

/// When a process started, in ms since the epoch, if that can be told.
#[cfg(target_os = "linux")]
pub fn started_ms(pid: i32) -> Option<u64> {
    // Its start in clock ticks since boot: the 20th field after the name, which may hold anything up to its last ')'.
    let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    let ticks: u64 = stat.rsplit_once(')')?.1.split_whitespace().nth(19)?.parse().ok()?;
    let boot = std::fs::read_to_string("/proc/stat").ok()?;
    let boot: u64 = boot.lines().find_map(|line| line.strip_prefix("btime "))?.trim().parse().ok()?;
    // SAFETY: sysconf only reads a setting.
    let per_second = u64::try_from(unsafe { libc::sysconf(libc::_SC_CLK_TCK) }).ok().filter(|hz| *hz > 0)?;
    Some(boot * 1000 + ticks * 1000 / per_second)
}

/// When a process started: not known on this system.
#[cfg(not(any(target_os = "macos", target_os = "linux")))]
pub fn started_ms(_pid: i32) -> Option<u64> {
    None
}

/// Lets go of the starter's stdio: stdout closes (it reads the ready line to its end), and nothing it holds is
/// written to or read from again.
pub fn detach_stdio() {
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

pub struct Listener(UnixListener);

impl Listener {
    pub fn bind(sock: &Path) -> Result<Listener, String> {
        // The socket is made 0600 from the start; the umask is the process's, so it is put back right after.
        // SAFETY: umask has no failure; no other thread runs yet.
        let old = unsafe { libc::umask(0o177) };
        let bound = UnixListener::bind(sock);
        unsafe { libc::umask(old) };
        let listener = bound.map_err(|e| format!("cannot listen on {}: {e}", sock.display()))?;
        let _ = fs::set_permissions(sock, fs::Permissions::from_mode(0o600));
        Ok(Listener(listener))
    }

    pub fn accept(&self) -> io::Result<Conn> {
        self.0.accept().map(|(stream, _)| Conn(stream))
    }
}

pub struct Conn(UnixStream);

impl Conn {
    pub fn try_clone(&self) -> io::Result<Conn> {
        self.0.try_clone().map(Conn)
    }

    /// Ends it both ways: its reader sees the end, the station sees it closed.
    pub fn shutdown(&self) {
        let _ = self.0.shutdown(Shutdown::Both);
    }
}

impl Read for Conn {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        self.0.read(buf)
    }
}

impl Write for Conn {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.0.write(buf)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.0.flush()
    }
}

/// The agent: its pid, which is also its process group.
pub struct Agent {
    pid: i32,
}

/// Starts the agent in a process group of its own.
pub fn spawn(program: &str, args: &[String], cwd: Option<&Path>) -> io::Result<(Child, Agent)> {
    let mut command = Command::new(program);
    command.args(args).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).process_group(0);
    if let Some(cwd) = cwd {
        command.current_dir(cwd);
    }
    let child = command.spawn()?;
    let pid = child.id() as i32;
    Ok((child, Agent { pid }))
}

/// Starts a terminal's program on a pseudo-terminal of `cols` × `rows`, the leader of a session of its own (which is
/// its process group, as `spawn`'s is) with the terminal as its controlling one: its stdin, stdout and stderr all the
/// terminal. The terminal's other side (what it writes, and where its input goes) is the File returned.
pub fn spawn_pty(program: &str, args: &[String], cwd: Option<&Path>, cols: u16, rows: u16) -> io::Result<(Child, Agent, File)> {
    use std::os::fd::{FromRawFd, OwnedFd};
    let (mut master, mut slave) = (-1, -1);
    let mut size = winsize(cols, rows);
    // SAFETY: openpty writes the two descriptors; the name and the termios are left as the system's. (macOS says its
    // termios and winsize are `*mut`, Linux `*const`: a `*mut` is taken as either.)
    if unsafe { libc::openpty(&mut master, &mut slave, std::ptr::null_mut(), std::ptr::null_mut(), &raw mut size) } != 0 {
        return Err(io::Error::last_os_error());
    }
    // SAFETY: both were just opened and are ours alone.
    let (master, slave) = unsafe { (OwnedFd::from_raw_fd(master), OwnedFd::from_raw_fd(slave)) };
    // The program must not hold the runner's side: its end would never be seen.
    // SAFETY: fcntl on a descriptor of ours.
    unsafe { libc::fcntl(std::os::fd::AsRawFd::as_raw_fd(&master), libc::F_SETFD, libc::FD_CLOEXEC) };
    let mut command = Command::new(program);
    command.args(args).stdin(slave.try_clone()?).stdout(slave.try_clone()?).stderr(slave);
    // What it reads of the terminal it is in; the rest of the environment is the runner's (the station's).
    command.env("TERM", "xterm-256color").env("COLORTERM", "truecolor");
    if let Some(cwd) = cwd {
        command.current_dir(cwd);
    }
    // SAFETY: between fork and exec only async-signal-safe calls: setsid, ioctl.
    unsafe {
        command.pre_exec(|| {
            if libc::setsid() < 0 {
                return Err(io::Error::last_os_error());
            }
            if libc::ioctl(0, libc::TIOCSCTTY as _, 0) < 0 {
                return Err(io::Error::last_os_error());
            }
            Ok(())
        });
    }
    // (the command, and the slave's copies in it, go once it has started: only the program holds that side then)
    let child = command.spawn()?;
    let pid = child.id() as i32;
    Ok((child, Agent { pid }, File::from(master)))
}

fn winsize(cols: u16, rows: u16) -> libc::winsize {
    libc::winsize { ws_row: rows.max(1), ws_col: cols.max(1), ws_xpixel: 0, ws_ypixel: 0 }
}

/// Tells the terminal's program its terminal is now `cols` × `rows` (it is sent SIGWINCH).
pub fn resize_pty(master: &File, cols: u16, rows: u16) -> io::Result<()> {
    use std::os::fd::AsRawFd;
    let size = winsize(cols, rows);
    // SAFETY: TIOCSWINSZ on the terminal's side we hold, with a winsize that lives across the call.
    if unsafe { libc::ioctl(master.as_raw_fd(), libc::TIOCSWINSZ as _, &size) } != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

impl Agent {
    pub fn pid(&self) -> i32 {
        self.pid
    }

    /// Ends the group just started, whose start did not go through.
    pub fn abandon(&self) {
        // SAFETY: the group was just started and is ours.
        unsafe { libc::kill(-self.pid, libc::SIGKILL) };
    }

    /// Waits for the agent to exit: `ended` is called once it has, before it is reaped (see `signal`). Its exit, as
    /// the runner says it.
    pub fn wait(&self, _child: Child, ended: impl FnOnce()) -> Value {
        let pid = self.pid;
        // It is seen ended before it is reaped, so a `signal` never reaches a pid that was reaped and reused.
        // SAFETY: waitid/waitpid on our own child, with somewhere to write.
        unsafe {
            let mut info: libc::siginfo_t = std::mem::zeroed();
            while libc::waitid(libc::P_PID, pid as libc::id_t, &mut info, libc::WEXITED | libc::WNOWAIT) < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {}
        }
        ended();
        let mut status = 0;
        unsafe { while libc::waitpid(pid, &mut status, 0) < 0 && io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {} }
        if libc::WIFSIGNALED(status) {
            json!({"op": "exit", "code": null, "signal": signal_name(libc::WTERMSIG(status))})
        } else {
            json!({"op": "exit", "code": libc::WEXITSTATUS(status), "signal": null})
        }
    }

    /// Sends `signal` to the agent's group, or to it alone. Called with the runner's state locked, so the agent is not
    /// reaped meanwhile (see `wait`): `exiting` is whether it has ended.
    pub fn signal(&self, signal: Signal, group: bool, exiting: bool) -> Result<(), String> {
        let signal = match signal {
            Signal::Term => libc::SIGTERM,
            Signal::Kill => libc::SIGKILL,
            Signal::Int => libc::SIGINT,
        };
        let target = target(self.pid, group, exiting)?;
        // SAFETY: kill on the agent or its group.
        if unsafe { libc::kill(target, signal) } != 0 {
            return Err(format!("signal: {}", io::Error::last_os_error()));
        }
        Ok(())
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
