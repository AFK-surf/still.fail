import type { MachineLogin, RuntimeInstall } from "../core/shapes.ts";
import { profilesPage, stationBase, useStation, useLink } from "../station.tsx";
import { Chart, ChevronRight, Edit, External, LogIn, Plus, Refresh, Trash } from "@stillfail/ui/icons.tsx";
import { useEffect, useRef, useState } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { useAction, useApi, useMemberships, useOverview, useProfiles, type AccessKind, type LoginJob, type Overview, type ProfileInput, type Profile } from "../api.ts";
import { ACCESS, KEYED, RUNTIME_LABEL } from "../format.ts";
import { useUsage, usageCss } from "../Usage.tsx";
import { pickModelsPath, useProfilesSidebar } from "../ProfilesNav.tsx";
import { hosts } from "../cloud/settings.tsx";
import type { WorkspaceProfile } from "../core/shapes.ts";
import { useDoing, useDoingFailed } from "../doing.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { useToast } from "@stillfail/ui/toast.tsx";
import { QuotaBars } from "../components.tsx";
import { StationNamedAt } from "../StationNamed.tsx";
import * as modelCss from "../ModelTriple.css.ts";
import { MachineLoginCard } from "../ProfileCard.tsx";
import { About, Button, Choices, Confirm, ConnectAvatar, CopyCommand, Dialog, Empty, Field, ICON, IconButton, Menu, BackLink, ModelLogo, Pill, ProviderLogo, RuntimeTags, Section, Select, StatusDot, SwitchRow, Time, Tip, Progress, Spinner, Waiting, WaitLine } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as baseCss from "../styles/base.css.ts";
import * as css from "./Accounts.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as waitingCss from "../styles/waiting.css.ts";
import * as additionsCss from "../styles/additions.css.ts";
import * as conversationCss from "../styles/conversation.css.ts";
import * as chatCss from "../styles/chat.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
import { tx } from "../cloud/words.tsx";
import * as pageCss from "@stillfail/ui/styles/page.css.ts";
/** The plans a machine's own login can be signed in again with (the add page: a vendor's subscription). */
export type Choice = "claude-sub" | "chatgpt-sub";

/** What a profile is, in a line, where the first one is asked for (an element: its words are read as it is drawn). */
export const PROFILE_LEAD = <ProfileLead />;

function ProfileLead() {
  return <>{tx("web-pages.profiles.lead", { subscription: <span className={baseCss.phrase}>{t("web-pages.profiles.leadSubscription")}</span> })}</>;
}

/**
 * Where a first profile is asked for: the accounts this machine's own Claude Code and Codex are signed in with (the
 * station reads them: src/machine-logins.ts). One kept in a file is used as it is — a profile on the machine's login,
 * which follows it; one kept only in the keychain cannot be, and is offered as a sign-in with the same account.
 */
export function MachineLoginOffers({ logins, onAdd }: { logins: MachineLogin[] | undefined; onAdd(choice: Choice): void }) {
  const api = useApi();
  const navigate = useNavigate();
  const toast = useToast();
  // Whose logins: the page may list several stations', and is read from any machine.
  const station = useStation();
  const use = useAction((runtime: MachineLogin["runtime"]) => api.useMachineLogin(runtime), ({ id }) => {
    toast(t("web-pages.profiles.machineAdded"));
    navigate(pickModelsPath(station.address, id));
  });
  const offers = (logins ?? []).filter((l) => l.offered);
  if (!offers.length) return null;
  return (
    <div className={css.machineLogins}>
      <p className={css.machineLoginsHead}>{t("web-pages.profiles.machineSignedIn", { station: station.name || t("web-main.machine.this") })}</p>
      {offers.map((l) => (
        // A refused account is said so, with nothing to do with it here.
        <MachineLoginCard key={l.runtime} login={l} action={l.quota?.state === "blocked" ? null : l.usable
          ? <Tip label={t("web-pages.profiles.useMachineTip")}><Button busy={use.busy && use.args?.[0] === l.runtime} disabled={use.busy} onClick={() => void use.run(l.runtime)}>{t("web-pages.profiles.useThis")}</Button></Tip>
          : <Tip label={t("web-pages.profiles.keychainTip", { name: NAME })}><Button onClick={() => onAdd(l.runtime === "claude" ? "claude-sub" : "chatgpt-sub")}>{t("web-pages.profiles.signIn")}</Button></Tip>} />
      ))}
      {use.error && <p className={controlsCss.fieldError} role="alert">{use.error.message}</p>}
    </div>
  );
}

export function AccountPage() {
  const { id } = useParams();
  const overview = useOverview(useStation().address);
  const profile = overview.value?.profiles.find((p) => p.id === id);
  if (!overview.value) return overview.error ? <Empty><p>{overview.error.message}</p></Empty> : <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}><Waiting shape="cards" text={t("web-pages.profiles.loading")} /></div>;
  if (!profile) return <Empty><p>{t("web-pages.profiles.notFound", { id: id ?? "" })}</p></Empty>;
  return <AccountView key={profile.id} profile={profile} overview={overview.value} />;
}

