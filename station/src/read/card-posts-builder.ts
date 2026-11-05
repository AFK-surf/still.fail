import { RequestedBuilder } from "./requested-builder.ts";

export class CardPostsBuilder extends RequestedBuilder<number> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./card-posts-worker.ts" : "./read/card-posts-worker.js", import.meta.url);
    super(path, options, file, "thread", "card post preparation");
  }
}
