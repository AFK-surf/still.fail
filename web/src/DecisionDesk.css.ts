import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

export const emptyList = style({ padding: "20px 10px", fontSize: vars.textXs, lineHeight: "20px", color: vars.subtle });

/** 奏 and how many, over the list. */
export const title = style({
  display: "flex", alignItems: "center", gap: 8, padding: "6px 8px 2px 18px", minHeight: 40, fontSize: vars.textBody, lineHeight: "20px",
});
export const filter = style({ marginLeft: "auto" });
export const titleWord = style({ fontWeight: 600 });
export const titleCount = style({ fontSize: vars.textXs, color: vars.subtle, fontVariantNumeric: "tabular-nums" });

/** 待定: the ones set aside, under the rest. */
export const group = style({ padding: "14px 10px 4px", fontSize: vars.textXs, lineHeight: "18px", color: vars.subtle });

/** One decision in the list: its question, then its chat, station and when; picked, it is the one shown. */
export const row = style({
  display: "grid", gap: 2, width: "100%", padding: "8px 10px", border: 0, borderRadius: vars.rNav,
  cornerShape: vars.cornerShape, background: "none", color: vars.text, fontFamily: "inherit", textAlign: "left",
  cursor: "pointer", transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.hover },
    "&[aria-current=\"true\"]": { background: vars.selected },
    "&[data-aside]": { opacity: 0.55 },
  },
});
export const question = style({
  fontSize: vars.textSm, lineHeight: "20px", fontWeight: 500, display: "-webkit-box", WebkitLineClamp: 2,
  WebkitBoxOrient: "vertical", overflow: "hidden", overflowWrap: "anywhere",
});
export const meta = style({
  display: "flex", gap: 6, minWidth: 0, fontSize: vars.textXs, lineHeight: "18px", color: vars.subtle,
  whiteSpace: "nowrap",
});
export const metaWhere = style({ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis" });
export const metaTime = style({ marginLeft: "auto", flex: "none", fontVariantNumeric: "tabular-nums" });

/** The page: its bar, then the decision picked. */
export const page = style({ display: "flex", flexDirection: "column", flex: 1, minHeight: 0 });
/** The bar: its chat (opening it) on the left, 待定 and 不再提醒 on the right. */
export const barLead = style({ display: "flex", alignItems: "center", gap: 6, minWidth: 0, gridColumn: "1 / 3", fontSize: vars.textSm });
export const barChat = style({
  minWidth: 0, padding: "2px 6px", border: 0, borderRadius: 6, background: "none", color: vars.text, fontFamily: "inherit",
  fontSize: vars.textSm, fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover } },
});
export const barStation = style({ flex: "none", color: vars.subtle, fontSize: vars.textXs });
export const barActions = style({ display: "flex", justifyContent: "flex-end", gap: 2 });
export const barButton = style({
  height: 28, padding: "0 10px", border: 0, borderRadius: 8, background: "none", color: vars.muted, fontFamily: "inherit",
  fontSize: vars.textXs, cursor: "pointer",
  selectors: { "&:hover:not(:disabled)": { background: vars.hover, color: vars.text }, "&:disabled": { opacity: 0.4, cursor: "default" } },
});
