// Markdown's own parts.
import { globalStyle, style, styleVariants } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { markdown } from "./styles/conversation.css.ts";

/** Long formulas scroll within the message on a phone. Room above and below keeps accents and limits unclipped. */
export const mathBlock = style({ maxWidth: "100%", overflowX: "auto", margin: "0 0 8px", padding: "2px 0" });
export const formula = style({ display: "inline-block", position: "relative", flexShrink: 0, maxWidth: "none" });
export const formulaSource = style({ position: "absolute", inset: 0, color: "transparent", overflow: "hidden", whiteSpace: "pre", userSelect: "all" });
globalStyle(`${formula} svg`, { display: "block", pointerEvents: "none", overflow: "visible" });

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
/** Code: a quiet tinted block, no frame; language and copy sit in the corner, whole (faded until hovered, their words
 * were 2.2:1: docs/ui-panels.md 对比度). */
export const codeBlock = style({
  position: "relative", margin: "0 0 8px", border: "0", borderRadius: `calc(12px * ${vars.cornerScale})`,
  background: `color-mix(in srgb, ${vars.text} 4%, ${vars.canvas})`, overflow: "hidden",
  cornerShape: vars.cornerShape,
});
export const codeBar = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", borderBottom: `1px solid ${vars.line}`,
  position: "absolute", top: "4px", right: "4px", height: "24px", padding: "0", border: "0", gap: "2px",
  "@media": {
    // A finger has no hover to bring the corner forward: the language and copy get a row of their own, over the code.
    "(pointer: coarse)": { position: "static", justifyContent: "flex-end", padding: "4px 4px 0" },
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
 * A table in its own sideways scroll, its copy key after it (tableKey): the message's `overflow-wrap: anywhere` would
 * else break its cells' words to fit, and each cell is no narrower than Prose says (its words on one line, or a
 * readable width for long ones).
 */
export const tableScroll = style({ display: "flex", alignItems: "flex-start", width: "fit-content", maxWidth: "100%", overflowX: "auto", margin: "0 0 8px" });
globalStyle(`${tableScroll}:last-child`, { marginBottom: "0" });
globalStyle(`${tableScroll} th, ${tableScroll} td`, { overflowWrap: "normal", minWidth: "4em" });
/** The table in the message, no card round it (docs/ui-panels.md 消息里的表格): its first column's words in line with
 * the message's, its last's with nothing after them, so its rules run from the first column's words to the last's
 * (apps/mbui/src/sf/markdown.mbt); the head told by its words alone: within the scroll, sliding with it. */
export const tableFrame = style({ flex: "none", width: "fit-content" });
globalStyle(`${tableFrame} > table`, { margin: "0" });
globalStyle(`${markdown} ${tableFrame} th`, { background: "none" });
globalStyle(`${markdown} ${tableFrame} :is(th, td):first-child`, { paddingLeft: "0" });
globalStyle(`${markdown} ${tableFrame} :is(th, td):last-child`, { paddingRight: "0" });
/** How far its copy key is from the table and from what follows it (Prose.tsx Table), its middle on the head's row's
 * (at the frame's top, the head's padding and line, its rule: Prose's `th`; an IconButton, 32): in what scrolls, after
 * the table, taking no room and over nothing of it (docs/ui-panels.md 复制表格). */
export const tableKey = style({
  flex: "none", padding: "0 6px", marginTop: `calc((14px + ${vars.textMeta} * 1.65 + 1px - 32px) / 2)`,
});
/** A code block's code: square in its block's frame, on its ground, wherever the words around it frame their own `pre`
 * (the reader's page). */
export const codePre = style({});
globalStyle(`${markdown} ${codeBlock} ${codePre}`, {
  margin: "0", padding: "10px 12px", borderRadius: "0", background: "none", fontSize: vars.textMeta, lineHeight: "1.55",
});
/** Code's colours by what each piece is (the letters of the core's `ink`, client/core-ts/src/highlight.ts SCOPES):
 * vitesse-light's, and vitesse-dark's on a dark page, as Shiki gave them, each made to read on a code block's ground
 * (4.5:1: its hue kept, its lightness moved the least; quotes as the words they hold, not faded; docs/ui-panels.md 对比度,
 * apps/mbui/src/sf/ink.mbt the same). */
const INK: Record<string, [light: string, dark: string]> = {
  a: ["#393A34", "#DBD7CAEE"], // text
  b: ["#667266", "#869786"], // comment
  c: ["#6F6F6F", "#939393"], // punctuation
  d: ["#A55B4B", "#C98A7D"], // string
  e: ["#A55B4B", "#C98A7D"], // a string's quotes
  f: ["#2E7889", "#52A096"], // number
  g: ["#1E754F", "#5AA081"], // keyword, constant.language, a tag
  h: ["#A95757", "#D07B7A"], // storage, keyword.operator, null
  i: ["#4E7B2E", "#80A665"], // function
  j: ["#96652F", "#BD976A"], // variable
  k: ["#A55D2A", "#C99076"], // constant, this, an option
  l: ["#137D71", "#5DA994"], // type
  m: ["#836E00", "#B8A965"], // property, support
  n: ["#836E00", "#B8A965"], // a property's quotes
  o: ["#198034", "#85E89D"], // a diff's line added
  p: ["#B31D28", "#FDAEB7"], // a diff's line removed
  q: ["#6F42C1", "#B392F0"], // a hunk's range
};
export const ink = styleVariants(INK, ([light, dark]) => ({
  color: light,
  selectors: { ':root[data-theme="dark"] &': { color: dark } },
  "@media": { "(prefers-color-scheme: dark)": { selectors: { ':root:not([data-theme="light"]) &': { color: dark } } } },
}));
globalStyle(`${markdown} ${codeBlock} ${codePre}`, { padding: "12px 14px", fontSize: vars.textMeta, lineHeight: "1.6" });
