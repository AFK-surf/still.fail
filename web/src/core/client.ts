// The UI's side of the core (docs/client-core.md): one channel to the worker
// that runs it, calls with request ids, and subscriptions that survive the
// worker being replaced. The worker is a SharedWorker so every tab shares one
// core; a dedicated Worker per tab where SharedWorker is missing (Chrome on
// Android). In the desktop app (apps/desktop) the core runs in a utility
// process instead, reached through a MessagePort; the protocol is the same.
import { captureException } from "../telemetry.ts";

/** What a UI can subscribe to (`Topic` in client/core/src/protocol.rs). */
export type Topic =
  | { topic: "accounts" }
  | { topic: "workspaces" }
  | { topic: "workspace"; workspace: string }
  | { topic: "link"; station: string }
  | { topic: "overview"; station: string }
  | { topic: "sessions"; station: string }
  | { topic: "session"; station: string; key: string }
  | { topic: "live"; station: string; key: string }
  | { topic: "host"; station: string }
  | { topic: "threads"; station: string }
  // Views: put together by the core from the topics above.
  | { topic: "chats"; scope: string; mine: boolean }
  | { topic: "stations"; scope: string }
  | { topic: "connects"; scope: string; mine: boolean }
  // An item's page: its chat, or its agent before it has one.
  | { topic: "chat"; station: string; thread: number }
  | { topic: "chat"; station: string; session: string };

export interface ErrorBody {
  code: string;
  message: string;
  status?: number;
}

/** A call or topic that failed; `code` is the core's (ember cloud's codes pass through). */
export class CoreError extends Error {
  readonly code: string;
  readonly status: number | undefined;

  constructor(body: ErrorBody) {
    super(body.message);
    this.name = "CoreError";
    this.code = body.code;
    this.status = body.status;
  }
}

/** An error the worker caught in its own tasks (worker.ts), sent to one page to report. */
export interface WorkerFault {
  name: string;
  message: string;
  stack?: string;
}

/** One open channel to a worker. */
export interface Channel {
  post(message: unknown): void;
  close(): void;
}

/**
 * Opens a channel; messages from the worker go to `onMessage`, and `onFail`
 * when the worker is gone or broken (then the client opens a new one).
 */
export type Opener = (onMessage: (data: unknown) => void, onFail: (reason: string) => void) => Channel;

interface Pending {
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
}

interface Subscription {
  topic: Topic;
  onValue: (value: unknown) => void;
  onError: (error: CoreError) => void;
  /** The whole current value, which deltas apply to; unset until the first value and after an error. */
  value?: unknown;
}

/** One change in a delta (`Op` in client/core/src/delta.rs): the place, and what happens there. */
export type DeltaOp = { path: (string | number)[] } & ({ set: unknown } | { append: unknown[] } | { remove: true });

/**
 * A delta applied to a value without changing it: only the objects and arrays
 * along each op's path are copied, so unchanged parts keep their identity and
 * React skips them.
 */
export function applyDelta(value: unknown, ops: DeltaOp[]): unknown {
  return ops.reduce((current, op) => applyOp(current, op, 0), value);
}

function applyOp(node: unknown, op: DeltaOp, depth: number): unknown {
  if (depth === op.path.length) {
    if ("set" in op) return op.set;
    if ("append" in op) return Array.isArray(node) ? [...node, ...op.append] : node;
    return node;
  }
  const key = op.path[depth]!;
  if (Array.isArray(node)) {
    if (typeof key !== "number" || key >= node.length) return node;
    const copy = node.slice();
    copy[key] = applyOp(node[key], op, depth + 1);
    return copy;
  }
  if (typeof node !== "object" || node === null || typeof key !== "string") return node;
  const object = node as Record<string, unknown>;
  if ("remove" in op && depth === op.path.length - 1) {
    const rest = { ...object };
    delete rest[key];
    return rest;
  }
  return { ...object, [key]: applyOp(object[key], op, depth + 1) };
}

export interface ClientOptions {
  /** Waits before reopening a failed worker; tests pass their own. */
  schedule?: (ms: number, run: () => void) => void;
  /** Errors in the worker (it reports them; the page cannot see them) and the worker failing, for error tracking. */
  onFault?: (error: Error) => void;
}

// A worker that keeps failing (a broken build, a panic on start) is retried
// with growing pauses rather than in a tight loop.
const RETRY_MS = [0, 1000, 2000, 5000, 10_000, 30_000];

