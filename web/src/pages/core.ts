// The pages on the core (pages/slack.tsx, pages/service.tsx, the admin's console): the core's words and the accounts
// signed in on the sign-in page (login/signin.ts), taken into the core before anything asks it who is signed in.
import { addWords, type Words } from "@stillfail/ui/i18n.ts";
import zhCommon from "../../../client/i18n/catalog/zh/common.json" with { type: "json" };
import enCommon from "../../../client/i18n/catalog/en/common.json" with { type: "json" };
import zhMain from "../../../client/i18n/catalog/zh/web-main.json" with { type: "json" };
import enMain from "../../../client/i18n/catalog/en/web-main.json" with { type: "json" };
import { core } from "../core/react.ts";
import { putBack, take } from "../login/signin.ts";
import "../i18n.ts";

addWords({ zh: { ...zhCommon, ...zhMain } as Words, en: { ...enCommon, ...enMain } as Words });

/** The accounts signed in on the sign-in page since, taken into the core (put back for the next page if it fails). */
export async function takeSignedIn(): Promise<void> {
  const accounts = take();
  if (accounts.length === 0) return;
  await core().call("migrate", { accounts }).catch(() => putBack(accounts));
}

/** The accounts signed in, once the core says. */
export function accounts(): Promise<{ sub: string; email: string }[]> {
  return new Promise((done) => {
    const stop = core().subscribe({ topic: "accounts" }, (value) => { queueMicrotask(() => stop()); done(Array.isArray(value) ? value : []); }, () => { queueMicrotask(() => stop()); done([]); });
  });
}

/** Where to sign in, coming back to this page. */
export const signInHere = () => `/login?return_to=${encodeURIComponent(location.pathname + location.search)}`;
