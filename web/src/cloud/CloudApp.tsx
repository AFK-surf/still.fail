// still.fail cloud's pages: sign-in (several Google accounts at once), the
// workspaces those accounts belong to, their members, invitations and
// stations. (The admin's console is an app of its own, src/admin/.) Everything goes through the
// client core: accounts, still.fail cloud and the links to stations live there,
// not on the page.
import { Tooltip } from "radix-ui";
import { useEffect, useMemo, useRef, useState } from "react";
import { ServicePage } from "../Preview.tsx";
import { BrowserRouter, Navigate, Route, Routes, useLocation, useNavigate, useParams } from "react-router";
import { WebUpdate } from "../WebUpdate.tsx";
import { ToastProvider } from "../toast.tsx";
import { Button, Select, Splash, useNarrow } from "../ui.tsx";
import { StatusLine } from "../Status.tsx";
import { useAccounts, useSignIn, useSignOut } from "./accounts.ts";
import { Callback, SignInPage } from "./gate.tsx";
import { BetaGate } from "./beta.tsx";
import { WorkspaceShell } from "./workspace.tsx";
import { ROLE_LABEL } from "./settings.tsx";
import { MobileWorkspace } from "../mobile/index.tsx";
import { MobileSignIn } from "../mobile/SignIn.tsx";
import { cloud, errorText, inviteCode, needsInviteCode, useAction, useWorkspaces } from "./api.ts";
import { Illustration } from "../brand.tsx";
import { PageViews, track } from "../telemetry.ts";
import { useNotices } from "../notify.ts";
import { useDoingFailed } from "../doing.ts";
import { prefs, setPrefs, usePrefs } from "../prefs.ts";
import { stationApi, useStationCall } from "../api.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./CloudApp.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as additionsCss from "../styles/additions.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
export function CloudApp() {
  const narrow = useNarrow();
  return (
    <ToastProvider>
      {narrow && <WebUpdate floating />}
      <Tooltip.Provider delayDuration={400}>
        <BrowserRouter>
          <PageViews />
          <Routes>
            <Route path="/auth/callback" element={<Callback />} />
            <Route path="/invite" element={<Invite />} />
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
  const narrow = useNarrow();
  const navigate = useNavigate();
  // In the desktop app: an item's link opened from outside (stillfail://o/… or ember://o/…) comes here, and the page goes there.
  useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      if (event.origin === location.origin && typeof event.data?.stillfailNavigate === "string") navigate(event.data.stillfailNavigate);
    };
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, [navigate]);
  if (!list) return <Splash />;
  if (list.length > 0) return <SignedIn />;
  if (narrow) return <MobileSignIn />;
  return <SignInPage lead={inviteCode() ? t("web-pages.cloud.signInWithCode", { name: NAME }) : undefined} />;
}