function AccountView({ profile, overview }: { profile: Profile; overview: Overview }) {
  const api = useApi();
  const station = useStation();
  const link = useLink();
  const navigate = useNavigate();
  const toast = useToast();
  const [editingName, setEditingName] = useState(false);
  const [name, setName] = useState(profile.name);
  const save = useAction((input: ProfileInput) => api.putProfile(profile.id, input));
  const remove = useAction(() => api.deleteProfile(profile.id), () => toast(profile.machine ? t("web-pages.profiles.disabled") : t("web-pages.profiles.deleted")));
  // One on the machine's login is stopped rather than deleted: the login stays the machine's, to be used again.
  const removal = profile.machine
    ? { item: t("web-pages.profiles.disable"), title: t("web-pages.profiles.disableConfirm", { name: profile.name }), action: t("web-pages.profiles.disable"), description: t("web-pages.profiles.disableBody", { name: NAME, runtime: RUNTIME_LABEL[profile.runtime] }) }
    : { item: t("web-pages.profiles.delete"), title: t("web-pages.archive.deleteConfirm", { title: profile.name }), action: t("web-pages.profiles.delete"), description: t("web-pages.profiles.deleteBody", { name: NAME }) };
  const check = useAction(() => api.checkProfile(profile.id));
  const saveThen = (input: ProfileInput, done: () => void) => void save.run(input).then((ok) => { if (ok) done(); });
  // Its new name shows while it is saved.
  const renamingTo = save.busy ? save.args?.[0].name : undefined;
  const rename = () => {
    setEditingName(false);
    if (name.trim() && name.trim() !== profile.name) saveThen({ name: name.trim() }, () => toast(t("web-pages.settings.workspace.renamed")));
  };
  // Its last check, as the station has it (a check done here, or after a sign-in, comes back with the overview).
  const latest = profile.check;
  const users = profile.usedBy.map((id) => overview.connects.find((c) => c.id === id)).filter((c) => c !== undefined);
  const [deleting, setDeleting] = useState(false);

  // A subscription, or a profile on an account (OpenCode Go's, Kimi Code's): signed in (again) rather than given a key.
  const signIn = profile.access.kind === "subscription" || !!profile.access.login;
  // A copy of another station's: shown, used, but changed only there.
  const copy = profile.share?.role === "user";
  const signingIn = profile.login && ["starting", "needs_code", "needs_approval", "verifying"].includes(profile.login.state);
  // Beside the profiles' sidebar (ProfilesNav.tsx) the list is there: no way back to it.
  const sidebar = useProfilesSidebar();
  const workspace = station.address.split("/")[0]!;
  // Its row of the workspace's list: the account it is, on whichever stations have it.
  const entry = useProfiles(workspace).value?.items.find((e) => e.members?.some((m) => m.station === station.address && m.profileId === profile.id));
  // What it is, in a line: its kind, the address signed in (when not its name), where it is.
  const facts = [
    profile.machine ? t("web-main.profile.machine") : profile.providerName ?? ACCESS[profile.access.kind].label,
    profile.email && profile.email !== profile.name ? profile.email : null,
    entry?.where,
  ].filter(Boolean).join(" · ");
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      {!sidebar && <BackLink to={profilesPage(station)} label="Profile" />}
      {/* Who the account is and whether it works now: its provider, name, runtimes, and its last check. */}
      <header className={pagesCss.identity}>
        <span className={`${pagesCss.mark} ${waitingCss.runtimeMark}`} style={{ width: 48, height: 48 }}><ProviderLogo runtime={profile.runtime} kind={profile.access.kind} mark={profile.providerMark} size={26} /></span>
        <div className={pagesCss.identityText}>
          {editingName ? (
            <input className={`${controlsCss.input} ${css.identityNameInput}`} value={name} autoFocus aria-label={t("web-pages.profiles.name")} onChange={(e) => setName(e.target.value)} onBlur={rename}
              onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) rename(); if (e.key === "Escape") { setName(profile.name); setEditingName(false); } }} />
          ) : (
            <h1 className={pagesCss.identityName}>{renamingTo ?? profile.name}
              {renamingTo && <Spinner label={t("web-pages.settings.stations.renaming")} />}<RuntimeTags runtimes={profile.runtimes} decision={profile.uses?.includes("decision")} />{!profile.machine && !copy && <IconButton label={t("web-pages.settings.stations.rename")} icon={Edit} onClick={() => setEditingName(true)} />}</h1>
          )}
          {facts && <p className={pagesCss.identitySub}>{facts}</p>}
          <p className={`${pagesCss.identitySub} ${css.profileState}`}>
            {profile.checkTone !== "green" && <Pill tone={profile.checkTone}>{profile.checkText}</Pill>}
            {/* Keep check details without repeating the healthy status. */}
            <span>{latest ? latest.detail.replace(/^可用[，,]\s*/, "") : t("web-pages.profiles.neverChecked")}</span>
            {latest && <span className={shellCss.muted}>{tx("web-pages.profiles.checkedAt", { time: <Time stamp={latest.time?.checkedAt} /> })}</span>}
            <IconButton label={check.busy ? t("web-pages.version.checking") : t("web-pages.profiles.recheck")} icon={Refresh} busy={check.busy} onClick={() => void check.run()} />
          </p>
          {check.error && <p className={controlsCss.fieldError} role="alert">{t("web-pages.profiles.checkFailed", { error: check.error.message })}</p>}
        </div>
        {!copy && <Menu items={[{ label: removal.item, icon: Trash, danger: true, onSelect: () => setDeleting(true) }]} />}
      </header>
      {save.error && <p className={controlsCss.fieldError} role="alert">{save.error.message}</p>}
      {/* A subscription that needs signing in, or is signing in: that comes first. */}
      {!copy && signIn && !profile.machine && (latest?.state === "login" || signingIn) && <section className={pageCss.section}><SignIn profile={profile} needed /></section>}

      <QuotaSection profile={profile} />

      <UsageSection profile={profile} entry={entry} workspace={workspace} />

      {entry && hosts(entry).length > 1 && <StationsSection entry={entry} here={station.address} />}

      {overview.sharing && <ShareSection profile={profile} />}

      {!copy && <WorkspacesSection profile={profile} />}

      {!copy && profile.fast !== undefined && profile.fast !== null && <FastSection profile={profile} />}

      {!copy && <ModelPool profile={profile} found={latest?.models ?? null} onSave={(models) => save.run({ models })} />}

      {/* A station older than the setting says nothing of it. */}
      {!copy && profile.runtimes.includes("claude") && profile.backgroundOnMessage !== undefined && (
        <Section title={t("web-pages.profiles.run")}>
          <SwitchRow title={t("web-pages.profiles.background")} checked={profile.backgroundOnMessage} disabled={save.busy}
            description={profile.backgroundOnMessage
              ? t("web-pages.profiles.backgroundOn")
              : t("web-pages.profiles.backgroundOff")}
            onChange={(on) => saveThen({ backgroundOnMessage: on }, () => toast(on ? t("web-pages.profiles.turnedOn") : t("web-pages.profiles.turnedOff")))} />
        </Section>
      )}

      <Section title={t("web-pages.profiles.usedBy")}>
        {users.length === 0 ? <p className={shellCss.muted}>{t("web-pages.profiles.usedByNone")}</p> : (
          <ul className={pagesCss.list}>
            {users.map((c) => (
              <li key={c.id}><Link className={pagesCss.listRow} to={link(`/connects/${c.id}`)}><ConnectAvatar connect={c} size={24} /><span className={pagesCss.listRowTitle}>{c.name}</span><span className={shellCss.muted}>{c.modelName ?? (profile.model ? profile.names[profile.model] ?? profile.model : t("web-pages.profiles.defaultModel"))}</span></Link></li>
            ))}
          </ul>
        )}
      </Section>

      {copy ? null : profile.machine ? <MachineAccount profile={profile} /> : <AccountSection profile={profile} signedIn={latest?.state !== "login" && !signingIn}
        onSave={(input) => saveThen(input, () => toast(t("web-pages.profiles.savedChecking")))} busy={save.busy} />}

      {!copy && profile.access.kind === "env" && <EnvSection profile={profile} onSave={(input) => saveThen(input, () => toast(t("web-pages.profiles.saved")))} busy={save.busy} />}
      {/* Gone from here at once: the list shows it until the station has dropped it, a failure said by toast. */}
      <Confirm open={deleting} onClose={() => setDeleting(false)} onConfirm={() => { setDeleting(false); navigate(profilesPage(station)); void remove.run(); }}
        title={removal.title} action={removal.action} description={removal.description} />
    </div>
  );
}


