// The files' page on a wide screen (docs/drive.md "The files' page"), as Finder's window: a row of tabs, each a folder of
// a station of the workspace (drive/tabs.ts), the one shown below; a tab split in two shows two folders side by side,
// of one station or two, to drag from one to the other. The side in front (its bar underlined) is what the page's
// address says and what the keys work on; a press in the other one puts it in front. Each side is a folder's page as
// before (Drive.tsx `FolderView`), under its own station.
import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { useStations } from "../api.ts";
import { useGo } from "../go.ts";
import { StationContext, useStationList, type Station } from "../station.tsx";
import { IconButton } from "../ui.tsx";
import { Close, Plus, ViewColumns } from "@stillfail/ui/icons.tsx";
import { useDrive } from "../drive/useDrive.ts";
import { nameOf, rootLabel } from "../drive/model.ts";
import type { StationView } from "../core/shapes.ts";
import { arrive, besides, closed, frontOf, fronted, opened, paneUrl, shown, split, tabTitle, useFilesTabs, type FilesTabs, type Pane } from "../drive/tabs.ts";
import { GoTo } from "./FilesGo.tsx";
import { FolderView } from "./Drive.tsx";
import { TransferAsk, TransfersButton } from "./Transfers.tsx";
import * as css from "./Files.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import * as driveCss from "./Drive.css.ts";
import { t } from "../i18n.ts";

/** A pane's folder (its last part; a root pinned by its name, the home as 主目录) and its station's name. */
export function paneParts(p: Pane, views: readonly StationView[] | undefined): { folder: string; station: string } {
  const v = views?.find((s) => s.station === p.station);
  const drive = v?.overview?.drive;
  return { folder: p.path ? nameOf(p.path) : drive?.home === p.root ? t("web-pages.drive.home") : rootLabel(drive?.roots, p.root), station: v?.name ?? "" };
}

/** A pane's name in a line: its station › its folder. */
export function paneName(p: Pane, views: readonly StationView[] | undefined): string {
  const { folder, station } = paneParts(p, views);
  return `${station} › ${folder}`;
}

/** What a folder's page asks of the files' page around it: a folder opened in a new tab, or on the other side. */
export interface FilesActions { open: (p: Pane, where: "tab" | "side") => void; goTo: () => void }
const Actions = createContext<FilesActions | null>(null);
/** The files' page's own, where there is one (none in a chat's 文件 tab). */
export const useFilesActions = () => useContext(Actions);

/**
 * The tabs and what the one shown shows, `here` (the page's address) in front. `scope`: the workspace.
 */
