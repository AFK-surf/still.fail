// The settings' 本机 Station page, in the desktop app: this machine's station whoever runs it (the app, a service
// installed on its own, a process started by hand), in a card as a workspace's stations are (cloud/StationCards.tsx):
// whether it runs, how and where, starting, stopping, restarting it in its menu, and an installed one behind the app's
// release brought up to it in place, offered as a station's updates are (Versions.tsx UpdateSummary). Which workspace
// it is in is only said: joining one is the workspace's station settings' (「添加这台 Mac」).
import { useEffect, useState } from "react";
import { useAction } from "../action.ts";
import type { LocalStationAction, LocalStationState } from "../core/client.ts";
import { FileText, Folder, Play, Refresh, Stop } from "../icons.tsx";
import { About, Menu, MobileBack, StatusDot } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as cardsCss from "../cloud/StationCards.css.ts";
import * as versionsCss from "../Versions.css.ts";
import * as css from "./LocalStation.css.ts";

import { NAME } from "../channel.ts";
import { t } from "../i18n.ts";

/** Only the desktop app has a station of this machine to manage (an app from before the page has no way to it). */
export const HAS_LOCAL_STATION = typeof window !== "undefined" && !!window.stillfailDesktop?.local;

/** The desktop app on Windows: a PC, not a Mac. */
const PC = typeof navigator !== "undefined" && /Windows/.test(navigator.userAgent);

/** Read now and every few seconds: a station starts, stops and updates on its own time (and from a terminal). */
function useLocalStation(): [LocalStationState | null, (s: LocalStationState) => void] {
  const local = window.stillfailDesktop?.local;
  const [state, setState] = useState<LocalStationState | null>(null);
  useEffect(() => {
    if (!local) return;
    let live = true;
    const read = () => void local.state().then((s) => { if (live && s) setState(s); }, () => undefined);
    read();
    const timer = setInterval(read, 3000);
    return () => { live = false; clearInterval(timer); };
  }, [local]);
  return [state, setState];
}

export function LocalStationPage({ back }: { back: string }) {
  const [state, setState] = useLocalStation();
  const act = useAction(async (action: LocalStationAction) => {
    const done = await window.stillfailDesktop!.local!.act(action);
    if (!done) throw new Error(t("web-pages.settings.thisMac.noAnswer"));
    if ("error" in done) throw new Error(done.error);
    return done;
  }, (done) => { if ("station" in done) setState(done.station); });
  const doing = act.busy ? act.args?.[0] : state?.doing;
  const working = doing === "start" || doing === "stop" || doing === "restart" || doing === "update" ? doing : undefined;
  const running = state?.runner !== "none";
  const canStart = !!state && (!!state.service || state.carried);
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.settings.title")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.localStation.title")}<About>{t(PC ? "web-pages.localStation.leadPc" : "web-pages.localStation.lead", { name: NAME })}</About></h1></div></header>
      {state && (
        <div className={cardsCss.card}>
          <div className={cardsCss.cardHead}>
            <StatusDot state={working ? "busy" : running ? "online" : "offline"} label={running ? t("web-pages.localStation.running") : t("web-pages.localStation.stopped")} />
            <span className={cardsCss.cardTitle}>
              <span className={css.name}>{state.workspace?.stationName ?? t(PC ? "web-pages.localStation.thisPc" : "web-pages.localStation.thisMac")}</span>
              <span className={cardsCss.state}>{working ? t(`web-pages.localStation.doing.${working}`) : running ? t("web-pages.localStation.running") : t("web-pages.localStation.stopped")}</span>
            </span>
            {!running && !working && canStart && <button type="button" className={versionsCss.action} onClick={() => void act.run("start")}>{t("web-pages.localStation.start")}</button>}
            <span className={cardsCss.menu}>
              <Menu items={[
                running
                  ? { label: t("web-pages.localStation.stop"), icon: Stop, disabled: !!working, onSelect: () => void act.run("stop") }
                  : { label: t("web-pages.localStation.start"), icon: Play, disabled: !!working || !canStart, onSelect: () => void act.run("start") },
                ...(running && state.runner !== "other" ? [{ label: t("web-pages.localStation.restart"), icon: Refresh, disabled: !!working, onSelect: () => void act.run("restart") }] : []),
                "separator",
                { label: t("web-pages.localStation.openLog"), icon: FileText, onSelect: () => void act.run("log") },
                { label: t(PC ? "web-pages.localStation.openFolderPc" : "web-pages.localStation.openFolder"), icon: Folder, onSelect: () => void act.run("folder") },
              ]} />
            </span>
          </div>
          <div className={cardsCss.cardFoot}>
            <span>{runBy(state)}</span>
            {state.version && <span>{state.version}</span>}
            <span>{place(state)}</span>
            <span className={cardsCss.mono}>{state.data}</span>
          </div>
          {state.outdated && (
            <div className={cardsCss.cardVersions}>
              <div className={versionsCss.summary}>
                <span className={versionsCss.summaryText}>
                  <span>{t("web-pages.localStation.newer", { version: state.version ?? "?", latest: state.carriedVersion ?? "" })}</span>
                </span>
                <span className={versionsCss.summaryAction}>
                  <button type="button" className={versionsCss.action} disabled={!!working} onClick={() => void act.run("update")}>{working === "update" ? t("web-main.versions.updating") : t("web-main.versions.update")}</button>
                </span>
              </div>
            </div>
          )}
          {act.error && <div className={cardsCss.warn}><span data-level="red" role="alert">{act.error.message}</span></div>}
        </div>
      )}
    </div>
  );
}

/** Who runs it: the app, the installed service (and which kind), or a process started by hand. */
function runBy(state: LocalStationState): string {
  const service = state.service && t(`web-pages.localStation.service.${state.service.kind}`);
  if (state.runner === "app") return t("web-pages.localStation.byApp", { name: NAME });
  if (state.runner === "service") return service!;
  if (state.runner === "other") return t("web-pages.localStation.byHand");
  return service ?? t("web-pages.localStation.byApp", { name: NAME });
}

/** The workspace its data is in, only said. */
function place(state: LocalStationState): string {
  const w = state.workspace;
  if (!w) return t("web-pages.localStation.noWorkspace");
  return t(w.removed ? "web-pages.localStation.removed" : "web-pages.localStation.inWorkspace", { workspace: w.name ?? w.id });
}
