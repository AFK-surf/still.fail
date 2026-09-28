import { globalStyle, style } from "@vanilla-extract/css";
import { btn } from "../styles/controls.css.ts";

export const signInPage = style({});
globalStyle(`${signInPage} p`, { maxWidth: "30em" });
globalStyle(`${signInPage} ${btn}`, { marginTop: "8px" });
