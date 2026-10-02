//! The API providers a profile can reach with a key: where each one is, and which protocols it speaks there. The
//! list follows Cue's model catalog (systems/apps/salix_agent/priv/model_catalog.json, its `sources`). What a profile
//! can run follows from the protocols: an Anthropic endpoint is what Claude Code speaks, a Responses endpoint is what
//! Codex speaks, and a chat-completions endpoint is what the automatic decisions ask (decision/profiles.rs).
//!
//! The station sets the runtimes up from this (mesh/app/src/profiles.rs) and the core says what a profile can do from
//! it (client/core/src/present.rs), so the two cannot disagree.

use crate::{AccessKind, RuntimeKind};

/// How the picker groups them: Cue's groups, in its order.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Group {
    Labs,
    China,
    Gateways,
    Cloud,
    Inference,
    Local,
}

pub const GROUPS: [Group; 6] = [Group::Labs, Group::China, Group::Gateways, Group::Cloud, Group::Inference, Group::Local];

impl Group {
    pub fn id(self) -> &'static str {
        match self {
            Group::Labs => "labs",
            Group::China => "china",
            Group::Gateways => "gateways",
            Group::Cloud => "cloud",
            Group::Inference => "inference",
            Group::Local => "local",
        }
    }
}

/// The wire protocols a provider speaks; a reader's own endpoint speaks one of them.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Protocol {
    Chat,
    Responses,
    Anthropic,
}

impl Protocol {
    pub fn id(self) -> &'static str {
        match self {
            Protocol::Chat => "chat_completions",
            Protocol::Responses => "responses",
            Protocol::Anthropic => "anthropic",
        }
    }
    pub fn parse(text: &str) -> Option<Protocol> {
        [Protocol::Chat, Protocol::Responses, Protocol::Anthropic].into_iter().find(|p| p.id() == text)
    }
}

/// How Claude Code is given the key: some endpoints read `x-api-key`, others a bearer token, a few either.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClaudeAuth {
    ApiKey,
    Bearer,
    Both,
}

pub struct Source {
    pub id: &'static str,
    pub name: &'static str,
    pub group: Group,
    /// The picture of its maker the clients have (web/public/models/<mark>.svg); `opencode` is the square drawn in the
    /// clients. None: the generic plug.
    pub mark: Option<&'static str>,
    pub chat: Option<&'static str>,
    pub responses: Option<&'static str>,
    pub anthropic: Option<&'static str>,
    /// The address is the person's (cloudflare, azure, custom), not the provider's.
    pub endpoint_required: bool,
    /// For one at the reader's own address: the protocols it can speak there, one chosen when it is added (more than
    /// one, a choice).
    pub protocols: &'static [Protocol],
    /// Works without a key (a server of one's own).
    pub key_optional: bool,
    pub auth: ClaudeAuth,
    /// OpenCode's gateways refuse a request without `x-opencode-session`.
    pub session_header: bool,
    /// Made before this list, as an access kind of its own; not offered again as a provider.
    pub legacy: Option<AccessKind>,
}

const fn source(id: &'static str, name: &'static str, group: Group, mark: Option<&'static str>) -> Source {
    Source { id, name, group, mark, chat: None, responses: None, anthropic: None, endpoint_required: false, protocols: &[], key_optional: false, auth: ClaudeAuth::Bearer, session_header: false, legacy: None }
}

const ALL: &[Protocol] = &[Protocol::Chat, Protocol::Responses, Protocol::Anthropic];

