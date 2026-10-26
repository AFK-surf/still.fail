// The files' sidebar (docs/drive.md "The files' page"), as Finder's: the person's own folders kept at hand (个人收藏, of any
// station: drive/favorites.ts), then every station of the workspace with a drive, a row each (online or not, whether it
// is this machine, how full its disk is), opened to its places (its home, the home's own folders, its disks), then the
// folders the stations pin for everyone (团队共享). A row opens its folder in the side in front; something dragged onto
// one goes into it (drive/transfer.ts: across stations a copy, ⌘ a move; within one a move, ⌥ a copy), and a folder
// dragged onto 个人收藏 is kept there.
import { useEffect, useState, type DragEvent, type ReactNode } from "react";
import { useLocation } from "react-router";
import { useDriveStations, useStations } from "../api.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import type { StationView } from "../core/shapes.ts";
import { stationBase } from "../station.tsx";
import { ICON, Tip } from "../ui.tsx";
import { StationMark } from "../StationMark.tsx";
import { StationNamed } from "../StationNamed.tsx";
import { ChevronRight, Close, Disk, Folder, Pin, Plus, Server, Star } from "@stillfail/ui/icons.tsx";
import { NavAction, NavItem, NavList, NavSection, NavTop } from "../SidebarList.tsx";
import { drive, drivePath, folderName, type PickFolder } from "../drive/useDrive.ts";
import { carriesDrive, draggedNow, droppedOf } from "../drive/drag.ts";
import { effectOf, takes } from "../drive/browse.ts";
import { transfer } from "../drive/transfer.ts";
import { useFavorites } from "../drive/favorites.ts";
import { modsOf } from "./DriveViews.tsx";
import { useAddFolder } from "./Drive.tsx";
import * as css from "./FilesNav.css.ts";
import { t } from "../i18n.ts";

/** What a station's overview says of its drive, for the viewer. */
const driveOf = (s: StationView) => s.overview?.drive;
const writes = (s: StationView) => s.overview?.viewer?.role !== "viewer";

/** A folder something can be dropped on: what it takes, the drop, and whether something it takes is over it. */
function useFolderDrop(s: StationView, root: string, path: string, name: string): { over: false | "copy" | "move"; props: Record<string, (e: DragEvent) => void> } {
  const act = useAct();
  const [over, setOver] = useState<false | "copy" | "move">(false);
  const d = driveOf(s);
  if (!d || !writes(s)) return { over: false, props: {} };
  const at = { station: s.station, root, path };
  const ok = (e: DragEvent) => carriesDrive(e.dataTransfer) && takes(e.dataTransfer, s.station, draggedNow(), d.transfers === true);
  return {
    over,
    props: {
      onDragOver: (e) => {
        if (!ok(e)) return;
        e.preventDefault();
        e.stopPropagation();
        const effect = effectOf(e.dataTransfer, s.station, draggedNow(), modsOf(e));
        e.dataTransfer.dropEffect = effect;
        setOver(effect);
      },
      onDragLeave: (e) => { if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setOver(false); },
      onDrop: (e) => {
        setOver(false);
        if (!ok(e)) return;
        e.preventDefault();
        e.stopPropagation();
        const move = effectOf(e.dataTransfer, s.station, draggedNow(), modsOf(e)) === "move";
        act(transfer(droppedOf(e.dataTransfer), at, move, name, d.anywhere === true), t(move ? "web-pages.drive.moveWhat" : "web-pages.files.copyWhat"));
      },
    },
  };
}

/** A folder's row: opens it, takes what is dropped on it. */
function FolderRow({ s, root, path, name, mark, end, lit, away, children }: {
  s: StationView; root: string; path: string; name: string; mark: ReactNode; end?: ReactNode; lit: boolean; away: boolean; children?: ReactNode;
}) {
  const drop = useFolderDrop(s, root, path, name);
  return (
    <div className={css.drop} data-over={drop.over || undefined} {...drop.props}>
      <NavItem to={drivePath(stationBase(s.station), root, path)} current={lit} tip={path ? `${root}/${path}` : root} mark={mark} title={name} end={end} away={away} />
      {children}
      {drop.over && <span className={css.dropSays}>{t(drop.over === "move" ? "web-pages.files.moveHereShort" : "web-pages.files.copyHereShort")}</span>}
    </div>
  );
}

/** How full a station's disk is: a short bar, amber past 90%. */
function DiskBar({ s }: { s: StationView }) {
  const disk = s.overview?.disk;
  if (!disk || disk.totalBytes <= 0) return null;
  const used = 1 - disk.freeBytes / disk.totalBytes;
  const label = t("web-pages.files.diskLeft", { free: `${(disk.freeBytes / 1e9).toFixed(disk.freeBytes >= 1e11 ? 0 : 1)} GB`, percent: Math.round(used * 100) });
  return (
    <Tip label={label}>
      <span className={css.disk} data-full={used >= 0.9 || undefined} role="img" aria-label={label}><span style={{ transform: `scaleX(${used})` }} /></span>
    </Tip>
  );
}

/** A station's places as its drive offers them to a member who browses everywhere (its home, the home's own folders,
 * its disks), read as its row opens. */
function usePlaces(station: string, open: boolean, anywhere: boolean): PickFolder[] | null {
  const [places, setPlaces] = useState<PickFolder[] | null>(null);
  useEffect(() => {
    if (!open || !anywhere || places !== null) return;
    let live = true;
    drive.folders(station, null).then((f) => { if (live) setPlaces(f.places); }, () => { if (live) setPlaces([]); });
    return () => { live = false; };
  }, [open, anywhere, station, places]);
  return places;
}

