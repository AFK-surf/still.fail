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
