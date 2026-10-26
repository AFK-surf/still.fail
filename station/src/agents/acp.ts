// The Agent Client Protocol (JSON-RPC over stdio, agentclientprotocol.com) as the station speaks it to the runtimes that
// serve it (Grok Build, Devin, Hermes Agent: grok.ts, devin.ts, hermes.ts), one ACP session in a process of its own
// (own-process.ts):
// - `initialize`, then `session/new` (the agent names the session) or `session/load` (one it keeps), given the station's
//   tools as an HTTP MCP server; what session/load says again of the session's past is no turn;
// - a turn is a `session/prompt`, ended by its answer: `stopReason` (`cancelled` after `session/cancel`), or an error
//   whose message says why it failed;
// - what the model says and does streams in `session/update`s (live.ts LiveFromAcp): text and thinking in chunks, a call
//   as `tool_call`, then `tool_call_update`s until it completed or failed. A step with no turn running is not the
//   session's turn's, unless a prompt of ours put in the turn as it ended became a turn of its own;
// - a permission it asks is granted for the call (the station runs its agents without approvals); any other request of
//   its own is refused (what it would ask is asked in the chat);
// - a call to the station's tools failing as unreachable says the tools are lost.
// What each runtime does its own way (how it is started and signed in, how it is given the station's instructions, a
// message for the running turn, what it says of its usage, its subagents) is its driver's, by the hooks below; and so is
// a transcript kept by the station (KeptTranscript), for a runtime whose own the station cannot read.
import { appendFileSync } from "node:fs";
import { join } from "node:path";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { LiveFromAcp, acpNamed, chars, type AcpLiveState } from "./live.ts";
import { type Events, OwnProcessDriver, OwnProcessSession, type ProcessSnapshot, parseLine } from "./own-process.ts";
import type { RunnerInfo } from "./runner.ts";
import { runtimeLabel, stationTool, unreachable, uuid, type FailureReason, type OpenOptions, type RuntimeKind, type TurnOutcome } from "./runtime.ts";

type Json = any;

/// The ids of the requests the station makes. A prompt carries its own (prompt:<uuid>), and so does a prompt put in the
/// running turn (steer:<uuid>), so whatever answers one (after a crash too) is known for what it is.
export const INIT = "init";
export const OPEN = "open";
export const PROMPT = "prompt:";
export const STEER = "steer:";

const CLIENT = { name: "still.fail", version: "1" };

export const rpc = (id: string, method: string, params: Json) => JSON.stringify({ jsonrpc: "2.0", id, method, params });

/// The station's tools as ACP gives an MCP server.
export const mcpServers = (url: string, token: string) => [{ type: "http", name: "stillfail", url, headers: [{ name: "Authorization", value: `Bearer ${token}` }] }];

/// Whether an update is a step of a turn (what the model says or does), not something said of the session.
export const turnStep = (update: Json) => ["agent_message_chunk", "agent_thought_chunk", "tool_call", "tool_call_update"].includes(update?.sessionUpdate);

/// What an error answer says: its message, and its data's.
function errorText(error: Json): string {
  const text = typeof error?.message === "string" ? error.message.replace(/^Internal error: /, "") : JSON.stringify(error);
  const data = typeof error?.data === "string" ? `: ${error.data}` : typeof error?.data?.message === "string" ? `: ${error.data.message}` : "";
  return `${text}${data}`;
}

/// How a prompt's answer ends the turn, told apart by `classify` when it failed.
export function acpOutcome(answer: Json, classify: (text: string) => FailureReason): TurnOutcome {
  if (answer?.error !== undefined) {
    const said = errorText(answer.error);
    return { kind: "failed", reason: classify(said), message: chars(said, 1000) };
  }
  const stop = answer?.result?.stopReason;
  if (stop === "cancelled") return { kind: "aborted" };
  if (stop === "refusal") return { kind: "failed", reason: "model", message: "the model refused" };
  return { kind: "completed" };
}

/// A call under way, as it started: its name (as the station names it: live.ts acpNamed) and its input.
export type Call = { name: string; input: Json };
/// A call done, and what it said.
type Done = Call & { id: string; failed: boolean; text: string };

/// What is being said, as a transcript keeps it: the step's kind and its text so far.
export type Said = { type: "assistant" | "thinking"; text: string };

/// A session as a next station takes it up. What a station before this one's handed over may lack.
export type AcpSnapshot = ProcessSnapshot & {
  turn: { busy: boolean; aborting: boolean };
  tools: string | null;
  live: AcpLiveState;
  model?: string | null;
  owner?: string | null;
  steering?: string[];
  said?: Said | null;
  calls?: [string, Call][];
};