/**
 * What it spent in the last 7 days (the core's `usage`, its row by account): on this station, and on the others that
 * have the same account when there are some (each its own line of 各 station).
 */
function UsageSection({ profile, entry, workspace }: { profile: Profile; entry: WorkspaceProfile | undefined; workspace: string }) {
  const station = useStation();
  const usage = useUsage(workspace, "7").value;
  if (!usage) return null;
  const item = usage.lists.find((l) => l.key === "profiles")?.items.find((i) => i.key === `${station.address}/${profile.id}`);
  const several = (entry?.members?.length ?? 0) > 1;
  return (
    <Section title={several ? t("web-pages.profiles.usageHere", { station: station.name }) : t("web-pages.profiles.usage")}
      actions={<Link className={`${controlsCss.btn} ${controlsCss.btnGhost}`} to={`/w/${workspace}/settings/usage`}><Chart {...ICON} />{t("web-pages.profiles.usageAll")}</Link>}>
      {item ? (
        <div className={`${usageCss.usage} ${usageCss.tiles} ${css.usageTiles}`}>
          <div className={usageCss.tile}><span className={usageCss.tileLabel}>{t("web-pages.profiles.usageCost")}</span><span className={usageCss.tileValue}>{item.costText}</span><span className={usageCss.tileSub}>{t("web-pages.profiles.usageShare", { share: item.shareText })}</span></div>
          <div className={usageCss.tile}><span className={usageCss.tileLabel}>{t("web-pages.profiles.usageCalls")}</span><span className={usageCss.tileValue}>{item.callsText}</span><span className={usageCss.tileSub}>{t("web-pages.profiles.usageCallsSub")}</span></div>
          <div className={usageCss.tile}><span className={usageCss.tileLabel}>Tokens</span><span className={usageCss.tileValue}>{item.tokensText}</span><span className={usageCss.tileSub}>{t("web-pages.profiles.usageTokensSub")}</span></div>
        </div>
      ) : usage.wait.reading ? <WaitLine /> : <p className={shellCss.muted}>{t("web-pages.profiles.usageNone")}</p>}
    </Section>
  );
}

/** The same account on several stations: each's part (lending it, borrowing it, signed in on its own), its state and
 * who uses it there, leading to its page there. */
function StationsSection({ entry, here }: { entry: WorkspaceProfile; here: string }) {
  return (
    <Section title={t("web-pages.profiles.account.each")}>
      <ul className={pagesCss.list}>
        {(entry.members ?? []).map((m) => (
          <li key={`${m.station}/${m.profileId}`}>
            <Link className={pagesCss.listRow} to={`${stationBase(m.station)}/settings/accounts/${encodeURIComponent(m.profileId)}`} aria-current={m.station === here ? "page" : undefined}>
              <StatusDot state={m.online ? "online" : "offline"} />
              <span className={pagesCss.listRowText}>
                <span className={pagesCss.listRowTitle}><StationNamedAt station={m.station} name={m.stationName} /></span>
                <span className={shellCss.muted}>{[m.about, m.usedBy > 0 ? t("web-pages.settings.profiles.usedBy", { n: m.usedBy }) : ""].filter(Boolean).join(" · ")}</span>
              </span>
              {!m.online ? <Pill tone="neutral">{t("web-pages.stations.offline")}</Pill> : !m.usable ? <Pill tone="red">{t("web-pages.settings.profiles.hostAway", { station: entry.hostName })}</Pill> : m.checkTone !== "green" && <Pill tone={m.checkTone as never}>{m.checkText}</Pill>}
              <ChevronRight {...ICON} className={shellCss.muted} />
            </Link>
          </li>
        ))}
      </ul>
    </Section>
  );
}

/**
 * Which of the workspaces the station joined may run their chats on it (docs/multi-workspace.md), a switch each:
 * for the owners and admins of its home workspace (the core's `memberships`), once the station is in more than one.
 * All are ticked at first: a profile serves every workspace the station is in until one is turned off.
 */
function WorkspacesSection({ profile }: { profile: Profile }) {
  const station = useStation();
  const api = useApi();
  const toast = useToast();
  const m = useMemberships(station.address).value;
  const joined = m?.manages ? m.workspaces.filter((w) => !w.home) : [];
  const now = profile.workspaces ?? [];
  const put = useAction((next: string[]) => api.putProfile(profile.id, { workspaces: next }));
  // What is being saved shows at once, its switch turning beside its ring.
  const shown = put.busy && put.args ? put.args[0] : now;
  if (joined.length === 0) return null;
  return (
    <Section title={t("web-pages.profiles.workspaces.title")} description={t("web-pages.profiles.workspaces.lead")}>
      {joined.map((w) => {
        const on = shown.includes(w.workspace);
        return (
          <SwitchRow key={w.workspace} title={t("web-pages.profiles.workspaces.for", { name: w.name })} checked={on}
            description={t(on ? "web-pages.profiles.workspaces.on" : "web-pages.profiles.workspaces.off", { name: w.name })}
            busy={put.busy && (put.args?.[0].includes(w.workspace) ?? false) !== now.includes(w.workspace)} disabled={put.busy}
            onChange={(next) => void put.run(next ? [...now, w.workspace] : now.filter((x) => x !== w.workspace)).then((ok) => {
              if (ok) toast(t(next ? "web-pages.profiles.workspaces.turnedOn" : "web-pages.profiles.workspaces.turnedOff", { name: w.name }));
            })} />
        );
      })}
    </Section>
  );
}

/**
 * Sharing with the workspace's other stations: a switch; once on, where a subscription is signed in (moved to another
 * station from here) and which stations may use it (every one unless some are picked). A copy of another station's
 * says whose it is, and leads there.
 */
