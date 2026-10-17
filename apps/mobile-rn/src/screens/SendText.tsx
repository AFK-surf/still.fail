// The field, flying words and own messages share their typography and line breaks (screens/SendText.kt).
import { createContext } from "react";
import type { TextStyle } from "react-native";

/** The field, flying words and own messages share their typography and line breaks. */
export const SendTextStyle = {
  fontWeight: "400",
  fontSize: 16,
  lineHeight: 21,
  letterSpacing: 0,
  includeFontPadding: false,
  // LineBreak.Simple, Hyphens.None: lines broken where they fit, never hyphenated.
  textBreakStrategy: "simple",
} as const satisfies TextStyle & { textBreakStrategy: "simple" };

/** Actual field width in px (dp here), excluding the buttons and padding; updated on resize too. */
export const LocalSendTextWidth = createContext(0);
