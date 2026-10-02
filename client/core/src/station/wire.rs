//! Mesh transport and preview socket framing.
use super::*;

// ── the wire ────────────────────────────────────────────────────────────────

/// A station's answer: status, headers, and the body as it arrives.
pub struct WireReply {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: LocalBoxStream<'static, Result<Vec<u8>>>,
    /// How it came, when the wire knows: `relay` or `direct`.
    pub via: Option<&'static str>,
}

impl WireReply {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers.iter().find(|(k, _)| k.eq_ignore_ascii_case(name)).map(|(_, v)| v.as_str())
    }

    /// The whole body.
    pub async fn bytes(mut self) -> Result<Vec<u8>> {
        let mut out = Vec::new();
        while let Some(chunk) = self.body.next().await {
            out.extend(chunk?);
        }
        Ok(out)
    }
}

/// How requests reach a station. `head.path` includes `/admin/api`; a request
/// for an event stream carries `accept: text/event-stream`.
pub trait StationWire {
    fn request(&self, station: &StationAddr, head: RequestHead, body: Vec<u8>) -> LocalBoxFuture<'static, Result<WireReply>>;
    /// The way to the station is taken for gone (wake.rs): what is open to it closes, and the next request opens it anew.
    fn reset(&self, _station: &StationAddr) {}
    /// Whether the wire itself finds another way to a station when the UI comes back or the network changes (the
    /// mesh races a new link against each open one, mesh.rs `race`), rather than leaving it to the wake rules.
    fn races(&self) -> bool {
        false
    }
    /// Resolves once the way to the station that a request would take now is replaced by another: a stream on it is
    /// then opened again on the new one. Never, for a wire that does not race.
    fn replaced(&self, _station: &StationAddr) -> LocalBoxFuture<'static, ()> {
        futures::future::pending().boxed_local()
    }
    /// How the connection to the station runs now (its path, round trip, bytes both ways), for its card; None where
    /// there is none of its own to read (the page's own station, over HTTP) or none open.
    fn net(&self, _station: &StationAddr) -> Option<LinkNet> {
        None
    }
    /// Measures the ways to the station now (mesh.rs `Mesh::remeasure`). Only the mesh has more than one.
    fn measure(&self, _station: &StationAddr) -> LocalBoxFuture<'static, Result<()>> {
        async { Err(CoreError::new("unsupported", t!("station.core.oneWay"))) }.boxed_local()
    }
    /// A preview page's WebSocket (`head.path` a preview's): the station's reply, then its frames both ways
    /// ([`SocketFrame`]). Only the mesh carries one.
    fn socket(&self, _station: &StationAddr, _head: RequestHead) -> LocalBoxFuture<'static, Result<WireSocket>> {
        async { Err(CoreError::new("unsupported", t!("station.core.previewNoSocket"))) }.boxed_local()
    }
}

/// A socket stream as it opened: the station's reply (101 once the service took the socket, else why not in its
/// body), the frames that come in the body, and where the client's frames go.
pub struct WireSocket {
    pub reply: WireReply,
    pub send: Box<dyn SocketOut>,
}

/// The client's half of a socket stream. Dropping it resets the stream.
pub trait SocketOut {
    fn write<'a>(&'a mut self, bytes: Vec<u8>) -> LocalBoxFuture<'a, Result<()>>;
    fn finish(&mut self);
}

impl SocketOut for crate::mesh::SocketSend {
    fn write<'a>(&'a mut self, bytes: Vec<u8>) -> LocalBoxFuture<'a, Result<()>> {
        async move { crate::mesh::SocketSend::write(self, &bytes).await }.boxed_local()
    }
    fn finish(&mut self) {
        crate::mesh::SocketSend::finish(self);
    }
}

/// A WebSocket message on a socket stream, framed as mesh/app/src/preview.rs frames it: a kind byte (1 text, 2 binary,
/// 8 close), the payload's length (4 bytes, big-endian), the payload; a close's is its code (2 bytes) and reason.
#[derive(Debug, Clone, PartialEq)]
pub enum SocketFrame {
    Text(String),
    Binary(Vec<u8>),
    Close(u16, String),
}

impl SocketFrame {
    pub fn encode(&self) -> Vec<u8> {
        let (kind, payload) = match self {
            SocketFrame::Text(text) => (1u8, text.as_bytes().to_vec()),
            SocketFrame::Binary(bytes) => (2, bytes.clone()),
            SocketFrame::Close(code, reason) => (8, [&code.to_be_bytes()[..], reason.as_bytes()].concat()),
        };
        let mut out = Vec::with_capacity(5 + payload.len());
        out.push(kind);
        out.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        out.extend(payload);
        out
    }

