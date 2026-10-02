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
import { failure, useToast } from "../toast.tsx";
import { Button, Confirm, CopyCommand, Dialog, Field, IconButton, Loading, MobileBack, Pill, ResizeHandle, Select, StatusDot, Switch, Time, ICON, type Presence, type Tone } from "../ui.tsx";
import { useAccounts, useSignOut, type Account } from "../cloud/accounts.ts";
import { admin, useAction, type FeedbackStatus } from "../cloud/api.ts";
import { Prose } from "../Prose.tsx";
import { Avatar } from "../cloud/gate.tsx";
import * as nav from "../Sidebar.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./console.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as conversationCss from "../styles/conversation.css.ts";
import { t } from "../i18n.ts";

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
  const signOut = useSignOut();
  return (
    <div className={shellCss.shell} data-detail={!atIndex}>
      <nav className={nav.sidebar} aria-label={t("web-pages.admin.title")}>
        <ResizeHandle variable="--sidebar-w" edge="right" min={180} max={480} label={t("web-pages.workspace.resizeSidebar")} />
        <div className={`${nav.brand} ${nav.brandCompact}`}><Lockup /></div>
        <div className={nav.navScroll}>
          <div className={nav.navHeading}>{t("web-pages.admin.title")}</div>
          <NavLink className={nav.navRow} to="/overview"><Monitor {...ICON} />{t("web-pages.admin.overview")}</NavLink>
          <NavLink className={nav.navRow} to="/users"><Users {...ICON} />{t("web-pages.admin.users")}</NavLink>
          <NavLink className={nav.navRow} to="/workspaces"><Boxes {...ICON} />Workspace</NavLink>
          <NavLink className={nav.navRow} to="/codes"><Ticket {...ICON} />{t("web-pages.cloud.inviteCode")}</NavLink>
          <NavLink className={nav.navRow} to="/feedback"><Said {...ICON} />{t("web-pages.admin.feedback")}</NavLink>
        </div>
        <div className={`${nav.navFootRow} ${css.adminFoot}`}>
          <span className={css.adminAccount}><Avatar account={account} size={20} /><span className={css.accountEmail}>{account.email}</span></span>
          <IconButton label={t("web-pages.admin.signOut")} icon={LogOut} busy={signOut.busy(account.sub)} onClick={() => void signOut.signOut(account.sub)} />
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
  return error ? <p className={controlsCss.fieldError} role="alert">{t("web-pages.admin.readFailed", { error: error.message })}</p> : null;
}

// ── the overview ────────────────────────────────────────────────────────

