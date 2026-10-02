//! Chats being changed from here (`chat.rename`, `chat.pin`, `chat.keep`, `chat.archive` back out): shown changed at
//! once, in the chat lists and the chat's page, while its station is asked. Refused, as it was at once. Done, it stays
//! so until the station's rows have changed since the answer (they may come after it): never back to the old value for
//! a moment and over again. Nothing a person does waits on the network to show.

use std::cell::{Cell, RefCell};

use serde_json::{Map, Value};

use super::Views;
use crate::protocol::Topic;

struct Change {
    id: u64,
    station: String,
    /// Its thread; none: an agent with no chat yet, by its session.
    thread: Option<u64>,
    session: String,
    /// What its station's row says once it is done (`title`, `pinned`, `archiveReminderDismissed`).
    row: Map<String, Value>,
    /// Out of the archive (or into it): what its page says meanwhile.
    archived: Option<bool>,
    /// Done: its station's rows as they were when it answered; once they are not, they have it.
    done: Option<Option<Value>>,
}

#[derive(Default)]
pub(super) struct Changing {
    next: Cell<u64>,
    list: RefCell<Vec<Change>>,
}

impl Views {
    /// A chat changed from here, until `changed`: its rows show `row` over the station's, its page `archived`.
    pub fn changing(&self, station: &str, thread: Option<u64>, session: &str, row: Map<String, Value>, archived: Option<bool>) -> u64 {
        let id = self.changing.next.get() + 1;
        self.changing.next.set(id);
        self.changing.list.borrow_mut().push(Change { id, station: station.to_string(), thread, session: session.to_string(), row, archived, done: None });
        self.changing_shown(station);
        id
    }

    /// Answered: refused (`ok` false), as it was at once; done, shown so until its station's rows change.
    pub fn changed(&self, id: u64, ok: bool) {
        let station = {
            let mut list = self.changing.list.borrow_mut();
            let Some(i) = list.iter().position(|c| c.id == id) else { return };
            if ok {
                let station = list[i].station.clone();
                list[i].done = Some(self.ok(Topic::ChatRows { station: station.clone() }));
                return;
            }
            list.remove(i).station
        };
        self.changing_shown(&station);
    }

    /// Lets go of what is done that its station's rows have had since (they changed after its answer).
    pub(super) fn settle_changes(&self, station: &str) {
        if !self.changing.list.borrow().iter().any(|c| c.station == station && c.done.is_some()) {
            return;
        }
        let rows = self.ok(Topic::ChatRows { station: station.to_string() });
        self.changing.list.borrow_mut().retain(|c| c.station != station || c.done.as_ref().is_none_or(|then| *then == rows));
    }

    fn matches(c: &Change, station: &str, thread: Option<u64>, session: Option<&str>) -> bool {
        c.station == station
            && match c.thread {
                Some(t) => thread == Some(t),
                None => session == Some(c.session.as_str()),
            }
    }

    /// A station's row (or the one found for a chat's page) as the changes from here have it, oldest first.
    pub(super) fn as_changing(&self, station: &str, row: &mut Value) {
        let thread = row.get("thread").and_then(Value::as_u64);
        let session = row.get("session").and_then(Value::as_str).map(str::to_string);
        for c in self.changing.list.borrow().iter().filter(|c| Self::matches(c, station, thread, session.as_deref())) {
            if let Some(row) = row.as_object_mut() {
                for (k, v) in &c.row {
                    row.insert(k.clone(), v.clone());
                }
            }
        }
    }

    /// Whether a chat's page is being taken out of the archive (`Some(false)`) or put in it, from here.
    pub(super) fn archived_changing(&self, station: &str, thread: Option<u64>, session: Option<&str>) -> Option<bool> {
        self.changing.list.borrow().iter().rev().filter(|c| Self::matches(c, station, thread, session)).find_map(|c| c.archived)
    }

    /// Whether an archived row is on its way out of the archive from here.
    pub(super) fn restoring(&self, station: &str, row: &Value) -> bool {
        let thread = row.get("thread").and_then(Value::as_u64);
        let session = row.get("session").and_then(Value::as_str);
        self.archived_changing(station, thread, session) == Some(false)
    }

    fn changing_shown(&self, station: &str) {
        let views: Vec<Topic> = self.views.borrow().keys().filter(|v| match v {
            Topic::Chats { .. } | Topic::ChatSearch { .. } | Topic::Archive { .. } | Topic::WorkspaceMarks { .. } | Topic::Decisions { .. } => true,
            Topic::Chat { station: s, .. } => s == station,
            _ => false,
        }).cloned().collect();
        for view in views {
            self.store.invalidate(&view);
        }
    }
}
