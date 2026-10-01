//! Topics: their current values, who subscribes, and when a value goes out.
//!
//! A topic comes alive with its first subscriber (the store calls the
//! [`Source`] to start it) and is stopped a minute after its last one leaves;
//! its value stays cached until then, so a UI that re-subscribes gets it at
//! once. `set` stores a value and schedules its emission; emissions are
//! coalesced over [`COALESCE_MS`], one window for all topics, so topics changed
//! together go out together, in the order they changed; a topic's first value, which a page opening waits on, goes
//! out on the next turn instead, with whatever else is pending. A subscriber's first message is the whole value, the
//! next ones only what changed since the last one sent ([`delta`]), and an
//! unchanged value sends nothing.
//!
//! Code inside the core can [`watch`](Store::watch) a topic: it counts as a
//! subscriber and hears each change at once. A topic whose value is derived
//! from others is [`invalidate`](Store::invalidate)d instead of set: its source
//! computes it when the emission goes out, so a burst of changes costs one
//! computation.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::{Rc, Weak};

use futures::FutureExt;
use serde_json::Value;

use crate::delta::{self, Op};
use crate::error::CoreError;
use crate::host::Host;
use crate::protocol::{ClientId, CoreMessage, RequestId, Topic};

pub const COALESCE_MS: u64 = 50;
pub const EVICT_AFTER_MS: u64 = 60_000;

/// Whoever produces a kind of topic (the station module, the accounts module).
pub trait Source {
    /// The topic got its first subscriber: fetch it and keep it current.
    fn start(&self, topic: &Topic);
    /// Nobody has subscribed for a while: stop streams and timers for it.
    fn stop(&self, topic: &Topic);
    /// The current value of a topic marked stale with [`Store::invalidate`], as it goes out; `None` while it has none.
    fn compute(&self, _topic: &Topic) -> Option<Result<Value, CoreError>> {
        None
    }
}

/// Keeps a watched topic subscribed; dropping it lets the topic go like a UI unsubscribing.
pub struct Watch {
    store: Weak<Store>,
    topic: Topic,
    id: u64,
}

impl Drop for Watch {
    fn drop(&mut self) {
        if let Some(store) = self.store.upgrade() {
            store.unwatch(&self.topic, self.id);
        }
    }
}

pub struct Store {
    host: Rc<dyn Host>,
    /// For the timers the store spawns; they must not keep it alive.
    me: Weak<Store>,
    inner: RefCell<Inner>,
}

#[derive(Default)]
struct Inner {
    topics: HashMap<Topic, Entry>,
    subscriptions: HashMap<(ClientId, RequestId), Topic>,
    source: Option<Rc<dyn Source>>,
    /// Numbers each time a topic loses its last subscriber, so a stale eviction timer can tell.
    idle_count: u64,
    watch_count: u64,
    /// Topics changed since the last emission. One window for all of them, so
    /// what one event changes (a live step ending, the timeline growing) goes out together.
    pending: Vec<Topic>,
    window_open: bool,
    /// A flush on the next turn is on its way (a topic's first value).
    soon: bool,
    /// The values of the topics the data center holds (`data.rs`): read there, never kept here but as sent.
    held: Option<Rc<dyn Fn(&Topic) -> Option<Value>>>,
    /// The minute clock runs: times in words go out fresh each minute while anything is shown.
    clock: bool,
    /// The clock is wanted (a UI's core; tests leave it off, their time is their own).
    clock_on: bool,
    /// Values go out through their shapes (client/shapes); the store's own tests send whatever they like.
    shaped: bool,
}

#[derive(Default)]
struct Entry {
    value: Option<Result<Value, CoreError>>,
    /// The value last sent to the subscribers; the next emission is the difference to it.
    sent: Option<Result<Value, CoreError>>,
    subscribers: Vec<(ClientId, RequestId)>,
    /// Watches from inside the core, called on every change.
    watchers: Vec<(u64, Rc<dyn Fn()>)>,
    /// Invalidated: the source computes the value when it goes out.
    stale: bool,
    /// Waiting in `pending`.
    emit_scheduled: bool,
    /// Set while nobody subscribes: the eviction timer that may drop the topic.
    idle: Option<u64>,
}

impl Store {
    pub fn new(host: Rc<dyn Host>) -> Rc<Store> {
        Rc::new_cyclic(|me| Store { host, me: me.clone(), inner: RefCell::default() })
    }

