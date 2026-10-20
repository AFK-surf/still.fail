// The app's words (@stillfail/ui/i18n.ts reads them): the catalog's parts it says things from, in the core's language
// (prefs `lang`: as chosen, else as the device is); before the core answers, or with a core from before languages, the
// browser's.
import { addWords, browserLocale, langOf, setLang, type Lang, type Words } from "@stillfail/ui/i18n.ts";
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

export { I18nRoot, lang, langOf, t, tr, useLang, type Lang } from "@stillfail/ui/i18n.ts";

addWords({
  zh: { ...zhCommon, ...zhWebPages, ...zhWebMobile, ...zhWebMain, ...zhDesktop } as Words,
  en: { ...enCommon, ...enWebPages, ...enWebMobile, ...enWebMain, ...enDesktop } as Words,
});

function langFrom(p: Prefs): Lang {
  if (p.lang === "zh" || p.lang === "en") return p.lang;
  return langOf(p.language ?? browserLocale());
}

setLang({ now: () => langFrom(prefs()), use: () => usePrefs(langFrom) });

/** The browser's language, for the core to follow when none is chosen (`client.device`'s `locale`). */
export function deviceLocale(): string {
  return browserLocale();
}
