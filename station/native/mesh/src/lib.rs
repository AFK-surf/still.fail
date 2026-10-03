//! The station's iroh for the station in TypeScript (docs/station-ts-native.md §3): its endpoint as
//! mesh/station/src/main.rs `serve_mesh` makes it (the station's key, its relays, found on the LAN by mDNS and by relay
//! through the Mainline DHT, cubic with a 256 KiB initial window), keepers on every relay (keep.rs), connections both
//! ways and their streams. Which relays, when to add iroh's public ones, who may connect and what is said: the
//! TypeScript's. And the image codecs of the thumbnails (thumbs.rs).

mod keep;
mod thumbs;
mod local;

use std::collections::HashMap;
use std::sync::{Arc, Mutex as StdMutex};

use iroh::endpoint::{Connection as IrohConnection, QuicTransportConfig, RecvStream, SendStream, presets::Minimal};
use iroh::{Endpoint as IrohEndpoint, EndpointAddr, EndpointId, RelayMode, RelayUrl, SecretKey, Watcher};
use napi::bindgen_prelude::Buffer;
use napi_derive::napi;
use tokio::sync::Mutex;

const MDNS_SERVICE: &str = "stillfail";
const FORMER_MDNS_SERVICE: &str = "ember";

fn failed(error: impl std::fmt::Display) -> napi::Error {
    napi::Error::from_reason(error.to_string())
}

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
    /// Found on the LAN and through the DHT, as a station is. Off for tests.
    pub discovery: Option<bool>,
    /// Where to listen; any free port when not said.
    pub bind_addr: Option<String>,
    /// A client's endpoint (the core in TypeScript, client/core-ts): it looks stations up on the LAN and in the DHT
    /// without being announced itself (a device is never dialed).
    pub lookup: Option<bool>,
    /// Relays alone, no IP transports: what measures the way through a relay must not go direct.
    pub relay_only: Option<bool>,
}

#[napi]
pub struct Endpoint {
    inner: IrohEndpoint,
    keepers: Arc<StdMutex<HashMap<String, tokio::task::JoinHandle<()>>>>,
}

