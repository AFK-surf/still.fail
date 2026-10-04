import { AutomaticDecisions, AutomaticDecisionCompletion, AutomaticDecisionLogs } from "../AutomaticDecisions.tsx";
// Settings in still.fail cloud, in two parts: the account the current workspace
// is reached through (who you are, where you are signed in), and the
// workspace itself (its name, members, stations, connects and the stations'
// runtime accounts).
import { Illustration } from "../brand.tsx";
import { CHANGEABLE } from "../keymap.ts";
import { CAN_NOTIFY } from "../notify.ts";
import { HAS_VERSION } from "../pages/AppVersion.tsx";
import { ArrowLeft, Bell, Brain, Chart, Check, ChevronRight, Info, Key, LogOut, Monitor, Plug, Plus, Read, Refresh, Server, Settings, Sliders, Sparks, Command, Trash, UserPlus, Users } from "../icons.tsx";
import { useCallback, useEffect, useRef, useState } from "react";
import { Link, Navigate, NavLink, useNavigate, useParams, useSearchParams } from "react-router";
import { useProfiles, useStations, type Profile, type StationView } from "../api.ts";
import type { WorkspaceProfile } from "../core/shapes.ts";
import { ConnectList } from "../pages/Connects.tsx";
import { ACCESS, RUNTIME_LABEL } from "../format.ts";
import { stamp } from "../api.ts";
import { QuotaBars } from "../components.tsx";
import { StationContext, stationBase, type Station } from "../station.tsx";
import { ProfileCard } from "../ProfileCard.tsx";
import { StationList } from "./StationCards.tsx";
import { MemoryView } from "../Memory.tsx";
import { DAYS, PriceTables, UsageBody, usageCss, useUsage, type UsageDays } from "../Usage.tsx";
import { MachineLoginOffers, PROFILE_LEAD, type Choice } from "../pages/Accounts.tsx";
import { addProfilePath } from "../pages/AddProfile.tsx";
import { useCall, useTopic } from "../core/react.ts";
import { failure, useAct, useToast } from "../toast.tsx";
import { About, BackLink, Button, Confirm, CopyCommand, Dialog, Empty, Field, FirstOne, ICON, IconButton, Loading, Menu, MobileBack, Pill, ProviderLogo, RuntimeTags, Section, Segmented, Select, StatusDot, Time } from "../ui.tsx";
import { useSignOut, type Account } from "./accounts.ts";
import { useLastChat } from "../lastChat.ts";
import { parseEmails, useSlackPeople } from "./adding.ts";
import { cloud, errorText, useAction, useWorkspace as useWorkspaceTopic, type LoginSession, type Role, type WorkspaceView } from "./api.ts";
import { Avatar } from "./gate.tsx";
import { DoingMark, DoingShown, useDoingState } from "../DoingMark.tsx";
import { useDoing } from "../doing.ts";
import { track } from "../telemetry.ts";
import type { WorkspaceEntry } from "./workspace.tsx";
import type { CarriedStation } from "../core/client.ts";
import * as nav from "../Sidebar.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as chatCss from "../styles/chat.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as additionsCss from "../styles/additions.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./settings.css.ts";
import * as accountsCss from "../pages/Accounts.css.ts";
import * as waitingCss from "../styles/waiting.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
import { tx } from "./words.tsx";
// Getters: read in the language at the time.
export const ROLE_LABEL: Record<Role, string> = {
  get owner() { return t("web-pages.roles.owner"); },
  get admin() { return t("web-pages.roles.admin"); },
  get member() { return t("web-pages.roles.member"); },
};
export const ROLE_HINT: Record<Role, string> = {
  get owner() { return t("web-pages.roles.ownerHint"); },
  get admin() { return t("web-pages.roles.adminHint"); },
  get member() { return t("web-pages.roles.memberHint"); },
};

/** The sidebar while in settings. */
export function SettingsNav({ entry }: { entry: WorkspaceEntry }) {
  const base = `/w/${entry.id}/settings`;
  // Connects and profiles are a station's: none to show before there is one.
  const some = (useStations(entry.id).value?.length ?? 0) > 0;
  const back = useLastChat(entry.id, `/w/${entry.id}`) ?? `/w/${entry.id}`;
  return (
    <div className={nav.navScroll}>
      <NavLink className={nav.navRow} to={back} end><ArrowLeft {...ICON} />{some ? t("web-pages.settings.nav.backToChats") : t("common.back")}</NavLink>
      <div className={nav.navHeading}>{t("web-pages.settings.nav.client")}</div>
      <NavLink className={nav.navRow} to={`${base}/appearance`}><Sliders {...ICON} />{t("web-pages.settings.nav.appearance")}</NavLink>
      {CAN_NOTIFY && <NavLink className={nav.navRow} to={`${base}/notifications`}><Bell {...ICON} />{t("web-pages.settings.nav.notifications")}</NavLink>}
      {CHANGEABLE && <NavLink className={nav.navRow} to={`${base}/shortcuts`}><Command {...ICON} />{t("web-pages.settings.nav.shortcuts")}</NavLink>}
      {HAS_VERSION && <NavLink className={nav.navRow} to={`${base}/version`}><Info {...ICON} />{t("web-pages.settings.nav.version")}</NavLink>}
      <NavLink className={nav.navRow} to={`${base}/changelog`}><Sparks {...ICON} />{t("web-pages.settings.nav.changelog")}</NavLink>
      <div className={nav.navHeading}>Station</div>
      <NavLink className={nav.navRow} to={`${base}/stations`}><Server {...ICON} />Station</NavLink>
      {some && <NavLink className={nav.navRow} to={`${base}/connects`}><Plug {...ICON} />{t("web-pages.settings.nav.connects")}</NavLink>}
      {some && <NavLink className={nav.navRow} to={`${base}/profiles`}><Key {...ICON} />Profile</NavLink>}
      {some && <NavLink className={nav.navRow} to={`${base}/automatic-decisions`}><Check {...ICON} />{t("web-pages.automaticDecisions.title")}</NavLink>}
      {some && <NavLink className={nav.navRow} to={`${base}/memory`}><Brain {...ICON} />{t("web-pages.settings.nav.memory")}</NavLink>}
      {some && <NavLink className={nav.navRow} to={`${base}/usage`}><Chart {...ICON} />{t("web-pages.settings.nav.usage")}</NavLink>}
      <div className={nav.navHeading}>Cloud</div>
      <NavLink className={nav.navRow} to={`${base}/workspace`}><Users {...ICON} /><span className={nav.navText}>Workspace · {entry.name}</span></NavLink>
      <NavLink className={nav.navRow} to={`${base}/account`}><Avatar account={entry.account} size={18} /><span className={nav.navText}>{entry.account.email}</span></NavLink>
    </div>
  );
}

