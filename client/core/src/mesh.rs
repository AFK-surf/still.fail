//! This device's iroh endpoint and its links to stations.
//!
//! One endpoint per core (its secret key is the device key, kept in storage
//! under [`DEVICE_KEY`]). A link to a station is opened with this device's
//! member credential for the station's workspace (still.fail cloud's, 30 days, kept
//! on the device: see `core.rs`) and presented again every [`RENEW_MS`] on the
//! control stream, so a new one reaches stations already linked; a closed link
//! is reopened on the next request. Wire format: mesh/station/src/main.rs — ALPN
//! `stillfail/admin/1` (or `ember/admin/1`, its name before the rename); the first bi-stream carries `{"credential": …}` lines, each
//! further bi-stream one request: a JSON head line `{method, path, headers}`
//! then the body; the reply is a JSON head line `{status, headers}` then the
//! body, streamed. The web build is relay-only (browsers have no UDP).
//!
//! Error codes: `credential_refused` when the station turned the credential down,
//! `mesh` for everything on the way (unreachable, stream broken).

use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::{Rc, Weak};
use std::sync::Arc;

use futures::channel::oneshot;
use futures::future::{Either, LocalBoxFuture, Shared};
use futures::lock::Mutex;
use futures::{FutureExt, pin_mut};

use iroh::endpoint::{ConnectOptions, ConnectionError, QuicTransportConfig, RecvStream, SendStream, presets::Minimal};
use iroh::{Endpoint, EndpointAddr, PublicKey, RelayMode, RelayUrl, SecretKey};
use serde_json::{Value, json};

use crate::cloud::Credential;
use crate::error::{CoreError, Result};
use crate::host::Host;
use crate::trace::{Kind, Tracer};

/// The mDNS service stations announce themselves under (mesh/station's `MDNS_SERVICE`).
#[cfg(not(target_arch = "wasm32"))]
const MDNS_SERVICE: &str = "ember";

pub const DEVICE_KEY: &str = "device";
pub const ALPN: &[u8] = b"stillfail/admin/1";
/// The same protocol under its name from before the rename, which stations from before it only know: offered too, so
/// a new client reaches an old station (a new one takes either and picks ALPN).
pub const FORMER_ALPN: &[u8] = b"ember/admin/1";
pub const RENEW_MS: u64 = 5 * 60_000;
/// How long a link is tried before the station is taken for not there.
pub const CONNECT_TIMEOUT_MS: u64 = 10_000;
/// How long a link, tried as the UI comes back (wake.rs), has to answer before it is taken for gone (if the new one
/// opened beside it has not opened yet either).
pub const PROBE_MS: u64 = 5_000;
/// How long a link that lost to a new one is kept before it is closed: what is still on it (a write to a station that
/// does not keep writes to once, which is not asked again) may yet be answered.
pub const RETIRE_MS: u64 = 10_000;
/// The endpoint is bound anew (`Mesh::rebind`) at most this often.
pub const REBIND_MS: u64 = 5_000;
/// What a link not opened in [`CONNECT_TIMEOUT_MS`] fails with.
const NO_ANSWER: &str = "连不上这台 station：没有回应";

/// A reply head is a line of JSON; anything longer is not a station talking.
const MAX_HEAD: usize = 64 * 1024;

/// This device's credential for a station's workspace, for its id (hex); `fresh` asks still.fail cloud for a new one
/// rather than the one kept (the station refused that one).
pub type CredentialSource = Rc<dyn Fn(String, bool) -> LocalBoxFuture<'static, Result<Credential>>>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RequestHead {
    pub method: String,
    /// Path under the station's admin API, e.g. `/admin/api/overview`.
    pub path: String,
    pub headers: Vec<(String, String)>,
}

fn mesh_error(message: String) -> CoreError {
    CoreError::new("mesh", message)
}

/// An opening shared by everyone who asks for the same station meanwhile.
type Opening = Shared<LocalBoxFuture<'static, Result<Rc<Link>>>>;

/// Where a link tried beside an opening goes (`hedge`).
type HedgeTx = oneshot::Sender<Result<Rc<Link>>>;

/// A link tried beside an opening that is still under way (`hedge`): what it opens is the opening's, if it is first.
struct Hedge {
    /// Which opening it goes with (`Mesh::openings`).
    serial: u64,
    credentials: CredentialSource,
    /// Taken when a link is tried beside it; one try per opening.
    tx: Option<HedgeTx>,
}

pub struct Mesh {
    host: Rc<dyn Host>,
    tracer: Rc<Tracer>,
    /// still.fail's relays, its own first (`relays`).
    relays: Vec<String>,
    /// Replaced when `migrate` brings another device key.
    endpoint: RefCell<Endpoint>,
    links: RefCell<HashMap<String, Opening>>,
    /// Told when `links` changes (a link opened, one put in place of another, one dropped): see `replaced`.
    changed: RefCell<Vec<futures::channel::oneshot::Sender<()>>>,
    /// Stations whose link is being tried against a new one (`race`).
    racing: RefCell<std::collections::HashSet<String>>,
    /// The device key, for binding the endpoint anew (`rebind`).
    secret: Cell<[u8; 32]>,
    /// The last link tried on this endpoint was not answered: the endpoint itself is suspect (its relay connection
    /// gone with nothing said, as a phone's after it slept or changed networks). Cleared by a link that opens.
    stuck: Rc<Cell<bool>>,
    /// When the endpoint was last bound anew (`REBIND_MS`).
    rebound_at: Cell<f64>,
    /// Where stations are known to be without looking them up (tests): told to each endpoint bound.
    known: RefCell<Vec<EndpointAddr>>,
    /// The openings under way, by station: a link tried beside each as the UI asks (`hedge`).
    hedges: Rc<RefCell<HashMap<String, Hedge>>>,
    serials: Cell<u64>,
}

impl Mesh {
    /// Binds the endpoint with the stored device key (making and storing one the first time).
    /// No relays binds without one (direct addresses only: tests, a LAN).
    pub async fn new(host: Rc<dyn Host>, tracer: Rc<Tracer>, relays: &[String]) -> Result<Rc<Mesh>> {
        let stored = host.storage_get(DEVICE_KEY).await?;
        let secret: [u8; 32] = match stored.and_then(|bytes| bytes.try_into().ok()) {
            Some(secret) => secret,
            // None yet (or not a key at all): a new device.
            None => {
                let mut secret = [0u8; 32];
                host.random_bytes(&mut secret);
                host.storage_set(DEVICE_KEY, secret.to_vec()).await?;
                secret
            }
        };
        let endpoint = bind(&secret, relays).await?;
        let mesh = Rc::new(Mesh {
            host: host.clone(),
            tracer,
            relays: relays.to_vec(),
            endpoint: RefCell::new(endpoint),
            links: RefCell::default(),
            changed: RefCell::default(),
            racing: RefCell::default(),
            secret: Cell::new(secret),
            stuck: Rc::default(),
            rebound_at: Cell::new(f64::NEG_INFINITY),
            known: RefCell::default(),
            hedges: Rc::default(),
            serials: Cell::new(0),
        });
        host.spawn(watch(host.clone(), Rc::downgrade(&mesh)).boxed_local());
        Ok(mesh)
    }

    /// The links open now, by station id.
    fn open_links(&self) -> Vec<(String, Rc<Link>)> {
        self.links.borrow().iter().filter_map(|(id, opening)| match opening.peek() {
            Some(Ok(link)) if link.usable() => Some((id.clone(), link.clone())),
            _ => None,
        }).collect()
    }

