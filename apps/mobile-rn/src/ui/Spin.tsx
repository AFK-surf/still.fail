// A box that turns for ever while `spinning`, once each `period` ms: a spinner's ring. Turned natively (modules/stillfail-ui
// SpinView: an animator on Android, Core Animation on iOS), not by Reanimated, whose rotation is a prop laid again over
// every React commit (a list of turning marks scrolled kept its JS thread busy). What it holds is hidden from
// accessibility, as in a Quiet (Quiet.tsx): say what it is on something round it.
import { requireNativeView } from "expo";
import type { ReactNode } from "react";
import type { StyleProp, ViewProps, ViewStyle } from "react-native";

const NativeSpin = requireNativeView<{ spinning: boolean; period: number } & ViewProps>("StillfailSpin");

export function Spin({ spinning, period = 1200, style, children }: { spinning: boolean; period?: number; style?: StyleProp<ViewStyle>; children?: ReactNode }) {
  return <NativeSpin spinning={spinning} period={period} style={style}>{children}</NativeSpin>;
}
