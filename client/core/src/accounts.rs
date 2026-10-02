//! The accounts signed in on this device. Each keeps its own still.fail cloud
//! session: a short access token and a rotating refresh token. Tokens are
//! refreshed at most once at a time per account (every caller waits on the
//! same refresh), which is what several tabs sharing one core gets right.
//!
//! Wire: POST /v1/auth/token {code, code_verifier, redirect_uri},
//! POST /v1/auth/refresh (Bearer refresh) {request_id: ULID},
//! POST /v1/auth/logout (Bearer refresh) {all:false}; tokens answer
//! {access_token, refresh_token, subject, email, name?, expires_at}.
//! Sign-in starts at GET /v1/auth/google/start?state&code_challenge&code_challenge_method=S256&redirect_uri&name.

use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::{Rc, Weak};

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use futures::future::{FutureExt, LocalBoxFuture, Shared};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use stillfail_i18n::t;
use sha2::{Digest, Sha256};

use crate::error::{CoreError, Result};
use crate::host::{Host, HttpRequest, HttpResponse};
use crate::trace::{Kind, Tracer};

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

impl From<&StoredAccount> for AccountView {
    fn from(a: &StoredAccount) -> Self {
        AccountView { sub: a.sub.clone(), email: a.email.clone(), name: a.name.clone(), picture: a.picture.clone() }
    }
}

#[derive(Debug, Serialize, Deserialize)]
struct PendingLogin {
    verifier: String,
    state: String,
    return_to: String,
    redirect_uri: String,
}

#[derive(Debug, Deserialize)]
struct Tokens {
    access_token: String,
    refresh_token: String,
    subject: String,
    email: String,
    #[serde(default)]
    name: Option<String>,
    expires_at: f64,
}

/// The page's localStorage entry before the core existed.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyAccount {
    sub: String,
    email: String,
    #[serde(default)]
    name: String,
    #[serde(default)]
    picture: String,
    access: String,
    refresh: String,
    access_expires: f64,
}

type Refresh = Shared<LocalBoxFuture<'static, Result<String>>>;

pub struct Accounts {
    host: Rc<dyn Host>,
    /// Lets a refresh outlive the call that started it (it is shared by later callers).
    me: Weak<Accounts>,
    list: RefCell<Vec<StoredAccount>>,
    listeners: RefCell<Vec<Rc<dyn Fn()>>>,
    refreshing: RefCell<HashMap<String, Refresh>>,
    /// Where refreshes are traced (docs/telemetry.md, signing out); none until the core sets it.
    tracer: RefCell<Option<Rc<Tracer>>>,
    /// Since when (monotonic ms) a refresh has had no answer: still.fail cloud may have rotated the credential all the
    /// same, and the next refresh says how long ago that was.
    unanswered: Cell<Option<f64>>,
}

impl Accounts {
    /// Loads the stored accounts.
    pub async fn load(host: Rc<dyn Host>) -> Rc<Accounts> {
        let list = match host.storage_get(STORAGE_KEY).await {
            Ok(Some(bytes)) => serde_json::from_slice(&bytes).unwrap_or_default(),
            _ => Vec::new(),
        };
        Rc::new_cyclic(|me| Accounts {
            host,
            me: me.clone(),
            list: RefCell::new(list),
            listeners: RefCell::default(),
            refreshing: RefCell::default(),
            tracer: RefCell::default(),
            unanswered: Cell::default(),
        })
    }

    /// Traces every refresh from now on.
    pub fn set_tracer(&self, tracer: Rc<Tracer>) {
        *self.tracer.borrow_mut() = Some(tracer);
    }

    pub fn list(&self) -> Vec<AccountView> {
        self.list.borrow().iter().map(AccountView::from).collect()
    }

    /// Called after every change to the list (sign-in, refresh of a name or picture, sign-out).
    pub fn on_change(&self, listener: Rc<dyn Fn()>) {
        self.listeners.borrow_mut().push(listener);
    }

    /// Starts a sign-in: stores the PKCE verifier and state, returns the URL to open.
    pub async fn begin_sign_in(&self, redirect_uri: &str, return_to: &str, device_name: &str) -> Result<String> {
        let verifier = self.secret();
        let state = self.secret();
        let pending = PendingLogin {
            verifier: verifier.clone(),
            state: state.clone(),
            return_to: return_to.into(),
            redirect_uri: redirect_uri.into(),
        };
        self.host.storage_set(LOGIN_KEY, serde_json::to_vec(&pending).unwrap()).await?;
        let query = [
            ("state", state.as_str()),
            ("code_challenge", &challenge(&verifier)),
            ("code_challenge_method", "S256"),
            ("redirect_uri", redirect_uri),
            ("name", device_name),
        ]
        .iter()
        .map(|(k, v)| format!("{k}={}", encode_component(v)))
        .collect::<Vec<_>>()
        .join("&");
        Ok(format!("{}/v1/auth/google/start?{query}", self.host.cloud_origin()))
    }