/** Signed in: the workspaces, and the notices of their chats (notify.ts). */
function SignedIn() {
  useNotices();
  return (
    <>
      <BetaGate />
      <Routes>
        <Route path="/" element={<Landing />} />
        <Route path="/o/:ws/:station/:session" element={<OpenItem />} />
        <Route path="/w/:ws/s/:station/services/:service" element={<CloudServicePage />} />
        <Route path="/w/:ws/*" element={<WorkspaceRoute />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </>
  );
}

/**
 * Straight into a workspace: the one last open on this device (WorkspaceRoute
 * keeps it), else the first. An account in none is shown its invitations, or
 * told it is in none; a workspace of its own is made only when it asks for one
 * (with the invite code it came with, or after asking for it).
 */
function Landing() {
  // Come from something going away, as the page that let it go says (its `state`: settings.tsx, mobile/WorkspacePage.tsx):
  // a workspace left or deleted, or an account signed out. The core lists it until that is done; meanwhile it is not
  // opened again, unless still.fail cloud said no to it (the last owner leaving, say).
  const going = useLocation().state as { left?: string; signingOut?: string } | null;
  const refused = useDoingFailed(["workspace.removeMember", "workspace.delete"], { workspace: going?.left }) !== undefined;
  const left = refused ? undefined : going?.left;
  const signedIn = useWorkspaces().value;
  // The accounts staying; all of them when none is (the sign-in page comes once the last is out: Home).
  const staying = signedIn?.filter((a) => a.account.sub !== going?.signingOut);
  const workspaces = staying?.length ? staying : signedIn;
  const last = usePrefs().workspace;
  const list = useAccounts() ?? [];
  const navigate = useNavigate();
  const signIn = useSignIn();
  const signOut = useSignOut();
  const create = useAction(
    (code: string) => cloud.createWorkspace(list[0]!.sub, t("web-pages.cloud.defaultWorkspaceName", { name: list[0]!.name || list[0]!.email.split("@")[0]! }), code),
    (w) => { track("workspace_created", { first: true }); navigate(`/w/${w.id}`, { replace: true }); },
  );
  const accept = useAction(
    (i: { sub: string; id: string }) => cloud.acceptInvitationById(i.sub, i.id),
    (w) => navigate(`/w/${w.id}`, { replace: true }),
  );
  // Once asked for a code, the form stays while a code is tried, rather than flicking to "creating…".
  const asked = useRef(false);
  if (needsInviteCode(create.error)) asked.current = true;
  const asking = asked.current && !create.result;
  const all = workspaces?.flatMap((a) => a.workspaces).filter((w) => w.id !== left) ?? [];
  const pending = workspaces?.flatMap((a) => a.invitations.map((i) => ({ ...i, account: a.account }))) ?? [];
  // Only once every account has answered does "no workspace" mean none: not before, not after a failure.
  const ready = workspaces !== undefined && workspaces.every((a) => a.loaded);
  const failed = workspaces?.find((a) => a.error)?.error;
  // The one last open may not be in what was kept yet: until every account has answered (or failed), it is waited for
  // rather than another put in its place, as the Android app does.
  const lastOpen = all.find((w) => w.id === last);
  const waiting = !!last && !lastOpen && !workspaces?.every((a) => a.loaded || a.error);
  const open = lastOpen ?? (waiting ? undefined : all[0]);
  // The beta app, and an account not let into the beta (the core says so): said, with a way out.
  const blocked = workspaces?.find((a) => a.blocked);
  if (open) return <Navigate to={`/w/${open.id}`} replace />;
  if (waiting) return <Splash label={t("web-pages.cloud.workspacesLoading")}><StatusLine /></Splash>;
  if (blocked) {
    return (
      <div className={`${shellCss.gate} ${css.invitePage}`}>
        <Illustration name="sign-in" />
        <h1>{blocked.blocked}</h1>
        <p>{blocked.account.email}</p>
        <Button variant="primary" busy={signOut.busy(blocked.account.sub)} onClick={() => void signOut.signOut(blocked.account.sub)}>{t("web-pages.cloud.signOutThis")}</Button>
        <Button variant="ghost" busy={signIn.busy} onClick={() => void signIn.signIn()}>{t("web-pages.cloud.switchAccount")}</Button>
      </div>
    );
  }
  if (ready && pending.length > 0) {
    return (
      <div className={`${shellCss.gate} ${css.invitePage}`}>
        <Illustration name="sign-in" />
        <h1>{t("web-pages.cloud.invited")}</h1>
        {pending.map((i) => (
          <div key={i.id} className={`${pagesCss.card} ${pagesCss.cardRow} ${css.inviteCard}`}>
            <div className={pagesCss.cardRowText}><strong>{i.name}</strong><span className={shellCss.muted}>{t("web-pages.cloud.invitedAs", { inviter: i.inviter || t("web-pages.cloud.someone"), email: i.account.email, role: ROLE_LABEL[i.role] })}</span></div>
            <Button variant="primary" busy={accept.busy && accept.arg?.id === i.id} onClick={() => accept.run({ sub: i.account.sub, id: i.id })}>{t("web-pages.cloud.join")}</Button>
          </div>
        ))}
        {accept.error && <p className={controlsCss.fieldError} role="alert">{t("web-pages.cloud.joinFailed", { error: errorText(accept.error) })}</p>}
        {asking
          ? <InviteCodeForm create={create} />
          : <Button variant="ghost" busy={create.busy} onClick={() => create.run(inviteCode())}>{t("web-pages.cloud.createInstead")}</Button>}
        {!asking && create.error && !needsInviteCode(create.error) && <p className={controlsCss.fieldError} role="alert">{errorText(create.error)}</p>}
      </div>
    );
  }
  if (asking) {
    return (
      <div className={`${shellCss.gate} ${css.invitePage}`}>
        <Illustration name="sign-in" />
        <h1>{t("web-pages.cloud.inviteOnly", { name: NAME })}</h1>
        <p>{t("web-pages.cloud.inviteOnlyBody", { name: NAME, email: list[0]!.email })}</p>
        <InviteCodeForm create={create} />
        <Button variant="ghost" busy={signIn.busy} onClick={() => void signIn.signIn()}>{t("web-pages.cloud.switchAccount")}</Button>
      </div>
    );
  }
  if (ready) {
    return (
      <div className={`${shellCss.gate} ${css.invitePage}`}>
        <Illustration name="sign-in" />
        <h1>{t("web-pages.cloud.noWorkspace")}</h1>
        <p>{t("web-pages.cloud.noWorkspaceBody", { name: NAME, email: list[0]!.email })}</p>
        <Button variant="primary" busy={create.busy} onClick={() => create.run(inviteCode())}>{t("web-pages.cloud.createWorkspace")}</Button>
        {create.error && <p className={controlsCss.fieldError} role="alert">{errorText(create.error)}</p>}
        <Button variant="ghost" busy={signIn.busy} onClick={() => void signIn.signIn()}>{t("web-pages.cloud.switchAccount")}</Button>
      </div>
    );
  }
  return <Splash label={failed ? t("web-pages.cloud.workspacesFailed", { error: failed.message }) : t("web-pages.cloud.workspacesLoading")} now={Boolean(failed)}>{!failed && <StatusLine />}</Splash>;
}

/** Asks for the invite code a new workspace needs; what the last try said stands under it. */
function InviteCodeForm({ create }: { create: { run(code: string): void; busy: boolean; error: Error | null; arg: string | undefined } }) {
  const [code, setCode] = useState(() => create.arg ?? inviteCode());
  // Nothing was wrong with a code nobody had typed yet.
  const said = create.error && create.arg ? errorText(create.error) : null;
  return (
    <form className={css.inviteCode} onSubmit={(e) => { e.preventDefault(); if (code.trim()) create.run(code.trim()); }}>
      <div className={additionsCss.inputRow}>
        <input className={`${controlsCss.input} ${shellCss.mono}`} aria-label={t("web-pages.cloud.inviteCode")} value={code} autoFocus placeholder="XXXX-XXXX-XXXX" maxLength={32} spellCheck={false} autoComplete="off"
          onChange={(e) => setCode(e.target.value)} />
        <Button variant="primary" type="submit" disabled={!code.trim()} busy={create.busy}>{t("web-pages.cloud.create")}</Button>
      </div>
      {said && <p className={controlsCss.fieldError} role="alert">{said}</p>}
    </form>
  );
}

/** A workspace by id, through whichever signed-in account belongs to it. */
function WorkspaceRoute() {
  const { ws = "" } = useParams();
  const narrow = useNarrow();
  const workspaces = useWorkspaces().value;
  const owner = workspaces?.find((a) => a.workspaces.some((w) => w.id === ws));
  const found = owner?.workspaces.find((w) => w.id === ws);
  // Shown, it is the one last open on this device: where the app opens next time (Landing).
  const shown = found !== undefined;
  useEffect(() => { if (shown && prefs().workspace !== ws) setPrefs({ workspace: ws }); }, [shown, ws]);
  if (!workspaces) return <Splash label={t("web-pages.cloud.opening")}><StatusLine /></Splash>;
  // One just joined (or kept from before) may not be in what was kept yet: until every account has answered (or failed),
  // it is waited for, not said to be out of reach.
  if ((!owner || !found) && !workspaces.every((a) => a.loaded || a.error)) return <Splash label={t("web-pages.cloud.opening")}><StatusLine /></Splash>;
  if (!owner || !found) return <div className={shellCss.gate}><h1>{t("web-pages.cloud.cantOpen")}</h1><p>{t("web-pages.cloud.cantOpenBody")}</p><a className={`${controlsCss.btn} btn-secondary`} href="/">{t("web-pages.cloud.backTo", { name: NAME })}</a></div>;
  const entry = { id: ws, name: found.name, account: owner.account };
  // A narrow screen is the Android app's (../mobile).
  return narrow
    ? <MobileWorkspace key={`${owner.account.sub}/${ws}`} entry={entry} />
    : <WorkspaceShell key={`${owner.account.sub}/${ws}`} entry={entry} />;
}

type Preview = Awaited<ReturnType<typeof cloud.previewInvitation>>;

function Invite() {
  const token = useMemo(() => location.hash.slice(1), []);
  const list = useAccounts();
  const [chosen, setChosen] = useState("");
  const sub = list?.some((a) => a.sub === chosen) ? chosen : list?.[0]?.sub ?? "";
  // Read once per account: what the link leads to depends on who looks.
  const [preview, setPreview] = useState<{ data: Preview } | { error: Error } | null>(null);
  useEffect(() => {
    setPreview(null);
    if (!sub || !token) return;
    let current = true;
    cloud.previewInvitation(sub, token).then(
      (data) => { if (current) setPreview({ data }); },
      (error: Error) => { if (current) setPreview({ error }); },
    );
    return () => { current = false; };
  }, [sub, token]);
  const accept = useAction(() => cloud.acceptInvitation(sub, token), (w) => location.assign(`/w/${w.id}`));
  const signIn = useSignIn();
  if (!list) return <Splash />;
  if (list.length === 0) return <SignInPage lead={t("web-pages.cloud.inviteSignIn", { name: NAME })} />;
  return (
    <div className={`${shellCss.gate} ${css.invitePage}`}>
      <Illustration name="sign-in" />
      {!preview ? <h1>{t("web-pages.cloud.inviteLoading")}</h1> : "error" in preview ? (
        <><h1>{t("web-pages.cloud.inviteUnusable")}</h1><p>{preview.error.message}</p><a className={`${controlsCss.btn} btn-secondary`} href="/">{t("web-pages.cloud.backTo", { name: NAME })}</a></>
      ) : (
        <>
          <h1>{t("web-pages.cloud.joinNamed", { name: preview.data.name })}</h1>
          <p>{t("web-pages.cloud.invitedYouAs", { inviter: preview.data.inviter || t("web-pages.cloud.someone"), role: ROLE_LABEL[preview.data.role] })}{preview.data.email ? t("web-pages.cloud.inviteOnlyFor", { email: preview.data.email }) : ""}</p>
          {list.length > 1 && (
            <div className={css.inviteAccount}><Select value={sub} onChange={setChosen} label={t("web-pages.cloud.joinWith")} options={list.map((a) => ({ value: a.sub, label: a.email }))} /></div>
          )}
          <div className={css.inviteActions}>
            <Button variant="ghost" busy={signIn.busy} onClick={() => void signIn.signIn()}>{t("web-pages.cloud.switchAccount")}</Button>
            <Button variant="primary" busy={accept.busy} onClick={() => accept.run()}>{t("web-pages.cloud.joinAs", { email: list.find((a) => a.sub === sub)?.email ?? "" })}</Button>
          </div>
          {accept.error && <p className={controlsCss.fieldError} role="alert">{errorText(accept.error)}</p>}
        </>
      )}
    </div>
  );
}

/** A web service on a page of its own (opened from its preview): the whole window. */
function CloudServicePage() {
  const { ws = "", station = "", service = "" } = useParams();
  return <ServicePage station={`${ws}/${station}`} service={service} />;
}

/**
 * An item's link from outside (a session's link in Slack): /o/<workspace>/<station>/<session>. On a computer the
 * desktop app is asked to open it (ember://o/…); when nothing takes it within a moment, or on a phone (where the
 * Android app takes these links itself), or inside the desktop app, it opens here.
 */
function OpenItem() {
  const { ws = "", station = "", session = "" } = useParams();
  // `?preview=<port>`: a web service of the session's, opened beside its chat.
  const { search } = useLocation();
  const target = `/w/${ws}/s/${station}/chats/${encodeURIComponent(session)}${search}`;
  // Offered to the desktop app first only from a computer's browser, as the core says (prefs.ts `device`).
  const [here, setHere] = useState(!usePrefs().device.handoff);
  useEffect(() => {
    if (here) return;
    const timer = setTimeout(() => setHere(true), 1200);
    // If the desktop app takes it, this page loses focus: it stays as it is, for a second look.
    const away = () => clearTimeout(timer);
    window.addEventListener("blur", away, { once: true });
    // ember://, not stillfail://: desktop apps from before the rename know only it, and the new ones take both.
    window.location.href = `ember://o/${ws}/${station}/${encodeURIComponent(session)}${search}`;
    return () => { clearTimeout(timer); window.removeEventListener("blur", away); };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
  if (here) return <Navigate to={target} replace />;
  return (
    <Splash label={t("web-pages.cloud.openingIn", { name: NAME })} now>
      <Button variant="ghost" onClick={() => setHere(true)}>{t("web-pages.cloud.openHere")}</Button>
    </Splash>
  );
}
