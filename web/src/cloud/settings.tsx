import { AutomaticDecisions, AutomaticDecisionCompletion, AutomaticDecisionPolicy } from "../AutomaticDecisions.tsx";
// Settings in still.fail cloud, in two parts: the account the current workspace
// is reached through (who you are, where you are signed in), and the
// workspace itself (its name, members, stations, connects and the stations'
// runtime accounts).
import { Illustration } from "../brand.tsx";
import { CHANGEABLE } from "../keymap.ts";
import { CAN_NOTIFY } from "../notify.ts";
import { HAS_VERSION } from "../pages/AppVersion.tsx";
import { HAS_LOCAL_STATION } from "../pages/LocalStation.tsx";
import { Archive, ArrowLeft, Bell, Brain, Key, Chart, Check, ChevronRight, Edit, Folder, Im, Info, LogOut, Monitor, Plus, Quota, Refresh, Server, Settings, ShieldCheck, Sliders, Sparks, Command, Trash, User, UserPlus, Users, type IconProps } from "@stillfail/ui/icons.tsx";
import { SecurityNotice } from "./Security.tsx";
import { VaultWaiting } from "./Vault.tsx";
import { useCommands } from "../commands.ts";
import { Fragment, useCallback, useEffect, useRef, useState, type ComponentType, type ReactNode } from "react";
import { Link, Navigate, NavLink, useNavigate, useParams, useSearchParams } from "react-router";
import { useJoinable, useProfiles, useStations, type Profile, type StationView } from "../api.ts";
import { same, type Mark } from "../stationPick.ts";
import { MarkPick } from "./MarkPick.tsx";
import { WorkspaceMark } from "../WorkspaceMark.tsx";
import type { JoinableView, WorkspaceProfile } from "../core/shapes.ts";
import { MarkOrLetter } from "../StationMark.tsx";
import { ConnectList } from "../pages/Connects.tsx";
import { ACCESS, RUNTIME_LABEL } from "../format.ts";
import { stamp } from "../api.ts";
import { QuotaBars } from "../components.tsx";
import { StationContext, stationBase, type Station } from "../station.tsx";
import { useGo } from "../go.ts";
import { ProfileCard } from "../ProfileCard.tsx";
import { StationList } from "./StationCards.tsx";
import { MemoryDoc, MemoryView } from "../Memory.tsx";
import { DAYS, PriceTables, UsageBody, usageCss, useUsage, type UsageDays } from "../Usage.tsx";
import { MachineLoginOffers, PROFILE_LEAD, type Choice } from "../pages/Accounts.tsx";
import { addProfilePath } from "../pages/AddProfile.tsx";
import { profilePath, useProfilesSidebar } from "../ProfilesNav.tsx";
import { useCall, useTopic } from "../core/react.ts";
import { failure, useAct, useToast } from "@stillfail/ui/toast.tsx";
import { About, BackLink, Button, Choices, Confirm, CopyCommand, Dialog, Empty, Field, FirstOne, ICON, IconButton, Menu, MobileBack, Pill, ProviderLogo, RuntimeTags, Section, Segmented, Select, StatusDot, Time, Spinner, Waiting, WaitLine, WaitMore } from "../ui.tsx";
import { useDeleteAccount, useSignOut, type Account } from "./accounts.ts";
import { useLastChat } from "../lastChat.ts";
import { parseEmails, useSlackPeople } from "./adding.ts";
import { cloud, errorText, useAction, useWorkspace as useWorkspaceTopic, type LoginSession, type Role, type WorkspaceView } from "./api.ts";
import { Avatar } from "./gate.tsx";
import { DoingMark, DoingShown, useDoingState } from "../DoingMark.tsx";
import { useDoing } from "../doing.ts";
import { track } from "../telemetry.ts";
import type { WorkspaceEntry } from "./workspace.tsx";
import { JoinThisMac, PC, useJoinThisMac } from "./thisMac.tsx";
import * as nav from "../Sidebar.css.ts";
import { useRailItems, type RailItem } from "../Rail.tsx";
import * as railCss from "../Rail.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as chatCss from "../styles/chat.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as additionsCss from "../styles/additions.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./settings.css.ts";
import * as accountsCss from "../pages/Accounts.css.ts";

import { NAME } from "../channel.ts";
import { StationArchiving } from "../pages/Archiving.tsx";
import { t } from "../i18n.ts";
import { tx } from "./words.tsx";
import * as pageCss from "@stillfail/ui/styles/page.css.ts";
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

/** A settings page, as its sidebar lists it and ⌘K finds it. */
interface SettingsPage { path: string; label: string; icon: ComponentType<IconProps>; words: string; group: "client" | "station" | "cloud" }

/** The settings pages there are here: connects and profiles are a station's, none to show before there is one. */
function settingsPages(entry: WorkspaceEntry, some: boolean): SettingsPage[] {
  const page = (group: SettingsPage["group"], path: string, label: string, icon: ComponentType<IconProps>, words: string, shown = true) =>
    shown ? [{ group, path, label, icon, words }] : [];
  return [
    ...page("client", "appearance", t("web-pages.settings.nav.appearance"), Sliders, "appearance theme language"),
    ...page("client", "notifications", t("web-pages.settings.nav.notifications"), Bell, "notifications", CAN_NOTIFY),
    ...page("client", "permissions", t("web-pages.settings.nav.permissions"), Key, "permissions system allow", CAN_NOTIFY),
    ...page("client", "shortcuts", t("web-pages.settings.nav.shortcuts"), Command, "shortcuts keys", CHANGEABLE),
    ...page("client", "version", t("web-pages.settings.nav.version"), Info, "version update", HAS_VERSION),
    ...page("client", "local-station", t("web-pages.localStation.title"), Monitor, "local station this mac", HAS_LOCAL_STATION),
    ...page("client", "changelog", t("web-pages.settings.nav.changelog"), Sparks, "changelog"),
    ...page("client", "about", t("web-pages.settings.nav.about"), Info, "about privacy telemetry statistics terms"),
    ...page("station", "stations", "Station", Server, "station"),
    ...page("station", "connects", t("web-pages.settings.nav.connects"), Im, "connects slack", some),
    ...page("station", "profiles", "Profile", Quota, "profile", some),
    ...page("station", "archive", t("web-pages.archiving.title"), Archive, "archive archiving auto"),
    ...page("station", "automatic-decisions", t("web-pages.automaticDecisions.title"), Check, "automatic decisions", some),
    ...page("station", "memory", t("web-pages.settings.nav.memory"), Brain, "memory", some),
    ...page("station", "usage", t("web-pages.settings.nav.usage"), Chart, "usage", some),
    ...page("cloud", "workspace", `Workspace · ${entry.name}`, Users, "workspace members"),
    ...page("cloud", "security", t("web-pages.security.title"), ShieldCheck, "security lock devices"),
    ...page("cloud", "vault", t("web-pages.vault.title"), Key, "vault secrets keys tokens"),
    ...page("cloud", "account", entry.account.email, User, "account sign out delete"),
  ];
}

