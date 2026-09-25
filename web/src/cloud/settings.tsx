// Settings in ember cloud, in two parts: the account the current workspace
// is reached through (who you are, where you are signed in), and the
// workspace itself (its name, members, stations, connects and the stations'
// runtime accounts).
import { useMutation, useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { ArrowLeft, Check, Copy, KeyRound, LogOut, Plug, Plus, Server, Settings2, Trash2, UserPlus, Users } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { Link, NavLink, useNavigate } from "react-router";
import { keys, makeApi } from "../api.ts";
import { ConnectList } from "../pages/Connects.tsx";
import { ACCESS, checkTone, relativeTime, RUNTIME_LABEL, timeUntil } from "../format.ts";
import { QuotaBars } from "../components.tsx";
import type { Station } from "../station.tsx";
import { useToast } from "../toast.tsx";
import { Button, Confirm, Loading, CopyCommand, Dialog, Empty, Field, ICON, Menu, MobileBack, Pill, Section, Select, StatusDot } from "../ui.tsx";
import { accessToken, signOut, type Account } from "./accounts.ts";
import { cloud, type Role, type StationView, type WorkspaceView } from "./api.ts";
import { Avatar, online } from "./gate.tsx";
import type { WorkspaceEntry } from "./workspace.tsx";

export const ROLE_LABEL: Record<Role, string> = { owner: "Owner", admin: "管理员", member: "成员" };
const ROLE_HINT: Record<Role, string> = {
  owner: "管理一切，包括成员角色和删除 workspace",
  admin: "邀请成员、添加和移除 station",
  member: "使用 workspace 里的 station",
};


export function useWorkspaceView(entry: WorkspaceEntry) {
  return useQuery({
    queryKey: ["cloud", "workspace", entry.id, entry.account.sub],
    queryFn: () => cloud.workspace(entry.account.sub, entry.id),
    refetchInterval: 30_000,
  });
}

/** The sidebar while in settings. */
export function SettingsNav({ entry }: { entry: WorkspaceEntry }) {
  const base = `/w/${entry.id}/settings`;
  return (
    <div className="nav-scroll">
      <NavLink className="nav-row" to={`/w/${entry.id}`} end><ArrowLeft {...ICON} />返回会话</NavLink>
      <div className="nav-heading">账号</div>
      <NavLink className="nav-row" to={`${base}/account`}><Avatar account={entry.account} size={18} /><span className="nav-text">{entry.account.email}</span></NavLink>
      <div className="nav-heading">Workspace · {entry.name}</div>
      <NavLink className="nav-row" to={`${base}/general`}><Settings2 {...ICON} />通用</NavLink>
      <NavLink className="nav-row" to={`${base}/members`}><Users {...ICON} />成员</NavLink>
      <NavLink className="nav-row" to={`${base}/stations`}><Server {...ICON} />Station</NavLink>
      <NavLink className="nav-row" to={`${base}/connects`}><Plug {...ICON} />连接</NavLink>
      <NavLink className="nav-row" to={`${base}/profiles`}><KeyRound {...ICON} />Profile</NavLink>
    </div>
  );
}

function Page({ title, lead, back, children }: { title: string; lead?: string; back: string; children: React.ReactNode }) {
  return (
    <div className="page page-narrow">
      <MobileBack to={back} label="设置" />
      <header className="page-head"><div><h1>{title}</h1>{lead && <p className="page-sub">{lead}</p>}</div></header>
      {children}
    </div>
  );
}

// ── account ─────────────────────────────────────────────────────────────

interface LoginSession { id: string; name: string; created_at: number; expires_at: number; current: boolean }

export function AccountSettings({ entry }: { entry: WorkspaceEntry }) {
  const account = entry.account;
  const navigate = useNavigate();
  const toast = useToast();
  const queries = useQueryClient();
  const sessions = useQuery({
    queryKey: ["cloud", "login-sessions", account.sub],
    queryFn: async () => {
      const r = await fetch("/v1/auth/sessions", { headers: { authorization: `Bearer ${await accessToken(account.sub)}` } });
      if (!r.ok) throw new Error(`读不到登录记录（${r.status}）`);
      return ((await r.json()) as { sessions: LoginSession[] }).sessions;
    },
  });
  const revoke = useMutation({
    mutationFn: async (id: string) => {
      const r = await fetch(`/v1/auth/sessions/${id}`, { method: "DELETE", headers: { authorization: `Bearer ${await accessToken(account.sub)}` } });
      if (!r.ok) throw new Error(`没能退出（${r.status}）`);
    },
    onSuccess: () => { toast("已让那台设备退出"); void queries.invalidateQueries({ queryKey: ["cloud", "login-sessions", account.sub] }); },
  });
  const [leaving, setLeaving] = useState(false);
  return (
    <div className="page page-narrow">
      <MobileBack to={`/w/${entry.id}/settings`} label="设置" />
      <header className="identity">
        <Avatar account={account} size={52} />
        <div className="identity-text">
          <h1 className="identity-name">{account.name || account.email}</h1>
          <p className="identity-sub"><span>{account.email}</span><span>Google 账号</span></p>
        </div>
        <Button icon={LogOut} onClick={() => setLeaving(true)}>退出这个账号</Button>
      </header>
      <Section title="登录的地方" description="这个账号在哪些浏览器或设备上登录了 ember。认不出来的可以让它退出。">
        {sessions.isPending ? <Loading label="正在读取…" fill={false} /> : sessions.isError ? <p className="field-error">{sessions.error.message}</p> : (
          <ul className="list">
            {sessions.data.map((s) => (
              <li key={s.id} className="list-row">
                <span className="list-row-text">
                  <span className="list-row-title">{s.name || "未命名设备"}{s.current && <span className="choice-badge">这里</span>}</span>
                  <span className="muted">{relativeTime(s.created_at * 1000)}登录 · {timeUntil(s.expires_at * 1000)}过期</span>
                </span>
                {!s.current && <Button variant="ghost" busy={revoke.isPending && revoke.variables === s.id} onClick={() => revoke.mutate(s.id)}>退出</Button>}
              </li>
            ))}
          </ul>
        )}
      </Section>
      <Confirm open={leaving} onClose={() => setLeaving(false)} onConfirm={() => void signOut(account.sub).then(() => { toast(`已退出 ${account.email}`); navigate("/"); })}
        title={`退出 ${account.email}？`} action="退出账号" description="这个浏览器上不再使用这个账号；它所在的 workspace 也会从这里消失。其他已登录的账号不受影响。" />
    </div>
  );
}

// ── workspace ───────────────────────────────────────────────────────────

function useWorkspace(entry: WorkspaceEntry): { view: WorkspaceView | undefined; manager: boolean; pending: boolean; error: Error | null } {
  const q = useWorkspaceView(entry);
  return { view: q.data, manager: q.data?.role === "owner" || q.data?.role === "admin", pending: q.isPending, error: q.error };
}

export function GeneralSettings({ entry }: { entry: WorkspaceEntry }) {
  const { view, manager } = useWorkspace(entry);
  const account = entry.account;
  const queries = useQueryClient();
  const navigate = useNavigate();
  const toast = useToast();
  const [name, setName] = useState("");
  useEffect(() => { if (view) setName(view.name); }, [view?.name]);
  const refresh = () => void queries.invalidateQueries({ queryKey: ["cloud"] });
  const [leaving, setLeaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const rename = useMutation({ mutationFn: () => cloud.renameWorkspace(account.sub, entry.id, name), onSuccess: () => { refresh(); toast("已改名"); } });
  const leave = useMutation({ mutationFn: () => cloud.removeMember(account.sub, entry.id, account.sub), onSuccess: () => { refresh(); toast("已退出 workspace"); navigate("/"); } });
  const remove = useMutation({ mutationFn: () => cloud.deleteWorkspace(account.sub, entry.id), onSuccess: () => { refresh(); toast("已删除 workspace"); navigate("/"); } });
  if (!view) return <Loading label="正在读取 workspace…" />;
  return (
    <Page title="通用" back={`/w/${entry.id}/settings`}>
      <Section title="名字">
        <div className="card">
          <Field label="Workspace 名字" htmlFor="ws-rename" hint={manager ? undefined : "只有 owner 和管理员能改名。"}>
            <div className="input-row">
              <input id="ws-rename" className="input" value={name} maxLength={80} disabled={!manager} onChange={(e) => setName(e.target.value)} />
              {manager && <Button variant="primary" disabled={!name.trim() || name.trim() === view.name} busy={rename.isPending} onClick={() => rename.mutate()}>保存</Button>}
            </div>
          </Field>
          <p className="muted card-foot">你在这里是{ROLE_LABEL[view.role]}，通过 {account.email} 访问。</p>
        </div>
      </Section>
      <Section title="离开或删除">
        <div className="card card-row">
          <div className="card-row-text"><strong>退出这个 workspace</strong><span className="muted">退出后不能再访问里面的 station，需要重新被邀请。</span></div>
          <Button onClick={() => setLeaving(true)}>退出</Button>
        </div>
        {view.role === "owner" && (
          <div className="card card-row">
            <div className="card-row-text"><strong>删除 workspace</strong><span className="muted">所有成员失去访问权限，station 断开与 ember cloud 的连接；station 本机的数据不受影响。</span></div>
            <Button variant="danger" icon={Trash2} onClick={() => setDeleting(true)}>删除</Button>
          </div>
        )}
      </Section>
      <Confirm open={leaving} onClose={() => setLeaving(false)} busy={leave.isPending} onConfirm={() => leave.mutate()}
        title={`退出「${view.name}」？`} action="退出" description={leave.error?.message ?? "退出后你就不能再访问里面的 station，需要重新被邀请才能回来。"} />
      <Confirm open={deleting} onClose={() => setDeleting(false)} busy={remove.isPending} onConfirm={() => remove.mutate()}
        title={`删除「${view.name}」？`} action="删除 workspace"
        description={remove.error?.message ?? `所有成员都会失去访问权限，${view.stations.length} 台 station 会断开和 ember cloud 的连接（station 本机上的数据不受影响）。`} />
    </Page>
  );
}

export function MembersSettings({ entry }: { entry: WorkspaceEntry }) {
  const { view, manager } = useWorkspace(entry);
  if (!view) return <Loading label="正在读取 workspace…" />;
  return (
    <Page title="成员" lead="谁能使用这个 workspace 里的 station。" back={`/w/${entry.id}/settings`}>
      <Members view={view} account={entry.account} manager={manager} />
    </Page>
  );
}

export function StationsSettings({ entry }: { entry: WorkspaceEntry }) {
  const { view, manager } = useWorkspace(entry);
  if (!view) return <Loading label="正在读取 workspace…" />;
  return (
    <Page title="Station" lead="每台 station 是一台运行 ember 的机器：它的连接、会话和Profile都在那台机器上。" back={`/w/${entry.id}/settings`}>
      <Stations view={view} account={entry.account} manager={manager} />
    </Page>
  );
}

export function ConnectsSettings({ entry, stations }: { entry: WorkspaceEntry; stations: Station[] }) {
  const live = stations.filter((s) => s.online);
  const overviews = useQueries({ queries: live.map((s) => ({ queryKey: keys.overview(s.id), queryFn: () => makeApi(s.transport).overview(), refetchInterval: 10_000 })) });
  const items = useMemo(() => live.flatMap((station, i) => (overviews[i]?.data?.connects ?? []).map((connect) => ({ connect, station }))), [live, overviews]);
  return <ConnectList items={items} stations={stations} showStation loading={overviews.some((o) => o.isPending)} back={`/w/${entry.id}/settings`} />;
}

export function RuntimeSettings({ entry, stations }: { entry: WorkspaceEntry; stations: Station[] }) {
  const live = stations.filter((s) => s.online);
  const overviews = useQueries({ queries: live.map((s) => ({ queryKey: keys.overview(s.id), queryFn: () => makeApi(s.transport).overview(), refetchInterval: 30_000 })) });
  return (
    <Page title="Profile" lead="每台 station 有自己的 Profile：用哪份订阅、或者接到哪个模型服务来运行 Claude Code 和 Codex。额度每几分钟更新一次。" back={`/w/${entry.id}/settings`}>
      {stations.length === 0 && <Empty><p>还没有 station。</p></Empty>}
      {stations.map((station) => {
        const overview = station.online ? overviews[live.indexOf(station)]?.data : undefined;
        return (
          <Section key={station.id}
            title={<span className="station-heading"><StatusDot state={station.online ? "online" : "offline"} label={station.online ? "在线" : "离线"} />{station.name}</span>}
            actions={station.online && <Link className="btn btn-secondary" to={`${station.base}/settings/accounts`}>管理</Link>}>
            {!station.online ? <div className="card"><p className="muted card-foot">离线，暂时看不到它的 Profile。</p></div>
              : !overview ? <div className="card"><Loading label={`正在连接 ${station.name}…`} fill={false} /></div>
              : overview.profiles.length === 0 ? <div className="card"><p className="muted card-foot">还没有 Profile。</p></div>
              : (
                <ul className="list">
                  {overview.profiles.map((p) => {
                    const tone = checkTone(p.check);
                    return (
                      <li key={p.id}>
                        <Link className="list-row" to={`${station.base}/settings/accounts/${p.id}`}>
                          <span className="list-row-text">
                            <span className="list-row-title">{p.name}</span>
                            <span className="muted">{RUNTIME_LABEL[p.runtime]} · {ACCESS[p.access.kind].label}{p.usedBy.length ? ` · ${p.usedBy.length} 个连接在用` : ""}</span>
                          </span>
                          <QuotaBars quota={p.quota} compact />
                          <Pill tone={tone.tone}>{tone.label}</Pill>
                        </Link>
                      </li>
                    );
                  })}
                </ul>
              )}
          </Section>
        );
      })}
    </Page>
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
    <Section title={`${view.stations.length} 台`} actions={manager && <Button icon={Plus} onClick={() => setAdding(true)}>添加 station</Button>}>
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
              <Link className="btn btn-ghost" to={`/w/${view.id}/s/${s.id}/settings/accounts`}>Profile</Link>
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
    <Section title={`${view.members.length} 人`} actions={manager && <Button icon={UserPlus} onClick={() => setInviting(true)}>邀请成员</Button>}>
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
  const invite = useMutation({ mutationFn: () => cloud.invite(account.sub, view.id, role, email.trim()), onSuccess: () => void queries.invalidateQueries({ queryKey: ["cloud", "workspace"] }) });
  const roles: Role[] = view.role === "owner" ? ["member", "admin", "owner"] : ["member", "admin"];
  const valid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
  return (
    <Dialog open onClose={onClose} title="邀请成员" description={`对方用这个邮箱登录 ember，就会看到加入「${view.name}」的邀请。邀请 7 天内有效。`}
      footer={invite.isSuccess ? <Button variant="primary" onClick={onClose}>完成</Button> : <>
        <Button variant="ghost" onClick={onClose}>取消</Button>
        <Button variant="primary" disabled={!valid} busy={invite.isPending} onClick={() => invite.mutate()}>邀请</Button>
      </>}>
      {!invite.isSuccess ? (
        <>
          <Field label="邮箱" htmlFor="invite-email" hint="对方登录 ember 用的 Google 账号邮箱。">
            <input id="invite-email" className="input" type="email" autoFocus value={email} onChange={(e) => setEmail(e.target.value)} placeholder="name@example.com"
              onKeyDown={(e) => { if (e.key === "Enter" && valid) invite.mutate(); }} />
          </Field>
          <Field label="角色" hint={ROLE_HINT[role]}>
            <Select value={role} onChange={(r) => setRole(r as Role)} label="角色" options={roles.map((r) => ({ value: r, label: ROLE_LABEL[r] }))} />
          </Field>
        </>
      ) : (
        <div className="callout" data-tone="green"><Check {...ICON} /><span>已邀请 {email.trim()}。对方用这个邮箱登录 ember 就能看到邀请并加入。</span></div>
      )}
      {invite.error && <p className="field-error" role="alert">{invite.error.message}</p>}
    </Dialog>
  );
}

/** /invite#token: see what it leads to, pick which signed-in account accepts it. */
