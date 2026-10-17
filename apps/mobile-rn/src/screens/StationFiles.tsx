// A station's files put into a message, as the phone's web does (web/src/mobile/StationFiles.tsx; the wide screen drags
// them from a chat's 文件 tab): ＋'s Station 文件 opens the places (each station's home, for a member who browses every
// folder, and its folders pinned), a folder entered by a tap, the way back as crumbs; files ticked (and the folder shown,
// as a whole), then 添加. Each goes in named by its path (which station has it, and where: the message says so, nothing
// goes up), or as a file where the chat says so; its card, tapped, switches that (a folder of the chat's own station
// goes as a zip). A file goes up as the station stages it (`drive.stage`) on the chat's station, else read from its own
// and sent up.
import { useEffect, useMemo, useRef, useState } from "react";
import { FlatList, Pressable, ScrollView, View, type FlatList as FlatListType } from "react-native";
import Svg, { Rect } from "react-native-svg";
import type { DriveEntry, DriveFolder, StationView } from "../../../../web/src/core/shapes.ts";
import { useTopic } from "../../../../web/src/core/react.ts";
import { CoreError } from "../../../../web/src/core/client.ts";
import { SheetSpec, type AppState } from "../AppState";
import { Topics } from "../data/Topics";
import { arranged } from "../data/Drives";
import { DriveCache } from "../data/DriveCache";
import { t } from "../i18n";
import { Icon, Icons } from "../ui/Icon";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";
import { chatInk } from "../ui/ChatInk";
import { Button, PickRow, fileSize, kindIcon } from "../ui/Controls";
import { SectionHeader, Seg } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { Spinner, Waiting } from "../ui/Waiting";
import { Switch } from "./Connects";
import { Pending, uploadingText, type Draft } from "./Composer";
import { byteSourceOf } from "./ChatFiles";

/**
 * A file or folder of a station's in a draft: which station has it (`station`, its name `stationName`), where (`path`,
 * as the station names it), and how it goes (`mode`: "path", named; "file", sent). `root` and `at`: where it is in that
 * station's drive, to send it as a file.
 */
export class RefFile {
  constructor(readonly station: string, readonly stationName: string, readonly path: string, readonly dir: boolean, readonly root: string, readonly at: string, public mode: string) {}
}

/** Where a file named by its path is, as the message says it (the core's words for it, composer.ts `pathWords`). */
export function pathWords(ref: RefFile): string {
  return t(ref.dir ? "common.folderOn" : "common.pathOn", { station: ref.stationName, path: ref.path });
}

/** The draft's key the chat's say is kept by ("<station>:<chat>", as the web keys it). */
const chatKey = (draft: Draft, station: string) => draft.keptAs ?? `new:${station}`;

/** A place of a station's drive: the station, a root, a path under it. */
interface Place { station: string; stationName: string; root: string; rootName: string; path: string }

/** What is ticked: a file of a folder, or the folder shown, as a whole. */
class Ticked {
  constructor(readonly station: string, readonly stationName: string, readonly root: string, readonly at: string, readonly name: string, readonly size: number, readonly dir: boolean) {}
  get path() { return absoluteOf(this.root, this.at); }
  get key() { return `${this.station}\n${this.path}`; }
}

const absoluteOf = (root: string, path: string) => (path.length === 0 ? root : root.replace(/[/\\]+$/, "") + "/" + path);
const joinIn = (dir: string, name: string) => (dir.length === 0 ? name : `${dir}/${name}`);
const ripple = (ink: string) => ({ color: withAlpha(ink, 0.1), borderless: false });

/** ＋'s Station 文件: the workspace's stations' files, to tick and add to `draft` (its chat on `station`). */
export function openStationFiles(app: AppState, draft: Draft, station: string) {
  app.sheet = new SheetSpec(0.86, true, null, null, false, () => <StationFilesSheet app={app} draft={draft} station={station} />);
}

