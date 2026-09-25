//! ember's iroh client in the browser. Browsers have no UDP, so every
//! connection goes through the relay. A `Mesh` is this browser's endpoint
//! (its device key); `Mesh.connect` opens a link to a station, presenting a
//! grant from ember cloud; `Link.request` sends one admin API request on its
//! own stream and returns a `Reply` whose body is read chunk by chunk, so
//! event streams work. Wire format: see mesh/station/src/main.rs.

use std::rc::Rc;

use futures::lock::Mutex;
use iroh::{
    Endpoint, EndpointAddr, PublicKey, RelayMode, RelayUrl, SecretKey,
    endpoint::{Connection, RecvStream, SendStream, presets::Minimal},
};
use js_sys::{Promise, Uint8Array};
use wasm_bindgen::prelude::*;
use wasm_bindgen_futures::future_to_promise;

const ALPN: &[u8] = b"ember/admin/1";

fn js(error: impl std::fmt::Display) -> JsValue {
    JsError::new(&error.to_string()).into()
}

async fn read_line(recv: &mut RecvStream, carry: &mut Vec<u8>) -> Result<Option<String>, JsValue> {
    loop {
        if let Some(i) = carry.iter().position(|&b| b == b'\n') {
            let line: Vec<u8> = carry.drain(..=i).collect();
            return Ok(Some(String::from_utf8_lossy(&line[..line.len() - 1]).into_owned()));
        }
        if carry.len() > 64 * 1024 {
            return Err(js("head too large"));
        }
        let mut buf = vec![0u8; 8192];
        match recv.read(&mut buf).await.map_err(js)? {
            Some(n) => carry.extend_from_slice(&buf[..n]),
            None if carry.is_empty() => return Ok(None),
            None => return Err(js("stream ended mid-line")),
        }
    }
}

#[wasm_bindgen]
pub struct Mesh {
    endpoint: Endpoint,
}

#[wasm_bindgen]
impl Mesh {
    /// Binds this browser's endpoint. `secret` is the stored 32-byte device key, or empty to make one.
    pub async fn create(secret: Vec<u8>, relay_url: String) -> Result<Mesh, JsValue> {
        let key = if secret.len() == 32 {
            SecretKey::from_bytes(&secret.try_into().unwrap())
        } else {
            SecretKey::generate()
        };
        let relay: RelayUrl = relay_url.parse().map_err(js)?;
        let endpoint = Endpoint::builder(Minimal)
            .secret_key(key)
            .relay_mode(RelayMode::Custom(relay.into()))
            .bind()
            .await
            .map_err(js)?;
        Ok(Mesh { endpoint })
    }

    /// The device key's public half, in hex: what grants name.
    pub fn id(&self) -> String {
        hex::encode(self.endpoint.id().as_bytes())
    }

    /// The device key, for the page to store.
    pub fn secret(&self) -> Vec<u8> {
        self.endpoint.secret_key().to_bytes().to_vec()
    }

    /// Connects to a station through `relay_url` and presents `grant`. Resolves once the station accepted it.
    pub fn connect(&self, station: String, relay_url: String, grant: String) -> Promise {
        let endpoint = self.endpoint.clone();
        future_to_promise(async move {
            let bytes: [u8; 32] = hex::decode(&station).map_err(js)?.try_into().map_err(|_| js("bad station id"))?;
            let id = PublicKey::from_bytes(&bytes).map_err(js)?;
            let relay: RelayUrl = relay_url.parse().map_err(js)?;
            let conn = endpoint.connect(EndpointAddr::new(id).with_relay_url(relay), ALPN).await.map_err(js)?;
            let (send, recv) = conn.open_bi().await.map_err(js)?;
            let control = Rc::new(Mutex::new(Control { send, recv, carry: Vec::new() }));
            let answer = control.lock().await.exchange(&grant).await?;
            Ok(Link { conn, control, accepted: answer }.into())
        })
    }
}

