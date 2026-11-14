//! A station's endpoint on every one of still.fail's relays, not only its home one (`iroh.keep`), as the station's mesh
//! addon has it (station/native/mesh/src/keep.rs, which says why): each relay gets a keeper, a small endpoint of its
//! own on that relay alone (no IP), which the station stays connected to through that relay.

use std::time::{Duration, Instant};

use iroh::{Endpoint, EndpointAddr, RelayMode, RelayUrl, endpoint::presets::Minimal};

/// What the station and its keepers speak: nothing, only the connection is wanted.
const ALPN: &[u8] = b"stillfail/keep/1";
/// How long a keeper may take to be on its relay, and the station to reach it there.
const SETUP: Duration = Duration::from_secs(20);
/// The longest wait before trying a relay again; a hold that lasted this long starts the waits over.
const MAX_BACKOFF: Duration = Duration::from_secs(60);

/// Holds the station on one relay for good, starting over (with backoff) whenever the hold breaks.
pub async fn keep(endpoint: Endpoint, relay: RelayUrl) {
    let mut backoff = Duration::from_secs(1);
    loop {
        let started = Instant::now();
        if let Err(error) = hold(&endpoint, &relay).await {
            eprintln!("mesh: not held on {relay}: {error}");
        }
        if started.elapsed() >= MAX_BACKOFF {
            backoff = Duration::from_secs(1);
        }
        tokio::time::sleep(backoff).await;
        backoff = (backoff * 2).min(MAX_BACKOFF);
    }
}

/// One hold: a keeper on the relay, the station connected to it through the relay, until that connection ends.
async fn hold(endpoint: &Endpoint, relay: &RelayUrl) -> Result<(), String> {
    let keeper = Endpoint::builder(Minimal)
        .clear_ip_transports()
        .relay_mode(RelayMode::Custom(iroh::RelayMap::from_iter([relay.clone()])))
        .alpns(vec![ALPN.to_vec()])
        .bind()
        .await
        .map_err(|e| format!("keeper: {e}"))?;
    let held = async {
        tokio::time::timeout(SETUP, keeper.online()).await.map_err(|_| format!("keeper not on the relay after {SETUP:?}"))?;
        let addr = EndpointAddr::new(keeper.id()).with_relay_url(relay.clone());
        let dialed = async { endpoint.connect(addr, ALPN).await.map_err(|e| format!("station to keeper: {e}")) };
        let accepted = async {
            let incoming = keeper.accept().await.ok_or("keeper closed")?;
            incoming.await.map_err(|e| format!("keeper accepting: {e}"))
        };
        let (conn, _accepted) = tokio::time::timeout(SETUP, async { tokio::try_join!(dialed, accepted) })
            .await
            .map_err(|_| format!("no connection through the relay after {SETUP:?}"))??;
        eprintln!("mesh: held on {relay}");
        let reason = conn.closed().await;
        Err::<(), _>(format!("connection through the relay ended: {reason}"))
    }
    .await;
    keeper.close().await;
    held
}
