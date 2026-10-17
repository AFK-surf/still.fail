// What a button does that may take a while (Action.kt): the core says whether it is under way and whether it failed
// (its `doing` topic, AppState.isDoing); only work of the device's own, with no core call in it, is followed here.
import { useMemo, useSyncExternalStore } from "react";
import { captureCall, CoreError } from "../../../../web/src/core/client.ts";
import { UNTRACKED_OPERATIONS } from "../../../../web/src/core/operations.ts";
import { useApp, type AppState } from "../AppState";

interface Call { name: string; on: [string, string][] }

/**
 * Callback adapter. The core supplies running/failed state; only native work without a core call is local. The calls
 * `work` makes are seen as the core's client captures them (captureCall: the one it starts before it first waits, which
 * is how a page's work starts), where Kotlin's CallObserver sees each of them.
 */
export class Action {
  readonly #app: AppState;
  #calls: Call[] = [];
  #nativePending = false;
  #locked = false;
  #error: CoreError | null = null;
  readonly #listeners = new Set<() => void>();
  #version = 0;

  constructor(app: AppState) { this.#app = app; }

  get error(): CoreError | null { return this.#error; }

  get busy(): boolean {
    const tracked = this.#calls.filter((c) => !UNTRACKED_OPERATIONS.has(c.name));
    if (tracked.length === 0) return this.#nativePending;
    return tracked.some((c) => this.#app.isDoing(c.name, Object.fromEntries(c.on)));
  }

  run(work: () => Promise<void>): void {
    if (this.#locked) return;
    this.#locked = true; this.#calls = []; this.#nativePending = true; this.#error = null;
    this.changed();
    const { promise, details } = captureCall(() => work());
    if (details) {
      const on = Object.entries(details.on)
        .filter(([key]) => !/token|code|password|secret/i.test(key))
        .map(([key, value]) => [key, String(value)] as [string, string]);
      this.#calls = [...this.#calls, { name: details.name, on }];
      this.changed();
    }
    promise.then(
      () => undefined,
      (e: unknown) => {
        this.#error = e instanceof CoreError ? e : new CoreError({ code: "local", message: e instanceof Error ? e.message : String(e) });
        this.#app.toast = this.#error.message;
      },
    ).finally(() => { this.#locked = false; this.#nativePending = false; this.changed(); });
  }

  /** Something of it changed: what shows it is drawn again. */
  protected changed() { this.#version++; for (const l of this.#listeners) l(); }
  readonly subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  readonly version = () => this.#version;
}

/**
 * `remember(app) { Action(app) }`: one Action for the life of what made it, drawn again as it changes and as the core's
 * `doing` does (its `busy` is read from it).
 */
export function useAction<A extends Action>(make: () => A): A {
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const action = useMemo(make, []);
  useSyncExternalStore(action.subscribe, action.version);
  useApp((s) => s.doing);
  return action;
}
