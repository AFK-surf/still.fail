//! Words the Rust station (mesh/) shares with what the clients are told: runtimes, accounts, connect modes, software
//! versions, and how models, providers and reasoning levels are read (model.rs, providers.rs, reasoning.rs).
//!
//! What the core gives its clients is declared in client/core-ts/src/shapes/schema.ts (the clients' types are made
//! from it); this crate is not where it is declared any more. Keep these as that schema has them.

pub mod model;
pub mod providers;
pub mod reasoning;

use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;

/// A runtime.
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[serde(rename_all = "lowercase")]
pub enum RuntimeKind {
    Claude,
    Codex,
}

/// Whose account a profile runs on.
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum AccessKind {
    Subscription,
    OpencodeGo,
    AnthropicApi,
    Env,
    /// A key for one of the providers in providers.rs (`Access.provider`). A station says `env` of it where an older
    /// core would read the overview (the core takes it back by `provider`), so an older client stays whole.
    ApiProvider,
}

/// How a connect's conversations become sessions.
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum ConnectMode {
    MultiSession,
    SingleSession,
}

/// A piece of software on a station and whether a newer one is out (updates.rs): the station itself (`station`) or a
/// runtime (`claude`, `codex`).
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SoftwareVersion {
    /// station | claude | codex
    pub id: String,
    pub name: String,
    /// On the machine (a runtime may not be: then `updatable` says it can be installed from here).
    pub installed: bool,
    /// What runs now; none when it is not installed, or not a release (a clone).
    pub version: Option<String>,
    /// The latest out, when it could be read.
    pub latest: Option<String>,
    /// The latest is newer than what runs.
    pub newer: bool,
    /// The station's, switched back from the test channel: the latest is the stable release, older than the beta that
    /// runs, and going back to it is offered (回到正式版). False from a station older than channels.
    #[serde(default)]
    pub downgrade: bool,
    /// The station's: which releases it is updated to, `stable` or `beta`; none where it cannot be updated from here,
    /// and from a station older than channels.
    pub channel: Option<String>,
    /// The station's: whether it updates itself when a newer release of its channel is out (自动更新); none where it
    /// cannot be updated from here, and from a station older than it.
    pub auto: Option<bool>,
    /// Automatic updates wait for clients and running turns to leave, then five quiet minutes.
    pub idle_only: Option<bool>,
    /// The pages can update it (or install it, when it is not installed).
    pub updatable: bool,
    /// Why it cannot be updated from here (the desktop app's station, a runtime installed another way…).
    pub note: Option<String>,
    /// idle | updating | failed
    pub state: String,
    /// The station's, while it is updating: where the update is, in a line (正在下载新版本…). None from a station
    /// older than it, or an installer that does not say.
    pub progress: Option<String>,
    /// A runtime's, while what its install or update downloads comes in: how much of it is, 0–100 (drawn as a bar
    /// beside `progress`). None when that is not known, and from a station older than it.
    pub percent: Option<i64>,
    /// The station's, for a while after an update ended well: how it went (已更新到 0.1.1300，agent 没有中断).
    pub done: Option<String>,
    /// What the last update that failed said.
    pub message: Option<String>,
    /// When what is out was last read.
    pub checked_at: Option<i64>,
}
