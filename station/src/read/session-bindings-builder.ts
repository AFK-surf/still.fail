import { mbReaderBinary } from "./mb-reader.ts";
import { RequestedBuilder } from "./requested-builder.ts";

/// An old binding index is shared by readers while they need it, and stops when none do. Built by the MoonBit builder
/// (station/mb, src/bindings) where its program is there, else by the worker; a worker of its own given, by that one.
export class SessionBindingsBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL, mb = workerFile === undefined ? mbReaderBinary() : null) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./session-bindings-worker.ts" : "./read/session-bindings-worker.js", import.meta.url);
    super(path, options, file, "scope", "session binding preparation", undefined, mb === null ? null : { binary: mb, args: ["--builder", "session-bindings", "--db", path] });
  }

  readyIndex(signal?: AbortSignal): Promise<void> { return this.ready(["all"], signal); }
}