function ShareSection({ profile }: { profile: Profile }) {
  const station = useStation();
  const api = useApi();
  const act = useAct();
  const workspace = station.address.split("/")[0]!;
  const entries = useProfiles(workspace).value?.items ?? [];
  const share = profile.share;
  // Its row of the workspace's list (the account it is), and there the station that lends it.
  const entry = entries.find((e) => e.members?.some((m) => m.station === station.address && m.profileId === profile.id));
  const stations = entry?.stations ?? [];
  const lender = share ? entry?.members?.find((m) => m.stationId === share.host && m.role === "host") : undefined;
  const on = { station: station.address, id: profile.id };
  const sharing = useDoing("profile.share", on);
  const moving = useDoing("profile.move", on);
  const [picking, setPicking] = useState(false);
  const [moveOpen, setMoveOpen] = useState(false);
  const subscription = profile.access.kind === "subscription";
  if (share?.role === "user") {
    const host = stations.find((x) => x.id === share.host)?.name ?? share.host.slice(0, 8);
    return (
      <Section title={t("web-pages.profiles.share.title")}>
        <p>{t("web-pages.profiles.share.copy", { station: host })}{lender && <> <Link to={`${stationBase(lender.station)}/settings/accounts/${encodeURIComponent(lender.profileId)}`}>{t("web-pages.profiles.share.goHost", { station: host })}</Link></>}</p>
        {subscription && share.reachable === false && <p className={controlsCss.fieldError}>{t("web-pages.profiles.share.hostAway", { station: host })}</p>}
      </Section>
    );
  }
  const shared = share !== undefined;
  const allowed = share?.allow ?? null;
  const names = allowed === null ? t("web-pages.profiles.share.everyStation") : stations.filter((x) => allowed.includes(x.id) || x.id === station.id).map((x) => x.name).join(t("web-main.list.separator"));
  const describe = !shared
    ? t("web-pages.profiles.share.onlyHere", { station: station.name })
    : subscription ? t("web-pages.profiles.share.lent") : t("web-pages.profiles.share.copied");
  const targets = stations.filter((x) => x.id !== station.id);
  return (
    <Section title={t("web-pages.profiles.share.title")}>
      <SwitchRow title={t("web-pages.profiles.share.switch")} description={describe} checked={shared} busy={sharing} disabled={sharing}
        onChange={(next) => act(api.shareProfile(profile.id, next, null), t("web-pages.profiles.share.switch"), next ? t("web-pages.profiles.share.shared") : t("web-pages.profiles.share.unshared"))} />
      {shared && <div className={css.shareRows}>
      {subscription && !profile.machine && (
        <div className={pagesCss.cardRow}>
          <span className={pagesCss.cardRowText}><b>{t("web-pages.profiles.share.signedIn")}</b></span>
          <span className={css.shareValue}><StatusDot state="online" /><StationNamedAt station={station.address} name={station.name} /></span>
          <Button variant="ghost" busy={moving} disabled={moving || targets.length === 0} onClick={() => setMoveOpen(true)}>{t("web-pages.profiles.share.move")}</Button>
        </div>
      )}
      <div className={pagesCss.cardRow}>
        <span className={pagesCss.cardRowText}><b>{t("web-pages.profiles.share.stations")}</b>
          {(share?.users?.length ?? 0) > 0 && <span className={shellCss.muted}>{t("web-pages.profiles.share.users", { stations: share!.users!.map((u) => stations.find((x) => x.id === u)?.name ?? u.slice(0, 8)).join(t("web-main.list.separator")) })}</span>}</span>
        <span className={css.shareValue}>{names}</span>
        <Button variant="ghost" disabled={sharing} onClick={() => setPicking(true)}>{t("web-pages.profiles.share.change")}</Button>
      </div>
      </div>}
      <Dialog open={moveOpen} onClose={() => setMoveOpen(false)} title={t("web-pages.profiles.share.moveTitle")} description={t("web-pages.profiles.share.moveLead", { station: station.name })}>
        <ul className={pagesCss.list}>
          {targets.map((x) => (
            <li key={x.id}>
              <button type="button" className={`${pagesCss.listRow} ${css.pickRow}`} disabled={!x.online}
                onClick={() => { setMoveOpen(false); act(api.moveProfile(profile.id, x.id), t("web-pages.profiles.share.move"), t("web-pages.profiles.share.moved", { station: x.name })); }}>
                <StatusDot state={x.online ? "online" : "offline"} /><span className={pagesCss.listRowTitle}>{x.name}</span>
                {!x.online && <span className={shellCss.muted}>{t("web-pages.stations.offline")}</span>}
              </button>
            </li>
          ))}
        </ul>
      </Dialog>
      {picking && <PickStations stations={stations} self={station.id} allowed={allowed} onClose={() => setPicking(false)}
        onSave={(next) => { setPicking(false); act(api.shareProfile(profile.id, true, next), t("web-pages.profiles.share.stations")); }} />}
    </Section>
  );
}

/** Which stations may use a share: every one (those to come too), or those ticked; the one that has it always. */
export function PickStations({ stations, self, allowed, onClose, onSave }: {
  stations: { id: string; name: string; online: boolean }[]; self: string; allowed: string[] | null; onClose(): void; onSave(allow: string[] | null): void;
}) {
  const [ticked, setTicked] = useState<Set<string>>(() => new Set(allowed ?? stations.map((x) => x.id)));
  const all = stations.every((x) => x.id === self || ticked.has(x.id));
  const toggle = (id: string) => setTicked((was) => { const next = new Set(was); if (next.has(id)) next.delete(id); else next.add(id); return next; });
  return (
    <Dialog open onClose={onClose} title={t("web-pages.profiles.share.stations")}
      description={all ? t("web-pages.profiles.share.futureIn") : t("web-pages.profiles.share.futureOut")}
      footer={<Button variant="primary" onClick={() => onSave(all ? null : [...new Set([...ticked, self])])}>{t("web-pages.profiles.share.done")}</Button>}>
      <ul className={pagesCss.list}>
        {stations.map((x) => (
          <li key={x.id}>
            <label className={pagesCss.listRow}>
              <input type="checkbox" checked={x.id === self || ticked.has(x.id)} disabled={x.id === self} onChange={() => toggle(x.id)} />
              <StatusDot state={x.online ? "online" : "offline"} /><span className={pagesCss.listRowTitle}>{x.name}</span>
              {x.id === self && <span className={shellCss.muted}>{t("web-pages.profiles.share.here")}</span>}
            </label>
          </li>
        ))}
      </ul>
    </Dialog>
  );
}

/** A profile on the machine's own login: whose it is, and that it is changed on the machine. */
function MachineAccount({ profile }: { profile: Profile }) {
  const station = useStation();
  const runtime = RUNTIME_LABEL[profile.runtime];
  return (
    <Section title={t("web-pages.profiles.account")}>
      <p>{station.name ? t("web-pages.profiles.machineLoginOn", { station: station.name, runtime }) : t("web-pages.profiles.machineLoginHere", { runtime })}<About>{t("web-pages.profiles.machineLoginAbout", { runtime })}</About></p>
    </Section>
  );
}

/**
 * The account itself: its key (shown masked, replaced here — its provider stays, since a profile is that account), or
 * for a subscription, signing in again (as another account, or after it expired).
 */