function Page({ title, lead, back, backLabel, actions, children }: { title: string; lead?: string; back: string; backLabel?: string; actions?: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      {backLabel ? <BackLink to={back} label={backLabel} /> : <MobileBack to={back} label={t("web-pages.settings.title")} />}
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
  const navigate = useNavigate();
  const [signingOut, setSigningOut] = useState(false);
  const signOut = useSignOut();
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={`/w/${entry.id}/settings`} label={t("web-pages.settings.title")} />
      <header className={pagesCss.identity}>
        <Avatar account={account} size={52} />
        <div className={pagesCss.identityText}>
          <h1 className={pagesCss.identityName}>{account.name || account.email}</h1>
          <p className={pagesCss.identitySub}><span>{account.email}</span><span>{t("web-pages.settings.account.google")}</span></p>
        </div>
      </header>
      <Section title={t("web-pages.settings.account.sessions")} description={t("web-pages.settings.account.sessionsLead", { name: NAME })}>
        {!devices.value ? devices.error ? <p className={controlsCss.fieldError}>{t("web-pages.settings.account.sessionsFailed", { error: devices.error.message })}</p> : <Loading label={t("web-pages.settings.reading")} fill={false} /> : (
          <ul className={pagesCss.list}>
            {devices.value.map((s) => (
              <li key={s.id} className={pagesCss.listRow}>
                <span className={pagesCss.listRowText}>
                  <span className={pagesCss.listRowTitle}>{s.name || t("web-pages.settings.account.unnamedDevice")}{s.current && <span className={additionsCss.choiceBadge}>{t("web-pages.settings.account.here")}</span>}</span>
                  <span className={shellCss.muted}>{tx("web-pages.settings.account.sessionTimes", { time: <Time stamp={stamp(s, "created_at")} />, until: stamp(s, "expires_at")?.until ?? "" })}</span>
                </span>
                {!s.current && <RevokeDevice account={account} id={s.id} />}
              </li>
            ))}
          </ul>
        )}
      </Section>
      <Section title={t("web-pages.settings.account.signOut")}>
        <div className={`${pagesCss.card} ${pagesCss.cardRow}`}>
          <div className={pagesCss.cardRowText}><strong>{t("web-pages.settings.account.signOutHere", { email: account.email })}</strong><span className={shellCss.muted}>{t("web-pages.settings.account.signOutHereBody")}</span></div>
          <Button icon={LogOut} onClick={() => setSigningOut(true)}>{t("web-pages.settings.account.signOutAction")}</Button>
        </div>
      </Section>
      {/* Away at once; signing out goes on by itself, a failure said by toast (useSignOut). */}
      <Confirm open={signingOut} onClose={() => setSigningOut(false)}
        onConfirm={() => { setSigningOut(false); navigate("/"); void signOut.signOut(account.sub).then((out) => { if (out) toast(t("web-pages.settings.account.signedOut", { email: account.email })); }); }}
        title={t("web-pages.settings.account.signOutConfirm", { email: account.email })} action={t("web-pages.settings.account.signOutAction")} description={t("web-pages.settings.account.signOutConfirmBody")} />
    </div>
  );
}

/**
 * Signing a device out, each on its own: the button turns until the cloud has it, whichever others are on their way;
 * a failure is said by toast.
 */
