// A workspace in ember cloud: every station's chats and connects in one
// place. The core reaches each station and puts the workspace's views
// together (docs/client-core.md); a page opened from the sidebar talks to the
// station the item belongs to (StationContext).
import { ChevronRight, ChevronsUpDown, Plus, Settings, UserPlus } from "../icons.tsx";
import { NewChat } from "../NewChat.tsx";
import { lastChat, useRememberChat } from "../lastChat.ts";
import { DropdownMenu } from "radix-ui";
import { useEffect, useMemo, useState } from "react";
import { Link, Navigate, NavLink, Route, Routes, useLocation, useNavigate, useParams } from "react-router";
import { useChats, useStations } from "../api.ts";
import type { Topic } from "../core/client.ts";
import { useTopics } from "../core/react.ts";
import { AccountPage } from "../pages/Accounts.tsx";
import { ConnectPage } from "../pages/Connect.tsx";
import { ChatPage } from "../pages/ChatPage.tsx";
import { ChatList, StationTrouble } from "../Sidebar.tsx";
import { OpenJobs } from "../OpenJobs.tsx";
import { GlobalShortcuts } from "../Switcher.tsx";
import { ShortcutsPage } from "../Shortcuts.tsx";
import { CHANGEABLE } from "../keymap.ts";
import { ArchivePage } from "../pages/Archive.tsx";
import { AppearancePage } from "../pages/Appearance.tsx";
import { AccountSettings, ConnectsSettings, FirstStation, MemorySettings, ROLE_LABEL, RuntimeSettings, SettingsNav, StationsSettings, WorkspaceSettings } from "./settings.tsx";
import { PeopleContext, profilesPage, StationContext, stationBase, type Station } from "../station.tsx";
import { useToast } from "../toast.tsx";
import { Button, Dialog, Empty, Field, ICON, Loading, ResizeHandle, Select, Tip } from "../ui.tsx";
import { toMadeChat } from "../Chat.tsx";
import { ComposerDock } from "../dock.tsx";
import { Previews } from "../Previews.tsx";
import { signIn, useAccounts, type Account } from "./accounts.ts";
import { cloud, errorText, forgetInviteCode, inviteCode, needsInviteCode, useAction, useWorkspace, useWorkspaces, type PendingInvitation } from "./api.ts";
import { Illustration, PageBrand, SidebarBrand } from "../brand.tsx";
import { identify, track } from "../telemetry.ts";
import * as nav from "../Sidebar.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./workspace.css.ts";
import * as chatCss from "../styles/chat.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as controlsCss from "../styles/controls.css.ts";

/** The workspace in view and the signed-in account that reaches it. */
export interface WorkspaceEntry { id: string; name: string; account: Account }

interface InvitationEntry extends PendingInvitation { account: Account }