    /// Routes each kind of topic to its producer; set once by `Core` at construction.
    pub fn set_source(&self, source: Rc<dyn Source>) {
        self.inner.borrow_mut().source = Some(source);
    }

    /// Where the values of the data center's topics are read: they have no value of their own here.
    pub fn set_held(&self, held: Rc<dyn Fn(&Topic) -> Option<Value>>) {
        self.inner.borrow_mut().held = Some(held);
    }

    fn held(&self, topic: &Topic) -> Option<Value> {
        let held = self.inner.borrow().held.clone()?;
        held(topic)
    }

    /// A topic starts: the source brings it up to date; what the data center already has of it goes out at once.
    fn start(&self, topic: &Topic, source: Option<Rc<dyn Source>>) {
        if let Some(source) = source {
            source.start(topic);
        }
        if self.held(topic).is_some() {
            self.invalidate(topic);
        }
    }

    /// The data center changed a topic's value: it goes out (computed from there), and whatever watches it hears now.
    pub fn changed(&self, topic: &Topic) {
        self.invalidate(topic);
        let watchers = match self.inner.borrow().topics.get(topic) {
            Some(entry) => watchers(entry),
            None => return,
        };
        watchers.iter().for_each(|w| w());
    }

    /// Adds a subscriber; sends the cached value (or error) at once if there is one, and starts the topic if it was not live.
    pub fn subscribe(&self, client: ClientId, id: RequestId, topic: Topic) {
        // The same request id again means the UI replaced that subscription.
        self.unsubscribe(client, id);
        let (cached, started, source) = {
            let mut inner = self.inner.borrow_mut();
            inner.subscriptions.insert((client, id), topic.clone());
            let started = !inner.topics.contains_key(&topic);
            let entry = inner.topics.entry(topic.clone()).or_default();
            entry.subscribers.push((client, id));
            entry.idle = None;
            // What the other subscribers have: a change still on its way comes as a delta to that.
            let cached = entry.sent.clone();
            (cached, started, inner.source.clone())
        };
        if let Some(value) = cached {
            self.host.emit(client, Out::whole(value).to(id));
        }
        if started {
            self.start(&topic, source);
        }
        self.tick();
    }

    /// Wakes a second past each minute, while any topic is live, to send again what shows times in words ("3 分钟前",
    /// a day's heading); stops when none is.
    /// Sends every value through its shape (present::conform).
    pub fn set_shaped(&self) {
        self.inner.borrow_mut().shaped = true;
    }

    /// Starts the minute clock (see `tick`).
    pub fn set_clock(&self) {
        self.inner.borrow_mut().clock_on = true;
        self.tick();
    }

    fn tick(&self) {
        {
            let mut inner = self.inner.borrow_mut();
            if !inner.clock_on || std::mem::replace(&mut inner.clock, true) {
                return;
            }
        }
        let now = self.host.now_ms();
        let next = ((now / 60_000.0).floor() + 1.0) * 60_000.0 + 1000.0;
        let sleep = self.host.sleep((next - now).max(0.0) as u64);
        let store = self.me.clone();
        self.host.spawn(
            async move {
                sleep.await;
                let Some(store) = store.upgrade() else { return };
                store.inner.borrow_mut().clock = false;
                let shown: Vec<Topic> = store.inner.borrow().topics.iter()
                    .filter(|(t, e)| !e.subscribers.is_empty() && crate::present::ticks(t))
                    .map(|(t, _)| t.clone()).collect();
                if shown.is_empty() {
                    return;
                }
                for topic in &shown {
                    store.invalidate(topic);
                }
                store.tick();
            }
            .boxed_local(),
        );
    }

    pub fn unsubscribe(&self, client: ClientId, id: RequestId) {
        let mut inner = self.inner.borrow_mut();
        let Some(topic) = inner.subscriptions.remove(&(client, id)) else { return };
        let Some(entry) = inner.topics.get_mut(&topic) else { return };
        entry.subscribers.retain(|s| *s != (client, id));
        drop(inner);
        self.release(topic);
    }

    /// Subscribes from inside the core: starts the topic if it was not live and
    /// calls `on_change` after each `set` or `update` of it, until the watch is dropped.
    pub fn watch(&self, topic: &Topic, on_change: Rc<dyn Fn()>) -> Watch {
        let (id, started, source) = {
            let mut inner = self.inner.borrow_mut();
            inner.watch_count += 1;
            let id = inner.watch_count;
            let started = !inner.topics.contains_key(topic);
            let entry = inner.topics.entry(topic.clone()).or_default();
            entry.watchers.push((id, on_change));
            entry.idle = None;
            (id, started, inner.source.clone())
        };
        if started {
            self.start(topic, source);
        }
        Watch { store: self.me.clone(), topic: topic.clone(), id }
    }

