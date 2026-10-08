import { globalStyle, style } from "@vanilla-extract/css";
import { btn, input } from "../styles/controls.css.ts";
import { vars } from "../styles/tokens.css.ts";

export const signInPage = style({});
globalStyle(`${signInPage} p`, { maxWidth: "30em" });
globalStyle(`${signInPage} ${btn}`, { marginTop: "8px" });
/** The ways to sign in: one column, each as wide as the others. */
export const ways = style({ display: "flex", flexDirection: "column", alignItems: "stretch", gap: "12px", width: "100%", maxWidth: "300px", marginTop: "12px" });
globalStyle(`${ways} ${btn}`, { marginTop: 0, width: "100%" });
export const or = style({ color: vars.subtle, fontSize: vars.textMeta, textAlign: "center", lineHeight: "16px" });
export const passwordForm = style({ display: "flex", flexDirection: "column", gap: "12px" });
globalStyle(`${passwordForm} ${btn}`, { marginTop: 0 });
/** Email and password as one block (as iOS groups fields): a grey ground, a hairline gap between, no outlines. */
export const fields = style({ display: "flex", flexDirection: "column", gap: "1px", borderRadius: "16px", overflow: "hidden", cornerShape: vars.cornerShape });
globalStyle(`${fields} input${input}`, {
  height: "44px", border: 0, borderRadius: 0, paddingLeft: "18px", paddingRight: "18px",
  background: `color-mix(in srgb, ${vars.text} 5%, transparent)`, transition: `background ${vars.dur} ${vars.easeOut}`,
});
globalStyle(`${fields} input${input}:hover, ${fields} input${input}:focus`, { background: `color-mix(in srgb, ${vars.text} 8%, transparent)` });
export const passwordError = style({ textAlign: "left", paddingLeft: "18px" });
