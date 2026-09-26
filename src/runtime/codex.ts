// Codex driver: one shared `codex app-server` per profile, one thread per session.
//
// Pinned by spikes (spike/README.md):
// - a thread adds <1MB to its app-server, so sessions share one process;
// - per-session settings (the MCP endpoint and token) travel in the
//   thread/start|resume `config`, not the process environment;
// - threads need sandbox "danger-full-access" with approvalPolicy "never",
//   or MCP tool calls are refused.
import { mkdirSync } from "node:fs";
import { expandRoute, type Profile } from "../config.ts";
import { log } from "../log.ts";
import { codexOverrides } from "../profiles.ts";
import { spawnGroup, type GroupProcess, type ProcessRegistry } from "./process.ts";
import type { AgentDriver, AgentSession, FailureReason, LiveEvent, LivePhase, LiveStepKind, OpenOptions, SessionEvents, TurnOutcome } from "./types.ts";

const SCRUBBED = ["OPENAI_API_KEY", "CODEX_HOME"];

interface ThreadHandler {
  notify(method: string, params: Record<string, any>): void;
  hostExited(reason: string): void;
}

export function classifyCodexError(info: unknown): FailureReason {
  const code = typeof info === "string" ? info : info && typeof info === "object" ? Object.keys(info)[0] : undefined;
  if (code === "unauthorized") return "auth";
  if (code === "usageLimitExceeded" || code === "rateLimitExceeded" || code === "serverOverloaded") return "rate_limit";
  return "model";
}

/** One app-server process and its JSON-RPC connection. */
class Host {
  readonly #proc: GroupProcess;
  readonly #pending = new Map<number, { resolve(v: any): void; reject(e: Error): void }>();
  readonly threads = new Map<string, ThreadHandler>();
  #nextId = 1;
  alive = true;
  readonly ready: Promise<void>;
  /** What the process was started with; a profile edit that changes it needs a new process. */
  readonly signature: string;

  constructor(profile: Profile, command: string, registry: ProcessRegistry, onExit: () => void) {
    mkdirSync(profile.home, { recursive: true });
    const env: NodeJS.ProcessEnv = { ...process.env };
    for (const name of SCRUBBED) delete env[name];
    Object.assign(env, expandRoute(profile.envs.codex ?? {}, profile.id), { CODEX_HOME: profile.home });
    const overrides = Object.entries(codexOverrides(profile.access.kind, profile.model)).flatMap(([k, v]) => ["-c", `${k}=${v}`]);
    this.signature = hostSignature(profile);
    this.#proc = spawnGroup({
      command, args: ["app-server", ...overrides, "--listen", "stdio://"], cwd: profile.home, env,
      runtime: "codex", label: `codex app-server ${profile.id}`, registry,
      onLine: (line) => this.#onLine(line),
    });
    void this.#proc.exited.then((code) => {
      this.alive = false;
      const reason = `codex app-server exited (${code})`;
      for (const pending of this.#pending.values()) pending.reject(new Error(reason));
      this.#pending.clear();
      for (const thread of this.threads.values()) thread.hostExited(reason);
      this.threads.clear();
      onExit();
    });
    this.ready = this.#initialize();
  }

  async #initialize(): Promise<void> {
    await this.request("initialize", { clientInfo: { name: "ember", version: "0" }, capabilities: { experimentalApi: true } });
    this.#proc.write(JSON.stringify({ method: "initialized", params: {} }));
  }

  request(method: string, params: unknown): Promise<any> {
    if (!this.alive) return Promise.reject(new Error("codex app-server is not running"));
    const id = this.#nextId++;
    this.#proc.write(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => this.#pending.set(id, { resolve, reject }));
  }

  kill(): Promise<void> {
    return this.#proc.kill();
  }

  #onLine(line: string): void {
    let msg: Record<string, any>;
    try {
      msg = JSON.parse(line) as Record<string, any>;
    } catch {
      log.debug("codex non-json line", { line: line.slice(0, 500) });
      return;
    }
    if (typeof msg.id === "number" && ("result" in msg || "error" in msg)) {
      const pending = this.#pending.get(msg.id);
      if (!pending) return;
      this.#pending.delete(msg.id);
      if (msg.error) pending.reject(new Error(`codex ${JSON.stringify(msg.error)}`));
      else pending.resolve(msg.result);
    } else if (msg.id !== undefined && typeof msg.method === "string") {
      // Server->client requests (approvals) should not arrive with approvalPolicy "never"; refuse rather than hang.
      log.warn("codex asked the client something; refusing", { method: msg.method });
      this.#proc.write(JSON.stringify({ id: msg.id, error: { code: -32601, message: "ember does not answer client requests" } }));
    } else if (typeof msg.method === "string") {
      const threadId = msg.params?.threadId;
      if (typeof threadId === "string") this.threads.get(threadId)?.notify(msg.method, msg.params);
    }
  }
}

