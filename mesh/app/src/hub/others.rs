//! Other conversations and sessions of the station, for an agent to read (chat_list, chat_read, session_history):
//! people refer to another chat by its link, and the agent reads what was said there and what its agents did.

use anyhow::{Result, anyhow, bail};
use serde_json::{Map, Value};

use super::{Hub, js_number, js_string};
use crate::admin::percent_decode;
use crate::instructions::{parse_thread_address, thread_address};
use crate::store::{STILLFAIL_SURFACE, ThreadRow};
use crate::transcript::TimelineEntry;

/// What an agent named: a conversation, or a session (maybe one entry of its execution history).
#[derive(Debug, Clone, PartialEq)]
pub(super) enum Named {
    Thread(ThreadRow),
    Session { key: String, entry: Option<usize> },
}

/// A session key a reference holds, in whichever form people pass chats around: a chat's page
/// (…/chats/<key>), a still.fail link (…/o/<workspace>/<station>/<key>), a link to execution history (?history=<key>&entry=<n>).
pub(super) fn linked_session(reference: &str) -> Option<(String, Option<usize>)> {
    let end = |s: &str| s.find(|c: char| matches!(c, '/' | '?' | '#' | ')' | '>' | '|' | '"' | '\'') || c.is_whitespace()).unwrap_or(s.len());
    if let Some(at) = reference.find("history=") {
        let rest = &reference[at + "history=".len()..];
        let key = percent_decode(&rest[..rest.find(|c: char| c == '&' || c == '#' || c == ')' || c == '>' || c == '|' || c.is_whitespace()).unwrap_or(rest.len())]);
        let entry = reference.find("entry=").and_then(|at| {
            let digits: String = reference[at + "entry=".len()..].chars().take_while(char::is_ascii_digit).collect();
            digits.parse().ok()
        });
        return (!key.is_empty()).then_some((key, entry));
    }
    let segment = |rest: &str| percent_decode(&rest[..end(rest)].replace('+', "%2B"));
    if let Some(at) = reference.find("/chats/") {
        let key = segment(&reference[at + "/chats/".len()..]);
        return (!key.is_empty()).then_some((key, None));
    }
    if let Some(at) = reference.find("/o/") {
        let parts: Vec<&str> = reference[at + "/o/".len()..].splitn(3, '/').collect();
        if let [_, _, rest] = parts.as_slice() {
            let key = segment(rest);
            return (!key.is_empty()).then_some((key, None));
        }
    }
    None
}

/// Cuts text to `max` characters, saying how much was left out.
fn cut(text: &str, max: usize) -> String {
    let count = text.chars().count();
    if count <= max {
        return text.to_string();
    }
    format!("{}… ({} more characters)", text.chars().take(max).collect::<String>(), count - max)
}

/// One-line text: a title or a message's start, as a list shows it.
fn line(text: &str, max: usize) -> String {
    cut(&text.split_whitespace().collect::<Vec<_>>().join(" "), max)
}

/// Execution history entries as the agent reads them: numbered as the pages number them (…&entry=<n>).
pub(super) fn format_steps(start: usize, entries: &[TimelineEntry], max_chars: usize) -> String {
    entries
        .iter()
        .enumerate()
        .map(|(i, e)| {
            let what = match (&e.kind[..], &e.tool, e.ok) {
                ("tool_call", Some(tool), _) => format!("tool_call {tool}"),
                ("tool_result", _, Some(false)) => "tool_result (error)".to_string(),
                (kind, _, _) => kind.to_string(),
            };
            let sub = if e.subagent == Some(true) { " subagent" } else { "" };
            let at = e.at.as_deref().map(|at| format!(" {at}")).unwrap_or_default();
            format!("#{}{at} {what}{sub}:\n{}", start + i, cut(e.text.trim(), max_chars))
        })
        .collect::<Vec<_>>()
        .join("\n\n")
}

impl Hub {
    /// What a reference names on this station: a chat link, an execution history link, a thread address
    /// (CHANNEL/THREAD_TS) or a session key.
    pub(super) fn named(&self, reference: &str) -> Result<Named> {
        let reference = reference.trim();
        if reference.is_empty() {
            bail!("chat is required: a chat's link, a thread address (CHANNEL/THREAD_TS) or a session key; chat_list lists them");
        }
        if let Some((key, entry)) = linked_session(reference) {
            if self.store.get_session(&key)?.is_none() {
                bail!("{reference} names session {key}, which is not on this station (it may be another station's, or deleted)");
            }
            return Ok(Named::Session { key, entry });
        }
        if let Some((channel, thread_ts)) = parse_thread_address(reference) {
            let mut found = self.store.threads_at(&channel, &thread_ts)?;
            if found.is_empty() {
                bail!("no conversation {reference} on this station");
            }
            return Ok(Named::Thread(found.remove(0)));
        }
        if self.store.get_session(reference)?.is_some() {
            return Ok(Named::Session { key: reference.to_string(), entry: None });
        }
        bail!("{} is not a chat of this station: give a chat's link, a thread address (CHANNEL/THREAD_TS) or a session key; chat_list lists them", Value::String(reference.into()))
    }

