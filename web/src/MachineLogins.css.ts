import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { pillInner, surfaceCorner, TEXT_IN, PANEL_PILL } from "@stillfail/ui/styles/align.ts";
import { DIALOG_INNER } from "@stillfail/ui/parts.css.ts";

// A station's logins (MachineLogins.tsx, docs/remote-login.md): its page's 登录 list, the login panel (a dialog; the
// phone's sheet) and a chat's login card. Grey but for what is off.

const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;

// ── the station page's list ──

/** A service's row, as the page's software rows (not pressed: no ground on hover). */
export const row = style({ selectors: { "&:hover": { background: "none" } } });
export const mark = style({ width: "36px", height: "36px", color: vars.muted });
export const name = style({ fontWeight: "500", color: vars.text, ...ellipsis });
export const state = style({ color: vars.muted, ...ellipsis });
/** The last row: a command of one's own to run, a row to press until it is opened into a field. */
export const commandRow = style({ width: "100%", border: "0", background: "none", color: vars.text, font: "inherit", textAlign: "left", cursor: "pointer" });
export const commandLabel = style({ flex: "1", minWidth: 0, color: vars.muted });
export const commandForm = style({ flex: "1", minWidth: 0, display: "flex", alignItems: "center", gap: "8px" });
export const commandField = style({ flex: "1", minWidth: 0, fontFamily: vars.fontMono });
export const note = style({ margin: "0", fontSize: vars.textUi, color: vars.muted });

// ── the panel ──

export const body = style({ display: "grid", gap: "14px", minWidth: 0 });
export const line = style({ margin: "0", fontSize: vars.textUi, lineHeight: "20px", overflowWrap: "anywhere" });
export const quiet = style([line, { color: vars.muted }]);
export const failed = style([line, { color: vars.red, fontWeight: "500" }]);
export const done = style([line, { fontWeight: "500" }]);
/** What is done about it: its buttons side by side. */
export const actions = style({ display: "flex", flexWrap: "wrap", alignItems: "center", gap: "8px" });
/** A step: what to do, its code large where there is one, its buttons, a quiet line after. */
export const step = style({ display: "grid", justifyItems: "start", gap: "10px", minWidth: 0 });
export const code = style({
  fontFamily: vars.fontMono, fontSize: vars.textHeading, fontWeight: "600", letterSpacing: "0.08em", lineHeight: "1.3",
  userSelect: "all",
});
export const waitingLine = style([quiet, { display: "inline-flex", alignItems: "center", gap: "8px" }]);

/** The terminal: a line that opens it (what it waits for after it), then its screen, a field and its keys. */
export const terminal = style({ display: "grid", gap: "10px", minWidth: 0 });
export const terminalToggle = style({
  display: "inline-flex", alignItems: "center", gap: "6px", justifySelf: "start", padding: "0", border: "0", background: "none",
  color: vars.text, font: "inherit", fontSize: vars.textUi, fontWeight: "500", cursor: "pointer",
});
export const terminalWaits = style({ color: vars.accentText, fontWeight: "400" });
export const chevron = style({ color: vars.muted, transition: `transform ${vars.dur} ${vars.easeOut}`, selectors: { "&[data-open]": { transform: "rotate(90deg)" } } });
/** Its screen: the station's lines in monospace, wrapped to the width (they come 200 columns wide), the cursor a block. */
export const screen = style({
  margin: "0", padding: "12px 14px", minHeight: "96px", maxHeight: "260px", overflowY: "auto", boxSizing: "border-box",
  borderRadius: DIALOG_INNER, cornerShape: vars.cornerShape, background: `var(--m-chip, color-mix(in srgb, ${vars.text} 6%, transparent))`, color: vars.text,
  fontFamily: vars.fontMono, fontSize: vars.textMeta, lineHeight: "1.5", whiteSpace: "pre-wrap", overflowWrap: "anywhere",
});
export const screenRow = style({ minHeight: "1.5em" });
export const cursor = style({ background: vars.text, color: vars.canvas });
/** The command's last lines, as the screen is drawn. */
export const lastLines = style([screen, { minHeight: "0" }]);
export const typing = style({ display: "flex", alignItems: "center", gap: "8px", minWidth: 0 });
export const typingField = style({ flex: "1", minWidth: 0, fontFamily: vars.fontMono });
export const keys = style({ display: "flex", flexWrap: "wrap", gap: "6px" });
/** The dialog's foot: where the login is and who uses it, on the buttons' left. */
export const foot = style({ flex: "1", minWidth: 0, margin: "0", fontSize: vars.textMeta, color: vars.muted });
/** The phone's sheet: its words in from its edges as its other sheets' are. */
export const sheetBody = style({ padding: "0 20px 24px" });
export const sheetFoot = style({ margin: "16px 0 0", fontSize: vars.textMeta, color: vars.muted });

/** The phone's station page: a service's name over how it stands. */
export const phoneRowText = style({ flex: "1", minWidth: 0, display: "grid", gap: "2px" });
export const phoneState = style({ fontSize: vars.textMeta, color: "var(--m-muted)", ...ellipsis });
export const phoneLead = style({ margin: "8px 24px 0", fontSize: vars.textCaption, color: "var(--m-muted)" });

// ── a chat's card ──

/** Where the card's buttons stand from its edges: they sit at its corner, its corner theirs and this together. */
const CARD_PAD = 8;
/**
 * A login in a chat, under the agent's message as a decision's options are: the same grey ground and no line, its
 * title and how it stands, then its buttons (small pills) along its foot. Pressed anywhere else, the panel opens.
 */
export const card = style({
  padding: CARD_PAD, borderRadius: surfaceCorner(CARD_PAD, pillInner(CARD_PAD, PANEL_PILL, vars.cornerScale)), cornerShape: vars.cornerShape,
  display: "grid", justifyItems: "start", gap: "2px", width: "fit-content", minWidth: "min(100%, 360px)", maxWidth: "100%",
  boxSizing: "border-box", marginTop: "8px", background: `var(--m-chip, color-mix(in srgb, ${vars.text} 5%, transparent))`,
  color: vars.text, textAlign: "left", cursor: "pointer", WebkitTapHighlightColor: "transparent",
  transition: `background-color ${vars.dur}`,
  selectors: { "&:hover": { background: `var(--m-chip, color-mix(in srgb, ${vars.text} 8%, transparent))` } },
});
/** Its words in by a row's padding (as a small panel's), and as far from its top and foot when first or last. */
const cardText = {
  paddingInline: TEXT_IN, maxWidth: "100%", boxSizing: "border-box", overflowWrap: "anywhere",
  selectors: { "&:first-child": { paddingTop: TEXT_IN }, "&:last-child": { paddingBottom: TEXT_IN } },
} as const;
export const cardTitle = style({ ...cardText, fontSize: vars.textUi, lineHeight: "20px", fontWeight: "500" });
export const cardStatus = style({ ...cardText, fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted });
export const cardActions = style({ display: "flex", flexWrap: "wrap", gap: "4px", marginTop: "6px" });
/** A button's words, sized here: the phone's buttons take their font from what they are in. */
export const cardButtonText = style({ fontSize: vars.textMeta, fontWeight: "500", lineHeight: `${PANEL_PILL}px` });
globalStyle(`${card} :focus-visible`, { outlineOffset: "-2px" });
