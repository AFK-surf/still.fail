import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";
import { glass } from "./glass.ts";

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
globalStyle(`${composerBox}[data-multiline]`, {
  flexDirection: "column", alignItems: "stretch", gap: "8px", padding: "12px",
  borderRadius: `calc(32px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
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
