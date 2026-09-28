import { globalStyle, style } from "@vanilla-extract/css";

export const mNewNone = style({});
globalStyle(`${mNewNone} p`, { fontSize: "14px", color: "var(--m-muted)" });
