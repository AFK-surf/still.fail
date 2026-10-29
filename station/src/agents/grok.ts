// Grok Build driver: one `grok agent stdio` per session, spoken to in ACP (acp.ts) with one ACP session in it.
//
// Behaviour pinned against Grok Build 1.0 (docs/grok.md), beside what ACP says:
// - `session/load` takes up a persisted session (its directory under the home's sessions/, one directory per working
//   directory);
// - the prompt's answer carries the turn's usage in its `_meta`;
// - what comes in while a turn runs goes into it with `x.ai/interject` (at the next safe point: after the tool call it
//   is in), not as a prompt of its own;
// - a subagent is a session of its own in the process, said spawned and finished in Grok Build's own notifications;
// - the model and effort are flags of the process, the station's instructions `_meta.rules`; `--always-approve` runs
//   without approvals, as the other runtimes do.
import { appendFileSync, mkdirSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { peerHttpBase } from "../tools/http.ts";
import { AcpDriver, AcpSession, STEER, type AcpStart } from "./acp.ts";
import { LiveFromAcp } from "./live.ts";
import type { Events } from "./own-process.ts";
import { expandRoute, profileEnv, profileModel } from "./profiles.ts";
import { cleanEnv, failureOf, uuid, type FailureReason, type LiveEvent, type OpenOptions } from "./runtime.ts";

type Json = any;

/// Inherited variables that would let a session use another account, home or configuration than its profile's.
const SCRUBBED = ["XAI_API_KEY", "GROK_CODE_XAI_API_KEY", "GROK_HOME", "GROK_AUTH", "GROK_AUTH_PATH", "GROK_AUTH_PROVIDER_COMMAND", "GROK_CONFIG", "GROK_CONFIG_PATH", "GROK_DEFAULT_MODEL", "GROK_AGENT_SECRET", "GROK_SANDBOX"];
/// Grok Build's home in a profile's (GROK_HOME): its sign-in, configuration and sessions apart from the other runtimes'
/// a profile may run (Codex's sessions/ is in the profile's home itself).
export const grokHome = (home: string) => join(home, "grok");
/// Where in its home Grok Build keeps its sessions; in a session's directory, its transcript, and what the station
/// writes beside it of each turn's usage (Grok Build keeps none: the prompt's answer says it).
export const SESSIONS = "sessions";
export const TRANSCRIPT = "chat_history.jsonl";
export const USAGE = "stillfail-usage.jsonl";

/// Reasoning effort in the station's terms (pool.ts) as Grok Build takes it (low, medium, high, xhigh; max where the
/// model has it).
export const grokEffort = (effort: string | undefined) => (effort && ["low", "medium", "high", "xhigh", "max"].includes(effort) ? effort : undefined);

/// Grok Build keeps a session at <grok home>/sessions/<working directory, escaped>/<id>/: the directory, if it is there
/// (`home`: the profile's).
export function sessionDir(home: string, sessionId: string): string | null {
  if (sessionId === "") return null;
  const root = join(grokHome(home), SESSIONS);
  let dirs: string[];
  try {
    dirs = readdirSync(root);
  } catch {
    return null;
  }
  for (const d of dirs) {
    try {
      if (statSync(join(root, d, sessionId)).isDirectory()) return join(root, d, sessionId);
    } catch {}
  }
  return null;
}

/// What failed a turn, from what Grok Build said of it (SuperGrok's sign-in is a subscription's).
export const classifyFailure = (text: string): FailureReason => failureOf(text, { auth: ["access token", "subscription"] });

/// A turn's usage as the station keeps it beside the transcript (counted by usage/counter.ts): its input less what was
/// read from the cache or written to it, as the others count.
export function usageLine(answer: Json, time: number, window: number | null = null): string | null {
  const meta = answer?.result?._meta;
  const u = meta?.usage;
  if (u === null || typeof u !== "object") return null;
  const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
  const read = n(u.cachedReadTokens);
  const written = n(u.cacheCreationTokens);
  const usage = { input: Math.max(0, n(u.inputTokens) - read - written), cacheRead: read, cacheWrite: written, output: n(u.outputTokens), calls: n(u.modelCalls) };
  const id = typeof meta.promptId === "string" ? meta.promptId : typeof meta.requestId === "string" ? meta.requestId : null;
  if (id === null) return null;
  // What the context holds at the turn's end (its last call's), and how much it can.
  const context = n(meta.totalTokens);
  return JSON.stringify({ type: "stillfail/usage", time, id, model: typeof meta.modelId === "string" ? meta.modelId : null, usage, context, window });
}

export type GrokDriverOptions = {
  /// The station's data directory: runners live in <data>/run/runners.
  data: string;
  /// The CLI, by name on the agent's PATH or a path.
  command?: string;
};

/// The station's instructions as Grok Build is given them: with how its tools are reached there (an MCP server's tools
/// are behind Grok Build's search_tool and use_tool), so that no turn spends a step looking for them.
export const grokRules = (instructions: string) =>
  `${instructions}${instructions === "" ? "" : "\n\n"}The station's tools (chat_post, chat_state and the others named in these instructions) are the stillfail MCP server's: call one with use_tool and its full name, stillfail__<tool> (for example stillfail__chat_post), without searching for it first.`;

/// A subagent's step as the parent session shows it: its own id, marked a subagent's, under the call that spawned it.
function underParent(event: LiveEvent, child: string, parent: string | undefined): LiveEvent {
  if (event.kind === "phase" || event.kind === "tasks" || event.kind === "plan") return event;
  const id = `sub:${child}:${event.id}`;
  if (event.kind !== "start") return { ...event, id };
  return { ...event, id, subagent: true, ...(parent !== undefined ? { parent } : {}) };
}

/// The process's arguments: no approvals, its own process (not a shared leader), the model and effort chosen.
export function grokArgs(model: string | undefined, effort: string | undefined): string[] {
  const args = ["agent", "--always-approve", "--no-leader"];
  if (model !== undefined) args.push("--model", model);
  const e = grokEffort(effort);
  if (e !== undefined) args.push("--reasoning-effort", e);
  args.push("stdio");
  return args;
}

/// Its environment: the profile's home as Grok Build's, its key where it has one; no updating itself, no telemetry.
export function grokEnv(options: OpenOptions): Record<string, string> {
  const env: Record<string, string> = { ...cleanEnv(SCRUBBED), ...expandRoute(profileEnv(options.profile, "grok"), options.route) };
  env.GROK_HOME = grokHome(options.profile.home);
  env.GROK_DISABLE_AUTOUPDATER = "1";
  env.GROK_TELEMETRY_ENABLED ??= "0";
  env.GROK_TELEMETRY_TRACE_UPLOAD ??= "0";
  // Not the person's Claude Code or Cursor setup (their hooks, MCP servers, rules, skills): the station's agents run
  // with the profile's and the station's, as Claude Code runs with its profile's home here.
  for (const vendor of ["CLAUDE", "CURSOR"]) for (const cell of ["SKILLS", "RULES", "AGENTS", "MCPS", "HOOKS", "SESSIONS"]) env[`GROK_${vendor}_${cell}_ENABLED`] = "false";
  env.STILLFAIL_PEER_HTTP = peerHttpBase(options.mcpUrl);
  return env;
}

export class GrokDriver extends AcpDriver<GrokSession> {
  private readonly command: string;

  constructor(options: GrokDriverOptions) {
    super(options.data);
    this.command = options.command ?? "grok";
  }

  runtime(): "grok" {
    return "grok";
  }

  protected session(options: OpenOptions, events: Events) {
    return new GrokSession(this, events, options);
  }

  protected starting(options: OpenOptions): AcpStart {
    const home = options.profile.home;
    mkdirSync(grokHome(home), { recursive: true });
    if (options.resume !== undefined && sessionDir(home, options.resume) === null) throw new Error(`no Grok Build session ${options.resume}`);
    const model = options.model ?? profileModel(options.profile);
    // The station's instructions after Grok Build's own, for the session opened or loaded.
    return { command: this.command, args: grokArgs(model, options.effort), env: grokEnv(options), meta: { rules: grokRules(options.instructions) } };
  }
}

export class GrokSession extends AcpSession {
  /// The profile's home (its sessions are in grokHome of it).
  private readonly home: string;
  /// What its model's context can hold (as session/new or session/load said), by model.
  private windows = new Map<string, number>();
  /// Its subagents' sessions (Grok Build says them as it spawns them): their steps, under the call that spawned them.
  private children = new Map<string, { live: LiveFromAcp; parent: string | undefined }>();

  constructor(driver: GrokDriver, events: Events, options: OpenOptions) {
    super(driver, events);
    this.home = options.profile.home;
    this.model = options.model ?? profileModel(options.profile) ?? null;
  }

  protected classify(text: string) {
    return classifyFailure(text);
  }

  /// The models Grok Build said it has: which is current, and what each one's context holds.
  opened(result: Json) {
    super.opened(result);
    const models = result?.models;
    if (typeof models?.currentModelId === "string") this.model = models.currentModelId;
    for (const m of Array.isArray(models?.availableModels) ? models.availableModels : []) {
      const size = m?._meta?.totalContextTokens;
      if (typeof m?.modelId === "string" && typeof size === "number") this.windows.set(m.modelId, size);
    }
  }

  /// A subagent's session says its own steps: under the call that spawned it.
  protected other(from: string, update: Json) {
    const child = this.children.get(from);
    if (child) for (const event of child.live.feed(update)) this.events({ type: "live", event: underParent(event, from, child.parent) });
  }

  protected notified(message: Json) {
    if (message.method !== "_x.ai/session_notification" || message.params?.sessionId !== this.sessionId) return;
    const update = message.params?.update;
    const child = typeof update?.child_session_id === "string" ? update.child_session_id : null;
    if (child === null) return;
    if (update?.sessionUpdate === "subagent_spawned") this.children.set(child, { live: new LiveFromAcp(), parent: this.live.openCall() });
    if (update?.sessionUpdate === "subagent_finished") this.endChild(child);
  }

  protected ending(_id: string, answer: Json) {
    this.keepUsage(answer);
    for (const child of [...this.children.keys()]) this.endChild(child);
  }

  /// A subagent done: what it still had open ends.
  private endChild(id: string) {
    const child = this.children.get(id);
    if (!child) return;
    this.children.delete(id);
    for (const event of child.live.ended()) this.events({ type: "live", event: underParent(event, id, child.parent) });
  }

  /// The turn's usage, beside its transcript (none for a turn that made no call).
  private keepUsage(answer: Json) {
    const model = typeof answer?.result?._meta?.modelId === "string" ? answer.result._meta.modelId : this.model;
    const line = usageLine(answer, wall.now(), model !== null ? (this.windows.get(model) ?? null) : null);
    const dir = sessionDir(this.home, this.sessionId);
    if (line === null || dir === null) return;
    try {
      appendFileSync(join(dir, USAGE), `${line}\n`);
    } catch (e) {
      log.warn("agents::grok", "a turn's usage was not kept", { session: this.sessionId, error: (e as Error).message });
    }
  }

  /// Into the running turn, read at its next safe point (after the tool call it is in). Not when nothing runs: Grok
  /// Build would make it a turn of its own, which the station starts itself.
  async steer(text: string) {
    if (this.turn.closed || !this.turn.busy || this.turn.aborting) return false;
    try {
      const answer = await this.request(`${STEER}${uuid()}`, "_x.ai/interject", { sessionId: this.sessionId, text });
      return answer?.result?.status === "queued" || answer?.result !== undefined;
    } catch (e) {
      log.warn("agents::grok", "a message could not go into the running turn", { session: this.sessionId, error: (e as Error).message });
      return false;
    }
  }

  /// Between turns, another model or effort is set in the running process (session/set_config_option), read from its
  /// next turn on.
  retune(options: OpenOptions) {
    if (this.turn.closed || this.turn.busy || this.sessionId === "") return false;
    const model = options.model ?? profileModel(options.profile);
    const effort = grokEffort(options.effort);
    if (model === undefined && effort === undefined) return false;
    if (model !== undefined) {
      this.send("session/set_config_option", { sessionId: this.sessionId, configId: "model", value: model });
      this.model = model;
    }
    if (effort !== undefined) this.send("session/set_config_option", { sessionId: this.sessionId, configId: "reasoning_effort", value: effort });
    return true;
  }
}
