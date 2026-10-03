// The words people read, in their language: client/i18n/catalog (its README says how it is read).
// A key a language lacks is said in Chinese; one neither has is shown as the key. `{name}` takes the value given as
// `name`; words that change with a number (`{"one", "other"}`) are chosen by `n`.
import zh_android_chat from "../../i18n/catalog/zh/android-chat.json" with { type: "json" };
import zh_android_misc from "../../i18n/catalog/zh/android-misc.json" with { type: "json" };
import zh_android_settings from "../../i18n/catalog/zh/android-settings.json" with { type: "json" };
import zh_cloud from "../../i18n/catalog/zh/cloud.json" with { type: "json" };
import zh_common from "../../i18n/catalog/zh/common.json" with { type: "json" };
import zh_core_logic from "../../i18n/catalog/zh/core-logic.json" with { type: "json" };
import zh_core_misc from "../../i18n/catalog/zh/core-misc.json" with { type: "json" };
import zh_core_views from "../../i18n/catalog/zh/core-views.json" with { type: "json" };
import zh_desktop from "../../i18n/catalog/zh/desktop.json" with { type: "json" };
import zh_station from "../../i18n/catalog/zh/station.json" with { type: "json" };
import zh_web_main from "../../i18n/catalog/zh/web-main.json" with { type: "json" };
import zh_web_mobile from "../../i18n/catalog/zh/web-mobile.json" with { type: "json" };
import zh_web_pages from "../../i18n/catalog/zh/web-pages.json" with { type: "json" };
import en_android_chat from "../../i18n/catalog/en/android-chat.json" with { type: "json" };
import en_android_misc from "../../i18n/catalog/en/android-misc.json" with { type: "json" };
import en_android_settings from "../../i18n/catalog/en/android-settings.json" with { type: "json" };
import en_cloud from "../../i18n/catalog/en/cloud.json" with { type: "json" };
import en_common from "../../i18n/catalog/en/common.json" with { type: "json" };
import en_core_logic from "../../i18n/catalog/en/core-logic.json" with { type: "json" };
import en_core_misc from "../../i18n/catalog/en/core-misc.json" with { type: "json" };
import en_core_views from "../../i18n/catalog/en/core-views.json" with { type: "json" };
import en_desktop from "../../i18n/catalog/en/desktop.json" with { type: "json" };
import en_station from "../../i18n/catalog/en/station.json" with { type: "json" };
import en_web_main from "../../i18n/catalog/en/web-main.json" with { type: "json" };
import en_web_mobile from "../../i18n/catalog/en/web-mobile.json" with { type: "json" };
import en_web_pages from "../../i18n/catalog/en/web-pages.json" with { type: "json" };

export type Lang = "zh" | "en";
type Words = Record<string, string | { one?: string; other?: string }>;

const CATALOG: Record<Lang, Words> = {
  zh: { ...zh_android_chat, ...zh_android_misc, ...zh_android_settings, ...zh_cloud, ...zh_common, ...zh_core_logic, ...zh_core_misc, ...zh_core_views, ...zh_desktop, ...zh_station, ...zh_web_main, ...zh_web_mobile, ...zh_web_pages, } as Words,
  en: { ...en_android_chat, ...en_android_misc, ...en_android_settings, ...en_cloud, ...en_common, ...en_core_logic, ...en_core_misc, ...en_core_views, ...en_desktop, ...en_station, ...en_web_main, ...en_web_mobile, ...en_web_pages, } as Words,
};

/// From a setting or a locale (`zh`, `zh-CN`, `en-US`, …): Chinese for Chinese, English for any other; Chinese when
/// nothing is said.
export function fromLocale(locale: string): Lang {
  const l = locale.trim().toLowerCase();
  return l === "" || l.startsWith("zh") ? "zh" : "en";
}

let CURRENT: Lang = "zh";
/// Whether the prefs may change the language (tests run side by side in one process and expect Chinese, as the Rust
/// core's tests do: `cfg!(test)`).
let FOLLOW = true;

/// The language words are said in where no one is asked (the core: its person's, as their prefs say).
export function current(): Lang {
  return CURRENT;
}

export function setCurrent(lang: Lang): void {
  CURRENT = lang;
}

export function follows(): boolean {
  return FOLLOW;
}

/// Tests: the language stays Chinese whatever the prefs say.
export function holdLanguage(): void {
  FOLLOW = false;
  CURRENT = "zh";
}

/// Whether a language has the key itself.
export function has(lang: Lang, key: string): boolean {
  return key in CATALOG[lang];
}

export type Args = Record<string, unknown>;

/// Rust's Display of an argument: whole floats without `.0`.
function shown(v: unknown): string {
  if (typeof v === "number") return Number.isFinite(v) ? String(v) : v > 0 ? "inf" : v < 0 ? "-inf" : "NaN";
  return String(v);
}

/// The words for `key` in `lang`, with `args` put in.
export function tr(lang: Lang, key: string, args?: Args): string {
  const found = CATALOG[lang][key] ?? CATALOG.zh[key];
  let text: string;
  if (typeof found === "string") text = found;
  else if (found && typeof found === "object") {
    const one = args !== undefined && "n" in args && shown(args.n).trim() === "1";
    text = (one ? found.one : found.other) ?? found.other ?? key;
  } else text = key;
  return fill(text, args);
}

/// `t!("key", name = value)`: the words in the current language.
export function t(key: string, args?: Args): string {
  return tr(CURRENT, key, args);
}

function fill(text: string, args?: Args): string {
  if (!args || Object.keys(args).length === 0 || !text.includes("{")) return text;
  let out = "";
  let rest = text;
  for (;;) {
    const open = rest.indexOf("{");
    if (open < 0) break;
    out += rest.slice(0, open);
    const after = rest.slice(open + 1);
    const close = after.indexOf("}");
    if (close >= 0 && /^[A-Za-z0-9_]*$/.test(after.slice(0, close))) {
      const name = after.slice(0, close);
      if (Object.prototype.hasOwnProperty.call(args, name)) out += shown(args[name]);
      else out += rest.slice(open, open + close + 2);
      rest = after.slice(close + 1);
    } else {
      out += "{";
      rest = after;
    }
  }
  return out + rest;
}
