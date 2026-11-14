// Where a service sends back a person who signed in to it for their vault (添加 › Slack 账号: the core's
// client/core-ts/src/vault/oauth.ts, which says why it comes back here): the query is handed on to where the sign-in
// began, as its state says (`{n, w, b}` in base64url): the app's own scheme, the app's loopback address, or this page's
// core (`b` "web"), which changes the code for the token and writes it into the vault. With `done` this is the page the
// app's loopback sends the browser on to once it has the query.
import { render } from "preact";
import { useEffect, useState } from "preact/hooks";
import { addWords, I18nRoot, t, type Words } from "@stillfail/ui/i18n.ts";
import zhPages from "../../../client/i18n/catalog/zh/web-pages.json" with { type: "json" };
import enPages from "../../../client/i18n/catalog/en/web-pages.json" with { type: "json" };
import { core } from "../core/react.ts";
import { NAME } from "../channel.ts";
import { accounts, signInHere, takeSignedIn } from "./core.ts";
import * as css from "../login/login.css.ts";

addWords({ zh: zhPages as Words, en: enPages as Words });

type Result = { name: string } | { error: string } | "signedOut";

/** The state's `{n, w, b}` (vault/oauth.ts `stateText`); null when it is not one. */
function stateOf(state: string): { w: string; b: string } | null {
  try {
    const v: unknown = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(state.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0))));
    if (typeof v !== "object" || v === null) return null;
    const { w, b } = v as { w?: unknown; b?: unknown };
    return typeof w === "string" && typeof b === "string" ? { w, b } : null;
  } catch {
    return null;
  }
}

/** Where the query goes on to (vault/oauth.ts `handedTo`, the same rule): null for this page's own. */
function handedTo(back: string, query: string): string | null {
  if (/^http:\/\/127\.0\.0\.1:\d{1,5}\/[\w/.-]*$/.test(back)) return `${back}?${query}`;
  if (back !== "web" && /^[a-z][a-z0-9.+-]*$/.test(back) && !["http", "https", "javascript", "data", "file", "blob", "about"].includes(back)) return `${back}://auth/vault?${query}`;
  return null;
}

function VaultOauth() {
  const query = location.search.replace(/^\?/, "");
  const params = new URLSearchParams(query);
  const said = stateOf(params.get("state") ?? "");
  const to = said ? handedTo(said.b, query) : null;
  const [result, setResult] = useState<Result | null>(null);
  useEffect(() => {
    if (params.has("done") || !said) return;
    if (to !== null) return void location.replace(to);
    if (said.b !== "web") return;
    void takeSignedIn().then(async () => {
      if ((await accounts()).length === 0) return setResult("signedOut");
      core().call("vault.oauthComplete", { workspace: said.w, query }).then((r) => setResult(r as { name: string }), (e: Error) => setResult({ error: e.message }));
    });
  }, []);
  const page = (title: string, lead: string, action?: [string, string]) => (
    <main className={css.page}>
      <h1 className={css.title}>{title}</h1>
      <p className={css.lead}>{lead}</p>
      {action && <div className={css.actions}><a className={css.button} href={action[1]}>{action[0]}</a></div>}
    </main>
  );
  const back: [string, string] = [t("web-pages.cloud.backTo", { name: NAME }), "/"];
  if (params.has("done")) return page(t("web-pages.cloud.vaultOauth.added"), t("web-pages.cloud.vaultOauth.backInApp", { name: NAME }));
  if (!said) return page(t("web-pages.cloud.vaultOauth.failed"), t("web-pages.cloud.vaultOauth.notOurs", { name: NAME }), back);
  if (to !== null) return page(t("web-pages.cloud.vaultOauth.handing", { name: NAME }), "", [t("web-pages.cloud.vaultOauth.openApp", { name: NAME }), to]);
  if (result === "signedOut") return page(t("web-pages.cloud.slackInstalled.signIn", { name: NAME }), t("web-pages.cloud.vaultOauth.signInBody", { name: NAME }), [t("web-pages.cloud.slackInstalled.signIn", { name: NAME }), signInHere()]);
  if (result === null) return page(t("web-pages.cloud.vaultOauth.adding"), "");
  if ("error" in result) return page(t("web-pages.cloud.vaultOauth.failed"), result.error, back);
  return page(t("web-pages.cloud.vaultOauth.added"), t("web-pages.cloud.vaultOauth.addedBody", { item: result.name, name: NAME }), back);
}

export function show(root: HTMLElement): void {
  // (in place of the splash index.html paints first)
  root.replaceChildren();
  render(<I18nRoot><VaultOauth /></I18nRoot>, root);
}
