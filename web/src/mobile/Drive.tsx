// A station's drive on a narrow screen (docs/drive.md), from its page's 文件 row: the folders it lends (one: what is in
// it at once), each folder a page of its own pushed over the last (so it slides in, and a swipe from the edge goes
// back), its entries in a list card: their mark, name, and size · time. A tap opens one: a folder is entered, text
// and Markdown read (../drive/Reader.tsx), video and audio played as they come (../drive/Player.tsx), images, PDFs and
// code previewed as a chat's files are (../FilePreview.tsx), the rest saved. A long press gives what can be done to
// it (rename, save, delete); ＋ puts files up or makes a folder; what goes up shows as rows with how far each has got.
// The workspace's owners and admins name the folders lent (a folder picker on the station, from its home).
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useSearchParams } from "react-router";
import { useStation } from "../station.tsx";
import { useDoing } from "../doing.ts";
import { useAct } from "../toast.tsx";
import type { Attachment, DriveEntry, DriveRoot } from "../core/shapes.ts";
import { ChevronRight, Close, Download, Edit, Folder, FolderPlus, More, Plus, Refresh, Retry, Trash, Upload } from "../icons.tsx";
import { FilePreview, FileSource, Gallery, type FileSourceOf, type Shown } from "../FilePreview.tsx";
import { KindIcon } from "../drive/KindIcon.tsx";
import { Reader } from "../drive/Reader.tsx";
import { Player } from "../drive/Player.tsx";
import { cancel, download, joinPath, nameOf, openerOf, parentOf, readKept, refresh, retry, rootLabel, settle, sizeOf, upload, useFolder, useUploads, type At, type Upload as Up } from "../drive/model.ts";
import { childOf, drive, drivePath, nameProblem, rootTrouble, useDrive, type DriveState } from "../drive/useDrive.ts";
import { SheetGrab, SheetHead, useApp, type MobileApp } from "./app.tsx";
import { ask, confirm } from "./sheets.tsx";
import { Button, ListCard, Loading, NavBar, NavButton, PickRow, Spinner } from "./parts.tsx";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as css from "./Drive.css.ts";
import { t } from "../i18n.ts";

/** A sheet's share of the screen for a title and `rows` rows (a sheet is as tall as what it holds). */
const fit = (rows: number) => Math.min(0.9, (96 + rows * 48 + 24) / window.innerHeight);

/** The drive's page at `files`: its folders, or the one folder's contents, or (`root`, `path`) a folder of one. */
export function DriveScreen() {
  const station = useStation();
  const [q] = useSearchParams();
  const d = useDrive(station.address);
  const asked = q.get("root");
  const path = q.get("path") ?? "";
  // One folder lent, and nothing wrong with it: its contents are the page.
  const only = d.roots.length === 1 && d.roots[0]!.state === "ok" ? d.roots[0]!.path : null;
  const root = asked ?? only;
  if (d.loading || !d.offered || root === null) return <RootsPage d={d} />;
  return <FolderPage d={d} root={root} path={path} top={asked === null} />;
}

function RootsPage({ d }: { d: DriveState }) {
  const app = useApp();
  const station = useStation();
  const manage = () => app.sheet({ height: 0.7, draggable: true, content: () => <RootsSheet station={station.address} roots={d.roots} /> });
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back={station.name} onBack={app.pop} title={t("web-pages.drive.title")}
        trailing={d.manage && d.offered && d.roots.length > 0 ? <NavButton icon={More} label={t("web-pages.drive.manage")} onClick={manage} /> : undefined} />
      <div className={pagesCss.mScroll}>
        {d.loading ? <Loading text={d.error ?? t("web-mobile.reading")} />
          : !d.offered ? <Empty text={t("web-pages.drive.oldStation")} />
          : d.roots.length === 0 ? (
            <Empty text={d.manage ? t("web-pages.drive.noneManage") : t("web-pages.drive.noneMember")}
              action={d.manage ? <Button label={t("web-pages.drive.pick")} primary onClick={() => app.sheet({ height: 0.85, draggable: true, content: () => <PickerSheet station={station.address} roots={d.roots} /> })} /> : undefined} />
          ) : (
            <>
              <p className={css.mCount}>{t("web-pages.drive.rootsCount", { n: d.roots.length })}</p>
              <ListCard>
                {d.roots.map((r) => <RootRow key={r.path} root={r} manage={d.manage} roots={d.roots} onOpen={() => app.push(drivePath(station.base, r.path))} />)}
              </ListCard>
            </>
          )}
        <div style={{ height: 30 }} />
      </div>
    </div>
  );
}

