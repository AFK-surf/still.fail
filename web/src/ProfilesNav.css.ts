// The profiles' sidebar (ProfilesNav.tsx): two lines a row, as a chat's, the provider's mark beside the name.
import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;

/** 添加 Profile, as 新建对话 is over the chats. */
export const add = style({ padding: "2px 0 0" });
export const addRow = style({ width: "100%", border: 0, background: "none", font: "inherit", textAlign: "left", cursor: "pointer" });

export const row = style({
  width: "100%", alignItems: "flex-start", paddingTop: 7, paddingBottom: 7, textAlign: "left", font: "inherit", border: 0,
  background: "none", cursor: "pointer", textDecoration: "none",
  selectors: { "&:disabled": { cursor: "progress" } },
});
/** The mark on the first line, as wide as the add row's icon. */
export const mark = style({ display: "grid", placeItems: "center", flex: "none", width: 16, height: 20 });
export const text = style({ display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: 2, flex: 1, minWidth: 0 });
export const head = style({ display: "flex", alignItems: "center", gap: 6, height: 20, minWidth: 0 });
export const name = style({
  flex: 1, ...ellipsis,
  selectors: { [`${row}[data-away] &`]: { opacity: 0.5 } },
});
export const quota = style({ flex: "none", display: "flex" });
export const credits = style({ flex: "none", fontSize: vars.textMeta, color: vars.muted, fontVariantNumeric: "tabular-nums" });
export const meta = style({
  display: "flex", alignItems: "center", gap: 4, height: 18, lineHeight: "18px", minWidth: 0,
  fontSize: vars.textMeta, color: vars.muted, whiteSpace: "nowrap",
});
export const facts = style({ flex: 1, ...ellipsis });
/** How it is doing, only when something is wrong: in its tone. */
export const trouble = style({
  flex: "none", color: vars.amber,
  selectors: { '&[data-tone="red"]': { color: vars.red }, '&[data-tone="neutral"]': { color: vars.muted } },
});
/** What clicking a machine's login does, at the end of its second line. */
export const offer = style({ flex: "none", color: vars.accentText });
