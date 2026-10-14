import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { cardLook } from "./styles/pages.css.ts";
import { DIALOG_INNER } from "./ui.css.ts";

/** What a public snapshot would hold, as the chat draws it (its messages' heads in line, the phone's way), on a card. */
export const preview = style({
  ...cardLook, display: "grid", gap: "16px", padding: "16px 18px", maxHeight: "340px", overflowY: "auto", minHeight: "0",
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
  maxWidth: "760px", margin: "0 auto", padding: "84px 32px 96px", display: "grid", gap: "16px",
  "@media": { "(max-width: 640px)": { padding: "64px 18px 64px" } },
});
/** Who can read it, over the messages. */
export const lead = style({ margin: "0", fontSize: vars.textUi, color: vars.muted });
/** 「发布」 in the bar: its corners the bar's (14), less the 4 round it, as the bar's other buttons are. */
export const headGo = style({ height: "36px", borderRadius: `calc(10px * ${vars.cornerScale})`, cornerShape: vars.cornerShape });
/** In the bar, after its name: how many things were hidden in all. */
export const headNote = style({ display: "inline-flex", alignItems: "center", gap: "4px", alignSelf: "center" });
/** What went wrong (the preview not read, the ticked too big together), in red. */
export const problem = style({ margin: "0", fontSize: vars.textUi, color: vars.red });
/** The link once published, as a one-line field shows it (a pill, as the buttons under it): cut short at its end. */
export const madeLink = style({
  display: "block", minWidth: "0", height: "40px", padding: "0 18px", borderRadius: "999px", background: cardLook.background,
  fontSize: vars.textUi, lineHeight: "40px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", userSelect: "all",
});
/** A chat's public links in its info: a row each under 「公开分享」, when and by whom, 复制 and 撤销 at its end. */
export const link = style({
  display: "flex", alignItems: "center", gap: "8px", minHeight: "30px", padding: "2px 10px 2px 32px",
  fontSize: vars.textMeta, color: vars.muted,
});
export const linkText = style({ flex: "1 1 0", width: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const linkAction = style({
  flex: "none", padding: "2px 4px", border: "0", background: "none", color: vars.muted, font: "inherit", cursor: "pointer",
  borderRadius: vars.rOption, cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { color: vars.text, background: vars.hover },
    "&:disabled": { cursor: "default", opacity: "0.5" },
  },
});
/** The messages there are the page's, not on a card of their own. */
globalStyle(`${page} > ${preview}`, { background: "none", padding: "0", borderRadius: "0" });
