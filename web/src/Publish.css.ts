import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { CARD_PAD, cardLook } from "./styles/pages.css.ts";
import { fpHead } from "./FilePreview.css.ts";
import { DIALOG_INNER } from "@stillfail/ui/parts.css.ts";

/** The picture's messages, as the chat draws them (their heads in line, the phone's way), on a card. */
export const preview = style({
  ...cardLook, display: "grid", gap: "16px", padding: CARD_PAD, maxHeight: "340px", overflowY: "auto", minHeight: "0",
  selectors: {
    // In the dialog its corners follow the dialog's (ui.css.ts DIALOG_INNER); on the phone's sheet, the cards' own.
    "&:not([data-whole])": { borderRadius: DIALOG_INNER },
    "&[data-whole]": { maxHeight: "none", minHeight: "auto", overflowY: "visible" },
  },
});
/** Under a message: how many things in it were hidden (as looking secret), or its attachments' names. */
export const note = style({
  display: "flex", alignItems: "center", gap: "6px", fontSize: vars.textMeta, color: vars.muted, minWidth: "0",
});
/** Attachments under a message: as the chat lays them out, wrapping. */
export const files = style({ display: "flex", flexWrap: "wrap", alignItems: "flex-start", gap: "8px", marginTop: "6px" });
/** An attachment in a message, as the chat draws it, to tick: its box in its top right corner; unticked, it fades. */
export const file = style({
  position: "relative", display: "inline-block", maxWidth: "100%", verticalAlign: "top", cursor: "pointer",
  transition: `opacity ${vars.dur} ${vars.easeOut}`,
  selectors: { "&[data-off]": { opacity: "0.45" } },
});
export const tick = style({ position: "absolute", top: "8px", right: "8px" });
/** Over the whole window (as a file's preview, FilePreview.css.ts fpMarkdown): the chat's width, below the bar. */
export const page = style({
  maxWidth: "760px", margin: "0 auto", padding: "52px 0 64px",
  "@media": { "(max-width: 640px)": { padding: "32px 0 32px" } },
});
/**
 * The picture as it would be, on the page's ground (what it is drawn on when it is taken): its words 32 in, 32 from
 * its top and foot (18 in on a phone's), its parts 16 apart.
 */
export const paper = style({
  display: "grid", gap: "16px", padding: "32px", background: vars.canvas, color: vars.text,
  "@media": { "(max-width: 640px)": { padding: "32px 18px" } },
});
/** The chat's name over its messages. */
export const title = style({ margin: "0", fontSize: vars.textTitle, lineHeight: vars.leadingTitle, fontWeight: "600" });
/** still.fail's mark and name at its foot, 6 apart, 8 under the last message, muted. */
export const foot = style({
  display: "flex", alignItems: "center", gap: "6px", paddingTop: "8px", fontSize: vars.textMeta, fontWeight: "500", color: vars.muted,
});
/**
 * Its bar, as a file preview's but round at the ends: a pill holds the pill 「复制图片」 (buttons are pills everywhere) at
 * one distance all round (its half height 22, the button's 18, 4 between), and the close button is round too.
 */
export const head = style({});
globalStyle(`${fpHead}${head}`, { borderRadius: "22px", cornerShape: "round", paddingLeft: "20px", paddingRight: "4px" });
globalStyle(`${head} > button:last-child, ${head} > :last-child > button`, { borderRadius: "999px", cornerShape: "round", width: "36px", height: "36px" });
/** In the bar, after its name: how many things were hidden in all. */
export const headNote = style({ display: "inline-flex", alignItems: "center", gap: "4px", alignSelf: "center" });
/** What went wrong (the preview not read, the ticked too big together), in red. */
export const problem = style({ margin: "0", fontSize: vars.textUi, color: vars.red });
/**
 * A chat's public links in its info: a row each under 「分享图片」, a link's mark where the rows' icons are, when and by
 * whom, 复制 and 撤销 at its end; its words under the row's (ChatPage.css.ts infoRows: 3 in, a 20 icon, 10 between).
 */
export const link = style({
  display: "flex", alignItems: "center", gap: "8px", minHeight: "30px", padding: "2px 6px 2px 3px",
  fontSize: vars.textMeta, color: vars.muted,
});
/** Its mark: 14 in the rows' icons' 20, its words 10 after that (with the row's 8). */
export const linkMark = style({ flex: "none", margin: "0 5px 0 3px" });
export const linkText = style({ flex: "1 1 0", width: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const linkAction = style({
  flex: "none", padding: "2px 4px", border: "0", background: "none", color: vars.muted, font: "inherit", cursor: "pointer",
  borderRadius: vars.rOption, cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { color: vars.text, background: vars.hover },
    "&:disabled": { cursor: "default", opacity: "0.5" },
  },
});
/** The messages there are the picture's, not on a card of their own. */
globalStyle(`${paper} > ${preview}`, { background: "none", padding: "0", borderRadius: "0" });
