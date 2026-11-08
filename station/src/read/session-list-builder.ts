import { mbReaderBinary } from "./mb-reader.ts";
import { RequestedBuilder } from "./requested-builder.ts";

/// A requested old index is shared by the readers waiting for it; abandoned requests stop scheduling more batches. By
/// the MoonBit builder (station/mb, src/sessions) where its program is there, else by the worker; a worker of its own
/// given, by that one.
export class SessionListBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL, mb = workerFile === undefined ? mbReaderBinary() : null) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./session-list-worker.ts" : "./read/session-list-worker.js", import.meta.url);
    super(path, options, file, "scope", "session list preparation", undefined, mb === null ? null : { binary: mb, args: ["--builder", "session-list", "--db", path] });
  }

  readyIndex(signal?: AbortSignal): Promise<void> { return this.ready(["all"], signal); }
  readySearch(signal?: AbortSignal): Promise<void> { return this.ready(["search"], signal); }
}
