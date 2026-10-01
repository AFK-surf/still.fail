//! Routes chat messages to session actors, creates sessions, and exposes the MCP tools through which agents act on
//! their conversations. Several connects share one hub; each has its own chat connection and its own sessions.
//!
//! A connect's mode decides the sessions: multi-session gives each thread its own session (started by an @mention);
//! single-session sends every thread the connect sees into the one session bound to it, which people can switch or
//! replace. Either way every message carries its source and the agent names the thread it answers, so a session never
//! assumes it belongs to one conversation; replies go out through whichever connect the thread came in on.
//!
//! Everything said in a thread is recorded once (see store.rs): people's messages are delivered to every session in the
//! thread, and what agents and the station post there is recorded after the platform takes it.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, Weak};
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use base64::Engine;
use stillfail_shapes::{ConnectMode, RuntimeKind};
use futures_util::future::BoxFuture;
use serde_json::{Map, Value, json};
use tokio::task::JoinHandle;
use tracing::{error, info, warn};

use crate::agent_home::agent_home_paths;
use crate::chat::internal::{INTERNAL_CHANNEL, INTERNAL_CONNECT, InternalChat, next_ts};
use crate::chat::{ChatEvent, ChatSurface, InboundMessage, ThreadRef};
use crate::config::{Config, Connect, Profile, profiles_for, runtime_named};
use crate::image_size::image_size;
use crate::instructions::{format_history, parse_thread_address, thread_address};
use crate::live::LiveHub;
use crate::machine_sessions::{MachineRoots, MachineSession};
use crate::mcp::{Run, Tool};
use crate::pool::{PoolSignals, ProfileHealth, pick_profile, serves, usable};
use crate::runtime::AgentDriver;
use crate::session::{DeclaredState, HandedSession, SessionActor, SessionDeps};
use crate::store::{
    AUTO, Attachment, AuthorKind, STILLFAIL_SURFACE, MANUAL, NewMessage, NewSession, Post, Quote, SessionRow, SessionScope, SessionThread, Store, ThreadRow, now_ms,
    slack_surface, write_compressed,
};
use crate::transcript::{TimelineEntry, iso, transcript_path};

/// A multi-session connect's session for one thread.
pub fn session_key(connect: &str, channel: &str, thread_ts: &str) -> String {
    format!("{connect}:{channel}:{thread_ts}")
}

fn random_bytes<const N: usize>() -> [u8; N] {
    let mut b = [0u8; N];
    getrandom::fill(&mut b).expect("the system's randomness");
    b
}

/// A new session for a single-session connect.
pub fn new_single_session_key(connect: &str) -> String {
    format!("{connect}:s-{}", hex::encode(random_bytes::<4>()))
}

fn new_token() -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(random_bytes::<24>())
}

/// `-stop`, alone or after mentions.
pub fn is_stop_command(text: &str) -> bool {
    let mut rest = text.trim();
    while let Some(after) = rest.strip_prefix("<@") {
        let Some(end) = after.find('>') else { return false };
        let id = &after[..end];
        if id.is_empty() || !id.chars().all(|c| c.is_ascii_alphanumeric()) {
            return false;
        }
        rest = after[end + 1..].trim_start();
    }
    rest.eq_ignore_ascii_case("-stop")
}

/// A Slack Web API method's shape: family.method, lower camel case.
fn is_slack_method(method: &str) -> bool {
    let mut parts = method.split('.');
    let first = parts.next().unwrap_or("");
    let rest: Vec<&str> = parts.collect();
    first.starts_with(|c: char| c.is_ascii_lowercase())
        && first.chars().all(|c| c.is_ascii_alphabetic())
        && !rest.is_empty()
        && rest.iter().all(|p| !p.is_empty() && p.chars().all(|c| c.is_ascii_alphabetic()))
}

/// Methods that land in a thread: the threads rule applies to them.
const WRITES: [&str; 12] = [
    "chat.postMessage",
    "chat.postEphemeral",
    "chat.scheduleMessage",
    "chat.update",
    "chat.delete",
    "chat.meMessage",
    "reactions.add",
    "reactions.remove",
    "pins.add",
    "pins.remove",
    "files.completeUploadExternal",
    "assistant.threads.",
];

/// How a session runs from its next turn on. Outer None: unchanged; inner None: back to the default.
#[derive(Debug, Clone, Default)]
pub struct SessionChange {
    pub profile: Option<Option<String>>,
    pub model: Option<Option<String>>,
    pub effort: Option<Option<String>>,
}

/// A session of its own, talked to in the station's chat.
#[derive(Debug, Clone)]
pub struct NewChat {
    pub runtime: RuntimeKind,
    pub profile: Option<String>,
    pub model: Option<String>,
    pub effort: Option<String>,
    pub title: Option<String>,
    pub created_by: String,
    /// The key the asking client knows it by until it is made (`clientKey`): the sidebar's rows say it for a while.
    pub client_key: Option<String>,
}

/// How long a new chat's rows say the key its client gave it: long past its answer.
const CLIENT_KEY_KEPT_MS: i64 = 10 * 60 * 1000;
/// How long a profile a turn ran into the allowance of is passed over when its allowance is not read again.
const SPENT_FOR_MS: i64 = 60 * 60 * 1000;

pub type ConfigFn = Arc<dyn Fn() -> Arc<Config> + Send + Sync>;
pub type ChatsFn = Arc<dyn Fn(&str) -> Option<Arc<dyn ChatSurface>> + Send + Sync>;
pub type HealthFn = Arc<dyn Fn(&str) -> ProfileHealth + Send + Sync>;

pub struct HubOptions {
    /// Read on every use, so edits apply to the next decision.
    pub config: ConfigFn,
    pub store: Arc<Store>,
    /// The connected connects by id; configured connects without one are offline.
    pub chats: ChatsFn,
    pub drivers: Vec<Arc<dyn AgentDriver>>,
    pub mcp_url: String,
    /// The station's own chat on its pages; sessions can be talked to there too.
    pub internal: Option<Arc<InternalChat>>,
    /// A session's page in still.fail (its /o/ link, which opens the app where there is one), when the station is in a
    /// workspace.
    pub link: Option<Box<dyn Fn(&str) -> Option<String> + Send + Sync>>,
}

pub struct Hub {
    config: ConfigFn,
    store: Arc<Store>,
    chats: ChatsFn,
    internal: Option<Arc<InternalChat>>,
    drivers: HashMap<RuntimeKind, Arc<dyn AgentDriver>>,
    mcp_url: String,
    link: Box<dyn Fn(&str) -> Option<String> + Send + Sync>,
    actors: Mutex<HashMap<String, Arc<SessionActor>>>,
    /// When each idle process is next looked at for eviction.
    deadlines: Mutex<HashMap<String, JoinHandle<()>>>,
    /// How profiles are doing, for the pool; the admin API knows their checks and allowances.
    health: Mutex<HealthFn>,
    picked: Mutex<HashMap<String, i64>>,
    /// Profiles a turn ran into the allowance of, and when: passed over until their allowance is read again, or for
    /// SPENT_FOR when it is not.
    spent: Mutex<HashMap<String, i64>>,
    /// What running turns are doing, for the pages' live view.
    pub live: Arc<LiveHub>,
    /// Why turns are held (SessionDeps::held): held while any reason stands.
    holds: Mutex<HashSet<Hold>>,
    /// Sessions taken up from the previous binary: their turns run on, not cut off.
    adopted: Mutex<HashSet<String>>,
    /// Chats made lately by session key: the key their client gave them, and when (NewChat::client_key).
    client_keys: Mutex<HashMap<String, (String, i64)>>,
    /// Titles agents gave chats someone has open, waiting until they leave (titles.rs), by thread.
    titles: Mutex<HashMap<i64, String>>,
    /// One message at a time per thread: Slack sends a mention twice (app_mention and message), and both would make its session.
    thread_gates: Mutex<HashMap<String, Arc<tokio::sync::Mutex<()>>>>,
    /// The station's background jobs (made after the hub, which tells their agents): what a session stopped while it
    /// waits ends (SessionDeps::stop_jobs).
    jobs: Mutex<Weak<crate::jobs::Jobs>>,
    me: Weak<Hub>,
}

/// Why turns are held. Each is taken back on its own: a station drained for a restart while in no workspace takes no
/// turns once the drain ends either.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Hold {
    /// A restart or handoff is coming (the station's drain, `hand_off`).
    Drain,
    /// The station is in no workspace (never joined one, or removed from it): it does no work until it is.
    Unbound,
}

/// What the hub hands over to the station's next binary: its drivers' shared processes, then its sessions.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, Default)]
pub struct HandedHub {
    #[serde(default)]
    pub drivers: HashMap<RuntimeKind, Value>,
    #[serde(default)]
    pub sessions: Vec<HandedSession>,
}

impl Hub {
    pub fn new(options: HubOptions) -> Arc<Hub> {
        let (store, config) = (options.store.clone(), options.config.clone());
        let locate = Arc::new(move |key: &str| {
            let row = store.get_session(key).ok().flatten()?;
            let config = config();
            let profile = config.profiles.iter().find(|p| p.id == row.profile)?;
            let runtime = runtime_named(&row.runtime)?;
            Some((runtime, transcript_path(runtime, &profile.home, row.runtime_session_id.as_deref()?)?))
        });
        let store = options.store.clone();
        let posts = Arc::new(move |key: &str| post_entries(&store.posts_by(key).unwrap_or_default()));
        Arc::new_cyclic(|me| Hub {
            config: options.config,
            store: options.store,
            chats: options.chats,
            internal: options.internal,
            drivers: options.drivers.into_iter().map(|d| (d.runtime(), d)).collect(),
            mcp_url: options.mcp_url,
            link: options.link.unwrap_or_else(|| Box::new(|_| None)),
            actors: Mutex::default(),
            deadlines: Mutex::default(),
            health: Mutex::new(Arc::new(|_| ProfileHealth::default())),
            picked: Mutex::default(),
            spent: Mutex::default(),
            live: LiveHub::new(locate, posts),
            holds: Mutex::default(),
            adopted: Mutex::default(),
            client_keys: Mutex::default(),
            titles: Mutex::default(),
            thread_gates: Mutex::default(),
            jobs: Mutex::new(Weak::new()),
            me: me.clone(),
        })
    }

    /// Holds turns for `reason`: none starts from now on, and messages stay pending. Those running go on.
    pub fn hold(&self, reason: Hold) {
        self.holds.lock().unwrap().insert(reason);
    }

    /// Takes back `reason` to hold turns; once none is left, turns start again and what waited meanwhile goes on.
    pub fn release(&self, reason: Hold) {
        {
            let mut holds = self.holds.lock().unwrap();
            if !holds.remove(&reason) || !holds.is_empty() {
                return;
            }
        }
        let actors: Vec<Arc<SessionActor>> = self.actors.lock().unwrap().values().cloned().collect();
        for actor in actors {
            drop(actor.release());
        }
        for key in self.store.sessions_with_pending().unwrap_or_default() {
            if let Ok(Some(row)) = self.store.get_session(&key) {
                if let Ok(actor) = self.actor(&row) {
                    drop(actor.kick());
                }
            }
        }
    }

    /// Whether turns are held for `reason`.
    pub fn holds(&self, reason: Hold) -> bool {
        self.holds.lock().unwrap().contains(&reason)
    }

    /// The station left its workspace (turns are held first): every runtime process ends, running or idle, then what the
    /// drivers run themselves (codex's app-servers), so no agent goes on outside the workspace. Interrupting turns was
    /// not enough: input a runtime had queued still ran after the interrupt, and posted. Turns cut off stay marked
    /// running and messages given to them pending again (SessionActor::suspend): `recover` resumes them once the
    /// station is back in its workspace.
    pub async fn suspend_all(&self) {
        for (_, deadline) in self.deadlines.lock().unwrap().drain() {
            deadline.abort();
        }
        // Taken up from the previous binary or not, what was cut off now resumes the usual way.
        self.adopted.lock().unwrap().clear();
        let actors: Vec<Arc<SessionActor>> = self.actors.lock().unwrap().values().cloned().collect();
        futures_util::future::join_all(actors.iter().map(|a| a.suspend())).await;
        futures_util::future::join_all(self.drivers.values().map(|d| d.shutdown())).await;
    }

    /// Whether any turn is running.
    pub fn any_running(&self) -> bool {
        self.running() > 0
    }

    /// How many turns are running.
    pub fn running(&self) -> usize {
        let actors: Vec<Arc<SessionActor>> = self.actors.lock().unwrap().values().cloned().collect();
        actors.iter().filter(|a| a.process_state() == "running").count()
    }

