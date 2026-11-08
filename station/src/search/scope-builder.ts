import { RequestedBuilder } from "../read/requested-builder.ts";

export class SearchScopeBuilder extends RequestedBuilder<string> {
  constructor(path: string, options: { previousGone?: Promise<void>; priority?: SharedArrayBuffer } = {}) {
    const file = new URL(import.meta.url.endsWith(".ts") ? "./scope-worker.ts" : "./search/scope-worker.js", import.meta.url);
    super(path, options, file, "scope", "search scope preparation");
  }

  prepare(): Promise<void> { return this.ready(["all"]); }
}
