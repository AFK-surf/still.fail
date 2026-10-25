// Only which records are held, never their payloads. Hot logs keep this small index across reads and update it as
// records arrive, so each new message need not copy the entire log's numbers out of SQLite again.
import { lowerBound, upperBound } from "../ordered.ts";

export class LogIndex {
  numbers: number[];
  constructor(numbers: number[]) { this.numbers = numbers; }
  get span(): { min: number; max: number; count: number } | null {
    const n = this.numbers;
    return n.length ? { min: n[0]!, max: n[n.length - 1]!, count: n.length } : null;
  }
  count(from: number, to: number): number {
    return to < from ? 0 : upperBound(this.numbers, to) - lowerBound(this.numbers, from);
  }
  put(added: number[], cutAfter: number | null): void {
    const held = this.numbers;
    const ns = [...new Set(added)].filter(n => !held.length || n > held[held.length - 1]! || held[lowerBound(held, n)] !== n).sort((a, b) => a - b);
    if (!held.length || (ns.length && ns[0]! > held[held.length - 1]!)) {
      // The usual case: messages arriving at the end. Amortized constant work per new record.
      for (const n of ns) held.push(n);
    } else if (ns.length) {
      const merged: number[] = [];
      let i = 0;
      for (const n of ns) {
        while (i < held.length && held[i]! < n) merged.push(held[i++]!);
        if (held[i] === n) i++;
        merged.push(n);
      }
      while (i < held.length) merged.push(held[i++]!);
      this.numbers = merged;
    }
    if (cutAfter !== null) this.numbers.length = upperBound(this.numbers, cutAfter);
  }
}

// Both the number of logs and the numbers held are bounded. This is disposable: eviction falls back to SQLite.
export class LogIndices {
  readonly #logs = new Map<string, { index: LogIndex; size: number }>();
  #numbers = 0;
  readonly maxNumbers: number;
  readonly maxLogs: number;
  constructor(maxNumbers = 1_000_000, maxLogs = 128) {
    this.maxNumbers = maxNumbers;
    this.maxLogs = maxLogs;
  }
  get(key: string): LogIndex | undefined {
    const entry = this.#logs.get(key);
    if (entry) { this.#logs.delete(key); this.#logs.set(key, entry); }
    return entry?.index;
  }
  delete(key: string): void {
    const entry = this.#logs.get(key);
    if (entry) { this.#numbers -= entry.size; this.#logs.delete(key); }
  }
  set(key: string, index: LogIndex): void {
    this.delete(key);
    if (index.numbers.length > this.maxNumbers) return;
    this.#logs.set(key, { index, size: index.numbers.length });
    this.#numbers += index.numbers.length;
    while (this.#logs.size > this.maxLogs || this.#numbers > this.maxNumbers) this.delete(this.#logs.keys().next().value!);
  }
  clear(): void { this.#logs.clear(); this.#numbers = 0; }
}