    /// Resolves once no actor has a task queued or running (and has stayed so a moment: a runtime's last events may
    /// still be on their way into the queues), or fails after `limit`.
    async fn settle(&self, limit: Duration) -> Result<()> {
        let until = std::time::Instant::now() + limit;
        let mut quiet = 0;
        while quiet < 3 {
            let actors: Vec<Arc<SessionActor>> = self.actors.lock().unwrap().values().cloned().collect();
            quiet = if actors.iter().all(|a| a.settled()) { quiet + 1 } else { 0 };
            if std::time::Instant::now() > until {
                bail!("sessions did not settle within {} s", limit.as_secs());
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        Ok(())
    }

    /// Gives up the drivers' processes and the sessions to the station's next binary. Turns are held first; until the
    /// runtimes' readers stop it can still fail and be released, after that it cannot (what could not be handed over
    /// ends with this binary, and the next resumes it the usual way).
    pub async fn hand_off(&self) -> Result<HandedHub> {
        self.hold(Hold::Drain);
        if let Err(e) = self.settle(Duration::from_secs(30)).await {
            self.release(Hold::Drain);
            return Err(e);
        }
        let mut handed = HandedHub::default();
        // Shared processes first (codex's app-servers wait out replies owed, and can still refuse)...
        let mut drivers: Vec<(RuntimeKind, Arc<dyn AgentDriver>)> = self.drivers.iter().map(|(k, d)| (*k, d.clone())).collect();
        drivers.sort_by_key(|(k, _)| crate::config::runtime_name(*k));
        for (runtime, driver) in &drivers {
            match driver.hand_off().await {
                Ok(state) => {
                    handed.drivers.insert(*runtime, state);
                }
                Err(e) if handed.drivers.values().all(Value::is_null) => {
                    self.release(Hold::Drain);
                    return Err(e.context(format!("{} would not hand over", crate::config::runtime_name(*runtime))));
                }
                Err(e) => warn!(error = %e, "a driver could not hand over"),
            }
        }
        // ...then each session's runtime session, and, once the events they said last are taken in, the actors.
        let actors: Vec<Arc<SessionActor>> = self.actors.lock().unwrap().values().cloned().collect();
        let mut agents = vec![];
        for actor in &actors {
            match actor.hand_off_agent().await {
                Some(agent) => agents.push((actor.clone(), agent)),
                // No runtime session, but notices or a wait: those go along.
                None if actor.holds_state() => agents.push((actor.clone(), Value::Null)),
                None => {}
            }
        }
        if let Err(e) = self.settle(Duration::from_secs(10)).await {
            warn!(error = %e, "handing over with sessions unsettled");
        }
        for (actor, agent) in agents {
            handed.sessions.push(actor.snapshot(agent));
        }
        info!(sessions = handed.sessions.len(), "handed over");
        Ok(handed)
    }

    /// Takes up what the previous binary handed over: the drivers' processes, then the sessions on them.
    pub async fn adopt(&self, handed: HandedHub) {
        for (runtime, state) in &handed.drivers {
            if let Some(driver) = self.drivers.get(runtime) {
                if let Err(e) = driver.adopt(state).await {
                    warn!(runtime = crate::config::runtime_name(*runtime), error = %e, "a driver's processes could not be taken up");
                }
            }
        }
        for session in handed.sessions {
            let key = session.key.clone();
            let taken = async {
                let row = self.store.get_session(&key)?.ok_or_else(|| anyhow!("session {key} is gone"))?;
                let agent = if session.agent.is_null() {
                    None
                } else {
                    let driver = self.driver(session.runtime)?;
                    let (events, received) = tokio::sync::mpsc::unbounded_channel();
                    Some((driver.adopt_session(&session.agent, events).await?, received))
                };
                let actor = self.actor(&row)?;
                let (running, with_agent) = (session.turn.is_some(), agent.is_some());
                let notices = !session.notices.is_empty();
                actor.adopt(session, agent);
                if notices {
                    drop(actor.release());
                }
                Ok::<_, anyhow::Error>((running, with_agent))
            };
            match taken.await {
                Ok((running, with_agent)) => {
                    info!(session = key, with_agent, "session taken up from the previous binary");
                    // Without its runtime session, a turn it had is resumed the usual way (Hub::recover).
                    if with_agent {
                        self.adopted.lock().unwrap().insert(key.clone());
                        if !running {
                            self.idle_now(&key);
                        }
                    }
                }
                Err(e) => warn!(session = key, error = %e, "session handed over could not be taken up; it resumes the usual way"),
            }
        }
    }

    fn config(&self) -> Arc<Config> {
        (self.config)()
    }

    pub fn repos_dir(&self) -> PathBuf {
        self.config().data_dir.join("repos")
    }

    /// Takes one event from a connect's platform. Resolves once it is durably recorded (or deliberately ignored).
    pub async fn receive(&self, connect_id: &str, event: ChatEvent) -> Result<()> {
        match event {
            ChatEvent::Message(message) => self.accept(connect_id, message).await,
            ChatEvent::Changed { channel, thread_ts, ts, text } => {
                self.store.edit_message(&self.surface(connect_id), &channel, &thread_ts, &ts, &text)?;
                Ok(())
            }
        }
    }

    /// Accepts one message seen by a connect. Resolves once it is durably recorded (or deliberately ignored).
    pub async fn accept(&self, connect_id: &str, message: InboundMessage) -> Result<()> {
        let at = format!("{}\0{}\0{}", self.surface(connect_id), message.channel, message.thread_ts);
        let gate = self.thread_gates.lock().unwrap().entry(at.clone()).or_default().clone();
        let accepted = {
            let _turn = gate.lock().await;
            self.accept_in_turn(connect_id, message).await
        };
        let mut gates = self.thread_gates.lock().unwrap();
        // Only the map and this call hold it: no one waits on it.
        if Arc::strong_count(&gate) == 2 {
            gates.remove(&at);
        }
        accepted
    }

    async fn accept_in_turn(&self, connect_id: &str, message: InboundMessage) -> Result<()> {
        let config = self.config();
        // What a bot of this station posted is its agent's, recorded and handed to the thread as it was posted: Slack's
        // copy of it, seen through another connect, is not a message of its own.
        if self.own_bot(&config, &message.user) {
            return Ok(());
        }
        let connect = connect_of(&config, connect_id)?;
        let chat = self.chat(connect_id)?;
        let surface = self.surface(connect_id);
        let single = connect.mode == ConnectMode::SingleSession;
        let bound = if single { self.store.binding(&connect.id)? } else { None };
        let key = match bound {
            Some(key) => key,
            None if single => new_single_session_key(&connect.id),
            None => session_key(&connect.id, &message.channel, &message.thread_ts),
        };
        let existing = self.store.thread_at(&surface, &message.channel, &message.thread_ts)?;
        let members = match &existing {
            Some(thread) => self.store.thread_sessions(thread.id)?,
            None => vec![],
        };
        let exists = self.store.get_session(&key)?.is_some();
        let wanted = if single {
            message.addressed || !connect.require_mention || (exists && members.iter().any(|m| m.session == key))
        } else {
            exists || message.addressed
        };
        // Chatter this connect is not part of, in a thread no session takes part in.
        if !wanted && members.is_empty() {
            return Ok(());
        }
        let here = ThreadRef::new(&message.channel, &message.thread_ts);
        let created_by = format!("slack:{}:{}", connect.id, message.user);
        if wanted && !exists {
            let scope = if single { SessionScope::All } else { SessionScope::Thread };
            let created = self.create_session(&config, &key, connect, scope, Some(&message), None, Some(&created_by)).and_then(|()| {
                if single {
                    self.store.set_binding(&connect.id, Some(&key))?;
                }
                Ok(())
            });
            if let Err(e) = created {
                error!(session = key, error = %e, "cannot create session");
                chat.post(&here, &format!("⚠️ 无法创建会话：{e}"), &[]).await?;
                return Ok(());
            }
            // As the broker did: a new session says first where it can be followed. Once, as it starts; not waited for.
            // In Slack's own link form: what the station posts is sent as written (the agents write mrkdwn themselves).
            if let Some(link) = (!single).then(|| (self.link)(&key)).flatten() {
                let (chat, here, key) = (chat.clone(), here.clone(), key.clone());
                tokio::spawn(async move {
                    if let Err(e) = chat.post(&here, &format!("<{link}|在 still.fail 里查看这个会话>"), &[]).await {
                        warn!(session = key, error = %e, "session link not posted");
                    }
                });
            }
        }
        let thread = match existing {
            Some(thread) => thread,
            None => self.open_slack_thread(&chat, &surface, &message, &created_by).await?,
        };
        if wanted {
            self.store.join_thread(thread.id, &key, &connect.id)?;
        }
        let (n, fresh) = self.store.insert_message(NewMessage::new(thread.id, &message.ts, AuthorKind::Person, &message.user, &message.text))?;
        // A message seen by a second connect is already delivered to the thread; only a session it brings in lacks it.
        let targets = if fresh {
            self.store.thread_sessions(thread.id)?.into_iter().map(|m| m.session).collect()
        } else if wanted {
            vec![key]
        } else {
            vec![]
        };
        self.hand_over(thread.id, n, &targets, &message.text)
    }

    /// A Slack thread the station starts following. When that happens mid-thread, what was said before is recorded
    /// first (without deliveries), so the thread on the pages and chat_history are complete and the log keeps Slack's
    /// order.
    async fn open_slack_thread(&self, chat: &Arc<dyn ChatSurface>, surface: &str, message: &InboundMessage, created_by: &str) -> Result<ThreadRow> {
        let mut earlier = vec![];
        if message.ts != message.thread_ts {
            match chat.history(&ThreadRef::new(&message.channel, &message.thread_ts), &message.ts, 200).await {
                Some(Ok(messages)) => earlier = messages,
                Some(Err(e)) => {
                    warn!(channel = message.channel, thread_ts = message.thread_ts, error = %e, "cannot read what the thread said before; continuing without it")
                }
                None => {}
            }
        }
        // Asked before the thread exists, so a connect seeing the same message meanwhile cannot record it ahead of these.
        let thread = self.store.open_thread(surface, &message.channel, &message.thread_ts, None, Some(created_by))?;
        for m in earlier {
            self.store.insert_message(NewMessage::new(thread.id, &m.ts, AuthorKind::Person, &m.user, &m.text))?;
        }
        Ok(thread)
    }

    /// Gives sessions a message they have not had: each runs it, or stops for `-stop`.
    fn hand_over(&self, thread: i64, n: i64, sessions: &[String], text: &str) -> Result<()> {
        for key in self.store.deliver(thread, n, sessions)? {
            self.store.touch(&key)?;
            let Some(row) = self.store.get_session(&key)? else { continue };
            let actor = self.actor(&row)?;
            if is_stop_command(text) {
                self.store.mark_delivered(&key, &[(thread, n)])?;
                drop(actor.stop());
            } else {
                drop(actor.kick());
            }
        }
        Ok(())
    }

    /// After a restart: resume cut-off turns, then deliver whatever is still pending.
    pub fn recover(&self) -> Result<()> {
        let adopted = self.adopted.lock().unwrap().clone();
        for row in self.store.list_sessions()?.into_iter().filter(|s| s.running) {
            // Taken up from the previous binary: its turn runs on.
            if adopted.contains(&row.key) {
                continue;
            }
            if !self.online(&row) {
                continue;
            }
            info!(session = row.key, "recovering a turn cut off by restart");
            drop(self.actor(&row)?.recover());
        }
        for key in self.store.sessions_with_pending()? {
            if let Some(row) = self.store.get_session(&key)?.filter(|row| self.online(row)) {
                drop(self.actor(&row)?.kick());
            }
        }
        Ok(())
    }

    /// Ends idle claude processes beyond the warm limit, oldest first, once they have idled past warm_ms. Codex threads
    /// share a process and stay. Runs when a process goes idle (the count grew) and at each idle process's deadline (one
    /// may have become old enough).
    fn evict_idle(&self) {
        let config = self.config();
        let now = now_ms();
        let actors: Vec<Arc<SessionActor>> = self.actors.lock().unwrap().values().cloned().collect();
        let mut idle: Vec<(Arc<SessionActor>, i64)> =
            actors.into_iter().filter(|a| a.runtime == RuntimeKind::Claude).filter_map(|a| a.idle_ms(now).map(|ms| (a, ms))).collect();
        idle.sort_by(|a, b| b.1.cmp(&a.1));
        let mut excess = idle.len() as i64 - config.max_warm_claude as i64;
        for (actor, ms) in idle {
            if excess <= 0 || ms < config.warm_ms as i64 {
                break;
            }
            drop(actor.evict());
            excess -= 1;
        }
    }

    /// A process went idle: look again when it has idled past warm_ms.
    fn idle_now(&self, key: &str) {
        let warm = Duration::from_millis(self.config().warm_ms);
        let me = self.me.clone();
        let deadline_key = key.to_string();
        let deadline = tokio::spawn(async move {
            tokio::time::sleep(warm).await;
            if let Some(hub) = me.upgrade() {
                hub.deadlines.lock().unwrap().remove(&deadline_key);
                hub.evict_idle();
            }
        });
        if let Some(old) = self.deadlines.lock().unwrap().insert(key.to_string(), deadline) {
            old.abort();
        }
        self.evict_idle();
    }

    /// Points a single-session connect at a session: an existing one (any session on the same runtime, whichever
    /// connect started it) or, with None, a new empty one. Returns the bound session's key.
    pub fn bind_single(&self, connect_id: &str, target: Option<&str>, title: Option<&str>, created_by: Option<&str>) -> Result<String> {
        let config = self.config();
        let connect = connect_of(&config, connect_id)?;
        if connect.mode != ConnectMode::SingleSession {
            bail!("connect {connect_id} is not single-session");
        }
        let Some(target) = target else {
            let key = new_single_session_key(&connect.id);
            let title = title.map(str::trim).filter(|t| !t.is_empty());
            self.create_session(&config, &key, connect, SessionScope::All, None, title, created_by)?;
            self.store.set_binding(&connect.id, Some(&key))?;
            return Ok(key);
        };
        let row = self.store.get_session(target)?.ok_or_else(|| anyhow!("unknown session {target}"))?;
        let runs = crate::config::runtime_name(connect.bind.runtime);
        if row.runtime != runs {
            bail!("session {target} runs {}, the connect runs {runs}", row.runtime);
        }
        self.store.set_binding(&connect.id, Some(target))?;
        info!(connect = connect.id, session = target, "single-session connect rebound");
        Ok(target.to_string())
    }

    /// Opens a chat on the station's pages with a session in it. More sessions can join it later (see add_to_thread).
    pub fn open_chat(&self, session: &str, created_by: &str, title: Option<&str>) -> Result<ThreadRow> {
        if self.internal.is_none() {
            bail!("still.fail chat is not available");
        }
        let Some(row) = self.store.get_session(session)? else {
            bail!("unknown session {session}");
        };
        // The first chat made with a session is its own; later ones are chats of their own (ThreadRow::home).
        let home = if self.store.home_chat(session)?.is_some() { None } else { Some(session) };
        // Its own chat keeps the name the session was given before it had one.
        let title = title.or(home.and(row.title.as_deref()));
        let thread = self.store.open_thread_of(STILLFAIL_SURFACE, INTERNAL_CHANNEL, &next_ts(), title, Some(created_by), home)?;
        self.store.join_thread(thread.id, session, INTERNAL_CONNECT)?;
        Ok(thread)
    }

    /// Brings another session into a chat on the station's pages; it hears what is said from then on.
    pub fn add_to_thread(&self, thread: i64, session: &str) -> Result<()> {
        self.stillfail_chat(thread)?;
        if self.store.get_session(session)?.is_none() {
            bail!("unknown session {session}");
        }
        self.store.join_thread(thread, session, INTERNAL_CONNECT)?;
        Ok(())
    }

    fn stillfail_chat(&self, thread: i64) -> Result<ThreadRow> {
        self.store.get_thread(thread)?.filter(|t| t.surface == STILLFAIL_SURFACE).ok_or_else(|| anyhow!("no still.fail chat {thread}"))
    }

    /// A person's message in a chat on the station's pages: recorded with its quotes and files and delivered to every
    /// session in the chat, like a Slack message. `client`: the app it was sent from, as it said. Returns its entry number.
    pub fn say(&self, thread: i64, user: &str, text: &str, attachments: Vec<Attachment>, quotes: Vec<Quote>, client: Option<String>) -> Result<i64> {
        self.stillfail_chat(thread)?;
        let message = NewMessage { attachments, quotes, client, ..NewMessage::new(thread, &next_ts(), AuthorKind::Person, user, text) };
        let (n, _) = self.store.insert_message(message)?;
        let sessions: Vec<String> = self.store.thread_sessions(thread)?.into_iter().map(|m| m.session).collect();
        self.hand_over(thread, n, &sessions, text)?;
        Ok(n)
    }

    /// Hides a session from lists, or shows it again, by hand (see archive_by).
    pub fn archive(&self, key: &str, archived: bool) -> Result<()> {
        self.archive_by(key, archived, MANUAL)
    }

    /// Hides a session from lists, or shows it again (see Store::set_archived); `by` is MANUAL or AUTO. Archiving also
    /// keeps a copy of its transcript, written like an archived thread (the runtime's own file in the profile's home
    /// stays as it is), ends its process if idle, and then cleans what can be made again from its directory
    /// (clean_rebuildable).
    pub fn archive_by(&self, key: &str, archived: bool, by: &str) -> Result<()> {
        let row = self.store.get_session(key)?.ok_or_else(|| anyhow!("unknown session {key}"))?;
        self.store.set_archived(key, archived, by)?;
        let copy = self.transcript_copy(key);
        if !archived {
            let _ = std::fs::remove_file(&copy);
            return Ok(());
        }
        let actor = self.actors.lock().unwrap().get(key).cloned();
        if let (Some(hub), Ok(runtime)) = (self.me.upgrade(), tokio::runtime::Handle::try_current()) {
            let key = key.to_string();
            runtime.spawn(async move {
                if let Some(actor) = actor {
                    actor.evict().await;
                }
                let _ = tokio::task::spawn_blocking(move || hub.clean_rebuildable(&key)).await;
            });
        }
        let config = self.config();
        let profile = config.profiles.iter().find(|p| p.id == row.profile);
        let path = match (runtime_named(&row.runtime), &row.runtime_session_id, profile) {
            (Some(runtime), Some(id), Some(profile)) => transcript_path(runtime, &profile.home, id),
            _ => None,
        };
        if let Some(path) = path.filter(|p| p.exists()) {
            write_compressed(&copy, &std::fs::read_to_string(path)?)?;
        }
        Ok(())
    }

    /// Removes what a build or an install makes again (node_modules, a Cargo target, …; footprint::rebuildable) from an
    /// archived session's own directory: it may come back, and is built again then. Left as it is while the session is
    /// back in the lists or at work, and while another session in the lists has the same directory. Answers the bytes
    /// freed; the footprint page sees it at its next scan.
    pub fn clean_rebuildable(&self, key: &str) -> u64 {
        let Ok(Some(row)) = self.store.get_session(key) else { return 0 };
        let Some(dir) = crate::footprint::room_of(&self.config().data_dir, &row.workspace) else { return 0 };
        if row.archived_at.is_none() || row.running || self.process_state(key) == "running" {
            return 0;
        }
        let shared = self.store.list_sessions().unwrap_or_default().into_iter().any(|s| {
            s.key != key && s.archived_at.is_none() && crate::footprint::room_of(&self.config().data_dir, &s.workspace).as_ref() == Some(&dir)
        });
        if shared {
            return 0;
        }
        let mut freed = 0;
        for (path, bytes) in crate::footprint::measure_room(&dir).rebuild {
            match std::fs::remove_dir_all(&path) {
                Ok(()) => freed += bytes,
                Err(e) => warn!(path = %path.display(), error = %e, "not removed"),
            }
        }
        if freed > 0 {
            info!(session = key, freed, "rebuildable files of an archived session cleaned");
        }
        freed
    }

    /// Archives a chat on the pages, or shows it again: a session's own chat goes with its session; a chat of its own
    /// goes alone, its sessions staying as they are.
    pub fn archive_chat(&self, thread: i64, archived: bool) -> Result<()> {
        let chat = self.stillfail_chat(thread)?;
        match chat.home {
            Some(home) => self.archive(&home, archived),
            None => self.store.set_thread_hidden(thread, archived, MANUAL),
        }
    }

    /// Archives what has idled past auto_archive_ms (counted from its last activity, or from being shown again by hand)
    /// and is done: nothing running or waiting to be heard, no background job or service of its own still up (a watch
    /// above all), not stopped at a block for someone, nothing its chat's starter has not read, and no single-session
    /// connect feeding it. Anything new said brings it back
    /// (Store::bring_back).
    pub fn auto_archive(&self, now: i64) -> Result<()> {
        let after = self.config().auto_archive_ms as i64;
        if after <= 0 {
            return Ok(());
        }
        let idle = |at: &[Option<i64>]| now - at.iter().flatten().copied().max().unwrap_or(0) >= after;
        let unread = |t: &ThreadRow| -> Result<bool> {
            Ok(match (&t.created_by, t.surface == STILLFAIL_SURFACE) {
                (Some(starter), true) => self.store.unread_count(starter, t.id)? > 0,
                _ => false,
            })
        };
        let bound = self.store.list_bindings()?;
        let stats = self.store.session_stats(None)?;
        let jobs: HashSet<String> = self.store.list_jobs(None)?.into_iter()
            .filter(|j| j.state == "running" || (j.port.is_some() && j.state == "exited"))
            .map(|j| j.session_key)
            .collect();
        let busy = |key: &str| -> Result<bool> {
            let Some(row) = self.store.get_session(key)? else { return Ok(true) };
            let stat = stats.get(key);
            let last = stat.and_then(|s| s.last_turn.as_ref());
            Ok(row.running
                || jobs.contains(key)
                || self.process_state(key) == "running"
                || stat.is_some_and(|s| s.pending > 0)
                || last.is_some_and(|t| t.declared.as_deref() == Some("block") || t.ended_at.is_none()))
        };
        // A chat someone pinned stays in the lists until put away by hand.
        let pinned = self.store.pinned_sessions()?;
        for s in self.store.list_sessions()? {
            if s.archived_at.is_some() || !idle(&[Some(s.last_active_at), s.shown_at]) || bound.contains_key(&s.key) || pinned.contains(&s.key) || busy(&s.key)? {
                continue;
            }
            let mut unheard = false;
            for t in self.store.session_threads(&s.key)? {
                unheard |= unread(&t.thread)?;
            }
            if unheard {
                continue;
            }
            info!(session = s.key, "archiving an idle session");
            self.archive_by(&s.key, true, AUTO)?;
        }
        for t in self.store.chats_of_their_own()? {
            let said = self.store.last_message(t.id)?.map(|m| m.created_at);
            if !idle(&[Some(t.created_at), said, t.shown_at]) || unread(&t)? {
                continue;
            }
            let mut working = false;
            for m in self.store.thread_sessions(t.id)? {
                working |= pinned.contains(&m.session) || busy(&m.session)?;
            }
            if working {
                continue;
            }
            info!(thread = t.id, "archiving an idle chat");
            self.store.set_thread_hidden(t.id, true, AUTO)?;
        }
        Ok(())
    }

    /// Where an archived session's transcript copy is.
    fn transcript_copy(&self, key: &str) -> PathBuf {
        self.store.archive_dir().join("transcripts").join(format!("{key}.jsonl.zst"))
    }

    /// Deletes a session: its process ends, its rows go (see Store::delete_session) and its workspace directory and
    /// transcript copy with them. The runtime's transcript stays in the profile's home, which may be a person's own.
    pub async fn delete_session(&self, key: &str) -> Result<()> {
        let row = self.store.get_session(key)?.ok_or_else(|| anyhow!("unknown session {key}"))?;
        let actor = self.actors.lock().unwrap().remove(key);
        if let Some(deadline) = self.deadlines.lock().unwrap().remove(key) {
            deadline.abort();
        }
        if let Some(actor) = actor {
            actor.dispose().await;
        }
        self.live.forget(key);
        self.store.delete_session(key)?;
        let _ = std::fs::remove_file(self.transcript_copy(key));
        // Sessions made by the station keep their workspace in a directory of their own.
        let workspace = Path::new(&row.workspace);
        let own = workspace.file_name().is_some_and(|n| n == "workspace") && workspace.starts_with(self.config().data_dir.join("sessions"));
        let home = if own { workspace.parent().unwrap_or(workspace) } else { workspace };
        let _ = std::fs::remove_dir_all(home);
        info!(session = key, "session deleted");
        Ok(())
    }

    /// Live process state of a session, for the pages.
    pub fn process_state(&self, key: &str) -> &'static str {
        self.actors.lock().unwrap().get(key).map(|a| a.process_state()).unwrap_or("cold")
    }

    /// The station's background jobs, once they are made.
    pub fn set_jobs(&self, jobs: &Arc<crate::jobs::Jobs>) {
        *self.jobs.lock().unwrap() = Arc::downgrade(jobs);
    }

    /// Interrupts the session's running turn, or what it waits on, as `-stop` in a thread would.
    pub async fn stop(&self, key: &str) -> Result<()> {
        let row = self.store.get_session(key)?.ok_or_else(|| anyhow!("unknown session {key}"))?;
        self.actor(&row)?.stop().await;
        Ok(())
    }

    /// Changes how a session runs from its next turn on: another profile of its runtime (another account, say), another
    /// model it can run, another effort. Its transcript is shared by the runtime's profiles, so the next message resumes
    /// it with all it had; its idle process ends first so the change takes. Not while a turn runs. Another model starts
    /// over what went with the old one: its effort back to the runtime's default, its profile back to the station's
    /// choice (picked here, among those with the model enabled), unless given with it.
    pub async fn configure(&self, key: &str, change: SessionChange) -> Result<()> {
        let row = self.store.get_session(key)?.ok_or_else(|| anyhow!("unknown session {key}"))?;
        let runtime = runtime_named(&row.runtime).ok_or_else(|| anyhow!("session {key} runs an unknown runtime {}", row.runtime))?;
        let runtime_name = if runtime == RuntimeKind::Claude { "Claude Code" } else { "Codex" };
        let config = self.config();
        let nonempty = |v: Option<String>| v.filter(|s| !s.is_empty());
        // A profile given keeps the session to it; None gives the choice back to the station.
        let wanted_profile = change.profile.map(nonempty);
        let new_model = change.model.map(nonempty);
        let new_effort = change.effort.map(nonempty);
        if let Some(Some(id)) = &wanted_profile {
            let next = config.profiles.iter().find(|p| &p.id == id).ok_or_else(|| anyhow!("unknown profile {id}"))?;
            if !next.runtimes.contains(&runtime) {
                bail!("「{}」不能跑 {runtime_name}", next.name);
            }
            let runs = new_model.clone().unwrap_or_else(|| row.model.clone());
            if let Some(runs) = runs.filter(|m| !next.runs(m)) {
                bail!("「{}」没有启用 {runs}：换一个模型，或先在它的 Profile 里启用", next.name);
            }
        }
        let model = new_model.clone().unwrap_or_else(|| row.model.clone());
        // Another spelling of its model is its model.
        let remodel = match (&model, &row.model) {
            (Some(a), Some(b)) => !stillfail_shapes::model::same(a, b),
            (a, b) => a != b,
        };
        let model = if remodel { model } else { row.model.clone() };
        let effort = match &new_effort {
            Some(effort) => effort.clone(),
            None if remodel => None,
            None => row.effort.clone(),
        };
        // What changes is checked; what stays is as it was.
        if let (Some(Some(_)), Some(model)) = (&new_model, &model) {
            if !config.profiles.iter().any(|p| p.runtimes.contains(&runtime) && p.runs(model)) {
                bail!("没有能跑 {model} 的 {runtime_name} Profile：先在一个 Profile 上启用它");
            }
        }
        if let Some(effort) = effort.as_ref().filter(|_| new_effort.is_some() || wanted_profile.is_some() || remodel) {
            let pinned = wanted_profile.as_ref().map(|p| p.as_deref()).unwrap_or_else(|| (!remodel && row.profile_pinned).then_some(row.profile.as_str()));
            let allowed = self.model_efforts(runtime, model.as_deref(), pinned);
            if !allowed.contains(effort) {
                bail!("{runtime_name} 的思考深度只有 {}", allowed.join("、"));
            }
        }
        if self.process_state(key) == "running" {
            bail!("这个会话正在跑，等这一轮结束再改");
        }
        self.evict(key).await;
        let profile = match wanted_profile {
            Some(profile) => Some(profile),
            None if remodel => Some(None),
            None => None,
        };
        if let Some(profile) = &profile {
            self.store.set_session_profile(key, profile.as_deref().unwrap_or(&row.profile), profile.is_some())?;
        }
        if model != row.model || effort != row.effort {
            self.store.set_session_model(key, model.as_deref(), effort.as_deref())?;
        }
        if profile == Some(None) {
            self.run_on(key)?;
        }
        let now = self.store.get_session(key)?.map(|r| r.profile).unwrap_or_default();
        info!(session = key, profile = now, model = ?model, effort = ?effort, "session changed");
        // Its last turn stopped at the allowance: changed, it goes on by itself.
        let cut_short = self.store.last_turn(key)?.is_some_and(|t| t.outcome.as_deref() == Some("failed") && t.detail.as_deref().is_some_and(|d| d.starts_with("rate_limit")));
        if cut_short {
            drop(self.actor(&row)?.go_on());
        }
        Ok(())
    }

    /// The profile a session's runtime starts on: its own while usable (the account's cache is warm there), else the
    /// one the pool picks among those of its runtime (transcripts are shared, so it resumes with all it had there).
    pub fn run_on(&self, key: &str) -> Result<Profile> {
        let row = self.store.get_session(key)?.ok_or_else(|| anyhow!("unknown session {key}"))?;
        let runtime = runtime_named(&row.runtime).ok_or_else(|| anyhow!("session {key} runs an unknown runtime {}", row.runtime))?;
        let config = self.config();
        let candidates: Vec<&Profile> = config.profiles.iter().filter(|p| p.runtimes.contains(&runtime)).collect();
        // Kept to it by hand: that one, whatever it says. Otherwise its own while it can run it: usable, and with its
        // model enabled.
        if let Some(current) = candidates.iter().find(|p| p.id == row.profile) {
            if row.profile_pinned || (usable(&self.health_of(&current.id)) && serves(current, row.model.as_deref())) {
                return Ok((*current).clone());
            }
        }
        if candidates.is_empty() {
            bail!("session {key}: no profile runs {}", row.runtime);
        }
        let next = self.pick(&candidates, row.model.as_deref(), false)?;
        if next.id != row.profile {
            self.store.set_session_profile(key, &next.id, false)?;
            info!(session = key, from = row.profile, to = next.id, "session taken on by another profile");
        }
        Ok(next)
    }

    /// Ends the session's runtime process if it is idle; the conversation resumes on the next message.
    pub async fn evict(&self, key: &str) {
        let actor = self.actors.lock().unwrap().get(key).cloned();
        if let Some(actor) = actor {
            actor.evict().await;
        }
    }

    /// Copies files the agent attaches into the session's uploads, so the message keeps them even if the originals
    /// change, and measures images so pages can hold their place.
    fn attach(&self, key: &str, paths: &[String]) -> Result<Vec<Attachment>> {
        let row = self.store.get_session(key)?.ok_or_else(|| anyhow!("unknown session"))?;
        if paths.len() > 10 {
            bail!("at most 10 files per message");
        }
        let workspace = Path::new(&row.workspace);
        let dir = workspace.join("uploads");
        std::fs::create_dir_all(&dir)?;
        paths
            .iter()
            .map(|given| {
                let path = workspace.join(given);
                let meta = std::fs::metadata(&path).map_err(|_| anyhow!("no such file: {given}"))?;
                if !meta.is_file() {
                    bail!("not a file: {given}");
                }
                if meta.len() > 50 * 1024 * 1024 {
                    bail!("too large (over 50 MB): {given}");
                }
                let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
                let stamp: String = iso(now_ms())[..19].replace([':', '.'], "-");
                let safe: String = name.chars().map(|c| if c == '\\' || c == '/' || (c as u32) < 0x20 { '_' } else { c }).collect();
                let copy = dir.join(format!("{stamp}-{safe}"));
                std::fs::copy(&path, &copy)?;
                let lower = name.to_ascii_lowercase();
                let image = [".png", ".jpg", ".jpeg", ".gif", ".webp"].iter().any(|e| lower.ends_with(e));
                let size = if image { image_size(&copy) } else { None };
                Ok(Attachment {
                    name,
                    path: copy.to_string_lossy().into_owned(),
                    size: meta.len(),
                    width: size.map(|s| s.0),
                    height: size.map(|s| s.1),
                    thumbhash: None,
                })
            })
            .collect()
    }

    /// A session of its own, talked to in the station's chat: the runtime, model and effort chosen by whoever starts it
    /// rather than a connect's, and the profile: one given keeps it there; else the pool picks one with the model on.
    pub fn new_session(&self, options: NewChat) -> Result<(String, ThreadRow)> {
        let config = self.config();
        let runtime = crate::config::runtime_name(options.runtime);
        let profiles: Vec<&Profile> = config.profiles.iter().filter(|p| p.runtimes.contains(&options.runtime)).collect();
        if profiles.is_empty() {
            bail!("no {runtime} profile configured");
        }
        let model = options.model.as_deref().map(str::trim).filter(|m| !m.is_empty()).map(String::from);
        let profile = match &options.profile {
            Some(id) => profiles.iter().find(|p| &p.id == id).map(|p| (*p).clone()).ok_or_else(|| anyhow!("no {runtime} profile {id}"))?,
            None => self.pick(&profiles, model.as_deref(), true)?,
        };
        if let (Some(_), Some(model)) = (&options.profile, &model) {
            if !profile.runs(model) {
                bail!("「{}」没有启用 {model}", profile.name);
            }
        }
        let effort = options.effort.filter(|e| !e.is_empty());
        if let Some(effort) = &effort {
            let allowed = self.model_efforts(options.runtime, model.as_deref(), options.profile.as_deref());
            if !allowed.contains(effort) {
                bail!("effort must be one of {}", allowed.join(", "));
            }
        }
        let key = format!("{INTERNAL_CONNECT}:c-{}", hex::encode(random_bytes::<5>()));
        let workspace = config.data_dir.join("sessions").join(INTERNAL_CONNECT).join(&key[INTERNAL_CONNECT.len() + 1..]).join("workspace");
        std::fs::create_dir_all(&workspace)?;
        std::fs::create_dir_all(config.data_dir.join("repos"))?;
        let now = now_ms();
        // Known before its rows are (their events can reach the client before this answers), and for a while after.
        if let Some(client) = options.client_key.as_deref().map(str::trim).filter(|k| !k.is_empty()) {
            let mut keys = self.client_keys.lock().unwrap();
            keys.retain(|_, (_, at)| now - *at < CLIENT_KEY_KEPT_MS);
            keys.insert(key.clone(), (client.chars().take(120).collect(), now));
        }
        let title = options.title.as_deref().map(str::trim).filter(|t| !t.is_empty()).map(String::from);
        self.store.insert_session(&NewSession {
            key: key.clone(),
            connect: INTERNAL_CONNECT.into(),
            scope: Some(SessionScope::All),
            title: title.clone(),
            created_by: Some(options.created_by.clone()),
            runtime: runtime.into(),
            profile: profile.id.clone(),
            profile_pinned: options.profile.is_some(),
            model: model.clone().or_else(|| profile.model.clone()),
            effort,
            workspace: workspace.to_string_lossy().into_owned(),
            cwd: None,
            runtime_session_id: None,
            token: new_token(),
            created_at: now,
            last_active_at: now,
        })?;
        info!(session = key, connect = INTERNAL_CONNECT, runtime, profile = profile.id, model = ?model, "session created");
        let thread = self.open_chat(&key, &options.created_by, title.as_deref())?;
        Ok((key, thread))
    }

    /// The key the client that asked for a session gave it (NewChat::client_key), while it is kept.
    pub fn client_key(&self, key: &str) -> Option<String> {
        let keys = self.client_keys.lock().unwrap();
        keys.get(key).filter(|(_, at)| now_ms() - *at < CLIENT_KEY_KEPT_MS).map(|(client, _)| client.clone())
    }

    /// Goes on in a chat with a session the machine's own Claude Code or Codex kept (run in a terminal). Its transcript
    /// is copied into the shared transcripts (the original is left as it was, and can go on in the terminal on its own);
    /// the new session resumes it, running in the directory it ran in. The chat starts with a note of where it came from,
    /// linking to the session's execution history, which shows what was said before (it is not copied into the chat). A session already
    /// going on with it is that one's chat, brought back if archived.
    pub fn continue_machine_session(&self, roots: &MachineRoots, found: &MachineSession, created_by: &str) -> Result<(String, ThreadRow)> {
        let runtime = crate::config::runtime_name(found.runtime);
        if let Some(row) = self.store.list_sessions()?.into_iter().find(|r| r.runtime == runtime && r.runtime_session_id.as_deref() == Some(found.id.as_str())) {
            if let Some(thread) = self.store.home_chat(&row.key)? {
                if row.archived_at.is_some() {
                    self.archive(&row.key, false)?;
                }
                return Ok((row.key, thread));
            }
        }
        if !Path::new(&found.cwd).is_dir() {
            bail!("它原来的目录 {} 已经不在了", found.cwd);
        }
        let config = self.config();
        let profiles: Vec<&Profile> = config.profiles.iter().filter(|p| p.runtimes.contains(&found.runtime)).collect();
        if profiles.is_empty() {
            bail!("没有能跑 {} 的 Profile", if found.runtime == RuntimeKind::Claude { "Claude Code" } else { "Codex" });
        }
        // The model it ran, where a profile has it enabled; else the one picked runs its own.
        let kept = found.model.clone().filter(|m| profiles.iter().any(|p| p.models.contains(m)));
        let profile = self.pick(&profiles, kept.as_deref(), false)?;
        let model = kept.or_else(|| profile.model.clone()).or_else(|| profile.models.first().cloned());
        let copy = crate::machine_sessions::copy_transcript(roots, found, &config.data_dir.join("transcripts").join(runtime))?;
        // Where its execution history is when it comes here: its last entry, read as the history reads it (from the file
        // the profile's home finds).
        let read = transcript_path(found.runtime, &profile.home, &found.id).unwrap_or(copy);
        let mut tail = crate::transcript::TranscriptTail::new(found.runtime, read);
        tail.read();
        let last = tail.entries.len().checked_sub(1);
        let key = format!("{INTERNAL_CONNECT}:c-{}", hex::encode(random_bytes::<5>()));
        let workspace = config.data_dir.join("sessions").join(INTERNAL_CONNECT).join(&key[INTERNAL_CONNECT.len() + 1..]).join("workspace");
        std::fs::create_dir_all(&workspace)?;
        std::fs::create_dir_all(config.data_dir.join("repos"))?;
        let now = now_ms();
        let title: Option<String> = found.title.clone().or_else(|| found.first.clone()).map(|t| t.chars().take(80).collect());
        self.store.insert_session(&NewSession {
            key: key.clone(),
            connect: INTERNAL_CONNECT.into(),
            scope: Some(SessionScope::All),
            title: title.clone(),
            created_by: Some(created_by.into()),
            runtime: runtime.into(),
            profile: profile.id.clone(),
            profile_pinned: false,
            model,
            effort: None,
            workspace: workspace.to_string_lossy().into_owned(),
            cwd: Some(found.cwd.clone()),
            runtime_session_id: Some(found.id.clone()),
            token: new_token(),
            created_at: now,
            last_active_at: now,
        })?;
        info!(session = key, runtime, profile = profile.id, from = found.id, cwd = found.cwd, "session continued from the machine's own");
        let thread = self.open_chat(&key, created_by, title.as_deref())?;
        // What was said before stays in its transcript: the note links to the session's execution history, which shows it,
        // at where it was when it came here (the pages open `?history=<session>&entry=<n>` links there).
        let at = last.map(|n| format!("&entry={n}")).unwrap_or_default();
        let name = if found.runtime == RuntimeKind::Claude { "Claude Code" } else { "Codex" };
        let note = format!(
            "接着本机 {name} 在 {} 的会话 · [查看之前的对话](?history={key}{at})",
            found.cwd
        );
        self.store.insert_message(NewMessage::new(thread.id, &next_ts(), AuthorKind::StillFail, "ember", &note))?;
        self.store.set_read(created_by, thread.id, self.store.last_entry(thread.id)?)?;
        Ok((key, thread))
    }

    /// The same per-account capabilities sent to the clients. Automatic selection must work on every
    /// eligible account, including after quota failover; a pinned account may expose additional levels.
    pub fn model_efforts(&self, runtime: RuntimeKind, model: Option<&str>, pinned: Option<&str>) -> Vec<String> {
        let config = self.config();
        let name = crate::config::runtime_name(runtime);
        let profiles: Vec<_> = config.profiles.iter().filter(|p| p.runtimes.contains(&runtime))
            .filter(|p| pinned.is_none_or(|id| p.id == id))
            .filter(|p| model.is_none_or(|m| p.runs(m))).collect();
        stillfail_shapes::reasoning::common(profiles.into_iter().map(|p| {
            let health = self.health_of(&p.id);
            stillfail_shapes::reasoning::available(name, model.or(p.model.as_deref()), health.check.as_ref().and_then(|c| c.model_efforts.as_ref()))
        }), name)
    }

    /// Lets the pool see profiles' checks and allowances.
    pub fn set_profile_health(&self, health: HealthFn) {
        *self.health.lock().unwrap() = health;
    }

    fn health_of(&self, id: &str) -> ProfileHealth {
        let health = self.health.lock().unwrap().clone();
        let mut health = health(id);
        let mut spent = self.spent.lock().unwrap();
        if let Some(&at) = spent.get(id) {
            // Read again since: what it says now counts.
            if health.quota.as_ref().is_some_and(|q| q.checked_at > at) || now_ms() - at > SPENT_FOR_MS {
                spent.remove(id);
            } else {
                health.spent = true;
            }
        }
        health
    }

    /// A turn of the session ran into its profile's allowance: that profile is passed over for now, and a session left
    /// to the station moves to another of its runtime's that can run it now. Says the names of the one left and the one
    /// taken when it moved; not when it is kept to its profile or none other can.
    pub fn spend(&self, key: &str) -> Result<Option<(String, String)>> {
        let row = self.store.get_session(key)?.ok_or_else(|| anyhow!("unknown session {key}"))?;
        self.spent.lock().unwrap().insert(row.profile.clone(), now_ms());
        if row.profile_pinned {
            return Ok(None);
        }
        let Some(runtime) = runtime_named(&row.runtime) else { return Ok(None) };
        let config = self.config();
        // As the pool: those with its model enabled, or, when none has (a connect's binding from before models were
        // enabled), all of its runtime's.
        let runs: Vec<&Profile> = config.profiles.iter().filter(|p| p.runtimes.contains(&runtime)).collect();
        let strict = runs.iter().any(|p| serves(p, row.model.as_deref()));
        let candidates: Vec<&Profile> = runs
            .into_iter()
            .filter(|p| p.id != row.profile && (!strict || serves(p, row.model.as_deref())) && usable(&self.health_of(&p.id)))
            .collect();
        if candidates.is_empty() {
            return Ok(None);
        }
        let next = self.pick(&candidates, row.model.as_deref(), false)?;
        self.store.set_session_profile(key, &next.id, false)?;
        info!(session = key, from = row.profile, to = next.id, "allowance ran out; session taken on by another profile");
        let from = config.profiles.iter().find(|p| p.id == row.profile).map_or(row.profile.clone(), |p| p.name.clone());
        Ok(Some((from, next.name)))
    }

    /// Chooses the profile a new session runs on; see pool.rs.
    fn pick(&self, candidates: &[&Profile], model: Option<&str>, strict: bool) -> Result<Profile> {
        struct Signals<'a> {
            hub: &'a Hub,
            /// The profiles of sessions with a process.
            running: Vec<String>,
        }
        impl PoolSignals for Signals<'_> {
            fn health(&self, id: &str) -> ProfileHealth {
                self.hub.health_of(id)
            }
            fn load(&self, id: &str) -> usize {
                self.running.iter().filter(|p| *p == id).count()
            }
            fn last_picked(&self, id: &str) -> i64 {
                self.hub.picked.lock().unwrap().get(id).copied().unwrap_or(0)
            }
        }
        let actors: Vec<Arc<SessionActor>> = self.actors.lock().unwrap().values().cloned().collect();
        let running = actors
            .iter()
            .filter(|a| a.process_state() != "cold")
            .filter_map(|a| self.store.get_session(&a.key).ok().flatten().map(|row| row.profile))
            .collect();
        let profile = pick_profile(candidates, model, &Signals { hub: self, running }, strict)?.clone();
        self.picked.lock().unwrap().insert(profile.id.clone(), now_ms());
        Ok(profile)
    }

    /// A word from the station for a session's agent, outside any conversation (see SessionActor::notify).
    pub fn notify(&self, key: &str, text: String) -> Result<()> {
        let row = self.store.get_session(key)?.ok_or_else(|| anyhow!("unknown session {key}"))?;
        drop(self.actor(&row)?.notify(text));
        Ok(())
    }

    /// Starts a session's runtime ahead of a message; see SessionActor::warm.
    pub async fn warm(&self, key: &str) -> Result<()> {
        if let Some(row) = self.store.get_session(key)? {
            self.actor(&row)?.warm().await;
        }
        Ok(())
    }

    pub async fn shutdown(&self) {
        for (_, deadline) in self.deadlines.lock().unwrap().drain() {
            deadline.abort();
        }
        self.live.close();
        let actors: Vec<Arc<SessionActor>> = self.actors.lock().unwrap().values().cloned().collect();
        futures_util::future::join_all(actors.iter().map(|a| a.dispose())).await;
        futures_util::future::join_all(self.drivers.values().map(|d| d.shutdown())).await;
    }

    // ── the agents' tools ──────────────────────────────────────────────────

    pub fn tools(&self) -> Vec<Tool> {
        let me = self.me.clone();
        type Body = fn(Arc<Hub>, String, Map<String, Value>) -> BoxFuture<'static, Result<String>>;
        let run = move |body: Body| -> Run {
            let me = me.clone();
            Arc::new(move |key, args| match me.upgrade() {
                Some(hub) => body(hub, key, args),
                None => Box::pin(async { bail!("the station is shutting down") }),
            })
        };
        let to = json!({ "type": "string", "description": "CHANNEL/THREAD_TS: the thread attribute of the message you are answering." });
        vec![
            Tool {
                name: "chat_post".into(),
                description: "Post a message to one of your conversations: in Slack's formatting (mrkdwn) for a Slack thread, Markdown for a still.fail chat. In a still.fail chat a message that asks people something can carry a card for their answer: options to pick from, or a field to write in. A post that ends your turn says how with kind: all_done (nothing in the chat is left unfinished: done says why, with the evidence) or need_help (a person has to give, do or decide something: need says what; after posting a card, this is how the turn ends).".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "to": to.clone(),
                        "text": { "type": "string", "description": "The message, formatted for where it goes (posted as written). With a card: what it asks and the facts it turns on, so it can be answered from this message alone." },
                        "kind": { "type": "string", "enum": ["all_done", "need_help"], "description": "Omit for a progress update. all_done: the chat has nothing unfinished at all (no branch left unmerged, no open question, nothing waiting for a yes); give done. need_help: a person has to give, do or decide something, or answer an open question (a card you posted included); give need. (need_decision, from before cards, is still taken: options, the turn ends need_help.)" },
                        "need": { "type": "string", "description": "For need_help (required): what the person has to give, do or decide, in one sentence in the language people use there (e.g. 要 Stripe 的测试 key, 选统计口径); to verify something, where, how and what to look at; work of yours still running, after the ask (e.g. 选统计口径；CI 还在跑)." },
                        "about": { "type": "string", "description": "With kind, optional: the ts of the message in this conversation the state is about (all_done: the one with the result; need_help: the one that asks, by default the card still waiting there, this post's own when it carries one). People's lists jump to it." },
                        "done": { "type": "string", "description": "For all_done (required): why nothing in the chat is left, so people can trust it, in the language they use there: what was finished and where it landed or how it was confirmed, naming the evidence (a commit, a release, a person's confirmation, the answer given), e.g. 已合进 main 82f108a5，测试版 1389 已发，你确认过滑动可以. Not just 做完了 or done: that is refused." },
                        "files": { "type": "array", "items": { "type": "string" }, "description": "Absolute paths of files on this machine to attach (images show inline; in a Slack thread they are uploaded below the text). Shown below the text unless the text refers to one by its file name, as ![](shot.png) or [report](report.pdf), which places it there. Up to 10, 50 MB each." },
                        "title": { "type": "string", "description": "The conversation's name in still.fail lists (including Slack threads; does not rename anything in Slack): a few words on what it is about, in the language people use there (at most 30 characters). Give one with your first post that ends a turn in a chat. Give another only when the chat has moved to something else and the name no longer says what it is about, not to reword it; the station changes it rarely, and never over a name people gave." },
                        "card": {
                            "type": "object",
                            "description": "Still.fail chats only: what people answer this message with, shown with it and on their list of things waiting for them (奏). {\"type\": \"options\", \"options\": [...]} when they choose between answers you can name (1 to 6, recommend one if you can): shown under the message, a tap answers. {\"type\": \"text\", \"placeholder\": \"…\"} when they must write something (a value, a name, a key): a field on their 奏 page. Either way an answer reaches you as their message quoting this one, and anything they write in the chat instead answers it too. A card waits until a person writes in the chat or you post a newer one. It says nothing of your turn: end the turn need_help (with need) after posting one.",
                            "properties": {
                                "type": { "type": "string", "enum": ["options", "text"] },
                                "options": {
                                    "type": "array",
                                    "description": "For an options card (required): the answers (1 to 6).",
                                    "items": {
                                        "type": "object",
                                        "properties": {
                                            "label": { "type": "string", "description": "A short phrase that reads on its own, in the language people use there (e.g. 按今天累计, 先不改)." },
                                            "detail": { "type": "string", "description": "One line on what choosing it leads to." },
                                            "recommended": { "type": "boolean", "description": "The one you recommend (at most one)." },
                                        },
                                        "required": ["label"],
                                        "additionalProperties": false,
                                    },
                                },
                                "placeholder": { "type": "string", "description": "For a text card: a hint shown in the empty field (e.g. sk_test_…)." },
                            },
                            "required": ["type"],
                            "additionalProperties": false,
                        },
                        "options": {
                            "type": "array",
                            "description": "As said before cards: the same as card {\"type\": \"options\", \"options\": …}. Prefer card.",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "label": { "type": "string", "description": "A short phrase that reads on its own, in the language people use there (e.g. 按今天累计, 先不改)." },
                                    "detail": { "type": "string", "description": "One line on what choosing it leads to." },
                                    "recommended": { "type": "boolean", "description": "The one you recommend (at most one)." },
                                },
                                "required": ["label"],
                                "additionalProperties": false,
                            },
                        },
                    },
                    "required": ["to"],
                    "additionalProperties": false,
                }),
                run: run(|hub, key, args| Box::pin(async move { hub.chat_post(&key, &args).await })),
            },
            Tool {
                name: "slack_api".into(),
                description: "Call any Slack Web API method as your Slack bot, e.g. conversations.history, users.info, reactions.add, chat.update, conversations.open then chat.postMessage for a direct message. Writes in a thread another session takes part in are refused; posting in a thread nobody else is in, or a new message, makes that thread one of your conversations (its replies come to you). Prefer chat_post to answer the thread you are working in.".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "method": { "type": "string", "description": "The Web API method, e.g. \"conversations.replies\"." },
                        "params": { "type": "object", "description": "Its arguments as Slack documents them (blocks and other structures as JSON values).", "additionalProperties": true },
                        "to": { "type": "string", "description": "CHANNEL/THREAD_TS of one of your Slack conversations: whose bot to call as. Default: this session's own connect." },
                    },
                    "required": ["method"],
                    "additionalProperties": false,
                }),
                run: run(|hub, key, args| {
                    Box::pin(async move {
                        let method = args.get("method").map(js_string).unwrap_or_default().trim().to_string();
                        let params = args.get("params").and_then(Value::as_object).cloned().unwrap_or_default();
                        let via = match args.get("to") {
                            Some(Value::String(to)) if !to.is_empty() => Some(hub.target(&key, args.get("to"))?.connect),
                            _ => None,
                        };
                        hub.slack_api(&key, &method, params, via).await
                    })
                }),
            },
            Tool {
                name: "chat_state".into(),
                description: "Record how this turn ends without posting another message: all_done (nothing in the chat is left unfinished: done says why, with the evidence), need_help (a person has to give, do or decide something, a card you posted included: need says what) or waiting (only for work you started that brings you back on its own, such as CI, a build, a job: for says what; waiting on a person is need_help).".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "kind": { "type": "string", "enum": ["all_done", "need_help", "waiting"] },
                        "need": { "type": "string", "description": "For need_help (required): what the person has to give, do or decide, in one sentence in the language people use there (e.g. 要 Stripe 的测试 key, 选统计口径); to verify something, where, how and what to look at; work of yours still running, after the ask (e.g. 选统计口径；CI 还在跑)." },
                        "about": { "type": "string", "description": "Optional: the ts of the message in your conversation the state is about (all_done: the one with the result; need_help: the one that asks, by default the card still waiting; waiting: the one saying what you started). People's lists jump to it." },
                        "done": { "type": "string", "description": "For all_done (required): why nothing in the chat is left, so people can trust it, in the language they use there: what was finished and where it landed or how it was confirmed, naming the evidence (a commit, a release, a person's confirmation, the answer given), e.g. 已合进 main 82f108a5，测试版 1389 已发，你确认过滑动可以. Not just 做完了 or done: that is refused." },
                        "seconds": { "type": "integer", "minimum": MIN_WAIT_SECONDS, "maximum": MAX_WAIT_SECONDS, "description": "For waiting: your estimate of how long until the work brings you back. If nothing has by then, you are asked again (not while a watch of yours runs: job_start with watch)." },
                        "for": { "type": "string", "description": "For waiting (required): what you wait for, in a few words people read under your name, in the language they use there (e.g. 安卓滑动测试在模拟器上跑完)." },
                    },
                    "required": ["kind"],
                    "additionalProperties": false,
                }),
                run: run(|hub, key, args| {
                    Box::pin(async move {
                        // Checked whole before anything is recorded: its words (what it waits for, needs, ends with)
                        // and what it is about.
                        let (kind, words) = match args.get("kind") {
                            Some(Value::String(s)) if s == "waiting" => {
                                let seconds = args.get("seconds").and_then(js_number).ok_or_else(|| anyhow!("seconds is required for waiting: how long until the work brings you back"))?;
                                let what = args.get("for").map(js_string).map(|w| w.trim().to_string()).filter(|w| !w.is_empty())
                                    .ok_or_else(|| anyhow!("for is required for waiting: what you wait for, in a few words people read"))?;
                                (DeclaredState::Waiting((seconds.max(0.0) as u64).clamp(MIN_WAIT_SECONDS, MAX_WAIT_SECONDS)), Some(what))
                            }
                            kind => match state_arg(kind)? {
                                Some((_, Said::Decision)) => bail!("need_decision is posted with chat_post: the question in the text, its options in a card; then the turn ends need_help"),
                                Some((kind, said)) => (kind, need_arg(&args, kind, said)?),
                                None => bail!("kind is required"),
                            },
                        };
                        let about = hub.state_about(&key, kind, &args)?;
                        match (kind, &words) {
                            (DeclaredState::Waiting(_), Some(what)) => hub.wait_for(&key, what),
                            (_, Some(need)) => hub.need(&key, need),
                            _ => {}
                        }
                        hub.about(&key, about.as_ref().map(|(thread, n, ts)| (*thread, *n, ts.as_str())));
                        hub.declare(&key, kind);
                        Ok(match kind {
                            DeclaredState::Waiting(seconds) => format!("Recorded state waiting: you are asked again in {seconds} seconds unless something brings you back first."),
                            _ => format!("Recorded state {}.", kind.as_str()),
                        })
                    })
                }),
            },
            Tool {
                name: "chat_history".into(),
                description: "Read earlier messages of one of your conversations, oldest first, your own posts included.".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "to": to,
                        "before": { "type": "string", "description": "Only messages older than this message ts." },
                        "limit": { "type": "integer", "minimum": 1, "maximum": 200, "description": "Default 30." },
                    },
                    "required": ["to"],
                    "additionalProperties": false,
                }),
                run: run(|hub, key, args| Box::pin(async move { hub.chat_history(&key, &args).await })),
            },
            Tool {
                name: "chat_list".into(),
                description: "List the conversations on this station (still.fail chats and Slack threads), the latest first: each with its address, title, agents (session keys) and last message. Use it to find a chat people refer to.".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "query": { "type": "string", "description": "Only conversations whose title, last message or agents contain this (case-insensitive)." },
                        "limit": { "type": "integer", "minimum": 1, "maximum": 100, "description": "Default 20." },
                    },
                    "additionalProperties": false,
                }),
                run: run(|hub, key, args| Box::pin(async move { hub.chat_list(&key, &args) })),
            },
            Tool {
                name: "chat_read".into(),
                description: "Read the messages of any conversation on this station, not only your own, oldest first: the chat people refer to by its link.".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "chat": { "type": "string", "description": "The chat: its link as people give it (…/chats/<key>, …/o/<workspace>/<station>/<key>), a thread address CHANNEL/THREAD_TS, or a session key (reads that session's chat)." },
                        "before": { "type": "string", "description": "Only messages older than this message ts." },
                        "limit": { "type": "integer", "minimum": 1, "maximum": 200, "description": "Default 30." },
                    },
                    "required": ["chat"],
                    "additionalProperties": false,
                }),
                run: run(|hub, key, args| Box::pin(async move { hub.chat_read(&key, &args).await })),
            },
            Tool {
                name: "session_history".into(),
                description: "Read a session's execution history, as the pages show it: what its agent thought, the tools it called and what they returned, numbered #0 onwards. The latest entries unless before is given.".into(),
                input_schema: json!({
                    "type": "object",
                    "properties": {
                        "chat": { "type": "string", "description": "Whose: a session key, a chat's link (…/chats/<key>, …/o/…/<key>, or an execution history link with ?history=<key>&entry=<n>, which shows the entries around n), or a thread address CHANNEL/THREAD_TS with one agent." },
                        "before": { "type": "integer", "minimum": 0, "description": "Only entries before #before (the reply says where older ones start)." },
                        "limit": { "type": "integer", "minimum": 1, "maximum": 200, "description": "Default 40." },
                        "max_chars": { "type": "integer", "minimum": 100, "maximum": 4000, "description": "Each entry cut to this many characters. Default 1500." },
                    },
                    "required": ["chat"],
                    "additionalProperties": false,
                }),
                run: run(|hub, _key, args| Box::pin(async move { tokio::task::spawn_blocking(move || hub.session_history(&args)).await? })),
            },
        ]
    }

    fn wait_for(&self, key: &str, what: &str) {
        let actor = self.actors.lock().unwrap().get(key).cloned();
        if let Some(actor) = actor {
            actor.wait_for(what);
        }
    }

    fn need(&self, key: &str, what: &str) {
        let actor = self.actors.lock().unwrap().get(key).cloned();
        if let Some(actor) = actor {
            actor.need(what);
        }
    }

    fn about(&self, key: &str, about: Option<(i64, i64, &str)>) {
        let actor = self.actors.lock().unwrap().get(key).cloned();
        if let Some(actor) = actor {
            actor.about(about);
        }
    }

    /// What a state recorded with chat_state is about: the message `about` names (by its ts, in one of the session's
    /// threads); else for need_help, the card still pending in its chats (the latest, if several).
    fn state_about(&self, key: &str, kind: DeclaredState, args: &Map<String, Value>) -> Result<Option<(i64, i64, String)>> {
        let threads = self.store.session_threads(key)?;
        if let Some(ts) = about_ts(args)? {
            for t in &threads {
                if let Some(m) = self.store.message_at(t.thread.id, &ts)? {
                    return Ok(Some((m.thread, m.n, m.ts)));
                }
            }
            bail!("about must be the ts of a message in one of your conversations (or leave it out), got {ts}");
        }
        if kind != DeclaredState::NeedHelp {
            return Ok(None);
        }
        let mut pending: Vec<_> = threads.iter().filter_map(|t| self.store.pending_card(t.thread.id).ok().flatten()).map(|(m, _)| m).collect();
        pending.sort_by_key(|m| m.created_at);
        Ok(pending.pop().map(|m| (m.thread, m.n, m.ts)))
    }

    fn declare(&self, key: &str, kind: DeclaredState) {
        let actor = self.actors.lock().unwrap().get(key).cloned();
        if let Some(actor) = actor {
            actor.declare(kind);
        }
    }

    /// A thread of this session the agent named with to=, and how the session posts there.
    fn target(&self, key: &str, to: Option<&Value>) -> Result<SessionThread> {
        if self.store.get_session(key)?.is_none() {
            bail!("unknown session");
        }
        let known = || {
            let threads = self.store.session_threads(key).unwrap_or_default();
            let known: Vec<String> = threads.iter().map(|t| thread_address(&t.thread.channel, &t.thread.thread_ts)).collect();
            if known.is_empty() { "none yet".to_string() } else { known.join(", ") }
        };
        let to = match to {
            Some(Value::String(to)) if !to.trim().is_empty() => to,
            _ => bail!("to is required: the thread attribute of the message you are answering. This session's threads: {}", known()),
        };
        let Some((channel, thread_ts)) = parse_thread_address(to) else {
            bail!("to must look like CHANNEL/THREAD_TS, got {}", Value::String(to.clone()));
        };
        self.store.session_thread(key, &channel, &thread_ts)?.ok_or_else(|| anyhow!("{to} is not a conversation of this session. Its threads: {}", known()))
    }

    async fn chat_post(&self, key: &str, args: &Map<String, Value>) -> Result<String> {
        let text = args.get("text").map(js_string).unwrap_or_default().trim().to_string();
        let paths: Vec<String> = args.get("files").and_then(Value::as_array).map(|a| a.iter().map(js_string).collect()).unwrap_or_default();
        let given = state_arg(args.get("kind"))?;
        let card = card_arg(args.get("card"), args.get("options"))?;
        // need_decision, as said before cards: a post with a card that ends the turn need_help.
        if matches!(given, Some((_, Said::Decision))) && card.is_none() {
            bail!("need_decision carries options: a card {{\"type\": \"options\", \"options\": [...]}} people pick from (or end with kind \"need_help\" and say in need what they have to decide)");
        }
        let kind = given.map(|(kind, _)| kind);
        let need = match given {
            Some((kind, said)) => need_arg(args, kind, said)?,
            // A progress update says neither.
            None => need_arg(args, DeclaredState::Waiting(0), Said::Now)?,
        };
        // Without a need of its own, a decision asked the words from before needs what its post asks: its first line.
        let need = need.or_else(|| {
            matches!(given, Some((DeclaredState::NeedHelp, Said::Decision | Said::Before))).then(|| card.as_ref().map(|_| first_line(&text))).flatten().filter(|l| !l.is_empty())
        });
        if kind.is_none() && args.get("about").is_some_and(|a| !a.is_null()) {
            bail!("about goes with kind: the message the state this post records is about");
        }
        if text.is_empty() && paths.is_empty() {
            bail!("text is empty");
        }
        let thread = self.target(key, args.get("to"))?;
        if card.is_some() && thread.thread.surface != STILLFAIL_SURFACE {
            bail!("cards (options, a text field) are shown only in still.fail chats (EMBER/…); in a Slack thread, write the choices or the question in the text and end with kind \"need_help\"");
        }
        if card.is_some() && text.is_empty() {
            bail!("text is required with a card: what it asks and the facts it turns on, so it can be answered from this message alone");
        }
        let about = match about_ts(args)? {
            Some(ts) => Some(self.store.message_at(thread.thread.id, &ts)?.map(|m| (m.thread, m.n, m.ts)).ok_or_else(|| {
                anyhow!("about must be the ts of a message in {} (or leave it out), got {ts}", thread_address(&thread.thread.channel, &thread.thread.thread_ts))
            })?),
            None => None,
        };
        // Slack gets the files in the thread below the text. An app made before it could upload (no files:write) links to
        // them in still.fail instead.
        let slack = thread.thread.surface != STILLFAIL_SURFACE && !paths.is_empty();
        let link = || (self.link)(key).ok_or_else(|| anyhow!("files cannot be shown from Slack until this station is in a still.fail workspace; mention their paths in the text instead"));
        let files = if paths.is_empty() { vec![] } else { self.attach(key, &paths)? };
        let files = crate::thumbs::keep(files, crate::thumbs::dir(&self.config().data_dir)).await;
        let here = ThreadRef::new(&thread.thread.channel, &thread.thread.thread_ts);
        let chat = self.chat(&thread.connect)?;
        let (ts, text) = if slack {
            match chat.post(&here, &text, &files).await {
                Err(e) if e.to_string().contains("missing_scope") => {
                    let (posted, kept) = slack_with_files(&text, &files, &link()?);
                    (chat.post(&here, &posted, &[]).await?, kept)
                }
                posted => (posted?, place_figures(&text, &files)),
            }
        } else {
            (chat.post(&here, &text, &files).await?, text)
        };
        let offered = card.as_ref().map(card_said).unwrap_or_default();
        let (n, _) = self.store.insert_message(NewMessage {
            attachments: files,
            declared: kind.map(|k| k.as_str().to_string()),
            card,
            ..NewMessage::new(thread.thread.id, &ts, AuthorKind::Agent, key, &text)
        })?;
        self.shared(thread.thread.id, n, key, &text)?;
        if let Some(post) = self.store.posts_by(key)?.pop() {
            self.live.posted(key, post_entries(&[post]));
        }
        if let Some(need) = &need {
            self.need(key, need);
        }
        if let Some(kind) = kind {
            // What the state is about: as said, else for need_help the card still pending in this chat (this post's,
            // when it carries one).
            let about = about.or_else(|| {
                (kind == DeclaredState::NeedHelp).then(|| self.store.pending_card(thread.thread.id).ok().flatten().map(|(m, _)| (m.thread, m.n, m.ts))).flatten()
            });
            self.about(key, about.as_ref().map(|(thread, n, ts)| (*thread, *n, ts.as_str())));
            self.declare(key, kind);
        }
        let titled = match args.get("title").and_then(Value::as_str) {
            Some(title) => self.name_chat(&thread.thread, title)?,
            None => String::new(),
        };
        let place = thread_address(&thread.thread.channel, &thread.thread.thread_ts);
        Ok(match kind {
            Some(kind) => format!("Posted to {place}, and recorded state {}.{titled}{offered}", kind.as_str()),
            None => format!("Posted to {place}.{titled}{offered}"),
        })
    }

    async fn chat_history(&self, key: &str, args: &Map<String, Value>) -> Result<String> {
        let thread = self.target(key, args.get("to"))?;
        let to = args.get("to").map(js_string).unwrap_or_default();
        self.thread_history(key, &thread.thread, &thread.connect, &to, args).await
    }

    /// A thread's messages as chat_history and chat_read give them: `before` (a message ts) and `limit` from `args`,
    /// people named through `connect`, `key`'s own posts as "you". `named`: the thread as the agent named it.
    async fn thread_history(&self, key: &str, thread: &ThreadRow, connect: &str, named: &str, args: &Map<String, Value>) -> Result<String> {
        let limit = match args.get("limit").and_then(js_number) {
            Some(n) if n != 0.0 => n.clamp(1.0, 200.0) as usize,
            _ => 30,
        };
        let before = args.get("before").and_then(Value::as_str).filter(|b| !b.is_empty());
        let from = match before {
            Some(before) => Some(self.store.message_at(thread.id, before)?.ok_or_else(|| anyhow!("no message {before} in {named}"))?),
            None => None,
        };
        let messages = self.store.messages_before(thread.id, from.map(|m| m.n), limit)?;
        if messages.is_empty() {
            return Ok("No earlier messages.".into());
        }
        let chat = self.chat_of(connect);
        let mut names = HashMap::new();
        for m in messages.iter().filter(|m| m.author_kind == AuthorKind::Person) {
            if names.contains_key(&m.author) {
                continue;
            }
            if let Some(name) = match &chat {
                Some(chat) => chat.user_name(&m.author).await,
                None => None,
            } {
                names.insert(m.author.clone(), name);
            }
        }
        let place = thread_address(&thread.channel, &thread.thread_ts);
        Ok(format_history(&messages, &thread.surface, &place, key, &names))
    }

    /// A Slack Web API call from session `key` (slack_api), as the bot of `via` (else the session's own connect).
    /// Writes keep to the threads rule: not in a thread another session of the same bot takes part in; one it writes in
    /// becomes its own.
    async fn slack_api(&self, key: &str, method: &str, params: Map<String, Value>, via: Option<String>) -> Result<String> {
        if !is_slack_method(method) {
            bail!("not a Slack method: {}", Value::String(method.into()));
        }
        if ["admin.", "apps.", "oauth."].iter().any(|p| method.starts_with(p)) || method == "auth.revoke" {
            bail!("{method} is not for agents: it manages the Slack app itself");
        }
        let connect = match via {
            Some(via) => Some(via),
            None => self.store.get_session(key)?.map(|row| row.connect),
        };
        let connect = connect.filter(|c| c != INTERNAL_CONNECT).ok_or_else(|| anyhow!("this session has no Slack connect: give to= one of your Slack conversations"))?;
        let chat = self.chat(&connect)?;
        let text_of = |name: &str| params.get(name).and_then(Value::as_str).map(String::from);
        let channel = text_of("channel").or_else(|| text_of("channel_id"));
        let surface = self.surface(&connect);
        // A write lands in a thread: the one named, the one its message is in, or (a new message) the one it starts.
        let write = WRITES.iter().any(|w| method.starts_with(w));
        let named = text_of("thread_ts");
        let about = text_of("ts").or_else(|| text_of("timestamp"));
        let mut thread_ts = None;
        if let (true, Some(channel)) = (write, &channel) {
            thread_ts = match (named, &about) {
                (Some(named), _) => Some(named),
                (None, Some(about)) => Some(self.store.thread_of_message(&surface, channel, about)?.map(|t| t.thread_ts).unwrap_or_else(|| about.clone())),
                (None, None) => None,
            };
            let known = match &thread_ts {
                Some(ts) => self.store.thread_at(&surface, channel, ts)?,
                None => None,
            };
            // Another session of the same bot there: the thread is its (other bots' sessions keep to their own).
            if let Some(known) = known {
                if self.store.thread_sessions(known.id)?.iter().any(|m| m.session != key && m.connect == connect) {
                    bail!("{channel}/{} is another session's conversation: this session cannot write there", thread_ts.as_deref().unwrap_or(""));
                }
            }
        }
        let posted_text = text_of("text").unwrap_or_default();
        let result = chat.api(method, params).await?;
        if let (true, Some(channel)) = (write, &channel) {
            // Its thread is the session's now: a new message starts one.
            let result_ts = result.get("ts").and_then(Value::as_str);
            if let Some(root) = thread_ts.as_deref().or(result_ts) {
                let thread = self.store.open_thread(&surface, channel, root, None, Some(key))?;
                if self.store.join_thread(thread.id, key, &connect)? {
                    info!(session = key, channel, thread_ts = root, method, "session took part in a thread through slack_api");
                }
                if let (Some(ts), "chat.postMessage") = (result_ts, method) {
                    let (n, _) = self.store.insert_message(NewMessage::new(thread.id, ts, AuthorKind::Agent, key, &posted_text))?;
                    self.shared(thread.id, n, key, &posted_text)?;
                }
            }
        }
        let text = serde_json::to_string(&result)?;
        Ok(if text.chars().count() > 60_000 {
            format!("{}… (cut at 60000 characters; ask for less, e.g. a smaller limit)", text.chars().take(60_000).collect::<String>())
        } else {
            text
        })
    }

    /// A Slack user that is one of this station's connects' bots.
    fn own_bot(&self, config: &Config, user: &str) -> bool {
        config.connects.iter().filter_map(|c| self.chat_of(&c.id)).any(|chat| {
            let bot = chat.bot_user_id();
            !bot.is_empty() && bot == user
        })
    }

    /// An agent's post reaches the other sessions of its thread, as a person's would: agents work together there.
    fn shared(&self, thread: i64, n: i64, author: &str, text: &str) -> Result<()> {
        let others: Vec<String> = self.store.thread_sessions(thread)?.into_iter().map(|m| m.session).filter(|s| s != author).collect();
        if others.is_empty() {
            return Ok(());
        }
        self.hand_over(thread, n, &others, text)
    }

    fn chat(&self, connect: &str) -> Result<Arc<dyn ChatSurface>> {
        self.chat_of(connect).ok_or_else(|| anyhow!("connect {connect} is not connected"))
    }

    fn chat_of(&self, connect: &str) -> Option<Arc<dyn ChatSurface>> {
        if connect == INTERNAL_CONNECT {
            return self.internal.clone().map(|c| c as Arc<dyn ChatSurface>);
        }
        (self.chats)(connect)
    }

    /// Where a connect's threads live; the rule the v10 migration follows too.
    fn surface(&self, connect: &str) -> String {
        if connect == INTERNAL_CONNECT {
            return STILLFAIL_SURFACE.into();
        }
        slack_surface(connect, self.chat_of(connect).and_then(|c| c.workspace()).as_deref())
    }

    fn online(&self, row: &SessionRow) -> bool {
        let via = self.store.latest_thread(&row.key).ok().flatten().map(|t| t.connect).unwrap_or_else(|| row.connect.clone());
        if self.chat_of(&via).is_some() {
            return true;
        }
        warn!(session = row.key, connect = via, "session's latest thread came through a connect that is not connected; leaving it");
        false
    }

    #[allow(clippy::too_many_arguments)]
    fn create_session(
        &self,
        config: &Config,
        key: &str,
        connect: &Connect,
        scope: SessionScope,
        message: Option<&InboundMessage>,
        title: Option<&str>,
        created_by: Option<&str>,
    ) -> Result<()> {
        // The connect's own profile when it keeps to one (and it still can run it); else any of its runtime, the model's
        // first (pool.rs).
        let fits = profiles_for(config, connect);
        let model = connect.bind.model.as_deref();
        let kept = connect.bind.profile.as_ref().and_then(|id| fits.iter().find(|p| &p.id == id && serves(p, model)).copied());
        let profile = match kept {
            Some(profile) => profile.clone(),
            None => self.pick(&fits, model, false)?,
        };
        let dir = match (scope, message) {
            (SessionScope::Thread, Some(m)) => format!("{}-{}", m.channel, m.thread_ts.replacen('.', "-", 1)),
            _ => key[connect.id.len() + 1..].to_string(),
        };
        let workspace = config.data_dir.join("sessions").join(&connect.id).join(dir).join("workspace");
        std::fs::create_dir_all(&workspace)?;
        std::fs::create_dir_all(config.data_dir.join("repos"))?;
        let now = now_ms();
        self.store.insert_session(&NewSession {
            key: key.into(),
            connect: connect.id.clone(),
            scope: Some(scope),
            title: title.map(String::from),
            created_by: created_by.map(String::from),
            runtime: crate::config::runtime_name(connect.bind.runtime).into(),
            profile: profile.id.clone(),
            profile_pinned: kept.is_some(),
            model: connect.bind.model.clone(),
            effort: connect.bind.effort.clone(),
            workspace: workspace.to_string_lossy().into_owned(),
            cwd: None,
            runtime_session_id: None,
            token: new_token(),
            created_at: now,
            last_active_at: now,
        })?;
        info!(session = key, connect = connect.id, scope = ?scope, runtime = ?connect.bind.runtime, profile = profile.id, "session created");
        Ok(())
    }

    fn actor(&self, row: &SessionRow) -> Result<Arc<SessionActor>> {
        let mut actors = self.actors.lock().unwrap();
        if let Some(actor) = actors.get(&row.key) {
            return Ok(actor.clone());
        }
        let runtime = runtime_named(&row.runtime).ok_or_else(|| anyhow!("session {} runs an unknown runtime {}", row.key, row.runtime))?;
        let deps: Weak<dyn SessionDeps> = self.me.clone();
        let actor = SessionActor::new(&row.key, runtime, deps);
        actors.insert(row.key.clone(), actor.clone());
        Ok(actor)
    }
}

