import { RequestedBuilder } from "./requested-builder.ts";

/// The requested chats alone; concurrent sidebar and archive reads share each chat's progress.
export class SaidBuilder extends RequestedBuilder<number> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    super(path, options, workerFile, "thread", "sidebar said state");
  }
}
