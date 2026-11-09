import { mbReaderBinary } from "./mb-reader.ts";
import { RequestedBuilder } from "./requested-builder.ts";

/// Prepare exact counts only for old sessions whose summaries were requested. By the MoonBit builder (station/mb,
/// src/turns), which takes the backfill permit only for its writes as the worker does, where its program is there;
/// else by the worker; a worker of its own given, by that one.
export class TurnBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL, mb = workerFile === undefined ? mbReaderBinary() : null) {
    super(path, options, workerFile, "session", "old turn counts", undefined, mb === null ? null : { binary: mb, args: ["--builder", "turn-counts", "--db", path], lazy: true });
  }
}
