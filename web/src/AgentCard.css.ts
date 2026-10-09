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

/** The rest: a quiet line. */
export const quiet = style({ margin: "0", fontSize: vars.textMeta, color: vars.muted, overflowWrap: "anywhere" });
/** Its jobs, and what is wrong in its level's colour. */
export const notes = style({ display: "flex", flexDirection: "column", gap: "2px", fontSize: vars.textMeta, color: vars.muted });
globalStyle(`${notes} > span`, { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${notes} > span[data-level=amber]`, { color: vars.amber });
globalStyle(`${notes} > span[data-level=red]`, { color: vars.red });
