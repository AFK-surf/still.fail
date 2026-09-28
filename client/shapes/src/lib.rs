//! What the core gives its clients, declared once. The web's and Android's types are generated from these
//! (scripts/shapes.sh: web/src/core/shapes.ts, apps/android/.../data/Shapes.kt), and every value the core sends on a
//! topic passes through its shape first (`conform`): a field a client reads is here, with its type, or it is not
//! sent. Whole numbers (times in ms, counts) are `i64`, sent as whole numbers; an absent `Option` is left out.
//!
//! Station shapes are as src/admin/types.ts has them; what the core puts in for the clients to show is marked so
//! (client/core/src/present.rs, format.rs, views.rs, history.rs, activity.rs).

pub mod model;

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use serde_with::skip_serializing_none;
use typeshare::typeshare;

// ── closed sets of words ──────────────────────────────────────────────────

/// A runtime.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[serde(rename_all = "lowercase")]
pub enum RuntimeKind {
    Claude,
    Codex,
}

/// Whose account a profile runs on.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum AccessKind {
    Subscription,
    OpencodeGo,
    AnthropicApi,
    Env,
}

/// How a connect's conversations become sessions.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum ConnectMode {
    MultiSession,
    SingleSession,
}

/// A colour of meaning.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Tone {
    Accent,
    Green,
    Blue,
    Red,
    Amber,
    Neutral,
}

/// A link's dot.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Presence {
    Online,
    Busy,
    Error,
    Offline,
}

/// How full something is.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Level {
    Ok,
    Amber,
    Red,
}

/// Where an agent stands.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Running,
    Queued,
    Final,
    Block,
    Failed,
    Aborted,
    Unexpected,
    Idle,
}

/// An agent's mark: at work, blocked, failed.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Badge {
    Run,
    Block,
    Failed,
}

// ── words the core puts in ───────────────────────────────────────────────

/// A moment in words, fresh each minute: 3 分钟前 (`ago`), 9/20 14:05:09 (`full`), 3 小时后 (`until`), whether it has come.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Stamp {
    pub at: f64,
    pub ago: String,
    pub full: String,
    pub until: String,
    pub past: bool,
}


/// Who made a model, for its mark; absent when the marks do not know it (the runtime's stands in).
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct Maker {
    pub id: String,
    pub name: String,
}

/// A person as the core names them: `display` is 你 for the viewer.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct PersonShown {
    pub name: String,
    pub display: String,
    pub picture: Option<String>,
    pub mine: bool,
}

// ── station shapes ───────────────────────────────────────────────────────