/** A folder lent: its name, where it is; one that cannot be browsed now in red, with what to do about it. */
function RootRow({ root, manage, roots, onOpen }: { root: DriveRoot; manage: boolean; roots: DriveRoot[]; onOpen: () => void }) {
  const app = useApp();
  const station = useStation();
  const trouble = rootTrouble(root);
  const press = useLongPress(() => {
    if (!manage) return;
    app.sheet({ height: fit(1), content: () => (
      <>
        <SheetGrab />
        <SheetHead title={root.name} />
        <div className={sheetsCss.mSheetScroll}>
          <PickRow label={t("web-pages.drive.unshare")} accent leading={<Close size={20} />} onClick={() => unshare(app, station.address, roots, root)} />
        </div>
      </>
    ) });
  });
  return (
    <button type="button" className={css.mRow} {...press.props} onClick={() => { if (!press.held()) onOpen(); }}>
      <Folder size={22} strokeWidth={1.6} className={css.mIcon} />
      <span className={css.mText}>
        <span className={css.mName}>{root.name}</span>
        <span className={css.mMeta}>{root.path}</span>
        {trouble && <span className={css.mTrouble}><b>{trouble.text}</b>{trouble.hint}</span>}
      </span>
      <ChevronRight size={14} className={partsCss.mSubtle} />
    </button>
  );
}

function unshare(app: MobileApp, station: string, roots: DriveRoot[], root: DriveRoot) {
  confirm(app, {
    title: t("web-pages.drive.unshareAsk", { name: root.name }), text: t("web-pages.drive.unshareText"), action: t("web-pages.drive.unshare"), danger: true,
    atOnce: "web-pages.drive.rootsFailed", run: () => drive.setRoots(station, roots.filter((r) => r.path !== root.path).map((r) => r.path)),
  });
}

