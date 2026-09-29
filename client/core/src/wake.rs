//! The UI coming back after being away (a phone's page in the background, frozen): what went out before is
//! suspect. A mobile browser freezes a hidden page and its worker and cuts their connections, and on the way back
//! a request sent before may never answer nor fail, and a stream may stay open with nothing on it. There are no
//! timeouts to end those, so a UI says when it is back (`core.wake`), and then:
//!
//! - a request still unanswered that was sent before the UI went away fails, for its caller to ask again;
//! - a stream (an event stream, still.fail cloud's events socket) that heard nothing while the UI was away ends, and
//!   is opened again;
//! - what waits to reconnect stops waiting (`Host::woken`).
//!
//! [`WakingHost`] does the first two for everything that goes through the host; the mesh's links are the
//! stations module's (station.rs `follow_events`).

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use futures::channel::oneshot;
use futures::future::{Either, LocalBoxFuture};
use futures::{FutureExt, StreamExt, pin_mut};

use crate::host::{DbOp, DbRange, Host, HostError, HttpRequest, HttpResponse, SocketFrames, StreamResponse};
use crate::protocol::{ClientId, CoreMessage};

/// Away at least this long: a request sent before is given up.
pub const REQUEST_AWAY_MS: f64 = 10_000.0;
/// Away at least this long: a stream that heard nothing meanwhile is taken for gone. Longer than a station's
/// keepalive (25 s, mesh/app/src/admin/events.rs), so a stream that is there has said something.
pub const STREAM_AWAY_MS: f64 = 30_000.0;

/// What a request given up fails with.
pub const DROPPED: &str = "页面回到前台，重新请求";
/// What a stream taken for gone ends with.
pub const GONE: &str = "页面回到前台，重新连接";

/// The UI came back at `at` (the host's clock) after `away` milliseconds.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Wake {
    pub at: f64,
    pub away: f64,
}

impl Wake {
    /// When the UI went away.
    pub fn left(&self) -> f64 {
        self.at - self.away
    }

    /// A request sent at `sent` and not answered yet is given up.
    pub fn drops_request(&self, sent: f64) -> bool {
        self.away >= REQUEST_AWAY_MS && sent <= self.left()
    }

    /// A stream that last heard something at `heard` is taken for gone.
    pub fn drops_stream(&self, heard: f64) -> bool {
        self.away >= STREAM_AWAY_MS && heard <= self.left()
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
        Either::Right(_) => Err(HostError(DROPPED.into())),
    }
}

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
                Either::Right(_) => Some((Err(HostError(GONE.into())), None)),
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

    fn fetch(&self, request: HttpRequest) -> LocalBoxFuture<'static, Result<HttpResponse, HostError>> {
        unless_dropped(self.wakes.clone(), self.inner.now_ms(), self.inner.fetch(request)).boxed_local()
    }

    fn fetch_stream(&self, request: HttpRequest) -> LocalBoxFuture<'static, Result<StreamResponse, HostError>> {
        let (host, wakes) = (self.inner.clone(), self.wakes.clone());
        let opening = unless_dropped(wakes.clone(), host.now_ms(), self.inner.fetch_stream(request));
        async move {
            let response = opening.await?;
            Ok(StreamResponse { body: quiet_ends(host, wakes, response.body), ..response })
        }
        .boxed_local()
    }

    fn websocket(&self, url: String, protocols: Vec<String>) -> LocalBoxFuture<'static, Result<SocketFrames, HostError>> {
        let (host, wakes) = (self.inner.clone(), self.wakes.clone());
        let opening = unless_dropped(wakes.clone(), host.now_ms(), self.inner.websocket(url, protocols));
        async move { Ok(quiet_ends(host, wakes, opening.await?)) }.boxed_local()
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

    #[test]
    fn a_request_from_before_the_page_went_away_fails_when_it_is_back() {
        run(async {
            let wakes = Rc::new(Wakes::default());
            let request = unless_dropped(wakes.clone(), 1_000.0, never());
            pin_mut!(request);
            // Back after a short while: it may still come.
            wakes.wake(Wake { at: 3_000.0, away: 1_500.0 });
            assert!(futures::poll!(request.as_mut()).is_pending());
            // Sent after the page went away: left alone.
            wakes.wake(Wake { at: 60_000.0, away: 59_500.0 });
            assert!(futures::poll!(request.as_mut()).is_pending());
            // Sent before, and away long enough: given up.
            wakes.wake(Wake { at: 60_000.0, away: 59_000.0 });
            assert_eq!(request.await, Err(HostError(DROPPED.into())));
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
            wakes.wake(Wake { at: heard + 1_000.0, away: STREAM_AWAY_MS + 5_000.0 });
            assert!(futures::poll!(next.as_mut()).is_pending());
            // Away not long enough to tell.
            wakes.wake(Wake { at: heard + 20_000.0, away: 10_000.0 });
            assert!(futures::poll!(next.as_mut()).is_pending());
            // Nothing since before the page went away: it ends.
            wakes.wake(Wake { at: heard + STREAM_AWAY_MS + 10_000.0, away: STREAM_AWAY_MS });
            assert_eq!(next.await.unwrap(), Err(HostError(GONE.into())));
            assert!(frames.next().await.is_none());
        });
    }
}
