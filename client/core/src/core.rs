//! `Core`: takes messages from connected UIs, answers calls, keeps
//! subscriptions. Construction wires the modules together: accounts → cloud →
//! mesh links (member credentials come from cloud as the account that reaches the
//! workspace) → stations; the store routes topics to accounts (accounts,
//! workspaces, workspace), stations (everything with a station) or the views.
//!
//! The account topics live here: `accounts` is the list itself, `workspaces`
//! every account's `/v1/me`, `workspace` one `GET /v1/workspaces/:id`. While
//! `workspaces` or a `workspace` is live, each signed-in account holds still.fail
//! cloud's `/v1/events` socket, and the topics change when it says so:
//! `workspaces` reads that account's `/v1/me` again, `workspace` that
//! workspace, and `station` sets the station's `online` in place. Every time a
//! socket opens, the live account topics are read once (nothing is replayed).
//! They are also read when the accounts change and after a write to still.fail
//! cloud (ops.rs); never on a timer.

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::rc::{Rc, Weak};

use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use futures::future::{AbortHandle, Abortable, LocalBoxFuture, Shared, join_all};
use futures::{FutureExt, StreamExt};
use serde::{Deserialize, Serialize};
use serde::de::DeserializeOwned;
use serde_json::{Value, json};

use crate::accounts::{AccountView, Accounts};
use crate::attend::{Attend, Due};
use crate::choose::{Choose, Saved};
use crate::cloud::{Cloud, Credential};
use crate::data::{Center, Data};
use crate::error::{CoreError, Result};
use crate::host::Host;
use crate::kept::Kept;
use crate::mesh::{CredentialSource, Mesh};
use crate::protocol::{ClientId, ClientMessage, CoreMessage, RequestId, Topic};
use crate::station::{self, MeshSource, StationAddr, StationCredentials, Stations, TopicSink};
use crate::status::{Place, Status};
use crate::store::{Source, Store};
use crate::notices::Notices;
use crate::sync::Sync;
use crate::trace::{self, Kind, Span, Tracer};
use crate::views::{EmailOf, Views};
use crate::wake::{self, Wake, Wakes, WakingHost};

/// The first wait before an events socket is opened again; it doubles up to [`SOCKET_RETRY_MAX_MS`], and starts
/// over once a socket held for a minute.
pub const SOCKET_RETRY_MS: u64 = 1_000;
pub const SOCKET_RETRY_MAX_MS: u64 = 60_000;
/// An events socket that answered a ping before and then heard nothing this long (the host pings every
/// `SOCKET_PING_MS`, host.rs) is on a connection that is gone though nothing said so: it is opened again.
pub const SOCKET_IDLE_MS: u64 = 2 * crate::host::SOCKET_PING_MS + 10_000;
/// The subprotocol still.fail cloud's `/v1/events` answers with; the token travels as a second one.
pub const EVENTS_PROTOCOL: &str = "stillfail-events";

pub struct Core {
    inner: Rc<Inner>,
    next_client: Cell<ClientId>,
}

struct Inner {
    me: Weak<Inner>,
    host: Rc<dyn Host>,
    tracer: Rc<Tracer>,
    /// Client errors recorded lately, by source and message, and when (the same one once a minute).
    reported: RefCell<HashMap<String, f64>>,
    accounts: Rc<Accounts>,
    cloud: Rc<Cloud>,
    store: Rc<Store>,
    stations: Rc<Stations>,
    /// What the core keeps in sync by itself, whatever the UI shows (sync.rs).
    sync: Rc<Sync>,
    views: Rc<Views>,
    /// What chats run on, chosen: a new chat's, a model control's (choose.rs).
    choose: Rc<Choose>,
    /// Threads' entries and transcripts kept on the device.
    kept: Rc<Kept>,
    /// The data center: what the cloud and the stations said (data.rs).
    data: Rc<Data>,
    /// Where what is read or pushed goes: the data center, or the store for the rest.
    center: Rc<Center>,
    /// The device endpoint, brought up once (it needs the relay url from `/v1/me`); cleared if that fails so the next use retries.
    mesh: RefCell<Option<Shared<LocalBoxFuture<'static, Result<Rc<Mesh>>>>>>,
    relay_url: RefCell<Option<String>>,
    /// Which account reaches each workspace, from the latest `/v1/me` answers.
    owners: RefCell<HashMap<String, String>>,
    /// Whether each account's latest `/v1/me` answered this run, or why it failed. What it said is the data
    /// center's `me` record (kept from run to run): whom the account reaches.
    mes: RefCell<HashMap<String, Result<()>>>,
    /// The accounts as last shown, so a change that UIs cannot see (a refreshed token) is not one.
    shown_accounts: RefCell<Vec<AccountView>>,
    /// Every account's `/v1/me` under way.
    me_loading: RefCell<Option<Shared<LocalBoxFuture<'static, ()>>>>,
    /// Numbers the `/v1/me` requests per account, so only the newest answer is kept.
    me_fetches: RefCell<HashMap<String, u64>>,
    /// The live `workspaces` / `workspace` topics, each with the number of its newest fetch.
    live: RefCell<HashMap<Topic, u64>>,
    /// Per account, its still.fail cloud events socket while an account topic is live.
    sockets: RefCell<HashMap<String, Socket>>,
    /// What is waited on, for the `status` topic.
    status: Rc<Status>,
    /// Where each UI's attention is, and what follows (attend.rs).
    attend: Rc<Attend>,
    /// Told when a UI is back after being away (wake.rs).
    wakes: Rc<Wakes>,
    /// The calls under way, by client and id: a UI cancels one, a UI gone cancels its own.
    calls: RefCell<HashMap<(ClientId, RequestId), AbortHandle>>,
    /// Preview sockets open (`preview.socket`), by client and the name its UI gave each: where `preview.socket.send`
    /// puts the page's messages.
    preview_sockets: Rc<RefCell<HashMap<(ClientId, String), SocketInbox>>>,
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
    /// Keeps times in words fresh while anything is shown (a UI's core; see `Store::tick`).
    pub fn keep_time(&self) {
        self.inner.store.set_clock();
    }

    pub async fn new(host: Rc<dyn Host>) -> Core {
        Core::traced(host, trace::SAMPLE).await
    }

    /// A core that records `sample` of its traces (0: none).
    pub async fn traced(host: Rc<dyn Host>, sample: f64) -> Core {
        // Everything the core asks of the host is given up or opened again when a UI comes back (wake.rs).
        let wakes = Rc::new(Wakes::default());
        let host: Rc<dyn Host> = WakingHost::new(host, wakes.clone());
        let tracer = Tracer::new(host.clone(), sample);
        let accounts = Accounts::load(host.clone()).await;
        let status = Status::new(host.clone());
        let cloud = Cloud::new(host.clone(), accounts.clone(), tracer.clone(), status.clone());
        // What was last known is there before any UI asks.
        let data = Data::new(host.clone());
        data.load().await;
        let attend = Attend::load(host.clone()).await;
        let inner = Rc::new_cyclic(|me: &Weak<Inner>| {
            let store = Store::new(host.clone());
            // What goes out is what the clients' types say (client/shapes).
            store.set_shaped();
            store.set_held({
                let data = data.clone();
                Rc::new(move |topic: &Topic| data.get(topic))
            });
            data.on_change({
                let store = Rc::downgrade(&store);
                Rc::new(move |topic: &Topic| {
                    if let Some(store) = store.upgrade() {
                        store.changed(topic);
                    }
                })
            });
            let center = Rc::new(Center { store: store.clone(), data: data.clone() });
            let wire = station::wire(host.clone(), mesh_source(me.clone()), credentials(me.clone()), status.clone());
            status.on_change({
                let store = Rc::downgrade(&store);
                Rc::new(move || {
                    if let Some(store) = store.upgrade() {
                        store.invalidate(&Topic::Status);
                    }
                })
            });
            status.set_names(name_of(me.clone()));
            let kept = Kept::new(host.clone());
            let stations = Stations::new(host.clone(), center.clone() as Rc<dyn TopicSink>, wire, tracer.clone(), kept.clone(), status.clone());
            let views = Views::new(host.clone(), store.clone(), email_of(me.clone()));
            let choose = Choose::new(host.clone(), store.clone(), data.clone(), views.clone(), check_profile(me.clone()));
            let sync = Sync::new(store.clone(), host.clone());
            let notices = Notices::new(store.clone(), host.clone(), email_of(me.clone()));
            let jobs = crate::jobs::Polls::new(host.clone(), Rc::downgrade(&store), Rc::downgrade(&stations));
            store.set_source(Rc::new(Router { core: me.clone(), stations: stations.clone(), views: views.clone(), choose: choose.clone(), status: status.clone(), notices: notices.clone(), attend: attend.clone(), jobs, tracer: tracer.clone(), opening: RefCell::default() }));
            sync.on_look({
                let notices = Rc::downgrade(&notices);
                let (attend, store) = (Rc::downgrade(&attend), Rc::downgrade(&store));
                Rc::new(move |stations: &[String]| {
                    let (Some(notices), Some(attend), Some(store)) = (notices.upgrade(), attend.upgrade(), store.upgrade()) else { return };
                    let added = notices.look(stations);
                    if attend.noticed(&added, store.subscribed(&Topic::Notify)) {
                        store.invalidate(&Topic::Notify);
                    }
                })
            });
            Inner {
                sync,
                views,
                choose,
                kept,
                data: data.clone(),
                center,
                me: me.clone(),
                host: host.clone(),
                tracer: tracer.clone(),
                reported: RefCell::default(),
                accounts: accounts.clone(),
                cloud,
                store,
                stations,
                mesh: RefCell::default(),
                relay_url: RefCell::default(),
                owners: RefCell::default(),
                mes: RefCell::default(),
                me_loading: RefCell::default(),
                shown_accounts: RefCell::new(accounts.list()),
                me_fetches: RefCell::default(),
                live: RefCell::default(),
                sockets: RefCell::default(),
                status: status.clone(),
                attend: attend.clone(),
                wakes,
                calls: RefCell::default(),
                preview_sockets: Rc::default(),
            }
        });
        // Whom each account reaches, as the data center has it from the last run: views put together before the
        // first `/v1/me` answers know whose workspace is whose.
        inner.recompute_owners();
        // From now on the core keeps its workspaces and stations in sync, whatever the UI shows.
        inner.sync.start();
        // Whether this device has pushes, as it was left.
        if let Some(kept) = host.storage_get(PUSH_KEY).await.ok().flatten().and_then(|b| serde_json::from_slice::<KeptPush>(&b).ok()) {
            attend.set_pushing(!kept.with.is_empty());
        }
        let me = Rc::downgrade(&inner);
        tracer.set_export(Rc::new(move |body: Vec<u8>| {
            let me = me.clone();
            async move {
                let Some(core) = me.upgrade() else { return };
                // Any signed-in account will do: still.fail cloud only needs to know that someone of ours sends them.
                let Some(account) = core.accounts.list().into_iter().next() else { return };
                let _ = core.cloud.traces(&account.sub, body).await;
            }
            .boxed_local()
        }));
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
        self.inner.attend.gone(client);
        self.inner.attended();
        let calls: Vec<AbortHandle> = self.inner.calls.borrow_mut().extract_if(|(c, _), _| *c == client).map(|(_, abort)| abort).collect();
        for call in calls {
            call.abort();
        }
    }

    /// A message from a UI. Answers and values go out through `Host::emit`.
    pub fn receive(&self, client: ClientId, message: ClientMessage) {
        match message {
            ClientMessage::Call { id, call: name, params } => match parse_call(&name, params) {
                Err(error) => self.inner.host.emit(client, answer(id, Err(error))),
                Ok(call) => {
                    // Each call is a trace: what it asks of stations and still.fail cloud are its spans.
                    let tracer = &self.inner.tracer;
                    let mut span = tracer.root(name, Kind::Internal);
                    if let Some(station) = call.station() {
                        span.set("stillfail.station", station_id(station).to_string());
                    }
                    let inner = self.inner.clone();
                    // How far a call has got, for a UI that asked to hear it: values under the call's id, before its answer.
                    let progress: Progress = {
                        let inner = self.inner.clone();
                        Rc::new(move |value| inner.host.emit(client, CoreMessage::Value { id, value }))
                    };
                    // Only a call that holds something open for its page can be stopped (and is, with the page):
                    // one that changes something (a message sent, a file uploaded) runs to its end whoever waits.
                    let registration = call.cancellable().then(|| {
                        let (abort, registration) = AbortHandle::new_pair();
                        self.inner.calls.borrow_mut().insert((client, id), abort);
                        registration
                    });
                    self.inner.host.spawn(tracer.instrument(Some(span.context()), async move {
                        let run = inner.execute(call, progress, (client, id));
                        let result = match registration {
                            Some(registration) => {
                                let result = Abortable::new(run, registration).await.unwrap_or_else(|_| Err(CoreError::new("cancelled", "已取消")));
                                inner.calls.borrow_mut().remove(&(client, id));
                                result
                            }
                            None => run.await,
                        };
                        if let Err(error) = &result {
                            span.fail();
                            span.set("error.type", error.code.clone());
                        }
                        span.end();
                        inner.host.emit(client, answer(id, result));
                    }));
                }
            },
            ClientMessage::Subscribe { id, subscribe } => self.inner.store.subscribe(client, id, subscribe),
            ClientMessage::Unsubscribe { id, .. } => self.inner.store.unsubscribe(client, id),
            ClientMessage::Cancel { id, .. } => {
                let call = self.inner.calls.borrow_mut().remove(&(client, id));
                if let Some(call) = call {
                    call.abort();
                }
            }
        }
    }
}

/// Station topics go to `Stations`, views to `Views`; the account topics are kept here.
struct Router {
    core: Weak<Inner>,
    stations: Rc<Stations>,
    views: Rc<Views>,
    choose: Rc<Choose>,
    status: Rc<Status>,
    notices: Rc<Notices>,
    attend: Rc<Attend>,
    /// A job and its output, read again while shown (jobs.rs).
    jobs: Rc<crate::jobs::Polls>,
    tracer: Rc<Tracer>,
    /// Views opening: each is a trace (`chat.open`, …) until its first value goes out.
    opening: RefCell<HashMap<Topic, Span>>,
}

/// A station's id in its address (`"<workspace>/<station>"`), or `local`.
fn station_id(address: &str) -> &str {
    address.rsplit('/').next().unwrap_or(address)
}

impl Source for Router {
    fn start(&self, topic: &Topic) {
        // Always kept (status.rs): only computed while shown.
        if *topic == Topic::Status {
            self.status.changed();
            return;
        }
        if *topic == Topic::Notices {
            self.notices.changed();
            return;
        }
        if *topic == Topic::Notify {
            if let Some(core) = self.core.upgrade() {
                core.store.invalidate(topic);
            }
            return;
        }
        if Choose::handles(topic) {
            return self.choose.start(topic);
        }
        // Kept on the device (data.rs) and nowhere else: what is there goes out, or, with nothing written, empty.
        if matches!(topic, Topic::Draft { .. } | Topic::Prefs) {
            if let Some(core) = self.core.upgrade() {
                core.store.invalidate(topic);
            }
            return;
        }
        if crate::jobs::Polls::owns(topic) {
            self.jobs.start(topic);
            return;
        }
        // Followed by its station (station.rs, below); what it says in words goes out fresh as it changes (jobs.rs).
        if let Topic::JobLog { .. } = topic {
            self.jobs.words(topic);
        }
        if topic.is_view() {
            let (name, station) = match topic {
                Topic::Chat { station, .. } => ("chat.open", Some(station)),
                Topic::ChatJobs { station, .. } => ("jobs.open", Some(station)),
                Topic::LongJobs { .. } => ("jobs.open", None),
                Topic::Chats { .. } => ("chats.open", None),
                Topic::ChatSearch { .. } => ("chats.search", None),
                Topic::Stations { .. } => ("stations.open", None),
                Topic::Archive { .. } => ("archive.open", None),
                _ => ("connects.open", None),
            };
            let mut span = self.tracer.root(name, Kind::Internal);
            if let Some(station) = station {
                span.set("stillfail.station", station_id(station).to_string());
            }
            let context = span.context();
            self.opening.borrow_mut().insert(topic.clone(), span);
            // The topics it watches start now, inside the trace, and so do their first requests.
            self.tracer.enter(Some(context), || self.views.start(topic));
        } else if topic.station().is_some() {
            self.stations.start(topic);
        } else if let Some(core) = self.core.upgrade() {
            core.start_topic(topic);
        }
    }

    fn stop(&self, topic: &Topic) {
        if *topic == Topic::Status || *topic == Topic::Notices || *topic == Topic::Notify || matches!(topic, Topic::Draft { .. } | Topic::Prefs) {
            return;
        }
        if Choose::handles(topic) {
            return self.choose.stop(topic);
        }
        if crate::jobs::Polls::owns(topic) {
            return self.jobs.stop(topic);
        }
        // Followed by its station (station.rs); what it says in words goes out fresh as it changes (jobs.rs).
        if let Topic::JobLog { .. } = topic {
            self.jobs.stop(topic);
        }
        if topic.is_view() {
            // Given up before it had a value: recorded as cancelled.
            let opening = self.opening.borrow_mut().remove(topic);
            drop(opening);
            self.views.stop(topic);
        } else if topic.station().is_some() {
            self.stations.stop(topic);
        } else if let Some(core) = self.core.upgrade() {
            core.live.borrow_mut().remove(topic);
            core.sync_sockets();
        }
    }

    fn compute(&self, topic: &Topic) -> Option<Result<Value>> {
        if *topic == Topic::Status {
            return Some(Ok(self.status.value()));
        }
        if *topic == Topic::Notices {
            return Some(Ok(self.notices.value()));
        }
        if *topic == Topic::Notify {
            return Some(Ok(self.attend.value()));
        }
        if Choose::handles(topic) {
            return self.choose.compute(topic);
        }
        // A draft held has its record's value (data.rs); none is nothing written.
        if let Topic::Draft { .. } = topic {
            return Some(Ok(json!({ "text": "", "quotes": [], "files": [] })));
        }
        // Nothing chosen on this device yet: the defaults (the shape fills them in).
        if *topic == Topic::Prefs {
            return Some(Ok(json!({})));
        }
        let Some(context) = self.opening.borrow().get(topic).map(Span::context) else { return self.views.compute(topic).map(|v| self.attended(topic, v)) };
        // Still opening: what it starts now (a chat's agents) is part of it too.
        let value = self.tracer.enter(Some(context), || self.views.compute(topic)).map(|v| self.attended(topic, v));
        let opened = if value.is_some() { self.opening.borrow_mut().remove(topic) } else { None };
        if let Some(mut span) = opened {
            if let Some(Err(error)) = &value {
                span.fail();
                span.set("error.type", error.code.clone());
            }
            span.end();
        }
        value
    }
}

impl Router {
    /// A chat as its UIs attend to it (attend.rs): its unread line; its older page loaded, or it read, when due.
    fn attended(&self, topic: &Topic, value: Result<Value>) -> Result<Value> {
        let Topic::Chat { station, session, .. } = topic else { return value };
        let mut value = value?;
        let due = self.attend.chat(station, session.as_deref(), &mut value);
        if due.is_empty() {
            return Ok(value);
        }
        let (Some(core), Ok(addr)) = (self.core.upgrade(), StationAddr::parse(station)) else { return Ok(value) };
        let (station, me) = (station.clone(), Rc::downgrade(&core));
        core.host.spawn(async move {
            for due in due {
                let Some(core) = me.upgrade() else { return };
                let done = match due {
                    Due::Older { thread } => core.stations.older(&addr, thread).await.map(|_| ()),
                    Due::Read { thread, seq } => core.stations.read(&addr, thread, seq).await,
                };
                if done.is_err() {
                    core.attend.failed(&station, &due);
                }
            }
        }.boxed_local());
        Ok(value)
    }
}

