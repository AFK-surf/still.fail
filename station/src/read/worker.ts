// A reader: answers the admin API's reads off the main thread, on a read-only connection of its own (WAL lets readers
// and the one writer go on together). What it answers is text, ready to send: no copying the value across threads.
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { parentPort, workerData } from "node:worker_threads";
import type { Lang } from "../ops/i18n.ts";
import { ops } from "./ops.ts";
import { openStore } from "./store.ts";
import { HttpError, setSpoken } from "./views.ts";

export type Ask = { id: number; op: string; args: any; lang: Lang; names: [string, string][]; processes: [string, string][]; clientKeys: [string, string][] };
export type Answer = { id: number; text?: string; status?: number; error?: string };

const store = openStore(workerData.data as string);

/// The connection a checkpoint is made on: one that may write (a read-only one may not), made at the first, and used
/// for nothing else.
let writer: DatabaseSync | null = null;

/// What of the log (the WAL) is not in the database yet, written into it, as far as no reader still reads it (a passive
/// checkpoint: it waits for no one, and holds up no read or write): the main thread leaves it to the readers (store.ts).
function checkpoint(): unknown {
  if (writer === null) {
    writer = new DatabaseSync(join(workerData.data as string, "stillfail.db"), { timeout: 0 });
    writer.exec("PRAGMA synchronous = NORMAL");
  }
  return writer.prepare("PRAGMA wal_checkpoint(PASSIVE)").get();
}

parentPort!.on("message", (ask: Ask) => {
  let answer: Answer;
  try {
    if (ask.op === "checkpoint") {
      parentPort!.postMessage({ id: ask.id, text: JSON.stringify(checkpoint()) } satisfies Answer);
      return;
    }
    setSpoken(ask.lang);
    store.names = new Map(ask.names);
    store.processes = new Map(ask.processes);
    store.clientKeys = new Map(ask.clientKeys);
    const op = ops[ask.op];
    if (!op) throw new HttpError(500, `no read ${ask.op}`);
    answer = { id: ask.id, text: JSON.stringify(op(store, ask.args)) };
  } catch (error) {
    answer = { id: ask.id, status: error instanceof HttpError ? error.status : 500, error: (error as Error).message };
  }
  parentPort!.postMessage(answer);
});
