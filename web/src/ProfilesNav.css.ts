// The profiles' sidebar (ProfilesNav.tsx): what is on a row's second line (the rows themselves, SidebarList.tsx).
import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

export const quota = style({ flex: "none", display: "flex", gap: 4 });
export const credits = style({ flex: "none", fontSize: vars.textMeta, color: vars.muted, fontVariantNumeric: "tabular-nums" });
/** How it is doing, only when something is wrong: in its tone. */
export const trouble = style({
  flex: "none", color: vars.amber,
  selectors: { '&[data-tone="red"]': { color: vars.red }, '&[data-tone="neutral"]': { color: vars.muted } },
});
/** What clicking a machine's login does, at the end of its second line. */
export const offer = style({ flex: "none", color: vars.accentText });
