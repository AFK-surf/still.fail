// The admin's console, on its own host: every user and workspace in still.fail cloud, the invite codes that let
// a new person create a workspace, and the bug reports people's agents sent about still.fail. Only the admin's account reaches it (still.fail cloud answers 404 to everyone
// else). The core puts each page together (views/admin.ts: found, filtered, sorted, counted); this draws it. Where
// the page is (a list's words, filter and sort, the item open) is in its URL, so a link shows the same.
import { useTopic } from "../core/react.ts";
import type { CoreError, Topic } from "../core/client.ts";
import { Boxes, ChevronRight, Close, Copy, LogOut, Monitor, Plus, Said, Search, Server, Ticket, Users } from "@stillfail/ui/icons.tsx";
import { Fragment, useEffect, useRef, useState } from "react";
import { Link, Navigate, NavLink, Route, Routes, useLocation, useNavigate, useParams, useSearchParams } from "react-router";
import { Wordmark } from "../brand.tsx";
import { stamp, type Stamp } from "../api.ts";
import { sampleStamp, sampleWords } from "../samples.ts";
import { failure, useToast } from "@stillfail/ui/toast.tsx";
import { Button, Confirm, CopyCommand, Dialog, Field, IconButton, MobileBack, Pill, ResizeHandle, Segmented, Select, StatusDot, Switch, SwitchRow, Time, ICON, type Presence, type Tone, Waiting } from "../ui.tsx";
import { useAccounts, useSignOut, type Account } from "../cloud/accounts.ts";
import { admin, useAction, type FeedbackStatus } from "../cloud/api.ts";
import { Prose } from "../Prose.tsx";
import { Avatar } from "../cloud/gate.tsx";
import * as nav from "../Sidebar.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./console.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as conversationCss from "../styles/conversation.css.ts";
import { t } from "../i18n.ts";
import { STATIONS_PER_WORKSPACE } from "../../../client/limits.ts";

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