    fn unwatch(&self, topic: &Topic, id: u64) {
        let mut inner = self.inner.borrow_mut();
        let Some(entry) = inner.topics.get_mut(topic) else { return };
        entry.watchers.retain(|(w, _)| *w != id);
        drop(inner);
        self.release(topic.clone());
    }

    /// Starts the eviction grace if nobody subscribes to or watches the topic any more.
    fn release(&self, topic: Topic) {
        let mut inner = self.inner.borrow_mut();
        inner.idle_count += 1;
        let idle = inner.idle_count;
        let Some(entry) = inner.topics.get_mut(&topic) else { return };
        if !entry.subscribers.is_empty() || !entry.watchers.is_empty() {
            return;
        }
        entry.idle = Some(idle);
        drop(inner);
        let store = self.me.clone();
        let sleep = self.host.sleep(EVICT_AFTER_MS);
        self.host.spawn(
            async move {
                sleep.await;
                if let Some(store) = store.upgrade() {
                    store.evict(&topic, idle);
                }
            }
            .boxed_local(),
        );
    }

    /// A UI went away: drops all its subscriptions.
    pub fn drop_client(&self, client: ClientId) {
        let ids: Vec<RequestId> = self.inner.borrow().subscriptions.keys().filter(|(c, _)| *c == client).map(|(_, id)| *id).collect();
        for id in ids {
            self.unsubscribe(client, id);
        }
    }

    /// Stores a topic's new value (or its error) and schedules sending it to the topic's subscribers.
    /// A topic that is not live is ignored: it is a late answer for a topic already stopped.
    pub fn set(&self, topic: &Topic, value: Result<Value, CoreError>) {
        let mut inner = self.inner.borrow_mut();
        let Some(entry) = inner.topics.get_mut(topic) else { return };
        entry.value = Some(value);
        let schedule = !std::mem::replace(&mut entry.emit_scheduled, true);
        let watchers = watchers(entry);
        drop(inner);
        if schedule {
            self.schedule_emit(topic);
        }
        watchers.iter().for_each(|w| w());
    }

    /// Changes a topic's value in place (e.g. appending live timeline entries), then schedules sending it.
    /// Does nothing if the topic has no value yet.
    pub fn update(&self, topic: &Topic, change: &mut dyn FnMut(&mut Value)) {
        let mut inner = self.inner.borrow_mut();
        let Some(entry) = inner.topics.get_mut(topic) else { return };
        let Some(Ok(value)) = entry.value.as_mut() else { return };
        change(value);
        let schedule = !std::mem::replace(&mut entry.emit_scheduled, true);
        let watchers = watchers(entry);
        drop(inner);
        if schedule {
            self.schedule_emit(topic);
        }
        watchers.iter().for_each(|w| w());
    }

    /// Marks a live topic's value out of date and schedules its emission; the
    /// source's [`Source::compute`] gives the value then.
    pub fn invalidate(&self, topic: &Topic) {
        let mut inner = self.inner.borrow_mut();
        let Some(entry) = inner.topics.get_mut(topic) else { return };
        entry.stale = true;
        let schedule = !std::mem::replace(&mut entry.emit_scheduled, true);
        drop(inner);
        if schedule {
            self.schedule_emit(topic);
        }
    }

    /// Invalidates every live topic `pick` chooses (a topic of each workspace, and the one of all of them).
    pub fn invalidate_all(&self, pick: impl Fn(&Topic) -> bool) {
        for topic in self.live_topics().into_iter().filter(|t| pick(t)) {
            self.invalidate(&topic);
        }
    }

    /// The topic's value or error; `None` while it has neither. A data center topic's value is read there (its
    /// error, while it has nothing, is kept here).
    pub fn value(&self, topic: &Topic) -> Option<Result<Value, CoreError>> {
        if let Some(value) = self.held(topic) {
            return Some(Ok(value));
        }
        let inner = self.inner.borrow();
        let with_data = inner.held.is_some();
        match inner.topics.get(topic)?.value.clone()? {
            Err(error) => Some(Err(error)),
            // With a data center, a value of its topics here is only what was last sent.
            Ok(value) => (!(with_data && crate::data::holds(topic))).then_some(Ok(value)),
        }
    }

