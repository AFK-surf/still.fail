// A reader: answers the admin API's reads off the main thread, on a read-only connection of its own (WAL lets readers
// and the one writer go on together). What it answers is text, ready to send: no copying the value across threads.
import { parentPort, workerData } from "node:worker_threads";
import { openStore } from "./store.ts";
import { HttpError, chats, entries, setSpoken } from "./views.ts";
import type { Lang } from "../ops/i18n.ts";

export type Ask = { id: number; op: "chats" | "entries"; args: any; lang: Lang; names: [string, string][] };
export type Answer = { id: number; text?: string; status?: number; error?: string };

const store = openStore(workerData.data as string);

parentPort!.on("message", (ask: Ask) => {
  let answer: Answer;
  try {
    setSpoken(ask.lang);
    store.names = new Map(ask.names);
    const viewer = ask.args.viewer;
    const value = ask.op === "chats" ? chats(store, viewer, ask.args.archived) : entries(store, viewer, ask.args.thread, ask.args.params);
    answer = { id: ask.id, text: JSON.stringify(value) };
  } catch (error) {
    answer = { id: ask.id, status: error instanceof HttpError ? error.status : 500, error: (error as Error).message };
  }
  parentPort!.postMessage(answer);
});
