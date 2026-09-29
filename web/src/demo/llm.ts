// The model behind the demo's agent, reached from this browser with the visitor's own key (keys.ts): the Anthropic
// Messages API, as OpenCode Go serves it (what Claude Code uses there too). OpenCode Go does not let a page call it
// across origins, so the site forwards /_llm/opencode/* to it unchanged (site/serve.mjs, and the site's host).
import type { UserProfile } from "./keys.ts";

const BASE: Record<UserProfile["kind"], string> = { "opencode-go": "/_llm/opencode" };
/** OpenCode Go routes a request by its session (the station sends `x-opencode-session` too: profiles.rs). */
const SESSION = `ember-demo-${Math.random().toString(36).slice(2, 10)}`;

export interface ToolUse { type: "tool_use"; id: string; name: string; input: Record<string, unknown> }
export type Block = { type: "text"; text: string } | ToolUse | { type: "tool_result"; tool_use_id: string; content: string; is_error?: boolean };
export interface Turn { role: "user" | "assistant"; content: string | Block[] }
export interface Tool { name: string; description: string; input_schema: object }

export class LlmError extends Error {
  constructor(message: string, readonly auth: boolean) {
    super(message);
  }
}

/** One request: the model's answer (its text and the tools it asks for), or an LlmError saying why not. */
export async function ask(profile: UserProfile, model: string, system: string, messages: Turn[], tools: Tool[], maxTokens = 2048): Promise<{ content: Block[]; stop: string }> {
  let response: Response;
  try {
    response = await fetch(`${BASE[profile.kind]}/v1/messages`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-api-key": profile.key, "anthropic-version": "2023-06-01", "x-opencode-session": SESSION },
      body: JSON.stringify({ model, max_tokens: maxTokens, system, messages, ...(tools.length ? { tools } : {}) }),
    });
  } catch (e) {
    throw new LlmError(`连不上模型服务（${(e as Error).message}）`, false);
  }
  const body = await response.json().catch(() => null) as { content?: Block[]; stop_reason?: string; error?: { message?: string } } | null;
  if (!response.ok) {
    throw new LlmError(`${body?.error?.message ?? `模型服务返回 ${response.status}`}`, response.status === 401 || response.status === 403);
  }
  return { content: body?.content ?? [], stop: body?.stop_reason ?? "end_turn" };
}

/** Whether a key works: the smallest request there is. */
export async function check(profile: UserProfile): Promise<void> {
  await ask(profile, profile.models[0]!, "Reply with one word.", [{ role: "user", content: "hi" }], [], 1);
}
