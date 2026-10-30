// What this device keeps of how its person likes it (the `prefs` topic; prefs.rs): one record in the data center
// (table `prefs`, key `device`), written by `prefs.set`; with it, what the device is (`client.device`) and what follows.
import * as brand from "./brand.ts";
import * as fonts from "./fonts.ts";
import { conform } from "./conform.ts";
import { railView } from "./rail.ts";
import type { Data } from "./data.ts";
import { CoreError } from "./error.ts";
import { current, fromLocale, follows, setCurrent, t, tr, type Lang } from "./i18n.ts";
import * as keymap from "./keymap.ts";
import { SCREEN_FPS, type ScreenFps } from "./station/wire.ts";
import { ofAddress } from "./workspace.ts";
import { equal, isObject } from "./util.ts";

const FIELDS = ["onlyMine", "onlyWatching", "listFilter", "appearance", "motion", "rowPicture", "absoluteTime", "language", "keys", "workspace", "lastChat", "chatTabs", "dropFiles", "dropAs", "archiveHint", "screenTouch", "screenQuality", "screenFps", "screenCodec", "screenMouse", "driveViews", "filesTabs", "driveFavorites", "resume", "invite", "badge", "badgeKinds", "reader", "lockNotice", "rail", "rails", "bars", "barsBy", "fonts", "previewSizes", "sidebars", "trouble", "jobsSeen", "failsGone", "fillOff", "fillMax", "shareLook"];
const MAPS = ["listFilter", "keys", "lastChat", "chatTabs", "dropFiles", "driveViews", "filesTabs", "driveFavorites", "resume", "lockNotice", "rails", "barsBy", "previewSizes", "sidebars", "trouble", "jobsSeen", "failsGone"];
const TABS_KEPT = 200;
/// At most this many jobs kept as looked at in one workspace's bell.
const JOBS_SEEN_KEPT = 200;
/// At most this many failures kept as let go in one workspace's 待处理.
const FAILS_GONE_KEPT = 200;
const PREFS = { topic: "prefs" };

type Map_ = Record<string, unknown>;

/// How the drive's reader lays text out on this device (docs/drive.md): each number within its bounds, its default
/// where none is kept; the papers and faces there are.
const READER_NUMBERS = { size: [12, 32, 18], line: [1.2, 2.4, 1.7], margin: [8, 44, 22] } as const;
const PAPERS = ["follow", "white", "green", "grey", "night"];
const FACES = ["serif", "sans"];

export function readerOf(v: unknown): Map_ {
  const r = isObject(v) ? v : {};
  const num = (k: keyof typeof READER_NUMBERS, step: number) => {
    const [min, max, fallback] = READER_NUMBERS[k];
    const n = r[k];
    return typeof n === "number" && Number.isFinite(n) ? Math.min(max, Math.max(min, Math.round(n / step) * step)) : fallback;
  };
  return {
    size: num("size", 1),
    line: Math.round(num("line", 0.1) * 10) / 10,
    margin: num("margin", 1),
    face: FACES.includes(r.face as string) ? r.face : "sans",
    indent: typeof r.indent === "boolean" ? r.indent : true,
    paper: PAPERS.includes(r.paper as string) ? r.paper : "follow",
  };
}

export type BadgeKinds = { on: boolean; wait: boolean; failed: boolean; done: boolean; message: boolean; services: boolean };

/// What the badge counts, kind by kind: as kept (`badgeKinds`, what it does not say as before), or as the older
/// `badge` says (decisions: the cards; attention, the default: and what went wrong; all: and the unread). `services`
/// is the rail's bell's alone: the services and jobs left up long light it until looked at (never the app's number).
export function badgeKindsOf(prefs: unknown): BadgeKinds {
  const by = isObject(prefs) ? prefs.badge : null;
  const base = { on: true, wait: true, failed: by !== "decisions", done: by === "all", message: by === "all", services: true };
  const k = isObject(prefs) && isObject(prefs.badgeKinds) ? prefs.badgeKinds : {};
  const flag = (name: keyof BadgeKinds) => (typeof k[name] === "boolean" ? k[name] as boolean : base[name]);
  return { on: flag("on"), wait: flag("wait"), failed: flag("failed"), done: flag("done"), message: flag("message"), services: flag("services") };
}

