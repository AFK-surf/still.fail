//! test/hub.test.ts, ported (with test/fakes.ts: in-memory stand-ins for a chat platform and a runtime).

use std::collections::{HashMap, HashSet};
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};

use async_trait::async_trait;
use serde_json::Value;

use super::*;
use crate::chat::{ChatMessage, Handler};
use crate::config::{RawConfig, parse_config};
use crate::profiles::{ProfileQuota, QuotaWindow};
use crate::runtime::{Events, FailureReason, LiveEvent, LiveStepKind, OpenOptions, RuntimeEvent, TurnOutcome};
use crate::runtime::AgentSession;

static COUNTER: AtomicU64 = AtomicU64::new(1);

struct FakeChat {
    bot: String,
    posts: Mutex<Vec<(ThreadRef, String)>>,
    /// What it was told the agent is doing, per thread ("" once done).
    statuses: Mutex<Vec<(String, Option<String>, String)>>,
    calls: Mutex<Vec<(String, Map<String, Value>)>>,
    answers: Mutex<HashMap<String, Value>>,
    /// What the platform says was in a thread before the station saw it, by thread ts.
    earlier: Mutex<HashMap<String, Vec<ChatMessage>>>,
    /// The names of the files each post carried.
    files: Mutex<Vec<Vec<String>>>,
    /// Like a Slack app without files:write.
    no_files: AtomicBool,
}

impl FakeChat {
    fn new(bot: &str) -> Arc<FakeChat> {
        Arc::new(FakeChat {
            bot: bot.into(),
            posts: Mutex::default(),
            statuses: Mutex::default(),
            calls: Mutex::default(),
            answers: Mutex::default(),
            earlier: Mutex::default(),
            files: Mutex::default(),
            no_files: Default::default(),
        })
    }
    fn texts(&self) -> Vec<String> {
        self.posts.lock().unwrap().iter().map(|p| p.1.clone()).collect()
    }
    fn last_text(&self) -> String {
        self.texts().pop().unwrap_or_default()
    }
}

#[async_trait]
impl ChatSurface for FakeChat {
    fn bot_user_id(&self) -> String {
        self.bot.clone()
    }
    fn bot_name(&self) -> String {
        "ember".into()
    }
    fn workspace(&self) -> Option<String> {
        Some("T1".into())
    }
    async fn start(self: Arc<Self>, _handler: Handler) -> Result<()> {
        Ok(())
    }
    async fn post(&self, thread: &ThreadRef, message: &str, files: &[Attachment]) -> Result<String> {
        if !files.is_empty() && self.no_files.load(Ordering::SeqCst) {
            anyhow::bail!("slack files.getUploadURLExternal: missing_scope");
        }
        self.files.lock().unwrap().push(files.iter().map(|f| f.name.clone()).collect());
        self.posts.lock().unwrap().push((thread.clone(), message.into()));
        Ok(format!("{}.000200", 9_000_000 + COUNTER.fetch_add(1, Ordering::SeqCst)))
    }
    fn working(&self, thread: &ThreadRef, message_ts: Option<&str>, status: &str) {
        self.statuses.lock().unwrap().push((format!("{}/{}", thread.channel, thread.thread_ts), message_ts.map(String::from), status.into()));
    }
    async fn api(&self, method: &str, params: Map<String, Value>) -> Result<Value> {
        self.calls.lock().unwrap().push((method.into(), params));
        let answer = self.answers.lock().unwrap().get(method).cloned();
        Ok(answer.unwrap_or_else(|| json!({ "ok": true, "ts": format!("{}.000300", 9_500_000 + COUNTER.fetch_add(1, Ordering::SeqCst)) })))
    }
    async fn history(&self, thread: &ThreadRef, before: &str, limit: usize) -> Option<Result<Vec<ChatMessage>>> {
        let before: f64 = before.parse().unwrap_or(0.0);
        let all = self.earlier.lock().unwrap().get(&thread.thread_ts).cloned().unwrap_or_default();
        let earlier: Vec<ChatMessage> = all.into_iter().filter(|m| m.ts.parse::<f64>().unwrap_or(0.0) < before).collect();
        let skip = earlier.len().saturating_sub(limit);
        Some(Ok(earlier.into_iter().skip(skip).collect()))
    }
    async fn stop(&self) {}
}

struct FakeSession {
    id: String,
    options: OpenOptions,
    events: Events,
    prompts: Mutex<Vec<String>>,
    steers: Mutex<Vec<String>>,
    /// Times the running turn's tool calls were moved to the background.
    backgrounds: AtomicUsize,
    aborts: AtomicUsize,
    disposed: AtomicBool,
    busy: AtomicBool,
    /// Takes no steer (e.g. a codex turn that is not steerable).
    unsteerable: AtomicBool,
}

impl FakeSession {
    /// The test ends the running turn.
    fn end(&self, outcome: TurnOutcome) {
        self.busy.store(false, Ordering::SeqCst);
        let _ = self.events.send(RuntimeEvent::TurnEnded(outcome));
    }
    fn complete(&self) {
        self.end(TurnOutcome::Completed);
    }
    fn prompts(&self) -> Vec<String> {
        self.prompts.lock().unwrap().clone()
    }
    fn steers(&self) -> Vec<String> {
        self.steers.lock().unwrap().clone()
    }
    fn disposed(&self) -> bool {
        self.disposed.load(Ordering::SeqCst)
    }
}

#[async_trait]
impl AgentSession for FakeSession {
    fn id(&self) -> String {
        self.id.clone()
    }
    fn busy(&self) -> bool {
        self.busy.load(Ordering::SeqCst)
    }
    async fn prompt(&self, text: &str) -> Result<()> {
        if self.disposed() {
            bail!("disposed");
        }
        if self.busy() {
            bail!("busy");
        }
        self.busy.store(true, Ordering::SeqCst);
        self.prompts.lock().unwrap().push(text.into());
        Ok(())
    }
    async fn steer(&self, text: &str) -> bool {
        if !self.busy() || self.unsteerable.load(Ordering::SeqCst) {
            return false;
        }
        self.steers.lock().unwrap().push(text.into());
        true
    }
    async fn background_tools(&self) {
        self.backgrounds.fetch_add(1, Ordering::SeqCst);
    }
    async fn abort(&self) {
        self.aborts.fetch_add(1, Ordering::SeqCst);
    }
    async fn dispose(&self) {
        self.disposed.store(true, Ordering::SeqCst);
    }
    async fn hand_off(&self) -> Result<Value> {
        Ok(json!({ "id": self.id, "busy": self.busy() }))
    }
}

struct FakeDriver {
    runtime: RuntimeKind,
    sessions: Mutex<Vec<Arc<FakeSession>>>,
    /// Runtime session ids that resume fails for.
    unresumable: Mutex<HashSet<String>>,
    next: AtomicU64,
    /// Times every process it started was ended.
    shutdowns: AtomicUsize,
}

impl FakeDriver {
    fn new(runtime: RuntimeKind) -> Arc<FakeDriver> {
        Arc::new(FakeDriver { runtime, sessions: Mutex::default(), unresumable: Mutex::default(), next: AtomicU64::new(1), shutdowns: AtomicUsize::new(0) })
    }
    fn last(&self) -> Arc<FakeSession> {
        self.sessions.lock().unwrap().last().cloned().expect("a session opened")
    }
    fn count(&self) -> usize {
        self.sessions.lock().unwrap().len()
    }
    fn all(&self) -> Vec<Arc<FakeSession>> {
        self.sessions.lock().unwrap().clone()
    }
}

#[async_trait]
impl AgentDriver for FakeDriver {
    fn runtime(&self) -> RuntimeKind {
        self.runtime
    }
    async fn open(&self, options: OpenOptions, events: Events) -> Result<Arc<dyn AgentSession>> {
        if let Some(resume) = &options.resume {
            if self.unresumable.lock().unwrap().contains(resume) {
                bail!("no such session");
            }
        }
        let id = options.resume.clone().unwrap_or_else(|| format!("{}-{}", crate::config::runtime_name(self.runtime), self.next.fetch_add(1, Ordering::SeqCst)));
        let session = Arc::new(FakeSession {
            id,
            options,
            events,
            prompts: Mutex::default(),
            steers: Mutex::default(),
            backgrounds: AtomicUsize::new(0),
            aborts: AtomicUsize::new(0),
            disposed: AtomicBool::new(false),
            busy: AtomicBool::new(false),
            unsteerable: AtomicBool::new(false),
        });
        self.sessions.lock().unwrap().push(session.clone());
        Ok(session)
    }
    async fn shutdown(&self) {
        self.shutdowns.fetch_add(1, Ordering::SeqCst);
    }
    async fn adopt_session(&self, handed: &Value, events: Events) -> Result<Arc<dyn AgentSession>> {
        let options = OpenOptions {
            profile: {
                let raw: RawConfig = serde_json::from_value(json!({ "profiles": [{ "id": "cc", "runtime": "claude", "home": "homes/cc" }] })).unwrap();
                parse_config(&raw, Path::new("/tmp")).unwrap().profiles[0].clone()
            },
            cwd: PathBuf::new(),
            resume: None,
            model: None,
            effort: None,
            instructions: String::new(),
            mcp_token: String::new(),
            mcp_url: String::new(),
            route: String::new(),
        };
        let session = Arc::new(FakeSession {
            id: handed["id"].as_str().unwrap_or_default().to_string(),
            options,
            events,
            prompts: Mutex::default(),
            steers: Mutex::default(),
            backgrounds: AtomicUsize::new(0),
            aborts: AtomicUsize::new(0),
            disposed: AtomicBool::new(false),
            busy: AtomicBool::new(handed["busy"] == json!(true)),
            unsteerable: AtomicBool::new(false),
        });
        self.sessions.lock().unwrap().push(session.clone());
        Ok(session)
    }
}

fn message() -> InboundMessage {
    let ts = format!("{}.000100", 1000 + COUNTER.fetch_add(1, Ordering::SeqCst));
    InboundMessage { channel: "C1".into(), thread_ts: ts.clone(), ts, user: "U1".into(), text: "<@UBOT> hello".into(), addressed: true }
}

fn say(text: &str) -> InboundMessage {
    InboundMessage { text: text.into(), ..message() }
}

/// A reply in a thread, not addressed to anyone.
fn reply(to: &InboundMessage, ts: &str, text: &str) -> InboundMessage {
    InboundMessage { channel: to.channel.clone(), thread_ts: to.thread_ts.clone(), ts: ts.into(), user: "U1".into(), text: text.into(), addressed: false }
}

/// Lets queued actor tasks and what they started run.
async fn settle() {
    for _ in 0..50 {
        tokio::task::yield_now().await;
    }
}

struct Rig {
    _dir: tempfile::TempDir,
    config: Arc<Mutex<Arc<Config>>>,
    store: Arc<Store>,
    chat: Arc<FakeChat>,
    gpt_chat: Arc<FakeChat>,
    team_chat: Arc<FakeChat>,
    claude: Arc<FakeDriver>,
    codex: Arc<FakeDriver>,
    hub: Arc<Hub>,
}

#[derive(Default)]
struct Setup {
    max_nudges: Option<u32>,
    max_warm_claude: Option<u32>,
    warm_minutes: Option<f64>,
    team_require_mention: Option<bool>,
    link: bool,
}

fn setup_with(o: Setup) -> Rig {
    let dir = tempfile::tempdir().unwrap();
    let mut raw = json!({
        "profiles": [
            { "id": "cc", "runtime": "claude", "home": "homes/cc" },
            { "id": "cx", "runtime": "codex", "home": "homes/cx" },
        ],
        "connects": [
            { "id": "cl", "slack": { "botName": "Claude bot" }, "bind": { "runtime": "claude", "model": "opus", "effort": "high" } },
            { "id": "gpt", "bind": { "runtime": "codex" } },
            { "id": "team", "mode": "single-session", "requireMention": o.team_require_mention.unwrap_or(true), "bind": { "runtime": "claude" } },
        ],
    });
    if let Some(n) = o.max_nudges {
        raw["maxNudges"] = json!(n);
    }
    if let Some(n) = o.max_warm_claude {
        raw["maxWarmClaude"] = json!(n);
    }
    if let Some(n) = o.warm_minutes {
        raw["warmMinutes"] = json!(n);
    }
    let raw: RawConfig = serde_json::from_value(raw).unwrap();
    let config = Arc::new(Mutex::new(Arc::new(parse_config(&raw, dir.path()).unwrap())));
    let store = Arc::new(Store::open(":memory:", None).unwrap());
    let (chat, gpt_chat, team_chat) = (FakeChat::new("UBOT"), FakeChat::new("UGPT"), FakeChat::new("UTEAM"));
    let (claude, codex) = (FakeDriver::new(RuntimeKind::Claude), FakeDriver::new(RuntimeKind::Codex));
    let chats: HashMap<String, Arc<dyn ChatSurface>> =
        HashMap::from([("cl".to_string(), chat.clone() as Arc<dyn ChatSurface>), ("gpt".into(), gpt_chat.clone()), ("team".into(), team_chat.clone())]);
    let read = config.clone();
    let hub = Hub::new(HubOptions {
        config: Arc::new(move || read.lock().unwrap().clone()),
        store: store.clone(),
        chats: Arc::new(move |id| chats.get(id).cloned()),
        drivers: vec![claude.clone(), codex.clone()],
        mcp_url: "http://127.0.0.1:1/mcp".into(),
        internal: Some(Arc::new(InternalChat::default())),
        link: o.link.then(|| Box::new(|key: &str| Some(format!("https://ember.test/o/ws/st/{}", key.replace(':', "%3A")))) as Box<dyn Fn(&str) -> Option<String> + Send + Sync>),
    });
    Rig { _dir: dir, config, store, chat, gpt_chat, team_chat, claude, codex, hub }
}

fn setup() -> Rig {
    setup_with(Setup::default())
}

impl Rig {
    async fn accept(&self, m: &InboundMessage) {
        self.accept_via(m, "cl").await;
    }
    async fn accept_via(&self, m: &InboundMessage, connect: &str) {
        self.hub.accept(connect, m.clone()).await.unwrap();
    }
    async fn call(&self, key: &str, name: &str, args: Value) -> Result<String> {
        let tool = self.hub.tools().into_iter().find(|t| t.name == name).unwrap();
        (tool.run)(key.into(), args.as_object().cloned().unwrap_or_default()).await
    }
    fn edit(&self, change: impl FnOnce(&mut Config)) {
        let mut config = self.config.lock().unwrap();
        let mut next = (**config).clone();
        change(&mut next);
        *config = Arc::new(next);
    }
    fn session(&self, key: &str) -> SessionRow {
        self.store.get_session(key).unwrap().unwrap()
    }
    fn thread(&self, channel: &str, thread_ts: &str) -> ThreadRow {
        self.store.thread_at("slack:T1", channel, thread_ts).unwrap().unwrap()
    }
    fn said(&self, thread: i64) -> Vec<crate::store::MessageRow> {
        self.store.messages_before(thread, None, 10).unwrap()
    }
}

fn matches(text: &str, parts: &[&str]) -> bool {
    let mut rest = text;
    for part in parts {
        match rest.find(part) {
            Some(at) => rest = &rest[at + part.len()..],
            None => return false,
        }
    }
    true
}

