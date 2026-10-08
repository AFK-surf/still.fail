// What wants the viewer, in the sidebar's foot (Attention.tsx): its row, as light as the rows by it, and the list it
// opens, as wide as the sidebar.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

export const entry = style({ width: "100%", border: "0", background: "none", textAlign: "left", font: "inherit", cursor: "pointer", selectors: { '&[data-state="open"]': { background: vars.hover } } });
export const name = style({ flex: "1", color: vars.text });
/** How many came since the viewer looked: a small red count, as the Dock's. */
export const count = style({
  minWidth: "16px", height: "16px", padding: "0 4px", borderRadius: "8px", background: vars.red, color: vars.onPrimary,
  fontSize: vars.textCaption, fontWeight: "600", lineHeight: "16px", textAlign: "center", fontVariantNumeric: "tabular-nums",
});
/** Only ones looked at: how many, quiet. */
export const quiet = style({ color: vars.muted, fontSize: vars.textMeta, fontVariantNumeric: "tabular-nums" });

export const panel = style({
  width: "var(--radix-popover-trigger-width)", minWidth: "240px", maxWidth: "calc(100vw - 16px)", maxHeight: "min(480px, 70vh)",
  overflowY: "auto", display: "flex", flexDirection: "column", gap: "2px",
});
export const group = style({ display: "flex", flexDirection: "column", gap: "1px", selectors: { "& + &": { marginTop: "6px" } } });
export const groupName = style({ padding: "4px 8px 2px", fontSize: vars.textMeta, color: vars.muted });
export const item = style({
  display: "flex", alignItems: "center", gap: "8px", width: "100%", padding: "6px 8px", borderRadius: vars.rOption,
  color: vars.text, cursor: "pointer", outline: "none", cornerShape: vars.cornerShape,
  selectors: { "&:hover, &:focus-visible": { background: vars.hover } },
});
export const dot = style({
  width: "7px", height: "7px", borderRadius: "50%", flex: "none", background: vars.amber,
  selectors: { '&[data-kind="alert"]': { background: vars.red } },
});
globalStyle(`${item}[data-seen] ${dot}`, { background: "none", boxShadow: `inset 0 0 0 1.5px ${vars.muted}` });
export const itemText = style({ flex: "1", minWidth: "0", display: "flex", flexDirection: "column" });
export const itemTitle = style({ fontSize: vars.textUi, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${item}:not([data-seen]) ${itemTitle}`, { fontWeight: "500" });
globalStyle(`${item}[data-seen] ${itemTitle}`, { color: vars.muted });
export const itemLine = style({ fontSize: vars.textMeta, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** 忽略: small words, only on the row pointed at (or focused). */
export const dismiss = style({
  flex: "none", padding: "1px 4px", border: "0", borderRadius: vars.rOption, background: "none", color: vars.muted,
  font: "inherit", fontSize: vars.textMeta, cursor: "pointer", visibility: "hidden",
  selectors: { "&:hover": { color: vars.text, background: vars.hover } },
});
globalStyle(`${item}:hover ${dismiss}, ${item}:focus-within ${dismiss}`, { visibility: "visible" });
export const foot = style({ display: "flex", gap: "12px", padding: "8px 8px 4px", marginTop: "4px", borderTop: `1px solid ${vars.line}`, fontSize: vars.textMeta });
export const link = style({ color: vars.muted, textDecoration: "none", selectors: { "&:hover": { color: vars.text } } });
export const empty = style({ padding: "10px 8px", fontSize: vars.textUi, color: vars.muted });
