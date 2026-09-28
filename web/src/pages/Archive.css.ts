import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

export const archiveStation = style({
  selectors: {
    // The archive: one row a chat, what it is on the left and what can be done on the right; no lines between.
    "& + &": { marginTop: "24px" },
  },
});
export const archiveList = style({ display: "grid", gap: "2px" });
export const archiveRow = style({
  display: "flex", alignItems: "center", gap: "12px", padding: "8px 10px", borderRadius: vars.rNav,
  cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover },
  },
});
export const archiveText = style({ display: "grid", gap: "2px", minWidth: "0", flex: "1" });
export const archiveTitle = style({
  fontSize: vars.textSm, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const archiveMeta = style({
  fontSize: vars.textXs, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const archiveActions = style({ display: "flex", gap: "4px", flex: "none" });
