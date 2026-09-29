//! Handing the station over to its next binary without stopping its agents (`ember update`).
//!
//! The station execs the new binary in its own process: the pid stays, so the runtimes and jobs it started stay its
//! children, and whatever it keeps open across exec goes on. Before that it stops taking anything new: its listening
//! sockets stop accepting (connections wait in the kernel's backlog for the new binary), turns are held, and each
//! runtime's reader stops at a line boundary (what the runtime writes meanwhile waits in its pipe). What it hands over
//! is written to a file the new binary is pointed to: the descriptors it left open, and where each session stood.
//! A binary that cannot read the file (another VERSION) is never exec'd: the old one asks it first.

use std::net::TcpListener as StdListener;
use std::os::fd::{FromRawFd, IntoRawFd, OwnedFd};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::watch;
use tokio::task::JoinHandle;
use tracing::warn;

use crate::hub::HandedHub;
use crate::runtime::process::{claim_fd, keep_across_exec};

/// What a handoff file's shape is. The old binary execs the new one only when the new one says it reads this one.
pub const VERSION: u32 = 1;

/// What the app hands over (the station's binary adds its own around it).
#[derive(Serialize, Deserialize, Debug, Clone, Default)]
pub struct HandedApp {
    /// The agents' MCP endpoint's listening socket.
    pub mcp: Option<i32>,
    #[serde(default)]
    pub hub: HandedHub,
}

impl HandedApp {
    /// The process groups handed over (runtimes'), which the new binary must not reap.
    pub fn pgids(&self) -> Vec<i64> {
        fn walk(v: &Value, out: &mut Vec<i64>) {
            match v {
                Value::Object(map) => {
                    if let (Some(pgid), true) = (map.get("pgid").and_then(Value::as_i64), map.contains_key("stdout")) {
                        out.push(pgid);
                    }
                    map.values().for_each(|v| walk(v, out));
                }
                Value::Array(items) => items.iter().for_each(|v| walk(v, out)),
                _ => {}
            }
        }
        let mut out = vec![];
        walk(&serde_json::to_value(&self.hub).unwrap_or(Value::Null), &mut out);
        out
    }
}

/// A listening socket handed over, as tokio's.
pub fn claim_listener(fd: i32) -> Result<TcpListener> {
    let owned: OwnedFd = claim_fd(fd)?;
    // SAFETY: the handoff says this descriptor is a listening TCP socket, and it is ours alone (claimed above).
    let std = unsafe { StdListener::from_raw_fd(owned.into_raw_fd()) };
    std.set_nonblocking(true)?;
    Ok(TcpListener::from_std(std)?)
}

/// A listening socket whose accepting can stop and start again, and be given up for the next binary. Requests under
/// way are counted (Door::busy), so stopping waits for them; connections still open are asked to close once idle.
pub struct Door {
    busy: Arc<AtomicUsize>,
    closing: watch::Sender<bool>,
    accepting: Mutex<Option<(JoinHandle<TcpListener>, watch::Sender<bool>)>>,
    idle: Mutex<Option<TcpListener>>,
    on_stream: Arc<dyn Fn(TcpStream, watch::Receiver<bool>) + Send + Sync>,
}

/// One request under way, while it lives.
pub struct Busy(Arc<AtomicUsize>);

impl Drop for Busy {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::SeqCst);
    }
}

impl Door {
    /// Accepts on `listener`; each connection goes to `on_stream`, with what says when it should close once idle.
    pub fn open(listener: TcpListener, on_stream: impl Fn(TcpStream, watch::Receiver<bool>) + Send + Sync + 'static) -> Arc<Door> {
        let door = Arc::new(Door { busy: Arc::default(), closing: watch::channel(false).0, accepting: Mutex::default(), idle: Mutex::new(Some(listener)), on_stream: Arc::new(on_stream) });
        door.start();
        door
    }

    /// Counts a request as under way for as long as what it returns lives.
    pub fn busy(&self) -> Busy {
        self.busy.fetch_add(1, Ordering::SeqCst);
        Busy(self.busy.clone())
    }

    fn start(&self) {
        let Some(listener) = self.idle.lock().unwrap().take() else { return };
        let _ = self.closing.send(false);
        let (stop, mut stopping) = watch::channel(false);
        let (on_stream, closing) = (self.on_stream.clone(), self.closing.clone());
        let task = tokio::spawn(async move {
            loop {
                tokio::select! {
                    biased;
                    _ = stopping.changed() => return listener,
                    accepted = listener.accept() => match accepted {
                        Ok((stream, _)) => on_stream(stream, closing.subscribe()),
                        Err(e) => {
                            warn!(error = %e, "accept failed");
                            tokio::time::sleep(Duration::from_millis(50)).await;
                        }
                    },
                }
            }
        });
        *self.accepting.lock().unwrap() = Some((task, stop));
    }

    /// Stops accepting (connections wait in the backlog) and asks open connections to close once idle; resolves once
    /// no request is under way, or fails after `limit` (accepting again).
    pub async fn pause(&self, limit: Duration) -> Result<()> {
        let running = self.accepting.lock().unwrap().take();
        if let Some((task, stop)) = running {
            let _ = stop.send(true);
            let listener = task.await.map_err(|e| anyhow!("accept loop failed: {e}"))?;
            *self.idle.lock().unwrap() = Some(listener);
        }
        let _ = self.closing.send(true);
        let until = std::time::Instant::now() + limit;
        while self.busy.load(Ordering::SeqCst) > 0 {
            if std::time::Instant::now() > until {
                self.resume();
                bail!("requests still under way after {} s", limit.as_secs());
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        Ok(())
    }

    /// Accepts again after a pause.
    pub fn resume(&self) {
        self.start();
    }

    /// The paused socket, kept open across exec for the next binary.
    pub fn keep(&self) -> Result<i32> {
        let idle = self.idle.lock().unwrap();
        let listener = idle.as_ref().ok_or_else(|| anyhow!("the door is not paused"))?;
        keep_across_exec(listener)
    }
}

/// Serves one HTTP/1 connection until it ends, or, once `closing` says so, until what it is doing is done.
pub async fn serve_http1<S, B>(stream: TcpStream, service: S, mut closing: watch::Receiver<bool>)
where
    S: hyper::service::HttpService<hyper::body::Incoming, ResBody = B>,
    S::Error: Into<Box<dyn std::error::Error + Send + Sync>>,
    B: hyper::body::Body + 'static,
    B::Error: Into<Box<dyn std::error::Error + Send + Sync>>,
{
    let conn = hyper::server::conn::http1::Builder::new().serve_connection(hyper_util::rt::TokioIo::new(stream), service);
    tokio::pin!(conn);
    if *closing.borrow() {
        conn.as_mut().graceful_shutdown();
        let _ = conn.await;
        return;
    }
    let asked = tokio::select! {
        _ = conn.as_mut() => return,
        asked = closing.wait_for(|c| *c) => asked.is_ok(),
    };
    if asked {
        conn.as_mut().graceful_shutdown();
    }
    let _ = conn.await;
}
