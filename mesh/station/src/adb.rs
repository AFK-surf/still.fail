//! Phones lent to this station's agents (docs/adb-share.md): a phone offers its adbd over its member link, and the
//! station reaches it at `127.0.0.1:<port>`, a listener of its own whose every TCP connection is a stream it opens on
//! the phone's connection (the phone's core takes it on to adbd). `adb connect` as the offer comes, `adb disconnect`
//! as it goes; `adb pair` through the phone's pairing port when its person types the code. The agents read who lent
//! what with the app's `adb_devices` tool (`register`).

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Weak;

use sha2::{Digest, Sha256};
use tokio::io::AsyncWriteExt;
use tokio::net::{TcpListener, TcpStream};

use super::*;

/// Where a phone's port is looked for first: the same phone gets the same one while it is free, so what an agent
/// wrote down of it (`adb -s 127.0.0.1:37xxx`) holds across offers.
const PORTS: std::ops::Range<u16> = 37000..38000;
/// How long the phone has to take a tunnel stream and reach its adbd.
const TUNNEL_OPEN: Duration = Duration::from_secs(10);
/// How long adb has to answer: a look at its state, and what reaches the phone (`connect`, `pair`, `shell`).
const ADB_QUICK: Duration = Duration::from_secs(5);
const ADB_TIMEOUT: Duration = Duration::from_secs(30);
/// How long a phone whose offer ended is kept for another offer of it (the pairing port opened, a new link): its port
/// and what adb holds of it stay.
const GRACE: Duration = Duration::from_secs(5);
/// How long a connected phone's state is looked at before it is taken as it is (adb says `offline` a moment first).
const SETTLE: Duration = Duration::from_secs(6);

/// The phones offered now, by whose and which (`key`).
#[derive(Default)]
pub struct Shares(Mutex<HashMap<String, Arc<Share>>>);

/// One phone, as its latest offer has it.
pub struct Share {
    port: u16,
    owner: Viewer,
    /// What the phone says it is: `device`, `android`, `package`; `adbd` (Wireless debugging is on) and `pair` (its
    /// pairing port is open).
    info: Mutex<Value>,
    /// The connection its latest offer came on: where its tunnels go.
    conn: Mutex<Connection>,
    /// Which offer it is (`offer`): one that ended after another came does not take the phone away.
    offer: std::sync::atomic::AtomicU64,
    /// How the station's adb holds the phone (`{adb, message}`), as the offer's stream is told.
    state: tokio::sync::watch::Sender<Value>,
    /// Why the phone last turned a tunnel down (its adbd not there, say): what adb not getting in is put down to.
    refused: Mutex<Option<String>>,
    listener: tokio::task::AbortHandle,
}

impl Share {
    fn serial(&self) -> String {
        format!("127.0.0.1:{}", self.port)
    }

    fn set(&self, adb: &str, message: impl Into<String>) {
        let message: String = message.into();
        self.state.send_replace(json!({ "serial": self.serial(), "adb": adb, "message": message.trim() }));
    }

    /// What the agents are told of it (`adb_devices`).
    fn listed(&self) -> Value {
        let info = self.info.lock().unwrap().clone();
        let state = self.state.borrow().clone();
        json!({
            "serial": self.serial(),
            "device": info["device"],
            "android": info["android"],
            "owner": { "name": self.owner.name, "email": self.owner.email },
            "adb": state["adb"],
            "message": state["message"],
        })
    }
}

static NEXT_OFFER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

/// Lets the app's `adb_devices` tool list the phones offered here.
pub fn register(station: &Arc<Station>) {
    let station = Arc::downgrade(station);
    stillfail_app::adb::register(Arc::new(move || {
        let Some(station) = station.upgrade() else { return Vec::new() };
        let shares: Vec<Arc<Share>> = station.adb.0.lock().unwrap().values().cloned().collect();
        shares.iter().map(|s| s.listed()).collect()
    }));
}

