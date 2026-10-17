// What changed in still.fail, as the narrow web has it (web/src/mobile/Changelog.tsx), from the core's `changelog` topic
// (client/core-ts/src/changelog.ts): the settings' 更新日志 page, a tab a part (this app's first), by day on cards, each
// change with where it is and whether this app has it; and at the top of the list, what the last update brought, until
// the page is opened or it is put away (`changelog.seen`).
import { useEffect, useState } from "react";
import { Pressable, ScrollView, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import type { ChangelogItem, ChangelogLine, ChangelogNews as News, ChangelogView } from "../../../../web/src/core/shapes.ts";
import { app as theApp, type AppState } from "../AppState";
import { rememberTopic, Topics } from "../data/Topics";
import { t } from "../i18n";
import { Icons } from "../ui/Icon";
import { IconIn, LargeTitle, ListCard, ripple, SectionHeader, Seg } from "../ui/Parts";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { useC } from "../ui/Theme";
import { WaitShape, Waiting } from "../ui/Waiting";
import { TopBack } from "./Stations";

/** Says the changelog was seen up to this build: what it brought is not news any more. */
async function seen(app: AppState) {
  try { await app.core.call("changelog.seen", {}); } catch { /* not said: it stays news */ }
}

export function ChangelogScreen() {
  const app = theApp;
  const C = useC();
  const insets = useSafeAreaInsets();
  const topic = rememberTopic<ChangelogView>(Topics.changelog);
  const view = topic.value;
  // Opened: what the update brought is read.
  const news = view?.news != null;
  useEffect(() => { if (news) void seen(app); }, [news, app]);
  const [part, setPart] = useState<string | null>(null);
  const tabs = view?.tabs ?? [];
  const at = Math.max(0, tabs.findIndex((it) => it.part === part));
  const tab = tabs[at];
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom }}>
      <TopBack label={t("android-settings.title")} onBack={() => app.pop()} />
      <LargeTitle small={view?.build != null ? t("android-settings.changelog.build", { build: view.build }) : ""} big={t("android-settings.changelog.title")} />
      {tab != null && (
        <View style={{ paddingLeft: 16, paddingRight: 16, paddingTop: 4, paddingBottom: 2, alignSelf: "stretch" }}>
          <Seg options={tabs.map((it) => it.label)} selected={at} onSelect={(i: number) => setPart(tabs[i]!.part)} height={34} fill />
        </View>
      )}
      {view == null || view.loading === true ? <Waiting shape={WaitShape.Cards} text={t("common.reading")} error={topic.error?.message} />
        : view.error != null ? <T size={14} color={C.red} style={{ paddingHorizontal: 24, paddingVertical: 8 }}>{view.error}</T>
        : tab == null || tab.days.length === 0 ? <T size={14} color={C.muted} style={{ paddingHorizontal: 24, paddingVertical: 8 }}>{t("android-settings.changelog.empty")}</T>
        : tab.days.map((day) => (
          <View key={day.label}>
            <SectionHeader title={day.label} start={24} />
            <ListCard>{day.entries.map((it, i) => <Change key={`${it.version}/${i}`} item={it} />)}</ListCard>
          </View>
        ))}
      <View style={{ height: 30 }} />
    </ScrollView>
  );
}

/** One change: each line led by its kind on a small tinted label (the accent's for something new), then its version and
 *  what is not out yet (in the accent: an update would bring it). */
function Change({ item }: { item: ChangelogItem }) {
  const C = useC();
  return (
    <View style={{ alignSelf: "stretch", paddingHorizontal: 16, paddingVertical: 10, gap: 2 }}>
      {item.lines.map((it, i) => <Line key={i} line={it} />)}
      <View style={{ flexDirection: "row", gap: 10 }}>
        <T size={13} line={18} color={C.muted}>{item.versionName}</T>
        {item.note !== "" && <T size={13} line={18} color={item.has === false ? C.accentInk : C.muted} style={{ flexShrink: 1 }}>{item.note}</T>}
      </View>
    </View>
  );
}

/** A line, its kind's label inline before it so the text wraps under it. */
function Line({ line }: { line: ChangelogLine }) {
  const C = useC();
  if (line.label === "") return <T size={15} line={21} color={C.ink}>{line.text}</T>;
  const isNew = line.kind === "new";
  // The label as wide as its words and 12 more, then 6 of room; 19 tall, on the middle of the line.
  return (
    <T size={15} line={21} color={C.ink}>
      <View style={{ paddingRight: 6, height: 19, transform: [{ translateY: 4 }] }}>
        <Smooth radius={6} style={{ height: 19, paddingHorizontal: 6, backgroundColor: isNew ? C.accentBg : C.chip, alignItems: "center", justifyContent: "center" }}>
          <T size={13} line={19} color={isNew ? C.accentInk : C.muted} numberOfLines={1}>{line.label}</T>
        </Smooth>
      </View>
      {line.text}
    </T>
  );
}

/** At the top of the list after an update: the build it is now and what it brought; opens the changelog. */
export function ChangelogNews() {
  const app = theApp;
  const C = useC();
  const topic = rememberTopic<ChangelogView>(Topics.changelog);
  // Let go (知道了): gone at once, before the core has it.
  const [gone, setGone] = useState<News | null>(null);
  const news = topic.value?.news;
  if (news == null || gone === news) return null;
  const lines = news.entries.flatMap((it) => it.text);
  return (
    <View style={{ paddingLeft: 12, paddingRight: 12, paddingTop: 4, paddingBottom: 10, alignSelf: "stretch" }}>
      <Smooth radius={16} style={{ backgroundColor: C.surface }}>
        <Pressable onPress={() => app.push({ kind: "Changelog" })} android_ripple={ripple(C.ink)} style={{ paddingLeft: 16, paddingRight: 44, paddingTop: 12, paddingBottom: 12, gap: 2 }}>
          <View style={{ flexDirection: "row", paddingBottom: 2, alignItems: "center", gap: 6 }}>
            <IconIn icon={Icons.Sparks} size={16} tint={C.ink} />
            <T size={15} weight="600" color={C.ink}>{news.build != null ? t("android-settings.changelog.updatedTo", { build: news.build }) : t("android-settings.changelog.updated")}</T>
          </View>
          {lines.slice(0, 3).map((it, i) => <T key={i} size={13} line={18} color={C.muted} numberOfLines={1} ellipsizeMode="tail">{it}</T>)}
          {lines.length > 3 && <T size={13} line={18} color={C.muted}>{t("android-settings.changelog.more", { n: lines.length - 3 })}</T>}
        </Pressable>
        <Pressable
          accessibilityLabel={t("android-settings.changelog.dismiss")}
          onPress={() => { setGone(news); void seen(app); }}
          android_ripple={ripple(C.ink)}
          style={{ position: "absolute", top: 6, right: 6, width: 32, height: 32, borderRadius: 16, overflow: "hidden", alignItems: "center", justifyContent: "center" }}
        >
          <IconIn icon={Icons.Close} size={16} tint={C.muted} />
        </Pressable>
      </Smooth>
    </View>
  );
}
