import type { Store } from "../store/store.ts";

/// The recent threads whose people a connected platform can learn.
export function knownThreads(store: Store, connect: string): { thread: number; people: string[] }[] {
  const prefix = `slack:${connect}:`;
  return store.listThreads("", null, null, "none").slice(0, 200)
    .filter((t) => t.sessions.some((m) => m.connect === connect))
    .map((t) => ({ thread: t.thread.id, people: t.people.flatMap((p) => p.startsWith(prefix) ? [p.slice(prefix.length)] : []) }));
}
