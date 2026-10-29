// An agent in brief, over its avatar (AgentCard.tsx), in the hover cards' language (Hover.css.ts).
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { litOver } from "@stillfail/ui/styles/lit.ts";
import { spokesBox, spokesTurn } from "@stillfail/ui/styles/spokes.ts";

export const agentCard = style({ display: "flex", flexDirection: "column", gap: "8px", minWidth: "0", width: "288px", maxWidth: "100%" });
export const head = style({ display: "flex", alignItems: "center", gap: "10px", minWidth: "0" });
export const name = style({ flex: "1 1 auto", minWidth: "0", fontWeight: "500", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** Stopping its turn, for it alone, while it works. */
export const stop = style({
  flex: "none", display: "inline-flex", alignItems: "center", gap: "5px", height: "24px", padding: "0 10px", border: "0", borderRadius: "999px",
  background: vars.redBg, color: vars.red, font: "inherit", fontSize: vars.textMeta, fontWeight: "500", cursor: "pointer",
  selectors: { "&:hover": litOver },
});

/** Where it stands, in words, after a dot in its tone; three lines at most (a need or a failure can be long). */
export const status = style({
  margin: "0", paddingLeft: "14px", position: "relative", overflowWrap: "anywhere",
  display: "-webkit-box", WebkitLineClamp: "3", WebkitBoxOrient: "vertical", overflow: "hidden",
  vars: { "--dot": vars.subtle },
  selectors: {
    "&::before": { content: '""', position: "absolute", left: "2px", top: "calc(0.725em - 3px)", width: "6px", height: "6px", borderRadius: "50%", background: "var(--dot)" },
    '&[data-tone="accent"]': { vars: { "--dot": vars.accent } },
    '&[data-tone="green"]': { vars: { "--dot": vars.green } },
    '&[data-tone="blue"]': { vars: { "--dot": vars.blue } },
    '&[data-tone="red"]': { vars: { "--dot": vars.red } },
    '&[data-tone="amber"]': { vars: { "--dot": vars.amber } },
  },
});

/** Its latest lines, a line each, oldest first; what it does now in the text's colour. */
export const recent = style({
  listStyle: "none", margin: "0", padding: "0 0 0 14px", display: "flex", flexDirection: "column", gap: "2px",
  fontSize: vars.textMeta, color: vars.muted,
  // Its lines run on in it (AgentCard.tsx useLinesMotion): their offset parent, none drawn past its edges.
  position: "relative", overflow: "hidden",
});
// A line moves whole, on a layer of its own: its letters are drawn once.
globalStyle(`${recent} > li`, { flex: "none", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", willChange: "transform" });
globalStyle(`${recent} > li[data-now]`, { color: vars.text });

export const elapsed = style({ color: vars.muted, fontVariantNumeric: "tabular-nums" });

/** The figures that say most, each large over its name, side by side. */
export const tiles = style({ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(0, 1fr))", gap: "6px" });
export const tile = style({
  display: "flex", flexDirection: "column", gap: "1px", minWidth: "0", padding: "7px 9px",
  borderRadius: `calc(8px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: vars.hover,
});
/** Its context's tile when something can be done to it: pressed as a button is, its name ending in ›. */
export const tileButton = style({
  border: "0", textAlign: "left", font: "inherit", cursor: "pointer",
  selectors: { "&:hover, &[data-state=open]": litOver },
});
export const tileName = style({ display: "flex", alignItems: "center", gap: "2px", minWidth: "0" });
globalStyle(`${tileName} > span`, { minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${tileName} > svg`, { flex: "none" });
globalStyle(`${tile}[data-level=amber] b`, { color: vars.amber });
globalStyle(`${tile}[data-level=red] b`, { color: vars.red });
globalStyle(`${tile} b`, { color: vars.text, fontSize: vars.textTitle, lineHeight: vars.leadingTitle, fontWeight: "600", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" });
globalStyle(`${tile} small`, { fontSize: vars.textCaption, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });

/** The account it runs on, what is left of it to its right. */
export const account = style({ display: "flex", alignItems: "center", gap: "8px", minWidth: "0", fontSize: vars.textMeta });
export const accountName = style({ flex: "1 1 auto", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", color: vars.muted });
export const chips = style({ display: "inline-flex", gap: "4px", flex: "none" });

/** The rest: a quiet line. */
export const quiet = style({ margin: "0", fontSize: vars.textMeta, color: vars.muted, overflowWrap: "anywhere" });
/** Its jobs, and what is wrong in its level's colour. */
export const notes = style({ display: "flex", flexDirection: "column", gap: "2px", fontSize: vars.textMeta, color: vars.muted });
globalStyle(`${notes} > span`, { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${notes} > span[data-level=amber]`, { color: vars.amber });
globalStyle(`${notes} > span[data-level=red]`, { color: vars.red });

/**
 * Its work past its turns in one line (WorkLine): as small and quiet as its latest lines, cut at its end, never
 * wrapped; pressed, it leads on (its history, or all of it unfolded), in the text's colour under the pointer.
 */
/**
 * The mark of its work at the end of its history's details' quiet line (WorkMark): the line's words, pressable, in the
 * link's ink under the pointer; as tall as the line (no padding of its own).
 */
export const workMark = style({
  display: "inline-flex", alignItems: "center", gap: "3px", border: "0", background: "none", padding: "0", margin: "0",
  font: "inherit", lineHeight: "inherit", color: "inherit", whiteSpace: "nowrap", cursor: "pointer",
  selectors: { "&:hover, &[data-state=open]": { color: vars.accentText } },
});
export const workMarkLead = style({ whiteSpace: "pre" });
/** At work's spokes before it while something runs in the background: the chats' marks' yellow, 10 on a line of 12. */
export const workSpokes = style({ flex: "none", width: 10, height: 10, ...spokesBox("#f2b01e") });
spokesTurn(workSpokes);
export const workMarkWrap = style({ position: "relative", display: "inline-flex", alignItems: "baseline", flex: "none" });
export const workMarkMeasure = style({ position: "absolute", top: "0", left: "0", visibility: "hidden", pointerEvents: "none", display: "flex", width: "max-content" });
/** The quiet line it ends: one line, its own words cut at their end only once the mark has given way. */
export const workQuiet = style({ display: "flex", alignItems: "baseline", minWidth: "0", whiteSpace: "nowrap" });
export const workQuietText = style({ flex: "0 1 auto", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis" });
/** Its popover: a small panel of words (panelCard), as wide as an agent's card is. */
export const workPop = style({ width: "320px", maxWidth: "calc(100vw - 16px)", maxHeight: "min(520px, calc(100vh - 80px))", overflowY: "auto" });
export const workLine = style({
  display: "flex", alignItems: "center", gap: "4px", minWidth: "0", maxWidth: "100%", margin: "0", padding: "0 0 0 14px",
  fontSize: vars.textMeta, color: vars.muted,
});
export const workLineButton = style({
  border: "0", background: "none", font: "inherit", fontSize: vars.textMeta, color: vars.muted, textAlign: "left", cursor: "pointer",
  selectors: { "&:hover": { color: vars.text } },
});
export const workLineText = style({ flex: "0 1 auto", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/**
 * What it has going in the background and its checklist (AgentWork), a small panel's groups: each under its small head
 * (12, muted, how many quieter after it), a line between them, 10 over and under it.
 */
export const work = style({ display: "flex", flexDirection: "column", gap: "10px", minWidth: "0" });
export const workPart = style({ display: "flex", flexDirection: "column", gap: "4px", minWidth: "0" });
globalStyle(`${workPart} + ${workPart}`, { borderTop: `1px solid ${vars.line}`, paddingTop: "10px" });
export const workHead = style({ display: "flex", alignItems: "baseline", gap: "6px", margin: "0", fontSize: vars.textMeta, fontWeight: "500", color: vars.muted });
export const workCount = style({ fontWeight: "400", color: vars.subtle, fontVariantNumeric: "tabular-nums" });
/** A task a row, 28 high: its kind's chip in a column of its own, what it is (cut at its end), for how long at its end. */
export const tasks = style({ listStyle: "none", margin: "0", padding: "0", display: "flex", flexDirection: "column", fontSize: vars.textMeta });
globalStyle(`${tasks} > li`, { display: "flex", alignItems: "center", gap: "8px", minWidth: "0", height: "28px" });
globalStyle(`${tasks} > li > :last-child`, { flex: "none", textAlign: "right" });
export const taskKind = style({
  flex: "none", width: "48px", boxSizing: "border-box", textAlign: "center", padding: "1px 6px", borderRadius: "999px",
  background: vars.hover, color: vars.muted, fontSize: vars.textCaption, whiteSpace: "nowrap",
});
/** The checklist on the tasks' line: its plan list without its own inset. */
export const workPlan = style({});
globalStyle(`${workPlan} ul`, { padding: "0" });
export const taskText = style({ flex: "1 1 auto", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
