import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { enterUpKeyframes, fadeKeyframes, nowInKeyframes, nowOutKeyframes, popInKeyframes, spinKeyframes } from "./styles/keyframes.css.ts";
import { markdown, msg, msgHead, msgTime } from "./styles/conversation.css.ts";
import { chat, chatList } from "./styles/session.css.ts";
import { spinner } from "./styles/waiting.css.ts";
import { composerBox } from "./styles/composer.css.ts";
import { tokenStart } from "./pages/Connect.css.ts";
import { msgAvatar, msgMine, msgWaiting } from "./styles/chat.css.ts";
import { onboardingCard } from "./cloud/settings.css.ts";
import { glass } from "./styles/glass.ts";

export const msgName = style({ fontWeight: "600" });
/** A chat's list of messages, on either screen (the wide screen's pane, the phone's page): what quotes jump within. */
export const chatMessages = style({});
// Historical loading changes opacity only, all rows in a commit together: no queue, motion or repeated layout.
globalStyle(`${chatMessages} > ${msg}[data-history-fade]`, { animation: `${fadeKeyframes} 180ms ${vars.easeOut}` });
globalStyle(`${chatMessages} > ${msg}[data-history-fade]`, { "@media": { "(prefers-reduced-motion: reduce)": { animation: "none" } } });
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
/** A chat whose station is offline: read from what was kept, not written to. */
export const offlineNotice = style({
  margin: "0 auto 8px", maxWidth: "760px", width: "calc(100% - 64px)", padding: "8px 12px", borderRadius: "10px",
  background: vars.hover, color: vars.muted, fontSize: vars.textUi,
  selectors: {
    [`${chat}[data-under-composer] > &`]: { marginBottom: "calc(8px + var(--composer-room))" },
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
    "&[data-open]": { borderRadius: "16px" },
  },
});
/** What went wrong in a notice about a profile: a link to that profile's page, in the pill's own colour, underlined. */
export const msgSystemLink = style({ textDecoration: "underline", textUnderlineOffset: "3px" });
globalStyle(`${msgSystemBox} ${markdown} a.${msgSystemLink}`, { color: "inherit" });
/**
 * A draft past its three lines scrolls: what is cut above or below fades out over a line's height, not at a hard edge.
 * It wraps plainly, not `pretty` as the page does: that weighs the whole draft again at every letter typed, and the
 * words of lines already written hopped between them.
 */
