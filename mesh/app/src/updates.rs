//! Which versions this station and the machine's runtimes (Claude Code, Codex) are, whether newer ones are out, and
//! updating them from the pages.
//! - The station: its release says its version in BUILD (scripts/station-bundle.sh: `0.1.<commits>`, as the apps are
//!   numbered); the latest is what still.fail cloud serves as releases/station.json (scripts/release.sh). It is updated as
//!   `stillfail update` does, by the cloud's installer (cloud/src/install.ts), run apart from the station (its own
//!   process group, not waited for): the installer hands the running station over to the new release, or drains and
//!   restarts it, so this process is gone (or another binary) by the time it ends. Only a release installed by that
//!   installer (<data>/app) is: the desktop app's station comes with the desktop app, a clone's with the clone.
//! - Claude Code and Codex: `--version`, and the latest their npm packages say. Updated the way each was installed
//!   (the path of the command on the station's PATH says): `claude update`, npm, or Homebrew. Running agents go on with
//!   what they started with; the next process starts the new one.

use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use stillfail_shapes::SoftwareVersion;
use serde_json::Value;
use tokio::process::Command;
use tokio::sync::watch;
use tracing::{info, warn};

use crate::machine_logins::Env;
use crate::store::now_ms;

/// How often what is out is read again (and the pages' "check" reads it at once).
const EVERY: Duration = Duration::from_secs(6 * 3600);
/// How long an update of a runtime may take.
const RUNTIME_LIMIT: Duration = Duration::from_secs(10 * 60);
/// How long the station's installer is waited for: a drain alone may take 10 minutes (install.ts).
const STATION_LIMIT_MS: i64 = 20 * 60_000;

/// The station's version as its release says it (`0.1.<n>`); None for a build that is not a release (a clone).
pub fn station_version(app: &Path) -> Option<String> {
    let build = std::fs::read_to_string(app.join("BUILD")).ok()?;
    let build = build.trim();
    (!build.is_empty() && build.chars().all(|c| c.is_ascii_digit())).then(|| format!("0.1.{build}"))
}

/// The release directory a station's page (dist/admin) is in.
pub fn app_of(ui: &Path) -> PathBuf {
    ui.parent().and_then(Path::parent).map(Path::to_path_buf).unwrap_or_else(|| ui.to_path_buf())
}

/// Whether `latest` is a newer version than `current`, number by number ("2.1.10" is newer than "2.1.9").
pub fn newer(current: &str, latest: &str) -> bool {
    let parts = |v: &str| v.split(|c: char| !c.is_ascii_digit()).filter(|p| !p.is_empty()).map(|p| p.parse::<u64>().unwrap_or(0)).collect::<Vec<_>>();
    parts(latest) > parts(current)
}

/// The first dotted version in what a command said ("2.1.284 (Claude Code)", "codex-cli 0.46.0").
fn version_in(text: &str) -> Option<String> {
    text.split(|c: char| c.is_whitespace() || c == '(' || c == ')' || c == ',')
        .map(|w| w.trim_start_matches('v'))
        .find(|w| w.contains('.') && w.split('.').all(|p| !p.is_empty() && p.chars().next().is_some_and(|c| c.is_ascii_digit())))
        .map(String::from)
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Kind {
    Station,
    Claude,
    Codex,
}

impl Kind {
    const ALL: [Kind; 3] = [Kind::Station, Kind::Claude, Kind::Codex];

    fn id(self) -> &'static str {
        match self {
            Kind::Station => "station",
            Kind::Claude => "claude",
            Kind::Codex => "codex",
        }
    }

    fn name(self) -> &'static str {
        match self {
            Kind::Station => "still.fail station",
            Kind::Claude => "Claude Code",
            Kind::Codex => "Codex",
        }
    }

    fn command(self) -> &'static str {
        match self {
            Kind::Station => "stillfail-station",
            Kind::Claude => "claude",
            Kind::Codex => "codex",
        }
    }

    /// Where the latest is said: the npm registry's latest of the runtime's package.
    fn package(self) -> &'static str {
        match self {
            Kind::Station => "",
            Kind::Claude => "@anthropic-ai/claude-code",
            Kind::Codex => "@openai/codex",
        }
    }

    fn of(id: &str) -> Option<Kind> {
        Kind::ALL.into_iter().find(|k| k.id() == id)
    }
}

/// How an update is done: a program and its arguments, in words for the pages.
#[derive(Clone, Debug, PartialEq)]
struct How {
    program: PathBuf,
    args: Vec<String>,
}

