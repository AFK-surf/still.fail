import { globalStyle, style } from "@vanilla-extract/css";
import { btn } from "../styles/controls.css.ts";
import { vars } from "../styles/tokens.css.ts";

export const signInPage = style({});
globalStyle(`${signInPage} p`, { maxWidth: "30em" });
globalStyle(`${signInPage} ${btn}`, { marginTop: "8px" });
export const passwordLink = style({ marginTop: "12px", padding: 0, border: 0, background: "none", color: vars.muted, fontSize: vars.textSm, cursor: "pointer", selectors: { "&:hover": { color: vars.text } } });
export const passwordForm = style({ display: "flex", flexDirection: "column", gap: "8px", width: "100%", maxWidth: "280px", marginTop: "16px" });
