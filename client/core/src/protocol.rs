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

/// What a UI can subscribe to. `station` is `"<workspace>/<station>"` or `"local"`.
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
    /// Every thread of a station, with the viewer's unread counts.
    Threads { station: String },
    /// One thread's messages: its latest page, older pages as `chat.older` loads them.
    Thread { station: String, thread: u64 },
    /// The station's sidebar rows for the viewer, as it puts them together (`/chats`).
    ChatRows { station: String },
    // Views: put together from the topics above (see views.rs). `scope` is a workspace id or "local".
    Chats { scope: String, #[serde(default)] mine: bool },
    Stations { scope: String },
    Connects { scope: String, #[serde(default)] mine: bool },
    /// One item's page: its chat (`thread`: the thread, its messages and its agents), or, before its agent has a
    /// chat (`session`), that agent alone.
    Chat { station: String, #[serde(default)] thread: Option<u64>, #[serde(default)] session: Option<String> },
}

impl Topic {
    /// The station a station topic belongs to; `None` for the account topics and the views.
    pub fn station(&self) -> Option<&str> {
        match self {
            Topic::Link { station } | Topic::Overview { station } | Topic::Sessions { station } | Topic::Host { station } | Topic::Threads { station } | Topic::ChatRows { station } => Some(station),
            Topic::Session { station, .. } | Topic::Live { station, .. } | Topic::Thread { station, .. } => Some(station),
            Topic::Accounts | Topic::Workspaces | Topic::Workspace { .. } => None,
            Topic::Chats { .. } | Topic::Stations { .. } | Topic::Connects { .. } | Topic::Chat { .. } => None,
        }
    }

    pub fn is_view(&self) -> bool {
        matches!(self, Topic::Chats { .. } | Topic::Stations { .. } | Topic::Connects { .. } | Topic::Chat { .. })
    }
}