    /// Waits `ms` on this device's clock.
    pub fn sleep(&self, ms: u64) -> LocalBoxFuture<'static, ()> {
        self.host.sleep(ms)
    }

    /// This device's clock.
    pub fn now_ms(&self) -> f64 {
        self.host.now_ms()
    }

    /// The station's link now, if one is open.
    pub fn current(&self, station_id: &str) -> Option<Rc<Link>> {
        self.links.borrow().get(station_id).and_then(|o| o.peek().and_then(|l| l.as_ref().ok().cloned()))
    }

    /// Whether `link` is the station's link now.
    fn is_current(&self, station_id: &str, link: &Rc<Link>) -> bool {
        let current = self.links.borrow().get(station_id).and_then(|o| o.peek().and_then(|l| l.as_ref().ok().cloned()));
        current.is_some_and(|c| Rc::ptr_eq(&c, link))
    }

    /// Lets go of the link to a station if it is still `link` (not one opened since).
    fn drop_if(&self, station_id: &str, link: &Rc<Link>) {
        if self.is_current(station_id, link) {
            self.drop_link(station_id);
        }
    }

    fn notify(&self) {
        for waiter in self.changed.take() {
            let _ = waiter.send(());
        }
    }

    /// Resolves once `link` is no longer the station's link: another put in its place (it lost to a new one, `race`),
    /// or it was dropped. What is on it is then asked again on the way there now (station.rs `MeshWire`), and a stream
    /// on it is opened again there (`follow_events`).
    pub fn replaced(self: &Rc<Self>, station_id: &str, link: &Rc<Link>) -> LocalBoxFuture<'static, ()> {
        let (mesh, id, link) = (Rc::downgrade(self), station_id.to_string(), link.clone());
        async move {
            loop {
                let change = {
                    let Some(mesh) = mesh.upgrade() else { return futures::future::pending().await };
                    if !mesh.is_current(&id, &link) {
                        return;
                    }
                    let (tx, rx) = futures::channel::oneshot::channel();
                    mesh.changed.borrow_mut().push(tx);
                    rx
                };
                if change.await.is_err() {
                    return futures::future::pending().await;
                }
            }
        }
        .boxed_local()
    }

    /// Puts `new` in place of `old` as the station's link (if `old` still is: else `new` is not needed), and closes
    /// `old` after [`RETIRE_MS`].
    fn switch(&self, station_id: &str, old: &Rc<Link>, new: Rc<Link>) {
        if !self.is_current(station_id, old) {
            new.close();
            return;
        }
        let ready: Opening = futures::future::ready(Ok(new)).boxed_local().shared();
        let _ = ready.clone().now_or_never();
        self.links.borrow_mut().insert(station_id.to_string(), ready);
        self.notify();
        let (host, old) = (self.host.clone(), old.clone());
        self.host.spawn(
            async move {
                host.sleep(RETIRE_MS).await;
                old.conn.close(0u32.into(), b"replaced");
            }
            .boxed_local(),
        );
    }

    /// The device key's public half, hex: what credentials name.
    pub fn device_id(&self) -> String {
        hex::encode(self.endpoint.borrow().id().as_bytes())
    }

    /// The iroh endpoint itself.
    pub fn endpoint(&self) -> Endpoint {
        self.endpoint.borrow().clone()
    }

    /// Tells this endpoint, and each bound after it, where a station is (when there is no relay: tests, a LAN).
    pub fn add_addr(&self, addr: EndpointAddr) {
        if let Ok(lookup) = self.endpoint().address_lookup() {
            lookup.add(iroh::address_lookup::MemoryLookup::from_endpoint_info([addr.clone()]));
        }
        self.known.borrow_mut().push(addr);
    }

    /// Whether some station's link is open on the endpoint now: then the endpoint is not what is wrong.
    fn any_open(&self) -> bool {
        !self.open_links().is_empty()
    }

    /// The endpoint bound anew with the same key (new sockets, a new relay connection), the old one closed: for when
    /// what is tried on it is not answered and nothing on it is open (`stuck`), which iroh does not find out itself
    /// when its relay connection died with nothing said. At most once in [`REBIND_MS`]; the endpoint then.
    async fn rebind(&self) -> Endpoint {
        let now = self.host.now_ms();
        if now - self.rebound_at.get() < REBIND_MS as f64 {
            return self.endpoint();
        }
        self.rebound_at.set(now);
        let endpoint = match bind(&self.secret.get(), &self.relays).await {
            Ok(endpoint) => endpoint,
            Err(_) => return self.endpoint(),
        };
        if let Ok(lookup) = endpoint.address_lookup() {
            lookup.add(iroh::address_lookup::MemoryLookup::from_endpoint_info(self.known.borrow().clone()));
        }
        let old = self.endpoint.replace(endpoint.clone());
        self.stuck.set(false);
        // Two endpoints of one key on one relay would push each other off it: the old one goes now, and what was still
        // being tried on it fails (an opening with a link tried beside it waits for that one).
        self.host.spawn(async move { old.close().await }.boxed_local());
        endpoint
    }

    /// The link to a station, opening it (or reopening a closed one) with a credential from `credentials`.
    pub async fn link(&self, station_id: &str, credentials: CredentialSource) -> Result<Rc<Link>> {
        let existing = self.links.borrow().get(station_id).cloned();
        // Opening anew after the station refused the credential: a new one is asked of still.fail cloud.
        let mut fresh = false;
        if let Some(opening) = existing {
            match opening.peek() {
                None => return opening.await,
                Some(Ok(link)) if link.usable() => return Ok(link.clone()),
                // Failed, closed, or its credential refused: open anew.
                Some(Ok(link)) => fresh = link.refused.borrow().is_some(),
                Some(Err(error)) => fresh = error.code == "credential_refused",
            }
        }
        // A span of the request that needed the link; the credential it asks still.fail cloud for is part of it.
        let mut span = self.tracer.span("mesh.connect", Kind::Internal);
        span.set("stillfail.station", station_id.to_string());
        // The last try on this endpoint was not answered and nothing is open on it: tried on one bound anew.
        let endpoint = if self.stuck.get() && !self.any_open() {
            span.set("stillfail.rebound", true);
            self.rebind().await
        } else {
            self.endpoint()
        };
        span.set("stillfail.relay", relay_status(&endpoint));
        let serial = self.serials.get() + 1;
        self.serials.set(serial);
        let (tx, hedged) = oneshot::channel();
        self.hedges.borrow_mut().insert(station_id.to_string(), Hedge { serial, credentials: credentials.clone(), tx: Some(tx) });
        let first = self.tracer.instrument(Some(span.context()), open(self.host.clone(), endpoint.clone(), self.relays.clone(), station_id.to_string(), credentials, fresh));
        let (hedges, stuck, id) = (self.hedges.clone(), self.stuck.clone(), station_id.to_string());
        let opening = async move {
            // The first link that opens, of this one and one tried beside it (`hedge`); failing, the other's result.
            let link = match futures::future::select(first, hedged).await {
                Either::Left((Ok(link), _)) => Ok(link),
                Either::Left((Err(error), hedged)) => {
                    let tried = hedges.borrow_mut().get_mut(&id).is_some_and(|h| h.serial == serial && h.tx.take().is_none());
                    if tried { hedged.await.unwrap_or(Err(error.clone())).map_err(|_| error) } else { Err(error) }
                }
                Either::Right((Ok(Ok(link)), _)) => {
                    span.set("stillfail.hedged", true);
                    Ok(link)
                }
                Either::Right((_, first)) => first.await,
            };
            if hedges.borrow().get(&id).is_some_and(|h| h.serial == serial) {
                hedges.borrow_mut().remove(&id);
            }
            match &link {
                Ok(link) => {
                    stuck.set(false);
                    if let Some(path) = link.path() {
                        span.set("stillfail.path", path);
                    }
                }
                Err(error) => {
                    if error.message == NO_ANSWER {
                        stuck.set(true);
                    }
                    span.fail();
                    span.set("error.type", error.code.clone());
                    span.set("stillfail.relay", relay_status(&endpoint));
                }
            }
            span.end();
            link
        }
        .boxed_local()
        .shared();
        self.links.borrow_mut().insert(station_id.to_string(), opening.clone());
        self.notify();
        opening.await
    }

    /// Closes the link to a station, if one is open or opening: taken for gone (wake.rs), so the next request opens
    /// another rather than waiting on this one. Requests on it fail (a read is asked once more, on the new one).
    pub fn drop_link(&self, station_id: &str) {
        let opening = self.links.borrow_mut().remove(station_id);
        self.notify();
        if let Some(Ok(link)) = opening.as_ref().and_then(|o| o.peek()) {
            link.conn.close(0u32.into(), b"woke");
        }
    }

    /// Takes over the device key a page kept before the core existed (32 bytes).
    ///
    /// The page's key wins: it is stored whenever it differs from the stored
    /// one (which may be a key this core made before the page handed its own
    /// over), the endpoint is rebound with it and open links are closed (they
    /// reopen under the new id). The same key again changes nothing.
    pub async fn migrate(&self, secret: Vec<u8>) -> Result<()> {
        let secret: [u8; 32] = secret.try_into().map_err(|_| CoreError::invalid("设备密钥应为 32 字节"))?;
        if self.host.storage_get(DEVICE_KEY).await?.as_deref() == Some(&secret[..]) {
            return Ok(());
        }
        let endpoint = bind(&secret, &self.relays).await?;
        self.host.storage_set(DEVICE_KEY, secret.to_vec()).await?;
        self.secret.set(secret);
        let old = self.endpoint.replace(endpoint);
        let links: Vec<Opening> = self.links.borrow_mut().drain().map(|(_, opening)| opening).collect();
        self.notify();
        for opening in links {
            if let Some(Ok(link)) = opening.peek() {
                link.conn.close(0u32.into(), b"device key replaced");
            }
        }
        self.host.spawn(async move { old.close().await }.boxed_local());
        Ok(())
    }
}

