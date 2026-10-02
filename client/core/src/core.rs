//! `Core`: takes messages from connected UIs, answers calls, keeps
//! subscriptions. Construction wires the modules together: accounts → cloud →
//! mesh links (member credentials come from cloud as the account that reaches the
//! workspace) → stations; the store routes topics to accounts (accounts,
//! workspaces, workspace), stations (everything with a station) or the views.
//! What the core has of each workspace is that workspace's (workspace.rs): the
//! account that reaches it, its stations, its waits, its notices, what is kept
//! in sync of it.
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

mod execute;
mod routing;
mod account_state;

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
use stillfail_i18n::t;

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
use crate::status::{Place, Status, StatusOf, Take};
use crate::store::{Source, Store};
use crate::notices::Notices;
use crate::sync::Sync;
use crate::trace::{self, Kind, Span, Tracer};
use crate::views::{EmailOf, Views};
use crate::wake::{self, Wake, Wakes, WakingHost};
use crate::workspace::Workspaces;

mod calls;
pub(crate) use calls::Call;
use calls::parse_call;

/// The first wait before an events socket is opened again; it doubles up to [`SOCKET_RETRY_MAX_MS`], and starts
/// over once a socket held for a minute.
pub const SOCKET_RETRY_MS: u64 = 1_000;
pub const SOCKET_RETRY_MAX_MS: u64 = 60_000;
/// An events socket that answered a ping before and then heard nothing this long (the host pings every
/// `SOCKET_PING_MS`, host.rs) is on a connection that is gone though nothing said so: it is opened again.
pub const SOCKET_IDLE_MS: u64 = 2 * crate::host::SOCKET_PING_MS + 10_000;
/// The subprotocol still.fail cloud's `/v1/events` answers with; the token travels as a second one.
pub const EVENTS_PROTOCOL: &str = "stillfail-events";

pub struct PreparedMessage(Prepared);

enum Prepared {
    Call { id: RequestId, name: String, asked: Option<Value>, call: Result<Call> },
    Other(ClientMessage),
}

