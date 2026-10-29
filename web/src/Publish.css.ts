import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { columns } from "@stillfail/ui/styles/align.ts";
import { MESSAGE_FILE_CORNER } from "./Chat.css.ts";

/** The column the messages' boxes to tick stand in on the page, before the picture's words: a box (18) and 12 after it
 * (the app's publish_tick_room). The picture taken leaves it out (takePicture). */
export const TICKS = 30;
/** How far an attachment's ✕ reaches past its top and right edge: 20 round, its centre on the corner's curve where it
 * turns 45° (the composer's, the app's with_corner_remove); the room for it kept in the picture too. */
const HUNG = `calc(10px - ${MESSAGE_FILE_CORNER} * 0.2929)`;

/** The picture's messages, as the chat's list lays them out: 28 apart (session.css.ts chatList), the phone's 20. */
export const list = style({
  display: "flex", flexDirection: "column", gap: "28px",
  selectors: { "&[data-inline]": { gap: "20px" } },
});
/** A message and, under it, how much was hidden in it; left out of the picture, it fades. */
export const said = style({
  position: "relative", isolation: "isolate", display: "grid", gap: "6px", minWidth: "0",
  transition: `opacity ${vars.dur} ${vars.easeOut}`,
  selectors: { "&[data-off]": { opacity: "0.45" } },
});
/**
 * A message's box to tick: in a column of its own before the words (docs/ui-panels.md: what goes before a row is a
 * column of its own), before the pictures out in the margin, 12 short of them; on the middle of its first line, its
 * head's (24 high) or the viewer's own bubble's first line (`data-bubble`: under the bubble's 8).
 */
export const messageTick = style({
  position: "absolute", top: "3px", left: `calc(-1 * (var(--lead) + ${TICKS}px))`, margin: "0", zIndex: "1", lineHeight: "inherit",
  selectors: { "&[data-bubble]": { top: "calc(8px + (1lh - 18px) / 2)" } },
});
/**
 * A message lit while its box to tick is pointed at (or pressed): a band across the picture from edge to edge, behind
 * it, half the room between messages over and under it, so that lit one after another they meet; square, as a list's
 * row running out of its sides.
 */
export const lit = style({
  position: "absolute", zIndex: "-1", pointerEvents: "none", background: vars.hover, opacity: "0",
  left: `calc(-1 * (var(--edge) + var(--lead) + ${TICKS}px))`, right: "calc(-1 * var(--edge))",
  top: "calc(-1 * var(--between) / 2)", bottom: "calc(-1 * var(--between) / 2)",
  transition: `opacity ${vars.dur} ${vars.easeOut}`,
  selectors: { [`${said}:has(> ${messageTick}:is(:hover, :active)) > &`]: { opacity: "1" } },
});
/** Under a message: how many things in it were hidden (as looking secret); under the viewer's own, at its end. */
export const note = style({
  display: "flex", alignItems: "center", gap: "6px", fontSize: vars.textMeta, color: vars.muted, minWidth: "0",
  selectors: { "&[data-mine]": { justifySelf: "end" } },
});
/** An attachment in a message, as the chat draws it, the room its ✕ hangs in past its top and right kept (in the
 * picture too, so that it is laid out as the page has it); pressed, taken out or put back. */
export const file = style({
  position: "relative", display: "inline-block", maxWidth: "100%", verticalAlign: "top", cursor: "pointer",
  marginTop: HUNG, marginRight: HUNG,
});
/** What it shows; taken out, it fades. */
export const fileLook = style({
  transition: `opacity ${vars.dur} ${vars.easeOut}`,
  selectors: { [`${file}[data-off] &`]: { opacity: "0.45" } },
});
/** Its ✕ on its top right corner (the composer's: solid, the page's colour on the words'); taken out, turned into a ＋. */
export const hung = style({
  position: "absolute", top: `calc(-1 * ${HUNG})`, right: `calc(-1 * ${HUNG})`, display: "grid", placeItems: "center",
  width: "20px", height: "20px", padding: "0", border: "0", borderRadius: "50%", background: vars.text, color: vars.canvas, // own corner: a circle hung on the card's corner, not in it
  cursor: "pointer", transition: `transform ${vars.dur} ${vars.easeOut}`,
  selectors: { [`${file}[data-off] &`]: { transform: "rotate(45deg)" } },
});
/** Over the whole window (as a file's preview, FilePreview.css.ts fpMarkdown): the chat's width, below the bar. */
export const page = style({
  maxWidth: `${760 + TICKS}px`, margin: "0 auto", padding: "52px 0 64px",
  "@media": { "(max-width: 640px)": { padding: "32px 0 32px" } },
});
/**
 * The picture as it would be, on the page's ground (what it is drawn on when it is taken): 32 round what it holds, 32
 * from its top and foot, its parts 16 apart; its words the messages' pictures' room further in than its end, as those
 * stand out before them (align.ts columns.avatar). Their heads in line with their pictures (`data-inline`, the phone's
 * list), its words 32 in (18 on a phone's). Before its words, on the page, the column of the messages' boxes to tick
 * (TICKS), which the picture taken leaves out.
 */
export const paper = style({
  vars: { "--edge": "32px", "--lead": `${columns.avatar}px`, "--between": "28px" },
  display: "grid", gap: "16px", padding: `32px var(--edge) 32px calc(var(--edge) + var(--lead) + ${TICKS}px)`,
  background: vars.canvas, color: vars.text,
  selectors: { "&[data-inline]": { vars: { "--lead": "0px", "--between": "20px" } } },
  "@media": { "(max-width: 640px)": { selectors: { "&[data-inline]": { vars: { "--edge": "18px" } } } } },
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
 * whom, 复制 and 撤销 at its end; its words under the row's (parts.css.ts panelRow: 10 in, a 20 icon, 10 between).
 */
export const link = style({
  display: "flex", alignItems: "center", gap: "8px", minHeight: "30px", padding: "2px 6px 2px 10px",
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