struct Control {
    send: SendStream,
    recv: RecvStream,
    carry: Vec<u8>,
}

impl Control {
    /// Sends a grant line and returns the station's answer; fails if it refused.
    async fn exchange(&mut self, grant: &str) -> Result<String, JsValue> {
        let line = format!("{}\n", serde_json::json!({ "grant": grant }));
        self.send.write_all(line.as_bytes()).await.map_err(js)?;
        let answer = read_line(&mut self.recv, &mut self.carry).await?.ok_or_else(|| js("station closed the grant stream"))?;
        let value: serde_json::Value = serde_json::from_str(&answer).map_err(js)?;
        if let Some(error) = value["error"].as_str() {
            return Err(js(format!("station refused the grant: {error}")));
        }
        Ok(answer)
    }
}

#[wasm_bindgen]
pub struct Link {
    conn: Connection,
    control: Rc<Mutex<Control>>,
    accepted: String,
}

#[wasm_bindgen]
impl Link {
    /// The station's answer to the first grant (JSON: station name, expiry).
    pub fn accepted(&self) -> String {
        self.accepted.clone()
    }

    /// Presents a fresh grant before the current one runs out.
    pub fn renew(&self, grant: String) -> Promise {
        let control = self.control.clone();
        future_to_promise(async move {
            let answer = control.lock().await.exchange(&grant).await?;
            Ok(JsValue::from_str(&answer))
        })
    }

    /// One request: `head` is the JSON head line, `body` the request body.
    pub fn request(&self, head: String, body: Vec<u8>) -> Promise {
        let conn = self.conn.clone();
        future_to_promise(async move {
            let (mut send, mut recv) = conn.open_bi().await.map_err(js)?;
            send.write_all(format!("{head}\n").as_bytes()).await.map_err(js)?;
            if !body.is_empty() {
                send.write_all(&body).await.map_err(js)?;
            }
            send.finish().map_err(js)?;
            let mut carry = Vec::new();
            let head = read_line(&mut recv, &mut carry).await?.ok_or_else(|| js("station sent no reply"))?;
            Ok(Reply { head, state: Rc::new(Mutex::new(ReplyBody { recv, carry: Some(carry), done: false })) }.into())
        })
    }

    /// Why the connection closed, once it has; null while open.
    pub fn closed(&self) -> Option<String> {
        self.conn.close_reason().map(|reason| reason.to_string())
    }

    pub fn close(&self) {
        self.conn.close(0u32.into(), b"closed");
    }
}

struct ReplyBody {
    recv: RecvStream,
    carry: Option<Vec<u8>>,
    done: bool,
}

#[wasm_bindgen]
pub struct Reply {
    head: String,
    state: Rc<Mutex<ReplyBody>>,
}

#[wasm_bindgen]
impl Reply {
    /// The reply's JSON head line: status and headers.
    pub fn head(&self) -> String {
        self.head.clone()
    }

    /// The next chunk of the body, or undefined at its end.
    pub fn next(&self) -> Promise {
        let state = self.state.clone();
        future_to_promise(async move {
            let mut body = state.lock().await;
            if let Some(carry) = body.carry.take() {
                if !carry.is_empty() {
                    return Ok(Uint8Array::from(carry.as_slice()).into());
                }
            }
            if body.done {
                return Ok(JsValue::UNDEFINED);
            }
            let mut buf = vec![0u8; 32 * 1024];
            match body.recv.read(&mut buf).await.map_err(js)? {
                Some(n) => Ok(Uint8Array::from(&buf[..n]).into()),
                None => {
                    body.done = true;
                    Ok(JsValue::UNDEFINED)
                }
            }
        })
    }

    /// Stops reading the body (e.g. an event stream the page no longer needs).
    pub fn cancel(&self) {
        let state = self.state.clone();
        wasm_bindgen_futures::spawn_local(async move {
            let mut body = state.lock().await;
            body.done = true;
            let _ = body.recv.stop(0u32.into());
        });
    }
}
