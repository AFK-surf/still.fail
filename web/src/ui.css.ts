// The app's own marks and links among the shared parts (ui.tsx): what made an agent's model, a connect's kind, a time,
// the way back; and where the app's pages put @stillfail/ui's parts (its parts.css.ts, just before this in the cascade).
import { globalStyle, style } from "@vanilla-extract/css";
import { spokesBox, spokesTurn } from "@stillfail/ui/styles/spokes.ts";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { appearKeyframes } from "@stillfail/ui/styles/keyframes.css.ts";
import { outsetStart } from "@stillfail/ui/styles/align.ts";
import { DIALOG_INNER, DIALOG_PAD, dialogBody } from "@stillfail/ui/parts.css.ts";
import { pageBar } from "./styles/sidebar.css.ts";
import { markdown } from "./styles/conversation.css.ts";
import { card, listRow } from "./styles/pages.css.ts";
import { STILL, stillLoop } from "@stillfail/ui/styles/still.ts";

export const kindIcon = style({
  display: "inline-grid", placeItems: "center", width: "20px", height: "20px", flex: "none", color: vars.muted,
});
export const kindMark = style({ color: vars.text });
/** Centred on the line: aligned by baseline, the letter inside a small avatar would pull it down. */
/**
 * An agent: its model's maker on a tile; where it stands is a mark at the corner in the chat list's colours
 * (ChatMark.css.ts): yellow spokes stepping round at work, red when it wants someone (blocked, failed); no halo, the tile is
 * small. A gap of the ground (`--ring`: the page's, a panel's where it is in one) round it. The badge as a 20 one's has
 * it and no larger on a larger mark; on a smaller one all of it as much smaller (`--badge`, AgentMark's: a badge 12
 * across covered a 14 one's whole maker but a sliver).
 */
export const agentMark = style({
  position: "relative", display: "inline-grid", placeItems: "center", flex: "none", width: "var(--mark)",
  height: "var(--mark)", borderRadius: `calc(var(--mark) * .3 * ${vars.cornerScale})`, background: vars.neutralBg,
  cornerShape: vars.cornerShape,
  selectors: {
    "&[data-badge]::after": {
      content: "\"\"", position: "absolute", right: "calc(-3px * var(--badge))", bottom: "calc(-3px * var(--badge))",
      width: "calc(12px * var(--badge))", height: "calc(12px * var(--badge))", boxSizing: "border-box", borderRadius: "50%",
      border: `calc(2px * var(--badge)) solid var(--ring, ${vars.canvas})`, background: `var(--ring, ${vars.canvas})`,
    },
    "&[data-badge=\"block\"]::after, &[data-badge=\"failed\"]::after": { background: "#e5484d" },
    // At work: yellow spokes stepping round (spokes.ts), 10px, with no disc of the ground round them (it showed as a
    // dark rim, 2026-10-19).
    "&[data-badge=\"run\"]::after": { display: "none" },
    "&[data-badge=\"run\"]::before": {
      content: "\"\"", position: "absolute", right: "calc(-2px * var(--badge))", bottom: "calc(-2px * var(--badge))",
      width: "calc(10px * var(--badge))", height: "calc(10px * var(--badge))", zIndex: 1, ...spokesBox("#f2b01e"),
    },
    [`${STILL} &[data-badge="run"]::before`]: stillLoop(),
  },
});
spokesTurn(`${agentMark}[data-badge="run"]::before`);
/**
 * With the station it runs on: one tile, as tall, the maker's part square, the station's (its icon or its name) after it,
 * centred in its own part. The agent's badge stays on the maker's corner: the station's corner is the station's own.
 */
