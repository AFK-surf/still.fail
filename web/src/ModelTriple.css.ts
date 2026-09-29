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

/** A series of models in the control's list: its models one under another, each as wide as the list. */
export const series = style({ display: "flex", flexDirection: "column", gap: 1 });

/** A series in a profile's list of models to enable: its name, a toggle for all of it, its models under. */
export const poolSeries = style({ display: "grid", gap: 2, selectors: { "& + &": { marginTop: 10 } } });
export const poolSeriesHead = style({ display: "flex", alignItems: "center", gap: 10, padding: "0 8px" });
globalStyle(`${poolSeriesHead} h4`, { margin: 0, fontSize: vars.textXs, fontWeight: 500, color: vars.muted });

export const runOptionText = style({ display: "grid", gap: "1px", flex: "1", minWidth: "0" });
export const runPickerPanel = style({ padding: "6px" });
export const runPicker = style({ display: "flex", gap: "4px", maxHeight: "420px" });
export const runPickerFoot = style({
  display: "flex", justifyContent: "flex-end", gap: "6px", marginTop: "6px", padding: "8px 4px 2px",
});
export const runPickerColumn = style({
  display: "flex", flexDirection: "column", gap: "1px", minWidth: "110px", overflowY: "auto",
});
export const runPickerAccounts = style({ minWidth: "260px" });
export const runPickerEfforts = style({ minWidth: "80px" });
export const runPickerOption = style({
  display: "flex", alignItems: "center", gap: "6px", minHeight: "30px", padding: "4px 8px", border: "0",
  borderRadius: `calc(6px * ${vars.cornerScale})`, background: "none", color: vars.text, font: "inherit",
  fontSize: vars.textSm, textAlign: "left", cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover },
    "&[aria-pressed=\"true\"]": { background: vars.hover, fontWeight: "600" },
  },
});
export const runPickerNote = style({ margin: "0 8px 6px", maxWidth: "240px", fontSize: vars.textXs, color: vars.amber });
export const btnSm = style({ height: "28px", padding: "0 10px", fontSize: vars.textXs });
export const modelTriple = style({
  display: "inline-flex", alignItems: "center", gap: "6px", maxWidth: "100%", justifySelf: "start", alignSelf: "start",
  width: "max-content", height: "30px", padding: "0 10px", border: "1px solid transparent",
  borderRadius: `calc(9px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: "none", color: vars.text,
  font: "inherit", fontSize: vars.textSm, lineHeight: "20px", cursor: "pointer", whiteSpace: "nowrap", overflow: "hidden",
  selectors: {
    "&:hover": { background: vars.hover },
    "&[data-state=\"open\"]": { background: vars.hover },
    "&:disabled": { color: vars.muted, cursor: "default" },
    [`${newChat} &`]: { height: "28px", fontSize: vars.textXs },
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
export const runPickerSpent = style({ fontSize: vars.textXs, color: vars.amber });
/** As wide as its models when the panel opens, within bounds (100–280px); a filter then leaves it as it is (ModelTriple keeps it). */
export const runPickerModels = style({ minWidth: "100px", maxWidth: "280px", flex: "none" });
/** A model's name too long for the column is cut short. */
export const runOptionName = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const runPickerFilter = style({ height: "30px", margin: "0 4px 6px", fontSize: vars.textSm });
export const runPickerGroup = style({});
export const runPickerEmpty = style({ margin: "4px 8px", fontSize: vars.textXs });
globalStyle(`${runOptionText} ${muted}`, { fontSize: vars.textXs, whiteSpace: "normal", maxWidth: "260px" });
globalStyle(`${runPickerColumn} h4`, { margin: "4px 8px 6px", fontSize: vars.textXs, lineHeight: "18px", fontWeight: "500", color: vars.muted });
globalStyle(`${runPickerOption} ${quotaChips}`, { marginLeft: "auto", paddingLeft: "12px" });
/** The model control takes the room left beside the other choices, and fits itself in it (.model-triple-fit). */
globalStyle(`${composerChoices} > :not(${modelTripleFit})`, { flex: "none" });
/** Here rather than with its class: it comes after .run-option-text .muted, and wins over it. */
globalStyle(`${modelPoolItem} ${mono}`, { minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${modelTriple} ${quotaChips}`, { marginLeft: "2px" });
globalStyle(`${modelTriple} ${chooserChevron}`, { color: vars.muted, flex: "none" });
globalStyle(`${modelTriple} ${quotaRingNumber}`, { display: "none" });
globalStyle(`${runPickerGroup} h5`, { margin: "8px 8px 2px", fontSize: vars.textXs, lineHeight: "18px", fontWeight: "500", color: vars.subtle });
/** Here rather than with its class: it comes after .composer-choices > :not(.model-triple-fit), and wins over it. */
globalStyle(`${runCardRow} > ${modelTripleFit}`, { flex: "1 1 auto", marginTop: "-5px" });
/** Here rather than with its class: it comes after .composer-choices > :not(.model-triple-fit), and wins over it. */
globalStyle(`${onboardingRow} ${input}`, { flex: "1", minWidth: "0" });
