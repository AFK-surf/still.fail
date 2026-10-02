//! Profiles lent to the workspace's other stations while they are on the same LAN as the station whose they are.
//!
//! - A subscription's login stays with the lending station, which alone renews it: refresh tokens are single-use, so
//!   two stations renewing would sign each other out. A borrower is handed the current access token, never the refresh
//!   token. Claude Code runs on it as a machine profile runs on the machine's (CLAUDE_CODE_OAUTH_TOKEN, started again
//!   with the next one as it is about to run out). Codex reads an auth.json in the borrowed profile's home, written
//!   with the lender's tokens but no refresh token; a ChatGPT access token lasts 10 days and Codex renews only after 8,
//!   so the lender has its own app-server renew it once less than RENEW_BEFORE_MS is left, and the borrower takes the
//!   new one (Codex reads the file again at a 401 before trying to renew).
//! - A key (Anthropic API, OpenCode Go, an API provider) needs no renewing: the borrower is given it and holds it in
//!   memory only. Custom environment profiles are not lent: what they set may be the lender's machine's own.
//!
//! Same LAN: the lender answers only over a direct path to a private address in one of its own networks (the station
//! transport says so, mesh/station's peer.rs); over a relay, or a VPN's address, it refuses. A borrower asks every
//! station of the workspace what it lends each round; what one lent and now refuses or cannot be reached stays in its
//! config but cannot be picked (a Codex auth.json is removed), so its sessions go on with another profile at their next
//! turn.
//!
//! Lent: a profile with `shareOnLan` (config.json). Borrowed: profiles `lan-<station>-<id>` after the station's own,
//! with a home of their own under <data>/lan for the runtime's files.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock, Weak};
use std::time::Duration;

use anyhow::{Context, Result, anyhow, bail};
use base64::Engine;
use futures_util::future::{BoxFuture, join_all};
use serde_json::{Value, json};
use stillfail_shapes::{AccessKind, RuntimeKind};
use tracing::{info, warn};

use crate::config::{Lent, Profile, RawConfig, RawProfile, RawProfileAccess, parse_config};
use crate::profiles::{ProfileCheck, ProfileQuota};
use crate::remote::{Call, Refused};
use crate::settings::Settings;
use crate::store::{Store, now_ms};

/// What a station lends (asked by a borrower each round).
pub const ASK_LENT: &str = "profiles.lent";
/// A lent subscription's current access token (Claude) or auth.json without its refresh token (Codex).
pub const ASK_TOKEN: &str = "profile.token";
/// What a lender answers off the LAN.
pub const NOT_ON_LAN: &str = "not on the same LAN as the station lending its accounts";
const ROUND: Duration = Duration::from_secs(20);
/// A Codex access token with less than this left is renewed by the lender before it is handed over, and asked for
/// again by a borrower.
const RENEW_BEFORE_MS: i64 = 3 * 24 * 3600 * 1000;

/// Has a lent Codex subscription's own app-server renew its login (account/read with refreshToken).
pub type RenewCodex = Arc<dyn Fn(Profile) -> BoxFuture<'static, Result<()>> + Send + Sync>;

/// What a lending station last said of a profile it lends this one.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Health {
    /// It answered over the LAN this round.
    pub on_lan: bool,
    pub check: Option<ProfileCheck>,
    pub quota: Option<ProfileQuota>,
}

/// Lending and borrowing over the LAN: the way to the workspace's stations, how the borrowed profiles are now, and how
/// a lent Codex login is renewed.
#[derive(Default)]
pub struct Lan {
    call: OnceLock<Call>,
    renew_codex: OnceLock<RenewCodex>,
    /// By the profile's id here.
    health: Mutex<HashMap<String, Health>>,
}

impl Lan {
    pub fn attach(&self, call: Call) {
        let _ = self.call.set(call);
    }

    pub fn on_renew_codex(&self, renew: RenewCodex) {
        let _ = self.renew_codex.set(renew);
    }

