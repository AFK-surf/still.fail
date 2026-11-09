// A text-only completion for a keyed DeepSeek Harness profile whose provider speaks chat completions. It uses the
// profile's own endpoint and key, and never gives the provider tools.
import { DSH_KEY, dshRoute, expandRoute, profileEnv } from "../agents/profiles.ts";
import type { RunOn } from "./accounts.ts";
import { profileFetch } from "../ops/agent-env.ts";

export type TitleCompletion = { endpoint: string; key: string; model: string; headers: Record<string, string> };

export function titleCompletion(profile: RunOn, model: string | null, session: string): TitleCompletion | null {
  if (!profile.runtimes.includes("dsh")) return null;
  const route = dshRoute(profile);
  if (!route || (route.kind === "pi" && route.api !== "openai-completions")) return null;
  const chosen = model ? (profile.spelling(model) ?? model) : profile.model ?? (route.kind === "deepseek" ? "deepseek-v4-flash" : undefined);
  if (!chosen) return null;
  const env = profileEnv(profile, "dsh");
  const key = route.kind === "deepseek" ? env.DEEPSEEK_API_KEY : env[DSH_KEY];
  const base = route.kind === "deepseek" ? "https://api.deepseek.com" : route.baseURL;
  let url: URL;
  try { url = new URL(base); } catch { return null; }
  const local = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  if (!(url.protocol === "https:" || (url.protocol === "http:" && local)) || url.username || url.password || url.search || url.hash) return null;
  const headers = route.kind === "pi" ? expandRoute(route.headers ?? {}, session) : {};
  return { endpoint: `${url.href.replace(/\/+$/, "")}/chat/completions`, key: key === "none" ? "" : key ?? "", model: chosen, headers };
}

export async function completeTitle(config: TitleCompletion, instructions: string, input: string, signal: AbortSignal): Promise<string> {
  const headers: Record<string, string> = { ...config.headers, "content-type": "application/json" };
  if (config.key !== "") headers.authorization = `Bearer ${config.key}`;
  const body = JSON.stringify({ model: config.model, stream: false, max_tokens: 128, messages: [{ role: "system", content: instructions }, { role: "user", content: input }] });
  const response = await profileFetch(config.endpoint, { method: "POST", headers, body, redirect: "manual", signal });
  if (!response.ok) throw new Error("title completion failed");
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of response.body ?? []) {
    size += chunk.length;
    if (size > 256_000) throw new Error("title completion too large");
    chunks.push(Buffer.from(chunk));
  }
  const answer = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  const text = answer?.choices?.[0]?.message?.content;
  if (typeof text !== "string" || answer?.choices?.[0]?.message?.tool_calls?.length) throw new Error("title completion missing");
  return text;
}
