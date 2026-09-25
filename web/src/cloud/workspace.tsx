// A workspace in ember cloud: every station's sessions, chats and connects in
// one place. Each station has its own iroh link and its own slice of the data
// cache (StationContext); the sidebar merges their sessions, and a page opened
// from it talks to the station the item belongs to.
import { useMutation, useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, ChevronsUpDown, LogOut, Plus, Settings, UserPlus } from "lucide-react";
import { DropdownMenu } from "radix-ui";
import { useMemo, useState, type ReactNode } from "react";
import { Navigate, NavLink, Route, Routes, useLocation, useNavigate, useParams } from "react-router";
import { keys, makeApi, useLiveUpdates, type Overview, type SessionSummary } from "../api.ts";
import { connectionText, dayLabel, modeShort, presence } from "../format.ts";
import { AccountPage, AccountsPage } from "../pages/Accounts.tsx";
import { ConnectPage, NewConnectDialog } from "../pages/Connect.tsx";
import { SessionPage } from "../pages/Session.tsx";
import { SessionRow, useSessionGroups } from "../Sidebar.tsx";
import { MineFilter, useOnlyMine } from "../components.tsx";
import { AccountSettings, ConnectsSettings, GeneralSettings, MembersSettings, RuntimeSettings, SettingsNav, StationsSettings } from "./settings.tsx";
import { MeContext, PeopleContext, StationContext, type Station } from "../station.tsx";
import { useToast } from "../toast.tsx";
import { Button, ConnectKindIcon, Dialog, Empty, Field, ICON, IconButton, Loading, Select, SkeletonRows, StatusDot } from "../ui.tsx";
import { signIn, signOut, type Account } from "./accounts.ts";
import { cloud, type PendingInvitation, type WorkspaceView } from "./api.ts";
export type { PendingInvitation };
import { Avatar, online, useAccounts } from "./gate.tsx";
import { StationTransport } from "./link.ts";

export interface WorkspaceEntry { id: string; name: string; account: Account; relay: string; stations: number; members: number }

export interface InvitationEntry extends PendingInvitation { account: Account }

/** What every signed-in account can reach, and the invitations waiting for their emails. */
function useMe() {
  const list = useAccounts();
  return useQuery({
    queryKey: ["cloud", "me", list.map((a) => a.sub).join(",")],
    queryFn: async () => {
      const results = await Promise.all(list.map(async (account) => ({ account, me: await cloud.me(account.sub).catch(() => null) })));
      return {
        workspaces: results.flatMap(({ account, me }) => (me?.workspaces ?? []).map((w): WorkspaceEntry => ({ id: w.id, name: w.name, stations: w.stations, members: w.members, account, relay: me!.relay_url }))),
        invitations: results.flatMap(({ account, me }) => (me?.invitations ?? []).map((i): InvitationEntry => ({ ...i, account }))),
      };
    },
    enabled: list.length > 0,
    refetchInterval: 60_000,
  });
}

/** Every workspace of every signed-in account, each with the account that reaches it. */
export function useWorkspaces() {
  const me = useMe();
  return { ...me, data: me.data?.workspaces };
}

export function useInvitations() {
  const me = useMe();
  return { ...me, data: me.data?.invitations };
}

// One link per station for the page's lifetime, whichever component asks.
const transports = new Map<string, StationTransport>();
function transportFor(sub: string, ws: string, station: string, relay: string): StationTransport {
  const key = `${sub}/${ws}/${station}`;
  let t = transports.get(key);
  if (!t) transports.set(key, (t = new StationTransport(sub, ws, station, relay)));
  return t;
}

