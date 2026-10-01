// The UI's side of the core (docs/client-core.md): one channel to the worker
// that runs it, calls with request ids, and subscriptions that survive the
// worker being replaced. The worker is a SharedWorker so every tab shares one
// core; a dedicated Worker per tab where SharedWorker is missing (Chrome on
// Android). In the desktop app (apps/desktop) the core runs in a utility
// process instead, reached through a MessagePort; the protocol is the same.
import { BUILT_AT } from "./built.ts";
import { BETA } from "../channel.ts";
import { applyDelta, type DeltaOp } from "./delta.ts";
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
  | { topic: "slackApp"; station: string; connect: string }
  // A station's background jobs still up, each with the chat it is in.
  | { topic: "jobs"; station: string }
  // A job's last `lines` lines of output and when it last grew, current as it grows.
  | { topic: "jobLog"; station: string; job: string; lines: number }
  | { topic: "loginSessions"; account: string }
  // `feedback`: bug reports about still.fail (a cloud from before has none: an error).
  | { topic: "admin"; account: string; list: "users" | "workspaces" | "invite-codes" | "feedback" }
  | { topic: "adminList"; account: string; list: "users" | "workspaces" | "invite-codes" | "feedback"; query: string; filter?: string; sort?: string; limit?: number }
  | { topic: "adminItem"; account: string; list: "users" | "workspaces" | "feedback"; id: string }
  | { topic: "adminOverview"; account: string }
  // Views: put together by the core from the topics above.
  | { topic: "chats"; scope: string; mine: boolean }
  | { topic: "stations"; scope: string }
  | { topic: "connects"; scope: string; mine: boolean }
  // An item's page: its chat, or its agent before it has one.
  | { topic: "chat"; station: string; thread: number }
  | { topic: "chat"; station: string; session: string }
  // An agent's execution history, read for people.
  | { topic: "history"; station: string; key: string }
  // What the core is waiting on, when it is worth saying (a core from before it answers an error: nothing to say): a
  // workspace's (its stations, its account's socket, the relay), or with none all of it.
  | { topic: "status"; workspace?: string }
  // What a chat on a station says of its connection, when it says it all decided (client/core/src/pill.rs).
  | { topic: "connection"; station: string }
  // What a person hears about while the client runs (docs/notifications.md): a workspace's, or every one's.
  | { topic: "notices"; workspace?: string }
  // What is written to a chat on this device, until sent: `chat` its key, `thread:<id>`, or `new` (a new chat there).
  | { topic: "draft"; station: string; chat: string }
  // Notifications on this device: on or off, asked, whether to hold pushes, the notices to show now (`notice.claim`),
  // only a workspace's for a page in it.
  | { topic: "notify"; workspace?: string }
  // The chats of a scope a few words find, titles first (only `station`'s, not `exclude`, `limit` at most): the
  // composer's `@` menu and the switcher. A core from before it answers an error.
  | { topic: "chatSearch"; scope: string; query: string; station?: string; exclude?: string; limit?: number }
  // The archived chats of a scope's stations online, newest first by day (client/core/src/views/archive.rs).
  | { topic: "archive"; scope: string }
  // A new chat's page in a scope: its stations, the one it starts on and what it runs there, as last picked here.
  | { topic: "newChat"; scope: string }
  // A model control: what it runs on now and what its panel picked (`of`: new, session:<key>, connect:<id>, connect-new).
  | { topic: "pick"; station: string; of: string }
  // A chat's services and background jobs as its pages show them (the same thread or session as its `chat`).
  | { topic: "chatJobs"; station: string; thread: number }
  | { topic: "chatJobs"; station: string; session: string }
  // The services and jobs left up a long while on the scope's stations that are up.
  | { topic: "longJobs"; scope: string }
  // A job as it is now (kept current by its events).
  | { topic: "job"; station: string; id: string }
  // How its person likes it on this device, and what the device is (prefs.ts).
  | { topic: "prefs" }
  // What changed in still.fail, as this app shows it, and what an update brought until `changelog.seen`
  // (client/core/src/changelog.rs).
  | { topic: "changelog" }
  // What each workspace has waiting (how many chats want their person, how many are unread) and the chat last open in
  // it; of those other than `workspace` (the one in view), the most urgent (client/core/src/views/marks.rs).
  | { topic: "workspaceMarks"; workspace?: string };

/** A chat as a page shows it (`client.focus`): by its thread, or its key before it has one; `end`: its end in view. */
export interface ChatShown { station: string; thread: number | null; session: string | null; end?: boolean }

/**
 * Where this page's attention is (`client.focus`, client/core/src/attend.rs): in view, looked at, the chat it shows,
 * the workspace it is in (an id, or `local`). Each field given changes; `chat: null` shows none; `left` says the chat
 * named is not shown any more.
 */
