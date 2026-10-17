// Frosted glass (ui/Glass.kt, Haze there): the top bar is the page's paper at 70% over a CSS blur(24px), a hairline
// along its bottom; what floats at the bottom is `--raised` at 72% over a blur(20px) with a breath of shadow. Here
// expo-blur's Android blur (BlurView, Dimezis') frosts what is behind; Android 11 and earlier get the tint alone.
import { BlurView } from "expo-blur";
import type { ReactNode } from "react";
import { Platform, StyleSheet, View, type StyleProp, type ViewStyle } from "react-native";
import { Quiet } from "./Quiet";
import { concentric, Smooth } from "./Smooth";
import { raised, useC, withAlpha } from "./Theme";

/**
 * expo-blur takes an intensity it divides by blurReductionFactor into the blur's radius: a CSS blur's px as radius. Its
 * intensity also lays a white of its own over the blur (44% of the intensity, as a share of 100): kept at 1, so the
 * only tint is ours (the glass's 72% or 70%), as the Kotlin's Haze has it.
 */
const blur = (px: number) => ({ intensity: 1, blurReductionFactor: 1 / px }) as const;

interface GlassProps { tint: string; alpha: number; px: number; style?: StyleProp<ViewStyle>; children?: ReactNode }

/** The frost itself: what is behind blurred `px`, under `tint` at `alpha`. */
export function Frost({ tint, alpha, px, style, children }: GlassProps) {
  return (
    <View style={style}>
      {/* Quiet: the blur draws anew each frame what moves behind it, and Android tells accessibility of each (Quiet.tsx). */}
      <Quiet style={StyleSheet.absoluteFill}>
        {Platform.OS === "android" && Platform.Version >= 31 ? (
          <BlurView experimentalBlurMethod="dimezisBlurView" {...blur(px)} tint="default" style={StyleSheet.absoluteFill} />
        ) : (
          <BlurView {...blur(px)} tint="default" style={StyleSheet.absoluteFill} />
        )}
      </Quiet>
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
