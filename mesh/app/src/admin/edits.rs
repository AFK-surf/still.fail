//! What the pages change: connects and profiles in the config, sign-ins that make profiles, and profiles' checks and
//! allowances.

use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{Result, anyhow, bail};
use base64::Engine;
use stillfail_shapes::{AccessKind, ConnectMode, RuntimeKind};
use serde_json::{Value, json};
use tracing::{info, warn};

use super::{AdminApi, CheckRequest, Input, Pending, http_error};
use crate::access::Viewer;
use crate::lang::{spoken, t};
use crate::config::{Owner, Profile, RawBind, RawConfig, RawConnect, RawPlace, RawProfile, RawProfileAccess, RawSlack, runtime_name};
use crate::login::LoginState;
use crate::profiles::{ProfileCheck, ProfileQuota, needs_key, runtimes_for, runtimes_of};

fn random_hex(n: usize) -> String {
    let mut b = vec![0u8; n];
    let _ = getrandom::fill(&mut b);
    hex::encode(b)
}

/// A profile as a check or sign-in needs it, before it is in the config.
pub fn bare_profile(id: &str, runtime: RuntimeKind, kind: AccessKind, key: &str, home: &Path) -> Profile {
    Profile {
        id: id.into(),
        name: id.into(),
        runtime,
        runtimes: runtimes_of(kind, Some(runtime)),
        access_kind: kind,
        key: key.into(),
        provider: None,
        endpoint: None,
        protocol: None,
        home: home.to_path_buf(),
        envs: BTreeMap::new(),
        custom_env: BTreeMap::new(),
        model: None,
        models: vec![],
        machine: false,
        background_on_message: true,
        fast: false,
    }
}

fn runtime_of(value: Option<&Value>) -> Option<RuntimeKind> {
    serde_json::from_value(value?.clone()).ok()
}

/// A slug for an id: lower case, runs of anything else as one dash, at most `max` long.
fn slug(text: &str, max: usize) -> String {
    let mut out = String::new();
    for c in text.to_lowercase().chars() {
        if c.is_ascii_alphanumeric() {
            out.push(c);
        } else if !out.ends_with('-') {
            out.push('-');
        }
    }
    out.trim_matches('-').chars().take(max).collect::<String>().trim_end_matches('-').to_string()
}

/// The first of base, base-2, base-3 … not taken.
fn unique(base: &str, taken: &HashSet<String>) -> String {
    let mut id = base.to_string();
    let mut n = 2;
    while taken.contains(&id) {
        id = format!("{base}-{n}");
        n += 1;
    }
    id
}

/// Ids a new profile may not take: the profiles' own, and every home already on disk (a deleted profile's home stays,
/// and a new one cannot be moved onto it).
fn taken_ids(config: &crate::config::Config) -> HashSet<String> {
    let homes = std::fs::read_dir(config.data_dir.join("homes")).into_iter().flatten().flatten();
    config.profiles.iter().map(|p| p.id.clone()).chain(homes.filter_map(|e| e.file_name().into_string().ok())).collect()
}

/// The account a subscription home is signed in as, when its files say: Codex's id token, Claude's account record.
pub(super) fn account_email(runtime: RuntimeKind, home: &Path) -> Option<String> {
    if runtime == RuntimeKind::Codex {
        let auth: Value = serde_json::from_str(&std::fs::read_to_string(home.join("auth.json")).ok()?).ok()?;
        let payload = auth["tokens"]["id_token"].as_str()?.split('.').nth(1)?;
        let claims: Value = serde_json::from_slice(&base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(payload.trim_end_matches('=')).ok()?).ok()?;
        return claims["email"].as_str().or_else(|| claims["https://api.openai.com/profile"]["email"].as_str()).map(String::from);
    }
    [home.join(".claude.json"), home.join("claude.json")].iter().find_map(|file| {
        let config: Value = serde_json::from_str(&std::fs::read_to_string(file).ok()?).ok()?;
        config["oauthAccount"]["emailAddress"].as_str().map(String::from)
    })
}

/// A profile leaving its runtime (deleted, or moved to another): refused when it is the last one of a runtime that
/// connects run.
fn last_of_runtime(raw: &RawConfig, runtime: RuntimeKind, id: &str) -> Result<()> {
    let profiles = raw.profiles.as_deref().unwrap_or_default();
    if profiles.iter().any(|p| p.id != id && runtimes_for(p.access.as_ref(), p.runtime).contains(&runtime)) {
        return Ok(());
    }
    let users: Vec<String> = raw
        .connects
        .as_deref()
        .unwrap_or_default()
        .iter()
        .filter(|c| c.bind.runtime == runtime)
        .map(|c| c.slack.as_ref().and_then(|s| s.bot_name.clone()).filter(|n| !n.is_empty()).unwrap_or_else(|| c.id.clone()))
        .collect();
    if !users.is_empty() {
        bail!(t!(spoken(); "station.profile.lastForRuntime", runtime = runtime_name(runtime), users = users.join(&t!(spoken(); "station.list.separator"))));
    }
    Ok(())
}

