// An agent in brief, over its avatar (AgentCard.tsx), in the hover cards' language (Hover.css.ts).
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

export const agentCard = style({ display: "flex", flexDirection: "column", gap: "8px", minWidth: "0", width: "288px", maxWidth: "100%" });
export const head = style({ display: "flex", alignItems: "center", gap: "10px", minWidth: "0" });
export const name = style({ fontWeight: "500", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });

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

export const elapsed = style({ color: vars.muted, fontVariantNumeric: "tabular-nums" });

/** The cost to the right of its name. */
export const headCost = style({ marginLeft: "auto", paddingLeft: "12px", fontWeight: "500", fontVariantNumeric: "tabular-nums" });

/** The figures that say most, each large over its name, side by side. */
export const tiles = style({ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(0, 1fr))", gap: "6px" });
export const tile = style({
  display: "flex", flexDirection: "column", gap: "1px", minWidth: "0", padding: "7px 9px", borderRadius: "8px", background: vars.hover,
});
globalStyle(`${tile}[data-level=amber] b`, { color: vars.amber });
globalStyle(`${tile}[data-level=red] b`, { color: vars.red });
globalStyle(`${tile} b`, { fontSize: vars.textTitle, lineHeight: vars.leadingTitle, fontWeight: "600", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" });
globalStyle(`${tile} small`, { fontSize: vars.textCaption, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });

/** The account it runs on, what is left of it to its right. */
export const account = style({ display: "flex", alignItems: "center", gap: "8px", minWidth: "0", fontSize: vars.textMeta });
export const accountName = style({ flex: "1 1 auto", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", color: vars.muted });
export const chips = style({ display: "inline-flex", gap: "4px", flex: "none" });

/** Rings in a row, each its name under it. */
export const rings = style({ display: "flex", gap: "14px", flexWrap: "wrap" });
export const ringCell = style({ display: "flex", flexDirection: "column", alignItems: "center", gap: "2px" });
globalStyle(`${ringCell} small`, { fontSize: vars.textCaption, color: vars.muted, whiteSpace: "nowrap" });

/** A bar each: its name, how full, the figure. */
export const bars = style({ display: "grid", gridTemplateColumns: "auto minmax(72px, 1fr) auto", columnGap: "10px", rowGap: "5px", alignItems: "center", fontSize: vars.textMeta });
export const bar = style({ display: "contents" });
export const barLabel = style({ color: vars.muted, whiteSpace: "nowrap" });
export const barTrack = style({ height: "4px", borderRadius: "999px", background: vars.line, overflow: "hidden" });
globalStyle(`${barTrack} i`, { display: "block", height: "100%", borderRadius: "inherit", background: vars.muted });
globalStyle(`${bar}[data-level=amber] ${barTrack} i`, { background: vars.amber });
globalStyle(`${bar}[data-level=red] ${barTrack} i`, { background: vars.red });
export const barText = style({ textAlign: "right", whiteSpace: "nowrap", fontVariantNumeric: "tabular-nums", selectors: { [`${bar}[data-level=amber] &`]: { color: vars.amber }, [`${bar}[data-level=red] &`]: { color: vars.red } } });

/** What is left: a quiet line. */
export const quiet = style({ margin: "0", fontSize: vars.textMeta, color: vars.muted, overflowWrap: "anywhere" });
/** Its jobs, and what is wrong in its level's colour. */
export const notes = style({ display: "flex", flexDirection: "column", gap: "2px", fontSize: vars.textMeta, color: vars.muted });
globalStyle(`${notes} > span`, { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${notes} > span[data-level=amber]`, { color: vars.amber });
globalStyle(`${notes} > span[data-level=red]`, { color: vars.red });