    /// Finishes a sign-in from the callback's query string. Returns the account and where to go next.
    pub async fn complete_sign_in(&self, query: &str) -> Result<(AccountView, String)> {
        let params = parse_query(query);
        let param = |k: &str| params.iter().find(|(n, _)| n == k).map(|(_, v)| v.as_str());
        // A login is good for one try, whatever its outcome.
        let pending = self.host.storage_get(LOGIN_KEY).await.ok().flatten().and_then(|b| serde_json::from_slice::<PendingLogin>(&b).ok());
        let _ = self.host.storage_delete(LOGIN_KEY).await;
        if let Some(error) = param("error").filter(|e| !e.is_empty()) {
            return Err(if error == "login_cancelled" {
                CoreError::new("login_cancelled", t!("core-logic.accounts.login.cancelled"))
            } else {
                CoreError::new("login_failed", t!("core-logic.accounts.login.failed"))
            });
        }
        let pending = match pending {
            Some(p) if param("state") == Some(p.state.as_str()) => p,
            _ => return Err(CoreError::new("login_state_mismatch", t!("core-logic.accounts.login.state_mismatch"))),
        };
        let expired = || CoreError::new("login_expired", t!("core-logic.accounts.login.expired"));
        let body = json!({ "code": param("code"), "code_verifier": pending.verifier, "redirect_uri": pending.redirect_uri });
        let response = self.post("/v1/auth/token", None, body, None).await.map_err(|_| expired())?;
        if !ok(&response) {
            return Err(expired().with_status(response.status));
        }
        let tokens: Tokens = serde_json::from_slice(&response.body).map_err(|_| expired())?;
        let mut account = StoredAccount {
            sub: tokens.subject,
            email: tokens.email,
            name: tokens.name.unwrap_or_default(),
            picture: String::new(),
            access: tokens.access_token,
            refresh: tokens.refresh_token,
            access_expires: tokens.expires_at,
        };
        self.put(account.clone()).await?;
        // The picture comes with the profile; fetched once, best effort.
        if let Some(picture) = self.picture(&account.access).await {
            account.picture = picture;
            let _ = self.put(account.clone()).await;
        }
        let return_to = if pending.return_to.is_empty() || pending.return_to.starts_with("/auth/") { "/".into() } else { pending.return_to };
        Ok((AccountView::from(&account), return_to))
    }

    /// A usable access token, refreshing it when it expires within a minute. A refused refresh forgets the account.
    pub async fn access_token(&self, sub: &str) -> Result<String> {
        let now = self.host.now_ms() / 1000.0;
        match self.get(sub) {
            None => return Err(CoreError::signed_out(t!("core-logic.accounts.signed_out"))),
            Some(a) if a.access_expires - 60.0 > now => return Ok(a.access),
            Some(_) => {}
        }
        let existing = self.refreshing.borrow().get(sub).cloned();
        let refresh = match existing {
            Some(r) => r,
            None => {
                let me = self.me.clone();
                let owned = sub.to_string();
                let refresh = async move {
                    let this = me.upgrade().ok_or_else(|| CoreError::signed_out(t!("core-logic.accounts.signed_out")))?;
                    let result = this.refresh(&owned).await;
                    this.refreshing.borrow_mut().remove(&owned);
                    result
                }
                .boxed_local()
                .shared();
                self.refreshing.borrow_mut().insert(sub.into(), refresh.clone());
                refresh
            }
        };
        refresh.await
    }

    pub async fn sign_out(&self, sub: &str) -> Result<()> {
        if let Some(account) = self.get(sub) {
            let _ = self.post("/v1/auth/logout", Some(&account.refresh), json!({ "all": false }), None).await;
        }
        self.forget(sub).await
    }

    /// Takes over the accounts a page kept before the core existed (localStorage "ember.accounts", camelCase fields).
    /// Accepts the parsed array or the raw JSON string. An account already here is replaced only by a newer session.
    pub async fn migrate(&self, accounts: Value) -> Result<()> {
        let accounts = match accounts {
            Value::String(text) => serde_json::from_str(&text).map_err(|_| CoreError::invalid(t!("core-logic.accounts.invalid_json")))?,
            Value::Null => return Ok(()),
            other => other,
        };
        let Value::Array(items) = accounts else {
            return Err(CoreError::invalid(t!("core-logic.accounts.not_array")));
        };
        let mut changed = false;
        {
            let mut list = self.list.borrow_mut();
            for item in items {
                let Ok(old) = serde_json::from_value::<LegacyAccount>(item) else { continue };
                let account = StoredAccount {
                    sub: old.sub,
                    email: old.email,
                    name: old.name,
                    picture: old.picture,
                    access: old.access,
                    refresh: old.refresh,
                    access_expires: old.access_expires,
                };
                match list.iter_mut().find(|a| a.sub == account.sub) {
                    Some(existing) if existing.access_expires >= account.access_expires => {}
                    Some(existing) => *existing = account,
                    None => list.push(account),
                }
                changed = true;
            }
        }
        if changed { self.save().await } else { Ok(()) }
    }