export const composerText = style({
  flex: "1", minHeight: "20px", maxHeight: "160px", padding: "6px 8px 4px", border: "0", outline: "none",
  resize: "none", background: "transparent", font: "inherit", fontSize: vars.textInput, lineHeight: "1.5",
  color: vars.text, textWrap: "wrap",
  vars: { "--more-above": "0px", "--more-below": "0px" },
  selectors: {
    // In a column, flex: 1 would size it by its one row, not the height it is given: it would not grow.
    [`${composerBox}[data-multiline] &`]: { flex: "none", padding: "8px 8px 0" },
    "&::placeholder": { color: vars.subtle },
    [`${composerBox}:not([data-multiline]) &`]: { padding: "5px 8px 5px 0" },
    "&[data-more-above]": {
      WebkitMaskImage: "linear-gradient(to bottom, transparent, #000 var(--more-above), #000 calc(100% - var(--more-below)), transparent)",
      maskImage: "linear-gradient(to bottom, transparent, #000 var(--more-above), #000 calc(100% - var(--more-below)), transparent)",
      vars: { "--more-above": "18px" },
    },
    "&[data-more-below]": {
      WebkitMaskImage: "linear-gradient(to bottom, transparent, #000 var(--more-above), #000 calc(100% - var(--more-below)), transparent)",
      maskImage: "linear-gradient(to bottom, transparent, #000 var(--more-above), #000 calc(100% - var(--more-below)), transparent)",
      vars: { "--more-below": "18px" },
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
    "&:hover": { color: vars.accent },
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
    [`${composerBox} &`]: { padding: "0 4px", maxHeight: "148px", overflowY: "auto", overscrollBehavior: "contain" },
  },
});
export const msgFiles = style({
  selectors: {
    [`${msgMine} &`]: { justifyContent: "flex-end" },
  },
});
export const chatOlder = style({ display: "flex", justifyContent: "center", padding: "4px 0 8px", color: vars.muted });
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
/** Sending it again or dropping it under way: a ring in place of the button's icon. */
export const msgUnsentSpinner = style({});
globalStyle(`${msgUnsentSpinner}${spinner}`, { width: "10px", height: "10px", borderWidth: "1.5px" });
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
export const msgAvatarAgent = style({
  background: vars.neutralBg,
  // Slack's mark on its corner (msgAvatarSlack) is out past its round.
  selectors: { "&[data-slack]": { overflow: "visible" } },
});
/** A Slack person's avatar with Slack's mark on its corner (msgAvatarSlack), out past its round. */
export const msgAvatarSlackHolder = style({ selectors: { "&[data-slack]": { overflow: "visible" } } });
/** Slack's mark on the corner of an avatar, over what was said in Slack (Chat.tsx SentElsewhere). */
export const msgAvatarSlack = style({
  position: "absolute", right: "-6px", bottom: "-6px", width: "14px", height: "14px", display: "grid", placeItems: "center",
  borderRadius: "50%", background: vars.list, boxShadow: `0 0 0 1px ${vars.line}`,
});
export const fileCard = style({
  selectors: {
    [`${composerFiles} &`]: { animation: `${enterUpKeyframes} 180ms ${vars.easeOut} both` },
  },
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      selectors: {
        [`${composerFiles} &`]: { animation: "none" },
      },
    },
  },
});
export const fileCardMeta = style({
  fontSize: vars.textCaption, lineHeight: "16px", color: vars.muted,
  selectors: {
    [`${fileCard}[data-error] &`]: { color: vars.red },
  },
});
export const fileCardText = style({ flex: "1", minWidth: "0", display: "grid" });
export const fileCardName = style({
  fontSize: vars.textUi, lineHeight: "20px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
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
      borderRadius: `calc(10px * ${vars.cornerScale})`, background: vars.neutralBg, cornerShape: vars.cornerShape,
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
    "@media": { "(prefers-reduced-motion: reduce)": { animation: "none" } },
  });
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
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none",
    },
  },
});
export const activityLine = style({
  selectors: {
    [`${chatList} &`]: { marginLeft: "-31px" },
    "&:hover": { color: vars.text },
  },
  "@media": {
    "(max-width: 700px)": {
      selectors: {
        [`${chatList} &`]: { marginLeft: "-9px" },
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
    "&::after": {
      content: "\"\"", position: "absolute", inset: "-3px", borderRadius: "50%", border: "1.5px solid transparent",
      borderTopColor: vars.accent, borderRightColor: vars.accent, animation: `${spinKeyframes} 1.1s linear infinite`,
    },
    // Waiting on work it started: a still, quiet ring.
    [`${agentActivity}[data-waiting] &::after`]: { borderColor: vars.line, animation: "none" },
    [`${agentActivity}[data-leaving] &::after`]: { opacity: "0", transition: "opacity 160ms" },
    [`${agentActivity}[data-away] &`]: { visibility: "hidden" },
  },
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      selectors: {
        "&::after": { animation: "none" },
      },
    },
  },
});
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
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      selectors: {
        "&[data-in]": { animation: "none" },
        "&[data-out]": { animation: "none" },
      },
    },
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
    [`${composerBox}:not([data-multiline]) &`]: { order: "1" },
  },
});
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
    [`${composerQuote} &`]: { maxWidth: "none", borderRadius: `calc(32px * ${vars.cornerScale} - 12px)` },
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
    [`${composerQuote} &`]: { top: "8px", right: "10px" },
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
  width: "14px", height: "14px", borderColor: `color-mix(in srgb, ${vars.onPrimary} 35%, transparent)`,
  borderTopColor: vars.onPrimary,
});
globalStyle(`${chatEmpty} p`, { margin: "0" });
/** Here rather than with its class: it comes after .msg-agent:hover, and wins over it. */
globalStyle(`${msgHead} ${msgName}`, {
  fontWeight: "600", fontSize: vars.textUi, color: vars.accentText, maxWidth: "240px", overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
});
globalStyle(`${fileCard} ${spinner}`, { width: "14px", height: "14px", flex: "none" });
globalStyle(`${fileCard} svg`, { flex: "none", color: vars.muted });
globalStyle(`${msgImage} img`, { display: "block", maxWidth: "100%", maxHeight: "300px", width: "auto", height: "auto" });
globalStyle(`${msgAvatarAgent} img`, { width: "14px", height: "14px" });
globalStyle(`${msgAvatarAgent} img`, { width: "12px", height: "12px" });
/** Out in the list's 32px padding, as far from its edge as from the name: 7px + 18px + 7px. */
globalStyle(`${msgRow} > ${msgAvatar}`, { marginLeft: "-25px" });
globalStyle(`${msgRow} > ${msgAvatar}`, {
  "@media": {
    "(max-width: 700px)": {
      marginLeft: "-3px",
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
/** Here rather than with its class: it comes after .send-btn .spinner, and wins over it. */
globalStyle(`${msgWaiting} ${spinner}`, { width: "10px", height: "10px", borderWidth: "1.5px" });
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
globalStyle(`${composerThumbBusy} ${spinner}`, { width: "16px", height: "16px" });
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
// A letterboxed image on the chat itself, not on grey (a video keeps its black).
globalStyle(`button${msgImage}[data-letterbox]:not(${msgVideo}):not([data-failed])`, { background: "none" });
export const msgVideoPlay = style({
  position: "absolute", top: "50%", left: "50%", transform: "translate(-50%, -50%)",
  width: "40px", height: "40px", display: "grid", placeItems: "center", borderRadius: "50%",
  background: "rgba(0, 0, 0, 0.65)", fontSize: vars.textHeading, pointerEvents: "none",
});
export const msgVideoName = style({
  position: "absolute", bottom: "0", left: "0", right: "0", padding: "6px 8px",
  background: "rgba(0, 0, 0, 0.65)", fontSize: vars.textMeta, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});

export const msgVideoUnavailable = style({
  position: "absolute", inset: "0 0 30px", display: "flex", flexDirection: "column",
  alignItems: "center", justifyContent: "center", gap: "8px", fontSize: vars.textUi,
});
globalStyle(`${msgVideo}[data-unavailable] .${msgVideoName}`, {
  background: "transparent", color: vars.text, textAlign: "center", padding: "8px 12px",
});


/** What the archive check made of the chat, under its agent's all-done post: a quiet line; red when the check failed. */
export const archiveCheck = style({
  margin: "6px 0 0", fontSize: vars.textMeta, color: vars.muted, lineHeight: "18px",
  selectors: { "&[data-failed]": { color: vars.red } },
});

/** What an agent needs of the viewer (Chat.tsx WaitingBar): a line after the last message, in the list's flow. */
export const waitingBar = style({
  display: "flex", alignItems: "center", gap: "8px", padding: "6px 6px 6px 12px", borderRadius: "10px",
  background: vars.amberBg, color: vars.text, fontSize: vars.textUi,
});
export const waitingText = style({
  flex: "1", minWidth: "0", display: "flex", alignItems: "center", gap: "6px", padding: "0", border: "0", background: "none",
  color: "inherit", font: "inherit", textAlign: "left", cursor: "pointer", whiteSpace: "nowrap", overflow: "hidden",
});
globalStyle(`${waitingText} > svg`, { flex: "none", color: vars.amber });
globalStyle(`${waitingText} > b`, { flex: "none", fontWeight: "600" });
globalStyle(`${waitingText} > span`, { overflow: "hidden", textOverflow: "ellipsis", color: vars.text });
globalStyle(`${waitingText}:hover > span`, { textDecoration: "underline" });
export const waitingDismiss = style({
  flex: "none", padding: "3px 8px", border: "0", borderRadius: "7px", background: "none", color: vars.muted, font: "inherit",
  fontSize: vars.textMeta, cursor: "pointer", selectors: { "&:hover": { background: vars.hover, color: vars.text } },
});