/** ⌘K finds each settings page by its name (or typing 设置 for them all): mounted once under a workspace's pages. */
export function useSettingsCommands(entry: WorkspaceEntry): void {
  const navigate = useNavigate();
  const stations = useStations(entry.id).value;
  const some = (stations?.length ?? 0) > 0;
  const settings = t("web-pages.settings.title");
  const files = t("web-pages.drive.title");
  useCommands([
    ...settingsPages(entry, some).map((p) => ({
      id: `settings/${p.path}`, group: "settings" as const, label: p.label, icon: p.icon, words: `${settings} settings ${p.words}`, typed: true,
      run: () => navigate(`/w/${entry.id}/settings/${p.path}`),
    })),
    // Each station's drive, where it has one (docs/drive.md).
    ...(stations ?? []).filter((s) => s.overview?.drive).map((s) => ({
      id: `drive/${s.id}`, group: "settings" as const, label: `${files} · ${s.name}`, icon: Folder, words: `${files} files drive ${s.name}`, typed: true,
      run: () => navigate(`${stationBase(s.station)}/files`),
    })),
  ]);
}

/** The sidebar while in settings. */
export function SettingsNav({ entry }: { entry: WorkspaceEntry }) {
  const base = `/w/${entry.id}/settings`;
  const some = (useStations(entry.id).value?.length ?? 0) > 0;
  const back = useLastChat(entry.id, `/w/${entry.id}`) ?? `/w/${entry.id}`;
  const pages = settingsPages(entry, some);
  const railed = useRailItems();
  const heading = { client: t("web-pages.settings.nav.client"), station: "Station", cloud: "Cloud" };
  return (
    <div className={nav.navScroll}>
      <NavLink className={nav.navRow} to={back} end><ArrowLeft {...ICON} />{some ? t("web-pages.settings.nav.backToChats") : t("common.back")}</NavLink>
      {(["client", "station", "cloud"] as const).map((group) => (
        <Fragment key={group}>
          <div className={nav.navHeading}>{heading[group]}</div>
          {pages.filter((p) => p.group === group).map((p) => (
            // In the rail, a place is not among the settings (there is no rail on a narrow screen: there it is).
            <NavLink key={p.path} className={railed.includes(p.path as RailItem) ? `${nav.navRow} ${railCss.narrowOnly}` : nav.navRow} to={`${base}/${p.path}`}>
              {p.path === "account" ? <Avatar account={entry.account} size={18} /> : <p.icon {...ICON} />}
              {group === "cloud" ? <span className={nav.navText}>{p.label}</span> : p.label}
              {p.path === "vault" && <VaultWaiting workspace={entry.id} />}
            </NavLink>
          ))}
        </Fragment>
      ))}
    </div>
  );
}

