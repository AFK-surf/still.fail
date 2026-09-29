// The admin's console, on its own host: every user and workspace in ember
// cloud, and the invite codes that let a new person create a workspace. Only
// the admin's account reaches it (ember cloud answers 404 to everyone else).
// It is an operator's tool: each page reads when it opens and after each
// action, nothing more.
import { useTopic } from "../core/react.ts";
import { Boxes, Copy, LogOut, Plus, Ticket, Users } from "../icons.tsx";
import { useCallback, useEffect, useState } from "react";
import { Navigate, NavLink, Route, Routes, useLocation } from "react-router";
import { Lockup } from "../brand.tsx";
import { stamp } from "../api.ts";
import { useToast } from "../toast.tsx";
import { About, Button, Confirm, CopyCommand, Dialog, Field, IconButton, Loading, MobileBack, Pill, ResizeHandle, Section, Select, Time, ICON, type Tone } from "../ui.tsx";
import { signOut, useAccounts, type Account } from "../cloud/accounts.ts";
import { admin, useAction, type Admission, type AdminUser, type AdminWorkspace, type InviteCodeView } from "../cloud/api.ts";
import { Avatar } from "../cloud/gate.tsx";
import { ROLE_LABEL } from "../cloud/settings.tsx";
import * as nav from "../Sidebar.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./console.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as controlsCss from "../styles/controls.css.ts";

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

// On a phone the sidebar and a page take turns: "/" is the sidebar there, and the users page elsewhere.
const narrow = () => matchMedia("(max-width: 700px)").matches;

export function Console({ account }: { account: Account }) {
  const atIndex = useLocation().pathname === "/";
  return (
    <div className={shellCss.shell} data-detail={!atIndex}>
      <nav className={nav.sidebar} aria-label="管理后台">
        <ResizeHandle variable="--sidebar-w" edge="right" min={180} max={480} label="调整侧边栏宽度" />
        <div className={`${nav.brand} ${nav.brandCompact}`}><Lockup /></div>
        <div className={nav.navScroll}>
          <div className={nav.navHeading}>管理后台</div>
          <NavLink className={nav.navRow} to="/users"><Users {...ICON} />用户</NavLink>
          <NavLink className={nav.navRow} to="/workspaces"><Boxes {...ICON} />Workspace</NavLink>
          <NavLink className={nav.navRow} to="/codes"><Ticket {...ICON} />邀请码</NavLink>
        </div>
        <div className={`${nav.navFootRow} ${css.adminFoot}`}>
          <span className={css.adminAccount}><Avatar account={account} size={20} /><span className={css.accountEmail}>{account.email}</span></span>
          <IconButton label="退出登录" icon={LogOut} onClick={() => void signOut(account.sub)} />
        </div>
      </nav>
      <main className={shellCss.main}>
        <Routes>
          <Route index element={narrow() ? null : <Navigate to="/users" replace />} />
          <Route path="users" element={<UsersPage account={account} />} />
          <Route path="workspaces" element={<WorkspacesPage account={account} />} />
          <Route path="codes" element={<CodesPage account={account} />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
    </div>
  );
}

/** A read on open, again on `reload`; what was read stays in view while it reads again. */
/** One of ember cloud's operator lists, as a topic of the core (read again after a write through it). */
function useList<T>(account: string, list: "users" | "workspaces" | "invite-codes", pick: (value: Record<string, unknown>) => T): { data: T | undefined; error: Error | null } {
  const topic = useTopic<Record<string, unknown>>({ topic: "admin", account, list });
  return { data: topic.value ? pick(topic.value) : undefined, error: topic.error ? new Error(topic.error.message) : null };
}

function Page({ title, lead, children }: { title: string; lead?: string | undefined; children: React.ReactNode }) {
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to="/" label="管理后台" />
      <header className={pagesCss.pageHead}><div><h1>{title}{lead && <About>{lead}</About>}</h1></div></header>
      {children}
    </div>
  );
}

function Failed({ error }: { error: Error | null }) {
  return error ? <p className={controlsCss.fieldError} role="alert">读取失败：{error.message}</p> : null;
}

// ── users ───────────────────────────────────────────────────────────────

const ADMISSION: Record<Admission | "none", { label: string; tone: Tone }> = {
  admin: { label: "still.fail 管理员", tone: "accent" },
  code: { label: "用邀请码加入", tone: "blue" },
  invitation: { label: "被邀请加入", tone: "green" },
  early: { label: "邀请码之前加入", tone: "neutral" },
  none: { label: "还没进来", tone: "amber" },
};