export function WorkspaceShell({ entry }: { entry: WorkspaceEntry }) {
  const view = useWorkspace(entry.id).value;
  const found = useStations(entry.id);
  const stations = useMemo<Station[]>(() => (found.value ?? []).map((s) => ({
    id: s.id, name: s.name, online: s.online,
    address: s.station, base: stationBase(s.station), settings: `/w/${entry.id}/settings`,
  })), [found.value, entry.id]);
  const path = useLocation().pathname;
  const navigate = useNavigate();
  useRememberChat(entry.id, (p) => /^\/w\/[^/]+\/(new|s\/[^/]+\/chats\/.+)$/.test(p));
  const detail = /\/(s\/[^/]+\/.+|settings|new$|archive$)/.test(path);
  // Settings, a connect or a station's runtime accounts: the sidebar becomes the settings menu.
  const settings = /^\/w\/[^/]+\/(settings|s\/[^/]+\/(connects|settings))(\/|$)/.test(path);
  const people = useMemo(() => new Map((view?.members ?? []).map((m) => [m.email.toLowerCase(), { name: m.name, email: m.email, picture: m.picture }])), [view]);
  useEffect(() => identify(entry.account), [entry.account]);
  useEffect(() => window.stillfailDesktop?.inWorkspace(entry.account.sub, entry.id), [entry.account.sub, entry.id]);
  // The views the workspace's pages and settings show, subscribed from the start: a page opened the first time draws at
  // once, with no frame waiting for the core's first answer. What the core keeps in sync is its own call (sync.rs);
  // these only read it.
  useTopics<unknown>([
    { topic: "connects", scope: entry.id, mine: false },
    { topic: "connects", scope: entry.id, mine: true },
    { topic: "chats", scope: entry.id, mine: false },
    { topic: "chats", scope: entry.id, mine: true },
    { topic: "loginSessions", account: entry.account.sub },
    ...(found.value ?? []).map((s): Topic => ({ topic: "overview", station: s.station })),
  ]);

  // No station yet: nothing of the workspace's pages works, so none is shown; adding the first station is the page.
  if (found.value && found.value.length === 0 && !settings) return <Onboarding entry={entry} />;

  return (
    <PeopleContext.Provider value={people}>
      <div className={shellCss.shell} data-detail={detail}>
        {settings
          ? <nav className={nav.sidebar} aria-label="设置"><ResizeHandle variable="--sidebar-w" edge="right" min={180} max={480} label="调整侧边栏宽度" /><div className={`${nav.brand} ${nav.brandCompact}`}><SidebarBrand /></div><SettingsNav entry={entry} /><div className={nav.navFoot}><WorkspaceSwitcher current={entry} /></div></nav>
          : <WorkspaceSidebar entry={entry} />}
        <GlobalShortcuts scope={entry.id} newChat={`/w/${entry.id}/new`} settings={`/w/${entry.id}/settings`} />
        <main className={shellCss.main}>
          <ComposerDock>
          <Routes>
            <Route index element={<WorkspaceHome id={entry.id} stations={found.value && stations} />} />
            <Route path="settings" element={<Navigate to="stations" replace />} />
            <Route path="settings/appearance" element={<AppearancePage back={`/w/${entry.id}/settings`} />} />
            {CHANGEABLE && <Route path="settings/shortcuts" element={<ShortcutsPage back={`/w/${entry.id}/settings`} />} />}
            <Route path="settings/account" element={<AccountSettings entry={entry} />} />
            <Route path="settings/workspace" element={<WorkspaceSettings entry={entry} />} />
            {/* Pages the workspace page took in: links to them still land there. */}
            <Route path="settings/general" element={<Navigate to={`/w/${entry.id}/settings/workspace`} replace />} />
            <Route path="settings/members" element={<Navigate to={`/w/${entry.id}/settings/workspace`} replace />} />
            <Route path="settings/stations" element={<StationsSettings entry={entry} />} />
            <Route path="settings/connects" element={<ConnectsSettings entry={entry} />} />
            <Route path="settings/profiles" element={<RuntimeSettings entry={entry} />} />
            <Route path="settings/memory" element={<MemorySettings entry={entry} />} />
            <Route path="settings/leave" element={<Navigate to={`/w/${entry.id}/settings/workspace`} replace />} />
            <Route path="s/:station/*" element={<StationPages stations={found.value && stations} />} />
            <Route path="archive" element={<ArchivePage scope={entry.id} back={`/w/${entry.id}`} />} />
            <Route path="new" element={<NewChat scope={entry.id} onCreated={(station, session) => toMadeChat(() => navigate(`${stationBase(station)}/chats/${encodeURIComponent(session)}`))} />} />
            <Route path="*" element={<Navigate to={`/w/${entry.id}`} replace />} />
          </Routes>
          </ComposerDock>
        </main>
        <Previews />
      </div>
    </PeopleContext.Provider>
  );
}

