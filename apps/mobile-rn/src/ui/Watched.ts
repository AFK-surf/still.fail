// Compose's snapshot state as the pages here have it: a value the screen draws from, changed by setting it.
import { useSyncExternalStore } from "react";

/** A store of values the screen draws from (Compose's snapshot state): read with `use`, changed with `set`. */
export class Watched<T> {
  #value: T;
  readonly #listeners = new Set<() => void>();
  constructor(value: T) { this.#value = value; }
  get value() { return this.#value; }
  set value(v: T) { if (v === this.#value) return; this.#value = v; for (const l of this.#listeners) l(); }
  subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
}
export function useWatched<T>(w: Watched<T>): T {
  return useSyncExternalStore(w.subscribe, () => w.value);
}
