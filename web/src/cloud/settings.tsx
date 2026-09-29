// Settings in ember cloud, in two parts: the account the current workspace
// is reached through (who you are, where you are signed in), and the
// workspace itself (its name, members, stations, connects and the stations'
// runtime accounts).
import { Illustration } from "../brand.tsx";
import { CHANGEABLE } from "../keymap.ts";
import { ArrowLeft, Brain, Check, Key, LogOut, Plug, Plus, Server, Settings, Sliders, Command, Trash, UserPlus, Users } from "../icons.tsx";
import { useCallback, useEffect, useRef, useState } from "react";
import { Link, Navigate, NavLink, useNavigate } from "react-router";
import { useStations, type StationView } from "../api.ts";
import { ConnectList } from "../pages/Connects.tsx";
import { ACCESS, RUNTIME_LABEL } from "../format.ts";
import { stamp } from "../api.ts";
import { QuotaBars } from "../components.tsx";
import { StationContext, stationBase, type Station } from "../station.tsx";
import { ProfileCard } from "../ProfileCard.tsx";
import { StationList } from "./StationCards.tsx";
import { MemoryView } from "../Memory.tsx";
import { AddAccountDialog, MachineLoginOffers, PROFILE_LEAD, type Choice } from "../pages/Accounts.tsx";
import { useTopic } from "../core/react.ts";
import { useToast } from "../toast.tsx";
import { About, Button, Confirm, CopyCommand, Dialog, Empty, Field, FirstOne, ICON, Loading, Menu, MobileBack, Pill, ProviderLogo, RuntimeTags, Section, Select, StatusDot, Time } from "../ui.tsx";
import { signOut, type Account } from "./accounts.ts";
import { lastChat } from "../lastChat.ts";
import { parseEmails, useSlackPeople } from "./adding.ts";
import { cloud, useAction, useWorkspace as useWorkspaceTopic, type LoginSession, type Role, type WorkspaceView } from "./api.ts";
import { Avatar } from "./gate.tsx";
import { track } from "../telemetry.ts";
import type { WorkspaceEntry } from "./workspace.tsx";
import * as nav from "../Sidebar.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as chatCss from "../styles/chat.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as additionsCss from "../styles/additions.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./settings.css.ts";
import * as waitingCss from "../styles/waiting.css.ts";

export const ROLE_LABEL: Record<Role, string> = { owner: "Owner", admin: "管理员", member: "成员" };
export const ROLE_HINT: Record<Role, string> = {
  owner: "管理一切，包括成员角色和删除 workspace",
  admin: "邀请成员、添加和移除 station",
  member: "使用 workspace 里的 station",
};

/** The sidebar while in settings. */
export function SettingsNav({ entry }: { entry: WorkspaceEntry }) {
  const base = `/w/${entry.id}/settings`;
  // Connects and profiles are a station's: none to show before there is one.
  const some = (useStations(entry.id).value?.length ?? 0) > 0;
  return (
    <div className={nav.navScroll}>
      <NavLink className={nav.navRow} to={lastChat(entry.id, `/w/${entry.id}`)} end><ArrowLeft {...ICON} />{some ? "返回会话" : "返回"}</NavLink>
      <div className={nav.navHeading}>客户端</div>
      <NavLink className={nav.navRow} to={`${base}/appearance`}><Sliders {...ICON} />外观</NavLink>
      {CHANGEABLE && <NavLink className={nav.navRow} to={`${base}/shortcuts`}><Command {...ICON} />快捷键</NavLink>}
      <div className={nav.navHeading}>Station</div>
      <NavLink className={nav.navRow} to={`${base}/stations`}><Server {...ICON} />Station</NavLink>
      {some && <NavLink className={nav.navRow} to={`${base}/connects`}><Plug {...ICON} />连接</NavLink>}
      {some && <NavLink className={nav.navRow} to={`${base}/profiles`}><Key {...ICON} />Profile</NavLink>}
      {some && <NavLink className={nav.navRow} to={`${base}/memory`}><Brain {...ICON} />记忆</NavLink>}
      <div className={nav.navHeading}>Cloud</div>
      <NavLink className={nav.navRow} to={`${base}/workspace`}><Users {...ICON} /><span className={nav.navText}>Workspace · {entry.name}</span></NavLink>
      <NavLink className={nav.navRow} to={`${base}/account`}><Avatar account={entry.account} size={18} /><span className={nav.navText}>{entry.account.email}</span></NavLink>
    </div>
  );
}

