// Models by name, by series: the model control's list, and a profile's list of models to enable.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { mono, muted } from "./styles/shell.css.ts";
import { card } from "./styles/pages.css.ts";
import { quotaChips, quotaRingNumber } from "./components.css.ts";
import { newChat } from "./NewChat.css.ts";
import { runCardRow } from "./pages/Connect.css.ts";
import { input } from "./styles/controls.css.ts";
import { chooserChevron, modelPoolItem } from "./styles/chat.css.ts";
import { onboardingRow } from "./cloud/settings.css.ts";
import { sessionDetails } from "./pages/ChatPage.css.ts";
import { composerChoices } from "./Chat.css.ts";
import { spinner } from "./styles/waiting.css.ts";

/** A series of models in the control's list: its models one under another, each as wide as the list. */
export const series = style({ display: "flex", flexDirection: "column", gap: 1 });

/** A series in a profile's list of models to enable: its name, a toggle for all of it, its models under. */
export const poolSeries = style({ display: "grid", gap: 2, selectors: { "& + &": { marginTop: 10 } } });
export const poolSeriesHead = style({ display: "flex", alignItems: "center", gap: 10, padding: "0 8px" });
globalStyle(`${poolSeriesHead} h4`, { margin: 0, fontSize: vars.textMeta, fontWeight: 500, color: vars.muted });