/// The transcript the station keeps of a session whose runtime keeps none it can read (Devin keeps its sessions in a
/// database of its own; Hermes'): <dir>/<session id>.jsonl, a line for each thing said and done, as Cursor's bridge
/// keeps its own (read/transcript.ts reads them alike): the person's messages, what was said once whole (something else
/// came), a call once done with what it said, the turn's usage, its end.
export class KeptTranscript {
  private readonly kind: RuntimeKind;
  private readonly dir: string;
  /// What is being said now (in a snapshot: the next station writes it whole).
  said: Said | null = null;
  /// Read again after a crash: what was written then is not written twice.
  private quiet = false;

  constructor(kind: RuntimeKind, dir: string) {
    this.kind = kind;
    this.dir = dir;
  }

  keep(id: string, line: Json) {
    if (id === "" || this.quiet) return;
    try {
      appendFileSync(join(this.dir, `${id}.jsonl`), `${JSON.stringify({ time: wall.now(), ...line })}\n`);
    } catch (e) {
      log.warn(`agents::${this.kind}`, "a transcript line was not kept", { session: id, error: (e as Error).message });
    }
  }

  user(id: string, text: string, steered = false) {
    this.flush(id);
    this.keep(id, steered ? { type: "user", text, steered: true } : { type: "user", text });
  }

  /// What an update adds: what is being said grows, whole once something else comes; a call once it is done.
  take(id: string, update: Json, done: Done | null) {
    const kind = update?.sessionUpdate;
    if (kind === "agent_message_chunk" || kind === "agent_thought_chunk") {
      const type = kind === "agent_message_chunk" ? "assistant" : "thinking";
      const text = typeof update.content?.text === "string" ? update.content.text : "";
      if (this.said !== null && this.said.type !== type) this.flush(id);
      this.said ??= { type, text: "" };
      this.said.text += text;
      return;
    }
    if ((kind !== "tool_call" && kind !== "tool_call_update") || typeof update.toolCallId !== "string") return;
    this.flush(id);
    if (done !== null) this.keep(id, { type: "tool", id: done.id, name: done.name, status: done.failed ? "error" : "completed", args: done.input, result: chars(done.text, 20_000) });
  }

  /// What was being said, written.
  flush(id: string) {
    if (this.said === null) return;
    if (this.said.text.trim() !== "") this.keep(id, { type: this.said.type, text: this.said.text });
    this.said = null;
  }

  ended(id: string, outcome: TurnOutcome) {
    this.flush(id);
    this.keep(id, { type: "end", status: outcome.kind === "completed" ? "finished" : outcome.kind === "aborted" ? "cancelled" : "error", ...(outcome.kind === "failed" ? { error: { message: outcome.message } } : {}) });
  }

  /// `f`, nothing written of it.
  quietly(f: () => void) {
    this.quiet = true;
    try {
      f();
    } finally {
      this.quiet = false;
    }
  }
}

export abstract class AcpSession extends OwnProcessSession {
  protected live = new LiveFromAcp();
  /// The model its turns run on (null when not known).
  model: string | null = null;
  /// The prompt whose answer ends the turn (ours, or one put in the turn that became a turn of its own), and the prompts
  /// put in the running turn not answered yet.
  protected owner: string | null = null;
  protected steering = new Set<string>();
  /// Until the session is open: what session/load says again of its past is no turn.
  private loading = true;
  /// Its calls under way.
  private calls = new Map<string, Call>();
  /// The transcript the station keeps of it (null: the runtime's own is read).
  protected readonly transcript: KeptTranscript | null;
  /// Whether a message for the running turn goes into it as a prompt of its own, answered with the turn (Devin's),
  /// rather than as a request of the runtime's own or not at all.
  protected readonly steersByPrompt: boolean = false;

  constructor(driver: AcpDriver<any>, events: Events, transcript: KeptTranscript | null = null) {
    super(driver, "", { busy: false, aborting: false, closed: false }, events);
    this.transcript = transcript;
  }