function Page({ title, lead, back, actions, children }: { title: string; lead?: string; back: string; actions?: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label="设置" />
      <header className={pagesCss.pageHead}><div><h1>{title}{lead && <About>{lead}</About>}</h1></div>{actions}</header>
      {children}
    </div>
  );
}

// ── account ─────────────────────────────────────────────────────────────

export function AccountSettings({ entry }: { entry: WorkspaceEntry }) {
  const account = entry.account;
  const toast = useToast();
  // Where the account is signed in: a topic of the core, read again after a revoke.
  const devices = useTopic<LoginSession[]>({ topic: "loginSessions", account: account.sub });
  const revoke = useAction((id: string) => cloud.revokeLoginSession(account.sub, id), () => toast("已让那台设备退出"));
  const navigate = useNavigate();
  const [signingOut, setSigningOut] = useState(false);
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={`/w/${entry.id}/settings`} label="设置" />
      <header className={pagesCss.identity}>
        <Avatar account={account} size={52} />
        <div className={pagesCss.identityText}>
          <h1 className={pagesCss.identityName}>{account.name || account.email}</h1>
          <p className={pagesCss.identitySub}><span>{account.email}</span><span>Google 账号</span></p>
        </div>
      </header>
      <Section title="登录的地方" description="这个账号在哪些浏览器或设备上登录了 still.fail。认不出来的可以让它退出。">
        {!devices.value ? devices.error ? <p className={controlsCss.fieldError}>读不到登录记录：{devices.error.message}</p> : <Loading label="正在读取…" fill={false} /> : (
          <ul className={pagesCss.list}>
            {devices.value.map((s) => (
              <li key={s.id} className={pagesCss.listRow}>
                <span className={pagesCss.listRowText}>
                  <span className={pagesCss.listRowTitle}>{s.name || "未命名设备"}{s.current && <span className={additionsCss.choiceBadge}>这里</span>}</span>
                  <span className={shellCss.muted}><Time stamp={stamp(s, "created_at")} />登录 · {stamp(s, "expires_at")?.until}过期</span>
                </span>
                {!s.current && <Button variant="ghost" busy={revoke.busy && revoke.arg === s.id} onClick={() => revoke.run(s.id)}>退出</Button>}
              </li>
            ))}
          </ul>
        )}
      </Section>
      <Section title="退出登录">
        <div className={`${pagesCss.card} ${pagesCss.cardRow}`}>
          <div className={pagesCss.cardRowText}><strong>在这个浏览器上退出 {account.email}</strong><span className={shellCss.muted}>它所在的 workspace 会从这里消失；其他已登录的账号不受影响。</span></div>
          <Button icon={LogOut} onClick={() => setSigningOut(true)}>退出账号</Button>
        </div>
      </Section>
      <Confirm open={signingOut} onClose={() => setSigningOut(false)} onConfirm={() => void signOut(account.sub).then(() => { toast(`已退出 ${account.email}`); navigate("/"); })}
        title={`退出 ${account.email}？`} action="退出账号" description="这个浏览器上不再使用这个账号；它所在的 workspace 也会从这里消失。其他已登录的账号不受影响。" />
    </div>
  );
}

// ── workspace ───────────────────────────────────────────────────────────

function useWorkspace(entry: WorkspaceEntry): { view: WorkspaceView | undefined; manager: boolean } {
  const view = useWorkspaceTopic(entry.id).value;
  return { view, manager: view?.role === "owner" || view?.role === "admin" };
}

