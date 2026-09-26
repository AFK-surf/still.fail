//! `Core`: takes messages from connected UIs, answers calls, keeps
//! subscriptions. Construction wires the modules together: accounts → cloud →
//! mesh links (grants come from cloud as the account that reaches the
//! workspace) → stations; the store routes topics to accounts (accounts,
//! workspaces, workspace) or stations (everything with a station).
//!
//! The account topics live here: `accounts` is the list itself, `workspaces`
//! every account's `/v1/me`, `workspace` one `GET /v1/workspaces/:id`. They are
//! refetched when the accounts change, after a write through `cloud.request`,
//! and every [`REFRESH_MS`] while subscribed.

use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::{Rc, Weak};

use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use futures::FutureExt;
use futures::future::{LocalBoxFuture, Shared};
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::{Value, json};

use crate::accounts::{AccountView, Accounts};
use crate::cloud::Cloud;
use crate::error::{CoreError, Result};
use crate::host::Host;
use crate::mesh::{GrantSource, Mesh};
use crate::protocol::{ClientId, ClientMessage, CoreMessage, RequestId, Topic};
use crate::station::{Links, StationAddr, Stations};
use crate::store::{Source, Store};

/// How often `workspaces` and `workspace` are refetched while subscribed.
pub const REFRESH_MS: u64 = 30_000;

pub struct Core {
    inner: Rc<Inner>,
    next_client: Cell<ClientId>,
}

struct Inner {
    me: Weak<Inner>,
    host: Rc<dyn Host>,
    accounts: Rc<Accounts>,
    cloud: Rc<Cloud>,
    store: Rc<Store>,
    stations: Rc<Stations>,
    /// The device endpoint, brought up once (it needs the relay url from `/v1/me`); cleared if that fails so the next use retries.
    mesh: RefCell<Option<Shared<LocalBoxFuture<'static, Result<Rc<Mesh>>>>>>,
    relay_url: RefCell<Option<String>>,
    /// Which account reaches each workspace, from the latest `/v1/me` answers.
    owners: RefCell<HashMap<String, String>>,
    /// The subscribed `workspaces` / `workspace` topics. `run` ends a refresh loop when the topic stops or restarts;
    /// `fetch` lets only the newest fetch of a topic set its value.
    live: RefCell<HashMap<Topic, Live>>,
    runs: Cell<u64>,
}

struct Live {
    run: u64,
    fetch: u64,
}

impl Core {
    pub async fn new(host: Rc<dyn Host>) -> Core {
        let accounts = Accounts::load(host.clone()).await;
        let cloud = Cloud::new(host.clone(), accounts.clone());
        let inner = Rc::new_cyclic(|me: &Weak<Inner>| {
            let store = Store::new(host.clone());
            let stations = Stations::new(host.clone(), store.clone(), links(me.clone()));
            store.set_source(Rc::new(Router { core: me.clone(), stations: stations.clone() }));
            Inner {
                me: me.clone(),
                host: host.clone(),
                accounts: accounts.clone(),
                cloud,
                store,
                stations,
                mesh: RefCell::default(),
                relay_url: RefCell::default(),
                owners: RefCell::default(),
                live: RefCell::default(),
                runs: Cell::new(0),
            }
        });
        let me = Rc::downgrade(&inner);
        accounts.on_change(Rc::new(move || {
            if let Some(core) = me.upgrade() {
                core.accounts_changed();
            }
        }));
        Core { inner, next_client: Cell::new(1) }
    }

    /// A UI connected; its messages and emissions use this id.
    pub fn connect(&self) -> ClientId {
        let id = self.next_client.get();
        self.next_client.set(id + 1);
        id
    }

    /// A UI went away (tab closed, port gone): its subscriptions end.
    pub fn disconnect(&self, client: ClientId) {
        self.inner.store.drop_client(client);
    }

