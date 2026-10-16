// A chat's 文件 tab (ChatPage.tsx's side panel): the files of the workspace's stations, beside the chat, to put into what
// is being written. It starts at the chat's station's home for a member who browses every folder, else at its pinned
// folders; the way up is a trail of folders over the list, the first of them the places (each station's home and the
// folders pinned on it). A file or folder is added to the message from its … or dragged onto the chat, named by its
// path on its station until switched to a file there; its path is copied from its … (or a right click), or dragged
// anywhere that takes text. A folder is entered, or pinned. Images, PDFs and code open in the chat's preview over the
// page; what reads or plays opens on the files' page.
import { useMemo, useState } from "react";
import { stationBase, useStation } from "../station.tsx";
import { useStations } from "../api.ts";
import { useGo } from "../go.ts";
import { useAct, useToast } from "../toast.tsx";
import { offerToDraft } from "../draft.ts";
import type { DriveEntry, StationView } from "../core/shapes.ts";
import { Button, IconButton, ICON, type MenuItem } from "../ui.tsx";
import { ChevronRight, Copy, Download, Folder, Pin, Refresh, Retry, Send, Server } from "../icons.tsx";
import { download, joinPath, openerOf, refresh, useFolder, type At } from "../drive/model.ts";
import { absoluteOf, drive, drivePath, folderName, rootTrouble, trailOf, useDrive } from "../drive/useDrive.ts";
import { draggedOf, droppedFrom } from "../drive/drag.ts";
import { DrivePreview } from "../mobile/Drive.tsx";
import { DriveRow } from "./Drive.tsx";
import * as shellCss from "../styles/shell.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as driveCss from "./Drive.css.ts";
import * as css from "./DriveTab.css.ts";
import { t } from "../i18n.ts";

/** Where the tab is: a folder of a station (a root and a path under it), or the places (null). */
type Place = { station: string; root: string; path: string } | null;

export function DriveTab({ chat }: {
  /** The chat's key (its draft's): what is added goes into its composer. */
  chat: string;
}) {
  const here = useStation();
  const d = useDrive(here.address);
  const go = useGo();
  const act = useAct();
  const [asked, setAsked] = useState<Place | undefined>(undefined);
  // Where nothing was chosen yet: the chat's station's home (every folder browsed), or its one folder pinned.
  const start: Place = d.anywhere && d.home ? { station: here.address, root: d.home, path: "" } : d.roots.length === 1 ? { station: here.address, root: d.roots[0]!.path, path: "" } : null;
  const place = asked === undefined ? start : asked;
  const [preview, setPreview] = useState<{ at: At; entries: readonly DriveEntry[]; entry: DriveEntry } | null>(null);
  if (asked === undefined && d.loading) return <p className={`${shellCss.muted} ${css.note}`}>{d.error ?? t("web-pages.drive.reading")}</p>;
  return (
    <div className={css.tab}>
      {place === null
        ? <Places scope={here.address.split("/")[0] ?? ""} onGo={(station, root) => setAsked({ station, root, path: "" })} />
        : <FolderList key={`${place.station}\n${place.root}\n${place.path}`} station={place.station} root={place.root} path={place.path} chat={chat}
          onGo={(root, path) => setAsked({ station: place.station, root, path })} onPlaces={() => setAsked(null)}
          onOpen={(at, entries, entry) => {
            const full = joinPath(at.path, entry.name);
            switch (openerOf(entry.kind)) {
              case "folder": return setAsked({ station: at.station, root: at.root, path: full });
              case "read": return go(drivePath(stationBase(at.station), at.root, full, "read"));
              case "play": return go(drivePath(stationBase(at.station), at.root, full, "play"));
              case "preview": return setPreview({ at, entries, entry });
              default: return act(download({ ...at, path: full }, entry), t("web-pages.drive.downloadWhat"));
            }
          }} />}
      {preview && <DrivePreview at={preview.at} entries={preview.entries} entry={preview.entry} onClose={() => setPreview(null)} />}
    </div>
  );
}

/** The places: under each station's name, its home (for a member who browses every folder), then its folders pinned. */
function Places({ scope, onGo }: { scope: string; onGo: (station: string, root: string) => void }) {
  const stations = (useStations(scope).value ?? []).filter((s) => s.overview?.drive);
  return (
    <div className={`${driveCss.list} ${css.list}`}>
      {stations.length === 0 && <p className={`${shellCss.muted} ${css.note}`}>{t("web-main.rail.filesNone")}</p>}
      {stations.map((s) => <StationPlaces key={s.station} s={s} onGo={(root) => onGo(s.station, root)} />)}
    </div>
  );
}

function StationPlaces({ s, onGo }: { s: StationView; onGo: (root: string) => void }) {
  const drive = s.overview!.drive!;
  return (
    <>
      <div className={css.group}><span className={driveCss.name}>{s.name}</span>{!s.online && <span>{t("web-pages.stations.offline")}</span>}</div>
      {drive.anywhere && drive.home && (
        <button type="button" className={driveCss.row} title={drive.home} onClick={() => onGo(drive.home!)}>
          <Server size={18} strokeWidth={1.6} className={driveCss.icon} />
          <span className={driveCss.name}>{t("web-pages.drive.home")}</span>
          <ChevronRight {...ICON} className={shellCss.muted} />
        </button>
      )}
      {drive.roots.map((r) => {
        const trouble = rootTrouble(r);
        return (
          <button key={r.path} type="button" className={driveCss.row} title={r.path} onClick={() => onGo(r.path)}>
            <Folder size={18} strokeWidth={1.6} className={driveCss.icon} />
            <span className={driveCss.text}>
              <span className={driveCss.name}>{r.name}</span>
              {trouble && <span className={driveCss.trouble}><b>{trouble.text}</b></span>}
            </span>
            <ChevronRight {...ICON} className={shellCss.muted} />
          </button>
        );
      })}
    </>
  );
}