function RevokeDevice({ account, id }: { account: Account; id: string }) {
  const toast = useToast();
  const busy = useDoing("loginSession.revoke", { account: account.sub, id });
  const revoke = () => void cloud.revokeLoginSession(account.sub, id).then(() => toast(t("web-pages.settings.account.revoked")),
    (e: unknown) => toast(t("web-pages.settings.account.revokeFailed", { error: failure(e) })));
  return <Button variant="ghost" busy={busy} onClick={revoke}>{t("web-pages.settings.account.revoke")}</Button>;
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
  const rename = useAction(() => cloud.renameWorkspace(account.sub, entry.id, name), () => toast(t("web-pages.settings.workspace.renamed")));
  const [leaving, setLeaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const leave = useAction(() => cloud.removeMember(account.sub, entry.id, account.sub), () => toast(t("web-pages.settings.workspace.left")));
  const remove = useAction(() => cloud.deleteWorkspace(account.sub, entry.id), () => toast(t("web-pages.settings.workspace.deleted")));
  if (!view) return <Loading label={t("web-pages.settings.workspace.loading")} />;
  return (
    <Page title="Workspace" back={`/w/${entry.id}/settings`}>
      <Section title={t("web-pages.settings.workspace.name")}>
        <div className={pagesCss.card}>
          <Field label={t("web-pages.settings.workspace.nameLabel")} htmlFor="ws-rename" hint={manager ? undefined : t("web-pages.settings.workspace.nameHint")} error={rename.error ? t("web-pages.settings.workspace.renameFailed", { error: rename.error.message }) : undefined}>
            <div className={additionsCss.inputRow}>
              <input id="ws-rename" className={controlsCss.input} value={name} maxLength={80} disabled={!manager} onChange={(e) => setName(e.target.value)} />
              {manager && <Button variant="primary" disabled={!name.trim() || name.trim() === view.name} busy={rename.busy} onClick={() => rename.run()}>{t("common.save")}</Button>}
            </div>
          </Field>
          <p className={`${shellCss.muted} ${controlsCss.cardFoot}`}>{t("web-pages.settings.workspace.youAre", { role: ROLE_LABEL[view.role], email: account.email })}</p>
        </div>
      </Section>
      <Members view={view} account={account} manager={manager} />
      <Relays view={view} account={account} manager={manager} />
      <Section title={t("web-pages.settings.workspace.leaveDelete")}>
        {/* One card, as the name's: leaving, and (the owner) deleting, each asked again before it is done. */}
        <div className={pagesCss.card}>
          <div className={pagesCss.cardRow}>
            <div className={pagesCss.cardRowText}><strong>{t("web-pages.settings.workspace.leave")}</strong><span className={shellCss.muted}>{t("web-pages.settings.workspace.leaveBody")}</span></div>
            <Button variant="danger" icon={LogOut} onClick={() => setLeaving(true)}>{t("web-pages.settings.workspace.leaveAction")}</Button>
          </div>
          {view.role === "owner" && (
            <div className={pagesCss.cardRow}>
              <div className={pagesCss.cardRowText}><strong>{t("web-pages.settings.workspace.delete")}</strong><span className={shellCss.muted}>{t("web-pages.settings.workspace.deleteBody", { name: NAME })}</span></div>
              <Button variant="danger" icon={Trash} onClick={() => setDeleting(true)}>{t("common.delete")}</Button>
            </div>
          )}
        </div>
      </Section>
      {/* Away at once: it goes on by itself, a failure said by toast. */}
      <Confirm open={leaving} onClose={() => setLeaving(false)} onConfirm={() => { setLeaving(false); navigate("/"); void leave.run(); }}
        title={t("web-pages.settings.workspace.leaveConfirm", { name: view.name })} action={t("web-pages.settings.workspace.leaveAction")} description={t("web-pages.settings.workspace.leaveConfirmBody")} />
      <Confirm open={deleting} onClose={() => setDeleting(false)} onConfirm={() => { setDeleting(false); navigate("/"); void remove.run(); }}
        title={t("web-pages.settings.workspace.deleteConfirm", { name: view.name })} action={t("web-pages.settings.workspace.delete")}
        description={t("web-pages.settings.workspace.deleteConfirmBody", { n: view.stations.length, name: NAME })} />
    </Page>
  );
}

export function StationsSettings({ entry }: { entry: WorkspaceEntry }) {
  const { view, manager } = useWorkspace(entry);
  const stations = useStations(entry.id).value;
  if (!view || !stations) return <Loading label={t("web-pages.settings.workspace.loading")} />;
  return (
    <Page title="Station" lead={t("web-pages.settings.stations.lead", { name: NAME })} back={`/w/${entry.id}/settings`}>
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
    <Page title={t("web-pages.settings.memory.title")} lead={t("web-pages.settings.memory.lead")} back={`/w/${entry.id}/settings`}>
      {stations.map((s) => (
        <div key={s.id} className={css.memoryStation}>
          {stations.length > 1 && <h2 className={css.memoryStationName}>{s.name}</h2>}
          {s.online ? <MemoryView station={s.station} /> : <p className={shellCss.muted}>{t("web-pages.settings.memory.offline")}</p>}
        </div>
      ))}
    </Page>
  );
}

/** What the agents of the workspace's stations spent (../Usage.tsx). */
export function UsageSettings({ entry }: { entry: WorkspaceEntry }) {
  const listed = useStations(entry.id).value;
  const [days, setDays] = useState<UsageDays>("7");
  const usage = useUsage(entry.id, days);
  if (listed?.length === 0) return <Navigate to={`/w/${entry.id}/settings/stations`} replace />;
  return (
    <Page title={t("web-pages.settings.usage.title")} lead={t("web-pages.settings.usage.lead")} back={`/w/${entry.id}/settings`}
      actions={<Segmented<UsageDays> className={usageCss.pick} label={t("web-pages.settings.usage.days")} value={days} onChange={setDays} options={DAYS} />}>
      {usage.value ? <UsageBody view={usage.value} pricesPath={`/w/${entry.id}/settings/usage/prices?days=${days}`} />
        : usage.error ? <p className={controlsCss.fieldError}>{t("web-pages.settings.usage.failed", { error: usage.error.message })}</p> : <Loading label={t("web-pages.settings.reading")} fill={false} />}
    </Page>
  );
}

export function UsagePricesSettings({ entry }: { entry: WorkspaceEntry }) {
  const [params] = useSearchParams();
  const usage = useUsage(entry.id, params.get("days") === "30" ? "30" : "7");
  return <Page title={t("web-pages.settings.prices.title")} lead={t("web-pages.settings.prices.lead")} back={`/w/${entry.id}/settings/usage`}>
    {usage.value ? <PriceTables view={usage.value} /> : <Loading label={usage.error ? t("web-pages.settings.prices.failed", { error: usage.error.message }) : t("web-pages.settings.reading")} fill={false} />}
  </Page>;
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
  const navigate = useNavigate();
  // A profile is added on its own page (pages/AddProfile.tsx), on the station it runs on.
  const setAdding = (station: string) => navigate(addProfilePath(entry.id, station));
  const addPlan = (station: string, c: Choice) => navigate(addProfilePath(entry.id, station, c === "claude-sub" ? "anthropic" : "openai", "plan"));
  const online = stations.filter((s) => s.online);
  const profiles = useProfiles(entry.id);
  // Which station a profile is added to, asked when there are several.
  const [choosing, setChoosing] = useState(false);
  const asStation = (s: (typeof stations)[number]): Station => ({ id: s.id, name: s.name, online: s.online, address: s.station, base: stationBase(s.station), settings: `/w/${entry.id}/settings` });
  if (listed?.length === 0) return <Navigate to={`/w/${entry.id}/settings/stations`} replace />;
  // Not one profile on any station (each read): the page is about adding the first.
  const first = stations.length > 0 && stations.every((s) => s.overview && s.overview.profiles.length === 0);
  return (
    <Page title="Profile" lead={t("web-pages.settings.profiles.lead", { name: NAME })} back={`/w/${entry.id}/settings`}
      actions={!first && online.length > 0 && <Button icon={Plus} onClick={() => (online.length === 1 ? setAdding(online[0]!.station) : setChoosing(true))}>{t("web-pages.settings.profiles.add")}</Button>}>
      {first ? (
        <FirstOne art={<Illustration name="no-profile" />} title={t("web-pages.settings.profiles.addFirst")} lead={PROFILE_LEAD}>
          {/* Each station in a row: where a profile is added is part of adding it. */}
          <div className={css.firstStations}>
            {stations.map((s) => (
              <div key={s.id} className={css.firstStation}>
                <div className={css.firstStationRow}>
                  <StatusDot state={s.online ? "online" : "offline"} label={s.online ? t("web-pages.stations.online") : t("web-pages.stations.offline")} />
                  <span className={css.firstStationName}>{s.name}</span>
                  {s.online
                    ? <Button variant={stations.length === 1 ? "primary" : "secondary"} icon={Plus} onClick={() => setAdding(s.station)}>{t("web-pages.settings.profiles.add")}</Button>
                    : <span className={shellCss.muted}>{t("web-pages.settings.profiles.offlineAdd")}</span>}
                </div>
                {s.online && (
                  <StationContext.Provider value={asStation(s)}>
                    <MachineLoginOffers logins={s.overview?.machineLogins} onAdd={(c) => addPlan(s.station, c)} />
                  </StationContext.Provider>
                )}
              </div>
            ))}
          </div>
        </FirstOne>
      ) : (
        <>
          {/* The workspace's profiles in one list: one shared between stations once (where it is signed in, or which
              stations may use it, in its line), the others each with the station they are on (the core's `profiles`). */}
          {profiles.value && profiles.value.items.length > 0 && (
            <ul className={pagesCss.list}>
              {profiles.value.items.map((e) => (
                <li key={e.key}><WorkspaceProfileRow entry={e} workspace={entry.id} /></li>
              ))}
            </ul>
          )}
          {profiles.value?.loading && <Loading label={t("web-pages.settings.reading")} fill={false} />}
          {/* The machines' own logins not used yet, each where it is. */}
          {online.map((station) => (
            <StationContext.Provider key={station.id} value={asStation(station)}>
              <MachineLoginOffers logins={station.overview?.machineLogins} onAdd={(c) => addPlan(station.station, c)} />
            </StationContext.Provider>
          ))}
        </>
      )}
      <Dialog open={choosing} onClose={() => setChoosing(false)} title={t("web-pages.settings.profiles.addWhere")} description={t("web-pages.settings.profiles.addWhereLead")}>
        <ul className={pagesCss.list}>
          {online.map((st) => (
            <li key={st.id}><button type="button" className={`${pagesCss.listRow} ${accountsCss.pickRow}`} onClick={() => { setChoosing(false); setAdding(st.station); }}>
              <StatusDot state="online" /><span className={pagesCss.listRowTitle}>{st.name}</span>
            </button></li>
          ))}
        </ul>
      </Dialog>
    </Page>
  );
}

/** An account's page, where it is on several stations. */
export const accountPath = (workspace: string, key: string) => `/w/${workspace}/settings/profiles/account/${encodeURIComponent(key)}`;

/**
 * An account on several stations (the same subscription or key, shared or signed in on each): what they have in common
 * (its allowance, how it is doing), then each station's part (lending it, borrowing it, signed in on its own), each
 * leading to its page there.
 */
export function ProfileAccountSettings({ entry }: { entry: WorkspaceEntry }) {
  const { key = "" } = useParams();
  const view = useProfiles(entry.id).value;
  const found = view?.items.find((e) => e.key === key);
  const back = `/w/${entry.id}/settings/profiles`;
  if (!view) return <Page title="Profile" back={back}><Loading label={t("web-pages.settings.reading")} fill={false} /></Page>;
  if (!found) return <Page title="Profile" back={back}><p className={shellCss.muted}>{t("web-pages.profiles.notFound", { id: key })}</p></Page>;
  const p = found.profile;
  const kind = p.machine ? t("web-main.profile.machine") : p.providerName ?? ACCESS[p.access.kind].label;
  return (
    <Page title={p.name} lead={[p.email, kind].filter(Boolean).join(" · ")} back={back} backLabel="Profile">
      <Section title={t("web-pages.profiles.account.common")} description={t("web-pages.profiles.account.commonLead")}>
        <div className={css.accountState}>
          {p.checkTone !== "green" && <Pill tone={p.checkTone}>{p.checkText}</Pill>}
          <span className={shellCss.muted}>{p.check ? p.check.detail : t("web-pages.profiles.neverChecked")}</span>
        </div>
        <QuotaBars quota={p.quota} />
        {p.modelsText && <p className={shellCss.muted}>{p.modelsText}</p>}
      </Section>
      <Section title={t("web-pages.profiles.account.each")} description={t("web-pages.profiles.account.eachLead")}>
        <ul className={pagesCss.list}>
          {(found.members ?? []).map((m) => (
            <li key={m.station}>
              <Link className={pagesCss.listRow} to={`${stationBase(m.station)}/settings/accounts/${encodeURIComponent(m.profileId)}`}>
                <StatusDot state={m.online ? "online" : "offline"} />
                <span className={pagesCss.listRowText}>
                  <span className={pagesCss.listRowTitle}>{m.stationName}</span>
                  <span className={shellCss.muted}>{[m.about, m.usedBy > 0 ? t("web-pages.settings.profiles.usedBy", { n: m.usedBy }) : ""].filter(Boolean).join(" · ")}</span>
                </span>
                {!m.online ? <Pill tone="neutral">{t("web-pages.stations.offline")}</Pill> : !m.usable ? <Pill tone="red">{t("web-pages.settings.profiles.hostAway", { station: found.hostName })}</Pill> : m.checkTone !== "green" && <Pill tone={m.checkTone as never}>{m.checkText}</Pill>}
                <ChevronRight {...ICON} className={shellCss.muted} />
              </Link>
            </li>
          ))}
        </ul>
      </Section>
    </Page>
  );
}

/** A profile of the workspace's list: on its page's station; one shared that cannot be used now (its subscription's
 * station away) dimmed, and said why. */
function WorkspaceProfileRow({ entry, workspace }: { entry: WorkspaceProfile; workspace: string }) {
  const state = useDoingState(["profile.delete", "profile.share", "profile.move"], { station: entry.station, id: entry.profile.id });
  const uses = [entry.where, entry.profile.usedBy.length ? t("web-pages.settings.profiles.usedBy", { n: entry.profile.usedBy.length }) : ""].filter(Boolean).join(" · ");
  // On several stations: its own page, what they share and what each has; on one: that station's page.
  const to = (entry.members?.length ?? 0) > 1 ? accountPath(workspace, entry.key) : `${stationBase(entry.station)}/settings/accounts/${encodeURIComponent(entry.profile.id)}`;
  return (
    <div className={entry.usable ? undefined : css.profileAway}>
      <ProfileCard profile={entry.profile} to={to} uses={uses}
        state={entry.usable ? undefined : <Pill tone="red">{t("web-pages.settings.profiles.hostAway", { station: entry.hostName })}</Pill>}
        action={state.running || state.error !== undefined ? <DoingShown state={state} className={controlsCss.iconSpinner} size={14} label={t("web-main.activity.busy")} /> : undefined} />
    </div>
  );
}

function Stations({ view, account, manager, stations }: { view: WorkspaceView; account: Account; manager: boolean; stations: StationView[] }) {
  const [adding, setAdding] = useState(false);
  const [removing, setRemoving] = useState<StationView | null>(null);
  const remove = useAction((s: StationView) => cloud.removeStation(account.sub, view.id, s.id));
  const rename = useAction(({ id, name }: { id: string; name: string }) => cloud.renameStation(account.sub, view.id, id, name));
  const renaming = (s: StationView) => rename.busy && rename.arg?.id === s.id;
  return (
    <Section title={t("web-pages.settings.stations.count", { n: stations.length })} actions={manager && <><JoinThisMac account={account} workspace={view.id} /><Button icon={Plus} onClick={() => setAdding(true)}>{t("web-pages.settings.stations.add")}</Button></>}>
      {/* A name or a removal on its way shows at once, a ring beside its menu until the cloud has it (a red mark a moment if not). */}
      <StationList stations={stations.map((s) => (renaming(s) ? { ...s, name: rename.arg!.name } : s))} manager={manager} menu={(s) => manager && <>
        <DoingMark calls={["workspace.renameStation", "workspace.removeStation"]} on={{ account: account.sub, workspace: view.id, station: s.id }} className={controlsCss.iconSpinner} size={14}
          label={renaming(s) ? t("web-pages.settings.stations.renaming") : t("web-main.activity.busy")} />
        <Menu items={[
          { label: t("web-pages.settings.stations.rename"), disabled: renaming(s), onSelect: () => { const n = window.prompt(t("web-pages.settings.stations.namePrompt"), s.name); if (n?.trim() && n.trim() !== s.name) rename.run({ id: s.id, name: n.trim() }); } },
          { label: t("web-pages.settings.stations.remove"), icon: Trash, danger: true, onSelect: () => setRemoving(s) },
        ]} />
      </>} />
      {rename.error && <p className={controlsCss.fieldError} role="alert">{t("web-pages.settings.stations.renameFailed", { name: stations.find((s) => s.id === rename.arg?.id)?.name ?? "station", error: rename.error.message })}</p>}
      {adding && <AddStationDialog view={view} account={account} stations={stations} onClose={() => setAdding(false)} />}
      <Confirm open={removing !== null} onClose={() => setRemoving(null)} onConfirm={() => { if (removing) void remove.run(removing); setRemoving(null); }}
        title={t("web-pages.settings.stations.removeConfirm", { name: removing?.name ?? "" })} action={t("web-pages.settings.stations.removeAction")}
        description={t("web-pages.settings.stations.removeConfirmBody", { name: NAME })} />
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
    <Dialog open onClose={onClose} wide title={t("web-pages.settings.stations.add")}
      description={t("web-pages.settings.stations.addLead")}
      footer={joined ? <Button variant="primary" onClick={onClose}>{t("common.done")}</Button> : <>
        <Button variant="ghost" onClick={onClose}>{enroll.result ? t("common.close") : t("common.cancel")}</Button>
        {!enroll.result && <Button variant="primary" disabled={!name.trim()} busy={enroll.busy} onClick={() => enroll.run()}>{t("web-pages.settings.stations.generate")}</Button>}
      </>}>
      {!enroll.result ? (
        <Field label={t("web-pages.settings.stations.nameLabel")} htmlFor="station-name">
          <input id="station-name" className={controlsCss.input} value={name} autoFocus placeholder={t("web-pages.settings.stations.namePlaceholder")} onChange={(e) => setName(e.target.value)} maxLength={80}
            onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && name.trim() && !enroll.busy) enroll.run(); }} />
        </Field>
      ) : joined ? (
        <div className={additionsCss.callout} data-tone="green"><Check {...ICON} /><span>{t("web-pages.settings.stations.joined", { name: joined.name })}</span></div>
      ) : <EnrollSteps enrollment={enroll.result} />}
      {enroll.error && <p className={controlsCss.fieldError} role="alert">{enroll.error.message}</p>}
    </Dialog>
  );
}

