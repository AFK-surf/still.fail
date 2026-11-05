import { RequestedBuilder } from "./requested-builder.ts";

/// Prepare only the sessions whose copy destinations a chat needs.
export class CcIndexBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./cc-index-worker.ts" : "./read/cc-index-worker.js", import.meta.url);
    super(path, options, file, "session", "copy destination preparation");
  }
}
