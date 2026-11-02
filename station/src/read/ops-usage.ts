// The reads of usage, the machine's own sessions, the agents' memory and the host (src/api/routes/usage.ts asks them).
// The request's language comes in the args (`lang`), as these words are said outside views.ts.
import type { ReadOp } from "./ops.ts";
import { hostInfo } from "./host.ts";
import { machineSession, machineSessions } from "./machine.ts";
import { memory } from "./memory.ts";
import { resourceChats, usage } from "./usage.ts";
import { HOME, type Of, outflowChats, outflowMessages, outflowThread, outflowUsage } from "./outflow.ts";

/// A whole number from the args (another station's may say anything), else 0.
const num = (v: unknown): number => (typeof v === "number" && Number.isSafeInteger(v) ? v : 0);
/// The workspace whose chats an outflow read reads: as another station asked it, else the home one.
const outflowOf = (ws: unknown): Of =>
  ws !== null && typeof ws === "object" && typeof (ws as Of).workspace === "string" ? { workspace: (ws as Of).workspace, home: (ws as Of).home === true } : HOME;
/// A span of usage read at once, at most (outflow/server.ts says so to its programs).
const SPAN_MAX_MS = 31 * 24 * 60 * 60_000;

export const usageOps: Record<string, ReadOp> = {
  // `reading`: the counter's readingAll (absent: true).
  // `history`: the whole of it by day as well (usage.ts usageHistory).
  usage: (store, a) => usage(store, a.lang, BigInt(a.from), BigInt(a.to), BigInt(a.tz), typeof a.reading === "boolean" ? a.reading : true, a.viewer ?? null, a.history === true),
  resourceChats: (store, a) => resourceChats(store, a.sessions ?? [], a.viewer ?? null),
  // What a program granted data outflow reads (docs/data-outflow.md), in its version's shape.
  // `ws`: another station's program reads the chats of that workspace (outflow/module.ts); absent, the home one's.
  outflowUsage: (store, a) => outflowUsage(store, a.lang, num(a.from), Math.min(num(a.to), num(a.from) + SPAN_MAX_MS), Math.max(-1440, Math.min(num(a.tz), 1440)), outflowOf(a.ws)),
  // `limit`: a page of them, after `before`; absent, all.
  outflowChats: (store, a) =>
    outflowChats(store, num(a.since), outflowOf(a.ws), typeof a.limit === "number" ? { limit: Math.min(Math.max(num(a.limit), 1), 1000), before: typeof a.before === "string" ? a.before : null } : null),
  // The chat by its `thread`, a `session` of it, or its `channel` and `ts`.
  outflowMessages: (store, a) => {
    const thread = outflowThread(store, a);
    return thread === null ? null : outflowMessages(store, thread, num(a.after), Math.min(Math.max(num(a.limit), 1), 500), outflowOf(a.ws));
  },
  machineSessions: (store) => machineSessions(store),
  machineSession: (store, a) => machineSession(store, a.lang, a.runtime, a.id, a.limit),
  memory: (store) => memory(store.dataDir),
  host: (store, a) => hostInfo(store.dataDir, a.seen),
};
