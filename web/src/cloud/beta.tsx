// The test channel (app.youdid.wtf): the same build as app.still.fail, served by ember-web-beta, which marks each page
// with <meta name="stillfail-beta" content="<the stable origin>"> (cloud/src/web.ts). The core talks to the page's own
// origin, so on that host it calls the API there, which lets in only the accounts the admin turned beta on for and
// answers the others' calls 403 not_beta. Here the page goes by the test channel's name (youdid.wtf, which is all it
// takes to tell the two apart) and sends an account not let in to the same page on the stable one.
import { useEffect } from "react";
import { useWorkspaces } from "./api.ts";
import { BETA, BETA_META, NAME } from "../channel.ts";

export { BETA, NAME };

/** Where the stable channel is. */
const STABLE = BETA_META?.content || "https://app.still.fail";

/** The title the page was served with (index.html's still.fail) in the page's own name, where that is another. */
export function nameTitle(): void {
  if (NAME !== "still.fail") document.title = document.title.replaceAll("still.fail", NAME);
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