/// Who started a session or chat, or added a connect: "local", an email, or "slack:<connect>:<user>".
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Creator {
    pub id: String,
    pub name: String,
    pub email: Option<String>,
    /// local | cloud | slack
    pub via: String,
    /// As the core names them.
    pub shown: Option<PersonShown>,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TurnSummary {
    pub kind: String,
    pub outcome: Option<String>,
    pub declared: Option<String>,
    pub detail: Option<String>,
    #[typeshare(serialized_as = "I54")]
    pub started_at: i64,
    #[typeshare(serialized_as = "Option<I54>")]
    pub ended_at: Option<i64>,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TurnRecord {
    pub id: String,
    pub kind: String,
    pub outcome: Option<String>,
    pub declared: Option<String>,
    pub detail: Option<String>,
    #[typeshare(serialized_as = "I54")]
    pub started_at: i64,
    #[typeshare(serialized_as = "Option<I54>")]
    pub ended_at: Option<i64>,
}

/// A session, with what the clients show of it. Before its details are read an agent is only what the sidebar's rows
/// say of it (key, runtime, model, effort, process, pending, last turn): the rest is absent then.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Session {
    pub key: String,
    pub connect: Option<String>,
    /// thread | all
    pub scope: Option<String>,
    pub title: Option<String>,
    pub created_by: Option<String>,
    pub bound_to: Option<Vec<String>>,
    pub creator: Option<Creator>,
    pub participants: Option<Vec<Creator>>,
    /// claude | codex
    pub runtime: RuntimeKind,
    pub profile: Option<String>,
    pub profile_pinned: Option<bool>,
    pub model: Option<String>,
    pub effort: Option<String>,
    pub runtime_session_id: Option<String>,
    pub workspace: Option<String>,
    pub running: Option<bool>,
    #[typeshare(serialized_as = "Option<I54>")]
    pub created_at: Option<i64>,
    #[typeshare(serialized_as = "Option<I54>")]
    pub last_active_at: Option<i64>,
    #[typeshare(serialized_as = "Option<I54>")]
    pub archived_at: Option<i64>,
    /// running | warm | cold
    pub process: String,
    #[typeshare(serialized_as = "Option<I54>")]
    pub turns: Option<i64>,
    #[typeshare(serialized_as = "I54")]
    pub pending: i64,
    pub first_text: Option<String>,
    pub last_turn: Option<TurnSummary>,
    // What the core says of it.
    pub status_text: String,
    /// accent | green | blue | red | neutral
    pub tone: Tone,
    /// Its mark (run | block | failed), and in words.
    pub mark: Option<Badge>,
    pub badge_text: Option<String>,
    pub title_text: String,
    pub agent_text: String,
    /// Its model as people call it (Opus 5.5).
    pub model_name: Option<String>,
    pub maker: Option<Maker>,
    pub runtime_text: String,
    pub process_text: Option<String>,
    /// How hard its runtime can think, lowest first.
    pub efforts: Vec<String>,
    /// Its times in words, by field (`createdAt`, `lastActiveAt`, …).
    pub time: Option<HashMap<String, Stamp>>,
    /// On a connect's page: the chat it was last talked in; as a candidate to deliver into, described, and whether it
    /// is the one now.
    #[typeshare(serialized_as = "Option<I54>")]
    pub chat: Option<i64>,
    pub description: Option<String>,
    pub current: Option<bool>,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Membership {
    #[typeshare(serialized_as = "I54")]
    pub thread: i64,
    pub session: String,
    pub connect: String,
    #[typeshare(serialized_as = "I54")]
    pub joined_at: i64,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Attachment {
    pub name: String,
    pub path: String,
    #[typeshare(serialized_as = "I54")]
    pub size: i64,
    #[typeshare(serialized_as = "Option<I54>")]
    pub width: Option<i64>,
    #[typeshare(serialized_as = "Option<I54>")]
    pub height: Option<i64>,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Quote {
    pub author: String,
    pub text: String,
    pub comment: String,
    pub ts: Option<String>,
    /// agent | person
    pub role: Option<String>,
}

/// Who said a message, as its line shows them: an agent by its label and mark, a person by name and picture.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MessageBy {
    pub name: String,
    pub agent: Option<String>,
    pub maker: Option<Maker>,
    pub runtime: Option<RuntimeKind>,
    pub picture: Option<String>,
}

/// A message as merged from its thread's entries. In a chat, the core says whose it is and who said it.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Message {
    #[typeshare(serialized_as = "I54")]
    pub seq: i64,
    #[typeshare(serialized_as = "I54")]
    pub thread: i64,
    pub ts: String,
    /// person | agent | ember
    pub author_kind: String,
    pub author: String,
    pub author_name: Option<String>,
    pub text: String,
    pub attachments: Vec<Attachment>,
    pub quotes: Vec<Quote>,
    pub declared: Option<String>,
    #[typeshare(serialized_as = "I54")]
    pub created_at: i64,
    #[typeshare(serialized_as = "Option<I54>")]
    pub edited_at: Option<i64>,
    /// Its times in words, by field (`createdAt`, `lastActiveAt`, …).
    pub time: Option<HashMap<String, Stamp>>,
}

/// A message of a chat, with what the core decides of it: the viewer's (their bubble), ember's own notice, who said
/// it, and whether its agents have yet to take it.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ChatMessage {
    #[typeshare(serialized_as = "I54")]
    pub seq: i64,
    #[typeshare(serialized_as = "I54")]
    pub thread: i64,
    pub ts: String,
    /// person | agent | ember
    pub author_kind: String,
    pub author: String,
    pub author_name: Option<String>,
    pub text: String,
    pub attachments: Vec<Attachment>,
    pub quotes: Vec<Quote>,
    pub declared: Option<String>,
    #[typeshare(serialized_as = "I54")]
    pub created_at: i64,
    #[typeshare(serialized_as = "Option<I54>")]
    pub edited_at: Option<i64>,
    pub mine: bool,
    pub system: bool,
    pub by: MessageBy,
    pub waiting: bool,
    /// Its times in words, by field (`createdAt`).
    pub time: Option<HashMap<String, Stamp>>,
}

/// A thread: a Slack thread or a chat on ember's page.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ChatThread {
    #[typeshare(serialized_as = "I54")]
    pub id: i64,
    /// "slack:<team id>" or "ember".
    pub surface: String,
    pub channel: String,
    pub channel_name: Option<String>,
    pub thread_ts: String,
    pub title: Option<String>,
    pub created_by: Option<String>,
    pub creator: Option<Creator>,
    #[typeshare(serialized_as = "I54")]
    pub created_at: i64,
    pub sessions: Vec<Membership>,
    #[typeshare(serialized_as = "I54")]
    pub last: i64,
    pub last_message: Option<Message>,
    #[typeshare(serialized_as = "I54")]
    pub read: i64,
    #[typeshare(serialized_as = "I54")]
    pub unread: i64,
    pub people: Vec<Creator>,
    pub first_text: Option<String>,
    /// Its times in words, by field (`createdAt`, `lastActiveAt`, …).
    pub time: Option<HashMap<String, Stamp>>,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SlackIdentity {
    pub team: String,
    pub team_id: String,
    pub url: String,
    pub bot_user_id: String,
    pub bot_name: String,
    /// Its bot's picture (the app's icon), when Slack says.
    #[serde(default)]
    pub bot_image: Option<String>,
}

/// A connect's link to Slack: disabled | no_tokens | starting | connected | reconnecting (`botUserId`, `lastError`,
/// `workspace`) | error (`error`).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ConnectState {
    pub state: String,
    pub bot_user_id: Option<String>,
    pub last_error: Option<String>,
    pub workspace: Option<SlackIdentity>,
    pub error: Option<String>,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Bind {
    pub runtime: RuntimeKind,
    pub model: Option<String>,
    pub effort: Option<String>,
    pub profile: Option<String>,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SlackTokens {
    pub app_token: String,
    pub bot_token: String,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Owner {
    pub id: String,
    pub name: String,
    /// As the core names them.
    pub shown: Option<PersonShown>,
}

/// A connect, with its state and how it runs in words.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Connect {
    pub id: String,
    pub name: String,
    pub team: Option<String>,
    /// Its bot's picture in Slack, as last seen.
    #[serde(default)]
    pub bot_image: Option<String>,
    pub enabled: bool,
    pub kind: String,
    /// multi-session | single-session
    pub mode: ConnectMode,
    pub require_mention: bool,
    pub bind: Bind,
    pub slack: SlackTokens,
    pub connection: ConnectState,
    pub created_by: Option<Owner>,
    #[typeshare(serialized_as = "I54")]
    pub sessions: i64,
    pub session: Option<String>,
    // What the core says of it.
    pub status_text: String,
    /// online | busy | error | offline
    pub presence: Presence,
    pub mode_text: String,
    pub mode_short: String,
    pub runtime_text: String,
    pub run_text: String,
    /// Its bound model as people call it (Opus 5.5).
    pub model_name: Option<String>,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct EnvVar {
    pub key: String,
    pub secret: bool,
    pub value: String,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Access {
    /// subscription | opencode-go | anthropic-api | env
    pub kind: AccessKind,
    pub key: String,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProfileCheck {
    /// ok | login | failed | unknown
    pub state: String,
    pub detail: String,
    pub models: Option<Vec<String>>,
    #[typeshare(serialized_as = "I54")]
    pub checked_at: i64,
    /// Its times in words, by field (`createdAt`, `lastActiveAt`, …).
    pub time: Option<HashMap<String, Stamp>>,
}

/// A quota window, as drawn: its mark (5H, W), what is left, how full (ok | amber | red), when it refills in words.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QuotaWindow {
    pub label: String,
    pub used_percent: f64,
    #[typeshare(serialized_as = "Option<I54>")]
    pub resets_at: Option<i64>,
    pub mark: String,
    #[typeshare(serialized_as = "I54")]
    pub left: i64,
    pub level: Level,
    pub refills: Option<String>,
    /// Its times in words, by field (`createdAt`, `lastActiveAt`, …).
    pub time: Option<HashMap<String, Stamp>>,
}

/// An allowance: its windows shortest first.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Quota {
    /// ok | unsupported | unavailable | blocked (the provider refuses the account)
    pub state: String,
    pub windows: Vec<QuotaWindow>,
    pub detail: Option<String>,
    #[typeshare(serialized_as = "I54")]
    pub checked_at: i64,
    /// Its times in words, by field (`createdAt`, `lastActiveAt`, …).
    pub time: Option<HashMap<String, Stamp>>,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LoginJob {
    pub profile: String,
    pub runtime: RuntimeKind,
    /// starting | needs_code | needs_approval | verifying | done | failed | cancelled
    pub state: String,
    pub url: Option<String>,
    pub user_code: Option<String>,
    pub error: Option<String>,
    #[typeshare(serialized_as = "I54")]
    pub started_at: i64,
    #[typeshare(serialized_as = "I54")]
    pub expires_at: i64,
}

/// A profile, with its last check in words and its models' makers.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Profile {
    pub id: String,
    pub name: String,
    pub runtime: RuntimeKind,
    pub runtimes: Vec<RuntimeKind>,
    pub access: Access,
    pub home: String,
    pub home_exists: bool,
    pub model: Option<String>,
    pub models: Vec<String>,
    pub env: Vec<EnvVar>,
    pub used_by: Vec<String>,
    pub login_command: String,
    /// On the machine's own login of its runtime: not edited (but for its models) or signed in here; removing it stops using that login.
    #[serde(default)]
    pub machine: bool,
    pub check: Option<ProfileCheck>,
    pub login: Option<LoginJob>,
    pub quota: Option<Quota>,
    // What the core says of it.
    pub check_text: String,
    pub check_tone: Tone,
    /// The makers of its models, and of those its check found, by model.
    pub makers: HashMap<String, Option<Maker>>,
    /// Its models, its default and those its check found as people call them (Opus 5.5), by model.
    pub names: HashMap<String, String>,
    /// Its models and those its check found, by series (Claude's biggest first, the rest by name; 其他 last), newest
    /// first: how the list to enable them from is laid out.
    pub series: Vec<ModelSeries>,
    /// How many of the models it could run are enabled, in words.
    pub models_text: String,
}

/// Models of one series (Opus), newest first.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ModelSeries {
    pub name: String,
    pub models: Vec<String>,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AgentProcess {
    #[typeshare(serialized_as = "I54")]
    pub pgid: i64,
    #[typeshare(serialized_as = "I54")]
    pub started_at: i64,
    pub runtime: RuntimeKind,
    pub label: String,
    pub rss_mb: Option<f64>,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Counts {
    #[typeshare(serialized_as = "I54")]
    pub sessions: i64,
    #[typeshare(serialized_as = "I54")]
    pub running: i64,
    #[typeshare(serialized_as = "I54")]
    pub warm: i64,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MeshStatus {
    /// off | missing | running | restarting
    pub state: String,
    pub origin: Option<String>,
    pub station: Option<String>,
    pub workspace: Option<String>,
    pub workspace_id: Option<String>,
    pub name: Option<String>,
}

/// Who is looking: local | access (`email`) | mesh (`email`, `name`, `sub`, `role`, `workspace`, `device`).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Viewer {
    pub via: String,
    pub email: Option<String>,
    pub name: Option<String>,
    pub sub: Option<String>,
    pub role: Option<String>,
    pub workspace: Option<String>,
    pub device: Option<String>,
}

#[typeshare]
#[skip_serializing_none]
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

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SlackTeam {
    pub team_id: String,
    pub name: String,
    pub owner: Option<ConfigTokenOwner>,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SlackAppLinks {
    pub settings: String,
    pub install: String,
    pub app_token: String,
    pub oauth: String,
}

/// A Slack app ember made that no connect has taken yet, as its maker sees it (never its secrets or tokens).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MadeSlackApp {
    pub app_id: String,
    pub name: String,
    pub team_id: String,
    /// The Slack workspace's name, when its configuration token says.
    pub team: Option<String>,
    #[typeshare(serialized_as = "I54")]
    pub created: i64,
    pub links: SlackAppLinks,
    /// The link that installs it through Slack's OAuth (a station in ember cloud); none when its tokens are copied by hand.
    pub install: Option<String>,
    /// Its install's state, what a connect names it by.
    pub state: Option<String>,
    pub installed: bool,
    pub installed_team: Option<String>,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DiskRoom {
    #[typeshare(serialized_as = "I54")]
    pub free_bytes: i64,
    #[typeshare(serialized_as = "I54")]
    pub total_bytes: i64,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PendingLogin {
    pub id: String,
    pub runtime: RuntimeKind,
    pub job: Option<LoginJob>,
    pub created: Option<String>,
}

/// Who the station machine's own Claude Code or Codex is signed in as (only read: ember never takes the login over).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MachineLogin {
    pub runtime: RuntimeKind,
    pub installed: bool,
    pub logged_in: bool,
    pub email: Option<String>,
    pub plan: Option<String>,
    /// A profile can use it as it is (kept in a file, not only in the keychain).
    #[serde(default)]
    pub usable: bool,
    /// Its allowance, as a profile on it would show (none until read, or when it cannot be).
    pub quota: Option<Quota>,
    /// In a line, as the pages show it.
    pub text: String,
}

/// A station's overview, with what the clients show of its connects and profiles.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Overview {
    pub viewer: Viewer,
    pub connects: Vec<Connect>,
    pub profiles: Vec<Profile>,
    pub processes: Vec<AgentProcess>,
    pub counts: Counts,
    pub mesh: Option<MeshStatus>,
    pub slack_users: Vec<String>,
    pub slack_teams: Vec<SlackTeam>,
    #[serde(default)]
    pub slack_apps: Vec<MadeSlackApp>,
    pub disk: Option<DiskRoom>,
    pub logins: Vec<PendingLogin>,
    /// This machine's own logins (none from a station older than them).
    #[serde(default)]
    pub machine_logins: Vec<MachineLogin>,
    /// Its agents' processes, in a line.
    pub processes_text: String,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Memory {
    #[typeshare(serialized_as = "I54")]
    pub total_bytes: i64,
    #[typeshare(serialized_as = "I54")]
    pub used_bytes: i64,
    #[typeshare(serialized_as = "Option<I54>")]
    pub swap_used_bytes: Option<i64>,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Disk {
    pub path: String,
    #[typeshare(serialized_as = "I54")]
    pub total_bytes: i64,
    #[typeshare(serialized_as = "I54")]
    pub free_bytes: i64,
}

/// CPU, memory or disk: how full (and how bad: ok | amber | red), in words.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Meter {
    pub label: String,
    pub short: String,
    #[typeshare(serialized_as = "I54")]
    pub percent: i64,
    pub level: Level,
    pub value: String,
    pub note: Option<String>,
}

/// The machine a station runs on, with it in words.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Host {
    pub hostname: String,
    pub os: String,
    pub arch: String,
    #[typeshare(serialized_as = "I54")]
    pub cpus: i64,
    pub cpu_model: String,
    pub load: f64,
    pub uptime_sec: f64,
    pub memory: Memory,
    pub disk: Disk,
    #[typeshare(serialized_as = "I54")]
    pub ember_rss_bytes: i64,
    #[typeshare(serialized_as = "I54")]
    pub checked_at: i64,
    // What the core says of it.
    pub summary: String,
    pub line: String,
    pub facts: Vec<String>,
    pub meters: Vec<Meter>,
    pub ember_text: String,
}

/// A session with its threads and turns (`session` topic).
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SessionDetail {
    pub session: Session,
    pub threads: Vec<ChatThread>,
    pub turns: Vec<TurnRecord>,
}

// ── the live transcript and activity ─────────────────────────────────────

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TimelineEntry {
    pub at: Option<String>,
    /// user | assistant | thinking | tool_call | tool_result
    pub kind: String,
    pub text: String,
    pub tool: Option<String>,
    pub ok: Option<bool>,
    pub call_id: Option<String>,
    pub subagent: Option<bool>,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TranscriptUsage {
    #[typeshare(serialized_as = "I54")]
    pub model_calls: i64,
    #[typeshare(serialized_as = "I54")]
    pub input_tokens: i64,
    #[typeshare(serialized_as = "I54")]
    pub cached_tokens: i64,
    #[typeshare(serialized_as = "I54")]
    pub output_tokens: i64,
    pub model: Option<String>,
}

/// A step in flight; an ended one stays until the transcript entry that records it arrives.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LiveStep {
    pub id: String,
    /// text | thinking | tool
    pub step: String,
    pub tool: Option<String>,
    pub subagent: Option<bool>,
    pub parent: Option<String>,
    pub input: String,
    #[typeshare(serialized_as = "I54")]
    pub started_at: i64,
    pub ended: Option<bool>,
}

/// Where the turn stands with the model (starting | requesting | responding | working), since when.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Phase {
    pub phase: String,
    #[typeshare(serialized_as = "I54")]
    pub since: i64,
}

/// What an agent at work does now (activity.rs): `key` names the thing (a step, or where the turn stands), `text` says
/// it; the same thing keeps its key while its words change.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ActivityNow {
    pub key: String,
    pub text: String,
}

/// What an agent at work is doing, as a chat shows it (activity.rs).
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Activity {
    pub now: ActivityNow,
}

/// A session as it runs: its transcript (all of it once `loaded`), the model's use, the steps in flight, where the
/// turn stands, how fast it writes, and its activity.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Live {
    pub loaded: bool,
    pub timeline: Vec<TimelineEntry>,
    pub usage: Option<TranscriptUsage>,
    pub steps: Vec<LiveStep>,
    pub phase: Option<Phase>,
    #[typeshare(serialized_as = "Option<I54>")]
    pub rate: Option<i64>,
    pub activity: Option<Activity>,
    /// Its station is offline: this is what was kept.
    pub offline: Option<bool>,
}

// ── views ────────────────────────────────────────────────────────────────

/// Who is looking: an account's email, or "local".
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct Me {
    pub id: Option<String>,
    pub email: Option<String>,
}

/// A station's mesh link: connecting | online | offline | error.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct Link {
    pub state: String,
    pub message: Option<String>,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StationState {
    pub station: String,
    pub id: String,
    pub name: String,
    /// online | connecting | offline | error
    pub state: String,
    pub message: Option<String>,
}

/// What is wrong with the workspace's stations, in a line, and the worst of it: offline | error | reconnecting.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StationTrouble {
    pub text: String,
    pub state: String,
}

