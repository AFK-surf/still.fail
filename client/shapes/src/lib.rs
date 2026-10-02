//! What the core gives its clients, declared once. The web's and Android's types are generated from these
//! (scripts/shapes.sh: web/src/core/shapes.ts, apps/android/.../data/Shapes.kt), and every value the core sends on a
//! topic passes through its shape first (`conform`): a field a client reads is here, with its type, or it is not
//! sent. Whole numbers (times in ms, counts) are `i64`, sent as whole numbers; an absent `Option` is left out.
//!
//! Station shapes are as src/admin/types.ts has them; what the core puts in for the clients to show is marked so
//! (client/core/src/present.rs, format.rs, views.rs, history.rs, activity.rs).

pub mod model;
pub mod reasoning;

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
    Decision,
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

/// Who started a session or chat, or added a connect: an email, or "slack:<connect>:<user>"; "local" in records from
/// a station's own page, before it went.
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
    /// For waiting: at most how long, in seconds, until the agent is asked again (a station yet to update says none).
    #[typeshare(serialized_as = "Option<I54>")]
    pub wait_seconds: Option<i64>,
    /// For waiting: what it waits for, in the agent's words (a station yet to update says nothing).
    pub wait_for: Option<String>,
    /// How the agent ended it in today's words: all_done, need_help or waiting (`declared` keeps the words from before:
    /// final, block; a station before cards may say need_decision, which the core reads as need_help). A station yet to
    /// update says nothing.
    pub ending: Option<String>,
    /// For need_help: what a person has to give, do or decide, in the agent's words; for all_done, what the chat ends
    /// with.
    pub need: Option<String>,
    /// The message its state is about (the agent's `about`; for need_help, the card waiting by default). A station
    /// before it says nothing.
    pub about: Option<TurnAbout>,
    pub detail: Option<String>,
    #[typeshare(serialized_as = "I54")]
    pub started_at: i64,
    #[typeshare(serialized_as = "Option<I54>")]
    pub ended_at: Option<i64>,
}

/// The message a turn's state is about: its thread, its seq there, its ts.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TurnAbout {
    #[typeshare(serialized_as = "I54")]
    pub thread: i64,
    #[typeshare(serialized_as = "I54")]
    pub seq: i64,
    pub ts: String,
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
    /// In today's words (TurnSummary::ending).
    pub ending: Option<String>,
    /// For waiting: at most how long, in seconds, until the agent is asked again (a station yet to update says none).
    #[typeshare(serialized_as = "Option<I54>")]
    pub wait_seconds: Option<i64>,
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
    pub fast: Option<bool>,
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
    /// Keeping watch (a `job_start` watch of its runs): its chat is a watching one. A station from before watches says none.
    pub watch: Option<Watching>,
}

/// What a session keeps watch with (its watches running): their names, oldest first; since when the first runs; when
/// one last gave word (a notice, else its start).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Watching {
    pub names: Vec<String>,
    #[typeshare(serialized_as = "I54")]
    pub since: i64,
    #[typeshare(serialized_as = "I54")]
    pub at: i64,
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
    /// An image's ThumbHash (base64): a blurred likeness of it, shown until it loads.
    pub thumbhash: Option<String>,
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
    /// agent | person | page (a mark on a previewed page) | image (a numbered mark on an image)
    pub role: Option<String>,
    /// The name of the file, among the message's attachments, that goes with it (a preview mark's screenshot).
    pub file: Option<String>,
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
    /// An agent's post that ended its turn: final, block (the words from before; `ending` has today's).
    pub declared: Option<String>,
    /// all_done, need_decision, need_help: how the post ended its agent's turn. A station yet to update says nothing.
    pub ending: Option<String>,
    #[typeshare(serialized_as = "I54")]
    pub created_at: i64,
    #[typeshare(serialized_as = "Option<I54>")]
    pub edited_at: Option<i64>,
    /// Its times in words, by field (`createdAt`, `lastActiveAt`, …).
    pub time: Option<HashMap<String, Stamp>>,
}

/// A message of a chat, with what the core decides of it: the viewer's (their bubble), still.fail's own notice, who said
/// it, and whether its agents have yet to take it.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ChatMessage {
    /// The local outbox identity this message replaced, when sent from this core.
    pub outgoing: Option<String>,
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
    /// An agent's post that ended its turn: final, block (the words from before; `ending` has today's).
    pub declared: Option<String>,
    /// all_done, need_decision, need_help: how the post ended its agent's turn. A station yet to update says nothing.
    pub ending: Option<String>,
    #[typeshare(serialized_as = "I54")]
    pub created_at: i64,
    #[typeshare(serialized_as = "Option<I54>")]
    pub edited_at: Option<i64>,
    pub mine: bool,
    pub system: bool,
    /// still.fail's notice about one of the station's profiles (its sign-in failed): that profile's id, for a link to it.
    pub profile: Option<String>,
    pub by: MessageBy,
    pub waiting: bool,
    /// Said while the chat shows (told as it was said, not caught up on): it comes in rather than being there at once.
    /// Decided by the core once, when first seen (attend.rs).
    pub said: Option<bool>,
    /// Its times in words, by field (`createdAt`).
    pub time: Option<HashMap<String, Stamp>>,
    /// An agent's post with an options card: the answers to pick, in the order they are shown (the one the agent
    /// recommends last), as `card.options`; drawn under the message. Absent for every other message.
    pub options: Option<Vec<DecisionOption>>,
    /// The card it carries (options to pick, or a text field), as shown. Absent for a message with none.
    pub card: Option<MessageCard>,
    /// With a card: whether it still waits for an answer, and who answered it how.
    pub decision: Option<MessageDecision>,
}

/// What an agent's message asks people to answer it with (core decisions.rs): `type` options (`options`, as shown: the
/// recommended one last; a tap answers, `decision.answer`) or text (a field to write in, with a `placeholder`;
/// `decision.reply`). A type a UI does not know: answered by writing in the chat.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MessageCard {
    /// The person the agent asks to decide, by email. Absent on legacy cards.
    pub assignee: Option<String>,
    /// Who needs to decide, in the viewer's words; prepared by the core.
    pub assignee_text: Option<String>,
    /// options | text
    #[serde(rename = "type")]
    pub kind: String,
    pub options: Option<Vec<DecisionOption>>,
    pub placeholder: Option<String>,
}

/// One answer a decision offers (an agent's block post with chat_post `options`): a short phrase that reads on its own,
/// a line on what it leads to, and whether the agent recommends it.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DecisionOption {
    pub label: String,
    pub detail: Option<String>,
    pub recommended: Option<bool>,
}

/// Where a decision in a chat's messages stands (core, decisions.rs): still waiting (no person has written since it was
/// asked, and no newer one replaced it), or `resolved`, with who answered and whether by picking an option.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MessageDecision {
    pub resolved: bool,
    /// Still waiting, and the viewer dismissed it (off their list; the options still work).
    pub dismissed: Option<bool>,
    /// Who answered it (the first person to write after it), by name; absent while it waits, or when a newer decision
    /// replaced it.
    pub answered_by: Option<String>,
    /// The option they picked (their message quoted it with an option's label), its label.
    pub chosen: Option<String>,
    /// Resolved, in words: 林晓 选了「先不改」, 林晓 回复了, 已换成新的问题.
    pub text: Option<String>,
}

/// A chat's card still pending (a row's, a chat page's; named for when the only cards were decisions): its post's entry,
/// the card as shown, an options card's options in the order they are shown (the recommended one last; empty for a
/// text card), whether the viewer dismissed it, and its line (奏 · …) while it is the viewer's.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RowDecision {
    #[typeshare(serialized_as = "I54")]
    pub seq: i64,
    pub options: Vec<DecisionOption>,
    /// The card itself. A core before cards says none: an options card.
    pub card: Option<MessageCard>,
    pub dismissed: Option<bool>,
    /// 奏 · <the post's first line, cut to about 40 characters>. Absent once dismissed.
    pub text: Option<String>,
}

