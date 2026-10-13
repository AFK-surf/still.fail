// A station's drive on a wide screen (docs/drive.md), at `/w/<ws>/s/<station>/files` (opened from the station's card in
// settings, the card over its name in a chat, or ⌘K): the folders it lends, a folder's entries in a list (its mark,
// name, size, time), the path above as a trail back. With a mouse: a click opens, the row's … (on hover) or a right
// click gives what can be done to it, files dropped on the list go up into the folder shown, ⌘/Ctrl+U puts files up.
// The reader and the player are pages of their own (`files/read`, `files/play`); images, PDFs and code open in the
// chat's preview over the page. The phone's pages are ../mobile/Drive.tsx, with the same parts under them.
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useSearchParams } from "react-router";
import { ContextMenu, DropdownMenu } from "radix-ui";
import { useStation } from "../station.tsx";
import { useGo } from "../go.ts";
import { useDoing } from "../doing.ts";
import { useAct } from "../toast.tsx";
import type { DriveEntry, DriveRoot } from "../core/shapes.ts";
import { Button, Confirm, Dialog, ICON, IconButton, Menu, Tip, type MenuItem } from "../ui.tsx";
import { ChevronLeft, ChevronRight, Close, Download, Edit, Folder, FolderPlus, Plus, Refresh, Retry, Trash, Upload } from "../icons.tsx";
import { KindIcon } from "../drive/KindIcon.tsx";
import { Reader } from "../drive/Reader.tsx";
import { Player } from "../drive/Player.tsx";
import { cancel, download, joinPath, nameOf, openerOf, parentOf, refresh, retry, rootLabel, settle, sizeOf, upload, useFolder, useUploads, type At, type Upload as Up } from "../drive/model.ts";
import { childOf, drive, drivePath, nameProblem, rootTrouble, useDrive, type DriveState } from "../drive/useDrive.ts";
import { DrivePreview, useFolders } from "../mobile/Drive.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as shellCss from "../styles/shell.css.ts";
import * as controlsCss from "../styles/controls.css.ts";
import * as waitingCss from "../styles/waiting.css.ts";
import * as css from "./Drive.css.ts";
import { t } from "../i18n.ts";

