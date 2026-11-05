import { RequestedBuilder } from "./requested-builder.ts";

/// Prepare only the sessions an archive check needs; several checks share each session's work.
export class SessionUpJobsBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./session-up-jobs-worker.ts" : "./read/session-up-jobs-worker.js", import.meta.url);
    super(path, options, file, "session", "session up jobs preparation");
  }
}