/// The cards waiting in a workspace's chats for the viewer (the `decisions` view, the 奏 page, core decisions.rs):
/// pending whatever their agents do, not dismissed by them, those they set aside (待定) last; `count` for 奏 N.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct DecisionsView {
    pub items: Vec<DecisionItem>,
    pub count: u32,
    /// Some station's chats are still being read: more may come.
    pub loading: bool,
    /// The cards the viewer answered today, newest first. A core before them says none.
    pub answered: Option<Vec<DecisionAnswered>>,
    /// The viewer's chats where an agent is at work or waiting (正在办), newest first: where the next may come from.
    pub working: Option<Vec<DecisionWorking>>,
    /// The day in numbers.
    pub today: Option<DecisionsToday>,
}

/// A card the viewer answered today: where it is, what it asked (`text`, its post's first line), how they answered it
/// (`answer`: 选了「…」, 回复：…), and when (`clock`, 14:05).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DecisionAnswered {
    pub station: String,
    pub station_name: String,
    pub session: String,
    #[typeshare(serialized_as = "I54")]
    pub thread: i64,
    pub title: String,
    #[typeshare(serialized_as = "I54")]
    pub seq: i64,
    pub text: String,
    pub answer: String,
    pub clock: String,
}

/// A chat of the viewer's where an agent is at work or waiting: where it is, and what it is doing (`line`: 在做 · …,
/// 在等：…), and since when (`time.lastActiveAt`).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DecisionWorking {
    pub station: String,
    pub station_name: String,
    pub session: String,
    #[typeshare(serialized_as = "I54")]
    pub thread: i64,
    pub title: String,
    pub line: String,
    pub time: Option<HashMap<String, Stamp>>,
}

/// The 奏 page's day: how many cards the viewer answered today, how long they waited on average (in words; none with
/// none answered), and how many of their chats have an agent at work or waiting.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DecisionsToday {
    pub count: u32,
    pub waited: Option<String>,
    pub working: u32,
}

/// One card on the 奏 page: where it is, the post that asks (as a chat shows messages, with its card) and the messages
/// just before it, the card (an options card's options as shown, also as `options`), and whether the viewer set it
/// aside on this device. An options card is answered with `decision.answer`, a text card with `decision.reply`.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DecisionItem {
    pub station: String,
    pub station_name: String,
    /// Its chat's item id (its session's key): what its page opens by.
    pub session: String,
    #[typeshare(serialized_as = "I54")]
    pub thread: i64,
    /// Its chat's title.
    pub title: String,
    #[typeshare(serialized_as = "I54")]
    pub seq: i64,
    pub message: ChatMessage,
    /// The one or two messages before it, oldest first.
    pub before: Vec<ChatMessage>,
    pub options: Vec<DecisionOption>,
    /// The card. A core before cards says none: an options card.
    pub card: Option<MessageCard>,
    /// Set aside (待定) on this device: last in the list, still pending.
    pub deferred: Option<bool>,
    /// 奏 · <the post's first line>
    pub text: String,
    /// What it asks, uncut: the need its agent ended need_human with, else the post's first line. A core before it says
    /// none.
    pub question: Option<String>,
}

/// A thread: a Slack thread or a chat on still.fail's page.
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
    pub decision: Option<DecisionCapability>,
    /// Runtime → model → supported reasoning levels; absent on older stations.
    pub model_efforts: Option<HashMap<String, HashMap<String, Vec<String>>>>,
    /// ok | login | failed | unknown
    pub state: String,
    pub detail: String,
    pub models: Option<Vec<String>>,
    #[typeshare(serialized_as = "I54")]
    pub checked_at: i64,
    /// Its times in words, by field (`createdAt`, `lastActiveAt`, …).
    pub time: Option<HashMap<String, Stamp>>,
}

/// Discovered on the existing profile; credentials and transport settings never enter this view.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DecisionCapability {
    pub state: String,
    pub detail: String,
    pub model: Option<String>,
    pub provider: Option<String>,
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

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QuotaCredits {
    pub has_credits: bool,
    pub unlimited: bool,
    pub balance: Option<String>,
}

/// An allowance: its windows shortest first.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Quota {
    pub credits: Option<QuotaCredits>,
    #[typeshare(serialized_as = "Option<I54>")]
    pub reset_count: Option<u64>,
    pub credits_text: Option<String>,
    pub reset_text: Option<String>,
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
    /// The signed-in subscription identity; independent of the editable display name.
    pub email: Option<String>,
    pub runtime: RuntimeKind,
    pub runtimes: Vec<RuntimeKind>,
    pub access: Access,
    pub home: String,
    pub home_exists: bool,
    pub model: Option<String>,
    pub models: Vec<String>,
    /// Models changed by the pending selection; None when no selection is being saved.
    pub models_saving: Option<Vec<String>>,
    pub env: Vec<EnvVar>,
    pub used_by: Vec<String>,
    pub login_command: String,
    /// On the machine's own login of its runtime: not edited (but for its models) or signed in here; removing it stops using that login.
    #[serde(default)]
    pub machine: bool,
    /// Whether a message to a running Claude Code turn moves what it waits on to the background first; None from a
    /// station older than the setting.
    pub background_on_message: Option<bool>,
    pub fast: Option<bool>,
    pub check: Option<ProfileCheck>,
    pub login: Option<LoginJob>,
    pub quota: Option<Quota>,
    // What the core says of it.
    pub check_text: String,
    pub check_tone: Tone,
    /// The first problem to resolve, with its next step; absent when nothing needs attention.
    pub trouble: Option<ProfileTrouble>,
    /// The makers of its models, and of those its check found, by model.
    pub makers: HashMap<String, Option<Maker>>,
    /// Its models, its default and those its check found as people call them (Opus 5.5), by model.
    pub names: HashMap<String, String>,
    /// Its models and those its check found, by series (Claude's biggest first, the rest by name; 其他 last), newest
    /// first: how the list to enable them from is laid out.
    pub series: Vec<ModelSeries>,
    /// How many of the models it could run are enabled, in words.
    pub models_text: String,
    /// What can be enabled on it: what its provider lists, then whatever is enabled already, each once.
    #[serde(default)]
    pub available: Vec<String>,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProfileTrouble {
    pub title: String,
    pub detail: String,
    pub next: String,
    /// check | quota | login | command | key | env
    pub action: String,
    pub label: String,
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

/// A Slack app still.fail made that no connect has taken yet, as its maker sees it (never its secrets or tokens).
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
    /// The link that installs it through Slack's OAuth (a station in still.fail cloud); none when its tokens are copied by hand.
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
    /// Why a sign-in that succeeded made no profile.
    pub error: Option<String>,
}

/// Who the station machine's own Claude Code or Codex is signed in as (only read: still.fail never takes the login over).
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
    /// Offered for a profile: signed in, on a plan, and no profile on it yet.
    #[serde(default)]
    pub offered: bool,
}

/// A piece of software on a station and whether a newer one is out (updates.rs): the station itself (`station`) or a
/// runtime (`claude`, `codex`).
#[typeshare]
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
    #[typeshare(serialized_as = "Option<I54>")]
    pub percent: Option<i64>,
    /// The station's, for a while after an update ended well: how it went (已更新到 0.1.1300，agent 没有中断).
    pub done: Option<String>,
    /// What the last update that failed said.
    pub message: Option<String>,
    /// When what is out was last read.
    #[typeshare(serialized_as = "Option<I54>")]
    pub checked_at: Option<i64>,
}

/// A station's overview, with what the clients show of its connects and profiles.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Overview {
    pub automatic_decisions: Option<AutomaticDecisionView>,
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
    /// The station's and its runtimes' versions, and whether newer ones are out (none from a station older than them).
    #[serde(default)]
    pub updates: Vec<SoftwareVersion>,
    /// Its agents' processes, in a line.
    pub processes_text: String,
    /// How much of the disk it takes (none from a station older than the footprint page, which then is not offered).
    pub footprint: Option<FootprintBrief>,
}