#[tokio::test]
async fn a_new_session_first_says_where_it_can_be_followed_multi_session_connects_only() {
    let r = setup_with(Setup { link: true, ..Setup::default() });
    let m = say("<@UBOT> fix the build");
    r.accept(&m).await;
    settle().await;
    let posts = r.chat.posts.lock().unwrap().clone();
    assert_eq!(posts.len(), 1);
    assert_eq!(posts[0].1, format!("<https://ember.test/o/ws/st/cl%3AC1%3A{}|在 still.fail 里查看这个会话>", m.thread_ts));
    assert_eq!(posts[0].0, ThreadRef::new("C1", &m.thread_ts));
    // Its next message is the same session: nothing more.
    r.accept(&InboundMessage { thread_ts: m.thread_ts.clone(), ..say("<@UBOT> and the tests") }).await;
    settle().await;
    assert_eq!(r.chat.texts().len(), 1);
    // A single-session connect has one session for everything: no link per thread.
    r.accept_via(&say("<@UBOT> hi"), "team").await;
    settle().await;
    assert!(r.team_chat.texts().is_empty());
}

#[tokio::test]
async fn a_mention_starts_a_session_and_prompts_the_runtime_with_the_message() {
    let r = setup();
    let m = say("<@UBOT> fix the build");
    r.accept(&m).await;
    settle().await;
    let session = r.claude.last();
    assert_eq!(session.prompts().len(), 1);
    // What the agent is called there comes with the message (the connect's bot and its mention).
    let expected = format!("<message via=\"slack\" connect=\"cl\" you=\"ember (<@UBOT>)\" thread=\"C1/{0}\" from=\"U1\" ts=\"{0}\">\n<@UBOT> fix the build\n</message>", m.ts);
    assert!(session.prompts()[0].contains(&expected), "{}", session.prompts()[0]);
    assert_eq!(r.session(&session_key("cl", "C1", &m.thread_ts)).runtime_session_id, Some(session.id.clone()));
    assert!(session.options.cwd.ends_with("workspace"));
}

#[tokio::test]
async fn thread_chatter_without_a_session_is_ignored() {
    let r = setup();
    r.accept(&InboundMessage { addressed: false, ..say("just talking") }).await;
    settle().await;
    assert_eq!(r.claude.count(), 0);
}

#[tokio::test]
async fn a_mention_inside_an_existing_thread_records_what_was_said_before_and_tells_the_agent_about_it() {
    let r = setup();
    let earlier = |ts: &str, user: &str, text: &str| ChatMessage { ts: ts.into(), user: user.into(), text: text.into(), from_bot: false };
    r.chat.earlier.lock().unwrap().insert("1.000001".into(), vec![earlier("1.000001", "U2", "the build is red"), earlier("3.000001", "U3", "since this morning")]);
    r.accept(&InboundMessage { thread_ts: "1.000001".into(), ts: "5.000001".into(), ..message() }).await;
    settle().await;
    let prompt = r.claude.last().prompts()[0].clone();
    assert!(prompt.contains("Thread C1/1.000001 had messages before you were brought in"), "{prompt}");
    assert!(!prompt.contains("the build is red"), "earlier messages are recorded, not delivered");
    let thread = r.thread("C1", "1.000001");
    assert_eq!(r.said(thread.id).iter().map(|m| m.ts.as_str()).collect::<Vec<_>>(), ["1.000001", "3.000001", "5.000001"]);
    let history = r.call(&session_key("cl", "C1", "1.000001"), "chat_history", json!({ "to": "C1/1.000001", "before": "5.000001" })).await.unwrap();
    assert!(history.contains("from=\"U2\" ts=\"1.000001\">\nthe build is red"), "{history}");
    assert!(!history.contains("hello"));
}

#[tokio::test]
async fn a_message_during_a_running_turn_is_steered_into_it() {
    let r = setup();
    let first = message();
    r.accept(&first).await;
    settle().await;
    r.accept(&reply(&first, "9999.1", "also check tests")).await;
    settle().await;
    assert_eq!(r.claude.last().prompts().len(), 1);
    assert!(r.claude.last().steers()[0].contains("also check tests"));
}

#[tokio::test]
async fn a_message_during_a_running_turn_moves_what_it_waits_on_to_the_background_unless_its_profile_says_not() {
    let r = setup();
    let first = message();
    r.accept(&first).await;
    settle().await;
    r.accept(&reply(&first, "9999.1", "also check tests")).await;
    settle().await;
    let session = r.claude.last();
    assert_eq!(session.backgrounds.load(Ordering::SeqCst), 1);
    r.edit(|c| c.profiles.iter_mut().for_each(|p| p.background_on_message = false));
    r.accept(&reply(&first, "9999.2", "and lint")).await;
    settle().await;
    assert_eq!(session.steers().len(), 2);
    assert_eq!(session.backgrounds.load(Ordering::SeqCst), 1, "off: the message waits for what the turn waits on");
}

#[tokio::test]
async fn the_same_message_delivered_twice_is_handled_once() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    r.accept(&m).await;
    settle().await;
    assert_eq!(r.claude.last().prompts().len(), 1);
}

#[tokio::test]
async fn a_turn_ending_without_a_state_is_nudged_then_reported_after_max_nudges() {
    let r = setup_with(Setup { max_nudges: Some(1), ..Setup::default() });
    r.accept(&message()).await;
    settle().await;
    r.claude.last().complete();
    settle().await;
    let prompts = r.claude.last().prompts();
    assert_eq!(prompts.len(), 2);
    assert!(prompts[1].contains("ended without a state"));
    r.claude.last().complete();
    settle().await;
    assert_eq!(r.claude.last().prompts().len(), 2);
    assert!(r.chat.last_text().contains("没有给出结果"));
}

#[tokio::test(start_paused = true)]
async fn a_turn_ending_waiting_is_not_nudged_nor_evicted_and_is_asked_again_when_the_wait_is_over() {
    let r = setup_with(Setup { max_warm_claude: Some(0), warm_minutes: Some(0.0), ..Setup::default() });
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let said = r.call(&key, "chat_state", json!({ "kind": "waiting", "seconds": 1, "for": "CI 跑完" })).await.unwrap();
    assert!(said.contains("in 10 seconds"), "at least 10: {said}");
    r.claude.last().complete();
    settle().await;
    let last = r.store.session_stats(None).unwrap()[&key].last_turn.clone().unwrap();
    assert_eq!((last.declared.as_deref(), last.wait_for.as_deref()), (Some("waiting"), Some("CI 跑完")), "what it waits for is kept with the turn");
    assert_eq!(r.claude.last().prompts().len(), 1, "not nudged");
    assert!(!r.claude.last().disposed(), "its background work may run in its process");
    assert!(r.chat.texts().is_empty());
    tokio::time::sleep(Duration::from_secs(11)).await;
    settle().await;
    let prompts = r.claude.last().prompts();
    assert_eq!(prompts.len(), 2);
    assert!(prompts[1].contains("waiting on work you started (10 seconds)"), "{}", prompts[1]);
    assert_eq!(r.store.list_turns(&key).unwrap().iter().filter_map(|t| t.summary.declared.clone()).collect::<Vec<_>>(), ["waiting"]);
}

#[tokio::test(start_paused = true)]
async fn a_wait_does_not_run_out_while_a_watch_of_its_session_runs() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let watch = crate::store::JobRow {
        id: "job_w".into(), session_key: key.clone(), name: "盯 CI".into(), command: "sleep 600".into(), cwd: "/".into(), port: None,
        token: "tw".into(), state: "running".into(), pgid: None, exit_code: None, started_at: now_ms(), ended_at: None, restarts: 0,
        log: "/dev/null".into(), watch: true,
    };
    r.store.insert_job(&watch).unwrap();
    r.call(&key, "chat_state", json!({ "kind": "waiting", "seconds": 10, "for": "CI 跑完" })).await.unwrap();
    r.claude.last().complete();
    settle().await;
    tokio::time::sleep(Duration::from_secs(35)).await;
    settle().await;
    assert_eq!(r.claude.last().prompts().len(), 1, "the watch brings it back, not the clock");
    // The watch over, the wait runs out as any other.
    r.store.job_ended(&watch.id, "stopped", None).unwrap();
    tokio::time::sleep(Duration::from_secs(11)).await;
    settle().await;
    assert_eq!(r.claude.last().prompts().len(), 2);
}

#[tokio::test(start_paused = true)]
async fn a_turn_that_starts_before_the_wait_is_over_ends_it() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    r.call(&key, "chat_state", json!({ "kind": "waiting", "seconds": 60, "for": "CI 跑完" })).await.unwrap();
    r.claude.last().complete();
    settle().await;
    r.accept(&reply(&m, "9999.1", "any news?")).await;
    settle().await;
    r.call(&key, "chat_state", json!({ "kind": "final" })).await.unwrap();
    r.claude.last().complete();
    tokio::time::sleep(Duration::from_secs(120)).await;
    settle().await;
    assert_eq!(r.claude.last().prompts().len(), 2, "no word when the old wait's time comes");
    let refused = r.call(&key, "chat_state", json!({ "kind": "waiting" })).await.unwrap_err();
    assert!(refused.to_string().contains("seconds is required"), "{refused}");
    let refused = r.call(&key, "chat_state", json!({ "kind": "waiting", "seconds": 60 })).await.unwrap_err();
    assert!(refused.to_string().contains("for is required"), "{refused}");
}

#[tokio::test]
async fn chat_post_with_kind_final_posts_and_settles_the_turn_without_a_nudge() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let to = format!("C1/{}", m.thread_ts);
    // "final", from a session whose instructions are from before all_done, is all_done.
    assert_eq!(r.call(&key, "chat_post", json!({ "to": to, "text": "**done**", "kind": "final" })).await.unwrap(), format!("Posted to {to}, and recorded state all_done."));
    r.claude.last().complete();
    settle().await;
    assert_eq!(r.claude.last().prompts().len(), 1);
    assert_eq!(*r.chat.posts.lock().unwrap(), vec![(ThreadRef::new("C1", &m.thread_ts), "**done**".to_string())]);
}

#[tokio::test]
async fn the_agents_posts_are_recorded_in_the_thread_and_chat_history_shows_them_as_its_own() {
    let r = setup();
    let m = say("<@UBOT> look");
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let to = format!("C1/{}", m.thread_ts);
    r.call(&key, "chat_post", json!({ "to": to, "text": "looking", "kind": "block" })).await.unwrap();
    let thread = r.thread("C1", &m.thread_ts);
    let said = r.said(thread.id);
    assert_eq!(
        (said[0].author_kind, said[1].author_kind, said[1].author.as_str(), said[1].declared.as_deref()),
        (AuthorKind::Person, AuthorKind::Agent, key.as_str(), Some("need_help"))
    );
    assert_eq!(r.store.pending_messages(&key).unwrap().len(), 0, "an agent's own post is not delivered back to it");
    let history = r.call(&key, "chat_history", json!({ "to": to })).await.unwrap();
    assert!(matches(&history, &["from=\"U1\" ts=\"", "\">\n<@UBOT> look", "from=\"you\" ts=\"", "\">\nlooking"]), "{history}");
}

#[tokio::test]
async fn an_agent_reads_another_sessions_chat_by_its_link_or_address_and_finds_it_in_the_list() {
    let r = setup();
    let (a, b) = (say("<@UBOT> look at the build"), say("<@UBOT> what did the other chat find?"));
    r.accept(&a).await;
    r.accept(&b).await;
    settle().await;
    let (key_a, key_b) = (session_key("cl", "C1", &a.thread_ts), session_key("cl", "C1", &b.thread_ts));
    let to_a = format!("C1/{}", a.thread_ts);
    r.call(&key_a, "chat_post", json!({ "to": to_a, "text": "the build is green" })).await.unwrap();
    // Not one of B's conversations, yet B reads it: by its address, by its chat's link, by its session key.
    let link = format!("https://ember.test/w/ws/s/st/chats/{}", key_a.replace(':', "%3A"));
    for chat in [to_a.clone(), link, key_a.clone()] {
        let read = r.call(&key_b, "chat_read", json!({ "chat": chat })).await.unwrap();
        assert!(matches(&read, &[&format!("Conversation {to_a}; its agents: {key_a}."), "from=\"U1\"", "look at the build", &format!("from=\"{key_a}\" bot"), "the build is green"]), "{read}");
    }
    let listed = r.call(&key_b, "chat_list", json!({ "query": "BUILD" })).await.unwrap();
    assert!(matches(&listed, &[&format!("- {to_a} (Slack thread)"), &format!("agents: {key_a};"), "the build is green"]), "{listed}");
    assert!(!listed.contains(&b.thread_ts), "{listed}");
    let mine = r.call(&key_b, "chat_list", json!({})).await.unwrap();
    assert!(mine.contains(&format!("{key_b} (you)")), "{mine}");
    let history = r.call(&key_b, "session_history", json!({ "chat": to_a })).await.unwrap();
    assert_eq!(history, format!("Session {key_a} has no execution history yet."));
    let e = r.call(&key_b, "chat_read", json!({ "chat": "https://ember.test/o/ws/st/nope" })).await.unwrap_err().to_string();
    assert!(e.contains("not on this station"), "{e}");
    let e = r.call(&key_b, "chat_read", json!({ "chat": "C9/1.000001" })).await.unwrap_err().to_string();
    assert!(e.contains("no conversation C9/1.000001"), "{e}");
}

#[tokio::test]
async fn slack_edits_are_appended_to_the_thread_as_entries_of_their_own() {
    let r = setup();
    let m = say("<@UBOT> typo");
    r.accept(&m).await;
    let thread = r.thread("C1", &m.thread_ts);
    let before = r.store.last_entry(thread.id).unwrap();
    let edit = || ChatEvent::Changed { channel: "C1".into(), thread_ts: m.thread_ts.clone(), ts: m.ts.clone(), text: "<@UBOT> fixed".into() };
    r.hub.receive("cl", edit()).await.unwrap();
    r.hub.receive("cl", edit()).await.unwrap(); // Slack repeats roots when replies come
    let entries = r.store.entries_after(thread.id, before).unwrap();
    assert_eq!((entries[0].kind, entries[0].target, entries[0].text.as_deref()), (crate::store::EntryKind::Edit, Some(before), Some("<@UBOT> fixed")));
    assert_eq!(r.store.last_entry(thread.id).unwrap(), before + 1);
}

#[tokio::test]
async fn chat_state_rejects_kinds_it_does_not_know() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    let refused = r.call(&session_key("cl", "C1", &m.thread_ts), "chat_state", json!({ "kind": "wait" })).await.unwrap_err();
    assert!(refused.to_string().contains("\"all_done\" or \"need_human\" (or \"waiting\""), "{refused}");
}

#[tokio::test]
async fn stop_aborts_the_running_turn_and_confirms_once_it_ends() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    r.accept(&InboundMessage { addressed: true, ..reply(&m, "9999.2", "<@UBOT> -stop") }).await;
    settle().await;
    let session = r.claude.last();
    assert_eq!(session.aborts.load(Ordering::SeqCst), 1);
    assert!(session.steers().is_empty(), "-stop is not forwarded to the agent");
    session.end(TurnOutcome::Aborted);
    settle().await;
    assert_eq!(r.chat.last_text(), "已停止当前任务");
    assert_eq!(session.prompts().len(), 1, "no nudge after a stop");
}

