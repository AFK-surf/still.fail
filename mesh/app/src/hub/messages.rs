//! session_send: one session's agent writes to another's, on this station or on another station of the workspace
//! (through the station transport, Remote::ask, as station_task goes). The message is posted in the other chat for
//! people to see, headed with a link back to the sender's chat, and handed to the sessions there like any message;
//! they answer the same way. Nothing limits how long two agents talk: that is theirs to judge.

use anyhow::{Result, anyhow, bail};
use futures_util::future::BoxFuture;
use serde_json::{Map, Value, json};
use std::sync::Arc;

use super::others::{Named, linked_session};
use super::{Hub, js_string};
use crate::chat::ThreadRef;
use crate::instructions::thread_address;
use crate::lang::{station, t};
use crate::store::{AuthorKind, NewMessage, STILLFAIL_SURFACE, SessionThread};

/// Calls another station of the workspace by its id with a request; its answer.
pub type PeerCall = Arc<dyn Fn(String, Value) -> BoxFuture<'static, Result<Value>> + Send + Sync>;

/// The method another station's message comes as (Remote::handle hands it to Hub::from_peer).
pub const METHOD: &str = "session.message";

/// At most this much text in one message (a peer request is bounded at 1 MiB).
const MAX_TEXT: usize = 200_000;

/// The station a still.fail link (…/o/<workspace>/<station>/<key>) is on.
pub(super) fn linked_station(reference: &str) -> Option<String> {
    let at = reference.find("/o/")?;
    let parts: Vec<&str> = reference[at + "/o/".len()..].splitn(3, '/').collect();
    match parts.as_slice() {
        [_, station, _] if !station.is_empty() => Some(station.to_string()),
        _ => None,
    }
}

/// Who a message comes from, as its header shows it: the sender's chat by its title, linked when it has a link.
fn header(surface: &str, title: &str, link: Option<&str>) -> String {
    let from = match link {
        Some(link) if surface == STILLFAIL_SURFACE => format!("[{}]({link})", title.replace(['[', ']'], "")),
        Some(link) => format!("<{link}|{}>", title.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('|', "/")),
        None => title.to_string(),
    };
    t!(station(); "station.session.from", from = from)
}

impl Hub {
    /// Hooks session_send up to the other stations of the workspace.
    pub fn on_peer(&self, call: PeerCall) {
        *self.peers.lock().unwrap() = Some(call);
    }

    /// session_send from session `key`.
    pub(super) async fn session_send(&self, key: &str, args: &Map<String, Value>) -> Result<String> {
        let to = args.get("to").map(js_string).unwrap_or_default().trim().to_string();
        let text = args.get("text").map(js_string).unwrap_or_default().trim().to_string();
        if to.is_empty() {
            bail!("to is required: the other chat's link, its session key or a thread address; chat_list lists this station's");
        }
        if text.is_empty() {
            bail!("text is empty");
        }
        if text.chars().count() > MAX_TEXT {
            bail!("text is too long (at most {MAX_TEXT} characters): put the rest in a file and name its path");
        }
        let (title, link) = self.sender(key)?;
        let here = link.as_deref().and_then(linked_station);
        if let Some(there) = linked_station(&to).filter(|s| Some(s) != here.as_ref()) {
            let (target, _) = linked_session(&to).ok_or_else(|| anyhow!("{to} names no chat"))?;
            let call = self.peers.lock().unwrap().clone().ok_or_else(|| anyhow!("other stations cannot be reached from this one yet"))?;
            let request = json!({ "method": METHOD, "session": key, "to": target, "text": text, "from": { "title": title, "link": link } });
            let answer = call(there.clone(), request).await.map_err(|e| {
                // What a station from before session.message answers it with (Remote::handle took it for a task).
                let old = e.to_string();
                if e.downcast_ref::<crate::remote::Refused>().is_some() && (old.contains("remote tasks are not enabled") || old.contains("task key")) {
                    anyhow!("not sent to {to}: that station is not updated yet and takes no messages")
                } else {
                    anyhow!("not sent to {to}: {e}. If it timed out, it may have arrived: ask before sending it again")
                }
            })?;
            let place = answer["thread"].as_str().unwrap_or("its chat");
            return Ok(format!("Sent to {target} on station {there} ({place}). Its agent answers with session_send to your chat."));
        }
        let (thread, targets) = match self.named(&to)? {
            Named::Session { key: target, .. } => {
                if target == key {
                    bail!("that is this session: use chat_post for your own conversations");
                }
                // Said in its chat: every agent there hears it, as they would a person.
                let thread = self.session_thread_of(&target)?;
                let members: Vec<String> = self.store.thread_sessions(thread.thread.id)?.into_iter().map(|m| m.session).collect();
                if members.iter().any(|m| m == key) {
                    bail!("{} is one of your conversations: use chat_post there", thread_address(&thread.thread.channel, &thread.thread.thread_ts));
                }
                (thread, members)
            }
            Named::Thread(thread) => {
                let members = self.store.thread_sessions(thread.id)?;
                if members.iter().any(|m| m.session == key) {
                    bail!("{to} is one of your conversations: use chat_post there");
                }
                let connect = members.first().map(|m| m.connect.clone()).ok_or_else(|| anyhow!("no agent takes part in {to}"))?;
                (SessionThread { thread, connect }, members.into_iter().map(|m| m.session).collect())
            }
        };
        let place = self.post_from(&thread, key, &title, link.as_deref(), &text, &targets).await?;
        Ok(format!("Sent to {place} (agents there: {}). They answer with session_send to your chat.", targets.join(", ")))
    }

