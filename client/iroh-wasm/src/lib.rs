//! iroh in the browser for the core in TypeScript (client/core-ts/src/iroh.ts, hosts/web.ts): the one thing of the
//! core left in Rust on the web. A relay-only endpoint (a browser has no UDP), its connections to stations and their
//! streams, as station/native/mesh gives them to Node. Which relays, credentials, races and measurements are the
//! TypeScript's (mesh.ts).
//!
//!   const endpoint = await bind({ secretKey, relayUrls });
//!   const conn = await endpoint.connect({ id, relays }, alpn, [former]);
//!   const stream = await conn.openBi(); await stream.write(bytes); const chunk = await stream.read();
//!
//! Every method that waits answers a Promise: each takes what it needs out of `self` first, as wasm-bindgen's futures
//! must own what they hold.

use std::cell::RefCell;
use std::rc::Rc;
use std::sync::Arc;

use futures::channel::oneshot;
use futures::lock::Mutex;
use iroh::endpoint::{Connection as IrohConnection, QuicTransportConfig, RecvStream, SendStream, presets::Minimal};
use iroh::{Endpoint as IrohEndpoint, EndpointAddr, EndpointId, RelayMode, RelayUrl, SecretKey, Watcher};
use js_sys::{Promise, Uint8Array};
use serde::{Deserialize, Serialize};
use wasm_bindgen::prelude::*;
use wasm_bindgen_futures::future_to_promise;

fn failed(error: impl std::fmt::Display) -> JsValue {
    js_sys::Error::new(&error.to_string()).into()
}

fn to_js<T: Serialize>(value: &T) -> Result<JsValue, JsValue> {
    value.serialize(&serde_wasm_bindgen::Serializer::json_compatible()).map_err(failed)
}

