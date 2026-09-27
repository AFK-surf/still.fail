// Settings in ember cloud, in two parts: the account the current workspace
// is reached through (who you are, where you are signed in), and the
// workspace itself (its name, members, stations, connects and the stations'
// runtime accounts).
import { ArrowLeft, Check, Key, LogOut, Plug, Plus, Server, Settings, Trash, UserPlus, Users } from "../icons.tsx";
import { useCallback, useEffect, useRef, useState } from "react";
import { Link, Navigate, NavLink, useNavigate } from "react-router";
import { useStations, type StationView } from "../api.ts";
import { ConnectList } from "../pages/Connects.tsx";
import { ACCESS, RUNTIME_LABEL } from "../format.ts";
import { stamp } from "../api.ts";
import { AppearanceSetting, DeviceCard, QuotaBars } from "../components.tsx";
import { StationContext, stationBase, type Station } from "../station.tsx";
import { AddAccountDialog, MachineLoginOffers, PROFILE_LEAD, type Choice } from "../pages/Accounts.tsx";
import { useTopic } from "../core/react.ts";
import { useToast } from "../toast.tsx";
import { Button, Confirm, CopyCommand, Dialog, Empty, Field, FirstOne, ICON, Loading, Menu, MobileBack, Pill, ProviderLogo, RuntimeTags, Section, Select, StatusDot, Time } from "../ui.tsx";
import { signOut, type Account } from "./accounts.ts";
import { lastChat } from "../lastChat.ts";
import { cloud, useAction, useWorkspace as useWorkspaceTopic, type LoginSession, type Role, type WorkspaceView } from "./api.ts";
import { Avatar } from "./gate.tsx";
import { track } from "../telemetry.ts";
import type { WorkspaceEntry } from "./workspace.tsx";

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
    <div className="nav-scroll">
      <NavLink className="nav-row" to={lastChat(entry.id, `/w/${entry.id}`)} end><ArrowLeft {...ICON} />{some ? "返回会话" : "返回"}</NavLink>
      <div className="nav-heading">账号</div>
      <NavLink className="nav-row" to={`${base}/account`}><Avatar account={entry.account} size={18} /><span className="nav-text">{entry.account.email}</span></NavLink>
      <div className="nav-heading">Workspace · {entry.name}</div>
      <NavLink className="nav-row" to={`${base}/stations`}><Server {...ICON} />Station</NavLink>
      {some && <NavLink className="nav-row" to={`${base}/connects`}><Plug {...ICON} />连接</NavLink>}
      {some && <NavLink className="nav-row" to={`${base}/profiles`}><Key {...ICON} />Profile</NavLink>}
      <NavLink className="nav-row" to={`${base}/members`}><Users {...ICON} />成员</NavLink>
      <NavLink className="nav-row" to={`${base}/general`}><Settings {...ICON} />通用</NavLink>
      <div className="nav-heading">离开</div>
      <NavLink className="nav-row" to={`${base}/leave`}><LogOut {...ICON} />退出与删除</NavLink>
    </div>
  );
}

