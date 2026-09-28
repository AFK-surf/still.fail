//! Live view of sessions: what a running turn is doing, told at its turning points — the phase (asking the model,
//! thinking, working), each step starting (thinking, writing, a tool with its input) and ending — and the transcript's
//! entries as each is written whole. What a step writes as it goes (the runtime's deltas) is not sent: a step's words
//! come with its entry; how fast it writes is, now and then. Nothing here is stored: the steps in flight live in memory
//! until they end, and the transcript stays the record, parsed incrementally and kept in memory while someone watches.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use ember_shapes::RuntimeKind;
use serde::Serialize;
use tokio::sync::mpsc;
use tokio::task::JoinHandle;

use crate::runtime::{LiveEvent, LivePhase, LiveStepKind};
use crate::store::now_ms;
use crate::transcript::{TimelineEntry, TranscriptTail, TranscriptUsage};

/// A step in flight: what it is, not what it has written so far.
#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LiveStep {
    pub id: String,
    pub step: LiveStepKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subagent: Option<bool>,
    /// For a sub-agent's step: the tool call that started the sub-agent.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent: Option<String>,
    /// A tool's input as it started (a command), cut short.
    pub input: String,
    pub started_at: i64,
}

/// Where the turn stands with the model, and for how long (ms) at the time it is sent.
#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LivePhaseView {
    pub phase: LivePhase,
    pub elapsed_ms: i64,
}

#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum LiveMessage {
    Steps { steps: Vec<LiveStep>, phase: Option<LivePhaseView> },
    Step { event: LiveEvent },
    Timeline { start: usize, entries: Vec<TimelineEntry>, usage: TranscriptUsage },
    /// How fast the model is writing now (≈ tokens a second, from bytes), at most once a second; 0 once it stops.
    Rate {
        #[serde(rename = "tokensPerSecond")]
        tokens_per_second: i64,
    },
    Clear,
}

pub type Listener = mpsc::UnboundedSender<LiveMessage>;

/// How much of a tool's input a step carries: enough to say what it runs.
const INPUT_CHARS: usize = 300;
/// The output rate is told at most this often, over this window (bytes / 4 ≈ tokens, as Zork estimates).
const RATE_EVERY_MS: i64 = 1_000;
const RATE_WINDOW_MS: i64 = 2_000;
const RATE_FIRST_MS: i64 = 500;
/// How often a watched transcript is looked at for growth (the runtime's own events look sooner).
const POLL: Duration = Duration::from_millis(250);

/// A session's recent output, in 250 ms buckets, and when its rate was last told.
#[derive(Default)]
struct Rate {
    buckets: Vec<(i64, i64)>,
    told_at: i64,
    told: i64,
}

struct Watched {
    tail: TranscriptTail,
    poll: JoinHandle<()>,
    reading: bool,
}

#[derive(Default)]
struct State {
    steps: HashMap<String, Vec<LiveStep>>,
    phase: HashMap<String, (LivePhase, i64)>,
    rates: HashMap<String, Rate>,
    listeners: HashMap<String, Vec<(u64, Listener)>>,
    watched: HashMap<String, Watched>,
    next_id: u64,
}

pub type Locate = Arc<dyn Fn(&str) -> Option<(RuntimeKind, PathBuf)> + Send + Sync>;
pub type Posts = Arc<dyn Fn(&str) -> Vec<TimelineEntry> + Send + Sync>;

pub struct LiveHub {
    state: Mutex<State>,
    /// Where a session's transcript is, once its runtime has started one.
    locate: Locate,
    /// What a session's agent posted, as timeline entries: woven into its transcript's (which leaves its posts out).
    posts: Posts,
}

impl LiveHub {
    pub fn new(locate: Locate, posts: Posts) -> Arc<LiveHub> {
        Arc::new(LiveHub { state: Mutex::default(), locate, posts })
    }

    fn emit(state: &mut State, key: &str, message: LiveMessage) {
        if let Some(listeners) = state.listeners.get_mut(key) {
            listeners.retain(|(_, l)| l.send(message.clone()).is_ok());
        }
    }

