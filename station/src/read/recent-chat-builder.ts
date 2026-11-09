import type { RecentChatScope } from "../store/chat-list-prepare.ts";
import { mbReaderBinary } from "./mb-reader.ts";
import { RequestedBuilder } from "./requested-builder.ts";

/// Requests share a scope's work and each unfinished scope returns to the back of the line. By the MoonBit builder
/// (station/mb, src/recent) where its program is there, else by the worker; a worker of its own given, by that one.
export class RecentChatBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL, mb = workerFile === undefined ? mbReaderBinary() : null) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./recent-chat-worker.ts" : "./read/recent-chat-worker.js", import.meta.url);
    super(path, options, file, "scope", "recent chat preparation", undefined, mb === null ? null : { binary: mb, args: ["--builder", "recent-chat", "--db", path] });
  }

  readyScope(scope: RecentChatScope, signal?: AbortSignal): Promise<void> {
    return this.ready([JSON.stringify([scope.ws, scope.home])], signal);
  }
}
