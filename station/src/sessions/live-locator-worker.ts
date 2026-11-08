// Find live transcript paths off the station's main thread. The temporary source snapshot keeps its order without
// holding a main-database read transaction while the filesystem is searched.
import { parentPort, workerData } from "node:worker_threads";
import { runtimeKind } from "../agents/runtime.ts";
import { getSession, historyRuntimeSources, openStore } from "../read/store.ts";
import { sessionPlaces, transcriptLocationHints, transcriptSources, useTranscriptLocationHints } from "../read/transcript.ts";
import { locationIdentity, type LocateMessage, type LocateReply, type LocateRequest, type LiveSource } from "./live-location-protocol.ts";

const data = workerData.data as string;
const store = openStore(data);
const BATCH = 64;
const waiting = new Map<number, (reply: LocateReply) => void>();
const cancelled = new Set<number>();
const running = new Set<number>();

function exchange(message: LocateMessage): Promise<LocateReply> {
  if (cancelled.has(message.id)) return Promise.resolve({ type: "cancel", id: message.id });
  return new Promise((resolve) => { waiting.set(message.id, resolve); parentPort!.postMessage(message); });
}

async function locate(ask: LocateRequest): Promise<void> {
  store.db.exec("BEGIN");
  let row: ReturnType<typeof getSession>, token: string | undefined, sources: ReturnType<typeof historyRuntimeSources> | null = null;
  try {
    row = getSession(store, ask.key);
    if (row !== null) token = (store.db.prepare("SELECT token FROM sessions WHERE key=?").get(ask.key) as { token: string } | undefined)?.token;
    if (row !== null && runtimeKind(row.runtime)) sources = historyRuntimeSources(store, ask.key);
  } finally { store.db.exec("COMMIT"); }
  const runtime = row === null ? null : (runtimeKind(row.runtime) ?? null);
  const identity = row === null || token === undefined ? null : locationIdentity(row, token);
  if (row === null || runtime === null || sources === null) {
    parentPort!.postMessage({ type: "done", id: ask.id, identity, runtime, current: false } satisfies LocateMessage);
    return;
  }
  let batch: LiveSource[] = [], visited = 0, current = false;
  const resolveBatch = async () => {
    if (batch.length === 0) return;
    for (;;) {
      const reply = await exchange({ type: "hints", id: ask.id, sources: batch });
      if (reply.type === "cancel") return;
      if (reply.type !== "hints") throw new Error("expected transcript location hints");
      useTranscriptLocationHints(reply.hints);
      const found = transcriptSources(data, ask.profiles, batch, sessionPlaces(row), { anywhere: false });
      const hints = transcriptLocationHints(data, ask.profiles, batch).value;
      const answer = await exchange({ type: "batch", id: ask.id, paths: found.paths, current: found.current, hints });
      if (answer.type === "cancel") return;
      if (answer.type !== "accepted") throw new Error("expected transcript location acknowledgement");
      if (answer.accepted) { current = found.current; break; }
    }
    batch = [];
  };
  try {
    for (const source of sources) {
      if (source !== null) batch.push(source);
      if (++visited % BATCH === 0) await resolveBatch();
      if (cancelled.has(ask.id)) return;
    }
    await resolveBatch();
  } finally { sources.close(); }
  parentPort!.postMessage({ type: "done", id: ask.id, identity, runtime, current } satisfies LocateMessage);
}

parentPort!.on("message", (message: LocateRequest | LocateReply) => {
  if (message.type !== "locate") {
    if (!running.has(message.id)) return;
    if (message.type === "cancel") cancelled.add(message.id);
    const done = waiting.get(message.id);
    waiting.delete(message.id);
    done?.(message);
    return;
  }
  if (running.has(message.id)) return;
  running.add(message.id);
  void locate(message).catch((error) => {
    if (!cancelled.has(message.id)) parentPort!.postMessage({ type: "error", id: message.id, error: String(error) } satisfies LocateMessage);
  }).finally(() => { running.delete(message.id); waiting.delete(message.id); cancelled.delete(message.id); });
});