/// In the order they are offered (Cue's presets: providerPresets.ts).
pub static SOURCES: &[Source] = &[
    // Labs.
    Source { responses: Some("https://api.openai.com/v1"), ..source("openai", "OpenAI", Group::Labs, Some("openai")) },
    Source { anthropic: Some("https://api.anthropic.com"), auth: ClaudeAuth::ApiKey, legacy: Some(AccessKind::AnthropicApi), ..source("anthropic", "Anthropic", Group::Labs, Some("anthropic")) },
    Source { chat: Some("https://generativelanguage.googleapis.com/v1beta/openai"), ..source("google", "Google Gemini", Group::Labs, Some("gemini")) },
    Source { responses: Some("https://api.x.ai/v1"), ..source("xai", "xAI", Group::Labs, Some("xai")) },
    Source { chat: Some("https://api.mistral.ai/v1"), ..source("mistral", "Mistral", Group::Labs, None) },
    // China.
    Source { chat: Some("https://api.deepseek.com"), ..source("deepseek", "DeepSeek", Group::China, Some("deepseek")) },
    Source { chat: Some("https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"), ..source("qwen", "Qwen", Group::China, Some("qwen")) },
    Source { chat: Some("https://api.moonshot.ai/v1"), ..source("moonshotai", "Kimi", Group::China, Some("kimi")) },
    Source { chat: Some("https://api.z.ai/api/coding/paas/v4"), ..source("zai", "Z.ai", Group::China, Some("zhipu")) },
    Source { anthropic: Some("https://api.minimax.io/anthropic"), ..source("minimax", "MiniMax", Group::China, Some("minimax")) },
    Source { chat: Some("https://api.xiaomimimo.com/v1"), ..source("xiaomi", "Xiaomi MiMo", Group::China, None) },
    Source { chat: Some("https://api.ant-ling.com/v1"), ..source("ant-ling", "Ant Ling", Group::China, None) },
    Source { chat: Some("https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"), ..source("qwen-cn", "Qwen (China)", Group::China, Some("qwen")) },
    Source { chat: Some("https://api.moonshot.cn/v1"), ..source("moonshotai-cn", "Kimi (China)", Group::China, Some("kimi")) },
    Source { chat: Some("https://open.bigmodel.cn/api/coding/paas/v4"), ..source("zai-coding-cn", "Z.ai Coding (China)", Group::China, Some("zhipu")) },
    Source { anthropic: Some("https://api.minimaxi.com/anthropic"), ..source("minimax-cn", "MiniMax (China)", Group::China, Some("minimax")) },
    // Gateways.
    Source { anthropic: Some("https://openrouter.ai/api"), chat: Some("https://openrouter.ai/api/v1"), ..source("openrouter", "OpenRouter", Group::Gateways, None) },
    Source { anthropic: Some("https://ai-gateway.vercel.sh"), ..source("vercel-ai-gateway", "Vercel AI Gateway", Group::Gateways, None) },
    Source {
        anthropic: Some("https://opencode.ai/zen"), chat: Some("https://opencode.ai/zen/v1"), responses: Some("https://opencode.ai/zen/v1"),
        auth: ClaudeAuth::ApiKey, session_header: true, ..source("opencode", "OpenCode Zen", Group::Gateways, Some("opencode"))
    },
    Source {
        anthropic: Some("https://opencode.ai/zen/go"), chat: Some("https://opencode.ai/zen/go/v1"), responses: Some("https://opencode.ai/zen/go/v1"),
        auth: ClaudeAuth::ApiKey, session_header: true, legacy: Some(AccessKind::OpencodeGo), ..source("opencode-go", "OpenCode Go", Group::Gateways, Some("opencode"))
    },
    Source { endpoint_required: true, protocols: ALL, auth: ClaudeAuth::Both, ..source("cloudflare-ai-gateway", "Cloudflare AI Gateway", Group::Gateways, None) },
    // Cloud.
    Source { endpoint_required: true, protocols: &[Protocol::Responses], ..source("azure-openai", "Azure OpenAI", Group::Cloud, None) },
    // Inference.
    Source { chat: Some("https://api.groq.com/openai/v1"), ..source("groq", "Groq", Group::Inference, None) },
    Source { chat: Some("https://api.together.ai/v1"), ..source("together", "Together AI", Group::Inference, None) },
    Source { anthropic: Some("https://api.fireworks.ai/inference"), chat: Some("https://api.fireworks.ai/inference/v1"), ..source("fireworks", "Fireworks", Group::Inference, None) },
    Source { chat: Some("https://api.cerebras.ai/v1"), ..source("cerebras", "Cerebras", Group::Inference, None) },
    Source { chat: Some("https://router.huggingface.co/v1"), ..source("huggingface", "Hugging Face", Group::Inference, None) },
    Source { chat: Some("https://integrate.api.nvidia.com/v1"), ..source("nvidia", "NVIDIA", Group::Inference, None) },
    Source { chat: Some("https://inference.baseten.co/v1"), ..source("baseten", "Baseten", Group::Inference, None) },
    Source { endpoint_required: true, protocols: &[Protocol::Chat], ..source("cloudflare-workers-ai", "Cloudflare Workers AI", Group::Inference, None) },
    // Local: at the reader's own address, which the station must be able to reach.
    Source { endpoint_required: true, protocols: &[Protocol::Chat], key_optional: true, ..source("ollama", "Ollama", Group::Local, None) },
    Source { endpoint_required: true, protocols: ALL, key_optional: true, auth: ClaudeAuth::Both, ..source("custom", "Custom", Group::Local, None) },
];

