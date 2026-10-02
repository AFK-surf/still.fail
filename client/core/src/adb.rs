//! This phone's adb, lent to a station's agents (docs/adb-share.md): the `adbShare` topic and the `adb.*` calls. While
//! it is offered (`adb.share`, until it is stopped or its hour is up) a stream on the station's link says so, opened
//! again on each link that takes the place of one, and every stream the station opens on that link is a tunnel to the
//! phone's own adbd (Wireless debugging) at the port the app found. Kept in memory only: a core started anew offers
//! nothing. Only a native core reaches adbd; the web's has no sockets.

use std::cell::RefCell;
use std::rc::{Rc, Weak};

use futures::FutureExt;
use futures::channel::oneshot;
use futures::future::LocalBoxFuture;
use iroh::endpoint::{RecvStream, SendStream};
use serde_json::{Value, json};
use stillfail_i18n::t;

use crate::error::{CoreError, Result};
use crate::host::Host;
use crate::mesh::{Link, RequestHead};
use crate::protocol::Topic;
use crate::station::{MeshSource, StationAddr, StationCredentials};
use crate::store::Store;

/// How long an offer lasts unless it says otherwise, and at most.
pub const MINUTES: u32 = 60;
const MAX_MINUTES: u32 = 8 * 60;
/// How long after a lost offer it is made again, doubling up to [`RETRY_MAX_MS`].
const RETRY_MS: u64 = 1_000;
const RETRY_MAX_MS: u64 = 30_000;

#[derive(Debug, Clone, PartialEq)]
pub enum Call {
    /// Offered to `station`, or the offer as it is now (another port, the pairing port open): the app says what it
    /// found of adbd and what the phone is.
    Share(Offer),
    Stop,
    /// The pairing code its person typed: the station pairs its adb through the phone's pairing port.
    Pair { code: String },
    /// The app may turn Wireless debugging on itself from now on (`WRITE_SECURE_SETTINGS`, granted by the station's adb).
    Grant,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Offer {
    pub station: String,
    /// adbd's port for adb (`_adb-tls-connect`), when Wireless debugging is on.
    pub connect: Option<u16>,
    /// Its pairing port (`_adb-tls-pairing`), while the pairing dialog is open.
    pub pair: Option<u16>,
    pub device: String,
    pub android: String,
    /// The app's package, for `adb.grant`.
    pub package: String,
    pub minutes: u32,
}

/// The call `name` names, with its params; `None` when it is none of these.
pub fn parse(name: &str, params: &Value) -> Option<Result<Call>> {
    let text = |field: &str| params.get(field).and_then(Value::as_str).unwrap_or_default().to_string();
    let port = |field: &str| params.get(field).and_then(Value::as_u64).and_then(|p| u16::try_from(p).ok()).filter(|p| *p > 0);
    Some(match name {
        "adb.share" => {
            let station = text("station");
            if StationAddr::parse(&station).is_err() {
                return Some(Err(CoreError::invalid(t!("core-misc.params.missing", field = "station"))));
            }
            let minutes = params.get("minutes").and_then(Value::as_u64).map_or(MINUTES, |m| m.clamp(1, MAX_MINUTES as u64) as u32);
            Ok(Call::Share(Offer { station, connect: port("connect"), pair: port("pair"), device: text("device"), android: text("android"), package: text("package"), minutes }))
        }
        "adb.stop" => Ok(Call::Stop),
        "adb.pair" => Ok(Call::Pair { code: text("code") }),
        "adb.grant" => Ok(Call::Grant),
        _ => return None,
    })
}

/// How the offer goes.
#[derive(Debug, Clone, Copy, PartialEq)]
enum Phase {
    /// Being made: the link opening, or opening again after it went.
    Connecting,
    /// The station has it.
    Offered,
}

#[derive(Default)]
struct State {
    offer: Option<Offer>,
    /// When it ends by itself (ms).
    until: f64,
    /// Which run of `keep` is the offer's: one from before it changed goes.
    run: u64,
    /// Told when the offer changes or stops: the stream that made it is let go.
    changed: Vec<oneshot::Sender<()>>,
    phase: Option<Phase>,
    /// What the station last said of how its adb holds the phone: `{serial, adb, message}`.
    station: Option<Value>,
    /// Why it is not offered now (the link went, the station is too old), while it is tried again or after it stopped.
    problem: Option<String>,
    /// Tunnels open now.
    tunnels: u32,
    /// Told when the offer stops or goes to another station: its tunnels close.
    closing: Vec<oneshot::Sender<()>>,
}

pub struct Adb {
    host: Rc<dyn Host>,
    store: Rc<Store>,
    mesh: MeshSource,
    credentials: StationCredentials,
    state: RefCell<State>,
    me: Weak<Adb>,
}

/// How an offer's stream ended.
enum Ended {
    /// The offer changed or stopped.
    Changed,
    /// Its hour is up.
    Expired,
    /// The station cannot take it: it stops, saying why.
    Refused(String),
    /// The link went (or another took its place): made again, after `pause` unless it was replaced.
    Lost { why: Option<String>, pause: bool },
}

impl Adb {
    pub fn new(host: Rc<dyn Host>, store: Rc<Store>, mesh: MeshSource, credentials: StationCredentials) -> Rc<Adb> {
        Rc::new_cyclic(|me| Adb { host, store, mesh, credentials, state: RefCell::default(), me: me.clone() })
    }

