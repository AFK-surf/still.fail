// The admin's console, on its own host: every user and workspace in still.fail cloud, the invite codes that let
// a new person create a workspace, and the bug reports people's agents sent about still.fail. Only the admin's account reaches it (still.fail cloud answers 404 to everyone
// else). The core puts each page together (views/admin.rs: found, filtered, sorted, counted); this draws it. Where
// the page is (a list's words, filter and sort, the item open) is in its URL, so a link shows the same.
import { useTopic } from "../core/react.ts";
import type { CoreError, Topic } from "../core/client.ts";
import { Boxes, ChevronRight, Close, Copy, LogOut, Monitor, Plus, Said, Search, Ticket, Users } from "../icons.tsx";
import { Fragment, useEffect, useRef, useState } from "react";
import { Link, Navigate, NavLink, Route, Routes, useLocation, useNavigate, useParams, useSearchParams } from "react-router";
import { Lockup } from "../brand.tsx";
import { stamp, type Stamp } from "../api.ts";
import { useToast } from "../toast.tsx";
import { Button, Confirm, CopyCommand, Dialog, Field, IconButton, Loading, MobileBack, Pill, ResizeHandle, Select, StatusDot, Switch, Time, ICON, type Presence, type Tone } from "../ui.tsx";
import { signOut, useAccounts, type Account } from "../cloud/accounts.ts";
import { admin, useAction, type FeedbackStatus } from "../cloud/api.ts";
import { Prose } from "../Prose.tsx";
import { Avatar } from "../cloud/gate.tsx";
import * as nav from "../Sidebar.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./console.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as conversationCss from "../styles/conversation.css.ts";

// Each account is asked once per page load whether it is the admin.
const probes = new Map<string, Promise<boolean>>();

/** The signed-in account that is still.fail's admin: null when none is, undefined until known. */
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

// ── what the core gives (views/admin.rs) ───────────────────────────────

type List = "users" | "workspaces" | "invite-codes" | "feedback";
type Timed = { time?: Record<string, Stamp> };
type Mark = { label: string; tone: Tone };
type PersonLike = { name: string; email: string; picture: string };
type Row = Timed & {
  id: string; title: string; line: string; marks: Mark[]; person?: PersonLike;
  /** A workspace's: how its stations last stood. A code's: open, used, expired, revoked. */
  state?: Presence | string | null; url?: string | null; note?: string;
  /** A bug report's: FB-<number>. */
  number?: string;
};
type ListView = { total: number; found: number; filter: string; filters: { id: string; label: string; count: number }[]; sort: string; sorts: { id: string; label: string }[]; rows: Row[]; more: boolean };
type UserPage = Timed & {
  id: string; title: string; person: PersonLike; email: string; admin: boolean; admission: string; code: string | null;
  mayCreate: boolean | null; mayCreateHint: string; mayCreateFixed: boolean; beta: boolean | null; blocked: boolean | null;
  workspaces: { id: string; name: string; line: string }[];
};
type WorkspacePage = Timed & {
  id: string; title: string; creator: { id: string; title: string } | null; people: string;
  members: (Timed & { id: string; title: string; person: PersonLike; role: string })[];
  stations: (Timed & { id: string; name: string; version: string | null; outdated: boolean; state: Presence })[];
  invitations: (Timed & { id: string; email: string; line: string })[];
};
type FeedbackPage = Timed & {
  id: string; number: string; title: string; body: string; status: FeedbackStatus; statuses: { id: FeedbackStatus; label: string }[];
  marks: Mark[]; channel: string; channelLabel: string; area: string; reporter: string;
  station: { id: string; name: string } | null; workspace: { id: string; title: string } | null; account: { id: string; title: string } | null;
  context: { key: string; value: string }[]; logs: string | null;
  /** All of it as plain text, to hand to an agent. */
  text: string;
};
type Overview = {
  stats: { label: string; value: number; note: string; list: List; filter: string }[];
  weeks: { count: number; label: string }[];
  todo: { text: string; hint: string; tone: string; list: List; filter: string }[];
};