  /// How a failure it said is told apart.
  protected abstract classify(text: string): FailureReason;
  /// An update as the station reads it.
  protected normalized(update: Json): Json {
    return update;
  }
  /// An update of another session in its process (a subagent's).
  protected other(_from: string, _update: Json): void {}
  /// A notification of the runtime's own.
  protected notified(_message: Json): void {}
  /// An update of the session's, once its steps are told: what the runtime says beside them (its usage).
  protected updated(_update: Json): void {}
  /// The turn ends as `answer` says, before what is open of it ends.
  protected ending(_id: string, _answer: Json): void {}
  /// What a message of the person's is given to it as.
  protected promptText(text: string): string {
    return text;
  }
  /// What a snapshot keeps besides the protocol's (the runtime's own), and takes back.
  protected kept(): Record<string, unknown> {
    return {};
  }
  protected taken(_snapshot: Json): void {}

  /// Open: session/new's or session/load's answer (`result`) says what it runs on besides.
  opened(_result: Json) {
    this.loading = false;
  }

  /// A session made new: the transcript says so first.
  began(cwd: string) {
    this.transcript?.keep(this.sessionId, { type: "session", id: this.sessionId, cwd });
  }

  /// A request whose answer is waited for: an error answer rejects.
  request(id: string, method: string, params: Json): Promise<Json> {
    const answer = this.waiting.wait(id, (m) => (m?.error !== undefined ? new Error(`${this.kind} ${method}: ${errorText(m.error)}`) : null));
    this.proc.write(rpc(id, method, params));
    return answer;
  }

  /// A request whose answer is not waited for.
  protected send(method: string, params: Json) {
    this.proc.write(rpc(`${method}:${uuid()}`, method, params));
  }

  protected heard(line: string) {
    const message = parseLine(this.kind, line);
    if (message !== undefined) this.onMessage(message);
  }

  private onMessage(message: Json) {
    const id = message.id;
    if (message.method === "session/update") return this.update(message.params);
    if (message.method === "session/request_permission" && id !== undefined) return this.permit(id, message.params?.options);
    if (message.method !== undefined) {
      // A request of its own the station has no answer for (asking the person a question, a plan to approve): what it
      // asks is answered in the chat, not here.
      if (id !== undefined) this.proc.write(JSON.stringify({ jsonrpc: "2.0", id, error: { code: -32601, message: `${message.method} is not supported` } }));
      else this.notified(message);
      return;
    }
    if (this.endsTurn(id)) {
      // One put in the turn is answered with the turn (before or after its prompt's answer); one whose turn this station
      // did not see the end of (taken up after a crash) ends the turn running now.
      if (this.steering.delete(id)) return;
      if (this.owner !== null && id !== this.owner) return;
      this.end(id, message);
      return;
    }
    this.waiting.answer(id, message);
  }

  /// Whether `id` is a prompt's, whose answer ends a turn.
  private endsTurn(id: unknown): id is string {
    return typeof id === "string" && (id.startsWith(PROMPT) || (this.steersByPrompt && id.startsWith(STEER)));
  }

  private update(params: Json) {
    if (this.loading) return;
    const update = this.normalized(params?.update);
    const from = params?.sessionId;
    if (this.sessionId !== "" && typeof from === "string" && from !== this.sessionId) return this.other(from, update);
    if (!this.turn.busy && turnStep(update) && !this.unprompted()) return;
    const done = this.track(update);
    this.transcript?.take(this.sessionId, update, done);
    for (const event of this.live.feed(update)) this.events({ type: "live", event });
    this.updated(update);
    const lost = done === null ? null : this.lost(done);
    if (lost !== null) this.events({ type: "toolsLost", why: lost });
  }

  /// A step came with no turn running: a prompt of ours put in the turn as it ended became a turn of its own, which its
  /// answer ends; any other is not a turn's.
  private unprompted(): boolean {
    const first = this.steering.values().next();
    if (first.done) return false;
    this.steering.delete(first.value);
    this.owner = first.value;
    this.turn.busy = true;
    this.events({ type: "turnStarted" });
    return true;
  }

  /// What an update says of its calls: one starting is under way; one done (completed or failed) is returned, with what
  /// it said.
  private track(update: Json): Done | null {
    const kind = update?.sessionUpdate;
    const id = typeof update?.toolCallId === "string" ? update.toolCallId : null;
    if ((kind !== "tool_call" && kind !== "tool_call_update") || id === null) return null;
    if (kind === "tool_call" && !this.calls.has(id)) {
      const [name, input] = acpNamed(update);
      this.calls.set(id, { name, input });
    }
    const call = this.calls.get(id);
    if (call === undefined || (update.status !== "completed" && update.status !== "failed")) return null;
    this.calls.delete(id);
    const text = (Array.isArray(update.content) ? update.content : []).map((c: Json) => c?.content?.text ?? c?.text ?? "").filter((t: string) => t !== "").join("\n");
    return { id, ...call, failed: update.status === "failed", text };
  }

