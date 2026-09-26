//! The core's data center (docs/core-db.md): the one place what the cloud and
//! the stations said is held. Both ways it comes — read (a request's answer)
//! and pushed (an event) — end here as records; nothing else holds a copy.
//! Records live in memory, by table and key, and are written through to the
//! host's database (SQLite natively, IndexedDB on the web); at start the core
//! loads them, so what was last known is there before any network.
//!
//! A topic of this data has no value of its own in the store: its value is
//! read from here when asked for, and a change here tells the store, which
//! sends the topics that read it (and the views put together from them).
//!
//! Kept here so far: the workspaces an account's `/v1/me` lists, a
//! workspace's stations, and per station its sidebar rows, sessions (their
//! summaries and details), threads and overview. Thread entries and
//! transcripts are still in `kept.rs`.

use std::cell::RefCell;
use std::collections::{BTreeMap, HashSet};
use std::rc::{Rc, Weak};

use futures::FutureExt;
use futures::future::{LocalBoxFuture, Shared};
use serde_json::Value;

use crate::host::{DbOp, DbRange, Host};
use crate::protocol::Topic;

/// Between the parts of a key: sorts before every character a part can hold.
const SEP: char = '\u{1}';

/// Every table, to load them all at start.
const TABLES: &[&str] = &["me", "workspace", "overview", "session", "row", "session_summary", "thread", "list"];

/// How a topic's value is held.
enum Shape {
    /// The whole value, one record.
    One { table: &'static str, key: String },
    /// An array: one record per item (by its `id_field`), and one `list` record with the ids in order (so an
    /// empty list read is known apart from one never read).
    List { table: &'static str, scope: String, id_field: &'static str },
}

fn shape(topic: &Topic) -> Option<Shape> {
    Some(match topic {
        Topic::Workspace { workspace } => Shape::One { table: "workspace", key: workspace.clone() },
        Topic::Overview { station } => Shape::One { table: "overview", key: station.clone() },
        Topic::Session { station, key } => Shape::One { table: "session", key: join(&[station, key]) },
        Topic::ChatRows { station } => Shape::List { table: "row", scope: station.clone(), id_field: "id" },
        Topic::Sessions { station } => Shape::List { table: "session_summary", scope: station.clone(), id_field: "key" },
        Topic::Threads { station } => Shape::List { table: "thread", scope: station.clone(), id_field: "id" },
        _ => return None,
    })
}

/// Whether a topic's value is held here (rather than by the store).
pub fn holds(topic: &Topic) -> bool {
    shape(topic).is_some()
}

fn join(parts: &[&str]) -> String {
    parts.join(&SEP.to_string())
}

type Tables = BTreeMap<(String, String), Value>;

pub struct Data {
    host: Rc<dyn Host>,
    me: Weak<Data>,
    records: RefCell<Tables>,
    /// Told of each topic whose value changed here (the store, which sends it).
    changed: RefCell<Option<Rc<dyn Fn(&Topic)>>>,
    /// Resolves when the last write asked for is done; writes go in order.
    tail: RefCell<Option<Shared<LocalBoxFuture<'static, ()>>>>,
}

impl Data {
    pub fn new(host: Rc<dyn Host>) -> Rc<Data> {
        Rc::new_cyclic(|me| Data { host, me: me.clone(), records: RefCell::default(), changed: RefCell::default(), tail: RefCell::default() })
    }

    pub fn on_change(&self, listener: Rc<dyn Fn(&Topic)>) {
        *self.changed.borrow_mut() = Some(listener);
    }

    /// Reads every record from the host's database. What arrived meanwhile (read or pushed) is newer and stays;
    /// `loaded` hears which topics it may have filled.
    pub fn load(&self) -> LocalBoxFuture<'static, ()> {
        let (host, me) = (self.host.clone(), self.me.clone());
        async move {
            let mut found = Tables::new();
            for table in TABLES {
                let range = DbRange { table: (*table).into(), from: String::new(), to: "\u{10ffff}".into() };
                for (key, bytes) in host.db_read(range).await.unwrap_or_default() {
                    if let Ok(value) = serde_json::from_slice::<Value>(&bytes) {
                        found.insert(((*table).into(), key), value);
                    }
                }
            }
            let Some(this) = me.upgrade() else { return };
            {
                let mut records = this.records.borrow_mut();
                for (at, value) in found {
                    records.entry(at).or_insert(value);
                }
            }
            this.tell_all();
        }
        .boxed_local()
    }