impl SessionDeps for Hub {
    fn store(&self) -> Arc<Store> {
        self.store.clone()
    }
    fn chat(&self, connect: &str) -> Option<Arc<dyn ChatSurface>> {
        self.chat_of(connect)
    }
    fn driver(&self, runtime: RuntimeKind) -> Result<Arc<dyn AgentDriver>> {
        self.drivers.get(&runtime).cloned().ok_or_else(|| anyhow!("no {} driver", crate::config::runtime_name(runtime)))
    }
    fn run_on(&self, key: &str) -> Result<Profile> {
        Hub::run_on(self, key)
    }
    fn spend(&self, key: &str) -> Result<Option<(String, String)>> {
        Hub::spend(self, key)
    }
    fn mcp_url(&self) -> String {
        self.mcp_url.clone()
    }
    fn repos_dir(&self) -> PathBuf {
        Hub::repos_dir(self)
    }
    fn memory_path(&self) -> PathBuf {
        agent_home_paths(&self.config().agent_home).0
    }
    fn max_nudges(&self) -> u32 {
        self.config().max_nudges
    }
    fn background_on_message(&self, key: &str) -> bool {
        let Ok(Some(row)) = self.store.get_session(key) else { return true };
        self.config().profiles.iter().find(|p| p.id == row.profile).is_none_or(|p| p.background_on_message)
    }
    fn live(&self) -> Option<Arc<LiveHub>> {
        Some(self.live.clone())
    }
    fn idle(&self, key: &str) {
        self.idle_now(key);
    }
    fn held(&self) -> bool {
        !self.holds.lock().unwrap().is_empty()
    }
    fn stop_jobs(&self, key: &str) -> BoxFuture<'static, ()> {
        let jobs = self.jobs.lock().unwrap().upgrade();
        let running: Vec<String> = self.store.list_jobs(Some(key)).unwrap_or_default().into_iter()
            .filter(|j| j.state == "running" && (j.watch || j.port.is_none()))
            .map(|j| j.id)
            .collect();
        let key = key.to_string();
        Box::pin(async move {
            let Some(jobs) = jobs else { return };
            for id in running {
                match jobs.stop(&id).await {
                    Ok(_) => info!(session = key, job = id, "job stopped with its session's wait"),
                    Err(e) => warn!(session = key, job = id, error = %e, "job not stopped"),
                }
            }
        })
    }
}

