//! Claude Code driver: one `claude -p` stream-json process per session.
//!
//! Behaviour pinned by spikes (spike/README.md):
//! - a turn is framed by system/init … result; `result.is_error` decides success, not `subtype` (an auth failure ends
//!   as subtype "success");
//! - 401/403 is retried silently for minutes, visible only as system/api_retry frames, so the first one fails the turn;
//! - input written while a turn is finishing may start a turn of its own (a system/init with no prompt of ours);
//! - interrupt is a control_request; the turn still ends with a result frame.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::{Result, bail};
use async_trait::async_trait;
use ember_shapes::RuntimeKind;
use serde_json::{Value, json};
use tracing::debug;

use super::process::{GroupProcess, Spawn, spawn_group};
use super::{AgentDriver, AgentSession, Events, FailureReason, LiveEvent, LiveField, LivePhase, LiveStepKind, OpenOptions, RuntimeEvent, TurnOutcome, clean_env, uuid};
use crate::config::expand_route;
use crate::machine_logins::{CLAUDE_TOKEN_MARGIN_MS, machine_claude_token, process_env};
use crate::store::{Store, now_ms};

const MCP_TOKEN_VAR: &str = "EMBER_MCP_TOKEN";
/// Inherited variables that would let a session authenticate as something other than its profile.
const SCRUBBED: [&str; 7] =
    ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "CLAUDE_CONFIG_DIR", "CLAUDE_CODE_OAUTH_TOKEN", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"];

pub fn user_message(text: &str) -> String {
    json!({ "type": "user", "message": { "role": "user", "content": [{ "type": "text", "text": text }] } }).to_string()
}

/// Claude keeps a session at $CLAUDE_CONFIG_DIR/projects/<encoded cwd>/<id>.jsonl.
pub fn transcript_exists(home: &Path, session_id: &str) -> bool {
    let Ok(dirs) = std::fs::read_dir(home.join("projects")) else { return false };
    dirs.flatten().any(|d| d.path().is_dir() && d.path().join(format!("{session_id}.jsonl")).exists())
}

pub fn classify_result(text: &str) -> FailureReason {
    let lower = text.to_lowercase();
    let word = |w: &str| lower.split(|c: char| !c.is_alphanumeric()).any(|x| x == w);
    if word("401") || word("403") || lower.contains("authenticat") || lower.contains("api key") {
        FailureReason::Auth
    } else if word("429") || lower.contains("rate limit") || lower.contains("rate-limit") || lower.contains("rate_limit") || lower.contains("ratelimit") || lower.contains("usage limit") || lower.contains("overloaded") {
        FailureReason::RateLimit
    } else {
        FailureReason::Model
    }
}

#[derive(Default)]
struct Turn {
    busy: bool,
    aborting: bool,
    auth_failure: Option<String>,
    closed: bool,
}

pub struct ClaudeDriver {
    store: Arc<Store>,
    command: String,
    live: Mutex<Vec<Arc<ClaudeSession>>>,
}

impl ClaudeDriver {
    pub fn new(store: Arc<Store>, command: &str) -> ClaudeDriver {
        ClaudeDriver { store, command: command.into(), live: Mutex::new(vec![]) }
    }
}

pub struct ClaudeSession {
    id: String,
    proc: Arc<GroupProcess>,
    turn: Arc<Mutex<Turn>>,
    events: Events,
    /// The machine login's token this process runs on (machine profiles): when it runs out.
    machine_expires: Option<i64>,
}

#[async_trait]
impl AgentDriver for ClaudeDriver {
    fn runtime(&self) -> RuntimeKind {
        RuntimeKind::Claude
    }

