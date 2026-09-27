//! Slack over Socket Mode (no public endpoint needed) and the Web API. (src/chat/slack.ts)

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use async_trait::async_trait;
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};
use tokio::sync::{Mutex as AsyncMutex, watch};
use tokio_tungstenite::tungstenite::Message;
use tracing::{error, info, warn};

use super::names::NameBook;
use super::status::{Call, ThreadStatus};
use super::{ChatEvent, ChatMessage, ChatSurface, Handler, InboundMessage, Person, ThreadRef, split_for_slack};
use crate::store::Attachment;

/// Who a bot token belongs to, as Slack reports it.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SlackIdentity {
    pub team: String,
    pub team_id: String,
    /// Workspace URL, e.g. https://acme.slack.com/
    pub url: String,
    pub bot_user_id: String,
    pub bot_name: String,
    /// Its bot's picture (the app's icon), as Slack shows it; None when Slack does not say.
    pub bot_image: Option<String>,
}

/// Where Slack's Web API is (tests point it elsewhere).
fn api_base() -> String {
    std::env::var("EMBER_SLACK_API").unwrap_or_else(|_| "https://slack.com/api".into())
}

fn client() -> &'static reqwest::Client {
    static CLIENT: OnceLock<reqwest::Client> = OnceLock::new();
    CLIENT.get_or_init(|| reqwest::Client::builder().timeout(Duration::from_secs(30)).build().expect("http client"))
}

/// A Slack Web API call: its answer, or an error `slack <method>: <error>` (as the TS station words it). A 429 waits
/// what Slack says and tries again, up to five times.
pub async fn slack_api(method: &str, params: &[(String, String)], token: &str) -> Result<Value> {
    let mut attempt = 0;
    loop {
        let response = client().post(format!("{}/{method}", api_base())).bearer_auth(token).form(params).send().await?;
        if response.status().as_u16() == 429 && attempt < 5 {
            let wait: u64 = response.headers().get("retry-after").and_then(|v| v.to_str().ok()).and_then(|v| v.parse().ok()).unwrap_or(1);
            tokio::time::sleep(Duration::from_secs(wait)).await;
            attempt += 1;
            continue;
        }
        let body: Value = response.json().await?;
        if body.get("ok") != Some(&Value::Bool(true)) {
            let code = body.get("error").map(|e| e.as_str().map(String::from).unwrap_or_else(|| e.to_string())).unwrap_or_else(|| "undefined".into());
            bail!("slack {method}: {code}");
        }
        return Ok(body);
    }
}

fn pairs(list: &[(&str, &str)]) -> Vec<(String, String)> {
    list.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
}

/// Who the bot is, and where: its name as people see it in that workspace (not its handle), when Slack says.
async fn identity_of(token: &str) -> Result<SlackIdentity> {
    let auth = slack_api("auth.test", &[], token).await?;
    let text = |v: Option<&Value>| v.and_then(Value::as_str).unwrap_or("").to_string();
    let bot_user_id = text(auth.get("user_id"));
    let user = slack_api("users.info", &pairs(&[("user", &bot_user_id)]), token).await.ok().and_then(|d| d.get("user").cloned()).unwrap_or(Value::Null);
    let profile = user.get("profile").cloned().unwrap_or(Value::Null);
    let shown = [profile.get("display_name"), user.get("real_name"), profile.get("real_name")]
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .find(|n| !n.trim().is_empty())
        .map(String::from);
    let image = [profile.get("image_72"), profile.get("image_48"), profile.get("image_original")]
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .find(|u| u.starts_with("https://"))
        .map(String::from);
    Ok(SlackIdentity {
        team: text(auth.get("team")),
        team_id: text(auth.get("team_id")),
        url: text(auth.get("url")),
        bot_name: shown.unwrap_or_else(|| text(auth.get("user"))),
        bot_user_id,
        bot_image: image,
    })
}

/// Checks a token pair without connecting: the bot token must authenticate, and the app-level token must be allowed to
/// open a Socket Mode connection.
pub async fn verify_slack_tokens(app_token: &str, bot_token: &str) -> (Option<SlackIdentity>, Vec<String>) {
    let mut errors = Vec::new();
    let mut identity = None;
    if !bot_token.starts_with("xoxb-") {
        errors.push("Bot Token 应该以 xoxb- 开头".to_string());
    } else {
        match identity_of(bot_token).await {
            Ok(id) => identity = Some(id),
            Err(e) => errors.push(format!("Bot Token 无效：{e}")),
        }
    }
    if !app_token.starts_with("xapp-") {
        errors.push("App-Level Token 应该以 xapp- 开头".to_string());
    } else if let Err(e) = slack_api("apps.connections.open", &[], app_token).await {
        errors.push(format!("App-Level Token 无法建立 Socket Mode 连接：{e}"));
    }
    (identity, errors)
}