impl How {
    fn new(program: impl Into<PathBuf>, args: &[&str]) -> How {
        How { program: program.into(), args: args.iter().map(|a| a.to_string()).collect() }
    }
}

#[derive(Clone, Debug, Default)]
struct Item {
    installed: bool,
    version: Option<String>,
    latest: Option<String>,
    how: Option<How>,
    /// Why it cannot be updated from here.
    note: Option<String>,
    /// When an update started, while it runs.
    updating: Option<i64>,
    failed: Option<String>,
}

/// The versions, read now and then; `changes` moves when they differ from the last reading.
pub struct Updates {
    app: PathBuf,
    data: PathBuf,
    env: Env,
    origin: Box<dyn Fn() -> Option<String> + Send + Sync>,
    items: Mutex<[Item; 3]>,
    checked: Mutex<(Option<i64>, bool)>,
    changes: watch::Sender<u64>,
}

impl Updates {
    /// `app`: the release this station runs from; `origin`: the still.fail cloud it is in, when it is.
    pub fn new(app: PathBuf, data: PathBuf, env: Env, origin: Box<dyn Fn() -> Option<String> + Send + Sync>) -> Arc<Updates> {
        let items = Default::default();
        Arc::new(Updates { app, data, env, origin, items: Mutex::new(items), checked: Mutex::new((None, false)), changes: watch::channel(0).0 })
    }

    /// Reads them at once and every few hours after.
    pub fn start(self: &Arc<Self>) {
        let me = Arc::downgrade(self);
        tokio::spawn(async move {
            loop {
                let Some(updates) = me.upgrade() else { return };
                updates.check().await;
                drop(updates);
                tokio::time::sleep(EVERY).await;
            }
        });
    }

    pub fn changes(&self) -> watch::Receiver<u64> {
        self.changes.subscribe()
    }

    fn changed(&self) {
        self.changes.send_modify(|n| *n += 1);
    }

    fn set(&self, kind: Kind, f: impl FnOnce(&mut Item)) {
        f(&mut self.items.lock().unwrap()[kind as usize]);
        self.changed();
    }

    /// What the pages show, one line each.
    pub fn get(&self) -> Vec<SoftwareVersion> {
        let checked = self.checked.lock().unwrap().0;
        let items = self.items.lock().unwrap().clone();
        Kind::ALL
            .into_iter()
            .zip(items)
            .map(|(kind, item)| SoftwareVersion {
                id: kind.id().into(),
                name: kind.name().into(),
                installed: item.installed,
                newer: matches!((&item.version, &item.latest), (Some(v), Some(l)) if newer(v, l)),
                updatable: item.how.is_some() || (kind == Kind::Station && item.note.is_none() && item.version.is_some()),
                version: item.version,
                latest: item.latest,
                note: item.note,
                state: if item.updating.is_some() { "updating" } else if item.failed.is_some() { "failed" } else { "idle" }.into(),
                message: item.failed,
                checked_at: checked,
            })
            .collect()
    }

    /// Reads every version and what is out, now (once at a time).
    pub async fn check(&self) {
        {
            let mut checked = self.checked.lock().unwrap();
            if checked.1 {
                return;
            }
            checked.1 = true;
        }
        let (station, claude, codex) = tokio::join!(self.read_station(), self.read_runtime(Kind::Claude), self.read_runtime(Kind::Codex));
        {
            let mut items = self.items.lock().unwrap();
            for (kind, read) in [(Kind::Station, station), (Kind::Claude, claude), (Kind::Codex, codex)] {
                let item = &mut items[kind as usize];
                // One that is updating keeps what it was until it is done.
                if item.updating.is_none() {
                    *item = Item { failed: item.failed.take(), ..read };
                }
            }
        }
        *self.checked.lock().unwrap() = (Some(now_ms()), false);
        self.changed();
    }

    async fn read_station(&self) -> Item {
        let version = station_version(&self.app);
        let installed = |p: &Path| std::fs::canonicalize(p).ok();
        let note = if installed(&self.app).is_some_and(|a| Some(a) == installed(&self.data.join("app"))) {
            None
        } else if self.app.to_string_lossy().contains(".app/Contents") {
            Some("随 still.fail 桌面端一起更新".to_string())
        } else {
            Some("不是用安装脚本装的，没法在这里更新".to_string())
        };
        let origin = (self.origin)();
        let note = note.or_else(|| origin.is_none().then(|| "还没加入 workspace，无从更新".to_string()));
        let latest = match &origin {
            Some(origin) => match fetch_json(&format!("{origin}/releases/station.json")).await {
                Ok(said) => said.get("version").and_then(Value::as_str).map(String::from),
                Err(e) => {
                    warn!(error = %e, "the station's latest release not read");
                    None
                }
            },
            None => None,
        };
        Item { installed: true, version, latest, note, ..Default::default() }
    }

