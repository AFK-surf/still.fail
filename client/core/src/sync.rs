//! What the core keeps in sync by itself, whatever the UI shows. A client's
//! subscriptions read what the core has; they do not decide what is asked
//! for. The core keeps, for as long as it runs:
//!
//! - the accounts' workspaces, and each workspace (its stations, who is online);
//! - of each station: its link, overview, chat rows, sessions and threads (an
//!   offline station is asked for nothing: see `Stations::set_presence`);
//! - the live state of every agent at work, as the chat rows say.
//!
//! Messages are kept by the stations module itself: the latest chats' pages
//! (`warm`), and a page ahead of what a chat shows (`prefetch_before`).

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::rc::{Rc, Weak};

use futures::FutureExt;
use serde_json::Value;

use crate::host::Host;
use crate::protocol::Topic;
use crate::store::{Store, Watch};

pub struct Sync {
    store: Rc<Store>,
    host: Rc<dyn Host>,
    me: Weak<Sync>,
    /// What is kept, each held by a watch; dropping one lets the topic go.
    kept: RefCell<HashMap<Topic, Watch>>,
    scheduled: Cell<bool>,
}

impl Sync {
    pub fn new(store: Rc<Store>, host: Rc<dyn Host>) -> Rc<Sync> {
        Rc::new_cyclic(|me| Sync { store, host, me: me.clone(), kept: RefCell::default(), scheduled: Cell::new(false) })
    }

    /// Starts keeping things in sync (again: it is idempotent).
    pub fn start(&self) {
        self.recompute();
    }

    /// What should be kept, from what is known now.
    fn wanted(&self) -> HashSet<Topic> {
        let mut want = HashSet::from([Topic::Workspaces]);
        let ok = |topic: &Topic| self.store.value(topic).and_then(Result::ok);
        let workspaces: Vec<String> = ok(&Topic::Workspaces).as_ref().and_then(Value::as_array).into_iter().flatten()
            .flat_map(|entry| entry.get("workspaces").and_then(Value::as_array).cloned().unwrap_or_default())
            .filter_map(|w| w.get("id").and_then(Value::as_str).map(str::to_string))
            .collect();
        for workspace in workspaces {
            let topic = Topic::Workspace { workspace: workspace.clone() };
            let stations: Vec<String> = ok(&topic).as_ref().and_then(|w| w.get("stations")).and_then(Value::as_array).into_iter().flatten()
                .filter_map(|s| s.get("id").and_then(Value::as_str).map(|id| format!("{workspace}/{id}")))
                .collect();
            want.insert(topic);
            for station in stations {
                // Agents at work, as its chat rows say: their live state is kept too.
                let rows = Topic::ChatRows { station: station.clone() };
                for row in ok(&rows).as_ref().and_then(Value::as_array).into_iter().flatten() {
                    for agent in row.get("agents").and_then(Value::as_array).into_iter().flatten() {
                        if agent.get("process").and_then(Value::as_str) == Some("running")
                            && let Some(key) = agent.get("key").and_then(Value::as_str)
                        {
                            want.insert(Topic::Live { station: station.clone(), key: key.to_string() });
                        }
                    }
                }
                want.insert(rows);
                want.insert(Topic::Link { station: station.clone() });
                want.insert(Topic::Overview { station: station.clone() });
                want.insert(Topic::Sessions { station: station.clone() });
                want.insert(Topic::Threads { station });
            }
        }
        want
    }

    fn recompute(&self) {
        self.scheduled.set(false);
        let want = self.wanted();
        let fresh: Vec<Topic> = {
            let mut kept = self.kept.borrow_mut();
            kept.retain(|topic, _| want.contains(topic));
            want.into_iter().filter(|t| !kept.contains_key(t)).collect()
        };
        for topic in fresh {
            let me = self.me.clone();
            // What is kept depends on what these say (a new workspace, a station, an agent at work): look again.
            let watch = self.store.watch(&topic, Rc::new(move || {
                if let Some(sync) = me.upgrade() {
                    sync.schedule();
                }
            }));
            self.kept.borrow_mut().insert(topic, watch);
        }
    }

    /// Looks again once what changed has settled (several changes, one look).
    fn schedule(&self) {
        if self.scheduled.replace(true) {
            return;
        }
        let me = self.me.clone();
        self.host.spawn(async move {
            if let Some(sync) = me.upgrade() {
                sync.recompute();
            }
        }.boxed_local());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::CoreError;
    use crate::store::Source;
    use crate::testing::{FakeHost, run};
    use serde_json::json;

    #[derive(Default)]
    struct Started(RefCell<Vec<Topic>>);

    impl Source for Started {
        fn start(&self, topic: &Topic) {
            self.0.borrow_mut().push(topic.clone());
        }
        fn stop(&self, _topic: &Topic) {}
        fn compute(&self, _topic: &Topic) -> Option<Result<Value, CoreError>> {
            None
        }
    }

    #[test]
    fn the_core_keeps_its_workspaces_stations_and_agents_at_work_with_nobody_looking() {
        run(async {
            let host = FakeHost::new();
            let store = Store::new(host.clone());
            let started = Rc::new(Started::default());
            store.set_source(started.clone());
            let sync = Sync::new(store.clone(), host.clone());
            sync.start();
            host.settle().await;
            assert_eq!(started.0.borrow().as_slice(), &[Topic::Workspaces]);
            store.set(&Topic::Workspaces, Ok(json!([{ "workspaces": [{ "id": "ws" }] }])));
            host.settle().await;
            let ws = Topic::Workspace { workspace: "ws".into() };
            assert!(started.0.borrow().contains(&ws));
            store.set(&ws, Ok(json!({ "id": "ws", "stations": [{ "id": "st", "online": true }] })));
            host.settle().await;
            let rows = Topic::ChatRows { station: "ws/st".into() };
            for topic in [rows.clone(), Topic::Link { station: "ws/st".into() }, Topic::Overview { station: "ws/st".into() }, Topic::Sessions { station: "ws/st".into() }, Topic::Threads { station: "ws/st".into() }] {
                assert!(started.0.borrow().contains(&topic), "{topic:?}");
            }
            // An agent at work: its live state is kept too.
            store.set(&rows, Ok(json!([{ "agents": [{ "key": "k", "process": "running" }, { "key": "idle", "process": "warm" }] }])));
            host.settle().await;
            let live = |key: &str| Topic::Live { station: "ws/st".into(), key: key.into() };
            assert!(started.0.borrow().contains(&live("k")));
            assert!(!started.0.borrow().contains(&live("idle")));
        });
    }
}