/** A topic of the core; while the next one (other words, say) is read, the last one's value stays in view. */
function useKept<T>(topic: Topic): { value: T | undefined; error: CoreError | null } {
  const state = useTopic<T>(topic);
  const last = useRef<T | undefined>(undefined);
  if (state.value) last.current = state.value;
  return { value: state.value ?? (state.error ? undefined : last.current), error: state.error };
}

const PATH: Record<List, string> = { users: "/users", workspaces: "/workspaces", "invite-codes": "/codes", feedback: "/feedback" };

// On a phone the sidebar and a page take turns: "/" is the sidebar there, and the overview elsewhere.
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
          <NavLink className={nav.navRow} to="/overview"><Monitor {...ICON} />概览</NavLink>
          <NavLink className={nav.navRow} to="/users"><Users {...ICON} />用户</NavLink>
          <NavLink className={nav.navRow} to="/workspaces"><Boxes {...ICON} />Workspace</NavLink>
          <NavLink className={nav.navRow} to="/codes"><Ticket {...ICON} />邀请码</NavLink>
          <NavLink className={nav.navRow} to="/feedback"><Said {...ICON} />反馈</NavLink>
        </div>
        <div className={`${nav.navFootRow} ${css.adminFoot}`}>
          <span className={css.adminAccount}><Avatar account={account} size={20} /><span className={css.accountEmail}>{account.email}</span></span>
          <IconButton label="退出登录" icon={LogOut} onClick={() => void signOut(account.sub)} />
        </div>
      </nav>
      <main className={shellCss.main}>
        <Routes>
          <Route index element={narrow() ? null : <Navigate to="/overview" replace />} />
          <Route path="overview" element={<OverviewPage account={account} />} />
          <Route path="users/:id?" element={<ListPage account={account} list="users" />} />
          <Route path="workspaces/:id?" element={<ListPage account={account} list="workspaces" />} />
          <Route path="codes" element={<ListPage account={account} list="invite-codes" />} />
          <Route path="feedback/:id?" element={<ListPage account={account} list="feedback" />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
    </div>
  );
}

function Failed({ error }: { error: Error | null }) {
  return error ? <p className={controlsCss.fieldError} role="alert">读取失败：{error.message}</p> : null;
}

// ── the overview ────────────────────────────────────────────────────────

function OverviewPage({ account }: { account: Account }) {
  const { value: view, error } = useKept<Overview>({ topic: "adminOverview", account: account.sub });
  const max = Math.max(1, ...(view?.weeks.map((w) => w.count) ?? []));
  return (
    <div className={`${pagesCss.page} ${css.mid}`}>
      <MobileBack to="/" label="管理后台" />
      <header className={pagesCss.pageHead}><div><h1>概览</h1></div></header>
      <Failed error={error} />
      {!view ? !error && <Loading label="正在读取…" fill={false} /> : <>
        <div className={css.stats}>
          {view.stats.map((s) => (
            <Link key={s.label} className={css.stat} to={`${PATH[s.list]}?filter=${s.filter}`}>
              <span className={shellCss.muted}>{s.label}</span>
              <span className={css.statValue}>{s.value}</span>
              <span className={css.statNote}>{s.note}</span>
            </Link>
          ))}
        </div>
        <section className={css.chart} aria-label="每周新用户">
          <div className={css.chartHead}><b>每周新用户</b><span className={shellCss.muted}>近 12 周</span></div>
          <div className={css.bars}>
            {view.weeks.map((w, i) => (
              <div key={i} className={css.bar} title={`${w.label}：${w.count} 人`}>
                <span className={css.barCount}>{w.count || ""}</span>
                <span className={css.barFill} data-now={i === view.weeks.length - 1 || undefined} style={{ height: `${(w.count / max) * 100}%` }} />
                <span className={css.barLabel}>{w.label}</span>
              </div>
            ))}
          </div>
        </section>
        {view.todo.length > 0 && <>
          <h2 className={css.h2}>需要看一眼</h2>
          <div className={css.list}>
            {view.todo.map((t) => (
              <Link key={t.text} className={css.todo} to={`${PATH[t.list]}?filter=${t.filter}`}>
                <StatusDot state={t.tone === "amber" ? "busy" : "offline"} />
                <span className={css.todoText}>{t.text}</span>
                <span className={css.todoHint}>{t.hint}</span>
                <ChevronRight {...ICON} />
              </Link>
            ))}
          </div>
        </>}
      </>}
    </div>
  );
}

