// What changed in still.fail, for people (changelog.rs; the `changelog` topic, docs/changelog.md): still.fail cloud's
// changelog with what each part has out on this app's channel, one tab a part (this app's first), by day, newest first;
// and what this app got since it
// was last shown here (`news`, until `changelog.seen`). Kept on the device (table `changelog`). The sync reads it as
// the core starts and each time still.fail cloud's events socket opens (rule 6: never because it is shown); `app.update`
// reads it too when it finds a build of this app the changelog kept was read before (`brings`).
import { Effect } from "effect";
import { channelHeader } from "./cloud.ts";
import type { Data } from "./data.ts";
import * as format from "./format.ts";
import type { Host } from "./host.ts";
import { t } from "./i18n.ts";
import type { Owner } from "./core/routing.ts";
import type { Topic } from "./protocol.ts";
import type { Store, Value } from "./store.ts";
import { arr as arrU, get as getU, parseJson } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

const SHOWN = 200;
const NEWS = 20;
const TABLE = "changelog";

function partsOf(app: string): string[] {
  return app === "android" ? ["android"] : app === "desktop" ? ["web", "desktop"] : app === "web" ? ["web"] : [];
}

/// The changelog's tabs, this app's first, and which changes each has: the desktop app carries the web's.
const TABS = ["desktop", "web", "android", "station", "cloud"];
function tabsOf(app: string): string[] {
  const own = TABS.includes(app) ? app : "web";
  return [own, ...TABS.filter((tab) => tab !== own)];
}
function inTab(tab: string, parts: string[]): boolean {
  if (tab === "cloud") return parts.length === 0 || parts.includes("cloud");
  return tab === "desktop" ? parts.includes("web") || parts.includes("desktop") : parts.includes(tab);
}

function partName(part: string): string {
  if (part === "web" || part === "android" || part === "desktop") return t(`core-misc.changelog.part.${part}`);
  return part;
}

const int = (v: J): number | null => (typeof v === "number" && Number.isInteger(v) ? v : null);

/// One change as this app shows it.
export function item(entry: J, app: string, build: number | null, released: J): J {
  const version = int(get(entry, "version"));
  if (version === null) return null;
  const textList = get(entry, "text");
  if (!Array.isArray(textList)) return null;
  const text = textList.filter((x): x is string => typeof x === "string");
  if (text.length === 0) return null;
  const parts: string[] = arr(get(entry, "parts")).filter((p): p is string => typeof p === "string");
  const ours = partsOf(app);
  const mine = parts.filter((p) => ours.includes(p));
  const out = (part: string) => part === "cloud" || ((int(get(released, part)) ?? -Infinity) >= version);
  const name = `0.1.${version}`;
  const names = parts.filter((p) => p !== "cloud").map(partName);
  const cloudOnly = parts.length === 0 || (parts.length === 1 && parts[0] === "cloud");
  const place = cloudOnly ? "" : t("core-misc.changelog.place", { parts: names.join(t("core-misc.changelog.and")), version: name });
  let has: boolean | null;
  let note: string;
  if (cloudOnly) [has, note] = [null, t("core-misc.changelog.live")];
  else if (mine.length > 0) {
    if (build !== null && build >= version) [has, note] = [true, t("core-misc.changelog.have")];
    else if (mine.every(out)) [has, note] = [false, app === "web" ? t("core-misc.changelog.reload") : t("core-misc.changelog.update", { version: name })];
    else [has, note] = [false, t("core-misc.changelog.unreleased")];
  } else if (parts.every(out)) [has, note] = [null, t("core-misc.changelog.released")];
  else [has, note] = [null, t("core-misc.changelog.unreleased")];
  return { version, versionName: name, text, place, has, note, mine: mine.length > 0 };
}

export class Changelog implements Owner {
  readonly #host: Host;
  readonly #store: Store;
  readonly #data: Data;
  #failed = false;

  constructor(host: Host, store: Store, data: Data) {
    this.#host = host;
    this.#store = store;
    this.#data = data;
  }

  owns(topic: Topic): boolean {
    return topic.topic === "changelog";
  }

  compute(): Value {
    return { ok: this.value() };
  }