  /// What a call done says of the station's tools being out of reach (null: nothing): one of them failed as unreachable.
  private lost(done: Done): string | null {
    return done.failed && stationTool(done.name) && unreachable(done.text) ? chars(done.text, 300) : null;
  }

  /// A permission it asks: granted for this call, as the other runtimes run without approvals here, and only for it
  /// (nothing of it is kept in the runtime's settings); refused when it offers no way to allow just this call.
  private permit(id: Json, options: Json) {
    const offered: Json[] = Array.isArray(options) ? options : [];
    const chosen = offered.find((o) => o?.kind === "allow_once");
    const result = chosen ? { outcome: { outcome: "selected", optionId: chosen.optionId } } : { outcome: { outcome: "cancelled" } };
    this.proc.write(JSON.stringify({ jsonrpc: "2.0", id, result }));
  }

  /// The turn ended as the answer to its prompt says.
  private end(id: string, answer: Json) {
    const outcome = this.turn.aborting && answer.error !== undefined ? ({ kind: "aborted" } as TurnOutcome) : acpOutcome(answer, (text) => this.classify(text));
    // An answer to a prompt this station did not see start (taken up after a crash just as it was given).
    if (!this.turn.busy) this.events({ type: "turnStarted" });
    this.turn.busy = false;
    this.turn.aborting = false;
    this.owner = null;
    this.transcript?.flush(this.sessionId);
    this.ending(id, answer);
    this.transcript?.ended(this.sessionId, outcome);
    this.calls.clear();
    for (const event of this.live.ended()) this.events({ type: "live", event });
    this.events({ type: "turnEnded", outcome });
  }

  protected cutShort(said: string) {
    this.transcript?.ended(this.sessionId, { kind: "failed", reason: "exited", message: `${this.kind} exited (${said})` });
    this.calls.clear();
    for (const event of this.live.ended()) this.events({ type: "live", event });
  }

  async prompt(text: string) {
    this.startable();
    this.turn.busy = true;
    this.owner = `${PROMPT}${uuid()}`;
    this.transcript?.user(this.sessionId, text);
    for (const event of this.live.prompted()) this.events({ type: "live", event });
    this.proc.write(rpc(this.owner, "session/prompt", { sessionId: this.sessionId, prompt: [{ type: "text", text: this.promptText(text) }] }));
  }

  /// Not into the running turn: the station gives it as the next turn's.
  async steer(_text: string): Promise<boolean> {
    return false;
  }

  /// Into the running turn as a prompt of its own, read at the turn's next step and answered with it. Not when nothing
  /// runs: it would be a turn of its own, which the station starts itself.
  protected promptInto(text: string): boolean {
    if (this.turn.closed || !this.turn.busy || this.turn.aborting) return false;
    const id = `${STEER}${uuid()}`;
    this.steering.add(id);
    this.transcript?.user(this.sessionId, text, true);
    this.proc.write(rpc(id, "session/prompt", { sessionId: this.sessionId, prompt: [{ type: "text", text: this.promptText(text) }] }));
    return true;
  }

  async abort() {
    if (this.turn.closed || !this.turn.busy || this.turn.aborting) return;
    this.turn.aborting = true;
    this.proc.write(JSON.stringify({ jsonrpc: "2.0", method: "session/cancel", params: { sessionId: this.sessionId } }));
  }

  /// What the station that handed it over knew of it.
  handed(snapshot: AcpSnapshot) {
    this.sessionId = snapshot.id;
    this.turn = { busy: snapshot.turn.busy, aborting: snapshot.turn.aborting, closed: false };
    this.live = new LiveFromAcp(snapshot.live);
    this.toolsUrl = snapshot.tools;
    this.model = snapshot.model ?? this.model;
    this.owner = snapshot.owner ?? null;
    this.steering = new Set(snapshot.steering ?? []);
    this.calls = new Map(snapshot.calls ?? []);
    if (this.transcript !== null) this.transcript.said = snapshot.said ?? null;
    this.loading = false;
    this.taken(snapshot);
  }

