//! What the core keeps on the device (docs/station-storage.md, Append-only
//! threads): a thread's entries and a session's transcript never change once
//! written, so what was read once is kept and never asked for again.
//!
//! A log is kept through `Host` storage in chunks of [`CHUNK`] entries —
//! `thread/<station>/<thread>/<chunk>` holds entries `chunk*256+1 …
//! chunk*256+256`, `transcript/<station>/<session>/<chunk>` transcript entries
//! `chunk*256 … chunk*256+255` — plus `<log>/meta`, the one run `{ first,
//! last }` it holds. Storage cannot list its keys, so `kept` indexes every log
//! with its chunks' sizes and when it was last opened: past [`LIMIT`] bytes the
//! least recently opened logs go first.
//!
//! Operations run one at a time, in the order they were asked for (not the
//! order their futures are first polled): a write that extends a log must not
//! overtake the one before it. Each reads the index afresh, since another core
//! on the device (a tab's own worker) may have changed it.

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::rc::{Rc, Weak};

use futures::channel::oneshot;
use futures::future::{LocalBoxFuture, Shared};
use futures::FutureExt;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::host::Host;

/// Entries per chunk.
pub const CHUNK: u64 = 256;
/// What is kept at most, over all logs.
pub const LIMIT: u64 = 50 * 1024 * 1024;
const INDEX: &str = "kept";

/// A log kept on the device.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Log {
    /// A thread's entries, numbered from 1.
    Thread { station: String, thread: u64 },
    /// A session's transcript, indexed from 0.
    Transcript { station: String, session: String },
}

impl Log {
    pub fn thread(station: &str, thread: u64) -> Log {
        Log::Thread { station: station.into(), thread }
    }

    pub fn transcript(station: &str, session: &str) -> Log {
        Log::Transcript { station: station.into(), session: session.into() }
    }

    fn name(&self) -> String {
        match self {
            Log::Thread { station, thread } => format!("thread/{station}/{thread}"),
            Log::Transcript { station, session } => format!("transcript/{station}/{session}"),
        }
    }

    fn station(&self) -> &str {
        match self {
            Log::Thread { station, .. } | Log::Transcript { station, .. } => station,
        }
    }

    /// The number of its first possible entry.
    fn base(&self) -> u64 {
        match self {
            Log::Thread { .. } => 1,
            Log::Transcript { .. } => 0,
        }
    }

    fn chunk_of(&self, at: u64) -> u64 {
        (at - self.base()) / CHUNK
    }

    /// The first and last number a chunk can hold.
    fn chunk_span(&self, chunk: u64) -> (u64, u64) {
        let start = chunk * CHUNK + self.base();
        (start, start + CHUNK - 1)
    }
}

/// The run of entries kept of a log, and (for a thread) its summary and its title in the sidebar as last seen, so a
/// chat opens without asking.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Held {
    pub first: u64,
    pub last: u64,
    #[serde(default, skip_serializing_if = "Value::is_null")]
    pub thread: Value,
    #[serde(default, skip_serializing_if = "Value::is_null")]
    pub title: Value,
}

#[derive(Default, Serialize, Deserialize)]
struct Item {
    station: String,
    /// When a view last opened it (host ms).
    opened: f64,
    /// Bytes stored per chunk.
    chunks: BTreeMap<u64, u64>,
}

type Index = BTreeMap<String, Item>;

pub struct Kept {
    host: Rc<dyn Host>,
    me: Weak<Kept>,
    /// Bytes kept at most.
    limit: u64,
    /// The index as the running operation read it.
    index: RefCell<Option<Index>>,
    /// Resolves when the last operation asked for is done.
    tail: RefCell<Option<Shared<LocalBoxFuture<'static, ()>>>>,
}

impl Kept {
    pub fn new(host: Rc<dyn Host>) -> Rc<Kept> {
        Kept::with_limit(host, LIMIT)
    }

