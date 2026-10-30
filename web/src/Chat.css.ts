import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { enterUpKeyframes, fadeKeyframes, nowInKeyframes, nowOutKeyframes, popInKeyframes } from "@stillfail/ui/styles/keyframes.css.ts";
import { markdown, msg, msgHead, msgTime } from "./styles/conversation.css.ts";
import { chat, chatList } from "./styles/session.css.ts";
import { COMPOSER_INNER, composerBox } from "./styles/composer.css.ts";
import { tokenStart } from "./pages/Connect.css.ts";
import { msgAvatar, msgMine, msgWaiting } from "./styles/chat.css.ts";
import { onboardingCard } from "./cloud/settings.css.ts";
import { tableKey, tableScroll } from "./Prose.css.ts";
import { leadRest, leadSlot } from "./ChatMark.css.ts";
import { glass } from "@stillfail/ui/styles/glass.ts";
import { bleedX, columns, outsetEnd, outsetStart } from "@stillfail/ui/styles/align.ts";
import { spinner } from "@stillfail/ui/styles/spinner.css.ts";
import { STILL, stillAtOnce, stillLoop } from "@stillfail/ui/styles/still.ts";
import { segments, spokesTurn, wholeRing } from "@stillfail/ui/styles/spokes.ts";

export const msgName = style({ fontWeight: "600" });
/** A chat's list of messages, on either screen (the wide screen's pane, the phone's page): what quotes jump within. */
export const chatMessages = style({});
/** A row waiting its turn among what changes the list's height (listQueue.ts): no room yet, nothing shown. */
globalStyle(`${chatMessages} > [data-queued]`, { display: "none" });
export const chatToBottom = style({
  position: "absolute", right: "24px", bottom: "12px", zIndex: "5", display: "grid", placeItems: "center",
  width: "34px", height: "34px", borderRadius: "50%", border: `1px solid ${vars.line}`, background: vars.canvas,
  color: vars.text, boxShadow: `0 2px 8px ${vars.shadow}`, cursor: "pointer",
  animation: `${fadeKeyframes} 160ms ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.hover },
    // Right over the send button, including the curve extending past the message column.
    [`${chat}[data-under-composer] &`]: {
      // (Its pane less what it leaves the small web services in the corner, as its composer does.)
      right: "calc((100% - var(--avoid-previews, 0px) - min(760px + 2 * var(--composer-curve), 100% - var(--avoid-previews, 0px) - 24px, 100% - var(--avoid-previews, 0px) - 2 * var(--composer-inset) + 2 * var(--composer-curve))) / 2 + 6px + var(--avoid-previews, 0px))",
      width: "32px", height: "32px",
      bottom: "calc(12px + var(--composer-room) + var(--asks-height, 0px))", border: "0",
      ...glass, boxShadow: "0 1px 3px rgb(0 0 0 / .04)",
      vars: { "--composer-inset": "32px", "--composer-curve": "22px" },
    },
    // With how many new messages wait at the end (a window short of it): a pill, growing leftwards from where it sits.
    "&[data-count]": {
      width: "auto", display: "flex", alignItems: "center", gap: "4px", padding: "0 12px 0 9px", borderRadius: "17px",
      fontSize: vars.textUi, whiteSpace: "nowrap",
    },
    [`${chat}[data-under-composer] &[data-count]`]: { width: "auto", borderRadius: "16px" },
  },
  "@media": {
    "(max-width: 700px)": {
      selectors: {
        [`${chat}[data-under-composer] &`]: { vars: { "--composer-inset": "12px" } },
      },
    },
  },
});
export const chatEmpty = style({
  color: vars.muted, margin: "auto", textAlign: "center", fontSize: vars.textUi, display: "grid", gap: "4px",
});
export const chatError = style({ padding: "0 32px 10px" });
/** What is said over a chat's composer (ComposerNotice.tsx): as wide as the composer (dock.css.ts: its pane less 12 each
 * side, 804 at most), 8 over it as it is now (the dock's height, less the 12 its wrap has over the composer), going
 * with it as it opens and closes. */
export const offlineNotice = style({
  margin: "0 auto 8px", maxWidth: "804px", width: "calc(100% - 24px)",
  selectors: {
    [`${chat}[data-under-composer] > &`]: { vars: { "--composer-height": "inherit" }, marginBottom: "calc(var(--composer-height) - 4px)" },
  },
});
/**
 * What still.fail itself says in a chat: a pill across it, apart from people's and agents' messages, in one line. The grey
 * of the offline notice; a failure in red (the accent is the names'). Opened, it shows all its words, and its time.
 */
export const msgSystem = style({ display: "flex", flexDirection: "column", alignItems: "center", gap: "4px" });
export const msgSystemBox = style({
  minWidth: "0", maxWidth: "100%", padding: "6px 14px", borderRadius: "999px", background: vars.hover, color: vars.text,
  fontSize: vars.textUi, cursor: "pointer",
  selectors: {
    "&[data-failed]": { background: vars.redBg, color: vars.red },
    "&[data-open]": { borderRadius: `calc(16px * ${vars.cornerScale})`, cornerShape: vars.cornerShape },
  },
});
/**
 * Under the viewer's message that waits for a runtime the station does not have (Chat.tsx BlockedLine), where its
 * waiting is said: a red mark and words while nothing is under way (as a message not delivered is told), then installing
 * it, a word in the text's colour.
 */
export const blocked = style({
  display: "inline-flex", alignItems: "center", gap: "4px", maxWidth: "100%", flexWrap: "wrap", justifyContent: "flex-end",
  padding: "0", border: "0", background: "none", font: "inherit", textAlign: "right",
  selectors: {
    "&[data-stuck]": { color: vars.red },
    "button&": { cursor: "pointer" },
    "button&:disabled": { cursor: "default", opacity: ".6" },
  },
});
export const blockedWords = style({ overflowWrap: "anywhere" });
export const blockedDot = style({ color: vars.muted });
/** Installing: a word in the text's colour, underlined under the pointer (the line it ends is what installs). */
export const blockedAction = style({
  padding: "0", border: "0", background: "none", color: vars.text, font: "inherit", fontWeight: "600", cursor: "pointer",
  selectors: {
    [`button:hover:not(:disabled) > &, button&:hover:not(:disabled)`]: { textDecoration: "underline", textUnderlineOffset: "3px" },
    "&:disabled": { opacity: ".5", cursor: "default" },
  },
});
// In a notice (one with none of the viewer's messages waiting for it): apart from its words, in the pill's colour.
globalStyle(`${msgSystemBox} ${blockedDot}`, { margin: "0 6px", color: "inherit" });
globalStyle(`${msgSystemBox} ${blockedAction}`, { color: "inherit", textDecoration: "underline", textUnderlineOffset: "3px" });
/** What went wrong in a notice about a profile: a link to that profile's page, in the pill's own colour, underlined. */
export const msgSystemLink = style({ textDecoration: "underline", textUnderlineOffset: "3px" });
globalStyle(`${msgSystemBox} ${markdown} a.${msgSystemLink}`, { color: "inherit" });
/** A notice's words and what is done at their end (reporting it): the words cut short before it, not it. */
export const msgSystemLine = style({ display: "flex", alignItems: "baseline", minWidth: "0" });
export const msgSystemEnd = style({ flex: "none", whiteSpace: "nowrap" });
/** What reporting a notice sends, in its dialog's body: the dialog's own words. */
export const reportSends = style({ margin: "0", fontSize: vars.textUi, color: vars.muted, textWrap: "pretty" });
/**
 * A draft past its viewport-aware height scrolls: its cut edges fade over a narrow strip.
 * It wraps plainly, not `pretty` as the page does: that weighs the whole draft again at every letter typed, and the
 * words of lines already written hopped between them.
 */
export const composerText = style({
  flex: "1", minHeight: "20px", maxHeight: "min(480px, 40dvh)", padding: "6px 8px 4px", border: "0", outline: "none",
  resize: "none", background: "transparent", font: "inherit", fontFamily: vars.fontText, fontVariantNumeric: "normal", fontSize: vars.textInput, lineHeight: "1.5",
  color: vars.text, textWrap: "wrap",
  vars: { "--more-above": "0px", "--more-below": "0px" },
  selectors: {
    // In a column, flex: 1 would size it by its one row, not the height it is given: it would not grow.
    [`${composerBox}[data-multiline] &`]: { flex: "none", padding: "8px 8px 0" },
    "&::placeholder": { color: vars.subtle },
    [`${composerBox}:not([data-multiline]) &`]: { padding: "5px 8px 5px 0" },
    "&[data-more-above]": {
      maskImage: "linear-gradient(to bottom, transparent, #000 var(--more-above), #000 calc(100% - var(--more-below)), transparent)",
      vars: { "--more-above": "4px" },
    },
    "&[data-more-below]": {
      maskImage: "linear-gradient(to bottom, transparent, #000 var(--more-above), #000 calc(100% - var(--more-below)), transparent)",
      vars: { "--more-below": "4px" },
    },
  },
});
export const composerToolbar = style({
  display: "flex", alignItems: "center", justifyContent: "flex-end", gap: "4px", flex: "none",
  selectors: {
    // On one line, the attach button is before the text, next to where it is typed (as on the phone).
    [`${composerBox}:not([data-multiline]) &`]: { display: "contents" },
    [`${composerBox}[data-multiline] &`]: { justifyContent: "space-between" },
  },
});
export const sendBtn = style({
  selectors: {
    "&:hover:not(:disabled)": { background: vars.primaryHover },
    "&:disabled": { background: vars.lineStrong, color: vars.canvas, cursor: "default" },
    [`${composerBox} &:not(:disabled)`]: { background: vars.text, color: vars.canvas },
    [`${composerBox} &:disabled`]: { background: `color-mix(in srgb, ${vars.text} 18%, ${vars.raised})`, color: vars.raised },
    [`${composerBox} &:hover:not(:disabled)`]: { background: `color-mix(in srgb, ${vars.text} 82%, ${vars.canvas})` },
  },
});
/** Over the first message that was unread when the chat opened. */
export const chatUnreadLine = style({
  display: "flex", alignItems: "center", gap: "10px", color: vars.accent, fontSize: vars.textMeta, fontWeight: "500",
  selectors: {
    "&::before": { content: "\"\"", flex: "1", height: "1px", background: "currentColor", opacity: ".5" },
    "&::after": { content: "\"\"", flex: "1", height: "1px", background: "currentColor", opacity: ".5" },
  },
});
export const msgAgent = style({
  padding: "0", border: "0", background: "none", font: "inherit", fontWeight: "600", color: vars.text, textDecoration: "none",
  cursor: "pointer",
  selectors: {
    // Words that are already the text's or the accent's colour, pointed at: underlined (docs/ui-panels.md 悬停).
    "&:hover": { textDecoration: "underline", textUnderlineOffset: "3px" },
  },
});
export const attachBtn = style({
  selectors: {
    [`${composerBox}:not([data-multiline]) &`]: { order: "-1" },
    "&:hover:not(:disabled)": { background: vars.hover, color: vars.text },
    "&:disabled": { opacity: ".4", cursor: "default" },
  },
});
/** Images waiting in the composer show as thumbnails. */
export const composerFiles = style({
  display: "flex", flexWrap: "wrap", gap: "6px", padding: "2px 4px 0", alignItems: "flex-start",
  selectors: {
    // Flush with the frame's padding, as the quotes above are: 12px from its edge on every side.
    [`${composerBox} &`]: { padding: "0", maxHeight: "148px", overflowY: "auto", overscrollBehavior: "contain" },
  },
});
export const msgFiles = style({
  selectors: {
    [`${msgMine} &`]: { justifyContent: "flex-end" },
  },
});
export const chatOlder = style({ display: "flex", justifyContent: "center", padding: "4px 0 8px", color: vars.muted });
/**
 * Where the chat stands, under its last message (the core's `stateText`: its row's second line, ChatMark.tsx WaitingText):
 * whole, its words wrapping where the row cuts them to a line, its lead's icon level with their first line.
 */
export const chatState = style({ fontSize: vars.textMeta, lineHeight: "20px", color: vars.muted, vars: { "--lead-gap": "6px" } });
globalStyle(`${chatState}[data-turn]`, { color: vars.text });
globalStyle(`${chatState} ${leadRest}`, { overflow: "visible", whiteSpace: "normal", overflowWrap: "anywhere" });
globalStyle(`${chatState} ${leadSlot}`, { height: 20 });
globalStyle(`${chatState}[data-state-line]`, { alignItems: "flex-start" });
export const chatNewer = style({ display: "flex", justifyContent: "center", padding: "8px 0 4px", color: vars.muted });
export const msgUnsent = style({
  display: "flex", alignItems: "center", justifyContent: "flex-end", gap: "2px", marginTop: "4px",
  fontSize: vars.textMeta,
});
export const msgUnsentNote = style({});
export const msgUnsentBtn = style({
  display: "inline-flex", alignItems: "center", gap: "4px", padding: "3px 7px", border: "0",
  borderRadius: `calc(7px * ${vars.cornerScale})`, background: "none", color: vars.muted, font: "inherit",
  cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&:hover:not(:disabled)": { background: vars.hover, color: vars.text },
    "&:disabled": { opacity: ".55", cursor: "default" },
    "&[aria-busy=\"true\"]": { cursor: "progress" },
  },
});
/**
 * Someone's message has its avatar out in the margin, left of its text (which takes no less room for it), held in view
 * while the message scrolls past: however long a reply, whose it is shows at the top of the pane. An agent at work has
 * the same avatar in the same place, where its message lands. A narrow pane has no margin: there it takes a column.
 */
export const msgRow = style({
  gap: "10px", display: "grid", gridTemplateColumns: "var(--avatar-column) minmax(0, 1fr)", columnGap: "0",
  alignItems: "start",
  vars: { "--avatar-column": "0px" },
  selectors: {
    "&[data-held]": { gridTemplateColumns: "var(--avatar-column) minmax(0, 1fr)" },
  },
  "@media": {
    "(max-width: 700px)": {
      // The 18px avatar reaches 3px past its 15px column into the list's 16px padding: 13px from the edge, 13px to the name.
      columnGap: "13px",
      vars: { "--avatar-column": "15px" },
    },
  },
});
export const msgMain = style({
  minWidth: "0", display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: "4px",
  selectors: {
    // What it says unrolls from its avatar's middle, 9px + the gap to its left.
    [`${msgRow}[data-emitting] > &`]: { transformOrigin: "-16px 12px" },
  },
  "@media": {
    "(max-width: 700px)": {
      selectors: {
        [`${msgRow}[data-emitting] > &`]: { transformOrigin: "-22px 12px" },
      },
    },
  },
});
/**
 * A message's own table (not one in a list item or a quote) scrolls through the room its list leaves beside the words
 * too, where that room is only the page's margin (`--list-gutter`, set by such a list: the phone's, the wide screen's,
 * whose avatars stand by their heads' line): scrolled, it runs to the pane's edge, and at either end it lines up with
 * the words.
 */
globalStyle(`${msgMain} > ${markdown} > ${tableScroll}`, { ...bleedX("var(--list-gutter, 0px)"), maxWidth: "calc(100% + 2 * var(--list-gutter, 0px))" });
/**
 * Its copy key out in that margin where the margin has its whole room (the wide list's: 44 at 768 of its width), so a
 * table as wide as the message scrolls not at all for it, nor shows a bar across the pane; narrower, past its end,
 * scrolled to (Prose.css.ts tableKey: its 6, an IconButton's 32, its 6).
 */
globalStyle(`${chatList} ${msgMain} > ${markdown} > ${tableScroll} > ${tableKey}`, {
  "@container": { "(min-width: 768px)": outsetEnd(44) },
});
export const msgAvatarAgent = style({
  background: vars.neutralBg,
  // Slack's mark on its corner (msgAvatarSlack) is out past its round.
  selectors: { "&[data-slack]": { overflow: "visible" } },
});
/** A Slack person's avatar with Slack's mark on its corner (msgAvatarSlack), out past its round. */
export const msgAvatarSlackHolder = style({ selectors: { "&[data-slack]": { overflow: "visible" } } });
/** Their Slack picture in it, round as the holder (out past which the mark goes) no longer clips it. */
export const msgAvatarSlackPicture = style({ display: "block", width: "18px", height: "18px", borderRadius: "50%", objectFit: "cover" });
/** Slack's mark on the corner of an avatar, over what was said in Slack (Chat.tsx SentElsewhere). */
export const msgAvatarSlack = style({
  position: "absolute", right: "-6px", bottom: "-6px", width: "14px", height: "14px", display: "grid", placeItems: "center",
  borderRadius: "50%", background: vars.list, boxShadow: `0 0 0 1px ${vars.line}`,
});
export const fileCard = style({
  selectors: {
    [`${composerFiles} &`]: { animation: `${enterUpKeyframes} 180ms ${vars.easeOut} both` },
  },
});
// Digits all one width: a percentage counting up does not shake.
export const fileCardMeta = style({
  fontSize: vars.textCaption, lineHeight: "16px", color: vars.muted, fontVariantNumeric: "tabular-nums",
  selectors: {
    [`${fileCard}[data-error] &`]: { color: vars.red },
  },
});
export const fileCardText = style({ flex: "1", minWidth: "0", display: "grid" });
/**
 * A file's card in a message (a screen's too): its sheet and words 16 in across and 12 down. What a message carries
 * (files' and screens' cards, pictures, videos, pasted text) is rounded alike: a row's corner, the app's ladder's 18
 * (a card's on a card a row high reads as a capsule).
 */
export const FILE_CARD_PAD = { y: 12, x: 16 } as const;
export const MESSAGE_FILE_CORNER = `calc(18px * ${vars.cornerScale})`; // own corner: the app's row step (sf row_corner), no web token for it yet
/** A file's kind at a glance (Chat.tsx FileTile): a sheet with its extension, in the text's colour; dashed when only its
 * path goes; filling with the accent as it goes up; its extension red when it failed. */
export const fileTile = style({ flex: "none", fill: "none", stroke: vars.muted, strokeWidth: 1.5, strokeLinecap: "round", strokeLinejoin: "round" });
export const fileTileExt = style({ fill: vars.text, stroke: "none", fontSize: ".62em", fontWeight: 600, letterSpacing: ".02em", selectors: { [`${fileTile}[data-error] &`]: { fill: vars.red } } });
export const fileTileFill = style({ fill: `color-mix(in srgb, ${vars.accent} 22%, transparent)`, stroke: "none", transition: "y 200ms linear" });
export const fileCardStem = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const fileCardExt = style({ flex: "none", whiteSpace: "nowrap" });
/** What a file dragged in is, on its card's hover: its name and where it is beside how it goes; under them, how the
 * chat takes what is dragged in. Words only where they say something; the controls small. */
export const refInfo = style({ display: "grid", gap: "10px", minWidth: "0", width: "300px", maxWidth: "100%" });
export const refInfoHead = style({ display: "flex", alignItems: "center", gap: "12px", minWidth: "0" });
export const refInfoText = style({ flex: "1", minWidth: "0", display: "grid", gap: "2px" });
export const refInfoName = style({ fontWeight: 500, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
// The folder's end is what tells: cut from its start.
export const refInfoPath = style({ color: vars.muted, fontSize: vars.textMeta, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", direction: "rtl", textAlign: "left" });
export const refInfoMode = style({ flex: "none", vars: { "--pad": "2px", "--gap": "0px" } });
globalStyle(`${refInfoMode} > button`, { height: "24px", padding: "0 10px", fontSize: vars.textMeta });
export const refInfoChat = style({ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px", color: vars.muted, fontSize: vars.textMeta, cursor: "pointer" });
export const fileCardName = style({
  display: "flex", minWidth: "0", fontSize: vars.textUi, lineHeight: "20px", whiteSpace: "nowrap",
});
/**
 * A message's file card with a button of its own beside the one that opens it (a download's ✕ or ↻): laid over the
 * room the card keeps for it at its end (`fileCardSlot`, as wide as fileCardRemove), where the composer's card has its
 * own.
 */
export const fileCardHold = style({ position: "relative", display: "inline-flex", maxWidth: "100%" });
export const fileCardSlot = style({ width: "22px", height: "22px", flex: "none" });
// (the card's right padding: later.css.ts fileCard)
export const fileCardAction = style({ position: "absolute", top: "50%", right: "10px", transform: "translateY(-50%)" });
export const fileCardRemove = style({
  display: "grid", placeItems: "center", width: "22px", height: "22px", padding: "0", border: "0", borderRadius: "50%",
  background: "none", color: vars.muted, cursor: "pointer", flex: "none",
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
  },
  // No hover on a touch screen: it shows as it would under the pointer.
  "@media": { "(hover: none)": { background: vars.hover } },
});
export const msgImage = style({
  selectors: {
    // Files open in a reading page over the whole window (FilePreview.tsx).
    // Images hold their place: the box is set from the size sent with them.
    "button&": {
      position: "relative", padding: "0", border: "0", cursor: "zoom-in", display: "block", overflow: "hidden",
      borderRadius: MESSAGE_FILE_CORNER, background: vars.neutralBg, cornerShape: vars.cornerShape,
    },
  },
});
/**
 * What an image shows until it loads: a few blurred warm blots drifting on the grey. When the image comes it is brushed
 * in from the top, blurred to sharp, and the blots fade out behind it.
 */
export const msgImageWait = style({
  position: "absolute", inset: "0", overflow: "hidden", background: vars.neutralBg, pointerEvents: "none",
  transition: `opacity 300ms ${vars.easeOut} 800ms`,
  selectors: {
    [`${msgImage}[data-loaded] &`]: { opacity: "0" },
    // Its wait was for the image's coming in, 1ms then.
    [`${STILL} &`]: stillAtOnce,
  },
});
const blotDrift = [
  keyframes({ to: { transform: "translate(35%, 25%) scale(1.15)" } }),
  keyframes({ to: { transform: "translate(-30%, 20%) scale(.9)" } }),
  keyframes({ to: { transform: "translate(20%, -30%) scale(1.1)" } }),
];
const blots = [
  { color: "light-dark(oklch(80% .12 45), oklch(45% .1 42))", place: { left: "-15%", top: "-20%" }, time: "6s" },
  { color: "light-dark(oklch(85% .09 75), oklch(42% .07 70))", place: { right: "-20%", top: "10%" }, time: "7s" },
  { color: "light-dark(oklch(78% .08 20), oklch(40% .08 20))", place: { left: "15%", bottom: "-35%" }, time: "8s" },
];
// The image's ThumbHash, sent with it: a small picture of it blurred, filling its box as the image will.
globalStyle(`${msgImageWait}[data-likeness]`, { backgroundSize: "cover", backgroundPosition: "center" });
// Not to be had (fetching it failed): the box stays as it waited, still, and says so.
globalStyle(`${msgImage}[data-failed]`, { cursor: "pointer" });
globalStyle(`${msgImage}[data-failed] ${msgImageWait} i`, { animation: "none" });
// Far from the screen (before it is near enough to load), still: blurred blots drifting where no one sees them cost a
// phone every frame all the same.
globalStyle(`${msgImage}:not([data-near]) ${msgImageWait} i`, { animationPlayState: "paused" });
export const msgImageUnavailable = style({
  position: "absolute", inset: "0", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center",
  gap: "6px", fontSize: vars.textMeta, color: vars.muted, background: `color-mix(in oklab, ${vars.neutralBg} 70%, transparent)`,
});
globalStyle(`${msgImageWait} i`, {
  position: "absolute", width: "70%", aspectRatio: "1", borderRadius: "50%", filter: "blur(28px)", opacity: ".75",
});
blots.forEach((b, i) => {
  globalStyle(`${msgImageWait} i:nth-child(${i + 1})`, {
    ...b.place, background: b.color, animation: `${blotDrift[i]} ${b.time} ease-in-out infinite alternate`,
  });
  globalStyle(`${STILL} ${msgImageWait} i:nth-child(${i + 1})`, stillLoop());
});
const msgImageRevealKeyframes = keyframes({
  from: { maskPosition: "0 100%", filter: "blur(14px)", transform: "scale(1.04)" },
  to: { maskPosition: "0 0", filter: "blur(0)", transform: "none" },
});
globalStyle(`button${msgImage} img`, { position: "relative" });
globalStyle(`button${msgImage}:not([data-loaded]) img`, { visibility: "hidden" });
globalStyle(`button${msgImage}[data-loaded="reveal"] img`, {
  maskImage: "linear-gradient(to bottom, #000 40%, transparent 60%)", maskSize: "100% 250%",
  animation: `${msgImageRevealKeyframes} 1100ms ${vars.easeOut} both`,
});
/** Quoting: a small button at the selection, then an editor for the comment. */
/** Quoting, part of the composer rather than floating around it. */
export const quotePop = style({
  cornerShape: vars.cornerShape, position: "fixed", zIndex: "40", transform: "translate(-50%, calc(-100% - 8px))",
  display: "inline-flex", alignItems: "center", gap: "4px", height: "26px", padding: "0 10px", border: "0",
  borderRadius: "999px", background: vars.primary, color: vars.onPrimary, fontSize: vars.textMeta, fontWeight: "500",
  boxShadow: `0 6px 16px ${vars.shadow}`, cursor: "pointer", animation: `${popInKeyframes} 120ms ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.primaryHover },
  },
});
/** Words picked with a turn to share (useSelectionQuote's `onShare`): its two pills side by side, 6 apart, where one is. */
export const quotePops = style({
  position: "fixed", zIndex: "40", transform: "translate(-50%, calc(-100% - 8px))", display: "flex", gap: "6px",
});
globalStyle(`${quotePops} > ${quotePop}`, { position: "static", transform: "none" });
/** An image of a message quoted, in the composer's quote card: as small as a picked one, the station's picture. */
export const quoteThumb = style({
  cornerShape: vars.cornerShape, display: "block", width: "64px", height: "64px", borderRadius: vars.rField, overflow: "hidden",
  background: vars.neutralBg,
});
globalStyle(`${quoteThumb} img`, { width: "100%", height: "100%", objectFit: "cover", display: "block" });
/** The same over an image's corner in the list (Chat.tsx useSelectionQuote's `images`): inside it, to be reached from it. */
export const quoteImagePop = style({ transform: "translate(-100%, 0)" });
export const activityLine = style({
  selectors: {
    [`${chatList} &`]: outsetStart(columns.activity),
    "&:hover": { color: vars.text },
  },
  "@media": {
    "(max-width: 700px)": {
      selectors: {
        [`${chatList} &`]: outsetStart(columns.activityNarrow),
      },
    },
  },
});
/** What waits in the composer never crowds out the conversation: quotes and files scroll within a bounded height. */
export const composerQuotes = style({
  display: "grid", gap: "6px", padding: "0", maxHeight: "176px", overflowY: "auto", overscrollBehavior: "contain",
});
/** In the composer: the same card, full width, without the old rule down the side. */
export const composerQuote = style({
  position: "relative", display: "grid", gap: "2px", borderLeft: `2px solid ${vars.lineStrong}`,
  animation: `${enterUpKeyframes} 180ms ${vars.easeOut} both`, padding: "0", border: "0",
});
export const fileCardOpen = style({});
export const agentActivity = style({
  selectors: {
    "&[data-leaving]": { gridTemplateRows: "0fr", opacity: "0" },
  },
});
export const activityAvatar = style({
  position: "relative", display: "grid", flex: "none",
  selectors: {
    [`${agentActivity}[data-away] &`]: { visibility: "hidden" },
  },
});
/**
 * The ring round an agent at work, 3px round its avatar (Android's Chat.kt WorkRing draws the same): eight arcs in the
 * accent, the brightest a step further round each step and the others fading behind it (spokes.ts segments). It
 * steps, it does not turn: a frame for each step, none between (2026-10-19). Waiting on work it started, a still, quiet
 * whole ring.
 */