// ── what the core gives (views/admin.ts) ───────────────────────────────

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
  /** An email given rights before anyone signed in with it (id `email:<address>`). */
  pending?: boolean;
  id: string; title: string; person: PersonLike; email: string; admin: boolean; admission: string; code: string | null;
  mayCreate: boolean | null; mayCreateHint: string; mayCreateFixed: boolean; beta: boolean | null; blocked: boolean | null;
  workspaces: { id: string; name: string; line: string }[];
};
type WorkspacePage = Timed & {
  id: string; title: string; creator: { id: string; title: string } | null; people: string;
  /** Missing from a core from before. */
  stationCount?: string; plan?: string | null; limits?: { members: number; stations: number | null } | null; enrollable?: boolean;
  members: (Timed & { id: string; title: string; person: PersonLike; role: string })[];
  /** Emails added that have not signed in yet. */
  added?: (Timed & { id: string; email: string; line: string })[];
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
type Range = "day" | "week";
type RelaysView = {
  range: Range;
  ranges: { id: Range; label: string }[];
  relays: Relay[];
};
type Relay = {
  url: string; name: string;
  state: "online" | "offline" | "error";
  /** When it was last heard from, said for people ("1 分钟前更新"). */
  seen: string;
  numbers: { label: string; value: string; tone?: "amber" | "red" }[];
  charts: RelayChart[];
  /** Where times are marked along the charts: `index` a bucket's. */
  ticks: { index: number; label: string }[];
};
type RelayChart = { id: string; label: string; peak: string; series: { id: string; label: string; values: (number | null)[] }[] };
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
        <div className={`${nav.brand} ${nav.brandCompact}`}><Wordmark size={24} /></div>
        <div className={nav.navScroll}>
          <div className={nav.navHeading}>{t("web-pages.admin.title")}</div>
          <NavLink className={nav.navRow} to="/overview"><Monitor {...ICON} />{t("web-pages.admin.overview")}</NavLink>
          <NavLink className={nav.navRow} to="/users"><Users {...ICON} />{t("web-pages.admin.users")}</NavLink>
          <NavLink className={nav.navRow} to="/workspaces"><Boxes {...ICON} />Workspace</NavLink>
          <NavLink className={nav.navRow} to="/codes"><Ticket {...ICON} />{t("web-pages.cloud.inviteCode")}</NavLink>
          <NavLink className={nav.navRow} to="/feedback"><Said {...ICON} />{t("web-pages.admin.feedback")}</NavLink>
          <NavLink className={nav.navRow} to="/relays"><Server {...ICON} />{t("web-pages.admin.relays")}</NavLink>
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
          <Route path="relays" element={<RelaysPage account={account} />} />
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
  return (
    <div className={`${pagesCss.page} ${css.mid}`}>
      <MobileBack to="/" label={t("web-pages.admin.title")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.admin.overview")}</h1></div></header>
      <Failed error={error} />
      {!view ? !error && <Waiting sample={<OverviewBody view={SAMPLE_OVERVIEW} />} /> : <OverviewBody view={view} />}
    </div>
  );
}

/** The overview under its title (`view`): its numbers, each opening its list; the weeks' sign-ups; what needs doing. */
function OverviewBody({ view }: { view: Overview }) {
  const max = Math.max(1, ...view.weeks.map((w) => w.count));
  return (
    <>
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
    </>
  );
}

/** The console's pages made up, for what they show while they are read (in their bones). */
const SAMPLE_OVERVIEW: Overview = {
  stats: [3, 4, 3, 4].map((n, i) => ({ label: sampleWords(n), value: 100 + i, note: sampleWords(n + 3), list: "users", filter: "" })),
  weeks: [3, 5, 4, 6, 8, 5, 7, 9, 6, 8, 10, 7].map((count) => ({ count, label: sampleWords(2) })),
  todo: [14, 10].map((n) => ({ text: sampleWords(n), hint: sampleWords(6), tone: "amber", list: "users", filter: "" })),
};
const SAMPLE_RELAYS: Relay[] = [6, 8].map((n, i) => ({
  url: String(i), name: sampleWords(n), state: "online", seen: sampleWords(5), ticks: [],
  numbers: [3, 4, 3].map((m) => ({ label: sampleWords(m), value: sampleWords(3) })),
  charts: [4, 3].map((m, j) => ({ id: String(j), label: sampleWords(m), peak: sampleWords(3), series: [{ id: "", label: "", values: [2, 3, 5, 4, 6, 5, 7, 6, 8, 6] }] })),
}));
const sampleRows = (list: List): Row[] => [6, 8, 5, 7, 9, 6].map((n, i) => ({
  id: `sample-${i}`, title: sampleWords(n), line: sampleWords(n + 8), marks: [], number: sampleWords(4),
  ...(list === "users" ? { person: { name: sampleWords(n), email: "", picture: "" } } : {}), time: { last_seen: sampleStamp(3), created_at: sampleStamp(3) },
}));
const SAMPLE_TIME = { created_at: sampleStamp(4), last_seen: sampleStamp(4) };
const SAMPLE_USER: UserPage = {
  id: "", title: sampleWords(5), person: { name: sampleWords(5), email: "", picture: "" }, email: sampleWords(16), admin: false, admission: sampleWords(4), code: null,
  mayCreate: false, mayCreateHint: sampleWords(14), mayCreateFixed: false, beta: false, blocked: false, time: SAMPLE_TIME,
  workspaces: [6, 4].map((n, i) => ({ id: String(i), name: sampleWords(n), line: sampleWords(n + 4) })),
};
const SAMPLE_WORKSPACE: WorkspacePage = {
  id: sampleWords(10), title: sampleWords(5), creator: { id: "", title: sampleWords(5) }, people: sampleWords(6), invitations: [], time: SAMPLE_TIME,
  members: [5, 7].map((n, i) => ({ id: String(i), title: sampleWords(n), person: { name: sampleWords(n), email: "", picture: "" }, role: sampleWords(2), time: SAMPLE_TIME })),
  stations: [5, 3].map((n, i) => ({ id: String(i), name: sampleWords(n), version: sampleWords(4), outdated: false, state: "online", time: SAMPLE_TIME })),
};
const SAMPLE_FEEDBACK: FeedbackPage = {
  id: "", number: sampleWords(4), title: sampleWords(12), body: [40, 26].map(sampleWords).join("\n\n"), status: "new", statuses: [{ id: "new", label: sampleWords(2) }],
  marks: [], channel: "", channelLabel: sampleWords(3), area: sampleWords(4), reporter: sampleWords(5), station: null, workspace: null, account: null,
  context: [], logs: null, text: "", time: SAMPLE_TIME,
};

// ── the relays ──────────────────────────────────────────────────────────

/** still.fail's relays, a card each: how each stands, its numbers, and its load over the range picked (in the URL). */
function RelaysPage({ account }: { account: Account }) {
  const [params, setParams] = useSearchParams();
  const range = params.get("range") === "week" ? "week" : undefined;
  const { value: view, error } = useKept<RelaysView>({ topic: "adminRelays", account: account.sub, ...(range ? { range } : {}) });
  const pick = (to: Range) => setParams((p) => { const next = new URLSearchParams(p); if (to === "day") next.delete("range"); else next.set("range", to); return next; }, { replace: true });
  // A still.fail cloud from before has none.
  const none = error?.status === 404 || view?.relays.length === 0;
  return (
    <div className={`${pagesCss.page} ${css.mid}`}>
      <MobileBack to="/" label={t("web-pages.admin.title")} />
      <header className={pagesCss.pageHead}>
        <div><h1>{t("web-pages.admin.relays")}</h1></div>
        {view && view.ranges.length > 1 && (
          <Segmented<Range> label={t("web-pages.admin.relays.range")} value={view.range} onChange={pick} options={view.ranges.map((r) => ({ value: r.id, label: r.label }))} />
        )}
      </header>
      {none ? <p className={css.relaysNone}>{t("web-pages.admin.relays.none")}</p> : <Failed error={error} />}
      {!view ? !error && <Waiting sample={<div className={css.relays}>{SAMPLE_RELAYS.map((r) => <RelayCard key={r.url} relay={r} />)}</div>} /> : !none && (
        <div className={css.relays}>{view.relays.map((r) => <RelayCard key={r.url} relay={r} />)}</div>
      )}
    </div>
  );
}

function RelayCard({ relay }: { relay: Relay }) {
  return (
    <section className={`${pagesCss.card} ${css.relay}`} aria-label={relay.name}>
      <div className={css.relayHead}>
        <StatusDot state={relay.state} />
        <b>{relay.name}</b>
        <span className={css.relaySeen}>{relay.seen}</span>
      </div>
      {relay.numbers.length > 0 && (
        <dl className={css.relayNumbers}>
          {relay.numbers.map((n) => (
            <div key={n.label}><dt>{n.label}</dt><dd data-tone={n.tone}>{n.value}</dd></div>
          ))}
        </dl>
      )}
      {relay.charts.map((c) => <LoadChart key={c.id} chart={c} ticks={relay.ticks} />)}
    </section>
  );
}

/** Each series' line, in a fixed order (the first blue, the second the accent): the same series the same colour in every chart. */
const SERIES = [css.seriesFirst, css.seriesSecond];

/**
 * One chart of a relay's load: a line for each series (a lone one with a faint wash under it: two washes over each
 * other only muddy), from 0 at the foot to the highest value of any of its series at the top (its peak, said above
 * it); a gap where a bucket has no value.
 */
function LoadChart({ chart, ticks }: { chart: RelayChart; ticks: Relay["ticks"] }) {
  const n = Math.max(1, ...chart.series.map((s) => s.values.length));
  const top = Math.max(0, ...chart.series.flatMap((s) => s.values.filter((v): v is number => v !== null)));
  // Drawn in a box 0–100 across (stretched to the chart's width; the lines keep their width) and 0–100 down.
  const x = (i: number) => (n === 1 ? 50 : (i / (n - 1)) * 100);
  const y = (v: number) => (top > 0 ? 100 - (v / top) * 100 : 100);
  return (
    <figure className={css.loadChart} aria-label={`${chart.label} · ${chart.peak}`}>
      <figcaption className={css.loadHead}>
        <b>{chart.label}</b>
        {chart.series.length > 1 && chart.series.map((s, i) => <span key={s.id} className={`${css.legend} ${SERIES[i % SERIES.length]}`}>{s.label}</span>)}
        <span className={css.peak}>{chart.peak}</span>
      </figcaption>
      <div className={css.plot}>
        <svg viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
          <line className={css.rule} x1="0" x2="100" y1="0" y2="0" vectorEffect="non-scaling-stroke" />
          <line className={css.rule} x1="0" x2="100" y1="100" y2="100" vectorEffect="non-scaling-stroke" />
          {chart.series.map((s, i) => {
            const runs = stretches(s.values);
            return (
              <g key={s.id} className={SERIES[i % SERIES.length]}>
                {chart.series.length === 1 && <path className={css.wash} d={runs.map((r) => `M${x(r.from)} 100${r.values.map((v, k) => `L${x(r.from + k)} ${y(v)}`).join("")}L${x(r.from + r.values.length - 1)} 100Z`).join("")} />}
                <path className={css.trace} vectorEffect="non-scaling-stroke"
                  d={runs.map((r) => `M${x(r.from)} ${y(r.values[0]!)}${r.values.length === 1 ? "h0" : r.values.slice(1).map((v, k) => `L${x(r.from + k + 1)} ${y(v)}`).join("")}`).join("")} />
              </g>
            );
          })}
        </svg>
      </div>
      <div className={css.ticks} aria-hidden="true">
        {ticks.map((tk) => {
          const at = x(tk.index);
          return <span key={tk.index} style={{ left: `${at}%` }} data-edge={at < 3 ? "start" : at > 97 ? "end" : undefined}>{tk.label}</span>;
        })}
      </div>
    </figure>
  );
}

/** A series' values in the stretches between its gaps (null). */
function stretches(values: (number | null)[]): { from: number; values: number[] }[] {
  const out: { from: number; values: number[] }[] = [];
  values.forEach((v, i) => {
    if (v === null) return;
    const last = out.at(-1);
    if (last && last.from + last.values.length === i) last.values.push(v);
    else out.push({ from: i, values: [v] });
  });
  return out;
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
  const [granting, setGranting] = useState(false);
  const [creating, setCreating] = useState(false);
  const search = params.toString() ? `?${params}` : "";
  const detail = id && list !== "invite-codes";
  return (
    <div className={css.split} data-open={detail || undefined}>
      <div className={`${pagesCss.page} ${css.listPage}`}>
        <MobileBack to="/" label={t("web-pages.admin.title")} />
        <header className={pagesCss.pageHead}>
          <div><h1>{TITLE[list]}{view && <span className={css.total}>{view.total}</span>}</h1></div>
          {list === "invite-codes" && <Button icon={Plus} variant="primary" onClick={() => setMaking(true)}>{t("web-pages.admin.code.make")}</Button>}
          {list === "users" && <Button icon={Plus} onClick={() => setGranting(true)}>{t("web-pages.admin.pending.add")}</Button>}
          {list === "workspaces" && <Button icon={Plus} onClick={() => setCreating(true)}>{t("web-pages.admin.ws.new")}</Button>}
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
        {!view ? !error && <Waiting sample={<div className={css.list}>{sampleRows(list).map((row) => list === "invite-codes"
          ? <CodeRow key={row.id} account={account} row={row} />
          : <ItemRow key={row.id} list={list} row={row} open={false} to="" />)}</div>} />
          : view.rows.length === 0 ? (
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
      {granting && <PendingDialog account={account} search={search} onClose={() => setGranting(false)} />}
      {creating && <NewWorkspaceDialog account={account} search={search} onClose={() => setCreating(false)} />}
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
  const revoke = useAction(() => admin.revokeCode(account.sub, row.id), () => toast(t("web-pages.admin.code.revoked")));
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
              <Button variant="ghost" busy={revoke.busy} onClick={() => setRevoking(true)}>{t("web-pages.settings.members.revoke")}</Button>
            </> : <Time stamp={at} fixed />}
          </span>
        </span>
        <span className={css.rowLine2}>{row.line || (row.state === "open" ? t("web-pages.admin.expires", { until: stamp(row, "expires_at")?.until ?? "" }) : "")}</span>
      </span>
      {/* Closes at once: its button turns until the cloud has it, a failure said by toast. */}
      <Confirm open={revoking} onClose={() => setRevoking(false)} onConfirm={() => { setRevoking(false); void revoke.run(); }}
        title={t("web-pages.admin.code.revokeConfirm", { code: row.title })} action={t("web-pages.admin.code.revoke")}
        description={t("web-pages.admin.code.revokeBody")} />
    </div>
  );
}

// ── an item's page, beside its list ─────────────────────────────────────

/** An item's pane beside its list: its head (`head`), closed from its end, over what it holds; `bones`: made up, while
 * the item is read, its head and all of it in their bones. */
function Detail({ close, head, bones = false, children }: { close: string; head: React.ReactNode; bones?: boolean; children: React.ReactNode }) {
  return (
    <aside className={css.detail}>
      <MobileBack to={close} label={t("web-pages.admin.backToList")} />
      {bones ? <Waiting sample={<><div className={css.detailHead}>{head}</div>{children}</>} /> : <>
        <div className={css.detailHead}>{head}<Link className={css.close} to={close} aria-label={t("common.close")}><Close {...ICON} /></Link></div>
        {children}
      </>}
    </aside>
  );
}

// An email given rights before anyone signed in with it is listed as `email:<address>` (views/admin.ts).
const PENDING = "email:";

function UserDetail({ account, id, close, search }: { account: Account; id: string; close: string; search: string }) {
  const { value: u, error } = useKept<UserPage>({ topic: "adminItem", account: account.sub, list: "users", id });
  if (!u) return error ? <aside className={css.detail}><Failed error={error} /></aside> : <UserShown account={account} id={id} close={close} search={search} u={SAMPLE_USER} bones />;
  return <UserShown account={account} id={id} close={close} search={search} u={u} />;
}

/** A user's pane (`u`): how they came in, when, their workspaces; what they may do, and blocking them. */
function UserShown({ account, id, close, search, u, bones = false }: { account: Account; id: string; close: string; search: string; u: UserPage; bones?: boolean }) {
  const toast = useToast();
  const navigate = useNavigate();
  const email = id.startsWith(PENDING) ? id.slice(PENDING.length) : null;
  const mayCreate = useAction<boolean, unknown>((on) => email !== null ? admin.setPending(account.sub, email, { may_create: on }) : admin.setMayCreate(account.sub, id, on),
    (_, on) => toast(on ? t("web-pages.admin.user.mayCreateOn") : t("web-pages.admin.user.mayCreateOff")));
  const beta = useAction<boolean, unknown>((on) => email !== null ? admin.setPending(account.sub, email, { beta: on }) : admin.setBeta(account.sub, id, on),
    (_, on) => toast(on ? t("web-pages.admin.user.betaOn") : t("web-pages.admin.user.betaOff")));
  const remove = useAction(() => admin.removePending(account.sub, email ?? ""), () => { toast(t("web-pages.admin.pending.removed")); navigate(close); });
  const [blocking, setBlocking] = useState(false);
  const block = useAction((on: boolean) => admin.block(account.sub, id, on), (_, on) => toast(on ? t("web-pages.admin.user.blocked") : t("web-pages.admin.user.unblocked")));
  return (
    <Detail close={close} bones={bones} head={<>
      <Avatar account={u.person} size={40} />
      <span className={css.detailTitle}><b>{u.title}</b><span>{u.pending ? u.admission : u.email}</span></span>
    </>}>
      {u.pending ? (
        <dl className={css.kv}>
          <dt>{t("web-pages.admin.user.admission")}</dt><dd>{u.admission}<span className={shellCss.muted}> · {t("web-pages.admin.pending.lead")}</span></dd>
          <dt>{t("web-pages.admin.pending.addedAt")}</dt><dd><Time stamp={stamp(u, "created_at")} /></dd>
        </dl>
      ) : <>
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
      </>}
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
              : <Button variant="danger" busy={block.busy} onClick={() => setBlocking(true)}>{t("web-pages.admin.user.block")}</Button>}
          </div>
        )}
        {u.pending && (
          <div className={css.actions}>
            <Button busy={remove.busy} onClick={() => remove.run()}>{t("web-pages.admin.pending.remove")}</Button>
          </div>
        )}
        {block.error && <p className={controlsCss.fieldError} role="alert">{block.error.message}</p>}
      </>}
      {/* Closes at once: the block button turns until the cloud has it, a failure said by toast. */}
      <Confirm open={blocking} onClose={() => setBlocking(false)} onConfirm={() => { setBlocking(false); void block.run(true); }}
        title={t("web-pages.admin.user.blockConfirm", { name: u.title })} action={t("web-pages.admin.user.block")}
        description={t("web-pages.admin.user.blockBody")} />
    </Detail>
  );
}

