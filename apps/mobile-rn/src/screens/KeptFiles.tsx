// What this phone keeps, by chat: each chat's messages as the core keeps them (`cache.usage`) and the files opened in it
// (the players, PDFs, a big file fetched a part at a time: in the app's cache, each under its own name in a directory
// of its own, cache/files/<id>-<size>/<name>, with the station and session it came from beside it); then what belongs
// to no chat: files opened from stations' drives (DriveCache, which lets the least lately opened go by itself past its
// bounds), web pages' cache, update packages, other temporary files, and the core's own data. Nothing else is deleted by
// itself: a file, a chat's all, or everything, when the person says.
import { useEffect, useState } from "react";
import { Pressable, ScrollView, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { Directory, File, Paths } from "expo-file-system";
import { app as theApp, type AppState } from "../AppState";
import { DriveCache } from "../data/DriveCache";
import { t } from "../i18n";
import { fileSize } from "../ui/Controls";
import { Icons } from "../ui/Icon";
import { IconIn, LargeTitle, ListCard, ListRow, ripple, SectionHeader } from "../ui/Parts";
import { T } from "../ui/Text";
import { useC } from "../ui/Theme";
import { confirm } from "./Settings";
import { PageNote } from "./SettingParts";
import { TopBack } from "./Stations";

/** A file kept on the phone: where it is, its name, how big, when last opened; `partial`, a fetch that stopped;
 * `station` and `session`, where it came from (none for one kept before that was written beside it). */
export class KeptFile {
  constructor(readonly file: File, readonly name: string, readonly size: number, readonly opened: number, readonly partial: boolean, readonly station: string | null, readonly session: string | null) {}
}

/** A chat as kept here: its messages (`messages`, as the core counts them) and the files opened in it. */
export class KeptChat {
  constructor(readonly station: string, readonly thread: number, readonly title: string, readonly messages: number, readonly files: KeptFile[]) {}
  get size() { return this.messages + this.files.reduce((n, f) => n + f.size, 0); }
}

/** What is kept here: by chat, files of no chat known, and what belongs to no chat. */
export class Kept {
  constructor(readonly chats: KeptChat[], readonly loose: KeptFile[], readonly drive: number, readonly web: number, readonly updates: number, readonly temporary: number, readonly data: number) {}
  get total() { return this.chats.reduce((n, c) => n + c.size, 0) + this.loose.reduce((n, f) => n + f.size, 0) + this.drive + this.web + this.updates + this.temporary + this.data; }
}

/** Java's String.hashCode, as Integer.toHexString shows it: the directory a file's id is kept under, as the Android app names it. */
function hashHex(text: string): string {
  let h = 0;
  for (let i = 0; i < text.length; i++) h = (Math.imul(31, h) + text.charCodeAt(i)) | 0;
  return (h >>> 0).toString(16);
}

const ORIGIN = ".origin";

function sizeOf(f: File | Directory): number {
  if (f instanceof Directory) return f.exists ? f.list().reduce((n: number, it: File | Directory) => n + sizeOf(it), 0) : 0;
  return f.exists ? (f.size ?? 0) : 0;
}

const webCache = () => new Directory(Paths.cache, "WebView");
const updates = () => new Directory(Paths.cache, "updates");
/** Temporary files of the app's own (a marked image made, say): the cache but for what is counted apart. */
function temporary(): (File | Directory)[] {
  const apart = new Set(["files", "WebView", "updates", DriveCache.dir().name, DriveCache.playedDir().name]);
  const cache = new Directory(Paths.cache);
  return cache.exists ? cache.list().filter((it: File | Directory) => !apart.has(it.name)) : [];
}

function deleteAll(d: Directory) { if (d.exists) d.delete(); }

export const KeptFiles = {
  dir: () => new Directory(Paths.cache, "files"),

  /** Where a file (by its id, `<station>/<session>/<path>`, and size) is kept, under its own name; its directory made,
   * where it came from written beside it. */
  place(id: string, name: string, size: number): File {
    const safe = (name.slice(name.lastIndexOf("/") + 1).replace(/[\u0000-\u001f]/g, "_").replace(/^\.+/, "").slice(0, 120)) || "file";
    const home = new Directory(KeptFiles.dir(), `${hashHex(id)}-${size}`);
    if (!home.exists) home.create({ intermediates: true });
    const origin = new File(home, ORIGIN);
    if (!origin.exists) origin.write(id);
    return new File(home, safe);
  },

  /** Every file kept, the latest opened first: each in its directory, and loose ones from before names were kept. */
  list(): KeptFile[] {
    const out: KeptFile[] = [];
    const add = (f: File, origin: string | null) => {
      const partial = f.name.endsWith(".part");
      const parts = origin?.split("/");
      const [station, session] = parts != null && parts.length >= 3 ? [`${parts[0]}/${parts[1]}`, parts[2]!] : [null, null];
      out.push(new KeptFile(f, partial ? f.name.slice(0, -".part".length) : f.name, f.size ?? 0, f.modificationTime ?? 0, partial, station, session));
    };
    const dir = KeptFiles.dir();
    if (dir.exists) for (const f of dir.list()) {
      if (f instanceof Directory) {
        const o = new File(f, ORIGIN);
        const origin = o.exists ? o.textSync() : null;
        for (const it of f.list()) if (it instanceof File && it.name !== ORIGIN) add(it, origin);
      } else add(f, null);
    }
    return out.sort((a, b) => b.opened - a.opened);
  },

  /** Deletes a kept file (its directory with it, once nothing else is in it). */
  delete(kept: KeptFile) {
    if (kept.file.exists) kept.file.delete();
    const home = kept.file.parentDirectory;
    if (home.uri === KeptFiles.dir().uri) return;
    if (home.exists && home.list().every((it: File | Directory) => it.name === ORIGIN)) home.delete();
  },

  /** Everything kept, read now: the core says what it keeps of each chat. */
  async read(app: AppState): Promise<Kept> {
    let usage: { station: string; thread: number; sessions?: string[]; title?: string | null; bytes?: number }[] = [];
    try { usage = ((await app.core.call("cache.usage", {})) as { chats?: typeof usage } | null)?.chats ?? []; } catch { usage = []; }
    const files = KeptFiles.list();
    const bySession = new Map<string, KeptFile[]>();
    for (const f of files) if (f.station != null) {
      const k = `${f.station}\u0000${f.session}`;
      bySession.set(k, [...(bySession.get(k) ?? []), f]);
    }
    const used = new Set<KeptFile>();
    const chats = usage.map((o) => {
      const mine = (o.sessions ?? []).flatMap((s) => bySession.get(`${o.station}\u0000${s}`) ?? []).filter((f) => { if (used.has(f)) return false; used.add(f); return true; });
      return new KeptChat(o.station, o.thread, o.title ?? t("android-settings.files.untitled", { n: o.thread }), o.bytes ?? 0, mine);
    });
    const loose = files.filter((f) => !used.has(f));
    const data = Math.max(0, sizeOf(new Directory(Paths.document, "stillfail-core")) - chats.reduce((n, c) => n + c.messages, 0));
    return new Kept(chats.sort((a, b) => b.size - a.size), loose, DriveCache.size(), sizeOf(webCache()), sizeOf(updates()), temporary().reduce((n, it) => n + sizeOf(it), 0), data);
  },

  /** Forgets a chat's messages (read again from its station when it is opened) and deletes its files. */
  async clearChat(app: AppState, chat: KeptChat) {
    await app.core.call("cache.clear", { station: chat.station, thread: chat.thread });
    for (const f of chat.files) KeptFiles.delete(f);
  },

  async clearDrive() { DriveCache.clear(); },
  async clearWeb() { deleteAll(webCache()); },
  async clearUpdates() { deleteAll(updates()); },
  async clearTemporary() { for (const it of temporary()) it.delete(); },

  /** Everything that can go: every chat's, files of no chat, files opened from drives, web pages', update packages, temporary files. */
  async clearAll(app: AppState, kept: Kept) {
    for (const c of kept.chats) await KeptFiles.clearChat(app, c);
    for (const f of kept.loose) KeptFiles.delete(f);
    await KeptFiles.clearDrive(); await KeptFiles.clearWeb(); await KeptFiles.clearUpdates(); await KeptFiles.clearTemporary();
  },
};

/** How long ago, in the app's words: just now, minutes, hours, days. */
function since(at: number): string {
  const minutes = Math.floor((Date.now() - at) / 60_000);
  if (minutes < 1) return t("android-settings.files.justNow");
  if (minutes < 60) return t("android-settings.files.minutes", { n: minutes });
  if (minutes < 24 * 60) return t("android-settings.files.hours", { n: Math.floor(minutes / 60) });
  return t("android-settings.files.days", { n: Math.floor(minutes / (24 * 60)) });
}

/** What is kept, read now, and again whenever `version` changes. */
function rememberKept(version: number): Kept | null {
  const [kept, setKept] = useState<Kept | null>(null);
  useEffect(() => {
    let gone = false;
    void KeptFiles.read(theApp).then((k) => { if (!gone) setKept(k); });
    return () => { gone = true; };
  }, [version]);
  return kept;
}

function SizeRow({ title, sub, size, onClick, chevron = onClick != null }: { title: string; sub: string | null; size: number; onClick: (() => void) | null; chevron?: boolean }) {
  const C = useC();
  return (
    <ListRow onClick={onClick}>
      <View style={{ flex: 1, minWidth: 0 }}>
        <T size={15} color={C.ink} numberOfLines={1} ellipsizeMode="tail">{title}</T>
        {sub != null && <T size={13} color={C.muted} numberOfLines={1} ellipsizeMode="tail">{sub}</T>}
      </View>
      <T size={14} color={C.muted}>{fileSize(size)}</T>
      {chevron && <IconIn icon={Icons.ChevronRight} size={14} tint={C.subtle} />}
    </ListRow>
  );
}

function DangerRow({ label, onClick }: { label: string; onClick: () => void }) {
  const C = useC();
  return <ListCard><ListRow onClick={onClick}><T size={15} color={C.red}>{label}</T></ListRow></ListCard>;
}

/** Everything this phone keeps: by chat, then what belongs to no chat. */
export function KeptFilesScreen() {
  const app = theApp;
  const insets = useSafeAreaInsets();
  const [version, setVersion] = useState(0);
  const kept = rememberKept(version);
  const ask = (title: string, text: string, run: () => Promise<void>) =>
    confirm(app, title, text, t("android-settings.files.clear.action"), true, null, null, async () => { await run(); setVersion((v) => v + 1); });
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom }}>
      <TopBack label={t("android-settings.title")} onBack={() => app.pop()} />
      <LargeTitle small="" big={t("android-settings.files.title")} />
      <PageNote text={t("android-settings.files.note")} />
      {kept != null && (
        <>
          <SectionHeader title={t("android-settings.files.byChat")} trailing={t("android-settings.files.total", { size: fileSize(kept.total) })} start={24} />
          {kept.chats.length === 0 ? <PageNote text={t("android-settings.files.none")} /> : (
            <ListCard>
              {kept.chats.map((c) => {
                const sub = c.files.length === 0 ? t("android-settings.files.chat.messages", { size: fileSize(c.messages) })
                  : t("android-settings.files.chat.both", { size: fileSize(c.messages), n: c.files.length, files: fileSize(c.files.reduce((n, f) => n + f.size, 0)) });
                return <SizeRow key={`${c.station}/${c.thread}`} title={c.title} sub={sub} size={c.size} onClick={() => app.push({ kind: "KeptChat", station: c.station, thread: c.thread })} />;
              })}
            </ListCard>
          )}
          <SectionHeader title={t("android-settings.files.other")} start={24} />
          <ListCard>
            {kept.loose.length > 0 && <SizeRow title={t("android-settings.files.loose")} sub={t("android-settings.files.count", { n: kept.loose.length })} size={kept.loose.reduce((n, f) => n + f.size, 0)} onClick={() => app.push({ kind: "KeptChat", station: null, thread: null })} />}
            <SizeRow title={t("android-settings.files.drive")} sub={t("android-settings.files.drive.sub")} size={kept.drive} onClick={kept.drive > 0 ? () => ask(t("android-settings.files.drive"), t("android-settings.files.drive.text"), () => KeptFiles.clearDrive()) : null} chevron={false} />
            <SizeRow title={t("android-settings.files.web")} sub={null} size={kept.web} onClick={kept.web > 0 ? () => ask(t("android-settings.files.web"), t("android-settings.files.web.text"), () => KeptFiles.clearWeb()) : null} chevron={false} />
            <SizeRow title={t("android-settings.files.updates")} sub={null} size={kept.updates} onClick={kept.updates > 0 ? () => ask(t("android-settings.files.updates"), t("android-settings.files.updates.text"), () => KeptFiles.clearUpdates()) : null} chevron={false} />
            <SizeRow title={t("android-settings.files.temporary")} sub={null} size={kept.temporary} onClick={kept.temporary > 0 ? () => ask(t("android-settings.files.temporary"), t("android-settings.files.temporary.text"), () => KeptFiles.clearTemporary()) : null} chevron={false} />
            <SizeRow title={t("android-settings.files.data")} sub={t("android-settings.files.data.text")} size={kept.data} onClick={null} />
          </ListCard>
          {kept.total > kept.data && (
            <DangerRow label={t("android-settings.files.clearAll")} onClick={() => {
              ask(t("android-settings.files.clearAll.title"), t("android-settings.files.clearAll.text", { size: fileSize(kept.total - kept.data) }), () => KeptFiles.clearAll(app, kept));
            }} />
          )}
        </>
      )}
      <View style={{ height: 30 }} />
    </ScrollView>
  );
}

