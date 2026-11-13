// The still.fail core's words: the mechanism is the base's (lang.ts, which says its own words), given here the rest of
// client/i18n/catalog and the product's name (client/i18n/brand.ts) as this module is first run: whatever says a word
// of the catalog imports this file, so it is run before that asks. The words the base says are in parts of their own,
// named by more of their keys (core-logic.mesh.json, core-misc.wake.json, …: lang.ts imports them), and in no other.
import zh_android_chat from "../../i18n/catalog/zh/android-chat.json" with { type: "json" };
import zh_android_misc from "../../i18n/catalog/zh/android-misc.json" with { type: "json" };
import zh_android_settings from "../../i18n/catalog/zh/android-settings.json" with { type: "json" };
import zh_cloud from "../../i18n/catalog/zh/cloud.json" with { type: "json" };
import zh_common from "../../i18n/catalog/zh/common.json" with { type: "json" };
import zh_core_logic from "../../i18n/catalog/zh/core-logic.json" with { type: "json" };
import zh_core_misc from "../../i18n/catalog/zh/core-misc.json" with { type: "json" };
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
import en_core_misc from "../../i18n/catalog/en/core-misc.json" with { type: "json" };
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
  zh: { ...zh_android_chat, ...zh_android_misc, ...zh_android_settings, ...zh_cloud, ...zh_common, ...zh_core_logic, ...zh_core_misc, ...zh_core_views, ...zh_desktop, ...zh_station, ...zh_web_main, ...zh_web_mobile, ...zh_web_pages, } as Words,
  en: { ...en_android_chat, ...en_android_misc, ...en_android_settings, ...en_cloud, ...en_common, ...en_core_logic, ...en_core_misc, ...en_core_views, ...en_desktop, ...en_station, ...en_web_main, ...en_web_mobile, ...en_web_pages, } as Words,
});
// (another product's cloud: its name for still.fail's, client/i18n/brand.ts)
saidBy((text) => branded(text, brand.current()));
