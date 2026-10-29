import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { glass } from "@stillfail/ui/styles/glass.ts";
import { muted } from "../styles/shell.css.ts";
import { sessionPage } from "../styles/session.css.ts";
import { pageBarTitle } from "../styles/conversation.css.ts";
import { windowsEmoji } from "../StationMark.css.ts";
import { outset, outsetTop } from "@stillfail/ui/styles/align.ts";
import { resizeHandle } from "@stillfail/ui/parts.css.ts";

export const agentMarkBtn = style({
  display: "inline-grid", padding: "0", border: "0", background: "none", cursor: "pointer",
  borderRadius: `calc(6px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  selectors: {
    "&:focus-visible": { outline: `2px solid var(--focus, ${vars.accent})`, outlineOffset: "2px" },
    // Its history is the one shown beside the chat (among several agents).
    "&[data-on]": { boxShadow: `0 0 0 2px ${vars.accent}` },
  },
});
/** An agent and the station it runs on, one tile (ui.tsx AgentMark): the maker's square opens its history. */
export const agentStation = style({
  display: "inline-flex", flex: "none", borderRadius: `calc(6px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  selectors: { "&[data-on]": { boxShadow: `0 0 0 2px ${vars.accent}` } },
});
export const agentStationAgent = style({
  display: "grid", placeItems: "center", width: "var(--mark)", height: "var(--mark)", padding: "0", border: "0",
  background: "none", color: "inherit", cursor: "pointer",
  selectors: {
    "&:hover, &[data-state=open]": { background: vars.hover },
    "&:focus-visible": { outline: `2px solid var(--focus, ${vars.accent})`, outlineOffset: "2px" },
  },
});
/** The station's part: its icon, or its name (kept short) where it has none. */
export const agentStationPart = style({
  display: "inline-flex", alignItems: "center", height: "var(--mark)", maxWidth: "140px", overflow: "hidden", textOverflow: "ellipsis",
  cursor: "default", outline: "none",
  selectors: {
    "&[data-name]": { display: "block", lineHeight: "var(--mark)" },
    // Segoe's wider emoji gets the same square as its provider. Keep the existing layout for other platforms/marks.
    [`&&:not([data-name]):has(${windowsEmoji})`]: { width: "var(--mark)", paddingInline: "0", justifyContent: "center", flex: "none" },
    "&:hover, &[data-state=open], &:focus-visible": { color: vars.text, background: vars.hover },
  },
});
/** The machine it runs on, beside the title: a quiet tag. */
export const chatStation = style({
  display: "inline-flex", alignItems: "center", gap: "4px",
  flex: "none", maxWidth: "160px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
  padding: "1px 7px", border: `1px solid ${vars.line}`, borderRadius: "999px",
  color: vars.muted, fontSize: vars.textMeta, lineHeight: vars.leadingMeta, cursor: "default",
  selectors: {
    "&:hover, &[data-state=open]": { color: vars.text, borderColor: vars.lineStrong },
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
export const sideTabAgent = style({ minWidth: "0", display: "inline-flex", alignItems: "center", gap: "6px", lineHeight: "1" });
/** A tab is as wide as its label in the active weight, active or not: choosing one does not move the others. With
 * many tabs they narrow, each label on one line, cut short with an ellipsis (its tip says it whole). */
export const sideTabText = style({
  display: "inline-block", minWidth: "0", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis",
  lineHeight: "1.3",
  selectors: {
    "&::after": {
      content: "attr(data-text)", display: "block", height: "0", overflow: "hidden", visibility: "hidden",
      fontWeight: "500", userSelect: "none", pointerEvents: "none",
    },
  },
});
/** A small panel of words (with controls.css.ts popover and panelCard, docs/ui-panels.md): its sharing rows at its padding. */
export const chatInfo = style({ width: "320px" });
export const detailsList = style({
  selectors: {
    [`${chatInfo} &`]: { marginTop: "10px" },
  },
});
/** The history's line of what is worth a look now (a quota running out, the disk filling up, an account). */
export const attention = style({
  display: "inline-flex", alignItems: "center", gap: "5px", fontSize: vars.textMeta, color: vars.muted,
  selectors: {
    "&[data-tone=\"amber\"]": { color: vars.amber },
    "&[data-tone=\"red\"]": { color: vars.red },
  },
});
export const attentionQuota = style({});
/** A session's details, by how much each matters: the account (largest), the model, what it used, the station. */
/** The history's head: its model control, and why saving it failed. */
export const sessionHead = style({ display: "flex", alignItems: "center", gap: "8px", minWidth: "0", flex: "1" });
/** Under the head: what it used (large figures, a quiet line), then a row each, its mark leading. */
export const sessionDetails = style({
  display: "flex", flexDirection: "column", gap: "10px", padding: "2px 16px 14px",
  fontSize: vars.textMeta, lineHeight: vars.leadingMeta, color: vars.muted,
});
export const sessionQuiet = style({ marginInline: 0, marginBottom: 0, ...outsetTop(4), overflowWrap: "anywhere" });
export const sessionLine = style({ display: "flex", alignItems: "center", gap: "8px", minWidth: "0" });
export const sessionLineMark = style({ display: "inline-flex", alignItems: "center", justifyContent: "center", width: "16px", flex: "none" });
export const sessionLineText = style({ flex: "1 1 auto", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const sessionLineName = style({ color: vars.text });
export const sessionFile = style({ fontFamily: vars.fontMono, fontSize: vars.textMeta });
export const resourceRings = style({ display: "flex", alignItems: "center", gap: "10px", flex: "none" });
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
  minWidth: "0", display: "inline-flex", alignItems: "center", height: "30px", padding: "0 12px", border: "0",
  borderRadius: `calc(10px * ${vars.cornerScale})`, background: "none", color: vars.muted, fontSize: vars.textUi,
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
  display: "grid", gridTemplateColumns: "6em minmax(0, 1fr)", gap: "12px", fontSize: vars.textUi, alignItems: "center",
});
export const detailInline = style({ display: "inline-flex", alignItems: "center", gap: "6px" });
/** A group of rows in the chat's info (what is in it: its pull requests, its files, its agents' letters, it in Slack; what is done with it: relaying, sharing, a picture of it): rows with their icons, as a panel's are; 16 under what is over them, the groups apart without a line. */
export const infoTools = style({ display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: "2px", marginTop: "16px" });
/** What holds a pull request's row in it (its card's and its menu's trigger): the row across it, as the others are. */
export const infoPull = style({ display: "grid", gridTemplateColumns: "minmax(0, 1fr)" });

/** Where the chat is shared, at the end of its row. */
export const shareText = style({
  minWidth: "0", color: vars.muted, fontSize: vars.textMeta, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** In its dialog, the workspaces to tick, then whether their agents may send. */
export const shareList = style({ marginBlock: "0", ...outset(12), padding: "0", listStyle: "none" });
export const shareWrite = style({ marginTop: "8px" });
export const detailLink = style({
  display: "inline-flex", alignItems: "center", gap: "6px", flex: "none", whiteSpace: "nowrap",
  selectors: {
    "&:hover": { textDecoration: "underline" },
  },
});
export const sideTabWrap = style({
  minWidth: "0", display: "inline-flex", alignItems: "center", borderRadius: `calc(10px * ${vars.cornerScale})`,
  cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover },
    [`&:has(${sideTab}[aria-selected="true"])`]: { background: vars.selected },
  },
});
export const sideTabClose = style({
  flex: "none", display: "grid", placeItems: "center", width: "20px", height: "20px", marginRight: "5px", border: "0",
  borderRadius: `calc(6px * ${vars.cornerScale})`, background: "none", color: vars.muted, cursor: "pointer",
  cornerShape: vars.cornerShape,
  selectors: {
    // Over the tab's own light (it is lit with it): a step more, on the tab in front's grey too (docs/ui-panels.md 悬停).
    "&:hover": { background: vars.hover, color: vars.text },
  },
});
/** The side panel's bar: tabs on the left, the panel switch in the top-right corner. */
export const sideBar = style({
  display: "flex", alignItems: "center", gap: "8px", height: "45px", padding: "0 12px 1px 8px",
  flex: "none",
});
globalStyle(`${jobsPanel} section`, { display: "flex", flexDirection: "column" });
globalStyle(`${jobsPanel} section + section`, { marginTop: "6px" });
globalStyle(`${detailRow} dt`, { color: vars.muted });
globalStyle(`${detailsList} ${muted}`, { fontSize: vars.textMeta });
globalStyle(`${sideTabAgent} > :not(${sideTabText})`, { flex: "none" });
globalStyle(`${sideTabWrap} ${sideTab}`, { background: "none !important", paddingRight: "4px" });
// Lit with its × (the pointer on it is on the tab too): its words come up with its ground (docs/ui-panels.md 悬停).
globalStyle(`${sideTabWrap}:hover ${sideTab}`, { color: vars.text });
/** Without a close button (the history's): its whole padding. */
globalStyle(`${sideTabWrap} ${sideTab}:only-child`, { paddingRight: "12px" });
globalStyle(`${sidePanel} ${resizeHandle}`, {
  "@media": {
    "(max-width: 1100px)": {
      display: "none",
    },
  },
});
globalStyle(`${sideBar} ${sideTabList}`, { flex: "1", minWidth: "0", height: "auto", padding: "0", borderBottom: "0" });
/** A button in its details' lines (ending its warm process, copying its transcript's path): a link's look, as the
 * profile's beside it. */
export const detailButton = style({ padding: "0", border: "0", background: "none", color: "inherit", font: "inherit", cursor: "pointer" });

/** The chat takes files dropped anywhere on it (ChatPage.tsx useChatDrop): while they are over it, it frosts over (as the
 * composer's glass) and shows them in its middle, with where they go; nothing ringed, nothing in a box. */
export const dropZone = style({ position: "relative" });
const frostOut = keyframes({ to: { opacity: 0 } });
export const dropHint = style({
  // Under the composer (dock.css.ts, 3), from the first: where they go stays clear, and a dropped file's mark comes
  // into it over the frost.
  ...glass, position: "absolute", inset: "0", zIndex: 2, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center",
  gap: "16px", pointerEvents: "none", color: vars.text, fontSize: vars.textUi, fontWeight: 500,
  // Let go: it fades (drive/flight.ts FROST_OUT_MS).
  selectors: { "&[data-leaving]": { animation: `${frostOut} 260ms ease-out forwards` } },
});
/** What is dragged, each by its mark (Chat.tsx FileTile) twice the size of a card's, a few fanned out as a stack. */
export const dropMarks = style({ position: "relative", width: "180px", height: "84px" });
globalStyle(`${dropMarks} > svg`, {
  position: "absolute", left: "calc(50% - 30px)", top: "6px", width: "60px", height: "72px",
  translate: "calc((var(--i) - (var(--n) - 1) / 2) * 44px) 0",
  rotate: "calc((var(--i) - (var(--n) - 1) / 2) * 7deg)",
});
// A sheet hides the one under it.
globalStyle(`${dropMarks} > svg > path:first-of-type`, { fill: `light-dark(${vars.canvas}, ${vars.raised})` });
/** A station's screen in its tab (screen/ScreenViewer.tsx `panel`): the viewer over the whole of the pane. */
export const sideScreen = style({ position: "relative", flex: "1", minHeight: "0", overflow: "hidden" });
