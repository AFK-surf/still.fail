// Where Slack sends someone who installed an app a station made (its OAuth redirect): the state names the station, and
// the code goes to it (`slack.installed`), which takes the bot token and keeps it with the app until a connect takes it.
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

type Result = { team: string | null } | { error: string } | "signedOut";

function SlackInstalled() {
  const query = new URLSearchParams(location.search);
  const state = query.get("state") ?? "";
  const code = query.get("code") ?? "";
  const [result, setResult] = useState<Result | null>(null);
  useEffect(() => {
    if (query.get("error") || !code || !state) return;
    void takeSignedIn().then(async () => {
      if ((await accounts()).length === 0) return setResult("signedOut");
      const station = state.split("~")[0] ?? "";
      core().call("slack.installed", { code, state, station }).then((r) => setResult(r as { team: string | null }), (e: Error) => setResult({ error: e.message }));
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
  if (query.get("error") || !code) return page(t("web-pages.cloud.slackInstalled.notInstalled"), t("web-pages.cloud.slackInstalled.notInstalledBody", { name: NAME }), back);
  if (result === "signedOut") return page(t("web-pages.cloud.slackInstalled.signIn", { name: NAME }), t("web-pages.cloud.slackInstalled.signInBody", { name: NAME }), [t("web-pages.cloud.slackInstalled.signIn", { name: NAME }), signInHere()]);
  if (result === null) return page(t("web-pages.cloud.slackInstalled.handing"), "");
  if ("error" in result) return page(t("web-pages.cloud.slackInstalled.failed"), result.error, back);
  return page(t("web-pages.cloud.slackInstalled.done", { team: result.team ?? t("web-pages.cloud.slackInstalled.workspace") }), t("web-pages.cloud.slackInstalled.doneBody", { name: NAME }));
}

export function show(root: HTMLElement): void {
  // (in place of the splash index.html paints first)
  root.replaceChildren();
  render(<I18nRoot><SlackInstalled /></I18nRoot>, root);
}