    /// A held topic's value; `None` while nothing is known of it.
    pub fn get(&self, topic: &Topic) -> Option<Value> {
        let records = self.records.borrow();
        match shape(topic)? {
            Shape::One { table, key } => records.get(&(table.into(), key)).cloned(),
            Shape::List { table, scope, .. } => {
                let ids = records.get(&("list".into(), join(&[table, &scope])))?;
                let items = ids.as_array()?.iter().filter_map(|id| records.get(&(table.into(), join(&[&scope, id.as_str()?]))).cloned());
                Some(Value::Array(items.collect()))
            }
        }
    }

    /// A held topic's new value (read, or as an event left it): its records that differ are written, those of items
    /// no longer in a list removed.
    pub fn set(&self, topic: &Topic, value: Value) {
        let Some(shape) = shape(topic) else { return };
        let mut ops = Vec::new();
        {
            let mut records = self.records.borrow_mut();
            let mut put = |records: &mut Tables, table: &str, key: String, value: Value| {
                let at = (table.to_string(), key);
                if records.get(&at) != Some(&value) {
                    ops.push(DbOp::Put { table: at.0.clone(), key: at.1.clone(), value: serde_json::to_vec(&value).unwrap_or_default() });
                    records.insert(at, value);
                }
            };
            match shape {
                Shape::One { table, key } => put(&mut records, table, key, value),
                Shape::List { table, scope, id_field } => {
                    let items = value.as_array().cloned().unwrap_or_default();
                    let mut ids = Vec::new();
                    for item in items {
                        let Some(id) = item.get(id_field).and_then(id_text) else { continue };
                        ids.push(Value::String(id.clone()));
                        put(&mut records, table, join(&[&scope, &id]), item);
                    }
                    let kept: HashSet<String> = ids.iter().filter_map(|id| Some(join(&[&scope, id.as_str()?]))).collect();
                    let prefix = format!("{scope}{SEP}");
                    let gone: Vec<(String, String)> = records
                        .range((table.to_string(), prefix.clone())..(table.to_string(), format!("{scope}\u{2}")))
                        .map(|(at, _)| at.clone())
                        .filter(|(_, key)| !kept.contains(key))
                        .collect();
                    for at in gone {
                        records.remove(&at);
                        ops.push(DbOp::Delete { table: at.0, key: at.1 });
                    }
                    put(&mut records, "list", join(&[table, &scope]), Value::Array(ids));
                }
            }
        }
        if !ops.is_empty() {
            self.write(ops);
            self.tell(topic);
        }
    }

    /// Changes a held topic's value in place; does nothing while nothing is known of it.
    pub fn update(&self, topic: &Topic, change: &mut dyn FnMut(&mut Value)) {
        let Some(mut value) = self.get(topic) else { return };
        change(&mut value);
        self.set(topic, value);
    }

    /// A record the core keeps itself, by table and key (an account's `/v1/me`).
    pub fn record(&self, table: &str, key: &str) -> Option<Value> {
        self.records.borrow().get(&(table.to_string(), key.to_string())).cloned()
    }

    pub fn put(&self, table: &str, key: &str, value: Value) {
        let at = (table.to_string(), key.to_string());
        if self.records.borrow().get(&at) == Some(&value) {
            return;
        }
        let bytes = serde_json::to_vec(&value).unwrap_or_default();
        self.records.borrow_mut().insert(at, value);
        self.write(vec![DbOp::Put { table: table.into(), key: key.into(), value: bytes }]);
    }

    /// Every record of a table, by key.
    pub fn records(&self, table: &str) -> Vec<(String, Value)> {
        let records = self.records.borrow();
        records.range((table.to_string(), String::new())..(table.to_string(), "\u{10ffff}".to_string())).map(|((_, key), value)| (key.clone(), value.clone())).collect()
    }

    /// Keeps only the stations `keep` picks (their rows, sessions, threads, overview) and, where given, those of
    /// `workspaces`: what a signed-in account no longer reaches goes.
    pub fn retain(&self, keep: impl Fn(&str) -> bool, workspaces: Option<&HashSet<String>>) {
        let station_of = |table: &str, key: &str| -> Option<String> {
            match table {
                "overview" => Some(key.to_string()),
                "list" => key.split_once(SEP).map(|(_, scope)| scope.to_string()),
                "session" | "row" | "session_summary" | "thread" => key.split_once(SEP).map(|(station, _)| station.to_string()),
                _ => None,
            }
        };
        self.forget(|table, key| match table {
            "workspace" => workspaces.is_some_and(|w| !w.contains(key)),
            _ => station_of(table, key).is_some_and(|station| !keep(&station)),
        });
    }