/** The workspace in one page: its name, its members, and leaving or deleting it (at the end, away from the rest). */
export function WorkspaceSettings({ entry }: { entry: WorkspaceEntry }) {
  const { view, manager } = useWorkspace(entry);
  const account = entry.account;
  const navigate = useNavigate();
  const toast = useToast();
  const [name, setName] = useState("");
  useEffect(() => { if (view) setName(view.name); }, [view?.name]);
  const rename = useAction(() => cloud.renameWorkspace(account.sub, entry.id, name), () => toast("已改名"));
  const [leaving, setLeaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const leave = useAction(() => cloud.removeMember(account.sub, entry.id, account.sub), () => { toast("已退出 workspace"); navigate("/"); });
  const remove = useAction(() => cloud.deleteWorkspace(account.sub, entry.id), () => { toast("已删除 workspace"); navigate("/"); });
  if (!view) return <Loading label="正在读取 workspace…" />;
  return (
    <Page title="Workspace" back={`/w/${entry.id}/settings`}>
      <Section title="名字">
        <div className={pagesCss.card}>
          <Field label="Workspace 名字" htmlFor="ws-rename" hint={manager ? undefined : "只有 owner 和管理员能改名。"}>
            <div className={additionsCss.inputRow}>
              <input id="ws-rename" className={controlsCss.input} value={name} maxLength={80} disabled={!manager} onChange={(e) => setName(e.target.value)} />
              {manager && <Button variant="primary" disabled={!name.trim() || name.trim() === view.name} busy={rename.busy} onClick={() => rename.run()}>保存</Button>}
            </div>
          </Field>
          <p className={`${shellCss.muted} ${controlsCss.cardFoot}`}>你在这里是{ROLE_LABEL[view.role]}，通过 {account.email} 访问。</p>
        </div>
      </Section>
      <Members view={view} account={account} manager={manager} />
      <Section title="退出与删除">
        {/* One card, as the name's: leaving, and (the owner) deleting, each asked again before it is done. */}
        <div className={pagesCss.card}>
          <div className={pagesCss.cardRow}>
            <div className={pagesCss.cardRowText}><strong>退出这个 workspace</strong><span className={shellCss.muted}>退出后不能再访问里面的 station，需要重新被邀请。</span></div>
            <Button variant="danger" icon={LogOut} onClick={() => setLeaving(true)}>退出</Button>
          </div>
          {view.role === "owner" && (
            <div className={pagesCss.cardRow}>
              <div className={pagesCss.cardRowText}><strong>删除 workspace</strong><span className={shellCss.muted}>所有成员失去访问权限，station 断开与 still.fail cloud 的连接；station 本机的数据不受影响。</span></div>
              <Button variant="danger" icon={Trash} onClick={() => setDeleting(true)}>删除</Button>
            </div>
          )}
        </div>
      </Section>
      <Confirm open={leaving} onClose={() => setLeaving(false)} busy={leave.busy} onConfirm={() => leave.run()}
        title={`退出「${view.name}」？`} action="退出" description="退出后你就不能再访问里面的 station，需要重新被邀请才能回来。" error={leave.error?.message} />
      <Confirm open={deleting} onClose={() => setDeleting(false)} busy={remove.busy} onConfirm={() => remove.run()}
        title={`删除「${view.name}」？`} action="删除 workspace"
        description={`所有成员都会失去访问权限，${view.stations.length} 台 station 会断开和 still.fail cloud 的连接（station 本机上的数据不受影响）。`} error={remove.error?.message} />
    </Page>
  );
}

export function StationsSettings({ entry }: { entry: WorkspaceEntry }) {
  const { view, manager } = useWorkspace(entry);
  const stations = useStations(entry.id).value;
  if (!view || !stations) return <Loading label="正在读取 workspace…" />;
  return (
    <Page title="Station" lead="每台 station 是一台运行 still.fail 的机器：它的连接、会话和 Profile 都在那台机器上。" back={`/w/${entry.id}/settings`}>
      {/* None yet: adding the first, as the workspace's page does. */}
      {stations.length === 0 ? <FirstStation entry={entry} />
        : <Stations view={view} account={entry.account} manager={manager} stations={stations} />}
    </Page>
  );
}

/** Each station's agents' memory: global and projects', where its sessions run. */
export function MemorySettings({ entry }: { entry: WorkspaceEntry }) {
  const listed = useStations(entry.id).value;
  if (listed?.length === 0) return <Navigate to={`/w/${entry.id}/settings/stations`} replace />;
  const stations = listed ?? [];
  return (
    <Page title="记忆" lead="每台 station 上所有会话共用的记忆：全局记忆放跨项目的，项目记忆每个项目一份。记忆在各台 station 上，不互相同步。" back={`/w/${entry.id}/settings`}>
      {stations.map((s) => (
        <div key={s.id} className={css.memoryStation}>
          {stations.length > 1 && <h2 className={css.memoryStationName}>{s.name}</h2>}
          {s.online ? <MemoryView station={s.station} /> : <p className={shellCss.muted}>离线，等它上线再看。</p>}
        </div>
      ))}
    </Page>
  );
}

export function ConnectsSettings({ entry }: { entry: WorkspaceEntry }) {
  const stations = useStations(entry.id).value;
  if (stations?.length === 0) return <Navigate to={`/w/${entry.id}/settings/stations`} replace />;
  return <ConnectList scope={entry.id} settings={`/w/${entry.id}/settings`} />;
}

/**
 * Every station's profiles on one page, each station with its own add button (and one at the top when there is only
 * one station): a profile is added where it runs.
 */
export function RuntimeSettings({ entry }: { entry: WorkspaceEntry }) {
  const listed = useStations(entry.id).value;
  const stations = listed ?? [];
  const [adding, setAdding] = useState<string | null>(null);
  const [addKind, setAddKind] = useState<Choice>("claude-sub");
  const online = stations.filter((s) => s.online);
  const asStation = (s: (typeof stations)[number]): Station => ({ id: s.id, name: s.name, online: s.online, address: s.station, base: stationBase(s.station), settings: `/w/${entry.id}/settings` });
  const addingTo = stations.find((s) => s.station === adding);
  if (listed?.length === 0) return <Navigate to={`/w/${entry.id}/settings/stations`} replace />;
  // Not one profile on any station (each read): the page is about adding the first.
  const first = stations.length > 0 && stations.every((s) => s.overview && s.overview.profiles.length === 0);
  return (
    <Page title="Profile" lead="Profile 是 agent 用来跑模型的账号：一份订阅，或者一个模型服务的 key。每个 Profile 在它所在的 station 上运行，能跑哪些运行时，still.fail 会自己配好。" back={`/w/${entry.id}/settings`}
      actions={!first && online.length === 1 && <Button icon={Plus} onClick={() => setAdding(online[0]!.station)}>添加 Profile</Button>}>
      {addingTo && (
        <StationContext.Provider value={asStation(addingTo)}>
          <AddAccountDialog key={addKind} initial={addKind} open onClose={() => setAdding(null)} />
        </StationContext.Provider>
      )}
      {first ? (
        <FirstOne art={<Illustration name="no-profile" />} title="添加第一个 Profile" lead={PROFILE_LEAD}>
          {/* Each station in a row: where a profile is added is part of adding it. */}
          <div className={css.firstStations}>
            {stations.map((s) => (
              <div key={s.id} className={css.firstStation}>
                <div className={css.firstStationRow}>
                  <StatusDot state={s.online ? "online" : "offline"} label={s.online ? "在线" : "离线"} />
                  <span className={css.firstStationName}>{s.name}</span>
                  {s.online
                    ? <Button variant={stations.length === 1 ? "primary" : "secondary"} icon={Plus} onClick={() => { setAddKind("claude-sub"); setAdding(s.station); }}>添加 Profile</Button>
                    : <span className={shellCss.muted}>离线，等它上线再加</span>}
                </div>
                {s.online && (
                  <StationContext.Provider value={asStation(s)}>
                    <MachineLoginOffers logins={s.overview?.machineLogins} onAdd={(c) => { setAddKind(c); setAdding(s.station); }} />
                  </StationContext.Provider>
                )}
              </div>
            ))}
          </div>
        </FirstOne>
      ) : stations.map((station) => {
        const { overview } = station;
        const base = stationBase(station.station);
        return (
          <Section key={station.id}
            title={<span className={css.stationHeading}><StatusDot state={station.online ? "online" : "offline"} label={station.online ? "在线" : "离线"} />{station.name}</span>}
            actions={station.online && online.length > 1 && <Button variant="ghost" icon={Plus} onClick={() => setAdding(station.station)}>添加</Button>}>
            {!station.online && !overview ? <p className={shellCss.muted}>离线，还没有读到过它的 Profile。</p>
              : !overview ? <Loading label={`正在连接 ${station.name}…`} fill={false} />
              : (
                <>
                  {overview.profiles.length === 0 ? <p className={shellCss.muted}>还没有 Profile。</p> : (
                    <ul className={pagesCss.list}>
                      {overview.profiles.map((p) => (
                        <li key={p.id}>
                          <ProfileCard profile={p} to={`${base}/settings/accounts/${p.id}`} uses={p.usedBy.length ? `${p.usedBy.length} 个连接在用` : ""} />
                        </li>
                      ))}
                    </ul>
                  )}
                  {/* The machine's own logins not used yet: each one offered as the first ones were. */}
                  {station.online && (
                    <StationContext.Provider value={asStation(station)}>
                      <MachineLoginOffers logins={overview.machineLogins} onAdd={(c) => { setAddKind(c); setAdding(station.station); }} />
                    </StationContext.Provider>
                  )}
                </>
              )}
          </Section>
        );
      })}
    </Page>
  );
}

function Stations({ view, account, manager, stations }: { view: WorkspaceView; account: Account; manager: boolean; stations: StationView[] }) {
  const [adding, setAdding] = useState(false);
  const [removing, setRemoving] = useState<StationView | null>(null);
  const remove = useAction((s: StationView) => cloud.removeStation(account.sub, view.id, s.id), () => setRemoving(null));
  const rename = useAction(({ id, name }: { id: string; name: string }) => cloud.renameStation(account.sub, view.id, id, name));
  return (
    <Section title={`${stations.length} 台`} actions={manager && <Button icon={Plus} onClick={() => setAdding(true)}>添加 station</Button>}>
      <StationList stations={stations} manager={manager} menu={(s) => manager && <Menu items={[
        { label: "改名", onSelect: () => { const n = window.prompt("station 的名字", s.name); if (n?.trim()) rename.run({ id: s.id, name: n.trim() }); } },
        { label: "从 workspace 移除", icon: Trash, danger: true, onSelect: () => setRemoving(s) },
      ]} />} />
      {adding && <AddStationDialog view={view} account={account} stations={stations} onClose={() => setAdding(false)} />}
      <Confirm open={removing !== null} onClose={() => setRemoving(null)} busy={remove.busy} onConfirm={() => removing && remove.run(removing)}
        title={`移除「${removing?.name ?? ""}」？`} action="移除 station"
        description="它会断开与 still.fail cloud 的连接，成员不能再从这里访问它。那台机器上的 still.fail 和数据不受影响，之后可以重新添加。" error={remove.error?.message} />
    </Section>
  );
}

function AddStationDialog({ view, account, stations, onClose }: { view: WorkspaceView; account: Account; stations: StationView[]; onClose(): void }) {
  const [name, setName] = useState("");
  // The stations there before: the one that joins is the one not among them.
  const [known] = useState(() => new Set(stations.map((s) => s.id)));
  const enroll = useAction(() => cloud.enroll(account.sub, view.id, name));
  const joined = enroll.result && stations.find((s) => !known.has(s.id));
  // From the command shown to the station in the list: how long adding one takes.
  const shown = useRef(0);
  useEffect(() => { if (enroll.result) shown.current = performance.now(); }, [enroll.result]);
  useEffect(() => { if (joined) track("station_added", { ms: Math.round(performance.now() - shown.current) }); }, [Boolean(joined)]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <Dialog open onClose={onClose} wide title="添加 station"
      description="给它起个名字，再在那台机器上执行一条命令。"
      footer={joined ? <Button variant="primary" onClick={onClose}>完成</Button> : <>
        <Button variant="ghost" onClick={onClose}>{enroll.result ? "关闭" : "取消"}</Button>
        {!enroll.result && <Button variant="primary" disabled={!name.trim()} busy={enroll.busy} onClick={() => enroll.run()}>生成命令</Button>}
      </>}>
      {!enroll.result ? (
        <Field label="名字" htmlFor="station-name">
          <input id="station-name" className={controlsCss.input} value={name} autoFocus placeholder="比如 studio、mac-mini" onChange={(e) => setName(e.target.value)} maxLength={80}
            onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && name.trim()) enroll.run(); }} />
        </Field>
      ) : joined ? (
        <div className={additionsCss.callout} data-tone="green"><Check {...ICON} /><span>「{joined.name}」已加入，现在可以打开它了。</span></div>
      ) : <EnrollSteps enrollment={enroll.result} />}
      {enroll.error && <p className={controlsCss.fieldError} role="alert">{enroll.error.message}</p>}
    </Dialog>
  );
}

