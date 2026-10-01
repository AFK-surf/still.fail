//! One actor per session. Every change to a session's state runs through its serial queue, so runtime events,
//! deliveries and tool calls never interleave halfway.

use std::collections::{HashMap, HashSet};
use std::future::Future;
use std::panic::AssertUnwindSafe;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, Weak};

use anyhow::{Result, anyhow};
use stillfail_shapes::RuntimeKind;
use futures_util::FutureExt;
use futures_util::future::BoxFuture;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::{mpsc, oneshot};
use tracing::{error, info, warn};

use crate::chat::status::tool_status;
use crate::chat::{ChatSurface, ThreadRef};
use crate::config::Profile;
use crate::instructions::{GO_ON_AFTER_SPENT, NUDGE, RESUME_AFTER_RESTART, RESUME_LOST, continued_here, format_inbound, format_widget_models, session_instructions, wait_over};
use crate::live::LiveHub;
use crate::runtime::{AgentDriver, AgentSession, FailureReason, LiveEvent, LivePhase, LiveStepKind, OpenOptions, RuntimeEvent, TurnOutcome, uuid};
use crate::store::{AuthorKind, STILLFAIL_SURFACE, NewMessage, PendingMessage, Store, TurnFor, now_ms};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeclaredState {
    Final,
    Block,
    /// The work goes on after the turn (a background agent or command of the runtime's) and will bring the agent back
    /// on its own; if nothing has by then, the agent is asked again after this many seconds.
    Waiting(u64),
}

impl DeclaredState {
    pub fn as_str(self) -> &'static str {
        match self {
            DeclaredState::Final => "final",
            DeclaredState::Block => "block",
            DeclaredState::Waiting(_) => "waiting",
        }
    }
}

/// What a session needs of the station. The hub gives it; the actor holds it weakly, so the hub's end ends the actors.
pub trait SessionDeps: Send + Sync {
    fn store(&self) -> Arc<Store>;
    /// A connect's chat connection, when it is connected. A session hears from and answers through several.
    fn chat(&self, connect: &str) -> Option<Arc<dyn ChatSurface>>;
    fn driver(&self, runtime: RuntimeKind) -> Result<Arc<dyn AgentDriver>>;
    /// The profile a session's runtime starts on now: its own while usable, else another that can take it on.
    fn run_on(&self, key: &str) -> Result<Profile>;
    /// A turn ran into its profile's allowance: the names of the profile left and the one the session moved to, when
    /// it moved (see Hub::spend).
    fn spend(&self, _key: &str) -> Result<Option<(String, String)>> {
        Ok(None)
    }
    fn mcp_url(&self) -> String;
    fn repos_dir(&self) -> PathBuf;
    fn memory_path(&self) -> PathBuf;
    fn max_nudges(&self) -> u32;
    /// Whether a message to the session's running turn first moves what it waits on to the background (its profile's
    /// setting).
    fn background_on_message(&self, key: &str) -> bool;
    /// Where the runtime's live steps go, for whoever watches the session.
    fn live(&self) -> Option<Arc<LiveHub>>;
    /// The runtime process has gone idle (see the hub's eviction deadlines).
    fn idle(&self, key: &str);
    /// Turns are held (the station is about to restart or hand over to its next binary): none starts, and messages
    /// stay pending, until it is released.
    fn held(&self) -> bool {
        false
    }
}

struct Turn {
    id: String,
    declared: Option<DeclaredState>,
}

/// A chat thread the running turn works for, with the message that brought it in: it is told what the turn does.
#[derive(Clone)]
struct Working {
    connect: String,
    thread: ThreadRef,
    ts: Option<String>,
}

/// A session as the station's next binary takes it up (handoff.rs): its runtime session, as its driver handed it
/// over, and where the actor stood.
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct HandedSession {
    pub key: String,
    pub runtime: RuntimeKind,
    /// The driver's own words for the runtime session (AgentSession::hand_off).
    pub agent: Value,
    pub turn: Option<HandedTurn>,
    #[serde(default)]
    pub working_for: Vec<HandedWorking>,
    #[serde(default)]
    pub notices: Vec<String>,
    /// The agent's wait: how long is left of it (ms), and how long it was.
    pub waiting_ms: Option<i64>,
    #[serde(default)]
    pub waiting_seconds: u64,
    #[serde(default)]
    pub nudges: u32,
    #[serde(default)]
    pub stop_requested: bool,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct HandedTurn {
    pub id: String,
    /// final, block or waiting.
    pub declared: Option<String>,
    pub wait: Option<u64>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct HandedWorking {
    pub connect: String,
    pub channel: String,
    pub thread_ts: String,
    pub ts: Option<String>,
}

#[derive(Default)]
struct State {
    /// The runtime session, with the generation it was opened in: events of an older one are ignored.
    agent: Option<(u64, Arc<dyn AgentSession>)>,
    /// The profile that runtime session runs on: what a notice of its sign-in or allowance failing points to.
    profile: Option<String>,
    generation: u64,
    turn: Option<Turn>,
    nudges: u32,
    stop_requested: bool,
    resume_lost: bool,
    idle_since: i64,
    working_for: Vec<Working>,
    /// Tool calls under way in the running turn, in the order they started: what the status line says.
    tools: Vec<(String, String)>,
    /// The station's words for the agent outside any conversation (a job's notices), not yet given to it.
    notices: Vec<String>,
    /// The agent said it is waiting on work that brings it back: the wait's number, until a turn starts. Its process is
    /// kept meanwhile (the work may run inside it).
    waiting: Option<u64>,
    waits: u64,
    /// When the wait is over (ms), and how long it was said to be.
    waiting_until: i64,
    waiting_seconds: u64,
    /// Messages (thread, n) given to the running turn while it ran, since the last turn the station started: the runtime
    /// may not have read them yet (suspend).
    steered: Vec<(i64, i64)>,
}

type Task = Box<dyn FnOnce(Arc<SessionActor>) -> BoxFuture<'static, Result<()>> + Send>;

/// One queued task, counted until it is done (or dropped).
struct Counted(Arc<AtomicUsize>);

impl Drop for Counted {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::SeqCst);
    }
}

