import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;

// The changelog on a narrow screen: each change on its day's card, its lines each led by its kind, then its version
// and what is not out yet (in the accent when an update would bring it).
export const mTabs = style({ padding: "4px 16px 2px" });
export const mNote = style({
  display: "flex", alignItems: "center", gap: "8px", margin: "8px 24px", fontSize: vars.textMeta, color: "var(--m-muted)",
  selectors: { "&[data-error]": { color: "var(--m-red)" } },
});
export const mChange = style({ display: "flex", flexDirection: "column", gap: "2px", padding: "10px 16px" });
export const mLine = style({ fontSize: vars.textBody, lineHeight: "21px", color: "var(--m-ink)" });
export const mKind = style({
  display: "inline-block", marginRight: "6px", padding: "0 6px", borderRadius: "6px", fontSize: vars.textMeta, lineHeight: "19px",
  verticalAlign: "1px", color: "var(--m-muted)", background: "var(--m-chip)",
  selectors: {
    '&[data-kind="new"]': { color: "var(--m-accent-ink)", background: "var(--m-accent-bg)" },
    // B: the kind's name alone.
    'html[data-clv="b"] &': { padding: "0", background: "none", fontWeight: 600 },
  },
});
export const mMeta = style({ display: "flex", flexWrap: "wrap", gap: "0 10px", fontSize: vars.textMeta, lineHeight: "18px", color: "var(--m-muted)" });
// What an update would bring, said in the accent.
globalStyle(`${mMeta} [data-has="false"]`, { color: "var(--m-accent-ink)" });

// After an update, at the top of the list: what it brought, put away by its ×. Its buttons inherit
// (./styles/root.css.ts): their colour and size are set here, as strongly.
export const mNews = style({ position: "relative", margin: "4px 12px 10px", borderRadius: "16px", background: "var(--m-surface)" });
export const mNewsBody = style({
  display: "flex", flexDirection: "column", gap: "2px", width: "100%", padding: "12px 44px 12px 16px", border: "0",
  borderRadius: "inherit", background: "none", textAlign: "left", cursor: "pointer",
  selectors: { "&:active": { background: "var(--m-chip)" } },
});
export const mNewsHead = style({ display: "flex", alignItems: "center", gap: "6px", marginBottom: "2px", fontSize: vars.textBody, fontWeight: 600, color: "var(--m-ink)" });
export const mNewsLine = style({ ...ellipsis, fontSize: vars.textMeta, lineHeight: "18px", color: "var(--m-muted)" });
export const mNewsClose = style({
  position: "absolute", top: "6px", right: "6px", display: "grid", placeItems: "center", width: "32px", height: "32px",
  padding: "0", border: "0", borderRadius: "50%", background: "none", color: "var(--m-muted)", cursor: "pointer",
});
globalStyle(`${mNews} button${mNewsBody}`, { fontSize: vars.textMeta, color: "var(--m-muted)" });
globalStyle(`${mNews} button${mNewsClose}`, { color: "var(--m-muted)" });
