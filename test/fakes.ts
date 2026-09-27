// In-memory stand-ins for a chat platform and a runtime, driven by tests.
import type { ChatMessage, ChatSurface, InboundMessage, ThreadRef } from "../src/chat/types.ts";
import type { RuntimeKind } from "../src/config.ts";
import type { AgentDriver, AgentSession, OpenOptions, SessionEvents, TurnOutcome } from "../src/runtime/types.ts";

let postCounter = 1;

export class FakeChat implements ChatSurface {
  readonly botUserId: string;
  readonly botName = "ember";
  readonly workspace: string | null;
  readonly posts: { thread: ThreadRef; text: string }[] = [];
  /** What it was told the agent is doing, per thread ("" once done). */
  readonly statuses: { thread: string; ts: string | null; status: string }[] = [];
  /** Web API calls made through it, and what each answers (by method; default ok with a fresh ts). */
  readonly calls: { method: string; params: Record<string, unknown> }[] = [];
  readonly answers = new Map<string, Record<string, unknown>>();
  async api(method: string, params: Record<string, unknown>): Promise<Record<string, unknown>> {
    this.calls.push({ method, params });
    return this.answers.get(method) ?? { ok: true, ts: `${9_500_000 + postCounter++}.000300` };
  }
  working(thread: ThreadRef, messageTs: string | null, status: string): void {
    this.statuses.push({ thread: `${thread.channel}/${thread.threadTs}`, ts: messageTs, status });
  }
  /** What the platform says was in a thread before ember saw it, by thread ts. */
  readonly earlier = new Map<string, ChatMessage[]>();
  constructor(botUserId = "UBOT", workspace: string | null = "T1") {
    this.botUserId = botUserId;
    this.workspace = workspace;
  }
  async start(): Promise<void> {}
  async stop(): Promise<void> {}
  async post(thread: ThreadRef, text: string): Promise<string> {
    this.posts.push({ thread: { channel: thread.channel, threadTs: thread.threadTs }, text });
    return `${9_000_000 + postCounter++}.000200`;
  }
  async history(thread: ThreadRef, before: string, limit: number): Promise<ChatMessage[]> {
    return (this.earlier.get(thread.threadTs) ?? []).filter((m) => Number(m.ts) < Number(before)).slice(-limit);
  }
}

export class FakeSession implements AgentSession {
  readonly id: string;
  readonly options: OpenOptions;
  readonly events: SessionEvents;
  readonly prompts: string[] = [];
  readonly steers: string[] = [];
  aborts = 0;
  disposed = false;
  busy = false;

  constructor(id: string, options: OpenOptions, events: SessionEvents) {
    this.id = id;
    this.options = options;
    this.events = events;
  }

  async prompt(text: string): Promise<void> {
    if (this.disposed) throw new Error("disposed");
    if (this.busy) throw new Error("busy");
    this.busy = true;
    this.prompts.push(text);
  }
  async steer(text: string): Promise<boolean> {
    if (!this.busy) return false;
    this.steers.push(text);
    return true;
  }
  async abort(): Promise<void> {
    this.aborts++;
  }
  async dispose(): Promise<void> {
    this.disposed = true;
  }

  /** The test ends the running turn. */
  end(outcome: TurnOutcome = { kind: "completed" }): void {
    this.busy = false;
    this.events.turnEnded(outcome);
  }
}

export class FakeDriver implements AgentDriver {
  readonly runtime: RuntimeKind;
  readonly sessions: FakeSession[] = [];
  /** Runtime session ids that resume fails for. */
  readonly unresumable = new Set<string>();
  #next = 1;

  constructor(runtime: RuntimeKind) {
    this.runtime = runtime;
  }

  async open(options: OpenOptions, events: SessionEvents): Promise<AgentSession> {
    if (options.resume && this.unresumable.has(options.resume)) throw new Error("no such session");
    const session = new FakeSession(options.resume ?? `${this.runtime}-${this.#next++}`, options, events);
    this.sessions.push(session);
    return session;
  }
  async shutdown(): Promise<void> {}

  get last(): FakeSession {
    const session = this.sessions.at(-1);
    if (!session) throw new Error(`no ${this.runtime} session opened`);
    return session;
  }
}

let tsCounter = 1000;
export function message(overrides: Partial<InboundMessage> = {}): InboundMessage {
  const ts = overrides.ts ?? `${tsCounter++}.000100`;
  return { channel: "C1", threadTs: ts, ts, user: "U1", text: "<@UBOT> hello", addressed: true, ...overrides };
}

/** Lets queued actor tasks and their promise chains run. */
export async function settle(): Promise<void> {
  for (let i = 0; i < 20; i++) await new Promise((resolve) => setImmediate(resolve));
}
