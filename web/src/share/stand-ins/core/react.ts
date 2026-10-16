// What the share page has of web/src/core/react.ts (in its place: web/vite.share.config.ts), for FilePreview.tsx: no
// core, so no topic ever has a value. The preview asks one only for a chat's images to step through (`imageNear`),
// and the share page gives its own list instead (Share.tsx, Gallery).
export interface TopicState<T> { value: T | undefined; error: null; loading: boolean }

const NONE: TopicState<never> = { value: undefined, error: null, loading: false };

export function useTopic<T = unknown>(_topic: unknown): TopicState<T> {
  return NONE;
}

/** A topic's part (a chat's title, for a preview's way back): none here either. */
export function useTopicSelect<T, S>(_topic: unknown, select: (state: TopicState<T>) => S): S {
  return select(NONE);
}
