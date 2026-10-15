// The sidebar while in the profiles (Rail.tsx, with Profile in the rail): 添加 Profile in the band over it, then every profile of the
// workspace (the core's `profiles`), a section each kind of account, one row an account however many stations it is
// on: its provider and its name on the first line, what is left of its allowance on the second (how it is doing before
// it when something is wrong; where it is and which connects use it instead when there is no allowance to show). Under
// them, the machines' own logins not used yet. The page beside is the one picked (pages/Accounts.tsx); come to the
// profiles, the first is picked (cloud/settings.tsx RuntimeSettings).
import { useSyncExternalStore, useState, type ReactNode } from "react";
import { useLocation, useNavigate } from "react-router";
import { useAction, useApi, useProfiles, useStations, type StationView } from "./api.ts";
import type { MachineLogin, Quota, WorkspaceProfile } from "./core/shapes.ts";
import { EdgeChip } from "./components.tsx";
import { Plus } from "./icons.tsx";
import { addProfilePath } from "./pages/AddProfile.tsx";
import { hosts, profileGroups } from "./cloud/settings.tsx";
import { StationContext, stationBase, type Station } from "./station.tsx";
import { useToast } from "./toast.tsx";
import { Dialog, ICON, ProviderLogo, StatusDot, Tip } from "./ui.tsx";
import { NavAction, NavList, NavItem, NavLine, NavSection, NavTop, navFill } from "./SidebarList.tsx";
import * as nav from "./Sidebar.css.ts";
import * as css from "./ProfilesNav.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as accountsCss from "./pages/Accounts.css.ts";
import { usePrefs } from "./prefs.ts";
import { railItems } from "./Rail.tsx";
import { NAME } from "./channel.ts";
import { t } from "./i18n.ts";

const WIDE = "(min-width: 701px)";

/** Whether the profiles have this sidebar: Profile in the rail, on a wide screen (on a narrow one the list is a page). */
export function useProfilesSidebar(): boolean {
  const railed = railItems(usePrefs((p) => p.rail)).includes("profiles");
  const wide = useSyncExternalStore((f) => {
    const query = window.matchMedia(WIDE);
    query.addEventListener("change", f);
    return () => query.removeEventListener("change", f);
  }, () => window.matchMedia(WIDE).matches, () => true);
  return railed && wide;
}

/** A profile's page: the station's copy the row shows (the one signed in, up), where what is shared is set too. */
export const profilePath = (e: WorkspaceProfile) => `${stationBase(e.station)}/settings/accounts/${encodeURIComponent(e.profile.id)}`;

export function ProfilesNav({ scope, top }: { scope: string; top?: ReactNode }) {
  const profiles = useProfiles(scope).value;
  const stations = useStations(scope).value ?? [];
  const online = stations.filter((s) => s.online);
  const navigate = useNavigate();
  const [choosing, setChoosing] = useState(false);
  const add = () => (online.length === 1 ? navigate(addProfilePath(scope, online[0]!.station)) : setChoosing(true));
  const items = profiles?.items ?? [];
  return (
    <>
      <NavTop top={top} action={online.length > 0 && <NavAction icon={<Plus {...ICON} />} label={t("web-pages.settings.profiles.add")} onClick={add} />} />
      <NavList>
        {profiles && items.length === 0 && !profiles.loading && <p className={nav.navEmpty}>{t("web-pages.settings.profiles.none")}</p>}
        {profileGroups(items).map((g) => (
          <NavSection key={g[0]!.group} title={g[0]!.groupTitle}>
            {g.map((e) => <ProfileRow key={e.key} entry={e} scope={scope} />)}
          </NavSection>
        ))}
        {online.map((s) => <MachineLogins key={s.id} station={s} scope={scope} />)}
        <Dialog open={choosing} onClose={() => setChoosing(false)} title={t("web-pages.settings.profiles.addWhere")} description={t("web-pages.settings.profiles.addWhereLead")}>
          <ul className={pagesCss.list}>
            {online.map((st) => (
              <li key={st.id}><button type="button" className={`${pagesCss.listRow} ${accountsCss.pickRow}`} onClick={() => { setChoosing(false); navigate(addProfilePath(scope, st.station)); }}>
                <StatusDot state="online" /><span className={pagesCss.listRowTitle}>{st.name}</span>
              </button></li>
            ))}
          </ul>
        </Dialog>
      </NavList>
    </>
  );
}

/** Whether the page in view is this account's: its page on any of its stations, or its page across them. */
function isHere(e: WorkspaceProfile, path: string, scope: string): boolean {
  if (path === `/w/${scope}/settings/profiles/account/${encodeURIComponent(e.key)}`) return true;
  return (e.members ?? []).some((m) => path === `${stationBase(m.station)}/settings/accounts/${encodeURIComponent(m.profileId)}`);
}