/// An agent of a sidebar row, with what its mark shows.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RowAgent {
    pub key: String,
    pub runtime: RuntimeKind,
    pub model: Option<String>,
    pub effort: Option<String>,
    pub process: String,
    #[typeshare(serialized_as = "I54")]
    pub pending: i64,
    pub last_turn: Option<TurnSummary>,
    pub agent_text: String,
    pub maker: Option<Maker>,
    pub mark: Option<Badge>,
    pub status_text: String,
    pub badge_text: Option<String>,
}

/// Who said a row's last thing: an agent (its state riding on its picture), a person, or ember.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LastBy {
    /// agent | person | ember
    pub kind: String,
    pub name: String,
    pub mine: bool,
    pub model: Option<String>,
    pub runtime: Option<RuntimeKind>,
    /// block | run | failed
    pub state: Option<Badge>,
    pub id: Option<String>,
    pub picture: Option<String>,
    /// What its picture says when pointed at: who, and an agent's state.
    pub label: String,
    pub maker: Option<Maker>,
}

/// A row's last message, its text cut to 200 characters; `preview` its line.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RowMessage {
    #[typeshare(serialized_as = "I54")]
    pub seq: i64,
    pub author_kind: String,
    pub author: String,
    pub author_name: Option<String>,
    pub text: String,
    #[typeshare(serialized_as = "I54")]
    pub created_at: i64,
    pub by: Option<LastBy>,
    pub preview: String,
    /// Its times in words, by field (`createdAt`, `lastActiveAt`, …).
    pub time: Option<HashMap<String, Stamp>>,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Origin {
    pub team_name: Option<String>,
    pub channel: String,
    pub channel_name: Option<String>,
    pub thread_ts: String,
}