/// Has a station's profile check itself (what a new chat offers is what the check found).
fn check_profile(core: Weak<Inner>) -> crate::choose::Check {
    Rc::new(move |station: &str, profile: &str| {
        let Some(core) = core.upgrade() else { return };
        let (station, path) = (station.to_string(), format!("/profiles/{}/check", encode(profile)));
        let run = core.clone();
        core.host.spawn(async move {
            if let Ok(addr) = StationAddr::parse(&station) {
                let _ = run.stations.request(&addr, "POST", &path, None).await;
            }
        }.boxed_local());
    })
}

/// A station's name by its address, as its workspace was last read (for what the status says).
fn name_of(core: Weak<Inner>) -> crate::status::NameOf {
    Rc::new(move |address: &str| {
        let core = core.upgrade()?;
        let (workspace, id) = address.split_once('/')?;
        let workspace = core.store.get(&Topic::Workspace { workspace: workspace.to_string() })?;
        let station = workspace.get("stations")?.as_array()?.iter().find(|s| s.get("id").and_then(Value::as_str) == Some(id))?.clone();
        station.get("name")?.as_str().map(str::to_string)
    })
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

/// This device's member credential for a workspace, as whichever account reaches it (`Inner::credential`).
fn credentials(core: Weak<Inner>) -> StationCredentials {
    Rc::new(move |workspace: &str| {
        let (core, workspace) = (core.clone(), workspace.to_string());
        let source: CredentialSource = Rc::new(move |device: String, fresh: bool| {
            let (core, workspace) = (core.clone(), workspace.clone());
            async move { core.upgrade().ok_or_else(gone)?.credential(&workspace, &device, fresh).await }.boxed_local()
        });
        source
    })
}

/// Where a device's member credentials are kept (`<key>/<account>/<workspace>`, a [`KeptCredential`]), and how long
/// one serves before a new one is asked for.
const CREDENTIAL_KEY: &str = "credential";
const CREDENTIAL_FOR_S: f64 = 24.0 * 60.0 * 60.0;

/// Where this device's push registration is kept (docs/notifications.md), and the accounts that have it.
const PUSH_KEY: &str = "push";

#[derive(Serialize, Deserialize)]
struct KeptPush {
    registration: Value,
    #[serde(default)]
    with: Vec<String>,
}

/// A credential as kept, with the device it names: one for another device key (the page's, taken over) is no use.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct KeptCredential {
    device: String,
    #[serde(flatten)]
    credential: Credential,
}

fn gone() -> CoreError {
    CoreError::new("closed", "核心已关闭")
}

