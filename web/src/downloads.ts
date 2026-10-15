// The apps to download from the web: this channel's (the test channel's web the beta apps, named youdid.wtf, beside the
// released ones), from the cloud the page is served by (the test channel's page says where the stable one is: channel.ts).
import { BETA, BETA_META } from "./channel.ts";

/**
 * Whether the apps are offered here: in a browser, not in the desktop app (which has itself already), nor in the site's
 * demo (the site has its own 下载 over it: withoutDownloads).
 */
let offered = typeof window !== "undefined" && !window.stillfailDesktop;
export const downloadsOffered = () => offered;
export function withoutDownloads(): void {
  offered = false;
}

const origin = () => BETA_META?.content || location.origin;
/** The latest build of an app on this channel (cloud's /releases/latest/<app>). */
export const download = (app: "mac" | "win" | "android") => `${origin()}/releases/latest/${app}${BETA ? "-beta" : ""}`;
/** The code to scan for this channel's Android app (web/public). */
export const androidQr = () => `${import.meta.env.BASE_URL}${BETA ? "android-beta-qr" : "android-qr"}.svg`;
/** Whether the page is on an Android phone, where the app itself is downloaded. */
export const onAndroid = () => typeof navigator !== "undefined" && /Android/i.test(navigator.userAgent);