  #changed(): void {
    this.#store.invalidate({ topic: "changelog" });
  }

  /// What the device's host said it is: its app, and its build's number.
  device(facts: J): void {
    const app = typeof get(facts, "app") === "string" ? facts.app : "";
    const raw = get(facts, "build");
    let build: number | null = null;
    if (typeof raw === "string") {
      const last = raw.trim().split(".").pop() ?? "";
      if (/^-?[0-9]+$/.test(last)) build = Number(last);
    }
    this.#data.put(TABLE, "device", { app, build }, false);
    if (build !== null && this.#data.record(TABLE, "seen") === undefined) this.#data.put(TABLE, "seen", build, false);
    this.#changed();
  }

  /// The changelog shown up to this build.
  seen(): void {
    const build = int(get(this.#data.record(TABLE, "device"), "build"));
    if (build !== null) this.#data.put(TABLE, "seen", build, false);
    this.#changed();
  }

  /// Reads the changelog from still.fail cloud (a sync task); what was kept stays when it cannot be read.
  read(): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      const header = channelHeader(this.#host);
      const response = yield* Effect.result(this.#host.fetch({ method: "GET", url: `${this.#host.cloudOrigin()}/v1/changelog`, headers: header ? [header] : [], body: null }));
      const feed = response._tag === "Success" && response.success.status === 200 ? (parseJson(response.success.body) as J) : undefined;
      if (feed !== undefined && Array.isArray(get(feed, "entries"))) {
        this.#failed = false;
        this.#data.put(TABLE, "feed", feed);
      } else this.#failed = true;
      this.#changed();
    });
  }

  /// What build `to` brings `app` at build `from`: the lines of its changes after `from`, up to `to`, newest first. The
  /// changelog kept is read again first when it was read before `to` was out, so a build is known with its lines.
  brings(app: string, from: number, to: number): Effect.Effect<string[]> {
    return Effect.gen({ self: this }, function* () {
      const known = (feed: J) => partsOf(app).every((part) => (int(get(get(feed, "released"), part)) ?? -Infinity) >= to);
      if (!known(this.#data.record(TABLE, "feed"))) yield* this.read();
      const feed = this.#data.record(TABLE, "feed") as J;
      const released = get(feed, "released") ?? null;
      return arr(get(feed, "entries"))
        .map((entry) => item(entry, app, from, released))
        .filter((it) => it !== null && it.mine && it.version > from && it.version <= to)
        .flatMap((it) => it.text as string[]);
    });
  }

  value(): J {
    const device: J = this.#data.record(TABLE, "device") ?? null;
    const app = typeof get(device, "app") === "string" ? device.app : "";
    const build = int(get(device, "build"));
    const seen = int(this.#data.record(TABLE, "seen"));
    const feed = this.#data.record(TABLE, "feed") as J;
    if (feed === undefined) return { app, build, tabs: [], loading: !this.#failed, error: this.#failed ? t("core-misc.changelog.unreadable") : null };
    const released = get(feed, "released") ?? null;
    const now = this.#host.nowMs();
    const offset = this.#host.utcOffsetMin(now);
    const news: J[] = [];
    const tabs = tabsOf(app).map((part) => ({ part, label: t(`core-misc.changelog.tab.${part}`), days: [] as J[] }));
    for (const entry of arr(get(feed, "entries")).slice(0, SHOWN)) {
      const it = item(entry, app, build, released);
      if (it === null) continue;
      const version = it.version as number;
      if (it.mine && build !== null && version <= build && seen !== null && version > seen && news.length < NEWS) news.push(structuredClone(it));
      const ms = (typeof get(entry, "at") === "number" ? entry.at : 0) * 1000;
      const label = format.dayLabel(ms, now, offset);
      const parts: string[] = arr(get(entry, "parts")).filter((p): p is string => typeof p === "string");
      for (const tab of tabs) {
        if (!inTab(tab.part, parts)) continue;
        const last = tab.days[tab.days.length - 1];
        if (last && last.label === label) last.entries.push(structuredClone(it));
        else tab.days.push({ label, entries: [structuredClone(it)] });
      }
    }
    return { app, build, tabs, news: news.length > 0 ? { build: build !== null ? `0.1.${build}` : null, entries: news } : null, loading: false };
  }
}
