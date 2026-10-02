//! How a runtime account reaches its models. A profile picks one access kind; the station derives the environment (and,
//! for Codex, provider config overrides) from it, so nobody has to know which variables each runtime reads. "env" keeps
//! the raw form for anything else.

use std::collections::BTreeMap;

use stillfail_shapes::providers::{self, ClaudeAuth, Source};
use stillfail_shapes::{AccessKind, RuntimeKind};

use crate::lang::{spoken, t};

/// The access kinds each runtime can use.
pub fn access_kinds(runtime: RuntimeKind) -> &'static [AccessKind] {
    match runtime {
        RuntimeKind::Claude => &[AccessKind::Subscription, AccessKind::OpencodeGo, AccessKind::AnthropicApi, AccessKind::ApiProvider, AccessKind::Env],
        RuntimeKind::Codex => &[AccessKind::Subscription, AccessKind::OpencodeGo, AccessKind::ApiProvider, AccessKind::Env],
    }
}

/// Access kinds that authenticate with a key the profile stores.
pub fn keyed(kind: AccessKind) -> bool {
    matches!(kind, AccessKind::OpencodeGo | AccessKind::AnthropicApi | AccessKind::ApiProvider)
}

/// Whether a profile on this access must have a key: every keyed one but a provider that works without (a server of
/// one's own).
pub fn needs_key(kind: AccessKind, provider: Option<&str>) -> bool {
    keyed(kind) && !(kind == AccessKind::ApiProvider && provider.and_then(providers::find).is_some_and(|s| s.key_optional))
}

/// The source of an API-provider profile and where it speaks, when the profile names a known provider (and, where it
/// needs one, a usable address).
pub fn api_source(provider: Option<&str>, endpoint: Option<&str>) -> Option<(&'static Source, providers::Endpoints)> {
    let source = providers::find(provider?)?;
    Some((source, providers::endpoints(source, endpoint)?))
}

/// The key the runtimes are given where the profile has none (a provider that works without): they ask for one.
const NO_KEY: &str = "none";

pub const OPENCODE: &str = "https://opencode.ai/zen/go";

/// Environment an access kind needs. `{route}` is expanded per session later.
pub fn access_env(runtime: RuntimeKind, kind: AccessKind, key: &str, model: Option<&str>, provider: Option<&str>, endpoint: Option<&str>) -> BTreeMap<String, String> {
    let pairs: Vec<(&str, String)> = match (kind, runtime) {
        (AccessKind::OpencodeGo, RuntimeKind::Claude) => {
            let small = model.unwrap_or("deepseek-flash").to_string();
            vec![
                ("ANTHROPIC_BASE_URL", OPENCODE.to_string()),
                ("ANTHROPIC_API_KEY", key.to_string()),
                ("ANTHROPIC_CUSTOM_HEADERS", "x-opencode-session: {route}".to_string()),
                // Claude Code's background calls use a small model; point it at one the provider has.
                ("ANTHROPIC_DEFAULT_HAIKU_MODEL", small.clone()),
                ("ANTHROPIC_SMALL_FAST_MODEL", small),
                ("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1".to_string()),
            ]
        }
        // The provider's session key keeps the name of before the rename: its sessions go on under it.
        (AccessKind::OpencodeGo, RuntimeKind::Codex) => vec![("OPENCODE_GO_KEY", key.to_string()), ("OPENCODE_SESSION", "ember-{route}".to_string())],
        (AccessKind::AnthropicApi, _) => vec![("ANTHROPIC_API_KEY", key.to_string())],
        (AccessKind::ApiProvider, runtime) => api_env(runtime, key, model, provider, endpoint),
        _ => vec![],
    };
    pairs.into_iter().map(|(k, v)| (k.to_string(), v)).collect()
}

/// The variable a Codex provider config reads an API provider's key from.
const CODEX_KEY: &str = "EMBER_API_KEY";