    async fn read_runtime(&self, kind: Kind) -> Item {
        let found = find_command(kind.command(), &self.env);
        let version = match &found {
            Some(found) => match run(found, &["--version"], &self.env, Duration::from_secs(20)).await {
                Ok((true, out)) => version_in(&out),
                _ => None,
            },
            None => None,
        };
        let latest = match fetch_json(&format!("https://registry.npmjs.org/{}/latest", kind.package())).await {
            Ok(said) => said.get("version").and_then(Value::as_str).map(String::from),
            Err(e) => {
                warn!(runtime = kind.id(), error = %e, "the runtime's latest version not read");
                None
            }
        };
        let how = match &found {
            Some(found) => how_to_update(kind, found, &self.env),
            None => how_to_install(kind, &self.env),
        };
        let (how, note) = match how {
            Ok(how) => (Some(how), None),
            Err(note) => (None, Some(note)),
        };
        Item { installed: found.is_some(), version, latest, how, note, ..Default::default() }
    }

    /// Updates one (`station`, `claude`, `codex`), or installs a runtime the machine has not: answers once it has started; how it goes shows in `get`.
    pub fn update(self: &Arc<Self>, id: &str) -> Result<()> {
        let kind = Kind::of(id).ok_or_else(|| anyhow!("没有 {id} 这一项"))?;
        let item = self.items.lock().unwrap()[kind as usize].clone();
        if item.updating.is_some() {
            bail!("{} 正在更新", kind.name());
        }
        if let Some(note) = &item.note {
            bail!("{}：{note}", kind.name());
        }
        if kind == Kind::Station {
            return self.update_station();
        }
        let how = item.how.ok_or_else(|| anyhow!("{} 没法在这里更新", kind.name()))?;
        self.set(kind, |i| {
            i.updating = Some(now_ms());
            i.failed = None;
        });
        let me = self.clone();
        tokio::spawn(async move {
            info!(runtime = kind.id(), program = %how.program.display(), args = ?how.args, "updating or installing a runtime");
            let args: Vec<&str> = how.args.iter().map(String::as_str).collect();
            let failed = match tokio::time::timeout(RUNTIME_LIMIT, run(&how.program, &args, &me.env, RUNTIME_LIMIT)).await {
                Ok(Ok((true, _))) => None,
                Ok(Ok((false, said))) => Some(tail(&said)),
                Ok(Err(e)) => Some(e.to_string()),
                Err(_) => Some("超过 10 分钟还没有完成".to_string()),
            };
            if let Some(failed) = &failed {
                warn!(runtime = kind.id(), failed, "the runtime not updated");
            }
            let read = me.read_runtime(kind).await;
            me.set(kind, |i| *i = Item { failed, ..read });
        });
        Ok(())
    }

    /// Runs the cloud's installer apart from the station, as `stillfail update` does; it says how it ended in
    /// run/update.exit (and what it said in run/update.log), read here while this process is still the one running.
    fn update_station(self: &Arc<Self>) -> Result<()> {
        let origin = (self.origin)().ok_or_else(|| anyhow!("还没加入 workspace，无从更新"))?;
        let run_dir = self.data.join("run");
        std::fs::create_dir_all(&run_dir)?;
        let exit = run_dir.join("update.exit");
        let _ = std::fs::remove_file(&exit);
        // In the background of a shell that ends at once: the installer is nobody's child here, and outlives both a
        // handover (this process becomes another binary) and a restart (the service's processes are stopped).
        let script = r#"( curl -fsSL "$1/install.sh" | sh; echo $? > "$2/update.exit" ) > "$2/update.log" 2>&1 < /dev/null &"#;
        let status = std::process::Command::new("/bin/sh")
            .args(["-c", script, "sh", &origin, &run_dir.to_string_lossy()])
            .env_clear()
            .envs(&self.env)
            // Under both names: the cloud's installer from before the rename reads the old one.
            .envs(crate::former::both("DATA").map(|name| (name, self.data.clone())))
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .process_group(0)
            .status()?;
        if !status.success() {
            bail!("没能开始更新");
        }
        info!(origin, "updating the station");
        let started = now_ms();
        self.set(Kind::Station, |i| {
            i.updating = Some(started);
            i.failed = None;
        });
        let me = Arc::downgrade(self);
        let log = run_dir.join("update.log");
        tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_secs(2)).await;
                let Some(me) = me.upgrade() else { return };
                let failed = match std::fs::read_to_string(&exit) {
                    Ok(code) if code.trim() == "0" => None,
                    Ok(code) => Some(tail(&std::fs::read_to_string(&log).unwrap_or_else(|_| format!("安装脚本退出码 {}", code.trim())))),
                    Err(_) if now_ms() - started > STATION_LIMIT_MS => Some("安装脚本 20 分钟没有结束，看 ~/.stillfail/run/update.log".to_string()),
                    Err(_) => continue,
                };
                me.set(Kind::Station, |i| {
                    i.updating = None;
                    i.failed = failed;
                });
                me.check().await;
                return;
            }
        });
        Ok(())
    }
}