/// An item of the sidebar, as its station puts it together for the viewer, and where it is.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ChatItem {
    pub id: String,
    pub session: String,
    #[typeshare(serialized_as = "Option<I54>")]
    pub thread: Option<i64>,
    pub title: String,
    pub agents: Vec<RowAgent>,
    pub last: Option<RowMessage>,
    pub unread: bool,
    pub mine: bool,
    #[typeshare(serialized_as = "I54")]
    pub last_active_at: i64,
    pub connect: Option<String>,
    pub origin: Option<Origin>,
    pub station: String,
    pub station_name: String,
    /// block | run | failed
    pub state: Option<Badge>,
    /// Where it came from (Slack · workspace · #channel), for a Slack chat.
    pub origin_text: Option<String>,
    /// Its station is offline, in words ("Studio 离线"): the row is shown greyed and marked. Absent while online.
    pub offline: Option<String>,
    /// Its station's link coming back, or failing and retried, in words ("正在重连 Studio…"): the row is marked with a
    /// turning ring. Absent while linked (and while offline).
    pub reconnecting: Option<String>,
    /// Its times in words, by field (`createdAt`, `lastActiveAt`, …).
    pub time: Option<HashMap<String, Stamp>>,
}

/// A day of the list, with its heading (今天, 昨天, 星期三, 9月20日).
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ChatDay {
    #[typeshare(serialized_as = "I54")]
    pub days_ago: i64,
    pub at: f64,
    pub label: String,
    pub items: Vec<ChatItem>,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ChatsView {
    pub me: Me,
    pub stations: Vec<StationState>,
    pub loading: bool,
    pub days: Vec<ChatDay>,
    /// The stations not working as they should, in a line ("MBA 离线", "正在重连 Studio", "2 台 station 异常"), for a
    /// corner of the list; absent while all are (a station first connecting is not one).
    pub trouble: Option<StationTrouble>,
}

/// Used up until a time (or no one knows when), in words.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Spent {
    pub until: Option<f64>,
    pub text: String,
    pub back: Option<String>,
}

