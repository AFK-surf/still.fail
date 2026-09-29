//! What the people of a chat hear about while no client of theirs runs (docs/notifications.md): an agent's turn
//! ending in one of the station's own chats (done with something said, or blocked), something going wrong there (the
//! station says so, ⚠️ first: a failed turn, an agent that could not start), and a person saying something there. Noticed from the store's changes as they come, whoever follows the pages; handed to the station
//! process (stillfail-station), which posts them to still.fail cloud for its pushes. Only what happens from now on
//! is noticed.

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex, OnceLock, Weak};

use serde_json::{Value, json};
use tokio::sync::broadcast;
use tracing::warn;

use super::AdminApi;
use super::views::chat_title;
use crate::store::{AuthorKind, EntryKind, EntryRow, MessageRow, STILLFAIL_SURFACE, StoreChange, TurnSummary};

/// How long a notice's text is kept, in characters (still.fail cloud cuts it shorter).
const TEXT: usize = 400;

/// Where notices go: whoever posts them (the station process) subscribes. Nobody listening, they go nowhere.
pub fn outbox() -> &'static broadcast::Sender<Value> {
    static OUTBOX: OnceLock<broadcast::Sender<Value>> = OnceLock::new();
    OUTBOX.get_or_init(|| broadcast::channel(256).0)
}

pub struct Notifier {
    api: Weak<AdminApi>,
    /// Each session's last turn noticed (when it ended), so one turn is noticed once.
    ended: Mutex<HashMap<String, i64>>,
    since: i64,
}

impl Notifier {
    /// Starts noticing what happens from now on.
    pub fn start(api: &Arc<AdminApi>) {
        let notifier = Arc::new(Notifier { api: Arc::downgrade(api), ended: Mutex::default(), since: crate::store::now_ms() });
        let mut changes = api.deps.store.subscribe();
        tokio::spawn(async move {
            loop {
                match changes.recv().await {
                    Ok(change) => {
                        if notifier.api.upgrade().is_none() {
                            return;
                        }
                        if let Err(error) = notifier.changed(change) {
                            warn!(%error, "a notice could not be made");
                        }
                    }
                    Err(broadcast::error::RecvError::Lagged(_)) => {}
                    Err(broadcast::error::RecvError::Closed) => return,
                }
            }
        });
    }

    fn changed(&self, change: StoreChange) -> anyhow::Result<()> {
        let Some(api) = self.api.upgrade() else { return Ok(()) };
        match change {
            StoreChange::Session(key) => self.session_changed(&api, &key),
            StoreChange::Thread { id, entries } => self.said(&api, id, &entries),
            _ => Ok(()),
        }
    }

    /// A turn that ended since the last look: its chats hear how.
    fn session_changed(&self, api: &AdminApi, key: &str) -> anyhow::Result<()> {
        let store = &api.deps.store;
        let Some(turn) = store.session_stats(Some(key))?.remove(key).and_then(|s| s.last_turn) else { return Ok(()) };
        let Some(ended) = turn.ended_at.filter(|at| *at >= self.since) else { return Ok(()) };
        if self.ended.lock().unwrap().insert(key.to_string(), ended) == Some(ended) {
            return Ok(());
        }
        for place in store.session_threads(key)? {
            let thread = place.thread;
            if thread.surface != STILLFAIL_SURFACE || thread.hidden_at.is_some() {
                continue;
            }
            let last = store.last_message(thread.id)?;
            let Some((kind, text)) = turn_notice(&turn, last.as_ref(), key) else { continue };
            let by = api.author_names(thread.id)(AuthorKind::Agent, key).unwrap_or_default();
            self.send(api, thread.id, key, kind, &by, &text, None);
        }
        Ok(())
    }

    /// In the station's own chats: people's messages (the chat's other people hear them), and the station saying
    /// something went wrong (everyone does).
    fn said(&self, api: &AdminApi, id: i64, entries: &[EntryRow]) -> anyhow::Result<()> {
        let new = |e: &&EntryRow| e.kind == EntryKind::Message && e.at >= self.since;
        let person = entries.iter().filter(new).filter(|e| e.author_kind == AuthorKind::Person).last();
        let wrong = entries.iter().filter(new).filter(|e| e.author_kind == AuthorKind::StillFail).filter_map(|e| went_wrong(e.text.as_deref()?)).last();
        if person.is_none() && wrong.is_none() {
            return Ok(());
        }
        let Some(thread) = api.deps.store.get_thread(id)? else { return Ok(()) };
        if thread.surface != STILLFAIL_SURFACE || thread.hidden_at.is_some() {
            return Ok(());
        }
        let Some(session) = api.deps.store.thread_sessions(id)?.first().map(|m| m.session.clone()) else { return Ok(()) };
        if let Some(said) = person {
            let by = api.author_names(id)(AuthorKind::Person, &said.author).unwrap_or_else(|| said.author.clone());
            let text = said.text.clone().filter(|t| !t.trim().is_empty()).unwrap_or_else(|| "（文件）".into());
            self.send(api, id, &session, "message", &by, &text, Some(&said.author));
        }
        if let Some(text) = wrong {
            self.send(api, id, &session, "failed", "", &text, None);
        }
        Ok(())
    }