function UsersPage({ account }: { account: Account }) {
  const users = useList(account.sub, "users", (v) => v.users as AdminUser[]);
  const list = users.data;
  return (
    <Page title="用户" lead={list && `${list.length} 人登录过 still.fail。「还没进来」的人登录了，但没有 workspace，也没有用过邀请码或接受过邀请。`}>
      <Failed error={users.error} />
      {!list ? !users.error && <Loading label="正在读取…" fill={false} /> : (
        <ul className={css.adminList}>{list.map((u) => <UserItem key={u.sub} user={u} />)}</ul>
      )}
    </Page>
  );
}

function UserItem({ user }: { user: AdminUser }) {
  const admission = ADMISSION[user.admission ?? "none"];
  return (
    <li className={css.adminItem}>
      <div className={css.adminHead}>
        <Avatar account={user} size={32} />
        <span className={pagesCss.listRowText}>
          <span className={pagesCss.listRowTitle}>{user.name || user.email}</span>
          <span className={shellCss.muted}>{user.email}</span>
        </span>
        <Pill tone={admission.tone}>{admission.label}</Pill>
      </div>
      <p className={`${css.adminMeta} ${shellCss.muted}`}>
        <Time stamp={stamp(user, "created_at")} />首次登录 · {user.last_seen ? <><Time stamp={stamp(user, "last_seen")} />来过</> : "还没有来访记录"}
      </p>
      {user.workspaces.length > 0 && (
        <div className={css.chips}>{user.workspaces.map((w) => <span key={w.id} className={css.chip}>{w.name} · {ROLE_LABEL[w.role]}</span>)}</div>
      )}
    </li>
  );
}

// ── workspaces ──────────────────────────────────────────────────────────

function WorkspacesPage({ account }: { account: Account }) {
  const workspaces = useList(account.sub, "workspaces", (v) => v.workspaces as AdminWorkspace[]);
  const list = workspaces.data;
  const stations = list?.reduce((n, w) => n + w.stations.length, 0) ?? 0;
  return (
    <Page title="Workspace" lead={list && `${list.length} 个 workspace，${stations} 台 station。`}>
      <Failed error={workspaces.error} />
      {!list ? !workspaces.error && <Loading label="正在读取…" fill={false} /> : (
        <ul className={css.adminList}>{list.map((w) => <WorkspaceItem key={w.id} workspace={w} />)}</ul>
      )}
    </Page>
  );
}

function WorkspaceItem({ workspace: w }: { workspace: AdminWorkspace }) {
  return (
    <li className={css.adminItem}>
      <div className={css.adminHead}>
        <span className={pagesCss.listRowText}>
          <span className={pagesCss.listRowTitle}>{w.name}</span>
          <span className={shellCss.muted}>{w.created_by ? w.created_by.name || w.created_by.email : "已不在的人"} 创建于 <Time stamp={stamp(w, "created_at")} /> · <span className={shellCss.mono}>{w.id}</span></span>
        </span>
      </div>
      <div className={css.adminGroup}>
        <div className={css.adminGroupLabel}>成员 {w.members.length}</div>
        {w.members.map((m) => (
          <div key={m.sub} className={css.adminLine}>
            <Avatar account={m} size={20} />
            <span className={css.adminLineText}>{m.name || m.email}<span className={shellCss.muted}>{m.name ? m.email : ""}</span></span>
            <span className={shellCss.muted}>{ROLE_LABEL[m.role]}</span>
          </div>
        ))}
      </div>
      <div className={css.adminGroup}>
        <div className={css.adminGroupLabel}>Station {w.stations.length}</div>
        {w.stations.length === 0 && <div className={`${css.adminLine} ${shellCss.muted}`}>还没有 station</div>}
        {w.stations.map((s) => (
          // Whether a station is up is for the devices to find out over the mesh; ember cloud only knows when it last
          // came to it (or left).
          <div key={s.id} className={css.adminLine}>
            <span className={css.adminLineText}>{s.name}<span className={shellCss.muted}>{s.version ? `ember-mesh ${s.version}` : ""}</span></span>
            <span className={shellCss.muted}>{s.last_seen ? <>上次连 still.fail cloud：<Time stamp={stamp(s, "last_seen")} /></> : "还没连过 still.fail cloud"}</span>
          </div>
        ))}
      </div>
      {w.invitations.length > 0 && (
        <div className={css.adminGroup}>
          <div className={css.adminGroupLabel}>未接受的邀请 {w.invitations.length}</div>
          {w.invitations.map((i) => (
            <div key={i.id} className={css.adminLine}>
              <span className={css.adminLineText}>{i.email ?? "任何拿到链接的人"}<span className={shellCss.muted}>{i.inviter ? `${i.inviter} 邀请` : ""}</span></span>
              <span className={shellCss.muted}>{ROLE_LABEL[i.role]} · {stamp(i, "expires_at")?.until}过期</span>
            </div>
          ))}
        </div>
      )}
    </li>
  );
}

