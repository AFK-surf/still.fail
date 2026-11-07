import { log } from "../ops/log.ts";
import { Fibers } from "../ops/fibers.ts";
import { legacyMergedReadReady } from "./legacy-edits-build.ts";
import { cardOutcomeHeads, hasCardOutbox, type CardEditPage, type CardMessagePage, type CardOutcome } from "./card-outbox.ts";
import { MessageWriteBusy, type Store } from "./store.ts";

const RETRY_MS = 250;
const IDLE_MS = 30_000;
const SCANS = 4;

/// Writes durable card results after the preceding station exits. Each main-thread turn examines one queue head;
/// a long card scan uses bounded reader pages, and does not prevent ready cards from being written.
export class CardOutcomeWorker {
  readonly #store: Store;
  readonly #time: Fibers;
  readonly #page: (thread: number, target: string, before: string | null, signal: AbortSignal) => Promise<CardEditPage>;
  readonly #messagePage: (thread: number, target: string, before: string | null, signal: AbortSignal) => Promise<CardMessagePage>;
  readonly #stop = new AbortController();
  readonly #scanning = new Map<string, Promise<void>>();
  readonly #deferred = new Map<string, () => void>();
  #timer: (() => void) | null = null;
  #cursor = "0";
  #again = false;
  #ready = false;
  #closed = false;

  constructor(store: Store, previousExited: Promise<void>,
    page: (thread: number, target: string, before: string | null, signal: AbortSignal) => Promise<CardEditPage>,
    messagePage: (thread: number, target: string, before: string | null, signal: AbortSignal) => Promise<CardMessagePage>) {
    this.#store = store; this.#time = new Fibers("card outbox", store.clock); this.#page = page; this.#messagePage = messagePage;
    void previousExited.then(() => {
      if (!this.#closed) { this.#ready = true; this.wake(); }
    }, (error: unknown) => {
      if (!this.#closed) log.warn("card-outbox", "the previous station did not exit", { error: String(error) });
    });
  }

  /// Save the request and its outcome together, then wake the consumer after that savepoint is released.
  save(item: Omit<CardOutcome, "id">, save: () => void): string {
    const id = this.#store.saveCardOutcome(item, save);
    this.wake();
    return id;
  }

  /// Call after committing a new queue item. The idle check also finds items left by an interrupted producer.
  wake(): void {
    if (this.#closed || !this.#ready) return;
    // A head already passed by this traversal may have become ready while it was waiting.
    this.#again = true;
    this.#timer?.();
    this.#timer = this.#time.after(0, () => { this.#timer = null; this.#tick(); });
  }

  #later(ms: number): void {
    if (this.#closed || this.#timer !== null) return;
    this.#timer = this.#time.after(ms, () => { this.#timer = null; this.#tick(); });
  }

  #defer(key: string): void {
    if (this.#closed || this.#deferred.has(key)) return;
    this.#deferred.set(key, this.#time.after(RETRY_MS, () => { this.#deferred.delete(key); this.wake(); }));
  }

  #tick(): void {
    if (this.#closed || !this.#ready) return;
    let item: CardOutcome | undefined;
    try {
      if (!hasCardOutbox(this.#store.db)) { this.#cursor = "0"; this.#later(IDLE_MS); return; }
      item = cardOutcomeHeads(this.#store.db, this.#cursor, 1)[0];
    }
    catch (error) {
      log.warn("card-outbox", "reading queued card outcomes failed", { error: String(error) });
      this.#cursor = "0"; this.#later(RETRY_MS); return;
    }
    if (!item) {
      this.#cursor = "0";
      if (this.#again) { this.#again = false; this.#later(0); }
      else this.#later(IDLE_MS);
      return;
    }
    this.#cursor = item.id;
    const key = JSON.stringify([item.thread, item.ts]);
    if (!this.#scanning.has(key) && !this.#deferred.has(key)) {
      try {
        if (this.#store.restateQueuedCard(item) === undefined) {
          if (this.#scanning.size < SCANS) this.#startScan(key, item);
        }
      } catch (error) {
        if (!(error instanceof MessageWriteBusy)) log.warn("card-outbox", "writing a card outcome failed", { error: String(error) });
        this.#defer(key);
      }
    }
    this.#later(0);
  }

  #startScan(key: string, item: CardOutcome): void {
    const running = this.#scan(item).then((done) => { if (!done) this.#defer(key); }, (error: unknown) => {
      if (!this.#closed && !(error instanceof MessageWriteBusy)) log.warn("card-outbox", "reading an old card failed", { error: String(error) });
      this.#defer(key);
    }).finally(() => { this.#scanning.delete(key); this.wake(); });
    this.#scanning.set(key, running);
  }

  async #scan(item: CardOutcome): Promise<boolean> {
    const scan = this.#store.beginCardEditScan(item);
    if (scan === null) return false;
    try {
      let edit: string | null | undefined;
      if (!legacyMergedReadReady(this.#store.db)) {
        let before: string | null = null;
        for (;;) {
          this.#stop.signal.throwIfAborted();
          const page = await this.#messagePage(scan.thread, scan.target, before, this.#stop.signal);
          if (page.kind === "found") { edit = page.n; break; }
          if (page.kind === "end") { edit = null; break; }
          before = page.before;
        }
      }
      let before: string | null = null, card: string | null = null;
      for (;;) {
        this.#stop.signal.throwIfAborted();
        const page = await this.#page(scan.thread, scan.target, before, this.#stop.signal);
        if (page.kind === "found") { card = page.card; break; }
        if (page.kind === "end") break;
        before = page.before;
      }
      this.#stop.signal.throwIfAborted();
      return this.#store.restateQueuedCard(item, { scan, card, edit }) !== undefined;
    } finally {
      try { this.#store.endCardEditScan(scan); }
      catch (error) { if (!this.#closed && !(error instanceof MessageWriteBusy)) log.warn("card-outbox", "releasing a card scan failed", { error: String(error) }); }
    }
  }

  async close(): Promise<void> {
    this.#closed = true; this.#stop.abort();
    this.#timer?.();
    for (const stop of this.#deferred.values()) stop();
    this.#deferred.clear();
    await this.#time.close();
    await Promise.allSettled([...this.#scanning.values()]);
  }
}