// ── the lists ───────────────────────────────────────────────────────────

const TITLE: Record<List, string> = { users: "用户", workspaces: "Workspace", "invite-codes": "邀请码", feedback: "反馈" };
const PLACEHOLDER: Record<List, string> = {
  users: "搜索名字、邮箱、workspace、ID", workspaces: "搜索名字、成员、station、ID", "invite-codes": "搜索邀请码、备注、用的人",
  feedback: "搜索标题、内容、反馈人、station、workspace、FB 编号",
};
const STEP = 50;

function ListPage({ account, list }: { account: Account; list: List }) {
  const { id } = useParams();
  const [params, setParams] = useSearchParams();
  const query = params.get("q") ?? "";
  const filter = params.get("filter") ?? undefined;
  const sort = params.get("sort") ?? undefined;
  const [limit, setLimit] = useState(STEP);
  useEffect(() => setLimit(STEP), [list, query, filter, sort]);
  const { value: view, error } = useKept<ListView>({ topic: "adminList", account: account.sub, list, query, ...(filter ? { filter } : {}), ...(sort ? { sort } : {}), limit });
  const set = (key: string, value: string | null) => setParams((p) => { const next = new URLSearchParams(p); if (value) next.set(key, value); else next.delete(key); return next; }, { replace: true });
  const [making, setMaking] = useState(false);
  const search = params.toString() ? `?${params}` : "";
  const detail = id && list !== "invite-codes";
  return (
    <div className={css.split} data-open={detail || undefined}>
      <div className={`${pagesCss.page} ${css.listPage}`}>
        <MobileBack to="/" label="管理后台" />
        <header className={pagesCss.pageHead}>
          <div><h1>{TITLE[list]}{view && <span className={css.total}>{view.total}</span>}</h1></div>
          {list === "invite-codes" && <Button icon={Plus} variant="primary" onClick={() => setMaking(true)}>生成邀请码</Button>}
        </header>
        <div className={css.toolbar}>
          <label className={css.search}>
            <Search {...ICON} />
            <input className={controlsCss.input} value={query} placeholder={PLACEHOLDER[list]} aria-label="搜索" onChange={(e) => set("q", e.target.value)} />
          </label>
          {view && view.sorts.length > 1 && (
            <label className={css.sort}>
              <span className={shellCss.muted}>按</span>
              <Select value={view.sort} onChange={(v) => set("sort", v === view.sorts[0]!.id ? null : v)} label="排序" options={view.sorts.map((s) => ({ value: s.id, label: s.label }))} />
            </label>
          )}
        </div>
        {view && (
          <div className={css.filters} role="tablist">
            {view.filters.map((f) => (
              <button key={f.id} role="tab" aria-selected={view.filter === f.id} className={css.filter} data-on={view.filter === f.id || undefined}
                onClick={() => set("filter", f.id === "all" ? null : f.id)}>{f.label}<span>{f.count}</span></button>
            ))}
          </div>
        )}
        {/* A still.fail cloud from before bug reports has no such list. */}
        {list === "feedback" && error?.status === 404 ? <p className={css.empty}>这个 still.fail cloud 还不收反馈</p> : <Failed error={error} />}
        {!view ? !error && <Loading label="正在读取…" fill={false} /> : view.rows.length === 0 ? (
          <p className={css.empty}>{query ? "没有找到" : "这里没有"}</p>
        ) : (
          <div className={css.list}>
            {view.rows.map((row) => list === "invite-codes"
              ? <CodeRow key={row.id} account={account} row={row} />
              : <ItemRow key={row.id} list={list} row={row} open={row.id === id} to={`${PATH[list]}/${encodeURIComponent(row.id)}${search}`} />)}
            {view.more && <button className={css.more} onClick={() => setLimit((n) => n + STEP)}>再显示 {Math.min(STEP, view.found - view.rows.length)} 条 · 共 {view.found} 条</button>}
          </div>
        )}
      </div>
      {detail && (list === "users"
        ? <UserDetail key={id} account={account} id={id} close={`${PATH.users}${search}`} search={search} />
        : list === "feedback"
          ? <FeedbackDetail key={id} account={account} id={id} close={`${PATH.feedback}${search}`} />
          : <WorkspaceDetail key={id} account={account} id={id} close={`${PATH.workspaces}${search}`} />)}
      {making && <NewCodeDialog account={account} onClose={() => setMaking(false)} />}
    </div>
  );
}