function AccountSection({ profile, signedIn, onSave, busy }: { profile: Profile; signedIn: boolean; onSave(input: ProfileInput): void; busy: boolean }) {
  const [replacing, setReplacing] = useState(false);
  const [key, setKey] = useState("");
  // Where a provider is at an address of the person's own, that too can be changed (a blank key keeps the stored one).
  const [endpoint, setEndpoint] = useState(profile.access.endpoint ?? "");
  // A profile on an account (OpenCode Go's, Kimi Code's) is signed in again, as a subscription is.
  const keyed = KEYED.has(profile.access.kind) && !profile.access.login;
  if (!keyed && profile.access.kind !== "subscription" && !profile.access.login) return null;
  const label = profile.access.kind === "opencode-go" ? "OpenCode Go key" : profile.providerName ? `${profile.providerName} key` : "API key";
  const changed = !!key || (profile.access.endpoint !== undefined && endpoint.trim() !== profile.access.endpoint);
  const stop = () => { setReplacing(false); setKey(""); setEndpoint(profile.access.endpoint ?? ""); };
  return (
    <Section title={t("web-pages.profiles.account")}>
      {keyed ? (
        <div className={pagesCss.card}>
          {!replacing ? (
            <div className={pagesCss.cardRow}>
              <div className={pagesCss.cardRowText}>
                <strong>{label}</strong>
                <span className={`${shellCss.muted} ${shellCss.mono}`}>{profile.access.key || t("web-pages.profiles.notSaved")}</span>
                {profile.access.endpoint && <span className={`${shellCss.muted} ${shellCss.mono}`}>{profile.access.endpoint}</span>}
              </div>
              <Button busy={busy} onClick={() => setReplacing(true)}>{t("web-pages.profiles.replace")}</Button>
            </div>
          ) : (
            <>
              {profile.access.endpoint !== undefined && (
                <Field label={t("common.provider.endpoint")} htmlFor="access-endpoint">
                  <input id="access-endpoint" className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} autoComplete="off" value={endpoint} onChange={(e) => setEndpoint(e.target.value.trim())} />
                </Field>
              )}
              <Field label={profile.access.kind === "opencode-go" ? t("web-pages.profiles.newOpencodeKey") : t("web-pages.profiles.newApiKey")} htmlFor="access-key" hint={t("web-pages.profiles.recheckHint")}>
                <div className={additionsCss.inputRow}>
                  <input id="access-key" className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} type="password" autoComplete="off" autoFocus value={key} onChange={(e) => setKey(e.target.value.trim())} placeholder={t("web-pages.profiles.pasteKey")} />
                  <Button variant="ghost" onClick={stop}>{t("common.cancel")}</Button>
                  {/* Closes at once: the button it came from turns until the key is saved. */}
                  <Button variant="primary" disabled={!changed} onClick={() => { onSave({ access: { kind: profile.access.kind, ...(key ? { key } : {}), ...(profile.access.endpoint !== undefined ? { endpoint: endpoint.trim() } : {}) } }); stop(); }}>{t("common.save")}</Button>
                </div>
              </Field>
            </>
          )}
        </div>
      ) : signedIn && <SignIn profile={profile} needed={false} />}
    </Section>
  );
}

interface EnvRow { row: number; key: string; value: string; masked: string | null; original: string | null }
let nextRow = 1;

/** The variables a custom profile runs with: what reaches its runtime's model service, set by hand. */
function EnvSection({ profile, onSave, busy }: { profile: Profile; onSave(input: ProfileInput): void; busy: boolean }) {
  const [rows, setRows] = useState<EnvRow[]>(() => profile.env.map((e) => ({ row: nextRow++, key: e.key, value: e.secret ? "" : e.value, masked: e.secret ? e.value : null, original: e.key })));
  const patch = (): Record<string, string | null> => {
    const out: Record<string, string | null> = {};
    const kept = new Set(rows.map((r) => r.key.trim()));
    for (const e of profile.env) if (!kept.has(e.key)) out[e.key] = null;
    for (const r of rows) {
      const key = r.key.trim();
      if (!key) continue;
      if (r.original && r.original !== key) out[r.original] = null;
      if (r.masked !== null && r.value === "" && r.original === key) continue;
      out[key] = r.value;
    }
    return out;
  };
  const update = (row: number, p: Partial<EnvRow>) => setRows(rows.map((r) => (r.row === row ? { ...r, ...p } : r)));
  return (
    <Section title={t("web-pages.profiles.env")} description={t("web-pages.profiles.envLead", { route: "{route}" })}>
      <div className={pagesCss.card}>
        <div className={css.envTable}>
          {rows.map((r) => {
            const secret = r.masked !== null || /KEY|TOKEN|SECRET|PASSWORD|AUTH/i.test(r.key);
            return (
              <div key={r.row} className={css.envRow}>
                <input className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} aria-label={t("web-pages.profiles.envName")} value={r.key} onChange={(e) => update(r.row, { key: e.target.value })} placeholder="NAME" />
                <input className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} aria-label={t("web-pages.profiles.envValueOf", { name: r.key || t("web-pages.profiles.envVariable") })} type={secret ? "password" : "text"} autoComplete="off" value={r.value}
                  onChange={(e) => update(r.row, { value: e.target.value })} placeholder={r.masked !== null ? t("web-pages.profiles.envSaved", { masked: r.masked }) : t("web-pages.profiles.envValue")} />
                <Button variant="ghost" onClick={() => setRows(rows.filter((x) => x.row !== r.row))}>{t("common.delete")}</Button>
              </div>
            );
          })}
          <div><Button variant="ghost" icon={Plus} onClick={() => setRows([...rows, { row: nextRow++, key: "", value: "", masked: null, original: null }])}>{t("web-pages.profiles.envAdd")}</Button></div>
        </div>
        <div className={pagesCss.cardActions}>
          <Button variant="primary" busy={busy} onClick={() => onSave({ env: patch() })}>{t("common.save")}</Button>
        </div>
      </div>
    </Section>
  );
}

/**
 * Signing a subscription account in without a terminal: ember runs the
 * runtime's login on its own machine and this panel relays the browser steps.
 */
function SignIn({ profile, needed }: { profile: Profile; needed: boolean }) {
  const api = useApi();
  const toast = useToast();
  const [code, setCode] = useState("");
  const [manual, setManual] = useState(false);
  const job = profile.login;
  const start = useAction(() => api.startLogin(profile.id));
  const cancel = useAction(() => api.cancelLogin(profile.id));
  const send = useAction(() => api.loginCode(profile.id, code), () => setCode(""));
  const active = job && ["starting", "needs_code", "needs_approval", "verifying"].includes(job.state);
  const provider = signInProvider(profile);
  // Announce a sign-in finishing while the page is open, not one that finished earlier.
  const previous = useRef(job?.state);
  useEffect(() => {
    if (job?.state === "done" && previous.current && previous.current !== "done") toast(t("web-pages.profiles.signedIn"));
    previous.current = job?.state;
  }, [job?.state, toast]);

  if (!active) {
    return (
      <div className={pagesCss.card}>
        <div className={pagesCss.cardRowText}>
          <strong>{needed ? t("web-pages.profiles.notSignedIn", { provider }) : t("web-pages.profiles.subscriptionSignIn", { provider })}</strong>
          <span className={shellCss.muted}>
            {job?.state === "failed" ? t("web-pages.profiles.lastFailed", { error: job.error ?? "" }) : job?.state === "done" ? t("web-pages.profiles.signedInSwitch") : t("web-pages.profiles.signInNote", { name: NAME })}
          </span>
        </div>
        {start.error && <p className={controlsCss.fieldError} role="alert">{start.error.message}</p>}
        {manual && profile.loginCommand && <CopyCommand text={profile.loginCommand} />}
        {/* Its one button solid, signed in or not: the card's others are words (pageControls.css.ts). */}
        <div className={pagesCss.cardFoot}>
          <Button variant="primary" icon={LogIn} busy={start.busy} onClick={() => void start.run()}>
            {job?.state === "done" || !needed ? t("web-pages.signIn.again") : t("web-pages.profiles.signIn")}
          </Button>
          {/* OpenCode's has no command to run by hand. */}
          {profile.loginCommand && <Button variant="ghost" onClick={() => setManual(!manual)}>{manual ? t("web-pages.profiles.collapse") : t("web-pages.profiles.manual")}</Button>}
        </div>
      </div>
    );
  }

  return (
    <div className={`${pagesCss.card} ${css.signIn}`} aria-live="polite">
      <div className={pagesCss.cardRowText}><strong>{t("web-pages.profiles.signingIn", { provider })}</strong><span className={shellCss.muted}>{t("web-pages.profiles.signingInNote")}</span></div>
      <LoginSteps job={job} provider={provider} code={code} setCode={setCode} send={() => void send.run()} sending={send.busy} sendError={send.error?.message ?? null} />
      {cancel.error && <p className={controlsCss.fieldError} role="alert">{t("web-pages.profiles.cancelFailed", { error: cancel.error.message })}</p>}
      {/* Under the steps, words: the steps' own buttons are what to press. */}
      <div className={pagesCss.cardFoot}><Button variant="ghost" busy={cancel.busy} onClick={() => void cancel.run()}>{t("common.cancel")}</Button></div>
    </div>
  );
}