function WorkspaceDetail({ account, id, close }: { account: Account; id: string; close: string }) {
  const { value: w, error } = useKept<WorkspacePage>({ topic: "adminItem", account: account.sub, list: "workspaces", id });
  if (!w) return error ? <aside className={css.detail}><Failed error={error} /></aside> : <WorkspaceShown account={account} id={id} close={close} w={SAMPLE_WORKSPACE} bones />;
  return <WorkspaceShown account={account} id={id} close={close} w={w} />;
}

/** A workspace's pane (`w`): who made it, its plan, its people, stations and invitations; adding a station, its limits, deleting it. */
function WorkspaceShown({ account, id, close, w, bones = false }: { account: Account; id: string; close: string; w: WorkspacePage; bones?: boolean }) {
  const toast = useToast();
  const navigate = useNavigate();
  const [deleting, setDeleting] = useState(false);
  const [enrolling, setEnrolling] = useState(false);
  const [limiting, setLimiting] = useState(false);
  const remove = useAction(() => admin.deleteWorkspace(account.sub, id), () => toast(t("web-pages.settings.workspace.deleted")));
  return (
    <Detail close={close} bones={bones} head={<>
      <span className={`${css.wsMark} ${css.wsMarkLarge}`}>{[...w.title][0]}</span>
      <span className={css.detailTitle}><b>{w.title}</b><span className={shellCss.mono}>{w.id}</span></span>
    </>}>
      <dl className={css.kv}>
        <dt>{t("web-pages.chat.info.created")}</dt><dd>{w.creator ? <Link className={css.link} to={`${PATH.users}/${encodeURIComponent(w.creator.id)}`}>{w.creator.title}</Link> : t("web-pages.admin.ws.gone")} · <Time stamp={stamp(w, "created_at")} /></dd>
        {w.plan && <><dt>{t("web-pages.admin.ws.plan")}</dt><dd>{w.plan}</dd></>}
        <dt>{t("web-pages.admin.ws.people")}</dt><dd>{w.people}</dd>
        {w.stationCount !== undefined && <><dt>Station</dt><dd>{w.stationCount}</dd></>}
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
      {w.added && w.added.length > 0 && <>
        <div className={css.group}>{t("web-pages.admin.ws.added", { n: w.added.length })}</div>
        {w.added.map((a) => (
          <div key={a.id} className={css.line}>
            <span className={css.grow}>{a.email}</span>
            <span className={css.lineAside}>{a.line}</span>
          </div>
        ))}
      </>}
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
      <div className={css.actions}>
        {w.enrollable && <Button icon={Plus} onClick={() => setEnrolling(true)}>{t("web-pages.admin.ws.addStation")}</Button>}
        {w.limits && <Button onClick={() => setLimiting(true)}>{t("web-pages.admin.ws.limits")}</Button>}
        <Button variant="danger" onClick={() => setDeleting(true)}>{t("web-pages.settings.workspace.delete")}</Button>
      </div>
      {enrolling && <EnrollDialog account={account} workspace={id} onClose={() => setEnrolling(false)} />}
      {limiting && w.limits && <LimitsDialog account={account} workspace={id} limits={w.limits} onClose={() => setLimiting(false)} />}
      {/* Back to the list at once: it goes on by itself, a failure said by toast. */}
      <Confirm open={deleting} onClose={() => setDeleting(false)} onConfirm={() => { setDeleting(false); void navigate(close, { replace: true }); void remove.run(); }}
        title={t("web-pages.settings.workspace.deleteConfirm", { name: w.title })} action={t("web-pages.settings.workspace.delete")}
        description={t("web-pages.admin.ws.deleteBody")} />
    </Detail>
  );
}

