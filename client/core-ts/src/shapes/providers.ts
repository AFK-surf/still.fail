// The API providers a profile can reach with a key (client/shapes/src/providers.rs): where each one is, and which
// protocols it speaks there. The station sets the runtimes up from the same list.

export type Protocol = "chat_completions" | "responses" | "anthropic";

export type Source = {
  id: string;
  name: string;
  group: "labs" | "gateways" | "hosted" | "local";
  mark: string | null;
  chat?: string;
  responses?: string;
  anthropic?: string;
  decision?: string;
  endpointRequired?: boolean;
  protocols?: Protocol[];
  keyOptional?: boolean;
  auth: "api-key" | "bearer" | "both";
  sessionHeader?: boolean;
  legacy?: string;
};

export const GROUPS = ["labs", "gateways", "hosted", "local"] as const;

/// In the order they are offered.
export const SOURCES: Source[] = [
 {
  "id": "openai",
  "name": "OpenAI",
  "group": "labs",
  "mark": "openai",
  "responses": "https://api.openai.com/v1",
  "auth": "bearer"
 },
 {
  "id": "anthropic",
  "name": "Anthropic",
  "group": "labs",
  "mark": "anthropic",
  "anthropic": "https://api.anthropic.com",
  "auth": "api-key",
  "legacy": "anthropic-api"
 },
 {
  "id": "google",
  "name": "Google Gemini",
  "group": "labs",
  "mark": "gemini",
  "chat": "https://generativelanguage.googleapis.com/v1beta/openai",
  "auth": "bearer"
 },
 {
  "id": "xai",
  "name": "xAI",
  "group": "labs",
  "mark": "xai",
  "responses": "https://api.x.ai/v1",
  "auth": "bearer"
 },
 {
  "id": "mistral",
  "name": "Mistral",
  "group": "labs",
  "mark": "mistral",
  "chat": "https://api.mistral.ai/v1",
  "auth": "bearer"
 },
 {
  "id": "deepseek",
  "name": "DeepSeek",
  "group": "labs",
  "mark": "deepseek",
  "chat": "https://api.deepseek.com",
  "auth": "bearer"
 },
 {
  "id": "qwen",
  "name": "Qwen",
  "group": "labs",
  "mark": "qwen",
  "chat": "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1",
  "auth": "bearer"
 },
 {
  "id": "moonshotai",
  "name": "Kimi",
  "group": "labs",
  "mark": "kimi",
  "chat": "https://api.moonshot.ai/v1",
  "auth": "bearer"
 },
 {
  "id": "zai",
  "name": "Z.ai",
  "group": "labs",
  "mark": "zhipu",
  "chat": "https://api.z.ai/api/coding/paas/v4",
  "auth": "bearer"
 },
 {
  "id": "minimax",
  "name": "MiniMax",
  "group": "labs",
  "mark": "minimax",
  "anthropic": "https://api.minimax.io/anthropic",
  "auth": "bearer"
 },
 {
  "id": "xiaomi",
  "name": "Xiaomi MiMo",
  "group": "labs",
  "mark": "xiaomi",
  "chat": "https://api.xiaomimimo.com/v1",
  "auth": "bearer"
 },
 {
  "id": "ant-ling",
  "name": "Ant Ling",
  "group": "labs",
  "mark": "ant-ling",
  "chat": "https://api.ant-ling.com/v1",
  "auth": "bearer"
 },
 {
  "id": "jev",
  "name": "Jev",
  "group": "labs",
  "mark": null,
  "decision": "https://api.typesafe.ai/v1",
  "auth": "bearer"
 },
 {
  "id": "qwen-cn",
  "name": "Qwen (China)",
  "group": "labs",
  "mark": "qwen",
  "chat": "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1",
  "auth": "bearer"
 },
 {
  "id": "moonshotai-cn",
  "name": "Kimi (China)",
  "group": "labs",
  "mark": "kimi",
  "chat": "https://api.moonshot.cn/v1",
  "auth": "bearer"
 },
 {
  "id": "zai-coding-cn",
  "name": "Z.ai Coding (China)",
  "group": "labs",
  "mark": "zhipu",
  "chat": "https://open.bigmodel.cn/api/coding/paas/v4",
  "auth": "bearer"
 },
 {
  "id": "minimax-cn",
  "name": "MiniMax (China)",
  "group": "labs",
  "mark": "minimax",
  "anthropic": "https://api.minimaxi.com/anthropic",
  "auth": "bearer"
 },
 {
  "id": "openrouter",
  "name": "OpenRouter",
  "group": "gateways",
  "mark": "openrouter",
  "chat": "https://openrouter.ai/api/v1",
  "anthropic": "https://openrouter.ai/api",
  "auth": "bearer"
 },
 {
  "id": "vercel-ai-gateway",
  "name": "Vercel AI Gateway",
  "group": "gateways",
  "mark": "vercel",
  "anthropic": "https://ai-gateway.vercel.sh",
  "auth": "bearer"
 },
 {
  "id": "opencode",
  "name": "OpenCode Zen",
  "group": "gateways",
  "mark": "opencode",
  "chat": "https://opencode.ai/zen/v1",
  "responses": "https://opencode.ai/zen/v1",
  "anthropic": "https://opencode.ai/zen",
  "auth": "api-key",
  "sessionHeader": true
 },
 {
  "id": "opencode-go",
  "name": "OpenCode Go",
  "group": "gateways",
  "mark": "opencode",
  "chat": "https://opencode.ai/zen/go/v1",
  "responses": "https://opencode.ai/zen/go/v1",
  "anthropic": "https://opencode.ai/zen/go",
  "auth": "api-key",
  "sessionHeader": true,
  "legacy": "opencode-go"
 },
 {
  "id": "cloudflare-ai-gateway",
  "name": "Cloudflare AI Gateway",
  "group": "gateways",
  "mark": "cloudflare",
  "endpointRequired": true,
  "protocols": [
   "chat_completions",
   "responses",
   "anthropic"
  ],
  "auth": "both"
 },
 {
  "id": "azure-openai",
  "name": "Azure OpenAI",
  "group": "hosted",
  "mark": "azure",
  "endpointRequired": true,
  "protocols": [
   "responses"
  ],
  "auth": "bearer"
 },
 {
  "id": "groq",
  "name": "Groq",
  "group": "hosted",
  "mark": "groq",
  "chat": "https://api.groq.com/openai/v1",
  "auth": "bearer"
 },
 {
  "id": "together",
  "name": "Together AI",
  "group": "hosted",
  "mark": "together",
  "chat": "https://api.together.ai/v1",
  "auth": "bearer"
 },
 {
  "id": "fireworks",
  "name": "Fireworks",
  "group": "hosted",
  "mark": "fireworks",
  "chat": "https://api.fireworks.ai/inference/v1",
  "anthropic": "https://api.fireworks.ai/inference",
  "auth": "bearer"
 },
 {
  "id": "cerebras",
  "name": "Cerebras",
  "group": "hosted",
  "mark": "cerebras",
  "chat": "https://api.cerebras.ai/v1",
  "auth": "bearer"
 },
 {
  "id": "huggingface",
  "name": "Hugging Face",
  "group": "hosted",
  "mark": "huggingface",
  "chat": "https://router.huggingface.co/v1",
  "auth": "bearer"
 },
 {
  "id": "nvidia",
  "name": "NVIDIA",
  "group": "hosted",
  "mark": "nvidia",
  "chat": "https://integrate.api.nvidia.com/v1",
  "auth": "bearer"
 },
 {
  "id": "baseten",
  "name": "Baseten",
  "group": "hosted",
  "mark": "baseten",
  "chat": "https://inference.baseten.co/v1",
  "auth": "bearer"
 },
 {
  "id": "cloudflare-workers-ai",
  "name": "Cloudflare Workers AI",
  "group": "hosted",
  "mark": "cloudflare",
  "endpointRequired": true,
  "protocols": [
   "chat_completions"
  ],
  "auth": "bearer"
 },
 {
  "id": "ollama",
  "name": "Ollama",
  "group": "local",
  "mark": null,
  "endpointRequired": true,
  "protocols": [
   "chat_completions"
  ],
  "keyOptional": true,
  "auth": "bearer"
 },
 {
  "id": "custom",
  "name": "Custom",
  "group": "local",
  "mark": null,
  "endpointRequired": true,
  "protocols": [
   "chat_completions",
   "responses",
   "anthropic"
  ],
  "keyOptional": true,
  "auth": "both"
 }
];

