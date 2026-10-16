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
import { Navigate, useSearchParams } from "react-router";
import { ContextMenu } from "radix-ui";
import { stationBase, useStation } from "../station.tsx";
import { useStations } from "../api.ts";
import { useWorkspace } from "../cloud/api.ts";
import { useGo } from "../go.ts";
import { useDoing } from "../doing.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import type { DriveEntry, DriveRoot, StationView } from "../core/shapes.ts";
import { useTopicSelect } from "../core/react.ts";
import { Button, Confirm, Dialog, ICON, IconButton, Menu, Tip, type MenuItem } from "../ui.tsx";
import { ChevronLeft, ChevronRight, Close, Copy, Disk, Server, Download, Edit, Folder, FolderPlus, Pin, Plus, Refresh, Retry, Trash, Upload } from "@stillfail/ui/icons.tsx";
import { KindIcon } from "../drive/KindIcon.tsx";
import { Reader } from "@stillfail/ui/viewer/Reader.tsx";
import { Player } from "@stillfail/ui/viewer/Player.tsx";
import { cancel, download, joinPath, nameOf, openerOf, parentOf, refresh, retry, rootLabel, settle, sizeOf, upload, useFolder, useUploads, type At, type Upload as Up } from "../drive/model.ts";
import { useDriveFile } from "../drive/viewerFile.ts";
import { absoluteOf, childOf, drive, drivePath, filtered, folderName, nameProblem, rootTrouble, trailOf, useDrive, type DriveState, type PickFolder } from "../drive/useDrive.ts";
import { draggedOf, endDrag, startDrag } from "../drive/drag.ts";
import { useJoinedPins } from "../drive/joinedPins.ts";
import { ColumnsView, TreeView, useDriveView, ViewSwitch, type RowOf } from "./DriveViews.tsx";
import { useToast } from "@stillfail/ui/toast.tsx";
import { DrivePreview, FilterField, useFolders } from "../mobile/Drive.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as css from "./Drive.css.ts";
import { t } from "../i18n.ts";
import * as spinnerCss from "@stillfail/ui/styles/spinner.css.ts";

export function DrivePage() {
  const station = useStation();
  const [q] = useSearchParams();
  const d = useDrive(station.address);
  const asked = q.get("root");
  const path = q.get("path") ?? "";
  const only = d.roots.length === 1 && d.roots[0]!.state === "ok" ? d.roots[0]!.path : null;
  // Where nothing is asked: the one folder pinned, else the home for a member who browses every folder.
  const root = asked ?? only ?? (d.anywhere ? d.home : null);
  return (
    <div className={`${pagesCss.page} ${css.page}`}>
      {d.loading || !d.offered || root === null ? <Roots d={d} /> : <FolderView d={d} root={root} path={path} />}
    </div>
  );
}

/** 文件 in the rail (`/w/<ws>/files`): the first folder pinned on any station (the sidebar lists them all), else the
 * first station's home; none, says so. */
