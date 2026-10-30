import { UNTRACKED_OPERATIONS } from "./operations.ts";
// The UI's side of the core (docs/client-core.md): one channel to the worker
// that runs it, calls with request ids, and subscriptions that survive the
// worker being replaced. Each tab has a dedicated Worker; one of them runs the
// core and the others' relay to it (worker.ts, docs/core-db.md).
import { BUILT_AT } from "./built.ts";
import { BETA } from "../channel.ts";
import { applyDelta, type DeltaOp } from "./delta.ts";
import { captureException } from "../telemetry.ts";
import { reload } from "../reloads.ts";
import { t } from "../i18n.ts";

/** What a UI can subscribe to (`Topic` in client/core-ts/src/protocol.ts). */
export type Topic =
  | { topic: "decisionForm"; station: string; form: string }
  | { topic: "policyForm"; station: string; form: string }
  | { topic: "agentEnvForm"; station: string; form: string }
  | { topic: "profileFlow"; station: string; form: string }
  | { topic: "connectFlow"; station: string; form: string }
  | { topic: "slackTokens"; station: string; form: string }
  | { topic: "accounts" }
  | { topic: "workspaces" }
  | { topic: "workspace"; workspace: string }
  | { topic: "link"; station: string }
  | { topic: "overview"; station: string }
  | { topic: "sessions"; station: string }
  | { topic: "session"; station: string; key: string }
  | { topic: "live"; station: string; key: string }
  | { topic: "host"; station: string }
  | { topic: "footprint"; station: string }
  // The agents' memory on a station, read as a page shows it (what was read last shows meanwhile).
  | { topic: "memory"; station: string }
  // What a web link in a message is, read as its card shows (what was read last shows meanwhile).
  | { topic: "linkPreview"; station: string; url: string }
  // What a file a message names is, read as its card shows (what was read last shows meanwhile).
  | { topic: "filePeek"; station: string; key: string; path: string; line?: number }
  | { topic: "threads"; station: string }
  | { topic: "slackApp"; station: string; connect: string }
  // A station's background jobs still up, each with the chat it is in.
  | { topic: "jobs"; station: string }
  // A job's last `lines` lines of output and when it last grew, current as it grows.
  | { topic: "jobLog"; station: string; job: string; lines: number }
  // A station's logins to its command-line tools (docs/remote-login.md): the services it knows and its logins, one
  // login as it stands, and that login's terminal (only while it is looked at).
  | { topic: "machineLogins"; station: string }
  | { topic: "machineLogin"; station: string; id: string }
  | { topic: "machineLoginScreen"; station: string; id: string }
  | { topic: "loginSessions"; account: string }
  // `feedback`: bug reports about still.fail (a cloud from before has none: an error).
  | { topic: "admin"; account: string; list: "users" | "workspaces" | "invite-codes" | "feedback" }
  | { topic: "adminList"; account: string; list: "users" | "workspaces" | "invite-codes" | "feedback"; query: string; filter?: string; sort?: string; limit?: number; messages?: number }
  | { topic: "adminItem"; account: string; list: "users" | "workspaces" | "feedback"; id: string }
  | { topic: "adminOverview"; account: string }
  // still.fail's relays and the load on each over the last day or week (a cloud from before has none: a 404).
  | { topic: "adminRelays"; account: string; range?: "day" | "week" }
  // Views: put together by the core from the topics above.
  | { topic: "chats"; scope: string; mine: boolean; watching?: boolean }
  // With `drive`: those with a drive, this machine's (`here`) first.
  | { topic: "stations"; scope: string; drive?: boolean; here?: string }
  // This device's connection to a station with every figure: sampled while subscribed, so only where they are drawn
  // (the list says only how it is reached, `way`).
  | { topic: "stationNet"; station: string }
  | { topic: "connects"; scope: string; mine: boolean }
  // An item's page: its chat, or its agent before it has one.
  | { topic: "chat"; station: string; thread: number }
  | { topic: "chat"; station: string; session: string }
  // An agent's execution history, read for people.
  | { topic: "history"; station: string; key: string }
  // What the core is waiting on, when it is worth saying (a core from before it answers an error: nothing to say): a
  // workspace's (its stations, its account's socket, the relay), or with none all of it.
  | { topic: "status"; workspace?: string }
  // What a chat on a station says of its connection, when it says it all decided (client/core-ts/src/pill.ts).
  | { topic: "connection"; station: string }
  // What a person hears about while the client runs (docs/notifications.md): a workspace's, or every one's.
  | { topic: "notices"; workspace?: string }
  // What is written to a chat on this device, until sent: `chat` its key, `thread:<id>`, or `new` (a new chat there).
  | { topic: "draft"; station: string; chat: string }
  // Notifications on this device: on or off, asked, whether to hold pushes, the notices to show now (`notice.claim`),
  // only a workspace's for a page in it.
  | { topic: "notify"; workspace?: string }
  // The chats of a scope a few words find, titles first (not `exclude`, `limit` at most; written on `station`, the
  // other stations' say so): the composer's `@` menu and the switcher. A core from before it answers an error.
  | { topic: "chatSearch"; scope: string; query: string; station?: string; exclude?: string; limit?: number; messages?: number }
  // What a few words find in a workspace, on the device and on every station (docs/search.md, views/search.ts): ⌘K and
  // the phone's search. With `kind`, that kind alone, more of it.
  | { topic: "search"; scope: string; query: string; kind?: string; limit?: number }
  // The archived chats of a scope's stations online, newest first by day (client/core-ts/src/views/archive.ts).
  | { topic: "archive"; scope: string; q?: string; limit?: number }
  // A new chat's page in a scope: its stations, the one it starts on and what it runs there, as last picked here.
  | { topic: "newChat"; scope: string }
  // Where something another app shares goes (`source` what is shared, `query` narrowing the chats): docs/share-in.md.
  | { topic: "shareIn"; scope: string; source: string; query?: string }
  // A model control: what it runs on now and what its panel picked (`of`: new, session:<key>, connect:<id>, connect-new).
  | { topic: "pick"; station: string; of: string }
  // A chat's services and background jobs as its pages show them (the same thread or session as its `chat`).
  // A chat's agent in brief, for its card over its avatar: what it did, cost and used, its account and quota, its jobs.
  | { topic: "agentCard"; station: string; key: string }
  // What a chat's agents and other chats' wrote each other, not said in it (Letters.tsx).
  | { topic: "chatLetters"; station: string; thread: number }
  // What was said in a chat besides words: its pictures, files, links and pull requests (Things.tsx).
  | { topic: "chatThings"; station: string; thread: number; q?: string }
  | { topic: "chatJobs"; station: string; thread: number }
  | { topic: "chatJobs"; station: string; session: string }
  // An image of a chat open in the preview: the ones beside it, as the chat's page shows them (the same thread or
  // session as its `chat`; `path` the image's).
  | { topic: "imageNear"; station: string; thread: number; path: string }
  | { topic: "imageNear"; station: string; session: string; path: string }
  // The services and jobs left up a long while on the scope's stations that are up.
  | { topic: "longJobs"; scope: string }
  | { topic: "fleet"; scope: string }
  | { topic: "profiles"; scope: string }
  // What the agents of a scope's stations spent over its last `days` (7 or 30), by day, person, chat, profile and model
  // (client/core-ts/src/views/usage.ts). A core from before it answers an error.
  | { topic: "usage"; scope: string; days?: number }
  // What the settings say of the scope as a whole: how many stations have the automatic decisions on
  // (client/core-ts/src/views/settings.ts).
  | { topic: "settings"; scope: string }
  | { topic: "resources"; scope: string; station?: string }
  // A job as it is now (kept current by its events).
  | { topic: "job"; station: string; id: string }
  // A folder of a station's drive (docs/drive.md): `root` one of its roots' paths, `path` under it ("" the root itself).
  // Read again each time it is shown; what is held shows meanwhile, a refusal is the topic's error.
  | { topic: "drive"; station: string; root: string; path: string }
  // Where a file of a drive was left on this device (a text's offset, a video's time in ms): null before.
  | { topic: "drivePlace"; station: string; root: string; path: string }
  // A folder of a drive as a place on this device shows it: its order, what is chosen, a tree's folders open, its
  // columns' widths, the keys that act (client/core-ts/src/views/browse.ts; `place` the page's own name for it).
  | { topic: "driveBrowse"; owner: string; place: string; view: string; station: string; root: string; path: string; write?: boolean }
  // The files' page's tabs on this device: null before any.
  | { topic: "filesTabs"; workspace: string }
  // How its person likes it on this device, and what the device is (prefs.ts).
  | { topic: "prefs" }
  // What people set going on this device and the core has not finished: each call that changes something, until it
  // answers (client/core-ts/src/doing.ts; doing.ts).
  | { topic: "doing" }
  | { topic: "composer"; key: string }
  | { topic: "previewLoad"; station: string; port: number }
  // What changed in still.fail, as this app shows it, and what an update brought until `changelog.seen`
  // (client/core-ts/src/changelog.ts).
  | { topic: "changelog" }
  // What each workspace has waiting (how many chats want their person, how many are unread) and the chat last open in
  // it; of those other than `workspace` (the one in view), the most urgent (client/core-ts/src/views/marks.ts).
  | { topic: "workspaceMarks"; workspace?: string }
  // How its members' devices reach a workspace's stations, each way on or off (client/core-ts/src/views/ways.ts).
  | { topic: "workspaceWays"; workspace: string }
  // The workspace's security mode (its lock), and what turning it on would sign (client/core-ts/src/views/lock.ts).
  // A core from before it has neither.
  | { topic: "lock"; workspace: string }
  | { topic: "lockDraft"; workspace: string }
  | { topic: "lockPrompts" }
  // A station in several workspaces (client/core-ts/src/views/memberships.ts): the stations of the viewer's other
  // workspaces that could be added to this one, and the workspaces a station is in. A core from before has neither.
  | { topic: "joinable"; workspace: string }
  | { topic: "memberships"; station: string }
  // A station's screens a person can see and drive (docs/remote-screens.md): a core from before it answers an error.
  | { topic: "screens"; station: string }
  | { topic: "screenCard"; station: string; screen: string }
  // A link to a station's 共享调试 as a message shows it (AdbLink.tsx).
  | { topic: "adbCard"; station: string }
  // The vault (docs/vault.md, client/core-ts/src/views/vault.ts): the viewer's vaults in a workspace and what waits on
  // them; a vault's items. A core from before has neither.
  | { topic: "vaults"; workspace: string }
  | { topic: "vaultItems"; workspace: string; vault: string }
  | { topic: "driveTransfers"; workspace: string }
  // A chat's files being downloaded to this device (client/core-ts views/downloads.ts), how far each has come.
  | { topic: "downloads" }
  | { topic: "vaultUses"; workspace: string; vault: string; item: string };

