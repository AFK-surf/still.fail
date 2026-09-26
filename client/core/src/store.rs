//! Topics: their current values, who subscribes, and when a value goes out.
//!
//! A topic comes alive with its first subscriber (the store calls the
//! [`Source`] to start it) and is stopped a minute after its last one leaves;
//! its value stays cached until then, so a UI that re-subscribes gets it at
//! once. `set` stores a value and schedules one emission per topic, coalesced
//! over [`COALESCE_MS`].

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::{Rc, Weak};

use futures::FutureExt;
use serde_json::Value;

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
}

#[derive(Default)]
struct Entry {
    value: Option<Result<Value, CoreError>>,
    subscribers: Vec<(ClientId, RequestId)>,
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
            let cached = entry.value.clone();
            (cached, started, inner.source.clone())
        };
        if let Some(value) = cached {
            self.host.emit(client, message(id, value));
        }
        if started && let Some(source) = source {
            source.start(&topic);
        }
    }

    pub fn unsubscribe(&self, client: ClientId, id: RequestId) {
        let mut inner = self.inner.borrow_mut();
        let Some(topic) = inner.subscriptions.remove(&(client, id)) else { return };
        inner.idle_count += 1;
        let idle = inner.idle_count;
        let Some(entry) = inner.topics.get_mut(&topic) else { return };
        entry.subscribers.retain(|s| *s != (client, id));
        if !entry.subscribers.is_empty() {
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
        drop(inner);
        if schedule {
            self.schedule_emit(topic);
        }
    }

    /// Changes a topic's value in place (e.g. appending live timeline entries), then schedules sending it.
    /// Does nothing if the topic has no value yet.
    pub fn update(&self, topic: &Topic, change: &mut dyn FnMut(&mut Value)) {
        let mut inner = self.inner.borrow_mut();
        let Some(entry) = inner.topics.get_mut(topic) else { return };
        let Some(Ok(value)) = entry.value.as_mut() else { return };
        change(value);
        let schedule = !std::mem::replace(&mut entry.emit_scheduled, true);
        drop(inner);
        if schedule {
            self.schedule_emit(topic);
        }
    }

    pub fn get(&self, topic: &Topic) -> Option<Value> {
        match self.inner.borrow().topics.get(topic)?.value.as_ref()? {
            Ok(value) => Some(value.clone()),
            Err(_) => None,
        }
    }

    /// Topics with at least one subscriber (or within their eviction grace).
    pub fn live_topics(&self) -> Vec<Topic> {
        self.inner.borrow().topics.keys().cloned().collect()
    }

    fn schedule_emit(&self, topic: &Topic) {
        let store = self.me.clone();
        let topic = topic.clone();
        let sleep = self.host.sleep(COALESCE_MS);
        self.host.spawn(
            async move {
                sleep.await;
                if let Some(store) = store.upgrade() {
                    store.flush(&topic);
                }
            }
            .boxed_local(),
        );
    }

    /// Sends a topic's value to all its subscribers.
    fn flush(&self, topic: &Topic) {
        let (subscribers, value) = {
            let mut inner = self.inner.borrow_mut();
            let Some(entry) = inner.topics.get_mut(topic) else { return };
            entry.emit_scheduled = false;
            let Some(value) = entry.value.clone() else { return };
            (entry.subscribers.clone(), value)
        };
        for (client, id) in subscribers {
            self.host.emit(client, message(id, value.clone()));
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

fn message(id: RequestId, value: Result<Value, CoreError>) -> CoreMessage {
    match value {
        Ok(value) => CoreMessage::Value { id, value },
        Err(error) => CoreMessage::Error { id, error },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::{HostError, HttpRequest, HttpResponse, StreamResponse};
    use crate::testing::{FakeHost, run};
    use futures::future::LocalBoxFuture;
    use serde_json::json;

    /// FakeHost with time sped up [`SPEEDUP`] times, so eviction takes 0.6 s of test time.
    struct Fast(Rc<FakeHost>);
    const SPEEDUP: u64 = 100;

    impl Host for Fast {
        fn cloud_origin(&self) -> String {
            self.0.cloud_origin()
        }
        fn fetch(&self, r: HttpRequest) -> LocalBoxFuture<'static, Result<HttpResponse, HostError>> {
            self.0.fetch(r)
        }
        fn fetch_stream(&self, r: HttpRequest) -> LocalBoxFuture<'static, Result<StreamResponse, HostError>> {
            self.0.fetch_stream(r)
        }
        fn storage_get(&self, k: &str) -> LocalBoxFuture<'static, Result<Option<Vec<u8>>, HostError>> {
            self.0.storage_get(k)
        }
        fn storage_set(&self, k: &str, v: Vec<u8>) -> LocalBoxFuture<'static, Result<(), HostError>> {
            self.0.storage_set(k, v)
        }
        fn storage_delete(&self, k: &str) -> LocalBoxFuture<'static, Result<(), HostError>> {
            self.0.storage_delete(k)
        }
        fn now_ms(&self) -> f64 {
            self.0.now_ms()
        }
        fn sleep(&self, ms: u64) -> LocalBoxFuture<'static, ()> {
            tokio::time::sleep(std::time::Duration::from_micros(ms * 1000 / SPEEDUP)).boxed_local()
        }
        fn spawn(&self, task: LocalBoxFuture<'static, ()>) {
            self.0.spawn(task)
        }
        fn random_bytes(&self, buf: &mut [u8]) {
            self.0.random_bytes(buf)
        }
        fn emit(&self, c: ClientId, m: CoreMessage) {
            self.0.emit(c, m)
        }
    }

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
    }

    impl Source for Recorder {
        fn start(&self, topic: &Topic) {
            self.calls.borrow_mut().push(format!("start {topic:?}"));
        }
        fn stop(&self, topic: &Topic) {
            self.calls.borrow_mut().push(format!("stop {topic:?}"));
        }
    }

    impl Recorder {
        fn take(&self) -> Vec<String> {
            std::mem::take(&mut self.calls.borrow_mut())
        }
    }

    fn setup() -> (Rc<FakeHost>, Rc<Store>, Rc<Recorder>) {
        let fake = FakeHost::new();
        let store = Store::new(Rc::new(Fast(fake.clone())));
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
            let session = Topic::Session { station: "local".into(), key: "k".into() };
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
}
