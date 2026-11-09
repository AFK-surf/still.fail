import { mbReaderBinary } from "./mb-reader.ts";
import { RequestedBuilder } from "./requested-builder.ts";

/// Prepare old archive marks on request, sharing the work and stopping when no archive check needs it. By the MoonBit
/// builder (station/mb, src/marks) where its program is there, else by the worker; a worker of its own given
/// (`workerFile`), by that one.
export class ArchiveMarkBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL, mb = workerFile === undefined ? mbReaderBinary() : null) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./archive-mark-worker.ts" : "./read/archive-mark-worker.js", import.meta.url);
    super(path, options, file, "scope", "archive mark preparation", undefined, mb === null ? null : { binary: mb, args: ["--builder", "archive-marks", "--db", path] });
  }

  readyIndex(signal?: AbortSignal): Promise<void> { return this.ready(["all"], signal); }
}
