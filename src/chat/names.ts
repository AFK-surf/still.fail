// What Slack calls people and channels, kept on disk so the admin API never
// waits on Slack for a name: a name not known yet answers null at once, is
// fetched in the background, and `onLearn` tells the pages to read again.
// Failed lookups are not retried for a while.
import { existsSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { log } from "../log.ts";

export interface Person { name: string; email: string }

type Entry = { person?: Person; channel?: string | null; at: number };

const RETRY_FAILED_MS = 10 * 60_000;
const SAVE_AFTER_MS = 2_000;
const LEARN_AFTER_MS = 200;

export class NameBook {
  readonly #path: string;
  readonly #entries: Record<string, Entry>;
  readonly #pending = new Set<string>();
  readonly #failed = new Map<string, number>();
  #onLearn: () => void = () => {};
  #saving: ReturnType<typeof setTimeout> | null = null;
  #learning: ReturnType<typeof setTimeout> | null = null;

  constructor(path: string) {
    this.#path = path;
    let entries: Record<string, Entry> = {};
    try {
      if (existsSync(path)) entries = JSON.parse(readFileSync(path, "utf8")) as Record<string, Entry>;
    } catch (error) {
      log.warn("slack names file unreadable; starting empty", { error });
    }
    this.#entries = entries;
  }

  /** Called (once per burst) after names were learned, so pages read what shows them again. */
  onLearn(listener: () => void): void {
    this.#onLearn = listener;
  }

  person(key: string, fetch: () => Promise<Person | null>): Person | null {
    const known = this.#entries[key]?.person;
    if (!known) this.#learn(key, async () => {
      const person = await fetch();
      return person ? { person, at: Date.now() } : null;
    });
    return known ?? null;
  }

  /** A channel's name; null for a direct message (known) or not known yet. */
  channel(key: string, fetch: () => Promise<string | null>): string | null {
    const known = this.#entries[key];
    if (!known || known.channel === undefined) this.#learn(key, async () => ({ channel: await fetch(), at: Date.now() }));
    return known?.channel ?? null;
  }

  #learn(key: string, fetch: () => Promise<Entry | null>): void {
    if (this.#pending.has(key) || (this.#failed.get(key) ?? 0) > Date.now()) return;
    this.#pending.add(key);
    fetch().then(
      (entry) => {
        this.#pending.delete(key);
        if (!entry) return void this.#failed.set(key, Date.now() + RETRY_FAILED_MS);
        this.#entries[key] = { ...this.#entries[key], ...entry };
        this.#later();
      },
      () => {
        this.#pending.delete(key);
        this.#failed.set(key, Date.now() + RETRY_FAILED_MS);
      },
    );
  }

  #later(): void {
    this.#learning ??= setTimeout(() => {
      this.#learning = null;
      this.#onLearn();
    }, LEARN_AFTER_MS);
    this.#saving ??= setTimeout(() => {
      this.#saving = null;
      try {
        const tmp = `${this.#path}.tmp`;
        writeFileSync(tmp, JSON.stringify(this.#entries));
        renameSync(tmp, this.#path);
      } catch (error) {
        log.warn("cannot save slack names", { error });
      }
    }, SAVE_AFTER_MS);
  }
}
