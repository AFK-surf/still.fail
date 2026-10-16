import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const mMemoryNote = style({ margin: "0", padding: "0 24px 8px", fontSize: vars.textMeta, color: "var(--m-muted)" });
export const mMemoryTitle = style({ display: "flex", alignItems: "baseline", gap: "8px", minWidth: "0" });
export const mMemoryTag = style({ flex: "none", fontSize: vars.textCaption, color: "var(--m-subtle)" });
export const mMemoryDoc = style({ fontSize: vars.textUi });
globalStyle(`${mMemoryDoc} > :first-child`, { marginTop: "0" });
globalStyle(`${mMemoryDoc} > :last-child`, { marginBottom: "0" });
/** When a skill is read, at the top of its page. */
export const mMemoryWhen = style({ fontSize: vars.textMeta, color: "var(--m-muted)" });
globalStyle(`${mMemoryWhen} b`, { display: "block", marginBottom: "2px", fontSize: vars.textCaption, fontWeight: "500", color: "var(--m-subtle)" });
export const mMemoryShare = style({ marginTop: "12px" });
/** The pages to pick between: a row of pills, scrolled across when they do not fit, in the cards' column. */
export const mMemoryChips = style({
  display: "flex", gap: "6px", overflowX: "auto", padding: "0 12px 10px", scrollbarWidth: "none",
  selectors: { "&::-webkit-scrollbar": { display: "none" } },
});
export const mMemoryChip = style({
  display: "inline-flex", alignItems: "center", gap: "5px", flex: "none", height: "32px", padding: "0 14px", border: "0",
  borderRadius: "999px", background: "var(--m-chip)", color: "var(--m-ink)", font: "inherit", fontSize: `${vars.textMeta} !important`, cursor: "pointer",
  selectors: {
    "&[data-on]": { background: "var(--m-ink)", color: "var(--m-bg) !important", fontWeight: "600" },
  },
});
globalStyle(`${mMemoryChip} span`, { fontWeight: "400", opacity: "0.6" });
