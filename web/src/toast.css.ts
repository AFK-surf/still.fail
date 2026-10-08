import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { fadeKeyframes, spinKeyframes, toastInKeyframes } from "./styles/keyframes.css.ts";
import { chatList } from "./styles/session.css.ts";
import { composerWrap } from "./styles/cloud.css.ts";
import { runtimeTags, spinner } from "./styles/waiting.css.ts";
import { about, firstOne, resizeHandle } from "./ui.css.ts";
import { peopleStack, quotaNote, quotaRing } from "./components.css.ts";
import { sidebarBuddy } from "./brand.css.ts";
import { modelChips } from "./pages/Accounts.css.ts";
import { slackTeamIcon } from "./pages/Connect.css.ts";
import { appearanceSetting, chooserCheck, modelPoolList, msgAvatar } from "./styles/chat.css.ts";
import { groupHead } from "./cloud/settings.css.ts";
import { details, detailsList, jobsPanel } from "./pages/ChatPage.css.ts";
import { activityLine, attachBtn, fileCard, fileCardOpen, msgFiles, msgImage, msgUnsentNote, quoteCards, sendBtn } from "./Chat.css.ts";
import { hPlace } from "./History.css.ts";

export const toastViewport = style({
  position: "fixed", left: "50%", bottom: "24px", transform: "translateX(-50%)", zIndex: "80", margin: "0",
  padding: "0", listStyle: "none", outline: "none",
});
export const toast = style({
  padding: "9px 18px", borderRadius: "999px", background: vars.primary, color: vars.onPrimary, fontSize: vars.textSecondary,
  whiteSpace: "nowrap", boxShadow: `0 8px 24px ${vars.shadow}`, animation: `${toastInKeyframes} 200ms ${vars.easeOut}`,
  selectors: {
    "&[data-state=\"closed\"]": { animation: `${fadeKeyframes} 150ms ${vars.easeOut} reverse forwards` },
  },
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(groupHead, {
  display: "flex", alignItems: "baseline", gap: "8px", margin: "0 4px 6px", fontSize: vars.textSecondary,
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(hPlace, {
  marginLeft: "auto", padding: "0 7px", borderRadius: "999px", background: vars.neutralBg, color: vars.muted,
});
/** Here rather than with its class: it comes after .toast-viewport, and wins over it. */
globalStyle(`${chatList} > *`, { width: "100%", maxWidth: "760px", marginLeft: "auto", marginRight: "auto" });
/** Blocks, not inline: a ring with no number inside would sit on its bottom edge instead of the others' text line. */
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(quotaRing, {
  position: "relative", display: "grid", placeItems: "center", flex: "none", width: "26px", height: "26px",
  color: vars.green,
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(quotaNote, { margin: "0", fontSize: vars.textSecondary });
/** Here rather than with its class: it comes after .toast-viewport, and wins over it. */
globalStyle(`${peopleStack} > *`, { marginLeft: "-4px", boxShadow: `0 0 0 1.5px ${vars.sidebar}` });
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
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(spinner, {
  width: "16px", height: "16px", flex: "none", borderRadius: "50%", border: `2px solid ${vars.lineStrong}`,
  borderTopColor: vars.accent, animation: `${spinKeyframes} 0.8s linear infinite`,
});
/** Here rather than with its class: it comes after .spinner, and wins over it. */
globalStyle(spinner, {
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animationDuration: "2.4s",
    },
  },
});
/** Here rather than with its class: it comes after .toast-viewport, and wins over it. */
globalStyle(`${composerWrap} > *`, { maxWidth: "760px", marginLeft: "auto", marginRight: "auto" });
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(sendBtn, {
  display: "grid", placeItems: "center", width: "32px", height: "32px", padding: "0", border: "0", borderRadius: "50%",
  background: vars.primary, color: vars.onPrimary, cursor: "pointer",
  transition: `background ${vars.dur} ${vars.easeOut}`,
});
/** The title bar's popover: what matters now. */
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(jobsPanel, { width: "360px", display: "flex", flexDirection: "column" });
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(details, { display: "grid", gap: "10px", margin: "0" });
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(detailsList, {
  listStyle: "none", margin: "0", padding: "0", display: "grid", gap: "8px", fontSize: vars.textSecondary,
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(attachBtn, {
  display: "grid", placeItems: "center", width: "32px", height: "32px", padding: "0", border: "0", borderRadius: "50%",
  background: "none", color: vars.muted, cursor: "pointer",
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(msgFiles, { display: "flex", flexWrap: "wrap", justifyContent: "flex-end", gap: "6px" });
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(resizeHandle, {
  position: "absolute", top: "0", bottom: "0", width: "7px", zIndex: "5", cursor: "col-resize", touchAction: "none",
});
/** Where a message came from or went: platform mark and name, a link when there is somewhere to go. */
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(hPlace, {
  display: "inline-flex", alignItems: "center", gap: "4px", padding: "1px 6px", margin: "0 2px", border: "0",
  borderRadius: `calc(6px * ${vars.cornerScale})`, background: vars.neutralBg, color: vars.text, font: "inherit",
  fontSize: vars.textLabel, lineHeight: "18px", fontWeight: "500", textDecoration: "none", verticalAlign: "1px",
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
  display: "inline-flex", alignItems: "center", gap: "10px", width: "236px", maxWidth: "100%", padding: "8px 10px",
  borderRadius: `calc(8px * ${vars.cornerScale})`, background: vars.neutralBg, color: vars.text, textAlign: "left",
  cornerShape: vars.cornerShape,
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(msgImage, {
  display: "block", borderRadius: `calc(10px * ${vars.cornerScale})`, overflow: "hidden", maxWidth: "min(100%, 360px)",
  cornerShape: vars.cornerShape,
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(msgFiles, { alignItems: "flex-start" });
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(msgAvatar, { width: "18px", height: "18px", flex: "none" });
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(fileCardOpen, {
  display: "inline-flex", maxWidth: "100%", padding: "0", border: "0", background: "none", color: "inherit",
  font: "inherit", textAlign: "left", cursor: "pointer", borderRadius: `calc(8px * ${vars.cornerScale})`,
  cornerShape: vars.cornerShape,
});
/**
 * Room around it for the avatar's ring (3px out, its edge smoothed over a pixel more on a phone's fractional scale): the
 * line clips (to fold away) at its padding's edge, not the ring's.
 */
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(activityLine, {
  display: "flex", alignItems: "center", gap: "8px", minWidth: "0", minHeight: "0", overflow: "hidden", padding: "6px",
  margin: "-6px", border: "0", background: "none", font: "inherit", fontSize: vars.textSecondary, textAlign: "left",
  color: vars.muted, cursor: "pointer",
});
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(chooserCheck, { width: "14px", display: "inline-grid", placeItems: "center", flex: "none" });
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
/** The buddy that holds the sidebar open: on its edge, pushing; closed, resting at the top left. */
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(sidebarBuddy, {
  position: "fixed", zIndex: "40", top: "14px", left: "calc(var(--sidebar-w, 240px) - 28px)", width: "28px",
  height: "28px", padding: "0", border: "0", background: "none", cursor: "pointer", WebkitAppRegion: "no-drag",
});
/** A list's first one to make (ui.tsx's FirstOne): a scene, a title, a line, what to do. */
/** Here rather than with its class: it comes after .people-stack > *, and wins over it. */
globalStyle(firstOne, {
  display: "flex", flexDirection: "column", alignItems: "center", textAlign: "center", gap: "8px", margin: "24px auto",
  padding: "8px 0 24px", maxWidth: "480px",
});
/** A quiet mark that says what a thing is on hover (ui.tsx's About), in place of a paragraph. */
/** Here rather than with its class: it comes after .chat-list > *, and wins over it. */
globalStyle(about, {
  display: "inline-flex", alignItems: "center", justifyContent: "center", width: "20px", height: "20px",
  marginLeft: "6px", padding: "0", border: "0", borderRadius: "999px", background: "none", color: vars.subtle,
  verticalAlign: "middle", cursor: "help", transition: `color ${vars.dur} ${vars.easeOut}`,
});
