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
    async fn post(&self, thread: &ThreadRef, message: &str, _files: &[Attachment]) -> Result<String> {
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
    async fn abort(&self) {
        self.aborts.fetch_add(1, Ordering::SeqCst);
    }
    async fn dispose(&self) {
        self.disposed.store(true, Ordering::SeqCst);
    }
}

struct FakeDriver {
    runtime: RuntimeKind,
    sessions: Mutex<Vec<Arc<FakeSession>>>,
    /// Runtime session ids that resume fails for.
    unresumable: Mutex<HashSet<String>>,
    next: AtomicU64,
}

impl FakeDriver {
    fn new(runtime: RuntimeKind) -> Arc<FakeDriver> {
        Arc::new(FakeDriver { runtime, sessions: Mutex::default(), unresumable: Mutex::default(), next: AtomicU64::new(1) })
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
            aborts: AtomicUsize::new(0),
            disposed: AtomicBool::new(false),
            busy: AtomicBool::new(false),
            unsteerable: AtomicBool::new(false),
        });
        self.sessions.lock().unwrap().push(session.clone());
        Ok(session)
    }
    async fn shutdown(&self) {}
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
    assert_eq!(posts[0].1, format!("<https://ember.test/o/ws/st/cl%3AC1%3A{}|在 ember 里查看这个会话>", m.thread_ts));
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
async fn the_same_message_delivered_twice_is_handled_once() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    r.accept(&m).await;
    settle().await;
    assert_eq!(r.claude.last().prompts().len(), 1);
}

#[tokio::test]
async fn a_turn_ending_without_final_or_block_is_nudged_then_reported_after_max_nudges() {
    let r = setup_with(Setup { max_nudges: Some(1), ..Setup::default() });
    r.accept(&message()).await;
    settle().await;
    r.claude.last().complete();
    settle().await;
    let prompts = r.claude.last().prompts();
    assert_eq!(prompts.len(), 2);
    assert!(prompts[1].contains("without a final or block state"));
    r.claude.last().complete();
    settle().await;
    assert_eq!(r.claude.last().prompts().len(), 2);
    assert!(r.chat.last_text().contains("没有给出明确结果"));
}

#[tokio::test(start_paused = true)]
async fn a_turn_ending_waiting_is_not_nudged_nor_evicted_and_is_asked_again_when_the_wait_is_over() {
    let r = setup_with(Setup { max_warm_claude: Some(0), warm_minutes: Some(0.0), ..Setup::default() });
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let said = r.call(&key, "chat_state", json!({ "kind": "waiting", "seconds": 1 })).await.unwrap();
    assert!(said.contains("in 10 seconds"), "at least 10: {said}");
    r.claude.last().complete();
    settle().await;
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
async fn a_turn_that_starts_before_the_wait_is_over_ends_it() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    r.call(&key, "chat_state", json!({ "kind": "waiting", "seconds": 60 })).await.unwrap();
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
}

#[tokio::test]
async fn chat_post_with_kind_final_posts_and_settles_the_turn_without_a_nudge() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    settle().await;
    let key = session_key("cl", "C1", &m.thread_ts);
    let to = format!("C1/{}", m.thread_ts);
    assert_eq!(r.call(&key, "chat_post", json!({ "to": to, "text": "**done**", "kind": "final" })).await.unwrap(), format!("Posted to {to}, and recorded state final."));
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
        (AuthorKind::Person, AuthorKind::Agent, key.as_str(), Some("block"))
    );
    assert_eq!(r.store.pending_messages(&key).unwrap().len(), 0, "an agent's own post is not delivered back to it");
    let history = r.call(&key, "chat_history", json!({ "to": to })).await.unwrap();
    assert!(matches(&history, &["from=\"U1\" ts=\"", "\">\n<@UBOT> look", "from=\"you\" ts=\"", "\">\nlooking"]), "{history}");
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
async fn chat_state_rejects_kinds_other_than_final_and_block() {
    let r = setup();
    let m = message();
    r.accept(&m).await;
    let refused = r.call(&session_key("cl", "C1", &m.thread_ts), "chat_state", json!({ "kind": "wait" })).await.unwrap_err();
    assert!(refused.to_string().contains("final\" or \"block"), "{refused}");
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
    assert_eq!(r.chat.last_text(), "已停止当前任务。");
    assert_eq!(session.prompts().len(), 1, "no nudge after a stop");
}

