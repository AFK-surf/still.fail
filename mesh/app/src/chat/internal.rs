//! The station's own chat: conversations on its pages. To the agent it is one more chat platform, like Slack: people's
//! messages arrive with their source, and the agent answers with chat_post to their thread. Every chat lives in one
//! channel, INTERNAL_CHANNEL; its thread_ts is its address. The messages themselves are the store's, like every
//! thread's.

use std::sync::Arc;
use std::sync::atomic::{AtomicI64, Ordering};

use anyhow::{Result, bail};
use async_trait::async_trait;

use super::{ChatSurface, Handler, ThreadRef};
use crate::store::{Attachment, now_ms};

/// The connect id the station's own chat goes by. Not configurable; never in config.json.
pub const INTERNAL_CONNECT: &str = "ember";
pub const INTERNAL_CHANNEL: &str = "EMBER";
/// How the agent is named in these chats.
pub const INTERNAL_BOT_USER: &str = "UEMBER";

static LAST_MICROS: AtomicI64 = AtomicI64::new(0);

/// Slack-style timestamps ("seconds.micros"), strictly increasing within this process.
pub fn next_ts() -> String {
    next_ts_at(now_ms())
}

pub fn next_ts_at(now_ms: i64) -> String {
    let mut prev = LAST_MICROS.load(Ordering::SeqCst);
    loop {
        let next = (prev + 1).max(now_ms * 1000);
        match LAST_MICROS.compare_exchange(prev, next, Ordering::SeqCst, Ordering::SeqCst) {
            Ok(_) => return format!("{}.{:06}", next / 1_000_000, next % 1_000_000),
            Err(actual) => prev = actual,
        }
    }
}

pub struct InternalChat {
    /// Display names of page users (the Access email, or "local").
    names: Box<dyn Fn(&str) -> String + Send + Sync>,
}

impl Default for InternalChat {
    fn default() -> Self {
        InternalChat { names: Box::new(|user| if user == "local" { "管理员".into() } else { user.into() }) }
    }
}

impl InternalChat {
    pub fn new(names: impl Fn(&str) -> String + Send + Sync + 'static) -> InternalChat {
        InternalChat { names: Box::new(names) }
    }
}

#[async_trait]
impl ChatSurface for InternalChat {
    fn bot_user_id(&self) -> String {
        INTERNAL_BOT_USER.into()
    }

    fn workspace(&self) -> Option<String> {
        None
    }

    async fn start(self: Arc<Self>, _handler: Handler) -> Result<()> {
        Ok(())
    }

    /// Nothing to send anywhere: the message is recorded under the ts this returns, and the page reads it from there.
    async fn post(&self, thread: &ThreadRef, _message: &str, _files: &[Attachment]) -> Result<String> {
        if thread.channel != INTERNAL_CHANNEL {
            bail!("no ember chat {}/{}", thread.channel, thread.thread_ts);
        }
        Ok(next_ts())
    }

    async fn user_name(&self, user: &str) -> Option<String> {
        (user != INTERNAL_BOT_USER).then(|| (self.names)(user))
    }

    async fn stop(&self) {}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timestamps_only_go_up() {
        let a = next_ts_at(1_000);
        let b = next_ts_at(1_000);
        assert!(b > a, "{a} {b}");
        assert_eq!(next_ts_at(4_102_444_800_000), "4102444800.000000");
    }
}
