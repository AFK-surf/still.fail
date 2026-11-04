// The web's own React pages that the app (mbui's, index.html) has none of yet (cloud/src/web.ts WEB_PAGES): a sign-in
// coming back, Slack sending back an app a station made, and a station's web service on a page of its own. (The
// admin's console is an app of its own, src/admin/.) Everything goes through the client core: accounts, still.fail
// cloud and the links to stations live there, not on the page.
import { GoKeeper } from "../go.ts";
import { Tooltip } from "radix-ui";
import { useEffect, useMemo, useRef, useState } from "react";
import { ServicePage } from "../Preview.tsx";
import { BrowserRouter, Route, Routes, useParams } from "react-router";
import { WebUpdate } from "../WebUpdate.tsx";
import { ToastProvider } from "@stillfail/ui/toast.tsx";
import { Splash, useNarrow } from "../ui.tsx";
import { useAccounts, useSignIn } from "./accounts.ts";
import { Callback, SignInPage } from "./gate.tsx";
import { PageViews } from "../telemetry.ts";
import { stationApi, useStationCall } from "../api.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";

export function CloudApp() {
  const narrow = useNarrow();
  return (
    <ToastProvider>
      {narrow && <WebUpdate floating />}
      <Tooltip.Provider delayDuration={400}>
        <BrowserRouter>
          <GoKeeper />
          <PageViews />
          <Routes>
            <Route path="/auth/callback" element={<Callback />} />
            <Route path="/slack/installed" element={<SlackInstalled />} />
            <Route path="*" element={<Home />} />
          </Routes>
        </BrowserRouter>
      </Tooltip.Provider>
    </ToastProvider>
  );
}

/**
 * Where Slack sends someone who installed an app a station made (its OAuth redirect): the state names the station, and
 * the code goes to it, which takes the bot token and keeps it with the app until a connect takes it.
 */
function SlackInstalled() {
  const query = useMemo(() => new URLSearchParams(location.search), []);
  const state = query.get("state") ?? "";
  const code = query.get("code") ?? "";
  const list = useAccounts();
  const call = useStationCall(state.split("~")[0] ?? "");
  const api = useMemo(() => stationApi(call), [call]);
  const [result, setResult] = useState<{ team: string | null } | { error: string } | null>(null);
  const sent = useRef(false);
  useEffect(() => {
    if (sent.current || !code || !state || !list?.length) return;
    sent.current = true;
    api.slackInstalled(code, state).then(setResult, (error: Error) => setResult({ error: error.message }));
  }, [api, code, state, list]);
  const back = <a className={`${controlsCss.btn} btn-secondary`} href="/">{t("web-pages.cloud.backTo", { name: NAME })}</a>;
  if (query.get("error") || !code) return <div className={shellCss.gate}><h1>{t("web-pages.cloud.slackInstalled.notInstalled")}</h1><p>{t("web-pages.cloud.slackInstalled.notInstalledBody", { name: NAME })}</p>{back}</div>;
  if (list && list.length === 0) return <div className={shellCss.gate}><h1>{t("web-pages.cloud.slackInstalled.signIn", { name: NAME })}</h1><p>{t("web-pages.cloud.slackInstalled.signInBody", { name: NAME })}</p>{back}</div>;
  if (!result) return <Splash label={t("web-pages.cloud.slackInstalled.handing")} />;
  if ("error" in result) return <div className={shellCss.gate}><h1>{t("web-pages.cloud.slackInstalled.failed")}</h1><p>{result.error}</p>{back}</div>;
  return <div className={shellCss.gate}><h1>{t("web-pages.cloud.slackInstalled.done", { team: result.team ?? t("web-pages.cloud.slackInstalled.workspace") })}</h1><p>{t("web-pages.cloud.slackInstalled.doneBody", { name: NAME })}</p></div>;
}

function Home() {
  const list = useAccounts();
  if (!list) return <Splash />;
  if (list.length > 0) return <SignedIn />;
  return <StartSignIn />;
}

/** The cloud's sign-in page already offers all ways to sign in. Go there directly. */
function StartSignIn() {
  const signIn = useSignIn();
  const started = useRef(false);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    if (started.current) return;
    started.current = true;
    void signIn.signIn().then((going) => { if (!going) setFailed(true); });
  }, [signIn.signIn]);
  if (!failed) return <Splash />;
  // If starting sign-in failed, leave a way to retry.
  return <SignInPage />;
}

/** Signed in: a station's web service on a page of its own; any other page is the app's (cloud/src/web.ts). */
function SignedIn() {
  return (
    <Routes>
      <Route path="/w/:ws/s/:station/services/:service" element={<CloudServicePage />} />
      <Route path="*" element={<ToApp />} />
    </Routes>
  );
}

/** A page the app has: loaded as its own. */
function ToApp() {
  useEffect(() => location.replace("/"), []);
  return <Splash />;
}

/** A web service on a page of its own (opened from its preview): the whole window. */
function CloudServicePage() {
  const { ws = "", station = "", service = "" } = useParams();
  return <ServicePage station={`${ws}/${station}`} service={service} />;
}