    /// A message from a UI. Answers and values go out through `Host::emit`.
    pub fn receive(&self, client: ClientId, message: ClientMessage) {
        match message {
            ClientMessage::Call { id, call, params } => match parse_call(&call, params) {
                Err(error) => self.inner.host.emit(client, answer(id, Err(error))),
                Ok(call) => {
                    let inner = self.inner.clone();
                    self.inner.host.spawn(
                        async move {
                            let result = inner.execute(call).await;
                            inner.host.emit(client, answer(id, result));
                        }
                        .boxed_local(),
                    );
                }
            },
            ClientMessage::Subscribe { id, subscribe } => self.inner.store.subscribe(client, id, subscribe),
            ClientMessage::Unsubscribe { id, .. } => self.inner.store.unsubscribe(client, id),
        }
    }
}

/// Station topics go to `Stations`; the account topics are kept here.
struct Router {
    core: Weak<Inner>,
    stations: Rc<Stations>,
}

impl Source for Router {
    fn start(&self, topic: &Topic) {
        if topic.station().is_some() {
            self.stations.start(topic);
        } else if let Some(core) = self.core.upgrade() {
            core.start_topic(topic);
        }
    }

    fn stop(&self, topic: &Topic) {
        if topic.station().is_some() {
            self.stations.stop(topic);
        } else if let Some(core) = self.core.upgrade() {
            core.live.borrow_mut().remove(topic);
        }
    }
}

/// Links for `Stations`: the mesh (brought up on first use) and a grant as whichever account reaches the workspace.
fn links(core: Weak<Inner>) -> Links {
    Rc::new(move |workspace: String, station: String| {
        let core = core.clone();
        async move {
            let core = core.upgrade().ok_or_else(gone)?;
            let mesh = core.mesh().await?;
            let sub = core.owner(&workspace).await?;
            let cloud = core.cloud.clone();
            let target = station.clone();
            let grants: GrantSource = Rc::new(move |device: String| {
                let (cloud, sub, workspace, station) = (cloud.clone(), sub.clone(), workspace.clone(), station.clone());
                async move { cloud.grant(&sub, &workspace, &station, &device).await }.boxed_local()
            });
            mesh.link(&target, grants).await
        }
        .boxed_local()
    })
}

fn gone() -> CoreError {
    CoreError::new("closed", "核心已关闭")
}

impl Inner {
    async fn execute(self: Rc<Self>, call: Call) -> Result<Value> {
        match call {
            Call::AuthBegin { redirect_uri, return_to, device_name } => {
                let url = self.accounts.begin_sign_in(&redirect_uri, &return_to, &device_name).await?;
                Ok(json!({ "url": url }))
            }
            Call::AuthComplete { query } => {
                let (account, return_to) = self.accounts.complete_sign_in(&query).await?;
                Ok(json!({ "account": account, "return_to": return_to }))
            }
            Call::SignOut { account } => {
                self.accounts.sign_out(&account).await?;
                Ok(Value::Null)
            }
            Call::CloudRequest { account, method, path, body } => {
                let result = self.cloud.request(&account, &method, &path, body).await?;
                // A write may rename, join or leave a workspace: what the account topics show changed too.
                if !method.eq_ignore_ascii_case("GET") {
                    self.refresh_all();
                }
                Ok(result)
            }
            Call::StationRequest { station, method, path, body } => {
                self.stations.request(&StationAddr::parse(&station)?, &method, &path, body).await
            }
            Call::StationUpload { station, key, name, bytes } => {
                self.stations.upload(&StationAddr::parse(&station)?, &key, &name, bytes).await
            }
            Call::StationFile { station, key, name } => {
                let (kind, bytes) = self.stations.file(&StationAddr::parse(&station)?, &key, &name).await?;
                Ok(json!({ "type": kind, "bytes": BASE64.encode(bytes) }))
            }
            Call::Migrate { accounts, device } => {
                if let Some(accounts) = accounts {
                    self.accounts.migrate(accounts).await?;
                }
                if let Some(device) = device {
                    self.mesh().await?.migrate(device).await?;
                }
                Ok(Value::Null)
            }
        }
    }

    /// The device endpoint, bringing it up the first time.
    async fn mesh(&self) -> Result<Rc<Mesh>> {
        let pending = self.mesh.borrow().clone();
        let pending = match pending {
            Some(pending) => pending,
            None => {
                let core = self.me.clone();
                let pending = async move {
                    let core = core.upgrade().ok_or_else(gone)?;
                    let relay = core.relay_url().await?;
                    Mesh::new(core.host.clone(), &relay).await
                }
                .boxed_local()
                .shared();
                *self.mesh.borrow_mut() = Some(pending.clone());
                pending
            }
        };
        let result = pending.clone().await;
        if result.is_err() {
            let mut mesh = self.mesh.borrow_mut();
            if mesh.as_ref().is_some_and(|m| m.ptr_eq(&pending)) {
                *mesh = None;
            }
        }
        result
    }

