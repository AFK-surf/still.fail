// ember cloud's pages: sign-in (several Google accounts at once), the
// workspaces those accounts belong to, their members, invitations and
// stations; and, for the admin, the console. Everything goes through the
// client core: accounts, ember cloud and the links to stations live there,
// not on the page.
import { Tooltip } from "radix-ui";
import { useEffect, useMemo, useRef, useState } from "react";
import { BrowserRouter, Navigate, Route, Routes, useNavigate, useParams } from "react-router";
import { ToastProvider } from "../toast.tsx";
import { Button, Loading, Select } from "../ui.tsx";
import { completeSignIn, signIn, useAccounts } from "./accounts.ts";
import { SignInPage } from "./gate.tsx";
import { WorkspaceShell } from "./workspace.tsx";
import { ROLE_LABEL } from "./settings.tsx";
import { AdminConsole } from "./admin.tsx";
import { cloud, errorText, forgetInviteCode, inviteCode, needsInviteCode, useAction, useWorkspaces } from "./api.ts";
import { Illustration } from "../brand.tsx";

export function CloudApp() {
  return (
    <ToastProvider>
      <Tooltip.Provider delayDuration={400}>
        <BrowserRouter>
          <Routes>
            <Route path="/auth/callback" element={<Callback />} />
            <Route path="/invite" element={<Invite />} />
            <Route path="*" element={<Home />} />
          </Routes>
        </BrowserRouter>
      </Tooltip.Provider>
    </ToastProvider>
  );
}

function Callback() {
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    completeSignIn().then((next) => location.replace(next), (e: Error) => setError(e.message));
  }, []);
  return (
    <div className="gate">
      <Illustration name="sign-in" />
      <h1>{error ? "登录没有完成" : "正在登录…"}</h1>
      {error && <><p>{error}</p><Button variant="primary" onClick={() => void signIn("/")}>重新登录</Button></>}
    </div>
  );
}

function Home() {
  const list = useAccounts();
  if (!list) return <div className="gate"><Loading /></div>;
  if (list.length === 0) return <SignInPage lead={inviteCode() ? "你拿到了 ember 的邀请码。用 Google 账号登录，就能建一个自己的 workspace。" : undefined} />;
  return (
    <Routes>
      <Route path="/" element={<Landing />} />
      <Route path="/admin/*" element={<AdminConsole />} />
      <Route path="/w/:ws/*" element={<WorkspaceRoute />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

/**
 * Straight into a workspace: the first one, or, for an account with none and
 * no invitations, a new one of its own — with the invite code it came with,
 * or, lacking one, after asking for it.
 */
function Landing() {
  const workspaces = useWorkspaces().value;
  const list = useAccounts() ?? [];
  const navigate = useNavigate();
  const create = useAction(
    (code: string) => cloud.createWorkspace(list[0]!.sub, `${list[0]!.name || list[0]!.email.split("@")[0]} 的 workspace`, code),
    (w) => { forgetInviteCode(); navigate(`/w/${w.id}`, { replace: true }); },
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
  const ready = workspaces !== undefined;
  useEffect(() => {
    if (ready && !first && pending.length === 0 && !create.busy && !create.result && !create.error) create.run(inviteCode());
  }, [ready, first, pending.length]); // eslint-disable-line react-hooks/exhaustive-deps
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
  if (create.error) return <div className="gate"><h1>没能建好 workspace</h1><p>{create.error.message}</p><Button onClick={() => create.run(inviteCode())}>重试</Button></div>;
  return <div className="gate"><Loading label={ready ? "正在为你建一个 workspace…" : "正在读取你的 workspace…"} /></div>;
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
  const workspaces = useWorkspaces().value;
  if (!workspaces) return <div className="gate"><Loading label="正在打开 workspace…" /></div>;
  const owner = workspaces.find((a) => a.workspaces.some((w) => w.id === ws));
  const found = owner?.workspaces.find((w) => w.id === ws);
  if (!owner || !found) return <div className="gate"><h1>打不开这个 workspace</h1><p>你登录的账号都不在里面。</p><a className="btn btn-secondary" href="/">回到 ember</a></div>;
  return (
    <WorkspaceShell key={`${owner.account.sub}/${ws}`} entry={{ id: ws, name: found.name, account: owner.account }} />
  );
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
  if (!list) return <div className="gate"><Loading /></div>;
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