function Marks({ marks }: { marks: Mark[] }) {
  return <>{marks.map((m) => <Pill key={m.label} tone={m.tone}>{m.label}</Pill>)}</>;
}

/** A user, a workspace or a bug report: two lines, what is off marked, when it was last seen (sent) at the end. */
function ItemRow({ list, row, open, to }: { list: List; row: Row; open: boolean; to: string }) {
  const feedback = list === "feedback";
  return (
    <Link className={css.row} to={open ? to.replace(/\/[^/?]+(\?|$)/, "$1") : to} aria-current={open ? "page" : undefined}>
      {feedback ? null : row.person ? <Avatar account={row.person} size={28} /> : <span className={css.wsMark}>{[...row.title][0]}</span>}
      <span className={css.rowText}>
        <span className={css.rowLine1}>
          {feedback && <span className={`${shellCss.mono} ${shellCss.muted} ${css.fbNumber}`}>{row.number}</span>}
          <b className={feedback ? css.fbTitle : undefined}>{row.title}</b>
          <Marks marks={row.marks} />
          <span className={css.rowTime}>
            {list === "workspaces" && row.state && <StatusDot state={row.state as Presence} />}
            {feedback ? <Time stamp={stamp(row, "created_at")} fixed />
              : stamp(row, "last_seen") ? <Time stamp={stamp(row, "last_seen")} fixed /> : list === "users" ? "没来过" : ""}
          </span>
        </span>
        <span className={css.rowLine2}>{row.line}</span>
      </span>
    </Link>
  );
}

function CodeRow({ account, row }: { account: Account; row: Row }) {
  const toast = useToast();
  const [revoking, setRevoking] = useState(false);
  const revoke = useAction(() => admin.revokeCode(account.sub, row.id), () => { setRevoking(false); toast("已撤回邀请码"); });
  const copy = () => void navigator.clipboard.writeText(row.url ?? "").then(() => toast("已复制注册链接"));
  const at = row.state === "used" ? stamp(row, "used_at") : row.state === "revoked" ? stamp(row, "revoked_at") : stamp(row, "created_at");
  return (
    <div className={css.row} data-static>
      <span className={css.rowText}>
        <span className={css.rowLine1}>
          <b className={`${shellCss.mono} ${css.code}`}>{row.title}</b>
          <Marks marks={row.marks} />
          <span className={css.rowTime}>
            {row.state === "open" ? <>
              <IconButton label="复制注册链接" icon={Copy} onClick={copy} />
              <Button variant="ghost" onClick={() => setRevoking(true)}>撤回</Button>
            </> : <Time stamp={at} fixed />}
          </span>
        </span>
        <span className={css.rowLine2}>{row.line || (row.state === "open" ? `${stamp(row, "expires_at")?.until ?? ""}过期` : "")}</span>
      </span>
      <Confirm open={revoking} onClose={() => setRevoking(false)} busy={revoke.busy} onConfirm={() => revoke.run()}
        title={`撤回 ${row.title}？`} action="撤回邀请码"
        description="撤回后这个邀请码就不能再用来新建 workspace 了。已经发出去的注册链接也会失效。" error={revoke.error?.message} />
    </div>
  );
}