#[tokio::test]
async fn a_failed_turn_is_reported_to_the_thread_and_not_nudged() {
    let r = setup();
    r.accept(&message()).await;
    settle().await;
    r.claude.last().end(TurnOutcome::Failed { reason: FailureReason::Auth, message: "401 Missing API key".into() });
    settle().await;
    assert!(matches(&r.chat.last_text(), &["认证失败", "401 Missing API key"]));
    assert_eq!(r.claude.last().prompts().len(), 1);
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
    let thread = r.hub.open_chat(&key, "local", Some("排查")).unwrap();
    r.hub.say(thread.id, "local", "现在进展如何？", vec![], vec![]).unwrap();
    settle().await;
    let prompt = r.claude.last().prompts().pop().unwrap();
    assert!(prompt.contains(&format!("<message via=\"web\" connect=\"ember\" thread=\"EMBER/{}\" from=\"管理员 (local)\"", thread.thread_ts)), "{prompt}");
    assert!(prompt.contains("现在进展如何"));
    let to = format!("EMBER/{}", thread.thread_ts);
    assert_eq!(r.call(&key, "chat_post", json!({ "to": to, "text": "快好了", "kind": "final" })).await.unwrap(), format!("Posted to {to}, and recorded state final."));
    let said: Vec<(AuthorKind, String)> = r.said(thread.id).into_iter().map(|x| (x.author_kind, x.text)).collect();
    assert_eq!(said, [(AuthorKind::Person, "现在进展如何？".to_string()), (AuthorKind::Agent, "快好了".into())]);
    assert_eq!(r.chat.texts().len(), 1, "only the Slack thread's own answer went to Slack");
    assert!(r.call(&key, "chat_history", json!({ "to": to })).await.unwrap().contains("现在进展如何"));
    assert!(r.hub.open_chat("nope", "local", None).unwrap_err().to_string().contains("unknown session"));
}

fn new_chat(runtime: RuntimeKind) -> NewChat {
    NewChat { runtime, profile: None, model: None, effort: None, title: None, created_by: "local".into() }
}

#[tokio::test]
async fn a_persons_message_in_a_chat_with_several_agents_reaches_each_of_them_once() {
    let r = setup();
    let one = r.hub.new_session(new_chat(RuntimeKind::Claude)).unwrap();
    let two = r.hub.new_session(new_chat(RuntimeKind::Codex)).unwrap();
    r.hub.add_to_thread(one.1.id, &two.0).unwrap();
    let quote = Quote { author: "Claude".into(), role: Some("agent".into()), ts: Some("1.000001".into()), text: "上一条".into(), comment: "这里".into() };
    r.hub.say(one.1.id, "a@example.com", "你们俩分一下工", vec![], vec![quote]).unwrap();
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
    let (web, thread) = r.hub.new_session(NewChat { runtime: RuntimeKind::Claude, profile: None, model: None, effort: None, title: None, created_by: "local".into() }).unwrap();
    r.hub.say(thread.id, "local", "hi", vec![], vec![]).unwrap();
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
    r.hub.auto_archive(later).unwrap();
    assert_eq!(r.session(&web).archived_by.as_deref(), Some(AUTO));
    assert!(r.store.get_thread(thread.id).unwrap().unwrap().hidden_at.is_some(), "its own chat with it");
    // Someone writes in the Slack thread again: its session is back.
    r.accept(&reply(&m, "9999.5", "<@UBOT> one more")).await;
    assert_eq!(r.session(&idle).archived_at, None);
    // A chat opened with a session that has one is a chat of its own, archived alone.
    r.hub.archive(&web, false).unwrap();
    let second = r.hub.open_chat(&web, "local", None).unwrap();
    assert_eq!(second.home, None);
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
    r.hub.say(one.1.id, "local", "分一下工", vec![], vec![]).unwrap();
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
    let shown: Vec<(AuthorKind, &str, &str)> = said.iter().map(|m| (m.author_kind, m.author.as_str(), m.text.as_str())).collect();
    assert!(shown[0].2.starts_with("接着本机 Claude Code 在"), "{:?}", shown[0]);
    assert_eq!(&shown[1..], &[(AuthorKind::Person, "local", "fix   the\nbuild"), (AuthorKind::Agent, key.as_str(), "Looking.\n\nFixed."), (AuthorKind::Person, "local", "thanks")]);
    settle().await;
    assert_eq!(r.claude.count(), 0, "what was said before is not handed to the agent again");

    r.hub.say(thread.id, "local", "and the tests", vec![], vec![]).unwrap();
    settle().await;
    let opened = r.claude.last();
    assert_eq!(opened.options.resume.as_deref(), Some(found.id.as_str()));
    assert_eq!(opened.options.cwd, project);
    assert_eq!(opened.options.instructions, "", "its system prompt is left as it began");
    assert_eq!(opened.prompts().len(), 1);
    let first = &opened.prompts()[0];
    assert!(first.starts_with("This session began in a terminal and now goes on in ember"), "{first}");
    assert!(first.contains("<ember-instructions>") && first.contains("and the tests"));
    assert!(first.contains(&format!("- Project directory: {}.", project.display())));
    opened.complete();
    settle().await;
    r.hub.say(thread.id, "local", "one more", vec![], vec![]).unwrap();
    settle().await;
    let next = r.claude.last().prompts().last().cloned().unwrap();
    assert!(!next.contains("<ember-instructions>"), "said once: {next}");

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