export function FilesShell({ scope, here }: { scope: string; here: Pane }) {
  const [kept, keep] = useFilesTabs(scope);
  const go = useGo();
  const views = useStations(scope).value;
  const stations = useStationList(views, scope) ?? [];
  // The address moved (a link, the sidebar, history): the side in front follows it.
  const tabs = useMemo(() => arrive(kept, here), [kept, here.station, here.root, here.path]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (JSON.stringify(tabs) !== JSON.stringify(kept)) keep(tabs);
  }); // eslint-disable-line react-hooks/exhaustive-deps
  const name = (p: Pane) => paneName(p, views);
  // Another tab or side brought in front: the address says it.
  const show = (next: FilesTabs) => {
    keep(next);
    const front = frontOf(next);
    go(paneUrl(front), { replace: true });
  };
  const tab = tabs.tabs.find((x) => x.id === tabs.current) ?? tabs.tabs[0]!;
  const [going, setGoing] = useState(false);
  const actions: FilesActions = { open: (p, where) => show(where === "tab" ? opened(tabs, p) : besides(tabs, p)), goTo: () => setGoing(true) };
  const splitAt = tab.panes.length === 2;
  // ⌘T a new tab where the front is (⌘W stays the window's: the desktop app's menu closes it), ⌃Tab / ⌘⇧] and ⌘⇧[ go
  // along them, ⌘⌥D splits.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const field = e.target instanceof HTMLElement && (e.target.closest("input, textarea, [contenteditable=true], [role=dialog]") !== null);
      if (field || e.defaultPrevented) return;
      const mod = e.metaKey || e.ctrlKey;
      const at = tabs.tabs.findIndex((x) => x.id === tabs.current);
      const along = (step: number) => show(shown(tabs, tabs.tabs[(at + step + tabs.tabs.length) % tabs.tabs.length]!.id));
      if (mod && !e.shiftKey && !e.altKey && e.key.toLowerCase() === "t") { e.preventDefault(); show(opened(tabs, frontOf(tabs))); }
      else if ((e.ctrlKey && e.key === "Tab") || (mod && e.shiftKey && (e.code === "BracketRight" || e.code === "BracketLeft"))) {
        e.preventDefault();
        along(e.code === "BracketLeft" || (e.key === "Tab" && e.shiftKey) ? -1 : 1);
      } else if (mod && e.altKey && e.code === "KeyD") { e.preventDefault(); show(split(tabs)); }
      // ⌘⇧G: a folder by its path, as Finder's 前往文件夹.
      else if (mod && e.shiftKey && e.code === "KeyG") { e.preventDefault(); setGoing(true); }
    };
    addEventListener("keydown", onKey);
    return () => removeEventListener("keydown", onKey);
  });
  return (
    <Actions.Provider value={actions}>
    <div className={css.shell}>
      {/* The tabs as Safari's compact ones: one groove, each tab an equal share of it, the one shown raised; its folder
          first, its station after it, small. One tab alone has none (as Finder's window): only the bar's buttons. */}
      <div className={css.bar}>
        {tabs.tabs.length > 1 ? (
          <div className={css.tabs} role="tablist" aria-label={t("web-pages.files.tabs")}>
            {tabs.tabs.map((x) => (
              <div key={x.id} className={css.tab} data-on={x.id === tabs.current || undefined} role="tab" aria-selected={x.id === tabs.current} title={tabTitle(x, name)}>
                <button type="button" className={css.tabClose} aria-label={t("web-pages.files.closeTab")} onClick={() => show(closed(tabs, x.id))}><Close size={10} strokeWidth={2.4} /></button>
                <button type="button" className={css.tabName} onClick={() => show(shown(tabs, x.id))}>
                  {x.panes.map((p, i) => {
                    const parts = paneParts(p, views);
                    return (
                      <span key={i} className={css.tabPart}>
                        {i > 0 && <span className={css.tabSplit} aria-hidden="true" />}
                        <StationDot station={p.station} stations={stations} />
                        <span className={css.tabFolder}>{parts.folder}</span>
                        <span className={css.tabStation}>{parts.station}</span>
                      </span>
                    );
                  })}
                </button>
              </div>
            ))}
          </div>
        ) : <div className={css.tabsNone} />}
        <div className={css.barEnd}>
          <TransfersButton scope={scope} />
          <span className={css.toggle} data-on={splitAt || undefined}><IconButton label={t(splitAt ? "web-pages.files.unsplit" : "web-pages.files.split")} icon={ViewColumns} onClick={() => show(split(tabs))} /></span>
          <IconButton label={t("web-pages.files.newTab")} icon={Plus} onClick={() => show(opened(tabs, frontOf(tabs)))} />
        </div>
      </div>
      <div className={css.panes} data-split={splitAt || undefined}>
        {tab.panes.map((p, i) => {
          const front = i === tab.front;
          // The side in front is where the address is: drawn from it, not from what is kept (which follows it).
          const pane = front ? here : p;
          return (
            <PaneFrame key={i} pane={pane} stations={stations} front={front} split={splitAt}
              onFront={() => { if (!front) show(fronted(tabs, i)); }} />
          );
        })}
      </div>
      <TransferAsk />
      {going && <GoTo scope={scope} here={here} onClose={() => setGoing(false)} />}
    </div>
    </Actions.Provider>
  );
}

/** A station's colour on the tabs, by its place among the workspace's (so one station is one colour throughout). */
function StationDot({ station, stations }: { station: string; stations: readonly Station[] }) {
  const at = Math.max(0, stations.findIndex((s) => s.address === station));
  return <span className={css.dot} data-tone={at % 6} aria-hidden="true" />;
}

/** One side: a folder under its station, a press in it bringing it in front. */
function PaneFrame({ pane, stations, front, split: two, onFront }: { pane: Pane; stations: readonly Station[]; front: boolean; split: boolean; onFront: () => void }) {
  const station = stations.find((s) => s.address === pane.station);
  return (
    <section className={`${pagesCss.page} ${driveCss.page} ${css.pane}`} data-front={(two && front) || undefined}
      onPointerDownCapture={onFront} onFocusCapture={onFront} aria-current={front || undefined}>
      {station ? (
        <StationContext.Provider value={station}>
          <PaneFolder pane={pane} front={front} />
        </StationContext.Provider>
      ) : <Missing />}
    </section>
  );
}

/** A side's folder as its station's drive has it (`root` a folder pinned, or any for a member who browses everywhere). */
function PaneFolder({ pane, front }: { pane: Pane; front: boolean }) {
  const d = useDrive(pane.station);
  return <FolderView d={d} root={pane.root} path={pane.path} front={front} />;
}

function Missing(): ReactNode {
  return <p className={css.missing}>{t("web-pages.workspace.noSuchStation")}</p>;
}