pub fn find(id: &str) -> Option<&'static Source> {
    SOURCES.iter().find(|s| s.id == id)
}

/// The source an access kind that came before this list is.
pub fn of_kind(kind: AccessKind) -> Option<&'static Source> {
    SOURCES.iter().find(|s| s.legacy == Some(kind))
}

/// An example of the address a provider at the reader's own is given.
pub fn example(id: &str) -> Option<&'static str> {
    match id {
        "cloudflare-workers-ai" => Some("https://api.cloudflare.com/client/v4/accounts/<account>/ai/v1"),
        "cloudflare-ai-gateway" => Some("https://gateway.ai.cloudflare.com/v1/<account>/<gateway>"),
        "azure-openai" => Some("https://<resource>.openai.azure.com/openai/v1"),
        "ollama" => Some("https://ollama.example.com/v1"),
        "custom" => Some("https://api.example.com/v1"),
        _ => None,
    }
}

/// An address as it is kept: trimmed, without a trailing slash; none unless it is an http(s) address.
pub fn clean_endpoint(text: &str) -> Option<String> {
    let text = text.trim().trim_end_matches('/');
    let rest = text.strip_prefix("https://").or_else(|| text.strip_prefix("http://"))?;
    (!rest.is_empty() && !rest.contains(char::is_whitespace)).then(|| text.to_string())
}

/// Where a source speaks each protocol.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Endpoints {
    pub chat: Option<String>,
    pub responses: Option<String>,
    pub anthropic: Option<String>,
}

/// The endpoints of a source; for one at the person's own address, derived from it and the protocol chosen for it
/// (none chosen: all it can speak, as profiles made before the choice have them). None when the address is needed
/// and is not a usable one.
pub fn endpoints(source: &Source, endpoint: Option<&str>, protocol: Option<&str>) -> Option<Endpoints> {
    if !source.endpoint_required {
        let own = |v: Option<&str>| v.map(String::from);
        return Some(Endpoints { chat: own(source.chat), responses: own(source.responses), anthropic: own(source.anthropic) });
    }
    let base = clean_endpoint(endpoint?)?;
    let chosen = protocol.and_then(Protocol::parse);
    if chosen.is_some_and(|p| !source.protocols.contains(&p)) {
        return None;
    }
    let mut at = match source.id {
        // The gateway's address (…/v1/<account>/<gateway>): each protocol under its own path.
        "cloudflare-ai-gateway" => {
            let root = ["/compat", "/openai", "/anthropic"].iter().find_map(|s| base.strip_suffix(s)).unwrap_or(&base).to_string();
            Endpoints { chat: Some(format!("{root}/compat")), responses: Some(format!("{root}/openai")), anthropic: Some(format!("{root}/anthropic")) }
        }
        // The resource's v1 address (https://<resource>.openai.azure.com/openai/v1): the Responses API.
        "azure-openai" => Endpoints { responses: Some(base), ..Default::default() },
        // The account's OpenAI-compatible address (…/accounts/<id>/ai/v1), and a local server's: chat completions.
        "cloudflare-workers-ai" | "ollama" => Endpoints { chat: Some(base), ..Default::default() },
        // Any server: one protocol at the address given. Before the choice existed it was taken for every protocol
        // (Anthropic's at the root above a /v1).
        _ => match chosen {
            Some(Protocol::Chat) => Endpoints { chat: Some(base), ..Default::default() },
            Some(Protocol::Responses) => Endpoints { responses: Some(base), ..Default::default() },
            Some(Protocol::Anthropic) => Endpoints { anthropic: Some(base), ..Default::default() },
            None => Endpoints { anthropic: base.strip_suffix("/v1").map(String::from), chat: Some(base.clone()), responses: Some(base) },
        },
    };
    if let (Some(p), true) = (chosen, source.id == "cloudflare-ai-gateway") {
        if p != Protocol::Chat { at.chat = None }
        if p != Protocol::Responses { at.responses = None }
        if p != Protocol::Anthropic { at.anthropic = None }
    }
    Some(at)
}

