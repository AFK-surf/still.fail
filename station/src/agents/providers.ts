// The API providers a profile can reach with a key, and where each speaks which protocol (client/core-ts/src/shapes/schema.ts providers.rs:
// what the runtimes' environment is made from, so it follows the same list). Only what setting up a runtime needs:
// `find`, `endpoints`, `cleanEndpoint`, `uses`.

export type Protocol = "chat_completions" | "responses" | "anthropic";

/// How Claude Code is given the key: some endpoints read `x-api-key`, others a bearer token, a few either.
export type ClaudeAuth = "apiKey" | "bearer" | "both";

export type Source = {
  id: string;
  name: string;
  chat?: string;
  responses?: string;
  anthropic?: string;
  /// A native decision endpoint (Jev's), for the automatic decisions only.
  decision?: string;
  /// The address is the person's (cloudflare, azure, custom), not the provider's.
  endpointRequired: boolean;
  /// For one at the reader's own address: the protocols it can speak there.
  protocols: Protocol[];
  /// Works without a key (a server of one's own).
  keyOptional: boolean;
  auth: ClaudeAuth;
  /// OpenCode's gateways refuse a request without `x-opencode-session`.
  sessionHeader: boolean;
};

const source = (id: string, name: string, more: Partial<Source> = {}): Source => ({
  id,
  name,
  endpointRequired: false,
  protocols: [],
  keyOptional: false,
  auth: "bearer",
  sessionHeader: false,
  ...more,
});

const ALL: Protocol[] = ["chat_completions", "responses", "anthropic"];

/// In the order they are offered.
export const SOURCES: Source[] = [
  // Labs.
  source("openai", "OpenAI", { responses: "https://api.openai.com/v1" }),
  source("anthropic", "Anthropic", { anthropic: "https://api.anthropic.com", auth: "apiKey" }),
  source("google", "Google Gemini", { chat: "https://generativelanguage.googleapis.com/v1beta/openai" }),
  source("xai", "xAI", { responses: "https://api.x.ai/v1" }),
  source("mistral", "Mistral", { chat: "https://api.mistral.ai/v1" }),
  // China.
  source("deepseek", "DeepSeek", { chat: "https://api.deepseek.com" }),
  source("qwen", "Qwen", { chat: "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1" }),
  source("moonshotai", "Kimi", { chat: "https://api.moonshot.ai/v1" }),
  source("zai", "Z.ai", { chat: "https://api.z.ai/api/coding/paas/v4" }),
  source("minimax", "MiniMax", { anthropic: "https://api.minimax.io/anthropic" }),
  source("xiaomi", "Xiaomi MiMo", { chat: "https://api.xiaomimimo.com/v1" }),
  source("ant-ling", "Ant Ling", { chat: "https://api.ant-ling.com/v1" }),
  // Only the automatic decisions use it: it answers a question with probabilities and has no chat.
  source("jev", "Jev", { decision: "https://api.typesafe.ai/v1" }),
  source("qwen-cn", "Qwen (China)", { chat: "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1" }),
  source("moonshotai-cn", "Kimi (China)", { chat: "https://api.moonshot.cn/v1" }),
  source("zai-coding-cn", "Z.ai Coding (China)", { chat: "https://open.bigmodel.cn/api/coding/paas/v4" }),
  source("minimax-cn", "MiniMax (China)", { anthropic: "https://api.minimaxi.com/anthropic" }),
  // Gateways.
  source("openrouter", "OpenRouter", { anthropic: "https://openrouter.ai/api", chat: "https://openrouter.ai/api/v1" }),
  source("vercel-ai-gateway", "Vercel AI Gateway", { anthropic: "https://ai-gateway.vercel.sh" }),
  source("opencode", "OpenCode Zen", {
    anthropic: "https://opencode.ai/zen",
    chat: "https://opencode.ai/zen/v1",
    responses: "https://opencode.ai/zen/v1",
    auth: "apiKey",
    sessionHeader: true,
  }),
  source("opencode-go", "OpenCode Go", {
    anthropic: "https://opencode.ai/zen/go",
    chat: "https://opencode.ai/zen/go/v1",
    responses: "https://opencode.ai/zen/go/v1",
    auth: "apiKey",
    sessionHeader: true,
  }),
  source("cloudflare-ai-gateway", "Cloudflare AI Gateway", { endpointRequired: true, protocols: ALL, auth: "both" }),
  // Cloud.
  source("azure-openai", "Azure OpenAI", { endpointRequired: true, protocols: ["responses"] }),
  // Inference.
  source("groq", "Groq", { chat: "https://api.groq.com/openai/v1" }),
  source("together", "Together AI", { chat: "https://api.together.ai/v1" }),
  source("fireworks", "Fireworks", { anthropic: "https://api.fireworks.ai/inference", chat: "https://api.fireworks.ai/inference/v1" }),
  source("cerebras", "Cerebras", { chat: "https://api.cerebras.ai/v1" }),
  source("huggingface", "Hugging Face", { chat: "https://router.huggingface.co/v1" }),
  source("nvidia", "NVIDIA", { chat: "https://integrate.api.nvidia.com/v1" }),
  source("baseten", "Baseten", { chat: "https://inference.baseten.co/v1" }),
  source("cloudflare-workers-ai", "Cloudflare Workers AI", { endpointRequired: true, protocols: ["chat_completions"] }),
  // Local: at the reader's own address, which the station must be able to reach.
  source("ollama", "Ollama", { endpointRequired: true, protocols: ["chat_completions"], keyOptional: true }),
  source("custom", "Custom", { endpointRequired: true, protocols: ALL, keyOptional: true, auth: "both" }),
];

