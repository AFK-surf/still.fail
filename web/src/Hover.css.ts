// What a link, a file or another chat named in a message is, while it is pointed at (Hover.tsx): a small card over it,
// in Cue's card language (clients/packages/app/src/styles.css `comma-recommendation-link-*`, ui hover-card.css): it
// grows out of the edge facing its link with a light blur, and leaves faster than it came; moving straight to the next
// link, the card moves with no fade at all.
import { keyframes, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { glass } from "./styles/glass.ts";

const enter = keyframes({ from: { opacity: "0", transform: "scale(.96)", filter: "blur(2px)" } });
const exit = keyframes({ to: { opacity: "0", transform: "scale(.97)" } });

export const card = style({
  zIndex: "60", width: "320px", maxWidth: "calc(100vw - 16px)", padding: "10px 12px", borderRadius: vars.rMenu, ...glass,
  border: `1px solid ${vars.line}`, boxShadow: `0 12px 32px ${vars.shadow}`, color: vars.text, fontSize: vars.textUi, lineHeight: "1.45",
  transformOrigin: "var(--radix-hover-card-content-transform-origin)", cornerShape: vars.cornerShape,
  selectors: {
    '&[data-state="open"]': { animation: `${enter} 160ms ${vars.easeOut}` },
    '&[data-state="closed"]': { animation: `${exit} 90ms ease-in forwards` },
    "&[data-instant]": { animation: "none" },
  },
  "@media": { "(prefers-reduced-motion: reduce)": { animation: "none !important" } },
});
/** A card that only names where a link goes (no page read): narrower. */
export const cardTile = style({ width: "auto", minWidth: "220px", maxWidth: "min(420px, calc(100vw - 16px))" });

// ---- the generic card: a tile with the site's mark, the link's words, where it goes ----

export const tile = style({ display: "flex", alignItems: "center", gap: "10px", minWidth: "0" });
export const tileThumb = style({
  display: "grid", placeItems: "center", flex: "0 0 auto", width: "36px", height: "36px", borderRadius: "9px", background: vars.hover, color: vars.muted,
  overflow: "hidden",
});
export const tileIcon = style({ width: "20px", height: "20px", objectFit: "contain" });
export const tileBody = style({ display: "flex", flexDirection: "column", gap: "1px", minWidth: "0" });
/** The title in two lines at most (a commit's or a page's is often longer than the tile), then an ellipsis. */
export const tileTitle = style({
  fontWeight: "500", overflow: "hidden", display: "-webkit-box", WebkitBoxOrient: "vertical", WebkitLineClamp: "2", overflowWrap: "anywhere",
});
export const tileUrl = style({ fontSize: vars.textMeta, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });

// ---- the rich card: state and reference with the time at the right; the title; who, and a few facts ----

export const rich = style({ display: "flex", flexDirection: "column", gap: "8px", minWidth: "0" });
export const meta = style({ display: "flex", alignItems: "center", gap: "8px", minWidth: "0", fontSize: vars.textMeta, color: vars.muted });
export const ref = style({ flex: "1 1 auto", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const refIcon = style({ verticalAlign: "-1px", marginRight: "4px" });
/** A file's card's head: its icon, name and age; its whole path under them, wrapped wherever it must be, selectable. */
export const fileHead = style({ display: "flex", flexDirection: "column", gap: "2px", minWidth: "0" });
export const fileTitle = style({ display: "flex", alignItems: "center", gap: "6px", minWidth: "0" });
export const fileTime = style({ flex: "0 0 auto", marginLeft: "auto", fontSize: vars.textMeta, color: vars.muted, whiteSpace: "nowrap" });
export const fileTitleIcon = style({ flex: "0 0 auto", color: vars.muted });
export const filePath = style({
  fontFamily: vars.fontMono, fontSize: vars.textCaption, color: vars.muted, overflowWrap: "anywhere", userSelect: "text", WebkitUserSelect: "text",
});
/** What can be done with a file's path (copied, shown in Finder), at the end of its facts. */
export const actions = style({ display: "inline-flex", gap: "2px", marginLeft: "auto" });
export const action = style({
  display: "inline-flex", alignItems: "center", gap: "4px", padding: "2px 6px", border: "0", borderRadius: "6px", background: "transparent",
  color: vars.muted, font: "inherit", cursor: "pointer", whiteSpace: "nowrap",
  selectors: { "&:hover": { background: vars.hover, color: vars.text } },
});
export const time = style({ flex: "0 0 auto", marginLeft: "auto", whiteSpace: "nowrap" });
/** A tinted pill: its glyph and the state's name, its colours by `data-state`. */
export const state = style({
  display: "inline-flex", alignItems: "center", gap: "4px", flex: "0 0 auto", padding: "1px 8px 1px 6px", borderRadius: "999px",
  background: vars.hover, color: vars.muted, fontWeight: "500", whiteSpace: "nowrap",
  selectors: {
    '&[data-state="open"], &[data-state="passed"]': { background: vars.greenBg, color: vars.green },
    '&[data-state="merged"], &[data-state="completed"]': { background: "color-mix(in srgb, #8250df 14%, transparent)", color: "#8250df" },
    '&[data-state="closed"], &[data-state="failed"]': { background: vars.redBg, color: vars.red },
    '&[data-state="draft"], &[data-state="not_planned"]': { background: vars.hover, color: vars.muted },
    '&[data-state="pending"]': { background: vars.amberBg, color: vars.amber },
  },
});
export const title = style({ display: "block", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontWeight: "500" });
export const excerpt = style({
  margin: "0", minWidth: "0", color: vars.text, overflowWrap: "anywhere",
  display: "-webkit-box", WebkitLineClamp: "3", WebkitBoxOrient: "vertical", overflow: "hidden",
});
export const facts = style({ display: "flex", alignItems: "center", gap: "8px", minWidth: "0", flexWrap: "wrap", fontSize: vars.textMeta, color: vars.muted });
export const person = style({ display: "inline-flex", alignItems: "center", gap: "6px", minWidth: "0", color: vars.text });
export const avatar = style({ width: "18px", height: "18px", borderRadius: "50%", background: vars.hover, flex: "0 0 auto" });
export const chip = style({ display: "inline-flex", gap: "6px", padding: "1px 7px", borderRadius: "999px", background: vars.hover, whiteSpace: "nowrap" });
export const add = style({ color: vars.green });
export const del = style({ color: vars.red });

/** A file's lines, numbered, the one named marked. */
export const lines = style({
  margin: "0", padding: "6px 0", borderRadius: "8px", background: vars.hover, fontFamily: vars.fontMono, fontSize: vars.textCaption, lineHeight: "1.55",
  overflow: "hidden", whiteSpace: "pre",
});
export const line = style({ display: "flex", paddingRight: "8px", selectors: { "&[data-at]": { background: vars.accentBg } } });
export const lineNo = style({ flex: "0 0 auto", width: "34px", paddingRight: "8px", textAlign: "right", color: vars.muted, userSelect: "none" });
export const lineText = style({ overflow: "hidden", textOverflow: "ellipsis" });
export const thumb = style({ display: "block", maxWidth: "100%", maxHeight: "180px", borderRadius: "8px", margin: "0 auto", background: vars.hover });
/** A directory's entries, in two columns, each with its icon. */
export const entries = style({
  display: "grid", gridTemplateColumns: "repeat(2, minmax(0, 1fr))", gap: "2px 12px", margin: "0", padding: "6px 8px", borderRadius: "8px",
  background: vars.hover, listStyle: "none", fontFamily: vars.fontMono, fontSize: vars.textCaption, lineHeight: "1.55", color: vars.text,
});
export const entry = style({ display: "flex", alignItems: "center", gap: "5px", minWidth: "0" });
export const entryIcon = style({ flex: "0 0 auto", color: vars.muted });
export const entryName = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const note = style({ margin: "0", color: vars.muted });

// ---- while it is read: bars where its lines will be ----

const shine = keyframes({ from: { backgroundPosition: "100% 0" }, to: { backgroundPosition: "-100% 0" } });
export const bar = style({
  display: "block", height: "10px", borderRadius: "999px",
  background: `linear-gradient(90deg, ${vars.hover} 40%, color-mix(in srgb, ${vars.muted} 22%, transparent) 50%, ${vars.hover} 60%) 0 0 / 400% 100%`,
  animation: `${shine} 1.4s linear infinite`,
  selectors: { '&[data-bar="title"]': { width: "85%", height: "12px" }, '&[data-bar="meta"]': { width: "45%" }, '&[data-bar="detail"]': { width: "60%" } },
  "@media": { "(prefers-reduced-motion: reduce)": { animation: "none" } },
});

// ---- a file named in a message: a chip, its icon and name ----

export const fileChip = style({
  display: "inline-flex", alignItems: "baseline", gap: "4px", maxWidth: "100%", padding: "0 6px", borderRadius: "6px", border: "0",
  background: `color-mix(in srgb, ${vars.muted} 13%, transparent)`, color: vars.text, fontFamily: vars.fontMono, fontSize: "0.88em",
  lineHeight: "inherit", cursor: "pointer", verticalAlign: "baseline", textAlign: "left",
  selectors: {
    "&:hover": { background: `color-mix(in srgb, ${vars.muted} 24%, transparent)` },
    // A directory opens nothing (but in Finder, on this machine): its card is all there is.
    "&[data-dir]:not([data-opens])": { cursor: "default" },
  },
});
export const fileChipIcon = style({ alignSelf: "center", flex: "0 0 auto", color: vars.muted });
export const fileChipName = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const fileChipLine = style({ color: vars.muted });
