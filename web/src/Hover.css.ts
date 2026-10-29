// What a link, a file or another chat named in a message is, while it is pointed at (Hover.tsx): a small card over it,
// in Cue's card language (clients/packages/app/src/styles.css `comma-recommendation-link-*`, ui hover-card.css): it
// grows out of the edge facing its link with a light blur, and leaves faster than it came; moving straight to the next
// link, the card moves with no fade at all.
import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { litOver } from "@stillfail/ui/styles/lit.ts";
import { panelCard, popover } from "@stillfail/ui/styles/controls.css.ts";
import { IN, PANEL_PAD, PANEL_PILL, TEXT_IN, inner, pillInner } from "@stillfail/ui/styles/align.ts";

const enter = keyframes({ from: { opacity: "0", transform: "scale(.96)", filter: "blur(2px)" } });
const exit = keyframes({ to: { opacity: "0", transform: "scale(.97)" } });

/** A small panel of words (styles/controls.css.ts popover, panelCard: docs/ui-panels.md), its own coming and going. */
export const card = style([popover, panelCard, {
  // Its corner from the pills a file's card has in its corner (fileFoot): align.ts pillInner.
  vars: { [IN]: pillInner(PANEL_PAD, PANEL_PILL, vars.cornerScale) },
  display: "flex", flexDirection: "column", gap: "8px",
  zIndex: "60", width: "320px", maxWidth: "calc(100vw - 16px)", color: vars.text, fontSize: vars.textUi, lineHeight: "1.45",
  transformOrigin: "var(--radix-hover-card-content-transform-origin)",
  selectors: {
    '&[data-state="open"]': { animation: `${enter} 160ms ${vars.easeOut}` },
    '&[data-state="closed"]': { animation: `${exit} 90ms var(--ease-leave) forwards` },
    "&[data-instant]": { animation: "none" },
  },
}]);
/** A card that only names where a link goes (no page read): narrower. */
export const cardTile = style({ width: "auto", minWidth: "220px", maxWidth: "min(420px, calc(100vw - 16px))" });

// ---- the generic card: a tile with the site's mark, the link's words, where it goes ----

export const tile = style({ display: "flex", alignItems: "center", gap: "10px", minWidth: "0" });
export const tileThumb = style({
  display: "grid", placeItems: "center", flex: "0 0 auto", width: "36px", height: "36px",
  borderRadius: `calc(9px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: vars.hover, color: vars.muted,
  overflow: "hidden",
});
export const tileIcon = style({ width: "20px", height: "20px", objectFit: "contain" });
export const tileBody = style({ display: "flex", flexDirection: "column", gap: "1px", minWidth: "0" });
/** The title in two lines at most (a commit's or a page's is often longer than the tile), then an ellipsis. */
export const tileTitle = style({
  fontWeight: "500", overflow: "hidden", display: "-webkit-box", WebkitBoxOrient: "vertical", WebkitLineClamp: "2", overflowWrap: "anywhere",
});
export const tileUrl = style({ fontSize: vars.textMeta, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** A page's picture over its tile: as wide as a full card, 16:9 (a video's frame; a wider og:image is cropped a little). */
export const tileWithPicture = style({ display: "flex", flexDirection: "column", gap: "10px", width: "min(296px, calc(100vw - 40px))" });
export const picture = style({ display: "block", width: "100%", aspectRatio: "16 / 9", objectFit: "cover", borderRadius: `calc(8px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: vars.hover });

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
  fontFamily: vars.fontMono, fontSize: vars.textCaption, color: vars.muted, overflowWrap: "anywhere", userSelect: "text",
});
/** What can be done with a file's path (copied, shown in Finder), at the end of its facts. */
/**
 * A file's card's foot, at the card's padding (controlsCss.panelEdge, docs/ui-panels.md): what it is (its size, its
 * entries) in words where the words stand, no ground of their own by a corner, and its buttons (ui.tsx PanelButton) in
 * the card's corner, as far from its side as from its foot.
 */
