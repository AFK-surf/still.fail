//! Configuration comes from one JSON file: $STILLFAIL_CONFIG, else <dataDir>/config.json with dataDir from
//! $STILLFAIL_DATA (default ~/.stillfail; the EMBER_* names too, and ~/.ember moved there: former.rs).
//!
//! A connect is one way in: today a Slack app. Each connect is bound to one model (runtime + account + model) and decides
//! how conversations map to sessions. Profiles are the runtime accounts connects draw from; connects may share them.
//!
//! `RawConfig` is config.json as written — what the admin API edits, keeping whatever it does not know — and `Config` is
//! it checked and filled in.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use anyhow::{Result, bail};
use stillfail_shapes::{AccessKind, ConnectMode, RuntimeKind};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::profiles::{access_env, access_kinds, keyed, runtimes_of};

pub const RUNTIMES: [RuntimeKind; 2] = [RuntimeKind::Claude, RuntimeKind::Codex];

/// The runtime a stored name is (sessions keep it as text).
pub fn runtime_named(name: &str) -> Option<RuntimeKind> {
    RUNTIMES.into_iter().find(|r| runtime_name(*r) == name)
}

pub fn runtime_name(runtime: RuntimeKind) -> &'static str {
    match runtime {
        RuntimeKind::Claude => "claude",
        RuntimeKind::Codex => "codex",
    }
}

// ── config.json as written ─────────────────────────────────────────────────

/// config.json as written. Fields it does not know are kept (`rest`), so an edit writes them back.
#[derive(Serialize, Deserialize, Debug, Clone, Default, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RawConfig {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agent_home: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub http: Option<RawHttp>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub connects: Option<Vec<RawConnect>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub slack_config_tokens: Option<Vec<ConfigToken>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub slack_apps: Option<Vec<SlackAppMade>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profiles: Option<Vec<RawProfile>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_nudges: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub warm_minutes: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_warm_claude: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub auto_archive_days: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub telemetry: Option<RawTelemetry>,
    /// Which releases the station is updated to (updates.rs): `stable` or `beta`; none: as its release was installed.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub update_channel: Option<String>,
    /// Whether the station updates itself when a newer release of its channel is out (updates.rs); none: it does not.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub auto_update: Option<bool>,
    #[serde(flatten)]
    pub rest: Map<String, Value>,
}

#[derive(Serialize, Deserialize, Debug, Clone, Default, PartialEq)]
pub struct RawHttp {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub host: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub port: Option<u16>,
}

