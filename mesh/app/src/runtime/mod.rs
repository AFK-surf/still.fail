//! The seam between the station and a coding-agent runtime (Claude Code, Codex). Everything above this module is
//! runtime-agnostic.
//!
//! A driver opens sessions; what a session's runtime does comes back as events on the channel it was opened with, in
//! order — the session's own task handles them — rather than as callbacks.

pub mod claude;
pub mod codex;
pub mod process;

use std::path::PathBuf;
use std::sync::Arc;

use anyhow::Result;
use async_trait::async_trait;
use ember_shapes::RuntimeKind;
use serde::{Deserialize, Serialize};
use tokio::sync::mpsc;

use crate::config::Profile;

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum FailureReason {
    Auth,
    RateLimit,
    Model,
    Exited,
    Other,
}

impl FailureReason {
    pub fn as_str(self) -> &'static str {
        match self {
            FailureReason::Auth => "auth",
            FailureReason::RateLimit => "rate_limit",
            FailureReason::Model => "model",
            FailureReason::Exited => "exited",
            FailureReason::Other => "other",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TurnOutcome {
    Completed,
    Aborted,
    Failed { reason: FailureReason, message: String },
}

impl TurnOutcome {
    pub fn kind(&self) -> &'static str {
        match self {
            TurnOutcome::Completed => "completed",
            TurnOutcome::Aborted => "aborted",
            TurnOutcome::Failed { .. } => "failed",
        }
    }
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum LiveStepKind {
    Text,
    Thinking,
    Tool,
}

#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum LiveField {
    Text,
    Input,
    Output,
}

/// Where a turn stands with the model: the runtime starting up, a request out with nothing back yet, the model streaming
/// its answer, or the runtime working on its own (running tools) between requests.
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum LivePhase {
    Starting,
    Requesting,
    Responding,
    Working,
}

/// A turn's steps as they happen. A step is a stretch of the reply, of thinking, or a tool call; it starts, grows by
/// deltas (the reply's text, the tool's input as it is written, a command's output as it runs) and ends. Nothing here
/// is kept: once a step ends, the transcript is the record. (The same JSON as the TypeScript station's.)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum LiveEvent {
    Start {
        id: String,
        step: LiveStepKind,
        #[serde(skip_serializing_if = "Option::is_none", default)]
        tool: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none", default)]
        input: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none", default)]
        subagent: Option<bool>,
        #[serde(skip_serializing_if = "Option::is_none", default)]
        parent: Option<String>,
    },
    Delta {
        id: String,
        field: LiveField,
        text: String,
    },
    End {
        id: String,
    },
    Phase {
        phase: LivePhase,
    },
}

impl LiveEvent {
    pub fn start(id: impl Into<String>, step: LiveStepKind) -> LiveEvent {
        LiveEvent::Start { id: id.into(), step, tool: None, input: None, subagent: None, parent: None }
    }
    pub fn delta(id: impl Into<String>, field: LiveField, text: impl Into<String>) -> LiveEvent {
        LiveEvent::Delta { id: id.into(), field, text: text.into() }
    }
}

/// What a session's runtime says, in order.
#[derive(Debug, Clone, PartialEq)]
pub enum RuntimeEvent {
    /// A turn started without a prompt of ours: input written while the previous turn was finishing became a turn.
    TurnStarted,
    TurnEnded(TurnOutcome),
    /// The runtime process (or its shared host) went away; the session is unusable.
    Closed(String),
    /// What the turn is doing right now, as the runtime streams it; the transcript has it only once a step is done.
    Live(LiveEvent),
}

pub type Events = mpsc::UnboundedSender<RuntimeEvent>;

#[derive(Debug, Clone)]
pub struct OpenOptions {
    pub profile: Profile,
    pub cwd: PathBuf,
    /// Runtime-native session id to resume; a new session when absent.
    pub resume: Option<String>,
    pub model: Option<String>,
    /// Reasoning effort, in the runtime's own terms.
    pub effort: Option<String>,
    /// Appended to the runtime's own system prompt.
    pub instructions: String,
    /// Bearer token the session presents to the station's MCP endpoint.
    pub mcp_token: String,
    pub mcp_url: String,
    /// Stable per-session routing id for provider affinity headers.
    pub route: String,
}

#[async_trait]
pub trait AgentSession: Send + Sync {
    /// Runtime-native id: claude session id, codex thread id. Persist it to resume.
    fn id(&self) -> String;
    fn busy(&self) -> bool;
    /// Starts a turn. Fails when a turn is already running (or the runtime cannot take one as it is).
    async fn prompt(&self, text: &str) -> Result<()>;
    /// Adds input to the running turn. False when nothing is running or the turn cannot take it.
    async fn steer(&self, text: &str) -> bool;
    /// Interrupts the running turn; its end still arrives as TurnEnded.
    async fn abort(&self);
    /// Releases the session; ends the runtime process when it is not shared.
    async fn dispose(&self);
}

#[async_trait]
pub trait AgentDriver: Send + Sync {
    fn runtime(&self) -> RuntimeKind;
    async fn open(&self, options: OpenOptions, events: Events) -> Result<Arc<dyn AgentSession>>;
    /// Ends every process this driver started.
    async fn shutdown(&self);
}

/// A random UUID (v4), as runtimes take for session ids.
pub fn uuid() -> String {
    let mut b = [0u8; 16];
    let _ = getrandom::fill(&mut b);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    let h = hex::encode(b);
    format!("{}-{}-{}-{}-{}", &h[0..8], &h[8..12], &h[12..16], &h[16..20], &h[20..32])
}

/// The station's own environment, less what would let a runtime authenticate as something other than its profile.
pub fn clean_env(scrubbed: &[&str]) -> std::collections::BTreeMap<String, String> {
    std::env::vars().filter(|(k, _)| !scrubbed.contains(&k.as_str())).collect()
}