#[tokio::test(start_paused = true)]
async fn stop_while_waiting_ends_the_wait_and_its_process() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    r.call(&key, "chat_state", json!({ "kind": "waiting", "seconds": 10, "for": "任务跑完" })).await.unwrap();
    r.claude.last().complete();
    settle().await;
    r.accept(&InboundMessage { addressed: true, ..reply(&m, "9999.2", "<@UBOT> -stop") }).await;
    settle().await;
    assert!(r.claude.last().disposed(), "the background work in its process ends with it");
    assert_eq!(r.chat.last_text(), "已停止当前任务");
    let last = r.store.last_turn(&key).unwrap().unwrap();
    assert_eq!((last.outcome.as_deref(), last.declared.as_deref(), last.wait_seconds), (Some("aborted"), None, None), "no longer shown running");
    tokio::time::sleep(Duration::from_secs(30)).await;
    settle().await;
    assert_eq!(r.claude.last().prompts().len(), 1, "not asked again when the wait would have been over");
}

#[tokio::test]
async fn stop_while_waiting_ends_the_jobs_that_would_bring_it_back_but_not_its_services() {
    let r = setup();
    let jobs = crate::jobs::Jobs::new(r.store.clone(), r._dir.path(), Arc::new(|_, _| {}), Arc::new(|_, _| None)).unwrap();
    r.hub.set_jobs(&jobs);
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let cwd = r._dir.path();
    let job = jobs.start(&key, "build", "sleep 600", cwd, None, crate::jobs::Watch::default()).unwrap();
    let watch = jobs.start(&key, "盯 CI", "sleep 600", cwd, None, crate::jobs::Watch { on: true }).unwrap();
    let service = jobs.start(&key, "page", "sleep 600", cwd, Some(47123), crate::jobs::Watch::default()).unwrap();
    r.call(&key, "chat_state", json!({ "kind": "waiting", "seconds": 600, "for": "任务跑完" })).await.unwrap();
    r.claude.last().complete();
    settle().await;
    r.hub.stop(&key).await.unwrap();
    let state = |id: &str| r.store.get_job(id).unwrap().unwrap().state;
    for _ in 0..50 {
        if state(&job.id) != "running" && state(&watch.id) != "running" {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert_eq!((state(&job.id), state(&watch.id), state(&service.id)), ("stopped".to_string(), "stopped".to_string(), "running".to_string()));
    assert_eq!(r.chat.last_text(), "已停止当前任务");
    jobs.stop(&service.id).await.unwrap();
}

#[tokio::test]
async fn claude_auth_retries_once_then_reports_the_profile_and_does_not_loop() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let first = r.claude.last();
    first.end(TurnOutcome::Failed { reason: FailureReason::Auth, message: "401 Missing API key".into() });
    settle().await;
    let retry = r.claude.last();
    assert!(first.disposed());
    assert_eq!(r.claude.count(), 2);
    assert_eq!(retry.options.resume.as_deref(), Some(first.id.as_str()));
    assert_eq!(retry.prompts(), vec![crate::instructions::GO_ON_AFTER_AUTH.to_string()]);
    assert!(!r.chat.texts().iter().any(|t| t.contains("认证失败")));
    retry.end(TurnOutcome::Failed { reason: FailureReason::Auth, message: "401 Missing API key".into() });
    settle().await;
    assert_eq!(r.claude.count(), 2, "a persistent auth failure must stop, not loop");
    assert!(matches(&r.chat.last_text(), &["认证失败", "401 Missing API key"]));
    assert_eq!(r.claude.last().prompts().len(), 1);
    // The notice says whose sign-in failed, for the clients to link that profile's page; another failure is no profile's.
    let thread = r.thread("C1", &m.thread_ts);
    let last = |r: &Rig| r.store.entries_before(thread.id, None, 1).unwrap().pop().unwrap();
    assert_eq!((last(&r).author_kind, last(&r).profile.as_deref()), (AuthorKind::StillFail, Some("cc")));
    r.accept(&InboundMessage { addressed: true, ..reply(&m, "9999.2", "<@UBOT> again") }).await;
    settle().await;
    r.claude.last().end(TurnOutcome::Failed { reason: FailureReason::Exited, message: "exit 1".into() });
    settle().await;
    assert!(matches(&r.chat.last_text(), &["意外退出"]));
    assert_eq!(last(&r).profile, None);
}

#[tokio::test]
async fn claude_auth_recovers_without_replaying_input_and_a_later_turn_can_recover_again() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = r.claude.last().options.route.clone();
    for expected in [2, 3] {
        r.claude.last().end(TurnOutcome::Failed { reason: FailureReason::Auth, message: "401 expired token".into() });
        settle().await;
        assert_eq!(r.claude.count(), expected);
        assert_eq!(r.claude.last().prompts(), vec![crate::instructions::GO_ON_AFTER_AUTH.to_string()]);
        r.call(&key, "chat_state", json!({ "kind": "all_done", "done": "测试任务已完成，没有剩余工作" })).await.unwrap();
        r.claude.last().complete();
        settle().await;
        assert!(!r.chat.texts().iter().any(|t| t.contains("认证失败")));
        if expected == 2 {
            r.accept(&InboundMessage { addressed: true, ..reply(&m, "9999.2", "<@UBOT> next task") }).await;
            settle().await;
        }
    }
}

#[tokio::test]
async fn claude_auth_does_not_restart_stopped_held_or_declared_work() {
    for mode in ["stop", "hold", "declared"] {
        let r = setup();
        let m = message();
        r.accept(&m).await;
        settle().await;
        match mode {
            "stop" => r.accept(&InboundMessage { addressed: true, ..reply(&m, "9999.2", "<@UBOT> -stop") }).await,
            "hold" => r.hub.hold(Hold::Drain),
            _ => { r.call(&r.claude.last().options.route, "chat_state", json!({ "kind": "all_done", "done": "测试任务已完成，没有剩余工作" })).await.unwrap(); }
        }
        settle().await;
        r.claude.last().end(TurnOutcome::Failed { reason: FailureReason::Auth, message: "401".into() });
        settle().await;
        assert_eq!(r.claude.count(), 1, "{mode}");
    }
}

#[tokio::test]
async fn claude_auth_retry_budget_and_attribution_survive_handoff() {
    let r = setup();
    r.accept(&message()).await;
    settle().await;
    r.claude.last().end(TurnOutcome::Failed { reason: FailureReason::Auth, message: "401".into() });
    settle().await;
    let handed = r.hub.hand_off().await.unwrap();
    let saved = serde_json::to_value(&handed.sessions[0].turn).unwrap();
    let turn: crate::session::HandedTurn = serde_json::from_value(saved).unwrap();
    assert!(turn.auth_retried);
    assert!(turn.by.person.is_some());
    assert!(turn.by.thread.is_some());
    // An older station never wrote these fields.
    let old: crate::session::HandedTurn = serde_json::from_value(json!({ "id": "old", "declared": null, "wait": null })).unwrap();
    assert!(!old.auth_retried);
    assert_eq!(old.by, crate::store::TurnFor::default());
}

#[tokio::test]
async fn messages_that_arrive_while_a_turn_cannot_take_them_go_in_the_next_turn() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let session = r.claude.last();
    session.unsteerable.store(true, Ordering::SeqCst);
    r.accept(&reply(&m, "9999.3", "one more thing")).await;
    settle().await;
    session.complete();
    settle().await;
    assert_eq!(session.prompts().len(), 2);
    assert!(session.prompts()[1].contains("one more thing"));
}

#[tokio::test]
async fn a_connects_runtime_profile_and_model_decide_the_session() {
    let r = setup();
    let m = say("<@UGPT> refactor this");
    r.accept_via(&m, "gpt").await;
    settle().await;
    assert_eq!((r.claude.count(), r.codex.count()), (0, 1));
    let row = r.session(&session_key("gpt", "C1", &m.thread_ts));
    assert_eq!((row.profile.as_str(), row.model), ("cx", None));
    let n = message();
    r.accept(&n).await;
    settle().await;
    assert_eq!(r.session(&session_key("cl", "C1", &n.thread_ts)).model.as_deref(), Some("opus"));
    assert_eq!(r.claude.last().options.effort.as_deref(), Some("high"), "the connect's effort reaches the runtime");
    // Guidance only: no identity, no name (what it is called comes with each message, per connect).
    let instructions = &r.claude.last().options.instructions;
    assert!(!instructions.contains("You are ") && !instructions.contains("Claude bot"));
}

#[tokio::test]
async fn two_connects_in_one_thread_keep_separate_sessions_share_its_messages_and_reply_through_their_own_connection() {
    let r = setup();
    let root = say("<@UBOT> <@UGPT> compare notes");
    r.accept(&root).await;
    r.accept_via(&root, "gpt").await;
    settle().await;
    let both = reply(&root, "9999.7", "both of you: go");
    r.accept(&both).await;
    r.accept_via(&both, "gpt").await;
    settle().await;
    assert!(r.claude.last().steers()[0].contains("both of you"));
    assert!(r.codex.last().steers()[0].contains("both of you"));
    r.call(&session_key("gpt", "C1", &root.thread_ts), "chat_post", json!({ "to": format!("C1/{}", root.thread_ts), "text": "from gpt" })).await.unwrap();
    assert_eq!(r.gpt_chat.texts(), ["from gpt"]);
    assert!(r.chat.texts().is_empty());
    let thread = r.thread("C1", &root.thread_ts);
    let members: Vec<(String, String)> = r.store.thread_sessions(thread.id).unwrap().into_iter().map(|m| (m.session, m.connect)).collect();
    assert_eq!(members, [(session_key("cl", "C1", &root.thread_ts), "cl".into()), (session_key("gpt", "C1", &root.thread_ts), "gpt".into())]);
    let kinds: Vec<AuthorKind> = r.said(thread.id).iter().map(|m| m.author_kind).collect();
    assert_eq!(kinds, [AuthorKind::Person, AuthorKind::Person, AuthorKind::Agent], "each message once, however many connects saw it");
}

#[tokio::test]
async fn a_mention_of_one_connect_does_not_start_a_session_for_another_connect_that_sees_the_message() {
    let r = setup();
    r.accept_via(&InboundMessage { addressed: false, ..say("<@UBOT> only claude") }, "gpt").await;
    settle().await;
    assert_eq!(r.codex.count(), 0);
}

#[tokio::test]
async fn after_a_restart_a_cut_off_turn_is_resumed() {
    let first = setup();
    first.accept(&message()).await;
    settle().await;
    let runtime_id = first.claude.last().id.clone();
    // Same store, new hub and drivers: what a restart looks like.
    let claude = FakeDriver::new(RuntimeKind::Claude);
    let chat = first.chat.clone();
    let read = first.config.clone();
    let hub = Hub::new(HubOptions {
        config: Arc::new(move || read.lock().unwrap().clone()),
        store: first.store.clone(),
        chats: Arc::new(move |id| (id == "cl").then(|| chat.clone() as Arc<dyn ChatSurface>)),
        drivers: vec![claude.clone(), FakeDriver::new(RuntimeKind::Codex)],
        mcp_url: "x".into(),
        internal: None,
        link: None,
    });
    hub.recover().unwrap();
    settle().await;
    assert_eq!(claude.last().options.resume, Some(runtime_id));
    assert!(claude.last().prompts()[0].contains("restarted while you were in the middle of a turn"));
}

#[tokio::test]
async fn handed_over_to_the_next_binary_a_running_turn_goes_on_and_what_came_meanwhile_reaches_it() {
    let first = setup();
    let m = message();
    first.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let old = first.claude.last();
    let handed = first.hub.hand_off().await.unwrap();
    assert_eq!(handed.sessions.len(), 1);
    assert!(handed.sessions[0].turn.is_some(), "its turn goes along");
    // Said while handing over: it waits, pending, and the old binary does nothing more with it.
    first.accept(&reply(&m, "9999.7", "one more thing")).await;
    settle().await;
    assert!(old.steers().is_empty() && old.prompts().len() == 1);
    // The next binary: same store, new hub and drivers, what was handed over read back from its file.
    let claude = FakeDriver::new(RuntimeKind::Claude);
    let chat = first.chat.clone();
    let read = first.config.clone();
    let hub = Hub::new(HubOptions {
        config: Arc::new(move || read.lock().unwrap().clone()),
        store: first.store.clone(),
        chats: Arc::new(move |id| (id == "cl").then(|| chat.clone() as Arc<dyn ChatSurface>)),
        drivers: vec![claude.clone(), FakeDriver::new(RuntimeKind::Codex)],
        mcp_url: "x".into(),
        internal: None,
        link: None,
    });
    hub.adopt(serde_json::from_str(&serde_json::to_string(&handed).unwrap()).unwrap()).await;
    hub.recover().unwrap();
    settle().await;
    let taken = claude.last();
    assert_eq!(taken.id, old.id);
    assert!(taken.prompts().is_empty(), "not resumed: its turn runs on");
    assert!(taken.steers().first().is_some_and(|s| s.contains("one more thing")), "{:?}", taken.steers());
    assert!(first.store.get_session(&key).unwrap().unwrap().running);
    // Its end is the next binary's: it ended without a state, so it nudges.
    taken.complete();
    settle().await;
    assert_eq!(taken.prompts().len(), 1, "{:?}", taken.prompts());
    assert!(taken.prompts()[0].contains(crate::instructions::NUDGE));
}

#[tokio::test]
async fn held_turns_start_once_released_with_what_waited_meanwhile() {
    let r = setup_with(Setup { max_nudges: Some(0), ..Setup::default() });
    let m = message();
    r.accept(&m).await;
    settle().await;
    let session = r.claude.last();
    session.complete();
    settle().await;
    r.hub.hold(Hold::Drain);
    r.accept(&reply(&m, "9999.8", "next")).await;
    settle().await;
    assert_eq!(session.prompts().len(), 1, "held: nothing starts");
    assert!(!r.hub.any_running());
    r.hub.release(Hold::Drain);
    settle().await;
    assert_eq!(session.prompts().len(), 2);
    assert!(session.prompts()[1].contains("next"));
}

#[tokio::test]
async fn a_station_in_no_workspace_starts_no_turn_until_it_joins_one_whatever_a_drain_does() {
    let r = setup_with(Setup { max_nudges: Some(0), ..Setup::default() });
    r.hub.hold(Hold::Unbound);
    let m = message();
    r.accept(&m).await;
    settle().await;
    assert!(r.claude.sessions.lock().unwrap().is_empty(), "unbound: no runtime session starts");
    let key = session_key("cl", &m.channel, &m.thread_ts);
    assert_eq!(r.store.pending_messages(&key).unwrap().len(), 1, "the message waits");
    // A drain that comes and goes meanwhile does not let it through.
    r.hub.hold(Hold::Drain);
    r.hub.release(Hold::Drain);
    settle().await;
    assert!(r.claude.sessions.lock().unwrap().is_empty());
    assert!(r.hub.holds(Hold::Unbound));
    r.hub.release(Hold::Unbound);
    settle().await;
    let session = r.claude.last();
    assert_eq!(session.prompts().len(), 1, "joined: what waited starts");
    assert!(session.prompts()[0].contains("hello"));
}

