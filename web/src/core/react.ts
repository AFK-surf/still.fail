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

// A topic nobody watches is let go after a moment, so a remount (or React's
// StrictMode double effect) does not resubscribe.
const LINGER_MS = 2000;
const entries = new Map<string, Entry>();
const IDLE: TopicState<never> = { value: undefined, error: null, loading: false };

/** The same key for the same topic, whatever order its fields were written in. */
export function topicKey(topic: Topic): string {
  return JSON.stringify(Object.entries(topic).sort(([a], [b]) => (a < b ? -1 : 1)));
}

function entry(key: string): Entry {
  let found = entries.get(key);
  if (!found) {
    found = { state: { value: undefined, error: null, loading: true }, listeners: new Set(), unsubscribe: null, drop: null };
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
  const e = entry(key);
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
  const snapshot = useCallback(() => (key ? entry(key).state : IDLE), [key]);
  return useSyncExternalStore(subscribe, snapshot) as TopicState<T>;
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
    const states = given.current.keys.map((key) => entry(key).state);
    if (states.length !== last.current.length || states.some((s, i) => s !== last.current[i])) last.current = states;
    return last.current;
  }, [joined]);
  return useSyncExternalStore(subscribe, snapshot) as TopicState<T>[];
}

/** `call(name, params)` on the page's core. */
export function useCall(): (name: string, params?: unknown) => Promise<unknown> {
  return useCallback((name: string, params?: unknown) => core().call(name, params), []);
}