export function WorkspaceShell({ entry }: { entry: WorkspaceEntry }) {
  const view = useQuery({
    queryKey: ["cloud", "workspace", entry.id, entry.account.sub],
    queryFn: () => cloud.workspace(entry.account.sub, entry.id),
    refetchInterval: 30_000,
  });
  const stations = useMemo<Station[]>(() => (view.data?.stations ?? []).map((s) => ({
    id: s.id, name: s.name, online: online(s),
    base: `/w/${entry.id}/s/${s.id}`, settings: `/w/${entry.id}/settings`,
    transport: transportFor(entry.account.sub, entry.id, s.id, entry.relay),
  })), [view.data, entry]);
  const path = useLocation().pathname;
  const detail = /\/(s\/[^/]+\/.+|settings)/.test(path);
  // Settings, a connect or a station's runtime accounts: the sidebar becomes the settings menu.
  const settings = /^\/w\/[^/]+\/(settings|s\/[^/]+\/(connects|settings))(\/|$)/.test(path);
  const me = useMemo(() => ({ id: entry.account.email, email: entry.account.email }), [entry.account.email]);
  const people = useMemo(() => new Map((view.data?.members ?? []).map((m) => [m.email.toLowerCase(), { name: m.name, email: m.email, picture: m.picture }])), [view.data]);

  return (
    <MeContext.Provider value={me}>
    <PeopleContext.Provider value={people}>
      <div className="shell" data-detail={detail}>
        {stations.filter((s) => s.online).map((s) => <Live key={s.id} station={s} />)}
        {settings
          ? <nav className="sidebar" aria-label="设置"><div className="account-slot"><WorkspaceSwitcher current={entry} /></div><SettingsNav entry={entry} /></nav>
          : <WorkspaceSidebar entry={entry} stations={stations} loading={view.isPending} />}
        <main className="main">
          <Routes>
            <Route index element={<WorkspaceHome view={view.data} stations={stations} />} />
            <Route path="settings" element={<Navigate to="general" replace />} />
            <Route path="settings/account" element={<AccountSettings entry={entry} />} />
            <Route path="settings/general" element={<GeneralSettings entry={entry} />} />
            <Route path="settings/members" element={<MembersSettings entry={entry} />} />
            <Route path="settings/stations" element={<StationsSettings entry={entry} stations={stations} />} />
            <Route path="settings/connects" element={<ConnectsSettings entry={entry} stations={stations} />} />
            <Route path="settings/profiles" element={<RuntimeSettings entry={entry} stations={stations} />} />
            <Route path="s/:station/*" element={<StationPages stations={stations} />} />
            <Route path="*" element={<Navigate to={`/w/${entry.id}`} replace />} />
          </Routes>
        </main>
      </div>
    </PeopleContext.Provider>
    </MeContext.Provider>
  );
}

/** Keeps one station's data current. */
function Live({ station }: { station: Station }) {
  return <StationContext.Provider value={station}><LiveInner /></StationContext.Provider>;
}
function LiveInner() {
  useLiveUpdates(true);
  return null;
}

function StationPages({ stations }: { stations: Station[] }) {
  const { station: id } = useParams();
  const station = stations.find((s) => s.id === id);
  if (!station) return <Empty><p>这个 workspace 里没有这台 station。</p></Empty>;
  if (!station.online) return <Empty><h2>「{station.name}」离线</h2><p>它最近没有和 ember cloud 联系。确认那台机器上的 ember 在运行。</p></Empty>;
  return (
    <StationContext.Provider value={station}>
      <Routes>
        <Route path="sessions/:key?" element={<SessionPage />} />
        <Route path="connects/:id" element={<ConnectPage />} />
        <Route path="settings/accounts" element={<AccountsPage />} />
        <Route path="settings/accounts/:id" element={<AccountPage />} />
        <Route path="*" element={<Navigate to="sessions" replace />} />
      </Routes>
    </StationContext.Provider>
  );
}

function WorkspaceHome({ view, stations }: { view: WorkspaceView | undefined; stations: Station[] }) {
  if (!view) return <Loading label="正在读取 workspace…" />;
  const up = stations.filter((s) => s.online).length;
  return (
    <Empty>
      <img src={`${import.meta.env.BASE_URL}ember.svg`} alt="" width={36} height={36} />
      <h2>{stations.length ? "选一个会话" : "这个 workspace 还没有 station"}</h2>
      <p>{stations.length
        ? `左边是 ${stations.length} 台 station 上的会话${up < stations.length ? `（${stations.length - up} 台离线）` : ""}，最近活动的在最上面。`
        : "到「设置」里添加一台 station：在要运行 ember 的机器上执行一条命令即可。"}</p>
    </Empty>
  );
}

