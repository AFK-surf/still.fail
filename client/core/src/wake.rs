//! The UI coming back after being away (a phone's app or page in the background, frozen; a laptop asleep), or the
//! network changing under it: what is under way is suspect. A mobile browser freezes a hidden page and its worker,
//! Android an app, and the connections under them die with nothing said; on the way back a request may never answer
//! nor fail, and a stream may stay open with nothing on it. There are no timeouts to end those, so a UI says when it
//! is back (`core.wake`), and when the network changed (`network`), and then:
//!
//! - a request still unanswered that has waited a while ([`QUIET_MS`]) fails, for its caller to ask again: whether
//!   it went out before the UI went away or while it was (a phone's app runs a while in the background, and is woken
//!   by a push, and whatever it sent then is on the same dead connections);
//! - a stream (an event stream, still.fail cloud's events socket) that heard nothing for a while ends, and is opened
//!   again;
//! - what waits to reconnect stops waiting (`Host::woken`);
//! - the host lets its connections go ([`Host::reset_connections`]), so what is asked next goes on new ones.
//!
//! When the network changed, everything under way fails, answered or not: every connection was on the old one.
//!
//! A person asking to try again (`retry`: 重试 where a station or still.fail cloud is shown down) is taken as the
//! connections suspect, not gone: what waits stops waiting, what may be asked twice is asked again beside itself, and the
//! links are tried against new ones; nothing under way is failed, as nothing says the network under it went.
//!
//! [`WakingHost`] does the first two for everything that goes through the host; the mesh's links are the mesh's
//! (mesh.rs `watch`) and the stations module's (station.rs `follow_events`).

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use futures::channel::oneshot;
use futures::future::{Either, LocalBoxFuture};
use futures::{FutureExt, StreamExt, pin_mut};

use crate::host::{DbOp, DbRange, Host, HostError, HttpRequest, HttpResponse, SocketFrames, StreamResponse};
use crate::protocol::{ClientId, CoreMessage};

/// Away at least this long: a request waiting since before is given up.
pub const REQUEST_AWAY_MS: f64 = 10_000.0;
/// A request unanswered this long when the UI comes back is taken for one on a dead connection; one sent just before
/// (the UI already asking again) is left to answer.
pub const QUIET_MS: f64 = 3_000.0;
/// Away at least this long: a stream that heard nothing for as long is taken for gone. Longer than a station's
/// keepalive (25 s, mesh/app/src/admin/events.rs) and the events socket's pong (core.rs `SOCKET_PING_MS`), so a
/// stream that is there has said something.
pub const STREAM_AWAY_MS: f64 = 30_000.0;

/// What a request given up fails with.
pub const DROPPED: &str = "页面回到前台，重新请求";
/// What a stream taken for gone ends with.
pub const GONE: &str = "页面回到前台，重新连接";
/// What everything under way fails with when the network changed.
pub const NETWORK: &str = "网络变了，重新连接";

/// The UI came back at `at` (the host's clock) after `away` milliseconds, or the network changed (`network`), or a
/// person asked to try again (`retry`).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Wake {
    pub at: f64,
    pub away: f64,
    pub network: bool,
    pub retry: bool,
}

impl Wake {
    /// When the UI went away.
    pub fn left(&self) -> f64 {
        self.at - self.away
    }

    /// A request that may be asked twice (a read, a write the station keeps to once), sent at `sent` and not answered
    /// yet, is asked again beside it: on new connections (the host's were let go), whichever answers first.
    pub fn hedges_request(&self, sent: f64) -> bool {
        (self.network || self.retry || self.away >= REQUEST_AWAY_MS) && sent <= self.at
    }

    /// A request sent at `sent` and not answered yet is given up.
    pub fn drops_request(&self, sent: f64) -> bool {
        self.network || (self.away >= REQUEST_AWAY_MS && self.at - sent >= QUIET_MS)
    }

    /// A stream that last heard something at `heard` is taken for gone.
    pub fn drops_stream(&self, heard: f64) -> bool {
        self.network || (self.away >= STREAM_AWAY_MS && self.at - heard >= STREAM_AWAY_MS)
    }

    /// Long enough away that the connections under the core are taken for gone (the mesh's links are tried, the
    /// host's let go).
    pub fn suspects_connections(&self) -> bool {
        self.network || self.retry || self.away >= STREAM_AWAY_MS
    }