/// A provider's key for a runtime, the way OpenCode Go is set up, from where the provider speaks: Claude Code reads its
/// Anthropic endpoint, Codex its Responses endpoint (the provider's config is `codex_overrides`).
fn api_env(runtime: RuntimeKind, key: &str, model: Option<&str>, provider: Option<&str>, endpoint: Option<&str>) -> Vec<(&'static str, String)> {
    let Some((source, at)) = api_source(provider, endpoint) else { return vec![] };
    let key_or_none = if key.is_empty() { NO_KEY.to_string() } else { key.to_string() };
    match runtime {
        RuntimeKind::Claude => {
            let Some(base) = at.anthropic else { return vec![] };
            let mut env = vec![("ANTHROPIC_BASE_URL", base)];
            match source.auth {
                ClaudeAuth::ApiKey => env.push(("ANTHROPIC_API_KEY", key_or_none)),
                // The key is a bearer token; a key variable left unset is not asked about.
                ClaudeAuth::Bearer => env.extend([("ANTHROPIC_AUTH_TOKEN", key_or_none), ("ANTHROPIC_API_KEY", String::new())]),
                ClaudeAuth::Both => env.extend([("ANTHROPIC_AUTH_TOKEN", key_or_none.clone()), ("ANTHROPIC_API_KEY", key_or_none)]),
            }
            if source.session_header {
                env.push(("ANTHROPIC_CUSTOM_HEADERS", "x-opencode-session: {route}".to_string()));
            }
            // Claude Code's background calls use a small model; where the profile names one, it is that.
            if let Some(small) = model {
                env.extend([("ANTHROPIC_DEFAULT_HAIKU_MODEL", small.to_string()), ("ANTHROPIC_SMALL_FAST_MODEL", small.to_string())]);
            }
            env.push(("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1".to_string()));
            env
        }
        RuntimeKind::Codex => {
            if at.responses.is_none() {
                return vec![];
            }
            let mut env = vec![(CODEX_KEY, key_or_none)];
            if source.session_header {
                env.push(("OPENCODE_SESSION", "ember-{route}".to_string()));
            }
            env
        }
    }
}

/// Codex features the station's agents have no use for, off for every profile: apps starts the ChatGPT connectors' MCP server
/// (over the network, about 1.5 s of a new thread's start); recommended_plugins fetches and lists plugins that are not
/// installed (several KB of prompt, and a request a turn can wait on).
const CODEX_FEATURES_OFF: [(&str, &str); 2] = [("features.apps", "false"), ("features.recommended_plugins", "false")];

/// Codex reads its model provider from config; the station passes it as `-c` overrides when it starts the app-server,
/// so config.toml stays the user's. Values are TOML.
pub fn codex_overrides(kind: AccessKind, model: Option<&str>, provider: Option<&str>, endpoint: Option<&str>) -> BTreeMap<String, String> {
    let mut out: BTreeMap<String, String> = CODEX_FEATURES_OFF.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
    if kind == AccessKind::ApiProvider {
        // Codex keeps its own names for the providers it has built in (openai among them): this one is just `api`.
        let Some((source, at)) = api_source(provider, endpoint) else { return out };
        let Some(base) = at.responses else { return out };
        out.insert("model_provider".into(), "\"api\"".into());
        if let Some(model) = model {
            out.insert("model".into(), serde_json::to_string(model).unwrap_or_default());
        }
        out.insert("model_providers.api.name".into(), serde_json::to_string(source.name).unwrap_or_default());
        out.insert("model_providers.api.base_url".into(), serde_json::to_string(&base).unwrap_or_default());
        out.insert("model_providers.api.env_key".into(), format!("\"{CODEX_KEY}\""));
        out.insert("model_providers.api.wire_api".into(), "\"responses\"".into());
        if source.session_header {
            out.insert("model_providers.api.env_http_headers".into(), "{\"x-opencode-session\"=\"OPENCODE_SESSION\"}".into());
        }
        return out;
    }
    if kind != AccessKind::OpencodeGo {
        return out;
    }
    out.insert("model_provider".into(), "\"opencode-go\"".into());
    if let Some(model) = model {
        out.insert("model".into(), serde_json::to_string(model).unwrap_or_default());
    }
    out.insert("model_providers.opencode-go.name".into(), "\"OpenCode Go\"".into());
    out.insert("model_providers.opencode-go.base_url".into(), format!("\"{OPENCODE}/v1\""));
    out.insert("model_providers.opencode-go.env_key".into(), "\"OPENCODE_GO_KEY\"".into());
    out.insert("model_providers.opencode-go.wire_api".into(), "\"responses\"".into());
    out.insert("model_providers.opencode-go.env_http_headers".into(), "{\"x-opencode-session\"=\"OPENCODE_SESSION\"}".into());
    out
}