export function DriveHome({ scope }: { scope: string }) {
  const stations = useStations(scope).value;
  const add = useAddFolder(scope);
  const first = (stations ?? []).flatMap((s) => (s.overview?.drive?.roots ?? []).map((r) => drivePath(stationBase(s.station), r.path)))[0]
    ?? (stations ?? []).flatMap((s) => (s.overview?.drive?.anywhere && s.overview.drive.home ? [drivePath(stationBase(s.station), s.overview.drive.home)] : []))[0];
  if (first) return <Navigate to={first} replace />;
  return (
    <div className={`${pagesCss.page} ${css.page}`}>
      <header className={pagesCss.pageHead}><div className={css.headText}><h1>{t("web-pages.drive.title")}</h1></div></header>
      {!stations ? <p className={shellCss.muted}>{t("web-pages.drive.reading")}</p>
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
              <Server size={18} strokeWidth={1.6} className={css.icon} />
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
          <span className={css.crumbs}><span>{station.name}</span></span>
          <h1>{t("web-pages.drive.title")}</h1>
        </div>
        {(d.manage || d.anywhere) && d.offered && d.roots.length > 0 && <div className={css.actions}><Menu items={[{ label: t("web-pages.drive.manage"), icon: Folder, onSelect: manage.open }]} /></div>}
      </header>
      {d.loading ? <p className={shellCss.muted}>{d.error ?? t("web-pages.drive.reading")}</p>
        : !d.offered ? <Empty text={t("web-pages.drive.oldStation")} />
        : d.roots.length === 0 ? (
          <Empty text={d.manage || d.anywhere ? t("web-pages.drive.noneManage") : t("web-pages.drive.noneMember")}
            action={d.manage || d.anywhere ? <Button variant="primary" icon={Folder} onClick={manage.pick}>{t("web-pages.drive.pick")}</Button> : undefined} />
        ) : (
          <div className={css.list}>
            <p className={css.count}>{t("web-pages.drive.rootsCount", { n: d.roots.length })}</p>
            {d.roots.map((r) => <RootRow key={r.path} root={r} onOpen={() => go(drivePath(station.base, r.path))} />)}
          </div>
        )}
      {manage.dialogs}
    </>
  );
}

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

function FolderView({ d, root, path }: { d: DriveState; root: string; path: string }) {
  const station = useStation();
  const go = useGo();
  const act = useAct();
  const folder = useFolder(station.address, root, path);
  const uploads = useUploads(station.address, root, path);
  const at: At = useMemo(() => ({ station: station.address, root, path }), [station.address, root, path]);
  const entries = folder.value?.entries ?? [];
  const manage = useManage(d);
  const files = useRef<HTMLInputElement>(null);
  const [refreshing, setRefreshing] = useState(false);
  // What is named, removed or previewed, with the folder it is in (a tree or columns show more than the one folder).
  const [naming, setNaming] = useState<{ at: At; entry: DriveEntry | null } | null>(null);
  const [removing, setRemoving] = useState<{ at: At; entry: DriveEntry } | null>(null);
  const [preview, setPreview] = useState<{ at: At; entries: readonly DriveEntry[]; entry: DriveEntry } | null>(null);
  const [view, setView] = useDriveView("page");
  const [dragging, setDragging] = useState(false);
  const here = absoluteOf(root, path);
  const name = path ? nameOf(path) : d.anywhere && !d.roots.some((r) => r.path === root) ? (here === d.home ? t("web-pages.drive.home") : folderName(here)) : rootLabel(d.roots, root);
  const pinned = d.roots.some((r) => r.path === here);
  const toast = useToast();
  const copyPath = (abs: string) => void navigator.clipboard.writeText(abs).then(() => toast(t("web-pages.drive.pathCopied")), (e: unknown) => toast(t("web-main.copyFailed", { error: e instanceof Error ? e.message : String(e) })));
  const pin = (abs: string, on: boolean) => act(drive.pin(station.address, d.roots, abs, on), t("web-pages.drive.rootsWhat"), t(on ? "web-pages.drive.shared" : "web-pages.drive.unpinned", { name: folderName(abs) }));
  // Lent to the workspaces the station joined, for its managers.
  const pinsFor = useJoinedPins(station.address, d.anywhere === true);
  const reload = () => {
    if (refreshing) return;
    setRefreshing(true);
    act(refresh(at).finally(() => setRefreshing(false)), t("web-pages.drive.refreshWhat"));
  };
  // An entry of the folder `in` (the one shown, or one under it a tree or columns show) opened: a folder gone into, a
  // text read, a video played, a picture or code previewed, the rest downloaded.
  const openIn = (in_: At, e: DriveEntry, siblings: readonly DriveEntry[] = [e]) => {
    const full = joinPath(in_.path, e.name);
    switch (openerOf(e.kind)) {
      case "folder": return go(drivePath(station.base, root, full));
      case "read": return go(drivePath(station.base, root, full, "read"));
      case "play": return go(drivePath(station.base, root, full, "play"));
      case "preview": return setPreview({ at: in_, entries: siblings, entry: e });
      default: return save(in_, e);
    }
  };
  const open = (e: DriveEntry) => openIn(at, e, entries);
  const save = (in_: At, e: DriveEntry) => act(download({ ...in_, path: joinPath(in_.path, e.name) }, e), t("web-pages.drive.downloadWhat"));
  const itemsIn = (in_: At, e: DriveEntry): MenuItem[] => [
    { label: t("web-pages.drive.open"), onSelect: () => openIn(in_, e) },
    ...(e.dir ? [] : [{ label: t("web-pages.drive.download"), icon: Download, onSelect: () => save(in_, e) }]),
    { label: t("web-pages.drive.copyPath"), icon: Copy, onSelect: () => copyPath(absoluteOf(root, joinPath(in_.path, e.name))) },
    ...(e.dir && d.anywhere ? [(() => {
      const abs = absoluteOf(root, joinPath(in_.path, e.name));
      const on = d.roots.some((r) => r.path === abs);
      return { label: t(on ? "web-pages.drive.unpin" : "web-pages.drive.pin"), icon: Pin, onSelect: () => pin(abs, !on) };
    })(), ...pinsFor(absoluteOf(root, joinPath(in_.path, e.name)))] : []),
    ...(d.write ? [
      { label: t("web-pages.drive.rename"), icon: Edit, onSelect: () => setNaming({ at: in_, entry: e }) },
      { label: t("web-pages.drive.delete"), icon: Trash, danger: true, onSelect: () => setRemoving({ at: in_, entry: e }) },
    ] : []),
  ];
  const items = (e: DriveEntry) => itemsIn(at, e);
  const rowOf: RowOf = (in_, e) => ({ items: itemsIn(in_, e), open: () => openIn(in_, e) });
  const empty = <Empty text={t("web-pages.drive.emptyFolder")} action={d.write ? <Button icon={Upload} onClick={() => files.current?.click()}>{t("web-pages.drive.upload")}</Button> : undefined} />;
  // ⌘/Ctrl+U puts files up into the folder shown.
  useEffect(() => {
    if (!d.write) return;
    const onKey = (e: KeyboardEvent) => { if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "u") { e.preventDefault(); files.current?.click(); } };
    addEventListener("keydown", onKey);
    return () => removeEventListener("keydown", onKey);
  }, [d.write]);
  const trail = path.split("/").filter(Boolean);
  // For a member who browses every folder: the whole way from the home (or the disk's top), each step a folder to go to
  // (those within the root by their path under it, so a pinned folder stays the one marked in the sidebar).
  const way = d.anywhere ? trailOf(here, d.home, t("web-pages.drive.home")) : null;
  const goTo = (abs: string) => {
    const under = abs === root ? "" : abs.startsWith(root.endsWith("/") ? root : `${root}/`) ? abs.slice(root.length).replace(/^\/+/, "") : null;
    go(under !== null ? drivePath(station.base, root, under) : drivePath(station.base, abs));
  };
  return (
    <>
      <header className={pagesCss.pageHead}>
        <div className={css.headText}>
          {way && way.length > 1 && (
            <span className={css.crumbs}>
              {way.slice(0, -1).map((c, i) => (
                <span key={c.path} className={css.crumb}>{i > 0 && <ChevronRight size={12} />}<button type="button" onClick={() => goTo(c.path)}>{c.name}</button></span>
              ))}
            </span>
          )}
          {/* Inside a folder lent: the way back up to it (the folder lent itself, and whose it is, are the sidebar's). */}
          {!way && trail.length > 0 && (
            <span className={css.crumbs}>
              <button type="button" onClick={() => go(drivePath(station.base, root))}>{rootLabel(d.roots, root)}</button>
              {trail.slice(0, -1).map((p, i) => (
                <span key={i} className={css.crumb}><ChevronRight size={12} /><button type="button" onClick={() => go(drivePath(station.base, root, trail.slice(0, i + 1).join("/")))}>{p}</button></span>
              ))}
            </span>
          )}
          <h1>{name}</h1>
          <p className={css.headMeta}>
            {station.name}
            {folder.value && <> · {folder.value.countText}{folder.value.truncated ? ` · ${t("web-pages.drive.truncated")}` : ""}</>}
          </p>
        </div>
        <div className={css.actions}>
          <ViewSwitch value={view} onChange={setView} />
          {d.write && <IconButton label={t("web-pages.drive.upload")} icon={Upload} onClick={() => files.current?.click()} />}
          {d.write && <IconButton label={t("web-pages.drive.mkdir")} icon={FolderPlus} onClick={() => setNaming({ at, entry: null })} />}
          <span className={css.spin} data-on={refreshing || undefined}><IconButton label={t("web-pages.drive.refresh")} icon={Refresh} onClick={reload} /></span>
          {d.anywhere && <span className={css.pin} data-on={pinned || undefined}><IconButton label={t(pinned ? "web-pages.drive.unpin" : "web-pages.drive.pin")} icon={Pin} onClick={() => pin(here, !pinned)} /></span>}
          <Menu items={[
            { label: t("web-pages.drive.copyPath"), icon: Copy, onSelect: () => copyPath(here) },
            ...(d.manage || d.anywhere ? [{ label: t("web-pages.drive.manage"), icon: Folder, onSelect: manage.open }] : []),
          ]} />
        </div>
      </header>
      <div className={css.list} data-dragging={dragging || undefined} data-view={view}
        onDragOver={(e) => { if (d.write && e.dataTransfer.types.includes("Files")) { e.preventDefault(); e.dataTransfer.dropEffect = "copy"; setDragging(true); } }}
        onDragLeave={(e) => { if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setDragging(false); }}
        onDrop={(e) => { if (!d.write || !e.dataTransfer.files.length) return; e.preventDefault(); setDragging(false); upload(station.address, root, path, [...e.dataTransfer.files]); }}>
        {folder.error ? (
          <div className={css.problem}><p className={controlsCss.fieldError}>{folder.error.message}</p><Button variant="ghost" icon={Retry} onClick={reload}>{t("web-pages.drive.retry")}</Button></div>
        ) : !folder.value ? <p className={shellCss.muted}>{t("web-pages.drive.reading")}</p> : (
          <>
            {uploads.map((u) => <UploadRow key={u.key} u={u} />)}
            {view === "columns" ? <ColumnsView at={{ ...at, path: "" }} open={path} onGo={(p) => go(drivePath(station.base, root, p))} rowOf={rowOf} empty={uploads.length ? <></> : empty} />
              : view === "tree" ? <TreeView key={path} at={at} rowOf={rowOf} empty={uploads.length ? <></> : empty} />
              : <>
                {entries.length === 0 && uploads.length === 0 && empty}
                {entries.map((e) => <EntryRow key={e.name} at={at} entry={e} items={items(e)} onOpen={() => open(e)} />)}
              </>}
          </>
        )}
        {dragging && <div className={css.drop}><Upload size={22} /><span>{t("web-pages.drive.dropHere", { name })}</span></div>}
      </div>
      <input ref={files} type="file" multiple hidden onChange={(e) => { const list = [...(e.target.files ?? [])]; e.target.value = ""; if (list.length) upload(station.address, root, path, list); }} />
      {naming && <NameDialog at={naming.at} entry={naming.entry} onClose={() => setNaming(null)} />}
      <Confirm open={removing !== null} onClose={() => setRemoving(null)}
        title={removing ? t(removing.entry.dir ? "web-pages.drive.deleteFolderAsk" : "web-pages.drive.deleteAsk", { name: removing.entry.name }) : ""}
        description={removing?.entry.dir ? t("web-pages.drive.deleteFolderText") : t("web-pages.drive.deleteText")} action={t("web-pages.drive.delete")}
        onConfirm={() => { const r = removing; setRemoving(null); if (r) act(drive.remove(r.at, r.entry), t("web-pages.drive.deleteWhat")); }} />
      {preview && <DrivePreview at={preview.at} entries={preview.entries} entry={preview.entry} onClose={() => setPreview(null)} />}
      {manage.dialogs}
    </>
  );
}

