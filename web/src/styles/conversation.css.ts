import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";

export const pageBarTitle = style({
  gridColumn: "2", display: "flex", alignItems: "center", gap: "8px", minWidth: "0", lineHeight: "22px",
  "@media": {
    "(max-width: 700px)": {
      gridColumn: "2", justifyContent: "center",
    },
  },
});
export const msg = style({ display: "grid", gap: "6px", fontSize: vars.textSecondary, lineHeight: "1.65", minWidth: "0" });
export const msgBubble = style({
  maxWidth: "min(78%, 640px)", padding: "10px 16px", borderRadius: `calc(20px * ${vars.cornerScale})`,
  background: vars.neutralBg, whiteSpace: "pre-wrap", overflowWrap: "anywhere", cornerShape: vars.cornerShape,
});
export const msgHead = style({ display: "flex", minHeight: "24px", alignItems: ["baseline", "center"], gap: "6px" });
export const msgTime = style({ fontSize: vars.textMicro, color: vars.muted });
/** "At work", as the agent badge says it: a still hollow ring. */
export const activityPulse = style({
  width: "8px", height: "8px", boxSizing: "border-box", borderRadius: "50%", border: `2px solid ${vars.accent}`,
  flex: "none",
});
export const markdown = style({ fontSize: vars.textSecondary, lineHeight: "1.65", overflowWrap: "anywhere", minWidth: "0" });
globalStyle(`${pageBarTitle} h1`, {
  margin: "0", fontSize: vars.textBody, fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis",
  whiteSpace: "nowrap", maxWidth: "42vw",
});
globalStyle(`${markdown} > :first-child`, { marginTop: "0" });
globalStyle(`${markdown} > :last-child`, { marginBottom: "0" });
globalStyle(`${markdown} ul, ${markdown} ol, ${markdown} pre, ${markdown} table, ${markdown} blockquote`, { margin: "0 0 8px" });
globalStyle(`${markdown} ul, ${markdown} ol`, { paddingLeft: "20px" });
globalStyle(`${markdown} h1, ${markdown} h3, ${markdown} h4`, { fontSize: vars.textBody, margin: "14px 0 6px" });
globalStyle(`${markdown} pre`, {
  maxWidth: "100%", padding: "10px 12px", borderRadius: `calc(12px * ${vars.cornerScale})`, background: vars.paper,
  overflow: "auto", cornerShape: vars.cornerShape,
});
globalStyle(`${markdown} pre code`, { padding: "0", background: "none" });
globalStyle(`${markdown} a`, { color: vars.blue });
globalStyle(`${markdown} table`, { borderCollapse: "collapse", fontSize: vars.textSecondary, fontVariantNumeric: "tabular-nums" });
globalStyle(`${markdown} th, ${markdown} td`, { borderBottom: `1px solid ${vars.line}`, padding: "7px 12px", textAlign: "left" });
globalStyle(`${markdown} th`, {
  fontSize: vars.textLabel, fontWeight: "500", color: vars.muted, background: `color-mix(in srgb, ${vars.text} 4%, ${vars.canvas})`,
});
globalStyle(`${markdown} tr:last-child td`, { borderBottom: "0" });
globalStyle(`${markdown} blockquote`, { paddingLeft: "10px", borderLeft: `2px solid ${vars.lineStrong}`, color: vars.muted });
globalStyle(`${pageBarTitle} h1`, {
  "@media": {
    "(max-width: 700px)": {
      maxWidth: "none",
    },
  },
});
globalStyle(`${markdown} pre code`, { fontFamily: vars.fontMono });
/**
 * Waiting its turn, a message takes no room (not even the list's gap), and what it holds does not reach past it (the
 * list's height is only what shows). Coming out, it takes its whole place at once and what it says unrolls from its
 * avatar's corner, drawn by the compositor alone: however long, nothing is laid out again while it moves.
 */
/** Here rather than with its class: it comes after .markdown > :first-child, and wins over it. */
globalStyle(`${msg}[data-held]`, {
  display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gridTemplateRows: "0fr", marginTop: "calc(-1 * var(--list-gap, 28px))",
  overflow: "hidden",
});
/** Inline code as Zork has it: no box, the code face in its own colour. */
globalStyle(`${markdown} :not(pre) > code`, {
  padding: "0", borderRadius: "0", background: "none", fontFamily: vars.fontMono, fontSize: ".9em",
  color: vars.codeInline,
});
/** A web address written as code is still a link: the link's colour, not the code's. */
globalStyle(`${markdown} a > code`, { color: "inherit" });