function FeedbackDetail({ account, id, close }: { account: Account; id: string; close: string }) {
  const { value: f, error } = useKept<FeedbackPage>({ topic: "adminItem", account: account.sub, list: "feedback", id });
  if (!f) return error ? <aside className={css.detail}><Failed error={error} /></aside> : <FeedbackShown account={account} id={id} close={close} f={SAMPLE_FEEDBACK} bones />;
  return <FeedbackShown account={account} id={id} close={close} f={f} />;
}

/** A bug report's pane (`f`): its status, copied whole; when, where and from whom; what it says, its context and logs. */
function FeedbackShown({ account, id, close, f, bones = false }: { account: Account; id: string; close: string; f: FeedbackPage; bones?: boolean }) {
  const toast = useToast();
  const status = useAction((to: FeedbackStatus) => admin.feedbackStatus(account.sub, id, to), (_, to) => toast(t("web-pages.admin.fb.marked", { status: f.statuses.find((s) => s.id === to)?.label ?? to })));
  const copy = () => void navigator.clipboard.writeText(f.text).then(() => toast(t("web-pages.admin.fb.copied")), () => toast(t("web-pages.admin.fb.copyFailed")));
  return (
    <Detail close={close} bones={bones} head={
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
  const [beta, setBeta] = useState(false);
  const make = useAction(() => admin.createCode(account.sub, note, Number(days), beta));
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
          <SwitchRow title={t("web-pages.admin.code.beta")} description={t("web-pages.admin.code.betaHint")} checked={beta} onChange={setBeta} />
        </>
      )}
      {make.error && <p className={controlsCss.fieldError} role="alert">{make.error.message}</p>}
    </Dialog>
  );
}

