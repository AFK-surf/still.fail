// The words people read, in their language: the catalog client/i18n reads (client/i18n/src/lib.rs says how), all of it,
// as the Rust station has it. `{name}` takes the value given as `name`; `{"one", "other"}` is chosen by `n` (1: one).
// A key a language lacks is said in Chinese; one neither has is the key.
import zhAndroidChat from "../../../client/i18n/catalog/zh/android-chat.json" with { type: "json" };
import zhAndroidMisc from "../../../client/i18n/catalog/zh/android-misc.json" with { type: "json" };
import zhAndroidSettings from "../../../client/i18n/catalog/zh/android-settings.json" with { type: "json" };
import zhCloud from "../../../client/i18n/catalog/zh/cloud.json" with { type: "json" };
import zhCommon from "../../../client/i18n/catalog/zh/common.json" with { type: "json" };
import zhCoreLogic from "../../../client/i18n/catalog/zh/core-logic.json" with { type: "json" };
import zhCoreMisc from "../../../client/i18n/catalog/zh/core-misc.json" with { type: "json" };
import zhCoreViews from "../../../client/i18n/catalog/zh/core-views.json" with { type: "json" };
import zhDesktop from "../../../client/i18n/catalog/zh/desktop.json" with { type: "json" };
import zhStation from "../../../client/i18n/catalog/zh/station.json" with { type: "json" };
import zhWebMain from "../../../client/i18n/catalog/zh/web-main.json" with { type: "json" };
import zhWebMobile from "../../../client/i18n/catalog/zh/web-mobile.json" with { type: "json" };
import zhWebPages from "../../../client/i18n/catalog/zh/web-pages.json" with { type: "json" };
import enAndroidChat from "../../../client/i18n/catalog/en/android-chat.json" with { type: "json" };
import enAndroidMisc from "../../../client/i18n/catalog/en/android-misc.json" with { type: "json" };
import enAndroidSettings from "../../../client/i18n/catalog/en/android-settings.json" with { type: "json" };
import enCloud from "../../../client/i18n/catalog/en/cloud.json" with { type: "json" };
import enCommon from "../../../client/i18n/catalog/en/common.json" with { type: "json" };
import enCoreLogic from "../../../client/i18n/catalog/en/core-logic.json" with { type: "json" };
import enCoreMisc from "../../../client/i18n/catalog/en/core-misc.json" with { type: "json" };
import enCoreViews from "../../../client/i18n/catalog/en/core-views.json" with { type: "json" };
import enDesktop from "../../../client/i18n/catalog/en/desktop.json" with { type: "json" };
import enStation from "../../../client/i18n/catalog/en/station.json" with { type: "json" };
import enWebMain from "../../../client/i18n/catalog/en/web-main.json" with { type: "json" };
import enWebMobile from "../../../client/i18n/catalog/en/web-mobile.json" with { type: "json" };
import enWebPages from "../../../client/i18n/catalog/en/web-pages.json" with { type: "json" };

export type Lang = "zh" | "en";
type Words = Record<string, string | { one?: string; other: string }>;

const ZH: Words = Object.assign({}, zhAndroidChat, zhAndroidMisc, zhAndroidSettings, zhCloud, zhCommon, zhCoreLogic, zhCoreMisc, zhCoreViews, zhDesktop, zhStation, zhWebMain, zhWebMobile, zhWebPages);
const EN: Words = Object.assign({}, enAndroidChat, enAndroidMisc, enAndroidSettings, enCloud, enCommon, enCoreLogic, enCoreMisc, enCoreViews, enDesktop, enStation, enWebMain, enWebMobile, enWebPages);

/// Chinese for Chinese, English for any other; Chinese when nothing is said.
export function langOf(locale: string | null | undefined): Lang {
  const l = (locale ?? "").trim().toLowerCase();
  return !l || l.startsWith("zh") ? "zh" : "en";
}

let station: Lang = "zh";
/// The station's own language (config.json `language`), for what it says on this machine.
export const setStationLang = (language: string | null | undefined) => (station = langOf(language));
export const stationLang = () => station;

export function tr(lang: Lang, key: string, args: Record<string, unknown> = {}): string {
  const found = (lang === "en" ? EN : ZH)[key] ?? ZH[key];
  let text: string;
  if (typeof found === "string") text = found;
  else if (found) text = ("n" in args && String(args.n).trim() === "1" ? found.one : found.other) ?? found.other ?? key;
  else text = key;
  return fill(text, args);
}

/// `{name}` filled; one not given, and a `{` that opens no name, left as they are.
function fill(text: string, args: Record<string, unknown>): string {
  if (Object.keys(args).length === 0 || !text.includes("{")) return text;
  return text.replace(/\{([A-Za-z0-9_]*)\}/g, (all, name) => (name in args ? String(args[name]) : all));
}
