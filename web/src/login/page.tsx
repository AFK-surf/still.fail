// The sign-in pages drawn (Login.tsx), on the web's host and the admin's: their words, the browser's language.
import { render } from "preact";
import { addWords, I18nRoot, type Words } from "@stillfail/ui/i18n.ts";
import zhLogin from "../../../client/i18n/catalog/zh/web-login.json" with { type: "json" };
import enLogin from "../../../client/i18n/catalog/en/web-login.json" with { type: "json" };
import type { ComponentChildren } from "preact";
import { Callback, SignIn } from "./Login.tsx";

addWords({ zh: zhLogin as Words, en: enLogin as Words });

/** Whether `path` is one of the sign-in pages. */
export const isSignIn = (path: string) => path === "/login" || path === "/auth/callback";

/** `signIn`: what /login draws there (the admin's console's own: admin/signin.tsx). */
export function show(root: HTMLElement, path: string, signIn: ComponentChildren = <SignIn />): void {
  // (in place of the splash index.html paints first)
  root.replaceChildren();
  render(<I18nRoot>{path === "/auth/callback" ? <Callback /> : signIn}</I18nRoot>, root);
}
