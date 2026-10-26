// A station's drive on a wide screen (docs/drive.md), at `/w/<ws>/s/<station>/files` (opened from the rail's 文件 and
// its sidebar of the stations' homes and pinned folders, the station's card in settings, the card over its name in a
// chat, or ⌘K), as wide as the page: a folder's entries in a list (its mark, name, size, time), the path above as a
// trail back (up to the top of the disk, for a member who browses every folder), the folder pinned to the sidebar or
// not. With a mouse: a click opens, the row's … (on hover) or a right click gives what can be done to it (its path
// copied among them), a row dragged out carries the file (into a chat's composer) and its path, files dropped on the
// list go up into the folder shown, ⌘/Ctrl+U puts files up.
// The reader and the player are pages of their own (`files/read`, `files/play`); images, PDFs and code open in the
// chat's preview over the page. The phone's pages are ../mobile/Drive.tsx, with the same parts under them.
import { useEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { Navigate, useLocation, useSearchParams } from "react-router";
import { ContextMenu } from "radix-ui";
import { scopeOf, stationBase, useStation } from "../station.tsx";
import { FilesShell } from "./Files.tsx";
import { useStations } from "../api.ts";
import { useWorkspace } from "../cloud/api.ts";
import { useGo } from "../go.ts";
import { useDoing } from "../doing.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import type { DriveArrangement, DriveEntry, DriveRoot, DriveSortBy, StationView } from "../core/shapes.ts";
import { useTopicSelect } from "../core/react.ts";
import { CoreError } from "../core/client.ts";
import { Button, Confirm, Dialog, ICON, IconButton, Menu, Tip, type MenuItem, Spinner, Waiting, WaitLine } from "../ui.tsx";
import { Check, ChevronLeft, ChevronRight, Close, Copy, Disk, Server, Download, Edit, Folder, FolderPlus, Move, PanelClose, PanelOpen, Pin, Plus, Refresh, Retry, Search, Star, Trash, Upload } from "@stillfail/ui/icons.tsx";
import { KindIcon } from "../drive/KindIcon.tsx";
import { Reader } from "@stillfail/ui/viewer/Reader.tsx";
import { Player } from "@stillfail/ui/viewer/Player.tsx";
import { cancel, download, downloadZip, joinPath, nameOf, parentOf, refresh, retry, rootLabel, settle, sizeOf, upload, useFolder, useUploads, type At, type Upload as Up } from "../drive/model.ts";
import { useDriveFile } from "../drive/viewerFile.ts";
import { absoluteOf, childOf, drive, drivePath, filtered, folderName, rootTrouble, trailOf, useDrive, type DriveState, type PickFolder } from "../drive/useDrive.ts";
import { carriesDrive, draggedNow, draggedOf, droppedOf, endDrag, startDrag } from "../drive/drag.ts";
import { keepFilesPage, keepOpened, lastFilesPage, useKeptScroll } from "../drive/kept.ts";
import { dropInto, effectOf, rowKey, takes, useBrowse } from "../drive/browse.ts";
import { transfer } from "../drive/transfer.ts";
import { useShortcut } from "../keymap.ts";
import { useFavorites } from "../drive/favorites.ts";
import { useFilesActions } from "./Files.tsx";
import { StationSwitch } from "./FilesGo.tsx";
import { CopyTo } from "./Transfers.tsx";
import { DrivePane, type Previewed } from "./DrivePane.tsx";
import { setPrefs, usePrefs } from "../prefs.ts";
import { paneUrl, useFilesTabs } from "../drive/tabs.ts";
import type { Dragged } from "../drive/drag.ts";
import { ColumnsView, modsOf, TreeView, useDriveView, useDropZone, ViewSwitch, type DropTarget, type RowOf, type RowProps, type Shown } from "./DriveViews.tsx";
import { useToast } from "@stillfail/ui/toast.tsx";
import { DrivePreview, FilterField, useFolders } from "../mobile/Drive.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as css from "./Drive.css.ts";
import { t } from "../i18n.ts";
import { StationMark } from "../StationMark.tsx";
import { StationNamedAt } from "../StationNamed.tsx";
import { sampleDriveEntries, sampleDriveRoots } from "../samples.ts";

export function DrivePage() {
  const station = useStation();
  const [q] = useSearchParams();
  const d = useDrive(station.address);
  const asked = q.get("root");
  const path = q.get("path") ?? "";
  const only = d.roots.length === 1 && d.roots[0]!.state === "ok" ? d.roots[0]!.path : null;
  // Where nothing is asked: the one folder pinned, else the home for a member who browses every folder.
  const root = asked ?? only ?? (d.anywhere ? d.home : null);
  // A folder: among the files' page's tabs (Files.tsx), in front.
  if (!d.loading && d.offered && root !== null) return <FilesShell scope={scopeOf(station.address)} here={{ station: station.address, root, path }} />;
  return (
    <div className={`${pagesCss.page} ${css.page}`}>
      <Roots d={d} />
    </div>
  );
}

/** 文件 in the rail (`/w/<ws>/files`): the folder in front of the tabs as they were left (else the folder last open on
 * this page), else the first folder pinned on any station (the sidebar lists them all), else the first station's home;
 * none, says so. */
export function DriveHome({ scope }: { scope: string }) {
  const stations = useStations(scope).value;
  const add = useAddFolder(scope);
  const [kept] = useFilesTabs(scope);
  const front = kept?.front ?? null;
  const first = (front ? paneUrl(front) : null) ?? lastFilesPage(scope)
    ?? (stations ?? []).flatMap((s) => (s.overview?.drive?.roots ?? []).map((r) => drivePath(stationBase(s.station), r.path)))[0]
    ?? (stations ?? []).flatMap((s) => (s.overview?.drive?.anywhere && s.overview.drive.home ? [drivePath(stationBase(s.station), s.overview.drive.home)] : []))[0];
  // The tabs not known yet: where they were left is waited for.
  if (kept === undefined) return null;
  if (first) return <Navigate to={first} replace />;
  return (
    <div className={`${pagesCss.page} ${css.page}`}>
      <header className={pagesCss.pageHead}><div className={css.headText}><h1>{t("web-pages.drive.title")}</h1></div></header>
      {!stations ? <Waiting text={t("common.readingStations")} sample={<RootList roots={SAMPLE_ROOTS} onOpen={() => undefined} />} />
        : <Empty text={t("web-main.rail.filesNone")} action={add.can ? <Button variant="primary" icon={Folder} onClick={add.start}>{t("web-pages.drive.pick")}</Button> : undefined} />}
      {add.dialogs}
    </div>
  );
}

/**
 * Pin 文件夹 where no one station is in view (the files' sidebar, their empty page), for those who may pin (any member
 * who may write; on a station from before, the workspace's owners and admins): the folders of the one station with a
 * drive to pick from, or of the one chosen first when there are several.
 */
export function useAddFolder(scope: string) {
  const role = useWorkspace(scope).value?.role;
  const manager = role === "owner" || role === "admin";
  const stations = (useStations(scope).value ?? []).filter((s) => s.overview?.drive && (manager || s.overview.drive.anywhere));
  const [choosing, setChoosing] = useState(false);
  const [picking, setPicking] = useState<string | null>(null);
  const roots = stations.find((s) => s.station === picking)?.overview?.drive?.roots ?? [];
  const dialogs = <>
    {choosing && (
      <Dialog open onClose={() => setChoosing(false)} title={t("web-pages.drive.addRoot")} description={t("web-pages.drive.whichStation")}>
        <div className={css.rootsList}>
          {stations.map((s) => (
            <button key={s.station} type="button" className={css.pickRow} onClick={() => { setChoosing(false); setPicking(s.station); }}>
              {s.emoji || s.icon ? <StationMark emoji={s.emoji} icon={s.icon} size={18} className={css.icon} /> : <Server size={18} strokeWidth={1.6} className={css.icon} />}
              <span className={css.name}>{s.name}</span>
              {!s.online && <span className={shellCss.muted}>{t("web-pages.stations.offline")}</span>}
            </button>
          ))}
        </div>
      </Dialog>
    )}
    {picking && <PickerDialog station={picking} roots={roots} onClose={() => setPicking(null)} />}
  </>;
  return {
    can: stations.length > 0,
    start: () => { if (stations.length === 1) setPicking(stations[0]!.station); else setChoosing(true); },
    dialogs,
  };
}

/** What can be done about the folders lent, for the workspace's owners and admins (its page's … menu). */
function useManage(d: DriveState) {
  const station = useStation();
  const [roots, setRoots] = useState(false);
  const [picking, setPicking] = useState(false);
  const dialogs = <>
    {roots && <RootsDialog station={station.address} roots={d.roots} onAdd={() => { setRoots(false); setPicking(true); }} onClose={() => setRoots(false)} />}
    {picking && <PickerDialog station={station.address} roots={d.roots} onClose={() => setPicking(false)} />}
  </>;
  return { open: () => setRoots(true), pick: () => setPicking(true), dialogs };
}

function Roots({ d }: { d: DriveState }) {
  const station = useStation();
  const go = useGo();
  const manage = useManage(d);
  return (
    <>
      <header className={pagesCss.pageHead}>
        <div className={css.headText}>
          <span className={css.crumbs}><span><StationNamedAt station={station.address} name={station.name} /></span></span>
          <h1>{t("web-pages.drive.title")}</h1>
        </div>
        {(d.manage || d.anywhere) && d.offered && d.roots.length > 0 && <div className={css.actions}><Menu items={[{ label: t("web-pages.drive.manage"), icon: Folder, onSelect: manage.open }]} /></div>}
      </header>
      {d.loading ? <Waiting error={d.error} sample={<RootList roots={SAMPLE_ROOTS} onOpen={() => undefined} />} />
        : !d.offered ? <Empty text={t("web-pages.drive.oldStation")} />
        : d.roots.length === 0 ? (
          <Empty text={d.manage || d.anywhere ? t("web-pages.drive.noneManage") : t("web-pages.drive.noneMember")}
            action={d.manage || d.anywhere ? <Button variant="primary" icon={Folder} onClick={manage.pick}>{t("web-pages.drive.pick")}</Button> : undefined} />
        ) : <RootList roots={d.roots} onOpen={(r) => go(drivePath(station.base, r.path))} />}
      {manage.dialogs}
    </>
  );
}

/** The folders pinned (`roots`), how many, a row each. */
function RootList({ roots, onOpen }: { roots: DriveRoot[]; onOpen(root: DriveRoot): void }) {
  return (
    <div className={css.list}>
      <p className={css.count}>{t("web-pages.drive.rootsCount", { n: roots.length })}</p>
      {roots.map((r) => <RootRow key={r.path} root={r} onOpen={() => onOpen(r)} />)}
    </div>
  );
}

/** Folders pinned made up, for what the files' pages show while they are read (in their bones). */
const SAMPLE_ROOTS = sampleDriveRoots();

function RootRow({ root, onOpen }: { root: DriveRoot; onOpen: () => void }) {
  const trouble = rootTrouble(root);
  return (
    <button type="button" className={css.row} title={root.path} onClick={onOpen}>
      <Folder size={20} strokeWidth={1.6} className={css.icon} />
      <span className={css.text}>
        <span className={css.name}>{root.name}</span>
        {trouble && <span className={css.trouble}><b>{trouble.text}</b> · {trouble.hint}</span>}
      </span>
      <ChevronRight {...ICON} className={shellCss.muted} />
    </button>
  );
}

/**
 * A folder's page: its trail, its name, what can be done to it, its entries. `front`: the side of the files' page in
 * front (Files.tsx), where the keys go and what the rail's 文件 comes back to.
 */
export function FolderView({ d, root, path, front = true }: { d: DriveState; root: string; path: string; front?: boolean }) {
  const station = useStation();
  const { pathname, search } = useLocation();
  const go = useGo();
  const act = useAct();
  const folder = useFolder(station.address, root, path);
  const uploads = useUploads(station.address, root, path);
  const at: At = useMemo(() => ({ station: station.address, root, path }), [station.address, root, path]);
  const entries = folder.value?.entries ?? [];
  const manage = useManage(d);
  const files = useRef<HTMLInputElement>(null);
  const [refreshing, setRefreshing] = useState(false);
  // What is removed or previewed, with the folder it is in (a tree or columns show more than the one folder).
  // What is asked about before it goes for good (no trash takes it there).
  const [removing, setRemoving] = useState<{ at: At; entry: DriveEntry }[] | null>(null);
  // Deleted: to the machine's trash, as Finder does, nothing asked; where none takes it, asked first, then for good.
  const remove = (items: { at: At; entry: DriveEntry }[]) => {
    if (!d.trash) return setRemoving(items);
    const trashed = Promise.all(items.map((x) => drive.remove(x.at, x.entry).then(() => null, (e: unknown) => (e instanceof CoreError && e.code === "no_trash" ? x : Promise.reject(e)))));
    act(trashed.then((left) => {
      const rest = left.filter((x): x is { at: At; entry: DriveEntry } => x !== null);
      if (rest.length) setRemoving(rest);
      else if (items.length) toast(t("web-pages.drive.trashed", { n: items.length }));
    }), t("web-pages.drive.deleteWhat"));
  };
  const [preview, setPreview] = useState<{ at: At; entries: readonly DriveEntry[]; entry: DriveEntry } | null>(null);
  const [view, setView] = useDriveView("page");
  // The folder kept for the rail's 文件 to come back to.
  useEffect(() => { if (front) keepFilesPage(station.address.split("/")[0] ?? "", pathname + search); }, [front, station.address, pathname, search]);
  // Something dragged over the list (not over one of its folders): what a drop does there.
  const [dragging, setDragging] = useState<false | "copy" | "move" | "upload">(false);
  const stationName = useStationName(station.address);
  const here = absoluteOf(root, path);
  const name = path ? nameOf(path) : d.anywhere && !d.roots.some((r) => r.path === root) ? (here === d.home ? t("web-pages.drive.home") : folderName(here)) : rootLabel(d.roots, root);
  const pinned = d.roots.some((r) => r.path === here);
  const fav = useFavorites(scopeOf(station.address));
  const kept = fav.has({ station: station.address, root, path });
  const keepHere = (on: boolean) => (on ? fav.add({ station: station.address, root, path, name }) : fav.remove({ station: station.address, root, path }));
  const filesPage = useFilesActions();
  const [copying, setCopying] = useState<{ items: Dragged[]; move: boolean } | null>(null);
  const toast = useToast();
  const copyPath = (abs: string) => void navigator.clipboard.writeText(abs).then(() => toast(t("web-pages.drive.pathCopied")), (e: unknown) => toast(t("web-main.copyFailed", { error: e instanceof Error ? e.message : String(e) })));
  const pin = (abs: string, on: boolean) => act(drive.pin(station.address, d.roots, abs, on), t("web-pages.drive.rootsWhat"), t(on ? "web-pages.drive.shared" : "web-pages.drive.unpinned", { name: folderName(abs) }));
  const reload = () => {
    if (refreshing) return;
    setRefreshing(true);
    act(refresh(at).finally(() => setRefreshing(false)), t("web-pages.drive.refreshWhat"));
  };
  // An entry of the folder `in` (the one shown, or one under it a tree or columns show) opened: a folder gone into, a
  // text read, a video played, a picture or code previewed, the rest downloaded.
  const openIn = (in_: At, e: DriveEntry, siblings: readonly DriveEntry[] = [e]) => {
    const full = joinPath(in_.path, e.name);
    keepOpened("page", in_, e.name);
    switch (e.opens) {
      case "folder": return go(drivePath(station.base, root, full));
      case "read": return go(drivePath(station.base, root, full, "read"));
      case "play": return go(drivePath(station.base, root, full, "play"));
      case "preview": return setPreview({ at: in_, entries: siblings, entry: e });
      default: return save(in_, e);
    }
  };
  const save = (in_: At, e: DriveEntry) => act(download({ ...in_, path: joinPath(in_.path, e.name) }, e), t("web-pages.drive.downloadWhat"));
  // A picture or code previewed with those beside it, as shown, to step through.
  const openRow = (in_: At, e: DriveEntry) => openIn(in_, e, in_.path === path ? browse.drawing.arranged(in_, entries) ?? [e] : [e]);
  const browse = useBrowse({
    owner: "page", view, at, write: d.write, act, open: openRow, preview: openRow,
    go: (p, replace) => go(drivePath(station.base, root, p), replace ? { replace: true } : undefined),
    remove,
  });
  const arranged = browse.drawing.arranged(at, entries);
  const shownEntries = arranged ?? [];
  // Back where it was, as each folder was left (the page scrolls, the list in it), once its rows are drawn.
  const list = useKeptScroll<HTMLDivElement>("page", at, view, (folder.value !== undefined && arranged !== undefined) || folder.error !== null, (el) => el.parentElement);
  // The preview beside the list (⌘⇧P): the one file chosen, as the folder it is in has it.
  const [previewing, setPreviewing] = usePreviewShown();
  const chosenIn = useFolder(station.address, previewing && browse.chosen.names.length === 1 ? root : null, browse.chosen.folder).value;
  const chosenEntry = chosenIn?.entries.find((e) => e.name === browse.chosen.names[0]);
  const previewed: Previewed = browse.chosen.names.length > 1 ? { many: browse.chosen.names.length }
    : chosenEntry ? { at: { station: station.address, root, path: browse.chosen.folder }, entry: chosenEntry } : null;
  // What goes into a folder dropped on it: a station's files moved or copied (this one's or another's), the computer's
  // put up.
  const into = (folder: At): DropTarget | undefined => d.write
    ? {
        takes: (dt) => takes(dt, station.address, draggedNow(), d.transfers),
        effect: (dt, mods) => effectOf(dt, station.address, draggedNow(), mods),
        drop: (dt, mods) => {
          if (!carriesDrive(dt)) return act(dropInto(dt, folder, d.anywhere), t("web-pages.drive.uploadWhat"));
          const move = effectOf(dt, station.address, draggedNow(), mods) === "move";
          const named = folder.path ? nameOf(folder.path) : name;
          act(transfer(droppedOf(dt), folder, move, named, d.anywhere), t(move ? "web-pages.drive.moveWhat" : "web-pages.files.copyWhat"));
        },
      }
    : undefined;
  // 复制到… and 移动到… (a member who may write moves): where to, picked in a dialog of every station's folders.
  const copyItems = (all: { at: At; entry: DriveEntry }[]): MenuItem[] => {
    const items = () => all.map((x) => draggedOf(x.at, x.entry, stationName));
    return [
      { label: t("web-pages.files.copyTo"), icon: Copy, onSelect: () => setCopying({ items: items(), move: false }) },
      ...(d.write ? [{ label: t("web-pages.files.moveTo"), icon: Move, onSelect: () => setCopying({ items: items(), move: true }) }] : []),
    ];
  };
  const itemsIn = (in_: At, e: DriveEntry): MenuItem[] => {
    const all = browse.chosenWith(in_, e);
    return all.length > 1 ? manyItems(all) : oneItems(in_, e);
  };
  // What is chosen, several at once.
  const manyItems = (all: { at: At; entry: DriveEntry }[]): MenuItem[] => {
    const files = all.filter((x) => !x.entry.dir);
    return [
      ...(files.length ? [{ label: t("web-pages.drive.downloadMany", { n: files.length }), icon: Download, onSelect: () => { for (const x of files) save(x.at, x.entry); } }] : []),
      { label: t("web-pages.drive.copyPaths"), icon: Copy, onSelect: () => copyPath(all.map((x) => absoluteOf(root, joinPath(x.at.path, x.entry.name))).join("\n")) },
      ...copyItems(all),
      ...(d.write ? [{ label: t(d.trash ? "web-pages.drive.toTrashMany" : "web-pages.drive.deleteMany", { n: all.length }), icon: Trash, danger: true, onSelect: () => remove(all) }] : []),
    ];
  };
  const oneItems = (in_: At, e: DriveEntry): MenuItem[] => [
    { label: t("web-pages.drive.open"), onSelect: () => openIn(in_, e) },
    ...(!e.dir ? [{ label: t("web-pages.drive.download"), icon: Download, onSelect: () => save(in_, e) }]
      : d.zip ? [{ label: t("web-pages.drive.downloadZip"), icon: Download, onSelect: () => act(downloadZip({ ...in_, path: joinPath(in_.path, e.name) }), t("web-pages.drive.downloadWhat")) }]
      : []),
    { label: t("web-pages.drive.copyPath"), icon: Copy, onSelect: () => copyPath(absoluteOf(root, joinPath(in_.path, e.name))) },
    ...(e.dir && filesPage ? [
      { label: t("web-pages.files.openInTab"), onSelect: () => filesPage.open({ station: station.address, root, path: joinPath(in_.path, e.name) }, "tab") },
      { label: t("web-pages.files.openBeside"), onSelect: () => filesPage.open({ station: station.address, root, path: joinPath(in_.path, e.name) }, "side") },
    ] : []),
    ...(e.dir ? [{ label: t("web-pages.files.favoriteIt"), icon: Star, onSelect: () => fav.add({ station: station.address, root, path: joinPath(in_.path, e.name), name: e.name }) }] : []),
    ...copyItems([{ at: in_, entry: e }]),
    ...(e.dir && d.anywhere ? [(() => {
      const abs = absoluteOf(root, joinPath(in_.path, e.name));
      const on = d.roots.some((r) => r.path === abs);
      return { label: t(on ? "web-pages.drive.unpin" : "web-pages.drive.pin"), icon: Pin, onSelect: () => pin(abs, !on) };
    })()] : []),
    ...(d.write ? [
      { label: t("web-pages.drive.rename"), icon: Edit, onSelect: () => browse.startRename(in_, e.name) },
      { label: t(d.trash ? "web-pages.drive.toTrash" : "web-pages.drive.delete"), icon: Trash, danger: true, onSelect: () => remove([{ at: in_, entry: e }]) },
    ] : []),
  ];
  const rowOf: RowOf = (in_, e) => ({
    items: itemsIn(in_, e),
    open: () => openRow(in_, e),
    press: (ev) => browse.press(in_, e, ev),
    menu: () => browse.choose(in_, e.name),
    chosen: browse.isChosen(in_, e.name),
    renaming: browse.renaming === rowKey(in_.path, e.name),
    rename: (to) => browse.rename(in_, e, to),
    dragged: () => browse.chosenWith(in_, e).map((x) => draggedOf(x.at, x.entry, stationName)),
    drop: e.dir ? into({ ...in_, path: joinPath(in_.path, e.name) }) : undefined,
  });
  const shown: Shown = { ...browse.drawing, rowOf, dropOn: into, clear: browse.clear };
  const newFolder = () => act(browse.newFolder(at, entries), t("web-pages.drive.mkdirWhat"));
  const empty = <Empty text={t("web-pages.drive.emptyFolder")} action={d.write ? <Button icon={Upload} onClick={() => files.current?.click()}>{t("web-pages.drive.upload")}</Button> : undefined} />;
  // ⌘⇧P (the keymap's files.preview): the preview beside the list, shown or not, while this folder is in front.
  useShortcut("files.preview", front ? () => setPreviewing(!previewing) : null);
  const newFolderRef = useRef(newFolder);
  newFolderRef.current = newFolder;
  // The keys are the rows' wherever on the page they are pressed (a folder gone into leaves nothing focused), but in a
  // field, a dialog or a menu.
  const keysRef = useRef(browse.onKeyDown);
  keysRef.current = browse.onKeyDown;
  useEffect(() => {
    if (!front) return;
    const onKey = (e: KeyboardEvent) => {
      const at = document.activeElement;
      if (e.defaultPrevented || !(at === document.body || at === null || list.current?.contains(at))) return;
      keysRef.current(e);
    };
    addEventListener("keydown", onKey);
    return () => removeEventListener("keydown", onKey);
  }, [list, front]);
  // A folder gone into (the row pressed gone with the one left): the list keeps the focus, as Finder's window does.
  useEffect(() => {
    if (front && (document.activeElement === document.body || document.activeElement === null)) list.current?.focus({ preventScroll: true });
  }, [path, view, list, front]);
  // ⌘/Ctrl+U puts files up into the folder shown.
  useEffect(() => {
    if (!d.write || !front) return;
    const onKey = (e: KeyboardEvent) => {
      if (!(e.metaKey || e.ctrlKey)) return;
      if (e.key.toLowerCase() === "u") { e.preventDefault(); files.current?.click(); }
      // ⌘⇧N: a new folder, as Finder makes one.
      if (e.shiftKey && e.key.toLowerCase() === "n") { e.preventDefault(); newFolderRef.current(); }
    };
    addEventListener("keydown", onKey);
    return () => removeEventListener("keydown", onKey);
  }, [d.write, front]);
  const trail = path.split("/").filter(Boolean);
  // For a member who browses every folder: the whole way from the home (or the disk's top), each step a folder to go to
  // (those within the root by their path under it, so a pinned folder stays the one marked in the sidebar).
  const way = d.anywhere ? trailOf(here, d.home, t("web-pages.drive.home")) : null;
  const goTo = (abs: string) => {
    const under = abs === root ? "" : abs.startsWith(root.endsWith("/") ? root : `${root}/`) ? abs.slice(root.length).replace(/^\/+/, "") : null;
    go(under !== null ? drivePath(station.base, root, under) : drivePath(station.base, abs));
  };
  // What can be done to the folder: on the files' page in its bar over the tabs, for the side in front (as Finder's
  // toolbar is the window's), else at the head's end.
  const toBar = filesPage?.bar ?? null;
  const actions = (
    <div className={css.actions}>
      <ViewSwitch value={view} onChange={setView} />
      <span className={css.pin} data-on={previewing || undefined}><IconButton label={t(previewing ? "web-pages.files.hidePreview" : "web-pages.files.showPreview")} shortcut="files.preview" icon={previewing ? PanelClose : PanelOpen} onClick={() => setPreviewing(!previewing)} /></span>
      {d.write && <IconButton label={t("web-pages.drive.upload")} icon={Upload} onClick={() => files.current?.click()} />}
      {d.write && <IconButton label={t("web-pages.drive.mkdir")} icon={FolderPlus} onClick={newFolder} />}
      <span className={css.spin} data-on={refreshing || undefined}><IconButton label={t("web-pages.drive.refresh")} icon={Refresh} onClick={reload} /></span>
      <span className={css.pin} data-on={kept || undefined}><IconButton label={t(kept ? "web-pages.files.unfavorite" : "web-pages.files.favorite", { name })} icon={Star} onClick={() => keepHere(!kept)} /></span>
      {d.anywhere && <span className={css.pin} data-on={pinned || undefined}><IconButton label={t(pinned ? "web-pages.drive.unpin" : "web-pages.drive.pin")} icon={Pin} onClick={() => pin(here, !pinned)} /></span>}
      <Menu items={[
        { label: t("web-pages.drive.copyPath"), icon: Copy, onSelect: () => copyPath(here) },
        ...(filesPage ? [{ label: t("web-pages.files.goTo"), icon: Search, onSelect: filesPage.goTo }] : []),
        ...(d.manage || d.anywhere ? [{ label: t("web-pages.drive.manage"), icon: Folder, onSelect: manage.open }] : []),
      ]} />
    </div>
  );
  return (
    <>
      {toBar && front && createPortal(actions, toBar)}
      <header className={pagesCss.pageHead}>
        <div className={css.headText}>
          {/* Its station (another one picked from there), then the way back up: from the home or the disk's top for a
              member who browses every folder, else from the folder lent. */}
          <span className={css.crumbs}>
            <StationSwitch station={station.address} abs={here} />
            {way && way.slice(0, -1).map((c) => (
              <span key={c.path} className={css.crumb}><ChevronRight size={12} /><button type="button" onClick={() => goTo(c.path)}>{c.name}</button></span>
            ))}
            {!way && trail.length > 0 && (
              <>
                <span className={css.crumb}><ChevronRight size={12} /><button type="button" onClick={() => go(drivePath(station.base, root))}>{rootLabel(d.roots, root)}</button></span>
                {trail.slice(0, -1).map((p, i) => (
                  <span key={i} className={css.crumb}><ChevronRight size={12} /><button type="button" onClick={() => go(drivePath(station.base, root, trail.slice(0, i + 1).join("/")))}>{p}</button></span>
                ))}
              </>
            )}
          </span>
          <h1>{name}</h1>
          <p className={css.headMeta}>
            <StationNamedAt station={station.address} name={station.name} />
            {folder.value && <> · {folder.value.countText}{folder.value.truncated ? ` · ${t("web-pages.drive.truncated")}` : ""}</>}
          </p>
        </div>
        {!toBar && actions}
      </header>
      <div className={css.withPane} data-pane={previewing || undefined}>
      <ContextMenu.Root modal={false}>
      <ContextMenu.Trigger asChild>
      <div ref={list} className={css.list} data-dragging={dragging || undefined} data-view={view} tabIndex={-1}
        onKeyUp={(e) => { if (e.key === " ") e.preventDefault(); }}
        onClick={(e) => { if (e.target === e.currentTarget) browse.clear(); }}
        // Dropped where no folder takes it (not on a folder's row or a column): into the folder shown. Unsaid on the way
        // down, said again on the way up: a row or a column that takes the drag stops it on its way up.
        onDragOverCapture={() => setDragging(false)}
        onDropCapture={() => setDragging(false)}
        onDragOver={(e) => {
          const here = into(at);
          if (!here?.takes(e.dataTransfer)) return;
          e.preventDefault();
          const effect = here.effect?.(e.dataTransfer, modsOf(e)) ?? "copy";
          e.dataTransfer.dropEffect = effect;
          setDragging((e.target as Element).closest("[data-drop-into]") ? false : carriesDrive(e.dataTransfer) ? effect : "upload");
        }}
        onDragLeave={(e) => { if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setDragging(false); }}
        onDrop={(e) => { const here = into(at); if (!here?.takes(e.dataTransfer)) return; e.preventDefault(); here.drop(e.dataTransfer, modsOf(e)); }}>
        {/* Columns stay while the folder opened is read (each column says its own reading or trouble), not redrawn whole. */}
        {view === "columns" ? (
          <>
            {uploads.map((u) => <UploadRow key={u.key} u={u} />)}
            <ColumnsView owner="page" at={{ ...at, path: "" }} open={path} shown={shown} empty={uploads.length ? <></> : empty} />
          </>
        ) : folder.error ? (
          <div className={css.problem}><p className={controlsCss.fieldError}>{folder.error.message}</p><Button variant="ghost" icon={Retry} onClick={reload}>{t("web-pages.drive.retry")}</Button></div>
        ) : !folder.value || !arranged ? <Waiting sample={<>
          {view === "list" && <ListHead arrangement={browse.arrangement} onSort={() => undefined} />}
          <DriveSample />
        </>} /> : (
          <>
            {uploads.map((u) => <UploadRow key={u.key} u={u} />)}
            {view === "list" && shownEntries.length > 0 && <ListHead arrangement={browse.arrangement} onSort={(by) => browse.arrangeAs(by === browse.arrangement.by ? { down: !browse.arrangement.down } : { by, down: false })} />}
            {view === "tree" ? <TreeView key={path} at={at} shown={shown} empty={uploads.length ? <></> : empty} />
              : <>
                {shownEntries.length === 0 && uploads.length === 0 && empty}
                {shownEntries.map((e) => <DriveRow key={e.name} at={at} entry={e} row={rowOf(at, e)} />)}
              </>}
          </>
        )}
        {dragging && (
          <div className={css.drop}>
            {dragging === "upload" ? <Upload size={22} /> : <Move size={22} />}
            <span>{dragging === "copy" ? t("web-pages.files.copyHere", { name }) : dragging === "move" ? t("web-pages.files.moveHere", { name }) : t("web-pages.drive.dropHere", { name })}</span>
          </div>
        )}
      </div>
      </ContextMenu.Trigger>
      <MenuContent items={[
        ...(d.write ? [{ label: t("web-pages.drive.mkdir"), icon: FolderPlus, onSelect: newFolder }, { label: t("web-pages.drive.upload"), icon: Upload, onSelect: () => files.current?.click() }] : []),
        ...(["name", "time", "size", "kind"] as const).map((by) => ({ label: t(`web-pages.drive.sortBy.${by}`), ...(browse.arrangement.by === by ? { icon: Check } : {}), onSelect: () => browse.arrangeAs({ by, down: false }) })),
        { label: t(browse.arrangement.hidden ? "web-pages.drive.hideHidden" : "web-pages.drive.showHidden"), onSelect: () => browse.arrangeAs({ hidden: !browse.arrangement.hidden }) },
        { label: t("web-pages.drive.refresh"), icon: Refresh, onSelect: reload },
      ]} />
      </ContextMenu.Root>
      {previewing && (
        <DrivePane shown={previewed} stationName={station.name}
          onOpen={() => { if (previewed && "entry" in previewed) openIn(previewed.at, previewed.entry); }}
          onSave={() => { if (previewed && "entry" in previewed) save(previewed.at, previewed.entry); }}
          onCopyPath={copyPath} />
      )}
      </div>
      <input ref={files} type="file" multiple hidden onChange={(e) => { const list = [...(e.target.files ?? [])]; e.target.value = ""; if (list.length) upload(station.address, root, path, list); }} />
      <Confirm open={removing !== null} onClose={() => setRemoving(null)}
        title={!removing ? "" : removing.length > 1 ? t("web-pages.drive.deleteManyAsk", { n: removing.length }) : t(removing[0]!.entry.dir ? "web-pages.drive.deleteFolderAsk" : "web-pages.drive.deleteAsk", { name: removing[0]!.entry.name })}
        description={removing?.some((r) => r.entry.dir) ? t("web-pages.drive.deleteFolderText") : t("web-pages.drive.deleteText")} action={t("web-pages.drive.delete")}
        onConfirm={() => { const r = removing; setRemoving(null); if (r) act(Promise.all(r.map((x) => drive.remove(x.at, x.entry, true))), t("web-pages.drive.deleteWhat")); }} />
      {preview && <DrivePreview at={preview.at} entries={preview.entries} entry={preview.entry} onClose={() => setPreview(null)} />}
      {copying && <CopyTo items={copying.items} move={copying.move} from={station.address} onClose={() => setCopying(null)} />}
      {manage.dialogs}
    </>
  );
}

/** Whether the preview shows beside a folder's list (the files' page's, a chat's 文件 tab's), on this device (prefs'
 * `driveViews`: `preview`, `tabPreview`: shown). */
export function usePreviewShown(place: "page" | "tab" = "page"): [boolean, (on: boolean) => void] {
  const key = place === "page" ? "preview" : "tabPreview";
  const on = usePrefs((p) => p.driveViews[key] === "shown");
  return [on, (next) => setPrefs({ driveViews: { [key]: next ? "shown" : null } })];
}

/** A station's name, as the workspace's stations list has it (its address while not known). */
export function useStationName(station: string): string {
  return useTopicSelect<StationView[], string>({ topic: "stations", scope: station.split("/")[0] ?? "" }, (s) => s.value?.find((x) => x.station === station)?.name ?? station);
}

/** A folder's rows made up, for what its list shows while it is read (in their bones); `compact` as DriveRow's. */
export function DriveSample({ compact = false }: { compact?: boolean }) {
  return SAMPLE_ENTRIES.map((e) => <DriveRow key={e.name} at={SAMPLE_AT} entry={e} row={SAMPLE_ROW} compact={compact} />);
}
const SAMPLE_ENTRIES = sampleDriveEntries();
const SAMPLE_AT: At = { station: "sample", root: "", path: "" };
const SAMPLE_ROW: RowProps = {
  items: [], open: () => undefined, press: () => undefined, menu: () => undefined, chosen: false, renaming: false, rename: () => undefined, dragged: () => [],
};

/**
 * A row of a folder's list, as the files' page and a chat's 文件 tab draw it: its mark, name, size and time (`compact`:
 * the size alone), the … on hover and the same on a right click. Pressed it is chosen, a double click opens it, its name
 * is changed in place; dragged out it carries the file (what is chosen with it) and its path, and a folder takes what
 * is dropped on it. In a tree (`depth`), in by its depth, a folder with its disclosure (`expanded`, `onToggle`); in
 * columns (`column`), the folder open (`along`) marked as the way to the next column, with › at its end.
 */
export function DriveRow({ at, entry, row, compact = false, depth, expanded, onToggle, column = false, along = false }: {
  at: At; entry: DriveEntry; row: RowProps; compact?: boolean;
  depth?: number | undefined; expanded?: boolean | undefined; onToggle?: (() => void) | undefined; column?: boolean; along?: boolean;
}) {
  // In a column only the folder open in the next one has ›, not every folder: their marks already say they open.
  const next = column && entry.dir && along;
  const full = joinPath(at.path, entry.name);
  const removing = useDoing("drive.remove", { station: at.station, root: at.root, path: full });
  const renamed = useDoing("drive.rename", { station: at.station, root: at.root, from: full });
  const busy = removing || renamed;
  const zone = useDropZone(row.drop);
  const shared = {
    className: css.row, "data-row": rowKey(at.path, entry.name), "data-compact": compact || undefined, "data-tree": depth !== undefined || undefined,
    "data-chosen": row.chosen || undefined, "data-along": (along && !row.chosen) || undefined,
    style: depth !== undefined ? { "--depth": depth } as CSSProperties : undefined, title: compact ? entry.name : undefined,
  };
  const parts = <>
    {depth !== undefined && (
      <span className={css.disclosure} data-open={expanded || undefined}
        onClick={onToggle ? (e) => { e.stopPropagation(); onToggle(); } : undefined} onDoubleClick={(e) => e.stopPropagation()}>
        {entry.dir && <ChevronRight size={12} strokeWidth={2} />}
      </span>
    )}
    <KindIcon kind={entry.kind} size={compact ? 18 : 20} className={css.icon} />
    {row.renaming ? <NameField name={entry.name} dir={entry.dir} onDone={row.rename} /> : <span className={css.name}>{entry.name}</span>}
    <span className={css.size}>{entry.dir || column ? "" : entry.sizeText}</span>
    {!compact && <span className={css.time}>{entry.timeText}</span>}
  </>;
  const el = (
    <div className={css.entry} data-busy={busy || undefined} data-drop={zone.over || undefined} data-drop-into={row.drop ? "" : undefined}
      draggable={!busy && !row.renaming} onDragStart={(e) => startDrag(e, row.dragged())} onDragEnd={endDrag} onContextMenu={row.menu} {...zone.props}>
      {row.renaming ? <div {...shared}>{parts}</div> : (
        <button type="button" {...shared} onClick={row.press} onDoubleClick={row.open} disabled={busy}
          aria-selected={row.chosen} aria-expanded={depth !== undefined && entry.dir ? !!expanded : undefined}>
          {parts}
        </button>
      )}
      {next && <span className={css.next}><ChevronRight size={12} strokeWidth={2} /></span>}
      <span className={css.more}>{busy ? <Spinner /> : <Menu items={row.items} />}</span>
    </div>
  );
  return (
    <ContextMenu.Root modal={false}>
      <ContextMenu.Trigger asChild disabled={busy || row.renaming}>{el}</ContextMenu.Trigger>
      <MenuContent items={row.items} />
    </ContextMenu.Root>
  );
}

/** A right click's menu: what can be done, each a line. */
function MenuContent({ items }: { items: MenuItem[] }) {
  return (
    <ContextMenu.Portal>
      <ContextMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList}`} collisionPadding={8} onCloseAutoFocus={(e) => e.preventDefault()}>
        {items.map((item) => (
          <ContextMenu.Item key={item.label} className={controlsCss.menuItem} data-danger={item.danger || undefined} onSelect={item.onSelect}>
            {item.icon && <item.icon {...ICON} />}{item.label}
          </ContextMenu.Item>
        ))}
      </ContextMenu.Content>
    </ContextMenu.Portal>
  );
}

/** A name changed in place: the name but its extension chosen; ⏎ or leaving it keeps it, esc leaves it as it was. */
function NameField({ name, dir, onDone }: { name: string; dir: boolean; onDone: (to: string | null) => void }) {
  const done = useRef(false);
  const finish = (to: string | null) => { if (done.current) return; done.current = true; onDone(to); };
  return (
    <input className={css.nameField} defaultValue={name} autoFocus aria-label={t("web-pages.drive.nameLabel")} spellCheck={false}
      onFocus={(e) => { const dot = e.currentTarget.value.lastIndexOf("."); e.currentTarget.setSelectionRange(0, !dir && dot > 0 ? dot : e.currentTarget.value.length); }}
      onClick={(e) => e.stopPropagation()} onDoubleClick={(e) => e.stopPropagation()}
      onKeyDown={(e) => {
        e.stopPropagation();
        if (e.nativeEvent.isComposing) return;
        if (e.key === "Enter") { e.preventDefault(); finish(e.currentTarget.value); }
        if (e.key === "Escape") { e.preventDefault(); finish(null); }
      }}
      onBlur={(e) => finish(e.currentTarget.value)} />
  );
}

/** Over a list, what its columns are, each ordering it (again: the other way). */
function ListHead({ arrangement, onSort }: { arrangement: DriveArrangement; onSort: (by: DriveSortBy) => void }) {
  const head = (by: DriveSortBy, label: string) => (
    <button type="button" data-on={arrangement.by === by || undefined} onClick={() => onSort(by)}>
      {label}{arrangement.by === by && <ChevronRight size={10} strokeWidth={2} style={{ transform: `rotate(${arrangement.down ? -90 : 90}deg)` }} />}
    </button>
  );
  return (
    <div className={css.listHead}>
      <span />
      {head("name", t("web-pages.drive.sortBy.nameHead"))}
      {head("size", t("web-pages.drive.sortBy.sizeHead"))}
      {head("time", t("web-pages.drive.sortBy.timeHead"))}
      <span />
    </div>
  );
}

function UploadRow({ u }: { u: Up }) {
  return (
    <div className={css.entry} data-upload>
      <span className={css.row}>
        <Upload size={20} strokeWidth={1.6} className={css.icon} />
        <span className={css.name}>{u.name}</span>
        {u.state === "taken" ? (
          <span className={css.ask}>
            {t("web-pages.drive.taken")}
            <Button variant="ghost" onClick={() => settle(u.key, true)}>{t("web-pages.drive.replace")}</Button>
            <Button variant="ghost" onClick={() => settle(u.key, false)}>{t("web-pages.drive.keepBoth")}</Button>
          </span>
        ) : u.state === "failed" ? <span className={css.failed}>{t("web-pages.drive.uploadFailed", { error: u.error ?? "" })}</span>
          : (
            <span className={css.progressCell}>
              <span className={css.progress}><span style={{ transform: `scaleX(${u.size ? u.sent / u.size : 0})` }} /></span>
              <span className={css.size}>{t("web-pages.drive.uploading", { sent: sizeOf(u.sent), size: sizeOf(u.size) })}</span>
            </span>
          )}
      </span>
      <span className={css.more} data-shown>
        {u.state === "failed" && <IconButton label={t("web-pages.drive.retry")} icon={Retry} onClick={() => retry(u.key)} />}
        <IconButton label={t("common.cancel")} icon={Close} onClick={() => cancel(u.key)} />
      </span>
    </div>
  );
}

function Empty({ text, action }: { text: string; action?: ReactNode }) {
  return (
    <div className={css.empty}>
      <Folder size={36} strokeWidth={1.3} />
      <p>{text}</p>
      {action}
    </div>
  );
}

/** The folders lent: each with its state, taken back with ×; another added from the station's folders. */
function RootsDialog({ station, roots, onAdd, onClose }: { station: string; roots: DriveRoot[]; onAdd: () => void; onClose: () => void }) {
  const act = useAct();
  const [asking, setAsking] = useState<DriveRoot | null>(null);
  const busy = useDoing("drive.setRoots", { station });
  return (
    <Dialog open onClose={onClose} title={t("web-pages.drive.manage")} description={t("web-pages.drive.manageNote")}
      footer={<><Button variant="ghost" onClick={onClose}>{t("common.done")}</Button><Button variant="primary" icon={Plus} busy={busy} onClick={onAdd}>{t("web-pages.drive.addRoot")}</Button></>}>
      <div className={css.rootsList}>
        {roots.length === 0 && <p className={shellCss.muted}>{t("web-pages.drive.noneYet")}</p>}
        {roots.map((r) => {
          const trouble = rootTrouble(r);
          return (
            <div key={r.path} className={css.rootLine}>
              <Folder {...ICON} className={shellCss.muted} />
              <span className={css.text}>
                <span className={css.name}>{r.name}</span>
                <span className={css.meta}>{r.path}</span>
                {trouble && <span className={css.trouble}><b>{trouble.text}</b> · {trouble.hint}</span>}
              </span>
              <IconButton label={t("web-pages.drive.unshare")} icon={Close} onClick={() => setAsking(r)} />
            </div>
          );
        })}
      </div>
      <Confirm open={asking !== null} onClose={() => setAsking(null)} title={t("web-pages.drive.unshareAsk", { name: asking?.name ?? "" })} description={t("web-pages.drive.unshareText")}
        action={t("web-pages.drive.unshare")} onConfirm={() => { const r = asking; setAsking(null); if (r) act(drive.setRoots(station, roots.filter((x) => x.path !== r.path).map((x) => x.path)), t("web-pages.drive.rootsWhat")); }} />
    </Dialog>
  );
}

/**
 * The station's folders from its home: the usual places beside them (the home's own folders, the disks), a filter,
 * the way back as crumbs; entered by a click, the one shown lent with 选这个文件夹. One the station may not list says
 * so, and is not lent.
 */
function PickerDialog({ station, roots, onClose }: { station: string; roots: DriveRoot[]; onClose: () => void }) {
  const act = useAct();
  const picker = useFolders(station);
  const v = picker.value;
  // Its places stay while the next folder is read, or when the station cannot read it.
  const near = picker.last;
  const taken = v ? roots.some((r) => r.path === v.path) : false;
  const unreadable = picker.unreadable;
  // At home with nothing typed, the usual places (on the left) are not listed again under their names on disk.
  const shown = v ? filtered(v.entries, picker.filter).filter((e) => !(v.path === v.home && picker.filter.trim() === "" && v.places.some((p) => p.path === e.path))) : [];
  const where = v?.path ?? picker.crumbs.at(-1)?.path;
  const row = (f: PickFolder, here = false) => (
    <button key={f.path} type="button" className={css.pickRow} data-here={here || undefined} onClick={() => picker.go(f)}>
      {f.disk ? <Disk size={18} strokeWidth={1.6} className={css.icon} /> : <Folder size={18} strokeWidth={1.6} className={css.icon} />}
      {f.unreadable ? (
        <span className={css.text}>
          <span className={css.name}>{f.name}</span>
          <span className={css.pickNote}>{t("web-pages.drive.pickUnreadable")}</span>
        </span>
      ) : <span className={css.name}>{f.name}</span>}
    </button>
  );
  return (
    <Dialog open wide onClose={onClose} title={t("web-pages.drive.pick")} description={t("web-pages.drive.pickNote")}
      footer={<>
        <Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button>
        <Button variant="primary" disabled={!v || taken || unreadable} onClick={() => {
          const path = v!.path;
          onClose();
          act(drive.setRoots(station, [...roots.map((r) => r.path), path]), t("web-pages.drive.rootsWhat"), t("web-pages.drive.shared", { name: path.split(/[/\\]/).filter(Boolean).at(-1) ?? path }));
        }}>{taken ? t("web-pages.drive.already") : t("web-pages.drive.pickThis")}</Button>
      </>}>
      <div className={css.pickerPath}>
        <span className={css.pickerCrumbs} ref={(el) => { if (el) el.scrollLeft = el.scrollWidth; }}>
          {picker.crumbs.map((c, i, all) => (
            <span key={c.path} className={css.pickerCrumb}>
              {i > 0 && <ChevronRight size={12} className={shellCss.muted} />}
              <button type="button" data-last={i === all.length - 1 || undefined} onClick={() => i < all.length - 1 && picker.go({ name: c.name, path: c.path, unreadable: false })}>{c.name}</button>
            </span>
          ))}
        </span>
        {!picker.shut && <span className={css.pickerFilter}><FilterField value={picker.filter} onChange={picker.setFilter} className={controlsCss.input} /></span>}
      </div>
      <div className={css.picker}>
        {near && near.places.length > 0 && (
          <div className={css.pickerPlaces}>
            <div className={css.pickerHead}>{t("web-pages.drive.places")}</div>
            {near.places.map((p) => row(p, p.path === where))}
          </div>
        )}
        <div className={css.pickerList}>
          {picker.shut ? (
            <div className={css.pickerShut}>
              <Folder size={32} strokeWidth={1.3} />
              <p>{picker.shut.unreadable ? t("web-pages.drive.pickNeedsAccess") : picker.shut.message}</p>
            </div>
          ) : !v ? <WaitLine className={css.pickerHead} />
            : shown.length === 0 ? <p className={`${shellCss.muted} ${css.pickerHead}`}>{picker.filter.trim() ? t("web-pages.drive.pickNoMatch") : t("web-pages.drive.noSubfolders")}</p>
            : (
              <>
                <div className={css.pickerHead}>{t("web-pages.drive.foldersHere")}</div>
                {shown.map((f) => row(f))}
              </>
            )}
        </div>
      </div>
    </Dialog>
  );
}

// ── a file opened: a page of its own ───────────────────────────────────

function useOpened() {
  const station = useStation();
  const [q] = useSearchParams();
  const root = q.get("root") ?? "";
  const path = q.get("path") ?? "";
  const folderPath = parentOf(path);
  const folder = useFolder(station.address, root, folderPath);
  const entry = folder.value?.entries.find((e) => e.name === nameOf(path)) ?? null;
  const d = useDrive(station.address);
  const back = folderPath ? nameOf(folderPath) : rootLabel(d.roots, root);
  const at = { station: station.address, root, path };
  const file = useDriveFile(at, entry);
  return { station, root, path, folderPath, folder, entry, back, at, file };
}

/** Back to the folder: a step back in history when it was opened from it, else there. */
function useBack(base: string, root: string, folder: string): () => void {
  const go = useGo();
  return () => {
    if (((window.history.state as { idx?: number } | null)?.idx ?? 0) > 0) go(-1);
    else go(drivePath(base, root, folder));
  };
}

export function DriveReadPage() {
  const o = useOpened();
  const back = useBack(o.station.base, o.root, o.folderPath);
  return (
    <div className={css.opened}>
      {o.file && o.entry ? <Reader key={o.path} file={o.file} markdown={o.entry.kind === "markdown"} backLabel={o.back} onBack={back} />
        : o.folder.error || o.folder.value ? <p className={`${css.openedNote} ${controlsCss.fieldError}`}>{o.folder.error?.message ?? t("web-pages.drive.gone")}</p>
        : <WaitLine className={css.openedNote} />}
    </div>
  );
}

export function DrivePlayPage() {
  const o = useOpened();
  const go = useGo();
  const back = useBack(o.station.base, o.root, o.folderPath);
  return (
    <div className={`${css.opened} ${css.dark}`}>
      {o.file ? <Player key={o.path} file={o.file} siblings={o.folder.value?.entries ?? []} backLabel={o.back} onBack={back}
        onGo={(name) => go(drivePath(o.station.base, o.root, joinPath(o.folderPath, name), "play"), { replace: true })} />
        : o.folder.error || o.folder.value ? <p className={`${css.openedNote} ${controlsCss.fieldError}`}>{o.folder.error?.message ?? t("web-pages.drive.gone")}</p>
        : <WaitLine className={css.openedNote} />}
    </div>
  );
}