/// Which phone of whose an offer or ask is about: the phone's device key as it says (`phone`; its link may be on one of
/// its other keys, one per relay), else the connection's.
fn key(viewer: &Viewer, conn: &Connection, ask: &Value) -> String {
    let phone = ask["phone"].as_str().filter(|p| p.len() == 64 && p.chars().all(|c| c.is_ascii_hexdigit()));
    format!("{}/{}", viewer.sub, phone.map_or_else(|| hex::encode(conn.remote_id().as_bytes()), str::to_string))
}

/// A stream whose head says `"adb"`: an offer, held as long as the stream is (its span is its opening, as an event
/// stream's), or an ask about the phone's offer.
pub async fn answer(station: &Arc<Station>, conn: &Connection, viewer: &Viewer, head: &Value, send: &mut SendStream, outcome: &mut Outcome, traced: &mut Traced<'_>) -> Result<()> {
    let ask = &head["adb"];
    let device = key(viewer, conn, ask);
    let reply = async |send: &mut SendStream, outcome: &mut Outcome, status: u16, message: String| -> Result<()> {
        outcome.status = status;
        write_line(send, &json!({ "status": status, "headers": { "content-type": "application/json" } })).await?;
        send.write_all(json!({ "message": message }).to_string().as_bytes()).await?;
        send.finish()?;
        Ok(())
    };
    match ask["op"].as_str() {
        Some("share") => offer(station, conn, viewer, device, ask, send, outcome, traced).await,
        Some(op @ ("pair" | "grant")) => {
            let share = station.adb.0.lock().unwrap().get(&device).cloned();
            let Some(share) = share else { return reply(send, outcome, 409, "这台手机没有在共享调试".into()).await };
            let done = if op == "pair" { pair(&share, ask["code"].as_str().unwrap_or_default()).await } else { grant(&share).await };
            info!(email = %viewer.email, op, done = ?done.as_ref().map_err(|e| e.to_string()), "adb asked");
            match done {
                Ok(message) => reply(send, outcome, 200, message).await,
                Err(error) => reply(send, outcome, 422, error.to_string()).await,
            }
        }
        _ => reply(send, outcome, 400, "不认识的 adb 请求".into()).await,
    }
}

