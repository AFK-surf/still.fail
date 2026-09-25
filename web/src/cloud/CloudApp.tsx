// ember cloud's pages: sign-in (several Google accounts at once), the
// workspaces those accounts belong to, their members, invitations and
// stations. Opening a station hands over to the station's own admin client
// (StationFrame), which talks to it over iroh.
import { QueryClient, QueryClientProvider, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, ChevronsUpDown, Copy, LogOut, Plus, Trash2, UserPlus } from "lucide-react";
import { DropdownMenu, Tooltip } from "radix-ui";
import { useEffect, useMemo, useState, type ReactNode } from "react";
import { BrowserRouter, Navigate, NavLink, Route, Routes, useNavigate, useParams } from "react-router";
import { relativeTime, timeUntil } from "../format.ts";
import { ToastProvider, useToast } from "../toast.tsx";
import { Button, Confirm, CopyCommand, Dialog, Empty, Field, ICON, Menu, MobileBack, Pill, Section, Select, StatusDot } from "../ui.tsx";
import { completeSignIn, signIn, signOut, type Account } from "./accounts.ts";
import { Avatar, online, SignInPage, useAccounts } from "./gate.tsx";
import { cloud, CloudError, type Role, type StationView, type WorkspaceView } from "./api.ts";

const ROLE_LABEL: Record<Role, string> = { owner: "Owner", admin: "管理员", member: "成员" };
const ROLE_HINT: Record<Role, string> = {
  owner: "管理一切，包括成员角色和删除 workspace",
  admin: "邀请成员、添加和移除 station",
  member: "使用 workspace 里的 station",
};

/** Every workspace of every signed-in account, each with the account that reaches it. */
export function useWorkspaces() {
  const list = useAccounts();
  return useQuery({
    queryKey: ["cloud", "me", list.map((a) => a.sub).join(",")],
    queryFn: async () => {
      const results = await Promise.all(list.map(async (account) => ({ account, me: await cloud.me(account.sub).catch(() => null) })));
      return results.flatMap(({ account, me }) => (me?.workspaces ?? []).map((w) => ({ ...w, account, relay: me!.relay_url })));
    },
    enabled: list.length > 0,
  });
}

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
    <div className="shell">
      <CloudSidebar />
      <main className="main">
        <Routes>
          <Route path="/" element={<Landing />} />
          <Route path="/w/:ws" element={<WorkspacePage />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
    </div>
  );
}