    async fn open(&self, options: OpenOptions, events: Events) -> Result<Arc<dyn AgentSession>> {
        let home = options.profile.home.clone();
        std::fs::create_dir_all(&home)?;
        if let Some(resume) = &options.resume {
            if !transcript_exists(&home, resume) {
                // claude would start and exit at once; failing here lets the caller start fresh.
                bail!("no claude transcript for session {resume}");
            }
        }
        let session_id = options.resume.clone().unwrap_or_else(uuid);
        let mcp_config = json!({ "mcpServers": { "ember": { "type": "http", "url": options.mcp_url, "headers": { "Authorization": format!("Bearer ${{{MCP_TOKEN_VAR}}}") } } } });
        let model = options.model.clone().or_else(|| options.profile.model.clone());
        let mut args: Vec<String> = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--dangerously-skip-permissions"]
            .map(String::from)
            .to_vec();
        if options.resume.is_some() {
            args.extend(["--resume".into(), session_id.clone()]);
        } else {
            args.extend(["--session-id".into(), session_id.clone()]);
        }
        if let Some(model) = &model {
            args.extend(["--model".into(), model.clone()]);
        }
        if let Some(effort) = &options.effort {
            args.extend(["--effort".into(), effort.clone()]);
        }
        args.extend(["--append-system-prompt".into(), options.instructions.clone(), "--mcp-config".into(), mcp_config.to_string()]);

        let mut env: BTreeMap<String, String> = clean_env(&SCRUBBED);
        env.extend(expand_route(&options.profile.env(RuntimeKind::Claude), &options.route));
        env.insert("CLAUDE_CONFIG_DIR".into(), home.display().to_string());
        env.insert(MCP_TOKEN_VAR.into(), options.mcp_token.clone());
        // Lets the agent name its own transcript, e.g. for an independent reviewer (codex has CODEX_THREAD_ID).
        env.insert("EMBER_RUNTIME_SESSION_ID".into(), session_id.clone());
        // A machine profile runs on the machine's own login, handed over as its current token (machine_logins.rs).
        let machine = if options.profile.machine { Some(machine_claude_token(&process_env()).await?) } else { None };
        if let Some((token, _)) = &machine {
            env.insert("CLAUDE_CODE_OAUTH_TOKEN".into(), token.clone());
        }
        // Its own root certificates, not the system's: read from the macOS keychain by a process outside the desktop
        // session, they took up to 36 s before a new session could start. One the user chose wins.
        env.entry("CLAUDE_CODE_CERT_STORE".into()).or_insert_with(|| "bundled".into());

        let turn = Arc::new(Mutex::new(Turn::default()));
        let (line_turn, line_events) = (turn.clone(), events.clone());
        let live = Mutex::new(LiveFromClaude::default());
        // Set once the process is up: the line handler needs it to interrupt a turn an auth failure stops.
        let proc_slot: Arc<Mutex<Option<Arc<GroupProcess>>>> = Arc::new(Mutex::new(None));
        let line_proc = proc_slot.clone();
        let proc = spawn_group(
            Spawn { command: &self.command, args, cwd: &options.cwd, env, runtime: "claude", label: format!("claude {session_id}") },
            self.store.clone(),
            move |line| {
                let Ok(frame) = serde_json::from_str::<Value>(&line) else {
                    debug!(line = &line[..line.len().min(500)], "claude non-json line");
                    return;
                };
                for event in live.lock().unwrap().feed(&frame) {
                    let _ = line_events.send(RuntimeEvent::Live(event));
                }
                on_frame(&frame, &line_turn, &line_events, &line_proc);
            },
        )?;
        *proc_slot.lock().unwrap() = Some(proc.clone());

        let session = Arc::new(ClaudeSession { id: session_id, proc: proc.clone(), turn: turn.clone(), events: events.clone(), machine_expires: machine.map(|m| m.1) });
        self.live.lock().unwrap().push(session.clone());
        let exit_turn = turn;
        tokio::spawn(async move {
            let code = proc.exited().await;
            let busy = {
                let mut t = exit_turn.lock().unwrap();
                t.closed = true;
                std::mem::take(&mut t.busy)
            };
            if busy {
                let _ = events.send(RuntimeEvent::TurnEnded(TurnOutcome::Failed { reason: FailureReason::Exited, message: format!("claude exited ({code}) during the turn") }));
            }
            let _ = events.send(RuntimeEvent::Closed(format!("claude exited ({code})")));
        });
        Ok(session)
    }

    async fn shutdown(&self) {
        let live: Vec<_> = std::mem::take(&mut *self.live.lock().unwrap());
        for session in live {
            session.dispose().await;
        }
    }
}

fn end_turn(turn: &Mutex<Turn>, events: &Events, outcome: TurnOutcome) {
    {
        let mut t = turn.lock().unwrap();
        t.busy = false;
        t.aborting = false;
        t.auth_failure = None;
    }
    let _ = events.send(RuntimeEvent::TurnEnded(outcome));
}

