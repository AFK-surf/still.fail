import { log } from "../ops/log.ts";

/// Ask for an old session's order once while synchronous callers keep their immediate answer.
export function followLatestThreadRequests(
  store: { requestLatestThread: ((session: string) => void) | null },
  readers: { prepareLatestThreads(sessions: readonly string[]): Promise<void> },
): () => void {
  const preparing = new Set<string>();
  const request = (session: string) => {
    if (preparing.has(session)) return;
    preparing.add(session);
    void readers.prepareLatestThreads([session]).catch((error: unknown) => {
      log.warn("store", "a session's latest conversation could not be prepared", { session, error: String(error) });
    }).finally(() => preparing.delete(session));
  };
  store.requestLatestThread = request;
  return () => { if (store.requestLatestThread === request) store.requestLatestThread = null; };
}
