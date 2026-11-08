import { mbReaderBinary } from "../read/mb-reader.ts";
import { RequestedBuilder } from "../read/requested-builder.ts";

/// The search's candidate scopes prepared: by the MoonBit builder (station/mb, src/searchscope) where its program is
/// there, else by scope-worker.ts; a worker of its own given, by that one.
export class SearchScopeBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL, mb = workerFile === undefined ? mbReaderBinary() : null) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./scope-worker.ts" : "./search/scope-worker.js", import.meta.url);
    super(path, options, file, "scope", "search scope preparation", undefined, mb === null ? null : { binary: mb, args: ["--builder", "search-scope", "--db", path] });
  }

  prepare(): Promise<void> { return this.ready(["all"]); }
}