/** Gives an email rights before anyone signed in with it; opens its page (an account's, if one has signed in with it). */
function PendingDialog({ account, search, onClose }: { account: Account; search: string; onClose(): void }) {
  const toast = useToast();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [beta, setBeta] = useState(true);
  const [mayCreate, setMayCreate] = useState(false);
  // Only what is switched on: an account already signed in with the email keeps what it has besides.
  const add = useAction(() => admin.setPending(account.sub, email, { ...(beta ? { beta } : {}), ...(mayCreate ? { may_create: mayCreate } : {}) }), (made) => {
    toast(made.sub !== null ? t("web-pages.admin.pending.known") : t("web-pages.admin.pending.added"));
    navigate(`${PATH.users}/${encodeURIComponent(made.sub ?? `${PENDING}${made.email}`)}${search}`);
    onClose();
  });
  const ready = email.trim() !== "" && (beta || mayCreate) && !add.busy;
  return (
    <Dialog open onClose={onClose} title={t("web-pages.admin.pending.add")} description={t("web-pages.admin.pending.addLead")}
      footer={<>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" busy={add.busy} disabled={!ready} onClick={() => add.run()}>{t("web-pages.admin.pending.addShort")}</Button>
      </>}>
      <Field label={t("web-pages.admin.pending.email")} htmlFor="pending-email">
        <input id="pending-email" className={controlsCss.input} type="email" value={email} autoFocus maxLength={255} placeholder="name@example.com" onChange={(e) => setEmail(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && ready) add.run(); }} />
      </Field>
      <SwitchRow title={t("web-pages.admin.user.beta")} description={t("web-pages.admin.user.betaHint")} checked={beta} onChange={setBeta} />
      <SwitchRow title={t("web-pages.admin.user.mayCreate")} description={t("web-pages.admin.pending.mayCreateHint")} checked={mayCreate} onChange={setMayCreate} />
      {add.error && <p className={controlsCss.fieldError} role="alert">{add.error.message}</p>}
    </Dialog>
  );
}

