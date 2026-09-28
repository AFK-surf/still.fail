// ember cloud's pages: sign-in (several Google accounts at once), the
// workspaces those accounts belong to, their members, invitations and
// stations. (The admin's console is an app of its own, src/admin/.) Everything goes through the
// client core: accounts, ember cloud and the links to stations live there,
// not on the page.
import { Tooltip } from "radix-ui";
import { useEffect, useMemo, useRef, useState } from "react";
import { BrowserRouter, Navigate, Route, Routes, useLocation, useNavigate, useParams } from "react-router";
import { ToastProvider } from "../toast.tsx";
import { Button, Select, Splash, useNarrow } from "../ui.tsx";
import { signIn, useAccounts } from "./accounts.ts";
import { Callback, SignInPage } from "./gate.tsx";
import { WorkspaceShell } from "./workspace.tsx";
import { ROLE_LABEL } from "./settings.tsx";
import { MobileWorkspace } from "../mobile/index.tsx";
import { MobileSignIn } from "../mobile/SignIn.tsx";
import { cloud, errorText, forgetInviteCode, inviteCode, needsInviteCode, useAction, useWorkspaces } from "./api.ts";
import { Illustration } from "../brand.tsx";
import { PageViews, track } from "../telemetry.ts";
import { stationApi, useStationCall } from "../api.ts";

