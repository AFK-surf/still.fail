import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { popKeyframes } from "./styles/keyframes.css.ts";

/** Where the menu hangs from: the composer's top edge. */
export const refAnchor = style({ position: "relative", height: "0" });
/** The composer's own look (styles/composer.css.ts, focused): glass, no border, its corners, its shadow. */
export const refMenu = style({
  position: "absolute", left: "0", right: "0", bottom: "8px", zIndex: "60", maxHeight: "320px", overflowY: "auto",
  padding: "12px", border: "0", borderRadius: `calc(32px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: `color-mix(in srgb, ${vars.raised} 72%, transparent)`, WebkitBackdropFilter: "blur(20px)", backdropFilter: "blur(20px)",
  boxShadow: "0 4px 12px rgb(0 0 0 / .07), 0 1px 3px rgb(0 0 0 / .05)",
  transformOrigin: "bottom", animation: `${popKeyframes} 140ms ${vars.easeOut}`,
});
export const refHead = style({ display: "flex", gap: "6px", padding: "0 12px 6px", fontSize: vars.textXs, color: vars.muted });
export const refQuery = style({ color: vars.text });
export const refEmpty = style({ margin: "0", padding: "6px 12px 4px", fontSize: vars.textSm, color: vars.muted });
export const refItem = style({
  display: "grid", gridTemplateColumns: "16px minmax(0, 1fr) auto", alignItems: "center", gap: "10px", width: "100%",
  minHeight: "38px", padding: "8px 12px", border: "0", borderRadius: `calc(20px * ${vars.cornerScale})`, background: "none", color: vars.text,
  textAlign: "left", fontSize: vars.textSm, cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&[data-active]": { background: vars.hover },
  },
});
export const refLogo = style({ display: "grid", placeItems: "center" });
export const refTitle = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const refTime = style({ fontSize: vars.textXs, color: vars.muted });

/** The composer: its mirror is placed in it. */
export const refHost = style({ position: "relative" });
/** The composer's text under its own: laid over it (Chat.tsx places it), the letters where the textarea has them. */
export const refMirror = style({
  position: "absolute", margin: "0", overflow: "hidden", whiteSpace: "pre-wrap", overflowWrap: "break-word",
  pointerEvents: "none", color: vars.text, maxHeight: "none",
});
/** A mark in the composer: colour only, no padding or border, so it takes the room its letters take. */
export const refMark = style({
  borderRadius: "6px", background: vars.accentBg, color: vars.accent, boxDecorationBreak: "clone", WebkitBoxDecorationBreak: "clone",
});
export const refMarkHidden = style({ color: "transparent" });
/** The composer's text while it holds a mark: see-through, the mirror under it drawn instead. */
export const refTextSeeThrough = style({ color: "transparent !important", caretColor: vars.text });
/** A reference in a message. */
export const refChip = style({
  display: "inline", padding: "1px 6px", borderRadius: "6px", background: vars.accentBg, color: vars.accent,
  textDecoration: "none", boxDecorationBreak: "clone", WebkitBoxDecorationBreak: "clone", cursor: "pointer",
  selectors: {
    // Over a message's own link colours (styles/conversation.css.ts).
    "&&": { color: vars.accent, textDecoration: "none" },
    "&&:hover": { textDecoration: "underline", textUnderlineOffset: "3px" },
  },
});
export const refChipHash = style({ marginRight: "3px", opacity: ".7" });
