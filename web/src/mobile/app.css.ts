import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { mFromLeftKeyframes, mFromRightKeyframes, mRiseInKeyframes, mRiseOutKeyframes, mToLeftKeyframes, mToRightKeyframes } from "../styles/keyframes.css.ts";

export const mPage = style({
  position: "absolute", inset: "0", background: "var(--m-bg)",
  selectors: {
    "&[data-role=\"under\"]": { visibility: "hidden", pointerEvents: "none" },
    "&[data-role=\"out\"]": { pointerEvents: "none" },
    // Swiped back with a finger: the page follows it, the one under it shows a little behind.
    "&[data-role=\"peek\"]": { pointerEvents: "none" },
    "&[data-role=\"top\"]:not([data-swiping])": { transition: "transform 200ms var(--m-standard)" },
    "&[data-swiping]": { boxShadow: "-8px 0 24px rgba(0, 0, 0, .12)" },
    // Side by side: the new page pushes in whole from the right, the old goes out whole to the left (and back the other way).
    "&[data-way=\"side\"][data-forward][data-role=\"in\"]": { animation: `${mFromRightKeyframes} 300ms var(--m-standard) both` },
    "&[data-way=\"side\"][data-forward][data-role=\"out\"]": { animation: `${mToLeftKeyframes} 300ms var(--m-standard) both` },
    "&[data-way=\"side\"]:not([data-forward])[data-role=\"in\"]": { animation: `${mFromLeftKeyframes} 300ms var(--m-standard) both` },
    "&[data-way=\"side\"]:not([data-forward])[data-role=\"out\"]": { animation: `${mToRightKeyframes} 300ms var(--m-standard) both` },
    // The viewer's own page is to the left of the list (its avatar is at the list's left): it comes and goes that way.
    "&[data-way=\"left\"][data-forward][data-role=\"in\"]": { animation: `${mFromLeftKeyframes} 300ms var(--m-standard) both` },
    "&[data-way=\"left\"][data-forward][data-role=\"out\"]": { animation: `${mToRightKeyframes} 300ms var(--m-standard) both` },
    "&[data-way=\"left\"]:not([data-forward])[data-role=\"in\"]": { animation: `${mFromRightKeyframes} 300ms var(--m-standard) both` },
    "&[data-way=\"left\"]:not([data-forward])[data-role=\"out\"]": { animation: `${mToLeftKeyframes} 300ms var(--m-standard) both` },
    // A new chat rises from the bottom, over the page it leaves in place; closed, it goes down the way it came.
    "&[data-way=\"rise\"][data-forward][data-role=\"in\"]": { animation: `${mRiseInKeyframes} 380ms var(--m-ease) both` },
    "&[data-way=\"rise\"]:not([data-forward])[data-role=\"out\"]": { animation: `${mRiseOutKeyframes} 380ms var(--m-ease) both` },
  },
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none !important", transition: "none !important",
    },
  },
});
// As wide as Safari's own edge gesture reaches in, which a touch here keeps from starting (app.tsx EdgeStrip).
export const mEdge = style({
  display: "none", position: "absolute", top: "0", bottom: "0", left: "0", zIndex: "40", width: "20px",
  touchAction: "none",
  "@media": {
    "(pointer: coarse)": {
      display: "block",
    },
  },
});
export const mOverlay = style({ position: "fixed", inset: "0", zIndex: "50" });
/**
 * WIDE (app.tsx): the button for the latest chats, at the screen's bottom left as high as the composer is (ChatHost.css.ts:
 * 10 from the foot, 52 tall on one line), frosted as it is.
 */