/// The command to sign a subscription profile in, run on the station's machine.
pub fn login_command(runtime: RuntimeKind, home: &str) -> String {
    match runtime {
        RuntimeKind::Claude => format!("CLAUDE_CONFIG_DIR={home} claude auth login"),
        RuntimeKind::Codex => format!("CODEX_HOME={home} codex login"),
    }
}

/// The runtimes an account runs, set up by the station for each: an OpenCode Go key both, an Anthropic key Claude Code;
/// a subscription (and custom variables) the runtime it was made for.
pub fn runtimes_of(kind: AccessKind, runtime: Option<RuntimeKind>) -> Vec<RuntimeKind> {
    match kind {
        AccessKind::OpencodeGo => vec![RuntimeKind::Claude, RuntimeKind::Codex],
        AccessKind::AnthropicApi => vec![RuntimeKind::Claude],
        // Of a provider it follows from where it speaks (a chat-completions-only one runs neither: it serves the
        // automatic decisions); `runtimes_for` has the provider.
        AccessKind::ApiProvider => vec![],
        _ => runtime.into_iter().collect(),
    }
}

/// `runtimes_of` for an access as a config has it (with its provider and address).
pub fn runtimes_for(access: Option<&crate::config::RawProfileAccess>, runtime: Option<RuntimeKind>) -> Vec<RuntimeKind> {
    let kind = access.map(|a| a.kind).unwrap_or(AccessKind::Env);
    match access.filter(|_| kind == AccessKind::ApiProvider) {
        Some(a) => api_source(a.provider.as_deref(), a.endpoint.as_deref()).map(|(_, at)| providers::uses(&at).runtimes()).unwrap_or_default(),
        None => runtimes_of(kind, runtime),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_key_runs_every_runtime_it_can_and_a_subscription_its_own() {
        assert_eq!(runtimes_of(AccessKind::OpencodeGo, None), vec![RuntimeKind::Claude, RuntimeKind::Codex]);
        assert_eq!(runtimes_of(AccessKind::AnthropicApi, Some(RuntimeKind::Codex)), vec![RuntimeKind::Claude]);
        assert_eq!(runtimes_of(AccessKind::Subscription, Some(RuntimeKind::Codex)), vec![RuntimeKind::Codex]);
        assert_eq!(runtimes_of(AccessKind::Env, None), Vec::<RuntimeKind>::new());
    }

    #[test]
    fn a_provider_is_set_up_for_each_runtime_from_where_it_speaks() {
        // Claude Code reads its Anthropic endpoint (a bearer token where the provider asks for one), Codex its Responses one.
        let router = access_env(RuntimeKind::Claude, AccessKind::ApiProvider, "k", Some("small"), Some("openrouter"), None);
        assert_eq!((router["ANTHROPIC_BASE_URL"].as_str(), router["ANTHROPIC_AUTH_TOKEN"].as_str(), router["ANTHROPIC_API_KEY"].as_str()), ("https://openrouter.ai/api", "k", "")); 
        assert_eq!(router["ANTHROPIC_SMALL_FAST_MODEL"], "small");
        assert!(access_env(RuntimeKind::Codex, AccessKind::ApiProvider, "k", None, Some("openrouter"), None).is_empty(), "no Responses endpoint");
        let openai = codex_overrides(AccessKind::ApiProvider, Some("gpt-x"), Some("openai"), None);
        assert_eq!(openai["model_providers.api.base_url"], "\"https://api.openai.com/v1\"");
        assert_eq!((openai["model_provider"].as_str(), openai["model_providers.api.wire_api"].as_str(), openai["model"].as_str()), ("\"api\"", "\"responses\"", "\"gpt-x\""));
        assert!(!openai.contains_key("model_providers.api.env_http_headers"));
        assert_eq!(access_env(RuntimeKind::Codex, AccessKind::ApiProvider, "k", None, Some("openai"), None)["EMBER_API_KEY"], "k");
        // OpenCode's gateways ask for a session on every request, whichever runtime.
        let zen = codex_overrides(AccessKind::ApiProvider, None, Some("opencode"), None);
        assert_eq!(zen["model_providers.api.env_http_headers"], "{\"x-opencode-session\"=\"OPENCODE_SESSION\"}");
        // Azure's address is the person's.
        let azure = codex_overrides(AccessKind::ApiProvider, None, Some("azure-openai"), Some("https://r.openai.azure.com/openai/v1/"));
        assert_eq!(azure["model_providers.api.base_url"], "\"https://r.openai.azure.com/openai/v1\"");
        // A chat-completions-only provider sets up neither runtime.
        assert!(access_env(RuntimeKind::Claude, AccessKind::ApiProvider, "k", None, Some("groq"), None).is_empty());
        assert_eq!(codex_overrides(AccessKind::ApiProvider, None, Some("groq"), None).len(), 2);
        // A server of one's own needs no key: the runtimes are given a placeholder.
        assert_eq!(access_env(RuntimeKind::Codex, AccessKind::ApiProvider, "", None, Some("custom"), Some("http://localhost:4000/v1"))["EMBER_API_KEY"], "none");
        assert!(!needs_key(AccessKind::ApiProvider, Some("custom")) && needs_key(AccessKind::ApiProvider, Some("groq")) && needs_key(AccessKind::OpencodeGo, None));
    }

    #[test]
    fn a_config_from_before_providers_loads_as_it_was() {
        let raw: crate::config::RawConfig = serde_json::from_value(serde_json::json!({ "profiles": [
            { "id": "go", "home": "homes/go", "access": { "kind": "opencode-go", "key": "k" } },
            { "id": "an", "home": "homes/an", "access": { "kind": "anthropic-api", "key": "k" } },
            { "id": "e", "home": "homes/e", "runtime": "codex", "access": { "kind": "env" } },
            { "id": "p", "home": "homes/p", "access": { "kind": "api-provider", "provider": "deepseek", "key": "k" } },
        ] })).unwrap();
        let config = crate::config::parse_config(&raw, std::path::Path::new("/nonexistent-profiles-test")).unwrap();
        let runtimes: Vec<_> = config.profiles.iter().map(|p| p.runtimes.len()).collect();
        assert_eq!(runtimes, [2, 1, 1, 0]);
        assert_eq!(config.profiles[3].provider.as_deref(), Some("deepseek"));
        let raw: crate::config::RawConfig = serde_json::from_value(serde_json::json!({ "profiles": [{ "id": "p", "home": "homes/p", "access": { "kind": "api-provider", "provider": "nope", "key": "k" } }] })).unwrap();
        assert!(crate::config::parse_config(&raw, std::path::Path::new("/x")).is_err(), "a provider the list does not have");
    }

    #[test]
    fn opencode_go_sets_up_each_runtime_its_own_way() {
        let claude = access_env(RuntimeKind::Claude, AccessKind::OpencodeGo, "k", None, None, None);
        assert_eq!(claude["ANTHROPIC_BASE_URL"], OPENCODE);
        assert_eq!(claude["ANTHROPIC_SMALL_FAST_MODEL"], "deepseek-flash");
        let codex = access_env(RuntimeKind::Codex, AccessKind::OpencodeGo, "k", None, None, None);
        assert_eq!(codex["OPENCODE_SESSION"], "ember-{route}");
        let overrides = codex_overrides(AccessKind::OpencodeGo, Some("m"), None, None);
        assert_eq!(overrides["model"], "\"m\"");
        assert_eq!(codex_overrides(AccessKind::Subscription, None, None, None).len(), 2);
    }
}

/// Whether a profile works, and what models it offers (as the station keeps it, JSON the same as the TS station's).
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProfileCheck {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub decision: Option<crate::decision::profiles::Capability>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model_efforts: Option<stillfail_shapes::reasoning::Catalog>,
    /// ok: usable; login: needs a subscription sign-in; failed: the key or login was rejected; unknown.
    pub state: String,
    pub detail: String,
    /// Models the account can use, when the provider lists them.
    pub models: Option<Vec<String>>,
    pub checked_at: i64,
}

/// A window of an allowance.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QuotaWindow {
    pub label: String,
    /// 0–100.
    pub used_percent: f64,
    /// Epoch ms; none when the provider does not say.
    pub resets_at: Option<i64>,
}