/// A profile that can run a model: `current` it runs on it now.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RunnableProfile {
    pub id: String,
    pub name: String,
    pub current: bool,
    pub spent: Option<Spent>,
    pub kind: Option<AccessKind>,
    pub runtime: Option<RuntimeKind>,
    pub quota: Option<Quota>,
}

/// A window of a session's account running out, as its ring draws it.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QuotaAttention {
    #[typeshare(serialized_as = "I54")]
    pub left: i64,
    pub mark: String,
    pub level: Level,
    #[typeshare(serialized_as = "Option<I54>")]
    pub until: Option<i64>,
}

/// What is worth a look about a session now (account | quota | disk): what it says (`text`; for a quota, its tip's
/// first line, `more` the rest), and a quota's ring.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Attention {
    pub kind: String,
    pub text: String,
    pub more: Option<String>,
    pub quota: Option<QuotaAttention>,
}

/// An agent of a chat: its session, the connect that started it, its profile, and what it can move to.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ChatAgent {
    pub session: Session,
    pub status: Status,
    pub badge: Option<Badge>,
    pub connect: Option<Connect>,
    pub profile: Option<Profile>,
    pub profiles: Vec<RunnableProfile>,
    /// The models it can move to, as its model control offers them; the account it runs on now.
    pub choices: Vec<ModelOption>,
    pub account: Option<RunnableProfile>,
    pub attention: Vec<Attention>,
    /// When its running turn began; absent when none runs.
    #[typeshare(serialized_as = "Option<I54>")]
    pub since: Option<i64>,
    pub turns: Vec<TurnRecord>,
    pub threads: Vec<ChatThread>,
    /// Its background jobs, newest first; those with a port are web services, shown by their names.
    pub jobs: Vec<Job>,
}

