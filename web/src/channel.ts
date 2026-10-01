// Which channel the page is on, decided as it loads (one build serves both, so a build tried on the test channel is
// promoted unchanged): the test channel's page (app.youdid.wtf) is marked by ember-web-beta with
// <meta name="stillfail-beta" content="<the stable origin>"> (cloud/src/web.ts); the desktop app's beta build says so
// through its preload. Kept free of React and the core so the core's opener (core/client.ts) can use it too.

/** The test channel's mark on this page, if any. */
export const BETA_META = typeof document === "undefined" ? null : document.querySelector<HTMLMetaElement>('meta[name="stillfail-beta"]');

/** Whether this page is the test channel's web (app.youdid.wtf). */
export const BETA = Boolean(BETA_META) || (typeof location !== "undefined" && location.host === "app.youdid.wtf");

/** The name the product goes by here: on the test channel (its web, or the beta desktop app) its own, youdid.wtf (still.fail's dual). */
export const NAME = BETA || (typeof window !== "undefined" && window.stillfailDesktop?.beta) ? "youdid.wtf" : "still.fail";