/**
 * 「添加这台 Mac」, in the desktop app: the station it carries joined to this workspace at a click, while it is in none
 * (never joined, or removed from its workspace: the app joins a removed one again only when asked). Nothing in a
 * browser, or in an app from before it. Once joined, the station shows in the list by itself, as one added by command.
 */
function JoinThisMac({ account, workspace, className }: { account: Account; workspace: string; className?: string }) {
  const desktop = typeof window !== "undefined" ? window.stillfailDesktop?.station : undefined;
  const toast = useToast();
  const [here, setHere] = useState<CarriedStation | null>(null);
  // Read again every few seconds: a station removed from its workspace marks itself so only once the cloud has told it.
  useEffect(() => {
    if (!desktop) return;
    let live = true;
    const read = () => void desktop.state().then((s) => { if (live) setHere(s); }, () => undefined);
    read();
    const timer = setInterval(read, 3000);
    return () => { live = false; clearInterval(timer); };
  }, [desktop]);
  const join = useAction(async () => {
    const done = await desktop!.join(account.sub, workspace);
    if (!done) throw new Error(t("web-pages.settings.thisMac.noAnswer"));
    if ("error" in done) throw new Error(done.error);
    return done.station;
  }, (s) => { setHere(s); toast(t("web-pages.settings.thisMac.joined")); });
  if (!desktop || !here?.carried || here.state === "running") return null;
  return <Button icon={Monitor} className={className} busy={join.busy} onClick={() => join.run()}>{t("web-pages.settings.thisMac.add")}</Button>;
}

