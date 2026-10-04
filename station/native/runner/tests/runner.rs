//! Runs the runner around small /bin/sh agents and talks to it as a station would.

use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::UnixStream;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use base64::Engine;
use base64::engine::general_purpose::STANDARD as B64;
use serde_json::{Value, json};

const BIN: &str = env!("CARGO_BIN_EXE_stillfail-runner");

/// A short path: socket paths are limited to about 100 bytes.
fn tmpdir(name: &str) -> PathBuf {
    let dir = PathBuf::from(format!("/tmp/sfr-{}-{name}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    dir
}

fn alive(pid: i64) -> bool {
    unsafe { libc::kill(pid as i32, 0) == 0 }
}

fn wait_until(what: &str, mut ok: impl FnMut() -> bool) {
    let until = Instant::now() + Duration::from_secs(5);
    while !ok() {
        assert!(Instant::now() < until, "timed out waiting for {what}");
        std::thread::sleep(Duration::from_millis(20));
    }
}

struct Runner {
    dir: PathBuf,
    info: Value,
    /// The runner when this test started it directly (it is then a zombie once it exits, until waited for).
    child: Option<Child>,
}

impl Runner {
    fn start(name: &str, script: &str) -> Runner {
        Runner::start_with(name, &[], script)
    }

    fn start_with(name: &str, extra: &[&str], script: &str) -> Runner {
        let dir = tmpdir(name);
        let mut child = Command::new(BIN)
            .args(["--dir", dir.to_str().unwrap(), "--id", "a"])
            .args(extra)
            .args(["--", "/bin/sh", "-c", script])
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        let info = ready_line(child.stdout.take().unwrap());
        Runner { dir, info, child: Some(child) }
    }

    fn pid(&self, key: &str) -> i64 {
        self.info[key].as_i64().unwrap()
    }

    fn connect(&self) -> Client {
        let stream = UnixStream::connect(self.info["socket"].as_str().unwrap()).unwrap();
        stream.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
        Client { reader: BufReader::new(stream.try_clone().unwrap()), writer: stream }
    }

    fn files(&self) -> Vec<String> {
        let mut names: Vec<String> = fs::read_dir(&self.dir).map(|d| d.map(|e| e.unwrap().file_name().into_string().unwrap()).collect()).unwrap_or_default();
        names.sort();
        names
    }

    /// Waits for a runner this test started to exit, with its code.
    fn exited(&mut self) -> i32 {
        let child = self.child.as_mut().unwrap();
        let until = Instant::now() + Duration::from_secs(5);
        loop {
            if let Some(status) = child.try_wait().unwrap() {
                return status.code().unwrap_or(-1);
            }
            assert!(Instant::now() < until, "the runner did not exit");
            std::thread::sleep(Duration::from_millis(20));
        }
    }
}

impl Drop for Runner {
    fn drop(&mut self) {
        unsafe {
            libc::kill(-(self.pid("pgid") as i32), libc::SIGKILL);
            libc::kill(self.pid("runner") as i32, libc::SIGKILL);
        }
        if let Some(child) = self.child.as_mut() {
            let _ = child.wait();
        }
        let _ = fs::remove_dir_all(&self.dir);
    }
}

/// The ready line, and that stdout closes after it.
fn ready_line(stdout: impl std::io::Read) -> Value {
    let mut reader = BufReader::new(stdout);
    let mut line = String::new();
    reader.read_line(&mut line).unwrap();
    let info: Value = serde_json::from_str(&line).unwrap_or_else(|e| panic!("ready line {line:?}: {e}"));
    assert_eq!(info["ready"], json!(true));
    let mut rest = String::new();
    reader.read_line(&mut rest).unwrap();
    assert_eq!(rest, "", "stdout closes after the ready line");
    info
}

struct Client {
    reader: BufReader<UnixStream>,
    writer: UnixStream,
}

impl Client {
    fn send(&mut self, message: Value) {
        self.writer.write_all(format!("{message}\n").as_bytes()).unwrap();
    }

    /// The next message, or None once the runner closed the connection.
    fn recv(&mut self) -> Option<Value> {
        let mut line = String::new();
        match self.reader.read_line(&mut line) {
            Ok(0) => None,
            Ok(_) => Some(serde_json::from_str(&line).unwrap()),
            // A connection the runner shut down can also end in a reset.
            Err(e) if e.kind() == std::io::ErrorKind::ConnectionReset => None,
            Err(e) => panic!("reading from the runner: {e}"),
        }
    }

    /// Closes its side and reads to the end: the runner reads a connection's messages in order up to its end, so once
    /// the end is back, everything sent before (an ack, say) has been taken. Dropping the connection instead leaves it
    /// to a race: the next connection, coming first, ends this one with its messages unread.
    fn leave(mut self) {
        self.writer.shutdown(std::net::Shutdown::Write).unwrap();
        while self.recv().is_some() {}
    }

    fn write(&mut self, data: &[u8]) {
        self.send(json!({"op": "write", "data": B64.encode(data)}));
    }

    /// Reads `out` messages, checking their offsets run on from `at`, until `stream` has `want` bytes in all.
    fn read_until(&mut self, at: &mut [u64; 2], got: &mut [Vec<u8>; 2], stream: usize, want: usize) {
        while got[stream].len() < want {
            let message = self.recv().expect("connection ended");
            assert_eq!(message["op"], "out", "{message}");
            self.take(message, at, got);
        }
    }

    fn take(&mut self, message: Value, at: &mut [u64; 2], got: &mut [Vec<u8>; 2]) {
        let i = match message["stream"].as_str() {
            Some("out") => 0,
            Some("err") => 1,
            other => panic!("stream {other:?}"),
        };
        assert_eq!(message["at"].as_u64().unwrap(), at[i], "offsets run on: {message}");
        let data = B64.decode(message["data"].as_str().unwrap()).unwrap();
        at[i] += data.len() as u64;
        got[i].extend(data);
    }

    /// Everything up to the exit, which must come last.
    fn until_exit(&mut self, mut at: [u64; 2]) -> ([Vec<u8>; 2], Value) {
        let mut got = [vec![], vec![]];
        loop {
            let message = self.recv().expect("connection ended before the exit");
            if message["op"] == "exit" {
                return (got, message);
            }
            assert_eq!(message["op"], "out", "{message}");
            self.take(message, &mut at, &mut got);
        }
    }

    /// That nothing comes for a while.
    fn quiet(&mut self) {
        self.reader.get_ref().set_read_timeout(Some(Duration::from_millis(300))).unwrap();
        let mut line = String::new();
        let read = self.reader.read_line(&mut line);
        assert!(read.is_err(), "expected nothing, got {line:?}");
        self.reader.get_ref().set_read_timeout(Some(Duration::from_secs(5))).unwrap();
    }
}

#[test]
fn the_ready_line_says_where_everything_is() {
    let runner = Runner::start("ready", "read x");
    let info = &runner.info;
    let dir = runner.dir.to_str().unwrap();
    assert_eq!(info["id"], "a");
    assert_eq!(info["program"], "/bin/sh");
    assert_eq!(info["args"], json!(["-c", "read x"]));
    assert_eq!(info["socket"], format!("{dir}/a.sock"));
    assert_eq!(info["out"], format!("{dir}/a.out"));
    assert_eq!(info["err"], format!("{dir}/a.err"));
    assert_eq!(info["runner"].as_u64().unwrap(), runner.child.as_ref().unwrap().id() as u64);
    assert_eq!(info["pid"], info["pgid"], "the agent leads its own group");
    assert_ne!(info["pid"], info["runner"]);
    assert_eq!(unsafe { libc::getpgid(runner.pid("pid") as i32) } as i64, runner.pid("pid"));
    let started = info["startedAt"].as_u64().unwrap();
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() as u64;
    assert!(started <= now && now - started < 10_000);
    // The json on disk is the ready line without "ready".
    let mut on_disk: Value = serde_json::from_str(&fs::read_to_string(runner.dir.join("a.json")).unwrap()).unwrap();
    on_disk["ready"] = json!(true);
    assert_eq!(&on_disk, info);
    for name in ["a.json", "a.sock"] {
        assert_eq!(fs::metadata(runner.dir.join(name)).unwrap().permissions().mode() & 0o777, 0o600, "{name}");
    }
    assert_eq!(runner.files(), ["a.err", "a.json", "a.out", "a.sock"]);
    // The runner left its starter's session.
    assert_eq!(unsafe { libc::getsid(runner.pid("runner") as i32) } as i64, runner.pid("runner"));
}

#[test]
fn output_comes_with_its_offsets_then_the_exit_and_again_on_the_next_attach() {
    let runner = Runner::start("offsets", "printf abc; printf def >&2; sleep 0.1; printf ghi; printf jk >&2; exit 3");
    let mut client = runner.connect();
    client.send(json!({"op": "attach"}));
    let ([out, err], exit) = client.until_exit([0, 0]);
    assert_eq!(out, b"abcghi");
    assert_eq!(err, b"defjk");
    assert_eq!(exit, json!({"op": "exit", "code": 3, "signal": null}));
    // The files hold the same bytes.
    assert_eq!(fs::read(runner.dir.join("a.out")).unwrap(), b"abcghi");
    assert_eq!(fs::read(runner.dir.join("a.err")).unwrap(), b"defjk");
    // Nothing acknowledged: a new connection is sent it all again, exit included.
    let mut again = runner.connect();
    again.send(json!({"op": "attach"}));
    let ([out, err], exit) = again.until_exit([0, 0]);
    assert_eq!((out.as_slice(), err.as_slice()), (&b"abcghi"[..], &b"defjk"[..]));
    assert_eq!(exit["code"], 3);
}

#[test]
fn the_exit_comes_after_all_output_even_what_a_child_writes_late() {
    let runner = Runner::start("all", "head -c 300000 /dev/zero | tr '\\0' x; (sleep 0.3; printf late) & exit 0");
    let mut client = runner.connect();
    client.send(json!({"op": "attach"}));
    let ([out, _], exit) = client.until_exit([0, 0]);
    assert_eq!(out.len(), 300_004);
    assert!(out.ends_with(b"xlate"));
    assert_eq!(exit["code"], 0);
}

#[test]
fn a_second_connection_attaching_resumes_from_the_ack() {
    let runner = Runner::start("ack", "printf 'one\\n'; read x; printf 'two\\n'");
    let mut client = runner.connect();
    client.send(json!({"op": "attach"}));
    let (mut at, mut got) = ([0, 0], [vec![], vec![]]);
    client.read_until(&mut at, &mut got, 0, 4);
    assert_eq!(got[0], b"one\n");
    client.send(json!({"op": "ack", "out": 9, "err": 0}));
    assert_eq!(client.recv().unwrap()["op"], "error", "an ack past the end is refused");
    client.send(json!({"op": "ack", "out": 2, "err": 0}));
    client.leave();

    let mut second = runner.connect();
    second.send(json!({"op": "attach"}));
    let (mut at, mut got) = ([2, 0], [vec![], vec![]]);
    second.read_until(&mut at, &mut got, 0, 2);
    assert_eq!(got[0], b"e\n");
    second.send(json!({"op": "ack", "out": 4}));
    second.leave();

    let mut third = runner.connect();
    third.send(json!({"op": "attach"}));
    third.quiet();
    third.write(b"go\n");
    let ([out, _], exit) = third.until_exit([4, 0]);
    assert_eq!(out, b"two\n");
    assert_eq!(exit["code"], 0);
}

#[test]
fn stdin_is_written_and_closed() {
    let runner = Runner::start("stdin", "cat; echo end");
    let mut client = runner.connect();
    client.send(json!({"op": "attach"}));
    client.write(b"hello\n");
    let (mut at, mut got) = ([0, 0], [vec![], vec![]]);
    client.read_until(&mut at, &mut got, 0, 6);
    assert_eq!(got[0], b"hello\n");
    client.send(json!({"op": "write", "data": "not base64!"}));
    assert_eq!(client.recv().unwrap()["op"], "error");
    client.send(json!({"op": "close_stdin"}));
    let ([out, _], exit) = client.until_exit(at);
    assert_eq!(out, b"end\n");
    assert_eq!(exit["code"], 0);
}

/// The agent starts a background sleep and says its pid.
fn agent_with_grandchild(name: &str) -> (Runner, Client, i64) {
    let runner = Runner::start(name, "sleep 30 >/dev/null 2>&1 & echo $!; wait");
    let mut client = runner.connect();
    client.send(json!({"op": "attach"}));
    let mut got = [vec![], vec![]];
    let mut at = [0, 0];
    while !got[0].ends_with(b"\n") {
        let want = got[0].len() + 1;
        client.read_until(&mut at, &mut got, 0, want);
    }
    let grandchild: i64 = String::from_utf8(got[0].clone()).unwrap().trim().parse().unwrap();
    assert!(alive(grandchild));
    (runner, client, grandchild)
}

#[test]
fn signal_to_the_group_takes_the_grandchild_too() {
    let (_runner, mut client, grandchild) = agent_with_grandchild("group");
    client.send(json!({"op": "signal", "signal": "TERM", "group": true}));
    let (_, exit) = client.until_exit([0, 0]);
    // The output was had already; nothing more comes before the exit.
    assert_eq!(exit, json!({"op": "exit", "code": null, "signal": "TERM"}));
    wait_until("the grandchild to die", || !alive(grandchild));
    client.send(json!({"op": "signal", "signal": "TERM"}));
    assert_eq!(client.recv().unwrap()["error"], "signal: the agent has exited");
    client.send(json!({"op": "signal", "signal": "STOP"}));
    assert_eq!(client.recv().unwrap()["op"], "error");
}

#[test]
fn signal_to_the_agent_alone_leaves_the_grandchild() {
    let (runner, mut client, grandchild) = agent_with_grandchild("alone");
    client.send(json!({"op": "signal", "signal": "TERM", "group": false}));
    let (_, exit) = client.until_exit([0, 0]);
    assert_eq!(exit["signal"], "TERM");
    std::thread::sleep(Duration::from_millis(100));
    assert!(alive(grandchild), "only the agent was signalled");
    // The group outlives its leader: it can still be ended by pgid.
    client.send(json!({"op": "signal", "signal": "KILL", "group": true}));
    wait_until("the grandchild to die", || !alive(grandchild));
    drop(runner);
}

#[test]
fn done_after_the_exit_removes_the_files_and_ends_the_runner() {
    let mut runner = Runner::start("done", "printf hi");
    let mut client = runner.connect();
    client.send(json!({"op": "attach"}));
    let ([out, _], _) = client.until_exit([0, 0]);
    assert_eq!(out, b"hi");
    client.send(json!({"op": "done"}));
    assert_eq!(runner.exited(), 0);
    assert!(runner.files().is_empty(), "{:?}", runner.files());
    assert!(client.recv().is_none());
}

#[test]
fn done_while_running_ends_nothing_and_cleans_up_once_the_agent_exits() {
    let mut runner = Runner::start("done-early", "read x");
    let mut client = runner.connect();
    client.send(json!({"op": "attach"}));
    client.send(json!({"op": "done"}));
    client.quiet();
    assert!(alive(runner.pid("pid")));
    assert_eq!(runner.files().len(), 4);
    client.write(b"x\n");
    assert_eq!(runner.exited(), 0);
    assert!(runner.files().is_empty(), "{:?}", runner.files());
}

#[test]
fn a_new_connection_replaces_the_old() {
    let runner = Runner::start("replace", "read x; echo $x");
    let mut first = runner.connect();
    first.send(json!({"op": "attach"}));
    let mut second = runner.connect();
    second.send(json!({"op": "attach"}));
    assert!(first.recv().is_none(), "the old connection is closed");
    second.write(b"hi\n");
    let ([out, _], exit) = second.until_exit([0, 0]);
    assert_eq!(out, b"hi\n");
    assert_eq!(exit["code"], 0);
}

#[test]
fn after_the_exit_without_done_it_cleans_up_by_itself() {
    let mut runner = Runner::start_with("linger", &["--linger-ms", "300"], "exit 0");
    assert_eq!(runner.exited(), 0);
    assert!(runner.files().is_empty(), "{:?}", runner.files());
}

/// Starts the runner from a shell, which writes the ready line to a file; returns the shell and the ready line.
fn start_from_shell(dir: &Path, after: &str, own_group: bool) -> (Child, Value) {
    fs::create_dir_all(dir).unwrap();
    let ready = dir.join("ready");
    let mut command = Command::new("/bin/sh");
    command
        .args(["-c", &format!("\"$@\" > \"$READY\" & {after}"), "sh", BIN, "--dir", dir.to_str().unwrap(), "--id", "a", "--", "/bin/sh", "-c", "read x; echo got $x"])
        .env("READY", &ready)
        .stdin(Stdio::null());
    if own_group {
        command.process_group(0);
    }
    let shell = command.spawn().unwrap();
    wait_until("the ready line", || fs::read_to_string(&ready).is_ok_and(|s| s.ends_with('\n')));
    let info = serde_json::from_str(&fs::read_to_string(&ready).unwrap()).unwrap();
    (shell, info)
}

fn still_works(runner: &Runner) {
    assert!(alive(runner.pid("runner")));
    assert!(alive(runner.pid("pid")));
    let mut client = runner.connect();
    client.send(json!({"op": "attach"}));
    client.write(b"hi\n");
    let ([out, _], exit) = client.until_exit([0, 0]);
    assert_eq!(out, b"got hi\n");
    assert_eq!(exit["code"], 0);
}

#[test]
fn the_runner_outlives_the_process_that_started_it() {
    let dir = tmpdir("parent");
    let (mut shell, info) = start_from_shell(&dir, "exit 0", false);
    assert!(shell.wait().unwrap().success());
    let runner = Runner { dir, info, child: None };
    // Its parent gone, it is taken up by init/launchd.
    let ppid = Command::new("ps").args(["-o", "ppid=", "-p", &runner.pid("runner").to_string()]).output().unwrap();
    assert_eq!(String::from_utf8_lossy(&ppid.stdout).trim(), "1");
    still_works(&runner);
}

#[test]
fn the_agent_survives_its_starter_killed_with_its_whole_group() {
    let dir = tmpdir("setsid");
    let (mut shell, info) = start_from_shell(&dir, "sleep 30", true);
    let runner = Runner { dir, info, child: None };
    // The runner was started inside the shell's group, and left it.
    assert_ne!(unsafe { libc::getpgid(runner.pid("runner") as i32) }, shell.id() as i32);
    unsafe { libc::kill(-(shell.id() as i32), libc::SIGKILL) };
    shell.wait().unwrap();
    std::thread::sleep(Duration::from_millis(100));
    still_works(&runner);
}

#[test]
fn a_runner_started_as_a_group_leader_forks_to_leave_the_session() {
    let dir = tmpdir("leader");
    let mut child = Command::new(BIN)
        .args(["--dir", dir.to_str().unwrap(), "--id", "a", "--", "/bin/sh", "-c", "read x; echo got $x"])
        .stdout(Stdio::piped())
        .process_group(0)
        .spawn()
        .unwrap();
    let info = ready_line(child.stdout.take().unwrap());
    assert!(child.wait().unwrap().success(), "the parent half exits 0 once the runner is ready");
    let runner = Runner { dir, info, child: None };
    assert_ne!(runner.pid("runner"), child.id() as i64);
    assert_eq!(unsafe { libc::getsid(runner.pid("runner") as i32) } as i64, runner.pid("runner"));
    still_works(&runner);
}

#[test]
fn a_start_that_fails_says_why_and_leaves_nothing() {
    let dir = tmpdir("fail");
    let out = Command::new(BIN).args(["--dir", dir.to_str().unwrap(), "--id", "a", "--", "/nonexistent/agent"]).output().unwrap();
    assert_eq!(out.status.code(), Some(1));
    assert!(out.stdout.is_empty());
    assert!(String::from_utf8_lossy(&out.stderr).contains("cannot start /nonexistent/agent"), "{}", String::from_utf8_lossy(&out.stderr));
    assert_eq!(fs::read_dir(&dir).unwrap().count(), 0);
    let _ = fs::remove_dir_all(&dir);

    let usage = Command::new(BIN).args(["--id", "a", "--", "/bin/true"]).output().unwrap();
    assert_eq!(usage.status.code(), Some(2));

    // A group leader's failure is reported by the parent half too.
    let out = Command::new(BIN).args(["--dir", dir.to_str().unwrap(), "--id", "a", "--", "/nonexistent/agent"]).process_group(0).output().unwrap();
    assert_eq!(out.status.code(), Some(1));
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn a_second_runner_for_a_live_id_is_refused() {
    let runner = Runner::start("twice", "read x");
    let out = Command::new(BIN).args(["--dir", runner.dir.to_str().unwrap(), "--id", "a", "--", "/bin/true"]).output().unwrap();
    assert_eq!(out.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&out.stderr).contains("already"));
    assert!(alive(runner.pid("pid")));
    assert_eq!(runner.files().len(), 4);
}