    pub fn get(&self, topic: &Topic) -> Option<Value> {
        self.value(topic)?.ok()
    }

    /// Whether a UI subscribes to the topic now (not only watched, nor in its grace).
    pub fn subscribed(&self, topic: &Topic) -> bool {
        self.inner.borrow().topics.get(topic).is_some_and(|e| !e.subscribers.is_empty())
    }

    /// Topics with at least one subscriber (or within their eviction grace).
    pub fn live_topics(&self) -> Vec<Topic> {
        self.inner.borrow().topics.keys().cloned().collect()
    }

    /// Adds the topic to the next emission, starting its window if none is open.
    fn schedule_emit(&self, topic: &Topic) {
        let mut inner = self.inner.borrow_mut();
        inner.pending.push(topic.clone());
        // Nothing of it shown yet: whoever subscribed is waiting on it (a chat opening), not on it changing again.
        let first = inner.topics.get(topic).is_some_and(|e| e.sent.is_none() && !e.subscribers.is_empty());
        let open = if first { &mut inner.soon } else { &mut inner.window_open };
        if std::mem::replace(open, true) {
            return;
        }
        drop(inner);
        let store = self.me.clone();
        let sleep = self.host.sleep(if first { 0 } else { COALESCE_MS });
        self.host.spawn(
            async move {
                sleep.await;
                if let Some(store) = store.upgrade() {
                    store.flush_pending();
                }
            }
            .boxed_local(),
        );
    }

    /// Sends every topic changed in the window, in the order they first changed.
    fn flush_pending(&self) {
        let pending = {
            let mut inner = self.inner.borrow_mut();
            // Either timer takes all that is pending; the other one, when it comes, finds less or nothing.
            inner.window_open = false;
            inner.soon = false;
            std::mem::take(&mut inner.pending)
        };
        for topic in pending {
            self.flush(&topic);
        }
    }

    /// Sends what changed in a topic's value to all its subscribers, computing it first if it is stale.
    fn flush(&self, topic: &Topic) {
        let (stale, source) = {
            let mut inner = self.inner.borrow_mut();
            let source = inner.source.clone();
            let Some(entry) = inner.topics.get_mut(topic) else { return };
            entry.emit_scheduled = false;
            (std::mem::take(&mut entry.stale), source)
        };
        // Computed with nothing borrowed: the source reads and watches other topics.
        // A data center topic's value is read there; a view's, computed by its source.
        let computed = if stale { self.held(topic).map(Ok).or_else(|| source.and_then(|s| s.compute(topic))) } else { None };
        let (subscribers, out, watchers) = {
            let mut inner = self.inner.borrow_mut();
            let shaped = inner.shaped;
            let Some(entry) = inner.topics.get_mut(topic) else { return };
            let mut changed = Vec::new();
            if let Some(value) = computed
                && entry.value.as_ref() != Some(&value)
            {
                entry.value = Some(value);
                changed = watchers(entry);
            }
            let Some(value) = entry.value.clone() else { return };
            // With what the clients show of it put in (present.rs).
            let clock = crate::present::Clock { now: self.host.now_ms(), offset_min: self.host.utc_offset_min(self.host.now_ms()) };
            let value = value.and_then(|mut v| {
                crate::present::decorate(topic, &mut v, clock);
                if !shaped {
                    return Ok(v);
                }
                // A value its shape does not allow is the core's bug: it goes out as an error saying where.
                crate::present::conform(topic, v).map_err(|at| CoreError::new("shape", format!("{topic:?} 不合约定：{at}")))
            });
            let out = match (&entry.sent, &value) {
                (Some(Ok(old)), Ok(new)) => {
                    let ops = delta::diff(old, new);
                    if ops.is_empty() {
                        None
                    } else if delta::larger_than(&ops, new) {
                        Some(Out::Value(new.clone()))
                    } else {
                        Some(Out::Delta(ops))
                    }
                }
                (Some(old), new) if old == new => None,
                (_, new) => Some(Out::whole(new.clone())),
            };
            entry.sent = Some(value);
            (entry.subscribers.clone(), out, changed)
        };
        watchers.iter().for_each(|w| w());
        let Some(out) = out else { return };
        for (client, id) in subscribers {
            self.host.emit(client, out.to(id));
        }
    }