    /// The conversation a session is best read in: its own chat on the pages, else the one it last heard from.
    pub(super) fn session_thread_of(&self, key: &str) -> Result<crate::store::SessionThread> {
        let threads = self.store.session_threads(key)?;
        if let Some(home) = threads.iter().find(|t| t.thread.home.as_deref() == Some(key)) {
            return Ok(home.clone());
        }
        self.store.latest_thread(key)?.ok_or_else(|| anyhow!("session {key} has no conversation yet"))
    }

    /// chat_list: the station's conversations, the latest first, each with its agents (session keys).
    pub(super) fn chat_list(&self, key: &str, args: &Map<String, Value>) -> Result<String> {
        let limit = args.get("limit").and_then(js_number).map(|n| n.clamp(1.0, 100.0) as usize).unwrap_or(20);
        let query = args.get("query").map(js_string).unwrap_or_default().trim().to_lowercase();
        let sessions: std::collections::HashMap<String, crate::store::SessionRow> = self.store.list_sessions()?.into_iter().map(|s| (s.key.clone(), s)).collect();
        let mut threads = self.store.list_threads("", None, None)?;
        threads.sort_by_key(|t| std::cmp::Reverse(t.last_message.as_ref().map(|m| m.created_at).unwrap_or(t.thread.created_at)));
        let mut lines = Vec::new();
        let mut matched = 0;
        for t in &threads {
            let titles: Vec<String> = t.thread.title.iter().chain(t.thread.auto_title.iter()).chain(t.first_text.iter()).cloned().chain(t.sessions.iter().filter_map(|m| sessions.get(&m.session)?.title.clone())).collect();
            let last = t.last_message.as_ref().map(|m| m.text.clone()).unwrap_or_default();
            if !query.is_empty() {
                let haystack = format!("{} {} {}", titles.join(" "), last, t.sessions.iter().map(|m| m.session.as_str()).collect::<Vec<_>>().join(" ")).to_lowercase();
                if !haystack.contains(&query) {
                    continue;
                }
            }
            matched += 1;
            if lines.len() >= limit {
                continue;
            }
            let address = thread_address(&t.thread.channel, &t.thread.thread_ts);
            let place = if t.thread.surface == STILLFAIL_SURFACE { "still.fail chat" } else { "Slack thread" };
            let title = titles.first().map(|t| line(t, 80)).unwrap_or_else(|| "(untitled)".into());
            let agents: Vec<String> = t
                .sessions
                .iter()
                .map(|m| {
                    let mine = if m.session == key { " (you)" } else { "" };
                    let archived = if sessions.get(&m.session).is_some_and(|s| s.archived_at.is_some()) { " archived" } else { "" };
                    format!("{}{mine}{archived}", m.session)
                })
                .collect();
            let when = t.last_message.as_ref().map(|m| crate::transcript::iso(m.created_at)).unwrap_or_else(|| crate::transcript::iso(t.thread.created_at));
            let hidden = if t.thread.hidden_at.is_some() { ", archived" } else { "" };
            let mut entry = format!("- {address} ({place}{hidden}) \"{title}\"\n  agents: {}; last message {when}", if agents.is_empty() { "none".into() } else { agents.join(", ") });
            if !last.is_empty() {
                entry.push_str(&format!(": {}", line(&last, 120)));
            }
            lines.push(entry);
        }
        if lines.is_empty() {
            return Ok(if query.is_empty() { "No conversations on this station.".into() } else { format!("No conversation matches {}.", Value::String(query)) });
        }
        let more = if matched > lines.len() { format!("\n({} more; raise limit or narrow query)", matched - lines.len()) } else { String::new() };
        Ok(format!("{}{more}", lines.join("\n")))
    }

    /// chat_read: the messages of any conversation of the station.
    pub(super) async fn chat_read(&self, key: &str, args: &Map<String, Value>) -> Result<String> {
        let reference = args.get("chat").map(js_string).unwrap_or_default();
        let (thread, connect, note) = match self.named(&reference)? {
            Named::Thread(thread) => {
                let connect = self.store.thread_sessions(thread.id)?.first().map(|m| m.connect.clone()).unwrap_or_default();
                (thread, connect, String::new())
            }
            Named::Session { key: session, .. } => {
                let found = self.session_thread_of(&session)?;
                let others: Vec<String> = self
                    .store
                    .session_threads(&session)?
                    .iter()
                    .filter(|t| t.thread.id != found.thread.id)
                    .map(|t| thread_address(&t.thread.channel, &t.thread.thread_ts))
                    .collect();
                let note = if others.is_empty() { String::new() } else { format!("\n(Session {session} also takes part in {}; read them with chat_read chat=<address>.)", others.join(", ")) };
                (found.thread, found.connect, note)
            }
        };
        let named = thread_address(&thread.channel, &thread.thread_ts);
        let text = self.thread_history(key, &thread, &connect, &named, args).await?;
        let agents: Vec<String> = self.store.thread_sessions(thread.id)?.into_iter().map(|m| m.session).collect();
        let head = format!("Conversation {named}; its agents: {}.", if agents.is_empty() { "none".into() } else { agents.join(", ") });
        Ok(format!("{head}\n{text}{note}"))
    }