export function Page({ title, lead, back, backLabel, actions, children, entry }: { title: string; lead?: string; back: string; backLabel?: string; actions?: React.ReactNode; children: React.ReactNode; entry?: WorkspaceEntry }) {
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      {backLabel ? <BackLink to={back} label={backLabel} /> : <MobileBack to={back} label={t("web-pages.settings.title")} />}
      {entry && <SecurityNotice entry={entry} />}
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
  const [deleting, setDeleting] = useState(false);
  const remove = useDeleteAccount();
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={`/w/${entry.id}/settings`} label={t("web-pages.settings.title")} />
      <header className={pagesCss.identity}>
        <Avatar account={account} size={52} />
        <div className={pagesCss.identityText}>
          <h1 className={pagesCss.identityName}>{account.name || account.email}</h1>
          <p className={pagesCss.identitySub}><span>{account.email}</span><span>{t(/^(em|pw)-/.test(account.sub) ? "web-pages.settings.account.email" : "web-pages.settings.account.google")}</span></p>
        </div>
      </header>
      <Section title={t("web-pages.settings.account.sessions")} description={t("web-pages.settings.account.sessionsLead", { name: NAME })}>
        {!devices.value ? devices.error ? <p className={controlsCss.fieldError}>{t("web-pages.settings.account.sessionsFailed", { error: devices.error.message })}</p> : <Waiting count={3} /> : (
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
      {/* Away at once (to another account's workspace while one stays: Landing); signing out goes on by itself, a failure
          said by toast (useSignOut). */}
      <Confirm open={signingOut} onClose={() => setSigningOut(false)}
        onConfirm={() => { setSigningOut(false); navigate("/", { state: { signingOut: account.sub } }); void signOut.signOut(account.sub).then((out) => { if (out) toast(t("web-pages.settings.account.signedOut", { email: account.email })); }); }}
        title={t("web-pages.settings.account.signOutConfirm", { email: account.email })} action={t("web-pages.settings.account.signOutAction")} description={t("web-pages.settings.account.signOutConfirmBody")} />
      <Section title={t("web-pages.settings.account.delete")}>
        <div className={`${pagesCss.card} ${pagesCss.cardRow}`}>
          <div className={pagesCss.cardRowText}><strong>{t("web-pages.settings.account.deleteHere", { email: account.email })}</strong><span className={shellCss.muted}>{t("web-pages.settings.account.deleteHereBody", { name: NAME })}</span></div>
          <Button variant="danger" icon={Trash} onClick={() => setDeleting(true)}>{t("web-pages.settings.account.deleteAction")}</Button>
        </div>
      </Section>
      {/* Asked again, the dialog turning until still.fail cloud has it (it may refuse: the only owner of a workspace others
          are in, said by toast); then away as after signing out, the account gone from here. */}
      <Confirm open={deleting} busy={remove.busy(account.sub)} onClose={() => setDeleting(false)}
        onConfirm={() => void remove.deleteAccount(account.sub).then((gone) => {
          setDeleting(false);
          if (!gone) return;
          navigate("/", { state: { signingOut: account.sub } });
          toast(t("web-pages.settings.account.deleted", { email: account.email }));
        })}
        title={t("web-pages.settings.account.delete")} action={t("web-pages.settings.account.deleteAction")}
        description={t("web-pages.settings.account.deleteConfirmBody", { email: account.email })} />
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

export function useWorkspace(entry: WorkspaceEntry): { view: WorkspaceView | undefined; manager: boolean } {
  const view = useWorkspaceTopic(entry.id).value;
  return { view, manager: view?.role === "owner" || view?.role === "admin" };
}

/**
 * The workspace in one page. At its head its mark (a square, picked there by its managers; its letter till then) and its
 * name (a title they rename where it is, Enter or leaving it keeps it), who the viewer is there and how many it holds;
 * then its people, its relays, and leaving or deleting it (at the end, away from the rest).
 */
export function WorkspaceSettings({ entry }: { entry: WorkspaceEntry }) {
  const { view, manager } = useWorkspace(entry);
  const account = entry.account;
  const navigate = useNavigate();
  const toast = useToast();
  const [name, setName] = useState("");
  useEffect(() => { if (view) setName(view.name); }, [view?.name]);
  const rename = useAction((to: string) => cloud.renameWorkspace(account.sub, entry.id, to), () => toast(t("web-pages.settings.workspace.renamed")));
  // Its mark shows at once, the square turning until the cloud has it.
  const mark = useAction((m: Mark) => cloud.setWorkspaceMark(account.sub, entry.id, m));
  const [leaving, setLeaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const leave = useAction(() => cloud.removeMember(account.sub, entry.id, account.sub), () => toast(t("web-pages.settings.workspace.left")));
  const remove = useAction(() => cloud.deleteWorkspace(account.sub, entry.id), () => toast(t("web-pages.settings.workspace.deleted")));
  if (!view) {
    return (
      <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
        <MobileBack to={`/w/${entry.id}/settings`} label={t("web-pages.settings.title")} />
        <Waiting shape="cards" text={t("web-pages.settings.workspace.loading")} />
      </div>
    );
  }
  const keep = () => { const to = name.trim(); if (!to) setName(view.name); else if (to !== view.name && !rename.busy) rename.run(to); };
  const shown = rename.busy ? rename.arg! : view.name;
  const nameField = (
    <input className={css.titleField} value={name} maxLength={80} disabled={!manager} aria-label={t("web-pages.settings.workspace.nameLabel")}
      onChange={(e) => setName(e.target.value)} onBlur={keep}
      onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) e.currentTarget.blur(); if (e.key === "Escape") { setName(view.name); e.currentTarget.blur(); } }} />
  );
  const failed = rename.error ? t("web-pages.settings.workspace.renameFailed", { error: rename.error.message }) : mark.error ? t("web-pages.settings.workspace.markFailed", { error: mark.error.message }) : null;
  const facts = [t("web-pages.settings.workspace.youAreShort", { role: ROLE_LABEL[view.role], email: account.email }), t("web-pages.settings.members.count", { n: view.members.length }), t("web-pages.settings.workspace.stationsCount", { n: view.stations.length })];
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={`/w/${entry.id}/settings`} label={t("web-pages.settings.title")} />
      <SecurityNotice entry={entry} />
      <header className={css.workspaceHead}>
        <MarkPick emoji={mark.busy ? mark.arg!.emoji : view.emoji} icon={mark.busy ? mark.arg!.icon : view.icon} name={view.name} editable={manager} busy={mark.busy} large
          empty={<WorkspaceMark w={{ name: shown }} />} onPick={(m) => { if (!same(m, view.emoji, view.icon)) void mark.run(m); }} />
        <div className={pagesCss.identityText}>
          {nameField}
          <p className={css.workspaceFacts}>{facts.map((f) => <span key={f}>{f}</span>)}</p>
        </div>
      </header>
      {failed && <p className={controlsCss.fieldError} role="alert">{failed}</p>}
      <Members view={view} account={account} manager={manager} />
      <Relays view={view} account={account} manager={manager} />
      <Section title={t("web-pages.settings.workspace.leaveDelete")}>
        {/* Rows of their own, each asked again before it is done: leaving, and (the owner) deleting. */}
        <div className={css.dangerList}>
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
      {/* Away at once (to another workspace: Landing): it goes on by itself, a failure said by toast. */}
      <Confirm open={leaving} onClose={() => setLeaving(false)} onConfirm={() => { setLeaving(false); navigate("/", { state: { left: entry.id } }); void leave.run(); }}
        title={t("web-pages.settings.workspace.leaveConfirm", { name: view.name })} action={t("web-pages.settings.workspace.leaveAction")} description={t("web-pages.settings.workspace.leaveConfirmBody")} />
      <Confirm open={deleting} onClose={() => setDeleting(false)} onConfirm={() => { setDeleting(false); navigate("/", { state: { left: entry.id } }); void remove.run(); }}
        title={t("web-pages.settings.workspace.deleteConfirm", { name: view.name })} action={t("web-pages.settings.workspace.delete")}
        description={t("web-pages.settings.workspace.deleteConfirmBody", { n: view.stations.length, name: NAME })} />
    </div>
  );
}