/// The jobs left up long in a workspace that its bell has shown (`jobsSeen`, by workspace: each `<station>/<id>`, as
/// the `longJobs` view's `ids` were when it opened).
export function jobsSeenOf(prefs: unknown, workspace: string): Set<string> {
  const by = isObject(prefs) && isObject(prefs.jobsSeen) ? prefs.jobsSeen[workspace] : null;
  return new Set(Array.isArray(by) ? by.filter((k): k is string => typeof k === "string") : []);
}

/// The failures let go in a workspace's 待处理 (`failsGone`, by workspace: each as its item's `failure` said it).
export function failsGoneOf(prefs: unknown, workspace: string): Set<string> {
  const by = isObject(prefs) && isObject(prefs.failsGone) ? prefs.failsGone[workspace] : null;
  return new Set(Array.isArray(by) ? by.filter((k): k is string => typeof k === "string") : []);
}

/// The looks the card shared can be drawn in (`shareLook`, chosen under it): none kept, night.
export const SHARE_LOOKS = ["night", "poster", "receipt", "terminal"];

export type ArchiveHint = "off" | "done" | "reviewed";

/// When a done chat is offered to archive (`archiveHint`, the appearance page): off, never; reviewed, only once its
/// station's archive review recommended it (never where the review is off); done, the default (none kept), whenever
/// nothing is left in it, going by the review where its station has one on.
export function archiveHintOf(prefs: unknown): ArchiveHint {
  const v = isObject(prefs) ? prefs.archiveHint : null;
  return v === "off" || v === "reviewed" ? v : "done";
}

/// The places a phone's bottom bar can hold (web/src/mobile/Bar.tsx, the Android app's ui/Bar.kt), in no order.
export const BAR_PLACES = ["chats", "files", "stations", "profiles", "connects", "usage", "archive"];
/// At most this many places in one bar.
export const BAR_SIZE = 4;
const BARS_DEFAULT = { sets: [["chats", "files", "profiles", "stations"], ["usage", "connects", "archive"]], current: 0 };

/// A phone's bottom bars as kept, whole: each bar one to four known places, none twice in a bar; at least one bar; the
/// one in view one of them. What is not that (nothing kept, a place this build does not know) reads as the default or
/// is left out.
export function barsOf(v: unknown): { sets: string[][]; current: number } {
  if (!isObject(v) || !Array.isArray(v.sets)) return { sets: BARS_DEFAULT.sets.map((s) => [...s]), current: BARS_DEFAULT.current };
  const sets = v.sets
    .map((set) => (Array.isArray(set) ? [...new Set(set.filter((k): k is string => typeof k === "string" && BAR_PLACES.includes(k)))].slice(0, BAR_SIZE) : []))
    .filter((set) => set.length > 0);
  if (!sets.length) return { sets: BARS_DEFAULT.sets.map((s) => [...s]), current: BARS_DEFAULT.current };
  const n = typeof v.current === "number" && Number.isFinite(v.current) ? Math.round(v.current) : 0;
  return { sets, current: Math.min(sets.length - 1, Math.max(0, n)) };
}

/// The lists a workspace's chat list can show (`listFilter`'s words).
const LIST_FILTERS = ["all", "mine", "watching", "archive"];

/// The list filters as kept, without those this build does not know (奏, gone: the list it shows then is all).
function listFiltersOf(v: unknown): Map_ {
  return isObject(v) ? Object.fromEntries(Object.entries(v).filter(([, f]) => LIST_FILTERS.includes(f as string))) : {};
}

/// The prefs as they go out: the reader's settings whole, the bottom bars (each workspace's too), the faces, and the
/// keymap and the rail.
export function shown(v: unknown): unknown {
  if (!isObject(v)) return v;
  const by = isObject(v.barsBy) ? Object.fromEntries(Object.entries(v.barsBy).map(([ws, b]) => [ws, barsOf(b)])) : {};
  return { ...v, listFilter: listFiltersOf(v.listFilter), reader: readerOf(v.reader), bars: barsOf(v.bars), barsBy: by, fonts: fonts.chosen(v.fonts), faces: fonts.shown(v.fonts), keymap: keymap.view(v), railView: railView(v) };
}