function StationFilesSheet({ app, draft, station }: { app: AppState; draft: Draft; station: string }) {
  const [place, setPlace] = useState<Place | null>(null);
  const [ticked, setTicked] = useState<ReadonlyMap<string, Ticked>>(new Map());
  // How far each folder was scrolled, for one gone back to.
  const scrolls = useRef(new Map<string, number>()).current;
  const toggle = (x: Ticked) => setTicked((was) => { const next = new Map(was); if (!next.delete(x.key)) next.set(x.key, x); return next; });
  const p = place;
  return (
    <View style={{ flex: 1 }}>
      <SheetGrab />
      <SheetHead title={t("web-pages.chat.files")} />
      <Crumbs place={place} onGo={setPlace} />
      <View style={{ flex: 1 }}>
        {p === null ? <Places scope={station.split("/")[0]!} onGo={setPlace} />
          : <FolderRows key={`${p.station}\n${p.root}\n${p.path}`} app={app} p={p} scrolls={scrolls} ticked={(x) => ticked.has(x.key)} onToggle={toggle}
            onEnter={(name) => setPlace({ ...p, path: joinIn(p.path, name) })} />}
      </View>
      <View style={{ flexDirection: "row", justifyContent: "flex-end", gap: 8, paddingLeft: 20, paddingRight: 20, paddingTop: 8, paddingBottom: 16 }}>
        <Button label={t("common.cancel")} primary={false} onClick={() => { app.sheet = null; }} />
        <Button label={ticked.size === 0 ? t("web-mobile.files.add") : t("web-mobile.files.addCount", { n: ticked.size })} primary enabled={ticked.size > 0} onClick={() => {
          const all = [...ticked.values()];
          app.sheet = null;
          addRefs(app, draft, station, all);
        }} />
      </View>
    </View>
  );
}

/** The way to the folder shown: all the places, then its station's place and the folders under it; each a way back. */
function Crumbs({ place, onGo }: { place: Place | null; onGo: (p: Place | null) => void }) {
  const C = useC();
  const steps: [string, Place | null][] = [[t("web-mobile.files.places"), null]];
  if (place !== null) {
    steps.push([`${place.stationName} · ${place.rootName}`, { ...place, path: "" }]);
    const parts = place.path.split("/").filter((s) => s.length > 0);
    parts.forEach((part, i) => steps.push([part, { ...place, path: parts.slice(0, i + 1).join("/") }]));
  }
  const scroll = useRef<ScrollView>(null);
  useEffect(() => { scroll.current?.scrollToEnd({ animated: false }); }, [steps.length]);
  return (
    <ScrollView ref={scroll} horizontal showsHorizontalScrollIndicator={false} onContentSizeChange={() => scroll.current?.scrollToEnd({ animated: false })}
      contentContainerStyle={{ minHeight: 28, paddingLeft: 17, paddingRight: 20, paddingBottom: 8, alignItems: "center" }} style={{ flexGrow: 0 }}>
      {steps.map(([name, to], i) => {
        const last = i === steps.length - 1;
        return (
          <View key={i} style={{ flexDirection: "row", alignItems: "center" }}>
            {i > 0 ? <Icon icon={Icons.ChevronRight} size={12} color={C.subtle} /> : null}
            <Smooth radius={6}>
              <Pressable disabled={last} onPress={() => onGo(to)} android_ripple={ripple(C.ink)} style={{ paddingHorizontal: 3, paddingVertical: 3 }}>
                <T size={14} color={last ? C.ink : C.muted} weight={last ? "600" : undefined} numberOfLines={1}>{name}</T>
              </Pressable>
            </Smooth>
          </View>
        );
      })}
    </ScrollView>
  );
}

type PlaceRow = { k: string; t: "wait"; error: string | null } | { k: string; t: "none" } | { k: string; t: "station"; s: StationView } | { k: string; t: "home"; s: StationView; home: string } | { k: string; t: "root"; s: StationView; name: string; path: string };

