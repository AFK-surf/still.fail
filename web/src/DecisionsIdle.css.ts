import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { busyRing } from "./styles/busyRing.ts";
import { spinKeyframes } from "./styles/keyframes.css.ts";

/** None left: the day, then where the next may come from and what was answered, in a column. */
export const idle = style({
  position: "absolute", inset: 0, overflowY: "auto", display: "flex", flexDirection: "column", padding: "32px 24px",
});
export const column = style({ width: "100%", maxWidth: 560, margin: "auto", display: "flex", flexDirection: "column", gap: 28 });
export const head = style({ display: "flex", flexDirection: "column", alignItems: "center", gap: 6, textAlign: "center" });
export const title = style({ margin: "6px 0 0", fontSize: vars.textTitle, fontWeight: 600, lineHeight: "22px" });
export const note = style({ margin: 0, fontSize: vars.textUi, color: vars.muted, lineHeight: "20px" });

/** The day in numbers: each a figure over its words. */
export const stats = style({ display: "flex", justifyContent: "center", gap: 32, marginTop: 10 });
export const stat = style({ display: "flex", flexDirection: "column", alignItems: "center", gap: 2 });
export const figure = style({ fontSize: vars.textHeading, lineHeight: "26px", fontWeight: 600, fontVariantNumeric: "tabular-nums" });
export const figureWords = style({ fontSize: vars.textMeta, lineHeight: "16px", color: vars.subtle });

export const section = style({ display: "flex", flexDirection: "column", gap: 2 });
export const sectionTitle = style({ margin: "0 0 4px 10px", fontSize: vars.textMeta, lineHeight: "18px", fontWeight: 500, color: vars.subtle });

/** One chat or card: its mark, its words over where it is, when at its end; opens its chat. */
export const row = style({
  display: "flex", alignItems: "flex-start", gap: 10, width: "100%", padding: "8px 10px", border: 0, borderRadius: vars.rNav,
  cornerShape: vars.cornerShape, background: "none", color: vars.text, fontFamily: "inherit", textAlign: "left", cursor: "pointer",
  transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: { "&:hover": { background: vars.hover } },
});
/** At work: the yellow ring the chats' marks turn. */
export const busy = style({
  flex: "none", width: 12, height: 12, marginTop: 4, background: `${busyRing(12)} center / 100% no-repeat`,
  animation: `${spinKeyframes} 1.2s linear infinite`,
  "@media": { "(prefers-reduced-motion: reduce)": { animation: "none" } },
});
/** Answered: a quiet dot. */
export const done = style({ flex: "none", width: 6, height: 6, margin: "7px 3px 0", borderRadius: "50%", background: vars.subtle });
export const words = style({ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: 1 });
export const main = style({ fontSize: vars.textUi, lineHeight: "20px", fontWeight: 500, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const meta = style({ fontSize: vars.textMeta, lineHeight: "18px", color: vars.subtle, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const answer = style({ color: vars.text });
export const when = style({ flex: "none", fontSize: vars.textMeta, lineHeight: "20px", color: vars.subtle, fontVariantNumeric: "tabular-nums" });
