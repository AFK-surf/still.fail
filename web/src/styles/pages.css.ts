import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { iconBtn } from "@stillfail/ui/styles/page.css.ts";

export const page = style({
  flex: "1", minHeight: "0", overflowY: "auto", padding: "40px 40px 80px",
  "@media": {
    "(max-width: 700px)": {
      padding: "24px 18px 60px",
    },
  },
});
export const pageNarrow = style({});
export const pageHead = style({
  display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: "16px", marginBottom: "28px",
});
// Its buttons may reach into the row that drags the desktop window (styles/shell.css.ts main): they are still pressed.
// Only the page's head: anything further down, scrolled up out of sight, would still cut holes in that row.
globalStyle(`[data-desktop] ${pageHead} :is(a, button, input, select, textarea, [role="button"], [tabindex])`, { WebkitAppRegion: "no-drag" });
export const identity = style({ display: "flex", alignItems: "center", gap: "16px", marginBottom: "28px" });
export const identityText = style({ flex: "1", minWidth: "0" });
export const identityName = style({
  display: "flex", alignItems: "center", gap: "4px", margin: "0", fontSize: vars.textHeading, lineHeight: "34px", fontWeight: "600",
});
// Its name's buttons (an edit's pencil) stand back until the name is pointed at.
globalStyle(`${identityName} ${iconBtn}`, { opacity: ".55" });
globalStyle(`${identityName}:hover ${iconBtn}`, { opacity: "1" });
export const identitySub = style({
  display: "flex", flexWrap: "wrap", alignItems: "center", gap: "6px 14px", margin: "6px 0 0", color: vars.muted,
  fontSize: vars.textUi, lineHeight: "20px",
});
/**
 * A grey ground, no line round it, and the app's kind of corner (a little over --r-card: it is large): nothing in it draws a curve near one (its buttons are words:
 * controls.css.ts), so nothing has to follow it.
 */
/** A settings card's ground and corner, for the other cards of the settings pages (a station's, the first station's) too. */
export const cardGround = `color-mix(in oklab, ${vars.text} 4%, ${vars.canvas})`;
export const cardLook = { borderRadius: `calc(22px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: cardGround } as const;
export const card = style({
  ...cardLook, padding: "18px 20px",
  display: "grid", gap: "14px",
  selectors: {
    "& + &": { marginTop: "10px" },
  },
});
export const cardRow = style({ display: "flex", alignItems: "center", gap: "12px" });
export const cardRowText = style({ flex: "1", display: "grid", gap: "2px", minWidth: "0", fontSize: vars.textUi });
export const cardActions = style({ display: "flex", justifyContent: "flex-end", gap: "8px" });
export const list = style({});
export const listRow = style({
  display: "flex", alignItems: "center", gap: "12px", minHeight: "52px", padding: "10px 12px",
  borderRadius: vars.rField, cornerShape: vars.cornerShape, fontSize: vars.textUi,
  transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.list },
  },
});
export const listRowText = style({ flex: "1", display: "grid", gap: "2px", minWidth: "0" });
export const listRowTitle = style({
  flex: "1", minWidth: "0", fontWeight: "500", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
  selectors: {
    [`${listRowText} &`]: { flex: "none" },
  },
});
export const mark = style({
  display: "inline-grid", placeItems: "center", flex: "none", borderRadius: `calc(10px * ${vars.cornerScale})`,
  background: vars.paper, color: vars.text, cornerShape: vars.cornerShape,
});
globalStyle(`${pageHead} h1`, { margin: "0", fontSize: vars.textHeading, lineHeight: "34px", fontWeight: "600" });
