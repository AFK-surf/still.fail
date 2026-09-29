// The worker that runs the core (docs/client-core.md). As a SharedWorker every
// tab connects a port; as a dedicated Worker (no SharedWorker, e.g. Chrome on
// Android) the global scope is the one port. Each port is one core client.
import { BUILT_AT } from "./built.ts";
import init, { start, type StillFailCore } from "./pkg/stillfail_core_wasm.js";
import type { WorkerFault } from "./client.ts";

// Typed by hand: the web tsconfig has the DOM lib, not the worker's.
interface Port {
  postMessage(message: unknown): void;
  onmessage: ((event: MessageEvent) => void) | null;
}

const scope = globalThis as unknown as Port & {
  onconnect?: ((event: MessageEvent) => void) | null;
  close(): void;
  addEventListener(type: "error", listener: (event: ErrorEvent) => void): void;
  addEventListener(type: "unhandledrejection", listener: (event: PromiseRejectionEvent) => void): void;
};

const clients = new Map<number, Port>();
const ports = new Set<Port>();
let core: StillFailCore | null = null;
let dead = false;

function emit(client: number, message: unknown): void {
  const port = clients.get(client);
  if (!port) return;
  try {
    port.postMessage(message);
  } catch {
    // A port that cannot take messages any more is gone. Not from inside
    // emit: the core is in the middle of something.
    queueMicrotask(() => gone(client));
  }
}

function gone(client: number): void {
  if (!clients.delete(client)) return;
  guard(() => core?.disconnect(client));
}

/**
 * A panic aborts the wasm instance (a RuntimeError from then on): this core is
 * finished. Tell every page, which starts a new worker, and end this one.
 */
function fatal(reason: string): void {
  if (dead) return;
  dead = true;
  console.error("still.fail core: fatal:", reason);
  for (const port of ports) {
    try {
      port.postMessage({ fatal: reason });
    } catch { /* gone already */ }
  }
  scope.close();
}

/**
 * An error the core survives: logged here, and handed to one page for error
 * tracking (a worker's console is out of the page's reach). One page, so that
 * several tabs do not report it several times; the page reports the fatal ones itself.
 */
function fault(error: unknown): void {
  console.error("still.fail core:", error);
  const port = clients.values().next().value;
  if (!port) return;
  const fault: WorkerFault = error instanceof Error
    ? { name: error.name, message: error.message, ...(error.stack ? { stack: error.stack } : {}) }
    : { name: "Error", message: String(error) };
  try {
    port.postMessage({ fault });
  } catch { /* gone; its client is dropped on the next emit */ }
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
 * One core per browser: a tab still on an earlier build keeps that build's worker (another script, so another shared
 * worker), and two cores on the same storage would race each other (a login refreshed twice is taken for theft). So
 * the workers of this origin say which build they are; an older one retires, and its pages reload onto this build.
 */
// The channel keeps its name from before the rename: a worker of a build from before it must hear of this one and retire.
const builds = typeof BroadcastChannel === "undefined" ? null : new BroadcastChannel("ember-core-builds");
if (builds) {
  builds.onmessage = (event: MessageEvent) => {
    const other = (event.data as { built?: unknown } | null)?.built;
    if (typeof other !== "number" || other === BUILT_AT) return;
    if (other > BUILT_AT) retire();
    // An older one started after this: it hears of this one and retires.
    else builds.postMessage({ built: BUILT_AT });
  };
  builds.postMessage({ built: BUILT_AT });
}

function retire(): void {
  if (dead) return;
  dead = true;
  for (const port of ports) {
    try {
      port.postMessage({ retired: true });
    } catch { /* gone already */ }
  }
  builds?.close();
  scope.close();
}

const ready: Promise<StillFailCore> = (async () => {
  await init();
  core = await start(emit);
  return core;
})();
ready.catch((error: unknown) => fatal(`核心没有启动：${String(error)}`));

function serve(port: Port): void {
  ports.add(port);
  // Connected on the first message, and again after a `bye` if the page comes
  // back from the back/forward cache.
  let client: number | null = null;
  port.onmessage = (event) => {
    const data: unknown = event.data;
    // Every message waits on the same promise, so they keep their order.
    void ready.then((core) => {
      if (dead) return;
      if (typeof data === "object" && data !== null && "bye" in data) {
        if (client !== null) gone(client);
        client = null;
        return;
      }
      guard(() => {
        if (client === null) {
          client = core.connect();
          clients.set(client, port);
        }
        core.receive(client, data);
      });
    }, () => undefined);
  };
}

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

if ("onconnect" in globalThis) {
  scope.onconnect = (event) => {
    const port = event.ports[0];
    if (port) serve(port);
  };
} else {
  serve(scope);
}