/// Who a connect belongs to: whoever added it, unless `requested` hands it to someone else. Only the station itself,
/// a workspace owner or admin, or the current owner may do that.
fn owner_of(current: Option<Owner>, requested: Option<&Value>, viewer: &Viewer) -> Result<Option<Owner>> {
    let Some(requested) = requested else {
        return Ok(current.or_else(|| Some(Owner { id: viewer.id(), name: viewer.name() })));
    };
    let id = requested.get("id").and_then(Value::as_str).map(|s| s.trim().to_lowercase()).unwrap_or_default();
    let email = id.split_once('@').is_some_and(|(a, b)| !a.is_empty() && !b.is_empty() && !id.contains(char::is_whitespace) && !b.contains('@'));
    if id != "local" && !email {
        bail!(t!(spoken(); "station.connect.ownerEmail"));
    }
    let manager = viewer.manages();
    if !manager && current.as_ref().is_none_or(|c| c.id != viewer.id()) {
        bail!(t!(spoken(); "station.connect.ownerWho"));
    }
    let name = requested.get("name").and_then(Value::as_str).map(|n| n.chars().take(120).collect()).unwrap_or_else(|| id.clone());
    Ok(Some(Owner { id, name }))
}

/// A field given as a string, trimmed and not empty; None when absent (`given` says whether it was).
fn field(object: Option<&Value>, key: &str) -> (bool, Option<String>) {
    match object.and_then(|o| o.get(key)) {
        None => (false, None),
        Some(v) => (true, v.as_str().map(str::trim).filter(|s| !s.is_empty()).map(String::from)),
    }
}

impl AdminApi {
    /// Edits the config for `viewer` (said in the log as `what`); the overview as it is then.
    pub(super) fn save(&self, viewer: &Viewer, what: &str, edit: impl FnOnce(&mut RawConfig) -> Result<()>) -> Result<Value> {
        self.deps.settings.update(edit).map_err(|e| http_error(400, e.to_string()))?;
        info!(what, by = viewer.id(), "config changed from the admin page");
        Ok(self.overview(viewer))
    }

    pub(super) fn put_connect(&self, id: &str, input: &Input, viewer: &Viewer) -> Result<Value> {
        self.save(viewer, &format!("connect {id}"), |raw| {
            let existing = raw.connects.as_deref().unwrap_or_default().iter().find(|c| c.id == id).cloned();
            let slack = input.get("slack");
            let old = existing.as_ref().and_then(|c| c.slack.clone()).unwrap_or_default();
            let token = |key: &str, stored: Option<String>| field(slack, key).1.or(stored);
            let app_token = token("appToken", old.app_token.clone());
            let bot_token = token("botToken", old.bot_token.clone());
            let bind = input.get("bind");
            let kept = |key: &str, stored: Option<String>| match field(bind, key) {
                (true, given) => given,
                (false, _) => stored,
            };
            let old_bind = existing.as_ref().map(|c| c.bind.clone());
            let model = kept("model", old_bind.as_ref().and_then(|b| b.model.clone()));
            let effort = kept("effort", old_bind.as_ref().and_then(|b| b.effort.clone()));
            let profile = kept("profile", old_bind.as_ref().and_then(|b| b.profile.clone()));
            // A connect's runtime is chosen when it is made: its sessions and their history belong to it.
            let given = bind.and_then(|b| b.get("runtime"));
            let runtime = match (old_bind.as_ref().map(|b| b.runtime), given) {
                (Some(runtime), _) => runtime,
                (None, Some(v)) => runtime_of(Some(v)).ok_or_else(|| anyhow!("unknown runtime {}", v.as_str().map(String::from).unwrap_or_else(|| v.to_string())))?,
                (None, None) => bail!("runtime is required"),
            };
            // The profile its sessions keep to (None: the pool's pick), one that runs its runtime and model.
            if let Some(profile) = &profile {
                let p = raw.profiles.as_deref().unwrap_or_default().iter().find(|p| &p.id == profile);
                let runs = p.is_some_and(|p| runtimes_for(p.access.as_ref(), p.runtime).contains(&runtime));
                if !runs {
                    bail!(t!(spoken(); "station.profile.cannotRun", profile = profile, runtime = runtime_name(runtime)));
                }
                if let (Some(model), Some(p)) = (&model, p) {
                    if !p.models.as_deref().unwrap_or_default().iter().any(|m| stillfail_shapes::model::same(m, model)) {
                        bail!(t!(spoken(); "station.profile.modelOff", profile = p.name.clone().unwrap_or_else(|| profile.clone()), model = model));
                    }
                }
            }
            if let Some(effort) = effort.as_ref().filter(|_| bind.is_some_and(|b| ["model", "effort", "profile"].iter().any(|f| b.get(f).is_some()))) {
                let allowed = self.deps.hub.model_efforts(runtime, model.as_deref(), profile.as_deref());
                if !allowed.contains(effort) {
                    bail!(t!(spoken(); "station.profile.efforts", runtime = runtime_name(runtime), efforts = allowed.join(&t!(spoken(); "station.list.separator"))));
                }
            }
            // Who it is in Slack: given with new tokens (as they were verified), else as last seen.
            let team = slack.and_then(|s| s.get("team")).filter(|t| t.is_object()).and_then(|t| serde_json::from_value::<RawPlace>(t.clone()).ok());
            let (team, bot_name, bot_image) = match team {
                Some(team) => (
                    Some(team),
                    slack.and_then(|s| s.get("botName")).and_then(Value::as_str).map(String::from),
                    slack.and_then(|s| s.get("botImage")).and_then(Value::as_str).filter(|i| !i.is_empty()).map(String::from),
                ),
                None if old.team.is_some() => (old.team.clone(), old.bot_name.clone(), old.bot_image.clone()),
                None => (None, None, None),
            };
            let any_slack = app_token.is_some() || bot_token.is_some() || old.app_id.is_some() || team.is_some();
            let next = RawConnect {
                id: id.into(),
                created_by: owner_of(existing.as_ref().and_then(|c| c.created_by.clone()), input.get("owner"), viewer)?,
                enabled: Some(input.get("enabled").and_then(Value::as_bool).or(existing.as_ref().and_then(|c| c.enabled)).unwrap_or(true)),
                kind: Some(input.str("kind").map(String::from).or(existing.as_ref().and_then(|c| c.kind.clone())).unwrap_or_else(|| "slack".into())),
                mode: Some(
                    input.get("mode").and_then(|m| serde_json::from_value::<ConnectMode>(m.clone()).ok()).or(existing.as_ref().and_then(|c| c.mode)).unwrap_or(ConnectMode::MultiSession),
                ),
                require_mention: Some(input.get("requireMention").and_then(Value::as_bool).or(existing.as_ref().and_then(|c| c.require_mention)).unwrap_or(true)),
                slack: any_slack.then(|| RawSlack { app_token, bot_token, app_id: old.app_id.clone(), team, bot_name, bot_image }),
                bind: RawBind { runtime, model, effort, profile },
                rest: existing.as_ref().map(|c| c.rest.clone()).unwrap_or_default(),
            };
            let connects = raw.connects.get_or_insert_with(Vec::new);
            match connects.iter_mut().find(|c| c.id == id) {
                Some(slot) => *slot = next,
                None => connects.push(next),
            }
            Ok(())
        })
    }