/// How much of the disk a station takes, for the row that opens its footprint page.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FootprintBrief {
    /// None before its first measure.
    #[typeshare(serialized_as = "Option<I54>")]
    pub bytes: Option<i64>,
    #[serde(default)]
    pub scanning: bool,
    /// What the core says of it: 12.3 GB, 正在统计….
    #[serde(default)]
    pub text: String,
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
    /// Remaining capacity for an alert chip; absent for CPU and older cores.
    pub remaining: Option<String>,
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
    /// 1-minute load average divided by CPU count, 0–1+.
    pub load: f64,
    /// How busy the CPUs are, all together, 0–1 (stations before it: absent).
    pub cpu_busy: Option<f64>,
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

/// A session as it runs: its transcript (its latest entries once `loaded`, from entry `first`; `history.older` loads
/// those before), the model's use, the steps in flight, where the turn stands, how fast it writes, and its activity.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Live {
    pub loaded: bool,
    #[typeshare(serialized_as = "Option<I54>")]
    pub first: Option<i64>,
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

/// Who is looking: the account that reaches the workspace, by its email.
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
/// `retry`: always false now (a station down is tried again from the stations' page); true from older cores while down.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StationTrouble {
    pub text: String,
    pub state: String,
    pub retry: Option<bool>,
}

/// The stations at a glance (the glyph): how many are online, offline or connecting (`dim`), failing, and at work; the
/// line beside it while all is well (the one station by name, else how many; and who works), and all of it in words.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StationsGlyph {
    #[typeshare(serialized_as = "I54")]
    pub online: i64,
    #[typeshare(serialized_as = "I54")]
    pub dim: i64,
    /// Of `dim`, those whose link is on its way: they pulse. Absent from a core before it.
    #[typeshare(serialized_as = "Option<I54>")]
    pub connecting: Option<i64>,
    #[typeshare(serialized_as = "I54")]
    pub failing: i64,
    #[typeshare(serialized_as = "I54")]
    pub working: i64,
    pub summary: String,
    pub label: String,
}

/// What a list with no rows to show says in their place: it is still reading, the stations it cannot reach (`text`
/// says so, `message` why), or there is nothing (`empty`). All false and none with rows to show.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ListNote {
    pub reading: bool,
    /// While reading, what it waits on (正在连接 Studio, 正在读取会话); absent from a core before it.
    pub text: Option<String>,
    pub failing: Vec<StationFailing>,
    pub empty: bool,
}

#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StationFailing {
    pub station: String,
    pub text: String,
    pub message: Option<String>,
}

/// A chat's link to its station while it is not as it should be: `tone` trouble (down; `detail` why) | busy (coming
/// back), and the line that says it.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LinkShown {
    pub tone: String,
    pub text: String,
    pub detail: Option<String>,
}

/// The station update control beside a chat title. Additions default for older cores.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StationUpdateNotice {
    pub tone: String,
    pub text: String,
    pub detail: Option<String>,
    pub label: Option<String>,
    pub version: Option<String>,
    #[serde(default)]
    pub open: bool,
    #[serde(default)]
    pub can_update: bool,
    #[serde(default)]
    pub dismissible: bool,
}

/// What one of still.fail's links opens in the app (`link.parse`): `invite` (`token`), a chat's page (`chat`), or an
/// item (`item`: its `session`, and `service` its web service); the call answers null for any other link.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LinkTarget {
    pub opens: String,
    pub token: Option<String>,
    pub workspace: Option<String>,
    pub station: Option<String>,
    pub chat: Option<String>,
    pub session: Option<String>,
    pub service: Option<String>,
}

/// A build of the app on still.fail cloud (`app.update`; scripts/release.sh puts it in /releases/<platform>/latest.json):
/// `file` is under /releases/.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AppRelease {
    #[typeshare(serialized_as = "I54")]
    pub version_code: i64,
    pub version_name: String,
    pub file: String,
    pub sha256: String,
    #[typeshare(serialized_as = "I54")]
    pub size: i64,
}

/// A buddy a Slack app can wear (`buddies`): its picture is avatars/<id>.webp (and .thumb.webp), on `bg`.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Buddy {
    pub id: String,
    pub label: String,
    pub bg: String,
}

/// The agents' memory on a station (`memory.get`): the global one, and the skills (projects' memories among them).
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct StationMemory {
    pub global: MemoryFile,
    pub skills: Vec<SkillFile>,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct MemoryFile {
    pub path: String,
    pub text: String,
}

/// A skill: `body` its text as people read it (no frontmatter), `about` when it applies (a project's without its
/// 项目记忆：); both absent from a core before them.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct SkillFile {
    pub name: String,
    pub description: String,
    pub project: bool,
    pub builtin: bool,
    pub text: String,
    pub body: Option<String>,
    pub about: Option<String>,
}

/// What the core is waiting on (the `status` topic), when it is worth saying: `state` slow (something has taken a
/// while) | trouble (a connection down), absent while all goes as it should; `text` says it in one line.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StatusView {
    pub state: Option<String>,
    pub text: Option<String>,
    pub items: Vec<StatusItem>,
}

/// What a chat says of its connection (the `connection` topic; client/core/src/pill.rs), all decided in the core:
/// `tone` busy (its link coming back, or something of its workspace waited on a while) | trouble (down) | back (up
/// again, for a moment after a busy or trouble was shown), absent while there is nothing to say; `text` the line,
/// `detail` beside it, `items` each thing waited on (on hover).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ConnectionView {
    pub tone: Option<String>,
    pub text: Option<String>,
    pub detail: Option<String>,
    pub items: Vec<StatusItem>,
}

/// What a person hears about while the client runs (the `notices` topic; docs/notifications.md), oldest first.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct NoticesView {
    pub items: Vec<Notice>,
}

/// What is being written to a chat on this device (the `draft` topic, `draft.put`): its text as typed, the passages
/// it quotes with what is said about them, and the files already up (the station keeps them in no chat until a
/// message takes them). Files still going up are the page's own.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct DraftView {
    pub text: String,
    pub quotes: Vec<Quote>,
    pub files: Vec<Attachment>,
}

/// How the pages look: as the system does (the default), or always light, or always dark.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Default)]
#[serde(rename_all = "lowercase")]
pub enum Appearance {
    #[default]
    System,
    Light,
    Dark,
}

/// Whose pictures lead a chat's row: by how many people the scope has (the default), or always the agents', or the
/// people's.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Default)]
#[serde(rename_all = "lowercase")]
pub enum RowPictureSetting {
    #[default]
    Auto,
    Agents,
    People,
}

/// Whose pictures lead the rows of a list (`ChatsView::leading`).
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Lead {
    Agents,
    People,
}

/// A chat's history tabs as last left: which are open, which is in front.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct KeptTabs {
    pub tabs: Vec<String>,
    pub active: Option<String>,
}

/// What this device is, as its host told the core at start (`client.device`), and what follows from it.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct DeviceView {
    /// `web`, `desktop` or `android`; empty until told.
    #[serde(default)]
    pub app: String,
    /// A phone (the Android app, or a phone's browser).
    #[serde(default)]
    pub phone: bool,
    /// An item's link from outside is offered to the desktop app first (a computer's browser).
    #[serde(default)]
    pub handoff: bool,
    /// The device's language as its host says (`zh-CN`, `en-US`, …); none until told.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub locale: Option<String>,
}

/// What changed in still.fail, as this app shows it (the `changelog` topic; client/core/src/changelog.rs): `app`
/// (web, desktop or android) and its `build` (0.1.<n>: n), absent before its host says; the changes by day, newest
/// first; what this app got since the changelog was last shown here (`news`, until `changelog.seen`); `loading` while
/// first read, `error` when it could not be and none was kept.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct ChangelogView {
    #[serde(default)]
    pub app: String,
    #[typeshare(serialized_as = "Option<I54>")]
    pub build: Option<i64>,
    pub days: Vec<ChangelogDay>,
    pub news: Option<ChangelogNews>,
    #[serde(default)]
    pub loading: bool,
    pub error: Option<String>,
}

