import { mbReaderBinary } from "./mb-reader.ts";
import { RequestedBuilder } from "./requested-builder.ts";

/// The requested chats alone; concurrent sidebar and archive reads share each chat's progress. By the MoonBit builder
/// (station/mb, src/said), which takes the backfill permit only for its writes as the worker does, where its program
/// is there and the store has no legacy lookup; else by the worker; a worker of its own given, by that one.
export class SaidBuilder extends RequestedBuilder<number> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL, mb = workerFile === undefined ? mbReaderBinary() : null) {
    super(path, options, workerFile, "thread", "sidebar said state", undefined, mb === null ? null : { binary: mb, args: ["--builder", "said", "--db", path], lazy: true });
  }
}
