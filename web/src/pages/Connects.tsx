// Connects, as a settings page: every station's connects in the workspace.
// Each shows who added it, and the list can be narrowed to the viewer's own.
import { Illustration } from "../brand.tsx";
import { Key, Plug, Plus } from "../icons.tsx";
import { DropdownMenu } from "radix-ui";
import { useState } from "react";
import { Link } from "react-router";
import { useAction, useApi, useConnects, useStations, type MadeSlackApp } from "../api.ts";
import { MineFilter, OwnerLabel } from "../components.tsx";
import { profilesPage, StationContext, stationBase, useOnlyMine, type Station } from "../station.tsx";
import { About, Button, Confirm, ConnectAvatar, FirstOne, Menu, MobileBack, SlackLogo, StatusDot } from "../ui.tsx";
import { NewConnectDialog } from "./Connect.tsx";
import { DoingMark } from "../DoingMark.tsx";
import * as controlsCss from "../styles/controls.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as css from "./Connects.css.ts";
import * as cloudCss from "../styles/cloud.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";
/** The connects of a workspace, from the core's `connects` view; `settings` is where the scope's settings live. */
export function ConnectList({ scope, settings }: { scope: string; settings: string }) {
  const [onlyMine] = useOnlyMine();
  const connects = useConnects(scope, onlyMine);
  const stations = useStations(scope);
  // A connect being added on a station: from the start, or (`resume`) from a Slack app made before.
  const [adding, setAdding] = useState<{ station: Station; resume?: string } | null>(null);
  const shown = connects.value?.items ?? [];
  const loading = !connects.value || connects.value.loading;
  const targets: Station[] = (stations.value ?? []).filter((s) => s.online).map((s) => ({
    id: s.id, name: s.name, base: stationBase(s.station), address: s.station, online: true, settings,
  }));
  // The Slack apps the viewer made that no connect has taken yet, each on its station: to be finished any time.
  const waiting = (stations.value ?? []).flatMap((s) => (s.overview?.slackApps ?? []).map((app) => ({ app, station: targets.find((target) => target.address === s.station) ?? null, stationName: s.name })));
  // None at all yet (not only none of the viewer's): the page is about adding the first.
  const first = !loading && !connects.error && shown.length === 0 && !onlyMine && waiting.length === 0;
  // A connect runs a profile's model: with none on any station (each read), the first step is a profile.
  const listed = stations.value ?? [];
  const noProfile = listed.length > 0 && listed.every((s) => s.overview && s.overview.profiles.length === 0);
  const profiles = profilesPage({ id: "", name: "", base: "", address: "", online: true, settings });
  // Adding one: on the one station there is, or on one picked.
  const add = (label: string, primary = false) => targets.length === 1 ? <Button variant={primary ? "primary" : "secondary"} icon={Plus} onClick={() => setAdding({ station: targets[0]! })}>{label}</Button> : targets.length > 1 && (
    <DropdownMenu.Root modal={false}>
      <DropdownMenu.Trigger asChild><Button variant={primary ? "primary" : "secondary"} icon={Plus}>{label}</Button></DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList}`} align={primary ? "center" : "end"} sideOffset={4}>
          <DropdownMenu.Label className={controlsCss.menuLabel}>{t("web-pages.connects.whichStation")}</DropdownMenu.Label>
          {targets.map((s) => <DropdownMenu.Item key={s.id} className={controlsCss.menuItem} onSelect={() => setAdding({ station: s })}>{s.name}</DropdownMenu.Item>)}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );

  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={settings} label={t("web-pages.settings.title")} />
      <header className={pagesCss.pageHead}>
        <div>
          <h1>{t("web-pages.settings.nav.connects")}<About>{t("web-pages.connects.about", { name: NAME })}</About></h1>
        </div>
        {!first && add(t("web-pages.connects.add"))}
      </header>
      <div>
      {first && noProfile ? (
        <FirstOne art={<Illustration name="no-profile" />} title={t("web-pages.connects.profileFirst")} lead={t("web-pages.connects.profileFirstLead")}>
          <Link className={`${controlsCss.btn} ${controlsCss.btnPrimary}`} to={profiles}>{t("web-pages.connects.goAddProfile")}</Link>
        </FirstOne>
      ) : first ? (
        <FirstOne art={<Illustration name="no-connect" />} title={t("web-pages.connects.addFirst")} lead={t("web-pages.connects.addFirstLead")}>
          {add(t("web-pages.connects.add"), true) || <p className={shellCss.muted}>{stations.value?.length ? t("web-pages.connects.noOnline") : t("web-pages.connects.stationFirst")}</p>}
        </FirstOne>
      ) : <MineFilter label={t("web-pages.settings.nav.connects")} />}
      {waiting.length > 0 && (
        <section className={pagesCss.section} aria-label={t("web-pages.connects.waiting")}>
          <h2 className={css.sectionTitleQuiet}>{t("web-pages.connects.waiting")}</h2>
          <ul className={pagesCss.list}>
            {waiting.map(({ app, station, stationName }) => (
              <li key={`${stationName}/${app.appId}`}>
                {station ? (
                  <StationContext.Provider value={station}>
                    <WaitingApp app={app} stationName={stationName} onGo={() => setAdding({ station, resume: app.appId })} />
                  </StationContext.Provider>
                ) : <WaitingApp app={app} stationName={stationName} onGo={null} />}
              </li>
            ))}
          </ul>
        </section>
      )}
      {first ? null : shown.length === 0 ? (
        <p className={connects.error ? controlsCss.fieldError : shellCss.muted}>{connects.error?.message ?? (loading ? t("web-pages.settings.reading") : onlyMine ? t("web-pages.connects.noneMine") : t("web-pages.connects.none"))}</p>
      ) : (
        <ul className={pagesCss.list}>
          {shown.map(({ connect: c, station, stationName }) => (
            <li key={`${station}/${c.id}`}>
              <Link className={pagesCss.listRow} to={`${stationBase(station)}/connects/${c.id}`}>
                <ConnectAvatar connect={c} />
                <span className={pagesCss.listRowText}>
                  <span className={pagesCss.listRowTitle}>{c.name}{c.team && <span className={css.connectTeam}><SlackLogo size={11} />{c.team}</span>}</span>
                  <span className={shellCss.muted}>{c.modeText} · {c.runtimeText}{c.bind.model ? ` · ${c.modelName ?? c.bind.model}` : ""}</span>
                </span>
                <span className={css.connectFacts}>
                  <span className={cloudCss.stationTag}>{stationName}</span>
                  <OwnerLabel owner={c.createdBy} />
                </span>
                <span className={css.navNote}>{c.statusText}</span>
                {/* Being deleted (asked on its page, which has gone back here): a ring until the station has dropped it. */}
                <DoingMark calls="connect.delete" on={{ station, id: c.id }} className={controlsCss.iconSpinner} size={14} label={t("web-main.activity.busy")} />
                <StatusDot state={c.presence} label={c.statusText} />
              </Link>
            </li>
          ))}
        </ul>
      )}
      </div>
      {adding && (
        <StationContext.Provider value={adding.station}>
          <NewConnectDialog open onClose={() => setAdding(null)} resume={adding.resume} />
        </StationContext.Provider>
      )}
    </div>
  );
}

/**
 * A Slack app made and not connected yet: where it stands (to install, or only its app-level token left), going on from
 * there (`onGo`, when its station is online), or dropping it (it stays in Slack).
 */
function WaitingApp({ app, stationName, onGo }: { app: MadeSlackApp; stationName: string | null; onGo: (() => void) | null }) {
  const api = useApi();
  const [dropping, setDropping] = useState(false);
  const drop = useAction(() => api.dropSlackApp(app.appId));
  const where = app.installed ? t("web-pages.connects.installedNeedsToken", { team: app.installedTeam ?? app.team ?? t("web-pages.cloud.slackInstalled.workspace") }) : app.install ? t("web-pages.connects.notInstalled") : t("web-pages.connects.needsToken");
  return (
    <div className={pagesCss.listRow}>
      <SlackLogo size={18} />
      <span className={pagesCss.listRowText}>
        <span className={pagesCss.listRowTitle}>{app.name}{app.team && <span className={css.connectTeam}><SlackLogo size={11} />{app.team}</span>}</span>
        <span className={shellCss.muted}>{where}</span>
      </span>
      {stationName && <span className={css.connectFacts}><span className={cloudCss.stationTag}>{stationName}</span></span>}
      {onGo ? <Button onClick={onGo}>{t("web-pages.connects.continue")}</Button> : <span className={css.navNote}>{t("web-pages.connects.stationOffline")}</span>}
      {/* Dropped from the Confirm, which closes at once: a ring in the menu's place until it is gone, a failure said by toast. */}
      <DoingMark calls="slack.dropApp" on={{ appId: app.appId }} className={controlsCss.iconSpinner} size={14} label={t("web-main.activity.busy")} />
      {onGo && !drop.busy && <Menu items={[{ label: t("web-pages.connects.removeHere"), danger: true, onSelect: () => setDropping(true) }]} />}
      <Confirm open={dropping} onClose={() => setDropping(false)} onConfirm={() => { setDropping(false); void drop.run(); }}
        title={t("web-pages.settings.stations.removeConfirm", { name: app.name })} action={t("web-pages.settings.members.unadd")} description={t("web-pages.connects.removeBody", { name: NAME })} />
    </div>
  );
}