export function StationsSettings({ entry }: { entry: WorkspaceEntry }) {
  const { view, manager } = useWorkspace(entry);
  const stations = useStations(entry.id).value;
  return (
    <Page title="Station" lead={t("web-pages.settings.stations.lead", { name: NAME })} back={`/w/${entry.id}/settings`}>
      {/* None yet: adding the first, as the workspace's page does. */}
      {!view || !stations ? <Waiting shape="cards" text={t("common.readingStations")} />
        : stations.length === 0 ? <FirstStation entry={entry} />
        : <Stations view={view} account={entry.account} manager={manager} stations={stations} />}
    </Page>
  );
}

/** Each station's agents' memory: global and projects', where its sessions run; each part opens on a page below. */
export function MemorySettings({ entry }: { entry: WorkspaceEntry }) {
  const listed = useStations(entry.id).value;
  if (listed?.length === 0) return <Navigate to={`/w/${entry.id}/settings/stations`} replace />;
  const stations = listed ?? [];
  return (
    <Page title={t("web-pages.settings.memory.title")} lead={t("web-pages.settings.memory.lead")} back={`/w/${entry.id}/settings`}>
      {stations.map((s) => (
        <div key={s.id} className={css.memoryStation}>
          {stations.length > 1 && <h2 className={css.memoryStationName}>{s.name}</h2>}
          {s.online ? <MemoryView station={s.station} to={(page) => `/w/${entry.id}/settings/memory/${s.id}/${page}`} /> : <p className={shellCss.muted}>{t("web-pages.settings.memory.offline")}</p>}
        </div>
      ))}
    </Page>
  );
}

/** A page of a station's memory (settings/memory/:station/global?at= or /skill/:name?file=), back to the list. */
export function MemoryDocSettings({ entry }: { entry: WorkspaceEntry }) {
  const { station: id, name } = useParams();
  const [params, setParams] = useSearchParams();
  const view = useStations(entry.id).value?.find((s) => s.id === id);
  return (
    <Page title={name ?? t("web-main.memory.global")} back={`/w/${entry.id}/settings/memory`} backLabel={t("web-pages.settings.memory.title")}>
      {view ? <MemoryDoc station={view.station} name={name ?? null} at={Number(params.get("at") ?? 0)} file={params.get("file") ?? ""}
        pick={(key, value) => setParams({ [key]: String(value) }, { replace: true })} /> : <Waiting count={4} />}
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
        : usage.error ? <p className={controlsCss.fieldError}>{t("web-pages.settings.usage.failed", { error: usage.error.message })}</p> : <Waiting shape="cards" />}
    </Page>
  );
}