    /// Takes the stored credentials of `sub` when another core wrote newer ones; their access token when still good.
    async fn adopt_stored(&self, sub: &str) -> Option<String> {
        let bytes = self.host.storage_get(STORAGE_KEY).await.ok().flatten()?;
        let stored: Vec<StoredAccount> = serde_json::from_slice(&bytes).ok()?;
        let theirs = stored.into_iter().find(|a| a.sub == sub)?;
        let ours = self.get(sub)?;
        if theirs.refresh == ours.refresh {
            return None;
        }
        let good = theirs.access_expires - 60.0 > self.host.now_ms() / 1000.0;
        let access = theirs.access.clone();
        if let Some(entry) = self.list.borrow_mut().iter_mut().find(|a| a.sub == sub) {
            *entry = theirs;
        }
        good.then_some(access)
    }

    fn get(&self, sub: &str) -> Option<StoredAccount> {
        self.list.borrow().iter().find(|a| a.sub == sub).cloned()
    }

    async fn refresh(&self, sub: &str) -> Result<String> {
        // Another core on the same storage (a tab still on the worker of an earlier deploy, say) may have refreshed
        // already: its credentials are the current ones, and refreshing with ours now would be taken for reuse.
        if let Some(access) = self.adopt_stored(sub).await {
            return Ok(access);
        }
        let account = self.get(sub).ok_or_else(|| CoreError::signed_out(t!("core-logic.accounts.signed_out")))?;
        let body = json!({ "request_id": ulid(self.host.as_ref()) });
        // Every refresh is a trace of its own, recorded whatever the sampling: still.fail cloud's span of it says what
        // became of the session (rotated, refused as reused, gone), which is how a device's signing out is explained.
        let tracer = self.tracer.borrow().clone();
        let mut span = tracer.map(|t| t.always("auth.refresh", Kind::Client));
        if let (Some(span), Some(at)) = (&mut span, self.unanswered.get()) {
            span.set("stillfail.auth.unanswered_ago_ms", (self.host.monotonic_ms() - at) as u64);
        }
        let traceparent = span.as_ref().map(|s| s.context().traceparent());
        // Unanswered until it is (given up on, or dropped by a wake, it stays so).
        self.unanswered.set(Some(self.host.monotonic_ms()));
        let response = self.post("/v1/auth/refresh", Some(&account.refresh), body, traceparent).await;
        let response = match response {
            Ok(response) => response,
            Err(error) => {
                if let Some(mut span) = span {
                    span.set("error.type", error.code.clone());
                    span.fail();
                    span.end();
                }
                return Err(error);
            }
        };
        self.unanswered.set(None);
        if let Some(mut span) = span {
            span.set("http.response.status_code", response.status);
            if !ok(&response) {
                let code = serde_json::from_slice::<Value>(&response.body).ok().and_then(|v| v.get("error")?.as_str().map(String::from));
                span.set("error.type", code.unwrap_or_else(|| format!("http_{}", response.status)));
                span.fail();
            }
            span.end();
        }
        if response.status == 401 {
            let _ = self.forget(sub).await;
            return Err(CoreError::signed_out(t!("core-logic.accounts.session_expired", email = account.email)).with_status(401));
        }
        if !ok(&response) {
            return Err(CoreError::new("refresh_failed", t!("core-logic.accounts.refresh_failed", status = response.status)).with_status(response.status));
        }
        let tokens: Tokens = serde_json::from_slice(&response.body)
            .map_err(|_| CoreError::new("refresh_failed", t!("core-logic.accounts.refresh_unreadable")))?;
        let name = tokens.name.filter(|n| !n.is_empty()).unwrap_or(account.name.clone());
        let access = tokens.access_token.clone();
        // The new tokens are good even if they cannot be written down.
        let _ = self
            .put(StoredAccount { access: tokens.access_token, refresh: tokens.refresh_token, access_expires: tokens.expires_at, name, ..account })
            .await;
        Ok(access)
    }

    async fn picture(&self, access: &str) -> Option<String> {
        let request = HttpRequest {
            method: "GET".into(),
            url: format!("{}/v1/me", self.host.cloud_origin()),
            headers: vec![("authorization".into(), format!("Bearer {access}"))],
            body: None,
        };
        let response = self.host.fetch(request).await.ok()?;
        let me: Value = serde_json::from_slice(&response.body).ok()?;
        me.pointer("/user/picture")?.as_str().filter(|p| !p.is_empty()).map(String::from)
    }

