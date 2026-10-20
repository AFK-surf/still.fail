// The share page's words (web/vite.share.config.ts puts this in place of web/src/i18n.ts): the catalog's parts it says
// things from — its own, and the chat's that Prose.tsx and Viz.tsx say — in the browser's language (@stillfail/ui's
// own). No core, no preferences: a visitor's browser is all it follows.
import { addWords, type Words } from "@stillfail/ui/i18n.ts";
import zhCommon from "../../../../client/i18n/catalog/zh/common.json" with { type: "json" };
import enCommon from "../../../../client/i18n/catalog/en/common.json" with { type: "json" };
import zhWebMain from "../../../../client/i18n/catalog/zh/web-main.json" with { type: "json" };
import enWebMain from "../../../../client/i18n/catalog/en/web-main.json" with { type: "json" };
import zhWebShare from "../../../../client/i18n/catalog/zh/web-share.json" with { type: "json" };
import enWebShare from "../../../../client/i18n/catalog/en/web-share.json" with { type: "json" };

export { I18nRoot, lang, langOf, t, tr, useLang, type Lang } from "@stillfail/ui/i18n.ts";

addWords({
  zh: { ...zhCommon, ...zhWebMain, ...zhWebShare } as Words,
  en: { ...enCommon, ...enWebMain, ...enWebShare } as Words,
});
