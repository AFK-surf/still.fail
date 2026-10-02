//! A Claude subscription lent to the workspace's other stations while they are on the same LAN as the station whose it
//! is. The lending station keeps the login and alone renews it: a borrower is handed its current access token (never the
//! refresh token, which is single-use: two renewing would sign each other out) and runs Claude Code on it as a machine
//! profile runs on the machine's (CLAUDE_CODE_OAUTH_TOKEN, started again with the next one as it is about to run out).
//!
//! Same LAN: the lender answers only over a direct path to a private address in one of its own networks (the station
//! transport says so, mesh/station's peer.rs); over a relay, or a VPN's address, it refuses. A borrower asks every
//! station of the workspace what it lends each round; what one lent and now refuses or cannot be reached stays in its
//! config but cannot be picked, so its sessions go on with another profile at their next turn.
//!
//! Lent: a profile with `shareOnLan` (config.json) of the Claude subscription kind. Borrowed: profiles `lan-<station>-<id>`
//! after the station's own, with a home of their own under <data>/lan for the runtime's files.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock, Weak};
use std::time::Duration;

use anyhow::{Result, anyhow, bail};
use futures_util::future::join_all;
use serde_json::{Value, json};
use stillfail_shapes::{AccessKind, RuntimeKind};
use tracing::{info, warn};

use crate::config::{Lent, Profile};
use crate::profiles::{ProfileCheck, ProfileQuota};
use crate::remote::{Call, Refused};
use crate::settings::Settings;
use crate::store::{Store, now_ms};

/// What a station lends (asked by a borrower each round).
pub const ASK_LENT: &str = "profiles.lent";
/// A lent profile's current access token.
pub const ASK_TOKEN: &str = "profile.token";
/// What a lender answers off the LAN.
pub const NOT_ON_LAN: &str = "not on the same LAN as the station lending its accounts";
const ROUND: Duration = Duration::from_secs(20);

/// What a lending station last said of a profile it lends this one.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Health {
    /// It answered over the LAN this round.
    pub on_lan: bool,
    pub check: Option<ProfileCheck>,
    pub quota: Option<ProfileQuota>,
}

/// The profiles lent to this station: how they are now, and the way to their stations.
#[derive(Default)]
pub struct Borrowed {
    call: OnceLock<Call>,
    /// By the profile's id here.
    health: Mutex<HashMap<String, Health>>,
}

impl Borrowed {
    pub fn attach(&self, call: Call) {
        let _ = self.call.set(call);
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

    /// The current access token of a borrowed profile, from its station, and when it runs out.
    pub async fn token(&self, lent: &Lent) -> Result<(String, i64)> {
        let call = self.call.get().cloned().ok_or_else(|| anyhow!("station mesh is not ready"))?;
        let answer = call(lent.station.clone(), json!({"method": ASK_TOKEN, "profile": lent.profile})).await?;
        let token = answer["token"].as_str().filter(|t| !t.is_empty()).ok_or_else(|| anyhow!("the lending station gave no token"))?;
        Ok((token.to_string(), answer["expiresAt"].as_i64().unwrap_or(0)))
    }
}

/// Whether this station lends a profile of its own.
fn lendable(p: &Profile) -> bool {
    p.share_on_lan && p.lent.is_none() && p.access_kind == AccessKind::Subscription && p.runtime == RuntimeKind::Claude
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
                    json!({"id": p.id, "name": p.name, "model": p.model, "models": p.models, "check": s.and_then(|s| s.check.clone()), "quota": s.and_then(|s| s.quota.clone())})
                })
                .collect();
            Ok(json!({"profiles": profiles}))
        }
        ASK_TOKEN => {
            let id = request["profile"].as_str().unwrap_or_default();
            let Some(p) = shared.into_iter().find(|p| p.id == id) else { return Err(Refused(format!("profile {id} is not lent")).into()) };
            let home = (!p.machine).then_some(p.home.as_path());
            let (token, expires) = crate::claude_oauth::token(&crate::machine_logins::process_env(), home, None).await?;
            Ok(json!({"token": token, "expiresAt": expires}))
        }
        other => bail!("unknown method {other}"),
    }
}

