//! The account pool: which of a station's profiles a new session runs on. Only profiles with the chosen model enabled
//! qualify; of those, one whose check says it cannot sign in or was rejected, or whose allowance is used up, is passed
//! over. Of the rest, the one with the most allowance left wins; then the one running fewer sessions; then the one
//! picked least recently. A session keeps its profile while it is usable (its runtime's cache is that account's); its
//! transcripts are shared by all, so when it is not, another takes it on.

use anyhow::{Result, bail};

use crate::config::Profile;
use crate::profiles::{ProfileCheck, ProfileQuota};

#[derive(Debug, Clone, Default, PartialEq)]
pub struct ProfileHealth {
    pub check: Option<ProfileCheck>,
    pub quota: Option<ProfileQuota>,
    /// A turn on it ran into its allowance since the allowance was last read (Hub::spend).
    pub spent: bool,
}

pub trait PoolSignals {
    fn health(&self, id: &str) -> ProfileHealth;
    /// Sessions with a live process on this profile.
    fn load(&self, id: &str) -> usize;
    /// When the pool last chose this profile (0 if never).
    fn last_picked(&self, id: &str) -> i64;
}

/// How much of its tightest window a profile has used, 0–100; unknown counts as half.
fn used(quota: Option<&ProfileQuota>) -> f64 {
    match quota {
        Some(q) if q.state == "ok" && !q.windows.is_empty() => q.windows.iter().map(|w| w.used_percent).fold(f64::MIN, f64::max),
        _ => 50.0,
    }
}

fn check_state(health: &ProfileHealth) -> Option<&str> {
    health.check.as_ref().map(|c| c.state.as_str())
}

/// Whether a profile can run now: it signs in, its key was not rejected, none of its windows is used up, and no turn
/// ran into its allowance since.
pub fn usable(health: &ProfileHealth) -> bool {
    !health.spent && !matches!(check_state(health), Some("login" | "failed")) && used(health.quota.as_ref()) < 100.0
}

/// A chosen model needs the profile to have it enabled; no model means the profile's own default.
pub fn serves(profile: &Profile, model: Option<&str>) -> bool {
    model.is_none_or(|m| profile.runs(m))
}

