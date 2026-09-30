//! What a chat says of its connection (the `connection` topic; web/src/Connection.tsx and Android
//! screens/Connection.kt draw it as a pill over the chat): its link to its station while down or coming back
//! (looks.rs `link_shown`), else what its workspace's `status` says (status.rs) — never another workspace's. When it
//! shows is decided here too, so the pages only draw it:
//! - trouble (down) at once;
//! - busy (coming back) only once it has lasted [`BUSY_MS`]: a link that drops and is back at once says nothing. What
//!   the status says has lasted a while by then already (status.rs `SLOW_MS`) and shows at once;
//! - back ("已连上") for [`BACK_MS`] once all is well again, only after a busy or a trouble was shown.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::{Rc, Weak};

use futures::FutureExt;
use serde_json::{Value, json};

use crate::host::Host;
use crate::protocol::Topic;
use crate::store::{Store, Watch};
use crate::views::Views;

/// How long a link coming back goes unsaid.
pub const BUSY_MS: f64 = 1_500.0;
/// How long "已连上" stays once all is well again.
pub const BACK_MS: f64 = 1_500.0;

/// When what is not as it should be shows, as it goes on.
#[derive(Default, Debug)]
pub struct Timing {
    /// Since when something has not been as it should be; none while all is well.
    since: Option<f64>,
    /// Something was shown since then.
    shown: bool,
    /// Until when "已连上" shows.
    back_until: Option<f64>,
}

fn nothing() -> Value {
    json!({ "tone": null, "text": null, "items": [] })
}

impl Timing {
    /// What shows at `now`, given what is not as it should be (`raw`, a ConnectionView with a tone; `lasted`: it has
    /// lasted a while already), and in how many ms it is to be looked at again (a busy not shown yet, a back ending).
    pub fn step(&mut self, now: f64, raw: Option<(Value, bool)>) -> (Value, Option<f64>) {
        match raw {
            Some((raw, lasted)) => {
                let since = *self.since.get_or_insert(now);
                if lasted || self.shown || raw["tone"] == "trouble" || now - since >= BUSY_MS {
                    self.shown = true;
                    self.back_until = None;
                    return (raw, None);
                }
                // Not yet: looked at again once it has lasted; what was back is not any more.
                self.back_until = None;
                (nothing(), Some(since + BUSY_MS - now))
            }
            None => {
                if self.since.take().is_some() && std::mem::replace(&mut self.shown, false) {
                    self.back_until = Some(now + BACK_MS);
                }
                match self.back_until {
                    Some(until) if now < until => (json!({ "tone": "back", "text": "已连上", "items": [] }), Some(until - now)),
                    _ => {
                        self.back_until = None;
                        (nothing(), None)
                    }
                }
            }
        }
    }
}

/// What is not as it should be for a chat on a station, before when it shows is decided: its link (as looks.rs says
/// it, null while up) while down or coming back, else its workspace's status; and whether it has lasted already.
pub fn raw(link: &Value, status: Option<&Value>) -> Option<(Value, bool)> {
    let items = status.and_then(|s| s.get("items")).cloned().unwrap_or_else(|| json!([]));
    if link.is_object() {
        let trouble = link["tone"] == "trouble";
        let tone = if trouble { "trouble" } else { "busy" };
        // What else is waited on goes with it while it comes back.
        return Some((json!({ "tone": tone, "text": link["text"], "detail": link["detail"], "items": if trouble { json!([]) } else { items } }), false));
    }
    let status = status?;
    let text = |or: &str| status.get("text").and_then(Value::as_str).unwrap_or(or).to_string();
    match status.get("state").and_then(Value::as_str) {
        Some("trouble") => Some((json!({ "tone": "trouble", "text": text("连不上 still.fail cloud"), "items": items }), true)),
        Some("slow") => Some((json!({ "tone": "busy", "text": text(""), "items": items }), true)),
        _ => None,
    }
}

struct Live {
    /// Its station's link and its workspace's status: when they change, it is computed again.
    _watches: Vec<Watch>,
    timing: Timing,
    /// When it is to be looked at again, if it is (one timer at a time).
    due: Option<f64>,
}

/// The live `connection` topics.
pub struct Pills {
    host: Rc<dyn Host>,
    store: Rc<Store>,
    views: Rc<Views>,
    me: Weak<Pills>,
    live: RefCell<HashMap<Topic, Live>>,
}

impl Pills {
    pub fn new(host: Rc<dyn Host>, store: Rc<Store>, views: Rc<Views>) -> Rc<Pills> {
        Rc::new_cyclic(|me| Pills { host, store, views, me: me.clone(), live: RefCell::default() })
    }