/// Removed from its workspace with a turn under way and a message given to it meanwhile: the runtime ends (an interrupt
/// left it free to act on the message it had queued, and post), and nothing it says afterwards counts. Back in the
/// workspace, the turn resumes on the same runtime session with the message again.
#[tokio::test]
async fn leaving_the_workspace_ends_the_runtimes_and_coming_back_resumes_the_cut_off_turn_with_what_it_was_given() {
    let r = setup_with(Setup { max_nudges: Some(0), ..Setup::default() });
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let session = r.claude.last();
    r.accept(&reply(&m, "9999.5", "and the docs too")).await;
    settle().await;
    assert!(session.steers()[0].contains("and the docs too"), "given to the running turn");
    assert!(r.store.pending_messages(&key).unwrap().is_empty());
    // An idle process of another session ends as well.
    let other = say("<@UBOT> other");
    r.accept(&other).await;
    settle().await;
    let idle = r.claude.last();
    idle.complete();
    settle().await;
    assert!(!Arc::ptr_eq(&idle, &session) && !idle.busy() && !idle.disposed());

    let said = r.chat.texts().len();
    r.hub.hold(Hold::Unbound);
    r.hub.suspend_all().await;
    assert!(session.disposed() && idle.disposed(), "every runtime process ended");
    assert_eq!(session.aborts.load(Ordering::SeqCst), 0, "ended, not just interrupted");
    assert_eq!((r.claude.shutdowns.load(Ordering::SeqCst), r.codex.shutdowns.load(Ordering::SeqCst)), (1, 1), "and the drivers' own");
    assert!(!r.hub.any_running());
    assert_eq!(r.hub.process_state(&key), "cold");
    assert!(r.session(&key).running, "kept for recover");
    let pending = r.store.pending_messages(&key).unwrap();
    assert_eq!(pending.iter().map(|p| p.message.text.as_str()).collect::<Vec<_>>(), ["and the docs too"], "what it may not have read waits again");
    // What the ended runtime still says is not taken: no nudge, no notice, nothing started.
    session.complete();
    settle().await;
    assert_eq!(r.claude.count(), 2, "no runtime starts while out of the workspace");
    assert_eq!(r.chat.texts().len(), said, "nothing said in the threads: {:?}", r.chat.texts());
    assert!(r.session(&key).running);

    // Back in the workspace (App::bind): recover, then release.
    r.hub.recover().unwrap();
    r.hub.release(Hold::Unbound);
    settle().await;
    let resumed = r.claude.last();
    assert_eq!(r.claude.count(), 3, "only the cut-off turn resumes; the idle session waits for its next message");
    assert_eq!(resumed.options.resume, Some(session.id.clone()), "on the same runtime session");
    assert!(matches(&resumed.prompts()[0], &["restarted while you were in the middle of a turn", "and the docs too"]), "{:?}", resumed.prompts());
    assert!(r.store.pending_messages(&key).unwrap().is_empty());
}

#[tokio::test]
async fn a_turn_that_had_already_said_final_is_not_resumed_after_leaving_the_workspace() {
    let r = setup_with(Setup { max_nudges: Some(0), ..Setup::default() });
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let thread = format!("C1/{}", m.thread_ts);
    r.call(&key, "chat_post", json!({ "to": thread, "text": "done", "kind": "final" })).await.unwrap();
    r.hub.hold(Hold::Unbound);
    r.hub.suspend_all().await;
    assert!(r.claude.last().disposed());
    assert!(!r.session(&key).running);
    r.hub.recover().unwrap();
    r.hub.release(Hold::Unbound);
    settle().await;
    assert_eq!(r.claude.count(), 1, "nothing to resume");
}

#[tokio::test]
async fn when_the_runtime_session_cannot_be_resumed_a_new_one_starts_and_is_told_to_catch_up() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let old = r.claude.last();
    old.end(TurnOutcome::Failed { reason: FailureReason::Exited, message: "gone".into() });
    let _ = old.events.send(RuntimeEvent::Closed("gone".into()));
    settle().await;
    r.claude.unresumable.lock().unwrap().insert(old.id.clone());
    r.accept(&reply(&m, "9999.4", "still there?")).await;
    settle().await;
    let now = r.claude.last();
    assert!(!Arc::ptr_eq(&now, &old));
    assert_eq!(now.options.resume, None);
    assert!(matches(&now.prompts()[0], &["could not be restored", "still there?"]));
}

#[tokio::test]
async fn idle_claude_processes_beyond_the_warm_limit_are_evicted_oldest_first_as_soon_as_another_goes_idle() {
    let r = setup_with(Setup { max_warm_claude: Some(1), warm_minutes: Some(0.0), ..Setup::default() });
    r.accept(&InboundMessage { ts: "1.1".into(), thread_ts: "1.1".into(), ..message() }).await;
    settle().await;
    r.claude.last().end(TurnOutcome::Aborted);
    settle().await;
    assert!(!r.claude.last().disposed(), "within the limit");
    // Idle for a moment longer than the next one will be.
    tokio::time::sleep(Duration::from_millis(5)).await;
    r.accept(&InboundMessage { ts: "2.1".into(), thread_ts: "2.1".into(), ..message() }).await;
    settle().await;
    r.claude.last().end(TurnOutcome::Aborted);
    settle().await;
    assert_eq!(r.claude.all().iter().map(|s| s.disposed()).collect::<Vec<_>>(), [true, false]);
}

#[tokio::test]
async fn an_idle_process_beyond_the_limit_is_evicted_at_its_own_deadline() {
    let r = setup_with(Setup { max_warm_claude: Some(0), warm_minutes: Some(0.002), ..Setup::default() }); // 120 ms
    r.accept(&message()).await;
    settle().await;
    r.claude.last().end(TurnOutcome::Aborted);
    settle().await;
    assert!(!r.claude.last().disposed(), "not idle long enough yet");
    tokio::time::sleep(Duration::from_millis(250)).await;
    settle().await;
    assert!(r.claude.last().disposed());
}

#[tokio::test]
async fn a_running_turn_is_never_evicted() {
    let r = setup_with(Setup { max_warm_claude: Some(0), warm_minutes: Some(0.0), ..Setup::default() });
    r.accept(&message()).await;
    tokio::time::sleep(Duration::from_millis(20)).await;
    settle().await;
    assert!(!r.claude.last().disposed());
}

#[tokio::test]
async fn chat_post_and_chat_history_need_an_explicit_thread_of_this_session() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let error = |args: Value, tool: &'static str| {
        let (r, key) = (&r, &key);
        async move { r.call(key, tool, args).await.unwrap_err().to_string() }
    };
    let e = error(json!({ "text": "hi" }), "chat_post").await;
    assert!(matches(&e, &["to is required", "C1/"]), "{e}");
    assert!(error(json!({ "to": "C1", "text": "hi" }), "chat_post").await.contains("CHANNEL/THREAD_TS"));
    assert!(error(json!({ "to": "C9/1.1", "text": "hi" }), "chat_post").await.contains("not a conversation of this session"));
    assert!(error(json!({}), "chat_history").await.contains("to is required"));
    assert!(r.chat.texts().is_empty());
}

#[tokio::test]
async fn a_single_session_connect_gathers_every_thread_into_one_session_and_replies_where_asked() {
    let r = setup();
    let a = say("<@UTEAM> build A");
    r.accept_via(&a, "team").await;
    settle().await;
    r.accept_via(&InboundMessage { addressed: false, channel: "C2".into(), ..say("unrelated chatter") }, "team").await;
    let b = InboundMessage { channel: "C2".into(), ..say("<@UTEAM> build B") };
    r.accept_via(&b, "team").await;
    settle().await;
    assert_eq!(r.claude.count(), 1);
    assert_eq!(r.store.list_sessions().unwrap().len(), 1);
    let bound = r.store.binding("team").unwrap().unwrap();
    assert_eq!(r.session(&bound).scope, SessionScope::All);
    let session = r.claude.last();
    assert!(matches(&session.steers()[0], &["thread=\"C2/", "build B"]));
    assert!(!(session.steers().join("\n") + &session.prompts().join("\n")).contains("unrelated chatter"));
    // A reply in a thread the session already follows needs no mention.
    r.accept_via(&reply(&a, "9999.8", "and tests too"), "team").await;
    settle().await;
    assert!(session.steers().last().unwrap().contains("and tests too"));
    r.call(&bound, "chat_post", json!({ "to": format!("C2/{}", b.thread_ts), "text": "B done" })).await.unwrap();
    assert_eq!(*r.team_chat.posts.lock().unwrap(), vec![(ThreadRef::new("C2", &b.thread_ts), "B done".to_string())]);
}

#[tokio::test]
async fn a_single_session_connect_without_require_mention_hears_every_message() {
    let r = setup_with(Setup { team_require_mention: Some(false), ..Setup::default() });
    r.accept_via(&InboundMessage { addressed: false, ..say("anyone around?") }, "team").await;
    settle().await;
    assert_eq!(r.claude.count(), 1);
    assert!(r.claude.last().prompts()[0].contains("anyone around?"));
}

#[tokio::test]
async fn a_single_session_connect_can_be_pointed_at_a_new_or_an_existing_session() {
    let r = setup();
    r.accept_via(&say("<@UTEAM> one"), "team").await;
    settle().await;
    let old = r.store.binding("team").unwrap().unwrap();
    let fresh = r.hub.bind_single("team", None, Some("值班"), None).unwrap();
    assert_ne!(fresh, old);
    assert_eq!(r.session(&fresh).title.as_deref(), Some("值班"));
    r.accept_via(&say("<@UTEAM> two"), "team").await;
    settle().await;
    assert_eq!(r.claude.count(), 2, "the new binding got its own runtime session");
    assert!(r.claude.last().prompts()[0].contains("two"));

    // Binding a session that another connect started: replies still go out where each thread came in.
    let m = say("<@UBOT> from cl");
    r.accept(&m).await;
    settle().await;
    let cl_key = session_key("cl", "C1", &m.thread_ts);
    r.hub.bind_single("team", Some(&cl_key), None, None).unwrap();
    let t = InboundMessage { channel: "C7".into(), ..say("<@UTEAM> via team") };
    r.accept_via(&t, "team").await;
    settle().await;
    let threads: Vec<(String, String)> = r.store.session_threads(&cl_key).unwrap().into_iter().map(|t| (t.thread.channel, t.connect)).collect();
    assert_eq!(threads, [("C7".to_string(), "team".to_string()), ("C1".into(), "cl".into())]);
    r.call(&cl_key, "chat_post", json!({ "to": format!("C7/{}", t.thread_ts), "text": "to team thread" })).await.unwrap();
    r.call(&cl_key, "chat_post", json!({ "to": format!("C1/{}", m.thread_ts), "text": "to cl thread" })).await.unwrap();
    assert_eq!(r.team_chat.texts(), ["to team thread"]);
    assert_eq!(r.chat.texts(), ["to cl thread"]);
    assert!(r.hub.bind_single("team", Some(&session_key("gpt", "C1", "1.1")), None, None).unwrap_err().to_string().contains("unknown session"));
    assert!(r.hub.bind_single("cl", None, None, None).unwrap_err().to_string().contains("not single-session"));
}

#[tokio::test]
async fn a_chat_opened_on_the_admin_page_reaches_the_session_like_slack_and_the_agent_answers_there() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    r.call(&key, "chat_post", json!({ "to": format!("C1/{}", m.thread_ts), "text": "done", "kind": "final" })).await.unwrap();
    r.claude.last().complete();
    settle().await;
    r.store.set_title(&key, Some("排查")).unwrap();
    let thread = r.hub.open_chat(&key, "local", None).unwrap();
    assert_eq!(thread.title.as_deref(), Some("排查"), "its own chat keeps the name the session was given");
    r.hub.say(thread.id, "local", "现在进展如何？", vec![], vec![], None).unwrap();
    settle().await;
    let prompt = r.claude.last().prompts().pop().unwrap();
    assert!(prompt.contains(&format!("<message via=\"web\" connect=\"ember\" thread=\"EMBER/{}\" from=\"管理员 (local)\"", thread.thread_ts)), "{prompt}");
    assert!(prompt.contains("现在进展如何"));
    let to = format!("EMBER/{}", thread.thread_ts);
    assert_eq!(r.call(&key, "chat_post", json!({ "to": to, "text": "快好了", "kind": "all_done", "done": "答了进展：快好了，没有别的要做" })).await.unwrap(), format!("Posted to {to}, and recorded state all_done."));
    let said: Vec<(AuthorKind, String)> = r.said(thread.id).into_iter().map(|x| (x.author_kind, x.text)).collect();
    assert_eq!(said, [(AuthorKind::Person, "现在进展如何？".to_string()), (AuthorKind::Agent, "快好了".into())]);
    assert_eq!(r.chat.texts().len(), 1, "only the Slack thread's own answer went to Slack");
    assert!(r.call(&key, "chat_history", json!({ "to": to })).await.unwrap().contains("现在进展如何"));
    assert!(r.hub.open_chat("nope", "local", None).unwrap_err().to_string().contains("unknown session"));
}

fn new_chat(runtime: RuntimeKind) -> NewChat {
    NewChat { runtime, profile: None, model: None, effort: None, title: None, created_by: "local".into(), client_key: None }
}

#[tokio::test]
async fn a_persons_message_in_a_chat_with_several_agents_reaches_each_of_them_once() {
    let r = setup();
    let one = r.hub.new_session(new_chat(RuntimeKind::Claude)).unwrap();
    let two = r.hub.new_session(new_chat(RuntimeKind::Codex)).unwrap();
    r.hub.add_to_thread(one.1.id, &two.0).unwrap();
    let quote = Quote { author: "Claude".into(), role: Some("agent".into()), ts: Some("1.000001".into()), text: "上一条".into(), comment: "这里".into(), file: None };
    r.hub.say(one.1.id, "a@example.com", "你们俩分一下工", vec![], vec![quote], None).unwrap();
    settle().await;
    for driver in [&r.claude, &r.codex] {
        assert_eq!(driver.count(), 1);
        let prompt = &driver.last().prompts()[0];
        assert!(prompt.contains("[Quote] From your own earlier message 1.000001 in this conversation:\n> 上一条\nTheir comment on it: 这里\n\n你们俩分一下工"), "{prompt}");
    }
    assert_eq!(r.store.pending_messages(&one.0).unwrap().len() + r.store.pending_messages(&two.0).unwrap().len(), 0);
    let said = r.said(one.1.id);
    assert_eq!(said[0].text, "你们俩分一下工", "the words are stored as typed; the quote is a column");
    assert_eq!(said[0].quotes[0].comment, "这里");
}

