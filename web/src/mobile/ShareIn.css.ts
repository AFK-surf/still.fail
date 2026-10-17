// What another app shares, its sheet on a narrow screen (ShareIn.tsx): its words on the rows' line (a row's 12 in and
// 8 of its own, then a 36 mark and 12), the composer as the chat's (ChatHost.css.ts): its round button 8 in from it, its
// corner theirs and that together.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { surfaceCorner } from "@stillfail/ui/styles/align.ts";

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

/** The chats: each its title over one line (the last thing said, or why it is first), cut short. */
export const mShareList = style({});
globalStyle(`${mShareList} small`, { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });

/** The foot under the list: the composer, as far in as the chat's. */
export const mShareFoot = style({ flex: "none", padding: "8px 10px 10px" });
export const mShareComposer = style({
  display: "flex", alignItems: "flex-end", gap: "2px", padding: "8px", borderRadius: surfaceCorner(8, 18),
});
export const mShareField = style({
  flex: "1", minWidth: "0", minHeight: "36px", maxHeight: "30vh", boxSizing: "border-box", margin: "0", padding: "7px 8px 7px 10px",
  border: "0", background: "none", resize: "none", color: "var(--m-ink)", font: "inherit", fontSize: vars.textInput, lineHeight: "21px",
  textWrap: "wrap", selectors: { "&:focus": { outline: "none" }, "&::placeholder": { color: "var(--m-subtle)" } },
});
