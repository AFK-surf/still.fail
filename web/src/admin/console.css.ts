import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

// The admin console. Only names are bold and only what is off is coloured; rows stand apart by spacing, with no rules.

const NARROW = "(max-width: 700px)";

export const accountEmail = style({
  fontSize: vars.textMeta, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const adminFoot = style({ padding: "8px" });
export const adminAccount = style({
  flex: "1", minWidth: "0", display: "flex", alignItems: "center", gap: "8px", padding: "0 6px",
});

// ── a list, and the item open beside it ──
export const split = style({
  flex: "1", minHeight: "0", display: "grid", gridTemplateColumns: "minmax(0, 1fr)",
  selectors: { "&[data-open]": { gridTemplateColumns: "minmax(0, 1fr) 380px" } },
  "@media": { [NARROW]: { selectors: { "&[data-open]": { gridTemplateColumns: "minmax(0, 1fr)" } } } },
});
export const listPage = style({
  "@media": { [NARROW]: { selectors: { [`${split}[data-open] &`]: { display: "none" } } } },
});
export const mid = style({});
globalStyle(`${mid} > *`, { maxWidth: "760px", marginLeft: "auto", marginRight: "auto" });
export const total = style({ marginLeft: "10px", fontSize: vars.textBody, fontWeight: "400", color: vars.subtle, fontVariantNumeric: "tabular-nums" });

export const toolbar = style({ display: "flex", gap: "12px", alignItems: "center" });
export const search = style({ position: "relative", flex: "1", minWidth: "0", display: "flex" });
globalStyle(`${search} > svg`, { position: "absolute", left: "12px", top: "50%", transform: "translateY(-50%)", color: vars.subtle, pointerEvents: "none" });
globalStyle(`${search} > input`, { paddingLeft: "36px", borderColor: "transparent", background: vars.neutralBg });
export const sort = style({ flex: "none", display: "flex", alignItems: "center", gap: "6px", fontSize: vars.textUi });
export const filters = style({ display: "flex", gap: "4px", flexWrap: "wrap", margin: "12px 0 16px" });
export const filter = style({
  height: "28px", padding: "0 10px", border: "0", borderRadius: "999px", background: "none", color: vars.muted,
  fontSize: vars.textUi, display: "inline-flex", alignItems: "center", gap: "6px", cursor: "pointer",
  transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.hover },
    "&[data-on]": { background: vars.selected, color: vars.text },
  },
});
globalStyle(`${filter} > span`, { fontSize: vars.textMeta, color: vars.subtle, fontVariantNumeric: "tabular-nums" });

