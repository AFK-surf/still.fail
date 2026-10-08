// An agent in brief, over its avatar (AgentCard.tsx), in the hover cards' language (Hover.css.ts).
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

export const agentCard = style({ display: "flex", flexDirection: "column", gap: "8px", minWidth: "0", maxWidth: "300px" });
export const head = style({ display: "flex", alignItems: "center", gap: "10px", minWidth: "0" });
export const who = style({ display: "flex", flexDirection: "column", minWidth: "0" });
export const name = style({ fontWeight: "500", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const sub = style({ fontSize: vars.textMeta, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });

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
export const quota = style({
  selectors: { "&[data-level=amber]": { color: vars.amber }, "&[data-level=red]": { color: vars.red } },
});

/** A few facts, a line each, quiet. */
export const lines = style({ display: "flex", flexDirection: "column", gap: "2px", minWidth: "0", fontSize: vars.textMeta, color: vars.muted });
globalStyle(`${lines} > span`, { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** What is worth a look, in its level's colour. */
export const attention = style({
  selectors: { "&[data-level=amber]": { color: vars.amber }, "&[data-level=red]": { color: vars.red } },
});
