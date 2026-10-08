import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../../styles/tokens.css.ts";

export const mNewNone = style({});
globalStyle(`${mNewNone} p`, { fontSize: vars.textMeta, color: "var(--m-muted)" });