    /// A runtime's live event for a session.
    pub fn event(self: &Arc<Self>, key: &str, event: LiveEvent) {
        let mut state = self.state.lock().unwrap();
        match event {
            LiveEvent::Phase { phase } => {
                state.phase.insert(key.to_string(), (phase, now_ms()));
                Self::emit(&mut state, key, LiveMessage::Step { event });
            }
            // What a step writes as it goes is not told: its words come with its transcript entry. How fast it writes is.
            LiveEvent::Delta { text, .. } => Self::counted(&mut state, key, text.len() as i64),
            LiveEvent::Start { id, step, tool, input, subagent, parent } => {
                let input: String = input.unwrap_or_default().chars().take(INPUT_CHARS).collect();
                let steps = state.steps.entry(key.to_string()).or_default();
                // Started again with its input (Claude Code streams it after the start): it keeps when it started.
                let started_at = steps.iter().find(|s| s.id == id).map(|s| s.started_at).unwrap_or_else(now_ms);
                steps.retain(|s| s.id != id);
                steps.push(LiveStep { id: id.clone(), step, tool: tool.clone(), subagent: subagent.filter(|s| *s), parent: parent.clone(), input: input.clone(), started_at });
                let told = LiveEvent::Start { id, step, tool, input: Some(input), subagent, parent };
                Self::emit(&mut state, key, LiveMessage::Step { event: told });
            }
            LiveEvent::End { ref id } => {
                let Some(steps) = state.steps.get_mut(key) else { return };
                let before = steps.len();
                steps.retain(|s| &s.id != id);
                if steps.len() == before {
                    return;
                }
                Self::emit(&mut state, key, LiveMessage::Step { event: event.clone() });
                // A step ended: the model is not writing (until its next output).
                if let Some(rate) = state.rates.remove(key) {
                    if rate.told > 0 {
                        Self::emit(&mut state, key, LiveMessage::Rate { tokens_per_second: 0 });
                    }
                }
                drop(state);
                self.soon(key);
            }
        }
    }

    /// The agent posted: its history shows it now, after what was read.
    pub fn posted(&self, key: &str, entries: Vec<TimelineEntry>) {
        let mut state = self.state.lock().unwrap();
        let Some(watched) = state.watched.get_mut(key) else { return };
        let start = watched.tail.append(entries.clone());
        let usage = watched.tail.usage.clone();
        Self::emit(&mut state, key, LiveMessage::Timeline { start, entries, usage });
    }

    /// The turn is over: whatever was in flight is in the transcript now, or never will be.
    pub fn turn_ended(self: &Arc<Self>, key: &str) {
        {
            let mut state = self.state.lock().unwrap();
            state.steps.remove(key);
            state.phase.remove(key);
            state.rates.remove(key);
            Self::emit(&mut state, key, LiveMessage::Clear);
        }
        self.soon(key);
    }

    /// Follows a session: first the transcript entries from index `from` on (and the usage so far), the steps in
    /// flight, then everything new. Returns what stops it (unsubscribe).
    pub fn subscribe(self: &Arc<Self>, key: &str, from: usize, listener: Listener) -> u64 {
        let mut state = self.state.lock().unwrap();
        state.next_id += 1;
        let id = state.next_id;
        state.listeners.entry(key.to_string()).or_default().push((id, listener.clone()));
        if self.watch(&mut state, key) {
            let watched = &state.watched[key];
            // A watcher that has more than the transcript (it was written anew) is told where it ends.
            let start = from.min(watched.tail.entries.len());
            let _ = listener.send(LiveMessage::Timeline { start, entries: watched.tail.entries[start..].to_vec(), usage: watched.tail.usage.clone() });
        }
        let phase = state.phase.get(key).map(|(phase, at)| LivePhaseView { phase: *phase, elapsed_ms: now_ms() - at });
        let _ = listener.send(LiveMessage::Steps { steps: state.steps.get(key).cloned().unwrap_or_default(), phase });
        id
    }

    pub fn unsubscribe(&self, key: &str, id: u64) {
        let mut state = self.state.lock().unwrap();
        let empty = match state.listeners.get_mut(key) {
            Some(listeners) => {
                listeners.retain(|(i, _)| *i != id);
                listeners.is_empty()
            }
            None => false,
        };
        if empty {
            state.listeners.remove(key);
            Self::unwatch(&mut state, key);
        }
    }