function AccountMenu() {
  const list = useAccounts();
  const toast = useToast();
  const first = list[0]!;
  return (
    <DropdownMenu.Root modal={false}>
      <DropdownMenu.Trigger asChild>
        <button type="button" className="account-trigger" aria-label="账号">
          <Avatar account={first} size={26} />
          <span className="account-text">
            <span className="account-name">{list.length > 1 ? `${list.length} 个账号` : first.name || first.email}</span>
            <span className="account-email">{list.length > 1 ? list.map((a) => a.email.split("@")[0]).join("、") : first.email}</span>
          </span>
          <ChevronsUpDown {...ICON} size={14} />
        </button>
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className="popover menu-list account-menu" align="start" sideOffset={4}>
          <DropdownMenu.Label className="menu-label">已登录的账号</DropdownMenu.Label>
          {list.map((a) => (
            <DropdownMenu.Sub key={a.sub}>
              <DropdownMenu.SubTrigger className="menu-item">
                <Avatar account={a} size={22} />
                <span className="thread-item"><span>{a.name || a.email}</span><span className="muted">{a.email}</span></span>
              </DropdownMenu.SubTrigger>
              <DropdownMenu.Portal>
                <DropdownMenu.SubContent className="popover menu-list" sideOffset={6}>
                  <DropdownMenu.Item className="menu-item" data-danger onSelect={() => void signOut(a.sub).then(() => toast(`已退出 ${a.email}`))}>
                    <LogOut {...ICON} />退出这个账号
                  </DropdownMenu.Item>
                </DropdownMenu.SubContent>
              </DropdownMenu.Portal>
            </DropdownMenu.Sub>
          ))}
          <DropdownMenu.Separator className="menu-sep" />
          <DropdownMenu.Item className="menu-item" onSelect={() => void signIn()}><UserPlus {...ICON} />添加另一个账号</DropdownMenu.Item>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

function CloudSidebar() {
  const workspaces = useWorkspaces();
  const list = useAccounts();
  const [creating, setCreating] = useState(false);
  const many = list.length > 1;
  return (
    <nav className="sidebar" aria-label="导航">
      <div className="brand"><img src={`${import.meta.env.BASE_URL}ember.svg`} alt="" width={22} height={22} /><span className="brand-word">ember</span></div>
      <div className="account-slot"><AccountMenu /></div>
      <div className="nav-scroll">
        <div className="nav-heading nav-heading-action">
          <span>Workspace</span>
          <button type="button" className="icon-btn" aria-label="新建 workspace" onClick={() => setCreating(true)}><Plus {...ICON} /></button>
        </div>
        {workspaces.data?.length === 0 && <p className="nav-empty">还没有 workspace。新建一个，或者让别人邀请你。</p>}
        {workspaces.data?.map((w) => (
          <NavLink key={`${w.account.sub}:${w.id}`} className="nav-row nav-session" to={`/w/${w.id}`}>
            <span className="ws-mark" aria-hidden="true">{([...w.name][0] ?? "?").toUpperCase()}</span>
            <span className="nav-session-text">
              <span className="nav-session-title">{w.name}</span>
              <span className="nav-session-meta">
                <span className="nav-text">{w.stations} 台 station · {w.members} 人{many ? ` · ${w.account.email}` : ""}</span>
              </span>
            </span>
          </NavLink>
        ))}
      </div>
      <NewWorkspaceDialog open={creating} onClose={() => setCreating(false)} />
    </nav>
  );
}

function NewWorkspaceDialog({ open, onClose }: { open: boolean; onClose(): void }) {
  const list = useAccounts();
  const navigate = useNavigate();
  const queries = useQueryClient();
  const [name, setName] = useState("");
  const [owner, setOwner] = useState(list[0]?.sub ?? "");
  const create = useMutation({
    mutationFn: () => cloud.createWorkspace(owner || list[0]!.sub, name),
    onSuccess: (w) => { void queries.invalidateQueries({ queryKey: ["cloud"] }); setName(""); onClose(); navigate(`/w/${w.id}`); },
  });
  return (
    <Dialog open={open} onClose={onClose} title="新建 workspace" description="workspace 是一组人和他们共用的 station。你会成为它的 owner。"
      footer={<><Button variant="ghost" onClick={onClose}>取消</Button><Button variant="primary" disabled={!name.trim()} busy={create.isPending} onClick={() => create.mutate()}>新建</Button></>}>
      <Field label="名字" htmlFor="ws-name">
        <input id="ws-name" className="input" value={name} autoFocus onChange={(e) => setName(e.target.value)} placeholder="例如：Cue 团队" maxLength={80}
          onKeyDown={(e) => { if (e.key === "Enter" && name.trim()) create.mutate(); }} />
      </Field>
      {list.length > 1 && (
        <Field label="属于哪个账号" htmlFor="ws-owner">
          <Select id="ws-owner" value={owner} onChange={setOwner} options={list.map((a) => ({ value: a.sub, label: a.email }))} />
        </Field>
      )}
      {create.error && <p className="field-error" role="alert">{create.error.message}</p>}
    </Dialog>
  );
}

function Landing() {
  const workspaces = useWorkspaces();
  if (workspaces.isPending) return null;
  const first = workspaces.data?.[0];
  if (first) return <Navigate to={`/w/${first.id}`} replace />;
  return (
    <Empty>
      <img src={`${import.meta.env.BASE_URL}ember.svg`} alt="" width={36} height={36} />
      <h2>还没有 workspace</h2>
      <p>点左侧「Workspace」旁边的 + 新建一个；别人邀请你的话，打开邀请链接即可加入。</p>
    </Empty>
  );
}

function WorkspacePage() {
  const { ws = "" } = useParams();
  const workspaces = useWorkspaces();
  const entry = workspaces.data?.find((w) => w.id === ws);
  const view = useQuery({
    queryKey: ["cloud", "workspace", ws, entry?.account.sub],
    queryFn: () => cloud.workspace(entry!.account.sub, ws),
    enabled: Boolean(entry),
    refetchInterval: 30_000,
  });
  if (workspaces.isPending || (entry && view.isPending)) return <div className="page" />;
  if (!entry) return <Empty><p>你登录的账号里没有这个 workspace。</p></Empty>;
  if (view.isError) return <Empty><p>{view.error.message}</p></Empty>;
  return <WorkspaceDetail key={ws} view={view.data!} account={entry.account} />;
}

function WorkspaceDetail({ view, account }: { view: WorkspaceView; account: Account }) {
  const queries = useQueryClient();
  const navigate = useNavigate();
  const toast = useToast();
  const manager = view.role === "owner" || view.role === "admin";
  const refresh = () => void queries.invalidateQueries({ queryKey: ["cloud"] });
  const [leaving, setLeaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const leave = useMutation({ mutationFn: () => cloud.removeMember(account.sub, view.id, account.sub), onSuccess: () => { refresh(); toast("已退出 workspace"); navigate("/"); } });
  const remove = useMutation({ mutationFn: () => cloud.deleteWorkspace(account.sub, view.id), onSuccess: () => { refresh(); toast("已删除 workspace"); navigate("/"); } });
  const rename = useMutation({ mutationFn: (name: string) => cloud.renameWorkspace(account.sub, view.id, name), onSuccess: refresh });

  return (
    <div className="page page-narrow">
      <MobileBack to="/" label="Workspace" />
      <header className="identity">
        <span className="ws-mark ws-mark-lg" aria-hidden="true">{([...view.name][0] ?? "?").toUpperCase()}</span>
        <div className="identity-text">
          <h1 className="identity-name">{view.name}</h1>
          <p className="identity-sub"><span>{ROLE_LABEL[view.role]}</span><span>{account.email}</span></p>
        </div>
        <Menu items={[
          ...(manager ? [{ label: "改名", onSelect: () => { const n = window.prompt("新的名字", view.name); if (n?.trim()) rename.mutate(n.trim()); } }] : []),
          { label: "退出这个 workspace", icon: LogOut, onSelect: () => setLeaving(true) },
          ...(view.role === "owner" ? ["separator" as const, { label: "删除 workspace", icon: Trash2, danger: true, onSelect: () => setDeleting(true) }] : []),
        ]} />
      </header>
      <Stations view={view} account={account} manager={manager} />
      <Members view={view} account={account} manager={manager} />
      <Confirm open={leaving} onClose={() => setLeaving(false)} busy={leave.isPending} onConfirm={() => leave.mutate()}
        title={`退出「${view.name}」？`} action="退出" description={leave.error?.message ?? "退出后你就不能再访问里面的 station，需要重新被邀请才能回来。"} />
      <Confirm open={deleting} onClose={() => setDeleting(false)} busy={remove.isPending} onConfirm={() => remove.mutate()}
        title={`删除「${view.name}」？`} action="删除 workspace"
        description={remove.error?.message ?? `所有成员都会失去访问权限，${view.stations.length} 台 station 会断开和 ember cloud 的连接（station 本机上的数据不受影响）。`} />
    </div>
  );
}

function Stations({ view, account, manager }: { view: WorkspaceView; account: Account; manager: boolean }) {
  const [adding, setAdding] = useState(false);
  const [removing, setRemoving] = useState<StationView | null>(null);
  const queries = useQueryClient();
  const remove = useMutation({
    mutationFn: (s: StationView) => cloud.removeStation(account.sub, view.id, s.id),
    onSuccess: () => { setRemoving(null); void queries.invalidateQueries({ queryKey: ["cloud"] }); },
  });
  const rename = useMutation({ mutationFn: ({ id, name }: { id: string; name: string }) => cloud.renameStation(account.sub, view.id, id, name), onSuccess: () => void queries.invalidateQueries({ queryKey: ["cloud"] }) });
  return (
    <Section title="Station" description="每台 station 是一台运行 ember 的机器：它的连接、会话和运行时账号都在那台机器上。"
      actions={manager && <Button icon={Plus} onClick={() => setAdding(true)}>添加 station</Button>}>
      {view.stations.length === 0 ? (
        <div className="card"><p className="muted">{manager ? "还没有 station。点「添加 station」，在要运行 ember 的机器上执行一条命令即可加入。" : "还没有 station，等管理员添加。"}</p></div>
      ) : (
        <ul className="list">
          {view.stations.map((s) => (
            <li key={s.id} className="list-row station-row">
              <StatusDot state={online(s) ? "online" : "offline"} label={online(s) ? "在线" : "离线"} />
              <span className="list-row-text">
                <span className="list-row-title">{s.name}</span>
                <span className="muted">
                  {online(s) ? "在线" : s.last_seen ? `${relativeTime(s.last_seen * 1000)}在线` : "还没上线"}
                  {s.version ? ` · ember-mesh ${s.version}` : ""} · <span className="mono">{s.id.slice(0, 12)}</span>
                </span>
              </span>
              <a className="btn btn-secondary" href={`/w/${view.id}/s/${s.id}/sessions`}>打开</a>
              {manager && <Menu items={[
                { label: "改名", onSelect: () => { const n = window.prompt("station 的名字", s.name); if (n?.trim()) rename.mutate({ id: s.id, name: n.trim() }); } },
                { label: "从 workspace 移除", icon: Trash2, danger: true, onSelect: () => setRemoving(s) },
              ]} />}
            </li>
          ))}
        </ul>
      )}
      {adding && <AddStationDialog view={view} account={account} onClose={() => setAdding(false)} />}
      <Confirm open={removing !== null} onClose={() => setRemoving(null)} busy={remove.isPending} onConfirm={() => removing && remove.mutate(removing)}
        title={`移除「${removing?.name ?? ""}」？`} action="移除 station"
        description="它会断开与 ember cloud 的连接，成员不能再从这里访问它。那台机器上的 ember 和数据不受影响，之后可以重新添加。" />
    </Section>
  );
}

function AddStationDialog({ view, account, onClose }: { view: WorkspaceView; account: Account; onClose(): void }) {
  const [name, setName] = useState("");
  const known = useMemo(() => new Set(view.stations.map((s) => s.id)), [view.stations]);
  const enroll = useMutation({ mutationFn: () => cloud.enroll(account.sub, view.id, name) });
  // Watch for the station to show up once the command ran.
  const watch = useQuery({
    queryKey: ["cloud", "enroll-watch", view.id],
    queryFn: () => cloud.workspace(account.sub, view.id),
    enabled: enroll.isSuccess,
    refetchInterval: 3000,
  });
  const joined = watch.data?.stations.find((s) => !known.has(s.id));
  const queries = useQueryClient();
  useEffect(() => { if (joined) void queries.invalidateQueries({ queryKey: ["cloud", "me"] }); }, [joined, queries]);
  return (
    <Dialog open onClose={onClose} wide title="添加 station"
      description="station 是一台运行 ember 的机器。给它起个名字，然后在那台机器上执行生成的命令。"
      footer={joined ? <Button variant="primary" onClick={onClose}>完成</Button> : <>
        <Button variant="ghost" onClick={onClose}>{enroll.isSuccess ? "关闭" : "取消"}</Button>
        {!enroll.isSuccess && <Button variant="primary" disabled={!name.trim()} busy={enroll.isPending} onClick={() => enroll.mutate()}>生成命令</Button>}
      </>}>
      {!enroll.isSuccess ? (
        <Field label="名字" htmlFor="station-name" hint="比如机器名：studio、mac-mini、gpu-box。">
          <input id="station-name" className="input" value={name} autoFocus onChange={(e) => setName(e.target.value)} maxLength={80}
            onKeyDown={(e) => { if (e.key === "Enter" && name.trim()) enroll.mutate(); }} />
        </Field>
      ) : joined ? (
        <div className="callout" data-tone="green"><Check {...ICON} /><span>「{joined.name}」已加入，现在可以打开它了。</span></div>
      ) : (
        <>
          <ol className="steps">
            <li><span>在要当 station 的机器上，进入 ember 的目录，执行：</span><CopyCommand text={`bin/${enroll.data.command}`} /></li>
            <li>ember 正在运行的话，几秒内就会连上；没有运行就启动它（<span className="mono">pnpm start</span>）。</li>
          </ol>
          <p className="muted dialog-note"><span className="activity-pulse inline" aria-hidden="true" />等待 station 加入… 命令 1 小时内有效，只能用一次。</p>
        </>
      )}
      {enroll.error && <p className="field-error" role="alert">{enroll.error.message}</p>}
    </Dialog>
  );
}

function Members({ view, account, manager }: { view: WorkspaceView; account: Account; manager: boolean }) {
  const queries = useQueryClient();
  const toast = useToast();
  const [inviting, setInviting] = useState(false);
  const refresh = () => void queries.invalidateQueries({ queryKey: ["cloud"] });
  const setRole = useMutation({ mutationFn: ({ sub, role }: { sub: string; role: Role }) => cloud.setRole(account.sub, view.id, sub, role), onSuccess: () => { refresh(); toast("已更改角色"); } });
  const remove = useMutation({ mutationFn: (sub: string) => cloud.removeMember(account.sub, view.id, sub), onSuccess: () => { refresh(); toast("已移除成员"); } });
  const revoke = useMutation({ mutationFn: (id: string) => cloud.revokeInvitation(account.sub, view.id, id), onSuccess: refresh });
  return (
    <Section title="成员" actions={manager && <Button icon={UserPlus} onClick={() => setInviting(true)}>邀请成员</Button>}>
      <ul className="list">
        {view.members.map((m) => (
          <li key={m.sub} className="list-row">
            <Avatar account={m} size={28} />
            <span className="list-row-text">
              <span className="list-row-title">{m.name || m.email}{m.sub === account.sub && <span className="choice-badge">你</span>}</span>
              <span className="muted">{m.email}</span>
            </span>
            {view.role === "owner" && m.sub !== account.sub ? (
              <div className="role-select">
                <Select value={m.role} onChange={(role) => setRole.mutate({ sub: m.sub, role: role as Role })} label="角色"
                  options={(["owner", "admin", "member"] as Role[]).map((r) => ({ value: r, label: ROLE_LABEL[r] }))} />
              </div>
            ) : <Pill>{ROLE_LABEL[m.role]}</Pill>}
            {manager && m.sub !== account.sub && (m.role !== "owner" || view.role === "owner") && (
              <Menu items={[{ label: "移出 workspace", icon: Trash2, danger: true, onSelect: () => { if (window.confirm(`把 ${m.email} 移出「${view.name}」？`)) remove.mutate(m.sub); } }]} />
            )}
          </li>
        ))}
      </ul>
      {(setRole.error || remove.error) && <p className="field-error" role="alert">{(setRole.error ?? remove.error)!.message}</p>}
      {manager && view.invitations.length > 0 && (
        <>
          <div className="group-head"><strong>未接受的邀请</strong><span className="muted">{view.invitations.length} 个</span></div>
          <ul className="list">
            {view.invitations.map((i) => (
              <li key={i.id} className="list-row">
                <span className="list-row-text">
                  <span className="list-row-title">{i.email ?? "任何拿到链接的人"}</span>
                  <span className="muted">{ROLE_LABEL[i.role]} · {timeUntil(i.expires_at * 1000)}过期</span>
                </span>
                <Button variant="ghost" busy={revoke.isPending && revoke.variables === i.id} onClick={() => revoke.mutate(i.id)}>撤回</Button>
              </li>
            ))}
          </ul>
        </>
      )}
      {inviting && <InviteDialog view={view} account={account} onClose={() => setInviting(false)} />}
    </Section>
  );
}

function InviteDialog({ view, account, onClose }: { view: WorkspaceView; account: Account; onClose(): void }) {
  const queries = useQueryClient();
  const [role, setRole] = useState<Role>("member");
  const [email, setEmail] = useState("");
  const [copied, setCopied] = useState(false);
  const invite = useMutation({ mutationFn: () => cloud.invite(account.sub, view.id, role, email.trim()), onSuccess: () => void queries.invalidateQueries({ queryKey: ["cloud", "workspace"] }) });
  const roles: Role[] = view.role === "owner" ? ["member", "admin", "owner"] : ["member", "admin"];
  return (
    <Dialog open onClose={onClose} title="邀请成员" description={`生成一个加入「${view.name}」的链接，发给对方。链接 7 天内有效，只能用一次。`}
      footer={invite.isSuccess ? <Button variant="primary" onClick={onClose}>完成</Button> : <>
        <Button variant="ghost" onClick={onClose}>取消</Button>
        <Button variant="primary" busy={invite.isPending} onClick={() => invite.mutate()}>生成链接</Button>
      </>}>
      {!invite.isSuccess ? (
        <>
          <Field label="角色" hint={ROLE_HINT[role]}>
            <Select value={role} onChange={(r) => setRole(r as Role)} label="角色" options={roles.map((r) => ({ value: r, label: ROLE_LABEL[r] }))} />
          </Field>
          <Field label="只允许这个邮箱接受（可选）" htmlFor="invite-email" hint="留空则任何拿到链接的人都能用它加入。">
            <input id="invite-email" className="input" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="name@example.com" />
          </Field>
        </>
      ) : (
        <div className="command">
          <code>{invite.data.url}</code>
          <button type="button" className="icon-btn" aria-label="复制链接" onClick={() => void navigator.clipboard.writeText(invite.data.url).then(() => setCopied(true))}>
            {copied ? <Check {...ICON} /> : <Copy {...ICON} />}
          </button>
        </div>
      )}
      {invite.error && <p className="field-error" role="alert">{invite.error.message}</p>}
    </Dialog>
  );
}

/** /invite#token: see what it leads to, pick which signed-in account accepts it. */
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