#[tokio::test]
async fn a_pending_message_edited_before_delivery_reaches_the_agent_as_edited() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let session = r.claude.last();
    session.unsteerable.store(true, Ordering::SeqCst);
    let edited = reply(&m, "9999.5", "first draft");
    r.accept(&edited).await;
    settle().await; // it waits: the running turn takes no steer
    r.hub.receive("cl", ChatEvent::Changed { channel: "C1".into(), thread_ts: m.thread_ts.clone(), ts: edited.ts.clone(), text: "final words".into() }).await.unwrap();
    session.complete();
    settle().await;
    let prompt = &session.prompts()[1];
    assert!(prompt.contains("final words") && !prompt.contains("first draft"), "{prompt}");
    assert_eq!(r.store.pending_messages(&session_key("cl", "C1", &m.thread_ts)).unwrap().len(), 0);
}

/// A transcript the runtime wrote for a session, in its profile's home.
fn transcript_of(r: &Rig, row: &SessionRow, text: &str) -> PathBuf {
    let home = r.config.lock().unwrap().profiles[0].home.clone();
    let path = home.join("projects").join("x").join(format!("{}.jsonl", row.runtime_session_id.as_deref().unwrap()));
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(&path, text).unwrap();
    path
}

#[tokio::test]
async fn deleting_a_session_ends_its_process_and_removes_its_workspace_and_the_threads_only_it_was_in() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let row = r.session(&key);
    // The runtime's transcript lives in the profile's home and stays.
    let transcript = transcript_of(&r, &row, "{}\n");
    assert!(Path::new(&row.workspace).exists());
    r.hub.delete_session(&key).await.unwrap();
    assert!(r.claude.last().disposed());
    assert!(r.store.get_session(&key).unwrap().is_none());
    assert!(r.store.thread_at("slack:T1", "C1", &m.thread_ts).unwrap().is_none());
    assert!(!Path::new(&row.workspace).exists());
    assert!(!Path::new(&row.workspace).parent().unwrap().exists());
    assert!(transcript.exists());
}

#[tokio::test]
async fn archiving_a_session_keeps_a_zstd_copy_of_its_transcript_showing_it_again_or_deleting_it_removes_the_copy() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let transcript = transcript_of(&r, &r.session(&key), "{\"type\":\"user\"}\n");
    let copy = r.store.archive_dir().join("transcripts").join(format!("{key}.jsonl.zst"));
    r.hub.archive(&key, true).unwrap();
    assert_eq!(zstd::decode_all(std::fs::read(&copy).unwrap().as_slice()).unwrap(), b"{\"type\":\"user\"}\n");
    assert!(transcript.exists(), "the runtime's own file stays as it is");
    r.hub.archive(&key, false).unwrap();
    assert!(!copy.exists());
    r.hub.archive(&key, true).unwrap();
    r.hub.delete_session(&key).await.unwrap();
    assert!(!copy.exists());
}

#[tokio::test]
async fn archiving_a_session_cleans_what_can_be_made_again_from_its_directory() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let workspace = PathBuf::from(r.session(&key).workspace);
    std::fs::create_dir_all(workspace.join("app/node_modules/x")).unwrap();
    std::fs::write(workspace.join("app/node_modules/x/index.js"), vec![1u8; 50_000]).unwrap();
    std::fs::write(workspace.join("notes.md"), b"kept").unwrap();
    assert_eq!(r.hub.clean_rebuildable(&key), 0, "not while in the lists");
    r.hub.archive(&key, true).unwrap();
    settle().await;
    assert_eq!(r.hub.clean_rebuildable(&key), 0, "not while at work");
    assert!(workspace.join("app/node_modules").exists());
    r.call(&key, "chat_state", json!({ "kind": "final" })).await.unwrap();
    r.claude.last().complete();
    settle().await;
    r.hub.archive(&key, false).unwrap();
    r.hub.archive(&key, true).unwrap();
    for _ in 0..200 {
        if !workspace.join("app/node_modules").exists() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    assert!(!workspace.join("app/node_modules").exists(), "cleaned once archived");
    assert_eq!(std::fs::read(workspace.join("notes.md")).unwrap(), b"kept");
}

#[tokio::test]
async fn idle_chats_that_are_done_are_archived_by_the_station_busy_blocked_unread_and_bound_ones_stay() {
    let r = setup();
    let day = 86_400_000;
    let m = message();
    r.accept(&m).await;
    settle().await;
    let idle = session_key("cl", "C1", &m.thread_ts);
    r.call(&idle, "chat_state", json!({ "kind": "final" })).await.unwrap();
    r.claude.last().complete();
    settle().await;
    let b = InboundMessage { channel: "C2".into(), ..say("<@UBOT> look") };
    r.accept(&b).await;
    settle().await;
    let blocked = session_key("cl", "C2", &b.thread_ts);
    r.call(&blocked, "chat_state", json!({ "kind": "block" })).await.unwrap();
    r.claude.last().complete();
    settle().await;
    let (web, thread) = r.hub.new_session(NewChat { runtime: RuntimeKind::Claude, profile: None, model: None, effort: None, title: None, created_by: "local".into(), client_key: None }).unwrap();
    r.hub.say(thread.id, "local", "hi", vec![], vec![], None).unwrap();
    settle().await;
    // The agent's answer is unread: the chat stays.
    r.call(&web, "chat_post", json!({ "to": format!("EMBER/{}", thread.thread_ts), "text": "hello", "kind": "final" })).await.unwrap();
    r.claude.last().complete();
    settle().await;
    r.accept_via(&say("<@UBOT> hi"), "team").await;
    settle().await;
    let bound = r.store.binding("team").unwrap().unwrap();
    r.call(&bound, "chat_state", json!({ "kind": "final" })).await.unwrap();
    r.claude.last().complete();
    settle().await;

    r.hub.auto_archive(now_ms()).unwrap();
    assert!(r.store.list_sessions().unwrap().iter().all(|s| s.archived_at.is_none()), "nothing has idled a day yet");
    let later = now_ms() + 2 * day;
    r.hub.auto_archive(later).unwrap();
    assert_eq!(r.session(&idle).archived_by.as_deref(), Some(AUTO));
    assert_eq!(r.session(&blocked).archived_at, None, "stopped at a block");
    assert_eq!(r.session(&web).archived_at, None, "unread");
    assert_eq!(r.session(&bound).archived_at, None, "a single-session connect's");
    r.store.set_read("local", thread.id, r.store.last_entry(thread.id).unwrap()).unwrap();
    // A job of its own still up (a watch above all): it stays until the job is over.
    let watch = crate::store::JobRow {
        id: "job_w".into(), session_key: web.clone(), name: "盯 CI".into(), command: "sleep 600".into(), cwd: "/".into(), port: None,
        token: "tw".into(), state: "running".into(), pgid: None, exit_code: None, started_at: now_ms(), ended_at: None, restarts: 0,
        log: "/dev/null".into(), watch: true,
    };
    r.store.insert_job(&watch).unwrap();
    r.hub.auto_archive(later).unwrap();
    assert_eq!(r.session(&web).archived_at, None, "its watch runs");
    r.store.job_ended(&watch.id, "stopped", None).unwrap();
    // Pinned by anyone, it stays in the lists.
    r.store.set_pin("dev@example.com", &web, true).unwrap();
    r.hub.auto_archive(later).unwrap();
    assert_eq!(r.session(&web).archived_at, None, "pinned");
    r.store.set_pin("dev@example.com", &web, false).unwrap();
    r.hub.auto_archive(later).unwrap();
    assert_eq!(r.session(&web).archived_by.as_deref(), Some(AUTO));
    assert!(r.store.get_thread(thread.id).unwrap().unwrap().hidden_at.is_some(), "its own chat with it");
    // Someone writes in the Slack thread again: its session is back.
    r.accept(&reply(&m, "9999.5", "<@UBOT> one more")).await;
    assert_eq!(r.session(&idle).archived_at, None);
    // A chat opened with a session that has one is a chat of its own, archived alone.
    r.hub.archive(&web, false).unwrap();
    r.store.set_title(&web, Some("值班")).unwrap();
    let second = r.hub.open_chat(&web, "local", None).unwrap();
    assert_eq!(second.home, None);
    assert_eq!(second.title, None, "a chat of its own does not take the session's name");
    r.hub.archive_chat(second.id, true).unwrap();
    assert_eq!(r.session(&web).archived_at, None);
    assert!(r.store.get_thread(second.id).unwrap().unwrap().hidden_at.is_some());
    r.hub.archive_chat(thread.id, true).unwrap();
    assert_eq!(r.session(&web).archived_by.as_deref(), Some(MANUAL));
}

#[test]
fn command_parsing() {
    assert!(is_stop_command("<@UBOT>  -stop "));
    assert!(!is_stop_command("please -stop now"));
    assert!(is_slack_method("conversations.history") && is_slack_method("assistant.threads.setStatus"));
    assert!(!is_slack_method("Chat.postMessage") && !is_slack_method("chat") && !is_slack_method("chat..x"));
}

#[tokio::test]
async fn a_session_changes_profile_model_and_effort_by_hand_and_is_taken_on_by_another_profile_when_its_own_cannot_run() {
    let r = setup();
    let m = say("<@UBOT> fix the build");
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    fn with(id: &'static str, name: &'static str, models: &'static [&'static str]) -> impl FnOnce(&mut Config) {
        move |c: &mut Config| {
            let mut p = c.profiles[0].clone();
            (p.id, p.name, p.models) = (id.to_string(), name.to_string(), models.iter().map(|s| s.to_string()).collect());
            c.profiles.push(p);
        }
    }
    let change = |profile: Option<Option<&str>>, model: Option<&str>, effort: Option<&str>| SessionChange {
        profile: profile.map(|p| p.map(String::from)),
        model: model.map(|m| Some(m.to_string())),
        effort: effort.map(|e| Some(e.to_string())),
    };
    let refused = |e: Result<()>| e.unwrap_err().to_string();
    r.edit(with("cc2", "another", &["opus"]));
    assert!(refused(r.hub.configure(&key, change(Some(Some("cc2")), None, None)).await).contains("正在跑"), "not while a turn runs");
    r.call(&key, "chat_post", json!({ "to": format!("C1/{}", m.thread_ts), "text": "done", "kind": "final" })).await.unwrap();
    r.claude.last().complete();
    settle().await;
    r.hub.configure(&key, change(Some(Some("cc2")), None, None)).await.unwrap();
    assert_eq!(r.session(&key).profile, "cc2");
    assert!(refused(r.hub.configure(&key, change(Some(Some("cx")), None, None)).await).contains("不能跑 Claude Code"));
    r.edit(with("cc3", "third", &[]));
    assert!(refused(r.hub.configure(&key, change(Some(Some("cc3")), None, None)).await).contains("「third」没有启用 opus"), "only one with its model enabled");
    // Its model and effort change too, to what a profile of its runtime runs.
    assert!(refused(r.hub.configure(&key, change(None, Some("gpt-5"), None)).await).contains("没有能跑 gpt-5 的 Claude Code Profile"));
    assert!(refused(r.hub.configure(&key, change(None, None, Some("ultra"))).await).contains("思考深度只有"));
    r.edit(|c| c.profiles.iter_mut().filter(|p| p.id == "cc" || p.id == "cc2").for_each(|p| p.models.push("sonnet".into())));
    r.hub.configure(&key, change(Some(Some("cc2")), Some("sonnet"), Some("low"))).await.unwrap();
    let row = r.session(&key);
    assert_eq!((row.model.as_deref(), row.effort.as_deref()), (Some("sonnet"), Some("low")));
    assert!(row.profile_pinned, "kept to it by hand");
    // Another model alone: what went with the old one starts over, the effort default and the profile the station's
    // pick among those with it enabled.
    r.edit(|c| c.profiles.iter_mut().filter(|p| p.id == "cc3").for_each(|p| p.models.push("haiku".into())));
    r.hub.configure(&key, change(None, Some("haiku"), None)).await.unwrap();
    let row = r.session(&key);
    assert_eq!((row.model.as_deref(), row.effort.as_deref(), row.profile.as_str(), row.profile_pinned), (Some("haiku"), None, "cc3", false));
    r.hub.configure(&key, change(Some(Some("cc2")), Some("sonnet"), Some("low"))).await.unwrap();
    // Given back to the station, and its own used up: the next start runs on the other one, which takes it on.
    r.hub.configure(&key, change(Some(None), None, None)).await.unwrap();
    assert!(!r.session(&key).profile_pinned);
    r.hub.evict(&key).await;
    r.hub.set_profile_health(Arc::new(|id| ProfileHealth {
        check: None,
        quota: (id == "cc2").then(|| ProfileQuota {
            state: "ok".into(),
            windows: vec![QuotaWindow { label: "每周".into(), used_percent: 100.0, resets_at: None }],
            detail: None,
            checked_at: 0,
        }),
        spent: false,
    }));
    r.accept(&InboundMessage { thread_ts: m.thread_ts.clone(), ..say("<@UBOT> and the tests") }).await;
    settle().await;
    assert_eq!(r.session(&key).profile, "cc");
}

#[tokio::test]
async fn a_connect_or_a_new_chat_can_keep_its_sessions_to_one_profile_otherwise_the_pool_picks() {
    let r = setup();
    r.edit(|c| {
        let mut p = c.profiles[0].clone();
        (p.id, p.name, p.models) = ("cc2".into(), "second".into(), vec!["opus".into()]);
        c.profiles.push(p);
        c.connects.iter_mut().find(|c| c.id == "cl").unwrap().bind.profile = Some("cc2".into());
    });
    let m = say("<@UBOT> hi");
    r.accept(&m).await;
    settle().await;
    let row = r.session(&session_key("cl", "C1", &m.thread_ts));
    assert_eq!((row.profile.as_str(), row.profile_pinned), ("cc2", true));
    // A new chat given a profile keeps to it; one that has not the model on is refused.
    let pinned = |model: &str| NewChat { model: Some(model.into()), profile: Some("cc2".into()), ..new_chat(RuntimeKind::Claude) };
    let (key, _) = r.hub.new_session(pinned("opus")).unwrap();
    assert_eq!((r.session(&key).profile.as_str(), r.session(&key).profile_pinned), ("cc2", true));
    assert!(r.hub.new_session(pinned("sonnet")).unwrap_err().to_string().contains("没有启用 sonnet"));
    let (auto, _) = r.hub.new_session(new_chat(RuntimeKind::Claude)).unwrap();
    assert!(!r.session(&auto).profile_pinned);
}

#[tokio::test]
async fn the_slack_thread_a_turn_works_for_says_what_the_agent_is_doing_until_the_turn_ends() {
    let r = setup();
    let m = say("<@UBOT> fix the build");
    r.accept(&m).await;
    settle().await;
    let session = r.claude.last();
    let live = |event: LiveEvent| session.events.send(RuntimeEvent::Live(event)).unwrap();
    live(LiveEvent::Start { id: "t1".into(), step: LiveStepKind::Tool, tool: Some("Bash".into()), input: None, subagent: None, parent: None });
    live(LiveEvent::End { id: "t1".into() });
    session.complete();
    settle().await;
    let statuses = r.chat.statuses.lock().unwrap().clone();
    assert_eq!(statuses.iter().map(|s| s.2.as_str()).collect::<Vec<_>>(), ["正在思考…", "正在运行命令…", "正在思考…", ""]);
    assert_eq!(statuses[0].0, format!("C1/{}", m.thread_ts));
    assert_eq!(statuses[0].1.as_deref(), Some(m.ts.as_str()), "the message that started it, for the fallback reaction");
}