/// A background job an agent started (a web service when it has a port): shown by its name; the port is how the
/// station reaches a service, not for people.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Job {
    pub id: String,
    pub name: String,
    /// running | exited | stopped | failed (a service that exited is being started again)
    pub state: String,
    #[typeshare(serialized_as = "Option<I54>")]
    pub port: Option<i64>,
    #[typeshare(serialized_as = "Option<I54>")]
    pub exit_code: Option<i64>,
    #[typeshare(serialized_as = "I54")]
    pub started_at: i64,
    #[typeshare(serialized_as = "Option<I54>")]
    pub ended_at: Option<i64>,
    /// What it runs (sh -c).
    #[serde(default)]
    pub command: String,
    /// How often a service was started again after it ended.
    #[serde(default)]
    #[typeshare(serialized_as = "I54")]
    pub restarts: i64,
    /// What it said lately (`ember-job notify`), newest first: how people see what a long-running job is up to.
    #[serde(default)]
    pub notices: Vec<JobNotice>,
    /// When its output last grew; absent when it has none.
    #[typeshare(serialized_as = "Option<I54>")]
    pub output_at: Option<i64>,
}

/// Something a job said, and when.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct JobNotice {
    #[typeshare(serialized_as = "I54")]
    pub at: i64,
    pub text: String,
}