    async fn post(&self, path: &str, bearer: Option<&str>, body: Value, traceparent: Option<String>) -> Result<HttpResponse> {
        let mut headers = vec![("content-type".to_string(), "application/json".to_string())];
        if let Some(traceparent) = traceparent {
            headers.push(("traceparent".into(), traceparent));
        }
        if let Some(token) = bearer {
            headers.push(("authorization".into(), format!("Bearer {token}")));
        }
        // A refresh asked twice with its one `request_id` is answered the same (cloud/src/account.ts, the retry
        // window): it may go again on a new connection beside one that went quiet (wake.rs).
        if path == "/v1/auth/refresh" {
            headers.push((crate::wake::HEDGE.into(), "1".into()));
        }
        let request = HttpRequest {
            method: "POST".into(),
            url: format!("{}{path}", self.host.cloud_origin()),
            headers,
            body: Some(serde_json::to_vec(&body).unwrap()),
        };
        Ok(self.host.fetch(request).await?)
    }

    /// Adds or replaces an account, keeping its place in the list.
    async fn put(&self, account: StoredAccount) -> Result<()> {
        {
            let mut list = self.list.borrow_mut();
            match list.iter_mut().find(|a| a.sub == account.sub) {
                Some(existing) => *existing = account,
                None => list.push(account),
            }
        }
        self.save().await
    }

    async fn forget(&self, sub: &str) -> Result<()> {
        let before = self.list.borrow().len();
        self.list.borrow_mut().retain(|a| a.sub != sub);
        if self.list.borrow().len() == before {
            return Ok(());
        }
        self.save().await
    }

    /// Writes the list and tells the listeners. Memory is updated first, so a failed write still changes this session.
    async fn save(&self) -> Result<()> {
        let bytes = serde_json::to_vec(&*self.list.borrow()).unwrap();
        let written = self.host.storage_set(STORAGE_KEY, bytes).await;
        let listeners = self.listeners.borrow().clone();
        for listener in listeners {
            listener();
        }
        Ok(written?)
    }

    fn secret(&self) -> String {
        let mut bytes = [0u8; 32];
        self.host.random_bytes(&mut bytes);
        URL_SAFE_NO_PAD.encode(bytes)
    }
}

fn ok(response: &HttpResponse) -> bool {
    (200..300).contains(&response.status)
}

/// PKCE S256: base64url(sha256(verifier)).
fn challenge(verifier: &str) -> String {
    URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()))
}

/// A ULID, which still.fail cloud wants as the id of each refresh request.
fn ulid(host: &dyn Host) -> String {
    const ALPHABET: &[u8; 32] = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    let mut time = host.now_ms() as u64;
    let mut out = [0u8; 26];
    for i in (0..10).rev() {
        out[i] = ALPHABET[(time % 32) as usize];
        time /= 32;
    }
    let mut random = [0u8; 16];
    host.random_bytes(&mut random);
    for (i, byte) in random.iter().enumerate() {
        out[10 + i] = ALPHABET[(byte % 32) as usize];
    }
    String::from_utf8(out.to_vec()).unwrap()
}

