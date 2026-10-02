//! The archive (`Topic::Archive`): the archived chats of a scope's stations online (`Topic::ArchivedRows`) in one
//! list, newest first by the day they were archived. And the chats being archived from here (`chat.archive`): gone
//! from the chat lists at once, until their station answers; back if it could not.

use std::cell::RefCell;

use serde_json::{Value, json};
use stillfail_i18n::t;

use super::Views;
use crate::error::Result;
use crate::protocol::Topic;

/// The chats on their way into the archive from here: station, thread (none: an agent with no chat yet), session.
#[derive(Default)]
pub(super) struct Archiving(RefCell<Vec<(String, Option<u64>, String)>>);

impl Views {
    /// A chat on its way into the archive (`on`), or answered either way: the chat lists leave it out meanwhile. Once
    /// answered, its station's rows (read again before the answer, station.rs `after_write`) say whether it is gone.
    pub fn archiving(&self, station: &str, thread: Option<u64>, session: &str, on: bool) {
        {
            let mut list = self.archiving.0.borrow_mut();
            let chat = (station.to_string(), thread, session.to_string());
            if on {
                list.push(chat);
            } else if let Some(i) = list.iter().position(|c| *c == chat) {
                list.remove(i);
            }
        }
        let views: Vec<Topic> = self.views.borrow().keys().filter(|v| matches!(v, Topic::Chats { .. } | Topic::WorkspaceMarks { .. } | Topic::Decisions { .. })).cloned().collect();
        for view in views {
            self.store.invalidate(&view);
        }
    }

    /// Whether a station's row is a chat on its way into the archive from here.
    pub(super) fn being_archived(&self, station: &str, row: &Value) -> bool {
        self.archiving.0.borrow().iter().any(|(s, thread, session)| {
            s == station
                && match thread {
                    Some(thread) => row.get("thread").and_then(Value::as_u64) == Some(*thread),
                    None => row.get("session").and_then(Value::as_str) == Some(session.as_str()),
                }
        })
    }

    pub(super) fn archive(&self, scope: &str) -> Option<Result<Value>> {
        let stations = match self.stations(scope) {
            None => return Some(Ok(json!({ "days": [], "errors": [], "loading": true, "note": t!("core-views.archive.reading_stations") }))),
            Some(Err(error)) => return Some(Err(error)),
            Some(Ok(stations)) => stations,
        };
        let online: Vec<_> = stations.iter().filter(|s| s.online).collect();
        // Which station a chat is on is said only where there is more than one to tell apart.
        let named = online.len() > 1;
        let (mut items, mut errors, mut loading) = (Vec::new(), Vec::new(), false);
        for s in online.iter() {
            let place = named.then(|| s.name.clone());
            match self.store.value(&Topic::ArchivedRows { station: s.address.clone() }) {
                None => loading = true,
                Some(Err(error)) => {
                    let text = match &place { Some(name) => t!("core-views.named_error", name = name, error = error.message), None => error.message };
                    errors.push(json!({ "station": s.address, "text": text }));
                }
                // A station from before the archive answers the chats it shows: none says `archived`, so none is.
                Some(Ok(list)) => items.extend(list.as_array().into_iter().flatten().filter(|c| c.get("archived").is_some_and(Value::is_object)).map(|chat| {
                    let mark = &chat["archived"];
                    let at = mark.get("at").or_else(|| chat.get("lastActiveAt")).and_then(Value::as_f64).unwrap_or(0.0);
                    let text = |v: Option<&Value>| v.and_then(Value::as_str).unwrap_or("").to_string();
                    json!({
                        "station": s.address, "session": text(chat.get("session")), "thread": chat.get("thread").cloned().unwrap_or(Value::Null),
                        "title": text(chat.get("title")), "last": text(chat.get("last").and_then(|l| l.get("text"))),
                        "at": at, "clock": crate::format::clock(at, self.host.utc_offset_min(at)),
                        "how": if mark.get("by").and_then(Value::as_str) == Some("auto") { t!("core-views.archive.auto") } else { t!("core-views.archive.manual") },
                        // Archived alone, its agents are still at work elsewhere: nothing of theirs is deleted from here.
                        "deletable": mark.get("alone").and_then(Value::as_bool) != Some(true),
                        "place": place,
                    })
                })),
            }
        }
        let at = |item: &Value| item["at"].as_f64().unwrap_or(0.0);
        items.sort_by(|a, b| at(b).total_cmp(&at(a)));
        let now = self.host.now_ms();
        let offset = self.host.utc_offset_min(now);
        let mut days: Vec<(String, Vec<Value>)> = Vec::new();
        for item in items {
            let label = day_label(at(&item), now, offset);
            match days.last_mut() {
                Some((last, same)) if *last == label => same.push(item),
                _ => days.push((label, vec![item])),
            }
        }
        let note = if online.is_empty() {
            Some(t!("core-views.archive.none_online"))
        } else if days.is_empty() && loading {
            Some(t!("core-views.archive.reading"))
        } else if days.is_empty() && errors.is_empty() {
            Some(t!("core-views.archive.empty"))
        } else {
            None
        };
        let days: Vec<Value> = days.into_iter().map(|(label, items)| json!({ "label": label, "items": items })).collect();
        Some(Ok(json!({ "days": days, "errors": errors, "loading": loading, "note": note })))
    }
}

/// The chat list's day headings (今天, 昨天, 星期三, 9月20日), with the year before this one's.
fn day_label(at: f64, now: f64, offset: i32) -> String {
    let label = crate::format::day_label(at, now, offset);
    let year = crate::format::local(at, offset).0;
    // A date (not 今天, 昨天 or a weekday: a week or more ago).
    let dated = crate::format::local_day(now, offset) - crate::format::local_day(at, offset) >= 7;
    if dated && year != crate::format::local(now, offset).0 { t!("core-views.archive.day_with_year", year = year, day = label) } else { label }
}