/// JSON is already decoded here; parameter validation and large base64 inputs can be prepared by a native worker.
impl PreparedMessage {
    pub fn call_id(&self) -> Option<RequestId> {
        match &self.0 { Prepared::Call { id, .. } => Some(*id), Prepared::Other(_) => None }
    }
}

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
    /// still.fail's relays, its own first, as the first `/v1/me` of this run or the kept one said (`relays`).
    relays: RefCell<Option<Vec<String>>>,
    /// Every workspace, each with the account that reaches it (from the latest `/v1/me` answers) and what is its own.
    workspaces: Rc<Workspaces>,
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
    /// What the device waits on, for the `status` topic: still.fail cloud, its sockets, the relay for no station.
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
    /// What UIs ask that is no station's or account's call (asks.rs).
    asks: crate::asks::Asks,
    /// What changed in still.fail, for this app (changelog.rs).
    changelog: Rc<crate::changelog::Changelog>,
    /// What people set going here, until it is done (doing.rs).
    doing: crate::doing::Doing,
    connect_flow: crate::connect_flow::Flows,
    slack_tokens: crate::slack_tokens::Tokens,
    /// This phone's adb, while it is lent to a station's agents (adb.rs).
    adb: Rc<crate::adb::Adb>,
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
        Core::built(host, sample, None).await
    }

    /// One whose stations answer over the wire `wire` makes of its host, not the mesh: tests' stations.
    #[cfg(test)]
    pub(crate) async fn with_wire(host: Rc<dyn Host>, sample: f64, wire: impl FnOnce(Rc<dyn Host>) -> Rc<dyn station::StationWire> + 'static) -> Core {
        Core::built(host, sample, Some(Box::new(wire))).await
    }

    async fn built(host: Rc<dyn Host>, sample: f64, wire: Option<WireOf>) -> Core {
        // Everything the core asks of the host is given up or opened again when a UI comes back (wake.rs).
        let wakes = Rc::new(Wakes::default());
        let host: Rc<dyn Host> = WakingHost::new(host, wakes.clone());
        crate::brand::set_test_channel(host.test_channel());
        let tracer = Tracer::new(host.clone(), sample);
        let accounts = Accounts::load(host.clone()).await;
        accounts.set_tracer(tracer.clone());
        let status = Status::new(host.clone());
        let cloud = Cloud::new(host.clone(), accounts.clone(), tracer.clone(), status.clone());
        // What was last known is there before any UI asks.
        let data = Data::new(host.clone());
        data.load().await;
        crate::prefs::follow_lang(&data);
        let attend = Attend::load(host.clone()).await;
        let workspaces = Workspaces::new(host.clone());
        let inner = Rc::new_cyclic(|me: &Weak<Inner>| {
            let store = Store::new(host.clone());
            // What goes out is what the clients' types say (client/shapes).
            store.set_shaped();
            store.set_held({
                let data = data.clone();
                Rc::new(move |topic: &Topic| data.shown(topic))
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
            let wire = match wire {
                Some(wire) => wire(host.clone()),
                None => station::wire(mesh_source(me.clone()), credentials(me.clone()), status_of(&workspaces)),
            };
            // The device's waits show in every workspace's status (what of them does, status.rs `Take`); a
            // workspace's in its own and the plain one.
            status.on_change({
                let store = Rc::downgrade(&store);
                Rc::new(move || {
                    if let Some(store) = store.upgrade() {
                        store.invalidate_all(|t| matches!(t, Topic::Status { .. }));
                    }
                })
            });
            status.set_names(name_of(me.clone()));
            workspaces.wire_status(
                {
                    let store = Rc::downgrade(&store);
                    Rc::new(move |id: &str| {
                        if let Some(store) = store.upgrade() {
                            store.invalidate_all(|t| matches!(t, Topic::Status { workspace } if workspace.as_deref().is_none_or(|w| w == id)));
                            // What is under way says when its station is waited on to say whether it was done.
                            store.invalidate(&Topic::Doing);
                        }
                    })
                },
                name_of(me.clone()),
            );
            let kept = Kept::new(host.clone());
            let stations = Stations::new(host.clone(), center.clone() as Rc<dyn TopicSink>, wire, tracer.clone(), kept.clone(), workspaces.clone());
            let views = Views::new(host.clone(), store.clone(), email_of(me.clone()), relay_name(me.clone()), beta_of(me.clone()));
            let choose = Choose::new(host.clone(), store.clone(), data.clone(), views.clone(), check_profile(me.clone()));
            let sync = Sync::new(store.clone(), host.clone(), workspaces.clone());
            let notices = Notices::new(store.clone(), host.clone(), workspaces.clone(), email_of(me.clone()));
            let pills = crate::pill::Pills::new(host.clone(), store.clone(), views.clone());
            let jobs = crate::jobs::Polls::new(host.clone(), Rc::downgrade(&store), Rc::downgrade(&stations));
            let changelog = crate::changelog::Changelog::new(host.clone(), Rc::downgrade(&store), data.clone());
            store.set_source(Rc::new(Router { core: me.clone(), stations: stations.clone(), views: views.clone(), choose: choose.clone(), status: status.clone(), workspaces: workspaces.clone(), notices: notices.clone(), attend: attend.clone(), pills, jobs, changelog: changelog.clone(), tracer: tracer.clone(), opening: RefCell::default() }));
            sync.on_look({
                let notices = Rc::downgrade(&notices);
                let (attend, store) = (Rc::downgrade(&attend), Rc::downgrade(&store));
                Rc::new(move |stations: &[String]| {
                    let (Some(notices), Some(attend), Some(store)) = (notices.upgrade(), attend.upgrade(), store.upgrade()) else { return };
                    let added = notices.look(stations);
                    let listened = store.live_topics().iter().any(|t| matches!(t, Topic::Notify { .. }) && store.subscribed(t));
                    if attend.noticed(&added, listened) {
                        store.invalidate_all(|t| matches!(t, Topic::Notify { .. }));
                    }
                })
            });
            Inner {
                adb: crate::adb::Adb::new(host.clone(), store.clone(), mesh_source(me.clone()), credentials(me.clone())),
                connect_flow: crate::connect_flow::Flows::new(store.clone(), choose.clone()),
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
                relays: RefCell::default(),
                workspaces: workspaces.clone(),
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
                asks: crate::asks::Asks::new(host.clone()),
                changelog,
                doing: crate::doing::Doing::default(),
                slack_tokens: crate::slack_tokens::Tokens::default(),
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
        self.inner.connect_flow.disconnect(client);
        for topic in self.inner.slack_tokens.disconnect(client) { self.inner.store.invalidate(&topic); }
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
        self.receive_prepared(client, Self::prepare(message));
    }

    /// Pure input work, independent of core state. Native callers run this before enqueueing a command.
    pub fn prepare(message: ClientMessage) -> PreparedMessage {
        PreparedMessage(match message {
            ClientMessage::Call { id, call: name, params } => {
                let asked = (!crate::doing::heavy(&name)).then(|| params.clone());
                let call = parse_call(&name, params);
                Prepared::Call { id, name, asked, call }
            }
            other => Prepared::Other(other),
        })
    }

    pub fn receive_prepared(&self, client: ClientId, message: PreparedMessage) {
        match message.0 {
            Prepared::Call { id, name, asked, call } => {
                match call {
                    Err(error) => self.inner.host.emit(client, answer(id, Err(error))),
                    Ok(call) => {
                        // Under way from now until it answers, for every page to show where it is (doing.rs).
                        let doing = asked.filter(|_| crate::doing::counts(&call, &name)).map(|params| {
                            let at = self.inner.doing.start(&name, &params, self.inner.host.now_ms());
                            self.inner.store.invalidate(&Topic::Doing);
                            at
                        });
                        let resource = if let Call::StationPreview { station, port, method, path, headers, .. } = &call {
                            let workspace = self.inner.workspaces.of_station(station);
                            let key = workspace.preview_load.start(station, *port, method, path, headers, self.inner.host.now_ms());
                            self.inner.store.invalidate(&key.0);
                            Some((workspace, key))
                        } else { None };
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
                            let resource = resource.clone();
                            Rc::new(move |value: Value| {
                                if let Some((workspace, key)) = &resource {
                                    if let Some(status) = value["head"]["status"].as_u64() {
                                        workspace.preview_load.head(key, status);
                                        // Event streams stay open after they have successfully connected.
                                        if value["head"]["headers"].as_array().is_some_and(|hs| hs.iter().any(|h| h[0].as_str().is_some_and(|k| k.eq_ignore_ascii_case("content-type")) && h[1].as_str().is_some_and(|v| v.starts_with("text/event-stream")))) {
                                            workspace.preview_load.end(key, inner.host.now_ms(), None);
                                        }
                                        inner.store.invalidate(&key.0);
                                    }
                                }
                                inner.host.emit(client, CoreMessage::Value { id, value });
                            })
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
                                    let result = Abortable::new(run, registration).await.unwrap_or_else(|_| Err(CoreError::new("cancelled", t!("core-misc.call.cancelled"))));
                                    inner.calls.borrow_mut().remove(&(client, id));
                                    result
                                }
                                None => run.await,
                            };
                            if let Some((workspace, key)) = &resource {
                                if let Ok(value) = &result {
                                    if let Some(status) = value["status"].as_u64() { workspace.preview_load.head(key, status); }
                                }
                                workspace.preview_load.end(key, inner.host.now_ms(), result.as_ref().err().map(|e| e.message.as_str()));
                                inner.store.invalidate(&key.0);
                            }
                            if let Err(error) = &result {
                                span.fail();
                                span.set("error.type", error.code.clone());
                            }
                            span.end();
                            // Done, it goes; failed, it says why where it was asked a while first.
                            let failed = match (doing, &result) {
                                (Some(at), Err(error)) => {
                                    inner.doing.fail(at, &error.message);
                                    Some(at)
                                }
                                (Some(at), Ok(_)) => {
                                    inner.doing.end(at);
                                    None
                                }
                                (None, _) => None,
                            };
                            if doing.is_some() {
                                inner.store.invalidate(&Topic::Doing);
                            }
                            inner.host.emit(client, answer(id, result));
                            if let Some(at) = failed {
                                inner.host.sleep(crate::doing::FAILED_SHOWN_MS).await;
                                inner.doing.end(at);
                                inner.store.invalidate(&Topic::Doing);
                            }
                        }));
                    }
                }
            }
            Prepared::Other(ClientMessage::Subscribe { id, subscribe }) => self.inner.store.subscribe(client, id, subscribe),
            Prepared::Other(ClientMessage::Unsubscribe { id, .. }) => self.inner.store.unsubscribe(client, id),
            Prepared::Other(ClientMessage::Call { .. }) => unreachable!("calls are prepared"),
            Prepared::Other(ClientMessage::Cancel { id, .. }) => {
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
    /// The device's waits; each workspace has its own.
    status: Rc<Status>,
    workspaces: Rc<Workspaces>,
    notices: Rc<Notices>,
    attend: Rc<Attend>,
    /// What each chat says of its connection (pill.rs).
    pills: Rc<crate::pill::Pills>,
    /// A job and its output, read again while shown (jobs.rs).
    jobs: Rc<crate::jobs::Polls>,
    changelog: Rc<crate::changelog::Changelog>,
    tracer: Rc<Tracer>,
    /// Views opening: each is a trace (`chat.open`, …) until its first value goes out.
    opening: RefCell<HashMap<Topic, Span>>,
}

/// Makes a core's station wire of its host, in place of the mesh one.
type WireOf = Box<dyn FnOnce(Rc<dyn Host>) -> Rc<dyn station::StationWire>>;

/// A station's id in its address (`"<workspace>/<station>"`).
fn station_id(address: &str) -> &str {
    address.rsplit('/').next().unwrap_or(address)
}

/// Has a station's profile check itself (what a new chat offers is what the check found).
fn check_profile(core: Weak<Inner>) -> crate::choose::Check {
    Rc::new(move |station: &str, profile: &str| {
        let Some(core) = core.upgrade() else { return };
        let (station, profile) = (station.to_string(), profile.to_string());
        let run = core.clone();
        core.host.spawn(async move {
            if let Ok(addr) = StationAddr::parse(&station) {
                if let Some(Ok(op)) = crate::ops::request("profile.check", &json!({ "station": station, "id": profile })) {
                    let _ = run.stations.perform(&addr, &op).await;
                }
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

/// Each workspace's waits, for the station wire: a link's waits are its workspace's.
fn status_of(workspaces: &Rc<Workspaces>) -> StatusOf {
    let workspaces = workspaces.clone();
    Rc::new(move |workspace: &str| workspaces.of(workspace).status.clone())
}

/// Who a workspace's views take as "me": the account that reaches it, as far as `/v1/me` has told.
fn email_of(core: Weak<Inner>) -> EmailOf {
    Rc::new(move |workspace: &str| {
        let core = core.upgrade()?;
        let sub = core.workspaces.owner(workspace)?;
        core.accounts.list().into_iter().find(|a| a.sub == sub).map(|a| a.email)
    })
}

/// Whether the account that reaches a workspace is in the beta, as its `/v1/me` said (`user.beta`).
fn beta_of(core: Weak<Inner>) -> crate::views::BetaOf {
    Rc::new(move |workspace: &str| {
        let Some(core) = core.upgrade() else { return false };
        let Some(sub) = core.workspaces.owner(workspace) else { return false };
        core.data.record("me", &sub).and_then(|me| me.pointer("/user/beta").and_then(Value::as_bool)) == Some(true)
    })
}

/// What still.fail calls the relay at a host, as any account's `/v1/me` said (`relay_names`, by URL).
fn relay_name(core: Weak<Inner>) -> crate::views::RelayName {
    Rc::new(move |host: &str| {
        let core = core.upgrade()?;
        core.accounts.list().into_iter().find_map(|account| {
            let me = core.data.record("me", &account.sub)?;
            let names = me.get("relay_names")?.as_object()?.clone();
            names.into_iter().find_map(|(url, name)| {
                let url: iroh::RelayUrl = url.parse().ok()?;
                (url.host_str() == Some(host)).then(|| name.as_str().map(str::to_string)).flatten()
            })
        })
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
/// Beside each, under `<key>/<account>/<workspace>/others`, those of the mesh's other keys (mesh.rs `pinned_key`), the
/// latest first: one per relay, a few more after the device key changed.
const CREDENTIAL_OTHERS: &str = "others";
const CREDENTIAL_OTHERS_KEPT: usize = 8;

/// Where this device's push registration is kept (docs/notifications.md), and the accounts that have it.
const PUSH_KEY: &str = "push";

#[derive(Serialize, Deserialize)]
struct KeptPush {
    registration: Value,
    #[serde(default)]
    with: Vec<String>,
    /// The language the accounts were given with it (their notifications are said in it); another: given again.
    #[serde(default)]
    lang: Option<String>,
}

/// A credential as kept, with the device it names: one for another device key (the page's, taken over) is no use.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct KeptCredential {
    device: String,
    #[serde(flatten)]
    credential: Credential,
}

fn gone() -> CoreError {
    CoreError::new("closed", t!("core-misc.core.closed"))
}

/// The relays a `/v1/me` names: `relay_urls`, still.fail's own first, or `relay_url` alone from a cloud from before
/// there were several.
fn relays_of(me: &Value) -> Option<Vec<String>> {
    let all: Vec<String> = me.get("relay_urls").and_then(Value::as_array).into_iter().flatten().filter_map(|v| v.as_str().map(str::to_string)).collect();
    if !all.is_empty() {
        return Some(all);
    }
    me.get("relay_url").and_then(Value::as_str).map(|url| vec![url.to_string()])
}

impl Inner {


}

/// Holds an account's `/v1/events` socket open, reconnecting with backoff, until it is no longer wanted (the
/// task is aborted) or the account is signed out.
async fn follow_socket(core: Weak<Inner>, sub: String) {
    let mut wait = SOCKET_RETRY_MS;
    loop {
        let Some(this) = core.upgrade() else { return };
        let waiting = this.status.begin(Place::Cloud, t!("core-misc.status.connect"), true);
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
                down = if idle { t!("core-misc.socket.silent") } else { t!("core-misc.socket.dropped") };
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

pub(crate) use crate::station::encode;

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


#[cfg(test)]
mod tests;

/// Large API outputs are converted away from the native event loop, before their JSON is handed to its output lane.
pub(crate) async fn encode_bytes(host: &dyn Host, bytes: Vec<u8>) -> Result<String> {
    crate::host::background(host, move || BASE64.encode(bytes)).await
        .map_err(|error| CoreError::new("encode", error.0))
}