#[derive(Serialize, Deserialize, Debug, Clone, Default, PartialEq)]
pub struct RawTelemetry {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub errors: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub traces: Option<bool>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RawConnect {
    pub id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub enabled: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mode: Option<ConnectMode>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub require_mention: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub slack: Option<RawSlack>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created_by: Option<Owner>,
    pub bind: RawBind,
    #[serde(flatten)]
    pub rest: Map<String, Value>,
}

#[derive(Serialize, Deserialize, Debug, Clone, Default, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RawSlack {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub app_token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bot_token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub app_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub team: Option<RawPlace>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bot_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bot_image: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone, Default, PartialEq)]
pub struct RawPlace {
    #[serde(default)]
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct RawBind {
    pub runtime: RuntimeKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub effort: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profile: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct Owner {
    pub id: String,
    #[serde(default)]
    pub name: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RawProfile {
    pub id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// Needed for a subscription (which one) and custom variables; keyed kinds run every runtime they can.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub runtime: Option<RuntimeKind>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub access: Option<RawProfileAccess>,
    pub home: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub env: Option<BTreeMap<String, String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub models: Option<Vec<String>>,
    /// Uses this machine's own login of its runtime (a subscription profile of one runtime).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub machine: Option<bool>,
    /// Absent: on (Profile::background_on_message).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub background_on_message: Option<bool>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct RawProfileAccess {
    pub kind: AccessKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub key: Option<String>,
}

/// A Slack app configuration token, a person's own (`by`), for one Slack workspace: the station makes and edits apps there.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ConfigToken {
    pub access_token: String,
    pub refresh_token: String,
    /// Epoch ms when the access token stops working.
    pub expires_at: i64,
    /// The Slack workspace it makes apps in.
    pub team_id: String,
    /// The still.fail user who added it (an email, or "local"): only they see it and use it.
    pub by: String,
    /// Whose token it is, and where, as Slack shows them (read when it is added): what tells tokens apart.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub owner: Option<ConfigTokenOwner>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ConfigTokenOwner {
    pub team: String,
    pub team_domain: Option<String>,
    pub team_icon: Option<String>,
    pub user: String,
    pub email: Option<String>,
    pub image: Option<String>,
}

/// A Slack app the station made with someone's configuration token (`by`), waiting for its connect. Made to be installed
/// through Slack's OAuth (`oauth`: a station in still.fail cloud), Slack's code comes back here and becomes its bot token;
/// else its tokens are copied from Slack by hand.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SlackAppMade {
    pub app_id: String,
    pub name: String,
    /// The Slack workspace it was made in.
    pub team_id: String,
    pub by: String,
    pub created: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub oauth: Option<SlackAppOauth>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SlackAppOauth {
    /// The install link's state: which station and install it is.
    pub state: String,
    pub client_id: String,
    pub client_secret: String,
    pub redirect_uri: String,
    /// The link that installs it.
    pub install: String,
    /// Once installed.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bot_token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub installed_team: Option<String>,
}

// ── checked and filled in ──────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq)]
pub struct Profile {
    pub id: String,
    /// Shown instead of the id.
    pub name: String,
    /// The runtime a subscription signs in with (or custom variables are for); for a keyed profile, its first runtime.
    pub runtime: RuntimeKind,
    /// The runtimes it can run: the station sets each one up for the account (runtimes_of).
    pub runtimes: Vec<RuntimeKind>,
    pub access_kind: AccessKind,
    /// Set for keyed kinds.
    pub key: String,
    /// The runtimes' config home: CLAUDE_CONFIG_DIR and CODEX_HOME (their files do not overlap).
    pub home: PathBuf,
    /// The environment for this profile's processes, by runtime: what the access kind needs there plus `custom_env`.
    /// In values, `{route}` is replaced with a per-session routing id (claude) or the profile id (codex).
    pub envs: BTreeMap<&'static str, BTreeMap<String, String>>,
    /// Variables set by hand; they win over derived ones.
    pub custom_env: BTreeMap<String, String>,
    pub model: Option<String>,
    /// Models this profile may be used for, chosen by hand from what its check found. None until someone picks.
    pub models: Vec<String>,
    /// Uses this machine's own login of its runtime: not edited or signed in here; removing it stops using that login.
    pub machine: bool,
    /// A message that reaches a running Claude Code turn first moves the commands and subagents it waits on to the
    /// background (Ctrl+B), so it is read now rather than when they end.
    pub background_on_message: bool,
}

impl Profile {
    /// Its own spelling of a model it has enabled, however the model is spelled (gpt-6-astra here may be
    /// openai/gpt-6-astra there: stillfail_shapes::model::key).
    pub fn spelling(&self, model: &str) -> Option<&str> {
        self.models.iter().find(|m| *m == model).or_else(|| self.models.iter().find(|m| stillfail_shapes::model::same(m, model))).map(String::as_str)
    }

    /// Whether it has a model enabled, in any spelling.
    pub fn runs(&self, model: &str) -> bool {
        self.spelling(model).is_some()
    }

    pub fn env(&self, runtime: RuntimeKind) -> BTreeMap<String, String> {
        self.envs.get(runtime_name(runtime)).cloned().unwrap_or_default()
    }
}

/// A Slack workspace, as a connect last saw it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SlackPlace {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct SlackTokens {
    pub app_token: String,
    pub bot_token: String,
    pub app_id: Option<String>,
    pub team: Option<SlackPlace>,
    pub bot_name: Option<String>,
    pub bot_image: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Binding {
    pub runtime: RuntimeKind,
    /// How hard the model thinks; the runtime's default when absent.
    pub effort: Option<String>,
    /// Sessions run on the profiles of `runtime` that have this model enabled, picked per session (pool).
    pub model: Option<String>,
    /// Kept to this profile, when set: its sessions start pinned to it instead of the pool's pick.
    pub profile: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Connect {
    /// Stable id; part of session keys, so do not rename a connect that has sessions.
    pub id: String,
    /// A disabled connect keeps its config and sessions but is not connected.
    pub enabled: bool,
    pub kind: String,
    pub mode: ConnectMode,
    /// single-session only: whether starting on a new thread needs an @mention.
    pub require_mention: bool,
    pub slack: SlackTokens,
    /// Who added it from the admin page: an email, or "local"; absent for older or hand-written ones.
    pub created_by: Option<Owner>,
    pub bind: Binding,
}

impl Connect {
    /// What a connect is called: its bot's name in its Slack workspace, else its id.
    pub fn name(&self) -> &str {
        self.slack.bot_name.as_deref().filter(|n| !n.is_empty()).unwrap_or(&self.id)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Http {
    pub host: String,
    pub port: u16,
    /// The config sets the port (else it is the usual one, which gives way when taken).
    pub named: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Config {
    pub data_dir: PathBuf,
    pub slack_config_tokens: Vec<ConfigToken>,
    /// Slack apps the station made that no connect has taken yet: kept until one does (or someone drops it).
    pub slack_apps: Vec<SlackAppMade>,
    /// Shared MEMORY.md and skills/ linked into every profile home.
    pub agent_home: PathBuf,
    /// Agents' MCP endpoint.
    pub http: Http,
    pub connects: Vec<Connect>,
    pub profiles: Vec<Profile>,
    /// How many times a turn that ended without final/block is nudged before giving up.
    pub max_nudges: u32,
    /// Idle claude processes kept alive at most this long before they may be evicted.
    pub warm_ms: u64,
    /// Idle claude processes beyond this count are evicted, oldest first, once past warm_ms.
    pub max_warm_claude: u32,
    /// Chats idle this long, and done (Hub::auto_archive), are archived by the station; 0: never.
    pub auto_archive_ms: u64,
    /// What this station sends still.fail: errors to PostHog; traces to still.fail cloud.
    pub telemetry_errors: bool,
    pub telemetry_traces: bool,
}

/// Where the station keeps its data and its config file, by the environment: $STILLFAIL_DATA (default ~/.stillfail)
/// and $STILLFAIL_CONFIG (default <data>/config.json), else their EMBER_* names. Where they are, not moving anything
/// (former::data_dir does, as the station starts).
pub fn paths(env: impl Fn(&str) -> Option<String>) -> (PathBuf, PathBuf) {
    let home = env("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("."));
    let data = crate::former::var_in(&env, "DATA").map(PathBuf::from).unwrap_or_else(|| home.join(crate::former::DATA_DIR));
    let config = crate::former::var_in(&env, "CONFIG").map(PathBuf::from).unwrap_or_else(|| data.join("config.json"));
    (data, config)
}

/// config.json as written; an absent file is an empty config.
pub fn read_raw(path: &Path) -> Result<RawConfig> {
    if !path.exists() {
        return Ok(RawConfig::default());
    }
    Ok(serde_json::from_str(&std::fs::read_to_string(path)?)?)
}

fn id_ok(id: &str) -> bool {
    let mut chars = id.chars();
    matches!(chars.next(), Some(c) if c.is_ascii_lowercase() || c.is_ascii_digit())
        && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

fn under(data_dir: &Path, path: &str) -> PathBuf {
    let p = Path::new(path);
    if p.is_absolute() { p.to_path_buf() } else { data_dir.join(p) }
}

pub fn parse_config(raw: &RawConfig, data_dir: &Path) -> Result<Config> {
    let mut profiles = Vec::new();
    for p in raw.profiles.iter().flatten() {
        if !id_ok(&p.id) {
            bail!("profile id {}: use lowercase letters, digits and dashes", serde_json::to_string(&p.id)?);
        }
        if p.home.is_empty() {
            bail!("profile {}: home is required", p.id);
        }
        let kind = p.access.as_ref().map(|a| a.kind).unwrap_or(AccessKind::Env);
        let runtimes = runtimes_of(kind, p.runtime);
        let kind_name = serde_json::to_value(kind)?.as_str().unwrap_or_default().to_string();
        if runtimes.is_empty() {
            bail!("profile {}: {kind_name} needs a runtime (claude or codex)", p.id);
        }
        if !runtimes.iter().all(|r| access_kinds(*r).contains(&kind)) {
            let names: Vec<&str> = runtimes.iter().map(|r| runtime_name(*r)).collect();
            bail!("profile {}: {} cannot use access {kind_name}", p.id, names.join("/"));
        }
        let key = p.access.as_ref().and_then(|a| a.key.as_deref()).unwrap_or("").trim().to_string();
        if keyed(kind) && key.is_empty() {
            bail!("profile {}: access {kind_name} needs a key", p.id);
        }
        let custom_env = p.env.clone().unwrap_or_default();
        let envs = runtimes
            .iter()
            .map(|r| {
                let mut env = access_env(*r, kind, &key, p.model.as_deref());
                env.extend(custom_env.clone());
                (runtime_name(*r), env)
            })
            .collect();
        let mut seen = BTreeSet::new();
        let models = p
            .models
            .iter()
            .flatten()
            .map(|m| m.trim().to_string())
            .filter(|m| !m.is_empty() && seen.insert(m.clone()))
            .collect();
        profiles.push(Profile {
            id: p.id.clone(),
            name: p.name.as_deref().map(str::trim).filter(|n| !n.is_empty()).unwrap_or(&p.id).to_string(),
            runtime: runtimes[0],
            runtimes,
            access_kind: kind,
            key,
            home: under(data_dir, &p.home),
            envs,
            custom_env,
            model: p.model.clone().filter(|m| !m.is_empty()),
            models,
            machine: p.machine == Some(true),
            background_on_message: p.background_on_message != Some(false),
        });
    }
    unique("profile", profiles.iter().map(|p| p.id.as_str()))?;

    let mut connects = Vec::new();
    for c in raw.connects.iter().flatten() {
        if !id_ok(&c.id) {
            bail!("connect id {}: use lowercase letters, digits and dashes", serde_json::to_string(&c.id)?);
        }
        let kind = c.kind.clone().unwrap_or_else(|| "slack".into());
        if kind != "slack" {
            bail!("connect {}: unknown kind {kind}", c.id);
        }
        let mode = c.mode.unwrap_or(ConnectMode::MultiSession);
        let runtime = c.bind.runtime;
        if let Some(effort) = c.bind.effort.as_deref().filter(|e| !e.is_empty()) {
            // Codex reports an open set of levels per model, after sign-in. Loading persisted config must
            // not reject a newly advertised level before the account's capabilities have been read.
            let legacy = stillfail_shapes::reasoning::fallback(runtime_name(runtime));
            if runtime != RuntimeKind::Codex && !legacy.contains(&effort) {
                bail!("connect {}: {} has no effort {effort}; use {}", c.id, runtime_name(runtime), legacy.join(", "));
            }
        }
        let slack = c.slack.clone().unwrap_or_default();
        connects.push(Connect {
            id: c.id.clone(),
            enabled: c.enabled.unwrap_or(true),
            kind,
            mode,
            require_mention: if mode == ConnectMode::MultiSession { true } else { c.require_mention.unwrap_or(true) },
            slack: SlackTokens {
                app_token: slack.app_token.unwrap_or_default(),
                bot_token: slack.bot_token.unwrap_or_default(),
                app_id: slack.app_id.filter(|a| !a.is_empty()),
                team: slack.team.filter(|t| !t.id.is_empty()).map(|t| SlackPlace { id: t.id, name: t.name.unwrap_or_default() }),
                bot_name: slack.bot_name.filter(|n| !n.is_empty()),
                bot_image: slack.bot_image.filter(|i| !i.is_empty()),
            },
            created_by: c.created_by.clone().filter(|o| !o.id.is_empty()),
            bind: Binding {
                runtime,
                effort: c.bind.effort.clone().filter(|e| !e.is_empty()),
                model: c.bind.model.clone().filter(|m| !m.is_empty()),
                profile: c.bind.profile.clone().filter(|p| !p.is_empty()),
            },
        });
    }
    unique("connect", connects.iter().map(|c| c.id.as_str()))?;

    Ok(Config {
        data_dir: data_dir.to_path_buf(),
        slack_config_tokens: raw
            .slack_config_tokens
            .iter()
            .flatten()
            .filter(|t| !t.refresh_token.is_empty() && !t.team_id.is_empty() && !t.by.is_empty())
            .cloned()
            .collect(),
        slack_apps: raw.slack_apps.iter().flatten().filter(|a| !a.app_id.is_empty() && !a.by.is_empty()).cloned().collect(),
        agent_home: under(data_dir, raw.agent_home.as_deref().unwrap_or("agent")),
        http: Http {
            host: raw.http.as_ref().and_then(|h| h.host.clone()).unwrap_or_else(|| "127.0.0.1".into()),
            port: raw.http.as_ref().and_then(|h| h.port).unwrap_or(4750),
            named: raw.http.as_ref().is_some_and(|h| h.port.is_some()),
        },
        connects,
        profiles,
        max_nudges: raw.max_nudges.unwrap_or(2),
        warm_ms: (raw.warm_minutes.unwrap_or(30.0) * 60_000.0) as u64,
        max_warm_claude: raw.max_warm_claude.unwrap_or(4),
        auto_archive_ms: (raw.auto_archive_days.unwrap_or(1.0).max(0.0) * 86_400_000.0) as u64,
        telemetry_errors: raw.telemetry.as_ref().and_then(|t| t.errors) == Some(true),
        telemetry_traces: raw.telemetry.as_ref().and_then(|t| t.traces) == Some(true),
    })
}

fn unique<'a>(kind: &str, ids: impl Iterator<Item = &'a str>) -> Result<()> {
    let mut seen = BTreeSet::new();
    for id in ids {
        if !seen.insert(id) {
            bail!("duplicate {kind} id {id}");
        }
    }
    Ok(())
}

/// The profiles a connect's sessions can run on: every profile of its runtime (the pool picks one per session).
pub fn profiles_for<'a>(config: &'a Config, connect: &Connect) -> Vec<&'a Profile> {
    config.profiles.iter().filter(|p| p.runtimes.contains(&connect.bind.runtime)).collect()
}

pub fn expand_route(env: &BTreeMap<String, String>, route: &str) -> BTreeMap<String, String> {
    env.iter().map(|(k, v)| (k.clone(), v.replace("{route}", route))).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(json: &str) -> Result<Config> {
        parse_config(&serde_json::from_str(json)?, Path::new("/data"))
    }

    #[test]
    fn a_config_is_filled_in_from_what_it_says() {
        let config = parse(r#"{
            "profiles": [
                {"id": "cc", "runtime": "claude", "home": "homes/cc", "access": {"kind": "subscription"}},
                {"id": "og", "home": "/abs/og", "access": {"kind": "opencode-go", "key": " k "}, "models": ["a", " a", "b", ""], "env": {"X": "1"}}
            ],
            "connects": [{"id": "ds", "mode": "single-session", "requireMention": false, "bind": {"runtime": "codex", "effort": "high"},
                          "slack": {"appToken": "xapp", "botToken": "xoxb", "team": {"id": "T1", "name": "Acme"}, "botName": "helper"}}],
            "warmMinutes": 5
        }"#).unwrap();
        assert_eq!(config.profiles[0].home, PathBuf::from("/data/homes/cc"));
        assert_eq!(config.profiles[0].runtimes, vec![RuntimeKind::Claude]);
        let og = &config.profiles[1];
        assert_eq!((og.home.clone(), og.key.as_str(), og.models.clone()), (PathBuf::from("/abs/og"), "k", vec!["a".to_string(), "b".to_string()]));
        assert_eq!(og.runtimes, vec![RuntimeKind::Claude, RuntimeKind::Codex]);
        assert_eq!(og.env(RuntimeKind::Codex)["X"], "1");
        assert_eq!(og.env(RuntimeKind::Codex)["OPENCODE_GO_KEY"], "k");
        let ds = &config.connects[0];
        assert_eq!((ds.mode, ds.require_mention, ds.name()), (ConnectMode::SingleSession, false, "helper"));
        assert_eq!(ds.slack.team, Some(SlackPlace { id: "T1".into(), name: "Acme".into() }));
        assert_eq!(config.warm_ms, 300_000);
        assert_eq!(config.agent_home, PathBuf::from("/data/agent"));
        assert_eq!((config.http.port, config.http.named), (4750, false));
    }

    #[test]
    fn what_cannot_run_is_refused_in_words() {
        let err = |json: &str| parse(json).unwrap_err().to_string();
        assert_eq!(err(r#"{"profiles": [{"id": "A", "home": "h"}]}"#), "profile id \"A\": use lowercase letters, digits and dashes");
        assert_eq!(err(r#"{"profiles": [{"id": "a", "home": "h"}]}"#), "profile a: env needs a runtime (claude or codex)");
        assert_eq!(err(r#"{"profiles": [{"id": "a", "home": "h", "access": {"kind": "opencode-go"}}]}"#), "profile a: access opencode-go needs a key");
        assert_eq!(err(r#"{"connects": [{"id": "c", "bind": {"runtime": "claude", "effort": "minimal"}}]}"#), "connect c: claude has no effort minimal; use low, medium, high, xhigh, max");
        assert_eq!(err(r#"{"connects": [{"id": "c", "bind": {"runtime": "claude"}}, {"id": "c", "bind": {"runtime": "claude"}}]}"#), "duplicate connect id c");
    }

    #[test]
    fn what_the_station_does_not_know_in_config_json_is_written_back() {
        let raw: RawConfig = serde_json::from_str(r#"{"future": {"x": 1}, "connects": [{"id": "c", "bind": {"runtime": "claude"}, "later": true}]}"#).unwrap();
        let back = serde_json::to_value(&raw).unwrap();
        assert_eq!(back["future"]["x"], 1);
        assert_eq!(back["connects"][0]["later"], true);
    }

    #[test]
    fn the_cloudflare_access_setting_of_before_opens_and_is_kept_as_it_was() {
        let json = r#"{"admin": {"access": {"teamDomain": "afk", "aud": "a"}}, "connects": []}"#;
        assert!(parse(json).is_ok());
        let raw: RawConfig = serde_json::from_str(json).unwrap();
        assert_eq!(serde_json::to_value(&raw).unwrap()["admin"]["access"]["teamDomain"], "afk");
    }
}