    /// The frames whole in `buf`, taken from it; what is left is the start of the next.
    pub fn take(buf: &mut Vec<u8>) -> Vec<SocketFrame> {
        let mut frames = Vec::new();
        let mut at = 0;
        while buf.len() - at >= 5 {
            let len = u32::from_be_bytes([buf[at + 1], buf[at + 2], buf[at + 3], buf[at + 4]]) as usize;
            if buf.len() - at - 5 < len {
                break;
            }
            let payload = &buf[at + 5..at + 5 + len];
            match buf[at] {
                1 => frames.push(SocketFrame::Text(String::from_utf8_lossy(payload).into_owned())),
                2 => frames.push(SocketFrame::Binary(payload.to_vec())),
                8 => {
                    let code = if payload.len() >= 2 { u16::from_be_bytes([payload[0], payload[1]]) } else { 1005 };
                    frames.push(SocketFrame::Close(code, String::from_utf8_lossy(payload.get(2..).unwrap_or_default()).into_owned()));
                }
                _ => {}
            }
            at += 5 + len;
        }
        buf.drain(..at);
        frames
    }
}

/// This device's endpoint, bound when first needed.
pub type MeshSource = Rc<dyn Fn() -> LocalBoxFuture<'static, Result<Rc<Mesh>>>>;
/// Grants for one station, given (workspace, station): the caller decides which account asks.
/// This device's credential for a workspace's stations (every one of them takes the same).
pub type StationCredentials = Rc<dyn Fn(&str) -> CredentialSource>;

/// Remote stations, over mesh links.
pub struct MeshWire {
    mesh: MeshSource,
    credentials: StationCredentials,
    /// Each workspace's waits: a link's are its workspace's, the relay brought up for it too.
    status: StatusOf,
    /// Stations that said they keep writes with a key to once ([`IDEMPOTENT`]), by id.
    idempotent: Rc<RefCell<HashSet<String>>>,
}

impl MeshWire {
    pub fn new(mesh: MeshSource, credentials: StationCredentials, status: StatusOf) -> Rc<MeshWire> {
        Rc::new(MeshWire { mesh, credentials, status, idempotent: Rc::default() })
    }
}

/// Whichever of two attempts answers; one that fails leaves it to the other.
pub(super) async fn first_answer<T>(a: LocalBoxFuture<'static, Result<T>>, b: LocalBoxFuture<'static, Result<T>>) -> Result<T> {
    match futures::future::select(a, b).await {
        Either::Left((Ok(answer), _)) | Either::Right((Ok(answer), _)) => Ok(answer),
        Either::Left((Err(_), other)) | Either::Right((Err(_), other)) => other.await,
    }
}