    pub(super) fn delete_connect(&self, id: &str, viewer: &Viewer) -> Result<Value> {
        self.save(viewer, &format!("delete connect {id}"), |raw| {
            let connects = raw.connects.get_or_insert_with(Vec::new);
            if !connects.iter().any(|c| c.id == id) {
                bail!("unknown connect {id}");
            }
            connects.retain(|c| c.id != id);
            Ok(())
        })
    }

    pub(super) fn put_profile(&self, id: &str, given: &Input, viewer: &Viewer) -> Result<Value> {
        self.save(viewer, &format!("profile {id}"), |raw| {
            let existing = raw.profiles.as_deref().unwrap_or_default().iter().find(|p| p.id == id).cloned();
            let machine = existing.as_ref().and_then(|p| p.machine).unwrap_or(false);
            // One on the machine's login is the machine's: only which of its models are used, and how it runs, are chosen
            // here.
            let get = |key: &str| if machine && !["model", "models", "backgroundOnMessage", "fast"].contains(&key) { None } else { given.get(key) };
            // env: a string sets the value; null removes the key; an omitted key keeps it (so masked secrets survive
            // edits).
            let mut env = existing.as_ref().and_then(|p| p.env.clone()).unwrap_or_default();
            for (key, value) in get("env").and_then(Value::as_object).into_iter().flatten() {
                let valid = key.starts_with(|c: char| c.is_ascii_alphabetic() || c == '_') && key.chars().all(|c| c.is_ascii_alphanumeric() || c == '_');
                if !valid {
                    bail!("invalid environment variable name {key}");
                }
                match value {
                    Value::Null => {
                        env.remove(key);
                    }
                    Value::String(v) => {
                        env.insert(key.clone(), v.clone());
                    }
                    _ => {}
                }
            }
            let access = get("access");
            let kind = access.and_then(|a| a.get("kind")).and_then(|k| serde_json::from_value::<AccessKind>(k.clone()).ok()).or(existing.as_ref().and_then(|p| p.access.as_ref().map(|a| a.kind)));
            let given_key = access.and_then(|a| a.get("key")).and_then(Value::as_str).map(str::trim).filter(|k| !k.is_empty()).map(String::from);
            let keep = existing.as_ref().and_then(|p| p.access.as_ref()).filter(|a| Some(a.kind) == kind);
            let key = given_key.or(keep.and_then(|a| a.key.clone()));
            // An API provider stays the one it was made for; its address can be changed.
            let provider = keep.and_then(|a| a.provider.clone());
            let endpoint = match access.and_then(|a| a.get("endpoint")).and_then(Value::as_str) {
                Some(given) => Some(stillfail_shapes::providers::clean_endpoint(given).ok_or_else(|| http_error(400, t!(spoken(); "station.profile.addressNeeded")))?),
                None => keep.and_then(|a| a.endpoint.clone()),
            };
            let protocol = keep.and_then(|a| a.protocol.clone());
            let name = match get("name").and_then(Value::as_str) {
                Some(n) => Some(n.trim().to_string()),
                None => existing.as_ref().and_then(|p| p.name.clone()),
            };
            let model = match get("model") {
                Some(Value::String(m)) => Some(m.trim().to_string()),
                Some(_) => None,
                None => existing.as_ref().and_then(|p| p.model.clone()),
            }
            .filter(|m| !m.is_empty());
            let models = match get("models") {
                Some(Value::Array(ms)) => {
                    let mut seen = HashSet::new();
                    let list: Vec<String> =
                        ms.iter().map(|m| m.as_str().map(String::from).unwrap_or_else(|| m.to_string()).trim().to_string()).filter(|m| !m.is_empty() && seen.insert(m.clone())).take(200).collect();
                    Some(list)
                }
                Some(_) => None,
                None => existing.as_ref().and_then(|p| p.models.clone()),
            }
            .filter(|m| !m.is_empty());
            // One model named by hand (a provider that does not list its models): added to those enabled.
            let models = match get("addModel").and_then(Value::as_str).map(str::trim).filter(|m| !m.is_empty()) {
                Some(added) => {
                    let mut list = models.unwrap_or_default();
                    if !list.iter().any(|m| m == added) {
                        list.push(added.chars().take(200).collect());
                    }
                    Some(list)
                }
                None => models,
            };
            let next = RawProfile {
                id: id.into(),
                name: name.filter(|n| !n.is_empty()),
                runtime: get("runtime").and_then(|r| serde_json::from_value(r.clone()).ok()).or(existing.as_ref().and_then(|p| p.runtime)),
                access: kind.map(|kind| RawProfileAccess { kind, key, provider: provider.clone().filter(|_| kind == AccessKind::ApiProvider), endpoint: endpoint.clone().filter(|_| kind == AccessKind::ApiProvider), protocol: protocol.clone().filter(|_| kind == AccessKind::ApiProvider) }),
                home: get("home").and_then(Value::as_str).map(str::trim).filter(|h| !h.is_empty()).map(String::from).or(existing.as_ref().map(|p| p.home.clone())).unwrap_or_else(|| format!("homes/{id}")),
                env: Some(env),
                model,
                models,
                machine: machine.then_some(true),
                fast: match get("fast") {
                    Some(Value::Bool(on)) => Some(*on),
                    Some(_) => return Err(http_error(400, "fast must be a boolean")),
                    None => existing.as_ref().and_then(|p| p.fast),
                }.filter(|on| *on),
                // Only the default's opposite is written.
                background_on_message: match get("backgroundOnMessage") {
                    Some(Value::Bool(on)) => Some(*on),
                    _ => existing.as_ref().and_then(|p| p.background_on_message),
                }
                .filter(|on| !on),
            };
            if let Some(old) = &existing {
                let kept = runtimes_for(next.access.as_ref(), next.runtime);
                for r in runtimes_for(old.access.as_ref(), old.runtime) {
                    if !kept.contains(&r) {
                        last_of_runtime(raw, r, id)?;
                    }
                }
            }
            let profiles = raw.profiles.get_or_insert_with(Vec::new);
            match profiles.iter_mut().find(|p| p.id == id) {
                Some(slot) => *slot = next,
                None => profiles.push(next),
            }
            Ok(())
        })
    }

