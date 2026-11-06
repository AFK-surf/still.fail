import { RequestedBuilder } from "./requested-builder.ts";

export class CardPostsBuilder extends RequestedBuilder<number> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./card-posts-worker.ts" : "./read/card-posts-worker.js", import.meta.url);
    super(path, options, file, "thread", "card post preparation");
  }
}

/// The same worker also prepares the old closed-card lookup, on its own queue.
export class ClosedCardsBuilder extends RequestedBuilder<number> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./card-posts-worker.ts" : "./read/card-posts-worker.js", import.meta.url);
    super(path, options, file, "thread", "closed card preparation", (thread, cancel) => ({ thread, cancel, closed: true }));
  }
}

/// Prepare the people-time lookup for only the old chats a read needs.
export class PeopleSinceBuilder extends RequestedBuilder<number> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./card-posts-worker.ts" : "./read/card-posts-worker.js", import.meta.url);
    super(path, options, file, "thread", "people-time preparation", (thread, cancel) => ({ thread, cancel, people: true }));
  }
}