/** Each station's places: its home (for a member who browses every folder), then its folders pinned. */
function Places({ scope, onGo }: { scope: string; onGo: (p: Place) => void }) {
  const C = useC();
  const stations = useTopic<StationView[]>(Topics.stations(scope));
  const list = (stations.value ?? []).filter((s) => s.overview?.drive != null);
  const rows: PlaceRow[] = [];
  if (stations.value == null) rows.push({ k: "wait", t: "wait", error: stations.error?.message ?? null });
  else if (list.length === 0) rows.push({ k: "none", t: "none" });
  else for (const s of list) {
    const drive = s.overview!.drive!;
    rows.push({ k: "s:" + s.station, t: "station", s });
    const home = drive.home;
    if (drive.anywhere === true && home != null) rows.push({ k: "h:" + s.station, t: "home", s, home });
    for (const r of drive.roots) rows.push({ k: "r:" + s.station + "\n" + r.path, t: "root", s, name: r.name, path: r.path });
  }
  return (
    <FlatList
      data={rows}
      keyExtractor={(r) => r.k}
      contentContainerStyle={{ paddingBottom: 8 }}
      renderItem={({ item: r }) => {
        switch (r.t) {
          case "wait": return <Waiting text={t("common.reading")} error={r.error} />;
          case "none": return <Note text={t("web-main.rail.filesNone")} />;
          case "station": return <SectionHeader title={r.s.name} trailing={r.s.online ? null : t("web-pages.stations.offline")} />;
          case "home": return (
            <PickRow label={t("web-pages.drive.home")} sub={r.home} leading={() => <Icon icon={Icons.Server} size={20} color={C.ink} />}
              onClick={() => onGo({ station: r.s.station, stationName: r.s.name, root: r.home, rootName: t("web-pages.drive.home"), path: "" })} />
          );
          case "root": return (
            <PickRow label={r.name} sub={r.path} leading={() => <Icon icon={Icons.Folder} size={20} color={C.ink} />}
              onClick={() => onGo({ station: r.s.station, stationName: r.s.name, root: r.path, rootName: r.name, path: "" })} />
          );
        }
      }}
    />
  );
}

type FolderRow = { k: string; t: "whole" } | { k: string; t: "wait"; error: string | null } | { k: string; t: "empty" } | { k: string; t: "entry"; e: DriveEntry };

/** A folder: itself to tick as a whole, then what is in it (a folder entered, a file ticked). */
function FolderRows({ app, p, scrolls, ticked, onToggle, onEnter }: {
  app: AppState; p: Place; scrolls: Map<string, number>; ticked: (x: Ticked) => boolean; onToggle: (x: Ticked) => void; onEnter: (name: string) => void;
}) {
  const C = useC();
  const folder = useTopic<DriveFolder>(Topics.drive(p.station, p.root, p.path));
  // Each folder its own scroll: one entered starts at its top, one gone back to is where it was left.
  const key = `${p.station}\n${p.root}\n${p.path}`;
  const list = useRef<FlatListType<FolderRow>>(null);
  const at = useRef(scrolls.get(key) ?? 0);
  useEffect(() => () => { scrolls.set(key, at.current); }, [key]);
  const whole = new Ticked(p.station, p.stationName, p.root, p.path, p.path.length === 0 ? p.rootName : p.path.substring(p.path.lastIndexOf("/") + 1), 0, true);
  const of = (e: DriveEntry) => new Ticked(p.station, p.stationName, p.root, joinIn(p.path, e.name), e.name, e.size, e.dir);
  const shown = folder.value;
  const entries = useMemo(() => (shown ? arranged(shown.entries, app.driveSort, app.driveHidden) : []), [shown, app.driveSort, app.driveHidden]);
  const rows: FolderRow[] = [{ k: "whole", t: "whole" }];
  if (shown == null) rows.push({ k: "wait", t: "wait", error: folder.error ? folder.error.message || t("android-misc.failed") : null });
  else if (entries.length === 0) rows.push({ k: "empty", t: "empty" });
  else for (const e of entries) rows.push({ k: "e:" + e.name, t: "entry", e });
  return (
    <FlatList
      ref={list}
      data={rows}
      keyExtractor={(r) => r.k}
      contentContainerStyle={{ paddingBottom: 8 }}
      contentOffset={{ x: 0, y: at.current }}
      onScroll={(e) => { at.current = e.nativeEvent.contentOffset.y; }}
      scrollEventThrottle={16}
      renderItem={({ item: r }) => {
        switch (r.t) {
          case "whole": return (
            <View>
              <PickRow label={t("web-mobile.files.wholeFolder")} sub={whole.path} checked={ticked(whole)} leading={() => <Icon icon={Icons.Folder} size={20} color={C.ink} />} onClick={() => onToggle(whole)} />
              <View style={{ marginHorizontal: 20, marginVertical: 4, height: 1, backgroundColor: C.line }} />
            </View>
          );
          case "wait": return <Waiting text={t("common.reading")} error={r.error} />;
          case "empty": return <Note text={t("web-pages.drive.emptyFolder")} />;
          case "entry": {
            const e = r.e;
            const icon = () => <Icon icon={kindIcon(e.kind)} size={20} color={C.ink} />;
            if (e.dir) return <PickRow label={e.name} sub={e.timeText} leading={icon} onClick={() => onEnter(e.name)} />;
            return <PickRow label={e.name} sub={[e.sizeText || fileSize(e.size), e.timeText].filter((s) => s.length > 0).join(" · ")} checked={ticked(of(e))} leading={icon} onClick={() => onToggle(of(e))} />;
          }
        }
      }}
    />
  );
}

