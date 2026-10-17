// 设置 · 下方栏: this device's bottom bars (Places.tsx, ui/Bar.tsx), each a card of its places (up to four), as the
// prototype has it (barSettings): a place taken out with the "−" at its corner, one added from a sheet of all of them,
// a place held and moved sideways to change its order; a bar made the one in view, deleted, or a new one made.
import { useState } from "react";
import { Pressable, ScrollView, View } from "react-native";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, { runOnJS, useAnimatedStyle, useSharedValue } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { app as theApp, SheetSpec, useApp, type AppState } from "../AppState";
import { t } from "../i18n";
import { BAR_SIZE, PlaceIcon, placeLabel, PLACES } from "../Places";
import { PickRow } from "../ui/Controls";
import { Icons } from "../ui/Icon";
import { IconIn, LargeTitle, ListCard, ListRow, ripple } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { Smooth } from "../ui/Smooth";
import type { GlyphCounts } from "../ui/StationGlyph";
import { T } from "../ui/Text";
import { useC } from "../ui/Theme";
import { PageNote } from "./SettingParts";
import { TopBack } from "./Stations";

/** What the settings' row says of the bars: how many, or the one bar's places. */
export function barsValue(app: AppState): string {
  const sets = app.bars.sets;
  return sets.length > 1 ? t("android-misc.bar.count", { n: sets.length }) : sets[0]!.map(placeLabel).join(t("android-misc.bar.sep"));
}

/**
 * The bars kept whole: an empty one dropped (the core keeps none), the one in view still the same bar after it (or,
 * when it is the one dropped, the next).
 */
function save(app: AppState, sets: string[][], current: number) {
  let c = current;
  const kept: string[][] = [];
  sets.forEach((s, i) => { if (s.length === 0) { if (i < current) c--; } else kept.push(s); });
  app.setBars(kept, c);
}

export function BarSettingsScreen() {
  const app = theApp;
  const C = useC();
  const insets = useSafeAreaInsets();
  // The prefs followed: the bars are drawn again as they change.
  useApp((s) => s.kept);
  const bars = app.bars;
  const cur = bars.current;
  // A bar just made, empty until a place is added to it (the core keeps no empty bar): on this page only.
  const [adding, setAdding] = useState(false);
  const sets = [...bars.sets, ...(adding ? [[] as string[]] : [])];
  const pickFor = (i: number) => openPick(app, i, (place) => {
    if (i >= app.bars.sets.length) { setAdding(false); save(app, [...app.bars.sets, [place]], cur); }
    else save(app, app.bars.sets.map((s, n) => (n === i && !s.includes(place) && s.length < BAR_SIZE ? [...s, place] : s)), app.bars.current);
  });
  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: insets.bottom }}>
      <TopBack label={t("android-settings.title")} onBack={() => app.pop()} />
      <LargeTitle small={t("android-misc.bar.small")} big={t("android-misc.bar.title")} />
      <PageNote text={t("android-misc.bar.note")} />
      {sets.map((set, i) => {
        const made = i < bars.sets.length;
        return (
          <View key={i}>
            <View style={{ flexDirection: "row", paddingLeft: 24, paddingRight: 24, paddingTop: 16, paddingBottom: 6, alignItems: "center" }}>
              <T size={13} weight="600" color={C.ink}>{t("android-misc.bar.set", { n: i + 1 })}</T>
              {made && i === cur && (
                <View style={{ marginLeft: 8, borderRadius: 999, overflow: "hidden", backgroundColor: C.accentBg, paddingHorizontal: 7, paddingVertical: 1 }}>
                  <T size={11} weight="600" color={C.accent}>{t("android-misc.bar.current")}</T>
                </View>
              )}
              <View style={{ flex: 1 }} />
              {made && i !== cur && (
                <Smooth radius={6}>
                  <Pressable onPress={() => save(app, bars.sets, i)} android_ripple={ripple(C.ink)} style={{ padding: 4 }}>
                    <T size={13} color={C.accent}>{t("android-misc.bar.use")}</T>
                  </Pressable>
                </Smooth>
              )}
              {sets.length > 1 && (
                <Smooth radius={6} style={{ marginLeft: 10 }}>
                  <Pressable
                    accessibilityLabel={t("android-misc.bar.deleteNamed", { n: i + 1 })}
                    onPress={() => {
                      if (!made) { setAdding(false); return; }
                      const left = bars.sets.filter((_, n) => n !== i);
                      save(app, left, cur > i || cur >= left.length ? Math.max(0, cur - 1) : cur);
                    }}
                    android_ripple={ripple(C.ink)}
                    style={{ padding: 4 }}
                  >
                    <T size={13} color={C.red}>{t("android-misc.bar.delete")}</T>
                  </Pressable>
                </Smooth>
              )}
            </View>
            <BarCard app={app} i={i} set={set} only={bars.sets.length === 1 && set.length === 1} onAdd={() => pickFor(i)} onMove={(from, to) => {
              if (from === to) return;
              const moved = [...set];
              moved.splice(to, 0, moved.splice(from, 1)[0]!);
              save(app, bars.sets.map((s, n) => (n === i ? moved : s)), cur);
            }} />
          </View>
        );
      })}
      <ListCard modifier={{ paddingTop: 14 }}>
        <ListRow onClick={() => { setAdding(true); pickFor(bars.sets.length); }}>
          <IconIn icon={Icons.Plus} size={20} tint={C.accent} />
          <T size={15} color={C.accent} style={{ flex: 1, minWidth: 0 }}>{t("android-misc.bar.new")}</T>
        </ListRow>
      </ListCard>
      <PageNote text={bars.sets.length > 1 ? t("android-misc.bar.foot.many") : t("android-misc.bar.foot.one")} />
      <View style={{ height: 30 }} />
    </ScrollView>
  );
}

