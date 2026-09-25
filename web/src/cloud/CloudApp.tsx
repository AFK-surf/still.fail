// ember cloud's pages: sign-in (several Google accounts at once), the
// workspaces those accounts belong to, their members, invitations and
// stations. Opening a station hands over to the station's own admin client
// (StationFrame), which talks to it over iroh.
import { QueryClient, QueryClientProvider, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, ChevronsUpDown, Copy, LogOut, Plus, Trash2, UserPlus } from "lucide-react";
import { DropdownMenu, Tooltip } from "radix-ui";
import { useEffect, useMemo, useState, type ReactNode } from "react";
import { BrowserRouter, Link, Navigate, Route, Routes, useNavigate, useParams } from "react-router";
import { relativeTime, timeUntil } from "../format.ts";
import { ToastProvider, useToast } from "../toast.tsx";
import { Button, Confirm, Loading, CopyCommand, Dialog, Empty, Field, ICON, Menu, MobileBack, Pill, Section, Select, StatusDot } from "../ui.tsx";
import { completeSignIn, signIn, type Account } from "./accounts.ts";
import { Avatar, online, SignInPage, useAccounts } from "./gate.tsx";
import { useInvitations, useWorkspaces, WorkspaceShell } from "./workspace.tsx";
import { ROLE_LABEL } from "./settings.tsx";
import { cloud, CloudError, type Role, type StationView, type WorkspaceView } from "./api.ts";

const client = new QueryClient({ defaultOptions: { queries: { refetchOnWindowFocus: false, retry: (n, e) => !(e instanceof CloudError && e.status < 500) && n < 2 } } });

export function CloudApp() {
  return (
    <QueryClientProvider client={client}>
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
    </QueryClientProvider>
  );
}

function Callback() {
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    completeSignIn().then((next) => location.replace(next), (e: Error) => setError(e.message));
  }, []);
  return (
    <div className="gate">
      <img src={`${import.meta.env.BASE_URL}ember.svg`} alt="" width={40} height={40} />
      <h1>{error ? "登录没有完成" : "正在登录…"}</h1>
      {error && <><p>{error}</p><Button variant="primary" onClick={() => void signIn("/")}>重新登录</Button></>}
    </div>
  );
}

function Home() {
  const list = useAccounts();
  if (list.length === 0) return <SignInPage />;
  return (
    <Routes>
      <Route path="/" element={<Landing />} />
      <Route path="/w/:ws/*" element={<WorkspaceRoute />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

/** Straight into a workspace: the first one, or, for an account with none and no invitations, a new one of its own. */
function Landing() {
  const workspaces = useWorkspaces();
  const invitations = useInvitations();
  const list = useAccounts();
  const navigate = useNavigate();
  const queries = useQueryClient();
  const create = useMutation({
    mutationFn: () => cloud.createWorkspace(list[0]!.sub, `${list[0]!.name || list[0]!.email.split("@")[0]} 的 workspace`),
    onSuccess: (w) => { void queries.invalidateQueries({ queryKey: ["cloud"] }); navigate(`/w/${w.id}`, { replace: true }); },
  });
  const accept = useMutation({
    mutationFn: (i: { sub: string; id: string }) => cloud.acceptInvitationById(i.sub, i.id),
    onSuccess: (w) => { void queries.invalidateQueries({ queryKey: ["cloud"] }); navigate(`/w/${w.id}`, { replace: true }); },
  });
  const first = workspaces.data?.[0];
  const pending = invitations.data ?? [];
  const ready = !workspaces.isPending && !invitations.isPending;
  useEffect(() => {
    if (ready && !first && pending.length === 0 && !create.isPending && !create.isSuccess && !create.isError) create.mutate();
  }, [ready, first, pending.length]); // eslint-disable-line react-hooks/exhaustive-deps
  if (first) return <Navigate to={`/w/${first.id}`} replace />;
  if (ready && pending.length > 0) {
    return (
      <div className="gate invite-page">
        <img src={`${import.meta.env.BASE_URL}ember.svg`} alt="" width={44} height={44} />
        <h1>你收到了邀请</h1>
        {pending.map((i) => (
          <div key={i.id} className="card card-row invite-card">
            <div className="card-row-text"><strong>{i.name}</strong><span className="muted">{i.inviter || "有人"}邀请 {i.account.email} 以{ROLE_LABEL[i.role]}身份加入</span></div>
            <Button variant="primary" busy={accept.isPending && accept.variables?.id === i.id} onClick={() => accept.mutate({ sub: i.account.sub, id: i.id })}>加入</Button>
          </div>
        ))}
        <Button variant="ghost" busy={create.isPending} onClick={() => create.mutate()}>不加入，建一个自己的 workspace</Button>
      </div>
    );
  }
  if (create.isError) return <div className="gate"><h1>没能建好 workspace</h1><p>{create.error.message}</p><Button onClick={() => create.mutate()}>重试</Button></div>;
  return <div className="gate"><Loading label={workspaces.isPending || invitations.isPending ? "正在读取你的 workspace…" : "正在为你建一个 workspace…"} /></div>;
}

/** A workspace by id, through whichever signed-in account belongs to it. */
function WorkspaceRoute() {
  const { ws = "" } = useParams();
  const workspaces = useWorkspaces();
  if (workspaces.isPending) return <div className="gate"><Loading label="正在打开 workspace…" /></div>;
  const entry = workspaces.data?.find((w) => w.id === ws);
  if (!entry) return <div className="gate"><h1>打不开这个 workspace</h1><p>你登录的账号都不在里面。</p><a className="btn btn-secondary" href="/">回到 ember</a></div>;
  return (
    <WorkspaceShell key={`${entry.account.sub}/${ws}`} entry={entry} />
  );
}

function Invite() {
  const token = useMemo(() => location.hash.slice(1), []);
  const list = useAccounts();
  const [chosen, setChosen] = useState(list[0]?.sub ?? "");
  const sub = list.some((a) => a.sub === chosen) ? chosen : list[0]?.sub ?? "";
  const preview = useQuery({ queryKey: ["cloud", "invite", sub], queryFn: () => cloud.previewInvitation(sub, token), enabled: Boolean(sub && token), retry: false });
  const accept = useMutation({ mutationFn: () => cloud.acceptInvitation(sub, token), onSuccess: (w) => location.assign(`/w/${w.id}`) });
  if (list.length === 0) return <SignInPage lead="你收到了一个 ember workspace 的邀请。先用 Google 账号登录，再决定是否加入。" />;
  return (
    <div className="gate invite-page">
      <img src={`${import.meta.env.BASE_URL}ember.svg`} alt="" width={44} height={44} />
      {preview.isPending ? <h1>正在读取邀请…</h1> : preview.isError ? (
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
            <Button variant="primary" busy={accept.isPending} onClick={() => accept.mutate()}>以 {list.find((a) => a.sub === sub)?.email} 加入</Button>
          </div>
          {accept.error && <p className="field-error" role="alert">{accept.error.message}</p>}
        </>
      )}
    </div>
  );
}

