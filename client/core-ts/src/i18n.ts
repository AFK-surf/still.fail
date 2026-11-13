// The still.fail core's words: the mechanism is the base's (lang.ts, which says words of its own that name no program:
// lang.zh.json, lang.en.json), given here the whole of client/i18n/catalog and the product's name
// (client/i18n/brand.ts) as this module is first run. The catalog writes every key the base says as still.fail says
// it, in parts of their own named by more of their keys (core-logic.mesh.json, core-misc.wake.json, …), so given here
// they take the base's place: nothing of still.fail's says the base's own (test/base-words.test.ts holds each key to
// the catalog's text). Whatever says a word of the catalog imports this file, so it is run before that asks; and so
// does whatever loads a base file that says a word, itself or through what it imports (scripts/base.ts refuses a file
// of the repository that does not, and any other file outside the base that imports lang.ts itself).
import zh_android_chat from "../../i18n/catalog/zh/android-chat.json" with { type: "json" };
import zh_android_misc from "../../i18n/catalog/zh/android-misc.json" with { type: "json" };
import zh_android_settings from "../../i18n/catalog/zh/android-settings.json" with { type: "json" };
import zh_cloud from "../../i18n/catalog/zh/cloud.json" with { type: "json" };
import zh_common from "../../i18n/catalog/zh/common.json" with { type: "json" };
import zh_core_logic from "../../i18n/catalog/zh/core-logic.json" with { type: "json" };
import zh_core_logic_format from "../../i18n/catalog/zh/core-logic.format.json" with { type: "json" };
import zh_core_logic_mesh from "../../i18n/catalog/zh/core-logic.mesh.json" with { type: "json" };
import zh_core_misc from "../../i18n/catalog/zh/core-misc.json" with { type: "json" };
import zh_core_misc_call from "../../i18n/catalog/zh/core-misc.call.json" with { type: "json" };
import zh_core_misc_error from "../../i18n/catalog/zh/core-misc.error.json" with { type: "json" };
import zh_core_misc_host from "../../i18n/catalog/zh/core-misc.host.json" with { type: "json" };
import zh_core_misc_secure from "../../i18n/catalog/zh/core-misc.secure.json" with { type: "json" };
import zh_core_misc_wake from "../../i18n/catalog/zh/core-misc.wake.json" with { type: "json" };
import zh_core_views from "../../i18n/catalog/zh/core-views.json" with { type: "json" };
import zh_desktop from "../../i18n/catalog/zh/desktop.json" with { type: "json" };
import zh_station from "../../i18n/catalog/zh/station.json" with { type: "json" };
import zh_web_main from "../../i18n/catalog/zh/web-main.json" with { type: "json" };
import zh_web_mobile from "../../i18n/catalog/zh/web-mobile.json" with { type: "json" };
import zh_web_pages from "../../i18n/catalog/zh/web-pages.json" with { type: "json" };
import en_android_chat from "../../i18n/catalog/en/android-chat.json" with { type: "json" };
import en_android_misc from "../../i18n/catalog/en/android-misc.json" with { type: "json" };
import en_android_settings from "../../i18n/catalog/en/android-settings.json" with { type: "json" };
import en_cloud from "../../i18n/catalog/en/cloud.json" with { type: "json" };
import en_common from "../../i18n/catalog/en/common.json" with { type: "json" };
import en_core_logic from "../../i18n/catalog/en/core-logic.json" with { type: "json" };
import en_core_logic_format from "../../i18n/catalog/en/core-logic.format.json" with { type: "json" };
import en_core_logic_mesh from "../../i18n/catalog/en/core-logic.mesh.json" with { type: "json" };
import en_core_misc from "../../i18n/catalog/en/core-misc.json" with { type: "json" };
import en_core_misc_call from "../../i18n/catalog/en/core-misc.call.json" with { type: "json" };
import en_core_misc_error from "../../i18n/catalog/en/core-misc.error.json" with { type: "json" };
import en_core_misc_host from "../../i18n/catalog/en/core-misc.host.json" with { type: "json" };
import en_core_misc_secure from "../../i18n/catalog/en/core-misc.secure.json" with { type: "json" };
import en_core_misc_wake from "../../i18n/catalog/en/core-misc.wake.json" with { type: "json" };
import en_core_views from "../../i18n/catalog/en/core-views.json" with { type: "json" };
import en_desktop from "../../i18n/catalog/en/desktop.json" with { type: "json" };
import en_station from "../../i18n/catalog/en/station.json" with { type: "json" };
import en_web_main from "../../i18n/catalog/en/web-main.json" with { type: "json" };
import en_web_mobile from "../../i18n/catalog/en/web-mobile.json" with { type: "json" };
import en_web_pages from "../../i18n/catalog/en/web-pages.json" with { type: "json" };
import { branded } from "../../i18n/brand.ts";
import * as brand from "./brand.ts";
import { saidBy, words, type Words } from "./lang.ts";

export { current, follows, fromLocale, has, holdLanguage, setCurrent, t, tr, type Args, type Lang } from "./lang.ts";

words({
  zh: { ...zh_android_chat, ...zh_android_misc, ...zh_android_settings, ...zh_cloud, ...zh_common, ...zh_core_logic, ...zh_core_logic_format, ...zh_core_logic_mesh, ...zh_core_misc, ...zh_core_misc_call, ...zh_core_misc_error, ...zh_core_misc_host, ...zh_core_misc_secure, ...zh_core_misc_wake, ...zh_core_views, ...zh_desktop, ...zh_station, ...zh_web_main, ...zh_web_mobile, ...zh_web_pages, } as Words,
  en: { ...en_android_chat, ...en_android_misc, ...en_android_settings, ...en_cloud, ...en_common, ...en_core_logic, ...en_core_logic_format, ...en_core_logic_mesh, ...en_core_misc, ...en_core_misc_call, ...en_core_misc_error, ...en_core_misc_host, ...en_core_misc_secure, ...en_core_misc_wake, ...en_core_views, ...en_desktop, ...en_station, ...en_web_main, ...en_web_mobile, ...en_web_pages, } as Words,
});
// (another product's cloud: its name for still.fail's, client/i18n/brand.ts)
saidBy((text) => branded(text, brand.current()));
