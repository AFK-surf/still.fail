//! Messages between a UI and the core. See docs/client-core.md.

use serde::{Deserialize, Serialize};
use serde_json::Value;

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
    /// A subscription's whole current value.
    Value { id: RequestId, value: Value },
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
}

impl Topic {
    /// The station a topic belongs to, if any.
    pub fn station(&self) -> Option<&str> {
        match self {
            Topic::Link { station } | Topic::Overview { station } | Topic::Sessions { station } | Topic::Host { station } => Some(station),
            Topic::Session { station, .. } | Topic::Live { station, .. } => Some(station),
            Topic::Accounts | Topic::Workspaces | Topic::Workspace { .. } => None,
        }
    }
}
