import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { gate } from "../styles/shell.css.ts";
import { btn, fieldError } from "../styles/controls.css.ts";

export const invitePage = style({});
export const inviteAccount = style({ width: "280px", marginTop: "8px" });
export const inviteActions = style({ display: "flex", gap: "8px" });
export const inviteCard = style({ width: "min(460px, 90vw)", textAlign: "left" });
export const inviteCode = style({ display: "grid", gap: "6px", width: "min(420px, 90vw)", marginTop: "8px" });
globalStyle(`${invitePage} p`, { maxWidth: "30em" });
globalStyle(`${invitePage} ${btn}`, { marginTop: "8px" });
globalStyle(`${inviteCode} ${btn}`, { marginTop: "0" });
globalStyle(`${gate} ${inviteCode} ${fieldError}`, { color: vars.red });