/** A chat as a page shows it (`client.focus`): by its thread, or its key before it has one; `end`: its end in view. */
export interface ChatShown { station: string; thread: number | null; session: string | null; end?: boolean }

/**
 * Where this page's attention is (`client.focus`, client/core-ts/src/attend.ts): in view, looked at, the chat it shows,
 * the workspace it is in (an id, or `local`). Each field given changes; `chat: null` shows none; `left` says the chat
 * named is not shown any more; `newChat`, that the new chat of the workspace named shows (what it goes back to).
 */
export interface Focus { visible?: boolean; focused?: boolean; chat?: ChatShown | null; left?: ChatShown; workspace?: string; newChat?: string }

export interface ErrorBody {
  code: string;
  message: string;
  status?: number;
}

/** A call or topic that failed; `code` is the core's (still.fail cloud's codes pass through). */
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
  /** Its answer, with the bytes beside it when it carries some (a file read). */
  resolve: (value: unknown, bytes?: Uint8Array) => void;
  reject: (error: Error) => void;
  /** How far the call has got, for one that says so (a file asked for with `progress`); `bytes` beside a value that carries some (a screen view's frame). */
  onProgress?: ((value: unknown, bytes?: Uint8Array) => void) | undefined;
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
  /**
   * The channel is to a worker of the page's own (workerOpener): it ends as the page leaves, and a new one starts if the
   * page comes back. Kept in the back/forward cache with the page, it would be frozen there with the lock the core runs
   * under (worker.ts), and the pages after it would wait on that core for good (an iOS home-screen app coming back from
   * Google's sign-in, 2026-10-09).
   */
  endWithPage?: boolean;
}

