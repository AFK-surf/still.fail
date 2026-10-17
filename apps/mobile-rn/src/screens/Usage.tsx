// What the agents spent, from settings, as the narrow web has it (web/src/mobile/Usage.tsx): the core's `usage` view
// (client/core-ts/src/views/usage.ts) for the last 7 or 30 days. A few totals, each day's cost as a bar split by who it was
// for (tapped, the day says its numbers: there is no hover here), and who, which chats, which accounts and which
// models spent the most. Everything shown is the core's; the page only picks the days and the list.
import { useState } from "react";
import { Pressable, ScrollView, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import type { UsageDay, UsageItem, UsageList, UsageSeries, UsageView } from "../../../../web/src/core/shapes.ts";
import { app as theApp } from "../AppState";
import type { WorkspaceEntry } from "../data/Accounts";
import { ChatOf, rememberTopic, Topics } from "../data/Topics";
import { t } from "../i18n";
import { Markdown } from "../ui/Markdown";
import { Avatar, Card, LargeTitle, ripple, Seg } from "../ui/Parts";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { useC, withAlpha, type StillFailColors } from "../ui/Theme";
import { WaitShape, Waiting } from "../ui/Waiting";
import { PlacePage } from "./PlacePage";
import { PlaceEmpty } from "./PlaceRows";
import { PageNote } from "./SettingParts";
import { BarRoom, TopBack } from "./Stations";

const DAYS = (): [number, string][] => [[7, t("android-misc.usage.days", { n: 7 })], [30, t("android-misc.usage.days", { n: 30 })]];

// The people a day's bar is split by, as the web draws them (web/src/Usage.css.ts): checked for colour-blind readers
// on both grounds; the first is still.fail's accent, stepped down in dark.
const LIGHT = ["#EF6A3C", "#2A78D6", "#1BAF7A", "#4A3AA7"];
const DARK = ["#E0602F", "#3987E5", "#199E70", "#9085E9"];

function seriesColor(C: StillFailColors, series: UsageSeries[], i: number): string {
  return series[i]?.key === "" ? withAlpha(C.subtle, 0.45) : (C.dark ? DARK : LIGHT)[i % 4]!;
}

export function UsageScreen({ current }: { current: WorkspaceEntry }) {
  const app = theApp;
  const C = useC();
  const insets = useSafeAreaInsets();
  const [days, setDays] = useState(7);
  const topic = rememberTopic<UsageView>(Topics.usage(current.workspace.id, days));
  const view = topic.value;
  const options = DAYS();
  // Its days are its own action, at the top bar's right; nothing to add.
  return (
    <PlacePage current={current} place="usage" primary={null} actions={() => (
      <Seg options={options.map((it) => it[1])} selected={Math.max(0, options.findIndex((it) => it[0] === days))} onSelect={(i: number) => setDays(options[i]![0])} />
    )} content={(top: number) => (
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingTop: top, paddingBottom: insets.bottom }}>
        {view == null ? (
          <Waiting shape={WaitShape.Cards} text={t("common.reading")} error={topic.error ? t("android-misc.usage.loadFailed", { error: topic.error.message }) : null} />
        ) : (
          <>
            <Tiles view={view} openPrices={() => app.push({ kind: "UsagePrices", days })} />
            {/* None counted yet: the stations not read yet, or those that could not be; else none at all, what the page
                counts said with it. */}
            {view.empty && (view.wait.reading || view.wait.failing.length > 0) ? <Waiting shape={WaitShape.Cards} count={2} note={view.wait} />
              : view.empty ? <PlaceEmpty text={t("android-misc.usage.none")} note={t("android-misc.usage.note")} />
              : (
                <>
                  <Card><Days view={view} /></Card>
                  <Lists view={view} open={(item) => {
                    const chat = item.chat;
                    if (chat == null) return;
                    const of = chat.thread != null ? ChatOf.Thread(chat.thread) : chat.session != null ? ChatOf.Session(chat.session) : null;
                    if (of == null) return;
                    app.push({ kind: "Chat", station: chat.station, of });
                  }} />
                </>
              )}
            <View style={{ paddingHorizontal: 24, paddingVertical: 6, gap: 4 }}>
              {[...view.notes, view.basis].map((it, i) => <T key={i} size={12} color={C.subtle}>{it}</T>)}
            </View>
          </>
        )}
        <View style={{ height: 30 }} />
        <BarRoom />
      </ScrollView>
    )} />
  );
}