/// What is kept, as kept (no defaults filled in).
function kept(data: Data): Map_ {
  const v = data.get(PREFS);
  return isObject(v) ? (v as Map_) : {};
}

/// Puts `patch` into what is kept: a field given replaces it and null removes it; a map's entries are each put so.
/// `fill`: only what is not kept yet.
export function set(data: Data, patch: unknown, fill: boolean, now: number): void {
  if (!isObject(patch)) throw CoreError.invalid(t("core-misc.params.not_object"));
  const prefs = kept(data);
  // What an older build kept for 奏 is not kept on.
  if ("listFilter" in prefs) prefs.listFilter = listFiltersOf(prefs.listFilter);
  delete prefs.onlyDecisions;
  delete prefs.decisionsDeferred;
  // serde_json's Map iterates in key order.
  for (const field of Object.keys(patch).sort()) {
    const value = patch[field];
    if (!FIELDS.includes(field)) throw CoreError.invalid(t("core-misc.params.unknown_field", { field }));
    if (field === "bars" && value !== null) {
      // Kept as it reads: what this build does not know is not kept.
      prefs.bars = barsOf(value);
    } else if (field === "reader" && isObject(value)) {
      // Only what is said changes: one setting of the 排版 sheet at a time.
      prefs.reader = readerOf({ ...(isObject(prefs.reader) ? prefs.reader : {}), ...value });
    } else if (field === "fonts" && isObject(value)) {
      // Only the places said change; a face not there is an error.
      const put = fonts.put(prefs.fonts, value);
      if (typeof put === "string") throw CoreError.invalid(t("core-misc.params.invalid", { error: `fonts.${put}` }));
      if (Object.keys(put).length) prefs.fonts = put;
      else delete prefs.fonts;
    } else if (field === "badgeKinds" && isObject(value)) {
      // Kept whole: what is not said stays as the badge counts now (as the older `badge` says, first).
      prefs.badgeKinds = badgeKindsOf({ ...prefs, badgeKinds: { ...(isObject(prefs.badgeKinds) ? prefs.badgeKinds : {}), ...value } });
    } else if (isObject(value) && MAPS.includes(field)) {
      if (!(field in prefs)) prefs[field] = {};
      const map = prefs[field];
      if (!isObject(map)) continue;
      for (const key of Object.keys(value).sort()) {
        let entry: unknown = value[key];
        if (fill && key in map) continue;
        if (entry === null) {
          delete map[key];
          continue;
        }
        // The jobs a bell has shown: the newest of them.
        if (field === "jobsSeen" && Array.isArray(entry)) entry = entry.slice(-JOBS_SEEN_KEPT);
        // The failures let go: added to those kept, the newest of them.
        if (field === "failsGone" && Array.isArray(entry)) {
          const was = Array.isArray(map[key]) ? (map[key] as unknown[]) : [];
          entry = [...new Set([...was, ...entry])].slice(-FAILS_GONE_KEPT);
        }
        // A workspace's bottom bars, kept as they read (as `bars`).
        if (field === "barsBy") entry = barsOf(entry);
        // An action's keys, each a binding as the keymap has it (keymap.ts); one that is none is refused.
        if (field === "keys") {
          const keys = Array.isArray(entry) ? entry.map(keymap.binding) : [null];
          if (keys.includes(null)) throw CoreError.invalid(t("core-misc.params.invalid", { error: `keys.${key}` }));
          entry = [...new Set(keys)];
        }
        if (field === "chatTabs" && isObject(entry)) {
          const last = Object.values(map).reduce<number>((m, v) => (isObject(v) && typeof v.at === "number" ? Math.max(m, v.at) : m), 0);
          entry = { ...entry, at: Math.max(now, last + 1) };
        }
        map[key] = entry as never;
      }
    } else if (fill && field in prefs) {
      // kept
    } else if (value === null) {
      delete prefs[field];
    } else {
      const ONE_OF = ["onlyMine", "onlyWatching"];
      if (ONE_OF.includes(field) && value === true && !fill) for (const other of ONE_OF) if (other !== field) delete prefs[other];
      prefs[field] = value;
    }
  }
  const tabs = prefs.chatTabs;
  if (isObject(tabs) && Object.keys(tabs).length > TABS_KEPT) {
    const byUse = Object.entries(tabs).map(([k, v]) => [isObject(v) && typeof v.at === "number" ? v.at : 0, k] as [number, string]);
    byUse.sort((a, b) => a[0] - b[0]);
    for (const [, key] of byUse.slice(0, byUse.length - TABS_KEPT)) delete tabs[key];
  }
  if ("badge" in prefs && !["decisions", "attention", "all"].includes(prefs.badge as string)) throw CoreError.invalid(t("core-misc.params.invalid", { error: "badge" }));
  if ("motion" in prefs && prefs.motion !== "reduce" && prefs.motion !== "full") throw CoreError.invalid(t("core-misc.params.invalid", { error: "motion" }));
  if ("dropAs" in prefs && prefs.dropAs !== "file" && prefs.dropAs !== "path") throw CoreError.invalid(t("core-misc.params.invalid", { error: "dropAs" }));
  if ("shareLook" in prefs && !SHARE_LOOKS.includes(prefs.shareLook as string)) throw CoreError.invalid(t("core-misc.params.invalid", { error: "shareLook" }));
  if ("archiveHint" in prefs && !["off", "done", "reviewed"].includes(prefs.archiveHint as string)) throw CoreError.invalid(t("core-misc.params.invalid", { error: "archiveHint" }));
  if ("screenTouch" in prefs && prefs.screenTouch !== "direct" && prefs.screenTouch !== "pad") throw CoreError.invalid(t("core-misc.params.invalid", { error: "screenTouch" }));
  if ("screenQuality" in prefs && !["smooth", "hd", "original"].includes(prefs.screenQuality as string)) throw CoreError.invalid(t("core-misc.params.invalid", { error: "screenQuality" }));
  if ("screenFps" in prefs && !SCREEN_FPS.includes(prefs.screenFps as ScreenFps)) throw CoreError.invalid(t("core-misc.params.invalid", { error: "screenFps" }));
  if ("screenCodec" in prefs && prefs.screenCodec !== "h264") throw CoreError.invalid(t("core-misc.params.invalid", { error: "screenCodec" }));
  if ("screenMouse" in prefs && prefs.screenMouse !== "off") throw CoreError.invalid(t("core-misc.params.invalid", { error: "screenMouse" }));
  if (isObject(prefs.previewSizes) && Object.values(prefs.previewSizes).some((v) => typeof v !== "string" || !/^[0-9]{1,4}(x[0-9]{1,4})?$/.test(v))) throw CoreError.invalid(t("core-misc.params.invalid", { error: "previewSizes" }));
  if (isObject(prefs.sidebars) && Object.values(prefs.sidebars).some((v) => typeof v !== "string" || !/^([0-9]{1,4}|[0-9]{1,4},closed|closed)$/.test(v))) throw CoreError.invalid(t("core-misc.params.invalid", { error: "sidebars" }));
  if (isObject(prefs.trouble) && (Object.keys(prefs.trouble).some((k) => !/\n(seen|gone)$/.test(k)) || Object.values(prefs.trouble).some((v) => v !== null && (typeof v !== "string" || v.length > 2000)))) throw CoreError.invalid(t("core-misc.params.invalid", { error: "trouble" }));
  if (isObject(prefs.jobsSeen) && Object.values(prefs.jobsSeen).some((v) => !Array.isArray(v) || v.some((k) => typeof k !== "string" || k.length > 300))) throw CoreError.invalid(t("core-misc.params.invalid", { error: "jobsSeen" }));
  if (isObject(prefs.failsGone) && Object.values(prefs.failsGone).some((v) => !Array.isArray(v) || v.some((k) => typeof k !== "string" || k.length > 400))) throw CoreError.invalid(t("core-misc.params.invalid", { error: "failsGone" }));
  if ("badgeKinds" in prefs && prefs.badgeKinds !== null && !isObject(prefs.badgeKinds)) throw CoreError.invalid(t("core-misc.params.invalid", { error: "badgeKinds" }));
  if ("fillOff" in prefs && typeof prefs.fillOff !== "boolean") throw CoreError.invalid(t("core-misc.params.invalid", { error: "fillOff" }));
  if ("fillMax" in prefs && (typeof prefs.fillMax !== "number" || !Number.isSafeInteger(prefs.fillMax) || prefs.fillMax < 0)) throw CoreError.invalid(t("core-misc.params.invalid", { error: "fillMax" }));
  if ("language" in prefs && !(prefs.language === "zh" || prefs.language === "en")) throw CoreError.invalid(t("core-misc.params.language"));
  withLang(prefs);
  const shaped = conform("PrefsView", prefs);
  if ("error" in shaped) throw CoreError.invalid(t("core-misc.params.invalid", { error: shaped.error }));
  data.set(PREFS, prefs);
}