// ── a workspace made for a company ──────────────────────────────────────

/** Whole numbers from 1 to the most the cloud takes (directory.ts LIMITS_MAX), or null. */
const limit = (text: string, max: number): number | null => (/^[0-9]{1,4}$/.test(text.trim()) && Number(text) >= 1 && Number(text) <= max ? Number(text) : null);
const MAX = { members: 1000 };

function LimitFields({ members, setMembers, submit }: { members: string; setMembers(v: string): void; submit(): void }) {
  const enter = (e: React.KeyboardEvent) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) submit(); };
  return (
    <>
      <Field label={t("web-pages.admin.ws.memberLimit")} htmlFor="limit-members" hint={t("web-pages.admin.ws.limitHint", { max: MAX.members })}>
        <input id="limit-members" className={controlsCss.input} inputMode="numeric" value={members} onChange={(e) => setMembers(e.target.value)} onKeyDown={enter} />
      </Field>
      <Field label={t("web-pages.admin.ws.stationLimit")} htmlFor="limit-stations" hint={t("web-pages.admin.ws.stationFixed", { n: STATIONS_PER_WORKSPACE })}>
        <input id="limit-stations" className={controlsCss.input} value={STATIONS_PER_WORKSPACE} readOnly />
      </Field>
    </>
  );
}