    pub fn forget_record(&self, table: &str, key: &str) {
        self.forget(|t, k| t == table && k == key);
    }

    fn forget(&self, doomed: impl Fn(&str, &str) -> bool) {
        let gone: Vec<(String, String)> = self.records.borrow().keys().filter(|(t, k)| doomed(t, k)).cloned().collect();
        if gone.is_empty() {
            return;
        }
        let mut records = self.records.borrow_mut();
        let ops = gone.into_iter().map(|at| {
            records.remove(&at);
            DbOp::Delete { table: at.0, key: at.1 }
        });
        let ops: Vec<DbOp> = ops.collect();
        drop(records);
        self.write(ops);
        self.tell_all();
    }

    fn tell(&self, topic: &Topic) {
        let listener = self.changed.borrow().clone();
        if let Some(listener) = listener {
            listener(topic);
        }
    }

    /// Every topic the records may be of changed (loaded, or forgotten in bulk).
    fn tell_all(&self) {
        let topics: HashSet<Topic> = self.records.borrow().keys().filter_map(|(table, key)| topic_of(table, key)).collect();
        for topic in topics {
            self.tell(&topic);
        }
    }

    /// Queues a batch after those before it.
    fn write(&self, ops: Vec<DbOp>) {
        let previous = self.tail.borrow_mut().take();
        let write = self.host.db_write(ops);
        let next = async move {
            if let Some(previous) = previous {
                previous.await;
            }
            // A failed write leaves the older record there; the next change writes it again.
            let _ = write.await;
        }
        .boxed_local()
        .shared();
        *self.tail.borrow_mut() = Some(next.clone());
        self.host.spawn(next.map(|_| ()).boxed_local());
    }
}

/// The topic a record is (part) of.
fn topic_of(table: &str, key: &str) -> Option<Topic> {
    let station = |key: &str| key.split_once(SEP).map(|(s, _)| s.to_string());
    Some(match table {
        "workspace" => Topic::Workspace { workspace: key.into() },
        "overview" => Topic::Overview { station: key.into() },
        "session" => {
            let (station, session) = key.split_once(SEP)?;
            Topic::Session { station: station.into(), key: session.into() }
        }
        "row" => Topic::ChatRows { station: station(key)? },
        "session_summary" => Topic::Sessions { station: station(key)? },
        "thread" => Topic::Threads { station: station(key)? },
        "list" => {
            let (table, scope) = key.split_once(SEP)?;
            match table {
                "row" => Topic::ChatRows { station: scope.into() },
                "session_summary" => Topic::Sessions { station: scope.into() },
                "thread" => Topic::Threads { station: scope.into() },
                _ => return None,
            }
        }
        _ => return None,
    })
}

fn id_text(id: &Value) -> Option<String> {
    match id {
        Value::String(s) => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        _ => None,
    }
}


/// Where the station module (and the core, for the cloud) puts what it reads and what is pushed: the data center's
/// topics go to the data center, the rest (link state, samples, live steps, thread pages) to the store. A failed
/// read shows only while nothing is known.
pub struct Center {
    pub store: Rc<crate::store::Store>,
    pub data: Rc<Data>,
}

impl crate::station::TopicSink for Center {
    fn set(&self, topic: &Topic, value: crate::error::Result<Value>) {
        if !holds(topic) {
            return self.store.set(topic, value);
        }
        match value {
            Ok(value) => {
                // A failure it showed is over.
                if matches!(self.store.value(topic), Some(Err(_))) {
                    self.store.set(topic, Ok(value.clone()));
                }
                self.data.set(topic, value);
            }
            Err(error) => {
                if self.data.get(topic).is_none() {
                    self.store.set(topic, Err(error));
                }
            }
        }
    }

    fn update(&self, topic: &Topic, change: &mut dyn FnMut(&mut Value)) {
        if holds(topic) { self.data.update(topic, change) } else { self.store.update(topic, change) }
    }

    fn get(&self, topic: &Topic) -> Option<Value> {
        if holds(topic) { self.data.get(topic) } else { self.store.get(topic) }
    }
}
