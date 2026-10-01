// Bug reports about still.fail itself (docs/feedback.md). A station's agent, asked by the person it works for, sends
// one to POST /v1/feedback signed with the station's key like its traces (tag "station-feedback-v1"); a signed-in
// account may send one with its access token. Either host takes them (app.still.fail and the test channel's
// app.youdid.wtf): each is marked with the channel it came on. They wait in the admin's console (/v1/admin/feedback),
// where the team picks them up.
import { readText, reply } from "./auth";
import { betaOrigin, header } from "./compat";
import type { Env } from "./env";
import { stationSender } from "./tracing";
import type { FeedbackArea } from "./types";

const MAX_BYTES = 128 * 1024;
export const FEEDBACK_LIMITS = { title: 200, body: 20_000, reporter: 200, context: 8_000, logs: 64 * 1024, key: 64 };
export const FEEDBACK_AREAS: readonly FeedbackArea[] = ["station", "web", "android", "desktop", "slack", "cloud", "unknown"];

/** A report as the Directory keeps it: checked and cut to size here. */
export interface FeedbackInput {
  key: string;
  channel: "stable" | "beta";
  sender: string;
  station: string | null;
  account: string | null;
  title: string;
  body: string;
  area: FeedbackArea;
  reporter: string;
  context: string | null;
  logs: string | null;
}

const text = (value: unknown, max: number): string => (typeof value === "string" ? value.trim().slice(0, max) : "");

/** POST /v1/feedback: { key, title, body, area?, reporter?, context?, logs? } → { id, number, duplicate }. */
export async function receiveFeedback(request: Request, env: Env, account: string | null): Promise<Response> {
  if (request.headers.get("content-type")?.split(";")[0] !== "application/json") return reply({ error: "invalid_request" }, 400);
  let raw: string;
  try {
    raw = await readText(request, MAX_BYTES);
  } catch {
    return reply({ error: "too_large" }, 413);
  }
  const station = account ? null : await stationSender(request, env, raw, "station-feedback-v1");
  if (!account && !station) return reply({ error: "invalid_session" }, 401);
  let value: Record<string, unknown>;
  try {
    value = JSON.parse(raw) as Record<string, unknown>;
    if (typeof value !== "object" || value === null || Array.isArray(value)) throw new Error("shape");
  } catch {
    return reply({ error: "invalid_request" }, 400);
  }
  const key = text(value.key, FEEDBACK_LIMITS.key);
  const title = text(value.title, FEEDBACK_LIMITS.title);
  const body = text(value.body, FEEDBACK_LIMITS.body);
  if (!/^[A-Za-z0-9_.:-]{1,64}$/.test(key) || !title || !body) return reply({ error: "invalid_request" }, 400);
  const area = FEEDBACK_AREAS.includes(value.area as FeedbackArea) ? (value.area as FeedbackArea) : "unknown";
  const context = value.context && typeof value.context === "object" && !Array.isArray(value.context) ? JSON.stringify(value.context).slice(0, FEEDBACK_LIMITS.context) : null;
  const logs = text(value.logs, FEEDBACK_LIMITS.logs) || null;
  const beta = new URL(request.url).origin === betaOrigin(env) || header(request, "channel") === "beta";
  const input: FeedbackInput = {
    key,
    channel: beta ? "beta" : "stable",
    sender: account ? `account:${account}` : `station:${station}`,
    station,
    account,
    title,
    body,
    area,
    reporter: text(value.reporter, FEEDBACK_LIMITS.reporter),
    context,
    logs,
  };
  const made = await env.DIRECTORY.getByName("primary").addFeedback(input);
  if (!made) return reply({ error: "rate_limited" }, 429, { "retry-after": "3600" });
  return reply(made, made.duplicate ? 200 : 201);
}