#[tokio::test]
async fn slack_api_calls_slack_as_the_sessions_bot_a_thread_it_writes_in_becomes_its_own_one_another_session_has_is_refused() {
    let r = setup();
    let mine = say("<@UBOT> look around");
    let theirs = say("<@UBOT> something else");
    r.accept(&mine).await;
    r.accept(&theirs).await;
    settle().await;
    let key = session_key("cl", "C1", &mine.thread_ts);
    let history = json!({ "ok": true, "messages": [{ "ts": "1.1", "text": "hello" }] });
    r.chat.answers.lock().unwrap().insert("conversations.history".into(), history.clone());
    let got = r.call(&key, "slack_api", json!({ "method": "conversations.history", "params": { "channel": "C1", "limit": 1 } })).await.unwrap();
    assert_eq!(got, history.to_string());
    let last = r.chat.calls.lock().unwrap().last().cloned().unwrap();
    assert_eq!((last.0.as_str(), Value::Object(last.1)), ("conversations.history", json!({ "channel": "C1", "limit": 1 })));
    // Not the app itself, and not another session's thread.
    let refused = |args: Value| {
        let (r, key) = (&r, &key);
        async move { r.call(key, "slack_api", args).await.unwrap_err().to_string() }
    };
    assert!(refused(json!({ "method": "apps.manifest.update", "params": {} })).await.contains("not for agents"));
    assert!(refused(json!({ "method": "chat.postMessage", "params": { "channel": "C1", "thread_ts": theirs.thread_ts, "text": "hi" } })).await.contains("another session's"));
    // A new message: its thread is this session's now, and a reply there comes to it.
    r.chat.answers.lock().unwrap().insert("chat.postMessage".into(), json!({ "ok": true, "ts": "7777.1" }));
    r.call(&key, "slack_api", json!({ "method": "chat.postMessage", "params": { "channel": "C2", "text": "a new topic" } })).await.unwrap();
    let started = r.thread("C2", "7777.1");
    assert_eq!(r.store.thread_sessions(started.id).unwrap().into_iter().map(|m| m.session).collect::<Vec<_>>(), [key.clone()]);
    let said: Vec<(AuthorKind, String)> = r.said(started.id).into_iter().map(|m| (m.author_kind, m.text)).collect();
    assert_eq!(said, [(AuthorKind::Agent, "a new topic".to_string())]);
    let agent = r.claude.all().into_iter().find(|s| s.options.route == key).unwrap();
    r.call(&key, "chat_state", json!({ "kind": "final" })).await.unwrap();
    agent.complete();
    settle().await;
    r.accept(&InboundMessage { channel: "C2".into(), thread_ts: "7777.1".into(), ts: "7777.2".into(), addressed: false, ..say("a reply to it") }).await;
    settle().await;
    assert!(agent.prompts().last().unwrap().contains("a reply to it"));
}

#[test]
fn posts_show_in_the_history_as_chat_post_calls() {
    let post = Post {
        thread: 3,
        n: 7,
        channel: "C1".into(),
        thread_ts: "1.1".into(),
        text: "done".into(),
        attachments: vec![],
        declared: Some("final".into()),
        at: 0,
    };
    let entries = post_entries(&[post]);
    assert_eq!(entries[0].text, "{\n  \"to\": \"C1/1.1\",\n  \"text\": \"done\",\n  \"kind\": \"final\"\n}");
    assert_eq!((entries[0].at.as_deref(), entries[1].text.as_str(), entries[1].call_id.as_deref()), (Some("1970-01-01T00:00:00.000Z"), "Posted to C1/1.1.", Some("post:3:7")));
}

#[tokio::test]
async fn agents_in_one_thread_hear_each_other_a_post_reaches_the_threads_other_sessions_marked_a_bot_and_not_its_author() {
    let r = setup();
    let root = say("<@UBOT> <@UGPT> work this out together");
    r.accept(&root).await;
    r.accept_via(&root, "gpt").await;
    settle().await;
    let (cl, gpt) = (session_key("cl", "C1", &root.thread_ts), session_key("gpt", "C1", &root.thread_ts));
    r.call(&cl, "chat_state", json!({ "kind": "final" })).await.unwrap();
    r.call(&gpt, "chat_state", json!({ "kind": "final" })).await.unwrap();
    r.claude.last().complete();
    r.codex.last().complete();
    settle().await;
    let before = r.claude.last().prompts().len();
    r.call(&gpt, "chat_post", json!({ "to": format!("C1/{}", root.thread_ts), "text": "I'll take the tests; can you do the build?" })).await.unwrap();
    settle().await;
    let prompts = r.claude.last().prompts();
    assert_eq!(prompts.len(), before + 1);
    assert!(matches(prompts.last().unwrap(), &["from=\"ember (<@UGPT>)\" bot ts=\"", "\">\nI'll take the tests; can you do the build?"]), "{}", prompts.last().unwrap());
    assert!(!r.codex.last().prompts().iter().any(|p| p.contains("I'll take the tests")), "not back to its author");
    // Slack's copy of that post, seen through the other connect, is not a message of its own.
    r.accept(&InboundMessage { user: "UGPT".into(), ..reply(&root, "9999.9", "I'll take the tests; can you do the build?") }).await;
    settle().await;
    assert_eq!(r.claude.last().prompts().len(), before + 1);
}

#[tokio::test]
async fn in_a_chat_on_the_stations_page_with_several_agents_what_one_posts_reaches_the_others() {
    let r = setup();
    let one = r.hub.new_session(new_chat(RuntimeKind::Claude)).unwrap();
    let two = r.hub.new_session(new_chat(RuntimeKind::Codex)).unwrap();
    r.hub.add_to_thread(one.1.id, &two.0).unwrap();
    r.hub.say(one.1.id, "local", "分一下工", vec![], vec![], None).unwrap();
    settle().await;
    r.call(&one.0, "chat_state", json!({ "kind": "final" })).await.unwrap();
    r.call(&two.0, "chat_state", json!({ "kind": "final" })).await.unwrap();
    r.claude.last().complete();
    r.codex.last().complete();
    settle().await;
    r.call(&one.0, "chat_post", json!({ "to": format!("EMBER/{}", one.1.thread_ts), "text": "我来写接口" })).await.unwrap();
    settle().await;
    let heard = r.codex.last().prompts().pop().unwrap();
    assert!(matches(&heard, &["from=\"Claude Code\" bot ts=\"", "\">\n我来写接口"]), "{heard}");
}

#[tokio::test]
async fn a_session_the_machine_kept_goes_on_in_a_chat_run_in_its_own_directory_with_what_was_said_in_it() {
    let r = setup();
    let machine = tempfile::tempdir().unwrap();
    let project = machine.path().join("app");
    std::fs::create_dir_all(&project).unwrap();
    std::fs::write(project.join("main.rs"), "fn main() {}").unwrap();
    let roots = crate::machine_sessions::tests::machine(machine.path(), &project);
    let found = crate::machine_sessions::find(&roots, RuntimeKind::Claude, "11111111-aaaa-bbbb-cccc-000000000001").unwrap();
    let (key, thread) = r.hub.continue_machine_session(&roots, &found, "local").unwrap();
    let row = r.session(&key);
    assert_eq!(row.cwd.as_deref(), Some(project.to_str().unwrap()));
    assert_eq!(row.runtime_session_id.as_deref(), Some(found.id.as_str()));
    assert!(row.workspace.ends_with("workspace") && !row.workspace.starts_with(project.to_str().unwrap()));
    assert_eq!(r.store.get_thread(thread.id).unwrap().unwrap().title.as_deref(), Some("Fix the build"));
    let copy = r.config.lock().unwrap().data_dir.join("transcripts/claude").join(found.path.strip_prefix(&roots.claude).unwrap());
    assert_eq!(std::fs::read(&copy).unwrap(), std::fs::read(&found.path).unwrap());
    let said = r.said(thread.id);
    // Only a note of where it came from, linking to what was said before: nothing of it is copied into the chat.
    assert_eq!(said.len(), 1);
    assert_eq!(said[0].author_kind, AuthorKind::StillFail);
    assert!(said[0].text.starts_with("接着本机 Claude Code 在"), "{}", said[0].text);
    // At its history's last entry as it came: the transcript's timeline (user, assistant, tool call and result, …).
    let mut tail = crate::transcript::TranscriptTail::new(RuntimeKind::Claude, found.path.clone());
    tail.read();
    let last = tail.entries.len() - 1;
    assert!(said[0].text.ends_with(&format!("[查看之前的对话](?history={key}&entry={last})")), "{}", said[0].text);
    settle().await;
    assert_eq!(r.claude.count(), 0, "what was said before is not handed to the agent again");

    r.hub.say(thread.id, "local", "and the tests", vec![], vec![], None).unwrap();
    settle().await;
    let opened = r.claude.last();
    assert_eq!(opened.options.resume.as_deref(), Some(found.id.as_str()));
    assert_eq!(opened.options.cwd, project);
    assert_eq!(opened.options.instructions, "", "its system prompt is left as it began");
    assert_eq!(opened.prompts().len(), 1);
    let first = &opened.prompts()[0];
    assert!(first.starts_with("This session began in a terminal and now goes on in still.fail"), "{first}");
    assert!(first.contains("<stillfail-instructions>") && first.contains("and the tests"));
    assert!(first.contains(&format!("- Project directory: {}.", project.display())));
    opened.complete();
    settle().await;
    r.hub.say(thread.id, "local", "one more", vec![], vec![], None).unwrap();
    settle().await;
    let next = r.claude.last().prompts().last().cloned().unwrap();
    assert!(!next.contains("<stillfail-instructions>"), "said once: {next}");

    // Going on with it again is the same chat.
    let again = crate::machine_sessions::find(&roots, RuntimeKind::Claude, &found.id).unwrap();
    assert_eq!(r.hub.continue_machine_session(&roots, &again, "local").unwrap().0, key);

    // Deleting the chat leaves the project and the machine's transcript alone.
    r.claude.last().complete();
    settle().await;
    r.hub.delete_session(&key).await.unwrap();
    assert!(project.join("main.rs").exists());
    assert!(found.path.exists());
}

#[tokio::test]
async fn a_session_whose_directory_is_gone_is_not_continued() {
    let r = setup();
    let machine = tempfile::tempdir().unwrap();
    let roots = crate::machine_sessions::tests::machine(machine.path(), &machine.path().join("gone"));
    let found = crate::machine_sessions::find(&roots, RuntimeKind::Codex, "22222222-aaaa-bbbb-cccc-000000000001").unwrap();
    let error = r.hub.continue_machine_session(&roots, &found, "local").unwrap_err().to_string();
    assert!(error.contains("已经不在了"), "{error}");
    assert!(r.store.list_sessions().unwrap().is_empty());
}

#[tokio::test]
async fn files_posted_to_slack_go_into_the_thread_apps_without_files_write_link_to_still_fail() {
    let r = setup_with(Setup { link: true, ..Setup::default() });
    let m = say("<@UBOT> chart it");
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let to = format!("C1/{}", m.thread_ts);
    let workspace = r.store.get_session(&key).unwrap().unwrap().workspace;
    for name in ["shot.png", "weather.html"] {
        std::fs::write(Path::new(&workspace).join(name), "x").unwrap();
    }
    let link = format!("https://ember.test/o/ws/st/cl%3AC1%3A{}", m.thread_ts);
    r.call(&key, "chat_post", json!({ "to": to, "text": "图在这", "files": ["shot.png"] })).await.unwrap();
    assert_eq!((r.chat.last_text(), r.chat.files.lock().unwrap().last().cloned().unwrap()), ("图在这".to_string(), vec!["shot.png".to_string()]));
    r.call(&key, "chat_post", json!({ "to": to, "text": "图表", "files": ["shot.png", "weather.html"] })).await.unwrap();
    assert_eq!(r.chat.last_text(), "图表");
    assert_eq!(r.chat.files.lock().unwrap().last().cloned().unwrap(), vec!["shot.png".to_string(), "weather.html".to_string()]);
    let said = r.said(r.thread("C1", &m.thread_ts).id);
    let last = said.last().unwrap();
    assert_eq!((last.text.as_str(), last.attachments.len()), ("图表\n\n[weather.html](weather.html)", 2), "still.fail keeps both, the figure placed");
    r.chat.no_files.store(true, Ordering::SeqCst);
    r.call(&key, "chat_post", json!({ "to": to, "text": "再看", "files": ["shot.png"] })).await.unwrap();
    assert_eq!(r.chat.last_text(), format!("再看\n\n<{link}?file=shot.png|在 still.fail 里查看附件>"), "no files:write: linked as before");
    assert_eq!(r.chat.files.lock().unwrap().last().cloned().unwrap(), Vec::<String>::new());
}

#[test]
fn files_an_app_cannot_upload_stay_in_still_fail_and_the_post_links_there() {
    let file = |name: &str| Attachment { name: name.into(), path: format!("/w/uploads/{name}"), size: 1, width: None, height: None, thumbhash: None };
    let (posted, kept) = slack_with_files("这周的天气", &[file("weather.html"), file("shot.png")], "https://e/o/w/s/k");
    assert_eq!(posted, "这周的天气\n\n<https://e/o/w/s/k?file=weather.html|在 still.fail 里查看图表和附件>", "the link opens the figure");
    assert_eq!(kept, "这周的天气\n\n[weather.html](weather.html)", "the HTML placed so still.fail draws it; an image shows below as ever");
    let (posted, kept) = slack_with_files("看图：[天气](weather.html)", &[file("weather.html")], "L");
    assert_eq!((posted.as_str(), kept.as_str()), ("看图：[天气](weather.html)\n\n<L?file=weather.html|在 still.fail 里查看图表>", "看图：[天气](weather.html)"), "placed already: kept as written");
    assert_eq!(slack_with_files("", &[file("a b.pdf")], "L"), ("<L?file=a%20b.pdf|在 still.fail 里查看附件>".into(), String::new()));
}

