//! The accounts signed in on this device. Each keeps its own ember cloud
//! session: a short access token and a rotating refresh token. Tokens are
//! refreshed at most once at a time per account (every caller waits on the
//! same refresh), which is what several tabs sharing one core gets right.
//!
//! Wire: POST /v1/auth/token {code, code_verifier, redirect_uri},
//! POST /v1/auth/refresh (Bearer refresh) {request_id: ULID},
//! POST /v1/auth/logout (Bearer refresh) {all:false}; tokens answer
//! {access_token, refresh_token, subject, email, name?, expires_at}.
//! Sign-in starts at GET /v1/auth/google/start?state&code_challenge&code_challenge_method=S256&redirect_uri&name.

use std::rc::Rc;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::error::Result;
use crate::host::Host;

/// Storage key of the accounts list (JSON array of [`StoredAccount`]).
pub const STORAGE_KEY: &str = "accounts";
/// Storage key of the sign-in in progress (verifier, state, return_to).
pub const LOGIN_KEY: &str = "login";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StoredAccount {
    pub sub: String,
    pub email: String,
    pub name: String,
    pub picture: String,
    pub access: String,
    pub refresh: String,
    /// Epoch seconds.
    pub access_expires: f64,
}

/// What UIs see of an account: never its tokens.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AccountView {
    pub sub: String,
    pub email: String,
    pub name: String,
    pub picture: String,
}

pub struct Accounts {
    _host: Rc<dyn Host>,
}

impl Accounts {
    /// Loads the stored accounts.
    pub async fn load(host: Rc<dyn Host>) -> Rc<Accounts> {
        let _ = host;
        todo!("accounts")
    }

    pub fn list(&self) -> Vec<AccountView> {
        todo!()
    }

    /// Called after every change to the list (sign-in, refresh of a name or picture, sign-out).
    pub fn on_change(&self, listener: Rc<dyn Fn()>) {
        let _ = listener;
        todo!()
    }

    /// Starts a sign-in: stores the PKCE verifier and state, returns the URL to open.
    pub async fn begin_sign_in(&self, redirect_uri: &str, return_to: &str, device_name: &str) -> Result<String> {
        let _ = (redirect_uri, return_to, device_name);
        todo!()
    }

    /// Finishes a sign-in from the callback's query string. Returns the account and where to go next.
    pub async fn complete_sign_in(&self, query: &str) -> Result<(AccountView, String)> {
        let _ = query;
        todo!()
    }

    /// A usable access token, refreshing it when it expires within a minute. A refused refresh forgets the account.
    pub async fn access_token(&self, sub: &str) -> Result<String> {
        let _ = sub;
        todo!()
    }

    pub async fn sign_out(&self, sub: &str) -> Result<()> {
        let _ = sub;
        todo!()
    }

    /// Takes over the accounts a page kept before the core existed (localStorage "ember.accounts", camelCase fields).
    pub async fn migrate(&self, accounts: Value) -> Result<()> {
        let _ = accounts;
        todo!()
    }
}
