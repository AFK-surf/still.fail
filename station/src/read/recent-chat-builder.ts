import type { RecentChatScope } from "../store/chat-list-prepare.ts";
import { RequestedBuilder } from "./requested-builder.ts";

/// Requests share a scope's work and each unfinished scope returns to the back of the line.
export class RecentChatBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}, workerFile?: URL) {
    const file = workerFile ?? new URL(import.meta.url.endsWith(".ts") ? "./recent-chat-worker.ts" : "./read/recent-chat-worker.js", import.meta.url);
    super(path, options, file, "scope", "recent chat preparation");
  }

  readyScope(scope: RecentChatScope, signal?: AbortSignal): Promise<void> {
    return this.ready([JSON.stringify([scope.ws, scope.home])], signal);
  }
}
