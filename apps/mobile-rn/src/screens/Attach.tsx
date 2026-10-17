// ＋ in a composer: the gallery's recent photos across the top, a tap putting one in the message (most of what goes to
// an agent is a screenshot just taken), the camera before them; under them the system's photo picker, its file picker
// and (where there is one) Station 文件. The recent photos need the gallery's permission, asked for from the strip's
// last tile (on Android 14 and later the photos chosen there may be all it gets: the tile then chooses more); without
// it the strip is the camera and that tile. The phone's web cannot read a gallery: there ＋ is a menu (mobile/Chat.tsx).
//
// Here the system's pickers are expo-image-picker's (the camera, the photo picker) and expo-document-picker's (the
// file picker); the gallery is read through expo-media-library.
import * as DocumentPicker from "expo-document-picker";
import * as ImagePicker from "expo-image-picker";
import * as MediaLibrary from "expo-media-library";
import { useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { FlatList, Image, Linking, Pressable, View } from "react-native";
import type { AppState } from "../AppState";
import { t } from "../i18n";
import { Icon, Icons } from "../ui/Icon";
import type { IconPaths } from "../ui/IconSet";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";
import { SheetGrab } from "../ui/Sheet";
import { photoPicked, readPicked, type Picked } from "./Composer";

/** A count that can be watched (MutableIntState there): the gallery's answers. */
export class Answered {
  #value = 0;
  readonly #listeners = new Set<() => void>();
  get intValue(): number { return this.#value; }
  bump() { this.#value++; for (const l of this.#listeners) l(); }
  subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
}

/** What ＋ offers: the system's camera, photo and file pickers, a recent photo of the gallery's put in, and asking for the gallery. */
export class Attach {
  constructor(
    readonly camera: () => void,
    readonly photos: () => void,
    readonly files: () => void,
    readonly recent: (uri: string, name?: string | null) => void = () => {},
    readonly askPhotos: () => void = () => {},
    /** Counts the gallery's answers, for the strip to read it again after one. */
    readonly answered: Answered = new Answered(),
  ) {}
}

/** How much of the gallery the app may read: all of it, the photos chosen for it (Android 14 and later), or none. */
export enum PhotoAccess { All = "All", Some = "Some", None = "None" }

export async function photoAccess(): Promise<PhotoAccess> {
  try {
    const p = await MediaLibrary.getPermissionsAsync(false, ["photo"]);
    if (!p.granted) return PhotoAccess.None;
    return p.accessPrivileges === "limited" ? PhotoAccess.Some : p.accessPrivileges === "none" ? PhotoAccess.None : PhotoAccess.All;
  } catch {
    return PhotoAccess.None;
  }
}

/**
 * The ways ＋ picks (rememberLauncherForActivityResult there), each picked file handed to `onPicked` as it is read. A
 * hook, called as a composable is.
 */
export function AttachLaunchers(onPicked: (picked: Picked) => void): Attach {
  const latest = useRef(onPicked);
  latest.current = onPicked;
  return useMemo(() => {
    const picked = (p: Picked | null) => { if (p) latest.current(p); };
    const answered = new Answered();
    return new Attach(
      // The camera's photo, as TakePicturePreview hands one back: a JPEG at 90 (photoPicked).
      () => {
        void (async () => {
          const allowed = await ImagePicker.requestCameraPermissionsAsync().catch(() => null);
          if (!allowed?.granted) return;
          const shot = await ImagePicker.launchCameraAsync({ mediaTypes: ["images"], quality: 0.9 }).catch(() => null);
          const a = shot && !shot.canceled ? shot.assets[0] : undefined;
          if (a) picked(await photoPicked(a));
        })();
      },
      // The system's photo picker, images only, as many as are chosen.
      () => {
        void (async () => {
          const got = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ["images"], allowsMultipleSelection: true, quality: 1 }).catch(() => null);
          if (!got || got.canceled) return;
          for (const a of got.assets) picked(await readPicked(a.uri, a.fileName ?? null, a.fileSize ?? null));
        })();
      },
      // The system's file picker, any file, read from where it is (not copied first).
      () => {
        void (async () => {
          const got = await DocumentPicker.getDocumentAsync({ type: "*/*", multiple: true, copyToCacheDirectory: false }).catch(() => null);
          if (!got || got.canceled) return;
          for (const a of got.assets) picked(await readPicked(a.uri, a.name, a.size ?? null));
        })();
      },
      (uri, name) => { void readPicked(uri, name ?? null, null).then(picked); },
      () => {
        void (async () => {
          // Asked and turned down for good (the system shows no dialog any more): the app's settings, where it is allowed.
          const now = await MediaLibrary.getPermissionsAsync(false, ["photo"]).catch(() => null);
          const refused = now != null && !now.granted && !now.canAskAgain;
          if (refused) { void Linking.openSettings(); return; }
          await MediaLibrary.requestPermissionsAsync(false, ["photo"]).catch(() => null);
          answered.bump();
        })();
      },
      answered,
    );
  }, []);
}

/** The same hook by a hook's name. */
export const useAttachLaunchers = AttachLaunchers;

const RECENT = 30;
/** A recent photo's tile, for the tests. */
export const RECENT_TAG = "attach-recent";
const TILE_W = 92;
const TILE_H = 122;

/** ＋'s sheet: the recent photos, then 照片, 文件 and (`station`) Station 文件. As tall as those two rows. */
export function openAttach(app: AppState, attach: Attach, station: (() => void) | null = null) {
  app.sheet = {
    height: 0.32,
    fit: 25 + 4 + TILE_H + 12 + 70 + 18,
    content: () => <AttachSheet app={app} attach={attach} station={station} />,
  };
}

function AttachSheet({ app, attach, station }: { app: AppState; attach: Attach; station: (() => void) | null }) {
  const C = useC();
  const ways: [string, IconPaths, () => void][] = [
    [t("android-chat.attach.photos"), Icons.Photo, attach.photos],
    [t("android-chat.attach.files"), Icons.File, attach.files],
    ...(station ? [[t("web-pages.chat.files"), Icons.Server, station] as [string, IconPaths, () => void]] : []),
  ];
  return (
    <>
      <SheetGrab />
      <RecentPhotos app={app} attach={attach} />
      <View style={{ width: "100%", paddingLeft: 12, paddingRight: 12, paddingBottom: 18, flexDirection: "row", gap: 8 }}>
        {ways.map(([label, icon, go]) => (
          // Its name under its icon, the tile's whole width for it (Station files, on a phone set to show things large).
          <Smooth key={label} radius={14} style={{ flex: 1, height: 70, backgroundColor: C.chip }}>
            <Pressable
              onPress={() => { app.sheet = null; go(); }}
              android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false }}
              style={{ flex: 1, paddingHorizontal: 4, alignItems: "center", justifyContent: "center", gap: 6 }}
            >
              <Icon icon={icon} size={22} color={C.ink} />
              <T size={13} line={18} color={C.ink} numberOfLines={1} ellipsizeMode="tail">{label}</T>
            </Pressable>
          </Smooth>
        ))}
      </View>
    </>
  );
}

