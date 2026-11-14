// What changed in still.fail, for people (the `changelog` topic, scripts/changelog.ts): still.fail cloud's
// changelog with what each part has out on this app's channel, one tab a part (this app's first; this app's alone where
// they would all be the same, as the stable channel's are: a release an entry, each every part's), by day, newest first;
// and what this app got since it was last shown here (`news`, until `changelog.seen`). Only the tab asked (`part`; this
// app's where none is said, or one there is not) has its days, its first `limit` changes (a page, `PAGE`, where none is
// said), the others' none, and `more` says how many it has past those: a page more is asked with a larger `limit`,
// `from` the subscription the app holds, and goes as what changed from it (store.ts `#firstFrom`; collections.ts keys
// the tabs, days and changes). The newest `SHOWN` of the feed are what any tab can reach. The beta's feed has thousands
// of entries; every tab of its newest 200 whole was ~190 KB each time the page opened (2026-11-11). Asked with `news`,
// that alone, no tab made: what the chats' list reads of it for its card (the whole was 125 KB on a phone, sent again
// each time the list came back, 2026-11-10). Kept on the device (table `changelog`). The sync reads it as
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
/// The changes of a tab sent where its `limit` is not said: what the page asks first.
const PAGE = 30;
const NEWS = 20;
const TABLE = "changelog";

function partsOf(app: string): string[] {
  return app === "android" ? ["android"] : app === "desktop" ? ["web", "desktop"] : app === "web" ? ["web"] : [];
}

/// The changelog's tabs, this app's first, and the parts each shows: the desktop app carries the web's; the cloud's
/// has the changes that needed no release too.
const TABS = ["desktop", "web", "android", "station", "cloud"];
const ownTab = (app: string) => (TABS.includes(app) ? app : "web");
function tabsOf(app: string): string[] {
  const own = ownTab(app);
  return [own, ...TABS.filter((tab) => tab !== own)];
}
const tabParts = (tab: string) => (tab === "desktop" ? ["web", "desktop"] : [tab]);
function inTab(tab: string, parts: string[]): boolean {
  return (tab === "cloud" && parts.length === 0) || parts.some((p) => tabParts(tab).includes(p));
}

/// A line's kind, from how it starts (修复：, 改进：, 新功能：; scripts/changelog.ts), and the rest of it.
const KINDS: [RegExp, string][] = [[/^(新功能|新增)[：:]\s*/, "new"], [/^(改进|优化|调整|移除)[：:]\s*/, "improve"], [/^修复[：:]\s*/, "fix"]];
function line(text: string): J {
  for (const [start, kind] of KINDS) {
    const m = start.exec(text);
    if (m && m[0].length < text.length) return { kind, label: t(`core-misc.changelog.kind.${kind}`), text: text.slice(m[0].length) };
  }
  return { label: "", text };
}

const int = (v: J): number | null => (typeof v === "number" && Number.isInteger(v) ? v : null);

