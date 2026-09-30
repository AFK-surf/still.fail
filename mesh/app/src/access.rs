//! Who uses the admin API: a member of the station's workspace reaching it through still.fail cloud, whose credential
//! the station's mesh verified (stillfail-station). There is no other way in: the page on this machine and the
//! Cloudflare Access tunnel to it are gone (the loopback port only sends old links to the cloud).

use serde::Serialize;

/// Who is asking.
#[derive(Serialize, Debug, Clone, PartialEq, Eq)]
#[serde(tag = "via", rename_all = "lowercase")]
pub enum Viewer {
    /// A person reaching the station through still.fail cloud; the station's mesh verified their grant.
    Mesh { sub: String, email: String, name: String, role: String, workspace: String, device: String },
}

impl Viewer {
    /// Who did something, for people: a name, else the email.
    pub fn name(&self) -> String {
        let Viewer::Mesh { name, email, .. } = self;
        if name.is_empty() { email.clone() } else { name.clone() }
    }

    /// Who did something, for logs and records: an email. (Records from the page this machine had say "local".)
    pub fn id(&self) -> String {
        let Viewer::Mesh { email, .. } = self;
        email.clone()
    }

    /// Whether they manage the workspace (its owner or an admin).
    pub fn manages(&self) -> bool {
        let Viewer::Mesh { role, .. } = self;
        role == "owner" || role == "admin"
    }
}