#[tokio::test]
async fn an_agent_names_its_chat_once_and_again_only_after_people_said_enough_never_over_peoples_name_nor_while_it_is_open() {
    let r = setup();
    let (web, thread) = r.hub.new_session(NewChat { runtime: RuntimeKind::Claude, profile: None, model: None, effort: None, title: None, created_by: "local".into(), client_key: None }).unwrap();
    r.hub.say(thread.id, "local", "帮我看下这个", vec![], vec![], None).unwrap();
    settle().await;
    let to = format!("EMBER/{}", thread.thread_ts);
    let post = |title: &str| r.call(&web, "chat_post", json!({ "to": to, "text": "ok", "title": title }));
    let named = || r.store.get_thread(thread.id).unwrap().unwrap().auto_title;
    assert_eq!(post("  登录\n排查。 ").await.unwrap(), format!("Posted to {to}. Titled the chat \"登录 排查\"."));
    assert_eq!(named().as_deref(), Some("登录 排查"));
    assert_eq!(post("登录 排查").await.unwrap(), format!("Posted to {to}."), "the same name: nothing to say");
    assert!(post("登录问题排查").await.unwrap().contains("Title not changed: people have said too little"));
    for n in 0..5 {
        r.hub.say(thread.id, "local", &format!("再看 {n}"), vec![], vec![], None).unwrap();
    }
    settle().await;
    assert!(post("部署失败").await.unwrap().ends_with("Titled the chat \"部署失败\"."));
    assert_eq!(r.store.auto_title(thread.id).unwrap().changes, 1);
    // Someone has it open: the new name waits for them to leave.
    for n in 0..5 {
        r.hub.say(thread.id, "local", &format!("又一件 {n}"), vec![], vec![], None).unwrap();
    }
    r.store.set_read("local", thread.id, r.store.last_entry(thread.id).unwrap()).unwrap();
    settle().await;
    assert!(post("证书过期").await.unwrap().ends_with("The chat will be titled \"证书过期\" once nobody has it open."));
    assert_eq!(named().as_deref(), Some("部署失败"));
    // A name people gave stays.
    r.store.set_thread_title(thread.id, Some("值班")).unwrap();
    assert!(post("别的").await.unwrap().contains("Title not changed: people named this chat"));
    // No title given: the post as before.
    assert_eq!(r.call(&web, "chat_post", json!({ "to": to, "text": "ok" })).await.unwrap(), format!("Posted to {to}."));
}

#[tokio::test]
async fn a_slack_agent_names_its_list_entry_with_the_same_rename_limits_and_manual_title_protection() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let to = format!("C1/{}", m.thread_ts);
    let post = |title: &str| r.call(&key, "chat_post", json!({ "to": to, "text": "ok", "title": title }));
    let thread = r.thread("C1", &m.thread_ts);
    assert!(post("登录排查").await.unwrap().ends_with("Titled the chat \"登录排查\"."));
    let named = r.thread("C1", &m.thread_ts);
    assert_eq!(named.auto_title.as_deref(), Some("登录排查"));
    assert_eq!(post("登录排查").await.unwrap(), format!("Posted to {to}."));
    assert!(post("部署失败").await.unwrap().contains("people have said too little"));
    for change in 0..3 {
        for n in 0..5 {
            r.accept(&reply(&m, &format!("{}.000100", 20000 + change * 5 + n), "继续排查")).await;
        }
        settle().await;
        let said = post(&format!("新话题 {change}")).await.unwrap();
        if change < 2 {
            assert!(said.contains("Titled the chat"), "{said}");
        } else {
            assert!(said.contains("changed as often as it may be"), "{said}");
        }
    }
    r.store.set_thread_title(thread.id, Some("手动标题")).unwrap();
    assert!(post("自动标题").await.unwrap().contains("people named this chat"));
    let named = r.thread("C1", &m.thread_ts);
    assert_eq!(named.title.as_deref(), Some("手动标题"));
}

#[tokio::test]
async fn a_chat_that_starts_a_watch_may_be_renamed_for_it_at_once() {
    let r = setup();
    let (web, thread) = r.hub.new_session(NewChat { runtime: RuntimeKind::Claude, profile: None, model: None, effort: None, title: None, created_by: "local".into(), client_key: None }).unwrap();
    r.hub.say(thread.id, "local", "帮我盯着 CI", vec![], vec![], None).unwrap();
    settle().await;
    let to = format!("EMBER/{}", thread.thread_ts);
    let post = |title: &str| r.call(&web, "chat_post", json!({ "to": to, "text": "ok", "title": title }));
    assert!(post("CI").await.unwrap().ends_with("Titled the chat \"CI\"."));
    assert!(post("监控 · CI").await.unwrap().contains("Title not changed: people have said too little"));
    let watch = crate::store::JobRow {
        id: "job_w".into(), session_key: web.clone(), name: "盯 CI".into(), command: "sleep 600".into(), cwd: "/".into(), port: None,
        token: "tw".into(), state: "running".into(), pgid: None, exit_code: None, started_at: now_ms(), ended_at: None, restarts: 0,
        log: "/dev/null".into(), watch: true,
    };
    r.store.insert_job(&watch).unwrap();
    assert!(post("监控 · CI").await.unwrap().ends_with("Titled the chat \"监控 · CI\"."), "a watch runs: at once");
}

#[test]
fn titles_are_one_short_line() {
    assert_eq!(super::titles::clean_title("  修一下\n登录。"), "修一下 登录");
    assert_eq!(super::titles::clean_title(&"长".repeat(40)).chars().count(), 30);
    assert_eq!(super::titles::clean_title(" 。 "), "");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_mention_slack_sends_twice_at_once_makes_one_session_without_an_error() {
    let r = Arc::new(setup());
    for i in 0..20 {
        let m = InboundMessage { ts: format!("{}.000001", 100 + i), thread_ts: format!("{}.000001", 100 + i), ..say("<@UBOT> fix the build") };
        // app_mention and message for the same post, handled side by side as the Slack socket does.
        let (a, b) = (r.clone(), r.clone());
        let (ma, mb) = (m.clone(), m.clone());
        let (x, y) = tokio::join!(tokio::spawn(async move { a.accept(&ma).await }), tokio::spawn(async move { b.accept(&mb).await }));
        x.unwrap();
        y.unwrap();
    }
    settle().await;
    let texts = r.chat.texts();
    assert!(!texts.iter().any(|t| t.contains("无法创建会话")), "{texts:?}");
    assert!(r.hub.thread_gates.lock().unwrap().is_empty());
}

#[tokio::test]
async fn a_turn_that_runs_out_of_allowance_goes_on_on_another_account_or_once_the_session_is_changed() {
    let r = setup();
    r.edit(|c| {
        c.profiles[0].models = vec!["opus".into()];
        let mut p = c.profiles[0].clone();
        (p.id, p.name) = ("cc2".into(), "second".into());
        c.profiles.push(p);
    });
    let spent = |message: &str| TurnOutcome::Failed { reason: crate::runtime::claude::classify_result(message), message: message.into() };
    let m = message();
    r.accept(&m).await;
    settle().await;
    let first = r.claude.last();
    let key = first.options.route.clone();
    let on = r.session(&key).profile;
    // Left to the station: another account takes it on, in a process of its own, and goes on.
    first.end(spent("You've hit your session limit · resets 3:40am (Asia/Tokyo)"));
    settle().await;
    assert!(first.disposed(), "its process ran on the account left");
    let second = r.claude.last();
    assert_eq!(r.claude.count(), 2);
    assert_ne!(second.options.profile.id, on);
    assert_eq!(r.session(&key).profile, second.options.profile.id);
    assert!(!r.session(&key).profile_pinned);
    assert!(r.chat.texts().iter().all(|t| !t.contains("额度")), "it just goes on, saying nothing");
    assert_eq!(second.prompts(), vec![crate::instructions::GO_ON_AFTER_SPENT.to_string()]);
    // That one runs out too: none left, so it says so and waits.
    second.end(spent("usage limit reached"));
    settle().await;
    assert_eq!(r.claude.count(), 2, "no account left to go on with");
    assert!(matches(&r.chat.last_text(), &["触发额度或限流", "usage limit reached"]));
    // Changed by hand (here: kept to the first again): it goes on by itself.
    let change = SessionChange { profile: Some(Some(on.clone())), model: None, effort: None };
    r.hub.configure(&key, change).await.unwrap();
    settle().await;
    let third = r.claude.last();
    assert_eq!(r.claude.count(), 3);
    assert_eq!(third.options.profile.id, on);
    assert_eq!(third.prompts(), vec![crate::instructions::GO_ON_AFTER_SPENT.to_string()]);
    // A change after a turn that ended well starts nothing.
    r.call(&key, "chat_post", json!({ "to": format!("C1/{}", m.thread_ts), "text": "done", "kind": "final" })).await.unwrap();
    third.complete();
    settle().await;
    r.hub.configure(&key, SessionChange { profile: Some(None), model: None, effort: None }).await.unwrap();
    settle().await;
    assert_eq!(r.claude.count(), 3);
}

#[tokio::test]
async fn a_post_carries_a_card_kept_with_it_and_checked() {
    let r = setup();
    let (web, thread) = r.hub.new_session(NewChat { runtime: RuntimeKind::Claude, profile: None, model: None, effort: None, title: None, created_by: "ada@x.com".into(), client_key: None }).unwrap();
    r.hub.say(thread.id, "ada@x.com", "fix the spacing", vec![], vec![], None).unwrap();
    settle().await;
    let to = format!("EMBER/{}", thread.thread_ts);
    let kept = |r: &Rig| {
        let n = r.said(thread.id).last().unwrap().n;
        r.store.entries_between(thread.id, n, n).unwrap().remove(0)
    };
    let options = json!([
        { "label": " 按今天累计 ", "detail": "重连不清零，零点归零", "recommended": true },
        { "label": "先不改", "detail": "", "recommended": false },
    ]);
    let shown = json!([{ "label": "按今天累计", "detail": "重连不清零，零点归零", "recommended": true }, { "label": "先不改" }]);
    // An options card, with the turn ending need_help: the card is the message's, the state the turn's.
    let said = r.call(&web, "chat_post", json!({ "to": to, "text": "「共」改成按今天累计吗？", "kind": "need_help", "need": "选统计口径", "card": { "type": "options", "options": options } })).await.unwrap();
    assert!(said.starts_with(&format!("Posted to {to}, and recorded state need_human. People can pick: 按今天累计 (recommended); 先不改;")), "{said}");
    let entry = kept(&r);
    assert_eq!(entry.card, Some(json!({ "type": "options", "options": shown })));
    assert_eq!(entry.options, Some(shown.clone()), "kept as options too: what stations and clients from before cards read");
    assert_eq!(entry.declared.as_deref(), Some("need_help"));
    // A text card, on a progress post (no kind): any post may carry one.
    let said = r.call(&web, "chat_post", json!({ "to": to, "text": "测试 key 是多少？", "card": { "type": "text", "placeholder": " sk_test_… " } })).await.unwrap();
    assert!(said.starts_with(&format!("Posted to {to}. People can write their answer")), "{said}");
    let entry = kept(&r);
    assert_eq!((entry.card, entry.options, entry.declared), (Some(json!({ "type": "text", "placeholder": "sk_test_…" })), None, None));
    r.call(&web, "chat_post", json!({ "to": to, "text": "名字？", "card": "{\"type\": \"text\"}" })).await.unwrap();
    assert_eq!(kept(&r).card, Some(json!({ "type": "text" })), "as JSON text, from a runtime whose tool list is from before cards");
    // need_decision, from before cards: an options card, the turn need_help needing what it asks.
    let said = r.call(&web, "chat_post", json!({ "to": to, "text": "**「共」改成按今天累计吗？**\n细节", "kind": "need_decision", "options": options })).await.unwrap();
    assert!(said.contains("recorded state need_human. People can pick"), "{said}");
    assert_eq!((kept(&r).card, kept(&r).declared), (Some(json!({ "type": "options", "options": shown })), Some("need_help".into())));
    assert_eq!(r.store.last_turn(&web).unwrap().unwrap().need.as_deref(), Some("「共」改成按今天累计吗？"), "it needs what the post asks");
    // Options as JSON text, asking with block; a bare phrase is a label.
    let said = r.call(&web, "chat_post", json!({ "to": to, "text": "选哪个？", "kind": "block", "options": "[\"A\", {\"label\": \"B\"}]" })).await.unwrap();
    assert!(said.contains("recorded state need_human."), "{said}");
    assert_eq!(kept(&r).options, Some(json!([{ "label": "A" }, { "label": "B" }])));
    // Options without a kind: an options card all the same.
    r.call(&web, "chat_post", json!({ "to": to, "text": "顺便：哪个？", "options": [{ "label": "A" }] })).await.unwrap();
    assert_eq!(kept(&r).card, Some(json!({ "type": "options", "options": [{ "label": "A" }] })));
    // A post without a card keeps none.
    r.call(&web, "chat_post", json!({ "to": to, "text": "进度" })).await.unwrap();
    assert_eq!((kept(&r).card, kept(&r).options), (None, None));
    let refused = |args: Value| {
        let r = &r;
        let web = web.clone();
        async move { r.call(&web, "chat_post", args).await.unwrap_err().to_string() }
    };
    let one = json!([{ "label": "A" }]);
    assert!(refused(json!({ "to": to, "text": "x", "card": { "type": "poll" } })).await.contains("unknown card type \"poll\": the types known are options, text"));
    assert!(refused(json!({ "to": to, "text": "x", "card": {} })).await.contains("one of options, text"));
    assert!(refused(json!({ "to": to, "text": "x", "card": ["A"] })).await.contains("card must be an object"));
    assert!(refused(json!({ "to": to, "text": "x", "card": { "type": "options" } })).await.contains("an options card has options"));
    assert!(refused(json!({ "to": to, "text": "x", "card": { "type": "options", "options": one }, "options": one })).await.contains("not also as options"));
    assert!(refused(json!({ "to": to, "text": "x", "card": { "type": "text", "placeholder": "字".repeat(81) } })).await.contains("at most 80"));
    assert!(refused(json!({ "to": to, "text": "x", "kind": "need_help", "card": { "type": "text" } })).await.contains("need is required"));
    assert!(refused(json!({ "to": to, "text": "x", "kind": "need_decision" })).await.contains("carries options"));
    assert!(refused(json!({ "to": to, "text": "x", "kind": "need_decision", "options": [] })).await.contains("1 to 6"));
    let seven: Vec<Value> = (0..7).map(|i| json!({ "label": format!("选项{i}") })).collect();
    assert!(refused(json!({ "to": to, "text": "x", "card": { "type": "options", "options": seven } })).await.contains("1 to 6"));
    assert!(refused(json!({ "to": to, "text": "x", "kind": "need_decision", "options": [{ "label": " " }] })).await.contains("label is empty"));
    assert!(refused(json!({ "to": to, "text": "x", "kind": "need_decision", "options": [{ "label": "A" }, { "label": "A" }] })).await.contains("repeats"));
    assert!(refused(json!({ "to": to, "text": "x", "kind": "need_decision", "options": [{ "label": "A", "recommended": true }, { "label": "B", "recommended": true }] })).await.contains("only one"));
    assert!(refused(json!({ "to": to, "text": "x", "kind": "need_decision", "options": { "label": "A" } })).await.contains("must be an array"));
    assert!(refused(json!({ "to": to, "text": "x", "kind": "need_decision", "options": "not json" })).await.contains("must be an array"));
    assert!(refused(json!({ "to": to, "files": [], "card": { "type": "text" } })).await.contains("text is empty"));
}

#[tokio::test]
async fn a_state_says_which_message_it_is_about_the_pending_card_by_default() {
    let r = setup();
    let (web, thread) = r.hub.new_session(NewChat { runtime: RuntimeKind::Claude, profile: None, model: None, effort: None, title: None, created_by: "ada@x.com".into(), client_key: None }).unwrap();
    r.hub.say(thread.id, "ada@x.com", "上线吧", vec![], vec![], None).unwrap();
    settle().await;
    let to = format!("EMBER/{}", thread.thread_ts);
    let last = || r.store.last_turn(&web).unwrap().unwrap();
    let about = || last().about.map(|a| (a.thread, a.seq, a.ts));
    // need_help after a card: about the card, by default.
    r.call(&web, "chat_post", json!({ "to": to, "text": "合吗？", "card": { "type": "options", "options": [{ "label": "合" }] } })).await.unwrap();
    let card = r.said(thread.id).last().unwrap().clone();
    r.call(&web, "chat_post", json!({ "to": to, "text": "等你看一下", "kind": "need_help", "need": "决定合不合" })).await.unwrap();
    r.claude.last().complete();
    settle().await;
    assert_eq!(about(), Some((thread.id, card.n, card.ts.clone())));
    let turn = serde_json::to_value(last()).unwrap();
    assert_eq!(turn["about"], json!({ "thread": thread.id, "seq": card.n, "ts": card.ts }), "as the clients read it");
    // all_done about the message with the result, given by its ts; with chat_state too.
    r.hub.say(thread.id, "ada@x.com", "合", vec![], vec![], None).unwrap();
    settle().await;
    r.call(&web, "chat_post", json!({ "to": to, "text": "已合进 main" })).await.unwrap();
    let result = r.said(thread.id).last().unwrap().clone();
    assert_eq!(r.call(&web, "chat_state", json!({ "kind": "all_done", "done": "已合进 main 82f108a5", "about": result.ts })).await.unwrap(), "Recorded state all_done.");
    r.claude.last().complete();
    settle().await;
    assert_eq!(about(), Some((thread.id, result.n, result.ts.clone())));
    // waiting about the message saying what was started; need_help with no card waiting is about nothing.
    r.hub.say(thread.id, "ada@x.com", "再跑一遍测试", vec![], vec![], None).unwrap();
    settle().await;
    r.call(&web, "chat_post", json!({ "to": to, "text": "测试开始跑了" })).await.unwrap();
    let started = r.said(thread.id).last().unwrap().clone();
    r.call(&web, "chat_state", json!({ "kind": "waiting", "seconds": 60, "for": "测试跑完", "about": started.ts })).await.unwrap();
    r.claude.last().complete();
    settle().await;
    assert_eq!(about().map(|a| a.1), Some(started.n));
    r.hub.say(thread.id, "ada@x.com", "怎样了", vec![], vec![], None).unwrap();
    settle().await;
    r.call(&web, "chat_post", json!({ "to": to, "text": "卡住了", "kind": "need_help", "need": "要 key" })).await.unwrap();
    r.claude.last().complete();
    settle().await;
    assert_eq!(about(), None, "no card waiting, none given");
    // A ts not in the chat, or about with no kind: refused.
    r.hub.say(thread.id, "ada@x.com", "给你", vec![], vec![], None).unwrap();
    settle().await;
    assert!(r.call(&web, "chat_post", json!({ "to": to, "text": "x", "kind": "all_done", "done": "已合进 main 82f108a5", "about": "1.000001" })).await.unwrap_err().to_string().contains("about must be the ts of a message"));
    assert!(r.call(&web, "chat_state", json!({ "kind": "all_done", "done": "已合进 main 82f108a5", "about": "1.000001" })).await.unwrap_err().to_string().contains("about must be the ts of a message"));
    assert!(r.call(&web, "chat_post", json!({ "to": to, "text": "x", "about": started.ts })).await.unwrap_err().to_string().contains("about goes with kind"));
}

#[tokio::test]
async fn options_are_refused_in_a_slack_thread() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let refused = r.call(&key, "chat_post", json!({ "to": format!("C1/{}", m.thread_ts), "text": "选哪个？", "kind": "need_decision", "options": [{ "label": "A" }] })).await.unwrap_err();
    assert!(refused.to_string().contains("only in still.fail chats"), "{refused}");
    let refused = r.call(&key, "chat_post", json!({ "to": format!("C1/{}", m.thread_ts), "text": "key？", "card": { "type": "text" } })).await.unwrap_err();
    assert!(refused.to_string().contains("only in still.fail chats"), "{refused}");
}

