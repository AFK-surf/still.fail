import { globalStyle, style } from "@vanilla-extract/css";
import { btn } from "../styles/controls.css.ts";
import { vars } from "../styles/tokens.css.ts";

export const signInPage = style({});
globalStyle(`${signInPage} p`, { maxWidth: "30em" });
globalStyle(`${signInPage} ${btn}`, { marginTop: "8px" });
/** The ways to sign in: one column, each as wide as the others. */
export const ways = style({ display: "flex", flexDirection: "column", alignItems: "stretch", gap: "12px", width: "100%", maxWidth: "300px", marginTop: "12px" });
globalStyle(`${ways} ${btn}`, { marginTop: 0, width: "100%" });
export const or = style({ color: vars.subtle, fontSize: vars.textXs, textAlign: "center", lineHeight: "16px" });
export const passwordForm = style({ display: "flex", flexDirection: "column", gap: "8px" });
globalStyle(`${passwordForm} ${btn}`, { marginTop: "4px" });
export const passwordError = style({ textAlign: "left", paddingLeft: "16px" });
