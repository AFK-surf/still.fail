import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { fadeInKeyframes } from "@stillfail/ui/styles/keyframes.css.ts";
import { markdown, msg, pageBarTitle } from "./styles/conversation.css.ts";
import { sessionPage } from "./styles/session.css.ts";
import { mineFilterBtn, mineFilterWide } from "./components.css.ts";
import { textToggle } from "@stillfail/ui/styles/controls.css.ts";
import { accountMenu } from "./cloud/workspace.css.ts";
import { detailRow, details, sideContent } from "./pages/ChatPage.css.ts";
import { msgRoute } from "./Chat.css.ts";
import { bleedStart, bleedX, columns } from "@stillfail/ui/styles/align.ts";
import { spinner } from "@stillfail/ui/styles/spinner.css.ts";

export const history = style({
  minWidth: "0", minHeight: "0", display: "flex", flexDirection: "column", borderLeft: `1px solid ${vars.line}`,
  background: vars.canvas,
  selectors: {
    [`${sideContent} &`]: { borderLeft: "0", flex: "1" },
  },
});
export const historyHead = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", gap: "8px", height: "45px",
  padding: "0 8px 1px 16px",
});
/** What is too long is cut at its end; its start has the room the model control stands out by (ModelTriple.css.ts). */
export const historyIdentity = style({
  display: "flex", alignItems: "center", gap: "6px", flex: "1", minWidth: "0", fontSize: vars.textUi, color: vars.muted,
  whiteSpace: "nowrap", overflow: "hidden", ...bleedStart(columns.modelControl),
});
export const historyTools = style({ display: "flex", alignItems: "center", gap: "2px", flex: "none" });
export const usage = style({
  display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(96px, 1fr))", gap: "10px 16px", margin: "0",
  padding: "12px 16px", borderBottom: `1px solid ${vars.line}`, background: vars.list,
});
export const historyBody = style({
  flex: "1", minHeight: "0", overflowY: "auto", padding: "12px 16px 40px", display: "grid",
  gridTemplateColumns: "minmax(0, 1fr)", gap: "14px", alignContent: "start", overflowAnchor: "none",
  // What the list's spacers take back on the sides they have a neighbour (virtual/list.css.ts).
  vars: { "--list-gap": "14px" },
});
/** A group's calls, opened: in its words' column, beside the turn's rail. */
export const hSteps = style({
  gridColumn: "2", minWidth: "0", display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: "2px", marginTop: "2px",
});
export const historyEdge = style({ margin: "4px 0", textAlign: "center", fontSize: vars.textMeta, color: vars.muted });
/** An event's line, as tall as its mark in the gutter: what does not fit goes to the next line, and a long place is cut
 * short, rather than squeezing the words. */