/**
 * A bar's card: its places in four slots, each its icon over its name with a "−" at its corner (none on the last
 * place of the only bar: a bar is never empty), and, with room left, a slot that adds one. A place held and moved
 * sideways goes where it is let go (by how many slots it moved).
 */
function BarCard({ app, i, set, only, onAdd, onMove }: { app: AppState; i: number; set: string[]; only: boolean; onAdd: () => void; onMove: (from: number, to: number) => void }) {
  const C = useC();
  const [width, setWidth] = useState(0);
  const slot = width / BAR_SIZE;
  return (
    <View style={{ paddingHorizontal: 12, paddingBottom: 10, alignSelf: "stretch" }}>
      <Smooth radius={20} style={{ backgroundColor: C.surface, paddingHorizontal: 4, paddingVertical: 8, overflow: "visible" }}>
        <View style={{ flexDirection: "row" }} onLayout={(e) => setWidth(e.nativeEvent.layout.width)}>
          {set.map((key, j) => <Slot key={key} app={app} i={i} j={j} keyName={key} count={set.length} slot={slot} only={only} onMove={onMove} />)}
          {set.length < BAR_SIZE && (
            <Smooth radius={16} style={{ width: slot }} testID={`bar-add-${i}`}>
              <Pressable onPress={onAdd} android_ripple={ripple(C.ink)} style={{ paddingTop: 12, paddingBottom: 10, alignItems: "center" }}>
                <View style={{ alignItems: "center", gap: 6 }}>
                  <View style={{ width: 30, height: 30, alignItems: "center", justifyContent: "center", overflow: "visible" }}>
                    <View style={{ width: 44, height: 44, borderRadius: 22, borderWidth: 1.5, borderColor: C.line, alignItems: "center", justifyContent: "center" }}>
                      <IconIn icon={Icons.Plus} size={22} tint={C.subtle} />
                    </View>
                  </View>
                  <T size={12} color={C.subtle} numberOfLines={1}>{t("android-misc.bar.add")}</T>
                </View>
              </Pressable>
            </Smooth>
          )}
        </View>
      </Smooth>
    </View>
  );
}