    /// What what it ends fails with.
    pub fn reason(&self) -> &'static str {
        if self.network { NETWORK } else { GONE }
    }
}

/// Tells whoever waits that the UI is back.
#[derive(Default)]
pub struct Wakes {
    waiting: RefCell<Vec<oneshot::Sender<Wake>>>,
}

impl Wakes {
    pub fn wake(&self, wake: Wake) {
        for waiter in self.waiting.take() {
            let _ = waiter.send(wake);
        }
    }

    /// The next time the UI comes back.
    pub fn next(&self) -> LocalBoxFuture<'static, Wake> {
        let (tx, rx) = oneshot::channel();
        let mut waiting = self.waiting.borrow_mut();
        // Those no longer waited on (their request answered, their stream ended) go.
        waiting.retain(|waiter| !waiter.is_canceled());
        waiting.push(tx);
        // Never sent: the waker went with the core, and so does the wait.
        rx.then(|wake| async move {
            match wake {
                Ok(wake) => wake,
                Err(_) => futures::future::pending().await,
            }
        })
        .boxed_local()
    }
}

/// Resolves at the first wake `drops` says is the end of it.
async fn dropped(wakes: Rc<Wakes>, drops: impl Fn(&Wake) -> bool) -> Wake {
    loop {
        let wake = wakes.next().await;
        if drops(&wake) {
            return wake;
        }
    }
}

/// The first wake `drops` says is the end of something, from the host's wakes (`Host::woken`).
pub async fn woken_for(host: Rc<dyn Host>, drops: impl Fn(&Wake) -> bool) -> Wake {
    loop {
        let wake = host.woken().await;
        if drops(&wake) {
            return wake;
        }
    }
}

/// `pending`, unless a wake says it went out before the UI was away: then an error.
async fn unless_dropped<T>(wakes: Rc<Wakes>, sent: f64, pending: LocalBoxFuture<'static, Result<T, HostError>>) -> Result<T, HostError> {
    let dropped = dropped(wakes, move |wake| wake.drops_request(sent));
    pin_mut!(dropped);
    match futures::future::select(pending, dropped).await {
        Either::Left((result, _)) => result,
        Either::Right((wake, _)) => Err(HostError(if wake.network { NETWORK } else { DROPPED }.into())),
    }
}

/// What a request says to be one that may be asked twice though it is not a read (still.fail cloud's refresh, whose
/// `request_id` makes a second the first's twin; a write to a station that keeps it to once). Taken off before it goes.
pub const HEDGE: &str = "x-stillfail-hedge";

/// A read, or said to be one that may be asked twice ([`HEDGE`]).
fn hedgeable(request: &HttpRequest) -> bool {
    request.method.eq_ignore_ascii_case("GET") || request.method.eq_ignore_ascii_case("HEAD") || request.headers.iter().any(|(k, _)| k.eq_ignore_ascii_case(HEDGE))
}

/// A request that may be asked twice: asked again at each wake that suspects what it went on (up to [`HEDGES`] at
/// once), and the first answer is its answer; one that fails leaves it to the others. Nothing waits to tell whether
/// the first is gone.
async fn hedged<T: 'static>(wakes: Rc<Wakes>, host: Rc<dyn Host>, request: HttpRequest, ask: impl Fn(HttpRequest) -> LocalBoxFuture<'static, Result<T, HostError>>) -> Result<T, HostError> {
    let mut attempts = futures::stream::FuturesUnordered::new();
    attempts.push(ask(request.clone()));
    let mut sent = host.now_ms();
    loop {
        let again = dropped(wakes.clone(), move |wake| wake.hedges_request(sent));
        pin_mut!(again);
        match futures::future::select(attempts.next(), again).await {
            Either::Left((Some(Ok(answer)), _)) => return Ok(answer),
            Either::Left((Some(Err(error)), _)) => {
                if attempts.is_empty() {
                    return Err(error);
                }
            }
            Either::Left((None, _)) => return Err(HostError(DROPPED.into())),
            Either::Right((wake, next)) => {
                drop(next);
                sent = wake.at;
                if attempts.len() < HEDGES {
                    attempts.push(ask(request.clone()));
                }
            }
        }
    }
}

