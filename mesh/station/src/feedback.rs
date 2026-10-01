//! Bug reports on their way to still.fail cloud (stillfail_app::feedback): posted to `/v1/feedback` signed with the
//! station's key like its notices, over "stillfail-station-feedback-v1:<origin>:<station>:<ts>:<sha256 of the body,
//! hex>". The agent waits for the answer: the report's number, which it gives the person who reported it. And which
//! of them are fixed and out (POST /v1/feedback/fixed, tag stillfail-station-feedback-fixed-v1), for the app to tell
//! their sessions.

use std::sync::Arc;

use iroh::SecretKey;
use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::{Station, cloud_error, http, now, version};

/// Lets the app's `feedback_send` tool post through this station, and the app ask which reports are fixed (`tell_fixed`).
pub fn register(station: Arc<Station>, key: SecretKey) {
    let client = http();
    let (fixed_station, fixed_key) = (station.clone(), key.clone());
    stillfail_app::feedback::register(Arc::new(move |mut report: Value| {
        let (client, station, key) = (client.clone(), station.clone(), key.clone());
        Box::pin(async move {
            if station.removed() {
                anyhow::bail!("this station was removed from its workspace");
            }
            report["context"]["version"] = Value::String(version().to_string());
            send(&client, &station, &key, "/v1/feedback", "stillfail-station-feedback-v1", &report).await
        })
    }));
    let client = http();
    stillfail_app::feedback::register_fixed(Arc::new(move |told: Vec<String>| {
        let (client, station, key) = (client.clone(), fixed_station.clone(), fixed_key.clone());
        Box::pin(async move {
            if station.removed() {
                return Ok(serde_json::json!({ "fixed": [] }));
            }
            let mut answer = send(&client, &station, &key, "/v1/feedback/fixed", "stillfail-station-feedback-fixed-v1", &serde_json::json!({ "told": told })).await?;
            answer["station"] = Value::String(version().to_string());
            Ok(answer)
        })
    }));
}

async fn send(client: &reqwest::Client, station: &Station, key: &SecretKey, path: &str, tag: &str, report: &Value) -> anyhow::Result<Value> {
    let (origin, id) = {
        let s = station.state.lock().unwrap();
        (s.origin.clone(), s.station.clone())
    };
    let body = serde_json::to_vec(report)?;
    let ts = now();
    let digest = hex::encode(Sha256::digest(&body));
    let signature = hex::encode(key.sign(format!("{tag}:{origin}:{id}:{ts}:{digest}").as_bytes()).to_bytes());
    let response = client
        .post(format!("{origin}{path}"))
        .header("content-type", "application/json")
        .header("x-stillfail-station", &id)
        .header("x-stillfail-ts", ts.to_string())
        .header("x-stillfail-signature", signature)
        .body(body)
        .send()
        .await?;
    if !response.status().is_success() {
        return Err(cloud_error(response).await);
    }
    Ok(response.json().await?)
}