/// A chat opened (`client.focus`): kept as the one last open in its workspace (`openChat`).
export function chatOpened(data: Data, station: string, key: string): void {
  const workspace = ofAddress(station);
  const chat = { station, key };
  const prefs = kept(data);
  if (isObject(prefs.openChat) && equal(prefs.openChat[workspace], chat)) return;
  if (!isObject(prefs.openChat)) prefs.openChat = {};
  (prefs.openChat as Map_)[workspace] = chat;
  data.set(PREFS, prefs);
}

/// A new chat shown in `workspace` (`client.focus {newChat}`): it is what the workspace goes back to, so no chat is kept
/// as the one last open there (`openChat`, nor the path an older core kept: `lastChat`).
export function newChatOpened(data: Data, workspace: string): void {
  const prefs = kept(data);
  const open = isObject(prefs.openChat) && workspace in prefs.openChat;
  const path = isObject(prefs.lastChat) && workspace in prefs.lastChat;
  if (!open && !path) return;
  if (open) delete (prefs.openChat as Map_)[workspace];
  if (path) delete (prefs.lastChat as Map_)[workspace];
  data.set(PREFS, prefs);
}

/// One version dismissed on this device, by workspace/station.
export function dismissStationUpdate(data: Data, station: string, version: string): void {
  const prefs = kept(data);
  if (!isObject(prefs.stationUpdatesDismissed)) prefs.stationUpdatesDismissed = {};
  (prefs.stationUpdatesDismissed as Map_)[station] = version;
  data.set(PREFS, prefs);
}

