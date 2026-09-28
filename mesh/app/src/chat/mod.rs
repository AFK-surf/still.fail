//! What the station needs from a chat platform. Slack is the first implementation; the station's own chat (its pages'
//! conversations) is another.

pub mod internal;
pub mod names;
pub mod slack;
pub mod slack_apps;
pub mod status;

use std::sync::Arc;

use anyhow::{Result, bail};
use async_trait::async_trait;
use futures_util::future::BoxFuture;
use serde_json::{Map, Value};

use crate::store::Attachment;

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct ThreadRef {
    pub channel: String,
    pub thread_ts: String,
}

impl ThreadRef {
    pub fn new(channel: &str, thread_ts: &str) -> ThreadRef {
        ThreadRef { channel: channel.into(), thread_ts: thread_ts.into() }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InboundMessage {
    pub channel: String,
    pub thread_ts: String,
    pub ts: String,
    pub user: String,
    pub text: String,
    /// Mentions the bot or is a direct message: may start a session. Other thread replies only continue one.
    pub addressed: bool,
}

/// What a platform tells the station: a new message, or an edit of one already said (deletes are not taken: the
/// station keeps what was said).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChatEvent {
    Message(InboundMessage),
    Changed { channel: String, thread_ts: String, ts: String, text: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatMessage {
    pub ts: String,
    pub user: String,
    pub text: String,
    pub from_bot: bool,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct Person {
    pub name: String,
    pub email: String,
}

/// Takes a platform's event; it must finish keeping it before it resolves: the platform is acknowledged only after.
pub type Handler = Arc<dyn Fn(ChatEvent) -> BoxFuture<'static, Result<()>> + Send + Sync>;

#[async_trait]
pub trait ChatSurface: Send + Sync {
    /// The bot's own user id, once started.
    fn bot_user_id(&self) -> String;
    /// The bot's name on the platform (what people there call the agent), once started; empty where it has none.
    fn bot_name(&self) -> String {
        String::new()
    }
    /// The platform workspace (Slack team id) once started; threads are named by it.
    fn workspace(&self) -> Option<String>;
    /// Starts receiving.
    async fn start(self: Arc<Self>, handler: Handler) -> Result<()>;
    /// Posts a message into the thread as written (formatted for the surface: Slack's mrkdwn, or Markdown in the
    /// station's chats) and returns the posted message's ts. `files` are attachments already copied into the session's
    /// uploads; surfaces that cannot carry files refuse them.
    async fn post(&self, thread: &ThreadRef, message: &str, files: &[Attachment]) -> Result<String>;
    /// A person's display name, or None if unknown.
    async fn user_name(&self, _user: &str) -> Option<String> {
        None
    }
    /// Says in the thread what the agent working for it is doing ("" when it is done), best effort, never waited on.
    /// `message_ts`: the message that started the work.
    fn working(&self, _thread: &ThreadRef, _message_ts: Option<&str>, _status: &str) {}
    /// Calls the platform's API as the bot (Slack's Web API): what the agent reaches through slack_api.
    async fn api(&self, method: &str, _params: Map<String, Value>) -> Result<Value> {
        bail!("{method}: this conversation has no API")
    }
    /// A person's email, where the platform shares it.
    async fn user_email(&self, _user: &str) -> Option<String> {
        None
    }
    /// What is already known of a person, without waiting (unknown ones are fetched in the background).
    fn known_person(&self, _user: &str) -> Option<Person> {
        None
    }
    fn known_channel(&self, _channel: &str) -> Option<String> {
        None
    }
    /// A channel's name without the #, where the platform says; None for direct messages.
    async fn channel_name(&self, _channel: &str) -> Option<String> {
        None
    }
    /// Messages in the thread strictly before `before`, oldest first, at most `limit`: what was said before the station
    /// joined a thread. None where the platform cannot say (the station cannot join late there).
    async fn history(&self, _thread: &ThreadRef, _before: &str, _limit: usize) -> Option<Result<Vec<ChatMessage>>> {
        None
    }
    async fn stop(&self);
}

/// Splits text for Slack's message size, preferring paragraph, then line boundaries. Slack messages go out as the
/// agent wrote them, in Slack's own formatting: no converting, only splitting what is too long for one message.
pub fn split_for_slack(text: &str, limit: usize) -> Vec<String> {
    let mut chunks = Vec::new();
    let mut rest: Vec<char> = text.chars().collect();
    while rest.len() > limit {
        let window: String = rest[..=limit.min(rest.len() - 1)].iter().collect();
        let last = |needle: &str| window.rfind(needle).map(|b| window[..b].chars().count());
        let mut cut = last("\n\n").unwrap_or(0);
        if cut < limit / 2 {
            cut = last("\n").unwrap_or(0);
        }
        if cut < limit / 2 {
            cut = limit;
        }
        chunks.push(rest[..cut].iter().collect());
        let mut next = cut;
        while rest.get(next) == Some(&'\n') {
            next += 1;
        }
        rest = rest[next..].to_vec();
    }
    if !rest.is_empty() || chunks.is_empty() {
        chunks.push(rest.into_iter().collect());
    }
    chunks
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn long_text_splits_on_paragraph_boundaries() {
        let para = "x".repeat(60);
        let chunks = split_for_slack(&vec![para.clone(); 5].join("\n\n"), 130);
        assert_eq!(chunks, vec![format!("{para}\n\n{para}"), format!("{para}\n\n{para}"), para]);
        assert_eq!(split_for_slack("", 3500), vec![String::new()]);
    }
}