/// A message sent from here that the chat does not show yet (sending | failed); `seq` once the station has it.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Outgoing {
    pub id: String,
    pub text: String,
    pub attachments: Vec<Attachment>,
    pub quotes: Vec<Quote>,
    #[typeshare(serialized_as = "I54")]
    pub created_at: i64,
    pub state: String,
    pub error: Option<String>,
    #[typeshare(serialized_as = "Option<I54>")]
    pub seq: Option<i64>,
    /// Its times in words, by field (`createdAt`, `lastActiveAt`, …).
    pub time: Option<HashMap<String, Stamp>>,
}

/// Someone in a chat, named as the core names them.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Person {
    pub id: String,
    pub name: String,
    pub email: Option<String>,
    pub via: String,
    pub shown: PersonShown,
}

/// An item's page: its chat (with the viewer's read position), or its agent before it has one.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ChatView {
    pub me: Me,
    pub thread: Option<ChatThread>,
    pub title: String,
    /// Where a Slack chat is (#channel, 私信), and its link in Slack while its connect is signed in.
    pub place: Option<String>,
    pub slack_url: Option<String>,
    pub people: Vec<Person>,
    pub agents: Vec<ChatAgent>,
    pub messages: Vec<ChatMessage>,
    pub more: bool,
    pub outbox: Vec<Outgoing>,
    pub link: Link,
    pub offline: bool,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeModels {
    pub runtime: RuntimeKind,
    pub models: Vec<String>,
}

