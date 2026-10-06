// The worker that runs the core (docs/client-core.md, docs/core-db.md). Every tab has a dedicated worker of its own;
// one of them runs the core: the one holding the Web Lock `stillfail-core`, as the core's databases are SQLite on
// OPFS, whose access handles only one worker can hold. The other tabs' workers relay their page's messages to it over
// a BroadcastChannel and what it says back; when the tab running the core goes, the lock goes to another worker, which
// starts the core from the same databases, and every page subscribes again (`rejoin`).
// The core is the TypeScript one (client/core-ts, its web host; docs/core-ts.md); of Rust only iroh is left,
// client/iroh-wasm, loaded once the mesh is first needed while the core starts from its database.
import { startWeb, type WasmSqlite, type WebCore } from "@stillfail/core-ts/web";
import { BUILT_AT } from "./built.ts";
import initIroh, * as iroh from "./iroh-pkg/stillfail_iroh_wasm.js";
import type { WorkerFault } from "./client.ts";

// Typed by hand: the web tsconfig has the DOM lib, not the worker's.
interface Port {
  postMessage(message: unknown): void;
  onmessage: ((event: MessageEvent) => void) | null;
}

const scope = globalThis as unknown as Port & {
  close(): void;
  addEventListener(type: "error", listener: (event: ErrorEvent) => void): void;
  addEventListener(type: "unhandledrejection", listener: (event: PromiseRejectionEvent) => void): void;
};

/** This tab's worker, among the others of this origin. */
const tab = crypto.randomUUID();
/** The lock the worker running the core holds; each worker holds one of its own for as long as it lives. */
const CORE_LOCK = "stillfail-core";
const tabLock = (id: string) => `stillfail-tab-${id}`;
// The channel the workers of this origin and build talk on (another build's workers retire, below).
const relay = new BroadcastChannel(`stillfail-core-${BUILT_AT}`);

/// What the workers say to each other: a worker started (`hello`); who runs the core (`leader`, to one or all); a
/// page's message to the core (`up`), and the core's to a page (`down`).
type Relayed =
  | { hello: string }
  | { leader: string; to?: string }
  | { from: string; to: string; up: unknown }
  | { from: string; to: string; down: unknown };

let core: WebCore | null = null;
let dead = false;
/** The worker running the core: this one once it holds the lock; null until it is known. */
let leader: string | null = null;
/** What this page said before the core was known, in order. */
let queued: unknown[] = [];
/** This page's client of the core when it runs here. */
let mine: number | null = null;
/** The other tabs' clients of the core running here, by their worker. */
const remotes = new Map<string, number>();
const clients = new Map<number, (message: unknown) => void>();

function toPage(message: unknown): void {
  try {
    scope.postMessage(message);
  } catch {
    // The page is gone; this worker goes with it.
  }
}

function emit(client: number, message: unknown): void {
  const send = clients.get(client);
  if (!send) return;
  try {
    send(message);
  } catch {
    // A port that cannot take messages any more is gone. Not from inside
    // emit: the core is in the middle of something.
    queueMicrotask(() => gone(client));
  }
}

function gone(client: number): void {
  if (!clients.delete(client)) return;
  for (const [id, c] of remotes) if (c === client) remotes.delete(id);
  if (mine === client) mine = null;
  guard(() => core?.disconnect(client));
}

/**
 * A bug that ended one of the core's fibers (or a panic in iroh's wasm, a
 * RuntimeError from then on): this core is finished. Tell this page, which
 * starts a new worker, and end this one (its lock goes to another tab's).
 */
function fatal(reason: string): void {
  if (dead) return;
  dead = true;
  console.error("still.fail core: fatal:", reason);
  toPage({ fatal: reason });
  relay.close();
  scope.close();
}

/**
 * An error the core survives: logged here, and handed to this page for error
 * tracking (a worker's console is out of the page's reach).
 */
function fault(error: unknown): void {
  console.error("still.fail core:", error);
  const fault: WorkerFault = error instanceof Error
    ? { name: error.name, message: error.message, ...(error.stack ? { stack: error.stack } : {}) }
    : { name: "Error", message: String(error) };
  toPage({ fault });
}

function guard(run: () => void): void {
  try {
    run();
  } catch (error) {
    if (error instanceof WebAssembly.RuntimeError) fatal(String(error));
    else fault(error);
  }
}

/**
 * One core per browser: a tab still on an earlier build keeps that build's worker, and two cores on the same storage
 * would race each other (a login refreshed twice is taken for theft). So the workers of this origin say which build
 * they are; an older one retires, and its pages reload onto this build.
 */
// The channel keeps its name from before the rename: a worker of a build from before it must hear of this one and retire.
const builds = new BroadcastChannel("ember-core-builds");
builds.onmessage = (event: MessageEvent) => {
  const other = (event.data as { built?: unknown } | null)?.built;
  if (typeof other !== "number" || other === BUILT_AT) return;
  if (other > BUILT_AT) retire();
  // An older one started after this: it hears of this one and retires.
  else builds.postMessage({ built: BUILT_AT });
};
builds.postMessage({ built: BUILT_AT });

function retire(): void {
  if (dead) return;
  dead = true;
  toPage({ retired: true });
  builds.close();
  relay.close();
  scope.close();
}

/** iroh's wasm, loaded once, the first time the core's mesh binds. */
let irohLoaded: Promise<typeof iroh> | null = null;
const loadIroh = () => (irohLoaded ??= initIroh().then(() => iroh));

/**
 * SQLite's WASM build and its pool of OPFS files (opfs-sahpool), loaded by the worker running the core alone: the
 * pool holds every file it has, so no other worker could.
 */
