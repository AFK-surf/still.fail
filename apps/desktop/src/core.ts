// The client core in the desktop app's utility process (docs/client-core.md):
// client/node's core, with one MessagePort per page, as the web's worker has
// one per tab (web/src/core/worker.ts). Pages post messages as objects; the
// core takes JSON and answers JSON, which goes to the page as it is.
import type { MessagePortMain } from "electron";

/** client/node (stillfail_core.node). */
interface NodeCore {
  connect(): number;
  receive(client: number, json: string): void;
  disconnect(client: number): void;
}
/** `channel`: "beta" for the beta app's core (main.ts BETA). */
type Start = (dataDir: string, cloudOrigin: string, listener: (client: number, json: string) => void, channel?: string) => NodeCore;

const [dataDir, cloudOrigin, addon, channel] = process.argv.slice(2) as [string, string, string, string | undefined];
const { start } = require(addon) as { start: Start };

/** One core and its clients. A panic ends a core; the pages then open new ports, which go to the next one. */
interface Generation {
  core: NodeCore;
  clients: Map<number, MessagePortMain>;
  dead: boolean;
}

function begin(): Generation {
  const generation: Generation = { core: null as unknown as NodeCore, clients: new Map(), dead: false };
  generation.core = start(dataDir, cloudOrigin, (client, json) => {
    // `{"fatal": …}` goes to each of its clients (client/ffi); from the first, new pages get a new core.
    if (!generation.dead && json.startsWith('{"fatal"')) {
      generation.dead = true;
      current = begin();
    }
    generation.clients.get(client)?.postMessage(json);
  }, channel || undefined);
  return generation;
}

let current = begin();

function serve(port: MessagePortMain): void {
  // Connected on the first message, and again after a `bye` if the page comes back from the back/forward cache.
  let client: { generation: Generation; id: number } | null = null;
  const leave = () => {
    if (!client) return;
    client.generation.clients.delete(client.id);
    client.generation.core.disconnect(client.id);
    client = null;
  };
  port.on("message", ({ data }) => {
    if (typeof data === "object" && data !== null && "bye" in data) {
      leave();
      return;
    }
    if (client === null) {
      client = { generation: current, id: current.core.connect() };
      current.clients.set(client.id, port);
    }
    client.generation.core.receive(client.id, JSON.stringify(data));
  });
  // The page closed or reloaded.
  port.on("close", leave);
  port.start();
}

process.parentPort.on("message", ({ ports }) => {
  const port = ports[0];
  if (port) serve(port);
});

// An error in this process's own code, handed to one page for error tracking as the worker does.
process.on("uncaughtException", (error) => {
  console.error("still.fail core:", error);
  const port = current.clients.values().next().value;
  port?.postMessage(JSON.stringify({ fault: { name: error.name, message: error.message, ...(error.stack ? { stack: error.stack } : {}) } }));
});