fn connect_of<'a>(config: &'a Config, id: &str) -> Result<&'a Connect> {
    config.connects.iter().find(|c| c.id == id).ok_or_else(|| anyhow!("unknown connect {id}"))
}

/// A value as JavaScript's String() writes it, for arguments given as another type than asked.
fn js_string(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Null => "null".into(),
        other => other.to_string(),
    }
}

fn js_number(value: &Value) -> Option<f64> {
    match value {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.trim().parse().ok(),
        _ => None,
    }
}

/// How long an agent may say it waits (chat_state "waiting").
const MIN_WAIT_SECONDS: u64 = 10;
const MAX_WAIT_SECONDS: u64 = 3600;

/// How many answers a decision may offer.
const MAX_OPTIONS: usize = 6;

/// The answers an options card offers (its `options`, or chat_post `options` as said before cards), as kept with its
/// post: `[{label, detail?, recommended?}]`, each label trimmed. 1 to 6, labels not empty and not repeated, at most one
/// recommended. A runtime whose tool list is from before the parameter sends it as JSON text: read too.
fn options_arg(value: Option<&Value>) -> Result<Option<Value>> {
    let parsed = match value {
        Some(Value::String(text)) if !text.trim().is_empty() => {
            Some(serde_json::from_str::<Value>(text).map_err(|_| anyhow!("options must be an array of {{label, detail?, recommended?}}"))?)
        }
        _ => None,
    };
    let list = match parsed.as_ref().or(value) {
        None | Some(Value::Null) => return Ok(None),
        Some(Value::String(_)) => return Ok(None),
        Some(Value::Array(list)) => list,
        Some(_) => bail!("options must be an array of {{label, detail?, recommended?}}"),
    };
    if list.is_empty() || list.len() > MAX_OPTIONS {
        bail!("options must have 1 to {MAX_OPTIONS} answers, got {}", list.len());
    }
    let mut out = Vec::new();
    let mut labels: Vec<String> = Vec::new();
    for (i, o) in list.iter().enumerate() {
        let o = match o {
            // A bare phrase is its label.
            Value::String(label) => json!({ "label": label }),
            Value::Object(_) => o.clone(),
            _ => bail!("options[{i}] must be an object {{label, detail?, recommended?}}"),
        };
        let label = o.get("label").map(js_string).unwrap_or_default().trim().to_string();
        if label.is_empty() {
            bail!("options[{i}].label is empty: a short phrase that reads on its own");
        }
        if labels.contains(&label) {
            bail!("options[{i}].label repeats {label:?}: each answer says something else");
        }
        labels.push(label.clone());
        let mut kept = json!({ "label": label });
        if let Some(detail) = o.get("detail").map(js_string).map(|d| d.trim().to_string()).filter(|d| !d.is_empty()) {
            kept["detail"] = json!(detail);
        }
        if o.get("recommended").is_some_and(|r| r.as_bool() == Some(true) || r.as_str() == Some("true")) {
            kept["recommended"] = json!(true);
        }
        out.push(kept);
    }
    if out.iter().filter(|o| o.get("recommended").is_some()).count() > 1 {
        bail!("only one option may be recommended");
    }
    Ok(Some(Value::Array(out)))
}

