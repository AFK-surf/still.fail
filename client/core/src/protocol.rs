//! Messages between a UI and the core. See docs/client-core.md.

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::delta::Op;
use crate::error::CoreError;

/// One connected UI (a tab, a window).
pub type ClientId = u64;
/// Chosen by the UI; answers and subscription values carry it back.
pub type RequestId = u64;

/// UI → core.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(untagged)]
pub enum ClientMessage {
    Call { id: RequestId, call: String, #[serde(default)] params: Value },
    Subscribe { id: RequestId, subscribe: Topic },
    Unsubscribe { id: RequestId, unsubscribe: bool },
    /// Stops a streamed preview or a preview socket still under way (nobody wants it any more); it answers
    /// `cancelled`. Any other call runs to its end.
    Cancel { id: RequestId, cancel: bool },
}

/// core → UI.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(untagged)]
pub enum CoreMessage {
    Ok { id: RequestId, ok: Value },
    /// A call failed, or a subscription's topic could not be read.
    Error { id: RequestId, error: CoreError },
    /// A subscription's whole current value: its first, and after an error.
    Value { id: RequestId, value: Value },
    /// What changed since the subscription's previous value.
    Delta { id: RequestId, delta: Vec<Op> },
}

/// What a UI can subscribe to. `station` is `"<workspace>/<station>"`.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Deserialize, Serialize)]
#[serde(tag = "topic", rename_all = "camelCase")]
pub enum Topic {
    Accounts,
    Workspaces,
    Workspace { workspace: String },
    Link { station: String },
    Overview { station: String },
    Sessions { station: String },
    Session { station: String, key: String },
    Live { station: String, key: String },
    Host { station: String },
    /// How this device's connection to the station runs (station.rs `sample_net`): its path, its round trip and
    /// bytes each way over the last minute, sampled while it is watched. None for a station with no link of its own.
    Net { station: String },
    /// Every thread of a station, with the viewer's unread counts.
    Threads { station: String },
    /// One thread's entries: `{ first, last, entries, thread }`, its latest page (kept on the device, then what came
    /// after), older pages as `chat.older` loads them; `thread` is its summary as kept, until `threads` is read.
    Thread { station: String, thread: u64 },
    /// The station's sidebar rows for the viewer, as it puts them together (`/chats`).
    ChatRows { station: String },
    /// A connect's Slack app as the station sees it (`/connects/:id/slack-app`): its settings and links.
    SlackApp { station: String, connect: String },
    /// The station's background jobs still up (running, or a service being started again), newest first, each with
    /// the chat it is in as the viewer's sidebar has it (`/jobs`).
    Jobs { station: String },
    /// A job's last `lines` lines of output and when it last grew (`{ text, outputAt }`), current as it grows.
    JobLog { station: String, job: String, lines: u64 },
    /// An account's signed-in devices (`/v1/auth/sessions`).
    LoginSessions { account: String },
    /// still.fail cloud's operator lists for an admin account: `users`, `workspaces`, `invite-codes` or `feedback` (bug
    /// reports; a cloud from before has none: 404) (`/v1/admin/…`).
    Admin { account: String, list: String },
    /// Views of those for the admin's console (views/admin.rs): one list as `query` finds it, in `filter`, by `sort`, its
    /// first `limit` rows; one user's, workspace's or bug report's page (`list`: `users`, `workspaces` or `feedback`); the
    /// first page's counts.
    AdminList {
        account: String,
        list: String,
        #[serde(default)]
        query: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        filter: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        sort: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        limit: Option<u32>,
    },
    AdminItem { account: String, list: String, id: String },
    AdminOverview { account: String },
    // Views: put together from the topics above (see views.rs). `scope` is a workspace id.
    Chats { scope: String, #[serde(default)] mine: bool },
    Stations { scope: String },
    Connects { scope: String, #[serde(default)] mine: bool },
    /// One item's page: its chat (`thread`: the thread, its messages and its agents), or, before its agent has a
    /// chat (`session`), that agent alone.
    Chat { station: String, #[serde(default)] thread: Option<u64>, #[serde(default)] session: Option<String> },
    /// An agent's execution history, as people read it (history.rs): its transcript in items, what streams now.
    History { station: String, key: String },
    /// What the core is waiting on, when it is worth saying (status.rs): something slow, a connection down. Of a
    /// `workspace`: its stations' waits, its account's still.fail cloud socket and the relay; with
    /// none, all of it.
    Status {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        workspace: Option<String>,
    },
    /// What a person hears about while the client runs (notices.rs): chats of theirs that want them, newest last; a
    /// `workspace`'s only, or every workspace's.
    Notices {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        workspace: Option<String>,
    },
    /// What a chat on `station` says of its connection (pill.rs): its link down or coming back, else what its
    /// workspace's `status` says; coming back only once that has lasted a moment, and back again only after.
    Connection { station: String },
    /// What is being written to a chat on this device (its text, quotes, and files already up), kept until sent
    /// (`draft.put`). `chat`: its session key, `thread:<id>`, or `new` for a new chat on the station; empty until
    /// something is written.
    Draft { station: String, chat: String },
    /// Notifications on this device (attend.rs): whether they are on, whether the system was asked to allow them,
    /// whether it should hold a push registration, and the notices a page is to show now (`notice.claim` each): a page
    /// in a `workspace` shows only its own.
    Notify {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        workspace: Option<String>,
    },
    /// The chats of a scope `query` finds (refs.rs): those whose title has it first, then those whose agent, station,
    /// origin or last message does; only `station`'s if given, not `exclude` (a chat's id or agent key), `limit` at
    /// most. A view of `chats`: the composer's `@` menu and the switcher.
    ChatSearch {
        scope: String,
        #[serde(default)]
        query: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        station: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        exclude: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        limit: Option<u32>,
    },
    /// The station's archived chats (`/chats?archived=1`), as it lists them.
    ArchivedRows { station: String },
    /// A view: the archive of a scope's stations online (views/archive.rs).
    Archive { scope: String },
    /// A new chat's page in a scope (choose.rs): the stations it can start on, the one it starts on and what it runs
    /// there, as last picked on this device (`newChat.pick`).
    NewChat { scope: String },
    /// A model control's state (choose.rs): what a chat runs on now and what is picked in its panel until saved
    /// (`pick.set`, `pick.save`). `of`: `new` (a new chat on the station), `session:<key>`, `connect:<id>`, or
    /// `connect-new` (a connect being added).
    Pick { station: String, of: String },
    /// A chat's services and background jobs as its pages show them (jobs.rs): the same `thread` or `session` as its
    /// `chat` view.
    ChatJobs { station: String, #[serde(default)] thread: Option<u64>, #[serde(default)] session: Option<String> },
    /// The services and jobs left up a long while on the scope's stations that are up (jobs.rs).
    LongJobs { scope: String },
    /// A background job as it is now (`/jobs/:id`, then its events).
    Job { station: String, id: String },
    /// What this device keeps of how its person likes it, and what it is (prefs.rs; `prefs.set`, `client.device`).
    Prefs,
    /// What changed in still.fail, as this app shows it (changelog.rs): by day, each change saying where it is and
    /// whether this app has it, and what this app got since it was last shown (`changelog.seen`).
    Changelog,
    /// What each workspace has waiting for its person (how many chats want them, how many have something unread) and
    /// the chat last open in it (views/marks.rs); of those other than `workspace` (the one in view), the most urgent.
    WorkspaceMarks {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        workspace: Option<String>,
    },
}

impl Topic {
    /// The station a station topic belongs to; `None` for the account topics and the views.
    pub fn station(&self) -> Option<&str> {
        match self {
            Topic::Link { station } | Topic::Overview { station } | Topic::Sessions { station } | Topic::Host { station } | Topic::Net { station } | Topic::Threads { station } | Topic::ChatRows { station } | Topic::Jobs { station } => Some(station),
            Topic::ArchivedRows { station } => Some(station),
            Topic::Session { station, .. } | Topic::Live { station, .. } | Topic::Thread { station, .. } | Topic::SlackApp { station, .. } | Topic::JobLog { station, .. } => Some(station),
            Topic::Accounts | Topic::Workspaces | Topic::Workspace { .. } | Topic::LoginSessions { .. } | Topic::Admin { .. } | Topic::Status { .. } | Topic::Notices { .. } | Topic::Notify { .. } | Topic::Draft { .. } | Topic::Prefs => None,
            // The core's own (pill.rs, changelog.rs).
            Topic::Changelog => None,
            Topic::Connection { .. } => None,
            Topic::Chats { .. } | Topic::Stations { .. } | Topic::Connects { .. } | Topic::Chat { .. } | Topic::History { .. } | Topic::ChatSearch { .. } | Topic::Archive { .. } | Topic::WorkspaceMarks { .. } => None,
            Topic::AdminList { .. } | Topic::AdminItem { .. } | Topic::AdminOverview { .. } => None,
            Topic::NewChat { .. } | Topic::Pick { .. } => None,
            // The core's own (jobs.rs), not the station module's.
            Topic::ChatJobs { .. } | Topic::LongJobs { .. } | Topic::Job { .. } => None,
        }
    }

    pub fn is_view(&self) -> bool {
        matches!(self, Topic::Chats { .. } | Topic::Stations { .. } | Topic::Connects { .. } | Topic::Chat { .. } | Topic::History { .. } | Topic::ChatSearch { .. } | Topic::Archive { .. } | Topic::ChatJobs { .. } | Topic::LongJobs { .. } | Topic::WorkspaceMarks { .. } | Topic::AdminList { .. } | Topic::AdminItem { .. } | Topic::AdminOverview { .. })
    }
}
