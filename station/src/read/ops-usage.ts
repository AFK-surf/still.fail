// The reads of usage, the machine's own sessions and the agents' memory (src/api/routes/usage.ts asks them).
// The request's language comes in the args (`lang`), as these words are said outside views.ts.
import type { ReadOp } from "./ops.ts";
import { machineSession, machineSessions } from "./machine.ts";
import { memory } from "./memory.ts";
import { HttpError } from "./views.ts";
import { resourceChats, usage } from "./usage.ts";
import { usageCallsPage } from "./store.ts";
import { usageTurns } from "../store/usage.ts";
import { HOME, type Of, outflowChats, outflowMessages, outflowUsage } from "./outflow.ts";
import type { PageBase } from "../sessions/page.ts";

/// A whole number from the args (another station's may say anything), else 0.
const num = (v: unknown): number => (typeof v === "number" && Number.isSafeInteger(v) ? v : 0);
/// The workspace whose chats a statistics read reads: as another station asked it, else the home one.
const outflowOf = (ws: unknown): Of =>
  ws !== null && typeof ws === "object" && typeof (ws as Of).workspace === "string" ? { workspace: (ws as Of).workspace, home: (ws as Of).home === true } : HOME;
/// Where the session pages are, as the station gave it; null when it gave none.
const pagesOf = (p: unknown): PageBase | null => {
  const v = p as PageBase | null | undefined;
  return v !== null && typeof v === "object" && typeof v.origin === "string" && typeof v.workspace === "string" && typeof v.station === "string"
    ? { origin: v.origin, workspace: v.workspace, station: v.station } : null;
};
/// A span of usage read at once, at most (as a Comma connect reads it, comma/stats.ts).
const SPAN_MAX_MS = 31 * 24 * 60 * 60_000;

export const usageOps: Record<string, ReadOp> = {
  /// The turns a part of a transcript's calls were made in, for the usage counter (usage/counter.ts).
  usageTurns: (store, a) => usageTurns(store.db, String(a.session), Number(a.from), Number(a.until)),
  // `reading`: the counter's readingAll (absent: true).
  // `history`: the page's year by day as well (usage.ts usageHistory; `historyRange`, its days).
  usage: (store, a) => usage(store, a.lang, BigInt(a.from), BigInt(a.to), BigInt(a.tz), typeof a.reading === "boolean" ? a.reading : true, a.viewer ?? null, a.history === true,
    { ...(a.historyRange ? { historyRange: { from: BigInt(a.historyRange.from), to: BigInt(a.historyRange.to) } } : {}),
      ...(a.detailsPreparing === true ? { detailsPreparing: true } : {}),
      ...(a.batchedSummary ? { batched: a.batchedSummary } : {}) }),
  usageCalls: (store, a) => usageCallsPage(store, String(a.session), BigInt(a.from), BigInt(a.to), [BigInt(a.beforeAt), BigInt(a.beforeSeq)],
    Math.min(Math.max(num(a.limit), 1), 200), a.viewer ?? null),
  resourceChats: (store, a) => resourceChats(store, a.sessions ?? [], a.viewer ?? null),
  // The workspace's statistics a Comma connect sends (comma/stats.ts), of this station: named as stations of every
  // version answer them (`outflow.read`, comma/peer.ts). `ws`: the workspace another station asks for; absent, the home one.
  outflowUsage: (store, a) => outflowUsage(store, a.lang, num(a.from), Math.min(num(a.to), num(a.from) + SPAN_MAX_MS), Math.max(-1440, Math.min(num(a.tz), 1440)), outflowOf(a.ws)),
  // `limit`: a page of them, after `before`; absent, all. `pages`: where this station's session pages are (the
  // station gives it, comma/module.ts), to link each chat with.
  outflowChats: (store, a) =>
    outflowChats(store, num(a.since), outflowOf(a.ws), typeof a.limit === "number" ? { limit: Math.min(Math.max(num(a.limit), 1), 1000), before: typeof a.before === "string" ? a.before : null } : null, pagesOf(a.pages)),
  // A chat's messages, as the Router reads it through a Comma connect (`task.read`).
  outflowMessages: (store, a) => outflowMessages(store, num(a.thread), num(a.after), Math.min(Math.max(num(a.limit), 1), 500), outflowOf(a.ws), a.messagesOnly === true),
  machineSessions: (store) => machineSessions(store),
  machineSession: (store, a) => machineSession(store, a.lang, a.runtime, a.id, a.limit),
  memory: (store, a) => {
    try { return memory(store.dataDir, a.workspace); }
    catch (error) {
      if (a.workspace !== undefined) throw new HttpError(400, (error as Error).message);
      throw error;
    }
  },
};