/** An enrollment's command, and that the station is awaited. */
function EnrollSteps({ enrollment }: { enrollment: { install: string } }) {
  return (
    <>
      <p>在那台机器的终端里执行<About>macOS（Apple 芯片）和 Linux 都行；装过 still.fail 的机器也用这条命令。</About></p>
      <CopyCommand text={enrollment.install} />
      <div className={css.enrollWait} role="status">
        <span className={waitingCss.spinner} aria-hidden="true" />
        <span><strong>等待这台机器加入</strong><span className={shellCss.muted}>执行命令后会自动继续 · 命令 1 小时内有效</span></span>
      </div>
    </>
  );
}

/**
 * A workspace's first station, added in the page (a workspace without one: workspace.tsx's Onboarding): its name, then the command
 * and the wait. The workspace's pages take over once it has joined.
 */
export function FirstStation({ entry }: { entry: WorkspaceEntry }) {
  const { view, manager } = useWorkspace(entry);
  const [name, setName] = useState("");
  const enroll = useAction(() => cloud.enroll(entry.account.sub, entry.id, name));
  const shown = useRef(0);
  useEffect(() => { if (enroll.result) shown.current = performance.now(); }, [enroll.result]);
  // Joined: the page is gone (the workspace has a station), so this is said as it goes.
  useEffect(() => () => { if (shown.current) track("station_added", { ms: Math.round(performance.now() - shown.current), first: true }); }, []);
  if (!view) return <Loading label="正在读取 workspace…" fill={false} />;
  if (!manager) return <div className={additionsCss.callout}>这个 workspace 还没有 station，等管理员添加。</div>;
  if (enroll.result) return <div className={css.onboardingCard}><EnrollSteps enrollment={enroll.result} /></div>;
  return (
    <div className={css.onboardingCard}>
      <Field label="给这台机器起个名字" htmlFor="first-station-name">
        <div className={css.onboardingRow}>
          <input id="first-station-name" className={controlsCss.input} value={name} autoFocus placeholder="比如 studio、mac-mini" onChange={(e) => setName(e.target.value)} maxLength={80}
            onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && name.trim()) enroll.run(); }} />
          <Button variant="primary" disabled={!name.trim()} busy={enroll.busy} onClick={() => enroll.run()}>生成命令</Button>
        </div>
      </Field>
      {enroll.error && <p className={controlsCss.fieldError} role="alert">{enroll.error.message}</p>}
    </div>
  );
}

