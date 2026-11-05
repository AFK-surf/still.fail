import { RequestedBuilder } from "./requested-builder.ts";

/// An old binding index is shared by readers while they need it, and stops when none do.
export class SessionBindingsBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./session-bindings-worker.ts" : "./read/session-bindings-worker.js", import.meta.url);
    super(path, options, file, "scope", "session binding preparation");
  }

  readyIndex(signal?: AbortSignal): Promise<void> { return this.ready(["all"], signal); }
}
