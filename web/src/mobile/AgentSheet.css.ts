// An agent in brief on the phone (AgentSheet.tsx): its sheet over the chat, and the same parts on its history's details.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

export const mAgent = style({ display: "flex", flexDirection: "column", padding: "0 18px 24px" });
export const mAgentHead = style({ display: "flex", alignItems: "center", gap: "12px", minWidth: "0", paddingTop: "4px" });
export const mAgentNames = style({ flex: "1", minWidth: "0", display: "flex", flexDirection: "column", gap: "1px" });
export const mAgentName = style({
  fontSize: vars.textTitle, fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
/** Where it stands, after a dot in its tone, and for how long; two lines at most (a need or a failure can be long). */
export const mAgentStatus = style({
  position: "relative", margin: "0", paddingLeft: "12px", fontSize: vars.textMeta, overflowWrap: "anywhere",
  display: "-webkit-box", WebkitLineClamp: "2", WebkitBoxOrient: "vertical", overflow: "hidden",
  vars: { "--dot": "var(--m-subtle)" },
  selectors: {
    "&::before": { content: '""', position: "absolute", left: "0", top: "calc(0.7em - 3px)", width: "6px", height: "6px", borderRadius: "50%", background: "var(--dot)" },
    '&[data-tone="accent"]': { vars: { "--dot": "var(--m-accent)" } },
    '&[data-tone="green"]': { vars: { "--dot": "var(--m-green)" } },
    '&[data-tone="blue"]': { vars: { "--dot": "var(--m-blue)" } },
    '&[data-tone="red"]': { vars: { "--dot": "var(--m-red)" } },
    '&[data-tone="amber"]': { vars: { "--dot": "var(--m-warn)" } },
  },
});
export const mAgentElapsed = style({ color: "var(--m-muted)", fontVariantNumeric: "tabular-nums" });
/** Stopping its turn, while it works. */
export const mAgentStop = style({
  flex: "none", display: "inline-flex", alignItems: "center", gap: "6px", height: "32px", padding: "0 14px", border: "0",
  borderRadius: "16px", background: "color-mix(in srgb, var(--m-red) 14%, transparent)", color: "var(--m-red) !important",
  fontSize: `${vars.textMeta} !important`, fontWeight: "500", cursor: "pointer",
  selectors: { "&:disabled": { opacity: ".6", cursor: "default" } },
});
/** Its latest lines, a line each, oldest first: what it does now in the ink. */
export const mAgentLines = style({
  listStyle: "none", margin: "12px 0 0", padding: "0", display: "flex", flexDirection: "column", gap: "3px",
  fontSize: vars.textMeta, color: "var(--m-muted)",
});
globalStyle(`${mAgentLines} > li`, { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${mAgentLines} > li[data-now]`, { color: "var(--m-ink)" });
/** The figures that say most, each large over its name, side by side: in the ink, but one worth a look in its level's colour. */
export const mAgentTiles = style({ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(0, 1fr))", gap: "8px", marginTop: "14px" });
export const mAgentTile = style({
  display: "flex", flexDirection: "column", minWidth: "0", padding: "9px 12px 8px", borderRadius: "14px",
  background: "color-mix(in srgb, var(--m-ink) 5%, transparent)",
});
globalStyle(`${mAgentTile} b`, { fontSize: vars.textHeading, lineHeight: vars.leadingHeading, fontWeight: "600", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" });
// A long one (a cost in the hundreds, a context whose window is not known) a size down, so it is not cut short.
globalStyle(`${mAgentTile}[data-long] b`, { fontSize: vars.textTitle });
globalStyle(`${mAgentTile} small`, { fontSize: vars.textCaption, color: "var(--m-muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${mAgentTile}[data-level=amber] b`, { color: "var(--m-warn)" });
globalStyle(`${mAgentTile}[data-level=red] b`, { color: "var(--m-red)" });
/** What is wrong, a line each in its level's colour. */
export const mAgentNotes = style({ display: "flex", flexDirection: "column", gap: "2px", marginTop: "10px", fontSize: vars.textMeta });
globalStyle(`${mAgentNotes} > span[data-level=amber]`, { color: "var(--m-warn)" });
globalStyle(`${mAgentNotes} > span[data-level=red]`, { color: "var(--m-red)" });
/** Where its rows lead: its account, its history, its jobs. */
export const mAgentRows = style({ marginTop: "12px" });
export const mAgentRowLabel = style({ flex: "none", color: "var(--m-muted)" });
export const mAgentRowValue = style({ flex: "1", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