export const list = style({ display: "grid", gap: "2px" });
export const empty = style({ margin: "24px 12px", fontSize: vars.textUi, color: vars.muted });
export const row = style({
  display: "flex", alignItems: "center", gap: "12px", minWidth: "0", padding: "8px 12px", borderRadius: vars.rNav,
  color: vars.text, cornerShape: vars.cornerShape, transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:not([data-static]):hover": { background: vars.hover },
    "&[aria-current=page]": { background: vars.selected },
  },
});
export const rowText = style({ flex: "1", minWidth: "0", display: "grid" });
export const rowLine1 = style({ display: "flex", alignItems: "center", gap: "8px", minWidth: "0", fontSize: vars.textUi, lineHeight: "22px" });
globalStyle(`${rowLine1} > b`, { fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const rowTime = style({
  marginLeft: "auto", flex: "none", display: "flex", alignItems: "center", gap: "6px", fontSize: vars.textMeta, color: vars.subtle, whiteSpace: "nowrap",
});
export const rowLine2 = style({ fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const code = style({ fontSize: vars.textBody, letterSpacing: ".04em" });
export const wsMark = style({
  flex: "none", width: "28px", height: "28px", display: "grid", placeItems: "center", borderRadius: "9px", background: vars.paper,
  fontSize: vars.textUi, fontWeight: "600", cornerShape: vars.cornerShape,
});
export const wsMarkLarge = style({ width: "40px", height: "40px", borderRadius: "12px", fontSize: vars.textTitle });
export const more = style({
  margin: "8px auto 0", height: "32px", padding: "0 14px", border: "0", borderRadius: "999px", background: "none",
  color: vars.muted, fontSize: vars.textMeta, cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover, color: vars.text } },
});

// ── an item's page ──
export const detail = style({
  minHeight: "0", overflowY: "auto", display: "flex", flexDirection: "column", gap: "2px", padding: "28px 24px 40px",
  background: vars.sidebar, fontSize: vars.textUi,
  "@media": { [NARROW]: { padding: "24px 18px 60px" } },
});
export const detailHead = style({ display: "flex", alignItems: "center", gap: "12px", marginBottom: "18px" });
export const detailTitle = style({ flex: "1", minWidth: "0", display: "grid" });
globalStyle(`${detailTitle} > b`, { fontSize: vars.textTitle, fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis" });
globalStyle(`${detailTitle} > span`, { fontSize: vars.textMeta, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const close = style({
  alignSelf: "flex-start", display: "grid", placeItems: "center", width: "28px", height: "28px", borderRadius: "50%", color: vars.muted,
  selectors: { "&:hover": { background: vars.hover, color: vars.text } },
  "@media": { [NARROW]: { display: "none" } },
});
export const kv = style({ display: "grid", gridTemplateColumns: "72px minmax(0, 1fr)", gap: "6px 12px", margin: "0 0 10px" });
globalStyle(`${kv} dt`, { color: vars.muted });
globalStyle(`${kv} dd`, { margin: "0", minWidth: "0", overflowWrap: "anywhere" });
export const group = style({ margin: "16px 0 4px", fontSize: vars.textMeta, color: vars.muted });
export const line = style({
  display: "flex", alignItems: "center", gap: "8px", minHeight: "36px", padding: "6px 12px", borderRadius: vars.rOption,
  background: vars.canvas, color: vars.text, cornerShape: vars.cornerShape,
  selectors: {
    "a&:hover": { background: vars.hover },
    "&[data-quiet]": { color: vars.muted },
  },
});
globalStyle(`${line} > svg`, { flex: "none", color: vars.subtle });
export const grow = style({ flex: "1", minWidth: "0", display: "grid", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const hint = style({ fontSize: vars.textMeta, color: vars.muted, whiteSpace: "normal" });
export const lineAside = style({ flex: "none", fontSize: vars.textMeta, color: vars.muted, whiteSpace: "nowrap" });
globalStyle(`${lineAside} [data-off]`, { color: vars.amber });
export const link = style({ color: vars.text, textDecoration: "underline", textDecorationColor: vars.lineStrong, textUnderlineOffset: "3px" });
export const actions = style({ display: "flex", flexWrap: "wrap", gap: "8px", marginTop: "20px" });
/** A command as wide as the dialog, scrolled within rather than spilling past it. */
export const command = style({ display: "grid", gridTemplateColumns: "minmax(0, 1fr)" });

// ── a bug report ──
export const fbNumber = style({ flex: "none", fontSize: vars.textMeta });
export const fbTitle = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const fbBar = style({ display: "flex", alignItems: "center", gap: "8px", flexWrap: "wrap", marginBottom: "14px" });
export const fbBody = style({ padding: "10px 12px", borderRadius: vars.rOption, background: vars.canvas, cornerShape: vars.cornerShape });
export const fbContext = style({ gridTemplateColumns: "minmax(72px, max-content) minmax(0, 1fr)", fontSize: vars.textMeta });
export const fbLogs = style({
  margin: "0", maxHeight: "360px", overflow: "auto", padding: "10px 12px", borderRadius: vars.rOption, background: vars.canvas,
  cornerShape: vars.cornerShape, fontSize: vars.textMeta, lineHeight: "18px", whiteSpace: "pre", tabSize: 4,
});

// ── the overview ──
export const stats = style({
  display: "grid", gridTemplateColumns: "repeat(4, minmax(0, 1fr))", gap: "8px", marginBottom: "8px",
  "@media": { [NARROW]: { gridTemplateColumns: "repeat(2, minmax(0, 1fr))" } },
});
export const stat = style({
  display: "grid", padding: "16px 18px", borderRadius: vars.rCard, background: vars.sidebar, color: vars.text, fontSize: vars.textMeta,
  cornerShape: vars.cornerShape, transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: { "&:hover": { background: vars.selected } },
});
export const statValue = style({ fontSize: vars.textDisplay, lineHeight: "40px", fontWeight: "600", fontVariantNumeric: "tabular-nums" });
export const statNote = style({ color: vars.subtle });
export const chart = style({ padding: "16px 18px 12px", borderRadius: vars.rCard, background: vars.sidebar, cornerShape: vars.cornerShape, marginBottom: "32px" });
export const chartHead = style({ display: "flex", alignItems: "baseline", gap: "8px", marginBottom: "12px", fontSize: vars.textUi });
globalStyle(`${chartHead} > b`, { fontWeight: "600" });
globalStyle(`${chartHead} > span`, { fontSize: vars.textMeta });
export const bars = style({ display: "grid", gridTemplateColumns: "repeat(12, minmax(0, 1fr))", gap: "8px", height: "150px" });
export const bar = style({ display: "flex", flexDirection: "column", justifyContent: "flex-end", alignItems: "stretch", minHeight: "0" });
export const barCount = style({ fontSize: vars.textMeta, color: vars.subtle, textAlign: "center", lineHeight: "18px", fontVariantNumeric: "tabular-nums" });
export const barFill = style({
  minHeight: "3px", borderRadius: "6px", background: vars.lineStrong,
  selectors: { "&[data-now]": { background: vars.accent } },
});
export const barLabel = style({ marginTop: "6px", fontSize: vars.textCaption, lineHeight: "14px", color: vars.subtle, textAlign: "center", whiteSpace: "nowrap", overflow: "hidden" });
export const h2 = style({ marginTop: "0", marginBottom: "8px", paddingLeft: "12px", fontSize: vars.textBody, fontWeight: "600" });
export const todo = style({
  display: "flex", alignItems: "center", gap: "12px", minHeight: "44px", padding: "0 12px", borderRadius: vars.rNav, color: vars.text,
  fontSize: vars.textUi, cornerShape: vars.cornerShape,
  selectors: { "&:hover": { background: vars.hover } },
});
globalStyle(`${todo} > svg`, { marginLeft: "auto", flex: "none", color: vars.subtle });
export const todoText = style({ fontWeight: "500" });
export const todoHint = style({ fontSize: vars.textMeta, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });

// ── the relays: a card each (pages.css.ts card), its numbers, its load over time ──
export const relays = style({});
/** None to show: under the title, on its line (only the bottom margin: the page's column centres it, mid). */
export const relaysNone = style({ marginTop: "0", marginBottom: "0", fontSize: vars.textUi, color: vars.muted });
export const relay = style({ gap: "18px" });
export const relayHead = style({ display: "flex", alignItems: "center", gap: "8px", minWidth: "0", fontSize: vars.textUi, lineHeight: "22px" });
globalStyle(`${relayHead} > b`, { fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const relaySeen = style({ marginLeft: "auto", flex: "none", fontSize: vars.textMeta, color: vars.subtle, whiteSpace: "nowrap" });
/** Its numbers side by side, as wide as each one's value, wrapping onto more lines where the card is narrow. */
export const relayNumbers = style({
  margin: "0", display: "flex", flexWrap: "wrap", gap: "12px 32px",
  "@media": { [NARROW]: { columnGap: "24px" } },
});
globalStyle(`${relayNumbers} dt`, { fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" });
globalStyle(`${relayNumbers} dd`, { margin: "0", fontSize: vars.textHeading, lineHeight: "30px", fontWeight: "600", whiteSpace: "nowrap" });
globalStyle(`${relayNumbers} dd[data-tone=amber]`, { color: vars.amber });
globalStyle(`${relayNumbers} dd[data-tone=red]`, { color: vars.red });

// A series' colour, by its place in the chart (the first blue, the second the accent), for its line, wash and key.
export const seriesFirst = style({ vars: { "--series": vars.blue } });
export const seriesSecond = style({ vars: { "--series": vars.accent } });
export const loadChart = style({ margin: "0", display: "grid", gap: "8px", minWidth: "0" });
export const loadHead = style({
  display: "flex", alignItems: "baseline", flexWrap: "wrap", gap: "4px 12px", fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted,
});
globalStyle(`${loadHead} > b`, { fontSize: vars.textUi, fontWeight: "500", color: vars.text });
/** A series' name, its colour only in the short line before it (words stay in the text's colours). */
export const legend = style({
  display: "inline-flex", alignItems: "center", gap: "6px", whiteSpace: "nowrap",
  selectors: { "&::before": { content: "''", width: "12px", height: "2px", borderRadius: "1px", background: "var(--series)" } },
});
export const peak = style({ marginLeft: "auto", color: vars.subtle, whiteSpace: "nowrap", fontVariantNumeric: "tabular-nums" });
export const plot = style({ height: "96px", minWidth: "0" });
globalStyle(`${plot} > svg`, { display: "block", width: "100%", height: "100%", overflow: "visible" });
globalStyle(`${plot} g`, { color: "var(--series)" });
/** The foot (0) and the top (the peak): hairlines. */
export const rule = style({ stroke: vars.line, strokeWidth: 1 });
export const wash = style({ fill: "currentColor", fillOpacity: 0.1, stroke: "none" });
export const trace = style({ fill: "none", stroke: "currentColor", strokeWidth: 2, strokeLinejoin: "round", strokeLinecap: "round" });
export const ticks = style({ position: "relative", height: "16px", fontSize: vars.textCaption, lineHeight: "16px", color: vars.subtle, fontVariantNumeric: "tabular-nums" });
globalStyle(`${ticks} > span`, { position: "absolute", top: "0", transform: "translateX(-50%)", whiteSpace: "nowrap" });
globalStyle(`${ticks} > span[data-edge=start]`, { transform: "none" });
globalStyle(`${ticks} > span[data-edge=end]`, { transform: "translateX(-100%)" });