function FolderList({ station, root, path, chat, onGo, onPlaces, onOpen }: {
  station: string; root: string; path: string; chat: string;
  onGo: (root: string, path: string) => void; onPlaces: () => void;
  onOpen: (at: At, entries: readonly DriveEntry[], entry: DriveEntry) => void;
}) {
  const d = useDrive(station);
  const name = useStations(station.split("/")[0] ?? "").value?.find((s) => s.station === station)?.name ?? station;
  const act = useAct();
  const toast = useToast();
  const folder = useFolder(station, root, path);
  const at: At = useMemo(() => ({ station, root, path }), [station, root, path]);
  const entries = folder.value?.entries ?? [];
  const here = absoluteOf(root, path);
  const pinned = d.roots.some((r) => r.path === here);
  const [refreshing, setRefreshing] = useState(false);
  const reload = () => {
    if (refreshing) return;
    setRefreshing(true);
    act(refresh(at).finally(() => setRefreshing(false)), t("web-pages.drive.refreshWhat"));
  };
  const copyPath = (abs: string) => void navigator.clipboard.writeText(abs).then(() => toast(t("web-pages.drive.pathCopied")), (e: unknown) => toast(t("web-main.copyFailed", { error: e instanceof Error ? e.message : String(e) })));
  const pin = (abs: string, on: boolean) => act(drive.pin(station, d.roots, abs, on), t("web-pages.drive.rootsWhat"), t(on ? "web-pages.drive.shared" : "web-pages.drive.unpinned", { name: folderName(abs) }));
  // The way here: from the home (or the disk's top) for a member who browses every folder, else from the folder pinned.
  const way = d.anywhere
    ? trailOf(here, d.home, t("web-pages.drive.home"))
    : [{ name: d.roots.find((r) => r.path === root)?.name ?? folderName(root), path: root }, ...path.split("/").filter(Boolean).map((part, i, all) => ({ name: part, path: absoluteOf(root, all.slice(0, i + 1).join("/")) }))];
  const goTo = (abs: string) => {
    const prefix = root.endsWith("/") ? root : `${root}/`;
    if (abs === root) onGo(root, "");
    else if (abs.startsWith(prefix)) onGo(root, abs.slice(prefix.length));
    else onGo(abs, "");
  };
  const items = (e: DriveEntry): MenuItem[] => {
    const abs = absoluteOf(root, joinPath(path, e.name));
    const on = d.roots.some((r) => r.path === abs);
    return [
      { label: t("web-pages.drive.sendToChat"), icon: Send, onSelect: () => offerToDraft(chat, { files: [], quotes: [], dropped: [droppedFrom(draggedOf(at, e, name))] }) },
      { label: t("web-pages.drive.copyPath"), icon: Copy, onSelect: () => copyPath(abs) },
      ...(e.dir ? [] : [{ label: t("web-pages.drive.download"), icon: Download, onSelect: () => act(download({ ...at, path: joinPath(path, e.name) }, e), t("web-pages.drive.downloadWhat")) }]),
      ...(e.dir && d.anywhere ? [{ label: t(on ? "web-pages.drive.unpin" : "web-pages.drive.pin"), icon: Pin, onSelect: () => pin(abs, !on) }] : []),
    ];
  };
  return (
    <>
      <div className={css.head}>
        <span className={css.trail} ref={(el) => { if (el) el.scrollLeft = el.scrollWidth; }}>
          <button type="button" onClick={onPlaces}>{name}</button>
          {way.map((c, i) => (
            <span key={c.path} className={css.step}>
              <ChevronRight size={12} className={shellCss.muted} />
              <button type="button" data-last={i === way.length - 1 || undefined} title={c.path} onClick={() => goTo(c.path)}>{c.name}</button>
            </span>
          ))}
        </span>
        <span className={driveCss.actions}>
          {d.anywhere && <span className={driveCss.pin} data-on={pinned || undefined}><IconButton label={t(pinned ? "web-pages.drive.unpin" : "web-pages.drive.pin")} icon={Pin} onClick={() => pin(here, !pinned)} /></span>}
          <IconButton label={t("web-pages.drive.copyPath")} icon={Copy} onClick={() => copyPath(here)} />
          <span className={driveCss.spin} data-on={refreshing || undefined}><IconButton label={t("web-pages.drive.refresh")} icon={Refresh} onClick={reload} /></span>
        </span>
      </div>
      <div className={`${driveCss.list} ${css.list}`}>
        {folder.error ? (
          <div className={driveCss.problem}><p className={controlsCss.fieldError}>{folder.error.message}</p><Button variant="ghost" icon={Retry} onClick={reload}>{t("web-pages.drive.retry")}</Button></div>
        ) : !folder.value ? <p className={`${shellCss.muted} ${css.note}`}>{t("web-pages.drive.reading")}</p>
          : entries.length === 0 ? <p className={`${shellCss.muted} ${css.note}`}>{t("web-pages.drive.emptyFolder")}</p>
          : entries.map((e) => <DriveRow key={e.name} at={at} entry={e} items={items(e)} compact onOpen={() => onOpen(at, entries, e)} />)}
      </div>
    </>
  );
}
