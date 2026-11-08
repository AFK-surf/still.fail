// The search's thread: answers what is looked for by looking through the station's data as it is then,
// on a read-only connection to the store of its own, as a reader does (read/store.ts). Nothing is kept between searches.
// The execution histories are looked through only when asked for (agents ask, people do not), file by file, the thread
// let through between them, so a search asked meanwhile is answered.
import { parentPort, workerData } from "node:worker_threads";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { openStore } from "../read/store.ts";
import { wall } from "../ops/fibers.ts";
import { type Asker, type Group, pickAsync, terms } from "./match.ts";
import { historyGroup, historyHits, profilesOf, stationDocSteps } from "./sources.ts";

export type Told = { type: "query"; id: number; query: string; asker: Asker; kinds?: string[]; limit?: number; offset?: number; archived?: boolean; cancel?: SharedArrayBuffer };

export type Answered = { id: number; groups?: Group[]; error?: string };

/// How long the execution histories are looked through at most.
const HISTORY_MS = 15_000;

const data = workerData.data as string;
const s = openStore(data);

const config = (): any => {
  try {
    return JSON.parse(readFileSync(join(data, "config.json"), "utf8"));
  } catch {
    return {};
  }
};

async function answer(told: Told): Promise<Group[]> {
  const words = terms(told.query);
  if (words.length === 0) return [];
  const kinds = told.kinds && told.kinds.length > 0 ? new Set(told.kinds) : null;
  const limit = Math.max(1, Math.min(told.limit ?? 8, 200));
  const offset = Math.max(0, told.offset ?? 0);
  const cancelled = told.cancel ? new Int32Array(told.cancel) : null;
  const groups = await pickAsync(stationDocSteps(s, data, config(), kinds, told.asker, told.archived === true, words), words, told.asker, { limit, offset }, () => cancelled !== null && Atomics.load(cancelled, 0) !== 0);
  if (kinds?.has("history")) {
    const found = await historyHits(s, profilesOf(config(), data), words, told.asker, { limit, offset, ms: HISTORY_MS, now: () => wall.now(), cancelled: () => cancelled !== null && Atomics.load(cancelled, 0) !== 0 });
    const group = historyGroup(found);
    if (group !== null) groups.push(group);
  }
  return groups;
}

parentPort!.on("message", (told: Told) => {
  answer(told).then(
    (groups) => parentPort!.postMessage({ id: told.id, groups } satisfies Answered),
    (error) => parentPort!.postMessage({ id: told.id, error: (error as Error).message } satisfies Answered),
  );
});
