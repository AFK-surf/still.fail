import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

// 设置 › 密钥 on a narrow screen (Vault.tsx): the settings' cards and rows (parts.css.ts), what is the vault's own here.
/** A link's button on its own line in a card, at the start of it. */
export const mStart = style({ justifySelf: "start" });
export const mMono = style({ fontFamily: vars.fontMono, fontSize: "0.9em" });

/** The recovery words: numbered, three columns. */
export const mWords = style({
  display: "grid", gridTemplateColumns: "repeat(3, minmax(0, 1fr))", gap: "10px 8px", margin: "0", padding: "4px 0",
  listStyle: "none", fontFamily: vars.fontMono, fontSize: vars.textUi,
});
globalStyle(`${mWords} li`, { display: "flex", alignItems: "baseline", gap: "6px", minWidth: "0" });
export const mWordN = style({ minWidth: "1.4em", textAlign: "right", fontSize: vars.textCaption, color: "var(--m-subtle)", fontVariantNumeric: "tabular-nums" });

/** A request waiting: its card, then its approval's rows on the page under it. */
export const mRequest = style({ display: "grid", marginBottom: "12px" });
export const mChoices = style({ padding: "0 12px" });
globalStyle(`${mChoices} > div`, { width: "100%", minWidth: "0", marginTop: "0" });
globalStyle(`${mChoices} > p`, { padding: "0 4px" });
export const mFacts = style({ display: "grid", gridTemplateColumns: "auto minmax(0, 1fr)", gap: "4px 12px", margin: "0", fontSize: vars.textUi });
globalStyle(`${mFacts} dt`, { color: "var(--m-subtle)" });
globalStyle(`${mFacts} dd`, { margin: "0", overflowWrap: "anywhere" });

/** An item's kind, before its name: as wide as the icon, quiet. */
export const mIcon = style({ display: "grid", placeItems: "center", width: "18px", flex: "none", color: "var(--m-subtle)" });

/** A sheet's body: a column of labels and fields, its buttons last. */
export const mSheetBody = style({ display: "flex", flexDirection: "column", gap: "8px", padding: "4px 20px 24px", overflowY: "auto", flex: "1", minHeight: "0" });
export const mLabel = style({ fontSize: vars.textMeta, color: "var(--m-muted)", fontWeight: "500", marginTop: "4px" });
export const mArea = style({ resize: "vertical", lineHeight: "1.5", fontSize: vars.textMeta });
export const mTools = style({ display: "flex", alignItems: "center", gap: "8px", paddingTop: "8px" });
/** An item's field opened: its label over its value and the buttons that show and copy it. */
export const mSecret = style({ display: "grid", gap: "2px", minWidth: "0", paddingTop: "6px", color: "var(--m-ink)" });
export const mSecretLine = style({ display: "flex", alignItems: "center", gap: "2px", minWidth: "0", color: "var(--m-muted)" });
export const mSecretValue = style({
  flex: "1", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontSize: vars.textUi, color: "var(--m-ink)",
  selectors: { "&[data-multiline]": { whiteSpace: "pre-wrap", overflowWrap: "anywhere", maxHeight: "180px", overflowY: "auto" } },
});
export const mIconButton = style({
  display: "grid", placeItems: "center", width: "36px", height: "36px", flex: "none", border: "0", borderRadius: "50%", background: "none", cursor: "pointer",
  selectors: { '&[aria-pressed="true"]': { background: "var(--m-chip)" } },
});