// ── an item's page, beside its list ─────────────────────────────────────

function Detail({ close, head, children }: { close: string; head: React.ReactNode; children: React.ReactNode }) {
  return (
    <aside className={css.detail}>
      <MobileBack to={close} label="返回列表" />
      <div className={css.detailHead}>{head}<Link className={css.close} to={close} aria-label="关闭"><Close {...ICON} /></Link></div>
      {children}
    </aside>
  );
}

function UserDetail({ account, id, close, search }: { account: Account; id: string; close: string; search: string }) {
  const toast = useToast();
  const { value: u, error } = useKept<UserPage>({ topic: "adminItem", account: account.sub, list: "users", id });
  const mayCreate = useAction((on: boolean) => admin.setMayCreate(account.sub, id, on), (_, on) => toast(on ? "已开通，可以新建 workspace" : "已收回新建 workspace 的资格"));
  const beta = useAction((on: boolean) => admin.setBeta(account.sub, id, on), (_, on) => toast(on ? "已开通测试版" : "已关闭测试版"));
  const [blocking, setBlocking] = useState(false);
  const block = useAction((on: boolean) => admin.block(account.sub, id, on), (_, on) => { setBlocking(false); toast(on ? "已封禁" : "已解封"); });
  useEffect(() => { const e = mayCreate.error ?? beta.error; if (e) toast(`没能更改：${e.message}`); }, [mayCreate.error, beta.error, toast]);
  if (!u) return <aside className={css.detail}>{error ? <Failed error={error} /> : <Loading label="正在读取…" fill={false} />}</aside>;
  return (
    <Detail close={close} head={<>
      <Avatar account={u.person} size={40} />
      <span className={css.detailTitle}><b>{u.title}</b><span>{u.email}</span></span>
    </>}>
      <dl className={css.kv}>
        <dt>准入</dt><dd>{u.admission}{u.code && <span className={shellCss.muted}> · <span className={shellCss.mono}>{u.code}</span></span>}</dd>
        <dt>首次登录</dt><dd><Time stamp={stamp(u, "created_at")} /></dd>
        <dt>最近来访</dt><dd>{stamp(u, "last_seen") ? <Time stamp={stamp(u, "last_seen")} /> : "没来过"}</dd>
        <dt>ID</dt><dd className={`${shellCss.mono} ${shellCss.muted}`}>{u.id}</dd>
      </dl>
      <div className={css.group}>Workspace {u.workspaces.length}</div>
      {u.workspaces.length === 0 && <div className={css.line} data-quiet>不在任何 workspace</div>}
      {u.workspaces.map((w) => (
        <Link key={w.id} className={css.line} to={`${PATH.workspaces}/${encodeURIComponent(w.id)}${search}`}>
          <span className={css.grow}>{w.name}</span><span className={css.lineAside}>{w.line}</span><ChevronRight {...ICON} />
        </Link>
      ))}
      {!u.admin && <>
        <div className={css.group}>资格</div>
        {u.mayCreate !== null && (
          <label className={css.line}>
            <span className={css.grow}>可以新建 workspace<span className={css.hint}>{u.mayCreateHint}</span></span>
            <Switch checked={mayCreate.busy ? Boolean(mayCreate.arg) : u.mayCreate} disabled={u.mayCreateFixed || mayCreate.busy} onChange={(on) => mayCreate.run(on)} label="可以新建 workspace" />
          </label>
        )}
        {u.beta !== null && (
          <label className={css.line}>
            <span className={css.grow}>测试版<span className={css.hint}>能用 app.youdid.wtf</span></span>
            <Switch checked={beta.busy ? Boolean(beta.arg) : u.beta} disabled={beta.busy} onChange={(on) => beta.run(on)} label="测试版" />
          </label>
        )}
        {u.blocked !== null && (
          <div className={css.actions}>
            {u.blocked
              ? <Button busy={block.busy} onClick={() => block.run(false)}>解封</Button>
              : <Button variant="danger" onClick={() => setBlocking(true)}>封禁</Button>}
          </div>
        )}
        {block.error && !blocking && <p className={controlsCss.fieldError} role="alert">{block.error.message}</p>}
      </>}
      <Confirm open={blocking} onClose={() => setBlocking(false)} busy={block.busy} onConfirm={() => block.run(true)}
        title={`封禁 ${u.title}？`} action="封禁"
        description="会立刻在所有设备上退出，之后也登录不了。workspace 和里面的东西不动，随时可以解封。" error={block.error?.message} />
    </Detail>
  );
}