/// The last lines of what a command said, for the pages.
fn tail(said: &str) -> String {
    let lines: Vec<&str> = said.trim().lines().filter(|l| !l.trim().is_empty()).collect();
    let tail = lines[lines.len().saturating_sub(4)..].join("\n");
    if tail.is_empty() { "更新失败，没有输出".to_string() } else { tail.chars().rev().take(600).collect::<Vec<_>>().into_iter().rev().collect() }
}

async fn fetch_json(url: &str) -> Result<Value> {
    let http = reqwest::Client::builder().timeout(Duration::from_secs(15)).build()?;
    let response = http.get(url).header("user-agent", "stillfail-station").send().await?;
    if !response.status().is_success() {
        bail!("{url}: {}", response.status());
    }
    Ok(response.json().await?)
}

/// A command as the station's PATH finds it: where it was found (the link on PATH) and what that is.
#[derive(Clone, Debug)]
struct Found {
    on_path: PathBuf,
    real: PathBuf,
}

impl AsRef<Path> for Found {
    fn as_ref(&self) -> &Path {
        &self.on_path
    }
}

fn find_command(name: &str, env: &Env) -> Option<Found> {
    use std::os::unix::fs::PermissionsExt;
    let path = env.get("PATH")?;
    std::env::split_paths(path).map(|dir| dir.join(name)).find(|p| p.metadata().is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)).map(|on_path| Found {
        real: std::fs::canonicalize(&on_path).unwrap_or_else(|_| on_path.clone()),
        on_path,
    })
}

/// How a runtime installed as `found` is updated, or why it cannot be from here.
fn how_to_update(kind: Kind, found: &Found, env: &Env) -> Result<How, String> {
    let real = found.real.to_string_lossy();
    let brew = || find_command("brew", env).map(|b| b.on_path).ok_or_else(|| format!("{} 是用 Homebrew 装的，但 station 找不到 brew", kind.name()));
    let npm = || {
        // The npm beside the command (the same Node's), else the one on PATH.
        let beside = found.on_path.parent().map(|d| d.join("npm")).filter(|p| p.exists());
        beside.or_else(|| find_command("npm", env).map(|n| n.on_path)).ok_or_else(|| format!("{} 是用 npm 装的，但 station 找不到 npm", kind.name()))
    };
    let package = format!("{}@latest", kind.package());
    match kind {
        Kind::Station => Err(String::new()),
        Kind::Claude if real.contains("/Caskroom/") => Ok(How::new(brew()?, &["upgrade", "--cask", "claude-code"])),
        Kind::Claude if real.contains("/Cellar/") => Ok(How::new(brew()?, &["upgrade", "claude-code"])),
        // Its own updater: the native build (~/.local/share/claude) and npm's alike.
        Kind::Claude => Ok(How::new(&found.on_path, &["update"])),
        Kind::Codex if real.contains("/Caskroom/") => Ok(How::new(brew()?, &["upgrade", "--cask", "codex"])),
        Kind::Codex if real.contains("/Cellar/") => Ok(How::new(brew()?, &["upgrade", "codex"])),
        Kind::Codex if real.contains("/node_modules/") => Ok(How::new(npm()?, &["install", "-g", &package])),
        Kind::Codex => Err(format!("装在 {real}，不是 npm 或 Homebrew 装的，要在那台机器上自己更新")),
    }
}

