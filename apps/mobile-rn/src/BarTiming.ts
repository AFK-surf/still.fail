// How long a switch between places on the bottom bar takes, and where the time goes (docs/telemetry.md → Android:
// `bar_switch`; the Android app's BarTiming.kt): from the finger lifted to the place's page on the stack, to the page
// shown (once it has what it opens with, App.tsx Pages, LOCAL_MS at most), its first render and first frame drawn; and
// for each topic the page follows anew, how long the core took to give its first value, decoding it, and how big it
// was. Logged on the device (`adb logcat -s ReactNativeJS | grep StillfailTiming`), and to PostHog as the account
// signed in, in a build with its key (EXPO_PUBLIC_POSTHOG_KEY). Only names of places and topics, counts and times:
// nothing a person wrote, no ids.
import Constants from "expo-constants";
import * as Device from "expo-device";
import type { Topic } from "../../../web/src/core/client.ts";
import { topicNow } from "../../../web/src/core/react.ts";
import { AppHooks, screenId, type Screen } from "./AppState";
import { BETA } from "./build";
import { placeOf } from "./Places";

const TAG = "StillfailTiming";
/** A switch is told once its page is drawn and each topic it followed anew has a value; at the latest this long after. */
const LONGEST_MS = 3_000;
/** A finger lifted longer ago than this is not what switched (the back gesture, a switch from the bars' panel landing). */
const TAP_MS = 1_000;
/** Sent to PostHog in batches: once this many are waiting, or this long after the first. */
const BATCH = 20;
const BATCH_MS = 60_000;

/** PostHog, as the Android app's build has it (BuildConfig.POSTHOG_KEY, POSTHOG_HOST): none, nothing is sent. */
const POSTHOG_KEY = process.env.EXPO_PUBLIC_POSTHOG_KEY ?? "";
const POSTHOG_HOST = process.env.EXPO_PUBLIC_POSTHOG_HOST ?? "https://us.i.posthog.com";

/** The clock every time here is on (ms, as precise as the platform's): Kotlin's System.nanoTime. */
const now = () => performance.now();

let lastUp = 0;
/** The places shown since the app started, and when each was last left. */
const seen = new Set<string>();
const left = new Map<string, number>();
/** The switch being timed; a new one tells it as it stands. */
let on: Switch | null = null;
const waiting: Record<string, unknown>[] = [];

class TopicTime {
  /** The core's first value reached the app, its decoding, and shown. */
  arrived = 0;
  decoding = 0;
  shown = 0;
  failed = false;
  json: unknown = undefined;
  constructor(readonly name: string, readonly at: number, readonly opening: boolean, readonly held: boolean) {}
}

class Switch {
  effect = 0;
  snapped = 0;
  waited = false;
  timedOut = false;
  composed = 0;
  drawn = 0;
  frame = 0;
  readonly topics = new Map<string, TopicTime>();
  done = false;
  /** The frames' times from the tap until it is told: how the JS thread kept up meanwhile. */
  readonly frames: number[] = [];
  constructor(
    readonly from: string | null, readonly to: string, readonly page: string, readonly tap: number, readonly touched: boolean,
    readonly placed: number, readonly first: boolean, readonly awayMs: number | null,
  ) {}
  readonly ticking = (): void => {
    if (this.done || this.frames.length >= 200) return;
    this.frames.push(now());
    requestAnimationFrame(this.ticking);
  };
}

/** A topic's key, as the core's client tells one from another (web/src/core/react.ts topicKey). */
const keyOf = (topic: Topic) => JSON.stringify(Object.entries(topic).sort(([a], [b]) => (a < b ? -1 : 1)));

function start() {
  AppHooks.placed = placed;
}

/** Every touch of the app: the last finger lifted is where a switch from the bar begins (Main.tsx, the root's touches). */
function touched() {
  lastUp = now();
}

/** A place's page put on the stack in place of `from`'s (AppState.place). */
function placed(from: Screen | null | undefined, to: Screen) {
  const at = now();
  if (on) finish(on, true);
  const place = placeOf(to);
  if (place == null) return;
  const was = from ? placeOf(from) : null;
  if (was != null) { left.set(was, at); seen.add(was); }
  const isTouch = lastUp !== 0 && at - lastUp >= 0 && at - lastUp <= TAP_MS;
  const since = left.get(place);
  const first = !seen.has(place);
  seen.add(place);
  const s = new Switch(was ?? null, place, screenId(to), isTouch ? lastUp : at, isTouch, at, first, since === undefined ? null : Math.floor(at - since));
  on = s;
  requestAnimationFrame(s.ticking);
  setTimeout(() => finish(s, false), LONGEST_MS);
}

/** The switch's effect in Pages has begun (the frame after the stack changed). */
function effect() {
  if (on && on.effect === 0) on.effect = now();
}

/** The page is now the one shown: `waited` for what it opens with, until LOCAL_MS ran out (`timedOut`). */
function snapped(waited: boolean, timedOut: boolean) {
  const s = on;
  if (!s || s.snapped !== 0) return;
  s.snapped = now(); s.waited = waited; s.timedOut = timedOut;
}

/** A topic followed anew by a page (App.tsx, what a page opens with), `held` if what it showed first was a value already. */
function followed(topic: Topic, held: boolean) {
  const s = on;
  if (!s || s.done || (s.drawn !== 0 && now() - s.drawn > 500)) return;
  const key = keyOf(topic);
  if (s.topics.has(key)) return;
  s.topics.set(key, new TopicTime(topic.topic, now(), s.snapped === 0, held));
}

