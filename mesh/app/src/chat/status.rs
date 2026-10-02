//! What an agent is doing, said in the Slack thread it works for while it works: Slack's own status line under the
//! thread (assistant.threads.setStatus), updated at most every couple of seconds and cleared when the turn ends. Where
//! Slack will not show one (the app lacks the scope, the conversation does not take it), an 👀 on the message that
//! started the work says the same, and goes when it is done.

use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::Result;
use futures_util::future::BoxFuture;
use tokio::sync::Mutex as AsyncMutex;
use tracing::warn;

use crate::lang::t;
use crate::store::now_ms;

/// How often the status line may change: Slack's limit on the call, and enough to follow along.
const MIN_INTERVAL_MS: i64 = 2_000;
const FALLBACK_REACTION: &str = "eyes";

/// What Slack answers when it will not show a status here: the reaction says it instead.
fn no_status(error: &str) -> bool {
    ["missing_scope", "unknown_method", "not_allowed_token_type", "feature_not_enabled", "method_not_supported_for_channel_type", "not_in_channel"]
        .iter()
        .any(|code| error.contains(code))
}

pub type Call = Arc<dyn Fn(String, Vec<(String, String)>) -> BoxFuture<'static, Result<()>> + Send + Sync>;

struct Line {
    message_ts: Option<String>,
    shown: String,
    wanted: String,
    last_at: i64,
    timer: bool,
    /// Slack will not show a status line here: the reaction stands in.
    reaction_only: bool,
    reacted: Option<String>,
}

/// One thread's status line. `say("")` clears it.
pub struct ThreadStatus {
    call: Call,
    channel: String,
    thread_ts: String,
    line: Mutex<Line>,
    sending: AsyncMutex<()>,
}

impl ThreadStatus {
    pub fn new(call: Call, channel: &str, thread_ts: &str) -> Arc<ThreadStatus> {
        Arc::new(ThreadStatus {
            call,
            channel: channel.into(),
            thread_ts: thread_ts.into(),
            line: Mutex::new(Line { message_ts: None, shown: String::new(), wanted: String::new(), last_at: 0, timer: false, reaction_only: false, reacted: None }),
            sending: AsyncMutex::new(()),
        })
    }

    pub fn say(self: &Arc<Self>, status: &str, message_ts: Option<&str>) {
        let wait = {
            let mut line = self.line.lock().unwrap();
            if let Some(ts) = message_ts {
                line.message_ts = Some(ts.to_string());
            }
            line.wanted = status.to_string();
            if line.timer {
                return;
            }
            line.timer = true;
            if status.is_empty() { 0 } else { (line.last_at + MIN_INTERVAL_MS - now_ms()).max(0) }
        };
        let me = self.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(wait as u64)).await;
            let next = {
                let mut line = me.line.lock().unwrap();
                line.timer = false;
                if line.wanted == line.shown {
                    return;
                }
                line.last_at = now_ms();
                line.wanted.clone()
            };
            let _order = me.sending.lock().await;
            me.send(next).await;
        });
    }

    async fn send(&self, status: String) {
        let reaction_only = self.line.lock().unwrap().reaction_only;
        if !reaction_only {
            let mut params = vec![("channel_id".to_string(), self.channel.clone()), ("thread_ts".to_string(), self.thread_ts.clone()), ("status".to_string(), status.clone())];
            if !status.is_empty() {
                params.push(("loading_messages".into(), status.clone()));
            }
            match (self.call)("assistant.threads.setStatus".into(), params).await {
                Ok(()) => {
                    self.line.lock().unwrap().shown = status;
                    return;
                }
                Err(error) if !no_status(&error.to_string()) => {
                    warn!(channel = self.channel, thread = self.thread_ts, error = %error, "could not say the agent's status in Slack");
                    return;
                }
                Err(_) => self.line.lock().unwrap().reaction_only = true,
            }
        }
        let (target, reacted) = {
            let mut line = self.line.lock().unwrap();
            line.shown = status.clone();
            (line.message_ts.clone(), line.reacted.clone())
        };
        let result = if !status.is_empty() {
            match target.filter(|t| reacted.as_deref() != Some(t.as_str())) {
                Some(target) => {
                    let done = (self.call)("reactions.add".into(), self.reaction(&target)).await;
                    if done.is_ok() {
                        self.line.lock().unwrap().reacted = Some(target);
                    }
                    done
                }
                None => Ok(()),
            }
        } else if let Some(reacted) = reacted {
            self.line.lock().unwrap().reacted = None;
            (self.call)("reactions.remove".into(), self.reaction(&reacted)).await
        } else {
            Ok(())
        };
        if let Err(error) = result {
            let said = error.to_string();
            if !said.contains("already_reacted") && !said.contains("no_reaction") {
                warn!(channel = self.channel, error = said, "could not mark the agent's work in Slack");
            }
        }
    }

    fn reaction(&self, timestamp: &str) -> Vec<(String, String)> {
        vec![("channel".into(), self.channel.clone()), ("timestamp".into(), timestamp.into()), ("name".into(), FALLBACK_REACTION.into())]
    }
}