export const mRecentButton = style({
  position: "fixed", left: "10px", bottom: "calc(10px + var(--m-foot))", zIndex: "46", display: "grid", placeItems: "center",
  width: "52px", height: "52px", padding: "0", borderRadius: "50%", color: "var(--m-ink) !important",
  boxShadow: "0 1px 3px rgb(0 0 0 / .04), 0 4px 16px rgb(0 0 0 / .08)", cursor: "pointer",
  transition: "background 160ms",
  selectors: { "&[data-open]": { background: "var(--m-ink)", color: "var(--m-bg) !important" } },
});
/** The latest chats over the page, not dimming it: a press anywhere outside them puts them away. */
export const mRecentLayer = style({
  position: "fixed", inset: "0", zIndex: "45", pointerEvents: "none",
  selectors: { "&[data-open]": { pointerEvents: "auto" } },
});
export const mRecentCatch = style({ position: "absolute", inset: "0" });
export const mRecent = style({
  position: "absolute", left: "10px", bottom: "calc(72px + var(--m-foot))", display: "flex", flexDirection: "column",
  width: "min(340px, calc(100vw - 20px))", maxHeight: "min(560px, calc(100vh - 100px - var(--m-foot)))", overflow: "hidden",
  borderRadius: "22px", background: "color-mix(in srgb, var(--m-surface) 88%, transparent)", WebkitBackdropFilter: "blur(24px)",
  backdropFilter: "blur(24px)", boxShadow: "0 14px 44px rgb(0 0 0 / .2), 0 0 0 .5px rgb(0 0 0 / .06)",
  transformOrigin: "26px calc(100% + 36px)", opacity: "0", transform: "scale(.6)",
  transition: "opacity 160ms, transform 200ms var(--m-ease)",
  selectors: {
    [`${mRecentLayer}[data-open] &`]: { opacity: "1", transform: "none", transition: "opacity 180ms, transform 280ms var(--m-ease)" },
  },
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none !important", transition: "none !important",
    },
  },
});
export const mScrim = style({
  position: "absolute", inset: "0", background: "#000", opacity: "0", transition: "opacity 300ms",
  selectors: {
    [`${mOverlay}[data-open] &`]: { opacity: ".28" },
  },
});
export const mSheet = style({
  position: "absolute", left: "0", right: "0", bottom: "0", display: "flex", flexDirection: "column",
  boxSizing: "border-box", maxHeight: "94vh", maxWidth: "680px", marginInline: "auto", paddingBottom: "var(--m-foot)", borderRadius: "26px 26px 0 0",
  background: "color-mix(in srgb, var(--m-surface) 80%, transparent)", WebkitBackdropFilter: "blur(28px)",
  backdropFilter: "blur(28px)", boxShadow: "0 -6px 36px rgba(0, 0, 0, .18)", transform: "translateY(100%)",
  // Its height is moved from script (app.tsx SheetHost): on from where a finger lets go of it, at that speed.
  transition: "transform 300ms var(--m-ease)",
  selectors: {
    "&[data-open]": { transform: "none", transition: "transform 380ms var(--m-ease)" },
    "&[data-dragging]": { transition: "none" },
  },
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none !important", transition: "none !important",
    },
  },
});
export const mGrab = style({
  display: "grid", placeItems: "center", flex: "none", padding: "12px 0 8px",
  selectors: {
    "&[data-draggable]": { cursor: "grab", touchAction: "none" },
  },
});
export const mSheetHead = style({ display: "flex", alignItems: "center", padding: "4px 18px 10px" });
export const mMenuLayer = style({ zIndex: "55" });
export const mMenu = style({
  position: "absolute", borderRadius: "14px", background: "var(--m-surface)",
  boxShadow: "0 12px 36px rgba(0, 0, 0, .25)", overflow: "hidden", transformOrigin: "0 0", opacity: "0",
  transform: "scale(.9)", transition: "opacity 150ms, transform 150ms",
  selectors: {
    "&[data-open]": { opacity: "1", transform: "none", transition: "opacity 200ms, transform 200ms" },
  },
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none !important", transition: "none !important",
    },
  },
});
export const mToast = style({
  position: "fixed", left: "50%", bottom: "calc(90px + var(--m-foot))", zIndex: "70", maxWidth: "calc(100% - 48px)",
  padding: "10px 16px", borderRadius: "18px", background: "var(--m-ink)", color: "var(--m-bg)", fontSize: vars.textUi,
  transform: "translateX(-50%)", opacity: "0", transition: "opacity 200ms", pointerEvents: "none",
  selectors: {
    "&[data-open]": { opacity: "1" },
  },
});
export const mReader = style({
  position: "fixed", inset: "0", zIndex: "60", display: "flex", flexDirection: "column", background: "var(--m-bg)",
  transform: "translateX(100%)", transition: "transform 300ms var(--m-standard)",
  selectors: {
    "&[data-open]": { transform: "none" },
  },
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none !important", transition: "none !important",
    },
  },
});
export const mReaderBar = style({ padding: "calc(var(--m-top) + 6px) 16px 10px 10px" });
export const mReaderBody = style({
  flex: "1", minHeight: "0", overflowY: "auto", display: "flex", flexDirection: "column", gap: "12px",
  padding: "0 20px calc(30px + var(--m-foot))",
});
export const mReaderLabel = style({ display: "flex", alignItems: "center", fontSize: vars.textMeta, color: "var(--m-muted)" });
globalStyle(`${mGrab} span`, { width: "38px", height: "5px", borderRadius: "3px", background: "var(--m-line)" });
globalStyle(`${mMenu} button`, {
  display: "flex", alignItems: "center", justifyContent: "space-between", boxSizing: "border-box", width: "100%",
  minHeight: "46px", padding: "12px 16px", border: "0", background: "none", color: "var(--m-ink)", fontSize: `${vars.textBody} !important`,
  cursor: "pointer",
});