// A worker that keeps failing (a broken build, a panic on start) is retried
// with growing pauses rather than in a tight loop.
const RETRY_MS = [0, 1000, 2000, 5000, 10_000, 30_000];
/** A worker that answered before and says nothing this long after the page is back is taken for gone. */
export const WAKE_ANSWER_MS = 5000;

// Promise identity survives thin generated bindings. Only identifying scalar params are retained, never bodies/tokens.
interface CallDetails { name: string; on: Record<string, string | number | boolean>; tracked: boolean }
const calls = new WeakMap<Promise<unknown>, CallDetails>();
let capturing: CallDetails[] | undefined;
/** Identifies the call behind a thin .then/async adapter. Multi-call orchestration keeps local feedback. */
export function captureCall<T>(run: () => Promise<T>): { promise: Promise<T>; details: CallDetails | undefined } {
  const parent = capturing;
  const found: CallDetails[] = [];
  capturing = found;
  try { const promise = run(); return { promise, details: calls.get(promise) ?? (found.length === 1 ? found[0] : undefined) }; }
  finally { capturing = parent; }
}
export const callDetails = (promise: Promise<unknown>) => calls.get(promise);

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
  readonly #endWithPage: boolean;
  /** The page left and its worker ended with it (`endWithPage`): a new one starts once it is back. */
  #left = false;

  constructor(open: Opener, options: ClientOptions = {}) {
    this.#open = open;
    this.#schedule = options.schedule ?? ((ms, run) => void setTimeout(run, ms));
    this.#onFault = options.onFault ?? (() => undefined);
    this.#endWithPage = options.endWithPage ?? false;
    this.#connect();
  }

  /** `signal` stops the call while it is under way; it then fails with `cancelled`. */
  call(name: string, params: unknown = {}, onProgress?: (value: unknown, bytes?: Uint8Array) => void, signal?: AbortSignal): Promise<unknown> {
    return this.#ask(name, params, undefined, onProgress, signal, (resolve) => (value) => resolve(value));
  }

  /**
   * A call with bytes: `bytes` go beside its params (a file's part going up), and it answers with the bytes beside its
   * answer, if any (a file read), never as base64 in either. Otherwise as [call].
   */
  callBytes(name: string, params: unknown, bytes?: Uint8Array, onProgress?: (value: unknown, bytes?: Uint8Array) => void, signal?: AbortSignal): Promise<{ value: unknown; bytes?: Uint8Array }> {
    return this.#ask(name, params, bytes, onProgress, signal, (resolve) => (value, got) => resolve(got === undefined ? { value } : { value, bytes: got }));
  }

  #ask<T>(name: string, params: unknown, bytes: Uint8Array | undefined, onProgress: Pending["onProgress"], signal: AbortSignal | undefined, answered: (resolve: (v: T) => void) => Pending["resolve"]): Promise<T> {
    if (this.#closed) return Promise.reject(new CoreError({ code: "closed", message: t("web-main.core.closed") }));
    if (signal?.aborted) return Promise.reject(new CoreError({ code: "cancelled", message: t("web-main.core.cancelled") }));
    const id = this.#nextId++;
    const promise = new Promise<T>((resolve, reject) => {
      this.#calls.set(id, { resolve: answered(resolve), reject, onProgress });
      this.#send(bytes === undefined ? { id, call: name, params } : { id, call: name, params, bytes });
      signal?.addEventListener("abort", () => {
        if (!this.#calls.has(id)) return;
        // The core answers `cancelled`; with no worker to tell, it is so here and now.
        if (this.#channel) {
          this.#post({ id, cancel: true });
        } else {
          this.#calls.delete(id);
          this.#queue = this.#queue.filter((m) => (m as { id?: number }).id !== id);
          reject(new CoreError({ code: "cancelled", message: t("web-main.core.cancelled") }));
        }
      }, { once: true });
    });
    const on = Object.fromEntries(Object.entries((params ?? {}) as Record<string, unknown>).filter(([k, v]) =>
      !/token|code|password|secret/i.test(k) && (typeof v === "string" || typeof v === "number" || typeof v === "boolean"))) as CallDetails["on"];
    const details = { name, on, tracked: !UNTRACKED_OPERATIONS.has(name) };
    calls.set(promise, details);
    capturing?.push(details);
    return promise;
  }

  /** Values arrive on `onValue` (the whole current value each time, deltas already applied); returns the unsubscribe. */
  subscribe(topic: Topic, onValue: (value: unknown) => void, onError: (error: CoreError) => void): () => void {
    const id = this.#nextId++;
    this.#subs.set(id, { topic, onValue, onError });
    // While the worker is being replaced, #connect subscribes everything anew.
    if (this.#channel) this.#post({ id, subscribe: topic, keyed: true });
    return () => {
      if (this.#subs.delete(id) && this.#channel) this.#post({ id, unsubscribe: true });
    };
  }

  /** Tells the core where this page's attention is (see `Focus`); a core from before it refuses it (`unknown_call`). */
  focus(part: Focus): Promise<unknown> {
    // (a new chat shown is kept by the core as what its workspace goes back to: not said again to a core started anew)
    const { left, newChat: _, ...rest } = part;
    const next: Focus = { ...this.#focus, ...rest };
    if (left && next.chat && same(next.chat, left)) next.chat = null;
    this.#focus = next;
    return this.call("client.focus", part);
  }

  /** The page is going away (or into the back/forward cache): the worker drops this client, or ends (`endWithPage`). */
  suspend(): void {
    if (!this.#channel) return;
    this.#post({ bye: true });
    if (!this.#endWithPage) return;
    this.#channel.close();
    this.#channel = null;
    this.#left = true;
  }

  /**
   * The page is back from the back/forward cache: the worker forgot us (or ended as the page left: a new one), so
   * subscribe again. Calls in flight were lost with the old client.
   */
  resume(): void {
    if (this.#left) return this.#back();
    this.#rejectCalls(t("web-main.core.resumed"));
    if (this.#channel) for (const [id, sub] of this.#subs) this.#post({ id, subscribe: sub.topic, keyed: true });
    this.#refocus();
  }

  /**
   * Back after its worker ended with the page leaving: what was asked of that one is lost, and a new one is told every
   * subscription and where the page is.
   */
  #back(): void {
    this.#rejectCalls(t("web-main.core.resumed"));
    this.#left = false;
    this.#connect();
  }

  /**
   * The page is back after `away` ms hidden (a phone's page frozen in the background): the core gives up what went
   * out before and reconnects (client/core-ts/src/wake.ts). A worker that was up and now says nothing at all is gone
   * (the system can end it without a word to its port): a new one is started.
   */
  wake(away: number): void {
    if (this.#closed) return;
    // Shown again after leaving without the cache bringing it back (no pageshow said so): its worker is started anew.
    if (this.#left) this.#back();
    const channel = this.#channel;
    const heard = this.#heard;
    // With the worker being replaced it waits in the queue: a worker joined again (a shared one) is the same core.
    this.call("client.wake", { away: Math.max(0, Math.round(away)) }).catch(() => undefined);
    if (!this.#up || !channel) return;
    this.#schedule(WAKE_ANSWER_MS, () => {
      if (this.#channel !== channel || this.#heard !== heard) return;
      // A worker only frozen longer than this, not gone, drops this page's client rather than keep it.
      this.#post({ bye: true });
      this.#restart(t("web-main.core.wakeSilent"));
    });
  }

  /**
   * The device's network changed (it came back online): every connection the core has was on the old one, so all
   * that is under way is given up and opened anew (client/core-ts/src/wake.ts). A core from before this takes it for a
   * wake after no time away, which does nothing.
   */
  networkChanged(): void {
    if (this.#closed) return;
    this.call("client.wake", { away: 0, network: true }).catch(() => undefined);
  }

  /**
   * A person asked to try again (重试 where a station or still.fail cloud shows down): what waits stops waiting, and
   * the connections are tried against new ones, but nothing under way is failed (client/core-ts/src/wake.ts). `network`
   * goes with it for a core from before `retry`, which takes it for the network changed.
   */
  retry(): void {
    if (this.#closed) return;
    this.call("client.wake", { away: 0, network: true, retry: true }).catch(() => undefined);
  }

  close(): void {
    this.#closed = true;
    this.#rejectCalls(t("web-main.core.closed"));
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
    for (const [id, sub] of this.#subs) this.#post({ id, subscribe: sub.topic, keyed: true });
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
    this.#rejectCalls(t("web-main.core.restarted"));
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
    const message = data as { id?: number; ok?: unknown; value?: unknown; bytes?: Uint8Array; delta?: DeltaOp[]; error?: ErrorBody; fatal?: string; fault?: WorkerFault; retired?: boolean; rejoin?: boolean };
    // A newer build's core took over: this page is of the older build, so it loads the newer one.
    if (message.retired) {
      reload("retired");
      return;
    }
    // The core this page talked to went with its tab; another tab's worker runs it now: this page asks it again.
    if (message.rejoin) {
      this.resume();
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
        call.onProgress?.(message.value, message.bytes);
        return;
      }
      this.#calls.delete(message.id);
      if (message.error) call.reject(new CoreError(message.error));
      else call.resolve(message.ok, message.bytes);
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

/**
 * Opens a channel to this tab's core worker (worker.ts: one of the tabs' workers runs the core, the others relay to
 * it). The browser is asked to keep what the core stores (it is the only copy of what was sent offline).
 */
export function workerOpener(): Opener {
  void navigator.storage?.persist?.().catch(() => false);
  return (onMessage, onFail) => {
    const receive = (event: MessageEvent) => {
      onMessage(event.data);
    };
    // Spelled out: Vite bundles a worker only from a literal `new Worker(new URL(…, import.meta.url))`.
    const worker = new Worker(new URL("./worker.ts", import.meta.url), { type: "module", name: workerName });
    worker.onmessage = receive;
    worker.onerror = (event) => onFail(event.message || t("web-main.core.workerFailed"));
    return { post: (message) => worker.postMessage(message), close: () => worker.terminate() };
  };
}

function same(a: ChatShown, b: ChatShown): boolean {
  return a.station === b.station && ((a.thread !== null && a.thread === b.thread) || (a.session !== null && a.session === b.session));
}

/** Starts (or joins) the core and keeps the page's client in step with the page's lifecycle. */
export function connectCore(): CoreClient {
  const client = new CoreClient(workerOpener(), { onFault: (error) => captureException(error, { source: "core" }), endWithPage: true });
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
  // In view, and looked at: what is read and which notices this page leaves out follow (client/core-ts/src/attend.ts).
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
  return client;
}
