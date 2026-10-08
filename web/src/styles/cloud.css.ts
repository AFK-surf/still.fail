import { style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";
import { inline } from "./additions.css.ts";
import { chat } from "./session.css.ts";

export const person = style({ flex: "none", borderRadius: "50%", objectFit: "cover" });
export const personLetter = style({
  display: "inline-grid", placeItems: "center", background: vars.paper, color: vars.text, fontWeight: "600",
  // Its own line box: the page's taller one sets a CJK initial low in the circle.
  lineHeight: "1",
});
export const stationTag = style({
  flex: "none", padding: "1px 8px", borderRadius: `calc(6px * ${vars.cornerScale})`, background: vars.neutralBg,
  color: vars.muted, fontSize: vars.textMeta, fontWeight: "500", cornerShape: vars.cornerShape,
  selectors: {
    [`&${inline}`]: { marginLeft: "8px" },
  },
});
export const composerWrap = style({
  flex: "none", padding: "12px 32px 16px",
  selectors: {
    [`${chat} &`]: { borderTop: "0" },
  },
  "@media": {
    "(max-width: 700px)": {
      padding: "8px 12px 12px",
    },
  },
});
