// The settings' 本机 Station page, in the desktop app: this machine's station whoever runs it (the app, a service
// installed on its own, a process started by hand), where it stands, and starting, stopping, restarting it, an
// installed one behind the app's release brought up to it in place (apps/desktop/src/main.ts, station:local). Which
// workspace it is in is only said: joining one is the workspace's station settings' (「添加这台 Mac」).
import { useEffect, useState } from "react";
import { useAction } from "../action.ts";
import type { LocalStationAction, LocalStationState } from "../core/client.ts";
import { Folder, FileText, Play, Refresh, Stop } from "../icons.tsx";
import { About, Button, MobileBack, Pill, Section, StatusDot } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as additionsCss from "../styles/additions.css.ts";
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
  const button = (action: LocalStationAction, label: string, icon: typeof Play, primary = false) => (
    <Button variant={primary ? "primary" : "secondary"} icon={icon} busy={doing === action} disabled={!!doing && doing !== action} onClick={() => void act.run(action)}>{label}</Button>
  );
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow}`}>
      <MobileBack to={back} label={t("web-pages.settings.title")} />
      <header className={pagesCss.pageHead}><div><h1>{t("web-pages.localStation.title")}<About>{t(PC ? "web-pages.localStation.leadPc" : "web-pages.localStation.lead", { name: NAME })}</About></h1></div></header>
      {state && (
        <>
          {state.outdated && (
            <div className={`${additionsCss.callout} ${css.outdated}`} data-tone="amber">
              <span>{t("web-pages.localStation.outdated", { version: state.version ?? "?", latest: state.carriedVersion ?? "" })}</span>
              {button("update", t("web-pages.localStation.update", { version: state.carriedVersion ?? "" }), Refresh, true)}
            </div>
          )}
          <Section title={t("web-pages.localStation.state")} actions={<>
            {state.runner === "none"
              ? (state.service || state.carried) && button("start", t("web-pages.localStation.start"), Play)
              : button("stop", t("web-pages.localStation.stop"), Stop)}
            {state.runner !== "none" && state.runner !== "other" && button("restart", t("web-pages.localStation.restart"), Refresh)}
          </>}>
            <div className={css.card}>
              <div className={css.head}>
                <StatusDot state={state.runner === "none" ? "offline" : "online"} />
                <span className={css.status}>{state.runner === "none" ? t("web-pages.localStation.stopped") : t("web-pages.localStation.running")}</span>
                {state.version && <span className={css.version}>{state.version}</span>}
                {state.outdated && <Pill tone="amber">{t("web-pages.localStation.behind")}</Pill>}
              </div>
              <dl className={css.facts}>
                <dt>{t("web-pages.localStation.runBy")}</dt>
                <dd>{runBy(state)}</dd>
                <dt>Workspace</dt>
                <dd>{!state.workspace ? t("web-pages.localStation.noWorkspace")
                  : state.workspace.removed ? t("web-pages.localStation.removed", { workspace: state.workspace.name ?? state.workspace.id })
                  : t("web-pages.localStation.inWorkspace", { workspace: state.workspace.name ?? state.workspace.id, station: state.workspace.stationName ?? "" })}</dd>
                <dt>{t("web-pages.localStation.data")}</dt>
                <dd className={css.path}>{state.data}</dd>
              </dl>
              <div className={css.links}>
                <Button variant="ghost" icon={FileText} onClick={() => void act.run("log")}>{t("web-pages.localStation.openLog")}</Button>
                <Button variant="ghost" icon={Folder} onClick={() => void act.run("folder")}>{t(PC ? "web-pages.localStation.openFolderPc" : "web-pages.localStation.openFolder")}</Button>
              </div>
            </div>
          </Section>
        </>
      )}
    </div>
  );
}

/** Who runs it: the app, the installed service (and which), or a process started by hand. */
function runBy(state: LocalStationState): string {
  const service = state.service && t(`web-pages.localStation.service.${state.service.kind}`, { name: state.service.name });
  if (state.runner === "app") return t("web-pages.localStation.byApp", { name: NAME });
  if (state.runner === "service") return service!;
  if (state.runner === "other") return t("web-pages.localStation.byHand");
  return service ?? (state.carried ? t("web-pages.localStation.byApp", { name: NAME }) : t("web-pages.localStation.nothing"));
}