/** Who a profile signs in to: OpenCode for OpenCode Go, Kimi for Kimi Code, else its runtime's vendor. */
const signInProvider = (profile: Profile) => (profile.access.kind === "opencode-go" ? "OpenCode" : profile.access.provider === "kimi-code" ? "Kimi" : profile.runtime === "claude" ? "Claude" : profile.runtime === "grok" ? "Grok" : profile.runtime === "cursor" ? "Cursor" : profile.runtime === "devin" ? "Devin" : "ChatGPT");

/**
 * A device sign-in (Codex's, Grok's, OpenCode's, Kimi's): the code comes first and is copied as the login page opens, so it is
 * pasted there with no trip back; the rest finishes by itself. OpenCode's and Kimi's pages have the code in their address: it is only
 * compared there, not copied. Cursor's has none: its page is only opened, and confirmed there.
 */
function DeviceCode({ url, code, provider }: { url: string; code: string | null; provider: string }) {
  const [copied, setCopied] = useState(false);
  const toast = useToast();
  const filled = provider === "OpenCode" || provider === "Kimi" || code === null;
  const go = () => {
    if (filled || code === null) return void window.open(url, "_blank", "noopener");
    // Not copied: the page opens all the same, the code to type in by hand.
    void navigator.clipboard.writeText(code).then(() => setCopied(true), () => toast(t("web-pages.profiles.copyFailed"))).finally(() => window.open(url, "_blank", "noopener"));
  };
  return (
    <div className={css.deviceCode}>
      {code !== null && <span className={`${css.deviceCodeValue} ${shellCss.mono}`}>{code}</span>}
      <Button variant="primary" icon={External} onClick={go}>{filled ? t("web-pages.profiles.openAuth") : copied ? t("web-pages.profiles.copiedReopen") : t("web-pages.profiles.copyOpen")}</Button>
      <p className={shellCss.muted}>{code === null ? t("web-pages.profiles.deviceCodeNoteCursor") : provider === "OpenCode" ? t("web-pages.profiles.deviceCodeNoteOpencode") : provider === "Kimi" ? t("web-pages.profiles.deviceCodeNoteKimi") : provider === "Grok" ? t("web-pages.profiles.deviceCodeNoteGrok") : t("web-pages.profiles.deviceCodeNote", { name: NAME })}</p>
    </div>
  );
}

/** What the person does in the browser for a sign-in under way: the link and the code to paste (Claude, Devin), the link
 * and the one-time code to enter (Codex), or the link alone, to confirm there (Cursor). */
export function LoginSteps({ job, provider, code, setCode, send, sending, sendError }: {
  job: LoginJob | null; provider: string; code: string; setCode(code: string): void; send(): void; sending: boolean; sendError: string | null;
}) {
  if (!job || job.state === "starting") return <p className={shellCss.muted}><span className={`${conversationCss.activityPulse} ${additionsCss.inline}`} aria-hidden="true" />{t("web-pages.profiles.generatingLink", { provider })}</p>;
  return (
    <>
      {job.state === "needs_code" && job.url && (
        <ol className={controlsCss.steps}>
          <li>
            <span>{provider === "Devin" ? t("web-pages.profiles.step1Devin", { name: NAME }) : t("web-pages.profiles.step1", { name: NAME })}</span>
            <a className={`${controlsCss.btn} ${controlsCss.btnPrimary}`} href={job.url} target="_blank" rel="noopener"><External {...ICON} />{t("web-pages.profiles.openAuth")}</a>
          </li>
          <li>
            <span>{provider === "Devin" ? t("web-pages.profiles.step2Devin") : t("web-pages.profiles.step2")}</span>
            <div className={additionsCss.inputRow}>
              <input className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} autoComplete="off" value={code} onChange={(e) => setCode(e.target.value)} placeholder={t("web-pages.profiles.pasteCode")} aria-label={t("web-pages.profiles.code")}
                onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && code.trim() && !sending) send(); }} />
              <Button variant="primary" disabled={!code.trim()} busy={sending} onClick={() => send()}>{t("web-pages.profiles.finish")}</Button>
            </div>
            {sendError && <p className={controlsCss.fieldError} role="alert">{sendError}</p>}
          </li>
        </ol>
      )}
      {/* No code where the page only asks to confirm (Cursor's). */}
      {job.state === "needs_approval" && job.url && <DeviceCode url={job.url} code={job.userCode || null} provider={provider} />}
      {job.state === "verifying" && <p className={shellCss.muted}><span className={`${conversationCss.activityPulse} ${additionsCss.inline}`} aria-hidden="true" />{t("web-pages.profiles.finishing")}</p>}
      {job.state === "done" && <p className={shellCss.muted}><span className={`${conversationCss.activityPulse} ${additionsCss.inline}`} aria-hidden="true" />{t("web-pages.profiles.adding")}</p>}
    </>
  );
}

/**
 * A plan's sign-in on a station without the runtime it signs in with (core `install`): installing it first, how that
 * stands, and its button when the viewer may (`software.update`). The sign-in starts once it is installed.
 */
