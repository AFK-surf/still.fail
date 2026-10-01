// The test channel (app.youdid.wtf): the same build as app.still.fail, served by ember-web-beta, which marks each page
// with <meta name="stillfail-beta" content="<the stable origin>"> (cloud/src/web.ts). The core talks to the page's own
// origin, so on that host it calls the API there, which lets in only the accounts the admin turned beta on for and
// answers the others' calls 403 not_beta. Here the page says it is the test channel (a mark at the bottom left, the
// title) and sends an account not let in to the same page on the stable one.
import { useEffect } from "react";
import { useWorkspaces } from "./api.ts";
import * as css from "./beta.css.ts";

const meta = typeof document === "undefined" ? null : document.querySelector<HTMLMetaElement>('meta[name="stillfail-beta"]');

/** Whether this page is the test channel's. */
export const BETA = Boolean(meta) || (typeof location !== "undefined" && location.host === "app.youdid.wtf");

/** Where the stable channel is. */
const STABLE = meta?.content || "https://app.still.fail";

const TITLE = "测试版 · ";

/** On the test channel, every title the page sets starts with 「测试版 · 」. */
export function markBetaTitle(): void {
  if (!BETA) return;
  const mark = () => { if (!document.title.startsWith(TITLE)) document.title = TITLE + document.title; };
  mark();
  new MutationObserver(mark).observe(document.head, { subtree: true, childList: true, characterData: true });
}

/** The test channel's mark, at the bottom left of every page. */
export function BetaMark() {
  return BETA ? <div className={css.mark} aria-hidden="true">测试版</div> : null;
}

/** Signed in on the test channel with no account let in: to the same page on the stable one. */
export function BetaGate() {
  const workspaces = useWorkspaces().value;
  const refused = BETA && Boolean(workspaces?.length) && workspaces!.every((a) => a.error?.code === "not_beta");
  useEffect(() => {
    if (refused) location.replace(`${STABLE}${location.pathname}${location.search}${location.hash}`);
  }, [refused]);
  return null;
}