    pub(super) fn delete_profile(&self, id: &str, viewer: &Viewer) -> Result<Value> {
        self.save(viewer, &format!("delete profile {id}"), |raw| {
            let profile = raw.profiles.as_deref().unwrap_or_default().iter().find(|p| p.id == id).cloned().ok_or_else(|| anyhow!("unknown profile {id}"))?;
            for r in runtimes_for(profile.access.as_ref(), profile.runtime) {
                last_of_runtime(raw, r, id)?;
            }
            raw.profiles.get_or_insert_with(Vec::new).retain(|p| p.id != id);
            Ok(())
        })
    }

    pub(super) async fn reset_quota(&self, id: &str, key: &str) -> Result<Value> {
        let profile = self.config().profiles.iter().find(|p| p.id == id).cloned().ok_or_else(|| http_error(404, t!(spoken(); "station.profile.notFound")))?;
        if profile.runtime != RuntimeKind::Codex || profile.access_kind != AccessKind::Subscription {
            return Err(http_error(400, t!(spoken(); "station.quota.resetOpenAiOnly")));
        }
        let reset = self.deps.reset_quota.as_ref().ok_or_else(|| http_error(503, t!(spoken(); "station.quota.resetUnsupported")))?;
        let result = reset(profile, key.to_string()).await?;
        self.read_quota(id, true).await?;
        match result.get("outcome").and_then(Value::as_str) {
            Some("reset" | "alreadyRedeemed") => Ok(result),
            Some("nothingToReset") => Err(http_error(409, t!(spoken(); "station.quota.nothingToReset"))),
            Some("noCredit") => Err(http_error(409, t!(spoken(); "station.quota.noCredit"))),
            _ => Err(http_error(502, t!(spoken(); "station.quota.resetUnconfirmed"))),
        }
    }