/// A workspace made: the invite code kept is done with.
export function inviteUsed(data: Data): void {
  if ("invite" in kept(data)) {
    try {
      set(data, { invite: null }, false, 0);
    } catch {}
  }
}

/// What the device is, from what its host says (`client.device`: app, build, userAgent, model, locale, `machine`, the
/// name its owner knows it by (a computer's name, a phone's as its settings say), and `client`, the name of an app other
/// than still.fail's own that runs this core).
export function device(data: Data, facts: unknown): void {
  const said = (k: string) => {
    const v = isObject(facts) ? facts[k] : undefined;
    return typeof v === "string" ? v.trim() : "";
  };
  const app = said("app");
  if (!["web", "desktop", "android", "ios"].includes(app)) throw CoreError.invalid(t("core-misc.params.app"));
  const build = said("build");
  const agent = said("userAgent");
  const model = said("model");
  const machine = said("machine").slice(0, 60);
  const has = (words: string[]) => words.some((w) => agent.toLowerCase().includes(w.toLowerCase()));
  const phone = app === "android" || app === "ios" || (app === "web" && has(["Android", "iPhone", "iPad"]));
  const os = has(["iPhone", "iPad"]) ? "iOS" : agent.includes("Mac OS X") ? "macOS" : agent.includes("Windows") ? "Windows" : agent.includes("Android") ? "Android" : agent.includes("Linux") ? "Linux" : "";
  const browser = agent.includes("Edg/") ? "Edge" : agent.includes("Chrome/") ? "Chrome" : agent.includes("Firefox/") ? "Firefox" : agent.includes("Safari/") ? "Safari" : "";
  const withMore = (s: string) => (s === "" ? "" : ` · ${s}`);
  const b = build === "" ? "" : ` ${build}`;
  const from = app === "web" ? `web${b} (${phone ? "phone" : "pc"})` : `${app}${b}`;
  const prefs = kept(data);
  // `mac`: keys are said as on a Mac (⌘, ⌥), as an Apple device's keyboard has them (keymap.ts)
  const told: Map_ = { app, phone, handoff: app === "web" && !phone, sentFrom: from, mac: app === "ios" || has(["Mac OS X", "iPhone", "iPad"]) };
  const locale = said("locale");
  if (locale !== "") told.locale = locale;
  prefs.device = told;
  const lang = withLang(prefs);
  // `client`: an app of its own that runs this core, named so (still.fail mbui), told apart from still.fail's own
  // where devices are listed and approved; else the brand's
  const client = said("client").slice(0, 40);
  if (client !== "") told.client = client;
  brand.setOwnApp(client === "");
  const name = client !== "" ? client : brand.name();
  // which machine it is where it says (the person's several Macs, their phone as they named it), else what kind
  let deviceName: string;
  if (app === "android") deviceName = tr(lang, "core-misc.device.android", { brand: name, more: withMore(machine || model) });
  else if (app === "ios") deviceName = tr(lang, "core-misc.device.ios", { brand: name, more: withMore(machine || model) });
  else if (app === "desktop") deviceName = tr(lang, "core-misc.device.desktop", { brand: name, more: withMore(machine || os) });
  else deviceName = tr(lang, "core-misc.device.web", { brand: name, browser: browser === "" ? tr(lang, "core-misc.device.browser") : browser, more: withMore(os) });
  told.name = deviceName;
  data.set(PREFS, prefs);
}

