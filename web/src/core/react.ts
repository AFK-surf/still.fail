// React on the core: `useTopic` renders a topic's current value, `useCall`
// makes calls. Components that want the same topic share one subscription.
import { use, useCallback, useContext, useRef, useSyncExternalStore } from "react";
import { InBones } from "@stillfail/ui/inBones.ts";
import { connectCore, type CoreClient, type CoreError, type Topic } from "./client.ts";
import { migrateChatRefs, migrateLegacy, migrateNewChat, migratePrefs } from "./migrate.ts";

declare const __BUILD__: string | null;

let client: CoreClient | null = null;

/** The page's core client, started on first use. */
export function core(): CoreClient {
  if (!client) {
    client = connectCore();
    void migrateLegacy(client);
    void migrateChatRefs(client);
    void migrateNewChat(client);
    void migratePrefs(client);
    // What this device is, said once: the core decides what follows from it (phone or computer, the name it signs in
    // as, the app a message is sent from). A core from before it has the page say those itself.
    client.call("client.device", { app: "web", build: typeof __BUILD__ === "string" ? __BUILD__ : "", userAgent: navigator.userAgent, locale: navigator.language ?? "" }).catch(() => undefined);
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
  /** Loading, and the core said it waits on a station for it: none of what it shows is on the device. */
  waiting?: boolean;
}

interface Entry {
  state: TopicState<unknown>;
  listeners: Set<() => void>;
  unsubscribe: (() => void) | null;
  drop: ReturnType<typeof setTimeout> | null;
  /** What a render waits on for its first value (`useReady`), settled once waited, whether it came or not. */
  ready?: Promise<void>;
  /** How long it is kept once nobody watches it, when not LINGER_MS. */
  linger?: number;
}

// A topic nobody watches is let go after a while: going back to what was just
// shown (switching chats quickly, a remount) finds it current at once, with
// no frame waiting for the core's first answer.
const LINGER_MS = 30_000;
// A chat is kept longer: going back to one read a few minutes ago shows it as it is, with nothing to wait for.
const LINGER_CHAT_MS = 5 * 60_000;
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

/** What the page knows of a topic before any core answers (setTopicSource), if it knows anything. */
export function knownOf(topic: Topic): unknown {
  return known?.(topic) ?? undefined;
}

/**
 * Forgets what is known of every topic, so that each starts again at what the source gives now: for a page built to HTML
 * more than once in one run, its source saying otherwise each time (the site's demo, opening elsewhere or in another
 * language: demo/prerender.tsx).
 */
export function forgetTopics(): void {
  for (const e of entries.values()) if (e.drop) clearTimeout(e.drop);
  entries.clear();
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
    if (topic?.topic === "chat") found.linger = LINGER_CHAT_MS;
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
  }, e.linger ?? LINGER_MS);
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
    () => { if (e.state.loading) update(e, { ...e.state, waiting: true }); },
  );
  return () => {
    e.listeners.delete(listener);
    if (e.listeners.size === 0) linger(key, e);
  };
}

/**
 * A topic's current value, kept up to date by the core. `null` subscribes to nothing; nor does a page's bones (what they are
 * drawn of is made up: @stillfail/ui waiting.tsx Bones), nor is anything there called.
 */
export function useTopic<T = unknown>(topic: Topic | null): TopicState<T> {
  if (useContext(InBones)) topic = null;
  const key = topic ? topicKey(topic) : null;
  // The topic object is new each render; its key is what counts.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const subscribe = useCallback((listener: () => void) => (topic && key ? listen(key, topic, listener) : () => undefined), [key]);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const snapshot = useCallback(() => (key ? entry(key, topic!).state : IDLE), [key]);
  // On the server (the site built to HTML) the same: what is known already.
  return useSyncExternalStore(subscribe, snapshot, snapshot) as TopicState<T>;
}

/**
 * What a component takes from a topic (`select` of its state): drawn again only when that changes (`same`, by default
 * the same value), not each time anything else in the topic does. `select` may be a new function each render.
 */
export function useTopicSelect<T, S>(topic: Topic | null, select: (state: TopicState<T>) => S, same: (a: S, b: S) => boolean = Object.is): S {
  if (useContext(InBones)) topic = null;
  const key = topic ? topicKey(topic) : null;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const subscribe = useCallback((listener: () => void) => (topic && key ? listen(key, topic, listener) : () => undefined), [key]);
  const pick = useRef(select);
  pick.current = select;
  // The state last taken from and how, and what was taken: the same while both are (a render's new `select` takes again,
  // and keeps what it had if that is the same).
  const last = useRef<{ key: string | null; state: TopicState<unknown> | null; select: unknown; picked: S } | null>(null);
  const snapshot = () => {
    const state = (key ? entry(key, topic!).state : IDLE) as TopicState<T>;
    const was = last.current;
    if (was && was.key === key && was.state === state && was.select === pick.current) return was.picked;
    const picked = pick.current(state);
    last.current = { key, state, select: pick.current, picked: was && was.key === key && same(was.picked, picked) ? was.picked : picked };
    return last.current.picked;
  };
  return useSyncExternalStore(subscribe, snapshot, snapshot);
}

/**
 * Holds the render back until the topic has its first value, or the core says it waits on a station for it, `ms` at
 * most. Rendered as part of a navigation (a transition), the page that was there stays until then instead of an empty
 * one showing first. Once only per topic.
 */
export function useReady(topic: Topic | null, ms: number): void {
  if (useContext(InBones)) topic = null;
  const wait = topic ? waitFor(topicKey(topic), topic, ms) : null;
  if (wait) use(wait);
}

function waitFor(key: string, topic: Topic, ms: number): Promise<void> | null {
  const e = entry(key, topic);
  // Once waited on, always the same (settled) one: the render that suspended on it must use it again when it goes on.
  if (e.ready) return e.ready;
  if (!e.state.loading) return null;
  let resolve!: () => void;
  const ready = new Promise<void>((r) => { resolve = r; });
  e.ready = ready;
  let over = false;
  let off: (() => void) | null = null;
  const done = () => {
    if (over) return;
    over = true;
    clearTimeout(timer);
    off?.();
    // Marked as React reads it: used again, it goes on at once rather than suspending for a tick.
    Object.assign(ready, { status: "fulfilled", value: undefined });
    resolve();
  };
  const timer = setTimeout(done, ms);
  off = listen(key, topic, () => { if (!e.state.loading || e.state.waiting) done(); });
  if (over) off();
  return ready;
}

/** A topic's value as the page has it now, read when asked (a tap), not followed; undefined while none. */
export function topicNow<T>(topic: Topic): T | undefined {
  return entries.get(topicKey(topic))?.state.value as T | undefined;
}

/** Starts reading a topic ahead of a page that will show it (a row hovered), kept a while for it. */
export function prime(topic: Topic): void {
  const key = topicKey(topic);
  listen(key, topic, () => undefined)();
}

/** Several topics at once (as many as there are, which may change): their states in the order given. */
export function useTopics<T = unknown>(topics: Topic[]): TopicState<T>[] {
  if (useContext(InBones)) topics = [];
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
export function useCall(): (name: string, params?: unknown, onProgress?: (value: unknown) => void, signal?: AbortSignal) => Promise<unknown> {
  const quiet = useContext(InBones);
  return useCallback((name: string, params?: unknown, onProgress?: (value: unknown) => void, signal?: AbortSignal) => quiet ? Promise.resolve(undefined) : core().call(name, params, onProgress, signal), [quiet]);
}