/** The totals, two to a row. */
function Tiles({ view, openPrices }: { view: UsageView; openPrices: () => void }) {
  const C = useC();
  const pairs: (typeof view.tiles)[] = [];
  for (let i = 0; i < view.tiles.length; i += 2) pairs.push(view.tiles.slice(i, i + 2));
  const first = view.tiles[0];
  return (
    <View style={{ paddingHorizontal: 12, paddingBottom: 10, gap: 10 }}>
      {pairs.map((pair, r) => (
        <View key={r} style={{ flexDirection: "row", gap: 10 }}>
          {pair.map((tile, i) => {
            const isFirst = tile === first;
            return (
              <Smooth key={i} radius={18} style={{ flex: 1, backgroundColor: C.surface }}>
                <Pressable disabled={!isFirst} onPress={openPrices} android_ripple={isFirst ? ripple(C.ink) : undefined} style={{ paddingHorizontal: 16, paddingVertical: 14 }}>
                  <T size={12} color={C.muted}>{tile.label}</T>
                  <T size={22} weight="700" color={C.ink} numberOfLines={1}>{tile.value}</T>
                  <T size={12} color={C.subtle} numberOfLines={1} ellipsizeMode="tail">{isFirst ? t("android-misc.usage.seePrices") : tile.sub}</T>
                </Pressable>
              </Smooth>
            );
          })}
          {pair.length === 1 && <View style={{ flex: 1 }} />}
        </View>
      ))}
    </View>
  );
}

/** Each day's cost as a bar, split by who it was for; the day tapped (today at first) says its numbers under them. */
function Days({ view }: { view: UsageView }) {
  const C = useC();
  // The day picked, as long as the page's days are the same.
  const [picked, setPicked] = useState<{ days: number; day: string | null }>({ days: view.days, day: null });
  const pickedDay = picked.days === view.days ? picked.day : null;
  const day = view.daily.find((d) => d.day === pickedDay) ?? view.daily[view.daily.length - 1];
  const several = view.series.length > 1;
  const many = view.daily.length > 10;
  const gap = many ? 3 : 6;
  return (
    <>
      {several && (
        <View style={{ flexDirection: "row", paddingBottom: 10, gap: 12, alignItems: "center" }}>
          {view.series.map((s, i) => (
            <View key={s.key || `s${i}`} style={{ flexDirection: "row", alignItems: "center", gap: 5, flexShrink: 1 }}>
              <View style={{ width: 8, height: 8, borderRadius: 2, backgroundColor: seriesColor(C, view.series, i) }} />
              <T size={12} color={C.muted} numberOfLines={1} ellipsizeMode="tail" style={{ flexShrink: 1 }}>{s.name}</T>
            </View>
          ))}
        </View>
      )}
      <View style={{ flexDirection: "row", height: 150, gap }}>
        {view.daily.map((d) => (
          <Smooth key={d.day} radius={[4, 4, 0, 0]} style={{ flex: 1, backgroundColor: d.day === day?.day ? C.chip : "transparent" }}>
            <Pressable onPress={() => setPicked({ days: view.days, day: d.day })} style={{ flex: 1, justifyContent: "flex-end", alignItems: "center" }}>
              <Bar d={d} view={view} />
            </Pressable>
          </Smooth>
        ))}
      </View>
      <View style={{ height: 1, backgroundColor: C.line }} />
      <View style={{ flexDirection: "row", paddingTop: 6, gap }}>
        {view.daily.map((d, i) => {
          const shown = !many || d.today || (view.daily.length - 1 - i) % 7 === 0;
          return <T key={d.day} size={11} color={d.today ? C.ink : C.subtle} numberOfLines={1} align="center" style={{ flex: 1 }}>{!shown ? "" : d.today ? t("android-misc.usage.today") : d.label}</T>;
        })}
      </View>
      {day != null && (
        <View style={{ paddingTop: 12, gap: 3 }}>
          <T size={13} weight="500" color={C.ink}>{`${day.today ? t("android-misc.usage.today") : day.label} · ${day.costText} · ${day.callsText}`}</T>
          {several && day.cost > 0 && view.series.map((s, i) => ((day.parts[i] ?? 0) > 0 ? (
            <View key={s.key || `s${i}`} style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
              <View style={{ width: 8, height: 8, borderRadius: 2, backgroundColor: seriesColor(C, view.series, i) }} />
              <T size={12} color={C.muted} numberOfLines={1} ellipsizeMode="tail" style={{ flex: 1, minWidth: 0 }}>{s.name}</T>
              <T size={12} color={C.muted}>{day.partsText[i] ?? ""}</T>
            </View>
          ) : null))}
        </View>
      )}
    </>
  );
}

