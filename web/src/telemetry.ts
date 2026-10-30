// Product analytics, error tracking and session replay through PostHog
// (docs/telemetry.md). A build without a project key has none of it: every
// function here does nothing and posthog-js is not in the bundle. What leaves
// the page is actions, counts, timings and errors, never what anyone wrote:
// no autocapture (it records element text), replays mask all text, inputs,
// images and the attributes that carry names, and URLs lose their ids,
// queries and hashes. A person may turn all of it off in settings; PostHog
// keeps that choice in the browser.
import type { CaptureResult, PostHog, Properties } from "posthog-js";
import { useEffect, useSyncExternalStore } from "react";
import { useLocation } from "react-router";

/** Set by web/vite.config.ts from the project key file; null in a build without one. */
declare const __POSTHOG__: { host: string; key: string; release: string } | null;

let posthog: PostHog | null = null;
/** Calls made while posthog-js loads; null when it is not coming. */
let early: ((ph: PostHog) => void)[] | null = null;
let loaded: Promise<void> = Promise.resolve();

/** Whether this build has PostHog: only then is there anything to turn off (the switch in settings). Undefined where
 * nothing built it (node's tests import the module as it is). */
export const HAS_TELEMETRY = typeof __POSTHOG__ !== "undefined" && __POSTHOG__ !== null;

/** Whether this browser sends anything: as PostHog keeps it once it has loaded, as last set here (else on) till then. */
let sending = true;
const watchers = new Set<() => void>();

function sendingNow(on: boolean): void {
  if (on === sending) return;
  sending = on;
  for (const watcher of watchers) watcher();
}

function use(run: (ph: PostHog) => void): void {
  if (posthog) run(posthog);
  else early?.push(run);
}

/** Starts PostHog for this page: `app` is which web app it is (only still.fail cloud's now; stations served one once). */
export function startTelemetry(app: "cloud"): void {
  if (!__POSTHOG__) return;
  const { host, key, release } = __POSTHOG__;
  early = [];
  loaded = import("posthog-js").then(({ posthog: ph }) => {
    ph.init(key, {
      api_host: host,
      defaults: "2026-08-30",
      person_profiles: "identified_only",
      autocapture: false,
      capture_pageview: false,
      capture_pageleave: false,
      rageclick: false,
      capture_dead_clicks: false,
      capture_heatmaps: false,
      capture_exceptions: { capture_unhandled_errors: true, capture_unhandled_rejections: true, capture_console_errors: false },
      disable_surveys: true,
      enable_recording_console_log: false,
      // The sign-in callback's query holds Google's code.
      disable_session_recording: location.pathname === "/auth/callback",
      session_recording: {
        maskAllInputs: true,
        maskTextSelector: "*",
        blockSelector: "img, picture, video, canvas",
        maskAttributeFn: (name, value) => (MASKED_ATTRIBUTES.has(name) ? "*".repeat(Math.min(value.length, 8)) : value),
        recordHeaders: false,
        recordBody: false,
      },
      before_send: scrub,
    });
    ph.register({ release, app });
    posthog = ph;
    for (const run of early ?? []) run(ph);
    early = null;
    sendingNow(!ph.has_opted_out_capturing());
  }, (error: unknown) => {
    early = null;
    console.warn("telemetry: posthog-js did not load", error);
  });
}

/** Whether this browser sends usage statistics and error reports (the switch in settings). */
export function telemetryOn(): boolean {
  return sending;
}

/** Whether this browser sends them, redrawn when that changes. */
export function useTelemetryOn(): boolean {
  return useSyncExternalStore((watcher) => { watchers.add(watcher); return () => watchers.delete(watcher); }, telemetryOn, telemetryOn);
}

/**
 * Turns sending on or off in this browser, kept by PostHog there (its opt-out). Off, nothing is captured: no events, no
 * exceptions, and the replay recording stops.
 */
export function setTelemetry(on: boolean): void {
  sendingNow(on);
  use((ph) => {
    if (on) {
      ph.opt_in_capturing();
    } else {
      ph.opt_out_capturing();
      // Opting out drops what the recording sends; it is stopped too, rather than left running for nothing.
      ph.stopSessionRecording();
    }
  });
}

/** Resolves once calls made so far are with posthog-js (or will never be); for a page about to go away. */
export function telemetrySettled(): Promise<void> {
  return Promise.race([loaded, new Promise<void>((resolve) => setTimeout(resolve, 2000))]);
}

/** Attributes that may carry names of people, files or chats (titles, labels, alt text) or links to them. */
const MASKED_ATTRIBUTES = new Set(["title", "alt", "aria-label", "aria-description", "aria-valuetext", "placeholder", "value", "label", "href", "src", "srcset", "download", "data-author", "data-ts"]);

/** Path segments that follow these are ids. */
const IDS: Record<string, string> = { w: ":workspace", s: ":station", chats: ":thread", connects: ":connect", bots: ":connect", accounts: ":profile", account: ":profile", stations: ":station" };

/** The words the app's routes are made of: any other segment is an id, a name or a key (a profile's holds an email,
 *  a skill's a customer's name), sent as `:id`. */
