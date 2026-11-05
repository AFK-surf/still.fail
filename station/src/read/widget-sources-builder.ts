import { RequestedBuilder } from "./requested-builder.ts";

/// Prepare the old threads whose widget sources are needed by a delivery.
export class WidgetSourcesBuilder extends RequestedBuilder<number> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./widget-sources-worker.ts" : "./read/widget-sources-worker.js", import.meta.url);
    super(path, options, file, "thread", "widget source preparation");
  }
}