/// A day's changes, under its heading (今天, 昨天, 9月20日).
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ChangelogDay {
    pub label: String,
    pub entries: Vec<ChangelogItem>,
}

/// One change: its lines for people, the version it came in, where it is (`place`: the parts and version, empty when
/// it needed no release), whether this app has it (`has`: absent when it is not this app's), and what that means
/// (`note`: 你的版本已包含, 更新到 0.1.n 后就有, 还没发布, 已发布, 已上线); `mine`: it is this app's.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ChangelogItem {
    #[typeshare(serialized_as = "I54")]
    pub version: i64,
    pub version_name: String,
    pub text: Vec<String>,
    pub place: String,
    pub has: Option<bool>,
    pub note: String,
    pub mine: bool,
}

/// What this app got since the changelog was last shown here: its `build` (0.1.n) and those changes.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ChangelogNews {
    pub build: Option<String>,
    pub entries: Vec<ChangelogItem>,
}

/// What people set going on this device and the core has not finished (the `doing` topic; client/core/src/doing.rs),
/// oldest first.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct DoingView {
    pub doing: Vec<DoingItem>,
}

/// A call under way: its name (`job.stop`), its params that are words, numbers or yes/no, as words (what a page
/// matches it by), and since when; `stage` running, rechecking (its station went quiet before it answered: asked again
/// once it is back, `note` saying so), or failed (kept a few seconds, `error` saying why). A core from before stages
/// gives none: running.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DoingItem {
    pub call: String,
    pub params: HashMap<String, String>,
    #[typeshare(serialized_as = "I54")]
    pub since: i64,
    pub stage: Option<String>,
    pub error: Option<String>,
    pub note: Option<String>,
}

/// This phone's adb as lent to a station's agents (the `adbShare` topic; client/core/src/adb.rs, docs/adb-share.md).
/// `phase`: `off`, `connecting` (the link opening, or opening again after it went: `message` says why) or `offered`;
/// `adb`, as the station's adb holds the phone once offered: `connecting`, `connected`, `unpaired`, `unauthorized`,
/// `off` (Wireless debugging is), `missing` (no adb there) or `failed`, `message` saying more. Stopped by itself (its hour up, a station too old), it
/// is off with why in `message`. `serial`: what the agents reach it at on the station; `until`: when it stops.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct AdbShareView {
    pub sharing: bool,
    pub station: Option<String>,
    pub phase: String,
    pub serial: Option<String>,
    pub adb: Option<String>,
    pub message: Option<String>,
    #[typeshare(serialized_as = "Option<I54>")]
    pub until: Option<i64>,
    pub tunnels: u32,
    pub connect_port: Option<u32>,
    pub pair_port: Option<u32>,
}

/// What this device keeps of how its person likes it (the `prefs` topic, `prefs.set`), and what it is.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct PrefsView {
    /// The lists show only the chats and connects the viewer takes part in.
    #[serde(default)]
    pub only_mine: bool,
    /// The chat list shows only the watching chats (监控中); never with `only_mine`.
    #[serde(default)]
    pub only_watching: bool,
    /// The wide screen's sidebar shows the decisions waiting for the viewer (奏) in place of the chats; never with
    /// `only_mine` or `only_watching`.
    #[serde(default)]
    pub only_decisions: bool,
    #[serde(default)]
    pub appearance: Appearance,
    #[serde(default)]
    pub row_picture: RowPictureSetting,
    /// Times are shown as dates rather than "3 分钟前".
    #[serde(default)]
    pub absolute_time: bool,
    /// The language chosen: `zh`, `en`, or none to follow the device's (its `locale`).
    #[serde(default)]
    pub language: Option<String>,
    /// The language things are said in, as chosen or else as the device is: `zh` or `en` (the core's; none from a core
    /// before languages, when the clients go by the device themselves).
    #[serde(default)]
    pub lang: Option<String>,
    /// Keys changed for an action (the desktop app's), by action.
    #[serde(default)]
    pub keys: HashMap<String, Vec<String>>,
    /// The workspace last open (the Android app's).
    #[serde(default)]
    pub workspace: Option<String>,
    /// The chat page last open, by scope (a workspace; `local` in what a station's own page kept, before it went).
    #[serde(default)]
    pub last_chat: HashMap<String, String>,
    /// The chat last open, by workspace, as the core keeps it from `client.focus` (a settings page leaves it as it
    /// was): what the workspace's page goes back to.
    #[serde(default)]
    pub open_chat: HashMap<String, OpenChat>,
    /// Each chat's history tabs, by `<station>:<chat>` (the latest 200).
    #[serde(default)]
    pub chat_tabs: HashMap<String, KeptTabs>,
    /// A Slack app made for a new connect, to go on with, by station (the Android app's).
    #[serde(default)]
    pub resume: HashMap<String, String>,
    /// Versions dismissed on this device, by workspace/station.
    #[serde(default)]
    pub station_updates_dismissed: HashMap<String, String>,
    /// The invite code a page was opened with, kept through signing in until a workspace is made with it.
    #[serde(default)]
    pub invite: Option<String>,
    #[serde(default)]
    pub device: DeviceView,
}

/// A chat to go back to: its station's address and the key its page goes by.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct OpenChat {
    pub station: String,
    pub key: String,
}

/// What each workspace has waiting for its person, for where workspaces are switched (the `workspaceMarks` view):
/// by workspace id; and of those other than the one in view, the most urgent.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceMarksView {
    pub workspaces: HashMap<String, WorkspaceMark>,
    /// alert | wait | done: the others' mark; none when nothing there wants anyone.
    pub others: Option<String>,
    /// 其他 workspace：1 个需要处理 · 2 个有新消息
    pub others_label: Option<String>,
}

/// A workspace's mark: of the chats its person takes part in, how many want them (blocked or failed) and how many
/// have something unread; of all its chats, how many have a decision waiting (`wait`); its `tone` (alert | wait | done, as a
/// chat's mark) and in words, none when it is 0 and 0; the chat last
/// open in it.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceMark {
    pub alert: u32,
    pub unread: u32,
    /// How many have a card waiting (not dismissed by them) or an agent needing them (need_help), not counted in
    /// `alert`. Absent for 0.
    pub wait: Option<u32>,
    /// How many cards wait in it for them in all (奏 N). Absent for 0.
    pub decisions: Option<u32>,
    pub tone: Option<String>,
    /// 2 个需要处理 · 1 个在等你 · 3 个有新消息
    pub label: Option<String>,
    pub chat: Option<OpenChat>,
}

/// A new chat's page (the `newChat` topic): the stations it can start on, the one it starts on, and what it runs
/// there, as last picked on this device (`newChat.pick`); what the station no longer has gives way to the first it has.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct NewChatView {
    /// The station last started on (or picked) in the scope, its id: the page holds its place with it until the
    /// stations are known.
    pub kept: String,
    /// The scope's stations up now; none until its workspace has been read (`error`: why it could not be).
    pub stations: Option<Vec<StationView>>,
    pub error: Option<String>,
    /// Whether the scope has any station, up or not.
    pub any: bool,
    /// The one it starts on: the one kept, else the first up; none when none is up.
    pub station: Option<StationView>,
    pub model: Option<ModelOption>,
    pub runtime: Option<RuntimeKind>,
    pub effort: Option<String>,
    pub fast: Option<bool>,
    /// The account kept to, while it still runs the model there; none: the station's pick.
    pub profile: Option<String>,
    /// How hard it can think there, and who can run it (offered when more than one can: `pickAccount`).
    pub efforts: Vec<String>,
    pub accounts: Vec<RunnableProfile>,
    pub pick_account: bool,
    /// Its profiles are being read.
    pub waiting: bool,
    /// What keeps a chat from starting: `profile` (none added) or `models` (none enabled).
    pub blocked: Option<String>,
    /// In a line under the page's words: the profiles being read, or no model enabled.
    pub problem: Option<String>,
    /// Every account of the model has used up its allowance: what is sent waits for it.
    pub spent: Option<String>,
    /// Its model control (the `pick` topic of `new` on the station), with the page.
    pub pick: Option<PickView>,
    /// Up to four combinations used on this device in this workspace, filtered to this station.
    pub frequent: Option<Vec<FrequentCombo>>,
}