function Note({ text }: { text: string }) {
  const C = useC();
  return <T size={13} color={C.muted} style={{ paddingHorizontal: 20, paddingVertical: 12 }}>{text}</T>;
}

let nano = 0;
/** A new id for what goes into a draft (the Kotlin's System.nanoTime()). */
const nanoTime = () => Date.now() * 1_000_000 + (nano = (nano + 1) % 1_000_000);

/** Ticked files into the draft: named by their path, or (where the chat says so) sent as files; a folder only named. */
function addRefs(app: AppState, draft: Draft, station: string, all: Ticked[]) {
  const asFiles = app.dropsAsFiles(chatKey(draft, station));
  for (const x of all) {
    const ref = new RefFile(x.station, x.stationName, x.path, x.dir, x.root, x.at, asFiles && !x.dir ? "file" : "path");
    const f = new Pending(nanoTime(), x.name, x.size, null, null, null, null, null, ref);
    draft.files = [...draft.files, f];
    if (ref.mode === "file") sendUp(app, draft, station, f);
  }
}

/**
 * A file of a station's switched to go as a file: staged on the chat's station from its own drive (a folder zipped
 * there), or read from the station that has it and sent up to the chat's. Once up, it is kept, switched back or not.
 */
function sendUp(app: AppState, draft: Draft, station: string, f: Pending) {
  const ref = f.ref;
  if (!ref) return;
  if (f.done != null || (f.error == null && f.sent != null)) return;
  f.error = null;
  f.sent = 0;
  app.scope.launch(async () => {
    try {
      if (ref.station === station) f.done = await app.api(station).driveStage(ref.root, ref.at, ref.dir);
      else {
        const kept = await DriveCache.fetch(app.api(ref.station), ref.root, ref.at, 0, f.size);
        f.done = await app.api(station).upload(f.name, kept.file.size ?? 0, () => byteSourceOf(kept.file), null, null, (sent: number) => { f.sent = sent; });
      }
      draft.save();
    } catch (e) {
      if (e instanceof CoreError) f.error = e.message;
      else f.error = t("android-chat.file.uploadFailed");
    } finally {
      if (f.done == null) f.sent = null;
    }
  });
}

/**
 * A file of a station's in the composer: its name, and where it is (named by its path: outlined, dashed, as it stays
 * where it is) or how it goes up; tapped, RefSheet. `shape`: its corner (the composer's, concentric with it).
 */
