// React on the core: `useTopic` renders a topic's current value, `useCall`
// makes calls. Components that want the same topic share one subscription.
import { useCallback, useRef, useSyncExternalStore } from "react";
import { connectCore, type CoreClient, type CoreError, type Topic } from "./client.ts";
import { migrateLegacy } from "./migrate.ts";

let client: CoreClient | null = null;

/** The page's core client, started on first use. */
export function core(): CoreClient {
  if (!client) {
    client = connectCore();
    void migrateLegacy(client);
  }
  return client;
}

/** For tests and debugging: use this client instead of starting a worker. */
export function setCore(next: CoreClient): void {
  client = next;
}

export interface TopicState<T> {
  value: T | undefined;
  error: CoreError | null;
  /** No value and no error yet. */
  loading: boolean;
}

interface Entry {
  state: TopicState<unknown>;
  listeners: Set<() => void>;
  unsubscribe: (() => void) | null;
  drop: ReturnType<typeof setTimeout> | null;
}

// A topic nobody watches is let go after a while: going back to what was just
// shown (switching chats quickly, a remount) finds it current at once, with
// no frame waiting for the core's first answer.
const LINGER_MS = 30_000;
const entries = new Map<string, Entry>();

/** What a page knows of a topic before any core answers: nothing, unless it said (setTopicSource). */
let known: ((topic: Topic) => unknown) | null = null;

/**
 * For a page whose data is its own (the site's demo): each topic starts at the value `source` gives, instead of loading,
 * so the first render (on the server too: the site is built to HTML) already shows it.
 */
export function setTopicSource(source: (topic: Topic) => unknown): void {
  known = source;
}
const IDLE: TopicState<never> = { value: undefined, error: null, loading: false };

/** The same key for the same topic, whatever order its fields were written in. */
export function topicKey(topic: Topic): string {
  return JSON.stringify(Object.entries(topic).sort(([a], [b]) => (a < b ? -1 : 1)));
}

function entry(key: string, topic?: Topic): Entry {
  let found = entries.get(key);
  if (!found) {
    const value = topic && known ? known(topic) : undefined;
    found = { state: value === undefined || value === null ? { value: undefined, error: null, loading: true } : { value, error: null, loading: false }, listeners: new Set(), unsubscribe: null, drop: null };
    entries.set(key, found);
    // Created by a render that may never commit: dropped unless someone listens.
    linger(key, found);
  }
  return found;
}

function linger(key: string, e: Entry): void {
  if (e.drop) clearTimeout(e.drop);
  e.drop = setTimeout(() => {
    if (e.listeners.size > 0) return;
    e.unsubscribe?.();
    entries.delete(key);
  }, LINGER_MS);
}

function update(e: Entry, state: TopicState<unknown>): void {
  e.state = state;
  for (const listener of e.listeners) listener();
}

function listen(key: string, topic: Topic, listener: () => void): () => void {
  const e = entry(key, topic);
  if (e.drop) clearTimeout(e.drop);
  e.drop = null;
  e.listeners.add(listener);
  e.unsubscribe ??= core().subscribe(
    topic,
    // A value clears an earlier error: the topic is readable again.
    (value) => update(e, { value, error: null, loading: false }),
    // The last value stays on screen next to the error.
    (error) => update(e, { value: e.state.value, error, loading: false }),
  );
  return () => {
    e.listeners.delete(listener);
    if (e.listeners.size === 0) linger(key, e);
  };
}

/** A topic's current value, kept up to date by the core. `null` subscribes to nothing. */
export function useTopic<T = unknown>(topic: Topic | null): TopicState<T> {
  const key = topic ? topicKey(topic) : null;
  // The topic object is new each render; its key is what counts.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const subscribe = useCallback((listener: () => void) => (topic && key ? listen(key, topic, listener) : () => undefined), [key]);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const snapshot = useCallback(() => (key ? entry(key, topic!).state : IDLE), [key]);
  // On the server (the site built to HTML) the same: what is known already.
  return useSyncExternalStore(subscribe, snapshot, snapshot) as TopicState<T>;
}

/** Several topics at once (as many as there are, which may change): their states in the order given. */
export function useTopics<T = unknown>(topics: Topic[]): TopicState<T>[] {
  const keys = topics.map(topicKey);
  const joined = keys.join("\n");
  const given = useRef({ topics, keys });
  given.current = { topics, keys };
  const subscribe = useCallback((listener: () => void) => {
    const { topics: now, keys: at } = given.current;
    const offs = now.map((topic, i) => listen(at[i]!, topic, listener));
    return () => { for (const off of offs) off(); };
  }, [joined]);
  // The same array while no state in it changed, as useSyncExternalStore needs.
  const last = useRef<TopicState<unknown>[]>([]);
  const snapshot = useCallback(() => {
    const states = given.current.keys.map((key, i) => entry(key, given.current.topics[i]).state);
    if (states.length !== last.current.length || states.some((s, i) => s !== last.current[i])) last.current = states;
    return last.current;
  }, [joined]);
  return useSyncExternalStore(subscribe, snapshot, snapshot) as TopicState<T>[];
}

/** `call(name, params)` on the page's core. */
export function useCall(): (name: string, params?: unknown, onProgress?: (value: unknown) => void) => Promise<unknown> {
  return useCallback((name: string, params?: unknown, onProgress?: (value: unknown) => void) => core().call(name, params, onProgress), []);
}

