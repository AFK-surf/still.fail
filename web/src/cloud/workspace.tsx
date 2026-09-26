// A workspace in ember cloud: every station's chats and connects in one
// place. The core reaches each station and puts the workspace's views
// together (docs/client-core.md); a page opened from the sidebar talks to the
// station the item belongs to (StationContext).
import { Check, ChevronsUpDown, LogOut, Plus, Settings, ShieldCheck, UserPlus } from "lucide-react";
import { NewChat } from "../NewChat.tsx";
import { lastChat, useRememberChat } from "../lastChat.ts";
import { DropdownMenu } from "radix-ui";
import { useEffect, useMemo, useState } from "react";
import { Link, Navigate, NavLink, Route, Routes, useLocation, useNavigate, useParams } from "react-router";
import { useStations } from "../api.ts";
import { AccountPage, AccountsPage } from "../pages/Accounts.tsx";
import { ConnectPage } from "../pages/Connect.tsx";
import { ChatPage } from "../pages/ChatPage.tsx";
import { ChatList } from "../Sidebar.tsx";
import { AccountSettings, ConnectsSettings, GeneralSettings, LeaveSettings, MembersSettings, RuntimeSettings, SettingsNav, StationsSettings } from "./settings.tsx";
import { PeopleContext, StationContext, stationBase, type Station } from "../station.tsx";
import { useToast } from "../toast.tsx";
import { Button, Dialog, Empty, Field, ICON, Loading, ResizeHandle, Select, Tip } from "../ui.tsx";
import { signIn, signOut, useAccounts, type Account } from "./accounts.ts";
import { cloud, errorText, forgetInviteCode, inviteCode, needsInviteCode, useAction, useWorkspace, useWorkspaces, type PendingInvitation } from "./api.ts";
import { useAdminAccount } from "./admin.tsx";
import { Avatar } from "./gate.tsx";
import { Illustration, Lockup } from "../brand.tsx";

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
  const detail = /\/(s\/[^/]+\/.+|settings|new$)/.test(path);
  // Settings, a connect or a station's runtime accounts: the sidebar becomes the settings menu.
  const settings = /^\/w\/[^/]+\/(settings|s\/[^/]+\/(connects|settings))(\/|$)/.test(path);
  const people = useMemo(() => new Map((view?.members ?? []).map((m) => [m.email.toLowerCase(), { name: m.name, email: m.email, picture: m.picture }])), [view]);

  return (
    <PeopleContext.Provider value={people}>
      <div className="shell" data-detail={detail}>
        {settings
          ? <nav className="sidebar" aria-label="设置"><ResizeHandle variable="--sidebar-w" edge="right" min={180} max={480} label="调整侧边栏宽度" /><div className="brand brand-compact"><Lockup /></div><SettingsNav entry={entry} /><div className="nav-foot"><WorkspaceSwitcher current={entry} /></div></nav>
          : <WorkspaceSidebar entry={entry} />}
        <main className="main">
          <Routes>
            <Route index element={<WorkspaceHome id={entry.id} stations={found.value && stations} />} />
            <Route path="settings" element={<Navigate to="stations" replace />} />
            <Route path="settings/account" element={<AccountSettings entry={entry} />} />
            <Route path="settings/general" element={<GeneralSettings entry={entry} />} />
            <Route path="settings/members" element={<MembersSettings entry={entry} />} />
            <Route path="settings/stations" element={<StationsSettings entry={entry} />} />
            <Route path="settings/connects" element={<ConnectsSettings entry={entry} />} />
            <Route path="settings/profiles" element={<RuntimeSettings entry={entry} />} />
            <Route path="settings/leave" element={<LeaveSettings entry={entry} />} />
            <Route path="s/:station/*" element={<StationPages stations={stations} />} />
            <Route path="new" element={<NewChat scope={entry.id} onCreated={(station, thread) => navigate(`${stationBase(station)}/chats/${thread}`)} />} />
            <Route path="*" element={<Navigate to={`/w/${entry.id}`} replace />} />
          </Routes>
        </main>
      </div>
    </PeopleContext.Provider>
  );
}