export function RefCard({ f, onRemove, shape, onClick }: { f: Pending; onRemove: () => void; shape: number; onClick: () => void }) {
  const C = useC();
  const ink = chatInk();
  const ref = f.ref!;
  const named = f.named;
  const busy = !named && f.done == null && f.error == null;
  const zipped = !named && ref.dir;
  const name = zipped ? `${f.name}.zip` : f.name;
  const note = named ? `${ref.stationName} · ${t("web-main.file.modePath")}` : f.error != null ? f.error : busy ? uploadingText(f) : fileSize(f.done?.size ?? f.size);
  const line = withAlpha(C.ink, 0.22);
  const [box, setBox] = useState({ width: 236, height: 0 });
  return (
    <Smooth radius={shape} style={{ width: 236, backgroundColor: named ? "transparent" : ink.neutral }}>
      {named && box.height > 0 ? (
        // NATIVE: dashed along a plain round corner; the Smooth view draws only a solid line along its own.
        <Svg width={box.width} height={box.height} style={{ position: "absolute", left: 0, top: 0 }} pointerEvents="none">
          <Rect x={0.5} y={0.5} width={box.width - 1} height={box.height - 1} rx={shape * 1.25} ry={shape * 1.25} stroke={line} strokeWidth={1} strokeDasharray="4 3" fill="none" />
        </Svg>
      ) : null}
      <Pressable onPress={onClick} android_ripple={ripple(C.ink)} onLayout={(e) => setBox({ width: e.nativeEvent.layout.width, height: e.nativeEvent.layout.height })}
        style={{ flexDirection: "row", alignItems: "center", gap: 10, paddingHorizontal: 10, paddingVertical: 8 }}>
        {busy ? <Spinner /> : <Icon icon={ref.dir && named ? Icons.Folder : Icons.Read} size={16} color={C.muted} />}
        <View style={{ flex: 1, minWidth: 0 }}>
          <T size={15} line={20} color={C.ink} numberOfLines={1}>{name}</T>
          <T size={11} line={16} color={f.error != null && !named ? C.red : C.muted} numberOfLines={1}>{note}</T>
        </View>
        <Pressable onPress={onRemove} android_ripple={ripple(C.ink)} style={{ width: 22, height: 22, borderRadius: 11, overflow: "hidden", backgroundColor: withAlpha(C.ink, 0.06), alignItems: "center", justifyContent: "center" }}>
          <Icon icon={Icons.Close} size={12} color={C.muted} />
        </Pressable>
      </Pressable>
    </Smooth>
  );
}

/**
 * A file of a station's in the composer, tapped (the wide screen's card says this on hover): its name, where it is, how
 * it goes (its path, or the file; a folder of the chat's own station as a zip), and whether this chat takes such files
 * as files.
 */
export function openRefSheet(app: AppState, draft: Draft, f: Pending, station: string) {
  const ref = f.ref;
  if (!ref) return;
  app.sheet = new SheetSpec(0.42, false, null, null, false, () => <RefSheet app={app} draft={draft} f={f} station={station} />);
}

function RefSheet({ app, draft, f, station }: { app: AppState; draft: Draft; f: Pending; station: string }) {
  const C = useC();
  const ref = f.ref!;
  const zips = ref.dir && ref.station === station;
  const key = chatKey(draft, station);
  const cut = Math.max(0, Math.max(ref.path.lastIndexOf("/"), ref.path.lastIndexOf("\\")));
  const where = ref.path.substring(0, cut) || ref.path;
  const [mode, setMode] = useState(ref.mode);
  const [chat, setChat] = useState(app.dropsAsFiles(key));
  return (
    <View>
      <SheetGrab />
      <SheetHead title={f.name} />
      <T size={13} color={C.muted} style={{ paddingLeft: 20, paddingRight: 20, paddingBottom: 14 }}>{`${ref.stationName} · ${where}`}</T>
      {!ref.dir || zips ? (
        <View style={{ paddingLeft: 20, paddingRight: 20, paddingBottom: 14, gap: 8 }}>
          <T size={13} color={C.muted}>{t("web-main.file.sendAs")}</T>
          <Seg options={[t("web-main.file.modePath"), t(ref.dir ? "web-main.file.modeZip" : "web-main.file.modeFile")]} selected={mode === "path" ? 0 : 1} fill onSelect={(i: number) => {
            ref.mode = i === 0 ? "path" : "file";
            setMode(ref.mode);
            if (ref.mode === "file") sendUp(app, draft, station, f);
          }} />
        </View>
      ) : null}
      <View style={{ paddingLeft: 20, paddingRight: 20, paddingBottom: 14 }}>
        <Smooth radius={14} style={{ width: "100%", backgroundColor: C.chip }}>
          <Pressable onPress={() => { const next = !chat; setChat(next); app.setDropsAsFiles(key, next); }} android_ripple={ripple(C.ink)}
            style={{ flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 14, paddingVertical: 10 }}>
            <T size={14} weight="600" color={C.ink} style={{ flex: 1 }}>{t("web-main.file.chatAsFiles")}</T>
            <Switch on={chat} />
          </Pressable>
        </Smooth>
      </View>
    </View>
  );
}