// ── sidebar ─────────────────────────────────────────────────────────────

function WorkspaceSidebar({ entry, stations, loading }: { entry: WorkspaceEntry; stations: Station[]; loading: boolean }) {
  const live = stations.filter((s) => s.online);
  const sessions = useQueries({ queries: live.map((s) => ({ queryKey: keys.sessions(s.id), queryFn: () => makeApi(s.transport).sessions() })) });
  const overviews = useQueries({ queries: live.map((s) => ({ queryKey: keys.overview(s.id), queryFn: () => makeApi(s.transport).overview(), refetchInterval: 10_000 })) });
  const [onlyMine] = useOnlyMine();
  const rows = useMemo(() => live.flatMap((station, i) =>
    (sessions[i]?.data ?? []).map((session) => ({ session, station, overview: overviews[i]?.data as Overview | undefined }))), [live, sessions, overviews]);
  const groups = useSessionGroups(rows);
  const failed = live.filter((_, i) => sessions[i]?.isError);
  const connecting = live.filter((_, i) => sessions[i]?.isPending);
  const offline = stations.filter((s) => !s.online);

  return (
    <nav className="sidebar" aria-label="导航">
      <div className="account-slot"><WorkspaceSwitcher current={entry} /></div>
      <MineFilter label="会话" />
      <div className="nav-scroll">
        {connecting.map((s) => <p key={s.id} className="nav-connecting"><span className="spinner" aria-hidden="true" />正在连接 {s.name}…</p>)}
        {failed.map((s) => <p key={s.id} className="nav-empty nav-error">连不上「{s.name}」，正在重试…</p>)}
        {groups.length === 0 && (connecting.length > 0 || loading) && <SkeletonRows />}
        {offline.length > 0 && <p className="nav-empty">{offline.map((s) => s.name).join("、")} 离线，它们的会话暂时看不到。</p>}
        {groups.length === 0 && !failed.length && !connecting.length && !loading && <p className="nav-empty">{onlyMine ? "没有你发起的会话。" : stations.length ? "还没有会话。在 Slack 里 @ 它们，或者打开会话新建对话。" : "还没有 station，到「设置 → Station」添加。"}</p>}
        {groups.map((group) => (
          <section key={group.label} aria-label={group.label}>
            <div className="nav-heading">{group.label}</div>
            {group.items.map(({ session, station, overview }) => (
              <StationContext.Provider key={`${station.id}/${session.key}`} value={station}>
                <SessionRow session={session} connect={overview?.connects.find((c) => c.id === session.connect)} station={station.name} />
              </StationContext.Provider>
            ))}
          </section>
        ))}
      </div>
      <div className="nav-foot">
        <NavLink className="nav-row" to={`/w/${entry.id}/settings`}><Settings {...ICON} />设置</NavLink>
      </div>
    </nav>
  );
}