function StationPages({ stations }: { stations: Station[] }) {
  const { station: id } = useParams();
  const station = stations.find((s) => s.id === id);
  if (!station) return <Empty><p>这个 workspace 里没有这台 station。</p></Empty>;
  if (!station.online) return <Empty><Illustration name="station-offline" /><h2>「{station.name}」离线</h2><p>它最近没有和 ember cloud 联系。确认那台机器上的 ember 在运行。</p></Empty>;
  return (
    <StationContext.Provider value={station}>
      <Routes>
        <Route path="chats/:thread?" element={<ChatPage />} />
        <Route path="connects/:id" element={<ConnectPage />} />
        <Route path="settings/accounts" element={<AccountsPage />} />
        <Route path="settings/accounts/:id" element={<AccountPage />} />
        <Route path="*" element={<Navigate to="chats" replace />} />
      </Routes>
    </StationContext.Provider>
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
      <p>到 <Link className="inline-link" to={`/w/${id}/settings/stations`}>设置 → Station</Link> 里添加一台 station：在要运行 ember 的机器上执行一条命令即可。</p>
    </Empty>
  );
}

// ── sidebar ─────────────────────────────────────────────────────────────

function WorkspaceSidebar({ entry }: { entry: WorkspaceEntry }) {
  return (
    <nav className="sidebar" aria-label="导航">
      <ResizeHandle variable="--sidebar-w" edge="right" min={180} max={480} label="调整侧边栏宽度" />
      <div className="brand brand-compact"><Lockup /></div>
      <ChatList scope={entry.id} newChat={`/w/${entry.id}/new`} settings={`/w/${entry.id}/settings/stations`} />
      <div className="nav-foot nav-foot-row">
        <WorkspaceSwitcher current={entry} />
        <Tip label="设置" side="top"><NavLink className="icon-btn" to={`/w/${entry.id}/settings`} aria-label="设置"><Settings {...ICON} /></NavLink></Tip>
      </div>
    </nav>
  );
}

/** At the sidebar's foot: the workspace in view, which account it belongs to, and the others. */
function WorkspaceSwitcher({ current }: { current: WorkspaceEntry }) {
  const byAccount = useWorkspaces().value ?? [];
  const list = useAccounts() ?? [];
  const navigate = useNavigate();
  const toast = useToast();
  const [creating, setCreating] = useState(false);
  const admin = useAdminAccount();
  const respond = useAction(
    ({ invite, accept }: { invite: InvitationEntry; accept: boolean }) =>
      accept ? cloud.acceptInvitationById(invite.account.sub, invite.id) : cloud.declineInvitation(invite.account.sub, invite.id).then(() => null),
    (joined, { invite }) => {
      if (joined) { toast(`已加入「${invite.name}」`); navigate(`/w/${joined.id}`); } else toast("已忽略邀请");
    },
  );
  const pending = byAccount.flatMap((a) => a.invitations.map((i): InvitationEntry => ({ ...i, account: a.account })));
  return (
    <>
      <DropdownMenu.Root modal={false}>
        <DropdownMenu.Trigger asChild>
          <button type="button" className="account-trigger">
            <span className="account-text">
              <span className="account-name">{current.name}</span>
            </span>
            {pending.length > 0 && <span className="invite-dot" role="img" aria-label={`${pending.length} 个邀请`} />}
            <ChevronsUpDown {...ICON} size={14} />
          </button>
        </DropdownMenu.Trigger>
        <DropdownMenu.Portal>
          <DropdownMenu.Content className="popover menu-list account-menu" side="top" align="start" sideOffset={6}>
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
                      <DropdownMenu.Item className="btn btn-primary menu-invite-btn" onSelect={() => respond.run({ invite, accept: true })}>加入</DropdownMenu.Item>
                      <DropdownMenu.Item className="btn btn-ghost menu-invite-btn" onSelect={() => respond.run({ invite, accept: false })}>忽略</DropdownMenu.Item>
                    </span>
                  </div>
                ))}
                <DropdownMenu.Separator className="menu-sep" />
              </>
            )}
            {byAccount.map(({ account, workspaces: items }, i) => (
              <div key={account.sub}>
                {i > 0 && <DropdownMenu.Separator className="menu-sep" />}
                <DropdownMenu.Label className="menu-label menu-account"><Avatar account={account} size={16} />{account.email}</DropdownMenu.Label>
                {items.length === 0 && <div className="menu-empty">没有 workspace</div>}
                {items.map((w) => (
                  <DropdownMenu.Item key={w.id} className="menu-item" onSelect={() => navigate(`/w/${w.id}`)}>
                    <span className="thread-item"><span>{w.name}</span><span className="muted">{w.stations} 台 station · {w.members} 人</span></span>
                    {w.id === current.id && account.sub === current.account.sub && <Check {...ICON} size={14} className="menu-check" />}
                  </DropdownMenu.Item>
                ))}
              </div>
            ))}
            <DropdownMenu.Separator className="menu-sep" />
            <DropdownMenu.Item className="menu-item" onSelect={() => setCreating(true)}><Plus {...ICON} />新建 workspace</DropdownMenu.Item>
            <DropdownMenu.Item className="menu-item" onSelect={() => void signIn()}><UserPlus {...ICON} />添加另一个账号</DropdownMenu.Item>
            {admin && <DropdownMenu.Item className="menu-item" onSelect={() => navigate("/admin")}><ShieldCheck {...ICON} />管理后台</DropdownMenu.Item>}
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