/** A chat's: its messages and the files opened in it, each to delete, or all of it. No chat: files of no chat known. */
export function KeptChatScreen({ station, thread }: { station: string | null; thread: number | null }) {
  const app = theApp;
  const C = useC();
  const insets = useSafeAreaInsets();
  const [version, setVersion] = useState(0);
  const kept = rememberKept(version);
  const chat = kept?.chats.find((c) => c.station === station && c.thread === thread) ?? null;
  const files = station == null ? (kept?.loose ?? []) : (chat?.files ?? []);
  const all = (chat?.size ?? 0) + (station == null ? files.reduce((n, f) => n + f.size, 0) : 0);
  const again = () => setVersion((v) => v + 1);
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom }}>
      <TopBack label={t("android-settings.files.title")} onBack={() => app.pop()} />
      <LargeTitle small="" big={station == null ? t("android-settings.files.loose") : (chat?.title ?? "")} />
      {kept != null && (
        <>
          {chat != null && (
            <ListCard>
              <SizeRow title={t("android-settings.files.messages")} sub={t("android-settings.files.messages.text")} size={chat.messages} onClick={chat.messages > 0 ? () => {
                confirm(app, t("android-settings.files.messages"), t("android-settings.files.messages.clear"), t("android-settings.files.clear.action"), true, null, null, async () => {
                  await app.core.call("cache.clear", { station: chat.station, thread: chat.thread }); again();
                });
              } : null} chevron={false} />
            </ListCard>
          )}
          {files.length > 0 && (
            <>
              <SectionHeader title={t("android-settings.files.files")} trailing={t("android-settings.files.filesTotal", { n: files.length, size: fileSize(files.reduce((n, f) => n + f.size, 0)) })} start={24} />
              <ListCard>
                {files.map((f) => (
                  <ListRow key={f.file.uri}>
                    <View style={{ flex: 1, minWidth: 0 }}>
                      <T size={15} color={C.ink} numberOfLines={1} ellipsizeMode="tail">{f.name}</T>
                      <T size={13} color={C.muted} numberOfLines={1} ellipsizeMode="tail">{f.partial ? t("android-settings.files.partial", { size: fileSize(f.size) }) : t("android-settings.files.meta", { size: fileSize(f.size), opened: since(f.opened) })}</T>
                    </View>
                    <Pressable onPress={() => { KeptFiles.delete(f); again(); }} android_ripple={ripple(C.ink)} style={{ width: 36, height: 36, borderRadius: 18, overflow: "hidden", alignItems: "center", justifyContent: "center" }}>
                      <IconIn icon={Icons.Trash} size={18} tint={C.muted} />
                    </Pressable>
                  </ListRow>
                ))}
              </ListCard>
            </>
          )}
          {all > 0 && (
            <DangerRow label={t("android-settings.files.clearChat")} onClick={() => {
              confirm(app, t("android-settings.files.clearChat"), t("android-settings.files.clearChat.text", { size: fileSize(all) }), t("android-settings.files.clear.action"), true, null, null, async () => {
                if (chat != null) await KeptFiles.clearChat(app, chat); else for (const f of files) KeptFiles.delete(f);
                again();
              });
            }} />
          )}
        </>
      )}
      <View style={{ height: 30 }} />
    </ScrollView>
  );
}