    pub fn health(&self, id: &str) -> Option<Health> {
        self.health.lock().unwrap().get(id).cloned()
    }

    /// Whether a borrowed profile can run now: its station answered over the LAN this round.
    pub fn on_lan(&self, id: &str) -> bool {
        self.health(id).is_some_and(|h| h.on_lan)
    }

    /// For the pool: what a borrowed profile's own station says of it, or (off the LAN) that it cannot run.
    pub fn check(&self, id: &str) -> Option<ProfileCheck> {
        let health = self.health(id)?;
        if !health.on_lan {
            return Some(ProfileCheck { decision: None, model_efforts: None, state: "failed".into(), detail: "不在出借账号的 station 的局域网里".into(), models: None, checked_at: now_ms() });
        }
        health.check
    }

    /// A borrowed Claude subscription's current access token, from its station, and when it runs out.
    pub async fn token(&self, lent: &Lent) -> Result<(String, i64)> {
        let answer = self.ask_token(lent).await?;
        let token = answer["token"].as_str().filter(|t| !t.is_empty()).ok_or_else(|| anyhow!("the lending station gave no token"))?;
        Ok((token.to_string(), answer["expiresAt"].as_i64().unwrap_or(0)))
    }

    async fn ask_token(&self, lent: &Lent) -> Result<Value> {
        let call = self.call.get().cloned().ok_or_else(|| anyhow!("station mesh is not ready"))?;
        call(lent.station.clone(), json!({"method": ASK_TOKEN, "profile": lent.profile})).await
    }
}

/// Whether this station lends a profile of its own.
fn lendable(p: &Profile) -> bool {
    p.share_on_lan && p.lent.is_none() && p.access_kind != AccessKind::Env
}

/// A lent profile as a borrower makes its own: how it reaches its models, never its home, environment or machine login.
fn offered(p: &Profile) -> RawProfile {
    RawProfile {
        id: p.id.clone(),
        name: Some(p.name.clone()),
        runtime: Some(p.runtime),
        access: Some(RawProfileAccess {
            kind: p.access_kind,
            key: crate::profiles::keyed(p.access_kind).then(|| p.key.clone()),
            provider: p.provider.clone(),
            endpoint: p.endpoint.clone(),
            protocol: p.protocol.clone(),
        }),
        home: String::new(),
        env: None,
        model: p.model.clone(),
        models: Some(p.models.clone()),
        machine: None,
        background_on_message: None,
        fast: p.fast.then_some(true),
        share_on_lan: None,
    }
}

/// A lender's answer to a workspace station: `lan` as the transport found the path it came on.
pub async fn answer(settings: &Settings, store: &Store, lan: bool, request: &Value) -> Result<Value> {
    if !lan {
        return Err(Refused(NOT_ON_LAN.into()).into());
    }
    let config = settings.config();
    let shared = config.profiles.iter().filter(|p| lendable(p));
    match request["method"].as_str().unwrap_or_default() {
        ASK_LENT => {
            let status = store.profile_status()?;
            let profiles: Vec<Value> = shared
                .map(|p| {
                    let s = status.get(&p.id);
                    json!({"profile": offered(p), "check": s.and_then(|s| s.check.clone()), "quota": s.and_then(|s| s.quota.clone())})
                })
                .collect();
            Ok(json!({"profiles": profiles}))
        }
        ASK_TOKEN => {
            let id = request["profile"].as_str().unwrap_or_default();
            let Some(p) = shared.into_iter().find(|p| p.id == id && p.access_kind == AccessKind::Subscription) else {
                return Err(Refused(format!("profile {id} is not lent")).into());
            };
            match p.runtime {
                RuntimeKind::Claude => {
                    let home = (!p.machine).then_some(p.home.as_path());
                    let (token, expires) = crate::claude_oauth::token(&crate::machine_logins::process_env(), home, None).await?;
                    Ok(json!({"token": token, "expiresAt": expires}))
                }
                RuntimeKind::Codex => codex_auth(settings, p).await,
            }
        }
        other => bail!("unknown method {other}"),
    }
}