function Members({ view, account, manager }: { view: WorkspaceView; account: Account; manager: boolean }) {
  const toast = useToast();
  const [inviting, setInviting] = useState(false);
  const setRole = useAction(({ sub, role }: { sub: string; role: Role }) => cloud.setRole(account.sub, view.id, sub, role), () => toast("已更改角色"));
  const remove = useAction((sub: string) => cloud.removeMember(account.sub, view.id, sub), () => toast("已移除成员"));
  const revoke = useAction((id: string) => cloud.revokeInvitation(account.sub, view.id, id));
  const unadd = useAction((email: string) => cloud.removeAdded(account.sub, view.id, email));
  return (
    <Section title={`${view.members.length} 人`} actions={manager && <Button icon={UserPlus} onClick={() => setInviting(true)}>添加成员</Button>}>
      <ul className={pagesCss.list}>
        {view.members.map((m) => (
          <li key={m.sub} className={pagesCss.listRow}>
            <Avatar account={m} size={28} />
            <span className={pagesCss.listRowText}>
              <span className={pagesCss.listRowTitle}>{m.name || m.email}{m.sub === account.sub && <span className={additionsCss.choiceBadge}>你</span>}</span>
              <span className={shellCss.muted}>{m.email}</span>
            </span>
            {view.role === "owner" && m.sub !== account.sub ? (
              <div className={css.roleSelect}>
                <Select value={m.role} onChange={(role) => setRole.run({ sub: m.sub, role: role as Role })} label="角色"
                  options={(["owner", "admin", "member"] as Role[]).map((r) => ({ value: r, label: ROLE_LABEL[r] }))} />
              </div>
            ) : <Pill>{ROLE_LABEL[m.role]}</Pill>}
            {manager && m.sub !== account.sub && (m.role !== "owner" || view.role === "owner") && (
              <Menu items={[{ label: "移出 workspace", icon: Trash, danger: true, onSelect: () => { if (window.confirm(`把 ${m.email} 移出「${view.name}」？`)) remove.run(m.sub); } }]} />
            )}
          </li>
        ))}
      </ul>
      {(setRole.error || remove.error) && <p className={controlsCss.fieldError} role="alert">{(setRole.error ?? remove.error)!.message}</p>}
      {manager && view.added.length > 0 && (
        <>
          <div className={css.groupHead}><strong>还没登录过</strong><span className={shellCss.muted}>{view.added.length} 人 · 第一次登录 still.fail 时自动加入</span></div>
          <ul className={pagesCss.list}>
            {view.added.map((a) => (
              <li key={a.email} className={pagesCss.listRow}>
                <span className={pagesCss.listRowText}>
                  <span className={pagesCss.listRowTitle}>{a.email}</span>
                  <span className={shellCss.muted}>{ROLE_LABEL[a.role]}</span>
                </span>
                <Button variant="ghost" busy={unadd.busy && unadd.arg === a.email} onClick={() => unadd.run(a.email)}>移除</Button>
              </li>
            ))}
          </ul>
        </>
      )}
      {manager && view.invitations.length > 0 && (
        <>
          <div className={css.groupHead}><strong>未接受的邀请</strong><span className={shellCss.muted}>{view.invitations.length} 个</span></div>
          <ul className={pagesCss.list}>
            {view.invitations.map((i) => (
              <li key={i.id} className={pagesCss.listRow}>
                <span className={pagesCss.listRowText}>
                  <span className={pagesCss.listRowTitle}>{i.email ?? "任何拿到链接的人"}</span>
                  <span className={shellCss.muted}>{ROLE_LABEL[i.role]} · {stamp(i, "expires_at")?.until}过期</span>
                </span>
                <Button variant="ghost" busy={revoke.busy && revoke.arg === i.id} onClick={() => revoke.run(i.id)}>撤回</Button>
              </li>
            ))}
          </ul>
        </>
      )}
      {inviting && <AddDialog view={view} account={account} onClose={() => setInviting(false)} />}
    </Section>
  );
}

