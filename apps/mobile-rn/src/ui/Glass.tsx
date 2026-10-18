// Frosted glass (ui/Glass.kt, Haze there): the top bar is the page's paper at 70% over a CSS blur(24px), a hairline
// along its bottom; what floats at the bottom is `--raised` at 72% over a blur(20px) with a breath of shadow. On Android
// a Backdrop is what the frosts over it blur, on the GPU, as Haze's source is (modules/stillfail-ui FrostView.kt);
// Android 11 and earlier get the tint alone. On iOS the system's blur sees what is behind it by itself. On iOS
// 26 the bottom bar is the system's own Liquid Glass (expo-glass-effect's GlassView, UIGlassEffect; Bar.tsx). A GlassView
// on a page (in App.tsx's pages) draws nothing there, even made anew once its page is at rest and laid out: the
// capsules on pages are frosted as on Android.
import { BlurView } from "expo-blur";
import { isLiquidGlassAvailable } from "expo-glass-effect";
import { requireNativeView } from "expo";
import { createContext, useContext, useId, type ReactNode } from "react";
import { Platform, StyleSheet, View, type StyleProp, type ViewProps, type ViewStyle } from "react-native";
import { Quiet } from "./Quiet";
import { concentric, Smooth } from "./Smooth";
import { raised, useC, withAlpha } from "./Theme";

/**
 * expo-blur's on iOS (UIVisualEffectView) has no radius: its intensity is how far its material's blur goes in, about
 * 30 pt at 100, so 4 a px.
 */
const blur = (px: number) => ({ intensity: Math.min(100, px * 4) }) as const;

/** iOS 26's Liquid Glass there (not on earlier iOS, nor on Android). */
export const LIQUID = Platform.OS === "ios" && isLiquidGlassAvailable();

/**
 * Which backdrop the frosts here blur (Haze's HazeState: Kotlin passes one from what it frosts to the glass over it):
 * a Backdrop's name. With none (or before Android 12, as Haze), a frost is its tint alone.
 */
export const LocalFrostSource = createContext<string | null>(null);

const NativeBackdrop = Platform.OS === "android" ? requireNativeView<{ name: string } & ViewProps>("StillfailBackdrop") : null;
const NativeFrost = Platform.OS === "android" ? requireNativeView<{ source: string | null; blurRadius: number; base: string } & ViewProps>("StillfailFrost") : null;

/** A name for a backdrop and the frosts over it, this component's own. */
export function useFrostName(what: string): string {
  return `${what}${useId()}`;
}

/**
 * What frosts blur (Haze's hazeSource): what it holds, drawn once more by each frost naming it, blurred on the GPU
 * (modules/stillfail-ui FrostView.kt). A frost inside its own backdrop draws its paper alone. On iOS a plain view (the
 * system's blur sees what is behind it by itself).
 */
export function Backdrop({ name, style, children, ...rest }: { name: string; style?: StyleProp<ViewStyle>; children?: ReactNode } & ViewProps) {
  if (NativeBackdrop) return <NativeBackdrop {...rest} name={name} style={style}>{children}</NativeBackdrop>;
  return <View {...rest} style={style}>{children}</View>;
}

/**
 * The blur radius that is CSS `blur(<px>)` (Glass.kt cssBlur): CSS gives the Gaussian's deviation, RenderEffect takes a
 * radius it turns into a deviation of 0.57735 × radius + 0.5.
 */
const cssBlur = (px: number) => (px - 0.5) / 0.57735;

interface GlassProps { tint: string; alpha: number; px: number; style?: StyleProp<ViewStyle>; children?: ReactNode }

/**
 * The blur alone, filling what holds it: on Android what the backdrop named here (LocalFrostSource) draws, blurred `px`
 * over the page's paper; on iOS the system's blur of what is behind.
 */
export function FrostLayer({ px }: { px: number }) {
  const C = useC();
  const source = useContext(LocalFrostSource);
  if (NativeFrost) {
    // The page's paper under the blur (Haze's backgroundColor): where the backdrop draws nothing, not what is under.
    return source != null && (Platform.Version as number) >= 31
      ? <NativeFrost source={source} blurRadius={cssBlur(px)} base={C.bg} style={StyleSheet.absoluteFill} pointerEvents="none" />
      : null;
  }
  // Quiet: the blur draws anew each frame what moves behind it, and accessibility would hear of each (Quiet.tsx).
  return (
    <Quiet style={StyleSheet.absoluteFill}>
      <BlurView {...blur(px)} tint="default" style={StyleSheet.absoluteFill} />
    </Quiet>
  );
}

/** The frost itself: what is behind blurred `px`, under `tint` at `alpha`. */
export function Frost({ tint, alpha, px, style, children }: GlassProps) {
  return (
    <View style={style}>
      <FrostLayer px={px} />
      <View style={[StyleSheet.absoluteFill, { backgroundColor: withAlpha(tint, alpha) }]} />
      {children}
    </View>
  );
}

/** ui/Glass.kt glass: a bar at the top of the page, over the list: frosted, a hairline along its bottom. */
export function TopGlass({ style, children }: { style?: StyleProp<ViewStyle>; children?: ReactNode }) {
  const C = useC();
  return (
    <Frost tint={C.bg} alpha={0.7} px={24} style={style}>
      {children}
      <View style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 0.5, backgroundColor: C.line }} />
    </Frost>
  );
}

/** ui/Glass.kt glassFoot: the same glass as a band along the page's foot, with no line. */
export function FootGlass({ style, children }: { style?: StyleProp<ViewStyle>; children?: ReactNode }) {
  const C = useC();
  return <Frost tint={C.bg} alpha={0.7} px={24} style={style}>{children}</Frost>;
}

/**
 * ui/Glass.kt floating: a capsule floating over the list, raised and frosted (`--raised` at 72% over a 20px blur, no
 * line round it, only a breath of shadow); `tint` for glass of another colour. `radius`: its Smooth corner.
 */
export function Floating({ radius, tint, style, children }: { radius: number; tint?: string; style?: StyleProp<ViewStyle>; children?: ReactNode }) {
  const C = useC();
  return (
    <Smooth radius={radius} style={[{ elevation: 1, shadowColor: "#000", shadowOpacity: 0.3, shadowRadius: 1, shadowOffset: { width: 0, height: 0.5 } }, style]}>
      <Frost tint={tint ?? raised(C)} alpha={0.72} px={20} style={StyleSheet.absoluteFill} />
      {children}
    </Smooth>
  );
}

/** The composer's capsule (ui/Glass.kt): its corner and the room inside it; what sits in it takes the corner concentric with it. */
export const ComposerCorner = 26;
export const ComposerInset = 8;
export const InComposer = concentric(ComposerCorner, ComposerInset);
/** The files in it: as far from its edge as from its top, and rounded as its corner less that. */
export const ComposerFilesIn = 10;
export const InComposerFiles = concentric(ComposerCorner, ComposerFilesIn);
/** The CSS blur of a floating capsule's glass (ui/Glass.kt GlassBlur, cssBlur(20)). */
export const GlassBlur = 20;
