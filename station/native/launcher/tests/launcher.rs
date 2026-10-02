//! The launcher run as launchd runs it, with a stand-in for the station's Node side (fixtures/main.js) on a real Node
//! ($STILLFAIL_NODE, else the build machine's). Each test has its own data directory and free ports.

use std::io::{BufRead, BufReader, Read};
use std::net::{TcpListener, TcpStream};
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde_json::Value;

const LAUNCHER: &str = env!("CARGO_BIN_EXE_stillfail-station");

fn node() -> String {
    std::env::var("STILLFAIL_NODE").unwrap_or_else(|_| format!("{}/.local/node-v24.15.0-darwin-arm64/bin/node", std::env::var("HOME").unwrap()))
}

/// Held while a socket is made or a process started. On macOS a socket is made close-on-exec only after it is made: a
/// fork from another test thread in between would hand the child (a launcher) a copy of a probe's listening socket,
/// holding its port.
static FORKS: Mutex<()> = Mutex::new(());

fn spawn(command: &mut Command) -> Child {
    let _forks = FORKS.lock().unwrap_or_else(|e| e.into_inner());
    command.spawn().unwrap()
}

fn output(command: &mut Command) -> std::process::Output {
    let _forks = FORKS.lock().unwrap_or_else(|e| e.into_inner());
    command.output().unwrap()
}

fn bind(port: u16) -> std::io::Result<TcpListener> {
    let _forks = FORKS.lock().unwrap_or_else(|e| e.into_inner());
    TcpListener::bind(("127.0.0.1", port))
}

/// A port free now, below the ephemeral range (where the tests' own connections' ports come from) and not handed out
/// to another test of this run: a port asked of the system (bind to 0) could be taken again before the launcher binds it.
fn free_port() -> u16 {
    static GIVEN: Mutex<Vec<u16>> = Mutex::new(Vec::new());
    let mut given = GIVEN.lock().unwrap();
    let seed = std::process::id() as u64 * 7919 + given.len() as u64 * 104_729;
    (0..20_000u64)
        .map(|i| 20_000 + ((seed + i * 7) % 20_000) as u16)
        .find(|p| !given.contains(p) && bind(*p).is_ok())
        .inspect(|p| given.push(*p))
        .unwrap()
}

/// A test's directory: data (with config.json naming the MCP port), app (with the stand-in as station/main.js).
struct Station {
    dir: PathBuf,
    data: PathBuf,
    app: PathBuf,
    mcp: u16,
    admin: u16,
    launcher: Option<Child>,
    times: String,
}

