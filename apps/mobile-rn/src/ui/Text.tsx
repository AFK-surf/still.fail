// Text as the Android app sets it (ui/Theme.kt WebType: line height 1.4 × the size, no letter spacing), in the
// palette's ink unless told: `<T size={15} weight="600" color={C.muted}>`.
import type { ReactNode } from "react";
import { PixelRatio, Platform, StyleSheet, Text, type StyleProp, type TextProps, type TextStyle } from "react-native";
import { useC } from "./Theme";

export interface TProps extends TextProps {
  /** sp, as the Kotlin's fontSize (Material's body is 16). */
  size?: number;
  weight?: TextStyle["fontWeight"];
  color?: string;
  /** Line height in sp; 1.4 × the size unless given. */
  line?: number;
  align?: TextStyle["textAlign"];
  mono?: boolean;
  style?: StyleProp<TextStyle>;
  children?: ReactNode;
}

/**
 * The font size to give React Native for Compose's `size.sp`. Compose sets the paint to the size's exact pixels (14sp at
 * 2.625: 36.75 px), which the platform's hinted glyphs are drawn at the whole pixels under (36: 15 Chinese characters
 * 540 px wide); React Native rounds a size up to whole pixels (TextAttributeProps: ceil, 37: 552 px), so its words ran
 * 2–4% wider than Kotlin's and wrapped or were cut short earlier. This is the size whose rounding up is the whole
 * pixels Compose's are drawn at. Only the size: line heights are given as they are (both round those up).
 */
export function sp(size: number): number {
  if (Platform.OS !== "android") return size;
  const k = PixelRatio.getFontScale() * PixelRatio.get();
  return (Math.floor(size * k + 0.001) - 0.01) / k;
}

/** Words the system draws in its CJK face (Noto Sans CJK), not the Latin one: Han, kana, hangul, CJK and full-width punctuation. */
const CJK = /[\u2E80-\u9FFF\uAC00-\uD7AF\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFFEF]/;

/**
 * The room Compose gives these words over their lines, top and bottom (dp each), or null. Compose lays text out with the
 * fallback fonts' line spacing (StaticLayout's useLineSpacingFromFallbacks): with Chinese in it, the first line reaches
 * up to the CJK face's ascent and the last down to its descent (1.448 em in all, at the whole pixels the size is drawn
 * at) however small the line height asked, while the lines between stay the line height apart; React Native holds every
 * line to the line height. A 32sp title in Chinese is 122 px there, not 118; a 16sp line of 21 (55 px) is 61, two of
 * them 116. The difference, half above and half below, is that room.
 */
export function cjkRoom(size: number, line: number, words: ReactNode): { top: number; bottom: number } | null {
  if (Platform.OS !== "android" || !CJK.test(plainOf(words))) return null;
  const k = PixelRatio.getFontScale() * PixelRatio.get();
  const extra = Math.round(Math.floor(size * k + 0.001) * 1.448) - Math.ceil(line * k - 0.001);
  if (extra <= 0) return null;
  const top = Math.ceil(extra / 2);
  return { top: top / k, bottom: (extra - top) / k };
}

/** `style` with `room` added to its vertical padding (what it has of its own kept). */
export function withRoom(style: StyleProp<TextStyle>, room: { top: number; bottom: number } | null): StyleProp<TextStyle> {
  if (room == null) return style;
  const f = StyleSheet.flatten(style) ?? {};
  const num = (...v: unknown[]) => { for (const x of v) if (typeof x === "number") return x; return 0; };
  return [style, { paddingTop: num(f.paddingTop, f.paddingVertical, f.padding) + room.top, paddingBottom: num(f.paddingBottom, f.paddingVertical, f.padding) + room.bottom }];
}

function plainOf(words: ReactNode): string {
  if (typeof words === "string") return words;
  if (typeof words === "number") return "";
  if (Array.isArray(words)) return words.map((w) => (typeof w === "string" ? w : "")).join("");
  return "";
}

export function T({ size = 16, weight, color, line, align, mono, style, children, ...rest }: TProps) {
  const C = useC();
  const lineHeight = line ?? size * 1.4;
  return (
    <Text
      {...rest}
      style={withRoom([{ fontSize: sp(size), lineHeight, color: color ?? C.ink, fontWeight: weight, textAlign: align, letterSpacing: 0, includeFontPadding: false }, mono && { fontFamily: "JetBrainsMono" }, style], cjkRoom(size, lineHeight, children))}
    >
      {children}
    </Text>
  );
}
