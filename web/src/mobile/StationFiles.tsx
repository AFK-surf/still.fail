// A phone's way to put a station's files into a message (the wide screen drags them from a chat's 文件 tab, ../pages/
// DriveTab.tsx): ＋'s Station 文件 opens the places (each station's home, for a member who browses every folder, and
// its folders pinned), a folder entered by a tap, the way back as crumbs; files ticked (and the folder shown, as a
// whole), then 添加. They go in named by their path, or as files where the chat says so (../draft.ts addDropped), as
// dragged ones do. A card of one in the composer, tapped, says where it is and switches how it goes (RefSheet).
import { useState } from "react";
import { useStations } from "../api.ts";
import type { DriveEntry, StationView } from "../core/shapes.ts";
import type { Dropped, Pending } from "../draft.ts";
import { draggedOf, droppedFrom } from "../drive/drag.ts";
import { KindIcon } from "../drive/KindIcon.tsx";
import { joinPath, useFolder, type At } from "../drive/model.ts";
import { absoluteOf, folderName, rootTrouble } from "../drive/useDrive.ts";
import { ChevronRight, Folder, Server } from "@stillfail/ui/icons.tsx";
import { fileSize } from "@stillfail/ui/fileSize.ts";
import { SheetGrab, SheetHead, type MobileApp } from "./app.tsx";
import { Button, Loading, PickRow, SectionHeader, Seg } from "./parts.tsx";
import * as css from "./Drive.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as sheetsCss from "./styles/sheets.css.ts";
import * as connectsCss from "./Connects.css.ts";
import * as own from "./StationFiles.css.ts";
import { t } from "../i18n.ts";

/** Where the picker is: a folder of a station (its root, a path under it), or the places (null). */
type Place = { station: string; stationName: string; root: string; rootName: string; path: string } | null;

/** ＋'s Station 文件: the workspace's stations' files, to tick and add to the message (`onAdd`). */
export function openStationFiles(app: MobileApp, chatStation: string, onAdd: (items: Dropped[]) => void): void {
  app.sheet({ height: 0.86, draggable: true, content: () => <Picker scope={chatStation.split("/")[0] ?? ""} onAdd={(items) => { app.sheet(null); onAdd(items); }} onCancel={() => app.sheet(null)} /> });
}

function Picker({ scope, onAdd, onCancel }: { scope: string; onAdd: (items: Dropped[]) => void; onCancel: () => void }) {
  const [place, setPlace] = useState<Place>(null);
  // What is ticked, by where it is (a station's, and the path there), in the order ticked.
  const [ticked, setTicked] = useState<Map<string, Dropped>>(new Map());
  const keyOf = (d: Dropped) => `${d.ref.station}\n${d.ref.path}`;
  const toggle = (d: Dropped) => setTicked((was) => {
    const next = new Map(was);
    if (next.has(keyOf(d))) next.delete(keyOf(d)); else next.set(keyOf(d), d);
    return next;
  });
  const crumbs = place === null ? [] : [
    { name: place.rootName, path: "" },
    ...place.path.split("/").filter(Boolean).map((part, i, all) => ({ name: part, path: all.slice(0, i + 1).join("/") })),
  ];
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-pages.chat.files")} />
      <div className={`${css.mCrumbs} ${css.mPickerCrumbs}`} ref={(el) => { if (el) el.scrollLeft = el.scrollWidth; }}>
        <span className={css.mCrumb}>
          {place === null ? <b>{t("web-mobile.files.places")}</b> : <button type="button" onClick={() => setPlace(null)}>{t("web-mobile.files.places")}</button>}
        </span>
        {place && crumbs.map((c, i) => (
          <span key={c.path} className={css.mCrumb}>
            <ChevronRight size={12} className={partsCss.mSubtle} />
            {i === crumbs.length - 1 ? <b>{i === 0 ? `${place.stationName} · ${c.name}` : c.name}</b>
              : <button type="button" onClick={() => setPlace({ ...place, path: c.path })}>{i === 0 ? `${place.stationName} · ${c.name}` : c.name}</button>}
          </span>
        ))}
      </div>
      <div className={sheetsCss.mSheetScroll}>
        {place === null
          ? <Places scope={scope} onGo={setPlace} />
          : <FolderRows key={`${place.station}\n${place.root}\n${place.path}`} place={place} ticked={(d) => ticked.has(keyOf(d))} onToggle={toggle}
            onEnter={(name) => setPlace({ ...place, path: joinPath(place.path, name) })} />}
      </div>
      <div className={css.mPickerFoot}>
        <Button label={t("common.cancel")} primary={false} onClick={onCancel} />
        <Button label={ticked.size ? t("web-mobile.files.addCount", { n: ticked.size }) : t("web-mobile.files.add")} primary enabled={ticked.size > 0} onClick={() => onAdd([...ticked.values()])} />
      </div>
    </>
  );
}

/** Each station's places: its home (for a member who browses every folder), then its folders pinned. */
function Places({ scope, onGo }: { scope: string; onGo: (place: Place) => void }) {
  const stations = useStations(scope);
  const list = (stations.value ?? []).filter((s) => s.overview?.drive);
  if (stations.loading && !stations.value) return <Loading text={t("web-mobile.reading")} />;
  if (!list.length) return <p className={`${partsCss.mMuted} ${css.mSheetNote}`}>{t("web-main.rail.filesNone")}</p>;
  return <>{list.map((s) => <StationPlaces key={s.station} s={s} onGo={onGo} />)}</>;
}