/// What the mesh does as the UI comes back or the network changes (wake.rs; also a person's 重试): iroh is told (on
/// Android it cannot see the network change itself, and after a long sleep its relay connection is suspect too), each
/// open link races a new one (`race`), and each link still being opened has another tried beside it (`hedge`).
/// Nothing waits to learn whether a link is gone, or a try unanswered, before there is another way to its station.
async fn watch(host: Rc<dyn Host>, mesh: Weak<Mesh>) {
    loop {
        let wake = host.woken().await;
        let Some(this) = mesh.upgrade() else { return };
        if !wake.suspects_connections() {
            continue;
        }
        let endpoint = this.endpoint();
        host.spawn(async move { endpoint.network_change().await }.boxed_local());
        for (id, link) in this.open_links() {
            if !this.racing.borrow_mut().insert(id.clone()) {
                continue;
            }
            host.spawn(race(host.clone(), mesh.clone(), id, link).boxed_local());
        }
        let pending: Vec<(String, CredentialSource, HedgeTx)> =
            this.hedges.borrow_mut().iter_mut().filter_map(|(id, h)| h.tx.take().map(|tx| (id.clone(), h.credentials.clone(), tx))).collect();
        for (id, credentials, tx) in pending {
            host.spawn(hedge(host.clone(), mesh.clone(), id, credentials, tx).boxed_local());
        }
    }
}

/// A link tried beside an opening still under way: on an endpoint bound anew if nothing is open on this one (then it
/// is as likely the endpoint as the station that does not answer), else on this one. It is the opening's if it opens
/// first; opened after, it is let go.
async fn hedge(host: Rc<dyn Host>, mesh: Weak<Mesh>, id: String, credentials: CredentialSource, tx: HedgeTx) {
    let Some(this) = mesh.upgrade() else { return };
    let endpoint = if this.any_open() { this.endpoint() } else { this.rebind().await };
    let (relays, tracer) = (this.relays.clone(), this.tracer.clone());
    drop(this);
    let mut span = tracer.span("mesh.hedge", Kind::Internal);
    span.set("stillfail.station", id.clone());
    span.set("stillfail.relay", relay_status(&endpoint));
    let opened = tracer.instrument(Some(span.context()), open(host, endpoint, relays, id, credentials, false)).await;
    if opened.is_err() {
        span.fail();
    }
    span.end();
    if let Err(Ok(late)) = tx.send(opened) {
        late.close();
    }
}

/// The endpoint's home relays and whether it is connected to them, for a span: `<url> up`, `<url> down`, or `none`.
fn relay_status(endpoint: &Endpoint) -> String {
    use iroh::Watcher;
    let status = endpoint.home_relay_status().get();
    if status.is_empty() {
        return "none".into();
    }
    status.iter().map(|s| format!("{} {}", s.url(), if s.is_connected() { "up" } else { "down" })).collect::<Vec<_>>().join(", ")
}

/// A link suspect (the UI back after long away, the network changed) against a new one opened beside it at once: the
/// old one is asked to answer (its credential presented again, `Link::answers`) while the new one opens. The old one
/// answering first keeps it (the new one is let go before it is used); the new one opening first takes its place
/// (`Mesh::switch`: what was on the old one is asked again on it); neither, the station is not reached (the link is
/// dropped, the next request opens anew). Either way no more than one round trip or one connection's opening.
async fn race(host: Rc<dyn Host>, mesh: Weak<Mesh>, id: String, old: Rc<Link>) {
    enum Won {
        Old,
        New(Rc<Link>),
        Neither,
    }
    let Some(this) = mesh.upgrade() else { return };
    let (endpoint, relays, tracer) = (this.endpoint(), this.relays.clone(), this.tracer.clone());
    drop(this);
    let mut span = tracer.span("mesh.race", Kind::Internal);
    span.set("stillfail.station", id.clone());
    let fresh = tracer.instrument(Some(span.context()), open(host.clone(), endpoint, relays, id.clone(), old.credentials.clone(), false));
    let probe = old.answers(host.as_ref());
    pin_mut!(fresh, probe);
    let won = match futures::future::select(probe, fresh).await {
        Either::Left((true, _)) => Won::Old,
        Either::Left((false, fresh)) => match fresh.await {
            Ok(new) => Won::New(new),
            Err(_) => Won::Neither,
        },
        Either::Right((Ok(new), _)) => Won::New(new),
        Either::Right((Err(_), probe)) => {
            if probe.await {
                Won::Old
            } else {
                Won::Neither
            }
        }
    };
    let Some(this) = mesh.upgrade() else { return };
    this.racing.borrow_mut().remove(&id);
    span.set("stillfail.race", match &won {
        Won::Old => "old",
        Won::New(_) => "new",
        Won::Neither => "neither",
    });
    span.end();
    match won {
        Won::Old => {}
        Won::New(new) => this.switch(&id, &old, new),
        Won::Neither => this.drop_if(&id, &old),
    }
}

/// The endpoint for a device key. On wasm iroh has no IP transports, so this
/// is relay-only like mesh/web, through ember's relay. Natively it also binds
/// UDP and goes direct, and finds stations without still.fail cloud: on the LAN by
/// mDNS (no relay needed at all), and which relay a station is on by the
/// Mainline DHT (a station whose relay is not ember's, ember's being down).
/// Its home relay is the nearest of still.fail's (see `relay_mode`).
async fn bind(secret: &[u8; 32], relays: &[String]) -> Result<Endpoint> {
    let builder = Endpoint::builder(Minimal).secret_key(SecretKey::from_bytes(secret)).relay_mode(relay_mode(relays)?).transport_config(transport());
    // No relay (tests on localhost): nothing to look up either.
    #[cfg(not(target_arch = "wasm32"))]
    let builder = if relays.is_empty() {
        builder
    } else {
        builder
            // Stations on the LAN, among ember's own (`_ember._udp`, as the station announces itself: mesh/station); a
            // device is never dialed, so it only asks. Answers to a query stop after a few, so every endpoint that
            // answers is one more a station may be crowded out by for a round (0.7 s).
            .address_lookup(iroh_mdns_address_lookup::MdnsAddressLookup::builder().service_name(MDNS_SERVICE).advertise(false))
            .address_lookup(iroh_mainline_address_lookup::DhtAddressLookup::builder().no_publish())
    };
    builder.bind().await.map_err(|e| mesh_error(format!("无法启动本机的 mesh 端点：{e}")))
}

/// still.fail's relays only, as the station's and the browser's, iroh homing on the nearest (the one inside mainland
/// China there, Cloudflare's abroad): with iroh's public ones beside them iroh could pick one of those as home, and a
/// phone on one was seen not to reach its station for minutes at a time (2026-09-30). A station moved to a public
/// relay (its own down: mesh/station `keep_relays`) is still reached there, the DHT saying which: a relay in no map is
/// dialed all the same.
fn relay_mode(relays: &[String]) -> Result<RelayMode> {
    if relays.is_empty() {
        return Ok(RelayMode::Disabled);
    }
    Ok(RelayMode::Custom(iroh::RelayMap::from_iter(relay_urls(relays)?)))
}

fn relay_urls(relays: &[String]) -> Result<Vec<RelayUrl>> {
    relays.iter().map(|url| url.parse().map_err(|e| mesh_error(format!("中继地址不对：{e}")))).collect()
}

/// Through a relay a round trip is hundreds of milliseconds, and QUIC's default first window
/// (~14 KB) would spread a chat's first page over several of them. Starting at 256 KB sends
/// what a screen needs in one round trip; larger transfers still grow the window as usual.
/// The station does the same (mesh/station/src/main.rs).
pub const INITIAL_WINDOW: u64 = 256 * 1024;

pub fn transport() -> QuicTransportConfig {
    let mut cubic = noq_proto::congestion::CubicConfig::default();
    cubic.initial_window(INITIAL_WINDOW);
    QuicTransportConfig::builder().congestion_controller_factory(Arc::new(cubic)).build()
}

