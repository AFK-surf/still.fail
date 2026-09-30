//! Workspaces: the units the core keeps apart. Stations are grouped into workspaces, and what the core has of one
//! workspace is its own: the account that reaches it, its stations (what is kept of each while any of its topics is
//! live, station.rs), what is waited on for them (status.rs), what its person hears of it (notices.rs) and what the core
//! keeps in sync of it (sync.rs). What a new chat was last started on is kept per workspace too (choose.rs). Nothing
//! of one is read or dropped through another.
//!
//! What is the device's stays shared: the host, the tracer, the mesh endpoint (one device identity, a link per
//! station), the relays, what is kept on the device (the store, the data center, the logs; their keys are as they
//! were), the notifications' settings and what the device likes. What is an account's (its tokens, its still.fail
//! cloud socket, its `/v1/me`) is kept by account.
//!
//! A station's own page (`local`) is a workspace of its own, [`LOCAL`], with no account.

use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};
use std::rc::Rc;

use crate::host::Host;
use crate::notices::Heard;
use crate::protocol::Topic;
use crate::station::StationState;
use crate::status::{NameOf, Status};
use crate::store::Watch;

/// The workspace of a station's own page (its address is `local` too).
pub const LOCAL: &str = "local";

/// The workspace a station's address (`"<workspace>/<station>"`, `local`) is in.
pub fn of_address(address: &str) -> &str {
    address.split_once('/').map_or(address, |(workspace, _)| workspace)
}

pub struct Workspace {
    pub id: String,
    /// The signed-in account that reaches it, as the latest `/v1/me` answers say; none for `local`, or not known yet.
    owner: RefCell<Option<String>>,
    /// Its stations while any of their topics is live, by address (station.rs).
    pub(crate) stations: RefCell<HashMap<String, StationState>>,
    /// What is waited on for its stations: their requests, and the relay and links opened for them (status.rs).
    pub status: Rc<Status>,
    /// How its stations' chat rows were when last looked at, and what was heard of them (notices.rs).
    pub(crate) heard: RefCell<Heard>,
    /// What the core keeps in sync of it, each held by a watch (sync.rs).
    pub(crate) synced: RefCell<HashMap<Topic, Watch>>,
}

impl Workspace {
    pub fn owner(&self) -> Option<String> {
        self.owner.borrow().clone()
    }
}

/// Every workspace the core has had to do with this run, by id: made on first use, and kept (a workspace with nothing
/// live is a few empty maps).
pub struct Workspaces {
    host: Rc<dyn Host>,
    all: RefCell<BTreeMap<String, Rc<Workspace>>>,
    /// Told the workspace whose status changed (the store invalidates the `status` topics that show it).
    status_changed: RefCell<Option<Rc<dyn Fn(&str)>>>,
    /// Station names by address, for what a status says.
    names: RefCell<Option<NameOf>>,
}

impl Workspaces {
    pub fn new(host: Rc<dyn Host>) -> Rc<Workspaces> {
        Rc::new(Workspaces { host, all: RefCell::default(), status_changed: RefCell::default(), names: RefCell::default() })
    }

    /// What a workspace's status changing calls, and the names its status says (the workspaces made so far too).
    pub fn wire_status(&self, changed: Rc<dyn Fn(&str)>, names: NameOf) {
        *self.status_changed.borrow_mut() = Some(changed);
        *self.names.borrow_mut() = Some(names);
        for workspace in self.all() {
            self.wire(&workspace);
        }
    }

    fn wire(&self, workspace: &Workspace) {
        if let Some(changed) = self.status_changed.borrow().clone() {
            let id = workspace.id.clone();
            workspace.status.on_change(Rc::new(move || changed(&id)));
        }
        if let Some(names) = self.names.borrow().clone() {
            workspace.status.set_names(names);
        }
    }

    pub fn get(&self, id: &str) -> Option<Rc<Workspace>> {
        self.all.borrow().get(id).cloned()
    }

    /// The workspace `id`, made the first time.
    pub fn of(&self, id: &str) -> Rc<Workspace> {
        if let Some(workspace) = self.get(id) {
            return workspace;
        }
        let workspace = Rc::new(Workspace {
            id: id.to_string(),
            owner: RefCell::default(),
            stations: RefCell::default(),
            status: Status::new(self.host.clone()),
            heard: RefCell::default(),
            synced: RefCell::default(),
        });
        self.wire(&workspace);
        self.all.borrow_mut().insert(id.to_string(), workspace.clone());
        workspace
    }

    /// The workspace a station is in, by its address.
    pub fn of_station(&self, address: &str) -> Rc<Workspace> {
        self.of(of_address(address))
    }

    pub fn all(&self) -> Vec<Rc<Workspace>> {
        self.all.borrow().values().cloned().collect()
    }

    /// Which account reaches each workspace, as `/v1/me` now says: those it names get theirs, every other one none.
    pub fn set_owners(&self, owners: &HashMap<String, String>) {
        for (id, sub) in owners {
            *self.of(id).owner.borrow_mut() = Some(sub.clone());
        }
        for workspace in self.all() {
            if !owners.contains_key(&workspace.id) {
                *workspace.owner.borrow_mut() = None;
            }
        }
    }

    pub fn owner(&self, id: &str) -> Option<String> {
        self.get(id).and_then(|w| w.owner())
    }

    /// The workspaces an account reaches.
    pub fn owned(&self) -> Vec<(String, String)> {
        self.all().into_iter().filter_map(|w| Some((w.id.clone(), w.owner()?))).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::FakeHost;

    #[test]
    fn a_station_is_in_the_workspace_its_address_names_and_local_is_its_own() {
        assert_eq!(of_address("ws/st"), "ws");
        assert_eq!(of_address("local"), LOCAL);
        let workspaces = Workspaces::new(FakeHost::new());
        assert!(Rc::ptr_eq(&workspaces.of_station("ws/a"), &workspaces.of_station("ws/b")));
        assert!(!Rc::ptr_eq(&workspaces.of_station("ws/a"), &workspaces.of_station("other/a")));
        workspaces.set_owners(&HashMap::from([("ws".to_string(), "s1".to_string())]));
        assert_eq!(workspaces.owner("ws").as_deref(), Some("s1"));
        assert_eq!(workspaces.owner("other"), None);
        workspaces.set_owners(&HashMap::new());
        assert_eq!(workspaces.owner("ws"), None);
    }
}
