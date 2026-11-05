import { RequestedBuilder } from "./requested-builder.ts";

/// Prepare only sessions a chat's copy destinations or a session's name need. Both kinds share one worker.
export class CcIndexBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./cc-index-worker.ts" : "./read/cc-index-worker.js", import.meta.url);
    super(path, options, file, "session", "session conversation preparation", (key, cancel) => ({
      session: key.slice(1), ...(key[0] === "n" ? { name: true } : {}), ...(cancel ? { cancel: true } : {}),
    }));
  }

  override ready(sessions: readonly string[], signal?: AbortSignal): Promise<void> {
    return super.ready(sessions.map((session) => `c${session}`), signal);
  }

  readyNames(sessions: readonly string[], signal?: AbortSignal): Promise<void> {
    return super.ready(sessions.map((session) => `n${session}`), signal);
  }
}
