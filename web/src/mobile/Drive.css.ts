import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { m } from "./styles/root.css.ts";

/** How many folders and files, over the list: a small grey line. */
export const mCount = style({ margin: "2px 0 8px", padding: "0 28px", fontSize: vars.textMeta, color: "var(--m-muted)" });

/** An entry: its mark, its name, its size and time under it; held, it darkens as a pressed row does. */
export const mRow = style({
  display: "flex", alignItems: "center", gap: "14px", boxSizing: "border-box", width: "100%", minHeight: "60px", padding: "10px 16px",
  border: "0", background: "none", color: "var(--m-ink)", textAlign: "left", cursor: "pointer",
  WebkitTouchCallout: "none", userSelect: "none", WebkitUserSelect: "none",
  transition: "background 120ms",
  selectors: {
    "&[data-held], &:active:not(:disabled):not([data-upload])": { background: "color-mix(in srgb, var(--m-ink) 6%, transparent)" },
    "&:disabled": { color: "var(--m-ink)", cursor: "default", opacity: ".6" },
    "&[data-upload]": { cursor: "default" },
  },
});
export const mIcon = style({ flex: "none", color: "var(--m-muted)" });
export const mText = style({ flex: "1", minWidth: "0", display: "flex", flexDirection: "column", gap: "1px" });
export const mName = style({ fontSize: vars.textBody, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const mMeta = style({ fontSize: vars.textMeta, color: "var(--m-muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** A folder lent that cannot be browsed now: why, in red, and what to do about it. */
export const mTrouble = style({ marginTop: "3px", fontSize: vars.textMeta, color: "var(--m-muted)", lineHeight: "1.4" });
globalStyle(`${mTrouble} b`, { display: "block", color: "var(--m-red)", fontWeight: "500" });

export const mBarButtons = style({ display: "flex", alignItems: "center", gap: "2px" });
const turn = keyframes({ to: { transform: "rotate(360deg)" } });
/** Refresh turns while the folder is read again. */
export const mSpin = style({ display: "contents" });
globalStyle(`${mSpin}[data-on] svg`, { animation: `${turn} 900ms linear infinite` });

export const mProblem = style({ display: "grid", justifyItems: "center", gap: "10px", padding: "48px 32px", textAlign: "center" });

/** The path under the root, each folder of it a tap back to: a row that scrolls sideways, its end in view. */
export const mCrumbs = style({
  display: "flex", alignItems: "center", gap: "2px", overflowX: "auto", scrollbarWidth: "none", padding: "0 20px 6px",
  whiteSpace: "nowrap", fontSize: vars.textMeta, color: "var(--m-muted)",
});
export const mCrumb = style({ display: "inline-flex", alignItems: "center", gap: "2px" });
globalStyle(`${m} ${mCrumbs} button`, { padding: "4px 4px", border: "0", background: "none", color: "var(--m-muted)", fontSize: vars.textMeta, cursor: "pointer" });
globalStyle(`${mCrumbs} b`, { padding: "4px 4px", fontWeight: "500", color: "var(--m-ink)" });

/** Its name taken there: replace it, or keep both. */
export const mUploadAsk = style({ display: "flex", alignItems: "center", gap: "12px", fontSize: vars.textMeta, color: "var(--m-muted)", flexWrap: "wrap" });
globalStyle(`${m} ${mUploadAsk} button`, { padding: "2px 0", border: "0", background: "none", color: "var(--m-accent)", fontSize: vars.textMeta, fontWeight: "500", cursor: "pointer" });
/** How far it has got: a hairline in the accent. */
export const mProgress = style({
  position: "relative", display: "block", height: "2px", marginTop: "6px", borderRadius: "1px", overflow: "hidden",
  background: "color-mix(in srgb, var(--m-ink) 10%, transparent)",
});
globalStyle(`${mProgress} > span`, { position: "absolute", inset: "0", background: "var(--m-accent)", transformOrigin: "left", transition: "transform 200ms linear" });
export const mRowButton = style({
  display: "grid", placeItems: "center", flex: "none", width: "32px", height: "32px", padding: "0", border: "0", borderRadius: "50%",
  background: "none", color: "var(--m-muted)", cursor: "pointer",
});

export const mEmpty = style({ display: "grid", justifyItems: "center", gap: "14px", padding: "56px 40px 24px", textAlign: "center", color: "var(--m-muted)", fontSize: vars.textUi });

export const mSheetNote = style({ padding: "0 20px 10px" });
/** The way there, its words in line with the rows' marks below (each crumb's button has 4 px of its own). */
export const mPickerCrumbs = style({ padding: "0 16px 8px" });
/** A folder the station may not read, opened: why, and where to let it. */
export const mPickerShut = style({ display: "grid", justifyItems: "center", gap: "12px", padding: "40px 32px", textAlign: "center", color: "var(--m-muted)", fontSize: vars.textUi, lineHeight: "1.5" });
/** The filter's field, a ✕ at its end once something is typed. */
export const filter = style({ position: "relative", display: "block" });
export const filterClear = style({
  position: "absolute", right: "6px", top: "50%", transform: "translateY(-50%)", display: "grid", placeItems: "center", width: "28px", height: "28px",
  padding: "0", border: "0", borderRadius: "50%", background: "color-mix(in srgb, currentColor 10%, transparent)", color: "inherit", cursor: "pointer",
});
globalStyle(`${filter} input`, { paddingRight: "40px" });
export const mPickerFilter = style({ padding: "0 16px 8px" });
export const mPickerFoot = style({ display: "flex", gap: "10px", justifyContent: "flex-end", padding: "10px 16px calc(var(--m-foot) + 12px)" });

/** A file opened: the page is the reader's or the player's own. */
export const mReaderPage = style({ background: "transparent" });
export const mPlayerPage = style({ background: "#000" });