    fn evict(&self, topic: &Topic, idle: u64) {
        let source = {
            let inner = self.inner.borrow();
            match inner.topics.get(topic) {
                Some(entry) if entry.idle == Some(idle) => inner.source.clone(),
                _ => return,
            }
        };
        if let Some(source) = source {
            source.stop(topic);
        }
        let mut inner = self.inner.borrow_mut();
        if inner.topics.get(topic).is_some_and(|e| e.idle == Some(idle)) {
            inner.topics.remove(topic);
        }
    }
}

fn watchers(entry: &Entry) -> Vec<Rc<dyn Fn()>> {
    entry.watchers.iter().map(|(_, w)| w.clone()).collect()
}

/// One emission of a topic, the same for each of its subscribers.
enum Out {
    Value(Value),
    Delta(Vec<Op>),
    Error(CoreError),
}

impl Out {
    fn whole(value: Result<Value, CoreError>) -> Out {
        match value {
            Ok(value) => Out::Value(value),
            Err(error) => Out::Error(error),
        }
    }

    fn to(&self, id: RequestId) -> CoreMessage {
        match self {
            Out::Value(value) => CoreMessage::Value { id, value: value.clone() },
            Out::Delta(delta) => CoreMessage::Delta { id, delta: delta.clone() },
            Out::Error(error) => CoreMessage::Error { id, error: error.clone() },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::{FakeHost, run};
    use serde_json::json;

    /// Time sped up this many times, so eviction takes 0.6 s of test time.
    const SPEEDUP: u64 = 100;

    /// Lets `ms` of (sped up) core time pass.
    async fn pass(ms: u64) {
        tokio::time::sleep(std::time::Duration::from_micros(ms * 1000 / SPEEDUP)).await;
        for _ in 0..5 {
            tokio::task::yield_now().await;
        }
    }

    #[derive(Default)]
    struct Recorder {
        calls: RefCell<Vec<String>>,
        /// What `compute` answers.
        computed: RefCell<Option<Result<Value, CoreError>>>,
    }

    impl Source for Recorder {
        fn start(&self, topic: &Topic) {
            self.calls.borrow_mut().push(format!("start {topic:?}"));
        }
        fn stop(&self, topic: &Topic) {
            self.calls.borrow_mut().push(format!("stop {topic:?}"));
        }
        fn compute(&self, topic: &Topic) -> Option<Result<Value, CoreError>> {
            self.calls.borrow_mut().push(format!("compute {topic:?}"));
            self.computed.borrow().clone()
        }
    }

    impl Recorder {
        fn take(&self) -> Vec<String> {
            std::mem::take(&mut self.calls.borrow_mut())
        }
    }

    fn setup() -> (Rc<FakeHost>, Rc<Store>, Rc<Recorder>) {
        let fake = FakeHost::new();
        fake.speed_up(SPEEDUP);
        let store = Store::new(fake.clone());
        let source = Rc::new(Recorder::default());
        store.set_source(source.clone());
        (fake, store, source)
    }

    fn overview() -> Topic {
        Topic::Overview { station: "ws/st".into() }
    }

    fn value(id: RequestId, v: Value) -> CoreMessage {
        CoreMessage::Value { id, value: v }
    }

    #[test]
    fn starts_once_and_emits_to_every_subscriber() {
        run(async {
            let (host, store, source) = setup();
            store.subscribe(1, 10, overview());
            store.subscribe(2, 20, overview());
            assert_eq!(source.take(), vec![format!("start {:?}", overview())]);
            assert!(host.take_emitted().is_empty());
            store.set(&overview(), Ok(json!({"n": 1})));
            assert!(host.take_emitted().is_empty(), "emission waits for the coalescing window");
            pass(COALESCE_MS * 2).await;
            assert_eq!(host.take_emitted(), vec![(1, value(10, json!({"n": 1}))), (2, value(20, json!({"n": 1})))]);
            assert_eq!(store.get(&overview()), Some(json!({"n": 1})));
            assert_eq!(store.live_topics(), vec![overview()]);
        });
    }

    #[test]
    fn coalesces_changes_into_one_emission() {
        run(async {
            let (host, store, _) = setup();
            store.subscribe(1, 10, overview());
            for n in 0..5 {
                store.set(&overview(), Ok(json!(n)));
            }
            store.update(&overview(), &mut |v| *v = json!(v.as_i64().unwrap() * 10));
            pass(COALESCE_MS * 2).await;
            assert_eq!(host.take_emitted(), vec![(1, value(10, json!(40)))]);
            // A later change gets its own emission.
            store.set(&overview(), Ok(json!("again")));
            pass(COALESCE_MS * 2).await;
            assert_eq!(host.take_emitted(), vec![(1, value(10, json!("again")))]);
        });
    }

    #[test]
    fn sends_the_cached_value_or_error_at_once() {
        run(async {
            let (host, store, source) = setup();
            store.subscribe(1, 10, overview());
            store.set(&overview(), Ok(json!({"cached": true})));
            pass(COALESCE_MS * 2).await;
            host.take_emitted();
            store.subscribe(2, 5, overview());
            assert_eq!(host.take_emitted(), vec![(2, value(5, json!({"cached": true})))]);

            let error = CoreError::new("offline", "连不上");
            store.set(&overview(), Err(error.clone()));
            pass(COALESCE_MS * 2).await;
            assert_eq!(host.take_emitted().len(), 2);
            assert_eq!(store.get(&overview()), None);
            store.subscribe(3, 7, overview());
            assert_eq!(host.take_emitted(), vec![(3, CoreMessage::Error { id: 7, error })]);
            assert_eq!(source.take().len(), 1, "only the first subscriber starts the topic");
        });
    }

    #[test]
    fn evicts_a_minute_after_the_last_subscriber_leaves() {
        run(async {
            let (host, store, source) = setup();
            store.subscribe(1, 10, overview());
            store.set(&overview(), Ok(json!(1)));
            pass(COALESCE_MS * 2).await;
            source.take();
            host.take_emitted();

            store.unsubscribe(1, 10);
            pass(EVICT_AFTER_MS / 2).await;
            assert!(source.take().is_empty());
            assert_eq!(store.get(&overview()), Some(json!(1)), "cached through the grace period");

            // Back within the grace: no restart, the cached value at once, and the first timer is void.
            store.subscribe(1, 11, overview());
            assert_eq!(host.take_emitted(), vec![(1, value(11, json!(1)))]);
            pass(EVICT_AFTER_MS * 3 / 4).await;
            assert!(source.take().is_empty());

            store.unsubscribe(1, 11);
            pass(EVICT_AFTER_MS + EVICT_AFTER_MS / 4).await;
            assert_eq!(source.take(), vec![format!("stop {:?}", overview())]);
            assert_eq!(store.get(&overview()), None);
            assert!(store.live_topics().is_empty());

            // Gone for good: a late value is ignored, and a new subscriber starts it afresh.
            store.set(&overview(), Ok(json!("late")));
            assert!(store.live_topics().is_empty());
            store.subscribe(1, 12, overview());
            assert!(host.take_emitted().is_empty());
            assert_eq!(source.take(), vec![format!("start {:?}", overview())]);
        });
    }

    #[test]
    fn drop_client_ends_all_its_subscriptions() {
        run(async {
            let (host, store, source) = setup();
            let sessions = Topic::Sessions { station: "ws/st".into() };
            store.subscribe(1, 1, overview());
            store.subscribe(1, 2, sessions.clone());
            store.subscribe(2, 1, sessions.clone());
            source.take();
            store.drop_client(1);
            store.set(&overview(), Ok(json!("o")));
            store.set(&sessions, Ok(json!("s")));
            pass(COALESCE_MS * 2).await;
            assert_eq!(host.take_emitted(), vec![(2, value(1, json!("s")))]);
            pass(EVICT_AFTER_MS + EVICT_AFTER_MS / 4).await;
            assert_eq!(source.take(), vec![format!("stop {:?}", overview())]);
            assert_eq!(store.live_topics(), vec![sessions]);
        });
    }

    #[test]
    fn update_changes_in_place_and_skips_topics_without_a_value() {
        run(async {
            let (host, store, _) = setup();
            let session = Topic::Session { station: "ws/st".into(), key: "k".into() };
            store.subscribe(1, 1, session.clone());
            store.update(&session, &mut |_| panic!("no value yet"));
            store.set(&session, Err(CoreError::new("x", "出错了")));
            store.update(&session, &mut |_| panic!("an error is not a value"));
            store.set(&session, Ok(json!({"timeline": [1]})));
            pass(COALESCE_MS * 2).await;
            host.take_emitted();
            store.update(&session, &mut |v| v["timeline"].as_array_mut().unwrap().push(json!(2)));
            assert_eq!(store.get(&session), Some(json!({"timeline": [1, 2]})));
            pass(COALESCE_MS * 2).await;
            assert_eq!(host.take_emitted(), vec![(1, value(1, json!({"timeline": [1, 2]})))]);
        });
    }

    #[test]
    fn reusing_a_request_id_replaces_the_subscription() {
        run(async {
            let (host, store, source) = setup();
            let sessions = Topic::Sessions { station: "ws/st".into() };
            store.subscribe(1, 1, overview());
            store.subscribe(1, 1, sessions.clone());
            source.take();
            store.set(&overview(), Ok(json!("o")));
            store.set(&sessions, Ok(json!("s")));
            pass(COALESCE_MS * 2).await;
            assert_eq!(host.take_emitted(), vec![(1, value(1, json!("s")))]);
            store.unsubscribe(1, 1);
            store.unsubscribe(1, 1);
            pass(EVICT_AFTER_MS + EVICT_AFTER_MS / 4).await;
            let mut stopped = source.take();
            stopped.sort();
            assert_eq!(stopped, vec![format!("stop {:?}", overview()), format!("stop {sessions:?}")]);
        });
    }

    fn delta(id: RequestId, ops: Value) -> CoreMessage {
        CoreMessage::Delta { id, delta: serde_json::from_value(ops).unwrap() }
    }

    fn long(n: usize) -> Value {
        json!({"timeline": (0..n).map(|i| format!("message {i}")).collect::<Vec<_>>(), "usage": {"n": n}})
    }

    #[test]
    fn sends_what_changed_after_the_first_value() {
        run(async {
            let (host, store, _) = setup();
            let session = Topic::Session { station: "ws/st".into(), key: "k".into() };
            store.subscribe(1, 1, session.clone());
            store.set(&session, Ok(long(50)));
            pass(COALESCE_MS * 2).await;
            assert_eq!(host.take_emitted(), vec![(1, value(1, long(50)))]);

            store.update(&session, &mut |v| {
                v["timeline"].as_array_mut().unwrap().push(json!("message 50"));
                v["usage"]["n"] = json!(51);
            });
            // A second subscriber gets the value the first one has, then the same change.
            store.subscribe(2, 7, session.clone());
            assert_eq!(host.take_emitted(), vec![(2, value(7, long(50)))]);
            pass(COALESCE_MS * 2).await;
            let ops = json!([{"path": ["timeline"], "append": ["message 50"]}, {"path": ["usage", "n"], "set": 51}]);
            assert_eq!(host.take_emitted(), vec![(1, delta(1, ops.clone())), (2, delta(7, ops))]);
            // Joining now: the whole current value.
            store.subscribe(3, 1, session.clone());
            assert_eq!(host.take_emitted(), vec![(3, value(1, long(51)))]);

            // The same value again: nothing goes out.
            store.set(&session, Ok(long(51)));
            pass(COALESCE_MS * 2).await;
            assert!(host.take_emitted().is_empty());

            // After an error, the whole value.
            let error = CoreError::new("offline", "连不上");
            store.set(&session, Err(error.clone()));
            pass(COALESCE_MS * 2).await;
            assert_eq!(host.take_emitted().len(), 3);
            store.set(&session, Ok(long(52)));
            pass(COALESCE_MS * 2).await;
            assert_eq!(host.take_emitted(), vec![(1, value(1, long(52))), (2, value(7, long(52))), (3, value(1, long(52)))]);

            // Changes that outweigh the value: the value.
            store.set(&session, Ok(json!({"timeline": []})));
            pass(COALESCE_MS * 2).await;
            assert_eq!(host.take_emitted()[0], (1, value(1, json!({"timeline": []}))));
        });
    }

    #[test]
    fn a_watch_keeps_a_topic_live_and_hears_its_changes() {
        run(async {
            let (host, store, source) = setup();
            let heard = Rc::new(RefCell::new(Vec::new()));
            let h = heard.clone();
            let s = Rc::downgrade(&store);
            let watch = store.watch(&overview(), Rc::new(move || h.borrow_mut().push(s.upgrade().unwrap().get(&overview()))));
            assert_eq!(source.take(), vec![format!("start {:?}", overview())]);
            store.set(&overview(), Ok(json!(1)));
            assert_eq!(*heard.borrow(), vec![Some(json!(1))], "at once, not after the coalescing window");
            store.update(&overview(), &mut |v| *v = json!(2));
            assert_eq!(heard.borrow().len(), 2);
            pass(COALESCE_MS * 2).await;
            assert!(host.take_emitted().is_empty(), "a watch is not a UI");

            // A UI leaving does not stop a watched topic; the watch leaving does, after the grace.
            store.subscribe(1, 1, overview());
            store.unsubscribe(1, 1);
            pass(EVICT_AFTER_MS + EVICT_AFTER_MS / 4).await;
            assert!(source.take().is_empty());
            assert_eq!(store.live_topics(), vec![overview()]);
            drop(watch);
            pass(EVICT_AFTER_MS / 2).await;
            assert_eq!(store.get(&overview()), Some(json!(2)), "cached through the grace period");
            pass(EVICT_AFTER_MS * 3 / 4).await;
            assert_eq!(source.take(), vec![format!("stop {:?}", overview())]);
            assert!(store.live_topics().is_empty());
            assert_eq!(heard.borrow().len(), 2);
        });
    }

    #[test]
    fn an_invalidated_topic_is_computed_once_as_it_goes_out() {
        run(async {
            let (host, store, source) = setup();
            let chats = Topic::Chats { scope: "ws".into(), mine: false, watching: false };
            store.subscribe(1, 1, chats.clone());
            source.take();
            // Nothing to show yet: nothing goes out.
            store.invalidate(&chats);
            pass(COALESCE_MS * 2).await;
            assert_eq!(source.take(), vec![format!("compute {chats:?}")]);
            assert!(host.take_emitted().is_empty());

            *source.computed.borrow_mut() = Some(Ok(json!({"n": 1})));
            for _ in 0..5 {
                store.invalidate(&chats);
            }
            assert!(source.take().is_empty(), "computed when it goes out");
            pass(COALESCE_MS * 2).await;
            assert_eq!(source.take(), vec![format!("compute {chats:?}")]);
            assert_eq!(host.take_emitted(), vec![(1, value(1, json!({"n": 1})))]);
            assert_eq!(store.get(&chats), Some(json!({"n": 1})));

            // The same result: not sent again.
            store.invalidate(&chats);
            pass(COALESCE_MS * 2).await;
            assert_eq!(source.take().len(), 1);
            assert!(host.take_emitted().is_empty());
        });
    }

    #[test]
    fn topics_changed_together_go_out_together_in_order() {
        run(async {
            let (host, store, _) = setup();
            let session = Topic::Session { station: "ws/st".into(), key: "k".into() };
            let live = Topic::Live { station: "ws/st".into(), key: "k".into() };
            store.subscribe(1, 1, overview());
            store.subscribe(1, 2, session.clone());
            store.subscribe(1, 3, live.clone());
            store.set(&overview(), Ok(json!("o0")));
            store.set(&session, Ok(json!("s0")));
            store.set(&live, Ok(json!("l0")));
            pass(COALESCE_MS * 2).await;
            host.take_emitted();
            // Real time, for a margin the timer resolution cannot eat.
            host.speed_up(1);
            let wait = |ms: u64| tokio::time::sleep(std::time::Duration::from_millis(ms));
            // `overview` opens the window; the other two change within it, later, and still go with it.
            store.set(&overview(), Ok(json!("o")));
            wait(COALESCE_MS / 2).await;
            store.set(&session, Ok(json!("s")));
            store.set(&live, Ok(json!("l")));
            wait(COALESCE_MS * 3 / 4).await;
            assert_eq!(host.take_emitted(), vec![(1, value(1, json!("o"))), (1, value(2, json!("s"))), (1, value(3, json!("l")))]);
        });
    }

    #[test]
    fn a_first_value_goes_out_without_waiting_the_window() {
        run(async {
            let (host, store, _) = setup();
            let session = Topic::Session { station: "ws/st".into(), key: "k".into() };
            store.subscribe(1, 1, overview());
            store.set(&overview(), Ok(json!("o0")));
            pass(COALESCE_MS * 2).await;
            host.take_emitted();
            store.subscribe(1, 2, session.clone());
            host.speed_up(1);
            let wait = |ms: u64| tokio::time::sleep(std::time::Duration::from_millis(ms));
            // A change opens the window; the new topic's first value does not wait for it, and takes the change along.
            store.set(&overview(), Ok(json!("o")));
            store.set(&session, Ok(json!("s")));
            wait(COALESCE_MS / 5).await;
            assert_eq!(host.take_emitted(), vec![(1, value(1, json!("o"))), (1, value(2, json!("s")))]);
        });
    }
}