/// How much of a profile's allowance is used, where the provider says.
#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProfileQuota {
    /// ok: windows filled; unsupported: nothing to show for this kind; unavailable: could not ask; blocked: the
    /// provider refuses the account (suspended, on hold, deactivated).
    pub state: String,
    pub windows: Vec<QuotaWindow>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub credits: Option<QuotaCredits>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reset_count: Option<u64>,
    pub detail: Option<String>,
    pub checked_at: i64,
}

#[derive(serde::Serialize, serde::Deserialize, Debug, Clone, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QuotaCredits {
    pub has_credits: bool,
    pub unlimited: bool,
    pub balance: Option<String>,
}

// ── checks ─────────────────────────────────────────────────────────────────

/// What a profile check is given: the account and where it lives.
pub struct CheckOptions<'a> {
    pub runtime: RuntimeKind,
    pub kind: AccessKind,
    pub key: &'a str,
    /// Of an API-provider profile: which provider and where it is (the address is the person's own for some).
    pub provider: Option<&'a str>,
    pub endpoint: Option<&'a str>,
    pub home: &'a std::path::Path,
    pub env: &'a crate::machine_logins::Env,
    /// On the machine's own login (machine_logins.rs).
    pub machine: bool,
}

fn check(state: &str, detail: impl Into<String>, models: Option<Vec<String>>) -> ProfileCheck {
    ProfileCheck { decision: None, model_efforts: None, state: state.into(), detail: detail.into(), models, checked_at: crate::store::now_ms() }
}