    /// A message another station's session sent here (session_send there), from station `peer`.
    pub async fn from_peer(&self, peer: &str, request: &Value) -> Result<Value> {
        let text = request["text"].as_str().unwrap_or("").trim();
        let target = request["to"].as_str().unwrap_or("");
        let sender = request["session"].as_str().unwrap_or("");
        if text.is_empty() || target.is_empty() || sender.is_empty() || text.chars().count() > MAX_TEXT {
            bail!("a message needs to, session and text (at most {MAX_TEXT} characters)");
        }
        if self.store.get_session(target)?.is_none() {
            bail!("no session {target} on this station (it may have been deleted)");
        }
        let thread = self.session_thread_of(target)?;
        let targets: Vec<String> = self.store.thread_sessions(thread.thread.id)?.into_iter().map(|m| m.session).collect();
        let title = request["from"]["title"].as_str().filter(|t| !t.trim().is_empty()).unwrap_or(sender);
        let link = request["from"]["link"].as_str().filter(|l| !l.is_empty());
        // Not a session of this station: by its station and key, so it is never taken for one.
        let author = format!("{peer}/{sender}");
        let place = self.post_from(&thread, &author, title, link, text, &targets).await?;
        Ok(json!({ "thread": place }))
    }

    /// The sender's chat as a message from it is headed: its title, and its link once the station is in a workspace.
    fn sender(&self, key: &str) -> Result<(String, Option<String>)> {
        let row = self.store.get_session(key)?.ok_or_else(|| anyhow!("unknown session"))?;
        let thread = self.session_thread_of(key).ok().map(|t| t.thread);
        let title = thread.as_ref().and_then(|t| t.title.clone().or_else(|| t.auto_title.clone())).or(row.title).filter(|t| !t.trim().is_empty());
        Ok((title.unwrap_or_else(|| key.to_string()), (self.link)(key)))
    }

    /// Posts `text` from `author` in `thread`, headed with where it comes from, and hands it to `targets`. Its address.
    async fn post_from(&self, thread: &SessionThread, author: &str, title: &str, link: Option<&str>, text: &str, targets: &[String]) -> Result<String> {
        let row = &thread.thread;
        let said = format!("{}\n\n{text}", header(&row.surface, title, link));
        let chat = self.chat(&thread.connect)?;
        let ts = chat.post(&ThreadRef::new(&row.channel, &row.thread_ts), &said, &[]).await?;
        let (n, _) = self.store.insert_message(NewMessage::new(row.id, &ts, AuthorKind::Agent, author, &said))?;
        let targets: Vec<String> = targets.iter().filter(|t| *t != author).cloned().collect();
        self.hand_over(row.id, n, &targets, &said)?;
        Ok(thread_address(&row.channel, &row.thread_ts))
    }
}