function OverviewPage({ account }: { account: Account }) {
  const { value: view, error } = useKept<Overview>({ topic: "adminOverview", account: account.sub });
  const max = Math.max(1, ...(view?.weeks.map((w) => w.count) ?? []));
  return (
    <div className={`${pagesCss.page} ${css.mid}`}>
      <MobileBack to="/" label={t("web-pages.admin.title")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.admin.overview")}</h1></div></header>
      <Failed error={error} />
      {!view ? !error && <Loading label={t("web-pages.settings.reading")} fill={false} /> : <>
        <div className={css.stats}>
          {view.stats.map((s) => (
            <Link key={s.label} className={css.stat} to={`${PATH[s.list]}?filter=${s.filter}`}>
              <span className={shellCss.muted}>{s.label}</span>
              <span className={css.statValue}>{s.value}</span>
              <span className={css.statNote}>{s.note}</span>
            </Link>
          ))}
        </div>
        <section className={css.chart} aria-label={t("web-pages.admin.weekly")}>
          <div className={css.chartHead}><b>{t("web-pages.admin.weekly")}</b><span className={shellCss.muted}>{t("web-pages.admin.last12")}</span></div>
          <div className={css.bars}>
            {view.weeks.map((w, i) => (
              <div key={i} className={css.bar} title={t("web-pages.admin.weekBar", { week: w.label, n: w.count })}>
                <span className={css.barCount}>{w.count || ""}</span>
                <span className={css.barFill} data-now={i === view.weeks.length - 1 || undefined} style={{ height: `${(w.count / max) * 100}%` }} />
                <span className={css.barLabel}>{w.label}</span>
              </div>
            ))}
          </div>
        </section>
        {view.todo.length > 0 && <>
          <h2 className={css.h2}>{t("web-pages.admin.todo")}</h2>
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

// Getters: read in the language at the time.
const TITLE: Record<List, string> = {
  get users() { return t("web-pages.admin.users"); }, workspaces: "Workspace",
  get "invite-codes"() { return t("web-pages.cloud.inviteCode"); }, get feedback() { return t("web-pages.admin.feedback"); },
};
const PLACEHOLDER: Record<List, string> = {
  get users() { return t("web-pages.admin.search.users"); }, get workspaces() { return t("web-pages.admin.search.workspaces"); },
  get "invite-codes"() { return t("web-pages.admin.search.codes"); }, get feedback() { return t("web-pages.admin.search.feedback"); },
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
        <MobileBack to="/" label={t("web-pages.admin.title")} />
        <header className={pagesCss.pageHead}>
          <div><h1>{TITLE[list]}{view && <span className={css.total}>{view.total}</span>}</h1></div>
          {list === "invite-codes" && <Button icon={Plus} variant="primary" onClick={() => setMaking(true)}>{t("web-pages.admin.code.make")}</Button>}
        </header>
        <div className={css.toolbar}>
          <label className={css.search}>
            <Search {...ICON} />
            <input className={controlsCss.input} value={query} placeholder={PLACEHOLDER[list]} aria-label={t("web-pages.admin.search")} onChange={(e) => set("q", e.target.value)} />
          </label>
          {view && view.sorts.length > 1 && (
            <label className={css.sort}>
              <span className={shellCss.muted}>{t("web-pages.admin.sortBy")}</span>
              <Select value={view.sort} onChange={(v) => set("sort", v === view.sorts[0]!.id ? null : v)} label={t("web-pages.admin.sort")} options={view.sorts.map((s) => ({ value: s.id, label: s.label }))} />
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
        {list === "feedback" && error?.status === 404 ? <p className={css.empty}>{t("web-pages.admin.noFeedback")}</p> : <Failed error={error} />}
        {!view ? !error && <Loading label={t("web-pages.settings.reading")} fill={false} /> : view.rows.length === 0 ? (
          <p className={css.empty}>{query ? t("web-pages.admin.notFound") : t("web-pages.admin.empty")}</p>
        ) : (
          <div className={css.list}>
            {view.rows.map((row) => list === "invite-codes"
              ? <CodeRow key={row.id} account={account} row={row} />
              : <ItemRow key={row.id} list={list} row={row} open={row.id === id} to={`${PATH[list]}/${encodeURIComponent(row.id)}${search}`} />)}
            {view.more && <button className={css.more} onClick={() => setLimit((n) => n + STEP)}>{t("web-pages.admin.more", { n: Math.min(STEP, view.found - view.rows.length), total: view.found })}</button>}
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
              : stamp(row, "last_seen") ? <Time stamp={stamp(row, "last_seen")} fixed /> : list === "users" ? t("web-pages.admin.neverSeen") : ""}
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
  const revoke = useAction(() => admin.revokeCode(account.sub, row.id), () => { setRevoking(false); toast(t("web-pages.admin.code.revoked")); });
  const copy = () => void navigator.clipboard.writeText(row.url ?? "").then(() => toast(t("web-pages.admin.code.linkCopied")), (e: unknown) => toast(t("web-pages.admin.copyFailed", { error: failure(e) })));
  const at = row.state === "used" ? stamp(row, "used_at") : row.state === "revoked" ? stamp(row, "revoked_at") : stamp(row, "created_at");
  return (
    <div className={css.row} data-static>
      <span className={css.rowText}>
        <span className={css.rowLine1}>
          <b className={`${shellCss.mono} ${css.code}`}>{row.title}</b>
          <Marks marks={row.marks} />
          <span className={css.rowTime}>
            {row.state === "open" ? <>
              <IconButton label={t("web-pages.admin.code.copyLink")} icon={Copy} onClick={copy} />
              <Button variant="ghost" onClick={() => setRevoking(true)}>{t("web-pages.settings.members.revoke")}</Button>
            </> : <Time stamp={at} fixed />}
          </span>
        </span>
        <span className={css.rowLine2}>{row.line || (row.state === "open" ? t("web-pages.admin.expires", { until: stamp(row, "expires_at")?.until ?? "" }) : "")}</span>
      </span>
      <Confirm open={revoking} onClose={() => setRevoking(false)} busy={revoke.busy} onConfirm={() => revoke.run()}
        title={t("web-pages.admin.code.revokeConfirm", { code: row.title })} action={t("web-pages.admin.code.revoke")}
        description={t("web-pages.admin.code.revokeBody")} error={revoke.error?.message} />
    </div>
  );
}

// ── an item's page, beside its list ─────────────────────────────────────

function Detail({ close, head, children }: { close: string; head: React.ReactNode; children: React.ReactNode }) {
  return (
    <aside className={css.detail}>
      <MobileBack to={close} label={t("web-pages.admin.backToList")} />
      <div className={css.detailHead}>{head}<Link className={css.close} to={close} aria-label={t("common.close")}><Close {...ICON} /></Link></div>
      {children}
    </aside>
  );
}

function UserDetail({ account, id, close, search }: { account: Account; id: string; close: string; search: string }) {
  const toast = useToast();
  const { value: u, error } = useKept<UserPage>({ topic: "adminItem", account: account.sub, list: "users", id });
  const mayCreate = useAction((on: boolean) => admin.setMayCreate(account.sub, id, on), (_, on) => toast(on ? t("web-pages.admin.user.mayCreateOn") : t("web-pages.admin.user.mayCreateOff")));
  const beta = useAction((on: boolean) => admin.setBeta(account.sub, id, on), (_, on) => toast(on ? t("web-pages.admin.user.betaOn") : t("web-pages.admin.user.betaOff")));
  const [blocking, setBlocking] = useState(false);
  const block = useAction((on: boolean) => admin.block(account.sub, id, on), (_, on) => { setBlocking(false); toast(on ? t("web-pages.admin.user.blocked") : t("web-pages.admin.user.unblocked")); });
  useEffect(() => { const e = mayCreate.error ?? beta.error; if (e) toast(t("web-pages.admin.changeFailed", { error: e.message })); }, [mayCreate.error, beta.error, toast]);
  if (!u) return <aside className={css.detail}>{error ? <Failed error={error} /> : <Loading label={t("web-pages.settings.reading")} fill={false} />}</aside>;
  return (
    <Detail close={close} head={<>
      <Avatar account={u.person} size={40} />
      <span className={css.detailTitle}><b>{u.title}</b><span>{u.email}</span></span>
    </>}>
      <dl className={css.kv}>
        <dt>{t("web-pages.admin.user.admission")}</dt><dd>{u.admission}{u.code && <span className={shellCss.muted}> · <span className={shellCss.mono}>{u.code}</span></span>}</dd>
        <dt>{t("web-pages.admin.user.firstSignIn")}</dt><dd><Time stamp={stamp(u, "created_at")} /></dd>
        <dt>{t("web-pages.admin.user.lastSeen")}</dt><dd>{stamp(u, "last_seen") ? <Time stamp={stamp(u, "last_seen")} /> : t("web-pages.admin.neverSeen")}</dd>
        <dt>ID</dt><dd className={`${shellCss.mono} ${shellCss.muted}`}>{u.id}</dd>
      </dl>
      <div className={css.group}>Workspace {u.workspaces.length}</div>
      {u.workspaces.length === 0 && <div className={css.line} data-quiet>{t("web-pages.admin.user.noWorkspace")}</div>}
      {u.workspaces.map((w) => (
        <Link key={w.id} className={css.line} to={`${PATH.workspaces}/${encodeURIComponent(w.id)}${search}`}>
          <span className={css.grow}>{w.name}</span><span className={css.lineAside}>{w.line}</span><ChevronRight {...ICON} />
        </Link>
      ))}
      {!u.admin && <>
        <div className={css.group}>{t("web-pages.admin.user.rights")}</div>
        {u.mayCreate !== null && (
          <label className={css.line}>
            <span className={css.grow}>{t("web-pages.admin.user.mayCreate")}<span className={css.hint}>{u.mayCreateHint}</span></span>
            <Switch checked={mayCreate.busy ? Boolean(mayCreate.arg) : u.mayCreate} disabled={u.mayCreateFixed || mayCreate.busy} onChange={(on) => mayCreate.run(on)} label={t("web-pages.admin.user.mayCreate")} />
          </label>
        )}
        {u.beta !== null && (
          <label className={css.line}>
            <span className={css.grow}>{t("web-pages.admin.user.beta")}<span className={css.hint}>{t("web-pages.admin.user.betaHint")}</span></span>
            <Switch checked={beta.busy ? Boolean(beta.arg) : u.beta} disabled={beta.busy} onChange={(on) => beta.run(on)} label={t("web-pages.admin.user.beta")} />
          </label>
        )}
        {u.blocked !== null && (
          <div className={css.actions}>
            {u.blocked
              ? <Button busy={block.busy} onClick={() => block.run(false)}>{t("web-pages.admin.user.unblock")}</Button>
              : <Button variant="danger" onClick={() => setBlocking(true)}>{t("web-pages.admin.user.block")}</Button>}
          </div>
        )}
        {block.error && !blocking && <p className={controlsCss.fieldError} role="alert">{block.error.message}</p>}
      </>}
      <Confirm open={blocking} onClose={() => setBlocking(false)} busy={block.busy} onConfirm={() => block.run(true)}
        title={t("web-pages.admin.user.blockConfirm", { name: u.title })} action={t("web-pages.admin.user.block")}
        description={t("web-pages.admin.user.blockBody")} error={block.error?.message} />
    </Detail>
  );
}

function WorkspaceDetail({ account, id, close }: { account: Account; id: string; close: string }) {
  const toast = useToast();
  const navigate = useNavigate();
  const { value: w, error } = useKept<WorkspacePage>({ topic: "adminItem", account: account.sub, list: "workspaces", id });
  const [deleting, setDeleting] = useState(false);
  const remove = useAction(() => admin.deleteWorkspace(account.sub, id), () => { setDeleting(false); toast(t("web-pages.settings.workspace.deleted")); void navigate(close, { replace: true }); });
  if (!w) return <aside className={css.detail}>{error ? <Failed error={error} /> : <Loading label={t("web-pages.settings.reading")} fill={false} />}</aside>;
  return (
    <Detail close={close} head={<>
      <span className={`${css.wsMark} ${css.wsMarkLarge}`}>{[...w.title][0]}</span>
      <span className={css.detailTitle}><b>{w.title}</b><span className={shellCss.mono}>{w.id}</span></span>
    </>}>
      <dl className={css.kv}>
        <dt>{t("web-pages.chat.info.created")}</dt><dd>{w.creator ? <Link className={css.link} to={`${PATH.users}/${encodeURIComponent(w.creator.id)}`}>{w.creator.title}</Link> : t("web-pages.admin.ws.gone")} · <Time stamp={stamp(w, "created_at")} /></dd>
        <dt>{t("web-pages.admin.ws.people")}</dt><dd>{w.people}</dd>
      </dl>
      <div className={css.group}>{t("web-pages.admin.ws.members", { n: w.members.length })}</div>
      {w.members.map((m) => (
        <Link key={m.id} className={css.line} to={`${PATH.users}/${encodeURIComponent(m.id)}`}>
          <Avatar account={m.person} size={20} />
          <span className={css.grow}>{m.title}</span>
          <span className={css.lineAside}>{m.role}{stamp(m, "last_seen") && <> · <Time stamp={stamp(m, "last_seen")} fixed /></>}</span>
          <ChevronRight {...ICON} />
        </Link>
      ))}
      <div className={css.group}>Station {w.stations.length}</div>
      {w.stations.length === 0 && <div className={css.line} data-quiet>{t("web-pages.admin.ws.noStations")}</div>}
      {w.stations.map((s) => (
        // still.fail cloud only knows when a station last came to it; whether it is up is for the devices to find out.
        <div key={s.id} className={css.line}>
          <StatusDot state={s.state} />
          <span className={css.grow}>{s.name}</span>
          <span className={css.lineAside}>
            <span data-off={s.outdated || undefined}>{s.version ?? t("web-pages.admin.ws.versionUnknown")}</span> · {stamp(s, "last_seen") ? <Time stamp={stamp(s, "last_seen")} fixed /> : t("web-pages.admin.ws.neverConnected")}
          </span>
        </div>
      ))}
      {w.invitations.length > 0 && <>
        <div className={css.group}>{t("web-pages.admin.ws.invitations", { n: w.invitations.length })}</div>
        {w.invitations.map((i) => (
          <div key={i.id} className={css.line}>
            <span className={css.grow}>{i.email}</span>
            <span className={css.lineAside}>{i.line} · {t("web-pages.admin.expires", { until: stamp(i, "expires_at")?.until ?? "" })}</span>
          </div>
        ))}
      </>}
      <div className={css.actions}><Button variant="danger" onClick={() => setDeleting(true)}>{t("web-pages.settings.workspace.delete")}</Button></div>
      <Confirm open={deleting} onClose={() => setDeleting(false)} busy={remove.busy} onConfirm={() => remove.run()}
        title={t("web-pages.settings.workspace.deleteConfirm", { name: w.title })} action={t("web-pages.settings.workspace.delete")}
        description={t("web-pages.admin.ws.deleteBody")} error={remove.error?.message} />
    </Detail>
  );
}

function FeedbackDetail({ account, id, close }: { account: Account; id: string; close: string }) {
  const toast = useToast();
  const { value: f, error } = useKept<FeedbackPage>({ topic: "adminItem", account: account.sub, list: "feedback", id });
  const status = useAction((to: FeedbackStatus) => admin.feedbackStatus(account.sub, id, to), (_, to) => toast(t("web-pages.admin.fb.marked", { status: f?.statuses.find((s) => s.id === to)?.label ?? to })));
  useEffect(() => { if (status.error) toast(t("web-pages.admin.changeFailed", { error: status.error.message })); }, [status.error, toast]);
  const copy = () => void navigator.clipboard.writeText(f?.text ?? "").then(() => toast(t("web-pages.admin.fb.copied")), () => toast(t("web-pages.admin.fb.copyFailed")));
  if (!f) return <aside className={css.detail}>{error ? <Failed error={error} /> : <Loading label={t("web-pages.settings.reading")} fill={false} />}</aside>;
  return (
    <Detail close={close} head={
      <span className={css.detailTitle}><b>{f.title}</b><span className={shellCss.mono}>{f.number}</span></span>
    }>
      <div className={css.fbBar}>
        <Select value={status.busy ? status.arg! : f.status} disabled={status.busy} onChange={(v) => { if (v !== f.status) status.run(v as FeedbackStatus); }} label={t("web-pages.admin.fb.status")}
          options={f.statuses.map((s) => ({ value: s.id, label: s.label }))} />
        <Button icon={Copy} onClick={copy}>{t("web-pages.admin.fb.copy")}</Button>
      </div>
      <dl className={css.kv}>
        <dt>{t("web-pages.admin.fb.submitted")}</dt><dd><Time stamp={stamp(f, "created_at")} /></dd>
        <dt>{t("web-pages.admin.fb.channel")}</dt><dd>{f.channelLabel}</dd>
        <dt>{t("web-pages.admin.fb.area")}</dt><dd>{f.area}</dd>
        {f.reporter && <><dt>{t("web-pages.admin.fb.reporter")}</dt><dd>{f.reporter}</dd></>}
        {f.account && <><dt>{t("web-pages.profiles.account")}</dt><dd><Link className={css.link} to={`${PATH.users}/${encodeURIComponent(f.account.id)}`}>{f.account.title}</Link></dd></>}
        {f.workspace && <><dt>Workspace</dt><dd><Link className={css.link} to={`${PATH.workspaces}/${encodeURIComponent(f.workspace.id)}`}>{f.workspace.title}</Link></dd></>}
        {f.station && <><dt>Station</dt><dd>{f.station.name || <span className={shellCss.mono}>{f.station.id}</span>}</dd></>}
      </dl>
      <div className={css.group}>{t("web-pages.admin.fb.content")}</div>
      <div className={`${conversationCss.markdown} ${css.fbBody}`}><Prose>{f.body}</Prose></div>
      {f.context.length > 0 && <>
        <div className={css.group}>{t("web-pages.admin.fb.context")}</div>
        <dl className={`${css.kv} ${css.fbContext}`}>
          {f.context.map((c) => <Fragment key={c.key}><dt>{c.key}</dt><dd className={shellCss.mono}>{c.value}</dd></Fragment>)}
        </dl>
      </>}
      {f.logs && <>
        <div className={css.group}>{t("web-pages.admin.fb.logs")}</div>
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
    <Dialog open onClose={onClose} wide title={made ? t("web-pages.admin.code.made") : t("web-pages.admin.code.make")}
      description={made ? t("web-pages.admin.code.madeLead", { n: Number(days) }) : t("web-pages.admin.code.makeLead")}
      footer={made ? <Button variant="primary" onClick={onClose}>{t("common.done")}</Button> : <>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" busy={make.busy} onClick={() => make.run()}>{t("web-pages.admin.code.makeShort")}</Button>
      </>}>
      {made ? (
        <>
          <Field label={t("web-pages.cloud.inviteCode")}><CopyCommand text={made.code} /></Field>
          <Field label={t("web-pages.admin.code.link")} hint={t("web-pages.admin.code.linkHint")}><CopyCommand text={made.url} /></Field>
        </>
      ) : (
        <>
          <Field label={t("web-pages.admin.code.note")} htmlFor="code-note" hint={t("web-pages.admin.code.noteHint")}>
            <input id="code-note" className={controlsCss.input} value={note} autoFocus maxLength={200} onChange={(e) => setNote(e.target.value)} placeholder={t("web-pages.admin.code.notePlaceholder")}
              onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && !make.busy) make.run(); }} />
          </Field>
          <Field label={t("web-pages.admin.code.validity")}>
            <Select value={days} onChange={setDays} label={t("web-pages.admin.code.validity")} options={DAYS.map((d) => ({ value: String(d), label: t("web-pages.admin.code.days", { n: d }) }))} />
          </Field>
        </>
      )}
      {make.error && <p className={controlsCss.fieldError} role="alert">{make.error.message}</p>}
    </Dialog>
  );
}

