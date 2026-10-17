// The archive (web/src/pages/Archive.tsx): chats archived by hand or by the station once they idled (a day by
// default), of every station online in one list, newest first and grouped by the day they were archived. Each can be
// opened to read (its composer restores it), put back in the list, and one archived with its session deleted for good. Anything new said in a chat the station
// archived brings it back by itself; one archived by hand takes no messages until shown again. A row: its title with when (and where) at the end of its line, then what can be done with it; its
// last message the whole line under it. No lines between.
import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { FlatList, Pressable, TextInput, View, type ViewToken } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import type { ArchiveItem, ArchiveView } from "../../../../web/src/core/shapes.ts";
import { app as theApp, useApp } from "../AppState";
import type { WorkspaceEntry } from "../data/Accounts";
import { ChatOf, rememberTopic, Topics } from "../data/Topics";
import { t } from "../i18n";
import { placeLabel } from "../Places";
import { DoingMark } from "../ui/Controls";
import { Icons } from "../ui/Icon";
import type { IconPaths } from "../ui/IconSet";
import { IconIn, ripple, SectionHeader } from "../ui/Parts";
import { Smooth } from "../ui/Smooth";
import { sp, T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";
import { Spinner, Waiting } from "../ui/Waiting";
import { PlacePage } from "./PlacePage";
import { PlaceEmpty } from "./PlaceRows";
import { confirm } from "./Settings";
import { BarRoom } from "./Stations";

interface Entry { key: string; draw: () => ReactNode }

export function ArchiveScreen({ current }: { current: WorkspaceEntry }) {
  const app = theApp;
  const C = useC();
  const insets = useSafeAreaInsets();
  useApp((s) => s.doing);
  // It can be very long: only those with the words looked for, and only the newest so many, more as it is scrolled near
  // its end; every station's archive as the core puts it together, and takes a chat out of once restored or deleted.
  const [q, setQ] = useState("");
  const [limit, setLimit] = useState(Topics.ARCHIVE_PAGE);
  const archive = rememberTopic<ArchiveView>(Topics.archive(current.workspace.id, q.trim(), limit));
  // Asked for more (or other words), what was shown stays until it comes: no rows taken away meanwhile.
  const last = useRef<ArchiveView | null>(null);
  if (archive.value != null) last.current = archive.value;
  const view = archive.value ?? last.current;
  const restore = (item: ArchiveItem) => app.act(t("android-misc.archive.restoreWhat"), () => app.api(item.station).setArchived(item.thread ?? null, item.session, false), t("android-misc.archive.restored"));
  const remove = (item: ArchiveItem) => {
    confirm(app, t("android-misc.archive.deleteTitle", { title: item.title }), t("android-misc.archive.deleteText"), t("common.delete"), true,
      t("android-misc.archive.deleteWhat"), null, async () => {
        await app.api(item.station).deleteSession(item.session);
        app.toast = t("android-misc.archive.deleted");
      });
  };
  // A screen or so before the end, the next rows.
  const [near, setNear] = useState(false);
  const entries: Entry[] = [];
  entries.push({ key: "search", draw: () => <ArchiveSearch q={q} onChange={(it) => { setQ(it); setLimit(Topics.ARCHIVE_PAGE); }} /> });
  // Nothing to show yet and still read (or some stations' could not be): the first read's shapes, what is waited on and
  // the stations that failed as its pills (so not their red lines too).
  if (view == null || (view.days.length === 0 && (view.wait.reading || view.wait.failing.length > 0))) {
    entries.push({ key: "wait", draw: () => <Waiting note={view?.wait} text={t("common.readingStations")} error={view == null ? archive.error?.message : null} /> });
  } else {
    for (const e of view.errors) entries.push({ key: `error/${e.station}`, draw: () => <T size={13} color={C.red} style={{ paddingHorizontal: 20, paddingVertical: 8 }}>{e.text}</T> });
    const note = view.note;
    if (note != null) entries.push({ key: "note", draw: () => <T size={14} color={C.muted} style={{ paddingHorizontal: 20, paddingVertical: 12 }}>{note}</T> });
    // What lands here, said only while nothing has.
    if (view.days.length === 0 && q.trim() === "") entries.push({ key: "empty", draw: () => <PlaceEmpty text={t("android-misc.archive.note")} /> });
    for (const day of view.days) {
      entries.push({ key: `day/${day.label}`, draw: () => <SectionHeader title={day.label} /> });
      for (const item of day.items) {
        entries.push({
          key: `${item.station}/${item.thread ?? item.session}`,
          draw: () => {
            // Restoring or deleting it under way: a spinner in place of its actions; failed: a red mark beside them a moment.
            const busy = app.isDoing("chat.archive", { station: item.station, session: item.session }) ||
              app.isDoing("session.delete", { station: item.station, key: item.session });
            const failed = app.failedOf("chat.archive", { station: item.station, session: item.session })
              ?? app.failedOf("session.delete", { station: item.station, key: item.session });
            // Tapped, its chat: read there, and restored from its composer.
            return <ArchiveRow item={item} busy={busy} failed={failed} onOpen={() => app.push({ kind: "Chat", station: item.station, of: ChatOf.Session(item.session) })} onRestore={() => restore(item)} onDelete={() => remove(item)} />;
          },
        });
      }
    }
  }
  entries.push({ key: "room", draw: () => <BarRoom /> });
  const countRef = useRef(entries.length);
  countRef.current = entries.length;
  const seen = useCallback(({ viewableItems }: { viewableItems: ViewToken<Entry>[] }) => {
    const lastShown = viewableItems.reduce((n, it) => Math.max(n, it.index ?? -1), -1);
    setNear(lastShown >= 0 && lastShown >= countRef.current - 12);
  }, []);
  useEffect(() => { if (near && view?.more === true) setLimit((n) => n + Topics.ARCHIVE_PAGE); }, [near, view]);
  // 令 in the bar's notch, as on the chats' list; nothing of its own to add.
  return (
    <PlacePage current={current} place="archive" primary={null} back={placeLabel("chats")} content={(top: number) => (
      <FlatList
        style={{ flex: 1 }}
        data={entries}
        keyExtractor={(it) => it.key}
        renderItem={({ item }) => <>{item.draw()}</>}
        onViewableItemsChanged={seen}
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={{ paddingTop: top, paddingBottom: 24 + insets.bottom }}
      />
    )} />
  );
}

/** Looking for one by its title or last line: the chats' search field (Search.tsx), over the list. */
function ArchiveSearch({ q, onChange }: { q: string; onChange: (q: string) => void }) {
  const C = useC();
  return (
    <View style={{ paddingLeft: 16, paddingRight: 16, paddingTop: 4, paddingBottom: 8 }}>
      <Smooth radius={19} style={{ height: 38, backgroundColor: withAlpha(C.ink, 0.06), paddingHorizontal: 12, flexDirection: "row", alignItems: "center", gap: 8 }}>
        <IconIn icon={Icons.Search} size={17} tint={C.muted} />
        {/* Its hint a Text of its own under the field, as Kotlin's (a TextInput's placeholder sits lower than a Text). */}
        <View style={{ flex: 1, minWidth: 0, justifyContent: "center" }}>
          {q.length === 0 && <T size={16} color={C.muted} numberOfLines={1} style={{ position: "absolute", left: 0, right: 0 }}>{t("web-pages.archive.search")}</T>}
          <TextInput
            value={q}
            onChangeText={onChange}
            accessibilityLabel={t("web-pages.archive.search")}
            returnKeyType="search"
            cursorColor={C.accent}
            selectionColor={withAlpha(C.accent, 0.4)}
            numberOfLines={1}
            style={{ fontSize: sp(16), color: C.ink, padding: 0, margin: 0, includeFontPadding: false }}
          />
        </View>
      </Smooth>
    </View>
  );
}

function ArchiveRow({ item, busy, failed, onOpen, onRestore, onDelete }: { item: ArchiveItem; busy: boolean; failed: string | null; onOpen: () => void; onRestore: () => void; onDelete: () => void }) {
  const C = useC();
  return (
    <Pressable onPress={onOpen} android_ripple={ripple(C.ink)} style={{ alignSelf: "stretch", paddingLeft: 20, paddingRight: 10, paddingTop: 6, paddingBottom: 6 }}>
      <View style={{ height: 34, flexDirection: "row", alignItems: "center", gap: 10 }}>
        <T size={16} line={22} color={C.ink} numberOfLines={1} ellipsizeMode="tail" style={{ flex: 1, minWidth: 0 }}>{item.title}</T>
        {/* When (and where), then what can be done: no pointer to point with, so always there. */}
        <T size={12} color={C.subtle} numberOfLines={1} accessibilityLabel={item.how}>{[item.place, item.clock].filter((x) => x != null).join("  ")}</T>
        {busy ? (
          <View style={{ width: 34, height: 34, alignItems: "center", justifyContent: "center" }}><Spinner /></View>
        ) : (
          <View style={{ flexDirection: "row", alignItems: "center" }}>
            {failed != null && <View style={{ width: 34, height: 34, alignItems: "center", justifyContent: "center" }}><DoingMark running={false} failed={failed} /></View>}
            <Action icon={Icons.Retry} label={t("android-misc.archive.restoreNamed", { title: item.title })} onClick={onRestore} />
            {item.deletable && <Action icon={Icons.Trash} label={t("android-misc.archive.deleteNamed", { title: item.title })} onClick={onDelete} />}
          </View>
        )}
      </View>
      <T size={14} line={20} color={C.muted} numberOfLines={1} ellipsizeMode="tail" style={{ paddingRight: 10 }}>{item.last}</T>
    </Pressable>
  );
}

export function Action({ icon, label, onClick }: { icon: IconPaths; label: string; onClick: () => void }) {
  const C = useC();
  return (
    <Pressable accessibilityLabel={label} onPress={onClick} android_ripple={ripple(C.ink)} style={{ width: 34, height: 34, borderRadius: 17, overflow: "hidden", alignItems: "center", justifyContent: "center" }}>
      <IconIn icon={icon} size={16} tint={C.muted} />
    </Pressable>
  );
}