/// The kinds of card a post can carry.
const CARDS: [&str; 2] = ["options", "text"];

/// How long a text card's placeholder may be, in characters.
const MAX_PLACEHOLDER: usize = 80;

/// The card a post carries (chat_post `card`, or its `options` as said before cards: an options card), as kept with it:
/// `{type: "options", options}` (options_arg) or `{type: "text", placeholder?}`. A card of a type not known is refused,
/// naming those that are. A runtime whose tool list is from before the parameter sends it as JSON text: read too.
fn card_arg(card: Option<&Value>, options: Option<&Value>) -> Result<Option<Value>> {
    let shape = "card must be an object: {\"type\": \"options\", \"options\": [{label, detail?, recommended?}]} or {\"type\": \"text\", \"placeholder\"?}";
    let card = match card {
        None | Some(Value::Null) => None,
        Some(Value::String(text)) if text.trim().is_empty() => None,
        Some(Value::String(text)) => Some(serde_json::from_str::<Value>(text).map_err(|_| anyhow!("{shape}"))?),
        Some(card) => Some(card.clone()),
    };
    let legacy = options_arg(options)?;
    let Some(card) = card else { return Ok(legacy.map(crate::store::options_card)) };
    if legacy.is_some() {
        bail!("give the options in card ({{\"type\": \"options\", \"options\": [...]}}), not also as options");
    }
    let Some(fields) = card.as_object() else { bail!("{shape}") };
    let kind = fields.get("type").map(js_string).unwrap_or_default().trim().to_string();
    match kind.as_str() {
        "options" => {
            let options = options_arg(fields.get("options"))?.ok_or_else(|| anyhow!("an options card has options: 1 to {MAX_OPTIONS} answers {{label, detail?, recommended?}}"))?;
            Ok(Some(crate::store::options_card(options)))
        }
        "text" => {
            let placeholder = fields.get("placeholder").map(js_string).map(|p| p.trim().to_string()).filter(|p| !p.is_empty());
            if placeholder.as_ref().is_some_and(|p| p.chars().count() > MAX_PLACEHOLDER) {
                bail!("a text card's placeholder is at most {MAX_PLACEHOLDER} characters: a hint of what to write");
            }
            let mut kept = json!({ "type": "text" });
            if let Some(placeholder) = placeholder {
                kept["placeholder"] = json!(placeholder);
            }
            Ok(Some(kept))
        }
        "" => bail!("a card says its type: one of {}", CARDS.join(", ")),
        other => bail!("unknown card type {other:?}: the types known are {}", CARDS.join(", ")),
    }
}