impl Inner {
    /// Runs a call; `at` is the client and id it came with.
    async fn execute(&self, call: Call, progress: Progress, at: (ClientId, RequestId)) -> Result<Value> {
        let at_call = at;
        match call {
            Call::AuthBegin { redirect_uri, return_to, device_name } => {
                // Named by the UI (those from before `client.device`), else as the device is.
                let device_name = device_name.or_else(|| crate::prefs::device_name(&self.data)).unwrap_or_else(|| "still.fail".into());
                let url = self.accounts.begin_sign_in(&redirect_uri, &return_to, &device_name).await?;
                Ok(json!({ "url": url }))
            }
            Call::AuthComplete { query } => {
                let (account, return_to) = self.accounts.complete_sign_in(&query).await?;
                Ok(json!({ "account": account, "return_to": return_to }))
            }
            Call::Wake { away, network, retry } => {
                let wake = Wake { at: self.host.now_ms(), away: away.max(0.0), network: network && !retry, retry };
                // What is asked again as the wake fails what was under way goes on new connections.
                if wake.suspects_connections() {
                    self.host.reset_connections();
                }
                self.wakes.wake(wake);
                Ok(json!({}))
            }
            Call::ClientError { source, message } => {
                let key = format!("{source}\u{0}{message}");
                let now = self.host.now_ms();
                let fresh = {
                    let mut reported = self.reported.borrow_mut();
                    let fresh = reported.get(&key).is_none_or(|at| now - at > 60_000.0);
                    if fresh {
                        reported.insert(key, now);
                    }
                    fresh
                };
                if fresh {
                    let mut span = self.tracer.always("client.error", Kind::Internal);
                    span.set("stillfail.source", source);
                    span.set("error.type", "client");
                    span.set("exception.message", message.chars().take(1000).collect::<String>());
                    span.fail();
                    span.end();
                }
                Ok(json!({}))
            }
            Call::SignOut { account } => {
                self.accounts.sign_out(&account).await?;
                Ok(Value::Null)
            }
            Call::PushKey => {
                let request = crate::host::HttpRequest { method: "GET".into(), url: format!("{}/v1/push/key", self.host.cloud_origin()), headers: Vec::new(), body: None };
                let response = self.host.fetch(request).await?;
                let data: Value = serde_json::from_slice(&response.body).unwrap_or_else(|_| json!({}));
                match data.get("vapid").and_then(Value::as_str) {
                    Some(key) if response.status == 200 => Ok(json!({ "vapid": key })),
                    _ => Err(CoreError::new("push_unavailable", "still.fail cloud 还不能推送")),
                }
            }
            Call::PushRegister { registration } => {
                // Notifications off: this device has no pushes (attend.rs).
                if !self.attend.on() {
                    return Ok(Value::Null);
                }
                let kept = KeptPush { registration, with: Vec::new() };
                let _ = self.host.storage_set(PUSH_KEY, serde_json::to_vec(&kept).unwrap_or_default()).await;
                let done = self.push_registered().await;
                self.attend.set_pushing(done.is_ok());
                done
            }
            Call::PushUnregister => {
                self.attend.set_pushing(false);
                let kept = self.host.storage_get(PUSH_KEY).await.ok().flatten().and_then(|b| serde_json::from_slice::<KeptPush>(&b).ok());
                let _ = self.host.storage_delete(PUSH_KEY).await;
                if let Some(kept) = kept {
                    let mut gone = json!({});
                    for k in ["endpoint", "token"] {
                        if let Some(v) = kept.registration.get(k) {
                            gone[k] = v.clone();
                        }
                    }
                    for account in self.accounts.list() {
                        let _ = self.cloud.request(&account.sub, "DELETE", "/v1/push", Some(gone.clone())).await;
                    }
                }
                Ok(Value::Null)
            }
            Call::Op(op) => match op.target {
                crate::ops::Target::Cloud(account) => {
                    let made = op.method == "POST" && op.path == "/v1/workspaces";
                    let result = self.cloud.request(&account, op.method, &op.path, op.body).await?;
                    // A workspace made: the invite code kept through signing in is done with.
                    if made {
                        crate::prefs::invite_used(&self.data);
                    }
                    // A write may rename, join or leave a workspace: what the account topics show changed too.
                    if op.method != "GET" {
                        self.refresh_all().await;
                    }
                    Ok(result)
                }
                crate::ops::Target::Station(station) => {
                    let addr = StationAddr::parse(&station)?;
                    let machine = op.method == "GET" && op.path.starts_with("/machine-sessions");
                    let mut result = match (self.stations.request(&addr, op.method, &op.path, op.body.clone()).await, op.fallback) {
                        // A station from before the request knew another way.
                        (Err(e), Some((method, path))) if e.status == Some(404) => self.stations.request(&addr, method, &path, op.body).await,
                        (result, _) => result,
                    };
                    // The machine's own sessions, each in a line (choose.rs).
                    if let (true, Ok(answer)) = (machine, result.as_mut()) {
                        let now = self.host.now_ms();
                        answer.get_mut("sessions").and_then(Value::as_array_mut).into_iter().flatten().for_each(|s| crate::choose::machine_meta(s, now));
                        if let Some(s) = answer.get_mut("session") {
                            crate::choose::machine_meta(s, now);
                        }
                    }
                    result
                }
            },
            // Out of the chat lists at once while its station archives it; back if it could not.
            Call::ChatArchive { op, thread, session, archived } => {
                let station = match &op.target {
                    crate::ops::Target::Station(station) => station.clone(),
                    crate::ops::Target::Cloud(_) => return Err(CoreError::invalid("参数不对：要有 station")),
                };
                if archived {
                    self.views.archiving(&station, thread, &session, true);
                }
                let result = Box::pin(self.execute(Call::Op(op), progress, at)).await;
                if archived {
                    self.views.archiving(&station, thread, &session, false);
                }
                result
            }
            Call::ChatSend { station, thread, text, attachments, quotes, client } => {
                let message = outgoing(crate::refs::expand(&self.data, &text), attachments, quotes, client.or_else(|| crate::prefs::sent_from(&self.data)));
                let id = self.views.outbox_add(&station, thread, message.clone());
                self.deliver(&station, thread, &id, message).await
            }
            Call::ChatCreate { station, ask } => {
                StationAddr::parse(&station)?;
                let key = self.views.pending_new(&station, ask);
                self.make_chat(&key);
                Ok(json!({ "key": key }))
            }
            Call::ChatSendTo { station, session, text, attachments, quotes, client } => {
                let message = outgoing(crate::refs::expand(&self.data, &text), attachments, quotes, client.or_else(|| crate::prefs::sent_from(&self.data)));
                match self.views.pending_thread(&station, &session) {
                    Some(Some(thread)) => {
                        let id = self.views.outbox_add(&station, thread, message.clone());
                        self.deliver(&station, thread, &id, message).await
                    }
                    // It waits for the chat; one that could not be made is tried again with it.
                    Some(None) => {
                        let failed = self.views.pending_failed_now(&session);
                        let id = self.views.pending_queue(&session, message).ok_or_else(|| CoreError::invalid("没有这个对话"))?;
                        if failed {
                            self.make_chat(&session);
                        }
                        Ok(json!({ "id": id }))
                    }
                    None => Err(CoreError::invalid("没有这个对话")),
                }
            }
            Call::ChatRetryIn { station, session, id } => match self.views.pending_thread(&station, &session) {
                Some(Some(thread)) => Box::pin(self.execute(Call::ChatRetry { station, thread, id }, progress, at)).await,
                Some(None) => {
                    self.make_chat(&session);
                    Ok(Value::Null)
                }
                None => Err(CoreError::invalid("没有这个对话")),
            },
            Call::ChatDiscardIn { station, session, id } => {
                match self.views.pending_thread(&station, &session) {
                    Some(Some(thread)) => self.views.outbox_remove(&station, thread, &id),
                    Some(None) => {
                        self.views.pending_discard(&session, &id);
                    }
                    None => return Err(CoreError::invalid("没有这个对话")),
                }
                Ok(Value::Null)
            }
            Call::ChatRetry { station, thread, id } => {
                let entry = self.views.outbox_get(&station, thread, &id).ok_or_else(|| CoreError::invalid("没有这条待发的消息"))?;
                self.views.outbox_state(&station, thread, &id, None);
                self.deliver(&station, thread, &id, crate::views::sent_as(&entry)).await
            }
            Call::ChatDiscard { station, thread, id } => {
                self.views.outbox_remove(&station, thread, &id);
                Ok(Value::Null)
            }
            Call::ChatOlder { station, thread } => Ok(json!({ "more": self.stations.older(&StationAddr::parse(&station)?, thread).await? })),
            Call::HistoryOlder { station, key } => Ok(json!({ "more": self.stations.history_older(&StationAddr::parse(&station)?, &key).await? })),
            Call::ChatRead { station, thread, seq } => {
                self.stations.read(&StationAddr::parse(&station)?, thread, seq).await?;
                Ok(Value::Null)
            }
            Call::Attend(call) => match call {
                crate::attend::Call::Focus(focus) => {
                    self.attend.focus(at.0, focus);
                    self.attended();
                    Ok(Value::Null)
                }
                crate::attend::Call::Set { on, asked } => {
                    self.attend.set(on, asked).await;
                    self.store.invalidate(&Topic::Notify);
                    // Off: this device's pushes go too.
                    if on == Some(false) {
                        Box::pin(self.execute(Call::PushUnregister, progress, at)).await?;
                    }
                    Ok(self.attend.value())
                }
                crate::attend::Call::Claim { id } => {
                    let show = self.attend.claim(&id);
                    if show {
                        self.store.invalidate(&Topic::Notify);
                    }
                    Ok(json!({ "show": show }))
                }
                crate::attend::Call::Pushed => Ok(json!({ "show": self.attend.pushed() })),
            },
            Call::Choose { name, params } => {
                let at = |field: &str| params.get(field).and_then(Value::as_str).unwrap_or("").to_string();
                match name.as_str() {
                    "newChat.pick" => self.choose.pick_new(&at("scope"), &params).map(|_| Value::Null),
                    "newChat.migrate" => {
                        self.choose.migrate(&params);
                        Ok(Value::Null)
                    }
                    // Made as `chat.create` makes it, with what is picked there.
                    "newChat.create" => {
                        let ask = self.choose.create(&at("station"))?;
                        let made = Box::pin(self.execute(Call::ChatCreate { station: at("station"), ask: ask.clone() }, progress, at_call)).await?;
                        Ok(json!({ "key": made["key"], "runtime": ask["runtime"], "model": ask["model"], "effort": ask.get("effort") }))
                    }
                    "pick.set" => self.choose.set(&at("station"), &at("of"), &params).map(|_| Value::Null),
                    _ => match self.choose.save(&at("station"), &at("of"))? {
                        Saved::Done(value) => Ok(value),
                        Saved::Op(op) => {
                            Box::pin(self.execute(Call::Op(op), progress, at_call)).await?;
                            Ok(json!({ "saved": true }))
                        }
                    },
                }
            }
            Call::DraftPut { station, chat, draft } => {
                let topic = Topic::Draft { station, chat };
                let empty = |field: &str| draft.get(field).is_none_or(|v| v.as_str().is_some_and(|s| s.trim().is_empty()) || v.as_array().is_some_and(Vec::is_empty));
                if empty("text") && empty("quotes") && empty("files") {
                    self.data.forget_topic(&topic);
                } else {
                    self.data.set_soon(&topic, draft);
                }
                Ok(Value::Null)
            }
            Call::DraftGet { station, chat } => Ok(self.data.get(&Topic::Draft { station, chat }).unwrap_or_else(|| json!({ "text": "", "quotes": [], "files": [] }))),
            Call::ChatRef { station, id, title, base } => {
                let base = base.unwrap_or_else(|| self.host.cloud_origin());
                Ok(json!({ "mark": crate::refs::mark(&self.data, &base, &station, &id, &title) }))
            }
            Call::ChatRefsKeep { links } => {
                crate::refs::keep(&self.data, links);
                Ok(Value::Null)
            }
            Call::PrefsSet { patch, fill } => {
                crate::prefs::set(&self.data, patch, fill, self.host.now_ms())?;
                Ok(Value::Null)
            }
            Call::ClientDevice { facts } => {
                crate::prefs::device(&self.data, &facts)?;
                Ok(Value::Null)
            }
            Call::StationUpload { station, name, bytes } => {
                self.stations.upload(&StationAddr::parse(&station)?, &name, bytes).await
            }
            Call::StationFile { station, key, name, thumb, progress: wanted } => {
                // `{ loaded, total }` in bytes as the file comes (total: null when the station does not say), for a UI
                // that asked: one that did not would take the first as the answer.
                let report = |loaded: u64, total: Option<u64>| {
                    if wanted {
                        progress(json!({ "loaded": loaded, "total": total }));
                    }
                };
                let (kind, bytes) = self.stations.file(&StationAddr::parse(&station)?, &key, &name, thumb, report).await?;
                Ok(json!({ "type": kind, "bytes": BASE64.encode(bytes) }))
            }
            Call::StationPreview { station, port, method, path, headers, body, stream: false } => {
                let (status, headers, bytes) = self.stations.preview(&StationAddr::parse(&station)?, port, &method, &path, headers, body).await?;
                Ok(json!({ "status": status, "headers": headers, "body": BASE64.encode(bytes) }))
            }
            // As it comes: `{head: {status, headers}}`, then `{chunk}` (base64) for each piece of the body; the answer
            // (null) once it ended. Cancelling the call stops it.
            Call::StationPreview { station, port, method, path, headers, body, stream: true } => {
                let (status, headers, mut chunks) = self.stations.preview_stream(&StationAddr::parse(&station)?, port, &method, &path, headers, body).await?;
                progress(json!({ "head": { "status": status, "headers": headers } }));
                while let Some(chunk) = chunks.next().await {
                    progress(json!({ "chunk": BASE64.encode(chunk?) }));
                }
                Ok(Value::Null)
            }
            // A preview page's WebSocket: `{open: {protocol}}` once the service took it, then `{text}` or `{binary}`
            // (base64) for each message; the answer is its close, `{code, reason}`. What the page sends goes by
            // `preview.socket.send` under the socket's name; cancelling the call drops the socket.
            Call::PreviewSocket { station, port, path, headers, socket: name } => {
                // Named before it opens: what the page sends meanwhile (a close right away) waits, and goes once it is open.
                let (tx, mut from_page) = futures::channel::mpsc::unbounded();
                let _open = Registered::new(self.preview_sockets.clone(), (at.0, name), tx).ok_or_else(|| CoreError::invalid("这个名字的 WebSocket 已经开着"))?;
                let station = StationAddr::parse(&station)?;
                let opening = self.stations.preview_socket(&station, port, &path, headers);
                let mut held = Vec::new();
                let socket = match open_unless_closed(opening, &mut from_page, &mut held).await? {
                    Ok(socket) => socket,
                    Err((code, reason)) => return Ok(json!({ "code": code, "reason": reason })),
                };
                let protocol = socket.reply.header("sec-websocket-protocol").unwrap_or("").to_string();
                progress(json!({ "open": { "protocol": protocol } }));
                let (mut from_station, mut to_station) = (socket.reply.body.fuse(), socket.send);
                let mut from_page = futures::stream::iter(held).chain(from_page);
                let mut buf = Vec::new();
                // The page's own close, once sent: what the socket closed with if the station says nothing after.
                let mut closing: Option<(u16, String)> = None;
                loop {
                    futures::select! {
                        chunk = from_station.next() => {
                            let Some(Ok(chunk)) = chunk else {
                                let (code, reason) = closing.unwrap_or((1006, String::new()));
                                return Ok(json!({ "code": code, "reason": reason }));
                            };
                            buf.extend(chunk);
                            for frame in station::SocketFrame::take(&mut buf) {
                                match frame {
                                    station::SocketFrame::Text(text) => progress(json!({ "text": text })),
                                    station::SocketFrame::Binary(bytes) => progress(json!({ "binary": BASE64.encode(bytes) })),
                                    station::SocketFrame::Close(code, reason) => return Ok(json!({ "code": code, "reason": reason })),
                                }
                            }
                        }
                        frame = from_page.next() => {
                            let Some(frame) = frame else { continue };
                            if let station::SocketFrame::Close(code, reason) = &frame {
                                closing = Some((*code, reason.clone()));
                            }
                            if to_station.write(frame.encode()).await.is_err() {
                                let (code, reason) = closing.unwrap_or((1006, String::new()));
                                return Ok(json!({ "code": code, "reason": reason }));
                            }
                        }
                    }
                }
            }
            Call::PreviewSocketSend { socket, frame } => {
                let sent = self.preview_sockets.borrow().get(&(at.0, socket)).map(|tx| tx.unbounded_send(frame).is_ok());
                match sent {
                    Some(true) => Ok(Value::Null),
                    _ => Err(CoreError::new("not_found", "这个 WebSocket 已经关了")),
                }
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

    /// Has the station make a chat asked for here (`chat.create`), in the background: then what was sent to it
    /// meanwhile goes in, in order. Failing, the chat and its messages say why, until tried again.
    fn make_chat(&self, key: &str) {
        let Some((station, ask)) = self.views.pending_try(key) else { return };
        let (Some(core), key) = (self.me.upgrade(), key.to_string()) else { return };
        self.host.spawn(async move {
            let made = async { core.stations.request(&StationAddr::parse(&station)?, "POST", "/sessions", Some(ask)).await }.await;
            let made = made.and_then(|answer| {
                let session = answer.get("key").and_then(Value::as_str).map(str::to_string);
                let thread = answer.get("thread").and_then(|t| t.get("id")).and_then(Value::as_u64);
                session.zip(thread).ok_or_else(|| CoreError::new("bad_response", "station 的回复里没有新会话"))
            });
            match made {
                Ok((session, thread)) => {
                    for (id, message) in core.views.pending_made(&key, &session, thread) {
                        // One failing stays in the outbox as failed; the rest still go, in order.
                        let _ = core.deliver(&station, thread, &id, message).await;
                    }
                }
                Err(error) => core.views.pending_failed(&key, &error.message),
            }
        }.boxed_local());
    }

    /// Posts an outgoing message into a chat. The entry leaves the outbox in the emission that brings the message
    /// into the chat's messages; a failure leaves it there as `failed`.
    async fn deliver(&self, station: &str, thread: u64, id: &str, message: Value) -> Result<Value> {
        let result = async { self.stations.post(&StationAddr::parse(station)?, thread, message).await }.await;
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
                    Mesh::new(core.host.clone(), core.tracer.clone(), &relay).await
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

    /// This device's member credential for a workspace, kept on the device: what gets it into the workspace's
    /// stations with no still.fail cloud on the way (on a LAN, or the cloud down). Kept, it serves for a day; then, or when
    /// a station refused it (`fresh`), a new one is asked for — and if still.fail cloud cannot be reached, the kept one goes
    /// on serving until it runs out (30 days).
    async fn credential(&self, workspace: &str, device: &str, fresh: bool) -> Result<Credential> {
        let sub = self.owner(workspace).await?;
        let key = format!("{CREDENTIAL_KEY}/{sub}/{workspace}");
        let now = self.host.now_ms() / 1000.0;
        let kept = self.host.storage_get(&key).await.ok().flatten().and_then(|bytes| serde_json::from_slice::<KeptCredential>(&bytes).ok());
        let kept = kept.filter(|k| k.device == device).map(|k| k.credential).filter(|c| c.expires_at > now + 60.0 && !fresh);
        if let Some(c) = kept.as_ref().filter(|c| now - c.issued_at < CREDENTIAL_FOR_S) {
            return Ok(c.clone());
        }
        match self.cloud.credential(&sub, workspace, device).await {
            Ok(credential) => {
                let kept = KeptCredential { device: device.to_string(), credential: credential.clone() };
                let _ = self.host.storage_set(&key, serde_json::to_vec(&kept).unwrap_or_default()).await;
                Ok(credential)
            }
            Err(error) => kept.ok_or(error),
        }
    }

    /// The relay the mesh uses, from any account's `/v1/me`.
    async fn relay_url(&self) -> Result<String> {
        if let Some(url) = self.relay_url.borrow().clone() {
            return Ok(url);
        }
        // As last heard (kept on the device): the mesh comes up without still.fail cloud.
        for account in self.accounts.list() {
            if let Some(url) = self.data.record("me", &account.sub).and_then(|me| me.get("relay_url")?.as_str().map(str::to_string)) {
                return Ok(url);
            }
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
            let me = match mes.get(&a.sub).cloned() {
                Some(Ok(())) => self.data.record("me", &a.sub).ok_or_else(|| CoreError::signed_out("这个账号已退出")),
                Some(Err(error)) => Err(error),
                None => Err(CoreError::signed_out("这个账号已退出")),
            };
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
                    let first = self.relay_url.borrow().is_none();
                    self.relay_url.borrow_mut().get_or_insert_with(|| url.to_string());
                    // The relay is known: bring the device endpoint up now and let it reach the relay while the page
                    // loads, so a station link has only its own handshake to do (no request of its own: the URL is here).
                    if first && self.mesh.borrow().is_none() {
                        let warm = self.me.clone();
                        self.host.spawn(
                            async move {
                                if let Some(core) = warm.upgrade() {
                                    let _ = core.mesh().await;
                                }
                            }
                            .boxed_local(),
                        );
                    }
                }
                self.data.put("me", &account.sub, me.clone());
            }
            self.mes.borrow_mut().insert(account.sub.clone(), me.map(|_| ()));
        }
        self.recompute_owners();
        self.forget_unreachable();
    }

    /// Which account reaches each workspace: the first (in sign-in order) whose last `/v1/me` answer lists it.
    /// An account whose latest request failed keeps what it was known to reach; signed-out ones are forgotten.
    fn recompute_owners(&self) {
        let accounts = self.accounts.list();
        self.mes.borrow_mut().retain(|sub, _| accounts.iter().any(|a| &a.sub == sub));
        for (sub, me) in self.data.records("me") {
            if !accounts.iter().any(|a| a.sub == sub) {
                // Signed out: its credentials go too (a station would take them for 30 days).
                for workspace in me.get("workspaces").and_then(Value::as_array).into_iter().flatten() {
                    if let Some(id) = workspace.get("id").and_then(Value::as_str) {
                        let (host, key) = (self.host.clone(), format!("{CREDENTIAL_KEY}/{sub}/{id}"));
                        self.host.spawn(async move { let _ = host.storage_delete(&key).await; }.boxed_local());
                    }
                }
                self.data.forget_record("me", &sub);
            }
        }
        let mut owners = self.owners.borrow_mut();
        owners.clear();
        for account in &accounts {
            let Some(me) = self.data.record("me", &account.sub) else { continue };
            for workspace in me.get("workspaces").and_then(Value::as_array).into_iter().flatten() {
                if let Some(id) = workspace.get("id").and_then(Value::as_str) {
                    owners.entry(id.to_string()).or_insert_with(|| account.sub.clone());
                }
            }
        }
    }

    /// What is kept on the device of stations no signed-in account reaches any more goes (all of it once the last
    /// one signs out) — decided only when every account's `/v1/me` has answered once, since one not heard from
    /// yet may reach them. The station's own page (`local`) is no account's.
    fn forget_unreachable(&self) {
        if self.accounts.list().iter().any(|a| self.data.record("me", &a.sub).is_none()) {
            return;
        }
        let workspaces: HashSet<String> = self.owners.borrow().keys().cloned().collect();
        let reached = workspaces.clone();
        self.data.retain(move |station| station == "local" || station.split_once('/').is_some_and(|(w, _)| reached.contains(w)), Some(&workspaces));
        self.host.spawn(self.kept.retain(move |station| station == "local" || station.split_once('/').is_some_and(|(w, _)| workspaces.contains(w))));
    }

    /// A workspace's stations as it lists them now: what is kept of the others in it goes.
    fn forget_gone_stations(&self, workspace: &str, view: &Value) {
        let ids: HashSet<String> = view.get("stations").and_then(Value::as_array).into_iter().flatten().filter_map(|s| Some(s.get("id")?.as_str()?.to_string())).collect();
        let workspace = workspace.to_string();
        let (listed, of) = (ids.clone(), workspace.clone());
        self.data.retain(move |station| match station.split_once('/') {
            Some((w, id)) if w == of => listed.contains(id),
            _ => true,
        }, None);
        self.host.spawn(self.kept.retain(move |station| match station.split_once('/') {
            Some((w, id)) if w == workspace => ids.contains(id),
            _ => true,
        }));
    }

    fn accounts_value(&self) -> Result<Value> {
        Ok(serde_json::to_value(self.accounts.list()).expect("accounts serialize"))
    }

    /// Every account with what its `/v1/me` said, as the data center has it (from this run, or kept from the last).
    /// `loaded` is true only once it answered this run: what was kept, or an empty list before an answer (or after a
    /// failure), is not "none" — a UI that makes a workspace for an account with none waits for it.
    fn workspaces_value(&self) -> Value {
        let mes = self.mes.borrow();
        let entries = self.accounts.list().into_iter().map(|account| {
            let me = self.data.record("me", &account.sub).unwrap_or(Value::Null);
            let mut entry = json!({
                "account": account,
                "workspaces": me.get("workspaces").cloned().unwrap_or_else(|| json!([])),
                "invitations": me.get("invitations").cloned().unwrap_or_else(|| json!([])),
                "relay_url": me.get("relay_url").cloned().unwrap_or(Value::Null),
                "loaded": matches!(mes.get(&account.sub), Some(Ok(()))),
            });
            // One account failing (offline, signed out elsewhere) still shows the others.
            if let Some(Err(error)) = mes.get(&account.sub) {
                entry["error"] = json!(error);
            }
            entry
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
        // What the accounts' `/v1/me` said last time is shown at once (not `loaded`); reading it again follows.
        if *topic == Topic::Workspaces && self.accounts.list().iter().any(|a| self.data.record("me", &a.sub).is_some()) {
            self.store.set(topic, Ok(self.workspaces_value()));
        }
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
            // Read as they are now; a write to still.fail cloud (ops.rs) reads them again (refresh_all).
            Topic::LoginSessions { account } => self.cloud.request(account, "GET", "/v1/auth/sessions", None).await.map(|v| v.get("sessions").cloned().unwrap_or(json!([]))),
            Topic::Admin { account, list } => match list.as_str() {
                "users" | "workspaces" | "invite-codes" => self.cloud.request(account, "GET", &format!("/v1/admin/{list}"), None).await,
                _ => Err(CoreError::invalid("没有这个列表")),
            },
            _ => return,
        };
        if let (Topic::Workspace { workspace }, Ok(view)) = (topic, &value) {
            self.forget_gone_stations(workspace, view);
        }
        if self.live.borrow().get(topic) == Some(&fetch) {
            // A workspace goes to the data center; the list of them is put together from the accounts' records.
            self.center.set(topic, value);
        }
    }

    /// What UIs attend to changed: the chats shown are put together again (their lines, what is read).
    fn attended(&self) {
        for topic in self.store.live_topics() {
            if matches!(topic, Topic::Chat { .. }) {
                self.store.invalidate(&topic);
            }
        }
    }

    /// Gives this device's push registration (as kept) to the signed-in accounts that do not have it yet.
    async fn push_registered(&self) -> Result<Value> {
        let Some(mut kept) = self.host.storage_get(PUSH_KEY).await.ok().flatten().and_then(|b| serde_json::from_slice::<KeptPush>(&b).ok()) else {
            return Ok(Value::Null);
        };
        let accounts = self.accounts.list();
        kept.with.retain(|sub| accounts.iter().any(|a| &a.sub == sub));
        let mut failed = None;
        let missing: Vec<&AccountView> = accounts.iter().filter(|a| !kept.with.contains(&a.sub)).collect();
        for account in missing {
            match self.cloud.request(&account.sub, "POST", "/v1/push", Some(kept.registration.clone())).await {
                Ok(_) => kept.with.push(account.sub.clone()),
                Err(error) => failed = Some(error),
            }
        }
        let _ = self.host.storage_set(PUSH_KEY, serde_json::to_vec(&kept).unwrap_or_default()).await;
        match failed {
            Some(error) => Err(error),
            None => Ok(Value::Null),
        }
    }

    /// The accounts as UIs see them changed (a token refresh alone changes nothing here).
    fn accounts_changed(&self) {
        let list = self.accounts.list();
        if *self.shown_accounts.borrow() == list {
            return;
        }
        *self.shown_accounts.borrow_mut() = list;
        // Signed out: what only that account reached goes now, whether or not anything is shown.
        self.recompute_owners();
        self.forget_unreachable();
        self.store.set(&Topic::Accounts, self.accounts_value());
        self.sync_sockets();
        let core = self.me.clone();
        self.host.spawn(
            async move {
                if let Some(core) = core.upgrade() {
                    // Someone signed in: their devices hear pushes too.
                    let _ = core.push_registered().await;
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

    // ── still.fail cloud's events ──

    /// One socket per signed-in account while any account topic is live; none otherwise.
    fn sync_sockets(&self) {
        let wanted: Vec<String> = if self.live.borrow().is_empty() { Vec::new() } else { self.accounts.list().into_iter().map(|a| a.sub).collect() };
        let mut sockets = self.sockets.borrow_mut();
        sockets.retain(|sub, socket| {
            let keep = wanted.contains(sub);
            if !keep {
                socket.task.abort();
                self.status.socket_up(sub);
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
        Ok(self.host.websocket(url, vec![EVENTS_PROTOCOL.into(), format!("stillfail-token.{token}")]).await?)
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
        let waiting = this.status.begin(Place::Cloud, "连接", true);
        let opened = this.open_socket(&sub).await;
        drop(waiting);
        // Why it is down, if it is: said until it is open again (status.rs).
        let down: String;
        match opened {
            Ok(mut frames) => {
                let opened = this.host.now_ms();
                this.socket_state(&sub, SocketState::Open);
                this.status.socket_up(&sub);
                // Nothing is replayed: what changed while it was closed is read now.
                this.refresh_all().await;
                let host = this.host.clone();
                drop(this);
                let mut woke = false;
                // It answers pings (not a cloud from before them): from then on, silence is its end.
                let mut answers = false;
                let mut idle = false;
                // Another one being opened beside it, as the UI came back or the network changed: once it is open it
                // takes this one's place, so nothing waits to learn whether this one is gone.
                let mut beside: Option<LocalBoxFuture<'static, Result<crate::host::SocketFrames>>> = None;
                enum Ev {
                    Frame(Option<std::result::Result<String, crate::host::HostError>>),
                    Idle,
                    Suspect,
                    Beside(Result<crate::host::SocketFrames>),
                }
                loop {
                    let ev = {
                        let frame = frames.next().map(Ev::Frame);
                        let idle_after = async {
                            if answers {
                                host.sleep(SOCKET_IDLE_MS).await;
                                Ev::Idle
                            } else {
                                futures::future::pending().await
                            }
                        };
                        let other = match beside.as_mut() {
                            Some(opening) => opening.map(Ev::Beside).boxed_local(),
                            None => wake::woken_for(host.clone(), |w| w.suspects_connections()).map(|_| Ev::Suspect).boxed_local(),
                        };
                        futures::pin_mut!(frame, idle_after);
                        match futures::future::select(futures::future::select(frame, idle_after), other).await {
                            futures::future::Either::Left((futures::future::Either::Left((ev, _)), _)) => ev,
                            futures::future::Either::Left((futures::future::Either::Right((ev, _)), _)) => ev,
                            futures::future::Either::Right((ev, _)) => ev,
                        }
                    };
                    let Some(this) = core.upgrade() else { break };
                    match ev {
                        Ev::Frame(None) => break,
                        Ev::Frame(Some(Ok(text))) if text == "pong" => answers = true,
                        Ev::Frame(Some(Ok(text))) => this.on_cloud_event(&sub, &text),
                        Ev::Frame(Some(Err(error))) => {
                            woke = error.0 == wake::GONE || error.0 == wake::NETWORK;
                            break;
                        }
                        Ev::Idle => {
                            idle = true;
                            break;
                        }
                        Ev::Suspect => {
                            let (core, sub) = (core.clone(), sub.clone());
                            beside = Some(
                                async move {
                                    let this = core.upgrade().ok_or_else(gone)?;
                                    this.open_socket(&sub).await
                                }
                                .boxed_local(),
                            );
                        }
                        Ev::Beside(Ok(new)) => {
                            beside = None;
                            frames = new;
                            answers = false;
                            // The old one may have missed something before it went: read now.
                            this.refresh_all().await;
                        }
                        // Not opened: the old one stays (it is watched as before).
                        Ev::Beside(Err(_)) => beside = None,
                    }
                }
                drop(frames);
                let Some(this) = core.upgrade() else { return };
                // Held a while, or taken for gone when the UI came back (it was fine before): opened again soon.
                if woke || idle || this.host.now_ms() - opened >= 60_000.0 {
                    wait = SOCKET_RETRY_MS;
                }
                this.socket_state(&sub, SocketState::Retrying);
                down = if idle { "连接没有回应".into() } else { "连接断开了".into() };
                // Taken for gone as the UI came back, or silent: opened again at once.
                if woke || idle {
                    continue;
                }
            }
            Err(error) if error.code == "signed_out" => {
                this.sockets.borrow_mut().remove(&sub);
                this.status.socket_up(&sub);
                return;
            }
            Err(error) => {
                down = error.message;
                // Its first try failed: the topics are read anyway, so they show what can be shown.
                if this.socket_state(&sub, SocketState::Retrying) == Some(SocketState::Connecting) {
                    this.refresh_all().await;
                }
            }
        }
        let Some(this) = core.upgrade() else { return };
        this.status.socket_down(&sub, &down, this.host.now_ms() + wait as f64);
        let (sleep, woken) = (this.host.sleep(wait), this.host.woken());
        drop(this);
        // A UI back after being away wants it now: the wait starts over.
        match futures::future::select(sleep, woken).await {
            futures::future::Either::Left(_) => wait = (wait * 2).min(SOCKET_RETRY_MAX_MS),
            futures::future::Either::Right(_) => wait = SOCKET_RETRY_MS,
        }
    }
}

/// A path segment, percent-encoded like `encodeURIComponent`.
pub(crate) fn encode(segment: &str) -> String {
    let mut out = String::new();
    for byte in segment.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'!' | b'~' | b'*' | b'\'' | b'(' | b')' => out.push(byte as char),
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

/// Where a preview socket's messages from its page go (`preview.socket.send`).
type SocketInbox = futures::channel::mpsc::UnboundedSender<station::SocketFrame>;

/// A preview socket's open, or the page's close if that comes first: the open is then let go (an older station takes
/// the socket for a request and never answers). Whatever else the page sends meanwhile is `held` for once it is open.
async fn open_unless_closed<T>(opening: impl std::future::Future<Output = Result<T>>, from_page: &mut futures::channel::mpsc::UnboundedReceiver<station::SocketFrame>, held: &mut Vec<station::SocketFrame>) -> Result<std::result::Result<T, (u16, String)>> {
    let mut opening = std::pin::pin!(opening.fuse());
    loop {
        futures::select! {
            opened = opening => return opened.map(Ok),
            frame = from_page.next() => match frame {
                Some(station::SocketFrame::Close(code, reason)) => return Ok(Err((code, reason))),
                Some(frame) => held.push(frame),
                None => return opening.await.map(Ok),
            },
        }
    }
}

/// An entry of a map for as long as this is held: gone with it, however the call holding it ends (cancelled too).
struct Registered<K: std::hash::Hash + Eq, V> {
    map: Rc<RefCell<HashMap<K, V>>>,
    key: Option<K>,
}

impl<K: std::hash::Hash + Eq + Clone, V> Registered<K, V> {
    /// None when the key is taken already (it stays whose it was).
    fn new(map: Rc<RefCell<HashMap<K, V>>>, key: K, value: V) -> Option<Self> {
        if map.borrow().contains_key(&key) {
            return None;
        }
        map.borrow_mut().insert(key.clone(), value);
        Some(Registered { map, key: Some(key) })
    }
}

impl<K: std::hash::Hash + Eq, V> Drop for Registered<K, V> {
    fn drop(&mut self) {
        if let Some(key) = self.key.take() {
            self.map.borrow_mut().remove(&key);
        }
    }
}

/// A message as it goes to the station: with the app it is sent from, when the UI said.
fn outgoing(text: String, attachments: Value, quotes: Value, client: Option<String>) -> Value {
    let mut message = json!({ "text": text, "attachments": attachments, "quotes": quotes });
    if let Some(client) = client.filter(|c| !c.is_empty()) {
        message["client"] = json!(client);
    }
    message
}

fn answer(id: RequestId, result: Result<Value>) -> CoreMessage {
    match result {
        Ok(ok) => CoreMessage::Ok { id, ok },
        Err(error) => CoreMessage::Error { id, error },
    }
}

/// A call with its params checked; binary params are already decoded.
/// Where a call tells its UI how far it has got.
type Progress = Rc<dyn Fn(Value)>;

#[derive(Debug, PartialEq)]
enum Call {
    /// A client could not do something with what the core gave it (a view it cannot read, say): recorded as an error
    /// span, so it is seen with the rest of the trace, the same one at most once a minute.
    ClientError { source: String, message: String },
    /// A UI is back after `away` ms (a page hidden, a phone's app in the background): what went out before is
    /// suspect (wake.rs); `network`: the network changed, and all that is under way is. Its answer also tells the UI
    /// the core is alive.
    /// `retry` goes with `network` from a UI that asks to try again: a core from before `retry` takes it for the
    /// network changed, which also tries everything again.
    Wake { away: f64, network: bool, retry: bool },
    /// `device_name`: as the device is (`client.device`) when not given.
    AuthBegin { redirect_uri: String, return_to: String, device_name: Option<String> },
    AuthComplete { query: String },
    SignOut { account: String },
    /// Something to have done on a station or still.fail cloud, by its name (ops.rs): the UI never makes a request itself.
    Op(crate::ops::Request),
    /// A chat into the archive or back (`chat.archive`, an `Op`): one going in is hidden from the lists meanwhile.
    ChatArchive { op: crate::ops::Request, thread: Option<u64>, session: String, archived: bool },
    /// `client`: the app it is sent from ("android 0.1.1123"), for the station to tell its agent; older UIs give none.
    ChatSend { station: String, thread: u64, text: String, attachments: Value, quotes: Value, client: Option<String> },
    /// A new chat on a station (`POST /sessions` with `ask`): answered at once with the key it goes by here; the
    /// station makes it meanwhile (views.rs, `Pending`).
    ChatCreate { station: String, ask: Value },
    /// Sending, trying again, dropping in a chat by its key: one asked for here goes to its thread once made.
    ChatSendTo { station: String, session: String, text: String, attachments: Value, quotes: Value, client: Option<String> },
    ChatRetryIn { station: String, session: String, id: String },
    ChatDiscardIn { station: String, session: String, id: String },
    ChatRetry { station: String, thread: u64, id: String },
    ChatDiscard { station: String, thread: u64, id: String },
    ChatOlder { station: String, thread: u64 },
    HistoryOlder { station: String, key: String },
    ChatRead { station: String, thread: u64, seq: u64 },
    StationUpload { station: String, name: String, bytes: Vec<u8> },
    StationFile { station: String, key: String, name: String, thumb: bool, progress: bool },
    StationPreview { station: String, port: u16, method: String, path: String, headers: Vec<(String, String)>, body: Vec<u8>, stream: bool },
    /// `socket`: the name the UI gives it, for what it sends.
    PreviewSocket { station: String, port: u16, path: String, headers: Vec<(String, String)>, socket: String },
    /// A message (or the close) for the socket this client named `socket`.
    PreviewSocketSend { socket: String, frame: station::SocketFrame },
    Migrate { accounts: Option<Value>, device: Option<Vec<u8>> },
    /// still.fail cloud's VAPID key, for a browser to subscribe to pushes with (docs/notifications.md).
    PushKey,
    /// This device's push registration (`{kind: "web", endpoint, keys}` or `{kind: "fcm", token}`): given to every
    /// signed-in account, and to each signed in later.
    PushRegister { registration: Value },
    PushUnregister,
    /// What is written to a chat on this device, as it is now (`Topic::Draft`): nothing written forgets it.
    DraftPut { station: String, chat: String, draft: Value },
    /// Where a UI's attention is, notifications' settings, a notice taken to show (attend.rs).
    Attend(crate::attend::Call),
    /// What is written to a chat on this device, once (empty: nothing).
    DraftGet { station: String, chat: String },
    /// A chat picked to refer to from the composer (refs.rs): answers its mark, `{ mark }`, its link kept until sent.
    /// `base`: where the page's own links start (still.fail cloud when not given).
    ChatRef { station: String, id: String, title: String, base: Option<String> },
    /// Links of references kept by a client before the core kept them (title, link), the latest last.
    ChatRefsKeep { links: Vec<(String, String)> },
    /// What a chat runs on, chosen (choose.rs): `newChat.pick`, `newChat.create`, `newChat.migrate`, `pick.set`,
    /// `pick.save`.
    Choose { name: String, params: Value },
    /// How its person likes it on this device (`Topic::Prefs`, prefs.rs); `fill`: only what is not kept yet.
    PrefsSet { patch: Value, fill: bool },
    /// What the device is, as its host says once at start (prefs.rs).
    ClientDevice { facts: Value },
}

impl Call {
    /// Whether a UI can cancel it (`{id, cancel}`), and one gone does: the calls that hold something open for a page.
    fn cancellable(&self) -> bool {
        matches!(self, Call::StationPreview { stream: true, .. } | Call::PreviewSocket { .. })
    }

    /// The station a call is about, if any.
    fn station(&self) -> Option<&str> {
        match self {
            Call::Op(op) | Call::ChatArchive { op, .. } => match &op.target {
                crate::ops::Target::Station(station) => Some(station),
                crate::ops::Target::Cloud(_) => None,
            },
            Call::ChatSend { station, .. } | Call::ChatRetry { station, .. } | Call::ChatDiscard { station, .. } => Some(station),
            Call::ChatCreate { station, .. } | Call::ChatSendTo { station, .. } | Call::ChatRetryIn { station, .. } | Call::ChatDiscardIn { station, .. } => Some(station),
            Call::ChatOlder { station, .. } | Call::ChatRead { station, .. } | Call::StationUpload { station, .. } | Call::StationFile { station, .. } => Some(station),
            Call::StationPreview { station, .. } | Call::HistoryOlder { station, .. } | Call::PreviewSocket { station, .. } => Some(station),
            Call::AuthBegin { .. } | Call::AuthComplete { .. } | Call::SignOut { .. } | Call::Migrate { .. } | Call::ClientError { .. } | Call::Wake { .. } | Call::PreviewSocketSend { .. } => None,
            Call::PushKey | Call::PushRegister { .. } | Call::PushUnregister => None,
            Call::DraftPut { station, .. } | Call::DraftGet { station, .. } | Call::ChatRef { station, .. } => Some(station),
            Call::Attend(_) | Call::ChatRefsKeep { .. } => None,
            Call::Choose { params, .. } => params.get("station").and_then(Value::as_str),
            Call::PrefsSet { .. } | Call::ClientDevice { .. } => None,
        }
    }
}

fn parse_call(name: &str, params: Value) -> Result<Call> {
    if let Some(call) = crate::attend::parse(name, &params) {
        return call.map(Call::Attend);
    }
    #[derive(Deserialize)]
    struct Begin {
        redirect_uri: String,
        return_to: String,
        #[serde(default)]
        device_name: Option<String>,
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
    struct ClientErrorParams {
        source: String,
        message: String,
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
        #[serde(default)]
        client: Option<String>,
    }
    fn empty_list() -> Value {
        json!([])
    }
    #[derive(Deserialize)]
    struct SendTo {
        station: String,
        session: String,
        #[serde(default)]
        text: String,
        #[serde(default = "empty_list")]
        attachments: Value,
        #[serde(default = "empty_list")]
        quotes: Value,
        #[serde(default)]
        client: Option<String>,
    }
    #[derive(Deserialize)]
    struct OutgoingIn {
        station: String,
        session: String,
        id: String,
    }
    #[derive(Deserialize)]
    struct Create {
        station: String,
        runtime: String,
        #[serde(default)]
        model: Option<String>,
        #[serde(default)]
        effort: Option<String>,
        #[serde(default)]
        profile: Option<String>,
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
    struct Session {
        station: String,
        key: String,
    }
    #[derive(Deserialize)]
    struct Upload {
        station: String,
        name: String,
        bytes: String,
    }
    #[derive(Deserialize)]
    struct File {
        station: String,
        key: String,
        name: String,
        /// An image as a chat shows it: its thumbnail, where the station keeps one.
        #[serde(default)]
        thumb: bool,
        /// Tell the UI how far it has got as it comes (a big file).
        #[serde(default)]
        progress: bool,
    }
    #[derive(Deserialize)]
    struct Preview {
        station: String,
        port: u16,
        method: String,
        path: String,
        #[serde(default)]
        headers: Vec<(String, String)>,
        #[serde(default)]
        body: String,
        /// Hand the answer on as it comes (see `Inner::execute`).
        #[serde(default)]
        stream: bool,
    }
    #[derive(Deserialize)]
    struct Socket {
        station: String,
        port: u16,
        path: String,
        #[serde(default)]
        headers: Vec<(String, String)>,
        socket: String,
    }
    #[derive(Deserialize)]
    struct SocketSend {
        socket: String,
        text: Option<String>,
        binary: Option<String>,
        close: Option<(u16, String)>,
    }
    #[derive(Deserialize)]
    struct WakeParams {
        #[serde(default)]
        away: f64,
        #[serde(default)]
        network: bool,
        #[serde(default)]
        retry: bool,
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
        "client.error" => {
            let p = read::<ClientErrorParams>(params)?;
            Call::ClientError { source: p.source, message: p.message }
        }
        "client.wake" => {
            let params = read::<WakeParams>(params)?;
            Call::Wake { away: params.away, network: params.network, retry: params.retry }
        }
        "push.key" => Call::PushKey,
        "push.register" => {
            let registration = params_or_empty(params);
            let kind = registration.get("kind").and_then(Value::as_str);
            let text = |k: &str| registration.get(k).and_then(Value::as_str).is_some_and(|v| !v.is_empty());
            let keys = |k: &str| registration.get("keys").and_then(|keys| keys.get(k)).and_then(Value::as_str).is_some_and(|v| !v.is_empty());
            let ok = match kind {
                Some("web") => text("endpoint") && keys("p256dh") && keys("auth"),
                Some("fcm") => text("token"),
                _ => false,
            };
            if !ok {
                return Err(CoreError::invalid("要么是 {kind: \"web\", endpoint, keys: {p256dh, auth}}，要么是 {kind: \"fcm\", token}"));
            }
            Call::PushRegister { registration }
        }
        "push.unregister" => Call::PushUnregister,
        "chat.create" => {
            let p: Create = read(params)?;
            let mut ask = json!({ "runtime": p.runtime });
            for (name, value) in [("model", p.model), ("effort", p.effort), ("profile", p.profile)] {
                if let Some(value) = value.filter(|v| !v.is_empty()) {
                    ask[name] = json!(value);
                }
            }
            Call::ChatCreate { station: p.station, ask }
        }
        // By its key (`session`) rather than its thread: a chat asked for here, made or not.
        "chat.send" if params.get("session").is_some() && params.get("thread").is_none() => {
            let p: SendTo = read(params)?;
            Call::ChatSendTo { station: p.station, session: p.session, text: p.text, attachments: p.attachments, quotes: p.quotes, client: p.client }
        }
        "chat.retry" if params.get("session").is_some() && params.get("thread").is_none() => {
            let p: OutgoingIn = read(params)?;
            Call::ChatRetryIn { station: p.station, session: p.session, id: p.id }
        }
        "chat.discard" if params.get("session").is_some() && params.get("thread").is_none() => {
            let p: OutgoingIn = read(params)?;
            Call::ChatDiscardIn { station: p.station, session: p.session, id: p.id }
        }
        "chat.send" => {
            let p: Send = read(params)?;
            Call::ChatSend { station: p.station, thread: p.thread, text: p.text, attachments: p.attachments, quotes: p.quotes, client: p.client }
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
        "history.older" => {
            let p: Session = read(params)?;
            Call::HistoryOlder { station: p.station, key: p.key }
        }
        "chat.read" => {
            let p: Read = read(params)?;
            Call::ChatRead { station: p.station, thread: p.thread, seq: p.seq }
        }
        "newChat.pick" | "newChat.create" | "newChat.migrate" | "pick.set" | "pick.save" => {
            let params = params_or_empty(params);
            let needs: &[&str] = match name {
                "newChat.pick" => &["scope"],
                "newChat.create" => &["station"],
                "pick.set" | "pick.save" => &["station", "of"],
                _ => &[],
            };
            if let Some(field) = needs.iter().find(|f| params.get(**f).and_then(Value::as_str).is_none_or(str::is_empty)) {
                return Err(CoreError::invalid(format!("参数不对：缺少 {field}")));
            }
            Call::Choose { name: name.to_string(), params }
        }
        "draft.put" | "draft.get" => {
            let mut p = params_or_empty(params);
            // By the page's key for it (refs.rs, draft_at), or by its station and chat.
            let at = |field: &str| p.get(field).and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string);
            let (Some(station), Some(chat)) = at("key").and_then(|k| crate::refs::draft_at(&k)).map_or((at("station"), at("chat")), |(s, c)| (Some(s), Some(c))) else {
                return Err(CoreError::invalid("参数不对：要有 key，或 station 和 chat"));
            };
            if name == "draft.get" {
                return Ok(Call::DraftGet { station, chat });
            }
            if let Some(o) = p.as_object_mut() {
                o.remove("station");
                o.remove("chat");
                o.remove("key");
            }
            let draft = stillfail_shapes::conform::<stillfail_shapes::DraftView>(p).map_err(|e| CoreError::invalid(format!("参数不对：{e}")))?;
            Call::DraftPut { station, chat, draft }
        }
        "chat.ref" => {
            #[derive(Deserialize)]
            struct Ref {
                station: String,
                id: String,
                title: String,
                base: Option<String>,
            }
            let p: Ref = read(params)?;
            Call::ChatRef { station: p.station, id: p.id, title: p.title, base: p.base }
        }
        "chat.refs" => {
            #[derive(Deserialize)]
            struct Links {
                links: Vec<(String, String)>,
            }
            Call::ChatRefsKeep { links: read::<Links>(params)?.links }
        }
        "prefs.set" => {
            let mut p = params_or_empty(params);
            let fill = p.as_object_mut().and_then(|o| o.remove("fill")).and_then(|v| v.as_bool()).unwrap_or(false);
            Call::PrefsSet { patch: p, fill }
        }
        "client.device" => Call::ClientDevice { facts: params_or_empty(params) },
        "station.upload" => {
            let p: Upload = read(params)?;
            Call::StationUpload { bytes: base64(&p.bytes, "文件内容")?, station: p.station, name: p.name }
        }
        "station.file" => {
            let p: File = read(params)?;
            Call::StationFile { station: p.station, key: p.key, name: p.name, thumb: p.thumb, progress: p.progress }
        }
        "station.preview" => {
            let p: Preview = read(params)?;
            Call::StationPreview { body: base64(&p.body, "请求内容")?, station: p.station, port: p.port, method: p.method, path: p.path, headers: p.headers, stream: p.stream }
        }
        "preview.socket" => {
            let p: Socket = read(params)?;
            Call::PreviewSocket { station: p.station, port: p.port, path: p.path, headers: p.headers, socket: p.socket }
        }
        "preview.socket.send" => {
            let p: SocketSend = read(params)?;
            let frame = match (p.text, p.binary, p.close) {
                (Some(text), None, None) => station::SocketFrame::Text(text),
                (None, Some(bytes), None) => station::SocketFrame::Binary(base64(&bytes, "消息")?),
                (None, None, Some((code, reason))) => station::SocketFrame::Close(code, reason),
                _ => return Err(CoreError::invalid("text、binary、close 要给且只给一个")),
            };
            Call::PreviewSocketSend { socket: p.socket, frame }
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
        "chat.archive" => {
            let params = params_or_empty(params);
            let op = crate::ops::request(name, &params).expect("an op")?;
            let session = params.get("session").and_then(Value::as_str).unwrap_or("").to_string();
            Call::ChatArchive { op, thread: params.get("thread").and_then(Value::as_u64), session, archived: params.get("archived").and_then(Value::as_bool) == Some(true) }
        }
        _ => match crate::ops::request(name, &params_or_empty(params)) {
            Some(op) => Call::Op(op?),
            None => return Err(CoreError::new("unknown_call", format!("没有这个调用：{name}"))),
        },
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
        let call: ClientMessage = serde_json::from_value(json!({"id": 7, "call": "job.stop", "params": {"station": "ws1/st1", "id": "j1"}})).unwrap();
        assert_eq!(call, ClientMessage::Call { id: 7, call: "job.stop".into(), params: json!({"station": "ws1/st1", "id": "j1"}) });
        let bare: ClientMessage = serde_json::from_value(json!({"id": 1, "call": "auth.signOut"})).unwrap();
        assert_eq!(bare, ClientMessage::Call { id: 1, call: "auth.signOut".into(), params: Value::Null });
        let subscribe: ClientMessage = serde_json::from_value(json!({"id": 8, "subscribe": {"topic": "session", "station": "ws1/st1", "key": "k"}})).unwrap();
        let chats: ClientMessage = serde_json::from_value(json!({"id": 4, "subscribe": {"topic": "chats", "scope": "w", "mine": true}})).unwrap();
        assert_eq!(chats, ClientMessage::Subscribe { id: 4, subscribe: Topic::Chats { scope: "w".into(), mine: true } });
        let chats: ClientMessage = serde_json::from_value(json!({"id": 4, "subscribe": {"topic": "chats", "scope": "local"}})).unwrap();
        assert_eq!(chats, ClientMessage::Subscribe { id: 4, subscribe: Topic::Chats { scope: "local".into(), mine: false } });
        let chat: ClientMessage = serde_json::from_value(json!({"id": 5, "subscribe": {"topic": "chat", "station": "w/s", "thread": 7}})).unwrap();
        assert_eq!(chat, ClientMessage::Subscribe { id: 5, subscribe: Topic::Chat { station: "w/s".into(), thread: Some(7), session: None } });
        let agent: ClientMessage = serde_json::from_value(json!({"id": 6, "subscribe": {"topic": "chat", "station": "w/s", "session": "ds:C1:1.0"}})).unwrap();
        assert_eq!(agent, ClientMessage::Subscribe { id: 6, subscribe: Topic::Chat { station: "w/s".into(), thread: None, session: Some("ds:C1:1.0".into()) } });
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
            Call::AuthBegin { redirect_uri: "r".into(), return_to: "/".into(), device_name: Some("Mac".into()) }
        );
        assert_eq!(parse_call("auth.complete", json!({"query": "?code=c&state=s"})).unwrap(), Call::AuthComplete { query: "?code=c&state=s".into() });
        assert_eq!(parse_call("auth.signOut", json!({"account": "sub1"})).unwrap(), Call::SignOut { account: "sub1".into() });
        assert_eq!(
            parse_call("client.error", json!({"source": "android.decode", "message": "chat: 读不懂"})).unwrap(),
            Call::ClientError { source: "android.decode".into(), message: "chat: 读不懂".into() }
        );
        assert_eq!(
            parse_call("workspace.rename", json!({"account": "a", "workspace": "w", "name": "n"})).unwrap(),
            Call::Op(crate::ops::Request { target: crate::ops::Target::Cloud("a".into()), method: "PATCH", path: "/v1/workspaces/w".into(), body: Some(json!({"name": "n"})), fallback: None })
        );
        assert_eq!(
            parse_call("job.stop", json!({"station": "local", "id": "j1"})).unwrap(),
            Call::Op(crate::ops::Request { target: crate::ops::Target::Station("local".into()), method: "POST", path: "/jobs/j1/stop".into(), body: None, fallback: None })
        );
        // Requests by method and path are not the UIs' to make.
        assert_eq!(code(parse_call("station.request", json!({"station": "local", "method": "GET", "path": "/sessions"}))), "unknown_call");
        assert_eq!(code(parse_call("cloud.request", json!({"account": "a", "method": "GET", "path": "/v1/me"}))), "unknown_call");
        assert_eq!(
            parse_call("station.upload", json!({"station": "w/s", "name": "a.png", "bytes": "aGVsbG8="})).unwrap(),
            Call::StationUpload { station: "w/s".into(), name: "a.png".into(), bytes: b"hello".to_vec() }
        );
        assert_eq!(
            parse_call("station.file", json!({"station": "w/s", "key": "k", "name": "a.png"})).unwrap(),
            Call::StationFile { station: "w/s".into(), key: "k".into(), name: "a.png".into(), thumb: false, progress: false }
        );
        assert_eq!(
            parse_call("station.file", json!({"station": "w/s", "key": "k", "name": "a.png", "thumb": true})).unwrap(),
            Call::StationFile { station: "w/s".into(), key: "k".into(), name: "a.png".into(), thumb: true, progress: false }
        );
        assert_eq!(
            parse_call("station.file", json!({"station": "w/s", "key": "k", "name": "a.png", "progress": true})).unwrap(),
            Call::StationFile { station: "w/s".into(), key: "k".into(), name: "a.png".into(), thumb: false, progress: true }
        );
        assert_eq!(
            parse_call("chat.send", json!({"station": "w/s", "thread": 7, "text": "hi"})).unwrap(),
            Call::ChatSend { station: "w/s".into(), thread: 7, text: "hi".into(), attachments: json!([]), quotes: json!([]), client: None }
        );
        assert_eq!(
            parse_call("chat.send", json!({"station": "w/s", "thread": 7, "text": "hi", "client": "android 0.1.1123"})).unwrap(),
            Call::ChatSend { station: "w/s".into(), thread: 7, text: "hi".into(), attachments: json!([]), quotes: json!([]), client: Some("android 0.1.1123".into()) }
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
        assert_eq!(parse_call("history.older", json!({"station": "w/s", "key": "ember:c-1"})).unwrap(), Call::HistoryOlder { station: "w/s".into(), key: "ember:c-1".into() });
        assert_eq!(parse_call("chat.read", json!({"station": "w/s", "thread": 7, "seq": 12})).unwrap(), Call::ChatRead { station: "w/s".into(), thread: 7, seq: 12 });
        // A chat is a thread: a session key does not name one.
        assert_eq!(code(parse_call("chat.send", json!({"station": "w/s", "key": "k", "text": "hi"}))), "invalid_params");
        assert_eq!(
            parse_call("chat.create", json!({"station": "w/s", "runtime": "claude", "model": "opus", "effort": ""})).unwrap(),
            Call::ChatCreate { station: "w/s".into(), ask: json!({"runtime": "claude", "model": "opus"}) }
        );
        assert_eq!(
            parse_call("chat.send", json!({"station": "w/s", "session": "new:1-1", "text": "hi"})).unwrap(),
            Call::ChatSendTo { station: "w/s".into(), session: "new:1-1".into(), text: "hi".into(), attachments: json!([]), quotes: json!([]), client: None }
        );
        assert_eq!(parse_call("chat.retry", json!({"station": "w/s", "session": "k", "id": "out-1"})).unwrap(), Call::ChatRetryIn { station: "w/s".into(), session: "k".into(), id: "out-1".into() });
        assert_eq!(parse_call("chat.discard", json!({"station": "w/s", "session": "k", "id": "out-1"})).unwrap(), Call::ChatDiscardIn { station: "w/s".into(), session: "k".into(), id: "out-1".into() });
    }

    #[test]
    fn checks_params() {
        let missing = parse_call("auth.begin", json!({"redirect_uri": "r"})).unwrap_err();
        assert_eq!(missing.code, "invalid_params");
        assert!(missing.message.contains("return_to"), "{}", missing.message);
        assert_eq!(code(parse_call("auth.signOut", Value::Null)), "invalid_params");
        assert_eq!(code(parse_call("workspace.rename", json!({"account": "a", "name": "n"}))), "invalid_params");
        assert_eq!(code(parse_call("station.upload", json!({"station": "w/s", "name": "n", "bytes": "not base64!"}))), "invalid_params");
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

    // ── still.fail cloud's events ──

    use crate::accounts::{STORAGE_KEY, StoredAccount};
    use crate::testing::{FakeHost, json_response, run};

    /// Timers this many times faster: eviction in 0.6 s, a socket's first retry in 10 ms.
    const SPEEDUP: u64 = 100;

    fn now_s() -> f64 {
        std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64()
    }

    /// A core with one signed-in account whose token expires in 30 s (so every socket opens with a fresh one),
    /// still.fail cloud answering `/v1/me`, the workspace and token refreshes.
    async fn cloud_core() -> (Rc<FakeHost>, Core) {
        let host = FakeHost::new();
        host.speed_up(SPEEDUP);
        let account = StoredAccount { sub: "s1".into(), email: "a@x.com".into(), name: "阿一".into(), picture: String::new(), access: "stale".into(), refresh: "r0".into(), access_expires: now_s() + 30.0 };
        host.store(STORAGE_KEY, serde_json::to_vec(&vec![account]).unwrap());
        let refreshes = Cell::new(0);
        host.on_fetch(move |req| {
            let path = req.url.trim_start_matches("https://stillfail.test");
            match path {
                "/v1/me" => json_response(200, json!({"workspaces": [{"id": "ws", "name": "W"}], "invitations": [], "relay_url": "https://relay.test"})),
                "/v1/workspaces/ws" => json_response(200, json!({"id": "ws", "stations": [{"id": "st", "name": "studio", "online": false, "last_seen": 1}]})),
                "/v1/auth/sessions" => json_response(200, json!({"sessions": [{"id": "d1", "current": true}]})),
                "/v1/auth/sessions/d2" => json_response(200, json!({"ok": true})),
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

    #[test]
    fn a_kept_credential_reaches_the_stations_without_ember_cloud() {
        run(async {
            let host = FakeHost::new();
            let account = StoredAccount { sub: "s1".into(), email: "a@x.com".into(), name: "阿一".into(), picture: String::new(), access: "a".into(), refresh: "r".into(), access_expires: now_s() + 3600.0 };
            host.store(STORAGE_KEY, serde_json::to_vec(&vec![account]).unwrap());
            let up = Rc::new(Cell::new(true));
            let asked = Rc::new(Cell::new(0));
            let (cloud_up, times) = (up.clone(), asked.clone());
            host.on_fetch(move |req| {
                let path = req.url.trim_start_matches("https://stillfail.test");
                if !cloud_up.get() {
                    return Err(crate::host::HostError("offline".into()));
                }
                match path {
                    "/v1/me" => json_response(200, json!({"workspaces": [{"id": "ws", "name": "W"}], "invitations": [], "relay_url": "https://relay.test"})),
                    "/v1/workspaces/ws/credential" => {
                        times.set(times.get() + 1);
                        json_response(200, json!({"credential": format!("c{}", times.get()), "issued_at": now_s(), "expires_at": now_s() + 30.0 * 86400.0, "relay_url": "https://relay.test"}))
                    }
                    _ => json_response(404, json!({"error": "not_found"})),
                }
            });
            let core = Core::new(host.clone()).await;
            let inner = core.inner.clone();
            let credential = |fresh| { let inner = inner.clone(); async move { inner.credential("ws", "dev", fresh).await } };
            let kept = |c: &Credential| KeptCredential { device: "dev".into(), credential: c.clone() };
            // Asked for once, then kept for the day.
            assert_eq!(credential(false).await.unwrap().credential, "c1");
            assert_eq!(credential(false).await.unwrap().credential, "c1");
            assert_eq!(asked.get(), 1);
            // A station refused it: a new one.
            assert_eq!(credential(true).await.unwrap().credential, "c2");
            // A day old, with still.fail cloud unreachable: the kept one serves on.
            let old = Credential { credential: "old".into(), issued_at: now_s() - 2.0 * 86400.0, expires_at: now_s() + 28.0 * 86400.0, relay_url: "https://relay.test".into() };
            host.store(&format!("{CREDENTIAL_KEY}/s1/ws"), serde_json::to_vec(&kept(&old)).unwrap());
            up.set(false);
            assert_eq!(credential(false).await.unwrap().credential, "old");
            // Refused, or run out, and no still.fail cloud: none.
            assert!(credential(true).await.is_err());
            let spent = Credential { expires_at: now_s() - 1.0, ..old.clone() };
            host.store(&format!("{CREDENTIAL_KEY}/s1/ws"), serde_json::to_vec(&kept(&spent)).unwrap());
            assert!(credential(false).await.is_err());
            // A day old, still.fail cloud back: a new one.
            host.store(&format!("{CREDENTIAL_KEY}/s1/ws"), serde_json::to_vec(&kept(&old)).unwrap());
            up.set(true);
            assert_eq!(credential(false).await.unwrap().credential, "c3");
            // One for another device key (the page's taken over): a new one.
            host.store(&format!("{CREDENTIAL_KEY}/s1/ws"), serde_json::to_vec(&KeptCredential { device: "other".into(), credential: old.clone() }).unwrap());
            assert_eq!(credential(false).await.unwrap().credential, "c4");
            // Signed out: it goes.
            inner.accounts.sign_out("s1").await.unwrap();
            pass(10).await;
            assert_eq!(host.stored(&format!("{CREDENTIAL_KEY}/s1/ws")), None);
        });
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
    fn an_accounts_devices_are_a_topic_read_again_after_a_write() {
        run(async {
            let (host, core) = cloud_core().await;
            let ui = core.connect();
            let mut values = HashMap::new();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::LoginSessions { account: "s1".into() } });
            host.settle().await;
            apply(&host, &mut values);
            assert_eq!(values[&1], json!([{"id": "d1", "current": true}]));
            let before = count(&host, "/v1/auth/sessions");
            // Signing a device out, through the core: the list is read again, nobody asks for it.
            core.receive(ui, ClientMessage::Call { id: 2, call: "loginSession.revoke".into(), params: json!({"account": "s1", "id": "d2"}) });
            host.settle().await;
            assert_eq!(count(&host, "/v1/auth/sessions"), before + 1);
        });
    }

    #[test]
    fn what_was_known_shows_after_a_restart_with_no_network() {
        run(async {
            let (host, core) = cloud_core().await;
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspaces });
            core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: Topic::Workspace { workspace: "ws".into() } });
            host.settle().await;
            drop(core);
            host.take_emitted();
            // Started again, offline.
            host.on_fetch(|_| json_response(503, json!({"error": "unavailable"})));
            let core = Core::new(host.clone()).await;
            let ui = core.connect();
            let mut values = HashMap::new();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspaces });
            core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: Topic::Workspace { workspace: "ws".into() } });
            core.receive(ui, ClientMessage::Subscribe { id: 3, subscribe: Topic::Chats { scope: "ws".into(), mine: false } });
            host.settle().await;
            apply(&host, &mut values);
            assert_eq!(values[&1][0]["workspaces"][0]["id"], "ws");
            // Kept, not confirmed: a UI does not take it for "no workspace yet".
            assert_eq!(values[&1][0]["loaded"], false);
            assert_eq!(values[&2]["stations"][0]["id"], "st");
            // Whose workspace it is is known from what was kept, before any answer.
            assert_eq!(values[&3]["me"]["email"], "a@x.com");
        });
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
            assert_eq!(sockets, vec![("wss://stillfail.test/v1/events".to_string(), vec!["stillfail-events".to_string(), "stillfail-token.fresh-1".to_string()])]);
            // Read once, when the socket opened.
            assert_eq!((count(&host, "/v1/me"), count(&host, "/v1/workspaces/ws")), (1, 1));
            apply(&host, &mut values);
            assert_eq!(values[&1][0]["workspaces"][0]["id"], "ws");
            assert_eq!(values[&1][0]["loaded"], true);
            assert_eq!(values[&2]["stations"][0]["id"], "st");
            pass(crate::store::EVICT_AFTER_MS * 5 / 4).await;
            assert_eq!(host.open_sockets("/v1/events"), 1);
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
            // 1 s, 2 s, 4 s: waits double (among the station's own retries, which go on beside it).
            let waits: Vec<u64> = host.sleeps.borrow().clone();
            let mut doubling = [1_000u64, 2_000, 4_000].into_iter().peekable();
            for wait in &waits {
                if doubling.peek() == Some(wait) {
                    doubling.next();
                }
            }
            assert!(doubling.peek().is_none(), "{waits:?}");
            assert_eq!(count(&host, "/v1/me"), 1, "failed retries read nothing");
            host.refuse_sockets.set(false);
            pass(SOCKET_RETRY_MS * 10).await;
            host.settle().await;
            assert_eq!(host.open_sockets("/v1/events"), 1);
            assert_eq!(count(&host, "/v1/me"), 2, "read again once it opened");
        });
    }

    #[test]
    fn back_after_being_away_a_socket_waiting_to_retry_tries_at_once() {
        run(async {
            let (host, core) = cloud_core().await;
            host.refuse_sockets.set(true);
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspaces });
            host.settle().await;
            // Refused for a while: the next try is 32 s away.
            pass(SOCKET_RETRY_MS * 40).await;
            host.refuse_sockets.set(false);
            assert_eq!(host.open_sockets("/v1/events"), 0);
            host.take_emitted();
            core.receive(ui, ClientMessage::Call { id: 9, call: "client.wake".into(), params: json!({ "away": 60_000 }) });
            pass(0).await;
            assert_eq!(host.open_sockets("/v1/events"), 1);
            // Answered, so the page knows the core is there.
            assert!(host.take_emitted().iter().any(|(_, m)| *m == CoreMessage::Ok { id: 9, ok: json!({}) }));
        });
    }

    #[test]
    fn a_socket_that_answered_pings_and_went_silent_is_opened_again() {
        run(async {
            let (host, core) = cloud_core().await;
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspaces });
            host.settle().await;
            let opened = host.sockets.borrow().len();
            assert_eq!(host.open_sockets("/v1/events"), 1);
            // Never a pong (a cloud from before them): silence is how it is.
            pass(SOCKET_IDLE_MS * 2).await;
            assert_eq!(host.sockets.borrow().len(), opened);
            host.socket_send("/v1/events", "pong");
            pass(SOCKET_IDLE_MS / 2).await;
            assert_eq!(host.sockets.borrow().len(), opened, "answered a while ago: still there");
            pass(SOCKET_IDLE_MS).await;
            assert_eq!(host.sockets.borrow().len(), opened + 1, "silent past its pings: opened again");
            assert_eq!(host.open_sockets("/v1/events"), 1);
        });
    }

    #[test]
    fn the_network_changing_opens_the_socket_again_at_once() {
        run(async {
            let (host, core) = cloud_core().await;
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Workspaces });
            host.settle().await;
            let opened = host.sockets.borrow().len();
            host.socket_send("/v1/events", "pong");
            pass(0).await;
            core.receive(ui, ClientMessage::Call { id: 9, call: "client.wake".into(), params: json!({ "away": 0, "network": true }) });
            pass(0).await;
            assert_eq!(host.sockets.borrow().len(), opened + 1);
            assert_eq!(host.open_sockets("/v1/events"), 1);
            assert_eq!(host.resets.get(), 1, "the host let its connections go");
        });
    }

    /// A core signed in as one account, on a station's own page (`local`, plain HTTP), whose admin API has chat 7
    /// with one agent; `sample` of its traces recorded. Its timers run at their real pace.
    /// A session as the station lists it.
    fn session(key: &str) -> Value {
        json!({
            "key": key, "connect": "ember", "scope": "thread", "title": null, "createdBy": null, "boundTo": [], "creator": null,
            "participants": [], "runtime": "claude", "profile": "p1", "profilePinned": false, "model": null, "effort": null,
            "runtimeSessionId": null, "workspace": "/w", "running": false, "createdAt": 1, "lastActiveAt": 1, "archivedAt": null,
            "process": "cold", "turns": 0, "pending": 0, "firstText": null, "lastTurn": null,
        })
    }

    async fn local_core(sample: f64) -> (Rc<FakeHost>, Core) {
        let host = FakeHost::new();
        let account = StoredAccount { sub: "s1".into(), email: "a@x.com".into(), name: String::new(), picture: String::new(), access: "tok".into(), refresh: "r0".into(), access_expires: now_s() + 3600.0 };
        host.store(STORAGE_KEY, serde_json::to_vec(&vec![account]).unwrap());
        host.on_fetch(|req| {
            let path = req.url.trim_start_matches("https://stillfail.test");
            match path.split('?').next().unwrap() {
                "/admin/api/threads" => json_response(200, json!([{
                    "id": 7, "surface": "ember", "channel": "EMBER", "channelName": null, "threadTs": "7.0", "title": null, "createdBy": null,
                    "creator": null, "createdAt": 1, "sessions": [{ "thread": 7, "session": "k1", "connect": "ember", "joinedAt": 1 }],
                    "last": 0, "lastMessage": null, "read": 0, "unread": 0, "people": [], "firstText": null,
                }])),
                "/admin/api/threads/7/entries" => json_response(200, json!({ "last": 0, "entries": [] })),
                "/admin/api/sessions" => json_response(200, json!([session("k1")])),
                "/admin/api/sessions/k1" => json_response(200, json!({ "session": session("k1"), "threads": [], "turns": [] })),
                "/admin/api/overview" => json_response(200, json!({
                    "viewer": { "via": "local" }, "connects": [], "profiles": [], "processes": [], "counts": { "sessions": 1, "running": 0, "warm": 0 },
                    "mesh": null, "slackUsers": [], "slackTeams": [], "slackApps": [], "disk": null, "logins": [],
                })),
                "/admin/api/memory" => json_response(200, json!({ "global": "" })),
                "/v1/telemetry/traces" => json_response(202, json!({})),
                _ => json_response(404, json!({})),
            }
        });
        host.on_fetch_stream(|_| Ok(crate::host::StreamResponse { status: 200, headers: vec![], body: futures::stream::pending().boxed_local() }));
        let core = Core::traced(host.clone(), sample).await;
        (host, core)
    }

    fn header(request: &crate::host::HttpRequest, name: &str) -> Option<String> {
        request.headers.iter().find(|(k, _)| k == name).map(|(_, v)| v.clone())
    }

    fn exports(host: &FakeHost) -> Vec<crate::host::HttpRequest> {
        host.requests.borrow().iter().filter(|r| r.url.ends_with("/v1/telemetry/traces")).cloned().collect()
    }

    #[test]
    fn a_streamed_preview_hands_its_answer_on_as_it_comes_until_cancelled_or_its_page_goes() {
        run(async {
            let (host, core) = local_core(0.0).await;
            // The service's answer: open, its body coming as it is sent here.
            type Body = futures::channel::mpsc::UnboundedSender<std::result::Result<Vec<u8>, crate::host::HostError>>;
            let bodies: Rc<RefCell<Vec<Body>>> = Rc::default();
            let opened = bodies.clone();
            host.on_fetch_stream(move |_| {
                let (tx, rx) = futures::channel::mpsc::unbounded();
                opened.borrow_mut().push(tx);
                Ok(crate::host::StreamResponse { status: 200, headers: vec![("content-type".into(), "text/event-stream".into())], body: rx.boxed_local() })
            });
            let ui = core.connect();
            let preview = |id| ClientMessage::Call { id, call: "station.preview".into(), params: json!({ "station": "local", "port": 5180, "method": "GET", "path": "/events", "stream": true }) };
            core.receive(ui, preview(1));
            host.settle().await;
            let asked = host.requests.borrow().last().cloned().unwrap();
            assert_eq!(asked.url, "https://stillfail.test/admin/api/preview/5180/events");
            // Under the old name: a station from before the rename strips x-ember-* only, so the service never sees it.
            assert_eq!(header(&asked, "x-ember-stream").as_deref(), Some("1"), "asked for as it comes");
            assert_eq!(header(&asked, "x-stillfail-stream"), None);
            let values = |host: &FakeHost| host.take_emitted().into_iter().map(|(_, m)| serde_json::to_value(m).unwrap()).collect::<Vec<_>>();
            assert_eq!(values(&host), vec![json!({ "id": 1, "value": { "head": { "status": 200, "headers": [["content-type", "text/event-stream"]] } } })]);
            // Nothing is said to be waited on once its head came, however long its body goes on.
            core.inner.status.skip(3_000.0);
            assert_eq!(core.inner.status.value()["state"], Value::Null);
            bodies.borrow()[0].unbounded_send(Ok(b"data: 1\n\n".to_vec())).unwrap();
            host.settle().await;
            assert_eq!(values(&host), vec![json!({ "id": 1, "value": { "chunk": BASE64.encode(b"data: 1\n\n") } })]);
            // Cancelled: it answers so, and the body is let go (the station stops asking the service).
            core.receive(ui, ClientMessage::Cancel { id: 1, cancel: true });
            host.settle().await;
            assert_eq!(values(&host), vec![json!({ "id": 1, "error": { "code": "cancelled", "message": "已取消" } })]);
            assert!(bodies.borrow()[0].is_closed());
            // A page gone takes its calls with it.
            core.receive(ui, preview(2));
            host.settle().await;
            core.disconnect(ui);
            host.settle().await;
            assert!(bodies.borrow()[1].is_closed());
            assert!(core.inner.calls.borrow().is_empty());
            // Any other call runs to its end, cancelled or not: a write is not dropped halfway.
            let ui = core.connect();
            core.receive(ui, ClientMessage::Call { id: 3, call: "memory.get".into(), params: json!({ "station": "local" }) });
            core.receive(ui, ClientMessage::Cancel { id: 3, cancel: true });
            core.disconnect(ui);
            host.settle().await;
            assert!(values(&host).iter().any(|v| v["id"] == 3 && v.get("ok").is_some()), "answered, not cancelled");
        });
    }

    #[test]
    fn a_preview_socket_is_only_carried_by_the_mesh_and_its_messages_are_checked() {
        run(async {
            let (host, core) = local_core(0.0).await;
            let ui = core.connect();
            core.receive(ui, ClientMessage::Call { id: 1, call: "preview.socket".into(), params: json!({ "station": "local", "port": 5180, "path": "/", "socket": "s1" }) });
            core.receive(ui, ClientMessage::Call { id: 2, call: "preview.socket.send".into(), params: json!({ "socket": "s1", "text": "hi" }) });
            host.settle().await;
            let answers: HashMap<u64, Value> = host.take_emitted().into_iter().map(|(_, m)| serde_json::to_value(m).unwrap()).map(|v| (v["id"].as_u64().unwrap(), v)).collect();
            assert_eq!(answers[&1]["error"]["code"], "unsupported");
            assert_eq!(answers[&2]["error"]["code"], "not_found", "no socket open by that name");
            assert!(parse_call("preview.socket.send", json!({ "socket": "s1", "text": "a", "close": [1000, ""] })).is_err());
            assert_eq!(parse_call("preview.socket.send", json!({ "socket": "s1", "close": [4001, "done"] })).unwrap(), Call::PreviewSocketSend { socket: "s1".into(), frame: station::SocketFrame::Close(4001, "done".into()) });
            assert_eq!(parse_call("preview.socket.send", json!({ "socket": "s1", "binary": BASE64.encode([0, 1]) })).unwrap(), Call::PreviewSocketSend { socket: "s1".into(), frame: station::SocketFrame::Binary(vec![0, 1]) });
        });
    }

    #[test]
    fn a_preview_socket_closed_before_it_opens_does_not_wait_for_the_station() {
        run(async {
            let (tx, mut from_page) = futures::channel::mpsc::unbounded();
            let mut held = Vec::new();
            tx.unbounded_send(station::SocketFrame::Text("early".into())).unwrap();
            tx.unbounded_send(station::SocketFrame::Close(1001, "gone".into())).unwrap();
            // A station that never answers: the page's close ends it.
            let opened = open_unless_closed(futures::future::pending::<Result<()>>(), &mut from_page, &mut held).await.unwrap();
            assert_eq!(opened, Err((1001, "gone".to_string())));
            assert_eq!(held, vec![station::SocketFrame::Text("early".into())], "what came before is kept");
            // Open first: the open.
            assert_eq!(open_unless_closed(async { Ok(7) }, &mut from_page, &mut held).await.unwrap(), Ok(7));
        });
    }

    #[test]
    fn a_chat_opening_is_one_trace_its_requests_carry_and_ember_cloud_gets() {
        run(async {
            let (host, core) = local_core(1.0).await;
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Chat { station: "local".into(), thread: Some(7), session: None } });
            host.settle().await;
            assert!(host.take_emitted().iter().any(|(_, m)| matches!(m, CoreMessage::Value { id: 1, .. })));
            let admin: Vec<_> = host.requests.borrow().iter().filter(|r| r.url.contains("/admin/api/")).cloned().collect();
            let paths: Vec<&str> = admin.iter().map(|r| r.url.trim_start_matches("https://stillfail.test/admin/api")).collect();
            assert_eq!(paths.len(), 7, "{paths:?}");
            assert!(paths.contains(&"/chats"), "the title as the sidebar has it: {paths:?}");
            assert!(paths.contains(&"/sessions/k1"), "the agent read as the chat opens: {paths:?}");
            let parents: Vec<String> = admin.iter().map(|r| header(r, "traceparent").expect("traceparent")).collect();
            let trace = parents[0][3..35].to_string();
            assert!(parents.iter().all(|p| p[3..35] == trace && p.ends_with("-01")), "{parents:?}");
            // Spans wait to go out together.
            assert!(exports(&host).is_empty());

            pass(SPEEDUP * (trace::EXPORT_MS + 100)).await;
            let sent = exports(&host);
            assert_eq!(sent.len(), 1);
            assert_eq!(header(&sent[0], "authorization").as_deref(), Some("Bearer tok"));
            assert_eq!(header(&sent[0], "traceparent"), None, "sending spans is no trace");
            let body: Value = serde_json::from_slice(sent[0].body.as_deref().unwrap()).unwrap();
            let spans = body["resourceSpans"][0]["scopeSpans"][0]["spans"].as_array().unwrap().clone();
            let named = |name: &str| spans.iter().find(|s| s["name"] == name).unwrap_or_else(|| panic!("no {name}: {spans:?}")).clone();
            let root = named("chat.open");
            assert_eq!(root["traceId"], trace.as_str());
            assert!(root.get("parentSpanId").is_none());
            let threads = named("GET /admin/api/threads");
            assert_eq!(threads["parentSpanId"], root["spanId"]);
            assert!(parents.iter().any(|p| p[36..52] == *threads["spanId"].as_str().unwrap()), "the request carries its own span");
            assert_eq!(named("GET /admin/api/sessions/:id")["parentSpanId"], root["spanId"]);
            let connect = named("station.connect");
            assert_eq!(connect["parentSpanId"], root["spanId"]);
            assert_eq!(named("GET /admin/api/events")["parentSpanId"], connect["spanId"]);
            assert!(spans.iter().all(|s| s["traceId"] == trace.as_str()));
            let text = serde_json::to_string(&spans).unwrap();
            assert!(!text.contains("a@x.com") && !text.contains("tok"), "{text}");

            // Nothing new: nothing more is sent.
            pass(SPEEDUP * (trace::EXPORT_MS + 100)).await;
            assert_eq!(exports(&host).len(), 1);
        });
    }