/// Connects, presents the first credential, and starts renewing it.
///
/// Nothing waits on anything it does not need: the credential is asked of ember
/// cloud while the connection is being made (to the relay this device already
/// uses), and the link is handed out as soon as the credential is sent — the
/// station reads a connection's first stream (the credential) before any request
/// stream, so requests can follow at once. If it refuses, it closes the
/// connection, the requests on it fail, and the next `Mesh::link` starts over.
async fn open(host: Rc<dyn Host>, endpoint: Endpoint, relays: Vec<String>, station_id: String, credentials: CredentialSource, fresh: bool) -> Result<Rc<Link>> {
    let id: [u8; 32] = hex::decode(&station_id).ok().and_then(|b| b.try_into().ok()).ok_or_else(|| CoreError::invalid(format!("station id 不对：{station_id}")))?;
    let id = PublicKey::from_bytes(&id).map_err(|_| CoreError::invalid(format!("station id 不对：{station_id}")))?;
    let device = hex::encode(endpoint.id().as_bytes());
    let connecting = async {
        // No waiting for our own relay link: the endpoint came up as soon as the relay was known (Core warms it),
        // and in the browser `online()` does not report it, so a wait would only ever run out.
        // On every relay of still.fail's: the station is on the one nearest it, which need not be ours (a station in
        // mainland China and a phone abroad), and the first packets go out on all of them, the station answering on
        // the one it heard them on.
        let mut addr = EndpointAddr::new(id);
        for relay in relay_urls(&relays)? {
            addr = addr.with_relay_url(relay);
        }
        let options = ConnectOptions::new().with_additional_alpns(vec![FORMER_ALPN.to_vec()]);
        let connecting = endpoint.connect_with_opts(addr, ALPN, options).await.map_err(|e| mesh_error(format!("连不上这台 station：{e}")))?;
        connecting.await.map_err(|e| mesh_error(format!("连不上这台 station：{e}")))
    };
    // A station that is not there is never said to be gone (a relay drops what is sent to someone not on it): the
    // try gives up after CONNECT_TIMEOUT_MS rather than QUIC's idle 30 s, so it is known to be down soon.
    let connecting = {
        let timeout = host.sleep(CONNECT_TIMEOUT_MS);
        async move {
            pin_mut!(connecting);
            match futures::future::select(connecting, timeout).await {
                Either::Left((connected, _)) => connected,
                Either::Right(_) => Err(mesh_error(NO_ANSWER.into())),
            }
        }
    };
    let (credential, conn) = futures::join!(credentials(device.clone(), fresh), connecting);
    let conn = conn?;
    let credential = match credential {
        Ok(credential) => credential,
        Err(error) => {
            conn.close(0u32.into(), b"no credential");
            return Err(error);
        }
    };
    let (send, recv) = conn.open_bi().await.map_err(|e| mesh_error(format!("连不上这台 station：{e}")))?;
    let mut control = Control { send, recv, carry: Vec::new() };
    control.send(&credential.credential).await?;
    let link = Rc::new(Link {
        conn,
        control: Mutex::new(control),
        renewal_failed: Cell::new(false),
        refused: RefCell::new(None),
        credential: RefCell::new(credential.credential.clone()),
        credentials: credentials.clone(),
    });
    // The station's answer to the first credential, while requests already go: a refusal closes the link.
    let answered = link.clone();
    host.spawn(
        async move {
            let answer = answered.control.lock().await.answer().await;
            if let Err(error) = answer {
                answered.renewal_failed.set(true);
                *answered.refused.borrow_mut() = Some(error);
                answered.conn.close(0u32.into(), b"credential refused");
            }
        }
        .boxed_local(),
    );
    host.spawn(renew(host.clone(), link.clone(), credentials, device).boxed_local());
    Ok(link)
}

/// Presents a fresh credential every RENEW_MS until the link closes. If one cannot
/// be had or is refused, the link is left to run out its current credential and
/// the next `Mesh::link` opens another.
async fn renew(host: Rc<dyn Host>, link: Rc<Link>, credentials: CredentialSource, device: String) {
    loop {
        let wait = host.sleep(RENEW_MS);
        let closed = link.conn.closed();
        pin_mut!(closed);
        if let Either::Right(_) = futures::future::select(wait, closed).await {
            return;
        }
        let renewed = match credentials(device.clone(), false).await {
            Ok(credential) => {
                let answer = link.control.lock().await.exchange(&credential.credential).await.map(|_| ());
                if answer.is_ok() {
                    *link.credential.borrow_mut() = credential.credential;
                }
                answer
            }
            Err(error) => Err(error),
        };
        if renewed.is_err() {
            link.renewal_failed.set(true);
            return;
        }
    }
}

/// The control stream: credential lines out, answers back.
struct Control {
    send: SendStream,
    recv: RecvStream,
    carry: Vec<u8>,
}

impl Control {
    /// Sends a credential line and returns the station's answer; fails if it refused.
    async fn exchange(&mut self, credential: &str) -> Result<Value> {
        self.send(credential).await?;
        self.answer().await
    }

    async fn send(&mut self, credential: &str) -> Result<()> {
        let line = format!("{}\n", json!({ "credential": credential }));
        self.send.write_all(line.as_bytes()).await.map_err(|e| mesh_error(format!("授权没送到 station：{e}")))
    }

    /// The station's answer to the credential last sent; fails if it refused.
    async fn answer(&mut self) -> Result<Value> {
        let answer = read_line(&mut self.recv, &mut self.carry).await?.ok_or_else(|| mesh_error("station 关闭了授权通道".into()))?;
        let answer: Value = serde_json::from_str(&answer).map_err(|e| mesh_error(format!("station 的授权答复看不懂：{e}")))?;
        if let Some(error) = answer.get("error") {
            let reason = error.as_str().map(str::to_string).unwrap_or_else(|| error.to_string());
            return Err(CoreError::new("credential_refused", format!("station 拒绝了授权：{reason}")));
        }
        Ok(answer)
    }
}

/// Reads one newline-terminated line; whatever followed stays in `carry`.
async fn read_line(recv: &mut RecvStream, carry: &mut Vec<u8>) -> Result<Option<String>> {
    loop {
        if let Some(i) = carry.iter().position(|&b| b == b'\n') {
            let line: Vec<u8> = carry.drain(..=i).collect();
            return Ok(Some(String::from_utf8_lossy(&line[..line.len() - 1]).into_owned()));
        }
        if carry.len() > MAX_HEAD {
            return Err(mesh_error("station 发来的头部太长".into()));
        }
        let mut buf = [0u8; 8192];
        match recv.read(&mut buf).await.map_err(|e| mesh_error(format!("读取 station 的回复失败：{e}")))? {
            Some(n) => carry.extend_from_slice(&buf[..n]),
            None if carry.is_empty() => return Ok(None),
            None => return Err(mesh_error("station 的回复在一行中间断了".into())),
        }
    }
}

pub struct Link {
    conn: iroh::endpoint::Connection,
    control: Mutex<Control>,
    renewal_failed: Cell<bool>,
    /// The station's refusal of the first credential, once it answered: what the link's requests fail with.
    refused: RefCell<Option<CoreError>>,
    /// The credential last presented, which [`Link::answers`] presents again.
    credential: RefCell<String>,
    /// Where its credentials come from: a link opened beside it (`race`) takes the same.
    credentials: CredentialSource,
}

impl Link {
    /// One request on its own stream.
    pub async fn request(&self, head: RequestHead, body: Vec<u8>) -> Result<Reply> {
        let result = self.send_request(head, body).await;
        // A request lost to a refused credential says so, not just that the connection went.
        match (&result, self.refused.borrow().as_ref()) {
            (Err(_), Some(refused)) => Err(refused.clone()),
            _ => result,
        }
    }

    async fn send_request(&self, head: RequestHead, body: Vec<u8>) -> Result<Reply> {
        let sent = |e: &dyn std::fmt::Display| mesh_error(format!("请求没送到 station：{e}"));
        let (mut send, mut recv) = self.conn.open_bi().await.map_err(|e| sent(&e))?;
        let headers: serde_json::Map<String, Value> = head.headers.into_iter().map(|(k, v)| (k, Value::String(v))).collect();
        let line = format!("{}\n", json!({ "method": head.method, "path": head.path, "headers": headers }));
        send.write_all(line.as_bytes()).await.map_err(|e| sent(&e))?;
        if !body.is_empty() {
            send.write_all(&body).await.map_err(|e| sent(&e))?;
        }
        send.finish().map_err(|e| sent(&e))?;
        let mut carry = Vec::new();
        let line = read_line(&mut recv, &mut carry).await?.ok_or_else(|| mesh_error("station 没有回应".into()))?;
        let reply: Value = serde_json::from_str(&line).map_err(|e| mesh_error(format!("station 的回复看不懂：{e}")))?;
        let status = reply["status"].as_u64().and_then(|s| u16::try_from(s).ok()).ok_or_else(|| mesh_error("station 的回复没有状态码".into()))?;
        let headers = match &reply["headers"] {
            Value::Object(map) => map.iter().map(|(k, v)| (k.clone(), v.as_str().map(str::to_string).unwrap_or_else(|| v.to_string()))).collect(),
            _ => Vec::new(),
        };
        Ok(Reply { status, headers, recv, carry, done: false })
    }