/// What chat_post says of the card it posted.
fn card_said(card: &Value) -> String {
    match card.get("type").and_then(Value::as_str) {
        Some("options") => options_said(&card["options"]),
        _ => " People can write their answer in the card's field; it reaches you as their message quoting this one, and anything they write in the chat instead is their answer too.".into(),
    }
}

/// A post's first line, without markup, cut to about 40 characters: what a decision asked the words from before needs.
fn first_line(text: &str) -> String {
    let first = text.lines().map(str::trim).find(|l| !l.is_empty()).unwrap_or("");
    let clean = first.replace("**", "").replace("__", "").replace('`', "");
    let clean = clean.trim_start_matches(['#', '>', '-', '*', ' ']).trim();
    let cut: String = clean.chars().take(40).collect();
    if clean.chars().count() > 40 { format!("{}…", cut.trim_end()) } else { cut }
}

/// Whether all_done's `done` gives a reason, not only the word: at least a few characters, and not one of the words
/// that say only that it is done.
fn is_reason(done: &str) -> bool {
    let bare: String = done.chars().filter(|c| c.is_alphanumeric()).collect::<String>().to_lowercase();
    const EMPTY: [&str; 9] = ["做完了", "已完成", "全部完成", "都完成了", "done", "ok", "alldone", "finished", "allfinished"];
    bare.chars().count() >= MIN_REASON && !EMPTY.contains(&bare.as_str())
}