const loadSqlite = async (): Promise<WasmSqlite> => {
  const { default: init } = await import("@sqlite.org/sqlite-wasm");
  const sqlite3 = await init();
  // A browser without OPFS's synchronous handles has no pool: the databases are in memory this run (the core says so).
  const pool = await sqlite3.installOpfsSAHPoolVfs({ name: "stillfail", directory: "/stillfail-core", initialCapacity: 6 }).catch((error: unknown) => {
    console.error("still.fail core: no OPFS pool:", error);
    return null;
  });
  const noPool = () => {
    throw new Error("OPFS is not available here");
  };
  return {
    open: (path) => (pool ? new pool.OpfsSAHPoolDb(path) : noPool()) as never,
    memory: () => new sqlite3.oo1.DB(":memory:") as never,
    unlink: (path) => pool?.unlink(path) ?? false,
    reserve: async (files) => {
      if (pool) await pool.reserveMinimumCapacity(pool.getFileCount() + files);
    },
  };
};

// ── the page ──

/** What this page says goes to the core, where it runs. */
scope.onmessage = (event) => {
  const data: unknown = event.data;
  if (dead) return;
  if (core !== null) return local(data);
  if (leader === null) {
    queued.push(data);
    return;
  }
  relay.postMessage({ from: tab, to: leader, up: data } satisfies Relayed);
};

/** A message of this page to the core running here. */
function local(data: unknown): void {
  const running = core!;
  if (typeof data === "object" && data !== null && "bye" in data) {
    if (mine !== null) gone(mine);
    return;
  }
  guard(() => {
    if (mine === null) {
      mine = running.connect();
      clients.set(mine, toPage);
    }
    running.receive(mine, data);
  });
}

// ── the other workers ──

relay.onmessage = (event: MessageEvent) => {
  const data = event.data as Relayed;
  if (dead || typeof data !== "object" || data === null) return;
  if ("hello" in data) {
    // A worker started: told who runs the core, if it is this one.
    if (core !== null) relay.postMessage({ leader: tab, to: data.hello } satisfies Relayed);
    return;
  }
  if ("leader" in data) {
    if (data.to !== undefined && data.to !== tab) return;
    follow(data.leader);
    return;
  }
  if (data.to !== tab) return;
  if ("up" in data) {
    if (core !== null) fromTab(data.from, data.up);
  } else if (core === null && data.from === leader) {
    // What the core running elsewhere says to this page.
    toPage(data.down);
  }
};

/** The core runs in worker `id`: what was queued goes to it; when it is another than before, the page subscribes anew. */
function follow(id: string): void {
  if (core !== null || id === leader) return;
  const before = leader;
  leader = id;
  if (before !== null) {
    // The core this page talked to is gone: what was asked of it is lost, and the page asks the new one again.
    queued = [];
    toPage({ rejoin: true });
    return;
  }
  const waiting = queued;
  queued = [];
  for (const message of waiting) relay.postMessage({ from: tab, to: id, up: message } satisfies Relayed);
}

/** A message of another tab's page to the core running here. */
function fromTab(id: string, message: unknown): void {
  void ready?.then((running) => {
    if (dead) return;
    let client = remotes.get(id);
    if (typeof message === "object" && message !== null && "bye" in message) {
      if (client !== undefined) gone(client);
      return;
    }
    guard(() => {
      if (client === undefined) {
        client = running.connect();
        remotes.set(id, client);
        clients.set(client, (out) => relay.postMessage({ from: tab, to: id, down: out } satisfies Relayed));
        // That tab's worker holds its own lock for as long as it lives: granted here once it is gone.
        const c = client;
        void navigator.locks.request(tabLock(id), () => {
          if (remotes.get(id) === c) gone(c);
        });
      }
      running.receive(client, message);
    });
  });
}

// ── who runs the core ──

let ready: Promise<WebCore> | null = null;

// This worker's own lock, held as long as it lives (the worker running the core hears when it is gone).
void navigator.locks.request(tabLock(tab), () => new Promise<void>(() => {}));
// Asks who runs the core; one that does answers.
relay.postMessage({ hello: tab } satisfies Relayed);
// Runs the core once the lock is this worker's: at once when no other tab runs one, else when it goes.
void navigator.locks.request(CORE_LOCK, async () => {
  if (dead) return;
  const followed = leader !== null;
  // On the test channel the page names the worker so (core/client.ts workerName): the core's words say youdid.wtf.
  // A defect's stack goes to error tracking first (as a fault): the fatal the pages hear is its message only.
  ready = startWeb(emit, (globalThis as { name?: string }).name?.endsWith("-test") ?? false, loadIroh, (reason, error) => {
    if (!dead) fault(error);
    fatal(reason);
  }, loadSqlite);
  ready.catch((error: unknown) => fatal(`核心没有启动：${String(error)}`));
  const running = await ready;
  core = running;
  leader = tab;
  relay.postMessage({ leader: tab } satisfies Relayed);
  if (followed) {
    // This page talked to the core of another tab, gone now: it asks this one again.
    queued = [];
    toPage({ rejoin: true });
  } else {
    const waiting = queued;
    queued = [];
    for (const message of waiting) local(message);
  }
  // Held until this worker ends.
  await new Promise<void>(() => {});
});

// Errors in the core's own tasks surface here, not at a call.
scope.addEventListener("error", (event) => {
  if (event.error instanceof WebAssembly.RuntimeError) fatal(String(event.error));
  else fault(event.error ?? event.message);
  // Handled: a dedicated Worker's page would otherwise take it as the worker failing.
  event.preventDefault();
});
scope.addEventListener("unhandledrejection", (event) => {
  if (event.reason instanceof WebAssembly.RuntimeError) fatal(String(event.reason));
  else fault(event.reason);
  event.preventDefault();
});