    /// The relay the mesh uses, from any account's `/v1/me`.
    async fn relay_url(&self) -> Result<String> {
        if let Some(url) = self.relay_url.borrow().clone() {
            return Ok(url);
        }
        let mut last = CoreError::signed_out("还没有登录的账号");
        for (_, me) in self.load_me().await {
            match me {
                Ok(me) => {
                    if let Some(url) = me.get("relay_url").and_then(Value::as_str) {
                        return Ok(url.to_string());
                    }
                }
                Err(error) => last = error,
            }
        }
        Err(last)
    }

    /// The signed-in account that reaches `workspace`, asking every account's `/v1/me` if it is not known yet.
    async fn owner(&self, workspace: &str) -> Result<String> {
        let known = |core: &Inner| {
            let sub = core.owners.borrow().get(workspace).cloned()?;
            core.accounts.list().iter().any(|a| a.sub == sub).then_some(sub)
        };
        if let Some(sub) = known(self) {
            return Ok(sub);
        }
        self.load_me().await;
        known(self).ok_or_else(|| CoreError::new("not_found", "已登录的账号都进不了这个工作区").with_status(404))
    }

    /// Every account's `/v1/me`, noting who reaches which workspace and the relay url on the way.
    async fn load_me(&self) -> Vec<(AccountView, Result<Value>)> {
        let accounts = self.accounts.list();
        let answers = futures::future::join_all(accounts.iter().map(|a| self.cloud.me(&a.sub))).await;
        let results: Vec<_> = accounts.into_iter().zip(answers).collect();
        let mut owners = self.owners.borrow_mut();
        // Accounts whose /v1/me failed keep what was known of them; signed-out ones are forgotten.
        let failed: Vec<&str> = results.iter().filter(|(_, me)| me.is_err()).map(|(a, _)| a.sub.as_str()).collect();
        owners.retain(|_, sub| failed.contains(&sub.as_str()));
        for (account, me) in &results {
            let Ok(me) = me else { continue };
            for workspace in me.get("workspaces").and_then(Value::as_array).into_iter().flatten() {
                if let Some(id) = workspace.get("id").and_then(Value::as_str) {
                    owners.entry(id.to_string()).or_insert_with(|| account.sub.clone());
                }
            }
            if let Some(url) = me.get("relay_url").and_then(Value::as_str) {
                self.relay_url.borrow_mut().get_or_insert_with(|| url.to_string());
            }
        }
        results
    }

    fn accounts_value(&self) -> Result<Value> {
        Ok(serde_json::to_value(self.accounts.list()).expect("accounts serialize"))
    }

    async fn workspaces_value(&self) -> Result<Value> {
        let entries = self.load_me().await.into_iter().map(|(account, me)| match me {
            Ok(me) => json!({
                "account": account,
                "workspaces": me.get("workspaces").cloned().unwrap_or_else(|| json!([])),
                "invitations": me.get("invitations").cloned().unwrap_or_else(|| json!([])),
                "relay_url": me.get("relay_url").cloned().unwrap_or(Value::Null),
            }),
            // One account failing (offline, signed out elsewhere) still shows the others.
            Err(error) => json!({ "account": account, "workspaces": [], "invitations": [], "relay_url": null, "error": error }),
        });
        Ok(Value::Array(entries.collect()))
    }

    async fn workspace_value(&self, workspace: &str) -> Result<Value> {
        let sub = self.owner(workspace).await?;
        self.cloud.request(&sub, "GET", &format!("/v1/workspaces/{}", encode(workspace)), None).await
    }