  /// What the station before had handled of its output when it crashed, read again silently: the session, whether a turn
  /// runs, what the turn had said and called so far.
  replay(lines: Iterable<string>, resume: string | undefined) {
    this.sessionId = resume ?? "";
    let open = false;
    let partial: Json[] = [];
    for (const line of lines) {
      const message = parseLine(this.kind, line);
      if (message === undefined) continue;
      if (message.id === OPEN) {
        open = true;
        if (typeof message.result?.sessionId === "string") this.sessionId = message.result.sessionId;
      } else if (open && message.method === "session/update" && (this.sessionId === "" || message.params?.sessionId === this.sessionId)) {
        const update = this.normalized(message.params?.update);
        if (!turnStep(update)) continue;
        this.turn.busy = true;
        this.live.feed(update);
        partial.push(update);
      } else if (this.endsTurn(message.id)) {
        this.turn.busy = false;
        this.live.ended();
        partial = [];
      }
    }
    this.loading = false;
    // What the running turn had said and called, as if heard now, nothing of it written again.
    const again = () => {
      for (const update of partial) {
        const done = this.track(update);
        this.transcript?.take(this.sessionId, update, done);
      }
    };
    if (this.transcript !== null) this.transcript.quietly(again);
    else again();
  }

  snapshot(): AcpSnapshot {
    this.handOver();
    return {
      runtime: this.kind,
      id: this.sessionId,
      runner: this.proc.info.id,
      turn: { busy: this.turn.busy, aborting: this.turn.aborting },
      tools: this.toolsUrl,
      live: this.live.state(),
      model: this.model,
      owner: this.owner,
      steering: [...this.steering],
      said: this.transcript?.said ?? null,
      calls: [...this.calls],
      ...this.kept(),
    };
  }
}

/// How a runtime's process is started for a session, and what the protocol's own requests carry of it.
export type AcpStart = {
  command: string;
  args: string[];
  env: Record<string, string>;
  /// The `_meta` of initialize, session/new and session/load (Grok Build's rules).
  meta?: Json;
  /// What session/new and session/load are given besides the working directory and the station's tools.
  opening?: Json;
};

export abstract class AcpDriver<S extends AcpSession> extends OwnProcessDriver<S> {
  /// A session of it, not open yet.
  protected abstract session(options: OpenOptions, events: Events): S;
  /// How its process is started for a session (`probe`: one opened only to learn what it offers, with no tools of the
  /// station's, nothing of it kept). What must be there first is made here; a session it would not find to load fails
  /// here, before anything starts, so that the caller starts afresh.
  protected abstract starting(options: OpenOptions, probe: boolean): AcpStart;
  /// Once initialize is answered (`answer`): signing in, its version.
  protected async initialized(_session: S, _answer: Json, _options: OpenOptions): Promise<void> {}
  /// Once the session is open: what it runs with (no approvals, its model).
  protected async ready(_session: S, _options: OpenOptions, _probe: boolean): Promise<void> {}

  open(options: OpenOptions, events: Events): Promise<S> {
    return this.begin(options, events, false);
  }

  protected async begin(options: OpenOptions, events: Events, probe: boolean): Promise<S> {
    const start = this.starting(options, probe);
    const session = this.session(options, events);
    session.toolsUrl = options.mcpUrl;
    await this.start(session, options, start.command, start.args, start.env);
    try {
      const meta = start.meta === undefined ? {} : { _meta: start.meta };
      const answer = await session.request(INIT, "initialize", { protocolVersion: 1, clientCapabilities: {}, clientInfo: CLIENT, ...meta });
      await this.initialized(session, answer, options);
      const opening = { cwd: options.cwd, mcpServers: probe ? [] : mcpServers(options.mcpUrl, options.mcpToken), ...start.opening, ...meta };
      let opened: Json;
      if (options.resume !== undefined) {
        session.named(options.resume);
        opened = await session.request(OPEN, "session/load", { sessionId: options.resume, ...opening });
      } else {
        opened = await session.request(OPEN, "session/new", opening);
        const id = opened?.result?.sessionId;
        if (typeof id !== "string" || id === "") throw new Error(`${runtimeLabel(this.runtime())} named no session`);
        session.named(id);
        if (!probe) session.began(options.cwd);
      }
      session.opened(opened?.result);
      await this.ready(session, options, probe);
    } catch (error) {
      await session.dispose();
      throw error;
    }
    return session;
  }

  protected handedOver(options: OpenOptions, snapshot: Json, _info: RunnerInfo, events: Events): S {
    const session = this.session(options, events);
    session.handed(snapshot as AcpSnapshot);
    return session;
  }

  protected crashed(options: OpenOptions, lines: Iterable<string>, _info: RunnerInfo, events: Events): S {
    const session = this.session(options, events);
    session.replay(lines, options.resume);
    session.toolsUrl = options.mcpUrl;
    return session;
  }
}
