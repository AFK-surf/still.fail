// Rules that must come late in the cascade (styles/index.ts), each after what it wins over, as it says.
import { globalStyle } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { chatList } from "./session.css.ts";
import { composerWrap } from "./cloud.css.ts";
import { runtimeTags } from "./waiting.css.ts";
import { peopleStack, quotaNote } from "../components.css.ts";
import { modelChips } from "../pages/Accounts.css.ts";
import { slackTeamIcon } from "../pages/Connect.css.ts";
import { appearanceSetting, modelPoolList, msgAvatar } from "./chat.css.ts";
import { groupHead } from "../cloud/settings.css.ts";
import { details, detailsList, jobsPanel } from "../pages/ChatPage.css.ts";
import { COMPOSER_BUTTON } from "./composer.css.ts";
import { FILE_CARD_PAD, MESSAGE_FILE_CORNER, activityLine, attachBtn, fileCard, fileCardOpen, msgFiles, msgImage, msgUnsentNote, quoteCards, sendBtn } from "../Chat.css.ts";
import { hPlace } from "../History.css.ts";
import { bleedX, bleedY, overlap } from "@stillfail/ui/styles/align.ts";

/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(groupHead, {
  display: "flex", alignItems: "baseline", gap: "8px", margin: "0 4px 6px", fontSize: vars.textUi,
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(hPlace, {
  marginLeft: "auto", padding: "0 7px", borderRadius: "999px", background: vars.neutralBg, color: vars.muted,
});
/** Here rather than with its class: it comes after .toast-viewport, and wins over it. */
globalStyle(`${chatList} > *`, { width: "100%", maxWidth: "760px", marginLeft: "auto", marginRight: "auto" });
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(quotaNote, { margin: "0", fontSize: vars.textUi });
/** Here rather than with its class: it comes after .toast-viewport, and wins over it. */
globalStyle(`${peopleStack} > *`, { ...overlap(4), boxShadow: `0 0 0 1.5px ${vars.sidebar}` });
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(groupHead, { marginLeft: "0", marginRight: "0" });
/** A profile's enabled models, as chips. */
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(modelChips, {
  display: "flex", flexWrap: "wrap", gap: "6px", margin: "0", padding: "0", listStyle: "none",
});
/** The runtimes a profile runs, after its name. */
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(runtimeTags, { display: "inline-flex", gap: "4px", marginLeft: "8px", verticalAlign: "1px" });
/** Here rather than with its class: it comes after .toast-viewport, and wins over it. */
globalStyle(`${composerWrap} > *`, { maxWidth: "760px", marginLeft: "auto", marginRight: "auto" });
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(sendBtn, {
  display: "grid", placeItems: "center", width: COMPOSER_BUTTON, height: COMPOSER_BUTTON, padding: "0", border: "0", borderRadius: "50%",
  background: vars.primary, color: vars.onPrimary, cursor: "pointer",
  transition: `background ${vars.dur} ${vars.easeOut}`,
});
/** The title bar's popover: what matters now. */
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
// No taller than the room under the title bar: its list scrolls (Jobs.css.ts jobsList).
globalStyle(jobsPanel, {
  width: "360px", maxHeight: "var(--radix-popover-content-available-height, calc(100vh - 16px))", display: "flex", flexDirection: "column",
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(details, { display: "grid", gap: "10px", margin: "0" });
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(detailsList, {
  listStyle: "none", margin: "0", padding: "0", display: "grid", gap: "8px", fontSize: vars.textUi,
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(attachBtn, {
  display: "grid", placeItems: "center", width: COMPOSER_BUTTON, height: COMPOSER_BUTTON, padding: "0", border: "0", borderRadius: "50%",
  background: "none", color: vars.muted, cursor: "pointer",
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(msgFiles, { display: "flex", flexWrap: "wrap", justifyContent: "flex-end", gap: "6px" });
/** Where a message came from or went: platform mark and name, a link when there is somewhere to go. */
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(hPlace, {
  display: "inline-flex", alignItems: "center", gap: "4px", padding: "1px 6px", margin: "0 2px", border: "0",
  borderRadius: `calc(6px * ${vars.cornerScale})`, background: vars.neutralBg, color: vars.text, font: "inherit",
  fontSize: vars.textMeta, lineHeight: "18px", fontWeight: "500", textDecoration: "none", verticalAlign: "1px",
  cornerShape: vars.cornerShape, maxWidth: "100%", minWidth: "0", whiteSpace: "nowrap",
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(msgUnsentNote, {
  display: "inline-flex", alignItems: "center", gap: "4px", marginRight: "6px", color: vars.red, cursor: "default",
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(msgAvatar, {
  width: "24px", height: "24px", borderRadius: "50%", display: "grid", placeItems: "center", overflow: "hidden",
  objectFit: "cover",
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(msgFiles, { display: "flex", flexWrap: "wrap", gap: "6px", minWidth: "0", maxWidth: "100%" });
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(fileCard, {
  display: "inline-flex", alignItems: "center", gap: "10px", width: "236px", maxWidth: "100%",
  padding: `${FILE_CARD_PAD.y}px ${FILE_CARD_PAD.x}px`,
  borderRadius: MESSAGE_FILE_CORNER, background: vars.neutralBg, color: vars.text, textAlign: "left",
  cornerShape: vars.cornerShape,
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(msgImage, {
  display: "block", borderRadius: MESSAGE_FILE_CORNER, overflow: "hidden", maxWidth: "min(100%, 360px)",
  cornerShape: vars.cornerShape,
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(msgFiles, { alignItems: "flex-start" });
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(msgAvatar, { width: "18px", height: "18px", flex: "none" });
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(fileCardOpen, {
  display: "inline-flex", maxWidth: "100%", padding: "0", border: "0", background: "none", color: "inherit",
  font: "inherit", textAlign: "left", cursor: "pointer", borderRadius: MESSAGE_FILE_CORNER,
  cornerShape: vars.cornerShape,
});
/**
 * Room around it for the avatar's ring (3px out, its edge smoothed over a pixel more on a phone's fractional scale): the
 * line clips (to fold away) at its padding's edge, not the ring's.
 */
/**
 * Its words start where a message's do: as far from its avatar as a message's words from theirs (11; 13 on a phone).
 * Here rather than with its class: it comes after .chat-list > *, and wins over it.
 */
globalStyle(activityLine, {
  display: "flex", alignItems: "center", gap: "11px", minWidth: "0", minHeight: "0", overflow: "hidden", ...bleedX(6), ...bleedY(6),
  border: "0", background: "none", font: "inherit", fontSize: vars.textUi, textAlign: "left",
  color: vars.muted, cursor: "pointer",
  "@media": { "(max-width: 700px)": { gap: "13px" } },
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(modelPoolList, {
  listStyle: "none", margin: "0", padding: "0", display: "grid",
  gridTemplateColumns: "repeat(auto-fill, minmax(230px, 1fr))", gap: "2px 12px",
});
/** Quote cards: each quote stands as a card of its own, the quoted part on warm paper, the comment below on white. */
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(quoteCards, { display: "grid", gap: "6px", width: "min(440px, 88%)" });
/** Quote cards, lighter: one soft tile, the passage small and grey, the comment under it. */
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(quoteCards, { width: "auto", maxWidth: "min(380px, 88%)", gap: "4px" });
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(appearanceSetting, { maxWidth: "320px" });
/** A row's last speaker when it is an agent: its state rides on its picture (the core decides which). */
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(slackTeamIcon, {
  width: "28px", height: "28px", flex: "none", display: "inline-grid", placeItems: "center",
  borderRadius: `calc(7px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, overflow: "hidden",
});