export const find = (id: string): Source | undefined => SOURCES.find((s) => s.id === id);

/// The two made before this list, as an access kind of their own (shapes `legacy`): not offered again as a provider.
export const LEGACY: Record<string, "anthropic-api" | "opencode-go"> = { anthropic: "anthropic-api", "opencode-go": "opencode-go" };

/// How the picker groups them (shapes `Group`): labs, gateways, hosted, local.
export function groupOf(id: string): "labs" | "gateways" | "hosted" | "local" {
  if (["openrouter", "vercel-ai-gateway", "opencode", "opencode-go", "cloudflare-ai-gateway"].includes(id)) return "gateways";
  if (["azure-openai", "groq", "together", "fireworks", "cerebras", "huggingface", "nvidia", "baseten", "cloudflare-workers-ai"].includes(id)) return "hosted";
  if (id === "ollama" || id === "custom") return "local";
  return "labs";
}

/// An address as it is kept: trimmed, without a trailing slash; none unless it is an http(s) address.
export function cleanEndpoint(text: string): string | undefined {
  const trimmed = text.trim().replace(/\/+$/, "");
  const rest = trimmed.startsWith("https://") ? trimmed.slice(8) : trimmed.startsWith("http://") ? trimmed.slice(7) : undefined;
  return rest !== undefined && rest !== "" && !/\s/.test(rest) ? trimmed : undefined;
}

export type Endpoints = { chat?: string; responses?: string; anthropic?: string; decision?: string };

/// The endpoints of a source; for one at the person's own address, derived from it and the protocol chosen for it (none
/// chosen: all it can speak). Undefined when the address is needed and is not a usable one.
export function endpoints(source: Source, endpoint: string | undefined, protocol: string | undefined): Endpoints | undefined {
  if (!source.endpointRequired) return { chat: source.chat, responses: source.responses, anthropic: source.anthropic, decision: source.decision };
  const base = endpoint === undefined ? undefined : cleanEndpoint(endpoint);
  if (base === undefined) return undefined;
  const chosen = ALL.find((p) => p === protocol);
  if (chosen !== undefined && !source.protocols.includes(chosen)) return undefined;
  let at: Endpoints;
  if (source.id === "cloudflare-ai-gateway") {
    // The gateway's address (…/v1/<account>/<gateway>): each protocol under its own path.
    const suffix = ["/compat", "/openai", "/anthropic"].find((s) => base.endsWith(s));
    const root = suffix ? base.slice(0, -suffix.length) : base;
    at = { chat: `${root}/compat`, responses: `${root}/openai`, anthropic: `${root}/anthropic` };
    if (chosen !== undefined) {
      if (chosen !== "chat_completions") delete at.chat;
      if (chosen !== "responses") delete at.responses;
      if (chosen !== "anthropic") delete at.anthropic;
    }
  } else if (source.id === "azure-openai") {
    at = { responses: base };
  } else if (source.id === "cloudflare-workers-ai" || source.id === "ollama") {
    at = { chat: base };
  } else if (chosen === "chat_completions") {
    at = { chat: base };
  } else if (chosen === "responses") {
    at = { responses: base };
  } else if (chosen === "anthropic") {
    at = { anthropic: base };
  } else {
    // Before the choice existed an address was taken for every protocol (Anthropic's at the root above a /v1).
    at = { anthropic: base.endsWith("/v1") ? base.slice(0, -3) : undefined, chat: base, responses: base };
  }
  return at;
}

/// The runtimes a provider's profile can run, from where it speaks: Anthropic's protocol is Claude Code's, Responses
/// Codex's.
export const runtimesOf = (at: Endpoints): ("claude" | "codex")[] => [
  ...(at.anthropic !== undefined ? (["claude"] as const) : []),
  ...(at.responses !== undefined ? (["codex"] as const) : []),
];
