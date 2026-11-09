// The words of the pages on the core (@stillfail/ui/i18n.ts reads them), in the core's language (prefs `lang`: as
// chosen, else as the device is); before the core answers, or with a core from before languages, the browser's. Each
// page adds the catalog's parts it says things from (`addWords`).
import { browserLocale, langOf, setLang, type Lang } from "@stillfail/ui/i18n.ts";
import { prefs, usePrefs, type Prefs } from "./prefs.ts";

export { I18nRoot, lang, langOf, t, tr, useLang, type Lang } from "@stillfail/ui/i18n.ts";

function langFrom(p: Prefs): Lang {
  if (p.lang === "zh" || p.lang === "en") return p.lang;
  return langOf(p.language ?? browserLocale());
}

setLang({ now: () => langFrom(prefs()), use: () => usePrefs(langFrom) });