/// One-click model and depth for a new chat; ranked and labelled by the core.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FrequentCombo {
    pub model: String,
    pub runtime: RuntimeKind,
    pub effort: Option<String>,
    pub label: String,
    pub selected: bool,
}

/// What a chat runs on: `model` none when none is chosen; `effort` none the default depth; `profile` none the
/// station's pick.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Picked {
    pub model: Option<String>,
    pub runtime: RuntimeKind,
    pub effort: Option<String>,
    pub fast: Option<bool>,
    pub profile: Option<String>,
}

/// The account a model control names: kept to (`auto` false), or the station's pick; `level` its window running low.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PickAccount {
    pub text: String,
    pub auto: bool,
    pub level: Option<Level>,
    pub profile: Option<RunnableProfile>,
}

/// A model control (the `pick` topic): what runs it now (`value`), what is picked in its panel so far (`draft`,
/// until `pick.save`), and what they say. An account kept to that does not run the model picked gives way to the
/// station's pick, said so (`dropped`, `force`).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PickView {
    pub fast_available: Option<bool>,
    pub fast_text: Option<String>,
    pub options: Vec<ModelOption>,
    pub runtime_fixed: bool,
    pub value: Picked,
    pub value_option: Option<ModelOption>,
    /// The account the control names; none: it names none (a new chat's, while the station's pick is fine).
    pub account: Option<PickAccount>,
    pub draft: Picked,
    /// The option picked in the panel, by its `model`.
    pub option: Option<String>,
    /// The runtimes offered for it (none: not asked), how hard it can think there, who can run it.
    pub runtimes: Vec<RuntimeKind>,
    pub efforts: Vec<String>,
    pub accounts: Vec<RunnableProfile>,
    pub dropped: Option<String>,
    /// The way to the accounts in the panel's foot: the one kept to, short, or 账号; amber when one gave way or the
    /// station's pick runs low.
    pub who: String,
    pub who_level: Option<Level>,
    /// The station's pick, said: who it is on now, or what it does.
    pub auto_note: String,
    pub changed: bool,
    /// Full screen (the phone's): the model, depth and account as they were and as they become; why the account
    /// must change; the model and account picked in words; what the button says.
    pub was: Vec<String>,
    pub becomes: Vec<String>,
    pub force: Option<String>,
    pub model_text: String,
    pub maker: Option<Maker>,
    pub account_text: String,
    pub account_note: String,
    pub account_warn: bool,
    pub save_text: String,
}

/// Notifications on this device (the `notify` topic; `notify.set`, `notice.claim`): whether they are on, whether the
/// system was asked to allow them, whether the device should hold a push registration, and the notices a page is to
/// show now, each taken by one page (`notice.claim`).
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct NotifyView {
    pub on: bool,
    pub asked: bool,
    pub push: bool,
    pub show: Vec<Notice>,
}

/// The chats a few words find (the `chatSearch` topic): as the sidebar has them, those whose title has the words
/// first. What the composer's `@` menu and the switcher list.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ChatSearchView {
    pub items: Vec<ChatItem>,
}

/// The archive of a scope's stations online (the `archive` topic): chats archived by hand or by their station once
/// idle, newest first by the day they were archived; what could not be read of it; and what the page says in place
/// of rows (reading, none), if anything. Restored (`chat.archive` with `archived` false) or deleted (`session.delete`),
/// a chat leaves it.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ArchiveView {
    pub days: Vec<ArchiveDay>,
    /// A station's archive that could not be read, in a line (named where there are several).
    pub errors: Vec<ArchiveError>,
    pub loading: bool,
    pub note: Option<String>,
}

/// A day of the archive, headed as the chat list's (今天, 昨天, 星期三, 9月20日).
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ArchiveDay {
    pub label: String,
    pub items: Vec<ArchiveItem>,
}

/// An archived chat: its thread (or, an agent with no chat, only its session), its title and last line, when it was
/// archived (`at`, and `clock` 14:05) and how (`how`: 手动归档, 空闲后自动归档). `place`: its station's name, where there
/// is more than one to tell apart. Not `deletable` when archived alone (its agents still at work elsewhere).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ArchiveItem {
    pub station: String,
    pub session: String,
    #[typeshare(serialized_as = "Option<I54>")]
    pub thread: Option<i64>,
    pub title: String,
    pub last: String,
    pub at: f64,
    pub clock: String,
    pub how: String,
    pub deletable: bool,
    pub place: Option<String>,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ArchiveError {
    pub station: String,
    pub text: String,
}

/// A chat that wants its person: its agent is blocked on them (`block`), failed (`failed`), finished with something
/// new to read (`done`), or someone else said something (`message`). `tag` names the chat (one notification each),
/// `url` opens it.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Notice {
    pub id: String,
    pub kind: String,
    pub station: String,
    pub workspace: String,
    pub station_id: String,
    pub session: String,
    #[typeshare(serialized_as = "Option<I54>")]
    pub thread: Option<i64>,
    pub title: String,
    pub body: String,
    pub tag: String,
    pub url: String,
    #[typeshare(serialized_as = "I54")]
    pub at: i64,
}

/// One thing waited on: what (`text`), how long or how much (`detail`), and whether it is slow | trouble.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StatusItem {
    pub state: String,
    pub text: String,
    pub detail: String,
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
    /// Keeping watch, as its session's `watch`.
    pub watch: Option<Watching>,
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
    /// A new chat asked for here that its station has not made yet. Absent otherwise.
    pub pending: Option<bool>,
    /// Who is in it, for its pictures: who started it first, then everyone who wrote in it, each once. From a
    /// station that does not say: absent.
    pub people: Option<Vec<Person>>,
    /// Who started it, as in `people`.
    pub creator: Option<Creator>,
    /// Its people in words, who started it said ("小王 发起 · Lina、你"), with `people`.
    pub people_text: Option<String>,
    /// The key a chat asked for here went by before its station made it: the list keeps it one row throughout. Older stations do not say it.
    pub client_key: Option<String>,
    /// Pinned by the viewer to the top of their list. Absent when its station does not know pins (it cannot be pinned).
    pub pinned: Option<bool>,
    /// A watching chat (one of its agents keeps watch): archiving it by hand asks first. Absent otherwise.
    pub watch: Option<RowWatch>,
    /// The card it waits on (an agent's post with a card no one has answered yet), as the viewer sees it. Absent when
    /// there is none (and from a station before decisions).
    pub decision: Option<RowDecision>,
    /// Nothing is left in it: each of its agents ended all_done, nothing at work, no card waiting for the viewer,
    /// nothing unread. Drawn faded, below the rest of its day (the core orders it so). Absent otherwise.
    pub settled: Option<bool>,
    /// With `settled`: offer to archive it with one tap (`chat.archive`). Absent otherwise.
    pub archivable: Option<bool>,
    /// Where it stands, in words, for its second line, its agents' states first: 要你帮忙：…, 出问题：…; then 奏 · … (a
    /// card waiting for the viewer, even while an agent works); then 在等：…, 做完了(：…). Absent while it is at work with
    /// no card waiting, or with nothing to say.
    pub state_text: Option<String>,
    /// The message `stateText` is about (a seq in this chat): the card, or the one the agent's state names. Opening the
    /// chat from the line may go to it. Absent when none.
    #[typeshare(serialized_as = "Option<I54>")]
    pub state_about: Option<i64>,
    /// Its mark, the most urgent first: alert (an agent failed), wait (a card waits, not dismissed by the viewer; or an
    /// agent needs them: need_help), busy (at work), done (something unread). Absent for none.
    pub tone: Option<String>,
}

