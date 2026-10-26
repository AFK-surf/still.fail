// What the share page has of web/src/core/react.ts (in its place: web/vite.share.config.ts), for FilePreview.tsx: no
// core, so no topic ever has a value. The preview asks one only for a chat's images to step through (`imageNear`),
// and the share page gives its own list instead (Share.tsx, Gallery). Markdown and code colours use the same
// pure readers as the core (the Markdown reader loaded on demand); both messages and file previews reach them through Prose.tsx.
import { inkKept } from "../../../../../client/core-ts/src/highlight.ts";

export interface TopicState<T> { value: T | undefined; error: null; loading: boolean }

const NONE: TopicState<never> = { value: undefined, error: null, loading: false };

export function useTopic<T = unknown>(_topic: unknown): TopicState<T> {
  return NONE;
}

/** A topic's part (a chat's title, for a preview's way back): none here either. */
export function useTopicSelect<T, S>(_topic: unknown, select: (state: TopicState<T>) => S): S {
  return select(NONE);
}

/** Only local text rendering is available to a visitor; account, station and binary calls still fail. */
export function core() {
  return {
    async call(method: string, params?: unknown, ..._rest: unknown[]): Promise<unknown> {
      const p = params as Record<string, unknown> | undefined;
      if (method === "markdown" && typeof p?.text === "string") {
        const { markdown } = await import("../../../../../client/core-ts/src/markdown.ts");
        return { md: markdown(p.text) };
      }
      if (method === "code.ink" && typeof p?.code === "string" && typeof p.lang === "string") {
        return { ink: inkKept(p.code, p.lang) };
      }
      throw new Error("no core on the share page");
    },
    async callBytes(..._args: unknown[]): Promise<never> {
      throw new Error("no core on the share page");
    },
  };
}
