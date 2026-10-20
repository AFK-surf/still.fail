// What another app shares, its sheet on a narrow screen (ShareIn.tsx): its words on the rows' line (a row's 12 in and
// 8 of its own, then a 36 mark and 12).
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { mSheetLabel } from "./Workspaces.css.ts";

/** What is shared, at the top: a mark of what it is (a link, some text), then its title over it. */
export const mShareWhat = style({ display: "flex", alignItems: "flex-start", gap: "12px", flex: "none", padding: "2px 20px 10px" });
/** A mark as wide as the rows' (a model's tile), the icon in its middle. */
export const mShareLead = style({ display: "grid", placeItems: "center", flex: "none", width: "36px", height: "36px", color: "var(--m-muted)" });
export const mShareIcon = mShareLead;
export const mShareText = style({ flex: "1", minWidth: "0", display: "flex", flexDirection: "column", gap: "2px", paddingTop: "1px" });
globalStyle(`${mShareText} b`, {
  fontSize: vars.textBody, fontWeight: "600", lineHeight: "22px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
// The link or the text: two lines of it (three when it is all there is), cut short.
globalStyle(`${mShareText} small`, {
  fontSize: vars.textCaption, lineHeight: "17px", color: "var(--m-muted)", overflowWrap: "anywhere",
  display: "-webkit-box", WebkitBoxOrient: "vertical", WebkitLineClamp: "2", overflow: "hidden",
});
globalStyle(`${mShareText} small[data-alone]`, { fontSize: vars.textUi, lineHeight: "20px", color: "var(--m-ink)", WebkitLineClamp: "3", paddingTop: "7px" });

/** 发到, and at its end 搜索 (取消 while searching): words to tap, in the label's own ink and size. */
export const mShareLabel = style([mSheetLabel, { display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: "12px" }]);
export const mShareSearch = style({ flex: "none", padding: "0", border: "0", background: "none", cursor: "pointer" });
/** 找 chat: on the rows' line, under 发到. */
export const mShareFind = style({ padding: "6px 20px 4px" });

/** The chats: each its title over one line (the last thing said, or why it is first), cut short. */
export const mShareList = style({});
globalStyle(`${mShareList} small`, { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