/// A watching chat (core, present.rs): what it watches in words (监控中：盯 CI), and what archiving it by hand asks
/// first (`ask`: it runs on in the archive).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RowWatch {
    pub text: String,
    pub ask: String,
}

/// A day of the list, with its heading (今天, 昨天, 星期三, 9月20日); or, above them all, the chats the viewer pinned
/// (`pinned`, `daysAgo` -1, headed 已固定).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ChatDay {
    #[typeshare(serialized_as = "I54")]
    pub days_ago: i64,
    pub at: f64,
    pub label: String,
    pub items: Vec<ChatItem>,
    pub pinned: Option<bool>,
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
    /// How many people the scope has, for how rows are pictured; absent until known.
    #[typeshare(serialized_as = "Option<I54>")]
    pub members: Option<i64>,
    /// Whose pictures lead the rows: the device's setting (`prefs`), 自动 by `members` (unknown: as if alone).
    pub leading: Option<Lead>,
    /// The stations at a glance, and what the list says with no rows; absent from a core before them.
    pub glyph: Option<StationsGlyph>,
    pub note: Option<ListNote>,
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
    /// The chosen model’s reasoning levels on this account.
    pub efforts: Option<Vec<String>>,
    pub id: String,
    pub name: String,
    pub current: bool,
    pub spent: Option<Spent>,
    pub kind: Option<AccessKind>,
    pub runtime: Option<RuntimeKind>,
    pub quota: Option<Quota>,
    /// What is left of its allowance, in a few words (a core from before it says nothing).
    pub quota_line: Option<QuotaLine>,
}

/// What is left of an account's allowance, in a few words: every window in gray, or only the one running low, with
/// its level.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QuotaLine {
    pub text: String,
    pub level: Option<Level>,
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
    /// While it waits on work it started (its turn ended as waiting): since when, and for how long at most.
    pub wait: Option<AgentWait>,
    /// Seen starting its turn while the chat shows (not at work already when first seen): its activity comes in.
    pub started: Option<bool>,
    pub turns: Vec<TurnRecord>,
    pub threads: Vec<ChatThread>,
    /// Its background jobs, newest first; those with a port are web services, shown by their names.
    pub jobs: Vec<Job>,
}

/// An agent waiting on work it started, which brings it back: since its turn ended, and at most how many seconds
/// until it is asked again (absent from a station yet to update).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AgentWait {
    #[typeshare(serialized_as = "I54")]
    pub since: i64,
    #[typeshare(serialized_as = "Option<I54>")]
    pub seconds: Option<i64>,
    /// What it waits for in words, as its activity line says it (在等：CI 跑完; 等待中 from a station that does not say).
    pub text: Option<String>,
}

/// A background job an agent started (a web service when it has a port): shown by its name; the port is how the
/// station reaches a service, not for people.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Job {
    pub id: String,
    /// The session that started it (a chat's agents each have their own).
    #[serde(default)]
    pub session: String,
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
    /// Started to keep watch (`job_start` watch). A station from before watches says none.
    pub watch: Option<bool>,
    /// When its output last grew; absent when it has none.
    #[typeshare(serialized_as = "Option<I54>")]
    pub output_at: Option<i64>,
    // What the core puts in for the clients to show (jobs.rs).
    /// Its dot: up (a service up), live (a job alive), restart (a service being started again), fail, off (over).
    pub tone: Option<String>,
    /// A web service (it has a port).
    pub service: Option<bool>,
    /// A service whose page can be opened: up, or being started again.
    pub open: Option<bool>,
    /// Over, so clearing takes it away (stopped, failed, ended by itself; not a service started again).
    pub ended: Option<bool>,
    /// It matters now: up, alive, restarting, or died lately (a day).
    pub current: Option<bool>,
    /// Its state in a word (在线, 在盯着, 意外退出…), coloured as its dot.
    pub word: Option<String>,
    /// The line under its name, in parts (see `JobPart`).
    pub meta: Option<Vec<JobPart>>,
    /// Its state, how long, and how many notices, as a detail's head says it: 在盯着 · 3 分钟 · 2 条通知.
    pub detail: Option<String>,
    /// When its output last grew, in words: 最后输出 · 3 分钟前.
    pub output_said: Option<String>,
    /// How long it has been up: 3 小时.
    pub age: Option<String>,
    /// Among the open ones (`longJobs`): its station, that station's name when there are several, the chat it is in as
    /// the viewer's sidebar has it, and all that in a line (studio · 修登录 · 已归档).
    pub station: Option<String>,
    pub station_name: Option<String>,
    pub chat: Option<JobChat>,
    pub where_text: Option<String>,
}

/// A part of a job's line: `word` its state's word (coloured as its dot), `notice` what it said (in the text's colour),
/// none the rest.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct JobPart {
    pub text: String,
    pub kind: Option<String>,
}

/// The chat an open job is in.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct JobChat {
    pub id: String,
    pub title: Option<String>,
    #[serde(default)]
    pub archived: bool,
}

/// Something a job said, and when; `ago` (3 分钟前) and `clock` (13:04, 9/27 13:04) put in by the core.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct JobNotice {
    #[typeshare(serialized_as = "I54")]
    pub at: i64,
    pub text: String,
    pub ago: Option<String>,
    pub clock: Option<String>,
}

/// A chat's services and background jobs as its pages show them (the `chatJobs` view): every one, those that matter
/// now first (died, restarting, up and alive, over; newest first within each); what the button's dot says; each
/// group's head's note; how many matter now, how many are over and whose they are (clearing them is per session).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ChatJobsView {
    pub jobs: Vec<Job>,
    /// fail: one died lately; restart: a service is being started again.
    pub alarm: Option<String>,
    /// 2 个在线，1 个在重启; 1 个在盯着 (empty: nothing to say).
    pub services_note: String,
    pub jobs_note: String,
    #[typeshare(serialized_as = "I54")]
    pub current: i64,
    #[typeshare(serialized_as = "I54")]
    pub ended: i64,
    /// The sessions whose jobs that are over clearing takes away (`job.clearEnded` each).
    pub clear: Vec<String>,
    /// 全部 5 个; 清掉 2 个已结束的; 另有 2 个已停止或结束.
    pub all_text: String,
    pub clear_text: String,
    pub hidden_text: String,
}

/// The services and jobs left up a long while (an hour) on a scope's stations that are up (the `longJobs` view),
/// oldest first, in groups: web services, then background jobs; none while empty.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct LongJobsView {
    pub groups: Vec<LongJobsGroup>,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct LongJobsGroup {
    /// services | jobs
    pub key: String,
    /// 开了很久的网页服务 · 3
    pub head: String,
    pub jobs: Vec<Job>,
}

/// What the agents of a workspace spent over its last `days` (the `usage` view, client/core/src/views/usage.rs): a few
/// totals (`tiles`), each day's cost split by the people who spent most (`series`, the rest as 其他), and lists of who,
/// which chats, which accounts and which models spent the most, at the providers' API prices (`basis` says what that
/// means). `notes`: what is missing or still being read, in lines; `loading` while a station has not answered.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct UsageView {
    pub days: u32,
    pub loading: bool,
    pub empty: bool,
    pub tiles: Vec<UsageTile>,
    pub series: Vec<UsageSeries>,
    pub daily: Vec<UsageDay>,
    /// The most a day cost (what the bars are drawn against).
    pub max: f64,
    pub lists: Vec<UsageList>,
    pub notes: Vec<String>,
    pub basis: String,
    /// Each station's own calculation table; absent with older cores.
    pub prices: Option<Vec<UsagePriceTable>>,
}

