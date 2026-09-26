//! Topics: their current values, who subscribes, and when a value goes out.
//!
//! A topic comes alive with its first subscriber (the store calls the
//! [`Source`] to start it) and is stopped a minute after its last one leaves;
//! its value stays cached until then, so a UI that re-subscribes gets it at
//! once. `set` stores a value and schedules one emission per topic, coalesced
//! over [`COALESCE_MS`].

use std::rc::Rc;

use serde_json::Value;

use crate::error::CoreError;
use crate::host::Host;
use crate::protocol::{ClientId, RequestId, Topic};

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
    _host: Rc<dyn Host>,
}

impl Store {
    pub fn new(host: Rc<dyn Host>) -> Rc<Store> {
        let _ = host;
        todo!("store")
    }

    /// Routes each kind of topic to its producer; set once by `Core` at construction.
    pub fn set_source(&self, source: Rc<dyn Source>) {
        let _ = source;
        todo!()
    }

    /// Adds a subscriber; sends the cached value (or error) at once if there is one, and starts the topic if it was not live.
    pub fn subscribe(&self, client: ClientId, id: RequestId, topic: Topic) {
        let _ = (client, id, topic);
        todo!()
    }

    pub fn unsubscribe(&self, client: ClientId, id: RequestId) {
        let _ = (client, id);
        todo!()
    }

    /// A UI went away: drops all its subscriptions.
    pub fn drop_client(&self, client: ClientId) {
        let _ = client;
        todo!()
    }

    /// Stores a topic's new value (or its error) and schedules sending it to the topic's subscribers.
    pub fn set(&self, topic: &Topic, value: Result<Value, CoreError>) {
        let _ = (topic, value);
        todo!()
    }

    /// Changes a topic's value in place (e.g. appending live timeline entries), then schedules sending it.
    /// Does nothing if the topic has no value yet.
    pub fn update(&self, topic: &Topic, change: &mut dyn FnMut(&mut Value)) {
        let _ = (topic, change);
        todo!()
    }

    pub fn get(&self, topic: &Topic) -> Option<Value> {
        let _ = topic;
        todo!()
    }

    /// Topics with at least one subscriber (or within their eviction grace).
    pub fn live_topics(&self) -> Vec<Topic> {
        todo!()
    }
}
