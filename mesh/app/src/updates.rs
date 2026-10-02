//! Which versions this station and the machine's runtimes (Claude Code, Codex) are, whether newer ones are out, and
//! updating them from the pages.
//! - The station: its release says its version in BUILD (scripts/station-bundle.sh: `0.1.<commits>`, as the apps are
//!   numbered); the latest is what still.fail cloud serves as releases/station.json (scripts/release.sh), or on the test
//!   channel (`updateChannel: "beta"` in config.json; a station installed from the beta and not told otherwise is on it)
//!   releases/station-beta.json (release.sh --beta). Switched back from the beta, the stable release may be older than
//!   the beta that runs: then going back to it is offered (`downgrade`), only then, never as a newer version. It is updated as
//!   `stillfail update` does, by the cloud's installer (cloud/src/install.ts), run apart from the station (its own
//!   process group, not waited for): the installer hands the running station over to the new release, or drains and
//!   restarts it, so this process is gone (or another binary) by the time it ends. Only a release installed by that
//!   installer (<data>/app) is: the desktop app's station comes with the desktop app, a clone's with the clone.
//!   With `autoUpdate: true` in config.json (the 自动更新 switch) the station does so by itself when a reading finds a
//!   newer release of its channel (never going back from the beta, and a version it already tried, not again).
//! - Claude Code and Codex: `--version`, and the latest their npm packages say. Updated the way each was installed
//!   (the path of the command on the station's PATH says): `claude update`, npm, or Homebrew. Running agents go on with
//!   what they started with; the next process starts the new one.

use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use stillfail_shapes::SoftwareVersion;
use serde_json::Value;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command;
use tokio::sync::watch;
use tracing::{info, warn};

use crate::config::RawConfig;
use crate::machine_logins::Env;
use crate::settings::Settings;
use crate::store::now_ms;

/// How often what is out is read again (and the pages' "check" reads it at once).
const EVERY: Duration = Duration::from_secs(6 * 3600);
/// How often what is out is read while the station updates itself: a new release reaches it within ten minutes.
const AUTO_EVERY: Duration = Duration::from_secs(10 * 60);
/// How long an update of a runtime may take.
const RUNTIME_LIMIT: Duration = Duration::from_secs(10 * 60);
/// How long the station's installer is waited for: a drain alone may take 10 minutes (install.ts).
const STATION_LIMIT_MS: i64 = 20 * 60_000;
/// How long how an update of the station went is shown after it ended.
const DONE_SHOWN: Duration = Duration::from_secs(10 * 60);

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

/// Which releases a station is updated to: the stable ones, or the test channel's.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Channel {
    Stable,
    Beta,
}

impl Channel {
    pub fn id(self) -> &'static str {
        match self {
            Channel::Stable => "stable",
            Channel::Beta => "beta",
        }
    }

    pub fn of(id: &str) -> Option<Channel> {
        match id.trim() {
            "stable" => Some(Channel::Stable),
            "beta" => Some(Channel::Beta),
            _ => None,
        }
    }

    /// Where still.fail cloud says its latest (scripts/release.sh, cloud/src/install.ts).
    pub fn feed(self, origin: &str) -> String {
        match self {
            Channel::Stable => format!("{origin}/releases/station.json"),
            Channel::Beta => format!("{origin}/releases/station-beta.json"),
        }
    }
}

/// The channel the release in `app` came from, as its installer wrote it (CHANNEL); None from an installer before that.
pub fn release_channel(app: &Path) -> Option<Channel> {
    Channel::of(&std::fs::read_to_string(app.join("CHANNEL")).ok()?)
}

/// The channel a station is updated on: as its config says, else as its release came (an install from before there
/// were channels: stable).
pub fn channel_of(raw: &RawConfig, app: &Path) -> Channel {
    raw.update_channel.as_deref().and_then(Channel::of).or_else(|| release_channel(app)).unwrap_or(Channel::Stable)
}

/// Sets the channel in the config at `config` (`stillfail update --beta`/`--stable`, run apart from the station).
pub fn set_channel_in(config: &Path, data: &Path, channel: Channel) -> Result<()> {
    Settings::open(config, data)?.update(|raw| {
        raw.update_channel = Some(channel.id().to_string());
        Ok(())
    })?;
    Ok(())
}

/// What is offered for the station going from `version` to `latest` (as `channel`'s feed says it), its release having
/// come from `installed`: (newer, downgrade). Back to the stable release from a beta is offered even when it is older,
/// but only so: a stable station is never offered an older version.
fn offer(version: Option<&str>, latest: Option<&str>, channel: Channel, installed: Channel) -> (bool, bool) {
    match (version, latest) {
        (Some(v), Some(l)) if newer(v, l) => (true, false),
        (Some(v), Some(l)) => (false, channel == Channel::Stable && installed == Channel::Beta && newer(l, v)),
        _ => (false, false),
    }
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
    fn pin_npm_version(&mut self, package: &str, version: &str) {
        // Keep the destination and other install options when using the prefetched build.
        if let Some(arg) = self.args.iter_mut().find(|arg| **arg == format!("{package}@latest")) {
            *arg = format!("{package}@{version}");
        }
        // The prefetched tarball does not refresh npm's package index. Revalidate it
        // so a cached index from before this release cannot reject the pinned version.
        self.args.push("--prefer-online".into());
    }

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
    /// The station's, while it updates: where it is, as the pages say it.
    progress: Option<String>,
    /// While what it downloads comes in: how much of it is (0–100).
    percent: Option<u64>,
    /// The station's, a while after an update ended well: how it went.
    done: Option<String>,
    failed: Option<String>,
    /// The station's: the channel whose latest `latest` is.
    channel: Option<Channel>,
}

/// The versions, read now and then; `changes` moves when they differ from the last reading.
pub struct Updates {
    app: PathBuf,
    data: PathBuf,
    env: Env,
    /// The config, where the channel is kept.
    settings: Arc<Settings>,
    /// The channel the running release came from: as it says (CHANNEL), else the channel it started on.
    installed: Channel,
    origin: Box<dyn Fn() -> Option<String> + Send + Sync>,
    /// Where the runtimes' latest versions are read (npm's registry; tests give one that answers nothing).
    registry: String,
    items: Mutex<[Item; 3]>,
    checked: Mutex<(Option<i64>, bool)>,
    changes: watch::Sender<u64>,
    /// How many turns run now (the hub's), for what a drain waits on.
    running: OnceLock<Box<dyn Fn() -> usize + Send + Sync>>,
    /// The version the station's last update in this process went for: updating by itself, not tried again.
    tried: Mutex<Option<String>>,
    /// Told when a runtime was installed or updated here (the machine's logins read again).
    runtime_changed: OnceLock<Box<dyn Fn() + Send + Sync>>,
}

/// What the station's update started from the pages leaves in <data>/run/update.started, for whichever process runs
/// the station when it ends (after a handover or a restart, not the one that started it).
#[derive(serde::Serialize, serde::Deserialize)]
struct Started {
    at: i64,
    from: Option<String>,
}

impl Updates {
    /// `app`: the release this station runs from; `origin`: the still.fail cloud it is in, when it is.
    pub fn new(app: PathBuf, data: PathBuf, env: Env, settings: Arc<Settings>, origin: Box<dyn Fn() -> Option<String> + Send + Sync>) -> Arc<Updates> {
        Updates::with_registry(app, data, env, settings, origin, "https://registry.npmjs.org".into())
    }