export function InstallStep({ install }: { install: RuntimeInstall }) {
  const station = useStation().address;
  const busy = useDoing("software.update", { station, id: install.runtime });
  const api = useApi();
  const act = useAct();
  const installing = install.state === "installing";
  return (
    <div className={pagesCss.card}>
      <div className={pagesCss.cardRowText}>
        <strong>{install.title}</strong>
        {install.detail ? <span className={controlsCss.fieldError} role="alert">{install.detail}</span> : <span className={shellCss.muted}>{install.note ?? t("web-pages.profiles.installThenSignIn")}</span>}
      </div>
      {installing && <Progress part={install.percent != null ? install.percent / 100 : null} label={install.title} />}
      {install.action && <div className={pagesCss.cardFoot}><Button variant="primary" busy={busy} onClick={() => act(api.updateSoftware(install.runtime), install.action!)}>{install.action}</Button></div>}
    </div>
  );
}

function FastSection({ profile }: { profile: Profile }) {
  const api = useApi();
  const station = useStation();
  const act = useAct();
  const params = { station: station.address, id: profile.id };
  const busy = useDoing("profile.put", params);
  const error = useDoingFailed("profile.put", params);
  return <Section title={t("web-pages.profiles.run")}><SwitchRow title={t("web-pages.profiles.fast")} checked={!!profile.fast} disabled={busy}
    description={t("web-pages.profiles.fastLead")}
    onChange={(fast) => act(api.putProfile(profile.id, { fast }), t("web-pages.profiles.fastSave"), fast ? t("web-pages.profiles.fastOn") : t("web-pages.profiles.fastOff"))} />
    {busy && <WaitLine text={t("common.saving")} />}
    {error && <p className={controlsCss.fieldError}>{error}</p>}
  </Section>;
}

function QuotaSection({ profile }: { profile: Profile }) {
  const api = useApi();
  // A refresh comes back with the overview.
  const refresh = useAction(() => api.refreshQuota(profile.id));
  const quota = profile.quota;
  const station = useStation();
  const toast = useToast();
  const [resetting, setResetting] = useState(false);
  const params = { station: station.address, id: profile.id };
  const busy = useDoing("profile.resetQuota", params);
  const failed = useDoingFailed("profile.resetQuota", params);
  const reset = useAction(() => api.resetQuota(profile.id), () => toast(t("web-pages.profiles.quotaReset")));
  return (
    <Section title={<>{t("web-pages.profiles.quota")}{quota?.time?.checkedAt && <About>{t("web-pages.profiles.quotaAbout", { ago: quota.time.checkedAt.ago })}</About>}</>}
      actions={<Button variant="ghost" icon={Refresh} busy={refresh.busy} onClick={() => void refresh.run()}>{t("web-pages.profiles.refresh")}</Button>}>
      {(quota?.windows.length || !quota?.creditsText) ? <QuotaBars quota={quota} /> : null}
      {quota?.creditsText && <p>{tx("web-pages.profiles.credits", { credits: <span className={shellCss.muted}>{quota.creditsText}</span> })}</p>}
      {quota?.resetCount != null && <p>{tx("web-pages.profiles.resets", { resets: <span className={shellCss.muted}>{quota.resetText}</span> })}{" "}
        <Button variant="ghost" disabled={!quota.resetCount || busy} busy={busy} onClick={() => setResetting(true)}>{t("web-pages.profiles.reset")}</Button>
      </p>}
      {failed && <p className={controlsCss.fieldError}>{failed}</p>}
      <Confirm open={resetting} onClose={() => setResetting(false)} title={t("web-pages.profiles.resetConfirm")} action={t("web-pages.profiles.resetAction")}
        description={t("web-pages.profiles.resetBody", { name: profile.name, n: quota?.resetCount ?? 0 })}
        onConfirm={() => { setResetting(false); void reset.run(); }} />
      {refresh.error && <p className={controlsCss.fieldError} role="alert">{t("web-pages.profiles.refreshFailed", { error: refresh.error.message })}</p>}
    </Section>
  );
}

/**
 * Which of the profile's models may be used, picked here (one just signed in
 * starts with those the others of its runtime have, the station's
 * accounts/models.ts). Chats and connects offer only enabled models, and the
 * account pool sends a chat only to a profile that has its model enabled.
 */
function ModelPool({ profile, found, onSave }: { profile: Profile; found: string[] | null; onSave(models: string[]): Promise<unknown> }) {
  const enabled = new Set(profile.models);
  const all = [...new Set([...(found ?? []), ...profile.models])].sort();
  const name = (m: string) => profile.names[m] ?? m;
  // With none enabled yet (a profile just added), the whole list is out to choose from.
  const [picked, setChoosing] = useState<boolean | null>(null);
  const choosing = picked ?? enabled.size === 0;
  const ordered = modelSeries(profile, all).flatMap((s) => s.models);
  const on = [...enabled].sort((a, b) => ordered.indexOf(a) - ordered.indexOf(b));
  // A provider that answers the automatic decisions alone: the models its probe found, as they are.
  if (profile.decisionOnly) {
    return (
      <Section title={t("web-pages.profiles.decisionModels")}>
        {(profile.decisionModels ?? []).length > 0 ? (
          <ul className={css.modelChips}>{(profile.decisionModels ?? []).map((m) => <li key={m} className={css.modelChip}><span>{m}</span></li>)}</ul>
        ) : null}
        {profile.decisionText && <p className={shellCss.muted}>{profile.decisionText}</p>}
      </Section>
    );
  }
  return (
    <Section title={<>{t("web-pages.profiles.models")}<About>{all.length ? t("web-pages.profiles.modelsAbout") : t("web-pages.profiles.modelsAboutNone")}</About></>}
      actions={all.length > 0 && <Button variant="ghost" onClick={() => setChoosing(!choosing)}>{choosing ? t("web-pages.profiles.collapse") : t("web-pages.profiles.chooseModels", { on: enabled.size, all: all.length })}</Button>}>
      <div className={css.modelsBody}>
        {/* What it can be used for now, first; the whole list only when choosing. */}
        {all.length > 0 && !choosing && (
          on.length === 0 ? <p className={shellCss.muted}>{t("web-pages.profiles.noModels")}</p> : (
            <ul className={css.modelChips}>
              {on.map((m) => <Tip key={m} label={m}><li className={css.modelChip}><ModelLogo maker={profile.makers[m]} runtime={profile.runtime} size={14} /><span>{name(m)}</span></li></Tip>)}
            </ul>
          )
        )}
        {all.length > 0 && choosing && <ModelChecklist profile={profile} found={found} onSave={onSave} />}
        {/* A provider that does not list its models: one is named by hand. */}
        {profile.canAddModel && <AddModel profile={profile} />}
      </div>
    </Section>
  );
}

/** The whole list of a profile's models to enable, by series, with a filter when there are many and all / none of
 * what is shown; each tick saved at once. On its page (ModelPool) and on the step after it is added (PickModelsPage). */
