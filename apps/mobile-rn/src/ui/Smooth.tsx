// A box with still.fail's corners (ui/Corners.kt `Smooth`): a superellipse(1.5) corner over a radius a quarter longer
// than the one given, circles and capsules untouched. What it holds is clipped to it (its background too), its
// shadow follows it, and `stroke` draws its line along it. On Android a native view draws it (modules/stillfail-ui);
// on iOS the system's continuous corner, its own superellipse, stands in.
import { requireNativeView } from "expo";
import type { ReactNode } from "react";
import { Platform, StyleSheet, View, type StyleProp, type ViewProps, type ViewStyle } from "react-native";

/** How much longer the smooth corner's radius is (Corners.kt SMOOTH_SCALE). */
export const SMOOTH_SCALE = 1.25;

/** The corner of a smooth box `inset` inside one of corner `outer`, concentric with it (Corners.kt concentric). */
export const concentric = (outer: number, inset: number) => outer - inset / SMOOTH_SCALE;

/** The superellipse's exponent (Corners.kt SMOOTH_EXPONENT, CSS superellipse(1.5)). */
const SMOOTH_EXPONENT = 2.8284271;

/**
 * How far in from each of its edges a Smooth corner of `radius` (room enough to be wholly smooth) passes at its middle,
 * where it turns 45° (Corners.kt smoothMiddle).
 */
export const smoothMiddle = (radius: number) => radius * SMOOTH_SCALE * (1 - Math.pow(2, -1 / SMOOTH_EXPONENT));

type Radii = number | [topLeft: number, topRight: number, bottomRight: number, bottomLeft: number];

interface NativeProps extends ViewProps { radii: number[]; amount: number; strokeWidth: number; strokeColor?: string }
const NativeSmooth = Platform.OS === "android" || Platform.OS === "ios" ? requireNativeView<NativeProps>("StillfailUi") : null;

export interface SmoothProps extends ViewProps {
  radius: Radii;
  /** How smooth, 0 the plain round corner and 1 Smooth's own (a box on its way between the two). */
  amount?: number;
  stroke?: { width: number; color: string };
  style?: StyleProp<ViewStyle>;
  children?: ReactNode;
}

export function Smooth({ radius, amount = 1, stroke, style, children, ...rest }: SmoothProps) {
  const r = typeof radius === "number" ? [radius, radius, radius, radius] : radius;
  if (NativeSmooth) {
    return (
      <NativeSmooth {...rest} radii={r} amount={amount} strokeWidth={stroke?.width ?? 0} strokeColor={stroke?.color} style={style}>
        {children}
      </NativeSmooth>
    );
  }
  const corners: ViewStyle = { borderTopLeftRadius: r[0] * SMOOTH_SCALE, borderTopRightRadius: r[1] * SMOOTH_SCALE, borderBottomRightRadius: r[2] * SMOOTH_SCALE, borderBottomLeftRadius: r[3] * SMOOTH_SCALE, borderCurve: "continuous", overflow: "hidden" };
  const line: ViewStyle | undefined = stroke ? { borderWidth: stroke.width, borderColor: stroke.color } : undefined;
  return (
    <View {...rest} style={[style, corners, line]}>
      {children}
    </View>
  );
}

export const smoothStyles = StyleSheet.create({ fill: { flex: 1 } });