/// The apps a device names itself as (`device`, core-misc.device.*).
const APPS = ["desktop", "android", "ios", "web"] as const;

/// An app's words in a device's name, after its brand, in `lang`: " 桌面版" ("{brand} 桌面版 · {machine}"), " Web".
function appWords(lang: Lang, app: (typeof APPS)[number]): string {
  return tr(lang, `core-misc.device.${app}`, { brand: "", browser: "\u0000", more: "" }).split(" · ")[0] ?? "";
}

/// A device's name as `device` makes it, taken apart: which app it is (`group`, the same whichever language it was
/// named in; `app`, its brand's in this language: still.fail 桌面版) and the machine it is on (左子健的 MacBook Air,
/// Chrome · macOS; empty where it said none). A name `device` did not make (one given when it was approved, an older
/// client's) is all machine, its app not known.
export function deviceParts(label: string): { group: string | null; app: string | null; machine: string } {
  // (its brand is what comes before the first of the apps' words in it: a web page's machine may end in Android)
  let found: { at: number; words: string; app: (typeof APPS)[number] } | null = null;
  for (const lang of ["zh", "en"] as const) {
    for (const app of APPS) {
      const words = appWords(lang, app);
      const before = label.indexOf(`${words} · `);
      const at = before >= 0 ? before : label.endsWith(words) ? label.length - words.length : -1;
      if (at > 0 && (found === null || at < found.at)) found = { at, words, app };
    }
  }
  if (found === null || label.slice(0, found.at).includes(" · ")) return { group: null, app: null, machine: label };
  const brand = label.slice(0, found.at);
  return { group: `${found.app} ${brand}`, app: brand + appWords(current(), found.app), machine: label.slice(found.at + found.words.length + 3) };
}

/// The language things are said in (`lang`): as chosen, else as the device is; the core says its words in it.
function withLang(prefs: Map_): Lang {
  const chosen = typeof prefs.language === "string" ? prefs.language : undefined;
  const dev = isObject(prefs.device) && typeof prefs.device.locale === "string" ? prefs.device.locale : undefined;
  const lang = fromLocale(chosen ?? dev ?? "");
  prefs.lang = lang;
  if (follows()) setCurrent(lang);
  return lang;
}

/// The core says its words in the language kept (at start).
export function followLang(data: Data): void {
  const lang = kept(data).lang;
  if (typeof lang === "string" && follows()) setCurrent(fromLocale(lang));
}

/// The brand as the device last said what app it is (at start, till it says so again): still.fail's, or one of its own.
export function followApp(data: Data): void {
  brand.setOwnApp(deviceSaid(data, "client") === null);
}

function deviceSaid(data: Data, field: string): string | null {
  const d = kept(data).device;
  const v = isObject(d) ? d[field] : undefined;
  return typeof v === "string" && v !== "" ? v : null;
}

/// The app a message is sent from ("web 0.1.1150 (phone)"); none until told.
export function sentFrom(data: Data): string | null {
  return deviceSaid(data, "sentFrom");
}

/// The name the device signs in as.
export function deviceName(data: Data): string | null {
  return deviceSaid(data, "name");
}