/// How many letters (or characters) all_done's `done` has at least.
const MIN_REASON: usize = 6;

/// The ts `about` names, if it is given.
fn about_ts(args: &Map<String, Value>) -> Result<Option<String>> {
    match args.get("about") {
        None | Some(Value::Null) => Ok(None),
        Some(about) => {
            let ts = js_string(about).trim().to_string();
            if ts.is_empty() { Ok(None) } else { Ok(Some(ts)) }
        }
    }
}

/// What chat_post says of the answers it offered.
fn options_said(options: &Value) -> String {
    let labels: Vec<String> = options
        .as_array()
        .into_iter()
        .flatten()
        .map(|o| {
            let label = o.get("label").and_then(Value::as_str).unwrap_or("");
            if o.get("recommended").is_some() { format!("{label} (recommended)") } else { label.to_string() }
        })
        .collect();
    format!(" People can pick: {}; a pick reaches you as their message quoting this one with the option's label, and anything they write instead is their answer too.", labels.join("; "))
}

/// In which words a turn's state was given.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Said {
    /// Today's: all_done, need_help, waiting.
    Now,
    /// From before all_done and need_help (final, block): a session whose instructions are older.
    Before,
    /// need_decision, from before cards: a post with an options card that ends the turn need_help.
    Decision,
}

