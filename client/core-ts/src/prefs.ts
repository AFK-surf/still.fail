// What this device keeps of how its person likes it (the `prefs` topic; prefs.rs): one record in the data center
// (table `prefs`, key `device`), written by `prefs.set`; with it, what the device is (`client.device`) and what follows.
import * as brand from "./brand.ts";
import { conform } from "./conform.ts";
import type { Data } from "./data.ts";
import { CoreError } from "./error.ts";
import { fromLocale, follows, setCurrent, t, tr, type Lang } from "./i18n.ts";
import { ofAddress } from "./workspace.ts";
import { equal, isObject } from "./util.ts";

const FIELDS = ["onlyMine", "onlyWatching", "onlyDecisions", "listFilter", "appearance", "rowPicture", "absoluteTime", "language", "keys", "workspace", "lastChat", "chatTabs", "resume", "invite"];
const MAPS = ["listFilter", "keys", "lastChat", "chatTabs", "resume"];
const TABS_KEPT = 200;
const DEFERRED_KEPT = 200;
const PREFS = { topic: "prefs" };

type Map_ = Record<string, unknown>;

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
  // serde_json's Map iterates in key order.
  for (const field of Object.keys(patch).sort()) {
    const value = patch[field];
    if (!FIELDS.includes(field)) throw CoreError.invalid(t("core-misc.params.unknown_field", { field }));
    if (isObject(value) && MAPS.includes(field)) {
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
      const ONE_OF = ["onlyMine", "onlyWatching", "onlyDecisions"];
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

/// A decision set aside on this device (待定), kept as `decisionsDeferred` by where it is, with when.
export function deferDecision(data: Data, at: string, now: number): void {
  const prefs = kept(data);
  if (!isObject(prefs.decisionsDeferred)) prefs.decisionsDeferred = {};
  const map = prefs.decisionsDeferred as Map_;
  const last = Object.values(map).reduce<number>((m, v) => (typeof v === "number" ? Math.max(m, v) : m), 0);
  map[at] = Math.max(now, last + 1);
  const keys = Object.keys(map);
  if (keys.length > DEFERRED_KEPT) {
    const byAge = keys.map((k) => [typeof map[k] === "number" ? (map[k] as number) : 0, k] as [number, string]).sort((a, b) => a[0] - b[0] || (a[1] < b[1] ? -1 : 1));
    for (const [, key] of byAge.slice(0, keys.length - DEFERRED_KEPT)) delete map[key];
  }
  data.set(PREFS, prefs);
}

/// A decision no longer set aside (answered, or dismissed).
export function undeferDecision(data: Data, at: string): void {
  const prefs = kept(data);
  const map = prefs.decisionsDeferred;
  if (!isObject(map) || !(at in map)) return;
  delete map[at];
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

/// What the device is, from what its host says (`client.device`).
export function device(data: Data, facts: unknown): void {
  const said = (k: string) => {
    const v = isObject(facts) ? facts[k] : undefined;
    return typeof v === "string" ? v.trim() : "";
  };
  const app = said("app");
  if (!["web", "desktop", "android"].includes(app)) throw CoreError.invalid(t("core-misc.params.app"));
  const build = said("build");
  const agent = said("userAgent");
  const model = said("model");
  const has = (words: string[]) => words.some((w) => agent.toLowerCase().includes(w.toLowerCase()));
  const phone = app === "android" || (app === "web" && has(["Android", "iPhone", "iPad"]));
  const os = has(["iPhone", "iPad"]) ? "iOS" : agent.includes("Mac OS X") ? "macOS" : agent.includes("Windows") ? "Windows" : agent.includes("Android") ? "Android" : agent.includes("Linux") ? "Linux" : "";
  const browser = agent.includes("Edg/") ? "Edge" : agent.includes("Chrome/") ? "Chrome" : agent.includes("Firefox/") ? "Firefox" : agent.includes("Safari/") ? "Safari" : "";
  const withMore = (s: string) => (s === "" ? "" : ` · ${s}`);
  const b = build === "" ? "" : ` ${build}`;
  const from = app === "web" ? `web${b} (${phone ? "phone" : "pc"})` : `${app}${b}`;
  const prefs = kept(data);
  const told: Map_ = { app, phone, handoff: app === "web" && !phone, sentFrom: from };
  const locale = said("locale");
  if (locale !== "") told.locale = locale;
  prefs.device = told;
  const lang = withLang(prefs);
  const name = brand.name();
  let deviceName: string;
  if (app === "android") deviceName = tr(lang, "core-misc.device.android", { brand: name, more: withMore(model) });
  else if (app === "desktop") deviceName = tr(lang, "core-misc.device.desktop", { brand: name, more: withMore(os) });
  else deviceName = tr(lang, "core-misc.device.web", { brand: name, browser: browser === "" ? tr(lang, "core-misc.device.browser") : browser, more: withMore(os) });
  told.name = deviceName;
  data.set(PREFS, prefs);
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