/// A station's own price table; its note explains missing data on older/offline stations.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct UsagePriceTable {
    pub station: String,
    pub note: String,
    pub rows: Vec<UsagePriceRow>,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct UsagePriceRow {
    pub model: String,
    pub rates: Vec<UsageRate>,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct UsageRate {
    pub label: String,
    pub value: String,
}

/// 折合费用 $1,911 (按 API 价算).
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct UsageTile {
    pub label: String,
    pub value: String,
    pub sub: String,
}

/// A part of each day's bar: a person (`key` their email or reference), or the rest (`key` empty).
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct UsageSeries {
    pub key: String,
    pub name: String,
}

/// A day (`day` 2026-10-01, `label` 10/1): what it cost, split as `series` (`parts`, in dollars, and in words), and its
/// calls.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct UsageDay {
    pub day: String,
    pub label: String,
    pub today: bool,
    pub cost: f64,
    pub cost_text: String,
    pub calls: f64,
    pub calls_text: String,
    pub parts: Vec<f64>,
    pub parts_text: Vec<String>,
}

/// 按人 / 按对话 / 按账号 / 按模型 (`key` people, chats, profiles, models), the most spent first.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct UsageList {
    pub key: String,
    pub title: String,
    pub items: Vec<UsageItem>,
}

/// A person, chat, account or model, and what it spent: `share` of the total cost (of the calls, when nothing was
/// priced), `detail` its calls and tokens in a line. A person's `person` (with `shown`); a chat's page (`chat`), when
/// it is still there.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct UsageItem {
    pub key: String,
    pub title: String,
    pub sub: Option<String>,
    pub cost: f64,
    pub cost_text: String,
    pub share: f64,
    pub share_text: String,
    pub calls: f64,
    pub detail: String,
    pub person: Option<Creator>,
    pub chat: Option<UsageChat>,
}

/// Where a chat in the usage lists opens: its station, and its thread, or its agent's session.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct UsageChat {
    pub station: String,
    #[typeshare(serialized_as = "Option<I54>")]
    pub thread: Option<i64>,
    pub session: Option<String>,
}

/// A job's output as it grows (the `jobLog` topic): its last lines, when it last grew, its state (absent from a
/// station yet to say), and, put in by the core, its last line and when in words (absent: nothing to say).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct JobLogView {
    pub text: String,
    #[typeshare(serialized_as = "Option<I54>")]
    pub output_at: Option<i64>,
    pub state: Option<String>,
    pub last: Option<String>,
    pub said: Option<String>,
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
    /// The newest message asks for attention or gives a final result: dim earlier messages only at the scroll end.
    pub focus_last: Option<bool>,
    /// Archived chats must be restored before composing another message.
    #[serde(default)]
    pub archived: bool,
    /// Pinned to the top of the viewer's list. Absent when its station does not know pins (it cannot be pinned).
    pub pinned: Option<bool>,
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
    /// Entries after those loaded: the chat shows a window short of its end (`chat.newer` loads the next page,
    /// `chat.latest` goes to the end). What is said meanwhile waits there, counted in its thread's `unread`.
    #[serde(default)]
    pub newer: bool,
    /// The entry the chat opened at when not at its end (its first unread, or where it was left): the list shows it
    /// at its top. Absent when it opened at its end.
    #[typeshare(serialized_as = "Option<I54>")]
    pub at: Option<i64>,
    /// Opened where it was left (`at`): how far below the top of the list that entry's top was then, as the client
    /// that left it said (`chat.place`). Absent otherwise, and from a core before it.
    pub at_offset: Option<f64>,
    /// The last message caught up on (read: kept on the device, a page, what was missed) rather than said while the
    /// chat is open. The core decides from it which come in (`ChatMessage::said`); clients go by that.
    #[typeshare(serialized_as = "Option<I54>")]
    pub caught: Option<i64>,
    /// The message the unread line goes over: the first the viewer had not read when the chat was opened (not
    /// theirs); none while older pages are loaded to find it, or with nothing unread. Absent from a core before it.
    #[typeshare(serialized_as = "Option<I54>")]
    pub unread_line: Option<i64>,
    /// The unread line lies above the messages loaded: older pages are being loaded to find it.
    pub unread_above: Option<bool>,
    pub outbox: Vec<Outgoing>,
    pub link: Link,
    pub offline: bool,
    /// One of its agents keeps watch: archiving it by hand asks first. Absent otherwise.
    pub watch: Option<RowWatch>,
    /// A new chat asked for here that its station has not made yet: what is sent to it waits in its outbox.
    #[serde(default)]
    pub pending: bool,
    /// The key its station gave a chat asked for here, once made: the page, opened under the core's key, goes by it.
    pub key: Option<String>,
    /// Why the station could not make it, the last time it was tried.
    pub failed: Option<String>,
    /// Its link while it is down or coming back, in words; absent while it is up (and from a core before it).
    pub connection: Option<LinkShown>,
    /// Station update availability or progress, including the local outbox while reconnecting.
    pub station_update: Option<StationUpdateNotice>,
    /// The card it waits on, as its row has it. Absent when there is none.
    pub decision: Option<RowDecision>,
    /// Nothing is left in it (as its row's `settled`), and it is not archived: offer to archive it with one tap
    /// (`chat.archive`). Absent otherwise.
    pub archivable: Option<bool>,
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
    /// Its buddy's face: offline | working | idle; and what it is under its name (its processor, else 在线/离线).
    pub face: Option<String>,
    pub line: Option<String>,
    pub online: bool,
    /// Seconds, from still.fail cloud.
    #[typeshare(serialized_as = "Option<I54>")]
    pub last_seen: Option<i64>,
    pub version: Option<String>,
    pub link: Link,
    pub runtimes: Vec<RuntimeModels>,
    pub models: Vec<ModelOption>,
    pub overview: Option<Overview>,
    /// Its versions offer the 测试版 switch: it can be put on a channel (its station's version says one), and the
    /// account that reaches it is in the beta or it is on the test channel already (to be switched back).
    #[serde(default)]
    pub beta_offered: bool,
    pub host: Option<Host>,
    /// How this device's connection to it runs; none for a station reached without one of its own (the page's own)
    /// or before one is open.
    pub net: Option<StationNet>,
    /// Its times in words, by field (`createdAt`, `lastActiveAt`, …).
    pub time: Option<HashMap<String, Stamp>>,
}

/// This device's connection to a station, in words (its card's network line): how it goes, its round trip now and
/// over the last minute, and what goes over it.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StationNet {
    /// 直连, 北京中继 (the relay's name, or 中继 host), or 正在选路.
    pub path: String,
    pub rtt: Option<NetFigure>,
    /// Round trips over the last minute, oldest first, in milliseconds.
    pub rtt_history: Vec<f64>,
    /// Bytes a second now, each way: 1.4 MB/s.
    pub down: String,
    pub up: String,
    /// What went over it today on this device: 今天共 ↓ 212 MB · ↑ 9.6 MB (a core from before: 本次共, since it opened).
    pub total: String,
    /// The same each way: 212 MB. Missing from a core from before.
    pub down_total: Option<String>,
    pub up_total: Option<String>,
    /// Packets lost over the last minute, when some were.
    pub loss: Option<NetFigure>,
    /// The way through each relay as last measured, once it was (natively and in the browser: the mesh). Missing from
    /// a core from before.
    pub measured: Option<NetMeasured>,
}

/// A station's ways through each relay as last measured, and whether they are being measured again.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct NetMeasured {
    pub measuring: bool,
    pub relays: Vec<NetRelay>,
    /// The relay the connection moved to as they were measured (its name), if it did.
    pub moved: Option<String>,
}

/// The way through one relay: its round trip, or none if it was not reached in time.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct NetRelay {
    /// What still.fail calls it (北京), or its host.
    pub name: String,
    pub rtt: Option<NetFigure>,
    /// The connection goes through it now.
    pub current: bool,
}

/// A figure in words, and how bad it is.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct NetFigure {
    pub text: String,
    pub level: Level,
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

/// A place a message came from or went to: a chat on still.fail's page (`session`: the agent it opens), or a Slack thread.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Place {
    /// A still.fail chat's title, or a Slack thread's workspace and channel (`Cue#ops`).
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