    /// A preview page's WebSocket on its own stream (mesh/station's `socket`): the head line says `"socket": true` and
    /// the stream stays open both ways. Answers the station's reply (101 once the service took it; its body then the
    /// service's frames) and the half the client's frames go out on.
    pub async fn socket(&self, head: RequestHead) -> Result<(Reply, SocketSend)> {
        let sent = |e: &dyn std::fmt::Display| mesh_error(format!("请求没送到 station：{e}"));
        let (mut send, mut recv) = self.conn.open_bi().await.map_err(|e| sent(&e))?;
        let headers: serde_json::Map<String, Value> = head.headers.into_iter().map(|(k, v)| (k, Value::String(v))).collect();
        let line = format!("{}\n", json!({ "method": head.method, "path": head.path, "headers": headers, "socket": true }));
        send.write_all(line.as_bytes()).await.map_err(|e| sent(&e))?;
        let mut carry = Vec::new();
        let line = read_line(&mut recv, &mut carry).await?.ok_or_else(|| mesh_error("station 没有回应".into()))?;
        let reply: Value = serde_json::from_str(&line).map_err(|e| mesh_error(format!("station 的回复看不懂：{e}")))?;
        let status = reply["status"].as_u64().and_then(|s| u16::try_from(s).ok()).ok_or_else(|| mesh_error("station 的回复没有状态码".into()))?;
        let headers = match &reply["headers"] {
            Value::Object(map) => map.iter().map(|(k, v)| (k.clone(), v.as_str().map(str::to_string).unwrap_or_else(|| v.to_string()))).collect(),
            _ => Vec::new(),
        };
        Ok((Reply { status, headers, recv, carry, done: false }, SocketSend(send)))
    }

    /// Why the link closed, if it did.
    pub fn closed(&self) -> Option<String> {
        self.conn.close_reason().map(|reason| close_message(&reason))
    }

    /// Closes the connection now (its streams end with it).
    pub fn close(&self) {
        self.conn.close(0u32.into(), b"closed");
    }

    /// How the connection runs now: `relay`, or `direct` once hole punching found a way.
    pub fn path(&self) -> Option<&'static str> {
        self.conn.paths().iter().find(|p| p.is_selected()).map(|p| if p.is_relay() { "relay" } else { "direct" })
    }

    /// How the connection runs, as QUIC measures it: the path it takes now, its round trip, and what went over it
    /// (every datagram, both ways, since it opened), for the station's card (station.rs `Topic::Net`).
    pub fn net(&self) -> LinkNet {
        let paths = self.conn.paths();
        let selected = paths.iter().find(|p| p.is_selected());
        let relay = selected.as_ref().and_then(|p| match p.remote_addr() {
            iroh::TransportAddr::Relay(url) => Some(url.host_str().unwrap_or_default().to_string()),
            _ => None,
        });
        let stats = self.conn.stats();
        LinkNet {
            path: selected.as_ref().map(|p| if p.is_relay() { "relay" } else { "direct" }),
            relay,
            rtt_ms: selected.as_ref().map(|p| p.rtt().as_secs_f64() * 1000.0),
            rx_bytes: stats.udp_rx.bytes,
            tx_bytes: stats.udp_tx.bytes,
            tx_packets: stats.udp_tx.datagrams,
            lost_packets: stats.lost_packets,
        }
    }

    /// Whether the station answers on it within [`PROBE_MS`]: the credential presented again (any station answers
    /// that, one line back), a round trip that also shows the way there is open.
    async fn answers(&self, host: &dyn Host) -> bool {
        let credential = self.credential.borrow().clone();
        let exchange = async move { self.control.lock().await.exchange(&credential).await.is_ok() };
        pin_mut!(exchange);
        match futures::future::select(exchange, host.sleep(PROBE_MS)).await {
            Either::Left((answered, _)) => answered,
            Either::Right(_) => false,
        }
    }

    /// Open, and its credential still being renewed.
    fn usable(&self) -> bool {
        self.conn.close_reason().is_none() && !self.renewal_failed.get()
    }
}

/// A link's connection as [`Link::net`] reads it.
#[derive(Clone, Debug, PartialEq)]
pub struct LinkNet {
    /// `relay` or `direct`; None before a path is chosen.
    pub path: Option<&'static str>,
    /// The relay's host, on a relay path.
    pub relay: Option<String>,
    pub rtt_ms: Option<f64>,
    pub rx_bytes: u64,
    pub tx_bytes: u64,
    pub tx_packets: u64,
    pub lost_packets: u64,
}

/// In words, with the station's own reasons (mesh/station) spelled out.
fn close_message(reason: &ConnectionError) -> String {
    match reason {
        ConnectionError::ApplicationClosed(close) => match &close.reason[..] {
            b"credential_refused" => "station 拒绝了授权".into(),
            b"credential_revoked" => "授权已被撤销".into(),
            b"credential_expired" => "授权已过期".into(),
            b"station_removed" => "这台 station 已被移出 workspace".into(),
            other => format!("station 断开了连接：{}", String::from_utf8_lossy(other)),
        },
        ConnectionError::LocallyClosed => "连接已关闭".into(),
        ConnectionError::TimedOut => "连接超时".into(),
        other => format!("连接断开：{other}"),
    }
}

/// The client's half of a socket stream: its frames go out on it; dropped, the stream is reset.
pub struct SocketSend(SendStream);

impl SocketSend {
    pub async fn write(&mut self, bytes: &[u8]) -> Result<()> {
        self.0.write_all(bytes).await.map_err(|e| mesh_error(format!("没送到 station：{e}")))
    }

    /// No more frames: the stream ends on this side.
    pub fn finish(&mut self) {
        let _ = self.0.finish();
    }
}

pub struct Reply {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    recv: RecvStream,
    /// Body bytes that came with the head line.
    carry: Vec<u8>,
    done: bool,
}

impl Reply {
    /// The next chunk of the body; None at its end.
    pub async fn next(&mut self) -> Option<Result<Vec<u8>>> {
        if !self.carry.is_empty() {
            return Some(Ok(std::mem::take(&mut self.carry)));
        }
        if self.done {
            return None;
        }
        let mut buf = vec![0u8; 32 * 1024];
        match self.recv.read(&mut buf).await {
            Ok(Some(n)) => {
                buf.truncate(n);
                Some(Ok(buf))
            }
            Ok(None) => {
                self.done = true;
                None
            }
            Err(e) => {
                self.done = true;
                Some(Err(mesh_error(format!("读取 station 的回复失败：{e}"))))
            }
        }
    }