    fn start_topic(&self, topic: &Topic) {
        if *topic == Topic::Accounts {
            self.store.set(topic, self.accounts_value());
            return;
        }
        let run = self.runs.get() + 1;
        self.runs.set(run);
        self.live.borrow_mut().insert(topic.clone(), Live { run, fetch: 0 });
        let core = self.me.clone();
        let topic = topic.clone();
        self.host.spawn(
            async move {
                loop {
                    let Some(this) = core.upgrade() else { return };
                    if this.live.borrow().get(&topic).map(|l| l.run) != Some(run) {
                        return;
                    }
                    this.refresh(&topic).await;
                    let sleep = this.host.sleep(REFRESH_MS);
                    drop(this);
                    sleep.await;
                }
            }
            .boxed_local(),
        );
    }

    /// Refetches one account topic; an answer overtaken by a newer fetch is dropped.
    async fn refresh(&self, topic: &Topic) {
        let fetch = {
            let mut live = self.live.borrow_mut();
            let Some(live) = live.get_mut(topic) else { return };
            live.fetch += 1;
            live.fetch
        };
        let value = match topic {
            Topic::Workspaces => self.workspaces_value().await,
            Topic::Workspace { workspace } => self.workspace_value(workspace).await,
            _ => return,
        };
        if self.live.borrow().get(topic).is_some_and(|l| l.fetch == fetch) {
            self.store.set(topic, value);
        }
    }

    fn accounts_changed(&self) {
        self.store.set(&Topic::Accounts, self.accounts_value());
        self.refresh_all();
    }

    /// Refetches every subscribed `workspaces` / `workspace` topic now.
    fn refresh_all(&self) {
        let topics: Vec<Topic> = self.live.borrow().keys().cloned().collect();
        for topic in topics {
            let core = self.me.clone();
            self.host.spawn(
                async move {
                    if let Some(core) = core.upgrade() {
                        core.refresh(&topic).await;
                    }
                }
                .boxed_local(),
            );
        }
    }
}

