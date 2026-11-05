import { RequestedBuilder } from "./requested-builder.ts";

/// A requested old index is shared by the readers waiting for it; abandoned requests stop scheduling more batches.
export class SessionListBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./session-list-worker.ts" : "./read/session-list-worker.js", import.meta.url);
    super(path, options, file, "scope", "session list preparation");
  }

  readyIndex(signal?: AbortSignal): Promise<void> { return this.ready(["all"], signal); }
}
