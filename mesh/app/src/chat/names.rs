//! What Slack calls people and channels, kept on disk so the admin API never waits on Slack for a name: a name not
//! known yet answers None at once, is fetched in the background, and `on_learn` tells the pages to read again. Failed
//! lookups are not retried for a while. (src/chat/names.ts)

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use futures_util::future::BoxFuture;
use serde::{Deserialize, Serialize};
use tracing::warn;

use super::Person;
use crate::store::now_ms;

const RETRY_FAILED_MS: i64 = 10 * 60_000;
const SAVE_AFTER: Duration = Duration::from_secs(2);
const LEARN_AFTER: Duration = Duration::from_millis(200);

#[derive(Serialize, Deserialize, Debug, Clone, Default, PartialEq)]
struct Entry {
    #[serde(skip_serializing_if = "Option::is_none", default)]
    person: Option<Person>,
    /// A channel's name; Some(None) for a direct message (known to have none).
    #[serde(skip_serializing_if = "Option::is_none", default, with = "double_option")]
    channel: Option<Option<String>>,
    at: i64,
}

mod double_option {
    use serde::{Deserialize, Deserializer, Serialize, Serializer};
    pub fn serialize<S: Serializer>(v: &Option<Option<String>>, s: S) -> Result<S::Ok, S::Error> {
        v.as_ref().unwrap().serialize(s)
    }
    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Option<Option<String>>, D::Error> {
        Ok(Some(Option::<String>::deserialize(d)?))
    }
}

struct State {
    entries: HashMap<String, Entry>,
    pending: HashSet<String>,
    failed: HashMap<String, i64>,
    saving: bool,
    learning: bool,
}

pub struct NameBook {
    path: PathBuf,
    state: Mutex<State>,
    on_learn: Mutex<Arc<dyn Fn() + Send + Sync>>,
}

impl NameBook {
    pub fn open(path: PathBuf) -> Arc<NameBook> {
        let entries = match std::fs::read_to_string(&path) {
            Ok(text) => serde_json::from_str(&text).unwrap_or_else(|error| {
                warn!(%error, "slack names file unreadable; starting empty");
                HashMap::new()
            }),
            Err(_) => HashMap::new(),
        };
        Arc::new(NameBook {
            path,
            state: Mutex::new(State { entries, pending: HashSet::new(), failed: HashMap::new(), saving: false, learning: false }),
            on_learn: Mutex::new(Arc::new(|| {})),
        })
    }

    /// Called (once per burst) after names were learned, so pages read what shows them again.
    pub fn on_learn(&self, listener: impl Fn() + Send + Sync + 'static) {
        *self.on_learn.lock().unwrap() = Arc::new(listener);
    }

    pub fn person(self: &Arc<Self>, key: &str, fetch: impl FnOnce() -> BoxFuture<'static, Option<Person>> + Send + 'static) -> Option<Person> {
        let known = self.state.lock().unwrap().entries.get(key).and_then(|e| e.person.clone());
        if known.is_none() {
            self.learn(key, async move { fetch().await.map(|person| Entry { person: Some(person), channel: None, at: now_ms() }) });
        }
        known
    }

    /// A channel's name; None for a direct message (known) or not known yet.
    pub fn channel(self: &Arc<Self>, key: &str, fetch: impl FnOnce() -> BoxFuture<'static, Option<String>> + Send + 'static) -> Option<String> {
        let known = self.state.lock().unwrap().entries.get(key).and_then(|e| e.channel.clone());
        if known.is_none() {
            self.learn(key, async move { Some(Entry { person: None, channel: Some(fetch().await), at: now_ms() }) });
        }
        known.flatten()
    }

    fn learn(self: &Arc<Self>, key: &str, fetch: impl std::future::Future<Output = Option<Entry>> + Send + 'static) {
        {
            let mut state = self.state.lock().unwrap();
            if state.pending.contains(key) || state.failed.get(key).is_some_and(|until| *until > now_ms()) {
                return;
            }
            state.pending.insert(key.to_string());
        }
        let me = self.clone();
        let key = key.to_string();
        tokio::spawn(async move {
            let entry = fetch.await;
            let mut state = me.state.lock().unwrap();
            state.pending.remove(&key);
            match entry {
                None => {
                    state.failed.insert(key, now_ms() + RETRY_FAILED_MS);
                }
                Some(entry) => {
                    let merged = state.entries.entry(key).or_default();
                    if entry.person.is_some() {
                        merged.person = entry.person;
                    }
                    if entry.channel.is_some() {
                        merged.channel = entry.channel;
                    }
                    merged.at = entry.at;
                    drop(state);
                    me.later();
                }
            }
        });
    }

    fn later(self: &Arc<Self>) {
        let mut state = self.state.lock().unwrap();
        if !state.learning {
            state.learning = true;
            let me = self.clone();
            tokio::spawn(async move {
                tokio::time::sleep(LEARN_AFTER).await;
                me.state.lock().unwrap().learning = false;
                let listener = me.on_learn.lock().unwrap().clone();
                listener();
            });
        }
        if !state.saving {
            state.saving = true;
            let me = self.clone();
            tokio::spawn(async move {
                tokio::time::sleep(SAVE_AFTER).await;
                let text = {
                    let mut state = me.state.lock().unwrap();
                    state.saving = false;
                    serde_json::to_string(&state.entries).unwrap_or_default()
                };
                let tmp = me.path.with_extension("json.tmp");
                if let Err(error) = std::fs::write(&tmp, text).and_then(|_| std::fs::rename(&tmp, &me.path)) {
                    warn!(%error, "cannot save slack names");
                }
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test(start_paused = true)]
    async fn a_name_not_known_yet_is_fetched_once_kept_and_told() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("slack-names.json");
        let book = NameBook::open(path.clone());
        let told = Arc::new(Mutex::new(0));
        let t = told.clone();
        book.on_learn(move || *t.lock().unwrap() += 1);
        let ada = || -> BoxFuture<'static, Option<Person>> { Box::pin(async { Some(Person { name: "Ada".into(), email: "ada@x".into() }) }) };
        assert_eq!(book.person("u:T:U1", ada), None);
        assert_eq!(book.person("u:T:U1", ada), None, "asked again while fetching: not twice");
        assert_eq!(book.channel("c:T:D1", || Box::pin(async { None })), None);
        tokio::time::sleep(Duration::from_secs(3)).await;
        assert_eq!(book.person("u:T:U1", ada).unwrap().name, "Ada");
        assert_eq!(*told.lock().unwrap(), 1, "once per burst");
        // Kept on disk: a direct message known to have no name, and the person.
        let again = NameBook::open(path);
        assert_eq!(again.person("u:T:U1", ada).unwrap().email, "ada@x");
        assert_eq!(again.state.lock().unwrap().entries["c:T:D1"].channel, Some(None));
    }
}