function Page({ title, lead, back, actions, children }: { title: string; lead?: string; back: string; actions?: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="page page-narrow">
      <MobileBack to={back} label="设置" />
      <header className="page-head"><div><h1>{title}</h1>{lead && <p className="page-sub">{lead}</p>}</div>{actions}</header>
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
  return (
    <div className="page page-narrow">
      <MobileBack to={`/w/${entry.id}/settings`} label="设置" />
      <header className="identity">
        <Avatar account={account} size={52} />
        <div className="identity-text">
          <h1 className="identity-name">{account.name || account.email}</h1>
          <p className="identity-sub"><span>{account.email}</span><span>Google 账号</span></p>
        </div>
      </header>
      <Section title="外观" description="浅色、深色，或跟着系统走。只对这个浏览器生效。">
        <div className="appearance-setting"><AppearanceSetting /></div>
      </Section>
      <Section title="登录的地方" description="这个账号在哪些浏览器或设备上登录了 ember。认不出来的可以让它退出。">
        {!devices.value ? devices.error ? <p className="field-error">读不到登录记录：{devices.error.message}</p> : <Loading label="正在读取…" fill={false} /> : (
          <ul className="list">
            {devices.value.map((s) => (
              <li key={s.id} className="list-row">
                <span className="list-row-text">
                  <span className="list-row-title">{s.name || "未命名设备"}{s.current && <span className="choice-badge">这里</span>}</span>
                  <span className="muted"><Time stamp={stamp(s, "created_at")} />登录 · {stamp(s, "expires_at")?.until}过期</span>
                </span>
                {!s.current && <Button variant="ghost" busy={revoke.busy && revoke.arg === s.id} onClick={() => revoke.run(s.id)}>退出</Button>}
              </li>
            ))}
          </ul>
        )}
      </Section>
    </div>
  );
}

// ── workspace ───────────────────────────────────────────────────────────

function useWorkspace(entry: WorkspaceEntry): { view: WorkspaceView | undefined; manager: boolean } {
  const view = useWorkspaceTopic(entry.id).value;
  return { view, manager: view?.role === "owner" || view?.role === "admin" };
}

export function GeneralSettings({ entry }: { entry: WorkspaceEntry }) {
  const { view, manager } = useWorkspace(entry);
  const account = entry.account;
  const toast = useToast();
  const [name, setName] = useState("");
  useEffect(() => { if (view) setName(view.name); }, [view?.name]);
  const rename = useAction(() => cloud.renameWorkspace(account.sub, entry.id, name), () => toast("已改名"));
  if (!view) return <Loading label="正在读取 workspace…" />;
  return (
    <Page title="通用" back={`/w/${entry.id}/settings`}>
      <Section title="名字">
        <div className="card">
          <Field label="Workspace 名字" htmlFor="ws-rename" hint={manager ? undefined : "只有 owner 和管理员能改名。"}>
            <div className="input-row">
              <input id="ws-rename" className="input" value={name} maxLength={80} disabled={!manager} onChange={(e) => setName(e.target.value)} />
              {manager && <Button variant="primary" disabled={!name.trim() || name.trim() === view.name} busy={rename.busy} onClick={() => rename.run()}>保存</Button>}
            </div>
          </Field>
          <p className="muted card-foot">你在这里是{ROLE_LABEL[view.role]}，通过 {account.email} 访问。</p>
        </div>
      </Section>
    </Page>
  );
}

/** The last settings page: everything that ends access, away from everyday settings. */
export function LeaveSettings({ entry }: { entry: WorkspaceEntry }) {
  const { view } = useWorkspace(entry);
  const account = entry.account;
  const navigate = useNavigate();
  const toast = useToast();
  const [signingOut, setSigningOut] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const leave = useAction(() => cloud.removeMember(account.sub, entry.id, account.sub), () => { toast("已退出 workspace"); navigate("/"); });
  const remove = useAction(() => cloud.deleteWorkspace(account.sub, entry.id), () => { toast("已删除 workspace"); navigate("/"); });
  if (!view) return <Loading label="正在读取 workspace…" />;
  return (
    <Page title="退出与删除" back={`/w/${entry.id}/settings`}>
      <Section title="账号">
        <div className="card card-row">
          <div className="card-row-text"><strong>在这个浏览器上退出 {account.email}</strong><span className="muted">它所在的 workspace 会从这里消失；其他已登录的账号不受影响。</span></div>
          <Button icon={LogOut} onClick={() => setSigningOut(true)}>退出账号</Button>
        </div>
      </Section>
      <Section title={`Workspace · ${view.name}`}>
        <div className="card card-row">
          <div className="card-row-text"><strong>退出这个 workspace</strong><span className="muted">退出后不能再访问里面的 station，需要重新被邀请。</span></div>
          <Button onClick={() => setLeaving(true)}>退出</Button>
        </div>
        {view.role === "owner" && (
          <div className="card card-row">
            <div className="card-row-text"><strong>删除 workspace</strong><span className="muted">所有成员失去访问权限，station 断开与 ember cloud 的连接；station 本机的数据不受影响。</span></div>
            <Button variant="danger" icon={Trash} onClick={() => setDeleting(true)}>删除</Button>
          </div>
        )}
      </Section>
      <Confirm open={leaving} onClose={() => setLeaving(false)} busy={leave.busy} onConfirm={() => leave.run()}
        title={`退出「${view.name}」？`} action="退出" description={leave.error?.message ?? "退出后你就不能再访问里面的 station，需要重新被邀请才能回来。"} />
      <Confirm open={deleting} onClose={() => setDeleting(false)} busy={remove.busy} onConfirm={() => remove.run()}
        title={`删除「${view.name}」？`} action="删除 workspace"
        description={remove.error?.message ?? `所有成员都会失去访问权限，${view.stations.length} 台 station 会断开和 ember cloud 的连接（station 本机上的数据不受影响）。`} />
      <Confirm open={signingOut} onClose={() => setSigningOut(false)} onConfirm={() => void signOut(account.sub).then(() => { toast(`已退出 ${account.email}`); navigate("/"); })}
        title={`退出 ${account.email}？`} action="退出账号" description="这个浏览器上不再使用这个账号；它所在的 workspace 也会从这里消失。其他已登录的账号不受影响。" />
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
  const stations = useStations(entry.id).value;
  if (!view || !stations) return <Loading label="正在读取 workspace…" />;
  return (
    <Page title="Station" lead="每台 station 是一台运行 ember 的机器：它的连接、会话和 Profile 都在那台机器上。" back={`/w/${entry.id}/settings`}>
      {/* None yet: adding the first, as the workspace's page does. */}
      {stations.length === 0 ? <FirstStation entry={entry} />
        : <Stations view={view} account={entry.account} manager={manager} stations={stations} />}
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
    <Page title="Profile" lead="Profile 是 agent 用来跑模型的账号：一份订阅，或者一个模型服务的 key。每个 Profile 在它所在的 station 上运行，能跑哪些运行时，ember 会自己配好。" back={`/w/${entry.id}/settings`}
      actions={!first && online.length === 1 && <Button icon={Plus} onClick={() => setAdding(online[0]!.station)}>添加 Profile</Button>}>
      {addingTo && (
        <StationContext.Provider value={asStation(addingTo)}>
          <AddAccountDialog key={addKind} initial={addKind} open onClose={() => setAdding(null)} />
        </StationContext.Provider>
      )}
      {first ? (
        <FirstOne icon={Key} title="添加第一个 Profile" lead={`${PROFILE_LEAD}Profile 加在某一台 station 上，由那台机器用它来跑。`}>
          {/* Each station in a row: where a profile is added is part of adding it. */}
          <div className="first-stations">
            {stations.map((s) => (
              <div key={s.id} className="first-station">
                <div className="first-station-row">
                  <StatusDot state={s.online ? "online" : "offline"} label={s.online ? "在线" : "离线"} />
                  <span className="first-station-name">{s.name}</span>
                  {s.online
                    ? <Button variant={stations.length === 1 ? "primary" : "secondary"} icon={Plus} onClick={() => { setAddKind("claude-sub"); setAdding(s.station); }}>添加 Profile</Button>
                    : <span className="muted">离线，等它上线再加</span>}
                </div>
                {s.online && <MachineLoginOffers logins={s.overview?.machineLogins} onAdd={(c) => { setAddKind(c); setAdding(s.station); }} />}
              </div>
            ))}
          </div>
        </FirstOne>
      ) : stations.map((station) => {
        const { overview } = station;
        const base = stationBase(station.station);
        return (
          <Section key={station.id}
            title={<span className="station-heading"><StatusDot state={station.online ? "online" : "offline"} label={station.online ? "在线" : "离线"} />{station.name}</span>}
            actions={station.online && online.length > 1 && <Button variant="ghost" icon={Plus} onClick={() => setAdding(station.station)}>添加</Button>}>
            {!station.online && !overview ? <div className="card"><p className="muted card-foot">离线，还没有读到过它的 Profile。</p></div>
              : !overview ? <div className="card"><Loading label={`正在连接 ${station.name}…`} fill={false} /></div>
              : overview.profiles.length === 0 ? <div className="card"><p className="muted card-foot">还没有 Profile。</p></div>
              : (
                <ul className="list">
                  {overview.profiles.map((p) => {
                    return (
                      <li key={p.id}>
                        <Link className="list-row" to={`${base}/settings/accounts/${p.id}`}>
                          <span className="mark runtime-mark"><ProviderLogo runtime={p.runtime} kind={p.access.kind} size={18} /></span>
                          <span className="list-row-text">
                            <span className="list-row-title">{p.name}<RuntimeTags runtimes={p.runtimes} /></span>
                            <span className="muted">{ACCESS[p.access.kind].label}{p.usedBy.length ? ` · ${p.usedBy.length} 个连接在用` : ""}</span>
                          </span>
                          <QuotaBars quota={p.quota} compact />
                          <Pill tone={p.checkTone}>{p.checkText}</Pill>
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

function Stations({ view, account, manager, stations }: { view: WorkspaceView; account: Account; manager: boolean; stations: StationView[] }) {
  const [adding, setAdding] = useState(false);
  const [removing, setRemoving] = useState<StationView | null>(null);
  const remove = useAction((s: StationView) => cloud.removeStation(account.sub, view.id, s.id), () => setRemoving(null));
  const rename = useAction(({ id, name }: { id: string; name: string }) => cloud.renameStation(account.sub, view.id, id, name));
  return (
    <Section title={`${stations.length} 台`} actions={manager && <Button icon={Plus} onClick={() => setAdding(true)}>添加 station</Button>}>
      {(
        <ul className="list">
          {stations.map((s) => (
            <li key={s.id} className="station-item"><div className="list-row station-row">
              <StatusDot state={s.online ? "online" : "offline"} label={s.online ? "在线" : "离线"} />
              <span className="list-row-text">
                <span className="list-row-title">{s.name}</span>
                <span className="muted">
                  {s.online ? "在线" : s.lastSeen ? <><Time stamp={stamp(s, "lastSeen")} />在线</> : "还没上线"}
                  {s.version ? ` · ember-mesh ${s.version}` : ""} · <span className="mono">{s.id.slice(0, 12)}</span>
                </span>
              </span>
              {manager && <Menu items={[
                { label: "改名", onSelect: () => { const n = window.prompt("station 的名字", s.name); if (n?.trim()) rename.run({ id: s.id, name: n.trim() }); } },
                { label: "从 workspace 移除", icon: Trash, danger: true, onSelect: () => setRemoving(s) },
              ]} />}
            </div>
              {s.online && (
                <div className="station-device">
                  <DeviceCard host={s.host} processes={s.overview?.processesText} />
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
      {adding && <AddStationDialog view={view} account={account} stations={stations} onClose={() => setAdding(false)} />}
      <Confirm open={removing !== null} onClose={() => setRemoving(null)} busy={remove.busy} onConfirm={() => removing && remove.run(removing)}
        title={`移除「${removing?.name ?? ""}」？`} action="移除 station"
        description="它会断开与 ember cloud 的连接，成员不能再从这里访问它。那台机器上的 ember 和数据不受影响，之后可以重新添加。" />
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
          <input id="station-name" className="input" value={name} autoFocus placeholder="比如 studio、mac-mini" onChange={(e) => setName(e.target.value)} maxLength={80}
            onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && name.trim()) enroll.run(); }} />
        </Field>
      ) : joined ? (
        <div className="callout" data-tone="green"><Check {...ICON} /><span>「{joined.name}」已加入，现在可以打开它了。</span></div>
      ) : <EnrollSteps enrollment={enroll.result} />}
      {enroll.error && <p className="field-error" role="alert">{enroll.error.message}</p>}
    </Dialog>
  );
}

/** An enrollment's command, and that the station is awaited. */
function EnrollSteps({ enrollment }: { enrollment: { install: string } }) {
  return (
    <>
      <p>在那台机器的终端里执行：</p>
      <CopyCommand text={enrollment.install} />
      <p className="enroll-hint">macOS（Apple 芯片）和 Linux 都行；装过 ember 的机器也用这条命令。</p>
      <div className="enroll-wait" role="status">
        <span className="spinner" aria-hidden="true" />
        <span><strong>等待这台机器加入</strong><span className="muted">执行命令后会自动继续 · 命令 1 小时内有效</span></span>
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
  if (!manager) return <div className="callout">这个 workspace 还没有 station，等管理员添加。</div>;
  if (enroll.result) return <div className="onboarding-card"><EnrollSteps enrollment={enroll.result} /></div>;
  return (
    <div className="onboarding-card">
      <Field label="给这台机器起个名字" htmlFor="first-station-name">
        <div className="onboarding-row">
          <input id="first-station-name" className="input" value={name} autoFocus placeholder="比如 studio、mac-mini" onChange={(e) => setName(e.target.value)} maxLength={80}
            onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && name.trim()) enroll.run(); }} />
          <Button variant="primary" disabled={!name.trim()} busy={enroll.busy} onClick={() => enroll.run()}>生成命令</Button>
        </div>
      </Field>
      {enroll.error && <p className="field-error" role="alert">{enroll.error.message}</p>}
    </div>
  );
}

function Members({ view, account, manager }: { view: WorkspaceView; account: Account; manager: boolean }) {
  const toast = useToast();
  const [inviting, setInviting] = useState(false);
  const setRole = useAction(({ sub, role }: { sub: string; role: Role }) => cloud.setRole(account.sub, view.id, sub, role), () => toast("已更改角色"));
  const remove = useAction((sub: string) => cloud.removeMember(account.sub, view.id, sub), () => toast("已移除成员"));
  const revoke = useAction((id: string) => cloud.revokeInvitation(account.sub, view.id, id));
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
      {(setRole.error || remove.error) && <p className="field-error" role="alert">{(setRole.error ?? remove.error)!.message}</p>}
      {manager && view.invitations.length > 0 && (
        <>
          <div className="group-head"><strong>未接受的邀请</strong><span className="muted">{view.invitations.length} 个</span></div>
          <ul className="list">
            {view.invitations.map((i) => (
              <li key={i.id} className="list-row">
                <span className="list-row-text">
                  <span className="list-row-title">{i.email ?? "任何拿到链接的人"}</span>
                  <span className="muted">{ROLE_LABEL[i.role]} · {stamp(i, "expires_at")?.until}过期</span>
                </span>
                <Button variant="ghost" busy={revoke.busy && revoke.arg === i.id} onClick={() => revoke.run(i.id)}>撤回</Button>
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
  const [role, setRole] = useState<Role>("member");
  const [email, setEmail] = useState("");
  const invite = useAction(() => cloud.invite(account.sub, view.id, role, email.trim()));
  const roles: Role[] = view.role === "owner" ? ["member", "admin", "owner"] : ["member", "admin"];
  const valid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
  return (
    <Dialog open onClose={onClose} title="邀请成员" description={`对方用这个邮箱登录 ember，就会看到加入「${view.name}」的邀请。邀请 7 天内有效。`}
      footer={invite.result ? <Button variant="primary" onClick={onClose}>完成</Button> : <>
        <Button variant="ghost" onClick={onClose}>取消</Button>
        <Button variant="primary" disabled={!valid} busy={invite.busy} onClick={() => invite.run()}>邀请</Button>
      </>}>
      {!invite.result ? (
        <>
          <Field label="邮箱" htmlFor="invite-email" hint="对方登录 ember 用的 Google 账号邮箱。">
            <input id="invite-email" className="input" type="email" autoFocus value={email} onChange={(e) => setEmail(e.target.value)} placeholder="name@example.com"
              onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && valid) invite.run(); }} />
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