fn http() -> reqwest::Client {
    reqwest::Client::builder().timeout(std::time::Duration::from_secs(15)).build().unwrap_or_default()
}

/// The ids of a `/v1/models` answer.
async fn model_ids(response: reqwest::Response) -> anyhow::Result<Vec<String>> {
    let body: serde_json::Value = response.json().await?;
    Ok(body["data"].as_array().map(|a| a.iter().filter_map(|m| m["id"].as_str().map(String::from)).collect()).unwrap_or_default())
}

/// The models a Claude subscription's OAuth token may use; None when Anthropic does not say.
async fn claude_models(token: &str) -> Option<Vec<String>> {
    let response = http()
        .get("https://api.anthropic.com/v1/models?limit=100")
        .bearer_auth(token)
        .header("anthropic-version", "2023-06-01")
        .header("anthropic-beta", "oauth-2025-04-20")
        .send()
        .await
        .ok()?;
    if !response.status().is_success() {
        return None;
    }
    model_ids(response).await.ok()
}

/// Runs a runtime's own status command; its output, or why it could not run.
async fn status_of(command: &str, args: &[&str], env: &crate::machine_logins::Env) -> anyhow::Result<std::process::Output> {
    let run = tokio::process::Command::new(command).args(args).env_clear().envs(env).stdin(std::process::Stdio::null()).kill_on_drop(true).output();
    Ok(tokio::time::timeout(std::time::Duration::from_secs(20), run).await.map_err(|_| anyhow::anyhow!("{command} {} timed out", args.join(" ")))??)
}

