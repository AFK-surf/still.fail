//! The station's iroh for a station written in TypeScript: an endpoint as mesh/station/src/main.rs `serve_mesh` makes
//! it (the station's key, its relays, found on the LAN by mDNS and by relay through the Mainline DHT, cubic with a
//! 256 KiB initial window), and its connections and streams, nothing more. Every decision is the TypeScript's.
//!
//!   const endpoint = await bind({ secretKey, alpns, relayUrls });
//!   for (let conn; (conn = await endpoint.accept()); ) { const stream = await conn.acceptBi(); await stream.read(); … }

use std::sync::Arc;

use iroh::endpoint::{Connection as IrohConnection, QuicTransportConfig, RecvStream, SendStream, presets::Minimal};
use iroh::{Endpoint as IrohEndpoint, RelayMode, RelayUrl, SecretKey};
use napi::bindgen_prelude::Buffer;
use napi_derive::napi;
use tokio::sync::Mutex;

const MDNS_SERVICE: &str = "stillfail";
const FORMER_MDNS_SERVICE: &str = "ember";

fn failed(error: impl std::fmt::Display) -> napi::Error {
    napi::Error::from_reason(error.to_string())
}

#[napi(object)]
pub struct Options {
    /// The station's 32-byte key (<data>/mesh/secret.key).
    pub secret_key: Buffer,
    pub alpns: Vec<Buffer>,
    /// still.fail's relays; none: relays off (tests on one machine).
    pub relay_urls: Vec<String>,
    /// Found on the LAN and through the DHT, as a station is. Off for tests.
    pub discovery: Option<bool>,
}

#[napi]
pub struct Endpoint {
    inner: IrohEndpoint,
}

#[napi]
pub async fn bind(options: Options) -> napi::Result<Endpoint> {
    let bytes: [u8; 32] = options.secret_key.as_ref().try_into().map_err(|_| failed("the key is not 32 bytes"))?;
    let key = SecretKey::from_bytes(&bytes);
    let relays: Vec<RelayUrl> = options.relay_urls.iter().map(|u| u.parse()).collect::<Result<_, _>>().map_err(failed)?;
    let mut cubic = noq_proto::congestion::CubicConfig::default();
    cubic.initial_window(256 * 1024);
    let mut builder = IrohEndpoint::builder(Minimal)
        .secret_key(key.clone())
        .alpns(options.alpns.iter().map(|a| a.to_vec()).collect())
        .relay_mode(if relays.is_empty() { RelayMode::Disabled } else { RelayMode::Custom(iroh::RelayMap::from_iter(relays)) })
        .transport_config(QuicTransportConfig::builder().congestion_controller_factory(Arc::new(cubic)).build());
    if options.discovery.unwrap_or(true) {
        builder = builder
            .address_lookup(iroh_mdns_address_lookup::MdnsAddressLookup::builder().service_name(MDNS_SERVICE))
            .address_lookup(iroh_mdns_address_lookup::MdnsAddressLookup::builder().service_name(FORMER_MDNS_SERVICE))
            .address_lookup(iroh_mainline_address_lookup::DhtAddressLookup::builder().secret_key(key));
    }
    Ok(Endpoint { inner: builder.bind().await.map_err(failed)? })
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

    #[napi]
    pub async fn close(&self) {
        self.inner.close().await;
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

    /// The next stream the client opened; null once the connection is gone.
    #[napi]
    pub async fn accept_bi(&self) -> Option<Stream> {
        let (send, recv) = self.inner.accept_bi().await.ok()?;
        Some(Stream { send: Arc::new(Mutex::new(send)), recv: Arc::new(Mutex::new(recv)) })
    }

    #[napi]
    pub async fn open_bi(&self) -> napi::Result<Stream> {
        let (send, recv) = self.inner.open_bi().await.map_err(failed)?;
        Ok(Stream { send: Arc::new(Mutex::new(send)), recv: Arc::new(Mutex::new(recv)) })
    }

    #[napi]
    pub fn close(&self, code: u32, reason: String) {
        self.inner.close(code.into(), reason.as_bytes());
    }

    /// Resolves when it is gone, with why.
    #[napi]
    pub async fn closed(&self) -> String {
        self.inner.closed().await.to_string()
    }
}

#[napi]
pub struct Stream {
    send: Arc<Mutex<SendStream>>,
    recv: Arc<Mutex<RecvStream>>,
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

    /// Ends it at once (and stops reading).
    #[napi]
    pub async fn reset(&self, code: u32) {
        let _ = self.send.lock().await.reset(code.into());
        let _ = self.recv.lock().await.stop(code.into());
    }
}
