//! The one error type calls and topics report. `code` is stable and
//! machine-readable (still.fail cloud's error codes pass through as they are);
//! `message` is for people, in their language (`stillfail_i18n::current`, as their prefs say) when it is made.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, thiserror::Error)]
#[error("{message}")]
pub struct CoreError {
    pub code: String,
    pub message: String,
    /// The HTTP status when the error came from still.fail cloud or a station.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<u16>,
}

impl CoreError {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self { code: code.into(), message: message.into(), status: None }
    }

    pub fn with_status(mut self, status: u16) -> Self {
        self.status = Some(status);
        self
    }

    /// The account's session is gone: it has to sign in again.
    pub fn signed_out(message: impl Into<String>) -> Self {
        Self::new("signed_out", message)
    }

    pub fn invalid(message: impl Into<String>) -> Self {
        Self::new("invalid_params", message)
    }
}

impl From<crate::host::HostError> for CoreError {
    fn from(error: crate::host::HostError) -> Self {
        // What wake.rs gives up with is matched as it is (core.rs, station/events.rs); said in the person's language here.
        let message = match error.0.as_str() {
            crate::wake::DROPPED => stillfail_i18n::t!("core-misc.wake.dropped"),
            crate::wake::GONE => stillfail_i18n::t!("core-misc.wake.gone"),
            crate::wake::NETWORK => stillfail_i18n::t!("core-misc.wake.network"),
            _ => error.0,
        };
        Self::new("host", message)
    }
}

pub type Result<T, E = CoreError> = std::result::Result<T, E>;