/// An offer: the phone in `shares` (its listener up), adb told, and how adb holds it said down the stream until the
/// phone stops it, its connection goes, or the station is removed. A later offer from the phone takes this one's place.
#[allow(clippy::too_many_arguments)]
async fn offer(station: &Arc<Station>, conn: &Connection, viewer: &Viewer, device: String, ask: &Value, send: &mut SendStream, outcome: &mut Outcome, traced: &mut Traced<'_>) -> Result<()> {
    let info = json!({
        "device": text(&ask["device"], 80),
        "android": text(&ask["android"], 20),
        "package": ask["package"].as_str().filter(|p| package(p)).unwrap_or_default(),
        "adbd": ask["adbd"].as_bool().unwrap_or(true),
        "pair": ask["pair"].as_bool().unwrap_or(false),
    });
    let number = NEXT_OFFER.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    let existing = station.adb.0.lock().unwrap().get(&device).cloned();
    let share = match existing {
        Some(share) => {
            *share.info.lock().unwrap() = info;
            *share.conn.lock().unwrap() = conn.clone();
            share.offer.store(number, std::sync::atomic::Ordering::SeqCst);
            share
        }
        None => {
            let listener = bind(&device).await?;
            let port = listener.local_addr()?.port();
            let share = Arc::new_cyclic(|me: &Weak<Share>| {
                let (state, _) = tokio::sync::watch::channel(json!({ "serial": format!("127.0.0.1:{port}"), "adb": "connecting", "message": "" }));
                Share {
                    port,
                    owner: viewer.clone(),
                    info: Mutex::new(info),
                    conn: Mutex::new(conn.clone()),
                    offer: std::sync::atomic::AtomicU64::new(number),
                    state,
                    refused: Mutex::new(None),
                    listener: tokio::spawn(listen(listener, me.clone())).abort_handle(),
                }
            });
            station.adb.0.lock().unwrap().insert(device.clone(), share.clone());
            info!(email = %viewer.email, port, "phone offered for adb");
            share
        }
    };
    outcome.status = 200;
    write_line(send, &json!({ "status": 200, "headers": { "content-type": "application/x-ndjson" } })).await?;
    traced.end(outcome, true, None);
    tokio::spawn(connect(share.clone()));
    let mut state = share.state.subscribe();
    state.mark_changed();
    let ended = loop {
        tokio::select! {
            changed = state.changed() => {
                if changed.is_err() { break "gone" }
                let line = state.borrow_and_update().clone();
                if write_line(send, &line).await.is_err() { break "stream" }
            }
            _ = send.stopped() => break "stopped",
            _ = conn.closed() => break "closed",
            _ = tokio::time::sleep(Duration::from_secs(5)) => if station.removed() { break "removed" },
        }
    };
    // Only the latest offer takes the phone away (one that came on another link has it now), and only if no other
    // comes a moment after.
    if ended != "removed" {
        tokio::time::sleep(GRACE).await;
    }
    let latest = share.offer.load(std::sync::atomic::Ordering::SeqCst) == number;
    if latest {
        let removed = {
            let mut shares = station.adb.0.lock().unwrap();
            let current = shares.get(&device).is_some_and(|s| Arc::ptr_eq(s, &share));
            if current { shares.remove(&device) } else { None }
        };
        if let Some(share) = removed {
            share.listener.abort();
            info!(email = %viewer.email, port = share.port, ended, "phone no longer offered for adb");
            if let Some(adb) = adb_path() {
                run(&adb, &["disconnect", &share.serial()], ADB_QUICK).await.ok();
            }
        }
    }
    send.finish().ok();
    Ok(())
}

/// Each TCP connection to the phone's port, a tunnel on its offer's connection.
async fn listen(listener: TcpListener, share: Weak<Share>) {
    while let Ok((tcp, _)) = listener.accept().await {
        let Some(share) = share.upgrade() else { return };
        let conn = share.conn.lock().unwrap().clone();
        tokio::spawn(async move {
            if let Err(error) = tunnel(&conn, "connect", tcp).await {
                info!(%error, "adb tunnel ended");
                *share.refused.lock().unwrap() = Some(error.to_string());
            }
        });
    }
}

