import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { glass } from "@stillfail/ui/styles/glass.ts";
import { pillInner } from "@stillfail/ui/styles/align.ts";

const COMPOSER_PAD = 12;
/** The attach and send buttons' size (toast.css.ts sendBtn, attachBtn). */
export const COMPOSER_BUTTON = 32;
/** The corner of what sits in the composer's corners (its files, its quotes): concentric with its own. */
export const COMPOSER_INNER = pillInner(COMPOSER_PAD, COMPOSER_BUTTON, vars.cornerScale);

export const composerBox = style({
  selectors: {
    "&[data-dragging]": {
      borderColor: vars.fieldFocus,
      background: `color-mix(in srgb, ${vars.fieldFocus} 8%, color-mix(in srgb, ${vars.raised} 72%, transparent))`,
    },
  },
});
/** Here rather than with its class: it comes after .composer-box[data-dragging], and wins over it. */
globalStyle(`${composerBox}:focus-within`, { borderColor: vars.fieldFocus });
/** Here rather than with its class: it comes after .composer-box:not([data-multiline]), and wins over it. */
// Its corner from the buttons in its corners (attach, send: 32, 12 in), as a pill's (align.ts pillInner).
globalStyle(`${composerBox}[data-multiline]`, {
  flexDirection: "column", alignItems: "stretch", gap: "8px", padding: `${COMPOSER_PAD}px`,
  borderRadius: `calc(${COMPOSER_INNER} + ${COMPOSER_PAD}px)`, cornerShape: vars.cornerShape,
});
/** Composer: one line sits on the frame's centre line; files ride above the text. */
/** Here rather than with its class: it comes after .composer-box[data-multiline], and wins over it. */
globalStyle(`${composerBox}:not([data-multiline])`, { alignItems: "center", gap: "2px", paddingLeft: "6px" });
/** Here rather than with its class: it comes after .composer-box:not([data-multiline]), and wins over it. */
globalStyle(`${composerBox}[data-multiline]`, { gap: "10px" });
/** Here rather than with its class: it comes after .composer-box[data-dragging], and wins over it. */
globalStyle(`${composerBox}:focus-within`, {
  border: "0", ...glass, boxShadow: "0 1px 3px rgb(0 0 0 / .04)",
});