export const hLabel = style({
  display: "flex", flexWrap: "wrap", alignItems: "center", gap: "0 6px", minWidth: "0", minHeight: "20px",
  fontSize: vars.textMeta, lineHeight: "20px", color: vars.muted,
});
/** A Slack user's name: a button that says whether it is the viewer. */
export const hPerson = style({
  font: "inherit", color: "inherit", background: "none", border: "0", padding: "0", cursor: "pointer",
  display: "inline-flex", alignItems: "center", gap: "4px",
  selectors: {
    "&:hover:not(:disabled)": { textDecoration: "underline" },
    "&:disabled": { cursor: "progress" },
  },
});
/** "这是我" / "不是我" on its way: a small ring after the name. */
export const hPersonSpinner = style({});
globalStyle(`${hPersonSpinner}${spinner}`, { width: "10px", height: "10px", borderWidth: "1.5px" });
export const hPlace = style({
  selectors: {
    "a&": { cursor: "pointer" },
    "button&": { cursor: "pointer" },
    "a&:hover": { background: vars.hover, textDecoration: "underline" },
    "button&:hover": { background: vars.hover, textDecoration: "underline" },
  },
});
/** A person's words to the agent: plain text in the panel's size, folded to a few lines. */
export const hWords = style({ fontSize: vars.textUi, color: vars.text, whiteSpace: "pre-wrap", overflowWrap: "anywhere" });
/** What a job told its agent: program output, its columns kept. */
export const hOutput = style({ fontFamily: vars.fontMono, fontSize: vars.textMeta, lineHeight: vars.leadingMeta, color: vars.text, whiteSpace: "pre-wrap", overflowWrap: "anywhere" });
/** A message the agent sent: what people were sent leads the history, on a card in the size it was read in. */
export const hCard = style({
  marginTop: "4px", padding: "8px 12px", border: `1px solid ${vars.line}`, borderRadius: vars.rField,
  cornerShape: vars.cornerShape, background: vars.paper, minWidth: "0",
  selectors: {
    "&[data-failed=\"true\"]": { borderColor: vars.red },
  },
});
export const hGroup = style({});
/** A group's line: its mark (the chevron) in the gutter, what it did beside it; all of it opens the group. */
export const hGroupHead = style({
  gridColumn: "1 / -1", display: "grid", gridTemplateColumns: "20px minmax(0, 1fr) auto auto", alignItems: "center",
  columnGap: "8px", width: "100%", minWidth: "0", padding: "0", margin: "0", ...bleedX(6), paddingInline: "6px",
  border: "0", borderRadius: vars.rOption, cornerShape: vars.cornerShape, background: "none",
  color: vars.muted, fontSize: vars.textMeta, lineHeight: "20px", textAlign: "left", cursor: "pointer",
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
  },
});
export const hGroupSummary = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const hStep = style({});
export const hStepName = style({
  fontWeight: "600", flex: "none", whiteSpace: "nowrap",
  selectors: {
    [`${hStep}[data-failed="true"] &`]: { color: vars.red },
  },
});
export const hStepHint = style({
  flex: "1", minWidth: "0", color: vars.muted, fontFamily: vars.fontMono, overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap",
});
export const hStepMeta = style({
  flex: "none", color: vars.subtle, fontVariantNumeric: "tabular-nums",
  selectors: {
    [`${hStep}[data-failed="true"] &`]: { color: vars.red },
  },
});
export const hStepBody = style({
  padding: "4px 6px 8px", fontSize: vars.textMeta, whiteSpace: "pre-wrap", overflowWrap: "anywhere",
});
export const hThinking = style({
  padding: "2px 0 6px 6px", fontSize: vars.textMeta, color: vars.muted, whiteSpace: "pre-wrap", overflowWrap: "anywhere",
});
/** Open under the head, on the same ground: one block, ruled off from the steps. */
export const historyDetails = style({ borderBottom: `1px solid ${vars.line}` });
export const flip = style({
  selectors: {
    [`${textToggle} &`]: { transform: "rotate(180deg)" },
  },
});
export const hPlaceName = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis" });
export const hLiveThinking = style({
  fontSize: vars.textMeta, lineHeight: "20px", color: vars.muted, whiteSpace: "nowrap", overflow: "hidden",
  textOverflow: "ellipsis",
});
/** Long history text folds to some lines (`--fold-lines`, History.tsx Fold). */
export const fold = style({ display: "grid", gap: "2px", minWidth: "0" });
/** Folded and unfolded by a click, it moves from one height to the other (History.tsx Fold). Folded, only its last
 * line fades: the lines above it read whole. */
export const foldBody = style({
  selectors: {
    "&[data-folded]": {
      maxHeight: "calc(var(--fold-lines, 5) * 1lh + 2px)", overflow: "hidden",
      WebkitMaskImage: "linear-gradient(to bottom, #000 calc(100% - 1lh), transparent)",
      maskImage: "linear-gradient(to bottom, #000 calc(100% - 1lh), transparent)",
    },
  },
});
/** Under its words, at their left edge. */
export const foldToggle = style({ justifySelf: "start", paddingLeft: "0", paddingRight: "0" });
/** Where the turn stands with the model, under the last item: its pulse in the gutter. */
export const hPhase = style({
  fontSize: vars.textMeta, color: vars.muted,
  selectors: {
    "&[data-phase=\"responding\"]": { color: vars.text },
  },
});
export const hPhaseLine = style({ display: "flex", alignItems: "center", gap: "6px", minHeight: "20px" });
export const hPhaseTime = style({ fontVariantNumeric: "tabular-nums", color: vars.subtle });
/** An item: the rule of the turn it begins (if it does), then its events. One an activity row opened the history at is
 * shown for a moment, then back to the page. */
export const hItem = style({
  position: "relative", display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: "8px", minWidth: "0",
  borderRadius: `calc(8px * ${vars.cornerScale})`, transition: `background-color 900ms ${vars.easeOut}`,
  cornerShape: vars.cornerShape,
  selectors: {
    "&[data-focus]": { background: `color-mix(in srgb, ${vars.accent} 10%, transparent)`, transition: "none" },
  },
});
/** A turn's rule: when it began and what it did, a line on to the edge; room above it parts it from the turn before. */
export const hTurn = style({
  display: "flex", alignItems: "center", gap: "8px", paddingTop: "8px", fontSize: vars.textCaption,
  lineHeight: vars.leadingCaption, color: vars.muted, fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap",
  selectors: {
    "&::after": { content: "\"\"", flex: "1", minWidth: "24px", height: "1px", background: vars.line },
  },
});
globalStyle(`${hTurn} > span`, { minWidth: "0", overflow: "hidden", textOverflow: "ellipsis" });
/** The turn's link to copy: past the end of its rule, shown while the row is pointed at. */
export const hTurnLink = style({
  order: "1", width: "24px", height: "24px", marginBlock: "-4px", borderRadius: vars.rOption, opacity: "0",
  selectors: {
    [`${hItem}:hover &, &:focus-visible`]: { opacity: "1" },
  },
});
/** An item's events, one under another (a prompt can carry a note, tasks and messages). `data-rail`: the turn goes on
 * past it, its rail running down to the next item. */
