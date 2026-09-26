//! ember cloud's account API, called as one of the signed-in accounts.
//! Errors come back as {error: code}; the codes and their Chinese messages
//! mirror web/src/cloud/api.ts.

use std::rc::Rc;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::accounts::Accounts;
use crate::error::Result;
use crate::host::Host;

/// POST /v1/workspaces/:ws/stations/:st/grant {device} answers this.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Grant {
    pub grant: String,
    pub expires_at: f64,
    pub station: String,
    pub station_name: String,
    pub relay_url: String,
}

pub struct Cloud {
    _host: Rc<dyn Host>,
    _accounts: Rc<Accounts>,
}

impl Cloud {
    pub fn new(host: Rc<dyn Host>, accounts: Rc<Accounts>) -> Rc<Cloud> {
        let _ = (host, accounts);
        todo!("cloud")
    }

    /// One call as `sub`: adds the token (refreshing it), parses JSON, maps errors to CoreError with the cloud's code.
    pub async fn request(&self, sub: &str, method: &str, path: &str, body: Option<Value>) -> Result<Value> {
        let _ = (sub, method, path, body);
        todo!()
    }

    /// GET /v1/me: {user, workspaces, invitations, relay_url}.
    pub async fn me(&self, sub: &str) -> Result<Value> {
        let _ = sub;
        todo!()
    }

    pub async fn grant(&self, sub: &str, workspace: &str, station: &str, device: &str) -> Result<Grant> {
        let _ = (sub, workspace, station, device);
        todo!()
    }
}