impl Station {
    fn new(name: &str) -> Station {
        let dir = std::env::temp_dir().join(format!("launcher-test-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let (data, app) = (dir.join("data"), dir.join("app"));
        std::fs::create_dir_all(app.join("station")).unwrap();
        std::fs::create_dir_all(&data).unwrap();
        std::fs::copy(Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/main.js"), app.join("station/main.js")).unwrap();
        let mut station = Station { dir, data, app, mcp: 0, admin: 0, launcher: None, times: String::new() };
        station.new_ports();
        station
    }

    fn new_ports(&mut self) {
        (self.mcp, self.admin) = (free_port(), free_port());
        std::fs::write(self.data.join("config.json"), format!(r#"{{"http":{{"port":{}}}}}"#, self.mcp)).unwrap();
    }

    /// Whether the launcher found one of its ports taken: by something else on the build machine, between free_port and
    /// the launcher's bind. The test then starts again on others.
    fn port_was_taken(&self) -> bool {
        let taken = std::fs::read_to_string(self.dir.join("launcher.log")).unwrap_or_default().contains("已被别的程序占用");
        if taken {
            for port in [self.mcp, self.admin] {
                let held = String::from_utf8_lossy(&output(Command::new("lsof").args(["-nP", &format!("-iTCP:{port}")])).stdout).into_owned();
                eprintln!("port {port} taken: {held}");
            }
        }
        taken
    }

    fn command(&self, times: &str) -> Command {
        let mut command = Command::new(LAUNCHER);
        command
            .env("STILLFAIL_NODE", node())
            .env("STILLFAIL_LAUNCHER_TIMES", times)
            .env_remove("STILLFAIL_DATA")
            .env_remove("EMBER_DATA")
            .env_remove("STILLFAIL_CONFIG")
            .env_remove("EMBER_CONFIG")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(std::fs::OpenOptions::new().create(true).append(true).open(self.dir.join("launcher.log")).unwrap());
        command
    }

    fn run_args(&self) -> Vec<String> {
        ["run", "--app", self.app.to_str().unwrap(), "--data", self.data.to_str().unwrap(), "--port", &self.admin.to_string()].map(String::from).to_vec()
    }

    fn start(&mut self, times: &str) {
        self.times = times.to_string();
        let child = spawn(self.command(times).args(self.run_args()));
        self.launcher = Some(child);
    }

    fn pid(&self) -> i32 {
        self.launcher.as_ref().unwrap().id() as i32
    }

    fn signal(&self, signal: i32) {
        // SAFETY: a signal to the launcher this test started.
        assert_eq!(unsafe { libc::kill(self.pid(), signal) }, 0);
    }

    fn wait(&mut self, within: Duration) -> ExitStatus {
        let child = self.launcher.as_mut().unwrap();
        until(within, "the launcher to exit", || child.try_wait().unwrap())
    }

    fn conf(&self, text: &str) {
        std::fs::write(self.data.join("fake.conf"), text).unwrap();
    }

    fn file(&self, name: &str) -> Option<String> {
        std::fs::read_to_string(self.data.join("run").join(name)).ok()
    }

    fn station_json(&self) -> Option<Value> {
        self.file("station.json").and_then(|t| serde_json::from_str(&t).ok())
    }

    /// The stand-in's log: (ms, pid, what).
    fn log(&self) -> Vec<(u64, i32, String)> {
        let text = std::fs::read_to_string(self.data.join("fake.log")).unwrap_or_default();
        text.lines()
            .filter_map(|l| {
                let mut parts = l.splitn(3, ' ');
                Some((parts.next()?.parse().ok()?, parts.next()?.parse().ok()?, parts.next()?.to_string()))
            })
            .collect()
    }

    fn said(&self, pid: i32, what: &str) -> bool {
        self.log().iter().any(|(_, p, w)| *p == pid && w.starts_with(what))
    }

    fn started(&self) -> Vec<i32> {
        self.log().into_iter().filter(|(_, _, w)| w.starts_with("start")).map(|(_, p, _)| p).collect()
    }

    /// Waits for the station to be up: station.json written.
    fn up(&mut self) -> Value {
        for _ in 0..3 {
            let up = until(Duration::from_secs(10), "station.json or an exit", || match self.station_json() {
                Some(said) => Some(Some(said)),
                None => self.launcher.as_mut().unwrap().try_wait().unwrap().map(|_| None),
            });
            match up {
                Some(said) => return said,
                None if self.port_was_taken() => {
                    let _ = std::fs::remove_file(self.dir.join("launcher.log"));
                    self.new_ports();
                    let times = self.times.clone();
                    self.start(&times);
                }
                None => panic!("the launcher exited"),
            }
        }
        panic!("ports taken three times");
    }
}

impl Drop for Station {
    fn drop(&mut self) {
        if std::thread::panicking() {
            eprintln!("--- launcher.log\n{}", std::fs::read_to_string(self.dir.join("launcher.log")).unwrap_or_default());
            eprintln!("--- fake.log\n{}", std::fs::read_to_string(self.data.join("fake.log")).unwrap_or_default());
            for port in [self.mcp, self.admin] {
                let held = String::from_utf8_lossy(&output(Command::new("lsof").args(["-nP", &format!("-iTCP:{port}")])).stdout).into_owned();
                eprintln!("--- port {port}\n{held}");
            }
        }
        // Only the launcher is killed: its Nodes end when their control socket closes.
        if let Some(child) = &mut self.launcher
            && child.try_wait().ok().flatten().is_none()
        {
            let _ = child.kill();
            let _ = child.wait();
        }
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn until<T>(within: Duration, what: &str, mut f: impl FnMut() -> Option<T>) -> T {
    let end = Instant::now() + within;
    loop {
        if let Some(v) = f() {
            return v;
        }
        assert!(Instant::now() < end, "waited {within:?} for {what}");
        std::thread::sleep(Duration::from_millis(20));
    }
}

fn alive(pid: i32) -> bool {
    // SAFETY: signal 0 only asks whether the process is there.
    unsafe { libc::kill(pid, 0) == 0 }
}

/// What the station answers on `port`: "<pid> mcp|admin".
fn ask(port: u16) -> std::io::Result<String> {
    let mut stream = TcpStream::connect_timeout(&([127, 0, 0, 1], port).into(), Duration::from_secs(5))?;
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;
    let mut text = String::new();
    stream.read_to_string(&mut text)?;
    if text.is_empty() {
        return Err(std::io::Error::other("closed without an answer"));
    }
    Ok(text.trim().to_string())
}

fn answered_by(port: u16) -> i32 {
    ask(port).unwrap().split(' ').next().unwrap().parse().unwrap()
}

#[test]
fn handoff_version_is_2() {
    let out = output(Command::new(LAUNCHER).arg("handoff-version"));
    assert!(out.status.success());
    assert_eq!(String::from_utf8(out.stdout).unwrap(), "2\n");
}

#[test]
fn other_commands_are_node_s_with_the_same_arguments() {
    let station = Station::new("exec");
    let mut command = station.command("");
    let args = ["channel", "beta", "--app", station.app.to_str().unwrap(), "--data", station.data.to_str().unwrap()];
    let child = spawn(command.args(args).stdout(Stdio::piped()));
    let pid = child.id();
    let out = child.wait_with_output().unwrap();
    assert_eq!(out.status.code(), Some(7));
    let said: Value = serde_json::from_slice(&out.stdout).unwrap();
    // Exec'd: the same process.
    assert_eq!(said["pid"], pid);
    assert_eq!(said["args"], serde_json::json!(args));
}

#[test]
fn a_held_lock_exits_3() {
    let mut station = Station::new("held");
    std::fs::create_dir_all(station.data.join("run")).unwrap();
    let lock = std::fs::File::create(station.data.join("run/station.lock")).unwrap();
    // SAFETY: flock on a file this test owns.
    assert_eq!(unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) }, 0);
    station.start("");
    assert_eq!(station.wait(Duration::from_secs(5)).code(), Some(3));
    assert!(std::fs::read_to_string(station.dir.join("launcher.log")).unwrap().contains("另一个 still.fail station 正在运行这个数据目录"));
    assert!(station.log().is_empty(), "no Node started");
}

#[test]
fn a_named_port_taken_fails_the_start() {
    let mut station = Station::new("taken");
    let _taken = bind(station.admin).unwrap();
    station.start("");
    assert_eq!(station.wait(Duration::from_secs(5)).code(), Some(1));
    assert!(std::fs::read_to_string(station.dir.join("launcher.log")).unwrap().contains(&format!("端口 127.0.0.1:{} 已被别的程序占用", station.admin)));
}

#[test]
fn node_serves_the_launchers_ports_and_station_json_names_the_launcher() {
    let mut station = Station::new("ports");
    station.start("");
    let before = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() as u64;
    let said = station.up();
    let text = station.file("station.json").unwrap();
    assert!(text.ends_with('\n') && text.trim_end().lines().count() == 1, "{text:?}");
    assert!(text.starts_with(&format!("{{\"pid\":{},\"startedAt\":", station.pid())), "{text}");
    assert_eq!(said["pid"], station.pid());
    assert_eq!(said["version"], "0.1.0");
    assert_eq!((said["handoff"].as_u64(), said["drain"].as_u64(), said["channel"].as_u64()), (Some(1), Some(1), Some(1)));
    assert!(said["startedAt"].as_u64().unwrap() + 10_000 > before);
    assert_eq!(station.file("ports.json").unwrap(), format!("{{\"admin\":{}}}\n", station.admin));
    // The launcher bound them; Node accepts on them.
    let node = station.started()[0];
    assert_ne!(node, station.pid());
    assert_eq!(ask(station.mcp).unwrap(), format!("{node} mcp"));
    assert_eq!(ask(station.admin).unwrap(), format!("{node} admin"));
    let start = &station.log()[0].2;
    let app = station.app.display();
    let data = station.data.display();
    assert_eq!(start, &format!("start run --app {app} --data {data} --launcher-fds 3,4,5"));
    station.signal(libc::SIGTERM);
    assert!(station.wait(Duration::from_secs(5)).success());
    assert!(station.said(node, "got stop") && station.said(node, "exit"));
}

#[test]
fn sigusr2_hands_over_to_a_new_node_with_no_gap_on_the_ports() {
    let mut station = Station::new("handover");
    station.start("");
    let first = station.up();
    let old = answered_by(station.mcp);
    // Asking both ports all along: every connection is answered, by the old Node, then the new.
    let (stop, failed, asked) = (Arc::new(AtomicBool::new(false)), Arc::new(Mutex::new(vec![])), Arc::new(AtomicUsize::new(0)));
    let who = Arc::new(Mutex::new(std::collections::BTreeSet::new()));
    let askers: Vec<_> = [station.mcp, station.admin]
        .into_iter()
        .map(|port| {
            let (stop, failed, asked, who) = (stop.clone(), failed.clone(), asked.clone(), who.clone());
            std::thread::spawn(move || {
                while !stop.load(Ordering::SeqCst) {
                    match ask(port) {
                        Ok(said) => {
                            who.lock().unwrap().insert(said.split(' ').next().unwrap().to_string());
                        }
                        Err(e) => failed.lock().unwrap().push(e.to_string()),
                    }
                    asked.fetch_add(1, Ordering::SeqCst);
                    std::thread::sleep(Duration::from_millis(2));
                }
            })
        })
        .collect();
    station.conf("version=0.2.0\nready_after=400\n");
    std::thread::sleep(Duration::from_millis(100));
    station.signal(libc::SIGUSR2);
    let after = until(Duration::from_secs(10), "a new startedAt", || station.station_json().filter(|s| s["startedAt"] != first["startedAt"]));
    std::thread::sleep(Duration::from_millis(200));
    stop.store(true, Ordering::SeqCst);
    askers.into_iter().for_each(|t| t.join().unwrap());
    assert_eq!(after["pid"], station.pid(), "the pid stays");
    assert_eq!(after["version"], "0.2.0");
    let new = answered_by(station.mcp);
    assert_ne!(new, old);
    assert!(station.said(old, "got handover") && station.said(old, "exit"));
    assert!(!alive(old));
    // The old one was told only once the new one was ready.
    let log = station.log();
    let at = |pid: i32, what: &str| log.iter().find(|(_, p, w)| *p == pid && w.starts_with(what)).unwrap().0;
    assert!(at(new, "ready") <= at(old, "got handover"));
    assert!(failed.lock().unwrap().is_empty(), "connections not answered: {:?}", failed.lock().unwrap());
    assert!(asked.load(Ordering::SeqCst) > 50);
    let who = who.lock().unwrap();
    assert!(who.contains(&old.to_string()) && who.contains(&new.to_string()), "{who:?}");
    assert!(station.file("handoff-failed").is_none());
    station.signal(libc::SIGTERM);
    assert!(station.wait(Duration::from_secs(5)).success());
}

#[test]
fn a_handover_whose_new_node_is_never_ready_fails_and_the_old_one_serves_on() {
    let mut station = Station::new("handfail");
    station.start("ready=1500");
    let first = station.up();
    let old = answered_by(station.mcp);
    station.conf("ready=no\n");
    station.signal(libc::SIGUSR2);
    let why = until(Duration::from_secs(10), "handoff-failed", || station.file("handoff-failed"));
    assert!(why.contains("not ready"), "{why}");
    let new = *station.started().last().unwrap();
    assert_ne!(new, old);
    until(Duration::from_secs(5), "the new Node killed", || (!alive(new)).then_some(()));
    assert_eq!(station.station_json().unwrap(), first);
    assert_eq!(answered_by(station.mcp), old);
    assert_eq!(answered_by(station.admin), old);
    assert!(!station.said(old, "got handover"));
    // A later handover works.
    station.conf("");
    station.signal(libc::SIGUSR2);
    until(Duration::from_secs(10), "a new startedAt", || station.station_json().filter(|s| s["startedAt"] != first["startedAt"]));
    assert_ne!(answered_by(station.mcp), old);
    station.signal(libc::SIGTERM);
    assert!(station.wait(Duration::from_secs(5)).success());
}

#[test]
fn sigusr1_and_sighup_go_to_node_and_drained_is_written() {
    let mut station = Station::new("forward");
    station.start("drained=1500");
    station.up();
    let node = station.started()[0];
    station.signal(libc::SIGUSR1);
    until(Duration::from_secs(5), "run/drained", || station.file("drained").filter(|d| d == "idle\n"));
    assert!(station.said(node, "got drain"));
    station.signal(libc::SIGHUP);
    until(Duration::from_secs(5), "hup", || station.said(node, "got hup").then_some(()));
    // Nobody stopped it: drained is taken back.
    until(Duration::from_secs(5), "run/drained gone", || station.file("drained").is_none().then_some(()));
    assert!(station.launcher.as_mut().unwrap().try_wait().unwrap().is_none());
    assert_eq!(answered_by(station.admin), node);
    station.signal(libc::SIGINT);
    assert!(station.wait(Duration::from_secs(5)).success());
    assert!(station.said(node, "got stop"));
}

#[test]
fn sigterm_during_a_handover_stops_both() {
    let mut station = Station::new("stopboth");
    station.start("");
    station.up();
    station.conf("ready=no\n");
    station.signal(libc::SIGUSR2);
    let both = until(Duration::from_secs(5), "the second Node", || Some(station.started()).filter(|s| s.len() == 2));
    std::thread::sleep(Duration::from_millis(300));
    let t = Instant::now();
    station.signal(libc::SIGTERM);
    assert!(station.wait(Duration::from_secs(5)).success());
    assert!(t.elapsed() < Duration::from_secs(3));
    for pid in both {
        assert!(station.said(pid, "got stop"), "{pid}");
        assert!(!alive(pid));
    }
}

#[test]
fn a_crashed_node_is_started_again_with_backoff() {
    let mut station = Station::new("crash");
    station.conf("crash_after=100\n");
    station.start("backoff=300");
    station.up();
    // Started, crashed, again after 300, 600, 1200 ms.
    let log = until(Duration::from_secs(10), "four starts", || Some(station.log()).filter(|l| l.iter().filter(|e| e.2.starts_with("start")).count() >= 4));
    station.conf("");
    let crashes: Vec<u64> = log.iter().filter(|e| e.2 == "crash").map(|e| e.0).collect();
    let starts: Vec<u64> = log.iter().filter(|e| e.2.starts_with("start")).map(|e| e.0).collect();
    for (i, expected) in [300u64, 600, 1200].into_iter().enumerate() {
        let gap = starts[i + 1] - crashes[i];
        // Wall-clock times (the log's) may be slewed against the launcher's monotonic clock: some leeway below.
        assert!(gap * 100 >= expected * 85 && gap < expected + 700, "restart {i}: {gap} ms, expected about {expected}");
    }
    // The launcher stays; a Node that does not crash serves again.
    let pid = station.pid();
    until(Duration::from_secs(10), "a Node that stays", || {
        let node = *station.started().last()?;
        (station.said(node, "ready") && !station.said(node, "crash") && ask(station.mcp).ok()? == format!("{node} mcp")).then_some(())
    });
    assert_eq!(station.station_json().unwrap()["pid"], pid);
    station.signal(libc::SIGTERM);
    assert!(station.wait(Duration::from_secs(5)).success());
}

#[test]
fn five_starts_in_a_row_that_fail_and_the_launcher_gives_up() {
    let mut station = Station::new("giveup");
    station.conf("start=crash\n");
    station.start("backoff=100");
    while station.wait(Duration::from_secs(15)).code() == Some(1) && station.port_was_taken() {
        let _ = std::fs::remove_file(station.dir.join("launcher.log"));
        station.new_ports();
        station.start("backoff=100");
    }
    assert_eq!(station.launcher.as_mut().unwrap().try_wait().unwrap().and_then(|s| s.code()), Some(1));
    assert_eq!(station.started().len(), 5);
    assert!(station.station_json().is_none());
}

/// Kills the shell of with_parent's test when it panics (the launcher then sees its parent gone).
struct Shell(Child);

impl Drop for Shell {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[test]
fn with_parent_it_stops_once_the_parent_is_gone() {
    let mut station = Station::new("parent");
    // A shell starts the launcher in the background, says its pid, then waits (as sleep, the same process).
    let start = |station: &Station| {
        let log = station.dir.join("launcher.log");
        let args = station.run_args().iter().map(|a| format!("'{a}'")).collect::<Vec<_>>().join(" ");
        let script = format!("\"$0\" {args} --with-parent >/dev/null 2>>'{}' & echo $!; exec sleep 60", log.display());
        let mut shell = spawn(
            Command::new("/bin/sh")
                .args(["-c", &script, LAUNCHER])
                .env("STILLFAIL_NODE", node())
                .env("STILLFAIL_LAUNCHER_TIMES", "parent=200")
                .env_remove("STILLFAIL_DATA")
                .env_remove("EMBER_DATA")
                .env_remove("STILLFAIL_CONFIG")
                .env_remove("EMBER_CONFIG")
                .stdout(Stdio::piped()),
        );
        let mut line = String::new();
        BufReader::new(shell.stdout.take().unwrap()).read_line(&mut line).unwrap();
        (Shell(shell), line.trim().parse::<i32>().unwrap())
    };
    let (mut shell, mut launcher) = start(&station);
    let mut said = None;
    for _ in 0..3 {
        said = until(Duration::from_secs(10), "station.json or an exit", || match station.station_json() {
            Some(said) => Some(Some(said)),
            // Ended, the launcher stays a zombie of the shell's sleep: its log says why.
            None => station.port_was_taken().then_some(None),
        });
        if said.is_some() || !station.port_was_taken() {
            break;
        }
        let _ = std::fs::remove_file(station.dir.join("launcher.log"));
        station.new_ports();
        drop(shell);
        (shell, launcher) = start(&station);
    }
    assert_eq!(said.expect("station.json")["pid"], launcher);
    let node = station.started()[0];
    // Still there while the parent is.
    std::thread::sleep(Duration::from_millis(600));
    assert!(alive(launcher));
    drop(shell);
    until(Duration::from_secs(5), "the launcher to end", || (!alive(launcher)).then_some(()));
    assert!(station.said(node, "got stop"));
    until(Duration::from_secs(5), "Node to end", || (!alive(node)).then_some(()));
}