/** The sidebar's header: the workspace in view, which account it belongs to, and the others. */
function WorkspaceSwitcher({ current }: { current: WorkspaceEntry }) {
  const workspaces = useWorkspaces();
  const invitations = useInvitations();
  const list = useAccounts();
  const navigate = useNavigate();
  const toast = useToast();
  const queries = useQueryClient();
  const [creating, setCreating] = useState(false);
  const respond = useMutation({
    mutationFn: ({ invite, accept }: { invite: InvitationEntry; accept: boolean }) =>
      accept ? cloud.acceptInvitationById(invite.account.sub, invite.id) : cloud.declineInvitation(invite.account.sub, invite.id).then(() => null),
    onSuccess: (joined, { invite }) => {
      void queries.invalidateQueries({ queryKey: ["cloud"] });
      if (joined) { toast(`已加入「${invite.name}」`); navigate(`/w/${joined.id}`); } else toast("已忽略邀请");
    },
  });
  const pending = invitations.data ?? [];
  const byAccount = list.map((a) => ({ account: a, items: (workspaces.data ?? []).filter((w) => w.account.sub === a.sub) }));
  return (
    <>
      <DropdownMenu.Root modal={false}>
        <DropdownMenu.Trigger asChild>
          <button type="button" className="account-trigger">
            <span className="ws-mark" aria-hidden="true">{([...current.name][0] ?? "?").toUpperCase()}</span>
            <span className="account-text">
              <span className="account-name">{current.name}</span>
              <span className="account-email">{current.account.email}</span>
            </span>
            {pending.length > 0 && <span className="invite-dot" role="img" aria-label={`${pending.length} 个邀请`} />}
            <ChevronsUpDown {...ICON} size={14} />
          </button>
        </DropdownMenu.Trigger>
        <DropdownMenu.Portal>
          <DropdownMenu.Content className="popover menu-list account-menu" align="start" sideOffset={4}>
            {pending.length > 0 && (
              <>
                <DropdownMenu.Label className="menu-label">邀请</DropdownMenu.Label>
                {pending.map((invite) => (
                  <div key={invite.id} className="menu-invite">
                    <span className="thread-item">
                      <span>{invite.inviter || "有人"}邀请你加入「{invite.name}」</span>
                      <span className="muted">{invite.account.email}{list.length > 1 ? "" : ""}</span>
                    </span>
                    <span className="menu-invite-actions">
                      <DropdownMenu.Item className="btn btn-primary menu-invite-btn" onSelect={() => respond.mutate({ invite, accept: true })}>加入</DropdownMenu.Item>
                      <DropdownMenu.Item className="btn btn-ghost menu-invite-btn" onSelect={() => respond.mutate({ invite, accept: false })}>忽略</DropdownMenu.Item>
                    </span>
                  </div>
                ))}
                <DropdownMenu.Separator className="menu-sep" />
              </>
            )}
            {byAccount.map(({ account, items }, i) => (
              <div key={account.sub}>
                {i > 0 && <DropdownMenu.Separator className="menu-sep" />}
                <DropdownMenu.Label className="menu-label menu-account"><Avatar account={account} size={16} />{account.email}</DropdownMenu.Label>
                {items.length === 0 && <div className="menu-empty">没有 workspace</div>}
                {items.map((w) => (
                  <DropdownMenu.Item key={w.id} className="menu-item" onSelect={() => navigate(`/w/${w.id}`)}>
                    <span className="ws-mark" aria-hidden="true">{([...w.name][0] ?? "?").toUpperCase()}</span>
                    <span className="thread-item"><span>{w.name}</span><span className="muted">{w.stations} 台 station · {w.members} 人</span></span>
                    {w.id === current.id && w.account.sub === current.account.sub && <Check {...ICON} size={14} className="menu-check" />}
                  </DropdownMenu.Item>
                ))}
              </div>
            ))}
            <DropdownMenu.Separator className="menu-sep" />
            <DropdownMenu.Item className="menu-item" onSelect={() => setCreating(true)}><Plus {...ICON} />新建 workspace</DropdownMenu.Item>
            <DropdownMenu.Item className="menu-item" onSelect={() => void signIn()}><UserPlus {...ICON} />添加另一个账号</DropdownMenu.Item>
            <DropdownMenu.Sub>
              <DropdownMenu.SubTrigger className="menu-item"><LogOut {...ICON} />退出账号</DropdownMenu.SubTrigger>
              <DropdownMenu.Portal>
                <DropdownMenu.SubContent className="popover menu-list" sideOffset={6}>
                  {list.map((a) => (
                    <DropdownMenu.Item key={a.sub} className="menu-item" data-danger onSelect={() => void signOut(a.sub).then(() => { toast(`已退出 ${a.email}`); navigate("/"); })}>
                      {a.email}
                    </DropdownMenu.Item>
                  ))}
                </DropdownMenu.SubContent>
              </DropdownMenu.Portal>
            </DropdownMenu.Sub>
          </DropdownMenu.Content>
        </DropdownMenu.Portal>
      </DropdownMenu.Root>
      <NewWorkspaceDialog open={creating} onClose={() => setCreating(false)} />
    </>
  );
}

export function NewWorkspaceDialog({ open, onClose }: { open: boolean; onClose(): void }) {
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