#[napi]
pub async fn bind(options: Options) -> napi::Result<Endpoint> {
    let bytes: [u8; 32] = options.secret_key.as_ref().try_into().map_err(|_| failed("the key is not 32 bytes"))?;
    let key = SecretKey::from_bytes(&bytes);
    let relays: Vec<RelayUrl> = options.relay_urls.iter().map(|u| relay_url(u)).collect::<Result<_, _>>()?;
    let mut cubic = noq_proto::congestion::CubicConfig::default();
    cubic.initial_window(256 * 1024);
    let mut builder = IrohEndpoint::builder(Minimal)
        .secret_key(key.clone())
        .alpns(options.alpns.iter().map(|a| a.to_vec()).collect())
        .relay_mode(if relays.is_empty() { RelayMode::Disabled } else { RelayMode::Custom(iroh::RelayMap::from_iter(relays.clone())) })
        .transport_config(QuicTransportConfig::builder().congestion_controller_factory(Arc::new(cubic)).build());
    if let Some(addr) = &options.bind_addr {
        builder = builder.bind_addr(addr.parse::<std::net::SocketAddr>().map_err(failed)?).map_err(failed)?;
    }
    if options.relay_only.unwrap_or(false) {
        builder = builder.clear_ip_transports();
    }
    if options.lookup.unwrap_or(false) && !relays.is_empty() {
        builder = builder
            .address_lookup(iroh_mdns_address_lookup::MdnsAddressLookup::builder().service_name(MDNS_SERVICE).advertise(false))
            .address_lookup(iroh_mdns_address_lookup::MdnsAddressLookup::builder().service_name(FORMER_MDNS_SERVICE).advertise(false))
            .address_lookup(iroh_mainline_address_lookup::DhtAddressLookup::builder().no_publish());
    } else if options.discovery.unwrap_or(true) {
        builder = builder
            .address_lookup(iroh_mdns_address_lookup::MdnsAddressLookup::builder().service_name(MDNS_SERVICE))
            .address_lookup(iroh_mdns_address_lookup::MdnsAddressLookup::builder().service_name(FORMER_MDNS_SERVICE))
            .address_lookup(iroh_mainline_address_lookup::DhtAddressLookup::builder().secret_key(key));
    }
    Ok(Endpoint { inner: builder.bind().await.map_err(failed)?, keepers: Arc::default() })
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

    /// Keeps the station on exactly these relays, besides its home one (keep.rs): a keeper for each new one, those of
    /// relays no longer named stopped.
    #[napi]
    pub fn keep(&self, urls: Vec<String>) -> napi::Result<()> {
        let relays: Vec<RelayUrl> = urls.iter().map(|u| relay_url(u)).collect::<Result<_, _>>()?;
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

    /// The next connection, its handshake done; null once the endpoint is closed. One that fails its handshake is
    /// skipped.
    #[napi]
    pub async fn accept(&self) -> Option<Connection> {
        while let Some(incoming) = self.inner.accept().await {
            if let Ok(conn) = incoming.await {
                return Some(Connection { inner: conn });
            }
        }
        None
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

    /// The network changed (a phone's, after it slept): its sockets and relay connection looked at anew.
    #[napi]
    pub async fn network_change(&self) {
        self.inner.network_change().await;
    }

    /// Its home relays, and whether it is connected to each now.
    #[napi]
    pub fn relay_status(&self) -> Vec<RelayState> {
        self.inner.home_relay_status().get().iter().map(|s| RelayState { url: s.url().to_string(), connected: s.is_connected() }).collect()
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
}

/// One way a connection can go: through a relay (its URL) or direct; the one chosen now, and its round trip.
#[napi(object)]
pub struct PathState {
    pub selected: bool,
    pub relay: Option<String>,
    pub rtt_ms: f64,
}

/// What went over a connection since it opened, both ways.
#[napi(object)]
pub struct Stats {
    pub rx_bytes: f64,
    pub tx_bytes: f64,
    pub tx_packets: f64,
    pub lost_packets: f64,
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
        self.inner.paths().iter().map(|p| PathState {
            selected: p.is_selected(),
            relay: match p.remote_addr() {
                iroh::TransportAddr::Relay(url) => Some(url.to_string()),
                _ => None,
            },
            rtt_ms: p.rtt().as_secs_f64() * 1000.0,
        }).collect()
    }

    #[napi]
    pub fn stats(&self) -> Stats {
        let stats = self.inner.stats();
        Stats { rx_bytes: stats.udp_rx.bytes as f64, tx_bytes: stats.udp_tx.bytes as f64, tx_packets: stats.udp_tx.datagrams as f64, lost_packets: stats.lost_packets as f64 }
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
}

impl Stream {
    fn new(send: SendStream, recv: RecvStream) -> Stream {
        Stream { send: Arc::new(Mutex::new(send)), recv: Arc::new(Mutex::new(recv)) }
    }
}

#[napi]
impl Stream {
    /// What came next, up to 64 KiB; null at its end.
    #[napi]
    pub async fn read(&self) -> napi::Result<Option<Buffer>> {
        let mut buf = vec![0u8; 64 * 1024];
        match self.recv.lock().await.read(&mut buf).await.map_err(failed)? {
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

    /// Resolves when the other end stops reading (or the stream is gone).
    #[napi]
    pub async fn stopped(&self) {
        // The future owns what it waits on: taken under the lock and awaited without it, so writes go on meanwhile.
        let stopped = self.send.lock().await.stopped();
        let _ = stopped.await;
    }

    /// Ends it at once, both ways.
    #[napi]
    pub async fn reset(&self, code: u32) {
        let _ = self.send.lock().await.reset(code.into());
        let _ = self.recv.lock().await.stop(code.into());
    }
}