export const fileFoot = style({
  display: "flex", alignItems: "center", gap: "8px", minWidth: "0", minHeight: PANEL_PILL, paddingLeft: TEXT_IN,
  fontSize: vars.textMeta, color: vars.muted,
});
/** What copies a web link, on its card (Peeks.tsx LinkCopy): at its facts' line's end, in the card's bottom end corner. */
export const copy = style({
  // (out past the card's words to where a 24 circle is concentric with its corner: the card's inner corner, IN, less
  // its half and the words' inset)
  flex: "none",
  marginRight: `calc(${inner} - ${PANEL_PILL / 2 + TEXT_IN}px)`, marginBottom: `calc(${inner} - ${PANEL_PILL / 2 + TEXT_IN}px)`,
});
export const actions = style({ display: "inline-flex", gap: "2px", marginLeft: "auto", flex: "none" });
export const time = style({ flex: "0 0 auto", marginLeft: "auto", whiteSpace: "nowrap" });
/** A tinted pill: its glyph and the state's name, its colours by `data-state`. */
export const state = style({
  display: "inline-flex", alignItems: "center", gap: "4px", flex: "0 0 auto", padding: "1px 8px 1px 6px", borderRadius: "999px",
  background: vars.hover, color: vars.muted, fontWeight: "500", whiteSpace: "nowrap",
  selectors: {
    '&[data-state="open"], &[data-state="passed"]': { background: vars.greenBg, color: vars.green },
    '&[data-state="merged"], &[data-state="completed"]': { background: vars.purpleBg, color: vars.purple },
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
/** The facts' line: them (wrapping), and what copies the link at its end, in the card's bottom end corner. */
export const factsLine = style({ display: "flex", alignItems: "flex-end", gap: "8px", minWidth: "0" });
export const facts = style({ flex: "1 1 auto", display: "flex", alignItems: "center", gap: "8px", minWidth: "0", flexWrap: "wrap", fontSize: vars.textMeta, color: vars.muted });
export const person = style({ display: "inline-flex", alignItems: "center", gap: "6px", minWidth: "0", color: vars.text });
export const avatar = style({ width: "18px", height: "18px", borderRadius: "50%", background: vars.line, flex: "0 0 auto" });
export const chip = style({ display: "inline-flex", gap: "6px", padding: "1px 7px", borderRadius: "999px", background: vars.hover, whiteSpace: "nowrap" });
export const add = style({ color: vars.green });
export const del = style({ color: vars.red });

/** A file's lines, numbered, the one named marked. */
export const lines = style({
  margin: "0", padding: "6px 0", borderRadius: `calc(8px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: vars.hover, fontFamily: vars.fontMono, fontSize: vars.textCaption, lineHeight: "1.55",
  overflow: "hidden", whiteSpace: "pre",
});
export const line = style({ display: "flex", paddingRight: "8px", selectors: { "&[data-at]": { background: vars.accentBg } } });
export const lineNo = style({ flex: "0 0 auto", width: "34px", paddingRight: "8px", textAlign: "right", color: vars.muted, userSelect: "none" });
export const lineText = style({ overflow: "hidden", textOverflow: "ellipsis" });
export const thumb = style({ display: "block", maxWidth: "100%", maxHeight: "180px", borderRadius: `calc(8px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, margin: "0 auto", background: vars.hover });
/** A directory's entries, in two columns, each with its icon. */
export const entries = style({
  display: "grid", gridTemplateColumns: "repeat(2, minmax(0, 1fr))", gap: "2px 12px", margin: "0", padding: "6px 8px",
  borderRadius: `calc(8px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: vars.hover, listStyle: "none", fontFamily: vars.fontMono, fontSize: vars.textCaption, lineHeight: "1.55", color: vars.text,
});
export const entry = style({ display: "flex", alignItems: "center", gap: "5px", minWidth: "0" });
export const entryIcon = style({ flex: "0 0 auto", color: vars.muted });
export const entryName = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const note = style({ margin: "0", color: vars.muted });

// ---- a file named in a message: a chip, its icon and name ----

export const fileChip = style({
  display: "inline-flex", alignItems: "baseline", gap: "4px", maxWidth: "100%", padding: "0 6px",
  borderRadius: `calc(6px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, border: "0",
  background: `color-mix(in srgb, ${vars.muted} 13%, transparent)`, color: vars.text, fontFamily: vars.fontMono, fontSize: "0.88em",
  lineHeight: "inherit", cursor: "pointer", verticalAlign: "baseline", textAlign: "left",
  selectors: {
    "&:hover": litOver,
    // A directory opens nothing (but in Finder, on this machine): its card is all there is.
    "&[data-dir]:not([data-opens])": { cursor: "default" },
  },
});
export const fileChipIcon = style({ alignSelf: "center", flex: "0 0 auto", color: vars.muted });
export const fileChipName = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const fileChipLine = style({ color: vars.muted });