/// A port of the phone's own: its usual one if free, else any.
async fn bind(device: &str) -> Result<TcpListener> {
    let hash = Sha256::digest(device.as_bytes());
    let usual = PORTS.start + u16::from_be_bytes([hash[0], hash[1]]) % (PORTS.end - PORTS.start);
    // An offer from before (the station handed over to a new one) may hold it a moment yet.
    for _ in 0..5 {
        if let Ok(listener) = TcpListener::bind(("127.0.0.1", usual)).await {
            return Ok(listener);
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
    Ok(TcpListener::bind(("127.0.0.1", 0)).await?)
}

/// A stream to the phone for `tcp`: `{"tunnel": kind}`, the phone's answer once it reached adbd (or why not), then the
/// bytes both ways until either side ends.
async fn tunnel(conn: &Connection, kind: &str, tcp: TcpStream) -> Result<()> {
    let (mut send, mut recv) = tokio::time::timeout(TUNNEL_OPEN, conn.open_bi()).await.context("the phone did not take the tunnel")??;
    write_line(&mut send, &json!({ "tunnel": kind })).await?;
    let mut carry = Vec::new();
    let answer = tokio::time::timeout(TUNNEL_OPEN, read_line(&mut recv, &mut carry)).await.context("the phone did not answer")??.ok_or_else(|| anyhow!("the phone closed the tunnel"))?;
    if let Some(error) = answer["error"].as_str() {
        bail!("the phone did not reach adb: {error}");
    }
    let (mut from_tcp, mut to_tcp) = tcp.into_split();
    let up = async {
        let copied = tokio::io::copy(&mut from_tcp, &mut send).await;
        send.finish().ok();
        copied
    };
    let down = async {
        to_tcp.write_all(&carry).await?;
        let copied = tokio::io::copy(&mut recv, &mut to_tcp).await;
        to_tcp.shutdown().await.ok();
        copied
    };
    let (up, down) = tokio::join!(up, down);
    up?;
    down?;
    Ok(())
}

/// `adb connect` to the phone (unless adb holds it already), and how adb holds it then.
async fn connect(share: Arc<Share>) {
    let Some(adb) = adb_path() else {
        return share.set("missing", "这台 station 上没有 adb：装上 Android platform-tools（macOS：brew install android-platform-tools），再重新共享");
    };
    let serial = share.serial();
    // Nothing to reach: adb is not left trying to (it would, a few times a second).
    if share.info.lock().unwrap()["adbd"] == false {
        run(&adb, &["disconnect", &serial], ADB_QUICK).await.ok();
        return share.set("off", "手机上的无线调试没开");
    }
    // Held already (another offer: the pairing port opened, a new link): it stays so.
    if run(&adb, &["-s", &serial, "get-state"], ADB_QUICK).await.unwrap_or_default() == "device" {
        return share.set("connected", "");
    }
    share.set("connecting", "");
    *share.refused.lock().unwrap() = None;
    // What adb kept of a tunnel gone (the phone's adbd on another port now) goes first.
    run(&adb, &["disconnect", &serial], ADB_QUICK).await.ok();
    if let Err(error) = run(&adb, &["connect", &serial], ADB_TIMEOUT).await {
        return share.set("failed", error.to_string());
    }
    // adb says `connected to …` for a TLS port it is not paired with too; only its state says whether it got in.
    let started = Instant::now();
    let state = loop {
        let state = run(&adb, &["-s", &serial, "get-state"], ADB_QUICK).await.unwrap_or_default();
        if state == "device" || started.elapsed() >= SETTLE {
            break state;
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    };
    let refused = share.refused.lock().unwrap().take();
    match (state.as_str(), refused) {
        ("device", _) => share.set("connected", ""),
        ("unauthorized", _) => share.set("unauthorized", "手机上弹出了「允许 USB 调试吗？」，点允许"),
        (_, Some(why)) => share.set("failed", why),
        _ => share.set("unpaired", "这台 station 还没和手机配对"),
    }
}

/// `adb pair` through the phone's pairing port (open while its 使用配对码配对设备 dialog is), then connected anew.
async fn pair(share: &Arc<Share>, code: &str) -> Result<String> {
    let code: String = code.chars().filter(char::is_ascii_digit).collect();
    if code.len() != 6 {
        bail!("配对码是 6 位数字");
    }
    if share.info.lock().unwrap()["pair"] != true {
        bail!("手机上的配对窗口没开：在无线调试里点「使用配对码配对设备」");
    }
    let adb = adb_path().ok_or_else(|| anyhow!("这台 station 上没有 adb"))?;
    // A port for this pairing alone, its one connection the phone's pairing port.
    let listener = TcpListener::bind(("127.0.0.1", 0)).await?;
    let port = listener.local_addr()?.port();
    let conn = share.conn.lock().unwrap().clone();
    let tunnel = tokio::spawn(async move {
        let Ok(Ok((tcp, _))) = tokio::time::timeout(ADB_TIMEOUT, listener.accept()).await else { return };
        if let Err(error) = tunnel(&conn, "pair", tcp).await {
            info!(%error, "adb pairing tunnel ended");
        }
    });
    let said = run(&adb, &["pair", &format!("127.0.0.1:{port}"), &code], ADB_TIMEOUT).await;
    tunnel.abort();
    let said = said?;
    if !said.contains("Successfully paired") {
        bail!("没配上：{said}");
    }
    tokio::spawn(connect(share.clone()));
    Ok("配对好了".into())
}

/// Lets the app turn Wireless debugging on itself from now on (`WRITE_SECURE_SETTINGS`), as its person asked.
async fn grant(share: &Arc<Share>) -> Result<String> {
    let package = share.info.lock().unwrap()["package"].as_str().unwrap_or_default().to_string();
    if package.is_empty() {
        bail!("手机没说 app 的包名");
    }
    let adb = adb_path().ok_or_else(|| anyhow!("这台 station 上没有 adb"))?;
    let said = run(&adb, &["-s", &share.serial(), "shell", "pm", "grant", &package, "android.permission.WRITE_SECURE_SETTINGS"], ADB_TIMEOUT).await?;
    // Quiet is granted; a refusal says why (MIUI and ColorOS want 「USB 调试（安全设置）」 on).
    if !said.is_empty() {
        bail!("没授权上：{said}");
    }
    Ok("以后 app 可以自己打开无线调试了".into())
}

/// The machine's adb: on `PATH`, else the Android SDK's (where Android Studio puts it, whose adb server is likely the
/// one running: another version's client would restart it), else a package manager's (launchd gives the station a short
/// `PATH`).
fn adb_path() -> Option<PathBuf> {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    let path = std::env::var_os("PATH").map(|p| std::env::split_paths(&p).map(|d| d.join("adb")).collect::<Vec<_>>()).unwrap_or_default();
    let sdk = ["ANDROID_HOME", "ANDROID_SDK_ROOT"].iter().filter_map(std::env::var_os).map(|d| PathBuf::from(d).join("platform-tools/adb"));
    let in_home = home.into_iter().flat_map(|h| [h.join("Library/Android/sdk/platform-tools/adb"), h.join("Android/Sdk/platform-tools/adb")]);
    let usual = ["/opt/homebrew/bin/adb", "/usr/local/bin/adb", "/usr/bin/adb"].iter().map(PathBuf::from);
    path.into_iter().chain(sdk).chain(in_home).chain(usual).find(|p| p.is_file())
}

/// What adb says to `args` (out and err), within `timeout`.
async fn run(adb: &Path, args: &[&str], timeout: Duration) -> Result<String> {
    let mut command = tokio::process::Command::new(adb);
    command.args(args).stdin(std::process::Stdio::null()).kill_on_drop(true);
    let output = tokio::time::timeout(timeout, command.output()).await.context("adb did not answer in time")??;
    let mut said = String::from_utf8_lossy(&output.stdout).into_owned();
    said.push_str(&String::from_utf8_lossy(&output.stderr));
    Ok(said.trim().to_string())
}

/// A word the phone says of itself, short and on one line.
fn text(value: &Value, max: usize) -> String {
    value.as_str().unwrap_or_default().chars().filter(|c| !c.is_control()).take(max).collect()
}

/// An Android package name, as `pm grant` takes it: nothing a shell would read otherwise.
fn package(name: &str) -> bool {
    !name.is_empty() && name.len() <= 200 && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '_')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn takes_only_plain_package_names() {
        assert!(package("fail.still.android.beta"));
        assert!(!package("fail.still.android; rm -rf /"));
        assert!(!package(""));
    }

    #[tokio::test]
    async fn gives_a_phone_its_usual_port_while_it_is_free() {
        let first = bind("ab12").await.unwrap();
        let port = first.local_addr().unwrap().port();
        assert!(PORTS.contains(&port));
        drop(first);
        assert_eq!(bind("ab12").await.unwrap().local_addr().unwrap().port(), port);
    }

    #[test]
    fn says_of_itself_only_one_short_line() {
        assert_eq!(text(&json!("Pixel\n8"), 80), "Pixel8");
        assert_eq!(text(&json!("x".repeat(100)), 80).len(), 80);
        assert_eq!(text(&json!(3), 80), "");
    }
}
