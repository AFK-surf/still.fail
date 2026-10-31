//! The station's iroh for the station in TypeScript (docs/station-ts-native.md §3): its endpoint as
//! mesh/station/src/main.rs `serve_mesh` makes it (the station's key, its relays, found on the LAN by mDNS and by relay
//! through the Mainline DHT, Cubic by default with a 256 KiB initial window), home on every one of its relays at once
//! (one connection to it has a path through each, PATH_IDLE), keepers on relays added since (keep.rs), connections both
//! ways and their streams. Which relays, when to add iroh's public ones, who may connect and what is said: the
//! TypeScript's. And the image codecs of the thumbnails (thumbs.rs).

mod keep;
mod thumbs;
mod local;
mod usage;

use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Mutex as StdMutex};
use std::time::{Duration, Instant};

use iroh::address_lookup::{AddressLookup, AddressLookupBuilder, AddressLookupBuilderError, EndpointData, Error as AddressLookupError, Item as AddressLookupItem};
use iroh::endpoint::{Connection as IrohConnection, QuicTransportConfig, RecvStream, SendStream, presets::Minimal};
use iroh::{Endpoint as IrohEndpoint, EndpointAddr, EndpointId, RelayMode, RelayUrl, SecretKey, Watcher};
use n0_future::boxed::BoxStream;
use napi::bindgen_prelude::Buffer;
use napi_derive::napi;
use tokio::sync::Mutex;

const MDNS_SERVICE: &str = "stillfail";
const FORMER_MDNS_SERVICE: &str = "ember";

fn failed(error: impl std::fmt::Display) -> napi::Error {
    napi::Error::from_reason(error.to_string())
}

/// How often each path of a connection is kept alive, and how long one may hear nothing before it is given up: its
/// packets go on on another path meanwhile (another relay, direct), and a relay's is opened again as it comes back.
/// iroh's own (5 s, 15 s; 30 s for a relay's) held a connection on a way that was gone that long (a relay down, a path
/// punched through that stopped answering), every stream on it waiting.
const PATH_KEEP_ALIVE: Duration = Duration::from_secs(1);
const PATH_IDLE: Duration = Duration::from_secs(3);

fn relay_url(url: &str) -> napi::Result<RelayUrl> {
    url.parse().map_err(failed)
}

#[napi(object)]
pub struct Options {
    /// The station's 32-byte key (<data>/mesh/secret.key).
    pub secret_key: Buffer,
    pub alpns: Vec<Buffer>,
    /// still.fail's relays, ours first; none: relays off (tests on one machine).
    pub relay_urls: Vec<String>,
    /// Alternative addresses into the same relays, used by client endpoints.
    pub relay_entries: Option<Vec<RelayEntry>>,
    /// Found on the LAN and through the DHT, as a station is. Off for tests.
    pub discovery: Option<bool>,
    /// Where to listen; any free port when not said.
    pub bind_addr: Option<String>,
    /// A client's endpoint (the core in TypeScript, client/core-ts): it looks stations up on the LAN and in the DHT
    /// without being announced itself (a device is never dialed).
    pub lookup: Option<bool>,
    /// Relays alone, no IP transports: what measures the way through a relay must not go direct.
    pub relay_only: Option<bool>,
    /// Advanced choice, cubic by default; read when the endpoint is created.
    pub congestion: Option<String>,
}

#[napi(object)]
pub struct RelayEntry {
    pub entry: String,
    pub relay: String,
}

#[napi]
pub struct Endpoint {
    inner: IrohEndpoint,
    keepers: Arc<StdMutex<HashMap<String, tokio::task::JoinHandle<()>>>>,
    /// The relays it was bound with: home on each, no keeper wanted there.
    homes: Vec<RelayUrl>,
    /// Connections coming that are held unanswered, not even their handshake (`hold_incoming`), and those held.
    held: Arc<StdMutex<(u32, Vec<iroh::endpoint::Incoming>)>>,
    /// The connections whose handshakes are done, as each finishes (`accept`), once one was first asked for.
    accepted: Arc<Mutex<Option<tokio::sync::mpsc::UnboundedReceiver<IrohConnection>>>>,
}

