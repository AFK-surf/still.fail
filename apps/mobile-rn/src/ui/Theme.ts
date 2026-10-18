// The mobile concept's look (ui/Theme.kt): warm paper, ink, and one still.fail orange that means "this needs you".
// The palette in use comes from the prefs' appearance (system, light, dark), as the Android app picks it.
import { createContext, createElement, useContext, type ReactNode } from "react";
import { PixelRatio, useColorScheme } from "react-native";
import { usePrefs } from "../../../../web/src/prefs.ts";

export interface StillFailColors {
  dark: boolean;
  bg: string; surface: string; surface2: string;
  ink: string; muted: string; subtle: string; line: string;
  /** The web's --line-strong: a field's frame, a quote's bar, a spinner's track. */
  lineStrong: string;
  accent: string; accentBg: string; accentInk: string;
  green: string; red: string; warn: string;
  /** Unread: news, not "this needs you". */
  blue: string;
  chip: string; bubble: string;
}

export const Light: StillFailColors = {
  dark: false,
  bg: "#F5F3EF", surface: "#FFFFFF", surface2: "#FBFAF7",
  ink: "#24272B", muted: "#7A7D83", subtle: "#A6A8AC", line: "#E7E3DC", lineStrong: "#C1C4C9",
  accent: "#E5704A", accentBg: "#FBE6DC", accentInk: "#B9471F",
  green: "#2F8F5B", red: "#C9412E", warn: "#D9962B", blue: "#1559C4",
  chip: "#EFECE6", bubble: "#E8E4DC",
};

export const Dark: StillFailColors = {
  dark: true,
  bg: "#1B1C1F", surface: "#26272B", surface2: "#2C2D31",
  ink: "#ECECED", muted: "#9A9DA3", subtle: "#6E7177", line: "#34353A", lineStrong: "#3D3F44",
  accent: "#EF7A55", accentBg: "#4A2F25", accentInk: "#F6A383",
  green: "#5CC08A", red: "#EB6B58", warn: "#D9962B", blue: "#81AEFA",
  chip: "#313237", bubble: "#313237",
};

/** A palette set for what is under it (StillFailTheme), over the one the prefs pick. */
const Forced = createContext<StillFailColors | null>(null);

/** ui/Theme.kt StillFailTheme: what is in it drawn in the dark or the light palette, whatever the prefs say. */
export function StillFailTheme({ dark, children }: { dark: boolean; children?: ReactNode }) {
  return createElement(Forced.Provider, { value: dark ? Dark : Light }, children);
}

/** The palette in use (C in the Android app). */
export function useC(): StillFailColors {
  const forced = useContext(Forced);
  const system = useColorScheme();
  const appearance = usePrefs((p) => p.appearance);
  const dark = appearance === "dark" || (appearance !== "light" && system === "dark");
  return forced ?? (dark ? Dark : Light);
}

/** Raised (ui/Glass.kt): what floats over the page, white in light and a step up in dark. */
export const raised = (c: StillFailColors) => (c.dark ? "#2A2C31" : "#FFFFFF");

/**
 * A Compose dp as Compose lays it out: whole pixels (Dp.roundToPx, half up), each padding, size and gap on its own.
 * Yoga keeps the fractions and rounds only where things land, so at 2.625 a 12dp padding is 31.5 px here and 32 in
 * Kotlin: a page of rows drifted a pixel a row (its sections 8–10 px higher by its middle), a meter's ten 7dp cells
 * and their gaps came out 6 px wider. Given the shared parts' numbers, they land on Kotlin's pixels.
 */
export function dp(n: number): number {
  const k = PixelRatio.get();
  return Math.round(n * k) / k;
}

/** The code face: JetBrains Mono, carried in the app (assets/fonts), not the system's monospace. */
export const CODE_FONT = "JetBrainsMono";
/** ui/Theme.kt Mono. */
export const Mono = { fontFamily: CODE_FONT, fontSize: 12, lineHeight: 18 } as const;

/** A colour's hex with `alpha` (0..1), as Compose's Color.copy(alpha). */
export function withAlpha(hex: string, alpha: number): string {
  const a = Math.round(Math.min(1, Math.max(0, alpha)) * 255).toString(16).padStart(2, "0");
  return `${hex.slice(0, 7)}${a}`;
}

/** Compose's lerp of two colours (hex #RRGGBB), `t` of the way from `a` to `b`. */
export function lerpColor(a: string, b: string, t: number): string {
  const p = (h: string, i: number) => parseInt(h.slice(1 + i * 2, 3 + i * 2), 16);
  const m = (i: number) => Math.round(p(a, i) + (p(b, i) - p(a, i)) * t).toString(16).padStart(2, "0");
  return `#${m(0)}${m(1)}${m(2)}`;
}
