// Markdown's own parts.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { markdown } from "./styles/conversation.css.ts";

/** A message's file placed in its text: on a line of its own, a little apart from the text around it. */
export const inlineFile = style({ display: "flex", margin: "8px 0" });
globalStyle(`${inlineFile}:first-child`, { marginTop: 0 });
globalStyle(`${inlineFile}:last-child`, { marginBottom: 0 });

/** A link within a sentence to one of the message's files: looks like any link, opens the file. */
export const fileLink = style({
  display: "inline", padding: 0, border: 0, background: "none", font: "inherit", color: vars.blue, cursor: "pointer", textAlign: "inherit",
});

/** A message the agent sent: a plain card so its content (code, tables, chips) keeps its own colours. */
/** Code blocks: a quiet frame, the language and a copy button above, highlighting in the page's own tones. */
/** Code: a quiet tinted block, no frame; language and copy sit in the corner and come forward on hover. */
export const codeBlock = style({
  position: "relative", margin: "0 0 8px", border: "0", borderRadius: `calc(12px * ${vars.cornerScale})`,
  background: `color-mix(in oklch, ${vars.text} 4%, ${vars.canvas})`, overflow: "hidden",
  cornerShape: vars.cornerShape,
});
export const codeBar = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", borderBottom: `1px solid ${vars.line}`,
  position: "absolute", top: "4px", right: "4px", height: "24px", padding: "0", border: "0", gap: "2px",
  opacity: ".55", transition: `opacity ${vars.dur} ${vars.easeOut}`,
  selectors: {
    [`${codeBlock}:hover &`]: { opacity: "1" },
    "&:focus-within": { opacity: "1" },
  },
});
export const codeLang = style({
  padding: "0 6px", fontFamily: "var(--font-sans, inherit)", fontSize: "10px", letterSpacing: ".02em",
  color: vars.subtle,
});
export const codeCopy = style({
  display: "inline-flex", alignItems: "center", gap: "4px", border: "0",
  borderRadius: `calc(6px * ${vars.cornerScale})`, color: vars.muted, cursor: "pointer", cornerShape: vars.cornerShape,
  height: "24px", padding: "0 7px", fontSize: "11px",
  background: `color-mix(in srgb, ${vars.canvas} 80%, transparent)`,
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
  },
});
export const codeShiki = style({});
globalStyle(`${markdown} ${codeBlock} pre`, {
  margin: "0", padding: "10px 12px", borderRadius: "0", background: "none", fontSize: "12px", lineHeight: "1.55",
});
globalStyle(`${codeShiki} pre.shiki`, {
  margin: "0", padding: "10px 12px", background: "none !important", overflow: "auto", fontSize: "12px",
  lineHeight: "1.55",
});
globalStyle(`${codeShiki} pre.shiki code`, { fontFamily: vars.fontMono, padding: "0", background: "none" });
globalStyle(`${markdown} ${codeBlock} pre, ${codeShiki} pre.shiki`, { padding: "12px 14px", fontSize: "12.5px", lineHeight: "1.6" });
