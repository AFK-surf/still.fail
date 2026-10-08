import { keyframes, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

// The placeholders breathe while waited on (Android screens/Loading.kt the same: 1 → 0.5 and back, 1.4s).
const breathe = keyframes({ "0%, 100%": { opacity: 1 }, "50%": { opacity: 0.5 } });

export const mPillRow = style({ display: "flex", justifyContent: "center", padding: "14px 20px 4px" });
export const mPill = style({
  display: "inline-flex", alignItems: "center", gap: "8px", maxWidth: "100%", boxSizing: "border-box",
  padding: "6px 12px", borderRadius: "16px", background: "var(--m-chip)", color: "var(--m-muted)",
  fontSize: vars.textMeta, lineHeight: "18px", textAlign: "center",
  selectors: { "&[data-error]": { color: "var(--m-red)" } },
});
export const mPlaceholders = style({
  animation: `${breathe} 1.4s ease-in-out infinite`,
  selectors: { "&[data-still]": { animation: "none", opacity: 0.6 } },
  "@media": { "(prefers-reduced-motion: reduce)": { animation: "none" } },
});
const bar = { display: "block", background: "var(--m-bubble)", borderRadius: "7px" } as const;
export const mPlaceRow = style({ display: "flex", alignItems: "center", height: "66px", padding: "0 16px 0 22px", boxSizing: "border-box" });
export const mPlaceLines = style({ flex: "1", display: "grid", gap: "10px", justifyItems: "start" });
export const mPlaceTitle = style({ ...bar, height: "13px" });
export const mPlaceLine = style({ ...bar, height: "10px" });
export const mPlacePicture = style({ ...bar, width: "22px", height: "22px", borderRadius: "50%", flex: "none" });
export const mPlaceMessages = style({ display: "grid", gap: "14px", paddingTop: "8px" });
export const mPlaceMessage = style({ display: "flex", gap: "10px", padding: "0 16px", selectors: { "&[data-mine]": { justifyContent: "flex-end" } } });
export const mPlaceBubble = style({ ...bar, borderRadius: "18px" });
export const mPlaceFace = style({ ...bar, width: "28px", height: "28px", borderRadius: "50%", flex: "none" });