/// At most this many of one request under way at once.
const HEDGES: usize = 3;

/// A stream that ends with an error at a wake when it heard nothing while the UI was away.
fn quiet_ends<T: 'static>(host: Rc<dyn Host>, wakes: Rc<Wakes>, stream: futures::stream::LocalBoxStream<'static, Result<T, HostError>>) -> futures::stream::LocalBoxStream<'static, Result<T, HostError>> {
    let heard = Rc::new(Cell::new(host.now_ms()));
    futures::stream::unfold(Some(stream), move |stream| {
        let (host, wakes, heard) = (host.clone(), wakes.clone(), heard.clone());
        async move {
            let mut stream = stream?;
            let gone = dropped(wakes, {
                let heard = heard.clone();
                move |wake| wake.drops_stream(heard.get())
            });
            pin_mut!(gone);
            match futures::future::select(stream.next(), gone).await {
                Either::Left((Some(item), _)) => {
                    heard.set(host.now_ms());
                    Some((item, Some(stream)))
                }
                Either::Left((None, _)) => None,
                Either::Right((wake, _)) => Some((Err(HostError(wake.reason().into())), None)),
            }
        }
    })
    .boxed_local()
}

/// The host the core runs on, with the rules above for its requests and streams.
pub struct WakingHost {
    inner: Rc<dyn Host>,
    wakes: Rc<Wakes>,
}

impl WakingHost {
    pub fn new(inner: Rc<dyn Host>, wakes: Rc<Wakes>) -> Rc<WakingHost> {
        Rc::new(WakingHost { inner, wakes })
    }
}

impl Host for WakingHost {
    fn cloud_origin(&self) -> String {
        self.inner.cloud_origin()
    }

    fn beta(&self) -> bool {
        self.inner.beta()
    }