impl StationWire for MeshWire {
    fn request(&self, station: &StationAddr, head: RequestHead, body: Vec<u8>) -> LocalBoxFuture<'static, Result<WireReply>> {
        let StationAddr { workspace, station } = station.clone();
        let mesh = (self.mesh)();
        let credentials = (self.credentials)(&workspace);
        let (status, address) = ((self.status)(&workspace), Place::Station(format!("{workspace}/{station}")));
        let (idempotent, reply_station) = (self.idempotent.clone(), station.clone());
        async move {
            // Bringing up the endpoint (the relay) and opening the link are waits of their own: a request slow for
            // them says so (status.rs).
            let mesh = {
                let _waiting = status.begin(Place::Relay, t!("station.core.connecting"), true);
                mesh.await?
            };
            let link = {
                let _waiting = status.begin(address.clone(), t!("station.core.connecting"), true);
                mesh.link(&station, credentials.clone()).await?
            };
            let repeats = may_repeat(&head, idempotent.borrow().contains(&station));
            let write = !head.method.eq_ignore_ascii_case("GET") && !head.method.eq_ignore_ascii_case("HEAD");
            let ask = |link: Rc<Link>, head: RequestHead, body: Vec<u8>| async move { link.request(head, body).await.map(|reply| (link, reply)) }.boxed_local();
            let first = ask(link.clone(), head.clone(), body.clone());
            let (link, reply) = if repeats {
                // The link is replaced while this is under way (it lost to a new one as the UI came back, mesh.rs
                // `race`): asked again on the new one at once, and whichever answers first is the answer. A read may be
                // asked twice; a write only with its key, to a station that keeps it to once.
                match futures::future::select(first, mesh.replaced(&station, &link)).await {
                    // A write gone and not answered: asked again with its key whenever its station is back, a while, so
                    // what is said is what happened (the station answers the first time's answer, or does it now).
                    Either::Left((Err(error), _)) if error.code == "mesh" && write => {
                        let _waiting = status.begin(address, RECHECKING, true);
                        let started = mesh.now_ms();
                        let mut pause = 1_000;
                        loop {
                            let again = async {
                                let link = mesh.link(&station, credentials.clone()).await?;
                                ask(link, head.clone(), body.clone()).await
                            };
                            match again.await {
                                Ok(answered) => break answered,
                                Err(e) if e.code != "mesh" => return Err(e),
                                Err(e) if mesh.now_ms() - started >= RECHECK_MS => return Err(unconfirmed(&e)),
                                Err(_) => {
                                    mesh.sleep(pause).await;
                                    pause = (pause * 2).min(15_000);
                                }
                            }
                        }
                    }
                    Either::Left((Err(error), _)) if error.code == "mesh" => {
                        // Its link went before it was answered (the station restarting, a network change): once more,
                        // on the link opened in its place.
                        let _waiting = status.begin(address, t!("station.core.connecting"), true);
                        let link = mesh.link(&station, credentials).await?;
                        drop(_waiting);
                        ask(link, head, body).await?
                    }
                    Either::Left((answered, _)) => answered?,
                    Either::Right((_, first)) => {
                        let again = async move {
                            let link = mesh.link(&station, credentials).await?;
                            ask(link, head, body).await
                        }
                        .boxed_local();
                        first_answer(first, again).await?
                    }
                }
            } else {
                // A station that may do a write twice is not asked again: one gone and not answered may have been done.
                first.await.map_err(|e| if write && e.code == "mesh" { unconfirmed(&e) } else { e })?
            };
            if reply.headers.iter().any(|(k, _)| k.eq_ignore_ascii_case(IDEMPOTENT)) {
                idempotent.borrow_mut().insert(reply_station);
            }
            let (status, headers) = (reply.status, reply.headers.clone());
            let body = futures::stream::unfold(reply, |mut reply| async move { reply.next().await.map(|chunk| (chunk, reply)) });
            Ok(WireReply { status, headers, body: body.boxed_local(), via: link.path() })
        }
        .boxed_local()
    }

    fn reset(&self, station: &StationAddr) {
        let station = &station.station;
        // Only a link already made: nothing to close before the endpoint is up.
        if let Some(Ok(mesh)) = (self.mesh)().now_or_never() {
            mesh.drop_link(station);
        }
    }

    fn races(&self) -> bool {
        true
    }

    fn replaced(&self, station: &StationAddr) -> LocalBoxFuture<'static, ()> {
        let (Some(Ok(mesh)), station) = ((self.mesh)().now_or_never(), station.station.clone()) else { return futures::future::pending().boxed_local() };
        let Some(link) = mesh.current(&station) else { return futures::future::pending().boxed_local() };
        mesh.replaced(&station, &link)
    }

    fn net(&self, station: &StationAddr) -> Option<LinkNet> {
        let Some(Ok(mesh)) = (self.mesh)().now_or_never() else { return None };
        mesh.current(&station.station).map(|link| LinkNet { measured: mesh.measured(&station.station), today: Some(mesh.today(&station.station)), ..link.net() })
    }

    fn measure(&self, station: &StationAddr) -> LocalBoxFuture<'static, Result<()>> {
        let (mesh, id) = ((self.mesh)(), station.station.clone());
        async move { mesh.await?.remeasure(&id).await }.boxed_local()
    }

    fn socket(&self, station: &StationAddr, head: RequestHead) -> LocalBoxFuture<'static, Result<WireSocket>> {
        let StationAddr { workspace, station } = station.clone();
        let mesh = (self.mesh)();
        let credentials = (self.credentials)(&workspace);
        let (status, address) = ((self.status)(&workspace), Place::Station(format!("{workspace}/{station}")));
        async move {
            let mesh = {
                let _waiting = status.begin(Place::Relay, t!("station.core.connecting"), true);
                mesh.await?
            };
            let link = {
                let _waiting = status.begin(address, t!("station.core.connecting"), true);
                mesh.link(&station, credentials).await?
            };
            let (reply, send) = link.socket(head).await?;
            let (status, headers) = (reply.status, reply.headers.clone());
            let body = futures::stream::unfold(reply, |mut reply| async move { reply.next().await.map(|chunk| (chunk, reply)) });
            Ok(WireSocket { reply: WireReply { status, headers, body: body.boxed_local(), via: link.path() }, send: Box::new(send) })
        }
        .boxed_local()
    }
}

/// The real wire: mesh links.
pub fn wire(mesh: MeshSource, credentials: StationCredentials, status: StatusOf) -> Rc<dyn StationWire> {
    MeshWire::new(mesh, credentials, status)
}