/// A model a station can run: its maker, the runtimes it runs on, and for each how hard it can think and who runs it.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ModelOption {
    /// The spelling a client sends: the one that is its key when a profile has that, else the first.
    pub model: String,
    /// As people call it (Opus 5.5).
    pub name: String,
    /// Its series (Opus, GPT), what a list groups it under; none when not known. Lists come by series, newest first.
    pub family: Option<String>,
    /// Every spelling of it the station's profiles have enabled (openai/gpt-6-astra, gpt-6-astra): one model.
    pub ids: Vec<String>,
    pub maker: Option<Maker>,
    pub runtimes: Vec<RuntimeKind>,
    pub efforts: HashMap<String, Vec<String>>,
    pub accounts: HashMap<String, Vec<RunnableProfile>>,
    pub spent: Option<Spent>,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StationView {
    pub station: String,
    pub id: String,
    pub name: String,
    /// Its line in a list: offline since when, or what it is and whether its agents work.
    pub summary: String,
    pub online: bool,
    /// Seconds, from ember cloud.
    #[typeshare(serialized_as = "Option<I54>")]
    pub last_seen: Option<i64>,
    pub version: Option<String>,
    pub link: Link,
    pub runtimes: Vec<RuntimeModels>,
    pub models: Vec<ModelOption>,
    pub overview: Option<Overview>,
    pub host: Option<Host>,
    /// Its times in words, by field (`createdAt`, `lastActiveAt`, …).
    pub time: Option<HashMap<String, Stamp>>,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ConnectItem {
    pub station: String,
    pub station_name: String,
    pub connect: Connect,
    /// Its latest dozen; the one it delivers into; those it could deliver into instead.
    pub sessions: Vec<Session>,
    pub bound: Option<Session>,
    pub candidates: Vec<Session>,
    #[typeshare(serialized_as = "I54")]
    pub running: i64,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ConnectsView {
    pub me: Me,
    pub items: Vec<ConnectItem>,
    pub loading: bool,
}

// ── the execution history ────────────────────────────────────────────────

/// A place a message came from or went to: a chat on ember's page (`session`: the agent it opens), or a Slack thread.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Place {
    /// An ember chat's title, or a Slack thread's workspace and channel (`Cue#ops`).
    pub name: String,
    /// ember | slack
    pub surface: String,
    pub session: Option<String>,
    /// A Slack thread's link in Slack, while a connect is signed in to its workspace.
    pub url: Option<String>,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HistoryFrom {
    pub name: String,
    pub slack_user: Option<String>,
    pub bound: bool,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HistoryMessage {
    pub key: String,
    pub from: HistoryFrom,
    pub text: String,
    pub place: Option<Place>,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HistoryThought {
    pub text: String,
    pub first: String,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HistoryStep {
    pub said: Option<String>,
    pub name: String,
    pub hint: String,
    pub meta: String,
    pub failed: bool,
    pub call: String,
    pub result: Option<String>,
}

/// What a prompt carried: ember's own words around them (`note`), then the messages.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HistoryReceived {
    pub note: Option<String>,
    pub messages: Vec<HistoryMessage>,
}

/// The agent's own words; `subagent`: a sub-agent's.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HistoryText {
    pub text: String,
    pub subagent: bool,
}

/// A message the agent posted: where to, whether it ended its work blocked, whether it failed.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HistoryPost {
    pub text: String,
    pub place: Option<Place>,
    pub block: bool,
    pub failed: bool,
}

/// A state the agent marked, in words.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HistoryMark {
    pub text: String,
}

/// Tool calls and thinking between two boundaries: named by its latest call, what it did by kind (`title`), how many
/// failed and are running.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HistoryGroup {
    pub summary: String,
    pub title: String,
    #[typeshare(serialized_as = "I54")]
    pub failures: i64,
    #[typeshare(serialized_as = "I54")]
    pub pending: i64,
    pub thinking: Vec<HistoryThought>,
    pub steps: Vec<HistoryStep>,
}

/// What an item of the history is.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(tag = "kind", content = "content", rename_all = "camelCase")]
pub enum HistoryBody {
    Received(HistoryReceived),
    Text(HistoryText),
    Post(HistoryPost),
    Mark(HistoryMark),
    Group(HistoryGroup),
}

/// One item of an execution history, and the transcript entries it draws (`entries`: first, last).
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HistoryItem {
    pub key: String,
    #[typeshare(serialized_as = "Vec<I54>")]
    pub entries: Vec<i64>,
    pub body: HistoryBody,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HistoryLive {
    pub id: String,
    pub text: String,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HistoryPhase {
    pub phase: String,
    pub text: String,
    #[typeshare(serialized_as = "I54")]
    pub since: i64,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct UsageLine {
    pub label: String,
    pub value: String,
}

/// An agent's execution history, read for people (history.rs).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HistoryView {
    pub items: Vec<HistoryItem>,
    pub live: Vec<HistoryLive>,
    pub phase: Option<HistoryPhase>,
    pub usage: Option<Vec<UsageLine>>,
    pub usage_line: Option<String>,
    /// What shows at its top: where the session begins, or why there is nothing (yet).
    pub edge: String,
    pub empty: bool,
    pub loaded: bool,
}

// ── conforming ───────────────────────────────────────────────────────────

/// A value put through its shape: what the shape does not declare is dropped, an absent option left out, and a value
/// of the wrong type (a fractional time, a missing field) is an error that names the field.
pub fn conform<T: Serialize + serde::de::DeserializeOwned>(value: serde_json::Value) -> Result<serde_json::Value, String> {
    let typed: T = serde_path_to_error::deserialize(value).map_err(|e| format!("{}: {}", e.path(), e.inner()))?;
    serde_json::to_value(typed).map_err(|e| e.to_string())
}