    /// A profile's allowance, asked again (unless a question is on its way already).
    pub(super) async fn refresh_quota(&self, id: &str) -> Result<Option<ProfileQuota>> {
        self.read_quota(id, false).await
    }

    async fn read_quota(&self, id: &str, after_reset: bool) -> Result<Option<ProfileQuota>> {
        let pending = self.quota_pending.lock().unwrap().entry(id.to_string()).or_default().clone();
        // A reset must read after any older refresh, so an in-flight pre-reset snapshot cannot win.
        let _guard = if after_reset { pending.lock().await } else {
            match pending.try_lock() {
                Ok(guard) => guard,
                Err(_) => return Ok(self.quotas.lock().unwrap().get(id).cloned()),
            }
        };
        let profile = self.config().profiles.iter().find(|p| p.id == id).cloned().ok_or_else(|| http_error(404, format!("unknown profile {id}")))?;
        let Some(quota) = self.deps.quota.clone() else { return Ok(self.quotas.lock().unwrap().get(id).cloned()) };
        let read = quota(profile).await;
        self.quotas.lock().unwrap().insert(id.to_string(), read.clone());
        self.deps.store.set_profile_quota(id, &serde_json::to_value(&read)?)?;
        self.events.overview_changed();
        Ok(Some(read))
    }

    pub(super) async fn check(self: &Arc<Self>, id: &str) -> Result<ProfileCheck> {
        let profile = self.config().profiles.iter().find(|p| p.id == id).cloned().ok_or_else(|| http_error(404, format!("unknown profile {id}")))?;
        let mut check = (self.deps.check_profile)(CheckRequest { home: profile.home.clone(), profile: profile.clone() }).await;
        // Keep Codex capabilities for each account, including providers whose model ids came from their API.
        let codex_subscription = profile.access_kind == AccessKind::Subscription && profile.runtime == RuntimeKind::Codex;
        if let (true, Some(models)) = (matches!(check.state.as_str(), "ok" | "unknown") && profile.runtimes.contains(&RuntimeKind::Codex), self.deps.codex_models.clone()) {
            match models(profile.clone()).await {
                Ok(catalog) => {
                    if codex_subscription && check.models.is_none() {
                        check.models = Some(catalog.models);
                    }
                    check.model_efforts = Some(std::collections::HashMap::from([("codex".into(), catalog.efforts)]));
                }
                Err(e) => {
                    // A temporary listing failure must not erase a saved max/ultra selection in the clients.
                    if let Some(previous) = self.checks.lock().unwrap().get(id) {
                        check.model_efforts = previous.model_efforts.clone();
                        if codex_subscription && check.models.is_none() {
                            check.models = previous.models.clone();
                        }
                    }
                    check.detail = t!(spoken(); "station.profile.modelsStale", detail = check.detail);
                    warn!(profile = id, error = %e, "could not list codex model capabilities");
                }
            }
        }
        check.decision = Some(crate::decision::profiles::discover(&profile, &check).await);
        // A profile edited during the probe must not inherit the previous account's capabilities.
        if self.config().profiles.iter().find(|p| p.id == id).is_none_or(|p| crate::decision::profiles::fingerprint(p) != crate::decision::profiles::fingerprint(&profile)) {
            return Err(http_error(409, "Profile 已修改，请重新检查"));
        }
        self.checks.lock().unwrap().insert(id.to_string(), check.clone());
        self.deps.store.set_profile_check(id, &serde_json::to_value(&check)?)?;
        self.events.overview_changed();
        // One never asked yet (just made, however): its allowance now, not at the next round.
        if check.state == "ok" && !self.quotas.lock().unwrap().contains_key(id) {
            let (api, id) = (self.clone(), id.to_string());
            tokio::spawn(async move {
                if let Err(e) = api.refresh_quota(&id).await {
                    warn!(profile = id, error = %e, "quota after a first check failed");
                }
            });
        }
        Ok(check)
    }

    /// A profile just signed in: checked (which lists its models) and its quota read, so its page shows them at once.
    pub(super) fn after_sign_in(self: &Arc<Self>, id: &str) {
        let (api, id) = (self.clone(), id.to_string());
        tokio::spawn(async move {
            if let Err(e) = api.check(&id).await {
                warn!(profile = id, error = %e, "check after sign-in failed");
            }
            if let Err(e) = api.refresh_quota(&id).await {
                warn!(profile = id, error = %e, "quota after sign-in failed");
            }
        });
    }