function StationPlaces({ s, onGo }: { s: StationView; onGo: (place: Place) => void }) {
  const drive = s.overview!.drive!;
  const go = (root: string, rootName: string) => onGo({ station: s.station, stationName: s.name, root, rootName, path: "" });
  return (
    <>
      <SectionHeader title={s.name} trailing={s.online ? undefined : t("web-pages.stations.offline")} />
      {drive.anywhere && drive.home && <PickRow label={t("web-pages.drive.home")} sub={drive.home} leading={<Server size={20} />} onClick={() => go(drive.home!, t("web-pages.drive.home"))} />}
      {drive.roots.map((r) => {
        const trouble = rootTrouble(r);
        return <PickRow key={r.path} label={r.name} sub={trouble?.text ?? r.path} leading={<Folder size={20} />} onClick={() => go(r.path, r.name)} />;
      })}
    </>
  );
}

/** A folder: the folder itself to tick as a whole, then what is in it (a folder entered, a file ticked). */
function FolderRows({ place, ticked, onToggle, onEnter }: {
  place: NonNullable<Place>; ticked: (d: Dropped) => boolean; onToggle: (d: Dropped) => void; onEnter: (name: string) => void;
}) {
  const folder = useFolder(place.station, place.root, place.path);
  const at: At = { station: place.station, root: place.root, path: place.path };
  const of = (e: DriveEntry) => droppedFrom(draggedOf(at, e, place.stationName));
  // The folder shown, as one of its parent's entries would be.
  const here: Dropped = {
    name: place.path ? folderName(place.path) : place.rootName, size: 0,
    ref: { station: place.station, stationName: place.stationName, path: absoluteOf(place.root, place.path), dir: true },
  };
  const entries = folder.value?.entries ?? [];
  return (
    <>
      <PickRow label={t("web-mobile.files.wholeFolder")} sub={here.ref.path} leading={<Folder size={20} />} checked={ticked(here)} onClick={() => onToggle(here)} />
      <div className={own.rule} />
      {folder.error ? <p className={`${partsCss.mRed} ${css.mSheetNote}`}>{folder.error.message}</p>
        : !folder.value ? <Loading text={t("web-mobile.reading")} />
        : entries.length === 0 ? <p className={`${partsCss.mMuted} ${css.mSheetNote}`}>{t("web-pages.drive.emptyFolder")}</p>
        : entries.map((e) => e.dir
          ? <PickRow key={e.name} label={e.name} sub={e.timeText} leading={<KindIcon kind={e.kind} size={20} />} onClick={() => onEnter(e.name)} />
          : <PickRow key={e.name} label={e.name} sub={[e.sizeText || fileSize(e.size), e.timeText].filter(Boolean).join(" · ")} leading={<KindIcon kind={e.kind} size={20} />} checked={ticked(of(e))} onClick={() => onToggle(of(e))} />)}
    </>
  );
}

/**
 * A file of a station's in the composer, tapped (the wide screen's card shows this on hover, ../Chat.tsx RefCard): its
 * name, where it is, how it goes (its path, or the file; a folder of the chat's own station as a zip), and whether this
 * chat takes such files as files.
 */
export function openRefSheet(app: MobileApp, f: Pending, how: { zips: boolean; setMode: (mode: "path" | "file") => void; asFiles: boolean; setAsFiles: (on: boolean) => void }): void {
  app.sheet({ height: 0.42, content: () => <RefSheet f={f} {...how} /> });
}

function RefSheet({ f, zips, setMode, asFiles, setAsFiles }: { f: Pending; zips: boolean; setMode: (mode: "path" | "file") => void; asFiles: boolean; setAsFiles: (on: boolean) => void }) {
  const ref = f.ref!;
  // Shown as switched at once; the draft is told (and comes back the same).
  const [mode, setShown] = useState(ref.mode);
  const [chat, setChat] = useState(asFiles);
  const where = ref.path.slice(0, Math.max(ref.path.lastIndexOf("/"), ref.path.lastIndexOf("\\"))) || ref.path;
  return (
    <>
      <SheetGrab />
      <SheetHead title={f.name} />
      <div className={sheetsCss.mSheetScroll}>
        <p className={`${partsCss.mMuted} ${own.where}`}><bdi>{ref.stationName} · {where}</bdi></p>
        {(!ref.dir || zips) && (
          <div className={own.block}>
            <span className={own.label}>{t("web-main.file.sendAs")}</span>
            <Seg fill options={[t("web-main.file.modePath"), t(ref.dir ? "web-main.file.modeZip" : "web-main.file.modeFile")]} selected={mode === "path" ? 0 : 1}
              onSelect={(i) => { const next = i === 0 ? "path" : "file"; setShown(next); setMode(next); }} />
          </div>
        )}
        <div className={own.block}>
          <button type="button" className={connectsCss.mSwitchRow} onClick={() => { setChat(!chat); setAsFiles(!chat); }}>
            <span className={partsCss.mGrow}><b>{t("web-main.file.chatAsFiles")}</b></span>
            <span className={connectsCss.mSwitch} data-on={chat || undefined} />
          </button>
        </div>
      </div>
    </>
  );
}
