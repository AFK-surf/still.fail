// A tool call drawn by what it is (ToolStep.tsx).
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { codeBar, codeLang } from "./Prose.css.ts";

const box = {
  margin: "0", padding: "8px 12px", borderRadius: `calc(10px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: `color-mix(in oklch, ${vars.text} 4%, ${vars.canvas})`,
  font: `12px/1.55 ${vars.fontMono}`, whiteSpace: "pre-wrap", overflowWrap: "anywhere", maxHeight: "360px", overflow: "auto",
} as const;

/** Highlighted code (a command, a file written, a file read), as markdown shows it but capped in height. */
export const block = style({ minWidth: "0" });
globalStyle(`${block} > *`, { margin: "0", maxHeight: "360px", overflow: "auto" });
/** Its copy button comes only on hover (it would sit on the first line of a command), without the language. */
globalStyle(`${block} ${codeBar}`, { opacity: "0" });
globalStyle(`${block}:hover ${codeBar}, ${block} ${codeBar}:focus-within`, { opacity: "1" });
globalStyle(`${block} ${codeLang}`, { display: "none" });
globalStyle(`${block} pre`, { padding: "8px 12px !important", fontSize: "12px !important", lineHeight: "1.55 !important", whiteSpace: "pre-wrap", overflowWrap: "anywhere" });

export const prose = style({
  ...box, font: "inherit", fontSize: vars.textXs, lineHeight: "1.6", whiteSpace: "normal", padding: "8px 12px",
});
globalStyle(`${prose} > :first-child`, { marginTop: "0" });
globalStyle(`${prose} > :last-child`, { marginBottom: "0" });

export const facts = style({ display: "flex", flexWrap: "wrap", gap: "4px 10px", fontSize: "11px", color: vars.subtle, padding: "0 2px" });
export const fact = style({});
globalStyle(`${fact} b`, { fontWeight: "500", color: vars.muted, fontFamily: vars.fontMono });

export const path = style({
  display: "flex", alignItems: "baseline", gap: "8px", minWidth: "0", padding: "0 2px",
  font: `12px/1.5 ${vars.fontMono}`, color: vars.text, overflowWrap: "anywhere",
});
export const pathExtra = style({ flex: "none", fontFamily: vars.fontBody, fontSize: "11px", color: vars.subtle });

export const lead = style({ padding: "0 2px", font: `12px/1.5 ${vars.fontMono}`, color: vars.text, overflowWrap: "anywhere" });

export const diff = style({ ...box, padding: "6px 0", whiteSpace: "normal" });
export const diffLine = style({
  padding: "0 12px 0 22px", whiteSpace: "pre-wrap", position: "relative", color: vars.muted,
  selectors: {
    "&::before": { position: "absolute", left: "9px", content: "''", color: vars.subtle },
    "&[data-mark=\"-\"]": { background: vars.redBg, color: vars.text },
    "&[data-mark=\"-\"]::before": { content: "'-'", color: vars.red },
    "&[data-mark=\"+\"]": { background: vars.greenBg, color: vars.text },
    "&[data-mark=\"+\"]::before": { content: "'+'", color: vars.green },
    "&[data-mark=\"@\"]": { color: vars.blue, fontWeight: "500", marginTop: "4px" },
  },
});

export const plan = style({ display: "grid", gap: "2px", margin: "0", padding: "0 2px", listStyle: "none", fontSize: vars.textXs });
export const planMark = style({ display: "inline-block", width: "16px", color: vars.subtle });
globalStyle(`${plan} li[data-status="completed"]`, { color: vars.muted, textDecoration: "line-through", textDecorationColor: vars.subtle });
globalStyle(`${plan} li[data-status="completed"] ${planMark}`, { color: vars.green, textDecoration: "none" });
globalStyle(`${plan} li[data-status="in_progress"]`, { fontWeight: "600" });
globalStyle(`${plan} li[data-status="in_progress"] ${planMark}`, { color: vars.accent });

export const fields = style({ display: "grid", gap: "4px", margin: "0", padding: "0 2px", fontSize: vars.textXs });
export const field = style({ display: "grid", gridTemplateColumns: "minmax(64px, max-content) minmax(0, 1fr)", gap: "12px", alignItems: "baseline" });
globalStyle(`${field} dt`, { color: vars.subtle, fontSize: "11px" });
globalStyle(`${field} dd`, { margin: "0", minWidth: "0" });
export const value = style({ fontFamily: vars.fontMono, fontSize: "12px", overflowWrap: "anywhere" });
export const long = style({ ...box, fontFamily: vars.fontBody, fontSize: vars.textXs, lineHeight: "1.6", maxHeight: "240px" });
export const json = style({ ...box, maxHeight: "240px" });

/** What came back: a little apart from the call. */
export const result = style({ display: "grid", gap: "4px", minWidth: "0" });
export const output = style({
  ...box, color: vars.muted,
  selectors: {
    [`${result}[data-failed] &`]: { background: vars.redBg, color: vars.text },
  },
});
export const none = style({ padding: "0 2px", fontSize: "11px", color: vars.subtle });

/** A step opened: the call, then what came back. */
export const body = style({ display: "grid", gap: "8px", minWidth: "0", padding: "4px 6px 10px 6px" });
export const section = style({ display: "grid", gap: "6px", minWidth: "0" });