function NewWorkspaceDialog({ open, onClose }: { open: boolean; onClose(): void }) {
  const list = useAccounts() ?? [];
  const navigate = useNavigate();
  const [name, setName] = useState("");
  const [owner, setOwner] = useState(list[0]?.sub ?? "");
  // Sent every time: the server looks at it only for an account not let in yet, and then asks for it when it is missing or wrong.
  const [code, setCode] = useState(inviteCode);
  const create = useAction(() => cloud.createWorkspace(owner || list[0]!.sub, name, code.trim()), (w) => { setName(""); forgetInviteCode(); onClose(); navigate(`/w/${w.id}`); });
  const [asked, setAsked] = useState(false);
  useEffect(() => { if (needsInviteCode(create.error)) setAsked(true); }, [create.error]);
  const asking = asked || needsInviteCode(create.error);
  return (
    <Dialog open={open} onClose={onClose} title="新建 workspace" description="workspace 是一组人和他们共用的 station。你会成为它的 owner。"
      footer={<><Button variant="ghost" onClick={onClose}>取消</Button><Button variant="primary" disabled={!name.trim()} busy={create.busy} onClick={() => create.run()}>新建</Button></>}>
      <Field label="名字" htmlFor="ws-name">
        <input id="ws-name" className="input" value={name} autoFocus onChange={(e) => setName(e.target.value)} placeholder="例如：Cue 团队" maxLength={80}
          onKeyDown={(e) => { if (e.key === "Enter" && name.trim()) create.run(); }} />
      </Field>
      {list.length > 1 && (
        <Field label="属于哪个账号" htmlFor="ws-owner">
          <Select id="ws-owner" value={owner} onChange={setOwner} options={list.map((a) => ({ value: a.sub, label: a.email }))} />
        </Field>
      )}
      {asking && (
        <Field label="邀请码" htmlFor="ws-code" error={create.error && needsInviteCode(create.error) && code.trim() ? errorText(create.error) : undefined}
          hint="ember 目前只对受邀的人开放：这个账号还没被邀请进任何 workspace，新建需要一个邀请码。">
          <input id="ws-code" className="input mono" value={code} autoFocus onChange={(e) => setCode(e.target.value)} placeholder="XXXX-XXXX-XXXX" maxLength={32} spellCheck={false} autoComplete="off"
            onKeyDown={(e) => { if (e.key === "Enter" && name.trim() && code.trim()) create.run(); }} />
        </Field>
      )}
      {create.error && !needsInviteCode(create.error) && <p className="field-error" role="alert">{create.error.message}</p>}
    </Dialog>
  );
}