pub struct SessionActor {
    pub key: String,
    /// A session's runtime never changes.
    pub runtime: RuntimeKind,
    deps: Weak<dyn SessionDeps>,
    queue: mpsc::UnboundedSender<(Task, oneshot::Sender<()>)>,
    state: Mutex<State>,
    /// Set for shutdown: queued and future tasks are skipped from then on.
    closing: AtomicBool,
    /// Tasks queued or running.
    queued: Arc<AtomicUsize>,
}

impl SessionActor {
    pub fn new(key: &str, runtime: RuntimeKind, deps: Weak<dyn SessionDeps>) -> Arc<SessionActor> {
        let (queue, mut tasks) = mpsc::unbounded_channel::<(Task, oneshot::Sender<()>)>();
        let queued: Arc<AtomicUsize> = Arc::default();
        let actor = Arc::new(SessionActor {
            key: key.to_string(),
            runtime,
            deps,
            queue,
            state: Mutex::new(State { idle_since: now_ms(), ..State::default() }),
            closing: AtomicBool::new(false),
            queued: queued.clone(),
        });
        let me = Arc::downgrade(&actor);
        tokio::spawn(async move {
            while let Some((task, done)) = tasks.recv().await {
                let _counted = Counted(queued.clone());
                let Some(actor) = me.upgrade() else { return };
                if !actor.closing.load(Ordering::SeqCst) {
                    let key = actor.key.clone();
                    match AssertUnwindSafe(task(actor)).catch_unwind().await {
                        Ok(Ok(())) => {}
                        Ok(Err(e)) => error!(session = key, error = %format!("{e:#}"), "session task failed"),
                        Err(_) => error!(session = key, "session task panicked"),
                    }
                }
                let _ = done.send(());
            }
        });
        actor
    }

    fn st(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap()
    }

    fn deps(&self) -> Result<Arc<dyn SessionDeps>> {
        self.deps.upgrade().ok_or_else(|| anyhow!("the station is shutting down"))
    }

    fn agent(&self) -> Option<Arc<dyn AgentSession>> {
        self.st().agent.as_ref().map(|(_, a)| a.clone())
    }

    fn is_current(&self, generation: u64) -> bool {
        self.st().agent.as_ref().is_some_and(|(g, _)| *g == generation)
    }

    /// Queues a task; what it returns resolves once the task has run (or was skipped). The task is queued at once,
    /// whether or not that is awaited.
    fn enqueue<F, Fut>(&self, task: F) -> impl Future<Output = ()> + Send + 'static
    where
        F: FnOnce(Arc<SessionActor>) -> Fut + Send + 'static,
        Fut: Future<Output = Result<()>> + Send + 'static,
    {
        let (done, wait) = oneshot::channel();
        self.queued.fetch_add(1, Ordering::SeqCst);
        if self.queue.send((Box::new(move |actor| Box::pin(task(actor))), done)).is_err() {
            self.queued.fetch_sub(1, Ordering::SeqCst);
        }
        async move {
            let _ = wait.await;
        }
    }