    pub async fn run(&self, call: Call) -> Result<Value> {
        match call {
            Call::Share(offer) => {
                if !tcp::CAN {
                    return Err(CoreError::new("unsupported", t!("core-misc.adb.unsupported")));
                }
                self.share(offer);
                Ok(Value::Null)
            }
            Call::Stop => {
                self.stop(None);
                Ok(Value::Null)
            }
            Call::Pair { code } => {
                let code: String = code.chars().filter(char::is_ascii_digit).collect();
                if code.len() != 6 {
                    return Err(CoreError::invalid(t!("core-misc.adb.pair_code")));
                }
                self.ask(json!({ "op": "pair", "code": code })).await
            }
            Call::Grant => self.ask(json!({ "op": "grant" })).await,
        }
    }

    /// The `adbShare` topic.
    pub fn value(&self) -> Value {
        let s = self.state.borrow();
        let said = |field: &str| s.station.as_ref().and_then(|v| v.get(field)).and_then(Value::as_str).filter(|v| !v.is_empty());
        let phase = match (&s.offer, s.phase) {
            (None, _) => "off",
            (Some(_), Some(Phase::Offered)) => "offered",
            (Some(_), _) => "connecting",
        };
        json!({
            "sharing": s.offer.is_some(),
            "station": s.offer.as_ref().map(|o| o.station.clone()),
            "phase": phase,
            "serial": said("serial").filter(|_| s.offer.is_some()),
            "adb": said("adb").filter(|_| phase == "offered"),
            "message": s.problem.clone().or_else(|| said("message").filter(|_| phase == "offered").map(str::to_string)),
            "until": s.offer.as_ref().map(|_| s.until as i64),
            "tunnels": s.tunnels,
            "connectPort": s.offer.as_ref().and_then(|o| o.connect),
            "pairPort": s.offer.as_ref().and_then(|o| o.pair),
        })
    }

    fn changed(&self) {
        self.store.invalidate(&Topic::AdbShare);
    }

    /// Offered as `offer` says from now: the stream made with the one before is let go, one with this made.
    fn share(&self, offer: Offer) {
        let run = {
            let mut s = self.state.borrow_mut();
            let station_changed = s.offer.as_ref().is_none_or(|o| o.station != offer.station);
            if station_changed {
                s.station = None;
                for close in s.closing.drain(..) {
                    let _ = close.send(());
                }
                s.until = self.host.now_ms() + offer.minutes as f64 * 60_000.0;
            }
            s.offer = Some(offer);
            s.run += 1;
            s.problem = None;
            s.phase = Some(Phase::Connecting);
            for told in s.changed.drain(..) {
                let _ = told.send(());
            }
            s.run
        };
        self.changed();
        if let Some(me) = self.me.upgrade() {
            self.host.spawn(me.keep(run).boxed_local());
        }
    }

    /// Offered no longer (`why`: it stopped by itself).
    fn stop(&self, why: Option<String>) {
        {
            let mut s = self.state.borrow_mut();
            s.offer = None;
            s.run += 1;
            s.phase = None;
            s.station = None;
            s.problem = why;
            let told: Vec<_> = s.changed.drain(..).collect();
            let closing: Vec<_> = s.closing.drain(..).collect();
            for told in told.into_iter().chain(closing) {
                let _ = told.send(());
            }
        }
        self.changed();
    }