/** `stations` is undefined until the core has listed them: until then nothing is said (least of all "no such station"). */
function StationPages({ stations }: { stations: Station[] | undefined }) {
  const { station: id } = useParams();
  if (!stations) return null;
  const station = stations.find((s) => s.id === id);
  if (!station) return <Empty><p>这个 workspace 里没有这台 station。</p></Empty>;
  // Offline, its pages still show what the core kept of it; the core says where nothing can be done.
  return (
    <StationContext.Provider value={station}>
      <Routes>
        <Route path="chats/:chat?" element={<ChatPage />} />
        <Route path="connects/:id" element={<ConnectPage />} />
        {/* One Profile page for the workspace: a station's own list is it. */}
        <Route path="settings/accounts" element={<Navigate to={profilesPage(station)} replace />} />
        <Route path="settings/accounts/:id" element={<AccountPage />} />
        <Route path="*" element={<Navigate to="chats" replace />} />
      </Routes>
    </StationContext.Provider>
  );
}

/**
 * A workspace with no station: what a station is and adding the first one, in the page; the workspace switcher (the
 * account, other workspaces) and the workspace's settings (inviting people) stay at hand. Its pages come once a station
 * has joined.
 */
function Onboarding({ entry }: { entry: WorkspaceEntry }) {
  return (
    <div className={css.onboarding}>
      <header className={css.onboardingBar}>
        <div className={`${nav.brand} ${nav.brandCompact}`}><PageBrand /></div>
        <div className={css.onboardingAccount}><WorkspaceSwitcher current={entry} /></div>
      </header>
      <main className={css.onboardingMain}>
        <Illustration name="no-station" />
        <h1 className={css.onboardingTitle}>添加第一台 station</h1>
        <p className={css.onboardingLead}>agent 在你的机器上干活。先把一台 Mac 或 Linux 机器加进来。</p>
        <FirstStation entry={entry} />
        <p className={`${css.onboardingFoot} ${shellCss.muted}`}>
          <Link className={chatCss.inlineLink} to={`/w/${entry.id}/settings/workspace`}>邀请成员</Link>
          <span aria-hidden="true"> · </span>
          <Link className={chatCss.inlineLink} to={`/w/${entry.id}/settings/workspace`}>workspace 设置</Link>
        </p>
      </main>
    </div>
  );
}

/** `stations` is undefined until the core has listed them. */
function WorkspaceHome({ id, stations }: { id: string; stations: Station[] | undefined }) {
  if (!stations) return <Loading label="正在读取 workspace…" />;
  // With stations there is always a chat in view: the one last open, or a new one.
  if (stations.length) return <Navigate to={lastChat(id, `/w/${id}/new`)} replace />;
  return (
    <Empty>
      <Illustration name="no-station" />
      <h2>这个 workspace 还没有 station</h2>
      <p>到 <Link className={chatCss.inlineLink} to={`/w/${id}/settings/stations`}>设置 → Station</Link> 里添加一台 station：在要运行 still.fail 的机器上执行一条命令即可。</p>
    </Empty>
  );
}

// ── sidebar ─────────────────────────────────────────────────────────────

function WorkspaceSidebar({ entry }: { entry: WorkspaceEntry }) {
  return (
    <nav className={nav.sidebar} aria-label="导航">
      <ResizeHandle variable="--sidebar-w" edge="right" min={180} max={480} label="调整侧边栏宽度" />
      <div className={`${nav.brand} ${nav.brandCompact}`}><SidebarBrand /></div>
      <ChatList scope={entry.id} newChat={`/w/${entry.id}/new`} stationsPage={`/w/${entry.id}/settings/stations`} archive={`/w/${entry.id}/archive`} />
      <div className={nav.navFoot}>
        <StationTrouble scope={entry.id} to={`/w/${entry.id}/settings/stations`} />
        <WorkspaceOpenJobs scope={entry.id} />
        <div className={nav.navFootRow}>
          <WorkspaceSwitcher current={entry} />
          <Tip label="设置" side="top"><NavLink className={pagesCss.iconBtn} to={`/w/${entry.id}/settings`} aria-label="设置"><Settings {...ICON} /></NavLink></Tip>
        </div>
      </div>
    </nav>
  );
}

/** The services and jobs left up a long while on the workspace's stations that are online, each marked with its station's name when there are several. */
function WorkspaceOpenJobs({ scope }: { scope: string }) {
  const stations = useChats(scope, false).value?.stations ?? [];
  const several = stations.length > 1;
  const online = useMemo(() => stations.filter((s) => s.state === "online").map((s) => ({ address: s.station, ...(several ? { name: s.name } : {}) })),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [stations.map((s) => `${s.station}\t${s.name}\t${s.state}`).join("\n")]);
  return <OpenJobs stations={online} />;
}

