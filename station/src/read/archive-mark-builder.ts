import { RequestedBuilder } from "./requested-builder.ts";

/// Prepare old archive marks on request, sharing the work and stopping when no archive check needs it.
export class ArchiveMarkBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./archive-mark-worker.ts" : "./read/archive-mark-worker.js", import.meta.url);
    super(path, options, file, "scope", "archive mark preparation");
  }

  readyIndex(signal?: AbortSignal): Promise<void> { return this.ready(["all"], signal); }
}
