// The readers: a few worker threads, each with its own read-only connection; a read goes to the one with the least
// to do, so a heavy one (a long chat list) holds up no other request and no writes.
import { availableParallelism } from "node:os";
import { Worker } from "node:worker_threads";
import type { Answer, Ask } from "./worker.ts";
import { HttpError } from "./views.ts";

export class Readers {
  private workers: { worker: Worker; busy: number }[] = [];
  private waiting = new Map<number, { resolve: (text: string) => void; reject: (error: Error) => void }>();
  private next = 0;
  /// People's names as their credentials say them (the admin API's `deps.names`), given to every read.
  readonly names = new Map<string, string>();

  /// Two by default (STILLFAIL_READERS says otherwise): each is a V8 of its own, tens of MB.
  constructor(data: string, size = Number(process.env.STILLFAIL_READERS) || Math.min(2, Math.max(1, availableParallelism() - 1))) {
    // From source: worker.ts beside this; bundled (this inside dist/main.js): dist/read/worker.js.
    const file = new URL(import.meta.url.endsWith(".ts") ? "./worker.ts" : "./read/worker.js", import.meta.url);
    for (let i = 0; i < size; i++) {
      // A reader's heap stays small: what it builds is answered and dropped.
      const worker = new Worker(file, { workerData: { data }, resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 8 } });
      const slot = { worker, busy: 0 };
      worker.on("message", (answer: Answer) => {
        slot.busy--;
        const waiter = this.waiting.get(answer.id);
        this.waiting.delete(answer.id);
        if (!waiter) return;
        if (answer.text !== undefined) waiter.resolve(answer.text);
        else waiter.reject(new HttpError(answer.status ?? 500, answer.error ?? "read failed"));
      });
      worker.unref();
      this.workers.push(slot);
    }
  }

  /// The answer, as JSON text.
  read(op: Ask["op"], args: any, lang: Ask["lang"]): Promise<string> {
    const id = this.next++;
    const slot = this.workers.reduce((a, b) => (b.busy < a.busy ? b : a));
    slot.busy++;
    return new Promise((resolve, reject) => {
      this.waiting.set(id, { resolve, reject });
      slot.worker.postMessage({ id, op, args, lang, names: [...this.names] } satisfies Ask);
    });
  }

  close() {
    for (const { worker } of this.workers) void worker.terminate();
  }
}