/// A Slack event as the station takes it: a person's message, an edit, or nothing it keeps (bots, its own, deletes).
pub fn to_event(event: &Value, bot_user_id: &str) -> Option<ChatEvent> {
    let text = |v: Option<&Value>| v.and_then(Value::as_str).unwrap_or("").to_string();
    let kind = event.get("type").and_then(Value::as_str).unwrap_or("");
    let subtype = event.get("subtype").and_then(Value::as_str);
    if kind == "message" && subtype == Some("message_changed") {
        let changed = event.get("message").cloned().unwrap_or(Value::Null);
        let ts = text(changed.get("ts"));
        if ts.is_empty() || changed.get("bot_id").is_some_and(|b| !b.is_null()) {
            return None;
        }
        // A message outside any thread is the root of its own.
        let thread_ts = changed.get("thread_ts").and_then(Value::as_str).map(String::from).unwrap_or_else(|| ts.clone());
        return Some(ChatEvent::Changed { channel: text(event.get("channel")), thread_ts, ts, text: text(changed.get("text")) });
    }
    // The station has no retraction: a deleted message stays as it was said.
    if kind == "message" && subtype == Some("message_deleted") {
        return None;
    }
    if kind != "app_mention" && kind != "message" {
        return None;
    }
    // Message subtypes that are still a person talking.
    if !matches!(subtype, None | Some("file_share") | Some("thread_broadcast")) {
        return None;
    }
    let user = text(event.get("user"));
    if event.get("bot_id").is_some_and(|b| !b.is_null()) || user.is_empty() || user == bot_user_id {
        return None;
    }
    let body = text(event.get("text"));
    let ts = text(event.get("ts"));
    Some(ChatEvent::Message(InboundMessage {
        channel: text(event.get("channel")),
        thread_ts: event.get("thread_ts").and_then(Value::as_str).map(String::from).unwrap_or_else(|| ts.clone()),
        addressed: kind == "app_mention" || event.get("channel_type").and_then(Value::as_str) == Some("im") || body.contains(&format!("<@{bot_user_id}>")),
        ts,
        user,
        text: body,
    }))
}

/// Whether the socket is up, and the last connection error.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SocketStatus {
    pub connected: bool,
    pub last_error: Option<String>,
}

pub struct SlackSurface {
    app_token: String,
    bot_token: String,
    identity: Mutex<Option<SlackIdentity>>,
    names: Mutex<HashMap<String, Person>>,
    channels: Mutex<HashMap<String, Option<String>>>,
    status: watch::Sender<SocketStatus>,
    stopped: watch::Sender<bool>,
    /// Each thread an agent works for: its status line (status.rs).
    working: Mutex<HashMap<String, Arc<ThreadStatus>>>,
    book: Option<Arc<NameBook>>,
}

impl SlackSurface {
    /// `book` keeps names across restarts and lets the admin API ask without waiting (known_person, known_channel).
    pub fn new(app_token: &str, bot_token: &str, book: Option<Arc<NameBook>>) -> Result<Arc<SlackSurface>> {
        if !app_token.starts_with("xapp-") {
            bail!("slack.appToken must be an app-level token (xapp-…)");
        }
        if !bot_token.starts_with("xoxb-") {
            bail!("slack.botToken must be a bot token (xoxb-…)");
        }
        Ok(Arc::new(SlackSurface {
            app_token: app_token.into(),
            bot_token: bot_token.into(),
            identity: Mutex::new(None),
            names: Mutex::default(),
            channels: Mutex::default(),
            status: watch::channel(SocketStatus::default()).0,
            stopped: watch::channel(false).0,
            working: Mutex::default(),
            book,
        }))
    }

    pub fn identity(&self) -> Option<SlackIdentity> {
        self.identity.lock().unwrap().clone()
    }

    pub fn status(&self) -> SocketStatus {
        self.status.borrow().clone()
    }

    /// Hears each change of `status` (and of the identity: it moves then too).
    pub fn status_changes(&self) -> watch::Receiver<SocketStatus> {
        self.status.subscribe()
    }

    fn set_status(&self, connected: bool, last_error: Option<String>) {
        self.status.send_if_modified(|s| {
            let next = SocketStatus { connected, last_error };
            let changed = *s != next;
            *s = next;
            changed
        });
    }