    pub(crate) fn with_registry(app: PathBuf, data: PathBuf, env: Env, settings: Arc<Settings>, origin: Box<dyn Fn() -> Option<String> + Send + Sync>, registry: String) -> Arc<Updates> {
        let items = Default::default();
        // Read before an update can replace the release.
        let installed = release_channel(&app).unwrap_or_else(|| channel_of(&settings.raw(), &app));
        Arc::new(Updates { app, data, env, settings, installed, origin, registry, items: Mutex::new(items), checked: Mutex::new((None, false)), changes: watch::channel(0).0, running: OnceLock::new(), tried: Mutex::new(None), runtime_changed: OnceLock::new() })
    }

    /// The channel the station is updated on now.
    pub fn channel(&self) -> Channel {
        channel_of(&self.settings.raw(), &self.app)
    }

    /// Whether the station updates itself (`autoUpdate` in its config; off unless someone turned it on).
    pub fn auto(&self) -> bool {
        self.settings.raw().auto_update.unwrap_or(false)
    }

    /// Turns updating by itself on or off (as someone asked, from a page): kept in its config; turned on, what is out
    /// is read at once, and a newer release installed.
    pub async fn set_auto(self: &Arc<Self>, on: bool) -> Result<()> {
        if let Some(note) = &self.items.lock().unwrap()[Kind::Station as usize].note {
            bail!("{}：{note}", Kind::Station.name());
        }
        if self.auto() != on {
            self.settings.update(|raw| {
                raw.auto_update = Some(on);
                Ok(())
            })?;
            info!(on, "the station's updating by itself set");
            self.changed();
        }
        if on {
            self.check().await;
        }
        Ok(())
    }

    /// Puts the station on `channel` (as someone asked, from a page): kept in its config, and what is out read again
    /// from that channel. Going back to the stable channel from a beta offers the stable release, older or not.
    pub async fn set_channel(self: &Arc<Self>, channel: Channel) -> Result<()> {
        if let Some(note) = &self.items.lock().unwrap()[Kind::Station as usize].note {
            bail!("{}：{note}", Kind::Station.name());
        }
        self.keep_channel(channel)?;
        self.check().await;
        Ok(())
    }

    /// Keeps `channel` in the config, when it is another one than now.
    pub fn keep_channel(&self, channel: Channel) -> Result<()> {
        if self.channel() != channel {
            self.settings.update(|raw| {
                raw.update_channel = Some(channel.id().to_string());
                Ok(())
            })?;
            info!(channel = channel.id(), "the station's update channel set");
            self.changed();
        }
        Ok(())
    }

    /// How many turns run now, for what an update waits on when it has to restart the station.
    pub fn count_running(&self, running: impl Fn() -> usize + Send + Sync + 'static) {
        let _ = self.running.set(Box::new(running));
    }

    /// What to do when a runtime was installed or updated from here (read the machine's logins again).
    pub fn on_runtime_changed(&self, f: impl Fn() + Send + Sync + 'static) {
        let _ = self.runtime_changed.set(Box::new(f));
    }

    /// The runtime being installed or updated now, when one is: the station is not updated meanwhile, as its update
    /// hands over to another process or restarts, and the install would go on unfollowed (or be stopped) — its line
    /// back to 未安装 with nothing said.
    fn runtime_updating(&self) -> Option<Kind> {
        let items = self.items.lock().unwrap();
        [Kind::Claude, Kind::Codex].into_iter().find(|k| items[*k as usize].updating.is_some())
    }

