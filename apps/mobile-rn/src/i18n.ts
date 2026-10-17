// The app's words (@stillfail/ui/i18n.ts reads them), in the core's language (prefs `lang`, else the device's): the
// Android app's parts of the catalog, as this app says what it says, and the web's for the logic taken from it
// (web/src/i18n.ts, which this module stands in for).
import { getLocales } from "expo-localization";
import { addWords, langOf, setLang, type Lang, type Words } from "@stillfail/ui/i18n.ts";
import { prefs, usePrefs, type Prefs } from "../../../web/src/prefs.ts";

export { I18nRoot, lang, langOf, t, tr, useLang, type Lang } from "@stillfail/ui/i18n.ts";

const PARTS = ["common", "android-chat", "android-misc", "android-settings", "web-pages", "web-mobile", "web-main"] as const;
const catalog: Record<Lang, Record<(typeof PARTS)[number], Words>> = {
  zh: {
    common: require("../../../client/i18n/catalog/zh/common.json"),
    "android-chat": require("../../../client/i18n/catalog/zh/android-chat.json"),
    "android-misc": require("../../../client/i18n/catalog/zh/android-misc.json"),
    "android-settings": require("../../../client/i18n/catalog/zh/android-settings.json"),
    "web-pages": require("../../../client/i18n/catalog/zh/web-pages.json"),
    "web-mobile": require("../../../client/i18n/catalog/zh/web-mobile.json"),
    "web-main": require("../../../client/i18n/catalog/zh/web-main.json"),
  },
  en: {
    common: require("../../../client/i18n/catalog/en/common.json"),
    "android-chat": require("../../../client/i18n/catalog/en/android-chat.json"),
    "android-misc": require("../../../client/i18n/catalog/en/android-misc.json"),
    "android-settings": require("../../../client/i18n/catalog/en/android-settings.json"),
    "web-pages": require("../../../client/i18n/catalog/en/web-pages.json"),
    "web-mobile": require("../../../client/i18n/catalog/en/web-mobile.json"),
    "web-main": require("../../../client/i18n/catalog/en/web-main.json"),
  },
};
addWords({
  zh: Object.assign({}, ...PARTS.map((p) => catalog.zh[p])) as Words,
  en: Object.assign({}, ...PARTS.map((p) => catalog.en[p])) as Words,
});

/** The device's language, for the core to follow when none is chosen (`client.device`'s `locale`). */
export function deviceLocale(): string {
  return getLocales()[0]?.languageTag ?? "";
}

function langFrom(p: Prefs): Lang {
  if (p.lang === "zh" || p.lang === "en") return p.lang;
  return langOf(p.language ?? deviceLocale());
}

setLang({ now: () => langFrom(prefs()), use: () => usePrefs(langFrom) });