    /// A deleted session: nothing of it is watched or kept any more.
    pub fn forget(&self, key: &str) {
        let mut state = self.state.lock().unwrap();
        state.steps.remove(key);
        state.phase.remove(key);
        state.rates.remove(key);
        Self::emit(&mut state, key, LiveMessage::Clear);
        state.listeners.remove(key);
        Self::unwatch(&mut state, key);
    }

    pub fn close(&self) {
        let mut state = self.state.lock().unwrap();
        let keys: Vec<String> = state.watched.keys().cloned().collect();
        for key in keys {
            Self::unwatch(&mut state, &key);
        }
    }

    /// Output written: its rate is told once half a second of it has come (a first few bytes say nothing of the pace),
    /// then when a second has passed since it last was.
    fn counted(state: &mut State, key: &str, bytes: i64) {
        let now = now_ms();
        let rate = state.rates.entry(key.to_string()).or_default();
        let bucket = now / 250 * 250;
        match rate.buckets.last_mut() {
            Some(last) if last.0 == bucket => last.1 += bytes,
            _ => rate.buckets.push((bucket, bytes)),
        }
        rate.buckets.retain(|(at, _)| *at >= now - RATE_WINDOW_MS);
        if now - rate.told_at < RATE_EVERY_MS {
            return;
        }
        let first = rate.buckets[0].0;
        if rate.told_at == 0 && now - first < RATE_FIRST_MS {
            return;
        }
        let span = RATE_WINDOW_MS.min(250.max(now - first));
        let total: i64 = rate.buckets.iter().map(|(_, b)| b).sum();
        let tokens_per_second = 1.max(((total * 1000) as f64 / (4 * span) as f64).round() as i64);
        rate.told_at = now;
        rate.told = tokens_per_second;
        Self::emit(state, key, LiveMessage::Rate { tokens_per_second });
    }

    /// Starts reading a watched session's transcript, once it exists. Whether it is watched now.
    fn watch(self: &Arc<Self>, state: &mut State, key: &str) -> bool {
        if state.watched.contains_key(key) {
            return true;
        }
        if !state.listeners.contains_key(key) {
            return false;
        }
        let Some((runtime, path)) = (self.locate)(key) else { return false };
        let mut tail = TranscriptTail::new(runtime, path.clone());
        tail.read(); // what is already there counts as known; subscribers ask for what they lack
        tail.weave((self.posts)(key));
        let me = Arc::downgrade(self);
        let watched_key = key.to_string();
        let poll = tokio::spawn(async move {
            let mut size = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
            loop {
                tokio::time::sleep(POLL).await;
                let now = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
                if now != size {
                    size = now;
                    match me.upgrade() {
                        Some(hub) => hub.soon(&watched_key),
                        None => return,
                    }
                }
            }
        });
        state.watched.insert(key.to_string(), Watched { tail, poll, reading: false });
        true
    }

    fn unwatch(state: &mut State, key: &str) {
        if let Some(watched) = state.watched.remove(key) {
            watched.poll.abort();
        }
    }