export const hMain = style({
  position: "relative", display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: "10px", minWidth: "0",
});
/** An event: its mark in the gutter, what it is beside it. */
export const hEv = style({
  position: "relative", display: "grid", gridTemplateColumns: "20px minmax(0, 1fr)", columnGap: "8px",
  alignItems: "start", minWidth: "0",
  selectors: {
    // The turn's rail: from under its mark down to the next event's, behind that one's mark. To the next item, across
    // the gap between rows, when the turn goes on.
    "&::before": {
      content: "\"\"", position: "absolute", left: "9.5px", width: "1px", top: "20px", bottom: "-10px",
      background: vars.line, display: "none",
    },
    [`&:has(~ &)::before`]: { display: "block" },
    [`${hMain}[data-rail] > &:not(:has(~ &))::before`]: { display: "block", bottom: `-14px` },
    // A state is a block in its colour, a little past its gutter and its words (drawn under them, over the rail).
    "&[data-state]": { isolation: "isolate", color: vars.muted },
    "&[data-state]::after": {
      content: "\"\"", position: "absolute", inset: "-6px 0 -6px -6px", zIndex: "-1",
      borderRadius: vars.rField, cornerShape: vars.cornerShape, background: vars.neutralBg,
    },
    "&[data-state=\"waiting\"]": { color: vars.blue },
    "&[data-state=\"waiting\"]::after": { background: vars.blueBg },
    "&[data-state=\"human\"]": { color: vars.accentText },
    "&[data-state=\"human\"]::after": { background: vars.accentBg },
  },
});
/** An event's mark: on the canvas, so the rail passes behind it; in a state's block, on its colour. */
export const hIcon = style({
  position: "relative", width: "20px", height: "20px", display: "grid", placeItems: "center", color: vars.muted,
  background: vars.canvas,
  selectors: {
    // In a group's line pointed at: on its ground, as the line is.
    [`${hGroupHead}:hover > &`]: { background: `linear-gradient(${vars.hover}, ${vars.hover}), ${vars.canvas}` },
    [`${hEv}[data-state] > &`]: { background: "none", color: "inherit" },
    [`${hEv}[data-state="done"] > &`]: { color: vars.green },
    [`${hEv}[data-tone="accent"] > &`]: { color: vars.accent },
    [`${hEv}[data-tone="red"] > &`]: { color: vars.red },
  },
});
export const hEvBody = style({ minWidth: "0", display: "grid", gridTemplateColumns: "minmax(0, 1fr)" });
/** A state's words in a line: what it waited for and how long, or how the turn ended. */
export const hStateLine = style({
  display: "flex", alignItems: "center", gap: "6px", minHeight: "20px", fontSize: vars.textMeta, lineHeight: "20px",
});
export const hStateText = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** How much of the most it waits has gone: a thin bar under the words, its fill growing on the compositor. */
const waitFillKeyframes = keyframes({ from: { transform: "scaleX(0)" }, to: { transform: "scaleX(1)" } });
export const hWaitBar = style({
  display: "block", height: "3px", margin: "3px 0 2px", borderRadius: "999px", overflow: "hidden",
  background: `color-mix(in srgb, currentColor 18%, transparent)`,
});
globalStyle(`${hWaitBar} > i`, {
  display: "block", height: "100%", background: "currentColor", transformOrigin: "left", transform: "scaleX(0)",
  animationName: waitFillKeyframes, animationTimingFunction: "linear", animationFillMode: "forwards",
});
/** An event in a line (the agent's own words, still.fail's reminders, what a sub-agent answered): its lead, then its
 * words cut short; a button that opens them whole when there is more. */