/// The id a profile lent by `station` has here (profile ids are lowercase letters, digits and dashes).
pub fn local_id(station: &str, profile: &str) -> String {
    let short: String = station.chars().filter(char::is_ascii_alphanumeric).map(|c| c.to_ascii_lowercase()).take(8).collect();
    format!("lan-{short}-{profile}")
}

/// A profile a station lends, as this one runs it.
fn borrowed(settings: &Settings, station: &str, station_name: &str, offer: &Value) -> Option<Profile> {
    let profile = offer["id"].as_str()?;
    let id = local_id(station, profile);
    let strings = |v: &Value| v.as_array().map(|a| a.iter().filter_map(Value::as_str).map(String::from).collect()).unwrap_or_default();
    let name = offer["name"].as_str().unwrap_or(profile);
    Some(Profile {
        name: if station_name.is_empty() { name.to_string() } else { format!("{name} · {station_name}") },
        runtime: RuntimeKind::Claude,
        runtimes: vec![RuntimeKind::Claude],
        access_kind: AccessKind::Subscription,
        key: String::new(),
        provider: None,
        endpoint: None,
        protocol: None,
        home: settings.data_dir.join("lan").join(&id),
        envs: Default::default(),
        custom_env: Default::default(),
        model: offer["model"].as_str().map(String::from),
        models: strings(&offer["models"]),
        machine: false,
        background_on_message: true,
        fast: false,
        share_on_lan: false,
        lent: Some(Lent { station: station.into(), profile: profile.into() }),
        id,
    })
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
                    let check = serde_json::from_value(offer["check"].clone()).ok();
                    let quota = serde_json::from_value(offer["quota"].clone()).ok();
                    health.insert(p.id.clone(), Health { on_lan: true, check, quota });
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
                    let mut was = settings.lan.health(&p.id).unwrap_or_default();
                    was.on_lan = false;
                    health.insert(p.id.clone(), was);
                    profiles.push(p);
                }
            }
        }
    }
    for p in &profiles {
        let _ = std::fs::create_dir_all(&p.home);
    }
    *settings.lan.health.lock().unwrap() = health;
    settings.set_lent(profiles);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn settings(dir: &std::path::Path, profiles: Value) -> Arc<Settings> {
        std::fs::write(dir.join("config.json"), json!({"profiles": profiles}).to_string()).unwrap();
        Settings::open(&dir.join("config.json"), dir).unwrap()
    }

    #[tokio::test]
    async fn only_a_claude_subscription_marked_shared_is_lent_and_only_over_the_lan() {
        let dir = tempfile::tempdir().unwrap();
        let s = settings(
            dir.path(),
            json!([
                {"id": "cc", "name": "Max", "runtime": "claude", "access": {"kind": "subscription"}, "home": "homes/cc", "models": ["claude-opus-5-5"], "shareOnLan": true},
                {"id": "kept", "runtime": "claude", "access": {"kind": "subscription"}, "home": "homes/kept"},
                {"id": "cx", "runtime": "codex", "access": {"kind": "subscription"}, "home": "homes/cx", "shareOnLan": true},
            ]),
        );
        let store = Store::open(dir.path().join("stillfail.db").to_str().unwrap(), None).unwrap();
        store.set_profile_quota("cc", &json!({"state": "ok", "windows": [], "checkedAt": 1})).unwrap();
        let lent = answer(&s, &store, true, &json!({"method": ASK_LENT})).await.unwrap();
        let ids: Vec<&str> = lent["profiles"].as_array().unwrap().iter().map(|p| p["id"].as_str().unwrap()).collect();
        assert_eq!(ids, ["cc"]);
        assert_eq!(lent["profiles"][0]["models"], json!(["claude-opus-5-5"]));
        assert_eq!(lent["profiles"][0]["quota"]["state"], "ok");
        let refused = answer(&s, &store, false, &json!({"method": ASK_LENT})).await.unwrap_err();
        assert_eq!(refused.to_string(), NOT_ON_LAN);
        assert!(answer(&s, &store, false, &json!({"method": ASK_TOKEN, "profile": "cc"})).await.is_err());
        let not_lent = answer(&s, &store, true, &json!({"method": ASK_TOKEN, "profile": "kept"})).await.unwrap_err();
        assert!(not_lent.to_string().contains("not lent"), "{not_lent}");
    }

    /// A fake workspace: `lender` lends `cc` while `lan` says so; `gone` takes it out of the roster.
    struct Fake {
        lan: Mutex<bool>,
        gone: Mutex<bool>,
    }

    fn call(fake: Arc<Fake>) -> Call {
        Arc::new(move |target: String, request: Value| {
            let fake = fake.clone();
            Box::pin(async move {
                match (target.as_str(), request["method"].as_str().unwrap()) {
                    ("", "peers") => {
                        let mut stations = vec![json!({"id": "me0000000000", "name": "here"})];
                        if !*fake.gone.lock().unwrap() {
                            stations.push(json!({"id": "abcdef0123456789", "name": "studio"}));
                        }
                        Ok(json!({"self": "me0000000000", "stations": stations, "current": true}))
                    }
                    ("abcdef0123456789", ASK_LENT) if *fake.lan.lock().unwrap() => Ok(json!({"profiles": [
                        {"id": "cc", "name": "Max", "models": ["claude-opus-5-5"], "check": {"state": "ok", "detail": "", "models": null, "checkedAt": 1}, "quota": null}
                    ]})),
                    ("abcdef0123456789", ASK_LENT) => Err(Refused(NOT_ON_LAN.into()).into()),
                    ("abcdef0123456789", ASK_TOKEN) => Ok(json!({"token": "access", "expiresAt": 99})),
                    other => panic!("unexpected {other:?}"),
                }
            })
        })
    }

    #[tokio::test]
    async fn a_borrower_runs_what_is_lent_while_on_the_lan_and_keeps_it_unusable_off_it() {
        let dir = tempfile::tempdir().unwrap();
        let s = settings(dir.path(), json!([{"id": "own", "runtime": "claude", "access": {"kind": "subscription"}, "home": "homes/own"}]));
        let fake = Arc::new(Fake { lan: Mutex::new(true), gone: Mutex::new(false) });
        s.lan.attach(call(fake.clone()));
        let mut changes = s.subscribe();
        changes.borrow_and_update();

        round(&s).await;
        let config = s.config();
        let lent = config.profiles.iter().find(|p| p.lent.is_some()).unwrap();
        assert_eq!(lent.id, "lan-abcdef01-cc");
        assert_eq!(lent.name, "Max · studio");
        assert!(lent.runs("claude-opus-5-5"));
        assert!(lent.home.starts_with(dir.path().join("lan")) && lent.home.is_dir());
        assert!(s.lan.on_lan(&lent.id));
        assert_eq!(s.lan.check(&lent.id).unwrap().state, "ok");
        assert_eq!(s.lan.token(lent.lent.as_ref().unwrap()).await.unwrap(), ("access".into(), 99));
        assert!(changes.has_changed().unwrap());
        changes.borrow_and_update();
        assert!(read_raw_profiles(dir.path()).iter().all(|id| id == "own"), "never written to config.json");

        round(&s).await;
        assert!(!changes.has_changed().unwrap(), "the same profiles again change nothing");

        *fake.lan.lock().unwrap() = false;
        round(&s).await;
        assert!(s.config().profiles.iter().any(|p| p.id == "lan-abcdef01-cc"), "kept, so its sessions are moved");
        assert!(!s.lan.on_lan("lan-abcdef01-cc"));
        assert_eq!(s.lan.check("lan-abcdef01-cc").unwrap().state, "failed");

        // An edit of the station's own config keeps what is lent.
        s.update(|raw| {
            raw.max_nudges = Some(3);
            Ok(())
        })
        .unwrap();
        assert!(s.config().profiles.iter().any(|p| p.id == "lan-abcdef01-cc"));

        *fake.gone.lock().unwrap() = true;
        round(&s).await;
        assert!(s.config().profiles.iter().all(|p| p.lent.is_none()), "its station left the workspace");
    }

    fn read_raw_profiles(dir: &std::path::Path) -> Vec<String> {
        crate::config::read_raw(&dir.join("config.json")).unwrap().profiles.unwrap_or_default().into_iter().map(|p| p.id).collect()
    }
}