    pub fn with_limit(host: Rc<dyn Host>, limit: u64) -> Rc<Kept> {
        Rc::new_cyclic(|me| Kept { host, me: me.clone(), limit, index: RefCell::default(), tail: RefCell::default() })
    }

    /// Queues an operation after those asked for before it.
    fn queued<T: 'static>(&self, op: impl AsyncFnOnce(Rc<Kept>) -> T + 'static) -> LocalBoxFuture<'static, Option<T>> {
        let (done, finished) = oneshot::channel::<()>();
        let previous = self.tail.replace(Some(finished.map(|_| ()).boxed_local().shared()));
        let me = self.me.clone();
        async move {
            if let Some(previous) = previous {
                previous.await;
            }
            let out = match me.upgrade() {
                Some(kept) => Some(op(kept).await),
                None => None,
            };
            let _ = done.send(());
            out
        }
        .boxed_local()
    }

    /// What is kept of a log and its last `tail` entries (all with `u64::MAX`), noting that it was opened.
    pub fn open(&self, log: &Log, tail: u64) -> LocalBoxFuture<'static, Option<(Held, Vec<Value>)>> {
        let log = log.clone();
        self.queued(async move |kept| {
            let held = kept.held(&log).await?;
            let from = held.first.max(held.last.saturating_sub(tail.saturating_sub(1)));
            let entries = kept.read(&log, &held, from, held.last).await?;
            if let Some(item) = kept.index().get_mut(&log.name()) {
                item.opened = kept.host.now_ms();
            }
            kept.save_index().await;
            Some((Held { first: from, ..held }, entries))
        })
        .map(Option::flatten)
        .boxed_local()
    }

    /// Up to `count` kept entries just before `before`, if the entry before it is kept.
    pub fn before(&self, log: &Log, before: u64, count: u64) -> LocalBoxFuture<'static, Option<Vec<Value>>> {
        let log = log.clone();
        self.queued(async move |kept| {
            let held = kept.held(&log).await?;
            if before <= held.first || before > held.last + 1 {
                return None;
            }
            kept.read(&log, &held, held.first.max(before.saturating_sub(count)), before - 1).await
        })
        .map(Option::flatten)
        .boxed_local()
    }

    /// Keeps `entries`, numbered from `from` on, with what is kept of the log when they touch it (else in its
    /// place). `truncate`: nothing after them is kept (a transcript written anew). `thread`: the summary to keep.
    pub fn write(&self, log: &Log, from: u64, entries: Vec<Value>, truncate: bool, thread: Option<Value>) -> LocalBoxFuture<'static, ()> {
        let log = log.clone();
        self.queued(async move |kept| kept.put(&log, from, entries, truncate, thread).await).map(|_| ()).boxed_local()
    }

    /// Keeps a thread's summary and sidebar title as last seen (each where given), if anything of it is kept.
    pub fn summary(&self, log: &Log, thread: Option<Value>, title: Option<Value>) -> LocalBoxFuture<'static, ()> {
        let log = log.clone();
        self.queued(async move |kept| {
            let Some(held) = kept.held(&log).await else { return };
            let next = Held { thread: thread.unwrap_or_else(|| held.thread.clone()), title: title.unwrap_or_else(|| held.title.clone()), ..held.clone() };
            if next != held {
                kept.set_held(&log, &next).await;
            }
        })
        .map(|_| ())
        .boxed_local()
    }

    /// Forgets a log (its thread went, or what is kept of it cannot be read).
    pub fn forget(&self, log: &Log) -> LocalBoxFuture<'static, ()> {
        let log = log.clone();
        self.queued(async move |kept| {
            kept.load_index().await;
            kept.remove(&log.name()).await;
            kept.save_index().await;
        })
        .map(|_| ())
        .boxed_local()
    }

    /// Forgets every log of the stations `keep` says no to.
    pub fn retain(&self, keep: impl Fn(&str) -> bool + 'static) -> LocalBoxFuture<'static, ()> {
        self.queued(async move |kept| {
            kept.load_index().await;
            let gone: Vec<String> = kept.index().iter().filter(|(_, item)| !keep(&item.station)).map(|(name, _)| name.clone()).collect();
            if gone.is_empty() {
                return;
            }
            for name in gone {
                kept.remove(&name).await;
            }
            kept.save_index().await;
        })
        .map(|_| ())
        .boxed_local()
    }

    // ── inside the queue ──

    fn index(&self) -> std::cell::RefMut<'_, Index> {
        std::cell::RefMut::map(self.index.borrow_mut(), |i| i.get_or_insert_with(Index::new))
    }

    async fn load_index(&self) {
        let stored = self.host.storage_get(INDEX).await.ok().flatten().and_then(|b| serde_json::from_slice::<Index>(&b).ok());
        *self.index.borrow_mut() = Some(stored.unwrap_or_default());
    }

    async fn save_index(&self) {
        let bytes = serde_json::to_vec(&*self.index()).unwrap_or_default();
        let _ = self.host.storage_set(INDEX, bytes).await;
    }

    async fn held(&self, log: &Log) -> Option<Held> {
        self.load_index().await;
        if !self.index().contains_key(&log.name()) {
            return None;
        }
        let bytes = self.host.storage_get(&format!("{}/meta", log.name())).await.ok().flatten()?;
        serde_json::from_slice(&bytes).ok()
    }

    async fn set_held(&self, log: &Log, held: &Held) {
        let _ = self.host.storage_set(&format!("{}/meta", log.name()), serde_json::to_vec(held).unwrap_or_default()).await;
    }

    /// The chunk's entries as `held` says it holds them; `None` if it is not all there.
    async fn chunk(&self, log: &Log, held: &Held, chunk: u64) -> Option<Vec<Value>> {
        let (start, end) = log.chunk_span(chunk);
        let (first, last) = (start.max(held.first), end.min(held.last));
        let bytes = self.host.storage_get(&format!("{}/{chunk}", log.name())).await.ok().flatten()?;
        let entries: Vec<Value> = serde_json::from_slice(&bytes).ok()?;
        let whole = entries.len() as u64 == last + 1 - first;
        // A thread's entries say their number: one out of place means the chunk is not what the meta says.
        let placed = |(i, e): (usize, &Value)| !matches!(log, Log::Thread { .. }) || e.get("n").and_then(Value::as_u64) == Some(first + i as u64);
        (whole && entries.iter().enumerate().all(placed)).then_some(entries)
    }

    /// Entries `from ..= to`, all held; a log that cannot give them is forgotten.
    async fn read(&self, log: &Log, held: &Held, from: u64, to: u64) -> Option<Vec<Value>> {
        let mut out = Vec::new();
        for chunk in log.chunk_of(from)..=log.chunk_of(to) {
            let Some(entries) = self.chunk(log, held, chunk).await else {
                self.remove(&log.name()).await;
                self.save_index().await;
                return None;
            };
            let first = log.chunk_span(chunk).0.max(held.first);
            out.extend(entries.into_iter().enumerate().filter(|(i, _)| (from..=to).contains(&(first + *i as u64))).map(|(_, e)| e));
        }
        Some(out)
    }

    async fn put(&self, log: &Log, from: u64, entries: Vec<Value>, truncate: bool, thread: Option<Value>) {
        let name = log.name();
        let old = self.held(log).await;
        let to = from + entries.len() as u64; // one past the last
        let touches = old.as_ref().is_some_and(|o| from <= o.last + 1 && to >= o.first);
        let thread = thread.or_else(|| old.as_ref().map(|o| o.thread.clone())).unwrap_or(Value::Null);
        let title = old.as_ref().map_or(Value::Null, |o| o.title.clone());
        let held = match &old {
            Some(o) if touches => Held { first: o.first.min(from), last: if truncate { to.max(1) - 1 } else { o.last.max(to.max(1) - 1) }, thread, title },
            _ if entries.is_empty() => return,
            _ => Held { first: from, last: to - 1, thread, title },
        };
        if !touches && old.is_some() {
            self.remove(&name).await;
        }
        if held.last < held.first || to == 0 && entries.is_empty() {
            // Written anew and nothing kept before it.
            self.remove(&name).await;
        } else {
            let old = old.filter(|_| touches);
            self.put_run(log, old.as_ref(), &held, from, entries).await;
            self.evict(&name).await;
        }
        self.save_index().await;
    }

    /// Rewrites the chunks `entries` (numbered from `from`) fall in, and the last one of a run cut short, taking
    /// the rest of each from what `old` held; drops the chunks past the run; then writes the meta.
    async fn put_run(&self, log: &Log, old: Option<&Held>, held: &Held, from: u64, entries: Vec<Value>) {
        let name = log.name();
        let to = from + entries.len() as u64;
        let mut chunks: Vec<u64> = if entries.is_empty() { Vec::new() } else { (log.chunk_of(from)..=log.chunk_of(to - 1)).collect() };
        if old.is_some_and(|o| held.last < o.last) {
            chunks.push(log.chunk_of(held.last));
        }
        chunks.sort_unstable();
        chunks.dedup();
        for chunk in chunks {
            let (start, end) = log.chunk_span(chunk);
            let (first, last) = (start.max(held.first), end.min(held.last));
            // What was kept of this chunk, where the new entries do not cover it.
            let covered = from <= first && last < to;
            let kept = match old {
                Some(o) if !covered && start.max(o.first) <= end.min(o.last) => self.chunk(log, o, chunk).await.map(|e| (start.max(o.first), e)),
                _ => None,
            };
            let mut out = Vec::with_capacity((last + 1 - first) as usize);
            for at in first..=last {
                let entry = if (from..to).contains(&at) {
                    entries.get((at - from) as usize).cloned()
                } else {
                    kept.as_ref().and_then(|(start, e)| e.get(at.checked_sub(*start)? as usize).cloned())
                };
                match entry {
                    Some(entry) => out.push(entry),
                    // What was kept cannot be joined with them: the new entries are kept alone.
                    None => return self.restart(log, from, entries).await,
                }
            }
            let bytes = serde_json::to_vec(&out).unwrap_or_default();
            let size = bytes.len() as u64;
            if self.host.storage_set(&format!("{name}/{chunk}"), bytes).await.is_err() {
                return self.remove(&name).await;
            }
            let (station, now) = (log.station().to_string(), self.host.now_ms());
            self.index().entry(name.clone()).or_insert_with(|| Item { station, opened: now, chunks: BTreeMap::new() }).chunks.insert(chunk, size);
        }
        let past: Vec<u64> = self.index().get(&name).map(|i| i.chunks.keys().copied().filter(|&c| c > log.chunk_of(held.last)).collect()).unwrap_or_default();
        for chunk in past {
            let _ = self.host.storage_delete(&format!("{name}/{chunk}")).await;
            if let Some(item) = self.index().get_mut(&name) {
                item.chunks.remove(&chunk);
            }
        }
        self.set_held(log, held).await;
    }

    fn restart<'a>(&'a self, log: &'a Log, from: u64, entries: Vec<Value>) -> LocalBoxFuture<'a, ()> {
        async move {
            self.remove(&log.name()).await;
            let held = Held { first: from, last: from + entries.len() as u64 - 1, thread: Value::Null, title: Value::Null };
            self.put_run(log, None, &held, from, entries).await;
        }
        .boxed_local()
    }

    /// Past the limit: the least recently opened logs go, never `current`.
    async fn evict(&self, current: &str) {
        loop {
            let victim = {
                let index = self.index();
                let total: u64 = index.values().flat_map(|i| i.chunks.values()).sum();
                if total <= self.limit {
                    return;
                }
                index.iter().filter(|(name, _)| name.as_str() != current).min_by(|a, b| a.1.opened.total_cmp(&b.1.opened)).map(|(name, _)| name.clone())
            };
            let Some(victim) = victim else { return };
            self.remove(&victim).await;
        }
    }

    async fn remove(&self, name: &str) {
        let item = self.index().remove(name);
        for chunk in item.map(|i| i.chunks.into_keys().collect::<Vec<_>>()).unwrap_or_default() {
            let _ = self.host.storage_delete(&format!("{name}/{chunk}")).await;
        }
        let _ = self.host.storage_delete(&format!("{name}/meta")).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::{FakeHost, run};
    use serde_json::json;

    fn entries(from: u64, to: u64) -> Vec<Value> {
        (from..=to).map(|n| json!({"n": n, "kind": "message", "text": format!("m{n}")})).collect()
    }

    fn numbers(entries: &[Value]) -> Vec<u64> {
        entries.iter().filter_map(|e| e["n"].as_u64()).collect()
    }

    #[test]
    fn a_thread_is_kept_in_chunks_of_256_and_read_back() {
        run(async {
            let host = FakeHost::new();
            let kept = Kept::new(host.clone());
            let log = Log::thread("ws/st", 7);
            assert_eq!(kept.open(&log, 50).await, None);
            // The latest page, then what came after it, across a chunk's end.
            kept.write(&log, 201, entries(201, 250), false, Some(json!({"id": 7}))).await;
            kept.write(&log, 251, entries(251, 300), false, None).await;
            assert_eq!(numbers(&serde_json::from_slice::<Vec<Value>>(&host.stored("thread/ws/st/7/0").unwrap()).unwrap()), (201..=256).collect::<Vec<_>>());
            assert_eq!(numbers(&serde_json::from_slice::<Vec<Value>>(&host.stored("thread/ws/st/7/1").unwrap()).unwrap()), (257..=300).collect::<Vec<_>>());
            let (held, page) = kept.open(&log, 50).await.unwrap();
            assert_eq!((held.first, held.last, held.thread.clone()), (251, 300, json!({"id": 7})));
            assert_eq!(numbers(&page), (251..=300).collect::<Vec<_>>());
            // Older pages in front; entries it has already change nothing.
            kept.write(&log, 1, entries(1, 200), false, None).await;
            kept.write(&log, 290, entries(290, 300), false, None).await;
            assert_eq!(numbers(&kept.before(&log, 251, 50).await.unwrap()), (201..=250).collect::<Vec<_>>());
            assert_eq!(numbers(&kept.before(&log, 3, 50).await.unwrap()), vec![1, 2]);
            assert_eq!(kept.before(&log, 1, 50).await, None, "nothing before the first");
            assert_eq!(numbers(&kept.open(&log, u64::MAX).await.unwrap().1), (1..=300).collect::<Vec<_>>());
            // Entries that do not touch what is kept take its place.
            kept.write(&log, 400, entries(400, 401), false, None).await;
            let (held, page) = kept.open(&log, 50).await.unwrap();
            assert_eq!((held.first, held.last, numbers(&page)), (400, 401, vec![400, 401]));
            assert_eq!((host.stored("thread/ws/st/7/0"), host.stored("thread/ws/st/7/1").is_some()), (None, true));
        });
    }

    #[test]
    fn a_chunk_that_does_not_match_its_meta_forgets_the_log() {
        run(async {
            let host = FakeHost::new();
            let kept = Kept::new(host.clone());
            let log = Log::thread("ws/st", 7);
            kept.write(&log, 1, entries(1, 10), false, None).await;
            host.store("thread/ws/st/7/0", serde_json::to_vec(&entries(2, 11)).unwrap());
            assert_eq!(kept.open(&log, 50).await, None);
            assert_eq!(host.stored("thread/ws/st/7/meta"), None);
        });
    }

    #[test]
    fn a_transcript_counts_from_0_and_can_be_cut_short() {
        run(async {
            let host = FakeHost::new();
            let kept = Kept::new(host.clone());
            let log = Log::transcript("local", "ember:c-1");
            let lines = |from: u64, to: u64| (from..=to).map(|i| json!(format!("e{i}"))).collect::<Vec<_>>();
            kept.write(&log, 0, lines(0, 299), true, None).await;
            assert_eq!(serde_json::from_slice::<Vec<Value>>(&host.stored("transcript/local/ember:c-1/0").unwrap()).unwrap().len(), 256);
            // Written anew from 100: what came after is gone.
            kept.write(&log, 100, lines(100, 101), true, None).await;
            let (held, all) = kept.open(&log, u64::MAX).await.unwrap();
            assert_eq!((held.first, held.last, all.len(), all[101].clone()), (0, 101, 102, json!("e101")));
            assert_eq!(host.stored("transcript/local/ember:c-1/1"), None);
            kept.write(&log, 50, Vec::new(), true, None).await;
            assert_eq!(kept.open(&log, u64::MAX).await.unwrap().1.len(), 50);
            kept.write(&log, 0, Vec::new(), true, None).await;
            assert_eq!(kept.open(&log, u64::MAX).await, None);
        });
    }

    #[test]
    fn past_the_limit_the_least_recently_opened_go() {
        run(async {
            let host = FakeHost::new();
            let (a, b, c) = (Log::thread("ws/st", 1), Log::thread("ws/st", 2), Log::thread("ws/st", 3));
            let size = serde_json::to_vec(&entries(1, 100)).unwrap().len() as u64;
            let kept = Kept::with_limit(host.clone(), size * 2);
            kept.write(&a, 1, entries(1, 100), false, None).await;
            tokio::time::sleep(std::time::Duration::from_millis(2)).await;
            kept.write(&b, 1, entries(1, 100), false, None).await;
            tokio::time::sleep(std::time::Duration::from_millis(2)).await;
            // `a` opened again: `b` is now the least recently opened.
            kept.open(&a, 50).await.unwrap();
            tokio::time::sleep(std::time::Duration::from_millis(2)).await;
            kept.write(&c, 1, entries(1, 100), false, None).await;
            assert!(kept.open(&b, 50).await.is_none());
            assert!(kept.open(&a, 50).await.is_some() && kept.open(&c, 50).await.is_some());
            assert_eq!(host.stored("thread/ws/st/2/0"), None);
        });
    }

    #[test]
    fn a_station_out_of_reach_is_forgotten() {
        run(async {
            let host = FakeHost::new();
            let kept = Kept::new(host.clone());
            kept.write(&Log::thread("ws/st", 1), 1, entries(1, 2), false, None).await;
            kept.write(&Log::transcript("ws/st", "k"), 0, vec![json!("x")], true, None).await;
            kept.write(&Log::thread("other/st", 1), 1, entries(1, 2), false, None).await;
            kept.write(&Log::thread("local", 1), 1, entries(1, 2), false, None).await;
            kept.retain(|station| station != "ws/st").await;
            assert!(kept.open(&Log::thread("ws/st", 1), 50).await.is_none());
            assert!(kept.open(&Log::transcript("ws/st", "k"), 50).await.is_none());
            assert!(host.stored("transcript/ws/st/k/0").is_none());
            assert!(kept.open(&Log::thread("other/st", 1), 50).await.is_some());
            kept.forget(&Log::thread("other/st", 1)).await;
            assert!(kept.open(&Log::thread("other/st", 1), 50).await.is_none());
            assert!(kept.open(&Log::thread("local", 1), 50).await.is_some());
        });
    }

    #[test]
    fn operations_run_in_the_order_they_were_asked_for() {
        run(async {
            let host = FakeHost::new();
            let kept = Kept::new(host.clone());
            let log = Log::thread("ws/st", 7);
            // Asked for in order, polled the other way round.
            let first = kept.write(&log, 1, entries(1, 10), false, None);
            let second = kept.write(&log, 11, entries(11, 20), false, None);
            futures::future::join(second, first).await;
            assert_eq!(numbers(&kept.open(&log, u64::MAX).await.unwrap().1), (1..=20).collect::<Vec<_>>());
        });
    }
}