    /// Reads again who the bot is and where (its name changed in Slack, say); listeners hear of it.
    pub async fn refresh_identity(&self) -> Result<()> {
        let identity = identity_of(&self.bot_token).await?;
        *self.identity.lock().unwrap() = Some(identity);
        self.status.send_modify(|_| {});
        Ok(())
    }

    async fn profile(&self, user: &str) -> Option<Person> {
        if let Some(known) = self.names.lock().unwrap().get(user).cloned() {
            return Some(known);
        }
        let r = slack_api("users.info", &pairs(&[("user", user)]), &self.bot_token).await.ok()?;
        let u = r.get("user").cloned().unwrap_or(Value::Null);
        let p = u.get("profile").cloned().unwrap_or(Value::Null);
        let name = [p.get("display_name"), u.get("real_name"), u.get("name")].into_iter().flatten().filter_map(Value::as_str).find(|n| !n.is_empty()).unwrap_or("").to_string();
        let person = Person { name, email: p.get("email").and_then(Value::as_str).unwrap_or("").to_lowercase() };
        self.names.lock().unwrap().insert(user.to_string(), person.clone());
        Some(person)
    }

    async fn connect_loop(self: Arc<Self>, handler: Handler) {
        let mut backoff = Duration::from_secs(1);
        let mut stopped = self.stopped.subscribe();
        while !*stopped.borrow() {
            let run = async {
                let open = slack_api("apps.connections.open", &[], &self.app_token).await?;
                let url = open.get("url").and_then(Value::as_str).ok_or_else(|| anyhow!("slack gave no socket url"))?.to_string();
                self.clone().run_socket(&url, handler.clone()).await
            };
            let result = tokio::select! {
                r = run => r,
                _ = stopped.changed() => return,
            };
            match result {
                Ok(()) => backoff = Duration::from_secs(1),
                Err(e) => {
                    self.set_status(false, Some(e.to_string()));
                    warn!(error = %e, retry_in_ms = backoff.as_millis() as u64, "slack socket failed");
                    tokio::time::sleep(backoff).await;
                    backoff = (backoff * 2).min(Duration::from_secs(60));
                }
            }
        }
    }

    /// Returns when the socket closes (Slack rotates connections routinely).
    async fn run_socket(self: Arc<Self>, url: &str, handler: Handler) -> Result<()> {
        let (socket, _) = tokio_tungstenite::connect_async(url).await?;
        let (write, mut read) = socket.split();
        let write = Arc::new(AsyncMutex::new(write));
        self.set_status(true, None);
        let bot = self.bot_user_id();
        while let Some(frame) = read.next().await {
            let text = match frame? {
                Message::Text(t) => t.to_string(),
                Message::Close(_) => break,
                _ => continue,
            };
            let Ok(envelope) = serde_json::from_str::<Value>(&text) else { continue };
            match envelope.get("type").and_then(Value::as_str) {
                Some("disconnect") => {
                    info!(reason = %envelope.get("reason").cloned().unwrap_or(Value::Null), "slack asked to reconnect");
                    let _ = write.lock().await.close().await;
                    break;
                }
                Some("events_api") => {}
                _ => continue,
            }
            let event = envelope.get("payload").and_then(|p| p.get("event")).cloned().unwrap_or(Value::Null);
            let envelope_id = envelope.get("envelope_id").cloned().unwrap_or(Value::Null);
            let chat_event = to_event(&event, &bot);
            let (write, handler) = (write.clone(), handler.clone());
            tokio::spawn(async move {
                let accepted = match chat_event {
                    Some(e) => handler(e).await,
                    None => Ok(()),
                };
                match accepted {
                    Ok(()) => {
                        let ack = json!({ "envelope_id": envelope_id }).to_string();
                        let _ = write.lock().await.send(Message::Text(ack.into())).await;
                    }
                    // Not acknowledged: Slack redelivers, and the store dedupes.
                    Err(e) => error!(error = %e, "failed to accept slack event"),
                }
            });
        }
        let last = self.status().last_error;
        self.set_status(false, last);
        Ok(())
    }
}

#[async_trait]
impl ChatSurface for SlackSurface {
    fn bot_user_id(&self) -> String {
        self.identity.lock().unwrap().as_ref().map(|i| i.bot_user_id.clone()).unwrap_or_default()
    }

    fn bot_name(&self) -> String {
        self.identity.lock().unwrap().as_ref().map(|i| i.bot_name.clone()).unwrap_or_default()
    }

    fn workspace(&self) -> Option<String> {
        self.identity.lock().unwrap().as_ref().map(|i| i.team_id.clone()).filter(|t| !t.is_empty())
    }

