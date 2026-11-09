import { RequestedBuilder } from "./requested-builder.ts";

/// Prepare the old station-wide up-job lookup in bounded batches after handover.
export class WorkspaceUpJobsBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./workspace-up-jobs-worker.ts" : "./read/workspace-up-jobs-worker.js", import.meta.url);
    super(path, options, file, "scope", "workspace up jobs preparation");
  }
}