export function UsagePricesSettings({ entry }: { entry: WorkspaceEntry }) {
  const [params] = useSearchParams();
  const usage = useUsage(entry.id, params.get("days") === "30" ? "30" : "7");
  return <Page title={t("web-pages.settings.prices.title")} lead={t("web-pages.settings.prices.lead")} back={`/w/${entry.id}/settings/usage`}>
    {usage.value ? <PriceTables view={usage.value} /> : <Waiting shape="cards" count={2} error={usage.error ? t("web-pages.settings.prices.failed", { error: usage.error.message }) : null} />}
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
  const sidebar = useProfilesSidebar();
  // Which station a profile is added to, asked when there are several.
  const [choosing, setChoosing] = useState(false);
  const asStation = (s: (typeof stations)[number]): Station => ({ id: s.id, name: s.name, online: s.online, address: s.station, base: stationBase(s.station), settings: `/w/${entry.id}/settings` });
  if (listed?.length === 0) return <Navigate to={`/w/${entry.id}/settings/stations`} replace />;
  // Not one profile on any station (each read): the page is about adding the first.
  const first = stations.length > 0 && stations.every((s) => s.overview && s.overview.profiles.length === 0);
  // Beside the profiles' own sidebar (ProfilesNav.tsx) the page is the one picked there: the first, come to the list.
  const top = profiles.value?.items[0];
  if (sidebar && !first && top) return <Navigate to={profilePath(top)} replace />;
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
          {/* The workspace's profiles, a section each kind of account: one shared between stations once (where it is
              signed in, or which stations may use it, in its line), the others each with the station they are on (the
              core's `profiles`). */}
          {/* Not one read yet: the shapes of what will come; some read, the rest said under them. */}
          {!profiles.value?.items.length && (!profiles.value || profiles.value.wait.reading || profiles.value.wait.failing.length > 0)
            && <Waiting count={3} note={profiles.value?.wait} />}
          {profileGroups(profiles.value?.items ?? []).map((g) => (
            <Section key={g[0]!.group} title={g[0]!.groupTitle}>
              <ul className={pagesCss.list}>
                {g.map((e) => (
                  <li key={e.key}><WorkspaceProfileRow entry={e} workspace={entry.id} /></li>
                ))}
              </ul>
            </Section>
          ))}
          {!!profiles.value?.items.length && <WaitMore note={profiles.value.wait} />}
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

/** Profiles (the workspace's, or a station's own) a run each kind of account, as the core lists them (by kind, in order). */
export function profileGroups<T extends { group?: string }>(items: T[]): T[][] {
  const groups: T[][] = [];
  for (const e of items) {
    const last = groups[groups.length - 1];
    if (last && last[0]!.group === e.group) last.push(e);
    else groups.push([e]);
  }
  return groups;
}

/** The stations an account is signed in on (or a key kept): one borrowing it has nothing of its own to set. */
export const hosts = (e: WorkspaceProfile) => (e.members ?? []).filter((m) => m.role !== "user");

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
  if (!view) return <Page title="Profile" back={back}><Waiting shape="cards" /></Page>;
  if (!found) return <Page title="Profile" back={back}><p className={shellCss.muted}>{t("web-pages.profiles.notFound", { id: key })}</p></Page>;
  const p = found.profile;
  const kind = p.machine ? t("web-main.profile.machine") : p.providerName ?? ACCESS[p.access.kind].label;
  return (
    <Page title={p.name} lead={[p.email, kind].filter(Boolean).join(" · ")} back={back} backLabel="Profile">
      <section className={pageCss.section}>
        <div className={css.accountState}>
          {p.checkTone !== "green" && <Pill tone={p.checkTone}>{p.checkText}</Pill>}
          <span className={shellCss.muted}>{p.check ? p.check.detail : t("web-pages.profiles.neverChecked")}</span>
        </div>
        <QuotaBars quota={p.quota} />
        {p.modelsText && <p className={shellCss.muted}>{p.modelsText}</p>}
      </section>
      <Section title={t("web-pages.profiles.account.each")}>
        <ul className={pagesCss.list}>
          {hosts(found).map((m) => (
            <li key={`${m.station}/${m.profileId}`}>
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
  const to = hosts(entry).length > 1 ? accountPath(workspace, entry.key) : `${stationBase(entry.station)}/settings/accounts/${encodeURIComponent(entry.profile.id)}`;
  return (
    <div className={entry.usable ? undefined : css.profileAway}>
      <ProfileCard profile={entry.profile} to={to} uses={uses}
        state={entry.usable ? undefined : <Pill tone="red">{t("web-pages.settings.profiles.hostAway", { station: entry.hostName })}</Pill>}
        action={state.running || state.error !== undefined ? <DoingShown state={state} label={t("web-main.activity.busy")} /> : undefined} />
    </div>
  );
}

/** A station as it will be once its new mark is there ("": none). */
function shownAs(s: StationView, mark: Mark | undefined): StationView {
  if (mark === undefined) return s;
  const { emoji: _, icon: __, ...rest } = s;
  return { ...rest, ...(mark.emoji ? { emoji: mark.emoji } : {}), ...(mark.icon ? { icon: mark.icon } : {}) };
}

/**
 * What a manager changes of a station, on its card and on its own page alike: its name and mark (shown at once, `shown`,
 * a ring by its menu until the cloud has them, a red mark a moment if not), and its removal; `menu` the items for its ⋯,
 * `dialogs` what they open and what failed.
 */
export function useStationEdits(view: WorkspaceView | undefined, account: Account, stations: StationView[]) {
  const navigate = useGo();
  const [removing, setRemoving] = useState<StationView | null>(null);
  // Asked in a dialog of ours: window.prompt does nothing in the desktop app (Electron has none).
  const [naming, setNaming] = useState<StationView | null>(null);
  const workspace = view?.id ?? "";
  const remove = useAction((s: StationView) => cloud.removeStation(account.sub, workspace, s.id));
  const rename = useAction(({ id, name }: { id: string; name: string }) => cloud.renameStation(account.sub, workspace, id, name));
  const renaming = (s: StationView) => rename.busy && rename.arg?.id === s.id;
  const mark = useAction(({ id, mark }: { id: string; mark: Mark }) => cloud.setStationMark(account.sub, workspace, id, mark));
  const picking = (s: StationView) => mark.busy && mark.arg?.id === s.id;
  const shown = (s: StationView) => shownAs(renaming(s) ? { ...s, name: rename.arg!.name } : s, picking(s) ? mark.arg!.mark : undefined);
  const busy = (s: StationView) => (
    <DoingMark calls={["workspace.renameStation", "workspace.removeStation"]} on={{ account: account.sub, workspace, station: s.id }}
      label={renaming(s) ? t("web-pages.settings.stations.renaming") : t("web-main.activity.busy")} />
  );
  /** `drive`: its 文件 among them (the card's ⋯; its page opens them from its folders). */
  const menu = (s: StationView, manager: boolean, drive = true) => [
    // Its drive (docs/drive.md), for every member, where the station has one.
    ...(drive && s.overview?.drive ? [{ label: t("web-pages.drive.title"), icon: Folder, onSelect: () => navigate(`${stationBase(s.station)}/files`) }] : []),
    ...(manager ? [
      { label: t("web-pages.settings.stations.rename"), icon: Edit, disabled: renaming(s), onSelect: () => setNaming(s) },
      { label: t("web-pages.settings.stations.remove"), icon: Trash, danger: true, onSelect: () => setRemoving(s) },
    ] : []),
  ];
  const dialogs = (
    <>
      {mark.error && <p className={controlsCss.fieldError} role="alert">{t("web-pages.stations.emoji.failed", { name: stations.find((s) => s.id === mark.arg?.id)?.name ?? "station", error: mark.error.message })}</p>}
      {rename.error && <p className={controlsCss.fieldError} role="alert">{t("web-pages.settings.stations.renameFailed", { name: stations.find((s) => s.id === rename.arg?.id)?.name ?? "station", error: rename.error.message })}</p>}
      {naming && <RenameStationDialog station={naming} onClose={() => setNaming(null)} onRename={(name) => { if (name !== naming.name) void rename.run({ id: naming.id, name }); setNaming(null); }} />}
      <Confirm open={removing !== null} onClose={() => setRemoving(null)} onConfirm={() => { if (removing) void remove.run(removing); setRemoving(null); }}
        title={t("web-pages.settings.stations.removeConfirm", { name: removing?.name ?? "" })} action={t("web-pages.settings.stations.removeAction")}
        description={t("web-pages.settings.stations.removeConfirmBody", { name: NAME })} />
    </>
  );
  return {
    shown, busy, menu, dialogs, picking, setMark: (s: StationView, m: Mark) => void mark.run({ id: s.id, mark: m }),
    rename: (s: StationView, name: string) => { if (name !== s.name && !renaming(s)) void rename.run({ id: s.id, name }); },
  };
}

function Stations({ view, account, manager, stations }: { view: WorkspaceView; account: Account; manager: boolean; stations: StationView[] }) {
  const [adding, setAdding] = useState(false);
  const edits = useStationEdits(view, account, stations);
  return (
    <Section title={t("web-pages.settings.stations.count", { n: stations.length })} actions={manager && <Button icon={Plus} onClick={() => setAdding(true)}>{t("web-pages.settings.stations.add")}</Button>}>
      <StationList stations={stations.map(edits.shown)} manager={manager} page={(s) => `/w/${view.id}/settings/stations/${s.id}`}
        onMark={manager ? edits.setMark : undefined} markBusy={edits.picking} menu={(s) => (manager || s.overview?.drive) && <>
        {manager && edits.busy(s)}
        <Menu items={edits.menu(s, manager)} />
      </>} />
      {edits.dialogs}
      {adding && <AddStationDialog view={view} account={account} stations={stations} onClose={() => setAdding(false)} thisMac />}
    </Section>
  );
}

function RenameStationDialog({ station, onClose, onRename }: { station: StationView; onClose(): void; onRename(name: string): void }) {
  const [name, setName] = useState(station.name);
  const save = () => { if (name.trim()) onRename(name.trim()); };
  return (
    <Dialog open onClose={onClose} title={t("web-pages.settings.stations.rename")}
      footer={<><Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button><Button variant="primary" disabled={!name.trim()} onClick={save}>{t("common.save")}</Button></>}>
      <Field label={t("web-pages.settings.stations.namePrompt")} htmlFor="station-name">
        <input id="station-name" className={controlsCss.input} value={name} autoFocus onFocus={(e) => e.target.select()} onChange={(e) => setName(e.target.value)} maxLength={80}
          onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) save(); }} />
      </Field>
    </Dialog>
  );
}

/** Which way a station is added: this machine (the desktop app's own station), a new machine (its command), or one of the
 * viewer's other workspaces' as it is. */
type AddKind = "this" | "new" | "existing";

/**
 * `thisMac`: this machine offered too, where the app offers it, first and chosen at the start: the machine the app
 * runs on is the one most often added.
 */
export function AddStationDialog({ view, account, stations, onClose, thisMac = false }: { view: WorkspaceView; account: Account; stations: StationView[]; onClose(): void; thisMac?: boolean }) {
  const [name, setName] = useState("");
  // A station the viewer manages in another workspace, offered beside a new machine (docs/multi-workspace.md).
  const joinable = useJoinable(view.id).value;
  // Its joining said in the dialog, not in a toast as well.
  const mac = useJoinThisMac(account, view.id, { announce: false });
  const macJoined = mac.join.result !== undefined;
  const offersMac = thisMac && (mac.offered || macJoined);
  const offersExisting = !!joinable?.offered && joinable.items.length > 0;
  const [picked, setKind] = useState<AddKind | null>(null);
  const kind: AddKind = picked ?? (offersMac ? "this" : "new");
  // The stations there before: the one that joins is the one not among them.
  const [known] = useState(() => new Set(stations.map((s) => s.id)));
  const enroll = useAction(() => cloud.enroll(account.sub, view.id, name));
  const joined = enroll.result && stations.find((s) => !known.has(s.id));
  // From the command shown to the station in the list: how long adding one takes.
  const shown = useRef(0);
  useEffect(() => { if (enroll.result) shown.current = performance.now(); }, [enroll.result]);
  useEffect(() => { if (joined) track("station_added", { ms: Math.round(performance.now() - shown.current) }); }, [Boolean(joined)]); // eslint-disable-line react-hooks/exhaustive-deps
  const kinds = <AddKinds kind={kind} onKind={setKind} thisMac={offersMac} existing={offersExisting} />;
  if (kind === "existing" && joinable?.offered) return <JoinStationDialog view={view} joinable={joinable} kinds={kinds} onClose={onClose} />;
  if (kind === "this" && offersMac) {
    return (
      <Dialog open onClose={onClose} wide title={t("web-pages.settings.stations.add")}
        description={t(PC ? "web-pages.settings.stations.thisPcLead" : "web-pages.settings.stations.thisMacLead")}
        footer={macJoined ? <Button variant="primary" onClick={onClose}>{t("common.done")}</Button> : <>
          <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
          <Button variant="primary" busy={mac.busy} onClick={() => mac.join.run()}>{t(PC ? "web-pages.settings.thisPc.add" : "web-pages.settings.thisMac.add")}</Button>
        </>}>
        {!macJoined && kinds}
        {macJoined && <div className={additionsCss.callout} data-tone="green"><Check {...ICON} /><span>{t(PC ? "web-pages.settings.thisPc.joined" : "web-pages.settings.thisMac.joined")}</span></div>}
        {mac.join.error && <p className={controlsCss.fieldError} role="alert">{mac.join.error.message}</p>}
      </Dialog>
    );
  }
  return (
    <Dialog open onClose={onClose} wide title={t("web-pages.settings.stations.add")}
      description={t("web-pages.settings.stations.addLead")}
      footer={joined ? <Button variant="primary" onClick={onClose}>{t("common.done")}</Button> : <>
        <Button variant="ghost" onClick={onClose}>{enroll.result ? t("common.close") : t("common.cancel")}</Button>
        {!enroll.result && <Button variant="primary" disabled={!name.trim()} busy={enroll.busy} onClick={() => enroll.run()}>{t("web-pages.settings.stations.generate")}</Button>}
      </>}>
      {!enroll.result && kinds}
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

/** This machine, a new one, or a station the viewer has elsewhere: at the top of 添加 station, where more than one is offered. */
function AddKinds({ kind, onKind, thisMac, existing }: { kind: AddKind; onKind(kind: AddKind): void; thisMac: boolean; existing: boolean }) {
  if (!thisMac && !existing) return null;
  const options: { value: AddKind; label: string }[] = [
    ...(thisMac ? [{ value: "this" as const, label: t(PC ? "web-pages.settings.stations.kindThisPc" : "web-pages.settings.stations.kindThisMac") }] : []),
    { value: "new", label: t("web-pages.settings.stations.kindNew") },
    ...(existing ? [{ value: "existing" as const, label: t("web-pages.settings.stations.kindExisting") }] : []),
  ];
  return <Segmented<AddKind> className={css.addKinds} label={t("web-pages.settings.stations.kind")} value={kind} onChange={onKind} options={options} />;
}

/**
 * 添加 station with a station the viewer manages in another workspace (its home): picked from those not here yet
 * (the core's `joinable`), then added as it is (`station.join`: the core makes the enrollment here and has the station
 * join with it). What that shares of the machine is said under the list: one system user, kept apart, not a sandbox.
 */
export function JoinStationDialog({ view, joinable, kinds, onClose }: { view: WorkspaceView; joinable: JoinableView; kinds: ReactNode; onClose(): void }) {
  // One whose home's security mode keeps it out is shown, not picked.
  const open = joinable.items.filter((s) => !s.needsLock);
  const [picked, setPicked] = useState<string>(open[0]?.station ?? "");
  const chosen = open.find((s) => s.station === picked) ?? open[0];
  const join = useAction((station: string) => cloud.joinStation(view.id, station));
  const busy = useDoing("station.join", { workspace: view.id, station: chosen?.station ?? "" }) || join.busy;
  const done = join.result ? joinable.items.find((s) => s.station === join.arg) ?? chosen : undefined;
  return (
    <Dialog open onClose={onClose} wide title={t("web-pages.settings.stations.add")}
      description={t("web-pages.settings.stations.existingLead")}
      footer={done ? <Button variant="primary" onClick={onClose}>{t("common.done")}</Button> : <>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" disabled={!chosen} busy={busy} onClick={() => { if (chosen) join.run(chosen.station); }}>{t("web-pages.settings.stations.joinAction")}</Button>
      </>}>
      {!done && kinds}
      {done ? (
        <div className={additionsCss.callout} data-tone="green"><Check {...ICON} /><span>{t("web-pages.settings.stations.joinedHere", { name: done.name })}</span></div>
      ) : joinable.items.length > 0 ? (
        <Field label={t("web-pages.settings.stations.existingLabel")} hint={t("web-pages.settings.stations.softIsolation")}>
          <Choices<string> label={t("web-pages.settings.stations.existingLabel")} value={chosen?.station ?? ""} onChange={setPicked}
            options={joinable.items.map((s) => ({
              value: s.station, title: s.name, description: s.line, disabled: s.needsLock,
              icon: <MarkOrLetter emoji={s.emoji} icon={s.icon} name={s.name} />,
            }))} />
        </Field>
      ) : joinable.loading ? <WaitLine text={t("common.readingStations")} />
        : <Empty>{t("web-pages.settings.stations.existingNone")}</Empty>}
      {join.error && <p className={controlsCss.fieldError} role="alert">{join.error.message}</p>}
    </Dialog>
  );
}

type EnrollSystem = "unix" | "windows";

/// The system whose command is shown first: this browser's (a station is most often added on the machine it is to be;
/// another is a click away).
const BROWSER_SYSTEM: EnrollSystem = /Win/.test(navigator.platform) ? "windows" : "unix";

/** An enrollment's command, macOS and Linux's or Windows' (from a cloud that gives one), and that the station is awaited. */
function EnrollSteps({ enrollment }: { enrollment: { install: string; installWindows?: string } }) {
  const [system, setSystem] = useState<EnrollSystem>(BROWSER_SYSTEM);
  const windows = system === "windows" && enrollment.installWindows !== undefined;
  return (
    <div className={css.enroll}>
      <div className={css.enrollStep} data-shell={windows ? "powershell" : undefined}>
        <p className={css.enrollLabel}>{t(windows ? "web-pages.settings.enroll.windows" : "web-pages.settings.enroll.run")}<About>{t("web-pages.settings.enroll.about", { name: NAME })}</About></p>
        {enrollment.installWindows !== undefined && (
          <Segmented<EnrollSystem> className={css.enrollSystem} label={t("web-pages.settings.enroll.system")} value={system} onChange={setSystem}
            options={[{ value: "unix", label: t("web-pages.settings.enroll.unix") }, { value: "windows", label: t("web-pages.settings.enroll.windowsTab") }]} />
        )}
        <CopyCommand text={windows ? enrollment.installWindows! : enrollment.install} />
      </div>
      <div className={css.enrollWait} role="status">
        <Spinner />
        <span><strong>{t("web-pages.settings.enroll.waiting")}</strong><span className={shellCss.muted}>{t("web-pages.settings.enroll.waitingNote")}</span></span>
      </div>
    </div>
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
  if (!view) return <Waiting shape="cards" count={1} text={t("web-pages.settings.workspace.loading")} />;
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

/**
 * A station the viewer manages in another workspace, added to a workspace with none as it is (docs/multi-workspace.md):
 * a link among the first station's page's others, there only while there is such a station to add.
 */
export function JoinExistingLink({ entry, className }: { entry: WorkspaceEntry; className?: string }) {
  const { view, manager } = useWorkspace(entry);
  const joinable = useJoinable(entry.id).value;
  const [open, setOpen] = useState(false);
  if (!view || !manager || !joinable?.offered || joinable.items.length === 0) return null;
  return (
    <>
      <span aria-hidden="true"> · </span>
      <button type="button" className={className} onClick={() => setOpen(true)}>{t("web-pages.settings.stations.firstExisting")}</button>
      {open && <JoinStationDialog view={view} joinable={joinable} onClose={() => setOpen(false)}
        kinds={<AddKinds kind="existing" onKind={(kind) => { if (kind === "new") setOpen(false); }} thisMac={false} existing />} />}
    </>
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
  // The field to add one is opened by the section's button (none: nothing but the words of what they are).
  const [open, setOpen] = useState(false);
  const [adding, setAdding] = useState("");
  const set = useAction((next: string[]) => cloud.setRelays(account.sub, view.id, next), (_r, next) => { if (next.length > relays.length) { setAdding(""); setOpen(false); } });
  const add = () => { const url = adding.trim(); if (url) void set.run([...relays, url]); };
  if (!manager && relays.length === 0) return null;
  return (
    <Section title={<>{t("web-pages.settings.relays.title")}{relays.length > 0 && <span className={css.titleCount}>{relays.length}</span>}</>} description={t("web-pages.settings.relays.lead", { name: NAME })}
      actions={manager && !open && <Button icon={Plus} onClick={() => setOpen(true)}>{t("web-pages.settings.relays.add")}</Button>}>
      {(relays.length > 0 || open) && (
        <div className={pagesCss.card}>
          {relays.map((url) => (
            <div key={url} className={pagesCss.cardRow}>
              <span className={pagesCss.cardRowText}><strong>{relayLabel(url)}</strong></span>
              {manager && <Button variant="ghost" busy={set.busy && !set.arg?.includes(url)} disabled={set.busy} onClick={() => set.run(relays.filter((u) => u !== url))}>{t("web-pages.settings.relays.remove")}</Button>}
            </div>
          ))}
          {open && (
            <Field label={t("web-pages.settings.relays.add")} htmlFor="ws-relay" hint={t("web-pages.settings.relays.hint")} error={set.error ? set.error.message : undefined}>
              <div className={additionsCss.inputRow}>
                <input id="ws-relay" className={controlsCss.input} value={adding} autoFocus placeholder="https://relay.example.com" inputMode="url" autoComplete="off" spellCheck={false}
                  onChange={(e) => setAdding(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") add(); if (e.key === "Escape") setOpen(false); }} />
                <Button variant="ghost" onClick={() => { setOpen(false); setAdding(""); }}>{t("common.cancel")}</Button>
                <Button variant="primary" disabled={!adding.trim() || set.busy} busy={set.busy && (set.arg?.length ?? 0) > relays.length} onClick={add}>{t("web-pages.settings.relays.addAction")}</Button>
              </div>
            </Field>
          )}
        </div>
      )}
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
    <Section title={<>{t("web-pages.settings.workspace.members")}<span className={css.titleCount}>{view.members.length}</span></>} actions={manager && <Button icon={UserPlus} onClick={() => setInviting(true)}>{t("web-pages.settings.members.add")}</Button>}>
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
              label={remove.busy && remove.arg === m.sub ? t("web-pages.settings.members.removing") : t("web-pages.settings.members.changingRole")} />
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
          <div className={css.memberGroup}><strong>{t("web-pages.settings.members.added")}</strong><span className={shellCss.muted}>{t("web-pages.settings.members.addedNote", { n: view.added.length, name: NAME })}</span></div>
          <ul className={pagesCss.list}>
            {view.added.map((a) => (
              <li key={a.email} className={pagesCss.listRow}>
                <Avatar account={{ name: "", email: a.email, picture: "" }} size={28} />
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
          <div className={css.memberGroup}><strong>{t("web-pages.settings.members.invitations")}</strong><span className={shellCss.muted}>{t("web-pages.settings.members.invitationsCount", { n: view.invitations.length })}</span></div>
          <ul className={pagesCss.list}>
            {view.invitations.map((i) => (
              <li key={i.id} className={pagesCss.listRow}>
                <Avatar account={{ name: "", email: i.email ?? "?", picture: "" }} size={28} />
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
  const call=useCall(); const act=useAct();
  const stations=useStations(entry.id).value;
  const base=`/w/${entry.id}/settings/automatic-decisions`;
  const refresh=()=>Promise.all((stations??[]).filter(s=>s.online).map(s=>act(call("automaticDecisions.refresh",{station:s.station}),t("web-pages.automaticDecisions.refreshAction"),t("web-pages.automaticDecisions.refreshed"))));
  return <Page title={t("web-pages.automaticDecisions.completion")} lead={t("web-pages.automaticDecisions.completionNote")} back={base} backLabel={t("web-pages.automaticDecisions.title")}
    actions={<Button variant="ghost" icon={Refresh} onClick={refresh}>{t("web-pages.automaticDecisions.refresh")}</Button>}>
    <AutomaticDecisionCompletion workspace={entry.id} />
  </Page>;
}

/** 设置 › 归档 › a station: how it archives chats on its own (pages/Archiving.tsx). */
export function StationArchivingSettings({entry}:{entry:WorkspaceEntry}) {
  const {station=""}=useParams();
  const name=useStations(entry.id).value?.find(s=>s.station===station)?.name;
  return <Page title={name ? `${t("web-pages.archiving.auto.title")} · ${name}` : t("web-pages.archiving.auto.title")} back={`/w/${entry.id}/settings/archive`} backLabel={t("web-pages.archiving.title")}>
    <StationArchiving workspace={entry.id} station={station} />
  </Page>;
}

export function AutomaticDecisionPolicySettings({entry}:{entry:WorkspaceEntry}) {
  const {station=""}=useParams();
  const name=useStations(entry.id).value?.find(s=>s.station===station)?.name;
  return <Page title={name ? `${t("web-pages.archivePolicy.title")} · ${name}` : t("web-pages.archivePolicy.title")} lead={t("web-pages.archivePolicy.textLead")} back={`/w/${entry.id}/settings/automatic-decisions/completion`} backLabel={t("web-pages.automaticDecisions.completion")}>
    <AutomaticDecisionPolicy workspace={entry.id} station={station} />
  </Page>;
}