export interface Focus { visible?: boolean; focused?: boolean; chat?: ChatShown | null; left?: ChatShown; workspace?: string }

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
  /** How far the call has got, for one that says so (a file asked for with `progress`). */
  onProgress?: ((value: unknown) => void) | undefined;
}

interface Subscription {
  topic: Topic;
  onValue: (value: unknown) => void;
  onError: (error: CoreError) => void;
  /** The whole current value, which deltas apply to; unset until the first value and after an error. */
  value?: unknown;
}

export { applyDelta, type DeltaOp } from "./delta.ts";

export interface ClientOptions {
  /** Waits before reopening a failed worker; tests pass their own. */
  schedule?: (ms: number, run: () => void) => void;
  /** Errors in the worker (it reports them; the page cannot see them) and the worker failing, for error tracking. */
  onFault?: (error: Error) => void;
}

// A worker that keeps failing (a broken build, a panic on start) is retried
// with growing pauses rather than in a tight loop.
const RETRY_MS = [0, 1000, 2000, 5000, 10_000, 30_000];
/** A worker that answered before and says nothing this long after the page is back is taken for gone. */
export const WAKE_ANSWER_MS = 5000;

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
  /** The current channel has answered: it was up, so silence from it means something. */
  #up = false;
  /** Bumped by every message from the worker, so a wake can tell whether anything came after it. */
  #heard = 0;
  /** Where this page's attention is, as told last: told again to a worker started anew. */
  #focus: Focus = {};

  constructor(open: Opener, options: ClientOptions = {}) {
    this.#open = open;
    this.#schedule = options.schedule ?? ((ms, run) => void setTimeout(run, ms));
    this.#onFault = options.onFault ?? (() => undefined);
    this.#connect();
  }

  /** `signal` stops the call while it is under way; it then fails with `cancelled`. */
  call(name: string, params: unknown = {}, onProgress?: (value: unknown) => void, signal?: AbortSignal): Promise<unknown> {
    if (this.#closed) return Promise.reject(new CoreError({ code: "closed", message: "连接已关闭" }));
    if (signal?.aborted) return Promise.reject(new CoreError({ code: "cancelled", message: "已取消" }));
    const id = this.#nextId++;
    return new Promise((resolve, reject) => {
      this.#calls.set(id, { resolve, reject, onProgress });
      this.#send({ id, call: name, params });
      signal?.addEventListener("abort", () => {
        if (!this.#calls.has(id)) return;
        // The core answers `cancelled`; with no worker to tell, it is so here and now.
        if (this.#channel) {
          this.#post({ id, cancel: true });
        } else {
          this.#calls.delete(id);
          this.#queue = this.#queue.filter((m) => (m as { id?: number }).id !== id);
          reject(new CoreError({ code: "cancelled", message: "已取消" }));
        }
      }, { once: true });
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

  /** Tells the core where this page's attention is (see `Focus`); a core from before it refuses it (`unknown_call`). */
  focus(part: Focus): Promise<unknown> {
    const { left, ...rest } = part;
    const next: Focus = { ...this.#focus, ...rest };
    if (left && next.chat && same(next.chat, left)) next.chat = null;
    this.#focus = next;
    return this.call("client.focus", part);
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
    this.#refocus();
  }

  /**
   * The page is back after `away` ms hidden (a phone's page frozen in the background): the core gives up what went
   * out before and reconnects (client/core/src/wake.rs). A worker that was up and now says nothing at all is gone
   * (the system can end it without a word to its port): a new one is started.
   */
  wake(away: number): void {
    if (this.#closed) return;
    const channel = this.#channel;
    const heard = this.#heard;
    // With the worker being replaced it waits in the queue: a worker joined again (a shared one) is the same core.
    this.call("client.wake", { away: Math.max(0, Math.round(away)) }).catch(() => undefined);
    if (!this.#up || !channel) return;
    this.#schedule(WAKE_ANSWER_MS, () => {
      if (this.#channel !== channel || this.#heard !== heard) return;
      // A worker only frozen longer than this, not gone, drops this page's client rather than keep it.
      this.#post({ bye: true });
      this.#restart("回到前台后核心没有回应");
    });
  }

  /**
   * The device's network changed (it came back online): every connection the core has was on the old one, so all
   * that is under way is given up and opened anew (client/core/src/wake.rs). A core from before this takes it for a
   * wake after no time away, which does nothing.
   */
  networkChanged(): void {
    if (this.#closed) return;
    this.call("client.wake", { away: 0, network: true }).catch(() => undefined);
  }

  /**
   * A person asked to try again (重试 where a station or still.fail cloud shows down): what waits stops waiting, and
   * the connections are tried against new ones, but nothing under way is failed (client/core/src/wake.rs). `network`
   * goes with it for a core from before `retry`, which takes it for the network changed.
   */
  retry(): void {
    if (this.#closed) return;
    this.call("client.wake", { away: 0, network: true, retry: true }).catch(() => undefined);
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
      console.error("still.fail core: could not start the worker", error);
      return;
    }
    this.#channel = channel;
    this.#up = false;
    for (const [id, sub] of this.#subs) this.#post({ id, subscribe: sub.topic });
    const queued = this.#queue;
    this.#queue = [];
    for (const message of queued) this.#post(message);
    this.#refocus();
  }

  /** A core that forgot this page (a worker started anew, a page back from the cache) hears where it is again. */
  #refocus(): void {
    if (Object.keys(this.#focus).length) this.call("client.focus", this.#focus).catch(() => undefined);
  }

  #restart(reason: string): void {
    console.error("still.fail core: worker failed:", reason);
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
    this.#heard++;
    const message = data as { id?: number; ok?: unknown; value?: unknown; delta?: DeltaOp[]; error?: ErrorBody; fatal?: string; fault?: WorkerFault; retired?: boolean };
    // A newer build's core took over: this page is of the older build, so it loads the newer one.
    if (message.retired) {
      location.reload();
      return;
    }
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
    this.#up = true;
    if (message.id === undefined) return;
    const call = this.#calls.get(message.id);
    if (call) {
      // Values under a call's id tell how far it has got; its answer comes after them.
      if ("value" in message && !message.error) {
        call.onProgress?.(message.value);
        return;
      }
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

/**
 * The worker's name: its build, and on the test channel (app.youdid.wtf) a mark, by which the core there names the
 * product youdid.wtf (worker.ts; a worker has no page to look at).
 */
const workerName = `stillfail-core-${BUILT_AT}${BETA ? "-test" : ""}`;

/** Opens a channel to the core's worker: shared by every tab where the browser can. */
export function workerOpener(): Opener {
  return (onMessage, onFail) => {
    const receive = (event: MessageEvent) => {
      onMessage(event.data);
    };
    // Both constructors spelled out: Vite bundles a worker only from a literal
    // `new (Shared)Worker(new URL(…, import.meta.url))`.
    if (typeof SharedWorker !== "undefined") {
      const worker = new SharedWorker(new URL("./worker.ts", import.meta.url), { type: "module", name: workerName });
      worker.port.onmessage = receive;
      worker.onerror = () => onFail("共享 worker 没有启动");
      return { post: (message) => worker.port.postMessage(message), close: () => worker.port.close() };
    }
    const worker = new Worker(new URL("./worker.ts", import.meta.url), { type: "module", name: workerName });
    worker.onmessage = receive;
    worker.onerror = (event) => onFail(event.message || "worker 出错");
    return { post: (message) => worker.postMessage(message), close: () => worker.terminate() };
  };
}

/** What the desktop app's preload (apps/desktop/src/preload.ts) gives the page. */
export interface StillFailDesktop {
  /** Asks for a port to the core; it arrives as a window message `{ stillfailCore: "port", id }`. */
  openCore(id: number): void;
  /** The host a station's web service is shown at, stillfail-preview://<host>/ (apps/desktop/src/main.ts, previews). */
  previewHost(station: string, port: number): Promise<string | null>;
  /** The page is in a workspace, reached as `account`: the app's station joins it when it is in none yet. */
  inWorkspace(account: string, workspace: string): void;
  /** The station the app carries, and joining it to a workspace when asked to; an app from before this has none. */
  station?: {
    state(): Promise<CarriedStation | null>;
    /** Joins it to `workspace` as `account`, even if it joined one before (not over one it is in): its state after, or why not. */
    join(account: string, workspace: string): Promise<{ station: CarriedStation } | { error: string } | null>;
  };
  /** The cloud's origin (https://app.still.fail): its links are the app's own, though the app is at app://ember. */
  cloudOrigin?: string;
  /** The app's version (0.1.<commits>); an app from before it has none. */
  version?: string;
  /** The beta app (「youdid.wtf」, beside the released one); an app from before it has none (released). */
  beta?: boolean;
  /** The scheme a sign-in comes back to the app on (stillfail://, the beta app's stillfail-beta://); an app from before it has none (stillfail). */
  scheme?: string;
  /** A newer build of the app (apps/desktop/src/main.ts, keepUpdated); an app from before updates has none. */
  appUpdate?: {
    state(): Promise<AppUpdate | null>;
    /** Each change of it; the returned function stops listening. */
    watch(listener: (state: AppUpdate | null) => void): () => void;
    /** Downloads it; once it is, the app restarts as the new one. */
    start(): void;
    /** Asks for a newer build now, not waiting for the next check; an app from before it has none. */
    check?(): Promise<UpdateCheck | null>;
  };
  /** Whether the app tells about the chats (it shows them from its main process); an app from before them has none. */
  notify?: {
    get(): Promise<boolean | null>;
    set(on: boolean): Promise<void>;
  };
  /**
   * The computer woke from sleep after `away` ms (the window may have stayed visible all along, so the page is not
   * told otherwise); the returned function stops listening. An app from before this has none.
   */
  onResume?(listener: (away: number) => void): () => void;
  /** The computer's network became another; the returned function stops listening. An app from before this has none. */
  onNetwork?(listener: () => void): () => void;
}

/**
 * The station the desktop app carries (apps/desktop/src/station.ts): `carried` false in a build without one; in no
 * workspace (off), in one (running), or removed from the one it was in (`workspace`: the one it is or was in).
 */
export interface CarriedStation {
  carried: boolean;
  state: "off" | "running" | "removed";
  workspace?: string;
}

/** What a check asked for now found: the newer build (`latest`), none (neither), or why it could not tell. */
export type UpdateCheck = { current: string; latest?: string; error?: string };

export type AppUpdate =
  | { phase: "available"; version: string }
  | { phase: "downloading"; version: string; percent: number }
  | { phase: "installing"; version: string }
  | { phase: "failed"; version: string; message: string };

declare global {
  interface Window {
    stillfailDesktop?: StillFailDesktop;
  }
}

let nextPort = 1;

/**
 * Opens a channel to the desktop app's core, in its utility process: each
 * channel is a port of its own. Messages go out as objects and come back as
 * the core's JSON. The core's process exiting is announced to every page.
 */
export function desktopOpener(desktop: StillFailDesktop): Opener {
  return (onMessage, onFail) => {
    const id = nextPort++;
    let port: MessagePort | null = null;
    // What the client posts before the port is here, in order.
    const early: unknown[] = [];
    const arrive = (event: MessageEvent) => {
      if (event.source !== window) return;
      const data = event.data as { stillfailCore?: string; id?: number; reason?: string } | null;
      if (data?.stillfailCore === "exit") {
        onFail(data.reason ?? "核心进程退出了");
      } else if (data?.stillfailCore === "port" && data.id === id && !port && event.ports[0]) {
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

function same(a: ChatShown, b: ChatShown): boolean {
  return a.station === b.station && ((a.thread !== null && a.thread === b.thread) || (a.session !== null && a.session === b.session));
}

/** Starts (or joins) the core and keeps the page's client in step with the page's lifecycle. */
export function connectCore(): CoreClient {
  const open = window.stillfailDesktop ? desktopOpener(window.stillfailDesktop) : workerOpener();
  const client = new CoreClient(open, { onFault: (error) => captureException(error, { source: "core" }) });
  addEventListener("pagehide", () => client.suspend());
  // Hidden since when (wall clock: a frozen page's monotonic clock may stand still).
  let hidden = document.visibilityState === "hidden" ? Date.now() : null;
  const back = () => {
    if (hidden === null) return;
    const away = Date.now() - hidden;
    hidden = null;
    client.wake(away);
  };
  addEventListener("pageshow", (event) => {
    if (event.persisted) client.resume();
    back();
  });
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") hidden ??= Date.now();
    else back();
  });
  // In view, and looked at: what is read and which notices this page leaves out follow (client/core/src/attend.rs).
  const attend = () => void client.focus({ visible: document.visibilityState === "visible", focused: document.hasFocus() }).catch(() => undefined);
  attend();
  document.addEventListener("visibilitychange", attend);
  addEventListener("focus", attend);
  addEventListener("blur", attend);
  addEventListener("online", () => client.networkChanged());
  // Another network with no time offline between (Wi-Fi to mobile data): only where the browser says which kind it is
  // on (Chrome on Android); its other changes (speed, round trip) are the same network.
  const connection = (navigator as { connection?: EventTarget & { type?: string } }).connection;
  let kind = connection?.type;
  connection?.addEventListener("change", () => {
    const now = connection.type;
    if (now === kind) return;
    const was = kind;
    kind = now;
    if (was !== undefined && now !== undefined && now !== "none") client.networkChanged();
  });
  window.stillfailDesktop?.onNetwork?.(() => client.networkChanged());
  // The computer slept with the window open: the page never went hidden, so the app says so.
  window.stillfailDesktop?.onResume?.((away) => client.wake(away));
  return client;
}