function ProfileRow({ entry, scope }: { entry: WorkspaceProfile; scope: string }) {
  const path = useLocation().pathname;
  const p = entry.profile;
  // Only what is wrong is in colour: one nobody can use now, one whose check did not pass.
  const trouble = !entry.usable ? t("web-pages.settings.profiles.hostAway", { station: entry.hostName }) : p.checkTone !== "green" ? p.checkText : null;
  const several = hosts(entry).length > 1;
  const facts = [
    entry.where,
    p.usedBy.length > 0 ? t("web-pages.settings.profiles.usedBy", { n: p.usedBy.length }) : null,
  ].filter(Boolean).join(" · ");
  // What is left of its allowance has the second line to itself; where it is and who uses it, on the tip then.
  const windows = Windows({ quota: p.quota });
  return (
    <NavItem to={profilePath(entry)} current={isHere(entry, path, scope)} away={!entry.usable} tip={windows ? facts || undefined : several ? entry.where : undefined}
      mark={<ProviderLogo runtime={p.runtime} kind={p.access.kind} mark={p.providerMark} size={16} />} title={p.name}>
      <NavLine>
        {trouble && <span className={css.trouble} data-tone={entry.usable ? p.checkTone : "red"}>{trouble}</span>}
        {windows ?? <>{trouble && facts && <span aria-hidden="true">·</span>}<span className={navFill}>{facts}</span></>}
      </NavLine>
    </NavItem>
  );
}

/** An allowance's windows, shortest first, each named by its mark; when each refills on the tip. */
function Windows({ quota }: { quota: Quota | null | undefined }) {
  if (!quota || quota.state !== "ok") return null;
  // A key's balance, where its provider says one.
  if (quota.windows.length === 0) return quota.creditsText ? <span className={css.credits}>{quota.creditsText}</span> : null;
  const left = (w: Quota["windows"][number]) => t("web-main.quota.left", { label: w.label, left: w.left });
  return (
    <span className={css.quota}>
      {quota.windows.map((w) => (
        <Tip key={w.label} label={<>{left(w)}{w.refills && <><br />{w.refills}</>}</>}>
          <EdgeChip fill={w.left} level={w.level} mark={w.mark} label={left(w)} small bare />
        </Tip>
      ))}
    </span>
  );
}

const RUNTIME: Record<MachineLogin["runtime"], string> = { claude: "Claude Code", codex: "Codex" };

/** A station's own logins not made profiles yet (as the list page offers them, pages/Accounts.tsx MachineLoginOffers):
 * used as they are, or signed in again for still.fail where the station cannot read them. */
function MachineLogins({ station, scope }: { station: StationView; scope: string }) {
  const offers = (station.overview?.machineLogins ?? []).filter((l) => l.offered && l.quota?.state !== "blocked");
  if (offers.length === 0) return null;
  const at: Station = { id: station.id, name: station.name, online: station.online, address: station.station, base: stationBase(station.station), settings: `/w/${scope}/settings` };
  return (
    <StationContext.Provider value={at}>
      <NavSection title={t("web-pages.profiles.machineSignedIn", { station: station.name })}>
        {offers.map((l) => <MachineLoginRow key={l.runtime} login={l} scope={scope} station={station.station} />)}
      </NavSection>
    </StationContext.Provider>
  );
}

function MachineLoginRow({ login, scope, station }: { login: MachineLogin; scope: string; station: string }) {
  const api = useApi();
  const navigate = useNavigate();
  const toast = useToast();
  const use = useAction(() => api.useMachineLogin(login.runtime), ({ id }) => {
    toast(t("web-pages.profiles.machineAdded"));
    navigate(`${stationBase(station)}/settings/accounts/${encodeURIComponent(id)}`);
  });
  const signIn = () => navigate(addProfilePath(scope, station, login.runtime === "claude" ? "anthropic" : "openai", "plan"));
  return (
    <Tip label={login.usable ? t("web-pages.profiles.useMachineTip") : t("web-pages.profiles.keychainTip", { name: NAME })} side="right">
      <NavItem disabled={use.busy} onClick={() => (login.usable ? void use.run() : signIn())}
        mark={<ProviderLogo runtime={login.runtime} kind="subscription" size={16} />} title={RUNTIME[login.runtime]}>
        <NavLine>
          <span className={navFill}>{login.email ?? t("web-main.profile.signedIn")}</span>
          <Windows quota={login.quota} />
          <span className={css.offer}>{use.busy ? t("web-pages.settings.profiles.using") : login.usable ? t("web-pages.profiles.useThis") : t("web-pages.profiles.signIn")}</span>
        </NavLine>
      </NavItem>
    </Tip>
  );
}
