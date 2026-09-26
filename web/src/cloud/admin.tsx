// The admin's console at /admin: every user and workspace in ember cloud, and
// the invite codes that let a new person create a workspace. Only the admin's
// account reaches it (ember cloud answers 404 to everyone else, and so does
// this page). It is an operator's tool: each page reads when it opens and
// after each action, nothing more.
import { ArrowLeft, Copy, Plus, Ticket, Users, Boxes } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Navigate, NavLink, Route, Routes } from "react-router";
import { Lockup } from "../brand.tsx";
import { timeUntil } from "../format.ts";
import { useToast } from "../toast.tsx";
import { Button, Confirm, CopyCommand, Dialog, Field, IconButton, Loading, MobileBack, Pill, ResizeHandle, Section, Select, StatusDot, Time, ICON, type Tone } from "../ui.tsx";
import { useAccounts, type Account } from "./accounts.ts";
import { admin, useAction, type Admission, type AdminUser, type AdminWorkspace, type InviteCodeView } from "./api.ts";
import { Avatar } from "./gate.tsx";
import { ROLE_LABEL } from "./settings.tsx";

// Each account is asked once per page load whether it is the admin.
const probes = new Map<string, Promise<boolean>>();

/** The signed-in account that is ember's admin: null when none is, undefined until known. */
export function useAdminAccount(): Account | null | undefined {
  const list = useAccounts();
  const [known, setKnown] = useState<Record<string, boolean>>({});
  useEffect(() => {
    let current = true;
    for (const account of list ?? []) {
      if (!probes.has(account.sub)) probes.set(account.sub, admin.me(account.sub).then(() => true, () => false));
      void probes.get(account.sub)!.then((yes) => { if (current) setKnown((k) => (k[account.sub] === yes ? k : { ...k, [account.sub]: yes })); });
    }
    return () => { current = false; };
  }, [list]);
  if (!list) return undefined;
  return list.find((a) => known[a.sub]) ?? (list.every((a) => a.sub in known) ? null : undefined);
}

export function AdminConsole() {
  const account = useAdminAccount();
  if (account === undefined) return <div className="gate"><Loading /></div>;
  if (!account) return <Navigate to="/" replace />;
  return (
    <div className="shell" data-detail="true">
      <nav className="sidebar" aria-label="管理后台">
        <ResizeHandle variable="--sidebar-w" edge="right" min={180} max={480} label="调整侧边栏宽度" />
        <div className="brand brand-compact"><Lockup /></div>
        <div className="nav-scroll">
          <NavLink className="nav-row" to="/" end><ArrowLeft {...ICON} />返回 ember</NavLink>
          <div className="nav-heading">管理后台 · {account.email}</div>
          <NavLink className="nav-row" to="/admin/users"><Users {...ICON} />用户</NavLink>
          <NavLink className="nav-row" to="/admin/workspaces"><Boxes {...ICON} />Workspace</NavLink>
          <NavLink className="nav-row" to="/admin/codes"><Ticket {...ICON} />邀请码</NavLink>
        </div>
      </nav>
      <main className="main">
        <Routes>
          <Route index element={<Navigate to="users" replace />} />
          <Route path="users" element={<UsersPage account={account} />} />
          <Route path="workspaces" element={<WorkspacesPage account={account} />} />
          <Route path="codes" element={<CodesPage account={account} />} />
          <Route path="*" element={<Navigate to="/admin" replace />} />
        </Routes>
      </main>
    </div>
  );
}

/** A read on open, again on `reload`; what was read stays in view while it reads again. */
function useRead<T>(read: () => Promise<T>): { data: T | undefined; error: Error | null; reload(): void } {
  const [state, setState] = useState<{ data: T | undefined; error: Error | null }>({ data: undefined, error: null });
  const reload = useCallback(() => {
    read().then((data) => setState({ data, error: null }), (error: Error) => setState((s) => ({ data: s.data, error })));
  }, [read]);
  useEffect(reload, [reload]);
  return { ...state, reload };
}

function Page({ title, lead, children }: { title: string; lead?: string | undefined; children: React.ReactNode }) {
  return (
    <div className="page page-narrow">
      <MobileBack to="/" label="返回" />
      <header className="page-head"><div><h1>{title}</h1>{lead && <p className="page-sub">{lead}</p>}</div></header>
      {children}
    </div>
  );
}

function Failed({ error }: { error: Error | null }) {
  return error ? <p className="field-error" role="alert">读取失败：{error.message}</p> : null;
}

// ── users ───────────────────────────────────────────────────────────────

const ADMISSION: Record<Admission | "none", { label: string; tone: Tone }> = {
  admin: { label: "ember 管理员", tone: "accent" },
  code: { label: "用邀请码加入", tone: "blue" },
  invitation: { label: "被邀请加入", tone: "green" },
  early: { label: "邀请码之前加入", tone: "neutral" },
  none: { label: "还没进来", tone: "amber" },
};