function Bar({ d, view }: { d: UsageDay; view: UsageView }) {
  const C = useC();
  if (view.max <= 0 || d.cost <= 0) return null;
  const share = Math.min(1, Math.max(0, d.cost / view.max));
  // Top first: the column is drawn from the top, the first person at the foot.
  const parts = d.parts.map((p, i) => [i, p] as const).reverse().filter(([, p]) => p > 0);
  return (
    <Smooth radius={[4, 4, 0, 0]} style={{ maxWidth: 28, width: "100%", height: `${share * 100}%`, justifyContent: "flex-end", gap: 2 }}>
      {parts.map(([i, p]) => <View key={i} style={{ alignSelf: "stretch", flex: Math.max(0.001, p / d.cost), backgroundColor: seriesColor(C, view.series, i) }} />)}
    </Smooth>
  );
}

/** The lists, one at a time, the first few until asked for all. */
function Lists({ view, open }: { view: UsageView; open: (item: UsageItem) => void }) {
  const C = useC();
  const [shown, setShown] = useState(0);
  const list: UsageList | undefined = view.lists[shown] ?? view.lists[0];
  // All of a list, asked for: as long as it is that list.
  const [all, setAll] = useState<string | null>(null);
  if (list == null) return null;
  const every = all === list.key;
  const items = every ? list.items : list.items.slice(0, 8);
  return (
    <Card>
      <Seg options={view.lists.map((it) => it.title)} selected={Math.max(0, view.lists.indexOf(list))} onSelect={setShown} fill />
      <View style={{ height: 6 }} />
      {items.map((item, i) => <ItemRow key={item.key} item={item} rank={i + 1} kind={list.key} open={open} />)}
      {list.items.length > 8 && (
        <Smooth radius={10} style={{ alignSelf: "flex-start" }}>
          <Pressable onPress={() => setAll(every ? null : list.key)} android_ripple={ripple(C.ink)} style={{ paddingHorizontal: 4, paddingVertical: 10 }}>
            <T size={14} color={C.muted}>{every ? t("android-misc.usage.collapse") : t("android-misc.usage.showAll", { n: list.items.length })}</T>
          </Pressable>
        </Smooth>
      )}
    </Card>
  );
}