    #[test]
    fn calls_are_traces_and_nothing_goes_out_when_tracing_is_off() {
        run(async {
            let (host, core) = local_core(1.0).await;
            let ui = core.connect();
            core.receive(ui, ClientMessage::Call { id: 1, call: "memory.get".into(), params: json!({ "station": "local" }) });
            host.settle().await;
            pass(SPEEDUP * (trace::EXPORT_MS + 100)).await;
            let body: Value = serde_json::from_slice(exports(&host)[0].body.as_deref().unwrap()).unwrap();
            let names: Vec<String> = body["resourceSpans"][0]["scopeSpans"][0]["spans"].as_array().unwrap().iter().map(|s| s["name"].as_str().unwrap().to_string()).collect();
            assert_eq!(names, ["GET /admin/api/memory", "memory.get"]);

            let (host, core) = local_core(0.0).await;
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Chat { station: "local".into(), thread: Some(7), session: None } });
            core.receive(ui, ClientMessage::Call { id: 2, call: "memory.get".into(), params: json!({ "station": "local" }) });
            host.settle().await;
            pass(SPEEDUP * (trace::EXPORT_MS + 100)).await;
            assert!(exports(&host).is_empty());
            // Stations still hear that these are not recorded.
            let parents: Vec<String> = host.requests.borrow().iter().filter_map(|r| header(r, "traceparent")).collect();
            assert!(!parents.is_empty() && parents.iter().all(|p| p.ends_with("-00")), "{parents:?}");
        });
    }

    #[test]
    fn prefs_are_kept_on_the_device_and_moved_in_once_without_writing_over() {
        run(async {
            let (host, core) = local_core(0.0).await;
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Prefs });
            host.settle().await;
            let mut values = HashMap::new();
            apply(&host, &mut values);
            // Nothing chosen: the defaults.
            assert_eq!((values[&1]["onlyMine"].clone(), values[&1]["appearance"].clone(), values[&1]["rowPicture"].clone()), (json!(false), json!("system"), json!("auto")));
            assert_eq!(values[&1]["device"]["app"], "");
            let set = |id, params: Value| core.receive(ui, ClientMessage::Call { id, call: "prefs.set".into(), params });
            set(2, json!({ "onlyMine": true, "appearance": "dark", "lastChat": { "local": "/chats/k1", "ws": "/w/ws/new" }, "chatTabs": { "local:t": { "tabs": ["k1"], "active": "k1" } } }));
            host.settle().await;
            apply(&host, &mut values);
            assert_eq!((values[&1]["onlyMine"].clone(), values[&1]["appearance"].clone()), (json!(true), json!("dark")));
            assert_eq!(values[&1]["chatTabs"]["local:t"], json!({ "tabs": ["k1"], "active": "k1" }));
            // A map by entry: one gone, the other kept.
            set(3, json!({ "lastChat": { "ws": null } }));
            // What a device kept before, moved in: only what is not chosen here yet.
            set(4, json!({ "fill": true, "appearance": "light", "rowPicture": "people", "lastChat": { "local": "/chats/old", "other": "/w/other/new" } }));
            host.settle().await;
            apply(&host, &mut values);
            assert_eq!((values[&1]["appearance"].clone(), values[&1]["rowPicture"].clone()), (json!("dark"), json!("people")));
            assert_eq!(values[&1]["lastChat"], json!({ "local": "/chats/k1", "other": "/w/other/new" }));
            // Not a pref, or not one of its words: refused, nothing changed.
            set(5, json!({ "appearance": "blue" }));
            set(6, json!({ "device": { "app": "web" } }));
            host.settle().await;
            let refused = host.take_emitted().into_iter().filter(|(_, m)| matches!(m, CoreMessage::Error { id: 5 | 6, .. })).count();
            assert_eq!(refused, 2);
            // The invite code a page came with, kept through signing in until a workspace is made.
            set(7, json!({ "invite": "ABCD-EFGH" }));
            host.settle().await;
            apply(&host, &mut values);
            assert_eq!(values[&1]["invite"], "ABCD-EFGH");
            crate::prefs::invite_used(&core.inner.data);
            host.settle().await;
            apply(&host, &mut values);
            assert_eq!(values[&1].get("invite"), None);
            // Kept across a restart.
            drop(core);
            let core = Core::new(host.clone()).await;
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Prefs });
            host.settle().await;
            let mut values = HashMap::new();
            apply(&host, &mut values);
            assert_eq!((values[&1]["onlyMine"].clone(), values[&1]["appearance"].clone(), values[&1]["lastChat"]["local"].clone()), (json!(true), json!("dark"), json!("/chats/k1")));
            // The tabs of the latest 200 chats are kept.
            for i in 0..205u64 {
                core.receive(ui, ClientMessage::Call { id: 10 + i, call: "prefs.set".into(), params: json!({ "chatTabs": { format!("local:{i}"): { "tabs": [], "active": null } } }) });
                host.settle().await;
            }
            apply(&host, &mut values);
            let tabs = values[&1]["chatTabs"].as_object().unwrap();
            assert_eq!(tabs.len(), 200);
            assert!(tabs.contains_key("local:204") && !tabs.contains_key("local:4") && !tabs.contains_key("local:t"));
        });
    }

    #[test]
    fn the_device_says_what_it_is_once_and_the_core_decides_what_follows() {
        run(async {
            let (host, core) = local_core(0.0).await;
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Prefs });
            let phone = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
            core.receive(ui, ClientMessage::Call { id: 2, call: "client.device".into(), params: json!({ "app": "web", "build": "0.1.9", "userAgent": phone }) });
            host.settle().await;
            let mut values = HashMap::new();
            apply(&host, &mut values);
            assert_eq!(values[&1]["device"], json!({ "app": "web", "phone": true, "handoff": false }));
            // A message goes with the app it is sent from, unless the UI says.
            core.receive(ui, ClientMessage::Call { id: 3, call: "chat.send".into(), params: json!({ "station": "local", "thread": 7, "text": "hi" }) });
            host.settle().await;
            let sent: Vec<Value> = host.requests.borrow().iter().filter(|r| r.method == "POST" && r.url.ends_with("/threads/7/messages"))
                .map(|r| serde_json::from_slice(r.body.as_deref().unwrap_or_default()).unwrap()).collect();
            assert_eq!(sent[0]["client"], "web 0.1.9 (phone)");
            // A computer's browser: its links are offered to the desktop app first; it signs in by its browser's name.
            let mac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36";
            core.receive(ui, ClientMessage::Call { id: 4, call: "client.device".into(), params: json!({ "app": "web", "userAgent": mac }) });
            core.receive(ui, ClientMessage::Call { id: 5, call: "auth.begin".into(), params: json!({ "redirect_uri": "r", "return_to": "/" }) });
            core.receive(ui, ClientMessage::Call { id: 6, call: "client.device".into(), params: json!({ "app": "phone" }) });
            host.settle().await;
            let emitted = host.take_emitted();
            let url = emitted.iter().find_map(|(_, m)| match m { CoreMessage::Ok { id: 5, ok } => ok["url"].as_str().map(str::to_string), _ => None }).unwrap();
            assert!(url.contains(&format!("name={}", encode("still.fail 网页版 · Chrome · macOS"))), "{url}");
            assert!(emitted.iter().any(|(_, m)| matches!(m, CoreMessage::Error { id: 6, .. })));
            core.receive(ui, ClientMessage::Unsubscribe { id: 1, unsubscribe: true });
            core.receive(ui, ClientMessage::Subscribe { id: 7, subscribe: Topic::Prefs });
            host.settle().await;
            let mut values = HashMap::new();
            apply(&host, &mut values);
            assert_eq!(values[&7]["device"], json!({ "app": "web", "phone": false, "handoff": true }));
        });
    }

    #[test]
    fn the_rows_are_led_by_the_setting_or_by_how_many_people_there_are() {
        assert_eq!(crate::prefs::leading(None, None), "agents");
        assert_eq!(crate::prefs::leading(Some(&json!({})), Some(3)), "people");
        assert_eq!(crate::prefs::leading(Some(&json!({ "rowPicture": "agents" })), Some(3)), "agents");
        assert_eq!(crate::prefs::leading(Some(&json!({ "rowPicture": "people" })), Some(1)), "people");
    }

    #[test]
    fn a_draft_is_kept_on_the_device_until_emptied() {
        run(async {
            let (host, core) = local_core(0.0).await;
            let ui = core.connect();
            let topic = Topic::Draft { station: "local".into(), chat: "new".into() };
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: topic.clone() });
            host.settle().await;
            let mut values = HashMap::new();
            apply(&host, &mut values);
            // Nothing written: empty, not waiting.
            assert_eq!(values[&1], json!({ "text": "", "quotes": [], "files": [] }));
            core.receive(ui, ClientMessage::Call { id: 2, call: "draft.put".into(), params: json!({
                "station": "local", "chat": "new", "text": "修一下登录",
                "quotes": [{ "author": "a", "text": "b", "comment": "" }], "files": [{ "name": "x.png", "path": "up/x.png", "size": 3 }],
            }) });
            host.settle().await;
            apply(&host, &mut values);
            assert_eq!(values[&1]["text"], "修一下登录");
            assert_eq!(values[&1]["files"][0]["path"], "up/x.png");
            // Kept across a restart, with no station to ask (written a moment after the last change).
            host.sleep(crate::data::SOON_MS + 50).await;
            drop(core);
            host.take_emitted();
            let core = Core::new(host.clone()).await;
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: topic.clone() });
            host.settle().await;
            let mut values = HashMap::new();
            apply(&host, &mut values);
            assert_eq!(values[&1]["text"], "修一下登录");
            assert_eq!(values[&1]["quotes"][0]["author"], "a");
            // Emptied (sent): gone, from the device too.
            core.receive(ui, ClientMessage::Call { id: 2, call: "draft.put".into(), params: json!({ "station": "local", "chat": "new", "text": " ", "quotes": [], "files": [] }) });
            host.settle().await;
            apply(&host, &mut values);
            assert_eq!(values[&1], json!({ "text": "", "quotes": [], "files": [] }));
            drop(core);
            let core = Core::new(host.clone()).await;
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: topic });
            host.settle().await;
            let mut values = HashMap::new();
            apply(&host, &mut values);
            assert_eq!(values[&1]["text"], "");
            // What is not a draft is refused.
            core.receive(ui, ClientMessage::Call { id: 3, call: "draft.put".into(), params: json!({ "station": "local", "chat": "new", "text": 3 }) });
            core.receive(ui, ClientMessage::Call { id: 4, call: "draft.put".into(), params: json!({ "chat": "new", "text": "x" }) });
            host.settle().await;
            let refused = host.take_emitted().into_iter().filter(|(_, m)| matches!(m, CoreMessage::Error { id: 3 | 4, .. })).count();
            assert_eq!(refused, 2);
        });
    }

    /// A profile as the station lists it: `used` percent of its five hours used; checked since the station started or not.
    fn profile(id: &str, runtime: &str, models: &[&str], checked: bool, used: f64) -> Value {
        json!({
            "id": id, "name": format!("{id}@x.com"), "runtime": runtime, "runtimes": [runtime], "access": { "kind": "subscription", "key": "" },
            "home": "/h", "homeExists": true, "model": null, "models": models, "env": [], "usedBy": [], "loginCommand": "",
            "check": if checked { json!({ "state": "ok", "detail": "", "checkedAt": 1 }) } else { Value::Null },
            "quota": { "state": "ok", "windows": [{ "label": "5 小时", "usedPercent": used, "resetsAt": null }], "detail": null, "checkedAt": 1 },
        })
    }

    /// A local core whose station has three profiles: p1 (unchecked) and p2 run Claude Code, p3 Codex.
    async fn choosing_core() -> (Rc<FakeHost>, Core) {
        let (host, core) = local_core(0.0).await;
        host.on_fetch(|req| {
            let path = req.url.trim_start_matches("https://stillfail.test");
            match (req.method.as_str(), path.split('?').next().unwrap()) {
                ("GET", "/admin/api/overview") => json_response(200, json!({
                    "viewer": { "via": "local" }, "connects": [], "processes": [], "counts": { "sessions": 1, "running": 0, "warm": 0 },
                    "mesh": null, "slackUsers": [], "slackTeams": [], "slackApps": [], "disk": null, "logins": [],
                    "profiles": [
                        profile("p1", "claude", &["claude-opus-5-5", "claude-sonnet-5"], false, 10.0),
                        profile("p2", "claude", &["claude-opus-5-5"], true, 80.0),
                        profile("p3", "codex", &["gpt-6-astra"], true, 0.0),
                    ],
                })),
                ("GET", "/admin/api/sessions") => json_response(200, json!([session("k1")])),
                ("GET", "/admin/api/sessions/k1") => json_response(200, json!({ "session": session("k1"), "threads": [], "turns": [] })),
                ("GET", "/admin/api/machine-sessions") => json_response(200, json!({ "sessions": [{ "runtime": "codex", "id": "m1", "cwd": "/Users/bob/src/x", "updatedAt": 0 }] })),
                ("POST", "/admin/api/profiles/p1/check") => json_response(200, json!({ "state": "ok", "detail": "", "checkedAt": 2 })),
                ("POST", "/admin/api/sessions/k1/settings") => json_response(200, json!({ "ok": true })),
                ("POST", "/admin/api/sessions") => json_response(400, json!({ "error": "not now" })),
                _ => json_response(404, json!({})),
            }
        });
        (host, core)
    }

    fn call(host: &Rc<FakeHost>, core: &Core, ui: ClientId, id: RequestId, name: &str, params: Value) -> impl std::future::Future<Output = Result<Value>> {
        core.receive(ui, ClientMessage::Call { id, call: name.into(), params });
        let host = host.clone();
        async move {
            host.settle().await;
            let mut out = None;
            let mut rest = Vec::new();
            for (c, m) in host.take_emitted() {
                match m {
                    CoreMessage::Ok { id: i, ok } if i == id => out = Some(Ok(ok)),
                    CoreMessage::Error { id: i, error } if i == id => out = Some(Err(error)),
                    m => rest.push((c, m)),
                }
            }
            host.emitted.borrow_mut().extend(rest);
            out.expect("answered")
        }
    }

    fn posted(host: &FakeHost, path: &str) -> Vec<Value> {
        host.requests.borrow().iter().filter(|r| r.method == "POST" && r.url.ends_with(&format!("/admin/api{path}")))
            .map(|r| serde_json::from_slice(r.body.as_deref().unwrap_or(b"null")).unwrap_or(Value::Null)).collect()
    }

    #[test]
    fn a_new_chat_runs_on_what_was_last_picked_there_as_far_as_the_station_still_has_it() {
        run(async {
            let (host, core) = choosing_core().await;
            let ui = core.connect();
            // What the page kept before the core did comes in once.
            call(&host, &core, ui, 1, "newChat.migrate", json!({ "choices": { "local": { "runtime": "claude", "model": "claude-sonnet-5", "effort": "low", "profile": "" } }, "last": "local" })).await.unwrap();
            let topic = Topic::NewChat { scope: "local".into() };
            core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: topic.clone() });
            host.settle().await;
            let mut values = HashMap::new();
            apply(&host, &mut values);
            let v = &values[&2];
            assert_eq!((v["kept"].as_str(), v["station"]["id"].as_str()), (Some("local"), Some("local")));
            assert_eq!((v["model"]["model"].as_str(), v["runtime"].as_str(), v["effort"].as_str()), (Some("claude-sonnet-5"), Some("claude"), Some("low")));
            assert_eq!((v["waiting"].clone(), v["blocked"].clone(), v["pickAccount"].clone()), (json!(false), Value::Null, json!(false)));
            // Its unchecked profile is checked, once.
            assert_eq!(posted(&host, "/profiles/p1/check").len(), 1);
            assert!(posted(&host, "/profiles/p2/check").is_empty());
            // An account kept to that does not run the model gives way to the station's pick.
            call(&host, &core, ui, 3, "newChat.pick", json!({ "scope": "local", "model": "claude-opus-5-5", "profile": "p3" })).await.unwrap();
            apply(&host, &mut values);
            let v = &values[&2];
            assert_eq!((v["model"]["model"].as_str(), v["effort"].as_str(), v["profile"].clone()), (Some("claude-opus-5-5"), Some("low"), Value::Null));
            assert_eq!(v["accounts"].as_array().map(Vec::len), Some(2));
            assert_eq!(v["pickAccount"], true);
            assert_eq!(v["accounts"][0]["quotaLine"], json!({ "text": "5 小时 90%" }));
            assert_eq!(v["accounts"][1]["quotaLine"], json!({ "text": "5 小时只剩 20%", "level": "amber" }));
            // A model on another runtime takes it, and its default depth.
            call(&host, &core, ui, 4, "newChat.pick", json!({ "scope": "local", "model": "gpt-6-astra" })).await.unwrap();
            apply(&host, &mut values);
            assert_eq!((values[&2]["runtime"].as_str(), values[&2]["effort"].clone()), (Some("codex"), Value::Null));
            // Kept across a restart; what an older page kept does not come in over it.
            drop(core);
            host.take_emitted();
            let core = Core::new(host.clone()).await;
            let ui = core.connect();
            call(&host, &core, ui, 1, "newChat.migrate", json!({ "choices": { "local": { "runtime": "claude", "model": "claude-sonnet-5", "effort": "", "profile": "" } } })).await.unwrap();
            core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: topic });
            host.settle().await;
            let mut values = HashMap::new();
            apply(&host, &mut values);
            assert_eq!(values[&2]["model"]["model"], "gpt-6-astra");
            // The model control of a new chat there: picked in its panel, then saved as what it runs on.
            let pick = Topic::Pick { station: "local".into(), of: "new".into() };
            core.receive(ui, ClientMessage::Subscribe { id: 5, subscribe: pick });
            host.settle().await;
            apply(&host, &mut values);
            assert_eq!((values[&5]["changed"].clone(), values[&5]["value"]["runtime"].clone(), values[&5]["account"].clone()), (json!(false), json!("codex"), Value::Null));
            call(&host, &core, ui, 6, "pick.set", json!({ "station": "local", "of": "new", "model": "claude-opus-5-5", "profile": "p2" })).await.unwrap();
            apply(&host, &mut values);
            let p = &values[&5];
            assert_eq!((p["changed"].clone(), p["draft"]["runtime"].clone(), p["draft"]["profile"].clone(), p["who"].clone()), (json!(true), json!("claude"), json!("p2"), json!("p2")));
            assert_eq!(values[&2]["model"]["model"], "gpt-6-astra", "only a draft until saved");
            assert_eq!(call(&host, &core, ui, 7, "pick.save", json!({ "station": "local", "of": "new" })).await.unwrap()["saved"], true);
            apply(&host, &mut values);
            assert_eq!((values[&2]["model"]["model"].as_str(), values[&2]["profile"].as_str()), (Some("claude-opus-5-5"), Some("p2")));
            // Kept to an account running low: the control names it, amber.
            assert_eq!(values[&5]["account"], json!({ "text": "p2@x.com", "auto": false, "level": "amber" }));
            // A chat made there is asked for with it, and the scope's next new chat starts there too.
            let made = call(&host, &core, ui, 8, "newChat.create", json!({ "station": "local" })).await.unwrap();
            assert!(made["key"].as_str().is_some_and(|k| k.starts_with(crate::views::PENDING_PREFIX)));
            assert_eq!(posted(&host, "/sessions").last().map(|b| (b["model"].clone(), b["profile"].clone())), Some((json!("claude-opus-5-5"), json!("p2"))));
            // Refused: no scope, no station.
            assert!(call(&host, &core, ui, 9, "newChat.pick", json!({ "model": "x" })).await.is_err());
            assert!(call(&host, &core, ui, 10, "pick.set", json!({ "station": "local", "of": "nothing" })).await.is_err());
        });
    }

    #[test]
    fn a_sessions_model_control_says_what_changes_and_saves_it_on_the_station() {
        run(async {
            let (host, core) = choosing_core().await;
            let ui = core.connect();
            let pick = Topic::Pick { station: "local".into(), of: "session:k1".into() };
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: pick });
            host.settle().await;
            let mut values = HashMap::new();
            apply(&host, &mut values);
            let p = &values[&1];
            // It runs on p1, the station's pick, with no model set.
            assert_eq!((p["runtimeFixed"].clone(), p["value"]["model"].clone(), p["account"]["text"].clone()), (json!(true), Value::Null, json!("自动 · p1@x.com")));
            assert_eq!(p["saveText"], "不变");
            // Kept to p2 and moved to Sonnet, which p2 does not run: back to the station's pick, said so.
            call(&host, &core, ui, 2, "pick.set", json!({ "station": "local", "of": "session:k1", "profile": "p2" })).await.unwrap();
            call(&host, &core, ui, 3, "pick.set", json!({ "station": "local", "of": "session:k1", "model": "claude-sonnet-5", "effort": "high" })).await.unwrap();
            apply(&host, &mut values);
            let p = &values[&1];
            assert_eq!(p["draft"]["profile"], Value::Null);
            assert!(p["dropped"].as_str().is_some_and(|d| d.contains("改成了自动分配")), "{p}");
            assert!(p["force"].as_str().is_some_and(|f| f.starts_with("指定的账号「p2」没有启用")), "{p}");
            assert_eq!(p["whoLevel"], "amber");
            assert_eq!(p["becomes"][1], "high");
            assert_eq!(p["changed"], true);
            call(&host, &core, ui, 4, "pick.save", json!({ "station": "local", "of": "session:k1" })).await.unwrap();
            assert_eq!(posted(&host, "/sessions/k1/settings"), [json!({ "model": "claude-sonnet-5", "effort": "high", "profile": null })]);
            // Opened again: from what it runs on.
            call(&host, &core, ui, 5, "pick.set", json!({ "station": "local", "of": "session:k1", "open": true })).await.unwrap();
            apply(&host, &mut values);
            assert_eq!(values[&1]["draft"]["effort"], Value::Null);
            // The machine's own sessions come each with its line.
            let listed = call(&host, &core, ui, 6, "machineSessions.list", json!({ "station": "local" })).await.unwrap();
            assert!(listed["sessions"][0]["meta"].as_str().is_some_and(|m| m.starts_with("Codex · ~/src/x · ")), "{listed}");
        });
    }

    #[test]
    fn a_draft_written_as_it_is_typed_is_one_write_and_read_by_its_key() {
        run(async {
            let (host, core) = local_core(0.0).await;
            let ui = core.connect();
            let put = |id, text: &str| ClientMessage::Call { id, call: "draft.put".into(), params: json!({ "key": "local:thread:7", "text": text, "quotes": [], "files": [] }) };
            for (id, text) in [(1, "修"), (2, "修一"), (3, "修一下")] {
                core.receive(ui, put(id, text));
            }
            host.settle().await;
            let kept = |host: &FakeHost| host.db.borrow().iter().filter(|((t, _), _)| t == "draft").map(|(_, v)| serde_json::from_slice::<Value>(v).unwrap()["text"].clone()).collect::<Vec<_>>();
            // There at once; on the device a moment after the last change, as it is then.
            assert!(kept(&host).is_empty());
            core.receive(ui, ClientMessage::Call { id: 4, call: "draft.get".into(), params: json!({ "key": "local:thread:7" }) });
            host.settle().await;
            let answer = |host: &FakeHost, want| host.take_emitted().into_iter().find_map(|(_, m)| match m { CoreMessage::Ok { id, ok } if id == want => Some(ok), _ => None });
            assert_eq!(answer(&host, 4).unwrap()["text"], "修一下");
            host.sleep(crate::data::SOON_MS + 50).await;
            host.settle().await;
            assert_eq!(kept(&host), [json!("修一下")]);
            // Emptied before it was written: nothing is written after all.
            core.receive(ui, ClientMessage::Call { id: 5, call: "draft.put".into(), params: json!({ "key": "new:local", "text": "新的" }) });
            core.receive(ui, ClientMessage::Call { id: 6, call: "draft.put".into(), params: json!({ "key": "new:local", "text": "" }) });
            host.sleep(crate::data::SOON_MS + 50).await;
            host.settle().await;
            assert_eq!(kept(&host), [json!("修一下")]);
            core.receive(ui, ClientMessage::Call { id: 7, call: "draft.get".into(), params: json!({ "key": "new:local" }) });
            host.settle().await;
            assert_eq!(answer(&host, 7).unwrap(), json!({ "text": "", "quotes": [], "files": [] }));
        });
    }

    #[test]
    fn a_chat_referred_to_goes_out_as_a_link_to_it() {
        run(async {
            let (host, core) = local_core(0.0).await;
            let ui = core.connect();
            core.receive(ui, ClientMessage::Call { id: 1, call: "chat.ref".into(), params: json!({ "station": "local", "id": "ember:c 1", "title": "排查 [登录]", "base": "/admin" }) });
            core.receive(ui, ClientMessage::Call { id: 2, call: "chat.ref".into(), params: json!({ "station": "ws/st", "id": "k2", "title": "云上的" }) });
            // Kept by a page before the core kept them.
            core.receive(ui, ClientMessage::Call { id: 3, call: "chat.refs".into(), params: json!({ "links": [["旧的", "https://x/chats/a"]] }) });
            host.settle().await;
            let answers: HashMap<RequestId, Value> = host.take_emitted().into_iter().filter_map(|(_, m)| match m { CoreMessage::Ok { id, ok } => Some((id, ok)), _ => None }).collect();
            assert_eq!(answers[&1], json!({ "mark": "@[排查 登录]" }));
            assert_eq!(answers[&2], json!({ "mark": "@[云上的]" }));
            core.receive(ui, ClientMessage::Call { id: 4, call: "chat.send".into(), params: json!({ "station": "local", "thread": 7, "text": "看 @[排查 登录]、@[云上的]、@[旧的] 和 @[不知道]" }) });
            host.settle().await;
            let sent = host.requests.borrow().iter().rev().find(|r| r.method == "POST" && r.url.ends_with("/admin/api/threads/7/messages")).map(|r| serde_json::from_slice::<Value>(r.body.as_deref().unwrap()).unwrap()).expect("sent");
            assert_eq!(sent["text"], "看 [排查 登录](/admin/chats/ember%3Ac%201)、[云上的](https://stillfail.test/w/ws/s/st/chats/k2)、[旧的](https://x/chats/a) 和 @[不知道]");
        });
    }

    #[test]
    fn the_chats_a_few_words_find_are_a_view_of_the_list() {
        run(async {
            let (host, core) = local_core(0.0).await;
            host.on_fetch(|req| {
                let path = req.url.trim_start_matches("https://stillfail.test");
                let row = |id: &str, title: &str, at: i64| json!({
                    "id": id, "session": id, "thread": null, "title": title, "agents": [], "last": null, "unread": false, "mine": true,
                    "lastActiveAt": at, "connect": null, "origin": null,
                });
                match path.split('?').next().unwrap() {
                    "/admin/api/chats" => json_response(200, json!([row("a", "别的", 3), row("b", "登录页", 2), row("c", "修登录", 1)])),
                    "/admin/api/overview" => json_response(200, json!({
                        "viewer": { "via": "local" }, "connects": [], "profiles": [], "processes": [], "counts": { "sessions": 0, "running": 0, "warm": 0 },
                        "mesh": null, "slackUsers": [], "slackTeams": [], "slackApps": [], "disk": null, "logins": [],
                    })),
                    _ => json_response(404, json!({})),
                }
            });
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: serde_json::from_value(json!({ "topic": "chatSearch", "scope": "local", "query": "登录", "exclude": "c" })).unwrap() });
            host.settle().await;
            let mut values = HashMap::new();
            apply(&host, &mut values);
            let ids: Vec<&str> = values[&1]["items"].as_array().unwrap().iter().map(|i| i["id"].as_str().unwrap()).collect();
            assert_eq!(ids, ["b"]);
            assert_eq!(values[&1]["items"][0]["station"], "local");
        });
    }

    #[test]
    fn a_chat_shown_has_its_unread_line_and_is_read_while_its_end_is_in_view() {
        run(async {
            let (host, core) = local_core(0.0).await;
            host.on_fetch(|req| {
                let path = req.url.trim_start_matches("https://stillfail.test");
                let said = |n: u64| json!({ "thread": 7, "n": n, "kind": "message", "ts": format!("{n}.0"), "authorKind": "agent", "author": "k1", "authorName": null, "text": "好", "at": n });
                match (req.method.as_str(), path.split('?').next().unwrap()) {
                    ("GET", "/admin/api/threads") => json_response(200, json!([{
                        "id": 7, "surface": "ember", "channel": "EMBER", "channelName": null, "threadTs": "7.0", "title": null, "createdBy": null,
                        "creator": null, "createdAt": 1, "sessions": [{ "thread": 7, "session": "k1", "connect": "ember", "joinedAt": 1 }],
                        "last": 3, "lastMessage": null, "read": 1, "unread": 2, "people": [], "firstText": null,
                    }])),
                    ("GET", "/admin/api/threads/7/entries") => json_response(200, json!({ "first": 1, "last": 3, "entries": [said(1), said(2), said(3)] })),
                    ("PUT", "/admin/api/threads/7/read") => json_response(200, json!({ "n": 3 })),
                    ("GET", "/admin/api/sessions") => json_response(200, json!([session("k1")])),
                    ("GET", "/admin/api/sessions/k1") => json_response(200, json!({ "session": session("k1"), "threads": [], "turns": [] })),
                    _ => json_response(404, json!({})),
                }
            });
            let ui = core.connect();
            let mut values = HashMap::new();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Chat { station: "local".into(), thread: Some(7), session: None } });
            host.settle().await;
            apply(&host, &mut values);
            // Not shown by any page yet: no line.
            assert_eq!(values[&1]["messages"].as_array().unwrap().len(), 3);
            assert_eq!(values[&1].get("unreadLine"), None);
            // Shown: the line over the first not read when it was opened; not read while its end is out of view.
            core.receive(ui, ClientMessage::Call { id: 2, call: "client.focus".into(), params: json!({ "visible": true, "focused": true, "chat": { "station": "local", "thread": 7, "end": false } }) });
            host.settle().await;
            apply(&host, &mut values);
            assert_eq!(values[&1]["unreadLine"], 2);
            let reads = |host: &FakeHost| host.requests.borrow().iter().filter(|r| r.method == "PUT" && r.url.ends_with("/threads/7/read")).count();
            assert_eq!(reads(&host), 0);
            // Its end in view: read up to the newest, once; the line stays for the visit.
            core.receive(ui, ClientMessage::Call { id: 3, call: "client.focus".into(), params: json!({ "chat": { "station": "local", "thread": 7, "end": true } }) });
            host.settle().await;
            core.receive(ui, ClientMessage::Call { id: 4, call: "client.focus".into(), params: json!({ "visible": true }) });
            host.settle().await;
            apply(&host, &mut values);
            assert_eq!(reads(&host), 1);
            assert_eq!(values[&1]["unreadLine"], 2);
            // The page gone: the visit ends with it; opened again, nothing unread.
            core.disconnect(ui);
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Chat { station: "local".into(), thread: Some(7), session: None } });
            core.receive(ui, ClientMessage::Call { id: 2, call: "client.focus".into(), params: json!({ "visible": true, "chat": { "station": "local", "thread": 7 } }) });
            host.settle().await;
            let mut values = HashMap::new();
            apply(&host, &mut values);
            assert_eq!(values[&1]["unreadLine"], Value::Null);
        });
    }

    #[test]
    fn notifications_are_on_until_turned_off_and_kept_so_with_no_pushes() {
        run(async {
            let (host, core) = local_core(0.0).await;
            let ui = core.connect();
            let mut values = HashMap::new();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Notify });
            host.settle().await;
            apply(&host, &mut values);
            assert_eq!(values[&1], json!({ "on": true, "asked": false, "push": true, "show": [] }));
            // Off (and asked, as Android moves its old settings over): pushes go, and are not taken while off.
            core.receive(ui, ClientMessage::Call { id: 2, call: "notify.set".into(), params: json!({ "on": false, "asked": true }) });
            core.receive(ui, ClientMessage::Call { id: 3, call: "push.register".into(), params: json!({ "kind": "fcm", "token": "t" }) });
            host.settle().await;
            apply(&host, &mut values);
            assert_eq!(values[&1], json!({ "on": false, "asked": true, "push": false, "show": [] }));
            assert_eq!(host.stored(PUSH_KEY), None);
            // Kept across a restart.
            drop(core);
            let core = Core::new(host.clone()).await;
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Notify });
            core.receive(ui, ClientMessage::Call { id: 2, call: "notice.pushed".into(), params: json!({}) });
            core.receive(ui, ClientMessage::Call { id: 3, call: "notice.claim".into(), params: json!({ "id": "n1" }) });
            host.settle().await;
            let emitted = host.take_emitted();
            let ok = |id| emitted.iter().find_map(|(_, m)| match m { CoreMessage::Ok { id: i, ok } if *i == id => Some(ok.clone()), _ => None }).unwrap();
            assert_eq!((ok(2), ok(3)), (json!({ "show": false }), json!({ "show": false })));
            let value = emitted.iter().find_map(|(_, m)| match m { CoreMessage::Value { id: 1, value } => Some(value.clone()), _ => None }).unwrap();
            assert_eq!(value["on"], false);
        });
    }

    #[test]
    fn a_chats_jobs_are_shown_as_the_core_puts_them_and_a_jobs_output_says_when_it_last_grew() {
        run(async {
            let host = FakeHost::new();
            host.speed_up(SPEEDUP);
            let now = (now_s() * 1000.0) as i64;
            let reads = Rc::new(std::cell::Cell::new(0));
            let counted = reads.clone();
            host.on_fetch(move |req| {
                let path = req.url.trim_start_matches("https://stillfail.test");
                let job = |id: &str, patch: Value| {
                    let mut j = json!({ "id": id, "session": "k1", "name": id, "state": "running", "port": null, "startedAt": now - 60_000, "command": "watch" });
                    j.as_object_mut().unwrap().extend(patch.as_object().unwrap().clone());
                    j
                };
                match path.split('?').next().unwrap() {
                    "/admin/api/threads" => json_response(200, json!([{
                        "id": 7, "surface": "ember", "channel": "EMBER", "channelName": null, "threadTs": "7.0", "title": null, "createdBy": null,
                        "creator": null, "createdAt": 1, "sessions": [{ "thread": 7, "session": "k1", "connect": "ember", "joinedAt": 1 }],
                        "last": 0, "lastMessage": null, "read": 0, "unread": 0, "people": [], "firstText": null,
                    }])),
                    "/admin/api/threads/7/entries" => json_response(200, json!({ "last": 0, "entries": [] })),
                    "/admin/api/sessions" => json_response(200, json!([session("k1")])),
                    "/admin/api/sessions/k1" => json_response(200, json!({ "session": session("k1"), "threads": [], "turns": [], "jobs": [
                        job("w", json!({ "notices": [{ "at": now - 120_000, "text": "CI 还在跑" }] })),
                        job("s", json!({ "port": 4817, "state": "exited", "restarts": 1 })),
                        job("done", json!({ "state": "exited", "exitCode": 0, "endedAt": now - 30_000 })),
                    ] })),
                    "/admin/api/overview" => json_response(200, json!({
                        "viewer": { "via": "local" }, "connects": [], "profiles": [], "processes": [], "counts": { "sessions": 1, "running": 0, "warm": 0 },
                        "mesh": null, "slackUsers": [], "slackTeams": [], "slackApps": [], "disk": null, "logins": [],
                    })),
                    "/admin/api/jobs/w/log" => {
                        counted.set(counted.get() + 1);
                        json_response(200, json!({ "text": "step 3\n", "outputAt": now - 180_000, "follows": true }))
                    }
                    _ => json_response(404, json!({})),
                }
            });
            host.on_fetch_stream(|_| Ok(crate::host::StreamResponse { status: 200, headers: vec![], body: futures::stream::pending().boxed_local() }));
            let core = Core::new(host.clone()).await;
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::ChatJobs { station: "local".into(), thread: Some(7), session: None } });
            core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: Topic::JobLog { station: "local".into(), job: "w".into(), lines: 1 } });
            host.settle().await;
            host.settle().await;
            let mut values = HashMap::new();
            apply(&host, &mut values);
            // Restarting first, then alive, then what is over; each with its dot and its line; the heads' notes.
            let jobs = &values[&1];
            let ids: Vec<&str> = jobs["jobs"].as_array().unwrap().iter().map(|j| j["id"].as_str().unwrap()).collect();
            assert_eq!(ids, ["s", "w", "done"]);
            assert_eq!((jobs["alarm"].as_str(), jobs["servicesNote"].as_str(), jobs["jobsNote"].as_str()), (Some("restart"), Some("1 个在重启"), Some("1 个在盯着")));
            assert_eq!((jobs["ended"].as_i64(), jobs["clear"].clone(), jobs["clearText"].as_str()), (Some(1), json!(["k1"]), Some("清掉 1 个已结束的")));
            let w = &jobs["jobs"][1];
            assert_eq!((w["tone"].as_str(), w["meta"][0]["text"].as_str(), w["meta"][1]["text"].as_str(), w["detail"].as_str()), (Some("live"), Some("CI 还在跑"), Some(" · 2 分钟前"), Some("在盯着 · 1 分钟 · 1 条通知")));
            assert_eq!((jobs["jobs"][0]["meta"][0]["text"].as_str(), jobs["jobs"][2]["tone"].as_str()), (Some("正在重启"), Some("off")));
            // Its output: the last line and when, in words; the station follows it, so it is not read again.
            assert_eq!((values[&2]["last"].as_str(), values[&2]["said"].as_str()), (Some("step 3"), Some("最后输出 · 3 分钟前")));
            let before = reads.get();
            pass(5_000).await;
            assert_eq!(reads.get(), before);
        });
    }

    #[test]
    fn a_new_chat_is_there_at_once_and_what_is_sent_to_it_goes_in_once_the_station_has_made_it() {
        run(async {
            let (host, core) = local_core(0.0).await;
            let up = Rc::new(Cell::new(false));
            let station_up = up.clone();
            host.on_fetch(move |req| {
                let path = req.url.trim_start_matches("https://stillfail.test");
                match (req.method.as_str(), path) {
                    ("POST", "/admin/api/sessions") if !station_up.get() => json_response(400, json!({"error": "no claude profile configured"})),
                    ("POST", "/admin/api/sessions") => json_response(200, json!({"key": "ember:c-1", "thread": {
                        "id": 9, "surface": "ember", "channel": "EMBER", "channelName": null, "threadTs": "9.0", "title": null, "createdBy": "local",
                        "creator": null, "createdAt": 1, "sessions": [{ "thread": 9, "session": "ember:c-1", "connect": "ember", "joinedAt": 1 }],
                        "last": 0, "lastMessage": null, "read": 0, "unread": 0, "people": [], "firstText": null,
                    }})),
                    ("POST", "/admin/api/threads/9/messages") => json_response(200, json!({"n": 1})),
                    _ => json_response(404, json!({})),
                }
            });
            let ui = core.connect();
            core.receive(ui, ClientMessage::Call { id: 1, call: "chat.create".into(), params: json!({"station": "local", "runtime": "claude", "model": "opus"}) });
            host.settle().await;
            let answers = host.take_emitted();
            let key = answers.iter().find_map(|(_, m)| match m { CoreMessage::Ok { id: 1, ok } => ok["key"].as_str().map(str::to_string), _ => None }).expect("answered at once");
            assert!(key.starts_with(crate::views::PENDING_PREFIX), "{key}");
            // The station could not make it: what is sent waits, and has it tried again.
            core.receive(ui, ClientMessage::Subscribe { id: 2, subscribe: Topic::Chat { station: "local".into(), thread: None, session: Some(key.clone()) } });
            host.settle().await;
            let mut values = HashMap::new();
            apply(&host, &mut values);
            assert_eq!(values[&2]["pending"], true);
            up.set(true);
            core.receive(ui, ClientMessage::Call { id: 3, call: "chat.send".into(), params: json!({"station": "local", "session": key, "text": "修一下登录", "client": "android 0.1.1123"}) });
            host.settle().await;
            let asked: Vec<(String, String)> = host.requests.borrow().iter().filter(|r| r.method == "POST" && r.url.contains("/admin/api/"))
                .map(|r| (r.url.trim_start_matches("https://stillfail.test/admin/api").to_string(), String::from_utf8(r.body.clone().unwrap_or_default()).unwrap())).collect();
            assert_eq!(asked.iter().map(|(p, _)| p.as_str()).collect::<Vec<_>>(), ["/sessions", "/sessions", "/threads/9/messages"]);
            // It carries the key given here: the station's rows say it of the chat made.
            assert_eq!(serde_json::from_str::<Value>(&asked[0].1).unwrap(), json!({"runtime": "claude", "model": "opus", "clientKey": key}));
            // With the app it was sent from, which waited with it.
            let sent = serde_json::from_str::<Value>(&asked[2].1).unwrap();
            assert_eq!((sent["text"].clone(), sent["client"].clone()), (json!("修一下登录"), json!("android 0.1.1123")));
            // The page is the station's chat now, under the key it was opened with, and says the one the station gave it.
            apply(&host, &mut values);
            assert_eq!((values[&2]["pending"].clone(), values[&2]["key"].clone()), (json!(false), json!("ember:c-1")));
        });
    }

    /// What came out: subscription values (deltas applied) into `values`, and the calls' answers.
    fn answers(host: &FakeHost, values: &mut HashMap<RequestId, Value>) -> HashMap<RequestId, std::result::Result<Value, String>> {
        let mut answers = HashMap::new();
        for (_, message) in host.take_emitted() {
            match message {
                CoreMessage::Value { id, value } => {
                    values.insert(id, value);
                }
                CoreMessage::Delta { id, delta } => crate::delta::apply(values.get_mut(&id).expect("a delta needs a value"), &delta),
                CoreMessage::Ok { id, ok } => {
                    answers.insert(id, Ok(ok));
                }
                CoreMessage::Error { id, error } => {
                    answers.insert(id, Err(error.message));
                }
            }
        }
        answers
    }

    #[test]
    fn a_chat_being_archived_leaves_the_list_at_once_and_comes_back_if_it_could_not_be() {
        run(async {
            let (host, core) = local_core(0.0).await;
            let (archived, refused) = (Rc::new(Cell::new(false)), Rc::new(Cell::new(true)));
            let (a, r) = (archived.clone(), refused.clone());
            host.on_fetch(move |req| {
                let row = |id: &str, thread: u64| json!({ "id": id, "session": id, "thread": thread, "title": id, "agents": [], "last": null,
                    "unread": false, "mine": true, "lastActiveAt": 1, "connect": null, "origin": null });
                match (req.method.as_str(), req.url.trim_start_matches("https://stillfail.test/admin/api")) {
                    ("GET", "/chats") => json_response(200, if a.get() { json!([row("k2", 8)]) } else { json!([row("k1", 7), row("k2", 8)]) }),
                    ("POST", "/threads/7/archive") if r.get() => json_response(409, json!({ "error": "还在跑" })),
                    ("POST", "/threads/7/archive") => {
                        a.set(true);
                        json_response(200, json!({ "ok": true }))
                    }
                    _ => json_response(404, json!({})),
                }
            });
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Chats { scope: "local".into(), mine: false } });
            host.settle().await;
            let mut values = HashMap::new();
            answers(&host, &mut values);
            let ids = |values: &HashMap<RequestId, Value>| -> Vec<String> {
                values[&1]["days"].as_array().unwrap().iter().flat_map(|d| d["items"].as_array().unwrap().iter().map(|i| i["id"].as_str().unwrap().to_string())).collect()
            };
            assert_eq!(ids(&values), ["k1", "k2"]);
            let archive = |id| ClientMessage::Call { id, call: "chat.archive".into(), params: json!({ "station": "local", "thread": 7, "session": "k1", "archived": true }) };
            // Gone at once, while the station has not answered.
            let held = host.hold("/threads/7/archive");
            core.receive(ui, archive(2));
            host.settle().await;
            assert!(answers(&host, &mut values).is_empty());
            assert_eq!(ids(&values), ["k2"]);
            // It could not be: back, and the call says why.
            drop(held);
            host.settle().await;
            assert_eq!(answers(&host, &mut values)[&2], Err("还在跑".to_string()));
            assert_eq!(ids(&values), ["k1", "k2"]);
            // Archived: its station's rows, read again before the answer, no longer have it.
            refused.set(false);
            let held = host.hold("/threads/7/archive");
            core.receive(ui, archive(3));
            host.settle().await;
            answers(&host, &mut values);
            assert_eq!(ids(&values), ["k2"]);
            held.send(()).unwrap();
            host.settle().await;
            assert!(answers(&host, &mut values)[&3].is_ok());
            assert_eq!(ids(&values), ["k2"]);
            assert!(archived.get());
        });
    }

    #[test]
    fn the_archive_is_its_stations_archived_chats_newest_first_by_day_and_one_restored_or_deleted_leaves_it() {
        run(async {
            let (host, core) = local_core(0.0).await;
            let now = host.now_ms().round();
            let gone = Rc::new(RefCell::new(Vec::<&str>::new()));
            let g = gone.clone();
            host.on_fetch(move |req| {
                let chat = |id: &str, thread: u64, archived: Value| json!({ "id": id, "session": id, "thread": thread, "title": format!("聊 {id}"),
                    "last": { "text": "好了" }, "lastActiveAt": now - 9e8, "archived": archived });
                match (req.method.as_str(), req.url.trim_start_matches("https://stillfail.test/admin/api")) {
                    ("GET", "/chats?archived=1") => {
                        let all = [
                            chat("k2", 8, json!({ "at": now - 3.0 * 86_400_000.0, "by": "auto", "alone": true })),
                            chat("k1", 7, json!({ "at": now, "by": "manual", "alone": false })),
                            // A station from before the archive answers the chats it shows: not archived ones.
                            chat("k3", 9, Value::Null),
                        ];
                        json_response(200, Value::Array(all.into_iter().filter(|c| !g.borrow().contains(&c["id"].as_str().unwrap())).collect()))
                    }
                    ("DELETE", "/threads/7/archive") => {
                        g.borrow_mut().push("k1");
                        json_response(200, json!({ "ok": true }))
                    }
                    ("DELETE", "/sessions/k2") => {
                        g.borrow_mut().push("k2");
                        json_response(200, json!({ "ok": true }))
                    }
                    _ => json_response(404, json!({})),
                }
            });
            let ui = core.connect();
            core.receive(ui, ClientMessage::Subscribe { id: 1, subscribe: Topic::Archive { scope: "local".into() } });
            host.settle().await;
            let mut values = HashMap::new();
            answers(&host, &mut values);
            let v = &values[&1];
            assert_eq!((v["loading"].clone(), v.get("note"), v["errors"].clone()), (json!(false), None, json!([])));
            let days = v["days"].as_array().unwrap();
            assert_eq!(days.len(), 2);
            assert_eq!(days[0]["label"], "今天");
            let first = &days[0]["items"][0];
            assert_eq!(
                (first["station"].clone(), first["session"].clone(), first["thread"].clone(), first["title"].clone(), first["last"].clone(), first["how"].clone(), first["deletable"].clone()),
                (json!("local"), json!("k1"), json!(7), json!("聊 k1"), json!("好了"), json!("手动归档"), json!(true))
            );
            assert_eq!(first["clock"].as_str().unwrap().len(), 5);
            // One station: which one is not said.
            assert!(first.get("place").is_none());
            assert_eq!((days[1]["items"][0]["how"].clone(), days[1]["items"][0]["deletable"].clone()), (json!("空闲后自动归档"), json!(false)));
            // Put back in the list: it leaves the archive before the call answers.
            core.receive(ui, ClientMessage::Call { id: 2, call: "chat.archive".into(), params: json!({ "station": "local", "thread": 7, "session": "k1", "archived": false }) });
            host.settle().await;
            assert!(answers(&host, &mut values)[&2].is_ok());
            let sessions = |v: &Value| -> Vec<String> { v["days"].as_array().unwrap().iter().flat_map(|d| d["items"].as_array().unwrap().iter().map(|i| i["session"].as_str().unwrap().to_string())).collect() };
            assert_eq!(sessions(&values[&1]), ["k2"]);
            // Deleted: the same, and with nothing left the page says so.
            core.receive(ui, ClientMessage::Call { id: 3, call: "session.delete".into(), params: json!({ "station": "local", "key": "k2" }) });
            host.settle().await;
            assert!(answers(&host, &mut values)[&3].is_ok());
            assert_eq!((values[&1]["days"].clone(), values[&1]["note"].clone()), (json!([]), json!("没有归档的对话。")));
        });
    }

    #[test]
    fn encodes_path_segments_like_encode_uri_component() {
        assert_eq!(encode("ws_01-a.b~"), "ws_01-a.b~");
        assert_eq!(encode("a/b c?"), "a%2Fb%20c%3F");
        assert_eq!(encode("工"), "%E5%B7%A5");
    }
}