    /// Reads them at once and every few hours after (every ten minutes while the station updates itself); an update
    /// of the station started before this process (by the one it took over from, or the one before a restart) is
    /// followed to its end.
    pub fn start(self: &Arc<Self>) {
        self.follow_started();
        let me = Arc::downgrade(self);
        tokio::spawn(async move {
            let mut last: Option<tokio::time::Instant> = None;
            loop {
                let Some(updates) = me.upgrade() else { return };
                if last.is_none_or(|at| updates.auto() || at.elapsed() >= EVERY) {
                    updates.check().await;
                    last = Some(tokio::time::Instant::now());
                }
                drop(updates);
                tokio::time::sleep(AUTO_EVERY).await;
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
        let channel = self.channel();
        Kind::ALL
            .into_iter()
            .zip(items)
            .map(|(kind, mut item)| {
                let station = kind == Kind::Station;
                // Read from another channel than the one it is on now: not yet known.
                if station && item.channel != Some(channel) {
                    item.latest = None;
                }
                let (newer, downgrade) = if station {
                    offer(item.version.as_deref(), item.latest.as_deref(), channel, self.installed)
                } else {
                    (matches!((&item.version, &item.latest), (Some(v), Some(l)) if newer(v, l)), false)
                };
                SoftwareVersion {
                    id: kind.id().into(),
                    name: kind.name().into(),
                    installed: item.installed,
                    newer,
                    downgrade,
                    // Only where it can be updated from here.
                    channel: (station && item.note.is_none() && item.version.is_some()).then(|| channel.id().to_string()),
                    auto: (station && item.note.is_none() && item.version.is_some()).then(|| self.auto()),
                    updatable: item.how.is_some() || (kind == Kind::Station && item.note.is_none() && item.version.is_some()),
                    version: item.version,
                    latest: item.latest,
                    note: item.note,
                    state: if item.updating.is_some() { "updating" } else if item.failed.is_some() { "failed" } else { "idle" }.into(),
                    progress: item.updating.and(item.progress),
                    percent: item.updating.and(item.percent).map(|p| p as i64),
                    done: item.done,
                    message: item.failed,
                    checked_at: checked,
                }
            })
            .collect()
    }

    /// Reads every version and what is out, now (once at a time); a newer release of the station's channel is
    /// installed when it updates itself.
    pub async fn check(self: &Arc<Self>) {
        {
            let mut checked = self.checked.lock().unwrap();
            if checked.1 {
                return;
            }
            checked.1 = true;
        }
        let (mut station, claude, codex) = tokio::join!(self.read_station(self.channel()), self.read_runtime(Kind::Claude), self.read_runtime(Kind::Codex));
        // Put on another channel while it was read: read from that one.
        while station.channel != Some(self.channel()) {
            station = self.read_station(self.channel()).await;
        }
        {
            let mut items = self.items.lock().unwrap();
            for (kind, read) in [(Kind::Station, station), (Kind::Claude, claude), (Kind::Codex, codex)] {
                let item = &mut items[kind as usize];
                // One that is updating keeps what it was until it is done; but one not yet read (an update this
                // process took over following) is read.
                if item.updating.is_none() {
                    *item = Item { failed: item.failed.take(), done: item.done.take(), ..read };
                } else if !item.installed {
                    *item = Item { updating: item.updating, progress: item.progress.take(), percent: item.percent, ..read };
                }
            }
        }
        *self.checked.lock().unwrap() = (Some(now_ms()), false);
        self.changed();
        if let Some(to) = self.to_update_to() {
            info!(to, "a newer release out: the station updates itself");
            if let Err(e) = self.update_station() {
                warn!(error = %e, "the station not updated by itself");
            }
        }
    }

    /// The version the station updates itself to now, when it does: it updates itself, can be updated from here, is
    /// not updating, and its channel's latest is newer (not an older stable one back from the beta) and not one it
    /// already went for.
    fn to_update_to(&self) -> Option<String> {
        if !self.auto() {
            return None;
        }
        let item = self.items.lock().unwrap()[Kind::Station as usize].clone();
        if item.note.is_some() || item.updating.is_some() || item.channel != Some(self.channel()) || self.runtime_updating().is_some() {
            return None;
        }
        let latest = item.latest?;
        let (newer, _) = offer(item.version.as_deref(), Some(&latest), self.channel(), self.installed);
        (newer && self.tried.lock().unwrap().as_ref() != Some(&latest)).then_some(latest)
    }

    async fn read_station(&self, channel: Channel) -> Item {
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
            Some(origin) => match fetch_json(&channel.feed(origin)).await {
                Ok(said) => said.get("version").and_then(Value::as_str).map(String::from),
                Err(e) => {
                    warn!(error = %e, "the station's latest release not read");
                    None
                }
            },
            None => None,
        };
        Item { installed: true, version, latest, note, channel: Some(channel), ..Default::default() }
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
        let latest = match fetch_json(&format!("{}/{}/latest", self.registry, kind.package())).await {
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
            if let Some(runtime) = self.runtime_updating() {
                bail!("{} 正在安装或更新，等它完成再更新 station", runtime.name());
            }
            return self.update_station();
        }
        if self.items.lock().unwrap()[Kind::Station as usize].updating.is_some() {
            bail!("station 正在更新，等它完成再{}{}", if item.installed { "更新" } else { "安装" }, kind.name());
        }
        let how = item.how.ok_or_else(|| anyhow!("{} 没法在这里更新", kind.name()))?;
        self.set(kind, |i| {
            i.updating = Some(now_ms());
            i.progress = None;
            i.percent = None;
            i.failed = None;
            i.done = None;
        });
        let me = self.clone();
        tokio::spawn(async move {
            info!(runtime = kind.id(), program = %how.program.display(), args = ?how.args, "updating or installing a runtime");
            let failed = match tokio::time::timeout(RUNTIME_LIMIT, me.install(kind, how.clone())).await {
                Ok(Ok((true, _))) => None,
                Ok(Ok((false, said))) => Some(tail(&said)),
                Ok(Err(e)) => Some(e.to_string()),
                Err(_) => Some("超过 10 分钟还没有完成".to_string()),
            };
            if let Some(failed) = &failed {
                warn!(runtime = kind.id(), failed, "the runtime not updated");
            }
            let read = me.read_runtime(kind).await;
            // Done without an error but not there, or not newer: installed somewhere the station's PATH does not find.
            let failed = failed.or_else(|| match (&read.version, &read.latest) {
                _ if !read.installed => Some(format!("{} 跑完了，但 station 的 PATH 上还是找不到 {}：可能装到了别处", how.program.display(), kind.command())),
                (Some(version), Some(latest)) if newer(version, latest) => {
                    Some(format!("{} 跑完了，但 {} 还是 {version}（最新 {latest}）：可能装到了别处，PATH 上的不是它", how.program.display(), kind.command()))
                }
                _ => None,
            });
            me.set(kind, |i| *i = Item { failed, ..read });
            if let Some(changed) = me.runtime_changed.get() {
                changed();
            }
            // The station's own update waited for this one.
            if let Some(to) = me.to_update_to() {
                info!(to, "a newer release out, waited for a runtime: the station updates itself");
                if let Err(e) = me.update_station() {
                    warn!(error = %e, "the station not updated by itself");
                }
            }
        });
        Ok(())
    }

    /// Runs `how`, saying where it is as it goes (an item's `progress`): a download that can be measured, by how much of
    /// it is in (Codex's build for this machine, fetched here first; Claude Code's, as its installer writes it), else
    /// the step the command says it is at (Homebrew's, Claude Code's installer's).
    async fn install(self: &Arc<Self>, kind: Kind, mut how: How) -> Result<(bool, String)> {
        let npm = how.program.file_name().is_some_and(|n| n == "npm") && how.args.first().is_some_and(|a| a == "install");
        if kind == Kind::Codex && npm {
            if let Some(version) = self.fetch_codex(&how.program).await {
                // That version, as npm's cache has its build (`latest` from a cached list could be an older one).
                how.pin_npm_version(kind.package(), &version);
            }
        }
        let installing = Arc::new(AtomicBool::new(false));
        // Claude Code's own installer (not `claude update`, nor Homebrew).
        let watch = (kind == Kind::Claude && how.program == Path::new("/bin/sh")).then(|| self.watch_claude_download(installing.clone()));
        let args: Vec<&str> = how.args.iter().map(String::as_str).collect();
        let said = run_lines(&how.program, &args, &self.env, RUNTIME_LIMIT, |line| {
            if let Some(step) = step_of(line) {
                if step == INSTALLING {
                    installing.store(true, Ordering::SeqCst);
                }
                self.say(kind, step, None);
            }
        })
        .await;
        if let Some(watch) = watch {
            watch.abort();
        }
        said
    }

    /// Where a runtime's update is, as the pages say it (while it updates), and how much of a download is in.
    fn say(&self, kind: Kind, progress: &str, percent: Option<u64>) {
        let mut items = self.items.lock().unwrap();
        let item = &mut items[kind as usize];
        if item.updating.is_none() || (item.progress.as_deref() == Some(progress) && item.percent == percent) {
            return;
        }
        item.progress = Some(progress.to_string());
        item.percent = percent;
        drop(items);
        self.changed();
    }

    fn say_downloading(&self, kind: Kind, version: &str, got: u64, total: Option<u64>) {
        let (said, percent) = downloading(version, got, total);
        self.say(kind, &said, percent);
    }

    /// Codex's build for this machine (nearly all its install downloads), fetched here so how much is in can be said,
    /// and put in npm's cache for the install to take: the version fetched; None when it was not (the install then
    /// downloads it itself, unmeasured).
    async fn fetch_codex(&self, npm: &Path) -> Option<String> {
        let platform = platform()?;
        let package = Kind::Codex.package();
        let latest = fetch_json(&format!("{}/{package}/latest", self.registry)).await.ok()?;
        let version = latest.get("version")?.as_str()?.to_string();
        let build = fetch_json(&format!("{}/{package}/{version}-{platform}", self.registry)).await.ok()?;
        let url = build.pointer("/dist/tarball")?.as_str()?.to_string();
        let file = std::env::temp_dir().join(format!("stillfail-codex-{version}-{platform}.tgz"));
        let cached = match self.download(Kind::Codex, &version, &url, &file).await {
            Ok(()) => {
                self.say(Kind::Codex, INSTALLING, None);
                run(npm, &["cache", "add", &file.to_string_lossy()], &self.env, Duration::from_secs(120)).await
            }
            Err(e) => Err(e),
        };
        let _ = std::fs::remove_file(&file);
        match cached {
            Ok((true, _)) => Some(version),
            Ok((false, said)) => {
                warn!(said = %tail(&said), "Codex's build not put in npm's cache; npm downloads it");
                None
            }
            Err(e) => {
                warn!(error = %e, "Codex's build not fetched; npm downloads it");
                None
            }
        }
    }

    /// Downloads `url` to `to`, saying how much of it is in.
    async fn download(&self, kind: Kind, version: &str, url: &str, to: &Path) -> Result<()> {
        let http = reqwest::Client::builder().connect_timeout(Duration::from_secs(15)).build()?;
        let mut response = http.get(url).header("user-agent", "stillfail-station").send().await?;
        if !response.status().is_success() {
            bail!("{url}: {}", response.status());
        }
        let total = response.content_length();
        let mut file = tokio::fs::File::create(to).await?;
        let mut got = 0;
        self.say_downloading(kind, version, got, total);
        while let Some(chunk) = tokio::time::timeout(Duration::from_secs(60), response.chunk()).await.map_err(|_| anyhow!("下载一分钟没有动静"))?? {
            file.write_all(&chunk).await?;
            got += chunk.len() as u64;
            self.say_downloading(kind, version, got, total);
        }
        file.flush().await?;
        Ok(())
    }

    /// Says how much of Claude Code's build its installer has downloaded (into ~/.claude/downloads, its size in the
    /// release's manifest; the zstd one when the machine has zstd), until it sets it up (`installing`).
    fn watch_claude_download(self: &Arc<Self>, installing: Arc<AtomicBool>) -> tokio::task::JoinHandle<()> {
        let me = self.clone();
        tokio::spawn(async move {
            let (Some(home), Some(platform)) = (me.env.get("HOME").map(PathBuf::from), platform()) else { return };
            let base = "https://downloads.claude.ai/claude-code-releases";
            let Ok(version) = fetch_text(&format!("{base}/latest")).await else { return };
            let version = version.trim().to_string();
            let (plain, zst) = (format!("{base}/{version}/manifest.json"), format!("{base}/{version}/manifest.zst.json"));
            let (plain, zst) = tokio::join!(fetch_json(&plain), fetch_json(&zst));
            let size = |manifest: Result<Value>| manifest.ok().and_then(|m| m.pointer(&format!("/platforms/{platform}/size")).and_then(Value::as_u64));
            let (plain, zst) = (size(plain), size(zst));
            let file = home.join(".claude/downloads").join(format!("claude-{version}-{platform}"));
            let zst_file = file.with_file_name(format!("claude-{version}-{platform}.zst"));
            while !installing.load(Ordering::SeqCst) {
                let len = |f: &Path| std::fs::metadata(f).ok().map(|m| m.len());
                let got = match (len(&zst_file), len(&file)) {
                    (Some(got), _) => zst.map(|total| (got, total)),
                    (None, Some(got)) => plain.map(|total| (got, total)),
                    _ => None,
                };
                if let Some((got, total)) = got {
                    me.say_downloading(Kind::Claude, &version, got, Some(total));
                }
                tokio::time::sleep(Duration::from_millis(500)).await;
            }
        })
    }

    /// Runs the cloud's installer apart from the station, as `stillfail update` does, and follows it (`follow`): by
    /// this process, and after a handover or a restart by the one that runs then (run/update.started says to).
    fn update_station(self: &Arc<Self>) -> Result<()> {
        let origin = (self.origin)().ok_or_else(|| anyhow!("还没加入 workspace，无从更新"))?;
        let run_dir = self.data.join("run");
        std::fs::create_dir_all(&run_dir)?;
        for file in ["update.exit", "update.step"] {
            let _ = std::fs::remove_file(run_dir.join(file));
        }
        // In the background of a shell that ends at once: the installer is nobody's child here, and outlives both a
        // handover (this process becomes another binary) and a restart (the service's processes are stopped).
        let script = r#"( curl -fsSL "$1/install.sh" | sh; echo $? > "$2/update.exit" ) > "$2/update.log" 2>&1 < /dev/null &"#;
        let channel = self.channel();
        let status = std::process::Command::new("/bin/sh")
            .args(["-c", script, "sh", &origin, &run_dir.to_string_lossy()])
            .env_clear()
            .envs(&self.env)
            // Under both names: the cloud's installer from before the rename reads the old one.
            .envs(crate::former::both("DATA").map(|name| (name, self.data.clone())))
            // The release of its channel (the installer from before channels takes the stable one).
            .env("STILLFAIL_CHANNEL", channel.id())
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .process_group(0)
            .status()?;
        if !status.success() {
            bail!("没能开始更新");
        }
        info!(origin, channel = channel.id(), "updating the station");
        *self.tried.lock().unwrap() = self.items.lock().unwrap()[Kind::Station as usize].latest.clone();
        let started = Started { at: now_ms(), from: station_version(&self.app) };
        if let Err(e) = std::fs::write(run_dir.join("update.started"), serde_json::to_vec(&started)?) {
            warn!(error = %e, "update.started not written; a handover or restart will not say how the update went");
        }
        self.follow(started);
        Ok(())
    }

    /// An update started before this process, when one is: followed as if started here.
    fn follow_started(self: &Arc<Self>) {
        let run_dir = self.data.join("run");
        let Some(started) = std::fs::read(run_dir.join("update.started")).ok().and_then(|b| serde_json::from_slice::<Started>(&b).ok()) else { return };
        if now_ms() - started.at > STATION_LIMIT_MS {
            for file in ["update.started", "update.step"] {
                let _ = std::fs::remove_file(run_dir.join(file));
            }
            return;
        }
        info!("following the station's update started before this process");
        self.follow(started);
    }

    /// Shows how the station's update goes (the installer's steps, in run/update.step) until it says how it ended in
    /// run/update.exit (and what it said in run/update.log), then how it went for a while.
    fn follow(self: &Arc<Self>, started: Started) {
        self.set(Kind::Station, |i| {
            i.updating = Some(started.at);
            i.progress = None;
            i.percent = None;
            i.failed = None;
            i.done = None;
        });
        let run_dir = self.data.join("run");
        let weak = Arc::downgrade(self);
        tokio::spawn(async move {
            let (exit, log, step_file) = (run_dir.join("update.exit"), run_dir.join("update.log"), run_dir.join("update.step"));
            loop {
                let Some(me) = weak.upgrade() else { return };
                let step = std::fs::read_to_string(&step_file).map(|s| s.trim().to_string()).unwrap_or_default();
                let (failed, done) = match std::fs::read_to_string(&exit) {
                    Ok(code) if code.trim() == "0" => (None, Some(me.done(&started, &step))),
                    Ok(code) => (Some(tail(&std::fs::read_to_string(&log).unwrap_or_else(|_| format!("安装脚本退出码 {}", code.trim())))), None),
                    Err(_) if now_ms() - started.at > STATION_LIMIT_MS => (Some("安装脚本 20 分钟没有结束，看 ~/.stillfail/run/update.log".to_string()), None),
                    Err(_) => {
                        let progress = me.progress(&step);
                        let percent = if step == "download" { station_download_percent(&log) } else { None };
                        let changed = {
                            let items = me.items.lock().unwrap();
                            let item = &items[Kind::Station as usize];
                            item.progress != progress || item.percent != percent
                        };
                        if changed {
                            me.set(Kind::Station, |i| {
                                i.progress = progress;
                                i.percent = percent;
                            });
                        }
                        drop(me);
                        tokio::time::sleep(Duration::from_secs(1)).await;
                        continue;
                    }
                };
                for file in ["update.started", "update.step"] {
                    let _ = std::fs::remove_file(run_dir.join(file));
                }
                info!(failed = failed.is_some(), "the station's update ended");
                me.set(Kind::Station, |i| {
                    i.updating = None;
                    i.progress = None;
                    i.percent = None;
                    i.failed = failed;
                    i.done = done.clone();
                });
                me.check().await;
                drop(me);
                if let Some(done) = done {
                    tokio::time::sleep(DONE_SHOWN).await;
                    let Some(me) = weak.upgrade() else { return };
                    // Unless another update has said something since.
                    if me.items.lock().unwrap()[Kind::Station as usize].done.as_ref() == Some(&done) {
                        me.set(Kind::Station, |i| i.done = None);
                    }
                }
                return;
            }
        });
    }

    /// Where the update is, by the installer's step, as the pages say it.
    fn progress(&self, step: &str) -> Option<String> {
        Some(match step {
            "download" => "正在下载新版本…".to_string(),
            "handoff" => "正在交接给新版本（agent 不中断）…".to_string(),
            "drain" => match self.running.get().map(|running| running()).unwrap_or(0) {
                0 => "正在重启…".to_string(),
                n => format!("等 {n} 个 agent 跑完这一轮再重启（新消息先排队）…"),
            },
            "restart" => "正在重启…".to_string(),
            _ => return None,
        })
    }

    /// How an update that ended well went, by the step it ended on.
    fn done(&self, started: &Started, step: &str) -> String {
        let now = station_version(&self.app);
        if now.is_some() && now == started.from {
            return "已经是最新版".to_string();
        }
        let to = now.map(|v| format!("到 {v}")).unwrap_or_default();
        match step {
            "handoff" => format!("已更新{to}，agent 没有中断"),
            "drain" | "restart" => format!("已更新{to}（重启了一次 station）"),
            _ => format!("已更新{to}"),
        }
    }
}

/// The installer already records curl's progress bar in update.log, including with older clouds. Read only its
/// tail (a slow download's log can be large), and only complete percentage readings: curl may be mid-write.
fn station_download_percent(log: &Path) -> Option<u64> {
    use std::io::{Read, Seek, SeekFrom};
    let mut file = std::fs::File::open(log).ok()?;
    let len = file.metadata().ok()?.len();
    file.seek(SeekFrom::Start(len.saturating_sub(4096))).ok()?;
    let mut bytes = Vec::new();
    file.take(4096).read_to_end(&mut bytes).ok()?;
    curl_percent(&String::from_utf8_lossy(&bytes))
}

fn curl_percent(log: &str) -> Option<u64> {
    log.split(['\r', '\n']).rev().find_map(|line| {
        let line = line.trim_end();
        let (bar, value) = line.rsplit_once(char::is_whitespace)?;
        if bar.is_empty() || !bar.chars().all(|c| c == '#' || c.is_ascii_whitespace()) {
            return None;
        }
        let value = value.strip_suffix('%')?.parse::<f64>().ok()?;
        (value.is_finite() && (0.0..=100.0).contains(&value)).then_some(value as u64)
    })
}

/// The last lines of what a command said, for the pages.
fn tail(said: &str) -> String {
    let lines: Vec<&str> = said.trim().lines().filter(|l| !l.trim().is_empty()).collect();
    let tail = lines[lines.len().saturating_sub(4)..].join("\n");
    if tail.is_empty() { "更新失败，没有输出".to_string() } else { tail.chars().rev().take(600).collect::<Vec<_>>().into_iter().rev().collect() }
}

/// What a runtime's update says once what it downloads is in.
const INSTALLING: &str = "正在安装…";

/// The step a line of an installer's output says it is at: Homebrew's, and Claude Code's installer's.
fn step_of(line: &str) -> Option<&'static str> {
    let line = line.trim();
    if ["==> Fetching", "==> Downloading"].iter().any(|s| line.starts_with(s)) {
        Some("正在下载…")
    } else if ["==> Installing", "==> Pouring", "==> Upgrading", "==> Moving", "==> Linking", "Setting up Claude Code"].iter().any(|s| line.starts_with(s)) {
        Some(INSTALLING)
    } else {
        None
    }
}

/// How much of a download is in, as the pages say it: a line, and the share (drawn as a bar) when its size is known.
fn downloading(version: &str, got: u64, total: Option<u64>) -> (String, Option<u64>) {
    let mb = |b: u64| (b as f64 / 1_000_000.0).round() as u64;
    match total {
        Some(total) if total > 0 => (format!("正在下载 {version}（{} MB）", mb(total)), Some(got.min(total) * 100 / total)),
        _ => (format!("正在下载 {version}：已下 {} MB", mb(got)), None),
    }
}

/// This machine as the runtimes name their builds (`darwin-arm64`…).
fn platform() -> Option<String> {
    let os = match std::env::consts::OS {
        "macos" => "darwin",
        "linux" => "linux",
        _ => return None,
    };
    let arch = match std::env::consts::ARCH {
        "aarch64" => "arm64",
        "x86_64" => "x64",
        _ => return None,
    };
    Some(format!("{os}-{arch}"))
}

async fn fetch_text(url: &str) -> Result<String> {
    let http = reqwest::Client::builder().timeout(Duration::from_secs(15)).build()?;
    let response = http.get(url).header("user-agent", "stillfail-station").send().await?;
    if !response.status().is_success() {
        bail!("{url}: {}", response.status());
    }
    Ok(response.text().await?)
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
    // Vite+ global commands are shims pointing to vp itself. Its packages are separate from npm's;
    // `claude update` can report success after updating a different installation.
    if kind != Kind::Station && found.real.file_name().is_some_and(|name| name == "vp") {
        let vp = found.on_path.parent().map(|dir| dir.join("vp"))
            .filter(|p| std::fs::canonicalize(p).is_ok_and(|p| p == found.real))
            .or_else(|| find_command("vp", env).filter(|vp| vp.real == found.real).map(|vp| vp.on_path))
            .ok_or_else(|| format!("{} 是用 Vite+ 装的，但 station 找不到对应的 vp", kind.name()))?;
        return Ok(How::new(vp, &["install", "-g", &format!("{}@latest", kind.package())]));
    }
    let brew = || find_command("brew", env).map(|b| b.on_path).ok_or_else(|| format!("{} 是用 Homebrew 装的，但 station 找不到 brew", kind.name()));
    let npm = || {
        // The npm of the Node the command is installed in (…/lib/node_modules/… → …/bin/npm): the link on PATH can sit
        // beside another Node's npm (~/.local/bin with links into two Nodes), which installs where PATH does not look.
        let own = real.split_once("/lib/node_modules/").map(|(prefix, _)| Path::new(prefix).join("bin/npm")).filter(|p| p.exists());
        let beside = || found.on_path.parent().map(|d| d.join("npm")).filter(|p| p.exists());
        own.or_else(beside).or_else(|| find_command("npm", env).map(|n| n.on_path)).ok_or_else(|| format!("{} 是用 npm 装的，但 station 找不到 npm", kind.name()))
    };
    let package = format!("{}@latest", kind.package());
    match kind {
        Kind::Station => Err(String::new()),
        Kind::Claude if real.contains("/Caskroom/") => Ok(How::new(brew()?, &["upgrade", "--cask", "claude-code"])),
        Kind::Claude if real.contains("/Cellar/") => Ok(How::new(brew()?, &["upgrade", "claude-code"])),
        Kind::Codex if real.contains("/Caskroom/") => Ok(How::new(brew()?, &["upgrade", "--cask", "codex"])),
        Kind::Codex if real.contains("/Cellar/") => Ok(How::new(brew()?, &["upgrade", "codex"])),
        Kind::Claude | Kind::Codex if real.contains("/node_modules/") => {
            // npm's shebang uses PATH's node; even the right npm can therefore choose another
            // Node's global prefix. Explicitly target the installation the station actually uses.
            let (prefix, _) = real.split_once("/lib/node_modules/")
                .ok_or_else(|| format!("无法确定 {real} 的 npm 全局安装目录，要在那台机器上自己更新"))?;
            Ok(How::new(npm()?, &["install", "-g", &package, "--prefix", prefix]))
        },
        Kind::Claude => Ok(How::new(&found.on_path, &["update"])),
        Kind::Codex if real.contains("/packages/standalone/releases/") => standalone_codex_update(found),
        Kind::Codex => Err(format!("装在 {real}，不是 npm 或 Homebrew 装的，要在那台机器上自己更新")),
    }
}

/// Reuse the official installer's checksums, versioned releases and atomic link switch. Keep both
/// the package home and the visible command at the locations this station actually uses.
fn standalone_codex_update(found: &Found) -> Result<How, String> {
    let invalid = || format!("无法确定 {} 的 standalone 安装入口，要在那台机器上自己更新", found.on_path.display());
    let real = found.real.to_str().ok_or_else(invalid)?;
    let (home, release) = real.rsplit_once("/packages/standalone/releases/").ok_or_else(invalid)?;
    let (_, binary) = release.split_once('/').ok_or_else(invalid)?;
    let bin = found.on_path.parent().ok_or_else(invalid)?;
    // Never replace a binary inside an immutable release, or make current/bin link into itself.
    if !matches!(binary, "bin/codex" | "codex") || bin.starts_with(Path::new(home).join("packages/standalone")) {
        return Err(invalid());
    }
    let script = r#"set -eu
installer=$(curl -fsSL https://chatgpt.com/codex/install.sh)
CODEX_HOME="$1" CODEX_INSTALL_DIR="$2" CODEX_NON_INTERACTIVE=1 sh -c "$installer" -- --release latest"#;
    Ok(How::new("/bin/sh", &["-c", script, "stillfail-codex-update", home, &bin.to_string_lossy()]))
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

/// Runs a command to its end as `run` does, telling each line it says as it says it (stdout and stderr).
async fn run_lines(program: impl AsRef<Path>, args: &[&str], env: &Env, timeout: Duration, mut on_line: impl FnMut(&str)) -> Result<(bool, String)> {
    let mut cmd = Command::new(program.as_ref());
    cmd.args(args).env_clear().envs(env).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).kill_on_drop(true);
    cmd.current_dir(std::env::temp_dir()).process_group(0);
    let mut child = cmd.spawn()?;
    let (mut out, mut err) = (BufReader::new(child.stdout.take().unwrap()).split(b'\n'), BufReader::new(child.stderr.take().unwrap()).split(b'\n'));
    let mut said = String::new();
    let work = async {
        let (mut out_done, mut err_done) = (false, false);
        let mut take = |line: Option<Vec<u8>>, done: &mut bool| match line {
            Some(line) => {
                let line = String::from_utf8_lossy(&line);
                on_line(&line);
                said.push_str(&line);
                said.push('\n');
            }
            None => *done = true,
        };
        while !(out_done && err_done) {
            tokio::select! {
                line = out.next_segment(), if !out_done => take(line?, &mut out_done),
                line = err.next_segment(), if !err_done => take(line?, &mut err_done),
            }
        }
        anyhow::Ok(child.wait().await?)
    };
    let status = tokio::time::timeout(timeout, work).await.map_err(|_| anyhow!("{} 没有及时结束", program.as_ref().display()))??;
    Ok((status.success(), said))
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    #[tokio::test]
    async fn an_install_says_where_it_is_as_it_goes() {
        let env: Env = [("PATH".to_string(), "/usr/bin:/bin".to_string())].into_iter().collect();
        let mut steps = vec![];
        let (ok, said) = run_lines("/bin/sh", &["-c", "echo '==> Downloading https://x'; echo '==> Pouring codex'; echo 'Warning: x' >&2; exit 3"], &env, Duration::from_secs(10), |line| steps.extend(step_of(line))).await.unwrap();
        assert!(!ok);
        assert_eq!(steps, ["正在下载…", INSTALLING]);
        // Both streams kept (their order between them is not known).
        assert!(said.contains("==> Pouring codex") && said.contains("Warning: x"));
        assert_eq!(step_of("Setting up Claude Code..."), Some(INSTALLING));
        assert_eq!(step_of("added 2 packages in 4s"), None);
        assert_eq!(downloading("0.159.3", 60_000_000, Some(133_847_481)), ("正在下载 0.159.3（134 MB）".to_string(), Some(44)));
        assert_eq!(downloading("0.159.3", 60_000_000, None), ("正在下载 0.159.3：已下 60 MB".to_string(), None));
    }

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

    #[test]
    fn the_latest_comes_from_the_channels_feed_and_a_station_is_on_the_channel_it_was_installed_from() {
        assert_eq!(Channel::Stable.feed("https://app.still.fail"), "https://app.still.fail/releases/station.json");
        assert_eq!(Channel::Beta.feed("https://app.still.fail"), "https://app.still.fail/releases/station-beta.json");
        let dir = tempfile::tempdir().unwrap();
        let raw = |channel: Option<&str>| RawConfig { update_channel: channel.map(String::from), ..Default::default() };
        // An install from before channels, and a config that says none: stable.
        assert_eq!(release_channel(dir.path()), None);
        assert_eq!(channel_of(&raw(None), dir.path()), Channel::Stable);
        assert_eq!(channel_of(&raw(Some("nonsense")), dir.path()), Channel::Stable);
        // Installed from the beta: on it, until the config says otherwise.
        std::fs::write(dir.path().join("CHANNEL"), "beta\n").unwrap();
        assert_eq!(channel_of(&raw(None), dir.path()), Channel::Beta);
        assert_eq!(channel_of(&raw(Some("stable")), dir.path()), Channel::Stable);
        assert_eq!(channel_of(&raw(Some("beta")), dir.path()), Channel::Beta);
    }

    #[test]
    fn an_older_version_is_offered_only_back_from_the_beta() {
        use Channel::*;
        // Newer is newer on either channel.
        assert_eq!(offer(Some("0.1.10"), Some("0.1.12"), Stable, Stable), (true, false));
        assert_eq!(offer(Some("0.1.10"), Some("0.1.12"), Beta, Stable), (true, false));
        // A stable station never goes back by itself, nor a beta one to an older beta.
        assert_eq!(offer(Some("0.1.12"), Some("0.1.10"), Stable, Stable), (false, false));
        assert_eq!(offer(Some("0.1.12"), Some("0.1.10"), Beta, Beta), (false, false));
        // Switched back from the beta: the older stable release is offered, as going back.
        assert_eq!(offer(Some("0.1.12"), Some("0.1.10"), Stable, Beta), (false, true));
        // The same build (a beta promoted): nothing.
        assert_eq!(offer(Some("0.1.12"), Some("0.1.12"), Stable, Beta), (false, false));
        assert_eq!(offer(None, Some("0.1.10"), Stable, Beta), (false, false));
        assert_eq!(offer(Some("0.1.12"), None, Stable, Beta), (false, false));
    }

    /// A station installed by the installer (<data>/app, BUILD `build`, from `channel`), in a cloud that answers nothing;
    /// its config `settings`, else <data>/config.json.
    pub(crate) fn installed(data: &Path, build: &str, channel: Option<&str>, settings: Option<Arc<Settings>>) -> Arc<Updates> {
        let app = data.join("app");
        std::fs::create_dir_all(&app).unwrap();
        std::fs::write(app.join("BUILD"), build).unwrap();
        if let Some(channel) = channel {
            std::fs::write(app.join("CHANNEL"), channel).unwrap();
        }
        let settings = settings.unwrap_or_else(|| Settings::open(&data.join("config.json"), data).unwrap());
        let nowhere = "http://127.0.0.1:1".to_string();
        let env: Env = [("PATH".to_string(), "/nowhere".to_string())].into();
        Updates::with_registry(app, data.to_path_buf(), env, settings, Box::new(move || Some("http://127.0.0.1:1".into())), nowhere)
    }

    #[tokio::test]
    async fn an_update_started_before_a_handover_is_followed_to_its_end() {
        let dir = tempfile::tempdir().unwrap();
        let run = dir.path().join("run");
        std::fs::create_dir_all(&run).unwrap();
        // Started by the binary this one took over from, which was 0.1.1299; the installer is handing over.
        std::fs::write(run.join("update.started"), serde_json::to_vec(&Started { at: now_ms(), from: Some("0.1.1299".into()) }).unwrap()).unwrap();
        std::fs::write(run.join("update.step"), "handoff\n").unwrap();
        let updates = installed(dir.path(), "1300", None, None);
        updates.count_running(|| 2);
        updates.follow_started();
        let station = || updates.get().remove(0);
        tokio::time::sleep(Duration::from_millis(300)).await;
        assert_eq!((station().state.as_str(), station().progress.as_deref()), ("updating", Some("正在交接给新版本（agent 不中断）…")));
        // Had it had to restart: what the drain waits on.
        std::fs::write(run.join("update.step"), "drain\n").unwrap();
        tokio::time::sleep(Duration::from_millis(1500)).await;
        assert_eq!(station().progress.as_deref(), Some("等 2 个 agent 跑完这一轮再重启（新消息先排队）…"));
        std::fs::write(run.join("update.step"), "handoff\n").unwrap();
        std::fs::write(run.join("update.exit"), "0\n").unwrap();
        tokio::time::sleep(Duration::from_millis(1500)).await;
        let line = station();
        assert_eq!((line.state.as_str(), line.progress, line.done.as_deref()), ("idle", None, Some("已更新到 0.1.1300，agent 没有中断")));
        assert!(!run.join("update.started").exists() && !run.join("update.step").exists());
        // Read again (the next check), it still says so.
        updates.check().await;
        assert_eq!(station().done.as_deref(), Some("已更新到 0.1.1300，agent 没有中断"));
    }

    #[test]
    fn installer_download_percent_reads_complete_curl_bars() {
        assert_eq!(curl_percent("下载 still.fail station…\n\r                 0.0%"), Some(0));
        assert_eq!(curl_percent("\r###   12.4%\r########   44.9%\r#########  45."), Some(44));
        assert_eq!(curl_percent("\r######## 100.0%\n"), Some(100));
        for log in ["", "\r#=#=#", "error 44.0%", "### NaN%", "### 101.0%", "### -1.0%"] {
            assert_eq!(curl_percent(log), None, "{log}");
        }
        let dir = tempfile::tempdir().unwrap();
        let log = dir.path().join("update.log");
        assert_eq!(station_download_percent(&log), None);
        std::fs::write(&log, format!("{}\r### 37.2%", "old output\n".repeat(1000))).unwrap();
        assert_eq!(station_download_percent(&log), Some(37));
    }

    #[tokio::test]
    async fn station_download_percent_changes_are_published_and_cleared() {
        let dir = tempfile::tempdir().unwrap();
        let run = dir.path().join("run");
        std::fs::create_dir_all(&run).unwrap();
        let updates = installed(dir.path(), "1300", None, None);
        let station = || updates.get().remove(0);
        std::fs::write(run.join("update.step"), "download\n").unwrap();
        std::fs::write(run.join("update.log"), "\r### 12.4%").unwrap();
        updates.follow(Started { at: now_ms(), from: Some("0.1.1300".into()) });
        tokio::time::sleep(Duration::from_millis(300)).await;
        assert_eq!(station().percent, Some(12));
        std::fs::write(run.join("update.log"), "\r### 12.4%\r######## 44.9%").unwrap();
        tokio::time::sleep(Duration::from_millis(1500)).await;
        assert_eq!(station().percent, Some(44));
        std::fs::write(run.join("update.step"), "handoff\n").unwrap();
        tokio::time::sleep(Duration::from_millis(1500)).await;
        assert_eq!(station().percent, None);
        assert_eq!(station().progress.as_deref(), Some("正在交接给新版本（agent 不中断）…"));
        std::fs::write(run.join("update.exit"), "0\n").unwrap();
        tokio::time::sleep(Duration::from_millis(1500)).await;
        assert_eq!(station().state, "idle");
        assert_eq!(station().percent, None);
    }

    /// What the station's line says, its latest read as `latest` (as if from the channel it is on).
    fn station_with(updates: &Updates, latest: &str) -> SoftwareVersion {
        {
            let mut items = updates.items.lock().unwrap();
            let item = &mut items[Kind::Station as usize];
            item.version = station_version(&updates.app);
            item.latest = Some(latest.into());
            item.channel = Some(updates.channel());
        }
        updates.get().remove(0)
    }

    #[tokio::test]
    async fn switched_back_from_the_beta_the_stable_release_is_offered_and_kept_in_the_config() {
        let dir = tempfile::tempdir().unwrap();
        let updates = installed(dir.path(), "1300", Some("beta"), None);
        assert_eq!(updates.channel(), Channel::Beta);
        let line = station_with(&updates, "0.1.1310");
        assert_eq!((line.channel.as_deref(), line.newer, line.downgrade), (Some("beta"), true, false));

        updates.set_channel(Channel::Stable).await.unwrap();
        assert_eq!(updates.channel(), Channel::Stable);
        let config: Value = serde_json::from_str(&std::fs::read_to_string(dir.path().join("config.json")).unwrap()).unwrap();
        assert_eq!(config["updateChannel"], "stable");
        // What was read from the beta's feed is not the stable one's.
        let line = updates.get().remove(0);
        assert_eq!((line.latest, line.newer, line.downgrade), (None, false, false));
        let line = station_with(&updates, "0.1.1200");
        assert_eq!((line.channel.as_deref(), line.newer, line.downgrade), (Some("stable"), false, true));

        // A station that never was on the beta is not offered an older one.
        let other = tempfile::tempdir().unwrap();
        let stable = installed(other.path(), "1300", None, None);
        let line = station_with(&stable, "0.1.1200");
        assert_eq!((line.channel.as_deref(), line.newer, line.downgrade), (Some("stable"), false, false));
        // Read again in a new process from a config that says beta: the feed it reads is the beta's.
        set_channel_in(&other.path().join("config.json"), other.path(), Channel::Beta).unwrap();
        assert_eq!(installed(other.path(), "1300", None, None).channel(), Channel::Beta);
    }

    #[tokio::test]
    async fn turned_on_the_station_updates_itself_to_each_newer_release_once() {
        let dir = tempfile::tempdir().unwrap();
        let updates = installed(dir.path(), "1300", None, None);
        assert_eq!(station_with(&updates, "0.1.1310").auto, Some(false));
        assert_eq!(updates.to_update_to(), None, "not unless turned on");
        updates.settings.update(|raw| {
            raw.auto_update = Some(true);
            Ok(())
        }).unwrap();
        assert_eq!(station_with(&updates, "0.1.1310").auto, Some(true));
        assert_eq!(updates.to_update_to().as_deref(), Some("0.1.1310"));
        // Already the latest, or the latest is older: nothing.
        station_with(&updates, "0.1.1300");
        assert_eq!(updates.to_update_to(), None);
        station_with(&updates, "0.1.1290");
        assert_eq!(updates.to_update_to(), None);
        // A version it went for (and failed to get) is not tried again; the next one is.
        *updates.tried.lock().unwrap() = Some("0.1.1310".into());
        station_with(&updates, "0.1.1310");
        assert_eq!(updates.to_update_to(), None);
        station_with(&updates, "0.1.1320");
        assert_eq!(updates.to_update_to().as_deref(), Some("0.1.1320"));
        // While a runtime installs: not yet, nor by hand (a handover or restart would leave it unfollowed).
        updates.items.lock().unwrap()[Kind::Codex as usize].updating = Some(now_ms());
        assert_eq!(updates.to_update_to(), None);
        assert!(updates.update("station").unwrap_err().to_string().contains("Codex 正在安装"));
        updates.items.lock().unwrap()[Kind::Codex as usize].updating = None;
        assert_eq!(updates.to_update_to().as_deref(), Some("0.1.1320"));
        // While an update goes on: nothing more, nor a runtime installed meanwhile.
        updates.items.lock().unwrap()[Kind::Station as usize].updating = Some(now_ms());
        assert_eq!(updates.to_update_to(), None);
        assert!(updates.update("codex").unwrap_err().to_string().contains("station 正在更新"));

        // Switched back from the beta, the older stable release is offered, but not gone to by itself.
        let other = tempfile::tempdir().unwrap();
        let beta = installed(other.path(), "1300", Some("beta"), None);
        beta.settings.update(|raw| {
            raw.auto_update = Some(true);
            raw.update_channel = Some("stable".into());
            Ok(())
        }).unwrap();
        assert!(station_with(&beta, "0.1.1200").downgrade);
        assert_eq!(beta.to_update_to(), None);
    }

    fn found(real: &str) -> Found {
        Found { on_path: PathBuf::from("/nowhere/bin/x"), real: PathBuf::from(real) }
    }

    #[tokio::test]
    async fn vite_shims_update_the_package_with_their_own_vp() {
        use std::os::unix::fs::{symlink, PermissionsExt};
        let dir = tempfile::tempdir().unwrap();
        let vp = dir.path().join("vp");
        std::fs::write(&vp, "#!/bin/sh\nprintf '%s\\n' \"$@\"\n").unwrap();
        std::fs::set_permissions(&vp, std::fs::Permissions::from_mode(0o755)).unwrap();
        for kind in [Kind::Claude, Kind::Codex] {
            symlink("vp", dir.path().join(kind.command())).unwrap();
            let env: Env = [("PATH".into(), dir.path().display().to_string())].into();
            let found = find_command(kind.command(), &env).unwrap();
            let how = how_to_update(kind, &found, &env).unwrap();
            let args: Vec<&str> = how.args.iter().map(String::as_str).collect();
            let (ok, said) = run(&how.program, &args, &env, Duration::from_secs(10)).await.unwrap();
            assert!(ok);
            assert_eq!(said, format!("install\n-g\n{}@latest\n", kind.package()));
        }
    }

    #[tokio::test]
    async fn standalone_update_preserves_the_actual_home_and_path_with_shell_characters() {
        use std::os::unix::fs::{symlink, PermissionsExt};
        let dir = tempfile::tempdir().unwrap();
        let home = dir.path().join("custom codex ' $home");
        let real = home.join("packages/standalone/releases/0.155.1-aarch64-apple-darwin/bin/codex");
        let bin = dir.path().join("visible bin ' $bin");
        std::fs::create_dir_all(real.parent().unwrap()).unwrap();
        std::fs::create_dir_all(&bin).unwrap();
        std::fs::write(&real, "#!/bin/sh\necho 'codex-cli 0.155.1'\n").unwrap();
        std::fs::set_permissions(&real, std::fs::Permissions::from_mode(0o755)).unwrap();
        symlink(&real, bin.join("codex")).unwrap();
        // Supply a harmless installer instead of downloading or changing any real installation.
        let curl = bin.join("curl");
        std::fs::write(&curl, r#"#!/bin/sh
cat <<'INSTALLER'
test "$CODEX_NON_INTERACTIVE" = 1 || exit 1
test "$1" = --release && test "$2" = latest || exit 2
printf '%s\n' "$CODEX_HOME" "$CODEX_INSTALL_DIR"
INSTALLER
"#).unwrap();
        std::fs::set_permissions(&curl, std::fs::Permissions::from_mode(0o755)).unwrap();
        let env: Env = [("PATH".into(), format!("{}:/usr/bin:/bin", bin.display())), ("CODEX_HOME".into(), "/wrong/home".into())].into();
        let found = find_command("codex", &env).unwrap();
        let how = how_to_update(Kind::Codex, &found, &env).unwrap();
        let args: Vec<&str> = how.args.iter().map(String::as_str).collect();
        let (ok, said) = run(&how.program, &args, &env, Duration::from_secs(10)).await.unwrap();
        assert!(ok, "{said}");
        assert_eq!(said, format!("{}\n{}\n", home.canonicalize().unwrap().display(), bin.display()));
        assert!(how_to_update(Kind::Codex, &Found { on_path: real.clone(), real }, &env).is_err());
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
        assert_eq!(by_npm, How::new(&npm, &["install", "-g", "@openai/codex@latest", "--prefix", "/Users/a/.nvm/versions/node/v24"]));
        let claude_npm = how_to_update(Kind::Claude, &found("/Users/a/node/lib/node_modules/@anthropic-ai/claude-code/cli.js"), &env).unwrap();
        assert_eq!(claude_npm, How::new(&npm, &["install", "-g", "@anthropic-ai/claude-code@latest", "--prefix", "/Users/a/node"]));
        // Linked from a directory beside another Node's npm: its own Node's npm, not that one.
        let node = dir.path().join("node/v24.3.0");
        std::fs::create_dir_all(node.join("bin")).unwrap();
        std::fs::write(node.join("bin/npm"), "").unwrap();
        let linked = Found { on_path: dir.path().join("codex"), real: node.join("lib/node_modules/@openai/codex/bin/codex.js") };
        let mut how = how_to_update(Kind::Codex, &linked, &env).unwrap();
        assert_eq!(how, How::new(node.join("bin/npm"), &["install", "-g", "@openai/codex@latest", "--prefix", &node.to_string_lossy()]));
        how.pin_npm_version("@openai/codex", "0.159.3");
        assert_eq!(how.args, ["install", "-g", "@openai/codex@0.159.3", "--prefix", &node.to_string_lossy(), "--prefer-online"]);
        assert!(how_to_update(Kind::Codex, &found("/project/node_modules/@openai/codex/bin/codex.js"), &env).unwrap_err().contains("全局安装目录"));
        assert!(how_to_update(Kind::Codex, &found("/usr/local/bin/codex"), &env).unwrap_err().contains("自己更新"));
        assert_eq!(how_to_install(Kind::Codex, &env).unwrap(), How::new(&npm, &["install", "-g", "@openai/codex@latest"]));
        let bare: Env = [("PATH".to_string(), "/nowhere".to_string())].into();
        assert!(how_to_install(Kind::Codex, &bare).unwrap_err().contains("Node"));
        assert_eq!(how_to_install(Kind::Claude, &bare).unwrap().program, PathBuf::from("/bin/sh"));
    }
}