/// `strict` (a chat started by hand): the model must be enabled on a profile. Otherwise (a connect's binding, set up
/// before models were enabled) profiles with it enabled are preferred, and without any the bound ones still serve.
pub fn pick_profile<'a>(candidates: &[&'a Profile], model: Option<&str>, signals: &dyn PoolSignals, strict: bool) -> Result<&'a Profile> {
    if candidates.is_empty() {
        bail!("no profile to run on");
    }
    let rank: Vec<(&Profile, ProfileHealth)> = candidates.iter().map(|p| (*p, signals.health(&p.id))).collect();
    let mut serving: Vec<usize> = (0..rank.len()).filter(|&i| serves(rank[i].0, model)).collect();
    if serving.is_empty() {
        if strict {
            bail!("no profile has {} enabled; enable it on a profile first", model.unwrap_or(""));
        }
        serving = (0..rank.len()).collect();
    }
    let fit: Vec<usize> = serving.iter().copied().filter(|&i| usable(&rank[i].1)).collect();
    // Nothing healthy serves it: still pick one that has it enabled, so the failure shows in the session.
    let mut pool = if fit.is_empty() { serving } else { fit };
    pool.sort_by(|&a, &b| {
        let (pa, pb) = (&rank[a], &rank[b]);
        used(pa.1.quota.as_ref())
            .partial_cmp(&used(pb.1.quota.as_ref()))
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(signals.load(&pa.0.id).cmp(&signals.load(&pb.0.id)))
            .then(signals.last_picked(&pa.0.id).cmp(&signals.last_picked(&pb.0.id)))
    });
    Ok(rank[pool[0]].0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::profiles::QuotaWindow;
    use std::collections::HashMap;

    fn profile(id: &str, models: &[&str]) -> Profile {
        let raw = format!(r#"{{"profiles": [{{"id": "{id}", "runtime": "claude", "home": "/h/{id}", "models": {}}}]}}"#, serde_json::to_string(models).unwrap());
        crate::config::parse_config(&serde_json::from_str(&raw).unwrap(), std::path::Path::new("/")).unwrap().profiles.remove(0)
    }
    fn ok(state: &str) -> Option<ProfileCheck> {
        Some(ProfileCheck { state: state.into(), detail: String::new(), models: None, checked_at: 0 })
    }
    fn quota(used: f64) -> Option<ProfileQuota> {
        Some(ProfileQuota { state: "ok".into(), windows: vec![QuotaWindow { label: "5 小时".into(), used_percent: used, resets_at: None }], detail: None, checked_at: 0 })
    }
    struct Signals {
        health: HashMap<String, ProfileHealth>,
        load: HashMap<String, usize>,
        picked: HashMap<String, i64>,
    }
    impl PoolSignals for Signals {
        fn health(&self, id: &str) -> ProfileHealth {
            self.health[id].clone()
        }
        fn load(&self, id: &str) -> usize {
            *self.load.get(id).unwrap_or(&0)
        }
        fn last_picked(&self, id: &str) -> i64 {
            *self.picked.get(id).unwrap_or(&0)
        }
    }

    #[test]
    fn the_pool_skips_broken_spent_and_unfit_profiles_then_prefers_headroom_then_fewer_sessions() {
        let (a, b, c, d) = (profile("a", &["m1"]), profile("b", &["m1"]), profile("c", &["m1", "m2"]), profile("d", &["m2"]));
        let mut health = HashMap::from([
            ("a".to_string(), ProfileHealth { check: ok("failed"), quota: quota(0.0), ..Default::default() }),
            ("b".to_string(), ProfileHealth { check: ok("ok"), quota: quota(100.0), ..Default::default() }),
            ("c".to_string(), ProfileHealth { check: ok("ok"), quota: quota(60.0), ..Default::default() }),
            ("d".to_string(), ProfileHealth { check: ok("ok"), quota: quota(20.0), ..Default::default() }),
        ]);
        let signals = |health: &HashMap<String, ProfileHealth>, load: &[(&str, usize)], picked: &[(&str, i64)]| Signals {
            health: health.clone(),
            load: load.iter().map(|(k, v)| (k.to_string(), *v)).collect(),
            picked: picked.iter().map(|(k, v)| (k.to_string(), *v)).collect(),
        };
        let all = [&a, &b, &c, &d];
        assert_eq!(pick_profile(&all, Some("m1"), &signals(&health, &[], &[]), true).unwrap().id, "c", "a failed, b spent, d lacks m1");
        assert_eq!(pick_profile(&all, Some("m2"), &signals(&health, &[], &[]), true).unwrap().id, "d", "most headroom");
        assert_eq!(pick_profile(&all, None, &signals(&health, &[], &[]), true).unwrap().id, "d");
        health.insert("c".into(), ProfileHealth { check: ok("ok"), quota: quota(20.0), ..Default::default() });
        assert_eq!(pick_profile(&[&c, &d], None, &signals(&health, &[("d", 2), ("c", 1)], &[]), true).unwrap().id, "c", "fewer sessions");
        assert_eq!(pick_profile(&[&c, &d], None, &signals(&health, &[], &[("c", 5), ("d", 1)]), true).unwrap().id, "d", "least recently picked");
        assert_eq!(pick_profile(&[&a], Some("m1"), &signals(&health, &[], &[]), true).unwrap().id, "a", "nothing healthy: still one, so the failure shows");
        let refused = pick_profile(&[&a, &b], Some("m2"), &signals(&health, &[], &[]), true).unwrap_err().to_string();
        assert!(refused.contains("no profile has m2 enabled"), "a model enabled nowhere is refused");
        assert_eq!(pick_profile(&[&a, &c], Some("m9"), &signals(&health, &[], &[]), false).unwrap().id, "c", "a connect's binding still runs on its healthy profiles");
    }

    #[test]
    fn a_model_is_served_however_a_profile_spells_it() {
        let (direct, router) = (profile("direct", &["gpt-6-astra"]), profile("router", &["openai/gpt-6-astra"]));
        let health = HashMap::from([
            ("direct".to_string(), ProfileHealth { check: ok("ok"), quota: quota(100.0), ..Default::default() }),
            ("router".to_string(), ProfileHealth { check: ok("ok"), quota: quota(10.0), ..Default::default() }),
        ]);
        let signals = Signals { health, load: HashMap::new(), picked: HashMap::new() };
        let picked = pick_profile(&[&direct, &router], Some("gpt-6-astra"), &signals, true).unwrap();
        assert_eq!(picked.id, "router", "the direct account is spent; the router's spelling is the same model");
        assert_eq!(picked.spelling("gpt-6-astra"), Some("openai/gpt-6-astra"), "and it runs as the router spells it");
        assert_eq!(direct.spelling("openai/gpt-6-astra"), Some("gpt-6-astra"));
        assert!(!serves(&direct, Some("gpt-6")));
    }
}
