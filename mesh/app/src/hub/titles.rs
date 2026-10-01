//! A chat named by its agent (chat_post's title): the first name at once, a new one only when the talk has moved on
//! (people said enough since, and it was not changed too often), never over a name people gave it, and not while
//! someone has the chat open: then it waits until they leave.

use std::time::Duration;

use anyhow::Result;

use super::Hub;
use crate::store::{STILLFAIL_SURFACE, ThreadRow, now_ms};

/// How long a title may run.
const LONGEST: usize = 30;
/// Messages people write after a title before it may change.
const SAID_BEFORE_CHANGE: i64 = 5;
/// Changes after the first title.
const CHANGES: i64 = 2;
/// A chat read this lately is taken as open.
const OPEN_MS: i64 = 3 * 60 * 1000;
/// How often a title that waits for a chat to be left looks again.
const LOOK_AGAIN: Duration = Duration::from_secs(60);

/// A title as a chat shows it: one line, spaces collapsed, no closing full stop, at most LONGEST characters.
pub(super) fn clean_title(title: &str) -> String {
    let line = title.split_whitespace().collect::<Vec<_>>().join(" ");
    let line = line.trim_end_matches(['.', '。']).trim_end();
    line.chars().take(LONGEST).collect::<String>().trim_end().to_string()
}

/// What became of a title an agent gave.
enum Named {
    Now,
    Same,
    Later,
    Not(&'static str),
}

impl Hub {
    /// Names `thread` `title` as its agent asked (chat_post's title); what came of it, for the agent.
    pub(super) fn name_chat(&self, thread: &ThreadRow, title: &str) -> Result<String> {
        let title = clean_title(title);
        if title.is_empty() {
            return Ok(String::new());
        }
        let named = match self.may_name(thread.id, &title)? {
            Err(why) => Named::Not(why),
            Ok(false) => Named::Same,
            Ok(true) if self.is_open(thread.id)? && self.store.auto_title(thread.id)?.title.is_some() => {
                self.wait_to_name(thread.id, title.clone());
                Named::Later
            }
            Ok(true) => {
                self.apply_title(thread.id, &title)?;
                Named::Now
            }
        };
        Ok(match named {
            Named::Now => format!(" Titled the chat \"{title}\"."),
            Named::Same => String::new(),
            Named::Later => format!(" The chat will be titled \"{title}\" once nobody has it open."),
            Named::Not(why) => format!(" Title not changed: {why}."),
        })
    }

    /// Whether `title` may name the chat now (false: it already does), or why not.
    fn may_name(&self, thread: i64, title: &str) -> Result<std::result::Result<bool, &'static str>> {
        let Some(row) = self.store.get_thread(thread)? else { return Ok(Err("the chat is gone")) };
        if row.surface != STILLFAIL_SURFACE {
            return Ok(Err("a Slack thread is named in Slack"));
        }
        if row.title.as_deref().is_some_and(|t| !t.trim().is_empty()) {
            return Ok(Err("people named this chat"));
        }
        let given = self.store.auto_title(thread)?;
        let Some(current) = given.title else { return Ok(Ok(true)) };
        if current == title {
            return Ok(Ok(false));
        }
        if given.changes >= CHANGES {
            return Ok(Err("it has been changed as often as it may be"));
        }
        // A watch started since: the name may say so at once (job_start's watch), not only once the talk moved on.
        if self.store.people_said_after(thread, given.n)? < SAID_BEFORE_CHANGE && !self.watching_in(thread)? {
            return Ok(Err("people have said too little since it was given; change it only when it no longer says what the chat is about"));
        }
        Ok(Ok(true))
    }

    /// Whether one of the chat's agents keeps watch (a watch job of its runs).
    fn watching_in(&self, thread: i64) -> Result<bool> {
        for member in self.store.thread_sessions(thread)? {
            if self.store.list_jobs(Some(&member.session))?.iter().any(|j| j.watch && j.state == "running") {
                return Ok(true);
            }
        }
        Ok(false)
    }

    fn is_open(&self, thread: i64) -> Result<bool> {
        Ok(self.store.last_read_at(thread)?.is_some_and(|at| now_ms() - at < OPEN_MS))
    }

    fn apply_title(&self, thread: i64, title: &str) -> Result<()> {
        let changed = self.store.auto_title(thread)?.title.is_some();
        self.store.set_auto_title(thread, title, changed)
    }

    /// Keeps `title` for when nobody has the chat open (the latest one given wins), and looks now and then.
    fn wait_to_name(&self, thread: i64, title: String) {
        if self.titles.lock().unwrap().insert(thread, title).is_some() {
            return;
        }
        let me = self.me.clone();
        tokio::spawn(async move {
            loop {
                tokio::time::sleep(LOOK_AGAIN).await;
                let Some(hub) = me.upgrade() else { return };
                match hub.is_open(thread) {
                    Ok(true) => continue,
                    Ok(false) => {}
                    Err(e) => tracing::warn!("titling chat {thread}: {e:#}"),
                }
                let Some(title) = hub.titles.lock().unwrap().remove(&thread) else { return };
                // Looked at again: people may have named the chat meanwhile.
                if let Err(e) = hub.may_name(thread, &title).and_then(|may| if may == Ok(true) { hub.apply_title(thread, &title) } else { Ok(()) }) {
                    tracing::warn!("titling chat {thread}: {e:#}");
                }
                return;
            }
        });
    }
}
