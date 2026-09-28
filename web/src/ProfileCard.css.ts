import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { phrase } from "./styles/base.css.ts";
import { runtimeTags } from "./styles/waiting.css.ts";
import { btn } from "./styles/controls.css.ts";

/**
 * A profile or an account (ProfileCard.tsx), laid out by its own width: in one line when wide; name and state over what
 * it is when there is less, its quota on a line below; its action on a line of its own when narrow.
 */
export const profileCard = style({
  containerType: "inline-size", display: "block", padding: "10px 12px", borderRadius: vars.rField,
  cornerShape: vars.cornerShape, fontSize: vars.textSm, color: "inherit", textDecoration: "none",
  selectors: {
    // Standing alone (not a row of a list): its text lines up with what is around it.
    "&[data-framed]": { margin: "0 -12px" },
  },
});
export const profileCardLink = style({
  transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.list },
  },
});
export const profileCardWhy = style({ display: "inline-flex", cursor: "help", borderRadius: "999px" });
export const profileCardGrid = style({
  display: "flex", flexWrap: "wrap", alignItems: "center", columnGap: "12px", rowGap: "8px",
});
export const profileCardMark = style({ width: "24px", height: "24px", background: "none" });
export const profileCardMain = style({ flex: "1", minWidth: "0", display: "grid", gap: "2px" });
export const profileCardTitle = style({
  display: "flex", alignItems: "center", gap: "6px", minWidth: "0", fontWeight: "500", overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** What it is wraps rather than cutting off (an account's long address would hide its plan). */
export const profileCardSub = style({ color: vars.muted, fontSize: vars.textXs, overflowWrap: "anywhere" });
export const profileCardEmail = style({
  display: "block", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const profileCardState = style({ flex: "none", display: "flex", alignItems: "center" });
export const profileCardAction = style({
  flex: "none", display: "flex", alignItems: "center", order: "11", flexBasis: "100%",
  "@container": {
    "(min-width: 420px)": {
      order: "0", flexBasis: "auto",
    },
  },
});
export const profileCardChevron = style({ color: vars.muted });
/** Its quota beside its state, however narrow (a ring or two is small); narrow, its action across the whole width. */
export const profileCardQuota = style({ flex: "none", display: "flex" });
globalStyle(`${profileCardTitle} ${runtimeTags}`, { marginLeft: "0" });
/** An address is cut short rather than wrapped: which account it is shows well enough from its start. */
globalStyle(`${profileCardSub} ${phrase}:has(> ${profileCardEmail})`, { display: "block", minWidth: "0" });
globalStyle(`${profileCardAction} > ${btn}`, { width: "100%" });
globalStyle(`${profileCardAction}:has(> ${profileCardChevron})`, { order: "0", flexBasis: "auto" });
globalStyle(`${profileCardAction} > ${btn}`, {
  "@container": {
    "(min-width: 420px)": {
      width: "auto",
    },
  },
});