    /// Reads what the transcript gained, coalescing bursts of writes.
    fn soon(self: &Arc<Self>, key: &str) {
        let fresh = {
            let mut state = self.state.lock().unwrap();
            if !state.listeners.contains_key(key) {
                return;
            }
            let fresh = !state.watched.contains_key(key);
            if !self.watch(&mut state, key) {
                return;
            }
            let watched = state.watched.get_mut(key).unwrap();
            if watched.reading {
                return;
            }
            watched.reading = true;
            fresh
        };
        let me = self.clone();
        let key = key.to_string();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(40)).await;
            let mut state = me.state.lock().unwrap();
            let Some(watched) = state.watched.get_mut(&key) else { return };
            watched.reading = false;
            let (start, entries) = watched.tail.read();
            let usage = watched.tail.usage.clone();
            if !entries.is_empty() || fresh {
                Self::emit(&mut state, &key, LiveMessage::Timeline { start, entries, usage });
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime::LiveField;
    use serde_json::json;
    use std::io::Write;

    fn line(text: &str, id: &str) -> String {
        format!("{}\n", json!({ "type": "assistant", "timestamp": "2026-09-26T00:00:00Z", "message": { "id": id, "content": [{ "type": "text", "text": text }], "usage": { "input_tokens": 10, "output_tokens": 2 } } }))
    }

    fn drain(rx: &mut mpsc::UnboundedReceiver<LiveMessage>) -> Vec<LiveMessage> {
        let mut out = Vec::new();
        while let Ok(m) = rx.try_recv() {
            out.push(m);
        }
        out
    }

    #[tokio::test]
    async fn a_watcher_gets_what_it_lacks_the_steps_in_flight_then_new_entries_as_the_file_grows() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("t.jsonl");
        std::fs::write(&path, line("one", "m1") + &line("two", "m2")).unwrap();
        let located = path.clone();
        let hub = LiveHub::new(Arc::new(move |_| Some((RuntimeKind::Claude, located.clone()))), Arc::new(|_| vec![]));
        hub.event("s", LiveEvent::start("x", LiveStepKind::Text));
        hub.event("s", LiveEvent::delta("x", LiveField::Text, "wri"));
        let (tx, mut rx) = mpsc::unbounded_channel();
        let id = hub.subscribe("s", 1, tx);
        let got = drain(&mut rx);
        match (&got[0], &got[1]) {
            (LiveMessage::Timeline { entries, .. }, LiveMessage::Steps { steps, .. }) => {
                assert_eq!(entries.iter().map(|e| e.text.as_str()).collect::<Vec<_>>(), vec!["two"]);
                // What a step is, not what it wrote.
                assert_eq!(steps[0].step, LiveStepKind::Text);
            }
            other => panic!("{other:?}"),
        }
        hub.event("s", LiveEvent::delta("x", LiveField::Text, "ting"));
        assert!(drain(&mut rx).is_empty(), "a delta sends nothing");
        hub.event("s", LiveEvent::End { id: "x".into() });
        std::fs::OpenOptions::new().append(true).open(&path).unwrap().write_all(line("writing", "m3").as_bytes()).unwrap();
        tokio::time::sleep(Duration::from_millis(600)).await;
        let got = drain(&mut rx);
        let timeline = got.iter().rev().find_map(|m| if let LiveMessage::Timeline { start, entries, .. } = m { Some((*start, entries.clone())) } else { None }).unwrap();
        assert_eq!((timeline.0, timeline.1.iter().map(|e| e.text.clone()).collect::<Vec<_>>()), (2, vec!["writing".to_string()]));
        hub.turn_ended("s");
        assert!(drain(&mut rx).contains(&LiveMessage::Clear));
        hub.unsubscribe("s", id);
        hub.close();
    }

    #[tokio::test]
    async fn how_fast_the_model_writes_is_told_once_half_a_second_of_it_has_come() {
        let hub = LiveHub::new(Arc::new(|_| None), Arc::new(|_| vec![]));
        let (tx, mut rx) = mpsc::unbounded_channel();
        hub.subscribe("s", 0, tx);
        let mut got = drain(&mut rx);
        hub.event("s", LiveEvent::start("x", LiveStepKind::Text));
        hub.event("s", LiveEvent::delta("x", LiveField::Text, "x".repeat(400)));
        got.extend(drain(&mut rx));
        let rates = |got: &[LiveMessage]| got.iter().filter_map(|m| if let LiveMessage::Rate { tokens_per_second } = m { Some(*tokens_per_second) } else { None }).collect::<Vec<_>>();
        assert!(rates(&got).is_empty(), "a first few bytes say nothing of the pace");
        tokio::time::sleep(Duration::from_millis(600)).await;
        hub.event("s", LiveEvent::delta("x", LiveField::Text, "x".repeat(400)));
        hub.event("s", LiveEvent::delta("x", LiveField::Text, "x".repeat(400)));
        got.extend(drain(&mut rx));
        assert_eq!(rates(&got).len(), 1, "then told, and not again within the second");
        assert!(rates(&got)[0] > 0);
        hub.event("s", LiveEvent::End { id: "x".into() });
        got.extend(drain(&mut rx));
        assert_eq!(rates(&got).last(), Some(&0));
        assert!(!got.iter().any(|m| matches!(m, LiveMessage::Step { event: LiveEvent::Delta { .. } })), "no delta is told");
    }
}