function AddDialog({ view, account, onClose }: { view: WorkspaceView; account: Account; onClose(): void }) {
  const [role, setRole] = useState<Role>("member");
  const [text, setText] = useState("");
  const slack = useSlackPeople(view.id);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const inside = new Set([...view.members.map((m) => m.email.toLowerCase()), ...view.added.map((a) => a.email)]);
  const typed = parseEmails(text);
  const emails = [...new Set([...typed, ...picked])].filter((e) => !inside.has(e));
  const add = useAction(() => cloud.addMembers(account.sub, view.id, role, emails));
  const roles: Role[] = view.role === "owner" ? ["member", "admin", "owner"] : ["member", "admin"];
  const fromSlack = () => void slack.load();
  // Once read, the workspace's own Slack people are picked; guests are left to choose.
  useEffect(() => {
    if (slack.people) setPicked(new Set(slack.people.filter((p) => !p.guest && !inside.has(p.email)).map((p) => p.email)));
  }, [slack.people]);
  const toggle = (email: string) => setPicked((now) => {
    const next = new Set(now);
    if (next.has(email)) next.delete(email); else next.add(email);
    return next;
  });
  const done = add.result;
  return (
    <Dialog open onClose={onClose} title="添加成员" description={`直接加进「${view.name}」，不用对方接受：已经登录过 still.fail 的人马上就是成员，其他人第一次用这个邮箱登录时自动加入。`}
      footer={done ? <Button variant="primary" onClick={onClose}>完成</Button> : <>
        <Button variant="ghost" onClick={onClose}>取消</Button>
        <Button variant="primary" disabled={emails.length === 0} busy={add.busy} onClick={() => add.run()}>{emails.length > 1 ? `添加 ${emails.length} 人` : "添加"}</Button>
      </>}>
      {!done ? (
        <>
          <Field label="邮箱" htmlFor="add-emails" hint="对方登录 still.fail 用的 Google 账号邮箱；一次可以粘贴多个。">
            <textarea id="add-emails" className={controlsCss.input} rows={3} autoFocus value={text} onChange={(e) => setText(e.target.value)} placeholder="name@example.com" />
          </Field>
          {slack.available && (
            slack.people === null ? (
              <Button variant="secondary" busy={slack.busy} onClick={fromSlack}>从 Slack 里选人</Button>
            ) : (
              <div className={chatCss.modelPool}>
                <div className={chatCss.modelPoolTools}>
                  <span className={shellCss.muted}>Slack 里 {slack.people.length} 人，选中 {[...picked].filter((e) => !inside.has(e)).length} 人</span>
                  <button type="button" className={controlsCss.textToggle} onClick={() => setPicked(new Set(slack.people!.filter((p) => !inside.has(p.email)).map((p) => p.email)))}>全选</button>
                  <button type="button" className={controlsCss.textToggle} onClick={() => setPicked(new Set())}>全不选</button>
                </div>
                <ul className={chatCss.modelPoolList}>
                  {slack.people.map((p) => (
                    <li key={p.email}>
                      <label className={chatCss.modelPoolItem} data-on={picked.has(p.email) || inside.has(p.email) || undefined}>
                        <input type="checkbox" disabled={inside.has(p.email)} checked={picked.has(p.email) || inside.has(p.email)} onChange={() => toggle(p.email)} />
                        <span>{p.name}</span>
                        <span className={shellCss.muted}>{p.email}</span>
                        {inside.has(p.email) ? <span className={shellCss.muted}>已在</span> : p.guest && <span className={shellCss.muted}>访客</span>}
                      </label>
                    </li>
                  ))}
                </ul>
                {slack.errors.length > 0 && <p className={controlsCss.fieldError}>{slack.errors.join("；")}</p>}
              </div>
            )
          )}
          <Field label="角色" hint={ROLE_HINT[role]}>
            <Select value={role} onChange={(r) => setRole(r as Role)} label="角色" options={roles.map((r) => ({ value: r, label: ROLE_LABEL[r] }))} />
          </Field>
        </>
      ) : (
        <div className={additionsCss.callout} data-tone="green"><Check {...ICON} /><span>{[
          done.joined.length ? `${done.joined.length} 人已经加入` : "",
          done.added.length ? `${done.added.length} 人第一次登录 still.fail 时自动加入` : "",
          done.already.length ? `${done.already.length} 人本来就在` : "",
        ].filter(Boolean).join("，")}。</span></div>
      )}
      {add.error && <p className={controlsCss.fieldError} role="alert">{add.error.message}</p>}
    </Dialog>
  );
}
