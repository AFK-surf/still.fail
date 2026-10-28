import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const mNote = style({ padding: "0 24px 10px", fontSize: vars.textMeta, color: "var(--m-muted)", lineHeight: "1.5" });
/** A bar's head: its name, 当前 on the one in view, what can be done to it at its end. */
export const mHead = style({ display: "flex", alignItems: "center", gap: "8px", padding: "14px 24px 8px", fontSize: vars.textMeta });
export const mNow = style({
  padding: "1px 7px", borderRadius: "999px", fontSize: vars.textCaption, fontWeight: "600", color: "var(--m-accent)", background: "var(--m-accent-bg)",
});
export const mAct = style({
  padding: "0", border: "0", background: "none", color: "var(--m-accent)", fontSize: vars.textMeta, cursor: "pointer",
  selectors: { "&[data-danger]": { color: "var(--m-red)" } },
});
/** A bar's four slots, a card. */
export const mCard = style({
  display: "grid", gridTemplateColumns: "repeat(4, 1fr)", margin: "0 12px 10px", padding: "8px 4px",
  borderRadius: `calc(20px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: "var(--m-surface)",
});
export const mSlot = style({
  position: "relative", display: "flex", flexDirection: "column", alignItems: "center", gap: "6px", padding: "12px 0 10px",
  border: "0", background: "none", color: "var(--m-ink)", borderRadius: "16px", touchAction: "none", userSelect: "none",
  userSelect: "none", transition: "transform 200ms var(--m-ease)", cursor: "grab",
  selectors: {
    "&[data-lifted]": { transition: "none", zIndex: 2, background: "var(--m-surface)", boxShadow: "0 6px 18px rgb(0 0 0 / .14)", cursor: "grabbing" },
    "&[data-empty]": { color: "var(--m-subtle)", cursor: "pointer" },
  },
});
globalStyle(`${mSlot} small`, { fontSize: vars.textCaption, color: "var(--m-muted)" });
export const mIcon = style({ display: "grid", placeItems: "center", height: "30px" });
export const mAdd = style({ display: "grid", placeItems: "center", width: "30px", height: "30px", borderRadius: "50%", border: "1.5px dashed var(--m-line)" });
/** A place's −, at its icon's top right. */
export const mMinus = style({
  position: "absolute", top: "4px", left: "calc(50% + 10px)", width: "20px", height: "20px", borderRadius: "50%", border: "0", padding: "0",
  display: "grid", placeItems: "center", background: "var(--m-chip)", color: "var(--m-muted)", cursor: "pointer",
});
export const mNewIcon = style({ display: "grid", placeItems: "center", color: "var(--m-accent)" });
export const mNewText = style({ color: "var(--m-accent)" });
export const mPickIcon = style({ display: "grid", placeItems: "center", width: "28px", color: "var(--m-ink)" });

// The phone's buttons take their page's colour (root.css.ts): these their own, as strong and after it.
globalStyle(`${mHead} button${mAct}`, { color: "var(--m-accent)" });
globalStyle(`${mHead} button${mAct}[data-danger]`, { color: "var(--m-red)" });
globalStyle(`${mCard} button${mSlot}[data-empty]`, { color: "var(--m-subtle)" });
globalStyle(`${mCard} button${mMinus}`, { color: "var(--m-muted)" });