/// Asks the provider or runtime whether this profile works, and what models it offers. (checkProfile)
pub async fn check_profile(o: CheckOptions<'_>) -> ProfileCheck {
    match check_inner(&o).await {
        Ok(check) => check,
        Err(e) => check("failed", t!(spoken(); "station.profile.checkError", error = e), None),
    }
}

async fn check_inner(o: &CheckOptions<'_>) -> anyhow::Result<ProfileCheck> {
    match (o.kind, o.runtime) {
        (AccessKind::OpencodeGo, _) => {
            // The model list answers any key; the usage is the key's own, so it is what tells a key that works.
            let usage = http().get(format!("{OPENCODE}/v1/usage")).bearer_auth(o.key).send().await?;
            if !usage.status().is_success() {
                return Ok(check("failed", t!(spoken(); "station.profile.keyRefused", provider = "OpenCode Go", status = usage.status().as_u16()), None));
            }
            let response = http().get(format!("{OPENCODE}/v1/models")).bearer_auth(o.key).send().await?;
            if !response.status().is_success() {
                return Ok(check("failed", t!(spoken(); "station.profile.modelsUnreadable", provider = "OpenCode Go", status = response.status().as_u16()), None));
            }
            let mut models = model_ids(response).await?;
            models.sort();
            Ok(check("ok", t!(spoken(); "station.profile.works", n = models.len()), Some(models)))
        }
        (AccessKind::AnthropicApi, _) => {
            let response = http()
                .get("https://api.anthropic.com/v1/models?limit=100")
                .header("x-api-key", o.key)
                .header("anthropic-version", "2023-06-01")
                .send()
                .await?;
            if !response.status().is_success() {
                return Ok(check("failed", t!(spoken(); "station.profile.keyRefused", provider = "Anthropic", status = response.status().as_u16()), None));
            }
            let models = model_ids(response).await?;
            Ok(check("ok", t!(spoken(); "station.profile.works", n = models.len()), Some(models)))
        }
        (AccessKind::ApiProvider, _) => {
            let Some(source) = o.provider.and_then(providers::find) else { return Ok(check("failed", t!(spoken(); "station.profile.unknownProvider"), None)) };
            let Some(at) = providers::endpoints(source, o.endpoint) else { return Ok(check("failed", t!(spoken(); "station.profile.addressNeeded"), None)) };
            check_api(source, &at, o.key).await
        }
        (AccessKind::Subscription, RuntimeKind::Claude) => {
            let mut env = o.env.clone();
            env.insert("CLAUDE_CONFIG_DIR".into(), o.home.to_string_lossy().into_owned());
            let machine_token = if o.machine { Some(crate::machine_logins::machine_claude_token(o.env).await?.0) } else { None };
            match &machine_token {
                Some(token) => {
                    env.insert("CLAUDE_CODE_OAUTH_TOKEN".into(), token.clone());
                }
                None => {
                    crate::no_keychain::take_back(o.home).await;
                    crate::no_keychain::file_credentials(&mut env);
                }
            }
            let output = status_of("claude", &["auth", "status"], &env).await?;
            // Signed out, it says so and exits 1: its answer is still the JSON on stdout.
            let stdout = String::from_utf8_lossy(&output.stdout);
            if !output.status.success() && !(output.status.code() == Some(1) && stdout.trim_start().starts_with('{')) {
                anyhow::bail!("Command failed: claude auth status\n{}", String::from_utf8_lossy(&output.stderr));
            }
            let status: serde_json::Value = serde_json::from_str(&stdout)?;
            if status["loggedIn"] != true {
                return Ok(check("login", t!(spoken(); "station.profile.signedOut"), None));
            }
            // What the subscription runs, as Anthropic lists it for the account's own token.
            let token = machine_token.or_else(|| crate::quota::claude_token(o.home));
            let models = match token {
                Some(token) => claude_models(&token).await,
                None => None,
            };
            let signed_in = t!(spoken(); "station.profile.signedIn");
            let detail: Vec<&str> = [signed_in.as_str(), status["email"].as_str().unwrap_or(""), status["subscriptionType"].as_str().unwrap_or("")].into_iter().filter(|s| !s.is_empty()).collect();
            Ok(check("ok", detail.join(&t!(spoken(); "station.list.comma")), models))
        }
        (AccessKind::Subscription, RuntimeKind::Codex) => {
            if o.machine {
                crate::machine_logins::link_codex_auth(o.home, o.env)?;
            }
            let mut env = o.env.clone();
            env.insert("CODEX_HOME".into(), o.home.to_string_lossy().into_owned());
            let output = status_of("codex", &["login", "status"], &env).await?;
            let text = format!("{}{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr)).trim().to_string();
            if text.to_lowercase().contains("not logged in") {
                return Ok(check("login", t!(spoken(); "station.profile.signedOut"), None));
            }
            if !output.status.success() {
                anyhow::bail!("Command failed: codex login status\n{text}");
            }
            Ok(check("ok", text.lines().next().map(str::to_string).unwrap_or_else(|| t!(spoken(); "station.profile.signedIn")), None))
        }
        _ => Ok(check("unknown", t!(spoken(); "station.profile.envUnchecked"), None)),
    }
}

/// The header OpenCode's gateways ask of every request: any id will do, and without one they answer 400 MissingSessionID.
pub fn opencode_session() -> (&'static str, String) {
    let mut b = [0u8; 16];
    let _ = getrandom::fill(&mut b);
    // A version 4 uuid.
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    let h = hex::encode(b);
    ("x-opencode-session", format!("{}-{}-{}-{}-{}", &h[..8], &h[8..12], &h[12..16], &h[16..20], &h[20..]))
}

/// A provider's key, asked by its model list: a refusal (401/403) is a key that does not work; a provider with no list
/// (some answer 404 there) is not held against it, its key is only unchecked.
async fn check_api(source: &Source, at: &providers::Endpoints, key: &str) -> anyhow::Result<ProfileCheck> {
    let (base, anthropic_only) = match (&at.chat, &at.responses, &at.anthropic) {
        (Some(base), _, _) | (None, Some(base), _) => (base.clone(), false),
        (None, None, Some(base)) => (format!("{base}/v1"), true),
        _ => return Ok(check("failed", t!(spoken(); "station.profile.addressNeeded"), None)),
    };
    let mut request = http().get(format!("{base}/models"));
    if !key.is_empty() {
        request = request.bearer_auth(key);
    }
    if anthropic_only {
        request = request.header("x-api-key", key).header("anthropic-version", "2023-06-01");
    }
    if source.session_header {
        let (name, value) = opencode_session();
        request = request.header(name, value);
    }
    let response = request.send().await?;
    let status = response.status();
    if status.as_u16() == 401 || status.as_u16() == 403 {
        return Ok(check("failed", t!(spoken(); "station.profile.keyRefused", provider = source.name, status = status.as_u16()), None));
    }
    if !status.is_success() {
        return Ok(check("unknown", t!(spoken(); "station.profile.noModelList", provider = source.name), None));
    }
    let mut models = model_ids(response).await?;
    models.sort();
    Ok(check("ok", t!(spoken(); "station.profile.works", n = models.len()), Some(models)))
}