function FolderPage({ d, root, path, top }: { d: DriveState; root: string; path: string; top: boolean }) {
  const app = useApp();
  const station = useStation();
  const folder = useFolder(station.address, root, path);
  const uploads = useUploads(station.address, root, path);
  const at: At = { station: station.address, root, path };
  const name = path ? nameOf(path) : rootLabel(d.roots, root);
  const back = top ? station.name : path ? (parentOf(path) ? nameOf(parentOf(path)) : rootLabel(d.roots, root)) : t("web-pages.drive.title");
  const [refreshing, setRefreshing] = useState(false);
  const act = useAct();
  const files = useRef<HTMLInputElement>(null);
  const [preview, setPreview] = useState<DriveEntry | null>(null);
  const entries = folder.value?.entries ?? [];
  const reload = () => {
    if (refreshing) return;
    setRefreshing(true);
    act(refresh(at).finally(() => setRefreshing(false)), t("web-pages.drive.refreshWhat"));
  };
  const plus = () => app.sheet({ height: fit(d.manage && top ? 3 : 2), content: () => (
    <>
      <SheetGrab />
      <SheetHead title={name} />
      <div className={sheetsCss.mSheetScroll}>
        <PickRow label={t("web-pages.drive.upload")} leading={<Upload size={20} />} onClick={() => { app.sheet(null); files.current?.click(); }} />
        <PickRow label={t("web-pages.drive.mkdir")} leading={<FolderPlus size={20} />} onClick={() => newFolder(app, at)} />
        {d.manage && top && <PickRow label={t("web-pages.drive.manage")} leading={<Folder size={20} />} onClick={() => app.sheet({ height: 0.7, draggable: true, content: () => <RootsSheet station={station.address} roots={d.roots} /> })} />}
      </div>
    </>
  ) });
  const open = (e: DriveEntry) => {
    const full = joinPath(path, e.name);
    switch (openerOf(e.kind)) {
      case "folder": return app.push(drivePath(station.base, root, full));
      case "read": return app.push(drivePath(station.base, root, full, "read"));
      case "play": return app.push(drivePath(station.base, root, full, "play"));
      case "preview": return setPreview(e);
      default: return save(app, act, { ...at, path: full }, e);
    }
  };
  return (
    <div className={pagesCss.mScreen}>
      <NavBar back={back} onBack={app.pop} title={name}
        trailing={
          <span className={css.mBarButtons}>
            <span className={css.mSpin} data-on={refreshing || undefined}><NavButton icon={Refresh} label={t("web-pages.drive.refresh")} onClick={reload} /></span>
            {d.write ? <NavButton icon={Plus} iconSize={20} label={t("web-pages.drive.add")} onClick={plus} />
              : d.manage && top ? <NavButton icon={More} label={t("web-pages.drive.manage")} onClick={() => app.sheet({ height: 0.7, draggable: true, content: () => <RootsSheet station={station.address} roots={d.roots} /> })} /> : null}
          </span>
        } />
      <div className={pagesCss.mScroll}>
        {path && <Crumbs root={root} rootName={rootLabel(d.roots, root)} path={path} />}
        {folder.error ? (
          <div className={css.mProblem}>
            <span className={partsCss.mError}>{folder.error.message}</span>
            <button type="button" className={partsCss.mLink} onClick={reload}>{t("web-pages.drive.retry")}</button>
          </div>
        ) : !folder.value ? <Loading text={t("web-mobile.reading")} /> : (
          <>
            <p className={css.mCount}>{folder.value.countText}{folder.value.truncated ? ` · ${t("web-pages.drive.truncated")}` : ""}</p>
            {uploads.length > 0 && <ListCard>{uploads.map((u) => <UploadRow key={u.key} u={u} />)}</ListCard>}
            {entries.length === 0 && uploads.length === 0 ? (
              <Empty text={t("web-pages.drive.emptyFolder")} action={d.write ? <Button label={t("web-pages.drive.upload")} primary={false} onClick={() => files.current?.click()} /> : undefined} />
            ) : entries.length > 0 && (
              <ListCard>{entries.map((e) => <EntryRow key={e.name} at={at} entry={e} write={d.write} onOpen={() => open(e)} />)}</ListCard>
            )}
          </>
        )}
        <div style={{ height: 30 }} />
      </div>
      <input ref={files} type="file" multiple hidden onChange={(e) => { const list = [...(e.target.files ?? [])]; e.target.value = ""; if (list.length) upload(station.address, root, path, list); }} />
      {preview && <DrivePreview at={at} entries={entries} entry={preview} onClose={() => setPreview(null)} />}
    </div>
  );
}

/** Where the folder is under its root: each step up a tap away. */
function Crumbs({ root, rootName, path }: { root: string; rootName: string; path: string }) {
  const app = useApp();
  const station = useStation();
  const parts = path.split("/").filter(Boolean);
  const row = useRef<HTMLDivElement>(null);
  // The end of a long path is what matters: in view.
  useEffect(() => { const el = row.current; if (el) el.scrollLeft = el.scrollWidth; }, [path]);
  return (
    <div ref={row} className={css.mCrumbs}>
      <button type="button" onClick={() => app.push(drivePath(station.base, root))}>{rootName}</button>
      {parts.map((p, i) => (
        <span key={i} className={css.mCrumb}>
          <ChevronRight size={12} className={partsCss.mSubtle} />
          {i === parts.length - 1 ? <b>{p}</b> : <button type="button" onClick={() => app.push(drivePath(station.base, root, parts.slice(0, i + 1).join("/")))}>{p}</button>}
        </span>
      ))}
    </div>
  );
}

/** Held a while (a finger): `onHold`; the tap that ends it is not taken for a tap. A right click with a mouse too. */
function useLongPress(onHold: () => void) {
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const held = useRef(false);
  const from = useRef<{ x: number; y: number } | null>(null);
  const [pressed, setPressed] = useState(false);
  const stop = () => { clearTimeout(timer.current); from.current = null; setPressed(false); };
  return {
    held: () => held.current,
    props: {
      "data-held": pressed || undefined,
      onPointerDown: (e: React.PointerEvent) => {
        held.current = false;
        if (e.pointerType === "mouse") return;
        from.current = { x: e.clientX, y: e.clientY };
        setPressed(true);
        timer.current = setTimeout(() => { held.current = true; navigator.vibrate?.(10); onHold(); }, 450);
      },
      onPointerMove: (e: React.PointerEvent) => { const f = from.current; if (f && Math.hypot(e.clientX - f.x, e.clientY - f.y) > 8) stop(); },
      onPointerUp: stop, onPointerCancel: stop, onPointerLeave: stop,
      // The click a finger lifting after a hold makes would land on the sheet's scrim just opened under it, and close it.
      onTouchEnd: (e: React.TouchEvent) => { if (held.current && e.cancelable) e.preventDefault(); },
      onContextMenu: (e: React.MouseEvent) => { e.preventDefault(); if (!held.current) { held.current = true; onHold(); } },
    },
  };
}