    /// The offer, while `run` is its run.
    fn current(&self, run: u64) -> Option<Offer> {
        let s = self.state.borrow();
        s.offer.clone().filter(|_| s.run == run)
    }

    /// The offer made, and made again each time its stream ends, until it changes, stops or is up.
    async fn keep(self: Rc<Self>, run: u64) {
        let mut pause = RETRY_MS;
        while let Some(offer) = self.current(run) {
            let ended = self.offer(run, &offer).await;
            if self.current(run).is_none() {
                return;
            }
            match ended {
                Ended::Changed => return,
                Ended::Expired => return self.stop(Some(t!("core-misc.adb.expired"))),
                Ended::Refused(why) => return self.stop(Some(why)),
                Ended::Lost { why, pause: wait } => {
                    {
                        let mut s = self.state.borrow_mut();
                        s.phase = Some(Phase::Connecting);
                        s.problem = why;
                    }
                    self.changed();
                    if wait {
                        self.host.sleep(pause).await;
                        pause = (pause * 2).min(RETRY_MAX_MS);
                    } else {
                        pause = RETRY_MS;
                    }
                }
            }
        }
    }

    /// The link to the offer's station now.
    async fn link(&self, station: &str) -> Result<(Rc<crate::mesh::Mesh>, Rc<Link>)> {
        let StationAddr { workspace, station } = StationAddr::parse(station)?;
        let mesh = (self.mesh)().await?;
        let link = mesh.link(&station, (self.credentials)(&workspace)).await?;
        Ok((mesh, link))
    }

    /// One stream of the offer on the station's link now, the tunnels the station opens on that link meanwhile; until
    /// either ends, the link is replaced, the offer changes or its time is up.
    async fn offer(&self, run: u64, offer: &Offer) -> Ended {
        let (told, changed) = oneshot::channel();
        self.state.borrow_mut().changed.push(told);
        let (mesh, link) = match self.link(&offer.station).await {
            Ok(opened) => opened,
            Err(error) => return Ended::Lost { why: Some(error.message), pause: true },
        };
        let ask = json!({ "op": "share", "phone": mesh.device_id(), "device": offer.device, "android": offer.android, "package": offer.package, "adbd": offer.connect.is_some(), "pair": offer.pair.is_some() });
        let mut reply = match link.adb(head(), ask).await {
            Ok(reply) => reply,
            Err(error) => return Ended::Lost { why: Some(error.message), pause: true },
        };
        if reply.status == 404 || reply.status == 405 {
            return Ended::Refused(t!("core-misc.adb.station_too_old"));
        }
        if reply.status != 200 {
            let said = String::from_utf8(reply.body().await.unwrap_or_default()).unwrap_or_default();
            return Ended::Lost { why: Some(message(&said).unwrap_or_else(|| t!("core-misc.adb.not_accepted"))), pause: true };
        }
        if self.current(run).is_none() {
            return Ended::Changed;
        }
        {
            let mut s = self.state.borrow_mut();
            s.phase = Some(Phase::Offered);
            s.problem = None;
        }
        self.changed();
        // What the station says of its adb, a line at a time.
        let hears = async {
            let mut carry = Vec::new();
            while let Some(chunk) = reply.next().await {
                let Ok(chunk) = chunk else { break };
                carry.extend(chunk);
                while let Some(at) = carry.iter().position(|b| *b == b'\n') {
                    let line: Vec<u8> = carry.drain(..=at).collect();
                    if let Ok(said) = serde_json::from_slice::<Value>(&line) {
                        if self.current(run).is_some() {
                            self.state.borrow_mut().station = Some(said);
                            self.changed();
                        }
                    }
                }
            }
            Ended::Lost { why: Some(t!("core-misc.adb.station_ended")), pause: true }
        };
        let tunnels = async {
            while let Some((send, recv)) = link.accept().await {
                if let Some(me) = self.me.upgrade() {
                    self.host.spawn(me.tunnel(run, send, recv).boxed_local());
                }
            }
            Ended::Lost { why: Some(link.closed().unwrap_or_else(|| t!("core-misc.adb.link_lost"))), pause: true }
        };
        let replaced = mesh.replaced(&station_id(&offer.station), &link).map(|_| Ended::Lost { why: None, pause: false });
        let changed = changed.map(|_| Ended::Changed);
        let until = self.state.borrow().until;
        let left = (until - self.host.now_ms()).max(0.0) as u64;
        let expired = self.host.sleep(left).map(|_| Ended::Expired);
        let ends: Vec<LocalBoxFuture<'_, Ended>> = vec![hears.boxed_local(), tunnels.boxed_local(), replaced.boxed_local(), changed.boxed_local(), expired.boxed_local()];
        let (ended, _, _) = futures::future::select_all(ends).await;
        // The phone sleeping may have held the clock back: the hour is the wall clock's.
        if !matches!(ended, Ended::Changed) && self.host.now_ms() >= until {
            return Ended::Expired;
        }
        ended
    }

