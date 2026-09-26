//! `Core`: takes messages from connected UIs, answers calls, keeps
//! subscriptions. Construction wires the modules together: accounts → cloud →
//! mesh links (grants come from cloud as the account that reaches the
//! workspace) → stations; the store routes topics to accounts (accounts,
//! workspaces, workspace) or stations (everything with a station).

use std::rc::Rc;

use crate::host::Host;
use crate::protocol::{ClientId, ClientMessage};

pub struct Core {
    _host: Rc<dyn Host>,
}

impl Core {
    pub async fn new(host: Rc<dyn Host>) -> Core {
        let _ = host;
        todo!("core")
    }

    /// A UI connected; its messages and emissions use this id.
    pub fn connect(&self) -> ClientId {
        todo!()
    }

    /// A UI went away (tab closed, port gone): its subscriptions end.
    pub fn disconnect(&self, client: ClientId) {
        let _ = client;
        todo!()
    }

    /// A message from a UI. Answers and values go out through `Host::emit`.
    pub fn receive(&self, client: ClientId, message: ClientMessage) {
        let _ = (client, message);
        todo!()
    }
}
