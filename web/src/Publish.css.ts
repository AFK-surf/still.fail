import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { columns } from "@stillfail/ui/styles/align.ts";

/** The picture's messages, as the chat's list lays them out: 28 apart (session.css.ts chatList), the phone's 20. */
export const list = style({
  display: "flex", flexDirection: "column", gap: "28px",
  selectors: { "&[data-inline]": { gap: "20px" } },
});
/** A message and, under it, how much was hidden in it; left out of the picture, it fades. */
export const said = style({
  position: "relative", display: "grid", gap: "6px", minWidth: "0",
  transition: `opacity ${vars.dur} ${vars.easeOut}`,
  selectors: { "&[data-off]": { opacity: "0.45" } },
});
/** A message's box to tick: over it, at the top of the side its words leave (its head's end; the viewer's own, its start). */
export const messageTick = style({
  position: "absolute", top: "2px", right: "0", margin: "0", zIndex: "1", cursor: "pointer",
  selectors: { "&[data-mine]": { right: "auto", left: "0" } },
});
/** Under a message: how many things in it were hidden (as looking secret); under the viewer's own, at its end. */
export const note = style({
  display: "flex", alignItems: "center", gap: "6px", fontSize: vars.textMeta, color: vars.muted, minWidth: "0",
  selectors: { "&[data-mine]": { justifySelf: "end" } },
});
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
 * The picture as it would be, on the page's ground (what it is drawn on when it is taken): 32 round what it holds, 32
 * from its top and foot, its parts 16 apart; its words the messages' pictures' room further in than its end, as those
 * stand out before them (align.ts columns.avatar). Their heads in line with their pictures (`data-inline`, the phone's
 * list), its words 32 in (18 on a phone's).
 */
export const paper = style({
  display: "grid", gap: "16px", padding: `32px 32px 32px ${32 + columns.avatar}px`, background: vars.canvas, color: vars.text,
  selectors: { "&[data-inline]": { padding: "32px" } },
  "@media": { "(max-width: 640px)": { selectors: { "&[data-inline]": { padding: "32px 18px" } } } },
});
/** The chat's name over its messages. */
export const title = style({ margin: "0", fontSize: vars.textTitle, lineHeight: vars.leadingTitle, fontWeight: "600" });
/** still.fail's mark and name at its foot, 6 apart, 8 under the last message, muted. */
export const foot = style({
  display: "flex", alignItems: "center", gap: "6px", paddingTop: "8px", fontSize: vars.textMeta, fontWeight: "500", color: vars.muted,
});
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