/** An enrollment's command, and that the station is awaited. */
function EnrollSteps({ enrollment }: { enrollment: { install: string } }) {
  return (
    <>
      <p>{t("web-pages.settings.enroll.run")}<About>{t("web-pages.settings.enroll.about", { name: NAME })}</About></p>
      <CopyCommand text={enrollment.install} />
      <div className={css.enrollWait} role="status">
        <span className={waitingCss.spinner} aria-hidden="true" />
        <span><strong>{t("web-pages.settings.enroll.waiting")}</strong><span className={shellCss.muted}>{t("web-pages.settings.enroll.waitingNote")}</span></span>
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
  if (!view) return <Loading label={t("web-pages.settings.workspace.loading")} fill={false} />;
  if (!manager) return <div className={additionsCss.callout}>{t("web-pages.settings.stations.noneYet")}</div>;
  if (enroll.result) return <div className={css.onboardingCard}><EnrollSteps enrollment={enroll.result} /></div>;
  return (
    <div className={css.onboardingCard}>
      <Field label={t("web-pages.settings.stations.nameFirst")} htmlFor="first-station-name">
        <div className={css.onboardingRow}>
          <input id="first-station-name" className={controlsCss.input} value={name} autoFocus placeholder={t("web-pages.settings.stations.namePlaceholder")} onChange={(e) => setName(e.target.value)} maxLength={80}
            onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && name.trim() && !enroll.busy) enroll.run(); }} />
          <Button variant="primary" disabled={!name.trim()} busy={enroll.busy} onClick={() => enroll.run()}>{t("web-pages.settings.stations.generate")}</Button>
        </div>
      </Field>
      {enroll.error && <p className={controlsCss.fieldError} role="alert">{enroll.error.message}</p>}
      <JoinThisMac account={entry.account} workspace={entry.id} className={css.firstThisMac} />
    </div>
  );
}

