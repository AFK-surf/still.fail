// What people set going on this device and the core has not finished (the `doing` topic, client/core/src/doing.rs):
// every call that changes something, from when it is asked until it answers, whichever page or menu asked it. A row or
// button shows its own at once (a spinner, not pressed again), even after the menu that asked it has closed.

import { useTopic } from "./core/react.ts";
import type { DoingItem, DoingView } from "./core/shapes.ts";

type Words = Record<string, string | number | boolean | null | undefined>;

const TOPIC = { topic: "doing" } as const;

/** Whether `item` is one of `calls` about what `on` names (its params, as words; one left undefined is any). */
export function doingMatches(item: DoingItem, calls: string | readonly string[], on: Words): boolean {
  if (typeof calls === "string" ? item.call !== calls : !calls.includes(item.call)) return false;
  return Object.entries(on).every(([k, v]) => v === undefined || item.params[k] === String(v));
}

/** Everything under way now, oldest first. */
export function useDoingList(): DoingItem[] {
  return useTopic<DoingView>(TOPIC).value?.doing ?? [];
}

/** Whether one of `calls` is under way about what `on` names, e.g. `useDoing("job.stop", { station, id })`. */
export function useDoing(calls: string | readonly string[], on: Words = {}): boolean {
  return useDoingList().some((item) => doingMatches(item, calls, on));
}
