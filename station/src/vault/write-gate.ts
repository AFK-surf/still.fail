// Writes on a new station must not finish before a previous station's unconditional writes have stopped.
import { wall } from "../ops/fibers.ts";

// The launcher normally stops the previous station within 30 seconds. A standalone predecessor can remain alive;
// do not keep requests (or their bodies) indefinitely when it does.
const HANDOVER_WAIT_MS = 40_000;

export function vaultWriteGate(previous: Promise<void> | null, after = wall.after) {
  let ready = previous === null;
  let closed = false;
  const waiting = Promise.withResolvers<boolean>();
  let cancel = () => {};
  if (previous !== null) {
    cancel = after(HANDOVER_WAIT_MS, () => waiting.resolve(false));
    void previous.then(() => {
      if (closed) return;
      ready = true;
      cancel();
      waiting.resolve(true);
    }, () => {
      cancel();
      waiting.resolve(false);
    });
  }
  return {
    // Undefined is the usual path: no asynchronous wait once the previous station has exited.
    wait(): false | Promise<boolean> | undefined {
      if (closed) return false;
      return ready ? undefined : waiting.promise;
    },
    close(): void {
      closed = true;
      cancel();
      waiting.resolve(false);
    },
  };
}
