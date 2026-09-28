import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { enterUpKeyframes, fadeKeyframes, nowInKeyframes, nowOutKeyframes, popInKeyframes, spinKeyframes } from "./styles/keyframes.css.ts";
import { markdown, msgHead, msgTime } from "./styles/conversation.css.ts";
import { chat, chatList } from "./styles/session.css.ts";
import { spinner } from "./styles/waiting.css.ts";
import { composerBox } from "./styles/composer.css.ts";
import { tokenStart } from "./pages/Connect.css.ts";
import { msgAvatar, msgMine, msgWaiting } from "./styles/chat.css.ts";
import { onboardingCard } from "./cloud/settings.css.ts";

export const msgName = style({ fontWeight: "600" });
export const chatToBottom = style({
  position: "absolute", right: "24px", bottom: "12px", zIndex: "5", display: "grid", placeItems: "center",
  width: "34px", height: "34px", borderRadius: "50%", border: `1px solid ${vars.line}`, background: vars.canvas,
  color: vars.text, boxShadow: `0 2px 8px ${vars.shadow}`, cursor: "pointer",
  animation: `${fadeKeyframes} 160ms ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.hover },
    // Right over the send button: the composer's box is its width (760px at most, 32px in from each side, 12px in a narrow
    // pane) and the button 6px in from its right, as big as the send.
    [`${chat}[data-under-composer] &`]: {
      right: "calc((100% - min(760px, 100% - 2 * var(--composer-inset))) / 2 + 6px)", width: "32px", height: "32px",
      bottom: "calc(12px + var(--composer-height))", border: "0",
      background: `color-mix(in oklch, ${vars.canvas} 72%, transparent)`, WebkitBackdropFilter: "blur(20px)",
      backdropFilter: "blur(20px)", boxShadow: "0 4px 12px rgb(0 0 0 / .07), 0 1px 3px rgb(0 0 0 / .05)",
      vars: { "--composer-inset": "32px" },
    },
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
  color: vars.muted, margin: "auto", textAlign: "center", fontSize: vars.textSm, display: "grid", gap: "4px",
});
export const chatError = style({ padding: "0 32px 10px" });
/** A chat whose station is offline: read from what was kept, not written to. */
export const offlineNotice = style({
  margin: "0 auto 8px", maxWidth: "760px", width: "calc(100% - 64px)", padding: "8px 12px", borderRadius: "10px",
  background: vars.hover, color: vars.muted, fontSize: vars.textSm,
  selectors: {
    [`${chat}[data-under-composer] > &`]: { marginBottom: "calc(8px + var(--composer-height))" },
  },
});
/** What ember itself says in a chat: a notice across it, apart from people's and agents' messages. */
export const msgSystem = style({ display: "flex", justifyContent: "center" });
export const msgSystemBox = style({
  display: "flex", alignItems: "flex-start", gap: "8px", maxWidth: "min(560px, 100%)", padding: "8px 12px",
  borderRadius: "12px", background: `color-mix(in oklch, ${vars.amber} 10%, ${vars.canvas})`,
  border: `1px solid color-mix(in oklch, ${vars.amber} 22%, transparent)`, fontSize: vars.textSm, color: vars.text,
});
/** A draft past its three lines scrolls: what is cut above or below fades out over a line's height, not at a hard edge. */
export const composerText = style({
  flex: "1", minHeight: "20px", maxHeight: "160px", padding: "6px 8px 4px", border: "0", outline: "none",
  resize: "none", background: "transparent", font: "inherit", fontSize: vars.textBody, lineHeight: "1.5",
  color: vars.text,
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
    [`${composerBox} &:disabled`]: { background: vars.line, color: vars.canvas },
    [`${composerBox} &:hover:not(:disabled)`]: { background: `color-mix(in oklch, ${vars.text} 82%, ${vars.canvas})` },
  },
});
/** Over the first message that was unread when the chat opened. */
export const chatUnreadLine = style({
  display: "flex", alignItems: "center", gap: "10px", color: vars.accent, fontSize: vars.textXs, fontWeight: "500",
  selectors: {
    "&::before": { content: "\"\"", flex: "1", height: "1px", background: "currentColor", opacity: ".5" },
    "&::after": { content: "\"\"", flex: "1", height: "1px", background: "currentColor", opacity: ".5" },
  },
});
export const msgAgent = style({
  padding: "0", border: "0", background: "none", font: "inherit", fontWeight: "600", color: vars.text,
  cursor: "pointer",
  selectors: {
    "&:hover": { color: vars.accent },
    [`${msgHead} &:hover`]: { textDecoration: "underline", textUnderlineOffset: "3px" },
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
export const msgUnsent = style({
  display: "flex", alignItems: "center", justifyContent: "flex-end", gap: "2px", marginTop: "4px",
  fontSize: vars.textXs,
});
export const msgUnsentNote = style({});
export const msgUnsentBtn = style({
  display: "inline-flex", alignItems: "center", gap: "4px", padding: "3px 7px", border: "0",
  borderRadius: `calc(7px * ${vars.cornerScale})`, background: "none", color: vars.muted, font: "inherit",
  cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
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
export const msgAvatarAgent = style({ background: vars.neutralBg });
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
  fontSize: "11px", color: vars.muted,
  selectors: {
    [`${fileCard}[data-error] &`]: { color: vars.red },
  },
});
export const fileCardText = style({ flex: "1", minWidth: "0", display: "grid" });
export const fileCardName = style({
  fontSize: vars.textSm, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const fileCardRemove = style({
  display: "grid", placeItems: "center", width: "22px", height: "22px", padding: "0", border: "0", borderRadius: "50%",
  background: "none", color: vars.muted, cursor: "pointer", flex: "none",
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
  },
});
export const msgImage = style({
  selectors: {
    // Files open in a reading page over the whole window (FilePreview.tsx).
    // Images hold their place: the box is set from the size sent with them.
    "button&": {
      padding: "0", border: "0", cursor: "zoom-in", display: "block", overflow: "hidden",
      borderRadius: `calc(10px * ${vars.cornerScale})`, background: vars.neutralBg, cornerShape: vars.cornerShape,
    },
  },
});
export const msgImageWait = style({
  display: "block", width: "200px", height: "140px", background: vars.neutralBg,
  selectors: {
    [`button${msgImage} &`]: { width: "100%", height: "100%" },
  },
});
/** Quoting: a small button at the selection, then an editor for the comment. */
/** Quoting, part of the composer rather than floating around it. */
export const quotePop = style({
  cornerShape: vars.cornerShape, position: "fixed", zIndex: "40", transform: "translate(-50%, calc(-100% - 8px))",
  display: "inline-flex", alignItems: "center", gap: "4px", height: "26px", padding: "0 10px", border: "0",
  borderRadius: "999px", background: vars.primary, color: vars.onPrimary, fontSize: vars.textXs, fontWeight: "500",
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
    [`${chatList} &`]: { marginLeft: "-29px" },
    "&:hover": { color: vars.text },
  },
  "@media": {
    "(max-width: 700px)": {
      selectors: {
        [`${chatList} &`]: { marginLeft: "-7px" },
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
  transition: `max-width 200ms ${vars.easeOut}, opacity 160ms ${vars.easeOut}`,
  selectors: {
    // A message coming out of the avatar: the line folds to its avatar, which flies (a copy, over the list) to where the
    // message goes and back down.
    [`${agentActivity}[data-folded] &`]: { maxWidth: "0", opacity: "0" },
  },
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      transition: "none",
    },
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
    [`${chatList} > &`]: { position: "absolute", zIndex: "2", maxWidth: "none", margin: "0", pointerEvents: "none" },
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
  borderRadius: `calc(12px * ${vars.cornerScale})`, background: `color-mix(in oklch, ${vars.text} 4%, ${vars.canvas})`,
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
export const quoteCardText = style({
  whiteSpace: "pre-wrap", overflow: "hidden", WebkitBoxOrient: "vertical", display: "-webkit-box",
  WebkitLineClamp: "2", fontSize: vars.textXs, lineHeight: "1.5", color: vars.muted,
  selectors: {
    [`${composerQuote} &`]: { WebkitLineClamp: "2" },
    [`${quoteCardSource}:not(:disabled):hover &`]: { color: vars.text },
  },
});
export const quoteCardComment = style({
  selectors: {
    [`${composerQuote} &`]: { padding: "3px 16px 10px" },
  },
});
export const quoteCardInput = style({
  width: "100%", border: "0", outline: "none", background: "transparent", color: vars.text, font: "inherit",
  fontSize: vars.textSm,
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
});
export const composerThumb = style({
  selectors: {
    "&[data-error]": { outline: `2px solid ${vars.red}`, outlineOffset: "-2px" },
  },
});
export const composerThumbBusy = style({
  position: "absolute", inset: "0", display: "grid", placeItems: "center",
  background: `color-mix(in oklch, ${vars.canvas} 55%, transparent)`,
});
export const composerThumbRemove = style({
  position: "absolute", top: "4px", right: "4px", display: "grid", placeItems: "center", width: "20px", height: "20px",
  padding: "0", border: "0", borderRadius: "50%", background: "color-mix(in oklch, #000 55%, transparent)",
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
globalStyle(`${msgSystemBox} > img`, { flex: "none", marginTop: "2px" });
globalStyle(`${msgSystemBox} ${markdown}`, { minWidth: "0" });
globalStyle(`${msgSystemBox} ${markdown} > :first-child`, { marginTop: "0" });
globalStyle(`${msgSystemBox} ${markdown} > :last-child`, { marginBottom: "0" });
globalStyle(`${msgSystemBox} ${msgTime}`, { flex: "none", marginTop: "1px" });
globalStyle(`${sendBtn} ${spinner}`, {
  width: "14px", height: "14px", borderColor: `color-mix(in oklch, ${vars.onPrimary} 35%, transparent)`,
  borderTopColor: vars.onPrimary,
});
globalStyle(`${chatEmpty} p`, { margin: "0" });
/** Here rather than with its class: it comes after .msg-agent:hover, and wins over it. */
globalStyle(`${msgHead} ${msgName}`, {
  fontWeight: "650", fontSize: vars.textBody, color: vars.accentText, maxWidth: "240px", overflow: "hidden",
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
/** Here rather than with its class: it comes after .send-btn .spinner, and wins over it. */
globalStyle(`${msgWaiting} ${spinner}`, { width: "10px", height: "10px", borderWidth: "1.5px" });
globalStyle(`${fileCardOpen} ${fileCard}`, { transition: `background ${vars.dur} ${vars.easeOut}` });
globalStyle(`${fileCardOpen}:hover ${fileCard}`, { background: vars.hover });
globalStyle(`button${msgImage} img`, {
  width: "100%", height: "100%", maxWidth: "none", maxHeight: "none", objectFit: "cover", display: "block",
});
globalStyle(`${msgRow} ${msgFiles}`, { justifyContent: "flex-start" });
/** Here rather than with its class: it comes after .quote-card-input, and wins over it. */
globalStyle(quoteCardComment, {
  padding: "9px 12px 10px", fontSize: vars.textSm, lineHeight: "1.55", whiteSpace: "pre-wrap",
  overflowWrap: "anywhere",
});
globalStyle(`${composerThumb} img`, { width: "100%", height: "100%", objectFit: "cover", display: "block" });
globalStyle(`${composerThumbBusy} ${spinner}`, { width: "16px", height: "16px" });
globalStyle(`${quoteCardText} svg`, { display: "inline", verticalAlign: "-1px", marginRight: "4px", color: vars.accent });
/** Here rather than with its class: it comes after .quote-card-input, and wins over it. */
globalStyle(quoteCardComment, { padding: "3px 11px 8px", fontSize: vars.textSm, lineHeight: "1.5" });
globalStyle(`${quoteCard}:not(:has(${quoteCardComment})) ${quoteCardSource}`, { paddingBottom: "7px" });
/** Here rather than with its class: it comes after .chat-empty p, and wins over it. */
globalStyle(`${tokenStart} > p`, { margin: "0 0 8px", fontSize: vars.textSm });
/** Here rather than with its class: it comes after .token-start > p, and wins over it. */
globalStyle(`${onboardingCard} p`, { margin: "0", fontSize: vars.textSm });