export function find(id: string): Source | null {
  return SOURCES.find((s) => s.id === id) ?? null;
}

/// The source an access kind that came before this list is.
export function ofKind(kind: string): Source | null {
  return SOURCES.find((s) => s.legacy === kind) ?? null;
}

export const REGIONS: [string, string][] = [
  ["qwen", "qwen-cn"],
  ["moonshotai", "moonshotai-cn"],
  ["zai", "zai-coding-cn"],
  ["minimax", "minimax-cn"],
];

export function chinaOf(id: string): string | null {
  return REGIONS.find(([base]) => base === id)?.[1] ?? null;
}

export function isChinaVariant(id: string): boolean {
  return REGIONS.some(([, cn]) => cn === id);
}

export function example(id: string): string | null {
  const examples: Record<string, string> = {
    "cloudflare-workers-ai": "https://api.cloudflare.com/client/v4/accounts/<account>/ai/v1",
    "cloudflare-ai-gateway": "https://gateway.ai.cloudflare.com/v1/<account>/<gateway>",
    "azure-openai": "https://<resource>.openai.azure.com/openai/v1",
    ollama: "https://ollama.example.com/v1",
    custom: "https://api.example.com/v1",
  };
  return examples[id] ?? null;
}

/// An address as it is kept: trimmed, without a trailing slash; none unless it is an http(s) address.
export function cleanEndpoint(text: string): string | null {
  const t = text.trim().replace(/\/+$/, "");
  const rest = t.startsWith("https://") ? t.slice(8) : t.startsWith("http://") ? t.slice(7) : null;
  return rest !== null && rest !== "" && !/\s/.test(rest) ? t : null;
}