/// When a JWT runs out (its `exp`), in ms.
fn expires_ms(jwt: &str) -> Option<i64> {
    let payload = jwt.split('.').nth(1)?;
    let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(payload.trim_end_matches('=')).ok()?;
    serde_json::from_slice::<Value>(&bytes).ok()?["exp"].as_i64().map(|s| s * 1000)
}

/// A Codex auth.json and when its access token runs out.
fn read_auth(file: &Path) -> Result<(Value, i64)> {
    let auth: Value = serde_json::from_slice(&std::fs::read(file).with_context(|| format!("no Codex login at {}", file.display()))?)?;
    let expires = auth["tokens"]["access_token"].as_str().and_then(expires_ms).ok_or_else(|| anyhow!("the Codex login has no ChatGPT access token"))?;
    Ok((auth, expires))
}

fn codex_auth_file(p: &Profile) -> PathBuf {
    if p.machine { crate::machine_logins::codex_auth_file(&crate::machine_logins::process_env()) } else { p.home.join("auth.json") }
}

/// A lent Codex subscription's login without its refresh token, renewed first (by its own app-server) when it is near
/// its end.
async fn codex_auth(settings: &Settings, p: &Profile) -> Result<Value> {
    let file = codex_auth_file(p);
    let (mut auth, mut expires) = read_auth(&file)?;
    if expires - now_ms() < RENEW_BEFORE_MS {
        match settings.lan.renew_codex.get().cloned() {
            Some(renew) => match renew(p.clone()).await {
                Ok(()) => (auth, expires) = read_auth(&file)?,
                Err(e) => warn!(profile = p.id, error = %e, "lent codex login not renewed"),
            },
            None => warn!(profile = p.id, "no codex to renew a lent login with"),
        }
    }
    auth["tokens"]["refresh_token"] = json!("");
    auth["OPENAI_API_KEY"] = Value::Null;
    Ok(json!({"auth": auth, "expiresAt": expires}))
}

/// The id a profile lent by `station` has here (profile ids are lowercase letters, digits and dashes).
pub fn local_id(station: &str, profile: &str) -> String {
    let short: String = station.chars().filter(char::is_ascii_alphanumeric).map(|c| c.to_ascii_lowercase()).take(8).collect();
    format!("lan-{short}-{profile}")
}

/// A profile a station lends, as this one runs it: made as config.json's would be.
fn borrowed(settings: &Settings, station: &str, station_name: &str, offer: &Value) -> Option<Profile> {
    let mut raw: RawProfile = serde_json::from_value(offer["profile"].clone()).ok()?;
    if raw.access.as_ref().is_none_or(|a| a.kind == AccessKind::Env) {
        return None;
    }
    let profile = std::mem::take(&mut raw.id);
    let id = local_id(station, &profile);
    let name = raw.name.take().unwrap_or_else(|| profile.clone());
    raw.id = id.clone();
    raw.home = format!("lan/{id}");
    (raw.env, raw.machine, raw.share_on_lan) = (None, None, None);
    let config = RawConfig { profiles: Some(vec![raw]), ..Default::default() };
    let mut p = match parse_config(&config, &settings.data_dir) {
        Ok(mut c) => c.profiles.remove(0),
        Err(e) => {
            warn!(station, profile, error = %e, "a lent profile does not check out here");
            return None;
        }
    };
    p.name = if station_name.is_empty() { name } else { format!("{name} · {station_name}") };
    p.lent = Some(Lent { station: station.into(), profile });
    Some(p)
}

fn codex_subscription(p: &Profile) -> bool {
    p.access_kind == AccessKind::Subscription && p.runtime == RuntimeKind::Codex
}

