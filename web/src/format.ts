// Names of the choices forms offer: fixed words, not worked out from any data (what data says in words is the core's,
// client/core/src/present.rs and format.rs).
import type { AccessKind, ConnectMode, RuntimeKind } from "./api.ts";

export const MODE: Record<ConnectMode, { label: string; description: string }> = {
  "multi-session": { label: "每个 thread 一个会话", description: "在 thread 里 @ 它就开一个新会话，thread 里的后续消息都进这个会话。" },
  "single-session": { label: "所有 thread 共用一个会话", description: "它看到的所有 thread 进同一个会话，适合一个长期值守的助手。" },
};

export const RUNTIME_LABEL: Record<RuntimeKind, string> = { claude: "Claude Code", codex: "Codex" };

export const ACCESS: Record<AccessKind, { label: string; description: string }> = {
  "subscription": { label: "订阅账号", description: "在服务器上登录 Claude 或 ChatGPT 订阅，用订阅额度运行。" },
  "opencode-go": { label: "OpenCode Go", description: "用 OpenCode Go 套餐的 key，模型由 OpenCode Go 提供。" },
  "anthropic-api": { label: "Anthropic API", description: "用 Anthropic API key，按量计费。" },
  "env": { label: "自定义环境变量", description: "手动填写运行时需要的环境变量。" },
};

export const ACCESS_KINDS: Record<RuntimeKind, AccessKind[]> = {
  claude: ["subscription", "opencode-go", "anthropic-api", "env"],
  codex: ["subscription", "opencode-go", "env"],
};

export const KEYED = new Set<AccessKind>(["opencode-go", "anthropic-api"]);