/** A relay's URL as shown: without its scheme. */
const relayLabel = (url: string) => url.replace(/^https?:\/\//, "");

/**
 * The workspace's own relays, used besides still.fail's by its stations and its members' devices: owners and admins
 * add and remove them, the rest see them.
 */
function Relays({ view, account, manager }: { view: WorkspaceView; account: Account; manager: boolean }) {
  const relays = view.relays ?? [];
  const [adding, setAdding] = useState("");
  const set = useAction((next: string[]) => cloud.setRelays(account.sub, view.id, next), (_r, next) => { if (next.length > relays.length) setAdding(""); });
  const add = () => { const url = adding.trim(); if (url) void set.run([...relays, url]); };
  if (!manager && relays.length === 0) return null;
  return (
    <Section title={t("web-pages.settings.relays.title")} description={t("web-pages.settings.relays.lead", { name: NAME })}>
      <div className={pagesCss.card}>
        {/* Rows of the card, as leaving and deleting are: on the card's own edges. */}
        {relays.map((url) => (
          <div key={url} className={pagesCss.cardRow}>
            <span className={pagesCss.cardRowText}><strong>{relayLabel(url)}</strong></span>
            {manager && <Button variant="ghost" busy={set.busy && !set.arg?.includes(url)} disabled={set.busy} onClick={() => set.run(relays.filter((u) => u !== url))}>{t("web-pages.settings.relays.remove")}</Button>}
          </div>
        ))}
        {manager && (
          <Field label={t("web-pages.settings.relays.add")} htmlFor="ws-relay" hint={t("web-pages.settings.relays.hint")}>
            <div className={additionsCss.inputRow}>
              <input id="ws-relay" className={controlsCss.input} value={adding} placeholder="https://relay.example.com" inputMode="url" autoComplete="off" spellCheck={false}
                onChange={(e) => setAdding(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") add(); }} />
              <Button variant="primary" disabled={!adding.trim() || set.busy} busy={set.busy && (set.arg?.length ?? 0) > relays.length} onClick={add}>{t("web-pages.settings.relays.addAction")}</Button>
            </div>
          </Field>
        )}
      </div>
    </Section>
  );
}

function Members({ view, account, manager }: { view: WorkspaceView; account: Account; manager: boolean }) {
  const toast = useToast();
  const [inviting, setInviting] = useState(false);
  const setRole = useAction(({ sub, role }: { sub: string; role: Role }) => cloud.setRole(account.sub, view.id, sub, role), () => toast(t("web-pages.settings.members.roleChanged")));
  const remove = useAction((sub: string) => cloud.removeMember(account.sub, view.id, sub), () => toast(t("web-pages.settings.members.removed")));
  const revoke = useAction((id: string) => cloud.revokeInvitation(account.sub, view.id, id));
  const unadd = useAction((email: string) => cloud.removeAdded(account.sub, view.id, email));
  return (
    <Section title={t("web-pages.settings.members.count", { n: view.members.length })} actions={manager && <Button icon={UserPlus} onClick={() => setInviting(true)}>{t("web-pages.settings.members.add")}</Button>}>
      <ul className={pagesCss.list}>
        {view.members.map((m) => (
          <li key={m.sub} className={pagesCss.listRow}>
            <Avatar account={m} size={28} />
            <span className={pagesCss.listRowText}>
              <span className={pagesCss.listRowTitle}>{m.name || m.email}{m.sub === account.sub && <span className={additionsCss.choiceBadge}>{t("web-pages.settings.members.you")}</span>}</span>
              <span className={shellCss.muted}>{m.email}</span>
            </span>
            {view.role === "owner" && m.sub !== account.sub ? (
              <div className={css.roleSelect}>
                <Select value={setRole.busy && setRole.arg?.sub === m.sub ? setRole.arg.role : m.role} disabled={setRole.busy && setRole.arg?.sub === m.sub}
                  onChange={(role) => setRole.run({ sub: m.sub, role: role as Role })} label={t("web-pages.settings.members.role")}
                  options={(["owner", "admin", "member"] as Role[]).map((r) => ({ value: r, label: ROLE_LABEL[r] }))} />
              </div>
            ) : <Pill>{ROLE_LABEL[m.role]}</Pill>}
            {/* Its role or its removal on the way, wherever asked; failed: a red mark a few seconds, why on hover. */}
            <DoingMark calls={["workspace.setRole", "workspace.removeMember"]} on={{ account: account.sub, workspace: view.id, member: m.sub }}
              className={controlsCss.iconSpinner} size={14} label={remove.busy && remove.arg === m.sub ? t("web-pages.settings.members.removing") : t("web-pages.settings.members.changingRole")} />
            {manager && m.sub !== account.sub && (m.role !== "owner" || view.role === "owner") && !(remove.busy && remove.arg === m.sub) && (
              <Menu items={[{ label: t("web-pages.settings.members.remove"), icon: Trash, danger: true, onSelect: () => { if (window.confirm(t("web-pages.settings.members.removeConfirm", { email: m.email, name: view.name }))) remove.run(m.sub); } }]} />
            )}
          </li>
        ))}
      </ul>
      {(setRole.error || remove.error) && <p className={controlsCss.fieldError} role="alert">{(setRole.error ?? remove.error)!.message}</p>}
      {unadd.error && <p className={controlsCss.fieldError} role="alert">{t("web-pages.settings.members.unaddFailed", { email: unadd.arg ?? "", error: unadd.error.message })}</p>}
      {manager && view.added.length > 0 && (
        <>
          <div className={css.groupHead}><strong>{t("web-pages.settings.members.added")}</strong><span className={shellCss.muted}>{t("web-pages.settings.members.addedNote", { n: view.added.length, name: NAME })}</span></div>
          <ul className={pagesCss.list}>
            {view.added.map((a) => (
              <li key={a.email} className={pagesCss.listRow}>
                <span className={pagesCss.listRowText}>
                  <span className={pagesCss.listRowTitle}>{a.email}</span>
                  <span className={shellCss.muted}>{ROLE_LABEL[a.role]}</span>
                </span>
                <Button variant="ghost" busy={unadd.busy && unadd.arg === a.email} onClick={() => unadd.run(a.email)}>{t("web-pages.settings.members.unadd")}</Button>
              </li>
            ))}
          </ul>
        </>
      )}
      {manager && view.invitations.length > 0 && (
        <>
          <div className={css.groupHead}><strong>{t("web-pages.settings.members.invitations")}</strong><span className={shellCss.muted}>{t("web-pages.settings.members.invitationsCount", { n: view.invitations.length })}</span></div>
          <ul className={pagesCss.list}>
            {view.invitations.map((i) => (
              <li key={i.id} className={pagesCss.listRow}>
                <span className={pagesCss.listRowText}>
                  <span className={pagesCss.listRowTitle}>{i.email ?? t("web-pages.settings.members.anyone")}</span>
                  <span className={shellCss.muted}>{t("web-pages.settings.members.invitationNote", { role: ROLE_LABEL[i.role], until: stamp(i, "expires_at")?.until ?? "" })}</span>
                </span>
                <Button variant="ghost" busy={revoke.busy && revoke.arg === i.id} onClick={() => revoke.run(i.id)}>{t("web-pages.settings.members.revoke")}</Button>
              </li>
            ))}
          </ul>
          {revoke.error && <p className={controlsCss.fieldError} role="alert">{t("web-pages.settings.members.revokeFailed", { error: revoke.error.message })}</p>}
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
    <Dialog open onClose={onClose} title={t("web-pages.settings.members.add")} description={t("web-pages.settings.members.addLead", { workspace: view.name, name: NAME })}
      footer={done ? <Button variant="primary" onClick={onClose}>{t("common.done")}</Button> : <>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" disabled={emails.length === 0} busy={add.busy} onClick={() => add.run()}>{emails.length > 1 ? t("web-pages.settings.members.addN", { n: emails.length }) : t("web-pages.settings.members.addOne")}</Button>
      </>}>
      {!done ? (
        <>
          <Field label={t("web-pages.settings.members.emails")} htmlFor="add-emails" hint={t("web-pages.settings.members.emailsHint", { name: NAME })}>
            <textarea id="add-emails" className={controlsCss.input} rows={3} autoFocus value={text} onChange={(e) => setText(e.target.value)} placeholder="name@example.com" />
          </Field>
          {slack.available && (
            slack.people === null ? (
              <Button variant="secondary" busy={slack.busy} onClick={fromSlack}>{t("web-pages.settings.members.fromSlack")}</Button>
            ) : (
              <div className={chatCss.modelPool}>
                <div className={chatCss.modelPoolTools}>
                  <span className={shellCss.muted}>{t("web-pages.settings.members.slackPicked", { n: slack.people.length, picked: [...picked].filter((e) => !inside.has(e)).length })}</span>
                  <button type="button" className={controlsCss.textToggle} onClick={() => setPicked(new Set(slack.people!.filter((p) => !inside.has(p.email)).map((p) => p.email)))}>{t("web-pages.settings.members.all")}</button>
                  <button type="button" className={controlsCss.textToggle} onClick={() => setPicked(new Set())}>{t("web-pages.settings.members.none")}</button>
                </div>
                <ul className={chatCss.modelPoolList}>
                  {slack.people.map((p) => (
                    <li key={p.email}>
                      <label className={chatCss.modelPoolItem} data-on={picked.has(p.email) || inside.has(p.email) || undefined}>
                        <input type="checkbox" disabled={inside.has(p.email)} checked={picked.has(p.email) || inside.has(p.email)} onChange={() => toggle(p.email)} />
                        <span>{p.name}</span>
                        <span className={shellCss.muted}>{p.email}</span>
                        {inside.has(p.email) ? <span className={shellCss.muted}>{t("web-pages.settings.members.inside")}</span> : p.guest && <span className={shellCss.muted}>{t("web-pages.settings.members.guest")}</span>}
                      </label>
                    </li>
                  ))}
                </ul>
                {slack.errors.length > 0 && <p className={controlsCss.fieldError}>{slack.errors.join(t("web-pages.settings.members.errorSeparator"))}</p>}
              </div>
            )
          )}
          <Field label={t("web-pages.settings.members.role")} hint={ROLE_HINT[role]}>
            <Select value={role} onChange={(r) => setRole(r as Role)} label={t("web-pages.settings.members.role")} options={roles.map((r) => ({ value: r, label: ROLE_LABEL[r] }))} />
          </Field>
        </>
      ) : (
        <div className={additionsCss.callout} data-tone="green"><Check {...ICON} /><span>{t("web-pages.settings.members.doneSentence", { list: [
          done.joined.length ? t("web-pages.settings.members.doneJoined", { n: done.joined.length }) : "",
          done.added.length ? t("web-pages.settings.members.doneAdded", { n: done.added.length, name: NAME }) : "",
          done.already.length ? t("web-pages.settings.members.doneAlready", { n: done.already.length }) : "",
        ].filter(Boolean).join(t("web-pages.settings.members.doneSeparator")) })}</span></div>
      )}
      {add.error && <p className={controlsCss.fieldError} role="alert">{errorText(add.error)}</p>}
    </Dialog>
  );
}

export function AutomaticDecisionsSettings({entry}:{entry:WorkspaceEntry}) {
  return <Page title={t("web-pages.automaticDecisions.title")} lead={t("web-pages.automaticDecisions.choosePoint")} back={`/w/${entry.id}/settings`}><AutomaticDecisions workspace={entry.id} /></Page>;
}

export function AutomaticDecisionCompletionSettings({entry}:{entry:WorkspaceEntry}) {
  const navigate=useNavigate();
  const call=useCall(); const act=useAct();
  const stations=useStations(entry.id).value;
  const base=`/w/${entry.id}/settings/automatic-decisions`;
  const refresh=()=>Promise.all((stations??[]).filter(s=>s.online).map(s=>act(call("automaticDecisions.refresh",{station:s.station}),t("web-pages.automaticDecisions.refreshAction"),t("web-pages.automaticDecisions.refreshed"))));
  return <Page title={t("web-pages.automaticDecisions.completion")} lead={t("web-pages.automaticDecisions.completionNote")} back={base} backLabel={t("web-pages.automaticDecisions.title")}
    actions={<div style={{display:"flex",gap:4}}><Button variant="ghost" icon={Refresh} onClick={refresh}>{t("web-pages.automaticDecisions.refresh")}</Button><Button variant="ghost" icon={Read} onClick={()=>navigate(`${base}/completion/logs`)}>{t("web-pages.automaticDecisions.logs")}</Button></div>}>
    <AutomaticDecisionCompletion workspace={entry.id} />
  </Page>;
}
export function AutomaticDecisionLogsSettings({entry}:{entry:WorkspaceEntry}) {
  return <Page title={t("web-pages.automaticDecisions.logsTitle")} back={`/w/${entry.id}/settings/automatic-decisions/completion`} backLabel={t("web-pages.automaticDecisions.completion")}>
    <AutomaticDecisionLogs workspace={entry.id} />
  </Page>;
}
