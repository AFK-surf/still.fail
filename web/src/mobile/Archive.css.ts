import { style } from "@vanilla-extract/css";

/** What the archive is: no hover to explain it on a phone, so said at the top. */
export const mArchiveAbout = style({ margin: "0", padding: "4px 16px", fontSize: "13px", color: "var(--m-muted)" });
export const mArchiveNote = style({
  margin: "0", padding: "12px 20px", fontSize: "14px", color: "var(--m-muted)",
  selectors: { "&[data-error]": { padding: "8px 20px", fontSize: "13px", color: "var(--m-red)" } },
});
/** A row: its title with when (and where) at the end of its line, then what can be done; its last message under it. */
export const mArchiveRow = style({ display: "flex", flexDirection: "column", padding: "6px 10px 6px 20px" });
export const mArchiveHead = style({ display: "flex", alignItems: "center", gap: "10px", height: "34px" });
export const mArchiveTitle = style({
  flex: "1", minWidth: "0", fontSize: "16px", lineHeight: "22px", color: "var(--m-ink)", overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const mArchiveWhen = style({ display: "flex", gap: "8px", flex: "none", fontSize: "12px", color: "var(--m-subtle)", whiteSpace: "nowrap" });
// Its buttons take their colour from here (the phone's buttons inherit theirs, ./styles/root.css.ts).
export const mArchiveActions = style({ display: "flex", flex: "none", color: "var(--m-muted)" });
export const mArchiveAction = style({
  display: "grid", placeItems: "center", width: "34px", height: "34px", padding: "0", border: "0", borderRadius: "50%",
  background: "none", cursor: "pointer",
  selectors: { "&:active": { background: "var(--m-chip)" } },
});
export const mArchiveLast = style({
  paddingRight: "10px", fontSize: "14px", lineHeight: "20px", color: "var(--m-muted)", overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap", minHeight: "20px",
});