/** A station's name, as the workspace's stations list has it (its address while not known). */
export function useStationName(station: string): string {
  return useTopicSelect<StationView[], string>({ topic: "stations", scope: station.split("/")[0] ?? "" }, (s) => s.value?.find((x) => x.station === station)?.name ?? station);
}

function EntryRow({ at, entry, items, onOpen }: { at: At; entry: DriveEntry; items: MenuItem[]; onOpen: () => void }) {
  return <DriveRow at={at} entry={entry} items={items} onOpen={onOpen} />;
}

/**
 * A row of a folder's list, as the files' page and a chat's 文件 tab draw it: its mark, name, size and time (`compact`:
 * the size alone), the … on hover and the same on a right click; dragged out, it carries the file and its path. In a
 * tree (`depth`), in by its depth, a folder with its disclosure (`expanded`); in columns, a folder with › at its end
 * (`column`), the one open `selected`.
 */
export function DriveRow({ at, entry, items, onOpen, compact = false, depth, expanded, column = false, selected = false }: {
  at: At; entry: DriveEntry; items: MenuItem[]; onOpen: () => void; compact?: boolean;
  depth?: number | undefined; expanded?: boolean | undefined; column?: boolean; selected?: boolean;
}) {
  // In a column a folder has › at its end, a file nothing: its name takes the room.
  const next = column && entry.dir;
  const stationName = useStationName(at.station);
  const full = joinPath(at.path, entry.name);
  const removing = useDoing("drive.remove", { station: at.station, root: at.root, path: full });
  const renaming = useDoing("drive.rename", { station: at.station, root: at.root, from: full });
  const busy = removing || renaming;
  const row = (
    <div className={css.entry} data-busy={busy || undefined} draggable={!busy} onDragStart={(e) => startDrag(e, [draggedOf(at, entry, stationName)])} onDragEnd={endDrag}>
      <button type="button" className={css.row} data-compact={compact || undefined} data-tree={depth !== undefined || undefined} data-selected={selected || undefined}
        style={depth !== undefined ? { "--depth": depth } as CSSProperties : undefined} onClick={onOpen} disabled={busy} title={compact ? entry.name : undefined}
        aria-expanded={depth !== undefined && entry.dir ? !!expanded : undefined}>
        {depth !== undefined && <span className={css.disclosure} data-open={expanded || undefined}>{entry.dir && <ChevronRight size={12} strokeWidth={2} />}</span>}
        <KindIcon kind={entry.kind} size={compact ? 18 : 20} className={css.icon} />
        <span className={css.name}>{entry.name}</span>
        <span className={css.size}>{entry.dir ? (next ? <ChevronRight size={12} strokeWidth={2} className={shellCss.muted} /> : "") : column ? "" : entry.sizeText}</span>
        {!compact && <span className={css.time}>{entry.timeText}</span>}
      </button>
      <span className={css.more}>{busy ? <span className={`${spinnerCss.spinner} ${controlsCss.iconSpinner}`} aria-hidden="true" /> : <Menu items={items} />}</span>
    </div>
  );
  return (
    <ContextMenu.Root modal={false}>
      <ContextMenu.Trigger asChild disabled={busy}>{row}</ContextMenu.Trigger>
      <ContextMenu.Portal>
        <ContextMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList}`} collisionPadding={8} onCloseAutoFocus={(e) => e.preventDefault()}>
          {items.map((item) => (
            <ContextMenu.Item key={item.label} className={controlsCss.menuItem} data-danger={item.danger || undefined} onSelect={item.onSelect}>
              {item.icon && <item.icon {...ICON} />}{item.label}
            </ContextMenu.Item>
          ))}
        </ContextMenu.Content>
      </ContextMenu.Portal>
    </ContextMenu.Root>
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

/** A new folder's name (`entry` null), or an entry's new one. */
function NameDialog({ at, entry, onClose }: { at: At; entry: DriveEntry | null; onClose: () => void }) {
  const act = useAct();
  const [name, setName] = useState(entry?.name ?? "");
  const problem = name.trim() ? nameProblem(name) : null;
  const ok = !!name.trim() && !problem && name.trim() !== entry?.name;
  const go = () => {
    if (!ok) return;
    onClose();
    if (entry) act(drive.rename(at, entry, name.trim()), t("web-pages.drive.renameWhat"));
    else act(drive.mkdir(at, name.trim()), t("web-pages.drive.mkdirWhat"));
  };
  return (
    <Dialog open onClose={onClose} title={entry ? t("web-pages.drive.renameTitle") : t("web-pages.drive.mkdir")}
      footer={<><Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button><Button variant="primary" disabled={!ok} onClick={go}>{entry ? t("common.save") : t("web-pages.drive.make")}</Button></>}>
      <input className={controlsCss.input} value={name} autoFocus placeholder={entry ? entry.name : t("web-pages.drive.mkdirPlaceholder")} aria-label={t("web-pages.drive.nameLabel")}
        onFocus={(e) => { if (entry && !entry.dir) { const dot = e.currentTarget.value.lastIndexOf("."); if (dot > 0) e.currentTarget.setSelectionRange(0, dot); } }}
        onChange={(e) => setName(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter" && !e.nativeEvent.isComposing) go(); }} />
      {problem && <p className={controlsCss.fieldError}>{problem}</p>}
    </Dialog>
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
          ) : !v ? <p className={`${shellCss.muted} ${css.pickerHead}`}>{t("web-pages.drive.reading")}</p>
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
        : <p className={`${css.openedNote} ${o.folder.error || o.folder.value ? controlsCss.fieldError : shellCss.muted}`}>{o.folder.error?.message ?? (o.folder.value ? t("web-pages.drive.gone") : t("web-pages.drive.reading"))}</p>}
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
        : <p className={`${css.openedNote} ${o.folder.error || o.folder.value ? controlsCss.fieldError : shellCss.muted}`}>{o.folder.error?.message ?? (o.folder.value ? t("web-pages.drive.gone") : t("web-pages.drive.reading"))}</p>}
    </div>
  );
}
