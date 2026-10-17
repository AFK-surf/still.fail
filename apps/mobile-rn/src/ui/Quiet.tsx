// A box whose insides move without the accessibility services hearing of it (modules/stillfail-ui QuietView): a
// view turned, scaled or faded each frame is told on Android to every accessibility client as a change in the window,
// so it is never idle (UI Automator waits for idle, TalkBack hears a flood); Compose draws such motion in its draw
// phase, telling nobody. Round what turns or breathes for ever (a spinner, a pulse), only where what it says does not
// change. Layout only in its style: it is a plain box, not one that clips or rounds.
import { requireNativeView } from "expo";
import type { ReactNode } from "react";
import { Platform, View, type StyleProp, type ViewProps, type ViewStyle } from "react-native";

const NativeQuiet = Platform.OS === "android" ? requireNativeView<ViewProps>("StillfailQuiet") : null;

export function Quiet({ style, children, ...rest }: ViewProps & { style?: StyleProp<ViewStyle>; children?: ReactNode }) {
  if (NativeQuiet == null) return <View style={style} {...rest}>{children}</View>;
  return <NativeQuiet style={style} {...rest}>{children}</NativeQuiet>;
}
