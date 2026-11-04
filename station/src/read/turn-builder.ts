import { RequestedBuilder } from "./requested-builder.ts";

/// Prepare exact counts only for old sessions whose summaries were requested.
export class TurnBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    super(path, options, workerFile, "session", "old turn counts");
  }
}
