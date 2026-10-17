// A station's drive (docs/drive.md; drive/DriveScreen.kt): the folders it lends its members, one page per folder
// (Screen.Drive), so going in and coming back is the stack's slide and the edge swipe. One root shows what is in it at
// once; several are listed as folders, one that cannot be browsed in red with why. A row opens by its kind: a folder goes
// in, text and Markdown are read (Reader.tsx), video and audio play (Player.tsx), pictures, PDFs, code, tables and pages
// open in the chat's viewer (FilePreview.tsx), the rest goes to another app. Held, a row is chosen (others then by a tap,
// as the phone's own file managers do), and what is chosen is downloaded, its paths copied, deleted (to the machine's
// trash where the station has one), one renamed or shared. The order and whether hidden files show are the device's, as
// the web's (prefs `driveViews`); a folder shown is kept as it is on the station's disk (the core watches it).
// The workspace's owners and admins choose the folders (⋯); read-only members get no way to change anything. Laid out
// as the phone web's (web/src/mobile/Drive.tsx), the reference for the phone (docs/mobile-parity.md).
import * as Clipboard from "expo-clipboard";
import * as DocumentPicker from "expo-document-picker";
import { File, type FileHandle } from "expo-file-system";
import * as IntentLauncher from "expo-intent-launcher";
import * as Sharing from "expo-sharing";
import { useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode, type RefObject } from "react";
import { BackHandler, FlatList, Platform, Pressable, ScrollView, TextInput, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useTopic } from "../../../../web/src/core/react.ts";
import type { CoreError } from "../../../../web/src/core/client.ts";
import type { DriveEntry, DriveFolder, DrivePlace, DriveRoot, StationView } from "../../../../web/src/core/shapes.ts";
import { useDoing, useDoingFailed } from "../../../../web/src/doing.ts";
import { usePrefs } from "../../../../web/src/prefs.ts";
import { SheetSpec, app, type Screen } from "../AppState";
import { manager, type WorkspaceEntry, type WorkspaceView } from "../data/Accounts";
import type { ByteSource, DriveCrumb, DriveFolders, PickFolder } from "../data/Calls";
import { DriveCache } from "../data/DriveCache";
import { arranged, freeName } from "../data/Drives";
import { t } from "../i18n";
import { DriveKey, Shown, download } from "../screens/ChatFiles";
import { FilePreview } from "../screens/FilePreview";
import { ask, confirm } from "../screens/Settings";
import { Button, DoingMark, PickRow, fileSize, kindIcon } from "../ui/Controls";
import { Icons, type IconPaths } from "../ui/IconSet";
import { DownloadChip, IconIn, NavBar, NavButton, SectionHeader } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { Smooth } from "../ui/Smooth";
import { sp, T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";
import { Progress, Spinner, WaitLine, Waiting } from "../ui/Waiting";

/** The ripple a tap leaves (Compose's clickable): the ink, faint. */
const ripple = (ink: string) => ({ color: withAlpha(ink, 0.1) });

/** ui/Sheet.kt's SheetSpec(height, draggable, fit) { content }. */
const sheet = (spec: { height: number; draggable?: boolean; fit?: number; content: () => ReactNode }): SheetSpec =>
  new SheetSpec(spec.height, spec.draggable ?? false, spec.fit ?? null, null, false, spec.content);

const errorOf = (e: unknown) => (e instanceof Error ? e.message : String(e));
const codeOf = (e: unknown) => (e as CoreError | null)?.code;

// ── what an entry is ────────────────────────────────────────────────────

/** A path under a root, `/` between its components; `dir` empty for the root itself. */
export const join = (dir: string, name: string) => (dir.length === 0 ? name : `${dir}/${name}`);
export const parentOf = (path: string) => { const i = path.lastIndexOf("/"); return i < 0 ? "" : path.substring(0, i); };
export const nameOf = (path: string) => path.substring(path.lastIndexOf("/") + 1);

/** What a root is called: its name as the station lends it, else its path's last part. */
export function rootLabel(roots: readonly DriveRoot[] | null | undefined, root: string): string {
  const named = roots?.find((it) => it.path === root)?.name;
  if (named !== undefined) return named;
  const trimmed = root.replace(/[/\\]+$/, "");
  return trimmed.substring(trimmed.lastIndexOf("/") + 1) || root;
}

/** Why a root cannot be browsed (in red) and what to do about it; null while it can (web drive/useDrive.ts rootTrouble). */
export function rootTrouble(state: string): [string, string] | null {
  switch (state) {
    case "ok": return null;
    case "missing": return [t("android-misc.drive.root.missing"), t("android-misc.drive.root.missingHint")];
    case "not_a_directory": return [t("android-misc.drive.root.notFolder"), t("android-misc.drive.root.notFolderHint")];
    default: return [t("android-misc.drive.root.unreadable"), t("android-misc.drive.root.unreadableHint")];
  }
}

/** Where a path under a root is on the station. */
export const absoluteIn = (root: string, path: string) => (path.length === 0 ? root : `${root.replace(/[/\\]+$/, "")}/${path}`);

/** What a name a file or folder may have says is wrong with it (empty, a slash, . or ..); null when nothing is. */
export function nameProblem(name: string): string | null {
  const n = name.trim();
  if (n.length === 0) return t("android-misc.drive.name.empty");
  if (n.includes("/") || n.includes("\\") || n === "." || n === "..") return t("android-misc.drive.name.bad");
  return null;
}

/** An error by its code and words, as CoreException(code, message, null) is thrown in the Kotlin. */
function coreError(code: string, message: string): Error {
  return Object.assign(new Error(message), { code });
}

/** What the viewer may do with a station's drive: name the folders it lends (owners and admins), change what is in them (not a read-only member). */
interface DriveRights { manage: boolean; write: boolean; trash: boolean; zip: boolean }

function useRights(current: WorkspaceEntry, s: StationView | undefined): DriveRights {
  const ws = useTopic<WorkspaceView>({ topic: "workspace", workspace: current.workspace.id });
  const drive = s?.overview?.drive;
  return { manage: ws.value !== undefined && manager(ws.value), write: s?.overview?.viewer?.role !== "viewer" && ws.value?.role !== "viewer", trash: drive?.trash === true, zip: drive?.zip === true };
}

// ── a store the rows follow ─────────────────────────────────────────────

/** Something that changes and is drawn again when it does (Compose's snapshot state). */
class Watched {
  #version = 0;
  readonly #listeners = new Set<() => void>();
  subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  version = () => this.#version;
  changed() { this.#version++; for (const l of this.#listeners) l(); }
}

const useWatched = (w: Watched) => useSyncExternalStore(w.subscribe, w.version);

// ── uploads ─────────────────────────────────────────────────────────────

/**
 * A file going up into a folder of a drive, shown in its folder's list until it is there: how much of it the station
 * has; its name taken there (`taken`: replace it or keep both); why it failed (`failed`: tried again or let go).
 */
export class DriveUpload {
  #name: string;
  #size = 0;
  #sent = 0;
  #state: "waiting" | "going" | "taken" | "failed" = "waiting";
  #error: string | null = null;
  /** What it is reading the file through: closed when it is let go, which stops what it was doing. */
  handles: { close(): void }[] = [];
  /** Its answer when its name was taken: true replace, false keep both, null let go. */
  answer: ((replace: boolean | null) => void) | null = null;
  /** Let go (off the list). */
  cancelled = false;
  /** Replace a file of its name when it goes up. */
  replace = false;
  /** What its folder holds now, for a name taken there and another to keep both by. */
  held: () => readonly DriveEntry[] = () => [];
  /** Its own key in a list. */
  readonly id = ++uploadIds;

  constructor(readonly station: string, readonly root: string, readonly dir: string, name: string, readonly uri: string, readonly knownSize: number = -1) {
    this.#name = name;
  }

  get name() { return this.#name; }
  set name(v) { this.#name = v; DriveUploads.changes.changed(); }
  get size() { return this.#size; }
  set size(v) { this.#size = v; DriveUploads.changes.changed(); }
  get sent() { return this.#sent; }
  set sent(v) { this.#sent = v; DriveUploads.changes.changed(); }
  /** waiting | going | taken | failed */
  get state() { return this.#state; }
  set state(v) { this.#state = v; DriveUploads.changes.changed(); }
  get error() { return this.#error; }
  set error(v) { this.#error = v; DriveUploads.changes.changed(); }
}
let uploadIds = 0;

/** The uploads, whatever page is shown (they go on past the page that started them), one going at a time. */
export const DriveUploads = {
  list: [] as DriveUpload[],
  changes: new Watched(),
  pumping: false,

  add(ups: DriveUpload[], held: () => readonly DriveEntry[]) {
    ups.forEach((it) => { it.held = held; });
    this.list = [...this.list, ...ups];
    this.changes.changed();
    this.pump();
  },

  /** Its name taken: replaced (`true`) or both kept (`false`). */
  settle(up: DriveUpload, replace: boolean) { up.answer?.(replace); },

  /** Let go: off the list, what it was doing stopped. */
  cancel(up: DriveUpload) {
    up.answer?.(null);
    up.cancelled = true;
    up.handles.forEach((h) => { try { h.close(); } catch { /* closed already */ } });
    this.list = this.list.filter((it) => it !== up);
    this.changes.changed();
  },

  /** Failed: tried again from the start. */
  retry(up: DriveUpload, held: () => readonly DriveEntry[]) { up.held = held; up.state = "waiting"; up.error = null; up.sent = 0; this.pump(); },

  pump() {
    if (this.pumping) return;
    this.pumping = true;
    void (async () => {
      try {
        for (;;) {
          const up = this.list.find((it) => it.state === "waiting");
          if (!up) break;
          await this.send(up);
        }
      } finally { this.pumping = false; }
    })();
  },

  async send(up: DriveUpload): Promise<void> {
    const held = up.held;
    up.state = "going";
    try {
      // A provider that does not say how big it is: read it once to know.
      up.size = up.knownSize >= 0 ? up.knownSize : (await new File(up.uri).bytes()).length;
      const open = (): ByteSource => {
        if (up.cancelled) throw new Error(t("android-misc.drive.upload.unreadable"));
        let handle: FileHandle;
        try { handle = new File(up.uri).open(); } catch { throw new Error(t("android-misc.drive.upload.unreadable")); }
        up.handles.push(handle);
        return sourceOf(handle);
      };
      for (;;) {
        try {
          await app.api(up.station).driveUpload(up.root, join(up.dir, up.name), up.size, open, up.replace, (n: number) => { up.sent = n; });
          this.list = this.list.filter((it) => it !== up);
          this.changes.changed();
          return;
        } catch (e) {
          if (up.cancelled) return;
          // Its name taken by a file (a folder of that name cannot be replaced): asked here, in its row.
          if ((e as CoreError).status !== 409 || up.replace || held().some((it) => it.name === up.name && it.dir)) throw e;
          up.state = "taken";
          const replace = await new Promise<boolean | null>((resolve) => { up.answer = resolve; });
          if (replace === null) return;
          up.answer = null;
          up.state = "going";
          up.sent = 0;
          if (replace) up.replace = true;
          else up.name = freeName(up.name, new Set([...held().map((it) => it.name), ...this.list.filter((it) => it !== up && it.dir === up.dir).map((it) => it.name)]));
        }
      }
    } catch (e) {
      if (up.cancelled) return;
      up.state = "failed"; up.error = errorOf(e);
    } finally {
      up.handles = [];
    }
  },
};

/** A file read as it goes (the provider's InputStream), over the file system's handle on it: -1 at its end. */
function sourceOf(h: FileHandle): ByteSource {
  return {
    async read(into, offset, length) {
      const got = h.readBytes(length);
      if (got.length === 0) return -1;
      into.set(got, offset);
      return got.length;
    },
    async skip(n) {
      const at = h.offset ?? 0;
      const to = Math.min(at + n, h.size ?? at + n);
      h.offset = to;
      return to - at;
    },
    close() { h.close(); },
  };
}

/** Puts the files picked into a folder of the drive, one after another, each a row in that folder's list while it goes. */
export function uploadInto(station: string, root: string, dir: string, picks: readonly DocumentPicker.DocumentPickerAsset[], held: () => readonly DriveEntry[]): void {
  if (picks.length === 0) return;
  // The picker asked the document's provider for its name and size (OpenableColumns), as Drives.kt `picked` does.
  const ups = picks.map((p) => new DriveUpload(station, root, dir, p.name || "file", p.uri, p.size ?? -1));
  DriveUploads.add(ups, held);
}

// ── fetching for another app ────────────────────────────────────────────

/** Files of the drive being fetched to hand to another app (or to Downloads): how far each has come (0–100), by station and path. */
export const DriveFetches = {
  progress: new Map<string, number>(),
  changes: new Watched(),
  id: (station: string, root: string, path: string) => `${station}\n${root}\n${path}`,
  set(id: string, v: number | null) { if (v === null) this.progress.delete(id); else this.progress.set(id, v); this.changes.changed(); },
};

/** A file of the drive kept on the phone (DriveCache; for another app to open, or to save), fetched a part at a time with its progress shown on its row. */
async function fetched(station: string, root: string, entry: DriveEntry, path: string): Promise<File> {
  const id = DriveFetches.id(station, root, path);
  DriveFetches.set(id, 0);
  try {
    return (await DriveCache.fetch(app.api(station), root, path, entry.mtime, entry.size, undefined, (at, total) => DriveFetches.set(id, total > 0 ? Math.trunc((at * 100) / total) : 0))).file;
  } finally {
    DriveFetches.set(id, null);
  }
}

/** Android's Intent.FLAG_GRANT_READ_URI_PERMISSION. */
const FLAG_GRANT_READ_URI_PERMISSION = 1;

/** How another app is handed a file: to open it (VIEW) or to share it (SEND). */
async function hand(file: File, type: string, share: boolean): Promise<boolean> {
  const mime = type || "application/octet-stream";
  try {
    if (share || Platform.OS !== "android") await Sharing.shareAsync(file.uri, { mimeType: mime });
    else await IntentLauncher.startActivityAsync("android.intent.action.VIEW", { data: file.contentUri, type: mime, flags: FLAG_GRANT_READ_URI_PERMISSION });
    return true;
  } catch {
    return false;
  }
}

/** Fetches a file and hands it to another app (`share`: to send it somewhere; else to open it). */
export function openElsewhere(station: string, root: string, entry: DriveEntry, path: string, share: boolean): void {
  void (async () => {
    try {
      const file = await fetched(station, root, entry, path);
      if (!(await hand(file, entry.type, share))) app.toast = t("android-misc.drive.noApp");
    } catch (e) {
      app.toast = t("android-misc.drive.fetchFailed", { name: entry.name, error: errorOf(e) });
    }
  })();
}

/** Fetches a file into the phone's Downloads. */
export function saveToDownloads(station: string, root: string, entry: DriveEntry, path: string): void {
  void (async () => {
    try {
      const file = await fetched(station, root, entry, path);
      app.toast = (await download(entry.name, file)) ? t("android-chat.file.saved") : t("android-chat.file.saveFailed");
    } catch (e) {
      app.toast = t("android-misc.drive.fetchFailed", { name: entry.name, error: errorOf(e) });
    }
  })();
}

// ── the page ────────────────────────────────────────────────────────────

/** A sheet's height for a title and `rows` rows (a sheet is as tall as what it holds). */
const fit = (rows: number) => 96 + rows * 48 + 24;

/** How a station's files are listed on this device (AppState.kt driveSort, driveHidden): the prefs' `driveViews`. */
function useDriveView(): { sort: string; hidden: boolean } {
  const sort = usePrefs((p) => p.driveViews?.sort ?? "name");
  const hidden = usePrefs((p) => p.driveViews?.hidden === "shown");
  return { sort, hidden };
}
const setDriveView = (key: string, value: string | null) => app.setDriveView(key, value);

/**
 * A page of a station's drive (as the phone web's, web/src/mobile/Drive.tsx): `root` null is the drive itself (its one
 * root's contents, or its roots as folders); else the folder `path` under `root`.
 */
export function DriveScreen({ current, station, root, path }: { current: WorkspaceEntry; station: string; root: string | null; path: string }) {
  const stations = useTopic<StationView[]>({ topic: "stations", scope: current.workspace.id });
  const s = stations.value?.find((it) => it.station === station);
  const roots = s?.overview?.drive?.roots;
  const can = useRights(current, s);
  // The drive's own page with one root, and nothing wrong with it: what is in it is the page.
  const only = roots?.length === 1 && roots[0]!.state === "ok" ? roots[0]!.path : null;
  const folderRoot = root ?? only;
  if (s === undefined || roots === undefined || folderRoot === null) return <RootsPage station={station} s={s} roots={roots} error={stations.error?.message ?? null} can={can} />;
  return <FolderPage key={`${station}|${folderRoot}|${path}`} station={station} s={s} roots={roots} root={folderRoot} path={path} top={root === null} can={can} />;
}

function RootsPage({ station, s, roots, error, can }: { station: string; s: StationView | undefined; roots: DriveRoot[] | undefined; error: string | null; can: DriveRights }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  let body: ReactNode;
  // The station's folders lent still on their way (or what kept them), as every list's first read.
  if (roots === undefined && (error !== null || s?.overview === undefined)) body = <Waiting text={t("common.reading")} error={error} />;
  else if (roots === undefined) body = <Note text={t("android-misc.drive.oldStation")} />;
  else if (roots.length === 0) {
    body = (
      <Empty text={can.manage ? t("android-misc.drive.none.manager") : t("android-misc.drive.none.member")}>
        {can.manage ? <Button label={t("android-misc.drive.choose")} primary onClick={() => openFolderPicker(station, [])} /> : null}
      </Empty>
    );
  } else {
    body = (
      <FlatList
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingBottom: 30 + insets.bottom }}
        data={[null, ...roots]}
        keyExtractor={(r) => (r === null ? "count" : r.path)}
        renderItem={({ item: r, index }) =>
          r === null ? <Count text={t("android-misc.drive.roots.count", { n: roots.length })} />
          : <RootRow station={station} r={r} roots={roots} first={index === 1} last={index === roots.length} manage={can.manage} />}
      />
    );
  }
  return (
    <View style={{ flex: 1, backgroundColor: C.bg }}>
      <NavBar
        back={s?.name ?? ""} onBack={() => app.pop()} title={t("android-misc.drive.title")}
        trailing={can.manage && roots !== undefined && roots.length > 0 ? <NavButton icon={Icons.More} onClick={() => openRoots(station)} /> : null}
      />
      {body}
    </View>
  );
}

/** Card rows in a lazy list: each row its part of one rounded card (the first and last carry its corners). */
function CardRow({ first, last, ground, onPress, onLongPress, enabled = true, style, children }: {
  first: boolean; last: boolean; ground: string; onPress?: () => void; onLongPress?: () => void; enabled?: boolean;
  style: { paddingHorizontal?: number; paddingVertical?: number; paddingLeft?: number; paddingRight?: number; paddingTop?: number; paddingBottom?: number }; children: ReactNode;
}) {
  const C = useC();
  const r = (on: boolean) => (on ? 16 : 0);
  const row = { flexDirection: "row", alignItems: "center", gap: 12, ...style } as const;
  return (
    <View style={{ paddingHorizontal: 12, paddingBottom: last ? 10 : 0 }}>
      <Smooth radius={[r(first), r(first), r(last), r(last)]} style={{ backgroundColor: ground }}>
        {onPress || onLongPress ? (
          <Pressable disabled={!enabled} onPress={onPress} onLongPress={onLongPress} android_ripple={ripple(C.ink)} style={row}>{children}</Pressable>
        ) : <View style={row}>{children}</View>}
      </Smooth>
    </View>
  );
}

/** A folder lent: its name, where it is; one that cannot be browsed now with why in red and what to do about it. */
function RootRow({ station, r, roots, first, last, manage }: { station: string; r: DriveRoot; roots: DriveRoot[]; first: boolean; last: boolean; manage: boolean }) {
  const C = useC();
  const trouble = rootTrouble(r.state);
  return (
    <CardRow
      first={first} last={last} ground={C.surface} style={{ paddingHorizontal: 16, paddingVertical: 12 }}
      onPress={() => app.push({ kind: "Drive", station, root: r.path, path: "" })}
      onLongPress={manage ? () => {
        app.sheet = sheet({
          height: 0.3, fit: fit(1), content: () => (
            <>
              <SheetGrab />
              <SheetHead title={r.name} />
              <PickRow label={t("android-misc.drive.roots.stop")} color={C.accent} leading={<IconIn icon={Icons.Close} size={20} tint={C.accent} />} onClick={() => unshare(station, roots, r)} />
            </>
          ),
        });
      } : undefined}
    >
      <IconIn icon={Icons.Folder} size={22} tint={C.muted} />
      <View style={{ flex: 1, minWidth: 0 }}>
        <T size={15} line={20} color={C.ink} numberOfLines={1}>{r.name}</T>
        <T size={12} line={16} color={C.muted} numberOfLines={1}>{r.path}</T>
        {trouble !== null ? (
          <>
            <T size={12} line={16} weight="600" color={C.red} style={{ paddingTop: 3 }}>{trouble[0]}</T>
            <T size={12} line={16} color={C.muted}>{trouble[1]}</T>
          </>
        ) : null}
      </View>
      <IconIn icon={Icons.ChevronRight} size={14} tint={C.subtle} />
    </CardRow>
  );
}

function unshare(station: string, roots: readonly DriveRoot[], r: DriveRoot) {
  confirm(app, t("android-misc.drive.roots.stopTitle", { name: r.name }), t("android-misc.drive.roots.stopText"), t("android-misc.drive.roots.stop"), { danger: true, what: t("android-misc.drive.roots.what") }, async () => {
    await app.api(station).driveSetRoots(roots.map((it) => it.path).filter((p) => p !== r.path));
  });
}

type Row =
  | { key: "crumbs" } | { key: "stale" } | { key: "error" } | { key: "reading" } | { key: "count" } | { key: "empty" }
  | { key: string; up: DriveUpload; i: number }
  | { key: string; e: DriveEntry; i: number };

/** A folder: back to where it was opened from, its name; where it is under its root (each step a tap away), what it holds in a line, its entries. */
function FolderPage({ station, s, roots, root, path, top, can }: { station: string; s: StationView; roots: DriveRoot[]; root: string; path: string; top: boolean; can: DriveRights }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const folder = useTopic<DriveFolder>({ topic: "drive", station, root, path });
  const entries = folder.value?.entries ?? [];
  const latest = useRef(entries);
  latest.current = entries;
  const held = () => latest.current;
  const home = s.overview?.drive?.home;
  const name = path.length > 0 ? nameOf(path) : root === home && !roots.some((it) => it.path === root) ? t("web-pages.drive.home") : rootLabel(roots, root);
  const back = top ? s.name : path.length === 0 ? t("android-misc.drive.title") : parentOf(path).length === 0 ? rootLabel(roots, root) : nameOf(parentOf(path));
  const [refreshing, setRefreshing] = useState(false);
  const [previewing, setPreviewing] = useState<DriveEntry | null>(null);
  const upload = () => {
    void DocumentPicker.getDocumentAsync({ type: "*/*", multiple: true, copyToCacheDirectory: false }).then((r) => { if (!r.canceled) uploadInto(station, root, path, r.assets, held); });
  };
  const reload = () => {
    if (refreshing) return;
    setRefreshing(true);
    app.api(station).driveRefresh(root, path)
      .catch((e: unknown) => { app.toast = t("android-misc.act.failed", { what: t("android-misc.drive.refreshWhat"), error: errorOf(e) }); })
      .finally(() => setRefreshing(false));
  };
  useWatched(DriveUploads.changes);
  const uploads = DriveUploads.list.filter((it) => it.station === station && it.root === root && it.dir === path);
  const view = useDriveView();
  const shownEntries = useMemo(() => arranged(entries, view.sort, view.hidden), [entries, view.sort, view.hidden]);
  // What is chosen (a row held, then others tapped), by name: what the bar on top then acts on.
  const [chosen, setChosen] = useState<string[]>([]);
  const choosing = chosen.length > 0;
  useEffect(() => {
    if (!choosing) return;
    const sub = BackHandler.addEventListener("hardwareBackPress", () => { setChosen([]); return true; });
    return () => sub.remove();
  }, [choosing]);
  const chosenEntries = () => entries.filter((it) => chosen.includes(it.name));

  const error = folder.error;
  const value = folder.value;
  const rows: Row[] = [];
  if (path.length > 0) rows.push({ key: "crumbs" });
  // Not read now (the station away, the folder refused): what was read last stays, said to be so.
  if (error !== null && value !== undefined) rows.push({ key: "stale" });
  if (error !== null && value === undefined) rows.push({ key: "error" });
  else if (value === undefined) rows.push({ key: "reading" });
  else {
    rows.push({ key: "count" });
    uploads.forEach((up, i) => rows.push({ key: `up:${up.id}`, up, i }));
    if (shownEntries.length === 0 && uploads.length === 0) rows.push({ key: "empty" });
    shownEntries.forEach((e, i) => rows.push({ key: `e:${e.name}`, e, i }));
  }

  const renderRow = (row: Row): ReactNode => {
    if ("up" in row) return <UploadRow u={row.up} first={row.i === 0} last={row.i === uploads.length - 1} held={held} />;
    if ("e" in row) {
      const e = row.e;
      const full = join(path, e.name);
      const toggle = () => setChosen((was) => (was.includes(e.name) ? was.filter((it) => it !== e.name) : [...was, e.name]));
      return (
        <EntryRow
          station={station} root={root} path={full} e={e} first={row.i === 0} last={row.i === shownEntries.length - 1} chosen={choosing ? chosen.includes(e.name) : null}
          onOpen={() => { if (choosing) toggle(); else open(station, root, path, e, setPreviewing); }}
          // Held: chosen, as the phone's own file managers do; what is chosen is acted on from the bar.
          onHold={toggle}
        />
      );
    }
    switch (row.key) {
      case "crumbs": return <Crumbs station={station} root={root} rootName={rootLabel(roots, root)} path={path} />;
      case "stale": return (
        <View style={{ paddingHorizontal: 20, paddingVertical: 6, flexDirection: "row", gap: 12, alignItems: "center" }}>
          <T size={13} color={C.muted} numberOfLines={2} style={{ flexShrink: 1 }}>{t("android-misc.drive.stale", { error: error?.message ?? "" })}</T>
          <Smooth radius={6}><Pressable onPress={reload} android_ripple={ripple(C.ink)} style={{ padding: 4 }}><T size={13} color={C.accent}>{t("android-misc.drive.retry")}</T></Pressable></Smooth>
        </View>
      );
      case "error": return (
        <View style={{ paddingHorizontal: 20, paddingVertical: 12, flexDirection: "row", gap: 12, alignItems: "center" }}>
          <T size={14} color={C.red} style={{ flexShrink: 1 }}>{error?.message}</T>
          <Smooth radius={6}><Pressable onPress={reload} android_ripple={ripple(C.ink)} style={{ padding: 4 }}><T size={14} color={C.accent}>{t("android-misc.drive.retry")}</T></Pressable></Smooth>
        </View>
      );
      case "reading": return <Waiting text={t("common.reading")} />;
      case "count": return <Count text={value!.countText + (value!.truncated === true ? ` · ${t("android-misc.drive.truncated")}` : "")} />;
      case "empty": return (
        <Empty text={t("android-misc.drive.empty")}>
          {can.write ? <Button label={t("android-misc.drive.upload")} primary={false} onClick={upload} /> : null}
        </Empty>
      );
      default: return null;
    }
  };

  // Pictures, PDFs, code, tables and pages: the chat's viewer, over the page; a picture steps to the folder's others.
  const shownOf = (e: DriveEntry) => new Shown(DriveKey.of(root, e.mtime), { name: e.name, path: join(path, e.name), size: e.size });
  const opened = useMemo(() => (previewing ? shownOf(previewing) : null), [previewing]);

  return (
    <View style={{ flex: 1, backgroundColor: C.bg }}>
      {choosing ? (
        <NavBar
          back={t("common.cancel")} onBack={() => setChosen([])} title={t("android-misc.drive.chosen", { n: chosen.length })}
          trailing={
            <View style={{ flexDirection: "row", alignItems: "center" }}>
              <Smooth radius={6}>
                <Pressable
                  android_ripple={ripple(C.ink)} style={{ paddingHorizontal: 8, paddingVertical: 6 }}
                  onPress={() => setChosen(chosen.length === shownEntries.length ? [] : shownEntries.map((it) => it.name))}
                >
                  <T size={15} color={C.accent}>{t(chosen.length === shownEntries.length ? "android-misc.drive.chooseNone" : "android-misc.drive.chooseAll")}</T>
                </Pressable>
              </Smooth>
              <View>
                <NavButton icon={Icons.More} label={t("android-misc.drive.chosenActions")} onClick={() => openChosenSheet(station, root, path, chosenEntries(), can, new Set(entries.map((it) => it.name)), () => setChosen([]))} />
              </View>
            </View>
          }
        />
      ) : (
        <NavBar
          back={back} onBack={() => app.pop()} title={name}
          trailing={
            <View style={{ flexDirection: "row", alignItems: "center" }}>
              <Pressable
                disabled={refreshing} onPress={reload} accessibilityLabel={t("android-misc.drive.refresh")}
                android_ripple={{ ...ripple(C.ink), borderless: true, radius: 17 }}
                style={{ width: 34, height: 34, borderRadius: 17, overflow: "hidden", alignItems: "center", justifyContent: "center" }}
              >
                {refreshing ? <Spinner /> : <IconIn icon={Icons.Refresh} size={18} />}
              </Pressable>
              {can.write ? (
                <View>
                  <NavButton
                    icon={Icons.Plus} iconSize={20} label={t("android-misc.drive.add")}
                    onClick={() => {
                      const rows = can.manage && top ? 3 : 2;
                      app.sheet = sheet({
                        height: 0.4, fit: fit(rows), content: () => (
                          <>
                            <SheetGrab />
                            <SheetHead title={name} />
                            <PickRow label={t("android-misc.drive.upload")} leading={<IconIn icon={Icons.Upload} size={20} tint={C.ink} />} onClick={() => { app.sheet = null; upload(); }} />
                            <PickRow label={t("android-misc.drive.mkdir")} leading={<IconIn icon={Icons.FolderPlus} size={20} tint={C.ink} />} onClick={() => newFolder(station, root, path)} />
                            {can.manage && top ? <PickRow label={t("android-misc.drive.roots.manage")} leading={<IconIn icon={Icons.Folder} size={20} tint={C.ink} />} onClick={() => openRoots(station)} /> : null}
                          </>
                        ),
                      });
                    }}
                  />
                </View>
              ) : null}
              {/* How the folder is shown (its order, hidden files), and the folders lent for those who name them. */}
              <View>
                <NavButton icon={Icons.More} label={t("android-misc.drive.view")} onClick={() => openViewSheet(station, can.manage && top)} />
              </View>
            </View>
          }
        />
      )}
      <FlatList
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingBottom: 30 + insets.bottom }}
        data={rows}
        extraData={[chosen, uploads, error, value]}
        keyExtractor={(row) => row.key}
        renderItem={({ item }) => <>{renderRow(item)}</>}
      />
      {opened !== null ? (
        <FilePreview
          station={station} sessionKey={opened.key} file={opened.file} canDraft={false}
          gallery={{ kind: "Folder", images: () => latest.current.filter((it) => it.kind === "image").map(shownOf) }}
          onClose={() => setPreviewing(null)}
        />
      ) : null}
    </View>
  );
}

/** The line over a list: what it holds. */
function Count({ text }: { text: string }) {
  const C = useC();
  return <T size={13} color={C.muted} numberOfLines={1} style={{ paddingLeft: 24, paddingRight: 20, paddingTop: 2, paddingBottom: 6 }}>{text}</T>;
}

function Note({ text }: { text: string }) {
  const C = useC();
  return (
    <View style={{ padding: 32, alignItems: "center", justifyContent: "center" }}>
      <T size={14} color={C.muted} align="center">{text}</T>
    </View>
  );
}

/** Nothing here: a folder's mark, why, and what can be done about it. */
function Empty({ text, children }: { text: string; children?: ReactNode }) {
  const C = useC();
  return (
    <View style={{ paddingHorizontal: 32, paddingVertical: 56, alignItems: "center", gap: 12 }}>
      <IconIn icon={Icons.Folder} size={40} tint={C.subtle} />
      <T size={14} color={C.muted} align="center">{text}</T>
      {children}
    </View>
  );
}

/** A path's steps scrolled to their end (the end of a long path is what matters), each but the last a tap away. */
function Trail({ labels, size, onPick, style }: { labels: string[]; size: number; onPick: (i: number) => void; style: object }) {
  const C = useC();
  const scroll = useRef<ScrollView>(null);
  const v = size === 13 ? 2 : 3;
  return (
    <ScrollView ref={scroll} horizontal showsHorizontalScrollIndicator={false} style={{ flexGrow: 0 }} contentContainerStyle={[{ alignItems: "center" }, style]} onContentSizeChange={() => scroll.current?.scrollToEnd({ animated: false })}>
      {labels.map((label, i) => {
        const last = i === labels.length - 1;
        return (
          <View key={i} style={{ flexDirection: "row", alignItems: "center" }}>
            {i > 0 ? <IconIn icon={Icons.ChevronRight} size={12} tint={C.subtle} /> : null}
            <Smooth radius={6}>
              <Pressable disabled={last} onPress={() => onPick(i)} android_ripple={ripple(C.ink)} style={{ paddingHorizontal: 3, paddingVertical: v }}>
                <T size={size} color={last ? C.ink : C.muted} weight={last ? "600" : undefined} numberOfLines={1}>{label}</T>
              </Pressable>
            </Smooth>
          </View>
        );
      })}
    </ScrollView>
  );
}

/** Where the folder is under its root: the root, then each folder down to this one, each but the last a way back to it. */
function Crumbs({ station, root, rootName, path }: { station: string; root: string; rootName: string; path: string }) {
  const parts = path.split("/").filter((it) => it.length > 0);
  const levels: [string, Extract<Screen, { kind: "Drive" }>][] = [
    [rootName, { kind: "Drive", station, root, path: "" }],
    ...parts.map((p, i): [string, Extract<Screen, { kind: "Drive" }>] => [p, { kind: "Drive", station, root, path: parts.slice(0, i + 1).join("/") }]),
  ];
  return (
    <Trail
      labels={levels.map(([label]) => label)} size={13} style={{ paddingLeft: 21, paddingRight: 20, paddingTop: 2, paddingBottom: 4 }}
      onPick={(i) => {
        const to = levels[i]![1];
        // Back to it where it is in the stack; else opened there.
        // The root as the drive's own page with one root has it (no root named) is the same page.
        const stack = app.stack;
        let at = -1;
        for (let k = stack.length - 1; k >= 0; k--) {
          const it = stack[k]!;
          if (it.kind === "Drive" && it.station === to.station && ((it.root === to.root && it.path === to.path) || (to.path.length === 0 && it.root === null && it.path.length === 0))) { at = k; break; }
        }
        if (at >= 0) for (let n = stack.length - 1 - at; n > 0; n--) app.pop();
        else app.push(to);
      }}
    />
  );
}

/** Opens an entry as its kind wants. */
function open(station: string, root: string, dir: string, e: DriveEntry, preview: (e: DriveEntry) => void) {
  const path = join(dir, e.name);
  switch (e.kind) {
    case "folder": app.push({ kind: "Drive", station, root, path }); break;
    case "text": case "markdown": app.push({ kind: "DriveRead", station, root, path }); break;
    case "video": case "audio": app.push({ kind: "DrivePlay", station, root, path }); break;
    case "image": case "pdf": case "code": case "csv": case "html": case "subtitle": preview(e); break;
    default: openElsewhere(station, root, e, path, false);
  }
}

function EntryRow({ station, root, path, e, first, last, chosen = null, onOpen, onHold }: {
  station: string; root: string; path: string; e: DriveEntry; first: boolean; last: boolean; chosen?: boolean | null; onOpen: () => void; onHold: () => void;
}) {
  const C = useC();
  const removing = useDoing("drive.remove", { root, path });
  const renaming = useDoing("drive.rename", { root, from: path });
  const busy = removing || renaming;
  const removeFailed = useDoingFailed("drive.remove", { root, path });
  const renameFailed = useDoingFailed("drive.rename", { root, from: path });
  const failed = removeFailed ?? renameFailed;
  useWatched(DriveFetches.changes);
  const fetching = DriveFetches.progress.get(DriveFetches.id(station, root, path));
  const line = e.dir ? e.timeText : [e.sizeText, e.timeText].filter((it) => it.length > 0).join(" · ");
  let end: ReactNode = null;
  if (busy || failed !== undefined) end = <DoingMark running={busy} failed={failed ?? null} inline />;
  else if (fetching !== undefined) end = <DownloadChip percent={fetching} />;
  else if (e.kind === "text" || e.kind === "markdown") end = <ReadShare station={station} root={root} path={path} />;
  else if (e.dir) end = <IconIn icon={Icons.ChevronRight} size={14} tint={C.subtle} />;
  return (
    <CardRow first={first} last={last} ground={chosen === true ? withAlpha(C.accent, 0.12) : C.surface} enabled={!busy} onPress={onOpen} onLongPress={onHold} style={{ paddingHorizontal: 16, paddingVertical: 11 }}>
      {/* Choosing: each row's mark says whether it is chosen. */}
      {chosen !== null ? (
        <View style={{ width: 22, height: 22, borderRadius: 11, backgroundColor: chosen ? C.accent : withAlpha(C.ink, 0.08), alignItems: "center", justifyContent: "center" }}>
          {chosen ? <IconIn icon={Icons.Check} size={14} tint={C.surface} /> : null}
        </View>
      ) : <IconIn icon={kindIcon(e.kind)} size={22} tint={C.muted} />}
      <View style={{ flex: 1, minWidth: 0 }}>
        <T size={15} line={20} color={C.ink} numberOfLines={1}>{e.name}</T>
        {line.length > 0 ? <T size={12} line={16} color={C.muted} numberOfLines={1}>{line}</T> : null}
      </View>
      {end}
    </CardRow>
  );
}

/** A file going up: its name, how far it has got (a thin bar); its name taken there (replace or keep both), or why it failed. */
function UploadRow({ u, first, last, held }: { u: DriveUpload; first: boolean; last: boolean; held: () => readonly DriveEntry[] }) {
  const C = useC();
  useWatched(DriveUploads.changes);
  let status: ReactNode;
  if (u.state === "taken") {
    status = (
      <View style={{ flexDirection: "row", alignItems: "center", gap: 12 }}>
        <T size={12} line={16} color={C.muted}>{t("android-misc.drive.exists.title")}</T>
        <Pressable onPress={() => DriveUploads.settle(u, true)} android_ripple={ripple(C.ink)}><T size={12} line={16} weight="600" color={C.accent}>{t("android-misc.drive.exists.replace")}</T></Pressable>
        <Pressable onPress={() => DriveUploads.settle(u, false)} android_ripple={ripple(C.ink)}><T size={12} line={16} weight="600" color={C.accent}>{t("android-misc.drive.exists.both")}</T></Pressable>
      </View>
    );
  } else if (u.state === "failed") {
    status = <T size={12} line={16} color={C.red} numberOfLines={2}>{t("android-misc.drive.upload.failed", { error: u.error ?? "" })}</T>;
  } else {
    status = (
      <>
        <T size={12} line={16} color={C.muted} numberOfLines={1}>{t("android-misc.drive.upload.going", { sent: fileSize(u.sent), size: fileSize(u.size) })}</T>
        {/* Its size not known: a sweep. */}
        <Progress part={u.size > 0 ? u.sent / u.size : null} style={{ marginTop: 5 }} />
      </>
    );
  }
  return (
    <CardRow first={first} last={last} ground={C.surface} style={{ paddingLeft: 16, paddingRight: 8, paddingTop: 11, paddingBottom: 11 }}>
      <IconIn icon={Icons.Upload} size={22} tint={C.muted} />
      <View style={{ flex: 1, minWidth: 0 }}>
        <T size={15} line={20} color={C.ink} numberOfLines={1}>{u.name}</T>
        {status}
      </View>
      {u.state === "failed" ? <RowKey icon={Icons.Retry} label={t("android-misc.drive.retry")} onClick={() => DriveUploads.retry(u, held)} /> : null}
      <RowKey icon={Icons.Close} label={t("common.cancel")} onClick={() => DriveUploads.cancel(u)} />
    </CardRow>
  );
}

function RowKey({ icon, label, onClick }: { icon: IconPaths; label: string; onClick: () => void }) {
  const C = useC();
  return (
    <Pressable
      onPress={onClick} accessibilityLabel={label} android_ripple={{ ...ripple(C.ink), borderless: true, radius: 17 }}
      style={{ width: 34, height: 34, borderRadius: 17, overflow: "hidden", alignItems: "center", justifyContent: "center" }}
    >
      <IconIn icon={icon} size={16} tint={C.muted} />
    </Pressable>
  );
}

/** How far a text has been read on this device, when it has been opened: grey, as every ordinary figure is. */
function ReadShare({ station, root, path }: { station: string; root: string; path: string }) {
  const C = useC();
  const place = useTopic<DrivePlace>({ topic: "drivePlace", station, root, path });
  const p = place.value;
  if (!p) return null;
  const of = p.of !== undefined && p.of > 0 ? p.of : null;
  if (of === null) return null;
  const share = Math.min(Math.max(p.at / of, 0), 1);
  // Opened and left at its start: nothing read yet.
  if (share < 0.01) return null;
  return <T size={12} color={C.muted}>{share >= 0.995 ? t("android-misc.drive.read.done") : `${Math.trunc(share * 100)}%`}</T>;
}

// ── what can be done to an entry ────────────────────────────────────────

/** How a folder is shown on this device, as the web's: its order, and whether hidden files show; with the folders lent, for those who name them. */
function openViewSheet(station: string, manage: boolean) {
  const sorts = ["name", "time", "size", "kind"];
  app.sheet = sheet({ height: 0.5, fit: fit(sorts.length + 1 + (manage ? 1 : 0)), content: () => <ViewSheet station={station} manage={manage} sorts={sorts} /> });
}

function ViewSheet({ station, manage, sorts }: { station: string; manage: boolean; sorts: string[] }) {
  const C = useC();
  const view = useDriveView();
  const by = view.sort.split("-")[0];
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-misc.drive.view")} />
      <ScrollView style={{ flex: 1 }}>
        {sorts.map((it) => <PickRow key={it} label={t(`web-pages.drive.sortBy.${it}`)} checked={by === it} onClick={() => setDriveView("sort", it === "name" ? null : it)} />)}
        <PickRow label={t("web-pages.drive.showHidden")} checked={view.hidden} onClick={() => setDriveView("hidden", view.hidden ? null : "shown")} />
        {manage ? <PickRow label={t("android-misc.drive.roots.manage")} leading={<IconIn icon={Icons.Folder} size={20} tint={C.ink} />} onClick={() => openRoots(station)} /> : null}
      </ScrollView>
    </>
  );
}

/** What is chosen, from the bar over it: one as a row held always was (rename, download, share…); several downloaded, their paths copied, deleted. */
function openChosenSheet(station: string, root: string, dir: string, items: DriveEntry[], can: DriveRights, names: ReadonlySet<string>, done: () => void) {
  if (items.length === 0) return;
  if (items.length === 1) return openEntrySheet(station, root, dir, items[0]!, can, names, done);
  const files = items.filter((it) => !it.dir);
  app.sheet = sheet({
    height: 0.4, fit: fit((files.length > 0 ? 1 : 0) + 1 + (can.write ? 1 : 0)), content: () => <ChosenSheet station={station} root={root} dir={dir} items={items} files={files} can={can} done={done} />,
  });
}

function ChosenSheet({ station, root, dir, items, files, can, done }: { station: string; root: string; dir: string; items: DriveEntry[]; files: DriveEntry[]; can: DriveRights; done: () => void }) {
  const C = useC();
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-misc.drive.chosen", { n: items.length })} />
      {files.length > 0 ? (
        <PickRow
          label={t("web-pages.drive.downloadMany", { n: files.length })} leading={<IconIn icon={Icons.Download} size={20} tint={C.ink} />}
          onClick={() => { app.sheet = null; done(); files.forEach((it) => saveToDownloads(station, root, it, join(dir, it.name))); }}
        />
      ) : null}
      <PickRow
        label={t("web-pages.drive.copyPaths")} leading={<IconIn icon={Icons.Copy} size={20} tint={C.ink} />}
        onClick={() => { app.sheet = null; done(); copyPaths(items.map((it) => absoluteIn(root, join(dir, it.name)))); }}
      />
      {can.write ? (
        <PickRow
          label={t(can.trash ? "web-pages.drive.toTrashMany" : "web-pages.drive.deleteMany", { n: items.length })} color={C.accent} leading={<IconIn icon={Icons.Trash} size={20} tint={C.accent} />}
          onClick={() => { app.sheet = null; done(); removeAll(station, root, dir, items, can.trash); }}
        />
      ) : null}
    </>
  );
}

/** One entry: renamed and deleted by those who may change the drive; a file downloaded and shared, a folder downloaded as a zip; its path copied. */
function openEntrySheet(station: string, root: string, dir: string, e: DriveEntry, can: DriveRights, names: ReadonlySet<string>, done: () => void) {
  const zip = e.dir && can.zip;
  const rows = (can.write ? 2 : 0) + (e.dir ? (zip ? 1 : 0) : 2) + 1;
  app.sheet = sheet({ height: 0.5, fit: fit(rows), content: () => <EntrySheet station={station} root={root} dir={dir} e={e} can={can} names={names} done={done} zip={zip} /> });
}

function EntrySheet({ station, root, dir, e, can, names, done, zip }: { station: string; root: string; dir: string; e: DriveEntry; can: DriveRights; names: ReadonlySet<string>; done: () => void; zip: boolean }) {
  const C = useC();
  const path = join(dir, e.name);
  return (
    <>
      <SheetGrab />
      <SheetHead title={e.name} />
      <ScrollView style={{ flex: 1 }}>
        {can.write ? (
          <PickRow
            label={t("android-misc.drive.rename")} leading={<IconIn icon={Icons.Edit} size={20} tint={C.ink} />}
            onClick={() => {
              done();
              ask(app, t("android-misc.drive.rename"), e.name, e.name, t("common.save"), { what: t("android-misc.drive.rename.what") }, async (name: string) => {
                const problem = nameProblem(name);
                if (problem !== null) throw coreError("invalid", problem);
                if (name !== e.name && names.has(name)) throw coreError("exists", t("station.drive.exists"));
                await app.api(station).driveRename(root, path, join(dir, name));
              });
            }}
          />
        ) : null}
        {!e.dir ? (
          <>
            <PickRow
              label={t("android-misc.drive.download")} leading={<IconIn icon={Icons.Download} size={20} tint={C.ink} />}
              onClick={() => { app.sheet = null; done(); app.toast = t("android-misc.drive.downloading", { name: e.name }); saveToDownloads(station, root, e, path); }}
            />
            <PickRow
              label={t("android-misc.drive.share")} leading={<IconIn icon={Icons.External} size={20} tint={C.ink} />}
              onClick={() => { app.sheet = null; done(); openElsewhere(station, root, e, path, true); }}
            />
          </>
        ) : zip ? (
          <PickRow
            label={t("web-pages.drive.downloadZip")} leading={<IconIn icon={Icons.Download} size={20} tint={C.ink} />}
            onClick={() => { app.sheet = null; done(); app.toast = t("android-misc.drive.downloading", { name: `${e.name}.zip` }); saveZip(station, root, path); }}
          />
        ) : null}
        <PickRow
          label={t("web-pages.drive.copyPath")} leading={<IconIn icon={Icons.Copy} size={20} tint={C.ink} />}
          onClick={() => { app.sheet = null; done(); copyPaths([absoluteIn(root, path)]); }}
        />
        {can.write ? (
          <PickRow
            label={t(can.trash ? "web-pages.drive.toTrash" : "android-misc.drive.remove")} color={C.accent} leading={<IconIn icon={Icons.Trash} size={20} tint={C.accent} />}
            onClick={() => { done(); removeAll(station, root, dir, [e], can.trash); }}
          />
        ) : null}
      </ScrollView>
    </>
  );
}

/** Paths on the clipboard, a line each. */
function copyPaths(paths: string[]) {
  void Clipboard.setStringAsync(paths.join("\n"));
  app.toast = t("web-pages.drive.pathCopied");
}

/** A folder zipped on the station and saved into the phone's Downloads. */
function saveZip(station: string, root: string, path: string) {
  void (async () => {
    try {
      const z = await app.api(station).driveZip(root, path);
      saveToDownloads(station, z.root, { name: z.name, dir: false, size: z.size, mtime: 0, type: "application/zip", kind: "other", sizeText: "", timeText: "" }, z.path);
    } catch (e) {
      app.toast = t("android-misc.drive.fetchFailed", { name: nameOf(path), error: errorOf(e) });
    }
  })();
}

/**
 * Deleted: to the machine's trash where the station has one, nothing asked (said once done); where none takes them (or
 * a station without one), asked first, then for good.
 */
function removeAll(station: string, root: string, dir: string, items: DriveEntry[], trash: boolean) {
  const forGood = (list: DriveEntry[]) => {
    const one = list.length === 1 ? list[0]! : null;
    confirm(
      app,
      one !== null ? t(one.dir ? "android-misc.drive.remove.folderTitle" : "android-misc.drive.remove.fileTitle", { name: one.name }) : t("web-pages.drive.deleteManyAsk", { n: list.length }),
      t(list.some((it) => it.dir) ? "android-misc.drive.remove.folderText" : "android-misc.drive.remove.fileText"),
      t("android-misc.drive.remove"), { danger: true, what: t("android-misc.drive.remove.what") },
      async () => { for (const it of list) await app.api(station).driveRemove(root, join(dir, it.name), true); },
    );
  };
  if (!trash) return forGood(items);
  app.act(t("android-misc.drive.remove.what"), async () => {
    const left: DriveEntry[] = [];
    for (const e of items) {
      try { await app.api(station).driveRemove(root, join(dir, e.name)); } catch (x) { if (codeOf(x) === "no_trash") left.push(e); else throw x; }
    }
    if (left.length > 0) forGood(left); else app.toast = t("web-pages.drive.trashed", { n: items.length });
  });
}

/** A new folder in `dir`, named here. */
function newFolder(station: string, root: string, dir: string) {
  ask(app, t("android-misc.drive.mkdir"), "", t("android-misc.drive.mkdir.placeholder"), t("android-misc.drive.mkdir.make"), { what: t("android-misc.drive.mkdir.what") }, async (name: string) => {
    const problem = nameProblem(name);
    if (problem !== null) throw coreError("invalid", problem);
    await app.api(station).driveMkdir(root, join(dir, name));
  });
}

// ── the folders lent ────────────────────────────────────────────────────

/** The folders the station lends (the owners and admins): each tapped to stop lending it; another one added. */
function openRoots(station: string) {
  app.sheet = sheet({ height: 0.7, draggable: true, content: () => <RootsSheet station={station} /> });
}

function RootsSheet({ station }: { station: string }) {
  const C = useC();
  const workspace = station.split("/")[0]!;
  const stations = useTopic<StationView[]>({ topic: "stations", scope: workspace });
  const roots = stations.value?.find((it) => it.station === station)?.overview?.drive?.roots ?? [];
  const setting = useDoing("drive.setRoots");
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-misc.drive.roots.manage")} trailing={setting ? <Spinner /> : null} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 24 }}>
        <T size={13} color={C.muted} style={{ paddingLeft: 20, paddingRight: 20, paddingBottom: 6 }}>{t("android-misc.drive.roots.note")}</T>
        {roots.map((r) => {
          const trouble = rootTrouble(r.state);
          return (
            <PickRow
              key={r.path} label={r.name} sub={r.path} leading={<IconIn icon={Icons.Folder} size={20} tint={C.ink} />}
              mark={trouble !== null ? <T size={12} color={C.red}>{trouble[0]}</T> : null}
              onClick={() => unshare(station, roots, r)}
            />
          );
        })}
        <PickRow label={t("android-misc.drive.roots.add")} color={C.accent} leading={<IconIn icon={Icons.Plus} size={20} tint={C.accent} />} onClick={() => openFolderPicker(station, roots.map((it) => it.path))} />
      </ScrollView>
    </>
  );
}

/** Where the picker is: the folder asked for (null: the home), the way there as known before the station answers, whether its row said the station may not read it. */
interface PickAt { path: string | null; way: DriveCrumb[]; unreadable: boolean }

/** The way to `path` as the station would give it: from the home when it is under it (its name the station's word for it), else from the top. */
function wayTo(path: string, here: DriveFolders): DriveCrumb[] {
  const home = (here.home ?? "").replace(/[/\\]+$/, "");
  const first = here.crumbs?.[0];
  const homeName = first !== undefined && first.path === here.home ? first.name : null;
  const under = homeName !== null && home.length > 0 && (path === here.home || path.startsWith(`${home}/`) || path.startsWith(`${home}\\`));
  const top: DriveCrumb = under ? { name: homeName!, path: here.home! } : { name: "/", path: "/" };
  let at = under ? home : "";
  const rest = under ? path.substring(home.length) : path;
  return [top, ...rest.split(/[/\\]/).filter((it) => it.length > 0).map((it) => { at = `${at}/${it}`; return { name: it, path: at }; })];
}

/**
 * The station's folders, from its home: the way there on top (each step a way back), a filter for the names, then at the
 * home the usual places (its own folders, the disks) over its folders. A folder the station may not read says so; it can
 * be entered but not lent, and how to let the station read it is told. `lent`: the folders lent already.
 */
export function openFolderPicker(station: string, lent: readonly string[]): void {
  app.sheet = sheet({ height: 0.85, draggable: true, content: () => <FolderPicker station={station} lent={lent} /> });
}

type PickItem = { key: string; kind: "error" | "denied" | "reading" | "none" | "places" | "folders" } | { key: string; folder: PickFolder; go: () => void };

function FolderPicker({ station, lent }: { station: string; lent: readonly string[] }) {
  const C = useC();
  const [at, setAt] = useState<PickAt>({ path: null, way: [], unreadable: false });
  const [shown, setShown] = useState<DriveFolders | null>(null);
  const [denied, setDenied] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState("");
  const input = useRef<TextInput>(null);
  // Each place asked for anew; a later one supersedes what is still on its way.
  useEffect(() => {
    let live = true;
    setShown(null); setError(null); setDenied(at.unreadable);
    app.api(station).driveFolders(at.path).then(
      (it: DriveFolders) => { if (live) { setShown(it); setDenied(it.unreadable === true); } },
      (e: unknown) => { if (!live) return; if (codeOf(e) === "permission") setDenied(true); else setError(errorOf(e)); },
    );
    return () => { live = false; };
  }, [at]);
  const go = (to: PickAt) => { setFilter(""); input.current?.blur(); setAt(to); };
  const here = shown;
  // A station from before gives neither the way nor where each folder is: made from the path.
  const way = here !== null ? (here.crumbs ?? wayTo(here.path, here)) : at.way;
  const entries: PickFolder[] = here !== null ? (here.entries ?? (here.folders ?? []).map((it) => ({ name: it, path: `${here.path.replace(/\/+$/, "")}/${it}`, unreadable: false, disk: false }))) : [];
  const wanted = filter.trim();
  const places = here !== null && here.path === here.home && wanted.length === 0 ? (here.places ?? []).filter((it) => it.path !== here.home) : [];
  // At home the usual places are above: not listed again under their names on disk.
  const listed = wanted.length === 0 ? entries.filter((e) => !places.some((it) => it.path === e.path)) : entries.filter((it) => it.name.toLowerCase().includes(wanted.toLowerCase()));
  const items: PickItem[] = [];
  if (error !== null) items.push({ key: "error", kind: "error" });
  else if (denied) items.push({ key: "denied", kind: "denied" });
  // Each folder gone into is read anew: a line, said only when it takes a while (no shapes flashing at each step).
  else if (here === null) items.push({ key: "reading", kind: "reading" });
  else {
    if (places.length > 0) {
      items.push({ key: "places", kind: "places" });
      places.forEach((p) => items.push({ key: `p:${p.path}`, folder: p, go: () => go({ path: p.path, way: wayTo(p.path, here), unreadable: p.unreadable === true }) }));
      items.push({ key: "folders", kind: "folders" });
    }
    if (listed.length === 0) items.push({ key: "none", kind: "none" });
    listed.forEach((e) => items.push({ key: `f:${e.path}`, folder: e, go: () => go({ path: e.path, way: [...way, { name: e.name, path: e.path }], unreadable: e.unreadable === true }) }));
  }
  const taken = here !== null && lent.includes(here.path);
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-misc.drive.pick.title")} />
      <PickCrumbs way={way} onPick={(i, c) => go({ path: c.path, way: way.slice(0, i + 1), unreadable: false })} />
      <PickFilter text={filter} onChange={setFilter} input={input} />
      {/* Each folder from its top (one list's scroll is not the next folder's). */}
      <FlatList
        key={at.path ?? ""}
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingBottom: 8 }}
        keyboardShouldPersistTaps="handled"
        data={items}
        keyExtractor={(it) => it.key}
        renderItem={({ item }) => {
          if ("folder" in item) return <PickFolderRow f={item.folder} onClick={item.go} />;
          switch (item.kind) {
            case "error": return <T size={13} color={C.red} style={{ paddingHorizontal: 20, paddingVertical: 8 }}>{error}</T>;
            case "denied": return <Note text={t("android-misc.drive.pick.unreadable")} />;
            case "reading": return <WaitLine text={t("common.reading")} style={{ paddingHorizontal: 20, paddingVertical: 12 }} />;
            case "places": return <SectionHeader title={t("android-misc.drive.pick.places")} />;
            case "folders": return <SectionHeader title={t("android-misc.drive.pick.folders")} />;
            case "none": return (
              <T size={13} color={C.muted} style={{ paddingHorizontal: 20, paddingVertical: 12 }}>
                {wanted.length === 0 ? t("android-misc.drive.pick.empty") : t("android-misc.drive.pick.noMatch", { q: wanted })}
              </T>
            );
          }
        }}
      />
      {denied ? <T size={13} color={C.muted} style={{ paddingLeft: 20, paddingRight: 20, paddingTop: 8 }}>{t("android-misc.drive.pick.unreadableNote")}</T> : null}
      <View style={{ flexDirection: "row", justifyContent: "flex-end", gap: 8, paddingLeft: 20, paddingRight: 20, paddingTop: 8, paddingBottom: 16 }}>
        <Button label={t("common.cancel")} primary={false} onClick={() => { app.sheet = null; }} />
        <Button
          label={taken ? t("android-misc.drive.pick.already") : t("android-misc.drive.pick.choose")} primary enabled={here !== null && !taken && !denied}
          onClick={() => {
            const p = here?.path;
            if (p === undefined) return;
            app.sheet = null;
            const trimmed = p.replace(/\/+$/, "");
            app.act(t("android-misc.drive.roots.what"), () => app.api(station).driveSetRoots([...lent, p]), t("android-misc.drive.roots.added", { name: trimmed.substring(trimmed.lastIndexOf("/") + 1) || p }));
          }}
        />
      </View>
    </>
  );
}

/** The way to the folder shown, scrolled to its end: each step but the last a way back to it. */
function PickCrumbs({ way, onPick }: { way: DriveCrumb[]; onPick: (i: number, c: DriveCrumb) => void }) {
  return (
    <View style={{ minHeight: 28 }}>
      <Trail labels={way.map((it) => it.name)} size={14} style={{ paddingLeft: 17, paddingRight: 20, paddingBottom: 8, minHeight: 28 }} onPick={(i) => onPick(i, way[i]!)} />
    </View>
  );
}

/** A pill to type a part of a folder's name in: only those with it are listed; × clears it. */
function PickFilter({ text, onChange, input }: { text: string; onChange: (s: string) => void; input: RefObject<TextInput | null> }) {
  const C = useC();
  return (
    <View style={{ paddingHorizontal: 20, paddingBottom: 6 }}>
      <View style={{ height: 38, borderRadius: 19, backgroundColor: withAlpha(C.ink, 0.06), paddingLeft: 12, paddingRight: 6, flexDirection: "row", alignItems: "center", gap: 8 }}>
        <IconIn icon={Icons.Search} size={16} tint={C.muted} />
        <View style={{ flex: 1, justifyContent: "center" }}>
          <TextInput
            ref={input} value={text} onChangeText={onChange} multiline={false} returnKeyType="done"
            placeholder={t("android-misc.drive.pick.filter")} placeholderTextColor={C.muted} cursorColor={C.accent} selectionColor={withAlpha(C.accent, 0.4)}
            accessibilityLabel={t("android-misc.drive.pick.filter")}
            style={{ fontSize: sp(15), color: C.ink, padding: 0, includeFontPadding: false }}
          />
        </View>
        {text.length > 0 ? (
          <Pressable
            onPress={() => onChange("")} accessibilityLabel={t("android-misc.drive.pick.filterClear")} android_ripple={{ ...ripple(C.ink), borderless: true, radius: 14 }}
            style={{ width: 28, height: 28, borderRadius: 14, overflow: "hidden", alignItems: "center", justifyContent: "center" }}
          >
            <IconIn icon={Icons.Close} size={14} tint={C.muted} />
          </Pressable>
        ) : null}
      </View>
    </View>
  );
}

/** A folder or a place to go into: a disk's mark for a disk; whether the station may not read it, under its name. */
function PickFolderRow({ f, onClick }: { f: PickFolder; onClick: () => void }) {
  const C = useC();
  return <PickRow label={f.name} sub={f.unreadable ? t("android-misc.drive.pick.unreadable") : null} leading={<IconIn icon={f.disk ? Icons.Disk : Icons.Folder} size={20} tint={C.ink} />} onClick={onClick} />;
}