/// Percent-encodes everything but RFC 3986 unreserved characters.
pub(crate) fn encode_component(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for b in text.bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~') {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

pub(crate) fn decode_component(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'+' => out.push(b' '),
            b'%' if i + 2 < bytes.len() => {
                match std::str::from_utf8(&bytes[i + 1..i + 3]).ok().and_then(|h| u8::from_str_radix(h, 16).ok()) {
                    Some(v) => {
                        out.push(v);
                        i += 2;
                    }
                    None => out.push(b'%'),
                }
            }
            b => out.push(b),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// A query string (with or without its leading `?`) as name/value pairs.
fn parse_query(query: &str) -> Vec<(String, String)> {
    query
        .trim_start_matches('?')
        .split('&')
        .filter(|p| !p.is_empty())
        .map(|p| match p.split_once('=') {
            Some((k, v)) => (decode_component(k), decode_component(v)),
            None => (decode_component(p), String::new()),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use std::cell::Cell;

    use super::*;
    use crate::host::{HostError, StreamResponse};
    use crate::protocol::{ClientId, CoreMessage};
    use crate::testing::{FakeHost, json_response, run};

    fn tokens(access: &str, refresh: &str, expires_at: f64) -> Value {
        json!({ "access_token": access, "refresh_token": refresh, "subject": "sub1", "email": "a@x.com", "name": "阿一", "expires_at": expires_at })
    }

    fn now() -> f64 {
        std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64()
    }

    fn account(sub: &str, access_expires: f64) -> StoredAccount {
        StoredAccount {
            sub: sub.into(),
            email: format!("{sub}@x.com"),
            name: "旧名".into(),
            picture: "p.png".into(),
            access: "old-access".into(),
            refresh: "old-refresh".into(),
            access_expires,
        }
    }

    fn body(request: &HttpRequest) -> Value {
        serde_json::from_slice(request.body.as_deref().unwrap()).unwrap()
    }

    fn header<'a>(request: &'a HttpRequest, name: &str) -> Option<&'a str> {
        request.headers.iter().find(|(k, _)| k == name).map(|(_, v)| v.as_str())
    }

    async fn with_stored(host: &Rc<FakeHost>, list: &[StoredAccount]) -> Rc<Accounts> {
        host.store(STORAGE_KEY, serde_json::to_vec(list).unwrap());
        Accounts::load(host.clone()).await
    }

    fn query_of(url: &str) -> HashMap<String, String> {
        parse_query(url.split_once('?').unwrap().1).into_iter().collect()
    }

    /// Delays every fetch, so concurrent callers really overlap.
    struct SlowHost(Rc<FakeHost>);

    impl Host for SlowHost {
        fn cloud_origin(&self) -> String {
            self.0.cloud_origin()
        }
        fn fetch(&self, request: HttpRequest) -> LocalBoxFuture<'static, Result<HttpResponse, HostError>> {
            let answer = self.0.fetch(request);
            async move {
                tokio::time::sleep(std::time::Duration::from_millis(20)).await;
                answer.await
            }
            .boxed_local()
        }
        fn fetch_stream(&self, request: HttpRequest) -> LocalBoxFuture<'static, Result<StreamResponse, HostError>> {
            self.0.fetch_stream(request)
        }
        fn websocket(&self, url: String, protocols: Vec<String>) -> LocalBoxFuture<'static, Result<crate::host::SocketFrames, HostError>> {
            self.0.websocket(url, protocols)
        }
        fn storage_get(&self, key: &str) -> LocalBoxFuture<'static, Result<Option<Vec<u8>>, HostError>> {
            self.0.storage_get(key)
        }
        fn storage_set(&self, key: &str, value: Vec<u8>) -> LocalBoxFuture<'static, Result<(), HostError>> {
            self.0.storage_set(key, value)
        }
        fn storage_delete(&self, key: &str) -> LocalBoxFuture<'static, Result<(), HostError>> {
            self.0.storage_delete(key)
        }
        fn now_ms(&self) -> f64 {
            self.0.now_ms()
        }
        fn utc_offset_min(&self, at_ms: f64) -> i32 {
            self.0.utc_offset_min(at_ms)
        }
        fn sleep(&self, ms: u64) -> LocalBoxFuture<'static, ()> {
            self.0.sleep(ms)
        }
        fn spawn(&self, task: LocalBoxFuture<'static, ()>) {
            self.0.spawn(task)
        }
        fn random_bytes(&self, buf: &mut [u8]) {
            self.0.random_bytes(buf)
        }
        fn emit(&self, client: ClientId, message: CoreMessage) {
            self.0.emit(client, message)
        }
    }

    #[test]
    fn pkce_challenge_is_base64url_sha256() {
        // sha256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
        assert_eq!(challenge("abc"), "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0");
    }

    #[test]
    fn query_encoding_round_trips() {
        let text = "still.fail 网页版 · Chrome & co=1/2+3%";
        let encoded = encode_component(text);
        assert!(encoded.bytes().all(|b| b.is_ascii_alphanumeric() || b"-_.~%".contains(&b)));
        assert_eq!(decode_component(&encoded), text);
        assert_eq!(parse_query("?a=1+2&b=%E4%BD%A0&c"), vec![("a".into(), "1 2".into()), ("b".into(), "你".into()), ("c".into(), "".into())]);
    }

    #[test]
    fn begin_sign_in_stores_pkce_and_builds_url() {
        run(async {
            let host = FakeHost::new();
            let accounts = Accounts::load(host.clone()).await;
            let url = accounts.begin_sign_in("https://stillfail.test/auth/callback", "/w/ws1", "still.fail 网页版 · Chrome").await.unwrap();
            assert!(url.starts_with("https://stillfail.test/v1/auth/google/start?state="));
            let pending: PendingLogin = serde_json::from_slice(&host.stored(LOGIN_KEY).unwrap()).unwrap();
            assert_eq!(pending.verifier.len(), 43);
            assert_ne!(pending.verifier, pending.state);
            assert_eq!(pending.return_to, "/w/ws1");
            let q = query_of(&url);
            assert_eq!(q["state"], pending.state);
            assert_eq!(q["code_challenge"], challenge(&pending.verifier));
            assert_eq!(q["code_challenge_method"], "S256");
            assert_eq!(q["redirect_uri"], "https://stillfail.test/auth/callback");
            assert_eq!(q["name"], "still.fail 网页版 · Chrome");
        });
    }

    #[test]
    fn sign_in_happy_path() {
        run(async {
            let host = FakeHost::new();
            let expires = now() + 3600.0;
            host.on_fetch(move |req| match req.url.as_str() {
                "https://stillfail.test/v1/auth/token" => json_response(200, tokens("acc", "ref", expires)),
                "https://stillfail.test/v1/me" => json_response(200, json!({ "user": { "picture": "https://pic/1" } })),
                other => panic!("unexpected {other}"),
            });
            let accounts = Accounts::load(host.clone()).await;
            let changes = Rc::new(Cell::new(0));
            let counter = changes.clone();
            accounts.on_change(Rc::new(move || counter.set(counter.get() + 1)));
            let url = accounts.begin_sign_in("https://stillfail.test/auth/callback", "/w/ws1", "dev").await.unwrap();
            let state = query_of(&url)["state"].clone();
            let pending: PendingLogin = serde_json::from_slice(&host.stored(LOGIN_KEY).unwrap()).unwrap();

            let (view, return_to) = accounts.complete_sign_in(&format!("?code=id.secret&state={state}")).await.unwrap();
            assert_eq!(view, AccountView { sub: "sub1".into(), email: "a@x.com".into(), name: "阿一".into(), picture: "https://pic/1".into() });
            assert_eq!(return_to, "/w/ws1");
            assert!(host.stored(LOGIN_KEY).is_none());
            assert!(changes.get() >= 1);

            let requests = host.requests.borrow().clone();
            assert_eq!(requests[0].method, "POST");
            assert_eq!(body(&requests[0]), json!({ "code": "id.secret", "code_verifier": pending.verifier, "redirect_uri": "https://stillfail.test/auth/callback" }));
            assert_eq!(header(&requests[1], "authorization"), Some("Bearer acc"));

            // Stored, and a fresh token is handed out without a refresh.
            let stored: Vec<StoredAccount> = serde_json::from_slice(&host.stored(STORAGE_KEY).unwrap()).unwrap();
            assert_eq!(stored.len(), 1);
            assert_eq!(stored[0].refresh, "ref");
            assert_eq!(accounts.access_token("sub1").await.unwrap(), "acc");
            assert_eq!(host.requests.borrow().len(), 2);
        });
    }

    #[test]
    fn sign_in_survives_a_failed_profile_and_sanitises_return_to() {
        run(async {
            for (return_to, expected) in [("/auth/callback", "/"), ("", "/")] {
                let host = FakeHost::new();
                let expires = now() + 3600.0;
                host.on_fetch(move |req| {
                    if req.url.ends_with("/v1/me") { Err(HostError("offline".into())) } else { json_response(200, tokens("acc", "ref", expires)) }
                });
                let accounts = Accounts::load(host.clone()).await;
                let url = accounts.begin_sign_in("https://stillfail.test/auth/callback", return_to, "dev").await.unwrap();
                let state = query_of(&url)["state"].clone();
                let (view, to) = accounts.complete_sign_in(&format!("code=c&state={state}")).await.unwrap();
                assert_eq!(view.picture, "");
                assert_eq!(to, expected);
            }
        });
    }

    #[test]
    fn sign_in_failures() {
        run(async {
            let host = FakeHost::new();
            host.on_fetch(|_| json_response(400, json!({ "error": "invalid_grant" })));
            let accounts = Accounts::load(host.clone()).await;
            let begin = || accounts.begin_sign_in("https://stillfail.test/auth/callback", "/", "dev");

            begin().await.unwrap();
            let e = accounts.complete_sign_in("error=login_cancelled").await.unwrap_err();
            assert_eq!(e.message, "登录已取消");
            assert!(host.stored(LOGIN_KEY).is_none(), "a failed login is not retried");

            begin().await.unwrap();
            let e = accounts.complete_sign_in("error=access_denied").await.unwrap_err();
            assert_eq!(e.message, "Google 登录没有成功");

            begin().await.unwrap();
            let e = accounts.complete_sign_in("code=c&state=wrong").await.unwrap_err();
            assert_eq!(e.message, "登录状态不匹配，请重新登录");

            // No sign-in in progress at all.
            let e = accounts.complete_sign_in("code=c&state=wrong").await.unwrap_err();
            assert_eq!(e.message, "登录状态不匹配，请重新登录");

            let state = query_of(&begin().await.unwrap())["state"].clone();
            let e = accounts.complete_sign_in(&format!("code=c&state={state}")).await.unwrap_err();
            assert_eq!(e.message, "登录凭证已失效，请重新登录");
            assert_eq!(e.status, Some(400));

            assert!(accounts.list().is_empty());
        });
    }

    #[test]
    fn refresh_is_single_flight() {
        run(async {
            let fake = FakeHost::new();
            let refreshes = Rc::new(Cell::new(0));
            let counter = refreshes.clone();
            let expires = now() + 3600.0;
            fake.on_fetch(move |req| {
                assert!(req.url.ends_with("/v1/auth/refresh"));
                counter.set(counter.get() + 1);
                json_response(200, json!({ "access_token": "new-access", "refresh_token": "new-refresh", "subject": "s", "email": "s@x.com", "expires_at": expires }))
            });
            // Expires within the minute: due for a refresh.
            fake.store(STORAGE_KEY, serde_json::to_vec(&[account("s", now() + 30.0)]).unwrap());
            let accounts = Accounts::load(Rc::new(SlowHost(fake.clone()))).await;

            let (a, b) = futures::join!(accounts.access_token("s"), accounts.access_token("s"));
            assert_eq!(a.unwrap(), "new-access");
            assert_eq!(b.unwrap(), "new-access");
            assert_eq!(refreshes.get(), 1);
            assert!(accounts.refreshing.borrow().is_empty());

            let request = fake.requests.borrow()[0].clone();
            assert_eq!(header(&request, "authorization"), Some("Bearer old-refresh"));
            let id = body(&request)["request_id"].as_str().unwrap().to_string();
            assert_eq!(id.len(), 26);
            assert!(id.chars().all(|c| "0123456789ABCDEFGHJKMNPQRSTVWXYZ".contains(c)));

            // Rotated and kept; the name stays when the cloud sends none.
            let stored: Vec<StoredAccount> = serde_json::from_slice(&fake.stored(STORAGE_KEY).unwrap()).unwrap();
            assert_eq!((stored[0].refresh.as_str(), stored[0].name.as_str()), ("new-refresh", "旧名"));
            assert_eq!(accounts.access_token("s").await.unwrap(), "new-access");
            assert_eq!(refreshes.get(), 1);
        });
    }

    #[test]
    fn another_core_on_the_same_storage_refreshed_first_so_its_credentials_are_taken() {
        run(async {
            let fake = FakeHost::new();
            fake.on_fetch(|req| panic!("no refresh expected, got {}", req.url));
            fake.store(STORAGE_KEY, serde_json::to_vec(&[account("s", now() + 30.0)]).unwrap());
            let accounts = Accounts::load(fake.clone()).await;
            // Meanwhile another core (a tab on an earlier deploy's worker) rotated and wrote down the new pair.
            let theirs = StoredAccount { access: "their-access".into(), refresh: "their-refresh".into(), access_expires: now() + 3600.0, ..account("s", 0.0) };
            fake.store(STORAGE_KEY, serde_json::to_vec(&[theirs]).unwrap());
            assert_eq!(accounts.access_token("s").await.unwrap(), "their-access");
            assert_eq!(accounts.get("s").unwrap().refresh, "their-refresh");
        });
    }

    #[test]
    fn refused_refresh_forgets_the_account() {
        run(async {
            let host = FakeHost::new();
            host.on_fetch(|_| json_response(401, json!({ "error": "invalid_session" })));
            let accounts = with_stored(&host, &[account("s", 0.0), account("t", now() + 3600.0)]).await;
            let e = accounts.access_token("s").await.unwrap_err();
            assert_eq!(e.code, "signed_out");
            assert_eq!(e.message, "s@x.com 的登录已过期，请重新登录");
            assert_eq!(accounts.list().iter().map(|a| a.sub.as_str()).collect::<Vec<_>>(), ["t"]);
            let stored: Vec<StoredAccount> = serde_json::from_slice(&host.stored(STORAGE_KEY).unwrap()).unwrap();
            assert_eq!(stored.len(), 1);
            assert_eq!(accounts.access_token("s").await.unwrap_err().message, "这个账号已退出");
        });
    }

    #[test]
    fn refreshes_are_traced_with_why_they_failed() {
        run(async {
            let host = FakeHost::new();
            let calls = Rc::new(Cell::new(0));
            let counter = calls.clone();
            let parents: Rc<RefCell<Vec<String>>> = Rc::default();
            let seen = parents.clone();
            host.on_fetch(move |req| {
                seen.borrow_mut().push(header(&req, "traceparent").unwrap_or_default().to_string());
                counter.set(counter.get() + 1);
                // No answer first (still.fail cloud may have rotated all the same), then refused as reuse.
                if counter.get() == 1 { Err(HostError("offline".into())) } else { json_response(401, json!({ "error": "refresh_reused" })) }
            });
            let accounts = with_stored(&host, &[account("s", 0.0)]).await;
            let tracer = Tracer::new(host.clone(), 0.0);
            let bodies: Rc<RefCell<Vec<Value>>> = Rc::default();
            let sink = bodies.clone();
            tracer.set_export(Rc::new(move |body: Vec<u8>| {
                sink.borrow_mut().push(serde_json::from_slice(&body).unwrap());
                async {}.boxed_local()
            }));
            accounts.set_tracer(tracer.clone());
            assert!(accounts.access_token("s").await.is_err());
            assert_eq!(accounts.access_token("s").await.unwrap_err().code, "signed_out");
            tracer.flush();
            // Recorded though the tracer samples nothing, and said so to the cloud.
            assert_eq!(parents.borrow().len(), 2);
            assert!(parents.borrow().iter().all(|p| p.starts_with("00-") && p.ends_with("-01")));
            let spans: Vec<Value> = bodies.borrow().iter().flat_map(|b| b["resourceSpans"][0]["scopeSpans"][0]["spans"].as_array().cloned().unwrap()).collect();
            assert_eq!(spans.len(), 2);
            let attribute = |span: &Value, key: &str| span["attributes"].as_array().unwrap().iter().find(|a| a["key"] == key).map(|a| a["value"].clone());
            assert!(spans.iter().all(|s| s["name"] == "auth.refresh" && s["status"]["code"] == 2));
            assert!(attribute(&spans[0], "error.type").is_some());
            assert!(attribute(&spans[0], "stillfail.auth.unanswered_ago_ms").is_none());
            assert_eq!(attribute(&spans[1], "error.type").unwrap()["stringValue"], "refresh_reused");
            assert!(attribute(&spans[1], "stillfail.auth.unanswered_ago_ms").is_some());
        });
    }

    #[test]
    fn failed_refresh_keeps_the_account() {
        run(async {
            let host = FakeHost::new();
            host.on_fetch(|_| json_response(503, json!({})));
            let accounts = with_stored(&host, &[account("s", 0.0)]).await;
            let e = accounts.access_token("s").await.unwrap_err();
            assert_eq!(e.message, "刷新登录失败（503）");
            assert_eq!(accounts.list().len(), 1);
            assert!(accounts.refreshing.borrow().is_empty());
        });
    }

    #[test]
    fn persistence_round_trips() {
        run(async {
            let host = FakeHost::new();
            let list = [account("s", now() + 3600.0), account("t", now() + 3600.0)];
            let accounts = with_stored(&host, &list).await;
            assert_eq!(accounts.list(), list.iter().map(AccountView::from).collect::<Vec<_>>());
            accounts.sign_out("s").await.unwrap();
            let again = Accounts::load(host.clone()).await;
            assert_eq!(again.list(), vec![AccountView::from(&list[1])]);
            assert_eq!(again.access_token("t").await.unwrap(), "old-access");
        });
    }

    #[test]
    fn sign_out_posts_logout_and_forgets_even_offline() {
        run(async {
            let host = FakeHost::new();
            host.on_fetch(|_| Err(HostError("offline".into())));
            let accounts = with_stored(&host, &[account("s", now() + 3600.0)]).await;
            let changes = Rc::new(Cell::new(0));
            let counter = changes.clone();
            accounts.on_change(Rc::new(move || counter.set(counter.get() + 1)));
            accounts.sign_out("s").await.unwrap();
            assert!(accounts.list().is_empty());
            assert_eq!(changes.get(), 1);
            let request = host.requests.borrow()[0].clone();
            assert_eq!(request.url, "https://stillfail.test/v1/auth/logout");
            assert_eq!(header(&request, "authorization"), Some("Bearer old-refresh"));
            assert_eq!(body(&request), json!({ "all": false }));
        });
    }

    #[test]
    fn migrate_merges_the_old_list() {
        run(async {
            let host = FakeHost::new();
            let accounts = with_stored(&host, &[account("s", 2000.0)]).await;
            let old = json!([
                { "sub": "s", "email": "s@x.com", "name": "", "picture": "", "access": "stale", "refresh": "stale", "accessExpires": 1000 },
                { "sub": "u", "email": "u@x.com", "name": "乌", "picture": "", "access": "ua", "refresh": "ur", "accessExpires": 3000 },
                { "nonsense": true },
            ]);
            accounts.migrate(Value::String(old.to_string())).await.unwrap();
            let again = Accounts::load(host.clone()).await;
            let stored = again.list.borrow().clone();
            assert_eq!(stored.len(), 2);
            assert_eq!(stored[0].access, "old-access", "the newer session here wins");
            assert_eq!((stored[1].sub.as_str(), stored[1].refresh.as_str(), stored[1].access_expires), ("u", "ur", 3000.0));

            // A newer session from the page replaces the one here.
            accounts.migrate(json!([{ "sub": "s", "email": "s@x.com", "access": "fresh", "refresh": "fresh", "accessExpires": 5000 }])).await.unwrap();
            assert_eq!(accounts.get("s").unwrap().refresh, "fresh");
            assert!(accounts.migrate(json!({ "sub": "s" })).await.is_err());
        });
    }
}