    /// Hands a notice to the station process, for the chat's people (but `except`, who said it).
    #[allow(clippy::too_many_arguments)]
    fn send(&self, api: &AdminApi, thread: i64, session: &str, kind: &str, by: &str, text: &str, except: Option<&str>) {
        let Ok(Some(summary)) = api.deps.store.list_threads("", None, Some(thread)).map(|mut l| l.pop()) else { return };
        let to = people(api, &summary.thread.created_by, &summary.people, &summary.sessions.iter().map(|m| m.session.clone()).collect::<Vec<_>>(), except);
        if to.is_empty() || outbox().receiver_count() == 0 {
            return;
        }
        let _ = outbox().send(json!({
            "to": to, "kind": kind, "session": session, "thread": thread,
            "title": chat_title(&summary, None), "by": by, "text": text.chars().take(TEXT).collect::<String>(),
            "at": crate::store::now_ms(),
        }));
    }
}

/// What a turn's end is worth telling its chat, and in what words: blocked, or done having said something there (the
/// chat's last message is the agent's, from this turn). A turn that ended any other way (waiting, stopped, without a
/// state, when it is asked again) says nothing; one that failed, the station says so in the chat (`went_wrong`).
fn turn_notice(turn: &TurnSummary, last: Option<&MessageRow>, key: &str) -> Option<(&'static str, String)> {
    let theirs = last.filter(|m| m.author_kind == AuthorKind::Agent && m.author == key && m.created_at >= turn.started_at);
    let text = theirs.map(|m| m.text.clone()).filter(|t| !t.trim().is_empty());
    match (turn.declared.as_deref(), turn.outcome.as_deref()) {
        (Some("block"), _) => Some(("block", text.unwrap_or_default())),
        (_, Some("failed")) => None,
        (Some("final"), _) => theirs.map(|_| ("done", text.unwrap_or_else(|| "（文件）".into()))),
        _ => None,
    }
}

/// The station's word in a chat that something went wrong (⚠️ first, as session.rs posts it): what went wrong.
fn went_wrong(text: &str) -> Option<String> {
    text.strip_prefix("⚠️").map(|t| t.trim().to_string())
}

/// The emails of a chat's people: who made it, who said something in it, who started its agents; but `except`.
fn people(api: &AdminApi, creator: &Option<String>, said: &[String], sessions: &[String], except: Option<&str>) -> Vec<String> {
    let starters: Vec<String> = sessions.iter().filter_map(|k| api.deps.store.get_session(k).ok().flatten()?.created_by).collect();
    let refs: Vec<String> = creator.iter().cloned().chain(said.iter().cloned()).chain(starters).collect();
    let except = except.map(str::to_lowercase);
    let mut seen = HashSet::new();
    api.people(&refs).into_iter()
        .filter_map(|p| p["email"].as_str().map(str::to_lowercase))
        .filter(|e| Some(e) != except.as_ref() && seen.insert(e.clone()))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn turn(declared: Option<&str>, outcome: &str) -> TurnSummary {
        TurnSummary { kind: "message".into(), outcome: Some(outcome.into()), declared: declared.map(str::to_string), wait_seconds: None, detail: Some("rate_limit: 用完了".into()), started_at: 100, ended_at: Some(200) }
    }

    fn said(kind: AuthorKind, author: &str, at: i64) -> MessageRow {
        MessageRow { thread: 1, n: 3, ts: "1.1".into(), author_kind: kind, author: author.into(), text: "修好了".into(), attachments: vec![], quotes: vec![], declared: None, created_at: at, edited_at: None }
    }

    #[test]
    fn a_turn_is_told_by_how_it_ended() {
        let mine = said(AuthorKind::Agent, "k", 150);
        assert_eq!(turn_notice(&turn(Some("final"), "completed"), Some(&mine), "k"), Some(("done", "修好了".into())));
        assert_eq!(turn_notice(&turn(Some("block"), "completed"), Some(&mine), "k"), Some(("block", "修好了".into())));
        // Said nothing this turn: done says nothing, failed says why.
        let old = said(AuthorKind::Agent, "k", 50);
        assert_eq!(turn_notice(&turn(Some("final"), "completed"), Some(&old), "k"), None);
        // A failed one: the station's ⚠️ in the chat tells it.
        assert_eq!(turn_notice(&turn(None, "failed"), Some(&old), "k"), None);
        assert_eq!(went_wrong("⚠️ 无法启动 agent：没有 claude").as_deref(), Some("无法启动 agent：没有 claude"));
        assert_eq!(went_wrong("已停止当前任务"), None);
        // Someone else had the last word; a turn with no state or waiting is asked again.
        assert_eq!(turn_notice(&turn(Some("final"), "completed"), Some(&said(AuthorKind::Person, "a@b.c", 150)), "k"), None);
        assert_eq!(turn_notice(&turn(None, "completed"), Some(&mine), "k"), None);
        assert_eq!(turn_notice(&turn(Some("waiting"), "completed"), Some(&mine), "k"), None);
    }
}