    async fn start(self: Arc<Self>, handler: Handler) -> Result<()> {
        let identity = identity_of(&self.bot_token).await?;
        info!(bot_user_id = identity.bot_user_id, team = identity.team, "slack authenticated");
        *self.identity.lock().unwrap() = Some(identity);
        tokio::spawn(self.clone().connect_loop(handler));
        Ok(())
    }

    /// Posted as written (the agent writes Slack's formatting); a long message goes out in parts, the first part's ts
    /// standing for the whole.
    async fn post(&self, thread: &ThreadRef, message: &str, files: &[Attachment]) -> Result<String> {
        if !files.is_empty() {
            bail!("attaching files is not supported in Slack yet; mention the file paths in the text instead");
        }
        let mut first = None;
        for text in split_for_slack(message, 3500) {
            let posted = slack_api(
                "chat.postMessage",
                &pairs(&[("channel", &thread.channel), ("thread_ts", &thread.thread_ts), ("text", &text), ("unfurl_links", "false")]),
                &self.bot_token,
            )
            .await?;
            if first.is_none() {
                first = posted.get("ts").and_then(Value::as_str).map(String::from);
            }
        }
        first.ok_or_else(|| anyhow!("nothing to post"))
    }

    /// Display name via users.info, cached for the connection's lifetime.
    async fn user_name(&self, user: &str) -> Option<String> {
        self.profile(user).await.map(|p| p.name).filter(|n| !n.is_empty())
    }

    /// The person's email (users:read.email), which ties a Slack user to an ember cloud account.
    async fn user_email(&self, user: &str) -> Option<String> {
        self.profile(user).await.map(|p| p.email).filter(|e| !e.is_empty())
    }

    /// A person as far as already known, without waiting; an unknown one is looked up in the background.
    fn known_person(&self, user: &str) -> Option<Person> {
        let book = self.book.as_ref()?;
        let team = self.workspace().unwrap_or_else(|| "?".into());
        let (token, user_id) = (self.bot_token.clone(), user.to_string());
        book.person(&format!("u:{team}:{user}"), move || {
            Box::pin(async move {
                let r = slack_api("users.info", &pairs(&[("user", &user_id)]), &token).await.ok()?;
                let u = r.get("user").cloned().unwrap_or(Value::Null);
                let p = u.get("profile").cloned().unwrap_or(Value::Null);
                let name = [p.get("display_name"), u.get("real_name"), u.get("name")].into_iter().flatten().filter_map(Value::as_str).find(|n| !n.is_empty()).unwrap_or("").to_string();
                Some(Person { name, email: p.get("email").and_then(Value::as_str).unwrap_or("").to_lowercase() })
            })
        })
    }

    /// A channel's name as far as already known (None for DMs or not yet known), without waiting.
    fn known_channel(&self, channel: &str) -> Option<String> {
        let book = self.book.as_ref()?;
        let team = self.workspace().unwrap_or_else(|| "?".into());
        let (token, id) = (self.bot_token.clone(), channel.to_string());
        book.channel(&format!("c:{team}:{channel}"), move || Box::pin(async move { channel_name_of(&id, &token).await }))
    }

    /// Channel name via conversations.info (None for DMs), cached for the connection's lifetime.
    async fn channel_name(&self, channel: &str) -> Option<String> {
        if let Some(known) = self.channels.lock().unwrap().get(channel).cloned() {
            return known;
        }
        let name = channel_name_of(channel, &self.bot_token).await;
        self.channels.lock().unwrap().insert(channel.to_string(), name.clone());
        name
    }

    async fn history(&self, thread: &ThreadRef, before: &str, limit: usize) -> Option<Result<Vec<ChatMessage>>> {
        let bot = self.bot_user_id();
        let fetch = async {
            let mut all = Vec::new();
            let mut cursor: Option<String> = None;
            loop {
                let mut params = pairs(&[("channel", &thread.channel), ("ts", &thread.thread_ts), ("limit", "200")]);
                if let Some(c) = &cursor {
                    params.push(("cursor".into(), c.clone()));
                }
                let page = slack_api("conversations.replies", &params, &self.bot_token).await?;
                for m in page.get("messages").and_then(Value::as_array).into_iter().flatten() {
                    let user = m.get("user").or(m.get("bot_id")).and_then(Value::as_str).unwrap_or("unknown").to_string();
                    let from_bot = m.get("bot_id").is_some_and(|b| !b.is_null()) || user == bot;
                    all.push(ChatMessage { ts: m.get("ts").and_then(Value::as_str).unwrap_or("").into(), user, text: m.get("text").and_then(Value::as_str).unwrap_or("").into(), from_bot });
                }
                cursor = page.get("response_metadata").and_then(|r| r.get("next_cursor")).and_then(Value::as_str).filter(|c| !c.is_empty()).map(String::from);
                if cursor.is_none() {
                    break;
                }
            }
            let before: f64 = before.parse().unwrap_or(f64::MAX);
            let earlier: Vec<ChatMessage> = all.into_iter().filter(|m| m.ts.parse::<f64>().unwrap_or(0.0) < before).collect();
            Ok(earlier[earlier.len().saturating_sub(limit)..].to_vec())
        };
        Some(fetch.await)
    }