fn relay_url(url: &str) -> Result<RelayUrl, JsValue> {
    url.parse().map_err(failed)
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Options {
    /// The device's 32-byte key.
    secret_key: Vec<u8>,
    /// still.fail's relays, its own first.
    relay_urls: Vec<String>,
}

/// Through a relay a round trip is hundreds of milliseconds: a first window of 256 KB sends what a screen needs in
/// one (client/core mesh.rs `INITIAL_WINDOW`, the station's too).
fn transport() -> QuicTransportConfig {
    let mut cubic = noq_proto::congestion::CubicConfig::default();
    cubic.initial_window(256 * 1024);
    QuicTransportConfig::builder().congestion_controller_factory(Arc::new(cubic)).build()
}

/// An endpoint with the device's key on still.fail's relays (none: relays off).
#[wasm_bindgen]
pub fn bind(options: JsValue) -> Promise {
    console_error_panic_hook::set_once();
    future_to_promise(async move {
        let options: Options = serde_wasm_bindgen::from_value(options).map_err(failed)?;
        let bytes: [u8; 32] = options.secret_key.as_slice().try_into().map_err(|_| failed("the key is not 32 bytes"))?;
        let relays: Vec<RelayUrl> = options.relay_urls.iter().map(|u| relay_url(u)).collect::<Result<_, _>>()?;
        let endpoint = IrohEndpoint::builder(Minimal)
            .secret_key(SecretKey::from_bytes(&bytes))
            .relay_mode(if relays.is_empty() { RelayMode::Disabled } else { RelayMode::Custom(iroh::RelayMap::from_iter(relays)) })
            .transport_config(transport())
            .bind()
            .await
            .map_err(failed)?;
        Ok(Endpoint { inner: endpoint }.into())
    })
}

#[derive(Deserialize)]
struct Addr {
    id: String,
    #[serde(default)]
    relays: Option<Vec<String>>,
}

fn endpoint_addr(addr: JsValue) -> Result<EndpointAddr, JsValue> {
    let addr: Addr = serde_wasm_bindgen::from_value(addr).map_err(failed)?;
    let bytes: [u8; 32] = hex::decode(&addr.id).map_err(failed)?.try_into().map_err(|_| failed("the id is not 32 bytes"))?;
    let mut out = EndpointAddr::new(EndpointId::from_bytes(&bytes).map_err(failed)?);
    for url in addr.relays.iter().flatten() {
        out = out.with_relay_url(relay_url(url)?);
    }
    Ok(out)
}

#[wasm_bindgen]
pub struct Endpoint {
    inner: IrohEndpoint,
}

#[derive(Serialize)]
struct RelayState {
    url: String,
    connected: bool,
}

#[wasm_bindgen]
impl Endpoint {
    /// Its id (hex).
    pub fn id(&self) -> String {
        hex::encode(self.inner.id().as_bytes())
    }

    /// A connection to a station offering `alpn` and, for one from before a rename, the `additional` ones.
    pub fn connect(&self, addr: JsValue, alpn: Uint8Array, additional: Vec<Uint8Array>) -> Promise {
        let endpoint = self.inner.clone();
        future_to_promise(async move {
            let options = iroh::endpoint::ConnectOptions::new().with_additional_alpns(additional.iter().map(Uint8Array::to_vec).collect());
            let connecting = endpoint.connect_with_opts(endpoint_addr(addr)?, &alpn.to_vec(), options).await.map_err(failed)?;
            let conn = connecting.await.map_err(failed)?;
            Ok(Connection { inner: conn }.into())
        })
    }

    /// Where an endpoint is, without looking it up.
    #[wasm_bindgen(js_name = addAddr)]
    pub fn add_addr(&self, addr: JsValue) -> Result<(), JsValue> {
        let addr = endpoint_addr(addr)?;
        self.inner.address_lookup().map_err(failed)?.add(iroh::address_lookup::MemoryLookup::from_endpoint_info([addr]));
        Ok(())
    }

    /// The network changed: its relay connection looked at anew.
    #[wasm_bindgen(js_name = networkChange)]
    pub fn network_change(&self) -> Promise {
        let endpoint = self.inner.clone();
        future_to_promise(async move {
            endpoint.network_change().await;
            Ok(JsValue::UNDEFINED)
        })
    }

    /// Its home relays, and whether it is connected to each now.
    #[wasm_bindgen(js_name = relayStatus)]
    pub fn relay_status(&self) -> Result<JsValue, JsValue> {
        let states: Vec<RelayState> = self.inner.home_relay_status().get().iter().map(|s| RelayState { url: s.url().to_string(), connected: s.is_connected() }).collect();
        to_js(&states)
    }

    pub fn close(&self) -> Promise {
        let endpoint = self.inner.clone();
        future_to_promise(async move {
            endpoint.close().await;
            Ok(JsValue::UNDEFINED)
        })
    }
}

#[derive(Serialize)]
struct CloseInfo {
    kind: &'static str,
    reason: String,
}

fn close_info(error: &iroh::endpoint::ConnectionError) -> CloseInfo {
    use iroh::endpoint::ConnectionError;
    match error {
        ConnectionError::ApplicationClosed(close) => CloseInfo { kind: "application", reason: String::from_utf8_lossy(&close.reason).into_owned() },
        ConnectionError::LocallyClosed => CloseInfo { kind: "local", reason: String::new() },
        ConnectionError::TimedOut => CloseInfo { kind: "timeout", reason: String::new() },
        other => CloseInfo { kind: "other", reason: other.to_string() },
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PathState {
    selected: bool,
    relay: Option<String>,
    rtt_ms: f64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Stats {
    rx_bytes: f64,
    tx_bytes: f64,
    tx_packets: f64,
    lost_packets: f64,
}

#[wasm_bindgen]
pub struct Connection {
    inner: IrohConnection,
}

#[wasm_bindgen]
impl Connection {
    #[wasm_bindgen(js_name = remoteId)]
    pub fn remote_id(&self) -> String {
        hex::encode(self.inner.remote_id().as_bytes())
    }

    /// The next stream the other end opened; null once the connection is gone.
    #[wasm_bindgen(js_name = acceptBi)]
    pub fn accept_bi(&self) -> Promise {
        let conn = self.inner.clone();
        future_to_promise(async move {
            Ok(match conn.accept_bi().await {
                Ok((send, recv)) => Stream::new(Some(send), Some(recv)).into(),
                Err(_) => JsValue::NULL,
            })
        })
    }

    #[wasm_bindgen(js_name = openBi)]
    pub fn open_bi(&self) -> Promise {
        let conn = self.inner.clone();
        future_to_promise(async move {
            let (send, recv) = conn.open_bi().await.map_err(failed)?;
            Ok(Stream::new(Some(send), Some(recv)).into())
        })
    }

    /// A stream one way (read answers null at once).
    #[wasm_bindgen(js_name = openUni)]
    pub fn open_uni(&self) -> Promise {
        let conn = self.inner.clone();
        future_to_promise(async move {
            let send = conn.open_uni().await.map_err(failed)?;
            Ok(Stream::new(Some(send), None).into())
        })
    }

    pub fn close(&self, code: u32, reason: String) {
        self.inner.close(code.into(), reason.as_bytes());
    }

    /// Why it is gone (`{kind, reason}`), or null while it is not.
    #[wasm_bindgen(js_name = closeReason)]
    pub fn close_reason(&self) -> Result<JsValue, JsValue> {
        match self.inner.close_reason() {
            Some(e) => to_js(&close_info(&e)),
            None => Ok(JsValue::NULL),
        }
    }

    /// Resolves when it is gone, with why.
    #[wasm_bindgen(js_name = closedInfo)]
    pub fn closed_info(&self) -> Promise {
        let conn = self.inner.clone();
        future_to_promise(async move { to_js(&close_info(&conn.closed().await)) })
    }

    pub fn paths(&self) -> Result<JsValue, JsValue> {
        let paths: Vec<PathState> = self
            .inner
            .paths()
            .iter()
            .map(|p| PathState {
                selected: p.is_selected(),
                relay: match p.remote_addr() {
                    iroh::TransportAddr::Relay(url) => Some(url.to_string()),
                    _ => None,
                },
                rtt_ms: p.rtt().as_secs_f64() * 1000.0,
            })
            .collect();
        to_js(&paths)
    }

    pub fn stats(&self) -> Result<JsValue, JsValue> {
        let s = self.inner.stats();
        to_js(&Stats { rx_bytes: s.udp_rx.bytes as f64, tx_bytes: s.udp_tx.bytes as f64, tx_packets: s.udp_tx.datagrams as f64, lost_packets: s.lost_packets as f64 })
    }
}

/// The halves of a stream, and the reads waiting on it: `reset` wakes them first, so the receiving half is let go.
struct Halves {
    send: Mutex<Option<SendStream>>,
    recv: Mutex<Option<RecvStream>>,
    reset: RefCell<bool>,
    waiting: RefCell<Vec<oneshot::Sender<()>>>,
}

#[wasm_bindgen]
pub struct Stream {
    halves: Rc<Halves>,
}

impl Stream {
    fn new(send: Option<SendStream>, recv: Option<RecvStream>) -> Stream {
        Stream { halves: Rc::new(Halves { send: Mutex::new(send), recv: Mutex::new(recv), reset: RefCell::new(false), waiting: RefCell::default() }) }
    }
}

#[wasm_bindgen]
impl Stream {
    /// What came next, up to 64 KiB; null at its end (or once it was reset).
    pub fn read(&self) -> Promise {
        let halves = self.halves.clone();
        future_to_promise(async move {
            if *halves.reset.borrow() {
                return Ok(JsValue::NULL);
            }
            let (woken, wake) = oneshot::channel();
            // Those of reads done are let go.
            halves.waiting.borrow_mut().retain(|w| !w.is_canceled());
            halves.waiting.borrow_mut().push(woken);
            let mut recv = halves.recv.lock().await;
            let Some(recv) = recv.as_mut() else { return Ok(JsValue::NULL) };
            let mut buf = vec![0u8; 64 * 1024];
            let read = match futures::future::select(Box::pin(recv.read(&mut buf)), wake).await {
                futures::future::Either::Left((read, _)) => read,
                futures::future::Either::Right(_) => Ok(None),
            };
            match read {
                Ok(Some(n)) => Ok(Uint8Array::from(&buf[..n]).into()),
                Ok(None) => Ok(JsValue::NULL),
                Err(e) => Err(failed(e)),
            }
        })
    }

    pub fn write(&self, bytes: Uint8Array) -> Promise {
        let halves = self.halves.clone();
        future_to_promise(async move {
            let mut send = halves.send.lock().await;
            let send = send.as_mut().ok_or_else(|| failed("no sending half"))?;
            send.write_all(&bytes.to_vec()).await.map_err(failed)?;
            Ok(JsValue::UNDEFINED)
        })
    }

    pub fn finish(&self) -> Promise {
        let halves = self.halves.clone();
        future_to_promise(async move {
            if let Some(send) = halves.send.lock().await.as_mut() {
                send.finish().map_err(failed)?;
            }
            Ok(JsValue::UNDEFINED)
        })
    }

    /// Once what was sent is acknowledged: null, or the code the other end stopped it with.
    pub fn stopped(&self) -> Promise {
        let halves = self.halves.clone();
        future_to_promise(async move {
            // Taken under the lock and awaited without it, so writes go on meanwhile.
            let stopped = match halves.send.lock().await.as_mut() {
                Some(send) => send.stopped(),
                None => return Ok(JsValue::NULL),
            };
            Ok(match stopped.await {
                Ok(Some(code)) => JsValue::from_f64(code.into_inner() as f64),
                _ => JsValue::NULL,
            })
        })
    }

    /// Ends it at once, both ways.
    pub fn reset(&self, code: u32) -> Promise {
        let halves = self.halves.clone();
        future_to_promise(async move {
            *halves.reset.borrow_mut() = true;
            for wake in halves.waiting.borrow_mut().drain(..) {
                let _ = wake.send(());
            }
            if let Some(send) = halves.send.lock().await.as_mut() {
                let _ = send.reset(code.into());
            }
            if let Some(recv) = halves.recv.lock().await.as_mut() {
                let _ = recv.stop(code.into());
            }
            Ok(JsValue::UNDEFINED)
        })
    }
}