export function CloudApp() {
  return (
    <ToastProvider>
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
  const back = <a className="btn btn-secondary" href="/">回到 ember</a>;
  if (query.get("error") || !code) return <div className="gate"><h1>没有安装</h1><p>Slack 里没有允许安装这个 app。回到 ember 重新点「安装到工作区」。</p>{back}</div>;
  if (list && list.length === 0) return <div className="gate"><h1>先登录 ember</h1><p>要用建这个 app 的账号登录，才能把安装交给 station。登录后再从 ember 里点一次「安装到工作区」。</p>{back}</div>;
  if (!result) return <Splash label="正在把安装交给 station…" />;
  if ("error" in result) return <div className="gate"><h1>没能完成安装</h1><p>{result.error}</p>{back}</div>;
  return <div className="gate"><h1>已装进「{result.team ?? "工作区"}」</h1><p>回到 ember：这个 app 在「连接」页等着，填上 App-Level Token 就能连上。这个页面可以关了。</p></div>;
}

function Home() {
  const list = useAccounts();
  const narrow = useNarrow();
  const navigate = useNavigate();
  // In the desktop app: an item's link opened from outside (ember://o/…) comes here, and the page goes there.
  useEffect(() => {
    const onMessage = (event: MessageEvent) => {
      if (event.origin === location.origin && typeof event.data?.emberNavigate === "string") navigate(event.data.emberNavigate);
    };
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, [navigate]);
  if (!list) return <Splash />;
  if (list.length === 0 && narrow) return <MobileSignIn />;
  if (list.length === 0) return <SignInPage lead={inviteCode() ? "你拿到了 ember 的邀请码。用 Google 账号登录，就能建一个自己的 workspace。" : undefined} />;
  return (
    <Routes>
      <Route path="/" element={<Landing />} />
      <Route path="/o/:ws/:station/:session" element={<OpenItem />} />
      <Route path="/w/:ws/*" element={<WorkspaceRoute />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

/**
 * Straight into a workspace: the first one. An account in none is shown its
 * invitations, or told it is in none; a workspace of its own is made only when
 * it asks for one (with the invite code it came with, or after asking for it).
 */
function Landing() {
  const workspaces = useWorkspaces().value;
  const list = useAccounts() ?? [];
  const navigate = useNavigate();
  const create = useAction(
    (code: string) => cloud.createWorkspace(list[0]!.sub, `${list[0]!.name || list[0]!.email.split("@")[0]} 的 workspace`, code),
    (w) => { track("workspace_created", { first: true }); forgetInviteCode(); navigate(`/w/${w.id}`, { replace: true }); },
  );
  const accept = useAction(
    (i: { sub: string; id: string }) => cloud.acceptInvitationById(i.sub, i.id),
    (w) => navigate(`/w/${w.id}`, { replace: true }),
  );
  // Once asked for a code, the form stays while a code is tried, rather than flicking to "creating…".
  const asked = useRef(false);
  if (needsInviteCode(create.error)) asked.current = true;
  const asking = asked.current && !create.result;
  const first = workspaces?.flatMap((a) => a.workspaces)[0];
  const pending = workspaces?.flatMap((a) => a.invitations.map((i) => ({ ...i, account: a.account }))) ?? [];
  // Only once every account has answered does "no workspace" mean none: not before, not after a failure.
  const ready = workspaces !== undefined && workspaces.every((a) => a.loaded);
  const failed = workspaces?.find((a) => a.error)?.error;
  if (first) return <Navigate to={`/w/${first.id}`} replace />;
  if (ready && pending.length > 0) {
    return (
      <div className="gate invite-page">
        <Illustration name="sign-in" />
        <h1>你收到了邀请</h1>
        {pending.map((i) => (
          <div key={i.id} className="card card-row invite-card">
            <div className="card-row-text"><strong>{i.name}</strong><span className="muted">{i.inviter || "有人"}邀请 {i.account.email} 以{ROLE_LABEL[i.role]}身份加入</span></div>
            <Button variant="primary" busy={accept.busy && accept.arg?.id === i.id} onClick={() => accept.run({ sub: i.account.sub, id: i.id })}>加入</Button>
          </div>
        ))}
        {asking
          ? <InviteCodeForm create={create} />
          : <Button variant="ghost" busy={create.busy} onClick={() => create.run(inviteCode())}>不加入，建一个自己的 workspace</Button>}
      </div>
    );
  }
  if (asking) {
    return (
      <div className="gate invite-page">
        <Illustration name="sign-in" />
        <h1>ember 目前只对受邀的人开放</h1>
        <p>有邀请码的话填在下面，就能建一个自己的 workspace。也可以请已经在用 ember 的人把 {list[0]!.email} 邀请进他们的 workspace。</p>
        <InviteCodeForm create={create} />
        <Button variant="ghost" onClick={() => void signIn()}>换一个账号</Button>
      </div>
    );
  }
  if (ready) {
    return (
      <div className="gate invite-page">
        <Illustration name="sign-in" />
        <h1>你还不在任何 workspace 里</h1>
        <p>可以请已经在用 ember 的人把 {list[0]!.email} 邀请进他们的 workspace，也可以自己建一个。</p>
        <Button variant="primary" busy={create.busy} onClick={() => create.run(inviteCode())}>建一个 workspace</Button>
        {create.error && <p className="field-error" role="alert">{errorText(create.error)}</p>}
        <Button variant="ghost" onClick={() => void signIn()}>换一个账号</Button>
      </div>
    );
  }
  return <Splash label={failed ? `没能读取你的 workspace：${failed.message}` : "正在读取你的 workspace…"} now={Boolean(failed)} />;
}

/** Asks for the invite code a new workspace needs; what the last try said stands under it. */
function InviteCodeForm({ create }: { create: { run(code: string): void; busy: boolean; error: Error | null; arg: string | undefined } }) {
  const [code, setCode] = useState(() => create.arg ?? inviteCode());
  // Nothing was wrong with a code nobody had typed yet.
  const said = create.error && create.arg ? errorText(create.error) : null;
  return (
    <form className="invite-code" onSubmit={(e) => { e.preventDefault(); if (code.trim()) create.run(code.trim()); }}>
      <div className="input-row">
        <input className="input mono" aria-label="邀请码" value={code} autoFocus placeholder="XXXX-XXXX-XXXX" maxLength={32} spellCheck={false} autoComplete="off"
          onChange={(e) => setCode(e.target.value)} />
        <Button variant="primary" type="submit" disabled={!code.trim()} busy={create.busy}>建 workspace</Button>
      </div>
      {said && <p className="field-error" role="alert">{said}</p>}
    </form>
  );
}

/** A workspace by id, through whichever signed-in account belongs to it. */
function WorkspaceRoute() {
  const { ws = "" } = useParams();
  const narrow = useNarrow();
  const workspaces = useWorkspaces().value;
  if (!workspaces) return <Splash label="正在打开 workspace…" />;
  const owner = workspaces.find((a) => a.workspaces.some((w) => w.id === ws));
  const found = owner?.workspaces.find((w) => w.id === ws);
  if (!owner || !found) return <div className="gate"><h1>打不开这个 workspace</h1><p>你登录的账号都不在里面。</p><a className="btn btn-secondary" href="/">回到 ember</a></div>;
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
  if (!list) return <Splash />;
  if (list.length === 0) return <SignInPage lead="你收到了一个 ember workspace 的邀请。先用 Google 账号登录，再决定是否加入。" />;
  return (
    <div className="gate invite-page">
      <Illustration name="sign-in" />
      {!preview ? <h1>正在读取邀请…</h1> : "error" in preview ? (
        <><h1>邀请不能用</h1><p>{preview.error.message}</p><a className="btn btn-secondary" href="/">回到 ember</a></>
      ) : (
        <>
          <h1>加入「{preview.data.name}」</h1>
          <p>{preview.data.inviter || "有人"}邀请你以{ROLE_LABEL[preview.data.role]}身份加入。{preview.data.email ? `这个邀请只能由 ${preview.data.email} 接受。` : ""}</p>
          {list.length > 1 && (
            <div className="invite-account"><Select value={sub} onChange={setChosen} label="用哪个账号加入" options={list.map((a) => ({ value: a.sub, label: a.email }))} /></div>
          )}
          <div className="invite-actions">
            <Button variant="ghost" onClick={() => void signIn()}>换一个账号</Button>
            <Button variant="primary" busy={accept.busy} onClick={() => accept.run()}>以 {list.find((a) => a.sub === sub)?.email} 加入</Button>
          </div>
          {accept.error && <p className="field-error" role="alert">{accept.error.message}</p>}
        </>
      )}
    </div>
  );
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
  const inDesktop = "emberDesktop" in window;
  const phone = /Android|iPhone|iPad/i.test(navigator.userAgent);
  const [here, setHere] = useState(inDesktop || phone);
  useEffect(() => {
    if (here) return;
    const timer = setTimeout(() => setHere(true), 1200);
    // If the desktop app takes it, this page loses focus: it stays as it is, for a second look.
    const away = () => clearTimeout(timer);
    window.addEventListener("blur", away, { once: true });
    window.location.href = `ember://o/${ws}/${station}/${encodeURIComponent(session)}${search}`;
    return () => { clearTimeout(timer); window.removeEventListener("blur", away); };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
  if (here) return <Navigate to={target} replace />;
  return (
    <Splash label="正在用 ember 打开…" now>
      <Button variant="ghost" onClick={() => setHere(true)}>在网页里打开</Button>
    </Splash>
  );
}
