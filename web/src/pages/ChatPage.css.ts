import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { muted } from "../styles/shell.css.ts";
import { sessionPage } from "../styles/session.css.ts";
import { pageBarTitle } from "../styles/conversation.css.ts";
import { resizeHandle } from "../ui.css.ts";
import { quotaRing, quotaRingNumber } from "../components.css.ts";

export const agentMarkBtn = style({
  display: "inline-grid", padding: "0", border: "0", background: "none", cursor: "pointer", borderRadius: "6px",
  selectors: {
    "&:focus-visible": { outline: `2px solid var(--focus, ${vars.accent})`, outlineOffset: "2px" },
  },
});
export const pageBarActions = style({
  gridColumn: "3", justifySelf: "end", display: "flex", gap: "2px",
  selectors: {
    [`${sessionPage} &`]: { gridColumn: "2" },
  },
  "@media": {
    "(max-width: 1100px)": {
      selectors: {
        [`${sessionPage} &`]: { gridColumn: "3" },
      },
    },
  },
});
export const historySummary = style({
  minWidth: "0", overflow: "hidden", whiteSpace: "nowrap", fontVariantNumeric: "tabular-nums", display: "inline-flex",
  alignItems: "center", gap: "12px", flexWrap: "wrap",
});
export const sideTabAgent = style({ display: "inline-flex", alignItems: "center", gap: "6px", lineHeight: "1" });
/** A tab is as wide as its label in the active weight, active or not: choosing one does not move the others. */
export const sideTabText = style({
  display: "inline-flex", flexDirection: "column",
  selectors: {
    "&::after": {
      content: "attr(data-text)", height: "0", overflow: "hidden", visibility: "hidden", fontWeight: "500",
      userSelect: "none", pointerEvents: "none",
    },
  },
});
export const chatInfo = style({ width: "320px", padding: "12px 14px" });
export const detailsList = style({
  selectors: {
    [`${chatInfo} &`]: { marginTop: "10px" },
  },
});
/** The history's line of what is worth a look now (a quota running out, the disk filling up, an account). */
export const attention = style({
  display: "inline-flex", alignItems: "center", gap: "5px", fontSize: vars.textXs, color: vars.muted,
  selectors: {
    "&[data-tone=\"amber\"]": { color: vars.amber },
    "&[data-tone=\"red\"]": { color: vars.red },
  },
});
export const attentionQuota = style({});
/** A session's details, by how much each matters: the account (largest), the model, what it used, the station. */
export const sessionDetails = style({
  overflowY: "auto", padding: "16px", display: "grid", gap: "20px", alignContent: "start",
});
export const runUsage = style({ margin: "0", fontSize: vars.textXs });
export const runStation = style({});
export const resourceRings = style({
  display: "flex", alignItems: "center", gap: "10px",
  selectors: {
    [`${runStation} &`]: { marginTop: "8px" },
  },
});
export const sidePanel = style({
  minWidth: "0", minHeight: "0", display: "flex", flexDirection: "column",
  background: vars.canvas,
  selectors: {
  },
  "@media": {
    "(max-width: 1100px)": {
      selectors: {
        [`${sessionPage}[data-panel="true"] &`]: {
          position: "fixed", inset: "0 0 0 auto", width: "min(460px, 100vw)", zIndex: "30",
          boxShadow: `-12px 0 32px ${vars.shadow}`,
        },
      },
    },
    "(min-width: 1101px)": {
      position: "relative",
    },
  },
});
export const sideTabList = style({
  display: "flex", alignItems: "center", gap: "2px", height: "45px", padding: "0 8px 1px",
  flex: "none",
});
export const sideTab = style({
  display: "inline-flex", alignItems: "center", height: "30px", padding: "0 12px", border: "0",
  borderRadius: `calc(10px * ${vars.cornerScale})`, background: "none", color: vars.muted, fontSize: vars.textSm,
  cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { color: vars.text, background: vars.hover },
    // aria-selected, not data-state: the Tip around each tab sets data-state to its own (closed / delayed-open).
    "&[aria-selected=\"true\"]": { color: vars.text, background: vars.selected, fontWeight: "500" },
  },
});
export const sideContent = style({
  flex: "1", minHeight: "0", display: "flex", flexDirection: "column", outline: "none",
  selectors: {
    "&[hidden]": { display: "none" },
    // A preview's tab stays loaded while another is shown (its page keeps its place).
    "&[data-state=\"inactive\"]": { display: "none" },
  },
});
export const jobsPanel = style({});
/** The title bar's button: red while one died lately, amber while a service restarts; faint with none. */
export const jobsTrigger = style({
  position: "relative",
  selectors: {
    "&[data-none]": { opacity: ".5" },
    "&[data-alarm]::after": {
      content: "\"\"", position: "absolute", top: "6px", right: "6px", width: "7px", height: "7px",
      borderRadius: "50%", boxShadow: `0 0 0 2px ${vars.canvas}`,
    },
    "&[data-alarm=\"fail\"]::after": { background: vars.red },
    "&[data-alarm=\"restart\"]::after": { background: vars.amber },
  },
});
export const details = style({});
export const detailRow = style({
  display: "grid", gridTemplateColumns: "6em minmax(0, 1fr)", gap: "12px", fontSize: vars.textSm, alignItems: "center",
});
export const detailInline = style({ display: "inline-flex", alignItems: "center", gap: "6px" });
export const detailLink = style({
  display: "inline-flex", alignItems: "center", gap: "6px",
  selectors: {
    "&:hover": { textDecoration: "underline" },
  },
});
export const sideTabWrap = style({
  display: "inline-flex", alignItems: "center", borderRadius: `calc(10px * ${vars.cornerScale})`,
  cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover },
    [`&:has(${sideTab}[aria-selected="true"])`]: { background: vars.selected },
  },
});
export const sideTabClose = style({
  display: "grid", placeItems: "center", width: "20px", height: "20px", marginRight: "5px", border: "0",
  borderRadius: `calc(6px * ${vars.cornerScale})`, background: "none", color: vars.muted, cursor: "pointer",
  cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.line, color: vars.text },
  },
});
/** The side panel's bar: tabs on the left, the panel switch in the top-right corner. */
export const sideBar = style({
  display: "flex", alignItems: "center", gap: "8px", height: "45px", padding: "0 12px 1px 8px",
  flex: "none",
});
globalStyle(`${attentionQuota} ${quotaRing}`, { flex: "none" });
globalStyle(`${attentionQuota} ${quotaRingNumber}`, { fontSize: "8px" });
globalStyle(`${runStation} p`, { margin: "0", fontSize: vars.textXs });
globalStyle(`${jobsPanel} section`, { display: "flex", flexDirection: "column" });
globalStyle(`${jobsPanel} section + section`, { marginTop: "6px" });
globalStyle(`${detailRow} dt`, { color: vars.muted });
globalStyle(`${detailsList} ${muted}`, { fontSize: vars.textXs });
globalStyle(`${sideTabWrap} ${sideTab}`, { background: "none !important", paddingRight: "4px" });
globalStyle(`${sidePanel} ${resizeHandle}`, {
  "@media": {
    "(max-width: 1100px)": {
      display: "none",
    },
  },
});
/** Side by side, the tab set is a pane that clips what is past its edge: its handle lies just inside that edge. */
globalStyle(`${sidePanel} ${resizeHandle}[data-edge="left"]`, {
  "@media": { "(min-width: 1101px)": { left: "0" } },
});
globalStyle(`${sidePanel} ${resizeHandle}[data-edge="left"]::after`, {
  "@media": { "(min-width: 1101px)": { left: "0", top: "12px", bottom: "12px" } },
});
globalStyle(`${sideBar} ${sideTabList}`, { flex: "1", minWidth: "0", height: "auto", padding: "0", borderBottom: "0" });
/** The chat's title when it can be renamed: pressed, it turns into the field (Rename.css.ts titleInputBar) in the same box. */
export const titleBtn = style({
  display: "block", width: "calc(100% + 16px)", height: "28px", margin: "0 -8px", padding: "0 8px", border: "0",
  borderRadius: `calc(6px * ${vars.cornerScale})`, background: "transparent", color: "inherit", font: "inherit", lineHeight: "28px",
  overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", cursor: "pointer", cornerShape: vars.cornerShape,
  transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: { "&:hover, &:focus-visible": { background: vars.hover } },
});
// The title keeps its width; its button's box reaches 8px past it each side (cut short with it), and a little more room
// before what follows.
globalStyle(`${pageBarTitle} h1:has(> ${titleBtn})`, { overflow: "visible", marginRight: "4px" });