/// One change as this app shows it in a tab (this app's by default): whether this app has it, in its own; in another,
/// only what is not out yet of that tab's parts. Nothing is said of what is out.
export function item(entry: J, app: string, build: number | null, released: J, tab: string = ownTab(app)): J {
  const version = int(get(entry, "version"));
  if (version === null) return null;
  const textList = get(entry, "text");
  if (!Array.isArray(textList)) return null;
  const text = textList.filter((x): x is string => typeof x === "string");
  if (text.length === 0) return null;
  const parts: string[] = arr(get(entry, "parts")).filter((p): p is string => typeof p === "string");
  const mine = parts.filter((p) => partsOf(app).includes(p));
  const out = (part: string) => part === "cloud" || ((int(get(released, part)) ?? -Infinity) >= version);
  const name = `0.1.${version}`;
  let has: boolean | null = null;
  let note = "";
  if (tab === ownTab(app) && mine.length > 0) {
    if (build !== null && build >= version) has = true;
    else if (mine.every(out)) [has, note] = [false, app === "web" ? t("core-misc.changelog.reload") : t("core-misc.changelog.update", { version: name })];
    else [has, note] = [false, t("core-misc.changelog.unreleased")];
  } else if (!parts.filter((p) => tabParts(tab).includes(p)).every(out)) note = t("core-misc.changelog.unreleased");
  return { version, versionName: name, text, lines: text.map(line), has, note, mine: mine.length > 0 };
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

  compute(topic: Topic): Value {
    if (topic.news === true) return { ok: this.value(true) };
    const limit = typeof topic.limit === "number" ? topic.limit : PAGE;
    return { ok: this.value(false, typeof topic.part === "string" ? topic.part : null, limit) };
  }

  /// Both go out again: the whole, and its news alone.
  #changed(): void {
    this.#store.invalidateAll((topic) => topic.topic === "changelog");
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

  /// What build `to` brings this app (as the device said it is: `client.device`) at build `from`: the lines of its
  /// changes after `from`, up to `to`, newest first. The changelog kept is read again first when it was read before `to`
  /// was out, so a build is known with its lines.
  brings(from: number, to: number): Effect.Effect<string[]> {
    return Effect.gen({ self: this }, function* () {
      const app = this.#app();
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

  /// The app the device said it is (web, desktop or android); "" before it says.
  #app(): string {
    const app = get(this.#data.record(TABLE, "device") ?? null, "app");
    return typeof app === "string" ? app : "";
  }

  /// The changelog as this app shows it; `newsOnly`: what it got since it was last shown alone (`changelog` asked with
  /// `news`), its tabs none. Else every tab there is, but only tab `part`'s days (the first's where it is none of them),
  /// its first `limit` changes, and how many it has past those (`more`).
  value(newsOnly: boolean = false, part: string | null = null, limit: number = PAGE): J {
    const device: J = this.#data.record(TABLE, "device") ?? null;
    const app = this.#app();
    const build = int(get(device, "build"));
    const seen = int(this.#data.record(TABLE, "seen"));
    const feed = this.#data.record(TABLE, "feed") as J;
    if (feed === undefined) return { app, build, tabs: [], loading: !this.#failed, error: this.#failed ? t("core-misc.changelog.unreadable") : null };
    const released = get(feed, "released") ?? null;
    const news: J[] = [];
    const shown = arr(get(feed, "entries")).slice(0, SHOWN);
    for (const entry of shown) {
      if (news.length >= NEWS) break;
      const it = item(entry, app, build, released);
      if (it === null || !it.mine) continue;
      const version = it.version as number;
      if (build !== null && version <= build && seen !== null && version > seen) news.push(it);
    }
    const said = news.length > 0 ? { build: build !== null ? `0.1.${build}` : null, entries: news } : null;
    if (newsOnly) return { app, build, tabs: [], news: said, loading: false };
    // Each tab's changes (those `item` reads as one), by where they are in the feed.
    const all = tabsOf(app);
    const of = new Map<string, J[]>(all.map((tab) => [tab, []]));
    for (const entry of shown) {
      if (item(entry, app, build, released) === null) continue;
      const parts: string[] = arr(get(entry, "parts")).filter((p): p is string => typeof p === "string");
      for (const tab of all) if (inTab(tab, parts)) of.get(tab)!.push(entry);
    }
    // A tab a part only where they part what is said: where each would list the same changes, this app's alone.
    const listed = all.map((tab) => of.get(tab)!.map((e) => e.version).join(","));
    const parted = listed.every((l) => l === listed[0]) ? all.slice(0, 1) : all;
    const asked = part !== null && parted.includes(part) ? part : parted[0]!;
    const now = this.#host.nowMs();
    const offset = this.#host.utcOffsetMin(now);
    const entries = of.get(asked)!;
    const days: J[] = [];
    for (const entry of entries.slice(0, Math.max(limit, 0))) {
      const ms = (typeof get(entry, "at") === "number" ? entry.at : 0) * 1000;
      // the day it is of where the device is: which day of the list it is, the same whatever else that day lists or
      // what the list leaves off (its label only says it)
      const day = format.localDay(ms, offset);
      const it = item(entry, app, build, released, asked);
      const change = { version: it.version, versionName: it.versionName, lines: it.lines, has: it.has, note: it.note };
      const last = days[days.length - 1];
      if (last && last.day === day) last.entries.push(change);
      else days.push({ day, label: format.dayLabel(ms, now, offset), entries: [change] });
    }
    const tabs = parted.map((tab) => ({ part: tab, label: t(`core-misc.changelog.tab.${tab}`), days: tab === asked ? days : [] }));
    const more = entries.length - Math.max(limit, 0);
    return { app, build, tabs, news: said, loading: false, ...(more > 0 ? { more } : {}) };
  }
}