/** A value of `topic` reached the app at `arrived` and was decoded by now. */
function decoded(topic: Topic, arrived: number, value: unknown, failed: boolean) {
  const s = on;
  if (!s) return;
  const t = s.topics.get(keyOf(topic));
  if (!t || t.arrived !== 0 || (value == null && !failed)) return;
  t.arrived = arrived; t.decoding = now() - arrived; t.json = value; t.failed = failed;
}

/** What a topic followed by a page shows changed. */
function shown(topic: Topic, value: unknown, failed: boolean) {
  const s = on;
  if (!s) return;
  const t = s.topics.get(keyOf(topic));
  if (!t || t.shown !== 0 || (value == null && !failed)) return;
  t.shown = now();
  settle(s);
}

/**
 * The page `screen` rendered, and drawn: the first time after a switch to it is the switch's. Called as the page is
 * rendered (App.tsx); the frame it is drawn in is the next one, and the one after it is when it has been handed to the
 * display (Choreographer's next frame on Android).
 */
function page(screen: Screen) {
  const s = on;
  const id = screenId(screen);
  if (!s || s.page !== id || s.snapped === 0 || s.composed !== 0) return;
  s.composed = now();
  requestAnimationFrame(() => {
    if (on !== s || s.drawn !== 0) return;
    s.drawn = now();
    requestAnimationFrame(() => { s.frame = now(); settle(s); });
  });
}

function settle(s: Switch) {
  if (s.frame !== 0 && [...s.topics.values()].every((t) => t.shown !== 0 || t.held)) finish(s, false);
}

function ms(from: number, to: number): number | null {
  return from === 0 || to === 0 ? null : Math.round((to - from) * 100) / 100;
}

function finish(s: Switch, cut: boolean) {
  if (s.done) return;
  s.done = true;
  if (on === s) on = null;
  const topics = [...s.topics.values()];
  // Between frames, up to the one the page was handed to the display in.
  const frames = s.frames.filter((f) => s.frame === 0 || f <= s.frame);
  const gaps = frames.slice(1).map((b, i) => Math.round((b - frames[i]!) * 10) / 10);
  const at = Date.now() - (now() - s.tap);
  // The values' sizes are counted after the switch, off its frames: counting them is work too.
  setTimeout(() => {
    const event: Record<string, unknown> = {
      from: s.from, to: s.to,
      first: s.first, ...(s.awayMs != null ? { away_ms: s.awayMs } : {}),
      touched: s.touched,
      place_ms: ms(s.tap, s.placed),
      effect_ms: ms(s.tap, s.effect),
      snap_ms: ms(s.tap, s.snapped),
      wait_ms: ms(s.effect, s.snapped),
      waited: s.waited, timed_out: s.timedOut,
      composed_ms: ms(s.tap, s.composed),
      drawn_ms: ms(s.tap, s.drawn),
      frame_ms: ms(s.tap, s.frame),
      cut: cut || s.frame === 0,
      frames: frames.length,
      longest_frame_ms: gaps.length ? Math.max(...gaps) : null,
      frame_gaps_ms: gaps.slice(0, 30),
      topics_count: topics.length,
      topics: topics.map((t) => ({
        topic: t.name,
        opening: t.opening,
        held: t.held,
        // From the page following it to the core's value in the app, decoding it, on screen.
        core_ms: ms(t.at, t.arrived),
        decode_ms: ms(t.arrived, t.arrived + t.decoding),
        shown_ms: ms(t.at, t.shown),
        tap_shown_ms: ms(s.tap, t.shown),
        ...(t.json !== undefined ? { bytes: byteSize(t.json) } : {}),
        ...(t.failed ? { failed: true } : {}),
      })),
    };
    console.log(TAG, `bar_switch ${JSON.stringify(event)}`);
    send(at, event);
  }, 0);
}

function byteSize(value: unknown): number {
  try {
    return new TextEncoder().encode(JSON.stringify(value)).length;
  } catch {
    return 0;
  }
}

/** The signed-in account's id (the web's distinct id), as Crashes.kt keeps it: the first account the core lists. */
function account(): string | null {
  return topicNow<{ sub: string }[]>({ topic: "accounts" })?.[0]?.sub ?? null;
}

/** What every event of the app carries: its build, and the device (Crashes.kt device). */
function device(): Record<string, unknown> {
  const version = Constants.expoConfig?.version ?? "";
  return {
    release: version, app: "android", beta: BETA, $app_version: version,
    $os: Device.osName ?? "", $os_version: Device.osVersion ?? "", $device_manufacturer: Device.manufacturer ?? "", $device_model: Device.modelName ?? "",
    $lib: "stillfail-rn",
  };
}

function send(at: number, properties: Record<string, unknown>) {
  if (POSTHOG_KEY === "") return;
  const id = account();
  if (id == null) return;
  waiting.push({ event: "bar_switch", distinct_id: id, uuid: uuid(), timestamp: new Date(at).toISOString(), properties: { ...properties, ...device() } });
  if (waiting.length === 1) setTimeout(flush, BATCH_MS);
  if (waiting.length < BATCH) return;
  flush();
}

function flush() {
  const batch = waiting.splice(0, waiting.length);
  if (batch.length === 0) return;
  fetch(`${POSTHOG_HOST.replace(/\/+$/, "")}/batch/`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ api_key: POSTHOG_KEY, batch }),
  }).catch(() => undefined);
}

function uuid(): string {
  const c = globalThis.crypto as Crypto | undefined;
  if (c?.randomUUID) return c.randomUUID();
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (ch) => {
    const r = (Math.random() * 16) | 0;
    return (ch === "x" ? r : (r & 0x3) | 0x8).toString(16);
  });
}

export const BarTiming = { start, touched, placed, effect, snapped, followed, decoded, shown, page };
