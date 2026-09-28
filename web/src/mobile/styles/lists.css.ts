import { style } from "@vanilla-extract/css";

export const mCard = style({
  display: "block", boxSizing: "border-box", width: "calc(100% - 24px)", margin: "0 12px 10px", padding: "14px 16px",
  border: "0", borderRadius: "20px", background: "var(--m-surface)", color: "var(--m-ink)", textAlign: "left",
  selectors: {
    "button&": { cursor: "pointer" },
  },
});
export const mRowText = style({ display: "flex", flexDirection: "column" });
export const mRowTitle = style({ fontSize: "15px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const mRowNote = style({
  display: "block", fontSize: "13px", color: "var(--m-muted)", overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap",
});
export const mGroupLabel = style({ padding: "14px 0 4px", fontSize: "13px", color: "var(--m-muted)" });
export const mInfoRow = style({
  display: "flex", alignItems: "center", gap: "12px", boxSizing: "border-box", width: "100%", padding: "10px 12px",
  border: "0", background: "none", color: "var(--m-ink)", textAlign: "left", fontSize: "14px",
  selectors: {
    "button&": { cursor: "pointer" },
  },
});
export const mField = style({
  boxSizing: "border-box", width: "100%", padding: "10px 12px", border: "1px solid var(--m-line)",
  borderRadius: "12px", background: "var(--m-surface)", color: "var(--m-ink)", font: "inherit", fontSize: "16px",
  outline: "none",
  selectors: {
    "&::placeholder": { color: "var(--m-subtle)" },
    "&[data-mono]": { fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace" },
  },
});
