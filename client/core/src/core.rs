//! `Core`: takes messages from connected UIs, answers calls, keeps
//! subscriptions. Construction wires the modules together: accounts → cloud →
//! mesh links (grants come from cloud as the account that reaches the
//! workspace) → stations; the store routes topics to accounts (accounts,
//! workspaces, workspace), stations (everything with a station) or the views.
//!
//! The account topics live here: `accounts` is the list itself, `workspaces`
//! every account's `/v1/me`, `workspace` one `GET /v1/workspaces/:id`. While
//! `workspaces` or a `workspace` is live, each signed-in account holds ember
//! cloud's `/v1/events` socket, and the topics change when it says so:
//! `workspaces` reads that account's `/v1/me` again, `workspace` that
//! workspace, and `station` sets the station's `online` in place. Every time a
//! socket opens, the live account topics are read once (nothing is replayed).
//! They are also read when the accounts change and after a write through
//! `cloud.request`; never on a timer.

use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::{Rc, Weak};

use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use futures::future::{AbortHandle, Abortable, LocalBoxFuture, Shared, join_all};
use futures::{FutureExt, StreamExt};
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::{Value, json};

use crate::accounts::{AccountView, Accounts};
use crate::cloud::Cloud;
use crate::error::{CoreError, Result};
use crate::host::Host;
use crate::mesh::{GrantSource, Mesh};
use crate::protocol::{ClientId, ClientMessage, CoreMessage, RequestId, Topic};
use crate::station::{self, MeshSource, StationAddr, StationGrants, Stations, TopicSink};
use crate::store::{Source, Store};
use crate::views::{EmailOf, SendTarget, Views};

/// The first wait before an events socket is opened again; it doubles up to [`SOCKET_RETRY_MAX_MS`], and starts
/// over once a socket held for a minute.
pub const SOCKET_RETRY_MS: u64 = 1_000;
pub const SOCKET_RETRY_MAX_MS: u64 = 60_000;
/// The subprotocol ember cloud's `/v1/events` answers with; the token travels as a second one.
pub const EVENTS_PROTOCOL: &str = "ember-events";

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
    views: Rc<Views>,
    /// The device endpoint, brought up once (it needs the relay url from `/v1/me`); cleared if that fails so the next use retries.
    mesh: RefCell<Option<Shared<LocalBoxFuture<'static, Result<Rc<Mesh>>>>>>,
    relay_url: RefCell<Option<String>>,
    /// Which account reaches each workspace, from the latest `/v1/me` answers.
    owners: RefCell<HashMap<String, String>>,
    /// Each account's latest `/v1/me`: its answer, or why it failed.
    mes: RefCell<HashMap<String, Result<Value>>>,
    /// Each account's latest successful `/v1/me`: whom it reaches.
    reach: RefCell<HashMap<String, Value>>,
    /// The accounts as last shown, so a change that UIs cannot see (a refreshed token) is not one.
    shown_accounts: RefCell<Vec<AccountView>>,
    /// Every account's `/v1/me` under way.
    me_loading: RefCell<Option<Shared<LocalBoxFuture<'static, ()>>>>,
    /// Numbers the `/v1/me` requests per account, so only the newest answer is kept.
    me_fetches: RefCell<HashMap<String, u64>>,
    /// The live `workspaces` / `workspace` topics, each with the number of its newest fetch.
    live: RefCell<HashMap<Topic, u64>>,
    /// Per account, its ember cloud events socket while an account topic is live.
    sockets: RefCell<HashMap<String, Socket>>,
}