    /// One tunnel the station opened: to adbd's port it names (`connect` or `pair`), then its bytes both ways.
    async fn tunnel(self: Rc<Self>, run: u64, mut send: SendStream, mut recv: RecvStream) {
        let mut carry = Vec::new();
        let Ok(Some(line)) = crate::mesh::read_line(&mut recv, &mut carry).await else { return };
        let kind = serde_json::from_str::<Value>(&line).ok().and_then(|v| v["tunnel"].as_str().map(str::to_string)).unwrap_or_default();
        let Some(offer) = self.current(run) else { return refuse(send, "已经停止共享").await };
        let port = match kind.as_str() {
            "connect" => offer.connect.ok_or("手机上的无线调试没开"),
            "pair" => offer.pair.ok_or("手机上的配对窗口没开"),
            _ => Err("不认识的通道"),
        };
        let port = match port {
            Ok(port) => port,
            Err(why) => return refuse(send, why).await,
        };
        let tcp = match tcp::connect(port).await {
            Ok(tcp) => tcp,
            Err(error) => return refuse(send, &format!("连不上手机上的 adb：{error}")).await,
        };
        let ok = format!("{}\n", json!({ "ok": true }));
        if send.write_all(ok.as_bytes()).await.is_err() {
            return;
        }
        let (close, closed) = oneshot::channel();
        {
            let mut s = self.state.borrow_mut();
            s.tunnels += 1;
            s.closing.push(close);
        }
        self.changed();
        futures::future::select(tcp::pump(tcp, carry, send, recv).boxed_local(), closed).await;
        let mut s = self.state.borrow_mut();
        s.tunnels = s.tunnels.saturating_sub(1);
        drop(s);
        self.changed();
    }

    /// An ask about the offer (`pair`, `grant`) on the station's link now: what it answers.
    async fn ask(&self, ask: Value) -> Result<Value> {
        let Some(offer) = self.state.borrow().offer.clone() else { return Err(CoreError::invalid(t!("core-misc.adb.not_sharing"))) };
        let (mesh, link) = self.link(&offer.station).await?;
        let mut ask = ask;
        ask["phone"] = json!(mesh.device_id());
        let reply = link.adb(head(), ask).await?;
        let status = reply.status;
        let said = String::from_utf8(reply.body().await?).unwrap_or_default();
        let said = message(&said).unwrap_or_default();
        if status == 200 {
            Ok(json!({ "message": said }))
        } else {
            Err(CoreError::invalid(if said.is_empty() { t!("core-misc.adb.failed", status = status) } else { said }))
        }
    }
}

fn head() -> RequestHead {
    RequestHead { method: "POST".into(), path: "/admin/api/adb".into(), headers: Vec::new() }
}

fn station_id(address: &str) -> String {
    StationAddr::parse(address).map(|a| a.station).unwrap_or_default()
}

/// The `message` of a station's JSON answer.
fn message(said: &str) -> Option<String> {
    serde_json::from_str::<Value>(said).ok()?.get("message")?.as_str().map(str::to_string)
}

async fn refuse(mut send: SendStream, why: &str) {
    let line = format!("{}\n", json!({ "error": why }));
    let _ = send.write_all(line.as_bytes()).await;
    let _ = send.finish();
}

/// adbd on this phone: only a native core reaches it (tokio's sockets, on the core's runtime).
#[cfg(all(not(target_arch = "wasm32"), any(feature = "tunnels", test)))]
mod tcp {
    use iroh::endpoint::{RecvStream, SendStream};
    use tokio::io::AsyncWriteExt;
    use tokio::net::TcpStream;