/** A photo of the gallery's in the strip: where it is read from, and its file's name. */
interface Recent { uri: string; name: string | null }

type StripItem = { kind: "camera" } | { kind: "photo"; photo: Recent } | { kind: "ask" };

function RecentPhotos({ app, attach }: { app: AppState; attach: Attach }) {
  const answers = useSyncExternalStore(attach.answered.subscribe, () => attach.answered.intValue);
  // Read again on each answer of the gallery's, and as the sheet opens (allowed meanwhile in the system's settings).
  const [access, setAccess] = useState<PhotoAccess | null>(null);
  const [photos, setPhotos] = useState<Recent[]>([]);
  useEffect(() => {
    let live = true;
    void photoAccess().then(async (a) => {
      if (!live) return;
      setAccess(a);
      const list = a === PhotoAccess.None ? [] : await recentPhotos();
      if (live) setPhotos(list);
    });
    return () => { live = false; };
  }, [answers]);
  const items: StripItem[] = [
    { kind: "camera" },
    ...photos.map((photo): StripItem => ({ kind: "photo", photo })),
    ...(access !== null && access !== PhotoAccess.All ? [{ kind: "ask" } as StripItem] : []),
  ];
  const C = useC();
  return (
    <FlatList
      horizontal
      data={items}
      keyExtractor={(i) => (i.kind === "photo" ? i.photo.uri : i.kind)}
      showsHorizontalScrollIndicator={false}
      style={{ width: "100%", flexGrow: 0 }}
      contentContainerStyle={{ paddingLeft: 12, paddingRight: 12, paddingTop: 4, paddingBottom: 12, gap: 6 }}
      renderItem={({ item }) => {
        if (item.kind === "camera") return <Tile onClick={() => { app.sheet = null; attach.camera(); }}><Icon icon={Icons.Camera} size={24} color={C.ink} /></Tile>;
        if (item.kind === "photo") return <Tile testID={RECENT_TAG} onClick={() => { app.sheet = null; attach.recent(item.photo.uri, item.photo.name); }}><Thumbnail uri={item.photo.uri} /></Tile>;
        const words = access === PhotoAccess.Some ? t("android-chat.attach.recent.more") : t("android-chat.attach.recent.allow");
        return <Tile onClick={attach.askPhotos}><Words icon={Icons.Photo} words={words} /></Tile>;
      }}
    />
  );
}

