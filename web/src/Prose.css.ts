// Markdown's own parts.
import { globalStyle, style, styleVariants } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { markdown } from "./styles/conversation.css.ts";

/** A message's file placed in its text: on a line of its own, a little apart from the text around it. */
export const inlineFile = style({ display: "flex", margin: "8px 0" });
globalStyle(`${inlineFile}:first-child`, { marginTop: 0 });
globalStyle(`${inlineFile}:last-child`, { marginBottom: 0 });
/** Images written in one paragraph: in a row, wrapping onto the next when the row is full. */
export const inlineFiles = style([inlineFile, { flexWrap: "wrap", gap: "8px" }]);
export const inlineFilesItem = style({ display: "block", minWidth: 0 });
/** The image takes its place in the row, whatever size its own box would be. */
globalStyle(`${inlineFilesItem} > button`, { width: "100% !important", height: "auto !important", aspectRatio: "var(--ratio) !important" });

/** A link within a sentence to one of the message's files: looks like any link, opens the file. */
export const fileLink = style({
  display: "inline", padding: 0, border: 0, background: "none", font: "inherit", color: vars.blue, cursor: "pointer", textAlign: "inherit",
});

/** A web address in what a person wrote (withBareLinks): a link as one in markdown is. */
export const bareLink = style({ color: vars.blue });

/** A message the agent sent: a plain card so its content (code, tables, chips) keeps its own colours. */
/** Code blocks: a quiet frame, the language and a copy button above, highlighting in the page's own tones. */
/** Code: a quiet tinted block, no frame; language and copy sit in the corner and come forward on hover. */
export const codeBlock = style({
  position: "relative", margin: "0 0 8px", border: "0", borderRadius: `calc(12px * ${vars.cornerScale})`,
  background: `color-mix(in srgb, ${vars.text} 4%, ${vars.canvas})`, overflow: "hidden",
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
  "@media": {
    // A finger has no hover to bring the corner forward: the language and copy get a row of their own, over the code.
    "(pointer: coarse)": { position: "static", justifyContent: "flex-end", padding: "4px 4px 0", opacity: "1" },
  },
});
export const codeLang = style({
  padding: "0 6px", fontFamily: "var(--font-sans, inherit)", fontSize: vars.textCaption, letterSpacing: ".02em",
  color: vars.subtle,
});
export const codeCopy = style({
  // In the block's top right corner, 4 in (codeBar): rounded as the block less that, concentric with it.
  display: "inline-flex", alignItems: "center", gap: "4px", border: "0",
  borderRadius: `calc(12px * ${vars.cornerScale} - 4px)`, color: vars.muted, cursor: "pointer", cornerShape: vars.cornerShape,
  height: "24px", padding: "0 7px", fontSize: vars.textCaption,
  background: `color-mix(in srgb, ${vars.canvas} 80%, transparent)`,
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
  },
});
/**
 * A table in its own sideways scroll: the message's `overflow-wrap: anywhere` would else break its cells' words to fit.
 * Framed as a card (its corners, a faint ground), the rows ruled between them only.
 */
export const tableScroll = style({
  width: "fit-content", maxWidth: "100%", overflowX: "auto", margin: "0 0 8px", border: `1px solid ${vars.line}`,
  borderRadius: vars.rCard, cornerShape: vars.cornerShape, background: `color-mix(in srgb, ${vars.text} 2%, ${vars.canvas})`,
});
globalStyle(`${tableScroll}:last-child`, { marginBottom: "0" });
globalStyle(`${tableScroll} > table`, { margin: "0" });
globalStyle(`${tableScroll} th, ${tableScroll} td`, { overflowWrap: "normal", minWidth: "4em" });
globalStyle(`${markdown} ${codeBlock} pre`, {
  margin: "0", padding: "10px 12px", borderRadius: "0", background: "none", fontSize: vars.textMeta, lineHeight: "1.55",
});
/** Code's colours by what each piece is (the letters of the core's `ink`, client/core-ts/src/highlight.ts SCOPES):
 * vitesse-light's, and vitesse-dark's on a dark page, as Shiki gave them. */
const INK: Record<string, [light: string, dark: string]> = {
  a: ["#393A34", "#DBD7CAEE"], // text
  b: ["#A0ADA0", "#758575DD"], // comment
  c: ["#999999", "#666666"], // punctuation
  d: ["#B56959", "#C98A7D"], // string
  e: ["#B5695977", "#C98A7D77"], // a string's quotes
  f: ["#2F798A", "#4C9A91"], // number
  g: ["#1E754F", "#4D9375"], // keyword, constant.language, a tag
  h: ["#AB5959", "#CB7676"], // storage, keyword.operator, null
  i: ["#59873A", "#80A665"], // function
  j: ["#B07D48", "#BD976A"], // variable
  k: ["#A65E2B", "#C99076"], // constant, this, an option
  l: ["#2E8F82", "#5DA994"], // type
  m: ["#998418", "#B8A965"], // property, support
  n: ["#99841877", "#B8A96577"], // a property's quotes
  o: ["#22863A", "#85E89D"], // a diff's line added
  p: ["#B31D28", "#FDAEB7"], // a diff's line removed
  q: ["#6F42C1", "#B392F0"], // a hunk's range
};
export const ink = styleVariants(INK, ([light, dark]) => ({
  color: light,
  selectors: { ':root[data-theme="dark"] &': { color: dark } },
  "@media": { "(prefers-color-scheme: dark)": { selectors: { ':root:not([data-theme="light"]) &': { color: dark } } } },
}));
globalStyle(`${markdown} ${codeBlock} pre`, { padding: "12px 14px", fontSize: vars.textMeta, lineHeight: "1.6" });
