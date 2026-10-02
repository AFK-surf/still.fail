// The words people read, in their language: the same catalog the core and the Android app read
// (client/i18n/catalog/<lang>/*.json; client/i18n/src/lib.rs says how). Which language is the core's (prefs `lang`: as
// chosen, else as the device is); before the core answers, or with a core from before languages, the browser's.
// `t` reads it as it is now: the app's root is drawn again, whole, when it changes (I18nRoot).
import { createElement, Fragment, type ReactNode } from "react";
import { prefs, usePrefs, type Prefs } from "./prefs.ts";
import zhCommon from "../../client/i18n/catalog/zh/common.json" with { type: "json" };
import enCommon from "../../client/i18n/catalog/en/common.json" with { type: "json" };
import zhWebPages from "../../client/i18n/catalog/zh/web-pages.json" with { type: "json" };
import enWebPages from "../../client/i18n/catalog/en/web-pages.json" with { type: "json" };
import zhWebMobile from "../../client/i18n/catalog/zh/web-mobile.json" with { type: "json" };
import enWebMobile from "../../client/i18n/catalog/en/web-mobile.json" with { type: "json" };
import zhWebMain from "../../client/i18n/catalog/zh/web-main.json" with { type: "json" };
import enWebMain from "../../client/i18n/catalog/en/web-main.json" with { type: "json" };
import zhDesktop from "../../client/i18n/catalog/zh/desktop.json" with { type: "json" };
import enDesktop from "../../client/i18n/catalog/en/desktop.json" with { type: "json" };

export type Lang = "zh" | "en";
type Words = Record<string, string | { one?: string; other: string }>;

const CATALOG: Record<Lang, Words> = {
  zh: { ...zhCommon, ...zhWebPages, ...zhWebMobile, ...zhWebMain, ...zhDesktop } as Words,
  en: { ...enCommon, ...enWebPages, ...enWebMobile, ...enWebMain, ...enDesktop } as Words,
};

/** Chinese for Chinese, English for any other; Chinese when nothing is said (as the core decides, i18n/src/lib.rs). */
export function langOf(locale: string | undefined | null): Lang {
  const l = (locale ?? "").trim().toLowerCase();
  return !l || l.startsWith("zh") ? "zh" : "en";
}

function browserLocale(): string {
  return typeof navigator === "undefined" ? "" : navigator.language ?? "";
}

function langFrom(p: Prefs): Lang {
  if (p.lang === "zh" || p.lang === "en") return p.lang;
  return langOf(p.language ?? browserLocale());
}

/** The language things are said in now. */
export function lang(): Lang {
  return langFrom(prefs());
}

/** The language, redrawn when it changes. */
export function useLang(): Lang {
  return langFrom(usePrefs());
}

/** The browser's language, for the core to follow when none is chosen (`client.device`'s `locale`). */
export function deviceLocale(): string {
  return browserLocale();
}

type Args = Record<string, string | number>;

/** The words for `key` in a language, with `args` put in for `{name}`; `n` chooses between `one` and `other`. */
export function tr(language: Lang, key: string, args?: Args): string {
  const found = CATALOG[language][key] ?? CATALOG.zh[key];
  let text: string;
  if (found === undefined) text = key;
  else if (typeof found === "string") text = found;
  else text = (args && Number(args.n) === 1 ? found.one : undefined) ?? found.other;
  if (!args) return text;
  return text.replace(/\{(\w+)\}/g, (all, name: string) => (name in args ? String(args[name]) : all));
}

/** The words for `key` in the language now. */
export function t(key: string, args?: Args): string {
  return tr(lang(), key, args);
}

/** Draws the app again, whole, when the language changes (its words are read as it is drawn). */
export function I18nRoot({ children }: { children: ReactNode }) {
  const language = useLang();
  if (typeof document !== "undefined") document.documentElement.lang = language === "zh" ? "zh-CN" : "en";
  return createElement(Fragment, { key: language }, children);
}