    pub const CAN: bool = true;

    pub async fn connect(port: u16) -> std::io::Result<TcpStream> {
        TcpStream::connect(("127.0.0.1", port)).await
    }

    /// Both ways until either side ends; what came with the station's head line goes first.
    pub async fn pump(tcp: TcpStream, carry: Vec<u8>, mut send: SendStream, mut recv: RecvStream) {
        let (mut from_tcp, mut to_tcp) = tcp.into_split();
        let up = async {
            let _ = tokio::io::copy(&mut from_tcp, &mut send).await;
            let _ = send.finish();
        };
        let down = async {
            if to_tcp.write_all(&carry).await.is_ok() {
                let _ = tokio::io::copy(&mut recv, &mut to_tcp).await;
            }
            let _ = to_tcp.shutdown().await;
        };
        futures::join!(up, down);
    }
}

#[cfg(not(all(not(target_arch = "wasm32"), any(feature = "tunnels", test))))]
mod tcp {
    use iroh::endpoint::{RecvStream, SendStream};

    pub const CAN: bool = false;

    pub struct TcpStream;

    pub async fn connect(_port: u16) -> std::io::Result<TcpStream> {
        Err(std::io::Error::other("这里不能连 adb"))
    }

    pub async fn pump(_tcp: TcpStream, _carry: Vec<u8>, _send: SendStream, _recv: RecvStream) {}
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use std::time::Duration;

    use iroh::endpoint::presets::Minimal;
    use iroh::{Endpoint, EndpointAddr, RelayMode};

    use super::*;
    use crate::cloud::Credential;
    use crate::mesh::{ALPN, CredentialSource, Mesh};
    use crate::testing::{FakeHost, run};
    use crate::trace::Tracer;

    async fn line(recv: &mut RecvStream) -> Value {
        let mut carry = Vec::new();
        let line = crate::mesh::read_line(recv, &mut carry).await.unwrap().unwrap();
        serde_json::from_str(&line).unwrap()
    }

    async fn write(send: &mut SendStream, value: Value) {
        send.write_all(format!("{value}\n").as_bytes()).await.unwrap();
    }

    /// What the station saw: the offer's head, what came back through the tunnel, the offer stopped.
    struct Seen {
        offer: oneshot::Receiver<Value>,
        echoed: oneshot::Receiver<Vec<u8>>,
        stopped: oneshot::Receiver<()>,
    }

    /// A station on localhost that takes a credential, then an offer: answers it, opens a tunnel and says "hello"
    /// through it, and waits for the offer to stop.
    async fn station() -> (Endpoint, EndpointAddr, Seen) {
        let endpoint = Endpoint::builder(Minimal)
            .alpns(vec![ALPN.to_vec()])
            .relay_mode(RelayMode::Disabled)
            .bind_addr("127.0.0.1:0".parse::<std::net::SocketAddr>().unwrap())
            .unwrap()
            .bind()
            .await
            .unwrap();
        let ip = *endpoint.bound_sockets().iter().find(|a| a.ip().is_loopback()).unwrap();
        let addr = EndpointAddr::new(endpoint.id()).with_ip_addr(ip);
        let ((offer_tx, offer), (echoed_tx, echoed), (stopped_tx, stopped)) = (oneshot::channel(), oneshot::channel(), oneshot::channel());
        let accepting = endpoint.clone();
        tokio::task::spawn_local(async move {
            let conn = accepting.accept().await.unwrap().await.unwrap();
            let (mut send, mut recv) = conn.accept_bi().await.unwrap();
            line(&mut recv).await;
            write(&mut send, json!({ "ok": true, "station": "测试" })).await;
            let (mut send, mut recv) = conn.accept_bi().await.unwrap();
            let _ = offer_tx.send(line(&mut recv).await);
            write(&mut send, json!({ "status": 200, "headers": {} })).await;
            write(&mut send, json!({ "serial": "127.0.0.1:37001", "adb": "connected", "message": "" })).await;
            let (mut to, mut from) = conn.open_bi().await.unwrap();
            write(&mut to, json!({ "tunnel": "connect" })).await;
            assert_eq!(line(&mut from).await, json!({ "ok": true }));
            to.write_all(b"hello").await.unwrap();
            let mut back = [0u8; 5];
            from.read_exact(&mut back).await.unwrap();
            let _ = echoed_tx.send(back.to_vec());
            let _ = send.stopped().await;
            let _ = stopped_tx.send(());
            // Held until the test ends.
            futures::future::pending::<()>().await;
        });
        (endpoint, addr, Seen { offer, echoed, stopped })
    }