export const activityRing = style({
  position: "absolute", inset: "-3px", pointerEvents: "none",
  background: vars.accent, mask: `${segments} center / 100% no-repeat`, willChange: "rotate",
  selectors: {
    [`${agentActivity}[data-waiting] &`]: { background: vars.line, maskImage: wholeRing },
    [`${agentActivity}[data-leaving] &`]: { opacity: "0", transition: "opacity 160ms" },
    [`${STILL} &`]: stillLoop(),
  },
});
spokesTurn(activityRing);
export const activityTail = style({
  display: "flex", alignItems: "center", gap: "8px", minWidth: "0", maxWidth: "100%",
  selectors: {
    // A message coming out of the avatar: the line folds to its avatar, which flies (a copy, over the list) to where the
    // message goes and back down. Folding and unfolding are moved from script (Chat.tsx Activity).
    [`${agentActivity}[data-folded] &`]: { width: "0", opacity: "0" },
  },
});
export const activityNow = style({ display: "grid", minWidth: "0" });
export const activityNowText = style({
  gridArea: "1 / 1", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
  selectors: {
    "&[data-in]": { animation: `${nowInKeyframes} 240ms ${vars.easeOut} both` },
    "&[data-out]": { animation: `${nowOutKeyframes} 240ms ${vars.easeOut} both`, pointerEvents: "none" },
  },
});
export const activityElapsed = style({ flex: "none", color: vars.subtle, fontVariantNumeric: "tabular-nums" });
export const avatarFlying = style({
  selectors: {
    [`${chatMessages} > &`]: { position: "absolute", zIndex: "2", maxWidth: "none", margin: "0", pointerEvents: "none" },
  },
});
export const composerChoices = style({
  display: "flex", alignItems: "center", gap: "4px", flex: "1 1 auto", minWidth: "0", marginRight: "auto",
  selectors: {
    // On one line (a chat's composer, its 抄送 there): before send, at its own width, the words taking the rest.
    [`${composerBox}:not([data-multiline]) &`]: { flex: "none", marginRight: "0" },
  },
});
/** 抄送 and where it copies to (Chat.tsx CcChooser): at the end of what is left of the row, just before send. */
export const ccTools = style({ display: "flex", alignItems: "center", gap: "4px", marginLeft: "auto", minWidth: "0" });
/** Where what is sent is copied, said (Chat.tsx CcChooser): by send while some thread is ticked, on one line and opened alike; nothing to press. */
export const ccState = style({
  display: "inline-flex", alignItems: "center", gap: "8px", padding: "0 8px", whiteSpace: "nowrap",
  fontSize: vars.textMeta, color: vars.muted,
});
/** Its chooser (Chat.tsx CcChooser): just before where it copies to, once the composer is opened to write. */
export const ccSwitch = style({
  display: "contents",
  selectors: {
    [`${composerBox}:not([data-multiline]) &`]: { display: "none" },
  },
});
/** A thread it is copied to: its platform's mark and its place. */
export const ccPlace = style({ display: "inline-flex", alignItems: "center", gap: "4px" });
export const msgFlash = style({});
export const quoteCards = style({
  selectors: {
    [`${msgMine} &`]: { justifySelf: "end" },
    [`${msgRow} &`]: { justifySelf: "start" },
  },
});
export const quoteCard = style({
  position: "relative", display: "grid", overflow: "hidden", cornerShape: vars.cornerShape, border: "0",
  borderRadius: `calc(12px * ${vars.cornerScale})`, background: `color-mix(in srgb, ${vars.text} 4%, ${vars.canvas})`,
  selectors: {
    // Inside the composer, cards follow its curve: inner radius = the frame's radius less its padding.
    [`${composerQuote} &`]: { maxWidth: "none", borderRadius: COMPOSER_INNER },
  },
});
export const quoteCardSource = style({
  display: "grid", border: "0", color: vars.text, font: "inherit", textAlign: "left", cursor: "pointer",
  transition: `background ${vars.dur} ${vars.easeOut}`, gap: "0", padding: "7px 11px 0", background: "none",
  selectors: {
    "&:disabled": { cursor: "default" },
    "&:not(:disabled):hover": { background: "none" },
    [`${composerQuote} &`]: { cursor: "default", paddingRight: "30px", padding: "9px 34px 0 16px" },
  },
});
export const quoteCardWho = style({ fontWeight: "500", color: vars.text });
/** A page mark's number, as its pin on the page (annotate/Marks.css.ts). */
export const quoteCardPin = style({
  display: "inline-grid", placeItems: "center", minWidth: "16px", height: "16px", padding: "0 4px", marginRight: "6px",
  boxSizing: "border-box", borderRadius: "8px 8px 8px 2px", background: vars.accent, color: "#fff", fontSize: vars.textCaption,
  fontWeight: "600", lineHeight: "1", verticalAlign: "1px",
});
export const quoteCardText = style({
  whiteSpace: "pre-wrap", overflow: "hidden", WebkitBoxOrient: "vertical", display: "-webkit-box",
  WebkitLineClamp: "2", fontSize: vars.textMeta, lineHeight: "1.5", color: vars.muted,
  selectors: {
    [`${composerQuote} &`]: { WebkitLineClamp: "2" },
    [`${quoteCardSource}:not(:disabled):hover &`]: { color: vars.text },
  },
});
/** A quote's own picture (a preview mark's screenshot), under what it quotes. */
export const quoteCardPicture = style({
  display: "flex", padding: "6px 11px 0",
  selectors: {
    [`${composerQuote} &`]: { padding: "6px 16px 0" },
  },
});
export const quoteCardComment = style({
  selectors: {
    [`${composerQuote} &`]: { padding: "3px 16px 10px" },
  },
});
export const quoteCardInput = style({
  width: "100%", border: "0", outline: "none", background: "transparent", color: vars.text, font: "inherit",
  fontSize: vars.textUi,
  selectors: {
    "&::placeholder": { color: vars.subtle },
  },
});
export const quoteCardRemove = style({
  position: "absolute", top: "6px", right: "6px", display: "grid", placeItems: "center", width: "22px", height: "22px",
  padding: "0", border: "0", borderRadius: "50%", background: "none", color: vars.subtle, cursor: "pointer",
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
    [`${composerQuote} &`]: { top: "8px", right: "8px" },
  },
  // No hover on a touch screen: it shows as it would under the pointer.
  "@media": { "(hover: none)": { background: vars.hover } },
});
export const composerThumb = style({
  selectors: {
    "&[data-error]": { outline: `2px solid ${vars.red}`, outlineOffset: "-2px" },
  },
});
export const composerThumbOpen = style({
  display: "block", width: "100%", height: "100%", padding: "0", border: "0", background: "none", cursor: "zoom-in",
});
export const composerThumbBusy = style({
  position: "absolute", inset: "0", display: "grid", placeItems: "center", pointerEvents: "none",
  background: `color-mix(in srgb, ${vars.canvas} 55%, transparent)`,
});
/** Over a picture that failed to go up: tapped, it goes up again. */
export const composerThumbRetry = style({
  position: "absolute", inset: "0", display: "grid", placeItems: "center", padding: "0", border: "0", cursor: "pointer",
  background: "color-mix(in srgb, #000 45%, transparent)", color: "#fff",
});
export const composerThumbRemove = style({
  position: "absolute", top: "4px", right: "4px", display: "grid", placeItems: "center", width: "20px", height: "20px",
  padding: "0", border: "0", borderRadius: "50%", background: "color-mix(in srgb, #000 55%, transparent)",
  color: "#fff", cursor: "pointer", opacity: "0", transition: `opacity ${vars.dur} ${vars.easeOut}`,
  selectors: {
    [`${composerThumb}:hover &`]: { opacity: "1" },
    "&:focus-visible": { opacity: "1" },
  },
  "@media": {
    "(hover: none)": {
      opacity: "1",
    },
  },
});
export const msgWaitingLate = style({});
globalStyle(`${msgSystemBox} ${markdown}`, { minWidth: "0" });
globalStyle(`${msgSystemBox} ${markdown} > :first-child`, { marginTop: "0" });
globalStyle(`${msgSystemBox} ${markdown} > :last-child`, { marginBottom: "0" });
globalStyle(`${msgSystemBox}:not([data-open]) ${markdown} > *`, { whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" });
globalStyle(`${msgSystemBox}:not([data-open]) ${markdown} > :not(:first-child)`, { display: "none" });
globalStyle(`${sendBtn} ${spinner}`, {
  borderColor: `color-mix(in srgb, ${vars.onPrimary} 35%, transparent)`,
  borderTopColor: vars.onPrimary,
});
globalStyle(`${chatEmpty} p`, { margin: "0" });
/** Here rather than with its class: it comes after .msg-agent:hover, and wins over it. */
globalStyle(`${msgHead} ${msgName}`, {
  fontWeight: "600", fontSize: vars.textUi, color: vars.accentText, maxWidth: "240px", overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** Where a message said elsewhere went or came from, in its head after the name: a long place is cut short, and the
 * name only once nothing of the place is left to cut (shrinking a millionth as much, it keeps its whole width). */
export const msgRoute = style({
  display: "flex", alignItems: "center", gap: "6px", minWidth: "0", flexShrink: "1000000", fontSize: vars.textMeta,
  color: vars.muted, whiteSpace: "nowrap",
});
globalStyle(`${msgRoute} > svg`, { flex: "none", color: vars.accent });
globalStyle(`${msgHead} > ${msgRoute} ~ *`, { flex: "none", whiteSpace: "nowrap" });
globalStyle(`${fileCard} svg`, { flex: "none", color: vars.muted });
globalStyle(`${msgImage} img`, { display: "block", maxWidth: "100%", maxHeight: "300px", width: "auto", height: "auto" });
globalStyle(`${msgAvatarAgent} img`, { width: "14px", height: "14px" });
globalStyle(`${msgAvatarAgent} img`, { width: "12px", height: "12px" });
/** Out in the list's 40px padding, as far from its edge as from the name: 11px + 18px + 11px. */
globalStyle(`${msgRow} > ${msgAvatar}`, outsetStart(columns.avatar));
globalStyle(`${msgRow} > ${msgAvatar}`, {
  "@media": {
    "(max-width: 700px)": {
      ...outsetStart(columns.avatarNarrow),
    },
  },
});
/** Sticky offsets count from inside the list's padding: these put the avatar 8px under the pane's top. */
globalStyle(`${msgRow} > ${msgAvatar}`, { position: "sticky", top: "-16px" });
globalStyle(`${msgRow} > ${msgAvatar}`, {
  "@media": {
    "(max-width: 700px)": {
      top: "-8px",
    },
  },
});
globalStyle(`${msgRow} > ${msgAvatar}`, { marginTop: "3px" });
/**
 * A list whose messages have their avatar and name in one line over what they say, in line with it, nothing out in a
 * margin (the phone's): the avatar lies at the head's start, and what is said unrolls from it.
 */
export const inlineHeads = style({});
globalStyle(`${inlineHeads} ${msgRow}`, { gridTemplateColumns: "minmax(0, 1fr)", columnGap: "0", position: "relative" });
globalStyle(`${inlineHeads} ${msgRow} > ${msgAvatar}`, { position: "absolute", left: "0", top: "3px", margin: "0" });
globalStyle(`${inlineHeads} ${msgRow} > ${msgMain} > ${msgHead}`, { paddingLeft: "25px" });
globalStyle(`${inlineHeads} ${msgRow}[data-emitting] > ${msgMain}`, { transformOrigin: "9px 12px" });
/** No room beside the name there: where it went or came from has the line under it, from the row's start. */
globalStyle(`${inlineHeads} ${msgHead}:has(> ${msgRoute})`, { flexWrap: "wrap", rowGap: "4px" });
globalStyle(`${inlineHeads} ${msgHead} > ${msgRoute}`, { order: "1", flex: "none", width: `calc(100% + ${columns.route}px)`, ...outsetStart(columns.route) });
globalStyle(`${fileCardOpen} ${fileCard}`, { transition: `background ${vars.dur} ${vars.easeOut}` });
globalStyle(`${fileCardOpen}:hover ${fileCard}`, { background: vars.hover });
globalStyle(`button${msgImage} img`, {
  width: "100%", height: "100%", maxWidth: "none", maxHeight: "none", objectFit: "cover", display: "block",
});
// A letterboxed image's placeholder takes only its share of the box (sized where it is drawn), centred.
globalStyle(`${msgImage}[data-letterbox] ${msgImageWait}`, { inset: "auto", top: "50%", left: "50%", transform: "translate(-50%, -50%)" });
globalStyle(`button${msgImage}[data-letterbox] img`, { objectFit: "contain" });
globalStyle(`${msgRow} ${msgFiles}`, { justifyContent: "flex-start" });
/** Here rather than with its class: it comes after .quote-card-input, and wins over it. */
globalStyle(quoteCardComment, {
  padding: "9px 12px 10px", fontSize: vars.textUi, lineHeight: "1.55", whiteSpace: "pre-wrap",
  overflowWrap: "anywhere",
});
globalStyle(`${composerThumb} img`, { width: "100%", height: "100%", objectFit: "cover", display: "block" });
globalStyle(`${quoteCardText} svg`, { display: "inline", verticalAlign: "-1px", marginRight: "4px", color: vars.accent });
/** Here rather than with its class: it comes after .quote-card-input, and wins over it. */
globalStyle(quoteCardComment, { padding: "3px 11px 8px", fontSize: vars.textUi, lineHeight: "1.5" });
globalStyle(`${quoteCard}:not(:has(${quoteCardComment})) ${quoteCardSource}`, { paddingBottom: "7px" });
globalStyle(`${quoteCard}:not(:has(${quoteCardComment})) ${quoteCardPicture}`, { paddingBottom: "8px" });
/** Here rather than with its class: it comes after .chat-empty p, and wins over it. */
globalStyle(`${tokenStart} > p`, { margin: "0 0 8px", fontSize: vars.textUi });
/** Here rather than with its class: it comes after .token-start > p, and wins over it. */
globalStyle(`${onboardingCard} p`, { margin: "0", fontSize: vars.textUi });

/** Video stills share each screen's attachment sizing, with an explicit play affordance. */
export const msgVideo = style({
  position: "relative", maxWidth: "100%",
  selectors: {
    "button&": { cursor: "pointer", background: "#000", color: "#fff" },
    'button&[data-unavailable]': { background: vars.neutralBg, color: vars.muted, boxShadow: `inset 0 0 0 1px ${vars.line}` },
  },
});
globalStyle(`${msgVideo} video, ${msgVideo} img`, { width: "100%", height: "100%", objectFit: "cover", display: "block", pointerEvents: "none" });
globalStyle(`${msgVideo}[data-letterbox] video, ${msgVideo}[data-letterbox] img`, { objectFit: "contain" });
// An image on the chat itself, not on grey, once it shows (and a letterboxed one throughout): its clear parts, a window
// screenshot's shadow, show the chat rather than a grey edge. The grey is only its box waiting. (A video keeps its black.)
globalStyle(`button${msgImage}:is([data-loaded], [data-letterbox]):not(${msgVideo}):not([data-failed])`, { background: "none" });
export const msgVideoPlay = style({
  position: "absolute", top: "50%", left: "50%", transform: "translate(-50%, -50%)",
  width: "40px", height: "40px", display: "grid", placeItems: "center", borderRadius: "50%",
  background: "rgba(0, 0, 0, 0.65)", pointerEvents: "none",
});
export const msgVideoName = style({
  position: "absolute", bottom: "0", left: "0", right: "0", padding: `8px ${FILE_CARD_PAD.x}px`,
  background: "rgba(0, 0, 0, 0.65)", fontSize: vars.textMeta, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** Under its words while the core downloads it (chatDownloads.ts): how far, 4 below them. */
export const msgVideoBar = style({ display: "block", marginTop: "4px" });
/** Its name cut short before how long it is (as its message says: the station read it from its header), 8 apart. */
export const msgVideoLine = style({ display: "flex", gap: "8px", justifyContent: "space-between" });
globalStyle(`${msgVideoLine} > span:first-child`, { minWidth: "0", overflow: "hidden", textOverflow: "ellipsis" });
globalStyle(`${msgVideoLine} > span + span`, { flex: "none" });

export const msgVideoUnavailable = style({
  position: "absolute", inset: "0 0 30px", display: "flex", flexDirection: "column",
  alignItems: "center", justifyContent: "center", gap: "8px", fontSize: vars.textUi,
});
globalStyle(`${msgVideo}[data-unavailable] .${msgVideoName}`, {
  background: "transparent", color: vars.text, textAlign: "center", padding: "8px 12px",
});


/** 忽略 under a post that asks (Chat.tsx AskDismiss): quiet words, as the line a settled decision leaves. */
export const askDismiss = style({
  display: "block", alignSelf: "flex-start", width: "fit-content", margin: "6px 0 0", padding: "0", border: "0", background: "none", font: "inherit", fontSize: vars.textMeta, lineHeight: "18px", textAlign: "left",
  color: vars.subtle, cursor: "pointer", selectors: { "&:hover": { color: vars.text, textDecoration: "underline" } },
});

/** What comes and goes under a message (settling.tsx Settles): what leaves is placed over it; its children's margins kept in. */
export const settles = style({ position: "relative", display: "flow-root" });

/** The way to what waits to be decided (Chat.tsx ToAsk), as the way to the chat's end (chatToBottom) and over it when both show. */
export const chatToAsk = style({
  selectors: {
    "&[data-above]": { bottom: "54px" },
    [`${chat}[data-under-composer] &[data-above]`]: { bottom: "calc(52px + var(--composer-room) + var(--asks-height, 0px))" },
  },
});

/** What is said right on top of the composer's box (ComposerProps `above`): as wide as it, a little inset. */
export const composerAbove = style({ margin: "0 12px 6px" });
/** The activity line and, for one of several agents, its own stop: shown on hover. */
export const activityRow = style({ display: "flex", alignItems: "center", gap: "4px", minWidth: "0" });
export const activityStop = style({
  display: "grid", placeItems: "center", width: "22px", height: "22px", padding: "0", border: "0",
  borderRadius: `calc(6px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: "none", color: vars.muted, cursor: "pointer", opacity: "0", transition: "opacity 120ms",
  selectors: {
    [`${activityRow}:hover &, &:focus-visible`]: { opacity: "1" },
    "&:hover": { background: vars.hover, color: vars.text },
  },
});

/**
 * Pasted text waiting in the composer (Chat.tsx PendingFile): a file's card, its first line where a name is (clicked,
 * shown whole), how many characters under it; its buttons together at its end: put back in the text (sent again, if it
 * failed) and removed.
 */
export const pasteCardTitle = style({
  minWidth: "0", padding: "0", border: "0", background: "none", color: "inherit", font: "inherit", fontSize: vars.textUi,
  lineHeight: "20px", textAlign: "left", cursor: "pointer", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const pasteCardMeta = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const pasteCardActions = style({ display: "flex", gap: "2px", flex: "none" });
/**
 * Inside the composer, files follow its curve as its quotes do: inner radius = the frame's radius less its padding.
 * Cards are as tall as an image's thumbnail beside them.
 */
globalStyle(`${composerFiles} :is(${composerThumb}, ${fileCard})`, {
  borderRadius: COMPOSER_INNER, cornerShape: vars.cornerShape,
});
globalStyle(`${composerFiles} ${fileCard}`, { boxSizing: "border-box", height: "64px", alignItems: "center", padding: "0 14px" });
// Off the composer's frosted ground: a file to send stands on the page's own (a step up in the dark); one named by its
// path, which stays where it is, is only outlined, dashed.
// A quote (a mark, a note) waiting there stands on the same ground.
globalStyle(`:is(${composerFiles} ${fileCard}, ${composerQuote} ${quoteCard})`, {
  background: `light-dark(${vars.canvas}, color-mix(in srgb, ${vars.text} 9%, ${vars.raised}))`, boxShadow: "0 1px 2px rgb(0 0 0 / .05)",
});
globalStyle(`${composerFiles} ${fileCard}[data-named]`, { background: "none", boxShadow: "none", border: `1px dashed ${vars.lineStrong}` });
