// The words people read, in their language: the catalog the core, the station and the apps read
// (client/i18n/catalog/<lang>/*.json; client/i18n/src/lib.rs says how), cloud's part and the shared one. Which language
// is the request's: a `lang` it names, else its Accept-Language; Chinese when it says neither (as before there were
// languages).
import zhCommon from "../../client/i18n/catalog/zh/common.json" with { type: "json" };
import enCommon from "../../client/i18n/catalog/en/common.json" with { type: "json" };
import zhCloud from "../../client/i18n/catalog/zh/cloud.json" with { type: "json" };
import enCloud from "../../client/i18n/catalog/en/cloud.json" with { type: "json" };

export type Lang = "zh" | "en";
type Words = Record<string, string | { one?: string; other: string }>;

const CATALOG: Record<Lang, Words> = {
  zh: { ...zhCommon, ...zhCloud } as Words,
  en: { ...enCommon, ...enCloud } as Words,
};

/** Chinese for Chinese, English for any other; Chinese when nothing is said (as the core decides, i18n/src/lib.rs). */
export function langOf(locale: string | undefined | null): Lang {
  const l = (locale ?? "").trim().toLowerCase();
  return !l || l.startsWith("zh") ? "zh" : "en";
}

/** The language a request is answered in: its `?lang=`, else its Accept-Language (the first named; `*` names none). */
export function requestLang(request: Request): Lang {
  const asked = new URL(request.url).searchParams.get("lang");
  const accepted = request.headers.get("accept-language")?.split(/[,;]/)[0]?.trim();
  return langOf(asked || (accepted === "*" ? "" : accepted));
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

/**
 * JavaScript for the words for `key` in the language of the browser it runs in (`navigator.language`, Chinese when it
 * says none), `{name}`s put in from the JavaScript expressions in `args`: for scripts served as they are, to anyone.
 */
export function browserWords(key: string, args: Record<string, string> = {}): string {
  const said = (language: Lang) =>
    tr(language, key)
      .split(/\{(\w+)\}/)
      .map((part, i) => (i % 2 ? (part in args ? `(${args[part]})` : JSON.stringify(`{${part}}`)) : JSON.stringify(part)))
      .filter((part) => part !== '""')
      .join(" + ") || '""';
  return `(/^zh/i.test(navigator.language || "zh") ? ${said("zh")} : ${said("en")})`;
}