/** A station's row: opens its home (or the folder it pins, for a read-only member); its places under it, opened. */
function StationRow({ s, lit, root, path }: { s: StationView; lit: (station: string, root: string, path: string) => boolean; root: string | null; path: string }) {
  const d = driveOf(s)!;
  const [open, setOpen] = useState(false);
  const places = usePlaces(s.station, open, d.anywhere === true);
  const start = d.anywhere && d.home ? d.home : d.roots[0]?.path ?? null;
  const shownPlaces: { name: string; path: string; disk?: boolean }[] = d.anywhere ? (places ?? []) : d.roots.map((r) => ({ name: r.name, path: r.path }));
  const inThis = root !== null && lit(s.station, root, path);
  return (
    <div className={css.station}>
      <div className={css.stationLine}>
        <button type="button" className={css.disclosure} data-open={open || undefined} aria-expanded={open} aria-label={t(open ? "web-pages.files.collapse" : "web-pages.files.expand", { name: s.name })}
          onClick={() => setOpen(!open)}><ChevronRight size={12} strokeWidth={2} /></button>
        {start !== null ? (
          <FolderRow s={s} root={start} path="" name={s.name} lit={inThis && root === start && path === ""} away={!s.online}
            mark={s.emoji || s.icon ? <StationMark emoji={s.emoji} icon={s.icon} size={ICON.size} /> : <Server {...ICON} />}
            end={s.online ? <DiskBar s={s} /> : <span>{t("web-pages.stations.offline")}</span>} />
        ) : <span className={css.stationName}><StationNamed emoji={s.emoji} icon={s.icon} name={s.name} /></span>}
      </div>
      {open && (
        <div className={css.places}>
          {d.anywhere && places === null && <p className={css.reading}>{t("web-pages.files.reading")}</p>}
          {shownPlaces.map((p) => (
            <FolderRow key={p.path} s={s} root={p.path} path="" name={p.name} lit={lit(s.station, p.path, "")} away={!s.online}
              mark={p.disk ? <Disk {...ICON} /> : <Folder {...ICON} />} />
          ))}
        </div>
      )}
    </div>
  );
}

/** The files' sidebar for the workspace `scope`. */
export function FilesNav({ scope, top }: { scope: string; top?: ReactNode }) {
  const views = useStations(scope).value ?? [];
  const where = useLocation();
  const q = new URLSearchParams(where.search);
  const root = q.get("root");
  const path = q.get("path") ?? "";
  const shownStation = /^\/w\/[^/]+\/s\/([^/]+)\/files/.exec(where.pathname)?.[1];
  const lit = (station: string, r: string, p: string) => shownStation !== undefined && station.endsWith(`/${shownStation}`) && root === r && path === p;
  const add = useAddFolder(scope);
  const fav = useFavorites(scope);
  // Those with a drive, as the workspace lists them.
  const stations = useDriveStations(scope).value ?? [];
  const pinned = views.flatMap((s) => (driveOf(s)?.roots ?? []).map((r) => ({ s, r })));
  const [keeping, setKeeping] = useState(false);
  // A folder dragged onto 个人收藏: kept there.
  const keepDrop = {
    onDragOver: (e: DragEvent) => { if (!carriesDrive(e.dataTransfer)) return; e.preventDefault(); e.dataTransfer.dropEffect = "copy"; setKeeping(true); },
    onDragLeave: (e: DragEvent) => { if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setKeeping(false); },
    onDrop: (e: DragEvent) => {
      setKeeping(false);
      if (!carriesDrive(e.dataTransfer)) return;
      e.preventDefault();
      for (const d of droppedOf(e.dataTransfer)) if (d.dir) fav.add({ station: d.station, root: d.abs, path: "", name: d.name });
    },
  };
  return (
    <>
      <NavTop top={top} action={add.can && <NavAction icon={<Plus {...ICON} />} label={t("web-pages.drive.addRoot")} onClick={add.start} />} />
      <NavList>
        {stations.length === 0 && <p className={css.empty}>{t("web-main.rail.filesNone")}</p>}
        <div className={css.keep} data-over={keeping || undefined} {...keepDrop}>
          <NavSection title={t("web-pages.files.favorites")}>
            {fav.list.length === 0 && <p className={css.hint}><Star {...ICON} />{t("web-pages.files.favoritesHint")}</p>}
            {fav.list.map((f) => {
              const s = views.find((v) => v.station === f.station);
              if (!s) return null;
              return (
                <div key={`${f.station}\n${f.root}\n${f.path}`} className={css.favorite}>
                  <FolderRow s={s} root={f.root} path={f.path} name={f.name} lit={lit(f.station, f.root, f.path)} away={!s.online} mark={<Folder {...ICON} />} end={<span><StationNamed emoji={s.emoji} icon={s.icon} name={s.name} /></span>} />
                  <button type="button" className={css.unkeep} aria-label={t("web-pages.files.unfavorite", { name: f.name })} onClick={() => fav.remove(f)}><Close size={12} strokeWidth={2} /></button>
                </div>
              );
            })}
          </NavSection>
        </div>
        {stations.length > 0 && (
          <NavSection title="Station">
            {stations.map((s) => <StationRow key={s.station} s={s} lit={lit} root={root} path={path} />)}
          </NavSection>
        )}
        {pinned.length > 0 && (
          <NavSection title={t("web-pages.files.shared")}>
            {pinned.map(({ s, r }) => (
              <FolderRow key={`${s.station}\n${r.path}`} s={s} root={r.path} path="" name={r.name || folderName(r.path)} lit={lit(s.station, r.path, "")} away={!s.online}
                mark={<Pin {...ICON} />} end={<span><StationNamed emoji={s.emoji} icon={s.icon} name={s.name} /></span>} />
            ))}
          </NavSection>
        )}
        {add.dialogs}
      </NavList>
    </>
  );
}