    /// What a chat's connection is shown from: its station's link and its workspace's status.
    fn sources(station: &str) -> [Topic; 2] {
        let workspace = crate::workspace::of_address(station).to_string();
        [Topic::Link { station: station.to_string() }, Topic::Status { workspace: Some(workspace) }]
    }

    pub fn start(&self, topic: &Topic) {
        let Topic::Connection { station } = topic else { return };
        let watches = Self::sources(station).iter().map(|source| {
            let (store, topic) = (Rc::downgrade(&self.store), topic.clone());
            self.store.watch(source, Rc::new(move || {
                if let Some(store) = store.upgrade() {
                    store.invalidate(&topic);
                }
            }))
        }).collect();
        self.live.borrow_mut().insert(topic.clone(), Live { _watches: watches, timing: Timing::default(), due: None });
        self.store.invalidate(topic);
    }

    pub fn stop(&self, topic: &Topic) {
        let gone = self.live.borrow_mut().remove(topic);
        drop(gone);
    }

    pub fn compute(&self, topic: &Topic) -> Option<Value> {
        let Topic::Connection { station } = topic else { return None };
        let [link, status] = Self::sources(station);
        let link = match self.store.get(&link) {
            Some(link) => crate::looks::link_shown(&link, &self.views.station_name(station)),
            None => Value::Null,
        };
        let status = self.store.get(&status);
        let now = self.host.now_ms();
        let (value, again) = {
            let mut live = self.live.borrow_mut();
            let entry = live.get_mut(topic)?;
            let (value, again) = entry.timing.step(now, raw(&link, status.as_ref()));
            let at = again.map(|ms| now + ms);
            let fresh = at.is_some_and(|at| entry.due.is_none_or(|due| due != at));
            entry.due = at;
            (value, again.filter(|_| fresh))
        };
        if let Some(ms) = again {
            let (me, topic, sleep) = (self.me.clone(), topic.clone(), self.host.sleep(ms.ceil().max(0.0) as u64));
            self.host.spawn(async move {
                sleep.await;
                if let Some(pills) = me.upgrade() && pills.live.borrow().contains_key(&topic) {
                    pills.store.invalidate(&topic);
                }
            }.boxed_local());
        }
        Some(value)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn link(tone: &str) -> Value {
        json!({ "tone": tone, "text": format!("{tone} 「studio」") })
    }

    fn tone(value: &Value) -> Option<&str> {
        value["tone"].as_str()
    }

    #[test]
    fn coming_back_shows_once_it_lasted_and_back_only_after_that() {
        let mut t = Timing::default();
        let busy = || raw(&link("busy"), None);
        // Dropped and back at once: nothing, and no 已连上 after.
        assert_eq!(t.step(0.0, busy()), (nothing(), Some(BUSY_MS)));
        assert_eq!(tone(&t.step(1_000.0, busy()).0), None);
        assert_eq!(t.step(1_200.0, None), (nothing(), None));
        // Coming back for 1.5 s: said, then 已连上 for a moment.
        t.step(2_000.0, busy());
        assert_eq!(tone(&t.step(3_500.0, busy()).0), Some("busy"));
        let (back, again) = t.step(4_000.0, None);
        assert_eq!((tone(&back), again), (Some("back"), Some(BACK_MS)));
        assert_eq!(tone(&t.step(5_000.0, None).0), Some("back"));
        assert_eq!(t.step(5_500.0, None), (nothing(), None));
    }

    #[test]
    fn trouble_and_what_the_status_says_show_at_once() {
        let mut t = Timing::default();
        let (shown, again) = t.step(0.0, raw(&link("trouble"), None));
        assert_eq!((tone(&shown), again), (Some("trouble"), None));
        // Down, then coming back: the one episode, said as it goes.
        assert_eq!(tone(&t.step(100.0, raw(&link("busy"), None)).0), Some("busy"));
        assert_eq!(tone(&t.step(200.0, None).0), Some("back"));
        let mut t = Timing::default();
        let slow = json!({ "state": "slow", "text": "studio 读取对话 · 2 秒", "items": [{ "state": "slow", "text": "studio 读取对话", "detail": "已等 2 秒" }] });
        let (shown, _) = t.step(0.0, raw(&Value::Null, Some(&slow)));
        assert_eq!((tone(&shown), shown["items"][0]["text"].as_str()), (Some("busy"), Some("studio 读取对话")));
        // Up, nothing waited on: nothing to say.
        assert_eq!(raw(&Value::Null, Some(&json!({ "state": null, "text": null, "items": [] }))), None);
    }
}
