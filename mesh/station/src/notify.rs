//! The chats' notices (stillfail_app::admin::notify) on their way to still.fail cloud, which pushes them to the
//! people's devices (docs/notifications.md): gathered over a moment, posted to `/v1/stations/notify` signed with the
//! station's key like its traces. A batch that cannot be sent is dropped; an older cloud (404) has no pushes.

use std::sync::Arc;
use std::time::Duration;

use iroh::SecretKey;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use tokio::sync::broadcast::error::RecvError;
use tracing::{info, warn};

use crate::{Station, http, now};

/// Notices wait this long to go out together.
const GATHER: Duration = Duration::from_secs(1);
/// At most this many in one post (the cloud takes no more).
const MAX_BATCH: usize = 50;

/// Posts the notices as they come, until the process ends.
pub async fn forward(station: Arc<Station>, key: SecretKey) {
    let mut notices = stillfail_app::admin::notify::outbox().subscribe();
    let client = http();
    loop {
        let first = match notices.recv().await {
            Ok(notice) => notice,
            Err(RecvError::Lagged(n)) => {
                warn!(n, "notices dropped");
                continue;
            }
            Err(RecvError::Closed) => return,
        };
        tokio::time::sleep(GATHER).await;
        let mut batch = vec![first];
        while batch.len() < MAX_BATCH {
            match notices.try_recv() {
                Ok(notice) => batch.push(notice),
                Err(_) => break,
            }
        }
        if station.removed() {
            continue;
        }
        let n = batch.len();
        match send(&client, &station, &key, batch).await {
            Ok(()) => info!(n, "notices sent"),
            Err(error) => warn!(%error, n, "notices dropped"),
        }
    }
}

/// Posts one batch, signed over "ember-station-notify-v1:<origin>:<station>:<ts>:<sha256 of the body, hex>", its
/// headers under both names.
async fn send(client: &reqwest::Client, station: &Station, key: &SecretKey, notices: Vec<Value>) -> anyhow::Result<()> {
    let (origin, id) = {
        let s = station.state.lock().unwrap();
        (s.origin.clone(), s.station.clone())
    };
    let body = serde_json::to_vec(&json!({ "notices": notices }))?;
    let ts = now();
    let digest = hex::encode(Sha256::digest(&body));
    let signature = hex::encode(key.sign(format!("ember-station-notify-v1:{origin}:{id}:{ts}:{digest}").as_bytes()).to_bytes());
    let response = client
        .post(format!("{origin}/v1/stations/notify"))
        .header("content-type", "application/json")
        .header("x-stillfail-station", &id)
        .header("x-stillfail-ts", ts.to_string())
        .header("x-stillfail-signature", &signature)
        .header("x-ember-station", &id)
        .header("x-ember-ts", ts.to_string())
        .header("x-ember-signature", signature)
        .body(body)
        .send()
        .await?;
    if !response.status().is_success() {
        anyhow::bail!("still.fail cloud answered {}", response.status());
    }
    Ok(())
}
