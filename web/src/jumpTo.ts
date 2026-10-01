// A message a chat is to show when it opens: a row's second line pressed, where the core says what its state is about
// (`stateAbout`). The row asks for it here and opens the chat as it always does; the chat's list (Chat.tsx
// useMessageList, both screens) takes it once the message is in, scrolls it to the middle and flashes it.
import { useSyncExternalStore } from "react";

interface Wanted { station: string; thread: number; seq: number }

let wanted: Wanted | null = null;
const heard = new Set<() => void>();
const tell = () => { for (const h of heard) h(); };

/** The chat on `thread` of `station` is to show its message `seq` (the next time its list is drawn, or now if it is). */
export function jumpTo(to: Wanted): void {
  wanted = to;
  tell();
}

/** It was shown (or cannot be): asked no more. */
export function jumped(): void {
  if (wanted === null) return;
  wanted = null;
  tell();
}

/** The seq a chat's list is asked to show, if any is asked of it. */
export function useJump(station: string, thread: number | null): number | null {
  return useSyncExternalStore(
    (h) => { heard.add(h); return () => { heard.delete(h); }; },
    () => (wanted && thread !== null && wanted.station === station && wanted.thread === thread ? wanted.seq : null),
    () => null,
  );
}