function hostSignature(profile: Profile): string {
  return JSON.stringify([profile.home, profile.envs.codex, codexOverrides(profile.access.kind, profile.model)]);
}

export class CodexDriver implements AgentDriver {
  readonly runtime = "codex" as const;
  readonly #registry: ProcessRegistry;
  readonly #command: string;
  readonly #hosts = new Map<string, Host>();

  constructor(registry: ProcessRegistry, command = "codex") {
    this.#registry = registry;
    this.#command = command;
  }

  async #host(profile: Profile): Promise<Host> {
    let host = this.#hosts.get(profile.id);
    if (host?.alive && host.signature !== hostSignature(profile)) {
      // The profile changed. Replace the process once no session uses it; until then keep serving.
      if (host.threads.size === 0) {
        log.info("profile changed; restarting its codex app-server", { profile: profile.id });
        this.#hosts.delete(profile.id);
        await host.kill();
        host = undefined;
      } else {
        log.info("profile changed; its codex app-server restarts once idle", { profile: profile.id, sessions: host.threads.size });
      }
    }
    if (!host || !host.alive) {
      const created = new Host(profile, this.#command, this.#registry, () => {
        if (this.#hosts.get(profile.id) === created) this.#hosts.delete(profile.id);
      });
      host = created;
      this.#hosts.set(profile.id, host);
    }
    await host.ready;
    return host;
  }

  async open(options: OpenOptions, events: SessionEvents): Promise<AgentSession> {
    const host = await this.#host(options.profile);
    const model = options.model ?? options.profile.model;
    const common = {
      cwd: options.cwd,
      ...(model ? { model } : {}),
      approvalPolicy: "never",
      sandbox: "danger-full-access",
      developerInstructions: options.instructions,
      config: {
        "mcp_servers.ember.url": options.mcpUrl,
        "mcp_servers.ember.http_headers": { Authorization: `Bearer ${options.mcpToken}` },
        ...(options.effort ? { model_reasoning_effort: options.effort } : {}),
      },
    };
    const opened = options.resume
      ? await host.request("thread/resume", { threadId: options.resume, ...common })
      : await host.request("thread/start", common);
    const threadId = opened.thread.id as string;

    let busy = false;
    let turnId: string | null = null;
    let closed = false;
    const endTurn = (outcome: TurnOutcome) => {
      busy = false;
      turnId = null;
      events.turnEnded(outcome);
    };

    const live = liveFromCodex((event) => events.live?.(event));
    host.threads.set(threadId, {
      notify(method, params) {
        live(method, params);
        if (method === "turn/started") {
          turnId = params.turn?.id ?? turnId;
          if (!busy) {
            busy = true;
            events.turnStarted();
          }
        } else if (method === "turn/completed") {
          const turn = params.turn ?? {};
          if (turn.status === "interrupted") endTurn({ kind: "aborted" });
          else if (turn.status === "failed") {
            endTurn({ kind: "failed", reason: classifyCodexError(turn.error?.codexErrorInfo), message: String(turn.error?.message ?? "turn failed").slice(0, 1000) });
          } else endTurn({ kind: "completed" });
        } else if (method === "error" && !params.willRetry) {
          log.warn("codex turn error", { threadId, error: params.error });
        }
      },
      hostExited(reason) {
        closed = true;
        if (busy) endTurn({ kind: "failed", reason: "exited", message: reason });
        events.closed(reason);
      },
    });

    const input = (text: string) => [{ type: "text", text }];
    return {
      id: threadId,
      get busy() { return busy; },
      async prompt(text) {
        if (closed) throw new Error("codex session is closed");
        if (busy) throw new Error("a turn is already running");
        busy = true;
        try {
          const started = await host.request("turn/start", { threadId, input: input(text) });
          turnId = started.turn?.id ?? turnId;
        } catch (error) {
          busy = false;
          throw error;
        }
      },
      async steer(text) {
        if (closed || !busy || turnId === null) return false;
        try {
          await host.request("turn/steer", { threadId, input: input(text), expectedTurnId: turnId });
          return true;
        } catch (error) {
          log.debug("codex steer refused", { threadId, error });
          return false;
        }
      },
      async abort() {
        if (closed || !busy || turnId === null) return;
        await host.request("turn/interrupt", { threadId, turnId }).catch((error) => log.warn("codex interrupt failed", { threadId, error }));
      },
      async dispose() {
        if (closed) return;
        closed = true;
        host.threads.delete(threadId);
        await host.request("thread/unsubscribe", { threadId }).catch(() => { /* best effort: the thread just stays loaded */ });
      },
    };
  }

  /** The account's rate-limit windows, as the profile's app-server reports them (ChatGPT subscriptions). */
  async rateLimits(profile: Profile): Promise<unknown> {
    const host = await this.#host(profile);
    return host.request("account/rateLimits/read", {});
  }

  /** The models the account can run in Codex, as its app-server lists them (the ones it does not hide). */
  async models(profile: Profile): Promise<string[]> {
    const host = await this.#host(profile);
    const answer = await host.request("model/list", {}) as { data?: { id?: string; model?: string; hidden?: boolean }[] };
    return (answer.data ?? []).filter((m) => !m.hidden).map((m) => m.id ?? m.model ?? "").filter(Boolean);
  }

  async shutdown(): Promise<void> {
    await Promise.all([...this.#hosts.values()].map((host) => host.kill()));
    this.#hosts.clear();
  }
}

/**
 * The app-server's item notifications as live steps: an item starts, grows by
 * deltas (the reply, reasoning, a command's output as it runs) and completes.
 */
export function liveFromCodex(emit: (event: LiveEvent) => void): (method: string, params: Record<string, any>) => void {
  const open = new Set<string>();
  let phase: LivePhase | null = null;
  const to = (next: LivePhase) => {
    if (phase !== next) emit({ kind: "phase", phase: (phase = next) });
  };
  return (method, params) => {
    if (method === "turn/started") to("requesting");
    else if (method === "turn/completed") phase = null;
    else if (method === "item/agentMessage/delta" || method.startsWith("item/reasoning/")) to("responding");
    else if (method === "item/started" && ["commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "webSearch"].includes(params.item?.type)) to("working");
    else if (method === "item/completed" && ["commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "webSearch"].includes(params.item?.type)) to("requesting");
    if (method === "item/started") {
      const item = params.item ?? {};
      const id = String(item.id ?? "");
      let start: { step: LiveStepKind; tool?: string; input?: string } | null = null;
      switch (item.type) {
        case "agentMessage": start = { step: "text" }; break;
        case "reasoning": start = { step: "thinking" }; break;
        case "commandExecution": start = { step: "tool", tool: "shell", input: String(item.command ?? "") }; break;
        case "fileChange": start = { step: "tool", tool: "apply_patch", input: (item.changes ?? []).map((c: any) => String(c.path ?? "")).join("\n") }; break;
        case "mcpToolCall": start = { step: "tool", tool: `${item.server}.${item.tool}`, input: JSON.stringify(item.arguments ?? {}, null, 2) }; break;
        case "dynamicToolCall": start = { step: "tool", tool: String(item.tool), input: JSON.stringify(item.arguments ?? {}, null, 2) }; break;
        case "webSearch": start = { step: "tool", tool: "web_search", input: String(item.query ?? "") }; break;
      }
      if (!id || !start) return;
      open.add(id);
      emit({ kind: "start", id, ...start });
    } else if (method === "item/agentMessage/delta" || method === "item/reasoning/textDelta" || method === "item/reasoning/summaryTextDelta" || method === "item/plan/delta") {
      if (open.has(String(params.itemId)) && params.delta) emit({ kind: "delta", id: String(params.itemId), field: "text", text: String(params.delta) });
    } else if (method === "item/commandExecution/outputDelta") {
      if (open.has(String(params.itemId)) && params.delta) emit({ kind: "delta", id: String(params.itemId), field: "output", text: String(params.delta) });
    } else if (method === "item/completed") {
      const id = String(params.item?.id ?? "");
      if (open.delete(id)) emit({ kind: "end", id });
    }
  };
}