    fn fetch(&self, mut request: HttpRequest) -> LocalBoxFuture<'static, Result<HttpResponse, HostError>> {
        if hedgeable(&request) {
            request.headers.retain(|(k, _)| !k.eq_ignore_ascii_case(HEDGE));
            let inner = self.inner.clone();
            return hedged(self.wakes.clone(), self.inner.clone(), request, move |r| inner.fetch(r)).boxed_local();
        }
        unless_dropped(self.wakes.clone(), self.inner.now_ms(), self.inner.fetch(request)).boxed_local()
    }

    fn fetch_stream(&self, mut request: HttpRequest) -> LocalBoxFuture<'static, Result<StreamResponse, HostError>> {
        let (host, wakes) = (self.inner.clone(), self.wakes.clone());
        let opening = if hedgeable(&request) {
            request.headers.retain(|(k, _)| !k.eq_ignore_ascii_case(HEDGE));
            let inner = self.inner.clone();
            hedged(wakes.clone(), host.clone(), request, move |r| inner.fetch_stream(r)).boxed_local()
        } else {
            unless_dropped(wakes.clone(), host.now_ms(), self.inner.fetch_stream(request)).boxed_local()
        };
        async move {
            let response = opening.await?;
            Ok(StreamResponse { body: quiet_ends(host, wakes, response.body), ..response })
        }
        .boxed_local()
    }

    /// Its frames are left to the core (core.rs `follow_socket` opens another beside one it suspects, and lets the
    /// old one go once the new one is open), only its opening is given up.
    fn websocket(&self, url: String, protocols: Vec<String>) -> LocalBoxFuture<'static, Result<SocketFrames, HostError>> {
        unless_dropped(self.wakes.clone(), self.inner.now_ms(), self.inner.websocket(url, protocols)).boxed_local()
    }

    fn storage_get(&self, key: &str) -> LocalBoxFuture<'static, Result<Option<Vec<u8>>, HostError>> {
        self.inner.storage_get(key)
    }

    fn storage_set(&self, key: &str, value: Vec<u8>) -> LocalBoxFuture<'static, Result<(), HostError>> {
        self.inner.storage_set(key, value)
    }

    fn storage_delete(&self, key: &str) -> LocalBoxFuture<'static, Result<(), HostError>> {
        self.inner.storage_delete(key)
    }

    fn db_read(&self, range: DbRange) -> LocalBoxFuture<'static, Result<Vec<(String, Vec<u8>)>, HostError>> {
        self.inner.db_read(range)
    }

    fn db_write(&self, ops: Vec<DbOp>) -> LocalBoxFuture<'static, Result<(), HostError>> {
        self.inner.db_write(ops)
    }

    fn now_ms(&self) -> f64 {
        self.inner.now_ms()
    }

    fn monotonic_ms(&self) -> f64 {
        self.inner.monotonic_ms()
    }

    fn utc_offset_min(&self, at_ms: f64) -> i32 {
        self.inner.utc_offset_min(at_ms)
    }

    fn sleep(&self, ms: u64) -> LocalBoxFuture<'static, ()> {
        self.inner.sleep(ms)
    }

    fn woken(&self) -> LocalBoxFuture<'static, Wake> {
        self.wakes.next()
    }

    fn reset_connections(&self) {
        self.inner.reset_connections()
    }

    fn spawn(&self, task: LocalBoxFuture<'static, ()>) {
        self.inner.spawn(task)
    }

    fn random_bytes(&self, buf: &mut [u8]) {
        self.inner.random_bytes(buf)
    }

    fn emit(&self, client: ClientId, message: CoreMessage) {
        self.inner.emit(client, message)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::{FakeHost, run};

    fn never() -> LocalBoxFuture<'static, Result<(), HostError>> {
        futures::future::pending().boxed_local()
    }

    fn wake(at: f64, away: f64) -> Wake {
        Wake { at, away, network: false, retry: false }
    }

    #[test]
    fn a_request_long_unanswered_fails_when_the_page_is_back() {
        run(async {
            let wakes = Rc::new(Wakes::default());
            let request = unless_dropped(wakes.clone(), 1_000.0, never());
            pin_mut!(request);
            // Back after a short while: it may still come.
            wakes.wake(wake(3_000.0, 1_500.0));
            assert!(futures::poll!(request.as_mut()).is_pending());
            // Away long enough, but it was only just sent (the page asking again as it came back): left alone.
            wakes.wake(wake(1_000.0 + QUIET_MS - 1.0, 60_000.0));
            assert!(futures::poll!(request.as_mut()).is_pending());
            // Sent while the page was away (an app in the background still runs a while), unanswered since: given up.
            wakes.wake(wake(60_000.0, 59_500.0));
            assert_eq!(request.await, Err(HostError(DROPPED.into())));
        });
    }

    #[test]
    fn a_read_under_way_is_asked_again_beside_itself_and_the_first_answer_is_its() {
        run(async {
            let fake = FakeHost::new();
            let asked = Rc::new(Cell::new(0));
            fake.on_fetch({
                let asked = asked.clone();
                move |_| {
                    asked.set(asked.get() + 1);
                    Ok(HttpResponse { status: 200, headers: vec![], body: b"second".to_vec() })
                }
            });
            let wakes = Rc::new(Wakes::default());
            let host: Rc<dyn Host> = fake.clone();
            // The first is on a connection that is gone: it never answers.
            let first_gone = Rc::new(Cell::new(true));
            let ask = {
                let (host, first_gone) = (host.clone(), first_gone.clone());
                move |r: HttpRequest| if first_gone.replace(false) { never_answers() } else { host.fetch(r) }
            };
            let get = HttpRequest { method: "GET".into(), url: "https://x/y".into(), ..Default::default() };
            let answer = hedged(wakes.clone(), host.clone(), get, ask);
            pin_mut!(answer);
            assert!(futures::poll!(answer.as_mut()).is_pending());
            wakes.wake(Wake { at: host.now_ms(), away: 0.0, network: true, retry: false });
            assert_eq!(answer.await.unwrap().body, b"second");
            assert_eq!(asked.get(), 1);
        });
    }

    fn never_answers() -> LocalBoxFuture<'static, Result<HttpResponse, HostError>> {
        futures::future::pending().boxed_local()
    }

    #[test]
    fn only_reads_and_what_says_so_are_asked_twice() {
        let request = |method: &str, headers: Vec<(String, String)>| HttpRequest { method: method.into(), headers, ..Default::default() };
        assert!(hedgeable(&request("GET", vec![])));
        assert!(!hedgeable(&request("POST", vec![])));
        assert!(hedgeable(&request("POST", vec![(HEDGE.into(), "1".into())])));
    }

    #[test]
    fn the_network_changing_fails_every_request_under_way() {
        run(async {
            let wakes = Rc::new(Wakes::default());
            let request = unless_dropped(wakes.clone(), 1_000.0, never());
            pin_mut!(request);
            assert!(futures::poll!(request.as_mut()).is_pending());
            wakes.wake(Wake { at: 1_001.0, away: 0.0, network: true, retry: false });
            assert_eq!(request.await, Err(HostError(NETWORK.into())));
        });
    }

    #[test]
    fn a_retry_fails_nothing_under_way_and_asks_a_read_again_beside_itself() {
        run(async {
            let wakes = Rc::new(Wakes::default());
            let retry = |at: f64| Wake { at, away: 0.0, network: false, retry: true };
            // A write under way: left to answer.
            let write = unless_dropped(wakes.clone(), 1_000.0, never());
            pin_mut!(write);
            assert!(futures::poll!(write.as_mut()).is_pending());
            wakes.wake(retry(60_000.0));
            assert!(futures::poll!(write.as_mut()).is_pending());
            // A read under way: asked again beside it, the first answer its.
            let fake = FakeHost::new();
            fake.on_fetch(|_| Ok(HttpResponse { status: 200, headers: vec![], body: b"again".to_vec() }));
            let host: Rc<dyn Host> = fake.clone();
            let first = Rc::new(Cell::new(true));
            let ask = {
                let (host, first) = (host.clone(), first.clone());
                move |r: HttpRequest| if first.replace(false) { never_answers() } else { host.fetch(r) }
            };
            let get = HttpRequest { method: "GET".into(), url: "https://x/y".into(), ..Default::default() };
            let answer = hedged(wakes.clone(), host.clone(), get, ask);
            pin_mut!(answer);
            assert!(futures::poll!(answer.as_mut()).is_pending());
            wakes.wake(retry(host.now_ms()));
            assert_eq!(answer.await.unwrap().body, b"again");
            // And the connections are suspect: the links are tried against new ones.
            assert!(retry(0.0).suspects_connections());
            assert!(!retry(0.0).drops_stream(0.0));
        });
    }

    #[test]
    fn a_stream_quiet_while_away_ends_and_one_that_spoke_goes_on() {
        run(async {
            let host: Rc<dyn Host> = FakeHost::new();
            let wakes = Rc::new(Wakes::default());
            let (tx, rx) = futures::channel::mpsc::unbounded::<Result<String, HostError>>();
            let mut frames = quiet_ends(host.clone(), wakes.clone(), rx.boxed_local());
            tx.unbounded_send(Ok("hello".into())).unwrap();
            assert_eq!(frames.next().await.unwrap().unwrap(), "hello");
            let heard = host.now_ms();
            let next = frames.next();
            pin_mut!(next);
            assert!(futures::poll!(next.as_mut()).is_pending());
            // It said something while the page was away: it is there.
            wakes.wake(wake(heard + 1_000.0, STREAM_AWAY_MS + 5_000.0));
            assert!(futures::poll!(next.as_mut()).is_pending());
            // Away not long enough to tell.
            wakes.wake(wake(heard + 20_000.0, 10_000.0));
            assert!(futures::poll!(next.as_mut()).is_pending());
            // Nothing since before the page went away: it ends.
            wakes.wake(wake(heard + STREAM_AWAY_MS + 10_000.0, STREAM_AWAY_MS));
            assert_eq!(next.await.unwrap(), Err(HostError(GONE.into())));
            assert!(frames.next().await.is_none());
        });
    }

    #[test]
    fn a_stream_opened_while_away_and_quiet_since_ends() {
        run(async {
            let host: Rc<dyn Host> = FakeHost::new();
            let wakes = Rc::new(Wakes::default());
            let (_tx, rx) = futures::channel::mpsc::unbounded::<Result<String, HostError>>();
            let opened = host.now_ms();
            let mut frames = quiet_ends(host.clone(), wakes.clone(), rx.boxed_local());
            let next = frames.next();
            pin_mut!(next);
            assert!(futures::poll!(next.as_mut()).is_pending());
            // The page went away before it opened (it was opened in the background), and nothing came since.
            wakes.wake(wake(opened + STREAM_AWAY_MS, STREAM_AWAY_MS + 60_000.0));
            assert_eq!(next.await.unwrap(), Err(HostError(GONE.into())));
        });
    }
}
