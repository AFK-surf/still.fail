//! How a runtime account reaches its models. A profile picks one access kind; the station derives the environment (and,
//! for Codex, provider config overrides) from it, so nobody has to know which variables each runtime reads. "env" keeps
//! the raw form for anything else. (src/profiles.ts)

use std::collections::BTreeMap;

use ember_shapes::{AccessKind, RuntimeKind};

/// The access kinds each runtime can use.
pub fn access_kinds(runtime: RuntimeKind) -> &'static [AccessKind] {
    match runtime {
        RuntimeKind::Claude => &[AccessKind::Subscription, AccessKind::OpencodeGo, AccessKind::AnthropicApi, AccessKind::Env],
        RuntimeKind::Codex => &[AccessKind::Subscription, AccessKind::OpencodeGo, AccessKind::Env],
    }
}

/// Access kinds that authenticate with a key the profile stores.
pub fn keyed(kind: AccessKind) -> bool {
    matches!(kind, AccessKind::OpencodeGo | AccessKind::AnthropicApi)
}

pub const OPENCODE: &str = "https://opencode.ai/zen/go";

/// Environment an access kind needs. `{route}` is expanded per session later.
pub fn access_env(runtime: RuntimeKind, kind: AccessKind, key: &str, model: Option<&str>) -> BTreeMap<String, String> {
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
        (AccessKind::OpencodeGo, RuntimeKind::Codex) => vec![("OPENCODE_GO_KEY", key.to_string()), ("OPENCODE_SESSION", "ember-{route}".to_string())],
        (AccessKind::AnthropicApi, _) => vec![("ANTHROPIC_API_KEY", key.to_string())],
        _ => vec![],
    };
    pairs.into_iter().map(|(k, v)| (k.to_string(), v)).collect()
}

/// Codex features ember's agents have no use for, off for every profile: apps starts the ChatGPT connectors' MCP server
/// (over the network, about 1.5 s of a new thread's start); recommended_plugins fetches and lists plugins that are not
/// installed (several KB of prompt, and a request a turn can wait on).
const CODEX_FEATURES_OFF: [(&str, &str); 2] = [("features.apps", "false"), ("features.recommended_plugins", "false")];

/// Codex reads its model provider from config; the station passes it as `-c` overrides when it starts the app-server,
/// so config.toml stays the user's. Values are TOML.
pub fn codex_overrides(kind: AccessKind, model: Option<&str>) -> BTreeMap<String, String> {
    let mut out: BTreeMap<String, String> = CODEX_FEATURES_OFF.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
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
        _ => runtime.into_iter().collect(),
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
    fn opencode_go_sets_up_each_runtime_its_own_way() {
        let claude = access_env(RuntimeKind::Claude, AccessKind::OpencodeGo, "k", None);
        assert_eq!(claude["ANTHROPIC_BASE_URL"], OPENCODE);
        assert_eq!(claude["ANTHROPIC_SMALL_FAST_MODEL"], "deepseek-flash");
        let codex = access_env(RuntimeKind::Codex, AccessKind::OpencodeGo, "k", None);
        assert_eq!(codex["OPENCODE_SESSION"], "ember-{route}");
        let overrides = codex_overrides(AccessKind::OpencodeGo, Some("m"));
        assert_eq!(overrides["model"], "\"m\"");
        assert_eq!(codex_overrides(AccessKind::Subscription, None).len(), 2);
    }
}