    /// session_history: what a session's agent did (its execution history, as the pages show it), from its transcript.
    pub(super) fn session_history(&self, args: &Map<String, Value>) -> Result<String> {
        let reference = args.get("chat").map(js_string).unwrap_or_default();
        let (session, entry) = match self.named(&reference)? {
            Named::Session { key, entry } => (key, entry),
            Named::Thread(thread) => {
                let agents: Vec<String> = self.store.thread_sessions(thread.id)?.into_iter().map(|m| m.session).collect();
                match agents.as_slice() {
                    [only] => (only.clone(), None),
                    [] => bail!("{reference} has no agent, so no execution history"),
                    many => bail!("{reference} has several agents; give one of them as chat: {}", many.join(", ")),
                }
            }
        };
        let limit = args.get("limit").and_then(js_number).map(|n| n.clamp(1.0, 200.0) as usize).unwrap_or(40);
        let max_chars = args.get("max_chars").and_then(js_number).map(|n| n.clamp(100.0, 4000.0) as usize).unwrap_or(1500);
        let before = match args.get("before").and_then(js_number) {
            Some(n) => n.max(0.0) as usize,
            // A link to one entry: it and what came around it.
            None => entry.map(|n| n + 1 + limit / 2).unwrap_or(usize::MAX),
        };
        let row = self.store.get_session(&session)?.ok_or_else(|| anyhow!("unknown session {session}"))?;
        let Some((_, all)) = self.live.before(&session, usize::MAX, usize::MAX) else {
            return Ok(format!("Session {session} has no execution history yet."));
        };
        let total = all.len();
        let end = before.min(total);
        let start = end.saturating_sub(limit);
        let entries = &all[start..end];
        if total == 0 {
            return Ok(format!("Session {session} has no execution history yet."));
        }
        if entries.is_empty() {
            return Ok(format!("Session {session} has {total} entries of execution history; none before #{before}."));
        }
        let model = row.model.as_deref().map(|m| format!(", {m}")).unwrap_or_default();
        let older = if start > 0 { format!(" Older ones: before={start}.") } else { String::new() };
        let head = format!("Session {session} ({}{model}): entries #{start}–#{} of {total}.{older}", row.runtime, start + entries.len() - 1);
        Ok(format!("{head}\n\n{}", format_steps(start, entries, max_chars)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn references_name_sessions_in_every_link_form() {
        let key = |r: &str| linked_session(r);
        assert_eq!(key("http://127.0.0.1:4760/admin/chats/c-e74a0bfa0b"), Some(("c-e74a0bfa0b".into(), None)));
        assert_eq!(key("[修 bug](https://ember.3720.org/w/ws1/s/st1/chats/cl%3AC1%3A1.2?x=1)"), Some(("cl:C1:1.2".into(), None)));
        assert_eq!(key("<https://ember.3720.org/o/ws1/st1/c-abc|在 ember 里查看>"), Some(("c-abc".into(), None)));
        assert_eq!(key("https://ember.3720.org/w/ws/s/st/chats/c-1?history=c-2&entry=41"), Some(("c-2".into(), Some(41))));
        // Links of the new domain read the same.
        assert_eq!(key("<https://app.still.fail/o/ws1/st1/c-abc|在 still.fail 里查看>"), Some(("c-abc".into(), None)));
        assert_eq!(key("https://app.still.fail/w/ws1/s/st1/chats/c-2"), Some(("c-2".into(), None)));
        assert_eq!(key("C1/1.000001"), None);
        assert_eq!(key("c-abc"), None);
    }

    #[test]
    fn steps_are_numbered_and_cut() {
        let entry = |kind: &str, tool: Option<&str>, text: &str| TimelineEntry {
            at: Some("2026-09-29T00:00:00.000Z".into()),
            kind: kind.into(),
            text: text.into(),
            tool: tool.map(String::from),
            ok: None,
            call_id: None,
            subagent: None,
        };
        let text = format_steps(7, &[entry("assistant", None, "好的"), entry("tool_call", Some("Bash"), "ls -la /tmp")], 4);
        assert_eq!(text, "#7 2026-09-29T00:00:00.000Z assistant:\n好的\n\n#8 2026-09-29T00:00:00.000Z tool_call Bash:\nls -… (7 more characters)");
    }
}
