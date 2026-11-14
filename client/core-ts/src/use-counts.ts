// What of still.fail people use, counted on this device and sent to still.fail's PostHog project (the user,
// 2026-11-15: 「每个功能的使用率」, after the React app's page views were gone and the app sent none): the calls its UI
// makes, each by its name alone (`chat.send`, `prefs.set`: what the core's own code names, never what a call carries),
// and the pages it shows, by their kind alone (the app's `page_kind`: `Chat`, `Setting Usage`, never which chat,
// station or file). Counted here, a count a name, and sent as one event a name each `USAGE_MS`: `feature_used`
// {feature, count} and `page_shown` {page, count}, as the account signed in first (as the traces go).
//
// Only where the app says so (`client.reports`: the settings' 发送使用统计和错误报告, on by default; the host's own
// switch on Android and iOS, the prefs' `reports` elsewhere), from still.fail's own cloud (another product built of
// this code, or a cloud of a test or of one's own, sends nothing) and from a build given the project's key
// (`__STILLFAIL_POSTHOG__`: apps/mbui/scripts/core.sh for the apps, web/vite.config.ts
// for the web, from the file STILLFAIL_POSTHOG names; none in development and tests). Turned off, what was counted is
// dropped.
import { Effect } from "effect";
import type { Host } from "./host.ts";
import { laterSleep, type Runner } from "./runtime.ts";
import { toJsonBytes } from "./util.ts";

/// Counts wait this long to go out together.
export const USAGE_MS = 30_000;
/// The longest counts that did not go out wait to be sent again.
const RETRY_MAX_MS = 10 * 60_000;
/// At most this many names counted between sends: the rest are let go (a name is a call's or a page's kind, a set
/// the code fixes, so only a UI gone wrong comes near it).
const NAMES_MOST = 500;

/// still.fail's own clouds: what any other origin's core counts goes nowhere.
export const OWN_ORIGINS = ["https://app.still.fail", "https://app.youdid.wtf"];

/// Where counts go: PostHog's host and the project's key.
export type UsageSink = { host: string; key: string };

declare const __STILLFAIL_POSTHOG__: { host?: unknown; key?: unknown } | undefined;

/// The project this build was given, if any.
export function builtSink(): UsageSink | null {
  const said = typeof __STILLFAIL_POSTHOG__ === "undefined" ? undefined : __STILLFAIL_POSTHOG__;
  if (!said || typeof said.host !== "string" || typeof said.key !== "string" || said.key === "") return null;
  return { host: said.host.replace(/\/+$/, ""), key: said.key };
}

/// A page's kind as the app says it: words of letters and spaces alone (sfbase's page_kind), else not counted.
const KIND = /^[A-Za-z][A-Za-z ]{0,59}$/;
/// A call's name: the core's own names (letters, digits, dots, dashes and underscores).
const NAME = /^[A-Za-z][A-Za-z0-9._-]{0,79}$/;

type Said = { app: string; os: string; build: string };

export class UseCounts {
  readonly #host: Pick<Host, "fetch" | "nowMs" | "cloudOrigin">;
  readonly #runner: Runner;
  readonly #sink: UsageSink | null;
  readonly #account: () => string | null;
  readonly #said: () => Said;
  #on = false;
  /// `feature\0<name>` or `page\0<kind>` → how many times since the last send.
  #counts = new Map<string, number>();
  #scheduled = false;
  #failed = 0;

  constructor(host: Pick<Host, "fetch" | "nowMs" | "cloudOrigin">, runner: Runner, sink: UsageSink | null, account: () => string | null, said: () => Said) {
    this.#host = host;
    this.#runner = runner;
    this.#sink = sink;
    this.#account = account;
    this.#said = said;
  }

  /// Whether anything is ever sent from this core: a key given, still.fail's own cloud.
  get sends(): boolean {
    return this.#sink !== null && OWN_ORIGINS.includes(this.#host.cloudOrigin().replace(/\/+$/, ""));
  }

  /// As the app says (`client.reports`): off, what was counted is dropped.
  setOn(on: boolean): void {
    this.#on = on;
    if (!on) this.#counts.clear();
  }

  /// A call the UI made, by its name.
  used(name: string): void {
    if (NAME.test(name)) this.#count(`feature\u0000${name}`);
  }

  /// A page the UI shows, by its kind.
  shown(kind: string): void {
    if (KIND.test(kind)) this.#count(`page\u0000${kind}`);
  }

  #count(key: string): void {
    if (!this.#on || !this.sends) return;
    const was = this.#counts.get(key);
    if (was === undefined && this.#counts.size >= NAMES_MOST) return;
    this.#counts.set(key, (was ?? 0) + 1);
    this.#schedule();
  }

  #schedule(): void {
    if (this.#scheduled) return;
    this.#scheduled = true;
    const wait = this.#failed === 0 ? USAGE_MS : Math.min(USAGE_MS * 2 ** this.#failed, RETRY_MAX_MS);
    this.#runner.fork(laterSleep(wait).pipe(Effect.andThen(Effect.sync(() => this.flush())))); // timer: a debounce of a burst, and a retry after a failure with a backoff
  }

  /// Sends what was counted, as the account signed in; none signed in, it waits for one.
  flush(): void {
    this.#scheduled = false;
    const sink = this.#sink;
    const account = this.#account();
    if (!sink || !this.#on || !this.sends || this.#counts.size === 0) return;
    if (account === null) {
      this.#schedule();
      return;
    }
    const counts = this.#counts;
    this.#counts = new Map();
    const said = this.#said();
    const timestamp = new Date(this.#host.nowMs()).toISOString();
    const batch = [...counts].map(([key, count]) => {
      const [what, name] = key.split("\u0000") as [string, string];
      const properties: Record<string, unknown> = { count, app: said.app, os: said.os, $lib: "stillfail-core" };
      if (said.build !== "") properties.$app_version = said.build;
      if (what === "feature") properties.feature = name;
      else properties.page = name;
      return { event: what === "feature" ? "feature_used" : "page_shown", distinct_id: account, timestamp, properties };
    });
    const body = toJsonBytes({ api_key: sink.key, batch });
    this.#runner.fork(
      Effect.match(this.#host.fetch({ method: "POST", url: `${sink.host}/batch/`, headers: [["content-type", "application/json"]], body }), {
        onSuccess: (response) => {
          // (one PostHog will never take, a 4xx but too many, is let go: it would be refused again)
          if (response.status >= 500 || response.status === 429) this.#unsent(counts);
          else this.#failed = 0;
        },
        onFailure: () => this.#unsent(counts),
      }),
    );
  }

  /// Counts that did not go out are added to what came since and sent again later.
  #unsent(counts: Map<string, number>): void {
    if (!this.#on) return;
    this.#failed++;
    for (const [key, n] of counts) {
      const was = this.#counts.get(key);
      if (was === undefined && this.#counts.size >= NAMES_MOST) continue;
      this.#counts.set(key, (was ?? 0) + n);
    }
    this.#schedule();
  }
}