/// How a runtime the machine has not is installed, or why it cannot be from here: Claude Code by its own installer
/// (into ~/.local/bin, on the station's PATH as install.ts sets it), Codex by npm, else Homebrew.
fn how_to_install(kind: Kind, env: &Env) -> Result<How, String> {
    match kind {
        Kind::Station => Err(String::new()),
        Kind::Claude => Ok(How::new("/bin/sh", &["-c", "curl -fsSL https://claude.ai/install.sh | bash"])),
        Kind::Codex => {
            if let Some(npm) = find_command("npm", env) {
                Ok(How::new(npm.on_path, &["install", "-g", "@openai/codex@latest"]))
            } else if let Some(brew) = find_command("brew", env) {
                Ok(How::new(brew.on_path, &["install", "--cask", "codex"]))
            } else {
                Err("这台机器上没有 npm 也没有 Homebrew：先装 Node（带 npm），再回来安装 Codex".to_string())
            }
        }
    }
}

/// Runs a command to its end: whether it succeeded, and what it said (stdout and stderr).
async fn run(program: impl AsRef<Path>, args: &[&str], env: &Env, timeout: Duration) -> Result<(bool, String)> {
    let mut cmd = Command::new(program.as_ref());
    cmd.args(args).env_clear().envs(env).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).kill_on_drop(true);
    // Out of any repository (npm and claude look around them) and in its own group (npm's children stop with it).
    cmd.current_dir(std::env::temp_dir()).process_group(0);
    let out = tokio::time::timeout(timeout, cmd.output()).await.map_err(|_| anyhow!("{} 没有及时结束", program.as_ref().display()))??;
    Ok((out.status.success(), format!("{}{}", String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr))))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_compare_number_by_number() {
        assert!(newer("2.1.9", "2.1.10"));
        assert!(!newer("2.1.10", "2.1.9"));
        assert!(!newer("0.1.1200", "0.1.1200"));
        assert!(newer("0.46.0", "0.47.0-alpha.1"));
    }

    #[test]
    fn a_version_is_read_from_what_the_command_says() {
        assert_eq!(version_in("2.1.284 (Claude Code)").as_deref(), Some("2.1.284"));
        assert_eq!(version_in("codex-cli 0.46.0\n").as_deref(), Some("0.46.0"));
        assert_eq!(version_in("nothing here"), None);
    }

    #[test]
    fn a_release_says_its_version_and_a_clone_none() {
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(station_version(dir.path()), None);
        std::fs::write(dir.path().join("BUILD"), "1234\n").unwrap();
        assert_eq!(station_version(dir.path()).as_deref(), Some("0.1.1234"));
        assert_eq!(app_of(&dir.path().join("dist").join("admin")), dir.path());
    }

    fn found(real: &str) -> Found {
        Found { on_path: PathBuf::from("/nowhere/bin/x"), real: PathBuf::from(real) }
    }

    #[test]
    fn each_runtime_is_updated_the_way_it_was_installed() {
        let dir = tempfile::tempdir().unwrap();
        for name in ["brew", "npm"] {
            let p = dir.path().join(name);
            std::fs::write(&p, "#!/bin/sh\n").unwrap();
            std::fs::set_permissions(&p, std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
        }
        let env: Env = [("PATH".to_string(), dir.path().display().to_string())].into();
        let (brew, npm) = (dir.path().join("brew"), dir.path().join("npm"));
        let native = how_to_update(Kind::Claude, &found("/Users/a/.local/share/claude/versions/2.1.284"), &env).unwrap();
        assert_eq!(native, How::new("/nowhere/bin/x", &["update"]));
        assert_eq!(how_to_update(Kind::Claude, &found("/opt/homebrew/Caskroom/claude-code/2.1.284/claude"), &env).unwrap(), How::new(&brew, &["upgrade", "--cask", "claude-code"]));
        assert_eq!(how_to_update(Kind::Codex, &found("/opt/homebrew/Cellar/codex/0.46.0/bin/codex"), &env).unwrap(), How::new(&brew, &["upgrade", "codex"]));
        let by_npm = how_to_update(Kind::Codex, &found("/Users/a/.nvm/versions/node/v24/lib/node_modules/@openai/codex/bin/codex.js"), &env).unwrap();
        assert_eq!(by_npm, How::new(&npm, &["install", "-g", "@openai/codex@latest"]));
        assert!(how_to_update(Kind::Codex, &found("/usr/local/bin/codex"), &env).unwrap_err().contains("自己更新"));
        assert_eq!(how_to_install(Kind::Codex, &env).unwrap(), How::new(&npm, &["install", "-g", "@openai/codex@latest"]));
        let bare: Env = [("PATH".to_string(), "/nowhere".to_string())].into();
        assert!(how_to_install(Kind::Codex, &bare).unwrap_err().contains("Node"));
        assert_eq!(how_to_install(Kind::Claude, &bare).unwrap().program, PathBuf::from("/bin/sh"));
    }
}
