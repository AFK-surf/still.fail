import { Worker } from "node:worker_threads";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { releaseStoppedBackfill } from "./backfill.ts";
import { hasLegacySaid, legacySaidMaintenanceStep, legacySaidNeedsWork } from "./legacy-said-build.ts";
import { hasLegacyAgent, legacyAgentMaintenanceStep, legacyAgentNeedsWork } from "./legacy-agent-build.ts";
import type { Store } from "./store.ts";

type Kind = "legacy-said" | "legacy-agent";
type Lookup = { kind: Kind; needsWork: () => boolean; step: () => { done: boolean; visited: number } };

/// Keep an old store readable during handover. One worker takes turns preparing its missing entry lookups, so one
/// steadily changing lookup cannot starve another and their transactions still yield to foreground writes.
function buildLookups(store: Store, previous: Promise<void>, kinds: readonly Kind[], workerFile?: URL): {
  ready: Promise<boolean>; wake: () => void; close: () => Promise<void>;
} {
  const { promise: ready, resolve } = Promise.withResolvers<boolean>();
  const lookups: Lookup[] = [];
  if (kinds.includes("legacy-said") && hasLegacySaid(store.db)) lookups.push({ kind: "legacy-said",
    needsWork: () => legacySaidNeedsWork(store.db), step: () => legacySaidMaintenanceStep(store.db) });
  if (kinds.includes("legacy-agent") && hasLegacyAgent(store.db)) lookups.push({ kind: "legacy-agent",
    needsWork: () => legacyAgentNeedsWork(store.db), step: () => legacyAgentMaintenanceStep(store.db) });
  const path = store.db.location();
  const work = new Fibers("old message lookup", store.clock);
  let worker: Worker | null = null;
  let retryCancel: (() => void) | null = null, memoryCancel: (() => void) | null = null;
  let allowed = false, closed = false, requested = false, retryMs = 250, next = 0;
  let off: () => void = () => {};
  const nextLookup = (): Lookup | null => {
    for (let i=0;i<lookups.length;i++) {
      const index = (next+i)%lookups.length, lookup = lookups[index];
      if (lookup.needsWork()) { next = (index+1)%lookups.length; return lookup; }
    }
    return null;
  };
  const retry = () => {
    if (closed || retryCancel !== null) return;
    const ms = retryMs;
    retryMs = Math.min(retryMs * 2, 30_000);
    retryCancel = work.after(ms, () => { retryCancel = null; start(); });
  };
  const memoryStep = () => {
    memoryCancel = null;
    if (closed) return;
    try {
      requested = false;
      const lookup = nextLookup();
      if (!lookup) { retryMs = 250; resolve(true); return; }
      lookup.step();
      memoryCancel = work.after(20, memoryStep);
    } catch (error) {
      log.warn("store", "an old message lookup batch stopped", { error: (error as Error).message });
      retry();
    }
  };
  const start = () => {
    if (lookups.length === 0 || !allowed || closed || worker !== null || retryCancel !== null || memoryCancel !== null) return;
    try {
      if (!lookups.some((lookup) => lookup.needsWork())) { requested = false; retryMs = 250; resolve(true); return; }
    } catch (error) {
      log.warn("store", "the old message lookup could not be checked", { error: (error as Error).message });
      retry();
      return;
    }
    if (path === null) { memoryStep(); return; }
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts")
      ? "../sessions/workspace-activity-worker.ts" : "./sessions/workspace-activity-worker.js", import.meta.url);
    let current: Worker;
    try { current = new Worker(file, { workerData: { path, priority: store.backfillPriority } }); }
    catch (error) {
      log.warn("store", "the old message lookup worker could not start", { error: (error as Error).message });
      retry();
      return;
    }
    const owner = current.threadId;
    let failed = false, finished = false;
    worker = current;
    current.unref();
    const send = () => {
      try {
        const lookup = nextLookup();
        if (!lookup) { requested = false; retryMs = 250; finished = true; resolve(true); void current.terminate(); return; }
        requested = false;
        current.postMessage({ kind: lookup.kind });
      } catch (error) {
        failed = true;
        log.warn("store", "the old message lookup could not be checked", { error: (error as Error).message });
        void current.terminate();
      }
    };
    current.on("message", (result: { done: boolean; error?: string }) => {
      if (closed || worker !== current) return;
      if (result.error) {
        failed = true;
        log.warn("store", "an old message lookup batch stopped", { error: result.error });
        void current.terminate();
      } else { retryMs = 250; send(); }
    });
    current.once("error", (error) => {
      failed = true;
      log.warn("store", "the old message lookup worker failed", { error: error.message });
    });
    current.once("exit", () => {
      releaseStoppedBackfill(store.backfillPriority, owner);
      if (worker === current) worker = null;
      if (closed) return;
      if (failed || !finished) { requested = true; retry(); }
      else if (requested) start();
    });
    send();
  };
  const wake = () => { requested = true; start(); };
  if (lookups.length > 0) {
    off = store.subscribe((change) => {
      if ((change.type === "thread" && change.entries.length > 0) || change.type === "threadRemoved") wake();
    });
    // An older connection's writes do not notify this Store. Probe one indexed key periodically once handover ends.
    work.every(5_000, () => {
      if (!allowed || closed || worker !== null) return;
      try { if (lookups.some((lookup) => lookup.needsWork())) wake(); }
      catch (error) { log.warn("store", "the old message lookup could not be checked", { error: (error as Error).message }); retry(); }
    });
    void previous.then(() => { allowed = true; wake(); }, (error) => {
      log.warn("store", "could not wait for the previous station before preparing messages", { error: (error as Error).message });
      resolve(false);
    });
  } else resolve(true);
  return {
    ready, wake,
    close: async () => {
      if (closed) return;
      closed = true;
      resolve(false);
      off(); retryCancel?.(); memoryCancel?.();
      await work.close();
      if (worker !== null) await worker.terminate();
    },
  };
}

/// Prepare only the old ordinary-message lookup (also used by its standalone recovery tests).
export function buildLegacySaid(store: Store, previous: Promise<void>, workerFile?: URL): ReturnType<typeof buildLookups> {
  return buildLookups(store,previous,["legacy-said"],workerFile);
}

/// Prepare all entry lookups a store needs after the old station has handed over.
export function buildLegacyEntryLookups(store: Store, previous: Promise<void>, workerFile?: URL): ReturnType<typeof buildLookups> {
  return buildLookups(store,previous,["legacy-said","legacy-agent"],workerFile);
}