    /// adbd: says back what it hears.
    async fn adbd() -> u16 {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        tokio::task::spawn_local(async move {
            while let Ok((mut tcp, _)) = listener.accept().await {
                tokio::task::spawn_local(async move {
                    let (mut from, mut to) = tcp.split();
                    let _ = tokio::io::copy(&mut from, &mut to).await;
                });
            }
        });
        port
    }

    #[test]
    fn offers_the_phone_and_tunnels_what_the_station_opens_to_its_adbd() {
        run(async {
            let port = adbd().await;
            let (endpoint, addr, seen) = station().await;
            let host = FakeHost::new();
            let mesh = Mesh::new(host.clone(), Tracer::new(host.clone(), 0.0), &[]).await.unwrap();
            mesh.add_addr(addr);
            let source: MeshSource = Rc::new(move || {
                let mesh = mesh.clone();
                async move { Ok(mesh) }.boxed_local()
            });
            let credentials: StationCredentials = Rc::new(|_: &str| {
                let source: CredentialSource = Rc::new(|_: String, _: bool| async { Ok(Credential { credential: "ok".into(), issued_at: 0.0, expires_at: 0.0, relay_url: String::new() }) }.boxed_local());
                source
            });
            let adb = Adb::new(host.clone(), Store::new(host.clone()), source, credentials);
            let station = format!("ws/{}", hex::encode(endpoint.id().as_bytes()));
            let offer = Offer { station: station.clone(), connect: Some(port), pair: None, device: "Pixel 8".into(), android: "14".into(), package: "fail.still.android".into(), minutes: 60 };
            adb.run(Call::Share(offer)).await.unwrap();
            let mut head = seen.offer.await.unwrap();
            assert_eq!(head["path"], "/admin/api/adb");
            assert_eq!(head["adb"]["phone"].as_str().map(str::len), Some(64));
            head["adb"].as_object_mut().unwrap().remove("phone");
            assert_eq!(head["adb"], json!({ "op": "share", "device": "Pixel 8", "android": "14", "package": "fail.still.android", "adbd": true, "pair": false }));
            assert_eq!(seen.echoed.await.unwrap(), b"hello");
            let value = loop {
                let value = adb.value();
                if value["adb"] == "connected" && value["tunnels"] == 1 {
                    break value;
                }
                tokio::time::sleep(Duration::from_millis(20)).await;
            };
            assert_eq!((value["sharing"].clone(), value["station"].clone(), value["phase"].clone(), value["serial"].clone()), (json!(true), json!(station), json!("offered"), json!("127.0.0.1:37001")));
            adb.run(Call::Stop).await.unwrap();
            tokio::time::timeout(Duration::from_secs(5), seen.stopped).await.expect("the station sees the offer stop").unwrap();
            let value = adb.value();
            assert_eq!((value["sharing"].clone(), value["phase"].clone(), value["tunnels"].clone()), (json!(false), json!("off"), json!(0)));
        });
    }

    #[test]
    fn reads_its_calls() {
        let share = parse("adb.share", &json!({ "station": "ws/st", "connect": 41234, "minutes": 10_000 })).unwrap().unwrap();
        assert_eq!(share, Call::Share(Offer { station: "ws/st".into(), connect: Some(41234), pair: None, device: String::new(), android: String::new(), package: String::new(), minutes: MAX_MINUTES }));
        assert!(parse("adb.share", &json!({})).unwrap().is_err());
        assert_eq!(parse("adb.pair", &json!({ "code": "123456" })).unwrap().unwrap(), Call::Pair { code: "123456".into() });
        assert!(parse("job.stop", &json!({})).is_none());
    }
}