#[tokio::test]
async fn a_card_is_pending_until_a_person_writes_and_a_newer_one_replaces_it() {
    let r = setup();
    let (web, thread) = r.hub.new_session(NewChat { runtime: RuntimeKind::Claude, profile: None, model: None, effort: None, title: None, created_by: "ada@x.com".into(), client_key: None }).unwrap();
    r.hub.say(thread.id, "ada@x.com", "fix the spacing", vec![], vec![], None).unwrap();
    settle().await;
    let to = format!("EMBER/{}", thread.thread_ts);
    let pending = || r.store.pending_card(thread.id).unwrap().map(|(m, card)| (m.n, card));
    assert_eq!(pending(), None);
    // Help asked for asks nothing to pick.
    r.call(&web, "chat_post", json!({ "to": to, "text": "要 key", "kind": "need_help", "need": "要 Stripe 的测试 key" })).await.unwrap();
    assert_eq!(pending(), None);
    r.call(&web, "chat_post", json!({ "to": to, "text": "合吗？", "kind": "need_decision", "options": [{ "label": "合" }] })).await.unwrap();
    let first = r.said(thread.id).last().unwrap().n;
    assert_eq!(pending(), Some((first, json!({ "type": "options", "options": [{ "label": "合" }] }))));
    // The agent saying more without options leaves it pending; only people answer it.
    r.call(&web, "chat_post", json!({ "to": to, "text": "顺便说一下进度" })).await.unwrap();
    assert_eq!(pending().map(|p| p.0), Some(first));
    // A newer one replaces it.
    r.call(&web, "chat_post", json!({ "to": to, "text": "还是先问这个：留哪个？", "kind": "need_decision", "options": [{ "label": "留旧的" }, { "label": "留新的" }] })).await.unwrap();
    let second = r.said(thread.id).last().unwrap().n;
    assert_eq!(pending().map(|p| p.0), Some(second));
    // Any person's message after it answers it, quoting it or not.
    r.hub.say(thread.id, "bob@x.com", "都不要，换个思路", vec![], vec![], None).unwrap();
    assert_eq!(pending(), None);
    r.call(&web, "chat_post", json!({ "to": to, "text": "那这样？", "kind": "need_decision", "options": [{ "label": "好" }] })).await.unwrap();
    assert!(pending().is_some());
    // A text card replaces it as well, on a post with no kind.
    r.call(&web, "chat_post", json!({ "to": to, "text": "域名填哪个？", "card": { "type": "text", "placeholder": "example.com" } })).await.unwrap();
    let text = r.said(thread.id).last().unwrap().n;
    assert_eq!(pending(), Some((text, json!({ "type": "text", "placeholder": "example.com" }))));
    r.hub.say(thread.id, "ada@x.com", "still.fail", vec![], vec![], None).unwrap();
    assert_eq!(pending(), None);
}

#[tokio::test]
async fn a_turn_ends_all_done_needing_a_decision_or_help_or_waiting_and_the_words_from_before_still_count() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let to = format!("C1/{}", m.thread_ts);
    let last = || r.store.last_turn(&key).unwrap().unwrap();
    // need_help says what is needed: kept with the turn; refused without it.
    let refused = r.call(&key, "chat_post", json!({ "to": to, "text": "卡住了", "kind": "need_help" })).await.unwrap_err();
    assert!(refused.to_string().contains("need is required"), "{refused}");
    let said = r.call(&key, "chat_post", json!({ "to": to, "text": "卡住了", "kind": "need_human", "need": " 要 Stripe 的测试 key " })).await.unwrap();
    assert_eq!(said, format!("Posted to {to}, and recorded state need_human."));
    r.claude.last().complete();
    settle().await;
    let turn = last();
    assert_eq!((turn.declared.as_deref(), turn.ending.as_deref(), turn.need.as_deref()), (Some("block"), Some("need_help"), Some("要 Stripe 的测试 key")), "clients from before read block");
    assert_eq!(r.claude.last().prompts().len(), 1, "a state: not nudged");
    // need goes only with need_help; need_decision only posted, with options.
    r.accept(&reply(&m, "9999.1", "给你 key")).await;
    settle().await;
    assert!(r.call(&key, "chat_state", json!({ "kind": "all_done", "need": "x", "done": "y" })).await.unwrap_err().to_string().contains("only with kind \"need_human\""));
    assert!(r.call(&key, "chat_state", json!({ "kind": "all_done" })).await.unwrap_err().to_string().contains("done is required"));
    // done is a reason people can trust, not the word done.
    for empty in ["做完了", " 完成。", "已完成", "Done!", "ok", "好了", "全部搞定"] {
        let refused = r.call(&key, "chat_state", json!({ "kind": "all_done", "done": empty })).await.unwrap_err().to_string();
        assert!(refused.contains("done must say why nothing in the chat is left"), "{empty}: {refused}");
    }
    assert!(r.call(&key, "chat_state", json!({ "kind": "need_help", "need": "x", "done": "y" })).await.unwrap_err().to_string().contains("only with kind \"all_done\""));
    assert!(r.call(&key, "chat_state", json!({ "kind": "need_decision" })).await.unwrap_err().to_string().contains("posted with chat_post"));
    assert!(r.call(&key, "chat_state", json!({ "kind": "need_help" })).await.unwrap_err().to_string().contains("need is required"));
    assert!(r.call(&key, "chat_state", json!({ "kind": "done" })).await.unwrap_err().to_string().contains("all_done"));
    assert_eq!(r.call(&key, "chat_state", json!({ "kind": "need_help", "need": "确认一下要不要上线" })).await.unwrap(), "Recorded state need_human.");
    r.claude.last().complete();
    settle().await;
    assert_eq!((last().ending.as_deref(), last().need.as_deref()), (Some("need_help"), Some("确认一下要不要上线")));
    // all_done says what the chat ends with, kept as need is.
    r.accept(&reply(&m, "9999.2", "上了")).await;
    settle().await;
    assert_eq!(r.call(&key, "chat_state", json!({ "kind": "all_done", "done": "已合并所有代码" })).await.unwrap(), "Recorded state all_done.");
    r.claude.last().complete();
    settle().await;
    assert_eq!((last().ending.as_deref(), last().need.as_deref()), (Some("all_done"), Some("已合并所有代码")));
    // The words from before: block needs no need; final is all_done.
    r.accept(&reply(&m, "9999.25", "上吧")).await;
    settle().await;
    assert_eq!(r.call(&key, "chat_state", json!({ "kind": "block" })).await.unwrap(), "Recorded state need_human.");
    r.claude.last().complete();
    settle().await;
    assert_eq!((last().declared.as_deref(), last().ending.as_deref(), last().need.as_deref()), (Some("block"), Some("need_help"), None));
    r.accept(&reply(&m, "9999.3", "好了吗"))
        .await;
    settle().await;
    assert_eq!(r.call(&key, "chat_state", json!({ "kind": "final" })).await.unwrap(), "Recorded state all_done.");
    r.claude.last().complete();
    settle().await;
    assert_eq!((last().declared.as_deref(), last().ending.as_deref()), (Some("final"), Some("all_done")));
    let thread = r.thread("C1", &m.thread_ts);
    assert_eq!(r.said(thread.id).iter().filter_map(|m| m.declared.clone()).collect::<Vec<_>>(), ["need_help"], "posts keep today's words");
}

#[tokio::test]
async fn codex_model_efforts_validate_new_chats_changes_and_pinned_accounts() {
    let r = setup();
    r.edit(|c| {
        let p = c.profiles.iter_mut().find(|p| p.id == "cx").unwrap();
        p.models = vec!["gpt-6-astra".into()];
        let mut second = p.clone();
        second.id = "limited".into();
        c.profiles.push(second);
    });
    r.hub.set_profile_health(Arc::new(|id| {
        let levels = if id == "limited" { json!(["low", "medium", "high", "xhigh", "max"]) } else { json!(["low", "medium", "high", "xhigh", "max", "ultra"]) };
        crate::pool::ProfileHealth {
            check: Some(serde_json::from_value(json!({"state": "ok", "detail": "", "models": ["gpt-6-astra"], "checkedAt": 0,
                "modelEfforts": {"codex": {"gpt-6-astra": levels}}
            })).unwrap()),
            ..Default::default()
        }
    }));
    let new = |profile: Option<&str>, effort: &str| NewChat {
        runtime: RuntimeKind::Codex, profile: profile.map(String::from), model: Some("openai/gpt-6-astra".into()),
        effort: Some(effort.into()), title: None, created_by: "local".into(), client_key: None,
    };
    let (key, _) = r.hub.new_session(new(None, "max")).unwrap();
    assert_eq!(r.session(&key).effort.as_deref(), Some("max"));
    assert!(r.hub.new_session(new(None, "minimal")).is_err());
    assert!(r.hub.new_session(new(None, "ultra")).is_err());
    let (pinned, _) = r.hub.new_session(new(Some("cx"), "ultra")).unwrap();
    assert_eq!(r.session(&pinned).effort.as_deref(), Some("ultra"));
    // A profile change must not carry an unsupported depth to the destination.
    assert!(r.hub.configure(&pinned, SessionChange { profile: Some(Some("limited".into())), model: None, effort: None }).await.is_err());
    assert!(r.hub.configure(&pinned, SessionChange { profile: Some(None), model: None, effort: None }).await.is_err());
    r.hub.configure(&key, SessionChange { profile: Some(Some("cx".into())), model: None, effort: Some(Some("ultra".into())) }).await.unwrap();
    assert_eq!(r.session(&key).effort.as_deref(), Some("ultra"));
    r.hub.configure(&key, SessionChange { profile: Some(None), model: None, effort: Some(None) }).await.unwrap();
    assert_eq!(r.session(&key).effort, None);
}

#[tokio::test]
async fn a_session_from_before_a_change_is_told_it_once_and_a_new_one_never() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    assert!(!r.claude.last().prompts()[0].contains("still.fail changed how you work"), "a new session has today's instructions");
    r.call(&key, "chat_state", json!({ "kind": "all_done", "done": "答完了它问的事" })).await.unwrap();
    r.claude.last().complete();
    settle().await;
    // As a session from before the notes: told them with its next turn, once.
    r.store.set_told_notes(&key, 0).unwrap();
    r.accept(&reply(&m, "9999.1", "还有一件")).await;
    settle().await;
    let prompts = r.claude.last().prompts();
    assert!(prompts.last().unwrap().starts_with("[still.fail changed how you work"), "{:?}", prompts.last());
    let workspace = r.store.get_session(&key).unwrap().unwrap().workspace;
    let full = std::path::Path::new(&workspace).join(".stillfail-instructions.md");
    assert!(prompts.last().unwrap().contains(&full.to_string_lossy().into_owned()), "it says where today's instructions are");
    assert!(std::fs::read_to_string(&full).unwrap().contains("Messages reach you"), "and they are there");
    assert_eq!(r.store.told_notes(&key).unwrap(), crate::migrations::latest());
    r.call(&key, "chat_state", json!({ "kind": "all_done", "done": "答完了它问的事" })).await.unwrap();
    r.claude.last().complete();
    settle().await;
    r.accept(&reply(&m, "9999.2", "再一件")).await;
    settle().await;
    assert!(!r.claude.last().prompts().last().unwrap().contains("still.fail changed how you work"));
}
