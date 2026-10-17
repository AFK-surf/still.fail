// A place's page (Places.tsx: 文件, Station, Profile, 连接, 用量, 已归档, 奏) as the chats' list is one: with the bottom bar
// under it, Home's frosted top bar over it (settings, the page's name, its other actions), what it shows scrolling under
// that bar, and its primary action in the bar's notch. Pushed (from settings, the list's menu), it is a sub-page as any:
// back to the page under it, its name in the middle, its actions with its "+" at the right. No large title, no note
// under it either way.
import { useContext, useState, type ReactNode } from "react";
import { slot, type Slot } from "../ui/Parts";
import { View, type StyleProp, type TextStyle, type ViewStyle } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { LocalApp, useApp } from "../AppState";
import type { WorkspaceEntry } from "../data/Accounts";
import { t } from "../i18n";
import { LocalPlaceRoot, PlaceAction, PlaceRoot, placeLabel } from "../Places";
import type { BarAction } from "../ui/Bar";
import { TopGlass } from "../ui/Glass";
import { Icons } from "../ui/Icon";
import { NavBar, NavButton } from "../ui/Parts";
import { T } from "../ui/Text";
import { useC } from "../ui/Theme";

/**
 * Home's top bar (and a place's): frosted over what is behind it, a hairline under it; its row of buttons. `haze`: the
 * Android app's frosting source; here the glass blurs what is behind it as it is (Glass.tsx).
 */
export function TopGlassBar({ modifier: modifier_, style = modifier_, children, onLayout }: { haze?: unknown; modifier?: StyleProp<ViewStyle>; style?: StyleProp<ViewStyle>; children?: ReactNode; onLayout?: (height: number) => void }) {
  const insets = useSafeAreaInsets();
  return (
    <TopGlass style={[style, { alignSelf: "stretch" }]}>
      <View
        onLayout={onLayout ? (e) => onLayout(e.nativeEvent.layout.height) : undefined}
        style={{ paddingTop: insets.top + 8, paddingLeft: 16, paddingRight: 16, paddingBottom: 8, flexDirection: "row", alignItems: "center", gap: 10 }}
      >
        {children}
      </View>
    </TopGlass>
  );
}

/** Settings, at the top bar's left (SettingsHome.tsx): the account, the workspace's things, this device's. */
export function SettingsGear() {
  const app = useContext(LocalApp);
  return (
    <View accessible accessibilityLabel={t("android-chat.home.settings")}>
      <NavButton icon={Icons.Settings} onClick={() => app.push({ kind: "Settings" })} iconSize={22} />
    </View>
  );
}

/** The name in the top bar, as Home's workspace name is set. */
export function TopBarTitle({ text, modifier: modifier_, style = modifier_ }: { text: string; modifier?: StyleProp<TextStyle>; style?: StyleProp<TextStyle> }) {
  const C = useC();
  return <T size={24} weight="700" color={C.ink} style={[{ letterSpacing: -0.4 }, style]} numberOfLines={1} ellipsizeMode="tail">{text}</T>;
}

/** A page's "+" in its top bar (pushed, or on a wide screen: no bar to hold it), named as what it adds. */
export function PlusButton({ action }: { action: BarAction }) {
  return (
    <View accessible accessibilityLabel={action.label}>
      <NavButton icon={action.icon} onClick={() => action.run()} iconSize={20} />
    </View>
  );
}

/**
 * What the back of a pushed page says: the page under it, the chats or settings; `orElse` for any other (a station's).
 */
function useUnderLabel(orElse: string): string {
  const stack = useApp((s) => s.stack);
  const under = stack[stack.length - 2];
  if (under?.kind === "Home") return placeLabel("chats");
  if (under?.kind === "Settings") return t("android-settings.title");
  return orElse;
}

/** The top bar's height by place, kept with the page's state (rememberSaveable there): coming back, it is known at once. */
const barHeights = new Map<string, number>();

/**
 * A place's page. `place` is which (its name the title unless `title` says another); `primary` its main action (null:
 * none), in the bar's notch on the bar's page and the top bar's "+" otherwise; `known` false while what decides it is not
 * read (the notch stays as it is meanwhile). `actions`: the page's others, at the top bar's right (用量's days). `back`:
 * what the back of a pushed page says when the page under it is neither the chats nor settings. `content` gets the room
 * to keep at its top: what scrolls starts there, under the frosted bar.
 */
export function PlacePage({ current, place, primary, known = true, title, back, actions, content }: {
  current: WorkspaceEntry;
  place: string;
  primary: BarAction | null;
  known?: boolean;
  title?: string;
  back?: string;
  actions?: Slot | null;
  content: (top: number) => ReactNode;
}) {
  const app = useContext(LocalApp);
  const root = useContext(LocalPlaceRoot);
  const insets = useSafeAreaInsets();
  const name = title ?? placeLabel(place);
  const under = useUnderLabel(back ?? t("android-settings.title"));
  const key = `${current.workspace.id}|${place}`;
  // Its height kept with the page's state (as Home's): coming back, what scrolls is laid out under it at once.
  const [bar, setBar] = useState(() => barHeights.get(key) ?? insets.top + 50);
  const action = <PlaceAction workspace={current.workspace.id} place={place} action={primary} known={known} />;
  if (root === PlaceRoot.Bar) {
    return (
      <View style={{ flex: 1 }}>
        {action}
        <View style={{ flex: 1 }}>{content(bar + 8)}</View>
        <TopGlassBar modifier={{ position: "absolute", left: 0, right: 0, top: 0 }} onLayout={(h) => { barHeights.set(key, h); setBar(h); }}>
          <SettingsGear />
          <TopBarTitle text={name} modifier={{ flex: 1, minWidth: 0 }} />
          {slot(actions)}
        </TopGlassBar>
      </View>
    );
  }
  // Pushed, or the top of a place on a wide screen (no bar there: back goes to the chats).
  const wide = root === PlaceRoot.Wide;
  return (
    <View style={{ flex: 1 }}>
      {action}
      <NavBar
        back={wide ? placeLabel("chats") : under}
        onBack={() => { if (wide) app.place({ kind: "Home" }); else app.pop(); }}
        title={name}
        trailing={actions == null && primary == null ? null : () => (
          <View style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>
            {slot(actions)}
            {primary != null && <PlusButton action={primary} />}
          </View>
        )}
      />
      <View style={{ flex: 1, alignSelf: "stretch" }}>{content(4)}</View>
    </View>
  );
}
