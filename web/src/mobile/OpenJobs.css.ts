import { style } from "@vanilla-extract/css";

const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;

export const mOpenJobs = style({ display: "flex", flexDirection: "column", gap: "8px", padding: "4px 10px 10px" });
export const mOpenGroup = style({ display: "flex", flexDirection: "column", gap: "2px" });
export const mOpenHead = style({ padding: "2px 10px", fontSize: "12px", color: "var(--m-muted)" });
/** Its buttons inherit (./styles/root.css.ts): their colour and size are the row's. */
export const mOpenMore = style({
  alignSelf: "flex-start", padding: "3px 10px", border: "0", borderRadius: "8px", background: "none", fontSize: "12px !important",
  color: "var(--m-muted) !important", cursor: "pointer",
});
export const mOpenRow = style({
  display: "flex", alignItems: "center", gap: "10px", padding: "5px 4px 5px 10px", borderRadius: "10px",
  selectors: { "&[data-link]": { cursor: "pointer" }, "&[data-link]:active": { background: "var(--m-chip)" } },
});
/** The dot, in the column the rows' icons take. */
export const mOpenMark = style({ width: "16px", flex: "none", display: "grid", placeItems: "center" });
export const mOpenText = style({ flex: "1", minWidth: "0", display: "flex", flexDirection: "column" });
export const mOpenName = style({ ...ellipsis, fontSize: "14px", lineHeight: "18px", color: "var(--m-ink)" });
export const mOpenWhere = style({ ...ellipsis, fontSize: "12px", lineHeight: "16px", color: "var(--m-muted)" });
export const mOpenStop = style({
  display: "grid", placeItems: "center", flex: "none", width: "32px", height: "32px", padding: "0", border: "0",
  borderRadius: "50%", background: "none", color: "var(--m-muted) !important", cursor: "pointer",
  selectors: { "&:disabled": { cursor: "default" } },
});