export function DrivePage() {
  const station = useStation();
  const [q] = useSearchParams();
  const d = useDrive(station.address);
  const asked = q.get("root");
  const path = q.get("path") ?? "";
  const only = d.roots.length === 1 && d.roots[0]!.state === "ok" ? d.roots[0]!.path : null;
  const root = asked ?? only;
  return (
    <div className={`${pagesCss.page} ${pagesCss.pageNarrow} ${css.page}`}>
      {d.loading || !d.offered || root === null ? <Roots d={d} /> : <FolderView d={d} root={root} path={path} />}
    </div>
  );
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
        {d.manage && d.offered && d.roots.length > 0 && <div className={css.actions}><Menu items={[{ label: t("web-pages.drive.manage"), icon: Folder, onSelect: manage.open }]} /></div>}
      </header>
      {d.loading ? <p className={shellCss.muted}>{d.error ?? t("web-pages.drive.reading")}</p>
        : !d.offered ? <Empty text={t("web-pages.drive.oldStation")} />
        : d.roots.length === 0 ? (
          <Empty text={d.manage ? t("web-pages.drive.noneManage") : t("web-pages.drive.noneMember")}
            action={d.manage ? <Button variant="primary" icon={Folder} onClick={manage.pick}>{t("web-pages.drive.pick")}</Button> : undefined} />
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
    <button type="button" className={css.row} onClick={onOpen}>
      <Folder size={20} strokeWidth={1.6} className={css.icon} />
      <span className={css.text}>
        <span className={css.name}>{root.name}</span>
        <span className={css.meta}>{root.path}</span>
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
  const [naming, setNaming] = useState<{ entry: DriveEntry | null } | null>(null);
  const [removing, setRemoving] = useState<DriveEntry | null>(null);
  const [preview, setPreview] = useState<DriveEntry | null>(null);
  const [dragging, setDragging] = useState(false);
  const name = path ? nameOf(path) : rootLabel(d.roots, root);
  const reload = () => {
    if (refreshing) return;
    setRefreshing(true);
    act(refresh(at).finally(() => setRefreshing(false)), t("web-pages.drive.refreshWhat"));
  };
  const open = (e: DriveEntry) => {
    const full = joinPath(path, e.name);
    switch (openerOf(e.kind)) {
      case "folder": return go(drivePath(station.base, root, full));
      case "read": return go(drivePath(station.base, root, full, "read"));
      case "play": return go(drivePath(station.base, root, full, "play"));
      case "preview": return setPreview(e);
      default: return save(e);
    }
  };
  const save = (e: DriveEntry) => act(download({ ...at, path: joinPath(path, e.name) }, e), t("web-pages.drive.downloadWhat"));
  const items = (e: DriveEntry): MenuItem[] => [
    { label: t("web-pages.drive.open"), onSelect: () => open(e) },
    ...(e.dir ? [] : [{ label: t("web-pages.drive.download"), icon: Download, onSelect: () => save(e) }]),
    ...(d.write ? [
      { label: t("web-pages.drive.rename"), icon: Edit, onSelect: () => setNaming({ entry: e }) },
      { label: t("web-pages.drive.delete"), icon: Trash, danger: true, onSelect: () => setRemoving(e) },
    ] : []),
  ];
  // ⌘/Ctrl+U puts files up into the folder shown.
  useEffect(() => {
    if (!d.write) return;
    const onKey = (e: KeyboardEvent) => { if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "u") { e.preventDefault(); files.current?.click(); } };
    addEventListener("keydown", onKey);
    return () => removeEventListener("keydown", onKey);
  }, [d.write]);
  const trail = path.split("/").filter(Boolean);
  return (
    <>
      <header className={pagesCss.pageHead}>
        <div className={css.headText}>
          <span className={css.crumbs}>
            <span>{station.name}</span>
            <ChevronRight size={12} />
            {/* With one folder lent, the drive's page is that folder: the trail starts at it. */}
            {d.roots.length > 1 ? <button type="button" onClick={() => go(drivePath(station.base, null))}>{t("web-pages.drive.title")}</button> : <span>{t("web-pages.drive.title")}</span>}
            {trail.length > 0 && <span className={css.crumb}><ChevronRight size={12} /><button type="button" onClick={() => go(drivePath(station.base, root))}>{rootLabel(d.roots, root)}</button></span>}
            {trail.slice(0, -1).map((p, i) => (
              <span key={i} className={css.crumb}><ChevronRight size={12} /><button type="button" onClick={() => go(drivePath(station.base, root, trail.slice(0, i + 1).join("/")))}>{p}</button></span>
            ))}
          </span>
          <h1>{name}</h1>
        </div>
        <div className={css.actions}>
          <span className={css.spin} data-on={refreshing || undefined}><IconButton label={t("web-pages.drive.refresh")} icon={Refresh} onClick={reload} /></span>
          {d.write && (
            <DropdownMenu.Root modal={false}>
              <DropdownMenu.Trigger asChild><Button variant="primary" icon={Plus}>{t("web-pages.drive.new")}</Button></DropdownMenu.Trigger>
              <DropdownMenu.Portal>
                <DropdownMenu.Content className={`${controlsCss.popover} ${controlsCss.menuList}`} align="end" sideOffset={4} collisionPadding={8}>
                  <DropdownMenu.Item className={controlsCss.menuItem} onSelect={() => files.current?.click()}><Upload {...ICON} />{t("web-pages.drive.upload")}</DropdownMenu.Item>
                  <DropdownMenu.Item className={controlsCss.menuItem} onSelect={() => setNaming({ entry: null })}><FolderPlus {...ICON} />{t("web-pages.drive.mkdir")}</DropdownMenu.Item>
                </DropdownMenu.Content>
              </DropdownMenu.Portal>
            </DropdownMenu.Root>
          )}
          {d.manage && <Menu items={[{ label: t("web-pages.drive.manage"), icon: Folder, onSelect: manage.open }]} />}
        </div>
      </header>
      <div className={css.list} data-dragging={dragging || undefined}
        onDragOver={(e) => { if (d.write && e.dataTransfer.types.includes("Files")) { e.preventDefault(); e.dataTransfer.dropEffect = "copy"; setDragging(true); } }}
        onDragLeave={(e) => { if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setDragging(false); }}
        onDrop={(e) => { if (!d.write || !e.dataTransfer.files.length) return; e.preventDefault(); setDragging(false); upload(station.address, root, path, [...e.dataTransfer.files]); }}>
        {folder.error ? (
          <div className={css.problem}><p className={controlsCss.fieldError}>{folder.error.message}</p><Button variant="ghost" icon={Retry} onClick={reload}>{t("web-pages.drive.retry")}</Button></div>
        ) : !folder.value ? <p className={shellCss.muted}>{t("web-pages.drive.reading")}</p> : (
          <>
            <p className={css.count}>{folder.value.countText}{folder.value.truncated ? ` · ${t("web-pages.drive.truncated")}` : ""}{d.write ? ` · ${t("web-pages.drive.dropHint")}` : ""}</p>
            {uploads.map((u) => <UploadRow key={u.key} u={u} />)}
            {entries.length === 0 && uploads.length === 0 && <Empty text={t("web-pages.drive.emptyFolder")} action={d.write ? <Button icon={Upload} onClick={() => files.current?.click()}>{t("web-pages.drive.upload")}</Button> : undefined} />}
            {entries.map((e) => <EntryRow key={e.name} at={at} entry={e} items={items(e)} onOpen={() => open(e)} />)}
          </>
        )}
        {dragging && <div className={css.drop}><Upload size={22} /><span>{t("web-pages.drive.dropHere", { name })}</span></div>}
      </div>
      <input ref={files} type="file" multiple hidden onChange={(e) => { const list = [...(e.target.files ?? [])]; e.target.value = ""; if (list.length) upload(station.address, root, path, list); }} />
      {naming && <NameDialog at={at} entry={naming.entry} onClose={() => setNaming(null)} />}
      <Confirm open={removing !== null} onClose={() => setRemoving(null)}
        title={removing ? t(removing.dir ? "web-pages.drive.deleteFolderAsk" : "web-pages.drive.deleteAsk", { name: removing.name }) : ""}
        description={removing?.dir ? t("web-pages.drive.deleteFolderText") : t("web-pages.drive.deleteText")} action={t("web-pages.drive.delete")}
        onConfirm={() => { const e = removing; setRemoving(null); if (e) act(drive.remove(at, e), t("web-pages.drive.deleteWhat")); }} />
      {preview && <DrivePreview at={at} entries={entries} entry={preview} onClose={() => setPreview(null)} />}
      {manage.dialogs}
    </>
  );
}

function EntryRow({ at, entry, items, onOpen }: { at: At; entry: DriveEntry; items: MenuItem[]; onOpen: () => void }) {
  const full = joinPath(at.path, entry.name);
  const removing = useDoing("drive.remove", { station: at.station, root: at.root, path: full });
  const renaming = useDoing("drive.rename", { station: at.station, root: at.root, from: full });
  const busy = removing || renaming;
  const row = (
    <div className={css.entry} data-busy={busy || undefined}>
      <button type="button" className={css.row} onClick={onOpen} disabled={busy}>
        <KindIcon kind={entry.kind} size={20} className={css.icon} />
        <span className={css.name}>{entry.name}</span>
        <span className={css.size}>{entry.dir ? "" : entry.sizeText}</span>
        <span className={css.time}>{entry.timeText}</span>
      </button>
      <span className={css.more}>{busy ? <span className={`${waitingCss.spinner} ${controlsCss.iconSpinner}`} aria-hidden="true" /> : <Menu items={items} />}</span>
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

/** The station's folders from its home, entered by a click; the one shown lent with 选这个文件夹. */
function PickerDialog({ station, roots, onClose }: { station: string; roots: DriveRoot[]; onClose: () => void }) {
  const act = useAct();
  const picker = useFolders(station);
  const taken = picker.value ? roots.some((r) => r.path === picker.value!.path) : false;
  return (
    <Dialog open wide onClose={onClose} title={t("web-pages.drive.pick")} description={t("web-pages.drive.pickNote")}
      footer={<><Button variant="ghost" onClick={onClose}>{t("common.cancel")}</Button><Button variant="primary" disabled={!picker.value || taken} onClick={() => {
        const path = picker.value!.path;
        onClose();
        act(drive.setRoots(station, [...roots.map((r) => r.path), path]), t("web-pages.drive.rootsWhat"), t("web-pages.drive.shared", { name: path.split(/[/\\]/).filter(Boolean).at(-1) ?? path }));
      }}>{taken ? t("web-pages.drive.already") : t("web-pages.drive.pickThis")}</Button></>}>
      <div className={css.pickerPath}>
        <Tip label={t("web-pages.drive.up")}><span><IconButton label={t("web-pages.drive.up")} icon={ChevronLeft} disabled={!picker.value?.parent} onClick={() => picker.go(picker.value?.parent ?? null)} /></span></Tip>
        <code>{picker.value?.path ?? "…"}</code>
      </div>
      <div className={css.pickerList}>
        {picker.error ? <p className={controlsCss.fieldError}>{picker.error}</p>
          : !picker.value ? <p className={shellCss.muted}>{t("web-pages.drive.reading")}</p>
          : picker.value.folders.length === 0 ? <p className={shellCss.muted}>{t("web-pages.drive.noSubfolders")}</p>
          : picker.value.folders.map((f) => (
            <button key={f} type="button" className={css.row} onClick={() => picker.go(childOf(picker.value!.path, f))}>
              <Folder size={18} strokeWidth={1.6} className={css.icon} /><span className={css.name}>{f}</span><ChevronRight {...ICON} className={shellCss.muted} />
            </button>
          ))}
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
  return { station, root, path, folderPath, folder, entry, back, at: { station: station.address, root, path } };
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
      {o.entry ? <Reader key={o.path} at={o.at} name={o.entry.name} size={o.entry.size} mtime={o.entry.mtime} markdown={o.entry.kind === "markdown"} backLabel={o.back} onBack={back} />
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
      {o.entry ? <Player key={o.path} at={o.at} entry={o.entry} siblings={o.folder.value?.entries ?? []} backLabel={o.back} onBack={back}
        onGo={(name) => go(drivePath(o.station.base, o.root, joinPath(o.folderPath, name), "play"), { replace: true })} />
        : <p className={`${css.openedNote} ${o.folder.error || o.folder.value ? controlsCss.fieldError : shellCss.muted}`}>{o.folder.error?.message ?? (o.folder.value ? t("web-pages.drive.gone") : t("web-pages.drive.reading"))}</p>}
    </div>
  );
}
