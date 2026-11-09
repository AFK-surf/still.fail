// The app's own marks and links among the shared parts (ui.tsx): what made an agent's model, a connect's kind, a time,
// the way back; and where the app's pages put @stillfail/ui's parts (its parts.css.ts, just before this in the cascade).
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { DIALOG_INNER, dialogBody } from "@stillfail/ui/parts.css.ts";
import { pageBar } from "./styles/sidebar.css.ts";
import { markdown } from "./styles/conversation.css.ts";
import { card } from "./styles/pages.css.ts";
export const mobileBack = style({
  display: "none", alignItems: "center", gap: "2px", color: vars.muted, fontSize: vars.textUi, lineHeight: "20px",
  "@media": {
    "(max-width: 700px)": {
      display: "inline-flex", marginBottom: "12px",
      selectors: {
        [`${pageBar} &`]: { margin: "0" },
      },
    },
  },
});
export const runtimeLogo = style({ flex: "none", display: "block" });
export const timeToggle = style({
  cursor: "pointer",
  selectors: {
    "&:hover": { textDecoration: "underline dotted", textUnderlineOffset: "2px" },
  },
});
/** Cards in a dialog sit at its padding, as its choices and command lines do: their corners are the dialog's, less it. */
globalStyle(`${dialogBody} ${card}`, { borderRadius: DIALOG_INNER });
/** Here rather than with its class: it comes after .empty p, and wins over it. */
globalStyle(`${markdown} p`, { margin: "0 0 8px" });
/** Here rather than with its class: it comes after .empty h2, and wins over it. */
globalStyle(`${markdown} h2`, { fontSize: vars.textBody, margin: "14px 0 6px" });
/** Here rather than with its class: it comes after .command code, and wins over it. */
globalStyle(`${markdown} code`, {
  fontSize: vars.textMeta, padding: "1px 5px", borderRadius: `calc(6px * ${vars.cornerScale})`, background: vars.neutralBg,
  cornerShape: vars.cornerShape,
});