function WorkspaceDetail({ account, id, close }: { account: Account; id: string; close: string }) {
  const toast = useToast();
  const navigate = useNavigate();
  const { value: w, error } = useKept<WorkspacePage>({ topic: "adminItem", account: account.sub, list: "workspaces", id });
  const [deleting, setDeleting] = useState(false);
  const remove = useAction(() => admin.deleteWorkspace(account.sub, id), () => { setDeleting(false); toast("已删除 workspace"); void navigate(close, { replace: true }); });
  if (!w) return <aside className={css.detail}>{error ? <Failed error={error} /> : <Loading label="正在读取…" fill={false} />}</aside>;
  return (
    <Detail close={close} head={<>
      <span className={`${css.wsMark} ${css.wsMarkLarge}`}>{[...w.title][0]}</span>
      <span className={css.detailTitle}><b>{w.title}</b><span className={shellCss.mono}>{w.id}</span></span>
    </>}>
      <dl className={css.kv}>
        <dt>创建</dt><dd>{w.creator ? <Link className={css.link} to={`${PATH.users}/${encodeURIComponent(w.creator.id)}`}>{w.creator.title}</Link> : "已不在的人"} · <Time stamp={stamp(w, "created_at")} /></dd>
        <dt>人数</dt><dd>{w.people}</dd>
      </dl>
      <div className={css.group}>成员 {w.members.length}</div>
      {w.members.map((m) => (
        <Link key={m.id} className={css.line} to={`${PATH.users}/${encodeURIComponent(m.id)}`}>
          <Avatar account={m.person} size={20} />
          <span className={css.grow}>{m.title}</span>
          <span className={css.lineAside}>{m.role}{stamp(m, "last_seen") && <> · <Time stamp={stamp(m, "last_seen")} fixed /></>}</span>
          <ChevronRight {...ICON} />
        </Link>
      ))}
      <div className={css.group}>Station {w.stations.length}</div>
      {w.stations.length === 0 && <div className={css.line} data-quiet>还没有 station</div>}
      {w.stations.map((s) => (
        // still.fail cloud only knows when a station last came to it; whether it is up is for the devices to find out.
        <div key={s.id} className={css.line}>
          <StatusDot state={s.state} />
          <span className={css.grow}>{s.name}</span>
          <span className={css.lineAside}>
            <span data-off={s.outdated || undefined}>{s.version ?? "版本未知"}</span> · {stamp(s, "last_seen") ? <Time stamp={stamp(s, "last_seen")} fixed /> : "没连过"}
          </span>
        </div>
      ))}
      {w.invitations.length > 0 && <>
        <div className={css.group}>待接受的邀请 {w.invitations.length}</div>
        {w.invitations.map((i) => (
          <div key={i.id} className={css.line}>
            <span className={css.grow}>{i.email}</span>
            <span className={css.lineAside}>{i.line} · {stamp(i, "expires_at")?.until}过期</span>
          </div>
        ))}
      </>}
      <div className={css.actions}><Button variant="danger" onClick={() => setDeleting(true)}>删除 workspace</Button></div>
      <Confirm open={deleting} onClose={() => setDeleting(false)} busy={remove.busy} onConfirm={() => remove.run()}
        title={`删除「${w.title}」？`} action="删除 workspace"
        description="成员都会被移出，它的 station 会断开、需要重新加入别的 workspace。删除后不能恢复。" error={remove.error?.message} />
    </Detail>
  );
}

