import { RequestedBuilder } from "./requested-builder.ts";

/// Prepare only requested copy destinations and latest conversations, sharing a worker between the two.
export class CcIndexBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./cc-index-worker.ts" : "./read/cc-index-worker.js", import.meta.url);
    super(path, options, file, "session", "session conversation preparation", (key, cancel) => ({
      session: key.slice(1), ...(key[0] === "l" ? { latest: true } : {}), ...(cancel ? { cancel: true } : {}),
    }));
  }

  override ready(sessions: readonly string[], signal?: AbortSignal): Promise<void> {
    return super.ready(sessions.map((session) => `c${session}`), signal);
  }

  readyLatest(sessions: readonly string[], signal?: AbortSignal): Promise<void> {
    return super.ready(sessions.map((session) => `l${session}`), signal);
  }
}