struct Socket {
    task: AbortHandle,
    state: SocketState,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum SocketState {
    /// Its first try: the topics are read once it opens (or fails).
    Connecting,
    Open,
    /// Down, trying again.
    Retrying,
}

impl Core {
    pub async fn new(host: Rc<dyn Host>) -> Core {
        let accounts = Accounts::load(host.clone()).await;
        let cloud = Cloud::new(host.clone(), accounts.clone());
        let inner = Rc::new_cyclic(|me: &Weak<Inner>| {
            let store = Store::new(host.clone());
            let wire = station::wire(host.clone(), mesh_source(me.clone()), grants(me.clone()));
            let stations = Stations::new(host.clone(), store.clone() as Rc<dyn TopicSink>, wire);
            let views = Views::new(host.clone(), store.clone(), email_of(me.clone()));
            store.set_source(Rc::new(Router { core: me.clone(), stations: stations.clone(), views: views.clone() }));
            Inner {
                views,
                me: me.clone(),
                host: host.clone(),
                accounts: accounts.clone(),
                cloud,
                store,
                stations,
                mesh: RefCell::default(),
                relay_url: RefCell::default(),
                owners: RefCell::default(),
                mes: RefCell::default(),
                reach: RefCell::default(),
                me_loading: RefCell::default(),
                shown_accounts: RefCell::new(accounts.list()),
                me_fetches: RefCell::default(),
                live: RefCell::default(),
                sockets: RefCell::default(),
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

/// Station topics go to `Stations`, views to `Views`; the account topics are kept here.
struct Router {
    core: Weak<Inner>,
    stations: Rc<Stations>,
    views: Rc<Views>,
}

impl Source for Router {
    fn start(&self, topic: &Topic) {
        if topic.is_view() {
            self.views.start(topic);
        } else if topic.station().is_some() {
            self.stations.start(topic);
        } else if let Some(core) = self.core.upgrade() {
            core.start_topic(topic);
        }
    }

    fn stop(&self, topic: &Topic) {
        if topic.is_view() {
            self.views.stop(topic);
        } else if topic.station().is_some() {
            self.stations.stop(topic);
        } else if let Some(core) = self.core.upgrade() {
            core.live.borrow_mut().remove(topic);
            core.sync_sockets();
        }
    }

    fn compute(&self, topic: &Topic) -> Option<Result<Value>> {
        self.views.compute(topic)
    }
}

/// Who a workspace's views take as "me": the account that reaches it, as far as `/v1/me` has told.
fn email_of(core: Weak<Inner>) -> EmailOf {
    Rc::new(move |workspace: &str| {
        let core = core.upgrade()?;
        let sub = core.owners.borrow().get(workspace).cloned()?;
        core.accounts.list().into_iter().find(|a| a.sub == sub).map(|a| a.email)
    })
}

/// The mesh for `Stations`, brought up on first use.
fn mesh_source(core: Weak<Inner>) -> MeshSource {
    Rc::new(move || {
        let core = core.clone();
        async move { core.upgrade().ok_or_else(gone)?.mesh().await }.boxed_local()
    })
}

/// Grants for a station, asked for as whichever account reaches its workspace.
fn grants(core: Weak<Inner>) -> StationGrants {
    Rc::new(move |workspace: &str, station: &str| {
        let (core, workspace, station) = (core.clone(), workspace.to_string(), station.to_string());
        let source: GrantSource = Rc::new(move |device: String| {
            let (core, workspace, station) = (core.clone(), workspace.clone(), station.clone());
            async move {
                let core = core.upgrade().ok_or_else(gone)?;
                let sub = core.owner(&workspace).await?;
                core.cloud.grant(&sub, &workspace, &station, &device).await
            }
            .boxed_local()
        });
        source
    })
}

fn gone() -> CoreError {
    CoreError::new("closed", "核心已关闭")
}

impl Inner {
    async fn execute(&self, call: Call) -> Result<Value> {
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
                    self.refresh_all().await;
                }
                Ok(result)
            }
            Call::StationRequest { station, method, path, body } => {
                self.stations.request(&StationAddr::parse(&station)?, &method, &path, body).await
            }
            Call::ChatSend { station, thread, text, attachments, quotes } => {
                let message = json!({ "text": text, "attachments": attachments, "quotes": quotes });
                let id = self.views.outbox_add(&station, thread, message.clone());
                self.deliver(&station, thread, &id, message).await
            }
            Call::ChatRetry { station, thread, id } => {
                let entry = self.views.outbox_get(&station, thread, &id).ok_or_else(|| CoreError::invalid("没有这条待发的消息"))?;
                self.views.outbox_state(&station, thread, &id, None);
                let message = json!({ "text": entry["text"], "attachments": entry["attachments"], "quotes": entry["quotes"] });
                self.deliver(&station, thread, &id, message).await
            }
            Call::ChatDiscard { station, thread, id } => {
                self.views.outbox_remove(&station, thread, &id);
                Ok(Value::Null)
            }
            Call::ChatOlder { station, thread } => Ok(json!({ "more": self.stations.older(&StationAddr::parse(&station)?, thread).await? })),
            Call::ChatRead { station, thread, seq } => {
                self.stations.read(&StationAddr::parse(&station)?, thread, seq).await?;
                Ok(Value::Null)
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

    /// Posts an outgoing message into a chat. The entry leaves the outbox in the emission that brings the message
    /// into the chat's messages; a failure leaves it there as `failed`.
    /// Posts an outgoing message where the chat's messages go (see `Views::send_target`); the outbox stays the chat's.
    async fn deliver(&self, station: &str, thread: u64, id: &str, message: Value) -> Result<Value> {
        let result = async {
            let addr = StationAddr::parse(station)?;
            let target = match self.views.send_target(station, thread) {
                SendTarget::Thread(target) => target,
                SendTarget::NewChatFor(session) => {
                    let made = self.stations.request(&addr, "POST", "/threads", Some(json!({ "session": session }))).await?;
                    made.get("id").and_then(Value::as_u64).ok_or_else(|| CoreError::invalid("station 没有给出新对话的 id"))?
                }
            };
            self.stations.post(&addr, target, message).await
        }
        .await;
        match result {
            Ok(seq) => {
                self.views.outbox_sent(station, thread, id, seq);
                Ok(json!({ "seq": seq }))
            }
            Err(error) => {
                self.views.outbox_state(station, thread, id, Some(&error.message));
                Err(error)
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
    /// One at a time: whoever asks while it is under way waits for that one.
    async fn load_me(&self) -> Vec<(AccountView, Result<Value>)> {
        let pending = self.me_loading.borrow().clone();
        let pending = match pending {
            Some(pending) => pending,
            None => {
                let core = self.me.clone();
                let pending = async move {
                    let Some(core) = core.upgrade() else { return };
                    let accounts = core.accounts.list();
                    core.load_me_of(&accounts).await;
                    core.me_loading.borrow_mut().take();
                }
                .boxed_local()
                .shared();
                *self.me_loading.borrow_mut() = Some(pending.clone());
                pending
            }
        };
        pending.await;
        let accounts = self.accounts.list();
        let mes = self.mes.borrow();
        accounts.into_iter().map(|a| {
            let me = mes.get(&a.sub).cloned().unwrap_or_else(|| Err(CoreError::signed_out("这个账号已退出")));
            (a, me)
        }).collect()
    }

    /// These accounts' `/v1/me`, kept per account; an answer overtaken by a newer request is dropped.
    async fn load_me_of(&self, accounts: &[AccountView]) {
        let asked: Vec<u64> = accounts.iter().map(|a| {
            let mut fetches = self.me_fetches.borrow_mut();
            let n = fetches.entry(a.sub.clone()).or_default();
            *n += 1;
            *n
        }).collect();
        let answers = join_all(accounts.iter().map(|a| self.cloud.me(&a.sub))).await;
        for ((account, n), me) in accounts.iter().zip(asked).zip(answers) {
            if self.me_fetches.borrow().get(&account.sub) != Some(&n) {
                continue;
            }
            if let Ok(me) = &me {
                if let Some(url) = me.get("relay_url").and_then(Value::as_str) {
                    self.relay_url.borrow_mut().get_or_insert_with(|| url.to_string());
                }
                self.reach.borrow_mut().insert(account.sub.clone(), me.clone());
            }
            self.mes.borrow_mut().insert(account.sub.clone(), me);
        }
        self.recompute_owners();
    }

    /// Which account reaches each workspace: the first (in sign-in order) whose last `/v1/me` answer lists it.
    /// An account whose latest request failed keeps what it was known to reach; signed-out ones are forgotten.
    fn recompute_owners(&self) {
        let accounts = self.accounts.list();
        self.mes.borrow_mut().retain(|sub, _| accounts.iter().any(|a| &a.sub == sub));
        self.reach.borrow_mut().retain(|sub, _| accounts.iter().any(|a| &a.sub == sub));
        let reach = self.reach.borrow();
        let mut owners = self.owners.borrow_mut();
        owners.clear();
        for account in &accounts {
            let Some(me) = reach.get(&account.sub) else { continue };
            for workspace in me.get("workspaces").and_then(Value::as_array).into_iter().flatten() {
                if let Some(id) = workspace.get("id").and_then(Value::as_str) {
                    owners.entry(id.to_string()).or_insert_with(|| account.sub.clone());
                }
            }
        }
    }

    fn accounts_value(&self) -> Result<Value> {
        Ok(serde_json::to_value(self.accounts.list()).expect("accounts serialize"))
    }

    /// Every account with what its latest `/v1/me` said.
    fn workspaces_value(&self) -> Value {
        let mes = self.mes.borrow();
        let entries = self.accounts.list().into_iter().map(|account| match mes.get(&account.sub) {
            Some(Ok(me)) => json!({
                "account": account,
                "workspaces": me.get("workspaces").cloned().unwrap_or_else(|| json!([])),
                "invitations": me.get("invitations").cloned().unwrap_or_else(|| json!([])),
                "relay_url": me.get("relay_url").cloned().unwrap_or(Value::Null),
            }),
            // One account failing (offline, signed out elsewhere) still shows the others.
            Some(Err(error)) => json!({ "account": account, "workspaces": [], "invitations": [], "relay_url": null, "error": error }),
            None => json!({ "account": account, "workspaces": [], "invitations": [], "relay_url": null }),
        });
        Value::Array(entries.collect())
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
        self.live.borrow_mut().insert(topic.clone(), 0);
        self.sync_sockets();
        // A socket on its first try reads the topics when it opens; otherwise they are read now.
        if !self.sockets.borrow().values().any(|s| s.state == SocketState::Connecting) {
            self.spawn_refresh(topic.clone());
        }
    }

    fn spawn_refresh(&self, topic: Topic) {
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

    /// Reads one account topic again; an answer overtaken by a newer fetch is dropped.
    async fn refresh(&self, topic: &Topic) {
        self.refresh_with(topic, false).await
    }

    /// `me_read`: every account's `/v1/me` was just read, so `workspaces` needs no request of its own.
    async fn refresh_with(&self, topic: &Topic, me_read: bool) {
        let fetch = {
            let mut live = self.live.borrow_mut();
            let Some(fetch) = live.get_mut(topic) else { return };
            *fetch += 1;
            *fetch
        };
        let value = match topic {
            Topic::Workspaces => {
                if !me_read {
                    self.load_me().await;
                }
                Ok(self.workspaces_value())
            }
            Topic::Workspace { workspace } => self.workspace_value(workspace).await,
            _ => return,
        };
        if self.live.borrow().get(topic) == Some(&fetch) {
            self.store.set(topic, value);
        }
    }

    /// The accounts as UIs see them changed (a token refresh alone changes nothing here).
    fn accounts_changed(&self) {
        let list = self.accounts.list();
        if *self.shown_accounts.borrow() == list {
            return;
        }
        *self.shown_accounts.borrow_mut() = list;
        self.store.set(&Topic::Accounts, self.accounts_value());
        self.sync_sockets();
        let core = self.me.clone();
        self.host.spawn(
            async move {
                if let Some(core) = core.upgrade() {
                    core.refresh_all().await;
                }
            }
            .boxed_local(),
        );
    }

    /// Reads every live `workspaces` / `workspace` topic again: `/v1/me` once, then each workspace.
    async fn refresh_all(&self) {
        let topics: Vec<Topic> = self.live.borrow().keys().cloned().collect();
        if topics.is_empty() {
            return;
        }
        self.load_me().await;
        join_all(topics.iter().map(|topic| self.refresh_with(topic, true))).await;
    }

    // ── ember cloud's events ──

    /// One socket per signed-in account while any account topic is live; none otherwise.
    fn sync_sockets(&self) {
        let wanted: Vec<String> = if self.live.borrow().is_empty() { Vec::new() } else { self.accounts.list().into_iter().map(|a| a.sub).collect() };
        let mut sockets = self.sockets.borrow_mut();
        sockets.retain(|sub, socket| {
            let keep = wanted.contains(sub);
            if !keep {
                socket.task.abort();
            }
            keep
        });
        for sub in wanted {
            if sockets.contains_key(&sub) {
                continue;
            }
            let (task, registration) = AbortHandle::new_pair();
            sockets.insert(sub.clone(), Socket { task, state: SocketState::Connecting });
            let follow = Abortable::new(follow_socket(self.me.clone(), sub), registration).map(|_| ());
            self.host.spawn(follow.boxed_local());
        }
    }

    /// Notes a socket's state; answers the one before.
    fn socket_state(&self, sub: &str, state: SocketState) -> Option<SocketState> {
        self.sockets.borrow_mut().get_mut(sub).map(|s| std::mem::replace(&mut s.state, state))
    }

    /// Opens an account's events socket with a token good now (refreshed when it is about to expire).
    async fn open_socket(&self, sub: &str) -> Result<crate::host::SocketFrames> {
        let token = self.accounts.access_token(sub).await?;
        let origin = self.host.cloud_origin();
        let url = match origin.strip_prefix("https://") {
            Some(rest) => format!("wss://{rest}/v1/events"),
            None => format!("ws://{}/v1/events", origin.strip_prefix("http://").unwrap_or(&origin)),
        };
        Ok(self.host.websocket(url, vec![EVENTS_PROTOCOL.into(), format!("ember-token.{token}")]).await?)
    }

    fn on_cloud_event(&self, sub: &str, text: &str) {
        let Ok(event) = serde_json::from_str::<Value>(text) else { return };
        match event.get("type").and_then(Value::as_str) {
            Some("workspaces") => {
                let (core, sub) = (self.me.clone(), sub.to_string());
                self.host.spawn(
                    async move {
                        let Some(core) = core.upgrade() else { return };
                        let Some(account) = core.accounts.list().into_iter().find(|a| a.sub == sub) else { return };
                        core.load_me_of(&[account]).await;
                        if core.live.borrow().contains_key(&Topic::Workspaces) {
                            core.store.set(&Topic::Workspaces, Ok(core.workspaces_value()));
                        }
                    }
                    .boxed_local(),
                );
            }
            Some("workspace") => {
                let Some(id) = event.get("id").and_then(Value::as_str) else { return };
                let topic = Topic::Workspace { workspace: id.to_string() };
                if self.live.borrow().contains_key(&topic) {
                    self.spawn_refresh(topic);
                }
            }
            Some("station") => {
                let (Some(workspace), Some(id), Some(online)) =
                    (event.get("workspace").and_then(Value::as_str), event.get("id").and_then(Value::as_str), event.get("online").and_then(Value::as_bool))
                else {
                    return;
                };
                // Complete in itself: the station's presence changes in place, and it was last seen now.
                let now = (self.host.now_ms() / 1000.0).floor();
                self.store.update(&Topic::Workspace { workspace: workspace.to_string() }, &mut |view| {
                    for station in view.get_mut("stations").and_then(Value::as_array_mut).into_iter().flatten() {
                        if station.get("id").and_then(Value::as_str) == Some(id) {
                            station["online"] = json!(online);
                            station["last_seen"] = json!(now);
                        }
                    }
                });
            }
            _ => {}
        }
    }
}

/// Holds an account's `/v1/events` socket open, reconnecting with backoff, until it is no longer wanted (the
/// task is aborted) or the account is signed out.
async fn follow_socket(core: Weak<Inner>, sub: String) {
    let mut wait = SOCKET_RETRY_MS;
    loop {
        let Some(this) = core.upgrade() else { return };
        match this.open_socket(&sub).await {
            Ok(mut frames) => {
                let opened = this.host.now_ms();
                this.socket_state(&sub, SocketState::Open);
                // Nothing is replayed: what changed while it was closed is read now.
                this.refresh_all().await;
                drop(this);
                while let Some(frame) = frames.next().await {
                    let (Some(this), Ok(text)) = (core.upgrade(), frame) else { break };
                    this.on_cloud_event(&sub, &text);
                }
                let Some(this) = core.upgrade() else { return };
                if this.host.now_ms() - opened >= 60_000.0 {
                    wait = SOCKET_RETRY_MS;
                }
                this.socket_state(&sub, SocketState::Retrying);
            }
            Err(error) if error.code == "signed_out" => {
                this.sockets.borrow_mut().remove(&sub);
                return;
            }
            Err(_) => {
                // Its first try failed: the topics are read anyway, so they show what can be shown.
                if this.socket_state(&sub, SocketState::Retrying) == Some(SocketState::Connecting) {
                    this.refresh_all().await;
                }
            }
        }
        let Some(this) = core.upgrade() else { return };
        let sleep = this.host.sleep(wait);
        drop(this);
        sleep.await;
        wait = (wait * 2).min(SOCKET_RETRY_MAX_MS);
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
    ChatSend { station: String, thread: u64, text: String, attachments: Value, quotes: Value },
    ChatRetry { station: String, thread: u64, id: String },
    ChatDiscard { station: String, thread: u64, id: String },
    ChatOlder { station: String, thread: u64 },
    ChatRead { station: String, thread: u64, seq: u64 },
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
    struct Send {
        station: String,
        thread: u64,
        #[serde(default)]
        text: String,
        #[serde(default = "empty_list")]
        attachments: Value,
        #[serde(default = "empty_list")]
        quotes: Value,
    }
    fn empty_list() -> Value {
        json!([])
    }
    #[derive(Deserialize)]
    struct Outgoing {
        station: String,
        thread: u64,
        id: String,
    }
    #[derive(Deserialize)]
    struct Chat {
        station: String,
        thread: u64,
    }
    #[derive(Deserialize)]
    struct Read {
        station: String,
        thread: u64,
        seq: u64,
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

    fn read<T: DeserializeOwned>(params: Value) -> Result<T> {
        serde_json::from_value(params_or_empty(params)).map_err(|e| CoreError::invalid(format!("参数不对：{e}")))
    }
    fn base64(text: &str, what: &str) -> Result<Vec<u8>> {
        BASE64.decode(text).map_err(|_| CoreError::invalid(format!("{what}不是 base64")))
    }

    Ok(match name {
        "auth.begin" => {
            let p: Begin = read(params)?;
            Call::AuthBegin { redirect_uri: p.redirect_uri, return_to: p.return_to, device_name: p.device_name }
        }
        "auth.complete" => Call::AuthComplete { query: read::<Complete>(params)?.query },
        "auth.signOut" => Call::SignOut { account: read::<SignOut>(params)?.account },
        "cloud.request" => {
            let p: CloudRequest = read(params)?;
            Call::CloudRequest { account: p.account, method: p.method, path: p.path, body: p.body }
        }
        "station.request" => {
            let p: StationRequest = read(params)?;
            Call::StationRequest { station: p.station, method: p.method, path: p.path, body: p.body }
        }
        "chat.send" => {
            let p: Send = read(params)?;
            Call::ChatSend { station: p.station, thread: p.thread, text: p.text, attachments: p.attachments, quotes: p.quotes }
        }
        "chat.retry" => {
            let p: Outgoing = read(params)?;
            Call::ChatRetry { station: p.station, thread: p.thread, id: p.id }
        }
        "chat.discard" => {
            let p: Outgoing = read(params)?;
            Call::ChatDiscard { station: p.station, thread: p.thread, id: p.id }
        }
        "chat.older" => {
            let p: Chat = read(params)?;
            Call::ChatOlder { station: p.station, thread: p.thread }
        }
        "chat.read" => {
            let p: Read = read(params)?;
            Call::ChatRead { station: p.station, thread: p.thread, seq: p.seq }
        }
        "station.upload" => {
            let p: Upload = read(params)?;
            Call::StationUpload { bytes: base64(&p.bytes, "文件内容")?, station: p.station, key: p.key, name: p.name }
        }
        "station.file" => {
            let p: File = read(params)?;
            Call::StationFile { station: p.station, key: p.key, name: p.name }
        }
        "migrate" => {
            let p: Migrate = read(params)?;
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
        let chats: ClientMessage = serde_json::from_value(json!({"id": 4, "subscribe": {"topic": "chats", "scope": "w", "mine": true}})).unwrap();
        assert_eq!(chats, ClientMessage::Subscribe { id: 4, subscribe: Topic::Chats { scope: "w".into(), mine: true } });
        let chats: ClientMessage = serde_json::from_value(json!({"id": 4, "subscribe": {"topic": "chats", "scope": "local"}})).unwrap();
        assert_eq!(chats, ClientMessage::Subscribe { id: 4, subscribe: Topic::Chats { scope: "local".into(), mine: false } });
        let chat: ClientMessage = serde_json::from_value(json!({"id": 5, "subscribe": {"topic": "chat", "station": "w/s", "thread": 7}})).unwrap();
        assert_eq!(chat, ClientMessage::Subscribe { id: 5, subscribe: Topic::Chat { station: "w/s".into(), thread: 7 } });
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
        let delta = CoreMessage::Delta { id: 8, delta: crate::delta::diff(&json!({"t": [1]}), &json!({"t": [1, 2]})) };
        assert_eq!(serde_json::to_value(delta).unwrap(), json!({"id": 8, "delta": [{"path": ["t"], "append": [2]}]}));
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
        assert_eq!(
            parse_call("chat.send", json!({"station": "w/s", "thread": 7, "text": "hi"})).unwrap(),
            Call::ChatSend { station: "w/s".into(), thread: 7, text: "hi".into(), attachments: json!([]), quotes: json!([]) }
        );
        assert_eq!(
            parse_call("chat.retry", json!({"station": "w/s", "thread": 7, "id": "out-1"})).unwrap(),
            Call::ChatRetry { station: "w/s".into(), thread: 7, id: "out-1".into() }
        );
        assert_eq!(
            parse_call("chat.discard", json!({"station": "w/s", "thread": 7, "id": "out-1"})).unwrap(),
            Call::ChatDiscard { station: "w/s".into(), thread: 7, id: "out-1".into() }
        );
        assert_eq!(parse_call("chat.older", json!({"station": "w/s", "thread": 7})).unwrap(), Call::ChatOlder { station: "w/s".into(), thread: 7 });
        assert_eq!(parse_call("chat.read", json!({"station": "w/s", "thread": 7, "seq": 12})).unwrap(), Call::ChatRead { station: "w/s".into(), thread: 7, seq: 12 });
        // A chat is a thread: a session key does not name one.
        assert_eq!(code(parse_call("chat.send", json!({"station": "w/s", "key": "k", "text": "hi"}))), "invalid_params");
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

    // ── ember cloud's events ──

    use crate::accounts::{STORAGE_KEY, StoredAccount};
    use crate::testing::{FakeHost, json_response, run};

    /// Timers this many times faster: eviction in 0.6 s, a socket's first retry in 10 ms.
    const SPEEDUP: u64 = 100;

    fn now_s() -> f64 {
        std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64()
    }

    /// A core with one signed-in account whose token expires in 30 s (so every socket opens with a fresh one),
    /// ember cloud answering `/v1/me`, the workspace and token refreshes.
    async fn cloud_core() -> (Rc<FakeHost>, Core) {
        let host = FakeHost::new();
        host.speed_up(SPEEDUP);
        let account = StoredAccount { sub: "s1".into(), email: "a@x.com".into(), name: "阿一".into(), picture: String::new(), access: "stale".into(), refresh: "r0".into(), access_expires: now_s() + 30.0 };
        host.store(STORAGE_KEY, serde_json::to_vec(&vec![account]).unwrap());
        let refreshes = Cell::new(0);
        host.on_fetch(move |req| {
            let path = req.url.trim_start_matches("https://ember.test");
            match path {
                "/v1/me" => json_response(200, json!({"workspaces": [{"id": "ws", "name": "W"}], "invitations": [], "relay_url": "https://relay.test"})),
                "/v1/workspaces/ws" => json_response(200, json!({"id": "ws", "stations": [{"id": "st", "name": "studio", "online": false, "last_seen": 1}]})),
                "/v1/auth/refresh" => {
                    refreshes.set(refreshes.get() + 1);
                    json_response(200, json!({"access_token": format!("fresh-{}", refreshes.get()), "refresh_token": "r", "subject": "s1", "email": "a@x.com", "expires_at": now_s() + 30.0}))
                }
                _ => json_response(404, json!({"error": "not_found"})),
            }
        });
        let core = Core::new(host.clone()).await;
        (host, core)
    }

    fn count(host: &FakeHost, path: &str) -> usize {
        host.requests.borrow().iter().filter(|r| r.url.ends_with(path) && r.method == "GET").count()
    }

    /// The value subscription `id` has now, deltas applied.
    fn apply(host: &FakeHost, values: &mut HashMap<RequestId, Value>) {
        for (_, message) in host.take_emitted() {
            match message {
                CoreMessage::Value { id, value } => {
                    values.insert(id, value);
                }
                CoreMessage::Delta { id, delta } => crate::delta::apply(values.get_mut(&id).expect("a delta needs a value"), &delta),
                _ => {}
            }
        }
    }

    async fn pass(ms: u64) {
        tokio::time::sleep(std::time::Duration::from_micros(ms * 1000 / SPEEDUP)).await;
        for _ in 0..10 {
            tokio::task::yield_now().await;
        }
    }

    #[test]
    fn account_topics_follow_the_cloud_socket() {
        run(async {
            let (host, core) = cloud_core().await;
            let ui = core.connect();
            let mut values = HashMap::new();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspaces });
            core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: Topic::Workspace { workspace: "ws".into() } });
            host.settle().await;
            // One socket, the token as a subprotocol (refreshed first: it was about to expire).
            let sockets: Vec<(String, Vec<String>)> = host.sockets.borrow().iter().map(|(u, p, _)| (u.clone(), p.clone())).collect();
            assert_eq!(sockets, vec![("wss://ember.test/v1/events".to_string(), vec!["ember-events".to_string(), "ember-token.fresh-1".to_string()])]);
            // Read once, when the socket opened.
            assert_eq!((count(&host, "/v1/me"), count(&host, "/v1/workspaces/ws")), (1, 1));
            apply(&host, &mut values);
            assert_eq!(values[&1][0]["workspaces"][0]["id"], "ws");
            assert_eq!(values[&2]["stations"][0]["online"], false);

            // A station event is complete in itself.
            host.socket_send("/v1/events", r#"{"type":"station","workspace":"ws","id":"st","online":true}"#);
            host.settle().await;
            apply(&host, &mut values);
            assert_eq!(values[&2]["stations"][0]["online"], true);
            assert!(values[&2]["stations"][0]["last_seen"].as_f64().unwrap() > 1.0);
            assert_eq!((count(&host, "/v1/me"), count(&host, "/v1/workspaces/ws")), (1, 1));
            // `workspaces` reads /v1/me again, `workspace` that workspace; others are not ours.
            host.socket_send("/v1/events", r#"{"type":"workspaces"}"#);
            host.socket_send("/v1/events", r#"{"type":"workspace","id":"ws"}"#);
            host.socket_send("/v1/events", r#"{"type":"workspace","id":"other"}"#);
            host.socket_send("/v1/events", "pong");
            host.settle().await;
            assert_eq!((count(&host, "/v1/me"), count(&host, "/v1/workspaces/ws")), (2, 2));
            apply(&host, &mut values);
            assert_eq!(values[&2]["stations"][0]["online"], false, "as the cloud says now");

            // Idle: no request and no timer.
            host.sleeps.borrow_mut().clear();
            let requests = host.requests.borrow().len();
            pass(super::SOCKET_RETRY_MAX_MS * 2).await;
            assert_eq!(host.requests.borrow().len(), requests);
            assert!(host.sleeps.borrow().is_empty(), "{:?}", host.sleeps.borrow());

            // The socket drops: it opens again after a second with a fresh token, and the topics are read once.
            host.socket_close("/v1/events");
            pass(SOCKET_RETRY_MS + 200).await;
            host.settle().await;
            assert_eq!((host.sockets.borrow().len(), host.open_sockets("/v1/events")), (2, 1));
            let token = host.sockets.borrow()[1].1[1].clone();
            assert!(token.starts_with("ember-token.fresh-") && token != "ember-token.fresh-1", "{token}");
            assert_eq!((count(&host, "/v1/me"), count(&host, "/v1/workspaces/ws")), (3, 3));

            // Nobody looks any more: the socket closes (after the topics' grace) and stays closed.
            core.receive(ui, ClientMessage::Unsubscribe { id: 1, unsubscribe: true });
            core.receive(ui, ClientMessage::Unsubscribe { id: 2, unsubscribe: true });
            pass(crate::store::EVICT_AFTER_MS * 5 / 4).await;
            assert_eq!(host.open_sockets("/v1/events"), 0);
            pass(SOCKET_RETRY_MAX_MS).await;
            assert_eq!(host.sockets.borrow().len(), 2);
        });
    }

    #[test]
    fn a_refused_socket_still_reads_the_topics_and_retries_with_backoff() {
        run(async {
            let (host, core) = cloud_core().await;
            host.refuse_sockets.set(true);
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspaces });
            host.settle().await;
            assert_eq!(count(&host, "/v1/me"), 1, "read although the socket did not open");
            pass(SOCKET_RETRY_MS * 7).await;
            // 1 s, 2 s, 4 s: waits double.
            let waits: Vec<u64> = host.sleeps.borrow().iter().copied().filter(|ms| *ms >= SOCKET_RETRY_MS && *ms <= SOCKET_RETRY_MAX_MS).collect();
            assert_eq!(&waits[..3], &[1_000, 2_000, 4_000]);
            assert_eq!(count(&host, "/v1/me"), 1, "failed retries read nothing");
            host.refuse_sockets.set(false);
            pass(SOCKET_RETRY_MS * 10).await;
            host.settle().await;
            assert_eq!(host.open_sockets("/v1/events"), 1);
            assert_eq!(count(&host, "/v1/me"), 2, "read again once it opened");
        });
    }

    #[test]
    fn encodes_path_segments_like_encode_uri_component() {
        assert_eq!(encode("ws_01-a.b~"), "ws_01-a.b~");
        assert_eq!(encode("a/b c?"), "a%2Fb%20c%3F");
        assert_eq!(encode("工"), "%E5%B7%A5");
    }
}
