import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

// 设置 › 密钥 (Vault.tsx): the settings pages' cards and lists (pages.css.ts), what is the vault's own here.
export const sub = style({ display: "block", margin: "0", color: vars.muted });
export const note = style({ margin: "0", fontSize: vars.textMeta, color: vars.muted });
export const grow = style({ flex: "1" });
/** The state, first in its card: a dot and words. */
export const state = style({ display: "flex", alignItems: "center", gap: "8px", fontSize: vars.textBody, fontWeight: "500" });
export const dot = style({
  width: "7px", height: "7px", borderRadius: "50%", flex: "none", background: vars.lineStrong,
  selectors: { '&[data-tone="amber"]': { background: vars.amber } },
});
export const actions = style({ display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap" });
/** The first card, as far from what follows as a section is. */
export const lead = style({ marginBottom: "28px" });
/** What the vault does, a line each with its icon. */
export const points = style({ display: "grid", gap: "10px" });
export const point = style({ display: "grid", gridTemplateColumns: "20px 1fr", gap: "8px", fontSize: vars.textBody, lineHeight: vars.leadingBody, color: vars.text });
export const pointIcon = style({ color: vars.muted, marginTop: "2px" });

/** The recovery words: numbered, three columns, each as it is to be written. */
export const words = style({
  display: "grid", gridTemplateColumns: "repeat(3, minmax(0, 1fr))", gap: "10px 16px", maxWidth: "540px", margin: "0", padding: "4px 0",
  listStyle: "none", fontFamily: vars.fontMono, fontSize: vars.textBody,
});
export const word = style({ display: "flex", alignItems: "baseline", gap: "10px", color: vars.text });
export const wordN = style({ minWidth: "1.6em", textAlign: "right", fontSize: vars.textMeta, color: vars.subtle, fontVariantNumeric: "tabular-nums" });

/** The settings' sidebar row's: requests waiting, at its end. */
export const navCount = style({ marginLeft: "auto", fontSize: vars.textMeta, color: vars.red, fontWeight: "500", fontVariantNumeric: "tabular-nums" });
export const count = style({ fontSize: vars.textMeta, padding: "0 7px", borderRadius: "999px", background: vars.redBg, color: vars.red, fontWeight: "500" });
/** The requests waiting: each one's facts over its approval's rows. */
export const requests = style({ display: "grid", gap: "28px" });
export const request = style({ display: "grid", gap: "8px" });
export const requestHead = style({ display: "flex", alignItems: "baseline", gap: "12px", flexWrap: "wrap" });
export const facts = style({
  display: "grid", gridTemplateColumns: "auto minmax(0, 1fr)", gap: "4px 14px", margin: "0", fontSize: vars.textUi, lineHeight: vars.leadingBody,
});
globalStyle(`${facts} dt`, { color: vars.muted });
globalStyle(`${facts} dd`, { margin: "0", overflowWrap: "anywhere" });
export const mono = style({ fontFamily: vars.fontMono, fontSize: "0.92em" });
export const link = style({ color: vars.accentText, textDecoration: "none", fontSize: vars.textUi, flex: "none" });

/** A row of a card's list (the devices). */
export const rows = style({ display: "grid", gap: "12px" });
export const row = style({ display: "flex", alignItems: "center", gap: "12px", fontSize: vars.textUi, minHeight: "30px" });
export const rowText = style({ flex: "1", minWidth: "0", display: "flex", alignItems: "baseline", gap: "6px 10px", flexWrap: "wrap" });
export const rowName = style({ fontWeight: "500", color: vars.text, fontSize: vars.textUi });
export const rowMeta = style({ color: vars.muted, fontSize: vars.textMeta });
export const warn = style({ color: vars.amber, fontSize: vars.textMeta });
/** An item's kind, before its name: as wide as the icon, quiet. */
export const rowIcon = style({ display: "grid", placeItems: "center", width: "16px", flex: "none", color: vars.muted, alignSelf: "flex-start", marginTop: "2px" });
/** A list's row that opens something: a button, drawn as the row. */
export const rowButton = style({
  width: "100%", border: "0", background: "none", color: "inherit", font: "inherit", textAlign: "left", cursor: "pointer",
  selectors: { "&:disabled": { cursor: "default" } },
});

/** An item opened: its fields, one over another. */
export const fields = style({ display: "grid", gap: "14px" });
export const fieldLabel = style({ fontSize: vars.textMeta, color: vars.muted, fontWeight: "500" });
export const secret = style({ display: "grid", gap: "4px", minWidth: "0" });
export const secretLine = style({ display: "flex", alignItems: "center", gap: "4px", minWidth: "0" });
export const secretValue = style({
  flex: "1", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontSize: vars.textUi,
  selectors: { "&[data-multiline]": { whiteSpace: "pre-wrap", overflowWrap: "anywhere", maxHeight: "160px", overflowY: "auto" } },
});
/** How agents may ask for it: the switch and what it opens, set apart. */
export const agentBox = style({ display: "grid", gap: "10px", paddingTop: "4px" });
export const area = style({ resize: "vertical", lineHeight: "1.5", fontFamily: vars.fontMono, fontSize: vars.textMeta });