    /// Signing a subscription in before there is a profile: the profile is made once the sign-in succeeds.
    pub(super) fn new_login(&self, input: &Input, viewer: &Viewer) -> Result<Value> {
        let runtime = runtime_of(input.get("runtime")).ok_or_else(|| http_error(400, format!("unknown runtime {}", input.text("runtime"))))?;
        let id = format!("login-{}", random_hex(4));
        let home = self.config().data_dir.join("homes").join(&id);
        self.pending.lock().unwrap().insert(id.clone(), Pending { runtime, home: home.clone(), by: viewer.clone(), created: None, error: None });
        info!(login = id, runtime = runtime_name(runtime), by = viewer.id(), "sign-in for a new profile started");
        let job = self.deps.logins.start(&bare_profile(&id, runtime, AccessKind::Subscription, "", &home))?;
        Ok(json!({ "id": id, "job": job }))
    }

    /// A sign-in for a new profile moved on: once it succeeds the profile is made, named by the account signed in.
    pub(super) fn pending_changed(self: &Arc<Self>, id: &str) {
        let Some((runtime, home, by, done)) = self.pending.lock().unwrap().get(id).map(|p| (p.runtime, p.home.clone(), p.by.clone(), p.created.is_some() || p.error.is_some())) else { return };
        let state = self.deps.logins.get(id).map(|j| j.state);
        if matches!(state, Some(LoginState::Failed | LoginState::Cancelled)) {
            let _ = std::fs::remove_dir_all(&home);
            return;
        }
        if state != Some(LoginState::Done) || done {
            return;
        }
        let email = account_email(runtime, &home);
        let config = self.config();
        let taken = taken_ids(&config);
        let base = slug(email.as_deref().unwrap_or(&format!("{}-subscription", runtime_name(runtime))), 40);
        let base = if base.is_empty() { runtime_name(runtime).to_string() } else { base };
        let profile_id = unique(&base, &taken);
        let target: PathBuf = config.data_dir.join("homes").join(&profile_id);
        if let Err(e) = std::fs::rename(&home, &target) {
            warn!(login = id, error = %e, "could not move a new profile's home");
            self.pending_failed(id, t!(spoken(); "station.login.homeFailed", error = e));
            return;
        }
        let name = email.clone().unwrap_or_else(|| t!(spoken(); if runtime == RuntimeKind::Claude { "station.profile.claudeSubscription" } else { "station.profile.chatgptSubscription" }));
        let made = self.save(&by, &format!("profile {profile_id} from a sign-in"), |raw| {
            raw.profiles.get_or_insert_with(Vec::new).push(RawProfile {
                id: profile_id.clone(),
                name: Some(name),
                runtime: Some(runtime),
                access: Some(RawProfileAccess { kind: AccessKind::Subscription, key: None, provider: None, endpoint: None, protocol: None }),
                home: format!("homes/{profile_id}"),
                env: Some(BTreeMap::new()),
                model: None,
                models: None,
                machine: None,
                fast: None, background_on_message: None,
            });
            Ok(())
        });
        if let Err(e) = made {
            warn!(login = id, error = %e, "the signed-in profile was not saved");
            let _ = std::fs::rename(&target, &home);
            self.pending_failed(id, t!(spoken(); "station.login.saveFailed", error = e));
            return;
        }
        if let Some(p) = self.pending.lock().unwrap().get_mut(id) {
            p.created = Some(profile_id.clone());
        }
        self.after_sign_in(&profile_id);
        // Kept a while for the page that started it to follow it to the profile.
        let (me, id) = (self.me.clone(), id.to_string());
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_secs(15 * 60)).await;
            if let Some(api) = me.upgrade() {
                api.drop_login(&id);
            }
        });
    }

    /// A sign-in that succeeded but made no profile: said on the page that started it, which would otherwise wait on.
    fn pending_failed(&self, id: &str, error: String) {
        if let Some(p) = self.pending.lock().unwrap().get_mut(id) {
            p.error = Some(error);
        }
        self.events.overview_changed();
    }

    pub(super) fn drop_login(&self, id: &str) {
        let Some(pending) = self.pending.lock().unwrap().remove(id) else { return };
        self.deps.logins.cancel(id);
        if pending.created.is_none() {
            let _ = std::fs::remove_dir_all(&pending.home);
        }
        self.events.overview_changed();
    }

    /// A new keyed profile: made only once its key is checked and works.
    pub(super) async fn new_keyed_profile(self: &Arc<Self>, input: &Input, viewer: &Viewer) -> Result<Value> {
        let access = input.get("access");
        let kind = access.and_then(|a| a.get("kind")).and_then(|k| serde_json::from_value::<AccessKind>(k.clone()).ok());
        let Some(kind) = kind else { return Err(http_error(400, format!("unknown access {}", access.and_then(|a| a.get("kind")).map(|k| k.to_string()).unwrap_or_default()))) };
        if kind == AccessKind::Subscription {
            return Err(http_error(400, t!(spoken(); "station.profile.subscriptionBySignIn")));
        }
        // An API provider is the one named, at the address given where the provider has none of its own.
        let provider = access.and_then(|a| a.get("provider")).and_then(Value::as_str).map(str::trim).filter(|p| !p.is_empty()).map(String::from);
        let endpoint = access.and_then(|a| a.get("endpoint")).and_then(Value::as_str).map(str::trim).filter(|e| !e.is_empty()).map(String::from);
        let protocol = access.and_then(|a| a.get("protocol")).and_then(Value::as_str).map(str::trim).filter(|e| !e.is_empty()).map(String::from);
        let source = if kind == AccessKind::ApiProvider {
            // The two kinds that came before the list are added as they were (their own words and ids).
            let source = provider.as_deref().and_then(stillfail_shapes::providers::find).filter(|s| s.legacy.is_none());
            let source = source.ok_or_else(|| http_error(400, t!(spoken(); "station.profile.unknownProvider")))?;
            // The protocol chosen: one the provider speaks at an address of the reader's own; a provider with one takes it.
            let protocol = protocol.as_deref().filter(|_| source.endpoint_required).or_else(|| source.protocols.first().filter(|_| source.endpoint_required && source.protocols.len() == 1).map(|p| p.id()));
            if stillfail_shapes::providers::endpoints(source, endpoint.as_deref(), protocol).is_none() {
                return Err(http_error(400, t!(spoken(); "station.profile.addressNeeded")));
            }
            Some(source)
        } else {
            None
        };
        let endpoint = endpoint.and_then(|e| stillfail_shapes::providers::clean_endpoint(&e)).filter(|_| source.is_some());
        // Of one at the reader's own address: the protocol it speaks there (the only one it has, or the one chosen).
        let protocol = source.filter(|s| s.endpoint_required).and_then(|s| protocol.filter(|p| stillfail_shapes::providers::Protocol::parse(p).is_some_and(|p| s.protocols.contains(&p))).or_else(|| (s.protocols.len() == 1).then(|| s.protocols[0].id().to_string()))).or_else(|| source.filter(|s| s.endpoint_required).and_then(|s| s.protocols.first().map(|p| p.id().to_string())));
        // A key runs every runtime it can (runtimes_of); custom variables are for the runtime given.
        let runtimes = match source {
            Some(source) => stillfail_shapes::providers::uses(&stillfail_shapes::providers::endpoints(source, endpoint.as_deref(), protocol.as_deref()).unwrap_or_default()).runtimes(),
            None => runtimes_of(kind, runtime_of(input.get("runtime"))),
        };
        if (runtimes.is_empty() && source.is_none()) || !runtimes.iter().all(|r| crate::profiles::access_kinds(*r).contains(&kind)) {
            return Err(http_error(400, format!("unknown access {}", serde_json::to_value(kind)?.as_str().unwrap_or(""))));
        }
        let runtime = runtimes.first().copied().unwrap_or(RuntimeKind::Claude);
        let key = access.and_then(|a| a.get("key")).and_then(Value::as_str).unwrap_or("").trim().to_string();
        if needs_key(kind, source.map(|s| s.id)) && key.is_empty() {
            return Err(http_error(400, t!(spoken(); "station.profile.keyRequired")));
        }
        let config = self.config();
        let trial = config.data_dir.join("homes").join(format!("new-{}", random_hex(4)));
        std::fs::create_dir_all(&trial)?;
        let mut bare = bare_profile("new", runtime, kind, &key, &trial);
        bare.provider = source.map(|s| s.id.to_string());
        bare.endpoint = endpoint.clone();
        bare.protocol = protocol.clone();
        bare.runtimes = runtimes;
        let check = (self.deps.check_profile)(CheckRequest { profile: bare, home: trial.clone() }).await;
        // A provider with no model list leaves its key unchecked (state unknown); a refused key is what stops it.
        let refused = if source.is_some() { check.state == "failed" } else { check.state != "ok" && crate::profiles::keyed(kind) };
        if refused {
            let _ = std::fs::remove_dir_all(&trial);
            return Err(http_error(400, t!(spoken(); "station.profile.checkFailed", detail = check.detail)));
        }
        let label = match (kind, source) {
            (_, Some(source)) => source.name.to_string(),
            (AccessKind::OpencodeGo, _) => "OpenCode Go".to_string(),
            (AccessKind::AnthropicApi, _) => "Anthropic API".to_string(),
            _ => t!(spoken(); "station.profile.envName", runtime = if runtime == RuntimeKind::Claude { "Claude Code" } else { "Codex" }),
        };
        let taken = taken_ids(&config);
        let base = match source {
            Some(source) => source.id.to_string(),
            None if kind == AccessKind::Env => format!("{}-env", runtime_name(runtime)),
            None => serde_json::to_value(kind)?.as_str().unwrap_or("profile").to_string(),
        };
        let id = unique(&base, &taken);
        std::fs::rename(&trial, config.data_dir.join("homes").join(&id))?;
        let overview = self.save(viewer, &format!("profile {id}"), |raw| {
            raw.profiles.get_or_insert_with(Vec::new).push(RawProfile {
                id: id.clone(),
                name: Some(label),
                runtime: (kind == AccessKind::Env).then_some(runtime),
                access: Some(RawProfileAccess { kind, key: (!key.is_empty()).then(|| key.clone()), provider: source.map(|s| s.id.to_string()), endpoint: endpoint.clone(), protocol: protocol.clone() }),
                home: format!("homes/{id}"),
                env: Some(BTreeMap::new()),
                model: None,
                models: None,
                machine: None,
                fast: None, background_on_message: None,
            });
            Ok(())
        })?;
        self.checks.lock().unwrap().insert(id.clone(), check.clone());
        self.deps.store.set_profile_check(&id, &serde_json::to_value(&check)?)?;
        self.events.overview_changed();
        // What the automatic decisions can use is found out once the profile is made: the probe asks the provider
        // with a model of its own, and a request to add must not wait on that (a slow provider ran the add out of time).
        if let Some(profile) = self.config().profiles.iter().find(|p| p.id == id).cloned() {
            let hub = Arc::clone(self);
            let id = id.clone();
            let mut check = check;
            tokio::spawn(async move {
                check.decision = Some(crate::decision::profiles::discover(&profile, &check).await);
                // A profile edited or removed meanwhile must not inherit what was found for the one it was.
                if hub.config().profiles.iter().find(|p| p.id == id).is_none_or(|p| crate::decision::profiles::fingerprint(p) != crate::decision::profiles::fingerprint(&profile)) {
                    return;
                }
                hub.checks.lock().unwrap().insert(id.clone(), check.clone());
                if let Err(e) = hub.deps.store.set_profile_check(&id, &serde_json::to_value(&check).unwrap_or_default()) {
                    warn!(profile = id, error = %e, "could not keep what the decisions can use");
                }
                hub.events.overview_changed();
            });
        }
        Ok(json!({ "id": id, "overview": overview }))
    }

    /// A profile on the machine's own login of `runtime`: made when that login is one a profile can use (kept in a
    /// file). Named by its account.
    pub(super) async fn new_machine_profile(self: &Arc<Self>, input: &Input, viewer: &Viewer) -> Result<Value> {
        let runtime = runtime_of(input.get("runtime")).ok_or_else(|| http_error(400, format!("unknown runtime {}", input.text("runtime"))))?;
        let id = format!("machine-{}", runtime_name(runtime));
        let config = self.config();
        if config.profiles.iter().any(|p| p.id == id) {
            return Err(http_error(409, t!(spoken(); "station.machine.alreadyUsed")));
        }
        let machine = self.deps.machine_logins.clone().ok_or_else(|| http_error(400, t!(spoken(); "station.machine.unreadable")))?;
        machine.refresh().await;
        let login = machine.get().into_iter().find(|l| l.runtime == runtime);
        let named = if runtime == RuntimeKind::Claude { "Claude Code" } else { "Codex" };
        let Some(login) = login.filter(|l| l.logged_in) else { return Err(http_error(400, t!(spoken(); "station.machine.notSignedIn", runtime = named))) };
        if !login.usable {
            return Err(http_error(400, t!(spoken(); "station.machine.keychain")));
        }
        let home = config.data_dir.join("homes").join(&id);
        std::fs::create_dir_all(&home)?;
        if runtime == RuntimeKind::Codex {
            crate::machine_logins::link_codex_auth(&home, &machine.env())?;
        }
        let name = match &login.email {
            Some(email) => t!(spoken(); "station.machine.emailName", email = email),
            None => t!(spoken(); "station.machine.runtimeName", runtime = named),
        };
        info!(profile = id, runtime = runtime_name(runtime), by = viewer.id(), "profile on the machine's login made");
        let overview = self.save(viewer, &format!("profile {id} on the machine's login"), |raw| {
            raw.profiles.get_or_insert_with(Vec::new).push(RawProfile {
                id: id.clone(),
                name: Some(name),
                runtime: Some(runtime),
                access: Some(RawProfileAccess { kind: AccessKind::Subscription, key: None, provider: None, endpoint: None, protocol: None }),
                home: format!("homes/{id}"),
                env: Some(BTreeMap::new()),
                model: None,
                models: None,
                machine: Some(true),
                fast: None, background_on_message: None,
            });
            Ok(())
        })?;
        self.after_sign_in(&id);
        Ok(json!({ "id": id, "overview": overview }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_are_made_from_names() {
        assert_eq!(slug("Ada.Lovelace@Example.org", 40), "ada-lovelace-example-org");
        assert_eq!(slug("--", 40), "");
        let taken = HashSet::from(["a".to_string(), "a-2".to_string()]);
        assert_eq!(unique("a", &taken), "a-3");
        assert_eq!(unique("b", &taken), "b");
    }
}