function UsersPage({ account }: { account: Account }) {
  const users = useRead(useCallback(() => admin.users(account.sub), [account.sub]));
  const list = users.data;
  return (
    <Page title="用户" lead={list && `${list.length} 人登录过 ember。「还没进来」的人登录了，但没有 workspace，也没有用过邀请码或接受过邀请。`}>
      <Failed error={users.error} />
      {!list ? !users.error && <Loading label="正在读取…" fill={false} /> : (
        <ul className="admin-list">{list.map((u) => <UserItem key={u.sub} user={u} />)}</ul>
      )}
    </Page>
  );
}

function UserItem({ user }: { user: AdminUser }) {
  const admission = ADMISSION[user.admission ?? "none"];
  return (
    <li className="admin-item">
      <div className="admin-head">
        <Avatar account={user} size={32} />
        <span className="list-row-text">
          <span className="list-row-title">{user.name || user.email}</span>
          <span className="muted">{user.email}</span>
        </span>
        <Pill tone={admission.tone}>{admission.label}</Pill>
      </div>
      <p className="admin-meta muted">
        <Time at={user.created_at * 1000} />首次登录 · {user.last_seen ? <><Time at={user.last_seen * 1000} />来过</> : "还没有来访记录"}
      </p>
      {user.workspaces.length > 0 && (
        <div className="chips">{user.workspaces.map((w) => <span key={w.id} className="chip">{w.name} · {ROLE_LABEL[w.role]}</span>)}</div>
      )}
    </li>
  );
}

// ── workspaces ──────────────────────────────────────────────────────────

function WorkspacesPage({ account }: { account: Account }) {
  const workspaces = useRead(useCallback(() => admin.workspaces(account.sub), [account.sub]));
  const list = workspaces.data;
  const online = list?.reduce((n, w) => n + w.stations.filter((s) => s.online).length, 0) ?? 0;
  const stations = list?.reduce((n, w) => n + w.stations.length, 0) ?? 0;
  return (
    <Page title="Workspace" lead={list && `${list.length} 个 workspace，${stations} 台 station（${online} 台在线）。`}>
      <Failed error={workspaces.error} />
      {!list ? !workspaces.error && <Loading label="正在读取…" fill={false} /> : (
        <ul className="admin-list">{list.map((w) => <WorkspaceItem key={w.id} workspace={w} />)}</ul>
      )}
    </Page>
  );
}

function WorkspaceItem({ workspace: w }: { workspace: AdminWorkspace }) {
  return (
    <li className="admin-item">
      <div className="admin-head">
        <span className="list-row-text">
          <span className="list-row-title">{w.name}</span>
          <span className="muted">{w.created_by ? w.created_by.name || w.created_by.email : "已不在的人"} 创建于 <Time at={w.created_at * 1000} /> · <span className="mono">{w.id}</span></span>
        </span>
      </div>
      <div className="admin-group">
        <div className="admin-group-label">成员 {w.members.length}</div>
        {w.members.map((m) => (
          <div key={m.sub} className="admin-line">
            <Avatar account={m} size={20} />
            <span className="admin-line-text">{m.name || m.email}<span className="muted">{m.name ? m.email : ""}</span></span>
            <span className="muted">{ROLE_LABEL[m.role]}</span>
          </div>
        ))}
      </div>
      <div className="admin-group">
        <div className="admin-group-label">Station {w.stations.length}</div>
        {w.stations.length === 0 && <div className="admin-line muted">还没有 station</div>}
        {w.stations.map((s) => (
          <div key={s.id} className="admin-line">
            <StatusDot state={s.online ? "online" : "offline"} label={s.online ? "在线" : "离线"} />
            <span className="admin-line-text">{s.name}<span className="muted">{s.version ? `ember-mesh ${s.version}` : ""}</span></span>
            <span className="muted">{s.online ? "在线" : s.last_seen ? <><Time at={s.last_seen * 1000} />在线</> : "还没上线"}</span>
          </div>
        ))}
      </div>
      {w.invitations.length > 0 && (
        <div className="admin-group">
          <div className="admin-group-label">未接受的邀请 {w.invitations.length}</div>
          {w.invitations.map((i) => (
            <div key={i.id} className="admin-line">
              <span className="admin-line-text">{i.email ?? "任何拿到链接的人"}<span className="muted">{i.inviter ? `${i.inviter} 邀请` : ""}</span></span>
              <span className="muted">{ROLE_LABEL[i.role]} · {timeUntil(i.expires_at * 1000)}过期</span>
            </div>
          ))}
        </div>
      )}
    </li>
  );
}

// ── invite codes ────────────────────────────────────────────────────────

const inviteUrl = (code: string) => `${location.origin}/?invite=${code}`;

function codeState(c: InviteCodeView): { label: string; tone: Tone } {
  if (c.used_by || c.used_at) return { label: "已使用", tone: "neutral" };
  if (c.revoked_at) return { label: "已撤回", tone: "red" };
  if (c.expires_at * 1000 <= Date.now()) return { label: "已过期", tone: "amber" };
  return { label: "可用", tone: "green" };
}