/** A place in its slot: held and moved sideways, lifted (a little larger, on a card of its own) until let go. */
function Slot({ app, i, j, keyName, count, slot, only, onMove }: { app: AppState; i: number; j: number; keyName: string; count: number; slot: number; only: boolean; onMove: (from: number, to: number) => void }) {
  const C = useC();
  const dx = useSharedValue(0);
  const [lifted, setLifted] = useState(false);
  const end = (moved: number) => {
    const to = Math.min(count - 1, Math.max(0, j + Math.round(moved / slot)));
    setLifted(false);
    onMove(j, to);
  };
  const drag = Gesture.Pan()
    .activeOffsetX([-10, 10])
    .failOffsetY([-10, 10])
    .onStart(() => { dx.value = 0; runOnJS(setLifted)(true); })
    .onUpdate((e) => { dx.value = e.translationX; })
    .onEnd(() => { const moved = dx.value; dx.value = 0; runOnJS(end)(moved); })
    .onFinalize((_, success) => { if (!success) { dx.value = 0; runOnJS(setLifted)(false); } });
  const moving = useAnimatedStyle(() => ({ transform: [{ translateX: dx.value }, { scale: lifted ? 1.08 : 1 }] }));
  return (
    <GestureDetector gesture={drag}>
      <Animated.View
        testID={`bar-slot-${i}-${keyName}`}
        accessibilityLabel={placeLabel(keyName)}
        accessibilityActions={[
          ...(j > 0 ? [{ name: "left", label: t("android-misc.bar.moveLeft") }] : []),
          ...(j < count - 1 ? [{ name: "right", label: t("android-misc.bar.moveRight") }] : []),
        ]}
        onAccessibilityAction={(e) => { if (e.nativeEvent.actionName === "left") onMove(j, j - 1); else if (e.nativeEvent.actionName === "right") onMove(j, j + 1); }}
        style={[
          { width: slot, zIndex: lifted ? 2 : 0, paddingTop: 12, paddingBottom: 10, alignItems: "center" },
          lifted && { borderRadius: 16 * 1.25, borderCurve: "continuous", backgroundColor: C.surface, elevation: 6, shadowColor: "#000000", shadowOpacity: 0.14, shadowRadius: 6, shadowOffset: { width: 0, height: 2 } },
          moving,
        ]}
      >
        <View style={{ alignItems: "center", gap: 6 }}>
          <View style={{ height: 30, alignItems: "center", justifyContent: "center" }}><PlaceIcon place={keyName} tint={C.ink} glyph={Still} /></View>
          <T size={12} color={C.muted} numberOfLines={1}>{placeLabel(keyName)}</T>
        </View>
        {!only && (
          // A touch target only as big as what is drawn (the "−" at a place's corner, over the place).
          <Pressable
            testID={`bar-remove-${i}-${keyName}`}
            accessibilityLabel={t("android-misc.bar.remove", { name: placeLabel(keyName) })}
            onPress={() => save(app, app.bars.sets.map((s, n) => (n === i ? s.filter((it) => it !== keyName) : s)), app.bars.current)}
            android_ripple={ripple(C.ink)}
            hitSlop={0}
            style={{ position: "absolute", top: 12 - 8, left: slot / 2 - 10 + 16, width: 20, height: 20, borderRadius: 10, overflow: "hidden", backgroundColor: C.chip, alignItems: "center", justifyContent: "center" }}
          >
            <IconIn icon={Icons.Minus} size={12} tint={C.muted} />
          </Pressable>
        )}
      </Animated.View>
    </GestureDetector>
  );
}

/** The places to add to bar `i` (its number as said): all of them, those in it already greyed ("已在这一栏"), none when it is full. */
function openPick(app: AppState, i: number, picked: (place: string) => void) {
  // Rows with a line under them ("已在这一栏") are taller: room for every row as one, scrolled if the screen is short.
  app.sheet = new SheetSpec(0.6, false, 90 + PLACES.length * 66, null, false, () => <PickSheet app={app} i={i} picked={picked} />);
}

function PickSheet({ app, i, picked }: { app: AppState; i: number; picked: (place: string) => void }) {
  const C = useC();
  useApp((s) => s.kept);
  const set = app.bars.sets[i] ?? [];
  const full = set.length >= BAR_SIZE;
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-misc.bar.pick.title", { n: i + 1 })} trailing={() => (
        <T size={13} color={C.muted}>{full ? t("android-misc.bar.pick.full") : t("android-misc.bar.pick.left", { n: BAR_SIZE - set.length })}</T>
      )} lead={null} />
      <ScrollView style={{ flexGrow: 0, flexShrink: 1 }}>
        {PLACES.map((key) => {
          const there = set.includes(key);
          return (
            <PickRow
              key={key}
              label={placeLabel(key)}
              sub={there ? t("android-misc.bar.pick.there") : null}
              enabled={!there && !full}
              leading={() => <View style={{ width: 28, height: 28, alignItems: "center", justifyContent: "center", opacity: there || full ? 0.4 : 1 }}><PlaceIcon place={key} tint={C.ink} glyph={Still} /></View>}
              onClick={() => { app.sheet = null; picked(key); }}
            />
          );
        })}
      </ScrollView>
    </>
  );
}

/** The stations' icon where no station is meant (the settings' cards, the picker): one station on, as the web's. */
const Still: GlyphCounts = { online: 1, dim: 0, failing: 0, working: 0, asleep: false };