/** At the sidebar's foot: the workspace in view, which account it belongs to, and the others. */
function WorkspaceSwitcher({ current }: { current: WorkspaceEntry }) {
  const byAccount = useWorkspaces().value ?? [];
  const list = useAccounts() ?? [];
  const navigate = useNavigate();
  const toast = useToast();
  const [creating, setCreating] = useState(false);
  const respond = useAction(
    ({ invite, accept }: { invite: InvitationEntry; accept: boolean }) =>
      accept ? cloud.acceptInvitationById(invite.account.sub, invite.id) : cloud.declineInvitation(invite.account.sub, invite.id).then(() => null),
    (joined, { invite }) => {
      if (joined) { toast(`已加入「${invite.name}」`); navigate(`/w/${joined.id}`); } else toast("已忽略邀请");
    },
  );
  const pending = byAccount.flatMap((a) => a.invitations.map((i): InvitationEntry => ({ ...i, account: a.account })));
  const isCurrent = (sub: string, id: string) => id === current.id && sub === current.account.sub;
  const shown = byAccount.find((a) => a.account.sub === current.account.sub)?.workspaces.find((w) => w.id === current.id);
  const others = byAccount.flatMap(({ account, workspaces: items }) => items.filter((w) => !isCurrent(account.sub, w.id)).map((w) => ({ account, w })));
  return (
    <>
      <DropdownMenu.Root modal={false}>
        <DropdownMenu.Trigger asChild>
          <button type="button" className={css.accountTrigger}>
            <span className={css.accountText}>
              <span className={css.accountName}>{current.name}</span>
            </span>
            {pending.length > 0 && <span className={css.inviteDot} role="img" aria-label={`${pending.length} 个邀请`} />}
            <ChevronsUpDown {...ICON} size={14} />
          </button>
        </DropdownMenu.Trigger>
        <DropdownMenu.Portal>
          <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList} ${css.accountMenu}`} side="top" align="start" sideOffset={6}>
            {/* The workspace in use first, as what the menu is about (as on the phone): its settings open from it. */}
            {shown && (
              <DropdownMenu.Item className={`${controlsCss.menuItem} ${css.menuCurrent}`} onSelect={() => navigate(`/w/${current.id}/settings/workspace`)}>
                <span className={css.menuCurrentText}>
                  <b>{shown.name}</b>
                  <span className={shellCss.muted}>你是{ROLE_LABEL[shown.role]} · {shown.stations} 台 station · {shown.members} 人</span>
                  {byAccount.length > 1 && <span className={shellCss.muted}>{current.account.email}</span>}
                </span>
                <span className={css.menuCurrentGo}>设置<ChevronRight {...ICON} size={14} /></span>
              </DropdownMenu.Item>
            )}
            {pending.length > 0 && (
              <>
                <DropdownMenu.Label className={controlsCss.menuLabel}>邀请</DropdownMenu.Label>
                {pending.map((invite) => (
                  <div key={invite.id} className={css.menuInvite}>
                    <span className={css.threadItem}>
                      <span>{invite.inviter || "有人"}邀请你加入「{invite.name}」</span>
                      <span className={shellCss.muted}>{invite.account.email}{list.length > 1 ? "" : ""}</span>
                    </span>
                    <span className={css.menuInviteActions}>
                      <DropdownMenu.Item className={`${controlsCss.btn} ${controlsCss.btnPrimary} ${css.menuInviteBtn}`} onSelect={() => respond.run({ invite, accept: true })}>加入</DropdownMenu.Item>
                      <DropdownMenu.Item className={`${controlsCss.btn} ${controlsCss.btnGhost} ${css.menuInviteBtn}`} onSelect={() => respond.run({ invite, accept: false })}>忽略</DropdownMenu.Item>
                    </span>
                  </div>
                ))}
                <DropdownMenu.Separator className={controlsCss.menuSep} />
              </>
            )}
            {others.length > 0 && <DropdownMenu.Label className={controlsCss.menuLabel}>切换到</DropdownMenu.Label>}
            {/* Each workspace says whose it is under its name (a heading per account read as something to pick), what it holds at its end. */}
            {others.map(({ account, w }) => (
              <DropdownMenu.Item key={w.id} className={controlsCss.menuItem} onSelect={() => navigate(`/w/${w.id}`)}>
                <span className={css.menuWorkspace}>
                  <span>{w.name}</span><span className={css.menuStat}>{w.stations} 台 station</span>
                  {byAccount.length > 1 ? <span className={shellCss.muted}>{account.email}</span> : <span />}<span className={css.menuStat}>{w.members} 人</span>
                </span>
              </DropdownMenu.Item>
            ))}
            <DropdownMenu.Separator className={controlsCss.menuSep} />
            <DropdownMenu.Item className={controlsCss.menuItem} onSelect={() => setCreating(true)}><Plus {...ICON} />新建 workspace</DropdownMenu.Item>
            <DropdownMenu.Item className={controlsCss.menuItem} onSelect={() => void signIn()}><UserPlus {...ICON} />添加另一个账号</DropdownMenu.Item>
          </DropdownMenu.Content>
        </DropdownMenu.Portal>
      </DropdownMenu.Root>
      <NewWorkspaceDialog open={creating} onClose={() => setCreating(false)} />
    </>
  );
}

function NewWorkspaceDialog({ open, onClose }: { open: boolean; onClose(): void }) {
  const list = useAccounts() ?? [];
  const navigate = useNavigate();
  const [name, setName] = useState("");
  const [owner, setOwner] = useState(list[0]?.sub ?? "");
  // Sent every time: the server looks at it only for an account not let in yet, and then asks for it when it is missing or wrong.
  const [code, setCode] = useState(inviteCode);
  const create = useAction(() => cloud.createWorkspace(owner || list[0]!.sub, name, code.trim()), (w) => { track("workspace_created", { first: false }); setName(""); forgetInviteCode(); onClose(); navigate(`/w/${w.id}`); });
  const [asked, setAsked] = useState(false);
  useEffect(() => { if (needsInviteCode(create.error)) setAsked(true); }, [create.error]);
  const asking = asked || needsInviteCode(create.error);
  return (
    <Dialog open={open} onClose={onClose} title="新建 workspace" description="workspace 是一组人和他们共用的 station。你会成为它的 owner。"
      footer={<><Button variant="ghost" onClick={onClose}>取消</Button><Button variant="primary" disabled={!name.trim()} busy={create.busy} onClick={() => create.run()}>新建</Button></>}>
      <Field label="名字" htmlFor="ws-name">
        <input id="ws-name" className={controlsCss.input} value={name} autoFocus onChange={(e) => setName(e.target.value)} placeholder="例如：产品团队" maxLength={80}
          onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && name.trim()) create.run(); }} />
      </Field>
      {list.length > 1 && (
        <Field label="属于哪个账号" htmlFor="ws-owner">
          <Select id="ws-owner" value={owner} onChange={setOwner} options={list.map((a) => ({ value: a.sub, label: a.email }))} />
        </Field>
      )}
      {asking && (
        <Field label="邀请码" htmlFor="ws-code" error={create.error && needsInviteCode(create.error) && code.trim() ? errorText(create.error) : undefined}
          hint="still.fail 目前只对受邀的人开放：这个账号还没被邀请进任何 workspace，新建需要一个邀请码。">
          <input id="ws-code" className={`${controlsCss.input} ${shellCss.mono}`} value={code} autoFocus onChange={(e) => setCode(e.target.value)} placeholder="XXXX-XXXX-XXXX" maxLength={32} spellCheck={false} autoComplete="off"
            onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && name.trim() && code.trim()) create.run(); }} />
        </Field>
      )}
      {create.error && !needsInviteCode(create.error) && <p className={controlsCss.fieldError} role="alert">{create.error.message}</p>}
    </Dialog>
  );
}