function CodesPage({ account }: { account: Account }) {
  const toast = useToast();
  const codes = useRead(useCallback(() => admin.codes(account.sub), [account.sub]));
  const [making, setMaking] = useState(false);
  const [revoking, setRevoking] = useState<InviteCodeView | null>(null);
  const revoke = useAction((c: InviteCodeView) => admin.revokeCode(account.sub, c.code), () => { setRevoking(null); toast("已撤回邀请码"); codes.reload(); });
  const list = codes.data;
  const usable = list?.filter((c) => codeState(c).label === "可用").length ?? 0;
  const copy = (code: string) => void navigator.clipboard.writeText(inviteUrl(code)).then(() => toast("已复制注册链接"));
  return (
    <Page title="邀请码" lead="ember 只对受邀的人开放。没被邀请进任何 workspace 的人，要有邀请码才能新建 workspace；一个邀请码只能用一次，用过的人之后可以再建。">
      <Section title={list ? `${list.length} 个，${usable} 个可用` : "邀请码"} actions={<Button icon={Plus} variant="primary" onClick={() => setMaking(true)}>生成邀请码</Button>}>
        <Failed error={codes.error} />
        {!list ? !codes.error && <Loading label="正在读取…" fill={false} /> : list.length === 0 ? (
          <div className="admin-item"><p className="muted admin-meta">还没有邀请码。</p></div>
        ) : (
          <ul className="admin-list">
            {list.map((c) => {
              const state = codeState(c);
              return (
                <li key={c.code} className="admin-item">
                  <div className="admin-head">
                    <span className="list-row-text">
                      <span className="list-row-title"><span className="mono admin-code">{c.code}</span>{c.note && <span className="admin-note">{c.note}</span>}</span>
                      <span className="muted">
                        <Time at={c.created_at * 1000} />生成 · {c.used_at ? <>
                          {c.used_by ? c.used_by.name || c.used_by.email : "已不在的人"} <Time at={c.used_at * 1000} />用它建了{c.workspace ? `「${c.workspace.name}」` : " workspace（已删除）"}
                        </> : c.revoked_at ? <><Time at={c.revoked_at * 1000} />撤回</> : state.label === "已过期" ? <><Time at={c.expires_at * 1000} />过期</> : `${timeUntil(c.expires_at * 1000)}过期`}
                      </span>
                    </span>
                    <Pill tone={state.tone}>{state.label}</Pill>
                    {state.label === "可用" && <>
                      <IconButton label="复制注册链接" icon={Copy} onClick={() => copy(c.code)} />
                      <Button variant="ghost" onClick={() => setRevoking(c)}>撤回</Button>
                    </>}
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </Section>
      {making && <NewCodeDialog account={account} onMade={codes.reload} onClose={() => setMaking(false)} />}
      <Confirm open={revoking !== null} onClose={() => setRevoking(null)} busy={revoke.busy} onConfirm={() => revoking && revoke.run(revoking)}
        title={`撤回 ${revoking?.code ?? ""}？`} action="撤回邀请码"
        description={revoke.error?.message ?? "撤回后这个邀请码就不能再用来新建 workspace 了。已经发出去的注册链接也会失效。"} />
    </Page>
  );
}

const DAYS = [7, 14, 30, 90];

function NewCodeDialog({ account, onMade, onClose }: { account: Account; onMade(): void; onClose(): void }) {
  const [note, setNote] = useState("");
  const [days, setDays] = useState("14");
  const make = useAction(() => admin.createCode(account.sub, note, Number(days)), onMade);
  const made = make.result;
  return (
    <Dialog open onClose={onClose} wide title={made ? "邀请码已生成" : "生成邀请码"}
      description={made ? `把邀请码或注册链接发给对方。只能用一次，${timeUntil(made.expires_at * 1000)}过期。` : "对方登录 ember 后，用它建一个自己的 workspace。一个邀请码只能用一次。"}
      footer={made ? <Button variant="primary" onClick={onClose}>完成</Button> : <>
        <Button variant="ghost" onClick={onClose}>取消</Button>
        <Button variant="primary" busy={make.busy} onClick={() => make.run()}>生成</Button>
      </>}>
      {made ? (
        <>
          <Field label="邀请码"><CopyCommand text={made.code} /></Field>
          <Field label="注册链接" hint="打开这个链接登录，新建 workspace 时邀请码会自动填好。"><CopyCommand text={made.url} /></Field>
        </>
      ) : (
        <>
          <Field label="备注" htmlFor="code-note" hint="可选：给谁的，方便之后认出来。">
            <input id="code-note" className="input" value={note} autoFocus maxLength={200} onChange={(e) => setNote(e.target.value)} placeholder="例如：给 Cue 团队的小王"
              onKeyDown={(e) => { if (e.key === "Enter") make.run(); }} />
          </Field>
          <Field label="有效期">
            <Select value={days} onChange={setDays} label="有效期" options={DAYS.map((d) => ({ value: String(d), label: `${d} 天` }))} />
          </Field>
        </>
      )}
      {make.error && <p className="field-error" role="alert">{make.error.message}</p>}
    </Dialog>
  );
}
