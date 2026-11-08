import { mbReaderBinary } from "./mb-reader.ts";
import { RequestedBuilder } from "./requested-builder.ts";

/// Prepare the old threads whose widget sources are needed by a delivery. By the MoonBit builder (station/mb,
/// src/widgets) where its program is there, else by the worker; a worker of its own given, by that one.
export class WidgetSourcesBuilder extends RequestedBuilder<number> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL, mb = workerFile === undefined ? mbReaderBinary() : null) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./widget-sources-worker.ts" : "./read/widget-sources-worker.js", import.meta.url);
    super(path, options, file, "thread", "widget source preparation", undefined, mb === null ? null : { binary: mb, args: ["--builder", "widget-sources", "--db", path] });
  }
}
