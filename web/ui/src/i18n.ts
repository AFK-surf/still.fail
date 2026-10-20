// The words people read, in their language: the catalog the core and the Android app read too
// (client/i18n/catalog/<lang>/*.json; client/i18n/src/lib.rs says how), as much of it as the page that draws gives
// (`addWords`), in the language it says (`setLang`). The browser's until then: the share page follows nothing else; the
// app follows its preferences (web/src/i18n.ts). `t` reads it as it is now: the page's root is drawn again, whole, when it
// changes (I18nRoot).
import { createElement, Fragment, type ReactNode } from "react";

export type Lang = "zh" | "en";
export type Words = Record<string, string | { one?: string; other: string }>;

const CATALOG: Record<Lang, Words> = { zh: {}, en: {} };

/** Words to say things with, each language's, added to those already given. */
export function addWords(words: Record<Lang, Words>): void {
  Object.assign(CATALOG.zh, words.zh);
  Object.assign(CATALOG.en, words.en);
}

/** Chinese for Chinese, English for any other; Chinese when nothing is said (as the core decides, i18n/src/lib.rs). */
export function langOf(locale: string | undefined | null): Lang {
  const l = (locale ?? "").trim().toLowerCase();
  return !l || l.startsWith("zh") ? "zh" : "en";
}

/** The browser's language. */
export function browserLocale(): string {
  return typeof navigator === "undefined" ? "" : navigator.language ?? "";
}

const browser = () => langOf(browserLocale());
let source: { now(): Lang; use(): Lang } = { now: browser, use: browser };

/** Where the language comes from: `now` reads it, `use` (a hook) reads it and redraws when it changes. */
export function setLang(from: { now(): Lang; use(): Lang }): void {
  source = from;
}

/** The language things are said in now. */
export function lang(): Lang {
  return source.now();
}

/** The language, redrawn when it changes. */
export function useLang(): Lang {
  return source.use();
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

/** Draws the page again, whole, when the language changes (its words are read as it is drawn). */
export function I18nRoot({ children }: { children: ReactNode }) {
  const language = useLang();
  // Writing `lang` again, even the same, has every element styled anew (`:lang`): only when it differs.
  const tag = language === "zh" ? "zh-CN" : "en";
  if (typeof document !== "undefined" && document.documentElement.lang !== tag) document.documentElement.lang = tag;
  return createElement(Fragment, { key: language }, children);
}