fn on_frame(frame: &Value, turn: &Mutex<Turn>, events: &Events, proc: &Mutex<Option<Arc<GroupProcess>>>) {
    let kind = frame.get("type").and_then(Value::as_str).unwrap_or("");
    let subtype = frame.get("subtype").and_then(Value::as_str).unwrap_or("");
    if kind == "system" && subtype == "init" {
        let started = {
            let mut t = turn.lock().unwrap();
            let was = t.busy;
            t.busy = true;
            !was
        };
        if started {
            let _ = events.send(RuntimeEvent::TurnStarted);
        }
    } else if kind == "system" && subtype == "api_retry" {
        let status = frame.get("error_status").and_then(Value::as_i64).unwrap_or(0);
        let first = {
            let mut t = turn.lock().unwrap();
            if (status == 401 || status == 403) && t.auth_failure.is_none() {
                let error = frame.get("error").map(|e| e.as_str().map(String::from).unwrap_or_else(|| e.to_string())).unwrap_or_else(|| "authentication failed".into());
                t.auth_failure = Some(format!("{status} {error}"));
                true
            } else {
                false
            }
        };
        if first {
            if let Some(proc) = proc.lock().unwrap().clone() {
                tokio::spawn(async move { interrupt(&proc).await });
            }
            turn.lock().unwrap().aborting = true;
        }
    } else if kind == "result" {
        let text = frame.get("result").and_then(Value::as_str).or(Some(subtype)).unwrap_or("").to_string();
        let (auth, aborting) = {
            let t = turn.lock().unwrap();
            (t.auth_failure.clone(), t.aborting)
        };
        let outcome = if let Some(message) = auth {
            TurnOutcome::Failed { reason: FailureReason::Auth, message }
        } else if aborting {
            TurnOutcome::Aborted
        } else if frame.get("is_error") == Some(&Value::Bool(true)) {
            TurnOutcome::Failed { reason: classify_result(&text), message: text.chars().take(1000).collect() }
        } else {
            TurnOutcome::Completed
        };
        end_turn(turn, events, outcome);
    }
}

async fn interrupt(proc: &GroupProcess) {
    proc.write(&json!({ "type": "control_request", "request_id": format!("interrupt-{}", uuid()), "request": { "subtype": "interrupt" } }).to_string()).await;
}

#[async_trait]
impl AgentSession for ClaudeSession {
    fn id(&self) -> String {
        self.id.clone()
    }

    fn busy(&self) -> bool {
        self.turn.lock().unwrap().busy
    }

    async fn prompt(&self, text: &str) -> Result<()> {
        {
            let mut t = self.turn.lock().unwrap();
            if t.closed {
                bail!("claude session is closed");
            }
            if t.busy {
                bail!("a turn is already running");
            }
            // Its token cannot refresh itself: about to run out, it is started again (resuming) with the machine's next one.
            if self.machine_expires.is_some_and(|at| at - now_ms() < CLAUDE_TOKEN_MARGIN_MS) {
                bail!("the machine login's token runs out");
            }
            t.busy = true;
        }
        self.proc.write(&user_message(text)).await;
        Ok(())
    }

    async fn steer(&self, text: &str) -> bool {
        {
            let t = self.turn.lock().unwrap();
            if t.closed || !t.busy {
                return false;
            }
        }
        self.proc.write(&user_message(text)).await;
        true
    }

    async fn abort(&self) {
        {
            let mut t = self.turn.lock().unwrap();
            if t.closed || !t.busy || t.aborting {
                return;
            }
            t.aborting = true;
        }
        interrupt(&self.proc).await;
    }

    async fn dispose(&self) {
        self.proc.kill(Duration::from_secs(5)).await;
        let _ = &self.events;
    }
}

/// Claude Code's partial messages (--include-partial-messages) as live steps. Each content block of a model response is
/// a step: text and thinking end with their block; a tool call ends when its result comes back, which also carries the
/// output (Claude Code does not stream tool output).
#[derive(Default)]
pub struct LiveFromClaude {
    message: String,
    blocks: HashMap<i64, Block>,
    tools: HashSet<String>,
}

struct Block {
    id: String,
    step: LiveStepKind,
    tool: Option<String>,
    input: Option<String>,
    subagent: Option<String>,
}

