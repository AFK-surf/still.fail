// The search's thread (docs/search.md): answers what is looked for by looking through the station's data as it is then,
// on a read-only connection to the store of its own, as a reader does (read/store.ts). Nothing is kept between searches.
// The execution histories are looked through only when asked for (agents ask, people do not), file by file, the thread
// let through between them, so a search asked meanwhile is answered.
import { parentPort, workerData } from "node:worker_threads";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { openStore } from "../read/store.ts";
import { wall } from "../ops/fibers.ts";
import { type Asker, type Group, pick, terms } from "./match.ts";
import { historyHits, profilesOf, stationDocs } from "./sources.ts";

export type Told = { type: "query"; id: number; query: string; asker: Asker; kinds?: string[]; limit?: number; offset?: number };

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
  const groups = pick(stationDocs(s, data, config(), kinds), words, told.asker, { limit, offset });
  if (kinds?.has("history")) {
    const found = await historyHits(s, profilesOf(config(), data), words, told.asker, { limit, offset, ms: HISTORY_MS, now: () => wall.now() });
    if (found.hits.length > 0) groups.push({ kind: "history", hits: found.hits, more: found.more, ...(found.left > 0 ? { left: found.left } : {}) });
  }
  return groups;
}

parentPort!.on("message", (told: Told) => {
  answer(told).then(
    (groups) => parentPort!.postMessage({ id: told.id, groups } satisfies Answered),
    (error) => parentPort!.postMessage({ id: told.id, error: (error as Error).message } satisfies Answered),
  );
});