export const runOptionText = style({ display: "grid", gap: "1px", flex: "1", minWidth: "0" });
/** The panel's lines: a tint of the text, seen in either theme (the page's line is lost on dark). */
const rule = `1px solid color-mix(in srgb, ${vars.text} 10%, transparent)`;
/** The panel: the filter across its top, the columns side by side under it with a line between, the foot under a line. */
export const runPickerPanel = style({ padding: "0", overflow: "hidden" });
export const runPickerAccountsPanel = style({ padding: "6px" });
export const runPickerSearch = style({
  display: "flex", alignItems: "center", gap: "8px", padding: "10px 14px", borderBottom: rule, color: vars.subtle,
  cursor: "text",
});
globalStyle(`${runPickerSearch} input`, {
  flex: "1", minWidth: "0", border: "0", outline: "none", background: "none", color: vars.text, font: "inherit", fontSize: vars.textUi,
});
globalStyle(`${runPickerSearch} input::placeholder`, { color: vars.subtle });
export const runPicker = style({ display: "flex", maxHeight: "360px" });
export const runPickerFoot = style({
  display: "flex", justifyContent: "flex-end", alignItems: "center", gap: "8px", padding: "8px 10px",
  borderTop: rule,
});
/** A column: only the models' scrolls (the others are short); each after the first has a line before it. */
export const runPickerColumn = style({
  display: "flex", flexDirection: "column", gap: "1px", minWidth: "120px", padding: "6px", overflowX: "hidden",
  selectors: { "& + &": { borderLeft: rule } },
});
/** What is picked: a mark at its row's end (none on the others). */
export const runCheck = style({ marginLeft: "auto", flex: "none", color: vars.accent, visibility: "hidden" });
/** The accounts, in a panel beside the model control's. */
export const runPickerAccounts = style({
  display: "flex", flexDirection: "column", gap: "1px", minWidth: "220px", maxWidth: "320px", maxHeight: "420px", overflowY: "auto",
});
globalStyle(`${runPickerAccounts} h4`, { margin: "4px 8px 6px", fontSize: vars.textMeta, lineHeight: "18px", fontWeight: "500", color: vars.muted });
/** Under an account's name: what is left of it, gray unless running low. */
export const runAccountNote = style({
  overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontSize: vars.textMeta, fontWeight: 400, color: vars.muted,
  selectors: { "&[data-level=amber]": { color: vars.amber }, "&[data-level=red]": { color: vars.red } },
});
/** The room the foot's line has: what the columns leave beside the buttons, never more. */
export const runPickerWhoRoom = style({ flex: "1 1 0", width: 0, minWidth: 0, display: "flex" });
/** The foot's line that says who runs it, and opens the accounts. */
export const runPickerWho = style({
  display: "inline-flex", alignItems: "center", gap: "4px", minWidth: 0, maxWidth: "100%", height: "28px", padding: "0 8px",
  border: 0, borderRadius: `calc(6px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: "none",
  color: vars.muted, font: "inherit", fontSize: vars.textMeta, cursor: "pointer",
  selectors: {
    "&:hover, &[data-state=open]": { background: vars.hover, color: vars.text },
    "&[data-level=amber]": { color: vars.amber }, "&[data-level=red]": { color: vars.red },
  },
});
export const runPickerWhoLead = style({ flex: "none", color: vars.subtle });
globalStyle(`${runPickerWho}:not([data-level]) > ${runPickerWhoLead} + *`, { color: vars.text, fontWeight: "500" });
export const runPickerWhoChevron = style({
  flex: "none",
});
export const runPickerEfforts = style({ minWidth: "136px" });
export const runPickerOption = style({
  display: "flex", alignItems: "center", gap: "6px", minHeight: "30px", padding: "4px 8px", border: "0",
  borderRadius: `calc(6px * ${vars.cornerScale})`, background: "none", color: vars.text, font: "inherit",
  fontSize: vars.textUi, textAlign: "left", cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover },
    "&[aria-pressed=\"true\"]": { background: vars.hover, fontWeight: "500" },
  },
});
globalStyle(`${runPickerOption}[aria-pressed="true"] > ${runCheck}, ${runPickerOption}[aria-pressed="true"] ${runCheck}`, { visibility: "visible" });
export const runPickerNote = style({ margin: "0 8px 6px", fontSize: vars.textMeta, color: vars.amber });
export const btnSm = style({ height: "28px", padding: "0 12px", fontSize: vars.textUi });
export const modelTriple = style({
  display: "inline-flex", alignItems: "center", gap: "6px", maxWidth: "100%", justifySelf: "start", alignSelf: "start",
  width: "max-content", height: "30px", padding: "0 10px", border: "1px solid transparent",
  borderRadius: `calc(9px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: "none", color: vars.text,
  font: "inherit", fontSize: vars.textUi, lineHeight: "20px", cursor: "pointer", whiteSpace: "nowrap", overflow: "hidden",
  selectors: {
    "&:hover": { background: vars.hover },
    "&[data-state=\"open\"]": { background: vars.hover },
    "&:disabled": { color: vars.muted, cursor: "default" },
    [`${newChat} &`]: { height: "28px", fontSize: vars.textMeta },
  },
});
/**
 * The model control within the room it has (ModelTriple measures it): data-drop says what it leaves out. The model is
 * never left out nor cut short.
 */
export const modelTripleFit = style({
  display: "block", flex: "1 1 auto", minWidth: "0", maxWidth: "100%",
  selectors: {
    // In a row of a list, a ring's mark sits beside it, so the ring is on the row's line.
    // Where it heads text, the control's text lines up with the text under it (its border and padding stand out).
    [`:is(${sessionDetails}, ${card}) > &`]: { marginLeft: "-11px" },
  },
});
export const tripleModel = style({
  selectors: {
    [`${modelTriple} &`]: { display: "inline-flex", alignItems: "center", gap: "6px", flex: "none" },
  },
});
export const triplePart = style({
  selectors: {
    [`${modelTriple} &`]: { display: "inline-flex", alignItems: "center", gap: "5px", flex: "none" },
    [`${modelTriple} &::before`]: { content: "\"·\"", color: vars.muted, marginRight: "1px" },
  },
});
export const tripleAccountShort = style({
  selectors: {
    [`${modelTriple} &`]: { display: "none" },
    [`${modelTriple}[data-drop~="name"] &`]: { display: "inline" },
  },
});
export const tripleRings = style({
  selectors: {
    [`${modelTriple} &`]: { display: "inline-flex", alignItems: "center" },
  },
});
export const tripleAccountName = style({
  selectors: {
    [`${modelTriple}[data-drop~="name"] &`]: { display: "none" },
  },
});
export const tripleAccount = style({
  selectors: {
    [`${modelTriple}[data-drop~="account"] &`]: { display: "none" },
    [`${modelTriple} &[data-level=amber]`]: { color: vars.amber },
    [`${modelTriple} &[data-level=red]`]: { color: vars.red },
  },
});
export const tripleRuntime = style({
  selectors: {
    [`${modelTriple}[data-drop~="runtime"] &`]: { display: "none" },
  },
});
export const tripleEffort = style({
  selectors: {
    [`${modelTriple}[data-drop~="effort"] &`]: { display: "none" },
  },
});
export const runPickerSpent = style({ fontSize: vars.textMeta, color: vars.amber });
/** As wide as its models when the panel opens, within bounds (100–280px); a filter then leaves it as it is (ModelTriple keeps it). */
export const runPickerModels = style({ minWidth: "200px", maxWidth: "300px", flex: "1 1 auto", overflowY: "auto" });
/** A model's name too long for the column is cut short. */
export const runOptionName = style({ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const runPickerGroup = style({});
export const runPickerEmpty = style({ margin: "4px 8px", fontSize: vars.textMeta });
globalStyle(`${runOptionText} ${muted}`, { fontSize: vars.textMeta, whiteSpace: "normal", maxWidth: "260px" });
globalStyle(`${runPickerColumn} h4`, { margin: "4px 8px 6px", fontSize: vars.textMeta, lineHeight: "18px", fontWeight: "500", color: vars.muted });
globalStyle(`${runPickerOption} ${quotaChips}`, { marginLeft: "auto", paddingLeft: "12px" });
/** The model control takes the room left beside the other choices, and fits itself in it (.model-triple-fit). */
globalStyle(`${composerChoices} > :not(${modelTripleFit})`, { flex: "none" });
/** Here rather than with its class: it comes after .run-option-text .muted, and wins over it. */
globalStyle(`${modelPoolItem} ${mono}`, { minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${modelTriple} ${quotaChips}`, { marginLeft: "2px" });
globalStyle(`${modelTriple} ${chooserChevron}`, { color: vars.muted, flex: "none" });
globalStyle(`${modelTriple} ${quotaRingNumber}`, { display: "none" });
globalStyle(`${runPickerGroup} h5`, { margin: "8px 8px 2px", fontSize: vars.textMeta, lineHeight: "18px", fontWeight: "500", color: vars.subtle });
/** Here rather than with its class: it comes after .composer-choices > :not(.model-triple-fit), and wins over it. */
globalStyle(`${runCardRow} > ${modelTripleFit}`, { flex: "1 1 auto", marginTop: "-5px" });
/** Here rather than with its class: it comes after .composer-choices > :not(.model-triple-fit), and wins over it. */
globalStyle(`${onboardingRow} ${input}`, { flex: "1", minWidth: "0" });

/** A pick on its way (pick.save): a small ring where the chevron goes. */
export const tripleSpinner = style({});
globalStyle(`${tripleSpinner}${spinner}`, { width: "12px", height: "12px", borderWidth: "1.5px" });