impl LiveFromClaude {
    pub fn feed(&mut self, frame: &Value) -> Vec<LiveEvent> {
        let mut out = Vec::new();
        let kind = frame.get("type").and_then(Value::as_str).unwrap_or("");
        if kind == "system" && frame.get("subtype").and_then(Value::as_str) == Some("status") && frame.get("status").and_then(Value::as_str) == Some("requesting") {
            out.push(LiveEvent::Phase { phase: LivePhase::Requesting });
        } else if kind == "stream_event" {
            let e = frame.get("event").cloned().unwrap_or(Value::Null);
            // A sub-agent's steps name the tool call (Task/Agent) that started it.
            let parent = frame.get("parent_tool_use_id").and_then(Value::as_str).filter(|p| !p.is_empty()).map(String::from);
            let event = e.get("type").and_then(Value::as_str).unwrap_or("");
            if event == "message_stop" && parent.is_none() {
                out.push(LiveEvent::Phase { phase: LivePhase::Working });
            }
            let index = e.get("index").and_then(Value::as_i64).unwrap_or(-1);
            match event {
                "message_start" => {
                    self.message = e.get("message").and_then(|m| m.get("id")).and_then(Value::as_str).map(String::from).unwrap_or_else(|| now_ms().to_string());
                    self.blocks.clear();
                    if parent.is_none() {
                        out.push(LiveEvent::Phase { phase: LivePhase::Responding });
                    }
                }
                "content_block_start" => {
                    let b = e.get("content_block").cloned().unwrap_or(Value::Null);
                    let step = match b.get("type").and_then(Value::as_str) {
                        Some("text") => LiveStepKind::Text,
                        Some("thinking") => LiveStepKind::Thinking,
                        Some("tool_use") => LiveStepKind::Tool,
                        _ => return out,
                    };
                    let id = match (step, b.get("id").and_then(Value::as_str)) {
                        (LiveStepKind::Tool, Some(id)) => id.to_string(),
                        _ => format!("{}:{index}", self.message),
                    };
                    let tool = (step == LiveStepKind::Tool).then(|| b.get("name").and_then(Value::as_str).unwrap_or("tool").to_string());
                    if step == LiveStepKind::Tool {
                        self.tools.insert(id.clone());
                    }
                    out.push(LiveEvent::Start {
                        id: id.clone(),
                        step,
                        tool: tool.clone(),
                        input: None,
                        subagent: parent.as_ref().map(|_| true),
                        parent: parent.clone(),
                    });
                    self.blocks.insert(index, Block { id, step, input: tool.as_ref().map(|_| String::new()), tool, subagent: parent });
                }
                "content_block_delta" => {
                    let Some(block) = self.blocks.get_mut(&index) else { return out };
                    let d = e.get("delta").cloned().unwrap_or(Value::Null);
                    let text = |k: &str| d.get(k).and_then(Value::as_str).filter(|t| !t.is_empty()).map(String::from);
                    match d.get("type").and_then(Value::as_str) {
                        Some("text_delta") => out.extend(text("text").map(|t| LiveEvent::delta(&block.id, LiveField::Text, t))),
                        Some("thinking_delta") => out.extend(text("thinking").map(|t| LiveEvent::delta(&block.id, LiveField::Text, t))),
                        Some("input_json_delta") => {
                            if let Some(partial) = text("partial_json") {
                                // A call's input streams in after it starts; kept (its start, a moment before, came without it).
                                if let Some(input) = block.input.as_mut().filter(|i| i.len() < 4096) {
                                    input.push_str(&partial);
                                }
                                out.push(LiveEvent::delta(&block.id, LiveField::Input, partial));
                            }
                        }
                        _ => {}
                    }
                }
                "content_block_stop" => {
                    if let Some(block) = self.blocks.get(&index) {
                        if block.step != LiveStepKind::Tool {
                            out.push(LiveEvent::End { id: block.id.clone() });
                        } else if let Some(input) = block.input.as_ref().filter(|i| !i.is_empty()) {
                            // Its input complete, the call starts again with it: what it runs can be said now.
                            out.push(LiveEvent::Start {
                                id: block.id.clone(),
                                step: LiveStepKind::Tool,
                                tool: block.tool.clone(),
                                input: Some(input.clone()),
                                subagent: block.subagent.as_ref().map(|_| true),
                                parent: block.subagent.clone(),
                            });
                        }
                    }
                }
                _ => {}
            }
        } else if kind == "user" {
            let content = frame.get("message").and_then(|m| m.get("content")).and_then(Value::as_array).cloned().unwrap_or_default();
            for c in content {
                let id = c.get("tool_use_id").and_then(Value::as_str).unwrap_or("").to_string();
                if c.get("type").and_then(Value::as_str) != Some("tool_result") || !self.tools.contains(&id) {
                    continue;
                }
                let text = match c.get("content") {
                    Some(Value::String(s)) => s.clone(),
                    Some(Value::Array(parts)) => parts.iter().map(|x| x.get("text").and_then(Value::as_str).unwrap_or("")).collect::<Vec<_>>().join("\n"),
                    _ => String::new(),
                };
                if !text.is_empty() {
                    out.push(LiveEvent::delta(&id, LiveField::Output, text.chars().take(8000).collect::<String>()));
                }
                out.push(LiveEvent::End { id: id.clone() });
                self.tools.remove(&id);
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn claude_partial_messages_become_steps() {
        let mut feed = LiveFromClaude::default();
        let mut all = Vec::new();
        let mut ev = |event: Value| all.extend(feed.feed(&json!({ "type": "stream_event", "event": event, "parent_tool_use_id": null })));
        ev(json!({ "type": "message_start", "message": { "id": "m1" } }));
        ev(json!({ "type": "content_block_start", "index": 0, "content_block": { "type": "thinking", "thinking": "" } }));
        ev(json!({ "type": "content_block_delta", "index": 0, "delta": { "type": "thinking_delta", "thinking": "hmm" } }));
        ev(json!({ "type": "content_block_stop", "index": 0 }));
        ev(json!({ "type": "content_block_start", "index": 1, "content_block": { "type": "tool_use", "id": "call_1", "name": "Bash", "input": {} } }));
        ev(json!({ "type": "content_block_delta", "index": 1, "delta": { "type": "input_json_delta", "partial_json": "{\"command\":" } }));
        ev(json!({ "type": "content_block_delta", "index": 1, "delta": { "type": "input_json_delta", "partial_json": "\"ls\"}" } }));
        ev(json!({ "type": "content_block_stop", "index": 1 }));
        drop(ev);
        all.extend(feed.feed(&json!({ "type": "user", "message": { "content": [{ "type": "tool_result", "tool_use_id": "call_1", "content": "hi" }] } })));
        let mut ev = |event: Value| all.extend(feed.feed(&json!({ "type": "stream_event", "event": event, "parent_tool_use_id": null })));
        ev(json!({ "type": "message_start", "message": { "id": "m2" } }));
        ev(json!({ "type": "content_block_start", "index": 0, "content_block": { "type": "text", "text": "" } }));
        ev(json!({ "type": "content_block_delta", "index": 0, "delta": { "type": "text_delta", "text": "Done" } }));
        ev(json!({ "type": "content_block_stop", "index": 0 }));
        let phases: Vec<LivePhase> = all.iter().filter_map(|e| if let LiveEvent::Phase { phase } = e { Some(*phase) } else { None }).collect();
        assert_eq!(phases, vec![LivePhase::Responding, LivePhase::Responding]);
        let steps: Vec<Value> = all.iter().filter(|e| !matches!(e, LiveEvent::Phase { .. })).map(|e| serde_json::to_value(e).unwrap()).collect();
        assert_eq!(
            steps,
            vec![
                json!({ "kind": "start", "id": "m1:0", "step": "thinking" }),
                json!({ "kind": "delta", "id": "m1:0", "field": "text", "text": "hmm" }),
                json!({ "kind": "end", "id": "m1:0" }),
                json!({ "kind": "start", "id": "call_1", "step": "tool", "tool": "Bash" }),
                json!({ "kind": "delta", "id": "call_1", "field": "input", "text": "{\"command\":" }),
                json!({ "kind": "delta", "id": "call_1", "field": "input", "text": "\"ls\"}" }),
                // Its input complete, it starts again with it.
                json!({ "kind": "start", "id": "call_1", "step": "tool", "tool": "Bash", "input": "{\"command\":\"ls\"}" }),
                json!({ "kind": "delta", "id": "call_1", "field": "output", "text": "hi" }),
                json!({ "kind": "end", "id": "call_1" }),
                json!({ "kind": "start", "id": "m2:0", "step": "text" }),
                json!({ "kind": "delta", "id": "m2:0", "field": "text", "text": "Done" }),
                json!({ "kind": "end", "id": "m2:0" }),
            ]
        );
    }

    #[test]
    fn failures_are_told_apart_by_what_claude_said() {
        assert_eq!(classify_result("API Error: 401 invalid x-api-key"), FailureReason::Auth);
        assert_eq!(classify_result("Claude AI usage limit reached"), FailureReason::RateLimit);
        assert_eq!(classify_result("prompt is too long"), FailureReason::Model);
    }
}