    /// The rest of the body.
    pub async fn body(mut self) -> Result<Vec<u8>> {
        let mut body = Vec::new();
        while let Some(chunk) = self.next().await {
            body.extend_from_slice(&chunk?);
        }
        Ok(body)
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use crate::host::{HostError, HttpRequest, HttpResponse, StreamResponse};
    use crate::protocol::{ClientId, CoreMessage};
    use crate::testing::FakeHost;
    use iroh::endpoint::Connection;
    use std::time::Duration;

    /// FakeHost, but the renewal wait is short so tests see renewals.
    struct QuickHost(Rc<FakeHost>);

    impl Host for QuickHost {
        fn cloud_origin(&self) -> String {
            self.0.cloud_origin()
        }
        fn fetch(&self, request: HttpRequest) -> LocalBoxFuture<'static, std::result::Result<HttpResponse, HostError>> {
            self.0.fetch(request)
        }
        fn fetch_stream(&self, request: HttpRequest) -> LocalBoxFuture<'static, std::result::Result<StreamResponse, HostError>> {
            self.0.fetch_stream(request)
        }
        fn websocket(&self, url: String, protocols: Vec<String>) -> LocalBoxFuture<'static, std::result::Result<crate::host::SocketFrames, HostError>> {
            self.0.websocket(url, protocols)
        }
        fn storage_get(&self, key: &str) -> LocalBoxFuture<'static, std::result::Result<Option<Vec<u8>>, HostError>> {
            self.0.storage_get(key)
        }
        fn storage_set(&self, key: &str, value: Vec<u8>) -> LocalBoxFuture<'static, std::result::Result<(), HostError>> {
            self.0.storage_set(key, value)
        }
        fn storage_delete(&self, key: &str) -> LocalBoxFuture<'static, std::result::Result<(), HostError>> {
            self.0.storage_delete(key)
        }
        fn now_ms(&self) -> f64 {
            self.0.now_ms()
        }
        fn utc_offset_min(&self, at_ms: f64) -> i32 {
            self.0.utc_offset_min(at_ms)
        }
        fn sleep(&self, ms: u64) -> LocalBoxFuture<'static, ()> {
            self.0.sleep(match ms {
                RENEW_MS => 150,
                // Also CONNECT_TIMEOUT_MS (the same 10 s).
                RETIRE_MS => 200,
                ms => ms,
            })
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

    /// iroh needs tokio's IO driver, which `testing::run` leaves off.
    fn run<F: std::future::Future<Output = ()>>(body: F) {
        let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
        tokio::task::LocalSet::new().block_on(&runtime, body);
    }

    /// A station on localhost: accepts credentials starting with "ok", echoes requests.
    struct Station {
        endpoint: Endpoint,
        grants: Rc<RefCell<Vec<String>>>,
        conns: Rc<RefCell<Vec<Connection>>>,
        /// Connections before this one (by the order they came) answer nothing more: a way there that went dead
        /// with nothing said, as a phone's after it slept.
        dead_below: Rc<Cell<usize>>,
        /// This many connections coming are never answered, not even their handshake: a device whose way there is
        /// gone (its endpoint's relay connection dead) dialing.
        unanswered: Rc<Cell<usize>>,
        /// Says it keeps writes to once (`stillfail-idempotent`, mesh/app/src/admin/once.rs).
        idempotent: Rc<Cell<bool>>,
    }

    impl Station {
        async fn start() -> Station {
            Station::speaking(vec![ALPN.to_vec(), FORMER_ALPN.to_vec()]).await
        }

        /// One that takes only these ALPNs (a station from before the rename: `FORMER_ALPN`).
        async fn speaking(alpns: Vec<Vec<u8>>) -> Station {
            let endpoint = Endpoint::builder(Minimal)
                .alpns(alpns)
                .relay_mode(RelayMode::Disabled)
                .bind_addr("127.0.0.1:0".parse::<std::net::SocketAddr>().unwrap())
                .unwrap()
                .bind()
                .await
                .unwrap();
            let station = Station { endpoint: endpoint.clone(), grants: Rc::default(), conns: Rc::default(), dead_below: Rc::default(), unanswered: Rc::default(), idempotent: Rc::default() };
            let (grants, conns, dead_below, unanswered, idempotent) = (station.grants.clone(), station.conns.clone(), station.dead_below.clone(), station.unanswered.clone(), station.idempotent.clone());
            tokio::task::spawn_local(async move {
                let mut ignored = Vec::new();
                while let Some(incoming) = endpoint.accept().await {
                    if unanswered.get() > 0 {
                        unanswered.set(unanswered.get() - 1);
                        ignored.push(incoming);
                        continue;
                    }
                    let Ok(conn) = incoming.await else { continue };
                    let index = conns.borrow().len();
                    conns.borrow_mut().push(conn.clone());
                    let dead = { let dead_below = dead_below.clone(); Rc::new(move || index < dead_below.get()) };
                    tokio::task::spawn_local(serve(conn, grants.clone(), dead, idempotent.clone()));
                }
            });
            station
        }

        fn id(&self) -> String {
            hex::encode(self.endpoint.id().as_bytes())
        }

        fn addr(&self) -> EndpointAddr {
            let ip = *self.endpoint.bound_sockets().iter().find(|a| a.ip().is_loopback()).unwrap();
            EndpointAddr::new(self.endpoint.id()).with_ip_addr(ip)
        }
    }

    async fn write_line(send: &mut SendStream, value: &Value) {
        send.write_all(format!("{value}\n").as_bytes()).await.unwrap();
    }

    async fn serve(conn: Connection, grants: Rc<RefCell<Vec<String>>>, dead: Rc<dyn Fn() -> bool>, idempotent: Rc<Cell<bool>>) {
        let Ok((mut send, mut recv)) = conn.accept_bi().await else { return };
        let mut carry = Vec::new();
        let answer = |line: &str, grants: &Rc<RefCell<Vec<String>>>| {
            let grant = serde_json::from_str::<Value>(line).unwrap()["credential"].as_str().unwrap().to_string();
            grants.borrow_mut().push(grant.clone());
            if grant.starts_with("ok") { json!({ "ok": true, "station": "测试" }) } else { json!({ "error": "grant signature invalid" }) }
        };
        let first = read_line(&mut recv, &mut carry).await.unwrap().unwrap();
        let reply = answer(&first, &grants);
        write_line(&mut send, &reply).await;
        if reply.get("error").is_some() {
            send.finish().ok();
            tokio::time::sleep(Duration::from_millis(200)).await;
            conn.close(1u32.into(), b"credential_refused");
            return;
        }
        let renewals = grants.clone();
        let still = dead.clone();
        tokio::task::spawn_local(async move {
            while let Ok(Some(line)) = read_line(&mut recv, &mut carry).await {
                if still() {
                    continue;
                }
                let reply = answer(&line, &renewals);
                write_line(&mut send, &reply).await;
            }
        });
        while let Ok((mut send, mut recv)) = conn.accept_bi().await {
            let (dead, once) = (dead.clone(), idempotent.get());
            tokio::task::spawn_local(async move {
                let mut carry = Vec::new();
                let head = read_line(&mut recv, &mut carry).await.unwrap().unwrap();
                let mut body = carry;
                let mut buf = [0u8; 4096];
                while let Some(n) = recv.read(&mut buf).await.unwrap() {
                    body.extend_from_slice(&buf[..n]);
                }
                let head: Value = serde_json::from_str(&head).unwrap();
                if dead() {
                    // Never answered; held so the stream stays open.
                    futures::future::pending::<()>().await;
                }
                let mut headers = json!({ "content-type": "text/event-stream", "x-method": head["method"] });
                if once {
                    headers["stillfail-idempotent"] = json!("1");
                }
                write_line(&mut send, &json!({ "status": 200, "headers": headers })).await;
                send.write_all(format!("{}|{}", head, String::from_utf8_lossy(&body)).as_bytes()).await.unwrap();
                // Then a stream that trickles, like /events.
                for part in ["|one", "|two", "|three"] {
                    tokio::time::sleep(Duration::from_millis(100)).await;
                    send.write_all(part.as_bytes()).await.unwrap();
                }
                send.finish().unwrap();
            });
        }
    }

    /// Grants "<prefix>-1", "<prefix>-2", … and counts them.
    fn grants(prefix: &'static str, count: Rc<Cell<u32>>) -> CredentialSource {
        Rc::new(move |device: String, _fresh: bool| {
            assert_eq!(device.len(), 64);
            count.set(count.get() + 1);
            let grant = Credential { credential: format!("{prefix}-{}", count.get()), issued_at: 0.0, expires_at: 0.0, relay_url: String::new() };
            async move { Ok(grant) }.boxed_local()
        })
    }

    async fn setup(host: Rc<dyn Host>) -> (Rc<Mesh>, Station) {
        setup_with(host, Station::start().await).await
    }

    async fn setup_with(host: Rc<dyn Host>, station: Station) -> (Rc<Mesh>, Station) {
        let mesh = Mesh::new(host.clone(), Tracer::new(host, 1.0), &[]).await.unwrap();
        mesh.add_addr(station.addr());
        (mesh, station)
    }

    fn head(path: &str) -> RequestHead {
        RequestHead { method: "POST".into(), path: path.into(), headers: vec![("content-type".into(), "application/json".into())] }
    }

    #[test]
    fn opens_requests_and_streams_the_reply() {
        run(async {
            let host = FakeHost::new();
            let (mesh, station) = setup(host.clone()).await;
            assert_eq!(host.stored(DEVICE_KEY).map(|k| k.len()), Some(32));
            let link = mesh.link(&station.id(), grants("ok", Rc::default())).await.unwrap();
            // Requests follow the credential without waiting for its answer; by the reply the station has read it.
            let mut reply = link.request(head("/admin/api/sessions"), b"{\"a\":1}".to_vec()).await.unwrap();
            assert_eq!(*station.grants.borrow(), vec!["ok-1".to_string()]);
            assert_eq!(reply.status, 200);
            assert!(reply.headers.contains(&("content-type".into(), "text/event-stream".into())));
            assert!(reply.headers.contains(&("x-method".into(), "POST".into())));
            let first = String::from_utf8(reply.next().await.unwrap().unwrap()).unwrap();
            let echoed: Value = serde_json::from_str(first.split('|').next().unwrap()).unwrap();
            assert_eq!(echoed, json!({ "method": "POST", "path": "/admin/api/sessions", "headers": { "content-type": "application/json" } }));
            // The first chunk comes before the stream ends.
            assert_eq!(first.split('|').nth(1), Some("{\"a\":1}"));
            assert!(!first.contains("three"));
            let rest = String::from_utf8(reply.body().await.unwrap()).unwrap();
            assert!(rest.ends_with("|one|two|three"), "{rest}");
            assert_eq!(link.closed(), None);
        });
    }

    #[test]
    fn reaches_stations_from_before_and_after_the_rename() {
        run(async {
            for (alpns, spoken) in [(vec![FORMER_ALPN.to_vec()], FORMER_ALPN), (vec![ALPN.to_vec(), FORMER_ALPN.to_vec()], ALPN)] {
                let (mesh, station) = setup_with(FakeHost::new(), Station::speaking(alpns).await).await;
                let link = mesh.link(&station.id(), grants("ok", Rc::default())).await.unwrap();
                let reply = link.request(head("/admin/api/overview"), Vec::new()).await.unwrap();
                assert_eq!(reply.status, 200);
                assert_eq!(station.conns.borrow()[0].alpn(), spoken);
            }
        });
    }

    #[test]
    fn refused_grant_fails_with_a_reason() {
        run(async {
            let (mesh, station) = setup(FakeHost::new()).await;
            let count = Rc::new(Cell::new(0));
            // The link comes at once; its requests fail with the station's refusal.
            let link = mesh.link(&station.id(), grants("bad", count.clone())).await.unwrap();
            let error = link.request(head("/admin/api/sessions"), Vec::new()).await.err().unwrap();
            assert_eq!(error.code, "credential_refused");
            assert!(error.message.contains("station 拒绝了授权"), "{}", error.message);
            // A refused link is not kept: the next call opens another, with a fresh credential.
            let again = mesh.link(&station.id(), grants("bad", count.clone())).await.unwrap();
            assert!(!Rc::ptr_eq(&link, &again));
            assert_eq!(count.get(), 2);
        });
    }

    #[test]
    fn reuses_the_open_link_and_shares_an_opening() {
        run(async {
            let (mesh, station) = setup(FakeHost::new()).await;
            let count = Rc::new(Cell::new(0));
            let id = station.id();
            let (a, b) = futures::join!(mesh.link(&id, grants("ok", count.clone())), mesh.link(&id, grants("ok", count.clone())));
            let (a, b) = (a.unwrap(), b.unwrap());
            assert!(Rc::ptr_eq(&a, &b));
            let c = mesh.link(&id, grants("ok", count.clone())).await.unwrap();
            assert!(Rc::ptr_eq(&a, &c));
            assert_eq!(count.get(), 1);
            a.request(head("/admin/api/overview"), Vec::new()).await.unwrap();
            assert_eq!(station.conns.borrow().len(), 1);
        });
    }

    #[test]
    fn reopens_a_closed_link_with_a_new_credential() {
        run(async {
            let (mesh, station) = setup(FakeHost::new()).await;
            let count = Rc::new(Cell::new(0));
            let first = mesh.link(&station.id(), grants("ok", count.clone())).await.unwrap();
            first.request(head("/admin/api/overview"), Vec::new()).await.unwrap();
            station.conns.borrow()[0].close(3u32.into(), b"credential_expired");
            for _ in 0..100 {
                if first.closed().is_some() {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
            assert_eq!(first.closed().as_deref(), Some("授权已过期"));
            let second = mesh.link(&station.id(), grants("ok", count.clone())).await.unwrap();
            assert!(!Rc::ptr_eq(&first, &second));
            let reply = second.request(head("/admin/api/overview"), Vec::new()).await.unwrap();
            assert_eq!(*station.grants.borrow(), vec!["ok-1".to_string(), "ok-2".to_string()]);
            assert_eq!(reply.status, 200);
            assert!(reply.body().await.is_ok());
        });
    }

    #[test]
    fn renews_the_grant_until_the_link_closes() {
        run(async {
            let (mesh, station) = setup(Rc::new(QuickHost(FakeHost::new()))).await;
            let count = Rc::new(Cell::new(0));
            let link = mesh.link(&station.id(), grants("ok", count.clone())).await.unwrap();
            tokio::time::sleep(Duration::from_millis(400)).await;
            let seen = station.grants.borrow().clone();
            assert!(seen.len() >= 3, "{seen:?}");
            assert_eq!(seen[..3], ["ok-1", "ok-2", "ok-3"]);
            // Renewing kept the same link.
            assert!(Rc::ptr_eq(&link, &mesh.link(&station.id(), grants("ok", count.clone())).await.unwrap()));

            link.close();
            let asked = count.get();
            tokio::time::sleep(Duration::from_millis(400)).await;
            assert_eq!(count.get(), asked);
            assert_eq!(link.closed().as_deref(), Some("连接已关闭"));
        });
    }

    #[test]
    fn a_refused_renewal_makes_the_next_link_reopen() {
        run(async {
            let (mesh, station) = setup(Rc::new(QuickHost(FakeHost::new()))).await;
            let refuse_later: CredentialSource = {
                let count = Rc::new(Cell::new(0));
                Rc::new(move |_device: String, _fresh: bool| {
                    count.set(count.get() + 1);
                    let grant = Credential { credential: if count.get() == 1 { "ok".into() } else { "revoked".into() }, issued_at: 0.0, expires_at: 0.0, relay_url: String::new() };
                    async move { Ok(grant) }.boxed_local()
                })
            };
            let first = mesh.link(&station.id(), refuse_later).await.unwrap();
            tokio::time::sleep(Duration::from_millis(300)).await;
            let second = mesh.link(&station.id(), grants("ok", Rc::default())).await.unwrap();
            assert!(!Rc::ptr_eq(&first, &second));
        });
    }

    #[test]
    fn keeps_the_device_key_and_migrates_to_the_pages() {
        run(async {
            let host = FakeHost::new();
            let first = Mesh::new(host.clone(), Tracer::new(host.clone(), 1.0), &[]).await.unwrap();
            let again = Mesh::new(host.clone(), Tracer::new(host.clone(), 1.0), &[]).await.unwrap();
            assert_eq!(first.device_id(), again.device_id());

            let page = [7u8; 32];
            first.migrate(page.to_vec()).await.unwrap();
            assert_eq!(host.stored(DEVICE_KEY), Some(page.to_vec()));
            assert_eq!(first.device_id(), hex::encode(SecretKey::from_bytes(&page).public().as_bytes()));
            assert_ne!(first.device_id(), again.device_id());
            first.migrate(page.to_vec()).await.unwrap();
            assert_eq!(first.migrate(vec![1, 2, 3]).await.err().unwrap().code, "invalid_params");
        });
    }

    /// A mesh on a host whose wakes the test gives (wake.rs), its timers short (QuickHost).
    async fn waking(station: Station) -> (Rc<Mesh>, Station, Rc<crate::wake::Wakes>, Rc<dyn Host>) {
        let wakes = Rc::new(crate::wake::Wakes::default());
        let host: Rc<dyn Host> = crate::wake::WakingHost::new(Rc::new(QuickHost(FakeHost::new())), wakes.clone());
        let (mesh, station) = setup_with(host.clone(), station).await;
        (mesh, station, wakes, host)
    }

    fn network(host: &Rc<dyn Host>) -> crate::wake::Wake {
        crate::wake::Wake { at: host.now_ms(), away: 0.0, network: true, retry: false }
    }

    #[test]
    fn a_link_that_answers_as_the_network_changes_is_kept() {
        run(async {
            let (mesh, station, wakes, host) = waking(Station::start().await).await;
            let link = mesh.link(&station.id(), grants("ok", Rc::default())).await.unwrap();
            link.request(head("/admin/api/overview"), Vec::new()).await.unwrap();
            wakes.wake(network(&host));
            tokio::time::sleep(Duration::from_millis(500)).await;
            // It answered (its credential again) before, or about when, the one beside it opened: still the one.
            assert!(Rc::ptr_eq(&link, &mesh.current(&station.id()).unwrap()));
            assert_eq!(link.closed(), None);
        });
    }

    #[test]
    fn a_link_gone_quiet_is_replaced_by_one_opened_beside_it_at_once() {
        run(async {
            let (mesh, station, wakes, host) = waking(Station::start().await).await;
            let id = station.id();
            let old = mesh.link(&id, grants("ok", Rc::default())).await.unwrap();
            old.request(head("/admin/api/overview"), Vec::new()).await.unwrap();
            // The way it went is dead now: nothing on it is answered, and nothing says so.
            station.dead_below.set(station.conns.borrow().len());
            let replaced = mesh.replaced(&id, &old);
            let started = std::time::Instant::now();
            wakes.wake(network(&host));
            replaced.await;
            // Not after the probe gave up (PROBE_MS): as soon as the new one opened.
            assert!(started.elapsed() < Duration::from_millis(PROBE_MS / 2), "{:?}", started.elapsed());
            let new = mesh.current(&id).unwrap();
            assert!(!Rc::ptr_eq(&old, &new));
            assert_eq!(new.request(head("/admin/api/overview"), Vec::new()).await.unwrap().status, 200);
            // The old one goes a while later (RETIRE_MS, short here).
            tokio::time::sleep(Duration::from_millis(400)).await;
            assert!(old.closed().is_some());
            assert_eq!(new.closed(), None);
        });
    }

    #[test]
    fn a_read_under_way_on_a_link_that_is_replaced_is_answered_on_the_new_one() {
        run(async {
            use crate::station::{MeshWire, StationAddr, StationWire};
            let (mesh, station, wakes, host) = waking(Station::start().await).await;
            let id = station.id();
            let source = { let mesh = mesh.clone(); Rc::new(move || { let mesh = mesh.clone(); async move { Ok::<_, CoreError>(mesh) }.boxed_local() }) };
            let count = Rc::new(Cell::new(0));
            let wire = MeshWire::new(source, Rc::new(move |_: &str| grants("ok", count.clone())), crate::status::one(crate::status::Status::new(host.clone())));
            let addr = StationAddr { workspace: "w".into(), station: id.clone() };
            let get = RequestHead { method: "GET".into(), path: "/admin/api/overview".into(), headers: vec![] };
            wire.request(&addr, get.clone(), Vec::new()).await.unwrap();
            station.dead_below.set(station.conns.borrow().len());
            // Sent on the dead way: it would never be answered.
            let asked = wire.request(&addr, get, Vec::new());
            let asked = tokio::task::spawn_local(asked);
            tokio::time::sleep(Duration::from_millis(50)).await;
            wakes.wake(network(&host));
            let reply = tokio::time::timeout(Duration::from_millis(PROBE_MS / 2), asked).await.expect("answered on the new link").unwrap().unwrap();
            assert_eq!(reply.status, 200);
            assert_eq!(station.conns.borrow().len(), 2);
        });
    }

    #[test]
    fn a_write_is_asked_again_only_of_a_station_that_does_it_once() {
        run(async {
            use crate::station::{MeshWire, StationAddr, StationWire};
            let (mesh, station, wakes, host) = waking(Station::start().await).await;
            let id = station.id();
            let source = { let mesh = mesh.clone(); Rc::new(move || { let mesh = mesh.clone(); async move { Ok::<_, CoreError>(mesh) }.boxed_local() }) };
            let count = Rc::new(Cell::new(0));
            let wire = MeshWire::new(source, Rc::new(move |_: &str| grants("ok", count.clone())), crate::status::one(crate::status::Status::new(host.clone())));
            let addr = StationAddr { workspace: "w".into(), station: id.clone() };
            let write = RequestHead { method: "POST".into(), path: "/admin/api/threads/1/messages".into(), headers: vec![("idempotency-key".into(), "k1".into())] };
            wire.request(&addr, RequestHead { method: "GET".into(), path: "/admin/api/overview".into(), headers: vec![] }, Vec::new()).await.unwrap();
            station.dead_below.set(station.conns.borrow().len());
            // This station never said it keeps writes to once: the write stays on the way it went.
            let asked = tokio::task::spawn_local(wire.request(&addr, write, Vec::new()));
            tokio::time::sleep(Duration::from_millis(50)).await;
            wakes.wake(network(&host));
            // It ends with the old way when that is closed (RETIRE_MS), never asked on the new one.
            let answered = tokio::time::timeout(Duration::from_millis(2_000), asked).await.expect("ends with the old link").unwrap();
            // Gone unanswered, it may have been done: said so, not that it failed.
            assert_eq!(answered.err().map(|e| e.code), Some("unconfirmed".to_string()));
        });
    }

    #[test]
    fn a_write_whose_link_went_before_its_answer_is_asked_again_once_its_station_is_back() {
        run(async {
            use crate::station::{MeshWire, StationAddr, StationWire};
            let (mesh, station, _wakes, host) = waking(Station::start().await).await;
            station.idempotent.set(true);
            let id = station.id();
            let source = { let mesh = mesh.clone(); Rc::new(move || { let mesh = mesh.clone(); async move { Ok::<_, CoreError>(mesh) }.boxed_local() }) };
            let count = Rc::new(Cell::new(0));
            let wire = MeshWire::new(source, Rc::new(move |_: &str| grants("ok", count.clone())), crate::status::one(crate::status::Status::new(host.clone())));
            let addr = StationAddr { workspace: "w".into(), station: id.clone() };
            // Its first answer says it keeps writes to once.
            wire.request(&addr, RequestHead { method: "GET".into(), path: "/admin/api/overview".into(), headers: vec![] }, Vec::new()).await.unwrap();
            station.dead_below.set(station.conns.borrow().len());
            let write = RequestHead { method: "POST".into(), path: "/admin/api/sessions/k/pin".into(), headers: vec![("idempotency-key".into(), "k1".into())] };
            let asked = tokio::task::spawn_local(wire.request(&addr, write, Vec::new()));
            tokio::time::sleep(Duration::from_millis(50)).await;
            // Its link goes before it is answered (the station restarting): asked again, with its key, on the next.
            station.conns.borrow()[0].close(0u32.into(), b"restart");
            let reply = tokio::time::timeout(Duration::from_millis(5_000), asked).await.expect("asked again").unwrap().unwrap();
            assert_eq!(reply.status, 200);
            assert_eq!(station.conns.borrow().len(), 2);
        });
    }

    #[test]
    fn a_try_not_answered_makes_the_next_go_on_an_endpoint_bound_anew() {
        run(async {
            let (mesh, station) = setup_with(Rc::new(QuickHost(FakeHost::new())), Station::start().await).await;
            station.unanswered.set(1);
            let before = mesh.endpoint().bound_sockets();
            let device = mesh.device_id();
            let error = mesh.link(&station.id(), grants("ok", Rc::default())).await.err().unwrap();
            assert_eq!(error.message, NO_ANSWER);
            let link = mesh.link(&station.id(), grants("ok", Rc::default())).await.unwrap();
            assert_eq!(link.request(head("/admin/api/overview"), Vec::new()).await.unwrap().status, 200);
            // Another endpoint (other sockets), the same device.
            assert_ne!(mesh.endpoint().bound_sockets(), before);
            assert_eq!(mesh.device_id(), device);
            // Answered: the next try stays on it.
            let now = mesh.endpoint().bound_sockets();
            link.close();
            mesh.link(&station.id(), grants("ok", Rc::default())).await.unwrap();
            assert_eq!(mesh.endpoint().bound_sockets(), now);
        });
    }

    #[test]
    fn a_wake_while_a_try_goes_unanswered_opens_one_beside_it() {
        run(async {
            let (mesh, station, wakes, host) = waking(Station::start().await).await;
            station.unanswered.set(1);
            let id = station.id();
            let opening = tokio::task::spawn_local({
                let (mesh, id) = (mesh.clone(), id.clone());
                async move { mesh.link(&id, grants("ok", Rc::default())).await.map(|_| ()) }
            });
            tokio::time::sleep(Duration::from_millis(50)).await;
            // A person taps 重试 (client.wake, network) while a try that will never be answered is under way: another
            // beside it opens. (The first alone fails as it runs out, or as its endpoint is bound anew.)
            wakes.wake(network(&host));
            opening.await.unwrap().unwrap();
            let link = mesh.current(&id).unwrap();
            assert_eq!(link.request(head("/admin/api/overview"), Vec::new()).await.unwrap().status, 200);
        });
    }
}
