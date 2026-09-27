//! The part of the station still written in TypeScript (src/main.ts), run as this process's child: started, watched
//! and started again when it ends. It answers the admin API on a Unix socket in the data directory, which only this
//! process connects to; it is ready once that socket answers `/healthz`. Its spans for ember cloud come on its fd 3.

use std::{
    path::{Path, PathBuf},
    process::Stdio,
    sync::Arc,
    time::{Duration, Instant},
};

use anyhow::{Context, Result};
use tokio::{
    process::{Child, Command},
    sync::watch,
};
use tracing::{info, warn};

use crate::local;
use crate::telemetry::Telemetry;

/// How the Node part is started: its interpreter, and the app directory holding src/main.ts.
#[derive(Clone)]
pub struct Launch {
    pub node: PathBuf,
    pub app: PathBuf,
    pub data: PathBuf,
    pub socket: PathBuf,
    pub secret: String,
}

/// Runs the Node part for as long as this process runs: `ready` says whether it answers now. Spans it writes go to
/// `telemetry`.
pub async fn supervise(launch: Launch, ready: watch::Sender<bool>, telemetry: Arc<Telemetry>, mut stopping: watch::Receiver<bool>) {
    let mut backoff = Duration::from_secs(1);
    loop {
        let started = Instant::now();
        let mut child = match spawn(&launch, &telemetry) {
            Ok(child) => child,
            Err(error) => {
                warn!(%error, "cannot start the station's Node part");
                tokio::time::sleep(backoff).await;
                backoff = (backoff * 2).min(Duration::from_secs(30));
                continue;
            }
        };
        info!(pid = ?child.id(), "station's Node part started");
        let waiting = wait_ready(&launch.socket, &ready);
        tokio::pin!(waiting);
        let mut waited = false;
        // Once up, it is asked again every few seconds: a Node part that stops answering (its socket gone, stuck)
        // is offline, and is started again after three misses.
        let mut check = tokio::time::interval(Duration::from_secs(5));
        let mut misses = 0;
        let exited = loop {
            tokio::select! {
                status = child.wait() => break status,
                _ = &mut waiting, if !waited => waited = true,
                _ = check.tick(), if waited => {
                    if local::healthy(&launch.socket).await {
                        misses = 0;
                        ready.send_replace(true);
                    } else {
                        misses += 1;
                        ready.send_replace(false);
                        if misses >= 3 {
                            warn!("station's Node part stopped answering; starting it again");
                            stop(&mut child).await;
                        }
                    }
                }
                _ = stopping.changed() => {
                    stop(&mut child).await;
                    ready.send_replace(false);
                    return;
                }
            }
        };
        ready.send_replace(false);
        warn!(status = ?exited.ok(), "station's Node part ended; starting it again");
        // One that ran a while starts again at once; one that keeps failing backs off.
        if started.elapsed() > Duration::from_secs(60) {
            backoff = Duration::from_secs(1);
        }
        tokio::time::sleep(backoff).await;
        backoff = (backoff * 2).min(Duration::from_secs(30));
    }
}

fn spawn(launch: &Launch, telemetry: &Arc<Telemetry>) -> Result<Child> {
    // Its spans come on a pipe of their own, fd 3 in the child.
    let (reader, writer) = std::io::pipe().context("pipe for spans")?;
    let mut command = Command::new(&launch.node);
    command
        .arg("src/main.ts")
        .current_dir(&launch.app)
        .env("EMBER_DATA", &launch.data)
        .env("EMBER_ADMIN_SOCKET", &launch.socket)
        .env("EMBER_MESH_SECRET", &launch.secret)
        .stdin(Stdio::null())
        .kill_on_drop(true);
    let fd = std::os::fd::OwnedFd::from(writer);
    let raw = std::os::fd::AsRawFd::as_raw_fd(&fd);
    // SAFETY: dup2 in the child between fork and exec, on a descriptor that stays open until then.
    unsafe {
        command.pre_exec(move || {
            // Already 3, it only needs to stay open across exec.
            let done = if raw == 3 { libc::fcntl(3, libc::F_SETFD, 0) } else { libc::dup2(raw, 3) };
            if done < 0 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
    let child = command.spawn().context("spawn node")?;
    drop(fd);
    tokio::spawn(telemetry.clone().read_station_spans(tokio::fs::File::from_std(std::fs::File::from(std::os::fd::OwnedFd::from(reader)))));
    Ok(child)
}

/// Asks the socket until it answers, then says the Node part is ready.
async fn wait_ready(socket: &Path, ready: &watch::Sender<bool>) {
    loop {
        if local::healthy(socket).await {
            info!("station's Node part is ready");
            ready.send_replace(true);
            return;
        }
        tokio::time::sleep(Duration::from_millis(300)).await;
    }
}

/// SIGTERM, then SIGKILL if it has not ended in 20 s (it ends its runtimes' process groups on SIGTERM).
async fn stop(child: &mut Child) {
    if let Some(pid) = child.id() {
        // SAFETY: a signal to our own child's pid.
        unsafe { libc::kill(pid as i32, libc::SIGTERM) };
    }
    if tokio::time::timeout(Duration::from_secs(20), child.wait()).await.is_err() {
        let _ = child.kill().await;
    }
}