export const hOne = style({
  display: "flex", alignItems: "center", gap: "6px", width: "100%", minWidth: "0", minHeight: "20px", padding: "0",
  margin: "0", border: "0", background: "none", font: "inherit", fontSize: vars.textMeta, lineHeight: "20px",
  color: vars.muted, textAlign: "left",
  selectors: {
    "button&": { cursor: "pointer" },
    "button&:hover": { color: vars.text },
    "&[data-failed=\"true\"]": { color: vars.red },
  },
});
globalStyle(`${hOne} strong`, { color: vars.text, fontWeight: "600", flex: "none" });
export const hOneText = style({ flex: "1", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const hOneFold = style({ marginLeft: "auto", flex: "none" });
/** What a one-line event says in whole, opened under its line. */
export const hOneBody = style({ minWidth: "0", padding: "2px 0 4px" });
/** The agent's own words, or a sub-agent's answer, opened: small and grey, as Markdown. */
export const hNote = style({ color: vars.muted });
globalStyle(`${hNote}${markdown}`, { fontSize: vars.textMeta, lineHeight: vars.leadingMeta });
/** still.fail's words, opened: small and grey, as they were written. */
export const hNotePlain = style({
  fontSize: vars.textMeta, lineHeight: vars.leadingMeta, color: vars.muted, whiteSpace: "pre-wrap", overflowWrap: "anywhere",
});
/** What kind of words a one-line event's are: "没发出", "子 agent". */
export const hTag = style({
  flex: "none", padding: "0 5px", borderRadius: "4px", cornerShape: vars.cornerShape,
  background: vars.neutralBg, fontSize: vars.textCaption, lineHeight: vars.leadingCaption,
});
/** "只看收发": pressed, in the ink of what it filters for. */
export const onlyIo = style({
  gap: "4px",
  selectors: {
    "&[aria-pressed=\"true\"]": { color: vars.text, background: vars.selected, borderRadius: vars.rField, cornerShape: vars.cornerShape },
  },
});
/** An item's link, copied from its top-right corner: shown while the item is pointed at (or the button focused). */
export const hPhaseText = style({ animation: `${fadeInKeyframes} 180ms ${vars.easeOut}` });
export const hStepSaid = style({
  minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", color: vars.text,
});
globalStyle(`${usage} dt`, { fontSize: vars.textMeta, color: vars.muted });
globalStyle(`${usage} dd`, {
  margin: "2px 0 0", fontSize: vars.textUi, fontWeight: "600", fontVariantNumeric: "tabular-nums",
});
globalStyle(`${historyBody} > *`, { minWidth: "0" });
globalStyle(`${hLabel} strong`, { color: vars.text, fontWeight: "600" });
globalStyle(`${hStep} summary`, {
  display: "flex", alignItems: "baseline", gap: "8px", padding: "5px 6px",
  borderRadius: `calc(8px * ${vars.cornerScale})`, listStyle: "none", cursor: "pointer", fontSize: vars.textMeta,
  cornerShape: vars.cornerShape,
});
globalStyle(`${hStep} summary::-webkit-details-marker`, { display: "none" });
globalStyle(`${hStep} summary:hover`, { background: vars.hover });
/** Here rather than with its class: it comes after .h-group-head > span:first-of-type, and wins over it. */
globalStyle(`${sessionPage} ${pageBarTitle} > :not(h1)`, { flex: "none" });
/** Here rather than with its class: it comes after .history-body > *, and wins over it. */
globalStyle(accountMenu, { minWidth: "260px" });
/** Here rather than with its class: it comes after .history-body > *, and wins over it. */
globalStyle(mineFilterBtn, {
  display: "inline-flex", alignItems: "center", justifyContent: "center", gap: "6px", flex: "none", height: "32px",
  minWidth: "32px", padding: "0 8px", border: "0", borderRadius: vars.rNav,
  cornerShape: vars.cornerShape, background: "none", color: vars.muted, font: "inherit", fontSize: vars.textUi,
  cursor: "pointer",
});
/** Here rather than with its class: it comes after .mine-filter-btn, and wins over it. */
globalStyle(mineFilterWide, { border: `1px solid ${vars.line}`, marginBottom: "12px" });
/** Here rather than with its class: it comes after .usage dd, and wins over it. */
globalStyle(`${detailRow} dd`, { margin: "0", minWidth: "0" });
globalStyle(`${historyDetails} + ${usage}`, { background: vars.list });
/** Details pack tight: two columns of short facts, small type. */
globalStyle(`${historyDetails} ${details}`, { gridTemplateColumns: "repeat(auto-fill, minmax(180px, 1fr))", gap: "4px 16px" });
globalStyle(`${historyDetails} ${detailRow}`, {
  gridTemplateColumns: "4.5em minmax(0, 1fr)", gap: "8px", fontSize: vars.textMeta, minHeight: "22px",
});
globalStyle(`${historyDetails} ${detailRow} dd`, { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${hPlace} > svg`, { flex: "none" });
/** In a chat message's head (Chat.tsx SentElsewhere): the place is what is cut short there, not what follows it. */
globalStyle(`${msgRoute} > ${hPlace}`, { overflow: "hidden" });
globalStyle(`${msgRoute} > ${hPlace} ~ *`, { flex: "none" });
globalStyle(`${historyDetails} ${details}`, { gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))" });
/** Here rather than with its class: it comes after .history-details .detail-row, and wins over it. */
globalStyle(`${msg}[data-held] > *`, { minHeight: "0", overflow: "hidden", visibility: "hidden" });
/** Here rather than with its class: it comes after .history-body > *, and wins over it. */