function EntryRow({ at, entry, write, onOpen }: { at: At; entry: DriveEntry; write: boolean; onOpen: () => void }) {
  const app = useApp();
  const act = useAct();
  const full = joinPath(at.path, entry.name);
  const removing = useDoing("drive.remove", { station: at.station, root: at.root, path: full });
  const renaming = useDoing("drive.rename", { station: at.station, root: at.root, from: full });
  const busy = removing || renaming;
  const press = useLongPress(() => app.sheet({ height: fit((write ? 2 : 0) + (entry.dir ? 0 : 1)), content: () => <EntrySheet at={at} entry={entry} write={write} act={act} /> }));
  return (
    <button type="button" className={css.mRow} {...press.props} disabled={busy} onClick={() => { if (!press.held()) onOpen(); }}>
      <KindIcon kind={entry.kind} className={css.mIcon} />
      <span className={css.mText}>
        <span className={css.mName}>{entry.name}</span>
        <span className={css.mMeta}>{entry.dir ? entry.timeText : [entry.sizeText, entry.timeText].filter(Boolean).join(" · ")}</span>
      </span>
      {busy ? <Spinner size={14} /> : entry.dir && <ChevronRight size={14} className={partsCss.mSubtle} />}
    </button>
  );
}

function EntrySheet({ at, entry, write, act }: { at: At; entry: DriveEntry; write: boolean; act: ReturnType<typeof useAct> }) {
  const app = useApp();
  return (
    <>
      <SheetGrab />
      <SheetHead title={entry.name} />
      <div className={sheetsCss.mSheetScroll}>
        {write && <PickRow label={t("web-pages.drive.rename")} leading={<Edit size={20} />} onClick={() => ask(app, {
          title: t("web-pages.drive.renameTitle"), value: entry.name, placeholder: entry.name, action: t("common.save"), atOnce: "web-pages.drive.renameFailed",
          run: (name) => { const bad = nameProblem(name); return bad ? Promise.reject(new Error(bad)) : drive.rename(at, entry, name); },
        })} />}
        {!entry.dir && <PickRow label={t("web-pages.drive.download")} leading={<Download size={20} />} onClick={() => { app.sheet(null); save(app, act, { ...at, path: joinPath(at.path, entry.name) }, entry); }} />}
        {write && <PickRow label={t("web-pages.drive.delete")} accent leading={<Trash size={20} />} onClick={() => confirm(app, {
          title: t(entry.dir ? "web-pages.drive.deleteFolderAsk" : "web-pages.drive.deleteAsk", { name: entry.name }), text: t(entry.dir ? "web-pages.drive.deleteFolderText" : "web-pages.drive.deleteText"),
          action: t("web-pages.drive.delete"), danger: true, atOnce: "web-pages.drive.deleteFailed", run: () => drive.remove(at, entry),
        })} />}
      </div>
    </>
  );
}

function newFolder(app: MobileApp, at: At) {
  ask(app, {
    title: t("web-pages.drive.mkdir"), value: "", placeholder: t("web-pages.drive.mkdirPlaceholder"), action: t("web-pages.drive.make"), atOnce: "web-pages.drive.mkdirFailed",
    run: (name) => { const bad = nameProblem(name); return bad ? Promise.reject(new Error(bad)) : drive.mkdir(at, name); },
  });
}

function save(app: MobileApp, act: ReturnType<typeof useAct>, at: At, entry: DriveEntry) {
  app.toast(t("web-pages.drive.downloading", { name: entry.name }));
  act(download(at, entry), t("web-pages.drive.downloadWhat"));
}

