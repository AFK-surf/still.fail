// The reads of usage, the machine's own sessions, the agents' memory and the host (src/api/routes/usage.ts asks them).
// The request's language comes in the args (`lang`), as these words are said outside views.ts.
import type { ReadOp } from "./ops.ts";
import { hostInfo } from "./host.ts";
import { machineSession, machineSessions } from "./machine.ts";
import { memory } from "./memory.ts";
import { resourceChats, usage } from "./usage.ts";
import { outflowChats, outflowMessages, outflowUsage } from "./outflow.ts";

export const usageOps: Record<string, ReadOp> = {
  // `reading`: the counter's readingAll (absent: true).
  usage: (store, a) => usage(store, a.lang, BigInt(a.from), BigInt(a.to), BigInt(a.tz), typeof a.reading === "boolean" ? a.reading : true, a.viewer ?? null),
  resourceChats: (store, a) => resourceChats(store, a.sessions ?? [], a.viewer ?? null),
  // What a program granted data outflow reads (docs/data-outflow.md), in its version's shape.
  outflowUsage: (store, a) => outflowUsage(store, a.lang, a.from, a.to, a.tz),
  outflowChats: (store, a) => outflowChats(store, a.since),
  outflowMessages: (store, a) => outflowMessages(store, a.thread, a.after, a.limit),
  machineSessions: (store) => machineSessions(store),
  machineSession: (store, a) => machineSession(store, a.lang, a.runtime, a.id, a.limit),
  memory: (store) => memory(store.dataDir),
  host: (store, a) => hostInfo(store.dataDir, a.seen),
};