function ModelChecklist({ profile, found, onSave }: { profile: Profile; found: string[] | null; onSave(models: string[]): Promise<unknown> }) {
  const enabled = new Set(profile.models);
  const busy = profile.modelsSaving != null;
  const [filter, setFilter] = useState("");
  const all = [...new Set([...(found ?? []), ...profile.models])].sort();
  const name = (m: string) => profile.names[m] ?? m;
  const shown = all.filter((m) => [m, name(m)].some((s) => s.toLowerCase().includes(filter.trim().toLowerCase())));
  const commit = (next: Set<string>) => { void onSave([...next].sort()); };
  const toggle = (m: string) => {
    const next = new Set(enabled);
    if (next.has(m)) next.delete(m); else next.add(m);
    commit(next);
  };
  const series = modelSeries(profile, all);
  return (
    <div className={chatCss.modelPool}>
      <div className={chatCss.modelPoolTools}>
        {all.length > 10 && <input className={`${controlsCss.input} ${css.modelPoolFilter}`} placeholder={t("web-pages.profiles.filter")} autoFocus value={filter} onChange={(e) => setFilter(e.target.value)} />}
        <button type="button" className={controlsCss.textToggle} disabled={busy} onClick={() => commit(new Set([...enabled, ...shown]))}>{filter ? t("web-pages.profiles.selectFiltered") : t("web-pages.settings.members.all")}</button>
        <button type="button" className={controlsCss.textToggle} disabled={busy} onClick={() => commit(new Set([...enabled].filter((m) => !shown.includes(m))))}>{filter ? t("web-pages.profiles.unselectFiltered") : t("web-pages.settings.members.none")}</button>
      </div>
      {series.map((s) => {
        const list = s.models.filter((m) => shown.includes(m));
        if (list.length === 0) return null;
        const every = list.every((m) => enabled.has(m));
        return (
          <div key={s.name} className={modelCss.poolSeries}>
            <div className={modelCss.poolSeriesHead}>
              <h4>{s.name}</h4>
              <button type="button" className={controlsCss.textToggle} disabled={busy} onClick={() => commit(every ? new Set([...enabled].filter((m) => !list.includes(m))) : new Set([...enabled, ...list]))}>{every ? t("web-pages.settings.members.none") : t("web-pages.settings.members.all")}</button>
            </div>
            <ul className={chatCss.modelPoolList}>
              {list.map((m) => (
                <li key={m}>
                  <Tip label={m}><label className={chatCss.modelPoolItem} data-on={enabled.has(m) || undefined}>
                    <input type="checkbox" disabled={busy} checked={enabled.has(m)} onChange={() => toggle(m)} />
                    <ModelLogo maker={profile.makers[m]} runtime={profile.runtime} size={14} />
                    <span>{name(m)}</span>
                    {profile.modelsSaving?.includes(m) && <Spinner inline label={t("common.saving")} />}
                    {found && !found.includes(m) && <span className={`${shellCss.muted} ${css.modelPoolGone}`}>{t("web-pages.profiles.gone")}</span>}
                  </label></Tip>
                </li>
              ))}
            </ul>
          </div>
        );
      })}
    </div>
  );
}

/** Its models and those its check found, by the core's series (newest first); one a newer check found that the core
 * has not placed yet goes with 其他. */
function modelSeries(profile: Profile, all: string[]) {
  const placed = new Set(profile.series.flatMap((s) => s.models));
  const loose = all.filter((m) => !placed.has(m));
  // The core's series of the rest, as it names it in either language (core-views.present.models_other).
  const isOther = (name: string) => name === "其他" || name === "Other";
  const other = profile.series.find((s) => isOther(s.name));
  return [...profile.series.filter((s) => !isOther(s.name)),
    ...((other?.models.length ?? 0) + loose.length ? [{ name: other?.name ?? t("web-pages.profiles.otherSeries"), models: [...(other?.models ?? []), ...loose] }] : [])];
}

/** A model named by hand, for a provider that does not list them all. */
function AddModel({ profile }: { profile: Profile }) {
  const api = useApi();
  const act = useAct();
  const [typed, setTyped] = useState("");
  const adding = useDoing("profile.addModel", { station: useStation().address, id: profile.id });
  const add = () => { act(api.addModel(profile.id, typed.trim()), t("web-pages.profiles.addModelWhat")); setTyped(""); };
  return (
    <div className={additionsCss.inputRow}>
      <input className={`${controlsCss.input} ${shellCss.mono}`} spellCheck={false} autoComplete="off" value={typed} aria-label={t("web-pages.profiles.addModelLabel")} placeholder={t("web-pages.profiles.addModelPlaceholder")}
        onChange={(e) => setTyped(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing && typed.trim() && !adding) add(); }} />
      <Button disabled={!typed.trim()} busy={adding} onClick={add}>{t("web-pages.profiles.addModel")}</Button>
    </div>
  );
}

/**
 * The step right after a profile is added (settings/accounts/<id>/models): its models chosen on a page of their own,
 * since chats use only those enabled, or skipped; either way on to its page. Its models are read by the check the
 * station runs once it is added (a few seconds): until then, that.
 */
export function PickModelsPage() {
  const { id = "" } = useParams();
  const api = useApi();
  const link = useLink();
  const navigate = useNavigate();
  const overview = useOverview(useStation().address);
  const profile = overview.value?.profiles.find((p) => p.id === id);
  const save = useAction((models: string[]) => api.putProfile(id, { models }));
  if (!overview.value) return overview.error ? <Empty><p>{overview.error.message}</p></Empty> : <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}><Waiting shape="cards" text={t("web-pages.profiles.loading")} /></div>;
  if (!profile) return <Empty><p>{t("web-pages.profiles.notFound", { id })}</p></Empty>;
  const leave = () => navigate(link(`/settings/accounts/${encodeURIComponent(id)}`), { replace: true });
  const found = profile.check?.models ?? null;
  const listed = (profile.available ?? []).length > 0;
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <header className={pagesCss.pageHead}>
        <div>
          <h1>{t("web-pages.profiles.pickModels.title")}</h1>
          <p className={shellCss.muted}>{t("web-pages.profiles.pickModels.lead", { name: profile.name })}</p>
        </div>
        <div className={css.pickModelsActions}>
          <Button variant="ghost" onClick={leave}>{t("web-pages.profiles.pickModels.skip")}</Button>
          <Button variant="primary" disabled={profile.models.length === 0} onClick={leave}>{t("common.done")}</Button>
        </div>
      </header>
      {profile.modelsReading ? <WaitLine text={t("web-pages.profiles.pickModels.reading")} />
        : !listed && !profile.canAddModel ? <p className={shellCss.muted}>{profile.check?.state === "ok" ? t("web-pages.profiles.pickModels.none") : profile.check?.detail || profile.checkText}</p>
        : (
          <div className={css.modelsBody}>
            {listed && <ModelChecklist profile={profile} found={found} onSave={(models) => save.run(models)} />}
            {profile.canAddModel && <AddModel profile={profile} />}
          </div>
        )}
      {save.error && <p className={controlsCss.fieldError} role="alert">{save.error.message}</p>}
    </div>
  );
}