const WORDS = new Set([
  "about", "account", "accounts", "adb", "add", "admin", "agents", "all", "appearance", "archive", "auth", "automatic-decisions",
  "bar", "bots", "callback", "changelog", "chats", "codes", "completion", "connects", "feedback", "files",
  "fonts", "footprint", "general", "global", "history", "installed", "invite", "language", "leave", "local-station",
  "login", "members", "memory", "messages", "models", "new", "notifications", "o", "open", "overview", "permissions",
  "play", "prices", "profiles", "read", "relays", "resources", "run", "s", "screen", "security", "services", "sessions", "settings",
  "share", "shortcuts", "skill", "slack", "stations", "usage", "users", "vault", "version", "w", "workspace", "workspaces",
]);

/** A path with its ids replaced by what they are: /w/:workspace/s/:station/chats/:thread; any other segment that is no
 *  word of the routes as `:id`. */
export function pathTemplate(path: string): string {
  const parts = path.split("/");
  return parts.map((part, i) => {
    if (!part || i === 0) return part;
    return IDS[parts[i - 1]!] ?? (WORDS.has(part) ? part : ":id");
  }).join("/");
}

/** This origin's URLs as templates, without query or hash; other origins' as the origin alone. */
function scrubUrl(value: unknown): unknown {
  if (typeof value !== "string" || !value) return value;
  let url: URL;
  try {
    url = new URL(value, location.origin);
  } catch {
    return null;
  }
  if (url.origin !== location.origin) return url.origin;
  return value.startsWith("/") ? pathTemplate(url.pathname) : url.origin + pathTemplate(url.pathname);
}

const URL_PROPERTIES = [
  "$current_url", "$pathname", "$referrer", "$initial_current_url", "$initial_pathname", "$initial_referrer",
  "$session_entry_url", "$session_entry_pathname", "$session_entry_referrer", "$prev_pageview_pathname",
];

function scrubProperties(properties: Properties | undefined): void {
  if (!properties) return;
  for (const name of URL_PROPERTIES) if (name in properties) properties[name] = scrubUrl(properties[name]);
}

/** Errors that say nothing is wrong: Chrome's notice that a ResizeObserver's callback changed sizes again (nearly all
 *  the errors reported, 2026-10), which is the observers working as meant. */
const NOT_ERRORS = [/^ResizeObserver loop (completed with undelivered notifications|limit exceeded)/];

function scrub(event: CaptureResult | null): CaptureResult | null {
  if (!event) return null;
  if (event.event === "$exception") {
    const values = ((event.properties?.$exception_list ?? []) as { value?: unknown }[]).map((e) => String(e.value ?? ""));
    if (values.length > 0 && values.every((v) => NOT_ERRORS.some((re) => re.test(v)))) return null;
  }
  scrubProperties(event.properties);
  scrubProperties(event.$set);
  scrubProperties(event.$set_once);
  return event;
}

/** A product event: what happened, with counts and timings only. */
export function track(event: string, properties: Record<string, string | number | boolean> = {}): void {
  use((ph) => ph.capture(event, properties));
}

/**
 * A product event sent at once rather than with the next batch: for one the page leaves (or is left) right after,
 * which a batch would lose (the sign-ins Safari and Edge finished came without their sign_in).
 */
export function trackNow(event: string, properties: Record<string, string | number | boolean> = {}): void {
  use((ph) => ph.capture(event, properties, { send_instantly: true, transport: "sendBeacon" }));
}

export function captureException(error: unknown, properties: Record<string, string> = {}): void {
  use((ph) => ph.captureException(error, properties));
}

/** Who is using the page: the signed-in account in view, by its ember account id alone (not its email). */
export function identify(account: { sub: string }): void {
  use((ph) => {
    if (ph.get_distinct_id() !== account.sub) ph.identify(account.sub);
  });
}

/** An account signed out (or deleted): if it was the one identified, later events are anonymous. */
export function signedOut(sub: string): void {
  use((ph) => {
    if (ph.get_distinct_id() !== sub) return;
    // reset() forgets the opt-out with the rest: a browser turned off stays off.
    const off = ph.has_opted_out_capturing();
    ph.reset();
    if (off) ph.opt_out_capturing();
  });
}

/** A $pageview on each route change (its URL a template, see scrub); rendered inside the router. */
export function PageViews(): null {
  const path = useLocation().pathname;
  useEffect(() => use((ph) => ph.capture("$pageview")), [path]);
  return null;
}

let workspaceOpened = false;

/**
 * The first workspace this page load shows (its pages instead of the splash), how long after the page began: `kept`
 * when what it was opened from is what the device kept (some account's `/v1/me` not answered yet), else it waited for
 * still.fail cloud; `accounts` signed in.
 */
export function workspaceShown(kept: boolean, accounts: number): void {
  if (workspaceOpened) return;
  workspaceOpened = true;
  track("workspace_opened", { ms: Math.round(performance.now()), kept, accounts });
}

/** Performance.now() of the last click on a chat in the list, for how long it took to open. */
let chatClick: number | null = null;
let chatsOpened = 0;

export function chatClicked(): void {
  chatClick = performance.now();
}

/**
 * The start of a chat's opening, taken when its page mounts: the click that
 * led there, else the page's own start for the first chat of a page load
 * (cold: the core, the station's link and the chat all start then), else now.
 */
export function chatOpening(): { at: number; cold: boolean } {
  const cold = chatsOpened++ === 0;
  const now = performance.now();
  // A click on the chat already open leads nowhere; it must not count for the next.
  const clicked = chatClick !== null && now - chatClick < 5000 ? chatClick : null;
  const at = clicked ?? (cold ? 0 : now);
  chatClick = null;
  return { at, cold };
}