/// A path segment, percent-encoded like `encodeURIComponent`.
fn encode(segment: &str) -> String {
    let mut out = String::new();
    for byte in segment.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'!' | b'~' | b'*' | b'\'' | b'(' | b')' => out.push(byte as char),
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

fn answer(id: RequestId, result: Result<Value>) -> CoreMessage {
    match result {
        Ok(ok) => CoreMessage::Ok { id, ok },
        Err(error) => CoreMessage::Error { id, error },
    }
}

/// A call with its params checked; binary params are already decoded.
#[derive(Debug, PartialEq)]
enum Call {
    AuthBegin { redirect_uri: String, return_to: String, device_name: String },
    AuthComplete { query: String },
    SignOut { account: String },
    CloudRequest { account: String, method: String, path: String, body: Option<Value> },
    StationRequest { station: String, method: String, path: String, body: Option<Value> },
    StationUpload { station: String, key: String, name: String, bytes: Vec<u8> },
    StationFile { station: String, key: String, name: String },
    Migrate { accounts: Option<Value>, device: Option<Vec<u8>> },
}

fn parse_call(name: &str, params: Value) -> Result<Call> {
    #[derive(Deserialize)]
    struct Begin {
        redirect_uri: String,
        return_to: String,
        device_name: String,
    }
    #[derive(Deserialize)]
    struct Complete {
        query: String,
    }
    #[derive(Deserialize)]
    struct SignOut {
        account: String,
    }
    #[derive(Deserialize)]
    struct CloudRequest {
        account: String,
        method: String,
        path: String,
        body: Option<Value>,
    }
    #[derive(Deserialize)]
    struct StationRequest {
        station: String,
        method: String,
        path: String,
        body: Option<Value>,
    }
    #[derive(Deserialize)]
    struct Upload {
        station: String,
        key: String,
        name: String,
        bytes: String,
    }
    #[derive(Deserialize)]
    struct File {
        station: String,
        key: String,
        name: String,
    }
    #[derive(Deserialize)]
    struct Migrate {
        accounts: Option<Value>,
        device: Option<String>,
    }

    fn params<T: DeserializeOwned>(params: Value) -> Result<T> {
        serde_json::from_value(params_or_empty(params)).map_err(|e| CoreError::invalid(format!("参数不对：{e}")))
    }
    fn base64(text: &str, what: &str) -> Result<Vec<u8>> {
        BASE64.decode(text).map_err(|_| CoreError::invalid(format!("{what}不是 base64")))
    }

    Ok(match name {
        "auth.begin" => {
            let p: Begin = params(params)?;
            Call::AuthBegin { redirect_uri: p.redirect_uri, return_to: p.return_to, device_name: p.device_name }
        }
        "auth.complete" => Call::AuthComplete { query: params::<Complete>(params)?.query },
        "auth.signOut" => Call::SignOut { account: params::<SignOut>(params)?.account },
        "cloud.request" => {
            let p: CloudRequest = params(params)?;
            Call::CloudRequest { account: p.account, method: p.method, path: p.path, body: p.body }
        }
        "station.request" => {
            let p: StationRequest = params(params)?;
            Call::StationRequest { station: p.station, method: p.method, path: p.path, body: p.body }
        }
        "station.upload" => {
            let p: Upload = params(params)?;
            Call::StationUpload { bytes: base64(&p.bytes, "文件内容")?, station: p.station, key: p.key, name: p.name }
        }
        "station.file" => {
            let p: File = params(params)?;
            Call::StationFile { station: p.station, key: p.key, name: p.name }
        }
        "migrate" => {
            let p: Migrate = params(params)?;
            let device = match p.device {
                Some(text) => {
                    let key = base64(&text, "设备密钥")?;
                    if key.len() != 32 {
                        return Err(CoreError::invalid("设备密钥应是 32 字节"));
                    }
                    Some(key)
                }
                None => None,
            };
            Call::Migrate { accounts: p.accounts.filter(|a| !a.is_null()), device }
        }
        _ => return Err(CoreError::new("unknown_call", format!("没有这个调用：{name}"))),
    })
}

/// Missing params read as `{}`, so the error names the missing field.
fn params_or_empty(params: Value) -> Value {
    if params.is_null() { json!({}) } else { params }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn code(result: Result<Call>) -> String {
        result.unwrap_err().code
    }

    #[test]
    fn parses_the_client_messages_of_the_protocol() {
        let call: ClientMessage = serde_json::from_value(json!({"id": 7, "call": "station.request", "params": {"station": "ws1/st1", "method": "GET", "path": "/overview"}})).unwrap();
        assert_eq!(call, ClientMessage::Call { id: 7, call: "station.request".into(), params: json!({"station": "ws1/st1", "method": "GET", "path": "/overview"}) });
        let bare: ClientMessage = serde_json::from_value(json!({"id": 1, "call": "auth.signOut"})).unwrap();
        assert_eq!(bare, ClientMessage::Call { id: 1, call: "auth.signOut".into(), params: Value::Null });
        let subscribe: ClientMessage = serde_json::from_value(json!({"id": 8, "subscribe": {"topic": "session", "station": "ws1/st1", "key": "k"}})).unwrap();
        assert_eq!(subscribe, ClientMessage::Subscribe { id: 8, subscribe: Topic::Session { station: "ws1/st1".into(), key: "k".into() } });
        let accounts: ClientMessage = serde_json::from_value(json!({"id": 2, "subscribe": {"topic": "accounts"}})).unwrap();
        assert_eq!(accounts, ClientMessage::Subscribe { id: 2, subscribe: Topic::Accounts });
        let workspace: ClientMessage = serde_json::from_value(json!({"id": 3, "subscribe": {"topic": "workspace", "workspace": "w"}})).unwrap();
        assert_eq!(workspace, ClientMessage::Subscribe { id: 3, subscribe: Topic::Workspace { workspace: "w".into() } });
        let unsubscribe: ClientMessage = serde_json::from_value(json!({"id": 8, "unsubscribe": true})).unwrap();
        assert_eq!(unsubscribe, ClientMessage::Unsubscribe { id: 8, unsubscribe: true });
    }

    #[test]
    fn answers_take_the_shapes_of_the_protocol() {
        assert_eq!(serde_json::to_value(answer(7, Ok(json!({"url": "u"})))).unwrap(), json!({"id": 7, "ok": {"url": "u"}}));
        assert_eq!(serde_json::to_value(answer(7, Ok(Value::Null))).unwrap(), json!({"id": 7, "ok": null}));
        let refused = CoreError::new("forbidden", "没有权限").with_status(403);
        assert_eq!(serde_json::to_value(answer(7, Err(refused))).unwrap(), json!({"id": 7, "error": {"code": "forbidden", "message": "没有权限", "status": 403}}));
        let local = answer(9, Err(CoreError::new("unknown_call", "没有这个调用：x")));
        assert_eq!(serde_json::to_value(local).unwrap(), json!({"id": 9, "error": {"code": "unknown_call", "message": "没有这个调用：x"}}));
    }

    #[test]
    fn unknown_calls_are_refused() {
        assert_eq!(code(parse_call("station.delete", json!({}))), "unknown_call");
        assert_eq!(code(parse_call("", Value::Null)), "unknown_call");
    }

    #[test]
    fn parses_each_call() {
        assert_eq!(
            parse_call("auth.begin", json!({"redirect_uri": "r", "return_to": "/", "device_name": "Mac"})).unwrap(),
            Call::AuthBegin { redirect_uri: "r".into(), return_to: "/".into(), device_name: "Mac".into() }
        );
        assert_eq!(parse_call("auth.complete", json!({"query": "?code=c&state=s"})).unwrap(), Call::AuthComplete { query: "?code=c&state=s".into() });
        assert_eq!(parse_call("auth.signOut", json!({"account": "sub1"})).unwrap(), Call::SignOut { account: "sub1".into() });
        assert_eq!(
            parse_call("cloud.request", json!({"account": "a", "method": "PATCH", "path": "/v1/workspaces/w", "body": {"name": "n"}})).unwrap(),
            Call::CloudRequest { account: "a".into(), method: "PATCH".into(), path: "/v1/workspaces/w".into(), body: Some(json!({"name": "n"})) }
        );
        assert_eq!(
            parse_call("station.request", json!({"station": "local", "method": "GET", "path": "/sessions"})).unwrap(),
            Call::StationRequest { station: "local".into(), method: "GET".into(), path: "/sessions".into(), body: None }
        );
        assert_eq!(
            parse_call("station.upload", json!({"station": "w/s", "key": "k", "name": "a.png", "bytes": "aGVsbG8="})).unwrap(),
            Call::StationUpload { station: "w/s".into(), key: "k".into(), name: "a.png".into(), bytes: b"hello".to_vec() }
        );
        assert_eq!(
            parse_call("station.file", json!({"station": "w/s", "key": "k", "name": "a.png"})).unwrap(),
            Call::StationFile { station: "w/s".into(), key: "k".into(), name: "a.png".into() }
        );
    }

    #[test]
    fn checks_params() {
        let missing = parse_call("auth.begin", json!({"redirect_uri": "r", "return_to": "/"})).unwrap_err();
        assert_eq!(missing.code, "invalid_params");
        assert!(missing.message.contains("device_name"), "{}", missing.message);
        assert_eq!(code(parse_call("auth.signOut", Value::Null)), "invalid_params");
        assert_eq!(code(parse_call("cloud.request", json!({"account": "a", "method": 1, "path": "/"}))), "invalid_params");
        assert_eq!(code(parse_call("station.upload", json!({"station": "w/s", "key": "k", "name": "n", "bytes": "not base64!"}))), "invalid_params");
    }

    #[test]
    fn migrate_takes_accounts_and_a_32_byte_device_key() {
        let key = BASE64.encode([7u8; 32]);
        assert_eq!(
            parse_call("migrate", json!({"accounts": [{"sub": "s"}], "device": key})).unwrap(),
            Call::Migrate { accounts: Some(json!([{"sub": "s"}])), device: Some(vec![7u8; 32]) }
        );
        assert_eq!(parse_call("migrate", json!({"accounts": null})).unwrap(), Call::Migrate { accounts: None, device: None });
        assert_eq!(parse_call("migrate", Value::Null).unwrap(), Call::Migrate { accounts: None, device: None });
        assert_eq!(code(parse_call("migrate", json!({"device": BASE64.encode([1u8; 16])}))), "invalid_params");
    }

    #[test]
    fn encodes_path_segments_like_encode_uri_component() {
        assert_eq!(encode("ws_01-a.b~"), "ws_01-a.b~");
        assert_eq!(encode("a/b c?"), "a%2Fb%20c%3F");
        assert_eq!(encode("工"), "%E5%B7%A5");
    }
}