// ── invite codes ────────────────────────────────────────────────────────

function codeState(c: InviteCodeView): { label: string; tone: Tone } {
  if (c.used_by || c.used_at) return { label: "已使用", tone: "neutral" };
  if (c.revoked_at) return { label: "已撤回", tone: "red" };
  if (stamp(c, "expires_at")?.past) return { label: "已过期", tone: "amber" };
  return { label: "可用", tone: "green" };
}

function CodesPage({ account }: { account: Account }) {
  const toast = useToast();
  const codes = useList(account.sub, "invite-codes", (v) => v.codes as (InviteCodeView & { url: string })[]);
  const [making, setMaking] = useState(false);
  const [revoking, setRevoking] = useState<InviteCodeView | null>(null);
  const revoke = useAction((c: InviteCodeView) => admin.revokeCode(account.sub, c.code), () => { setRevoking(null); toast("已撤回邀请码"); });
  const list = codes.data;
  const usable = list?.filter((c) => codeState(c).label === "可用").length ?? 0;
  const copy = (url: string) => void navigator.clipboard.writeText(url).then(() => toast("已复制注册链接"));
  return (
    <Page title="邀请码" lead="still.fail 只对受邀的人开放。没被邀请进任何 workspace 的人，要有邀请码才能新建 workspace；一个邀请码只能用一次，用过的人之后可以再建。">
      <Section title={list ? `${list.length} 个，${usable} 个可用` : "邀请码"} actions={<Button icon={Plus} variant="primary" onClick={() => setMaking(true)}>生成邀请码</Button>}>
        <Failed error={codes.error} />
        {!list ? !codes.error && <Loading label="正在读取…" fill={false} /> : list.length === 0 ? (
          <div className={css.adminItem}><p className={`${shellCss.muted} ${css.adminMeta}`}>还没有邀请码。</p></div>
        ) : (
          <ul className={css.adminList}>
            {list.map((c) => {
              const state = codeState(c);
              return (
                <li key={c.code} className={css.adminItem}>
                  <div className={css.adminHead}>
                    <span className={pagesCss.listRowText}>
                      <span className={pagesCss.listRowTitle}><span className={`${shellCss.mono} ${css.adminCode}`}>{c.code}</span>{c.note && <span className={css.adminNote}>{c.note}</span>}</span>
                      <span className={shellCss.muted}>
                        <Time stamp={stamp(c, "created_at")} />生成 · {c.used_at ? <>
                          {c.used_by ? c.used_by.name || c.used_by.email : "已不在的人"} <Time stamp={stamp(c, "used_at")} />用它建了{c.workspace ? `「${c.workspace.name}」` : " workspace（已删除）"}
                        </> : c.revoked_at ? <><Time stamp={stamp(c, "revoked_at")} />撤回</> : state.label === "已过期" ? <><Time stamp={stamp(c, "expires_at")} />过期</> : `${stamp(c, "expires_at")?.until}过期`}
                      </span>
                    </span>
                    <Pill tone={state.tone}>{state.label}</Pill>
                    {state.label === "可用" && <>
                      <IconButton label="复制注册链接" icon={Copy} onClick={() => copy(c.url)} />
                      <Button variant="ghost" onClick={() => setRevoking(c)}>撤回</Button>
                    </>}
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </Section>
      {making && <NewCodeDialog account={account} onMade={() => {}} onClose={() => setMaking(false)} />}
      <Confirm open={revoking !== null} onClose={() => setRevoking(null)} busy={revoke.busy} onConfirm={() => revoking && revoke.run(revoking)}
        title={`撤回 ${revoking?.code ?? ""}？`} action="撤回邀请码"
        description="撤回后这个邀请码就不能再用来新建 workspace 了。已经发出去的注册链接也会失效。" error={revoke.error?.message} />
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
      description={made ? `把邀请码或注册链接发给对方。只能用一次，${days} 天后过期。` : "对方登录 still.fail 后，用它建一个自己的 workspace。一个邀请码只能用一次。"}
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
            <input id="code-note" className={controlsCss.input} value={note} autoFocus maxLength={200} onChange={(e) => setNote(e.target.value)} placeholder="例如：给产品团队的小王"
              onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) make.run(); }} />
          </Field>
          <Field label="有效期">
            <Select value={days} onChange={setDays} label="有效期" options={DAYS.map((d) => ({ value: String(d), label: `${d} 天` }))} />
          </Field>
        </>
      )}
      {make.error && <p className={controlsCss.fieldError} role="alert">{make.error.message}</p>}
    </Dialog>
  );
}