export class CoreClient {
  readonly #open: Opener;
  readonly #schedule: (ms: number, run: () => void) => void;
  readonly #onFault: (error: Error) => void;
  #channel: Channel | null = null;
  #nextId = 1;
  readonly #calls = new Map<number, Pending>();
  readonly #subs = new Map<number, Subscription>();
  /** Calls made while the worker is being replaced, sent once it is up. */
  #queue: unknown[] = [];
  #failures = 0;
  #closed = false;

  constructor(open: Opener, options: ClientOptions = {}) {
    this.#open = open;
    this.#schedule = options.schedule ?? ((ms, run) => void setTimeout(run, ms));
    this.#onFault = options.onFault ?? (() => undefined);
    this.#connect();
  }

  call(name: string, params: unknown = {}): Promise<unknown> {
    if (this.#closed) return Promise.reject(new CoreError({ code: "closed", message: "连接已关闭" }));
    const id = this.#nextId++;
    return new Promise((resolve, reject) => {
      this.#calls.set(id, { resolve, reject });
      this.#send({ id, call: name, params });
    });
  }

  /** Values arrive on `onValue` (the whole current value each time, deltas already applied); returns the unsubscribe. */
  subscribe(topic: Topic, onValue: (value: unknown) => void, onError: (error: CoreError) => void): () => void {
    const id = this.#nextId++;
    this.#subs.set(id, { topic, onValue, onError });
    // While the worker is being replaced, #connect subscribes everything anew.
    if (this.#channel) this.#post({ id, subscribe: topic });
    return () => {
      if (this.#subs.delete(id) && this.#channel) this.#post({ id, unsubscribe: true });
    };
  }

  /** The page is going away (or into the back/forward cache): the worker drops this client. */
  suspend(): void {
    if (this.#channel) this.#post({ bye: true });
  }

  /**
   * The page is back from the back/forward cache: the worker forgot us, so
   * subscribe again. Calls in flight were lost with the old client.
   */
  resume(): void {
    this.#rejectCalls("页面已恢复，请重试");
    if (this.#channel) for (const [id, sub] of this.#subs) this.#post({ id, subscribe: sub.topic });
  }

  close(): void {
    this.#closed = true;
    this.#rejectCalls("连接已关闭");
    this.#subs.clear();
    this.#channel?.close();
    this.#channel = null;
  }

  #connect(): void {
    if (this.#closed) return;
    let channel: Channel | null = null;
    // Late news from a channel already replaced is ignored.
    const current = () => channel !== null && channel === this.#channel;
    try {
      channel = this.#open(
        (data) => { if (current()) this.#receive(data); },
        (reason) => { if (current()) this.#restart(reason); },
      );
    } catch (error) {
      this.#channel = null;
      this.#retry();
      console.error("ember core: could not start the worker", error);
      return;
    }
    this.#channel = channel;
    for (const [id, sub] of this.#subs) this.#post({ id, subscribe: sub.topic });
    const queued = this.#queue;
    this.#queue = [];
    for (const message of queued) this.#post(message);
  }

  #restart(reason: string): void {
    console.error("ember core: worker failed:", reason);
    this.#onFault(Object.assign(new Error(reason), { name: "CoreFailed" }));
    this.#channel?.close();
    this.#channel = null;
    // Whether they ran is unknown: the caller decides whether to try again.
    this.#rejectCalls("核心已重启，请重试");
    this.#retry();
  }

  #retry(): void {
    const ms = RETRY_MS[Math.min(this.#failures, RETRY_MS.length - 1)] ?? 0;
    this.#failures++;
    this.#schedule(ms, () => this.#connect());
  }

  #rejectCalls(message: string): void {
    const calls = [...this.#calls.values()];
    this.#calls.clear();
    this.#queue = [];
    for (const call of calls) call.reject(new CoreError({ code: "core_restarted", message }));
  }

  #send(message: unknown): void {
    if (this.#channel) this.#post(message);
    else this.#queue.push(message);
  }

  #post(message: unknown): void {
    try {
      this.#channel?.post(message);
    } catch (error) {
      // Not cloneable (a caller's mistake): fail that call only.
      const id = (message as { id?: number }).id;
      const call = id === undefined ? undefined : this.#calls.get(id);
      if (id !== undefined && call) {
        this.#calls.delete(id);
        call.reject(error instanceof Error ? error : new Error(String(error)));
      } else {
        throw error;
      }
    }
  }

  #receive(data: unknown): void {
    if (typeof data !== "object" || data === null) return;
    const message = data as { id?: number; ok?: unknown; value?: unknown; delta?: DeltaOp[]; error?: ErrorBody; fatal?: string; fault?: WorkerFault };
    if (message.fatal !== undefined) {
      this.#restart(message.fatal);
      return;
    }
    if (message.fault) {
      const { name, message: text, stack } = message.fault;
      this.#onFault(Object.assign(new Error(text), { name, ...(stack ? { stack } : {}) }));
      return;
    }
    // A healthy answer: the worker is up again.
    this.#failures = 0;
    if (message.id === undefined) return;
    const call = this.#calls.get(message.id);
    if (call) {
      this.#calls.delete(message.id);
      if (message.error) call.reject(new CoreError(message.error));
      else call.resolve(message.ok);
      return;
    }
    const sub = this.#subs.get(message.id);
    if (!sub) return; // unsubscribed while a value was on its way
    if (message.error) {
      delete sub.value;
      sub.onError(new CoreError(message.error));
    } else if ("value" in message) {
      sub.value = message.value;
      sub.onValue(sub.value);
    } else if (message.delta && "value" in sub) {
      sub.value = applyDelta(sub.value, message.delta);
      sub.onValue(sub.value);
    }
  }
}

/** Opens a channel to the core's worker: shared by every tab where the browser can. */
export function workerOpener(): Opener {
  return (onMessage, onFail) => {
    const receive = (event: MessageEvent) => {
      onMessage(event.data);
    };
    // Both constructors spelled out: Vite bundles a worker only from a literal
    // `new (Shared)Worker(new URL(…, import.meta.url))`.
    if (typeof SharedWorker !== "undefined") {
      const worker = new SharedWorker(new URL("./worker.ts", import.meta.url), { type: "module", name: "ember-core" });
      worker.port.onmessage = receive;
      worker.onerror = () => onFail("共享 worker 没有启动");
      return { post: (message) => worker.port.postMessage(message), close: () => worker.port.close() };
    }
    const worker = new Worker(new URL("./worker.ts", import.meta.url), { type: "module", name: "ember-core" });
    worker.onmessage = receive;
    worker.onerror = (event) => onFail(event.message || "worker 出错");
    return { post: (message) => worker.postMessage(message), close: () => worker.terminate() };
  };
}

/** What the desktop app's preload (apps/desktop/src/preload.ts) gives the page. */
export interface EmberDesktop {
  /** Asks for a port to the core; it arrives as a window message `{ emberCore: "port", id }`. */
  openCore(id: number): void;
}

declare global {
  interface Window {
    emberDesktop?: EmberDesktop;
  }
}

let nextPort = 1;

/**
 * Opens a channel to the desktop app's core, in its utility process: each
 * channel is a port of its own. Messages go out as objects and come back as
 * the core's JSON. The core's process exiting is announced to every page.
 */
export function desktopOpener(desktop: EmberDesktop): Opener {
  return (onMessage, onFail) => {
    const id = nextPort++;
    let port: MessagePort | null = null;
    // What the client posts before the port is here, in order.
    const early: unknown[] = [];
    const arrive = (event: MessageEvent) => {
      if (event.source !== window) return;
      const data = event.data as { emberCore?: string; id?: number; reason?: string } | null;
      if (data?.emberCore === "exit") {
        onFail(data.reason ?? "核心进程退出了");
      } else if (data?.emberCore === "port" && data.id === id && !port && event.ports[0]) {
        port = event.ports[0];
        port.onmessage = (message) => onMessage(JSON.parse(message.data as string));
        for (const message of early.splice(0)) port.postMessage(message);
      }
    };
    addEventListener("message", arrive);
    desktop.openCore(id);
    return {
      post: (message) => {
        if (port) {
          port.postMessage(message);
        } else {
          // Throws now, as posting would, for what cannot be sent.
          structuredClone(message);
          early.push(message);
        }
      },
      close: () => {
        removeEventListener("message", arrive);
        port?.close();
      },
    };
  };
}

/** Starts (or joins) the core and keeps the page's client in step with the page's lifecycle. */
export function connectCore(): CoreClient {
  const open = window.emberDesktop ? desktopOpener(window.emberDesktop) : workerOpener();
  const client = new CoreClient(open, { onFault: (error) => captureException(error, { source: "core" }) });
  addEventListener("pagehide", () => client.suspend());
  addEventListener("pageshow", (event) => { if (event.persisted) client.resume(); });
  return client;
}