/// What a profile can do, from where its provider speaks.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Uses {
    pub claude: bool,
    pub codex: bool,
    /// The automatic decisions: a chat-completions endpoint to ask for probabilities.
    pub decision: bool,
}

pub fn uses(endpoints: &Endpoints) -> Uses {
    Uses { claude: endpoints.anthropic.is_some(), codex: endpoints.responses.is_some(), decision: endpoints.chat.is_some() }
}

impl Uses {
    pub fn runtimes(self) -> Vec<RuntimeKind> {
        [(self.claude, RuntimeKind::Claude), (self.codex, RuntimeKind::Codex)].into_iter().filter(|(on, _)| *on).map(|(_, r)| r).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn uses_of(id: &str, endpoint: Option<&str>) -> Uses {
        uses(&endpoints(find(id).unwrap(), endpoint, None).unwrap())
    }

    #[test]
    fn what_a_provider_runs_follows_its_protocols() {
        let u = uses_of("openai", None);
        assert_eq!((u.claude, u.codex, u.decision), (false, true, false));
        let u = uses_of("deepseek", None);
        assert_eq!((u.claude, u.codex, u.decision), (false, false, true));
        let u = uses_of("openrouter", None);
        assert_eq!((u.claude, u.codex, u.decision), (true, false, true));
        let u = uses_of("opencode", None);
        assert_eq!((u.claude, u.codex, u.decision), (true, true, true));
        assert_eq!(uses_of("minimax", None).runtimes(), vec![RuntimeKind::Claude]);
    }

    #[test]
    fn an_address_of_the_persons_own_is_needed_and_shapes_the_endpoints() {
        assert!(endpoints(find("azure-openai").unwrap(), None, None).is_none());
        assert!(endpoints(find("azure-openai").unwrap(), Some("not a url"), None).is_none());
        let gateway = endpoints(find("cloudflare-ai-gateway").unwrap(), Some(" https://gateway.ai.cloudflare.com/v1/a/b/compat/ "), None).unwrap();
        assert_eq!(gateway.responses.as_deref(), Some("https://gateway.ai.cloudflare.com/v1/a/b/openai"));
        assert_eq!(gateway.anthropic.as_deref(), Some("https://gateway.ai.cloudflare.com/v1/a/b/anthropic"));
        let custom = endpoints(find("custom").unwrap(), Some("http://127.0.0.1:4000/v1"), None).unwrap();
        assert_eq!(custom.anthropic.as_deref(), Some("http://127.0.0.1:4000"));
        assert_eq!(endpoints(find("custom").unwrap(), Some("http://127.0.0.1:4000"), None).unwrap().anthropic, None);
        // One protocol chosen: only that one.
        let own = |p| uses(&endpoints(find("custom").unwrap(), Some("http://h/v1"), Some(p)).unwrap());
        assert_eq!((own("chat_completions").decision, own("chat_completions").codex, own("chat_completions").claude), (true, false, false));
        assert_eq!((own("responses").codex, own("responses").decision), (true, false));
        assert_eq!(own("anthropic").runtimes(), vec![RuntimeKind::Claude]);
        assert!(endpoints(find("azure-openai").unwrap(), Some("https://a.b/v1"), Some("anthropic")).is_none(), "a protocol it does not speak");
        let gateway = endpoints(find("cloudflare-ai-gateway").unwrap(), Some("https://g/v1/a/b"), Some("responses")).unwrap();
        assert_eq!((gateway.chat, gateway.responses.is_some(), gateway.anthropic), (None, true, None));
        assert_eq!(uses_of("cloudflare-workers-ai", Some("https://api.cloudflare.com/client/v4/accounts/x/ai/v1")).runtimes(), vec![]);
        assert_eq!(uses_of("ollama", Some("https://ollama.example.com/v1")).decision, true);
    }

    #[test]
    fn the_kinds_that_came_before_are_in_the_list() {
        assert_eq!(of_kind(AccessKind::OpencodeGo).unwrap().id, "opencode-go");
        assert_eq!(of_kind(AccessKind::AnthropicApi).unwrap().id, "anthropic");
        assert!(of_kind(AccessKind::Env).is_none());
        let mut ids: Vec<_> = SOURCES.iter().map(|s| s.id).collect();
        ids.sort();
        ids.dedup();
        assert_eq!(ids.len(), SOURCES.len());
    }
}