    /// Any Web API method as the bot; values that are not strings (blocks, arrays) go as JSON, as Slack takes them.
    async fn api(&self, method: &str, params: Map<String, Value>) -> Result<Value> {
        let form: Vec<(String, String)> = params
            .into_iter()
            .filter(|(_, v)| !v.is_null())
            .map(|(k, v)| (k, v.as_str().map(String::from).unwrap_or_else(|| v.to_string())))
            .collect();
        slack_api(method, &form, &self.bot_token).await
    }

    fn working(&self, thread: &ThreadRef, message_ts: Option<&str>, status: &str) {
        let key = format!("{}/{}", thread.channel, thread.thread_ts);
        let line = {
            let mut working = self.working.lock().unwrap();
            let token = self.bot_token.clone();
            let call: Call = Arc::new(move |method, params| {
                let token = token.clone();
                Box::pin(async move { slack_api(&method, &params, &token).await.map(|_| ()) })
            });
            let line = working.entry(key.clone()).or_insert_with(|| ThreadStatus::new(call, &thread.channel, &thread.thread_ts)).clone();
            if status.is_empty() && working.len() > 200 {
                working.remove(&key);
            }
            line
        };
        line.say(status, message_ts);
    }

    async fn stop(&self) {
        self.stopped.send_replace(true);
    }
}

async fn channel_name_of(channel: &str, token: &str) -> Option<String> {
    let r = slack_api("conversations.info", &pairs(&[("channel", channel)]), token).await.ok()?;
    let c = r.get("channel").cloned().unwrap_or(Value::Null);
    if c.get("is_im") == Some(&Value::Bool(true)) {
        return None;
    }
    c.get("name").and_then(Value::as_str).filter(|n| !n.is_empty()).map(String::from)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slack_events_become_messages_and_edits_and_the_rest_is_left() {
        let message = to_event(&json!({ "type": "message", "channel": "C1", "user": "U1", "ts": "2.1", "thread_ts": "1.1", "text": "hi <@UBOT>" }), "UBOT");
        assert_eq!(
            message,
            Some(ChatEvent::Message(InboundMessage { channel: "C1".into(), thread_ts: "1.1".into(), ts: "2.1".into(), user: "U1".into(), text: "hi <@UBOT>".into(), addressed: true }))
        );
        // A message of its own starts its thread; a direct message is addressed.
        let dm = to_event(&json!({ "type": "message", "channel": "D1", "channel_type": "im", "user": "U1", "ts": "3.1", "text": "hey" }), "UBOT");
        assert!(matches!(dm, Some(ChatEvent::Message(ref m)) if m.thread_ts == "3.1" && m.addressed));
        let plain = to_event(&json!({ "type": "message", "channel": "C1", "user": "U1", "ts": "3.2", "text": "chatter" }), "UBOT");
        assert!(matches!(plain, Some(ChatEvent::Message(ref m)) if !m.addressed));
        let edit = to_event(&json!({ "type": "message", "subtype": "message_changed", "channel": "C1", "message": { "ts": "2.1", "thread_ts": "1.1", "text": "new" } }), "UBOT");
        assert_eq!(edit, Some(ChatEvent::Changed { channel: "C1".into(), thread_ts: "1.1".into(), ts: "2.1".into(), text: "new".into() }));
        for left in [
            json!({ "type": "message", "subtype": "message_deleted", "channel": "C1" }),
            json!({ "type": "message", "channel": "C1", "user": "UBOT", "ts": "1" }),
            json!({ "type": "message", "channel": "C1", "bot_id": "B1", "user": "U2", "ts": "1" }),
            json!({ "type": "message", "subtype": "channel_join", "channel": "C1", "user": "U1", "ts": "1" }),
            json!({ "type": "reaction_added" }),
        ] {
            assert_eq!(to_event(&left, "UBOT"), None, "{left}");
        }
    }
}