/** A file going up: its name, how far it has got; its name taken there (replace it, or keep both), or why it failed. */
function UploadRow({ u }: { u: Up }) {
  const share = u.size > 0 ? u.sent / u.size : 0;
  return (
    <div className={css.mRow} data-upload>
      <Upload size={22} strokeWidth={1.6} className={css.mIcon} />
      <span className={css.mText}>
        <span className={css.mName}>{u.name}</span>
        {u.state === "taken" ? (
          <span className={css.mUploadAsk}>
            <span>{t("web-pages.drive.taken")}</span>
            <button type="button" onClick={() => settle(u.key, true)}>{t("web-pages.drive.replace")}</button>
            <button type="button" onClick={() => settle(u.key, false)}>{t("web-pages.drive.keepBoth")}</button>
          </span>
        ) : u.state === "failed" ? <span className={`${css.mMeta} ${partsCss.mRed}`}>{t("web-pages.drive.uploadFailed", { error: u.error ?? "" })}</span>
          : (
            <>
              <span className={css.mMeta}>{t("web-pages.drive.uploading", { sent: sizeOf(u.sent), size: sizeOf(u.size) })}</span>
              <span className={css.mProgress}><span style={{ transform: `scaleX(${share})` }} /></span>
            </>
          )}
      </span>
      {u.state === "failed" && <button type="button" className={css.mRowButton} aria-label={t("web-pages.drive.retry")} onClick={() => retry(u.key)}><Retry size={16} /></button>}
      <button type="button" className={css.mRowButton} aria-label={t("common.cancel")} onClick={() => cancel(u.key)}><Close size={14} /></button>
    </div>
  );
}

function Empty({ text, action }: { text: string; action?: ReactNode }) {
  return (
    <div className={css.mEmpty}>
      <Folder size={40} strokeWidth={1.3} className={partsCss.mSubtle} />
      <p>{text}</p>
      {action}
    </div>
  );
}

// ── the folders lent: managed, and picked on the station ───────────────

function RootsSheet({ station, roots }: { station: string; roots: DriveRoot[] }) {
  const app = useApp();
  const busy = useDoing("drive.setRoots", { station });
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.drive.manage")} trailing={busy ? <Spinner size={14} /> : undefined} />
      <div className={sheetsCss.mSheetScroll}>
        <p className={`${partsCss.mMuted} ${css.mSheetNote}`}>{t("web-pages.drive.manageNote")}</p>
        {roots.map((r) => (
          <PickRow key={r.path} label={r.name} sub={r.path} leading={<Folder size={20} />} onClick={() => unshare(app, station, roots, r)} mark={rootTrouble(r) ? <span className={partsCss.mRed}>{rootTrouble(r)!.text}</span> : undefined} />
        ))}
        <PickRow label={t("web-pages.drive.addRoot")} leading={<Plus size={20} />} accent onClick={() => app.sheet({ height: 0.85, draggable: true, content: () => <PickerSheet station={station} roots={roots} /> })} />
      </div>
    </>
  );
}

/** The station's folders, from its home: entered by a tap, the one shown lent with 选这个文件夹. */
function PickerSheet({ station, roots }: { station: string; roots: DriveRoot[] }) {
  const app = useApp();
  const act = useAct();
  const picker = useFolders(station);
  const taken = picker.value ? roots.some((r) => r.path === picker.value!.path) : false;
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.drive.pick")} />
      <div className={css.mPickerPath}>{picker.value?.path ?? " "}</div>
      <div className={sheetsCss.mSheetScroll}>
        {picker.error ? <p className={`${partsCss.mError} ${css.mSheetNote}`}>{picker.error}</p>
          : !picker.value ? <Loading text={t("web-mobile.reading")} /> : (
            <>
              {picker.value.parent && <PickRow label={t("web-pages.drive.up")} leading={<ChevronRight size={18} className={css.mUp} />} onClick={() => picker.go(picker.value!.parent)} />}
              {picker.value.folders.length === 0 && <p className={`${partsCss.mMuted} ${css.mSheetNote}`}>{t("web-pages.drive.noSubfolders")}</p>}
              {picker.value.folders.map((f) => <PickRow key={f} label={f} leading={<Folder size={20} />} onClick={() => picker.go(childOf(picker.value!.path, f))} />)}
            </>
          )}
      </div>
      <div className={css.mPickerFoot}>
        <Button label={t("common.cancel")} primary={false} onClick={() => app.sheet(null)} />
        <Button label={taken ? t("web-pages.drive.already") : t("web-pages.drive.pickThis")} primary enabled={!!picker.value && !taken} onClick={() => {
          const path = picker.value!.path;
          app.sheet(null);
          act(drive.setRoots(station, [...roots.map((r) => r.path), path]), t("web-pages.drive.rootsWhat"), t("web-pages.drive.shared", { name: path.split(/[/\\]/).filter(Boolean).at(-1) ?? path }));
        }} />
      </div>
    </>
  );
}