/// A borrowed Codex subscription's auth.json, asked for again when missing or near its end.
async fn keep_codex_auth(lan: &Lan, p: &Profile) -> Result<()> {
    let (Some(lent), file) = (p.lent.as_ref(), p.home.join("auth.json")) else { return Ok(()) };
    if read_auth(&file).is_ok_and(|(_, expires)| expires - now_ms() >= RENEW_BEFORE_MS) {
        return Ok(());
    }
    let answer = lan.ask_token(lent).await?;
    if !answer["auth"].is_object() {
        bail!("the lending station gave no Codex login");
    }
    std::fs::create_dir_all(&p.home)?;
    crate::no_keychain::write_private(&file, &answer["auth"].to_string())?;
    info!(profile = p.id, "lent codex login taken");
    Ok(())
}

/// Asks the workspace's stations what they lend, every round, while the station runs.
pub fn follow(settings: Weak<Settings>) {
    tokio::spawn(async move {
        loop {
            let Some(s) = settings.upgrade() else { return };
            round(&s).await;
            drop(s);
            tokio::time::sleep(ROUND).await;
        }
    });
}

async fn round(settings: &Settings) {
    let Some(call) = settings.lan.call.get().cloned() else { return };
    let roster = match call(String::new(), json!({"method": "peers"})).await {
        Ok(roster) => roster,
        Err(e) => return warn!(error = %e, "no workspace roster for lent profiles"),
    };
    let me = roster["self"].as_str().unwrap_or_default().to_string();
    let stations: Vec<(String, String)> = roster["stations"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|s| Some((s["id"].as_str()?.to_string(), s["name"].as_str().unwrap_or_default().to_string())))
        .filter(|(id, _)| *id != me)
        .collect();
    let before: Vec<Profile> = settings.config().profiles.iter().filter(|p| p.lent.is_some()).cloned().collect();
    let answers = join_all(stations.iter().map(|(id, _)| call(id.clone(), json!({"method": ASK_LENT})))).await;
    let (mut profiles, mut health) = (Vec::new(), HashMap::new());
    for ((station, name), answer) in stations.iter().zip(answers) {
        match answer {
            Ok(answer) => {
                for offer in answer["profiles"].as_array().into_iter().flatten() {
                    let Some(p) = borrowed(settings, station, name, offer) else { continue };
                    let _ = std::fs::create_dir_all(&p.home);
                    // A Codex login it cannot have is no profile to run on.
                    let on_lan = match codex_subscription(&p) {
                        true => keep_codex_auth(&settings.lan, &p).await.inspect_err(|e| warn!(profile = p.id, error = %e, "lent codex login not taken")).is_ok(),
                        false => true,
                    };
                    let check = serde_json::from_value(offer["check"].clone()).ok();
                    let quota = serde_json::from_value(offer["quota"].clone()).ok();
                    health.insert(p.id.clone(), Health { on_lan, check, quota });
                    profiles.push(p);
                }
            }
            // Off the LAN, or out of reach: what it lent stays, unusable, so its sessions are moved, not lost.
            Err(e) => {
                let kept: Vec<Profile> = before.iter().filter(|p| p.lent.as_ref().is_some_and(|l| l.station == *station)).cloned().collect();
                if !kept.is_empty() {
                    info!(station, error = %e, "lent profiles out of reach");
                }
                for p in kept {
                    if codex_subscription(&p) {
                        let _ = std::fs::remove_file(p.home.join("auth.json"));
                    }
                    let mut was = settings.lan.health(&p.id).unwrap_or_default();
                    was.on_lan = false;
                    health.insert(p.id.clone(), was);
                    profiles.push(p);
                }
            }
        }
    }
    // Gone from the workspace, or no longer lent: its Codex login goes with it.
    for p in before.iter().filter(|b| codex_subscription(b) && !profiles.iter().any(|p| p.id == b.id)) {
        let _ = std::fs::remove_file(p.home.join("auth.json"));
    }
    *settings.lan.health.lock().unwrap() = health;
    settings.set_lent(profiles);
}

#[cfg(test)]
mod tests;
