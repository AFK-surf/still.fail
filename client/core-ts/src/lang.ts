// The words people read, in their language: `t("key", { name })`. The base says its own words by it (the mesh's, an
// error's, a moment's): those are the catalog files imported here and no others (scripts/base.ts `WORDS` holds this
// file to them, and every key a base file says to being in them), so the base says them with nothing else loaded. A
// program built on the base gives its own catalog (`words`) as its module is first run, so before anything of it asks
// for a word (the still.fail core's: i18n.ts, the rest of client/i18n/catalog), and may say how every word is said
// (`saidBy`: the still.fail core's product's name).
// A key a language lacks is said in Chinese; one neither has is shown as the key. `{name}` takes the value given as
// `name`; words that change with a number (`{"one", "other"}`) are chosen by `n`.
import zh_core_logic_format from "../../i18n/catalog/zh/core-logic.format.json" with { type: "json" };
import zh_core_logic_mesh from "../../i18n/catalog/zh/core-logic.mesh.json" with { type: "json" };
import zh_core_misc_call from "../../i18n/catalog/zh/core-misc.call.json" with { type: "json" };
import zh_core_misc_error from "../../i18n/catalog/zh/core-misc.error.json" with { type: "json" };
import zh_core_misc_host from "../../i18n/catalog/zh/core-misc.host.json" with { type: "json" };
import zh_core_misc_secure from "../../i18n/catalog/zh/core-misc.secure.json" with { type: "json" };
import zh_core_misc_wake from "../../i18n/catalog/zh/core-misc.wake.json" with { type: "json" };
import en_core_logic_format from "../../i18n/catalog/en/core-logic.format.json" with { type: "json" };
import en_core_logic_mesh from "../../i18n/catalog/en/core-logic.mesh.json" with { type: "json" };
import en_core_misc_call from "../../i18n/catalog/en/core-misc.call.json" with { type: "json" };
import en_core_misc_error from "../../i18n/catalog/en/core-misc.error.json" with { type: "json" };
import en_core_misc_host from "../../i18n/catalog/en/core-misc.host.json" with { type: "json" };
import en_core_misc_secure from "../../i18n/catalog/en/core-misc.secure.json" with { type: "json" };
import en_core_misc_wake from "../../i18n/catalog/en/core-misc.wake.json" with { type: "json" };

export type Lang = "zh" | "en";
export type Words = Record<string, string | { one?: string; other?: string }>;

const CATALOG: Record<Lang, Words> = {
  zh: { ...zh_core_logic_format, ...zh_core_logic_mesh, ...zh_core_misc_call, ...zh_core_misc_error, ...zh_core_misc_host, ...zh_core_misc_secure, ...zh_core_misc_wake } as Words,
  en: { ...en_core_logic_format, ...en_core_logic_mesh, ...en_core_misc_call, ...en_core_misc_error, ...en_core_misc_host, ...en_core_misc_secure, ...en_core_misc_wake } as Words,
};

/// More words, each language's: a program's own catalog, given as its module is first run. A key is in one catalog
/// alone (the still.fail core's: test/catalog.test.ts).
export function words(more: Record<Lang, Words>): void {
  Object.assign(CATALOG.zh, more.zh);
  Object.assign(CATALOG.en, more.en);
}

/// How every word is said, before its `{names}` are filled; none given: as it is written.
let SAID: (text: string) => string = (text) => text;

/// The program's way of saying every word (the still.fail core's: its product's name where the catalog says
/// still.fail's, i18n.ts).
export function saidBy(by: (text: string) => string): void {
  SAID = by;
}

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
  return fill(SAID(text), args);
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