/// A tool call in words for the status line, by the tool's name (Claude Code's or Codex's).
pub fn tool_status(tool: &str) -> String {
    let lower = tool.to_lowercase();
    let name = match lower.strip_prefix("mcp__") {
        Some(rest) => rest.split_once("__").map(|(_, n)| n.to_string()).unwrap_or(lower.clone()),
        None => lower.clone(),
    };
    let starts = |prefixes: &[&str]| prefixes.iter().any(|p| name.starts_with(p));
    let key = if starts(&["read", "grep", "glob", "ls", "list", "view", "search_files", "stat"]) {
        "station.status.readingFiles"
    } else if starts(&["edit", "multiedit", "write", "apply_patch", "notebookedit", "delete", "copy"]) {
        "station.status.editingFiles"
    } else if starts(&["bash", "shell", "exec", "exec_command", "local_shell", "unified_exec", "run"]) {
        "station.status.runningCommand"
    } else if starts(&["websearch", "web_search", "search_query", "image_query"]) {
        "station.status.searchingWeb"
    } else if starts(&["webfetch", "fetch", "browse"]) {
        "station.status.readingWeb"
    } else if starts(&["task", "agent", "spawn"]) {
        "station.status.delegating"
    } else if starts(&["chat_", "slack"]) {
        "station.status.readingSlack"
    } else if starts(&["todowrite", "update_plan", "plan"]) {
        "station.status.planning"
    } else {
        "station.status.working"
    };
    // Said in Slack by the station: in its own language.
    t!(crate::lang::station(); key)
}

#[cfg(test)]
mod tests {
    use super::*;
    use anyhow::anyhow;

    type Calls = Arc<Mutex<Vec<(String, Vec<(String, String)>)>>>;

    fn recording(fail: Option<&'static str>) -> (Call, Calls) {
        let calls: Calls = Arc::default();
        let seen = calls.clone();
        let call: Call = Arc::new(move |method, params| {
            seen.lock().unwrap().push((method.clone(), params));
            Box::pin(async move {
                match fail {
                    Some(code) if method == "assistant.threads.setStatus" => Err(anyhow!("slack assistant.threads.setStatus: {code}")),
                    _ => Ok(()),
                }
            })
        });
        (call, calls)
    }

    fn get(params: &[(String, String)], key: &str) -> Option<String> {
        params.iter().find(|(k, _)| k == key).map(|(_, v)| v.clone())
    }

    #[tokio::test]
    async fn a_threads_status_line_says_what_the_agent_does_and_goes_when_it_is_done() {
        let (call, calls) = recording(None);
        let line = ThreadStatus::new(call, "C1", "1.1");
        line.say("正在思考…", Some("1.2"));
        tokio::time::sleep(Duration::from_millis(30)).await;
        line.say("", None);
        tokio::time::sleep(Duration::from_millis(30)).await;
        let calls = calls.lock().unwrap().clone();
        let said: Vec<(String, Option<String>)> = calls.iter().map(|(m, p)| (m.clone(), get(p, "status"))).collect();
        assert_eq!(said, vec![("assistant.threads.setStatus".into(), Some("正在思考…".into())), ("assistant.threads.setStatus".into(), Some(String::new()))]);
        assert_eq!((get(&calls[0].1, "channel_id"), get(&calls[0].1, "thread_ts")), (Some("C1".into()), Some("1.1".into())));
    }

    #[tokio::test]
    async fn where_slack_will_not_show_a_status_an_eyes_reaction_stands_in() {
        let (call, calls) = recording(Some("missing_scope"));
        let line = ThreadStatus::new(call, "C1", "1.1");
        line.say("正在运行命令…", Some("1.2"));
        tokio::time::sleep(Duration::from_millis(30)).await;
        line.say("", None);
        tokio::time::sleep(Duration::from_millis(30)).await;
        let calls = calls.lock().unwrap().clone();
        let said: Vec<(String, Option<String>, Option<String>)> = calls.iter().map(|(m, p)| (m.clone(), get(p, "timestamp"), get(p, "name"))).collect();
        assert_eq!(
            said,
            vec![
                ("assistant.threads.setStatus".into(), None, None),
                ("reactions.add".into(), Some("1.2".into()), Some("eyes".into())),
                ("reactions.remove".into(), Some("1.2".into()), Some("eyes".into())),
            ]
        );
    }

    #[test]
    fn tool_calls_in_words_by_either_runtimes_names() {
        let words: Vec<String> = ["Read", "Bash", "exec_command", "apply_patch", "WebSearch", "mcp__ember__chat_post", "something"].iter().map(|t| tool_status(t)).collect();
        assert_eq!(words, vec!["正在查看文件…", "正在运行命令…", "正在运行命令…", "正在修改文件…", "正在搜索网页…", "正在看 Slack…", "正在处理…"]);
    }
}
