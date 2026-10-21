// The client core in the desktop app's utility process (docs/client-core.md):
// the TypeScript core on Node (client/core-ts, its hosts/node.ts bundled
// beside this file as core-ts.js; docs/core-ts.md), with one MessagePort per
// page, as the web's worker has one per tab (web/src/core/worker.ts). Pages
// post messages as objects; the host restores selected file sources before the
// core reads them. Answers are JSON. Its iroh is the station's addon (mesh.node).
import { join } from "node:path";
import type { MessagePortMain } from "electron";
import type { CoreFiles as FilePort } from "../../../client/core-ts/src/hosts/file-port.ts";

/** client/core-ts's Node start (the API the Rust core's Node addon had). */
interface NodeCore {
  connect(): number;
  receiveRaw(client: number, message: unknown): void;
  disconnect(client: number): void;
}
/** client/core-ts hosts/node.ts `Sealer`: what seals values for the core. */
interface Sealer {
  get(key: string, user: boolean, reason: string): Promise<Uint8Array | null>;
  set(key: string, value: Uint8Array, user: boolean): Promise<void>;
  delete(key: string): Promise<void>;
  ask(reason: string): Promise<void>;
}
/** `channel`: "beta" for the beta app's core (main.ts BETA). */
/** `bytes`: beside the JSON of a message that carries some (a screen view's frame). */
/** `sealer`: what the main process seals for it (main.ts `sealedFiles`), where it does. */
type Start = (dataDir: string, cloudOrigin: string, listener: (client: number, json: string, bytes?: Uint8Array) => void, channel?: string, options?: { sealer?: Sealer }) => NodeCore;

const [dataDir, cloudOrigin, mesh, channel, sealing] = process.argv.slice(2) as [string, string, string, string | undefined, string | undefined];
process.env.STILLFAIL_MESH_NATIVE ??= mesh;
const { start, CoreFiles } = require(join(__dirname, "core-ts.js")) as { start: Start; CoreFiles: new (send: (message: unknown) => void) => FilePort };

/** Asks of what is sealed, waiting for the main process's answer by id; the bytes go as base64. */
const sealedWaiting = new Map<number, { resolve: (value: string | null | undefined) => void; reject: (error: Error) => void }>();
let sealedNext = 1;
function askSealed(ask: { op: "get" | "set" | "delete" | "ask"; key: string; user?: boolean; reason?: string; value?: string }): Promise<string | null | undefined> {
  return new Promise((resolve, reject) => {
    const id = sealedNext++;
    sealedWaiting.set(id, { resolve, reject });
    process.parentPort.postMessage({ sealed: { id, ...ask } });
  });
}
const sealer: Sealer | undefined = sealing === "sealed"
  ? {
      get: async (key, user, reason) => {
        const value = await askSealed({ op: "get", key, user, reason });
        return typeof value === "string" ? new Uint8Array(Buffer.from(value, "base64")) : null;
      },
      set: async (key, value, user) => void (await askSealed({ op: "set", key, user, value: Buffer.from(value).toString("base64") })),
      delete: async (key) => void (await askSealed({ op: "delete", key })),
      ask: async (reason) => void (await askSealed({ op: "ask", key: "", reason })),
    }
  : undefined;

/** One core and its clients. A panic ends a core; the pages then open new ports, which go to the next one. */
interface Generation {
  core: NodeCore;
  clients: Map<number, MessagePortMain>;
  dead: boolean;
}

function begin(): Generation {
  const generation: Generation = { core: null as unknown as NodeCore, clients: new Map(), dead: false };
  generation.core = start(dataDir, cloudOrigin, (client, json, bytes) => {
    // `{"fatal": …}` goes to each of its clients (a bug that ended the core); from the first, new pages get a new core.
    if (!generation.dead && json.startsWith('{"fatal"')) {
      generation.dead = true;
      current = begin();
    }
    // A message with bytes (a screen view's frame, a file read) goes as its JSON and the bytes beside it, not as base64 in the JSON
    // (web/src/core/client.ts desktopOpener reads both).
    generation.clients.get(client)?.postMessage(bytes === undefined ? json : { json, bytes });
  }, channel || undefined, sealer ? { sealer } : {});
  return generation;
}

let current = begin();

function serve(port: MessagePortMain): void {
  const files = new CoreFiles((message) => port.postMessage(message));
  // Connected on the first message, and again after a `bye` if the page comes back from the back/forward cache.
  let client: { generation: Generation; id: number } | null = null;
  const leave = () => {
    if (!client) return;
    client.generation.clients.delete(client.id);
    client.generation.core.disconnect(client.id);
    client = null;
  };
  port.on("message", ({ data }) => {
    if (files.receive(data)) return;
    if (typeof data === "object" && data !== null && "bye" in data) {
      leave();
      return;
    }
    if (client === null) {
      client = { generation: current, id: current.core.connect() };
      current.clients.set(client.id, port);
    }
    client.generation.core.receiveRaw(client.id, files.prepare(data));
  });
  // The page closed or reloaded.
  port.on("close", () => { files.close(); leave(); });
  port.start();
}

process.parentPort.on("message", ({ data, ports }) => {
  // The main process's answer to an ask of what is sealed.
  const answer = (data as { sealed?: { id: number; value?: string | null; error?: string } } | null)?.sealed;
  if (answer) {
    const waiting = sealedWaiting.get(answer.id);
    sealedWaiting.delete(answer.id);
    if (answer.error !== undefined) waiting?.reject(new Error(answer.error));
    else waiting?.resolve(answer.value);
    return;
  }
  const port = ports[0];
  if (port) serve(port);
});

// An error in this process's own code, handed to one page for error tracking as the worker does.
process.on("uncaughtException", (error) => {
  process.parentPort.postMessage({ diagnostic: { name: error.name, message: error.message, stack: error.stack } });
  console.error("still.fail core:", error);
  const port = current.clients.values().next().value;
  port?.postMessage(JSON.stringify({ fault: { name: error.name, message: error.message, ...(error.stack ? { stack: error.stack } : {}) } }));
});