    /// running: a turn is in progress; warm: a runtime process is waiting for input; cold: none.
    pub fn process_state(&self) -> &'static str {
        let st = self.st();
        match &st.agent {
            _ if st.turn.is_some() => "running",
            Some((_, a)) if a.busy() => "running",
            Some(_) => "warm",
            None => "cold",
        }
    }

    /// How long the runtime process has sat idle, or None if there is none or it is working.
    pub fn idle_ms(&self, now: i64) -> Option<i64> {
        let st = self.st();
        match &st.agent {
            Some((_, a)) if !a.busy() && st.turn.is_none() && st.waiting.is_none() => Some(now - st.idle_since),
            _ => None,
        }
    }

    /// Delivers any pending messages.
    pub fn kick(&self) -> impl Future<Output = ()> + Send + 'static {
        self.enqueue(|a| async move { a.pump().await })
    }

    /// A word from the station for the agent, outside any conversation (a background job's notice): it joins the
    /// running turn, or runs as a turn of its own; one the running turn cannot take waits for its end.
    pub fn notify(&self, text: String) -> impl Future<Output = ()> + Send + 'static {
        self.st().notices.push(text);
        self.enqueue(|a| async move { a.give_notices().await })
    }

    /// Called by the MCP tools while a turn runs.
    pub fn declare(&self, state: DeclaredState) {
        if let Some(turn) = self.st().turn.as_mut() {
            turn.declared = Some(state);
        }
    }

    pub fn stop(&self) -> impl Future<Output = ()> + Send + 'static {
        self.enqueue(|a| async move {
            if let Some(agent) = a.agent().filter(|agent| agent.busy()) {
                a.st().stop_requested = true;
                agent.abort().await;
            }
            Ok(())
        })
    }

    /// Its last turn stopped at its account's allowance and it was changed since (another account or model): it goes on
    /// where it stopped, unless something runs already.
    pub fn go_on(&self) -> impl Future<Output = ()> + Send + 'static {
        self.enqueue(|a| async move {
            let deps = a.deps()?;
            if deps.held() || a.st().turn.is_some() || a.agent().is_some_and(|agent| agent.busy()) {
                return Ok(());
            }
            if !deps.store().pending_messages(&a.key)?.is_empty() {
                return a.pump().await;
            }
            a.start_turn(&deps, "resume", GO_ON_AFTER_SPENT).await
        })
    }

    /// After the station restarts: the turn recorded as running was cut off; resume it.
    pub fn recover(&self) -> impl Future<Output = ()> + Send + 'static {
        self.enqueue(|a| async move {
            let deps = a.deps()?;
            let store = deps.store();
            store.set_running(&a.key, false)?;
            let pending = store.pending_messages(&a.key)?;
            let (said, widgets) = a.format(&deps, &pending).await?;
            let text = if said.is_empty() { RESUME_AFTER_RESTART.to_string() } else { format!("{RESUME_AFTER_RESTART}\n\n{said}") };
            a.start_turn(&deps, "resume", &text).await?;
            a.delivered(&store, &pending, &widgets)
        })
    }

    /// No task queued or running.
    pub fn settled(&self) -> bool {
        self.queued.load(Ordering::SeqCst) == 0
    }

    /// Turns were held and are no longer: what waited meanwhile (messages, notices, a wait that ran out) goes on.
    pub fn release(&self) -> impl Future<Output = ()> + Send + 'static {
        self.enqueue(|a| async move {
            let over = {
                let st = a.st();
                st.waiting.is_some() && st.waiting_until <= now_ms()
            };
            if over {
                let seconds = a.st().waiting_seconds;
                a.wait_ms(seconds, 0);
            }
            a.pump().await?;
            if !a.st().notices.is_empty() {
                a.give_notices().await?;
            }
            Ok(())
        })
    }

    /// Whether the actor holds anything the next binary should take up besides a runtime session: words for the agent
    /// not yet given, or its wait.
    pub fn holds_state(&self) -> bool {
        let st = self.st();
        !st.notices.is_empty() || st.waiting.is_some()
    }

    /// Gives the runtime session up to the next binary (turns are held and the queue settled). None when there is
    /// none, or it could not be given up: then it ends with this binary, and the next resumes it the usual way.
    pub async fn hand_off_agent(&self) -> Option<Value> {
        let agent = self.agent()?;
        match agent.hand_off().await {
            Ok(handed) => Some(handed),
            Err(e) => {
                warn!(session = self.key, error = %e, "runtime session not handed over");
                None
            }
        }
    }

    /// Where the session stands, with its runtime session as `hand_off_agent` gave it (null: none): for the next
    /// binary. From here on this actor does nothing more.
    pub fn snapshot(&self, agent: Value) -> HandedSession {
        self.closing.store(true, Ordering::SeqCst);
        let mut st = self.st();
        st.agent = None;
        HandedSession {
            key: self.key.clone(),
            runtime: self.runtime,
            agent,
            turn: st.turn.as_ref().map(|t| HandedTurn {
                id: t.id.clone(),
                declared: t.declared.map(|d| d.as_str().to_string()),
                wait: match t.declared {
                    Some(DeclaredState::Waiting(seconds)) => Some(seconds),
                    _ => None,
                },
            }),
            working_for: st.working_for.iter().map(|w| HandedWorking { connect: w.connect.clone(), channel: w.thread.channel.clone(), thread_ts: w.thread.thread_ts.clone(), ts: w.ts.clone() }).collect(),
            notices: st.notices.clone(),
            waiting_ms: st.waiting.map(|_| (st.waiting_until - now_ms()).max(0)),
            waiting_seconds: st.waiting_seconds,
            nudges: st.nudges,
            stop_requested: st.stop_requested,
        }
    }

    /// Takes up a session the previous binary handed over, on `agent` when it had one (its driver took the runtime
    /// session up, with its events coming on the receiver).
    pub fn adopt(self: &Arc<Self>, handed: HandedSession, agent: Option<(Arc<dyn AgentSession>, mpsc::UnboundedReceiver<RuntimeEvent>)>) {
        let (agent, events) = match agent {
            Some((agent, events)) => (Some(agent), Some(events)),
            None => (None, None),
        };
        let generation = {
            let mut st = self.st();
            st.generation += 1;
            st.agent = agent.map(|agent| (st.generation, agent));
            st.turn = handed.turn.map(|t| Turn {
                id: t.id,
                declared: match t.declared.as_deref() {
                    Some("final") => Some(DeclaredState::Final),
                    Some("block") => Some(DeclaredState::Block),
                    Some("waiting") => Some(DeclaredState::Waiting(t.wait.unwrap_or(0))),
                    _ => None,
                },
            });
            st.working_for = handed.working_for.into_iter().map(|w| Working { connect: w.connect, thread: ThreadRef::new(&w.channel, &w.thread_ts), ts: w.ts }).collect();
            st.notices = handed.notices;
            st.nudges = handed.nudges;
            st.stop_requested = handed.stop_requested;
            st.idle_since = now_ms();
            st.generation
        };
        if let Some(ms) = handed.waiting_ms {
            self.wait_ms(handed.waiting_seconds, ms);
        }
        if let Some(events) = events {
            self.follow(generation, events);
        }
    }

    /// Starts the runtime process ahead of a message, so its start-up overlaps the typing. Nothing is sent; an unused
    /// process is evicted as usual.
    pub fn warm(&self) -> impl Future<Output = ()> + Send + 'static {
        self.enqueue(|a| async move {
            if a.agent().is_some() || a.closing.load(Ordering::SeqCst) {
                return Ok(());
            }
            let deps = a.deps()?;
            if deps.held() {
                return Ok(());
            }
            info!(session = a.key, "warming session process");
            a.ensure_agent(&deps).await?;
            a.st().idle_since = now_ms();
            deps.store().notify(&a.key);
            deps.idle(&a.key);
            Ok(())
        })
    }

    /// Ends the runtime process if it is idle.
    pub fn evict(&self) -> impl Future<Output = ()> + Send + 'static {
        self.enqueue(|a| async move {
            let agent = {
                let mut st = a.st();
                match &st.agent {
                    Some((_, agent)) if !agent.busy() && st.turn.is_none() && st.waiting.is_none() => st.agent.take().map(|(_, agent)| agent),
                    _ => None,
                }
            };
            let Some(agent) = agent else { return Ok(()) };
            info!(session = a.key, "evicting idle session process");
            agent.dispose().await;
            a.deps()?.store().notify(&a.key);
            Ok(())
        })
    }

    /// The station left its workspace: the runtime process ends, and with it whatever the agent was doing or had been
    /// given, so nothing it was told gets acted on outside the workspace (a turn interrupted could still read input it
    /// had queued, and post). As at a shutdown, a turn under way stays marked running, for Hub::recover to resume once
    /// the station is back in its workspace (unless it had already said final or block); the messages given to it while
    /// it ran are pending again, since the process may have ended before reading them. Its record ends as aborted. No
    /// notice goes to the thread: the station says nothing while out of its workspace.
    pub fn suspend(&self) -> impl Future<Output = ()> + Send + 'static {
        self.enqueue(|a| async move {
            let (agent, turn, busy, steered) = {
                let mut st = a.st();
                let agent = st.agent.take().map(|(_, agent)| agent);
                let busy = agent.as_ref().is_some_and(|agent| agent.busy());
                st.tools.clear();
                st.working_for.clear();
                st.stop_requested = false;
                (agent, st.turn.take(), busy, std::mem::take(&mut st.steered))
            };
            if agent.is_none() && turn.is_none() {
                return Ok(());
            }
            let deps = a.deps()?;
            let store = deps.store();
            let settled = turn.as_ref().is_some_and(|t| matches!(t.declared, Some(DeclaredState::Final | DeclaredState::Block)));
            let resume = (turn.is_some() || busy) && !settled;
            info!(session = a.key, resume, "ending the runtime process: the station is in no workspace");
            if let Some(agent) = agent {
                agent.dispose().await;
            }
            if let Some(turn) = &turn {
                store.end_turn(&turn.id, "aborted", Some("other: the station left its workspace"), turn.declared.map(DeclaredState::as_str), None)?;
            }
            store.set_running(&a.key, resume)?;
            if turn.is_some() || busy {
                store.mark_undelivered(&a.key, &steered)?;
            }
            if let Some(live) = deps.live() {
                live.turn_ended(&a.key);
            }
            store.notify(&a.key);
            Ok(())
        })
    }

    /// For shutdown. A running turn is left marked running, so the next start resumes it instead of reporting a crash
    /// to the thread.
    pub async fn dispose(&self) {
        self.closing.store(true, Ordering::SeqCst);
        let agent = self.st().agent.take();
        if let Some((_, agent)) = agent {
            agent.dispose().await;
        }
    }

    // ── internals (always inside the queue) ────────────────────────────────

    /// The notices waiting, as the agent reads them: each a message from the station (via="ember", as before the rename).
    fn take_notices(&self) -> Option<String> {
        let notices = std::mem::take(&mut self.st().notices);
        if notices.is_empty() {
            return None;
        }
        let at = crate::chat::internal::next_ts();
        Some(notices.iter().map(|n| format!("<message via=\"ember\" from=\"ember\" ts=\"{at}\">\n{n}\n</message>")).collect::<Vec<_>>().join("\n"))
    }

    async fn give_notices(self: &Arc<Self>) -> Result<()> {
        let deps = self.deps()?;
        if deps.held() {
            return Ok(());
        }
        if let Some(agent) = self.agent().filter(|a| a.busy()) {
            let Some(text) = self.take_notices() else { return Ok(()) };
            if !agent.steer(&text).await {
                // Not now: after the running turn.
                self.st().notices.insert(0, text);
            }
            return Ok(());
        }
        let Some(text) = self.take_notices() else { return Ok(()) };
        self.start_turn(&deps, "job", &text).await
    }

    async fn pump(self: &Arc<Self>) -> Result<()> {
        let deps = self.deps()?;
        if deps.held() {
            return Ok(()); // they stay pending: delivered once released, or by the next binary
        }
        let store = deps.store();
        let pending = store.pending_messages(&self.key)?;
        if pending.is_empty() {
            return Ok(());
        }
        let (text, widgets) = self.format(&deps, &pending).await?;
        if let Some(agent) = self.agent().filter(|a| a.busy()) {
            // So it is read now, not when a long command ends; what it waited on goes on.
            if deps.background_on_message(&self.key) {
                agent.background_tools().await;
            }
            if agent.steer(&text).await {
                self.work_for(&deps, &pending);
                self.delivered(&store, &pending, &widgets)?;
                self.st().steered.extend(pending.iter().map(|m| (m.message.thread, m.message.n)));
            }
            return Ok(()); // otherwise delivered when the turn ends
        }
        self.st().nudges = 0;
        self.work_for(&deps, &pending);
        // The turn is for the first person whose message it takes.
        let by = pending
            .iter()
            .find(|m| m.message.author_kind == AuthorKind::Person)
            .map(|m| TurnFor { person: Some(person_ref(m)), thread: Some(m.message.thread), profile: None })
            .unwrap_or_default();
        self.start_turn_for(&deps, "input", &text, by).await?;
        self.delivered(&store, &pending, &widgets)
    }

    fn work_for(&self, deps: &Arc<dyn SessionDeps>, messages: &[PendingMessage]) {
        {
            let mut st = self.st();
            for m in messages.iter().filter(|m| m.surface != STILLFAIL_SURFACE) {
                let thread = ThreadRef::new(&m.channel, &m.thread_ts);
                match st.working_for.iter_mut().find(|w| w.connect == m.connect && w.thread == thread) {
                    Some(at) => at.ts = Some(m.message.ts.clone()),
                    None => st.working_for.push(Working { connect: m.connect.clone(), thread, ts: Some(m.message.ts.clone()) }),
                }
            }
        }
        self.say(deps, "正在思考…");
    }

    fn say(&self, deps: &Arc<dyn SessionDeps>, status: &str) {
        let working = self.st().working_for.clone();
        for w in working {
            if let Some(chat) = deps.chat(&w.connect) {
                chat.working(&w.thread, w.ts.as_deref(), status);
            }
        }
    }

    /// A live step of the running turn, for its threads' status line.
    fn on_live(&self, event: &LiveEvent) {
        let status = {
            let mut st = self.st();
            if st.working_for.is_empty() {
                return;
            }
            match event {
                LiveEvent::Start { id, step: LiveStepKind::Tool, tool: Some(tool), .. } => {
                    if !st.tools.iter().any(|(i, _)| i == id) {
                        st.tools.push((id.clone(), tool.clone()));
                    }
                }
                LiveEvent::End { id } => st.tools.retain(|(i, _)| i != id),
                LiveEvent::Phase { .. } => {}
                _ => return,
            }
            st.tools.last().map(|(_, tool)| tool_status(tool)).unwrap_or("正在思考…")
        };
        if let Ok(deps) = self.deps() {
            self.say(&deps, status);
        }
    }

    /// The turn is over: its threads' status line goes.
    fn done_working(&self, deps: &Arc<dyn SessionDeps>) {
        self.say(deps, "");
        let mut st = self.st();
        st.working_for.clear();
        st.tools.clear();
    }

    /// `widgets`: the widget models told with them (path, model), told once.
    fn delivered(&self, store: &Store, messages: &[PendingMessage], widgets: &[(String, String)]) -> Result<()> {
        store.mark_delivered(&self.key, &messages.iter().map(|m| (m.message.thread, m.message.n)).collect::<Vec<_>>())?;
        store.mark_widget_models_told(&self.key, widgets)
    }

    /// The messages as the agent reads them, made now so edits count: each with its source and sender's name, plus a
    /// hint when a thread appears in this session for the first time mid-conversation (its earlier messages are only a
    /// chat_history away); then what people chose in its widgets since it was last told, with the widgets told (path,
    /// model) for `delivered`.
    async fn format(&self, deps: &Arc<dyn SessionDeps>, said: &[PendingMessage]) -> Result<(String, Vec<(String, String)>)> {
        let heard = deps.store().heard_threads(&self.key)?;
        let new_threads: HashSet<i64> = said.iter().map(|m| m.message.thread).filter(|t| !heard.contains(t)).collect();
        let mut names = HashMap::new();
        for m in said {
            if names.contains_key(&m.message.author) {
                continue;
            }
            if m.message.author_kind == AuthorKind::Agent {
                names.insert(m.message.author.clone(), self.agent_name(deps, &m.message.author, m.message.thread));
                continue;
            }
            if m.message.author_kind != AuthorKind::Person {
                continue;
            }
            let Some(chat) = deps.chat(&m.connect) else { continue };
            if let Some(name) = chat.user_name(&m.message.author).await {
                names.insert(m.message.author.clone(), name);
            }
        }
        // What the agent is called in each connect these came through: the bot's name there and its mention.
        let mut selves = HashMap::new();
        for m in said {
            if selves.contains_key(&m.connect) {
                continue;
            }
            let Some(chat) = deps.chat(&m.connect) else { continue };
            let (name, user) = (chat.bot_name(), chat.bot_user_id());
            if !name.is_empty() {
                selves.insert(m.connect.clone(), if user.is_empty() { name } else { format!("{name} (<@{user}>)") });
            }
        }
        let text = format_inbound(said, &new_threads, &names, &selves);
        let models = deps.store().untold_widget_models(&self.key)?;
        let widgets = models.iter().map(|w| (w.path.clone(), w.model.clone())).collect();
        let text = match format_widget_models(&models) {
            told if told.is_empty() => text,
            told if text.is_empty() => told,
            told => format!("{text}\n\n{told}"),
        };
        Ok((text, widgets))
    }

    /// What another agent goes by in a thread: the bot of the connect it posts there through, with its mention (in
    /// Slack, to call on it); in the station's own chats, its runtime and model.
    fn agent_name(&self, deps: &Arc<dyn SessionDeps>, key: &str, thread: i64) -> String {
        let store = deps.store();
        let via = store.thread_sessions(thread).ok().and_then(|ms| ms.into_iter().find(|m| m.session == key)).map(|m| m.connect);
        if let Some(chat) = via.as_deref().filter(|c| *c != crate::chat::internal::INTERNAL_CONNECT).and_then(|c| deps.chat(c)) {
            let (name, user) = (chat.bot_name(), chat.bot_user_id());
            if !name.is_empty() {
                return if user.is_empty() { name } else { format!("{name} (<@{user}>)") };
            }
        }
        match store.get_session(key).ok().flatten() {
            Some(row) => format!("{}{}", if row.runtime == "claude" { "Claude Code" } else { "Codex" }, row.model.map(|m| format!(" {m}")).unwrap_or_default()),
            None => "another agent".into(),
        }
    }

    /// Starts a turn with `text`. On failure the thread is told and the error returned, so callers leave their messages
    /// pending for the next attempt.
    async fn start_turn(self: &Arc<Self>, deps: &Arc<dyn SessionDeps>, kind: &str, text: &str) -> Result<()> {
        self.start_turn_for(deps, kind, text, TurnFor::default()).await
    }

    /// Starts a turn with `text` for someone: the person whose message it answers, and where (usage counts it theirs).
    async fn start_turn_for(self: &Arc<Self>, deps: &Arc<dyn SessionDeps>, kind: &str, text: &str, by: TurnFor) -> Result<()> {
        let started = async {
            // Until the runtime says it has sent its request, the turn is starting (a warm process can still take a while
            // to take input).
            if let Some(live) = deps.live() {
                live.event(&self.key, LiveEvent::Phase { phase: LivePhase::Starting });
            }
            let mut agent = self.ensure_agent(deps).await?;
            // A session begun in a terminal and continued here: its first turn here says so, with how still.fail works (its
            // system prompt is left as it began).
            let continued = match deps.store().get_session(&self.key)? {
                Some(row) if row.cwd.is_some() && !deps.store().has_turns(&self.key)? => Some(continued_here(
                    &session_instructions(&row.workspace, row.cwd.as_deref(), &deps.repos_dir().to_string_lossy(), &deps.memory_path().to_string_lossy()),
                )),
                _ => None,
            };
            let prompt = {
                let mut st = self.st();
                let lost = std::mem::take(&mut st.resume_lost);
                let text = if lost { format!("{RESUME_LOST}\n\n{text}") } else { text.to_string() };
                match continued {
                    Some(preface) => format!("{preface}\n\n{text}"),
                    None => text,
                }
            };
            // The runtime may have started a turn on its own (late input became a turn); join it.
            if agent.busy() && agent.steer(&prompt).await {
                return Ok(());
            }
            self.st().steered.clear();
            self.begin_turn(deps, kind, by)?;
            if let Err(e) = agent.prompt(&prompt).await {
                // The runtime is unusable (died between turns, or refused): replace it once.
                warn!(session = self.key, error = %e, "prompt failed, reopening the runtime");
                self.st().agent = None;
                agent.dispose().await;
                agent = self.ensure_agent(deps).await?;
                agent.prompt(&prompt).await?;
            }
            Ok::<_, anyhow::Error>(())
        };
        let Err(e) = started.await else { return Ok(()) };
        let message = e.to_string();
        let store = deps.store();
        let turn = self.st().turn.take();
        if let Some(turn) = turn {
            store.end_turn(&turn.id, "failed", Some(&format!("other: {message}")), None, None)?;
        }
        store.set_running(&self.key, false)?;
        self.done_working(deps);
        self.notice(deps, &format!("⚠️ 无法启动 agent：{message}")).await;
        Err(e)
    }

    fn begin_turn(&self, deps: &Arc<dyn SessionDeps>, kind: &str, by: TurnFor) -> Result<()> {
        let id = uuid();
        let profile = {
            let mut st = self.st();
            st.turn = Some(Turn { id: id.clone(), declared: None });
            st.waiting = None;
            st.profile.clone()
        };
        let store = deps.store();
        store.start_turn_for(&id, &self.key, kind, &TurnFor { profile, ..by })?;
        store.set_running(&self.key, true)
    }

    async fn ensure_agent(self: &Arc<Self>, deps: &Arc<dyn SessionDeps>) -> Result<Arc<dyn AgentSession>> {
        if let Some(agent) = self.agent() {
            return Ok(agent);
        }
        let store = deps.store();
        let row = store.get_session(&self.key)?.ok_or_else(|| anyhow!("session {} disappeared", self.key))?;
        let driver = deps.driver(self.runtime)?;
        let profile = deps.run_on(&self.key)?;
        let profile_id = profile.id.clone();
        // The model as this profile spells it (openai/gpt-6-astra on a router for gpt-6-astra).
        let model = row.model.as_deref().map(|m| profile.spelling(m).unwrap_or(m).to_string());
        let base = OpenOptions {
            profile,
            cwd: PathBuf::from(row.cwd.as_deref().unwrap_or(&row.workspace)),
            resume: None,
            model,
            effort: row.effort.clone(),
            // A session continued from a terminal keeps the system prompt it began with (its cache holds); its first turn
            // here brings the station's instructions instead (start_turn).
            instructions: if row.cwd.is_some() {
                String::new()
            } else {
                session_instructions(&row.workspace, None, &deps.repos_dir().to_string_lossy(), &deps.memory_path().to_string_lossy())
            },
            mcp_token: row.token.clone(),
            mcp_url: deps.mcp_url(),
            route: row.key.clone(),
        };
        let generation = {
            let mut st = self.st();
            st.generation += 1;
            st.generation
        };
        let (events, received) = mpsc::unbounded_channel();
        let (agent, received) = match &row.runtime_session_id {
            Some(id) => match driver.open(OpenOptions { resume: Some(id.clone()), ..base.clone() }, events).await {
                Ok(agent) => (agent, received),
                Err(e) => {
                    warn!(session = self.key, runtime_session_id = id, error = %e, "resume failed; starting a new runtime session");
                    let (events, received) = mpsc::unbounded_channel();
                    let agent = driver.open(base, events).await?;
                    self.st().resume_lost = true;
                    (agent, received)
                }
            },
            None => (driver.open(base, events).await?, received),
        };
        let id = agent.id();
        if row.runtime_session_id.as_deref() != Some(id.as_str()) {
            store.set_runtime_session_id(&self.key, &id)?;
        }
        {
            let mut st = self.st();
            st.agent = Some((generation, agent.clone()));
            st.profile = Some(profile_id);
        }
        self.follow(generation, received);
        Ok(agent)
    }

    /// Takes a runtime session's events, in order, for as long as it sends them.
    fn follow(self: &Arc<Self>, generation: u64, mut events: mpsc::UnboundedReceiver<RuntimeEvent>) {
        let me = Arc::downgrade(self);
        tokio::spawn(async move {
            while let Some(event) = events.recv().await {
                let Some(actor) = me.upgrade() else { return };
                match event {
                    RuntimeEvent::TurnStarted => {
                        let _ = actor.enqueue(move |a| async move {
                            if a.is_current(generation) && a.st().turn.is_none() {
                                a.begin_turn(&a.deps()?, "input", TurnFor::default())?;
                            }
                            Ok(())
                        });
                    }
                    RuntimeEvent::TurnEnded(outcome) => {
                        if let Ok(deps) = actor.deps() {
                            if let Some(live) = deps.live() {
                                live.turn_ended(&actor.key);
                            }
                            actor.done_working(&deps);
                        }
                        let _ = actor.enqueue(move |a| async move { a.on_turn_ended(generation, outcome).await });
                    }
                    RuntimeEvent::Live(event) => {
                        if let Some(live) = actor.deps().ok().and_then(|d| d.live()) {
                            live.event(&actor.key, event.clone());
                        }
                        actor.on_live(&event);
                    }
                    RuntimeEvent::Closed(reason) => {
                        let _ = actor.enqueue(move |a| async move {
                            if a.is_current(generation) {
                                info!(session = a.key, reason, "session runtime closed");
                                a.st().agent = None;
                                a.deps()?.store().notify(&a.key);
                            }
                            Ok(())
                        });
                    }
                }
            }
        });
    }

    async fn on_turn_ended(self: &Arc<Self>, generation: u64, outcome: TurnOutcome) -> Result<()> {
        if !self.is_current(generation) {
            return Ok(());
        }
        let deps = self.deps()?;
        let store = deps.store();
        let (turn, stop_requested) = {
            let mut st = self.st();
            st.idle_since = now_ms();
            (st.turn.take(), std::mem::take(&mut st.stop_requested))
        };
        store.set_running(&self.key, false)?;
        if let Some(turn) = &turn {
            let detail = match &outcome {
                TurnOutcome::Failed { reason, message } => Some(format!("{}: {message}", reason.as_str())),
                _ => None,
            };
            let wait = match turn.declared {
                Some(DeclaredState::Waiting(seconds)) => Some(seconds),
                _ => None,
            };
            store.end_turn(&turn.id, outcome.kind(), detail.as_deref(), turn.declared.map(DeclaredState::as_str), wait)?;
        }
        match &outcome {
            TurnOutcome::Failed { reason: FailureReason::RateLimit, .. } => {
                self.st().nudges = 0;
                // Left to the station, it moves to another account and goes on there; otherwise it waits for a change.
                let moved = deps.spend(&self.key).unwrap_or_else(|e| {
                    warn!(session = self.key, error = %e, "could not move off a spent profile");
                    None
                });
                if let Some((from, to)) = moved {
                    // Its process runs on the account left: the next starts on the one taken.
                    let agent = self.st().agent.take();
                    if let Some((_, agent)) = agent {
                        agent.dispose().await;
                    }
                    info!(session = self.key, from, to, "allowance ran out; going on on another profile");
                    if !store.pending_messages(&self.key)?.is_empty() {
                        return self.pump().await;
                    }
                    return self.start_turn(&deps, "resume", GO_ON_AFTER_SPENT).await;
                }
                let profile = self.st().profile.clone();
                self.notice_about(&deps, &failure_notice(&outcome), profile).await;
            }
            TurnOutcome::Failed { reason, .. } => {
                self.st().nudges = 0;
                // A sign-in that failed is its profile's: the notice points there.
                let profile = if *reason == FailureReason::Auth { self.st().profile.clone() } else { None };
                self.notice_about(&deps, &failure_notice(&outcome), profile).await;
            }
            TurnOutcome::Aborted => {
                self.st().nudges = 0;
                if stop_requested {
                    self.notice(&deps, "已停止当前任务").await;
                }
            }
            TurnOutcome::Completed => {}
        }

        if !store.pending_messages(&self.key)?.is_empty() {
            return self.pump().await;
        }
        if !self.st().notices.is_empty() {
            return self.give_notices().await;
        }
        let declared = turn.as_ref().and_then(|t| t.declared);
        if let (TurnOutcome::Completed, Some(DeclaredState::Waiting(seconds))) = (&outcome, declared) {
            self.st().nudges = 0;
            self.wait(seconds);
            deps.idle(&self.key);
            return Ok(());
        }
        deps.idle(&self.key);
        if outcome != TurnOutcome::Completed || declared.is_some() {
            self.st().nudges = 0;
            return Ok(());
        }
        if deps.held() {
            return Ok(());
        }
        let attempt = {
            let mut st = self.st();
            if st.nudges < deps.max_nudges() {
                st.nudges += 1;
                Some(st.nudges)
            } else {
                st.nudges = 0;
                None
            }
        };
        match attempt {
            Some(attempt) => {
                info!(session = self.key, attempt, "turn ended without a state; nudging");
                self.start_turn(&deps, "nudge", NUDGE).await
            }
            None => {
                self.notice(&deps, "⚠️ 这一轮没有给出结果就停了，回复可继续").await;
                Ok(())
            }
        }
    }

    /// Asks the agent again after `seconds`, unless a turn has started by then (what it waited on brought it back, or
    /// someone wrote).
    fn wait(self: &Arc<Self>, seconds: u64) {
        self.wait_ms(seconds, seconds as i64 * 1000);
    }

    /// The same, with `ms` of it left.
    fn wait_ms(self: &Arc<Self>, seconds: u64, ms: i64) {
        let wait = {
            let mut st = self.st();
            st.waits += 1;
            st.waiting = Some(st.waits);
            st.waiting_until = now_ms() + ms;
            st.waiting_seconds = seconds;
            st.waits
        };
        let me = Arc::downgrade(self);
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(ms.max(0) as u64)).await;
            let Some(actor) = me.upgrade() else { return };
            let _ = actor.enqueue(move |a| async move {
                // Held: the wait stays, for the next binary to take up.
                if a.deps()?.held() {
                    return Ok(());
                }
                if a.st().waiting.take_if(|w| *w == wait).is_none() {
                    return Ok(());
                }
                // Keeping watch: the watch brings it back (its notices, its end), not the clock; it waits on.
                let watching = a.deps()?.store().list_jobs(Some(&a.key))?.iter().any(|j| j.watch && j.state == "running");
                if watching {
                    a.wait(seconds);
                    return Ok(());
                }
                info!(session = a.key, seconds, "the wait is over without word; asking again");
                a.start_turn(&a.deps()?, "nudge", &wait_over(seconds)).await
            });
        });
    }

    /// The station's own words (not the agent's) go to the thread people spoke in last, and are recorded there.
    async fn notice(&self, deps: &Arc<dyn SessionDeps>, text: &str) {
        self.notice_about(deps, text, None).await;
    }

    /// A notice about one of the station's profiles (`profile`, its id): the clients link it to that profile's page.
    async fn notice_about(&self, deps: &Arc<dyn SessionDeps>, text: &str, profile: Option<String>) {
        let store = deps.store();
        let latest = store.latest_thread(&self.key).ok().flatten();
        let Some((latest, chat)) = latest.and_then(|l| deps.chat(&l.connect).map(|c| (l, c))) else {
            warn!(session = self.key, text, "no thread to post a notice to");
            return;
        };
        let thread = ThreadRef::new(&latest.thread.channel, &latest.thread.thread_ts);
        let posted = async {
            let ts = chat.post(&thread, text, &[]).await?;
            store.insert_message(NewMessage { profile, ..NewMessage::new(latest.thread.id, &ts, AuthorKind::StillFail, "ember", text) })?;
            Ok::<_, anyhow::Error>(())
        };
        if let Err(e) = posted.await {
            warn!(session = self.key, error = %e, "notice failed");
        }
    }
}

fn failure_notice(outcome: &TurnOutcome) -> String {
    let TurnOutcome::Failed { reason, message } = outcome else { return String::new() };
    match reason.as_str() {
        "auth" => format!("⚠️ 认证失败，需要管理员检查账号：{message}"),
        "rate_limit" => format!("⚠️ 触发额度或限流，换个账号或模型会接着做，稍后回复也可继续：{message}"),
        "exited" => format!("⚠️ agent 进程意外退出，回复可恢复：{message}"),
        _ => format!("⚠️ 这一轮出错：{message}"),
    }
}

/// Who wrote a message, as a creator reference: their email on the page, their Slack user through the connect it came
/// by (store.rs thread_people).
fn person_ref(m: &PendingMessage) -> String {
    if m.surface == STILLFAIL_SURFACE { m.message.author.clone() } else { format!("slack:{}:{}", m.connect, m.message.author) }
}
