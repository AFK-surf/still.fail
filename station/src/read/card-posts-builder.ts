import { mbReaderBinary } from "./mb-reader.ts";
import { RequestedBuilder } from "./requested-builder.ts";

/// Prepare the old threads' posts that carry a card or options. By the MoonBit builder (station/mb, src/cards) where
/// its program is there, else by the worker; a worker of its own given, by that one.
export class CardPostsBuilder extends RequestedBuilder<number> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL, mb = workerFile === undefined ? mbReaderBinary() : null) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./card-posts-worker.ts" : "./read/card-posts-worker.js", import.meta.url);
    super(path, options, file, "thread", "card post preparation", undefined, mb === null ? null : { binary: mb, args: ["--builder", "card-posts", "--db", path] });
  }
}

/// The old closed-card lookup, on its own queue: by the MoonBit builder (station/mb, src/lookups) where its program is
/// there, else by the same worker.
export class ClosedCardsBuilder extends RequestedBuilder<number> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL, mb = workerFile === undefined ? mbReaderBinary() : null) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./card-posts-worker.ts" : "./read/card-posts-worker.js", import.meta.url);
    super(path, options, file, "thread", "closed card preparation", (thread, cancel) => ({ thread, cancel, closed: true }),
      mb === null ? null : { binary: mb, args: ["--builder", "closed-cards", "--db", path] });
  }
}

/// Prepare the people-time lookup for only the old chats a read needs: by the MoonBit builder (station/mb,
/// src/lookups) where its program is there, else by the worker.
export class PeopleSinceBuilder extends RequestedBuilder<number> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL, mb = workerFile === undefined ? mbReaderBinary() : null) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./card-posts-worker.ts" : "./read/card-posts-worker.js", import.meta.url);
    super(path, options, file, "thread", "people-time preparation", (thread, cancel) => ({ thread, cancel, people: true }),
      mb === null ? null : { binary: mb, args: ["--builder", "people-since", "--db", path] });
  }
}
