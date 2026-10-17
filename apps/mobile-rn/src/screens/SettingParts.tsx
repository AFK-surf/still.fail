// The settings' parts other pages use too: rows that go on, notes under a list, the pickers of a run (model, account,
// effort), a workspace's mark, a decision's options.
import { useState, type ReactNode } from "react";
import { Linking, Pressable, ScrollView, View, type StyleProp, type ViewStyle } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Svg, { Circle } from "react-native-svg";
import { CoreError } from "../../../../web/src/core/client.ts";
import type { DecisionOption, ModelOption, RunnableProfile, WorkspaceMark as WorkspaceMarkView } from "../../../../web/src/core/shapes.ts";
import type { AppState } from "../AppState";
import { Auth } from "../data/Calls";
import { t } from "../i18n";
import { DoingMark, Field, GroupLabel } from "../ui/Controls";
import { Icons } from "../ui/Icon";
import type { IconPaths } from "../ui/IconSet";
import { IconIn, ListRow, MakerIcon, ProviderMark, QuotaRings, ripple } from "../ui/Parts";
import { SMOOTH_SCALE, Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";
import { PresenceDot } from "./Connects";

/** A row that opens a page: its name, how things stand (`bad` in red; `dot`, a red dot before it), a chevron. */
export function GoRow({ title, value, bad = false, dot = false, lead, onClick }: { title: string; value?: string | null; bad?: boolean; dot?: boolean; lead?: (() => ReactNode) | null; onClick: () => void }) {
  const C = useC();
  return (
    <ListRow onClick={onClick}>
      {lead?.()}
      <T size={15} color={C.ink} numberOfLines={1} ellipsizeMode="tail" style={{ flex: 1, minWidth: 0 }}>{title}</T>
      {value != null && (
        <View style={{ maxWidth: 220, flexDirection: "row", alignItems: "center", gap: 6 }}>
          {dot && <PresenceDot state="error" />}
          <T size={14} color={bad ? C.red : C.muted} numberOfLines={1} ellipsizeMode="tail" style={{ flexShrink: 1 }}>{value}</T>
        </View>
      )}
      <IconIn icon={Icons.ChevronRight} size={14} tint={C.subtle} />
    </ListRow>
  );
}

/** A page's note under its title, in a line or two. */
export function PageNote({ text }: { text: string }) {
  const C = useC();
  return <T size={13} color={C.muted} style={{ paddingLeft: 24, paddingRight: 24, paddingBottom: 10 }}>{text}</T>;
}

/** A line that leads to a list: what is chosen, and an arrow. */
export function SettingRow({ onClick, leading, content, children }: { onClick: () => void; leading?: () => ReactNode; content?: () => ReactNode; children?: ReactNode }) {
  const C = useC();
  return (
    <Smooth radius={12} style={{ alignSelf: "stretch", backgroundColor: C.chip }}>
      <Pressable onPress={onClick} android_ripple={ripple(C.ink)} style={{ flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 14, paddingVertical: 12 }}>
        {leading?.()}
        <View style={{ flex: 1, minWidth: 0 }}>{content ? content() : children}</View>
        <IconIn icon={Icons.ChevronRight} size={16} tint={C.muted} />
      </Pressable>
    </Smooth>
  );
}

/** Every model it can move to, by series (the core says); a filter once there are many. */
export function ModelList({ models, runtime, picked, onPick }: { models: ModelOption[]; runtime: string; picked: string | null | undefined; onPick: (model: string) => void }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const [filter, setFilter] = useState("");
  const needle = filter.trim().toLowerCase();
  const shown = models.filter((m) => [m.name, m.model, ...m.ids].some((s) => s.toLowerCase().includes(needle)));
  const on = optionOf(models, picked);
  // By series, in the core's order.
  const groups = new Map<string, ModelOption[]>();
  for (const m of shown) {
    const who = m.family ?? t("android-chat.pick.family.other");
    groups.set(who, [...(groups.get(who) ?? []), m]);
  }
  return (
    <View style={{ flex: 1, alignSelf: "stretch", paddingHorizontal: 18 }}>
      {models.length > 8 && <Field value={filter} onChange={setFilter} placeholder={t("android-chat.run.model.search")} modifier={{ marginTop: 8, marginBottom: 4 }} />}
      <ScrollView style={{ flex: 1 }}>
        {[...groups].map(([who, list]) => (
          <View key={who}>
            {groups.size > 1 && <GroupLabel text={who} />}
            {list.map((m) => <PickLine key={m.model} label={m.name} checked={m === on} onClick={() => onPick(m.model)} leading={() => <MakerIcon maker={m.maker} runtime={runtime} size={18} />} />)}
          </View>
        ))}
        {shown.length === 0 && <T size={14} color={C.muted} style={{ paddingVertical: 16 }}>{t("android-chat.run.model.none")}</T>}
        <View style={{ height: insets.bottom + 16 }} />
      </ScrollView>
    </View>
  );
}

/** Who can run the model picked: the station's pick, or one kept to, with its quota. */
export function AccountList({ accounts, runtime, picked, onPick }: { accounts: RunnableProfile[]; runtime: string; picked: string | null | undefined; onPick: (id: string | null) => void }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  return (
    <ScrollView style={{ flex: 1, alignSelf: "stretch" }} contentContainerStyle={{ paddingHorizontal: 18 }}>
      <T size={12} color={C.muted} style={{ paddingTop: 8, paddingBottom: 4 }}>{t("android-chat.run.account.note")}</T>
      <PickLine label={t("android-chat.run.account.auto")} checked={picked == null} onClick={() => onPick(null)} />
      {accounts.map((p) => (
        <PickLine
          key={p.id}
          label={p.name}
          checked={picked === p.id}
          onClick={() => onPick(p.id)}
          leading={() => <ProviderMark runtime={p.runtime ?? runtime} kind={p.kind} size={18} mark={p.mark} />}
          trailing={() => <QuotaRings quota={p.quota} />}
        />
      ))}
      <View style={{ height: insets.bottom + 16 }} />
    </ScrollView>
  );
}

/** How hard it thinks, as chips as wide as their words, wrapping when they do not fit a line. */
export function EffortChips({ efforts, picked, onPick }: { efforts: (string | null)[]; picked: string | null | undefined; onPick: (effort: string | null) => void }) {
  const C = useC();
  return (
    <View style={{ flexDirection: "row", flexWrap: "wrap", columnGap: 8, rowGap: 8 }}>
      {efforts.map((e, i) => {
        const on = e === (picked ?? null);
        return (
          <Smooth key={e ?? `default-${i}`} radius={18} style={{ backgroundColor: on ? C.ink : C.chip }}>
            <Pressable onPress={() => onPick(e)} android_ripple={ripple(on ? C.bg : C.ink)} style={{ paddingHorizontal: 16, paddingVertical: 9 }}>
              <T size={14} color={on ? C.bg : C.ink} weight={on ? "600" : "400"}>{e ?? t("android-chat.pick.default")}</T>
            </Pressable>
          </Smooth>
        );
      })}
    </View>
  );
}

/**
 * What a workspace has waiting, as the core says (views/marks.ts): `alert` a red dot with a soft halo, `wait` a blue
 * ring (a card or an agent waits on them), `done` a blue dot; as a chat's mark (ChatMark), still. `label` says it in words.
 */
export function WorkspaceMark({ tone, label }: { tone: string; label: string }) {
  // Drawn in its 10dp box, the halo past it (a Canvas draws outside its box).
  const at = 7;
  const c = at + 5;
  const r = 5 - 1;
  const ring = 2;
  return (
    <View style={{ width: 10, height: 10 }} accessible={label.length > 0} accessibilityLabel={label || undefined}>
      <Svg width={24} height={24} style={{ position: "absolute", left: -at, top: -at }}>
        {tone === "alert" && <Circle cx={c} cy={c} r={r + 3} fill={withAlpha(MarkRed, 0.25)} />}
        {tone === "wait"
          ? <Circle cx={c} cy={c} r={4.5 - ring / 2} fill="none" stroke={MarkBlue} strokeWidth={ring} />
          : <Circle cx={c} cy={c} r={r} fill={tone === "alert" ? MarkRed : MarkBlue} />}
      </Svg>
    </View>
  );
}

/**
 * What a workspace has waiting, after its name in the switcher (web: ChatMark.tsx MarkCounts): a red dot and how many
 * of the chats its person takes part in want them, a blue ring and how many wait on them, a blue dot and how many are
 * unread; nothing for none.
 */
export function MarkCounts({ mark }: { mark: WorkspaceMarkView }) {
  const C = useC();
  if (mark.tone == null) return null;
  const counts: [string, number][] = [["alert", mark.alert], ["wait", mark.wait ?? 0], ["done", mark.unread]];
  return (
    <View accessible accessibilityLabel={mark.label ?? ""} style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
      {counts.filter(([, n]) => n > 0).map(([tone, n]) => (
        <View key={tone} style={{ flexDirection: "row", alignItems: "center", gap: 4 }}>
          <WorkspaceMark tone={tone} label="" />
          <T size={12} color={C.muted}>{`${n}`}</T>
        </View>
      ))}
    </View>
  );
}

/**
 * A decision's options (web Decisions.tsx DecisionOptions): one card, full width, a row each — its number in a circle,
 * the label (medium) and its detail under it, small and quiet, a hairline between two. The recommended one (last, as
 * the core orders them) is told by its number in the accent alone (said to a screen reader). `busy`: the label of the one being sent
 * (a spinner on it, none pressed meanwhile).
 */
export function DecisionOptions({ options, modifier: style, enabled = true, busy, onPick }: { options: DecisionOption[]; modifier?: StyleProp<ViewStyle>; enabled?: boolean; busy?: string | null; onPick: (option: DecisionOption) => void }) {
  const C = useC();
  const hairline = withAlpha(C.ink, 0.07);
  // A card of rows to be pressed (web pages.css.ts listCard, docs/ui-panels.md 页面卡片): each row's ground under the
  // finger OPTION_PAD from the card's edge, rounded OPTION_CORNER, the card's corner theirs and that together; its
  // number in its row's corner, concentric with it; its words OPTION_WORDS from the card's edge, as a card of words'.
  return (
    <Smooth radius={OPTION_CORNER + OPTION_PAD / SMOOTH_SCALE} style={[style, { alignSelf: "stretch", backgroundColor: C.chip, padding: OPTION_PAD }]}>
      {options.map((o, i) => {
        const strong = o.recommended === true;
        const said = strong ? t("common.recommended") : undefined;
        const free = enabled && busy == null;
        const ink = strong ? "#FFFFFF" : C.muted;
        const digit = Digits[i];
        return (
          <View key={`${i}-${o.label}`}>
            {i > 0 && <View style={{ marginLeft: NUMBER_IN + NUMBER + 12, marginRight: OPTION_WORDS - OPTION_PAD, height: 1, backgroundColor: hairline }} />}
            <Smooth radius={OPTION_CORNER} style={{ opacity: enabled ? 1 : 0.5 }}>
              <Pressable
                onPress={() => onPick(o)}
                disabled={!free}
                android_ripple={ripple(C.ink)}
                accessibilityValue={said ? { text: said } : undefined}
                style={{ flexDirection: "row", gap: 12, paddingLeft: NUMBER_IN, paddingRight: OPTION_WORDS - OPTION_PAD, paddingTop: NUMBER_IN, paddingBottom: NUMBER_IN }}
              >
                <View style={{ width: NUMBER, height: NUMBER, borderRadius: NUMBER / 2, overflow: "hidden", backgroundColor: strong ? C.accent : withAlpha(C.ink, 0.09), alignItems: "center", justifyContent: "center" }}>
                  {digit ? <IconIn icon={digit} size={NUMBER} tint={ink} /> : <T size={12} line={22} weight="600" color={ink}>{`${i + 1}`}</T>}
                </View>
                <View style={{ flex: 1, minWidth: 0 }}>
                  <T size={15} line={21} weight="500" color={C.ink}>{o.label}</T>
                  {o.detail != null && <T size={13} line={18} color={C.muted}>{o.detail}</T>}
                </View>
                {busy === o.label && <DoingMark running failed={null} inline />}
              </Pressable>
            </Smooth>
          </View>
        );
      })}
    </Smooth>
  );
}

/** The option a model is, however it is spelled (openai/gpt-6-astra is gpt-6-astra). */
export function optionOf(models: ModelOption[], model: string | null | undefined): ModelOption | null {
  if (model == null) return null;
  return models.find((m) => m.model === model) ?? models.find((m) => m.ids.includes(model)) ?? null;
}

/** A choice in a list: what it is, a note under it, and a check when it is the one chosen. */
export function PickLine({ label, sub, checked, onClick, leading, trailing }: { label: string; sub?: string | null; checked: boolean; onClick: () => void; leading?: (() => ReactNode) | null; trailing?: (() => ReactNode) | null }) {
  const C = useC();
  return (
    <Smooth radius={10} style={{ alignSelf: "stretch" }}>
      <Pressable onPress={onClick} android_ripple={ripple(C.ink)} style={{ flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 4, paddingVertical: 11 }}>
        {leading?.()}
        <View style={{ flex: 1, minWidth: 0 }}>
          <T size={15} color={C.ink} numberOfLines={1} ellipsizeMode="tail">{label}</T>
          {sub != null && <T size={12} color={C.muted}>{sub}</T>}
        </View>
        {trailing?.()}
        <View style={{ width: 18, alignItems: "center" }}>{checked && <IconIn icon={Icons.Check} size={16} tint={C.accent} />}</View>
      </Pressable>
    </Smooth>
  );
}

export const MarkBlue = "#3B82F6";

export const MarkRed = "#E5484D";

/** Each option's number, drawn (scripts/option-digits.py: in the middle of its circle at any size); past six, set. */
export const Digits: IconPaths[] = [Icons.Option1, Icons.Option2, Icons.Option3, Icons.Option4, Icons.Option5, Icons.Option6];

export const OPTION_PAD = 8;

export const OPTION_CORNER = 18;

export const OPTION_WORDS = 20;

export const NUMBER = 22;

/** The number in its row's corner: the row's corner less its half (both as round as they are drawn: Smooth's is round 18). */
export const NUMBER_IN = OPTION_CORNER - NUMBER / 2;

/**
 * Starts a Google sign-in through still.fail cloud in the browser; the app finishes it when its auth callback comes
 * back (Auth.REDIRECT). `context`: the Android app's, for its Custom Tab; none is needed here.
 * NATIVE: a Custom Tab (CustomTabsIntent, setShowTitle) as the Android app opens it, which needs expo-web-browser; until
 * it is in, the system's browser opens it.
 */
export async function signIn(app: AppState, context?: unknown): Promise<void> {
  void context;
  try {
    const url = await Auth.begin(app.core);
    await Linking.openURL(url);
  } catch (e) {
    app.toast = t("android-settings.signIn.beginFailed", { error: e instanceof CoreError ? e.message : e instanceof Error ? e.message : String(e) });
  }
}