function ItemRow({ item, rank, kind, open }: { item: UsageItem; rank: number; kind: string; open: (item: UsageItem) => void }) {
  const C = useC();
  const opens = kind === "chats" && item.chat != null;
  const person = item.person;
  const share = Math.min(1, Math.max(item.share > 0 ? 0.01 : 0, item.share));
  return (
    <Smooth radius={12} style={{ alignSelf: "stretch" }}>
      <Pressable disabled={!opens} onPress={() => open(item)} android_ripple={opens ? ripple(C.ink) : undefined} style={{ paddingVertical: 10 }}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 12 }}>
          {kind === "people" && person != null ? <Avatar id={person.email ?? person.id} name={person.shown?.name ?? item.title} size={22} picture={person.shown?.picture} />
            : <T size={12} color={C.subtle} align="right" style={{ width: 22 }}>{`${rank}`}</T>}
          <View style={{ flex: 1, minWidth: 0 }}>
            <T size={15} weight="500" color={C.ink} numberOfLines={1} ellipsizeMode="tail">{item.title}</T>
            <T size={12} color={C.muted} numberOfLines={1} ellipsizeMode="tail">{[item.sub, item.detail].filter((x) => x != null).join(" · ")}</T>
          </View>
          <View style={{ alignItems: "flex-end" }}>
            <T size={15} weight="600" color={C.ink}>{item.costText}</T>
            <T size={12} color={C.muted}>{item.shareText}</T>
          </View>
        </View>
        {/* Its share of the whole, under its words. */}
        <View style={{ marginLeft: 34, marginTop: 6, height: 4, borderRadius: 2, overflow: "hidden", backgroundColor: C.chip }}>
          <View style={{ width: `${share * 100}%`, height: "100%", backgroundColor: withAlpha(C.subtle, 0.5) }} />
        </View>
      </Pressable>
    </Smooth>
  );
}

export function UsagePricesScreen({ current, days }: { current: WorkspaceEntry; days: number }) {
  const app = theApp;
  const C = useC();
  const insets = useSafeAreaInsets();
  const topic = rememberTopic<UsageView>(Topics.usage(current.workspace.id, days));
  const view = topic.value;
  const tables = view?.prices ?? [];
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom }}>
      <TopBack label={t("android-misc.usage.title")} onBack={() => app.pop()} />
      <LargeTitle small="" big={t("android-misc.usage.prices")} />
      <PageNote text={t("android-misc.usage.prices.note")} />
      {view == null ? <Waiting shape={WaitShape.Cards} text={t("common.reading")} error={topic.error ? t("android-misc.usage.prices.loadFailed", { error: topic.error.message }) : null} /> : (
        <>
          {/* None yet while the stations are still read (or could not be): waited on, not said to be none. */}
          {tables.length === 0 && (view.wait.reading || view.wait.failing.length > 0) ? <Waiting shape={WaitShape.Cards} count={2} note={view.wait} />
            : tables.length === 0 ? <PageNote text={t("android-misc.usage.prices.none")} /> : null}
          {tables.map((table, n) => (
            <Card key={`${table.station}/${n}`}>
              <T size={16} weight="600" color={C.ink}>{table.station}</T>
              <T size={12} color={C.muted} style={{ paddingTop: 8, paddingBottom: 20 }}>{table.note}</T>
              {table.rows.length === 0 ? <T size={12} color={C.muted}>{t("android-misc.usage.prices.noModels")}</T>
                : <Markdown text={pricesMarkdown(table.rows)} modifier={{ paddingTop: 8 }} fillTables />}
            </Card>
          ))}
        </>
      )}
      <View style={{ height: 30 }} />
    </ScrollView>
  );
}

/** Serialize already-formatted cells for the app's existing Markdown table renderer. */
function pricesMarkdown(rows: NonNullable<UsageView["prices"]>[number]["rows"]): string {
  const cell = (value: string) => {
    let out = "";
    for (const c of value) {
      if (c === "\n" || c === "\r") out += " ";
      else { if ("\\`*_[]<>|".includes(c)) out += "\\"; out += c; }
    }
    return out;
  };
  const line = (cells: string[]) => "| " + cells.map(cell).join(" | ") + " |";
  const header = [t("android-misc.usage.prices.model"), ...rows[0]!.rates.map((it) => it.label)];
  return [line(header), line(header.map(() => "---")), ...rows.map((row) => line([row.model, ...row.rates.map((it) => it.value)]))].join("\n");
}
