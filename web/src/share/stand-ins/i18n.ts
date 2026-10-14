// The share page's words (web/vite.share.config.ts puts this in place of web/src/i18n.ts): the catalog's parts it says
// things from — its own, and the chat's that Prose.tsx and Viz.tsx say — in the browser's language. No core, no
// preferences: a visitor's browser is all it follows. The same reading as i18n.ts's.
import { createElement, Fragment, type ReactNode } from "react";
import zhCommon from "../../../../client/i18n/catalog/zh/common.json" with { type: "json" };
import enCommon from "../../../../client/i18n/catalog/en/common.json" with { type: "json" };
import zhWebMain from "../../../../client/i18n/catalog/zh/web-main.json" with { type: "json" };
import enWebMain from "../../../../client/i18n/catalog/en/web-main.json" with { type: "json" };
import zhWebShare from "../../../../client/i18n/catalog/zh/web-share.json" with { type: "json" };
import enWebShare from "../../../../client/i18n/catalog/en/web-share.json" with { type: "json" };

export type Lang = "zh" | "en";
type Words = Record<string, string | { one?: string; other: string }>;

const CATALOG: Record<Lang, Words> = {
  zh: { ...zhCommon, ...zhWebMain, ...zhWebShare } as Words,
  en: { ...enCommon, ...enWebMain, ...enWebShare } as Words,
};

/** Chinese for Chinese, English for any other; Chinese when nothing is said. */
export function langOf(locale: string | undefined | null): Lang {
  const l = (locale ?? "").trim().toLowerCase();
  return !l || l.startsWith("zh") ? "zh" : "en";
}

export function lang(): Lang {
  return langOf(typeof navigator === "undefined" ? "" : navigator.language);
}

export const useLang = lang;

type Args = Record<string, string | number>;

export function tr(language: Lang, key: string, args?: Args): string {
  const found = CATALOG[language][key] ?? CATALOG.zh[key];
  let text: string;
  if (found === undefined) text = key;
  else if (typeof found === "string") text = found;
  else text = (args && Number(args.n) === 1 ? found.one : undefined) ?? found.other;
  if (!args) return text;
  return text.replace(/\{(\w+)\}/g, (all, name: string) => (name in args ? String(args[name]) : all));
}

export function t(key: string, args?: Args): string {
  return tr(lang(), key, args);
}

/** The page in its language: `lang` on the document, for the fonts and line breaking. */
export function I18nRoot({ children }: { children: ReactNode }) {
  const tag = lang() === "zh" ? "zh-CN" : "en";
  if (typeof document !== "undefined" && document.documentElement.lang !== tag) document.documentElement.lang = tag;
  return createElement(Fragment, null, children);
}