export const agentMarkJoined = style({
  display: "inline-flex", width: "auto", gap: "0", color: vars.muted, fontSize: vars.textMeta, lineHeight: "1", whiteSpace: "nowrap",
  selectors: {
    "&[data-badge]::after": { right: "auto", left: "calc(var(--mark) - 9px * var(--badge))" },
    "&[data-badge=\"run\"]::before": { right: "auto", left: "calc(var(--mark) - 8px * var(--badge))" },
  },
});
// Hover tints meet at straight edges inside the tile; only its two outside ends are rounded.
const joinedCorner = `calc(var(--mark) * .3 * ${vars.cornerScale})`;
globalStyle(`${agentMarkJoined} > *`, { borderRadius: "0", cornerShape: vars.cornerShape });
globalStyle(`${agentMarkJoined} > :first-child`, { borderStartStartRadius: joinedCorner, borderEndStartRadius: joinedCorner });
globalStyle(`${agentMarkJoined} > :last-child`, { borderStartEndRadius: joinedCorner, borderEndEndRadius: joinedCorner });
globalStyle(`${agentMarkJoined} > :last-child`, { paddingInline: "calc(var(--mark) * .19 + 1px)" });
export const mobileBack = style({
  display: "none", alignItems: "center", gap: "2px", color: vars.muted, fontSize: vars.textUi, lineHeight: "20px",
  "@media": {
    "(max-width: 700px)": {
      display: "inline-flex", marginBottom: "12px",
      selectors: {
        [`${pageBar} &`]: { margin: "0" },
      },
    },
  },
});
/** A detail page's way back, on every screen, above its header. */
export const pageBackRow = style({ display: "flex", alignItems: "center", height: "24px", marginBottom: "14px" });
export const pageBack = style({
  display: "inline-flex", alignItems: "center", gap: "2px", ...outsetStart(4), color: vars.muted,
  fontSize: vars.textUi, lineHeight: "20px", textDecoration: "none",
  selectors: {
    "&:hover": { color: vars.text },
  },
});
export const splashLabel = style({
  margin: "0", maxWidth: "32em", fontSize: vars.textUi, color: vars.muted,
  animation: `${appearKeyframes} 0s linear 1s both`,
  selectors: {
    "&[data-now]": { animation: "none" },
  },
});
/** Offered once a splash has stood too long: loading the page again, as an app on the home screen has no reload of its own. */
export const splashReload = style({
  display: "inline-flex", alignItems: "center", gap: "6px", height: "32px", padding: "0 14px", border: "0", borderRadius: "999px",
  background: `color-mix(in srgb, ${vars.text} 6%, transparent)`, color: vars.text, font: "inherit", fontSize: vars.textUi, cursor: "pointer",
  animation: `${appearKeyframes} 200ms ease-out both`,
});
export const runtimeLogo = style({ flex: "none", display: "block" });
export const modelLogo = style({
  flex: "none", display: "inline-block", verticalAlign: "-2px",
  selectors: {
    ":root[data-theme=\"dark\"] &[data-mono]": { filter: "invert(1)" },
  },
  "@media": {
    "(prefers-color-scheme: dark)": {
      selectors: {
        ":root:not([data-theme=\"light\"]) &[data-mono]": { filter: "invert(1)" },
      },
    },
  },
});
export const timeToggle = style({
  cursor: "pointer",
  selectors: {
    "&:hover": { textDecoration: "underline dotted", textUnderlineOffset: "2px" },
  },
});
/** A list's rows in a dialog reach 12 past its words (pages.css.ts listRow): their hover follows the dialog's curve too. */
globalStyle(`${dialogBody} ${listRow}`, { borderRadius: `calc(${DIALOG_PAD + 18 - 12}px * ${vars.cornerScale})` });
/** Cards in a dialog sit at its padding, as its choices and command lines do: their corners are the dialog's, less it. */
globalStyle(`${dialogBody} ${card}`, { borderRadius: DIALOG_INNER });
/** Here rather than with its class: it comes after .empty p, and wins over it. */
globalStyle(`${markdown} p`, { margin: "0 0 8px" });
/** Here rather than with its class: it comes after .empty h2, and wins over it. */
globalStyle(`${markdown} h2`, { fontSize: vars.textBody, margin: "14px 0 6px" });
/** Here rather than with its class: it comes after .command code, and wins over it. */
globalStyle(`${markdown} code`, {
  fontSize: vars.textMeta, padding: "1px 5px", borderRadius: `calc(6px * ${vars.cornerScale})`, background: vars.neutralBg,
  cornerShape: vars.cornerShape,
});
/** Inline completion mark, aligned with the state explanation's text. */
export const doneMark = style({ display: "inline-flex", width: 14, height: 14, verticalAlign: "-2px", alignItems: "center", justifyContent: "center" });