/// What a prompt carried: still.fail's own words around them (`note`), then the messages.
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

/// A state the agent marked, in words; `wait` when it went to wait on work it started (drawn with an hourglass).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HistoryMark {
    pub text: String,
    pub wait: Option<HistoryWait>,
}

/// A wait in an agent's history: from its mark (`since`) until the next word brought it back (`until`, absent while it
/// still waits: count on from `since`), at most `seconds`.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct HistoryWait {
    #[typeshare(serialized_as = "I54")]
    pub since: i64,
    #[typeshare(serialized_as = "Option<I54>")]
    pub until: Option<i64>,
    #[typeshare(serialized_as = "Option<I54>")]
    pub seconds: Option<i64>,
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
    /// Older entries exist: `history.older` loads the page before them.
    pub more: Option<bool>,
}

// ── a station's usage (client/core/src/footprint.rs) ─────────────────────────

/// How much of the machine a station takes, as its footprint page shows it: everything in words, with what can be cleaned
/// and how (each clean a choice: the call, the chats it is for and the questions asked before it, in order).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FootprintView {
    /// Measured at least once: before, the page says it is being measured.
    pub measured: bool,
    pub scanning: bool,
    /// The viewer may clean up (an owner or admin).
    pub manage: bool,
    /// 3 分钟前统计, 正在统计….
    pub checked_text: String,
    /// still.fail 在这台机器上占用.
    pub lead: String,
    pub total_text: String,
    /// The disk in one bar: the station's parts, the rest that is used, and what is free (percent of the disk).
    pub bar: Vec<FootprintSegment>,
    pub legend: Vec<FootprintLegend>,
    pub parts: Vec<FootprintPart>,
    /// Beside the data directory: shown, not counted or cleaned.
    pub elsewhere: Vec<FootprintPart>,
    pub elsewhere_note: String,
    /// What can be cleaned up (only for those who may).
    pub actions: Vec<FootprintAction>,
    /// Why there is nothing to clean, or why the viewer cannot.
    pub actions_note: Option<String>,
    pub chats: Vec<FootprintChat>,
    /// 213 个 chat · 8.6 GB.
    pub chats_text: String,
    /// Chats of others the viewer cannot see, counted.
    pub unseen_text: Option<String>,
    /// 内存 · 共 6 GB，已用 5.2 GB.
    pub memory_title: String,
    pub memory: Vec<FootprintRow>,
}

/// A piece of the disk's bar: `tone` is the part's colour (chart-1…6), `rest` (used by others) or `free`.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FootprintSegment {
    pub id: String,
    pub percent: f64,
    pub tone: String,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FootprintLegend {
    pub text: String,
    /// Its dot's colour (as FootprintSegment's), or none for words alone.
    pub tone: String,
    pub level: Level,
}

/// A part of the data directory (or a place beside it): `chats` opens the list of chats.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FootprintPart {
    pub id: String,
    pub label: String,
    pub note: String,
    pub text: String,
    pub tone: String,
    pub opens: bool,
}

/// A clean-up offered: its line, and the choices it has (one, or several: all archived chats, or the older ones).
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FootprintAction {
    pub id: String,
    pub title: String,
    pub note: String,
    /// The button's words.
    pub action: String,
    pub danger: bool,
    /// Asked first when there are several: which one.
    pub pick: Option<String>,
    pub choices: Vec<FootprintChoice>,
}

/// One way to clean: `call` (footprint.rebuild, footprint.delete, footprint.evict) with `keys`, after each of `confirms` is agreed
/// to in turn; `done` is said after.
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FootprintChoice {
    pub label: String,
    pub call: String,
    pub keys: Vec<String>,
    pub confirms: Vec<FootprintConfirm>,
    pub done: String,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FootprintConfirm {
    pub title: String,
    pub text: String,
    pub action: String,
    pub danger: bool,
}

/// A chat's directory: its size, what can be made again in it, how long since it was used, and what can be done.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FootprintChat {
    pub key: String,
    /// The chat to open, by its id in the list.
    pub chat: Option<String>,
    pub title: String,
    pub archived: bool,
    pub text: String,
    pub note: String,
    pub choices: Vec<FootprintChoice>,
}

/// A line of the memory part: the station, the agents together, or one agent's process (`key`: its chat's session).
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FootprintRow {
    pub label: String,
    pub text: String,
    pub note: Option<String>,
    /// Under the line before it (an agent's process under the agents).
    pub nested: bool,
    pub chat: Option<String>,
    pub choice: Option<FootprintChoice>,
}

// ── conforming ───────────────────────────────────────────────────────────

/// A value put through its shape: what the shape does not declare is dropped, an absent option left out, and a value
/// of the wrong type (a fractional time, a missing field) is an error that names the field.
pub fn conform<T: Serialize + serde::de::DeserializeOwned>(value: serde_json::Value) -> Result<serde_json::Value, String> {
    let typed: T = serde_path_to_error::deserialize(value).map_err(|e| format!("{}: {}", e.path(), e.inner()))?;
    serde_json::to_value(typed).map_err(|e| e.to_string())
}

/// A Slack token form: a transient core draft, never saved to device storage.
#[typeshare]
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SlackTokensView {
    pub app_token: String,
    pub bot_token: String,
    pub verified: Option<SlackIdentity>,
    pub errors: Vec<String>,
    pub ready: bool,
}

/// Address of a transient Slack token form, shared by calls and topic subscriptions.
#[typeshare]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SlackTokenForm {
    pub station: String,
    pub form: String,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ConnectAppSettings {
    pub name: String,
    pub display_name: String,
    pub description: String,
    pub long_description: String,
    pub background_color: String,
    pub groups: HashMap<String, bool>,
}

/// One transient connect wizard. Decisions and navigation come from the core on every client.
#[typeshare]
#[skip_serializing_none]
#[derive(Serialize, Deserialize, Debug, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ConnectFlowView {
    pub step: String,
    pub title: String,
    pub back: String,
    pub number: u32,
    pub total: u32,
    pub resume: Option<String>,
    pub mobile: bool,
    pub team: Option<String>,
    pub adding: bool,
    pub settings: ConnectAppSettings,
    pub icon: Option<String>,
    pub icon_error: Option<String>,
    pub made_id: Option<String>,
    pub config: String,
    pub config_ready: bool,
    pub config_error: Option<String>,
    pub mode: ConnectMode,
    pub require_mention: bool,
    pub getting_token: bool,
    pub no_profile: bool,
    pub can_make: bool,
    pub can_create: bool,
    pub teams: Vec<SlackTeam>,
    pub chosen: Option<SlackTeam>,
    pub made: Option<MadeSlackApp>,
    pub pick: Option<PickView>,
}

#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AutomaticDecisionView {
    pub can_edit: bool,
    pub settings: AutomaticDecisionSettings,
    pub models: Vec<AutomaticDecisionModel>,
    pub recent: Vec<AutomaticDecisionCheck>,
}
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AutomaticDecisionSettings { pub completion: Option<AutomaticDecisionRule> }
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AutomaticDecisionRule { pub enabled: bool, pub model: Option<String> }
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AutomaticDecisionModel { pub id: String, pub name: String, pub profiles: Vec<String> }
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AutomaticDecisionDraft {
    pub enabled: bool, pub model: String, pub dirty: bool, pub pending: bool,
    /// The shared model selector, restricted to verified decision candidates.
    #[serde(default)]
    pub pick: Option<PickView>,
}
#[typeshare]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AutomaticDecisionCheck {
    #[typeshare(serialized_as = "I54")]
    pub id: i64,
    pub session: String,
    pub title: String,
    #[typeshare(serialized_as = "I54")]
    pub at: i64,
    #[serde(default)]
    pub stamp: Option<Stamp>,
    pub label: String,
    pub accepted: bool,
    pub model: String,
    pub profile: Option<String>,
    #[typeshare(serialized_as = "I54")]
    pub elapsed_ms: i64,
    pub error: Option<String>,
}
