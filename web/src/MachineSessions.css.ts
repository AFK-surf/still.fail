// The new chat page's way to go on with a session the machine kept (MachineSessions.tsx).
import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;

/** Under the composer, quiet as the words around it until pointed at. */
export const offer = style({
  display: "inline-flex", alignItems: "center", gap: 6, padding: "4px 10px", border: 0, borderRadius: vars.rNav,
  background: "transparent", color: vars.muted, font: "inherit", fontSize: vars.textSm, cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover, color: vars.text } },
});

export const list = style({ listStyle: "none", margin: "0 -12px", padding: 0, display: "grid", gap: 2 });

export const row = style({
  width: "100%", display: "grid", gridTemplateColumns: "auto minmax(0, 1fr) auto", alignItems: "center", gap: 12,
  padding: "10px 12px", border: 0, borderRadius: vars.rOption, background: "transparent", color: vars.text,
  font: "inherit", textAlign: "left", cursor: "pointer",
  selectors: { "&:hover:not(:disabled)": { background: vars.hover }, "&:disabled": { cursor: "default" } },
});

export const main = style({ display: "grid", gap: 2, minWidth: 0 });
export const title = style({ ...ellipsis, fontSize: vars.textBody, fontWeight: 500 });
export const meta = style({ ...ellipsis, fontSize: vars.textXs, color: vars.muted });
export const already = style({ fontSize: vars.textXs, color: vars.muted, whiteSpace: "nowrap" });