/** Makes a workspace for a company: its name, its owners by email, its limits; opens its page. */
function NewWorkspaceDialog({ account, search, onClose }: { account: Account; search: string; onClose(): void }) {
  const toast = useToast();
  const navigate = useNavigate();
  const [name, setName] = useState("");
  const [owners, setOwners] = useState("");
  const [members, setMembers] = useState("20");
  const emails = owners.split(/[\s,，;；]+/).filter(Boolean);
  const cap = limit(members, MAX.members);
  const create = useAction(() => admin.createWorkspace(account.sub, { name: name.trim(), owners: emails, members: cap!, stations: STATIONS_PER_WORKSPACE }), (made) => {
    toast(t("web-pages.admin.ws.created"));
    navigate(`${PATH.workspaces}/${encodeURIComponent(made.id)}${search}`);
    onClose();
  });
  const ready = name.trim() !== "" && emails.length > 0 && cap !== null && !create.busy;
  const submit = () => { if (ready) create.run(); };
  return (
    <Dialog open onClose={onClose} title={t("web-pages.admin.ws.new")} description={t("web-pages.admin.ws.newLead")}
      footer={<>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" busy={create.busy} disabled={!ready} onClick={submit}>{t("web-pages.admin.ws.create")}</Button>
      </>}>
      <Field label={t("web-pages.admin.ws.name")} htmlFor="ws-name">
        <input id="ws-name" className={controlsCss.input} value={name} autoFocus maxLength={80} onChange={(e) => setName(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) submit(); }} />
      </Field>
      <Field label={t("web-pages.admin.ws.owners")} htmlFor="ws-owners" hint={t("web-pages.admin.ws.ownersHint")}>
        <input id="ws-owners" className={controlsCss.input} inputMode="email" autoComplete="off" spellCheck={false} value={owners} placeholder="name@example.com" onChange={(e) => setOwners(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) submit(); }} />
      </Field>
      <LimitFields members={members} setMembers={setMembers} submit={submit} />
      {create.error && <p className={controlsCss.fieldError} role="alert">{create.error.message}</p>}
    </Dialog>
  );
}

