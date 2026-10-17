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
    // iOS's corners are a mask, which clips the box's own shadow away: a shadow asked for is cast by a view round it,
    // which takes its place among its neighbours too (its size, where it sits); the box fills it.
    const shadowed = Platform.OS === "ios" ? splitShadow(style, r) : null;
    const box = (
      <NativeSmooth {...rest} radii={r} amount={amount} strokeWidth={stroke?.width ?? 0} strokeColor={stroke?.color} style={shadowed ? shadowed.inner : style}>
        {children}
      </NativeSmooth>
    );
    return shadowed ? <View style={shadowed.outer} pointerEvents="box-none">{box}</View> : box;
  }
  const corners: ViewStyle = { borderTopLeftRadius: r[0] * SMOOTH_SCALE, borderTopRightRadius: r[1] * SMOOTH_SCALE, borderBottomRightRadius: r[2] * SMOOTH_SCALE, borderBottomLeftRadius: r[3] * SMOOTH_SCALE, borderCurve: "continuous", overflow: "hidden" };
  const line: ViewStyle | undefined = stroke ? { borderWidth: stroke.width, borderColor: stroke.color } : undefined;
  return (
    <View {...rest} style={[style, corners, line]}>
      {children}
    </View>
  );
}

/** What of a style goes on the view casting the shadow: the shadow, and how the box sits among its neighbours. */
const OUTER = new Set([
  "shadowColor", "shadowOpacity", "shadowRadius", "shadowOffset", "boxShadow", "elevation",
  "position", "top", "left", "right", "bottom", "start", "end", "inset", "zIndex",
  "margin", "marginTop", "marginBottom", "marginLeft", "marginRight", "marginHorizontal", "marginVertical", "marginStart", "marginEnd",
  "flex", "flexGrow", "flexShrink", "flexBasis", "alignSelf", "width", "height", "minWidth", "maxWidth", "minHeight", "maxHeight",
  "aspectRatio", "transform", "opacity", "display",
]);

function splitShadow(style: StyleProp<ViewStyle>, radii: number[]): { outer: ViewStyle; inner: ViewStyle } | null {
  const flat = StyleSheet.flatten(style) as Record<string, unknown> | undefined;
  if (flat == null || !((typeof flat.shadowOpacity === "number" && flat.shadowOpacity > 0) || (flat.boxShadow != null && flat.boxShadow !== ""))) return null;
  const outer: Record<string, unknown> = {};
  const inner: Record<string, unknown> = { flexGrow: 1 };
  for (const [k, v] of Object.entries(flat)) (OUTER.has(k) ? outer : inner)[k] = v;
  if (outer.width != null) inner.width = "100%";
  if (outer.height != null) inner.height = "100%";
  // With no background of its own, the outer view's shadow is cast from what it holds (the box); a boxShadow is drawn
  // round its bounds, rounded as the box's corners (the continuous corner standing in for the smooth one).
  Object.assign(outer, { borderRadius: Math.max(...radii) * SMOOTH_SCALE, borderCurve: "continuous" });
  return { outer: outer as ViewStyle, inner: inner as ViewStyle };
}

export const smoothStyles = StyleSheet.create({ fill: { flex: 1 } });