export type Endpoints = { chat: string | null; responses: string | null; anthropic: string | null; decision: string | null };

/// The endpoints of a source; for one at the person's own address, derived from it and the protocol chosen.
export function endpoints(source: Source, endpoint: string | null | undefined, protocol: string | null | undefined): Endpoints | null {
  if (!source.endpointRequired) return { chat: source.chat ?? null, responses: source.responses ?? null, anthropic: source.anthropic ?? null, decision: source.decision ?? null };
  if (endpoint === null || endpoint === undefined) return null;
  const base = cleanEndpoint(endpoint);
  if (base === null) return null;
  const chosen = protocol === "chat_completions" || protocol === "responses" || protocol === "anthropic" ? protocol : null;
  if (chosen && !(source.protocols ?? []).includes(chosen)) return null;
  let at: Endpoints;
  const none: Endpoints = { chat: null, responses: null, anthropic: null, decision: null };
  if (source.id === "cloudflare-ai-gateway") {
    const suffix = ["/compat", "/openai", "/anthropic"].find((s) => base.endsWith(s));
    const root = suffix ? base.slice(0, -suffix.length) : base;
    at = { chat: `${root}/compat`, responses: `${root}/openai`, anthropic: `${root}/anthropic`, decision: null };
  } else if (source.id === "azure-openai") at = { ...none, responses: base };
  else if (source.id === "cloudflare-workers-ai" || source.id === "ollama") at = { ...none, chat: base };
  else if (chosen === "chat_completions") at = { ...none, chat: base };
  else if (chosen === "responses") at = { ...none, responses: base };
  else if (chosen === "anthropic") at = { ...none, anthropic: base };
  else at = { anthropic: base.endsWith("/v1") ? base.slice(0, -3) : null, chat: base, responses: base, decision: null };
  if (chosen && source.id === "cloudflare-ai-gateway") {
    if (chosen !== "chat_completions") at.chat = null;
    if (chosen !== "responses") at.responses = null;
    if (chosen !== "anthropic") at.anthropic = null;
  }
  return at;
}

export type Uses = { claude: boolean; codex: boolean; decision: boolean };

export function uses(e: Endpoints): Uses {
  return { claude: e.anthropic !== null, codex: e.responses !== null, decision: e.chat !== null || e.decision !== null };
}

export function runtimes(u: Uses): string[] {
  return [u.claude ? "claude" : null, u.codex ? "codex" : null].filter((r): r is string => r !== null);
}
