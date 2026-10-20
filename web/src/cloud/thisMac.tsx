// This machine's station, as the desktop app says it: where the station it carries stands (station.state: the
// workspace it is in, those it joined beside it, its key) and who runs it (local.state: the app, a service, nobody).
// Read by every part that offers something about it, from one reading every few seconds while any is shown:
// 添加这台 Mac where a station is added (the first station's page, the 添加 station dialog), and 启动 on this
// machine's own station (its row in the sidebar says it is stopped, its page starts it). Nothing in a browser.
import { useSyncExternalStore } from "react";
import { Monitor } from "@stillfail/ui/icons.tsx";
import { useToast } from "@stillfail/ui/toast.tsx";
import type { StationView } from "../api.ts";
import type { CarriedStation, LocalStationState } from "../core/client.ts";
import { Button } from "../ui.tsx";
import { t } from "../i18n.ts";
import { useAction } from "./api.ts";
import type { Account } from "./accounts.ts";

interface Here {
  station: CarriedStation | null;
  local: LocalStationState | null;
}

const desktop = () => (typeof window !== "undefined" ? window.stillfailDesktop : undefined);
/** The desktop app on Windows: a PC, not a Mac. */
export const PC = typeof navigator !== "undefined" && /Windows/.test(navigator.userAgent);

let here: Here = { station: null, local: null };
const listeners = new Set<() => void>();
let timer: ReturnType<typeof setInterval> | null = null;

function set(next: Partial<Here>): void {
  here = { ...here, ...next };
  for (const f of listeners) f();
}

function read(): void {
  const app = desktop();
  void app?.station?.state().then((s) => set({ station: s }), () => undefined);
  void app?.local?.state().then((s) => { if (s) set({ local: s }); }, () => undefined);
}

// Read again every few seconds: a station removed from its workspace marks itself so only once the cloud has told it,
// and one starts and stops on its own time.
function subscribe(f: () => void): () => void {
  listeners.add(f);
  if (!timer && desktop()?.station) {
    read();
    timer = setInterval(read, 3000);
  }
  return () => {
    listeners.delete(f);
    if (listeners.size === 0 && timer) {
      clearInterval(timer);
      timer = null;
    }
  };
}

function useHere(): Here {
  return useSyncExternalStore(subscribe, () => here, () => here);
}

/** Whether a station in a workspace joins `workspace` beside it: not one it is in, and the app says which it joined. */
const joinsMore = (s: CarriedStation, workspace: string) =>
  s.joined !== undefined && s.workspace !== workspace && !s.joined.includes(workspace);

/** Nobody runs it, and something here can start it (the app's own, or a service installed on its own). */
const stopped = (local: LocalStationState | null) => local?.runner === "none" && (!!local.service || local.carried);

async function start(): Promise<LocalStationState | null> {
  const done = await desktop()!.local!.act("start");
  if (!done) throw new Error(t("web-pages.settings.thisMac.noAnswer"));
  if ("error" in done) throw new Error(done.error);
  return "station" in done ? done.station : null;
}

/** What starting it said of it, or a new reading when it said nothing. */
function started(local: LocalStationState | null): void {
  if (local) set({ local });
  else read();
}

/**
 * 添加这台 Mac: the station the app carries joined to `workspace` at a click, while it is in none (never joined, or
 * removed from its workspace: the app joins a removed one again only when asked), or in another one, which it stays
 * in (docs/multi-workspace.md; an app that says which it joined); started too when nobody runs it. `offered` false in
 * a browser, an app from before it, or where it is in `workspace` already.
 */
export function useJoinThisMac(account: Account, workspace: string) {
  const { station, local } = useHere();
  const toast = useToast();
  const join = useAction(async () => {
    const done = await desktop()!.station!.join(account.sub, workspace);
    if (!done) throw new Error(t("web-pages.settings.thisMac.noAnswer"));
    if ("error" in done) throw new Error(done.error);
    set({ station: done.station });
    if (stopped(here.local)) started(await start());
    return done.station;
  }, () => toast(t(PC ? "web-pages.settings.thisPc.joined" : "web-pages.settings.thisMac.joined")));
  const offered = !!desktop()?.station && !!station?.carried && (station.state !== "running" || joinsMore(station, workspace));
  return { offered, join, busy: join.busy || local?.doing === "start" };
}

/** 添加这台 Mac as a button of its own (the first station's page), where it is offered. */
export function JoinThisMac({ account, workspace, className }: { account: Account; workspace: string; className?: string }) {
  const { offered, join, busy } = useJoinThisMac(account, workspace);
  if (!offered) return null;
  return <Button icon={Monitor} className={className} busy={busy} onClick={() => join.run()}>{t(PC ? "web-pages.settings.thisPc.add" : "web-pages.settings.thisMac.add")}</Button>;
}

/**
 * `s` when it is this machine's station and nobody runs it: said as stopped at once, without waiting for the cloud to
 * see it gone; `start` starts it (the app's own, or its service).
 */
export function useStoppedHere(s: StationView) {
  const { station, local } = useHere();
  const toast = useToast();
  const run = useAction(async () => started(await start()), () => toast(t("web-pages.stations.page.started")));
  const key = station?.station;
  const mine = !!key && (s.id === key || s.station.endsWith(`/${key}`));
  return { stopped: mine && stopped(local), start: run, starting: run.busy || local?.doing === "start" };
}