/// The connections' transport: the congestion controller named (BBR is opt-in: noq 1.3.0 can underestimate bandwidth
/// after idle, n0-computer/noq#852), the paths kept alive and given up as PATH_KEEP_ALIVE and PATH_IDLE say.
fn transport(congestion: &str) -> napi::Result<QuicTransportConfig> {
    let controller: Arc<dyn noq_proto::congestion::ControllerFactory + Send + Sync> = match congestion {
        "cubic" => {
            let mut config = noq_proto::congestion::CubicConfig::default();
            config.initial_window(256 * 1024);
            Arc::new(config)
        }
        "bbr" => {
            let mut config = noq_proto::congestion::Bbr3Config::default();
            config.initial_window(256 * 1024);
            Arc::new(config)
        }
        _ => return Err(failed("congestion: expected cubic or bbr")),
    };
    Ok(QuicTransportConfig::builder()
        .congestion_controller_factory(controller)
        .default_path_keep_alive_interval(PATH_KEEP_ALIVE)
        .default_path_max_idle_timeout(PATH_IDLE)
        .build())
}

/// A way of finding stations (mDNS on the LAN, the DHT) that could not be made leaves the endpoint without it, said,
/// instead of failing the endpoint: mDNS binds UDP 5353 on the machine's networks, which fails with none up yet (a
/// Windows station started at logon before its network) or the port held by another program, and the endpoint failing
/// left the station off the mesh, and offline, until it was restarted.
#[derive(Debug)]
struct Optional<B>(&'static str, B);

#[derive(Debug)]
struct Unmade<L>(Option<L>);

impl<B: AddressLookupBuilder> AddressLookupBuilder for Optional<B> {
    fn into_address_lookup(self, endpoint: &IrohEndpoint) -> Result<impl AddressLookup, AddressLookupBuilderError> {
        Ok(Unmade(match self.1.into_address_lookup(endpoint) {
            Ok(lookup) => Some(lookup),
            Err(error) => {
                eprintln!("mesh: stations not found through {}: {error:#}", self.0);
                None
            }
        }))
    }
}

impl<L: AddressLookup> AddressLookup for Unmade<L> {
    fn publish(&self, data: &EndpointData) {
        if let Some(lookup) = &self.0 {
            lookup.publish(data);
        }
    }

    fn resolve(&self, endpoint_id: EndpointId) -> Option<BoxStream<Result<AddressLookupItem, AddressLookupError>>> {
        self.0.as_ref().and_then(|lookup| lookup.resolve(endpoint_id))
    }
}

#[napi]
pub async fn bind(options: Options) -> napi::Result<Endpoint> {
    let bytes: [u8; 32] = options.secret_key.as_ref().try_into().map_err(|_| failed("the key is not 32 bytes"))?;
    let key = SecretKey::from_bytes(&bytes);
    let relays: Vec<RelayUrl> = options.relay_urls.iter().map(|u| relay_url(u)).collect::<Result<_, _>>()?;
    let entries: Vec<(RelayUrl, RelayUrl)> = options.relay_entries.unwrap_or_default().iter().map(|e| Ok((relay_url(&e.entry)?, relay_url(&e.relay)?))).collect::<napi::Result<_>>()?;
    let relay_map = iroh::RelayMap::from_iter(relays.iter().map(|relay| {
        iroh::RelayConfig::from(relay.clone()).with_entries(entries.iter().filter(|(_, target)| target == relay).map(|(entry, _)| entry.clone()))
    }));
    let transport = transport(options.congestion.as_deref().unwrap_or("cubic"))?;
    let mut builder = IrohEndpoint::builder(Minimal)
        .secret_key(key.clone())
        .alpns(options.alpns.iter().map(|a| a.to_vec()).collect())
        .relay_mode(if relays.is_empty() { RelayMode::Disabled } else { RelayMode::Custom(relay_map) })
        .home_on_every_relay()
        .transport_config(transport);
    if let Some(addr) = &options.bind_addr {
        builder = builder.bind_addr(addr.parse::<std::net::SocketAddr>().map_err(failed)?).map_err(failed)?;
    }
    if options.relay_only.unwrap_or(false) {
        builder = builder.clear_ip_transports();
    }
    if options.lookup.unwrap_or(false) && !relays.is_empty() {
        builder = builder
            .address_lookup(Optional("mDNS", iroh_mdns_address_lookup::MdnsAddressLookup::builder().service_name(MDNS_SERVICE).advertise(false)))
            .address_lookup(Optional("mDNS", iroh_mdns_address_lookup::MdnsAddressLookup::builder().service_name(FORMER_MDNS_SERVICE).advertise(false)))
            .address_lookup(Optional("the DHT", iroh_mainline_address_lookup::DhtAddressLookup::builder().no_publish()));
    } else if options.discovery.unwrap_or(true) {
        builder = builder
            .address_lookup(Optional("mDNS", iroh_mdns_address_lookup::MdnsAddressLookup::builder().service_name(MDNS_SERVICE)))
            .address_lookup(Optional("mDNS", iroh_mdns_address_lookup::MdnsAddressLookup::builder().service_name(FORMER_MDNS_SERVICE)))
            .address_lookup(Optional("the DHT", iroh_mainline_address_lookup::DhtAddressLookup::builder().secret_key(key)));
    }
    Ok(Endpoint { inner: builder.bind().await.map_err(failed)?, keepers: Arc::default(), homes: relays, held: Arc::default(), accepted: Arc::default() })
}

#[napi(object)]
pub struct Addr {
    /// The endpoint's id (hex).
    pub id: String,
    pub relays: Option<Vec<String>>,
    /// `ip:port`, each.
    pub ips: Option<Vec<String>>,
}

fn endpoint_addr(addr: &Addr) -> napi::Result<EndpointAddr> {
    let bytes: [u8; 32] = hex::decode(&addr.id).map_err(failed)?.try_into().map_err(|_| failed("the id is not 32 bytes"))?;
    let id = EndpointId::from_bytes(&bytes).map_err(failed)?;
    let mut out = EndpointAddr::new(id);
    for url in addr.relays.iter().flatten() {
        out = out.with_relay_url(relay_url(url)?);
    }
    for ip in addr.ips.iter().flatten() {
        out = out.with_ip_addr(ip.parse::<std::net::SocketAddr>().map_err(failed)?);
    }
    Ok(out)
}

#[napi]
impl Endpoint {
    /// Its id, as the station's (hex).
    #[napi]
    pub fn id(&self) -> String {
        hex::encode(self.inner.id().as_bytes())
    }

    /// Where it listens on this machine: `ip:port`, each.
    #[napi]
    pub fn sockets(&self) -> Vec<String> {
        self.inner.bound_sockets().iter().map(ToString::to_string).collect()
    }

    /// Resolves once it is on its home relay (at once with relays off).
    #[napi]
    pub async fn online(&self) {
        self.inner.online().await;
    }

    /// Its home relay now, if it has one.
    #[napi]
    pub fn home(&self) -> Option<String> {
        self.inner.home_relay_status().get().first().map(|s| s.url().to_string())
    }

    #[napi]
    pub async fn insert_relay(&self, url: String) -> napi::Result<()> {
        let url = relay_url(&url)?;
        self.inner.insert_relay(url.clone(), Arc::new(iroh::RelayConfig::from(url))).await;
        Ok(())
    }

    #[napi]
    pub async fn remove_relay(&self, url: String) -> napi::Result<()> {
        self.inner.remove_relay(&relay_url(&url)?).await;
        Ok(())
    }

    /// The congestion controller of the connections made from now on, dialed and accepted (one made keeps its own):
    /// the advanced network setting changed while the station runs.
    #[napi]
    pub fn set_congestion(&self, congestion: String) -> napi::Result<()> {
        self.inner.set_transport_config(transport(&congestion)?);
        Ok(())
    }

    /// iroh's own public relays: added while none of still.fail's answers, removed once one does (`keep_relays`).
    #[napi]
    pub async fn public_relays(&self, on: bool) {
        let public: Vec<Arc<iroh::RelayConfig>> = iroh::defaults::prod::default_relay_map().relays();
        for config in public {
            if on {
                self.inner.insert_relay(config.url.clone(), config.clone()).await;
            } else {
                self.inner.remove_relay(&config.url).await;
            }
        }
    }

    /// Keeps the station on exactly these relays, besides those it is home on (bound with): a keeper for each new one
    /// (keep.rs), those of relays no longer named stopped.
    #[napi]
    pub fn keep(&self, urls: Vec<String>) -> napi::Result<()> {
        let mut relays: Vec<RelayUrl> = urls.iter().map(|u| relay_url(u)).collect::<Result<_, _>>()?;
        relays.retain(|r| !self.homes.contains(r));
        let urls: Vec<String> = relays.iter().map(ToString::to_string).collect();
        let mut keepers = self.keepers.lock().unwrap();
        keepers.retain(|url, task| {
            let named = urls.contains(url);
            if !named {
                task.abort();
            }
            named
        });
        for relay in relays {
            let endpoint = self.inner.clone();
            keepers.entry(relay.to_string()).or_insert_with(|| napi::bindgen_prelude::spawn(keep::keep(endpoint, relay)));
        }
        Ok(())
    }

    /// The next `n` connections coming are never answered, not even their handshake: a device whose way here is gone,
    /// dialing (the client core's tests).
    #[napi]
    pub fn hold_incoming(&self, n: u32) {
        self.held.lock().unwrap().0 = n;
    }

    /// The next connection, its handshake done; null once the endpoint is closed. One that fails its handshake is
    /// skipped. Handshakes go on side by side, each on its own: one that is never finished (its device gone half way,
    /// as an app updating, a phone out of signal) holds up no other. Taken one at a time, every connection behind it
    /// waited until it timed out, half a minute in which the station took no one (2026-10-08: with devices dialling
    /// every way at once, stations were out of everyone's reach a minute or two at a time).
    #[napi]
    pub async fn accept(&self) -> Option<Connection> {
        let mut accepted = self.accepted.lock().await;
        let done = accepted.get_or_insert_with(|| {
            let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
            let endpoint = self.inner.clone();
            let held = self.held.clone();
            napi::bindgen_prelude::spawn(async move {
                while let Some(incoming) = endpoint.accept().await {
                    {
                        let mut held = held.lock().unwrap();
                        if held.0 > 0 {
                            held.0 -= 1;
                            held.1.push(incoming);
                            continue;
                        }
                    }
                    let tx = tx.clone();
                    napi::bindgen_prelude::spawn(async move {
                        // One whose handshake fails is said, where it came from and how long it took: a device whose
                        // dials to the station never got through said nothing here, which way its packets came or
                        // whether any came at all (2026-10-29).
                        let from = incoming.remote_addr();
                        let started = Instant::now();
                        match incoming.await {
                            Ok(conn) => {
                                let _ = tx.send(conn);
                            }
                            Err(error) => eprintln!("mesh: a connection's handshake failed from {from:?} after {} ms: {error:#}", started.elapsed().as_millis()),
                        }
                    });
                }
            });
            rx
        });
        done.recv().await.map(|inner| Connection { inner })
    }

    /// A connection to another endpoint (a peer station; a station, from a client), offering `alpn` and, for one from
    /// before a rename, the `additional` ones too.
    #[napi]
    pub async fn connect(&self, addr: Addr, alpn: Buffer, additional: Option<Vec<Buffer>>) -> napi::Result<Connection> {
        let options = iroh::endpoint::ConnectOptions::new().with_additional_alpns(additional.unwrap_or_default().iter().map(|a| a.to_vec()).collect());
        let connecting = self.inner.connect_with_opts(endpoint_addr(&addr)?, &alpn, options).await.map_err(failed)?;
        let conn = connecting.await.map_err(failed)?;
        Ok(Connection { inner: conn })
    }

    /// Tells it where an endpoint is without looking it up (tests, a LAN with no relay).
    #[napi]
    pub fn add_addr(&self, addr: Addr) -> napi::Result<()> {
        let addr = endpoint_addr(&addr)?;
        let lookup = self.inner.address_lookup().map_err(failed)?;
        lookup.add(iroh::address_lookup::MemoryLookup::from_endpoint_info([addr]));
        Ok(())
    }

    /// Replace forwarding entrances without closing the endpoint's existing connections.
    #[napi]
    pub async fn set_relay_entries(&self, entries: Vec<RelayEntry>) -> napi::Result<()> {
        let mut grouped = BTreeMap::<RelayUrl, Vec<RelayUrl>>::new();
        for entry in entries {
            grouped.entry(relay_url(&entry.relay)?).or_default().push(relay_url(&entry.entry)?);
        }
        self.inner.set_relay_entries(grouped.into_iter().collect()).await;
        Ok(())
    }

    /// The network changed (a phone's, after it slept): its sockets and relay connection looked at anew.
    #[napi]
    pub async fn network_change(&self) {
        self.inner.network_change().await;
    }

    /// Its home relays, and whether it is connected to each now.
    #[napi]
    pub fn relay_status(&self) -> Vec<RelayState> {
        self.inner.home_relay_status().get().iter().map(|s| RelayState { url: s.url().to_string(), connected: s.is_connected(), access: s.access_url().to_string() }).collect()
    }

    #[napi]
    pub async fn close(&self) {
        for (_, task) in self.keepers.lock().unwrap().drain() {
            task.abort();
        }
        self.inner.close().await;
    }
}

#[napi(object)]
pub struct RelayState {
    pub url: String,
    pub connected: bool,
    pub access: String,
}

/// One way a connection can go: through a relay (its URL) or direct; the one chosen now, its round trip, and the
/// packets sent and lost on it alone (the connection's own counts take in every way it tried and dropped too).
#[napi(object)]
pub struct PathState {
    pub id: String,
    pub selected: bool,
    pub relay: Option<String>,
    /// A direct way's address at the other end (`ip:port`).
    pub ip: Option<String>,
    pub rtt_ms: Option<f64>,
    pub tx_packets: f64,
    pub lost_packets: f64,
    /// How much its sender may have unacknowledged on it now (bytes), and how many times it was cut for loss.
    pub cwnd: f64,
    pub congestion_events: f64,
}

/// What went over a connection since it opened, both ways: bytes, packets, and of the frames in them those that
/// carry nothing (pings, ACK requests, ACKs) and those that carry something (stream data, datagrams, the handshake's).
/// A connection that only trades the first kind, thousands of packets a second, is a storm (mesh/storms.ts).
#[napi(object)]
pub struct Stats {
    pub rx_bytes: f64,
    pub tx_bytes: f64,
    pub rx_packets: f64,
    pub tx_packets: f64,
    pub rx_pings: f64,
    pub tx_pings: f64,
    pub rx_ack_requests: f64,
    pub tx_ack_requests: f64,
    pub rx_acks: f64,
    pub tx_acks: f64,
    pub rx_data: f64,
    pub tx_data: f64,
}

/// Why a connection went: `application` (the other end closed it, saying `reason`), `local`, `timeout`, or `other`
/// (`reason` in words).
#[napi(object)]
pub struct CloseInfo {
    pub kind: String,
    pub reason: String,
}

fn close_info(error: &iroh::endpoint::ConnectionError) -> CloseInfo {
    use iroh::endpoint::ConnectionError;
    match error {
        ConnectionError::ApplicationClosed(close) => CloseInfo { kind: "application".into(), reason: String::from_utf8_lossy(&close.reason).into_owned() },
        ConnectionError::LocallyClosed => CloseInfo { kind: "local".into(), reason: String::new() },
        ConnectionError::TimedOut => CloseInfo { kind: "timeout".into(), reason: String::new() },
        other => CloseInfo { kind: "other".into(), reason: other.to_string() },
    }
}

#[napi]
pub struct Connection {
    inner: IrohConnection,
}

#[napi]
impl Connection {
    /// The device at the other end (hex).
    #[napi]
    pub fn remote_id(&self) -> String {
        hex::encode(self.inner.remote_id().as_bytes())
    }

    #[napi]
    pub fn alpn(&self) -> Buffer {
        self.inner.alpn().to_vec().into()
    }

    /// How it runs now: "relay", "direct", or null while none is chosen.
    #[napi]
    pub fn via(&self) -> Option<String> {
        self.inner.paths().iter().find(|p| p.is_selected()).map(|p| if p.is_relay() { "relay" } else { "direct" }.to_string())
    }

    /// The next stream the other end opened; null once the connection is gone.
    #[napi]
    pub async fn accept_bi(&self) -> Option<Stream> {
        let (send, recv) = self.inner.accept_bi().await.ok()?;
        Some(Stream::new(send, recv))
    }

    #[napi]
    pub async fn open_bi(&self) -> napi::Result<Stream> {
        let (send, recv) = self.inner.open_bi().await.map_err(failed)?;
        Ok(Stream::new(send, recv))
    }

    #[napi]
    pub fn close(&self, code: u32, reason: String) {
        self.inner.close(code.into(), reason.as_bytes());
    }

    /// Whether it is gone already.
    #[napi]
    pub fn is_closed(&self) -> bool {
        self.inner.close_reason().is_some()
    }

    /// Resolves when it is gone, with why.
    #[napi]
    pub async fn closed(&self) -> String {
        self.inner.closed().await.to_string()
    }

    /// Resolves when it is gone, with why, told apart (`CloseInfo`).
    #[napi]
    pub async fn closed_info(&self) -> CloseInfo {
        close_info(&self.inner.closed().await)
    }

    /// Why it is gone, if it is.
    #[napi]
    pub fn close_reason(&self) -> Option<CloseInfo> {
        self.inner.close_reason().map(|e| close_info(&e))
    }

    /// Every way it can go now.
    #[napi]
    pub fn paths(&self) -> Vec<PathState> {
        self.inner.paths().iter().map(|p| {
            let stats = p.stats();
            PathState {
                id: p.id().to_string(),
                selected: p.is_selected(),
                relay: match p.remote_addr() {
                    iroh::TransportAddr::Relay(url) => Some(url.to_string()),
                    _ => None,
                },
                ip: match p.remote_addr() {
                    iroh::TransportAddr::Ip(addr) => Some(addr.to_string()),
                    _ => None,
                },
                rtt_ms: stats.same_path_rtt.map(|rtt| rtt.as_secs_f64() * 1000.0),
                tx_packets: stats.udp_tx.datagrams as f64,
                lost_packets: stats.lost_packets as f64,
                cwnd: stats.cwnd as f64,
                congestion_events: stats.congestion_events as f64,
            }
        }).collect()
    }

    /// Whether the other end is still there: asked with a datagram (which a live end acknowledges at once) a few times
    /// within `within_ms`, true as soon as anything is heard from it. A process killed with the connection open says
    /// nothing, and the connection would only go at QUIC's idle timeout, half a minute on. An end that takes no
    /// datagrams is not asked, and counts as there.
    #[napi]
    pub async fn answers(&self, within_ms: u32) -> bool {
        let heard = self.inner.stats().udp_rx.datagrams;
        let within = Duration::from_millis(within_ms.into());
        let deadline = Instant::now() + within;
        let mut ask = Instant::now();
        loop {
            if self.inner.close_reason().is_some() {
                return false;
            }
            if self.inner.stats().udp_rx.datagrams > heard {
                return true;
            }
            let now = Instant::now();
            if now >= deadline {
                return false;
            }
            if now >= ask {
                match self.inner.send_datagram(bytes::Bytes::from_static(&[0])) {
                    Ok(()) => {}
                    Err(iroh::endpoint::SendDatagramError::ConnectionLost(_)) => return false,
                    Err(_) => return true,
                }
                ask = now + within / 3;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    }

    #[napi]
    pub fn stats(&self) -> Stats {
        let stats = self.inner.stats();
        let data = |f: &iroh::endpoint::FrameStats| (f.stream + f.datagram + f.crypto) as f64;
        Stats {
            rx_bytes: stats.udp_rx.bytes as f64,
            tx_bytes: stats.udp_tx.bytes as f64,
            rx_packets: stats.udp_rx.datagrams as f64,
            tx_packets: stats.udp_tx.datagrams as f64,
            rx_pings: stats.frame_rx.ping as f64,
            tx_pings: stats.frame_tx.ping as f64,
            rx_ack_requests: stats.frame_rx.immediate_ack as f64,
            tx_ack_requests: stats.frame_tx.immediate_ack as f64,
            rx_acks: (stats.frame_rx.acks + stats.frame_rx.path_acks) as f64,
            tx_acks: (stats.frame_tx.acks + stats.frame_tx.path_acks) as f64,
            rx_data: data(&stats.frame_rx),
            tx_data: data(&stats.frame_tx),
        }
    }

    /// A stream one way: what measures a round trip sends a byte on it (mesh.rs `sample_relay_rtt`).
    #[napi]
    pub async fn open_uni(&self) -> napi::Result<UniStream> {
        let send = self.inner.open_uni().await.map_err(failed)?;
        Ok(UniStream { send: Arc::new(Mutex::new(send)) })
    }
}

#[napi]
pub struct UniStream {
    send: Arc<Mutex<SendStream>>,
}

#[napi]
impl UniStream {
    #[napi]
    pub async fn write(&self, bytes: Buffer) -> napi::Result<()> {
        self.send.lock().await.write_all(&bytes).await.map_err(failed)
    }

    #[napi]
    pub async fn finish(&self) -> napi::Result<()> {
        self.send.lock().await.finish().map_err(failed)
    }

    /// Resolves once what was sent is acknowledged: null, or the code the other end stopped it with.
    #[napi]
    pub async fn stopped(&self) -> napi::Result<Option<u32>> {
        let stopped = self.send.lock().await.stopped();
        let code = stopped.await.map_err(failed)?;
        Ok(code.map(|c| u32::try_from(c.into_inner()).unwrap_or(u32::MAX)))
    }
}

#[napi]
pub struct Stream {
    send: Arc<Mutex<SendStream>>,
    recv: Arc<Mutex<RecvStream>>,
    /// Set by `reset`: a read waiting on the other end gives up (it holds the receiving half meanwhile).
    reset: tokio::sync::watch::Sender<bool>,
}

impl Stream {
    fn new(send: SendStream, recv: RecvStream) -> Stream {
        Stream { send: Arc::new(Mutex::new(send)), recv: Arc::new(Mutex::new(recv)), reset: tokio::sync::watch::channel(false).0 }
    }
}

#[napi]
impl Stream {
    /// What came next, up to 64 KiB; null at its end (or once it was reset).
    #[napi]
    pub async fn read(&self) -> napi::Result<Option<Buffer>> {
        let mut reset = self.reset.subscribe();
        if *reset.borrow() {
            return Ok(None);
        }
        let mut buf = vec![0u8; 64 * 1024];
        let mut recv = self.recv.lock().await;
        let read = tokio::select! {
            read = recv.read(&mut buf) => read.map_err(failed)?,
            _ = reset.changed() => None,
        };
        match read {
            Some(n) => {
                buf.truncate(n);
                Ok(Some(buf.into()))
            }
            None => Ok(None),
        }
    }

    #[napi]
    pub async fn write(&self, bytes: Buffer) -> napi::Result<()> {
        self.send.lock().await.write_all(&bytes).await.map_err(failed)
    }

    #[napi]
    pub async fn finish(&self) -> napi::Result<()> {
        self.send.lock().await.finish().map_err(failed)
    }

    /// Resolves once what was sent is acknowledged: null; or the code the other end stopped reading with; or null once
    /// the stream is gone.
    #[napi]
    pub async fn stopped(&self) -> Option<u32> {
        // The future owns what it waits on: taken under the lock and awaited without it, so writes go on meanwhile.
        let stopped = self.send.lock().await.stopped();
        stopped.await.ok().flatten().map(|c| u32::try_from(c.into_inner()).unwrap_or(u32::MAX))
    }

    /// Ends it at once, both ways: a read waiting gives up first, so the receiving half can be stopped.
    #[napi]
    pub async fn reset(&self, code: u32) {
        let _ = self.reset.send(true);
        let _ = self.send.lock().await.reset(code.into());
        let _ = self.recv.lock().await.stop(code.into());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A way of finding stations that cannot be made, as mDNS is with UDP 5353 unavailable.
    #[derive(Debug)]
    struct Unavailable;

    #[derive(Debug)]
    struct Nothing;

    impl AddressLookup for Nothing {}

    impl AddressLookupBuilder for Unavailable {
        fn into_address_lookup(self, _endpoint: &IrohEndpoint) -> Result<impl AddressLookup, AddressLookupBuilderError> {
            Err::<Nothing, _>(AddressLookupBuilderError::from_err("mdns", std::io::Error::other("no network")))
        }
    }

    #[tokio::test]
    async fn an_unmade_lookup_leaves_the_endpoint_up() {
        let failing = IrohEndpoint::builder(Minimal).relay_mode(RelayMode::Disabled).address_lookup(Unavailable).bind().await;
        assert!(failing.is_err(), "iroh fails an endpoint whose lookup is not made");
        let endpoint = IrohEndpoint::builder(Minimal).relay_mode(RelayMode::Disabled).address_lookup(Optional("mDNS", Unavailable)).bind().await;
        assert!(endpoint.is_ok(), "{:?}", endpoint.err());
        endpoint.unwrap().close().await;
    }
}
