import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { popKeyframes } from "./styles/keyframes.css.ts";
import { glass } from "./styles/glass.ts";

/** Where the menu hangs from: the composer's top edge. */
export const refAnchor = style({ position: "relative", height: "0" });
/** The composer's own look (styles/composer.css.ts, focused): glass, no border, its corners, its shadow. */
export const refMenu = style({
  position: "absolute", left: "0", right: "0", bottom: "8px", zIndex: "60", maxHeight: "320px", overflowY: "auto",
  padding: "12px", border: "0", borderRadius: `calc(32px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  ...glass,
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
export const refMark = style({ color: vars.accent });
export const refMarkHidden = style({ color: "transparent" });
/** The composer's text while it holds a mark: see-through, the mirror under it drawn instead. */
export const refTextSeeThrough = style({ color: "transparent !important", caretColor: vars.text });
/** A reference in a message. */
export const refChip = style({
  display: "inline", color: vars.accent, textDecoration: "none", cursor: "pointer",
  selectors: {
    // Over a message's own link colours (styles/conversation.css.ts).
    "&&": { color: vars.accent, textDecoration: "none" },
    "&&:hover": { textDecoration: "underline", textUnderlineOffset: "3px" },
  },
});
export const refChipHash = style({ marginRight: "1px", opacity: ".7" });
/** The station a reference to another station's chat is on, after its title: quieter than it. */
export const refChipStation = style({
  display: "inline-flex", alignItems: "center", gap: "2px", marginLeft: "4px", padding: "0 5px", borderRadius: "999px",
  fontSize: vars.textXs, lineHeight: "16px", color: vars.muted, background: vars.hover, verticalAlign: "1px",
});
