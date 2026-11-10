import { mbReaderBinary } from "./mb-reader.ts";
import { RequestedBuilder } from "./requested-builder.ts";

/// Prepare only the sessions an archive check needs; several checks share each session's work. By the MoonBit builder
/// (station/mb, src/upjobs) where its program is there, else by the worker; a worker of its own given, by that one.
export class SessionUpJobsBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL, mb = workerFile === undefined ? mbReaderBinary() : null) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./session-up-jobs-worker.ts" : "./read/session-up-jobs-worker.js", import.meta.url);
    super(path, options, file, "session", "session up jobs preparation", undefined, mb === null ? null : { binary: mb, args: ["--builder", "session-up-jobs", "--db", path] });
  }
}
