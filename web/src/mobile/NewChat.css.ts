import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

export const mNewchatScreen = style({ paddingBottom: "var(--m-bottom)", boxSizing: "border-box" });
/**
 * The scene runs on under what stands at its foot (the choices, then the composer, on a band of glass frosting it), down
 * to the screen's end; its own end kept clear of them (`--m-new-foot`: the band's height, NewChat.tsx).
 */
export const mNewBody = style({
  flex: "1", minHeight: "0", overflowY: "auto", display: "flex", flexDirection: "column", alignItems: "center",
  gap: "6px", padding: "30px 30px calc(10px + var(--m-new-foot, var(--m-bottom)))", marginBottom: "calc(-1 * var(--m-bottom))",
  textAlign: "center",
});
/**
 * A band of glass from a little above the choices to the screen's end (the composer on it too), with no line: over its
 * top 32px it comes in (masked), from none to all of it; what runs under it is frosted all over.
 */
export const mNewFoot = style({
  position: "absolute", left: "0", right: "0", bottom: "0", paddingTop: "32px", paddingBottom: "var(--m-bottom)",
  display: "flex", flexDirection: "column", isolation: "isolate",
  "::before": {
    content: '""', position: "absolute", inset: "0", zIndex: "-1",
    background: "color-mix(in srgb, var(--m-bg) 70%, transparent)", WebkitBackdropFilter: "blur(24px)", backdropFilter: "blur(24px)",
    maskImage: "linear-gradient(to bottom, transparent, black 32px)", WebkitMaskImage: "linear-gradient(to bottom, transparent, black 32px)",
  },
});
export const mNewProblem = style({
  marginTop: "6px !important", fontSize: `${vars.textMeta} !important`, color: "var(--m-red)",
  selectors: {
    "&[data-wait]": { color: "var(--m-muted)" },
  },
});
export const mNewSpent = style({
  margin: "0 12px", padding: "8px 12px", borderRadius: "12px",
  background: "color-mix(in srgb, var(--m-warn) 12%, var(--m-bg))", fontSize: vars.textMeta,
});
export const mNewBottom = style({
  display: "flex", flexDirection: "column", gap: "4px", flex: "none", padding: "8px 10px 0",
});
export const mChoosers = style({
  display: "flex", gap: "6px", overflowX: "auto", padding: "6px 2px", scrollbarWidth: "none",
  selectors: {
    "&::-webkit-scrollbar": { display: "none" },
  },
});
export const mChooser = style({
  display: "inline-flex", alignItems: "center", gap: "6px", flex: "none", height: "30px", boxSizing: "border-box",
  padding: "0 11px", borderRadius: "15px", fontSize: `${vars.textMeta} !important`, whiteSpace: "nowrap", cursor: "pointer",
});
globalStyle(`${mNewBody} h2`, { margin: "6px 0 0", fontSize: vars.textHeading, fontWeight: "600" });
globalStyle(`${mNewBody} > p`, { fontSize: vars.textUi });