function Tile({ onClick, testID, children }: { onClick: () => void; testID?: string; children: ReactNode }) {
  const C = useC();
  return (
    <Smooth radius={14} style={{ width: TILE_W, height: TILE_H, backgroundColor: C.chip }}>
      <Pressable testID={testID} onPress={onClick} android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false, foreground: true }} style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
        {children}
      </Pressable>
    </Smooth>
  );
}

function Words({ icon, words }: { icon: IconPaths; words: string }) {
  const C = useC();
  return (
    <View style={{ paddingHorizontal: 8, alignItems: "center", gap: 8 }}>
      <Icon icon={icon} size={22} color={C.muted} />
      <T size={12} line={16} color={C.muted} align="center">{words}</T>
    </View>
  );
}

/** A photo's small picture (loadThumbnail at 276 × 366 there): the image read down to about that. */
function Thumbnail({ uri }: { uri: string }) {
  return <Image source={{ uri, width: 276, height: 366 }} resizeMode="cover" resizeMethod="resize" style={{ position: "absolute", left: 0, top: 0, right: 0, bottom: 0 }} />;
}

/**
 * The gallery's latest photos, as many as it lets the app read. Not as the gallery sorts them: what it says of when a
 * photo came may be wrong (written in milliseconds, or ahead of now, by an app saving a picture or a phone maker's own
 * gallery and cloud), and that put old photos ahead of every screenshot since. Each photo's times are read (changed,
 * taken: expo-media-library does not give when it was added) and the latest believable one of them ranks it (`latest`).
 */
async function recentPhotos(): Promise<Recent[]> {
  const all: GalleryPhoto[] = [];
  const by = new Map<number, Recent>();
  try {
    let after: string | undefined;
    for (;;) {
      const page = await MediaLibrary.getAssetsAsync({ mediaType: MediaLibrary.MediaType.photo, first: 1000, ...(after ? { after } : {}) });
      for (const a of page.assets) {
        const id = Number(a.id);
        if (!Number.isFinite(id)) continue;
        // Both in milliseconds here; in seconds as the gallery keeps them.
        all.push(new GalleryPhoto(id, null, a.modificationTime ? Math.floor(a.modificationTime / 1000) : null, a.creationTime ? Math.floor(a.creationTime / 1000) : null));
        by.set(id, { uri: a.uri, name: a.filename ?? null });
      }
      if (!page.hasNextPage) break;
      after = page.endCursor;
    }
  } catch {
    return [];
  }
  return latest(all, Math.floor(Date.now() / 1000), RECENT).flatMap((id) => { const r = by.get(id); return r ? [r] : []; });
}

/** A photo of the gallery's and what it says of when, each in seconds (as it says them: perhaps wrong). */
export class GalleryPhoto {
  constructor(readonly id: number, readonly added: number | null, readonly modified: number | null, readonly taken: number | null) {}
}

/**
 * The ids of the `n` photos latest at `now` (seconds), newest first: each by the latest of its times that can be
 * believed, a time in milliseconds taken as the seconds it means and one still ahead of now (by more than a day) left
 * out; the gallery's own order (its id) between photos of the same time.
 */
export function latest(photos: GalleryPhoto[], now: number, n: number): number[] {
  const believed = (t: number | null): number | null => {
    if (t == null) return null;
    const s = t > 100_000_000_000 ? Math.floor(t / 1000) : t;
    return s >= 1 && s <= now + 86_400 ? s : null;
  };
  return photos
    .map((p): [number, number] => {
      const times = [believed(p.added), believed(p.modified), believed(p.taken)].filter((x): x is number => x != null);
      return [p.id, times.length ? Math.max(...times) : 0];
    })
    .sort((a, b) => (b[1] - a[1]) || (b[0] - a[0]))
    .slice(0, n)
    .map((p) => p[0]);
}