/** The station's folders at a path (its home first), for the picker: `go` to another. */
export function useFolders(station: string) {
  const [path, setPath] = useState<string | null>(null);
  const [value, setValue] = useState<{ path: string; parent: string | null; folders: string[] } | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    setError(null);
    drive.folders(station, path).then((v) => { if (live) setValue(v); }, (e: unknown) => { if (live) setError(e instanceof Error ? e.message : String(e)); });
    return () => { live = false; };
  }, [station, path]);
  return { value, error, go: (to: string | null) => { setValue(null); setPath(to); } };
}

// ── what opens over the folder ─────────────────────────────────────────

/** A drive's file as a chat's file would be, for the preview: its path under the root, its size. */
const asFile = (path: string, e: DriveEntry): Attachment => ({ name: e.name, path: joinPath(path, e.name), size: e.size });

/** An image, a PDF, code: the chat's preview, the folder's images stepped through. */
export function DrivePreview({ at, entries, entry, onClose }: { at: At; entries: readonly DriveEntry[]; entry: DriveEntry; onClose: () => void }) {
  const key = `drive:${at.root}`;
  const byPath = useMemo(() => new Map(entries.map((e) => [joinPath(at.path, e.name), e])), [entries, at.path]);
  const source = useMemo<FileSourceOf>(() => ({
    file: (_key, file, _thumb, onProgress) => {
      const e = byPath.get(file.path);
      return readKept({ ...at, path: file.path }, { size: e?.size ?? file.size, mtime: e?.mtime ?? 0 }, "", onProgress && ((got) => onProgress({ loaded: got.loaded, total: got.total })));
    },
  }), [byPath, at.station, at.root]); // eslint-disable-line react-hooks/exhaustive-deps
  const images = useMemo(() => entries.filter((e) => e.kind === "image").map((e): Shown => ({ sessionKey: key, file: asFile(at.path, e) })), [entries, at.path, key]);
  const gallery = useMemo(() => () => images, [images]);
  return (
    <FileSource.Provider value={source}>
      <Gallery.Provider value={gallery}>
        <FilePreview open onClose={onClose} sessionKey={key} file={asFile(at.path, entry)} />
      </Gallery.Provider>
    </FileSource.Provider>
  );
}

/** The file a read or play page is about, found in its folder (read there, if not held yet). */
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
  return { station, root, path, folder, entry, back, at: { station: station.address, root, path } };
}

export function DriveReadScreen() {
  const app = useApp();
  const o = useOpened();
  return (
    <div className={`${pagesCss.mScreen} ${css.mReaderPage}`}>
      {o.entry ? <Reader at={o.at} name={o.entry.name} size={o.entry.size} mtime={o.entry.mtime} markdown={o.entry.kind === "markdown"} backLabel={o.back} onBack={app.pop} />
        : <Missing back={o.back} error={o.folder.error?.message ?? (o.folder.value ? t("web-pages.drive.gone") : null)} />}
    </div>
  );
}

export function DrivePlayScreen() {
  const app = useApp();
  const o = useOpened();
  return (
    <div className={`${pagesCss.mScreen} ${css.mPlayerPage}`}>
      {o.entry ? <Player at={o.at} entry={o.entry} siblings={o.folder.value?.entries ?? []} backLabel={o.back} onBack={app.pop}
        onGo={(name) => app.replace(drivePath(o.station.base, o.root, joinPath(parentOf(o.path), name), "play"))} />
        : <Missing back={o.back} error={o.folder.error?.message ?? (o.folder.value ? t("web-pages.drive.gone") : null)} />}
    </div>
  );
}

function Missing({ back, error }: { back: string; error: string | null }) {
  const app = useApp();
  return (
    <>
      <NavBar back={back} onBack={app.pop} title="" />
      {error ? <div className={css.mProblem}><span className={partsCss.mError}>{error}</span></div> : <Loading text={t("web-mobile.reading")} />}
    </>
  );
}
