//! The station on every one of still.fail's relays, not only its home one.
//!
//! A relay passes packets on only to whoever is linked to it, and iroh keeps a link only to its home relay (the
//! nearest): one it sends nothing on is let go after a minute. So a station abroad, at home on Cloudflare's relay, was
//! out of reach of a phone in mainland China, which seldom gets through to Cloudflare (2026-10-01, bft in Tokyo); the
//! phone's packets on the other relays went nowhere. iroh 1.x takes one relay transport per endpoint, so a station
//! cannot be at home on several: each relay gets a keeper instead, a small endpoint of its own on that relay alone (no
//! IP), which the station stays connected to through that relay. The connection's keep-alives (iroh's, every 5 s)
//! are the station sending on the relay, so its link there stays up, and a device dialing on any of the relays is heard
//! (the station answers on the relay it heard it on).

use std::{
    collections::HashMap,
    time::{Duration, Instant},
};

use anyhow::{Context, Result, anyhow};
use iroh::{Endpoint, EndpointAddr, RelayMode, RelayUrl, endpoint::presets::Minimal};
use tokio::task::JoinHandle;
use tracing::info;

/// What the station and its keepers speak: nothing, only the connection is wanted.
const ALPN: &[u8] = b"stillfail/keep/1";
/// How long a keeper may take to be on its relay, and the station to reach it there.
const SETUP: Duration = Duration::from_secs(20);
/// The longest wait before trying a relay again; a hold that lasted this long starts the waits over.
const MAX_BACKOFF: Duration = Duration::from_secs(60);

/// The station's keepers, one per relay.
#[derive(Default)]
pub struct Keepers(HashMap<RelayUrl, JoinHandle<()>>);

impl Keepers {
    /// Keeps the station on these relays: a keeper for each new one, those of relays no longer named stopped.
    pub fn set(&mut self, endpoint: &Endpoint, relays: &[RelayUrl]) {
        self.0.retain(|url, task| {
            let named = relays.contains(url);
            if !named {
                task.abort();
            }
            named
        });
        for url in relays {
            self.0.entry(url.clone()).or_insert_with(|| tokio::spawn(keep(endpoint.clone(), url.clone())));
        }
    }
}

/// Holds the station on one relay for good, starting over (with backoff) whenever the hold breaks.
async fn keep(endpoint: Endpoint, relay: RelayUrl) {
    let mut backoff = Duration::from_secs(1);
    loop {
        let started = Instant::now();
        if let Err(error) = hold(&endpoint, &relay).await {
            info!(%relay, error = format!("{error:#}"), "not held on this relay");
        }
        if started.elapsed() >= MAX_BACKOFF {
            backoff = Duration::from_secs(1);
        }
        tokio::time::sleep(backoff).await;
        backoff = (backoff * 2).min(MAX_BACKOFF);
    }
}

/// One hold: a keeper on the relay, the station connected to it through the relay, until that connection ends.
async fn hold(endpoint: &Endpoint, relay: &RelayUrl) -> Result<()> {
    let keeper = Endpoint::builder(Minimal)
        .clear_ip_transports()
        .relay_mode(RelayMode::Custom(iroh::RelayMap::from_iter([relay.clone()])))
        .alpns(vec![ALPN.to_vec()]);
    // The tests' relays have certificates of their own.
    #[cfg(test)]
    let keeper = keeper.ca_tls_config(iroh_relay::tls::CaTlsConfig::insecure_skip_verify());
    let keeper = keeper
        .bind()
        .await
        .context("keeper")?;
    let held = async {
        tokio::time::timeout(SETUP, keeper.online()).await.map_err(|_| anyhow!("keeper not on the relay after {SETUP:?}"))?;
        let addr = EndpointAddr::new(keeper.id()).with_relay_url(relay.clone());
        let dialed = async { endpoint.connect(addr, ALPN).await.context("station to keeper") };
        let accepted = async {
            let incoming = keeper.accept().await.context("keeper closed")?;
            incoming.await.context("keeper accepting")
        };
        let (conn, _accepted) = tokio::time::timeout(SETUP, async { tokio::try_join!(dialed, accepted) })
            .await
            .map_err(|_| anyhow!("no connection through the relay after {SETUP:?}"))??;
        info!(%relay, "held on this relay");
        let reason = conn.closed().await;
        Err::<(), _>(anyhow!("connection through the relay ended: {reason}"))
    }
    .await;
    keeper.close().await;
    held
}

#[cfg(test)]
mod tests {
    use super::*;
    use iroh::{SecretKey, Watcher, endpoint::presets::Minimal};
    use iroh_relay::tls::CaTlsConfig;

    const TEST_ALPN: &[u8] = b"stillfail/test/1";

    fn on(relays: &[RelayUrl]) -> iroh::endpoint::Builder {
        Endpoint::builder(Minimal)
            .clear_ip_transports()
            .relay_mode(RelayMode::Custom(iroh::RelayMap::from_iter(relays.iter().cloned())))
            .ca_tls_config(CaTlsConfig::insecure_skip_verify())
    }

    /// A device that reaches only the relay the station is not at home on reaches it once the station has keepers.
    #[tokio::test]
    async fn reached_on_a_relay_not_its_home() -> Result<()> {
        reached(Duration::ZERO).await
    }

    /// And still does well after iroh lets go of a relay nothing is sent on (a minute). Slow: `cargo test -- --ignored`.
    #[tokio::test]
    #[ignore]
    async fn still_reached_after_iroh_would_let_go() -> Result<()> {
        reached(Duration::from_secs(75)).await
    }

    async fn reached(wait: Duration) -> Result<()> {
        let (_, a, _a) = iroh::test_utils::run_relay_server().await?;
        let (_, b, _b) = iroh::test_utils::run_relay_server().await?;
        let station = on(&[a.clone(), b.clone()]).secret_key(SecretKey::generate()).alpns(vec![TEST_ALPN.to_vec()]).bind().await?;
        station.online().await;
        let home = station.home_relay_status().get().first().map(|s| s.url().clone()).context("no home relay")?;
        let other = if home == a { b.clone() } else { a.clone() };
        tokio::spawn({
            let station = station.clone();
            async move {
                while let Some(incoming) = station.accept().await {
                    if let Ok(conn) = incoming.await {
                        tokio::spawn(async move { conn.closed().await });
                    }
                }
            }
        });
        let device = on(&[other.clone()]).bind().await?;
        device.online().await;
        let addr = || EndpointAddr::new(station.id()).with_relay_url(other.clone());
        let dial = || async {
            tokio::time::timeout(Duration::from_secs(20), async {
                loop {
                    if let Ok(Ok(conn)) = tokio::time::timeout(Duration::from_secs(3), device.connect(addr(), TEST_ALPN)).await {
                        break conn;
                    }
                }
            })
            .await
        };

        // Not on that relay: nothing the device sends there reaches the station.
        let before = tokio::time::timeout(Duration::from_secs(5), device.connect(addr(), TEST_ALPN)).await;
        assert!(!matches!(before, Ok(Ok(_))), "reached the station on a relay it was not on");

        let mut keepers = Keepers::default();
        keepers.set(&station, &[a.clone(), b.clone()]);
        let conn = dial().await.context("not reached on the other relay with keepers")?;
        assert_eq!(conn.remote_id(), station.id());
        if wait.is_zero() {
            return Ok(());
        }
        conn.close(0u32.into(), b"done");
        tokio::time::sleep(wait).await;
        let conn = dial().await.context("not reached on the other relay any more")?;
        assert_eq!(conn.remote_id(), station.id());
        Ok(())
    }
}
