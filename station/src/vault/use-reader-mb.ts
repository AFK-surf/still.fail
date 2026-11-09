// The vault's use reader by the MoonBit program (station/mb, src/vaultuses) in use-index-worker.ts's place: the same
// queue and pacing, here on the station's thread, each read, preparation step and background batch asked of the
// program (`--builder vault-uses`), which knows nothing of the backfill permit: it is taken here around each write.
import { EventEmitter } from "node:events";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { MbProcess } from "../read/mb-reader.ts";
import { BACKFILL_PAUSE_MS, REQUEST_BACKFILL_PAUSE_MS, giveBackfill, takeBackfill } from "../store/backfill.ts";
import type { PendingPrepare, UseAnswer, UseRead } from "./use-index.ts";

/// What stands for this reader in the permit (a worker's thread id there): never a thread's.
let nextOwner = 0x70000000;

type Reply = { answered?: UseAnswer; unready?: true; complete?: boolean; bodies?: string[]; done?: boolean; busy?: true; error?: string };

export class MbUseReader extends EventEmitter {
  readonly threadId = nextOwner++;
  readonly #process: MbProcess;
  readonly #priority: Int32Array | null;
  readonly #replies: ((reply: Reply) => void)[] = [];
  readonly #waiting: (UseRead | PendingPrepare)[] = [];
  #backgroundComplete = false;
  #reboxComplete = false;
  #reboxTurn = true;
  #scheduled = false;
  #foregroundWaiting = false;
  #exited = false;

  constructor(binary: string, path: string, priority: SharedArrayBuffer | undefined) {
    super();
    this.#priority = priority instanceof SharedArrayBuffer ? new Int32Array(priority) : null;
    this.#process = new MbProcess(binary, ["--builder", "vault-uses", "--db", path]);
    this.#process.on("message", (reply: Reply) => this.#replies.shift()?.(reply));
    this.#process.on("error", (error) => this.emit("error", error));
    this.#process.on("exit", (code) => {
      this.#exited = true;
      for (const resolve of this.#replies.splice(0)) resolve({ error: `the vault use program stopped (exit ${code})` });
      this.emit("exit", code);
    });
    this.#schedule();
  }

  #ask(op: string, q?: UseRead | PendingPrepare): Promise<Reply> {
    if (this.#exited) return Promise.resolve({ error: "the vault use program stopped" });
    return new Promise((resolve) => { this.#replies.push(resolve); this.#process.postMessage({ op, ...(q ? { q } : {}) }); });
  }

  /// A ready answer is a read: no permit, no pause.
  async #answerIfReady(q: UseRead | PendingPrepare): Promise<"answered" | "unready" | "busy"> {
    const reply = await this.#ask("ready", q);
    if (reply.busy) return "busy";
    if (reply.error !== undefined) { this.emit("message", { id: q.id, error: reply.error } satisfies UseAnswer); return "answered"; }
    if (reply.answered === undefined) return "unready";
    this.emit("message", reply.answered);
    return "answered";
  }

  #more(): boolean { return this.#waiting.length > 0 || !this.#backgroundComplete || !this.#reboxComplete; }
  #pause(): number { return this.#waiting.length > 1 ? REQUEST_BACKFILL_PAUSE_MS : BACKFILL_PAUSE_MS; }

  #schedule(delay = 0) {
    if (this.#scheduled || this.#exited) return;
    this.#scheduled = true;
    const run = () => void this.#step().catch((error) => log.error("vault", "the use reader stopped", { error: (error as Error).message }));
    if (delay > 0) wall.after(delay, run);
    else setImmediate(run);
  }

  async #step(): Promise<void> {
    this.#scheduled = false;
    if (this.#exited) return;
    const q = this.#waiting.shift();
    if (q) {
      const answer = await this.#answerIfReady(q);
      if (answer === "answered") {
        if (this.#more()) this.#schedule(this.#waiting.length ? REQUEST_BACKFILL_PAUSE_MS : BACKFILL_PAUSE_MS);
        return;
      }
      if (answer === "busy") {
        this.#waiting.push(q);
        this.#schedule(this.#pause());
        return;
      }
    }
    if (!takeBackfill(this.#priority, this.threadId)) {
      if (q) this.#waiting.push(q);
      if (!this.#foregroundWaiting && this.#priority !== null && Atomics.load(this.#priority, 0) !== 0) {
        this.#foregroundWaiting = true;
        this.emit("message", { foreground: true, request: q?.id });
      }
      this.#schedule(this.#pause());
      return;
    }
    this.#foregroundWaiting = false;
    try {
      if (q) {
        const reply = await this.#ask("prepare", q);
        if (reply.busy) { this.#waiting.push(q); this.#schedule(this.#pause()); return; }
        if (reply.error !== undefined) this.emit("message", { id: q.id, error: reply.error } satisfies UseAnswer);
        else if (!reply.complete) this.#waiting.push(q); // (other workspaces get a turn between this one's batches)
        else if ("kind" in q) this.emit("message", { id: q.id, ready: true } satisfies UseAnswer);
        else this.emit("message", { id: q.id, bodies: reply.bodies ?? [] } satisfies UseAnswer);
      } else if (!this.#reboxComplete && (this.#backgroundComplete || this.#reboxTurn)) {
        const reply = await this.#ask("rebox");
        if (reply.busy) { this.#schedule(this.#pause()); return; }
        if (reply.error !== undefined) {
          log.error("vault", "the recovery index backfill stopped", { error: reply.error });
          this.#reboxComplete = true;
        } else { this.#reboxComplete = reply.done === true; this.#reboxTurn = false; }
      } else if (!this.#backgroundComplete) {
        const reply = await this.#ask("uses");
        if (reply.busy) { this.#schedule(this.#pause()); return; }
        if (reply.error !== undefined) {
          // (a broken old request must not keep another workspace's prepared page from being read)
          log.error("vault", "the use history backfill stopped", { error: reply.error });
          this.#backgroundComplete = true;
        } else { this.#backgroundComplete = reply.done === true; this.#reboxTurn = true; }
      }
    } finally { giveBackfill(this.#priority, this.threadId); }
    if (this.#more()) this.#schedule(this.#waiting.length ? REQUEST_BACKFILL_PAUSE_MS : BACKFILL_PAUSE_MS);
  }

  postMessage(q: UseRead | PendingPrepare) {
    this.#foregroundWaiting = false;
    // (a ready read is served without disturbing the background's pacing)
    void this.#answerIfReady(q).then((answer) => {
      if (answer === "answered") return;
      this.#waiting.push(q);
      this.#schedule();
    });
  }

  unref() {}

  terminate(): Promise<number> { return this.#process.terminate(); }
}