function LimitsDialog({ account, workspace, limits, onClose }: { account: Account; workspace: string; limits: { members: number; stations: number | null }; onClose(): void }) {
  const toast = useToast();
  const [members, setMembers] = useState(String(limits.members));
  const cap = limit(members, MAX.members);
  const save = useAction(() => admin.setLimits(account.sub, workspace, { members: cap!, stations: STATIONS_PER_WORKSPACE }), () => { toast(t("web-pages.admin.ws.limitsSaved")); onClose(); });
  const ready = cap !== null && !save.busy;
  const submit = () => { if (ready) save.run(); };
  return (
    <Dialog open onClose={onClose} title={t("web-pages.admin.ws.limits")} description={t("web-pages.admin.ws.limitsLead")}
      footer={<>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" busy={save.busy} disabled={!ready} onClick={submit}>{t("common.save")}</Button>
      </>}>
      <LimitFields members={members} setMembers={setMembers} submit={submit} />
      {save.error && <p className={controlsCss.fieldError} role="alert">{save.error.message}</p>}
    </Dialog>
  );
}

/** A station's install command for the workspace, the admin not in it: its name first. */
function EnrollDialog({ account, workspace, onClose }: { account: Account; workspace: string; onClose(): void }) {
  const [name, setName] = useState("");
  const make = useAction(() => admin.enroll(account.sub, workspace, name.trim()));
  const made = make.result;
  const ready = name.trim() !== "" && !make.busy;
  return (
    <Dialog open onClose={onClose} wide title={t("web-pages.admin.ws.addStation")} description={made ? t("web-pages.admin.ws.commandLead") : t("web-pages.admin.ws.addStationLead")}
      footer={made ? <Button variant="primary" onClick={onClose}>{t("common.done")}</Button> : <>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" busy={make.busy} disabled={!ready} onClick={() => make.run()}>{t("web-pages.admin.ws.makeCommand")}</Button>
      </>}>
      {made ? (
        <Field label={t("web-pages.settings.enroll.run")}><div className={css.command}><CopyCommand text={made.install} /></div></Field>
      ) : (
        <Field label={t("web-pages.admin.ws.stationName")} htmlFor="station-name">
          <input id="station-name" className={controlsCss.input} value={name} autoFocus maxLength={80} placeholder="Mac mini" onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && ready) make.run(); }} />
        </Field>
      )}
      {make.error && <p className={controlsCss.fieldError} role="alert">{make.error.message}</p>}
    </Dialog>
  );
}
