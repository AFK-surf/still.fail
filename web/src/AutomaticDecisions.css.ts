import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { listRowTitle } from "./styles/pages.css.ts";

// Layout only: controls, popovers, switches and record text use the shared components.
export const content = style({});
export const note = style({ color: vars.muted, fontSize: vars.textXs, lineHeight: "1.5" });
export const recordHead = style({ display: "flex", alignItems: "baseline", gap: 16, minWidth: 0 });
export const meta = style({ display: "flex", gap: 6, fontSize: vars.textXs, color: vars.muted, lineHeight: "18px", minWidth: 0 });
export const time = style({ color: vars.subtle, fontSize: vars.textXs, whiteSpace: "nowrap", flex: "none" });
export const error = style({ color: vars.red, fontSize: vars.textXs, overflowWrap: "anywhere" });
export const bad = style({ color: vars.red });
export const tools = style({ display: "flex", alignItems: "center", gap: 8 });
globalStyle(`${recordHead} > ${listRowTitle}`, { flex: "1", minWidth: 0 });