/// How a post or chat_state ends the turn (`kind`), and in which words. Waiting is chat_state's own.
fn state_arg(value: Option<&Value>) -> Result<Option<(DeclaredState, Said)>> {
    match value {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(s)) if s.is_empty() => Ok(None),
        Some(Value::String(s)) if s != "waiting" && DeclaredState::parse(s, 0).is_some() => {
            let said = match s.as_str() {
                "final" | "block" => Said::Before,
                "need_decision" => Said::Decision,
                _ => Said::Now,
            };
            Ok(DeclaredState::parse(s, 0).map(|kind| (kind, said)))
        }
        Some(other) => bail!("kind must be \"all_done\" or \"need_help\" (or \"waiting\", with chat_state), got {other}"),
    }
}

/// The turn's words kept with it (turns.need): what a need_help turn needs of a person (`need`), or what an all_done
/// one leaves the chat with (`done`). Each goes only with its kind, and is required with it, unless the kind is given in
/// the words from before (block, final, need_decision: a session from before them).
fn need_arg(args: &Map<String, Value>, kind: DeclaredState, said: Said) -> Result<Option<String>> {
    let text = |k: &str| args.get(k).map(js_string).map(|n| n.trim().to_string()).filter(|n| !n.is_empty());
    let (need, done) = (text("need"), text("done"));
    if need.is_some() && kind != DeclaredState::NeedHelp {
        bail!("need goes only with kind \"need_help\"");
    }
    if done.is_some() && kind != DeclaredState::AllDone {
        bail!("done goes only with kind \"all_done\"");
    }
    if let Some(done) = &done
        && !is_reason(done)
    {
        bail!("done must say why nothing in the chat is left, so people can trust it: what was finished and where it landed or how it was confirmed (a commit, a release, a person's confirmation, the answer given), e.g. 已合进 main 82f108a5，测试版 1389 已发，你确认过滑动可以; not just that it is done");
    }
    match kind {
        DeclaredState::NeedHelp if need.is_none() && said == Said::Now => {
            bail!("need is required for need_help: what the person has to give, do or decide, in one sentence")
        }
        DeclaredState::AllDone if done.is_none() && said == Said::Now => {
            bail!("done is required for all_done: why nothing in the chat is left, with the evidence (e.g. 已合进 main 82f108a5，测试版 1389 已发，你确认过滑动可以)")
        }
        DeclaredState::NeedHelp => Ok(need),
        DeclaredState::AllDone => Ok(done),
        DeclaredState::Waiting(_) => Ok(None),
    }
}

fn is_html(f: &Attachment) -> bool {
    let name = f.name.to_lowercase();
    name.ends_with(".html") || name.ends_with(".htm")
}

/// What still.fail keeps of a post to Slack: the text with each HTML file not yet placed in it placed on a line of its
/// own (drawn there as a visualization, as the agent would place it in a still.fail chat).
fn place_figures(text: &str, files: &[Attachment]) -> String {
    let mut kept = text.to_string();
    for f in files.iter().filter(|f| is_html(f)) {
        if !kept.contains(&format!("]({})", f.name)) {
            kept = if kept.is_empty() { format!("[{0}]({0})", f.name) } else { format!("{kept}\n\n[{0}]({0})", f.name) };
        }
    }
    kept
}

/// A post with files to a Slack thread that cannot take them (an app without files:write): what Slack is sent, the text
/// with a link to the session in still.fail that opens its first figure (else its first file) on its own; and what
/// still.fail keeps (place_figures).
fn slack_with_files(text: &str, files: &[Attachment], link: &str) -> (String, String) {
    let figure = files.iter().find(|f| is_html(f));
    let what = match (figure, files.len()) {
        (Some(_), 1) => "在 still.fail 里查看图表",
        (Some(_), _) => "在 still.fail 里查看图表和附件",
        (None, _) => "在 still.fail 里查看附件",
    };
    let link = match figure.or(files.first()) {
        Some(f) => format!("{link}?file={}", crate::server::encode(&f.name)),
        None => link.to_string(),
    };
    let posted = if text.is_empty() { format!("<{link}|{what}>") } else { format!("{text}\n\n<{link}|{what}>") };
    (posted, place_figures(text, files))
}

/// What an agent posted, as its execution history shows a post: the call (to the thread, its text, files and state)
/// and that it went out. The station's own record of its messages, whatever the runtime wrote of the call.
pub fn post_entries(posts: &[Post]) -> Vec<TimelineEntry> {
    posts
        .iter()
        .flat_map(|p| {
            let at = iso(p.at);
            let call_id = format!("post:{}:{}", p.thread, p.n);
            let to = thread_address(&p.channel, &p.thread_ts);
            let mut args = json!({ "to": to, "text": p.text });
            if let Some(kind) = &p.declared {
                args["kind"] = json!(kind);
            }
            if !p.attachments.is_empty() {
                args["files"] = json!(p.attachments.iter().map(|a| a.name.clone()).collect::<Vec<_>>());
            }
            [
                TimelineEntry {
                    at: Some(at.clone()),
                    kind: "tool_call".into(),
                    text: serde_json::to_string_pretty(&args).unwrap_or_default(),
                    tool: Some("mcp__ember__chat_post".into()),
                    ok: None,
                    call_id: Some(call_id.clone()),
                    subagent: None,
                },
                TimelineEntry {
                    at: Some(at),
                    kind: "tool_result".into(),
                    text: format!("Posted to {to}."),
                    tool: None,
                    ok: Some(true),
                    call_id: Some(call_id),
                    subagent: None,
                },
            ]
        })
        .collect()
}

mod others;
mod titles;

#[cfg(test)]
mod tests;