function FeedbackDetail({ account, id, close }: { account: Account; id: string; close: string }) {
  const toast = useToast();
  const { value: f, error } = useKept<FeedbackPage>({ topic: "adminItem", account: account.sub, list: "feedback", id });
  const status = useAction((to: FeedbackStatus) => admin.feedbackStatus(account.sub, id, to), (_, to) => toast(`已标成${f?.statuses.find((s) => s.id === to)?.label ?? to}`));
  useEffect(() => { if (status.error) toast(`没能更改：${status.error.message}`); }, [status.error, toast]);
  const copy = () => void navigator.clipboard.writeText(f?.text ?? "").then(() => toast("已复制，可以贴给 agent"), () => toast("没能复制"));
  if (!f) return <aside className={css.detail}>{error ? <Failed error={error} /> : <Loading label="正在读取…" fill={false} />}</aside>;
  return (
    <Detail close={close} head={
      <span className={css.detailTitle}><b>{f.title}</b><span className={shellCss.mono}>{f.number}</span></span>
    }>
      <div className={css.fbBar}>
        <Select value={status.busy ? status.arg! : f.status} disabled={status.busy} onChange={(v) => { if (v !== f.status) status.run(v as FeedbackStatus); }} label="状态"
          options={f.statuses.map((s) => ({ value: s.id, label: s.label }))} />
        <Button icon={Copy} onClick={copy}>复制给 agent</Button>
      </div>
      <dl className={css.kv}>
        <dt>提交</dt><dd><Time stamp={stamp(f, "created_at")} /></dd>
        <dt>渠道</dt><dd>{f.channelLabel}</dd>
        <dt>范围</dt><dd>{f.area}</dd>
        {f.reporter && <><dt>反馈人</dt><dd>{f.reporter}</dd></>}
        {f.account && <><dt>账号</dt><dd><Link className={css.link} to={`${PATH.users}/${encodeURIComponent(f.account.id)}`}>{f.account.title}</Link></dd></>}
        {f.workspace && <><dt>Workspace</dt><dd><Link className={css.link} to={`${PATH.workspaces}/${encodeURIComponent(f.workspace.id)}`}>{f.workspace.title}</Link></dd></>}
        {f.station && <><dt>Station</dt><dd>{f.station.name || <span className={shellCss.mono}>{f.station.id}</span>}</dd></>}
      </dl>
      <div className={css.group}>内容</div>
      <div className={`${conversationCss.markdown} ${css.fbBody}`}><Prose>{f.body}</Prose></div>
      {f.context.length > 0 && <>
        <div className={css.group}>上下文</div>
        <dl className={`${css.kv} ${css.fbContext}`}>
          {f.context.map((c) => <Fragment key={c.key}><dt>{c.key}</dt><dd className={shellCss.mono}>{c.value}</dd></Fragment>)}
        </dl>
      </>}
      {f.logs && <>
        <div className={css.group}>日志</div>
        <pre className={`${shellCss.mono} ${css.fbLogs}`}>{f.logs}</pre>
      </>}
    </Detail>
  );
}

// ── a new invite code ───────────────────────────────────────────────────

const DAYS = [7, 14, 30, 90];

function NewCodeDialog({ account, onClose }: { account: Account; onClose(): void }) {
  const [note, setNote] = useState("");
  const [days, setDays] = useState("14");
  const make = useAction(() => admin.createCode(account.sub, note, Number(days)));
  const made = make.result;
  return (
    <Dialog open onClose={onClose} wide title={made ? "邀请码已生成" : "生成邀请码"}
      description={made ? `把邀请码或注册链接发给对方。只能用一次，${days} 天后过期。` : "对方登录 still.fail 后用它新建 workspace，这个账号从此就有资格，最多建 5 个。一个邀请码只能用一次。已经登录过的人，可以直接在用户页给他开通。"}
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

